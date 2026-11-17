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
--
-- Your trash changes (1.7.0): a trash row (one requirement in one section) can be hidden
-- ("we skip this") or moved to another boss's section. Saved per dungeon (db.trashEdits),
-- "Reset to the guides" drops them. They reach the walkthrough, the boss window, Your brief,
-- the Plan and its posts; Needs, pick ratings and Fill group keep the guides' full list.
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

---------------------------------------------------------------------------
-- Your trash changes
---------------------------------------------------------------------------
WT.trashVersion = 0

local function Edits(dk, create)
  local db = ns.db
  if not db then return nil end
  if type(db.trashEdits) ~= "table" then
    if not create then return nil end
    db.trashEdits = {}
  end
  if create and type(db.trashEdits[dk]) ~= "table" then db.trashEdits[dk] = {} end
  return type(db.trashEdits[dk]) == "table" and db.trashEdits[dk] or nil
end

local function TrashChanged(dk)
  WT.trashVersion = WT.trashVersion + 1
  WT.areasCache = nil
  if ns.BossCards and ns.BossCards.ClearPlanCache then ns.BossCards:ClearPlanCache() end
  ns:Fire("TRASH_CHANGED", dk)
end

-- The sections each trash requirement shows in, after your changes.
-- Returns areas   = { [id] = { boss indexes, ascending } }   where each row shows now
--         hidden  = { [id] = { [section] = true } }          rows you hid, by the guides' section
--         movedIn = { [id] = { [section] = from } }          rows you moved, by where they are now
function WT:Areas(dk)
  local c = self.areasCache
  if c and c.dk == dk and c.version == self.trashVersion and c.db == ns.db then return c.areas, c.hidden, c.movedIn end
  local guide = DD().AREAS[dk] or {}
  local edits = Edits(dk) or {}
  local areas, hidden, movedIn = {}, {}, {}
  for id, list in pairs(guide) do
    local e = type(edits[id]) == "table" and edits[id] or nil
    local on = {}
    for _, b in ipairs(list) do
      local to = e and e[b]
      if to == 0 then
        hidden[id] = hidden[id] or {}
        hidden[id][b] = true
      elseif type(to) == "number" and to ~= b then
        if not on[to] then
          on[to] = true
          movedIn[id] = movedIn[id] or {}
          movedIn[id][to] = b
        end
      else
        -- A row the guides put here wins over one moved in from elsewhere.
        on[b] = true
        if movedIn[id] then movedIn[id][b] = nil end
      end
    end
    local out = {}
    for b in pairs(on) do out[#out + 1] = b end
    table.sort(out)
    areas[id] = out
  end
  self.areasCache = { dk = dk, version = self.trashVersion, db = ns.db, areas = areas, hidden = hidden, movedIn = movedIn }
  return areas, hidden, movedIn
end

local function InGuide(dk, id, section)
  return has((DD().AREAS[dk] or {})[id], section)
end

-- Hide a trash row from the section the guides put it in ("we skip this").
function WT:HideRow(dk, id, section)
  if not InGuide(dk, id, section) then return false end
  local e = Edits(dk, true)
  e[id] = e[id] or {}
  e[id][section] = 0
  TrashChanged(dk)
  return true
end

-- Move a trash row from the guides' section to another boss's section.
function WT:MoveRow(dk, id, section, to)
  local d = DD().list[dk]
  if not d or not InGuide(dk, id, section) or type(to) ~= "number" or to < 1 or to > #(d.bosses or {}) then return false end
  if to == section then return self:RestoreRow(dk, id, section) end
  local e = Edits(dk, true)
  e[id] = e[id] or {}
  e[id][section] = to
  TrashChanged(dk)
  return true
end

-- Put one row back where the guides have it.
function WT:RestoreRow(dk, id, section)
  local e = Edits(dk)
  if not (e and e[id] and e[id][section] ~= nil) then return false end
  e[id][section] = nil
  if next(e[id]) == nil then e[id] = nil end
  if next(e) == nil then ns.db.trashEdits[dk] = nil end
  TrashChanged(dk)
  return true
end

-- "Reset to the guides": every trash change for this dungeon.
function WT:ResetTrash(dk)
  if not Edits(dk) then return false end
  ns.db.trashEdits[dk] = nil
  TrashChanged(dk)
  return true
end

-- How many rows you hid and moved in this dungeon.
function WT:TrashEditCounts(dk)
  local h, m = 0, 0
  for _, bySection in pairs(Edits(dk) or {}) do
    for _, to in pairs(bySection) do if to == 0 then h = h + 1 else m = m + 1 end end
  end
  return h, m
end
function WT:HasTrashEdits(dk)
  local h, m = self:TrashEditCounts(dk)
  return h + m > 0
end

-- Requirements you skip altogether: hidden in every trash section the guides list them in, and
-- on no boss card. The Plan, Your brief and the posts leave them out (and count them); Needs,
-- pick ratings and Fill group never read this.
function WT:SkippedReqs(dk)
  local out, n = {}, 0
  local areas, hidden = self:Areas(dk)
  if not next(hidden) then return out, n end
  local onBoss = {}
  for _, b in ipairs(ns.BossCards and ns.BossCards:Bosses(dk) or {}) do
    for _, id in ipairs(b.reqs or {}) do onBoss[id] = true end
  end
  for id in pairs(hidden) do
    if #(areas[id] or {}) == 0 and not onBoss[id] then out[id] = true; n = n + 1 end
  end
  return out, n
end

-- One trash section as the editor lists it: every row the guides put here or you moved here,
-- with what you did to it. { { req, state = "shown" | "hidden" | "movedIn" | "movedOut", from, to } }
function WT:SectionRows(dk, section)
  local d = DD().list[dk]
  if not d then return {} end
  local guide = DD().AREAS[dk] or {}
  local edits = Edits(dk) or {}
  local _, _, movedIn = self:Areas(dk)
  local out = {}
  for _, q in ipairs(d.requirements) do
    if not q.invalid then
      local e = type(edits[q.id]) == "table" and edits[q.id] or {}
      if has(guide[q.id], section) then
        local to = e[section]
        if to == 0 then out[#out + 1] = { req = q, state = "hidden", from = section }
        elseif type(to) == "number" and to ~= section then out[#out + 1] = { req = q, state = "movedOut", from = section, to = to }
        else out[#out + 1] = { req = q, state = "shown", from = section } end
      elseif movedIn[q.id] and movedIn[q.id][section] then
        out[#out + 1] = { req = q, state = "movedIn", from = movedIn[q.id][section], to = section }
      end
    end
  end
  return out
end

-- Throughout (no area, no boss), then for each boss in order: the trash that leads to it,
-- then the boss. Steps keep the boss's own index (`boss`); `pos` is its place in the order.
-- A trash step also carries `hidden` (rows you hid there, still counted) and `moved`
-- ({ [id] = from } for rows you moved in). Every step gets `also`: { [id] = true } for a
-- requirement an earlier step already showed (the Dungeon tab names those on one line).
local function GuideSteps(dk, reqs, onBoss)
  local BC = ns.BossCards
  local guide = DD().AREAS[dk] or {}
  local areas, hiddenBy, movedIn = WT:Areas(dk)
  local order = BC:Order(dk)
  local custom = BC:IsCustomOrder(dk)
  local steps = {}
  local anywhere = { kind = "anywhere", reqs = {} }
  for _, q in ipairs(reqs) do
    if not guide[q.id] and not onBoss[q.id] then anywhere.reqs[#anywhere.reqs + 1] = q end
  end
  if #anywhere.reqs > 0 then steps[#steps + 1] = anywhere end
  local function fill(t, members)
    t.hidden, t.moved = {}, {}
    for _, q in ipairs(reqs) do
      for _, b in ipairs(members) do
        if has(areas[q.id], b) then
          t.reqs[#t.reqs + 1] = q
          if movedIn[q.id] and movedIn[q.id][b] then t.moved[q.id] = movedIn[q.id][b] end
          break
        end
      end
      for _, b in ipairs(members) do
        if hiddenBy[q.id] and hiddenBy[q.id][b] then t.hidden[#t.hidden + 1] = q; break end
      end
    end
    return t
  end
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
        steps[#steps + 1] = fill({ kind = "trash", boss = bi, bosses = members, merged = true, pos = pos, reqs = {} }, members)
      end
    else
      steps[#steps + 1] = fill({ kind = "trash", boss = bi, pos = pos, reqs = {} }, { bi })
    end
    local b = { kind = "boss", boss = bi, pos = pos, reqs = {} }
    for _, q in ipairs(reqs) do if has(onBoss[q.id], bi) then b.reqs[#b.reqs + 1] = q end end
    steps[#steps + 1] = b
  end
  local seen = {}
  for _, st in ipairs(steps) do
    st.also = {}
    for _, q in ipairs(st.reqs) do
      if seen[q.id] then st.also[q.id] = true else seen[q.id] = true end
    end
  end
  return steps
end

-- { order = "guide", steps = { {kind, boss, reqs, also, hidden, moved} } }
function WT:Build(dk)
  if not dk or not DD().list[dk] then return nil end
  local reqs = Visible(dk)
  local onBoss = BossReqs(dk)
  return { order = "guide", steps = GuideSteps(dk, reqs, onBoss) }
end

-- The trash section that leads to a boss, as a walkthrough step (nil when the dungeon is
-- unknown). In a merged shared-path group every member boss gets the group's one section.
function WT:TrashStep(dk, boss)
  local w = self:Build(dk)
  for _, st in ipairs(w and w.steps or {}) do
    if st.kind == "trash" and (st.boss == boss or has(st.bosses, boss)) then return st end
  end
  return nil
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
