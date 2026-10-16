# Changelog

## 1.2.1
- **Critical gaps, full or partial:** an applicant who fully closes a critical gap (with a dependable ability of their own) still never rates below anyone who doesn't. One who only covers it with a weaker source (a talent, a pet, a long cooldown, a conditional or unconfirmed ability, or a spec the game hasn't shared) now gets less credit: at least halfway from the weakest pick to the best pick that closes nothing, and never raised further. Before, either kind was raised to the top non-closer. Example: Temple of Sethraliss, Protection and Fury Warrior, +12: a Shadow Priest covering Imbued Conduction with Mass Dispel alone rated 100 (Great), tied with an Elemental Shaman who closes far more; now 50 (Good). The same rule applies to the listing stripe for groups you could join.
- **"Why 78?" adds up:** the steps now show in the order they apply, each ending on the number the next starts from: the pick position ("this one closes 74.0, so 32/100 as a pick"), the experience blend ("70% of utility 32 + 30% of experience 65 = 42"), then the critical-gap rule with the ability that triggered it. Before, the position line showed the already-raised number and the experience line showed the final score instead of the blend.
- **Preview on the Composition tab:** only Needs rows whose status changes are marked "was MISSING" (or "new"); every row used to say "new".
- **Invite buttons** switch to "Invited" when you invite someone with the Group Finder's own button, on the Applicants tab and under the Composition slots.
- **Best value here** (Dungeon tab) leaves out needs you've unticked and, with "Hide low-severity requirements" on, low entries, like the walkthrough beside it.
- **Groups you could join** are rated on equal terms: every spec you're compared with gets Bloodlust assumed like you do, and the rating treats talents as uncertain for everyone (as a host sees you), so you never rate above the best spec of your role. "What you'd add" still counts the talents you have.
- **Chat posts are never cut:** a line too long for one chat message carries on to the next ("Ryvax (cont.): ..."), in the assignments post, the Bloodlust line, boss cards and the gaps post. Nothing is dropped any more (the assignments post used to drop backups and mob names first, then cut with "..."). The gaps post now uses the copy window when the game is blocking addon chat, like the other posts.
- **Faster with many applicants:** a new or departing application re-rates only that application instead of everyone (about 4 ms instead of about 75 ms with 12 applicants and 4 open slots, plain Lua 5.1 in the test harness).
- **Inside a key:** enemy forces and the roster scan treat values the game hides from addons as unknown instead of risking an error, and a roster scan that errors no longer escapes its timer. `/kc verify` reports both, and now also lists the functions the addon can do without and what each one missing costs.
- **Reset** (`/kc reset`, Settings > Data) says everything it wipes: saved comps, the planner comp, every setting, run history, boss-card edits, Bloodlust timing and the error log. It also clears this session's hand-picked assignments and boss progress.
- **Inside a key:** party inspects (how the addon learns other players' specs) now treat IDs the game hides from addons as unknown, like the roster scan already did, and an error inside the inspect timer is contained and reported by `/kc verify` instead of escaping.
- **Docs:** the overview is shorter, with a new opening, and the README and overview no longer suggest support for other addons: Mythic Dungeon Tools route features carry a note that Keystone Command isn't affiliated with MDT, and the Raider.IO panel mention is gone.
- **Releases** are now packaged and uploaded to CurseForge, Wago and GitHub automatically. The zip holds just the `KeystoneCommand` folder (with `LICENSE.txt` inside); the full guide is on the wiki instead of a readme beside the folder.
- The listing-marker frames are kept in the addon's own table instead of a field on the Group Finder's result buttons, and the listing fit cache is cleared with each new search.

## 1.2.0
- **Fit ratings mean "how good a pick is this person for this slot?"** An applicant's rating now compares them with every other spec of their role for that slot: 100 is as good as the best pick, 0 no better than the weakest. Ratings used to bunch up at Good and Great because the look-ahead (how well the rest of the group could still be filled) made up most of the score, and with slots open it was nearly the same for everyone. The look-ahead still shows in the headline ("OK if the last slot brings Poison dispel") and the notes, but no longer changes the rating.
- New bands from the measurement report: Great 80+, Good 45+, Fair 15+, Poor below.
- **Group after:** a plain line beside each rating says whether the group is OK once they join: "Ready", or what's left ("1 missing (Poison dispel), 1 thin (Interrupt), 1 slot open"). It's on applicant cards (now one line taller), the rows under the Composition slots (short form, full line on hover), the panel beside the Group Finder, Compare, the breakdown and Blizzard's applicant tooltip. It's never a second score.
- **No real difference:** when every pick for the slot is within 5 points, everyone gets the same rating, the card says to decide on experience, and the list is ordered by experience.
- **Critical gaps first:** an applicant who closes a critical gap never rates below one who doesn't, whatever their experience.
- **Groups you could join:** the listing stripe is now your pick rating for that group, with the same rules. In the tooltip, "Group after you:" replaces "Still missing after you" (missing needs keep their casts, plus how many stay thin or rest on a talent).
- "Why 78?" and the breakdown explain the new rating; the look-ahead line is gone.

## 1.1.1
- Updated for patch 12.1.5 (`## Interface: 120105`).
- Ruby Life Pools: Living Bomb (Primalist Cinderweaver and Blazebound Destroyer) is now a Magic effect that can be dispelled, which stops its explosion (12.1.5 dungeon tuning). It's a new Magic dispel need in the trash before Kokia Blazehoof.
- Kings' Rest: the Risen Hexer's Shadow Bolt is confirmed to still leave a Magic slow (no longer marked unconfirmed), and its ability link now has an icon and tooltip.
- Murder Row: Seduction is credited to the Seductive Sayaad, Fel Missiles to the Felonious Mage (a channel) and Heartstop Poison to the Street Sneak (all were credited to the Row Hooligan). Kick plans and chat posts name the right mob.
- Nothing in the data is marked unconfirmed any more.
- Composition (planner): the Saved menu no longer overlaps the Needs panel. The name box is narrower, so Save and Saved line up with Export, Clear all and Copy party below.
- Composition (your party, while hosting): the hint under the applicant rows ("+ N more on the Applicants tab. Click a row to preview.") wraps inside the column instead of running into the Needs panel.
- Data checked against 12.1.5's patch notes, its Mythic+ dungeon tuning and the hotfixes through October 13. The rest of the tuning is damage, health and cooldown numbers, and no class utility the addon tracks changed.

## 1.1.0
- Named **Keystone Command**. Command: `/kc`.
- Slogan: "Command the key." Summary: "Learn the dungeon. Build the group. Make the plan. Command the key."
- Invite applicants straight from the Applicants tab: an Invite button on every card.
- Boss cards rewritten as short what-to-do lines (the why stays in the Dungeon walkthrough).
- Boss cards: ability names are highlighted with their icon and show the game's tooltip on hover.
- Dungeon data checked against every hotfix since 12.1.0 (to October 6): Kings' Rest's Risen Hexer now casts Shadow Bolt (its slow is marked unconfirmed until checked in game); Envenom is credited to the High Evolutionist; Toxic Spew to the Potatoad Matriarch; Rav'i's Regurgitate asks for a Disease dispel (on Rav'i's card too); Ascendant's alternatives match the Season 2 guide.
- Tooltips no longer call root and snare effects "Magic debuff".
- Faster: the Composition and Dungeon tabs redraw several times faster, the boss window no longer re-runs the plan when you page or resize, and unchanged roster or applicant updates no longer redraw the windows.
- `/kc verify season`: the game's dungeon pool, bosses, ability spell IDs and affixes in one block (for updates). `/kc verify` now checks every game event the addon uses.
- Applicant ratings weigh experience: each applicant's best run of the listed dungeon against your key level (10% of the score up to +5, 20% to +9, 30% from +10). Sorting by Fit uses it, with ties going to the higher M+ rating.
- "What we need": a short line for your listing's description (open roles and missing needs), from the Applicants tab, the Group Finder panel and the Plan tab.
- Host coaching: "Fills your only gap" headlines, and at low keys a note when a less experienced applicant fits well.
- A short first-run tour (`/kc tour`, or Settings > General).
- The Dungeon tab, Settings > Data and bug reports show how current the data is.
- Pull-by-pull assignments from your Mythic Dungeon Tools route: the Plan tab lists each pull's kicks and dispels, and the boss window shows the pull you're on and how many assignments the next one has for you. Follows imported and shared routes. Settings > Boss cards to turn it off.
- Shorter text: no repeated "nobody has it" lines, short need names in lists, one line per kick or dispel assignment (abilities and cooldowns in its tooltip), a one-line CC summary, and needs nobody brings merged into one line.

- Tabs follow the three questions: **Composition** (who to bring: the old Builder and Live in one tab, switching automatically between your party and the planner, with a manual switch), **Applicants**, **Dungeon** (what to know), **Plan** (who handles what), History, Settings. Saved comps moved into a Saved menu beside Save; the grid view is gone.
- One set of words: needs, gaps and assignments (Readiness is now Needs).
- While you host, your best-fit applicants show under the Composition slots with Invite; click one to preview them in your group (Needs marks what changes). "List view" switches back; the Applicants tab keeps compare, filters and the full breakdown.
- The Dungeon tab is a walkthrough in the order you meet things: trash sections and bosses with what happens there, following your Mythic Dungeon Tools route when you have one (the guides' order otherwise), filtered by role.
- Bloodlust timing: a default per dungeon you can change (move it, add a note, add or remove one), shown on the Plan and Dungeon tabs, in the boss window and in the assignments post.
- Change who takes a kick or dispel: click an assignment line on the Plan tab. Lasts the session; "Reset all assignments to automatic" undoes it.
- A line for your Sign Up note when you apply to a group: your spec, rating, best run in that dungeon and what you'd bring, to copy into the note.

## 1.0.0
- First release for Midnight Season 2 (12.1).
- Boss cards: a short, role-split card for all 28 Season 2 bosses, a pop-up boss window that follows your progress through the dungeon (resizable, own text size, your plan jobs highlighted), editable cards, and one-click posting to chat. `/kc boss` and Settings > Boss cards.
- `/kc report` (also Settings > Data): a copyable bug report with version, setup, changed settings, other addons and the addon's recent Lua errors.
