local FILES = {}
for line in io.lines(ADDON_DIR .. "/Ensemble.toc") do
  local f = line:match("^%s*([%w_]+%.lua)%s*$"); if f then FILES[#FILES + 1] = f end
end
ALLFRAMES = {}
local ns = {}
for _, f in ipairs(FILES) do assert(loadfile(ADDON_DIR .. "/" .. f))("Ensemble", ns) end
for _, fr in ipairs(ALLFRAMES) do if fr._events.ADDON_LOADED then fr._scripts.OnEvent(fr, "ADDON_LOADED", "Ensemble"); fr._scripts.OnEvent(fr, "PLAYER_LOGIN") end end
local function clean(t)
  t = t:gsub("|T[^|]*|t", "[icon]"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  t = t:gsub("|H[^|]*|h(.-)|h", "%1")
  return t
end
local side = {}
function side:Header(t) print("\n## " .. clean(t)) end
function side:Add(t, o) print(string.rep(" ", math.floor(((o and o.indent) or 0) / 3)) .. clean(t)) end
function side:Space() end
local UI = ns.UI; pcall(UI.Show, UI)
local function run(title, dk, specs, me)
  local members = {}
  for i, id in ipairs(specs) do members[i] = { specID = id, isPlayer = (i == me) or nil } end
  local r = ns.Analysis:Analyze(members, dk, ns.db.settings, { keyLevel = 12 })
  local plan = ns.Assignments:Build(r, ns.db.settings)
  print("\n\n==================== " .. title .. " ====================")
  UI:RenderYourJob(side, r, plan)
  UI:RenderCheatSheet(side, dk, r, plan)
  print("\n## Chat: Post assignments (full)")
  local lines = ns.Assignments:ChatLines(plan, ns.Dungeons.list[dk].name, "full")
  local lust = ns.Walkthrough:LustChat(dk)
  if lust and #lines > 0 then table.insert(lines, 2, lust) end
  for _, l in ipairs(lines) do print(l) end
  print("\n## Chat: (short)")
  for _, l in ipairs(ns.Assignments:ChatLines(plan, ns.Dungeons.list[dk].name, "short")) do print(l) end
end
ns.db.settings.explain = true
run("Temple of Sethraliss: VDH(you) / Resto Sham / Fire Mage / Ret Pally / Balance Druid", "TempleOfSethraliss", { 581, 264, 63, 70, 102 }, 1)
run("Murder Row: Prot Warrior / Holy Priest(you) / BM Hunter / Affliction Lock / Shadow Priest", "MurderRow", { 73, 257, 253, 265, 258 }, 2)
