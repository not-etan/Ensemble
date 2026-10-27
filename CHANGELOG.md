# Changelog

## 1.5.1
Includes everything from 1.5.0 (below), which wasn't released on its own.

- **One player per class in each role:** Fill group never plans two players of one class in the same role (a Restoration and an Elemental Shaman together is fine; two Shaman DPS aren't), counting your party, players you've invited and reserved slots. An applicant whose class already holds that role shows as skipped with the reason, and a premade that repeats a class in a role is skipped. On by default; turn it off in Settings > Fill group. Your own Invite clicks aren't limited.
- **Tiebreaks:** when two applicants rate the same (two Demonology Warlocks, say), the one with the higher best timed run in this dungeon goes first, then the higher score in this dungeon, M+ rating and item level, then whoever waited longer. Fill group and every Applicants sort use the same order, and the Fill plan says what broke a tie.
- **What Fill group leans toward:** when no group passes, the closest group's cards are tagged CLOSEST and the Fill plan lists each thing it's short of once, with the rule it breaks ("Strict wants it not thin", "a must") and who could bring it. It also says when that group would pass at a lower level, names a group that would pass with a repeat class, and shows the best applicant so far for each open slot when there aren't enough applicants yet. Fill group still only invites a full group, and only when you click.
- **Pick from your friends and guild:** reserving a slot, adding a saved player or filling a Composition planner slot can now use your online friends, Battle.net friends and guildmates (with their M+ rating). Type a name, or click Browse for the list (search, show offline). The game doesn't share their spec, so you pick it from their class's specs. Guildmates on the Battle.net mobile app count as offline, since they can't join. Picking someone never saves them.
- **Wipes per boss:** History's Bosses line shows failed pulls on each boss and the lowest health it reached ("wiped 2x, best 12%"), including a boss you never killed.
- **Boss window:** it recognizes kills by the game's encounter ID before the boss's name, and catches up from the key's objectives after a reload.
- **Suggested item level works again:** the game doesn't report the end-of-dungeon loot level, so Fill group's suggested minimum item level uses this season's loot table instead (311 at +12 and up). `/ens verify` says which one it used.
- **Fixes:** the reserve dialog's note no longer runs into its buttons at larger text sizes.

## 1.5.0
- **Reserve a slot:** hold an open slot for a friend who's joining. Pick their spec (and, if you like, their name) from the Fill group band or Settings > Fill group: Fill group plans only the rest, the slot counts in Needs and Fill group's checks, and it clears when they join, when you release it, when the group is full or when the listing ends. When you invite the friend you named (from any Invite button), their reservation steps aside so the slot isn't counted twice: it comes back if the invite times out while you're still listed, and stays released if they decline. Players you've invited count as taking their slot, and your friend's application stays visible with "Hide Poor" on.
- **Saved players:** a list of the people you play with (Settings > Saved players). Their names are suggested as you type a reservation, and the Composition planner can put one in a slot with their spec; a saved comp keeps who was in each slot. Names stay on your computer: never in `/ens verify`, `/ens report`, party posts or share strings.
- **Past keys together:** applicant cards and tooltips say how your recorded keys with that player went ("With you: 2 timed, 1 over time"), with a "Past keys" sort. Fill group can prefer players you've timed with and lower or skip players you've failed with, only among groups that already cover the key (all off by default). Optional: show it in pick ratings. Counts keys recorded from this version on.
- **Boss splits:** History records when each boss died and the deaths in each stretch, compared with your best timed run of that dungeon at the same key level (or the nearest level you've timed, the higher one on a tie); an over-time key with no utility gaps now says where the time went.
- **Faster:** the window rebuilds only the tab that shows what changed, History shows 50 keys at a time ("Show 50 more"), and the boss window redraws once per burst of updates.
- **Downloads:** Ensemble is no longer published on Wago. Get updates from CurseForge or GitHub.

## 1.4.1
Includes everything from the 1.4.0 beta.

- **Fill group:** a band on the Applicants tab finds a full group among your applicants (one tank, one healer, three DPS, counting anyone already invited) that covers what the key needs, and invites it when you click. Click the band for the plan; when nothing passes, it says what it's waiting for.
- **Your rules** (Settings > Fill group): how complete the group must be (Relaxed, Standard, Strict, or by key level), musts per dungeon (Bloodlust and the boss needs), and who can be invited (minimum M+ rating and item level, the leaver flag). Only dependable sources count. Skipped applicants stay listed with the reason.
- **Auto-fill:** tells you when a full group is ready with Ensemble's new chime (or the game's ready-check sound) and the plan by the Group Finder, or a pop-up when everything's closed. It never invites by itself. Restart the game after updating to hear the chime.
- **Invites:** one click sends every invite; if the game takes only some, the button becomes "Invite next" until the next game update.
- **The Blinding Vale:** the default first Bloodlust follows whichever boss you do first.
- **Party posts:** "Nobody can remove ..." names your group's defensives, or says there are none.
- **Fixes:** layout at larger text sizes; a party member's new spec is read after they change it; Compare lines up its numbers; long notes are shortened at a word; and smaller fixes.
- **New logo and banner.** Data checked against Blizzard's hotfixes through October 23, 2026.

## 1.3.2
- **Boss ability links work again:** the game's dungeon journal only answers for the dungeon it has selected, so the boss cards got no abilities from it, and boss kills were matched by name alone. Ensemble now selects the dungeon before reading (and puts the journal back on the dungeon you had open, if its window is showing), and an empty read is tried again later instead of being kept for the whole session.
- **`/ens verify`:** a journal entry that's found but lists no bosses or no abilities is now a warning instead of a pass, and the report checks for the journal function the fix relies on. The "Re-run inside a Mythic+ key with a party" hint only shows when you're outside an instance.
- **`/ens verify season`** lists each dungeon's bosses and abilities again (same journal fix), and says so when a journal entry is found but lists no bosses.
- **`/ens verify` no longer shows another player's name:** the applicant check printed the first applicant's name and realm, and verify reports are often pasted in public. Names are now left out (also from the search-result check).
- **Best key and bug reports use your real group:** while you preview an applicant on the Composition tab, Best key ranked dungeons, and `/ens report` described the group, as if that applicant had already joined.
- **Clearer wording:** the "All gaps" list says each status once ("THIN  Battle resurrection", not "THIN  thin Battle resurrection"); a suggestion's "Why:" lists several casts of one need together ("covers Interrupt for Seduction, Fel Missiles") instead of repeating the words for each, which also leaves room for its other reasons; rows nobody covers read "NONE" without a second dash beside the fold marker; Bloodlust is no longer named twice in an applicant's utility and the slot tooltip; the applicant fit line reads "GOOD FIT   51 / 100"; an ability tooltip without a known spell no longer mentions the addon's files; the tour says the game may block addon chat during a key (the text then opens in a copy window) and that Auto also follows the dungeon you're in; Blizzard's Options > AddOns page lists the Boss cards settings too.
- **Boss window:** its smallest width is now 250 (was 240), so the Edit button no longer overlaps the text-size buttons.
- **Larger text sizes:** at 110-125% text, button labels that didn't fit ("Post assignments", "Summary view", "Copy party", "What we need", "Rating", "Open the boss window", "Reset its position and size", the slot's "x") now step down just enough to fit, never below the 100% size; short labels keep the bigger text. On the Composition tab, a slot's spec name and its second line no longer overlap ("Empty" was drawn over "Click to choose a spec"), the role label (TANK, HEAL) fits, and planner specs use their short names ("Veng Demon Hunter"; the full name is in the slot's tooltip). The note beside the dungeon picker is shorter ("From your keystone (+12)", "Your pick; Auto: Kings' Rest") with the full sentence on hover. Settings > Group Finder's two columns no longer touch, Settings > Appearance's lock option reads "Lock window" (details on hover), and "Expand all" and "Collapse all" have room between them.
- **Windows stack properly:** the boss window and the Group Finder applicant panel now always appear over the main window (the boss window could open behind it).

## 1.3.1
- **Window title:** "A Mythic+ Companion" under the Ensemble name now shows in your accent color (blue by default, or the color you picked in Settings > Appearance, including your class color) instead of gray, and changes with it.

## 1.3.0
**First public release.** A Mythic+ companion for *Midnight* Season 2 (patch 12.1.5) that helps you understand each dungeon, build stronger groups and walk into every key with a plan.

- **Composition:** check any group against the dungeon and this week's affixes, see every gap and who could cover it, and get class suggestions for open slots.
- **Applicants:** every applicant is rated Great, Good, Fair or Poor with a score out of 100, a "Group after:" line and a point-by-point "Why?". Browsing for a group? Every Mythic+ listing shows how well you'd fit, plus a line for your Sign Up note.
- **Dungeon:** a walkthrough of all eight Season 2 dungeons, trash and bosses in order, with boss cards and a boss window that follows your key.
- **Plan:** kick rotations, dispels and Bloodlust timing shared out by cooldown, posted to party chat in one click.

Type `/ens` to start. Found a problem? `/ens report` builds a bug report to paste in a comment or GitHub issue.

**Changes since the 1.2.1 beta:**
- **New name: Ensemble.** `/ens` opens it. The slash commands are down to the essentials (`/ens`, `minimap`, `verify`, `report`, `reset confirm` and `help`); everything else is done with the window's buttons and Settings. Settings, saved comps and run history from the beta don't carry over: Ensemble starts fresh. Messages in your own chat start with the addon's emblem, and party-chat posts start with "[Ensemble]". Shared comp strings now start with `ENS1:`, so strings exported from the beta won't import.
- **Sign Up note line:** it now appears even when another addon changes Blizzard's Sign Up dialog code (some interface addons do). `/ens verify` names any addon that replaced the Group Finder code Ensemble relies on, and the feature it affects.
- **Plan tab:** the full kick and dispel sheet now includes medium-danger casts after the critical and high ones (they were left out, which also hid some assignments), with "+N more" past five per category. "Post assignments" and "Post gaps" are real buttons under the sheet, with the same hover preview. The panels are titled "Your plan" and "Assignments: (dungeon)" instead of repeating their headings, and each affix line names its need, so Xal'atath's Guile no longer looks listed twice.
- **Boss order:** where groups can choose which boss comes first (this season, The Blinding Vale's first two bosses), the Dungeon tab has "Move earlier / later" buttons. Your order is saved per dungeon and also sets the Bloodlust order and the boss window's next boss.
- **Dungeon tab follows your dungeon:** on Auto it shows the dungeon you're in, your listing's or your keystone's, and keeps up as that changes; a dungeon you pick by hand holds until the detected one changes. A new "Open boss cards" button opens the boss window on the dungeon you're reading.
- **Sources:** a new window lists the guides the data comes from, with links to copy (Settings > Data or the Dungeon tab). Each dungeon's default Bloodlust timing now simply says it's a suggested default.
- **Ability links from the dungeon journal** now work: the addon was asking the journal the wrong way, so boss abilities had no links and boss kills relied on names alone (which matters on non-English clients).
- **Mythic Dungeon Tools route features removed:** the latest Mythic Dungeon Tools no longer lets other addons read routes, so the pull-by-pull plan, route order and the boss window's pull rows had stopped working. Bloodlust spots saved at a route pull go back to that dungeon's default.
- **Bug reports** say when BugGrabber is catching errors instead of "error capture not active".

## 1.2.1
- **Critical gaps, full or partial:** an applicant who fully closes a critical gap (with a dependable ability of their own) still never rates below anyone who doesn't. One who only covers it with a weaker source (a talent, a pet, a long cooldown, a conditional or unconfirmed ability, or a spec the game hasn't shared) now gets less credit: at least halfway from the weakest pick to the best pick that closes nothing, and never raised further. Before, either kind was raised to the top non-closer. Example: Temple of Sethraliss, Protection and Fury Warrior, +12: a Shadow Priest covering Imbued Conduction with Mass Dispel alone rated 100 (Great), tied with an Elemental Shaman who closes far more; now 50 (Good). The same rule applies to the listing stripe for groups you could join.
- **"Why 78?" adds up:** the steps now show in the order they apply, each ending on the number the next starts from: the pick position ("this one closes 74.0, so 32/100 as a pick"), the experience blend ("70% of utility 32 + 30% of experience 65 = 42"), then the critical-gap rule with the ability that triggered it. Before, the position line showed the already-raised number and the experience line showed the final score instead of the blend.
- **Preview on the Composition tab:** only Needs rows whose status changes are marked "was MISSING" (or "new"); every row used to say "new".
- **Invite buttons** switch to "Invited" when you invite someone with the Group Finder's own button, on the Applicants tab and under the Composition slots.
- **Best value here** (Dungeon tab) leaves out needs you've unticked and, with "Hide low-severity requirements" on, low entries, like the walkthrough beside it.
- **Groups you could join** are rated on equal terms: every spec you're compared with gets Bloodlust assumed like you do, and the rating treats talents as uncertain for everyone (as a host sees you), so you never rate above the best spec of your role. "What you'd add" still counts the talents you have.
- **Chat posts are never cut:** a line too long for one chat message carries on to the next ("Ryvax (cont.): ..."), in the assignments post, the Bloodlust line, boss cards and the gaps post. Nothing is dropped any more (the assignments post used to drop backups and mob names first, then cut with "..."). The gaps post now uses the copy window when the game is blocking addon chat, like the other posts.
- **Faster with many applicants:** a new or departing application re-rates only that application instead of everyone (about 4 ms instead of about 75 ms with 12 applicants and 4 open slots, plain Lua 5.1 in the test harness).
- **Inside a key:** enemy forces and the roster scan treat values the game hides from addons as unknown instead of risking an error, and a roster scan that errors no longer escapes its timer. `/ens verify` reports both, and now also lists the functions the addon can do without and what each one missing costs.
- **Reset** (`/ens reset`, Settings > Data) says everything it wipes: saved comps, the planner comp, every setting, run history, boss-card edits, Bloodlust timing and the error log. It also clears this session's hand-picked assignments and boss progress.
- **Inside a key:** party inspects (how the addon learns other players' specs) now treat IDs the game hides from addons as unknown, like the roster scan already did, and an error inside the inspect timer is contained and reported by `/ens verify` instead of escaping.
- **Docs:** the overview is shorter, with a new opening, and the README and overview no longer suggest support for other addons: Mythic Dungeon Tools route features carry a note that Ensemble isn't affiliated with MDT, and the Raider.IO panel mention is gone.
- **Releases** are now packaged and uploaded to CurseForge, Wago and GitHub automatically. The zip holds just the `Ensemble` folder (with `LICENSE.txt` inside); the full guide is on the wiki instead of a readme beside the folder.
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
- Invite applicants straight from the Applicants tab: an Invite button on every card.
- Boss cards rewritten as short what-to-do lines (the why stays in the Dungeon walkthrough).
- Boss cards: ability names are highlighted with their icon and show the game's tooltip on hover.
- Dungeon data checked against every hotfix since 12.1.0 (to October 6): Kings' Rest's Risen Hexer now casts Shadow Bolt (its slow is marked unconfirmed until checked in game); Envenom is credited to the High Evolutionist; Toxic Spew to the Potatoad Matriarch; Rav'i's Regurgitate asks for a Disease dispel (on Rav'i's card too); Ascendant's alternatives match the Season 2 guide.
- Tooltips no longer call root and snare effects "Magic debuff".
- Faster: the Composition and Dungeon tabs redraw several times faster, the boss window no longer re-runs the plan when you page or resize, and unchanged roster or applicant updates no longer redraw the windows.
- `/ens verify season`: the game's dungeon pool, bosses, ability spell IDs and affixes in one block (for updates). `/ens verify` now checks every game event the addon uses.
- Applicant ratings weigh experience: each applicant's best run of the listed dungeon against your key level (10% of the score up to +5, 20% to +9, 30% from +10). Sorting by Fit uses it, with ties going to the higher M+ rating.
- "What we need": a short line for your listing's description (open roles and missing needs), from the Applicants tab, the Group Finder panel and the Plan tab.
- Host coaching: "Fills your only gap" headlines, and at low keys a note when a less experienced applicant fits well.
- A short first-run tour (`/ens tour`, or Settings > General).
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
- Boss cards: a short, role-split card for all 28 Season 2 bosses, a pop-up boss window that follows your progress through the dungeon (resizable, own text size, your plan jobs highlighted), editable cards, and one-click posting to chat. `/ens boss` and Settings > Boss cards.
- `/ens report` (also Settings > Data): a copyable bug report with version, setup, changed settings, other addons and the addon's recent Lua errors.
