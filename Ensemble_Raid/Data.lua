-- Ensemble Raid (test build) / Data.lua
-- The season's raid content: The Venomous Abyss (8 bosses), The Unbinding of Kith'ix (1 boss)
-- and the Tidebound Grotto Lair (Nymrissa Wavecaller). Pure data; no UI.
--
-- SOURCES (November 6, 2026): Mythic Trap (https://www.mythictrap.com/en, Normal pages as the
-- baseline and Heroic pages for what Heroic adds), Method.gg's Heroic and Mythic boss guides
-- (August-October 2026), Icy Veins (The Lost Explorers, Normal and Heroic), wow.gg (Kith'ix),
-- Blizzard's Lairs post (July 30, 2026). Corrections from the author (November 6): Kith'ix is on
-- every difficulty; groups choose the wing, so the order can change (default below); Normal is the
-- baseline and Heroic/Mythic changes are labeled; Lairs have no Group Finder or LFR; World Lairs
-- scale 5-40 players, Normal/Heroic/Mythic 15-25. Details in the project doc
-- Ensemble-RaidResearch.md. Re-check every boss against the guides and Blizzard's hotfixes before
-- a release; the encounter journal is the baseline, the guides say what to actually do.
--
-- Shapes:
--   item  = { n = name, tag = short kind, d = "N"|"H"|"M" (first difficulty it applies to),
--             who = "ALL"|"TANK"|"HEALER"|"DAMAGER"|"MELEE"|"RANGED", t = what to do,
--             deadly = true (wipes or kills), src = source note when only one guide says it }
--   need  = { kind = "cap"|"role"|"class"|"range", key, d, min, sev = "must"|"rec", note }
--   call  = { w = when, t = text, d }       (leader view; "Say" posts the text)
--   row   = { id, mech, when, n, kind = "group"|"order"|"players", marker, d, fill }  (plan rows)
--   fill  = "role:TANK" | "role:HEALER" | "melee" | "ranged" | "cap:<UD cap>" | "class:<FILE>" |
--           "half1" | "half2" | "third1".."third3" | "groups:1,3,5" | "set:<k>" | "team:<k>"

local _, R = ...
if R.disabled then return end

local D = {}
R.Data = D

D.DATA_CHECKED = "November 6, 2026"

-- Difficulty keys. LFR and a Lair's World difficulty use Normal's data (Normal is the baseline).
D.DIFFS = {
  LFR = { label = "LFR",    data = "N", rank = 1, ids = { 17 } },
  W   = { label = "World",  data = "N", rank = 1, ids = {} },
  N   = { label = "Normal", data = "N", rank = 1, ids = { 14 } },
  H   = { label = "Heroic", data = "H", rank = 2, ids = { 15 } },
  M   = { label = "Mythic", data = "M", rank = 3, ids = { 16 } },
}
D.DIFF_BY_ID = {}
for key, d in pairs(D.DIFFS) do for _, id in ipairs(d.ids) do D.DIFF_BY_ID[id] = key end end

D.INSTANCES = {
  {
    key = "abyss", name = "The Venomous Abyss", kind = "raid", diffs = { "LFR", "N", "H", "M" },
    size = "Flexible 10-30 players below Mythic; Mythic 20",
    -- Default order (the author, November 6): the wings can be taken left or right, so bosses 2-5
    -- can be reordered by the player (like the Mythic+ boss-order control).
    bosses = { "nekzali", "sentinels", "vashnik", "explorers", "sszorak", "twinfangs", "altar", "ulatek" },
    orderGroups = { { 2, 3, 4, 5 } },
  },
  {
    key = "kithix", name = "The Unbinding of Kith'ix", kind = "raid", diffs = { "LFR", "N", "H", "M" },
    size = "Flexible below Mythic", bosses = { "kithix" },
  },
  {
    key = "grotto", name = "The Tidebound Grotto", kind = "lair", diffs = { "W", "N", "H", "M" },
    size = "World 5-40 players; Normal, Heroic and Mythic 15-25 (no Group Finder)", bosses = { "nymrissa" },
  },
}
D.INSTANCE = {}
for i, inst in ipairs(D.INSTANCES) do inst.index = i; D.INSTANCE[inst.key] = inst end

-- Needs every boss carries (added by Needs.lua): two tanks, the healer share, Bloodlust, battle rez.
D.GENERIC_NEEDS = {
  { kind = "role", key = "TANK", d = "N", min = 2, sev = "must", label = "Tanks" },
  { kind = "role", key = "HEALER", d = "N", share = 0.2, sev = "rec", label = "Healers" },
  { kind = "cap", key = "bloodlust", d = "N", min = 1, sev = "rec", label = "Bloodlust" },
  { kind = "cap", key = "battle_rez", d = "N", min = 1, sev = "rec", label = "Battle rez" },
}

D.BOSSES = {}
local B = D.BOSSES

B.nekzali = {
  name = "Nek'zali the Soulcoiler", short = "Nek'zali", instance = "abyss",
  aliases = { "Nek'zali" },
  src = "Mythic Trap (Normal, Heroic); Method.gg (Heroic August 11, Mythic September 22)",
  summary = "Single target with adds. Phase 1 to 50%, then an intermission where she's immune until both Echoes of Jawae die, then Phase 2: a race before her energy fills.",
  dangers = {
    { d = "N", t = "Adds reaching the well: they feed her energy and hit the raid." },
    { d = "N", t = "Standing in Possession Barrage's line, or between an Echo and the boss." },
    { d = "N", t = "Essence Rend dispelled in the middle of the raid (it spawns a Latent Cultist there)." },
    { d = "H", t = "Corpses left unburned rise again (Vessel of Awakening)." },
  },
  phases = {
    { name = "Phase 1: Soulcoil Initiation", items = {
      { n = "Soulcoil Well", tag = "Adds", d = "N", who = "DAMAGER", t = "Kill the Restless Amani before they reach the well; slows and crowd control help. Their shield only breaks to magic damage.", src = "shield: Method.gg" },
      { n = "Essence Rend", tag = "Dispel", d = "N", who = "ALL", t = "Debuffed players move to the room's edge to be dispelled: removing it spawns a Latent Cultist where you stand." },
      { n = "Essence Rend", tag = "Dispel", d = "N", who = "HEALER", t = "Dispel debuffed players once they reach the edge (Magic, per Method.gg)." },
      { n = "Soulcoil Ignition", tag = "Raid damage", d = "N", who = "HEALER", t = "The big healing moment of Phase 1: heal through it." },
      { n = "Soulcoil Ignition", tag = "Raid damage", d = "N", who = "ALL", t = "Debuffed players move to the edges." },
      { n = "Possession Barrage", tag = "Tank", d = "N", who = "TANK", t = "Move out, 30+ yards from the raid." },
      { n = "Possession Barrage", tag = "Dodge", d = "N", who = "ALL", t = "Stand behind the boss, out of the line." },
      { n = "Corpse Blight", tag = "DoT", d = "N", who = "HEALER", t = "Heal through the DoT." },
      { n = "Hollowing Strikes", tag = "Tank swap", d = "N", who = "TANK", t = "Swap at around 30-40%: each stack cuts healing taken by 5% (15% in Phase 2)." },
      { n = "Uncoiled Rage", tag = "Enrage", d = "N", who = "ALL", t = "If her energy fills, it's over: killing adds fast keeps her energy down.", deadly = true },
      { n = "Ritual Burn", tag = "Raid damage", d = "H", who = "HEALER", t = "Each Rite adds a stacking 15% damage taken, and DoTs hit harder." },
      { n = "Vessel of Awakening", tag = "Adds", d = "H", who = "ALL", t = "Killed Amani leave corpses that rise again unless Slithering Flame burns them." },
    } },
    { name = "Intermission: Ritual of Awakening (50%)", items = {
      { n = "Echo of Jawae", tag = "Kill", d = "N", who = "ALL", t = "Kill both Echoes to end the phase; don't stand between an Echo and the boss." },
      { n = "Soul Transfer", tag = "Dodge", d = "N", who = "ALL", t = "Move out of the line; a few assigned players soak it." },
      { n = "Hungering Pyre", tag = "Soak", d = "N", who = "ALL", t = "The active tank and a few players soak the circle; anyone who doesn't gets Slithering Flame." },
      { n = "Cremation", tag = "Soak", d = "H", who = "ALL", t = "Non-soakers' DoT explodes at the end and burns corpses inside its circle; the tank's soak burns them too. Soak near the corpses." },
    } },
    { name = "Phase 2: Uncoiling", items = {
      { n = "Invoke", tag = "Dodge", d = "N", who = "ALL", t = "Dodge; keep killing adds and watch for moving Latent Cultists." },
      { n = "Phase 1 continues", tag = "Repeat", d = "N", who = "ALL", t = "Essence Rend, Possession Barrage and Hollowing Strikes keep going (Hollowing Strikes now 15% per stack)." },
      { n = "Grasping Depths", tag = "Teams", d = "M", who = "ALL", t = "Well teams of 3 DPS + 1 healer each.", src = "Method.gg Mythic" },
      { n = "Soulcoiler's Curse", tag = "Interrupt", d = "M", who = "DAMAGER", t = "Interrupt every cast; Invoke silences interrupters for 3 seconds.", src = "Method.gg Mythic" },
    } },
  },
  needs = {
    { kind = "cap", key = "dispel_magic", d = "N", min = 2, sev = "rec", label = "Magic dispel", note = "Essence Rend (Magic per Method.gg; dispel at the room's edge)" },
    { kind = "cap", key = "stop", d = "N", min = 2, sev = "rec", label = "Slows and crowd control", note = "Restless Amani on their way to the well" },
    { kind = "cap", key = "interrupt", d = "M", min = 3, sev = "must", label = "Interrupts", note = "Soulcoiler's Curse, every cast" },
  },
  lust = { N = "Phase 2, after the intermission (Method.gg)" },
  prepull = {
    { d = "N", t = "Two tanks to trade Hollowing Strikes." },
    { d = "N", t = "A few soakers for Hungering Pyre, plus the active tank." },
    { d = "N", t = "Dispellers ready: Essence Rend is dispelled at the room's edge." },
    { d = "H", t = "Soak Hungering Pyre near the corpses so Cremation burns them." },
    { d = "M", t = "Two well teams of 3 DPS + 1 healer, and a kick order for Soulcoiler's Curse." },
  },
  calls = {
    { w = "Pull", d = "N", t = "Kill adds before they reach the well. Debuffed: go to the room's edge." },
    { w = "Ignition", d = "N", t = "Soulcoil Ignition: healing cooldowns now." },
    { w = "50%", d = "N", t = "Intermission: kill both Echoes. Soakers on the Pyre." },
    { w = "Intermission", d = "H", t = "Soak the Pyre near the corpses to burn them." },
    { w = "Phase 2", d = "N", t = "Bloodlust now. Burn; adds still come first." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "swap on Hollowing Strikes", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "pyre", mech = "Hungering Pyre soakers", when = "intermission", n = 4, kind = "group", marker = "star", d = "N", fill = "melee" },
    { id = "dispel", mech = "Essence Rend dispels", when = "all fight, at the room's edge", n = 2, kind = "players", d = "N", fill = "cap:dispel_magic" },
    { id = "lust", mech = "Bloodlust", when = "Phase 2", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
    { id = "well1", mech = "Well team 1", when = "Phase 2", n = 4, kind = "group", marker = "circle", d = "M", fill = "team:1" },
    { id = "well2", mech = "Well team 2", when = "Phase 2", n = 4, kind = "group", marker = "diamond", d = "M", fill = "team:2" },
    { id = "curse", mech = "Kick Soulcoiler's Curse", when = "every cast", n = 3, kind = "order", d = "M", fill = "cap:interrupt" },
  },
}

B.sentinels = {
  name = "Entombed Sentinels", short = "Sentinels", instance = "abyss",
  src = "Mythic Trap (Normal, Heroic); Method.gg (Heroic August 12, Mythic September 23)",
  summary = "Two golems that must stay 40+ yards apart, or they take 99% less damage. The raid splits in two, one group per golem. At 100 energy both go to the middle for the Helical Toxins puzzle; then groups and tanks swap sides.",
  dangers = {
    { d = "N", t = "The golems getting within 40 yards of each other." },
    { d = "N", t = "Toxic Droplets left unsquished: they explode for the whole raid." },
    { d = "N", t = "Wrong Helical Toxins totals in the intermission." },
    { d = "H", t = "Standing in the path of Living Venom's projectiles." },
  },
  phases = {
    { name = "Phase 1", items = {
      { n = "The split", tag = "Positioning", d = "N", who = "ALL", t = "Stay with your half of the raid on your golem's side." },
      { n = "Venom Coagulation", tag = "Add", d = "N", who = "DAMAGER", t = "Kill the slime fast: it pulses raid damage while it's alive." },
      { n = "Toxic Droplets", tag = "Run over", d = "N", who = "ALL", t = "Run over the droplets; any left explode for massive raid damage." },
      { n = "Blighted Blood", tag = "Dispel", d = "N", who = "HEALER", t = "Dispel as many as you can (Method.gg lists Magic dispels)." },
      { n = "Blighted Blood", tag = "Dispel", d = "N", who = "ALL", t = "If you're not dispelled you drop puddles: go to the room's edge." },
      { n = "Unstable Miasma", tag = "Soak", d = "N", who = "ALL", t = "Soak together near the edge, then spread out. Too few soakers is lethal.", deadly = true },
      { n = "Empowering Slam", tag = "Tank", d = "N", who = "TANK", t = "Defensives; swap after each slam (it stacks 15% per slam in a row, Method.gg)." },
      { n = "Bloodvenom Injection", tag = "Tank", d = "N", who = "TANK", t = "Defensives; swap before the stacks get high, and move off before it ends (it leaves a puddle)." },
      { n = "Living Venom", tag = "Dodge", d = "H", who = "ALL", t = "Venom shoots back to the Breath of Ula'tek as projectiles: stay out of their path." },
      { n = "Blood Venom", tag = "Puddles", d = "H", who = "ALL", t = "Blood debuffs drop puddles under you: drop them at the room's edge." },
      { n = "Shifting Protovenom", tag = "Spread", d = "M", who = "ALL", t = "Pre-spread for the eruptions; orb counts are hidden.", src = "Method.gg Mythic" },
    } },
    { name = "Intermission: Vitriolic Stasis (100 energy)", items = {
      { n = "Helical Toxins", tag = "Puzzle", d = "N", who = "ALL", t = "Pair up so your green-orb stacks total exactly 4, within 30 seconds. Wrong totals: massive damage and a huge DoT. A strong defensive or an immunity survives a mistake.", deadly = true },
      { n = "Swap sides", tag = "Positioning", d = "N", who = "ALL", t = "After the intermission, groups and tanks trade golems." },
    } },
  },
  needs = {
    { kind = "cap", key = "dispel_magic", d = "N", min = 2, sev = "rec", label = "Magic dispel", note = "Blighted Blood (type not stated by Mythic Trap; Method.gg lists Magic)" },
  },
  lust = { N = "On pull (Method.gg)" },
  prepull = {
    { d = "N", t = "Split the raid in two halves, one per golem, 40+ yards apart." },
    { d = "N", t = "One tank per golem; they trade after each intermission." },
    { d = "N", t = "Dispellers in both halves." },
  },
  calls = {
    { w = "Pull", d = "N", t = "Bloodlust. Split: {star} group left golem, {circle} group right. Keep them 40 yards apart." },
    { w = "Slime", d = "N", t = "Kill the slime." },
    { w = "Droplets", d = "N", t = "Squish every droplet." },
    { w = "100 energy", d = "N", t = "Intermission: pair up to exactly 4 stacks." },
    { w = "After", d = "N", t = "Swap sides: groups and tanks trade golems." },
  },
  plan = {
    { id = "tanks", mech = "Tanks (one per golem)", when = "trade after each intermission", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "left", mech = "Left golem group", when = "Phase 1 (swap after each intermission)", n = 10, kind = "group", marker = "star", d = "N", fill = "half1" },
    { id = "right", mech = "Right golem group", when = "Phase 1 (swap after each intermission)", n = 10, kind = "group", marker = "circle", d = "N", fill = "half2" },
    { id = "dispel", mech = "Blighted Blood dispels", when = "both sides", n = 2, kind = "players", d = "N", fill = "cap:dispel_magic" },
    { id = "lust", mech = "Bloodlust", when = "on pull", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
  },
}

B.vashnik = {
  name = "Vashnik the Malignant", short = "Vashnik", instance = "abyss",
  src = "Mythic Trap (Normal, Heroic); Method.gg (Heroic September 3, Mythic September 22)",
  summary = "Single target and three fountains (Blood, Shadow, Flame). At 100 energy he drinks from the two nearest (Imbibe): raid damage, a permanent Toxic Vapor stack and adds that depend on the fountains. Where the tank stands decides which fountains.",
  dangers = {
    { d = "N", t = "Adds left alive: after 60 seconds they can't be crowd-controlled, and one reaching the cavity bursts the raid.", },
    { d = "N", t = "Burning Venom adds killed at the same time." },
    { d = "N", t = "Exploding Infection going off next to other players." },
    { d = "H", t = "Malignant Catalyst circles left empty (they explode)." },
  },
  phases = {
    { name = "One phase", items = {
      { n = "Imbibe", tag = "Fountains", d = "N", who = "TANK", t = "Move him to the fountains the raid wants, and call the pair out loud." },
      { n = "Imbibe", tag = "Fountains", d = "N", who = "ALL", t = "A common rotation: Blood + Shadow, then Shadow + Flame, then Flame + Blood (Method.gg)." },
      { n = "Dripping Fangs", tag = "Tank swap", d = "N", who = "TANK", t = "Swap every cast." },
      { n = "Splitting Clot", tag = "Adds", d = "N", who = "DAMAGER", t = "Kill the adds; they split on death and can't be crowd-controlled." },
      { n = "Miasmic Coating", tag = "Adds", d = "N", who = "ALL", t = "Kill the adds, then heal off the absorb quickly." },
      { n = "Burning Presence", tag = "Adds", d = "N", who = "DAMAGER", t = "Kill Burning Venom adds a few seconds apart, never together; crowd control or Death Grip one." },
      { n = "Siphoning Infection", tag = "Soak", d = "N", who = "ALL", t = "Blood fountain: help soak by grouping up in the debuffed player's circle." },
      { n = "Stygian Infection", tag = "Absorb", d = "N", who = "HEALER", t = "Shadow fountain: heal through the absorb." },
      { n = "Exploding Infection", tag = "Fall-off", d = "N", who = "ALL", t = "Flame fountain: move far out before it ends. If it's dispelled, stagger it: each removal hits the raid (Method.gg)." },
      { n = "Plague Froth", tag = "Spread", d = "N", who = "ALL", t = "Spread and dodge the waves." },
      { n = "Toxic Vapor", tag = "Ramping", d = "N", who = "HEALER", t = "Raid damage that grows with every Imbibe: heal through it." },
      { n = "Malignant Catalyst", tag = "Soak", d = "H", who = "ALL", t = "A raid burst that leaves soak circles: every circle needs someone in it." },
      { n = "Burning Venom", tag = "Adds", d = "H", who = "DAMAGER", t = "Each death adds a stacking raid DoT: a few seconds apart matters more now." },
      { n = "Third Burning Venom", tag = "Adds", d = "M", who = "ALL", t = "A third Burning Venom (Banish one); Malignant Totems are cleared by aiming Plague Froth waves at them.", src = "Method.gg Mythic" },
    } },
  },
  needs = {
    { kind = "cap", key = "stop", d = "N", min = 2, sev = "rec", label = "Crowd control", note = "a Burning Venom or Shrouded Venom" },
    { kind = "class", key = "DEATHKNIGHT", d = "N", min = 1, sev = "rec", label = "Death Grip", note = "pulling Burning Venom adds apart (Method.gg)" },
  },
  lust = { N = "On pull (Method.gg)" },
  prepull = {
    { d = "N", t = "Agree on the fountain rotation; the tank calls the pair before each Imbibe." },
    { d = "N", t = "Who crowd-controls a Burning Venom so the adds die apart." },
  },
  calls = {
    { w = "Pull", d = "N", t = "Bloodlust. Tank calls the fountain pair." },
    { w = "Imbibe", d = "N", t = "Adds incoming: Burning Venoms a few seconds apart." },
    { w = "Catalyst", d = "H", t = "Fill every soak circle." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "swap every Dripping Fangs", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "caller", mech = "Fountain caller", when = "before each Imbibe", n = 1, kind = "players", d = "N", fill = "role:TANK" },
    { id = "cc", mech = "Crowd control on Burning Venom", when = "each Imbibe", n = 2, kind = "players", marker = "moon", d = "N", fill = "cap:stop" },
    { id = "grip", mech = "Death Grip adds apart", when = "each Imbibe", n = 1, kind = "players", d = "N", fill = "class:DEATHKNIGHT" },
    { id = "lust", mech = "Bloodlust", when = "on pull", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
  },
}

B.explorers = {
  name = "The Lost Explorers", short = "Explorers", instance = "abyss",
  aliases = { "Lost Explorers" },
  src = "Mythic Trap (Normal, Heroic); Icy Veins (Normal and Heroic, August 13); Method.gg (Mythic September 22)",
  summary = "Three turtles, Trader Gebbo, First Mate Nama and Scrollsage Iku, all attackable with separate health. Kill them evenly: each has an ultimate. Never let all three stand within 30 yards (99% less damage). Suggested order: Gebbo, Nama, Iku.",
  dangers = {
    { d = "N", t = "All three bosses stacked together." },
    { d = "N", t = "Final Ascension not stopped with the fish." },
    { d = "N", t = "Bombs dropped inside the raid." },
  },
  phases = {
    { name = "One phase", items = {
      { n = "Throw Junk", tag = "Boxes", d = "N", who = "ALL", t = "Run over boxes to clear them and find the fish; unsoaked boxes explode after 25 seconds." },
      { n = "Dark Whispers", tag = "Interrupt", d = "N", who = "ALL", t = "Hit a turtle with the fish to stop Final Ascension (the raid takes rot damage after).", deadly = true },
      { n = "Explosive Surprise", tag = "Bomb", d = "N", who = "ALL", t = "Gebbo's ultimate: drop the bomb far from the group and dodge the shockwave with a mushroom." },
      { n = "Mighty Thud", tag = "Soak", d = "N", who = "ALL", t = "Nama's ultimate: split up to soak three circles (Icy Veins: one melee spot, two ranged spots)." },
      { n = "Frostfire Volley", tag = "Puddles", d = "N", who = "ALL", t = "Iku's ultimate: drop your puddle, then clear your debuff in an opposite puddle; never touch an opposite debuff while dropping yours." },
      { n = "Blink Nova", tag = "Spread", d = "N", who = "ALL", t = "If you're marked, move far from the raid." },
      { n = "Evil Eyes", tag = "Dodge", d = "N", who = "ALL", t = "Dodge the circles." },
      { n = "Shell Spin", tag = "Bait", d = "N", who = "MELEE", t = "Bait the three shells to the edge, away from ranged." },
      { n = "Icebound Flames", tag = "Interrupt", d = "N", who = "DAMAGER", t = "Kick Iku's bolt (a 2-3 player rotation); if one lands, dispel the DoT." },
      { n = "Steady Strikes", tag = "Tank", d = "N", who = "TANK", t = "Nama: watch your physical vulnerability stacks; defensives." },
      { n = "Shredding Shards", tag = "Tank swap", d = "N", who = "TANK", t = "Iku: swap bosses after each cast." },
      { n = "United Defense", tag = "Positioning", d = "H", who = "TANK", t = "Only one other boss can be near Nama: bring Nama to Gebbo or Iku one at a time, aiming to kill all three together." },
      { n = "Relic Rupture", tag = "Bleed", d = "M", who = "ALL", t = "Each crate opened bleeds the raid (a dedicated box popper); one mushroom per bomb; a leftover Frostfire debuff wipes.", src = "Method.gg Mythic" },
    } },
  },
  needs = {
    { kind = "cap", key = "interrupt", d = "N", min = 3, sev = "must", label = "Interrupts", note = "Icebound Flames, a 2-3 player rotation" },
  },
  lust = { N = "On pull (Icy Veins, Method.gg)" },
  prepull = {
    { d = "N", t = "Kill order: Gebbo, Nama, Iku, evenly. Never all three together." },
    { d = "N", t = "A kick rotation for Icebound Flames." },
    { d = "N", t = "Mighty Thud soak teams: groups 1, 3, 5 and groups 2, 4, 6." },
    { d = "H", t = "Tanks bring Nama to one other turtle at a time." },
  },
  calls = {
    { w = "Pull", d = "N", t = "Bloodlust. Gebbo first. Never all three together." },
    { w = "Bomb", d = "N", t = "Bombs out; use a mushroom for the shockwave." },
    { w = "Mighty Thud", d = "N", t = "{star} team soaks 1 and 3, {circle} team soaks 2." },
    { w = "Ascension", d = "N", t = "Fish! Hit the turtle now." },
    { w = "Nama", d = "H", t = "Nama goes to one turtle at a time." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "swap after each Shredding Shards", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "kicks", mech = "Kick Icebound Flames", when = "every cast", n = 3, kind = "order", d = "N", fill = "cap:interrupt" },
    { id = "thud1", mech = "Mighty Thud team 1", when = "soaks 1 and 3", n = 10, kind = "group", marker = "star", d = "N", fill = "groups:1,3,5" },
    { id = "thud2", mech = "Mighty Thud team 2", when = "soak 2", n = 10, kind = "group", marker = "circle", d = "N", fill = "groups:2,4,6" },
    { id = "shells", mech = "Shell Spin baiters", when = "to the edge", n = 3, kind = "players", d = "N", fill = "melee" },
    { id = "fish", mech = "Box popper and fish carrier", when = "every Throw Junk", n = 1, kind = "players", d = "N", fill = "ranged" },
    { id = "lust", mech = "Bloodlust", when = "on pull", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
  },
}

B.sszorak = {
  name = "Sszorak", short = "Sszorak", instance = "abyss",
  src = "Mythic Trap (Normal, Heroic); Method.gg (Heroic August 13, Mythic October 2)",
  summary = "One phase with winds. Apex Predator is a five-hit tank combo of Ravage, Mutilate and Tempest. During the winds he takes 30% more damage. Venomous Surge places the cysts that decide the wind order.",
  dangers = {
    { d = "N", t = "Ravage aimed at the raid." },
    { d = "N", t = "Getting knocked off by Raging Crosswinds without your partner." },
    { d = "H", t = "The same group soaking Mutilate twice in a row (500% vulnerability)." },
  },
  phases = {
    { name = "One phase", items = {
      { n = "Apex Predator", tag = "Tank combo", d = "N", who = "TANK", t = "Be ready to taunt mid-combo: aim Ravage away from the raid and Mutilate at the soakers." },
      { n = "Ravage", tag = "Tankbuster", d = "N", who = "TANK", t = "Aim it away from the raid; trade it between casts (it stacks a vulnerability)." },
      { n = "Mutilate", tag = "Soak", d = "N", who = "ALL", t = "Soak the tank's hit with your group; dodge the tornadoes." },
      { n = "Tempest", tag = "Tornadoes", d = "N", who = "ALL", t = "Dodge; pair with an opposite so you aren't knocked off." },
      { n = "Venomous Surge", tag = "Cysts", d = "N", who = "ALL", t = "If you're marked, run out and place your Viscous Cyst opposite the marked tunnel; save extras to pop during the winds." },
      { n = "Howling Maelstrom", tag = "Winds", d = "N", who = "ALL", t = "Watch the wind order; he takes 30% more damage now." },
      { n = "Raging Crosswinds", tag = "Knockback", d = "N", who = "ALL", t = "Pair with the player whose arrow points the opposite way and collide; a knockback immunity can strand your partner." },
      { n = "Corroding Venom", tag = "Tank swap", d = "N", who = "TANK", t = "Swap at high stacks (3% damage taken each)." },
      { n = "Ula'tek's Presence", tag = "Rot", d = "N", who = "HEALER", t = "Heal through the constant raid damage." },
      { n = "Dig In", tag = "Burn", d = "N", who = "ALL", t = "Intermission: pixel stack in the middle and get pushed into the cyst opposite the active tunnel; he takes 30% more damage for 25 seconds.", src = "Method.gg" },
      { n = "Mutilate", tag = "Soak", d = "H", who = "ALL", t = "Soaking gives 500% vulnerability: two soak groups of 5+ alternate." },
      { n = "Ravage", tag = "Tankbuster", d = "H", who = "TANK", t = "400% vulnerability: strict swaps." },
      { n = "Caustic Claws", tag = "Puddles", d = "H", who = "ALL", t = "Venom lands in marked circles and leaves puddles: dodge, and pair with an opposite." },
      { n = "Serpent's Fury", tag = "Stack", d = "M", who = "ALL", t = "A 15-player stack resets his energy; four crosswind directions (Paladins, Priests and Shamans need partners).", src = "Method.gg Mythic" },
    } },
  },
  needs = {},
  lust = { N = "On pull, or the Dig In window (Method.gg)" },
  prepull = {
    { d = "N", t = "Tanks: Ravage away from the raid, Mutilate at the soakers." },
    { d = "H", t = "Two Mutilate soak groups that alternate." },
  },
  calls = {
    { w = "Pull", d = "N", t = "Bloodlust. Tanks: Ravage away, Mutilate at the soakers." },
    { w = "Surge", d = "N", t = "Cysts opposite the marked tunnels." },
    { w = "Crosswinds", d = "N", t = "Find your opposite partner." },
    { w = "Mutilate", d = "H", t = "Mutilate: {star} group, then {circle} group. Alternate." },
    { w = "Dig In", d = "N", t = "Burn: he takes 30% more damage." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "trade Ravage between casts", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "mut1", mech = "Mutilate soak group 1", when = "odd casts", n = 6, kind = "group", marker = "star", d = "H", fill = "half1" },
    { id = "mut2", mech = "Mutilate soak group 2", when = "even casts", n = 6, kind = "group", marker = "circle", d = "H", fill = "half2" },
    { id = "lust", mech = "Bloodlust", when = "on pull", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
  },
}

B.twinfangs = {
  name = "The Twin Fangs", short = "Twin Fangs", instance = "abyss",
  aliases = { "Twin Fangs", "Ithraz", "Vexhul" },
  src = "Mythic Trap (Normal, Heroic); Method.gg (Heroic August 14)",
  summary = "Two serpents, Ithraz and Vexhul, that can't be moved and have separate health: kill them together, or the survivor enrages. Eternal Venom stacks all fight; only soaking Ravenous Feast removes a stack.",
  dangers = {
    { d = "N", t = "Eternal Venom reaching 11 stacks (massive damage and a stun)." },
    { d = "N", t = "Caustic Globule orbs left unsoaked (they explode after 10 seconds)." },
    { d = "N", t = "One serpent far ahead of the other." },
    { d = "H", t = "Eternal Venom is a one-shot at 10 stacks (Mythic: 9)." },
  },
  phases = {
    { name = "One phase", items = {
      { n = "Eternal Venom", tag = "Stacks", d = "N", who = "ALL", t = "Stacks never fall off; soak Ravenous Feast to remove one. 11 stacks on Normal is massive damage and a stun.", deadly = true },
      { n = "Caustic Deluge", tag = "Soak orbs", d = "N", who = "ALL", t = "Soak every Globule orb quickly (they explode after 10 seconds)." },
      { n = "Venomous Emergence", tag = "Adds", d = "N", who = "DAMAGER", t = "Kill the three Spawns of Vexhul; dodge their Corrosive Spit lines." },
      { n = "Ravenous Feast", tag = "Soak", d = "N", who = "ALL", t = "Help soak the three smashes (each removes a stack); debuffed players go to the edges." },
      { n = "Coiling Ichor", tag = "Move out", d = "N", who = "ALL", t = "If you're marked, move to the edge: it grows and leaves puddles." },
      { n = "Stone Breaker", tag = "Tank soak", d = "N", who = "TANK", t = "One tank soaks all three smashes in order (33% vulnerability each for 90 seconds); tanks alternate sets." },
      { n = "Stir the Depths", tag = "Waves", d = "N", who = "ALL", t = "Dodge the waves (they add Eternal Venom)." },
      { n = "Vile Flood", tag = "Beam", d = "N", who = "ALL", t = "Move with the rotating beam and dodge the Sanguine Storm swirlies on the way." },
      { n = "Clotted Bolt", tag = "Tank", d = "N", who = "TANK", t = "Stay in range, or the boss bolts." },
      { n = "Envenomed", tag = "Tank", d = "N", who = "TANK", t = "Watch your stacks (10% vulnerability each)." },
      { n = "Toxic Fumes", tag = "Rot", d = "N", who = "HEALER", t = "Heal through raid damage all fight." },
      { n = "Uncoiled Wrath", tag = "Enrage", d = "N", who = "ALL", t = "Kill both evenly.", deadly = true },
      { n = "Ravenous Feast", tag = "Soak", d = "H", who = "ALL", t = "800% vulnerability and a knockback: three soak groups, nobody soaks twice in a set (Method.gg: 7+ each)." },
      { n = "Sanguine Storm", tag = "Puddles", d = "H", who = "ALL", t = "The swirlies leave damaging, slowing puddles." },
      { n = "Eternal Venom", tag = "Stacks", d = "M", who = "ALL", t = "A one-shot at 9 stacks." },
    } },
  },
  needs = {},
  lust = { N = "On pull (Method.gg)" },
  prepull = {
    { d = "N", t = "Damage evenly on both serpents." },
    { d = "N", t = "Who soaks the Caustic Globule orbs." },
    { d = "H", t = "Three Ravenous Feast soak groups; nobody soaks twice in a set." },
  },
  calls = {
    { w = "Pull", d = "N", t = "Bloodlust. Kill both evenly." },
    { w = "Globules", d = "N", t = "Soak the orbs." },
    { w = "Feast", d = "H", t = "Ravenous Feast: {star}, then {circle}, then {diamond}." },
    { w = "Beam", d = "N", t = "Move with the beam." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "alternate Stone Breaker sets", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "orbs", mech = "Globule orb soakers", when = "each Caustic Deluge", n = 3, kind = "players", d = "N", fill = "ranged" },
    { id = "feast1", mech = "Ravenous Feast soak 1", when = "first smash", n = 7, kind = "group", marker = "star", d = "H", fill = "third1" },
    { id = "feast2", mech = "Ravenous Feast soak 2", when = "second smash", n = 7, kind = "group", marker = "circle", d = "H", fill = "third2" },
    { id = "feast3", mech = "Ravenous Feast soak 3", when = "third smash", n = 7, kind = "group", marker = "diamond", d = "H", fill = "third3" },
    { id = "lust", mech = "Bloodlust", when = "on pull", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
  },
}

B.altar = {
  name = "The Coiled Altar", short = "Coiled Altar", instance = "abyss",
  aliases = { "Coiled Altar", "Zul'jan", "Malacrass" },
  src = "Mythic Trap (Normal, Heroic); Method.gg (Heroic August 22, Mythic October 3)",
  summary = "Phase 1 is Zul'jan alone. The intermission makes him take 100% more damage while Malacrass is immune. Phase 2 brings Malacrass; Phase 3 fuses them, with stronger Phase 1 and 2 mechanics. Kill them evenly at the end.",
  dangers = {
    { d = "N", t = "Eternal Nightfall finishing its cast: the raid wipes." },
    { d = "N", t = "A mind-controlled player walking off the edge (break Dreadmarch's shield)." },
    { d = "N", t = "Fewer than 5 Guillotine soakers." },
    { d = "H", t = "A Spiteful Soulcoiler reaching full energy (its fear can't be interrupted then)." },
  },
  phases = {
    { name = "Phase 1: Serpent's Bargain", items = {
      { n = "Fangs of the Coiled Altar", tag = "Raid damage", d = "N", who = "HEALER", t = "Heal through it; the puddles grow with each cast." },
      { n = "Coalesced Venom", tag = "Orbs", d = "N", who = "ALL", t = "Pick up orbs and move them into clusters (holding one is a 5-second DoT)." },
      { n = "Sever", tag = "Tank frontal", d = "N", who = "TANK", t = "Aim the cone at the orb clusters; swap each cast (200% vulnerability)." },
      { n = "Guillotine", tag = "Soak", d = "N", who = "ALL", t = "At least 5 players soak, then run out (40-yard explosion).", deadly = true },
      { n = "Axegrinder", tag = "Dodge", d = "N", who = "ALL", t = "Dodge the spinning axes." },
      { n = "Venomfang", tag = "Dispel", d = "N", who = "HEALER", t = "Dispel the Poison DoT when you can." },
      { n = "Coalesced Venom", tag = "Orbs", d = "H", who = "ALL", t = "Destroying orbs adds a stacking raid DoT." },
      { n = "Axegrinder", tag = "Dodge", d = "H", who = "ALL", t = "The axes don't despawn." },
      { n = "Guillotine", tag = "Soak", d = "H", who = "ALL", t = "Soakers get 500% vulnerability: two groups alternate." },
    } },
    { name = "Intermission: The Claimed Vessel", items = {
      { n = "Soulbinding", tag = "Damage amp", d = "N", who = "ALL", t = "Everything on Zul'jan (100% more damage taken; Malacrass is immune). Bloodlust here." },
      { n = "Fragment of Malacrass", tag = "Souls", d = "N", who = "ALL", t = "Block the souls (each one reaching Zul'jan heals him); blocking hits the raid, so watch health." },
    } },
    { name = "Phase 2: Usurper's Reprisal", items = {
      { n = "Dreadmarch", tag = "Mind control", d = "N", who = "ALL", t = "Break the shield before the player walks off the edge." },
      { n = "Manifestation of Dread", tag = "Ghosts", d = "N", who = "ALL", t = "Kite the ghosts into a clump by looking away, then look at them to stop them; touching one mind-controls you." },
      { n = "Soul Sever", tag = "Tank frontal", d = "N", who = "TANK", t = "Aim it at the ghosts (200% vulnerability and a DoT)." },
      { n = "Eternal Nightfall", tag = "Shield", d = "N", who = "ALL", t = "Break the shield fast: if the cast finishes, the raid wipes.", deadly = true },
      { n = "Gloombomb", tag = "Clones", d = "N", who = "ALL", t = "If you're marked, move out, then collect your clones." },
      { n = "Dreadful Presence", tag = "Rot", d = "N", who = "HEALER", t = "Heal through the constant damage." },
      { n = "Spiteful Soulcoiler", tag = "Interrupt", d = "H", who = "RANGED", t = "Interrupt Wail of Terror (a raid fear) every cast and kill it before full energy, or it can't be interrupted. It moves after each kick, so ranged usually take it." },
    } },
    { name = "Phase 3: Coiled Union", items = {
      { n = "Defilement of the Crucible", tag = "Tank swap", d = "N", who = "TANK", t = "Swap to drop the stacks (a DoT from melee swings)." },
      { n = "Defilement of the Crucible", tag = "Raid damage", d = "N", who = "HEALER", t = "Healing cooldowns (Method.gg)." },
      { n = "Blighted Sever", tag = "Tank frontal", d = "N", who = "TANK", t = "Hit both bosses with it, with orbs and ghosts nearby." },
      { n = "Dread Bolt", tag = "Tank", d = "N", who = "TANK", t = "A bolt on the primary target." },
      { n = "Soulbound", tag = "Enrage", d = "N", who = "ALL", t = "Kill both evenly.", deadly = true },
      { n = "Mythic", tag = "Mythic", d = "M", who = "ALL", t = "Orb cleanup by mobile players, stuns on every Dreadmarch, immunities for the second Guillotine, ghost control.", src = "Method.gg Mythic" },
    } },
  },
  needs = {
    { kind = "cap", key = "dispel_poison", d = "N", min = 2, sev = "must", label = "Poison dispel", note = "Venomfang" },
    { kind = "role", key = "HEALER", d = "H", share = 0.25, sev = "rec", label = "Healers", note = "Method.gg brings 5 of 20 on Heroic" },
    { kind = "cap", key = "interrupt", d = "H", min = 2, sev = "must", label = "Interrupts", note = "Spiteful Soulcoiler's Wail of Terror" },
  },
  lust = { N = "The Soulbinding intermission (Mythic Trap, Method.gg)" },
  prepull = {
    { d = "N", t = "5+ Guillotine soakers at the purple corner marker." },
    { d = "N", t = "Poison dispellers for Venomfang." },
    { d = "H", t = "Two Guillotine groups that alternate, and ranged kickers for the Spiteful Soulcoiler." },
  },
  calls = {
    { w = "Pull", d = "N", t = "Orbs into clusters; tank aims Sever at them." },
    { w = "Guillotine", d = "N", t = "Guillotine: 5+ soak at the {diamond} corner, then run out." },
    { w = "Guillotine", d = "H", t = "Guillotine: {star} group now, {circle} group next." },
    { w = "Soulbinding", d = "N", t = "Bloodlust now. Everything on Zul'jan." },
    { w = "Nightfall", d = "N", t = "Break the shield NOW." },
    { w = "Dreadmarch", d = "N", t = "Break the shield on the mind-controlled player." },
    { w = "Phase 3", d = "N", t = "Kill both evenly. Healing cooldowns on Defilement." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "swap every Sever", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "guil", mech = "Guillotine soakers", when = "Phase 1 and 3, at the corner", n = 5, kind = "group", marker = "diamond", d = "N", fill = "melee" },
    { id = "guil1", mech = "Guillotine group 1", when = "odd casts", n = 5, kind = "group", marker = "star", d = "H", fill = "half1" },
    { id = "guil2", mech = "Guillotine group 2", when = "even casts", n = 5, kind = "group", marker = "circle", d = "H", fill = "half2" },
    { id = "poison", mech = "Venomfang dispels", when = "all fight", n = 3, kind = "players", d = "N", fill = "cap:dispel_poison" },
    { id = "wail", mech = "Kick Wail of Terror", when = "Phase 2 and 3", n = 3, kind = "order", d = "H", fill = "cap:interrupt" },
    { id = "lust", mech = "Bloodlust", when = "Soulbinding", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
  },
}

B.ulatek = {
  name = "Ula'tek", short = "Ula'tek", instance = "abyss",
  src = "Mythic Trap (Normal, Heroic); Method.gg (Heroic August 30, Mythic October 16)",
  summary = "Phase 1 is egg control and the first damage amp. Phase 2 splits the raid into two sides with a Doomscale Warden and the Cauldron. An intermission shatters the platform; Phase 3 breaks four platforms in turn, then the final amp. Fury Unleashed is the hard enrage.",
  dangers = {
    { d = "N", t = "Malice not interrupted (Phase 2)." },
    { d = "N", t = "Vicious Echoes not interrupted: it stuns the raid and wipes it." },
    { d = "N", t = "Standing on a platform as it breaks (Phase 3)." },
    { d = "H", t = "Grasping Fangs tethers snapped all at once." },
  },
  phases = {
    { name = "Phase 1: Fury of the Serpent Mother", items = {
      { n = "Malignant Shell", tag = "Eggs", d = "N", who = "ALL", t = "Keep eggs out of the venom: venom hatches them. Vipers are dangerous; Rawlings are weak." },
      { n = "Caustic Waves", tag = "Waves", d = "N", who = "ALL", t = "Dodge the venom waves and keep them off the eggs." },
      { n = "Call of the Serpent", tag = "Eggs", d = "N", who = "ALL", t = "Pick up the new falling eggs and move out of their landing spots." },
      { n = "Mephitic Thrash", tag = "Tail", d = "N", who = "TANK", t = "Run out and back in, leaving no eggs behind." },
      { n = "Spectral Coils", tag = "Soak", d = "N", who = "ALL", t = "Two circles: one group soaks each." },
      { n = "Rage of the Shackled", tag = "Damage amp", d = "N", who = "ALL", t = "Hit the Heart (100% more damage taken) and dodge the rocks; tanks stay in Tail range." },
      { n = "Rattler Slam", tag = "Tail", d = "N", who = "TANK", t = "Stay in melee range of the Tail, or the raid takes massive damage." },
      { n = "Mother's Wrath", tag = "Tankbuster", d = "N", who = "TANK", t = "Defensives: a knockback, a slow you can remove, and a DoT." },
      { n = "Unchecked Rage", tag = "Positioning", d = "N", who = "TANK", t = "Someone must always be in melee, or the raid takes damage." },
      { n = "Necrotic Vapors", tag = "Rot", d = "N", who = "HEALER", t = "Heal through raid damage all fight." },
      { n = "Egg adds", tag = "Adds", d = "H", who = "ALL", t = "Rawlings stack a DoT on their target; Vipers make ground AoE, shield themselves and hit the raid." },
    } },
    { name = "Intermission: The Shattering", items = {
      { n = "Spectral Coils", tag = "Soak", d = "N", who = "ALL", t = "Soak a smash, then run to the next; one group per spot (Method.gg: group 1 takes casts 1, 3, 5, group 2 casts 2, 4, 6). Grab eggs between soaks." },
    } },
    { name = "Phase 2: Children of the Doomscale", items = {
      { n = "Malice", tag = "Interrupt", d = "N", who = "DAMAGER", t = "Always interrupt each Doomscale Warden's Malice. The Warden guards the ledge eggs until it dies.", deadly = true },
      { n = "Grasping Fangs", tag = "Tethers", d = "N", who = "ALL", t = "If you're tethered, break it slowly: each break is a DoT." },
      { n = "Grasping Fangs", tag = "Tethers", d = "H", who = "ALL", t = "Each break hits both sides of the raid: no more than two at a time." },
      { n = "Virulent Spit", tag = "Dodge", d = "N", who = "ALL", t = "Massive damage: dodge it." },
      { n = "Doomscale Cauldron", tag = "Eggs", d = "N", who = "ALL", t = "Put eggs in the cauldron; the big Doomscale egg starts a timer that hatches them all." },
      { n = "Desperate Thrash", tag = "Frontal", d = "N", who = "ALL", t = "Dodge the Weakened Doomscale's frontal; don't hit allies when crossing back." },
      { n = "Anguished Cry", tag = "Interrupt", d = "N", who = "DAMAGER", t = "Interrupt the Weakened Doomscale." },
      { n = "Crossing back", tag = "Movement", d = "H", who = "ALL", t = "Grips and rescues help players cross; a Warlock's gate for the return (Method.gg)." },
    } },
    { name = "Phase 3: Ula'tek's Ascension", items = {
      { n = "Circling Prey", tag = "Platforms", d = "N", who = "ALL", t = "Move to the next platform before it breaks; anyone left on it dies.", deadly = true },
      { n = "Blightscale Clutch", tag = "Adds", d = "N", who = "DAMAGER", t = "Kill the attackable eggs before they hatch." },
      { n = "Acidic Explosion", tag = "Adds", d = "N", who = "DAMAGER", t = "Kill Shriekers fast: each cast is a raid DoT." },
      { n = "Serpent's Bite", tag = "Soak", d = "N", who = "ALL", t = "Three groups (melee, healer, ranged): the bitten player dies unless soaked inside the circles." },
      { n = "Volatile Purge", tag = "Spread", d = "N", who = "ALL", t = "Spread out after soaking a bite." },
      { n = "Vicious Echoes", tag = "Interrupt", d = "N", who = "DAMAGER", t = "Always interrupt the Shrieker: a missed one stuns the raid and wipes it.", deadly = true },
      { n = "Phase 1 continues", tag = "Repeat", d = "N", who = "ALL", t = "Phase 1's mechanics are back on top of these." },
    } },
  },
  needs = {
    { kind = "cap", key = "interrupt", d = "N", min = 4, sev = "must", label = "Interrupts", note = "Malice, Anguished Cry, Vicious Echoes (all on adds)" },
    { kind = "cap", key = "dispel_poison", d = "H", min = 2, sev = "must", label = "Poison dispel", note = "Method.gg's required utility on Heroic" },
    { kind = "role", key = "HEALER", d = "H", share = 0.25, sev = "rec", label = "Healers", note = "Method.gg brings 5 of 20 on Heroic; Platform 2 hits hardest" },
    { kind = "class", key = "DEATHKNIGHT,PRIEST", d = "H", min = 1, sev = "rec", label = "Rescue / grip", note = "crossing back in Phase 2" },
    { kind = "class", key = "WARLOCK", d = "H", min = 1, sev = "rec", label = "Demonic Gateway", note = "the return in Phase 2" },
  },
  lust = { N = "The first damage amp (Rage of the Shackled), Phase 1 (Method.gg Heroic)", M = "On landing back after Phase 2 (Method.gg Mythic)" },
  prepull = {
    { d = "N", t = "Two soak groups for Spectral Coils (left and right); the same groups split the intermission." },
    { d = "N", t = "Three Serpent's Bite sets: melee + healer + ranged each." },
    { d = "N", t = "Kickers for Malice (Warden), Anguished Cry (Weakened Doomscale), Vicious Echoes (Shriekers)." },
    { d = "H", t = "Bring 5 healers if you can." },
    { d = "H", t = "A Warlock keeps Demonic Gateway for the return in Phase 2." },
  },
  calls = {
    { w = "Pull", d = "N", t = "Grab the three eggs. Bloodlust waits for the amp." },
    { w = "Phase 1 amp", d = "N", t = "Bloodlust now. Burn the Heart." },
    { w = "Phase 2", d = "N", t = "Split sides. Kill the Warden first, kick Malice." },
    { w = "Phase 2", d = "N", t = "Feed eggs to the Cauldron. Kill the Doomscales close together." },
    { w = "Intermission", d = "N", t = "Coils: {star} group soaks 1, 3, 5; {circle} group soaks 2, 4, 6." },
    { w = "Phase 3", d = "N", t = "Bite sets {triangle} {diamond} {square}: leech, then spread." },
    { w = "Platform 2", d = "N", t = "All defensives. Off the platform before it breaks." },
    { w = "Final amp", d = "N", t = "Everything. Fury Unleashed is the hard enrage." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "body / tail; swap on high Stone Venom", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "coilL", mech = "Spectral Coils, left", when = "Phase 1, then intermission casts 1-3-5", n = 10, kind = "group", marker = "star", d = "N", fill = "half1" },
    { id = "coilR", mech = "Spectral Coils, right", when = "Phase 1, then intermission casts 2-4-6", n = 10, kind = "group", marker = "circle", d = "N", fill = "half2" },
    { id = "bite1", mech = "Serpent's Bite, set 1", when = "Phase 3", n = 3, kind = "group", marker = "triangle", d = "N", fill = "set:1" },
    { id = "bite2", mech = "Serpent's Bite, set 2", when = "Phase 3", n = 3, kind = "group", marker = "diamond", d = "N", fill = "set:2" },
    { id = "bite3", mech = "Serpent's Bite, set 3", when = "Phase 3", n = 3, kind = "group", marker = "square", d = "N", fill = "set:3" },
    { id = "malice", mech = "Kick Malice (Warden)", when = "Phase 2", n = 3, kind = "order", d = "N", fill = "cap:interrupt" },
    { id = "cry", mech = "Kick Anguished Cry", when = "Phase 2, Weakened Doomscale", n = 3, kind = "order", d = "N", fill = "cap:interrupt" },
    { id = "echoes", mech = "Kick Vicious Echoes", when = "Phase 3, Shriekers", n = 3, kind = "order", d = "N", fill = "cap:interrupt" },
    { id = "poison", mech = "Poison dispels", when = "all fight", n = 3, kind = "players", d = "H", fill = "cap:dispel_poison" },
    { id = "lust", mech = "Bloodlust", when = "first damage amp, Phase 1", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
    { id = "gate", mech = "Demonic Gateway", when = "return in Phase 2", n = 1, kind = "players", d = "H", fill = "class:WARLOCK" },
  },
}

B.kithix = {
  name = "Kith'ix", short = "Kith'ix", instance = "kithix",
  src = "Mythic Trap (Normal, Heroic); wow.gg (October 14)",
  summary = "Two phases beside Liadrin. Collect light before every Extinguish; Phase 2 is a one-minute race against Eightfold Eclipse.",
  dangers = {
    { d = "N", t = "No light mote when Extinguish lands: a one-shot." },
    { d = "N", t = "Negation not removed at a Null Gate (the tank dies)." },
    { d = "N", t = "Phase 2 running past one minute (Eightfold Eclipse wipes the raid)." },
  },
  phases = {
    { name = "Phase 1", items = {
      { n = "Extinguish", tag = "Light", d = "N", who = "ALL", t = "Collect a light mote before it lands; anyone without light dies.", deadly = true },
      { n = "Voidswarm", tag = "Positioning", d = "N", who = "TANK", t = "Split the boss and the adds between the tanks." },
      { n = "Venomous Hulk", tag = "Add", d = "N", who = "ALL", t = "Dodge the frontal cone." },
      { n = "Voidweaver", tag = "Add", d = "N", who = "HEALER", t = "Heal through the beams on random players." },
      { n = "Bomber Beetle", tag = "Add", d = "N", who = "ALL", t = "Blow up beetles slowly: each one stacks a DoT." },
      { n = "Overwhelming Fear", tag = "Dispel", d = "N", who = "ALL", t = "If you're feared, move out; healers dispel slowly (dispel type not confirmed)." },
      { n = "Twisted Appendage", tag = "Dodge", d = "N", who = "ALL", t = "Dodge the circles; the tank takes the tank circle out of the raid." },
      { n = "Dark Devastation", tag = "Tankbuster", d = "N", who = "TANK", t = "Tankbuster circle (physical and shadow vulnerability): swap after each cast (wow.gg)." },
      { n = "Suffocating Darkness", tag = "Safe space", d = "N", who = "ALL", t = "Stay in the safe space; stepping into the darkness suffocates you." },
      { n = "Abyssal Grasp", tag = "Absorb", d = "N", who = "HEALER", t = "Heal through the absorb on random players." },
      { n = "Divine Radiance", tag = "Liadrin", d = "N", who = "ALL", t = "Liadrin's bulwarks get smaller each time." },
      { n = "Incubation", tag = "Eggs", d = "H", who = "DAMAGER", t = "Hulks and Voidweavers drop Mindstinger eggs: kill them before they hatch." },
      { n = "Voidscar", tag = "Dodge", d = "H", who = "ALL", t = "Dark Devastation leaves a Voidscar that knocks back and hurts anyone who touches it." },
      { n = "Eclipse Fragment", tag = "Soak", d = "H", who = "ALL", t = "Voidscars spawn fragments that drift toward Liadrin: soak them; tanks help intercept." },
    } },
    { name = "Phase 2", items = {
      { n = "Eightfold Eclipse", tag = "Enrage", d = "N", who = "ALL", t = "Kill the boss within one minute; the eighth eclipse wipes the raid.", deadly = true },
      { n = "Null Gate", tag = "Dodge", d = "N", who = "ALL", t = "Dodge the Nullshards (six hits kill); if you're marked, move away from the gates." },
      { n = "Negation", tag = "Tank", d = "N", who = "TANK", t = "Collide with a Null Gate to remove it (100% physical vulnerability; death if it isn't removed).", deadly = true },
      { n = "Last Light", tag = "Buff", d = "N", who = "ALL", t = "50% more damage, 100% more healing: burn." },
    } },
  },
  needs = {
    { kind = "cap", key = "dispel_magic", d = "N", min = 2, sev = "rec", label = "Fear dispel", note = "Overwhelming Fear; type not confirmed (Magic assumed)", unconfirmed = true },
  },
  lust = { N = "Phase 2, the one-minute race (wow.gg: the final phase)" },
  prepull = {
    { d = "N", t = "One tank on the boss, one on the adds." },
    { d = "N", t = "Everyone knows: light mote before every Extinguish." },
    { d = "H", t = "Who soaks Eclipse Fragments (tanks help)." },
  },
  calls = {
    { w = "Extinguish", d = "N", t = "Grab light NOW." },
    { w = "Fear", d = "N", t = "Feared players out; dispel slowly." },
    { w = "Phase 2", d = "N", t = "Bloodlust. One minute: everything." },
    { w = "Fragments", d = "H", t = "Soak the fragments before they reach Liadrin." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "boss / adds; swap on Dark Devastation", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "fear", mech = "Fear dispels", when = "Phase 1", n = 2, kind = "players", d = "N", fill = "role:HEALER" },
    { id = "frag", mech = "Eclipse Fragment soakers", when = "each Suffocating Darkness", n = 5, kind = "group", marker = "star", d = "H", fill = "ranged" },
    { id = "lust", mech = "Bloodlust", when = "Phase 2", n = 1, kind = "players", d = "N", fill = "cap:bloodlust" },
  },
}

B.nymrissa = {
  name = "Nymrissa Wavecaller", short = "Nymrissa", instance = "grotto",
  src = "Mythic Trap (Normal, Heroic); Method.gg (Heroic and Mythic, August 19); Blizzard's Lairs post",
  summary = "A Lair boss underwater on the Coiled Isle (an aquatic mount helps). Kill the Shorerunners before they reach the bubble, find the gap in the whirlpools, soak the frost orbs, and kill her before Unending Tides at six minutes.",
  dangers = {
    { d = "N", t = "Shorerunners reaching the Alluring Bubble (they empower and the pop hits everyone)." },
    { d = "N", t = "Standing in a whirlpool (massive damage)." },
    { d = "H", t = "Frost orbs left unsoaked for 30 seconds (they explode)." },
  },
  phases = {
    { name = "One phase", items = {
      { n = "Alluring Bubble", tag = "Adds", d = "N", who = "DAMAGER", t = "Kill the Shorerunners before they reach the bubble; ranged take single spawns, crowd control stops them (Method.gg)." },
      { n = "Swirling Whirlpools", tag = "Avoid", d = "N", who = "ALL", t = "Find the safe gap with no whirlpool; the bubble's pop hits everyone and knocks back." },
      { n = "Chilling Frost", tag = "Soak", d = "N", who = "ALL", t = "Soak the orbs (each one is a DoT and a 15% slow)." },
      { n = "Abyssal Rain", tag = "Raid damage", d = "N", who = "HEALER", t = "A healing check: don't let it overlap with the bubble's pop (Method.gg)." },
      { n = "Iceblade Flurry", tag = "Tankbuster", d = "N", who = "TANK", t = "Defensives (a heavy DoT and 20% more damage from the next one): trade it." },
      { n = "Pop!", tag = "Knockback", d = "N", who = "ALL", t = "A raid hit and a knockback toward the water: a healer cooldown, and a Warlock's gate cancels the knock (Method.gg)." },
      { n = "Unending Tides", tag = "Enrage", d = "N", who = "ALL", t = "Kill her before six minutes.", deadly = true },
      { n = "Chilling Frost", tag = "Soak", d = "H", who = "ALL", t = "Orbs explode if they aren't soaked within 30 seconds, and the debuff stacks: tanks and mobile or immune players soak." },
      { n = "Abyssal Rain", tag = "Raid damage", d = "H", who = "HEALER", t = "Each cast raises her damage by 5%, stacking." },
      { n = "Bubblefin Frostscale", tag = "Add", d = "M", who = "DAMAGER", t = "Kill it first; stagger the Frost Burst soaks.", src = "Method.gg Mythic" },
    } },
  },
  needs = {
    { kind = "range", key = "ranged", d = "N", min = 4, sev = "rec", label = "Ranged for Shorerunners", note = "kill each add before it reaches the bubble" },
    { kind = "cap", key = "stop", d = "N", min = 2, sev = "rec", label = "Crowd control", note = "stops a Shorerunner (stuns, roots, slows)" },
    { kind = "class", key = "WARLOCK", d = "N", min = 1, sev = "rec", label = "Gateway for Pop!", note = "cancels the knockback (else a healer cooldown each Pop!)" },
  },
  lust = { N = "The guides read give no timing: your call" },
  prepull = {
    { d = "N", t = "Ranged on the Shorerunners; who crowd-controls them." },
    { d = "H", t = "Orb soakers: tanks and mobile or immune players." },
  },
  calls = {
    { w = "Shorerunners", d = "N", t = "Ranged on the adds. Don't let them reach the bubble." },
    { w = "Whirlpools", d = "N", t = "Everyone into the gap." },
    { w = "Pop!", d = "N", t = "Healer cooldown. Face away from the water." },
    { w = "Abyssal Rain", d = "N", t = "Healing check: keep it off the Pop!." },
    { w = "Orbs", d = "H", t = "Soak the orbs within 30 seconds." },
  },
  plan = {
    { id = "tanks", mech = "Tanks", when = "trade Iceblade Flurry", n = 2, kind = "players", d = "N", fill = "role:TANK" },
    { id = "adds", mech = "Shorerunner killers", when = "every spawn", n = 4, kind = "group", marker = "skull", d = "N", fill = "ranged" },
    { id = "cc", mech = "Crowd control on Shorerunners", when = "every spawn", n = 2, kind = "players", marker = "moon", d = "N", fill = "cap:stop" },
    { id = "orbs", mech = "Frost orb soakers", when = "each Chilling Frost", n = 3, kind = "group", marker = "star", d = "H", fill = "role:TANK" },
    { id = "gate", mech = "Demonic Gateway", when = "each Pop!", n = 1, kind = "players", d = "N", fill = "class:WARLOCK" },
  },
}

-- Plain-text marker names, the game's raid target icon index, and the chat code.
D.MARKERS = {
  { key = "star", label = "Star", i = 1 }, { key = "circle", label = "Circle", i = 2 },
  { key = "diamond", label = "Diamond", i = 3 }, { key = "triangle", label = "Triangle", i = 4 },
  { key = "moon", label = "Moon", i = 5 }, { key = "square", label = "Square", i = 6 },
  { key = "cross", label = "Cross", i = 7 }, { key = "skull", label = "Skull", i = 8 },
}
D.MARKER = {}
for _, m in ipairs(D.MARKERS) do D.MARKER[m.key] = m end

-- Check the data's shape (tests and /ens verify call this). Returns a list of problems.
local ROLES = { ALL = true, TANK = true, HEALER = true, DAMAGER = true, MELEE = true, RANGED = true }
local DATA_DIFFS = { N = true, H = true, M = true }
function D:Validate(UD)
  local bad = {}
  local function Bad(s) bad[#bad + 1] = s end
  local seen = {}
  for _, inst in ipairs(self.INSTANCES) do
    for _, d in ipairs(inst.diffs) do if not self.DIFFS[d] then Bad(inst.key .. ": unknown difficulty " .. d) end end
    for _, bk in ipairs(inst.bosses) do
      local b = self.BOSSES[bk]
      if not b then Bad(inst.key .. ": no boss " .. bk)
      elseif b.instance ~= inst.key then Bad(bk .. ": instance is " .. tostring(b.instance))
      end
      seen[bk] = true
    end
    for _, g in ipairs(inst.orderGroups or {}) do
      for _, pos in ipairs(g) do if not inst.bosses[pos] then Bad(inst.key .. ": order group position " .. pos) end end
    end
  end
  for bk, b in pairs(self.BOSSES) do
    if not seen[bk] then Bad(bk .. ": in no instance") end
    if type(b.name) ~= "string" or type(b.summary) ~= "string" or type(b.src) ~= "string" then Bad(bk .. ": name, summary or src missing") end
    if not (b.lust and b.lust.N) then Bad(bk .. ": no Normal Bloodlust note") end
    for _, ph in ipairs(b.phases or {}) do
      for _, it in ipairs(ph.items or {}) do
        if not (it.n and it.tag and it.t) then Bad(bk .. ": item missing a field") end
        if not DATA_DIFFS[it.d] then Bad(bk .. " " .. tostring(it.n) .. ": difficulty " .. tostring(it.d)) end
        if not ROLES[it.who] then Bad(bk .. " " .. tostring(it.n) .. ": role " .. tostring(it.who)) end
      end
    end
    for _, n in ipairs(b.needs or {}) do
      if not DATA_DIFFS[n.d] then Bad(bk .. " need difficulty " .. tostring(n.d)) end
      if n.kind == "cap" and UD and not UD:IsCap(n.key) then Bad(bk .. " need cap " .. tostring(n.key)) end
      if n.kind == "class" and UD then
        for cls in tostring(n.key):gmatch("[^,]+") do if not UD.classes[cls] then Bad(bk .. " need class " .. cls) end end
      end
    end
    local ids = {}
    for _, r in ipairs(b.plan or {}) do
      if ids[r.id] then Bad(bk .. " plan row id twice: " .. r.id) end
      ids[r.id] = true
      if not DATA_DIFFS[r.d] then Bad(bk .. " plan " .. r.id .. " difficulty") end
      if r.marker and not self.MARKER[r.marker] then Bad(bk .. " plan " .. r.id .. " marker " .. r.marker) end
      if not R.ValidFill(r.fill) then Bad(bk .. " plan " .. r.id .. " fill " .. tostring(r.fill)) end
      if r.fill and r.fill:match("^cap:") and UD and not UD:IsCap(r.fill:sub(5)) then Bad(bk .. " plan " .. r.id .. " cap") end
    end
    for _, c in ipairs(b.calls or {}) do
      if not DATA_DIFFS[c.d] then Bad(bk .. " call difficulty") end
      for code in c.t:gmatch("{(%a+)}") do if not self.MARKER[code] then Bad(bk .. " call marker {" .. code .. "}") end end
    end
  end
  return bad
end
