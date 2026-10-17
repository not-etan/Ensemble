-- Ensemble / UtilityDatabase.lua  (Feature 1)
-- Per-class, per-spec utility data. Pure data + small lookup helpers; no UI, no analysis.
-- Blizzard retunes utility every patch: edit THIS file only, nothing else depends on its
-- internals beyond the accessor functions at the bottom.
--
-- DATA PROVENANCE: every class and spec was checked against Wowhead's Patch 12.1.0
-- "Abilities and Talents" guides (Classes tab, updated Aug 2026): what each spec has,
-- baseline vs talent, and stated cooldowns. Earlier sources: the spec's reference notes
-- plus long-standing class kits. Patch 12.1.5 (October 13, 2026): Blizzard's patch notes and
-- the hotfix thread change no tracked utility (Marksmanship's Unload was removed and
-- Merithra's Blessing lasts 30s, neither tracked here). Any entry
-- tagged `verify = true` is one the maintainer could not confirm for 12.1 -- check it
-- against Warcraft Wiki / in-game tooltips and drop the flag once confirmed.
--
-- Entry flags (all optional) on a capability source:
--   long        = long cooldown (e.g. 45-60s interrupt), weaker than a rotational kick
--   talent      = needs a talent choice; counted only if settings.countTalentSources
--   core        = with talent: a talent every build takes (interrupts, the class dispel or
--                 purge, a healer's signature cooldown). Shown as a talent, counted as reliable.
--   pet         = depends on a specific pet being out
--   conditional = string; only applies under a condition (e.g. fallback battle rez)
--   verify      = not confirmed for 12.1
-- Any of long/talent (unless core)/pet/conditional/verify makes a source "soft" (a weaker single point
-- of failure in the dungeon readiness check).

local _, ns = ...

local UD = {}
ns.UD = UD

---------------------------------------------------------------------------
-- Shared capability vocabulary. DungeonData `need` / `alt` keys MUST come from here.
---------------------------------------------------------------------------
UD.CAPS = {
  { key = "interrupt",          label = "Interrupt",                  category = "interrupts" },
  { key = "stop",               label = "Stop (stun/fear/incap)",     category = "stops" },
  { key = "aoe_stop",           label = "AoE stop",                   category = "stops" },
  { key = "knockback",          label = "Knockback / displacement",   category = "stops" },
  { key = "root",               label = "Root",                       category = "stops" },
  { key = "dispel_magic",       label = "Magic dispel",               category = "dispels" },
  { key = "dispel_curse",       label = "Curse dispel",               category = "dispels" },
  { key = "dispel_poison",      label = "Poison dispel",              category = "dispels" },
  { key = "dispel_disease",     label = "Disease dispel",             category = "dispels" },
  { key = "dispel_bleed",       label = "Bleed cleanse",              category = "dispels" },
  { key = "purge",              label = "Purge (enemy Magic)",        category = "dispels" },
  { key = "soothe",             label = "Soothe (enrage)",            category = "dispels" },
  { key = "freedom",            label = "Freedom (root/snare removal)", category = "other" },
  { key = "battle_rez",         label = "Battle resurrection",        category = "other" },
  { key = "bloodlust",          label = "Bloodlust / Heroism",        category = "other" },
  { key = "external_defensive", label = "External defensive",         category = "tank" },
  { key = "group_defensive",    label = "Group defensive",            category = "other" },
  { key = "movement",           label = "Group movement speed",       category = "other" },
  { key = "group_stealth",      label = "Group stealth / invis skip", category = "other" },
}
UD.CAP_INFO = {}
for i, c in ipairs(UD.CAPS) do c.order = i; UD.CAP_INFO[c.key] = c end
-- Short names for dense lists (row headers, tooltips and the glossary keep the full names).
UD.CAP_SHORT = {
  stop = "Stop", knockback = "Knockback", purge = "Purge", soothe = "Soothe", freedom = "Freedom",
  battle_rez = "Battle rez", bloodlust = "Bloodlust", external_defensive = "External",
  group_defensive = "Group defensive", movement = "Group speed", group_stealth = "Stealth skip",
}

-- Plain-language explanations (Settings > "Show explanations"). Teaching text only:
-- turning it off never hides a status, gap or coverer.
UD.CAP_EXPLAIN = {
  interrupt = "Stops an enemy cast so it does nothing. Rotational kicks come back every ~15s; long-cooldown ones (30s+) can't keep up on their own.",
  stop = "Any stun, fear or incapacitate that ends a cast. The backup when kicks are on cooldown, and the answer to casts that can't be kicked.",
  aoe_stop = "Stops several enemies at once (e.g. a stun around you). Packs of casters need these.",
  knockback = "Moves enemies away (knockbacks, grips, displacements). Ends some casts and pulls mobs out of bad spots.",
  root = "Holds an enemy in place. Useful for kiting and for keeping melee mobs off your healer.",
  dispel_magic = "Removes harmful Magic effects from your group. Usually the healer's job.",
  dispel_curse = "Removes Curses from your group. Only a few classes can.",
  dispel_poison = "Removes Poisons from your group.",
  dispel_disease = "Removes Diseases from your group.",
  dispel_bleed = "Removes bleeds. Few classes can, so groups usually answer them with defensives and healing.",
  purge = "Removes a buff from an enemy, such as a shield, a damage buff or a heal over time.",
  soothe = "Removes an Enrage from an enemy; enraged mobs hit much harder until it's removed or ends.",
  freedom = "Removes roots and slows so a player can move out of danger.",
  battle_rez = "Brings a dead player back during combat. In Mythic+ the whole group shares a limited number of charges.",
  bloodlust = "A big haste boost for the whole group for 40 seconds. Used on bosses or big pulls to save time.",
  external_defensive = "A damage reduction cast on someone else, usually the tank, for the biggest hits.",
  group_defensive = "Reduces damage for the whole group during heavy group-wide damage.",
  movement = "A group speed boost that saves time between packs.",
  group_stealth = "Lets the group sneak past packs it doesn't need to fight (skips).",
}
function UD:CapExplain(key) return self.CAP_EXPLAIN[key] end

-- Glossary of the addon's terms (the "?" button).
UD.GLOSSARY = {
  { "Needs", "What a dungeon (and this week's affixes) asks a group to handle: kicks, dispels, stops, tank help and more." },
  { "Gaps", "Needs your group doesn't cover (MISSING) or covers too thinly (THIN)." },
  { "Assignments", "Who takes each kick and dispel: 1st and 2nd in line, plus a backup. On the Plan tab and posted to chat." },
  { "MISSING", "Nobody in the group covers this, and something here needs it." },
  { "THIN", "Covered, but not well enough: fewer players than wanted, a single point of failure, or only a conditional source." },
  { "OK", "Covered." },
  { "NONE", "Nobody brings it, and nothing in this dungeon or week asks for it." },
  { "[unconfirmed]", "Comes from data that couldn't be verified for this patch. Never shown as MISSING." },
  { "Severity", "How bad a miss is: CRITICAL (wipes or kills), HIGH, MEDIUM, LOW." },
  { "Rotational kick", "An interrupt with a short cooldown (about 15-24s) that can be used on every pack." },
  { "Long-CD kick", "An interrupt with a 30s+ cooldown (e.g. Silence, Solar Beam); helps, but can't cover a cast alone." },
  { "Kick rotation", "Two or more players taking turns on the same dangerous cast, shortest cooldown first." },
  { "Stop", "Stun, fear or incapacitate that ends a cast. The backup for kicks." },
  { "AoE stop", "A stop that hits several enemies at once." },
  { "Single point of failure", "Only one player covers something critical; if they die or misplay, nobody else can." },
  { "Backup", "The second player assigned to a kick or dispel in case the first is busy or dead." },
  { "Brez", "Battle resurrection: revive a dead player in combat (shared charges in Mythic+)." },
  { "Lust", "Bloodlust / Heroism / Time Warp and similar: a 40-second group haste boost." },
  { "Dispel", "Remove a harmful effect (Magic, Curse, Poison, Disease) from a player." },
  { "Purge", "Remove a buff from an enemy." },
  { "Soothe", "Remove an Enrage from an enemy." },
  { "External", "A defensive cast on another player, usually the tank." },
  { "Synergy", "How well a raid buff suits the players you have (e.g. Chaos Brand with magic damage dealers)." },
  { "Fit score", "0-100: how much of what this slot could fix an applicant fixes, compared with the best and weakest picks for their role." },
  { "Great / Good / Fair / Poor", "Fit ratings. Poor also means their role has no open slot." },
  { "Affixes", "This week's Mythic+ modifiers; some add needs (e.g. Voidbound: kick Dark Prayer)." },
  { "Xal'atath's Bargain / Guile", "The +5 to +11 weekly affix, replaced by Guile (deaths cost time) at +12." },
}

function UD:IsCap(key) return self.CAP_INFO[key] ~= nil end
function UD:CapLabel(key) local c = self.CAP_INFO[key]; return c and c.label or tostring(key) end
function UD:CapShort(key) return self.CAP_SHORT[key] or self:CapLabel(key) end

-- CC types used for the "crowd control diversity" check.
UD.CC_TYPES = { "stun", "incapacitate", "disorient", "fear", "silence", "knockback", "root" }

-- Raid utility buffs/debuffs. Never reported as "missing" (a 5-player group can't carry
-- them all). What counts is SYNERGY: how many members actually benefit from a buff the
-- group has. `affects` says who benefits (factor 1 = full, 0.5 = partial):
--   stat   = primary stat     (str / agi / int)
--   school = damage school    (physical / magic / mixed)
--   range  = melee or ranged  (Skyfury's extra auto-attacks are melee-only)
--   all    = everyone equally (universal: shown, but no synergy to build around)
-- Damage schools and stats per spec are listed in SPEC_STAT / SPEC_SCHOOL below.
UD.BUFFS = {
  { key = "BATTLE_SHOUT",     name = "Battle Shout", spell = 6673,           class = "WARRIOR",
    effect = "Attack Power", affects = { stat = { str = 1, agi = 1 } }, who = "Strength/Agility users" },
  { key = "ARCANE_INTELLECT", name = "Arcane Intellect", spell = 1459,       class = "MAGE",
    effect = "Intellect", affects = { stat = { int = 1 } }, who = "Intellect users" },
  { key = "CHAOS_BRAND",      name = "Chaos Brand", spell = 1490,            class = "DEMONHUNTER",
    effect = "enemies take more magic damage", affects = { school = { magic = 1, mixed = 0.5 } }, who = "magic damage dealers" },
  { key = "MYSTIC_TOUCH",     name = "Mystic Touch", spell = 8647,           class = "MONK",
    effect = "enemies take more physical damage", affects = { school = { physical = 1, mixed = 0.5 } }, who = "physical damage dealers" },
  { key = "SKYFURY",          name = "Skyfury", spell = 462854,                class = "SHAMAN",
    effect = "Mastery, plus extra melee auto-attacks", affects = { range = { melee = 1, ranged = 0.5 } }, who = "melee" },
  { key = "MARK_OF_THE_WILD", name = "Mark of the Wild", spell = 1126,       class = "DRUID",
    effect = "Versatility", affects = { all = true } },
  { key = "FORTITUDE",        name = "Power Word: Fortitude", spell = 21562,  class = "PRIEST",
    effect = "Stamina", affects = { all = true } },
  { key = "BRONZE",           name = "Blessing of the Bronze", spell = 364342, class = "EVOKER",
    effect = "movement cooldowns", affects = { all = true } },
  { key = "HUNTERS_MARK",     name = "Hunter's Mark", spell = 257284,          class = "HUNTER",
    effect = "the marked target takes 3% more damage", affects = { all = true } },
}
-- Spell IDs for class abilities, keyed by the ability name used in the tables below
-- (suffixes like " (Felhunter)" or " (pet)" are stripped; "A / B" uses A). Used for icons
-- and tooltips only. IDs are long-standing values; Midnight may have changed some - if an
-- ID is gone the addon falls back to the player's own spell of that name, then a "?" icon.
UD.SPELL_IDS = {
  ["Mind Freeze"] = 47528, ["Raise Ally"] = 61999, ["Anti-Magic Zone"] = 51052, ["Death Grip"] = 49576,
  ["Asphyxiate"] = 221562, ["Blinding Sleet"] = 207167, ["Gorefiend's Grasp"] = 108199,
  ["Disrupt"] = 183752, ["Consume Magic"] = 278326, ["Darkness"] = 196718, ["Chaos Nova"] = 179057,
  ["Imprison"] = 217832, ["Sigil of Misery"] = 207684, ["Sigil of Silence"] = 202137,
  ["Rebirth"] = 20484, ["Soothe"] = 2908, ["Stampeding Roar"] = 106898, ["Remove Corruption"] = 2782,
  ["Incapacitating Roar"] = 99, ["Mighty Bash"] = 5211, ["Typhoon"] = 132469, ["Ursol's Vortex"] = 102793,
  ["Mass Entanglement"] = 102359, ["Cyclone"] = 33786, ["Solar Beam"] = 78675, ["Skull Bash"] = 106839,
  ["Maim"] = 22570, ["Nature's Cure"] = 88423, ["Ironbark"] = 102342,
  ["Fury of the Aspects"] = 390386, ["Quell"] = 351338, ["Cauterizing Flame"] = 374251, ["Zephyr"] = 374227,
  ["Wing Buffet"] = 357214, ["Tail Swipe"] = 368970, ["Sleep Walk"] = 360806, ["Landslide"] = 358385,
  ["Expunge"] = 365585, ["Naturalize"] = 360823, ["Time Dilation"] = 357170,
  ["Counter Shot"] = 147362, ["Muzzle"] = 187707, ["Tranquilizing Shot"] = 19801, ["Primal Rage"] = 264667, ["Roar of Sacrifice"] = 53480, ["Harrier's Cry"] = 466904,
  ["Avenger's Shield"] = 31935, ["Blessing of Spellwarding"] = 204018, ["Song of Chi-Ji"] = 198898,
  ["Oppressing Roar"] = 372048, ["Disrupting Shout"] = 386071, ["Void Nova"] = 1234195,
  ["Sigil of Chains"] = 202138,
  ["Master's Call"] = 272682, ["Intimidation"] = 19577, ["Freezing Trap"] = 187650, ["Binding Shot"] = 109248,
 
  ["Counterspell"] = 2139, ["Time Warp"] = 80353, ["Spellsteal"] = 30449, ["Remove Curse"] = 475,
  ["Mass Invisibility"] = 414664, ["Polymorph"] = 118, ["Frost Nova"] = 122, ["Ring of Frost"] = 113724,
  ["Blast Wave"] = 157981, ["Supernova"] = 157980, ["Dragon's Breath"] = 31661,
  ["Spear Hand Strike"] = 116705, ["Tiger's Lust"] = 116841, ["Detox"] = 218164, ["Leg Sweep"] = 119381,
  ["Paralysis"] = 115078, ["Ring of Peace"] = 116844, ["Life Cocoon"] = 116849,
  ["Blessing of Freedom"] = 1044, ["Blessing of Protection"] = 1022, ["Blessing of Sacrifice"] = 6940,
  ["Cleanse Toxins"] = 213644, ["Cleanse"] = 4987, ["Hammer of Justice"] = 853, ["Blinding Light"] = 115750,
  ["Repentance"] = 20066, ["Intercession"] = 391054, ["Aura Mastery"] = 31821, ["Rebuke"] = 96231,
  ["Dispel Magic"] = 528, ["Mass Dispel"] = 32375, ["Psychic Scream"] = 8122, ["Mind Control"] = 605,
  ["Purify"] = 527, ["Improved Purify"] = 390632, ["Pain Suppression"] = 33206, ["Power Word: Barrier"] = 62618,
  ["Guardian Spirit"] = 47788, ["Holy Word: Chastise"] = 88625, ["Silence"] = 15487, ["Purify Disease"] = 213634,
 
  ["Kick"] = 1766, ["Shiv"] = 5938, ["Shroud of Concealment"] = 114018, ["Kidney Shot"] = 408, ["Blind"] = 2094,
  ["Gouge"] = 1776, ["Sap"] = 6770, ["Between the Eyes"] = 315341,
  ["Wind Shear"] = 57994, ["Bloodlust"] = 2825, ["Purge"] = 370, ["Cleanse Spirit"] = 51886,
  ["Poison Cleansing Totem"] = 383013, ["Wind Rush Totem"] = 192077, ["Capacitor Totem"] = 192058, ["Hex"] = 51514,
  ["Earthgrab Totem"] = 51485, ["Thunderstorm"] = 51490, ["Purify Spirit"] = 77130, ["Spirit Link Totem"] = 98008,
  ["Soulstone"] = 20707, ["Spell Lock"] = 19647, ["Devour Magic"] = 19505, ["Singe Magic"] = 89808,
  ["Demonic Gateway"] = 111771, ["Fear"] = 5782, ["Shadowfury"] = 30283, ["Mortal Coil"] = 6789,
  ["Howl of Terror"] = 5484, ["Axe Toss"] = 89766,
  ["Pummel"] = 6552, ["Rallying Cry"] = 97462, ["Intervene"] = 3411, ["Intimidating Shout"] = 5246,
  ["Storm Bolt"] = 107570, ["Shockwave"] = 46968,
}

---------------------------------------------------------------------------
-- Base cooldowns (seconds) for kick and dispel assignments. Long-standing base values;
-- talents can shorten some (e.g. Counterspell, Quell, Mass Dispel). 0 = no cooldown
-- (global cooldown only). `UD.COOLDOWN_GROUP` maps abilities that share one cooldown.
---------------------------------------------------------------------------
UD.COOLDOWNS = {
  -- interrupts
  ["Mind Freeze"] = 15, ["Disrupt"] = 15, ["Quell"] = 20, ["Counter Shot"] = 24, ["Counterspell"] = 24,
  ["Spear Hand Strike"] = 15, ["Kick"] = 15, ["Wind Shear"] = 12, ["Spell Lock (Felhunter)"] = 24, ["Spell Lock (Fel Ravager)"] = 24, ["Avenger's Shield"] = 15,
  ["Pummel"] = 15, ["Solar Beam"] = 60, ["Skull Bash"] = 15, ["Muzzle"] = 15, ["Rebuke"] = 15,
  ["Silence"] = 45, ["Axe Toss (Felguard)"] = 30,
  -- dispels
  ["Cauterizing Flame"] = 60, ["Cleanse Spirit"] = 8, ["Cleanse Toxins"] = 8, ["Cleanse"] = 8, ["Detox"] = 8,
  ["Expunge"] = 8, ["Improved Purify"] = 8, ["Purify"] = 8, ["Mass Dispel"] = 45, ["Naturalize"] = 8,
  ["Nature's Cure"] = 8, ["Poison Cleansing Totem"] = 120, ["Purify Disease"] = 8, ["Purify Spirit"] = 8,
  ["Remove Corruption"] = 8, ["Remove Curse"] = 8, ["Singe Magic (Imp)"] = 15,
  -- purge / soothe
  ["Consume Magic"] = 10, ["Dispel Magic"] = 0, ["Purge"] = 0, ["Spellsteal"] = 0, ["Devour Magic (Felhunter)"] = 15,
  ["Tranquilizing Shot"] = 10, ["Paralysis (Pressure Points)"] = 45, ["Oppressing Roar (Overawe)"] = 120, ["Shiv"] = 30, ["Soothe"] = 10,
}
UD.COOLDOWN_GROUP = { ["Improved Purify"] = "Purify" }
UD.DEFAULT_COOLDOWN = { interrupt = 15, purge = 0, soothe = 10 }   -- dispels default 8

function UD:Cooldown(name, key)
  local cd = self.COOLDOWNS[name]
  if cd then return cd, true end
  return self.DEFAULT_COOLDOWN[key] or 8, false
end

function UD:SpellID(name)
  if not name then return nil end
  local key = tostring(name):gsub("%s*%(.-%)", ""):gsub("%s*/.*$", "")
  return self.SPELL_IDS[key]
end

UD.BUFF_INFO = {}
for _, b in ipairs(UD.BUFFS) do UD.BUFF_INFO[b.key] = b end

-- Primary stat per spec (Midnight assumptions; Devourer assumed Intellect - verify).
local SPEC_STAT = {
  [250] = "str", [251] = "str", [252] = "str",
  [577] = "agi", [581] = "agi", [1480] = "int",
  [102] = "int", [103] = "agi", [104] = "agi", [105] = "int",
  [1467] = "int", [1468] = "int", [1473] = "int",
  [253] = "agi", [254] = "agi", [255] = "agi",
  [62] = "int", [63] = "int", [64] = "int",
  [268] = "agi", [269] = "agi", [270] = "int",
  [65] = "int", [66] = "str", [70] = "str",
  [256] = "int", [257] = "int", [258] = "int",
  [259] = "agi", [260] = "agi", [261] = "agi",
  [262] = "int", [263] = "agi", [264] = "int",
  [265] = "int", [266] = "int", [267] = "int",
  [71] = "str", [72] = "str", [73] = "str",
}
-- Dominant damage school per spec. "mixed" = a large share of both (counts as partial for
-- Chaos Brand and Mystic Touch). Judgment calls from spec kits; adjust as tuning shifts.
local SPEC_SCHOOL = {
  [250] = "mixed", [251] = "mixed", [252] = "mixed",          -- DK: shadow/frost + physical
  [577] = "mixed", [581] = "mixed", [1480] = "magic",         -- DH: chaos/fire + physical; Devourer void (verify)
  [102] = "magic", [103] = "physical", [104] = "physical", [105] = "magic",
  [1467] = "magic", [1468] = "magic", [1473] = "magic",
  [253] = "physical", [254] = "physical", [255] = "physical",
  [62] = "magic", [63] = "magic", [64] = "magic",
  [268] = "physical", [269] = "physical", [270] = "magic",
  [65] = "magic", [66] = "mixed", [70] = "mixed",             -- Paladin: holy + physical
  [256] = "magic", [257] = "magic", [258] = "magic",
  [259] = "mixed", [260] = "physical", [261] = "mixed",       -- Rogue: poison/shadow + physical
  [262] = "magic", [263] = "mixed", [264] = "magic",
  [265] = "magic", [266] = "magic", [267] = "magic",
  [71] = "physical", [72] = "physical", [73] = "physical",
}

-- How much a profile benefits from a buff: 1 full, 0.5 partial, 0 none, nil = universal.
function UD:BuffBenefit(buff, profile)
  local a = buff and buff.affects
  if not a or a.all or not profile then return nil end
  if a.stat then return (profile.stat and a.stat[profile.stat]) or 0 end
  if a.school then return (profile.school and a.school[profile.school]) or 0 end
  if a.range then return (profile.range and a.range[profile.range]) or 0 end
  return 0
end

---------------------------------------------------------------------------
-- Builders (keep the tables below terse)
---------------------------------------------------------------------------
local function A(name, opts)
  local t = {}
  if opts then for k, v in pairs(opts) do t[k] = v end end
  t.name = name
  return t
end
-- CC: type, aoe, stop (can end a channel)
local function CC(name, ccType, opts)
  local t = A(name, opts)
  t.type = ccType
  return t
end

local TAL = { talent = true }
-- For entries a guide doesn't confirm (none at the moment): /ens verify lists them.
local VER = { verify = true }
local TAL_VER = { talent = true, verify = true }
local CORE = { talent = true, core = true }

---------------------------------------------------------------------------
-- Class bases. `caps[key]` = list of sources; specs add/remove on top.
---------------------------------------------------------------------------
local CLASSES = {
  -- Checked against Wowhead's Patch 12.1.0 class and spec "Abilities and Talents" guides
  -- (updated Aug 2026). TAL = optional talent (not guaranteed); CORE = a talent every build
  -- takes (interrupts, the class dispel/purge, a healer's signature cooldown): shown as a
  -- talent but counted as reliable.
  DEATHKNIGHT = {
    name = "Death Knight",
    buffs = {},
    caps = {
      interrupt = { A("Mind Freeze", CORE) },
      battle_rez = { A("Raise Ally") },
      group_defensive = { A("Anti-Magic Zone", TAL) },
    },
    cc = {
      CC("Death Grip", "knockback", { stop = true }),
      CC("Asphyxiate", "stun", { stop = true, talent = true }),
      CC("Blinding Sleet", "disorient", { aoe = true, stop = true, talent = true }),
    },
  },
  DEMONHUNTER = {
    name = "Demon Hunter",
    buffs = { "CHAOS_BRAND" },
    caps = {
      interrupt = { A("Disrupt") },
      purge = { A("Consume Magic", CORE) },
      group_defensive = { A("Darkness", TAL) },
    },
    cc = {
      CC("Chaos Nova", "stun", { aoe = true, stop = true, talent = true }),
      CC("Imprison", "incapacitate", { stop = true, talent = true }),
      -- Fel Eruption was removed from the game in Midnight.
      CC("Sigil of Misery", "disorient", { aoe = true, stop = true, talent = true }),
    },
  },
  DRUID = {
    name = "Druid",
    buffs = { "MARK_OF_THE_WILD" },
    caps = {
      battle_rez = { A("Rebirth") },
      soothe = { A("Soothe", TAL) },               -- choice node with Cyclone
      movement = { A("Stampeding Roar", TAL) },
      dispel_curse = { A("Remove Corruption", CORE) },
      dispel_poison = { A("Remove Corruption", CORE) },
    },
    cc = {
      CC("Incapacitating Roar", "incapacitate", { aoe = true, stop = true, talent = true }),  -- choice with Mighty Bash
      CC("Mighty Bash", "stun", { stop = true, talent = true }),
      CC("Typhoon", "knockback", { aoe = true, stop = true, talent = true }),
      CC("Ursol's Vortex", "knockback", { aoe = true, talent = true }),
      CC("Mass Entanglement", "root", { aoe = true, talent = true }),
      CC("Cyclone", "disorient", { stop = true, talent = true }),
    },
  },
  EVOKER = {
    name = "Evoker",
    buffs = { "BRONZE" },
    caps = {
      bloodlust = { A("Fury of the Aspects") },
      interrupt = { A("Quell", CORE) },
      -- Cauterizing Flame: Poison/Curse/Disease/Bleed on an ally (talent).
      dispel_poison = { A("Cauterizing Flame", TAL) },
      dispel_curse = { A("Cauterizing Flame", TAL) },
      dispel_disease = { A("Cauterizing Flame", TAL) },
      dispel_bleed = { A("Cauterizing Flame", TAL) },
      -- Oppressing Roar removes Enrage only with the Overawe talent.
      soothe = { A("Oppressing Roar (Overawe)", TAL) },
      group_defensive = { A("Zephyr", TAL) },
    },
    cc = {
      CC("Wing Buffet / Tail Swipe", "knockback", { aoe = true, stop = true }),
      CC("Sleep Walk", "disorient", { stop = true, talent = true }),
      CC("Landslide", "root", { aoe = true, talent = true }),
    },
  },
  HUNTER = {
    name = "Hunter",
    buffs = { "HUNTERS_MARK" },
    caps = {
      interrupt = { A("Counter Shot", CORE) },
      purge = { A("Tranquilizing Shot", CORE) },
      soothe = { A("Tranquilizing Shot", CORE) },
      bloodlust = { A("Primal Rage (pet)", { pet = true, conditional = "Ferocity pet out" }) },
      freedom = { A("Master's Call (pet)", { pet = true, conditional = "Cunning pet out" }) },
      external_defensive = { A("Roar of Sacrifice (pet)", { pet = true, talent = true }) },
    },
    cc = {
      CC("Intimidation", "stun", { stop = true, pet = true, talent = true }),
      CC("Freezing Trap", "incapacitate", { stop = true }),
      CC("Binding Shot", "root", { aoe = true, talent = true }),
    },
  },
  MAGE = {
    name = "Mage",
    buffs = { "ARCANE_INTELLECT" },
    caps = {
      interrupt = { A("Counterspell") },
      bloodlust = { A("Time Warp") },
      purge = { A("Spellsteal", CORE) },
      dispel_curse = { A("Remove Curse", CORE) },
      group_stealth = { A("Mass Invisibility", TAL) },  -- 40 yd, not on allies in combat
    },
    cc = {
      CC("Polymorph", "incapacitate", { stop = true }),
      CC("Frost Nova", "root", { aoe = true }),
      CC("Ring of Frost", "incapacitate", { aoe = true, talent = true }),
      -- Class choice node: Dragon's Breath or Supernova (every spec).
      CC("Dragon's Breath", "disorient", { aoe = true, stop = true, talent = true }),
      CC("Supernova", "knockback", { aoe = true, stop = true, talent = true }),
    },
  },
  MONK = {
    name = "Monk",
    buffs = { "MYSTIC_TOUCH" },
    caps = {
      interrupt = { A("Spear Hand Strike", CORE) },
      freedom = { A("Tiger's Lust", TAL) },
      dispel_poison = { A("Detox", CORE) },
      dispel_disease = { A("Detox", CORE) },
      -- Paralysis removes Enrage only with the Pressure Points talent.
      soothe = { A("Paralysis (Pressure Points)", TAL) },
    },
    cc = {
      CC("Leg Sweep", "stun", { aoe = true, stop = true }),
      CC("Paralysis", "incapacitate", { stop = true }),
      CC("Ring of Peace", "knockback", { aoe = true, stop = true, talent = true }),
      CC("Song of Chi-Ji", "disorient", { aoe = true, stop = true, talent = true }),  -- choice with Ring of Peace
    },
  },
  PALADIN = {
    name = "Paladin",
    buffs = {},
    caps = {
      freedom = { A("Blessing of Freedom", TAL) },
      external_defensive = { A("Blessing of Protection", TAL), A("Blessing of Sacrifice", TAL) },
      dispel_poison = { A("Cleanse Toxins", CORE) },
      dispel_disease = { A("Cleanse Toxins", CORE) },
      -- Spec notes: Intercession substitutes a combat rez only when no DK/Druid/Warlock.
      -- `fallback = true`: counts only when the group has no unconditional source.
      -- Baseline for every Paladin spec in 12.1.
      battle_rez = { A("Intercession", { conditional = "only when no DK/Druid/Warlock", fallback = true }) },
    },
    cc = {
      CC("Hammer of Justice", "stun", { stop = true }),
      CC("Blinding Light", "disorient", { aoe = true, stop = true, talent = true }),
      CC("Repentance", "incapacitate", { stop = true, talent = true }),
    },
  },
  PRIEST = {
    name = "Priest",
    buffs = { "FORTITUDE" },
    caps = {
      purge = { A("Dispel Magic", CORE) },
      dispel_magic = { A("Mass Dispel", { long = true, talent = true, core = true }) },
    },
    cc = {
      CC("Psychic Scream", "fear", { aoe = true, stop = true }),
      CC("Mind Control", "incapacitate", { stop = true, talent = true }),
    },
  },
  ROGUE = {
    name = "Rogue",
    buffs = {},
    caps = {
      interrupt = { A("Kick") },
      soothe = { A("Shiv", CORE) },  -- "dispelling all enrage effects"
      group_stealth = { A("Shroud of Concealment") },
    },
    cc = {
      CC("Kidney Shot", "stun", { stop = true }),
      CC("Blind", "disorient", { stop = true, talent = true }),
      CC("Gouge", "incapacitate", { stop = true, talent = true }),
      CC("Sap", "incapacitate", {}),
    },
  },
  SHAMAN = {
    name = "Shaman",
    buffs = { "SKYFURY" },
    caps = {
      interrupt = { A("Wind Shear", CORE) },
      bloodlust = { A("Bloodlust / Heroism") },
      purge = { A("Purge", CORE) },                -- choice with Greater Purge (also a purge)
      dispel_curse = { A("Cleanse Spirit", CORE) },
      dispel_poison = { A("Poison Cleansing Totem", TAL) },  -- choice with Tremor Totem; 2 min
      movement = { A("Wind Rush Totem", TAL) },
    },
    cc = {
      CC("Capacitor Totem", "stun", { aoe = true, stop = true, talent = true }),
      CC("Hex", "incapacitate", { stop = true, talent = true }),
      CC("Earthgrab Totem", "root", { aoe = true, talent = true }),
    },
  },
  WARLOCK = {
    name = "Warlock",
    buffs = {},
    caps = {
      battle_rez = { A("Soulstone") },
      interrupt = { A("Spell Lock (Felhunter)", { pet = true }) },
      purge = { A("Devour Magic (Felhunter)", { pet = true }) },
      dispel_magic = { A("Singe Magic (Imp)", { pet = true }) },  -- "the Imp provides magic dispelling"
      movement = { A("Demonic Gateway", TAL) },
    },
    cc = {
      CC("Fear", "fear", { stop = true }),
      CC("Shadowfury", "stun", { aoe = true, stop = true, talent = true }),  -- choice with Howl of Terror
      CC("Mortal Coil", "fear", { stop = true, talent = true }),
      CC("Howl of Terror", "fear", { aoe = true, stop = true, talent = true }),
    },
  },
  WARRIOR = {
    name = "Warrior",
    buffs = { "BATTLE_SHOUT" },
    caps = {
      interrupt = { A("Pummel") },
      group_defensive = { A("Rallying Cry", CORE) },
      external_defensive = { A("Intervene", TAL) },
    },
    cc = {
      CC("Intimidating Shout", "fear", { aoe = true, stop = true, talent = true }),
      CC("Storm Bolt", "stun", { stop = true, talent = true }),
      CC("Shockwave", "stun", { aoe = true, stop = true, talent = true }),
    },
  },
}

---------------------------------------------------------------------------
-- Specs. `add` merges into class caps, `set` replaces a cap list, `remove` deletes caps.
-- Spec IDs are the client's specialization IDs (GetSpecializationInfoByID).
---------------------------------------------------------------------------
local SPECS = {
  -- Death Knight
  [250] = { class = "DEATHKNIGHT", name = "Blood",   role = "TANK",    range = "melee",
            addCC = { CC("Gorefiend's Grasp", "knockback", { aoe = true, stop = true, talent = true }) } },
  [251] = { class = "DEATHKNIGHT", name = "Frost",   role = "DAMAGER", range = "melee" },
  [252] = { class = "DEATHKNIGHT", name = "Unholy",  role = "DAMAGER", range = "melee" },
  -- Demon Hunter. Devourer is new in Midnight.
  [577] = { class = "DEMONHUNTER", name = "Havoc",     role = "DAMAGER", range = "melee" },
  [581] = { class = "DEMONHUNTER", name = "Vengeance", role = "TANK",    range = "melee",
            addCC = { CC("Sigil of Silence", "silence", { aoe = true, stop = true, talent = true }),
                      CC("Sigil of Chains", "knockback", { aoe = true, stop = true, talent = true }) } },
  -- Devourer (spec 1480, confirmed by /ens verify): Void Nova replaces Chaos Nova. Range and
  -- primary stat aren't stated in the guide; ranged Intellect is assumed.
  [1480] = { class = "DEMONHUNTER", name = "Devourer", role = "DAMAGER", range = "ranged",
             removeCC = { "Chaos Nova" },
             addCC = { CC("Void Nova", "stun", { aoe = true, stop = true, talent = true }) } },
  -- Druid
  [102] = { class = "DRUID", name = "Balance",     role = "DAMAGER", range = "ranged",
            set = { interrupt = { A("Solar Beam", { long = true, talent = true, core = true }) } } },
  [103] = { class = "DRUID", name = "Feral",       role = "DAMAGER", range = "melee",
            set = { interrupt = { A("Skull Bash", CORE) } },
            addCC = { CC("Maim", "stun", { stop = true, talent = true }) } },
  [104] = { class = "DRUID", name = "Guardian",    role = "TANK",    range = "melee",
            set = { interrupt = { A("Skull Bash", CORE) } } },
  [105] = { class = "DRUID", name = "Restoration", role = "HEALER",  range = "ranged",
            set = {
              -- Improved Nature's Cure (Curse + Poison) is granted free to Restoration.
              dispel_magic = { A("Nature's Cure") },
              dispel_curse = { A("Nature's Cure") },
              dispel_poison = { A("Nature's Cure") },
              external_defensive = { A("Ironbark", CORE) },
            } },
  -- Evoker
  [1467] = { class = "EVOKER", name = "Devastation",  role = "DAMAGER", range = "ranged",
             add = { dispel_poison = { A("Expunge", TAL) } } },
  [1473] = { class = "EVOKER", name = "Augmentation", role = "DAMAGER", range = "ranged",
             add = { dispel_poison = { A("Expunge", TAL) } } },
  [1468] = { class = "EVOKER", name = "Preservation", role = "HEALER",  range = "ranged",
             -- Spec notes: Resto Shaman is the only healer with an interrupt this season.
             remove = { "interrupt" },
             set = {
               dispel_magic = { A("Naturalize") },
               dispel_poison = { A("Naturalize") },
               external_defensive = { A("Time Dilation", CORE) },
             } },
  -- Hunter
  [253] = { class = "HUNTER", name = "Beast Mastery", role = "DAMAGER", range = "ranged" },
  -- Marksmanship has no pet by default in 12.1 but its own baseline Bloodlust, Harrier's Cry;
  -- Master's Call through the Cunning talent; Intimidation via its Spotting Eagle (no pet).
  -- Bursting Shot was removed in Midnight (12.0); Scatter Shot is PvP-only in 12.1.
  [254] = { class = "HUNTER", name = "Marksmanship",  role = "DAMAGER", range = "ranged",
            set = { bloodlust = { A("Harrier's Cry") },
                    freedom = { A("Master's Call", TAL) } },
            remove = { "external_defensive" },
            removeCC = { "Intimidation" },
            addCC = { CC("Intimidation", "stun", { stop = true, talent = true }) } },
  [255] = { class = "HUNTER", name = "Survival",      role = "DAMAGER", range = "melee",
            set = { interrupt = { A("Muzzle", CORE) } } },
  -- Mage
  [62] = { class = "MAGE", name = "Arcane", role = "DAMAGER", range = "ranged" },
  [63] = { class = "MAGE", name = "Fire",   role = "DAMAGER", range = "ranged" },
  [64] = { class = "MAGE", name = "Frost",  role = "DAMAGER", range = "ranged" },
  -- Monk
  [268] = { class = "MONK", name = "Brewmaster", role = "TANK",    range = "melee" },
  [269] = { class = "MONK", name = "Windwalker", role = "DAMAGER", range = "melee" },
  [270] = { class = "MONK", name = "Mistweaver", role = "HEALER",  range = "ranged",
            remove = { "interrupt" },
            set = {
              dispel_magic = { A("Detox") },
              -- Poison and Disease need Improved Detox.
              dispel_poison = { A("Detox", CORE) },
              dispel_disease = { A("Detox", CORE) },
              external_defensive = { A("Life Cocoon", CORE) },
              freedom = { A("Tiger's Lust") },   -- baseline for Mistweaver
            } },
  -- Paladin
  [65] = { class = "PALADIN", name = "Holy",        role = "HEALER",  range = "ranged",
           set = {
             dispel_magic = { A("Cleanse") },
             -- Poison and Disease need Improved Cleanse.
             dispel_poison = { A("Cleanse", CORE) },
             dispel_disease = { A("Cleanse", CORE) },
             group_defensive = { A("Aura Mastery", CORE) },
           } },
  [66] = { class = "PALADIN", name = "Protection",  role = "TANK",    range = "melee",
           set = { interrupt = { A("Rebuke", CORE), A("Avenger's Shield", TAL) } },
           add = { external_defensive = { A("Blessing of Spellwarding", TAL) } } },
  [70] = { class = "PALADIN", name = "Retribution", role = "DAMAGER", range = "melee",
           set = { interrupt = { A("Rebuke", CORE) } } },
  -- Priest
  [256] = { class = "PRIEST", name = "Discipline", role = "HEALER",  range = "ranged",
            set = {
              dispel_magic = { A("Purify"), A("Mass Dispel", { long = true, talent = true, core = true }) },
              dispel_disease = { A("Improved Purify", CORE) },
              external_defensive = { A("Pain Suppression", CORE) },
              group_defensive = { A("Power Word: Barrier", TAL) },  -- choice with Ultimate Penitence
            } },
  [257] = { class = "PRIEST", name = "Holy",       role = "HEALER",  range = "ranged",
            set = {
              dispel_magic = { A("Purify"), A("Mass Dispel", { long = true, talent = true, core = true }) },
              dispel_disease = { A("Improved Purify", CORE) },
              external_defensive = { A("Guardian Spirit", CORE) },
            },
            addCC = { CC("Holy Word: Chastise", "incapacitate", { stop = true, talent = true }) } },
  [258] = { class = "PRIEST", name = "Shadow",     role = "DAMAGER", range = "ranged",
            set = {
              interrupt = { A("Silence", { long = true }) },
              dispel_disease = { A("Purify Disease", CORE) },
            } },  -- Psychic Horror was removed in Midnight (12.0).
  -- Rogue (Between the Eyes is no longer a stun in 12.1)
  [259] = { class = "ROGUE", name = "Assassination", role = "DAMAGER", range = "melee" },
  [260] = { class = "ROGUE", name = "Outlaw",        role = "DAMAGER", range = "melee" },
  [261] = { class = "ROGUE", name = "Subtlety",      role = "DAMAGER", range = "melee" },
  -- Shaman. Thunderstorm is Elemental-only in Midnight.
  [262] = { class = "SHAMAN", name = "Elemental",   role = "DAMAGER", range = "ranged",
            addCC = { CC("Thunderstorm", "knockback", { aoe = true, stop = true }) } },
  [263] = { class = "SHAMAN", name = "Enhancement", role = "DAMAGER", range = "melee" },
  [264] = { class = "SHAMAN", name = "Restoration", role = "HEALER",  range = "ranged",
            set = {
              dispel_magic = { A("Purify Spirit") },
              dispel_curse = { A("Purify Spirit", CORE) },   -- Curse needs Improved Purify Spirit
              dispel_poison = { A("Poison Cleansing Totem", TAL) },
              group_defensive = { A("Spirit Link Totem", CORE) },
            } },
  -- Warlock (Demonology uses a Felguard: Axe Toss stun-interrupt; no Felhunter purge.
  -- Grimoire: Fel Ravager gives a second interrupt.)
  [265] = { class = "WARLOCK", name = "Affliction",  role = "DAMAGER", range = "ranged" },
  [266] = { class = "WARLOCK", name = "Demonology",  role = "DAMAGER", range = "ranged",
            set = { interrupt = { A("Axe Toss (Felguard)", { pet = true }), A("Spell Lock (Fel Ravager)", TAL) } },
            remove = { "purge" } },
  [267] = { class = "WARLOCK", name = "Destruction", role = "DAMAGER", range = "ranged" },
  -- Warrior
  [71] = { class = "WARRIOR", name = "Arms",       role = "DAMAGER", range = "melee" },
  [72] = { class = "WARRIOR", name = "Fury",       role = "DAMAGER", range = "melee" },
  [73] = { class = "WARRIOR", name = "Protection", role = "TANK",    range = "melee",
           addCC = { CC("Disrupting Shout", "silence", { aoe = true, stop = true, talent = true }) } },
}

-- Healers other than Resto Shaman get no interrupt (spec notes); the class bases above
-- give Druid/Paladin/Priest no default interrupt, and Evoker/Monk healers remove theirs.

---------------------------------------------------------------------------
-- Resolve class + spec into flat spec profiles
---------------------------------------------------------------------------
local function CopyList(list)
  local out = {}
  for i = 1, #list do out[i] = ns.Util.DeepCopy(list[i]) end
  return out
end

local function DeriveCCCaps(profile)
  -- Turn the cc list into stop/aoe_stop/knockback/root capability sources.
  for _, c in ipairs(profile.cc) do
    local flags = { talent = c.talent, pet = c.pet, verify = c.verify }
    if c.stop then
      profile.caps.stop = profile.caps.stop or {}
      table.insert(profile.caps.stop, A(c.name, flags))
      if c.aoe then
        profile.caps.aoe_stop = profile.caps.aoe_stop or {}
        table.insert(profile.caps.aoe_stop, A(c.name, flags))
      end
    end
    if c.type == "knockback" then
      profile.caps.knockback = profile.caps.knockback or {}
      table.insert(profile.caps.knockback, A(c.name, flags))
    elseif c.type == "root" then
      profile.caps.root = profile.caps.root or {}
      table.insert(profile.caps.root, A(c.name, flags))
    end
  end
end

UD.classes = {}
UD.specs = {}

for classFile, cls in pairs(CLASSES) do
  UD.classes[classFile] = { name = cls.name, specs = {} }
end

for specID, s in pairs(SPECS) do
  local cls = CLASSES[s.class]
  local p = {
    id = specID, class = s.class, name = s.name, role = s.role, range = s.range,
    verify = s.verify, buffs = {}, caps = {}, cc = {},
  }
  for i, b in ipairs(cls.buffs) do p.buffs[i] = b end
  for key, list in pairs(cls.caps) do p.caps[key] = CopyList(list) end
  if s.remove then for _, key in ipairs(s.remove) do p.caps[key] = nil end end
  if s.set then for key, list in pairs(s.set) do p.caps[key] = CopyList(list) end end
  if s.add then
    for key, list in pairs(s.add) do
      p.caps[key] = p.caps[key] or {}
      for _, e in ipairs(list) do table.insert(p.caps[key], ns.Util.DeepCopy(e)) end
    end
  end
  p.stat, p.school = SPEC_STAT[specID], SPEC_SCHOOL[specID]
  p.cc = CopyList(cls.cc)
  if s.removeCC then
    local drop = {}
    for _, n in ipairs(s.removeCC) do drop[n] = true end
    for i = #p.cc, 1, -1 do if drop[p.cc[i].name] then table.remove(p.cc, i) end end
  end
  if s.addCC then for _, c in ipairs(s.addCC) do table.insert(p.cc, ns.Util.DeepCopy(c)) end end
  if s.verify then
    -- Whole spec unconfirmed: flag every source.
    for _, list in pairs(p.caps) do for _, e in ipairs(list) do e.verify = true end end
  end
  DeriveCCCaps(p)
  UD.specs[specID] = p
  table.insert(UD.classes[s.class].specs, specID)
end

-- Stable ordering for pickers.
UD.classOrder = {}
for classFile in pairs(UD.classes) do table.insert(UD.classOrder, classFile) end
table.sort(UD.classOrder, function(a, b) return UD.classes[a].name < UD.classes[b].name end)
for _, cls in pairs(UD.classes) do table.sort(cls.specs) end

---------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------
function UD:GetSpec(specID) return specID and self.specs[specID] or nil end

-- Display name, localized via the client when available.
function UD:SpecName(specID)
  local p = self.specs[specID]
  if not p then return "Unknown" end
  local locName = ns.API.GetSpecInfoByID(specID)
  return locName or p.name
end

function UD:ClassName(classFile)
  if classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] then
    return LOCALIZED_CLASS_NAMES_MALE[classFile]
  end
  local c = self.classes[classFile]
  return c and c.name or tostring(classFile or "?")
end

function UD:SpecsForRole(role)
  local out = {}
  for _, classFile in ipairs(self.classOrder) do
    for _, id in ipairs(self.classes[classFile].specs) do
      if not role or self.specs[id].role == role then table.insert(out, id) end
    end
  end
  return out
end

function UD:IsSoft(entry)
  -- A CORE talent (one every build takes) is shown as a talent but counts as reliable.
  return entry and (entry.long or (entry.talent and not entry.core) or entry.pet or entry.conditional or entry.verify) and true or false
end

-- Sources of `key` usable under the current settings (talent sources may be excluded).
function UD:Sources(profile, key, settings)
  local list = profile and profile.caps[key]
  if not list then return nil end
  local countTalents = not settings or settings.countTalentSources ~= false
  local out
  for _, e in ipairs(list) do
    if countTalents or not e.talent or e.core then
      out = out or {}
      table.insert(out, e)
    end
  end
  return out
end

-- Profile for a member whose class is known but spec is pending: only what EVERY spec of
-- the class provides (intersection), so we never over-credit an unknown spec.
local classCommon = {}
function UD:ClassCommonProfile(classFile)
  if classCommon[classFile] then return classCommon[classFile] end
  local cls = self.classes[classFile]
  if not cls or #cls.specs == 0 then return nil end
  local first = self.specs[cls.specs[1]]
  local p = { id = 0, class = classFile, name = "Spec pending", role = nil, range = nil,
              pending = true, buffs = {}, caps = {}, cc = {} }
  for _, field in ipairs({ "stat", "school", "range" }) do
    local v = first[field]
    for i = 2, #cls.specs do
      if self.specs[cls.specs[i]][field] ~= v then v = nil; break end
    end
    p[field] = v
  end
  for _, b in ipairs(first.buffs) do p.buffs[#p.buffs + 1] = b end
  for key, list in pairs(first.caps) do
    local inAll = true
    for i = 2, #cls.specs do
      if not self.specs[cls.specs[i]].caps[key] then inAll = false; break end
    end
    if inAll then
      local e = ns.Util.DeepCopy(list[1]); e.name = e.name .. " (assumed)"
      p.caps[key] = { e }
    end
  end
  -- CC: names shared by every spec.
  for _, c in ipairs(first.cc) do
    local inAll = true
    for i = 2, #cls.specs do
      local found = false
      for _, c2 in ipairs(self.specs[cls.specs[i]].cc) do if c2.name == c.name then found = true; break end end
      if not found then inAll = false; break end
    end
    if inAll then table.insert(p.cc, ns.Util.DeepCopy(c)) end
  end
  classCommon[classFile] = p
  return p
end
