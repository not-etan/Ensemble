-- Ensemble / Verify.lua
-- /ens verify: checks, in the live client, everything the addon could not confirm at build
-- time (12.1 API availability, spec IDs, spell IDs, dungeon list, Group Finder data) and
-- shows a plain-text report in a copyable box. Read-only: it changes nothing.

local _, ns = ...

local Verify = {}
ns.Verify = Verify

-- A table field that may hold a player's name (search-result member info): verify output is
-- pasted in public, so its value is never printed. Spec and class names are kept.
function Verify.IsNameField(k)
  local l = tostring(k):lower()
  return l:find("name", 1, true) ~= nil and not (l:find("spec", 1, true) or l:find("class", 1, true)
    or l:find("activity", 1, true) or l:find("map", 1, true) or l:find("zone", 1, true))
end

local lines, counts
local function Util_Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local function Add(status, text)
  counts[status] = (counts[status] or 0) + 1
  lines[#lines + 1] = string.format("[%s] %s", status, text)
end
local function Section(title)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "== " .. title .. " =="
end
local function Note(text) lines[#lines + 1] = "      " .. text end

-- Resolve "C_Spell.GetSpellInfo" style paths without erroring.
local function Lookup(path)
  local cur = _G
  for part in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" and type(cur) ~= "userdata" then return nil end
    local ok, v = pcall(function() return cur[part] end)
    if not ok then return nil end
    cur = v
    if cur == nil then return nil end
  end
  return cur
end

-- Run a check; a Lua error inside it becomes a FAIL line instead of breaking the report.
local function Try(label, fn)
  local ok, err = pcall(fn)
  if not ok then Add("FAIL", label .. ": error - " .. tostring(err)) end
end

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" then return info.name end
  end
  return nil
end
local function SpellExists(id)
  if C_Spell and C_Spell.DoesSpellExist then
    local ok, v = pcall(C_Spell.DoesSpellExist, id)
    return ok and v and true or false
  end
  return SpellName(id) ~= nil
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local API_FUNCTIONS = {
  -- spec detection
  "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetSpecializationInfo",
  "GetSpecializationInfoByID", "GetInspectSpecialization", "NotifyInspect", "CanInspect", "ClearInspectPlayer",
  "GetSpecializationInfoForClassID", "GetNumSpecializationsForClassID",
  -- group finder
  "C_LFGList.HasActiveEntryInfo", "C_LFGList.GetActiveEntryInfo", "C_LFGList.GetActivityInfoTable",
  "C_LFGList.GetApplicants", "C_LFGList.GetApplicantInfo", "C_LFGList.GetApplicantMemberInfo", "C_LFGList.InviteApplicant",
  -- keystone / dungeon icons
  "C_MythicPlus.GetOwnedKeystoneChallengeMapID", "C_MythicPlus.GetOwnedKeystoneLevel",
  "C_ChallengeMode.GetMapTable", "C_ChallengeMode.GetMapUIInfo",
  "C_ChallengeMode.GetActiveChallengeMapID", "GetInstanceInfo",
  "C_Timer.NewTicker", "hooksecurefunc",
  "C_MythicPlus.GetCurrentAffixes", "C_ChallengeMode.GetAffixInfo", "C_MythicPlus.RequestCurrentAffixes",
  "C_ChallengeMode.GetActiveKeystoneInfo", "C_ChallengeMode.GetDeathCount",
  -- icons / tooltips / links
  "C_Spell.GetSpellInfo", "C_Spell.GetSpellTexture", "C_Spell.DoesSpellExist", "C_Spell.GetSpellLink",
  "C_Item.GetItemIconByID", "ChatEdit_InsertLink",
  -- misc
  "C_ClassColor.GetClassColor", "C_AddOns.GetAddOnMetadata", "UnitGroupRolesAssigned",
  "ColorPickerFrame.SetupColorPickerAndShow",
}

local function CheckAPIs()
  Section("Client functions")
  local missing = 0
  for _, path in ipairs(API_FUNCTIONS) do
    if type(Lookup(path)) ~= "function" then
      Add("FAIL", "missing: " .. path); missing = missing + 1
    end
  end
  if missing == 0 then Add("OK", #API_FUNCTIONS .. " functions present") end

  -- Widget methods the UI relies on.
  local f = CreateFrame("Frame")
  Add(f.SetHyperlinksEnabled and "OK" or "FAIL", "Frame:SetHyperlinksEnabled (hover tooltips on ability links)")
  local t = f:CreateTexture()
  Add(t.SetRotation and "OK" or "WARN", "Texture:SetRotation (dropdown chevron)")
  local okSlider, sl = pcall(CreateFrame, "Slider", nil, f)
  Add(okSlider and sl and sl.SetObeyStepOnDrag and "OK" or "WARN", "Slider:SetObeyStepOnDrag (scale slider)")
  local okCS, cs = pcall(CreateFrame, "ColorSelect", nil, f)
  Add(okCS and cs and cs.SetColorWheelTexture and "OK" or "WARN",
    "ColorSelect widget (embedded color wheel; otherwise the Blizzard picker button is used)")
  Add(GameTooltip and GameTooltip.SetSpellByID and "OK" or "FAIL", "GameTooltip:SetSpellByID")
  Add(type(LFGListApplicantMember_OnEnter) == "function" and "OK" or "WARN",
    "LFGListApplicantMember_OnEnter (fit ratings in Group Finder tooltips) "
    .. (type(LFGListApplicantMember_OnEnter) == "function" and "found" or "not found - open the Group Finder once and re-run"))
  local hasSettings = Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
  Add(hasSettings and "OK" or "WARN", "Blizzard Options > AddOns entry (Settings.RegisterCanvasLayoutCategory) "
    .. (hasSettings and ((ns.UI and ns.UI.blizzCategory) and "registered" or "available, not registered") or "not available"))
  Add(PVEFrame and "OK" or "WARN", "PVEFrame (Group Finder window) " .. (PVEFrame and "found" or "not loaded yet - open the Group Finder once and re-run"))
  f:Hide()

  -- Events (RegisterEvent errors on unknown names).
  local probe = CreateFrame("Frame")
  local bad = {}
  -- Every game event any module registers (keep in step when adding one).
  local EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "INSPECT_READY",
                   "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_APPLICANT_LIST_UPDATED",
                   "LFG_LIST_APPLICANT_UPDATED", "LFG_LIST_SEARCH_RESULTS_RECEIVED", "PLAYER_ENTERING_WORLD",
                   "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA",
                   "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
                   "CHALLENGE_MODE_MAPS_UPDATE", "BAG_UPDATE_DELAYED", "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
                   "TRAIT_CONFIG_UPDATED", "ENCOUNTER_START", "ENCOUNTER_END", "SCENARIO_CRITERIA_UPDATE" }
  for _, ev in ipairs(EVENTS) do
    if not pcall(probe.RegisterEvent, probe, ev) then bad[#bad + 1] = ev end
  end
  probe:UnregisterAllEvents()
  if #bad == 0 then Add("OK", "all " .. #EVENTS .. " game events the addon uses accepted")
  else Add("FAIL", "unknown events: " .. table.concat(bad, ", ")) end

  -- "Post gaps to party chat"
  local cs = (C_ChatInfo and C_ChatInfo.SendChatMessage and "C_ChatInfo.SendChatMessage")
    or (SendChatMessage and "SendChatMessage") or nil
  Add(cs and "OK" or "FAIL", "chat send for 'Post gaps': " .. (cs or "no SendChatMessage found"))

  -- Functions the addon guards and can do without, and what each one missing costs.
  local OPTIONAL = {
    { { "C_ChallengeMode.GetOverallDungeonScore" }, "the Sign Up line leaves out your Mythic+ rating" },
    { { "IsPlayerSpell", "C_SpellBook.IsSpellKnown" }, "your talents can't be read: \"What you'd add\" counts every talent ability as maybe" },
    { { "C_ChatInfo.InChatMessagingLockdown" }, "the addon can't tell when chat is locked: a blocked post fails instead of opening the copy window" },
    { { "UnitIsGroupLeader" }, "the Invite buttons can't check that you lead the group (the game still refuses an invite you can't make)" },
    { { "UnitIsGroupAssistant" }, "an assistant's Invite buttons stay disabled; only the leader can invite from the addon" },
    { { "C_MythicPlus.RequestMapInfo" }, "the season's dungeon list isn't requested: the season-change check waits until the game loads it" },
  }
  for _, o in ipairs(OPTIONAL) do
    local found
    for _, path in ipairs(o[1]) do if type(Lookup(path)) == "function" then found = path; break end end
    if found then Add("OK", found .. " present")
    else Add("WARN", table.concat(o[1], " / ") .. " missing: " .. o[2]) end
  end

  -- Midnight secret values (only relevant inside instances / combat).
  local isSecret = Lookup("issecretvalue")
  if type(isSecret) == "function" then
    local _, cls = UnitClass("player")
    Add(isSecret(cls) and "WARN" or "OK", "UnitClass('player') " .. (isSecret(cls) and "is a secret value here" or "readable (not secret)"))
    -- #13: the hint is only useful outside an instance (inside a key it's already that run).
    local inInstance = false
    if type(IsInInstance) == "function" then
      local okI, inside = pcall(IsInInstance)
      inInstance = okI and inside and true or false
    end
    if not inInstance then Note("Re-run inside a Mythic+ key with a party to check party units too.") end
    if IsInGroup and IsInGroup() and UnitExists("party1") then
      local _, pcls = UnitClass("party1")
      local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("party1")
      Add((isSecret(pcls) or isSecret(role)) and "WARN" or "OK", "party1 class/role " ..
        ((isSecret(pcls) or isSecret(role)) and "secret in this context" or "readable"))
    end
  else
    Add("OK", "issecretvalue not present (no secret-value checks needed in this context)")
  end
  local R = ns.Report
  if R then
    local BG = rawget(_G, "BugGrabber")
    if R.captureActive then
      Add("OK", "error capture for /ens report active")
    elseif type(BG) == "table" and type(BG.GetDB) == "function" then
      Add("OK", "BugGrabber handles Lua errors: /ens report includes its errors from this addon")
    else
      Add("INFO", "error capture for /ens report not active (another addon owns the error handler, or the client refused): /ens report still works, without the error list")
    end
  end
end

local function CheckSpecs()
  Section("Specs")
  local UD = ns.UD
  local my = ns.API.GetPlayerSpecID()
  local _, myClass = UnitClass("player")
  Add(my and UD:GetSpec(my) and "OK" or "FAIL", string.format("your spec: %s (%s) %s", tostring(my), tostring(myClass),
    my and UD:GetSpec(my) and UD:GetSpec(my).name or "- not in the addon's spec table"))

  -- Every spec the addon knows, checked against the client.
  local wrong = {}
  local okCount = 0
  for id, p in pairs(UD.specs) do
    local okInfo, cid, name, _, _, role, classFile = pcall(GetSpecializationInfoByID, id)
    if not okInfo or not cid then
      wrong[#wrong + 1] = string.format("%d (%s %s): unknown to the client", id, p.name, p.class)
    elseif classFile ~= p.class or role ~= p.role then
      wrong[#wrong + 1] = string.format("%d: client says %s %s / %s, addon has %s %s / %s", id, tostring(name),
        tostring(classFile), tostring(role), p.name, p.class, p.role)
    else
      okCount = okCount + 1
    end
  end
  table.sort(wrong)
  for _, w in ipairs(wrong) do Add("FAIL", "spec " .. w) end
  Add(#wrong == 0 and "OK" or "WARN", okCount .. " spec IDs match the client")

  -- Specs the client has that the addon doesn't (e.g. the real Devourer ID).
  if GetNumClasses and GetSpecializationInfoForClassID and GetNumSpecializationsForClassID then
    local extra = {}
    for classID = 1, GetNumClasses() do
      local okN, n = pcall(GetNumSpecializationsForClassID, classID)
      for i = 1, (okN and n or 0) do
        local okS, sid, sname = pcall(GetSpecializationInfoForClassID, classID, i)
        if okS and sid and not UD.specs[sid] then
          local _, cf = GetClassInfo(classID)
          extra[#extra + 1] = string.format("%d = %s %s", sid, tostring(sname), tostring(cf))
        end
      end
    end
    if #extra == 0 then Add("OK", "no client specs missing from the addon")
    else for _, e in ipairs(extra) do Add("FAIL", "client spec not in addon: " .. e) end end
  end
end

local function CheckSpellTable(label, tbl, nameCheck)
  local missing, renamed, ok = {}, {}, 0
  local loc = GetLocale and GetLocale() or ""
  local english = (loc == "enUS" or loc == "enGB")
  for name, id in pairs(tbl) do
    if not id or id == 0 then
      missing[#missing + 1] = name .. " (no ID)"
    elseif not SpellExists(id) then
      missing[#missing + 1] = name .. " = " .. id
    else
      local real = SpellName(id)
      if nameCheck and english and real and real:lower() ~= name:lower() then
        renamed[#renamed + 1] = string.format("%s = %d is \"%s\" in game", name, id, real)
      else
        ok = ok + 1
      end
    end
  end
  table.sort(missing); table.sort(renamed)
  for _, m in ipairs(missing) do Add("FAIL", label .. " spell not found: " .. m) end
  for _, r in ipairs(renamed) do Add("WARN", label .. " name differs: " .. r) end
  Add(#missing == 0 and "OK" or "WARN", string.format("%s spells: %d OK, %d missing, %d name differences", label, ok, #missing, #renamed))
end

local function CheckSpells()
  Section("Spell IDs (icons and tooltips)")
  CheckSpellTable("class", ns.UD.SPELL_IDS, true)
  local buffs = {}
  for _, b in ipairs(ns.UD.BUFFS) do buffs[b.name] = b.spell end
  CheckSpellTable("raid buff", buffs, false)  -- buff names differ from cast names (e.g. Skyfury)
  CheckSpellTable("dungeon", ns.Dungeons.SPELL_IDS, true)
  for _, key in ipairs(ns.Dungeons.order) do
    local d = ns.Dungeons.list[key]
    if d.spellIds then CheckSpellTable(d.name, d.spellIds, true) end
  end
end

local function CheckDungeons()
  Section("Dungeons")
  local DD = ns.Dungeons
  if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then
    Add("FAIL", "C_ChallengeMode.GetMapTable missing: no dungeon icons"); return
  end
  local ok, maps = pcall(C_ChallengeMode.GetMapTable)
  if not ok or type(maps) ~= "table" or #maps == 0 then
    Add("WARN", "season dungeon list empty (Mythic+ data may not be loaded yet - open the Group Finder's Mythic+ tab and re-run)")
    return
  end
  local found = {}
  for _, mapID in ipairs(maps) do
    local okInfo, name, _, _, tex, _, instanceMapID = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    local key = DD:KeyForChallengeMap(mapID)
    if key then
      found[key] = true
      local nameNote = (name and DD:FindKey(name) == key) and "" or (" (name '" .. tostring(name) .. "' differs - matched by ID)")
      Add(tex and "OK" or "WARN", string.format("%s (map %d, instance %s) -> %s by ID, icon %s%s", tostring(name), mapID,
        tostring(instanceMapID), key, tex and "yes" or "MISSING", nameNote))
    else
      Add("FAIL", string.format("season dungeon not in the addon: %s (map %d)", tostring(okInfo and name), mapID))
    end
  end
  for _, key in ipairs(DD.order) do
    if not found[key] then Add("FAIL", "addon dungeon not in this season's list: " .. DD.list[key].name .. " (map " .. tostring(DD.CHALLENGE_MAP_IDS[key]) .. ")") end
  end
  local okK, kmap = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
  local okL, klvl = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
  if okK and kmap then
    local okN, kname = pcall(C_ChallengeMode.GetMapUIInfo, kmap)
    if not okN then kname = nil end
    Add("OK", string.format("your keystone: %s +%s (matched to %s)", tostring(kname), tostring(okL and klvl or "?"),
      tostring(ns:DungeonFromMapID(kmap))))
  else
    Add("OK", "no keystone in your bags (keystone-level detection not tested)")
  end
  -- Zone detection (Live/Applicants default when there's no listing).
  local okI, iname, itype = pcall(GetInstanceInfo)
  if okI and itype == "party" then
    local zk = ns:CurrentInstanceDungeon()
    Add(zk and "OK" or "WARN", string.format("current dungeon: %s (%s) -> %s", tostring(iname), tostring(itype),
      zk and DD.list[zk].name or "not matched"))
  else
    Add("INFO", "not inside a dungeon (zone detection not tested; run /ens verify inside one)")
  end
  local eff, src = ns:GetEffectiveDungeon(false)
  Add("INFO", "Planner default dungeon: " .. (eff and DD.list[eff].name or "none") .. " (" .. tostring(src or "nothing detected") .. ")")
end

local function CheckAffixes()
  Section("Affixes")
  local AF = ns.Affixes
  if not (C_MythicPlus and C_MythicPlus.GetCurrentAffixes) then
    Add("FAIL", "C_MythicPlus.GetCurrentAffixes missing: affix awareness off"); return
  end
  AF:Refresh()
  local cur = AF:Current()
  if #cur == 0 then
    Add("WARN", "this week's affixes not loaded yet - open the Group Finder's Mythic+ tab and re-run"); return
  end
  for i, a in ipairs(cur) do
    local how = a.def and ((function() for _, id in ipairs(a.def.ids) do if id == a.id then return "by ID" end end return "by name" end)()) or nil
    Add(a.def and "OK" or "WARN", string.format("#%d affix %d \"%s\" -> %s", i, a.id, tostring(a.name),
      a.def and (a.def.key .. " " .. how) or "not in the addon's affix list"))
  end
  local level = AF:KeyLevel(ns:GetEffectiveDungeon(false))
  local active = AF:Active(level)
  local names = {}
  for _, a in ipairs(active) do names[#names + 1] = a.label end
  Add("INFO", string.format("active at +%d%s: %s", level or AF.ASSUMED_LEVEL, level and "" or " (assumed)",
    #names > 0 and table.concat(names, ", ") or "none"))
  Add("INFO", "the first Fortified/Tyrannical listed is assumed to be the +7 one (check your keystone tooltip)")
end

local function CheckHistory()
  Section("Run history")
  local cm = C_ChallengeMode or {}
  local api = (cm.GetChallengeCompletionInfo and "GetChallengeCompletionInfo") or (cm.GetCompletionInfo and "GetCompletionInfo")
  Add(api and "OK" or "FAIL", "key completion info: " .. (api and ("C_ChallengeMode." .. api) or "no completion API found"))
  Add(ns.db.settings.history ~= false and "INFO" or "WARN", string.format("%d key(s) recorded; recording %s%s",
    #(ns.db.history or {}), ns.db.settings.history ~= false and "on" or "OFF",
    ns.db.activeRun and (" - a key is in progress (" .. tostring(ns.db.activeRun.key) .. ")") or ""))
  -- Past keys together (1.5.0): counts only, never a name.
  local H = ns.History
  local runs, named, players = H:PastStats()
  Add("INFO", string.format("past keys together: %d of %d recorded keys have full names (1.5.0 on), %d players you've played with; failed = %s",
    named, runs, players, H.FAILED_LABEL[H:FailedMode()]))
  -- Cross-realm party names (1.5.0 review, R5): counts only, never names. Settles whether the
  -- game gives party members' realms with spaces or hyphens ("Area 52"), which the addon now
  -- strips so they match applicant names.
  do
    local inParty, xr, raw, hidden = 0, 0, 0, 0
    for i = 1, 4 do
      local unit = "party" .. i
      local okE, exists = pcall(UnitExists, unit)
      if okE and exists and not (issecretvalue and select(2, pcall(issecretvalue, exists)) == true) then
        inParty = inParty + 1
        local okN, name, realm = pcall(UnitName, unit)
        local secret = issecretvalue and okN and ((select(2, pcall(issecretvalue, name)) == true) or (select(2, pcall(issecretvalue, realm)) == true))
        if not okN or secret then hidden = hidden + 1
        elseif type(realm) == "string" and realm ~= "" then
          xr = xr + 1
          if realm:find("[%s%-]") then raw = raw + 1 end
        end
      end
    end
    if inParty > 0 then
      Add(hidden > 0 and "WARN" or "INFO", string.format(
        "party names: %d of %d from another realm, %d of those written with spaces or hyphens (matched without them)%s",
        xr, inParty, raw, hidden > 0 and ("; " .. hidden .. " hidden by the game") or ""))
    else
      Add("INFO", "party names: not in a party (re-run with a cross-realm party member to see how realms read)")
    end
  end
  if ns.Tracker and ns.Tracker.hosting then
    local ok, _, evals = pcall(ns.ApplicantFit.ForLiveGroup, ns.ApplicantFit)
    local n, with = 0, 0
    for _, ev in ipairs(ok and evals or {}) do
      for _, m in ipairs(ev.members or {}) do
        n = n + 1
        if H:With(m.full) then with = with + 1 end
      end
    end
    Add("INFO", string.format("applicants you've played with: %d of %d", with, n))
  end
  -- Boss splits (1.5.0).
  local SI = rawget(_G, "C_ScenarioInfo")
  local hasCrit = type(SI) == "table" and type(SI.GetCriteriaInfo) == "function"
  Add(hasCrit and "OK" or "WARN", "C_ScenarioInfo.GetCriteriaInfo " .. (hasCrit and "present (boss splits)"
    or "missing: boss splits come from boss kills (ENCOUNTER_END) only"))
  local hasClock = type(rawget(_G, "GetWorldElapsedTime")) == "function"
  Add(hasClock and "OK" or "WARN", "GetWorldElapsedTime " .. (hasClock and "present (the key's timer for splits)"
    or "missing: no split times"))
  local inKey = false
  if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
    local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
    inKey = ok and id and true or false
  end
  if not inKey then
    Add("INFO", "boss splits: run /ens verify inside a key to check the boss objectives, the timer and the death count")
  else
    local before = H.secretReads or 0
    local list, why = H:BossCriteria()
    if not list then
      Add("WARN", "boss objectives: " .. (why == "api" and "the function is missing" or "none read (empty)") .. " - splits come from boss kills only")
    else
      local done = 0
      for _, c in ipairs(list) do if c.completed then done = done + 1 end end
      Add(#list > 0 and "OK" or "WARN", string.format("boss objectives: %d criteria read, %d bosses found, %d down", why, #list, done)
        .. (#list == 0 and " (no boss criteria: splits come from boss kills only)" or ""))
    end
    local t = H:KeyElapsed()
    Add(t and "OK" or "WARN", "key timer: " .. (t and (H.Clock(t) .. " elapsed") or "not readable (hidden or missing): splits have no times"))
    local d = H:DeathCount()
    Add(d and "OK" or "WARN", "death count: " .. (d and tostring(d) or "not readable (hidden or missing)"))
    local hidden = (H.secretReads or 0) - before
    if hidden > 0 then Add("WARN", hidden .. " value(s) hidden by the game in this check (left out of splits)") end
    local run = ns.db.activeRun
    Add("INFO", "splits recorded this key: " .. (run and run.splits and #run.splits or 0))
  end
end

local function CheckGroupFinder()
  Section("Group Finder")
  local okHas, has = pcall(C_LFGList.HasActiveEntryInfo)
  if not okHas then Add("FAIL", "HasActiveEntryInfo errored"); return end
  if not has then
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n >= 5 then
      Add("INFO", "no active listing: the game closes a listing once the group is full. To test this part, list with an open spot (ideally with applicants) and re-run")
    else
      Add("WARN", "no active listing - list a group (ideally with applicants) and re-run to test this part")
    end
    return
  end
  local okE, entry = pcall(C_LFGList.GetActiveEntryInfo)
  if okE and type(entry) == "table" then
    local ids = entry.activityIDs or (entry.activityID and { entry.activityID }) or {}
    Add(#ids > 0 and "OK" or "FAIL", "listing activity IDs: " .. (#ids > 0 and table.concat(ids, ", ") or "none (field renamed?)"))
    for _, id in ipairs(ids) do
      local okA, info = pcall(C_LFGList.GetActivityInfoTable, id)
      local name = okA and type(info) == "table" and (info.fullName or info.shortName)
      local DDv = ns.Dungeons
      local via = (DDv.ACTIVITY_IDS[id] and "activity ID")
        or (okA and type(info) == "table" and DDv:KeyForInstanceMap(info.mapID) and "instance map")
        or "name"
      local key = DDv:KeyForActivity(id, okA and info or nil)
      Add(key and "OK" or "WARN", string.format("activity %d \"%s\" (instance map %s) -> %s via %s", id, tostring(name),
        tostring(okA and type(info) == "table" and info.mapID), tostring(key or "no dungeon match"), key and via or "-"))
    end
  else
    Add("FAIL", "GetActiveEntryInfo returned no table")
  end
  local okA, apps = pcall(C_LFGList.GetApplicants)
  if not okA or type(apps) ~= "table" then Add("FAIL", "GetApplicants failed"); return end
  if #apps == 0 then Add("WARN", "no applicants right now - re-run once someone applies to test spec detection"); return end
  local withSpec, total, leaverRead = 0, 0, 0
  for _, aid in ipairs(apps) do
    local okI, info = pcall(C_LFGList.GetApplicantInfo, aid)
    for m = 1, (okI and type(info) == "table" and info.numMembers or 0) do
      local res = { pcall(C_LFGList.GetApplicantMemberInfo, aid, m) }
      if res[1] then
        total = total + 1
        local spec = res[17]
        if type(spec) == "number" and spec > 0 then withSpec = withSpec + 1 end
        if type(res[18]) == "boolean" then leaverRead = leaverRead + 1 end
        if total == 1 then
          -- The first return is the applicant's name: never in a report people paste in public.
          local shown = { "<name>" }
          for i = 3, #res do shown[#shown + 1] = tostring(res[i]) end
          Note("first applicant returns: " .. table.concat(shown, " | "))
        end
      end
    end
  end
  Add(withSpec > 0 and "OK" or "WARN", string.format("applicants with a spec ID: %d of %d%s", withSpec, total,
    withSpec == 0 and " (spec not exposed: applicants will be rated on class only)" or ""))
  -- Fill group's leaver filter reads the 17th return (isLeaver in Blizzard's LFGList.lua).
  Add(leaverRead > 0 and "OK" or "WARN", string.format("leaver flag (17th applicant return) readable: %d of %d%s", leaverRead, total,
    leaverRead == 0 and " (Fill group's leaver filter can't skip anyone)" or ""))
  -- Per-dungeon experience (best run of the listed dungeon) for the experience weighting.
  local fnScore = C_LFGList.GetApplicantDungeonScoreForListing
  if not fnScore then
    Add("WARN", "C_LFGList.GetApplicantDungeonScoreForListing missing: applicant ratings use utility only (no experience weighting)")
  else
    local ids = okE and type(entry) == "table" and (entry.activityIDs or { entry.activityID }) or {}
    local withRun, checked = 0, 0
    for _, aid in ipairs(apps) do
      local okI, info = pcall(C_LFGList.GetApplicantInfo, aid)
      for m = 1, (okI and type(info) == "table" and info.numMembers or 0) do
        checked = checked + 1
        local best = ns.Tracker.BestHere(aid, m, ids[1])
        if best and best.level > 0 then withRun = withRun + 1 end
        if checked == 1 then Note("first applicant's best run here: " .. (best and string.format("+%d %s (score %d)", best.level,
          best.timed and "timed" or "over time", best.score) or "no data")) end
      end
    end
    Add("OK", string.format("applicants with a run of this dungeon: %d of %d (experience weighting)", withRun, checked))
  end
end

-- Fill group (1.4.0): the APIs its filters and invites use, how invites behave on this game
-- build, the last fill, and the plan while you host.
local function CheckFill()
  Section("Fill group")
  local FG = ns.FillGroup
  if not FG then Add("FAIL", "Fill group module missing"); return end
  -- Reserved slots and Saved players (1.5.0): counts and roles only, never names.
  local P = ns.Players
  if P then
    local res = P:Reservations()
    local roles = {}
    for _, r in ipairs(res) do
      local sp = ns.UD:GetSpec(r.specID)
      roles[#roles + 1] = sp and (sp.role == "TANK" and "tank" or sp.role == "HEALER" and "healer" or "DPS") or "?"
    end
    local named = 0
    for _, r in ipairs(res) do if r.full then named = named + 1 end end
    Add("INFO", string.format("reserved slots: %d%s%s; saved players: %d", #res,
      #roles > 0 and (" (" .. table.concat(roles, ", ") .. ")") or "", named > 0 and (", " .. named .. " named") or "", #P:List()))
    if #res > 0 then
      Add(P:Listed() and "OK" or "INFO", P:Listed() and "reservations are for this listing (they clear when it ends)"
        or "not listed: the reservations wait for your listing")
    end
    -- A named reservation releases when that player is invited and comes back after a time-out
    -- (1.5.0 review, R3). Counts and the game's status names only. Unconfirmed in game: what an
    -- invite nobody answers turns into; these statuses settle it after the first one.
    local log = P.inviteLog or { statuses = {} }
    local st = {}
    for k, v in pairs(log.statuses or {}) do st[#st + 1] = k .. " " .. v end
    table.sort(st)
    local pending = ns.db.reserved and ns.db.reserved.pending or {}
    if (log.released or 0) + #pending + #st == 0 then
      Add("INFO", "reserved friends' invites: none seen this session")
    else
      Add("INFO", string.format("reserved friends' invites: %d out now; this session %d released on invite, %d back after a time-out, %d stayed released%s; statuses seen: %s",
        #pending, log.released or 0, log.restored or 0, log.stayed or 0,
        (log.notRestored or 0) > 0 and (", " .. log.notRestored .. " timed out with no free slot left") or "",
        #st > 0 and table.concat(st, ", ") or "none"))
    end
  end
  local fn = C_MythicPlus and C_MythicPlus.GetRewardLevelForDifficultyLevel
  if type(fn) ~= "function" then
    Add("WARN", "C_MythicPlus.GetRewardLevelForDifficultyLevel missing: no suggested item level (set your own or use your listing's)")
  else
    -- 0 (or nothing) means no suggested item level: the filter shows "Not in force" (seen in
    -- 12.1.5 build 70575, October 24: end of run 0, weekly 318). Was marked OK before 1.4.1.
    local ok, weekly, eor = pcall(fn, 10)
    local good = ok and tonumber(eor) and tonumber(eor) > 0
    Add(good and "OK" or "WARN", string.format("reward item level for +10: end of run %s, weekly %s%s",
      tostring(ok and eor), tostring(ok and weekly),
      good and " (suggested item level reads this)"
      or " - no end-of-run value, so the suggested item level stays off (use your listing's or a custom number)"))
  end
  local okH, has = pcall(C_LFGList.HasActiveEntryInfo)
  if okH and has then
    local okE, entry = pcall(C_LFGList.GetActiveEntryInfo)
    if okE and type(entry) == "table" then
      local r, i = entry.requiredDungeonScore, entry.requiredItemLevel
      Add((r ~= nil or i ~= nil) and "OK" or "INFO", string.format("listing minimums: rating %s, item level %s%s", tostring(r), tostring(i),
        (r == nil and i == nil) and " (none set, or the fields are named differently: \"From my listing\" finds nothing)" or ""))
    end
  else
    Add("INFO", "listing minimums: list a group to check the fields \"From my listing\" reads")
  end
  Add(C_LFGList.InviteApplicant and "OK" or "FAIL", "C_LFGList.InviteApplicant (Fill group and Invite buttons)")
  Add(C_LFGList.GetNumInvitedApplicantMembers and "OK" or "INFO",
    "C_LFGList.GetNumInvitedApplicantMembers" .. (C_LFGList.GetNumInvitedApplicantMembers and "" or " missing: the five-player check counts pending invites itself"))
  Add((PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK) and "OK" or "WARN", "PlaySound / SOUNDKIT.READY_CHECK (Auto-fill's ready-check sound)")
  Add(PlaySoundFile and "OK" or "WARN", "PlaySoundFile (Auto-fill's Ensemble chime)"
    .. (PlaySoundFile and "" or " missing: the game's ready-check sound plays instead"))
  -- What the last group-ready sound (or Play in Settings) actually did since the last reload.
  local ls = FG.lastSound
  if ls then
    local NAMES = { chime = "Ensemble chime", readycheck = "game ready check" }
    if ls.soundOff then
      -- Neither sound would play: game sound (or the Master channel) is off, not a file problem.
      Add("INFO", "last group-ready sound: nothing played - the game wasn't playing sounds (game sound or the Master channel off?)")
    else
      Add(ls.played == ls.choice and "OK" or "WARN", string.format("last group-ready sound: %s%s", NAMES[ls.played] or "nothing played",
        ls.played == ls.choice and "" or (" (picked: " .. tostring(NAMES[ls.choice] or ls.choice) .. ")")))
    end
  end
  local mode = FG:InviteMode()
  local learned = ns.db and ns.db.fillInvite
  if mode == "one" then
    Add("INFO", "invites: one per click on build " .. tostring(learned and learned.build) .. " (" .. tostring(learned and learned.reason) .. ")")
  elseif learned and learned.build == FG.GameBuild() and learned.oneAtATime == false then
    -- A one-click fill already went through on this build (kept across reloads since 1.4.1).
    Add("OK", "invites: one click sends the whole plan (seen on build " .. tostring(learned.build) .. ": " .. tostring(learned.reason) .. ")")
  else
    Add("INFO", "invites: one click sends the whole plan" .. (learned and learned.build ~= FG.GameBuild() and " (re-testing on this build)" or " (untested on this build until the first fill)"))
  end
  local last = FG:LastFillText()
  Add(last and ((last:find("not taken") or last:find("blocked") or last:find("error")) and "WARN" or "OK") or "INFO",
    last or "no Fill group used since the last reload")
  if FG.planErrors and FG.planErrors > 0 then Add("FAIL", "plan errors: " .. FG.planErrors .. " (last: " .. tostring(FG.lastPlanError) .. ")") end
  -- One player per class in each role (1.5.1): the setting, and how many it skips now (counts only).
  local fs = ns.db and ns.db.settings and ns.db.settings.fill or {}
  local nClass = 0
  local cur = ns.Tracker and ns.Tracker.hosting and FG:Current()
  for _, x in ipairs(cur and cur.skipped or {}) do if x.class then nClass = nClass + 1 end end
  Add("INFO", "one player per class in each role: " .. (fs.oneClassPerRole ~= false and "on" or "off")
    .. (cur and (" (" .. nClass .. " applicant" .. (nClass == 1 and "" or "s") .. " skipped for it now)") or ""))
  if ns.Tracker and ns.Tracker.hosting then
    local plan = FG:Current()
    if plan then
      Add("INFO", string.format("plan now: %s at %s, %d group(s) counted, %d full check(s), %d skipped%s", plan.status,
        tostring(plan.level), plan.leaves or 0, plan.checked or 0, #plan.skipped,
        plan.status == "ready" and (", " .. #plan.picks .. " to invite") or (plan.blocking and (": " .. plan.blocking) or "")))
    end
    Add("INFO", "Auto-fill " .. (FG.armed and "armed for this listing" or "off for this listing"))
  end
end

-- Groups you could join: search results, member specs and the listing marker / tooltip hooks.
local function CheckSearch()
  Section("Group Finder search (your fit)")
  local FS = ns.FinderSearch
  Add(type(LFGListSearchEntry_Update) == "function" and "OK" or "WARN",
    "LFGListSearchEntry_Update (listing markers) " .. (type(LFGListSearchEntry_Update) == "function" and "found" or "not found - open the Group Finder once and re-run"))
  Add(type(LFGListUtil_SetSearchEntryTooltip) == "function" and "OK" or "WARN",
    "LFGListUtil_SetSearchEntryTooltip (your fit in listing tooltips) " .. (type(LFGListUtil_SetSearchEntryTooltip) == "function" and "found" or "not found"))
  if FS and FS.Hook then FS:Hook() end
  Add(type(LFGListApplicationDialog_Show) == "function" and "OK" or "WARN",
    "LFGListApplicationDialog_Show (the line for your Sign Up note) " .. (type(LFGListApplicationDialog_Show) == "function" and "found" or "not found"))
  Add((C_MythicPlus and C_MythicPlus.GetSeasonBestForMap) and "OK" or "WARN",
    "C_MythicPlus.GetSeasonBestForMap (your best run, in the Sign Up line) " .. ((C_MythicPlus and C_MythicPlus.GetSeasonBestForMap) and "found" or "not found"))
  Note("hooks attached: rows " .. tostring(FS and FS.rowsHooked or false) .. ", tooltips " .. tostring(FS and FS.tipHooked or false)
    .. ", sign up " .. tostring(FS and FS.applyHooked or false) .. ", sign up dialog OnShow " .. tostring(FS and FS.dialogHooked or false))
  -- Another addon that replaces one of these functions after we hook it silences our hook
  -- (issue #4). issecurevariable names the addon that last wrote the global.
  if type(issecurevariable) ~= "function" then
    Add("WARN", "issecurevariable missing: can't tell whether another addon replaced the hooked Group Finder functions")
  elseif FS and FS.HOOKED_GLOBALS then
    for _, h in ipairs(FS.HOOKED_GLOBALS) do
      if type(_G[h.name]) == "function" then
        local okS, secure, by = pcall(issecurevariable, h.name)
        if not okS then
          Add("WARN", h.name .. ": issecurevariable errored")
        elseif secure then
          Add("OK", h.name .. " is Blizzard's own (not replaced by another addon)")
        else
          local who = (type(by) == "string" and by ~= "") and by or "another addon"
          local still = (h.name == "LFGListApplicationDialog_Show" and FS.dialogHooked)
            and " The Sign Up line uses the dialog's OnShow instead, so it still works."
            or (" " .. h.feature:sub(1, 1):upper() .. h.feature:sub(2) .. " may not appear while it's loaded.")
          Add("WARN", h.name .. " was replaced by " .. who .. " (affects " .. h.feature .. ")." .. still)
        end
      end
    end
  end
  local hasPlayer = C_LFGList and C_LFGList.GetSearchResultPlayerInfo
  local hasMember = C_LFGList and C_LFGList.GetSearchResultMemberInfo
  Add((hasPlayer or hasMember) and "OK" or "FAIL", "search result member info: "
    .. (hasPlayer and "GetSearchResultPlayerInfo" or "") .. (hasPlayer and hasMember and " + " or "") .. (hasMember and "GetSearchResultMemberInfo" or "")
    .. ((hasPlayer or hasMember) and "" or "none found"))
  if not (C_LFGList and C_LFGList.GetSearchResults) then Add("FAIL", "C_LFGList.GetSearchResults missing"); return end
  local ok, a, b = pcall(C_LFGList.GetSearchResults)
  local list = (type(b) == "table" and b) or (type(a) == "table" and a) or {}
  if not ok or #list == 0 then
    Add("WARN", "no search results - search for a Mythic+ dungeon in the Group Finder and re-run to test this part")
    return
  end
  local LFt = ns.ListingFit
  local tested, specKnown, specTotal, dungeonHits, firstShown = 0, 0, 0, 0, false
  local titleLevels, titleBlocked = 0, 0
  local titleNil, titleEmpty, titleText, titleCoded = 0, 0, 0, 0
  for _, id in ipairs(list) do
    if tested >= 10 then break end
    tested = tested + 1
    local key = LFt:DungeonFor(id)
    if key then dungeonHits = dungeonHits + 1 end
    local okI, rinfo = pcall(C_LFGList.GetSearchResultInfo, id)
    local lvl, why = LFt:LevelFromTitle(okI and rinfo or nil)
    if lvl then titleLevels = titleLevels + 1 elseif why == "encoded" then titleCoded = titleCoded + 1 elseif why then titleBlocked = titleBlocked + 1 end
    if not why then
      local nm = okI and type(rinfo) == "table" and rinfo.name
      if nm == nil or nm == false then titleNil = titleNil + 1
      elseif nm == "" then titleEmpty = titleEmpty + 1
      elseif type(nm) == "string" and nm:find("|K", 1, true) then titleCoded = titleCoded + 1
      else
        titleText = titleText + 1
        -- One sample, escaped, so the report shows what a "readable" title looks like.
        if titleText == 1 then
          Note(string.format("sample title (%d chars): %s", #nm, (nm:sub(1, 40):gsub("|", "||"))))
        end
      end
    end
    local members = LFt:Members(id) or {}
    for _, m in ipairs(members) do
      specTotal = specTotal + 1
      if m.specID then specKnown = specKnown + 1 end
    end
    if not firstShown and hasPlayer then
      local okP, info = pcall(C_LFGList.GetSearchResultPlayerInfo, id, 1)
      if okP and type(info) == "table" then
        local keys = {}
        for k, v in pairs(info) do keys[#keys + 1] = tostring(k) .. "=" .. (Verify.IsNameField(k) and "<name>" or tostring(v)) end
        table.sort(keys)
        Note("first member fields: " .. table.concat(keys, ", "))
        firstShown = true
      end
    end
    if key and LFt:PlayerMember() then
      local okR, res = pcall(LFt.ForResult, LFt, id)
      if okR and res and tested <= 3 then
        Note(string.format("result %d %s: %s %d (adds %d, maybe %d, not guaranteed %d, still missing %d)", id,
          ns.Dungeons.list[key].name, res.rating.word, res.score, #res.adds, #res.maybeAdds, #res.maybe, #res.still))
      elseif not okR then
        Add("FAIL", "evaluating result " .. id .. " errored: " .. tostring(res))
      end
    end
  end
  Add(dungeonHits > 0 and "OK" or "WARN", string.format("Season dungeons recognized in %d of %d results checked", dungeonHits, tested))
  -- Informational only: listing fit is designed to work without the title (dungeon needs
  -- only); a readable level just adds that key's affixes.
  Add(titleLevels > 0 and "OK" or "INFO", string.format("key level from listing titles: %d of %d (titles: %d protected, %d hidden, %d encoded, %d empty, %d readable)%s",
    titleLevels, tested, titleBlocked, titleNil, titleCoded, titleEmpty, titleText,
    titleLevels == 0 and " - expected; listing fit uses dungeon needs only" or ""))
  Add(specTotal == 0 and "WARN" or (specKnown == specTotal and "OK" or "WARN"),
    string.format("member specs identified: %d of %d%s", specKnown, specTotal,
      (specTotal > specKnown) and " (unidentified members count with their class's shared kit only)" or ""))
end

local function CheckGroup()
  Section("Party")
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  if n <= 1 then Add("WARN", "not in a group - join a party and re-run to test inspect-based spec detection"); return end
  local T = ns.Tracker
  T:Acquire("verify")
  T:Rescan()
  local known, pending = 0, 0
  for _, m in ipairs(T.members) do if m.pending then pending = pending + 1 else known = known + 1 end end
  T:Release("verify")
  Add(pending == 0 and "OK" or "WARN", string.format("party specs read: %d known, %d pending%s", known, pending,
    pending > 0 and " (inspects finish over a few seconds - re-run in ~10s)" or ""))
  -- In-key checks: roster reads the game hid (secret values) and roster scans that errored.
  local inKey = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and select(2, pcall(C_ChallengeMode.GetActiveChallengeMapID))
  local hidden, errs = T.secretReads or 0, T.rescanErrors or 0
  if hidden > 0 then
    Add("WARN", string.format("party reads hidden by the game (secret values): %d since login; those members show as spec pending", hidden))
  else
    Add(inKey and "OK" or "INFO", "party reads hidden by the game: none" .. (inKey and " during this key" or " so far (re-run inside a key to check)"))
  end
  if errs > 0 then
    Add("FAIL", string.format("roster scans or inspects that errored: %d (last: %s); the next roster change tries again", errs, tostring(T.lastRescanError)))
  end
end

local function ListFlags()
  Section("Still marked unconfirmed in the data")
  local n = 0
  for _, id in ipairs({ 1480 }) do
    if ns.UD.specs[id] and ns.UD.specs[id].verify then Add("INFO", "spec " .. id .. " (" .. ns.UD.specs[id].name .. ") kit unconfirmed"); n = n + 1 end
  end
  -- One line per ability: which specs have it and every need it covers.
  local byName, names = {}, {}
  for _, p in pairs(ns.UD.specs) do
    if not p.verify then
      for key, list in pairs(p.caps) do
        for _, e in ipairs(list) do
          if e.verify then
            local b = byName[e.name]
            if not b then b = { specs = {}, caps = {} }; byName[e.name] = b; names[#names + 1] = e.name end
            b.specs[p.name] = true
            local info = ns.UD.CAP_INFO and ns.UD.CAP_INFO[key]
            b.caps[(info and info.label) or key] = true
          end
        end
      end
    end
  end
  local function Keys(t) local out = {} for k in pairs(t) do out[#out + 1] = k end table.sort(out) return table.concat(out, ", ") end
  table.sort(names)
  for _, name in ipairs(names) do
    Add("INFO", "utility: " .. name .. " (" .. Keys(byName[name].specs) .. ") - " .. Keys(byName[name].caps)); n = n + 1
  end
  for _, key in ipairs(ns.Dungeons.order) do
    for _, req in ipairs(ns.Dungeons.list[key].requirements) do
      if req.confidence ~= "verified" then Add("INFO", "dungeon: " .. req.id .. " - " .. req.source); n = n + 1 end
    end
  end
  local bd = ns.BossData
  if bd then
    for _, key in ipairs(ns.Dungeons.order) do
      for _, b in ipairs(bd.list[key] or {}) do
        for _, l in ipairs(b.lines) do
          if l.nv then Add("INFO", "boss card: " .. b.name .. " (" .. l.role .. ") - " .. l.text); n = n + 1 end
        end
      end
    end
  end
  if n == 0 then Add("OK", "nothing left unconfirmed") end
end

-- Boss cards: the events the window follows, the encounter journal, and (inside a dungeon)
-- whether the game's boss names match the cards.
local function CheckBosses()
  Section("Boss cards")
  local BC, BD = ns.BossCards, ns.BossData
  if not (BC and BD) then Add("FAIL", "boss card modules not loaded"); return end
  local missing = {}
  for _, ev in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "CHALLENGE_MODE_START" }) do
    if BC.eventsOK[ev] == false then missing[#missing + 1] = ev end
  end
  if #missing > 0 then Add("FAIL", "events not accepted: " .. table.concat(missing, ", ") .. " (the window can't follow bosses; use its arrows)")
  elseif next(BC.eventsOK) == nil then Add("WARN", "boss events not registered yet")
  else Add("OK", "encounter events accepted (window follows boss pulls and kills)") end
  local cards, empty = 0, {}
  for _, key in ipairs(ns.Dungeons.order) do
    local n = #(BD.list[key] or {})
    cards = cards + n
    if n == 0 then empty[#empty + 1] = ns.Dungeons.list[key].name end
  end
  Add(#empty == 0 and "OK" or "WARN", string.format("%d boss cards%s", cards, #empty > 0 and (" (none for " .. table.concat(empty, ", ") .. ")") or ""))
  local CEJ = rawget(_G, "C_EncounterJournal")
  local hasEnc = rawget(_G, "EJ_GetEncounterInfoByIndex")
  local hasGame = type(CEJ) == "table" and CEJ.GetInstanceForGameMap
  local hasUI = rawget(_G, "EJ_GetInstanceForMap") and type(rawget(_G, "C_Map")) == "table" and C_Map.GetBestMapForUnit
  if not hasEnc or not (hasGame or hasUI) then
    Add("INFO", "encounter journal functions missing: bosses are matched by name only (English clients), no journal ability links")
  else
    Add(hasGame and "OK" or "WARN", hasGame and "C_EncounterJournal.GetInstanceForGameMap present (journal found for any dungeon, anywhere)"
      or "C_EncounterJournal.GetInstanceForGameMap missing: the journal is only found inside a dungeon (EJ_GetInstanceForMap fallback)")
    local hasSelect = rawget(_G, "EJ_SelectInstance")
    Add(hasSelect and "OK" or "WARN", hasSelect and "EJ_SelectInstance present (each journal read selects the dungeon first)"
      or "EJ_SelectInstance missing: the journal may list no bosses or abilities (no ability links; boss kills matched by name)")
    -- Each Season dungeon's journal instance, and which call found it.
    local found, parts = 0, {}
    for _, key in ipairs(ns.Dungeons.order) do
      local jid, how = BC:JournalInstance(key)
      if jid then found = found + 1 end
      parts[#parts + 1] = ns.Dungeons.list[key].name .. " " .. tostring(ns.Dungeons.INSTANCE_MAP_IDS[key]) .. " -> "
        .. (jid and (jid .. " (" .. how .. ")") or "not found")
    end
    Add(found == #ns.Dungeons.order and "OK" or "WARN", string.format("journal found for %d of %d dungeons%s", found,
      #ns.Dungeons.order, found < #ns.Dungeons.order and " (outside a dungeon, the fallback only works inside it)" or ""))
    for _, p in ipairs(parts) do Note(p) end
  end
  -- Ability links on the cards: how many names the journal (plus the dungeon data) turns
  -- into links, for the dungeon you're in or your keystone's.
  local linkDk = BC:CurrentDungeon()
  if not linkDk and ns.OwnKeystoneDungeon then
    local okK, k = pcall(ns.OwnKeystoneDungeon, ns)
    linkDk = okK and k or nil
  end
  if linkDk and BD.list[linkDk] then
    local fromJournal, linked, lines = Util_Count(BC:JournalSpells(linkDk)), 0, 0
    for _, card in ipairs(BD.list[linkDk]) do
      for _, l in ipairs(card.lines) do
        lines = lines + 1
        local _, n = BC:Decorate(linkDk, l.text):gsub("|Haddon:", "")
        if n > 0 then linked = linked + 1 end
      end
    end
    local linkJid = BC:JournalInstance(linkDk)
    -- #13: a found journal with no abilities is a failed read (WARN); no journal at all stays INFO.
    Add(fromJournal > 0 and "OK" or (linkJid and "WARN" or "INFO"), string.format("%s: %d boss abilities from the journal%s; %d of %d card lines have ability links",
      ns.Dungeons.list[linkDk].name, fromJournal,
      (fromJournal == 0 and linkJid) and (" (journal " .. linkJid .. " found but read empty)") or "", linked, lines))
  end
  local dk = BC:CurrentDungeon()
  if dk then
    local ids = BC:EncounterIDs(dk)
    local hereJid = BC:JournalInstance(dk)
    if ids then
      local unmatched = {}
      for name, n in pairs(ids.byName) do
        local card = BD.list[dk][n]
        if not card then unmatched[#unmatched + 1] = name end
      end
      Add(#unmatched == 0 and "OK" or "WARN", "journal bosses here: " .. Util_Count(ids.byName) .. ", cards: " .. #BD.list[dk]
        .. (#unmatched > 0 and (" (no card for: " .. table.concat(unmatched, ", ") .. ")") or ""))
    elseif hereJid then
      -- #13: the journal was found but listed no bosses (a failed read, not a pass).
      Add("WARN", string.format("journal bosses here: 0, cards: %d (journal %d found but read empty: boss kills are matched by name only)",
        #BD.list[dk], hereJid))
    end
    Add("INFO", string.format("inside %s: showing boss %d, killed %d", ns.Dungeons.list[dk].name, BC.state.index or 0,
      Util_Count(BC.state.killed or {})))
  else
    Add("INFO", "not inside a Season dungeon (run /ens verify inside one to check boss matching)")
  end
end

---------------------------------------------------------------------------
-- Report window (copyable)
---------------------------------------------------------------------------
local function ShowReport(text, title)
  local f = Verify.frame
  if not f then
    f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(680, 460)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.055, 0.059, 0.071, 0.97); f:SetBackdropBorderColor(0.165, 0.176, 0.212, 1)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -32); sf:SetPoint("BOTTOMRIGHT", -32, 44)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(ChatFontNormal); eb:SetWidth(620)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.report or "") end end)
    sf:SetScrollChild(eb)
    f.edit = eb
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(90, 22); close:SetPoint("BOTTOMRIGHT", -12, 12); close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)
    local sel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    sel:SetSize(110, 22); sel:SetPoint("RIGHT", close, "LEFT", -8, 0); sel:SetText("Select all")
    sel:SetScript("OnClick", function() eb:SetFocus(); eb:HighlightText() end)
    Verify.frame = f
  end
  f.title:SetText("Ensemble - " .. (title or "verify report") .. "   (click in the box, Ctrl+A then Ctrl+C to copy)")
  f.report = text
  f.edit:SetText(text)
  f:Show()
  f.edit:SetFocus(); f.edit:HighlightText()
end

-- Shared copy window (also used by /ens report). Editable only for selecting and copying.
function Verify:ShowText(text, title)
  return pcall(ShowReport, text, title)
end

---------------------------------------------------------------------------
-- Build the report without showing it: returns text, counts, lines.
function Verify:Build()
  lines, counts = {}, {}
  local version, build, date, toc = "?", "?", "?", "?"
  if GetBuildInfo then version, build, date, toc = GetBuildInfo() end
  lines[#lines + 1] = string.format("Ensemble %s - client %s (%s, toc %s) - locale %s",
    tostring(ns.VERSION), tostring(version), tostring(build), tostring(toc), tostring(GetLocale and GetLocale() or "?"))
  lines[#lines + 1] = ns.Dungeons:FreshnessText()
  Try("client functions", CheckAPIs)
  Try("specs", CheckSpecs)
  Try("spell IDs", CheckSpells)
  Try("dungeons", CheckDungeons)
  Try("affixes", CheckAffixes)
  Try("history", CheckHistory)
  Try("group finder", CheckGroupFinder)
  Try("fill group", CheckFill)
  Try("group finder search", CheckSearch)
  Try("party", CheckGroup)
  Try("boss cards", CheckBosses)
  Try("flags", ListFlags)
  table.insert(lines, 2, string.format("Summary: %d OK, %d WARN, %d FAIL, %d INFO",
    counts.OK or 0, counts.WARN or 0, counts.FAIL or 0, counts.INFO or 0))
  local text = table.concat(lines, "\n")
  return text, counts, lines
end

---------------------------------------------------------------------------
-- /ens verify season: the raw facts a season (or patch) update starts from, in one block to
-- paste into an update session: the game's Mythic+ dungeon pool with challenge and
-- instance map IDs and timers, each dungeon's bosses and their journal abilities with
-- spell IDs, and this week's affixes; each marked as known to the addon or NEW.
---------------------------------------------------------------------------
local function JournalBossList(jid, getEnc, getSec)
  local bosses = {}
  for n = 1, 12 do
    local ok2, name, _, _, rootSection, _, _, encounterID = pcall(getEnc, n, jid)
    if not ok2 or not name then break end
    local boss = { name = name, encounterID = encounterID, spells = {} }
    if getSec and rootSection then
      local stack, steps, seen = { rootSection }, 0, {}
      while #stack > 0 and steps < 400 do
        steps = steps + 1
        local id = table.remove(stack)
        local ok3, info = pcall(getSec, id)
        if ok3 and type(info) == "table" then
          if type(info.title) == "string" and type(info.spellID) == "number" and info.spellID > 0 and not seen[info.title] then
            seen[info.title] = true
            boss.spells[#boss.spells + 1] = info.title .. "=" .. info.spellID
          end
          if info.siblingSectionID then stack[#stack + 1] = info.siblingSectionID end
          if info.firstChildSectionID then stack[#stack + 1] = info.firstChildSectionID end
        end
      end
    end
    bosses[#bosses + 1] = boss
  end
  return bosses
end

local function JournalBosses(instanceMapID)
  local getEnc = rawget(_G, "EJ_GetEncounterInfoByIndex")
  local CEJ = rawget(_G, "C_EncounterJournal")
  local getSec = type(CEJ) == "table" and CEJ.GetSectionInfo
  if not (instanceMapID and getEnc and ns.BossCards) then return nil end
  local dk = ns.Dungeons.KeyForInstanceMap and ns.Dungeons:KeyForInstanceMap(instanceMapID) or nil
  local jid = ns.BossCards:JournalInstance(dk, instanceMapID)
  if not jid then return nil end
  -- The journal must have this instance selected to answer (#12).
  return ns.BossCards:WithJournalInstance(jid, function(j) return JournalBossList(j, getEnc, getSec) end), jid
end

function Verify:BuildSeason()
  local out = {}
  local function add(t) out[#out + 1] = t end
  local version, build, _, toc = "?", "?", "?", "?"
  if GetBuildInfo then version, build, _, toc = GetBuildInfo() end
  add(string.format("Ensemble %s - season data - client %s (%s, toc %s) - locale %s", tostring(ns.VERSION),
    tostring(version), tostring(build), tostring(toc), tostring(GetLocale and GetLocale() or "?")))
  local DD, BD = ns.Dungeons, ns.BossData
  add("")
  add("== Mythic+ dungeons in the game ==")
  local okM, maps = false, nil
  if C_ChallengeMode and C_ChallengeMode.GetMapTable then okM, maps = pcall(C_ChallengeMode.GetMapTable) end
  local inGame = {}
  if not okM or type(maps) ~= "table" or #maps == 0 then
    add("(not loaded yet - open the Group Finder's Mythic+ tab and run /ens verify season again)")
  else
    table.sort(maps)
    for _, mapID in ipairs(maps) do
      inGame[mapID] = true
      local okI, name, _, timeLimit, _, _, instanceMapID = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
      local key = DD:KeyForChallengeMap(mapID)
      add(string.format("%d | %s | instance %s | timer %s | %s", mapID, tostring(okI and name or "?"), tostring(okI and instanceMapID or "?"),
        (okI and type(timeLimit) == "number") and string.format("%d:%02d", math.floor(timeLimit / 60), timeLimit % 60) or "?",
        key and ("addon: " .. key) or "NEW"))
      local bosses, jid
      if okI then bosses, jid = JournalBosses(instanceMapID) end
      if bosses and #bosses == 0 then
        add(string.format("  (journal %s found but lists no bosses: the journal didn't answer, re-run later)", tostring(jid)))
      elseif bosses then
        local cards = key and BD and BD.list[key] or {}
        for i, b in ipairs(bosses) do
          local card = cards[i]
          local mark = (not key) and "" or (card and card.name == b.name and "" or ("  <- addon card: " .. (card and card.name or "none")))
          add(string.format("  boss %d: %s (encounter %s)%s", i, b.name, tostring(b.encounterID), mark))
          if #b.spells > 0 then add("    " .. table.concat(b.spells, ", ")) end
        end
      else
        add("  (encounter journal not available for this dungeon)")
      end
    end
    for _, key in ipairs(DD.order) do
      if not inGame[DD.CHALLENGE_MAP_IDS[key]] then add("addon only (not in the game's list): " .. DD.list[key].name .. " (" .. key .. ")") end
    end
  end
  add("")
  add("== This week's affixes ==")
  local AF = ns.Affixes
  if AF then
    pcall(AF.Refresh, AF)
    local cur = AF:Current()
    if #cur == 0 then add("(not loaded yet - open the Group Finder's Mythic+ tab and run it again)") end
    for _, a in ipairs(cur) do
      add(string.format("%d | %s | %s", a.id, tostring(a.name), a.def and ("addon: " .. a.def.key) or "NEW"))
    end
  end
  return table.concat(out, "\n")
end

function Verify:RunSeason()
  local text = self:BuildSeason()
  if ns.db then ns.db.lastSeason = text end
  if not pcall(ShowReport, text, "season data") then
    ns:Print("Could not open the report window; the data is in EnsembleDB.lastSeason after /reload.")
  end
  return text
end

function Verify:Run()
  local text, counts = self:Build()
  self.lastReport = text
  ns:Print(string.format("Verify: %d OK, %d WARN, %d FAIL. Copy the report from the window and paste it back.",
    counts.OK or 0, counts.WARN or 0, counts.FAIL or 0))
  local ok = pcall(ShowReport, text)
  if not ok then ns:Print("Could not open the report window; the report is in EnsembleDB.lastVerify after /reload.") end
  if ns.db then ns.db.lastVerify = text end
  return text
end
