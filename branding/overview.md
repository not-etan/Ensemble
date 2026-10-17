# 🛡️ Ensemble

### ⚔️ A Mythic+ Companion ⚔️

**Learn the dungeon. Build the group. Time the key.**

Ensemble is a Mythic+ companion that helps players of every skill level learn dungeon mechanics, build stronger groups, and time more keys. It's all in one place, so you spend less time checking guides and more time playing.

## ✨ Who it's for

- 🌱 **Newer players** learn how each dungeon works: every trash pack and boss, what each mechanic does and how to answer it, with short explanations of why they matter.
- 🪜 **Players pushing higher** learn the details that time keys: the must-kick casts, must-dispel debuffs and must-stop channels, the utility each dungeon asks for, and which classes bring it.
- 🏆 **Experienced players** decide faster, with instant applicant ratings, a clear view of every gap and who covers what, and a written plan to share with the group, all without tabbing out to check a single external guide.

🎮 **Game version:** World of Warcraft Retail, *Midnight* Season 2 (patch 12.1.5).

🔄 **Kept current:** dungeon data is checked against Blizzard's hotfixes. Last checked: patch 12.1.5 and hotfixes through October 13, 2026. The Dungeon tab shows this date too.

---

## 🧰 Features

### 🏰 Dungeons and bosses
- 🗺️ **Every Season 2 dungeon:** Altar of Fangs, Murder Row, Den of Nalorakk, The Blinding Vale, Voidscar Arena, Ruby Life Pools, Kings' Rest and Temple of Sethraliss.
- 📖 **Walkthrough:** every trash section and boss in order, with what each mechanic does and how to answer it, filtered by role if you like, plus a short card for every boss.
- 🪟 **Boss window:** opens when you enter the dungeon, follows your progress and highlights your own assignments.
- 🥇 **Best key:** rank every dungeon by how well your current group covers it.

### 📊 Composition
- 🛠️ **Planner or live party:** plan a comp from scratch or let the slots fill with your real group, then save and share comps with an export string.
- 🔎 **Every gap explained:** what your group has, what's thin and what's missing for this dungeon and this week's affixes, and which classes could cover each gap.
- 💡 **Filling open slots:** the best-fit classes for each empty slot, with a preview of what any spec would add before you pick it.

### 📥 Applicant ratings
- 🚦 **Fit rating:** every applicant rated Great, Good, Fair or Poor out of 100, by how well their spec fits your group and key and by their best run of this dungeon, with a point-by-point "Why?". Browsing for a group? Every Mythic+ listing shows how strong a pick you'd be.
- ✅ **Group after:** a plain line saying whether the group is ready once they join (or once you do), or what's still missing.
- ⚖️ **Compare and invite:** pin two applicants side by side, sort by fit, hide Poor fits, and invite from the card or the panel beside the Group Finder.
- 📝 **Ready-to-copy lines:** "What we need" for your listing ("LF 2 DPS. Need: Poison dispel, Brez."), and a Sign Up note with your spec, rating, best run and what you'd bring.

### 🗝️ The plan
- ⏱️ **Kick and dispel plan:** rotations shared out by cooldown, with backups for dangerous casts and your own assignments in one place. Click any assignment to change who takes it.
- 🥁 **Bloodlust timing:** a sensible default for every dungeon that you can move, annotate or add to.
- 💬 **Post to party chat:** the whole plan, one line per player, or just the gaps, in one click.

### 🎓 Learning and history
- 💡 **Learning mode:** plain-language explanations throughout, a glossary and a quick tour, or switch it off for a compact expert view.
- 📈 **Run history:** your keys saved locally, with timed rates with and without each gap and a takeaway from every run.

---

## 🚀 Getting started

1. 📦 **Install it,** then type **`/ens`** or click the minimap button.
2. 🏰 **New to a dungeon?** Open the **Dungeon** tab for a walkthrough.
3. 🧩 **Planning a group?** Open **Composition** and fill the slots.
4. 📥 **Hosting a key?** List it as usual. The **Applicants** tab opens with every applicant rated.
5. 🔎 **Looking for a group?** Browse the Group Finder. Every Mythic+ listing shows how well you'd fit.
6. 🗝️ **In a group?** Open **Plan** for assignments and Bloodlust timing, then post it to chat.

### ⌨️ Slash commands

| Command | What it does |
|---|---|
| `/ens` | Open or close the window |
| `/ens composition` · `applicants` · `dungeons` · `plan` · `history` · `settings` | Open a tab |
| `/ens planner` · `/ens party` | Show the planner or your party |
| `/ens glossary` · `/ens tour` | Open the glossary or the tour |
| `/ens bestkey` | Rank every dungeon for your group |
| `/ens boss [dungeon]` | Open or close the boss window |
| `/ens dungeon <name \| auto \| none>` | Choose the dungeon to check against |
| `/ens text <80-125>` | Set the text size |
| `/ens panel below \| right \| dock` | Move the applicant panel |
| `/ens lock` · `/ens unlock` | Lock or unlock the window |
| `/ens minimap` | Show or hide the minimap button |
| `/ens verify` · `/ens report` | Check the addon against your client, or build a bug report |
| `/ens reset confirm` | Reset all saved data and settings |

---

## 📦 Installation

🔌 **With an addon manager:** search for *Ensemble: A Mythic+ Companion* and install it.

🛠️ **Manually:** extract the archive and copy the `Ensemble` folder into `World of Warcraft/_retail_/Interface/AddOns/`, then restart the game.

---

## 🔒 Privacy

Everything runs inside the game. There's no companion app, no web service and no external data. Your comps, settings and run history stay in your own SavedVariables file, and `/ens report` only builds text for you to copy.

---

## ❓ FAQ

🔍 **Does it use Raider.IO or Warcraft Logs data?**
No. It doesn't pull live data from other sites or addons.

📚 **Where does the information come from?**
The same current-patch guides most players already use, like **Wowhead**, **Method.gg**, **Icy Veins** and **Raider.IO**, gathered into one place and checked in game.

🧩 **Do I need any other addons?**
No. Everything works on its own.

🚦 **Does the rating judge people by their M+ score?**
No. It rates how well a spec fits your group and this dungeon, plus their best run of it this season. Their overall M+ rating and item level are shown, and only break ties when sorting.

🗓️ **What happens when a new season starts?**
The addon notices the dungeon pool changed and warns you until it's updated. Between seasons, the data is checked against every hotfix.

---

## 🐞 Found a problem?

Type **`/ens report`** in game (or use Settings › Data). Fill in the first few lines, copy the window with Ctrl+A and Ctrl+C, and paste it in a comment on the addon's page or in a GitHub issue, with a 📸 screenshot if it's visual. For wrong ability or dungeon info, mention where you saw the correct version and I'll check it against the current patch.

---

## 🤖 AI disclaimer

Ensemble was built with help from Claude, which wrote much of the code and data. Everything is checked against current guides and tested in game, but if something looks off, let me know. The addon itself doesn't use AI.

---

*💙 Ensemble is a fan-made addon and isn't affiliated with or endorsed by Blizzard Entertainment.*
