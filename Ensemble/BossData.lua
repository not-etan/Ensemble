-- Ensemble / BossData.lua
-- HAND-MAINTAINED. Short boss cards: what each role does on each boss, in our own words.
--
-- Sources (third pass, October 2026, Patch 12.1): Method.gg's Season 2 dungeon guides,
-- Icy Veins' Season 2 dungeon guides, Wowhead's Midnight Season 2 dungeon overviews and
-- Raider.IO's Season 2 quick boss guides (read as guides only: no Raider.IO data is used),
-- plus in-game checks (dungeon journal) by the author. A line at least two of them support is unmarked; a
-- detail only one states, or where they disagree, is marked `nv` (needs verification) and
-- shows as unconfirmed until checked in game. Rechecked against every hotfix through
-- October 6, 2026: no line needed changing (the changes were timing and damage only).
-- Rechecked against patch 12.1.5's dungeon tuning (October 13, 2026): no line needed
-- changing (damage, health and cooldown numbers; Living Bomb is trash, in DungeonData).
--
-- Card fields
--   name     boss name as the game shows it (also used to match encounters by name)
--   reqs     DungeonData requirement IDs that happen on this boss: the card adds your
--            kick / dispel jobs for them from the plan ("Your assignments" lines)
--   lines    { role, text, nv? }  role = "ALL" | "TANK" | "HEAL" | "DPS"
-- Lines say WHAT TO DO, as short imperatives (aim for under ~60 characters). The why
-- belongs in the Dungeons primer (DungeonData notes), not on the card.
local _, ns = ...

local BD = { list = {} }
ns.BossData = BD

BD.ROLES = { "ALL", "TANK", "HEAL", "DPS" }

local function L(role, text, nv) return { role = role, text = text, nv = nv or nil } end

BD.list.AltarOfFangs = {
  { name = "Rav'i", reqs = { "AOF_REGURGITATE" }, lines = {
    L("ALL", "Spread loosely for Triple Shot; dodge Regurgitate."),
    L("ALL", "Ssscavenging: catch every Messy Eater chunk."),
    L("TANK", "Keep Rav'i off piles with Fresh Meat."),
    L("TANK", "Defensive for Hydrastrike."),
    L("HEAL", "Top everyone before Ravenous Stomp."),
    L("HEAL", "Disease-dispel anyone hit by Regurgitate."),
    L("DPS", "Pool damage; break the Ssscavenging shield fast."),
  } },
  { name = "The Writhing Coil", reqs = { "AOF_TOXIC_ATROPHY", "AOF_FREEDOM" }, lines = {
    L("ALL", "Kick all three Toxic Atrophy casts."),
    L("ALL", "Death Rattle: run 10 yards out until your tether turns green."),
    L("ALL", "Dodge Burrowing Charge, Venom Jet and Undermining."),
    L("TANK", "Defensive for Tail Scythe; aim Venom Jet away; stack the Writhes."),
    L("HEAL", "Heal through Synchronized Venom; cooldown for Death Rattle."),
    L("DPS", "Uncoil: stack, CC and burn the Writhes."),
  } },
  { name = "Zul'jan", reqs = {}, lines = {
    L("ALL", "Soak all four Ritual of the Fang beams from set spots."),
    L("ALL", "Clear Ritual Venom: stand together in one Boneslicer."),
    L("ALL", "Dodge Axegrinder axes; step out of blood pools."),
    L("TANK", "Defensive for Chop Down."),
    L("HEAL", "Top players before each Ritual soak."),
  } },
}

BD.list.MurderRow = {
  { name = "Kystia Manaheart", reqs = { "MR_MIRROR_IMAGES", "MR_CORRODING" }, lines = {
    L("ALL", "Damage Nibbles, not Kystia."),
    L("ALL", "Nibbles at 20%: burst Kystia while she's stunned."),
    L("ALL", "Step out of Fel Nova; dodge Fel Spray."),
    L("TANK", "Face Nibbles' Fel Spray away from the group."),
    L("HEAL", "Dispel Corroding Spittle (Magic); cooldown each Destabilized."),
    L("DPS", "Kick or CC every Mirror Image."),
  } },
  { name = "Zaen Bladesorrow", reqs = { "MR_HEARTSTOP" }, lines = {
    L("ALL", "Murder In A Row: hide behind your own barrel."),
    L("ALL", "Dodge thrown barrels and Fire Bomb blasts."),
    L("TANK", "Defensive for Envenom."),
    L("HEAL", "Dispel Heartstop Poison; bleed-cleanse after Murder In A Row."),
    L("DPS", "Fire Bomb on you: stand by the Fel-Infused Freight."),
  } },
  { name = "Xathuux the Annihilator", reqs = {}, lines = {
    L("ALL", "Spread loosely for Infernal Crush."),
    L("ALL", "Axe Toss on you: bring it to the boss."),
    L("TANK", "Tank at the edge, facing out."),
    L("TANK", "Demonic Rage: kite slowly along the edge."),
    L("HEAL", "Cooldown for Demonic Rage plus Infernal Crush."),
    L("DPS", "Kill the Legion Axe fast; burst during Demonic Rage."),
  } },
  { name = "Lithiel Cinderfury", reqs = { "MR_SPARE" }, lines = {
    L("ALL", "Malefic Wave: after the cast, take the gateway to the safe side."),
    L("ALL", "Fingers of Gul'dan: stay close, circles overlapping."),
    L("TANK", "Kite the Infernal away; pick up the Vilefiends."),
    L("HEAL", "Heal through Searing Fel Flame and wave damage."),
    L("DPS", "Kick Chaos Bolt; kill every imp and Vilefiend before the wave."),
  } },
}

BD.list.DenOfNalorakk = {
  { name = "The Hoardmonger", reqs = { "DN_TOXIC_SPORES" }, lines = {
    L("ALL", "Soak every Rotten Mushroom within 12s; spread the soaks."),
    L("ALL", "Dodge the slams and the bone spikes."),
    L("ALL", "Hearty Bellow: don't get knocked onto spikes."),
    L("TANK", "Keep him off bone spikes; soak mushrooms too."),
    L("HEAL", "Dispel Toxic Spores (Poison); heal through the Bellow."),
  } },
  { name = "Sentinel of Winter", reqs = { "DN_WINTERS_SHROUD", "DN_GLACIAL_TORMENT", "DN_FREEDOM" }, lines = {
    L("ALL", "Move together; leave Raging Squall tornadoes behind."),
    L("ALL", "Frozen Tempest: stand in the eye or a Snowdrift."),
    L("ALL", "Dodge Frostspike circles; soak each Rimeshatter."),
    L("TANK", "Tank the boss on an add's snow pile."),
    L("HEAL", "Dispel Glacial Torment (Magic), worst targets first."),
    L("DPS", "Kill the Shivercores; kick Winter's Shroud."),
  } },
  { name = "Nalorakk", reqs = {}, lines = {
    L("ALL", "Echoing Maul: drop your Echo at the wall, near the others."),
    L("ALL", "Overwhelming Onslaught: stand behind Zul'jarra's shield."),
    L("ALL", "Fury of the War God: intercept every Echo."),
    L("TANK", "Never face away from an Echo; run back in for Forceful Slam."),
    L("HEAL", "Cooldown for Overwhelming Onslaught."),
  } },
}

BD.list.TheBlindingVale = {
  { name = "Lightblossom Trinity", reqs = { "BV_SPARE", "BV_BLEEDS" }, lines = {
    L("ALL", "Soak every Lightblossom Beam blossom right away."),
    L("ALL", "Thornblade on you: step out of the group."),
    L("ALL", "Kick Kezkitt's Light Bolt on a rotation."),
    L("TANK", "Defensive for Bedrock Slam; start at a wall."),
    L("HEAL", "Heal Thornblade targets; cooldown after Bedrock Slam."),
  } },
  { name = "Ikuzz the Light Hunter", reqs = { "BV_FREEDOM" }, lines = {
    L("ALL", "Avoid Bloodthorn Roots; free rooted allies."),
    L("ALL", "Verdant Stomp: don't get knocked into roots."),
    L("ALL", "Gaze on you: run, dragging him over roots."),
    L("TANK", "Keep Ikuzz near rooted players."),
    L("HEAL", "Save cooldowns for 50%; external a caught Gaze target."),
  } },
  { name = "Lightwarden Ruia", reqs = { "BV_WARDENS_WRATH" }, lines = {
    L("ALL", "Moonkin: dodge Lightfall; Lightfire players stack away."),
    L("ALL", "Bear: marked players hold still; others spread."),
    L("ALL", "Below 40%: expect every ability, fast."),
    L("TANK", "Bear: self-heal through Grievous Thrash."),
    L("HEAL", "Heal Grievous Thrash targets to full."),
    L("DPS", "Kick Warden's Wrath."),
  } },
  { name = "Ziekket", reqs = { "BV_LIGHTSPORE" }, lines = {
    L("ALL", "Soak Lightbloom's Essence orbs; spread the stacks."),
    L("ALL", "Fight at the platform edge."),
    L("TANK", "Defensive for Thornspike; group the Lashers."),
    L("HEAL", "Heal through Oozing Xylem; spot-heal high orb stacks."),
    L("DPS", "Kill Lashers, kick Lightspore Shot, beam their bodies."),
  } },
}

BD.list.VoidscarArena = {
  { name = "Taz'Rah", reqs = {}, lines = {
    L("ALL", "Nether Dash: spread near the edge; dodge others' lines."),
    L("ALL", "Keep moving; dodge Dark Bloom orbs."),
    L("ALL", "Clump Umbral Rupture puddles; avoid Void Fissures."),
    L("TANK", "Defensive for Void Blast; don't land in puddles."),
    L("HEAL", "Cooldown for Dark Bloom; heal Nether Dash targets."),
  } },
  { name = "Atroxus", reqs = {}, lines = {
    L("ALL", "Stay close to the boss; sidestep Noxious Breath."),
    L("ALL", "Avoid Poison Splash pools."),
    L("TANK", "Kite the Toxic Creeper; defensive for Hulking Claw."),
    L("HEAL", "Poison-dispel the tank after Hulking Claw."),
    L("DPS", "Kill each Toxic Creeper fast."),
  } },
  { name = "Charonus", reqs = { "VA_FREEDOM" }, lines = {
    L("ALL", "Don't get pulled into a Singularity."),
    L("ALL", "Spread for Cosmic Crash; Void Cascade on you: run."),
    L("TANK", "Defensive for Dark Waves; keep him centered between Singularities."),
    L("HEAL", "Spot-heal Gravitic Orb targets."),
    L("DPS", "Kite your Gravitic Orb into a Singularity."),
  } },
}

BD.list.RubyLifePools = {
  { name = "Melidrussa Chillworn", reqs = { "RLP_FRIGID_SHARD", "RLP_COLD_CLAWS", "RLP_GROUP_DAMAGE" }, lines = {
    L("ALL", "Stack on the boss for Hailburst; move as ice fills."),
    L("ALL", "Chillstorm: leave the center; avoid Hailbombs."),
    L("TANK", "Pick up the Infused Whelps."),
    L("HEAL", "Dispel Cold Claws off the tank; cooldown for Frost Overload."),
    L("DPS", "Kick Frigid Shard; break Ice Bulwark fast."),
  } },
  { name = "Kokia Blazehoof", reqs = { "RLP_BLAZE_VOLLEY" }, lines = {
    L("ALL", "Ritual on you: 12 yards from others, near the boss."),
    L("ALL", "Dodge Molten Boulders; leave when the Firestorm dies."),
    L("TANK", "Defensive for every Searing Blows."),
    L("HEAL", "Cooldown for Inferno while the Firestorm lives."),
    L("DPS", "Kill the Firestorm fast; kick Blaze Volley."),
  } },
  { name = "Kyrakka and Erkhart Stormvein", reqs = { "RLP_STORMSLAM" }, lines = {
    L("ALL", "Inferno Spit on you: drop it away from the group."),
    L("ALL", "Winds go NW, SW, SE, NE: place fire accordingly."),
    L("ALL", "At 40%, they join up: save defensives."),
    L("TANK", "Tank Erkhart to 40%, then Kyrakka."),
    L("HEAL", "Dispel Stormslam (Magic) off the tank."),
    L("DPS", "Focus Kyrakka; stop casting for Interrupting Cloudburst."),
  } },
}

BD.list.KingsRest = {
  { name = "The Golden Serpent", reqs = { "KR_ANIMATED_GOLD", "KR_GROUP_DAMAGE" }, lines = {
    L("ALL", "Spit Gold on you: drop it by the other gold puddles."),
    L("TANK", "Defensive for Tail Thrash; pull him away from the gold."),
    L("HEAL", "Cooldown for Serpentine Gust."),
    L("DPS", "Kill, slow and CC every Animated Gold."),
  } },
  { name = "Mchimba the Embalmer", reqs = { "KR_WRETCHED" }, lines = {
    L("ALL", "Burn Corruption: drop the fire at a wall."),
    L("ALL", "Entomb: click the shaking coffin; trapped player spams Struggle."),
    L("ALL", "Drain Fluids on you: use a defensive."),
    L("HEAL", "Top everyone before Awakening Slam; heal Drain Fluids targets to 90%."),
    L("DPS", "Kill the mummies; kick Wretched Discharge."),
  } },
  { name = "The Council of Tribes", reqs = { "KR_POISON_NOVA", "KR_BLEEDS" }, lines = {
    L("ALL", "Dodge Whirling Axes; stack on the Barrel Through target."),
    L("TANK", "Tank Kula center; kite after Debilitating Backhand."),
    L("HEAL", "Heal Severing Axe targets; cooldown for Arc Lightning."),
    L("DPS", "Kick Poison Nova; totems: Explosive, Thundering, Torrent."),
  } },
  { name = "Dazar, the First King", reqs = { "KR_DEATHLY_ROAR", "KR_TANK", "KR_GROUP_DAMAGE" }, lines = {
    L("ALL", "Spread for Aerial Smash; dodge spears and gold swirls."),
    L("ALL", "Furthest from Quaking Leap: combat drop."),
    L("TANK", "Defensive for Blade Combo; face away in Gilded Destruction."),
    L("HEAL", "Big cooldown for Gilded Destruction."),
    L("DPS", "Kill Reban first; kick Deathly Roar."),
  } },
}

BD.list.TempleOfSethraliss = {
  { name = "Adderis and Aspix", reqs = {}, lines = {
    L("ALL", "Gale Force: spread at the back wall, then stack to soak."),
    L("ALL", "Tempest Winds on you: drop it out of the way."),
    L("ALL", "Switch to whichever boss can be damaged."),
    L("TANK", "Defensive for Overload."),
    L("HEAL", "Spot-heal Gust targets."),
  } },
  { name = "Merektha", reqs = { "TOS_POISON_SPIT", "TOS_KNOT_OF_SNAKES" }, lines = {
    L("ALL", "Knot of Snakes: stack in melee for one AoE CC."),
    L("ALL", "Thunder Spit on you: drop it at the edge; dodge Burrow."),
    L("TANK", "Defensive for Lightning Bite; park Storm Serpents by the edge."),
    L("HEAL", "Cooldown for Serpentstorm; Poison-dispel the DoTs."),
    L("DPS", "Kill the Storm Serpent first; kick Poison Spit."),
  } },
  { name = "Galvazzt", reqs = { "TOS_GROUP_DAMAGE" }, lines = {
    L("ALL", "Stand between each Lightning Spire and the boss."),
    L("ALL", "Rotate soaks and defensives."),
    L("TANK", "Move him off Induction fields; let others soak."),
    L("HEAL", "Heal the spire soakers."),
  } },
  { name = "Avatar of Sethraliss", reqs = { "TOS_FLAME_SHOCK", "TOS_TORMENTORS" }, lines = {
    L("ALL", "Kill every Essence Defiler first."),
    L("ALL", "Latent Hex on you: drop it at the room's edge."),
    L("TANK", "Defensive for Tainted Strike and Vile Charge."),
    L("HEAL", "Heal the Avatar after each Defiler dies; kite Tormentors."),
    L("DPS", "Soak Lifeforce orbs; kick Flame Shock; AoE Tormentors."),
  } },
}
