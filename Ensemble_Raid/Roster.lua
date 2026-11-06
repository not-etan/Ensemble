-- Ensemble Raid (test build) / Roster.lua
-- Who's in the raid: the live raid or party when you're in a group, else the planner list
-- (players you add by hand to plan ahead). Class and role come from the roster; specs from your
-- own spec, then a slow inspect queue (one player every 2 seconds, out of combat).

local _, R = ...
if R.disabled then return end
local ns = R.ns
local UD = ns.UD

local Roster = {}
R.Roster = Roster

Roster.specByGUID = {}
Roster.INSPECT_EVERY = 2

local function ShortName(name)
  if type(name) ~= "string" then return nil end
  local short = name:match("^([^%-]+)") or name
  return short
end
Roster.ShortName = ShortName

function Roster:Source()
  if IsInGroup and IsInGroup() then return "live" end
  return "planner"
end

local function RoleOf(unit, fallback)
  local role = UnitGroupRolesAssigned and R.Plain(UnitGroupRolesAssigned(unit))
  if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return role end
  if fallback == "TANK" or fallback == "HEALER" or fallback == "DAMAGER" then return fallback end
  return nil
end

local function SpecFor(unit, guid)
  if UnitIsUnit and UnitIsUnit(unit, "player") then return ns.API.GetPlayerSpecID() end
  return guid and Roster.specByGUID[guid] or nil
end

local function Finish(m)
  local p = m.spec and UD:GetSpec(m.spec)
  if p then
    m.role = m.role or p.role
    m.range = p.range
  else
    m.pending = true
  end
  return m
end

-- The members: { name, full, class, spec, role, group, unit, pending, range }.
function Roster:Members()
  local out = {}
  if self:Source() == "planner" then
    for i, pm in ipairs(R.db.planner.members) do
      local name = pm.name or (pm.spec and UD:SpecName(pm.spec) .. " " .. i) or (UD:ClassName(pm.class) .. " " .. i)
      out[#out + 1] = Finish({ name = name, full = name, class = pm.class, spec = pm.spec, role = pm.role,
                               group = math.floor((i - 1) / 5) + 1, planner = i })
    end
    return out
  end
  if IsInRaid and IsInRaid() then
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, n do
      local unit = "raid" .. i
      local name, subgroup, fileName, combatRole
      if GetRaidRosterInfo then
        local ok, nm, _, sg, _, _, fn, _, _, _, _, _, cr = pcall(GetRaidRosterInfo, i)
        if ok then name, subgroup, fileName, combatRole = R.Plain(nm), R.Plain(sg), R.Plain(fn), R.Plain(cr) end
      end
      if not fileName and UnitClass then fileName = R.Plain(select(2, UnitClass(unit))) end
      if name or fileName then
        local guid = UnitGUID and R.Plain(UnitGUID(unit))
        out[#out + 1] = Finish({ name = ShortName(name) or "?", full = name or "?", class = fileName, unit = unit, guid = guid,
                                 group = tonumber(subgroup) or 1, role = RoleOf(unit, combatRole), spec = SpecFor(unit, guid) })
      end
    end
    return out
  end
  local units = { "player", "party1", "party2", "party3", "party4" }
  for _, unit in ipairs(units) do
    if UnitExists and UnitExists(unit) then
      local name = UnitName and R.Plain((UnitName(unit)))
      local cls = UnitClass and R.Plain(select(2, UnitClass(unit)))
      local guid = UnitGUID and R.Plain(UnitGUID(unit))
      out[#out + 1] = Finish({ name = name or "?", full = name or "?", class = cls, unit = unit, guid = guid, group = 1,
                               role = RoleOf(unit), spec = SpecFor(unit, guid) })
    end
  end
  return out
end

-- The analysis profile for a member: their spec, else what every spec of the class brings.
function Roster:Profile(m)
  if m.spec then return UD:GetSpec(m.spec) end
  return m.class and UD:ClassCommonProfile(m.class) or nil
end

function Roster:Counts(members)
  local c = { total = #members, TANK = 0, HEALER = 0, DAMAGER = 0, known = 0, melee = 0, ranged = 0, groups = 0 }
  for _, m in ipairs(members) do
    if m.role and c[m.role] then c[m.role] = c[m.role] + 1 end
    if m.spec then c.known = c.known + 1 end
    if m.range == "melee" then c.melee = c.melee + 1 elseif m.range == "ranged" then c.ranged = c.ranged + 1 end
    if (m.group or 1) > c.groups then c.groups = m.group or 1 end
  end
  return c
end

---------------------------------------------------------------------------
-- The planner list (plan ahead without a group)
---------------------------------------------------------------------------
Roster.PLANNER_MAX = 40
function Roster:AddPlanned(specID, name)
  local p = UD:GetSpec(specID)
  if not p then return false end
  local list = R.db.planner.members
  if #list >= self.PLANNER_MAX then return false end
  name = ns.Util.Trim(name or "")
  list[#list + 1] = { class = p.class, spec = specID, role = p.role, name = name ~= "" and name or nil }
  R:Fire("ROSTER_CHANGED")
  return true
end
function Roster:RemovePlanned(i)
  if R.db.planner.members[i] then table.remove(R.db.planner.members, i); R:Fire("ROSTER_CHANGED") end
end
function Roster:MovePlanned(i, delta)
  local list = R.db.planner.members
  local j = i + delta
  if list[i] and list[j] then list[i], list[j] = list[j], list[i]; R:Fire("ROSTER_CHANGED") end
end
function Roster:ClearPlanned()
  R.db.planner.members = {}
  R:Fire("ROSTER_CHANGED")
end
-- Copy the live group into the planner (names and specs), to plan the next night ahead.
function Roster:CopyLiveToPlanner(members)
  local list = {}
  for _, m in ipairs(members) do
    if m.class and #list < self.PLANNER_MAX then
      list[#list + 1] = { class = m.class, spec = m.spec, role = m.role, name = m.full ~= "?" and m.full or nil }
    end
  end
  R.db.planner.members = list
  R:Fire("ROSTER_CHANGED")
  return #list
end

---------------------------------------------------------------------------
-- Inspect queue: specs of other players, slowly, never in combat or over your own Inspect window.
---------------------------------------------------------------------------
function Roster:InspectStep()
  if not (IsInGroup and IsInGroup()) then return end
  if ns.API.InCombat() then return end
  if InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown() then return end
  if self.pending and GetTime and (GetTime() - (self.pending.at or 0)) < 5 then return end
  self.pending = nil
  for _, m in ipairs(self:Members()) do
    if m.unit and m.guid and not m.spec and not (UnitIsUnit and UnitIsUnit(m.unit, "player")) then
      local can = CanInspect and R.Plain(CanInspect(m.unit))
      local online = not UnitIsConnected or R.Plain(UnitIsConnected(m.unit)) ~= false
      if can and online and NotifyInspect then
        self.pending = { guid = m.guid, unit = m.unit, at = GetTime and GetTime() or 0 }
        pcall(NotifyInspect, m.unit)
        return
      end
    end
  end
end

function Roster:OnInspectReady(guid)
  local p = self.pending
  if not (p and guid and p.guid == guid) then return end
  local spec = GetInspectSpecialization and R.Plain(GetInspectSpecialization(p.unit))
  if type(spec) == "number" and spec > 0 and UD:GetSpec(spec) then
    self.specByGUID[guid] = spec
    self.inspected = (self.inspected or 0) + 1
    R:Fire("ROSTER_CHANGED")
  end
  self.pending = nil
  -- Clear on the next frame so every other addon's INSPECT_READY handler reads first (as Ensemble's
  -- own tracker does since 1.4.0), and only if no new inspect started meanwhile.
  local token = {}
  self.clearToken = token
  local function clear() if Roster.clearToken == token and not Roster.pending and ClearInspectPlayer then pcall(ClearInspectPlayer) end end
  if C_Timer and C_Timer.After then C_Timer.After(0, clear) else clear() end
end

function Roster:SyncTicker()
  local want = R.db and (IsInGroup and IsInGroup()) and R:IsRaidMode()
  if want and not self.ticker and C_Timer and C_Timer.NewTicker then
    self.ticker = C_Timer.NewTicker(self.INSPECT_EVERY, function() Roster:InspectStep() end)
  elseif not want and self.ticker then
    self.ticker:Cancel(); self.ticker = nil
  end
end

R:On("INSPECT_READY", function(guid) Roster:OnInspectReady(guid) end)
R:On("GROUP_ROSTER_UPDATE", function() Roster:SyncTicker(); R:Fire("ROSTER_CHANGED") end)
R:On("PLAYER_SPECIALIZATION_CHANGED", function() R:Fire("ROSTER_CHANGED") end)
R:On("MODE_CHANGED", function() Roster:SyncTicker() end)
R:On("DB_READY", function() Roster:SyncTicker() end)
