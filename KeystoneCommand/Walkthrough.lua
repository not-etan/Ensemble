-- Keystone Command / Walkthrough.lua
-- The dungeon in the order you meet it, for the Dungeon tab: trash sections and bosses,
-- each with the requirements that happen there, plus the Bloodlust plan (defaults from
-- DungeonData, the player's own timing saved per dungeon).
--
-- Order: the player's Mythic Dungeon Tools route when there is one (Route.lua already
-- matches every pull's enemies to requirements), else the guide order (DungeonData.AREAS
-- for trash, BossData `reqs` for bosses). Mechanics never change with the order: a
-- requirement the route doesn't pull still shows, in its guide section.
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

-- Route order: pulls in order; a pull with a boss closes the trash section before it.
local function RouteSteps(dk, reqs, onBoss, route)
  local areas = DD().AREAS[dk] or {}
  local bosses = ns.BossCards:Bosses(dk)
  local visible = {}
  for _, q in ipairs(reqs) do visible[q.id] = true end
  local steps, placed, bossStep = {}, {}, {}
  local cur
  local function trash()
    if not cur then cur = { kind = "trash", reqs = {}, pulls = {} }; steps[#steps + 1] = cur end
    return cur
  end
  for _, p in ipairs(route.pulls) do
    if p.boss and not bossStep[p.boss] then
      if cur then cur.boss = p.boss end
      cur = nil
      local b = { kind = "boss", boss = p.boss, reqs = {}, pull = p.n }
      for _, q in ipairs(reqs) do if has(onBoss[q.id], p.boss) then b.reqs[#b.reqs + 1] = q end end
      steps[#steps + 1] = b
      bossStep[p.boss] = b
      -- the boss's own requirements belong to the boss; trash pulled with it is listed there too
      for _, q in ipairs(p.reqs) do
        if visible[q.id] and not has(onBoss[q.id], p.boss) and not placed[q.id] then
          b.reqs[#b.reqs + 1] = q; placed[q.id] = true
        end
      end
    else
      local t = trash()
      t.pulls[#t.pulls + 1] = p.n
      for _, q in ipairs(p.reqs) do
        if visible[q.id] and not placed[q.id] then t.reqs[#t.reqs + 1] = q; placed[q.id] = true end
      end
    end
  end
  -- Bosses the route never pulls: after everything else, in guide order.
  for bi = 1, #bosses do
    if not bossStep[bi] then
      local b = { kind = "boss", boss = bi, reqs = {}, missing = true }
      for _, q in ipairs(reqs) do if has(onBoss[q.id], bi) then b.reqs[#b.reqs + 1] = q end end
      steps[#steps + 1] = b
      bossStep[bi] = b
    end
  end
  -- Trash the route doesn't pull: into the section that leads to its guide boss.
  local anywhere = { kind = "anywhere", reqs = {} }
  for _, q in ipairs(reqs) do
    if not placed[q.id] and not onBoss[q.id] then
      local a = areas[q.id]
      if a then
        local target
        for _, st in ipairs(steps) do if st.kind == "trash" and st.boss == a[1] then target = st; break end end
        if not target then
          -- no trash pulled before that boss: open a section right before it
          target = { kind = "trash", boss = a[1], reqs = {}, pulls = {} }
          for i, st in ipairs(steps) do
            if st.kind == "boss" and st.boss == a[1] then table.insert(steps, i, target); break end
          end
        end
        q = setmetatable({ notInRoute = true }, { __index = q })
        target.reqs[#target.reqs + 1] = q
      else
        anywhere.reqs[#anywhere.reqs + 1] = q
      end
    end
  end
  if #anywhere.reqs > 0 then table.insert(steps, 1, anywhere) end
  return steps
end

-- { order = "route"|"guide", route = route|nil, steps = { {kind, boss, reqs, pulls?} } }
function WT:Build(dk)
  if not dk or not DD().list[dk] then return nil end
  local reqs = Visible(dk)
  local onBoss = BossReqs(dk)
  local route = ns.Route and ns.Route:For(dk)
  if route and #route.pulls > 0 then
    return { order = "route", route = route, steps = RouteSteps(dk, reqs, onBoss, route) }
  end
  return { order = "guide", steps = GuideSteps(dk, reqs, onBoss) }
end

-- "Pulls 1-4" / "Pull 6" for a trash section.
function WT:PullRange(st)
  local p = st.pulls
  if not p or #p == 0 then return nil end
  if #p == 1 then return "Pull " .. p[1] end
  return "Pulls " .. p[1] .. "-" .. p[#p]
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

-- Keep uses in dungeon order: by route pull when there's a route, else trash N, boss N.
local function Rank(dk, at)
  local kind, n = tostring(at):match("^(%a)(%d+)$")
  n = tonumber(n) or 0
  local route = ns.Route and ns.Route:For(dk)
  if route then
    if kind == "p" then return n end
    for _, p in ipairs(route.pulls) do
      if p.boss == n then return kind == "t" and (p.n - 0.5) or p.n end
    end
    return 1000 + n * 2 - (kind == "t" and 1 or 0)
  end
  return n * 2 - (kind == "t" and 1 or 0)
end

function WT:SortLust(dk)
  local uses = Own(dk)
  table.sort(uses, function(a, b) return Rank(dk, a.at) < Rank(dk, b.at) end)
end

-- Readable spot: "Trash before Rav'i", "Rav'i", "Pull 7 (Risen Hexer x3)".
function WT:SpotLabel(dk, at, short)
  local kind, n = tostring(at):match("^(%a)(%d+)$")
  n = tonumber(n)
  local bosses = ns.BossCards:Bosses(dk)
  if kind == "b" and bosses[n] then return bosses[n].name end
  if kind == "t" and bosses[n] then return (short and "Trash to " or "Trash before ") .. bosses[n].name end
  if kind == "p" then
    local route = ns.Route and ns.Route:For(dk)
    local p = route and route.pulls[n]
    return "Pull " .. n .. ((p and not short) and (" (" .. ns.Route:PullLabel(p) .. ")") or "")
  end
  return "?"
end

-- Every spot a lust can go, in order: trash and bosses, or route pulls when there's a route.
function WT:Spots(dk)
  local out = {}
  local route = ns.Route and ns.Route:For(dk)
  if route then
    for _, p in ipairs(route.pulls) do
      out[#out + 1] = { at = p.boss and ("b" .. p.boss) or ("p" .. p.n),
        label = p.boss and ("Pull " .. p.n .. ": " .. ns.BossCards:Bosses(dk)[p.boss].name) or ("Pull " .. p.n .. ": " .. ns.Route:PullLabel(p)) }
    end
    return out
  end
  for bi, b in ipairs(ns.BossCards:Bosses(dk)) do
    out[#out + 1] = { at = "t" .. bi, label = "Trash before " .. b.name }
    out[#out + 1] = { at = "b" .. bi, label = b.name }
  end
  return out
end

-- Lust uses at a walkthrough step (boss N, trash before boss N, or a route pull in it).
function WT:LustAt(dk, st)
  local uses = self:Lust(dk)
  local out = {}
  for i, u in ipairs(uses) do
    local kind, n = tostring(u.at):match("^(%a)(%d+)$")
    n = tonumber(n)
    local hit = (st.kind == "boss" and kind == "b" and n == st.boss)
      or (st.kind == "trash" and kind == "t" and n == st.boss)
      or (st.kind == "trash" and kind == "p" and has(st.pulls, n))
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
