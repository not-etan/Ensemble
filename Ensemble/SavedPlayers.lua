-- Ensemble / SavedPlayers.lua
-- Saved players and reserved slots (1.5.0).
--
-- Saved players: people you play with, kept on this computer for every character
-- (db.savedPlayers = { { full = "Name-Realm", specs = { specID, ... }, default = specID } }).
-- Picking one fills a reservation's name and their default spec, and a planner slot.
--
-- Reserved slots: hold an open slot for a friend who's joining, so Fill group plans and invites
-- only the rest (db.reserved = { seenListed = bool, list = { { specID, full = "Name-Realm"|nil } } }).
-- The spec is required (it decides the Fill group checks) and the role follows from it; the
-- name is optional. A reservation counts like a party member for Needs, the strictness check
-- and the musts (Analysis treats it as a member with a known spec), and suggestions never fill
-- it. It clears when that player joins (full name), on Release, when the group is full, or
-- when the listing ends; a /reload while the listing is up keeps it.
--
-- Limits: Blizzard's listing can't be changed by addons, so players keep applying for the
-- reserved role; and an invite you sent your friend outside the Group Finder isn't visible to
-- addons, so the reservation is set by hand.
--
-- Privacy: names stay here and in the window. /ens verify prints counts only; /ens report, party
-- posts and share strings never carry them.
local _, ns = ...

local P = {}
ns.Players = P

P.MAX_SAVED = 100
P.ROLE_SLOTS = { TANK = 1, HEALER = 1, DAMAGER = 3 }

local function DB() return ns.db end
local function Key(full) return type(full) == "string" and full:lower() or nil end
P.Key = Key

-- "ann", "Ann-Area 52" -> "Ann-Area52"; your own realm when none is given. nil for empty text.
function P:Normalize(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  local name, realm = text:match("^([^%-]+)%-(.+)$")
  if not name then name = text end
  name = name:gsub("%s+", "")
  if name == "" then return nil end
  -- Names are stored as the game writes them: first letter capitalized (ASCII only; other
  -- letters are kept as typed, since the game's own capitalization isn't known here).
  name = name:sub(1, 1):upper() .. name:sub(2)
  if realm then
    realm = realm:gsub("%s+", "")
    if realm == "" then realm = nil end
  end
  if not realm then
    local my = GetNormalizedRealmName and GetNormalizedRealmName()
    realm = type(my) == "string" and my ~= "" and my or nil
  end
  return realm and (name .. "-" .. realm) or name
end

local function ValidSpec(id) return type(id) == "number" and ns.UD:GetSpec(id) ~= nil end

---------------------------------------------------------------------------
-- Saved players
---------------------------------------------------------------------------
function P:List() return DB().savedPlayers end

function P:Find(full)
  local k = Key(full)
  if not k then return nil end
  for i, p in ipairs(DB().savedPlayers) do
    if Key(p.full) == k then return p, i end
  end
  return nil
end

local function Changed() ns:Fire("SAVED_PLAYERS_CHANGED") end

-- Add a player, or a spec to a saved player. A new player's first spec is their default; an
-- added spec never changes the default (the author, October 25, 2026).
function P:Save(full, specID)
  full = self:Normalize(full)
  if not full or not ValidSpec(specID) then return false end
  local p = self:Find(full)
  if not p then
    if #DB().savedPlayers >= self.MAX_SAVED then return false, "full" end
    p = { full = full, specs = { specID }, default = specID }
    table.insert(DB().savedPlayers, p)
    table.sort(DB().savedPlayers, function(a, b) return Key(a.full) < Key(b.full) end)
  else
    for _, id in ipairs(p.specs) do if id == specID then Changed(); return true end end
    table.insert(p.specs, specID)
  end
  Changed()
  return true
end

function P:HasSpec(p, specID)
  for _, id in ipairs(p and p.specs or {}) do if id == specID then return true end end
  return false
end

function P:SetDefault(full, specID)
  local p = self:Find(full)
  if not p or not self:HasSpec(p, specID) then return false end
  p.default = specID
  Changed()
  return true
end

-- Remove one spec (the last one can't go: remove the player instead).
function P:RemoveSpec(full, specID)
  local p = self:Find(full)
  if not p or #p.specs <= 1 then return false end
  for i, id in ipairs(p.specs) do
    if id == specID then
      table.remove(p.specs, i)
      if p.default == specID then p.default = p.specs[1] end
      Changed()
      return true
    end
  end
  return false
end

function P:Remove(full)
  local _, i = self:Find(full)
  if not i then return false end
  table.remove(DB().savedPlayers, i)
  Changed()
  return true
end

-- Saved players whose name matches what's typed: case-insensitive, names starting with the text
-- first, then names containing it; "Name-Realm" text also matches on the realm part.
function P:Matches(text, max)
  max = max or 6
  local q = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
  if q == "" then return {} end
  local starts, contains = {}, {}
  for _, p in ipairs(DB().savedPlayers) do
    local k = Key(p.full)
    local name = k:match("^([^%-]+)") or k
    if k:sub(1, #q) == q or name:sub(1, #q) == q then starts[#starts + 1] = p
    elseif k:find(q, 1, true) then contains[#contains + 1] = p end
  end
  local out = {}
  for _, list in ipairs({ starts, contains }) do
    for _, p in ipairs(list) do if #out < max then out[#out + 1] = p end end
  end
  return out
end

-- "Holy Priest (default), Shadow Priest"
function P:SpecsText(p)
  local parts = {}
  for _, id in ipairs(p and p.specs or {}) do
    local s = ns.UD:GetSpec(id)
    if s then
      parts[#parts + 1] = ns.UD:SpecName(id) .. " " .. ns.UD:ClassName(s.class) .. (id == p.default and " (default)" or "")
    end
  end
  return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Reserved slots
---------------------------------------------------------------------------
local function RChanged() ns:Fire("RESERVED_CHANGED") end

function P:Reservations() return DB().reserved.list end

-- Party members by role (real players only).
local function PartyRoles()
  local roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }
  for _, m in ipairs(ns.Tracker:GetComp()) do
    local s = m.specID and ns.UD:GetSpec(m.specID)
    local r = (s and s.role) or m.role
    if roles[r] then roles[r] = roles[r] + 1 end
  end
  return roles
end

-- Free slots of a role after the party and the other reservations.
function P:FreeFor(role)
  local roles = PartyRoles()
  for _, r in ipairs(self:Reservations()) do
    local s = ns.UD:GetSpec(r.specID)
    if s and roles[s.role] then roles[s.role] = roles[s.role] + 1 end
  end
  return (self.ROLE_SLOTS[role] or 0) - (roles[role] or 0)
end

-- Hold a slot. specID required; name optional ("Name" or "Name-Realm"). save: also add the
-- player (or this spec) to Saved players. Returns true, or false and the reason.
function P:Reserve(specID, name, save)
  if not ValidSpec(specID) then return false, "Pick a spec: it decides what the slot brings." end
  local role = ns.UD:GetSpec(specID).role
  if self:FreeFor(role) <= 0 then
    return false, "No open " .. (role == "TANK" and "tank" or role == "HEALER" and "healer" or "DPS") .. " slot to reserve."
  end
  local full = self:Normalize(name)
  if full then
    for _, r in ipairs(self:Reservations()) do
      if Key(r.full) == Key(full) then return false, full .. " already has a reserved slot." end
    end
  end
  table.insert(DB().reserved.list, { specID = specID, full = full })
  if self:Listed() then DB().reserved.seenListed = true end
  if save and full then self:Save(full, specID) end
  RChanged()
  return true
end

function P:Release(i)
  local list = self:Reservations()
  if not list[i] then return false end
  table.remove(list, i)
  if #list == 0 then DB().reserved.seenListed = false end
  RChanged()
  return true
end

function P:ClearReservations(why)
  local res = DB() and DB().reserved
  if not res or #res.list == 0 then
    if res then res.seenListed = false end
    return false
  end
  res.list = {}
  res.seenListed = false
  self.lastCleared = why
  RChanged()
  return true
end

-- "Holy Priest (Ann)" / "Holy Priest"
function P:ReservationLabel(r)
  local s = ns.UD:GetSpec(r.specID)
  local spec = s and (ns.UD:SpecName(r.specID) .. " " .. ns.UD:ClassName(s.class)) or "?"
  local name = r.full and (r.full:match("^([^%-]+)") or r.full)
  return spec .. (name and (" (" .. name .. ")") or "")
end

-- Names to show in "Group ready (1 slot reserved for Ann)": nil when the reservations are unnamed.
function P:ReservedFor()
  local names, n = {}, 0
  for _, r in ipairs(self:Reservations()) do
    n = n + 1
    if r.full then names[#names + 1] = r.full:match("^([^%-]+)") or r.full end
  end
  return n, names
end

-- Analysis members for the reservations: known spec, the spec's role, labeled for the slot.
function P:ReservedMembers()
  local out = {}
  for _, r in ipairs(self:Reservations()) do
    local s = ns.UD:GetSpec(r.specID)
    if s then
      out[#out + 1] = { specID = r.specID, classFile = s.class, role = s.role, reserved = true, full = r.full,
        label = "Reserved: " .. self:ReservationLabel(r) }
    end
  end
  return out
end

-- The live party plus reserved slots (never more than five): what Composition's Needs, the
-- applicant ratings and Fill group work on. History, boss cards and the Plan tab keep the real
-- party (Tracker:GetComp).
function P:LiveComp()
  local comp = ns.Tracker:GetComp()
  for _, m in ipairs(self:ReservedMembers()) do
    if #comp >= ns.NUM_SLOTS then break end
    comp[#comp + 1] = m
  end
  return comp
end

function P:Listed()
  if not (C_LFGList and C_LFGList.HasActiveEntryInfo) then return false end
  local ok, has = pcall(C_LFGList.HasActiveEntryInfo)
  return ok and has and true or false
end

-- The party changed: a named reservation clears when that player joins; all of them when the
-- group is full. Reads the units directly (the roster tracker may be off with the window
-- closed); a name the game hides matches nothing.
function P:OnRoster()
  local res = DB() and DB().reserved
  if not res or #res.list == 0 then return end
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  if n >= ns.NUM_SLOTS and not (IsInRaid and IsInRaid()) then self:ClearReservations("full"); return end
  local present = {}
  local FullName = ns.Tracker.FullName
  for i = 1, 4 do
    local ok, full = pcall(FullName, "party" .. i)
    if ok and type(full) == "string" then present[Key(full)] = true end
  end
  local changed = false
  for i = #res.list, 1, -1 do
    local k = Key(res.list[i].full)
    if k and present[k] then table.remove(res.list, i); changed = true end
  end
  if changed then
    if #res.list == 0 then res.seenListed = false end
    RChanged()
  end
end

-- Listing state: a reservation made while listed ends with that listing. One made before
-- listing waits for the listing. After a /reload the first answer can come before the listing
-- has loaded, so a "not listed" at that point is checked again a few seconds later.
P.RECHECK_DELAY = 5
function P:OnListing(has, was, baseline)
  local res = DB() and DB().reserved
  if not res then return end
  if has then
    if #res.list > 0 then res.seenListed = true end
    return
  end
  if #res.list == 0 or not res.seenListed then return end
  if baseline then
    C_Timer.After(self.RECHECK_DELAY, function()
      if not P:Listed() and DB().reserved.seenListed then P:ClearReservations("listing ended") end
    end)
  elseif was then
    self:ClearReservations("listing ended")
  end
end

local watch = CreateFrame("Frame")
pcall(watch.RegisterEvent, watch, "GROUP_ROSTER_UPDATE")
watch:SetScript("OnEvent", function() if ns.db then pcall(P.OnRoster, P) end end)
ns:On("LIVE_ROSTER_CHANGED", function() if ns.db then pcall(P.OnRoster, P) end end)
