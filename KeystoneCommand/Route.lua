-- Keystone Command / Route.lua
-- Pull-by-pull jobs from the player's Mythic Dungeon Tools (MDT) route. Optional: when MDT
-- isn't loaded, the setting is off, or the dungeon has no route, nothing changes and the
-- plan is built exactly as before.
--
-- What it reads (MDT's saved data, read-only, no MDT functions are changed):
--   MDT:GetDB()                         -> db.presets[dungeonIdx][presetIdx], db.currentPreset[dungeonIdx]
--   preset.value.pulls[n]               -> { [enemyIdx] = { cloneIdx, ... }, color = "..." }
--   MDT.dungeonEnemies[dungeonIdx][i]   -> { name, id (NPC), count, isBoss?, spells = { [spellID] = {...} } }
--   MDT.dungeonTotalCount[dungeonIdx]   -> { normal = forces needed }
--   MDT.mapInfo[dungeonIdx] / MDT.dungeonList[dungeonIdx] -> which dungeon an index is
-- The route in use is the dungeon's *current* MDT preset, so a route that is imported or
-- shared (MDT makes it the current preset) replaces the old one; a 2-second check while the
-- addon's windows are open notices the change.
--
-- Matching a pull to the dungeon data: an enemy's spell IDs against DD.SPELL_IDS (works in
-- every language), then its name against the mob named in each requirement's source, then a
-- boss against its boss card's `reqs`.
--
-- Following the run: the key's enemy-forces progress (C_ScenarioInfo, weighted criterion)
-- against each pull's running total of forces, plus boss kills for boss pulls.
local _, ns = ...

local Route = { cache = {}, idxByKey = {} }
ns.Route = Route

local function S() return ns.db and ns.db.settings end
local function MDTGlobal()
  local m = rawget(_G, "MDT")
  return type(m) == "table" and m or nil
end

function Route:Enabled()
  local s = S()
  return (s and s.routePlan ~= false) and MDTGlobal() ~= nil
end

local function norm(s) return (tostring(s or ""):lower():gsub("[^%w]", "")) end

---------------------------------------------------------------------------
-- MDT's dungeon index for one of our dungeons (by map ID, then by name).
---------------------------------------------------------------------------
function Route:DungeonIndex(dk)
  if self.idxByKey[dk] then return self.idxByKey[dk] end
  local MDT = MDTGlobal()
  if not MDT then return nil end
  local DD = ns.Dungeons
  local cm, im = DD.CHALLENGE_MAP_IDS[dk], DD.INSTANCE_MAP_IDS[dk]
  local enemies = type(MDT.dungeonEnemies) == "table" and MDT.dungeonEnemies or {}
  local found
  for idx in pairs(enemies) do
    if type(idx) == "number" then
      local info = type(MDT.mapInfo) == "table" and MDT.mapInfo[idx]
      local mid = type(info) == "table" and info.mapID
      if mid and (mid == cm or mid == im) then found = idx; break end
      local names = { type(info) == "table" and info.englishName, type(MDT.dungeonList) == "table" and MDT.dungeonList[idx] }
      for _, n in ipairs(names) do
        if type(n) == "string" and DD:FindKey(n) == dk then found = idx end
      end
      if found then break end
    end
  end
  if found then self.idxByKey[dk] = found end
  return found
end

-- The dungeon's current MDT preset (the route the player uses), or nil.
local function CurrentPreset(MDT, idx)
  local ok, db = pcall(function() return MDT.GetDB and MDT:GetDB() end)
  if not ok or type(db) ~= "table" or type(db.presets) ~= "table" then return nil end
  local list = db.presets[idx]
  if type(list) ~= "table" then return nil end
  local cur = type(db.currentPreset) == "table" and db.currentPreset[idx] or 1
  local p = list[cur] or list[1]
  if type(p) ~= "table" or type(p.value) ~= "table" or type(p.value.pulls) ~= "table" then return nil end
  return p, cur
end

-- Cheap fingerprint of a preset's pulls: changes when pulls are edited, imported or shared.
local function Fingerprint(preset, cur)
  local t = { tostring(cur), tostring(preset.uid or preset.text) }
  for n, pull in ipairs(preset.value.pulls) do
    local parts = {}
    for enemyIdx, clones in pairs(pull) do
      if type(enemyIdx) == "number" and type(clones) == "table" then parts[#parts + 1] = enemyIdx .. "x" .. #clones end
    end
    table.sort(parts)
    t[#t + 1] = n .. ":" .. table.concat(parts, ",")
  end
  return table.concat(t, ";")
end

---------------------------------------------------------------------------
-- Building the route: pulls with their enemies and the requirements they bring.
---------------------------------------------------------------------------
local function SpellNameIndex(dk)
  local DD = ns.Dungeons
  local byID = {}
  for name, id in pairs(DD.SPELL_IDS) do byID[id] = name end
  local d = DD.list[dk]
  for name, id in pairs(d and d.spellIds or {}) do byID[id] = name end
  return byID
end

local function BossIndex(dk, name)
  local bosses = ns.BossCards and ns.BossCards:Bosses(dk) or {}
  local nn = norm(name)
  for i, b in ipairs(bosses) do
    local bn = norm(b.name)
    if bn == nn or (nn ~= "" and (bn:find(nn, 1, true) or nn:find(bn, 1, true))) then return i end
  end
  return nil
end

-- Requirements one enemy brings: by its spells, then its name, then (bosses) its card.
local function ReqsForEnemy(dk, e, spellNames, out, seen)
  local d = ns.Dungeons.list[dk]
  if not d then return end
  local AS = ns.Assignments
  local names = {}
  for spellID in pairs(type(e.spells) == "table" and e.spells or {}) do
    local n = spellNames[spellID]
    if n then names[#names + 1] = n end
  end
  for _, req in ipairs(d.requirements) do
    if not req.invalid and not seen[req.id] then
      local src = req.source or ""
      local hit = false
      for _, n in ipairs(names) do if src:find(n, 1, true) then hit = true; break end end
      if not hit and e.name and e.name ~= "" then
        local mob = AS and AS.MobName(req)
        hit = (mob == e.name) or (src:find("(" .. e.name, 1, true) ~= nil) or (src:find(", " .. e.name, 1, true) ~= nil)
      end
      if hit then seen[req.id] = true; out[#out + 1] = req end
    end
  end
  if e.isBoss then
    local bi = BossIndex(dk, e.name)
    local card = bi and ns.BossCards:Boss(dk, bi)
    if card then
      for _, id in ipairs(card.reqs or {}) do
        for _, req in ipairs(d.requirements) do
          if req.id == id and not seen[id] then seen[id] = true; out[#out + 1] = req end
        end
      end
    end
    return bi
  end
end

-- The route for a dungeon, or nil (no MDT, setting off, no route, or not a Season dungeon).
-- { dk, name, pulls = { { n, enemies = { {name, count, n, isBoss} }, forces, cum, frac, reqs, boss } }, total }
function Route:For(dk)
  if not dk or not self:Enabled() then return nil end
  local MDT = MDTGlobal()
  local idx = self:DungeonIndex(dk)
  if not idx then return nil end
  local preset, cur = CurrentPreset(MDT, idx)
  if not preset or #preset.value.pulls == 0 then return nil end
  local fp = Fingerprint(preset, cur)
  local c = self.cache[dk]
  if c and c.fp == fp then return c.route end
  local enemies = MDT.dungeonEnemies and MDT.dungeonEnemies[idx] or {}
  local totals = type(MDT.dungeonTotalCount) == "table" and MDT.dungeonTotalCount[idx]
  local total = type(totals) == "table" and tonumber(totals.normal) or nil
  local spellNames = SpellNameIndex(dk)
  local route = { dk = dk, name = tostring(preset.text or "MDT route"), pulls = {}, total = total }
  local cum = 0
  for n, pull in ipairs(preset.value.pulls) do
    local p = { n = n, enemies = {}, forces = 0, reqs = {} }
    local seen = {}
    local order = {}
    for enemyIdx in pairs(pull) do if type(enemyIdx) == "number" then order[#order + 1] = enemyIdx end end
    table.sort(order)
    for _, enemyIdx in ipairs(order) do
      local clones = pull[enemyIdx]
      local e = enemies[enemyIdx]
      if type(e) == "table" and type(clones) == "table" and #clones > 0 then
        local count = tonumber(e.count) or 0
        p.forces = p.forces + count * #clones
        p.enemies[#p.enemies + 1] = { name = tostring(e.name or "?"), n = #clones, isBoss = e.isBoss and true or false }
        local bi = ReqsForEnemy(dk, e, spellNames, p.reqs, seen)
        if bi then p.boss = bi end
      end
    end
    cum = cum + p.forces
    p.cum = cum
    p.frac = total and total > 0 and (cum / total) or nil
    route.pulls[#route.pulls + 1] = p
  end
  self.cache[dk] = { fp = fp, route = route }
  return route
end

-- A short "Risen Hexer x2, Spectral Hex Priest" for a pull (bosses first).
function Route:PullLabel(p)
  local parts = {}
  for _, e in ipairs(p.enemies) do if e.isBoss then parts[#parts + 1] = e.name end end
  for _, e in ipairs(p.enemies) do
    if not e.isBoss then parts[#parts + 1] = e.name .. (e.n > 1 and (" x" .. e.n) or "") end
  end
  return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Jobs per pull, from the kick and dispel plan.
-- Returns { { text, mine = bool } } for one pull.
---------------------------------------------------------------------------
local function Short(w) return ns.UI and ns.UI.ShortLabel and ns.UI.ShortLabel(w.label) or tostring(w.label) end

function Route:PullJobs(p, plan)
  local out = {}
  local AS = ns.Assignments
  for _, req in ipairs(p.reqs) do
    local row = plan and plan.byReq and plan.byReq[req.id]
    local cast = AS.CastName(req)
    if row and row.kickers and #row.kickers > 0 then
      local names, mine = {}, false
      for i, k in ipairs(row.kickers) do
        names[#names + 1] = (k.isPlayer and "you" or Short(k)) .. (#row.kickers > 1 and (" " .. AS.Ord(i)) or "")
        if k.isPlayer then mine = true end
      end
      out[#out + 1] = { text = "Kick " .. cast .. ": " .. table.concat(names, ", "), mine = mine, severity = req.severity }
    elseif row and row.primary then
      local who = row.primary.isPlayer and "you" or Short(row.primary)
      local verb = row.type == "Purge" and "Purge " or row.type == "Soothe" and "Soothe " or "Dispel "
      out[#out + 1] = { text = verb .. cast .. ": " .. who, mine = row.primary.isPlayer and true or false, severity = req.severity }
    elseif row and row.stoppers then
      local names, mine = {}, false
      for _, st in ipairs(row.stoppers) do names[#names + 1] = st.isPlayer and "you" or Short(st); mine = mine or st.isPlayer end
      out[#out + 1] = { text = "Stop " .. cast .. ": " .. table.concat(names, ", "), mine = mine, severity = req.severity }
    elseif req.need == "stop" or req.need == "aoe_stop" then
      out[#out + 1] = { text = "CC " .. cast, mine = false, severity = req.severity }
    end
  end
  table.sort(out, function(a, b)
    if a.mine ~= b.mine then return a.mine end
    local R = ns.Dungeons.SEVERITY_RANK
    return (R[a.severity] or 9) < (R[b.severity] or 9)
  end)
  return out
end

---------------------------------------------------------------------------
-- Following the run
---------------------------------------------------------------------------
-- Enemy forces done so far, as a fraction (0-1), or nil when the game doesn't say.
-- Runs inside a key, where Midnight can hand addons "secret" values: any of the three numbers
-- being secret (or anything erroring) means "unknown", never an error.
local function IsSecret(v)
  if v == nil or not issecretvalue then return false end
  local ok, secret = pcall(issecretvalue, v)
  return (not ok) or secret and true or false
end
Route.IsSecret = IsSecret

local function ForcesFraction()
  local SI = C_ScenarioInfo
  if not (SI and SI.GetStepInfo and SI.GetCriteriaInfo) then return nil end
  local okS, step = pcall(SI.GetStepInfo)
  local n = okS and type(step) == "table" and step.numCriteria or 0
  if IsSecret(n) or type(n) ~= "number" then return nil end
  for i = 1, n do
    local okC, c = pcall(SI.GetCriteriaInfo, i)
    if okC and type(c) == "table" and c.isWeightedProgress then
      local q, tq, qs = c.quantity, c.totalQuantity, c.quantityString
      if IsSecret(q) or IsSecret(tq) or IsSecret(qs) then Route.forcesSecret = true; return nil end
      q, tq = tonumber(q), tonumber(tq)
      if q and tq and tq > 0 then return math.min(1, q / tq) end
      local pct = tonumber(tostring(qs or ""):match("([%d%.]+)%%"))
      if pct then return math.min(1, pct / 100) end
      return nil
    end
  end
  return nil
end

-- Route.forcesSecret / Route.forcesError: why the last read gave nothing (for /kc verify).
function Route:ForcesFraction()
  Route.forcesSecret, Route.forcesError = nil, nil
  local ok, frac = pcall(ForcesFraction)
  if ok then return frac end
  Route.forcesError = tostring(frac)
  return nil
end

-- The pull you're on: the first pull not done yet. A pull with forces is done once the
-- key's progress reaches its running total; a boss pull once that boss is dead.
function Route:CurrentPull(route)
  if not route then return nil end
  local frac = self:ForcesFraction()
  local killed = ns.BossCards and ns.BossCards.state and ns.BossCards.state.killed or {}
  local eps = 0.002
  for i, p in ipairs(route.pulls) do
    local done
    if p.boss then done = killed[p.boss] and true or false
    elseif p.forces > 0 and p.frac then done = frac ~= nil and frac + eps >= p.frac
    else done = false end
    if not done then return i, frac end
  end
  return #route.pulls, frac
end

---------------------------------------------------------------------------
-- Watching for route changes and progress
---------------------------------------------------------------------------
-- While a window that shows the route is open, look for a changed route every 2 seconds
-- (MDT has no change event other addons can use); progress comes from the scenario event.
function Route:SetWatching(on)
  if on and not self.ticker and C_Timer and C_Timer.NewTicker and MDTGlobal() then
    self.ticker = C_Timer.NewTicker(2, function() Route:CheckChanged() end)
  elseif not on and self.ticker then
    self.ticker:Cancel(); self.ticker = nil
  end
end

-- On while the main window or the boss window is open.
function Route:UpdateWatching()
  local ui = ns.UI and ns.UI.frame and ns.UI.frame:IsShown()
  local bw = ns.BossWindow and ns.BossWindow:IsShown()
  self:SetWatching((ui or bw) and true or false)
end

function Route:CheckChanged()
  local MDT = MDTGlobal()
  if not MDT or not self:Enabled() then return end
  for dk, c in pairs(self.cache) do
    local idx = self:DungeonIndex(dk)
    local preset, cur = idx and CurrentPreset(MDT, idx)
    local fp = preset and Fingerprint(preset, cur) or nil
    if fp ~= c.fp then
      self.cache[dk] = nil
      ns:Fire("ROUTE_CHANGED", dk)
    end
  end
end

function Route:Reset() self.cache = {}; self.idxByKey = {} end

local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "SCENARIO_CRITERIA_UPDATE")
f:SetScript("OnEvent", function() ns:Fire("ROUTE_PROGRESS") end)
ns:On("SETTINGS_CHANGED", function() Route.cache = {} end)
