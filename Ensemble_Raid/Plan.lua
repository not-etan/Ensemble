-- Ensemble Raid (test build) / Plan.lua
-- The plan builder: per boss and difficulty, rows from the boss's data (soak groups, kick orders,
-- dispels, Bloodlust...) plus your own rows, each with players and an optional marker. Saved per
-- boss and data difficulty (LFR and World share Normal's). Posted to chat with marker codes that
-- the game shows as icons, so everyone in the raid reads it without an addon.

local _, R = ...
if R.disabled then return end
local ns = R.ns
local UD = ns.UD
local D = R.Data

local Plan = {}
R.Plan = Plan

-- Fill rules (see Data.lua). Checked by Data:Validate.
function R.ValidFill(f)
  if f == nil then return true end
  if type(f) ~= "string" then return false end
  return f == "melee" or f == "ranged" or f == "half1" or f == "half2" or f:match("^third[123]$") ~= nil
    or f:match("^role:[A-Z]+$") ~= nil or f:match("^cap:[%w_]+$") ~= nil or f:match("^class:[A-Z]+$") ~= nil
    or f:match("^groups:[%d,]+$") ~= nil or f:match("^set:%d$") ~= nil or f:match("^team:%d$") ~= nil
end

function Plan:State(bossKey, diff, create)
  local dd = R:DataDiff(diff)
  local byBoss = R.db.plans[bossKey]
  if not byBoss then if not create then return nil end byBoss = {}; R.db.plans[bossKey] = byBoss end
  local st = byBoss[dd]
  if not st and create then st = { rows = {}, custom = {} }; byBoss[dd] = st end
  if st then st.rows = st.rows or {}; st.custom = st.custom or {} end
  return st
end

-- The rows shown at this difficulty: the boss's rows that apply, then your own.
function Plan:Rows(bossKey, diff)
  local b = D.BOSSES[bossKey]
  local st = self:State(bossKey, diff, false)
  local out = {}
  for _, r in ipairs(b and b.plan or {}) do
    if R:Applies(r.d, diff) then
      local s = st and st.rows[r.id]
      -- A saved marker wins; false means "no marker" even when the row has a default.
      local marker = r.marker
      if s and s.marker ~= nil then marker = s.marker or nil end
      out[#out + 1] = { id = r.id, mech = r.mech, when = r.when, n = r.n, kind = r.kind, fill = r.fill, d = r.d,
                        marker = marker, names = s and s.names or {}, data = true }
    end
  end
  for _, c in ipairs(st and st.custom or {}) do
    local s = st.rows[c.id]
    out[#out + 1] = { id = c.id, mech = c.mech, when = c.when, kind = "players", marker = s and s.marker or c.marker,
                      names = s and s.names or {}, custom = true }
  end
  return out
end

function Plan:Row(bossKey, diff, id)
  for _, r in ipairs(self:Rows(bossKey, diff)) do if r.id == id then return r end end
end

local function RowState(st, id)
  st.rows[id] = st.rows[id] or { names = {} }
  st.rows[id].names = st.rows[id].names or {}
  return st.rows[id]
end

function Plan:Toggle(bossKey, diff, id, name)
  if not (id and name) then return false end
  local st = self:State(bossKey, diff, true)
  local rs = RowState(st, id)
  for i, n in ipairs(rs.names) do
    if n == name then table.remove(rs.names, i); R:Fire("PLAN_CHANGED"); return false end
  end
  rs.names[#rs.names + 1] = name
  R:Fire("PLAN_CHANGED")
  return true
end
function Plan:ClearRow(bossKey, diff, id)
  local st = self:State(bossKey, diff, true)
  RowState(st, id).names = {}
  R:Fire("PLAN_CHANGED")
end
-- marker: a key, or false for "no marker" (overrides the row's default).
function Plan:SetMarker(bossKey, diff, id, marker)
  local st = self:State(bossKey, diff, true)
  RowState(st, id).marker = marker
  R:Fire("PLAN_CHANGED")
end
function Plan:AddRow(bossKey, diff, mech, when)
  mech = ns.Util.Trim(mech or "")
  if mech == "" then return nil end
  local st = self:State(bossKey, diff, true)
  st.nextId = (st.nextId or 0) + 1
  local id = "c" .. st.nextId
  st.custom[#st.custom + 1] = { id = id, mech = mech, when = ns.Util.Trim(when or "") }
  R:Fire("PLAN_CHANGED")
  return id
end
function Plan:RemoveRow(bossKey, diff, id)
  local st = self:State(bossKey, diff, false)
  if not st then return false end
  for i, c in ipairs(st.custom) do
    if c.id == id then table.remove(st.custom, i); st.rows[id] = nil; R:Fire("PLAN_CHANGED"); return true end
  end
  return false
end
function Plan:Reset(bossKey, diff)
  local byBoss = R.db.plans[bossKey]
  if byBoss then byBoss[R:DataDiff(diff)] = nil end
  R:Fire("PLAN_CHANGED")
end

---------------------------------------------------------------------------
-- Suggestions: fill each empty row from the roster by its rule. Never overwrites a row you filled.
---------------------------------------------------------------------------
local function HasCap(m, cap)
  local p = R.Roster:Profile(m)
  local src = p and UD:Sources(p, cap, ns.db and ns.db.settings)
  if not src then return false end
  for _, e in ipairs(src) do if not UD:IsSoft(e) then return true end end
  return #src > 0 and "soft"
end

-- Halves and thirds by raid group (live) or by the planner's order, so a group stays together.
local function Split(members, parts, which)
  local groups = {}
  for _, m in ipairs(members) do groups[m.group or 1] = true end
  local list = {}
  for g in pairs(groups) do list[#list + 1] = g end
  table.sort(list)
  local out = {}
  if #list >= parts then
    local per = #list / parts
    local mine = {}
    for i, g in ipairs(list) do if math.floor((i - 1) / per) + 1 == which then mine[g] = true end end
    for _, m in ipairs(members) do if mine[m.group or 1] then out[#out + 1] = m end end
  else
    local per = #members / parts
    for i, m in ipairs(members) do if math.floor((i - 1) / per) + 1 == which then out[#out + 1] = m end end
  end
  return out
end

function Plan:Candidates(fill, members, n)
  local out = {}
  local function Take(list)
    for _, m in ipairs(list) do if not n or #out < n then out[#out + 1] = m end end
  end
  if not fill then return out end
  local kind, arg = fill:match("^(%a+):(.+)$")
  if fill == "melee" or fill == "ranged" then
    local nonTank = {}
    for _, m in ipairs(members) do if m.range == fill and m.role ~= "TANK" then nonTank[#nonTank + 1] = m end end
    Take(nonTank)
  elseif fill == "half1" or fill == "half2" then
    Take(Split(members, 2, fill == "half1" and 1 or 2))
  elseif fill:match("^third") then
    Take(Split(members, 3, tonumber(fill:sub(-1))))
  elseif kind == "role" then
    local l = {}
    for _, m in ipairs(members) do if m.role == arg then l[#l + 1] = m end end
    Take(l)
  elseif kind == "class" then
    local l = {}
    for _, m in ipairs(members) do if m.class == arg then l[#l + 1] = m end end
    Take(l)
  elseif kind == "cap" then
    local solid, soft = {}, {}
    for _, m in ipairs(members) do
      local h = HasCap(m, arg)
      -- Dispels and Bloodlust: healers and DPS before tanks; kicks: DPS first.
      if h == true then solid[#solid + 1] = m elseif h then soft[#soft + 1] = m end
    end
    local rank = { DAMAGER = 1, HEALER = 2, TANK = 3 }
    if arg:match("^dispel") then rank = { HEALER = 1, DAMAGER = 2, TANK = 3 } end
    local function sorter(a, b)
      local ra, rb = rank[a.role or "DAMAGER"] or 2, rank[b.role or "DAMAGER"] or 2
      if ra ~= rb then return ra < rb end
      return (a.name or "") < (b.name or "")
    end
    table.sort(solid, sorter); table.sort(soft, sorter)
    Take(solid); Take(soft)
  elseif kind == "groups" then
    local want = {}
    for g in arg:gmatch("%d+") do want[tonumber(g)] = true end
    local l = {}
    for _, m in ipairs(members) do if want[m.group or 1] then l[#l + 1] = m end end
    Take(l)
  elseif kind == "set" or kind == "team" then
    -- set k: the k-th melee, healer and ranged; team k: k-th healer plus three DPS.
    local k = tonumber(arg)
    local melee, heal, ranged, dps = {}, {}, {}, {}
    for _, m in ipairs(members) do
      if m.role == "HEALER" then heal[#heal + 1] = m
      elseif m.role ~= "TANK" then
        dps[#dps + 1] = m
        if m.range == "melee" then melee[#melee + 1] = m else ranged[#ranged + 1] = m end
      end
    end
    if kind == "set" then
      for _, l in ipairs({ melee, heal, ranged }) do if l[k] then out[#out + 1] = l[k] end end
    else
      if heal[k] then out[#out + 1] = heal[k] end
      for i = (k - 1) * 3 + 1, k * 3 do if dps[i] then out[#out + 1] = dps[i] end end
    end
  end
  return out
end

-- Fill the empty rows; returns how many rows got names.
function Plan:Suggest(bossKey, diff, members)
  members = members or R.Roster:Members()
  local st = self:State(bossKey, diff, true)
  local filled = 0
  for _, r in ipairs(self:Rows(bossKey, diff)) do
    if r.data and #r.names == 0 then
      local cands = self:Candidates(r.fill, members, r.kind == "group" and nil or r.n)
      if #cands > 0 then
        local rs = RowState(st, r.id)
        for _, m in ipairs(cands) do rs.names[#rs.names + 1] = m.name end
        filled = filled + 1
      end
    end
  end
  if filled > 0 then R:Fire("PLAN_CHANGED") end
  return filled
end

function Plan:Count(bossKey, diff)
  local c = {}
  for _, r in ipairs(self:Rows(bossKey, diff)) do
    for _, n in ipairs(r.names) do c[n] = (c[n] or 0) + 1 end
  end
  return c
end

-- Rows that name `name` (the boss window's "Your jobs").
function Plan:JobsFor(bossKey, diff, name)
  local out = {}
  if not name then return out end
  for _, r in ipairs(self:Rows(bossKey, diff)) do
    for i, n in ipairs(r.names) do
      if n == name then out[#out + 1] = { row = r, pos = i } end
    end
  end
  return out
end

-- Chat lines: a header, then one line per row that has names (kick orders with " > ").
function Plan:ChatLines(bossKey, diff)
  local b = D.BOSSES[bossKey]
  local rows = self:Rows(bossKey, diff)
  local lines = {}
  local any = false
  for _, r in ipairs(rows) do
    if #r.names > 0 then
      any = true
      local sep = r.kind == "order" and " > " or ", "
      local text = (r.marker and ("{" .. r.marker .. "} ") or "") .. r.mech .. ": " .. table.concat(r.names, sep)
      for _, l in ipairs(ns.Util.ChatWrap("", R:ChatText(text), r.mech .. " (cont.): ", 250)) do lines[#lines + 1] = l end
    end
  end
  if not any then return nil end
  table.insert(lines, 1, string.format("[Ensemble] %s (%s) plan", b and b.name or bossKey, R:DiffLabel(diff)))
  local lust = b and (b.lust[R:DataDiff(diff)] or b.lust.N)
  return lines, lust
end
