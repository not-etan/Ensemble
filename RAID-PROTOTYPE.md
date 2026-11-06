# Raid test build (raid-prototype branch)

A raid module for Ensemble, built for the author's in-game testing. **Not released, not on `main`.** If the idea goes ahead it becomes one addon with an automatic Mythic+ / Raid switch; if not, everything below is removed.

## What's on this branch, and nowhere else

| Path | What it is |
|---|---|
| `Ensemble_Raid/` | The raid folder (its own TOC, saved variables `EnsembleRaidDB`, depends on Ensemble) |
| `tests/raid/` | Its tests (`python3 tests/raid/run_raid_tests.py`, both engines, reuses `tests/wowstub.lua`) |
| `tools/raid/package_raid.sh` | Builds `dist/Ensemble-<version>+Raid-<version>.zip` with both folders |
| `RAID-PROTOTYPE.md` | This file |

To remove the prototype: delete those four paths (or the branch). Nothing in `Ensemble/` depends on them. The only core change it needs is already on `main`: Ensemble publishes its namespace as `EnsembleCore` and its widgets on `UI.Kit` (test block 84), which is harmless without the raid folder.

## Install for testing

Unzip the test zip into `World of Warcraft/_retail_/Interface/AddOns` (it holds `Ensemble/` and `Ensemble_Raid/`), then restart the game (a new addon isn't picked up by `/reload`).

## What it does

- **Mode switch** in Ensemble's header, left of What's new: Auto (Raid in a raid group or inside a season raid or Lair, Mythic+ otherwise), or Mythic+ / Raid by hand (until you leave a group).
- **Raid tabs:** Roster, Bosses, Plan, Settings (Ensemble's own settings).
- **Context bar:** raid (The Venomous Abyss, The Unbinding of Kith'ix, The Tidebound Grotto Lair), difficulty (LFR / World use Normal's mechanics), boss.
- **Roster:** your raid by group (specs read one at a time out of combat), or a planner list when you're not in a group; **Needs** for the boss and difficulty (tanks, healers, Bloodlust, battle rez, dispels, interrupts, class utility, class buffs), higher-difficulty needs hidden with a count; Post gaps.
- **Bosses:** the boss list in your order (bosses 2-5 can move: the wings); **Learner** view per role (what kills raids here, each phase's mechanics, Bloodlust, "Stepping up: what Heroic adds"); **Leader** view (before the pull, calls with one-click posting, suggested markers, taking the group up a difficulty); Post pre-pull / calls / dangers; Build the plan.
- **Plan:** rows per boss and difficulty (soak groups, kick orders, dispels, Bloodlust...) plus your own rows; click a row, then players; markers per row; Suggest fills empty rows from the roster; Post to raid / raid warning (leader or assist) / Copy. Markers are named in chat as `{rtN}` (icons for everyone); the addon never places or sets markers.
- **Boss window:** follows the fight (jumps to the boss on pull by name, next boss on a kill), shows your jobs from the plan, Bloodlust and your role's mechanics.
- **`/ens verify`:** a "Raid test module" section (counts only, never a player's name).

Data: Normal baseline with Heroic and Mythic labeled, from Mythic Trap, Method.gg, Icy Veins and wow.gg (checked November 6, 2026; sources in `Ensemble_Raid/Data.lua`).
