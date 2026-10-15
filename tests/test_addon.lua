-- Headless scenario tests. Run with LuaJIT via lupa. ADDON_DIR is set by the runner.
-- Load order comes straight from the TOC, so a file added there is always tested.
local FILES = {}
for line in io.lines(ADDON_DIR .. "/KeystoneCommand.toc") do
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
      chunk("KeystoneCommand", ns)
    end
  end
  -- fire ADDON_LOADED / PLAYER_LOGIN on the boot frame
  for _, fr in ipairs(ALLFRAMES) do
    if fr._events.ADDON_LOADED then
      fr._scripts.OnEvent(fr, "ADDON_LOADED", "KeystoneCommand")
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

KeystoneCommandDB = nil
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
KeystoneCommandDB = { savedComps = { { name = "Alpha", slots = { 73 } }, "junk" }, currentComp = "x" }
local ns3 = boot()
ok(ns3.db.schema == 4, "schema set")
ok(#ns3.db.savedComps == 1 and ns3.db.savedComps[1].name == "Alpha", "junk comp dropped")
ok(ns3.db.savedComps[1].slots[5] == 0, "short slots padded")
ok(type(ns3.db.currentComp) == "table" and ns3.db.currentComp[1] == 0, "bad currentComp reset")

-- 16. Slash commands
SlashCmdList.KEYSTONECOMMAND("dungeon temple of sethraliss")
ok(ns3.db.selectedDungeon == "TempleOfSethraliss", "slash dungeon")
SlashCmdList.KEYSTONECOMMAND("reset")
ok(ns3.db.selectedDungeon == "TempleOfSethraliss", "reset needs confirm")
SlashCmdList.KEYSTONECOMMAND("reset confirm")
ok(ns3.db.selectedDungeon == "AUTO", "reset confirm works")


-- 17. Applicant fit (new feature)
do
  KeystoneCommandDB = nil
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
  SlashCmdList.KEYSTONECOMMAND("panel below"); UIF:RefreshFinderPanel()
  ok(nsF.db.settings.finderPanel.side == "below" and UIF.fp._point[3] == "BOTTOMLEFT", "/kc panel below")
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
  SlashCmdList.KEYSTONECOMMAND("panel dock")
  ok(fpPos.docked and UIF.fp._point[2] == PVEFrame, "/kc panel dock re-attaches")
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
  ok(mf:find("|Haddon:KeystoneCommand:a:47528:interrupt:Mind Freeze|h", 1, true) and mf:find("|T" .. (1000000 + 47528), 1, true),
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
  ok(lbl[1]:find("|Haddon:KeystoneCommand:a:", 1, true), "provider labels are links")
  local found = false
  for _, it in ipairs(r.dungeon.items) do
    for _, l in ipairs(nsL.Analysis.Labels(it.providers, it.req.need)) do if l:find("|Haddon:KeystoneCommand:a:", 1, true) then found = true end end
  end
  ok(found, "dungeon providers name their ability as a link")
  -- Tooltip handler
  local f = CreateFrame("Frame")
  Links:Enable(f)
  ok(f._scripts.OnHyperlinkEnter ~= nil, "hyperlink scripts installed")
  local lines, spellShown = {}, nil
  GameTooltip.SetSpellByID = function(_, id) spellShown = id end
  GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
  f._scripts.OnHyperlinkEnter(f, "addon:KeystoneCommand:e:270492:curse:Hex")
  ok(spellShown == 270492 and lines[1]:find("Curse debuff"), "tooltip shows the spell and its type")
  spellShown, lines = nil, {}
  GameTooltip.SetText = function(_, t) lines[#lines + 1] = "T:" .. t end
  f._scripts.OnHyperlinkEnter(f, "addon:KeystoneCommand:e:0:poison:Envenom")
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
  ok(UIA.titleText:GetText():find("|cffa78bfa", 1, true), "title recolored live")
  ok(UIA.tabButtons.settings.line._color[1] > 0.6 and UIA.tabButtons.settings.line._color[3] > 0.95, "registered accent recolored")
  ok(not UIA.SetThemeHex("12345"), "invalid hex rejected")
  RAID_CLASS_COLORS = setmetatable({ WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }, { __index = function() return { r = 1, g = 1, b = 1 } end })
  nsA.db.settings.theme.classColor = true; UIA:ApplyTheme(); RunTimers()
  ok(UIA.titleText:GetText():find("|cffc79c6e", 1, true), "class color applied")
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
  ok(UIA.logo and UIA.LOGO == "Interface\\AddOns\\KeystoneCommand\\Media\\LogoMark", "window header shows the addon logo")
  ok(UIA.sloganText and UIA.sloganText:GetText() == "Command the key." and UIA.sloganText._fontSize == 10, "slogan under the name at a fixed size")
  ok(UIA.headerFit and UIA.headerFit.sloganShown and UIA.sloganText:IsShown(), "slogan fits beside the tabs at the narrowest window")
  ok(nsA.db.settings.textSize == 120 and UIA.cp.sumTitle._fontSize == 16 and before == 13 and UIA.titleText._fontSize == 15, "text size applies to existing text (tab row stays fixed)")
  ok(UIA.frame._w == 1400, "text size leaves the window size alone")
  UIA:SetTextSize(200); ok(nsA.db.settings.textSize == 125, "text size clamped high")
  UIA:SetTextSize(10); ok(nsA.db.settings.textSize == 80, "text size clamped low")
  SlashCmdList.KEYSTONECOMMAND("text 110"); ok(nsA.db.settings.textSize == 110, "/kc text")
  UIA.grip._scripts.OnMouseDown(UIA.grip); ok(UIA.frame._sizing, "grip resizes")
  UIA.grip._scripts.OnMouseUp(UIA.grip)
  SlashCmdList.KEYSTONECOMMAND("lock"); RunTimers()
  ok(nsA.db.settings.window.locked and UIA.lockBtn.text:GetText() == "Locked" and not UIA.grip:IsShown(), "locked: grip hidden")
  SlashCmdList.KEYSTONECOMMAND("unlock"); RunTimers()
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

-- 23. /kc verify
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
  SlashCmdList.KEYSTONECOMMAND("verify")
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
  for _, row in ipairs(ready.risks) do if at:find(UIn.RiskText(row), ap, true) then listed = listed + 1 end end
  ok(listed == #ready.risks, "every problem listed after Expand all")
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
  KeystoneCommandDB = {}
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
  ok(UId.cp.dungeonNote:GetText():find("Auto would be Kings' Rest", 1, true), "note points at the auto choice")
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
  SlashCmdList.KEYSTONECOMMAND("dungeon none"); ok(nsD.db.selectedDungeon == "NONE", "/kc dungeon none")
  SlashCmdList.KEYSTONECOMMAND("dungeon auto"); ok(nsD.db.selectedDungeon == "AUTO", "/kc dungeon auto")
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
  ok(UId.cp.dungeonNote:GetText():find("the dungeon you're in", 1, true), "zone note")
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
  KeystoneCommandDB = nil
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
  ok(t:find("ASSIGNMENTS: TEMPLE OF SETHRALISS", 1, true), "assignments header")
  ok(t:find("KICK", 1, true) and t:find("Lightning Bolt", 1, true) and t:find("Flame Shock", 1, true), "must-kicks listed")
  ok(t:find("DISPEL", 1, true) and t:find("Imbued Conduction", 1, true) and t:find("Magic:", 1, true), "must-dispels listed with type")
  ok(t:find("STOP", 1, true) and t:find("Arrow Barrage", 1, true), "must-stops listed")
  ok(t:find("Hhaddon:KeystoneCommand", 1, true) == nil and t:find("|Haddon:KeystoneCommand", 1, true), "abilities are links with tooltips")
  local rows = UIc:CheatSheetRows("TempleOfSethraliss")
  for _, row in ipairs(rows) do
    local top = false
    for _, req in ipairs(row.reqs) do if req.severity == "critical" or req.severity == "high" then top = true end end
    for _, req in ipairs(row.reqs) do
      ok(not top or req.severity == "critical" or req.severity == "high", "only critical/high when the category has them: " .. req.id)
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
  ok(msg:find("^%[Keystone Command%] Temple of Sethraliss") and msg:find("Missing: ", 1, true) and msg:find("Bloodlust", 1, true)
    and msg:find("Poison dispel (Cytotoxin)", 1, true) and not msg:find("|", 1, true) and #msg <= 255, "gap message: " .. msg)
  local postBtn
  for i = 1, plan.bused do if plan.bpool[i].tip and plan.bpool[i].tip:find("Keystone Command]", 1, true) then postBtn = plan.bpool[i] end end
  ok(postBtn ~= nil, "post gaps row present")
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  local postBtn
  for i = 1, side.bused do if side.bpool[i].tip and side.bpool[i].tip:find(" assignments", 1, true) then postBtn = side.bpool[i] end end
  ok(postBtn ~= nil, "post plan row")
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" }, party1 = { guid = "H", name = "Hal", class = "PRIEST", role = "HEALER" } }
  SENT = {}
  postBtn:Click(); RunTimers(); RunTimers(); RunTimers(); RunTimers(); RunTimers(); RunTimers()
  ok(#SENT >= 3 and SENT[1].channel == "PARTY" and SENT[1].msg:find(" assignments", 1, true), "plan posted to party, one line per player (" .. #SENT .. ")")
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }
  nsK.UI:Hide()
end

-- 32. Applicant comparison, sort and filter
do
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  SlashCmdList.KEYSTONECOMMAND("history"); RunTimers()
  ok(nsH.UI.currentTab == "history", "/kc history opens the tab")
  nsH.UI:Hide()
end

-- 34. Review fixes
do
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
  local nsZ = boot()
  ok(nsZ.Affixes.Match(165, "Lindormis Fuehrung").key == "LINDORMI", "Lindormi matched by ID 165")
  ok(nsZ.Dungeons:KeyForInstanceMap(2813) == "MurderRow" and nsZ.Dungeons:KeyForInstanceMap(2993) == "AltarOfFangs",
    "confirmed instance IDs known without map data")
end

-- 36. Class suggestions for empty slots only
do
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  SlashCmdList.KEYSTONECOMMAND("glossary"); RunTimers()
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
  ok(dump(UIl.pl.list):find("ASSIGNMENTS", 1, true), "full assignments beside them")
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
  UIl.primerKey = "TempleOfSethraliss"; UIl:Refresh(); RunTimers()
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
  SlashCmdList.KEYSTONECOMMAND("dungeons"); ok(UIl.currentTab == "dungeons", "/kc dungeons")
  UIl:Hide()
end

-- 41. Score breakdown, wait times, Group Finder tooltips
do
  KeystoneCommandDB = nil
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
  ok(tl:find("Keystone Command: ", 1, true) and tl:find("/100", 1, true) and not tl:find("|H", 1, true), "fit added to the Blizzard tooltip")
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  SlashCmdList.KEYSTONECOMMAND("bestkey")
  ok(nsF.UI.bestKey:IsShown(), "/kc bestkey opens it")

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
  ok(full:find("Cytotoxin", 1, true) and short:find("^%[KC%]") and not short:find("Cytotoxin", 1, true), "short gaps post drops the casts")
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
  ok(mrl:find("Nobody can remove", 1, true) and mrl:find("Bleed", 1, true) and not mrl:find("Guardian Spirit", 1, true), "no-dispel needs become a group line")
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
  KeystoneCommandDB = {}
  local registered = {}
  Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) registered.name = name; return { name = name } end,
    RegisterAddOnCategory = function(cat) registered.cat = cat end,
  }
  local nsM = boot()
  ok(registered.name == "Keystone Command" and registered.cat ~= nil and nsM.UI.blizzCategory ~= nil, "entry in Blizzard's Options > AddOns")
  Settings = nil
end

-- 46. /kc report and the error log
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
  nextStack = "Interface/AddOns/KeystoneCommand/UI.lua:120: in function 'Refresh'\n[C]: ?"
  handler("Interface/AddOns/KeystoneCommand/UI.lua:120: attempt to index nil")
  nextStack = "Interface/AddOns/OtherAddon/x.lua:5: in function 'Foo'"
  handler("Interface/AddOns/OtherAddon/x.lua:5: not ours")
  nextStack = "Interface/AddOns/KeystoneCommand/UI.lua:120: in function 'Refresh'\n[C]: ?"
  handler("Interface/AddOns/KeystoneCommand/UI.lua:120: attempt to index nil")
  ok(prevCalls == 3, "every error still reaches the previous handler")
  local errs = nsP.db.errors
  ok(#errs == 1 and errs[1].count == 2 and errs[1].version, "only this addon's errors are logged, repeats counted")
  nsP.db.settings.chatStyle = "short"; nsP.db.settings.ignoredNeeds = { soothe = true }
  nsP.db.settings.window.x = 55
  nsP.db.currentComp = { 73, 257, 0, 0, 0 }
  local changed = table.concat(R:ChangedSettings(), " ")
  ok(changed:find("chatStyle=short", 1, true) and changed:find("ignoredNeeds={soothe}", 1, true) and not changed:find("window.x", 1, true),
    "changed settings listed, window position left out: " .. changed)
  BugGrabber = { GetDB = function() return { { message = "Interface/AddOns/KeystoneCommand/Report.lua:9: from bug grabber", counter = 3 },
    { message = "Interface/AddOns/Else/a.lua:1: other" } } end }
  local text = R:Build()
  BugGrabber = nil
  ok(text:find("=== Keystone Command bug report ===", 1, true) and text:find("What happened:", 1, true), "report starts with the questions")
  ok(text:find("Addon ", 1, true) and text:find("Planner slots: Protection Warrior, Holy Priest, empty", 1, true), "version line and Planner slots")
  ok(text:find("attempt to index nil", 1, true) and text:find("[x2", 1, true) and text:find("UI.lua:120", 1, true), "logged error with count and stack line")
  ok(text:find("from bug grabber", 1, true) ~= nil and not text:find("Else/a.lua", 1, true), "only this addon's BugGrabber errors")
  ok(text:find("Verify: ", 1, true) and text:find("=== end of report ===", 1, true), "verify summary included")
  ok(not text:find("Secretname", 1, true), "no player names in the report")
  ok(text:find("Settings changed from defaults: ", 1, true) and text:find("chatStyle=short", 1, true), "settings in the report")
  SlashCmdList.KEYSTONECOMMAND("report")
  ok(nsP.Verify.frame and nsP.Verify.frame:IsShown() and nsP.Verify.frame.report:find("bug report", 1, true), "/kc report opens the copy window")
  ok(nsP.db.lastReport ~= nil, "last report kept in SavedVariables")
  R:ClearErrors()
  ok(R:Build():find("none recorded", 1, true), "empty log reads 'none recorded'")
  -- A client that refuses the handler change: nothing breaks
  seterrorhandler = function() error("blocked") end
  handler = nil
  local nsQ = boot()
  ok(nsQ.Report.captureActive == false and nsQ.Report:Build():find("capture not active", 1, true), "refused handler: report still works")
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
  ok(cl[1]:find("^%[KC%] Rav'i %- ALL: ") and cl[2]:find("^TANK: ") and cl[3]:find("^HEAL: ") and cl[4]:find("^DPS: "), "one chat line per role, ALL first")
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
  ok(#SENT >= 3 and SENT[1].msg:find("^%[KC%] Zul'jan %- ALL:") and SENT[1].channel == "PARTY", "post sends the card to party chat")
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
  SlashCmdList.KEYSTONECOMMAND("boss ruby life pools")
  ok(BW:IsShown() and BW.title:GetText():find("Melidrussa", 1, true), "/kc boss <dungeon> opens that dungeon's cards")
  nsB.UI:OpenBossEditor("RubyLifePools", 1)
  local ed = nsB.UI.bossEditor
  ok(ed and ed:IsShown() and ed.edit:GetText():find("^ALL: "), "editor opens with the card's text")
  ed.edit:SetText("TANK: my note"); ed.save:Click()
  ok(BC:IsEdited("RubyLifePools", 1) and BW.title:GetText():find("(edited)", 1, true), "editor saves; the window marks it edited")
  BC:Reset("RubyLifePools", 1)
  -- Dungeons tab
  nsB.UI:Show("dungeons"); nsB.UI.primerKey = "TempleOfSethraliss"; nsB.UI:RefreshPrimer(); RunTimers()
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
  KeystoneCommandDB = nil
  local nsR = boot()
  ok(SLASH_KEYSTONECOMMAND1 == "/kc" and SLASH_KEYSTONECOMMAND2 == "/keystonecommand" and SLASH_KEYSTONECOMMAND3 == nil, "/kc and /keystonecommand only")
  ok(nsR.Share.Encode("New", { 73, 257, 0, 0, 0 }, "KingsRest"):find("^KC1:"), "share strings are KC1")
  ok(nsR.Share.Decode("XX1:a:NONE:0,0,0,0,0:1") == nil, "other prefixes rejected")
end

-- 49. Ability links on boss cards (encounter journal)
do
  EJ_GetInstanceForMap = function(map) return map == 2993 and 1300 or 0 end
  EJ_GetEncounterInfoByIndex = function(n, jid)
    if jid ~= 1300 then return nil end
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
  C_EncounterJournal = { GetSectionInfo = function(id) return SECTIONS[id] end }
  KeystoneCommandDB = nil
  local nsL2 = boot()
  local BC2 = nsL2.BossCards
  local js = BC2:JournalSpells("AltarOfFangs")
  ok(js.Hydrastrike and js.Hydrastrike.id == 1111 and js["Death Rattle"] and not js.Overview, "boss abilities read from the journal (sections without a spell skipped)")
  local line = BC2:Decorate("AltarOfFangs", "Defensive for Hydrastrike.")
  ok(line:find("|Haddon:KeystoneCommand:e:1111:boss:Hydrastrike|h", 1, true), "journal abilities become links: " .. line)
  local both = BC2:Decorate("AltarOfFangs", "Kick all three Toxic Atrophy casts in a row.")
  ok(both:find(":interrupt:Toxic Atrophy|h", 1, true), "dungeon-data abilities keep their own type")
  ok(not BC2:Decorate("AltarOfFangs", "Dispel it (Hydrastrike)."):find("|H", 1, true), "text in brackets is never linked")
  local bw = nsL2.BossWindow
  nsL2.db.settings.bossWindow.showAll = true
  bw.view = { dk = "AltarOfFangs", index = 1 }; bw:Show()
  local any = false
  for _, it in ipairs(bw.items) do if it.text:find("|Haddon:KeystoneCommand:e:1111:boss:", 1, true) then any = true end end
  ok(any and bw.content.cmLinks, "boss window shows ability links and handles their tooltips")
  ok(table.concat(nsL2.BossCards:ChatLines("AltarOfFangs", 1), "\n"):find("|H", 1, true) == nil, "chat posts stay plain text")
  -- /kc verify season: dungeon pool, journal bosses with ability IDs, affixes
  local stubInstance = DUNGEON_MAPS[588][3]
  DUNGEON_MAPS[588][3] = 2993            -- the live client's instance map for Altar of Fangs
  local season = nsL2.Verify:BuildSeason()
  DUNGEON_MAPS[588][3] = stubInstance
  ok(season:find("588 | Altar of Fangs | instance 2993", 1, true) and season:find("addon: AltarOfFangs", 1, true), "season dump lists dungeons with IDs")
  ok(season:find("boss 1: Rav'i", 1, true) and season:find("Hydrastrike=1111", 1, true), "season dump lists journal bosses and ability IDs")
  ok(season:find("== This week's affixes ==", 1, true), "season dump has the affix section")
  SlashCmdList.KEYSTONECOMMAND("verify season")
  ok(nsL2.db.lastSeason and nsL2.db.lastSeason:find("season data", 1, true), "/kc verify season opens the copy window")
  EJ_GetInstanceForMap, EJ_GetEncounterInfoByIndex, C_EncounterJournal = nil, nil, nil
end

-- 50. Full review (October 2026): resource and data fixes
do
  KeystoneCommandDB = nil
  local nsF = boot()
  -- Journal not ready: not cached as empty, so links appear once it loads.
  local BCF = nsF.BossCards
  ok(next(BCF:JournalSpells("AltarOfFangs")) == nil, "no journal: no ability links yet")
  EJ_GetInstanceForMap = function(map) return map == 2993 and 1300 or 0 end
  EJ_GetEncounterInfoByIndex = function(n, jid) if jid == 1300 and n == 1 then return "Rav'i", "", 9001, 10 end end
  C_EncounterJournal = { GetSectionInfo = function(id) if id == 10 then return { title = "Hydrastrike", spellID = 1111 } end end }
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
  KeystoneCommandDB = nil
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
  SlashCmdList.KEYSTONECOMMAND("tour")
  ok(Tour:IsActive() and Tour.step == 1, "/kc tour replays it")
  Tour.frame.skip._scripts.OnClick(Tour.frame.skip)
  ok(not Tour:IsActive(), "Skip ends it")
  C_LFGList.GetApplicantDungeonScoreForListing = nil
  LISTING = nil
end

-- 52. Pull-by-pull jobs from a Mythic Dungeon Tools route
do
  KeystoneCommandDB = nil
  MDTDB = {
    presets = { [77] = { { text = "My route", uid = "a", value = { pulls = {
      { [1] = { 1, 2 }, [2] = { 1 }, color = "ff0000" },   -- 2 Risen Hexers + a Phantom Hex Priest
      { [4] = { 1 } },                                     -- Queen Wasi (matched by name)
      { [3] = { 1 } },                                     -- The Golden Serpent (boss)
      { [5] = { 1, 2, 3 } },                               -- nothing that needs a job
    } } } } },
    currentPreset = { [77] = 1 },
  }
  MDT = {
    GetDB = function() return MDTDB end,
    mapInfo = { [77] = { mapID = 249, englishName = "Kings' Rest" } },
    dungeonTotalCount = { [77] = { normal = 100 } },
    dungeonEnemies = { [77] = {
      [1] = { name = "Risen Hexer", count = 4, spells = { [269972] = {} } },
      [2] = { name = "Phantom Hex Priest", count = 5, spells = { [270492] = {} } },
      [3] = { name = "The Golden Serpent", count = 0, isBoss = true, spells = {} },
      [4] = { name = "Queen Wasi", count = 6, spells = {} },
      [5] = { name = "Spectral Berserker", count = 2, spells = {} },
    } },
  }
  local nsR = boot()
  local R = nsR.Route
  ok(R:DungeonIndex("KingsRest") == 77, "MDT dungeon matched by map ID")
  local route = R:For("KingsRest")
  ok(route and #route.pulls == 4 and route.name == "My route", "route read from MDT's current preset")
  local ids = {}
  for _, q in ipairs(route.pulls[1].reqs) do ids[q.id] = true end
  ok(ids.KR_HEX_VOLLEY and ids.KR_HEX, "pull 1: Hex Volley and Hex matched by spell ID")
  local ids2 = {}
  for _, q in ipairs(route.pulls[2].reqs) do ids2[q.id] = true end
  ok(ids2.KR_BIND_SOUL, "pull 2: Queen Wasi's Bind Soul matched by name")
  ok(route.pulls[3].boss == 1 and #route.pulls[3].reqs > 0, "boss pull: the boss card's requirements")
  ok(route.pulls[1].forces == 13 and math.abs(route.pulls[2].frac - 0.19) < 1e-9, "running forces per pull")
  ok(R:PullLabel(route.pulls[1]) == "Risen Hexer x2, Phantom Hex Priest", "pull label")
  -- Jobs from the plan
  local members = { { specID = 73, isPlayer = true }, { specID = 256 }, { specID = 63 }, { specID = 71 }, { specID = 260 } }
  local r = nsR.Analysis:Analyze(members, "KingsRest", nsR.db.settings)
  local plan = nsR.Assignments:Build(r)
  local jobs = R:PullJobs(route.pulls[1], plan)
  local any, mine = false, false
  for _, j in ipairs(jobs) do if j.text:find("^Kick Hex Volley") then any = true end; if j.mine then mine = true end end
  ok(any, "pull 1 job: Kick Hex Volley")
  -- Plan column shows the route
  nsR.db.currentComp = { 73, 256, 63, 71, 260 }
  nsR:SetManualDungeon("KingsRest")
  local UIR = nsR.UI
  UIR:Show("builder"); RunTimers()
  UIR:Show("plan"); RunTimers()
  local t = {} for i = 1, UIR.pl.mine.used do t[#t + 1] = UIR.pl.mine.pool[i]:GetText() end
  local tx = table.concat(t, "\n")
  ok(tx:upper():find("YOUR ROUTE: MY ROUTE", 1, true) and tx:find("Pull 1:", 1, true) and tx:find("YOU|r", 1, true), "plan column lists the route's pulls with jobs")
  ok(not tx:find("Pull 4:", 1, true), "pulls without jobs are left out")
  -- A new route imported or shared: MDT makes it the current preset
  local changed = 0
  nsR:On("ROUTE_CHANGED", function() changed = changed + 1 end)
  MDTDB.presets[77][2] = { text = "Shared route", uid = "b", value = { pulls = { { [4] = { 1 } } } } }
  MDTDB.currentPreset[77] = 2
  R:CheckChanged()
  ok(changed == 1 and R:For("KingsRest").name == "Shared route", "an imported or shared route replaces the old one")
  MDTDB.currentPreset[77] = 1; R:CheckChanged()
  -- Following the run: enemy forces and boss kills
  local progress = 0
  C_ScenarioInfo = {
    GetStepInfo = function() return { numCriteria = 1 } end,
    GetCriteriaInfo = function() return { isWeightedProgress = true, quantity = progress, totalQuantity = 100 } end,
  }
  route = R:For("KingsRest")
  ok(R:CurrentPull(route) == 1, "start: pull 1")
  progress = 13
  ok(R:CurrentPull(route) == 2, "pull 1's forces done: pull 2")
  progress = 19
  ok(R:CurrentPull(route) == 3, "next is the boss pull")
  nsR.BossCards.state.killed = { [1] = true }
  ok(R:CurrentPull(route) == 4, "boss dead: on to pull 4")
  -- Boss window inside the dungeon shows the pull you're on
  nsR.BossCards.state = { dk = "KingsRest", index = 1, killed = {} }
  progress = 0
  nsR.BossWindow:Show()
  local first = nsR.BossWindow.items[1]
  ok(first and first.tag:find("PULL", 1, true) and first.text:find("Pull 1/4", 1, true), "boss window: the current pull first")
  -- Setting off, or no MDT: the plan is as before
  nsR.db.settings.routePlan = false; nsR:Fire("SETTINGS_CHANGED")
  ok(R:For("KingsRest") == nil, "setting off: no route")
  nsR.db.settings.routePlan = true; nsR:Fire("SETTINGS_CHANGED")
  MDT = nil
  ok(R:For("KingsRest") == nil and not R:Enabled(), "no MDT: no route")
  nsR.BossWindow:Hide()
  C_ScenarioInfo, MDTDB = nil, nil
end

-- 53. Dungeon walkthrough, role filter and the Bloodlust plan
do
  KeystoneCommandDB = { lust = { KingsRest = { { at = "zz" }, "bad", { at = "b1", note = 5 } }, Junk = 7 } }
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
  -- Route order (MDT)
  MDTDB = { presets = { [77] = { { text = "R1", uid = "a", value = { pulls = {
      { [1] = { 1, 2 }, [2] = { 1 } }, { [4] = { 1 } }, { [3] = { 1 } }, { [5] = { 1 } } } } } } },
    currentPreset = { [77] = 1 } }
  MDT = { GetDB = function() return MDTDB end, mapInfo = { [77] = { mapID = 249 } },
    dungeonTotalCount = { [77] = { normal = 100 } },
    dungeonEnemies = { [77] = {
      [1] = { name = "Risen Hexer", count = 4, spells = { [269972] = {} } },
      [2] = { name = "Phantom Hex Priest", count = 5, spells = { [270492] = {} } },
      [3] = { name = "The Golden Serpent", count = 0, isBoss = true, spells = {} },
      [4] = { name = "Queen Wasi", count = 6, spells = {} },
      [5] = { name = "Spectral Berserker", count = 2, spells = {} } } } }
  nsW.Route:Reset()
  w = WT:Build("KingsRest")
  ok(w.order == "route" and w.steps[1].kind == "trash" and WT:PullRange(w.steps[1]) == "Pulls 1-2", "route order: pulls 1-2 first")
  ids = {} for _, q in ipairs(w.steps[1].reqs) do ids[q.id] = true end
  ok(ids.KR_HEX_VOLLEY and ids.KR_HEX and ids.KR_BIND_SOUL, "route trash: what those pulls bring, Hex included")
  ok(w.steps[2].kind == "boss" and w.steps[2].boss == 1 and w.steps[2].pull == 3, "then the boss at its pull")
  local seenR, notIn = {}, false
  for _, st in ipairs(w.steps) do for _, q in ipairs(st.reqs) do seenR[q.id] = true; if q.id == "KR_UNHOLY_MENDING" and q.notInRoute then notIn = true end end end
  local all = true
  for _, q in ipairs(DDw.list.KingsRest.requirements) do if not seenR[q.id] then all = false end end
  ok(all and notIn, "route order keeps everything; unpulled trash marked, in its guide section")
  -- Bloodlust plan
  local uses, custom = WT:Lust("KingsRest")
  ok(#uses == 2 and not custom and uses[1].at == "b2", "default lust plan")
  ok(WT:LustChat("KingsRest"):find("^Lust: Mchimba the Embalmer") , "lust chat line: " .. WT:LustChat("KingsRest"))
  MDT = nil; nsW.Route:Reset()
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
  UIw:Show("dungeons"); UIw.primerKey = "KingsRest"; UIw:Refresh(); RunTimers()
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
  -- Boss window: lust on the boss, next pull line
  WT:SetLustAt("KingsRest", 1, "b1")
  local rows = nsW.BossWindow:Rows("KingsRest", 1, "TANK", false, false)
  local lustRow
  for _, r in ipairs(rows) do if r.kind == "lust" then lustRow = r end end
  ok(lustRow and lustRow.text:find("Bloodlust", 1, true), "boss window: lust row on its boss")
  MDT = { GetDB = function() return MDTDB end, mapInfo = { [77] = { mapID = 249 } },
    dungeonTotalCount = { [77] = { normal = 100 } },
    dungeonEnemies = { [77] = {
      [1] = { name = "Risen Hexer", count = 4, spells = { [269972] = {} } },
      [2] = { name = "Phantom Hex Priest", count = 5, spells = { [270492] = {} } },
      [3] = { name = "The Golden Serpent", count = 0, isBoss = true, spells = {} },
      [4] = { name = "Queen Wasi", count = 6, spells = {} },
      [5] = { name = "Spectral Berserker", count = 2, spells = {} } } } }
  nsW.Route:Reset()
  C_ScenarioInfo = { GetStepInfo = function() return { numCriteria = 1 } end,
    GetCriteriaInfo = function() return { isWeightedProgress = true, quantity = 0, totalQuantity = 100 } end }
  nsW.BossCards.state = { dk = "KingsRest", index = 1, killed = {} }
  rows = nsW.BossWindow:Rows("KingsRest", 1, "TANK", false, true)
  local nextRow
  for _, r in ipairs(rows) do if r.kind == "next" then nextRow = r end end
  ok(nextRow and nextRow.text:find("^Next: pull 2 %(") and nextRow.text:find("for you)", 1, true), "boss window: next pull line: " .. tostring(nextRow and nextRow.text))
  UIw:Hide()
  MDT, MDTDB, C_ScenarioInfo = nil, nil, nil
end

-- 54. Assignments chosen by hand
do
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
  ok(tipAll:find("Keystone Command: ", 1, true) and tipAll:find("Group after: ", 1, true), "Blizzard tooltip: Group after line")
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
  KeystoneCommandDB = nil
  local nsP = boot()
  local DDp = nsP.Dungeons
  ok(DDp.DATA_PATCH == "12.1.5" and DDp.DATA_CHECKED == "October 13, 2026"
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
  KeystoneCommandDB = nil
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
  KeystoneCommandDB = nil
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
-- /kc verify coverage, reset wording and session state
do
  KeystoneCommandDB = nil
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
      local head = "[KC] " .. BC:Boss(dk, i).name .. " - "
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

  -- Secret values: enemy forces.
  local SECRET = {}
  local function mark(v) local t = { v = v }; SECRET[t] = true; return t end
  issecretvalue = function(v) return SECRET[v] == true end
  local crit = { isWeightedProgress = true, quantity = 50, totalQuantity = 200, quantityString = "25%" }
  C_ScenarioInfo = { GetStepInfo = function() return { numCriteria = 1 } end, GetCriteriaInfo = function() return crit end }
  local R = nsV.Route
  ok(R:ForcesFraction() == 0.25, "forces: readable values")
  crit.totalQuantity = mark(200)
  ok(R:ForcesFraction() == nil and R.forcesSecret, "forces: a secret total means unknown")
  crit.totalQuantity, crit.quantity, crit.quantityString = nil, nil, mark("25%")
  ok(R:ForcesFraction() == nil and R.forcesSecret, "forces: a secret progress text means unknown")
  C_ScenarioInfo.GetStepInfo = function() return { numCriteria = mark(1) } end
  ok(R:ForcesFraction() == nil, "forces: a secret criteria count means unknown")
  C_ScenarioInfo.GetStepInfo = function() return { numCriteria = 1 } end
  C_ScenarioInfo.GetCriteriaInfo = function() return setmetatable({}, { __index = function() error("boom") end }) end
  ok(R:ForcesFraction() == nil and R.forcesError ~= nil, "forces: an error inside means unknown, never a Lua error")
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
  -- /kc verify reports both, and the guarded functions it didn't list before (item 10).
  T.secretReads = 3
  ACTIVE_CHALLENGE = 249
  MDT = { GetDB = function() return { global = {} } end, mapInfo = {} }
  crit = { isWeightedProgress = true, quantity = 1, totalQuantity = mark(100) }
  C_ScenarioInfo = { GetStepInfo = function() return { numCriteria = 1 } end, GetCriteriaInfo = function() return crit end }
  local realLead, realSB = UnitIsGroupLeader, C_SpellBook
  UnitIsGroupLeader, C_SpellBook = nil, nil
  local realIPS = IsPlayerSpell
  IsPlayerSpell = nil
  local text = nsV.Verify:Build()
  IsPlayerSpell, UnitIsGroupLeader, C_SpellBook = realIPS, realLead, realSB
  ok(text:find("party reads hidden by the game (secret values): 3", 1, true) and text:find("roster scans or inspects that errored: 1", 1, true),
    "verify: roster secret reads and contained errors reported")
  ok(text:find("enemy forces during this key: not readable (the game hides it from addons here: a secret value)", 1, true),
    "verify: enemy forces hidden by a secret value is reported")
  for _, name in ipairs({ "C_ChallengeMode.GetOverallDungeonScore", "C_ChatInfo.InChatMessagingLockdown", "UnitIsGroupAssistant",
                          "C_MythicPlus.RequestMapInfo" }) do
    ok(text:find(name .. " present", 1, true) or text:find(name .. " missing: ", 1, true), "verify reports " .. name)
  end
  ok(text:find("[WARN] UnitIsGroupLeader missing: the Invite buttons", 1, true)
    and text:find("[WARN] IsPlayerSpell / C_SpellBook.IsSpellKnown missing: your talents can't be read", 1, true),
    "verify: a missing guarded function says what it costs")
  issecretvalue, C_ScenarioInfo, MDT, ACTIVE_CHALLENGE = nil, nil, nil, nil
  T:Release("test58")
  ROSTER = { player = { guid = "P", name = "Me", class = "WARRIOR", spec = 73, role = "TANK" } }

  -- Reset: the prompt and Settings > Data name everything that's wiped; session state clears.
  PRINTED = ""
  SlashCmdList.KEYSTONECOMMAND("reset")
  local wipes = { "saved comps", "every setting", "run history", "boss-card edits", "Bloodlust timing" }
  local allNamed = true
  for _, wd in ipairs(wipes) do if not PRINTED:find(wd, 1, true) then allNamed = false end end
  ok(allNamed and PRINTED:find("can't be undone", 1, true), "/kc reset names everything it wipes")
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
  SlashCmdList.KEYSTONECOMMAND("help")
  for _, wd in ipairs(wipes) do if not PRINTED:find(wd, 1, true) then helpOK = false end end
  ok(helpOK, "/kc help's reset line names everything it wipes")
  AS.overrides = { X = { kind = "kick", who = {} } }
  BC.state = { dk = "KingsRest", index = 3, killed = { [1] = true, [2] = true } }
  SlashCmdList.KEYSTONECOMMAND("reset confirm")
  ok(next(AS.overrides) == nil and next(BC.state.killed) == nil and BC.state.index == 1 and nsV.db.bossProgress and next(nsV.db.bossProgress.killed) == nil,
    "reset clears assignments chosen by hand and boss progress")
  BC.state = { killed = {} }
  nsV.UI:Hide()
end

print(string.format("%d passed, %d failed", passes, fails))
return fails
