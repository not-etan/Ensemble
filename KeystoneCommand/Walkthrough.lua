-- Keystone Command / Walkthrough.lua
-- The dungeon in the order you meet it, for the Dungeon tab: trash sections and bosses,
-- each with the requirements that happen there, plus the Bloodlust plan (defaults from
-- DungeonData, the player's own timing saved per dungeon).
--
-- Order: the guides' order (DungeonData.AREAS for trash, BossData `reqs` for bosses).
-- (Up to 1.2.1 it could follow a Mythic Dungeon Tools route; that was removed in 1.3.0.)
local _, ns = ...

local WT = {}
ns.Walkthrough = WT

local function DD() return ns.Dungeons end

-- Requirements (DungeonData order) that respect the hidden categories / low-severity setting.
local function Visible(dk)
  local d = DD().list[dk]
  if not d then return {} end
  local s = ns.db and ns.db.settings or ns.DEFAULTS.settings
  local cats = s.dungeonCategories or {}
  local out = {}
  for _, q in ipairs(d.requirements) do
    if not q.invalid and cats[DD():CategoryOf(q)] ~= false and not (s.hideLowSeverity and q.severity == "low")
      and not ((s.ignoredNeeds or {})[q.need]) then
      out[#out + 1] = q
    end
  end
  return out
end

-- Boss index for each requirement on a boss card: id -> { boss indexes }
local function BossReqs(dk)
  local out = {}
  for i, b in ipairs(ns.BossCards and ns.BossCards:Bosses(dk) or {}) do
    for _, id in ipairs(b.reqs or {}) do
      out[id] = out[id] or {}
      out[id][#out[id] + 1] = i
    end
  end
  return out
end

local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end

-- Guide order: Throughout (no area, no boss), then trash 1, boss 1, trash 2, boss 2...
local function GuideSteps(dk, reqs, onBoss)
  local areas = DD().AREAS[dk] or {}
  local bosses = ns.BossCards:Bosses(dk)
  local steps = {}
  local anywhere = { kind = "anywhere", reqs = {} }
  for _, q in ipairs(reqs) do
    if not areas[q.id] and not onBoss[q.id] then anywhere.reqs[#anywhere.reqs + 1] = q end
  end
  if #anywhere.reqs > 0 then steps[#steps + 1] = anywhere end
  for bi = 1, #bosses do
    local t = { kind = "trash", boss = bi, reqs = {} }
    for _, q in ipairs(reqs) do if has(areas[q.id], bi) then t.reqs[#t.reqs + 1] = q end end
    steps[#steps + 1] = t
    local b = { kind = "boss", boss = bi, reqs = {} }
    for _, q in ipairs(reqs) do if has(onBoss[q.id], bi) then b.reqs[#b.reqs + 1] = q end end
    steps[#steps + 1] = b
  end
  return steps
end

-- { order = "guide", steps = { {kind, boss, reqs} } }
function WT:Build(dk)
  if not dk or not DD().list[dk] then return nil end
  local reqs = Visible(dk)
  local onBoss = BossReqs(dk)
  return { order = "guide", steps = GuideSteps(dk, reqs, onBoss) }
end

---------------------------------------------------------------------------
-- Bloodlust plan
---------------------------------------------------------------------------
WT.LUST_MAX = 4

-- The plan for a dungeon: the player's own (db.lust[dk]) or the default. Returns uses, custom.
function WT:Lust(dk)
  local own = ns.db and ns.db.lust and ns.db.lust[dk]
  if type(own) == "table" then return own, true end
  return DD().LUST[dk] or {}, false
end

-- A copy the player can change (made on first edit).
local function Own(dk)
  ns.db.lust = ns.db.lust or {}
  if type(ns.db.lust[dk]) ~= "table" then
    local copy = {}
    for _, u in ipairs(DD().LUST[dk] or {}) do copy[#copy + 1] = { at = u.at, note = u.note } end
    ns.db.lust[dk] = copy
  end
  return ns.db.lust[dk]
end

local function Changed() ns:Fire("LUST_CHANGED") end

function WT:SetLustAt(dk, i, at)
  local uses = Own(dk)
  if uses[i] then
    if uses[i].at ~= at then uses[i].note = nil end   -- a note about the old spot no longer fits
    uses[i].at = at
  else
    uses[#uses + 1] = { at = at }
  end
  self:SortLust(dk)
  Changed()
end

function WT:SetLustNote(dk, i, note)
  local uses = Own(dk)
  if not uses[i] then return end
  note = tostring(note or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("|", "")
  uses[i].note = note ~= "" and note:sub(1, 80) or nil
  Changed()
end

function WT:RemoveLust(dk, i)
  local uses = Own(dk)
  table.remove(uses, i)
  Changed()
end

function WT:ResetLust(dk)
  if ns.db.lust then ns.db.lust[dk] = nil end
  Changed()
end

-- Keep uses in dungeon order: trash before boss N, then boss N.
local function Rank(dk, at)
  local kind, n = tostring(at):match("^(%a)(%d+)$")
  n = tonumber(n) or 0
  return n * 2 - (kind == "t" and 1 or 0)
end

function WT:SortLust(dk)
  local uses = Own(dk)
  table.sort(uses, function(a, b) return Rank(dk, a.at) < Rank(dk, b.at) end)
end

-- Readable spot: "Trash before Rav'i", "Rav'i".
function WT:SpotLabel(dk, at, short)
  local kind, n = tostring(at):match("^(%a)(%d+)$")
  n = tonumber(n)
  local bosses = ns.BossCards:Bosses(dk)
  if kind == "b" and bosses[n] then return bosses[n].name end
  if kind == "t" and bosses[n] then return (short and "Trash to " or "Trash before ") .. bosses[n].name end
  return "?"
end

-- Every spot a lust can go, in order: the trash before each boss, then the boss.
function WT:Spots(dk)
  local out = {}
  for bi, b in ipairs(ns.BossCards:Bosses(dk)) do
    out[#out + 1] = { at = "t" .. bi, label = "Trash before " .. b.name }
    out[#out + 1] = { at = "b" .. bi, label = b.name }
  end
  return out
end

-- Lust uses at a walkthrough step (boss N, or the trash before boss N).
function WT:LustAt(dk, st)
  local uses = self:Lust(dk)
  local out = {}
  for i, u in ipairs(uses) do
    local kind, n = tostring(u.at):match("^(%a)(%d+)$")
    n = tonumber(n)
    local hit = (st.kind == "boss" and kind == "b" and n == st.boss)
      or (st.kind == "trash" and kind == "t" and n == st.boss)
    if hit then out[#out + 1] = { i = i, use = u } end
  end
  return out
end

-- "Rav'i (on pull)", one per use, for chat and lists.
function WT:LustText(dk, u, short)
  return self:SpotLabel(dk, u.at, short) .. (u.note and (" (" .. u.note .. ")") or "")
end

-- One chat line: "Lust: Rav'i (on pull) > Zul'jan (on pull)". nil when the plan is empty.
function WT:LustChat(dk)
  local uses = self:Lust(dk)
  if #uses == 0 then return nil end
  local parts = {}
  for _, u in ipairs(uses) do parts[#parts + 1] = self:LustText(dk, u, true) end
  return "Lust: " .. table.concat(parts, " > ")
end

function WT:LustSource(dk)
  local _, custom = self:Lust(dk)
  if custom then return "Your timing for this dungeon." end
  return DD().LUST_SOURCE[dk] or DD().LUST_SOURCE_DEFAULT
end
