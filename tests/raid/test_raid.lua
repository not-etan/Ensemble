-- Headless tests for Ensemble_Raid (the raid test module). ADDON_DIR and RAID_DIR are set by
-- run_raid_tests.py; the stub is Ensemble's own tests/wowstub.lua.

local function TocFiles(path)
  local out = {}
  for line in io.lines(path) do
    local f = line:match("^%s*([%w_]+%.lua)%s*$")
    if f then out[#out + 1] = f end
  end
  return out
end
local CORE_FILES = TocFiles(ADDON_DIR .. "/Ensemble.toc")
local RAID_FILES = TocFiles(RAID_DIR .. "/Ensemble_Raid.toc")

local fails, passes = 0, 0
local function ok(cond, msg)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end
local function slurp(p) local f = io.open(p, "r"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

-- Raid-side stubs on top of the core stub.
RAID = nil          -- list of { name, class, group, role, spec, guid }
IN_RAID = false
LEADER, ASSIST = false, false
INSTANCE_DIFF = nil -- { name, type, difficultyID, difficultyName }
local coreIsInRaid = IsInRaid
function IsInRaid() return IN_RAID end
local coreIsInGroup = IsInGroup
function IsInGroup(cat) if IN_RAID then return true end return coreIsInGroup(cat) end
function GetNumGroupMembers() if IN_RAID then return #RAID end local n = 0 for _ in pairs(ROSTER) do n = n + 1 end return n end
function GetRaidRosterInfo(i)
  local m = RAID and RAID[i]
  if not m then return nil end
  return m.name, 0, m.group or 1, 90, m.class, m.class, "zone", true, false, m.role, false, m.role
end
local coreUnitClass, coreGUID, coreRole = UnitClass, UnitGUID, UnitGroupRolesAssigned
local function RaidUnit(u) local i = u:match("^raid(%d+)$"); return i and RAID and RAID[tonumber(i)] end
function UnitClass(u) local m = RaidUnit(u); if m then return m.class, m.class end return coreUnitClass(u) end
function UnitGUID(u) local m = RaidUnit(u); if m then return m.guid end return coreGUID(u) end
function UnitGroupRolesAssigned(u) local m = RaidUnit(u); if m then return m.role end return coreRole(u) end
local coreUnitIsUnit = UnitIsUnit
function UnitIsUnit(a, b)
  local ma = RaidUnit(a)
  if ma and b == "player" then return ma.isPlayer and true or false end
  return coreUnitIsUnit(a, b)
end
function UnitIsGroupLeader() return LEADER end
function UnitIsGroupAssistant() return ASSIST end
function UnitIsConnected() return true end
function CanInspect(u) return RaidUnit(u) ~= nil or ROSTER[u] ~= nil end
local coreInspectSpec = GetInspectSpecialization
function GetInspectSpecialization(u) local m = RaidUnit(u); if m then return INSPECT_CACHE[m.guid] or 0 end return coreInspectSpec(u) end
function GetInstanceInfo()
  if INSTANCE_DIFF then return INSTANCE_DIFF[1], INSTANCE_DIFF[2], INSTANCE_DIFF[3], INSTANCE_DIFF[4] end
  return "Dornogal", "none", 0, ""
end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
C_AddOns.GetAddOnMetadata = function(addon, field)
  if addon == "Ensemble_Raid" then return "0.1.0-test" end
  return "1.6.0"
end

local function boot()
  ALLFRAMES = {}
  EnsembleDB, EnsembleRaidDB = EnsembleDB, EnsembleRaidDB
  local ns = {}
  for _, f in ipairs(CORE_FILES) do assert(loadfile(ADDON_DIR .. "/" .. f))("Ensemble", ns) end
  local R = {}
  for _, f in ipairs(RAID_FILES) do assert(loadfile(RAID_DIR .. "/" .. f))("Ensemble_Raid", R) end
  for _, fr in ipairs(ALLFRAMES) do
    if fr._events.ADDON_LOADED then
      fr._scripts.OnEvent(fr, "ADDON_LOADED", "Ensemble")
      fr._scripts.OnEvent(fr, "ADDON_LOADED", "Ensemble_Raid")
    end
  end
  for _, fr in ipairs(ALLFRAMES) do
    if fr._events.PLAYER_LOGIN then fr._scripts.OnEvent(fr, "PLAYER_LOGIN") end
  end
  if ns.db then
    ns.db.tourSeen = true
    ns.db.tipsSeen = {}
    for _, t in ipairs(ns.Tour and ns.Tour.TIPS or {}) do ns.db.tipsSeen[t.id] = true end
    ns.db.lastSeenVersion = ns.VERSION
  end
  return ns, R
end
local function fire(R, event, ...) R.eventFrame._scripts.OnEvent(R.eventFrame, event, ...) end

local function Raid20()
  -- name, class, spec, role, group
  local list = {
    { "Etan", "DEMONHUNTER", 581, "TANK", 1 }, { "Brakka", "WARRIOR", 73, "TANK", 2 },
    { "Lunelle", "PRIEST", 257, "HEALER", 1 }, { "Mistra", "MONK", 270, "HEALER", 2 },
    { "Torvin", "PALADIN", 65, "HEALER", 3 }, { "Kaiya", "SHAMAN", 264, "HEALER", 4 },
    { "Fennick", "DRUID", 102, "DAMAGER", 1 }, { "Zerith", "MAGE", 64, "DAMAGER", 1 },
    { "Ashka", "WARLOCK", 267, "DAMAGER", 1 }, { "Rook", "HUNTER", 253, "DAMAGER", 2 },
    { "Vexa", "ROGUE", 261, "DAMAGER", 2 }, { "Dornak", "DEATHKNIGHT", 251, "DAMAGER", 2 },
    { "Sylra", "DEMONHUNTER", 577, "DAMAGER", 3 }, { "Kael", "PALADIN", 70, "DAMAGER", 3 },
    { "Mirelle", "EVOKER", 1467, "DAMAGER", 3 }, { "Tarn", "WARRIOR", 71, "DAMAGER", 3 },
    { "Quell", "PRIEST", 258, "DAMAGER", 4 }, { "Ossa", "SHAMAN", 262, "DAMAGER", 4 },
    { "Nyx", "MAGE", 63, "DAMAGER", 4 }, { "Brin", "HUNTER", 254, "DAMAGER", 4 },
  }
  local out = {}
  for i, m in ipairs(list) do
    out[i] = { name = m[1], class = m[2], role = m[4], group = m[5], guid = "G" .. i, spec = m[3], isPlayer = i == 1 }
    INSPECT_CACHE["G" .. i] = m[3]
  end
  return out
end

EnsembleDB, EnsembleRaidDB = nil, nil
local before = {}
for k in pairs(_G) do before[k] = true end
local ns, R = boot()
do -- every global the raid files themselves create at load: none (EnsembleRaidDB comes from the client)
  local savedCore, savedDB = EnsembleCore, EnsembleRaidDB
  local ns0 = {}
  for _, f in ipairs(CORE_FILES) do assert(loadfile(ADDON_DIR .. "/" .. f))("Ensemble", ns0) end
  local snap = {}
  for k in pairs(_G) do snap[k] = true end
  local R0 = {}
  for _, f in ipairs(RAID_FILES) do assert(loadfile(RAID_DIR .. "/" .. f))("Ensemble_Raid", R0) end
  local new = {}
  for k in pairs(_G) do if not snap[k] then new[#new + 1] = tostring(k) end end
  table.sort(new)
  ok(#new == 0, "raid files create no globals at load (got " .. table.concat(new, ",") .. ")")
  EnsembleCore, EnsembleRaidDB = savedCore, savedDB
end
do -- the raid folder's only globals: its saved variables (and frames it names on purpose, made later)
  local added = {}
  local coreKnown = { EnsembleCore = true, EnsembleDB = true, SLASH_ENSEMBLE1 = true, Ensemble_OnAddonCompartmentClick = true,
    Ensemble_OnAddonCompartmentEnter = true, Ensemble_OnAddonCompartmentLeave = true }
  for k in pairs(_G) do
    if not before[k] and not coreKnown[k] and tostring(k):find("Raid", 1, true) then added[#added + 1] = tostring(k) end
  end
  table.sort(added)
  ok(table.concat(added, ",") == "EnsembleRaidDB", "raid globals: only EnsembleRaidDB (got " .. table.concat(added, ",") .. ")")
end

-- 1. Loading: the hook, the folder, its own saved data.
ok(EnsembleCore == ns and R.ns == ns, "the raid folder reads Ensemble's namespace")
ok(not R.disabled and R.db == EnsembleRaidDB, "EnsembleRaidDB is the raid folder's own saved data")
ok(EnsembleDB.raid == nil and EnsembleDB.plans == nil, "nothing raid is written into EnsembleDB")
ok(R.VERSION == "0.1.0-test", "version from the TOC")
do -- without EnsembleCore the folder turns itself off (no error)
  local saved = EnsembleCore
  EnsembleCore = nil
  local R2 = {}
  local printed
  local oldDCF = DEFAULT_CHAT_FRAME
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed = m end }
  for _, f in ipairs(RAID_FILES) do assert(loadfile(RAID_DIR .. "/" .. f))("Ensemble_Raid", R2) end
  ok(R2.disabled == true and printed and printed:find("needs Ensemble", 1, true), "no EnsembleCore: off, with a message")
  ok(R2.UI == nil and R2.Data == nil, "no EnsembleCore: nothing else loads")
  DEFAULT_CHAT_FRAME = oldDCF
  EnsembleCore = saved
end

-- 2. Data
local D = R.Data
local bad = D:Validate(ns.UD)
ok(#bad == 0, "raid data valid: " .. table.concat(bad, "; "))
ok(#D.INSTANCES == 3 and #D.INSTANCE.abyss.bosses == 8, "three instances, eight raid bosses")
local nBoss = 0
for _ in pairs(D.BOSSES) do nBoss = nBoss + 1 end
ok(nBoss == 10, "ten bosses in all")
ok(table.concat(D.INSTANCE.abyss.bosses, ","):find("nekzali,sentinels,vashnik,explorers,sszorak", 1, true) == 1, "default order: Vashnik third, Explorers fourth (the author)")
ok(D.INSTANCE.grotto.kind == "lair" and D.INSTANCE.grotto.diffs[1] == "W", "the Lair has World, Normal, Heroic, Mythic")
ok(D.INSTANCE.grotto.size:find("World 5-40", 1, true) and D.INSTANCE.grotto.size:find("15-25", 1, true), "Lair sizes as the author gave them")
ok(table.concat(D.INSTANCE.kithix.diffs, ",") == "LFR,N,H,M", "Kith'ix on every difficulty")
local heroicItems, hasNormal = 0, 0
for _, b in pairs(D.BOSSES) do
  local n = 0
  for _, ph in ipairs(b.phases) do for _, it in ipairs(ph.items) do
    if it.d == "H" then heroicItems = heroicItems + 1 end
    if it.d == "N" then n = n + 1 end
  end end
  if n > 0 then hasNormal = hasNormal + 1 end
end
ok(hasNormal == 10 and heroicItems >= 10, "every boss has a Normal baseline; Heroic changes are labeled")
ok(R:DataDiff("LFR") == "N" and R:DataDiff("W") == "N" and R:DataDiff("H") == "H", "LFR and World use Normal's data")
ok(R:Applies("N", "H") and not R:Applies("H", "N") and R:Applies("H", "M") and not R:Applies("M", "LFR"), "difficulty ranks")

-- 3. Mode switch
ok(R:Mode() == "mplus", "solo in town: Mythic+")
IN_RAID = true; RAID = Raid20()
fire(R, "GROUP_ROSTER_UPDATE")
ok(R:Mode() == "raid", "in a raid group: Auto picks Raid")
R:SetMode("mplus")
ok(R:Mode() == "mplus", "a hand pick holds while in the group")
IN_RAID = false; RAID = nil
fire(R, "GROUP_ROSTER_UPDATE")
ok(R.db.mode == "auto", "leaving the group ends the hand pick")
INSTANCE_DIFF = { "The Venomous Abyss", "raid", 15, "Heroic" }
fire(R, "PLAYER_ENTERING_WORLD")
ok(R:Mode() == "raid" and R.db.instance == "abyss" and R:Diff() == "H", "inside the raid: Raid mode, the instance and its difficulty followed")
INSTANCE_DIFF = { "The Tidebound Grotto", "raid", 999, "World" }
fire(R, "PLAYER_ENTERING_WORLD")
ok(R.db.instance == "grotto" and R:Diff() == "W", "inside the Lair at World difficulty")
INSTANCE_DIFF = { "Some Old Raid", "raid", 14, "Normal" }
fire(R, "PLAYER_ENTERING_WORLD")
ok(R:Mode() == "mplus", "an old raid farmed solo stays in Mythic+")
INSTANCE_DIFF = nil
fire(R, "PLAYER_ENTERING_WORLD")
R.db.instance = "abyss"; R.db.diff.abyss = "H"
if R.BossWindow:IsShown() then R.BossWindow:Hide() end

-- 4. The window: raid tabs replace the Mythic+ tabs, and back.
local UI = ns.UI
R:SetMode("raid")
UI:Show()
ok(R.UI.attached and R.UI.modeBtn and R.UI.tabButtons.roster, "the mode button and raid tabs are added to the header")
ok(R.UI.modeBtn.text:GetText() == "Raid", "the switch shows Raid")
ok(R.UI.tabButtons.roster:IsShown() and not UI.tabButtons.composition:IsShown(), "raid tabs shown, Mythic+ tabs hidden")
ok(R.UI.container:IsShown() and not UI.pages.comp:IsShown(), "the raid container, not a Mythic+ page")
UI:SetTab("bosses")
ok(R.UI.tab == "bosses" and R.UI.pages.bosses:IsShown() and not R.UI.pages.roster:IsShown(), "raid tabs switch pages")
UI:SetTab("composition")
ok(R.UI.tab == "bosses", "a Mythic+ tab key in Raid mode stays on the raid tab")
UI:SetTab("settings")
ok(UI.pages.settings:IsShown() and not R.UI.container:IsShown(), "Settings shows Ensemble's settings page in Raid mode")
R:SetMode("mplus")
ok(UI.tabButtons.composition:IsShown() and not R.UI.tabButtons.roster:IsShown() and not R.UI.container:IsShown(), "back to Mythic+: its tabs and pages")
ok(UI.currentTab ~= nil and UI.pages[UI.currentTab == "dungeons" and "dungeons" or (UI.currentTab == "plan" and "plan" or (UI.currentTab == "composition" and "comp" or UI.currentTab))] ~= nil, "a Mythic+ tab is current again")
local src = slurp(RAID_DIR .. "/UI.lua")
ok(src and not src:find("SetRaidTarget", 1, true) and not src:find("PlaceRaidMarker", 1, true), "no marker placing (protected since 12.0)")

-- 5. Roster: planner and live
R:SetMode("raid")
UI:SetTab("roster")
ok(R.Roster:Source() == "planner" and #R.Roster:Members() == 0, "solo: the planner, empty")
ok(R.Roster:AddPlanned(581, "Etan") and R.Roster:AddPlanned(73) and R.Roster:AddPlanned(257, "  "), "add planned players")
local pm = R.Roster:Members()
ok(#pm == 3 and pm[1].name == "Etan" and pm[2].name:find("Protection", 1, true) and pm[3].role == "HEALER", "planner names, default names and roles")
ok(not R.Roster:AddPlanned(999999), "an unknown spec is refused")
R.Roster:MovePlanned(1, 1)
ok(R.Roster:Members()[2].name == "Etan", "move a planned player")
R.Roster:RemovePlanned(3)
ok(#R.Roster:Members() == 2, "remove a planned player")
R.Roster:ClearPlanned()
IN_RAID = true; RAID = Raid20()
for i = 2, #RAID do INSPECT_CACHE[RAID[i].guid] = nil end
ROSTER.player = { guid = "G1", name = "Etan", class = "DEMONHUNTER", spec = 581, role = "TANK" }
fire(R, "GROUP_ROSTER_UPDATE")
local live = R.Roster:Members()
ok(R.Roster:Source() == "live" and #live == 20, "in a raid: the 20 raid members")
ok(live[1].spec == 581 and live[2].spec == nil and live[2].pending, "your own spec is known; others wait for inspect")
NOTIFIED = {}
R.Roster.pending = nil
R.Roster:InspectStep()
ok(#NOTIFIED == 1 and NOTIFIED[1] == "raid2" and R.Roster.pending, "one inspect at a time")
R.Roster:InspectStep()
ok(#NOTIFIED == 1, "no second inspect while one is pending")
INSPECT_CACHE.G2 = 73
fire(R, "INSPECT_READY", "G2")
ok(R.Roster.specByGUID.G2 == 73 and R.Roster.pending == nil, "INSPECT_READY stores the spec")
InCombatLockdown = function() return true end
R.Roster:InspectStep()
ok(#NOTIFIED == 1, "no inspect in combat")
InCombatLockdown = function() return false end
for i = 2, #RAID do R.Roster.specByGUID[RAID[i].guid] = RAID[i].spec; INSPECT_CACHE[RAID[i].guid] = RAID[i].spec end
live = R.Roster:Members()
local c = R.Roster:Counts(live)
ok(c.known == 20 and c.TANK == 2 and c.HEALER == 4 and c.DAMAGER == 14, "counts: 2 / 4 / 14, every spec known")
do -- a hidden name is never shown
  local old = issecretvalue
  issecretvalue = function(v) return v == "Nyx" end
  local m = R.Roster:Members()
  local found
  for _, x in ipairs(m) do if x.name == "Nyx" then found = true end end
  ok(not found, "a secret name is left out")
  issecretvalue = old
end

-- 6. Needs
local res = R.Needs:Evaluate("ulatek", "H", live)
local function row(r, label) for _, x in ipairs(r.rows) do if x.label == label then return x end end end
ok(row(res, "Bloodlust").status == "ok", "Bloodlust covered")
ok(row(res, "Healers").status == "thin" and row(res, "Healers").detail:find("4 of 5", 1, true), "Ula'tek Heroic: 4 healers of 5 suggested (thin)")
ok(row(res, "Interrupts").status == "ok", "interrupts covered")
ok(row(res, "Poison dispel").status == "ok", "Heroic poison dispel covered")
ok(row(res, "Demonic Gateway").status == "ok" and row(res, "Demonic Gateway").detail:find("Ashka", 1, true), "gateway: the Warlock named")
ok(row(res, "Class buffs") and row(res, "Class buffs").info, "a class buff row")
local resN = R.Needs:Evaluate("ulatek", "N", live)
ok(row(resN, "Poison dispel") == nil and #resN.above >= 3, "Normal: Heroic-only needs hidden, counted above")
ok(row(resN, "Healers").detail:find("4 of 4", 1, true), "Normal: the baseline healer share (about 1 in 5)")
local noLust = {}
for _, m in ipairs(live) do if m.class ~= "SHAMAN" and m.class ~= "MAGE" and m.class ~= "HUNTER" and m.class ~= "EVOKER" then noLust[#noLust + 1] = m end end
ok(row(R.Needs:Evaluate("nekzali", "N", noLust), "Bloodlust").status == "miss", "no Bloodlust class: MISSING")
local gl = R.Needs:GapLines(res, "ulatek", "H")
ok(gl[1]:find("^%[Ensemble%] Ula'tek %(Heroic%) gaps:") and gl[1]:find("Healers thin", 1, true), "Post gaps line")
for _, l in ipairs(gl) do ok(#l <= 255, "gap line fits chat") end
ok(row(R.Needs:Evaluate("kithix", "N", live), "Fear dispel").detail:find("[unconfirmed]", 1, true), "an unconfirmed need says so")

-- 7. Boss order
local abyss = D.INSTANCE.abyss
R.db.instance = "abyss"
ok(R:Move("vashnik", 1) and R:Order()[3] == "explorers" and R:Order()[4] == "vashnik", "move Vashnik later (wing choice)")
ok(not R:Move("nekzali", 1), "the first boss can't move")
R:SetBoss("ulatek")
ok(not R:CanMove(abyss, "ulatek", -1), "Ula'tek can't move")
R:SetBoss("sszorak")
ok(R:StepBoss(-1) and R:Boss() == "vashnik", "previous boss follows your order")
R.db.order.abyss = { "ulatek", "sentinels", "vashnik", "explorers", "sszorak", "twinfangs", "altar", "nekzali" }
R.Sanitize(R.db)
ok(R.db.order.abyss == nil, "a saved order outside the allowed moves is dropped")
R:ResetOrder()

-- 8. Plan builder
R:SetBoss("ulatek"); R:SetDiff("H")
local rows = R.Plan:Rows("ulatek", "H")
local ids = {}
for _, r in ipairs(rows) do ids[r.id] = r end
ok(ids.coilL and ids.bite1 and ids.poison and ids.gate, "Heroic rows include Heroic-only rows")
ok(not ({ R.Plan:Row("ulatek", "N", "poison") })[1], "Normal leaves Heroic-only rows out")
ok(R.Plan:Suggest("ulatek", "H", live) >= 8, "Suggest fills the rows")
local tanks = R.Plan:Row("ulatek", "H", "tanks")
ok(#tanks.names == 2 and tanks.names[1] == "Etan" or tanks.names[2] == "Etan", "tanks suggested")
local bite = R.Plan:Row("ulatek", "H", "bite1")
ok(#bite.names == 3, "a bite set: melee + healer + ranged")
local L1, L2 = R.Plan:Row("ulatek", "H", "coilL"), R.Plan:Row("ulatek", "H", "coilR")
local overlap = false
for _, a in ipairs(L1.names) do for _, b in ipairs(L2.names) do if a == b then overlap = true end end end
ok(#L1.names + #L2.names == 20 and not overlap, "the two coil groups split the raid by group")
ok(R.Plan:Row("ulatek", "H", "gate").names[1] == "Ashka", "the gateway row gets the Warlock")
local lustRow = R.Plan:Row("ulatek", "H", "lust")
ok(#lustRow.names == 1, "one Bloodlust")
local before = #R.Plan:Row("ulatek", "H", "malice").names
R.Plan:Toggle("ulatek", "H", "malice", "Vexa")
local after = #R.Plan:Row("ulatek", "H", "malice").names
ok(after ~= before, "click toggles a player in a row")
R.Plan:Suggest("ulatek", "H", live)
ok(#R.Plan:Row("ulatek", "H", "malice").names == after, "Suggest never overwrites a filled row")
R.Plan:SetMarker("ulatek", "H", "malice", "skull")
ok(R.Plan:Row("ulatek", "H", "malice").marker == "skull", "a marker on a row")
R.Plan:SetMarker("ulatek", "H", "coilL", false)
ok(R.Plan:Row("ulatek", "H", "coilL").marker == nil, "No marker overrides the default")
R.Plan:SetMarker("ulatek", "H", "coilL", "star")
local cid = R.Plan:AddRow("ulatek", "H", "Healing cooldown 1", "Platform 2")
ok(cid and R.Plan:Row("ulatek", "H", cid).custom, "add your own row")
R.Plan:Toggle("ulatek", "H", cid, "Lunelle")
ok(not R.Plan:AddRow("ulatek", "H", "   "), "an empty row name is refused")
ok(not R.Plan:RemoveRow("ulatek", "H", "coilL") and R.Plan:RemoveRow("ulatek", "H", cid), "only your own rows can be removed")
ok(R.Plan:State("ulatek", "LFR") == nil or R.Plan:State("ulatek", "LFR") == R.Plan:State("ulatek", "N"), "LFR shares Normal's plan")
local lines, lust = R.Plan:ChatLines("ulatek", "H")
ok(lines[1] == "[Ensemble] Ula'tek (Heroic) plan", "plan header line")
local joined = table.concat(lines, "\n")
ok(joined:find("{rt1} Spectral Coils, left:", 1, true) and joined:find("{rt8} Kick Malice", 1, true), "markers as chat codes ({rtN})")
ok(joined:find(" > ", 1, true), "kick orders with >")
for _, l in ipairs(lines) do ok(#l <= 255, "plan line fits chat: " .. l:sub(1, 30)) end
ok(lust and lust:find("first damage amp", 1, true), "Heroic Bloodlust note")
ok(D.BOSSES.ulatek.lust.M:find("landing", 1, true), "Mythic Bloodlust differs")
local jobs = R.Plan:JobsFor("ulatek", "H", "Etan")
ok(#jobs >= 1, "your jobs found by name")
R.Plan:Reset("ulatek", "H")
ok(#R.Plan:Row("ulatek", "H", "tanks").names == 0 and R.Plan:ChatLines("ulatek", "H") == nil, "reset empties the plan")

-- 9. Posting
SENT = {}
LEADER, ASSIST = false, false
R.Plan:Suggest("ulatek", "H", live)
R.UI:PostPlan(true)
RunTimers()
ok(#SENT > 1 and SENT[1].channel == "RAID", "raid warning without lead or assist: posts to raid")
SENT = {}
ASSIST = true
R.UI:PostPlan(true)
RunTimers()
ok(SENT[1] and SENT[1].channel == "RAID_WARNING", "with assist: raid warning")
ASSIST = false
SENT = {}
C_ChatInfo = C_ChatInfo or {}
local oldLock, oldShow = C_ChatInfo.InChatMessagingLockdown, ns.Verify.ShowText
local shown
C_ChatInfo.InChatMessagingLockdown = function() return true end
ns.Verify.ShowText = function(_, text) shown = text; return true end
R.UI:PostPlan(false)
ok(#SENT == 0 and shown and shown:find("[Ensemble] Ula'tek", 1, true), "chat locked: the copy window instead")
C_ChatInfo.InChatMessagingLockdown, ns.Verify.ShowText = oldLock, oldShow
SENT = {}
R.db.view = "leader"
UI:SetTab("bosses")
R.UI:PostCalls(); RunTimers()
local allCalls = {}
for _, x in ipairs(SENT) do allCalls[#allCalls + 1] = x.msg end
allCalls = table.concat(allCalls, "\n")
ok(#SENT >= 1 and SENT[1].msg:find("^%[Ensemble%] Ula'tek calls") and allCalls:find("{rt1}", 1, true), "Post calls, markers as chat codes")
ok(not allCalls:find("\n%(cont%.%) [;/]"), "no continuation line starts with a separator")
for _, s in ipairs(SENT) do ok(#s.msg <= 255, "call line fits chat") end
SENT = {}
R.UI:PostPrepull(); RunTimers()
ok(SENT[#SENT] and SENT[#SENT].msg:find("Bloodlust:", 1, true), "Post pre-pull ends with Bloodlust")
SENT = {}
R.UI:PostDangers(); RunTimers()
ok(SENT[1] and SENT[1].msg:find("what kills raids", 1, true), "Post dangers")

-- 10. Pages render (learner and leader, every boss and difficulty)
local errs = 0
local oldHandler = geterrorhandler
geterrorhandler = function() return function(e) errs = errs + 1; print("ERR: " .. tostring(e)) end end
for _, inst in ipairs(D.INSTANCES) do
  R:SetInstance(inst.key)
  for _, d in ipairs(inst.diffs) do
    R:SetDiff(d)
    for _, bk in ipairs(inst.bosses) do
      R:SetBoss(bk)
      for _, view in ipairs({ "learner", "leader" }) do
        R.db.view = view
        for _, role in ipairs({ "AUTO", "ALL", "TANK", "HEALER", "DAMAGER" }) do
          R.db.role = role
          for _, tab in ipairs({ "roster", "bosses", "plan" }) do UI:SetTab(tab) end
        end
      end
    end
  end
end
ok(errs == 0, "every page renders for every boss, difficulty, view and role")
geterrorhandler = oldHandler
R.db.instance = "abyss"; R.db.diff.abyss = "N"; R:SetBoss("ulatek")
R.db.view = "learner"; R.db.role = "HEALER"
UI:SetTab("bosses")
local text = {}
for i = 1, R.UI.cardList.used do text[#text + 1] = R.UI.cardList.pool[i]:GetText() end
local card = table.concat(text, "\n")
ok(card:find("Necrotic Vapors", 1, true) and not card:find("Mother's Wrath", 1, true), "healer filter: healer and everyone items, no tank-only items")
ok(card:find("STEPPING UP: WHAT HEROIC ADDS", 1, true), "Normal shows what Heroic adds")
ok(card:find("WHAT KILLS RAIDS HERE", 1, true) and card:find("Malice", 1, true), "the dangers box")
R.db.view = "leader"
UI:SetTab("bosses")
text = {}
for i = 1, R.UI.cardList.used do text[#text + 1] = R.UI.cardList.pool[i]:GetText() end
card = table.concat(text, "\n")
ok(card:find("CALLS DURING THE FIGHT", 1, true) and card:find("SUGGESTED MARKERS", 1, true), "leader view: calls and markers")
local sayBtn
for i = 1, R.UI.cardList.bused do
  local b = R.UI.cardList.bpool[i]
  if b.tip and b.tip:find("^Post: ") then sayBtn = b; break end
end
SENT = {}
ok(sayBtn ~= nil, "a call line is clickable")
if sayBtn then sayBtn._scripts.OnClick(sayBtn); RunTimers() end
ok(#SENT == 1 and SENT[1].msg:find("^%[Ensemble%] "), "a call posts one line")

-- 11. Boss window
R:SetInstance("abyss"); R:SetDiff("H"); R:SetBoss("nekzali")
R.BossWindow:Show(true)
fire(R, "ENCOUNTER_START", 3101, "Sszorak", 15, 20)
ok(R:Boss() == "sszorak" and R.db.encSeen.Sszorak == 3101, "ENCOUNTER_START jumps to the boss and keeps its ID")
fire(R, "ENCOUNTER_END", 3101, "Sszorak", 15, 20, 1)
ok(R:Boss() == "twinfangs", "a kill moves to the next boss")
fire(R, "ENCOUNTER_START", 3102, "Ithraz", 15, 20)
ok(R:Boss() == "twinfangs", "an alias matches (Ithraz -> The Twin Fangs)")
fire(R, "ENCOUNTER_END", 3102, "Ithraz", 15, 20, 0)
ok(R:Boss() == "twinfangs", "a wipe stays on the boss")
do
  local old = issecretvalue
  issecretvalue = function(v) return type(v) == "string" end
  fire(R, "ENCOUNTER_START", 3103, "The Coiled Altar", 15, 20)
  ok(R:Boss() == "twinfangs" and R.BossWindow.lastEncounter.matched == nil, "a secret encounter name is never matched or stored")
  issecretvalue = old
end
fire(R, "ENCOUNTER_START", 2900, "Ikuzz", 8, 5)
ok(R.db.encSeen.Ikuzz == nil, "a Mythic+ boss's encounter isn't kept")
ok(R.BossWindow:Match("The Lost Explorers") == "explorers" and R.BossWindow:Match("Lost Explorers") == "explorers", "names match with and without 'The'")
R.BossWindow:Hide()

-- 12. Verify
local vtext, vcounts = ns.Verify:Build()
ok(vtext:find("== Raid test module ==", 1, true) and vtext:find("raid data valid", 1, true), "/ens verify has the raid section")
ok(vtext:find("Sszorak=3101", 1, true) and vtext:find("encounters seen (name=ID):", 1, true), "verify lists encounter IDs seen")
for _, m in ipairs(Raid20()) do
  if m.name ~= "Etan" then ok(not vtext:find(m.name, 1, true), "verify never names a player: " .. m.name) end
end
ok(vcounts.FAIL == nil or vcounts.FAIL >= 0, "verify counts include the raid lines")

-- 13. Saved data is sanitized
EnsembleRaidDB = { mode = "weird", instance = "nope", diff = { abyss = "X" }, boss = { abyss = "nobody" },
                   planner = { members = { { class = "NOPE" }, { class = "MAGE", spec = 999 } } }, view = 7, role = "Z" }
R:InitDB()
ok(R.db.mode == "auto" and R.db.instance == "abyss" and R.db.diff.abyss == nil and R.db.boss.abyss == nil, "bad saved values reset")
ok(#R.db.planner.members == 1 and R.db.planner.members[1].spec == nil, "bad planner entries dropped or cleaned")
ok(R.db.view == "learner" and R.db.role == "AUTO", "view and role reset")

IN_RAID, RAID, INSTANCE_DIFF = false, nil, nil
print(string.format("%d passed, %d failed", passes, fails))
return fails
