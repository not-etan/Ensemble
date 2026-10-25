-- Ensemble / GroupFinderTracker.lua  (Feature 3)
-- Live tracking of the current party (and Group Finder applicants) while the window is
-- open in Live mode. Pure reads: roster, class, spec, LFG listing. Nothing here is
-- protected or secure, so it works in combat (inspects are simply deferred).
--
-- Lifecycle: owners call Tracker:Acquire(owner) / Tracker:Release(owner): the main window
-- while its Live or Applicants tab is visible, and the applicant panel while the Group
-- Finder is open. Events are only registered while someone holds it, so a closed window
-- with the Group Finder shut costs nothing.
--
-- Midnight "Secret Values": nothing here uses combat-log data. Class/spec/role queries on
-- party units are not secret-restricted: player and party class/role confirmed readable in
-- 12.1.0 (/ens verify); worth re-checking inside a running key.

local _, ns = ...

local Tracker = {
  enabled = false,
  members = {},     -- ordered list for the comp (see Rescan)
  applicants = {},  -- current Group Finder applicants (hosting only)
  hosting = false,
  inRaid = false,
}
ns.Tracker = Tracker

local DEBOUNCE_SECONDS = 0.35   -- GROUP_ROSTER_UPDATE arrives in bursts; coalesce them
local INSPECT_INTERVAL = 1.5    -- seconds between NotifyInspect calls (server throttles)
local INSPECT_TIMEOUT = 6       -- give up waiting on one INSPECT_READY after this

local specByGUID = {}           -- guid -> specID (from inspect)
local specByName = {}           -- "Name-Realm" -> specID (from applicant data)
local inspectQueue = {}         -- guids waiting for inspection
local inspectPending = nil      -- { guid, unit, started }
local updateTimer = nil
local inspectTimer = nil

local frame = CreateFrame("Frame")

-- All confirmed present in 12.1.0 (build 69933); /ens verify probes every event the addon uses.
local EVENTS = {
  "GROUP_ROSTER_UPDATE",
  "PLAYER_SPECIALIZATION_CHANGED",
  "INSPECT_READY",
  "LFG_LIST_ACTIVE_ENTRY_UPDATE",
  "LFG_LIST_APPLICANT_LIST_UPDATED",
  "LFG_LIST_APPLICANT_UPDATED",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_ENABLED",
  "ZONE_CHANGED_NEW_AREA",   -- entering/leaving a dungeon (auto-select by zone)
  "CHALLENGE_MODE_START",
}

local function Now() return GetTime and GetTime() or 0 end
local firstSeen = {}   -- applicantID -> GetTime() when first seen

local function FullName(unit)
  local name, realm = UnitName(unit)
  if not name then return nil end
  -- Secret values (inside a key) can't be joined into a string: no name, like a pending spec.
  if issecretvalue then
    local okN, sn = pcall(issecretvalue, name)
    local okR, sr = pcall(issecretvalue, realm)
    if not okN or sn or not okR or sr then return nil end
  end
  if realm and realm ~= "" then return name .. "-" .. realm end
  local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
  return myRealm and (name .. "-" .. myRealm) or name
end

local function NormalizeName(n)
  if type(n) ~= "string" then return nil end
  if n:find("-", 1, true) then return n end
  local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
  return myRealm and (n .. "-" .. myRealm) or n
end
Tracker.NormalizeName = NormalizeName
Tracker.FullName = FullName

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------
-- Reference-counted: several owners can need live data at once (the main window's
-- Live/Applicants tabs, and the applicant panel beside the Group Finder). Events stay
-- registered only while at least one owner holds the tracker.
local owners = {}

function Tracker:Acquire(owner)
  owners[owner or "default"] = true
  self.lastSig = nil              -- a new owner always gets a fresh LIVE_ROSTER_CHANGED
  if self.enabled then self:RequestUpdate(0); return end
  self.enabled = true
  for _, ev in ipairs(EVENTS) do
    -- pcall: RegisterEvent errors on an unknown event name; a renamed event should not
    -- take the whole tracker down.
    pcall(frame.RegisterEvent, frame, ev)
  end
  self:RequestUpdate(0)
end

function Tracker:Release(owner)
  owners[owner or "default"] = nil
  if next(owners) ~= nil or not self.enabled then return end
  self.enabled = false
  frame:UnregisterAllEvents()
  if updateTimer then updateTimer:Cancel(); updateTimer = nil end
  if inspectTimer then inspectTimer:Cancel(); inspectTimer = nil end
  inspectPending = nil
  wipe(inspectQueue)
  ns.state.autoDungeon = nil
end

function Tracker:IsHeldBy(owner) return owners[owner] == true end

-- The main window's hold (Live and Applicants tabs).
function Tracker:Enable() self:Acquire("window") end
function Tracker:Disable() self:Release("window") end

function Tracker:RequestUpdate(delay)
  if not self.enabled or updateTimer then return end
  updateTimer = C_Timer.NewTimer(delay or DEBOUNCE_SECONDS, function()
    updateTimer = nil
    -- A timer callback has nobody above it to catch an error: keep it contained (the next
    -- roster event rescans again) and count it for /ens verify.
    local ok, err = pcall(Tracker.Rescan, Tracker)
    if not ok then
      Tracker.rescanErrors = (Tracker.rescanErrors or 0) + 1
      Tracker.lastRescanError = tostring(err)
    end
  end)
end

-- Unit reads inside a key may come back as Midnight "secret" values: treat one as unknown,
-- like a spec that hasn't been inspected yet. Counted for /ens verify.
local function Readable(v)
  if v == nil or not issecretvalue then return v end
  local ok, secret = pcall(issecretvalue, v)
  if ok and not secret then return v end
  Tracker.secretReads = (Tracker.secretReads or 0) + 1
  return nil
end
Tracker.Readable = Readable

---------------------------------------------------------------------------
-- Inspect queue (spec of other party members)
---------------------------------------------------------------------------
-- GUIDs go through Readable: inside a key the game may hide them (secret values), and a
-- hidden GUID can't be compared or used as a table key. A hidden one matches nothing.
local function UnitForGUID(guid)
  guid = Readable(guid)
  if not guid then return nil end
  if Readable(UnitGUID("player")) == guid then return "player" end
  for i = 1, 4 do
    local u = "party" .. i
    if Readable(UnitGUID(u)) == guid then return u end
  end
  if IsInRaid() then
    for i = 1, 40 do
      local u = "raid" .. i
      if Readable(UnitGUID(u)) == guid then return u end
    end
  end
  return nil
end

-- Counts our own NotifyInspect calls, so a deferred clear can tell a new inspect started.
local inspectSerial = 0

local function InspectFrameOpen()
  return InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown()
end

local function ScheduleInspect()
  if inspectTimer or not Tracker.enabled then return end
  inspectTimer = C_Timer.NewTimer(INSPECT_INTERVAL, function()
    inspectTimer = nil
    -- Same as the rescan timer: nothing above a timer callback catches an error, so keep it
    -- contained (the next roster change queues the inspect again) and count it for /ens verify.
    local ok, err = pcall(Tracker.ProcessInspectQueue, Tracker)
    if not ok then
      Tracker.rescanErrors = (Tracker.rescanErrors or 0) + 1
      Tracker.lastRescanError = tostring(err)
    end
  end)
end

function Tracker:ProcessInspectQueue()
  if not self.enabled then return end
  if inspectPending and (Now() - inspectPending.started) < INSPECT_TIMEOUT then
    ScheduleInspect(); return
  end
  inspectPending = nil
  -- Defer while in combat or while the user has their own Inspect window open
  -- (NotifyInspect would retarget it).
  if ns.API.InCombat() or InspectFrameOpen() then
    if #inspectQueue > 0 then ScheduleInspect() end
    return
  end
  while #inspectQueue > 0 do
    local guid = table.remove(inspectQueue, 1)
    local unit = UnitForGUID(guid)
    if unit and not specByGUID[guid] and CanInspect and CanInspect(unit) then
      -- NotifyInspect / GetInspectSpecialization: long-standing, not protected.
      -- Confirmed working in 12.1.0 (build 69933): party specs read via inspect.
      NotifyInspect(unit)
      inspectSerial = inspectSerial + 1
      inspectPending = { guid = guid, unit = unit, started = Now() }
      break
    end
  end
  if #inspectQueue > 0 or inspectPending then ScheduleInspect() end
end

local function QueueInspect(guid)
  if not guid or specByGUID[guid] then return end
  if inspectPending and inspectPending.guid == guid then return end
  for _, g in ipairs(inspectQueue) do if g == guid then return end end
  table.insert(inspectQueue, guid)
  ScheduleInspect()
end

---------------------------------------------------------------------------
-- Listing / applicants
---------------------------------------------------------------------------
-- Returns the DungeonData key for the player's own active Group Finder listing, or nil.
-- Confirmed working in 12.1.0 (build 69933): listing activity detected and matched. C_LFGList.HasActiveEntryInfo,
-- C_LFGList.GetActiveEntryInfo (entry.activityIDs table since 10.2, activityID before),
-- C_LFGList.GetActivityInfoTable(activityID).fullName.
local function DetectListingDungeon()
  if not (C_LFGList and C_LFGList.HasActiveEntryInfo) then return nil end
  local okHas, has = pcall(C_LFGList.HasActiveEntryInfo)
  if not okHas or not has then return nil end
  local ok, entry = pcall(C_LFGList.GetActiveEntryInfo)
  if not ok or type(entry) ~= "table" then return nil end
  local ids = entry.activityIDs or (entry.activityID and { entry.activityID }) or {}
  for _, id in ipairs(ids) do
    local okInfo, info = pcall(C_LFGList.GetActivityInfoTable, id)
    local key = ns.Dungeons:KeyForActivity(id, okInfo and info or nil)
    if key then return key end
  end
  return nil
end

function Tracker:DetectListingDungeon() return DetectListingDungeon() end

-- Confirmed working in 12.1.0 (build 69933), specID is the 16th return (a 17th boolean follows): C_LFGList.GetApplicants,
-- C_LFGList.GetApplicantInfo(id) -> table{numMembers, applicationStatus,...},
-- C_LFGList.GetApplicantMemberInfo(id, i) -> name, class, localizedClass, level, itemLevel,
--   honorLevel, tank, healer, damage, assignedRole, relationship, dungeonScore,
--   pvpItemLevel, factionGroup, raceID, specID, <boolean>.
-- The listing's activity (for per-dungeon scores of applicants).
local function ListingActivity()
  if not (C_LFGList and C_LFGList.GetActiveEntryInfo) then return nil end
  local ok, entry = pcall(C_LFGList.GetActiveEntryInfo)
  if not ok or type(entry) ~= "table" then return nil end
  return (entry.activityIDs and entry.activityIDs[1]) or entry.activityID
end

-- An applicant's best run of the listed dungeon this season (Blizzard's own data):
-- C_LFGList.GetApplicantDungeonScoreForListing(applicantID, memberIndex, activityID) ->
-- { mapScore, mapName, bestRunLevel, finishedSuccess }. nil when unavailable.
local function BestHere(applicantID, m, activityID)
  local fn = C_LFGList and C_LFGList.GetApplicantDungeonScoreForListing
  if not (fn and activityID) then return nil end
  local ok, info = pcall(fn, applicantID, m, activityID)
  if not ok or type(info) ~= "table" then return nil end
  return { level = tonumber(info.bestRunLevel) or 0, timed = info.finishedSuccess and true or false,
           score = tonumber(info.mapScore) or 0 }
end
Tracker.BestHere = BestHere

local function ReadApplicants()
  local out = {}
  if not (C_LFGList and C_LFGList.GetApplicants) then return out end
  local activityID = ListingActivity()
  local ok, list = pcall(C_LFGList.GetApplicants)
  if not ok or type(list) ~= "table" then return out end
  for _, applicantID in ipairs(list) do
    local okI, info = pcall(C_LFGList.GetApplicantInfo, applicantID)
    if okI and type(info) == "table" then
      local status = info.applicationStatus
      if status == nil or status == "applied" or status == "invited" then
        for m = 1, (info.numMembers or 1) do
          -- 17th return: isLeaver (Blizzard's own name for it in LFGList.lua, 12.1.5); Fill group
          -- can skip applicants with that flag. Anything but a boolean means "unknown".
          local okM, name, classFile, _, level, itemLevel, _, tank, healer, damage, assignedRole, _, score,
                _, _, _, specID, isLeaver = pcall(C_LFGList.GetApplicantMemberInfo, applicantID, m)
          if okM and name then
            if type(specID) ~= "number" or specID == 0 or not ns.UD:GetSpec(specID) then specID = nil end
            if specID then specByName[NormalizeName(name)] = specID end
            table.insert(out, {
              applicantID = applicantID, name = name, classFile = classFile, specID = specID,
              full = NormalizeName(Readable(name)),   -- "Name-Realm", for past keys together (1.5.0)
              role = assignedRole, score = score, status = status, itemLevel = itemLevel, level = level,
              memberIndex = m, numMembers = info.numMembers or 1,
              canTank = tank, canHeal = healer, canDps = damage,
              isLeaver = Readable(isLeaver) == true, leaverKnown = type(Readable(isLeaver)) == "boolean",
              bestHere = BestHere(applicantID, m, activityID),
            })
          end
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Roster scan
---------------------------------------------------------------------------
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }

function Tracker:Rescan()
  local members = {}
  self.inRaid = IsInRaid() and true or false
  local units = { "player" }
  if self.inRaid then
    -- Raid groups aren't M+ groups; show the first five raid units so nothing errors.
    units = {}
    for i = 1, math.min(GetNumGroupMembers(), 5) do units[i] = "raid" .. i end
  else
    for i = 1, 4 do units[#units + 1] = "party" .. i end
  end

  local present = {}
  for _, unit in ipairs(units) do
    if Readable(UnitExists(unit)) then
      local guid = Readable(UnitGUID(unit))
      local _, classFile = UnitClass(unit)
      classFile = Readable(classFile)
      if type(classFile) ~= "string" then classFile = nil end
      local isPlayer = Readable(UnitIsUnit(unit, "player")) and true or false
      local specID
      if isPlayer then
        specID = Readable(ns.API.GetPlayerSpecID())
      else
        specID = guid and specByGUID[guid]
        if not specID and GetInspectSpecialization then
          local s = Readable(GetInspectSpecialization(unit))
          if type(s) == "number" and s > 0 then specID = s end
        end
        if not specID then
          -- From their application (they joined from your listing). Used once: it moves to the
          -- per-player cache, so a spec change (which clears that) can't bring the old one back.
          local full = FullName(unit)
          specID = full and specByName[full]
          if specID and guid then specByName[full] = nil end
        end
        if specID and guid then specByGUID[guid] = specID end
      end
      if type(specID) ~= "number" or not ns.UD:GetSpec(specID) then specID = nil end
      -- Spec belongs to another class (stale cache)? Drop it.
      if specID and classFile and ns.UD:GetSpec(specID).class ~= classFile then specID = nil end
      if not specID and guid and not isPlayer then QueueInspect(guid) end
      local role = Readable(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE")
      if type(role) ~= "string" then role = "NONE" end
      if specID and role == "NONE" then role = ns.UD:GetSpec(specID).role end
      if guid then present[guid] = true end
      local name = Readable(UnitName(unit))
      table.insert(members, {
        unit = unit, guid = guid, name = type(name) == "string" and name or "?", classFile = classFile,
        full = FullName(unit),   -- "Name-Realm" (nil when hidden), for past keys together
        specID = specID, role = role, pending = (specID == nil),
        isPlayer = isPlayer,
      })
    end
  end

  -- Drop queued inspects for people who left.
  for i = #inspectQueue, 1, -1 do
    if not present[inspectQueue[i]] then table.remove(inspectQueue, i) end
  end
  if inspectPending and not present[inspectPending.guid] then inspectPending = nil end

  table.sort(members, function(a, b)
    local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
    if ra ~= rb then return ra < rb end
    return (a.name or "") < (b.name or "")
  end)
  self.members = members

  self.hosting = false
  if C_LFGList and C_LFGList.HasActiveEntryInfo then
    local ok, has = pcall(C_LFGList.HasActiveEntryInfo)
    self.hosting = ok and has and true or false
  end
  self.applicants = self.hosting and ReadApplicants() or {}
  -- How long each application has been waiting. The game doesn't say when someone applied,
  -- so this is when the addon first saw them (a /reload restarts the count).
  local listed = {}
  for _, a in ipairs(self.applicants) do
    listed[a.applicantID] = true
    firstSeen[a.applicantID] = firstSeen[a.applicantID] or Now()
    a.firstSeen = firstSeen[a.applicantID]
  end
  for id in pairs(firstSeen) do if not listed[id] then firstSeen[id] = nil end end

  -- Auto dungeon for Live/Applicants: the listing first, else the dungeon you're in.
  local auto, autoSource = nil, nil
  if ns.db.settings.liveAutoDungeon ~= false then
    auto = DetectListingDungeon()
    if auto then autoSource = "listing"
    else
      auto = ns:CurrentInstanceDungeon()
      if auto then autoSource = "zone" end
    end
  end
  if auto ~= ns.state.autoDungeon or autoSource ~= ns.state.autoSource then
    local changedKey = auto ~= ns.state.autoDungeon
    ns.state.autoDungeon, ns.state.autoSource = auto, autoSource
    -- A new listing or a new dungeon: drop this session's manual Live pick so the
    -- default follows the group again. Never touches the Builder pick.
    if changedKey and auto then ns.state.liveDungeon = "AUTO" end
    ns:Fire("DUNGEON_CHANGED")
  end

  -- Applicant and roster events arrive in bursts and often change nothing the addon shows;
  -- only tell the windows when something did.
  local sig = self:Signature()
  if sig ~= self.lastSig then
    self.lastSig = sig
    ns:Fire("LIVE_ROSTER_CHANGED")
  end
end

-- Everything the windows read from the tracker, as one string.
function Tracker:Signature()
  -- Leader/assistant matters too: the Applicants tab's Invite button depends on it.
  local lead = UnitIsGroupLeader and (UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player")))
  local t = { self.hosting and "H" or "-", self.inRaid and "R" or "-", lead and "L" or "-" }
  for _, m in ipairs(self.members) do
    t[#t + 1] = table.concat({ tostring(m.guid), m.name, tostring(m.classFile), tostring(m.specID), m.role,
      m.pending and "p" or "", m.isPlayer and "me" or "" }, ":")
  end
  t[#t + 1] = "|"
  for _, a in ipairs(self.applicants) do
    t[#t + 1] = table.concat({ tostring(a.applicantID), tostring(a.memberIndex), tostring(a.numMembers), tostring(a.name),
      tostring(a.classFile), tostring(a.specID), tostring(a.role), tostring(a.score), tostring(a.status),
      tostring(a.itemLevel), tostring(a.level), a.canTank and "t" or "", a.canHeal and "h" or "", a.canDps and "d" or "",
      a.isLeaver and "L" or "",
      a.bestHere and (a.bestHere.level .. (a.bestHere.timed and "T" or "")) or "" }, ":")
  end
  return table.concat(t, ";")
end

-- Applicants grouped by application (a premade duo/trio applies as one entry).
-- Returns { { applicantID, members = { applicant rows } } } in list order.
function Tracker:GetApplicantGroups()
  local groups, byID = {}, {}
  for _, a in ipairs(self.applicants) do
    local g = byID[a.applicantID]
    if not g then
      g = { applicantID = a.applicantID, members = {}, firstSeen = a.firstSeen }
      byID[a.applicantID] = g
      groups[#groups + 1] = g
    end
    table.insert(g.members, a)
  end
  return groups
end

-- Members as analysis input: { specID?, classFile, pending, label }
function Tracker:GetComp()
  local out = {}
  for i = 1, math.min(#self.members, ns.NUM_SLOTS) do
    local m = self.members[i]
    out[#out + 1] = { specID = m.specID, classFile = m.classFile, pending = m.pending, label = m.name, role = m.role,
                      isPlayer = m.isPlayer, full = m.full }
  end
  return out
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "INSPECT_READY" then
    local guid = Readable(arg1)
    if not guid then return end
    local unit = guid and UnitForGUID(guid)
    -- Another addon (or the Inspect window) inspected someone outside the group: nothing to do.
    if not unit and not (inspectPending and inspectPending.guid == guid) then return end
    if unit and GetInspectSpecialization then
      local s = Readable(GetInspectSpecialization(unit))
      if type(s) == "number" and s > 0 then specByGUID[guid] = s end
    end
    if inspectPending and inspectPending.guid == guid then
      inspectPending = nil
      -- Only clear the inspect target we set ourselves, never the user's own. Cleared on the
      -- next frame, not here: another addon may have inspected the same player and its
      -- INSPECT_READY handler can run after ours, so every handler gets to read first. Skipped
      -- if we started a new inspect meanwhile (clearing would cancel it).
      if ClearInspectPlayer then
        local serial = inspectSerial
        local function clear()
          if inspectSerial == serial and not inspectPending and not InspectFrameOpen() then ClearInspectPlayer() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, clear) else clear() end
      end
    end
    Tracker:RequestUpdate()
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    -- arg1 = unit whose spec changed; invalidate their cached spec.
    if arg1 and arg1 ~= "player" then
      local guid = Readable(UnitGUID(arg1))
      if guid then specByGUID[guid] = nil end
      -- And the spec from their application, if it's still here (1.4.1 review, R2).
      local full = FullName(arg1)
      if full then specByName[full] = nil end
    end
    Tracker:RequestUpdate()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if #inspectQueue > 0 then ScheduleInspect() end
  else
    Tracker:RequestUpdate()
  end
end)
