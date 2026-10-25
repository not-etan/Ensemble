-- Headless scenario tests. Run with LuaJIT via lupa. ADDON_DIR is set by the runner.
-- Load order comes straight from the TOC, so a file added there is always tested.
local FILES = {}
for line in io.lines(ADDON_DIR .. "/Ensemble.toc") do
  local f = line:match("^%s*([%w_]+%.lua)%s*$")
  if f then FILES[#FILES + 1] = f end
end

local fails, passes = 0, 0
local function ok(cond, msg)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. msg) end
end

local function boot(skipMeta)
  ALLFRAMES = {}
  local ns = {}
  for _, f in ipairs(FILES) do
    if not (skipMeta and f == "MetaData.lua") then
      local chunk = assert(loadfile(ADDON_DIR .. "/" .. f))
      chunk("Ensemble", ns)
    end
  end
  -- fire ADDON_LOADED / PLAYER_LOGIN on the boot frame
  for _, fr in ipairs(ALLFRAMES) do
    if fr._events.ADDON_LOADED then
      fr._scripts.OnEvent(fr, "ADDON_LOADED", "Ensemble")
      fr._scripts.OnEvent(fr, "PLAYER_LOGIN")
    end
  end
  -- The first-run tour would take over the window in every test; test 51 runs it on purpose.
  if ns.db and not KEEP_TOUR then ns.db.tourSeen = true end
  return ns
end

local function hasFinding(r, pattern)
  for _, f in ipairs(r.findings) do if f.text:find(pattern) then return true end end
  return false
end
local function item(r, id)
  for _, it in ipairs(r.dungeon.items) do if it.req.id == id then return it end end
end

EnsembleDB = nil
local ns = boot()
local A, UD, DD = ns.Analysis, ns.UD, ns.Dungeons

-- Data integrity
ok(#DD:Validate() == 0, "DungeonData keys all valid")
ok(#DD.order == 8, "eight dungeons")
for _, key in ipairs(DD.order) do
  for _, req in ipairs(DD.list[key].requirements) do
    ok(UD:IsCap(req.need), key .. " need " .. tostring(req.need))
    for _, a in ipairs(req.alt or {}) do ok(UD:IsCap(a), key .. " alt " .. a) end
  end
end
local specCount = 0 for _ in pairs(UD.specs) do specCount = specCount + 1 end
ok(specCount == 40, "40 specs incl. Devourer (got " .. specCount .. ")")

-- 1. Five identical
local five = {} for i = 1, 5 do five[i] = { specID = 259 } end
local r = A:Analyze(five, nil, ns.db.settings)
ok(r.filled == 5, "five filled")
ok(#r.buffs.present == 0 and r.buffs.missing == nil, "5 rogues: no raid buffs present, none reported missing")
ok(not hasFinding(r, "raid buff"), "no missing-buff finding")
ok(hasFinding(r, "No battle resurrection"), "5x: no brez")
ok(hasFinding(r, "No Bloodlust"), "5x: no lust")
ok(hasFinding(r, "No Poison dispel") and hasFinding(r, "No Curse dispel"), "5x: dispel gaps")
ok(hasFinding(r, "melee%-only"), "5x: melee-only interrupts")
ok(hasFinding(r, "duplicate classes"), "5x: duplicate class")
ok(hasFinding(r, "one role"), "5x: stacked on one role")
print("5x summary: " .. r.summary)

-- 1b. Raid buffs are display-only
r = A:Analyze({ { specID = 73 }, { specID = 256 }, { specID = 62 } }, nil, ns.db.settings)
ok(#r.buffs.present == 3 and r.buffs.present[1].from ~= nil, "present buffs listed with provider")
local p1 = A:Penalty(r)
local r2 = A:Analyze({ { specID = 73 }, { specID = 256 }, { specID = 62 }, { specID = 259 } }, nil, ns.db.settings)
local r3 = A:Analyze({ { specID = 73 }, { specID = 256 }, { specID = 62 }, { specID = 269 } }, nil, ns.db.settings)
for _, f in ipairs(r3.findings) do ok(not f.text:find("Mystic Touch"), "buff never appears as a finding") end
for _, f in ipairs(r2.findings) do ok(f.check ~= "buffs", "no buffs check findings") end
-- 1c. Raid buff synergy
local function buff(r, key) for _, b in ipairs(r.buffs.present) do if b.key == key then return b end end end
r = A:Analyze({ { specID = 581 }, { specID = 256 }, { specID = 63 }, { specID = 258 }, { specID = 102 } }, nil, ns.db.settings)
local cb = buff(r, "CHAOS_BRAND")
ok(cb and cb.strength == "strong" and #cb.full >= 3, "Chaos Brand strong with 3 magic DPS")
ok(r.synergyPoints > 0, "synergy points counted")
r = A:Analyze({ { specID = 270 }, { specID = 63 }, { specID = 258 }, { specID = 102 } }, nil, ns.db.settings)
ok(buff(r, "MYSTIC_TOUCH").strength == "none", "Mystic Touch little value with all-magic group")
ok(buff(r, "ARCANE_INTELLECT").strength == "strong", "Arcane Intellect strong with int users")
local magicCore = { { specID = 63 }, { specID = 258 }, { specID = 102 } }
local withDH = A:Analyze({ magicCore[1], magicCore[2], magicCore[3], { specID = 577 } }, nil, ns.db.settings)
local withWW = A:Analyze({ magicCore[1], magicCore[2], magicCore[3], { specID = 269 } }, nil, ns.db.settings)
ok(withDH.synergyPoints > withWW.synergyPoints, "Havoc (Chaos Brand) out-synergizes Windwalker for casters")
local d = A:SynergyDelta(A:Analyze(magicCore, nil, ns.db.settings), withDH)
ok(d[1] and d[1].key == "CHAOS_BRAND" and d[1].long:find("Fire"), "synergy delta explains Chaos Brand")
r = A:Analyze({ { classFile = "DEMONHUNTER" }, { specID = 63 } }, nil, ns.db.settings)
ok(buff(r, "CHAOS_BRAND") ~= nil, "pending DH still shows Chaos Brand")
-- Suggestions mention synergy when it is a reason
local sug = A:SuggestClasses({ { specID = 66 }, { specID = 256 }, { specID = 63 }, { specID = 258 }, nil }, ns.SLOT_ROLES, nil, ns.db.settings, 40)
local mentions = false
for _, g in ipairs(sug) do for _, c in ipairs(g.classes) do for _, f in ipairs(c.reasons) do
  if f:find("Chaos Brand") or f:find("Arcane Intellect") or f:find("Battle Shout") then mentions = true end
end end end
ok(mentions, "suggestion reasons cite buff synergy")

-- 2. Partial
r = A:Analyze({ { specID = 73 }, { specID = 264 } }, nil, ns.db.settings)
ok(r.filled == 2 and r.summary:find("2/5"), "partial comp summary")
r = A:Analyze({}, "AltarOfFangs", ns.db.settings)
ok(r.filled == 0, "empty comp ok")

-- 3. Altar of Fangs, zero poison dispels
local noPoison = { { specID = 73 }, { specID = 256 }, { specID = 63 }, { specID = 71 }, { specID = 260 } }
r = A:Analyze(noPoison, "AltarOfFangs", ns.db.settings)
ok(#r.caps.dispel_poison == 0, "comp truly has no poison dispel")
local it = item(r, "AOF_ENVENOM_POISON")
ok(it and it.status == "missing", "AoF poison missing")
ok(r.dungeon.gaps[1].req.need == "dispel_poison", "poison is top gap (got " .. r.dungeon.gaps[1].req.id .. ")")
ok(r.summary:find("Poison") and r.summary:find("Envenom"), "summary mentions poison + Envenom: " .. r.summary)
print("AoF summary: " .. r.summary)
-- suggestions for the open slot prefer a poison dispeller
local slots = { { specID = 73 }, { specID = 256 }, { specID = 63 }, { specID = 71 }, nil }
local sugg = A:SuggestClasses(slots, ns.SLOT_ROLES, "AltarOfFangs", ns.db.settings, 5)
ok(#sugg == 1 and sugg[1].role == "DAMAGER" and #sugg[1].classes > 0, "suggestions returned for the open DPS slot")
local anyPoison = false
for _, c in ipairs(sugg[1].classes) do
  local p = UD:GetSpec(c.best)
  if p.caps.dispel_poison then anyPoison = true end
  print(string.format("  suggest %s %s (gain %.1f): %s", p.name, p.class, c.gain, table.concat(c.reasons, "; ")))
end
ok(anyPoison, "a suggestion adds a poison dispeller")
ok(UD:GetSpec(sugg[1].classes[1].best).caps.dispel_poison ~= nil, "top suggestion closes the poison gap")
-- Memoized: the same group returns the same answer; a settings change recomputes it.
local again = A:SuggestClasses(slots, ns.SLOT_ROLES, "AltarOfFangs", ns.db.settings, 5)
ok(again == sugg, "suggestions reused while nothing changed")
ns.db.settings.ignoredNeeds.dispel_poison = true
local without = A:SuggestClasses(slots, ns.SLOT_ROLES, "AltarOfFangs", ns.db.settings, 5)
ok(without ~= sugg, "ignoring a need recomputes the suggestions")
ns.db.settings.ignoredNeeds.dispel_poison = nil
do
  local mm, bm = UD:GetSpec(254), UD:GetSpec(253)
  local lust = mm.caps.bloodlust and mm.caps.bloodlust[1]
  ok(lust and lust.name == "Harrier's Cry" and not lust.pet and not lust.conditional and not lust.verify, "Marksmanship brings its own Bloodlust (Harrier's Cry), no pet needed")
  ok(mm.caps.freedom and mm.caps.freedom[1].talent and not mm.caps.freedom[1].pet, "Marksmanship Master's Call comes from a talent, not a pet")
  ok(bm.caps.bloodlust[1].name:find("Primal Rage", 1, true) and bm.caps.bloodlust[1].pet, "Beast Mastery keeps pet Primal Rage")
end

-- 12.1 class audit (Wowhead class guides)
do
  local function names(list) local t = {} for _, e in ipairs(list or {}) do t[#t + 1] = e.name end return table.concat(t, ",") end
  local function hasCC(id, n) for _, c in ipairs(UD:GetSpec(id).cc) do if c.name == n then return c end end end
  local mf = UD:GetSpec(250).caps.interrupt[1]
  ok(mf.talent and mf.core and not UD:IsSoft(mf), "core talent (Mind Freeze) is marked talent but counts as reliable")
  ok(UD:IsSoft(UD:GetSpec(103).caps.soothe[1]), "optional talent (Soothe) stays not guaranteed")
  local off = { countTalentSources = false }
  ok(UD:Sources(UD:GetSpec(250), "interrupt", off) ~= nil and UD:Sources(UD:GetSpec(103), "soothe", off) == nil,
    "'count talent sources' off still keeps core talents, drops optional ones")
  local rd = UD:GetSpec(105).caps
  ok(not rd.dispel_curse[1].talent and not rd.dispel_poison[1].talent, "Resto Druid gets Improved Nature's Cure free")
  for _, id in ipairs({ 62, 63, 64 }) do
    ok(hasCC(id, "Dragon's Breath") and hasCC(id, "Supernova") and not hasCC(id, "Blast Wave"), "mage " .. id .. ": Dragon's Breath/Supernova choice, no Blast Wave")
  end
  local dev = UD:GetSpec(1480)
  ok(hasCC(1480, "Void Nova") and not hasCC(1480, "Chaos Nova") and not dev.caps.interrupt[1].verify, "Devourer: Void Nova, kit confirmed")
  ok(not hasCC(260, "Between the Eyes"), "Outlaw: Between the Eyes no longer a stun")
  ok(not hasCC(258, "Psychic Horror") and not hasCC(254, "Bursting Shot") and not hasCC(254, "Scatter Shot"), "Psychic Horror and Bursting Shot removed, Scatter Shot PvP-only")
  local ts = hasCC(262, "Thunderstorm")
  ok(ts and not ts.verify and not hasCC(263, "Thunderstorm") and not hasCC(264, "Thunderstorm"), "Thunderstorm: Elemental only, confirmed")
  ok(not hasCC(577, "Fel Eruption") and not hasCC(581, "Fel Eruption") and not hasCC(1480, "Fel Eruption"), "Fel Eruption removed from the game")
  local sw = 0
  for _, c in ipairs(UD:GetSpec(73).cc) do if c.name == "Shockwave" then sw = sw + 1 end end
  ok(sw == 1 and hasCC(73, "Disrupting Shout"), "Prot Warrior: one Shockwave, plus Disrupting Shout")
  local mmI = hasCC(254, "Intimidation")
  ok(mmI and not mmI.pet and UD:GetSpec(254).caps.external_defensive == nil, "Marksmanship: petless Intimidation, no pet external")
  ok(UD:GetSpec(253).caps.freedom[1].conditional == "Cunning pet out", "BM Master's Call needs a Cunning pet")
  ok(UD:GetSpec(66).caps.battle_rez and UD:GetSpec(70).caps.battle_rez, "Intercession on every Paladin spec")
  ok(names(UD:GetSpec(66).caps.interrupt):find("Avenger's Shield", 1, true), "Prot Paladin: Avenger's Shield interrupt")
  ok(UD:GetSpec(1468).caps.soothe and UD:GetSpec(270).caps.soothe, "Evoker and Monk soothes added (talent)")
  ok(not UD:GetSpec(265).caps.dispel_magic[1].verify, "Singe Magic (Imp) confirmed")
  -- every interrupt is either baseline, a core talent, a pet or a known long/optional source
  local bad = {}
  for id, p in pairs(UD.specs) do
    for _, e in ipairs(p.caps.interrupt or {}) do
      if e.talent and not e.core and e.name ~= "Avenger's Shield" and not e.name:find("Fel Ravager", 1, true) then bad[#bad + 1] = id .. ":" .. e.name end
    end
  end
  ok(#bad == 0, "primary interrupts are reliable: " .. table.concat(bad, " "))
end

-- 4. alt capability: Paralyzing Shots via freedom
r = A:Analyze({ { specID = 70 }, { specID = 72 } }, "AltarOfFangs", ns.db.settings)
it = item(r, "AOF_PARALYZE")
ok(#r.caps.dispel_magic == 0, "ret+fury has no magic dispel")
-- Blessing of Freedom is an optional talent in 12.1 (choice node), so freedom alone is thin.
ok(it.status == "thin", "Paralyzing Shots: talent-only freedom is thin (got " .. it.status .. ")")

-- 5. needs_verification never "missing"; returning dungeons not falsely clean
for _, key in ipairs({ "RubyLifePools", "KingsRest", "TempleOfSethraliss" }) do
  r = A:Analyze(noPoison, key, ns.db.settings)
  for _, x in ipairs(r.dungeon.items) do
    if x.unconfirmed then ok(x.status ~= "missing", key .. " " .. x.req.id .. " unconfirmed but missing") end
  end
  ok(#r.dungeon.gaps > 0 or r.dungeon.incomplete or r.dungeon.unconfirmedCount == 0 or r.summary:find("unconfirmed"), key .. " not falsely clean")
  print(key .. ": " .. r.summary)
end
-- synthetic all-unverified dungeon
DD.list.FakeDungeon = { name = "Fake", requirements = {
  { id = "F1", need = "dispel_bleed", severity = "critical", minProviders = 1, source = "x", confidence = "needs_verification" } } }
r = A:Analyze({ { specID = 71 } }, "FakeDungeon", ns.db.settings)
ok(r.dungeon.incomplete, "fake dungeon incomplete")
ok(r.dungeon.items[1].status == "thin", "unverified gap capped at thin")
ok(r.summary:find("incomplete"), "summary says incomplete")
DD.list.FakeDungeon = nil

-- 6. nil / unknown dungeon
r = A:Analyze(noPoison, nil, ns.db.settings); ok(r.dungeon == nil, "nil dungeon")
r = A:Analyze(noPoison, "Nope", ns.db.settings); ok(r.dungeon.unknown, "unknown dungeon flagged")

-- 7. Holy Paladin fallback brez
r = A:Analyze({ { specID = 65 }, { specID = 71 } }, nil, ns.db.settings)
ok(r.brez.fallbackOnly and hasFinding(r, "Intercession"), "Intercession is fallback-only")
r = A:Analyze({ { specID = 65 }, { specID = 250 } }, nil, ns.db.settings)
ok(r.brez.count == 1 and not r.brez.fallbackOnly, "Intercession ignored when DK present")

-- 8. Pending spec member
r = A:Analyze({ { classFile = "PALADIN" }, { specID = 71 } }, "AltarOfFangs", ns.db.settings)
ok(r.pendingCount == 1, "pending counted")
ok(#r.caps.freedom == 1, "pending paladin still provides class-wide freedom")
ok(#r.caps.interrupt == 1, "pending paladin not credited with Rebuke (Holy lacks it)")

-- 9. Category toggles
ns.db.settings.dungeonCategories.dispels = false
r = A:Analyze(noPoison, "AltarOfFangs", ns.db.settings)
ok(item(r, "AOF_ENVENOM_POISON") == nil and r.dungeon.hidden > 0, "dispel category hidden")
ns.db.settings.dungeonCategories.dispels = true

-- 10. Share strings
local s = ns.Share.Encode("My: comp", { 73, 264, 62, 0, 259 }, "KingsRest")
local d = ns.Share.Decode(s)
ok(d and d.name == "My  comp" and d.slots[2] == 264 and d.slots[4] == 0 and d.dungeon == "KingsRest", "share roundtrip")
ok(ns.Share.Decode(s:gsub("264", "265")) == nil, "tampered string rejected")
ok(ns.Share.Decode("garbage") == nil, "garbage rejected")

-- 11. Live tracking: join, pending spec, inspect, leave + replace
ROSTER = {
  player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
  party1 = { guid = "A", name = "Ann", class = "SHAMAN", role = "HEALER" },
  party2 = { guid = "B", name = "Bob", class = "MAGE", role = "DAMAGER" },
}
LISTING = "Murder Row (Mythic Keystone)"
ns.db.selectedDungeon = "NONE"
local UI = ns.UI
UI:Show("live")
RunTimers()
local T = ns.Tracker
ok(T.enabled, "tracker enabled in live tab")
ok(#T.members == 3, "3 members tracked")
local pend = 0 for _, m in ipairs(T.members) do if m.pending then pend = pend + 1 end end
ok(pend == 2, "2 pending specs before inspect")
ok(#NOTIFIED >= 1, "inspect requested")
local eff, src = ns:GetEffectiveDungeon()
ok(eff == "MurderRow" and src == "auto", "auto-detected listing dungeon")
ok(#T.applicants == 1 and T.applicants[1].specID == 264, "applicant spec read")
-- inspect returns
INSPECT_CACHE.A = 264
local trackerFrame
for _, fr in ipairs(ALLFRAMES) do if fr._events.INSPECT_READY then trackerFrame = fr end end
trackerFrame._scripts.OnEvent(trackerFrame, "INSPECT_READY", "A")
RunTimers()
local annSpec
for _, m in ipairs(T.members) do if m.name == "Ann" then annSpec = m.specID end end
ok(annSpec == 264, "inspect resolved Ann's spec")
-- Bob leaves, Cid joins
ROSTER.party2 = { guid = "C", name = "Cid", class = "ROGUE", role = "DAMAGER" }
trackerFrame._scripts.OnEvent(trackerFrame, "GROUP_ROSTER_UPDATE")
trackerFrame._scripts.OnEvent(trackerFrame, "GROUP_ROSTER_UPDATE")
trackerFrame._scripts.OnEvent(trackerFrame, "GROUP_ROSTER_UPDATE")
RunTimers()
local names = {}
for _, m in ipairs(T.members) do names[#names + 1] = m.name end
local joined = table.concat(names, ",")
ok(not joined:find("Bob") and joined:find("Cid"), "roster replaced: " .. joined)
local comp = T:GetComp()
r = A:Analyze(comp, ns:GetEffectiveDungeon(), ns.db.settings)
ok(r.filled == 3, "live analysis has 3 members")
-- manual selection beats auto
ns:SetManualDungeon("AltarOfFangs")
eff, src = ns:GetEffectiveDungeon()
ok(eff == "AltarOfFangs" and src == "manual", "manual wins over listing")
RunTimers()
LISTING = nil
trackerFrame._scripts.OnEvent(trackerFrame, "LFG_LIST_ACTIVE_ENTRY_UPDATE"); RunTimers()
ok(ns.state.liveDungeon == "AltarOfFangs" and ns:GetEffectiveDungeon() == "AltarOfFangs", "manual not overwritten when listing goes away")
ok(T.hosting == false, "not hosting after delist")

-- 12. UI smoke over every tab, both views, with and without dungeon
for _, compact in ipairs({ false, true }) do
  ns.db.settings.compact = compact
  for _, tab in ipairs({ "builder", "live", "applicants", "dungeons", "plan", "history", "settings" }) do
    UI:Show(tab); RunTimers()
  end
end
ok(not T.enabled, "tracker disabled after leaving live tab")
UI:Show("builder"); RunTimers()
ns.db.currentComp = { 73, 256, 63, 71, 260 }
UI.cp.nameBox:SetText("Test")
UI:SaveCurrent(); UI:SaveCurrent()
ok(#ns.db.savedComps == 1, "save with same name updates in place")
do -- planner actions fit their column (Saved used to run into Needs)
  local cp, g = UI.cp, 6
  local top = cp.nameBox:GetWidth() + g + cp.saveBtn:GetWidth() + g + cp.savedBtn:GetWidth()
  local bottom = cp.exportBtn:GetWidth() + g + cp.clearBtn:GetWidth() + g + cp.copyLiveBtn:GetWidth()
  ok(top == bottom and top == cp.actionsRowW and top <= cp.actions:GetWidth()
    and cp.savedBtn:GetWidth() == cp.copyLiveBtn:GetWidth(), "Save/Saved row fits the column and lines up with the row below: " .. top .. "/" .. cp.actions:GetWidth())
end
local okImp = UI:ImportString(ns.Share.Encode("Other", { 581, 264, 62, 1473, 259 }, "NONE"))
ok(okImp and #ns.db.savedComps == 2, "import adds a comp")
ok(UI.pages.saved == nil and UI.tabButtons.saved == nil and UI.tabButtons.composition and UI.tabButtons.plan, "tabs: Saved folded into Composition, Plan added")
UI:Hide()
ok(not T.enabled, "tracker off when hidden")

-- 13. Meta feature removed: no tab, no data
ok(ns.MetaData == nil and UI.pages.meta == nil and UI.GetMeta == nil, "meta feature fully removed")
-- 14. Persistence across /reload (same SavedVariables table, fresh addon state)
ns.db.selectedDungeon = "KingsRest"
local before = #ns.db.savedComps
local ns2 = boot()
ok(ns2.db.selectedDungeon == "KingsRest", "dungeon persists")
ok(#ns2.db.savedComps == before, "saved comps persist")
ns2.UI:Show("builder"); RunTimers(); ns2.UI:Hide()

-- 15. Damaged saved data is cleaned up on load
EnsembleDB = { savedComps = { { name = "Alpha", slots = { 73 } }, "junk" }, currentComp = "x" }
local ns3 = boot()
ok(ns3.db.schema == 4, "schema set")
ok(#ns3.db.savedComps == 1 and ns3.db.savedComps[1].name == "Alpha", "junk comp dropped")
ok(ns3.db.savedComps[1].slots[5] == 0, "short slots padded")
ok(type(ns3.db.currentComp) == "table" and ns3.db.currentComp[1] == 0, "bad currentComp reset")

-- 16. Slash commands
ns3:SetManualDungeon("TempleOfSethraliss")
ok(ns3.db.selectedDungeon == "TempleOfSethraliss", "dungeon picked")
SlashCmdList.ENSEMBLE("reset")
ok(ns3.db.selectedDungeon == "TempleOfSethraliss", "reset needs confirm")
SlashCmdList.ENSEMBLE("reset confirm")
ok(ns3.db.selectedDungeon == "AUTO", "reset confirm works")


-- 17. Applicant fit (new feature)
do
  EnsembleDB = nil
  local nsF = boot()
  local Fit, TT, UIF = nsF.ApplicantFit, nsF.Tracker, nsF.UI
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
    party2 = { guid = "M", name = "Mia", class = "MAGE", role = "DAMAGER" },
  }
  INSPECT_CACHE = { H = 256, M = 63 }
  LISTING = "Altar of Fangs (Mythic Keystone)"
  APPLICANTS = {
    [1] = { { name = "Shamy", class = "SHAMAN", role = "HEALER", spec = 264 } },
    [2] = { { name = "Stabby", class = "ROGUE", role = "DAMAGER", spec = 259, score = 3100 } },
    [3] = { { name = "Kitty", class = "DRUID", role = "DAMAGER", spec = 103 } },
    [4] = { { name = "Pally", class = "PALADIN", role = "DAMAGER", spec = nil } },
    [5] = { { name = "Bear", class = "DRUID", role = "TANK", spec = 104 }, { name = "Arc", class = "MAGE", role = "DAMAGER", spec = 62 } },
    [6] = { { name = "Smash", class = "WARRIOR", role = "DAMAGER", spec = 71 } },
  }
  UIF:Show("applicants"); RunTimers()
  ok(TT.enabled and TT.hosting, "applicants tab enables tracker")
  local ctx, evals = Fit:ForLiveGroup()
  ok(ctx.dungeonKey == "AltarOfFangs", "fit uses listing dungeon")
  ok(ctx.open.DAMAGER == 2 and ctx.open.TANK == 0 and ctx.open.HEALER == 0, "open roles: 2 dps")
  local by = {}
  for _, ev in ipairs(evals) do by[ev.applicantID] = ev
    print(string.format("  #%d %-10s %3d %-9s %s", ev.applicantID, ev.members[1].name, ev.score, ev.rating.key, ev.headline))
  end
  ok(#evals == 6, "six applications")
  ok(evals[1].applicantID == 3 and by[3].rating.key == "great", "feral druid ranked first and great")
  ok(by[3].headline:find("Poison"), "feral headline is the poison gap: " .. by[3].headline)
  local hasPoisonFix = false
  for _, f in ipairs(by[3].dungeonFixes) do if f.cap == "dispel_poison" then hasPoisonFix = true end end
  ok(hasPoisonFix, "feral dungeon fix lists poison dispel")
  local hasBuff = false
  for _, c in ipairs(by[3].complements) do if c.text:find("Mark of the Wild") then hasBuff = true end end
  ok(hasBuff, "feral complement: adds Mark of the Wild (informational)")
  for _, c in ipairs(by[3].complements) do if c.text:find("Mark of the Wild") then ok(c.weight == 1, "buff complement is low weight") end end
  ok(by[1].roleConflict and by[1].rating.key == "poor", "healer applicant with healer present is poor")
  ok(by[5].roleConflict and by[5].rating.key == "poor", "duo with a tank is poor (tank taken)")
  ok(evals[#evals].roleConflict and evals[#evals - 1].roleConflict, "conflicts sorted last")
  ok(by[2].score < by[3].score and by[2].rating.key ~= "great", "rogue rated below druid")
  ok(by[4].pending, "class-only applicant marked pending")
  -- Applicant synergy: Havoc applicant into a caster-heavy party
  local syn = false
  for _, c in ipairs(by[3].complements) do if c.synergy and c.text:find("Battle Shout") then syn = true end end
  ok(syn, "feral applicant: benefits from your Battle Shout")
  local samec = false
  for _, o in ipairs(by[6].overlaps) do if o:find("Same class") and o:find("Battle Shout") then samec = true end end
  ok(samec, "warrior overlap with existing warrior noted")
  ok(#by[3].brings > 3, "brings list populated")
  -- Pick rating (1.2.0): look-ahead no longer props up the score. The rogue adds next to
  -- nothing for this slot, so it is Poor; the headline and "Group after:" carry the look-ahead.
  ok(by[2].rating.key == "poor" and by[2].headline:find("last slot"), "rogue: poor pick, headline says the last slot can cover poison")
  ok(by[2].groupAfter.status == "missing" and by[2].groupAfter.text:find("Poison", 1, true) and by[2].groupAfter.slots == 1,
    "rogue: group after = missing Poison dispel, 1 slot open (" .. by[2].groupAfter.text .. ")")
  ok(by[2].potential == nil and by[2].fitScore == by[2].score, "no look-ahead part in the score")
  ok(by[2].bestPartners and #by[2].bestPartners == 1, "best partner suggested for remaining slot")
  -- Only one DPS slot left: no lookahead, rogue no longer good.
  ROSTER.party3 = { guid = "D", name = "Dee", class = "DEMONHUNTER", role = "DAMAGER" }
  INSPECT_CACHE.D = 577
  for _, fr in ipairs(ALLFRAMES) do if fr._events.INSPECT_READY then fr._scripts.OnEvent(fr, "GROUP_ROSTER_UPDATE") end end
  RunTimers()
  local _, ev1 = Fit:ForLiveGroup()
  local b1 = {}
  for _, ev in ipairs(ev1) do b1[ev.applicantID] = ev end
  -- 12.1 data: Feral's Soothe/Stampeding Roar/Maim are optional talents, so a Retribution
  -- Paladin (reliable Cleanse Toxins) is now the best last pick; Feral still rates well.
  ok((b1[3].rating.key == "great" or b1[3].rating.key == "good") and b1[2].rating.key == "poor" and b1[2].potential == nil,
    "last slot: druid good or better, rogue poor (got " .. b1[3].rating.key .. " / " .. b1[2].rating.key .. " " .. b1[2].score .. ")")
  ROSTER.party3 = nil
  for _, fr in ipairs(ALLFRAMES) do if fr._events.INSPECT_READY then fr._scripts.OnEvent(fr, "GROUP_ROSTER_UPDATE") end end
  RunTimers()
  -- Cache: same inputs reuse, settings change recomputes
  local c1 = select(1, Fit:ForLiveGroup()); local c2 = select(1, Fit:ForLiveGroup())
  ok(c1 == c2, "fit cache reused")
  nsF:Fire("SETTINGS_CHANGED")
  ok(select(1, Fit:ForLiveGroup()) ~= c1, "settings change invalidates fit cache")
  -- Key level
  nsF.state.keyLevelOverride = 15
  local ctx2, evals2 = Fit:ForLiveGroup()
  local note = false
  for _, n in ipairs(evals2[1].notes) do if n:find("%+15") then note = true end end
  ok(ctx2.keyLevel == 15 and note, "high key note")
  nsF.state.keyLevelOverride = nil
  -- No dungeon: still works
  LISTING = "Unknown Place"; nsF.db.settings.liveAutoDungeon = false
  local ctx3, evals3 = Fit:ForLiveGroup()
  ok(ctx3.dungeonKey == nil and #evals3 == 6 and evals3[1].dungeonName == nil, "fit without a dungeon")
  nsF.db.settings.liveAutoDungeon = true; LISTING = "Altar of Fangs (Mythic Keystone)"
  -- UI paths
  UIF.ap.selected = 5; UIF:Refresh(); RunTimers()
  UIF:StepKeyLevel(1); RunTimers()
  UIF:Show("live"); RunTimers()
  UIF:Show("applicants"); RunTimers()
  -- Group Finder panel lifecycle
  PVEFrame:Show(); RunTimers()
  ok(UIF.fp and UIF.fp:IsShown(), "finder panel shown when Group Finder opens while hosting")
  ok(TT:IsHeldBy("finder"), "finder holds tracker")
  UIF:Hide(); RunTimers()
  ok(TT.enabled, "tracker stays on for finder panel after window closes")
  nsF.db.settings.applicantPanel = false; UIF:UpdateFinderPanel(); RunTimers()
  ok(not UIF.fp:IsShown() and not TT:IsHeldBy("finder") and TT:IsHeldBy("tooltip"), "setting off hides panel; tracker kept only for Group Finder tooltips")
  nsF.db.settings.applicantPanel = true; UIF:UpdateFinderPanel(); RunTimers()
  ok(UIF.fp:IsShown(), "setting on shows it again")
  -- Movable panel: docked by default, drag undocks and saves, Dock re-attaches
  ok(UIF.fp._point and UIF.fp._point[2] == PVEFrame and not UIF.fp.dock:IsShown(), "panel docked to Group Finder by default")
  -- Default dock: under the Group Finder (clear of add-ons attached to its right edge), two columns
  ok(UIF.fp._point[1] == "TOPLEFT" and UIF.fp._point[3] == "BOTTOMLEFT" and UIF.fp._point[5] < -20, "docked below the Group Finder's tabs")
  PVEFrame._w = 563; UIF:RefreshFinderPanel()
  ok(UIF.fp:GetWidth() == 563, "as wide as the Group Finder")
  local r1, r2, r3 = UIF.fp.rows[1]._point, UIF.fp.rows[2]._point, UIF.fp.rows[3]._point
  ok(r1[2] == r3[2] and r2[2] > r1[2] and r2[3] == r1[3] and r3[3] < r1[3], "applicants laid out in two columns")
  ok(UIF.fp.side:IsShown() and UIF.fp.side.text:GetText() == "Dock right", "switch-side button shown while docked")
  UIF.fp.side:Click(); RunTimers(); UIF:RefreshFinderPanel()
  ok(nsF.db.settings.finderPanel.side == "right" and UIF.fp._point[3] == "TOPRIGHT" and UIF.fp:GetWidth() == 280, "right side: single column")
  UIF.fp.side:Click(); RunTimers(); UIF:RefreshFinderPanel()
  ok(nsF.db.settings.finderPanel.side == "below" and UIF.fp._point[3] == "BOTTOMLEFT", "side button flips back below")
  UIF.fp._left, UIF.fp._top = 300, 500
  UIF.fp._scripts.OnDragStart(UIF.fp); UIF.fp._scripts.OnDragStop(UIF.fp); RunTimers()
  local fpPos = nsF.db.settings.finderPanel
  ok(fpPos.docked == false and fpPos.x == 300 and fpPos.y == 500, "drag saves position and undocks")
  ok(UIF.fp._point[2] == UIParent and UIF.fp._point[4] == 300 and UIF.fp.dock:IsShown(), "panel placed at saved spot with Dock button")
  UIF:RefreshFinderPanel()
  ok(UIF.fp._point[2] == UIParent, "refresh keeps the moved position")
  UIF.fp.dock:Click(); RunTimers()
  ok(fpPos.docked and UIF.fp._point[2] == PVEFrame and not UIF.fp.dock:IsShown(), "Dock button re-attaches")
  fpPos.docked = false; UIF:PositionFinderPanel()
  UIF.fp.dock:Click()
  ok(fpPos.docked and UIF.fp._point[2] == PVEFrame, "Dock re-attaches again")
  PVEFrame:Hide(); RunTimers()
  ok(not UIF.fp:IsShown() and not TT.enabled, "closing Group Finder hides panel and releases tracker")
  -- Not hosting
  LISTING = nil
  UIF:Show("applicants"); RunTimers()
  ok(not TT.hosting, "not hosting state")
  UIF:Hide()
end

-- 18. Ability links, icons, tooltips, dungeon icons
do
  MythicCompDB = nil
  local nsL = boot()
  local Links, UD2, UIL = nsL.Links, nsL.UD, nsL.UI
  local mf = Links:Ability("Mind Freeze", "interrupt")
  ok(mf:find("|Haddon:Ensemble:a:47528:interrupt:Mind Freeze|h", 1, true) and mf:find("|T" .. (1000000 + 47528), 1, true),
    "class ability link with icon + type")
  ok(mf:find(Links.TYPES.interrupt.hex, 1, true), "colored by type")
  local sl = Links:Ability("Spell Lock (Felhunter)", "interrupt")
  ok(sl:find(":19647:", 1, true) and sl:find("Spell Lock (Felhunter)", 1, true), "suffix stripped for ID, kept for display")
  UD2.SPELL_IDS["Kick"] = 999999
  ok(Links:Ability("Kick", "interrupt"):find(":1766:", 1, true), "stale ID falls back to player's spell by name")
  UD2.SPELL_IDS["Kick"] = 1766
  local hx = Links:Decorate("Hex (Phantom Hex Priest)", "curse")
  local n = 0 for _ in hx:gmatch("|Haddon") do n = n + 1 end
  ok(n == 1 and hx:find(":270492:curse:Hex|h", 1, true) and hx:find("(Phantom Hex Priest)", 1, true), "Hex linked once, not inside NPC name")
  local hv = Links:Decorate("Hex Volley (Risen Hexer)", "interrupt")
  ok(hv:find(":269972:interrupt:Hex Volley|h", 1, true), "longest name wins")
  local ev = Links:Decorate("Envenom DoTs (High Evolutionist)", "poison")
  ok(ev:find(":1307571:poison:Envenom|h", 1, true) and ev:find("|T" .. (1000000 + 1307571), 1, true), "Altar of Fangs ability now has its real icon")
  local multi = Links:Decorate("Ancestral Fury (Shadow-Borne Champion), Bestial Berserk (Queen Patlaa)", "enrage")
  ok(multi:find("Ancestral Fury|h", 1, true) and multi:find("Bestial Berserk|h", 1, true), "abilities after a paren group still linked")
  ok(Links:Buff("CHAOS_BRAND"):find(":1490:buff:Chaos Brand|h", 1, true), "buff link")
  -- Analysis output carries links
  local r = nsL.Analysis:Analyze({ { specID = 73 }, { specID = 256 }, { specID = 63 } }, "AltarOfFangs", nsL.db.settings)
  ok(r.summary:find(":1307571:poison:Envenom|h", 1, true), "summary links the ability with the requirement's type")
  local lbl = nsL.Analysis.Labels(r.caps.interrupt, "interrupt")
  ok(lbl[1]:find("|Haddon:Ensemble:a:", 1, true), "provider labels are links")
  local found = false
  for _, it in ipairs(r.dungeon.items) do
    for _, l in ipairs(nsL.Analysis.Labels(it.providers, it.req.need)) do if l:find("|Haddon:Ensemble:a:", 1, true) then found = true end end
  end
  ok(found, "dungeon providers name their ability as a link")
  -- Tooltip handler
  local f = CreateFrame("Frame")
  Links:Enable(f)
  ok(f._scripts.OnHyperlinkEnter ~= nil, "hyperlink scripts installed")
  local lines, spellShown = {}, nil
  GameTooltip.SetSpellByID = function(_, id) spellShown = id end
  GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
  f._scripts.OnHyperlinkEnter(f, "addon:Ensemble:e:270492:curse:Hex")
  ok(spellShown == 270492 and lines[1]:find("Curse debuff"), "tooltip shows the spell and its type")
  spellShown, lines = nil, {}
  GameTooltip.SetText = function(_, t) lines[#lines + 1] = "T:" .. t end
  f._scripts.OnHyperlinkEnter(f, "addon:Ensemble:e:0:poison:Envenom")
  ok(spellShown == nil and lines[1] == "T:Envenom" and lines[2]:find("Poison"), "name-only tooltip when ID unknown")
  -- Dungeon icons
  ok(UIL:DungeonIcon("AltarOfFangs") == 7001 and UIL:DungeonIcon("KingsRest") == 7002, "in-game dungeon icons by map ID")
  local savedMap = DUNGEON_MAPS[587]; DUNGEON_MAPS[587] = nil
  ok(tostring(UIL:DungeonIcon("MurderRow")):find("Hourglass"), "keystone fallback when the map data isn't loaded")
  DUNGEON_MAPS[587] = savedMap
  ok(UIL:DungeonLabel("AltarOfFangs"):find("|T7001:16:16", 1, true), "dungeon label shows icon")
  UIL:Show("builder"); RunTimers(); UIL:Show("applicants"); RunTimers(); UIL:Hide()
end

-- 19. Second data pass
do
  MythicCompDB = nil
  local nsD = boot()
  local DDx, Lx = nsD.Dungeons, nsD.Links
  ok(#DDx:Validate() == 0, "all requirements valid after second pass")
  local function has(key, id) for _, r in ipairs(DDx.list[key].requirements) do if r.id == id then return r end end end
  ok(has("RubyLifePools", "RLP_ICE_BULWARK") == nil and has("RubyLifePools", "RLP_TEMPEST_STORMSHIELD") == nil, "contradicted purge guesses removed")
  for _, id in ipairs({ "AOF_PIERCING_HISS", "AOF_MASS_ENVENOM", "AOF_EVOLVE" }) do ok(has("AltarOfFangs", id), id) end
  for _, id in ipairs({ "DN_HEALING_BREEZE", "DN_FRIGID_ROAR", "DN_ARC_LIGHTNING", "DN_FREEDOM" }) do ok(has("DenOfNalorakk", id), id) end
  for _, id in ipairs({ "KR_HUNTING_LEAP", "KR_GROUP_DAMAGE", "TOS_KNOT_OF_SNAKES", "RLP_TANK", "VA_MAD_SHRIEK", "BV_SCREECH", "MR_FEL_CRAZED" }) do
    local found = false
    for _, k in ipairs(DDx.order) do if has(k, id) then found = true end end
    ok(found, id)
  end
  local den = Lx:Decorate("Lightning Bolt (Stormbound Mystic)", "interrupt", "DenOfNalorakk")
  local tos = Lx:Decorate("Lightning Bolt (Storm Adept)", "interrupt", "TempleOfSethraliss")
  ok(den:find(":1246687:", 1, true) and tos:find(":1291262:", 1, true), "per-dungeon spell IDs for shared names")
  ok(Lx:Decorate("Hunting Leap (Thorny Saptor)", "cc", "TheBlindingVale"):find(":1303039:", 1, true)
     and Lx:Decorate("Hunting Leap (Honored Raptor)", "cc", "KingsRest"):find(":270500:", 1, true), "Hunting Leap differs per dungeon")
  ok(Lx:Decorate("Back to Work! (Keen Taskmaster)", "enrage", "MurderRow"):find(":1216970:enrage:Back to Work!|h", 1, true), "name with ! links")
end

-- 20. Ability tracker pass
do
  MythicCompDB = nil
  local nsT = boot()
  local DDt, A2 = nsT.Dungeons, nsT.Analysis
  ok(#DDt:Validate() == 0, "valid after tracker pass")
  local function req(key, id) for _, r in ipairs(DDt.list[key].requirements) do if r.id == id then return r end end end
  local ta = req("AltarOfFangs", "AOF_TOXIC_ATROPHY")
  ok(ta.confidence == "verified" and ta.minProviders == 2, "Toxic Atrophy confirmed interruptible")
  ok(req("AltarOfFangs", "AOF_FREEDOM") and req("TheBlindingVale", "BV_FREEDOM") and req("VoidscarArena", "VA_FREEDOM"), "freedom checks added")
  ok(req("TheBlindingVale", "BV_POTAD_TOSS") and req("VoidscarArena", "VA_SHELL_GUARD"), "stop checks added")
  ok(req("DenOfNalorakk", "DN_GLACIAL_TOMB") == nil and req("DenOfNalorakk", "DN_FREEDOM").source:find("Rimeshatter"), "Den freedom merged")
  ok(DDt.SPELL_IDS["A Knot of Snakes"] == 1290031 and DDt.SPELL_IDS["Knot of Snakes"] == nil, "Knot of Snakes renamed with real ID")
  -- No ability is left without an ID
  local zero = {}
  for name, id in pairs(DDt.SPELL_IDS) do if id == 0 then zero[#zero + 1] = name end end
  ok(#zero == 0, "every dungeon ability has a spell ID: " .. table.concat(zero, ","))
  -- A group with Blessing of Freedom covers the new freedom checks; one without shows them
  local withPal = A2:Analyze({ { specID = 66 }, { specID = 256 }, { specID = 63 } }, "VoidscarArena", nsT.db.settings)
  local without = A2:Analyze({ { specID = 73 }, { specID = 256 }, { specID = 63 } }, "VoidscarArena", nsT.db.settings)
  local function status(r, id) for _, it in ipairs(r.dungeon.items) do if it.req.id == id then return it.status end end end
  ok(status(withPal, "VA_FREEDOM") == "covered" and status(without, "VA_FREEDOM") == "missing", "freedom check works")
end

-- 21. Appearance: theme, scale, lock
do
  MythicCompDB = nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  local nsA = boot()
  local UIA = nsA.UI
  ok(nsA.db.settings.theme.hex == "7EB7FF", "theme defaults")
  local r, g, b = UIA.HexToRGB("#A78BFA")
  ok(r and UIA.RGBToHex(r, g, b) == "A78BFA" and UIA.HexToRGB("zzz") == nil, "hex conversion")
  UIA:Show("settings"); RunTimers()
  ok(UIA.SetThemeHex("a78bfa"), "set theme hex")
  ok(nsA.db.settings.theme.hex == "A78BFA", "hex saved normalized")
  ok(UIA.titleText:GetText() == "Ensemble", "title stays the plain white name when the accent changes")
  ok(UIA.tabButtons.settings.line._color[1] > 0.6 and UIA.tabButtons.settings.line._color[3] > 0.95, "registered accent recolored")
  local sc = UIA.subtitleText._color
  ok(sc and math.abs(sc[1] - 0xA7 / 255) < 0.01 and math.abs(sc[2] - 0x8B / 255) < 0.01 and math.abs(sc[3] - 0xFA / 255) < 0.01,
    "window subtitle follows the chosen accent color")
  ok(not UIA.SetThemeHex("12345"), "invalid hex rejected")
  RAID_CLASS_COLORS = setmetatable({ WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }, { __index = function() return { r = 1, g = 1, b = 1 } end })
  nsA.db.settings.theme.classColor = true; UIA:ApplyTheme(); RunTimers()
  ok(UIA.tabButtons.settings.line._color[1] > 0.7 and UIA.tabButtons.settings.line._color[3] < 0.5, "class color applied")
  ok(UIA.subtitleText._color[1] > 0.7 and UIA.subtitleText._color[3] < 0.5, "window subtitle follows the class color")
  UIA.SetThemeHex(UIA.PRESETS[3].hex)
  ok(nsA.db.settings.theme.classColor == false and nsA.db.settings.theme.hex == "7CE36A", "preset clears class color")
  -- Resizing adds room; text size is separate
  ok(nsA.db.settings.window.width == 952 and nsA.db.settings.window.height == 630 and nsA.db.settings.textSize == 100, "size/text defaults")
  UIA:SetWindowSize(1400, 900); RunTimers()
  ok(UIA.frame._w == 1400 and UIA.frame._h == 900 and nsA.db.settings.window.width == 1400, "window resized")
  ok(UIA.frame:GetScale() == 1, "resizing never scales")
  UIA:SetWindowSize(300, 200)
  ok(nsA.db.settings.window.width == UIA.MIN_W and nsA.db.settings.window.height == UIA.MIN_H, "minimum size enforced")
  UIA:SetWindowSize(1400, 900)
  ok(UIA.pl.leftPanel._w > 400, "extra width widens the Plan tab's columns: " .. tostring(UIA.pl.leftPanel._w))
  local before = UIA.cp.sumTitle._fontSize
  UIA:SetTextSize(120); RunTimers()
  ok(UIA.logo and UIA.LOGO == "Interface\\AddOns\\Ensemble\\Media\\LogoMark", "window header shows the addon logo")
  ok(UIA.subtitleText and UIA.subtitleText:GetText() == "A Mythic+ Companion" and UIA.subtitleText._fontSize == 10, "subtitle under the name at a fixed size")
  ok(UIA.headerFit and UIA.headerFit.subtitleShown and UIA.subtitleText:IsShown(), "subtitle fits beside the tabs at the narrowest window")
  ok(nsA.db.settings.textSize == 120 and UIA.cp.sumTitle._fontSize == 16 and before == 13 and UIA.titleText._fontSize == 15, "text size applies to existing text (tab row stays fixed)")
  ok(UIA.frame._w == 1400, "text size leaves the window size alone")
  UIA:SetTextSize(200); ok(nsA.db.settings.textSize == 125, "text size clamped high")
  UIA:SetTextSize(10); ok(nsA.db.settings.textSize == 80, "text size clamped low")
  UIA:SetTextSize(110); ok(nsA.db.settings.textSize == 110, "text size set")
  UIA.grip._scripts.OnMouseDown(UIA.grip); ok(UIA.frame._sizing, "grip resizes")
  UIA.grip._scripts.OnMouseUp(UIA.grip)
  UIA.lockBtn:Click(); RunTimers()
  ok(nsA.db.settings.window.locked and UIA.lockBtn.text:GetText() == "Locked" and not UIA.grip:IsShown(), "locked: grip hidden")
  UIA.lockBtn:Click(); RunTimers()
  ok(not nsA.db.settings.window.locked and UIA.grip:IsShown(), "unlocked: grip shown")
  UIA:ResetGeometry(); ok(nsA.db.settings.window.width == 952 and nsA.db.settings.window.point == "CENTER", "reset geometry")
  UIA:SetTextSize(100)
  for _, tab in ipairs({ "builder", "live", "applicants", "plan", "settings" }) do UIA:Show(tab); RunTimers() end
  UIA:Hide()
end

-- 22. Dropdown field
do
  local UIx = boot().UI
  UIx:Show("builder"); RunTimers()
  local t = UIx.cp.dungeonBtn.text:GetText()
  ok(UIx.cp.dungeonBtn.chev and #UIx.cp.dungeonBtn.chev == 2 and not t:find("  v", 1, true), "dropdown has a chevron, no 'v'")
  UIx:Show("applicants"); RunTimers()
  ok(UIx.ap.dungeonBtn.chev ~= nil and not UIx.ap.dungeonBtn.text:GetText():find("  v", 1, true), "applicants dropdown too")
  UIx:Hide()
end

-- 23. /ens verify
do
  MythicCompDB = nil
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
  }
  INSPECT_CACHE = { H = 256 }
  LISTING = "Altar of Fangs (Mythic Keystone)"
  APPLICANTS = { [1] = { { name = "Kitty", class = "DRUID", role = "DAMAGER", spec = 103 } } }
  local nsV = boot()
  local ok1, report = pcall(function() return nsV.Verify:Run() end)
  ok(ok1 and type(report) == "string", "verify runs without errors: " .. tostring(report):sub(1, 200))
  ok(report:find("Summary:", 1, true) and report:find("== Specs ==", 1, true) and report:find("== Group Finder ==", 1, true), "report has sections")
  ok(report:find("applicants with a spec ID: 1 of 1", 1, true), "applicant spec detection reported")
  ok(report:find("Altar of Fangs", 1, true), "dungeon list reported")
  ok(report:find("missing: ColorPickerFrame.SetupColorPickerAndShow", 1, true), "missing functions reported")
  -- All data confirmed (October 13: Shadow Bolt's slow and Living Bomb's Magic type in game).
  ok(not report:find("[INFO] utility:", 1, true) and not report:find("[INFO] dungeon:", 1, true)
    and not report:find("TOS_AVATAR", 1, true), "class and dungeon data fully confirmed")
  ok(report:find("[OK] nothing left unconfirmed", 1, true), "verify says nothing is left unconfirmed")
  ok(not report:find("[INFO] boss card:", 1, true) and report:find("== Boss cards ==", 1, true)
    and report:find("28 boss cards", 1, true), "boss cards checked, all confirmed")
  nsV.BossData.list.AltarOfFangs[1].lines[1].nv = true
  ok(nsV.Verify:Run():find("[INFO] boss card: Rav'i (ALL)", 1, true), "an unconfirmed boss line is listed")
  nsV.BossData.list.AltarOfFangs[1].lines[1].nv = nil; nsV.db.lastVerify = report
  do
    local section = report:match("== Still marked unconfirmed in the data ==(.*)$") or ""
    print(section)
    local _, nThunder = section:gsub("Thunderstorm", "")
    ok(nThunder == 0 and not section:find("utility:", 1, true), "no class ability left unconfirmed")
    ok(not section:find("Scatter Shot", 1, true) and not section:find("Psychic Horror", 1, true) and true, "confirmed or removed abilities no longer listed")
  end
  ok(nsV.db.lastVerify == report, "report saved for fallback")
  SlashCmdList.ENSEMBLE("verify")
  ok(nsV.Verify.lastReport ~= nil, "slash command runs verify")
  print(report:sub(1, 1500))
end

-- 24. Still needed (replaces Suggestions)
do
  MythicCompDB = nil
  local nsN = boot()
  local A, UDn = nsN.Analysis, nsN.UD
  -- Warrior tank + Holy Priest + Fury Warrior + Arms Warrior: no lust, thin kicks, no poison dispel etc.
  local mem = { { specID = 73 }, { specID = 257 }, { specID = 72 }, { specID = 71 } }
  local r = A:Analyze(mem, "TempleOfSethraliss", nsN.db.settings)
  local needs = A:StillNeeded(r)
  ok(#needs > 0, "still-needed list not empty: " .. #needs)
  local byTitle, lust, poison = {}, nil, nil
  for _, e in ipairs(needs) do
    ok(not byTitle[e.title], "one entry per capability set: " .. e.title); byTitle[e.title] = true
    for _, k in ipairs(e.keys) do
      if k == "bloodlust" then lust = e end
      if k == "dispel_poison" then poison = e end
    end
  end
  ok(lust and lust.status == "missing", "missing bloodlust is a need")
  ok(poison and #poison.sources >= 1 and poison.sources[1].dungeon == "TempleOfSethraliss", "dungeon poison dispel need has sources")
  for i = 2, #needs do
    local rank = { missing = 1, thin = 2 }
    ok((rank[needs[i - 1].status] or 3) <= (rank[needs[i].status] or 3), "sorted missing before thin")
  end
  -- Coverers: open slot is 1 DPS, so DPS-capable lust classes come first
  local open = nsN.ApplicantFit:OpenRoles(mem)
  ok(open.DAMAGER == 1 and open.HEALER == 0 and open.TANK == 0, "one DPS slot open")
  local cov = A:Coverers({ "bloodlust" }, open, nsN.db.settings)
  local classes, firstOut = {}, nil
  for i, c in ipairs(cov) do
    classes[c.classFile] = c
    if not c.inRole and not firstOut then firstOut = i end
    if firstOut then ok(not c.inRole, "in-role classes sorted first") end
  end
  ok(classes.SHAMAN and classes.MAGE and classes.HUNTER and classes.EVOKER, "lust classes listed")
  ok(not classes.WARRIOR and not classes.ROGUE, "classes without lust not listed")
  ok(classes.MAGE.inRole and classes.MAGE.abilities[1].name == "Time Warp" and classes.MAGE.abilities[1].allSpecs, "Mage: Time Warp, all specs")
  -- Spec-limited ability: poison dispel by Druid (Restoration only via Nature's Cure, or Remove Corruption for all)
  local pc = A:Coverers({ "dispel_poison" }, open, nsN.db.settings)
  local any = false
  for _, c in ipairs(pc) do for _, a in ipairs(c.abilities) do if not a.allSpecs then any = true end end end
  ok(any, "spec-limited abilities flagged")
  -- Full group: everyone is a swap option (inRole true)
  local full = A:Coverers({ "bloodlust" }, { TANK = 0, HEALER = 0, DAMAGER = 0 }, nsN.db.settings)
  local allIn = true
  for _, c in ipairs(full) do if not c.inRole then allIn = false end end
  ok(allIn, "full group lists every class as a swap option")
  -- Covered comp: nothing needed
  local r0 = A:Analyze({}, nil, nsN.db.settings)
  ok(#A:StillNeeded(r0) >= 0, "empty comp does not error")

  -- UI rendering
  local UIn = nsN.UI
  for s = 1, 5 do nsN.db.currentComp[s] = 0 end
  nsN.db.currentComp[1], nsN.db.currentComp[2], nsN.db.currentComp[3], nsN.db.currentComp[4] = 73, 257, 72, 71
  nsN:SetManualDungeon("TempleOfSethraliss")
  UIn:Show("builder"); RunTimers()
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  local side, an = UIn.cp.sideList, UIn.cp.analysis
  local sideText = dump(side)
  ok(not sideText:find("STILL NEEDED", 1, true),
    "Still needed section removed from the side column")
  local analysisText = dump(an)
  local function after(header, needle)
    local h = analysisText:find(header, 1, true); if not h then return false end
    local nextH = analysisText:find("\n|cff%x%x%x%x%x%x[A-Z][A-Z /&][A-Z /&]", h + #header) or #analysisText
    local n = analysisText:find(needle, h, true)
    return n ~= nil and n < nextH
  end
  ok(after("THROUGHPUT", "Bloodlust / Heroism") and after("THROUGHPUT", "Time Warp") and after("THROUGHPUT", "Can cover it"),
    "missing Bloodlust: row open with who can cover it")
  ok(after("SURVIVAL", "Battle resurrection") and after("SURVIVAL", "Rebirth"), "missing battle rez: coverers")
  ok(after("DISPELS", "Needed for:") and after("DISPELS", "Cytotoxin") and after("DISPELS", "Cleanse Toxins"),
    "poison dispel: dungeon reason and coverers in one row")
  ok(after("DISPELS", "Imbued Conduction") and after("DISPELS", "Covered by: "), "magic dispel row: who covers it and what needs it")
  ok(not analysisText:find("COMPOSITION ANALYSIS", 1, true) and not analysisText:find("TOP GAPS", 1, true), "one merged panel")
  -- Every THIN or MISSING row lists who can cover it
  local ready = UIn.cp.lastReady
  for _, grp in ipairs(ready.groups) do
    for _, row in ipairs(grp.rows) do
      if row.status == "thin" or row.status == "missing" then
        ok(after(grp.label:upper(), row.label) and analysisText:find("Can cover it", analysisText:find(row.label, 1, true), true) ~= nil,
          "coverers listed for " .. row.status .. " " .. row.label)
      end
    end
  end
  -- Covered rows fold to one line; click to open
  local okRow = nil
  for _, grp in ipairs(ready.groups) do for _, row in ipairs(grp.rows) do if row.status == "ok" and not okRow then okRow = row end end end
  ok(okRow and not UIn:IsOpen("row:" .. okRow.cap, false), "covered rows folded by default")
  local hdrBtn
  for i = 1, an.bused do if (an.bpool[i].tip and an.bpool[i].tip:find("Click to show details", 1, true) == 1) then hdrBtn = an.bpool[i]; break end end
  local usedBefore = an.used
  hdrBtn:Click(); RunTimers()
  ok(an.used > usedBefore, "clicking a folded row opens it")
  UIn.cp.expandBtn:Click(); RunTimers()
  local allOpen = true
  for _, grp in ipairs(ready.groups) do for _, row in ipairs(grp.rows) do
    if not UIn:IsOpen("row:" .. row.cap, UIn.readyMode == "all") then allOpen = false end
  end end
  ok(UIn.readyMode == "all" and allOpen and not dump(an):find("Click to show details", 1, true), "expand all opens every row")
  ok(dump(an):find("Covered by: ", 1, true), "expanded rows show details")
  -- Expand all also opens "All gaps" (this comp has more than 3 problems)
  ok(#ready.risks > 3, "comp has more than 3 problems")
  local at = dump(an)
  local ap = at:find("All gaps", 1, true)
  ok(ap and at:find("- |r", 1, true) and UIn:IsOpen("risks", UIn.readyMode == "all"), "expand all opens All gaps")
  local listed = 0
  for _, row in ipairs(ready.risks) do if at:find(UIn.RiskText(row, true), ap, true) then listed = listed + 1 end end
  ok(listed == #ready.risks, "every problem listed after Expand all")
  -- R3: the status tag isn't repeated in words ("THIN  thin ...", "MISSING  no ...").
  ok(not at:find("THIN|r  thin ", 1, true) and not at:find("MISSING|r  no ", 1, true), "All gaps: status said once")
  -- Folding it by hand after Expand all sticks; Expand all again reopens it
  UIn:SetOpen("risks", false); RunTimers()
  ok(not UIn:IsOpen("risks", true), "All gaps can be folded by hand")
  UIn.cp.expandBtn:Click(); RunTimers()
  ok(UIn:IsOpen("risks", UIn.readyMode == "all"), "Expand all reopens it")
  -- Collapse all folds everything, problems and every expanded list included
  UIn:SetOpen("need:interrupt", true); UIn:SetOpen("risks", true); UIn:SetOpen("cov:cov:dispel_poison", true)
  for _, k in ipairs({ "why:DAMAGER:SHAMAN", "sheet:interrupts", "savedq" }) do UIn:SetOpen(k, true) end
  RunTimers()
  UIn.cp.collapseBtn:Click(); RunTimers()
  local txt = dump(an)
  local openRows = 0
  for i = 1, an.bused do if an.bpool[i]:IsShown() and (an.bpool[i].tip and an.bpool[i].tip:find("Click to fold", 1, true) == 1) then openRows = openRows + 1 end end
  ok(openRows == 0, "collapse all folds every row, problems included")
  ok(not UIn:IsOpen("risks", UIn.readyMode == "all"), "collapse all folds All gaps")
  ok(not txt:find("show fewer", 1, true) and not txt:find("Needed for:", 1, true) and not txt:find("Can cover it", 1, true),
    "collapse all closes every expanded list")
  ok(not dump(UIn.cp.sideList):find("show fewer", 1, true),
    "collapse all also folds suggestions and saved comps")
  ok(txt:find("MISSING", 1, true), "folded problem rows still show their status")
  -- A single row can still be opened after Collapse all
  local hb
  for i = 1, an.bused do if an.bpool[i]:IsShown() and (an.bpool[i].tip and an.bpool[i].tip:find("Click to show details", 1, true) == 1) then hb = an.bpool[i]; break end end
  hb:Click(); RunTimers()
  openRows = 0
  for i = 1, an.bused do if an.bpool[i]:IsShown() and (an.bpool[i].tip and an.bpool[i].tip:find("Click to fold", 1, true) == 1) then openRows = openRows + 1 end end
  ok(openRows == 1, "one row opens on click after Collapse all")
  -- Collapse works from the default state too (no Expand all first)
  UIn.readyMode = nil; UIn.expand = {}; UIn:Refresh(); RunTimers()
  UIn.cp.collapseBtn:Click(); RunTimers()
  openRows = 0
  for i = 1, an.bused do if an.bpool[i]:IsShown() and (an.bpool[i].tip and an.bpool[i].tip:find("Click to fold", 1, true) == 1) then openRows = openRows + 1 end end
  ok(openRows == 0, "collapse all works straight from the default view")
  UIn.readyMode = nil; UIn.expand = {}; UIn:Refresh(); RunTimers()
  -- Interrupt need with its dungeon reasons, in Kicks & stops (a healer-only kick group)
  for s = 1, 5 do nsN.db.currentComp[s] = 0 end
  nsN.db.currentComp[1], nsN.db.currentComp[2] = 66, 257
  UIn:Refresh(); RunTimers()
  analysisText = dump(an)
  ok(after("KICKS & STOPS", "Lightning Bolt") and after("KICKS & STOPS", "Can cover it"), "interrupt need: reasons and coverers")
  nsN.db.currentComp[1], nsN.db.currentComp[2], nsN.db.currentComp[3], nsN.db.currentComp[4] = 73, 257, 72, 71
  UIn:Refresh(); RunTimers()
  analysisText = dump(an)
  -- "+N more" requirement lists expand and fold again
  UIn:SetOpen("row:interrupt", true); RunTimers()     -- Temple lists more than 3 kick casts
  local moreBtn
  for i = 1, an.bused do if an.bpool[i]:IsShown() and an.bpool[i].tip == "Show all" then moreBtn = an.bpool[i]; break end end
  ok(moreBtn ~= nil, "requirement list shows +N more")
  local u = an.used; moreBtn:Click(); RunTimers()
  ok(an.used > u, "+N more expands")
  local fewer
  for i = 1, an.bused do if an.bpool[i]:IsShown() and an.bpool[i].tip == "Show fewer" then fewer = an.bpool[i]; break end end
  ok(fewer ~= nil, "and can be folded again")
  fewer:Click(); RunTimers()
  ok(an.used == u, "folded back to the short list")
  -- Expand all / collapse all also reset rows the user touched
  UIn.cp.collapseBtn:Click(); RunTimers()
  ok(UIn.expand["row:interrupt"] == nil and UIn.readyMode == "none", "collapse all folds rows opened by hand")
  UIn.readyMode = nil; UIn:Refresh(); RunTimers()
  -- Summary view keeps every problem with its detail
  nsN.db.settings.compact = true; nsN:Fire("SETTINGS_CHANGED"); UIn:Refresh(); RunTimers()
  analysisText = dump(an)
  ok(analysisText:find("Cytotoxin", 1, true) and analysisText:find("Time Warp", 1, true) and analysisText:find("not shown in Summary view", 1, true),
    "summary view: problems with reasons and coverers, covered rows counted")
  nsN.db.settings.compact = false
  -- Generic check switched off: the dungeon's needs for it still show
  nsN.db.settings.checks.dispels = false; UIn:Refresh(); RunTimers()
  analysisText = dump(an)
  ok(after("DISPELS", "Cytotoxin") and not analysisText:find("Soothe (enrage)", 1, true), "dungeon needs stay when the generic check is off")
  nsN.db.settings.checks.dispels = true
  -- Summary strip
  UIn:Refresh(); RunTimers()
  ok(UIn.cp.sumTitle:GetText():find("missing", 1, true) and UIn.cp.sumRisks:GetText():find("Biggest risks", 1, true), "summary strip")
  local lustChip
  for _, b in ipairs(UIn.cp.chips) do if b:IsShown() and b.text:GetText():find("Lust", 1, true) then lustChip = b end end
  ok(lustChip ~= nil, "Lust chip")
  lustChip:Click(); RunTimers()
  ok(UIn:IsOpen("row:bloodlust", false), "chip jumps to the row (opened)")
  ok(UIn.cp.grid == nil and UIn.cp.gridBtn == nil and UIn.RenderGrid == nil, "grid view removed")
  -- Slot badges
  local sub2 = UIn.cp.slotRows[2].sub:GetText()
  ok(sub2:find("Magic", 1, true) and UIn.cp.slotRows[2].tip:find("Magic dispel", 1, true), "slot shows what the player brings")
  -- Empty comp
  for s = 1, 5 do nsN.db.currentComp[s] = 0 end
  nsN:Fire("COMP_CHANGED"); RunTimers()
  ok(dump(an):find("No players yet", 1, true), "empty-state text")
  UIn:Hide()
end

-- 25. Auto-open Applicants on listing
do
  MythicCompDB = nil
  LISTING = nil
  local nsL = boot()
  local UIl = nsL.UI
  local watcher
  for _, fr in ipairs(ALLFRAMES) do if fr._events.LFG_LIST_ACTIVE_ENTRY_UPDATE and fr._events.PLAYER_ENTERING_WORLD then watcher = fr end end
  ok(watcher ~= nil, "listing watcher registered")
  local function fire(ev) watcher._scripts.OnEvent(watcher, ev or "LFG_LIST_ACTIVE_ENTRY_UPDATE"); RunTimers() end
  fire("PLAYER_ENTERING_WORLD")
  ok(not (UIl.frame and UIl.frame:IsShown()), "baseline does not open")
  LISTING = "Temple of Sethraliss (Mythic Keystone)"
  fire()
  ok(UIl.frame and UIl.frame:IsShown() and UIl.currentTab == "applicants", "listing opens the Applicants tab")
  UIl:Hide()
  fire()
  ok(not UIl.frame:IsShown(), "listing update while already listed does not reopen")
  LISTING = nil; fire()
  LISTING = "Some Raid"; fire()
  ok(not UIl.frame:IsShown(), "non-Season listing ignored")
  LISTING = nil; fire()
  nsL.db.settings.autoOpenOnListing = false
  LISTING = "Kings' Rest (Mythic Keystone)"; fire()
  ok(not UIl.frame:IsShown(), "setting off: no auto-open")
  nsL.db.settings.autoOpenOnListing = true
  LISTING = nil; fire()
  local oldIC = InCombatLockdown; InCombatLockdown = function() return true end
  LISTING = "Kings' Rest (Mythic Keystone)"; fire()
  ok(not UIl.frame:IsShown(), "no auto-open in combat")
  InCombatLockdown = oldIC
  LISTING = nil
end

-- 26. Default dungeon: keystone (Builder), listing or zone (Live/Applicants)
do
  EnsembleDB = {}
  OWNED_KEY, OWNED_LEVEL, LISTING, INSTANCE, ACTIVE_CHALLENGE = 249, 14, nil, nil, nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  local nsD = boot()
  local UId = nsD.UI
  ok(nsD.db.selectedDungeon == "AUTO", "dungeon pick defaults to AUTO")
  local k, src = nsD:GetEffectiveDungeon(false)
  ok(k == "KingsRest" and src == "keystone", "Builder defaults to your keystone's dungeon")
  UId:Show("builder"); RunTimers()
  ok(UId.cp.dungeonBtn.text:GetText():find("Kings' Rest", 1, true) and UId.cp.dungeonNote:GetText():find("keystone (+14)", 1, true),
    "builder dropdown shows the keystone dungeon")
  -- Manual pick wins, Auto is offered back
  nsD:SetManualDungeon("AltarOfFangs")
  ok(nsD:GetEffectiveDungeon() == "AltarOfFangs" and nsD.db.selectedDungeon == "AltarOfFangs", "manual builder pick")
  RunTimers()
  ok(UId.cp.dungeonNote:GetText():find("Auto: Kings' Rest", 1, true) and UId.cp.noteBtn.tip:find("Auto would be Kings' Rest", 1, true),
    "note points at the auto choice (full sentence on hover)")
  -- New keystone (different dungeon) resets the builder to follow it
  nsD:CheckKeystoneChange()   -- records Kings' Rest as the current key
  OWNED_KEY = 588
  nsD:CheckKeystoneChange()
  ok(nsD.db.selectedDungeon == "AUTO" and nsD:GetEffectiveDungeon(false) == "AltarOfFangs", "new key: builder follows it again")
  nsD:SetManualDungeon("NONE")
  ok(nsD:GetEffectiveDungeon(false) == nil, "explicit generic-only still possible")
  nsD:CheckKeystoneChange()
  ok(nsD.db.selectedDungeon == "NONE", "same key does not override a pick")
  nsD:SetManualDungeon("AUTO")
  nsD:SetManualDungeon("NONE"); ok(nsD.db.selectedDungeon == "NONE", "dungeon none")
  nsD:SetManualDungeon("AUTO"); ok(nsD.db.selectedDungeon == "AUTO", "dungeon auto")
  -- No keystone: nothing
  OWNED_KEY = nil
  ok(nsD:GetEffectiveDungeon(false) == nil, "no key, no default")
  OWNED_KEY = 249

  -- Live: listing beats zone beats nothing; keystone NOT used in live
  UId:Show("live"); RunTimers()
  ok(nsD:GetEffectiveDungeon() == nil, "live: no listing, not in a dungeon -> none (keystone ignored)")
  INSTANCE = { "Temple of Sethraliss", "party" }
  for _, fr in ipairs(ALLFRAMES) do if fr._events.ZONE_CHANGED_NEW_AREA and fr._events.INSPECT_READY then fr._scripts.OnEvent(fr, "ZONE_CHANGED_NEW_AREA") end end
  RunTimers()
  k, src = nsD:GetEffectiveDungeon()
  ok(k == "TempleOfSethraliss" and src == "auto" and nsD.state.autoSource == "zone", "live: dungeon you're in")
  ok(UId.cp.dungeonNote:GetText() == "You're in it" and UId.cp.noteBtn.tip:find("the dungeon you're in", 1, true), "zone note")
  LISTING = "Murder Row (Mythic Keystone)"
  nsD.Tracker:RequestUpdate(); RunTimers()
  k = nsD:GetEffectiveDungeon()
  ok(k == "MurderRow" and nsD.state.autoSource == "listing", "live: listing beats zone")
  -- Active key beats instance name
  LISTING = nil; ACTIVE_CHALLENGE = 588
  nsD.Tracker:RequestUpdate(); RunTimers()
  ok(nsD:GetEffectiveDungeon() == "AltarOfFangs", "active keystone run detected")
  ACTIVE_CHALLENGE = nil
  nsD.Tracker:RequestUpdate(); RunTimers()
  -- Manual live pick is separate from builder and resets when the group's dungeon changes
  nsD:SetManualDungeon("KingsRest")
  ok(nsD.state.liveDungeon == "KingsRest" and nsD.db.selectedDungeon == "AUTO", "live pick does not touch builder pick")
  nsD.Tracker:RequestUpdate(); RunTimers()
  ok(nsD:GetEffectiveDungeon() == "KingsRest", "live pick sticks while the group's dungeon is unchanged")
  LISTING = "Murder Row (Mythic Keystone)"
  nsD.Tracker:RequestUpdate(); RunTimers()
  ok(nsD.state.liveDungeon == "AUTO" and nsD:GetEffectiveDungeon() == "MurderRow", "new listing: live pick resets to auto")
  -- Applicants tab uses the same live default
  UId:Show("applicants"); RunTimers()
  ok(UId.ap.dungeonBtn.text:GetText():find("Murder Row", 1, true) and UId.ap.dungeonBtn.text:GetText():find("auto", 1, true),
    "applicants dropdown shows listing dungeon, marked auto")
  ok(nsD:GetEffectiveDungeon(false) == "KingsRest", "builder context still on the keystone")
  -- Dropdown has an Auto entry describing the source
  local shown
  local oldShow = UId.ShowMenu
  UId.ShowMenu = function(_, _, items) shown = items end
  UId:OpenDungeonMenu(UId.ap.dungeonBtn)
  UId.ShowMenu = oldShow
  ok(shown and shown[1].text:find("Auto: Murder Row", 1, true) and shown[1].text:find("your listing", 1, true) and shown[1].selected,
    "menu Auto entry names the listing")
  -- Setting off: no auto anywhere
  nsD.db.settings.liveAutoDungeon = false
  nsD.Tracker:RequestUpdate(); RunTimers()
  ok(nsD:GetEffectiveDungeon() == nil and nsD:GetEffectiveDungeon(false) == nil, "auto-select setting off")
  nsD.db.settings.liveAutoDungeon = true
  -- Saving a comp stores the resolved dungeon, never "AUTO"
  UId:Show("builder"); RunTimers()
  UId.cp.nameBox:SetText("KeyComp"); UId:SaveCurrent()
  ok(nsD.db.savedComps[#nsD.db.savedComps].dungeon == "KingsRest", "saved comp stores resolved dungeon")
  UId:Hide()
  LISTING, INSTANCE, OWNED_KEY, OWNED_LEVEL = nil, nil, nil, nil
end

-- 27. Left column: cheat sheet, quick saved comps, post gaps
do
  EnsembleDB = nil
  OWNED_KEY, LISTING, INSTANCE = nil, nil, nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  local nsC = boot()
  local UIc = nsC.UI
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  for s = 1, 5 do nsC.db.currentComp[s] = 0 end
  UIc:Show("builder"); RunTimers()
  local side = UIc.cp.sideList
  UIc:Show("plan"); RunTimers()
  local plan = UIc.pl.list
  ok(dump(plan):find("Pick a dungeon to see", 1, true), "cheat sheet empty state")
  nsC:SetManualDungeon("TempleOfSethraliss"); RunTimers()
  local t = dump(plan)
  -- Issue #5: the panel title names the dungeon; no second header inside the list, and the
  -- left panel is "Your plan" (its "Your assignments" section stays).
  ok(UIc.pl.rightTitle:GetText() == "ASSIGNMENTS: TEMPLE OF SETHRALISS" and not t:find("ASSIGNMENTS: TEMPLE OF SETHRALISS", 1, true),
    "assignments: the dungeon is in the panel title, not repeated as a header")
  ok(UIc.pl.leftTitle:GetText() == "YOUR PLAN" and t:find("YOUR ASSIGNMENTS", 1, true) == nil, "left panel title is Your plan")
  ok(t:find("KICK", 1, true) and t:find("Lightning Bolt", 1, true) and t:find("Flame Shock", 1, true), "must-kicks listed")
  ok(t:find("DISPEL", 1, true) and t:find("Imbued Conduction", 1, true) and t:find("Magic:", 1, true), "must-dispels listed with type")
  ok(t:find("STOP", 1, true) and t:find("Arrow Barrage", 1, true), "must-stops listed")
  ok(t:find("Hhaddon:Ensemble", 1, true) == nil and t:find("|Haddon:Ensemble", 1, true), "abilities are links with tooltips")
  -- Issue #6: critical, high and medium casts are all on the sheet, most severe first; low stays off.
  local rows = UIc:CheatSheetRows("TempleOfSethraliss")
  local SEVN = { critical = 1, high = 2, medium = 3, low = 4 }
  local sheetIDs = {}
  for _, row in ipairs(rows) do
    for i, req in ipairs(row.reqs) do
      sheetIDs[req.id] = true
      ok(req.severity ~= "low", "no low-severity cast on the sheet: " .. req.id)
      ok(i == 1 or SEVN[row.reqs[i - 1].severity] <= SEVN[req.severity], "sheet sorted most severe first: " .. req.id)
    end
  end
  for _, q in ipairs(nsC.Dungeons.list.TempleOfSethraliss.requirements) do
    local cat = nsC.Dungeons:CategoryOf(q)
    if not q.invalid and q.severity ~= "low" and nsC.db.settings.dungeonCategories[cat] ~= false then
      ok(sheetIDs[q.id], "every critical/high/medium requirement is on the sheet: " .. q.id)
    end
  end
  nsC.db.settings.dungeonCategories.dispels = false; UIc:Refresh(); RunTimers()
  ok(not dump(plan):find("Imbued Conduction", 1, true), "cheat sheet respects hidden categories")
  nsC.db.settings.dungeonCategories.dispels = true
  -- Every dungeon produces a sheet without errors
  for _, key in ipairs(nsC.Dungeons.order) do
    local okR, res = pcall(UIc.CheatSheetRows, UIc, key)
    ok(okR and res and #res > 0, "cheat sheet for " .. key)
  end
  -- Quick saved comps
  UIc:Show("composition"); RunTimers()
  ok(dump(side):find("None yet", 1, true), "quick saved empty state")
  nsC.db.savedComps = {
    { name = "Old", slots = { 73, 256, 63, 71, 260 }, dungeon = "KingsRest", created = 1 },
    { name = "New", slots = { 581, 264, 62, 1473, 259 }, dungeon = "MurderRow", created = 9 },
  }
  UIc:Refresh(); RunTimers()
  t = dump(side)
  local iNew, iOld = t:find("New", 1, true), t:find("Old", 1, true)
  ok(iNew and iOld and iNew < iOld and t:find("Murder Row", 1, true), "quick saved: newest first, with dungeon")
  local loadBtn
  for i = 1, side.bused do if side.bpool[i].tip == "Click to load into the planner" then loadBtn = side.bpool[i]; break end end
  ok(loadBtn ~= nil, "quick saved rows clickable")
  loadBtn:Click(); RunTimers()
  ok(nsC.db.currentComp[1] == 581 and nsC.db.selectedDungeon == "MurderRow" and UIc.cp.nameBox:GetText() == "New", "click loads the comp")
  -- Post gaps
  nsC.db.currentComp = { 73, 257, 72, 71, 0 }
  nsC:SetManualDungeon("TempleOfSethraliss"); UIc:Show("plan"); RunTimers()
  local msg = UIc:GapsMessage(UIc.cp.lastAnalysis)
  ok(msg:find("^%[Ensemble%] Temple of Sethraliss") and msg:find("Missing: ", 1, true) and msg:find("Bloodlust", 1, true)
    and msg:find("Poison dispel (Cytotoxin)", 1, true) and not msg:find("|", 1, true) and #msg <= 255, "gap message: " .. msg)
  -- Issue #9: the Post buttons are real buttons under the list; hover previews the text.
  local postBtn = UIc.pl.postGapsBtn
  ok(postBtn and postBtn:IsEnabled() and postBtn.tooltip:find("Not in a group", 1, true) and postBtn.tooltip:find(msg, 1, true),
    "post gaps button present, its tooltip previews the post")
  ok(UIc.pl.postPlanBtn:IsEnabled() and UIc.pl.postPlanBtn.tooltip:find(" assignments", 1, true),
    "post assignments button previews the assignments post: " .. tostring(UIc.pl.postPlanBtn.tooltip))
  ok(UIc.pl.chatStyleBtn.text:GetText() == "Chat style: full", "chat style link beside the buttons")
  local planLines = dump(plan)
  ok(not planLines:find("> Post gaps", 1, true) and not planLines:find("> Post assignments", 1, true), "the Post lines are gone from the list")
  SENT = {}; PRINTED = ""
  postBtn:Click()
  ok(#SENT == 0 and PRINTED:find("shown only to you", 1, true), "solo: printed locally, not sent")
  ROSTER.party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" }
  postBtn:Click()
  ok(#SENT == 1 and SENT[1].channel == "PARTY" and SENT[1].msg == msg, "in a party: sent to party chat")
  local oldSend = SendChatMessage
  SendChatMessage = function() error("blocked") end; PRINTED = ""
  postBtn:Click()
  ok(PRINTED:find("couldn't send", 1, true), "blocked send falls back to printing")
  SendChatMessage = oldSend
  ROSTER.party1 = nil
  -- Long messages are trimmed
  local big = { findings = {}, filled = 1, dungeon = { key = "KingsRest", items = {} } }
  for i = 1, 40 do table.insert(big.findings, { cap = "dispel_magic", severity = "high", short = "no x" .. i, text = "x" }) end
  for _, l in ipairs(UIc:GapsLines(nsC.Analysis:Analyze({ { specID = 73 } }, "KingsRest", nsC.db.settings))) do
    ok(#l <= 255 and not l:find("%.%.%.$"), "gaps post line under 255, never cut (" .. #l .. ")")
  end
  -- Live tab: cheat sheet + post, no saved list
  UIc:Show("live"); RunTimers()
  t = dump(side)
  ok(not t:find("SAVED COMPS", 1, true), "no saved list for your party")
  UIc:Hide()
end

-- 28. Dungeons matched by ID, not name
do
  EnsembleDB = nil
  local nsI = boot()
  local DDi = nsI.Dungeons
  ok(DDi:KeyForChallengeMap(584) == "TheBlindingVale" and DDi:KeyForChallengeMap(250) == "TempleOfSethraliss", "challenge map IDs")
  local n = 0 for _ in pairs(DDi.CHALLENGE_MAP_IDS) do n = n + 1 end
  ok(n == #DDi.order, "every dungeon has a challenge map ID")
  ok(DDi:KeyForActivity(1949, { fullName = "Something Localized" }) == "TheBlindingVale", "known activity ID wins over name")
  ok(DDi:KeyForInstanceMap(1877) == "TempleOfSethraliss", "instance map ID learned from the map data")
  ok(DDi:KeyForActivity(7777, { fullName = "Tempel von Sethraliss (Mythischer Schlüsselstein)", mapID = 1877 }) == "TempleOfSethraliss",
    "non-English listing resolved through its instance map ID")
  -- Zone detection by instance ID with a non-English name
  local oldGII = GetInstanceInfo
  GetInstanceInfo = function() return "Königsruh", "party", 8, "Mythic", 5, 0, false, 1762 end
  ok(nsI:CurrentInstanceDungeon() == "KingsRest", "current dungeon by instance ID, not name")
  GetInstanceInfo = oldGII
  -- Keystone by map ID even if the name lookup fails
  local saved = DUNGEON_MAPS[588]; DUNGEON_MAPS[588] = { "Altar der Fänge", 7001, 2901 }
  OWNED_KEY, OWNED_LEVEL = 588, 12
  ok(nsI:OwnKeystoneDungeon() == "AltarOfFangs", "keystone matched by map ID")
  DUNGEON_MAPS[588] = saved; OWNED_KEY, OWNED_LEVEL = nil, nil
end

-- 29. Season-change warning
do
  EnsembleDB = nil
  local nsS = boot()
  PRINTED = ""
  nsS:CheckSeason()
  ok(nsS.state.seasonMismatch == nil and not PRINTED:find("dungeon list has changed", 1, true), "no warning when data matches")
  local saved = DUNGEON_MAPS[399]
  DUNGEON_MAPS[399] = nil
  DUNGEON_MAPS[700] = { "Shiny New Dungeon", 7099, 3000 }
  nsS:CheckSeason()
  ok(nsS.state.seasonMismatch and PRINTED:find("Shiny New Dungeon", 1, true) and PRINTED:find("Ruby Life Pools", 1, true),
    "warning names new and retired dungeons")
  PRINTED = ""
  nsS:CheckSeason()
  ok(PRINTED == "", "warns only once per change")
  nsS.UI:Show("builder"); RunTimers()
  local t = {} for i = 1, nsS.UI.cp.dungeon.used do t[#t + 1] = nsS.UI.cp.dungeon.pool[i]:GetText() end
  ok(table.concat(t, "\n"):find("dungeon list has changed", 1, true), "banner in Dungeon readiness")
  nsS.UI:Hide()
  DUNGEON_MAPS[399] = saved; DUNGEON_MAPS[700] = nil
  nsS:CheckSeason()
  ok(nsS.state.seasonMismatch == nil and nsS.db.seasonWarnedSig == nil, "warning clears when data matches again")
  local oldMT = C_ChallengeMode.GetMapTable
  C_ChallengeMode.GetMapTable = function() return {} end
  nsS:CheckSeason()
  ok(nsS.state.seasonMismatch == nil, "empty (not loaded) map list never warns")
  C_ChallengeMode.GetMapTable = oldMT
end

-- 30. Weekly affixes
do
  EnsembleDB = nil
  CURRENT_AFFIXES = { 158, 10, 9, 147 }   -- Voidbound, Fortified, Tyrannical, Guile
  local nsA2 = boot()
  local AF = nsA2.Affixes
  AF:Refresh()
  ok(#AF:Current() == 4 and AF:Current()[1].def.key == "VOIDBOUND", "current affixes read and matched")
  local function keys(level) local t = {} for _, a in ipairs((AF:Active(level))) do t[#t + 1] = a.def and a.def.key or "?" end return table.concat(t, ",") end
  ok(keys(4) == "", "+4: nothing (Lindormi not this week)")
  ok(keys(6) == "VOIDBOUND", "+6: Bargain only")
  ok(keys(8) == "VOIDBOUND,FORTIFIED", "+8: Bargain + this week's Fortified")
  ok(keys(10) == "VOIDBOUND,FORTIFIED,TYRANNICAL", "+10: both Fortified and Tyrannical")
  ok(keys(14) == "FORTIFIED,TYRANNICAL,GUILE", "+14: Guile replaces the Bargain")
  local _, assumed = AF:Active(nil)
  ok(assumed, "unknown level flagged as assumed")
  -- By name when the ID is unknown
  CURRENT_AFFIXES = { 777, 999 }; AF:Refresh()
  ok(AF:Current()[1].def and AF:Current()[1].def.key == "PULSAR" and AF:Current()[2].def == nil, "matched by name; unknown affix kept without rules")
  CURRENT_AFFIXES = { 158, 10, 9, 147 }; AF:Refresh()
  -- Requirements flow into the dungeon check at the right level
  local mem = { { specID = 73 }, { specID = 257 }, { specID = 63 } }
  local r8 = nsA2.Analysis:Analyze(mem, "KingsRest", nsA2.db.settings, { keyLevel = 8 })
  local r14 = nsA2.Analysis:Analyze(mem, "KingsRest", nsA2.db.settings, { keyLevel = 14 })
  local function has(r, id) for _, it in ipairs(r.dungeon.items) do if it.req.id == id then return it end end end
  ok(has(r8, "AFX_VOIDBOUND_1") and has(r8, "AFX_FORTIFIED_1") and not has(r8, "AFX_GUILE_1"), "+8 items: Voidbound + Fortified")
  ok(has(r14, "AFX_GUILE_1") and has(r14, "AFX_GUILE_2") and not has(r14, "AFX_VOIDBOUND_1"), "+14 items: Guile, no Bargain")
  ok(has(r8, "AFX_VOIDBOUND_1").category == "affixes", "affix category")
  nsA2.db.settings.dungeonCategories.affixes = false
  local rOff = nsA2.Analysis:Analyze(mem, "KingsRest", nsA2.db.settings, { keyLevel = 8 })
  ok(not has(rOff, "AFX_VOIDBOUND_1"), "affix category can be switched off")
  nsA2.db.settings.dungeonCategories.affixes = true
  -- Every affix requirement uses a valid capability
  for _, d in ipairs(AF.DEFS) do
    for _, q in ipairs(d.requirements) do
      ok(nsA2.UD.CAP_INFO[q.need] ~= nil, "affix need valid: " .. d.key)
      for _, a in ipairs(q.alt or {}) do ok(nsA2.UD.CAP_INFO[a] ~= nil, "affix alt valid: " .. d.key .. " " .. a) end
    end
  end
  -- UI line
  nsA2.db.currentComp = { 73, 257, 63, 0, 0 }
  nsA2:SetManualDungeon("KingsRest")
  nsA2.state.keyLevelOverride = 14
  nsA2.UI:Show("builder"); RunTimers()
  local t = {} for i = 1, nsA2.UI.cp.dungeon.used do t[#t + 1] = nsA2.UI.cp.dungeon.pool[i]:GetText() end
  local dt = table.concat(t, "\n")
  ok(dt:find("Affixes at +14:", 1, true) and dt:find("Xal'atath's Guile", 1, true) and dt:find("(affix: Xal'atath's Guile)", 1, true), "affix line, and affix needs tagged in their rows")
  nsA2.UI:Show("plan"); RunTimers()
  local st = {} for i = 1, nsA2.UI.pl.list.used do st[#st + 1] = nsA2.UI.pl.list.pool[i]:GetText() end
  ok(table.concat(st, "\n"):find("AFFIX", 1, true), "affix row in the cheat sheet")
  nsA2.state.keyLevelOverride = nil
  nsA2.UI:Hide()
  CURRENT_AFFIXES = {}
end

-- 31. Kick and dispel assignments
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  local nsK = boot()
  local AS, A3 = nsK.Assignments, nsK.Analysis
  ok(nsK.UD:Cooldown("Pummel", "interrupt") == 15 and nsK.UD:Cooldown("Silence", "interrupt") == 45, "cooldown table")
  -- Prot Warrior (Pummel 15), Holy Priest, Fire Mage (Counterspell 24), Assassination Rogue (Kick 15)
  local mem = { { specID = 73 }, { specID = 257 }, { specID = 63 }, { specID = 259 } }
  local r = A3:Analyze(mem, "TempleOfSethraliss", nsK.db.settings)
  local plan = AS:Build(r)
  ok(#plan.kicks > 0 and #plan.dispels > 0, "plan has kicks and dispels")
  local lb = plan.byReq.TOS_LIGHTNING_BOLT
  ok(lb and #lb.kickers == 2, "high-severity cast gets a two-kicker rotation")
  ok(lb.kickers[1].cd <= lb.kickers[2].cd, "rotation starts with the shortest cooldown")
  ok(lb.every and lb.every < 15, "combined kick rate reported: every ~" .. tostring(lb.every) .. "s")
  -- Load balancing: 15s kickers share more than the 24s kicker
  local counts = {}
  for _, row in ipairs(plan.kicks) do for _, k in ipairs(row.kickers) do counts[k.ability] = (counts[k.ability] or 0) + 1 end end
  ok((counts["Counterspell"] or 0) <= (counts["Pummel"] or 0) and (counts["Counterspell"] or 0) <= (counts["Kick"] or 0),
    "longer cooldown kicker gets fewer casts: " .. tostring(counts["Pummel"]) .. "/" .. tostring(counts["Kick"]) .. "/" .. tostring(counts["Counterspell"]))
  for _, row in ipairs(plan.kicks) do
    local seen = {}
    for _, k in ipairs(row.kickers) do ok(not seen[k.index], "no player twice in one rotation"); seen[k.index] = true end
    if row.backup then ok(not seen[row.backup.index], "backup is someone else") end
  end
  -- Dispels: Holy Priest takes the magic debuff; nobody for poison
  local ic = plan.byReq.TOS_IMBUED_CONDUCTION
  ok(ic and ic.primary and ic.primary.ability == "Purify" and ic.type == "Magic", "magic debuff -> Purify")
  ok(ic.notes[1] and ic.notes[1]:find("No backup", 1, true), "critical debuff with one dispeller flagged")
  local cy = plan.byReq.TOS_CYTOTOXIN
  ok(cy and not cy.primary and cy.severe, "nobody can remove poison: flagged")
  -- Only a long-cooldown kick: Shadow Priest (Silence 45s) alone
  local r2 = A3:Analyze({ { specID = 258 } }, "TempleOfSethraliss", nsK.db.settings)
  local p2 = AS:Build(r2)
  local row2 = p2.byReq.TOS_LIGHTNING_BOLT
  ok(row2 and row2.kickers[1] and row2.kickers[1].ability == "Silence" and row2.severe and row2.notes[1]:find("long%-cooldown"),
    "long-cooldown-only kick flagged")
  -- No kicker: interrupt-or-stop cast falls back to stoppers
  local r3 = A3:Analyze({ { specID = 65 } }, "TempleOfSethraliss", nsK.db.settings)   -- Holy Paladin: no kick
  local p3 = AS:Build(r3)
  local ed = p3.byReq.TOS_ESSENCE_DISRUPTION
  ok(ed and #ed.kickers == 0 and ed.stoppers and ed.stoppers[1], "no kicker: assigns a stop instead")
  -- Shared cooldown: Restoration Druid's Nature's Cure covers Magic + Poison
  local r4 = A3:Analyze({ { specID = 105 } }, "TempleOfSethraliss", nsK.db.settings)
  local p4 = AS:Build(r4)
  local shared = false
  for _, row in ipairs(p4.dispels) do for _, n in ipairs(row.notes) do if n:find("same cooldown", 1, true) then shared = true end end end
  ok(shared, "shared dispel cooldown noted")
  -- Two dispellers of the same type split dangerous debuffs
  local r5 = A3:Analyze({ { specID = 257 }, { specID = 256 } }, "TempleOfSethraliss", nsK.db.settings)
  local p5 = AS:Build(r5)
  local ic5 = p5.byReq.TOS_IMBUED_CONDUCTION
  ok(ic5.primary and ic5.backup and ic5.primary.index ~= ic5.backup.index, "primary and backup dispeller")
  -- Duplicate specs get distinct labels
  local r6 = A3:Analyze({ { specID = 72 }, { specID = 72 } }, "TempleOfSethraliss", nsK.db.settings)
  local p6 = AS:Build(r6)
  local labels = {}
  for _, p in ipairs(p6.people) do labels[#labels + 1] = p.label end
  ok(labels[1] ~= labels[2], "duplicate specs labeled apart: " .. table.concat(labels, " / "))
  -- Chat lines
  local lines = AS:ChatLines(plan, "Temple of Sethraliss")
  ok(#lines >= 3 and #lines <= 9, "chat lines: " .. #lines)
  for _, l in ipairs(lines) do ok(#l <= 255 and not l:find("|", 1, true), "chat line length/plain") end
  ok(lines[1]:find("assignments", 1, true) and lines[1]:find("1st/2nd", 1, true), "header explains the order")
  local hp
  for _, l in ipairs(lines) do if l:find("^Holy Priest: ") then hp = l end end
  ok(hp and hp:find("DISPEL", 1, true) and hp:find("(Magic)", 1, true), "one line per player, name first: " .. tostring(hp))
  local jobsAll = AS:PlayerJobs(plan)
  ok(#jobsAll == #plan.labels, "every player gets a line")
  -- UI: assignments under the cheat sheet + post button
  nsK.db.currentComp = { 73, 257, 63, 259, 0 }
  nsK:SetManualDungeon("TempleOfSethraliss")
  nsK.UI:Show("plan"); RunTimers()
  local side = nsK.UI.pl.list
  local t = {} for i = 1, side.used do t[#t + 1] = side.pool[i]:GetText() end
  local tx = table.concat(t, "\n")
  local tips = {} for i = 1, side.bused do tips[#tips + 1] = tostring(side.bpool[i].tip) end
  local tt = table.concat(tips, "\n")
  ok(tx:find("Kick: ", 1, true) and tx:find("Dispel: ", 1, true) and tx:find("Prot Warrior", 1, true),
    "assignments shown under each cast, one short line each")
  ok(tt:find("Pummel 15s", 1, true) and tt:find("Purify 8s", 1, true) and tt:find("Base cooldowns", 1, true),
    "abilities, cooldowns and the cooldown note are in the line's tooltip")
  ok(not tx:find("Base cooldowns", 1, true), "cooldown footnote moved into the tooltips")
  ok(not tx:find("Duty across all", 1, true) and tt:find("1st ", 1, true), "kick order shown as 1st/2nd, no duty totals")
  local postBtn = nsK.UI.pl.postPlanBtn
  ok(postBtn and postBtn:IsEnabled() and postBtn.tooltip:find(" assignments", 1, true), "post assignments button")
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" }, party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" } }
  SENT = {}
  postBtn:Click(); RunTimers(); RunTimers(); RunTimers(); RunTimers(); RunTimers(); RunTimers()
  ok(#SENT >= 3 and SENT[1].channel == "PARTY" and SENT[1].msg:find(" assignments", 1, true), "plan posted to party, one line per player (" .. #SENT .. ")")
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  nsK.UI:Hide()
end

-- 32. Applicant comparison, sort and filter
do
  EnsembleDB = nil
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
    party2 = { guid = "M", name = "Mia", class = "MAGE", role = "DAMAGER" },
  }
  INSPECT_CACHE = { H = 256, M = 63 }
  LISTING = "Temple of Sethraliss (Mythic Keystone)"
  APPLICANTS = {
    [1] = { { name = "Shamy", class = "SHAMAN", role = "DAMAGER", spec = 263, score = 2700, ilvl = 640 } },
    [2] = { { name = "Stabby", class = "ROGUE", role = "DAMAGER", spec = 259, score = 3100, ilvl = 650 } },
    [3] = { { name = "Bear", class = "DRUID", role = "TANK", spec = 104, score = 3500, ilvl = 660 } },
  }
  local nsP = boot()
  local UIp = nsP.UI
  UIp:Show("applicants"); RunTimers()
  local ctx, evals = nsP.ApplicantFit:ForLiveGroup()
  local byName = {}
  for _, ev in ipairs(evals) do byName[ev.members[1].name] = ev end
  local cmp = nsP.ApplicantFit:Compare(ctx, byName.Shamy, byName.Stabby)
  ok(cmp.winner == "a" and cmp.verdict:find("better fit", 1, true), "comparison verdict: " .. cmp.verdict)
  ok(#cmp.stats == 3 and cmp.stats[2].better == "b" and cmp.stats[3].better == "b", "stats: rating and ilvl favor B")
  local hasPoison = false
  for _, x in ipairs(cmp.onlyA) do if x:find("Poison", 1, true) then hasPoison = true end end
  ok(hasPoison, "only A brings Poison dispel")
  ok(#cmp.fixA >= 1 and #cmp.fixB == 0, "dungeon needs only A closes")
  local cmpRole = nsP.ApplicantFit:Compare(ctx, byName.Bear, byName.Stabby)
  ok(cmpRole.winner == "b" and cmpRole.verdict:find("open slot", 1, true), "role conflict decides")
  -- UI pins
  local function cardFor(name)
    for _, c in ipairs(UIp.ap.cards) do if c:IsShown() and c.name:GetText():find(name, 1, true) then return c end end
  end
  cardFor("Shamy").cmp:Click(); RunTimers()
  local function detail() local t = {} for i = 1, UIp.ap.detail.used do t[#t + 1] = UIp.ap.detail.pool[i]:GetText() end return table.concat(t, "\n") end
  ok(detail():find("pin one more", 1, true) and cardFor("Shamy").cmp.text:GetText() == "Pinned", "one pin: hint shown")
  cardFor("Stabby").cmp:Click(); RunTimers()
  ok(detail():find("Comparing", 1, true) and detail():find("SIDE BY SIDE", 1, true), "two pins: comparison shown")
  cardFor("Bear").cmp:Click(); RunTimers()
  ok(#UIp.ap.compare == 2 and UIp.ap.compare[1] == 2 and UIp.ap.compare[2] == 3, "third pin replaces the oldest")
  cardFor("Bear").cmp:Click(); RunTimers()
  ok(#UIp.ap.compare == 1, "clicking a pinned card unpins")
  -- Invite straight from the card
  local invited = {}
  C_LFGList.InviteApplicant = function(id) invited[#invited + 1] = id end
  UIp:Refresh(); RunTimers()
  local inv = cardFor("Shamy").inv
  ok(inv:IsEnabled() and inv.text:GetText() == "Invite", "invite button ready on each applicant")
  inv:Click(); RunTimers()
  ok(invited[1] == 1, "invite sends that applicant's application")
  inv = cardFor("Shamy").inv
  ok(inv.text:GetText() == "Invited" and not inv:IsEnabled(), "card shows Invited afterward")
  local oldIn, oldLead, oldAsst = IsInGroup, UnitIsGroupLeader, UnitIsGroupAssistant
  IsInGroup = function() return true end
  UnitIsGroupLeader = function() return false end
  UnitIsGroupAssistant = function() return false end
  UIp:Refresh(); RunTimers()
  inv = cardFor("Stabby").inv
  ok(not inv:IsEnabled() and inv.tooltip:find("group leader", 1, true), "only the leader or an assistant can invite")
  IsInGroup, UnitIsGroupLeader, UnitIsGroupAssistant = oldIn, oldLead, oldAsst
  C_LFGList.InviteApplicant = function() error("blocked") end
  PRINTED = ""
  UIp:Refresh(); RunTimers()
  cardFor("Stabby").inv:Click(); RunTimers()
  ok(PRINTED:find("didn't accept the invite", 1, true), "a refused invite says so")
  local fullCtx = { open = { TANK = 0, HEALER = 0, DAMAGER = 0 } }
  local can, why = UIp:CanInvite(byName.Bear, fullCtx)
  ok(not can and why:find("full", 1, true), "no invite when the group is full")
  C_LFGList.InviteApplicant = nil
  UIp:Refresh(); RunTimers()
  ok(not cardFor("Bear").inv:IsEnabled(), "no invite button action without the client function")
  -- Sorting and filter
  nsP.db.settings.applicantView.sort = "rating"; UIp:Refresh(); RunTimers()
  local order = {}
  for _, c in ipairs(UIp.ap.cards) do if c:IsShown() then order[#order + 1] = c.name:GetText():match("|c%x%x%x%x%x%x%x%x(%a+)") end end
  ok(order[1] == "Bear" and order[2] == "Stabby", "sorted by rating: " .. table.concat(order, ","))
  ok(UIp.ap.sortBtns.rating.active and not UIp.ap.sortBtns.fit.active, "sort button state")
  nsP.db.settings.applicantView.hidePoor = true; UIp:Refresh(); RunTimers()
  local shown = 0
  for _, c in ipairs(UIp.ap.cards) do if c:IsShown() then shown = shown + 1 end end
  ok(shown == 1 and cardFor("Shamy") and not cardFor("Bear") and not cardFor("Stabby"), "Hide Poor removes poor fits (" .. shown .. " shown)")
  local _, evals2 = nsP.ApplicantFit:ForLiveGroup()
  ok(#evals2 == 3, "shared evaluation list not mutated by the view")
  -- Pin removed when the applicant leaves
  UIp.ap.compare = { 1, 2 }
  APPLICANTS[2] = nil
  nsP.Tracker:RequestUpdate(); RunTimers()
  ok(#UIp.ap.compare == 1, "pin dropped when applicant is gone")
  UIp:Hide()
  LISTING = nil
  APPLICANTS = { [7] = { { name = "Applicant-Realm", class = "SHAMAN", role = "HEALER", spec = 264, score = 2900 } } }
end

-- 33. Run history
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
  }
  INSPECT_CACHE = { H = 257 }
  local nsH = boot()
  local Hs = nsH.History
  local hf
  for _, fr in ipairs(ALLFRAMES) do if fr._events.CHALLENGE_MODE_COMPLETED then hf = fr end end
  ok(hf ~= nil, "history listens for key events")
  local function fire(ev) hf._scripts.OnEvent(hf, ev); RunTimers() end
  local function runKey(mapID, level, timed)
    ACTIVE_CHALLENGE, ACTIVE_KEY_LEVEL, ACTIVE_KEY_AFFIXES = mapID, level, { 10, 158 }
    fire("CHALLENGE_MODE_START")
    COMPLETION = { mapChallengeModeID = mapID, level = level, time = 1700500, onTime = timed, keystoneUpgradeLevels = timed and 2 or 0 }
    DEATHS = 4
    fire("CHALLENGE_MODE_COMPLETED")
    ACTIVE_CHALLENGE = nil
  end
  runKey(250, 12, true)
  local h = nsH.db.history
  ok(#h == 1 and h[1].key == "TempleOfSethraliss" and h[1].level == 12 and h[1].result == "timed", "timed run recorded")
  ok(h[1].time == 1701 and h[1].deaths == 4 and h[1].upgrade == 2 and h[1].timeLimit == 1800, "time, deaths, upgrade, limit")
  ok(#h[1].comp == 2 and h[1].comp[1].specID ~= nil, "group snapshot stored")
  ok(#h[1].gaps > 0, "gaps stored at record time")
  ok(nsH.db.activeRun == nil and not nsH.Tracker:IsHeldBy("history"), "tracker released after the key")
  runKey(249, 10, false)
  ok(h[1].result == "overtime", "over-time run recorded")
  -- Abandon via leaving the instance
  ACTIVE_CHALLENGE, ACTIVE_KEY_LEVEL = 588, 9
  fire("CHALLENGE_MODE_START")
  fire("PLAYER_ENTERING_WORLD")     -- /reload inside the key: kept
  ok(nsH.db.activeRun ~= nil, "reload inside a key keeps the run")
  ACTIVE_CHALLENGE = nil
  fire("PLAYER_ENTERING_WORLD")
  ok(h[1].result == "abandoned" and nsH.db.activeRun == nil, "leaving without finishing = abandoned")
  -- Practice runs are not recorded
  local before = #h
  ACTIVE_CHALLENGE, ACTIVE_KEY_LEVEL = 250, 2
  fire("CHALLENGE_MODE_START")
  COMPLETION = { mapChallengeModeID = 250, level = 2, time = 1000, onTime = true, practiceRun = true }
  fire("CHALLENGE_MODE_COMPLETED")
  ACTIVE_CHALLENGE = nil
  ok(#h == before, "practice runs skipped")
  -- Recording off
  nsH.db.settings.history = false
  ACTIVE_CHALLENGE = 250; fire("CHALLENGE_MODE_START"); ACTIVE_CHALLENGE = nil
  ok(nsH.db.activeRun == nil, "recording can be turned off")
  nsH.db.settings.history = true
  -- Insights from synthetic runs
  local function mk(result, gaps, key) local g = {} for _, t in ipairs(gaps) do g[#g + 1] = { title = t, status = "missing" } end
    return { key = key or "KingsRest", level = 10, result = result, gaps = g } end
  local runs = {
    mk("overtime", { "Bloodlust / Heroism" }), mk("overtime", { "Bloodlust / Heroism" }), mk("timed", { "Bloodlust / Heroism" }),
    mk("timed", {}), mk("timed", {}), mk("timed", { "Curse dispel" }), mk("overtime", {}), mk("abandoned", { "Bloodlust / Heroism" }),
  }
  local ins = Hs:Insights(runs)
  ok(ins.total == 8 and ins.finished == 7 and ins.timed == 4 and ins.abandoned == 1, "insight totals")
  ok(#ins.gaps == 1 and ins.gaps[1].title == "Bloodlust / Heroism", "only gaps with enough samples on both sides")
  ok(math.abs(ins.gaps[1].rateWith - 1/3) < 1e-6 and math.abs(ins.gaps[1].rateWithout - 0.75) < 1e-6, "rates with/without the gap")
  ok(ins.dungeons[1].key == "KingsRest" and ins.dungeons[1].n == 7, "per-dungeon stats")
  -- Cap
  for i = 1, 520 do table.insert(nsH.db.history, 1, mk("timed", {})) end
  runKey(250, 12, true)
  ok(#nsH.db.history == Hs.MAX_RUNS, "history capped at " .. Hs.MAX_RUNS)
  -- UI
  nsH.db.history = { h[1] or mk("timed", {}) }
  nsH.UI:Show("history"); RunTimers()
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  local rt = dump(nsH.UI.hp.runs)
  ok(rt:find("Temple of Sethraliss", 1, true) and rt:find("TIMED", 1, true) and rt:find("Affixes: Fortified", 1, true), "run list rendered")
  ok(dump(nsH.UI.hp.insights):find("1 key recorded", 1, true), "insights rendered")
  nsH.UI.hp.filter = "KingsRest"; nsH.UI:Refresh(); RunTimers()
  ok(dump(nsH.UI.hp.runs):find("No keys recorded yet", 1, true), "dungeon filter")
  nsH.UI.hp.clear:Click(); nsH.UI.hp.clear:Click(); RunTimers()
  ok(#nsH.db.history == 0, "clear history (two clicks)")
  nsH.UI:Show("history"); RunTimers()
  ok(nsH.UI.currentTab == "history", "History tab opens")
  nsH.UI:Hide()
end

-- 34. Review fixes
do
  EnsembleDB = nil
  CURRENT_AFFIXES = { 160, 162 }
  local nsR = boot()
  local AF = nsR.Affixes
  AFFIX_INFO[160] = "Xal'atath's Bargain: Devour"; AFFIX_INFO[162] = "Xal'atath's Bargain: Pulsar"
  AF:Refresh()
  ok(AF:Current()[1].def.key == "DEVOUR" and AF:Current()[2].def.key == "PULSAR", "affix 160 = Devour, 162 = Pulsar")
  -- Ascendant: a stop job, not a kick rotation; stop providers assigned
  CURRENT_AFFIXES = { 148 }; AF:Refresh()
  local r = nsR.Analysis:Analyze({ { specID = 65 } }, "TempleOfSethraliss", nsR.db.settings, { keyLevel = 8 })
  local plan = nsR.Assignments:Build(r)
  ok(plan.byReq.AFX_ASCENDANT_1 == nil, "Ascendant (stop or interrupt) is not a kick row")
  -- Dispel row with an alternative: Altar of Fangs enrage (soothe or stop)
  CURRENT_AFFIXES = {}; AF:Refresh()
  local r2 = nsR.Analysis:Analyze({ { specID = 73 }, { specID = 65 } }, "AltarOfFangs", nsR.db.settings)
  local p2 = nsR.Assignments:Build(r2)
  local en = p2.byReq.AOF_ENRAGE
  ok(en and not en.primary and en.stoppers and not en.severe, "no soother: the stun alternative is assigned, not flagged")
  -- Kick fallback includes the requirement's own need (stop-type requirement)
  local fake = { members = r2.members, filled = 2, caps = r2.caps, dungeon = { items = {
    { req = { id = "X1", need = "interrupt", alt = { "stop" }, severity = "high", source = "Test Cast (Mob)" }, status = "thin", providers = {} } } } }
  local saveCaps = fake.caps.interrupt; fake.caps.interrupt = {}
  -- Members have Pummel; to force "no kicker", build with a healer-only roster instead
  local r3 = nsR.Analysis:Analyze({ { specID = 65 } }, "TempleOfSethraliss", nsR.db.settings)
  local p3 = nsR.Assignments:Build(r3)
  ok(p3.byReq.TOS_ESSENCE_DISRUPTION.stoppers ~= nil, "no kicker falls back to stoppers")
  fake.caps.interrupt = saveCaps
  -- Chat chunking never exceeds 250 and never emits a bare prefix
  local longPlan = { kicks = { { severity = "high", cast = string.rep("x", 300), kickers = { { label = "Ann" } } },
    { severity = "high", cast = "Short", kickers = { { label = "Bob" } } } }, dispels = {} }
  for _, l in ipairs(nsR.Assignments:ChatLines(longPlan, "D")) do
    ok(#l <= 255 and not l:match(": $"), "chunked line ok (" .. #l .. ")")
  end
  -- Chat lockdown: print locally instead of sending
  C_ChatInfo = { InChatMessagingLockdown = function() return true end }
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" }, party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" } }
  nsR.db.currentComp = { 73, 257, 0, 0, 0 }
  nsR:SetManualDungeon("TempleOfSethraliss")
  nsR.UI:Show("builder"); RunTimers()
  SENT = {}; PRINTED = ""
  nsR.UI:PostGaps()
  ok(#SENT == 0 and PRINTED:find("copy window", 1, true), "chat lockdown: the gaps post goes to the copy window, like the assignments post")
  C_ChatInfo = nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  nsR.UI:Hide()
  -- History: don't abandon while still in a keystone instance with state pending
  local hf
  for _, fr in ipairs(ALLFRAMES) do if fr._events.CHALLENGE_MODE_COMPLETED then hf = fr end end
  ACTIVE_CHALLENGE, ACTIVE_KEY_LEVEL, ACTIVE_KEY_AFFIXES = 250, 9, { 148 }
  hf._scripts.OnEvent(hf, "CHALLENGE_MODE_START"); RunTimers()
  ACTIVE_CHALLENGE = nil
  local oldGII = GetInstanceInfo
  GetInstanceInfo = function() return "Temple of Sethraliss", "party", 8, "Mythic Keystone", 5, 0, false, 1877 end
  nsR.History:OnEnteringWorld()
  ok(nsR.db.activeRun ~= nil, "still in the keystone instance: run kept")
  GetInstanceInfo = oldGII
  nsR.History:OnEnteringWorld()
  ok(nsR.db.activeRun == nil and nsR.db.history[1].result == "abandoned", "outside: abandoned")
  -- Recorded gaps used the run's affixes (Ascendant), not this week's (none)
  local hadAscendant = false
  local r4 = nsR.Analysis:Analyze({ { specID = 73 } }, "TempleOfSethraliss", nsR.db.settings, { keyLevel = 9, affixIDs = { 148 } })
  for _, it in ipairs(r4.dungeon.items) do if it.req.id == "AFX_ASCENDANT_1" then hadAscendant = true end end
  ok(hadAscendant, "Analyze honors a run's own affix list")
  ACTIVE_CHALLENGE, ACTIVE_KEY_AFFIXES = nil, {}
  CURRENT_AFFIXES = {}
end

-- 35. In-client report: Lindormi ID and confirmed instance IDs
do
  EnsembleDB = nil
  local nsZ = boot()
  ok(nsZ.Affixes.Match(165, "Lindormis Fuehrung").key == "LINDORMI", "Lindormi matched by ID 165")
  ok(nsZ.Dungeons:KeyForInstanceMap(2813) == "MurderRow" and nsZ.Dungeons:KeyForInstanceMap(2993) == "AltarOfFangs",
    "confirmed instance IDs known without map data")
end

-- 36. Class suggestions for empty slots only
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  local nsG = boot()
  local A4 = nsG.Analysis
  local slots = { { specID = 73 }, { specID = 257 }, { specID = 63 }, nil, nil }
  local groups = A4:SuggestClasses(slots, nsG.SLOT_ROLES, "TempleOfSethraliss", nsG.db.settings, 4)
  ok(#groups == 1 and groups[1].role == "DAMAGER" and groups[1].open == 2, "only the open role is suggested (2 DPS open)")
  local cl = groups[1].classes
  ok(#cl == 4, "up to 4 classes")
  for i = 2, #cl do ok(cl[i - 1].gain >= cl[i].gain, "ranked best fit first") end
  local seen = {}
  for _, c in ipairs(cl) do
    ok(not seen[c.classFile], "one entry per class"); seen[c.classFile] = true
    ok(#c.reasons > 0, "each suggestion explains why: " .. c.classFile)
    for _, id in ipairs(c.specs) do ok(nsG.UD:GetSpec(id).role == "DAMAGER", "suggested specs fit the open role") end
  end
  -- Synergy reasons appear (a buff for existing players, or an existing buff for them)
  local syn = false
  for _, c in ipairs(cl) do for _, r in ipairs(c.reasons) do if r:find("boosts", 1, true) or r:find("benefits from your", 1, true) then syn = true end end end
  ok(syn, "synergy with filled slots is a reason")
  -- Full group: nothing suggested
  local full = A4:SuggestClasses({ { specID = 73 }, { specID = 257 }, { specID = 63 }, { specID = 259 }, { specID = 262 } },
    nsG.SLOT_ROLES, "TempleOfSethraliss", nsG.db.settings)
  ok(#full == 0, "full group: no suggestions (no swaps)")
  -- Empty healer slot only: healers suggested, nobody else
  local h = A4:SuggestClasses({ { specID = 73 }, nil, { specID = 63 }, { specID = 259 }, { specID = 262 } },
    nsG.SLOT_ROLES, "TempleOfSethraliss", nsG.db.settings)
  ok(#h == 1 and h[1].role == "HEALER" and h[1].slot == 2, "only the empty healer slot")
  -- UI: click fills the empty slot, never replaces a filled one
  nsG.db.currentComp = { 73, 257, 63, 0, 0 }
  nsG:SetManualDungeon("TempleOfSethraliss")
  nsG.UI:Show("builder"); RunTimers()
  local side = nsG.UI.cp.sideList
  local t = {} for i = 1, side.used do t[#t + 1] = side.pool[i]:GetText() end
  local tx = table.concat(t, "\n")
  ok(tx:find("SUGGESTED FOR OPEN SLOTS", 1, true) and tx:find("2 open", 1, true) and tx:find("Why: ", 1, true), "suggestions rendered")
  local btn
  for i = 1, side.bused do if side.bpool[i].tip and side.bpool[i].tip:find("in the open slot", 1, true) then btn = side.bpool[i]; break end end
  ok(btn ~= nil, "suggestion is clickable in the Builder")
  btn:Click(); RunTimers()
  ok(nsG.db.currentComp[1] == 73 and nsG.db.currentComp[2] == 257 and nsG.db.currentComp[3] == 63 and nsG.db.currentComp[4] ~= 0
    and nsG.db.currentComp[5] == 0, "click filled the first empty DPS slot only")
  nsG.db.currentComp = { 73, 257, 63, 259, 262 }
  nsG:Fire("COMP_CHANGED"); RunTimers()
  t = {} for i = 1, side.used do t[#t + 1] = side.pool[i]:GetText() end
  ok(table.concat(t, "\n"):find("All five slots are filled", 1, true), "full group message")
  nsG.UI:Hide()
end

-- 37. No duplicate classes in suggestions (except across roles)
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  local nsD2 = boot()
  local A5 = nsD2.Analysis
  -- Warrior tank, Holy Paladin healer, Fury Warrior + Fire Mage DPS, one DPS open
  local slots = { { specID = 73 }, { specID = 65 }, { specID = 72 }, { specID = 63 }, nil }
  local g = A5:SuggestClasses(slots, nsD2.SLOT_ROLES, "TempleOfSethraliss", nsD2.db.settings, 40)
  local dps = g[1]
  local classes = {}
  for _, c in ipairs(dps.classes) do classes[c.classFile] = true end
  ok(not classes.WARRIOR and not classes.MAGE, "classes already in the DPS role are not suggested again")
  ok(classes.PALADIN, "a class in another role (Holy Paladin healer) can still be suggested for DPS")
  -- Healer and DPS open with a Paladin tank: Paladin can appear for both (different roles)
  local g2 = A5:SuggestClasses({ { specID = 73 }, nil, { specID = 72 }, { specID = 63 }, nil }, nsD2.SLOT_ROLES, "KingsRest", nsD2.db.settings, 40)
  local seen = {}
  for _, grp in ipairs(g2) do
    local inRole = {}
    for _, c in ipairs(grp.classes) do
      ok(not inRole[c.classFile], "no class twice within a role")
      inRole[c.classFile] = true
    end
    seen[grp.role] = inRole
  end
  ok(seen.HEALER and seen.DAMAGER, "both open roles listed")
  -- Pending live member (class only) blocks its class in its role too
  local g3 = A5:SuggestClasses({ { specID = 73 }, { specID = 256 }, { classFile = "ROGUE", role = "DAMAGER" }, nil, nil },
    nsD2.SLOT_ROLES, "TempleOfSethraliss", nsD2.db.settings, 40)
  local rogue = false
  for _, c in ipairs(g3[1].classes) do if c.classFile == "ROGUE" then rogue = true end end
  ok(not rogue, "spec-pending member's class not suggested again for the same role")
end

-- 38. Expanders everywhere, coverers on every THIN/MISSING, summary strip links
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  local nsE = boot()
  local UIe = nsE.UI
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  local function btnWith(l, pred) for i = 1, l.bused do local b = l.bpool[i]; if b:IsShown() and pred(b) then return b end end end
  nsE.db.currentComp = { 73, 257, 72, 71, 0 }
  nsE:SetManualDungeon("TempleOfSethraliss")
  UIe:Show("builder"); RunTimers()
  -- Suggestion reasons: "+N more reasons" expands and folds
  local side = UIe.cp.sideList
  local why = btnWith(side, function(b) return b.tip == "Show all" end)
  ok(why ~= nil, "suggestion reasons have a +N more toggle")
  local u = side.used; why:Click(); RunTimers()
  ok(side.used >= u and dump(side):find("show fewer", 1, true), "reasons expanded, with show fewer")
  btnWith(side, function(b) return b.tip == "Show fewer" end):Click(); RunTimers()
  ok(not dump(side):find("show fewer", 1, true), "reasons folded again")
  -- Cheat sheet "+N more casts"
  UIe:Show("plan"); RunTimers()
  local plan = UIe.pl.list
  local rows = UIe:CheatSheetRows("TempleOfSethraliss")
  local big
  for _, r in ipairs(rows) do if #r.reqs > 5 then big = r end end
  if big then
    ok(dump(plan):find("more cast", 1, true), "cheat sheet shows +N more casts")
    btnWith(plan, function(b) return b.tip == "Show all" end):Click(); RunTimers()
    ok(dump(plan):find("show fewer", 1, true), "cheat sheet expands")
  else
    ok(not dump(plan):find("more in Dungeon readiness", 1, true), "no dead-end '+N more' text in the cheat sheet")
  end
  UIe:Show("composition"); RunTimers()
  -- Summary risks line opens the full problem list
  UIe.cp.riskBtn._scripts.OnClick(UIe.cp.riskBtn); RunTimers()
  ok(dump(UIe.cp.ready):find("All gaps", 1, true) and UIe:IsOpen("risks", false), "risks line opens All gaps")
  -- Finder panel: 8 shown, +N more expands to 16
  LISTING = "Temple of Sethraliss (Mythic Keystone)"
  APPLICANTS = {}
  for i = 1, 12 do APPLICANTS[i] = { { name = "A" .. i, class = "ROGUE", role = "DAMAGER", spec = 259 } } end
  PVEFrame:Show(); RunTimers()
  local fp = UIe.fp
  local shown = 0 for i = 1, 16 do if fp.rows[i]:IsShown() then shown = shown + 1 end end
  ok(shown == 8 and fp.more.text:GetText() == "+ 4 more", "panel shows 8 with +4 more")
  fp.more:Click(); RunTimers()
  shown = 0 for i = 1, 16 do if fp.rows[i]:IsShown() then shown = shown + 1 end end
  ok(shown == 12 and fp.more.text:GetText() == "- show fewer", "panel expands to show everyone")
  fp.more:Click(); RunTimers()
  shown = 0 for i = 1, 16 do if fp.rows[i]:IsShown() then shown = shown + 1 end end
  ok(shown == 8, "and folds back")
  -- Applicant detail: remaining gaps with coverers
  UIe:Show("applicants"); RunTimers()
  local d = dump(UIe.ap.detail)
  ok(d:find("Still ", 1, true) and d:find("can cover:", 1, true), "applicant detail: remaining gaps list who can cover them")
  PVEFrame:Hide(); RunTimers()
  UIe:Hide()
  LISTING = nil
  APPLICANTS = { [7] = { { name = "Applicant-Realm", class = "SHAMAN", role = "HEALER", spec = 264, score = 2900 } } }
end

-- 39. Review fixes (presentation)
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  local nsF2 = boot()
  local U2 = nsF2.UI
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  -- Long-cooldown-only kicks: MISSING row keeps its explanation
  nsF2.db.currentComp = { 0, 0, 102, 258, 0 }
  nsF2:SetManualDungeon("NONE")
  U2:Show("builder"); RunTimers()
  local t = dump(U2.cp.ready)
  ok(t:find("rotational", 1, true) and t:find("Covered by: ", 1, true), "missing interrupt row explains long-cooldown-only kicks")
  nsF2.db.currentComp = { 73, 257, 72, 71, 63 }
  nsF2:SetManualDungeon("TempleOfSethraliss")
  -- Chips never run past the strip: they wrap onto more rows at any width
  local function check(width)
    U2.cp.chipBar._w = width; U2:Refresh(); RunTimers()
    local inside, shown = true, 0
    for _, b in ipairs(U2.cp.chips) do
      if b:IsShown() then
        shown = shown + 1
        local x = b._point[4]
        if x + b._w > width + 0.5 then inside = false end
      end
    end
    return inside, shown, U2.cp.chipRows, U2.cp.sumPanel._h
  end
  local in1, n1, rows1, h1 = check(200)
  ok(in1 and n1 == #U2.cp.lastReady.chips and rows1 > 1, "narrow strip: every chip shown, wrapped, inside the edge (" .. rows1 .. " rows)")
  local in2, n2, rows2, h2 = check(2000)
  ok(in2 and n2 == n1 and rows2 == 1 and h2 < h1, "wide strip: one row, shorter panel")
  local in3 = check(952 - 40)
  ok(in3, "default width: chips inside the edge")
  local below = false
  for _, pt in ipairs(U2.cp.left._points or {}) do if pt[2] == U2.cp.sumPanel and pt[3] == "BOTTOMLEFT" then below = true end end
  ok(below, "columns hang below the summary strip, so a taller strip pushes them down")
  U2.cp.chipBar._w = 900
  -- Coverers include a short requirement's alternative (Altar enrage: soothe or stop)
  local r = nsF2.Analysis:Analyze({ { specID = 65 } }, "AltarOfFangs", nsF2.db.settings)
  for _, it in ipairs(r.dungeon.items) do if it.req.id == "AOF_ENRAGE" then it.status = "missing" end end  -- as if nobody could stop it
  local ready = nsF2.Analysis:Readiness(r)
  local sooth = ready.rows.soothe
  local hasStop = false
  for _, k in ipairs(sooth and sooth.coverKeys or {}) do if k == "stop" then hasStop = true end end
  ok(sooth and hasStop, "coverers for soothe also consider stops")
  -- Text size grows slot rows
  U2:SetTextSize(125)
  ok(U2.cp.slotRows[1]._h > 40, "slot rows grow with text size")
  U2:SetTextSize(100)
  ok(U2.cp.slotRows[1]._h == 40, "and shrink back")
  U2:Hide()
end

-- 40. Learning features
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 72, role = "DAMAGER" } }
  local nsL = boot()
  local UIl = nsL.UI
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  -- 1. Explanations: every capability has one; shown in open rows; off switch removes only teaching text
  for _, c in ipairs(nsL.UD.CAPS) do ok(nsL.UD:CapExplain(c.key) ~= nil, "explanation for " .. c.key) end
  nsL.db.currentComp = { 73, 257, 72, 71, 0 }
  nsL:SetManualDungeon("TempleOfSethraliss")
  UIl:Show("builder"); RunTimers()
  local rt = dump(UIl.cp.ready)
  ok(rt:find("Removes Poisons from your group.", 1, true), "explanation shown under an open need")
  UIl:Show("plan"); RunTimers()
  ok(dump(UIl.pl.list):find("Dispel every one or it stuns on expiry.", 1, true), "mechanic notes in Assignments")
  UIl:Show("composition"); RunTimers()
  nsL.db.settings.explain = false; UIl:Refresh(); RunTimers()
  local rt2 = dump(UIl.cp.ready)
  ok(not rt2:find("Removes Poisons from your group.", 1, true) and rt2:find("Can cover it", 1, true) and rt2:find("Cytotoxin", 1, true),
    "expert mode drops explanations but keeps every gap and coverer")
  UIl:Show("plan"); RunTimers()
  ok(not dump(UIl.pl.list):find("Dispel every one or it stuns", 1, true), "expert mode: Assignments without notes")
  UIl:Show("composition"); RunTimers()
  nsL.db.settings.explain = true
  -- glossary
  UIl:ShowGlossary(); RunTimers()
  local g = dump(UIl.glossary.list)
  ok(UIl.glossary:IsShown() and g:find("THIN", 1, true) and g:find("Rotational kick", 1, true) and g:find("Curse dispel", 1, true), "glossary")
  UIl.glossary:Hide()
  -- 2. Every requirement has a mechanic note
  local missingNote = 0
  for _, k in ipairs(nsL.Dungeons.order) do for _, q in ipairs(nsL.Dungeons.list[k].requirements) do if not q.note then missingNote = missingNote + 1 end end end
  ok(missingNote == 0, "every requirement explains its mechanic")
  -- 7. Your job (your spec is Fury Warrior, in slot 3)
  UIl:Show("plan"); RunTimers()
  local pt = dump(UIl.pl.mine)
  ok(pt:find("YOUR ASSIGNMENTS", 1, true) and pt:find("As Fury Warrior", 1, true) and pt:find("Kick:", 1, true), "your assignments from the plan")
  ok(UIl.pl.rightTitle:GetText():find("^ASSIGNMENTS: ") and dump(UIl.pl.list):find("KICK", 1, true), "full assignments beside them")
  nsL.db.currentComp = { 73, 257, 71, 63, 0 }; UIl:Refresh(); RunTimers()
  ok(dump(UIl.pl.mine):find("Put your own spec (Fury Warrior)", 1, true), "hint when your spec isn't in the comp")
  UIl:Show("composition"); RunTimers()
  -- 6. Spec preview in the slot menu
  nsL.db.currentComp = { 73, 257, 72, 71, 0 }; UIl:Refresh(); RunTimers()
  local prev = UIl:SpecPreviewText(5, 263)
  ok(prev:find("Enhancement Shaman", 1, true) and prev:find("Poison dispel", 1, true) and prev:find("Net: +", 1, true), "spec preview: " .. prev:sub(1, 80))
  ok(UIl:SpecPreviewText(3, 72):find("Already in this slot", 1, true), "preview for the current spec")
  local repl = UIl:SpecPreviewText(2, 256)
  ok(repl:find("replacing Holy Priest", 1, true), "preview says what it replaces")
  local items
  local oldShow = UIl.ShowMenu
  UIl.ShowMenu = function(_, _, it) items = it end
  UIl:OpenSpecMenu(UIl.cp.slotRows[5], 5)
  UIl.ShowMenu = oldShow
  ok(type(items[2].tooltip) == "function" and items[2].tooltip():find("Net:", 1, true), "spec menu items carry the preview")
  -- 3. Dungeon primer
  UIl:Show("dungeons"); RunTimers()
  UIl:SetPrimerPick("TempleOfSethraliss"); UIl:Refresh(); RunTimers()
  local at, vt = dump(UIl.pp.asks), dump(UIl.pp.value)
  ok(at:find("MAGIC DISPEL", 1, true) and at:find("Imbued Conduction", 1, true) and at:find("Dispel every one", 1, true), "primer: needs with mechanics")
  ok(vt:find("TANK", 1, true) and vt:find("HEALER", 1, true) and vt:find("DPS", 1, true) and vt:find("answers:", 1, true), "primer: best value per role")
  ok(vt:find("KEY NEEDS: TEMPLE OF SETHRALISS", 1, true) and not vt:find("Kick: 1", 1, true), "primer: key needs, no assignments")
  local prof = nsL.Analysis:DungeonProfile("TempleOfSethraliss", nsL.db.settings)
  ok(prof.needs[1].worst == "critical", "primer: most dangerous need first")
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    local l = prof.roles[role]
    for i = 2, #l do ok(l[i - 1].score >= l[i].score, "primer ranking " .. role) end
  end
  ok(UIl.cp.lastPlan ~= false, "primer leaves the Builder's plan alone")
  UIl:Show("dungeons"); ok(UIl.currentTab == "dungeons", "Dungeon tab opens")
  UIl:Hide()
end

-- 41. Score breakdown, wait times, Group Finder tooltips
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
  }
  INSPECT_CACHE = { H = 257 }
  LISTING = "Temple of Sethraliss (Mythic Keystone)"
  APPLICANTS = { [1] = { { name = "Shamy", class = "SHAMAN", role = "DAMAGER", spec = 263 } },
                 [2] = { { name = "Bear", class = "DRUID", role = "TANK", spec = 104 } } }
  NOW = 1000
  local nsS2 = boot()
  local US = nsS2.UI
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  US:Show("applicants"); RunTimers()
  local _, evs = nsS2.ApplicantFit:ForLiveGroup()
  local sham
  for _, ev in ipairs(evs) do if ev.applicantID == 1 then sham = ev end end
  local sum = 0
  for _, b in ipairs(sham.breakdown) do sum = sum + b.points end
  ok(math.abs(sum - sham.gain) < 0.01, "breakdown adds up to the gain")
  US.ap.selected = 1; US:Refresh(); RunTimers()
  ok(dump(US.ap.detail):find("+ Why " .. sham.score .. "?", 1, true), "Why N? line (folded)")
  US:SetOpen("score:1", true); RunTimers()
  local d = dump(US.ap.detail)
  ok(d:find("covers Poison dispel for Cytotoxin", 1, true) and d:find("as a pick.", 1, true) and d:find("Total:", 1, true)
    and not d:find("Looking ahead", 1, true), "breakdown shown (pick rating, no look-ahead part)")
  ok(d:find("Group after: ", 1, true), "detail: Group after line under Group after inviting")
  US.ap.selected = 2; US:SetOpen("score:2", true); RunTimers()
  ok(dump(US.ap.detail):find("capped at 15", 1, true), "role-conflict breakdown explains the cap")
  -- Wait times
  local card
  for _, c in ipairs(US.ap.cards) do if c:IsShown() and c.name:GetText():find("Shamy", 1, true) then card = c end end
  ok(card.wait:GetText():find("waiting 0:00", 1, true), "wait time starts at 0:00, on its own line part")
  NOW = 1000 + 200; TickAll()
  ok(card.wait:GetText():find("waiting 3:20", 1, true), "ticker updates wait time: " .. card.wait:GetText())
  -- Group Finder tooltip hook
  PVEFrame:Show(); RunTimers()
  ok(HOOKS.LFGListApplicantMember_OnEnter == nil, "no hook when the Blizzard function doesn't exist")
  LFGListApplicantMember_OnEnter = function() end
  US.tipHooked = nil; US:AttachFinderPanel()
  ok(type(HOOKS.LFGListApplicantMember_OnEnter) == "function", "hooked Blizzard applicant tooltip")
  local lines = {}
  GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
  local parent = CreateFrame("Frame"); parent.applicantID = 1
  local member = CreateFrame("Button"); member.GetParent = function() return parent end
  HOOKS.LFGListApplicantMember_OnEnter(member)
  local tl = table.concat(lines, "\n")
  ok(tl:find("Ensemble: ", 1, true) and tl:find("/100", 1, true) and not tl:find("|H", 1, true), "fit added to the Blizzard tooltip")
  nsS2.db.settings.finderTooltip = false; lines = {}
  HOOKS.LFGListApplicantMember_OnEnter(member)
  ok(#lines == 0, "tooltip lines can be switched off")
  LFGListApplicantMember_OnEnter = nil
  PVEFrame:Hide(); RunTimers()
  US:Hide()
  LISTING = nil
  APPLICANTS = { [7] = { { name = "Applicant-Realm", class = "SHAMAN", role = "HEALER", spec = 264, score = 2900 } } }
end

-- 42. Lessons after each key
do
  EnsembleDB = nil
  local nsH2 = boot()
  local Hs = nsH2.History
  local function run(result, gaps, key) return { key = key or "TempleOfSethraliss", result = result, gaps = gaps, deaths = 3 } end
  local poison = { title = "Poison dispel", status = "missing", severity = "medium", source = "Cytotoxin" }
  local lust = { title = "Bloodlust / Heroism", status = "missing", severity = "high" }
  local old1 = run("overtime", { poison })
  local cur = run("overtime", { poison, lust })
  local runs = { cur, old1, run("timed", { poison }) }
  local text, tone = Hs:Lesson(cur, runs)
  ok(tone == "warn" and text:find("Over time with no Bloodlust / Heroism", 1, true) and text:find("Poison dispel (Cytotoxin, medium)", 1, true), "lesson: " .. text)
  local t2 = Hs:Lesson(run("overtime", { poison }), runs)
  ok(t2:find("Also missing in 2 other over-time keys here", 1, true), "lesson spots a repeat pattern: " .. t2)
  local t3, tone3 = Hs:Lesson(run("timed", {}), runs)
  ok(tone3 == "good" and t3:find("nothing missing", 1, true), "timed clean lesson")
  ok(Hs:Lesson(run("timed", { poison }), runs):find("Timed despite no Poison dispel", 1, true), "timed despite a gap")
  ok(Hs:Lesson(run("overtime", {}), runs):find("time went elsewhere", 1, true), "over time with no gaps")
  ok(Hs:Lesson(run("abandoned", { poison }), runs) == nil, "no lesson for abandoned keys")
  nsH2.db.history = { cur, old1 }
  nsH2.UI:Show("history"); RunTimers()
  local t = {} for i = 1, nsH2.UI.hp.runs.used do t[#t + 1] = nsH2.UI.hp.runs.pool[i]:GetText() end
  ok(table.concat(t, "\n"):find("Lesson: Over time with", 1, true), "lesson shown in the run list")
  nsH2.UI:Hide()
end

-- 43. Learning review fixes
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  local nsQ = boot()
  nsQ.db.currentComp = { 0, 0, 0, 0, 0 }
  nsQ:SetManualDungeon("NONE")
  nsQ.UI:Show("builder"); RunTimers()
  local t = nsQ.UI:SpecPreviewText(1, 73)
  ok(t:find("Empty group", 1, true) and not t:find("adds a gap", 1, true) and t:find("Net: +", 1, true), "empty Builder preview shows only what the spec covers")
  -- Verbs: missing -> covers, thin -> shores up
  local A = nsQ.Analysis
  local one = A:Analyze({ { specID = 73 } }, "KingsRest", nsQ.db.settings)
  local two = A:Analyze({ { specID = 73 }, { specID = 72 } }, "KingsRest", nsQ.db.settings)
  local none = A:Analyze({ { specID = 65 } }, "KingsRest", nsQ.db.settings)
  local function has(delta, pat) for _, d in ipairs(delta) do if d.text:find(pat) then return true end end end
  ok(has(A:ScoreDelta(none, A:Analyze({ { specID = 65 }, { specID = 73 } }, "KingsRest", nsQ.db.settings)), "^covers Interrupt"), "missing -> covers")
  ok(has(A:ScoreDelta(one, two), "^shores up Interrupt"), "thin -> shores up")
  -- Lesson repeat counting respects status
  local Hs = nsQ.History
  local thin = { title = "Magic dispel", status = "thin", severity = "critical" }
  local miss = { title = "Magic dispel", status = "missing", severity = "critical" }
  local cur = { key = "KingsRest", result = "overtime", gaps = { thin } }
  local txt = Hs:Lesson(cur, { cur, { key = "KingsRest", result = "overtime", gaps = { miss } }, { key = "KingsRest", result = "overtime", gaps = { thin } } })
  ok(txt:find("Also thin in 1 other", 1, true), "repeat counted only for the same status: " .. txt)
  nsQ.UI:Hide()
end

-- 44. Your fit in Group Finder search results, best key, need filters, chat style, minimap logo
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  local savedPlayer = ROSTER.player
  ROSTER.player = { guid = "P", name = "Me", class = "ROGUE", spec = 259, role = "DAMAGER" }
  local nsF = boot()
  local UDf, LFf, Af = nsF.UD, nsF.ListingFit, nsF.Analysis
  -- Localized spec names -> spec IDs (search results may only give the name)
  local oldGSI = GetSpecializationInfoByID
  GetSpecializationInfoByID = function(id)
    local p = UDf:GetSpec(id)
    if p then return id, "Loc" .. p.name, "", 1, p.role, p.class end
  end
  ok(LFf.SpecFromName("DRUID", "LocBalance") == 102 and LFf.SpecFromName("DRUID", "Nope") == nil, "spec found from its localized name")

  -- Evaluate: Blood DK + Holy Paladin + Balance Druid in Murder Row (needs a soothe); you are an Assassination Rogue.
  local members = { { specID = 250, role = "TANK" }, { specID = 65, role = "HEALER" }, { specID = 102, role = "DAMAGER" } }
  local me = LFf:PlayerMember()
  ok(me and me.specID == 259 and me.isPlayer, "you are read from your own spec")
  local res = LFf:Evaluate(members, "MurderRow", me, nsF.db.settings)
  ok(res.rating and res.score >= 0 and not res.roleConflict, "listing evaluated: " .. tostring(res.rating and res.rating.word) .. " " .. tostring(res.score))
  local function has(list, cap) for _, e in ipairs(list) do if e.cap == cap then return true end end end
  ok(has(res.maybeAdds, "soothe"), "Soothe: you'd add it, but their Druid may have it through a talent")
  ok(not has(res.adds, "soothe"), "an uncertain gap is not listed as a sure add")
  local allLists = 0
  for _, l in ipairs({ res.adds, res.maybeAdds, res.maybe, res.still }) do allLists = allLists + #l end
  ok(allLists > 0, "breakdown has entries")
  -- A healer applying to a group that has one: Poor, no slot
  local healer = { specID = 105, profile = UDf:GetSpec(105), isPlayer = true, role = "HEALER" }
  local r2 = LFf:Evaluate(members, "TempleOfSethraliss", healer, nsF.db.settings)
  ok(r2.roleConflict and r2.rating.key == "poor" and r2.score <= 15, "no open slot for your role is Poor")
  -- Your own talents: a talent you know counts as certain
  local oldIPS = IsPlayerSpell
  IsPlayerSpell = function(id) return id == UDf:SpellID("Soothe") end
  local druid = LFf:PlayerProfile(103)
  local soothe = druid.caps.soothe[1]
  ok(soothe.owned and not soothe.talent, "a talent you have is no longer 'maybe'")
  IsPlayerSpell = function() return false end
  local druid2 = LFf:PlayerProfile(103)
  ok(druid2.caps.soothe and druid2.caps.soothe[1].talent, "a talent you seem to lack stays a talent (never removed)")
  IsPlayerSpell = oldIPS

  -- Reading a search result (stubbed client API)
  local oldInfoTable = C_LFGList.GetActivityInfoTable
  C_LFGList.GetActivityInfoTable = function(id) if id == 9001 then return { mapID = 2813, fullName = "Murder Row" } end return oldInfoTable(id) end
  local RESULTS = {
    [41] = { info = { activityIDs = { 9001 }, numMembers = 3 }, members = {
      { classFilename = "DEATHKNIGHT", specName = "LocBlood", assignedRole = "TANK" },
      { classFilename = "PALADIN", specName = "LocHoly", assignedRole = "HEALER" },
      { classFilename = "DRUID", specName = "LocBalance", assignedRole = "DAMAGER" } } },
    [42] = { info = { activityIDs = { 9001 }, numMembers = 1 }, members = { { classFilename = "MAGE", assignedRole = "DAMAGER" } } },
    [43] = { info = { activityIDs = { 777 }, numMembers = 1 }, members = { { classFilename = "MAGE", specName = "LocFire", assignedRole = "DAMAGER" } } },
  }
  C_LFGList.GetSearchResultInfo = function(id) return RESULTS[id] and RESULTS[id].info end
  C_LFGList.GetSearchResultPlayerInfo = function(id, i) return RESULTS[id] and RESULTS[id].members[i] end
  C_LFGList.GetSearchResults = function() return 3, { 41, 42, 43 } end
  local m41 = LFf:Members(41)
  ok(#m41 == 3 and m41[1].specID == 250 and m41[3].specID == 102, "search result members mapped to spec IDs")
  ok(LFf:Members(42)[1].specID == nil and LFf:Members(42)[1].classFile == "MAGE", "member without a spec keeps its class")
  ok(LFf:DungeonFor(41) == "MurderRow" and LFf:DungeonFor(43) == nil, "listing dungeon from the activity's instance map; non-Season listings ignored")
  ok(LFf:Cached(41) == nil, "nothing cached before the first evaluation")
  local r41 = LFf:ForResult(41)
  ok(r41 and r41.resultID == 41 and LFf:Cached(41) == r41, "result evaluated and cached")
  ok(LFf:ForResult(43) == nil, "no answer for a non-Season listing")
  -- The line for your Sign Up note
  local FSa = nsF.FinderSearch
  C_MythicPlus.GetSeasonBestForMap = function(mapID) if mapID == nsF.Dungeons.CHALLENGE_MAP_IDS.MurderRow then return { level = 13 }, nil end end
  C_ChallengeMode.GetOverallDungeonScore = function() return 2950.4 end
  local line = FSa:ApplyLineText(41)
  ok(line and line:find("2950, timed %+13 here%.") and #line <= FSa.APPLY_MAX, "apply line: spec, rating, best here: " .. tostring(line))
  local dialog = CreateFrame("Frame")
  LFGListApplicationDialog_Show = function() end
  FSa:Hook()
  ok(FSa.applyHooked and HOOKS.LFGListApplicationDialog_Show, "sign up hook attached")
  HOOKS.LFGListApplicationDialog_Show(dialog, 41)
  ok(FSa.applyBox:IsShown() and FSa.applyBox.box:GetText() == line, "line shown under the dialog")
  FSa.applyBox.box._scripts.OnTextChanged(FSa.applyBox.box, true)
  ok(FSa.applyBox.box:GetText() == line, "read-only: typing restores the line")
  nsF.db.settings.applyLine = false
  HOOKS.LFGListApplicationDialog_Show(dialog, 41)
  ok(not FSa.applyBox:IsShown(), "setting off: no line")
  nsF.db.settings.applyLine = true
  HOOKS.LFGListApplicationDialog_Show(dialog, 43)
  ok(not FSa.applyBox:IsShown(), "non-Season listing: no line")
  -- Issue #4: another addon replaces LFGListApplicationDialog_Show after our hook, so the
  -- function hook never fires. The dialog's OnShow hook still shows the line, from the
  -- dialog's own resultID, else the search panel's selected result.
  local realDialog = CreateFrame("Frame", "LFGListApplicationDialog"); realDialog:Hide()
  FSa.dialogHooked = nil
  FSa:Hook()
  ok(FSa.dialogHooked, "sign up: the dialog's OnShow is hooked")
  FSa.applyBox:Hide()
  realDialog.resultID = 41
  realDialog:Show()   -- the replacing addon's own show: only OnShow reaches us
  ok(FSa.applyBox:IsShown() and FSa.applyBox.box:GetText() == line, "sign up: OnShow shows the line with the dialog's resultID")
  realDialog:Hide(); FSa.applyBox:Hide()
  realDialog.resultID = nil
  LFGListFrame = { SearchPanel = { selectedResult = 41 } }
  realDialog:Show()
  ok(FSa.applyBox:IsShown() and FSa.applyBox.box:GetText() == line, "sign up: falls back to the search panel's selected result")
  realDialog:Hide(); FSa.applyBox:Hide()
  LFGListFrame = nil
  realDialog:Show()
  ok(not FSa.applyBox:IsShown(), "sign up: no listing known, no line (and no error)")
  realDialog:Hide()
  local hookAgain = realDialog._scripts.OnShow
  FSa:Hook()
  ok(realDialog._scripts.OnShow == hookAgain, "sign up: OnShow is hooked once")
  -- /ens verify: issecurevariable on the three hooked globals names the addon that replaced one.
  LFGListSearchEntry_Update = function() end
  LFGListUtil_SetSearchEntryTooltip = function() end
  issecurevariable = function(name)
    if name == "LFGListApplicationDialog_Show" or name == "LFGListSearchEntry_Update" then return false, "EllesmereUIQoL" end
    return true
  end
  local vt = nsF.Verify:Build()
  ok(vt:find("[WARN] LFGListApplicationDialog_Show was replaced by EllesmereUIQoL (affects the Sign Up note line). The Sign Up line uses the dialog's OnShow instead, so it still works.", 1, true),
    "verify: a replaced Sign Up function names the addon and says the line still works")
  ok(vt:find("[WARN] LFGListSearchEntry_Update was replaced by EllesmereUIQoL (affects listing markers in search results). Listing markers in search results may not appear while it's loaded.", 1, true),
    "verify: a replaced row function names the addon and the feature affected")
  ok(vt:find("[OK] LFGListUtil_SetSearchEntryTooltip is Blizzard's own", 1, true), "verify: an untouched hooked function is OK")
  issecurevariable = nil
  vt = nsF.Verify:Build()
  ok(vt:find("issecurevariable missing", 1, true), "verify: a missing issecurevariable is a WARN, not an error")
  LFGListApplicationDialog = nil
  LFGListSearchEntry_Update, LFGListUtil_SetSearchEntryTooltip = nil, nil
  C_MythicPlus.GetSeasonBestForMap, C_ChallengeMode.GetOverallDungeonScore, LFGListApplicationDialog_Show = nil, nil, nil

  -- Markers on Blizzard's rows (styles) and the tooltip
  local FSf = nsF.FinderSearch
  LFGListSearchEntry_Update = function() end
  LFGListUtil_SetSearchEntryTooltip = function() end
  FSf:Hook()
  ok(FSf.rowsHooked and FSf.tipHooked and HOOKS.LFGListSearchEntry_Update and HOOKS.LFGListUtil_SetSearchEntryTooltip, "row and tooltip hooks attached")
  local hookedOnce = HOOKS.LFGListSearchEntry_Update
  FSf:Hook()
  ok(HOOKS.LFGListSearchEntry_Update == hookedOnce, "hooks are not attached twice")
  local row = CreateFrame("Button", nil, UIParent); row.resultID = 41
  function row:GetHeight() return 36 end
  HOOKS.LFGListSearchEntry_Update(row); RunTimers()
  local mk = FSf:MarkerFor(row)
  ok(rawget(row, "cmMarker") == nil, "no field written onto the Blizzard result button")
  ok(mk and mk.segs[1] and mk.segs[1]:IsShown() and rawget(mk, "badge") == nil, "edge stripe is the listing marker (no badges)")
  nsF.db.settings.listingMarker = "off"; FSf:UpdateButton(row)
  ok(not mk.segs[1]:IsShown() and not mk.tint:IsShown(), "marker off hides everything")
  nsF.db.settings.listingMarker = "stripe"; nsF.db.settings.listingHidePoor = true
  local pr = CreateFrame("Button", nil, UIParent); pr.resultID = 41
  function pr:GetHeight() return 36 end
  local savedRating = r41.rating
  r41.rating = nsF.ApplicantFit.RATINGS.poor
  FSf:UpdateButton(pr)
  ok(not (FSf:MarkerFor(pr) and FSf:MarkerFor(pr).segs[1] and FSf:MarkerFor(pr).segs[1]:IsShown()), "Poor fits can be left unmarked")
  r41.rating = savedRating; nsF.db.settings.listingHidePoor = false
  local lines = {}
  local tip = { AddLine = function(_, t) lines[#lines + 1] = t end, Show = function() end }
  HOOKS.LFGListUtil_SetSearchEntryTooltip(tip, 41)
  local all = table.concat(lines, "\n")
  ok(all:find("your fit", 1, true) and all:find("may already have it", 1, true) and all:find("talents can't be seen", 1, true) and not all:find("affixes", 1, true), "tooltip shows your fit and uncertainty, no affix note")
  ok(all:find("Group after you: ", 1, true) and not all:find("Still missing after you", 1, true), "tooltip: Group after you replaces Still missing after you")
  nsF.db.settings.listingTooltip = false
  lines = {}; FSf:AddTooltip(tip, 41)
  ok(#lines == 0, "tooltip lines can be turned off")
  nsF.db.settings.listingTooltip = true
  C_LFGList.GetActivityInfoTable = oldInfoTable

  -- Best key for this group
  local ranked = Af:RankDungeons(members, nsF.db.settings)
  ok(#ranked == #nsF.Dungeons.order, "every Season dungeon ranked")
  local sorted = true
  for i = 2, #ranked do if ranked[i].penalty + 0.01 < ranked[i - 1].penalty then sorted = false end end
  ok(sorted, "best key list sorted best first")
  nsF.db.currentComp = { 250, 65, 102, 0, 0 }
  nsF:SetManualDungeon("AUTO")
  nsF.UI:Show("builder"); RunTimers()
  nsF.UI:ShowBestKey()
  ok(nsF.UI.bestKey and nsF.UI.bestKey:IsShown() and nsF.UI.bestKey.list.used > 8, "best key popup lists the dungeons")
  nsF.UI.cp.bestKeyBtn:Click()
  ok(nsF.UI.bestKey:IsShown(), "the Best key button opens it")

  -- Needs that matter: ignoring a need removes it everywhere
  local base = Af:Analyze({ { specID = 250 } }, "TempleOfSethraliss", nsF.db.settings)
  local function itemFor(r, need) for _, it in ipairs(r.dungeon.items) do if it.req.need == need then return it end end end
  ok(itemFor(base, "dispel_poison") ~= nil, "poison requirement present by default")
  nsF.db.settings.ignoredNeeds = { dispel_poison = true }
  local ign = Af:Analyze({ { specID = 250 } }, "TempleOfSethraliss", nsF.db.settings)
  ok(itemFor(ign, "dispel_poison") == nil and Af:Readiness(ign, nsF.db.settings).rows.dispel_poison == nil, "ignored need left out of checks and readiness")
  ok(Af:Penalty(ign) < Af:Penalty(base), "ignored need no longer costs points")
  nsF.db.settings.ignoredNeeds = { interrupt = true }
  local ki = Af:Analyze({ { specID = 65 } }, "TempleOfSethraliss", nsF.db.settings)
  local agg = false
  for _, it in ipairs(ki.dungeon.items) do if it.aggregate or it.req.need == "interrupt" then agg = true end end
  ok(not agg, "ignoring interrupts drops the kick count check too")
  nsF.db.settings.ignoredNeeds = {}
  nsF.db.settings.hideLowSeverity = true
  local lowLeft = false
  for _, it in ipairs(Af:Analyze({ { specID = 250 } }, "TempleOfSethraliss", nsF.db.settings).dungeon.items) do
    if it.req.severity == "low" then lowLeft = true end
  end
  ok(not lowLeft, "low-severity requirements hidden")
  nsF.db.settings.hideLowSeverity = false

  -- Party chat style
  local rr = Af:Analyze({ { specID = 250 } }, "TempleOfSethraliss", nsF.db.settings)
  local full = nsF.UI:GapsMessage(rr)
  nsF.db.settings.chatStyle = "short"
  local short = nsF.UI:GapsMessage(rr)
  ok(full:find("Cytotoxin", 1, true) and short:find("^%[Ensemble%]") and not short:find("Cytotoxin", 1, true), "short gaps post drops the casts")
  local plan = nsF.Assignments:Build(Af:Analyze({ { specID = 250 }, { specID = 65 }, { specID = 259 }, { specID = 62 } }, "TempleOfSethraliss", nsF.db.settings))
  local sl = nsF.Assignments:ChatLines(plan, "Temple", "short")
  local fl = nsF.Assignments:ChatLines(plan, "Temple", "full")
  ok(#sl == #fl and #sl >= 3, "short and full posts both give every player a line")
  local slt = table.concat(sl, "\n", 2)
  ok(not slt:find("Backup", 1, true) and not slt:find("[", 1, true) and table.concat(fl, "\n", 2):find("[", 1, true), "short drops mobs and backups")
  -- Healers kick less: a Resto Shaman (12s Wind Shear) no longer carries the most kicks
  local tp = nsF.Assignments:Build(Af:Analyze({ { specID = 581 }, { specID = 264 }, { specID = 63 }, { specID = 70 }, { specID = 102 } }, "TempleOfSethraliss", nsF.db.settings))
  local kc = {}
  for _, row in ipairs(tp.kicks) do for _, k in ipairs(row.kickers) do kc[k.index] = (kc[k.index] or 0) + 1 end end
  ok((kc[2] or 0) < math.max(kc[1] or 0, kc[4] or 0), "healer takes fewer kicks than the tank or melee (" .. tostring(kc[2]) .. ")")
  -- Defensive alternatives are a group note, not one player's job
  local mr = nsF.Assignments:Build(Af:Analyze({ { specID = 73 }, { specID = 257 }, { specID = 253 }, { specID = 265 }, { specID = 258 } }, "MurderRow", nsF.db.settings))
  local mrl = table.concat(nsF.Assignments:ChatLines(mr, "Murder Row", "full"), "\n")
  ok(mrl:find("Nobody can remove", 1, true) and mrl:find("Bleed", 1, true), "no-dispel needs become a group line")
  -- The group line names the defensives the group has (as the sheet's note does); they're
  -- still not one player's job.
  local defLine, curseLine, playerHasDef
  for _, l in ipairs(nsF.Assignments:ChatLines(mr, "Murder Row", "full")) do
    if l:find("^Nobody can remove") then
      if l:find("Guardian Spirit", 1, true) then defLine = l else curseLine = l end
    elseif l:find("Guardian Spirit", 1, true) then playerHasDef = true end
  end
  ok(defLine and defLine:find("Bleed (Cutpurse)", 1, true) and defLine:find(": use defensives (", 1, true) and not playerHasDef,
    "defensives named in the group line, not as a job: " .. tostring(defLine))
  ok(curseLine == "Nobody can remove Curse (Curse of Doom), and nobody has a defensive for it.",
    "a cast with no defensive gets its own line: " .. tostring(curseLine))
  -- With no defensive for it, the line says so instead of "use defensives".
  local saved = {}
  for i, row in ipairs(mr.dispels) do saved[i] = row.defensives; row.defensives = nil end
  local noDef
  for _, l in ipairs(nsF.Assignments:ChatLines(mr, "Murder Row", "full")) do if l:find("^Nobody can remove") then noDef = l end end
  ok(noDef and not noDef:find("use defensives", 1, true) and noDef:find("Bleed (Cutpurse), Curse (Curse of Doom)", 1, true)
    and noDef:find("nobody has a defensive for them.", 1, true),
    "no defensive in the group: said plainly: " .. tostring(noDef))
  for i, row in ipairs(mr.dispels) do row.defensives = saved[i] end
  ok(nsF.Assignments:Priority(mr) ~= nil and mrl:find("Kick first if two cast at once:", 1, true), "priority line")
  ok(nsF.Assignments.MobName({ source = "Lightning Bolt (Storm Adept, Imbued Stormcaller)" }) == "Storm Adept"
    and nsF.Assignments.MobName({ source = "Mirror Images (boss; five spawn)" }) == nil
    and nsF.Assignments.MobName({ source = "Seduction (Seductive Sayaad channel on a random player)" }) == "Seductive Sayaad", "mob names from sources")
  nsF.db.settings.chatStyle = "full"

  -- Settings window: sections, gear shortcuts, presets, reset per section
  nsF.UI:Show("settings"); RunTimers()
  local U = nsF.UI
  ok(U.settingsFrames.general:IsShown() and not U.settingsFrames.finder:IsShown(), "settings open on General")
  for _, sec in ipairs(U.SETTINGS_SECTIONS) do
    U:ShowSettingsSection(sec.key)
    ok(U.settingsFrames[sec.key]:IsShown() and U.settingsNav[sec.key].mark:IsShown(), "section " .. sec.key .. " shows")
  end
  U:Show("builder"); RunTimers()
  U:OpenSettings("chat")
  ok(U.currentTab == "settings" or U.pages.settings:IsShown(), "gear opens the settings tab")
  ok(U.settingsFrames.chat:IsShown(), "gear jumps to its section")
  U:ApplySettingsPreset("expert")
  local st = nsF.db.settings
  ok(st.explain == false and st.compact == true and st.chatStyle == "short" and st.applicantView.hidePoor == true, "Expert preset applied")
  ok(U:CurrentSettingsPreset() == "expert", "current preset recognized")
  U:ApplySettingsPreset("learning")
  ok(st.explain == true and st.compact == false and st.chatStyle == "full" and U:CurrentSettingsPreset() == "learning", "Learning preset applied")
  st.chatStyle = "short"
  ok(U:CurrentSettingsPreset() == nil, "a changed setting reads as your own mix")
  U:ResetSettingsSection("chat")
  ok(st.chatStyle == "full", "reset section restores its defaults")
  st.ignoredNeeds = { soothe = true }; st.listingMarker = "stripe"
  U:ResetSettingsSection("checks")
  ok(next(st.ignoredNeeds) == nil and st.listingMarker == "stripe", "reset only touches its own section")
  U:ResetSettingsSection("finder")
  ok(st.listingMarker == "stripe", "finder section reset")
  -- What to check: a group's switch covers all of its needs
  U:ShowSettingsSection("checks")
  local head
  for _, c in ipairs(U.checks) do
    if rawget(c, "tip") == "Turn every need in this group on or off." then head = c; break end
  end
  ok(head ~= nil, "group switches exist")
  head:GetScript("OnClick")(head); RunTimers()
  local off = 0
  for _ in pairs(st.ignoredNeeds) do off = off + 1 end
  ok(off >= 3, "group switch turns all of its needs off (" .. off .. ")")
  head:GetScript("OnClick")(head); RunTimers()
  ok(next(st.ignoredNeeds) == nil, "and back on")
  ok(U.checksGear ~= nil or (U.cp and U.cp.checksGear ~= nil), "gear next to Readiness")

  -- Minimap button uses the logo
  ok(nsF.UI.minimapButton ~= nil and nsF.UI.LOGO:find("LogoMark", 1, true), "minimap button built with the addon logo")

  -- Key level from listing titles
  local P = LFf.ParseLevel
  ok(P("+15 timing") == 15 and P("TSE + 12 chill") == 12 and P("+12-14 KR") == 12, "level from +N")
  ok(P("15 TSE no leavers") == 15 and P("key 9 please") == 9 and P("lvl 11") == 11, "level from other common forms")
  ok(P("+2k rio only") == nil and P("2.8k io, chill") == nil and P("3k io") == nil, "ratings are not mistaken for levels")
  ok(LFf:LevelFromTitle({ name = "+16 weekly" }) == 16 and LFf:LevelFromTitle({ name = "come chill" }) == nil, "title read")
  issecretvalue = function() return true end
  local lv, why = LFf:LevelFromTitle({ name = "+16" })
  ok(lv == nil and why == "protected", "protected titles are not read")
  issecretvalue = nil
  local lvE, whyE = LFf:LevelFromTitle({ name = "|Kq1234|k" })
  ok(lvE == nil and whyE == "encoded", "encoded (|K) titles are recognized, not parsed")
  local lvl, src = LFf:LevelFor({ name = "+14 TSE" })
  ok(lvl == 14 and src == "title", "listing level from title")
  lvl, src = LFf:LevelFor({ name = "chill" })
  ok(lvl == nil and src == "none", "no level guessed when the title doesn't say")
  ok(r41.level == nil and r41.levelSource == "none", "untitled listing evaluated without a key level")
  local aNo = Af:Analyze(members, "MurderRow", nsF.db.settings, { noAffixes = true })
  local aLv = Af:Analyze(members, "MurderRow", nsF.db.settings, { keyLevel = 12 })
  ok(aNo.dungeon.affixLevel == nil and aLv.dungeon.affixLevel == 12, "noAffixes leaves this week's affixes out of the check")
  local aDef = Af:Analyze(members, "MurderRow", nsF.db.settings)
  ok(aDef.dungeon.affixLevel ~= nil, "Builder/Live checks still count affixes")
  RESULTS[41].info.name = "+12 Murder Row"
  LFf:ClearCache()
  local r12 = LFf:ForResult(41)
  ok(r12.level == 12 and r12.levelSource == "title", "listing evaluated at the title's level")
  lines = {}; HOOKS.LFGListUtil_SetSearchEntryTooltip(tip, 41)
  ok(table.concat(lines, "\n"):find("+12 (from the listing title)", 1, true), "tooltip names the level's source")


  -- Bloodlust is assumed whenever a member's spec can bring it (even a pet or talent)
  local gp = LFf.GroupProfile(253)
  local pr8 = gp.caps.bloodlust[1]
  ok(pr8 and not pr8.pet and not pr8.conditional and pr8.assumed, "a Beast Mastery hunter's Primal Rage counts as certain in listing fit")
  ok(UDf:GetSpec(253).caps.bloodlust[1].pet, "the Builder's data is untouched")
  local bm = { { specID = 253, profile = gp, role = "DAMAGER" } }
  local hr = LFf:Evaluate(bm, "MurderRow", { specID = 262, profile = LFf:PlayerProfile(262), isPlayer = true, role = "DAMAGER" }, nsF.db.settings)
  local function inList(l, cap) for _, e in ipairs(l) do if e.cap == cap then return true end end end
  ok(not inList(hr.adds, "bloodlust") and not inList(hr.maybeAdds, "bloodlust") and not inList(hr.maybe, "bloodlust"), "a shaman joining a hunter's group doesn't 'add' or 'maybe' Bloodlust")
  nsF.UI:Hide()
  GetSpecializationInfoByID = oldGSI
  ROSTER.player = savedPlayer
  C_LFGList.GetSearchResultInfo, C_LFGList.GetSearchResultPlayerInfo, C_LFGList.GetSearchResults = nil, nil, nil
  LFGListSearchEntry_Update, LFGListUtil_SetSearchEntryTooltip = nil, nil
end

-- 45. The Blizzard Options entry
do
  EnsembleDB = {}
  local registered = {}
  Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) registered.name = name; return { name = name } end,
    RegisterAddOnCategory = function(cat) registered.cat = cat end,
  }
  local nsM = boot()
  ok(registered.name == "Ensemble" and registered.cat ~= nil and nsM.UI.blizzCategory ~= nil, "entry in Blizzard's Options > AddOns")
  Settings = nil
end

-- 46. /ens report and the error log
do
  local prevCalls, handler = 0, nil
  local prev = function() prevCalls = prevCalls + 1 end
  geterrorhandler = function() return handler or prev end
  seterrorhandler = function(h) handler = h end
  local nextStack = ""
  debugstack = function() return nextStack end
  ROSTER = { player = { guid = "P", name = "Secretname", class = "WARRIOR", spec = 73, role = "TANK" } }
  local nsP = boot()
  local R = nsP.Report
  ok(R and R.captureActive and handler ~= nil, "error capture chained onto the game's handler")
  nextStack = "Interface/AddOns/Ensemble/UI.lua:120: in function 'Refresh'\n[C]: ?"
  handler("Interface/AddOns/Ensemble/UI.lua:120: attempt to index nil")
  nextStack = "Interface/AddOns/OtherAddon/x.lua:5: in function 'Foo'"
  handler("Interface/AddOns/OtherAddon/x.lua:5: not ours")
  nextStack = "Interface/AddOns/Ensemble/UI.lua:120: in function 'Refresh'\n[C]: ?"
  handler("Interface/AddOns/Ensemble/UI.lua:120: attempt to index nil")
  ok(prevCalls == 3, "every error still reaches the previous handler")
  local errs = nsP.db.errors
  ok(#errs == 1 and errs[1].count == 2 and errs[1].version, "only this addon's errors are logged, repeats counted")
  nsP.db.settings.chatStyle = "short"; nsP.db.settings.ignoredNeeds = { soothe = true }
  nsP.db.settings.window.x = 55
  nsP.db.currentComp = { 73, 257, 0, 0, 0 }
  local changed = table.concat(R:ChangedSettings(), " ")
  ok(changed:find("chatStyle=short", 1, true) and changed:find("ignoredNeeds={soothe}", 1, true) and not changed:find("window.x", 1, true),
    "changed settings listed, window position left out: " .. changed)
  BugGrabber = { GetDB = function() return { { message = "Interface/AddOns/Ensemble/Report.lua:9: from bug grabber", counter = 3 },
    { message = "Interface/AddOns/Else/a.lua:1: other" } } end }
  local text = R:Build()
  BugGrabber = nil
  ok(text:find("=== Ensemble bug report ===", 1, true) and text:find("What happened:", 1, true), "report starts with the questions")
  ok(text:find("Addon ", 1, true) and text:find("Planner slots: Protection Warrior, Holy Priest, empty", 1, true), "version line and Planner slots")
  ok(text:find("attempt to index nil", 1, true) and text:find("[x2", 1, true) and text:find("UI.lua:120", 1, true), "logged error with count and stack line")
  ok(text:find("from bug grabber", 1, true) ~= nil and not text:find("Else/a.lua", 1, true), "only this addon's BugGrabber errors")
  ok(text:find("Verify: ", 1, true) and text:find("=== end of report ===", 1, true), "verify summary included")
  ok(not text:find("Secretname", 1, true), "no player names in the report")
  ok(text:find("Settings changed from defaults: ", 1, true) and text:find("chatStyle=short", 1, true), "settings in the report")
  SlashCmdList.ENSEMBLE("report")
  ok(nsP.Verify.frame and nsP.Verify.frame:IsShown() and nsP.Verify.frame.report:find("bug report", 1, true), "/ens report opens the copy window")
  ok(nsP.db.lastReport ~= nil, "last report kept in SavedVariables")
  R:ClearErrors()
  ok(R:Build():find("none recorded", 1, true), "empty log reads 'none recorded'")
  -- A client that refuses the handler change: nothing breaks
  seterrorhandler = function() error("blocked") end
  handler = nil
  local nsQ = boot()
  ok(nsQ.Report.captureActive == false and nsQ.Report:Build():find("capture not active", 1, true), "refused handler: report still works")
  -- Issue #8: with BugGrabber owning the handler, the empty error line says so.
  BugGrabber = { GetDB = function() return { { message = "Interface/AddOns/Else/a.lua:1: other" } } end }
  local bgText = nsQ.Report:Build()
  BugGrabber = nil
  ok(bgText:find("Lua errors from this addon: none recorded (BugGrabber is catching errors; none from this addon)", 1, true)
    and not bgText:find("capture not active", 1, true), "BugGrabber present: the error line says it is catching errors")
  geterrorhandler, seterrorhandler, debugstack = nil, nil, nil
end

-- 47. Boss cards: data, edits, jobs, chat, boss tracking and the window
do
  ROSTER = { player = { guid = "P", name = "Me", class = "SHAMAN", spec = 262, role = "DAMAGER" } }
  local nsB = boot()
  local BC, BD, BW, DDb = nsB.BossCards, nsB.BossData, nsB.BossWindow, nsB.Dungeons
  -- Data
  local total, badReq, longLine, badRole, nameMismatch = 0, {}, {}, 0, {}
  local reqIds = {}
  for _, key in ipairs(DDb.order) do for _, q in ipairs(DDb.list[key].requirements) do reqIds[q.id] = true end end
  local ROLES = { ALL = true, TANK = true, HEAL = true, DPS = true }
  for _, key in ipairs(DDb.order) do
    local cards = BD.list[key] or {}
    total = total + #cards
    for i, b in ipairs(cards) do
      if DDb.list[key].bosses[i] ~= b.name then nameMismatch[#nameMismatch + 1] = b.name end
      for _, id in ipairs(b.reqs) do if not reqIds[id] then badReq[#badReq + 1] = id end end
      for _, l in ipairs(b.lines) do
        if #l.text > 95 then longLine[#longLine + 1] = l.text end
        if not ROLES[l.role] then badRole = badRole + 1 end
      end
    end
  end
  ok(total == 28, "a card for every boss in all 8 dungeons (" .. total .. ")")
  ok(#nameMismatch == 0, "card names match the dungeon boss lists: " .. table.concat(nameMismatch, ", "))
  ok(#badReq == 0, "linked requirements exist: " .. table.concat(badReq, ", "))
  ok(#longLine == 0 and badRole == 0, "lines short enough for chat, roles valid: " .. table.concat(longLine, " / "))
  -- Parse / serialize
  local parsed = BC:Parse("TANK: face away\nHealer: dispel it\nno prefix here\n\n  dps : kick it  ")
  ok(#parsed == 4 and parsed[1].role == "TANK" and parsed[2].role == "HEAL" and parsed[3].role == "ALL" and parsed[4].role == "DPS"
    and parsed[4].text == "kick it", "notes parse with role prefixes; unknown lines count as ALL")
  ok(BC:Serialize(parsed):find("^TANK: face away\nHEAL: dispel it"), "notes serialize back to ROLE: lines")
  -- Edits
  BC:SetEdit("AltarOfFangs", 1, "ALL: my own note\nTANK: my tank note")
  local lines, edited, changed = BC:Lines("AltarOfFangs", 1)
  ok(edited and not changed and #lines == 2 and lines[1].text == "my own note", "an edit replaces the card")
  nsB.db.bossNotes.AltarOfFangs["Rav'i"].base = "ALL: an older default"
  local _, _, changed2 = BC:Lines("AltarOfFangs", 1)
  ok(changed2, "a changed built-in card is noticed")
  BC:Reset("AltarOfFangs", 1)
  ok(not BC:IsEdited("AltarOfFangs", 1), "reset goes back to the built-in card")
  BC:SetEdit("AltarOfFangs", 1, BC:DefaultText("AltarOfFangs", 1))
  ok(not BC:IsEdited("AltarOfFangs", 1), "saving the default unchanged stores nothing")
  -- Order by role
  local ord = BC:Ordered(BD.list.AltarOfFangs[1].lines, "HEAL", false)
  ok(ord[1].role == "HEAL" and ord[#ord].role == "ALL", "your role first, then everyone's")
  local hasTank = false
  for _, l in ipairs(ord) do if l.role == "TANK" then hasTank = true end end
  ok(not hasTank and #BC:Ordered(BD.list.AltarOfFangs[1].lines, "HEAL", true) == #BD.list.AltarOfFangs[1].lines, "other roles only when showing all")
  ok(BC:MyRole() == "DPS", "your role from your spec")
  -- Jobs from the plan (solo Elemental Shaman: the only kicker)
  local plan, r = BC:Plan("AltarOfFangs")
  local jobs = BC:Jobs("AltarOfFangs", 2, plan, r)
  ok(jobs[1] and jobs[1].text:find("Kick Toxic Atrophy", 1, true) and jobs[1].text:find("Wind Shear", 1, true), "your job on this boss: " .. tostring(jobs[1] and jobs[1].text))
  ok(#BC:Jobs("AltarOfFangs", 3, plan, r) == 0, "no job lines where the boss has no linked casts")
  -- Chat
  local cl = BC:ChatLines("AltarOfFangs", 1)
  ok(cl[1]:find("^%[Ensemble%] Rav'i %- ALL: ") and cl[2]:find("^TANK: ") and cl[3]:find("^HEAL: ") and cl[4]:find("^DPS: "), "one chat line per role, ALL first")
  for _, l in ipairs(cl) do ok(#l <= 250 and not l:find("|", 1, true), "boss chat line plain and short (" .. #l .. ")") end
  -- Tracking
  ok(BC:Enter("AltarOfFangs") and BC.state.index == 1, "entering starts at the first boss")
  BC:OnEncounterStart(0, "The Writhing Coil")
  ok(BC.state.index == 2, "pulling a boss turns to its card")
  BC:OnEncounterEnd(0, "The Writhing Coil", 23, 5, 0)
  ok(not BC.state.killed[2], "a wipe doesn't count as a kill")
  BC:OnEncounterEnd(0, "Rav'i", 23, 5, 1)
  ok(BC.state.killed[1] and BC.state.index == 2, "a kill turns to the next boss alive")
  BC:OnEncounterEnd(0, "The Writhing Coil", 23, 5, 1)
  ok(BC.state.index == 3 and nsB.db.bossProgress.killed[2], "progress saved for a /reload")
  BC:Leave(); BC:Enter("AltarOfFangs")
  ok(BC.state.killed[1] and BC.state.killed[2] and BC.state.index == 3, "re-entering restores progress")
  BC:NewRun()
  ok(next(BC.state.killed) == nil and BC.state.index == 1, "a new key starts over")
  ok(BC:IndexForEncounter("RubyLifePools", 0, "Kyrakka") == 3, "partial encounter names match (Kyrakka)")
  -- Window: auto-open, job highlight, font size, roles, fade, post
  BC:Leave()
  local realCur = nsB.CurrentInstanceDungeon
  nsB.CurrentInstanceDungeon = function() return "AltarOfFangs" end
  BC:CheckZone(); RunTimers()
  ok(BW:IsShown(), "window opens on entering a Season dungeon")
  BC:Show(2); RunTimers()
  ok(BW.title:GetText():find("The Writhing Coil", 1, true) and BW.title:GetText():find("2/3", 1, true), "title shows the boss and page")
  ok(BW.items[1] and BW.items[1].job and BW.items[1].tag:find("YOU", 1, true), "your assignment comes first, tagged YOU")
  ok(BW.rows[1].bar:IsShown() and BW.rows[1].edge:IsShown() and not BW.rows[2].bar:IsShown(), "job lines highlighted, notes not")
  local mine = #BW.items
  nsB.db.settings.bossWindow.showAll = true; BW:Refresh()
  ok(#BW.items > mine, "show all roles adds the other roles' notes")
  BW:SetFontSize(99); ok(nsB.db.settings.bossWindow.fontSize == BW.FONT_MAX, "text size capped")
  BW:SetFontSize(1); ok(nsB.db.settings.bossWindow.fontSize == BW.FONT_MIN, "text size floor")
  BW:SetFontSize(14)
  nsB:Fire("BOSS_COMBAT", true); ok(BW.frame:GetAlpha() < 1, "fades in combat")
  nsB:Fire("BOSS_COMBAT", false); ok(BW.frame:GetAlpha() == 1, "back after combat")
  BW:Step(1); ok(BC.state.index == 3, "arrows turn the page")
  ROSTER.party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" }
  SENT = {}; BW:Post(); RunTimers(); RunTimers(); RunTimers(); RunTimers(); RunTimers()
  ok(#SENT >= 3 and SENT[1].msg:find("^%[Ensemble%] Zul'jan %- ALL:") and SENT[1].channel == "PARTY", "post sends the card to party chat")
  C_ChatInfo = { InChatMessagingLockdown = function() return true end }
  SENT = {}; BW:Post(); RunTimers()
  ok(#SENT == 0 and nsB.Verify.frame and nsB.Verify.frame:IsShown() and nsB.Verify.frame.report:find("Zul'jan", 1, true), "chat blocked: opens the copy window instead")
  C_ChatInfo = nil
  ROSTER.party1 = nil
  BW:Hide(true)
  nsB.db.settings.bossWindow.autoOpen = false
  BC:Leave(); BC:CheckZone(); RunTimers()
  ok(not BW:IsShown(), "auto-open can be turned off")
  nsB.CurrentInstanceDungeon = realCur
  BC:CheckZone()
  -- Slash and editor
  BW:Open("RubyLifePools")
  ok(BW:IsShown() and BW.title:GetText():find("Melidrussa", 1, true), "the boss window opens on a given dungeon's cards")
  nsB.UI:OpenBossEditor("RubyLifePools", 1)
  local ed = nsB.UI.bossEditor
  ok(ed and ed:IsShown() and ed.edit:GetText():find("^ALL: "), "editor opens with the card's text")
  ed.edit:SetText("TANK: my note"); ed.save:Click(); RunTimers()   -- the window redraws next frame (1.5.0, C3)
  ok(BC:IsEdited("RubyLifePools", 1) and BW.title:GetText():find("(edited)", 1, true), "editor saves; the window marks it edited")
  BC:Reset("RubyLifePools", 1)
  -- Dungeons tab
  nsB.UI:Show("dungeons"); nsB.UI:SetPrimerPick("TempleOfSethraliss"); nsB.UI:RefreshPrimer(); RunTimers()
  local pt = {}
  local L = nsB.UI.pp.asks
  for i = 1, L.used do pt[#pt + 1] = L.pool[i]:GetText() end
  local ptxt = table.concat(pt, "\n")
  ok(ptxt:find("ADDERIS AND ASPIX", 1, true) and ptxt:find("> Edit card", 1, true), "boss cards in the Dungeon walkthrough")
  local t1 = ptxt:find("TRASH BEFORE ADDERIS AND ASPIX", 1, true)
  local b1 = ptxt:find("1. ADDERIS AND ASPIX", 1, true)
  local t2 = ptxt:find("TRASH BEFORE MEREKTHA", 1, true)
  local b4 = ptxt:find("4. AVATAR OF SETHRALISS", 1, true)
  ok(t1 and b1 and t2 and b4 and t1 < b1 and b1 < t2 and t2 < b4, "trash, then its boss, in dungeon order")
  nsB.UI:Hide(); BW:Hide()
end

-- 48. Slash command and share-string prefix
do
  EnsembleDB = nil
  local nsR = boot()
  ok(SLASH_ENSEMBLE1 == "/ens" and SLASH_ENSEMBLE2 == nil, "/ens only")
  ok(nsR.Share.Encode("New", { 73, 257, 0, 0, 0 }, "KingsRest"):find("^ENS1:"), "share strings are ENS1")
  ok(nsR.Share.Decode("XX1:a:NONE:0,0,0,0,0:1") == nil, "other prefixes rejected")
end

-- 49. Ability links on boss cards (encounter journal)
do
  -- Like the client (issue #10): EJ_GetInstanceForMap takes a UI map ID, so an instance map ID
  -- gives 0; GetInstanceForGameMap takes the instance map ID (2993 -> 1322, in game).
  EJ_GetInstanceForMap = function(map) return 0 end
  EJ_GetEncounterInfoByIndex = function(n, jid)
    if jid ~= 1322 then return nil end
    local bosses = { { "Rav'i", 10 }, { "The Writhing Coil", 20 }, { "Zul'jan", 30 } }
    local b = bosses[n]; if not b then return nil end
    return b[1], "", 9000 + n, b[2]
  end
  local SECTIONS = {
    [10] = { title = "Hydrastrike", spellID = 1111, firstChildSectionID = 11 },
    [11] = { title = "Triple Shot", spellID = 2222, siblingSectionID = 12 },
    [12] = { title = "Overview", spellID = 0 },
    [20] = { title = "Death Rattle", spellID = 3333 },
    [30] = { title = "Boneslicer", spellID = 4444 },
  }
  C_EncounterJournal = { GetSectionInfo = function(id) return SECTIONS[id] end,
    GetInstanceForGameMap = function(map) return map == 2993 and 1322 or 0 end }
  EnsembleDB = nil
  local nsL2 = boot()
  local BC2 = nsL2.BossCards
  local js = BC2:JournalSpells("AltarOfFangs")
  ok(js.Hydrastrike and js.Hydrastrike.id == 1111 and js["Death Rattle"] and not js.Overview, "boss abilities read from the journal (sections without a spell skipped)")
  local line = BC2:Decorate("AltarOfFangs", "Defensive for Hydrastrike.")
  ok(line:find("|Haddon:Ensemble:e:1111:boss:Hydrastrike|h", 1, true), "journal abilities become links: " .. line)
  local both = BC2:Decorate("AltarOfFangs", "Kick all three Toxic Atrophy casts in a row.")
  ok(both:find(":interrupt:Toxic Atrophy|h", 1, true), "dungeon-data abilities keep their own type")
  ok(not BC2:Decorate("AltarOfFangs", "Dispel it (Hydrastrike)."):find("|H", 1, true), "text in brackets is never linked")
  local bw = nsL2.BossWindow
  nsL2.db.settings.bossWindow.showAll = true
  bw.view = { dk = "AltarOfFangs", index = 1 }; bw:Show()
  local any = false
  for _, it in ipairs(bw.items) do if it.text:find("|Haddon:Ensemble:e:1111:boss:", 1, true) then any = true end end
  ok(any and bw.content.cmLinks, "boss window shows ability links and handles their tooltips")
  ok(table.concat(nsL2.BossCards:ChatLines("AltarOfFangs", 1), "\n"):find("|H", 1, true) == nil, "chat posts stay plain text")
  -- /ens verify season: dungeon pool, journal bosses with ability IDs, affixes
  local stubInstance = DUNGEON_MAPS[588][3]
  DUNGEON_MAPS[588][3] = 2993            -- the live client's instance map for Altar of Fangs
  local season = nsL2.Verify:BuildSeason()
  DUNGEON_MAPS[588][3] = stubInstance
  ok(season:find("588 | Altar of Fangs | instance 2993", 1, true) and season:find("addon: AltarOfFangs", 1, true), "season dump lists dungeons with IDs")
  ok(season:find("boss 1: Rav'i", 1, true) and season:find("Hydrastrike=1111", 1, true), "season dump lists journal bosses and ability IDs")
  ok(season:find("== This week's affixes ==", 1, true), "season dump has the affix section")
  SlashCmdList.ENSEMBLE("verify season")
  ok(nsL2.db.lastSeason and nsL2.db.lastSeason:find("season data", 1, true), "/ens verify season opens the copy window")
  -- Issue #10: which call finds the journal, and the in-dungeon fallback.
  local jid, how = BC2:JournalInstance("AltarOfFangs")
  ok(jid == 1322 and how == "C_EncounterJournal.GetInstanceForGameMap", "journal found from the instance map, anywhere")
  ok(BC2:JournalInstance("MurderRow") == nil, "no journal for a dungeon the client doesn't map (outside it)")
  C_EncounterJournal.GetInstanceForGameMap = nil
  C_Map = { GetBestMapForUnit = function(u) return u == "player" and 2433 or nil end }
  EJ_GetInstanceForMap = function(map) return map == 2433 and 1304 or 0 end
  ok(BC2:JournalInstance("MurderRow") == nil, "fallback not used outside the dungeon")
  local realCur = nsL2.CurrentInstanceDungeon
  nsL2.CurrentInstanceDungeon = function() return "MurderRow" end
  local j2, how2 = BC2:JournalInstance("MurderRow")
  ok(j2 == 1304 and how2 == "EJ_GetInstanceForMap(C_Map.GetBestMapForUnit)", "inside the dungeon: UI map fallback")
  ok(BC2:JournalInstance("AltarOfFangs") == nil, "the fallback only answers for the dungeon you are in")
  C_Map.GetBestMapForUnit = function() error("client error") end
  ok(BC2:JournalInstance("MurderRow") == nil, "a failing map call is contained")
  nsL2.CurrentInstanceDungeon = realCur
  -- /ens verify lists each dungeon's journal ID and the call that found it.
  C_EncounterJournal.GetInstanceForGameMap = function(map)
    local J = { [2993] = 1322, [2521] = 1302, [1877] = 1300, [1762] = 1301, [2859] = 1309, [2923] = 1313, [2825] = 1311, [2813] = 1304 }
    return J[map] or 0
  end
  local vtx = nsL2.Verify:Build()
  ok(vtx:find("[OK] journal found for 8 of 8 dungeons", 1, true) and vtx:find("Murder Row 2813 -> 1304 (C_EncounterJournal.GetInstanceForGameMap)", 1, true),
    "verify: every dungeon's journal ID and the call that found it")
  C_EncounterJournal.GetInstanceForGameMap = nil
  vtx = nsL2.Verify:Build()
  ok(vtx:find("GetInstanceForGameMap missing", 1, true) and vtx:find("journal found for 0 of 8 dungeons", 1, true), "verify: missing call is a WARN")
  EJ_GetInstanceForMap, EJ_GetEncounterInfoByIndex, C_EncounterJournal, C_Map = nil, nil, nil, nil
end

-- 50. Full review (October 2026): resource and data fixes
do
  EnsembleDB = nil
  local nsF = boot()
  -- Journal not ready: not cached as empty, so links appear once it loads.
  local BCF = nsF.BossCards
  ok(next(BCF:JournalSpells("AltarOfFangs")) == nil, "no journal: no ability links yet")
  EJ_GetEncounterInfoByIndex = function(n, jid) if jid == 1322 and n == 1 then return "Rav'i", "", 9001, 10 end end
  C_EncounterJournal = { GetSectionInfo = function(id) if id == 10 then return { title = "Hydrastrike", spellID = 1111 } end end,
    GetInstanceForGameMap = function(map) return map == 2993 and 1322 or 0 end }
  ok(BCF:JournalSpells("AltarOfFangs").Hydrastrike ~= nil, "journal read once it is available")
  EJ_GetInstanceForMap, EJ_GetEncounterInfoByIndex, C_EncounterJournal = nil, nil, nil
  -- Boss-card plan reused while nothing changes; settings clear it.
  local mem = { { specID = 73, isPlayer = true }, { specID = 256 }, { specID = 63 } }
  local p1 = BCF:Plan("AltarOfFangs", mem)
  ok(p1 and BCF:Plan("AltarOfFangs", mem) == p1, "boss-card plan cached")
  nsF:Fire("SETTINGS_CHANGED")
  ok(BCF:Plan("AltarOfFangs", mem) ~= p1, "settings change rebuilds the plan")
  -- Roster events that change nothing don't redraw the windows.
  local fired = 0
  nsF:On("LIVE_ROSTER_CHANGED", function() fired = fired + 1 end)
  local T = nsF.Tracker
  T:Acquire("test"); RunTimers()
  local afterAcquire = fired
  T:Rescan(); T:Rescan()
  ok(afterAcquire >= 1 and fired == afterAcquire, "unchanged roster: no extra LIVE_ROSTER_CHANGED")
  T:Release("test")
  -- Listing fit: your own profile is built once, not on every row redraw.
  local me1 = nsF.ListingFit:PlayerMember()
  ok(me1 and nsF.ListingFit:PlayerMember() == me1, "listing fit reuses your profile")
  nsF.ListingFit:ClearCache()
  ok(nsF.ListingFit:PlayerMember() ~= me1, "spec/talent change rebuilds it")
  -- Link decoration is cached and still correct.
  local L = nsF.Links
  local d1 = L:Decorate("Kick Hex Volley and Hex.", "interrupt", "KingsRest")
  ok(d1:find(":interrupt:Hex Volley|h", 1, true) and d1:find(":interrupt:Hex|h", 1, true), "longest name first, both linked")
  ok(L:Decorate("Kick Hex Volley and Hex.", "interrupt", "KingsRest") == d1, "decorated text reused")
  -- Hotfix data: Regurgitate is a Disease; freedom-only abilities aren't called Magic.
  local reg
  for _, q in ipairs(nsF.Dungeons.list.AltarOfFangs.requirements) do if q.id == "AOF_REGURGITATE" then reg = q end end
  ok(reg and reg.need == "dispel_disease", "Regurgitate needs a Disease dispel")
  ok(L.NEED_TYPE.freedom == "snare" and L.TYPES.snare.enemy:find("freedom", 1, true), "freedom needs read as roots/snares")
  local kr
  for _, q in ipairs(nsF.Dungeons.list.KingsRest.requirements) do if q.id == "KR_SHADOW_BOLT" then kr = q end end
  ok(kr and kr.source:find("^Shadow Bolt") and kr.confidence == "verified" and kr.need == "dispel_magic"
    and nsF.Dungeons.SPELL_IDS["Shadow Bolt"] == 1258431, "Risen Hexer's Shadow Bolt: Magic slow, confirmed, with its spell ID")
  -- Dev-build leftovers are gone.
  ok(nsF.Analysis.Suggest == nil and nsF.db.settings.window.scale == nil, "swap suggestions and window scale removed")
end

-- 51. Experience weighting, "what we need", host coaching, data date, tour
do
  EnsembleDB = nil
  C_LFGList.GetApplicantDungeonScoreForListing = function(id, m, activityID)
    local x = APPLICANTS[id] and APPLICANTS[id][m]
    if not (x and x.best) then return nil end
    return { mapScore = 300, mapName = "Altar of Fangs", bestRunLevel = x.best[1], finishedSuccess = x.best[2] }
  end
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
    party2 = { guid = "M", name = "Mia", class = "MAGE", role = "DAMAGER" },
  }
  INSPECT_CACHE = { H = 256, M = 63 }
  LISTING = "Altar of Fangs (Mythic Keystone)"
  APPLICANTS = {
    [1] = { { name = "Vet", class = "ROGUE", role = "DAMAGER", spec = 259, score = 3000, best = { 16, true } } },
    [2] = { { name = "Newb", class = "ROGUE", role = "DAMAGER", spec = 259, score = 900, best = { 0, false } } },
    [3] = { { name = "NoData", class = "ROGUE", role = "DAMAGER", spec = 259, score = 2000 } },
    [4] = { { name = "Cleanser", class = "PALADIN", role = "DAMAGER", spec = 70, score = 2500, best = { 15, true } } },
  }
  local nsE = boot()
  local Fit, UIE = nsE.ApplicantFit, nsE.UI
  -- Experience points against the key level
  ok(Fit:Experience({ { bestHere = { level = 15, timed = true } } }, 15).points == 100, "timed at the key level: full experience")
  ok(Fit:Experience({ { bestHere = { level = 13, timed = true } } }, 15).points == 80, "timed two below: close")
  ok(Fit:Experience({ { bestHere = { level = 0 } } }, 15).verdict == "new", "no run here: new")
  ok(Fit:Experience({ { name = "x" } }, 15) == nil and Fit:Experience({ { bestHere = { level = 9, timed = true } } }, nil) == nil,
    "no data or no key level: not judged")
  ok(Fit:ExperienceWeight(4) == 0.10 and Fit:ExperienceWeight(8) == 0.20 and Fit:ExperienceWeight(12) == 0.30, "weight grows with the key level")
  -- High key: the proven player rates above the newer one with the same spec
  nsE.state.keyLevelOverride = 15
  UIE:Show("applicants"); RunTimers()
  local _, evals = Fit:ForLiveGroup()
  local by = {}
  for _, ev in ipairs(evals) do by[ev.members[1].name] = ev end
  ok(by.Vet and by.Newb and by.Vet.fitScore == by.Newb.fitScore, "same spec: same utility fit")
  local rank = {}
  for i, ev in ipairs(evals) do rank[ev.members[1].name] = i end
  ok(by.Vet.score > by.Newb.score and rank.Vet < rank.Newb, "+15: the proven player ranks above the newer one")
  ok(by.NoData.experience == nil and by.NoData.score == by.NoData.fitScore, "no per-dungeon data: utility fit alone, no penalty")
  ok(by.Vet.members[1].bestHere.level == 16, "best run read from the Group Finder")
  local gap15 = by.Vet.score - by.Newb.score
  -- Low key: experience counts less, and a newer player who fits well gets the coaching line
  nsE.state.keyLevelOverride = 4
  nsE.ApplicantFit.cache_reset = true
  local _, low = Fit:ForLiveGroup()
  local lb = {}
  for _, ev in ipairs(low) do lb[ev.members[1].name] = ev end
  ok(lb.Vet.score - lb.Newb.score < gap15, "+4: experience matters less than at +15")
  ok(lb.Newb.fitScore < 60 or (lb.Newb.coaching and lb.Newb.coaching:find("good key to give them the run", 1, true)),
    "low key: coaching for a newer player who fits well")
  -- Detail panel shows the split
  UIE.ap.selected = by.Vet.applicantID; UIE:Refresh()
  local detail = ""
  for i = 1, UIE.ap.detail.used do detail = detail .. UIE.ap.detail.pool[i]._text .. "\n" end
  ok(detail:find("Utility %d+, experience %d+") ~= nil, "applicant detail shows utility and experience")
  ok(UIE.ap.cards[1].sub:GetText():find("best here", 1, true) ~= nil, "card shows the best run here")
  -- "What we need" for the listing
  local text = UIE:NeedsListingText(select(1, UIE:LiveAnalysis()), nsE.Tracker:GetComp())
  ok(text:find("^LF 2 DPS") and #text <= UIE.NEEDS_TEXT_MAX + 20, "listing text: open roles first, short: " .. text)
  UIE:CopyNeedsText()
  ok(nsE.Verify.frame and nsE.Verify.frame.report == text, "listing text opens in the copy window")
  UIE:BuildFinderPanel()
  ok(UIE.ap.needs ~= nil and UIE.fp ~= nil and UIE.fp.needs ~= nil, "What we need buttons on Applicants and the Group Finder panel")
  -- Only-gap headline
  ok(by.Cleanser.onlyGap and by.Cleanser.headline:find("^Fills [%a ]+gaps?: ") ~= nil,
    "an applicant who closes the last gap says so: " .. tostring(by.Cleanser.headline))
  -- Data date
  UIE:Show("dungeons"); RunTimers()
  ok(UIE.pp.asks.pool[1]._text:find("checked against Blizzard's hotfixes through", 1, true), "Dungeons tab shows how current the data is")
  ok(nsE.Report:Build():find(nsE.Dungeons.DATA_CHECKED, 1, true), "bug report states the data date")
  nsE.state.keyLevelOverride = nil
  -- Tour: starts on the first plain open, steps through, remembered
  UIE:Hide()
  nsE.db.tourSeen = nil
  UIE:Show(); RunTimers()
  local Tour = nsE.Tour
  ok(Tour:IsActive() and Tour.step == 1 and Tour.frame:IsShown() and nsE.db.tourSeen, "tour starts the first time the window opens")
  for _ = 1, #Tour.STEPS - 1 do Tour.frame.next._scripts.OnClick(Tour.frame.next) end
  ok(Tour.step == #Tour.STEPS and Tour.frame.next.text:GetText() == "Done", "tour reaches its last step")
  Tour.frame.next._scripts.OnClick(Tour.frame.next)
  ok(not Tour:IsActive() and not Tour.frame:IsShown(), "Done ends the tour")
  UIE:Hide(); UIE:Show(); RunTimers()
  ok(not Tour:IsActive(), "tour shows only once")
  Tour:Start()
  ok(Tour:IsActive() and Tour.step == 1, "the tour replays")
  Tour.frame.skip._scripts.OnClick(Tour.frame.skip)
  ok(not Tour:IsActive(), "Skip ends it")
  C_LFGList.GetApplicantDungeonScoreForListing = nil
  LISTING = nil
end

-- 52. Mythic Dungeon Tools route tracking removed (1.3.0, issue #11): nothing reads MDT, even
-- when it's loaded; saved route-pull Bloodlust entries are dropped on load.
do
  local function slurp(path) local f = io.open(path, "rb"); if not f then return nil end local t = f:read("*a"); f:close(); return t end
  local toc = slurp(ADDON_DIR .. "/Ensemble.toc") or ""
  ok(not toc:find("Route.lua", 1, true) and not toc:find("MythicDungeonTools", 1, true), "TOC: no Route.lua, no MDT dependency")
  ok(slurp(ADDON_DIR .. "/Route.lua") == nil, "Route.lua is gone")
  for _, f in ipairs(FILES) do
    local src = slurp(ADDON_DIR .. "/" .. f) or ""
    ok(not src:find("rawget(_G, \"MDT\")", 1, true) and not src:find("MythicDungeonToolsAPI", 1, true) and not src:find("ns.Route", 1, true),
      "no code reads Mythic Dungeon Tools: " .. f)
  end
  -- Saved data from 1.2.1: route-pull Bloodlust entries and the old setting.
  EnsembleDB = { settings = { routePlan = false }, lust = {
    KingsRest = { { at = "p3", note = "big pack" }, { at = "b4", note = "on pull" } },   -- mixed: keep the boss one
    AltarOfFangs = { { at = "p7" }, { at = "p12" } },                                   -- only pulls: back to the default
    MurderRow = {},                                                                      -- emptied on purpose: stays empty
  } }
  -- An MDT that's loaded (old global and the new API) changes nothing.
  MDT = { GetDB = function() error("must not be read") end }
  MythicDungeonToolsAPI = { GetDB = function() error("must not be read") end }
  local nsR = boot()
  ok(nsR.Route == nil, "no route module")
  ok(nsR.db.settings.routePlan == nil and nsR.DEFAULTS.settings.routePlan == nil, "the route setting is gone (saved value dropped)")
  local kr = nsR.db.lust.KingsRest
  ok(#kr == 1 and kr[1].at == "b4" and kr[1].note == "on pull", "route-pull lust dropped, the boss one kept")
  ok(nsR.db.lust.AltarOfFangs == nil and not select(2, nsR.Walkthrough:Lust("AltarOfFangs")) and #nsR.Walkthrough:Lust("AltarOfFangs") == 2,
    "a plan of only route pulls falls back to the dungeon default")
  ok(type(nsR.db.lust.MurderRow) == "table" and #nsR.db.lust.MurderRow == 0 and select(2, nsR.Walkthrough:Lust("MurderRow")),
    "a plan emptied on purpose stays empty")
  -- Walkthrough, Plan tab, boss window and Settings: guide order, no route anywhere.
  ok(nsR.Walkthrough:Build("KingsRest").order == "guide", "walkthrough in the guides' order")
  local spots = nsR.Walkthrough:Spots("KingsRest")
  local onlyTB = #spots == 8
  for _, sp in ipairs(spots) do if not sp.at:match("^[tb]%d$") then onlyTB = false end end
  ok(onlyTB, "Bloodlust spots: the trash before each boss and the boss, nothing else")
  nsR.db.currentComp = { 73, 256, 63, 71, 260 }
  nsR:SetManualDungeon("KingsRest")
  local UIR = nsR.UI
  UIR:Show("plan"); RunTimers()
  local t = {} for i = 1, UIR.pl.mine.used do t[#t + 1] = UIR.pl.mine.pool[i]:GetText() end
  ok(not table.concat(t, "\n"):upper():find("ROUTE", 1, true), "Plan tab: no route section")
  nsR.BossCards.state = { dk = "KingsRest", index = 1, killed = {} }
  local kinds = {}
  for _, r in ipairs(nsR.BossWindow:Rows("KingsRest", 1, "TANK", true, true)) do kinds[r.kind] = true end
  ok(not (kinds.pull or kinds.pullmine or kinds.pulljob or kinds.next), "boss window: no PULL or NEXT rows")
  nsR.BossCards.state = { killed = {} }
  UIR:Show("settings"); UIR:ShowSettingsSection("bosses"); RunTimers()
  local mdtText = false
  for _, fr in ipairs(ALLFRAMES) do
    local tx = rawget(fr, "_text")
    if type(tx) == "string" and tx:find("Mythic Dungeon Tools", 1, true) then mdtText = true end
  end
  ok(not mdtText, "no window text mentions Mythic Dungeon Tools")
  local vt = nsR.Verify:Build()
  ok(not vt:find("Mythic Dungeon Tools", 1, true) and not vt:find("== Route", 1, true) and not vt:find("enemy forces", 1, true),
    "verify: no Route section")
  -- 21 since 1.5.0: SCENARIO_CRITERIA_UPDATE is back, for History's boss splits (not the route).
  ok(vt:find("all 21 game events the addon uses accepted", 1, true), "verify: 21 events (boss splits; the route is still gone)")
  -- Dungeon names with or without the apostrophe still find Kings' Rest (the aliases were MDT's).
  ok(nsR.Dungeons:FindKey("King's Rest") == "KingsRest" and nsR.Dungeons:FindKey("Kings Rest") == "KingsRest"
    and nsR.Dungeons:FindKey("Kings' Rest (Mythic Keystone)") == "KingsRest", "Kings' Rest found by any spelling")
  UIR:Hide()
  MDT, MythicDungeonToolsAPI = nil, nil
end

-- 53. Dungeon walkthrough, role filter and the Bloodlust plan
do
  EnsembleDB = { lust = { KingsRest = { { at = "zz" }, "bad", { at = "b1", note = 5 } }, Junk = 7 } }
  local nsW = boot()
  ok(#nsW.db.lust.KingsRest == 1 and nsW.db.lust.KingsRest[1].note == nil and nsW.db.lust.Junk == nil, "damaged lust data cleaned on load")
  nsW.db.lust = {}
  local WT, DDw = nsW.Walkthrough, nsW.Dungeons
  -- Guide order: every requirement shows somewhere, in trash/boss order
  for _, dk in ipairs(DDw.order) do
    local w = WT:Build(dk)
    local seen = {}
    for _, st in ipairs(w.steps) do for _, q in ipairs(st.reqs) do seen[q.id] = true end end
    local missing = {}
    for _, q in ipairs(DDw.list[dk].requirements) do if not q.invalid and not seen[q.id] then missing[#missing + 1] = q.id end end
    ok(w.order == "guide" and #missing == 0, "walkthrough keeps every requirement: " .. dk .. " " .. table.concat(missing, ","))
    for id in pairs(DDw.AREAS[dk] or {}) do
      local found = false
      for _, q in ipairs(DDw.list[dk].requirements) do if q.id == id then found = true end end
      ok(found, "area tag names a real requirement: " .. id)
    end
  end
  local w = WT:Build("KingsRest")
  ok(w.steps[1].kind == "trash" and w.steps[1].boss == 1 and w.steps[2].kind == "boss" and w.steps[2].boss == 1
    and w.steps[#w.steps].kind == "boss" and w.steps[#w.steps].boss == 4, "guide order: trash, boss, ... last boss")
  local ids = {} for _, q in ipairs(w.steps[1].reqs) do ids[q.id] = true end
  ok(ids.KR_HEX_VOLLEY and not ids.KR_HEX, "Hex Volley before the first boss, Hex later")
  -- Bloodlust plan
  local uses, custom = WT:Lust("KingsRest")
  ok(#uses == 2 and not custom and uses[1].at == "b2", "default lust plan")
  ok(WT:LustChat("KingsRest"):find("^Lust: Mchimba the Embalmer") , "lust chat line: " .. WT:LustChat("KingsRest"))
  WT:SetLustAt("KingsRest", 3, "t1")
  uses, custom = WT:Lust("KingsRest")
  ok(custom and #uses == 3 and uses[1].at == "t1", "added lust sorted into dungeon order")
  WT:SetLustAt("KingsRest", 2, "b3")
  ok(WT:Lust("KingsRest")[2].at == "b3" and WT:Lust("KingsRest")[2].note == nil, "moving a lust drops the old note")
  local UIw = nsW.UI
  UIw:Build()
  local items = UIw:OpenLustMenu(nil, "KingsRest", 1)
  local noteItem
  for _, it in ipairs(items) do if it.text == "Add a note..." then noteItem = it end end
  ok(#items >= 10 and noteItem, "lust menu: every spot, note, remove")
  noteItem.onClick()
  ok(UIw.share:IsShown() and UIw.share.import.text:GetText() == "Save", "note prompt")
  UIw.share.box:SetText("first big pack|x"); UIw.share.import:Click()
  ok(WT:Lust("KingsRest")[1].note == "first big packx" and not UIw.share:IsShown(), "note saved (no escape codes)")
  WT:RemoveLust("KingsRest", 3)
  ok(#WT:Lust("KingsRest") == 2, "lust removed")
  -- Dungeon tab: lust markers, role filter
  UIw:Show("dungeons"); UIw:SetPrimerPick("KingsRest"); UIw:Refresh(); RunTimers()
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  local tx = dump(UIw.pp.walk)
  ok(tx:find("BLOODLUST|r  first big packx", 1, true) and tx:find("BLOODLUST", 1, true) < tx:find("1. THE GOLDEN SERPENT", 1, true), "lust marker in the walkthrough")
  local magic
  for _, q in ipairs(DDw.list.KingsRest.requirements) do if q.need == "dispel_magic" then magic = q end end
  ok(magic and UIw:WalkRoleWants("HEAL", magic) and not UIw:WalkRoleWants("TANK", magic) and UIw:WalkRoleWants("TANK", { need = "interrupt" }), "role relevance")
  nsW.db.settings.walkRole = "TANK"; UIw:Refresh(); RunTimers()
  local tt = dump(UIw.pp.walk)
  ok(#tt < #tx and not tt:find("|cff61cc78HEAL|r", 1, true) and tt:find("Hex Volley", 1, true), "tank filter: no healer lines, kicks stay")
  nsW.db.settings.walkRole = "ALL"
  -- Reset, and the plan post carries the lust line
  WT:ResetLust("KingsRest")
  ok(not select(2, WT:Lust("KingsRest")), "reset to the default")
  nsW.db.currentComp = { 73, 256, 63, 71, 260 }
  nsW.db.settings.compMode = "planner"
  nsW:SetManualDungeon("KingsRest"); UIw:Show("plan"); RunTimers()
  local lines = UIw:PlanChatLines(UIw.cp.lastPlan, "KingsRest")
  ok(lines[1]:find("assignments", 1, true) and lines[2]:find("^Lust: "), "plan post: lust second")
  ok(dump(UIw.pl.mine):find("BLOODLUST", 1, true), "Plan tab shows the lust plan")
  -- Boss window: lust on the boss
  WT:SetLustAt("KingsRest", 1, "b1")
  local rows = nsW.BossWindow:Rows("KingsRest", 1, "TANK", false, false)
  local lustRow
  for _, r in ipairs(rows) do if r.kind == "lust" then lustRow = r end end
  ok(lustRow and lustRow.text:find("Bloodlust", 1, true), "boss window: lust row on its boss")
  UIw:Hide()
end

-- 54. Assignments chosen by hand
do
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  local nsO = boot()
  local AS = nsO.Assignments
  local members = { { specID = 73, isPlayer = true }, { specID = 256 }, { specID = 63 }, { specID = 71 }, { specID = 260 } }
  local r = nsO.Analysis:Analyze(members, "KingsRest", nsO.db.settings)
  local plan = AS:Build(r)
  local row = plan.byReq.KR_HEX_VOLLEY
  local choices, kind = AS:Choices(r, row.req)
  ok(kind == "kick" and #choices >= 3, "kick choices for Hex Volley")
  local pick = choices[#choices].index   -- the slowest kicker
  AS:SetOverride(r, "KR_HEX_VOLLEY", "kick", { pick })
  local plan2 = AS:Build(r)
  local row2 = plan2.byReq.KR_HEX_VOLLEY
  ok(row2.manual and #row2.kickers == 1 and row2.kickers[1].index == pick and row2.backup, "your kicker stands, a backup is still picked")
  ok(AS:OverrideCount() == 1 and AS.overrideVersion > 0, "override counted")
  -- A different player in that slot: the override stops applying
  local members2 = { { specID = 73, isPlayer = true }, { specID = 256 }, { specID = 63 }, { specID = 71 }, { specID = 260 } }
  members2[pick] = { specID = 577 }
  local r2 = nsO.Analysis:Analyze(members2, "KingsRest", nsO.db.settings)
  ok(not AS:Build(r2).byReq.KR_HEX_VOLLEY.manual, "override ignored once that player changes")
  -- Dispel primary
  local drow
  for _, d in ipairs(plan.dispels) do if d.primary then drow = d; break end end
  local dch, dkind = AS:Choices(r, drow.req)
  if #dch > 1 then
    local other
    for _, c in ipairs(dch) do if c.index ~= drow.primary.index then other = c.index end end
    AS:SetOverride(r, drow.req.id, "dispel", { other })
    local d2 = AS:Build(r).byReq[drow.req.id]
    ok(dkind == "dispel" and d2.manual and d2.primary.index == other, "your dispeller stands")
  else
    ok(dkind == "dispel", "dispel choices")
  end
  -- UI: lines are clickable on the Plan tab; the menu edits; reset
  nsO.db.currentComp = { 73, 256, 63, 71, 260 }
  nsO.db.settings.compMode = "planner"
  nsO:SetManualDungeon("KingsRest")
  local UIo = nsO.UI
  UIo:Show("plan"); RunTimers()
  local L = UIo.pl.list
  local t = {} for i = 1, L.used do t[#t + 1] = L.pool[i]:GetText() end
  ok(table.concat(t, "\n"):find("(set by you)", 1, true) and table.concat(t, "\n"):find("Reset all assignments", 1, true), "edited lines marked, reset offered")
  local items = UIo:OpenAssignMenu(nil, UIo.cp.lastPlan.byReq.KR_HEX_VOLLEY)
  ok(items and items[1].header and items[#items].text == "Back to automatic", "assignment menu")
  local add
  for _, it in ipairs(items) do if it.text and not it.selected and not it.header and it.text ~= "Back to automatic" then add = it; break end end
  add.onClick(); RunTimers()
  ok(#UIo.cp.lastPlan.byReq.KR_HEX_VOLLEY.kickers == 2, "adding a second kicker to the rotation")
  -- the boss-card plan follows the edit
  nsO.BossCards:ClearPlanCache()
  AS:ClearOverrides(); RunTimers()
  ok(AS:OverrideCount() == 0 and not UIo.cp.lastPlan.byReq.KR_HEX_VOLLEY.manual, "reset to automatic")
  UIo:Hide()
end

-- 55. Applicants on the Composition tab while hosting
do
  EnsembleDB = nil
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
    party2 = { guid = "M", name = "Mia", class = "MAGE", role = "DAMAGER" },
  }
  INSPECT_CACHE = { H = 256, M = 63 }
  LISTING = "Altar of Fangs (Mythic Keystone)"
  APPLICANTS = {
    [1] = { { name = "Shamy", class = "SHAMAN", role = "DAMAGER", spec = 263 } },
    [2] = { { name = "Stabby", class = "ROGUE", role = "DAMAGER", spec = 259, score = 3100 } },
    [3] = { { name = "Kitty", class = "DRUID", role = "DAMAGER", spec = 103 } },
    [4] = { { name = "Smash", class = "WARRIOR", role = "DAMAGER", spec = 71 } },
    [5] = { { name = "Arc", class = "MAGE", role = "DAMAGER", spec = 62 } },
    [6] = { { name = "Hunt", class = "HUNTER", role = "DAMAGER", spec = 253 } },
  }
  local nsP = boot()
  local UIp = nsP.UI
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  UIp:Show("applicants"); RunTimers()
  UIp:Show("composition"); RunTimers()
  local cp = UIp.cp
  ok(UIp:CompMode() == "live" and cp.appPanel:IsShown() and not cp.sideList.sf:IsShown(), "hosting: applicant panel instead of the left list")
  local shown = 0
  for _, row in ipairs(cp.appPanel.rows) do if row:IsShown() then shown = shown + 1 end end
  ok(shown >= 3 and shown <= 6 and cp.appPanel.rows[1].inv.text:GetText() == "Invite", "best-fit rows with Invite (" .. shown .. ")")
  ok(cp.appPanel.more:GetText():find("more on the Applicants tab", 1, true) or shown == 6, "the rest point to the Applicants tab")
  -- Preview
  local first = cp.appPanel.rows[1]
  first:Click(); RunTimers()
  ok(cp.preview ~= nil, "click previews")
  local previewed = false
  for s = 1, 5 do if cp.slotRows[s].sub:GetText():find("Preview:", 1, true) then previewed = true end end
  ok(previewed, "previewed applicant sits in an open slot")
  do -- the hint under the rows is bounded on both sides, so it wraps instead of running into Needs
    local more, right = cp.appPanel.more, false
    for _, p in ipairs(rawget(more, "_points") or {}) do if p[1] == "RIGHT" and p[2] == cp.appPanel then right = true end end
    ok(right and more:GetText() ~= nil, "applicant hint wraps inside the column")
  end
  local rt = dump(cp.ready)
  ok(rt:find("Preview:", 1, true) and rt:find("click to clear", 1, true), "Needs says it's a preview")
  do -- only rows whose status changes carry "was X" / "new"; unchanged rows carry nothing
    local pev, pctx = UIp:PreviewApplicant()
    local before = nsP.Analysis:Readiness(pctx.base, nsP.db.settings).rows
    local after = nsP.Analysis:Readiness(pev.after, nsP.db.settings).rows
    local changed, nBefore = 0, 0
    for _ in pairs(before) do nBefore = nBefore + 1 end
    for cap, row in pairs(after) do if not before[cap] or before[cap].status ~= row.status then changed = changed + 1 end end
    local wasN, newN, unchangedMarked = 0, 0, 0
    for i = 1, cp.ready.used do
      local t = cp.ready.pool[i]:GetText() or ""
      local w = t:match("  was (%u+)|r")
      if w then wasN = wasN + 1 end
      if t:find("  new|r", 1, true) then newN = newN + 1 end
      for cap, row in pairs(after) do
        if before[cap] and before[cap].status == row.status and t:find(row.label .. "|r", 1, true) and (w or t:find("  new|r", 1, true)) then
          unchangedMarked = unchangedMarked + 1
        end
      end
    end
    local cnt = 0 for _ in pairs(UIp.previewWas or {}) do cnt = cnt + 1 end
    ok(cnt == nBefore and nBefore > 0, "preview remembers every row's status before (" .. cnt .. "/" .. nBefore .. ")")
    ok(changed > 0 and wasN + newN == changed and unchangedMarked == 0,
      string.format("changes marked: %d was + %d new for %d changed rows, %d unchanged rows marked", wasN, newN, changed, unchangedMarked))
  end
  first:Click(); RunTimers()
  ok(cp.preview == nil and not dump(cp.ready):find("Preview:", 1, true), "click again clears it")
  -- Toggle back to the usual view, and again
  cp.appPanel.hide:Click(); RunTimers()
  ok(not cp.appPanel:IsShown() and cp.sideList.sf:IsShown() and dump(cp.sideList):find("Show applicants here", 1, true), "list view while hosting")
  local back
  for i = 1, cp.sideList.bused do if cp.sideList.bpool[i].tip and cp.sideList.bpool[i].tip:find("best-fit applicants", 1, true) then back = cp.sideList.bpool[i] end end
  back:Click(); RunTimers()
  ok(cp.appPanel:IsShown(), "and back to the panel")
  -- Planner: never the panel
  UIp:SetCompMode("planner"); RunTimers()
  ok(not cp.appPanel:IsShown(), "planner: no applicant panel")
  -- The Applicants tab is unchanged
  UIp:Show("applicants"); RunTimers()
  ok(UIp.ap.cards[1] and UIp.ap.cards[1]:IsShown() and UIp.ap.cards[1].cmp.text:GetText() ~= nil, "Applicants tab keeps cards and compare")
  -- 1.2.0 layouts: "Group after:" on every surface (mock-ups approved October 13)
  local ctxG, evG = nsP.ApplicantFit:ForLiveGroup()
  local card1, ev1 = UIp.ap.cards[1], evG[1]
  ok(card1:GetHeight() == 80, "card is 80px tall (one more line)")
  ok(card1.after:GetText():find("Group after: ", 1, true) and card1.after:GetText():find(ev1.groupAfter.missing[1] or "Ready", 1, true),
    "card: Group after line (" .. card1.after:GetText() .. ")")
  local hp = rawget(card1.headline, "_points") or {}
  ok(hp[1] and hp[1][1] == "TOPLEFT" and hp[1][2] == card1.sub, "card: headline sits under the name block")
  UIp:Show("composition"); RunTimers()
  local row1 = cp.appPanel.rows[1]
  ok(row1.tag:GetText():find(ev1.rating.word:upper(), 1, true) and row1.after:GetText():find(ev1.groupAfter.short, 1, true),
    "panel row: rating word over the group status")
  ok(row1.tooltip and row1.tooltip:find("Group after: ", 1, true), "panel row: full Group after line on hover")
  local np = rawget(row1.name, "_points") or {}
  local nameRight
  for _, p in ipairs(np) do if p[1] == "RIGHT" then nameRight = p end end
  ok(nameRight and nameRight[2] == row1.inv and nameRight[4] == -72, "panel row: name leaves room for the status column")
  -- Group Finder panel rows
  PVEFrame:Show(); RunTimers(); UIp:RefreshFinderPanel()
  local fr = UIp.fp.rows[1]
  ok(fr:IsShown() and fr.after:GetText():find(ev1.groupAfter.short, 1, true), "Group Finder row: status at the end of the headline line")
  PVEFrame:Hide(); RunTimers()
  -- Blizzard applicant tooltip
  local tipLines, oldAdd = {}, GameTooltip.AddLine
  GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = t end
  local fakeMember = { applicantID = ev1.applicantID }
  UIp:AddApplicantTooltip(fakeMember)
  GameTooltip.AddLine = oldAdd
  local tipAll = table.concat(tipLines, "\n")
  ok(tipAll:find("Ensemble: ", 1, true) and tipAll:find("Group after: ", 1, true), "Blizzard tooltip: Group after line")
  -- Compare: a Group after line under each applicant
  UIp:Show("applicants"); RunTimers()
  UIp.ap.compare = { evG[1].applicantID, evG[2].applicantID }; UIp:Refresh(); RunTimers()
  local cmpText = dump(UIp.ap.detail)
  local _, nGA = cmpText:gsub("Group after: ", "")
  ok(nGA >= 2, "Compare: Group after under A and B (" .. nGA .. ")")
  UIp.ap.compare = {}
  UIp:Hide()
  LISTING, APPLICANTS = nil, {}
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
end

-- 56. Patch 12.1.5 data: Living Bomb dispel, data date
do
  EnsembleDB = nil
  local nsP = boot()
  local DDp = nsP.Dungeons
  ok(DDp.DATA_PATCH == "12.1.5" and DDp.DATA_CHECKED == "October 23, 2026"
    and DDp:FreshnessText():find("patch 12.1.5", 1, true), "data dated to patch 12.1.5")
  local lb
  for _, q in ipairs(DDp.list.RubyLifePools.requirements) do if q.id == "RLP_LIVING_BOMB" then lb = q end end
  ok(lb and lb.need == "dispel_magic" and not lb.invalid and lb.confidence == "verified"
    and lb.source:find("^Living Bomb %(Primalist Cinderweaver, Blazebound Destroyer"), "Living Bomb: Magic dispel, both casters, confirmed")
  ok(DDp.SPELL_IDS["Living Bomb"] == 373693, "Living Bomb has its spell ID")
  -- Murder Row casters (Method.gg; ISSUES #2)
  local mr = {}
  for _, q in ipairs(DDp.list.MurderRow.requirements) do mr[q.id] = q end
  local AS = nsP.Assignments
  ok(AS.MobName(mr.MR_SEDUCTION) == "Seductive Sayaad" and AS.MobName(mr.MR_FEL_MISSILES) == "Felonious Mage"
    and AS.MobName(mr.MR_HEARTSTOP) == "Street Sneak", "Murder Row casts credited to the right mobs")
  -- Placed in the trash before Kokia (boss 2), not on a boss card
  local w = nsP.Walkthrough:Build("RubyLifePools")
  local where
  for _, st in ipairs(w.steps) do for _, q in ipairs(st.reqs) do
    if q.id == "RLP_LIVING_BOMB" then where = st end end end
  ok(where and where.kind == "trash" and where.boss == 2, "walkthrough: Living Bomb in the trash before Kokia")
  -- No Magic dispeller: missing. A Priest healer covers it.
  local A = nsP.Analysis
  local function status(specs)
    local r = A:Analyze(specs, "RubyLifePools", nsP.db.settings)
    for _, it in ipairs(r.dungeon and r.dungeon.items or {}) do
      if it.req.id == "RLP_LIVING_BOMB" then return it.status end
    end
  end
  local none = status({ { specID = 73 }, { specID = 71 }, { specID = 72 }, { specID = 251 } })
  local priest = status({ { specID = 73 }, { specID = 256 }, { specID = 71 }, { specID = 72 } })
  ok(none == "missing" and priest == "covered", "Living Bomb counts toward Magic dispel coverage: " .. tostring(none) .. "/" .. tostring(priest))
end

-- 57. Fit rating rework (1.2.0): pick rating, critical-gap rule, no-real-difference guard,
-- "Group after:" status, listing fit
do
  EnsembleDB = nil
  local nsR = boot()
  local Fit, LF, UDr, Ar, DDr = nsR.ApplicantFit, nsR.ListingFit, nsR.UD, nsR.Analysis, nsR.Dungeons
  local H = DDr.HEURISTICS
  local set = nsR.db.settings
  ok(H.FIT_GREAT == 80 and H.FIT_GOOD == 45 and H.FIT_FAIR == 15 and H.FIT_FLAT_SPREAD == 5 and H.FIT_FLAT_SCORE == 70,
    "bands re-tuned from the measurement report")
  ok(Fit:RatingFor(80).key == "great" and Fit:RatingFor(79).key == "good" and Fit:RatingFor(45).key == "good"
    and Fit:RatingFor(44).key == "fair" and Fit:RatingFor(15).key == "fair" and Fit:RatingFor(14).key == "poor"
    and Fit:RatingFor(100, true).key == "poor", "RatingFor follows the bands; a role conflict is always poor")
  ok(Fit.Relative(10, 12, 9) == nil and Fit.Relative(5, 10, 0) == 0.5 and Fit.Relative(-3, 10, 0) == 0 and Fit.Relative(20, 10, 0) == 1,
    "Relative: nil under the flat spread, clamped 0-1")

  -- Critical-gap rule (1.2.1: partial vs full), every spec of every role, several dungeons and
  -- party states, with and without a key level: a FULL closer never rates below anyone who
  -- doesn't fully close a critical gap; a PARTIAL closer never rates below its floor.
  local states = { {}, { 73 }, { 256 }, { 73, 256 }, { 73, 72 }, { 73, 256, 63 }, { 73, 256, 63, 577 }, { 63, 62, 64 } }
  local checked, closers, partials, partialChecked = 0, 0, 0, 0
  for _, dk in ipairs({ "AltarOfFangs", "KingsRest", "RubyLifePools", "TempleOfSethraliss", "VoidscarArena" }) do
    for _, lvl in ipairs({ false, 12 }) do
      for _, st in ipairs(states) do
        local mem = {}
        for i, id in ipairs(st) do mem[i] = { specID = id } end
        local ctx = Fit:BuildContext(mem, dk, set, lvl or nil)
        local byRole = {}
        for id, sp in pairs(UDr.specs) do
          local ev = Fit:Evaluate(ctx, { applicantID = id, members = { { name = "s" .. id, specID = id } } })
          if not ev.roleConflict then
            byRole[sp.role] = byRole[sp.role] or {}
            table.insert(byRole[sp.role], ev)
          end
        end
        for role, list in pairs(byRole) do
          local minFull, maxOther
          for _, ev in ipairs(list) do
            if ev.closesCriticalFull then closers = closers + 1; minFull = math.min(minFull or 999, ev.score)
            else maxOther = math.max(maxOther or -1, ev.score) end
            if ev.closesCritical and not ev.closesCriticalFull then
              partials = partials + 1
              local pf = ctx.critPartialFloor[role]
              if pf and not ev.flat then
                partialChecked = partialChecked + 1
                ok(ev.critFloor == math.floor(pf * 100 + 0.5) and ev.score >= ev.critFloor,
                  string.format("partial close floor: %s %s %s spec %d, %d >= %s", dk, tostring(lvl), role, ev.members[1].specID, ev.score, tostring(ev.critFloor)))
              end
            end
          end
          if minFull and maxOther then
            checked = checked + 1
            ok(minFull >= maxOther, string.format("critical-gap rule: %s %s %s, full closers min %d >= others max %d", dk, tostring(lvl), role, minFull, maxOther))
          end
        end
      end
    end
  end
  ok(checked > 0 and closers > 0 and partials > 0 and partialChecked > 0,
    "critical-gap rule exercised (" .. checked .. " role cases, " .. closers .. " full closers, " .. partials .. " partial, " .. partialChecked .. " floors checked)")

  -- The October 14 case: Temple of Sethraliss, Prot Warrior + Fury Warrior, +12. Shadow Priest
  -- covers Imbued Conduction only with Mass Dispel (long cooldown): a partial close, about 50
  -- (Good), below the Elemental Shaman who closes far more.
  local ctxT = Fit:BuildContext({ { specID = 73 }, { specID = 72 } }, "TempleOfSethraliss", set, 12)
  local evSh = Fit:Evaluate(ctxT, { applicantID = 1, members = { { name = "Shadow", specID = 258 } } })
  local evEl = Fit:Evaluate(ctxT, { applicantID = 2, members = { { name = "Ele", specID = 262 } } })
  ok(evSh.critClose and evSh.critClose.kind == "partial" and evSh.critClose.closes[1].how == "Mass Dispel, long cooldown",
    "Temple: Shadow Priest partly closes Imbued Conduction (" .. tostring(evSh.critClose and evSh.critClose.closes[1].how) .. ")")
  ok(evSh.rawImmediate < 50 and evSh.score == 50 and evSh.critFloored == "partial" and evSh.rating.key == "good",
    "Temple: Shadow Priest floored at 50, Good (raw " .. tostring(evSh.rawImmediate) .. ", score " .. evSh.score .. ")")
  ok(evEl.score == 100 and evSh.score < evEl.score, "Temple: Shadow below Elemental (" .. evSh.score .. " < " .. evEl.score .. ")")
  local both = Fit:EvaluateAll(ctxT, { { applicantID = 1, members = { { name = "Shadow", specID = 258 } } },
                                        { applicantID = 2, members = { { name = "Ele", specID = 262 } } } })
  ok(both[1].members[1].name == "Ele" and both[2].score == 50 and not both[2].critLifted, "Temple: a partial closer is never lifted")

  -- The rule also holds against experience: an inexperienced FULL closer vs a proven non-closer.
  -- (Voidscar Arena, nobody in the group: Restoration Shaman's Wind Shear fully closes a
  -- critical kick; the other healers close nothing.)
  local fullSpec, noSpec, ctxK
  for _, dk in ipairs({ "VoidscarArena", "KingsRest" }) do
    local c = Fit:BuildContext({}, dk, set, 12)
    for _, role in ipairs({ "HEALER", "DAMAGER", "TANK" }) do
      local f, n
      for _, id in ipairs(UDr:SpecsForRole(role)) do
        local cc = Fit.CriticalClose(c.baseCritical, Ar:Analyze({ { specID = id } }, dk, set))
        if cc and cc.kind == "full" then f = f or id elseif not cc then n = n or id end
      end
      if f and n and not fullSpec then fullSpec, noSpec, ctxK = f, n, c end
    end
  end
  ok(fullSpec and noSpec, "found a spec that fully closes a critical gap and one that closes none")
  local evs = Fit:EvaluateAll(ctxK, {
    { applicantID = 1, members = { { name = "Fresh", specID = fullSpec, bestHere = { level = 0 } } } },
    { applicantID = 2, members = { { name = "Vet", specID = noSpec, bestHere = { level = 20, timed = true } } } },
  })
  local fresh, vet
  for _, ev in ipairs(evs) do if ev.applicantID == 1 then fresh = ev else vet = ev end end
  ok(fresh.closesCriticalFull and not vet.closesCritical and fresh.score >= vet.score,
    "experience can't lift a non-closer above a full closer (" .. fresh.score .. " vs " .. vet.score .. ")")

  -- No real difference: with a huge flat spread every pick is the same and experience decides.
  local oldSpread = H.FIT_FLAT_SPREAD
  H.FIT_FLAT_SPREAD = 1e9
  local ctxF = Fit:BuildContext({ { specID = 73 }, { specID = 256 }, { specID = 63 } }, "AltarOfFangs", set, 8)
  local evF = Fit:EvaluateAll(ctxF, {
    { applicantID = 1, members = { { name = "Low", specID = 259, bestHere = { level = 3, timed = true } } } },
    { applicantID = 2, members = { { name = "High", specID = 70, bestHere = { level = 10, timed = true } } } },
    { applicantID = 3, members = { { name = "Tank", specID = 104 } } },
  })
  H.FIT_FLAT_SPREAD = oldSpread
  local flatNote = false
  for _, n in ipairs(evF[1].notes) do if n:find("No real difference", 1, true) and n:find("decide on experience", 1, true) then flatNote = true end end
  ok(evF[1].flat and evF[2].flat and evF[1].score == H.FIT_FLAT_SCORE and evF[2].score == H.FIT_FLAT_SCORE
    and evF[1].rating == evF[2].rating, "flat: everyone gets the same rating")
  ok(evF[1].members[1].name == "High" and flatNote, "flat: ordered by experience, card says to decide on experience")
  ok(evF[3].roleConflict and evF[3].rating.key == "poor" and not evF[3].flat, "flat: a role already filled stays Poor")
  ok(evF[1].idealPick == nil, "flat: no 'ideal pick' note")

  -- Experience weighting carries over (not flat).
  local ctxE = Fit:BuildContext({ { specID = 73 }, { specID = 256 }, { specID = 63 } }, "AltarOfFangs", set, 12)
  local evE = Fit:Evaluate(ctxE, { applicantID = 9, members = { { name = "E", specID = 259, bestHere = { level = 12, timed = true } } } })
  ok(not evE.flat and evE.score == math.floor(0.7 * evE.fitScore + 0.3 * 100 + 0.5), "experience counts 30% at +12")

  -- "Group after:" status
  local function analysis(specs, dk)
    local m = {} for i, id in ipairs(specs) do m[i] = { specID = id } end
    return Ar:Analyze(m, dk, set)
  end
  local rA = analysis({ 73, 256, 63, 577 }, "AltarOfFangs")
  local ga = Fit:GroupAfter(rA, set, 1)
  local ready = Ar:Readiness(rA, set)
  ok(ga.status == (ready.counts.missing > 0 and "missing" or ready.counts.thin > 0 and "thin" or "ready")
    and #ga.missing == ready.counts.missing and #ga.thin == ready.counts.thin, "group after matches the Needs counts")
  for _, l in ipairs(ga.missing) do ok(ga.text:find(l, 1, true) and ga.brief:find(l, 1, true), "group after names missing need " .. l) end
  for _, l in ipairs(ga.thin) do ok(ga.text:find(l, 1, true), "group after full text names thin need " .. l) end
  ok(ga.text:find(", 1 slot open$") and ga.short:find("missing") , "group after: slots and short form (" .. ga.text .. ")")
  ok(not ga.text:find("%d+/100") and not ga.text:find("score"), "group after is never a score")
  local oldR = Ar.Readiness
  Ar.Readiness = function() return { risks = {} } end
  local gaR = Fit:GroupAfter(rA, set, 0)
  Ar.Readiness = oldR
  ok(gaR.status == "ready" and gaR.text == "Ready" and gaR.short == "Ready", "group after: Ready, no slots text when full")
  ok(Fit.GROUP_AFTER_COLOR.ready and Fit.GROUP_AFTER_ICON.missing:find("NotReady"), "group after colors and icons")

  -- Listing fit: same pick rating, critical floor, group after you
  LF:PlayerProfile(nil)
  local function lm(specs) local t = {} for i, id in ipairs(specs) do t[i] = { specID = id, role = UDr:GetSpec(id).role, profile = LF.GroupProfile(id) } end return t end
  local function me(id) return { specID = id, profile = LF.GroupProfile(id), isPlayer = true, label = "You", role = UDr:GetSpec(id).role } end
  local resRet = LF:Evaluate(lm({ 73, 256, 63, 577 }), "AltarOfFangs", me(70), set)
  local resRog = LF:Evaluate(lm({ 73, 256, 63, 577 }), "AltarOfFangs", me(259), set)
  ok(resRet.score > resRog.score and resRet.rating.key == "great" and resRog.rating.key == "poor",
    "listing: Retribution a great pick, Assassination a poor one (" .. resRet.score .. "/" .. resRog.score .. ")")
  ok(resRet.groupAfter.status ~= "missing" and #resRet.still == 0 and resRog.groupAfter.status == "missing" and #resRog.groupAfter.missing == #resRog.still,
    "listing: group after you from what's still missing")
  -- Critical-gap rule in listing fit: full closers never below a spec that doesn't fully close
  -- one; partial closers never below their floor.
  local lchecked = 0
  for _, case in ipairs({ { "TempleOfSethraliss", {}, "HEALER" }, { "TempleOfSethraliss", { 73, 72 }, "DAMAGER" },
                          { "KingsRest", { 256 }, "DAMAGER" }, { "AltarOfFangs", { 256 }, "DAMAGER" } }) do
    local lmin, lmax, pbad = nil, nil, 0
    for id, sp in pairs(UDr.specs) do
      if sp.role == case[3] then
        local r = LF:Evaluate(lm(case[2]), case[1], me(id), set)
        if r.closesCriticalFull then lmin = math.min(lmin or 999, r.score) else lmax = math.max(lmax or -1, r.score) end
        if r.closesCritical and not r.closesCriticalFull and r.critFloor and r.score < r.critFloor then pbad = pbad + 1 end
      end
    end
    if lmin and lmax then lchecked = lchecked + 1; ok(lmin >= lmax, "listing: critical-gap rule " .. case[1] .. " (" .. lmin .. " >= " .. lmax .. ")") end
    ok(pbad == 0, "listing: partial closers keep their floor in " .. case[1])
  end
  ok(lchecked > 0, "listing critical-gap rule exercised (" .. lchecked .. ")")
  local lSh = LF:Evaluate(lm({ 73, 72 }), "TempleOfSethraliss", me(258), set, 12, "title")
  local lEl = LF:Evaluate(lm({ 73, 72 }), "TempleOfSethraliss", me(262), set, 12, "title")
  ok(lSh.critFloored == "partial" and lSh.score == 50 and lEl.score > lSh.score, "listing: Temple, Shadow " .. lSh.score .. " below Elemental " .. lEl.score)
end

-- 58. Code review fixes (1.2.1): Invite after an outside invite, "Why N?" arithmetic, best-value
-- filters, the per-applicant rating cache, listing fit on equal terms
do
  EnsembleDB = nil
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
  }
  INSPECT_CACHE = { H = 256 }
  LISTING = "Temple of Sethraliss (Mythic Keystone)"
  APPLICANT_STATUS = {}
  APPLICANTS = {
    [1] = { { name = "Shamy", class = "SHAMAN", role = "DAMAGER", spec = 263, score = 2700 } },
    [2] = { { name = "Stabby", class = "ROGUE", role = "DAMAGER", spec = 259, score = 3100 } },
    [3] = { { name = "Shade", class = "PRIEST", role = "DAMAGER", spec = 258, score = 2900 } },
    [4] = { { name = "Bear", class = "DRUID", role = "TANK", spec = 104, score = 3500 } },
  }
  local nsQ = boot()
  local UIq, FitQ, T = nsQ.UI, nsQ.ApplicantFit, nsQ.Tracker
  C_LFGList.InviteApplicant = function() end
  UIq:Show("applicants"); RunTimers()
  local function cardFor(name)
    for _, c in ipairs(UIq.ap.cards) do if c:IsShown() and c.name:GetText():find(name, 1, true) then return c end end
  end

  -- Item 2: invited through Blizzard's own button -> the card says Invited and is disabled.
  local inv = cardFor("Stabby").inv
  ok(inv.text:GetText() == "Invite" and inv:IsEnabled(), "Invite ready before the outside invite")
  APPLICANT_STATUS[2] = "invited"
  T:Rescan(); RunTimers(); UIq:Refresh(); RunTimers()
  inv = cardFor("Stabby").inv
  ok(inv.text:GetText() == "Invited" and not inv:IsEnabled(), "an outside invite shows as Invited (" .. inv.text:GetText() .. ")")
  UIq:Show("composition"); RunTimers()
  local rowInv
  for _, row in ipairs(UIq.cp.appPanel.rows) do
    if row:IsShown() and row.name:GetText():find("Stabby", 1, true) then rowInv = row.inv end
  end
  ok(rowInv and rowInv.text:GetText() == "Invited" and not rowInv:IsEnabled(), "Composition row: Invited too")
  APPLICANT_STATUS[2] = nil; T:Rescan(); RunTimers()

  -- Item 5: one new application costs one evaluation; one leaving costs none; same answer as
  -- an uncached pass.
  local calls, realEval = 0, FitQ.Evaluate
  FitQ.Evaluate = function(...) calls = calls + 1; return realEval(...) end
  FitQ:ForLiveGroup()
  calls = 0
  APPLICANTS[5] = { { name = "Arc", class = "MAGE", role = "DAMAGER", spec = 62, score = 2600 } }
  T:Rescan()
  local ctxC, evC = FitQ:ForLiveGroup()
  ok(calls == 1 and #evC == 5, "one new application: one evaluation (" .. calls .. ")")
  calls = 0
  APPLICANTS[1] = nil; T:Rescan()
  ctxC, evC = FitQ:ForLiveGroup()
  ok(calls == 0 and #evC == 4, "one application leaves: no evaluation (" .. calls .. ")")
  calls = 0
  APPLICANT_STATUS[3] = "invited"; T:Rescan()
  local _, evS = FitQ:ForLiveGroup()
  local shade
  for _, ev in ipairs(evS) do if ev.members[1].name == "Shade" then shade = ev end end
  ok(calls == 0 and shade.members[1].status == "invited", "a status change re-reads the rows without re-rating")
  APPLICANT_STATUS[3] = nil; T:Rescan()
  FitQ.Evaluate = realEval
  local function same(a, b)
    if #a ~= #b then return false, "count" end
    for i = 1, #a do
      local x, y = a[i], b[i]
      if x.applicantID ~= y.applicantID or x.score ~= y.score or x.rating.key ~= y.rating.key or x.headline ~= y.headline
        or (x.critLifted or false) ~= (y.critLifted or false) or table.concat(x.notes, "/") ~= table.concat(y.notes, "/") then
        return false, tostring(x.applicantID)
      end
    end
    return true
  end
  APPLICANTS[6] = { { name = "Hunt", class = "HUNTER", role = "DAMAGER", spec = 253, score = 2500 } }
  T:Rescan()
  local ctxI, evI = FitQ:ForLiveGroup()
  local ctxU = FitQ:BuildContext(T:GetComp(), ctxI.dungeonKey, nsQ.db.settings, ctxI.keyLevel)
  local evU = FitQ:EvaluateAll(ctxU, T:GetApplicantGroups())
  local same1, why1 = same(evI, evU)
  ok(same1, "cached and uncached passes agree (" .. tostring(why1) .. ")")
  FitQ:Rank(evI); FitQ:Rank(evI)
  ok(same(evI, evU), "ranking the same evaluations again changes nothing")

  -- Item 3: every "Why N?" step adds up, in order, for many applicants (experience, premades,
  -- role conflicts, partial and full critical closes, the lift).
  local set = nsQ.db.settings
  local stepCases, bad = 0, 0
  local function checkSteps(ctx, ev, label)
    local steps = FitQ:ScoreSteps(ctx, ev)
    local prev, last
    for i, st in ipairs(steps) do
      if st.value then
        if i == 1 then
          if st.value ~= ev.fitScore then bad = bad + 1; print("  step1 " .. label) end
          if not ev.flat and not st.text:find(string.format("so %d/100 as a pick", ev.fitScore), 1, true) then bad = bad + 1; print("  step1 text " .. label) end
          if not ev.flat then
            local rel = math.min(1, math.max(0, ev.gain - ev.worst) / (ev.best - ev.worst))
            if math.floor(rel * 100 + 0.5) ~= ev.fitScore then bad = bad + 1; print("  position " .. label) end
          end
        elseif st.text:find("^Experience counts") then
          local w = ev.experience.weight
          if st.value ~= math.floor((1 - w) * prev + w * ev.experience.points + 0.5) or not st.text:find("= " .. st.value .. ".", 1, true) then
            bad = bad + 1; print("  exp " .. label)
          end
        elseif st.text:find("^Raised to") then
          if not (st.value > prev and st.text:find("Raised to " .. st.value .. ":", 1, true)) then bad = bad + 1; print("  raise " .. label) end
        elseif st.text:find("capped at 15") then
          if st.value ~= math.min(prev, 15) then bad = bad + 1; print("  cap " .. label) end
        end
        prev, last = st.value, st.value
      end
    end
    if last ~= ev.score then bad = bad + 1; print(string.format("  last %s ~= score %d %s", tostring(last), ev.score, label)) end
    local sum = 0
    for _, b in ipairs(ev.breakdown or {}) do sum = sum + b.points end
    if math.abs(sum - ev.gain) > 0.05 * (#(ev.breakdown or {}) + 1) then bad = bad + 1; print("  gap lines " .. label) end
    stepCases = stepCases + 1
  end
  for _, dk in ipairs({ "TempleOfSethraliss", "KingsRest", "VoidscarArena", "AltarOfFangs" }) do
    for _, lvl in ipairs({ false, 4, 12 }) do
      for _, st in ipairs({ {}, { 73 }, { 73, 72 }, { 73, 256 }, { 73, 256, 63 } }) do
        local mem = {}
        for i, id in ipairs(st) do mem[i] = { specID = id } end
        local ctx = FitQ:BuildContext(mem, dk, set, lvl or nil)
        local groups, n = {}, 0
        for id in pairs(nsQ.UD.specs) do
          n = n + 1
          groups[#groups + 1] = { applicantID = id, members = { { name = "s" .. id, specID = id,
            bestHere = (n % 3 ~= 0) and { level = (n * 7) % 16, timed = n % 2 == 0 } or nil } } }
        end
        groups[#groups + 1] = { applicantID = 9001, members = { { name = "p1", specID = 262 }, { name = "p2", specID = 258 } } }
        for _, ev in ipairs(FitQ:EvaluateAll(ctx, groups)) do
          checkSteps(ctx, ev, dk .. " " .. tostring(lvl) .. " " .. table.concat(st, ",") .. " #" .. tostring(ev.applicantID))
        end
      end
    end
  end
  ok(stepCases > 1000 and bad == 0, "Why N? steps add up in every case (" .. stepCases .. " cases, " .. bad .. " wrong)")
  -- The Temple case reads in order: position 32 -> raised to 50, partly closes, with the source.
  local ctxT = FitQ:BuildContext({ { specID = 73 }, { specID = 72 } }, "TempleOfSethraliss", set, 12)
  local evT = FitQ:Evaluate(ctxT, { applicantID = 1, members = { { name = "Shadow", specID = 258 } } })
  local stT = FitQ:ScoreSteps(ctxT, evT)
  ok(stT[1].value == evT.rawImmediate and stT[1].text:find("so " .. evT.rawImmediate .. "/100", 1, true)
    and stT[2].text:find("Raised to 50: they only partly close a critical gap (Magic dispel for Imbued Conduction: Mass Dispel, long cooldown)", 1, true),
    "Temple: Why shows the position, then the partial rule with its source: " .. tostring(stT[2] and stT[2].text))
  -- In the window: "Why N?" heads the steps and the last line is the score.
  UIq:Show("applicants"); RunTimers()
  local _, evW = FitQ:ForLiveGroup()
  UIq.ap.selected = evW[1].applicantID
  UIq:SetOpen("score:" .. tostring(evW[1].applicantID), true); UIq:Refresh(); RunTimers()
  local dt = {}
  for i = 1, UIq.ap.detail.used do dt[#dt + 1] = UIq.ap.detail.pool[i]:GetText() or "" end
  local all = table.concat(dt, "\n")
  local lastStep = FitQ:ScoreSteps(ctxI, evW[1])
  ok(all:find("Why " .. evW[1].score .. "?", 1, true) and all:find(lastStep[#lastStep].text, 1, true), "the window shows the steps under Why " .. evW[1].score .. "?")

  -- Item 4: best-value classes honor ignored needs and "hide low", like the walkthrough.
  local A = nsQ.Analysis
  local dkP
  for _, key in ipairs(nsQ.Dungeons.order) do
    local hasPoison, hasLow = false, false
    for _, q in ipairs(nsQ.Dungeons.list[key].requirements) do
      if q.need == "dispel_poison" then hasPoison = true end
      if q.severity == "low" then hasLow = true end
    end
    if hasPoison and hasLow then dkP = key; break end
  end
  ok(dkP ~= nil, "a dungeon with Poison dispel and low-severity requirements (" .. tostring(dkP) .. ")")
  local s2 = nsQ.Util.DeepCopy(set)
  s2.ignoredNeeds = { dispel_poison = true }; s2.hideLowSeverity = true
  local prof = A:DungeonProfile(dkP, s2, 12)
  local poisonShown, lowShown, coverPoison = false, false, false
  for _, n in ipairs(prof.needs) do
    if n.key == "dispel_poison" then poisonShown = true end
    for _, q in ipairs(n.reqs) do if q.severity == "low" then lowShown = true end end
  end
  for _, list in pairs(prof.roles) do
    for _, e in ipairs(list) do for _, c in ipairs(e.covers) do if c.key == "dispel_poison" then coverPoison = true end end end
  end
  ok(not poisonShown and not lowShown and not coverPoison, "best-value classes: ignored Poison dispel and low entries left out")
  local oldIgn, oldLow = set.ignoredNeeds, set.hideLowSeverity
  set.ignoredNeeds, set.hideLowSeverity = { dispel_poison = true }, true   -- the walkthrough reads the saved settings
  local walk = nsQ.Walkthrough:Build(dkP)
  set.ignoredNeeds, set.hideLowSeverity = oldIgn, oldLow
  local wIds, pIds = {}, {}
  for _, stp in ipairs(walk and walk.steps or {}) do for _, q in ipairs(stp.reqs or {}) do wIds[q.id] = true end end
  for _, n in ipairs(prof.needs) do for _, q in ipairs(n.reqs) do if not q.affix then pIds[q.id] = true end end end
  local diff = 0
  for id in pairs(wIds) do if not pIds[id] then diff = diff + 1 end end
  for id in pairs(pIds) do if not wIds[id] then diff = diff + 1 end end
  ok(diff == 0, "best-value classes and the walkthrough count the same requirements (" .. diff .. " differ)")

  -- Item 6: listing fit on equal terms. With every talent known, you never rate above the best
  -- spec of your role, and your own spec as a comparison scores the same as you.
  local LF, UDq = nsQ.ListingFit, nsQ.UD
  local oldIPS = IsPlayerSpell
  IsPlayerSpell = function() return true end
  LF:ClearCache()
  local function lm(specs) local t = {} for i, id in ipairs(specs) do t[i] = { specID = id, role = UDq:GetSpec(id).role, profile = LF.GroupProfile(id) } end return t end
  local eqBad, eqN, addsKnown = 0, 0, 0
  for _, dk in ipairs({ "TempleOfSethraliss", "KingsRest", "RubyLifePools", "AltarOfFangs" }) do
    for _, st in ipairs({ { 73 }, { 73, 256 }, { 73, 256, 63 } }) do
      for id in pairs(UDq.specs) do
        local known = { specID = id, profile = LF:PlayerProfile(id), isPlayer = true, label = "You", role = UDq:GetSpec(id).role }
        local asSpec = { specID = id, profile = LF.GroupProfile(id), isPlayer = true, label = "You", role = UDq:GetSpec(id).role }
        local r1 = LF:Evaluate(lm(st), dk, known, set, 12, "title")
        local r2 = LF:Evaluate(lm(st), dk, asSpec, set, 12, "title")
        eqN = eqN + 1
        if r1.score ~= r2.score or r1.gain > r1.best + 1e-6 then eqBad = eqBad + 1 end
        if #r1.adds + #r1.maybeAdds > #r2.adds + #r2.maybeAdds then addsKnown = addsKnown + 1 end
      end
    end
  end
  IsPlayerSpell = oldIPS
  LF:ClearCache()
  ok(eqN > 400 and eqBad == 0, "listing: your known talents never change the rating or lift you above the best spec (" .. eqBad .. " of " .. eqN .. ")")
  ok(addsKnown > 0, "listing: \"You'd add\" still counts your known talents (" .. addsKnown .. " cases add more)")
  -- Bloodlust: the comparison specs get it assumed like you do (a Hunter's pet Bloodlust).
  local hunter = LF:Evaluate(lm({ 73, 256, 63 }), "AltarOfFangs", { specID = 253, profile = LF.GroupProfile(253), isPlayer = true, role = "DAMAGER" }, set)
  ok(hunter.gain <= hunter.best + 1e-6, "listing: Bloodlust assumed on both sides")

  UIq:Hide()
  C_LFGList.InviteApplicant = nil
  LISTING, APPLICANTS, APPLICANT_STATUS = nil, {}, nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
end

-- 58b. Code review fixes (1.2.1): chat posts never cut, secret-value guards in run-time paths,
-- /ens verify coverage, reset wording and session state
do
  EnsembleDB = nil
  local nsV = boot()
  local Util, AS, BC, Av, UDv = nsV.Util, nsV.Assignments, nsV.BossCards, nsV.Analysis, nsV.UD
  local set = nsV.db.settings
  local function squash(t) return (t:gsub("%s+", "")) end

  -- Util.ChatWrap: never loses text, never over the limit, never splits a UTF-8 character.
  local long = string.rep("abcdefghij", 60)
  local w = Util.ChatWrap("P: ", long, "P (cont.): ", 250)
  local joined, over = "", 0
  for i, l in ipairs(w) do
    if #l > 250 then over = over + 1 end
    joined = joined .. l:sub((i == 1 and #"P: " or #"P (cont.): ") + 1)
  end
  ok(#w == 3 and over == 0 and joined == long, "ChatWrap: a 600-character word is carried over, nothing lost")
  local utf = string.rep("\195\169", 300)   -- "é" x 300
  local bad = 0
  for _, l in ipairs(Util.ChatWrap("", utf, "", 101)) do
    local b = l:byte(1); if b and b >= 128 and b < 192 then bad = bad + 1 end
    local e = l:byte(#l); if e == 195 then bad = bad + 1 end
  end
  ok(bad == 0, "ChatWrap: never splits a UTF-8 character")
  local list = {}
  for i = 1, 40 do list[i] = "Cast number " .. i .. " [Some Mob]" end
  local ww = Util.ChatWrap("Ann: KICK ", table.concat(list, ", ") .. ".", "Ann (cont.): ", 250)
  local all = table.concat(ww, " ")
  local missing = 0
  for i = 1, 40 do if not all:find("Cast number " .. i .. " [Some Mob]", 1, true) then missing = missing + 1 end end
  ok(#ww > 1 and missing == 0 and ww[2]:find("^Ann %(cont%.%): Cast number"), "ChatWrap: breaks between items, continuation names the player")

  -- Assignments post: every player's whole line survives (random planner groups, every
  -- dungeon, both styles), no line over 255 and none ends in "...".
  local seed = 12345
  local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return (seed % n) + 1 end
  local byRole = { TANK = UDv:SpecsForRole("TANK"), HEALER = UDv:SpecsForRole("HEALER"), DAMAGER = UDv:SpecsForRole("DAMAGER") }
  local groups, cut, lost, longest, extra = 0, 0, 0, 0, 0
  local function checkPlan(plan, style)
    local lines = AS:ChatLines(plan, "Dungeon", style)
    local byName = {}
    for _, l in ipairs(lines) do
      longest = math.max(longest, #l)
      if #l > 255 or l:find("%.%.%.$") then cut = cut + 1 end
    end
    for _, job in ipairs(AS:PlayerJobs(plan)) do
      local name = AS.ShortName(job.label)
      local body = ""
      for _, l in ipairs(lines) do
        if l:sub(1, #name + 2) == name .. ": " then body = body .. l:sub(#name + 3)
        elseif l:sub(1, #name + 10) == name .. " (cont.): " then body = body .. l:sub(#name + 11); extra = extra + 1 end
      end
      if squash(body) ~= squash(AS:JobText(job, style)) then lost = lost + 1 end
    end
  end
  for g = 1, 240 do
    local dk = nsV.Dungeons.order[rnd(#nsV.Dungeons.order)]
    local specs = { byRole.TANK[rnd(#byRole.TANK)], byRole.HEALER[rnd(#byRole.HEALER)] }
    for _ = 1, 3 do specs[#specs + 1] = byRole.DAMAGER[rnd(#byRole.DAMAGER)] end
    local mem = {}
    for i, id in ipairs(specs) do mem[i] = { specID = id, label = "P" .. i .. "-Realm" } end
    local plan = AS:Build(Av:Analyze(mem, dk, set))
    checkPlan(plan, g % 2 == 0 and "short" or "full")
    groups = groups + 1
  end
  -- And a plan built to overflow: one player owns many casts with mob names and backups.
  local kicks = {}
  for i = 1, 14 do
    kicks[i] = { severity = "high", cast = "Very Dangerous Cast " .. i, req = { source = "Cast " .. i .. " (Enemy Caster Number " .. i .. ")" },
      kickers = { { index = 1, label = "Ann-Realm", ability = "Kick", cd = 15 } }, backup = { index = 2, label = "Bob-Realm" } }
  end
  local bigPlan = { kicks = kicks, dispels = {}, labels = { "Ann-Realm", "Bob-Realm" }, empty = false }
  checkPlan(bigPlan, "full")
  ok(groups == 240 and cut == 0 and lost == 0, string.format("assignments post: %d groups, %d lines cut, %d players lost text (longest %d)", groups, cut, lost, longest))
  ok(extra > 0, "assignments post: an overlong line goes on as \"Name (cont.):\" (" .. extra .. " continuation lines)")

  -- Boss cards: every role line kept whole, even with a long edit.
  local realLines = BC.Lines
  BC.Lines = function(self, dk, i)
    local out = {}
    for k, l in ipairs(realLines(self, dk, i)) do out[k] = l end   -- (the real list is cached: copy it)
    out[#out + 1] = { role = "ALL", text = string.rep("Stand in the swirl then move out. ", 14) }
    return out
  end
  local bcCut, bcLost = 0, 0
  for _, dk in ipairs(nsV.Dungeons.order) do
    for i = 1, #BC:Bosses(dk) do
      local lines = BC:ChatLines(dk, i)
      local want = ""
      for _, role in ipairs(nsV.BossData.ROLES) do
        for _, l in ipairs(BC:Lines(dk, i)) do if l.role == role then want = want .. l.text end end
      end
      local head = "[Ensemble] " .. BC:Boss(dk, i).name .. " - "
      local got = ""
      for _, l in ipairs(lines) do
        if #l > 255 or l:find("%.%.%.$") then bcCut = bcCut + 1 end
        if l:sub(1, #head) == head then l = l:sub(#head + 1) end
        got = got .. (l:gsub("^%u+: ", ""))
      end
      if squash(got) ~= squash(want) then bcLost = bcLost + 1 end
    end
  end
  BC.Lines = realLines
  ok(bcCut == 0 and bcLost == 0, "boss card posts: nothing cut (" .. bcCut .. ") or lost (" .. bcLost .. ")")

  -- Gaps post: a long list goes on to a second line.
  local realSN = Av.StillNeeded
  Av.StillNeeded = function()
    local t = {}
    for i = 1, 30 do t[i] = { title = "Need number " .. i, status = i % 3 == 0 and "thin" or "missing", sources = {} } end
    return t
  end
  nsV.UI:Show("composition"); RunTimers()
  local gl = nsV.UI:GapsLines({ dungeon = { key = "KingsRest" }, filled = 3 })
  Av.StillNeeded = realSN
  local gall, gbad = table.concat(gl, " "), 0
  for _, l in ipairs(gl) do if #l > 255 or l:find("%.%.%.$") then gbad = gbad + 1 end end
  local gmiss = 0
  for i = 1, 30 do if not gall:find("Need number " .. i .. "[,%.]") then gmiss = gmiss + 1 end end
  ok(#gl > 1 and gbad == 0 and gmiss == 0 and gl[2]:find("(cont.)", 1, true), "gaps post: " .. #gl .. " lines, nothing cut or lost")
  -- Bloodlust line in the assignments post: carried on, not cut at 255.
  local realLust = nsV.Walkthrough.LustChat
  nsV.Walkthrough.LustChat = function() return "Lust: " .. string.rep("Boss with a long name (on pull) > ", 10) .. "last boss" end
  local pl = nsV.UI:PlanChatLines(bigPlan, "KingsRest")
  nsV.Walkthrough.LustChat = realLust
  local lustTxt = ""
  for _, l in ipairs(pl) do if l:find("^Lust") then lustTxt = lustTxt .. l end end
  ok(lustTxt:find("last boss", 1, true) and pl[3]:find("^Lust %(cont%.%)"), "Bloodlust line carried on, not cut")

  -- Secret values (the route's enemy-forces reads went with route tracking in 1.3.0).
  local SECRET = {}
  local function mark(v) local t = { v = v }; SECRET[t] = true; return t end
  issecretvalue = function(v) return SECRET[v] == true end
  -- Secret values: roster reads (class and spec hidden for party1 -> spec pending, no error).
  local T = nsV.Tracker
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H58", name = "Hal", class = "PRIEST", role = "HEALER" },
  }
  INSPECT_CACHE = {}
  local realClass, realRole = UnitClass, UnitGroupRolesAssigned
  local sClass, sRole = mark("PRIEST"), mark("HEALER")
  UnitClass = function(u) if u == "party1" then return "Priest", sClass end return realClass(u) end
  UnitGroupRolesAssigned = function(u) if u == "party1" then return sRole end return realRole(u) end
  T.secretReads = 0
  local okScan = pcall(T.Rescan, T)
  local hal
  for _, m in ipairs(T.members) do if m.name == "Hal" then hal = m end end
  ok(okScan and hal and hal.pending and hal.classFile == nil and hal.role == "NONE" and T.secretReads >= 2,
    "roster: secret class and role read as unknown (" .. tostring(T.secretReads) .. " hidden reads)")
  UnitClass, UnitGroupRolesAssigned = realClass, realRole
  -- The rescan timer contains its own errors.
  T:Acquire("test58")
  local realExists = UnitExists
  UnitExists = function() error("client error") end
  T.rescanErrors = 0
  T:RequestUpdate(0)
  local okTimer = pcall(RunTimers)
  UnitExists = realExists
  ok(okTimer and T.rescanErrors == 1 and T.lastRescanError:find("client error", 1, true), "roster: a rescan error inside the timer is contained and counted")
  -- Secret values: the inspect path (INSPECT_READY, PLAYER_SPECIALIZATION_CHANGED, the inspect
  -- timer). A hidden GUID or spec must never error and never be stored as a key.
  local trk
  for _, fr in ipairs(ALLFRAMES) do if fr._events.INSPECT_READY then trk = fr end end
  local realGUID, realInsp = UnitGUID, GetInspectSpecialization
  local sGuid = mark("H58")
  local okReady = pcall(trk._scripts.OnEvent, trk, "INSPECT_READY", sGuid)
  ok(okReady, "inspect: a hidden GUID in INSPECT_READY is ignored, no error")
  UnitGUID = function(u) if u == "party1" then return mark("H58") end return realGUID(u) end
  local okSpec = pcall(trk._scripts.OnEvent, trk, "PLAYER_SPECIALIZATION_CHANGED", "party1")
  ok(okSpec, "inspect: a hidden GUID on a spec change is ignored, no error")
  local okReady2 = pcall(trk._scripts.OnEvent, trk, "INSPECT_READY", "H58")
  ok(okReady2, "inspect: a party member whose GUID is hidden matches nothing, no error")
  UnitGUID = realGUID
  GetInspectSpecialization = function() return mark(256) end
  local okReady3 = pcall(trk._scripts.OnEvent, trk, "INSPECT_READY", "H58")
  ok(okReady3, "inspect: a hidden spec from GetInspectSpecialization is ignored, no error")
  GetInspectSpecialization = realInsp
  -- The inspect timer contains its own errors and counts them.
  T.rescanErrors = 0
  local realCan = CanInspect
  CanInspect = function() error("inspect client error") end
  NOW = (NOW or 0) + 10   -- past INSPECT_TIMEOUT, so an earlier pending inspect is dropped
  ROSTER.party2 = { guid = "NEW58", name = "Newcomer", class = "MAGE", role = "DAMAGER" }  -- spec unknown: queued for inspect
  T:Rescan()
  local okInsp = pcall(RunTimers)
  CanInspect = realCan
  ROSTER.party2 = nil
  ok(okInsp and T.rescanErrors >= 1 and T.lastRescanError:find("inspect client error", 1, true),
    "inspect: an error inside the inspect timer is contained and counted")
  T.rescanErrors = 1
  -- /ens verify reports both, and the guarded functions it didn't list before (item 10).
  T.secretReads = 3
  ACTIVE_CHALLENGE = 249
  local realLead, realSB = UnitIsGroupLeader, C_SpellBook
  UnitIsGroupLeader, C_SpellBook = nil, nil
  local realIPS = IsPlayerSpell
  IsPlayerSpell = nil
  local text = nsV.Verify:Build()
  IsPlayerSpell, UnitIsGroupLeader, C_SpellBook = realIPS, realLead, realSB
  ok(text:find("party reads hidden by the game (secret values): 3", 1, true) and text:find("roster scans or inspects that errored: 1", 1, true),
    "verify: roster secret reads and contained errors reported")
  for _, name in ipairs({ "C_ChallengeMode.GetOverallDungeonScore", "C_ChatInfo.InChatMessagingLockdown", "UnitIsGroupAssistant",
                          "C_MythicPlus.RequestMapInfo" }) do
    ok(text:find(name .. " present", 1, true) or text:find(name .. " missing: ", 1, true), "verify reports " .. name)
  end
  ok(text:find("[WARN] UnitIsGroupLeader missing: the Invite buttons", 1, true)
    and text:find("[WARN] IsPlayerSpell / C_SpellBook.IsSpellKnown missing: your talents can't be read", 1, true),
    "verify: a missing guarded function says what it costs")
  issecretvalue, ACTIVE_CHALLENGE = nil, nil
  T:Release("test58")
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }

  -- Reset: the prompt and Settings > Data name everything that's wiped; session state clears.
  PRINTED = ""
  SlashCmdList.ENSEMBLE("reset")
  local wipes = { "saved comps", "every setting", "run history", "boss-card edits", "Bloodlust timing" }
  local allNamed = true
  for _, wd in ipairs(wipes) do if not PRINTED:find(wd, 1, true) then allNamed = false end end
  ok(allNamed and PRINTED:find("can't be undone", 1, true), "/ens reset names everything it wipes")
  nsV.UI:Show("settings"); RunTimers()
  local note
  for _, fr in ipairs(ALLFRAMES) do
    local t = rawget(fr, "_text")
    if type(t) == "string" and t:find("Can't be undone", 1, true) and t:find("Wipes ", 1, true) then note = t end
  end
  local noteOK = note ~= nil
  for _, wd in ipairs(wipes) do if not (note and note:find(wd, 1, true)) then noteOK = false end end
  ok(noteOK, "Settings > Data names everything a reset wipes: " .. tostring(note))
  local helpOK = true
  PRINTED = ""
  SlashCmdList.ENSEMBLE("help")
  for _, wd in ipairs(wipes) do if not PRINTED:find(wd, 1, true) then helpOK = false end end
  ok(helpOK, "/ens help's reset line names everything it wipes")
  AS.overrides = { X = { kind = "kick", who = {} } }
  BC.state = { dk = "KingsRest", index = 3, killed = { [1] = true, [2] = true } }
  SlashCmdList.ENSEMBLE("reset confirm")
  ok(next(AS.overrides) == nil and next(BC.state.killed) == nil and BC.state.index == 1 and nsV.db.bossProgress and next(nsV.db.bossProgress.killed) == nil,
    "reset clears assignments chosen by hand and boss progress")
  BC.state = { killed = {} }
  nsV.UI:Hide()
end

-- 59. Release packaging: the license inside the addon folder matches the repo's, and the TOC
-- carries the project IDs the release workflow uploads to.
do
  local function slurp(path) local f = io.open(path, "rb"); if not f then return nil end local t = f:read("*a"); f:close(); return t end
  local inFolder, root = slurp(ADDON_DIR .. "/LICENSE.txt"), slurp(ADDON_DIR .. "/../LICENSE")
  ok(inFolder and root and inFolder == root, "Ensemble/LICENSE.txt is an exact copy of LICENSE")
  local toc = slurp(ADDON_DIR .. "/Ensemble.toc") or ""
  ok(toc:find("\n## X%-Curse%-Project%-ID: 1745945") ~= nil, "TOC has the CurseForge project ID")
  -- Not published to Wago since October 24, 2026: no Wago ID, so the packager never uploads there.
  ok(not toc:find("X%-Wago%-ID"), "TOC has no Wago project ID")
end

-- 60. Plan tab (1.3.0 issues #5, #6, #7, #9), the issue's own case: Den of Nalorakk +17 with
-- Veng DH, Resto Shaman, Demo Warlock, Arcane Mage and Arms Warrior in the planner.
do
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 71, role = "DAMAGER" } }
  CURRENT_AFFIXES = { 158, 10, 9, 147 }
  local ns60 = boot()
  local function d60(L) local t = {} for i = 1, L.used do t[#t + 1] = L.pool[i]:GetText() end return table.concat(t, "\n") end
  ns60.Affixes:Refresh()
  ns60.state.keyLevelOverride = 17
  ns60.db.currentComp = { 581, 264, 266, 62, 71 }
  ns60:SetManualDungeon("DenOfNalorakk")
  ns60.UI:Show("plan"); RunTimers()
  local pl = ns60.UI.pl
  local t = d60(pl.list)
  -- #6: medium casts (Earth Bolt, Scavenge; the Magic dispels) are on the sheet with their assignments.
  local rows = ns60.UI:CheatSheetRows("DenOfNalorakk")
  local where = {}
  for _, row in ipairs(rows) do for i, req in ipairs(row.reqs) do where[req.id] = { cat = row.cat, i = i, n = #row.reqs } end end
  ok(where.DN_EARTH_BOLT and where.DN_EARTH_BOLT.cat == "interrupts" and where.DN_SPARE and where.DN_SPARE.cat == "interrupts",
    "#6: Earth Bolt and Scavenge are under KICK")
  ok(where.DN_GLACIAL_TORMENT and where.DN_CRYO_SURGE and where.DN_GLACIAL_TORMENT.cat == "dispels",
    "#6: Glacial Torment and Cryo Surge are under DISPEL")
  ok(where.DN_BREEZE_PURGE == nil, "#6: low severity stays off the sheet")
  ok(t:find("Glacial Torment", 1, true) and t:find("Cryo Surge", 1, true), "#6: the Magic dispel list is shown")
  -- Past five in a category, the rest fold behind "+N more" (nothing dropped).
  local kick = where.DN_EARTH_BOLT
  if kick.n > 5 then
    ok(t:find("more cast", 1, true), "#6: a long KICK list folds behind +N more")
  else
    ok(t:find("Earth Bolt", 1, true), "#6: Earth Bolt shown")
  end
  -- Every assignment the player has ("Your assignments") can be found on the sheet.
  local jobsAll = ns60.Assignments:PlayerJobs(ns60.UI.cp.lastPlan, false)
  local onSheet, counted = true, 0
  for _, j in ipairs(jobsAll) do
    for _, list in ipairs({ j.kicks, j.dispels, j.backups }) do
      for _, e in ipairs(list) do
        local id = e.row and e.row.req and e.row.req.id
        if id and not id:find("^AFFIX") then counted = counted + 1; if not where[id] then onSheet = false; print("not on sheet: " .. id) end end
      end
    end
  end
  ok(onSheet and counted > 0, "#6: every assigned kick, dispel and backup has its cast on the sheet (" .. counted .. ")")
  -- #7: Xal'atath's Guile's two lines name their need.
  ok(t:find("Group defensives:|r Xal'atath's Guile", 1, true) and t:find("Externals:|r Xal'atath's Guile", 1, true),
    "#7: each Guile line names its need")
  -- #5: titles.
  ok(pl.rightTitle:GetText() == "ASSIGNMENTS: DEN OF NALORAKK" and not t:find("ASSIGNMENTS: DEN OF NALORAKK", 1, true), "#5: one assignments heading")
  ok(pl.leftTitle:GetText() == "YOUR PLAN" and d60(pl.mine):find("YOUR ASSIGNMENTS", 1, true), "#5: Your plan panel keeps its Your assignments section")
  -- The Dungeon tab's sheet keeps its own header (it has no panel title naming the dungeon).
  ns60.UI:Show("dungeons"); RunTimers()
  ok(d60(ns60.UI.pp.value):find("KEY NEEDS: DEN OF NALORAKK", 1, true), "#5: Dungeon tab keeps its Key needs header")
  -- #9: buttons enable with a group and disable (with the reason) without one.
  ns60.UI:Show("plan"); RunTimers()
  ok(pl.postPlanBtn:IsEnabled() and pl.postGapsBtn:IsEnabled(), "#9: both Post buttons on with a group")
  ns60.db.currentComp = { 0, 0, 0, 0, 0 }; ns60.UI:Refresh(); RunTimers()
  ok(not pl.postPlanBtn:IsEnabled() and pl.postPlanBtn.tooltip == "Add players first." and not pl.postGapsBtn:IsEnabled()
    and pl.postGapsBtn:GetAlpha() < 1, "#9: off without players, tooltip says why")
  ns60.db.settings.chatStyle = "short"; ns60.UI:Refresh(); RunTimers()
  ok(pl.chatStyleBtn.text:GetText() == "Chat style: short", "#9: chat style link follows the setting")
  pl.chatStyleBtn:Click(); RunTimers()
  ok(ns60.UI.currentTab == "settings", "#9: the chat style link opens Settings")
  ns60.state.keyLevelOverride = nil
  CURRENT_AFFIXES = {}
  ns60.UI:Hide()
end

-- 61. Boss order where the data allows a choice (1.3.0): The Blinding Vale's first two bosses.
do
  EnsembleDB = { bossOrder = { TheBlindingVale = { 2, 1, 3, 4 }, KingsRest = { 2, 1, 3, 4 },
    MurderRow = "bad", AltarOfFangs = { 1, 2 } } }
  local ns61 = boot()
  local DD61, BC, WT = ns61.Dungeons, ns61.BossCards, ns61.Walkthrough
  local function d61(L) local t = {} for i = 1, L.used do t[#t + 1] = L.pool[i]:GetText() end return table.concat(t, "\n") end
  -- Data: only The Blinding Vale has a choice (Method.gg); the rest are fixed.
  local withChoice = {}
  for dk in pairs(DD61.BOSS_ORDER) do withChoice[#withChoice + 1] = dk end
  ok(#withChoice == 1 and DD61.BOSS_ORDER.TheBlindingVale[1][1] == 1 and DD61.BOSS_ORDER.TheBlindingVale[1][2] == 2
    and not DD61.BOSS_ORDER.TheBlindingVale[1].sharedTrash, "data: Blinding Vale's first two bosses, separate paths; no other dungeon")
  -- Validation of the data and of saved orders.
  ok(DD61:BossOrderGroupOK("TheBlindingVale", { 2, 3 }) and not DD61:BossOrderGroupOK("TheBlindingVale", { 1, 3 })
    and not DD61:BossOrderGroupOK("TheBlindingVale", { 4, 5 }) and not DD61:BossOrderGroupOK("TheBlindingVale", { 2 }),
    "group check: next to each other, in range, at least two")
  DD61.BOSS_ORDER.KingsRest = { { 1, 3 }, { 2, 3 } }
  local probs = table.concat(DD61:Validate(), " ")
  ok(probs:find("KingsRest:BOSS_ORDER", 1, true) and #DD61.BOSS_ORDER.KingsRest == 1 and DD61.BOSS_ORDER.KingsRest[1][1] == 2,
    "invalid groups dropped and reported, valid ones kept")
  DD61.BOSS_ORDER.KingsRest = nil
  ok(DD61:ValidBossOrder("TheBlindingVale", { 2, 1, 3, 4 }) and not DD61:ValidBossOrder("TheBlindingVale", { 1, 3, 2, 4 })
    and not DD61:ValidBossOrder("TheBlindingVale", { 1, 2, 3 }) and not DD61:ValidBossOrder("TheBlindingVale", { 1, 1, 3, 4 })
    and not DD61:ValidBossOrder("KingsRest", { 2, 1, 3, 4 }), "saved orders checked against the data")
  ok(ns61.db.bossOrder.TheBlindingVale and ns61.db.bossOrder.KingsRest == nil and ns61.db.bossOrder.MurderRow == nil
    and ns61.db.bossOrder.AltarOfFangs == nil, "on load: a fitting order kept, the rest dropped")
  -- Moving bosses.
  ns61.db.bossOrder = {}
  ok(BC:Neighbor("TheBlindingVale", 2, -1) == 1 and BC:Neighbor("TheBlindingVale", 3, -1) == nil and BC:Neighbor("TheBlindingVale", 1, -1) == nil,
    "only bosses in the same group can swap")
  ok(not BC:MoveBoss("KingsRest", 2, -1) and ns61.db.bossOrder.KingsRest == nil, "a fixed dungeon can't be reordered")
  local fired = 0
  ns61:On("BOSS_ORDER_CHANGED", function() fired = fired + 1 end)
  ok(BC:MoveBoss("TheBlindingVale", 2, -1) and fired == 1, "Ikuzz moved first")
  local o = BC:Order("TheBlindingVale")
  ok(o[1] == 2 and o[2] == 1 and o[3] == 3 and o[4] == 4 and BC:Position("TheBlindingVale", 2) == 1 and BC:IsCustomOrder("TheBlindingVale"),
    "order saved: Ikuzz, Trinity, Ruia, Ziekket")
  -- Walkthrough: each trash section moves with its boss; nothing is lost.
  local w = WT:Build("TheBlindingVale")
  local seq = {}
  for _, st in ipairs(w.steps) do if st.kind ~= "anywhere" then seq[#seq + 1] = st.kind:sub(1, 1) .. st.boss end end
  ok(table.concat(seq, ",") == "t2,b2,t1,b1,t3,b3,t4,b4", "walkthrough in your order: " .. table.concat(seq, ","))
  local t1
  for _, st in ipairs(w.steps) do if st.kind == "trash" and st.boss == 1 then t1 = st end end
  local ids = {} for _, q in ipairs(t1.reqs) do ids[q.id] = true end
  ok(ids.BV_SPORE_SPINES and t1.pos == 2, "the Trinity's trash stays with the Trinity, now second")
  local seen = {}
  for _, st in ipairs(w.steps) do for _, q in ipairs(st.reqs) do seen[q.id] = true end end
  local lost = {}
  for _, q in ipairs(DD61.list.TheBlindingVale.requirements) do if not q.invalid and not seen[q.id] then lost[#lost + 1] = q.id end end
  ok(#lost == 0, "every requirement still shows: " .. table.concat(lost, ","))
  -- Bloodlust: spots and numbering follow the order.
  local spots = WT:Spots("TheBlindingVale")
  ok(spots[1].label == "Trash before Ikuzz the Light Hunter" and spots[2].at == "b2" and spots[3].at == "t1", "Bloodlust spots in your order")
  WT:SetLustAt("TheBlindingVale", 1, "b1"); WT:SetLustAt("TheBlindingVale", 2, "b2")
  local uses = WT:Lust("TheBlindingVale")
  ok(uses[1].at == "b2", "lust numbering: Ikuzz's lust is #1 when Ikuzz is first")
  BC:MoveBoss("TheBlindingVale", 1, -1)   -- back to the guides' order
  uses = WT:Lust("TheBlindingVale")
  ok(ns61.db.bossOrder.TheBlindingVale == nil and uses[1].at == "b1" and fired == 2, "the guides' order again: entry cleared, lusts re-sorted")
  WT:ResetLust("TheBlindingVale")
  BC:MoveBoss("TheBlindingVale", 2, -1)
  local def = WT:Lust("TheBlindingVale")
  local ranks = {}
  for i, u in ipairs(def) do ranks[i] = BC:Position("TheBlindingVale", tonumber(u.at:sub(2))) end
  local sorted = true
  for i = 2, #ranks do if ranks[i] < ranks[i - 1] then sorted = false end end
  ok(sorted and #def == #ns61.Dungeons.LUST.TheBlindingVale and ns61.db.lust.TheBlindingVale == nil, "the default plan is shown in your order, unsaved")
  WT:SetLustAt("TheBlindingVale", 1, "t2")
  ok(ns61.db.lust.TheBlindingVale and ns61.db.lust.TheBlindingVale[1].at == "t2", "editing copies the plan in the order shown")
  WT:ResetLust("TheBlindingVale")
  -- Boss window: first boss and next boss follow the order.
  ns61.BossWindow.view = { dk = "TheBlindingVale" }   -- /ens boss The Blinding Vale
  ok(select(2, ns61.BossWindow:Current()) == 2, "boss window outside the dungeon starts on your first boss")
  ns61.BossWindow:Open("TheBlindingVale")
  ok(select(2, ns61.BossWindow:Current()) == 2, "/ens boss <dungeon> opens on your first boss")
  ns61.BossWindow:Hide()
  ns61.BossWindow.view = {}
  BC.state = { dk = "TheBlindingVale", killed = {} }
  BC:NewRun()
  ok(BC.state.index == 2, "a new key starts on your first boss")
  BC:OnEncounterEnd(nil, "Ikuzz the Light Hunter", 8, 5, 1)
  ok(BC.state.index == 1, "after Ikuzz dies, the window turns to the Trinity")
  BC:OnEncounterEnd(nil, "Lightblossom Trinity", 8, 5, 1)
  ok(BC.state.index == 3, "then Ruia")
  BC.state.index = 2; BC:Step(1)
  ok(BC.state.index == 1, "paging follows your order")
  ns61.BossWindow:Show()
  ok(ns61.BossWindow.title:GetText():find("Lightblossom Trinity", 1, true) and ns61.BossWindow.title:GetText():find("2/4", 1, true),
    "boss window title numbers the boss by your order")
  ns61.BossWindow:Hide()
  BC.state = { killed = {} }
  -- Dungeon tab: move and reset controls, only where the data allows.
  ns61.UI:Show("dungeons"); ns61.UI:SetPrimerPick("TheBlindingVale"); ns61.UI:Refresh(); RunTimers()
  local L = ns61.UI.pp.walk
  local tx = d61(L)
  ok(tx:find("1. IKUZZ THE LIGHT HUNTER", 1, true) and tx:find("Boss order: yours, Ikuzz the Light Hunter first.", 1, true),
    "walkthrough numbers bosses by your order and says the order is yours")
  local function btn(pattern)
    for i = 1, L.used do
      if L.pool[i]:GetText():find(pattern, 1, true) then
        for j = 1, L.bused do
          local b = L.bpool[j]
          if b:IsShown() and rawget(b, "_point") and L.pool[i]._point and b._point[5] == L.pool[i]._point[5] + 2 then return b end
        end
      end
    end
  end
  local later = btn("> Move later|r")
  ok(tx:find("Move later|r|cff", 1, true) and tx:find("(after Lightblossom Trinity)", 1, true) and tx:find("(before Ikuzz the Light Hunter)", 1, true),
    "move lines name the boss they swap with")
  ok(later ~= nil, "move line is clickable")
  if later then later:Click(); RunTimers() end
  ok(ns61.db.bossOrder.TheBlindingVale == nil, "Move later puts Ikuzz back second")
  BC:MoveBoss("TheBlindingVale", 2, -1); ns61.UI:Refresh(); RunTimers()
  local reset = btn("> Reset to the guides' order")
  ok(reset ~= nil, "reset line shown with your own order")
  if reset then reset:Click(); RunTimers() end
  ok(ns61.db.bossOrder.TheBlindingVale == nil and not d61(L):find("Boss order: yours", 1, true), "reset to the guides' order")
  ns61.UI:SetPrimerPick("KingsRest"); ns61.UI:Refresh(); RunTimers()
  ok(not d61(L):find("> Move ", 1, true), "fixed-order dungeon: no move lines")
  -- sharedTrash (no current dungeon has it): the group's trash becomes one section before it.
  DD61.BOSS_ORDER.KingsRest = { { 2, 3, sharedTrash = true } }
  w = WT:Build("KingsRest")
  local plain = {}
  for _, st in ipairs(w.steps) do if st.kind ~= "anywhere" then plain[#plain + 1] = st.kind:sub(1, 1) .. st.boss end end
  ok(table.concat(plain, ",") == "t1,b1,t2,b2,t3,b3,t4,b4", "shared path in the guides' order: sections as usual")
  BC:MoveBoss("KingsRest", 3, -1)
  w = WT:Build("KingsRest")
  local seq2, mergedSt = {}, nil
  for _, st in ipairs(w.steps) do
    if st.kind ~= "anywhere" then seq2[#seq2 + 1] = st.kind:sub(1, 1) .. st.boss .. (st.merged and "m" or "") end
    if st.merged then mergedSt = st end
  end
  ok(table.concat(seq2, ",") == "t1,b1,t3m,b3,b2,t4,b4", "shared path reordered: one trash section before the group: " .. table.concat(seq2, ","))
  local mids = {} for _, q in ipairs(mergedSt.reqs) do mids[q.id] = true end
  ok(mids.KR_UNHOLY_MENDING and mids.KR_HEX, "the merged section holds both bosses' trash")
  WT:SetLustAt("KingsRest", 1, "t2")
  ok(#WT:LustAt("KingsRest", mergedSt) == 1, "a lust before either boss shows in the merged section")
  WT:ResetLust("KingsRest")
  ns61.UI:Refresh(); RunTimers()
  ok(d61(L):find("TRASH BEFORE THE COUNCIL OF TRIBES AND MCHIMBA THE EMBALMER", 1, true), "merged header names the group")
  DD61.BOSS_ORDER.KingsRest = nil
  ns61.db.bossOrder.KingsRest = nil
  -- Reset wipes the order with everything else.
  BC:MoveBoss("TheBlindingVale", 2, -1)
  ok(ns61.RESET_WIPES:find("boss order", 1, true), "reset names the boss order")
  ns61:ResetDB()
  ok(next(ns61.db.bossOrder) == nil and not BC:IsCustomOrder("TheBlindingVale"), "reset clears the boss order")
  ns61.UI:Hide()
end

-- 62. Sources window and the Bloodlust default line (1.3.0)
do
  EnsembleDB = nil
  local ns62 = boot()
  local DD62, UI62 = ns62.Dungeons, ns62.UI
  -- The list: grouped by use, one link per site's guide index, https only.
  local groups, total = {}, 0
  for _, g in ipairs(DD62.SOURCES) do
    groups[#groups + 1] = g.group
    for _, it in ipairs(g.items) do
      total = total + 1
      ok(type(it.url) == "string" and it.url:find("^https://[%w%.%-]+/") and not it.url:find("%s"), "source link is a plain https URL: " .. tostring(it.url))
    end
  end
  ok(table.concat(groups, "|") == "Dungeons and boss cards|Classes and specs|Hotfix checks" and total == 6, "three groups, six links")
  local all = ""
  for _, g in ipairs(DD62.SOURCES) do for _, it in ipairs(g.items) do all = all .. it.name .. " " .. it.url .. "\n" end end
  ok(all:find("method.gg", 1, true) and all:find("icy-veins.com", 1, true) and all:find("wowhead.com/guides/dungeons", 1, true)
    and all:find("raider.io", 1, true) and all:find("wowhead.com/guides/classes", 1, true) and all:find("blizzard.com", 1, true),
    "Method.gg, Icy Veins, Wowhead (dungeons and classes), Raider.IO, Blizzard")
  ok(not all:lower():find("wowcarry", 1, true), "the Bloodlust timing source is not listed")
  -- The Sources window; each link in a read-only box; the footer.
  UI62:ShowSources()
  local p = UI62.sources
  ok(p and p:IsShown() and #p.boxes == 6 and p.boxes[1]:GetText() == DD62.SOURCES[1].items[1].url, "/ens sources opens the window with every link")
  local b = p.boxes[3]
  b:SetText("typed"); b._scripts.OnTextChanged(b, true)
  ok(b:GetText() == DD62.SOURCES[1].items[3].url, "link boxes are read-only (typing restores the link)")
  ok(p.footer:GetText() == "Ensemble isn't affiliated with these sites. Thanks to their authors.", "footer: not affiliated, thanks")
  p:Hide()
  -- Settings > Data button and the Dungeon tab's link.
  UI62:Show("settings"); UI62:ShowSettingsSection("data"); RunTimers()
  ok(UI62.sourcesBtn ~= nil, "Settings > Data has a Sources button")
  UI62.sourcesBtn:Click()
  ok(p:IsShown(), "the Sources button opens the window"); p:Hide()
  UI62:Show("dungeons"); RunTimers()
  local L = UI62.pp.walk
  local srcBtn
  for j = 1, L.bused do if L.bpool[j].tip == "The guides this data comes from" then srcBtn = L.bpool[j] end end
  ok(L.pool[1]:GetText():find("checked against", 1, true) and L.pool[1]:GetText():find("Sources|r", 1, true) and srcBtn,
    "Dungeon tab: Sources link on the data line")
  if srcBtn then srcBtn:Click() end
  ok(p:IsShown(), "the Dungeon tab link opens the window"); p:Hide()
  -- Bloodlust: one line for every dungeon, no source named.
  ok(DD62.LUST_SOURCE == nil, "no per-dungeon Bloodlust source text")
  local same = true
  for _, dk in ipairs(DD62.order) do
    if ns62.Walkthrough:LustSource(dk) ~= "A suggested default. Tanks and routes differ: set your own." then same = false end
  end
  ok(same, "every dungeon's default Bloodlust says it's a suggestion")
  UI62:Hide()
end

-- 63. The Ensemble name (1.3.0): TOC, /ens only, fresh saved data, chat prefix, window
-- subtitle, minimap tooltip, plain party posts, and no old name anywhere in the addon.
do
  local function slurp(path) local f = io.open(path, "rb"); if not f then return nil end local t = f:read("*a"); f:close(); return t end
  local toc = slurp(ADDON_DIR .. "/Ensemble.toc") or ""
  ok(toc:find("\n## Title: Ensemble\r?\n") ~= nil, "TOC title is Ensemble")
  ok(toc:find("\n## SavedVariables: EnsembleDB\r?\n") ~= nil, "TOC saves EnsembleDB only")
  ok(toc:find("A Mythic+ Companion", 1, true) and toc:find("Learn the dungeon. Build the group. Time the key.", 1, true)
    and toc:find("/ens", 1, true), "TOC notes: subtitle, summary and /ens")
  ok(toc:find("Interface\\AddOns\\Ensemble\\Media\\Logo", 1, true) ~= nil, "TOC icon in the Ensemble folder")
  ok(toc:find("AddonCompartmentFunc: Ensemble_OnAddonCompartmentClick", 1, true) ~= nil, "compartment function named in the TOC")
  -- Saved data from the beta under the old name is never read: Ensemble starts fresh.
  KeystoneCommandDB = { settings = { textSize = 110, minimap = { hide = true } } }
  EnsembleDB = nil
  SLASH_KEYSTONECOMMAND1, SlashCmdList.KEYSTONECOMMAND = nil, nil
  local ns63 = boot()
  ok(EnsembleDB == ns63.db and ns63.db.settings.textSize == 100 and not ns63.db.settings.minimap.hide,
    "fresh EnsembleDB; the beta's saved data isn't migrated")
  ok(KeystoneCommandDB.settings.textSize == 110, "the old saved data is left untouched")
  KeystoneCommandDB = nil
  -- /ens is the only command.
  ok(SLASH_ENSEMBLE1 == "/ens" and SLASH_ENSEMBLE2 == nil and type(SlashCmdList.ENSEMBLE) == "function", "/ens registered")
  ok(SLASH_KEYSTONECOMMAND1 == nil and SlashCmdList.KEYSTONECOMMAND == nil, "no /kc")
  -- Only the baseline commands: everything else is done in the interface.
  local H = ns63.SLASH_HELP
  local cmds = {}
  for _, l in ipairs(H) do cmds[#cmds + 1] = l:match("^(/ens[%w ]-) %- ") end
  ok(#H == 7 and table.concat(cmds, ",") == "/ens,/ens minimap,/ens verify,/ens verify season,/ens report,/ens reset confirm,/ens help",
    "/ens help lists only the baseline commands: " .. table.concat(cmds, ","))
  PRINTED = ""
  SlashCmdList.ENSEMBLE("help")
  ok(select(2, PRINTED:gsub("\n", "")) == 7, "/ens help prints seven lines")
  local Tour63 = ns63.Tour
  local dk0, lock0 = ns63.db.selectedDungeon, ns63.db.settings.window.locked
  for _, gone in ipairs({ "tour", "glossary", "sources", "bestkey", "boss", "boss ruby life pools", "lock", "unlock",
      "text 110", "panel dock", "dungeon none", "planner", "party", "composition", "settings", "show", "hide",
      "toggle", "bug", "credits" }) do
    PRINTED = ""
    SlashCmdList.ENSEMBLE(gone)
    ok(PRINTED:find("/ens verify season", 1, true) ~= nil, "/ens " .. gone .. " is gone: prints the help list")
  end
  ok(ns63.db.selectedDungeon == dk0 and ns63.db.settings.window.locked == lock0 and ns63.db.settings.textSize == 100
    and not (Tour63 and Tour63:IsActive()) and not (ns63.BossWindow and ns63.BossWindow:IsShown())
    and not (ns63.UI.glossary and ns63.UI.glossary:IsShown()) and not (ns63.UI.sources and ns63.UI.sources:IsShown()),
    "dropped commands change nothing")
  -- The kept ones still work.
  local hide0 = ns63.db.settings.minimap.hide
  SlashCmdList.ENSEMBLE("minimap"); ok(ns63.db.settings.minimap.hide ~= hide0, "/ens minimap toggles the button")
  SlashCmdList.ENSEMBLE("minimap")
  PRINTED = ""; SlashCmdList.ENSEMBLE("reset")
  ok(PRINTED:find("/ens reset confirm", 1, true) ~= nil, "/ens reset asks for confirm")
  ok(type(Ensemble_OnAddonCompartmentClick) == "function" and type(Ensemble_OnAddonCompartmentEnter) == "function"
    and type(Ensemble_OnAddonCompartmentLeave) == "function", "compartment globals exist")
  -- Chat prefix (D): the emblem as a text-height icon, then "Ensemble:" in white.
  PRINTED = ""
  ns63:Print("hello")
  ok(PRINTED == "|TInterface\\AddOns\\Ensemble\\Media\\LogoMark:0|t |cffffffffEnsemble:|r hello\n", "chat prefix: logo icon, white Ensemble:")
  ok(slurp(ADDON_DIR .. "/Media/LogoMark.tga") ~= nil, "the chat icon's texture ships in the folder")
  -- Window header: white name, subtitle underneath (where the slogan was).
  ns63.UI:Show("composition"); RunTimers()
  ok(ns63.UI.titleText:GetText() == "Ensemble" and ns63.UI.titleText._color and ns63.UI.titleText._color[1] > 0.9
    and ns63.UI.titleText._color[3] > 0.9, "window title: Ensemble in white")
  local sacc, scol = ns63.UI.Kit.C.accent, ns63.UI.subtitleText._color
  ok(ns63.UI.subtitleText:GetText() == "A Mythic+ Companion" and scol and scol[1] == sacc[1] and scol[2] == sacc[2] and scol[3] == sacc[3],
    "window subtitle: A Mythic+ Companion in the accent color")
  -- Minimap tooltip: name in white, subtitle in the accent, then the actions unchanged.
  local lines = {}
  local oldAdd, oldOwner, oldShow = GameTooltip.AddLine, GameTooltip.SetOwner, GameTooltip.Show
  GameTooltip.AddLine = function(_, t, r, g, b) lines[#lines + 1] = { t = t, r = r, g = g, b = b } end
  GameTooltip.SetOwner = function() end
  GameTooltip.Show = function() end
  ns63.UI.minimapButton._scripts.OnEnter(ns63.UI.minimapButton)
  ok(lines[1] and lines[1].t == "Ensemble" and lines[1].r == 1 and lines[1].g == 1 and lines[1].b == 1, "minimap tooltip: Ensemble in white")
  local acc = ns63.UI.Kit.C.accent
  ok(lines[2] and lines[2].t == "A Mythic+ Companion" and lines[2].r == acc[1] and lines[2].b == acc[3], "minimap tooltip: subtitle in the accent blue")
  ok(lines[3] and lines[3].t == "Left-click: toggle   Right-click: settings   Drag: move" and #lines == 3, "minimap tooltip: actions unchanged")
  GameTooltip.AddLine, GameTooltip.SetOwner, GameTooltip.Show = oldAdd, oldOwner, oldShow
  ns63.UI:Hide()
  -- Party posts: the [Ensemble] tag in both chat styles, plain text (no icons or colors).
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  local r = ns63.Analysis:Analyze({ { specID = 250 } }, "TempleOfSethraliss", ns63.db.settings)
  for _, style in ipairs({ "full", "short" }) do
    ns63.db.settings.chatStyle = style
    local gl = ns63.UI:GapsLines(r)
    local plain = true
    for _, l in ipairs(gl) do if l:find("|T", 1, true) or l:find("|c", 1, true) then plain = false end end
    ok(gl[1] and gl[1]:find("^%[Ensemble%] ") and plain, "gaps post (" .. style .. "): [Ensemble], plain text")
  end
  ns63.db.settings.chatStyle = "full"
  -- Bug reports claim only errors from the Ensemble folder itself.
  local OP = ns63.Report.OurPath
  ok(OP("Interface/AddOns/Ensemble/UI.lua:120: attempt to index nil") and OP("Interface\\AddOns\\Ensemble\\Core.lua:5")
    and OP("[string \"@Interface/AddOns/Ensemble/UI.lua\"]:9") and OP("Ensemble/UI.lua:3"), "our error paths recognized")
  ok(not OP("Interface/AddOns/RemixEnsemble/Core.lua:4") and not OP("Interface/AddOns/EnsembleTracker/x.lua:1")
    and not OP("Interface/AddOns/Ensembles/x.lua:1"), "another addon's folder with Ensemble in its name isn't ours")
  -- No old name anywhere in the shipped addon.
  local shipped = { "Ensemble.toc", "LICENSE.txt" }
  for _, f in ipairs(FILES) do shipped[#shipped + 1] = f end
  for _, f in ipairs(shipped) do
    local src = slurp(ADDON_DIR .. "/" .. f) or ""
    local low = src:lower()
    ok(not low:find("keystone command", 1, true) and not low:find("keystonecommand", 1, true)
      and not src:find("/kc[^%w]") and not src:find("[KC]", 1, true) and not src:find("KC1", 1, true)
      and not src:find("Command the key", 1, true), "no old name in " .. f)
  end
end

-- 64. Dungeon tab: "Open boss cards" opens the boss window on the dungeon the tab shows. On
-- Auto the tab follows detection (the dungeon you're in, else your listing, else your key); a
-- hand pick holds until the detected dungeon changes, like the Composition picker.
do
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  OWNED_KEY, OWNED_LEVEL, LISTING, INSTANCE, ACTIVE_CHALLENGE = 249, 12, nil, nil, nil   -- Kings' Rest +12
  local ns64 = boot()
  local UI64, BW64 = ns64.UI, ns64.BossWindow
  ns64.BossCards.state = { killed = {} }   -- not inside a dungeon
  local function note() return UI64.pp.note:GetText() or "" end
  UI64:Show("dungeons"); RunTimers()
  local btn = UI64.pp.bossBtn
  ok(btn and btn.text:GetText() == "Open boss cards" and btn.tooltip and btn.tooltip:find("this dungeon's cards", 1, true),
    "Dungeon tab has an Open boss cards button")
  ok(UI64.primerKey == "KingsRest" and note():find("Auto (your key +12)", 1, true), "Auto: the tab starts on your key: " .. note())
  btn:Click(); RunTimers()
  ok(BW64:IsShown() and BW64.title:GetText():find("The Golden Serpent", 1, true), "opens the detected dungeon's first boss card")
  BW64:Hide(true)
  -- Detection changes while on Auto: a listing beats the key, the zone beats both.
  LISTING = "Temple of Sethraliss (Mythic Keystone)"; UI64:QueueRefresh(); RunTimers()
  ok(UI64.primerKey == "TempleOfSethraliss" and note():find("your listing", 1, true), "Auto follows a new listing")
  INSTANCE = { "Ruby Life Pools", "party" }; UI64:QueueRefresh(); RunTimers()
  ok(UI64.primerKey == "RubyLifePools" and note():find("you're in it", 1, true), "Auto follows the dungeon you're in")
  btn:Click(); RunTimers()
  ok(BW64:IsShown() and BW64.title:GetText():find("Melidrussa", 1, true), "the button opens the followed dungeon")
  BW64:Hide(true)
  INSTANCE, LISTING = nil, nil; UI64:QueueRefresh(); RunTimers()
  ok(UI64.primerKey == "KingsRest", "leaving the dungeon and delisting: back to your key")
  -- A hand pick holds while detection stays the same, and the button follows it.
  UI64:SetPrimerPick("TempleOfSethraliss"); RunTimers()
  ok(UI64.primerKey == "TempleOfSethraliss" and not note():find("Auto", 1, true), "hand pick shown (no Auto note)")
  UI64:QueueRefresh(); RunTimers()
  ok(UI64.primerKey == "TempleOfSethraliss", "the hand pick holds while detection is unchanged")
  btn:Click(); RunTimers()
  ok(BW64:IsShown() and BW64.title:GetText():find("Adderis and Aspix", 1, true), "opens the dungeon picked on the tab")
  btn:Click(); RunTimers()
  ok(BW64:IsShown(), "a second click keeps the window open")
  BW64:Hide(true)
  -- Detection changes: the hand pick ends and the tab follows again.
  OWNED_KEY, OWNED_LEVEL = 588, 10; UI64:QueueRefresh(); RunTimers()   -- a new key: Altar of Fangs
  ok(UI64.primerPick == nil and UI64.primerKey == "AltarOfFangs", "a new key ends the hand pick")
  -- The menu: Auto first (naming what it follows), then every dungeon.
  local items
  local oldShow = UI64.ShowMenu
  UI64.ShowMenu = function(_, _, it) items = it end
  UI64.pp.dungeonBtn:Click()
  UI64.ShowMenu = oldShow
  ok(items and items[1].text:find("Auto: Altar of Fangs", 1, true) and items[1].selected and #items == 1 + #ns64.Dungeons.order,
    "menu: Auto (selected, names the detected dungeon) plus every dungeon")
  items[3].onClick(); RunTimers()
  ok(UI64.primerPick ~= nil and UI64.primerKey == UI64.primerPick, "picking from the menu sets a hand pick")
  UI64.pp.dungeonBtn:Click()
  -- (menu rebuilt; choose Auto again)
  UI64:SetPrimerPick(nil); RunTimers()
  ok(UI64.primerPick == nil and UI64.primerKey == "AltarOfFangs", "Auto goes back to detection")
  -- Nothing detected: the last dungeon shown stays.
  OWNED_KEY, OWNED_LEVEL = nil, nil; UI64:QueueRefresh(); RunTimers()
  ok(UI64.primerKey == "AltarOfFangs", "nothing detected: the tab keeps the last dungeon")
  -- A hand pick on Composition's planner counts, after the zone and listing.
  ns64:SetManualDungeon("DenOfNalorakk", false); UI64:QueueRefresh(); RunTimers()
  ok(UI64.primerKey == "DenOfNalorakk" and note():find("your Composition pick", 1, true), "Auto follows a Composition hand pick")
  ns64:SetManualDungeon("AUTO", false)
  -- "Auto dungeon" off in Settings: no detection, the tab keeps what it shows.
  OWNED_KEY = 249; ns64.db.settings.liveAutoDungeon = false; UI64:QueueRefresh(); RunTimers()
  ok(UI64.primerKey == "DenOfNalorakk" and UI64:PrimerDetected() == nil, "auto dungeon off: your key isn't followed, the tab keeps what it shows")
  ns64.db.settings.liveAutoDungeon = true
  OWNED_KEY, OWNED_LEVEL = nil, nil
  UI64:Hide()
end

-- 65. Issues #12 and #13: the journal answers only for the selected instance; verify WARNs on
-- an empty read; the party re-run note only outside an instance.
do
  -- Like the client (October 18, build 70448): encounter reads return nothing until
  -- EJ_SelectInstance(jid) has selected that journal instance.
  local selected, selects = 0, {}
  local function installJournal()
    EJ_GetCurrentInstance = function() return selected end
    EJ_SelectInstance = function(j) selects[#selects + 1] = j; selected = j end
  end
  EJ_GetEncounterInfoByIndex = function(n, jid)
    if jid ~= 1322 or selected ~= 1322 then return nil end
    local bosses = { { "Rav'i", 10 }, { "The Writhing Coil", 20 }, { "Zul'jan", 30 } }
    local b = bosses[n]; if not b then return nil end
    return b[1], "", 9000 + n, b[2], nil, nil, 3300 + n
  end
  local SECTIONS = { [10] = { title = "Hydrastrike", spellID = 1111 }, [20] = { title = "Death Rattle", spellID = 3333 } }
  C_EncounterJournal = { GetSectionInfo = function(id) return SECTIONS[id] end,
    GetInstanceForGameMap = function(map) return map == 2993 and 1322 or 0 end }
  EJ_SelectInstance, EJ_GetCurrentInstance, EncounterJournal = nil, nil, nil
  EnsembleDB = nil
  local ns65 = boot()
  local BC65 = ns65.BossCards
  -- No EJ_SelectInstance (an older or changed client): reads are empty and not cached.
  ok(next(BC65:JournalSpells("AltarOfFangs")) == nil, "#12: without a selection the journal reads no abilities")
  ok(BC65:EncounterIDs("AltarOfFangs") == nil, "#12: without a selection no encounter IDs (names stay the fallback)")
  -- The select call appears: the next read works, so the empty read wasn't cached.
  installJournal()
  local js = BC65:JournalSpells("AltarOfFangs")
  ok(js.Hydrastrike and js.Hydrastrike.id == 1111 and js["Death Rattle"], "#12: abilities read after selecting the instance")
  ok(selects[1] == 1322, "#12: EJ_SelectInstance called with the dungeon's journal ID")
  local ids = BC65:EncounterIDs("AltarOfFangs")
  ok(ids and ids.byName.ravi == 1 and ids.byID[3303] == 3, "#12: encounter IDs read after selecting the instance")
  ok(BC65:IndexForEncounter("AltarOfFangs", 3302, "Unknown") == 2, "#12: a boss kill matches by journal ID")
  -- Cached once read: no further selects.
  local n0 = #selects
  BC65:JournalSpells("AltarOfFangs"); BC65:EncounterIDs("AltarOfFangs")
  ok(#selects == n0, "#12: a successful read is cached")
  -- Journal window open on another dungeon: its selection is put back after our read.
  EnsembleDB = nil
  local ns65b = boot()
  EncounterJournal = { IsShown = function() return true end }
  selected, selects = 1311, {}
  ok(ns65b.BossCards:JournalSpells("AltarOfFangs").Hydrastrike ~= nil, "#12: read works with the journal open")
  ok(selects[1] == 1322 and selects[2] == 1311 and selected == 1311, "#12: the open journal's selection is restored")
  -- Journal window hidden: no restore (the window selects its own instance when opened).
  EncounterJournal = { IsShown = function() return false end }
  selected, selects = 1311, {}
  ns65b.BossCards:EncounterIDs("AltarOfFangs")
  ok(#selects == 1 and selected == 1322, "#12: hidden journal: selection not restored")
  -- Already selected: no select call; a failing select is contained.
  EnsembleDB = nil
  local ns65c = boot()
  selected, selects = 1322, {}
  ok(ns65c.BossCards:JournalSpells("AltarOfFangs").Hydrastrike ~= nil and #selects == 0, "#12: no select when already on that instance")
  EnsembleDB = nil
  local ns65d = boot()
  selected = 0
  EJ_SelectInstance = function() error("client error") end
  ok(next(ns65d.BossCards:JournalSpells("AltarOfFangs")) == nil and ns65d.BossCards:EncounterIDs("AltarOfFangs") == nil,
    "#12: a failing select is contained and reads empty")
  local okW = pcall(function() return ns65d.BossCards:WithJournalInstance(1322, function() error("read failed") end) end)
  ok(okW, "#12: an error inside a read is contained")

  -- #13: /ens verify. The dungeon here is Altar of Fangs; its journal is found.
  local BCv = ns65d.BossCards
  local realCur = BCv.CurrentDungeon
  BCv.CurrentDungeon = function() return "AltarOfFangs" end
  EJ_SelectInstance = nil
  local vtx = ns65d.Verify:Build()
  ok(vtx:find("[WARN] EJ_SelectInstance missing", 1, true), "#13: missing EJ_SelectInstance is a WARN")
  ok(vtx:find("[WARN] Altar of Fangs: 0 boss abilities from the journal (journal 1322 found but read empty)", 1, true),
    "#13: a found journal with no abilities is a WARN")
  ok(vtx:find("[WARN] journal bosses here: 0, cards: ", 1, true) and vtx:find("journal 1322 found but read empty", 1, true),
    "#13: a found journal with no bosses is a WARN")
  installJournal(); selected = 0
  vtx = ns65d.Verify:Build()
  ok(vtx:find("[OK] EJ_SelectInstance present", 1, true), "#13: EJ_SelectInstance present is OK")
  ok(vtx:find("[OK] Altar of Fangs: 2 boss abilities from the journal", 1, true), "#13: abilities read: OK")
  ok(vtx:find("[OK] journal bosses here: 3, cards: ", 1, true), "#13: bosses read: OK")
  -- No journal at all for the dungeon stays INFO.
  C_EncounterJournal.GetInstanceForGameMap = function() return 0 end
  EnsembleDB = nil
  local ns65e = boot()
  ns65e.BossCards.CurrentDungeon = function() return "AltarOfFangs" end
  vtx = ns65e.Verify:Build()
  ok(vtx:find("[INFO] Altar of Fangs: 0 boss abilities from the journal;", 1, true) and not vtx:find("journal bosses here", 1, true),
    "#13: no journal found stays INFO")
  C_EncounterJournal.GetInstanceForGameMap = function(map) return map == 2993 and 1322 or 0 end
  BCv.CurrentDungeon = realCur

  -- #13: the party re-run note only outside an instance.
  issecretvalue = function() return false end
  IsInInstance = function() return false end
  ok(ns65d.Verify:Build():find("Re-run inside a Mythic+ key with a party", 1, true), "#13: re-run note outside an instance")
  IsInInstance = function() return true, "party" end
  ok(not ns65d.Verify:Build():find("Re-run inside a Mythic+ key", 1, true), "#13: no re-run note inside an instance")
  IsInInstance = function() error("client error") end
  ok(ns65d.Verify:Build():find("Re-run inside a Mythic+ key", 1, true), "#13: a failing IsInInstance keeps the note")
  issecretvalue, IsInInstance = nil, nil

  -- /ens verify season: bosses listed after selecting; an empty read is named, not silent.
  local stubInstance = DUNGEON_MAPS[588][3]
  DUNGEON_MAPS[588][3] = 2993
  EnsembleDB = nil
  local ns65f = boot()
  selected = 0
  local season = ns65f.Verify:BuildSeason()
  ok(season:find("boss 1: Rav'i", 1, true) and season:find("Hydrastrike=1111", 1, true), "#12: season dump reads bosses after selecting")
  EJ_SelectInstance = nil; selected = 0
  season = ns65f.Verify:BuildSeason()
  ok(season:find("(journal 1322 found but lists no bosses", 1, true) and not season:find("boss 1: Rav'i", 1, true),
    "#12: season dump names a found but empty journal")
  DUNGEON_MAPS[588][3] = stubInstance
  EJ_GetInstanceForMap, EJ_GetEncounterInfoByIndex, C_EncounterJournal, C_Map = nil, nil, nil, nil
  EJ_SelectInstance, EJ_GetCurrentInstance, EncounterJournal = nil, nil, nil
end

-- 66. Review fixes before 1.3.2 (R1-R11, October 19)
do
  local function dump(l) local t = {} for i = 1, l.used do t[#t + 1] = l.pool[i]:GetText() end return table.concat(t, "\n") end
  EnsembleDB = nil
  local ns66 = boot()
  local UI66, V66 = ns66.UI, ns66.Verify
  -- R1: no player name in /ens verify.
  local NF = V66.IsNameField
  ok(NF("name") and NF("leaderName") and NF("fullName") and not NF("specName") and not NF("className")
    and not NF("classFilename") and not NF("activityName"), "R1: name fields recognized, spec and class names kept")
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
             party1 = { guid = "A", name = "Ann", class = "SHAMAN", role = "HEALER" } }
  INSPECT_CACHE.A = 264
  LISTING = "Temple of Sethraliss (Mythic Keystone)"
  APPLICANTS = { [7] = { { name = "Secretname-Realm", class = "SHAMAN", role = "DAMAGER", spec = 262, score = 2900 } },
                 [8] = { { name = "Other-Realm", class = "MAGE", role = "DAMAGER", spec = 63, score = 2500 } } }
  UI66:Show("composition"); RunTimers(); RunTimers()
  local vt = V66:Build()
  ok(vt:find("first applicant returns: <name> | SHAMAN", 1, true) and not vt:find("Secretname", 1, true),
    "R1: verify shows the applicant's data without their name")
  -- R2: previewing an applicant leaves the real group as the last group checked.
  ns66.db.settings.compMode = "auto"; ns66.db.settings.compApplicants = "panel"
  UI66:SetTab("composition"); RunTimers()
  local real = #(UI66.cp.lastMembers or {})
  UI66.cp.preview = 7; UI66:Refresh(); RunTimers()
  ok(UI66.previewWas ~= nil and #UI66.cp.lastMembers == real and UI66.cp.lastAnalysis.filled == real,
    "R2: lastMembers / lastAnalysis stay the real group during a preview (" .. real .. ")")
  local okR, rep = pcall(ns66.Report.Build, ns66.Report)
  ok(okR and not tostring(rep):find("Elemental Shaman", 1, true), "R2: /ens report's group doesn't include the previewed applicant")
  UI66.cp.preview = nil
  -- R5: the NONE tag doesn't double the fold marker.
  ok(UI66.READY_TAG.none == "|cff9499a8NONE|r", "R5: NONE tag without a dash")
  ns66.db.settings.compMode = "planner"
  for s, id in ipairs({ 73, 0, 0, 0, 0 }) do ns66.db.currentComp[s] = id end
  ns66:SetManualDungeon("AltarOfFangs"); UI66:SetTab("composition"); RunTimers()
  UI66:ExpandAll(); RunTimers()
  local an = dump(UI66.cp.ready)
  ok(an:find("NONE|r", 1, true) and not an:find("- |r|cff9499a8-  NONE", 1, true) and not an:find("+ |cff9499a8-  NONE", 1, true),
    "R5: no \"- -  NONE\" or \"+ -  NONE\" rows")
  -- R4: one reason per need: "covers Interrupt for A, B", never the same words twice.
  local groups = ns66.Analysis:SuggestClasses({ [1] = { specID = 73 } }, ns66.SLOT_ROLES, "MurderRow", ns66.db.settings, 4)
  local checked, repeated, merged = 0, 0, 0
  for _, g in ipairs(groups) do for _, c in ipairs(g.classes) do
    local heads = {}
    for _, reason in ipairs(c.reasons) do
      checked = checked + 1
      local head = reason:match("^(covers [^|]- for )") or reason:match("^(backs up [^|]- for )")
      if head then
        if heads[head] then repeated = repeated + 1 end
        heads[head] = true
        if reason:find(", |H", 1, true) then merged = merged + 1 end
      end
      local _, n = reason:gsub("covers Interrupt for", "")
      if n > 1 then repeated = repeated + 1 end
    end
  end end
  ok(checked > 0 and repeated == 0 and merged > 0, string.format("R4: reasons merged by need (%d reasons, %d merged, %d repeats)", checked, merged, repeated))
  -- R4: merging drops nothing: every cast a single-cast reason named is still named.
  local function casts(list)
    local n = 0
    for _, reason in ipairs(list) do local _, k = reason:gsub("|Haddon:Ensemble:", ""); n = n + k end
    return n
  end
  local anyClass = groups[1] and groups[1].classes[1]
  ok(anyClass and casts(anyClass.reasons) > 0, "R4: merged reasons keep their cast links")
  -- R6: an ability named like its need isn't preceded by the same words.
  local _, evals = ns66.ApplicantFit:ForLiveGroup()
  local slotR = ns66.Analysis:Analyze({ { specID = 262 }, { specID = 73 } }, "KingsRest", ns66.db.settings)
  local _, tip = UI66:SlotBadges(slotR, 1)
  ok(tip:find("Bloodlust / Heroism", 1, true) and not tip:find("Bloodlust / Heroism: Bloodlust", 1, true), "R6: slot tooltip says Bloodlust once")
  ns66.db.settings.compMode = "auto"; UI66:SetTab("applicants"); RunTimers()
  UI66.ap.selected = 7; UI66:Refresh(); RunTimers()
  local det = dump(UI66.ap.detail)
  ok(det:find("Bloodlust / Heroism", 1, true) and not det:find("Bloodlust / Heroism: |H", 1, true), "R6: applicant brings Bloodlust once")
  -- R7: "GOOD FIT   51 / 100", not "fit 51 / 100".
  ok(det:find(" / 100", 1, true) and not det:find("   fit %d+ / 100"), "R7: fit line says FIT once")
  -- R8: the link tooltip for an unknown spell has no developer instructions.
  local lines = {}
  local oldAdd, oldSet = GameTooltip.AddLine, GameTooltip.SetText
  GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
  GameTooltip.SetText = function(_, t) lines[#lines + 1] = t end
  local content = UI66.ap.detail.content
  content._scripts.OnHyperlinkEnter(content, "addon:Ensemble:a:0:utility:Mystery Spell")
  GameTooltip.AddLine, GameTooltip.SetText = oldAdd, oldSet
  local tipText = table.concat(lines, "\n")
  ok(tipText:find("Mystery Spell", 1, true) and not tipText:find(".lua", 1, true), "R8: no file names in the link tooltip")
  -- R9: tour text.
  local steps = ns66.Tour.STEPS
  ok(steps[2].text:find("the dungeon you're in", 1, true) and steps[5].text:find("may block addon chat", 1, true)
    and steps[5].text:find("copy window", 1, true), "R9: tour says Auto's sources and that chat may be blocked")
  -- R10: the Blizzard Options panel names every settings section.
  Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }
  UI66.blizzCategory = nil
  UI66:RegisterBlizzardOptions()
  local body
  for _, fr in ipairs(ALLFRAMES) do if type(fr._text) == "string" and fr._text:find("Every setting is in", 1, true) then body = fr._text end end
  local allNamed = body ~= nil
  for _, sec in ipairs(UI66.SETTINGS_SECTIONS) do if not (body and body:find(sec.label, 1, true)) then allNamed = false end end
  ok(allNamed, "R10: Options panel lists every settings section")
  Settings = nil
  -- R11: boss window footer: a gap between the left and right buttons at the smallest width.
  local BW = ns66.BossWindow
  ns66.db.settings.bossWindow.showAll = false
  BW.view = { dk = "KingsRest" }; BW:Show(); RunTimers()
  local function w(b) return rawget(b, "_w") end
  local leftEnd = 4 + w(BW.roleBtn) + 2 + w(BW.smaller) + w(BW.bigger)
  local rightStart = (BW.MIN_W - 2) - 18 - w(BW.post) - 2 - w(BW.edit)
  ok(w(BW.roleBtn) == 92 and rightStart - leftEnd >= 4, string.format("R11: footer gap at the minimum width (%d px)", rightStart - leftEnd))
  BW:Hide(true)
  UI66:Hide()
  ROSTER, LISTING = {}, nil
  APPLICANTS = { [7] = { { name = "Applicant-Realm", class = "SHAMAN", role = "HEALER", spec = 264, score = 2900 } } }
end

-- 67. Issue #16: layout at 125% text in the smallest window (October 20)
do
  EnsembleDB = nil
  local ns67 = boot()
  local UI67 = ns67.UI
  CURRENT_AFFIXES = { 10, 147 }
  OWNED_KEY, OWNED_LEVEL = 588, 12
  ns67.db.settings.compMode = "planner"
  for s2, id in ipairs({ 581, 0, 0, 0, 0 }) do ns67.db.currentComp[s2] = id end
  UI67:Show("composition"); RunTimers()
  -- A stand-in for the client's text measuring: visible characters x font size x 0.6.
  local function measure(self)
    local t = tostring(rawget(self, "_text") or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  ")
    return #t * (rawget(self, "_fontSize") or 12) * 0.6
  end
  local function installMeasure() for _, fr in ipairs(ALLFRAMES) do rawset(fr, "GetUnboundedStringWidth", measure) end end
  UI67:SetTab("plan"); RunTimers()
  UI67:SetTab("settings"); RunTimers()
  UI67:SetTab("composition"); RunTimers()
  installMeasure()
  UI67:SetTextSize(125); RunTimers()
  local FP = UI67.FontPx
  local function size(fs) return rawget(fs, "_fontSize") end
  local post = UI67.pl.postPlanBtn.text
  ok(size(post) == 13 and measure(post) <= 128, "fit: \"Post assignments\" steps down to fit its 140px button at 125% (" .. tostring(size(post)) .. ")")
  ok(size(UI67.cp.saveBtn.text) == FP(12), "fit: a short label keeps the player's text size")
  local clear = UI67.cp.slotRows[1].clear.text
  ok(size(clear) >= 12 and size(clear) < FP(12) and measure(clear) <= 8, "fit: the slot's x fits its 20px button")
  ok(size(UI67.cp.copyLiveBtn.text) >= 12 and measure(UI67.cp.copyLiveBtn.text) <= 80, "fit: \"Copy party\" fits")
  local note = UI67.cp.dungeonNote
  ok(note:GetText() == "From your keystone (+12)" and size(note) == 11, "fit: dungeon note shrinks no further than its design size")
  ok(UI67.cp.noteBtn.tip == "Auto: your keystone (+12)." and UI67.cp.noteBtn:IsShown(), "dungeon note: full sentence on hover")
  local chip = UI67.cp.chips[1]
  ok(chip and rawget(chip.text, "cmFit") == nil and size(chip.text) == FP(11), "chips aren't fitted (they size themselves to the label)")
  UI67:SetTextSize(100); RunTimers()
  ok(size(post) == 12 and size(UI67.cp.saveBtn.text) == 12, "fit: back at 100% every label is at its design size")
  UI67:SetTextSize(80); RunTimers()
  ok(size(post) == FP(12) and FP(12) < 12, "fit: at 80% labels follow the smaller text")
  UI67:SetTextSize(125); RunTimers()
  -- Slots: the two lines hang from the row, not the icon; the row fits both at 125%.
  local row = UI67.cp.slotRows[1]
  local np, sp = row.name._points[1], row.sub._points[1]
  ok(np[1] == "TOPLEFT" and np[2] == row and sp[1] == "BOTTOMLEFT" and sp[2] == row, "slots: name and sub anchored to the row")
  ok(row._h == FP(13) + FP(11) + 14, "slots: row height fits both lines (" .. tostring(row._h) .. ")")
  ok(row.role.cmFit ~= nil, "slots: role label fitted")
  ok(row.name:GetText():find("Veng Demon Hunter", 1, true) and row.tip:find("^Vengeance Demon Hunter\n"),
    "slots: short spec name, full name in the tooltip")
  -- Settings and the Needs header.
  local gf, lockFull, lockShort
  for _, fr in ipairs(ALLFRAMES) do
    local t = rawget(fr, "_text")
    if t == "Groups you could join" then gf = fr end
    if type(t) == "string" and t:find("^Lock window %(") then lockFull = true end
    if t == "Lock window" then lockShort = true end
  end
  ok(gf and gf._point[2] == 320, "Settings > Group Finder: right column at x 320")
  ok(lockShort and not lockFull, "Settings > Appearance: \"Lock window\", details in the tooltip")
  local ep = UI67.cp.expandBtn._point
  ok(ep[1] == "RIGHT" and ep[2] == UI67.cp.collapseBtn and ep[4] == -6, "Needs header: gap between Expand all and Collapse all")
  -- The boss window and the applicant panel draw over the main window, under the addon's pop-ups.
  local BW67 = ns67.BossWindow
  BW67:Open("AltarOfFangs"); RunTimers()
  local main = UI67.frame
  local function over(f)
    return f:GetFrameStrata() == main:GetFrameStrata() and f:GetFrameLevel() >= main:GetFrameLevel() + 100
  end
  ok(main:GetFrameStrata() == "HIGH" and over(BW67.frame), "boss window draws over the main window")
  UI67:BuildFinderPanel()
  ok(over(UI67.fp), "applicant panel draws over the main window")
  UI67:ShowSources()
  ok(UI67.sources:GetFrameStrata() == "DIALOG", "the addon's pop-ups stay above both (DIALOG)")
  BW67:Hide(true); UI67.sources:Hide()
  UI67:SetTextSize(100); UI67:Hide()
  OWNED_KEY, OWNED_LEVEL = nil, nil
  CURRENT_AFFIXES = {}
end

-- 68. Small cleanups (October 24): Addon Compartment tooltip, R15 deferred inspect clear,
-- clipping at a word, "Your assignments" naming each ability once, the compare column, the
-- dead boss-card renderer and wiki callout gone.
do
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 71, role = "DAMAGER" } }
  local ns68 = boot()
  local UI68 = ns68.UI
  -- Addon Compartment tooltip: same header as the minimap tooltip, then its own actions.
  local lines = {}
  local oldAdd, oldOwner, oldShow = GameTooltip.AddLine, GameTooltip.SetOwner, GameTooltip.Show
  GameTooltip.AddLine = function(_, t, r, g, b) lines[#lines + 1] = { t = t, r = r, g = g, b = b } end
  GameTooltip.SetOwner = function() end
  GameTooltip.Show = function() end
  Ensemble_OnAddonCompartmentEnter(nil, UIParent)
  GameTooltip.AddLine, GameTooltip.SetOwner, GameTooltip.Show = oldAdd, oldOwner, oldShow
  local acc = UI68.Kit.C.accent
  ok(lines[1] and lines[1].t == "Ensemble" and lines[1].r == 1 and lines[1].g == 1 and lines[1].b == 1, "compartment tooltip: Ensemble in white")
  ok(lines[2] and lines[2].t == "A Mythic+ Companion" and lines[2].r == acc[1] and lines[2].g == acc[2] and lines[2].b == acc[3],
    "compartment tooltip: subtitle in the accent color")
  ok(lines[3] and lines[3].t == "Left-click: toggle window" and lines[4] and lines[4].t == "Right-click: settings" and #lines == 4,
    "compartment tooltip: actions unchanged")
  -- R15: our own inspect is cleared on the next frame, after every INSPECT_READY handler read it.
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 71, role = "DAMAGER" },
             party1 = { guid = "Q1", name = "Quin", class = "MAGE", role = "DAMAGER" } }
  INSPECT_CACHE = {}
  NOTIFIED = {}
  UI68:Show("composition"); RunTimers()
  local trk
  for _, fr in ipairs(ALLFRAMES) do if fr._events.INSPECT_READY then trk = fr end end
  local cleared = 0
  local oldClear = ClearInspectPlayer
  ClearInspectPlayer = function() cleared = cleared + 1 end
  ok(#NOTIFIED >= 1, "R15: an inspect was requested")
  INSPECT_CACHE.Q1 = 62
  trk._scripts.OnEvent(trk, "INSPECT_READY", "Q1")
  ok(cleared == 0, "R15: not cleared inside the INSPECT_READY handler")
  local secondRead = GetInspectSpecialization("party1")
  ok(secondRead == 62, "R15: a second addon's handler after ours can still read")
  RunTimers()
  ok(cleared == 1, "R15: cleared on the next frame")
  -- A new inspect of ours started before the next frame: the clear is skipped.
  ROSTER.party2 = { guid = "Q2", name = "Ria", class = "PRIEST", role = "HEALER" }
  ROSTER.party3 = { guid = "Q3", name = "Sol", class = "ROGUE", role = "DAMAGER" }
  for _ = 1, 3 do trk._scripts.OnEvent(trk, "GROUP_ROSTER_UPDATE") end
  RunTimers()
  cleared = 0
  local pendingGuid = ROSTER[NOTIFIED[#NOTIFIED]] and ROSTER[NOTIFIED[#NOTIFIED]].guid
  INSPECT_CACHE[pendingGuid or "Q2"] = 256
  trk._scripts.OnEvent(trk, "INSPECT_READY", pendingGuid or "Q2")
  local nb = #NOTIFIED
  ns68.Tracker:ProcessInspectQueue()   -- the next inspect starts before the deferred clear runs
  local started = #NOTIFIED > nb
  RunTimers()
  ok(started and cleared == 0, "R15: a new inspect isn't cancelled by the deferred clear")
  ClearInspectPlayer = oldClear
  UI68:Hide()
  -- Util.Clip: at the last space that fits, never inside a UTF-8 character.
  local Clip = ns68.Util.Clip
  ok(Clip("short", 10) == "short", "Clip: short text unchanged")
  ok(Clip("Ikuzz at 50% if you go there first", 20) == "Ikuzz at 50% if you", "Clip: at a word")
  local accented = string.rep("a", 9) .. "\195\169" .. "tude"   -- 9 a's, then e-acute (2 bytes)
  local c = Clip(accented, 10)
  ok(c == string.rep("a", 9), "Clip: never splits a UTF-8 character (" .. #c .. " bytes)")
  local WT = ns68.Walkthrough
  ns68.db.lust = { MurderRow = { { at = "b1" } } }
  WT:SetLustNote("MurderRow", 1, string.rep("word ", 30))
  local note = ns68.db.lust.MurderRow[1].note
  ok(note and #note <= 80 and not note:find(" $") and note:sub(-4) == "word", "Bloodlust note cut at a word: " .. tostring(note and #note))
  -- "Your assignments": an ability is named once after the casts it answers.
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 71, role = "DAMAGER" } }
  CURRENT_AFFIXES = { 158, 10, 9, 147 }
  ns68 = boot()
  UI68 = ns68.UI
  ns68.Affixes:Refresh()
  ns68.state.keyLevelOverride = 17
  ns68.db.currentComp = { 581, 264, 266, 62, 71 }
  ns68:SetManualDungeon("DenOfNalorakk")
  UI68:Show("plan"); RunTimers()
  local kickLine
  for i = 1, UI68.pl.mine.used do
    local t = UI68.pl.mine.pool[i]:GetText() or ""
    if t:find("Kick:", 1, true) then kickLine = t end
  end
  local _, pummels = (kickLine or ""):gsub("Pummel", "")
  local _, casts = (kickLine or ""):gsub(";", "")
  ok(kickLine and pummels == 1 and casts >= 1, "Your assignments: Pummel named once after " .. (casts + 1) .. " casts")
  UI68:Hide()
  CURRENT_AFFIXES = {}
  ns68.state.keyLevelOverride = nil
  -- The compare view's labels sit in their own column (no space padding).
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
  }
  INSPECT_CACHE = { H = 256 }
  LISTING = "Temple of Sethraliss (Mythic Keystone)"
  APPLICANTS = {
    [1] = { { name = "Shamy", class = "SHAMAN", role = "DAMAGER", spec = 263, score = 2700, ilvl = 640 } },
    [2] = { { name = "Stabby", class = "ROGUE", role = "DAMAGER", spec = 259, score = 3100, ilvl = 650 } },
  }
  UI68:Show("applicants"); RunTimers()
  UI68:TogglePin(1); UI68:TogglePin(2); RunTimers()
  local det = UI68.ap.detail
  local label, value
  for i = 1, det.used do
    local fs = det.pool[i]
    local t = fs:GetText() or ""
    if t:find("M+ rating", 1, true) then label = fs end
    if t:find("^A 2700") then value = fs end
  end
  ok(label and value and not label:GetText():find("  ", 1, true), "compare: label and values are separate lines")
  ok(label and value and label._point[5] == value._point[5] and value._point[4] > label._point[4] + 50,
    "compare: values start at a fixed column on the label's row")
  UI68:Hide()
  ROSTER, LISTING, APPLICANTS = {}, nil, {}
  -- Dead code and the dead wiki callout are gone.
  ok(UI68.RenderBossCards == nil, "the old boss-card renderer is gone")
  local wf = io.open(ADDON_DIR .. "/../tools/make_wiki.py", "r")
  local wiki = wf and wf:read("*a") or ""
  if wf then wf:close() end
  ok(wiki ~= "" and not wiki:find("Your route, pull by pull", 1, true) and not wiki:find("Mythic Dungeon Tools", 1, true),
    "wiki: the Mythic Dungeon Tools route callout is gone")
end

-- 69. The Blinding Vale's default Bloodlust follows the first boss (October 24, the author):
-- Ikuzz first -> on Ikuzz "at 50%"; the Trinity first -> on the Trinity "after the first
-- garden". Marker, Plan line, boss window and party post all agree; a saved plan stays put.
do
  EnsembleDB = nil
  local ns69 = boot()
  local WT, BC, BW = ns69.Walkthrough, ns69.BossCards, ns69.BossWindow
  local dk = "TheBlindingVale"
  local bosses = BC:Bosses(dk)
  ok(bosses[1].name == "Lightblossom Trinity" and bosses[2].name == "Ikuzz the Light Hunter", "Vale data order: Trinity 1, Ikuzz 2")
  local function check(firstIdx, note, label)
    local uses, custom = WT:Lust(dk)
    ok(not custom and uses[1].at == "b" .. firstIdx and uses[1].note == note, label .. ": default lust 1 on " .. bosses[firstIdx].name)
    -- Walkthrough marker on the first boss step.
    local marked
    for _, st in ipairs(WT:Build(dk).steps) do
      if st.kind == "boss" and #WT:LustAt(dk, st) > 0 and not marked then marked = st end
    end
    ok(marked and marked.boss == firstIdx and marked.pos == 1, label .. ": walkthrough marker on the first boss")
    -- Plan / Dungeon tab line, party post, boss window.
    ok(WT:LustText(dk, uses[1]) == bosses[firstIdx].name .. " (" .. note .. ")", label .. ": Plan line names that boss and its note")
    local chat = WT:LustChat(dk)
    ok(chat and chat:find("^Lust: " .. bosses[firstIdx].name:gsub("%p", "%%%0") .. " %(" .. note:gsub("%p", "%%%0") .. "%)"),
      label .. ": party post starts on that boss: " .. tostring(chat))
    local rows = BW:LustRows(dk, "b" .. firstIdx)
    local other = BW:LustRows(dk, "b" .. (3 - firstIdx))
    ok(#rows == 1 and rows[1].text == "Bloodlust: " .. note and #other == 0, label .. ": boss window shows it on that boss only")
  end
  check(1, "after the first garden", "Trinity first")
  BC:MoveBoss(dk, 2, -1)
  check(2, "at 50%", "Ikuzz first")
  -- The rest of the plan is unchanged (Ruia at 40%, Ziekket if it's back).
  local uses = WT:Lust(dk)
  ok(#uses == 3 and uses[2].at == "b3" and uses[2].note == "at 40%" and uses[3].at == "b4", "the later defaults stay on Ruia and Ziekket")
  ok(ns69.db.lust == nil or ns69.db.lust[dk] == nil, "showing the default saves nothing")
  -- A saved plan stays where the player put it when the order changes.
  WT:SetLustNote(dk, 1, "my note")
  local own = ns69.db.lust[dk]
  ok(own[1].at == "b2" and own[1].note == "my note", "editing copies the resolved default (Ikuzz)")
  BC:MoveBoss(dk, 1, -1)   -- Trinity first again
  uses = WT:Lust(dk)
  local onIkuzz
  for _, u in ipairs(uses) do if u.at == "b2" and u.note == "my note" then onIkuzz = true end end
  ok(onIkuzz and select(2, WT:Lust(dk)) == true, "a saved plan doesn't move with the order")
  WT:ResetLust(dk)
  ok(WT:Lust(dk)[1].at == "b1" and WT:Lust(dk)[1].note == "after the first garden", "reset: back to the default, on the first boss")
  -- Data-driven: dungeons without an order choice keep their defaults as written.
  local ao = WT:Lust("AltarOfFangs")
  ok(ao[1].at == "b1" and ao[1].note == "on pull" and ao[2].at == "b3", "fixed-order dungeons unchanged")
  -- Every default note entry names a real boss.
  local badNotes = {}
  for dk2, list in pairs(ns69.Dungeons.LUST) do
    for _, u in ipairs(list) do
      for bi in pairs(u.notes or {}) do if not BC:Bosses(dk2)[bi] then badNotes[#badNotes + 1] = dk2 .. ":" .. tostring(bi) end end
      if u.notes then ok(BC:OrderGroup(dk2, tonumber(u.at:match("%d+"))) ~= nil, dk2 .. ": per-boss notes only inside an order group") end
    end
  end
  ok(#badNotes == 0, "per-boss notes name real bosses: " .. table.concat(badNotes, ","))
  ns69.db.bossOrder = {}
end

-- 70. Fill group, the planner (1.4.0): rating model, levels, filters, musts, the solid-source
-- rule, choosing the group, pending invites, the pool gap line, timing at 4 open slots.
do
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Faelan", class = "WARRIOR", spec = 73, role = "TANK" } }
  LISTING = "Den of Nalorakk (Mythic Keystone)"
  APPLICANT_STATUS = {}
  local ns70 = boot()
  local FG, H70 = ns70.FillGroup, ns70.Dungeons.HEURISTICS
  local function plan(apps, level)
    APPLICANTS = apps
    ns70.state.keyLevelOverride = level
    ns70.Tracker:Rescan()
    ns70.ApplicantFit.ClearCache(); FG.ClearCache()
    return FG:Current()
  end
  local function names(list) local t = {} for _, ev in ipairs(list or {}) do t[#t + 1] = ev.members[1].name end return table.concat(t, ",") end
  local BASE = {
    [1] = { { name = "Bralia", class = "PALADIN", role = "HEALER", spec = 65, score = 3464, ilvl = 328 } },
    [2] = { { name = "Bramok", class = "SHAMAN", role = "DAMAGER", spec = 262, score = 3390, ilvl = 324 } },
    [3] = { { name = "Kelor", class = "MONK", role = "DAMAGER", spec = 269, score = 3429, ilvl = 326 } },
    [4] = { { name = "Doriah", class = "PRIEST", role = "DAMAGER", spec = 258, score = 3453, ilvl = 325 } },
    [5] = { { name = "Faren", class = "DEMONHUNTER", role = "DAMAGER", spec = 577, score = 3461, ilvl = 325 } },
    [6] = { { name = "Lumira", class = "PRIEST", role = "HEALER", spec = 257, score = 2950, ilvl = 320 } },
    [7] = { { name = "Darik", class = "MAGE", role = "DAMAGER", spec = 63, score = 3500, ilvl = 300 } },
  }
  local function with(extra)
    local t = {}
    for k, v in pairs(BASE) do t[k] = v end
    for k, v in pairs(extra or {}) do t[k] = v ~= false and v or nil end
    return t
  end

  -- Rating model (Midnight Season 2 calculators) and "Suggested for the key" (two levels below).
  ok(FG.RatingForLevel(5) == 1720 and FG.RatingForLevel(7) == 2080 and FG.RatingForLevel(12) == 2920
    and FG.RatingForLevel(16) == 3400 and FG.RatingForLevel(18) == 3640 and FG.RatingForLevel(20) == 3880,
    "rating model reproduces the published anchors")
  local want = { [7] = 1700, [8] = 1800, [9] = 2050, [10] = 2200, [11] = 2300, [12] = 2550, [13] = 2650, [14] = 2900,
    [15] = 3000, [16] = 3150, [17] = 3250, [18] = 3400, [20] = 3600 }
  local bad = {}
  for L, v in pairs(want) do if FG:SuggestedRating(L) ~= v then bad[#bad + 1] = L .. "=" .. tostring(FG:SuggestedRating(L)) end end
  ok(#bad == 0 and FG:SuggestedRating(6) == nil and FG:SuggestedRating(nil) == nil, "suggested rating: the agreed table, off up to +6 " .. table.concat(bad, " "))
  ok(FG:SuggestedItemLevel(12) == 300 and FG:SuggestedItemLevel(6) == nil, "suggested item level: end-of-run reward two levels below, from the game")
  local oldReward = C_MythicPlus.GetRewardLevelForDifficultyLevel
  C_MythicPlus.GetRewardLevelForDifficultyLevel = nil
  local v, why = FG:SuggestedItemLevel(12)
  ok(v == nil and why == "api", "no reward API: no suggested item level")
  C_MythicPlus.GetRewardLevelForDifficultyLevel = function() error("boom") end
  ok(FG:SuggestedItemLevel(12) == nil, "reward API error: no value, no Lua error")
  C_MythicPlus.GetRewardLevelForDifficultyLevel = oldReward

  -- Levels.
  local s = ns70.db.settings
  ok(FG:Level(s, 2) == "relaxed" and FG:Level(s, 6) == "relaxed" and FG:Level(s, 7) == "standard" and FG:Level(s, 11) == "standard"
    and FG:Level(s, 12) == "strict" and FG:Level(s, 20) == "strict", "Match the key level: Relaxed to +6, Standard +7 to +11, Strict from +12")
  local lv, auto, unknown = FG:Level(s, nil)
  ok(lv == "standard" and auto and unknown, "no key level: Standard, said so")
  s.fill.level = "relaxed"; ok(FG:Level(s, 20) == "relaxed", "a fixed level ignores the key"); s.fill.level = "auto"
  local LF = FG.LevelFails
  ok(LF("relaxed", "missing", "critical") and not LF("relaxed", "missing", "high")
    and LF("standard", "missing", "high") and not LF("standard", "missing", "medium") and not LF("standard", "thin", "critical")
    and LF("strict", "missing", "medium") and not LF("strict", "missing", "low") and LF("strict", "thin", "high")
    and not LF("strict", "thin", "medium"), "level thresholds as agreed")

  -- Filters and their sources.
  local f = FG:Filters(s, 17)
  ok(f.rating.on and f.rating.value == 3250 and f.ilvl.on and f.ilvl.value == 305 and f.leaver and f.noData, "filters: suggested for +17")
  f = FG:Filters(s, 5)
  ok(not f.rating.on and f.rating.why == "off up to +6" and not f.ilvl.on, "filters: off up to +6")
  ok(not FG:Filters(s, nil).rating.on and FG:Filters(s, nil).rating.why == "key level unknown", "filters: key level unknown")
  s.fill.rating.source, s.fill.ilvl.source = "listing", "listing"
  LISTING_MIN_RATING, LISTING_MIN_ILVL = 2800, nil
  f = FG:Filters(s, 17)
  ok(f.rating.on and f.rating.value == 2800 and not f.ilvl.on and f.ilvl.why == "your listing sets none", "filters: from my listing")
  s.fill.rating.source, s.fill.rating.value = "custom", 3100
  ok(FG:Filters(s, 17).rating.value == 3100, "filters: custom value")
  s.fill.rating.on = false
  ok(not FG:Filters(s, 17).rating.on, "filters: a filter can be turned off")
  s.fill.rating = { on = true, source = "suggested", value = 2500 }; s.fill.ilvl.source = "suggested"
  LISTING_MIN_RATING = nil
  f = FG:Filters(s, 17)
  local FM = FG.FilterMember
  ok(FM({ score = 3300, itemLevel = 320 }, f) == nil, "a player above both minimums passes")
  ok(FM({ score = 2950, itemLevel = 320 }, f) == "M+ rating 2950 (needs 3250)", "rating below: skipped with the reason")
  ok(FM({ score = 3300, itemLevel = 300 }, f) == "item level 300 (needs 305)", "item level below: skipped")
  ok(FM({ score = 3300, itemLevel = 320, isLeaver = true }, f) == "has the game's leaver flag", "leaver flag: skipped")
  ok(FM({ score = nil, itemLevel = 320 }, f) == "no M+ rating from the game", "missing data fails a filter")
  s.fill.skipNoData = false
  ok(FM({ score = nil, itemLevel = 320 }, FG:Filters(s, 17)) == nil, "missing data allowed when that switch is off")
  s.fill.skipNoData = true
  s.fill.skipLeavers = false
  ok(FM({ score = 3300, itemLevel = 320, isLeaver = true }, FG:Filters(s, 17)) == nil, "leavers allowed when that switch is off")
  s.fill.skipLeavers = true
  ok(FG.FilterApplication({ members = { { name = "A", score = 3300, itemLevel = 320 }, { name = "B", score = 3000, itemLevel = 320 } } }, f)
    == "B: M+ rating 3000 (needs 3250)", "a premade is all-or-nothing, the failing member named")

  -- Solid sources: optional talents count (the author's call), pets, conditional, long cooldowns,
  -- unconfirmed and fallbacks don't.
  local SS = FG.SolidSource
  ok(SS({ name = "x" }) and SS({ talent = true }) and SS({ talent = true, core = true }) and not SS({ long = true })
    and not SS({ pet = true }) and not SS({ conditional = "x" }) and not SS({ verify = true }) and not SS({ fallback = true }),
    "solid sources: talents yes; pets, conditional, long CD, unconfirmed, fallback no")

  -- Musts: Bloodlust plus the boss cards' needs; low severity unticked.
  local bn = FG:BossNeeds("DenOfNalorakk")
  local ids = {}
  for _, e in ipairs(bn) do ids[#ids + 1] = e.req.id .. (e.default and "" or "-") end
  ok(table.concat(ids, ",") == "DN_TOXIC_SPORES,DN_WINTERS_SHROUD,DN_GLACIAL_TORMENT,DN_FREEDOM", "Den of Nalorakk: 4 boss needs " .. table.concat(ids, ","))
  local va = FG:BossNeeds("VoidscarArena")
  ok(#va == 1 and va[1].req.severity == "low" and not va[1].default, "Voidscar Arena's low freedom need starts unticked")
  local m = FG:Musts("DenOfNalorakk")
  ok(m.lust and #m.reqs == 4 and not m.custom, "musts default: Bloodlust and the 4 boss needs")
  local lbl, where
  for _, row in ipairs(m.rows) do if row.req.id == "DN_FREEDOM" then lbl, where = FG:MustLabel(row) end end
  ok(lbl == "Freedom (root/snare removal)" and where == "Rimeshatter, Sentinel of Winter", "a must names the boss's own cast: " .. tostring(where))
  local other = FG:OtherNeeds("DenOfNalorakk")
  local curse
  for _, q in ipairs(other) do if q.need == "dispel_curse" then curse = q end end
  ok(curse and #other > 0, "the dungeon's other needs can be added")
  FG:SetMust("DenOfNalorakk", "DN_FREEDOM", false)
  FG:SetMust("DenOfNalorakk", curse.id, true)
  FG:SetMust("DenOfNalorakk", "lust", false)
  m = FG:Musts("DenOfNalorakk")
  local has = {}
  for _, q in ipairs(m.reqs) do has[q.id] = true end
  ok(not m.lust and not has.DN_FREEDOM and has[curse.id] and m.custom and #m.reqs == 4, "musts: untick, add and Bloodlust saved")
  ok(ns70.db.fillMusts.DenOfNalorakk.on.DN_FREEDOM == false and ns70.db.fillMusts.DenOfNalorakk.lust == false, "saved per dungeon, only the differences")
  ok(FG:Musts("MurderRow").lust and not FG:Musts("MurderRow").custom, "other dungeons keep their defaults")
  FG:ResetMusts("DenOfNalorakk")
  ok(FG:Musts("DenOfNalorakk").lust and #FG:Musts("DenOfNalorakk").reqs == 4 and ns70.db.fillMusts.DenOfNalorakk == nil, "Reset needs: the dungeon's defaults again")

  -- A group passes at Standard (+10): the highest total of the groups that pass, never a partial.
  local p = plan(with({ [8] = { { name = "Oakra", class = "DRUID", role = "HEALER", spec = 105, score = 3300, ilvl = 320 } } }), 10)
  ok(p and p.status == "ready" and p.level == "standard" and #p.picks == 4, "Standard at +10: a full group passes")
  local roles = {}
  for _, ev in ipairs(p.picks) do roles[#roles + 1] = ev.roles[1] end
  ok(table.concat(roles, ",") == "HEALER,DAMAGER,DAMAGER,DAMAGER", "the plan fills the open slots exactly (tank is you)")
  ok(p.judge.pass and #p.judge.mustRows == 5 and p.sig:find("^DenOfNalorakk:"), "judged with every must; a signature for the click")
  ok(FG:ButtonText(p) == "Fill group (4)", "button: Fill group (4)")
  ok(p.runnerUp and p.runnerUp.out and p.runnerUp.inn and p.runnerUp.diff >= 0, "the next best group is named")
  local best = 0
  for _, ev in ipairs(p.picks) do best = best + ev.score end
  ok(best == p.total, "the plan's total is the sum of its pick ratings")
  ok(names(p.skipped):find("Lumira") == nil, "+10: Lumira's 2950 passes the 2200 minimum")

  -- Strict at +17: the filters skip, the fallback battle rez is thin, nothing is invited.
  p = plan(BASE, 17)
  ok(p.status == "none" and p.level == "strict" and #p.picks == 0, "Strict at +17: no group passes, no partial plan")
  local sk = {}
  for _, x in ipairs(p.skipped) do sk[x.ev.members[1].name] = x.reason end
  ok(sk.Lumira == "M+ rating 2950 (needs 3250)" and sk.Darik == "item level 300 (needs 305)", "skipped with their reasons")
  ok(p.closest and p.closest.judge.fails[1] and p.closest.judge.fails[1].label == "Battle resurrection (only a fallback)",
    "closest group: only Intercession, which Strict doesn't take")
  -- 1.4.1 review (R4): at Strict a fallback can't count, so it's a pool gap with who could bring it.
  ok(p.blocking == "Waiting for Battle resurrection: Death Knight, Druid or Warlock", "what's stopping it: " .. tostring(p.blocking))
  -- Intercession passes Standard as a thin battle rez (no DK, Druid or Warlock in the group).
  p = plan(BASE, 10)
  local thinBrez
  for _, t in ipairs(p.judge and p.judge.thin or {}) do if t:find("Battle resurrection", 1, true) then thinBrez = true end end
  ok(p.status == "ready" and thinBrez and names(p.picks):find("Bralia"), "Standard: Intercession counts as a thin battle rez")

  -- The pool gap line: nobody applying brings Bloodlust.
  p = plan({ [1] = BASE[1], [3] = BASE[3], [4] = BASE[4], [5] = BASE[5] }, 10)
  ok(p.status == "none" and p.poolGaps[1] and p.poolGaps[1].label == "Bloodlust" and p.poolGaps[1].must, "pool gap: Bloodlust, a must")
  local cov = table.concat(p.poolGaps[1].coverers, ",")
  ok(cov:find("Shaman") and cov:find("Mage") and cov:find("Evoker") and cov:find("Hunter"), "who could bring it: " .. cov)
  ok(p.blocking:find("^Waiting for Bloodlust: "), "the band says what it's waiting for")
  -- Not enough applicants.
  p = plan({ [1] = BASE[1], [2] = BASE[2] }, 10)
  ok(p.status == "short" and p.blocking == "Waiting for applicants: 2 DPS", "too few applicants: " .. tostring(p.blocking))
  -- Pending invites count toward the group.
  APPLICANT_STATUS = { [2] = "invited" }
  p = plan(with({ [8] = { { name = "Oakra", class = "DRUID", role = "HEALER", spec = 105, score = 3300, ilvl = 320 } } }), 10)
  ok(#p.pending == 1 and p.pending[1].applicantID == 2 and p.slots == 3 and #p.picks == 3 and not names(p.picks):find("Bramok"),
    "a pending invite holds its slot and counts toward the group")
  APPLICANT_STATUS = {}
  -- The leaver flag (the 17th applicant return).
  local lv8 = { [8] = { { name = "Oakra", class = "DRUID", role = "HEALER", spec = 105, score = 3300, ilvl = 320, leaver = true } } }
  p = plan(with(lv8), 10)
  local leaverSkipped
  for _, x in ipairs(p.skipped) do if x.ev.members[1].name == "Oakra" then leaverSkipped = x.reason end end
  ok(ns70.Tracker.applicants[#ns70.Tracker.applicants].isLeaver ~= nil and leaverSkipped == "has the game's leaver flag",
    "leaver flag read and skipped")

  -- Timing: 4 open slots, a full pool (10 healers, 20 DPS) with you as DPS: tank, healer and
  -- 2 DPS open, the worst case.
  ROSTER = { player = { guid = "P", name = "Faelan", class = "MAGE", spec = 63, role = "DAMAGER" } }
  local big, id = {}, 100
  local tanks = { { "WARRIOR", 73 }, { "PALADIN", 66 }, { "DRUID", 104 }, { "DEATHKNIGHT", 250 }, { "MONK", 268 }, { "DEMONHUNTER", 581 } }
  local heals = { { "PALADIN", 65 }, { "DRUID", 105 }, { "PRIEST", 256 }, { "SHAMAN", 264 }, { "MONK", 270 }, { "EVOKER", 1468 } }
  local dps = { { "SHAMAN", 262 }, { "HUNTER", 254 }, { "ROGUE", 259 }, { "WARLOCK", 265 }, { "DEATHKNIGHT", 251 }, { "MONK", 269 },
    { "PRIEST", 258 }, { "EVOKER", 1467 }, { "DRUID", 102 }, { "WARRIOR", 72 } }
  for i = 1, 10 do id = id + 1; local t = tanks[(i - 1) % #tanks + 1]; big[id] = { { name = "T" .. i, class = t[1], role = "TANK", spec = t[2], score = 3000 + i, ilvl = 320 } } end
  for i = 1, 10 do id = id + 1; local t = heals[(i - 1) % #heals + 1]; big[id] = { { name = "H" .. i, class = t[1], role = "HEALER", spec = t[2], score = 3000 + i, ilvl = 320 } } end
  for i = 1, 20 do id = id + 1; local t = dps[(i - 1) % #dps + 1]; big[id] = { { name = "D" .. i, class = t[1], role = "DAMAGER", spec = t[2], score = 3000 + i, ilvl = 320 } } end
  APPLICANTS = big
  ns70.state.keyLevelOverride = 10
  ns70.Tracker:Rescan(); ns70.ApplicantFit.ClearCache(); FG.ClearCache()
  local ctx, evals = ns70.ApplicantFit:ForLiveGroup()
  local t0 = os.clock()
  p = FG:Plan(ctx, evals)
  local ms = (os.clock() - t0) * 1000
  ok(p.status == "ready" and p.leaves <= 8 * 8 * 28 and p.checked <= H70.FILL_MAX_FULL_CHECKS,
    string.format("4 open slots, 40 applicants: %s, %d groups, %d full checks", p.status, p.leaves, p.checked))
  FG.lastTiming = { ms = ms, leaves = p.leaves, checked = p.checked }
  print(string.format("  (timing) Fill group plan at 4 open slots, 40 applicants: %.1f ms, %d groups counted, %d full analyses", ms, p.leaves, p.checked))
  ok(ms < 5000, "the worst case plans in reasonable time here (" .. math.floor(ms) .. " ms)")
  APPLICANTS, LISTING, ROSTER = {}, nil, {}
  ns70.state.keyLevelOverride = nil
  ns70.Tracker:Rescan()
end

-- 71. Fill group in the interface and the invite flow (1.4.0): the band, IN PLAN / SKIPPED,
-- the Fill plan, the click (re-plan, unchanged group only, the pause), one click for every
-- invite or one per click once the game shows it takes only one, the blocked event, the tab
-- dot, Auto-fill (arming, the wait, the sound), the docked panel turning into the plan, the
-- pop-up, Settings > Fill group, saved-data cleaning, /ens verify.
do
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Faelan", class = "WARRIOR", spec = 73, role = "TANK" } }
  LISTING = "Den of Nalorakk (Mythic Keystone)"
  APPLICANT_STATUS = {}
  APPLICANTS = {
    [1] = { { name = "Bralia", class = "PALADIN", role = "HEALER", spec = 65, score = 3464, ilvl = 328 } },
    [2] = { { name = "Bramok", class = "SHAMAN", role = "DAMAGER", spec = 262, score = 3390, ilvl = 324 } },
    [3] = { { name = "Kelor", class = "MONK", role = "DAMAGER", spec = 269, score = 3429, ilvl = 326 } },
    [4] = { { name = "Doriah", class = "PRIEST", role = "DAMAGER", spec = 258, score = 3453, ilvl = 325 } },
    [5] = { { name = "Faren", class = "DEMONHUNTER", role = "DAMAGER", spec = 577, score = 3461, ilvl = 325 } },
    [6] = { { name = "Lumira", class = "PRIEST", role = "HEALER", spec = 257, noScore = true, ilvl = 320 } },
    [8] = { { name = "Oakra", class = "DRUID", role = "HEALER", spec = 105, score = 3300, ilvl = 320 } },
  }
  BUILD = "70448"
  GetBuildInfo = function() return "12.1.5", BUILD, "Oct 1 2026", 120105 end
  SOUNDKIT = { READY_CHECK = 8960 }
  SOUNDS = {}
  PlaySound = function(id) SOUNDS[#SOUNDS + 1] = id end
  local invited = {}
  C_LFGList.InviteApplicant = function(id) invited[#invited + 1] = id end
  local ns71 = boot()
  local UI71, FG = ns71.UI, ns71.FillGroup
  ns71.state.keyLevelOverride = 10
  NOW = 1000
  UI71:Show("applicants"); RunTimers()
  local ap = UI71.ap
  local plan = ap.plan
  ok(plan and plan.status == "ready" and ap.band:IsShown(), "hosting: the Fill group band shows, a group passes")
  ok(ap.band.title:GetText():find("Full group ready", 1, true) and ap.band.fill.text:GetText() == "Fill group (4)", "band: ready, Fill group (4)")
  ok(ap.band.fill.glowOn == true and ap.band.fill.glow:IsShown() and (rawget(ap.band.fill.glowAnim, "_played") or 0) >= 1,
    "the button's glow breathes while a plan passes")
  ok(not ap.band.fill:IsEnabled(), "the button waits a moment after the plan changes")
  NOW = NOW + 2
  RunTimers(); UI71:Refresh()
  ok(ap.band.fill:IsEnabled(), "then it can be clicked")
  ok(ap.context:GetText():find("Pool covers every need", 1, true), "context line: the pool check")
  local top
  for _, pt in ipairs(rawget(ap.sf, "_points") or {}) do if pt[1] == "TOPLEFT" then top = pt end end
  ok(top and top[3] == -(8 + 56 + 6), "the cards start under the band")
  -- Cards: IN PLAN with an accent edge; SKIPPED dimmed with the reason.
  local inPlanN, skippedCard = 0, nil
  for _, c in ipairs(ap.cards) do
    if c:IsShown() and c.chip:IsShown() then
      if c.chip.text:GetText() == "IN PLAN" then inPlanN = inPlanN + 1 end
      if c.chip.text:GetText() == "SKIPPED" then skippedCard = c end
    end
  end
  ok(inPlanN == 4, "four cards marked IN PLAN")
  ok(skippedCard and skippedCard:GetAlpha() < 1 and skippedCard.headline:GetText():find("Skipped: no M+ rating from the game", 1, true),
    "a skipped applicant stays on the list, dimmed, with the reason")
  -- The band opens the Fill plan.
  ap.band:Click(); RunTimers()
  local function detail() local t = {} for i = 1, ap.detail.used do t[#t + 1] = ap.detail.pool[i]:GetText() end return table.concat(t, "\n") end
  ok(ap.detailTitle:GetText() == "FILL PLAN" and detail():find("4 invites, sent together with one click", 1, true)
    and detail():find("WHY THIS GROUP", 1, true) and detail():find("(you)", 1, true) and detail():find("SKIPPED BY YOUR FILTERS (1)", 1, true)
    and detail():find("Ensemble only invites when you click.", 1, true), "Fill plan: the group, why, who was skipped, the invite rule")
  ap.cards[1]:Click(); RunTimers()
  ok(ap.detailTitle:GetText() == "APPLICANT FIT", "clicking a card goes back to Applicant fit")

  -- The click: one click sends every invite (first fill on this build).
  local sig = ap.plan.sig
  ok(FG:InviteMode() == "all", "first fill on a build: one click for the whole plan")
  PRINTED = ""
  ap.band.fill:Click()
  ok(#invited == 4 and FG.lastFill.sent == 4 and PRINTED:find("Invited 4 of 4.", 1, true), "Fill group: four invites from one click")
  ok(FG:LastFillText():find("4 of 4 invites sent", 1, true), "the last fill is recorded for /ens verify")
  -- The game took only the first one: from now on, one per click on this build.
  APPLICANT_STATUS = { [invited[1]] = "invited" }
  RunTimers()
  ok(FG.lastFill.confirmed == 1 and FG.lastFill.stuck == 3 and FG:InviteMode() == "one" and ns71.db.fillInvite.build == "70448",
    "only 1 of 4 taken: invite one per click on this build")
  ok(FG:LastFillText():find("3 not taken", 1, true), "verify line says how many weren't taken")
  ns71.Tracker:Rescan(); ns71.ApplicantFit.ClearCache(); FG.ClearCache()
  NOW = NOW + 2
  local p2 = FG:Current()
  ok(#p2.pending == 1 and FG:ButtonText(p2) == "Invite next (2 of 4)", "button: Invite next (2 of 4)")
  invited = {}
  FG:Fill(p2.sig)
  ok(#invited == 1, "one invite per click")
  -- A new game build tests again.
  BUILD = "70500"
  ok(FG:InviteMode() == "all", "a new game build: one click for everything again")
  BUILD = "70448"
  -- The click re-plans and invites only the group shown; never right after a change.
  APPLICANT_STATUS = {}
  ns71.Tracker:Rescan(); ns71.ApplicantFit.ClearCache(); FG.ClearCache()
  ns71.db.fillInvite = nil
  invited = {}
  local ok1, msg1 = FG:Fill("DenOfNalorakk:9,99")
  ok(not ok1 and msg1:find("The group changed", 1, true) and #invited == 0, "a changed group isn't invited")
  local cur = FG:Current()
  FG.planChangedAt = NOW
  local ok2, msg2 = FG:Fill(cur.sig)
  ok(not ok2 and msg2:find("just changed", 1, true) and #invited == 0, "no invite in the pause after a change")
  NOW = NOW + 2
  -- An error on the second invite: stop there, and one per click from now on.
  local calls = 0
  C_LFGList.InviteApplicant = function(id) calls = calls + 1; if calls == 2 then error("blocked") end; invited[#invited + 1] = id end
  FG:Fill(cur.sig)
  ok(#invited == 1 and FG.lastFill.errors[1] and FG:InviteMode() == "one", "an error on the second invite: one per click")
  -- The game's blocked event naming Ensemble during a fill does the same.
  ns71.db.fillInvite = nil
  C_LFGList.InviteApplicant = function(id) invited[#invited + 1] = id end
  APPLICANT_STATUS = {}
  ns71.Tracker:Rescan(); ns71.ApplicantFit.ClearCache(); FG.ClearCache()
  NOW = NOW + 2
  cur = FG:Current()
  NOW = NOW + 2
  FG:Fill(cur.sig)
  local bw
  for _, fr in ipairs(ALLFRAMES) do if fr._events.ADDON_ACTION_BLOCKED then bw = fr end end
  bw._scripts.OnEvent(bw, "ADDON_ACTION_BLOCKED", "OtherAddon", "Foo")
  ok(FG:InviteMode() == "all", "another addon's blocked event changes nothing")
  bw._scripts.OnEvent(bw, "ADDON_ACTION_BLOCKED", "Ensemble", "InviteApplicant()")
  ok(FG:InviteMode() == "one" and FG.lastFill.blocked == "InviteApplicant()", "blocked during a fill: one per click")
  ns71.db.fillInvite = nil
  -- Not the leader: no invites.
  ROSTER.party1 = { guid = "Q", name = "Mia", class = "MAGE", spec = 63, role = "DAMAGER" }
  local oldLead = UnitIsGroupLeader
  UnitIsGroupLeader = function() return false end
  local can, why = FG:CanInvite({ status = "ready", picks = {}, pending = {} })
  ok(not can and why:find("leader", 1, true), "only the leader (or an assistant) can fill")
  UnitIsGroupLeader = oldLead
  ROSTER.party1 = nil
  APPLICANT_STATUS = {}
  ns71.Tracker:Rescan(); ns71.ApplicantFit.ClearCache(); FG.ClearCache()

  -- Auto-fill: armed per listing; the wait; the sound; told once per group.
  ns71.db.settings.fill.autoArm = true
  LISTING = nil; UI71:OnListingUpdate("LFG_LIST_ACTIVE_ENTRY_UPDATE")
  LISTING = "Den of Nalorakk (Mythic Keystone)"; UI71:OnListingUpdate("LFG_LIST_ACTIVE_ENTRY_UPDATE")
  ok(FG.armed and ns71.Tracker:IsHeldBy("autofill"), "a new listing arms Auto-fill (setting on), and it keeps the data fresh")
  ns71.Tracker:Rescan(); ns71.ApplicantFit.ClearCache(); FG.ClearCache()
  local alerts = {}
  ns71:On("FILL_ALERT", function(p) alerts[#alerts + 1] = p or false end)
  SOUNDS = {}
  FG.notifiedSig, FG.pendingSig = nil, nil
  FG:CheckAutoFill()
  ok(FG.pendingSig and #alerts == 0 and #SOUNDS == 0, "Auto-fill waits before telling you")
  RunTimers()
  ok(FG.notifiedSig and alerts[#alerts] and alerts[#alerts].status == "ready" and SOUNDS[1] == 8960, "then: the sound and the alert")
  local sig1 = FG.notifiedSig
  FG:CheckAutoFill(); RunTimers()
  ok(#SOUNDS == 1, "the same group isn't announced twice")
  -- The tab dot while you're on another tab.
  UI71:SetTab("dungeons"); RunTimers()
  ok(UI71.tabButtons.applicants.dot:IsShown(), "a dot on the Applicants tab while a group passes")
  UI71:SetTab("applicants"); RunTimers()
  ok(not UI71.tabButtons.applicants.dot:IsShown(), "no dot on the Applicants tab itself")
  -- The docked panel turns into the plan (C) while the Group Finder is open.
  PVEFrame:Show()
  UI71:UpdateFinderPanel(); RunTimers()
  local fp = UI71.fp
  ok(fp and fp.planView:IsShown() and fp.planView.title:GetText():find("Full group ready", 1, true)
    and fp.planView.fill.text:GetText() == "Fill group (4)" and not fp.rows[1]:IsShown(), "the docked panel shows the plan")
  ok(fp.planView.side:GetText():find("Musts: Bloodlust", 1, true), "with the musts and the level")
  local pts = rawget(fp.planView, "_points") or {}
  local lastTop
  for _, pt in ipairs(pts) do if pt[1] == "TOPLEFT" then lastTop = pt end end
  ok(lastTop and lastTop[2] == 0 and lastTop[3] == 0 and fp.planView.enter and (rawget(fp.planView.enter, "_played") or 0) >= 1,
    "the plan slides in (the animation plays) and ends in place")
  fp.planView.back:Click(); RunTimers()
  ok(not fp.planView:IsShown(), "Back to list shows the applicants again")
  UI71.fpListFor = nil
  UI71:QueueFinderRefresh(); RunTimers()
  ok(fp.planView:IsShown(), "the plan is back for a new alert")
  -- The pop-up: window and Group Finder both closed.
  PVEFrame:Hide(); UI71:Hide()
  UI71:UpdateFillPopup()
  local pop = UI71.fillPopup
  ok(pop and pop:IsShown() and pop.title:GetText():find("Full group ready", 1, true) and pop.fill.text:GetText() == "Fill group (4)",
    "window and Group Finder closed: the pop-up")
  pop.close:Click()
  ok(not pop:IsShown(), "x hides it until a different group passes")
  UI71.fillPopupDismissed = nil
  ns71.db.settings.fill.popup = false
  UI71:UpdateFillPopup()
  ok(not pop:IsShown(), "no pop-up when that's turned off")
  ns71.db.settings.fill.popup = true
  UI71:UpdateFillPopup()
  ok(pop:IsShown(), "pop-up on again")
  UI71:Show("applicants"); RunTimers()
  ok(not pop:IsShown(), "opening the window hides the pop-up")
  -- The plan stops passing: the alert ends by itself.
  local saved = APPLICANTS
  APPLICANTS = { [1] = saved[1] }
  ns71.Tracker:Rescan(); ns71.ApplicantFit.ClearCache(); FG.ClearCache()
  FG:CheckAutoFill(); RunTimers()
  ok(FG.notifiedSig == nil and alerts[#alerts] == false, "no group passes any more: the alert goes away")
  APPLICANTS = saved
  -- The listing ends: Auto-fill turns off.
  LISTING = nil; UI71:OnListingUpdate("LFG_LIST_ACTIVE_ENTRY_UPDATE")
  ok(not FG.armed and not ns71.Tracker:IsHeldBy("autofill"), "listing gone: Auto-fill off")
  LISTING = "Den of Nalorakk (Mythic Keystone)"; UI71:OnListingUpdate("LFG_LIST_ACTIVE_ENTRY_UPDATE")
  ns71.Tracker:Rescan()

  -- Settings > Fill group.
  UI71:OpenSettings("fill"); RunTimers()
  ok(UI71.settingsFrames.fill:IsShown() and UI71.settingsNav.fill, "Settings has a Fill group section")
  local order = {}
  for _, sec in ipairs(UI71.SETTINGS_SECTIONS) do order[#order + 1] = sec.key end
  ok(table.concat(order, ","):find("finder,fill,chat", 1, true), "between Group Finder and Party chat")
  local rows = UI71.fillMustRows
  ok(rows[1].check.label:GetText():find("^Bloodlust") and UI71.fillMustsPick.text:GetText():find("Den of Nalorakk", 1, true),
    "musts for the key being run, Bloodlust first")
  local freedomRow
  for _, r in ipairs(rows) do if r.check:IsShown() and r.check.label:GetText():find("Rimeshatter", 1, true) then freedomRow = r end end
  ok(freedomRow and freedomRow.get() == true, "boss needs ticked by default, with the boss's cast")
  freedomRow.check:Click(); RunTimers()
  ok(ns71.db.fillMusts.DenOfNalorakk.on.DN_FREEDOM == false, "unticking saves for this dungeon")
  ns71.FillGroup:ResetMusts("DenOfNalorakk"); RunTimers()
  local fr = UI71.fillFilterRows.rating
  ok(fr.src.text:GetText() == "Suggested for the key" and fr.note:GetText():find("In force for +10: 2200", 1, true), "rating filter: suggested, the value for the key")
  ns71.db.settings.fill.rating.source = "custom"; ns71.db.settings.fill.rating.value = 3000
  UI71:RefreshSettings()
  ok(fr.val:GetText() == "3000" and fr.src.text:GetText() == "Custom", "a custom minimum")
  UI71:ResetSettingsSection("fill")
  ok(ns71.db.settings.fill.rating.source == "suggested" and ns71.db.settings.fill.autoArm == false, "Reset section puts Fill group back")
  UI71:Hide()

  -- /ens verify: the Fill group section.
  local report = ns71.Verify:Run()
  ok(report:find("== Fill group ==", 1, true) and report:find("reward item level for +10: end of run 300", 1, true)
    and report:find("leaver flag (17th applicant return) readable", 1, true) and report:find("plan now: ready", 1, true),
    "verify: reward API, leaver flag, the plan")
  ok(report:find("invites sent", 1, true), "verify: the last fill")

  -- Saved data: bad musts and settings are cleaned.
  EnsembleDB = { schema = 4, fillMusts = { DenOfNalorakk = { lust = "yes", on = { DN_FREEDOM = 1, [3] = true, DN_TOXIC_SPORES = false } },
    NotADungeon = { on = {} }, MurderRow = "x" }, fillInvite = { oneAtATime = true },
    settings = { fill = { level = "max", rating = { source = "web", value = "a" }, ilvl = 7, wait = 999 } } }
  local nsS = boot()
  local fm = nsS.db.fillMusts
  ok(fm.DenOfNalorakk and fm.DenOfNalorakk.lust == nil and fm.DenOfNalorakk.on.DN_FREEDOM == nil and fm.DenOfNalorakk.on.DN_TOXIC_SPORES == false
    and fm.NotADungeon == nil and fm.MurderRow == nil, "saved musts cleaned")
  local fs = nsS.db.settings.fill
  ok(fs.level == "auto" and fs.rating.source == "suggested" and fs.rating.value == 2500 and type(fs.ilvl) == "table" and fs.wait == 120
    and nsS.db.fillInvite == nil, "Fill group settings cleaned")
  ok(nsS.RESET_WIPES:find("Fill group musts", 1, true), "a full reset names the musts")

  C_LFGList.InviteApplicant = nil
  GetBuildInfo, PlaySound, SOUNDKIT = nil, nil, nil
  APPLICANTS, LISTING, ROSTER, APPLICANT_STATUS = {}, nil, {}, nil
  PVEFrame._shown = false
end

-- 72. 1.4.0 test findings (October 24, 125% text): Settings > Fill group stacks by real
-- height, the musts' buttons follow the last must ("Reset needs"); the hosting applicant panel
-- on Composition follows the slots and its rows fit at larger text; verify WARNs on a 0
-- end-of-run reward item level.
do
  EnsembleDB = nil
  ROSTER = {
    player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" },
    party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" },
  }
  INSPECT_CACHE = { H = 256 }
  LISTING = "Altar of Fangs (Mythic Keystone)"
  APPLICANTS = {
    [1] = { { name = "Shamy", class = "SHAMAN", role = "DAMAGER", spec = 263 } },
    [2] = { { name = "Stabby", class = "ROGUE", role = "DAMAGER", spec = 259, score = 3100 } },
    [3] = { { name = "Kitty", class = "DRUID", role = "DAMAGER", spec = 103 } },
  }
  local ns72 = boot()
  local UI72 = ns72.UI
  local function pt(fr, i) return (rawget(fr, "_points") or {})[i or 1] or {} end
  local function find(text) for _, fr in ipairs(ALLFRAMES) do if rawget(fr, "_text") == text then return fr end end end

  -- Settings > Fill group: each level hangs below the description above it.
  UI72:OpenSettings("fill"); RunTimers()
  local relaxed, strictNote = find("Relaxed"), find("Nothing medium+ missing; critical and high not thin")
  local autoNote = find("Relaxed to +6, Standard +7 to +11, Strict from +12")
  -- The label is a font string inside the check; the check is its parent's anchor chain.
  local relaxedCheck
  for _, c in ipairs(UI72.checks) do if c.label == relaxed then relaxedCheck = c end end
  ok(relaxedCheck and pt(relaxedCheck)[1] == "TOPLEFT" and pt(relaxedCheck)[2] == autoNote and pt(relaxedCheck)[3] == "BOTTOMLEFT",
    "Fill group: a level hangs below the previous level's description")
  local head = find("Always require:")
  ok(head and pt(head)[2] == strictNote and pt(head)[3] == "BOTTOMLEFT", "\"Always require\" hangs below the last level")
  local box = UI72.fillMustsBox
  ok(pt(box)[2] == UI72.fillMustsNote and pt(UI72.fillMustsNote)[2] == head, "the musts box hangs below its note")
  local add, reset = UI72.fillMustsAdd, UI72.fillMustsReset
  ok(pt(add)[1] == "TOPLEFT" and pt(add)[2] == box and pt(add)[3] == "BOTTOMLEFT", "\"+ Add a need\" sits right under the last must")
  ok(reset.text:GetText() == "Reset needs" and pt(reset)[2] == add and not find("Back to boss needs"), "\"Reset needs\" beside it (was \"Back to boss needs\")")
  ok(reset.tooltip:find("defaults", 1, true), "its tooltip says what it resets to")
  -- The box is as tall as its rows, so the buttons move with the dungeon's list.
  local inner = UI72.fillMustInner
  local function rowsFor(dk) UI72.fillMustsDk = dk; UI72:RefreshSettings(); return inner:GetHeight(), box:GetHeight() end
  local hA, bA = rowsFor("AltarOfFangs")
  local hK, bK = rowsFor("KingsRest")
  ok(bA == hA and bK == hK and hK > hA, string.format("box follows the list: Altar of Fangs %d px, Kings' Rest %d px", bA, bK))
  -- With real positions: capped so the buttons stay inside the panel; the rest scrolls.
  rawset(box, "_top", 300); rawset(UI72.fillPanel, "_bottom", 100)
  UI72:LayoutFillMusts()
  ok(box:GetHeight() == math.min(hK, 300 - 100 - 44), "capped by the room under it (" .. box:GetHeight() .. ")")
  rawset(box, "_top", 1000); UI72:LayoutFillMusts()
  ok(box:GetHeight() == hK, "plenty of room: the whole list, no scrolling")
  rawset(box, "_top", nil); rawset(UI72.fillPanel, "_bottom", nil)
  UI72.fillMustsDk = nil
  -- The invite note hangs below the wait note (two lines at larger text).
  local waitNote = find("Gives more players time to apply, so the first full group isn't the only one seen.")
  local inviteNote = find("Ensemble only invites when you click: Auto-fill finds the group and tells you; you send the invites.")
  ok(pt(inviteNote)[2] == waitNote and pt(inviteNote)[3] == "BOTTOMLEFT", "Auto-fill notes stack")

  -- Composition while hosting, at 125%: the panel follows the slots.
  UI72:Show("applicants"); RunTimers()
  UI72:Show("composition"); RunTimers()
  local cp = UI72.cp
  local f = cp.appPanel
  ok(f:IsShown(), "hosting: the applicant panel shows")
  local FP = UI72.FontPx
  local function slotTop()
    local h = math.max(40, FP(13) + FP(11) + 14)
    return -8 - ns72.NUM_SLOTS * (h + 4) - 4
  end
  ok(pt(f)[1] == "TOPLEFT" and pt(f)[3] == slotTop() - 4, "100%: the panel starts under the slots (" .. tostring(pt(f)[3]) .. ")")
  local function measure(self)
    local t = tostring(rawget(self, "_text") or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  ")
    return #t * (rawget(self, "_fontSize") or 12) * 0.6
  end
  for _, fr in ipairs(ALLFRAMES) do rawset(fr, "GetUnboundedStringWidth", measure) end
  UI72:SetTextSize(125); RunTimers()
  ok(pt(f)[3] == slotTop() - 4 and slotTop() < -228, "125%: the panel moves down with the taller slots (" .. tostring(pt(f)[3]) .. ")")
  local rowH = UI72:AppRowH()
  ok(rowH == FP(12) + FP(10) + 14 and rowH > 36, "125%: applicant rows grow (" .. rowH .. " px)")
  local r1, r2 = f.rows[1], f.rows[2]
  ok(r1._h == rowH - 4 and pt(r2)[3] == -20 - rowH, "rows at the new pitch")
  ok(pt(r1.name)[1] == "TOPLEFT" and pt(r1.name)[2] == 36 and pt(r1.head)[1] == "BOTTOMLEFT" and pt(r1.head)[3] == 4, "name on the row's top edge, headline on its bottom edge")
  -- The title stops before the links and fits.
  local tp
  for _, p in ipairs(rawget(f.title, "_points")) do if p[1] == "RIGHT" then tp = p end end
  ok(tp and tp[2] == f.open and f.title.cmFit ~= nil, "title ends before \"Open tab\" and fits its room")
  -- The name and headline end left of the status column, however wide it is.
  -- The game replaces a repeated anchor; the stub keeps every call, so read the last RIGHT.
  local function rightGap(fs)
    local g
    for _, p in ipairs(rawget(fs, "_points")) do if p[1] == "RIGHT" then g = -p[4] end end
    return g
  end
  UI72:Refresh(); RunTimers()
  local widest = math.max(measure(r1.tag), measure(r1.after))
  ok(rightGap(r1.name) >= widest + 12 and rightGap(r1.head) == rightGap(r1.name) and rightGap(r1.name) >= 72,
    string.format("125%%: text ends left of the status (%d px gap, status %d px)", rightGap(r1.name), widest))
  UI72:SetTextSize(100); RunTimers()
  ok(UI72:AppRowH() == 36 and pt(f)[3] == slotTop() - 4, "back at 100%: 36 px rows, panel under the slots")
  UI72:Hide()

  -- /ens verify: a 0 end-of-run reward item level is a WARN, not OK.
  local orig = C_MythicPlus.GetRewardLevelForDifficultyLevel
  C_MythicPlus.GetRewardLevelForDifficultyLevel = function() return 318, 0 end
  local report = ns72.Verify:Run()
  ok(report:find("[WARN] reward item level for +10: end of run 0, weekly 318 - no end-of-run value", 1, true),
    "verify: end of run 0 WARNs (the suggested item level stays off)")
  C_MythicPlus.GetRewardLevelForDifficultyLevel = orig
  report = ns72.Verify:Run()
  ok(report:find("[OK] reward item level for +10: end of run 300, weekly 310 (suggested item level reads this)", 1, true),
    "verify: a real value stays OK")
  for _, fr in ipairs(ALLFRAMES) do rawset(fr, "GetUnboundedStringWidth", nil) end

  -- The group-ready sound (the author's pick, October 24: chime A with a picker).
  local FG72 = ns72.FillGroup
  local files, kits = {}, {}
  local fileWillPlay = true
  PlaySoundFile = function(path, ch) files[#files + 1] = path .. "|" .. tostring(ch); return fileWillPlay, 1 end
  SOUNDKIT = { READY_CHECK = 8960 }
  PlaySound = function(id, ch) kits[#kits + 1] = id .. "|" .. tostring(ch); return true end
  local fs72 = ns72.db.settings.fill
  ok(fs72.soundChoice == "chime" and fs72.sound == true, "default: the sound is on, Ensemble's chime")
  ok(FG72:PlayReadySound() == "chime" and files[1] == ns72.READY_SOUND .. "|Master" and #kits == 0, "the chime plays from the addon's Media folder, on Master")
  ok(ns72.READY_SOUND == "Interface\\AddOns\\Ensemble\\Media\\GroupReady.ogg", "path to the chime")
  local slurp = function(path) local fh = io.open(path, "rb"); if not fh then return nil end local t = fh:read("*a"); fh:close(); return t end
  local ogg = slurp(ADDON_DIR .. "/Media/GroupReady.ogg")
  ok(ogg and ogg:sub(1, 4) == "OggS" and #ogg < 64 * 1024, "the chime ships in Media as a small Ogg file")
  fs72.soundChoice = "readycheck"
  ok(FG72:PlayReadySound() == "readycheck" and kits[1] == "8960|Master" and #files == 1, "the game's ready check, by choice")
  fs72.soundChoice = "chime"
  fileWillPlay = false
  ok(FG72:PlayReadySound() == "readycheck" and #kits == 2, "the chime can't play: the ready check instead")
  local report = ns72.Verify:Run()
  ok(report:find("[WARN] last group-ready sound: game ready check (picked: Ensemble chime)", 1, true), "verify: says the chime didn't play")
  fileWillPlay = true
  local savedPSF = PlaySoundFile
  PlaySoundFile = nil
  ok(FG72:PlayReadySound() == "readycheck", "no PlaySoundFile: the ready check")
  report = ns72.Verify:Run()
  ok(report:find("[WARN] PlaySoundFile (Auto-fill's Ensemble chime) missing: the game's ready-check sound plays instead", 1, true), "verify: PlaySoundFile missing WARNs")
  PlaySoundFile = savedPSF
  FG72:PlayReadySound()
  report = ns72.Verify:Run()
  ok(report:find("[OK] PlaySoundFile (Auto-fill's Ensemble chime)", 1, true) and report:find("[OK] last group-ready sound: Ensemble chime", 1, true),
    "verify: the chime present and played")
  -- Notify plays it once, and nothing when the sound is off.
  local origFire = ns72.Fire
  ns72.Fire = function() end
  local before = #files
  FG72:Notify({})
  ok(#files == before + 1, "a new group: the chime plays")
  fs72.sound = false
  FG72:Notify({})
  ok(#files == before + 1 and #kits == 3, "sound off: nothing plays")
  fs72.sound = true
  ns72.Fire = origFire
  -- Settings > Fill group: the menu and the Play button.
  UI72:OpenSettings("fill"); RunTimers()
  ok(UI72.fillSoundBtn.text:GetText() == "Ensemble chime", "Settings: the sound menu shows the chime")
  local items
  local oldShow = UI72.ShowMenu
  UI72.ShowMenu = function(_, _, it) items = it end
  UI72.fillSoundBtn:Click()
  UI72.ShowMenu = oldShow
  ok(items and #items == 2 and items[1].text == "Ensemble chime" and items[1].selected and items[2].text == "Game ready check", "the menu: chime (picked), game ready check")
  items[2].onClick()
  ok(fs72.soundChoice == "readycheck" and UI72.fillSoundBtn.text:GetText() == "Game ready check", "picking the ready check")
  local k0 = #kits
  UI72.fillSoundPlay:Click()
  ok(#kits == k0 + 1, "Play: hear the picked sound")
  UI72:ResetSettingsSection("fill")
  ok(fs72.soundChoice == "chime" or ns72.db.settings.fill.soundChoice == "chime", "Reset section: back to the chime")
  UI72:Hide()
  -- Saved data: an unknown choice goes back to the chime.
  EnsembleDB = { schema = 4, settings = { fill = { soundChoice = "airhorn" } } }
  local nsS72 = boot()
  ok(nsS72.db.settings.fill.soundChoice == "chime", "saved sound choice cleaned")
  PlaySoundFile, PlaySound, SOUNDKIT = nil, nil, nil
  APPLICANTS, LISTING, ROSTER, INSPECT_CACHE = {}, nil, {}, {}
end

-- 73. 1.4.1 code review fixes (October 24, 2026): the planner never misses a passing group (the
-- quick counts never rule one out; a need-aware keep after the per-role cut), Strict counts only
-- solid sources where a fallback can't pass, a party member's spec change after joining from the
-- listing, the rating/item level steppers, the sound with game sound off, thin musts shown as
-- thin, a one-click fill remembered, and the small interface fixes.
do
  -- A seeded generator of our own, so LuaJIT and Lua 5.1 test the same groups.
  local seed = 12345
  local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return math.floor(seed / 65536) % n + 1 end
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Faelan", class = "WARRIOR", spec = 73, role = "TANK" } }
  LISTING = "Den of Nalorakk (Mythic Keystone)"
  APPLICANT_STATUS, APPLICANTS, INSPECT_CACHE = {}, {}, {}
  local ns73 = boot()
  local FG, UD, DD, A, H = ns73.FillGroup, ns73.UD, ns73.Dungeons, ns73.Analysis, ns73.Dungeons.HEURISTICS
  local s = ns73.db.settings
  local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
  for id, p in pairs(UD.specs) do table.insert(byRole[p.role], { id = id, class = p.class }) end
  for _, r in pairs(byRole) do table.sort(r, function(a, b) return a.id < b.id end) end

  -- The quick counts are a necessary condition of the judge: a group they rule out never passes.
  -- (Before the review, a critical need at Strict asked for 2 solid sources while the judge takes
  -- one solid plus a pet's or a conditional one: Temple of Sethraliss's Magic dispel.)
  local bad, ruled, passed = 0, 0, 0
  for _ = 1, 300 do
    local dk = DD.order[rnd(#DD.order)]
    local level = FG.LEVELS[rnd(3)]
    local musts = FG:Musts(dk)
    local function mem(role, pend)
      local sp = byRole[role][rnd(#byRole[role])]
      return { specID = (not pend) and sp.id or nil, classFile = sp.class, role = role, label = role }
    end
    local all = { mem("TANK"), mem("HEALER"), mem("DAMAGER"), mem("DAMAGER"), mem("DAMAGER", rnd(12) == 1) }
    local specs = FG.BuildSpecs(A:Analyze({ all[1] }, dk, s), level, musts, s)
    local counts = {}
    for _, m in ipairs(all) do for i, v in ipairs(FG.MemberCounts(m, specs, s)) do counts[i] = (counts[i] or 0) + v end end
    local cheap = FG.CheapFails(specs, counts)
    local pass = FG:Judge(A:Analyze(all, dk, s), level, musts, s).pass
    if cheap > 0 then ruled = ruled + 1 end
    if pass then passed = passed + 1 end
    if cheap > 0 and pass then bad = bad + 1 end
  end
  ok(bad == 0 and ruled > 50 and passed > 50, string.format("quick counts never rule out a passing group (%d ruled out, %d pass, %d both)", ruled, passed, bad))

  -- The plan against the same search with no per-role cut and no check cap: never "none" when a
  -- group passes. The cut is 4 per role here so it bites often; the keep-back must be used.
  local listings = { "Den of Nalorakk (Mythic Keystone)", "Altar of Fangs (Mythic Keystone)", "Kings' Rest (Mythic Keystone)",
    "Murder Row (Mythic Keystone)", "The Blinding Vale (Mythic Keystone)", "Temple of Sethraliss (Mythic Keystone)",
    "Voidscar Arena (Mythic Keystone)", "Ruby Life Pools (Mythic Keystone)" }
  local function plan(apps, level)
    APPLICANTS = apps
    ns73.state.keyLevelOverride = level
    ns73.Tracker:Rescan()
    ns73.ApplicantFit.ClearCache(); FG.ClearCache()
    return FG:Current()
  end
  local oldPer, oldCap = H.FILL_POOL_PER_ROLE, H.FILL_MAX_FULL_CHECKS
  local missed, readyBoth, keptBack, lower = 0, 0, 0, 0
  for t = 1, 12 do
    LISTING = listings[(t % #listings) + 1]
    local apps, id = {}, 1
    for i = 1, 1 + rnd(3) do
      local sp = byRole.HEALER[rnd(#byRole.HEALER)]
      apps[id] = { { name = "H" .. i, class = sp.class, role = "HEALER", spec = sp.id, score = 3000 + rnd(600), ilvl = 320 } }; id = id + 1
    end
    for i = 1, 8 + rnd(10) do
      local sp = byRole.DAMAGER[rnd(#byRole.DAMAGER)]
      apps[id] = { { name = "D" .. i, class = sp.class, role = "DAMAGER", spec = sp.id, score = 3000 + rnd(600), ilvl = 320 } }; id = id + 1
    end
    H.FILL_POOL_PER_ROLE, H.FILL_MAX_FULL_CHECKS = 4, 60
    local p = plan(apps, 14)
    keptBack = keptBack + (p.keptBack or 0)
    H.FILL_POOL_PER_ROLE, H.FILL_MAX_FULL_CHECKS = 99, 100000
    local q = plan(apps, 14)
    if q.status == "ready" then
      if p.status ~= "ready" then missed = missed + 1
      else readyBoth = readyBoth + 1; if p.total < q.total then lower = lower + 1 end end
    end
  end
  H.FILL_POOL_PER_ROLE, H.FILL_MAX_FULL_CHECKS = oldPer, oldCap
  ok(missed == 0 and readyBoth > 0 and keptBack > 0, string.format("Strict: the cut never hides a passing group (%d missed, %d ready, %d kept back)", missed, readyBoth, keptBack))
  ok(lower == 0, "and the plan's group is the best total the uncut search finds")

  -- Strict with Intercession the only battle rez: a pool gap with who could bring it, decided by
  -- the quick counts (no full analyses), not "Closest group: thin Battle resurrection".
  LISTING = "Kings' Rest (Mythic Keystone)"
  local pal = {}
  for i = 1, 3 do pal[i] = { { name = "HP" .. i, class = "PALADIN", role = "HEALER", spec = 65, score = 3300 + i, ilvl = 320 } } end
  local dps = { { "SHAMAN", 262 }, { "MAGE", 63 }, { "ROGUE", 259 }, { "PRIEST", 258 }, { "DEMONHUNTER", 577 }, { "MONK", 269 }, { "EVOKER", 1467 } }
  for i, d in ipairs(dps) do pal[#pal + 1] = { { name = "D" .. i, class = d[1], role = "DAMAGER", spec = d[2], score = 3200 + i, ilvl = 320 } } end
  local p = plan(pal, 14)
  ok(p.status == "none" and p.checked <= 1 and not p.capped, "Strict, Intercession only: no group, " .. tostring(p.checked) .. " full analyses")
  ok(p.blocking == "Waiting for Battle resurrection: Death Knight, Druid or Warlock", "Strict: the pool gap names who could bring it: " .. tostring(p.blocking))
  p = plan(pal, 10)
  ok(p.status == "ready", "Standard: Intercession still passes as a thin battle rez")

  -- A thin must passes below Strict but is listed as thin, never shown as covered.
  local req = { id = "T_MUST", need = "interrupt", source = "Test Cast (Test Boss)", severity = "critical", confidence = "verified", minProviders = 2 }
  local r = { caps = { interrupt = { { index = 1, member = {}, entry = { name = "Kick" } } } }, dungeon = { items = {} }, findings = {} }
  local j = FG:Judge(r, "standard", { lust = false, reqs = { req }, labels = { T_MUST = "Interrupts for Test Cast" } }, s)
  local thinMust = false
  for _, t in ipairs(j.thin) do if t == "Interrupts for Test Cast (must)" then thinMust = true end end
  ok(j.mustRows[1].status == "thin" and thinMust, "a thin must is in the thin list, marked (must)")
  j = FG:Judge(r, "strict", { lust = false, reqs = { req }, labels = { T_MUST = "Interrupts for Test Cast" } }, s)
  ok(not j.pass and j.fails[1].must, "and Strict still stops on it")

  -- A one-click fill that the game took whole is remembered for the build (verify after /reload).
  ns73.db.fillInvite = nil
  APPLICANTS = {}
  ns73.Tracker:Rescan()
  FG:ConfirmFill({ ids = { 901, 902 }, errors = {}, sent = 2, planned = 2, mode = "all" })
  local fi = ns73.db.fillInvite
  ok(fi and fi.oneAtATime == false and fi.build == FG.GameBuild() and FG:InviteMode() == "all", "a whole one-click fill is saved for this build")
  local report = ns73.Verify:Run()
  ok(report:find("[OK] invites: one click sends the whole plan (seen on build", 1, true), "verify: the one-click result shows after a reload")
  ns73.db.fillInvite = { oneAtATime = true, build = FG.GameBuild(), reason = "learned" }
  FG:ConfirmFill({ ids = { 901, 902 }, errors = {}, sent = 2, planned = 2, mode = "all" })
  ok(ns73.db.fillInvite.oneAtATime == true, "never replaces a learned one-per-click for the build")
  ns73.db.fillInvite = nil
  FG:ConfirmFill({ ids = { 901, 902 }, errors = {}, sent = 2, planned = 2, mode = "all", blocked = "InviteApplicant" })
  ok(ns73.db.fillInvite == nil, "a blocked fill isn't saved as a success")

  -- Sound with game sound off: neither plays; verify doesn't blame the chime.
  SOUNDKIT = { READY_CHECK = 8960 }
  PlaySoundFile = function() return false end
  PlaySound = function() return false end
  ok(FG:PlayReadySound("chime") == nil and FG.lastSound.soundOff, "game sound off: nothing played, recorded as sound off")
  report = ns73.Verify:Run()
  ok(report:find("[INFO] last group-ready sound: nothing played - the game wasn't playing sounds", 1, true)
    and not report:find("(picked: Ensemble chime)", 1, true), "verify: sound off, not a chime problem")
  PlaySound = function() return true end
  FG:PlayReadySound("chime")
  report = ns73.Verify:Run()
  ok(FG.lastSound.played == "readycheck" and report:find("[WARN] last group-ready sound: game ready check (picked: Ensemble chime)", 1, true),
    "the chime alone won't play: the ready check, and verify says so")
  PlaySound = function() end
  ok(FG:PlayReadySound("readycheck") == "readycheck", "a PlaySound that returns nothing still counts as played")
  PlaySoundFile, PlaySound, SOUNDKIT = nil, nil, nil

  -- A party member who joined from the listing, then changes spec: the old spec doesn't come back.
  LISTING = "Den of Nalorakk (Mythic Keystone)"
  APPLICANTS = { [1] = { { name = "Bralia-Stormrage", class = "PALADIN", role = "HEALER", spec = 65, score = 3400, ilvl = 320 } } }
  local T = ns73.Tracker
  T:Acquire("test73"); T:Rescan()
  APPLICANTS = {}
  ROSTER.party1 = { guid = "G-B", name = "Bralia", class = "PALADIN", spec = 65, role = "HEALER" }
  local origUnitName = UnitName
  UnitName = function(u) if u == "party1" then return "Bralia", "Stormrage" end return origUnitName(u) end
  T:Rescan()
  local function specOf() for _, m in ipairs(T.members) do if m.guid == "G-B" then return m.specID end end end
  ok(specOf() == 65, "joined from the listing: the spec from the application")
  ROSTER.party1.spec, ROSTER.party1.role = 70, "DAMAGER"
  NOTIFIED = {}
  local fr
  for _, f in ipairs(ALLFRAMES) do if f._events and f._events.PLAYER_SPECIALIZATION_CHANGED and f._events.INSPECT_READY then fr = f end end
  fr._scripts.OnEvent(fr, "PLAYER_SPECIALIZATION_CHANGED", "party1")
  T:Rescan(); RunTimers()
  ok(specOf() == nil and #NOTIFIED > 0, "a spec change: the old spec is gone and an inspect is queued")
  INSPECT_CACHE["G-B"] = 70
  fr._scripts.OnEvent(fr, "INSPECT_READY", "G-B")
  T:Rescan()
  ok(specOf() == 70, "the inspect gives the new spec")
  UnitName = origUnitName
  T:Release("test73")
  ROSTER.party1 = nil

  -- Settings: "+" and "-" step from the number shown (Suggested 3250 at +17 -> 3300, not 2550).
  ns73.state.keyLevelOverride = 17
  APPLICANTS = {}
  T:Rescan()
  local UI73 = ns73.UI
  UI73:Show("applicants"); RunTimers()
  UI73:OpenSettings("fill"); RunTimers()
  local fr73 = UI73.fillFilterRows.rating
  ok(fr73.val:GetText() == "3250", "suggested minimum for +17 shown: " .. tostring(fr73.val:GetText()))
  local plusB, minusB
  for _, f in ipairs(ALLFRAMES) do
    if rawget(f, "tooltip") == "Raise (sets a custom number)" and not plusB then plusB = f end
    if rawget(f, "tooltip") == "Lower (sets a custom number)" and not minusB then minusB = f end
  end
  plusB:Click(); RunTimers()
  ok(s.fill.rating.source == "custom" and s.fill.rating.value == 3300 and fr73.val:GetText() == "3300", "\"+\" from Suggested 3250: Custom 3300")
  minusB:Click(); minusB:Click(); RunTimers()
  ok(s.fill.rating.value == 3200, "then \"-\" steps from the custom number")
  UI73:ResetSettingsSection("fill")

  -- The musts note names where the dungeon came from.
  UI73.fillMustsDk = nil
  ns73.state.liveDungeon = "MurderRow"
  local dk, how = UI73:FillMustsDungeon()
  ok(dk == "MurderRow" and how == "your pick on the Applicants tab", "musts follow a hand pick, and say so: " .. tostring(how))
  ns73.state.liveDungeon = "AUTO"
  ns73.state.autoDungeon, ns73.state.autoSource = "AltarOfFangs", "zone"
  dk, how = UI73:FillMustsDungeon()
  ok(dk == "AltarOfFangs" and how == "the dungeon you're in", "musts follow the dungeon you're in: " .. tostring(how))
  ns73.state.autoSource = "listing"
  dk, how = UI73:FillMustsDungeon()
  ok(how == "your listing", "and your listing")
  ns73.state.autoDungeon, ns73.state.autoSource = nil, nil

  -- The pop-up's Fill group button keeps its tooltip while off.
  local motion = false
  local oldCF = CreateFrame
  CreateFrame = function(...)
    local f = oldCF(...)
    rawset(f, "SetMotionScriptsWhileDisabled", function(_, v) if v then motion = true end end)
    return f
  end
  UI73.fillPopup = nil
  UI73:BuildFillPopup()
  CreateFrame = oldCF
  ok(motion, "pop-up: the Fill group button shows its tooltip while off")

  -- "Hide Poor" never hides a player in the Fill plan (the band names them).
  LISTING = "Den of Nalorakk (Mythic Keystone)"
  APPLICANTS = {
    [1] = { { name = "Poorly", class = "ROGUE", role = "DAMAGER", spec = 259, score = 3000, ilvl = 320 } },
    [2] = { { name = "Other", class = "MAGE", role = "DAMAGER", spec = 63, score = 3000, ilvl = 320 } },
  }
  T:Rescan()
  local Fit = ns73.ApplicantFit
  local origLive, origCurrent = Fit.ForLiveGroup, FG.Current
  Fit.ForLiveGroup = function(self)
    local ctx, list = origLive(self)
    for _, ev in ipairs(list) do
      local rt = {}
      for k, v in pairs(ev.rating) do rt[k] = v end
      rt.key = "poor"; ev.rating = rt
    end
    return ctx, list
  end
  FG.Current = function()
    local _, list = Fit:ForLiveGroup()
    local pick
    for _, ev in ipairs(list) do if ev.members[1].name == "Poorly" then pick = ev end end
    return { status = "none", picks = { pick }, skipped = {}, pending = {}, poolGaps = {}, level = "standard", blocking = "test" }
  end
  s.applicantView.hidePoor = true
  UI73:Show("applicants"); UI73:Refresh(); RunTimers()
  local shown, poorlyShown = 0, false
  for _, c in ipairs(UI73.ap.cards) do
    if c:IsShown() then
      shown = shown + 1
      if tostring(c.name:GetText()):find("Poorly", 1, true) then poorlyShown = true end
    end
  end
  ok(poorlyShown and shown == 1, "Hide Poor: the planned player stays, the other Poor one is hidden (" .. shown .. " shown)")
  Fit.ForLiveGroup, FG.Current = origLive, origCurrent
  s.applicantView.hidePoor = false
  UI73:Hide()
  ns73.state.keyLevelOverride = nil
  APPLICANTS, LISTING, ROSTER, INSPECT_CACHE, NOTIFIED = {}, nil, {}, {}, {}
end

-- 74. Efficiency (1.5.0, C1-C3): only the open tab refreshes on the events it shows; History
-- draws 50 runs at a time and counts repeated gaps in one pass; the boss window coalesces.
do
  EnsembleDB = nil
  ROSTER = { player = { guid = "P", name = "Faelan", class = "WARRIOR", spec = 73, role = "TANK" } }
  LISTING, APPLICANTS, APPLICANT_STATUS, INSPECT_CACHE = nil, {}, {}, {}
  local ns74 = boot()
  local UI74 = ns74.UI
  ns74.db.settings.bossWindow.autoOpen = false   -- entering a dungeon would open it and hold the roster
  UI74:Show("history"); RunTimers()
  local count = 0
  local origRefresh = UI74.Refresh
  UI74.Refresh = function(self, ...) count = count + 1; return origRefresh(self, ...) end
  local function fired(tab, ev)
    UI74:SetTab(tab); RunTimers(); count = 0
    ns74:Fire(ev); RunTimers()
    return count
  end
  -- C1: each event refreshes the tabs that show it and skips the rest.
  local cases = {
    { "COMP_CHANGED", { composition = 1, plan = 1, applicants = 0, dungeons = 0, history = 0, settings = 0 } },
    { "LUST_CHANGED", { composition = 0, plan = 1, applicants = 0, dungeons = 1, history = 0, settings = 0 } },
    { "BOSS_ORDER_CHANGED", { composition = 0, plan = 1, applicants = 0, dungeons = 1, history = 0, settings = 0 } },
    { "ASSIGNMENTS_CHANGED", { composition = 0, plan = 1, applicants = 0, dungeons = 0, history = 0, settings = 0 } },
    { "HISTORY_CHANGED", { composition = 0, plan = 0, applicants = 0, dungeons = 0, history = 1, settings = 0 } },
    { "DUNGEON_CHANGED", { composition = 1, plan = 1, applicants = 1, dungeons = 1, history = 0, settings = 0 } },
    { "BOSS_DUNGEON_ENTERED", { composition = 0, plan = 0, applicants = 0, dungeons = 1, history = 0, settings = 0 } },
    { "FILL_ALERT", { composition = 0, plan = 0, applicants = 1, dungeons = 0, history = 0, settings = 0 } },
    { "SETTINGS_CHANGED", { composition = 1, plan = 1, applicants = 1, dungeons = 1, history = 1, settings = 1 } },
  }
  for _, c in ipairs(cases) do
    for tab, want in pairs(c[2]) do
      local got = fired(tab, c[1])
      ok(got == want, "C1: " .. c[1] .. " on " .. tab .. " refreshes " .. want .. " time(s) (got " .. got .. ")")
    end
  end
  -- The roster refreshes the live views only: Applicants always, Composition and Plan in party
  -- mode, never History or Dungeon (before 1.5.0, any tab while the mode was still "live").
  ns74.db.settings.compMode = "party"
  ok(fired("applicants", "LIVE_ROSTER_CHANGED") == 1, "C1: roster refreshes Applicants")
  ok(fired("composition", "LIVE_ROSTER_CHANGED") == 1, "C1: roster refreshes Composition in party mode")
  ok(fired("plan", "LIVE_ROSTER_CHANGED") == 1, "C1: roster refreshes Plan in party mode")
  UI74:SetTab("applicants"); RunTimers()   -- leaves the mode "live", as the old code saw it
  ok(fired("history", "LIVE_ROSTER_CHANGED") == 0, "C1: roster skips History while hosting")
  UI74:SetTab("applicants"); RunTimers()
  ok(fired("dungeons", "LIVE_ROSTER_CHANGED") == 0, "C1: roster skips the Dungeon tab while hosting")
  ns74.db.settings.compMode = "planner"
  ok(fired("composition", "LIVE_ROSTER_CHANGED") == 0, "C1: roster skips Composition in planner mode")
  -- Settings refreshes on roster and dungeon changes only while Fill group's section is open.
  UI74:SetTab("settings"); UI74:ShowSettingsSection("general")
  ok(fired("settings", "LIVE_ROSTER_CHANGED") == 0 and fired("settings", "DUNGEON_CHANGED") == 0,
    "C1: Settings > General skips roster and dungeon changes")
  UI74:ShowSettingsSection("fill")
  ok(fired("settings", "DUNGEON_CHANGED") == 1 and fired("settings", "FILL_SETTINGS_CHANGED") == 1,
    "C1: Settings > Fill group follows the dungeon and its own settings")
  -- A skipped tab is never stale: showing it refreshes it.
  UI74:SetTab("history"); RunTimers(); count = 0
  ns74:Fire("ASSIGNMENTS_CHANGED"); RunTimers()
  UI74:SetTab("plan")
  ok(count == 1, "C1: a tab that skipped an event refreshes when shown")
  -- The Applicants tab dot still follows the roster from another tab.
  local dotCalls = 0
  local origDot = UI74.SyncFillTabDot
  UI74.SyncFillTabDot = function(self) dotCalls = dotCalls + 1; return origDot(self) end
  UI74:SetTab("history"); RunTimers(); dotCalls = 0
  ns74:Fire("LIVE_ROSTER_CHANGED"); RunTimers()
  ok(dotCalls >= 1, "C1: the tab dot follows the roster on other tabs")
  UI74.SyncFillTabDot = origDot
  UI74.Refresh = origRefresh

  -- C2: History draws 50 runs, then 50 more per click; nothing stored is out of reach.
  local seed = 7
  local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return math.floor(seed / 65536) % n + 1 end
  local DD74 = ns74.Dungeons
  local titles = { "Bloodlust", "Battle resurrection", "Poison dispel", "Magic dispel" }
  local results = { "timed", "overtime", "overtime", "abandoned" }
  local runs = {}
  for i = 1, 130 do
    local gaps = {}
    for _ = 1, rnd(3) - 1 do
      gaps[#gaps + 1] = { title = titles[rnd(#titles)], status = rnd(2) == 1 and "missing" or "thin", severity = "high" }
    end
    runs[i] = { key = DD74.order[rnd(3)], level = 10, result = results[rnd(#results)], started = 1000 + i,
      comp = {}, gaps = gaps, affixes = {} }
  end
  ns74.db.history = runs
  local H74 = ns74.History
  -- The one-pass count gives the same lessons as the old scan of every run for every run.
  local function OldRepeats(run, all, lead)
    local n = 0
    for _, other in ipairs(all) do
      if other ~= run and other.key == run.key and other.result == "overtime" then
        for _, g in ipairs(other.gaps or {}) do
          if g.title == lead.title and g.status == lead.status then n = n + 1; break end
        end
      end
    end
    return n
  end
  local idx, same, checked = H74:RepeatIndex(runs), true, 0
  for _, run in ipairs(runs) do
    local a = H74:Lesson(run, runs, idx)
    local b = H74:Lesson(run, runs)
    if a ~= b then same = false end
    if run.result == "overtime" and #run.gaps > 0 and a then
      local want = OldRepeats(run, runs, (function()
        local gs = {}
        for _, g in ipairs(run.gaps) do gs[#gs + 1] = g end
        table.sort(gs, function(x, y)
          if (x.status == "missing") ~= (y.status == "missing") then return x.status == "missing" end
          return tostring(x.title) < tostring(y.title)
        end)
        return gs[1]
      end)())
      local got = tonumber(a:match("in (%d+) other over%-time key")) or 0
      if got ~= want then same = false end
      checked = checked + 1
    end
  end
  ok(same and checked > 10, "C2: lessons from the one-pass count match the old scan (" .. checked .. " over-time runs)")
  UI74:Show("history"); RunTimers()
  local function texts()
    local out = {}
    for i = 1, UI74.hp.runs.used do out[#out + 1] = tostring(UI74.hp.runs.pool[i]:GetText()) end
    return out
  end
  local function moreLine()
    for _, t in ipairs(texts()) do if t:find("Show %d+ more") then return t end end
  end
  local function shownRuns()
    local n = 0
    for _, t in ipairs(texts()) do if t:find("^|c%x+Gaps: ") or t:find("No gaps%.") then n = n + 1 end end
    return n
  end
  ok(shownRuns() == 50 and moreLine() and moreLine():find("Show 50 more", 1, true) and moreLine():find("80 older", 1, true),
    "C2: the newest 50 runs, then \"Show 50 more\" (80 older)")
  local L = UI74.hp.runs
  local btn
  for i = 1, L.bused do if L.bpool[i]:IsShown() then btn = L.bpool[i] end end
  btn:Click(); RunTimers()
  ok(shownRuns() == 100 and moreLine() and moreLine():find("Show 30 more", 1, true), "C2: one click shows 50 more")
  for i = 1, L.bused do if L.bpool[i]:IsShown() then btn = L.bpool[i] end end
  btn:Click(); RunTimers()
  ok(shownRuns() == 130 and not moreLine(), "C2: every stored run reachable; no more line at the end")
  UI74.hp.filter = DD74.order[1]; UI74.hp.shown = UI74.HISTORY_PAGE; UI74:Refresh()
  local n1 = 0
  for _, r in ipairs(runs) do if r.key == DD74.order[1] then n1 = n1 + 1 end end
  ok(shownRuns() == math.min(50, n1), "C2: a dungeon filter starts again at 50")
  UI74.hp.filter = nil
  ns74.db.history = {}
  UI74:Hide()

  -- C3: the boss window rebuilds once per frame however many events arrive.
  local BW = ns74.BossWindow
  BW:Open(DD74.order[1]); RunTimers()
  local bwCount = 0
  local origBW = BW.Refresh
  BW.Refresh = function(self, ...) bwCount = bwCount + 1; return origBW(self, ...) end
  for _, ev in ipairs({ "LIVE_ROSTER_CHANGED", "ASSIGNMENTS_CHANGED", "LUST_CHANGED", "SETTINGS_CHANGED",
    "BOSS_ORDER_CHANGED", "BOSS_CARD_CHANGED", "BOSS_NOTES_CHANGED" }) do ns74:Fire(ev) end
  ok(bwCount == 0, "C3: nothing redraws inside the burst")
  RunTimers()
  ok(bwCount == 1, "C3: seven events, one redraw next frame (got " .. bwCount .. ")")
  BW:Hide(true); bwCount = 0
  ns74:Fire("ASSIGNMENTS_CHANGED"); RunTimers()
  ok(bwCount == 0, "C3: a hidden boss window doesn't redraw")
  BW.Refresh = origBW
end

-- 75. Boss splits in History (1.5.0, F1): kill times from the key's boss objectives (scenario
-- criteria), ENCOUNTER_END as the second path, deaths per stretch, hidden values left out, a
-- /reload mid-key, the comparison with your best timed run, the lesson and verify.
do
  EnsembleDB = nil
  CURRENT_AFFIXES = {}
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  INSPECT_CACHE = {}
  local SECRET = {}
  local function mark(v) local t = { v = v }; SECRET[t] = true; return t end
  local ELAPSED = 0
  CRITERIA = {}
  C_Scenario = { GetStepInfo = function() return "Temple", "", #CRITERIA end }
  C_ScenarioInfo = { GetCriteriaInfo = function(i) return CRITERIA[i] end }
  GetWorldElapsedTime = function() return 1, ELAPSED, true end
  local function crit(enc, name, done) return { criteriaType = 165, assetID = enc, description = name, completed = done } end
  local function setCrit(done)
    CRITERIA = {
      crit(2124, "Adderis and Aspix", done >= 1), crit(2125, "Merektha", done >= 2),
      crit(2126, "Galvazzt", done >= 3), crit(2127, "Avatar of Sethraliss", done >= 4),
      { criteriaType = 0, assetID = 0, description = "Enemy Forces", completed = false },
    }
  end
  local nsS = boot()
  local Hs = nsS.History
  local hf
  for _, fr in ipairs(ALLFRAMES) do if fr._events.CHALLENGE_MODE_COMPLETED then hf = fr end end
  ok(hf._events.SCENARIO_CRITERIA_UPDATE and hf._events.ENCOUNTER_END, "F1: history listens for objectives and boss kills")
  local function fire(ev, ...) hf._scripts.OnEvent(hf, ev, ...); RunTimers() end
  local function kill(n, t, deaths)
    ELAPSED, DEATHS = t, deaths
    setCrit(n); fire("SCENARIO_CRITERIA_UPDATE")
  end
  local function runKey(level, times, deaths, finish, timed)
    ACTIVE_CHALLENGE, ACTIVE_KEY_LEVEL, ACTIVE_KEY_AFFIXES = 250, level, {}
    DEATHS, ELAPSED = 0, 0
    setCrit(0); fire("CHALLENGE_MODE_START")
    for i, t in ipairs(times) do kill(i, t, deaths[i]) end
    ELAPSED = finish
    COMPLETION = { mapChallengeModeID = 250, level = level, time = finish * 1000, onTime = timed, keystoneUpgradeLevels = timed and 1 or 0 }
    fire("CHALLENGE_MODE_COMPLETED")
    ACTIVE_CHALLENGE = nil
    return nsS.db.history[1]
  end
  -- A timed run: four kills in order with their times and the deaths so far.
  local best = runKey(12, { 300, 700, 1100, 1500 }, { 0, 1, 1, 2 }, 1700, true)
  ok(best.splits and #best.splits == 4, "F1: four boss splits recorded")
  ok(best.splits[1].enc == 2124 and best.splits[1].boss == 1 and best.splits[1].t == 300 and best.splits[1].via == "criteria",
    "F1: a split holds the encounter, our boss, the time and its source")
  ok(best.splits[2].deaths == 1 and best.splits[4].deaths == 2, "F1: the death count at each kill")
  -- The same kill's ENCOUNTER_END after the objective adds nothing.
  ACTIVE_CHALLENGE = 250; setCrit(0); fire("CHALLENGE_MODE_START")
  kill(1, 280, 0)
  ELAPSED = 290; fire("ENCOUNTER_END", 2124, "Adderis and Aspix", 8, 5, 1)
  ok(#nsS.db.activeRun.splits == 1 and nsS.db.activeRun.splits[1].t == 280, "F1: one split per boss, the objective's first")
  -- ENCOUNTER_END alone (no objectives) still records; a wipe doesn't.
  local saved = C_ScenarioInfo
  C_ScenarioInfo = nil
  ELAPSED, DEATHS = 640, 1
  fire("ENCOUNTER_END", 2125, "Merektha", 8, 5, 0)
  ok(#nsS.db.activeRun.splits == 1, "F1: a wipe isn't a split")
  fire("ENCOUNTER_END", 2125, "Merektha", 8, 5, 1)
  local sp2 = nsS.db.activeRun.splits[2]
  ok(sp2 and sp2.enc == 2125 and sp2.boss == 2 and sp2.via == "encounter" and sp2.t == 640, "F1: ENCOUNTER_END is the second path")
  C_ScenarioInfo = saved
  -- Hidden values: a hidden timer leaves the time out, a hidden encounter ID records nothing, no error.
  issecretvalue = function(v) return SECRET[v] == true end
  local realElapsed = GetWorldElapsedTime
  GetWorldElapsedTime = function() return 1, mark(900), true end
  DEATHS = 1
  setCrit(3); CRITERIA[3].completed = true; fire("SCENARIO_CRITERIA_UPDATE")
  local sp3 = nsS.db.activeRun.splits[3]
  ok(sp3 and sp3.enc == 2126 and sp3.t == nil, "F1: a hidden timer leaves the time out")
  GetWorldElapsedTime = realElapsed
  CRITERIA[4] = { criteriaType = 165, assetID = mark(2127), description = mark("x"), completed = true }
  local okHidden = pcall(fire, "SCENARIO_CRITERIA_UPDATE")
  ok(okHidden and #nsS.db.activeRun.splits == 3, "F1: a hidden encounter ID records nothing and doesn't error")
  local okEnc = pcall(fire, "ENCOUNTER_END", mark(2127), mark("x"), 8, 5, mark(1))
  ok(okEnc and #nsS.db.activeRun.splits == 3, "F1: hidden ENCOUNTER_END arguments are ignored")
  issecretvalue = nil
  -- A /reload mid-key: bosses already down are recorded once, marked as seen late.
  ELAPSED = 1300; setCrit(4)
  fire("PLAYER_ENTERING_WORLD")
  local sp4
  for _, sp in ipairs(nsS.db.activeRun.splits) do if sp.enc == 2127 then sp4 = sp end end
  ok(nsS.db.activeRun.splits[4] == sp3, "F1: a split without a time sorts last")
  ok(sp4 and sp4.enc == 2127 and sp4.approx and sp4.t == 1300, "F1: after a reload, a boss already down is marked approximate")
  fire("PLAYER_ENTERING_WORLD")
  ok(#nsS.db.activeRun.splits == 4, "F1: a second reload adds nothing")
  COMPLETION = { mapChallengeModeID = 250, level = 12, time = 1750000, onTime = false }
  ELAPSED = 1750; fire("CHALLENGE_MODE_COMPLETED"); ACTIVE_CHALLENGE = nil
  -- Splits survive the run and an abandoned key with no kills stores none.
  ACTIVE_CHALLENGE = 250; setCrit(0); fire("CHALLENGE_MODE_START"); ACTIVE_CHALLENGE = nil; fire("PLAYER_ENTERING_WORLD")
  ok(nsS.db.history[1].result == "abandoned" and nsS.db.history[1].splits == nil, "F1: no kills, no splits")

  -- Comparison with your best timed run; over-time lesson names the stretch that lost the most.
  local slow = runKey(13, { 330, 760, 1400, 1820 }, { 0, 1, 5, 6 }, 2050, false)
  local rows = Hs:SplitRows(slow, Hs:BestTimed("TempleOfSethraliss", slow))
  ok(rows[1].delta == 30 and rows[1].segLoss == 30, "F1: first boss +0:30 against the best")
  ok(rows[3].delta == 300 and rows[3].segLoss == 240 and rows[3].deaths == 4, "F1: Galvazzt's stretch lost 4:00, with 4 deaths there")
  ok(rows[5] and rows[5].final and rows[5].delta == 350 and rows[5].segLoss == 30, "F1: the stretch after the last boss")
  ok(Hs:BestTimed("TempleOfSethraliss", best) == nil, "F1: the best run isn't compared with itself (no other timed run)")
  slow.gaps = {}   -- a full group: no utility gaps, so the lesson looks at the time
  local text = Hs:Lesson(slow, nsS.db.history)
  ok(text:find("the most time went between Merektha and Galvazzt (+4:00 vs your best timed +12, 4 deaths there)", 1, true),
    "F1: lesson: " .. text)
  slow.splits = nil
  ok(Hs:Lesson(slow, nsS.db.history):find("the time went elsewhere", 1, true), "F1: no splits: the old lesson")
  -- History shows the splits line with the differences.
  local UIs = nsS.UI
  UIs:Show("history"); RunTimers()
  local found
  for i = 1, UIs.hp.runs.used do
    local t = tostring(UIs.hp.runs.pool[i]:GetText())
    if t:find("Bosses:", 1, true) and t:find("Adderis and Aspix 5:00", 1, true) then found = t end
  end
  ok(found ~= nil, "F1: History lists each boss with its kill time")
  UIs:Hide()
  -- Verify: outside a key it says where to run it; inside it reads the objectives.
  local vt = nsS.Verify:Build()
  ok(vt:find("C_ScenarioInfo.GetCriteriaInfo present", 1, true) and vt:find("GetWorldElapsedTime present", 1, true)
    and vt:find("run /ens verify inside a key", 1, true), "F1: verify outside a key")
  ACTIVE_CHALLENGE = 250; ELAPSED = 600; DEATHS = 2; setCrit(2)
  vt = nsS.Verify:Build()
  ok(vt:find("boss objectives: 5 criteria read, 4 bosses found, 2 down", 1, true) and vt:find("key timer: 10:00 elapsed", 1, true)
    and vt:find("death count: 2", 1, true), "F1: verify inside a key")
  C_ScenarioInfo = nil
  vt = nsS.Verify:Build()
  ok(vt:find("C_ScenarioInfo.GetCriteriaInfo missing", 1, true), "F1: verify without the objectives API")
  ACTIVE_CHALLENGE, C_Scenario, GetWorldElapsedTime, CRITERIA, DEATHS = nil, nil, nil, nil, 0
end

print(string.format("%d passed, %d failed", passes, fails))
return fails
