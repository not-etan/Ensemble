-- Ensemble / Walkthrough.lua
-- The dungeon in the order you meet it, for the Dungeon tab: trash sections and bosses,
-- each with the requirements that happen there, plus the Bloodlust plan (defaults from
-- DungeonData, the player's own timing saved per dungeon).
--
-- Order: the guides' order (DungeonData.AREAS for trash, BossData `reqs` for bosses), or
-- the player's boss order where the data allows a choice (BossCards:Order). Each trash
-- section moves with the boss it leads to; a group marked `sharedTrash` shows its trash as
-- one section before the group once its order changes. (Up to 1.2.1 the walkthrough could
-- follow a Mythic Dungeon Tools route; that was removed in 1.3.0.)
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

-- Throughout (no area, no boss), then for each boss in order: the trash that leads to it,
-- then the boss. Steps keep the boss's own index (`boss`); `pos` is its place in the order.
local function GuideSteps(dk, reqs, onBoss)
  local BC = ns.BossCards
  local areas = DD().AREAS[dk] or {}
  local order = BC:Order(dk)
  local custom = BC:IsCustomOrder(dk)
  local steps = {}
  local anywhere = { kind = "anywhere", reqs = {} }
  for _, q in ipairs(reqs) do
    if not areas[q.id] and not onBoss[q.id] then anywhere.reqs[#anywhere.reqs + 1] = q end
  end
  if #anywhere.reqs > 0 then steps[#steps + 1] = anywhere end
  local merged = {}
  for pos, bi in ipairs(order) do
    local g = BC:OrderGroup(dk, bi)
    if g and g.sharedTrash and custom then
      -- Bosses on one shared path, done in another order: their trash is one section before
      -- the group (where it starts), not split by the old order.
      if not merged[g] then
        merged[g] = true
        local members = {}
        for _, b in ipairs(order) do if has(g, b) then members[#members + 1] = b end end
        local t = { kind = "trash", boss = bi, bosses = members, merged = true, pos = pos, reqs = {} }
        for _, q in ipairs(reqs) do
          for _, b in ipairs(members) do
            if has(areas[q.id], b) then t.reqs[#t.reqs + 1] = q; break end
          end
        end
        steps[#steps + 1] = t
      end
    else
      local t = { kind = "trash", boss = bi, pos = pos, reqs = {} }
      for _, q in ipairs(reqs) do if has(areas[q.id], bi) then t.reqs[#t.reqs + 1] = q end end
      steps[#steps + 1] = t
    end
    local b = { kind = "boss", boss = bi, pos = pos, reqs = {} }
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

-- Where a spot sits in the player's boss order: the trash before a boss, then the boss.
local function Rank(dk, at)
  local kind, n = tostring(at):match("^(%a)(%d+)$")
  n = tonumber(n) or 0
  local pos = ns.BossCards and ns.BossCards:Position(dk, n) or n
  return pos * 2 - (kind == "t" and 1 or 0)
end

local function SortUses(dk, list)
  local rank = {}
  for i, u in ipairs(list) do rank[u] = Rank(dk, u.at) * 100 + i end   -- ties keep their order
  table.sort(list, function(a, b) return rank[a] < rank[b] end)
  return list
end

-- A default entry at a boss inside an order group stands for that place in the order (the
-- data's default order, where place N is boss N): it resolves to the boss the player does
-- there, with that boss's own note (`notes[boss]`, else `note`). Other entries are unchanged.
local function ResolveDefault(dk, u)
  local kind, n = tostring(u.at):match("^(%a)(%d+)$")
  n = tonumber(n)
  local at = u.at
  local BC = ns.BossCards
  if n and BC and BC:OrderGroup(dk, n) then
    local bi = BC:Order(dk)[n]
    if bi then at = kind .. bi end
  end
  local bi = tonumber(tostring(at):match("%d+"))
  local note = (type(u.notes) == "table" and bi and u.notes[bi]) or u.note
  return { at = at, note = note }
end

-- The plan for a dungeon: the player's own (db.lust[dk]) or the default, in the player's
-- boss order (so "Lust 1" is the first one you meet). Returns uses, custom.
function WT:Lust(dk)
  local own = ns.db and ns.db.lust and ns.db.lust[dk]
  if type(own) == "table" then return own, true end
  local copy = {}
  for i, u in ipairs(DD().LUST[dk] or {}) do copy[i] = ResolveDefault(dk, u) end
  if not (ns.BossCards and ns.BossCards:IsCustomOrder(dk)) then return copy, false end
  return SortUses(dk, copy), false
end

-- A copy the player can change (made on first edit), in the order shown.
local function Own(dk)
  ns.db.lust = ns.db.lust or {}
  if type(ns.db.lust[dk]) ~= "table" then
    local copy = {}
    for _, u in ipairs((WT:Lust(dk))) do copy[#copy + 1] = { at = u.at, note = u.note } end
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
  uses[i].note = note ~= "" and ns.Util.Clip(note, 80) or nil
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

-- Keep uses in dungeon order (the player's boss order).
function WT:SortLust(dk)
  SortUses(dk, Own(dk))
end

-- The boss order changed: a saved plan is re-sorted so its numbering follows it.
function WT:OnOrderChanged(dk)
  if ns.db and ns.db.lust and type(ns.db.lust[dk]) == "table" then self:SortLust(dk) end
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
  local bosses = ns.BossCards:Bosses(dk)
  for _, bi in ipairs(ns.BossCards:Order(dk)) do
    local b = bosses[bi]
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
      or (st.kind == "trash" and kind == "t" and (n == st.boss or has(st.bosses, n)))
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
  return DD().LUST_SOURCE_DEFAULT
end
