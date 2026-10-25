-- Ensemble / Core.lua
-- Init, private namespace, SavedVariables defaults + schema migration, callbacks,
-- slash commands and Addon Compartment hooks.
--
-- Everything lives on the private addon table `ns` (passed by the client as the
-- second vararg of every file). The only intentional globals are the ones the client
-- itself requires by name:
--   EnsembleDB                          (SavedVariables, declared in the .toc)
--   SLASH_ENSEMBLE1                     (slash command registration: /ens)
--   Ensemble_OnAddonCompartmentClick/Enter/Leave (referenced from the .toc)

local ADDON_NAME, ns = ...

ns.ADDON_NAME = "Ensemble"
ns.SCHEMA_VERSION = 4

-- GetAddOnMetadata moved to C_AddOns in 10.1; the global was removed in 11.x.
local function GetMeta(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON_NAME, field)
  end
  return nil
end
ns.VERSION = GetMeta("Version") or "dev"

---------------------------------------------------------------------------
-- Small utilities (shared by every module)
---------------------------------------------------------------------------
local Util = {}
ns.Util = Util

function Util.DeepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = Util.DeepCopy(val) end
  return out
end

-- Fill keys missing from `dst` with copies from `src`. Never overwrites user values,
-- and never replaces a user value of a different type unless it is nil.
function Util.MergeDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      dst[k] = Util.DeepCopy(v)
    elseif type(v) == "table" and type(dst[k]) == "table" then
      Util.MergeDefaults(dst[k], v)
    end
  end
  return dst
end

function Util.Count(t)
  local n = 0
  if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
  return n
end

function Util.Trim(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Chat lines that never lose text: `text` goes after `first` on the first line and after `cont`
-- on each continuation line, every line at most `max` bytes (chat allows 255). Breaks after
-- ", ", "; ", ". " or around " > " first, then at a space, and only as a last resort inside a
-- word (never inside a UTF-8 character). Nothing is cut off and no "..." is added.
local function ChatChunks(text)
  local out, pos = {}, 1
  while pos <= #text do
    local s, e = text:find("[,;%.]%s+", pos)
    local s2, e2 = text:find("%s>%s+", pos)
    if s2 and (not s or s2 < s) then s, e = s2, e2 end
    if not s then out[#out + 1] = text:sub(pos); break end
    out[#out + 1] = text:sub(pos, e)
    pos = e + 1
  end
  return out
end

function Util.ChatWrap(first, text, cont, max)
  max = max or 250
  first, cont, text = first or "", cont or "", tostring(text or "")
  local lines, cur = {}, first
  local function push() lines[#lines + 1] = (cur:gsub("%s+$", "")) end
  local function fresh() return cur == first or cur == cont end
  for _, piece in ipairs(ChatChunks(text)) do
    if #cur + #piece > max and not fresh() then
      push(); cur = cont
      piece = (piece:gsub("^%s+", ""))
    end
    while #cur + #piece > max do
      -- A piece too long for a line on its own: break at its last space that fits.
      local room = max - #cur
      local cut = piece:sub(1, room + 1):match("^.*()%s")
      if not cut or cut <= 1 then
        cut = room + 1
        while cut > 2 and piece:byte(cut) and piece:byte(cut) >= 128 and piece:byte(cut) < 192 do cut = cut - 1 end
      end
      cur = cur .. piece:sub(1, cut - 1)
      push(); cur = cont
      piece = (piece:sub(cut):gsub("^%s+", ""))
    end
    cur = cur .. piece
  end
  if not (cur == cont and #lines > 0) then push() end
  return lines
end

-- Shorten `text` to at most `max` bytes with the same rules as ChatWrap: at the last space that
-- fits, else inside a word but never inside a UTF-8 character. For boxes with a hard limit
-- (the Sign Up note, a Bloodlust note), where the rest can't go on another line.
function Util.Clip(text, max)
  text = tostring(text or "")
  if #text <= max then return text end
  local cut = text:sub(1, max + 1):match("^.*()%s")
  if cut and cut > 1 then return (text:sub(1, cut - 1):gsub("[%s,;]+$", "")) end
  cut = max + 1
  while cut > 2 and text:byte(cut) and text:byte(cut) >= 128 and text:byte(cut) < 192 do cut = cut - 1 end
  return text:sub(1, cut - 1)
end

function Util.Contains(list, value)
  if type(list) ~= "table" then return false end
  for i = 1, #list do if list[i] == value then return true end end
  return false
end

-- Returns r, g, b and a "|cffRRGGBB" prefix for a class file token.
function Util.ClassColor(classFile)
  local c
  if classFile and C_ClassColor and C_ClassColor.GetClassColor then
    c = C_ClassColor.GetClassColor(classFile)
  end
  if not c and classFile and RAID_CLASS_COLORS then
    c = RAID_CLASS_COLORS[classFile]
  end
  if not c then return 0.8, 0.8, 0.8, "|cffcccccc" end
  return c.r, c.g, c.b, string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

---------------------------------------------------------------------------
-- Thin wrappers around client APIs so that a renamed/missing function degrades
-- to nil instead of a Lua error. Every one of these is flagged where 12.1 status
-- is not certain.
---------------------------------------------------------------------------
local API = {}
ns.API = API

-- GetSpecializationInfoByID(specID) -> id, name, description, icon, role, classFile, className
-- Long-standing global; confirmed present in 12.1.0 (build 69933) by /ens verify (all 40 spec IDs match).
function API.GetSpecInfoByID(specID)
  if not specID or specID == 0 then return nil end
  if GetSpecializationInfoByID then
    local id, name, _, icon, role, classFile = GetSpecializationInfoByID(specID)
    if id then return name, icon, role, classFile end
  end
  return nil
end

-- The player's own current spec ID.
-- 11.x added C_SpecializationInfo.GetSpecialization / GetSpecializationInfo and
-- deprecated the globals; the C_SpecializationInfo path is confirmed present in 12.1.0 (build 69933) by /ens verify.
function API.GetPlayerSpecID()
  local index
  if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
    index = C_SpecializationInfo.GetSpecialization()
  elseif GetSpecialization then
    index = GetSpecialization()
  end
  if not index or index == 0 then return nil end
  local id
  if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
    id = C_SpecializationInfo.GetSpecializationInfo(index)
  elseif GetSpecializationInfo then
    id = GetSpecializationInfo(index)
  end
  if type(id) == "number" and id > 0 then return id end
  return nil
end

function API.InCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

---------------------------------------------------------------------------
-- Callbacks (tiny pub/sub so modules never reach into each other's frames)
---------------------------------------------------------------------------
local listeners = {}
function ns:On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end
function ns:Fire(event, ...)
  local list = listeners[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
end

-- The addon's emblem (Media/LogoMark), also used inline in chat as a text-height icon.
ns.LOGO_MARK = "Interface\\AddOns\\Ensemble\\Media\\LogoMark"
-- Auto-fill's "group ready" chime: our own, synthesized for Ensemble (1.4.1), not game audio.
ns.READY_SOUND = "Interface\\AddOns\\Ensemble\\Media\\GroupReady.ogg"
-- Prefix on lines printed to your own chat: the emblem, then "Ensemble:" in white. Party-chat
-- posts never use it (they're plain text; the game strips colors and icons from player chat).
ns.CHAT_PREFIX = "|T" .. ns.LOGO_MARK .. ":0|t |cffffffffEnsemble:|r "

function ns:Print(msg)
  local out = ns.CHAT_PREFIX .. tostring(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(out) else print(out) end
end

---------------------------------------------------------------------------
-- SavedVariables
---------------------------------------------------------------------------
ns.NUM_SLOTS = 5
-- Role-based slot layout (assumption: the spec allows either free 5-slot or role-based;
-- role-based is used because it matches how M+ groups are actually formed).
ns.SLOT_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }

ns.DEFAULTS = {
  schema = ns.SCHEMA_VERSION,
  settings = {
    compact = false,
    -- Generic (Feature 4) checks the user can switch off.
    checks = {
      buffs = true, interrupts = true, brez = true, lust = true,
      dispels = true, cc = true, utility = true,
    },
    -- Dungeon (Feature 5) requirement categories the user can switch off.
    dungeonCategories = { interrupts = true, dispels = true, stops = true, tank = true, other = true, affixes = true },
    -- Count talent-dependent sources (e.g. Cauterizing Flame) as providers.
    countTalentSources = true,
    liveAutoDungeon = true,
    -- Applicant-fit panel docked beside the Group Finder while you host a listing.
    applicantPanel = true,
    -- Where that panel sits: docked beside the Group Finder, or wherever the user dragged it.
    -- side: "below" (under the Group Finder's bottom tabs; clear of add-ons that attach a
    -- panel to its right edge, e.g. Raider.IO's profile) or "right".
    finderPanel = { docked = true, side = "below", point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = 0 },
    -- Open the window on the Applicants tab when you list a Mythic+ group.
    autoOpenOnListing = true,
    -- Applicants tab: sort order ("fit", "rating", "ilvl") and whether to hide Poor fits.
    applicantView = { sort = "fit", hidePoor = false },
    -- Learning mode: plain-language explanations of needs and mechanic notes.
    explain = true,
    -- Add fit ratings to the Group Finder's own applicant tooltips.
    finderTooltip = true,
    -- Groups you could apply to (Group Finder search results): a marker on each listing and
    -- a "your fit" breakdown in its tooltip. listingMarker: "stripe" (colored edge) or "off".
    listingMarker = "stripe",
    listingHidePoor = false,    -- no marker on groups rated Poor for you
    listingTooltip = true,      -- "your fit" lines in the listing tooltip
    applyLine = true,           -- a line about you to paste into the Sign Up note
    -- Needs you don't care about (capability key -> true): left out of every check, rating
    -- and plan. hideLowSeverity drops "low" dungeon requirements altogether.
    ignoredNeeds = {},
    hideLowSeverity = false,
    -- Party-chat posts: "full" (every row) or "short" (the essentials, one line).
    chatStyle = "full",
    -- Record every Mythic+ key you run (History tab).
    history = true,
    minimap = { hide = false, angle = 215 },
    window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, width = 952, height = 630, locked = false },
    -- Text size in percent (80-125), independent of the window size.
    textSize = 100,
    -- Boss-card window: opens in Season dungeons, follows the current boss.
    bossWindow = { autoOpen = true, showAll = false, fadeInCombat = true, locked = false, fontSize = 12 },
    -- Composition and Plan: "auto" (your party when grouped or listed, else the planner),
    -- "planner" or "party".
    compMode = "auto",
    -- While you host: "panel" shows your best-fit applicants under the Composition slots,
    -- "list" keeps the usual left column.
    compApplicants = "panel",
    -- Dungeon tab: whose notes to show, "ALL" | "TANK" | "HEAL" | "DPS".
    walkRole = "ALL",
    -- Accent color of the window. `classColor` follows the player's class color.
    theme = { hex = "7EB7FF", classColor = false },
    -- Fill group (Applicants tab): how complete the group must be ("auto" = match the key
    -- level, or "relaxed" / "standard" / "strict"), who can be invited (each filter's source:
    -- "suggested" for the key, "listing" = your listing's minimum, "custom" = `value`), and
    -- Auto-fill (armed per listing; it only finds a group and tells you).
    fill = {
      level = "auto",
      rating = { on = true, source = "suggested", value = 2500 },
      ilvl = { on = true, source = "suggested", value = 300 },
      skipLeavers = true,
      skipNoData = true,
      autoArm = false,
      sound = true,
      soundChoice = "chime",   -- "chime" (Ensemble's) or "readycheck" (the game's)
      popup = true,
      wait = 15,
      preferTimed = false,     -- past keys (1.5.0): prefer players you've timed with
      failedWith = "off",      -- players you've failed with: "off", "lower" (priority) or "skip"
    },
    -- Past keys together (1.5.0): what counts as a failed key with someone, and whether pick
    -- ratings show it. failed: "overtime", "abandoned" (over time and abandoned) or "abandonedHigh"
    -- (over time, and abandoned keys from the Strict threshold, +12, up).
    pastKeys = { failed = "overtime", rating = false },
  },
  -- Builder tab dungeon pick: "AUTO" follows your own keystone, "NONE" = generic only,
  -- or a dungeon key. Resets to "AUTO" when you get a keystone for a different dungeon.
  selectedDungeon = "AUTO",
  currentComp = { 0, 0, 0, 0, 0 }, -- spec IDs per slot, 0 = empty
  savedComps = {},              -- array of { name, slots = {5 specIDs}, dungeon, created }
  lastTab = "composition",
  -- Bloodlust timing per dungeon key: { { at = "b1"|"t2", note }, ... } (boss N, or the trash
  -- before boss N). Missing = the default from DungeonData.LUST.
  lust = {},
  -- Boss order per dungeon key, where the dungeon data allows a choice (DungeonData.BOSS_ORDER):
  -- boss indexes first to last. Missing = the guides' order.
  bossOrder = {},
  -- Fill group musts per dungeon key, only what differs from the boss-card defaults:
  -- { lust = false|nil, on = { [requirement id] = true|false } }.
  fillMusts = {},
  history = {},                 -- recorded runs, newest first (History.lua)
  -- Saved players and reserved slots (SavedPlayers.lua, 1.5.0).
  savedPlayers = {},            -- { { full = "Name-Realm", specs = { specID, ... }, default = specID } }
  reserved = { seenListed = false, list = {} },   -- list: { { specID, full = "Name-Realm"|nil } }
}

-- Migrations: index N upgrades a DB at schema N-1 to schema N. None are needed yet (schema 4
-- is the first released layout); add entries here when the saved structure changes, and
-- never edit old ones.
local MIGRATIONS = {}

local function SanitizeDB(db)
  if type(db.currentComp) ~= "table" then db.currentComp = { 0, 0, 0, 0, 0 } end
  for i = 1, ns.NUM_SLOTS do
    if type(db.currentComp[i]) ~= "number" then db.currentComp[i] = 0 end
  end
  if type(db.savedComps) ~= "table" then db.savedComps = {} end
  for i = #db.savedComps, 1, -1 do
    local c = db.savedComps[i]
    if type(c) ~= "table" or type(c.slots) ~= "table" then
      table.remove(db.savedComps, i)
    else
      c.name = tostring(c.name or ("Comp " .. i))
      for s = 1, ns.NUM_SLOTS do
        if type(c.slots[s]) ~= "number" then c.slots[s] = 0 end
      end
    end
  end
  if type(db.selectedDungeon) ~= "string" then db.selectedDungeon = "AUTO" end
  if type(db.lust) ~= "table" then db.lust = {} end
  for dk, uses in pairs(db.lust) do
    if type(uses) ~= "table" then db.lust[dk] = nil
    else
      -- Uses saved at a Mythic Dungeon Tools route pull ("p<N>", up to 1.2.1) are dropped: route
      -- tracking was removed in 1.3.0. A plan left empty only by that falls back to the
      -- dungeon's default; a plan the player emptied on purpose stays empty.
      local droppedPull = false
      for i = #uses, 1, -1 do
        local u = uses[i]
        if type(u) == "table" and type(u.at) == "string" and u.at:match("^p%d+$") then
          table.remove(uses, i); droppedPull = true
        elseif type(u) ~= "table" or type(u.at) ~= "string" or not u.at:match("^[tb]%d+$") then table.remove(uses, i)
        elseif u.note ~= nil and type(u.note) ~= "string" then u.note = nil end
      end
      if droppedPull and #uses == 0 then db.lust[dk] = nil end
    end
  end
  -- Boss orders that no longer fit the data (a season change, a data fix) are dropped.
  if type(db.bossOrder) ~= "table" then db.bossOrder = {} end
  for dk, order in pairs(db.bossOrder) do
    if not (ns.Dungeons and ns.Dungeons.ValidBossOrder and ns.Dungeons:ValidBossOrder(dk, order)) then db.bossOrder[dk] = nil end
  end
  -- Fill group musts: requirement IDs as keys, booleans as values; dungeons that left the data go.
  if type(db.fillMusts) ~= "table" then db.fillMusts = {} end
  for dk, m in pairs(db.fillMusts) do
    if type(m) ~= "table" or not (ns.Dungeons and ns.Dungeons.list[dk]) then db.fillMusts[dk] = nil
    else
      if m.lust ~= nil and type(m.lust) ~= "boolean" then m.lust = nil end
      if type(m.on) ~= "table" then m.on = {} end
      for id, v in pairs(m.on) do if type(id) ~= "string" or type(v) ~= "boolean" then m.on[id] = nil end end
    end
  end
  -- How the last fills went on this game build ("one invite per click" once it's seen that the
  -- game takes only one per click).
  if db.fillInvite ~= nil and (type(db.fillInvite) ~= "table" or type(db.fillInvite.build) ~= "string") then db.fillInvite = nil end
  if type(db.settings) == "table" and type(db.settings.fill) == "table" then
    local f, d = db.settings.fill, ns.DEFAULTS.settings.fill
    if f.level ~= "auto" and f.level ~= "relaxed" and f.level ~= "standard" and f.level ~= "strict" then f.level = d.level end
    for _, k in ipairs({ "rating", "ilvl" }) do
      if type(f[k]) ~= "table" then f[k] = Util.DeepCopy(d[k]) end
      local c = f[k]
      if c.source ~= "suggested" and c.source ~= "listing" and c.source ~= "custom" then c.source = d[k].source end
      c.value = tonumber(c.value) or d[k].value
      if c.on ~= false then c.on = true end
    end
    f.wait = math.max(0, math.min(120, tonumber(f.wait) or d.wait))
    if f.soundChoice ~= "chime" and f.soundChoice ~= "readycheck" then f.soundChoice = d.soundChoice end
    f.preferTimed = f.preferTimed == true
    if f.failedWith ~= "off" and f.failedWith ~= "lower" and f.failedWith ~= "skip" then f.failedWith = d.failedWith end
  end
  -- Past keys together (1.5.0).
  if type(db.settings) == "table" then
    local st = db.settings
    if type(st.pastKeys) ~= "table" then st.pastKeys = Util.DeepCopy(ns.DEFAULTS.settings.pastKeys) end
    local pk = st.pastKeys
    if pk.failed ~= "overtime" and pk.failed ~= "abandoned" and pk.failed ~= "abandonedHigh" then pk.failed = "overtime" end
    pk.rating = pk.rating == true
    if type(st.applicantView) == "table" then
      local so = st.applicantView.sort
      if so ~= "fit" and so ~= "rating" and so ~= "ilvl" and so ~= "past" then st.applicantView.sort = "fit" end
    end
  end
  -- Saved players (1.5.0): a name and at least one known spec; the default one of them.
  local UD = ns.UD
  local function SpecOK(id) return type(id) == "number" and UD and UD:GetSpec(id) ~= nil end
  if type(db.savedPlayers) ~= "table" then db.savedPlayers = {} end
  local seenP, keptP = {}, {}
  for _, p in ipairs(db.savedPlayers) do
    local keep = type(p) == "table" and type(p.full) == "string" and p.full ~= "" and type(p.specs) == "table"
    if keep then
      for j = #p.specs, 1, -1 do if not SpecOK(p.specs[j]) then table.remove(p.specs, j) end end
      keep = #p.specs > 0 and not seenP[p.full:lower()]   -- the first of two same names stays
    end
    if keep then
      seenP[p.full:lower()] = true
      local okDefault = false
      for _, id in ipairs(p.specs) do if id == p.default then okDefault = true end end
      if not okDefault then p.default = p.specs[1] end
      keptP[#keptP + 1] = p
    end
  end
  db.savedPlayers = keptP
  -- Reserved slots (1.5.0): a known spec, an optional name.
  if type(db.reserved) ~= "table" then db.reserved = { seenListed = false, list = {} } end
  if type(db.reserved.list) ~= "table" then db.reserved.list = {} end
  db.reserved.seenListed = db.reserved.seenListed == true
  for i = #db.reserved.list, 1, -1 do
    local r = db.reserved.list[i]
    if type(r) ~= "table" or not SpecOK(r.specID) then table.remove(db.reserved.list, i)
    elseif r.full ~= nil and type(r.full) ~= "string" then r.full = nil end
  end
  while #db.reserved.list > ns.NUM_SLOTS do table.remove(db.reserved.list) end
  -- Run history: boss splits (1.5.0) need a numeric encounter; a full name is a string.
  if type(db.history) ~= "table" then db.history = {} end
  local function CleanRun(run)
    if type(run.splits) == "table" then
      for i = #run.splits, 1, -1 do
        local sp = run.splits[i]
        if type(sp) ~= "table" or type(sp.enc) ~= "number" then table.remove(run.splits, i)
        else
          if sp.t ~= nil and type(sp.t) ~= "number" then sp.t = nil end
          if sp.deaths ~= nil and type(sp.deaths) ~= "number" then sp.deaths = nil end
        end
      end
    elseif run.splits ~= nil then run.splits = nil end
    if type(run.comp) == "table" then
      for _, m in ipairs(run.comp) do
        if type(m) == "table" and m.full ~= nil and type(m.full) ~= "string" then m.full = nil end
      end
    end
  end
  for i = #db.history, 1, -1 do
    if type(db.history[i]) ~= "table" then table.remove(db.history, i) else CleanRun(db.history[i]) end
  end
  if type(db.activeRun) == "table" then CleanRun(db.activeRun) elseif db.activeRun ~= nil then db.activeRun = nil end
  -- Settings that no longer exist (1.3.0: the Mythic Dungeon Tools route switch).
  if type(db.settings) == "table" then db.settings.routePlan = nil end
end

function ns:InitDB()
  if type(EnsembleDB) ~= "table" then EnsembleDB = {} end
  local db = EnsembleDB
  local from = tonumber(db.schema) or 0
  if from > ns.SCHEMA_VERSION then
    -- Saved data from a NEWER addon version (user downgraded). Don't migrate backwards;
    -- just fill defaults so this version can run.
    self:Print("Saved data is from a newer Ensemble version; some settings may be ignored.")
  else
    for v = from + 1, ns.SCHEMA_VERSION do
      if MIGRATIONS[v] then
        local ok, err = pcall(MIGRATIONS[v], db)
        if not ok then self:Print("Migration to schema " .. v .. " failed: " .. tostring(err)) end
      end
    end
    db.schema = ns.SCHEMA_VERSION
  end
  Util.MergeDefaults(db, ns.DEFAULTS)
  SanitizeDB(db)
  self.db = db
end

-- What a full reset wipes, in plain words (the /ens reset prompt and Settings > Data say it).
ns.RESET_WIPES = "saved comps, the planner comp, every setting, run history, saved players and reserved slots, boss-card edits, Bloodlust timing, boss order, Fill group musts and the error log"

function ns:ResetDB()
  EnsembleDB = Util.DeepCopy(ns.DEFAULTS)
  self.db = EnsembleDB
  -- Session state that would otherwise outlive the reset: assignments chosen by hand and the
  -- boss window's progress through the current key.
  if ns.Assignments and ns.Assignments.ClearOverrides then ns.Assignments:ClearOverrides() end
  local BC = ns.BossCards
  if BC and BC.state then
    BC.state.killed = {}
    if BC.state.dk then BC:Show(BC:Order(BC.state.dk)[1] or 1) end   -- back to the first boss (saved to the fresh data)
  end
  self:Fire("SETTINGS_CHANGED")
  self:Fire("COMP_CHANGED", "reset")
  self:Fire("DUNGEON_CHANGED")
end

---------------------------------------------------------------------------
-- Runtime state (not saved)
---------------------------------------------------------------------------
ns.state = {
  mode = "builder",     -- "builder" | "live"
  autoDungeon = nil,    -- key detected from the Group Finder listing or the dungeon you're in (live only)
  autoSource = nil,     -- "listing" | "zone"
  liveDungeon = "AUTO", -- Live/Applicants pick for this session: "AUTO", "NONE" or a key
  keyLevelOverride = nil, -- session-only keystone level set on the Applicants tab
}

---------------------------------------------------------------------------
-- Dungeon detection
-- C_MythicPlus.GetOwnedKeystoneChallengeMapID / C_ChallengeMode.GetMapUIInfo confirmed in
-- 12.1.0 (build 69933) by /ens verify. C_ChallengeMode.GetActiveChallengeMapID and
-- GetInstanceInfo are long-standing retail APIs; all calls are pcall-guarded.
---------------------------------------------------------------------------
local mapKeyCache = {}
function ns:DungeonFromMapID(mapID)
  if not mapID or mapID == 0 then return nil end
  if mapKeyCache[mapID] ~= nil then return mapKeyCache[mapID] or nil end
  local key = ns.Dungeons:KeyForChallengeMap(mapID)
  if key then return key end
  if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
    local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if ok and name then key = ns.Dungeons:FindKey(name) end
  end
  if key then mapKeyCache[mapID] = key end   -- don't cache misses: map data may not be loaded yet
  return key
end

-- The dungeon of the keystone in your bags, and its level.
function ns:OwnKeystoneDungeon()
  if not (C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID) then return nil end
  local ok, mapID = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
  if not ok then return nil end
  local key = self:DungeonFromMapID(mapID)
  if not key then return nil end
  local level
  if C_MythicPlus.GetOwnedKeystoneLevel then
    local okL, l = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
    if okL and type(l) == "number" and l > 0 then level = l end
  end
  return key, level
end

-- The Season dungeon you're standing in (an active key first, then the instance name).
function ns:CurrentInstanceDungeon()
  if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
    local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
    local key = ok and self:DungeonFromMapID(mapID)
    if key then return key end
  end
  if GetInstanceInfo then
    local ok, name, instanceType, _, _, _, _, _, instanceMapID = pcall(GetInstanceInfo)  -- 8th return = instanceID
    if ok and instanceType == "party" then
      return ns.Dungeons:KeyForInstanceMap(instanceMapID) or (name and ns.Dungeons:FindKey(name))
    end
  end
  return nil
end

-- live: true = Live/Applicants context, false = Builder context, nil = the window's current mode.
local function IsLive(self, live)
  if live == nil then return self.state.mode == "live" end
  return live and true or false
end

-- The dungeon the analysis should use right now, and why:
--   "manual"   - picked in the dropdown (or a loaded saved comp)
--   "auto"     - Live/Applicants: your Group Finder listing, else the dungeon you're in
--                (ns.state.autoSource says which)
--   "keystone" - Builder: the keystone in your bags
-- `live` = true forces live semantics (used by the Group Finder applicant panel, which
-- is live regardless of which tab the main window is on).
function ns:GetEffectiveDungeon(live)
  if not self.db then return nil, nil end
  local auto = self.db.settings.liveAutoDungeon ~= false
  if IsLive(self, live) then
    local pick = self.state.liveDungeon or "AUTO"
    if pick == "NONE" then return nil, "manual" end
    if pick ~= "AUTO" then return pick, "manual" end
    if auto and self.state.autoDungeon then return self.state.autoDungeon, "auto" end
    return nil, nil
  end
  local pick = self.db.selectedDungeon or "AUTO"
  if pick == "NONE" then return nil, "manual" end
  if pick ~= "AUTO" then return pick, "manual" end
  if auto then
    local key = self:OwnKeystoneDungeon()
    if key then return key, "keystone" end
  end
  return nil, nil
end

-- What "AUTO" would resolve to in a context (for the dropdown's Auto entry).
function ns:AutoDungeon(live)
  if self.db.settings.liveAutoDungeon == false then return nil end
  if IsLive(self, live) then return self.state.autoDungeon, self.state.autoSource end
  local key, level = self:OwnKeystoneDungeon()
  return key, key and "keystone", level
end

-- The pick for the current context. `key` = "AUTO", "NONE" or a dungeon key.
-- `live` nil = whichever context the window is in.
function ns:SetManualDungeon(key, live)
  if key ~= "NONE" and key ~= "AUTO" and not (ns.Dungeons and ns.Dungeons.list[key]) then key = "NONE" end
  live = IsLive(self, live)
  if live then self.state.liveDungeon = key else self.db.selectedDungeon = key end
  self:Fire("DUNGEON_CHANGED")
end

function ns:GetDungeonPick(live)
  if IsLive(self, live) then return self.state.liveDungeon or "AUTO" end
  return self.db.selectedDungeon or "AUTO"
end

-- Keystone watcher: when the key in your bags changes dungeon (new key after a run,
-- a reroll), the Builder goes back to following it.
local keyWatcher = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE" }) do
  pcall(keyWatcher.RegisterEvent, keyWatcher, ev)
end
function ns:CheckKeystoneChange()
  if not self.db then return end
  local key = self:OwnKeystoneDungeon()
  if not key or key == self.db.lastKeystoneDungeon then return end
  local had = self.db.lastKeystoneDungeon
  self.db.lastKeystoneDungeon = key
  if had then self.db.selectedDungeon = "AUTO" end   -- a NEW key: follow it again
  self:Fire("DUNGEON_CHANGED")
end
keyWatcher:SetScript("OnEvent", function(_, event)
  ns:CheckKeystoneChange()
  if event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_MAPS_UPDATE" then ns:CheckSeason() end
end)

---------------------------------------------------------------------------
-- Season-change warning: the game's current Mythic+ dungeon list (challenge map IDs)
-- against the addon's data. Warns in chat once per distinct change and shows a banner in
-- Dungeon readiness until the data matches again.
---------------------------------------------------------------------------
function ns:CheckSeason()
  if not self.db or not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
  local ok, maps = pcall(C_ChallengeMode.GetMapTable)
  if not ok or type(maps) ~= "table" or #maps == 0 then
    -- Not loaded yet: ask for it; CHALLENGE_MODE_MAPS_UPDATE calls back here.
    -- Throttled so an empty answer can't loop through CHALLENGE_MODE_MAPS_UPDATE.
    local now = GetTime and GetTime() or 0
    if C_MythicPlus and C_MythicPlus.RequestMapInfo and (not self.state.mapRequestAt or now - self.state.mapRequestAt > 30) then
      self.state.mapRequestAt = now
      pcall(C_MythicPlus.RequestMapInfo)
    end
    return
  end
  local DD = ns.Dungeons
  local inGame, newMaps, gone = {}, {}, {}
  for _, id in ipairs(maps) do
    inGame[id] = true
    if not DD:KeyForChallengeMap(id) then
      local okN, name = pcall(C_ChallengeMode.GetMapUIInfo, id)
      newMaps[#newMaps + 1] = (okN and name) or ("map " .. id)
    end
  end
  for _, key in ipairs(DD.order) do
    if not inGame[DD.CHALLENGE_MAP_IDS[key]] then gone[#gone + 1] = DD.list[key].name end
  end
  if #newMaps == 0 and #gone == 0 then
    self.state.seasonMismatch = nil
    self.db.seasonWarnedSig = nil
    return
  end
  table.sort(maps)
  local sig = table.concat(maps, ",")
  self.state.seasonMismatch = { newMaps = newMaps, gone = gone }
  if self.db.seasonWarnedSig ~= sig then
    self.db.seasonWarnedSig = sig
    self:Print(self:SeasonWarningText())
  end
  self:Fire("DUNGEON_CHANGED")
end

function ns:SeasonWarningText()
  local m = self.state.seasonMismatch
  if not m then return nil end
  local parts = {}
  if #m.newMaps > 0 then parts[#parts + 1] = "new in the game: " .. table.concat(m.newMaps, ", ") end
  if #m.gone > 0 then parts[#parts + 1] = "no longer in rotation: " .. table.concat(m.gone, ", ") end
  return "The Mythic+ dungeon list has changed (" .. table.concat(parts, "; ")
    .. "). Dungeon checks may be out of date until the addon's data is updated."
end

---------------------------------------------------------------------------
-- Share strings (export/import a comp). Plain-text and versioned, in the spirit of a
-- WeakAuras import string but human-readable:  ENS1:<name>:<dungeonKey>:<5 specIDs>:<checksum>
---------------------------------------------------------------------------
local Share = {}
ns.Share = Share

local function Checksum(s)
  local sum = 0
  for i = 1, #s do sum = (sum * 31 + s:byte(i)) % 999983 end
  return sum
end

function Share.Encode(name, slots, dungeonKey)
  name = Util.Trim(tostring(name or "Comp")):gsub("[:|\n\r]", " ")
  local ids = {}
  for i = 1, ns.NUM_SLOTS do ids[i] = tostring(tonumber(slots and slots[i]) or 0) end
  local body = string.format("ENS1:%s:%s:%s", name, dungeonKey or "NONE", table.concat(ids, ","))
  return body .. ":" .. Checksum(body)
end

-- Returns { name, slots, dungeon } or nil, errorMessage
function Share.Decode(str)
  str = Util.Trim(str or "")
  local body, sum = str:match("^(ENS1:.*):(%d+)$")
  if not body then return nil, "Not an Ensemble share string." end
  if Checksum(body) ~= tonumber(sum) then return nil, "String is damaged (checksum mismatch)." end
  local name, dungeon, idList = body:match("^ENS1:(.-):([%w_]+):([%d,]+)$")
  if not name then return nil, "Malformed string." end
  local slots, i = {}, 0
  for id in idList:gmatch("%d+") do
    i = i + 1
    local n = tonumber(id)
    if i <= ns.NUM_SLOTS then slots[i] = (ns.UD and ns.UD:GetSpec(n)) and n or 0 end
  end
  for s = i + 1, ns.NUM_SLOTS do slots[s] = 0 end
  if dungeon ~= "NONE" and not (ns.Dungeons and ns.Dungeons.list[dungeon]) then dungeon = "NONE" end
  return { name = name ~= "" and name or "Imported", slots = slots, dungeon = dungeon }
end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    ns:InitDB()
    self:UnregisterEvent("ADDON_LOADED")
    ns:Fire("DB_READY")
  elseif event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    ns:Fire("LOGIN")
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Only what has no button in the window, or must work when the window can't help: everything
-- else (tabs, planner or party, dungeon, lock, text size, panel, glossary, sources, tour, best key,
-- boss window) is done in the interface.
local HELP = {
  "/ens - open or close the window",
  "/ens minimap - show or hide the minimap button",
  "/ens verify - check this client and print a report to paste back",
  "/ens verify season - the game's dungeon pool, bosses, ability IDs and affixes (for updates)",
  "/ens report - a copyable bug report (version, setup, recent errors) to paste with your issue",
  "/ens reset confirm - wipe all Ensemble data: " .. ns.RESET_WIPES,
  "/ens help - this list",
}
ns.SLASH_HELP = HELP

SLASH_ENSEMBLE1 = "/ens"
SlashCmdList["ENSEMBLE"] = function(msg)
  if not ns.db then return end
  local cmd, rest = Util.Trim(msg or ""):match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if ns.UI then ns.UI:Toggle() end
  elseif cmd == "minimap" then
    ns.db.settings.minimap.hide = not ns.db.settings.minimap.hide
    ns:Fire("SETTINGS_CHANGED")
  elseif cmd == "verify" then
    if ns.Verify then
      if rest:lower() == "season" then ns.Verify:RunSeason() else ns.Verify:Run() end
    end
  elseif cmd == "report" then
    if ns.Report then ns.Report:Run() end
  elseif cmd == "reset" then
    if rest:lower() == "confirm" then
      ns:ResetDB(); ns:Print("All Ensemble data reset.")
    else
      ns:Print("This wipes " .. ns.RESET_WIPES .. ". It can't be undone. Type |cffffff00/ens reset confirm|r to proceed.")
    end
  else
    for i = 1, #HELP do ns:Print(HELP[i]) end
  end
end

---------------------------------------------------------------------------
-- Addon Compartment (the addon drop-down on the minimap cluster, 10.1+).
-- These names are referenced from the .toc, so they must be globals.
---------------------------------------------------------------------------
function Ensemble_OnAddonCompartmentClick(_, button)
  if not ns.UI then return end
  if button == "RightButton" then ns.UI:Show("settings") else ns.UI:Toggle() end
end

function Ensemble_OnAddonCompartmentEnter(_, menuButtonFrame)
  if not GameTooltip then return end
  GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
  -- Same header as the minimap tooltip: name in white, subtitle in the accent color.
  local UI = ns.UI
  GameTooltip:AddLine((UI and UI.NAME) or "Ensemble", 1, 1, 1)
  local acc = UI and UI.Kit and UI.Kit.C and UI.Kit.C.accent
  if UI and UI.SUBTITLE then
    if acc then GameTooltip:AddLine(UI.SUBTITLE, acc[1], acc[2], acc[3])
    else GameTooltip:AddLine(UI.SUBTITLE, 0.49, 0.72, 1) end
  end
  GameTooltip:AddLine("Left-click: toggle window", 1, 1, 1)
  GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
  GameTooltip:Show()
end

function Ensemble_OnAddonCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end
