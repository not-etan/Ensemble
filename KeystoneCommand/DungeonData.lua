-- Keystone Command / DungeonData.lua  (Feature 5 data)
-- HAND-MAINTAINED. Update by editing this file; ships with normal addon releases.
-- Re-check after every hotfix / M+ tuning pass.
--
-- Requirement fields
--   id            unique string
--   need          capability key from UtilityDatabase (UD.CAPS)
--   alt           optional list of other capability keys that also satisfy it
--   severity      "critical" | "high" | "medium" | "low"
--   minProviders  how many distinct group members should be able to answer it
--   source        the ability that creates the need, and where it happens
--   note          optional handling note
--   category      optional override: "interrupts" | "dispels" | "stops" | "tank" | "other"
--                 (default: derived from the `need` key's category in UD.CAPS)
--   confidence    "verified" | "needs_verification"
--
-- Sources: the five Midnight dungeons started from the seed data supplied with the build
-- spec (Method.gg / Icy Veins / Wowhead, mid-August 2026). All eight dungeons were then
-- checked against Method.gg's Season 2 dungeon guides and per-dungeon ability trackers
-- (Interrupt / Stop / Freedom tags, spell IDs). Entries whose handling those pages state are
-- "verified"; anything inferred (e.g. an unstated dispel type) is "needs_verification".
--
-- Hotfix cross-check (October 12, 2026): every Blizzard hotfix post from 12.1.0's release
-- (August 11) through October 6, read via Wowhead's blue tracker / Blizzard's hotfix page
-- and Icy Veins' weekly summaries. Changes that touch this file:
--   Aug 18  Kings' Rest Dark Revelation prefers non-tanks; Murder Row forces 655
--   Aug 21  Altar of Fangs: High Evolutionist's Envenom 3s / Mass Envenom 3.5s casts
--   Aug 25  Kings' Rest: Risen Hexer casts Shadow Bolt (was Shadowfrost Bolt); Phantom Hex
--           Priest's spells are Shadow (was Nature). Blinding Vale: Potatoad Matriarch's
--           Toxic Spew initial damage -50%.
--   Sep 22  Blade of the Altar's Laced Edge and Shrouded Fang's Slither Strike can no longer
--           be cast while crowd controlled (bug fix; CC now stops them as intended).
-- Everything else in those posts was damage/health tuning, mob counts or bug fixes with no
-- effect on which utility a dungeon asks for. No PvE class utility changed in that window.
--
-- Patch 12.1.5 (October 13, 2026): Blizzard's 12.1.5 patch notes, the Mythic+ dungeon tuning
-- that went live with it (Wowhead, "Mythic Dungeon Tuning with Weekly Reset"), and the hotfix
-- thread through October 13 (no posts after October 6). Changes that touch this file:
--   Oct 13  Ruby Life Pools: Living Bomb (Primalist Cinderweaver, Blazebound Destroyer) is now
--           a Magic effect and can be dispelled; dispelling it prevents the explosion. New
--           RLP_LIVING_BOMB (Wowhead's 12.1.5 Ruby Life Pools notes; confirmed by the author).
-- Also October 13 (author's in-game checks and Method.gg): Kings' Rest's Shadow Bolt still
-- leaves a Magic slow (KR_SHADOW_BOLT confirmed, spell ID added); Murder Row's Seduction is
-- cast by the Seductive Sayaad, Fel Missiles by the Felonious Mage (a channel) and Heartstop
-- Poison by the Street Sneak (all were credited to the Row Hooligan).
-- The rest of the tuning pass (Altar of Fangs, Murder Row, Ruby Life Pools, Temple of
-- Sethraliss, The Blinding Vale, Voidscar Arena) is damage, health, cooldown and duration
-- numbers that no note or boss card quotes. Murder Row's Murder in a Row safe-spot fix is a
-- bug fix. Class changes in 12.1.5 touch no tracked utility (Marksmanship's Unload removal
-- and Merithra's Blessing's shorter duration aren't tracked).

local _, ns = ...

local DD = { list = {}, order = {} }
ns.Dungeons = DD

-- How current the game data is: shown in the Dungeons tab, Settings > Data, /kc report and
-- /kc verify. Update both with every data pass (SEASON_UPDATE.md, Step 2: Hotfixes).
DD.DATA_PATCH = "12.1.5"
DD.DATA_CHECKED = "October 13, 2026"   -- newest hotfix post the data was checked against
function DD:FreshnessText()
  return "Data for patch " .. self.DATA_PATCH .. ", checked against Blizzard's hotfixes through " .. self.DATA_CHECKED .. "."
end

---------------------------------------------------------------------------
-- TUNABLE HEURISTICS. These are judgment calls, not published facts -- adjust freely.
---------------------------------------------------------------------------
DD.HEURISTICS = {
  -- A dungeon with at least this many interrupt-flagged requirements is "kick-heavy".
  KICK_HEAVY_REQUIREMENTS = 5,
  -- Short-cooldown interrupts a group should bring into a kick-heavy dungeon.
  KICKS_WANTED_KICK_HEAVY = 3,
  -- ...and into any other dungeon.
  KICKS_WANTED_DEFAULT = 2,
  -- If the only provider of a critical/high requirement is "soft" (talent, pet, long CD,
  -- conditional, unconfirmed, or a spec-pending member), report it as thin.
  SOFT_SOLE_PROVIDER_IS_THIN = true,
  -- If a CRITICAL requirement has exactly one provider of any kind, report it as thin
  -- (one death / one missed cast and it's uncovered).
  CRITICAL_SOLE_PROVIDER_IS_THIN = true,

  -- Applicant fit (Applicants tab / Group Finder panel) ----------------------------
  -- Keystone level from which thin coverage is weighted as heavily as a missing one
  -- (less slack for a single kicker/dispeller dying or being out of range).
  HIGH_KEY_LEVEL = 12,
  -- Fit score = a PICK rating: where this player's gap reduction sits between the weakest
  -- (0) and the best (100) spec of the same role for this slot. Rating bands on that score
  -- (tuned from the measurement report, `python3 tests/run_tests.py --fit`):
  -- 1.2.0 report (768 ratings): Great 15%, Good 25%, Fair 33%, Poor 27%. Covering a missing
  -- need usually lands Fair or better; Poor is left for picks that add next to nothing.
  -- 1.2.1 report (1,024 ratings, Temple of Sethraliss added): Great 15%, Good 25%, Fair 31%, Poor 29%.
  FIT_GREAT = 80,
  FIT_GOOD = 45,
  FIT_FAIR = 15,
  -- "No real difference": when the best and weakest pick for the slot are less than this many
  -- penalty points apart (about two low-severity gaps), everyone gets FIT_FLAT_SCORE and the
  -- card says to decide on experience.
  FIT_FLAT_SPREAD = 5,
  FIT_FLAT_SCORE = 70,
  -- Critical-gap rule (1.2.1). A FULL close (a critical need leaves MISSING through a solid
  -- source of theirs) never rates below anyone who doesn't fully close one. A PARTIAL close
  -- (only through a weak source: a talent, pet, long cooldown, conditional, unconfirmed or
  -- spec-pending source) still counts, but only up to this share of the way from the weakest
  -- pick to the best pick that closes nothing (0.5 = halfway).
  FIT_CRIT_PARTIAL_SHARE = 0.5,
  -- Applicant comparison: fit scores closer than this count as "similar".
  COMPARE_CLOSE = 10,

  -- Raid buff synergy: points per member who fully benefits from a buff the group has
  -- (DPS count 1, tanks/healers 0.5, partial benefit halves it). Subtracted from the gap
  -- penalty, so it nudges suggestions and applicant ratings toward groups whose buffs
  -- match their damage profile. Kept small so real utility gaps always matter more.
  BUFF_SYNERGY_POINTS = 1.5,

  -- Applicant experience: how much an applicant's best run of THIS dungeon (Blizzard's own
  -- per-dungeon score) counts next to their utility fit. Less at low keys, where a newer
  -- player is a fine pick and the point is to learn; more where a missed mechanic ends the key.
  EXPERIENCE_WEIGHT_LOW = 0.10,    -- keys up to +5
  EXPERIENCE_WEIGHT_MID = 0.20,    -- +6 to +9
  EXPERIENCE_WEIGHT_HIGH = 0.30,   -- +10 and up
  LOW_KEY_LEVEL = 9,               -- keys up to here get the "low key" host coaching
}

-- Spell IDs for dungeon abilities named in requirement `source` text: used for icons and
-- tooltips. Taken from Method.gg's Season 2 guides (Wowhead links). Names are global; when
-- two dungeons use the same name for different spells, the dungeon's own `spellIds` table
-- overrides it (e.g. Lightning Bolt in Den of Nalorakk vs Temple of Sethraliss). An ability missing here
-- still shows color-coded, with a "?" icon and a name-only tooltip.
DD.SPELL_IDS = {
  -- Kings' Rest
  ["Hex Volley"] = 269972, ["Unholy Mending"] = 270901, ["Bind Soul"] = 270920,
  ["Soul Bolt"] = 1294972, ["Wretched Discharge"] = 267763, ["Poison Nova"] = 267273, ["Deathly Roar"] = 269369,
  ["Spectral Bolt"] = 1295125, ["Hex"] = 270492, ["Bound by Shadow"] = 269935, ["Captain's Bulwark"] = 1296671,
  ["Ancestral Fury"] = 269976, ["Bestial Berserk"] = 1297763, ["Frost Shock"] = 270499,
  ["Serpent Strike"] = 1306763, ["Embalming Fluid"] = 271563, ["Mortal Bleed"] = 1297918,
  ["Sudden Rupture"] = 1297781, ["Bloodthirsty Axe"] = 1301851, ["Severing Axe"] = 266231,
  ["Soul Crush"] = 1302028, ["Blade Combo"] = 268586, ["Savage Maul"] = 1303490,
  ["Shadow Bolt"] = 1258431,   -- Wowhead; 1294815 was the old Shadowfrost Bolt (renamed Aug 25)
  -- Temple of Sethraliss
  ["Imbued Conduction"] = 1296052, ["Lightning Bolt"] = 1291262, ["Flame Shock"] = 268013,
  ["Essence Disruption"] = 1303535, ["Arrow Barrage"] = 1308116, ["Poison Spit"] = 267027,
  ["Venom Bolt"] = 1310683, ["Cytotoxin"] = 1308148, ["Poisoned Cheap Shot"] = 1308100,
  ["Addle Mind"] = 1314082, ["Accumulate Charge"] = 1293464, ["Serrated Charge"] = 1291399,
  ["Sunder Slam"] = 1291468, ["Lightning Bite"] = 1290797, ["Venomous Slash"] = 1308546,
  ["Tainted Strike"] = 1303446,
  -- Ruby Life Pools
  ["Ice Shield"] = 372743, ["Frigid Shard"] = 372808, ["Cinderbolt"] = 384194, ["Blaze Volley"] = 373017,
  ["Frostbolt"] = 371984, ["Fiery Blast"] = 1305955, ["Thunder Blast"] = 392576, ["Storm Bolt"] = 385310,
  ["Flaming Barrage"] = 385536, ["Stormslam"] = 381512, ["Cold Claws"] = 1305234,
  ["Stormcloud Barrier"] = 391031, ["Blaze of Glory"] = 373972, ["Rolling Thunder"] = 392641,
  ["Ice Bulwark"] = 372988, ["Tempest Stormshield"] = 1310355, ["Living Bomb"] = 373693,
  -- Altar of Fangs
  ["Paralyzing Shots"] = 1294569, ["Envenom"] = 1307571, ["Corrosive Fangs"] = 1294845,
  ["Toxic Atrophy"] = 1310358, ["Regurgitate"] = 1296058, ["Ravenous Claws"] = 1306338,
  -- Murder Row
  ["Fel Missiles"] = 1216570, ["Seduction"] = 1201554, ["Heartstop Poison"] = 1216590,
  ["Corroding Spittle"] = 1217633, ["Mirror Images"] = 1264095, ["Felfire Burst"] = 1223204,
  ["Doom Bolt"] = 1258420, ["Chaos Bolt"] = 474375,
  -- Den of Nalorakk
  ["Starvation Effigy"] = 1238760, ["Toxic Spores"] = 1234846, ["Winter's Shroud"] = 1235829,
  ["Earth Bolt"] = 1241214, ["Glacial Torment"] = 1235548,
  -- The Blinding Vale
  ["Toxic Spew"] = 1250937, ["Warden's Wrath"] = 1239821, ["Lightspore Shot"] = 1247669,
  ["Light Bolt"] = 1238063, ["Seed Shot"] = 1238232, ["Spore Spines"] = 1238084,
  -- Voidscar Arena
  ["Shadowbolt Volley"] = 1299938, ["Corrosive Essence"] = 1289265, ["Lava Bolt"] = 1228176,
  ["Melt Armor"] = 1250043,
  ["Demoralizing Shout"] = 1298899, ["Violent Sand"] = 1249621, ["Mad Shriek"] = 1233398,
  ["Mending Void"] = 1310324, ["Bolster"] = 1310319, ["Feral Rage"] = 1249661, ["Bloodsurge"] = 1254826,
  ["Savage Leap"] = 1267894, ["Rip And Slice"] = 1311778, ["Shred Defense"] = 1233535, ["Head Bash"] = 1245186,
  ["Brutalize"] = 1300243, ["Gravitic Orbs"] = 1223298, ["Shell Guard"] = 1250021,
  -- (second pass) Altar of Fangs
  ["Piercing Hiss"] = 1294557, ["Mass Envenom"] = 1307567, ["Evolve"] = 1306385, ["Dismember"] = 1306911,
  ["Noxious Spray"] = 1294934,
  -- Murder Row
  ["Fel Crazed"] = 1229433, ["Health Funnel"] = 1214980, ["Back to Work!"] = 1216970, ["Fel Rage"] = 1214922,
  ["Cutpurse"] = 1216300, ["Glaive Toss"] = 1295035, ["Sharp Nail"] = 1311136, ["Flay"] = 1295427,
  ["Shield Bash"] = 1216529, ["Curse of Doom"] = 1217973, ["Blade Dance"] = 1302007,
  -- Den of Nalorakk
  ["Healing Breeze"] = 1297696, ["Frigid Roar"] = 1309919, ["Arc Lightning"] = 1297778, ["Scavenge"] = 1239352,
  ["Cryo Surge"] = 1239860, ["Glacial Tomb"] = 1241464, ["Rimeshatter"] = 1263590, ["Mother's Wrath"] = 1238053, ["Bestial Wrath"] = 1246865,
  ["Razor Dive"] = 1238439, ["Shred Armor"] = 1311695, ["Frostbite"] = 1265402,
  -- The Blinding Vale
  ["Light Bolt Volley"] = 1301834, ["Disorienting Screech"] = 1238294, ["Call The Grove"] = 1267029,
  ["Hunting Leap"] = 270500, ["Thornblade"] = 1238076, ["Grievous Gash"] = 1242135,
  ["Earthrupture Strike"] = 1237855, ["Spouting Floret"] = 1271385, ["Potad-Toss"] = 1250829, ["Bloodthorn Roots"] = 1236658,
  -- Ruby Life Pools
  ["Steel Barrage"] = 372047, ["Crushing Smash"] = 372730, ["Searing Blows"] = 372858, ["Fire Maw"] = 392394,
  ["Thunder Jaw"] = 392395, ["Inferno"] = 373692, ["Molten Blood"] = 392569, ["Frost Overload"] = 373680,
  -- Kings' Rest
  ["Lucre's Call"] = 265923, ["Serpentine Gust"] = 265781, ["Gilded Destruction"] = 1303267,
  -- Temple of Sethraliss
  ["A Knot of Snakes"] = 1290031, ["Lightning Spire"] = 274006, ["Caustic Stomp"] = 1303486,
}

DD.SEVERITY_RANK = { critical = 1, high = 2, medium = 3, low = 4 }
DD.CATEGORIES = {
  { key = "interrupts", label = "Interrupts" },
  { key = "dispels",    label = "Dispels" },
  { key = "stops",      label = "Stops / CC" },
  { key = "tank",       label = "Tank mitigation" },
  { key = "other",      label = "Other" },
  { key = "affixes",    label = "Weekly affixes" },
}

local V, NV = "verified", "needs_verification"
-- Mechanic notes ("what it does; what to do") come from Method.gg's Season 2 dungeon guides,
-- with Icy Veins as a fallback (October 2026). Fel Crazed, Poison Nova, Deathly Roar and
-- Blaze Volley have no published effect description, so their notes only say what to do.

local function add(key, def)
  def.key = key
  for _, req in ipairs(def.requirements) do req.dungeon = key end
  DD.list[key] = def
  table.insert(DD.order, key)
end

---------------------------------------------------------------------------
-- Altar of Fangs (new in 12.1)
---------------------------------------------------------------------------
add("AltarOfFangs", {
  name = "Altar of Fangs",
  bosses = { "Rav'i", "The Writhing Coil", "Zul'jan" },
  requirements = {
    { id = "AOF_PARALYZE", need = "dispel_magic", alt = { "freedom" }, severity = "high", minProviders = 1,
      source = "Paralyzing Shots (Twinfang Harrower, before boss 1)",
      note = "Debuffs two players; Magic dispel OR a freedom effect removes it.", confidence = V },
    { id = "AOF_REGURGITATE", need = "dispel_disease", alt = { "freedom" }, severity = "medium", minProviders = 1,
      source = "Regurgitate (Rav'i, anyone the waves hit)",
      note = "Waves at a random player; dodge them, and Disease dispel anyone hit.", confidence = V },
    { id = "AOF_ENVENOM_INT", need = "interrupt", severity = "high", minProviders = 2,
      source = "Envenom (High Evolutionist; trash before The Writhing Coil and Zul'jan)",
      note = "Interrupt as many casts as possible; spare kicks go here.", confidence = V },
    { id = "AOF_ENVENOM_POISON", note = "Random-target poison DoT; kick what you can and Poison dispel the rest.", need = "dispel_poison", severity = "high", minProviders = 1,
      source = "Envenom DoTs (High Evolutionist)", confidence = V },
    { id = "AOF_CORROSIVE_FANGS", need = "external_defensive", category = "tank", severity = "medium", minProviders = 1,
      source = "Corrosive Fangs (Rattling Writhe), Dismember (Ritual Chieftain), Noxious Spray (Ascendant Serpent)",
      note = "Tank defensives; an external is the backup.", confidence = V },
    { id = "AOF_TOXIC_ATROPHY", need = "interrupt", severity = "high", minProviders = 2,
      source = "Toxic Atrophy (The Writhing Coil)",
      note = "Interruptible (Method ability tracker). One carry guide reports needing three interrupts in a row.",
      confidence = V },
    { id = "AOF_FREEDOM", need = "freedom", severity = "medium", minProviders = 1,
      source = "Regurgitate (Rav'i), Toxic Atrophy (The Writhing Coil)", note = "Freedom effects remove the CC.",
      confidence = V },
    { id = "AOF_ENRAGE", need = "soothe", alt = { "stop" }, severity = "medium", minProviders = 1,
      source = "Ravenous Claws (Ravenous Descendant stacks)", note = "Stacking Ravenous enrage; Soothe or CC resets the stacks.", confidence = V },
    { id = "AOF_PIERCING_HISS", need = "interrupt", severity = "high", minProviders = 2,
      source = "Piercing Hiss (Primal Serpent)", note = "Interrupt every cast.", confidence = V },
    { id = "AOF_MASS_ENVENOM", need = "interrupt", severity = "high", minProviders = 2,
      source = "Mass Envenom (Ula'tek's Chosen; High Evolutionist after Evolve)", note = "Interrupt every cast.", confidence = V },
    { id = "AOF_EVOLVE", need = "stop", severity = "high", minProviders = 1,
      source = "Evolve (High Evolutionist channel)", note = "CC to stop the channel; it turns Envenom into Mass Envenom.", confidence = V },
    { id = "AOF_HATCHLINGS", need = "aoe_stop", alt = { "root" }, severity = "low", minProviders = 1,
      source = "Hatchling packs", note = "CC and slows to lock them down.", confidence = V },
  },
})

---------------------------------------------------------------------------
-- Murder Row
---------------------------------------------------------------------------
add("MurderRow", {
  name = "Murder Row",
  bosses = { "Kystia Manaheart", "Zaen Bladesorrow", "Xathuux the Annihilator", "Lithiel Cinderfury" },
  requirements = {
    { id = "MR_SEDUCTION", need = "interrupt", alt = { "stop" }, severity = "high", minProviders = 2,
      source = "Seduction (Seductive Sayaad channel on a random player)", note = "Interrupt or CC.", confidence = V },
    { id = "MR_FEL_MISSILES", need = "interrupt", alt = { "stop" }, severity = "high", minProviders = 2,
      source = "Fel Missiles (Felonious Mage channel)", note = "Interrupt or CC the channel.", confidence = V },
    { id = "MR_HEARTSTOP", need = "dispel_poison", alt = { "external_defensive" }, severity = "medium", minProviders = 1,
      source = "Heartstop Poison (Street Sneak, on the tank)", note = "Poison dispel or defensives.", confidence = V },
    { id = "MR_CORRODING", need = "dispel_magic", severity = "medium", minProviders = 1,
      source = "Corroding Spittle (random player)", note = "Magic dispel, or the target uses a personal defensive.",
      confidence = V },
    { id = "MR_MIRROR_IMAGES", need = "interrupt", alt = { "aoe_stop" }, severity = "high", minProviders = 2,
      source = "Mirror Images (boss; five spawn periodically)", note = "Interrupts or CC while they are burned down.",
      confidence = V },
    { id = "MR_SPARE", need = "interrupt", severity = "medium", minProviders = 3,
      source = "Felfire Burst, Doom Bolt, Chaos Bolt (Lithiel Cinderfury)", note = "Spare interrupts.", confidence = V },
    { id = "MR_FEL_CRAZED", note = "Buff on the Felonious Mage; purge it off if you have a purge.", need = "purge", severity = "medium", minProviders = 1,
      source = "Fel Crazed (Felonious Mage)", confidence = V },
    { id = "MR_HEALTH_FUNNEL", need = "interrupt", alt = { "stop" }, severity = "medium", minProviders = 1,
      source = "Health Funnel (Fel Invoker)", note = "Interrupt or CC.", confidence = V },
    { id = "MR_SOOTHE", need = "soothe", severity = "medium", minProviders = 1,
      source = "Back to Work! (Keen Taskmaster), Fel Rage (Wrathguard Flayer)",
      note = "Fel Rage can also be interrupted.", confidence = V },
    { id = "MR_BLEEDS", need = "dispel_bleed", alt = { "external_defensive" }, severity = "medium", minProviders = 1,
      source = "Cutpurse, Glaive Toss, Sharp Nail, Flay", note = "Bleed cleanse or defensives.", confidence = V },
    { id = "MR_TANK", note = "Shield Bash stacks on the tank and Glaive Toss cleaves; defensive as stacks climb.", need = "external_defensive", category = "tank", severity = "medium", minProviders = 1,
      source = "Shield Bash stacks, Glaive Toss (Bribed Guard / Captain)", confidence = V },
    { id = "MR_CURSE_OF_DOOM", need = "dispel_curse", severity = "medium", minProviders = 1,
      source = "Curse of Doom (Corrupted Warlock)", note = "Curse (confirmed on Wowhead).", confidence = V },
    { id = "MR_BLADE_DANCE", need = "group_defensive", severity = "low", minProviders = 1,
      source = "Blade Dance (Felmaster Lucsei)", note = "Group defensives or healing cooldowns.", confidence = V },
  },
})

---------------------------------------------------------------------------
-- Den of Nalorakk
---------------------------------------------------------------------------
add("DenOfNalorakk", {
  spellIds = { ["Lightning Bolt"] = 1246687 },   -- not Temple of Sethraliss' Lightning Bolt
  name = "Den of Nalorakk",
  bosses = { "The Hoardmonger", "Sentinel of Winter", "Nalorakk" },
  requirements = {
    { id = "DN_EFFIGY_CURSE", note = "The Effigy weakens the party with debuffs; kill it fast and Curse dispel.", need = "dispel_curse", severity = "high", minProviders = 1,
      source = "Starvation Effigy debuffs", confidence = V },
    { id = "DN_TOXIC_SPORES", note = "Each mushroom soak stacks a poison; Poison dispel soakers and spread the soaks.", need = "dispel_poison", severity = "high", minProviders = 1,
      source = "Toxic Spores (boss soak)", confidence = V },
    { id = "DN_WINTERS_SHROUD", need = "interrupt", severity = "high", minProviders = 2,
      source = "Winter's Shroud (adds)", note = "Keep interrupts on it.", confidence = V },
    { id = "DN_EARTH_BOLT", need = "interrupt", severity = "medium", minProviders = 2,
      source = "Earth Bolt", note = "Spare interrupts.", confidence = V },
    { id = "DN_GLACIAL_TORMENT", need = "dispel_magic", severity = "medium", minProviders = 1,
      source = "Glacial Torment DoT", note = "Magic (confirmed on Wowhead); dispel quickly.", confidence = V },
    { id = "DN_HEALING_BREEZE", need = "interrupt", severity = "high", minProviders = 2,
      source = "Healing Breeze (Earthwhisper Tender)", note = "Interrupt every cast; purge if one lands.", confidence = V },
    { id = "DN_BREEZE_PURGE", note = "Heals the caster and nearby mobs; kick every cast, purge any buff that lands.", need = "purge", severity = "low", minProviders = 1,
      source = "Healing Breeze (if a cast lands)", confidence = V },
    { id = "DN_FRIGID_ROAR", need = "interrupt", severity = "high", minProviders = 2,
      source = "Frigid Roar (Frigid Mauler)", note = "Interrupt every cast.", confidence = V },
    { id = "DN_ARC_LIGHTNING", need = "interrupt", severity = "high", minProviders = 2,
      source = "Arc Lightning (Stormbound Mystic)", note = "Interrupt every cast.", confidence = V },
    { id = "DN_SPARE", need = "interrupt", severity = "medium", minProviders = 2,
      source = "Scavenge (Keen-Eyed Striker), Lightning Bolt (Stormbound Mystic, Loa Speaker Nanea)",
      note = "Spare interrupts; Nanea needs a full kick rotation.", confidence = V },
    { id = "DN_CRYO_SURGE", note = "Debuff damages allies standing close; Magic dispel it or spread out.", need = "dispel_magic", severity = "medium", minProviders = 1,
      source = "Cryo Surge (Glacial Revenant)", confidence = V },
    { id = "DN_FREEDOM", need = "freedom", severity = "medium", minProviders = 1,
      source = "Glacial Tomb (Avatar of Determination), Frigid Roar (Frigid Mauler), Rimeshatter (Sentinel of Winter)",
      note = "Freedom effects remove these; Glacial Tomb can also be broken.", confidence = V },
    { id = "DN_SOOTHE", need = "soothe", alt = { "external_defensive" }, severity = "medium", minProviders = 1,
      source = "Mother's Wrath (Territorial Matriarch), Bestial Wrath (Bonded Beasttamer)",
      note = "Soothe; Mother's Wrath can be tanked with defensives.", confidence = V },
    { id = "DN_BLEED", note = "Stacking bleed on a random player; Bleed cleanse or defensive at high stacks.", need = "dispel_bleed", alt = { "external_defensive" }, severity = "low", minProviders = 1,
      source = "Razor Dive (Keen-Eyed Striker)", confidence = V },
    { id = "DN_TANK", note = "Shred Armor stacks and Frostbite adds frost damage to melee; tank needs defensives.", need = "external_defensive", category = "tank", severity = "medium", minProviders = 1,
      source = "Shred Armor stacks (Loyal Saberfang), Frostbite (Frostfang)", confidence = V },
  },
})

---------------------------------------------------------------------------
-- The Blinding Vale
---------------------------------------------------------------------------
add("TheBlindingVale", {
  spellIds = { ["Hunting Leap"] = 1303039 },      -- not Kings' Rest's Hunting Leap
  name = "The Blinding Vale",
  bosses = { "Lightblossom Trinity", "Ikuzz the Light Hunter", "Lightwarden Ruia", "Ziekket" },
  requirements = {
    { id = "BV_TOXIC_SPEW", note = "Poison DoT on the whole group; Poison dispel as many as you can.", need = "dispel_poison", severity = "high", minProviders = 1,
      source = "Toxic Spew (Potatoad Matriarch, mini-boss before Ziekket; group DoT)", confidence = V },
    { id = "BV_WARDENS_WRATH", note = "Hits the tank hard; keep interrupts on it to cut tank damage.", need = "interrupt", severity = "high", minProviders = 2,
      source = "Warden's Wrath (tank damage)", confidence = V },
    { id = "BV_LIGHTSPORE", need = "interrupt", alt = { "stop" }, severity = "high", minProviders = 2,
      source = "Lightspore Shot (adds)", note = "Interrupts and CC.", confidence = V },
    { id = "BV_SPARE", need = "interrupt", severity = "medium", minProviders = 2,
      source = "Light Bolt, Seed Shot", note = "Spare interrupts.", confidence = V },
    { id = "BV_SPORE_SPINES", need = "dispel_magic", alt = { "freedom", "external_defensive" }, category = "tank",
      severity = "medium", minProviders = 1,
      source = "Spore Spines (tank DoT)", note = "Defensives, freedom, or Magic dispel.", confidence = V },
    { id = "BV_LIGHT_BOLT_VOLLEY", need = "interrupt", severity = "high", minProviders = 2,
      source = "Light Bolt Volley (Radiant Spellsower)", note = "Interrupt every cast.", confidence = V },
    { id = "BV_SCREECH", need = "interrupt", severity = "high", minProviders = 2,
      source = "Disorienting Screech (Lightfeather Petalwing)", note = "Interrupt every cast.", confidence = V },
    { id = "BV_CALL_THE_GROVE", need = "stop", severity = "medium", minProviders = 1,
      source = "Call The Grove (Radiant Spellsower)", note = "CC to stop it waking Dormant Lashers.", confidence = V },
    { id = "BV_HUNTING_LEAP", note = "Channeled frontal on a random player; dodge it or CC to stop it.", need = "stop", severity = "low", minProviders = 1,
      source = "Hunting Leap (Thorny Saptor)", confidence = V },
    { id = "BV_POTAD_TOSS", need = "stop", severity = "low", minProviders = 1,
      source = "Potad-Toss (Newborn Potadpole)", note = "Stop it with CC.", confidence = V },
    { id = "BV_FREEDOM", need = "freedom", severity = "medium", minProviders = 1,
      source = "Bloodthorn Roots (Ikuzz the Light Hunter)", note = "Freedom effects remove the roots.", confidence = V },
    { id = "BV_BLEEDS", note = "Thornblade bleeds a random player, Grievous Gash the tank; Bleed cleanse them.", need = "dispel_bleed", alt = { "external_defensive" }, severity = "medium", minProviders = 1,
      source = "Thornblade (Underbrush Stalker), Grievous Gash (Luminous Thornmaw, tank)", confidence = V },
    { id = "BV_TANK", note = "Tank-buster that leaves a puddle; tank defensive and drop it away from the group.", need = "external_defensive", category = "tank", severity = "medium", minProviders = 1,
      source = "Earthrupture Strike (Virid Grovekeeper)", confidence = V },
    { id = "BV_SPOUTING_FLORET", need = "group_defensive", severity = "low", minProviders = 1,
      source = "Spouting Floret (Sporeblight Belcher)", note = "Healing cooldowns.", confidence = V },
  },
})

---------------------------------------------------------------------------
-- Voidscar Arena
---------------------------------------------------------------------------
add("VoidscarArena", {
  name = "Voidscar Arena",
  bosses = { "Taz'Rah", "Atroxus", "Charonus" },
  requirements = {
    { id = "VA_VOLLEY", need = "interrupt", severity = "critical", minProviders = 3,
      source = "Shadowbolt Volley", note = "Interrupt every cast.", confidence = V },
    { id = "VA_CORROSIVE", need = "dispel_poison", severity = "high", minProviders = 2,
      source = "Corrosive Essence (debuffs 3 players)",
      note = "Poison dispels or defensives; the right-hand path is recommended only with multiple Poison dispels.",
      confidence = V },
    { id = "VA_LAVA_BOLT", need = "interrupt", severity = "medium", minProviders = 2,
      source = "Lava Bolt", note = "Spare interrupts.", confidence = V },
    { id = "VA_MELT_ARMOR", need = "dispel_magic", alt = { "external_defensive" }, category = "tank",
      severity = "medium", minProviders = 1,
      source = "Melt Armor (stacking tank debuff)", note = "Magic dispel or defensives.", confidence = V },
    { id = "VA_DEMORALIZING_SHOUT", need = "interrupt", severity = "high", minProviders = 2,
      source = "Demoralizing Shout (Dominated Brawler)", note = "Interrupt every cast.", confidence = V },
    { id = "VA_VIOLENT_SAND", need = "interrupt", severity = "high", minProviders = 2,
      source = "Violent Sand (Angry Krolusk)", note = "Interrupt every cast.", confidence = V },
    { id = "VA_MAD_SHRIEK", need = "interrupt", severity = "high", minProviders = 2,
      source = "Mad Shriek (Killvore Screamer)", note = "Interrupt every cast. (Method's guide calls it Mass Shriek.)", confidence = V },
    { id = "VA_FREEDOM", need = "freedom", severity = "low", minProviders = 1,
      source = "Violent Sand (Angry Krolusk), Gravitic Orbs (Charonus)", note = "Freedom effects remove these.", confidence = V },
    { id = "VA_SHELL_GUARD", need = "stop", severity = "low", minProviders = 1,
      source = "Shell Guard (Protective Turtle)", note = "Stop it with CC.", confidence = V },
    { id = "VA_MENDING_VOID", need = "interrupt", alt = { "stop" }, severity = "high", minProviders = 1,
      source = "Mending Void (Voidminder)", note = "Interrupt or CC.", confidence = V },
    { id = "VA_SOOTHE", note = "These enrages raise the mobs' damage on the tank; Soothe them off.", need = "soothe", severity = "medium", minProviders = 1,
      source = "Bolster (Longtooth Tuskarr), Feral Rage (Raging Raptor), Bloodsurge (Dominated Brawler)", confidence = V },
    { id = "VA_BLEEDS", note = "Savage Leap bleeds a random player, Rip And Slice the tank; Bleed cleanse them.", need = "dispel_bleed", alt = { "external_defensive" }, severity = "medium", minProviders = 1,
      source = "Savage Leap (Feral Saberon), Rip And Slice (Agitated Voidscythe)", confidence = V },
    { id = "VA_TANK", note = "Tank busters (one knocks back, one amplifies damage); tank needs defensives.", need = "external_defensive", category = "tank", severity = "medium", minProviders = 1,
      source = "Shred Defense, Head Bash, Brutalize, Bloodsurge", confidence = V },
  },
})

---------------------------------------------------------------------------
-- Ruby Life Pools (returning; reworked for S2)
---------------------------------------------------------------------------
add("RubyLifePools", {
  name = "Ruby Life Pools",
  bosses = { "Melidrussa Chillworn", "Kokia Blazehoof", "Kyrakka and Erkhart Stormvein" },
  requirements = {
    { id = "RLP_ICE_SHIELD", need = "interrupt", alt = { "stop" }, severity = "high", minProviders = 2,
      source = "Ice Shield (Flashfrost Chillweaver shields a mob)", note = "Interrupt or CC the cast.", confidence = V },
    { id = "RLP_FRIGID_SHARD", need = "interrupt", severity = "high", minProviders = 2,
      source = "Frigid Shard (Melidrussa)", note = "Now interruptible; cuts tank damage.", confidence = V },
    { id = "RLP_CINDERBOLT", note = "Random-target bolt; interrupt the cast.", need = "interrupt", severity = "high", minProviders = 2,
      source = "Cinderbolt (Primalist Cinderweaver)", confidence = V },
    -- 12.1.5: Living Bomb is now a Magic effect and can be dispelled; dispelling it prevents
    -- the explosion (Wowhead's 12.1.5 Ruby Life Pools tuning notes; confirmed by the author).
    { id = "RLP_LIVING_BOMB", note = "Random-player DoT that explodes when it expires; Magic dispel it to stop the explosion (since 12.1.5).",
      need = "dispel_magic", severity = "medium", minProviders = 1,
      source = "Living Bomb (Primalist Cinderweaver, Blazebound Destroyer; trash before Kokia)", confidence = V },
    { id = "RLP_BLAZE_VOLLEY", note = "Repeated cast from the Firestorm add; keep interrupts on it and kill the add.", need = "interrupt", severity = "high", minProviders = 2,
      source = "Blaze Volley (Kokia's Blazebound Firestorm add)", confidence = V },
    { id = "RLP_SPARE", need = "interrupt", severity = "medium", minProviders = 3,
      source = "Frostbolt, Fiery Blast, Thunder Blast, Storm Bolt (tank / random targets)",
      note = "Spare interrupts.", confidence = V },
    { id = "RLP_FLAMING_BARRAGE", need = "stop", severity = "high", minProviders = 1,
      source = "Flaming Barrage (Ashseer Flamelasher channel into the tank)", note = "CC to stop it.", confidence = V },
    { id = "RLP_STORMSLAM", need = "dispel_magic", severity = "high", minProviders = 1,
      source = "Stormslam (Erkhart, Magic debuff on the tank)", note = "Dispel before the next cast.", confidence = V },
    { id = "RLP_COLD_CLAWS", need = "dispel_magic", alt = { "freedom" }, severity = "medium", minProviders = 1,
      source = "Cold Claws (Infused Whelps, stacking on the tank)", note = "Clear before 20 stacks.", confidence = V },
    { id = "RLP_STORMCLOUD", need = "purge", severity = "medium", minProviders = 1,
      source = "Stormcloud Barrier (Primal Thundercloud)", note = "Purge to detonate the cloud.", confidence = V },
    { id = "RLP_BLAZE_OF_GLORY", need = "purge", severity = "low", minProviders = 1,
      source = "Blaze of Glory (Ashseer Flamelasher on death)", note = "Purge or avoid the swirlies.", confidence = V },
    { id = "RLP_ROLLING_THUNDER", need = "dispel_magic", severity = "low", minProviders = 1,
      source = "Rolling Thunder (Thunderhead lieutenant, often skipped)",
      note = "Stagger dispels: each removal pulses group damage.", confidence = V },
    { id = "RLP_TANK", need = "external_defensive", category = "tank", severity = "medium", minProviders = 1,
      source = "Steel Barrage (Defier Draghar), Crushing Smash, Searing Blows (Kokia), Fire Maw, Thunder Jaw",
      note = "Tank defensive every Searing Blows; an external is the backup.", confidence = V },
    { id = "RLP_GROUP_DAMAGE", need = "group_defensive", severity = "medium", minProviders = 1,
      source = "Inferno (Blazebound Destroyer), Molten Blood (Flamegullet), Frost Overload (Melidrussa)",
      note = "Group defensives or healing cooldowns.", confidence = V },
  },
})

---------------------------------------------------------------------------
-- Kings' Rest (returning; reworked for S2)
---------------------------------------------------------------------------
add("KingsRest", {
  name = "Kings' Rest",
  aliases = { "King's Rest", "Kings Rest" },
  bosses = { "The Golden Serpent", "Mchimba the Embalmer", "The Council of Tribes", "Dazar, the First King" },
  requirements = {
    { id = "KR_HEX_VOLLEY", need = "interrupt", severity = "critical", minProviders = 2,
      source = "Hex Volley (Risen Hexer)", note = "Interrupt every cast.", confidence = V },
    { id = "KR_UNHOLY_MENDING", need = "interrupt", severity = "critical", minProviders = 2,
      source = "Unholy Mending (Seneschal M'bara)", note = "Interrupt every cast; purge if one lands.", confidence = V },
    { id = "KR_BIND_SOUL", need = "interrupt", severity = "critical", minProviders = 2,
      source = "Bind Soul (Queen Wasi)", note = "Interrupt every cast.", confidence = V },
    { id = "KR_WRETCHED", note = "Interrupt every cast; casts that get through raise wipe risk on Mchimba.", need = "interrupt", severity = "high", minProviders = 2,
      source = "Wretched Discharge (Half-Finished Mummy, trash and Mchimba)", confidence = V },
    { id = "KR_POISON_NOVA", note = "Council cast to always interrupt.", need = "interrupt", severity = "high", minProviders = 2,
      source = "Poison Nova (Council of Tribes)", confidence = V },
    { id = "KR_DEATHLY_ROAR", note = "Reban's cast on the Dazar fight; keep it interrupted.", need = "interrupt", severity = "high", minProviders = 1,
      source = "Deathly Roar (Reban, Dazar encounter)", confidence = V },
    { id = "KR_SPARE", need = "interrupt", severity = "medium", minProviders = 3,
      source = "Shadow Bolt, Soul Bolt, Spectral Bolt", note = "Spare interrupts.", confidence = V },
    { id = "KR_HEX", need = "dispel_curse", alt = { "interrupt" }, severity = "high", minProviders = 1,
      source = "Hex (Phantom Hex Priest)", note = "Interrupt or Curse dispel every cast.", confidence = V },
    { id = "KR_BOUND_SHADOW", need = "purge", alt = { "stop" }, severity = "medium", minProviders = 1,
      source = "Bound by Shadow (Minion of Zul shield)", note = "Purging the shield kills the minion.", confidence = V },
    { id = "KR_MENDING_PURGE", note = "Kick every cast; if one lands, purge the buff off the mob.", need = "purge", severity = "medium", minProviders = 1,
      source = "Unholy Mending (if a cast lands)", confidence = V },
    { id = "KR_CAPTAINS_BULWARK", need = "purge", alt = { "stop" }, severity = "medium", minProviders = 1,
      source = "Captain's Bulwark (Guard Captain Atu)", note = "Purge it, or CC to delay the cast.", confidence = V },
    { id = "KR_SOOTHE", note = "Enrages the Champion, and Patlaa and her raptor; Soothe them off.", need = "soothe", severity = "medium", minProviders = 1,
      source = "Ancestral Fury (Shadow-Borne Champion), Bestial Berserk (Queen Patlaa)", confidence = V },
    -- Aug 25 hotfix: Risen Hexer now casts Shadow Bolt (was Shadowfrost Bolt). It still leaves
    -- a Magic slow (confirmed in game by the author, October 13, 2026); Method.gg's guide still
    -- calls it Shadowfrost Bolt: "use a Magic dispel or freedom to remove the effect".
    { id = "KR_SHADOW_BOLT", note = "Random-target bolt; kick it, and Magic dispel or free anyone it slows.", need = "dispel_magic", alt = { "freedom" }, severity = "medium", minProviders = 1,
      source = "Shadow Bolt (Risen Hexer, if not kicked)", confidence = V },
    { id = "KR_FROST_SHOCK", note = "Random-target slow; Magic dispel or freedom removes it.", need = "dispel_magic", alt = { "freedom" }, severity = "low", minProviders = 1,
      source = "Frost Shock slow (Spectral Shaman)", confidence = V },
    { id = "KR_SERPENT_STRIKE", note = "Random-target poison DoT; Poison dispel or a freedom effect.", need = "dispel_poison", alt = { "freedom" }, severity = "medium", minProviders = 1,
      source = "Serpent Strike DoT (Queen Patlaa)", confidence = V },
    { id = "KR_EMBALMING", note = "Mobs leave poison circles on death; dodge them, Poison dispel anyone hit.", need = "dispel_poison", alt = { "freedom" }, severity = "medium", minProviders = 1,
      source = "Embalming Fluid (puddles on death)", confidence = V },
    { id = "KR_BLEEDS", need = "dispel_bleed", alt = { "external_defensive" }, severity = "medium", minProviders = 1,
      source = "Mortal Bleed, Sudden Rupture, Bloodthirsty Axe, Severing Axe",
      note = "Bleed cleanse or defensives (Blood Drain punishes bleeding players).", confidence = V },
    { id = "KR_TANK", note = "Soul Crush amplifies damage, Blade Combo ramps up after Maul; tank defensive.", need = "external_defensive", category = "tank", severity = "medium", minProviders = 1,
      source = "Soul Crush (Ghostly Brute), Blade Combo / Savage Maul (Dazar)", confidence = V },
    { id = "KR_HUNTING_LEAP", need = "stop", severity = "low", minProviders = 1,
      source = "Hunting Leap (Honored Raptor)", note = "CC to stop the frontal.", confidence = V },
    { id = "KR_ANIMATED_GOLD", need = "aoe_stop", alt = { "root" }, severity = "low", minProviders = 1,
      source = "Lucre's Call (Golden Serpent's Animated Gold)", note = "Slows and CC keep the blobs off the boss.",
      confidence = V },
    { id = "KR_GROUP_DAMAGE", need = "group_defensive", severity = "medium", minProviders = 1,
      source = "Serpentine Gust (Golden Serpent), Gilded Destruction (Dazar)", note = "Group defensives or healing cooldowns.",
      confidence = V },
  },
})

---------------------------------------------------------------------------
-- Temple of Sethraliss (returning; reworked for S2)
---------------------------------------------------------------------------
add("TempleOfSethraliss", {
  name = "Temple of Sethraliss",
  bosses = { "Adderis and Aspix", "Merektha", "Galvazzt", "Avatar of Sethraliss" },
  requirements = {
    { id = "TOS_IMBUED_CONDUCTION", need = "dispel_magic", severity = "critical", minProviders = 1,
      source = "Imbued Conduction (Imbued Stormcaller)", note = "Dispel every one or it stuns on expiry.",
      confidence = V },
    { id = "TOS_LIGHTNING_BOLT", note = "Random-target bolt; keep interrupts on it.", need = "interrupt", severity = "high", minProviders = 2,
      source = "Lightning Bolt (Storm Adept, Imbued Stormcaller)", confidence = V },
    { id = "TOS_FLAME_SHOCK", note = "Random-target cast; run an interrupt rotation on it.", need = "interrupt", severity = "high", minProviders = 2,
      source = "Flame Shock (Twisted Hexxer, trash and final boss)", confidence = V },
    { id = "TOS_ESSENCE_DISRUPTION", note = "Channels into the nearest Eye; stop it with interrupts and CC.", need = "interrupt", alt = { "stop" }, severity = "high", minProviders = 2,
      source = "Essence Disruption (Temple Disruptor channel into the Eye)", confidence = V },
    { id = "TOS_ARROW_BARRAGE", need = "stop", severity = "high", minProviders = 1,
      source = "Arrow Barrage (Sandswept Hunter channel)", note = "Use CC to stop it.", confidence = V },
    { id = "TOS_POISON_SPIT", note = "Applies a poison DoT; keep interrupts on it, Poison dispel any that land.", need = "interrupt", severity = "medium", minProviders = 2,
      source = "Poison Spit (Merektha's Toxic Vipers)", confidence = V },
    { id = "TOS_SPARE", need = "interrupt", severity = "medium", minProviders = 2,
      source = "Venom Bolt (Brood Tender)", note = "Spare interrupts.", confidence = V },
    { id = "TOS_CYTOTOXIN", note = "Random-target poison debuff; Poison dispel it or use a defensive.", need = "dispel_poison", severity = "medium", minProviders = 1,
      source = "Cytotoxin (Poisonous Viper), Poison Spit DoTs", confidence = V },
    { id = "TOS_CHEAP_SHOT", need = "dispel_poison", alt = { "interrupt" }, severity = "medium", minProviders = 1,
      source = "Poisoned Cheap Shot (Shrouded Fang)", note = "Interrupt or Poison dispel the stun.", confidence = V },
    { id = "TOS_ADDLE_MIND", need = "dispel_curse", alt = { "interrupt" }, severity = "medium", minProviders = 1,
      source = "Addle Mind (Faithless Subjugator)", note = "Interrupt or Curse dispel the disorient.", confidence = V },
    { id = "TOS_ACCUMULATE", note = "Stacks make Release Charge hit much harder; purge the stacks off.", need = "purge", severity = "medium", minProviders = 1,
      source = "Accumulate Charge (Agitated Nimbus)", confidence = V },
    { id = "TOS_TORMENTORS", need = "aoe_stop", severity = "medium", minProviders = 1,
      source = "Faithless Tormentor waves (Avatar of Sethraliss)",
      note = "Kite, CC and AoE them; each one that dies heals the Avatar 0.7%. DPS take the purple Corrupted Lifeforce soaks.",
      confidence = V },
    { id = "TOS_BLEED", note = "Random-target bleed; Bleed cleanse or defensive if it overlaps other damage.", need = "dispel_bleed", alt = { "external_defensive" }, severity = "low", minProviders = 1,
      source = "Serrated Charge (Barbed Krolusk / Swarming Krolusks)", confidence = V },
    { id = "TOS_TANK", note = "Tank busters (Sunder Slam amplifies damage, Slash leaves circles); defensive each.", need = "external_defensive", category = "tank", severity = "medium", minProviders = 1,
      source = "Sunder Slam, Lightning Bite, Venomous Slash, Tainted Strike", confidence = V },
    -- Avatar of Sethraliss (Method.gg / Wowhead guides): no group-wide damage cooldown is called
    -- for. Its utility asks are Flame Shock kicks (TOS_FLAME_SHOCK), Faithless Tormentor CC
    -- (TOS_TORMENTORS) and Tainted Strike (TOS_TANK); the rest is soaking and positioning.
    { id = "TOS_KNOT_OF_SNAKES", need = "aoe_stop", severity = "medium", minProviders = 1,
      source = "A Knot of Snakes (Merektha)", note = "Stack in melee so one AoE CC destroys them.", confidence = V },
    { id = "TOS_GROUP_DAMAGE", need = "group_defensive", severity = "medium", minProviders = 1,
      source = "Lightning Spire soaks (Galvazzt), Caustic Stomp (Orb Watcher)",
      note = "Spread defensives and healing cooldowns.", confidence = V },
  },
})

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function norm(s)
  return (tostring(s or ""):lower():gsub("%(.-%)", ""):gsub("[^%w]", ""))
end

-- Map free text (slash command, LFG activity name) to a dungeon key.
---------------------------------------------------------------------------
-- Identity by ID (locale-proof). Names are only a last-resort fallback.
-- Challenge-mode (keystone) map IDs confirmed in 12.1.0 (build 69933) by /kc verify.
---------------------------------------------------------------------------
DD.CHALLENGE_MAP_IDS = {
  AltarOfFangs = 588, TheBlindingVale = 584, VoidscarArena = 585, DenOfNalorakk = 586,
  MurderRow = 587, RubyLifePools = 399, KingsRest = 249, TempleOfSethraliss = 250,
}
-- Group Finder activity IDs seen in-client (activity 1949 confirmed by /kc verify).
-- Others are resolved through the activity's instance map ID, then by name.
DD.ACTIVITY_IDS = { [1949] = "TheBlindingVale" }

local byChallenge = {}
for key, id in pairs(DD.CHALLENGE_MAP_IDS) do byChallenge[id] = key end

function DD:KeyForChallengeMap(mapID)
  return mapID and byChallenge[mapID] or nil
end

-- Instance (world) map IDs, learned from C_ChallengeMode.GetMapUIInfo's 6th return.
-- Confirmed in 12.1.0 (build 69933) by /kc verify; runtime learning covers later changes.
DD.INSTANCE_MAP_IDS = {
  AltarOfFangs = 2993, RubyLifePools = 2521, KingsRest = 1762, VoidscarArena = 2923,
  DenOfNalorakk = 2825, MurderRow = 2813, TheBlindingVale = 2859, TempleOfSethraliss = 1877,
}
local byInstance, instanceLearned = {}, false
for key, id in pairs(DD.INSTANCE_MAP_IDS) do byInstance[id] = key end
function DD:LearnInstanceMaps()
  if instanceLearned or not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return end
  local any = false
  for key, id in pairs(self.CHALLENGE_MAP_IDS) do
    local ok, name, _, _, _, _, instanceMapID = pcall(C_ChallengeMode.GetMapUIInfo, id)  -- 6th return = instance mapID
    if ok and name then any = true end
    if ok and type(instanceMapID) == "number" and instanceMapID > 0 then byInstance[instanceMapID] = key end
  end
  instanceLearned = any        -- retry later if the map data wasn't loaded yet
end
function DD:KeyForInstanceMap(instanceMapID)
  if not instanceMapID then return nil end
  self:LearnInstanceMaps()
  return byInstance[instanceMapID]
end

-- A Group Finder activity -> dungeon key: known activity ID, the activity's instance
-- map ID, then (English clients) its name.
local byActivity = {}
function DD:KeyForActivity(activityID, info)
  if activityID and self.ACTIVITY_IDS[activityID] then return self.ACTIVITY_IDS[activityID] end
  if activityID and byActivity[activityID] then return byActivity[activityID] end
  if type(info) ~= "table" then return nil end
  local key = self:KeyForInstanceMap(info.mapID)
    or self:FindKey(info.fullName) or self:FindKey(info.shortName)
  if key and activityID then byActivity[activityID] = key end
  return key
end

function DD:FindKey(text)
  local n = norm(text)
  if n == "" then return nil end
  for _, key in ipairs(self.order) do
    local d = self.list[key]
    if norm(key) == n or norm(d.name) == n then return key end
    if d.aliases then
      for _, a in ipairs(d.aliases) do if norm(a) == n then return key end end
    end
  end
  -- Substring match (e.g. "Kings' Rest (Mythic Keystone)").
  for _, key in ipairs(self.order) do
    local dn = norm(self.list[key].name)
    if #n >= 5 and (n:find(dn, 1, true) or dn:find(n, 1, true)) then return key end
  end
  return nil
end

function DD:CategoryOf(req)
  if req.category then return req.category end
  local cap = ns.UD and ns.UD.CAP_INFO[req.need]
  return cap and cap.category or "other"
end

-- WHERE each trash requirement happens, for the Dungeon tab's walkthrough: the trash
-- section(s) it shows up in, by the boss that section leads to (1 = trash before the first
-- boss, 2 = trash between bosses 1 and 2...). Boss mechanics come from BossData's `reqs`
-- instead, so a requirement listed on a boss card needs an entry here only when its mobs
-- also appear as trash. A requirement with neither shows under "Throughout the dungeon".
-- From Method.gg's and Icy Veins' Season 2 guides (trash sections by boss), October 2026.
-- With a Mythic Dungeon Tools route, the walkthrough follows the route's pull order and
-- uses these only for mobs the route doesn't pull.
DD.AREAS = {
  AltarOfFangs = {
    AOF_PARALYZE = { 1 }, AOF_ENRAGE = { 1 }, AOF_PIERCING_HISS = { 1 }, AOF_CORROSIVE_FANGS = { 1, 2, 3 },
    AOF_ENVENOM_INT = { 2, 3 }, AOF_ENVENOM_POISON = { 2, 3 }, AOF_EVOLVE = { 2, 3 }, AOF_HATCHLINGS = { 2 },
    AOF_MASS_ENVENOM = { 2, 3 },
  },
  MurderRow = {
    MR_SEDUCTION = { 1 }, MR_FEL_MISSILES = { 1 }, MR_FEL_CRAZED = { 1 }, MR_HEARTSTOP = { 1 }, MR_TANK = { 1 },
    MR_BLEEDS = { 1, 3, 4 }, MR_SOOTHE = { 3, 4 }, MR_HEALTH_FUNNEL = { 4 }, MR_CURSE_OF_DOOM = { 4 },
    MR_BLADE_DANCE = { 4 }, MR_SPARE = { 4 },
  },
  DenOfNalorakk = {
    DN_EFFIGY_CURSE = { 1 }, DN_EARTH_BOLT = { 1 }, DN_HEALING_BREEZE = { 1 }, DN_BREEZE_PURGE = { 1 },
    DN_BLEED = { 1 }, DN_SOOTHE = { 1, 3 }, DN_SPARE = { 1, 3 }, DN_FRIGID_ROAR = { 2 }, DN_CRYO_SURGE = { 2 },
    DN_FREEDOM = { 2 }, DN_TANK = { 2, 3 }, DN_ARC_LIGHTNING = { 3 },
  },
  TheBlindingVale = {
    BV_SPORE_SPINES = { 1 }, BV_LIGHT_BOLT_VOLLEY = { 1 }, BV_SCREECH = { 1 }, BV_CALL_THE_GROVE = { 1 },
    BV_HUNTING_LEAP = { 1 }, BV_TANK = { 1 }, BV_SPOUTING_FLORET = { 1 }, BV_SPARE = { 1 }, BV_BLEEDS = { 1, 3 },
    BV_TOXIC_SPEW = { 4 }, BV_POTAD_TOSS = { 4 },
  },
  VoidscarArena = {
    VA_VOLLEY = { 1 }, VA_LAVA_BOLT = { 1 }, VA_MELT_ARMOR = { 1 }, VA_DEMORALIZING_SHOUT = { 1 },
    VA_VIOLENT_SAND = { 1 }, VA_FREEDOM = { 1 }, VA_SHELL_GUARD = { 1 }, VA_SOOTHE = { 1 }, VA_BLEEDS = { 1, 2 },
    VA_TANK = { 1, 2, 3 }, VA_CORROSIVE = { 2 }, VA_MAD_SHRIEK = { 2 }, VA_MENDING_VOID = { 3 },
  },
  RubyLifePools = {
    RLP_ICE_SHIELD = { 1 }, RLP_COLD_CLAWS = { 1 }, RLP_SPARE = { 1, 2, 3 }, RLP_TANK = { 1, 2, 3 },
    RLP_CINDERBOLT = { 2 }, RLP_LIVING_BOMB = { 2 }, RLP_FLAMING_BARRAGE = { 2 }, RLP_BLAZE_OF_GLORY = { 2 }, RLP_ROLLING_THUNDER = { 2 },
    RLP_GROUP_DAMAGE = { 2 }, RLP_STORMCLOUD = { 3 },
  },
  KingsRest = {
    KR_HEX_VOLLEY = { 1 }, KR_SHADOW_BOLT = { 1 }, KR_BOUND_SHADOW = { 1, 4 }, KR_SOOTHE = { 1, 2 },
    KR_SPARE = { 1, 2, 3 }, KR_UNHOLY_MENDING = { 2 }, KR_MENDING_PURGE = { 2 }, KR_BIND_SOUL = { 2 },
    KR_WRETCHED = { 2 }, KR_CAPTAINS_BULWARK = { 2 }, KR_SERPENT_STRIKE = { 2 }, KR_EMBALMING = { 2 },
    KR_BLEEDS = { 2, 3 }, KR_HEX = { 3 }, KR_FROST_SHOCK = { 3 }, KR_HUNTING_LEAP = { 3 }, KR_TANK = { 3 },
  },
  TempleOfSethraliss = {
    TOS_ARROW_BARRAGE = { 1 }, TOS_CHEAP_SHOT = { 1 }, TOS_LIGHTNING_BOLT = { 1, 3 }, TOS_BLEED = { 1, 2 },
    TOS_TANK = { 1, 2, 4 }, TOS_CYTOTOXIN = { 2 }, TOS_SPARE = { 2 }, TOS_ADDLE_MIND = { 2 },
    TOS_IMBUED_CONDUCTION = { 3 }, TOS_ACCUMULATE = { 3 }, TOS_ESSENCE_DISRUPTION = { 4 }, TOS_FLAME_SHOCK = { 4 },
    TOS_TORMENTORS = { 4 }, TOS_GROUP_DAMAGE = { 4 },
  },
}

-- Default Bloodlust timing, shown until the player sets their own (Plan or Dungeon tab).
-- `at` is where it goes: "b<N>" = boss N, "t<N>" = the trash before boss N ("p<N>", pull N
-- of a Mythic Dungeon Tools route, only comes from the player's own edits). Method.gg and
-- Icy Veins give no timing; these follow WoWCarry's Season 2 guides (one source, so they
-- show as suggestions). Ruby Life Pools has no guide timing: first and last boss.
DD.LUST = {
  AltarOfFangs    = { { at = "b1", note = "on pull" }, { at = "b3", note = "on pull" } },
  MurderRow       = { { at = "b1", note = "when Nibbles hits 20% and Kystia is stunned" },
                      { at = "b4", note = "after her first gateway, once the shield ends" } },
  DenOfNalorakk   = { { at = "b1", note = "on pull" }, { at = "b3", note = "on pull" } },
  TheBlindingVale = { { at = "b1", note = "Ikuzz at 50% if you go there first; Trinity after the first garden" },
                      { at = "b3", note = "at 40%" }, { at = "b4", note = "if it's back" } },
  VoidscarArena   = { { at = "t1", note = "the opening arena champion pull" }, { at = "b2", note = "on pull" },
                      { at = "b3", note = "on pull, if it's back" } },
  RubyLifePools   = { { at = "b1", note = "on pull" }, { at = "b3", note = "on pull" } },
  KingsRest       = { { at = "b2", note = "on pull, or the opening pack if it's kept small" }, { at = "b4", note = "on pull" } },
  TempleOfSethraliss = { { at = "b2", note = "on pull, or on Adderis and Aspix instead" }, { at = "b4", note = "when the Tormentor waves stack up" } },
}
DD.LUST_SOURCE = {
  RubyLifePools = "No guide gives a timing for Ruby Life Pools; this is the common first and last boss default.",
}
DD.LUST_SOURCE_DEFAULT = "Suggested by one Season 2 guide (WoWCarry). Tanks and routes differ: set your own."

-- Validate every need/alt against the capability vocabulary. Run once at load; bad keys
-- are reported and the requirement is marked invalid so it can never read as "covered".
function DD:Validate()
  local problems = {}
  for _, key in ipairs(self.order) do
    for _, req in ipairs(self.list[key].requirements) do
      local bad = not ns.UD:IsCap(req.need)
      if req.alt then for _, a in ipairs(req.alt) do if not ns.UD:IsCap(a) then bad = true end end end
      if not DD.SEVERITY_RANK[req.severity] then bad = true end
      if req.confidence ~= V and req.confidence ~= NV then req.confidence = NV end
      if type(req.minProviders) ~= "number" or req.minProviders < 1 then req.minProviders = 1 end
      if bad then
        req.invalid = true
        table.insert(problems, key .. ":" .. tostring(req.id))
      end
    end
  end
  return problems
end

local problems = DD:Validate()
if #problems > 0 then
  ns:On("LOGIN", function()
    ns:Print("DungeonData has invalid capability keys: " .. table.concat(problems, ", "))
  end)
end
