# Ensemble: full guide

*A Mythic+ Companion*

Learn the dungeon. Build the group. Time the key.

Mythic+ companion for World of Warcraft: Midnight Season 2 (patch 12.1.5), from forming the group to the last boss.
It lists the specific utility gaps in a group (interrupts, battle rez, Bloodlust, dispels, CC), shows which raid buffs the group brings, checks the group against what a chosen Season 2 dungeon actually demands, rates Group Finder applicants and the listings you browse by how well they fit, plans kicks and dispels, and shows a boss card for every boss.

Everything runs inside the game. The addon has no external data sources, no companion app and no update service: it only reads your party, your Group Finder listing and applicants, the Group Finder listings you browse, and its own built-in data files.

## Install

Copy the `Ensemble` folder into `World of Warcraft/_retail_/Interface/AddOns/` so the path is `.../AddOns/Ensemble/Ensemble.toc`, then restart the game or type `/reload`.

## Use

- **Opening it:** `/ens` opens the window (also the minimap button, which shows the addon's logo, or the Addon Compartment menu). The first time, a seven-step tour points out the tabs, the dungeon picker, the slots, Needs, the Plan tab, the Applicants tab and the glossary (Skip ends it; replay it from Settings > General or `/ens tour`). Messages the addon prints in your own chat start with its emblem and "Ensemble:"; posts to party chat are plain text starting with "[Ensemble]".
- **Who it's for:** newer players learning how each dungeon works, players pushing toward +12 and beyond learning the details that time keys (must-kicks, dispels, what each dungeon asks for and which classes bring it), and experienced players who want fast decisions and a plan to share with the group.
- **Tabs, by question:** *Composition* (who to bring), *Applicants* (who's applying to your listing), *Dungeon* (what to know, in the order you meet it), *Plan* (who handles what), then *History* and *Settings*.
- **Data date:** the Dungeon tab, Settings > Data, `/ens report` and `/ens verify` show which patch the data is for and the newest Blizzard hotfix post it was checked against.
- **Sources:** the dungeon, boss and class data is written from published guides (Method.gg, Icy Veins, Wowhead and Raider.IO's quick boss guides) and checked against Blizzard's hotfix notes. *Sources* (in Settings > Data, beside the data line on the Dungeon tab, or `/ens sources`) lists each site's guide index with a link to copy. Ensemble isn't affiliated with these sites.
- **Words:** a *need* is something a group should be able to do (Bloodlust, Poison dispel, kicks); a *gap* is a need the group is MISSING or THIN on; an *assignment* is one player's job in the plan (kick this cast, dispel that debuff). The glossary (`?` in the title bar, or `/ens glossary`) lists every term.

### Composition

- **Your party or the planner:** in a party, or with a Group Finder listing, the slots fill with your real group; otherwise they're the planner, where you pick specs yourself. The mode button in the bar (Automatic, Planner, My party) overrides the automatic choice; `/ens planner` and `/ens party` do the same. "Copy party" puts your current party into the planner.
- **Planner:** click a slot (tank / healer / 3 DPS) to pick a spec. Everything updates instantly. **Hover a spec in the slot menu** to preview what it would change before you pick it ("+ covers Poison dispel for Cytotoxin, + raid buff synergy, - adds a gap: ..., Net: +32 points"), including what it replaces. In an empty planner it shows only what the spec covers on its own.
- **Saving:** name a comp and **Save**; the **Saved** menu beside it loads, deletes or imports comps (a share string from **Export**). Loading a comp switches to the planner.
- **Your party:** the roster fills in automatically. Specs show as "spec pending" until they can be read; the dungeon follows your listing or the dungeon you're in.
- **Layout:** a summary strip across the top; on the left the slots and, under them, suggestions for open slots (or your applicants while you host); on the right **Needs**: is this group OK for this dungeon?
- **Learning mode (Settings > "Show explanations", on by default):** every need gets a plain-language line on what it is ("Removes Curses from your group. Only a few classes can."), and every dungeon cast says what it does and what to do ("Dispel every one or it stuns on expiry."). The Dungeon tab always shows the mechanic notes, since teaching is its job. Turn it off for the expert view: only the teaching text goes; no status, gap or coverer is ever hidden.
- **Summary strip:** the dungeon and key level, counts of missing / thin / ok needs, one chip per key need (Lust, Brez, Kicks, Magic, Curse, Poison, Disease, AoE stop, Defensives; icon, word and color) and the biggest risks. Chips wrap onto extra rows when the window is narrow, so none is ever cut off. Click a chip to jump to that need under Needs; click the risks line to list every gap.
- **Slot badges:** each slot shows what that player brings (Kick, Lust, Brez, Magic...). A badge with "!" (amber) means they are the group's only source. Hover the slot for the full list.
- **Needs:** one row per need, combining the generic check with everything the dungeon and this week's affixes ask for, so a need never appears in two places. Rows are grouped (Kicks & stops, Dispels, Survival, Throughput, Mobility & skips) and sorted MISSING, THIN, OK, NONE (nobody brings it and nothing here needs it). Every MISSING or THIN row is open and shows who covers it, what needs it ("Needed for:" each cast with severity, the reason it's short and any note), and **which classes can cover it** with which ability. Covered rows fold to one line with who covers them; click a row to open or fold it. "Expand all" opens every row and the "All gaps" list; "Collapse all" folds every row and closes every expanded list on the page. After either, clicking a single row still opens or folds just that row. Throughput also lists raid buffs and synergy.
- **Summary view:** shows the strip and only the gap rows (with all their detail); a line says how many covered needs are hidden. "Full view" switches back.
- **"+N more" everywhere expands:** every "+N more" (requirements, classes, reasons, casts, applicants, remaining gaps) opens in place and has a "show fewer" to fold it again.
- **Raid buffs & synergy:** each slot shows the raid buff that player brings (e.g. `+Battle Shout`). The analysis lists the group's buffs and how well each one fits this group: Chaos Brand is rated STRONG SYNERGY with several magic damage dealers, Mystic Touch shows LITTLE VALUE in an all-caster group, Battle Shout helps Strength/Agility users, Arcane Intellect helps Intellect users, Skyfury favors melee. Universal buffs (Mark of the Wild, Fortitude, Blessing of the Bronze, Hunter's Mark) are listed as helping everyone. Buffs you don't have are never shown as missing. Synergy gives a small bonus to suggestions and applicant ratings, but real utility gaps always outweigh it.
- **Abilities, buffs and debuffs:** shown with their icon in front and colored by type (see *Colors* below). Hover any of them for the in-game tooltip, which also names the type in words; shift-click puts the spell link in chat.
- **Check against:** the dungeon is picked for you. In the planner it's the dungeon of the keystone in your bags; for your party and on the Applicants tab it's the dungeon your group is listed for, or, with no listing, the dungeon you're standing in. The note beside the dropdown says which. Pick any of the eight Season 2 dungeons (each shown with its in-game dungeon icon) to override it, or "Auto" to go back. A party pick only lasts until the group's dungeon changes (a new listing or zoning into another dungeon); a planner pick lasts until you get a keystone for a different dungeon. Entries marked `[unconfirmed]` come from unverified data and never show as MISSING.
- **Suggested for open slots (left column):** for each empty slot's role, up to four classes ranked best fit first, each with the specs that fit best and a "Why:" note: the gaps it closes (dungeon needs first, e.g. "covers Poison dispel for Cytotoxin"), missing utility it adds ("adds battle rez"), and raid buff synergy with the players already in. Only empty slots get suggestions; players already in a slot are never suggested away. No duplicates: a class already filling a role isn't suggested for that role again, and each class appears once per role; the only exception is a different role (a Holy Paladin healer doesn't stop a Retribution Paladin being suggested for DPS). In the planner, click a class to put its best spec in the open slot. Under the suggestions, the planner shows your four most recent saved comps (click one to load it).
- **Applicants under the slots (while you host):** the left column shows your best-fit applicants instead, one row each with the rating, name, spec, headline and an **Invite** button. Click a row to **preview** that applicant in an open slot: the slot shows them, Needs is checked as if they'd joined and each row whose status changes says what it was ("was MISSING", or "new" for a row that wasn't there); rows that don't change carry no marker. Click the row again (or "click to clear" above Needs) to stop. "Open tab" goes to the Applicants tab for compare, filters and the full breakdown; "List view" switches back to the usual left column even while you host ("Show applicants here" switches again; also Settings > Group Finder > "Applicants on the Composition tab").
- **Best key for this group:** the "Best key" button beside the dungeon picker (or `/ens bestkey`) ranks all eight Season dungeons by how well the current group covers them: ready, or how many needs are missing or thin, with the worst ones named. Your own keystone is marked and checked at its level. Click a dungeon to check the group against it.

#### Colors

| Color | Means |
|---|---|
| Cyan | Interrupts and interruptible casts |
| Orange | Crowd control and channels |
| Blue | Magic |
| Purple | Curse |
| Green | Poison, and raid buffs |
| Brown | Disease |
| Red | Bleeds and tank busters |
| Gold | Defensives |

Every tooltip also names the type in words, so color is never the only signal.

### Applicants

While you host a listing, every applicant (or premade applying together) gets a color-coded fit rating against your current party and the key you're running. The rating answers one question: **how good a pick is this person for this slot?**

| Rating | Color | Fit score |
|---|---|---|
| Great | Green | 80 to 100 |
| Good | Blue | 45 to 79 |
| Fair | Amber | 15 to 44 |
| Poor | Red | below 15 |

- **Fit score:** every rating is shown with an icon and the word, plus a score from 0 to 100. 100 is as good as the best spec of their role could be for this slot, 0 no better than the weakest. Applicants whose role is already filled are always Poor.
- **Group after:** a separate line in plain words says whether the group is OK once they join: "Ready", or what's left ("1 missing (Poison dispel), 1 thin (Interrupt), 1 slot open"). It uses the same needs as the Needs panel and is never a second score. It's on every applicant card, each row under the Composition slots (short form, the full line on hover), each row of the panel beside the Group Finder, Compare, the breakdown and Blizzard's applicant tooltip.
- **No real difference:** when the best and weakest pick for the slot are less than 5 points apart, everyone gets the same rating and the card says to decide on experience (the list is then ordered by experience).
- **Critical gaps first:** a critical gap is a critical dungeon need that's missing, or a critical gap such as no interrupts. An applicant who **fully** closes one, with a dependable ability of their own, never rates below anyone who doesn't, whatever their experience. One who only **partly** closes it, with a weaker source (a talent, a pet, a long cooldown, a conditional or unconfirmed ability, or a spec the game hasn't shared yet: a Shadow Priest's Mass Dispel, a Warlock's Imp), still gets credit for it, but less: at least halfway between the weakest pick and the best pick that closes nothing, and never raised past that. In Temple of Sethraliss with a Protection and a Fury Warrior at +12, a Shadow Priest covering Imbued Conduction with Mass Dispel alone rates 50 (Good) instead of tying the Elemental Shaman's 100.
- **Experience:** when the key level is known and the game shares it, each applicant's best run of the listed dungeon this season (Blizzard's own per-dungeon score) is weighed against the key level: timed at or above the key = 100, timed up to two below = 80, lower or over time scales down, no run of this dungeon = 30. The score blends it with the pick rating: 10% up to +5, 20% at +6 to +9, 30% from +10. With no key level or no data the score is the utility fit alone, never a penalty. Cards show "best here +14", the breakdown shows both parts ("Utility 82, experience 100").
- **Host coaching:** an applicant who closes the group's last missing dungeon need is headlined "Fills your only gap: ..." (or "Fills all your gaps: ..."). At keys up to +9, a less experienced applicant who fits well gets a note that it's a good key to give them the run.
- **What we need:** the "What we need" button (Applicants tab, the panel by the Group Finder, and the Plan tab while you're in a party) opens a short line for your listing's description, such as "LF 2 DPS. Need: Poison dispel, Brez. Nice to have: Kicks.": open roles, then confirmed missing needs, then thin ones, kept to about 120 characters. The game doesn't let addons fill in the listing, so it opens in the copy window.
- **Why this score:** *Why 78?* under the rating opens the score taken apart: each gap the applicant closes or opens and how much it counts ("+24.0 covers Poison dispel for Cytotoxin"), raid buff synergy, then each step that leads to the final score: where they sit between the best and weakest pick for their role, how their experience blends in, and the critical-gap rule when it applies.
- **Waiting time:** every applicant card (and the panel beside the Group Finder) shows how long they've been waiting ("waiting 2:40", amber after 3 minutes), counted from when the addon first saw them (a /reload restarts the count).
- **In the Group Finder itself:** hovering an applicant in Blizzard's list adds their fit rating, headline, "Group after:" line and biggest reason to the game's own tooltip (Settings > "Fit ratings in applicant tooltips").
- **Breakdown:** click an applicant to see the utility their spec brings, what it adds to your existing classes, where it overlaps, which of the dungeon's requirements it covers, and every gap still left after inviting them with the classes that could cover it.
- **Looking ahead:** with other slots still open, the headline looks ahead ("OK if the last slot brings Poison dispel, e.g. Balance Druid") and the notes name the best way to fill the rest. The look-ahead doesn't change the rating.
- **Key level:** set it with the -/+ buttons (or it's read from your own keystone when it matches).
- **Group Finder panel:** a compact version of the list docks under the Group Finder window while you host, as wide as the window with applicants in two columns. "Dock right" in its header moves it beside the window instead (single column); "Dock below" moves it back. Drag it anywhere to move it freely; it stays there until you click its "Dock" button, tick "Keep the panel docked" in Settings, or type `/ens panel below` / `/ens panel right`. Turn it off in Settings.
- **Invite:** each applicant card (and each row under the Composition slots) has an Invite button that invites that application to your group, a premade group as one. It changes to "Invited" afterward. It's off, with the reason in its tooltip, when you're not the leader or an assistant, when the group has no room for them, or when they've already been invited. Inviting needs a click by the game's rules, so the addon never invites on its own.
- **Compare:** click "Compare" on two applicant cards to see them side by side: fit, utility, experience, M+ rating and item level (the better value in green), the missing utility only one of them brings, the dungeon needs each one closes, their overlaps, and a one-line verdict. Pinning a third replaces the oldest; click "Pinned" to unpin.
- **Sort and filter:** sort the cards by Fit (utility plus experience; ties go to the higher M+ rating), M+ rating or item level, and tick "Hide Poor" to hide applicants rated Poor. The panel beside the Group Finder keeps its fit order.
- **Opens on its own:** when you list a group for a Season dungeon, the window opens on the Applicants tab automatically (untick "Open Applicants when you list a group" in Settings to stop it). It only triggers when a listing is created, not on edits or `/reload`, and never in combat.

### Groups you could join (Group Finder search results)

When you browse listings for a Season dungeon, each one gets a marker for how well **you** would fit it, and its tooltip gets a breakdown:

- *You'd add:* the needs you'd cover (with the cast that needs it), including extra cover such as a second kicker.
- *You'd add, though they may already have it:* needs the group covers only through an optional talent. Other players' talents can't be seen, so these are never counted as certain.
- *Not guaranteed:* needs that would still be thin, or covered only through a talent, after you join.
- *Group after you:* "Ready", or what the group would still need from someone else once you join, with the cast that needs it ("1 missing: Freedom (Regurgitate)"), plus how many needs stay thin or rest on a talent nobody can see.
- **Your talents:** your own talents *can* be read: in *You'd add*, a talent ability you have counts as certain. The rating doesn't use them: it rates you exactly as it rates every other spec it compares you with (and as a host sees you), with talents uncertain and Bloodlust assumed, so you never rate above the best spec of your role.
- **The rating:** Great, Good, Fair or Poor and a 0-100 score, your pick rating for that group, on the same scale as applicant ratings: how strong an applicant you'd be for its open slot compared with every other spec of your role, with the same "no real difference" and critical-gap rules. A group with no open slot for your role is Poor. Listings are checked against the dungeon's own needs only: this week's affixes depend on the key level, and the game doesn't let addons read listing titles, so affixes are left out rather than guessed.
- **Marker** (Settings > Group Finder): a colored edge stripe on each listing, a bar on the left plus a faint tint showing your pick rating for that group; solid for Great/Good, dashed for Fair, dotted for Poor, so it never relies on color alone. Options: turn it off, leave Poor fits unmarked, and turn the tooltip lines off.
- **A line for your Sign Up note:** when you click Sign Up, a small box under Blizzard's dialog holds a line about you: "Enh Shaman, 2950, timed +13 here. Brings Bloodlust, Poison dispel." (your spec, your M+ rating, your best run of that dungeon this season, and what you'd add to that group, kept to about 120 characters). Click it, Ctrl+C, and paste it into the note yourself: the addon never types into Blizzard's dialog. It still appears when another addon changes Blizzard's Sign Up dialog code, and `/ens verify` names any addon that replaced the Group Finder code the addon relies on, with the feature it affects. Settings > Group Finder > "A line for your Sign Up note" turns it off.
- **Bloodlust:** Bloodlust / Heroism is assumed whenever a member's spec can bring it, even through a pet or talent, since nobody who can bring it leaves it at home. Composition and applicant checks keep their usual caution.
- **Speed:** listings are evaluated a few at a time as they appear, so a long result list never stalls the game.

### Dungeon

A walkthrough of any Season dungeon, no group needed. Use it before you list a key or apply to one.

- **In the order you meet it:** each trash section ("Trash before Merektha") with what happens there, then the boss with its card and its mechanics, and so on to the last boss. Each line names the need, the cast and the mob, its severity, any alternative ("or Freedom"), and what the mechanic does and what to do. Requirements that aren't tied to one place sit under "Throughout the dungeon". Nothing is left out: every requirement of the dungeon shows up somewhere.
- **Order:** the guides' order (the trash sections are from Method.gg's and Icy Veins' Season 2 guides).
- **Boss order:** where groups can choose which boss comes first, the bosses that can swap have "Move earlier" and "Move later" under them (each says which boss it swaps with). This season that's The Blinding Vale's first two bosses: right to Ikuzz the Light Hunter or left to the Lightblossom Trinity. Each trash section moves with the boss it leads to, and the bosses are numbered in your order. Your order is saved per dungeon; "Reset to the guides' order" goes back. It also sets the Bloodlust order and which boss the boss window starts on and turns to next. Other dungeons have a fixed order and show no buttons.
- **Show: All / Tank / Healer / DPS:** filters boss notes to that role plus everyone's, and needs to the ones that role handles or helps with (everyone kicks, stops, soothes, purges and frees; dispels are the healer's, and yours too when your own spec has that dispel; tank-damage needs are the tank's and healer's).
- **Bloodlust:** the plan sits at the top and a BLOODLUST marker shows at each spot it's used (see the Plan tab).
- **Boss cards** in the walkthrough fold with a click and have Edit card, Post to chat and Open in the boss window.
- **Best value here** (right): per role, the classes that answer the most of it on their own, with what they answer ("Interrupt x8, AoE stop x3..."), and the key-needs sheet underneath. It counts the same requirements as the walkthrough: needs you've unticked in Settings > What to check and, with "Hide low-severity requirements" on, low entries are left out.

### Plan

Who handles what, for your party or the planner's group, in the dungeon you're checking. The left panel, *Your plan*, holds your assignments and the Bloodlust plan; the right one, *Assignments: (dungeon)*, holds the whole group's plan with the Post buttons under it.

- **Your assignments:** what you personally do in this key, from the plan: your kicks (and your place in each rotation), dispels, stops, and what you back up. In your party it's you; in the planner it's the first slot holding your current spec (otherwise it tells you to add it).
- **Bloodlust:** when to use it, numbered in dungeon order (your boss order where the dungeon allows a choice): "1. Mchimba the Embalmer (on pull)". Each dungeon starts with a suggested default. Tanks and routes differ, so it's yours to set: click a line to move it to another boss or trash section, add a short note ("at 40%") or remove it; "+ Add a Bloodlust" adds one (up to four); "Reset to the default" undoes your changes. Your timing is saved per dungeon. It shows in the Dungeon walkthrough, in the boss window ("LUST" on that boss) and as the second line of the assignments post ("Lust: Mchimba the Embalmer (on pull) > Dazar, the First King (on pull)").
- **Assignments:** for the selected dungeon: the must-kick casts, must-dispel debuffs (with their type), must-stop channels, plus tank and other mechanics and this week's affixes: critical first, then high, then medium (a red cross marks critical; low-severity entries are left off). A category with more than five folds the rest behind "+N more". Dispel lines start with the debuff type ("Magic:") and affix lines with the need ("Group defensives:", "Externals:"). Under each, one short line says who handles it ("Kick: Prot Warrior > Arms Warrior (~8s), backup Outlaw Rogue"); hover it for the abilities, cooldowns and order. Dangerous casts get a two-player kick rotation, shortest cooldown first, with the combined rate and a backup. Assignments are spread by cooldown: every cast adds load in proportion to the kicker's cooldown, so a 24s Counterspell takes fewer casts than a 15s Pummel and a 45s Silence is used only when nothing shorter is free. Healers kick only when the others are already loaded, and each kick they take counts for more. Dispels get a primary and a backup; healers are preferred for cleansing the group, others for purge and soothe, and one ability that covers two debuff types (Nature's Cure) is treated as one cooldown. Warnings show when only a long-cooldown kick or dispel is available, when nobody can kick a cast (the plan names who can stop it instead), or when a critical debuff has no backup dispeller. Kicks are owned per cast: "1st" takes the next cast, "2nd" the one after. A "Two casts at once? Kick first:" line ranks the casts by danger. Cooldowns are base values; talents can shorten some.
- **Changing an assignment:** click an assignment line to choose who takes it. For a kick, click players to add them to the rotation or take them out (the order you add them is the kick order); for a dispel, pick the dispeller. Changed lines say "(set by you)", and the backup is still picked for you. "Back to automatic" in the same menu undoes one; "Reset all assignments to automatic" undoes them all. Changes last for this session and stop applying the moment that player changes spec or leaves; the boss window, your assignments and the post all follow them.
- **Post assignments** (button under the list): sends a short header, the Bloodlust line, then **one line per player with their name first** ("Ryvax: KICK Essence Disruption [Temple Disruptor] 2nd, Lightning Bolt [Storm Adept] 2nd."), then the kick-first order and anything nobody can handle ("Nobody can remove Bleed (Cutpurse): use defensives."). Lines go out a moment apart so chat doesn't throttle them; a player whose line is too long for one chat message gets a second line ("Ryvax (cont.): ..."), so nothing is dropped or cut. A long Bloodlust plan goes on to a "Lust (cont.):" line the same way. If the game is blocking addon chat at that moment (it can inside a key), the text opens in the copy window instead so you can paste it.
- **Post gaps** (button beside it): sends one plain line such as "[Ensemble] Temple of Sethraliss - Missing: Bloodlust / Heroism, Poison dispel (Cytotoxin). Thin: Magic dispel (Imbued Conduction)." A long list goes on to a "(cont.)" line instead of being cut. Hover either button to preview the exact text; a button is dimmed, with the reason on hover, when there's nothing to post yet. "Chat style" beside them opens Settings > Party chat. Raid groups get raid chat; when you're not in a group it only prints for you, and when the game is blocking addon chat it opens in the copy window so you can paste it.
- **Party chat style (Settings > Party chat):** *Full* includes the mob behind each cast, dispel casts and backups; *Short* keeps just the casts to kick and the dispel types (gaps without the casts). Both post one line per player.

### Everything else

- **What to check (Settings > What to check):** every need, grouped like Needs, with a switch per group and per need: untick one (for example Soothe or Bleed cleanse) to leave it out of every check, rating, suggestion, plan and listing marker. Also: raid buffs & synergy, this week's affixes, tank-buster requirements, hide low-severity requirements, count optional talents.
- **Weekly affixes:** this week's affixes are read from the game and filtered by key level (+5 to +11 the week's Xal'atath's Bargain, +7 Fortified or Tyrannical, +10 both, +12 Xal'atath's Guile instead of the Bargain). Needs shows "Affixes at +N" with each active affix and its advice, and the utility they call for appears in the matching need's row, tagged "(affix: ...)". Those needs flow into the analysis, the assignments and applicant ratings. The level comes from the Applicants tab's setting or your own keystone; when unknown it assumes +10 and says so.
- **History:** every Mythic+ key you start is recorded on your own machine when it ends (timed with its upgrade, over time, or abandoned if you leave): dungeon, level, time against the timer, deaths, affixes, the group's specs and the gaps it had. The right side compares your timed rate with and without each gap once there are at least three finished keys on each side, plus a per-dungeon summary. Filter by dungeon, untick "Record my keys" to pause, or clear it (two clicks); `/ens reset confirm` also clears it. A `/reload` or reconnect inside a key keeps the run. Keeps the last 500 keys; practice runs are skipped. Each finished key gets a **lesson** line ("Over time with no Bloodlust / Heroism and no Poison dispel...", "Timed despite no battle rez").
- **Season changes:** dungeons are identified by the game's map IDs, not their names, so the addon works the same in every client language. If the game's Mythic+ dungeon list stops matching the addon's data (a new season), you get one chat warning naming what changed and a banner under Needs until the data is updated.
- **Window size and text size:** drag the bottom-right grip to resize the window. A bigger window gives the panels more room; the text stays the same size. Text size is its own setting: Settings > Appearance > Text size (80% to 125%) or `/ens text 110`. Click "Unlocked/Locked" in the title bar, tick "Lock window" in Settings, or type `/ens lock` to stop moving and resizing; `/ens unlock` reverses it.
- **Colors:** Settings > Appearance sets the accent color with a color wheel, a hex box (e.g. `#A78BFA`), ten presets or "Use my class color". Changes apply instantly.
- **Settings:** one window with sections down the left: *General* (presets, which group Composition and Plan show, summary view, explanations, auto dungeon, auto-open on listing, minimap button, the tour), *What to check*, *Group Finder* (applicant panels and tooltips, listing markers, the Sign Up line), *Party chat*, *Boss cards* (auto-open, all roles, fade in combat, lock, text size), *Appearance* and *Data* (record keys, clear history, reset everything, copy a bug report, Sources). Resetting everything (also `/ens reset confirm`) wipes saved comps, the planner comp, every setting, run history, boss-card edits, Bloodlust timing, boss order and the error log, and clears this session's hand-picked assignments and boss progress; it can't be undone. Hover any option for a one-line explanation; each section has its own *Reset section*. **Presets:** *Learning* or *Expert*, then adjust anything. The addon is also listed in Blizzard's Options > AddOns.

#### Slash commands

| Command | What it does |
|---|---|
| `/ens` | Open or close the window |
| `/ens composition` · `applicants` · `dungeons` · `plan` · `history` · `settings` | Open a tab |
| `/ens planner` · `/ens party` | Show the planner or your party |
| `/ens glossary` · `/ens tour` | Open the glossary or replay the tour |
| `/ens sources` | The guides the data comes from |
| `/ens bestkey` | Rank every dungeon for your group |
| `/ens dungeon <name \| auto \| none>` | Choose the dungeon to check against |
| `/ens boss [dungeon]` | Open or close the boss window |
| `/ens text <80-125>` | Set the text size |
| `/ens panel below \| right \| dock` | Move the applicant panel |
| `/ens lock` · `/ens unlock` | Lock or unlock the window |
| `/ens minimap` | Show or hide the minimap button |
| `/ens verify` | Check the addon against your game client |
| `/ens report` | Build a bug report to copy |
| `/ens reset confirm` | Reset all saved data and settings |


## Boss cards

Every boss in the 8 Season 2 dungeons (28 in all) has a short card: lines for everyone (ALL) and separate TANK, HEAL and DPS lines, each a short instruction saying what to do (the why is in the Dungeon walkthrough). They're written in our own words from four sets of Season 2 guides (Method.gg, Icy Veins, Wowhead and Raider.IO's quick boss guides, read as written guides only) and checked in game against the dungeon journal. Every line is currently confirmed; a future line that only one source states, or where they disagree, shows as *unconfirmed*.

- **Boss window** (`/ens boss`, or Settings > Boss cards): a small window that opens when you enter a Season dungeon and shows the first boss not yet killed. When a boss dies, it turns to the next card. `<` and `>` flip through the bosses by hand. Where a dungeon lets you choose the boss order (Dungeon tab), the window follows your order. Progress survives a `/reload` and starts over with a new key or another dungeon. Outside a dungeon, `/ens boss` shows the dungeon you're checking, and `/ens boss <dungeon>` opens a specific one.
- **What it shows:** your kick and dispel assignments on that boss from the plan first, on an accent-colored band tagged YOU or BACKUP (backups fainter), a LUST row where your Bloodlust plan uses it, then your role's lines and the ALL lines. The footer button switches to every role's lines. Assignments come from your party (specs read as on the Composition tab), or just you when you're solo, including any you changed by hand.
- **Ability links:** ability names on the cards (in the window and the Dungeon tab) are highlighted with their icon, and hovering one shows the game's own tooltip; shift-click puts the spell link in chat. Boss abilities come from the game's dungeon journal, so they always match the current patch; must-kick and must-dispel casts keep their usual colors. Chat posts stay plain text.
- **Size and text:** drag the corner to resize, `A-`/`A+` (or Settings > Boss cards) for 9-20 px text, lock it, and optionally fade it to 35% in combat. Position, size and text size are saved.
- **Editing:** Edit (in the window or the Dungeon tab) opens a box with one `ROLE: text` line per note. Your version is saved per boss and kept through updates; if the built-in card changes later, the card says "default updated". Reset to default any time.
- **Chat:** Post sends the card as one line per role (ALL first, with the boss name), a moment apart; a role whose notes don't fit one chat message goes on to a second line for that role instead of being cut. Your personal assignments aren't posted (Post assignments covers everyone's). When the game is blocking addon chat, which can happen inside keys, the text opens in a copy window instead; posting before the key starts avoids that.
- **Dungeon tab:** every card sits in the walkthrough where you meet that boss, with Edit card, Post to chat and Open in the boss window.
- **Checking it:** `/ens verify` checks the boss window's events and the encounter journal (each dungeon's journal entry and how it was found), and lists any unconfirmed boss lines.

## Checking the addon against your game client

Type `/ens verify`. It checks, in your client, the game functions, specs, spells, dungeons and affixes the addon relies on, your Group Finder listing, applicants and search results, your party, and (inside a key) what the game hides from addons, then lists anything still unconfirmed in the data. It opens a report window: click in the box, then Ctrl+A and Ctrl+C to copy it.

For the most complete report, run it while hosting a listing with at least one applicant and while in a party. It changes nothing; the last report is also saved in the SavedVariables file.

## Reporting a problem

Type `/ens report` (or Settings > Data > *Copy a bug report*). It opens the same copyable window with a bug report that starts with three lines to fill in (what happened, what you expected, how to make it happen again), followed by:

- addon version, client build and language, date;
- where you were: open tab, window and text size, the dungeon being checked (and why), your keystone, this week's affixes, whether you're in a group, an instance or hosting a listing, and your spec;
- the planner slots and the last group checked, as **specs only (never player names)**;
- settings changed from the defaults (window position left out);
- how many other addons are loaded, naming any that share the same screens (Raider.IO, Premade Groups Filter, ElvUI, Details, WeakAuras and similar);
- the addon's own recent Lua errors with their first stack lines, how many times each happened, and the version that raised them. The addon keeps its last 10 errors; errors recorded by BugGrabber, if installed, are included too (with BugGrabber installed it handles errors itself, and the report says so when it caught none from this addon);
- the `/ens verify` summary with up to 12 FAIL and WARN lines.

Nothing is sent anywhere: you copy it and paste it into your report. `/ens verify` says whether error capture is active in your client.

## License

All rights reserved. You may use Ensemble in game, but its code, data, artwork, name and logo may not be copied, modified or redistributed without permission. See `LICENSE`.
