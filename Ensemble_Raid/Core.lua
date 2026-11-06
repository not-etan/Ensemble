-- Ensemble Raid (test build) / Core.lua
-- A companion folder that uses Ensemble's own code through EnsembleCore (published by Ensemble's
-- Core.lua since November 6, 2026). Raid data and state live in this folder's own saved variables
-- (EnsembleRaidDB), so nothing here touches EnsembleDB. Not released: the author's in-game test.
--
-- Everything in this folder is plain, non-secure frames and reads; it never calls a protected
-- function (markers are named in plans and chat, never placed or set).

local ADDON, R = ...
R.ADDON = ADDON

local ns = EnsembleCore
if not ns or not ns.UI or not ns.UD then
  R.disabled = true
  local msg = "Ensemble Raid (test build) needs Ensemble 1.6.0 or later (with EnsembleCore). Raid features are off."
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
  return
end
R.ns = ns
R.Util = ns.Util

local function Meta(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, ADDON, field)
    if ok then return v end
  end
end
R.VERSION = Meta("Version") or "test"

---------------------------------------------------------------------------
-- Secret values (Midnight): a hidden value is never compared or shown.
---------------------------------------------------------------------------
function R.Secret(v)
  return issecretvalue and v ~= nil and issecretvalue(v) or false
end
function R.Plain(v)
  if R.Secret(v) then return nil end
  return v
end

---------------------------------------------------------------------------
-- Small event bus (like ns:On / ns:Fire) and the game events this folder listens to.
---------------------------------------------------------------------------
local listeners = {}
function R:On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end
function R:Fire(event, ...)
  local list = listeners[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

R.EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_START",
             "ENCOUNTER_END", "INSPECT_READY", "PLAYER_REGEN_ENABLED", "PLAYER_SPECIALIZATION_CHANGED" }

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
R.DEFAULTS = {
  schema = 1,
  mode = "auto",          -- "auto" | "mplus" | "raid"
  manualSince = nil,      -- true while a hand pick waits for the group to end
  tab = "roster",
  instance = "abyss",
  diff = {},              -- instance key -> difficulty key
  boss = {},              -- instance key -> boss key
  order = {},             -- instance key -> list of boss keys (the player's order)
  view = "learner",       -- Bosses tab: "learner" | "leader"
  role = "AUTO",          -- learner filter: "AUTO" (your role) | "ALL" | "TANK" | "HEALER" | "DAMAGER"
  planner = { members = {} },   -- the roster used when you're not in a group
  plans = {},             -- boss key -> data difficulty -> { rows = { [id] = { names, marker } }, custom = { ... } }
  encSeen = {},           -- encounter name -> encounter ID, as the game reports them (for later data work)
  bossWindow = { auto = true },
}

local function Sanitize(db)
  local D = R.Data
  if type(db.mode) ~= "string" or not ({ auto = true, mplus = true, raid = true })[db.mode] then db.mode = "auto" end
  if not D.INSTANCE[db.instance] then db.instance = "abyss" end
  for _, k in ipairs({ "diff", "boss", "order", "plans", "encSeen", "planner", "bossWindow" }) do
    if type(db[k]) ~= "table" then db[k] = {} end
  end
  if type(db.planner.members) ~= "table" then db.planner.members = {} end
  for inst, d in pairs(db.diff) do
    local I = D.INSTANCE[inst]
    if not I or not ns.Util.Contains(I.diffs, d) then db.diff[inst] = nil end
  end
  for inst, bk in pairs(db.boss) do
    local I = D.INSTANCE[inst]
    if not I or not ns.Util.Contains(I.bosses, bk) then db.boss[inst] = nil end
  end
  -- A saved order must hold exactly the instance's bosses, with only allowed moves.
  for inst, list in pairs(db.order) do
    local I = D.INSTANCE[inst]
    local okList = I and type(list) == "table" and #list == #I.bosses
    if okList then
      local seen = {}
      for _, bk in ipairs(list) do
        if seen[bk] or not ns.Util.Contains(I.bosses, bk) then okList = false end
        seen[bk] = true
      end
    end
    if okList and not R:OrderAllowed(I, list) then okList = false end
    if not okList then db.order[inst] = nil end
  end
  local kept = {}
  for _, m in ipairs(db.planner.members) do
    if type(m) == "table" and type(m.class) == "string" and ns.UD.classes[m.class] then
      if m.spec ~= nil and not ns.UD:GetSpec(m.spec) then m.spec = nil end
      if type(m.name) ~= "string" or m.name == "" then m.name = nil end
      kept[#kept + 1] = m
    end
  end
  db.planner.members = kept
  if db.view ~= "leader" then db.view = "learner" end
  if not ({ AUTO = true, ALL = true, TANK = true, HEALER = true, DAMAGER = true })[db.role] then db.role = "AUTO" end
  if type(db.bossWindow.auto) ~= "boolean" then db.bossWindow.auto = true end
end

function R:InitDB()
  EnsembleRaidDB = type(EnsembleRaidDB) == "table" and EnsembleRaidDB or {}
  ns.Util.MergeDefaults(EnsembleRaidDB, self.DEFAULTS)
  self.db = EnsembleRaidDB
  Sanitize(self.db)
end
R.Sanitize = Sanitize

---------------------------------------------------------------------------
-- Difficulties, instances and the boss order
---------------------------------------------------------------------------
function R:DataDiff(d)
  local info = self.Data.DIFFS[d]
  return info and info.data or "N"
end
-- Does something first seen at difficulty `itemD` ("N"/"H"/"M") apply at `viewD` (any key)?
function R:Applies(itemD, viewD)
  local D = self.Data.DIFFS
  return (D[itemD] and D[itemD].rank or 1) <= (D[viewD] and D[viewD].rank or 1)
end
function R:DiffLabel(d) local x = self.Data.DIFFS[d]; return x and x.label or tostring(d) end

function R:Instance() return self.Data.INSTANCE[self.db.instance] end
function R:Diff(inst)
  inst = inst or self:Instance()
  local d = self.db.diff[inst.key]
  if d and ns.Util.Contains(inst.diffs, d) then return d end
  return ns.Util.Contains(inst.diffs, "N") and "N" or inst.diffs[1]
end
function R:SetDiff(d)
  local inst = self:Instance()
  if ns.Util.Contains(inst.diffs, d) then self.db.diff[inst.key] = d; self:Fire("CHANGED") end
end

-- The player's boss order: the instance's default, with moves only inside its order groups.
function R:OrderAllowed(inst, list)
  local groupOf = {}
  for gi, g in ipairs(inst.orderGroups or {}) do for _, pos in ipairs(g) do groupOf[pos] = gi end end
  for pos, bk in ipairs(list) do
    if bk ~= inst.bosses[pos] then
      local home
      for p, k in ipairs(inst.bosses) do if k == bk then home = p end end
      if not (groupOf[pos] and groupOf[pos] == groupOf[home]) then return false end
    end
  end
  return true
end
function R:Order(inst)
  inst = inst or self:Instance()
  return self.db.order[inst.key] or inst.bosses
end
function R:CanMove(inst, bk, delta)
  local list = self:Order(inst)
  local pos
  for p, k in ipairs(list) do if k == bk then pos = p end end
  local to = pos and pos + delta
  if not to or to < 1 or to > #list then return false end
  local copy = {}
  for i, k in ipairs(list) do copy[i] = k end
  copy[pos], copy[to] = copy[to], copy[pos]
  return self:OrderAllowed(inst, copy), copy
end
function R:Move(bk, delta)
  local inst = self:Instance()
  local okMove, copy = self:CanMove(inst, bk, delta)
  if not okMove then return false end
  self.db.order[inst.key] = copy
  self:Fire("CHANGED")
  return true
end
function R:ResetOrder()
  self.db.order[self:Instance().key] = nil
  self:Fire("CHANGED")
end
function R:Movable(inst, bk)
  return self:CanMove(inst, bk, -1) or self:CanMove(inst, bk, 1)
end

function R:Boss(inst)
  inst = inst or self:Instance()
  local bk = self.db.boss[inst.key]
  if bk and ns.Util.Contains(inst.bosses, bk) then return bk end
  return self:Order(inst)[1]
end
function R:SetBoss(bk)
  local b = self.Data.BOSSES[bk]
  if not b then return end
  self.db.instance = b.instance
  self.db.boss[b.instance] = bk
  self:Fire("CHANGED")
end
function R:SetInstance(key)
  if self.Data.INSTANCE[key] then self.db.instance = key; self:Fire("CHANGED") end
end
function R:StepBoss(delta)
  local inst = self:Instance()
  local list, cur = self:Order(inst), self:Boss(inst)
  for p, k in ipairs(list) do
    if k == cur and list[p + delta] then self:SetBoss(list[p + delta]); return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Where you are: the instance (by name, from GetInstanceInfo) and its difficulty.
---------------------------------------------------------------------------
function R:CurrentInstance()
  if not GetInstanceInfo then return nil end
  local ok, name, itype, diffID, diffName = pcall(GetInstanceInfo)
  if not ok then return nil end
  name, itype, diffID, diffName = R.Plain(name), R.Plain(itype), R.Plain(diffID), R.Plain(diffName)
  local found
  for _, inst in ipairs(self.Data.INSTANCES) do if inst.name == name then found = inst end end
  local d = diffID and self.Data.DIFF_BY_ID[diffID]
  if found and found.kind == "lair" and type(diffName) == "string" and diffName:lower():find("world", 1, true) then d = "W" end
  return found, d, itype, diffID, name
end

---------------------------------------------------------------------------
-- Mode: Mythic+ or Raid. Auto: Raid in a raid group or inside one of the season's raids or Lairs.
-- A hand pick holds until you leave a group (then Auto again).
---------------------------------------------------------------------------
function R:AutoMode()
  if IsInRaid and IsInRaid() then return "raid" end
  -- Only this season's raids and Lair (an old raid farmed solo stays in Mythic+ mode).
  if self:CurrentInstance() then return "raid" end
  return "mplus"
end
function R:Mode()
  local m = self.db and self.db.mode or "auto"
  if m == "raid" or m == "mplus" then return m end
  return self:AutoMode()
end
function R:IsRaidMode() return self:Mode() == "raid" end
function R:SetMode(m)
  self.db.mode = m
  self.wasInGroup = IsInGroup and IsInGroup() or false
  self:Fire("MODE_CHANGED")
end

local lastMode
function R:CheckMode()
  -- Leaving a group ends a hand pick.
  local inGroup = IsInGroup and IsInGroup() or false
  if self.db.mode ~= "auto" and self.wasInGroup and not inGroup then self.db.mode = "auto" end
  self.wasInGroup = inGroup
  -- Follow the instance you're in: its difficulty, once per arrival.
  local inst, d = self:CurrentInstance()
  if inst and (self.lastArrival ~= inst.key .. ":" .. tostring(d)) then
    self.lastArrival = inst.key .. ":" .. tostring(d)
    self.db.instance = inst.key
    if d and ns.Util.Contains(inst.diffs, d) then self.db.diff[inst.key] = d end
    self:Fire("CHANGED")
  elseif not inst then
    self.lastArrival = nil
  end
  local m = self:Mode()
  if m ~= lastMode then lastMode = m; self:Fire("MODE_CHANGED") end
end

---------------------------------------------------------------------------
-- Markers and chat
---------------------------------------------------------------------------
function R:MarkerIcon(key, size)
  local m = key and self.Data.MARKER[key]
  if not m then return "" end
  return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:%d|t", m.i, size or 0)
end
-- "{star}" in our text: an icon on screen, {rtN} in chat (the game turns it into the icon).
function R:IconText(text, size)
  return (tostring(text or ""):gsub("{(%a+)}", function(k) return self.Data.MARKER[k] and self:MarkerIcon(k, size or 0) or nil end))
end
function R:ChatText(text)
  return (tostring(text or ""):gsub("{(%a+)}", function(k) local m = self.Data.MARKER[k]; return m and ("{rt" .. m.i .. "}") or nil end))
end

function R:ChatLocked()
  return ns.UI.ChatLocked and ns.UI.ChatLocked() or false
end
function R:CanWarn()
  if not (IsInRaid and IsInRaid()) then return IsInGroup and IsInGroup() and UnitIsGroupLeader and UnitIsGroupLeader("player") or false end
  return (UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player")) or false
end
function R:Channel(warning)
  local inInstanceGroup = LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
  local inHomeGroup = not LE_PARTY_CATEGORY_HOME or (IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME))
  if warning and self:CanWarn() then return "RAID_WARNING" end
  if inInstanceGroup and not inHomeGroup then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end

local function SendOne(msg, channel)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if not send then return false end
  return pcall(send, msg, channel)
end
-- Lines to the group a moment apart; blocked chat opens the copy window; solo prints them.
function R:Send(lines, what, warning)
  if not lines or #lines == 0 then return end
  local channel = self:Channel(warning)
  if warning and channel ~= "RAID_WARNING" then
    ns:Print("Raid warning needs leader or assist; posting to " .. (channel and channel:lower():gsub("_", " ") or "you") .. " instead.")
  end
  if channel and self:ChatLocked() then
    if ns.Verify and ns.Verify:ShowText(table.concat(lines, "\n"), (what or "chat text") .. ": chat is blocked right now, copy and paste it") then
      ns:Print("The game is blocking addon chat right now; the text is in the copy window.")
      return channel
    end
  end
  local function step(i)
    local line = lines[i]
    if not line then return end
    if not (channel and SendOne(line, channel)) then
      ns:Print(line .. (channel and " (couldn't send to chat here)" or ""))
    end
    if lines[i + 1] then
      if C_Timer and channel then C_Timer.After(0.3, function() step(i + 1) end) else step(i + 1) end
    end
  end
  step(1)
  if not channel then ns:Print("(not in a group: shown only to you)") end
  self.lastSent = { what = what, channel = channel, count = #lines }
  return channel
end
function R:Copy(lines, what)
  if ns.Verify then ns.Verify:ShowText(table.concat(lines or {}, "\n"), (what or "Text") .. ": copy and paste it") end
end

-- One wrapped post: "[Ensemble] " first, continuation lines after; nothing cut.
function R:Wrap(text, first, cont)
  return ns.Util.ChatWrap(first or "[Ensemble] ", self:ChatText(text), cont or "(cont.) ", 250)
end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
R.eventFrame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    R:InitDB()
    for _, e in ipairs(R.EVENTS) do pcall(self.RegisterEvent, self, e) end
    R.wasInGroup = IsInGroup and IsInGroup() or false
    R:Fire("DB_READY")
    return
  end
  if not R.db then return end
  if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    R:CheckMode()
  end
  R:Fire(event, ...)
end)
