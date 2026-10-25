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
-- A named reservation releases itself when that player's application turns to invited (your
-- Invite click, Fill group or Blizzard's button), so the slot isn't counted twice; it waits in
-- db.reserved.pending until the invite resolves. A time-out ("timedout") brings it back while
-- that listing is up; a declined invite ("invitedeclined") or any other end keeps it released.
-- No chat message either way: the band's "Reserved (N)" count shows it. What an invite nobody
-- answers turns into isn't documented; /ens verify lists the statuses seen (1.5.0 review, R3).
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

-- "ann", "Ann-Area 52", "Ann-Azjol-Nerub" -> "Ann-Realm", "Ann-Area52", "Ann-AzjolNerub": the
-- realm as the game writes it in names (no spaces or hyphens), your own when none is given.
-- nil for empty text, or an empty name or realm part ("Ann-", "-Realm") (1.5.0 review, R5).
function P:Normalize(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  local name, realm = text:match("^([^%-]*)%-(.*)$")
  if not name then name = text end
  name = name:gsub("%s+", "")
  if name == "" then return nil end
  -- Names are stored as the game writes them: first letter capitalized (ASCII only; other
  -- letters are kept as typed, since the game's own capitalization isn't known here).
  name = name:sub(1, 1):upper() .. name:sub(2)
  if realm then
    realm = ns.Tracker.CleanRealm(realm)
    if not realm then return nil end
  else
    realm = ns.Tracker.CleanRealm(GetNormalizedRealmName and GetNormalizedRealmName())
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
-- Planner slots (1.5.0): a saved player in a Composition planner slot. A person shows only
-- while the slot still holds the spec they were picked with.
---------------------------------------------------------------------------
function P:PlannerPerson(slot, people, slots)
  people = people or DB().currentPeople
  slots = slots or DB().currentComp
  local x = people and people[slot]
  if type(x) == "table" and x.full and slots[slot] == x.spec then return x end
  return nil
end

function P:SetPlannerSlot(slot, full, specID)
  if not ValidSpec(specID) then return false end
  DB().currentComp[slot] = specID
  DB().currentPeople[slot] = full and { full = full, spec = specID } or false
  ns:Fire("COMP_CHANGED", "slot")
  return true
end

-- Saved players who play `role`: { { p, specID } } (their default first when it fits the role).
function P:ForRole(role)
  local out = {}
  for _, p in ipairs(DB().savedPlayers) do
    local ids = {}
    for _, id in ipairs(p.specs) do
      local s = ns.UD:GetSpec(id)
      if s and s.role == role then
        if id == p.default then table.insert(ids, 1, id) else ids[#ids + 1] = id end
      end
    end
    for _, id in ipairs(ids) do out[#out + 1] = { p = p, specID = id } end
  end
  return out
end

-- The planner's people as saved-comp data (nil when nobody is named).
function P:PlannerPeopleCopy()
  local out, any = {}, false
  for s = 1, ns.NUM_SLOTS do
    local x = self:PlannerPerson(s)
    out[s] = x and { full = x.full, spec = x.spec } or false
    if x then any = true end
  end
  return any and out or nil
end

---------------------------------------------------------------------------
-- Reserved slots
---------------------------------------------------------------------------
local function RChanged() ns:Fire("RESERVED_CHANGED") end

function P:Reservations() return DB().reserved.list end

local UNITS = { "player", "party1", "party2", "party3", "party4" }

-- Party members by role (real players only), and how many there are. The roster tracker's list
-- while something holds it; otherwise the units directly, since the tracker's list goes stale
-- with nobody holding it (Settings tab, Group Finder closed, Auto-fill off; 1.5.0 review, R2).
-- A member whose role can't be read still takes a slot (the count).
local function PartyRoles()
  local roles, n = { TANK = 0, HEALER = 0, DAMAGER = 0 }, 0
  local Readable = ns.Tracker.Readable
  if ns.Tracker.enabled then
    for _, m in ipairs(ns.Tracker:GetComp()) do
      n = n + 1
      local s = m.specID and ns.UD:GetSpec(m.specID)
      local r = (s and s.role) or m.role
      if roles[r] then roles[r] = roles[r] + 1 end
    end
    return roles, n
  end
  if IsInRaid and IsInRaid() then return roles, ns.NUM_SLOTS end
  for _, unit in ipairs(UNITS) do
    local okE, exists = pcall(UnitExists, unit)
    if okE and Readable(exists) then
      n = n + 1
      local okR, r = pcall(UnitGroupRolesAssigned, unit)
      r = okR and Readable(r) or nil
      if (r == nil or r == "NONE") and unit == "player" then
        local s = ns.UD:GetSpec(Readable(ns.API.GetPlayerSpecID()) or 0)
        r = s and s.role
      end
      if roles[r] then roles[r] = roles[r] + 1 end
    end
  end
  return roles, n
end
P.PartyRoles = PartyRoles

-- The applicant status as the game reports it (nil when unknown or hidden).
function P:ApplicantStatus(id)
  if not (C_LFGList and C_LFGList.GetApplicantInfo) then return nil end
  local ok, info = pcall(C_LFGList.GetApplicantInfo, id)
  if not ok or type(info) ~= "table" then return nil end
  local st = ns.Tracker.Readable(info.applicationStatus)
  return type(st) == "string" and st or nil
end

-- Each applicant member with their application's status: { { id, status, full, role } }.
function P:ApplicantMembers()
  local out = {}
  if not (self:Listed() and C_LFGList.GetApplicants and C_LFGList.GetApplicantMemberInfo) then return out end
  local ok, list = pcall(C_LFGList.GetApplicants)
  if not ok or type(list) ~= "table" then return out end
  local Readable, NormalizeName = ns.Tracker.Readable, ns.Tracker.NormalizeName
  for _, id in ipairs(list) do
    local okI, info = pcall(C_LFGList.GetApplicantInfo, id)
    if okI and type(info) == "table" then
      local st = Readable(info.applicationStatus)
      for m = 1, (tonumber(Readable(info.numMembers)) or 1) do
        local okM, name, _, _, _, _, _, _, _, _, role = pcall(C_LFGList.GetApplicantMemberInfo, id, m)
        if okM then
          out[#out + 1] = { id = id, status = type(st) == "string" and st or nil,
            full = NormalizeName(Readable(name)), role = Readable(role) }
        end
      end
    end
  end
  return out
end

-- Invited applicants by role: they hold a slot until they join or the invite ends (R3).
function P:InvitedRoles()
  local roles, n = { TANK = 0, HEALER = 0, DAMAGER = 0 }, 0
  for _, a in ipairs(self:ApplicantMembers()) do
    if a.status == "invited" then
      n = n + 1
      if roles[a.role] then roles[a.role] = roles[a.role] + 1 end
    end
  end
  return roles, n
end

-- Free slots of a role after the party, invited applicants and the other reservations; never
-- more than the group's free slots overall.
function P:FreeFor(role)
  local roles, n = PartyRoles()
  local inv, ninv = self:InvitedRoles()
  for r, c in pairs(inv) do roles[r] = roles[r] + c end
  local taken = n + ninv
  for _, r in ipairs(self:Reservations()) do
    local s = ns.UD:GetSpec(r.specID)
    if s and roles[s.role] then roles[s.role] = roles[s.role] + 1 end
    taken = taken + 1
  end
  return math.min((self.ROLE_SLOTS[role] or 0) - (roles[role] or 0), ns.NUM_SLOTS - taken)
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
  -- Saved players full: the reservation still goes through; the caller says it wasn't saved (N3).
  local note
  if save and full then
    local okS, why = self:Save(full, specID)
    if not okS and why == "full" then note = "notSaved" end
  end
  RChanged()
  return true, note
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
    if res then res.seenListed = false; res.pending = {} end
    return false
  end
  res.list = {}
  res.pending = {}
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
  if not res or (#res.list == 0 and #res.pending == 0) then return end
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
  -- An invited friend who joined: their released reservation is done with.
  for i = #res.pending, 1, -1 do
    if present[Key(res.pending[i].full)] then table.remove(res.pending, i) end
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
  -- Waiting: reservations that belong to a listing, or friends' reservations released while
  -- their invite is out (those end with the listing too).
  local waiting = (#res.list > 0 and res.seenListed) or #res.pending > 0
  if not waiting then return end
  if baseline then
    C_Timer.After(self.RECHECK_DELAY, function()
      if P:Listed() then return end
      local r = DB().reserved
      if r.seenListed and #r.list > 0 then P:ClearReservations("listing ended") else r.pending = {} end
    end)
  elseif was then
    if #res.list > 0 and res.seenListed then self:ClearReservations("listing ended") else res.pending = {} end
  end
end

---------------------------------------------------------------------------
-- Invites to a reserved friend (1.5.0 review, R3)
---------------------------------------------------------------------------
-- What this session saw, for /ens verify (counts and status names only, never names).
P.inviteLog = { released = 0, restored = 0, stayed = 0, notRestored = 0, statuses = {} }

-- Statuses that put a friend's reservation on hold: the invite went out (or was taken already).
local RELEASE_ON = { invited = true, inviteaccepted = true }

local function ListingActivity()
  if not (C_LFGList and C_LFGList.GetActiveEntryInfo) then return nil end
  local ok, entry = pcall(C_LFGList.GetActiveEntryInfo)
  if not ok or type(entry) ~= "table" then return nil end
  return (type(entry.activityIDs) == "table" and entry.activityIDs[1]) or entry.activityID
end

local function Saw(status)
  local log = P.inviteLog.statuses
  log[status] = (log[status] or 0) + 1
end

-- Applicants changed: release a named reservation whose player is now invited, and settle the
-- released ones whose invite ended. Unnamed reservations are never touched.
function P:OnApplicants()
  local res = DB() and DB().reserved
  if not res then return end
  local named = false
  for _, r in ipairs(res.list) do if r.full then named = true end end
  if not named and #res.pending == 0 then return end
  if not self:Listed() then return end   -- the listing ending is OnListing's
  local activity = ListingActivity()
  local changed = false
  -- 1. Released reservations: has the invite ended?
  for i = #res.pending, 1, -1 do
    local p = res.pending[i]
    if p.listing and activity and p.listing ~= activity then
      table.remove(res.pending, i)   -- a different listing now: that invite is over
    else
      local st = self:ApplicantStatus(p.applicantID)
      if st and st ~= p.status then Saw(st); p.status = st end
      if st == "timedout" then
        table.remove(res.pending, i)
        local s = ns.UD:GetSpec(p.specID)
        local taken = false
        for _, r in ipairs(res.list) do if Key(r.full) == Key(p.full) then taken = true end end
        -- Back only into a slot that's still free (you may have filled the role meanwhile).
        if s and not taken and self:FreeFor(s.role) > 0 then
          table.insert(res.list, { specID = p.specID, full = p.full })
          res.seenListed = true
          self.inviteLog.restored = self.inviteLog.restored + 1
          changed = true
        else
          self.inviteLog.notRestored = self.inviteLog.notRestored + 1
        end
      elseif st and not RELEASE_ON[st] and st ~= "applied" then
        -- invitedeclined, or any other end: stays released.
        table.remove(res.pending, i)
        self.inviteLog.stayed = self.inviteLog.stayed + 1
      end
    end
  end
  -- 2. Named reservations whose player was just invited.
  if named then
    local byName = {}
    for _, a in ipairs(self:ApplicantMembers()) do
      if a.full and a.status and RELEASE_ON[a.status] then byName[Key(a.full)] = a end
    end
    for i = #res.list, 1, -1 do
      local r = res.list[i]
      local a = r.full and byName[Key(r.full)]
      if a then
        table.remove(res.list, i)
        table.insert(res.pending, { specID = r.specID, full = r.full, applicantID = a.id, status = a.status, listing = activity })
        Saw(a.status)
        self.inviteLog.released = self.inviteLog.released + 1
        changed = true
      end
    end
  end
  if changed then RChanged() end
end

local watch = CreateFrame("Frame")
pcall(watch.RegisterEvent, watch, "GROUP_ROSTER_UPDATE")
pcall(watch.RegisterEvent, watch, "LFG_LIST_APPLICANT_UPDATED")
pcall(watch.RegisterEvent, watch, "LFG_LIST_APPLICANT_LIST_UPDATED")
watch:SetScript("OnEvent", function(_, event)
  if not ns.db then return end
  if event == "GROUP_ROSTER_UPDATE" then pcall(P.OnRoster, P) else pcall(P.OnApplicants, P) end
end)
ns:On("LIVE_ROSTER_CHANGED", function()
  if ns.db then pcall(P.OnRoster, P); pcall(P.OnApplicants, P) end
end)
