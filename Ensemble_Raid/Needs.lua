-- Ensemble Raid (test build) / Needs.lua
-- Coverage for one boss at one difficulty: every need the boss carries up to that difficulty
-- (Normal is the baseline), plus the generic raid needs and the class buffs. Uses Ensemble's own
-- utility data (UD) and settings, so a talent source counts the same way it does in Mythic+.

local _, R = ...
if R.disabled then return end
local ns = R.ns
local UD = ns.UD
local D = R.Data

local Needs = {}
R.Needs = Needs

local function Names(list, max)
  max = max or 8
  local out = {}
  for i = 1, math.min(#list, max) do out[i] = list[i] end
  local s = table.concat(out, ", ")
  if #list > max then s = s .. string.format(" and %d more", #list - max) end
  return s
end

-- The needs that apply at `diff` for `bossKey`, generic ones first; a boss need replaces a generic
-- one of the same kind and key (the Coiled Altar's healer share on Heroic).
function Needs:List(bossKey, diff)
  local b = D.BOSSES[bossKey]
  local list, byKey = {}, {}
  local function Put(n)
    local k = n.kind .. ":" .. n.key
    if byKey[k] then list[byKey[k]] = n else list[#list + 1] = n; byKey[k] = #list end
  end
  for _, n in ipairs(D.GENERIC_NEEDS) do Put(n) end
  local applies = {}
  for _, n in ipairs(b and b.needs or {}) do if R:Applies(n.d, diff) then applies[#applies + 1] = n end end
  -- A higher-difficulty entry of the same kind/key wins over a lower one.
  table.sort(applies, function(a, c) return D.DIFFS[a.d].rank < D.DIFFS[c.d].rank end)
  for _, n in ipairs(applies) do Put(n) end
  return list
end

-- Needs that start above this difficulty (shown as a count with "Show").
function Needs:Above(bossKey, diff)
  local b = D.BOSSES[bossKey]
  local out = {}
  for _, n in ipairs(b and b.needs or {}) do
    if not R:Applies(n.d, diff) then out[#out + 1] = n end
  end
  return out
end

local function Providers(members, cap)
  local solid, soft = {}, {}
  local settings = ns.db and ns.db.settings
  for _, m in ipairs(members) do
    local p = R.Roster:Profile(m)
    local src = p and UD:Sources(p, cap, settings)
    if src and #src > 0 then
      local isSolid = false
      for _, e in ipairs(src) do if not UD:IsSoft(e) then isSolid = true end end
      local label = m.name .. (m.pending and " (spec pending)" or "")
      if isSolid then solid[#solid + 1] = label else soft[#soft + 1] = label .. " (talent)" end
    end
  end
  return solid, soft
end

function Needs:HealerTarget(n, count)
  return math.max(2, math.floor(count.total * (n.share or 0.2) + 0.999))
end

-- One row: { status = "ok"|"thin"|"miss", label, detail, need }.
function Needs:Row(n, members, count)
  local label = n.label or (n.kind == "cap" and UD:CapShort(n.key)) or n.key
  local note = n.note and (" (" .. n.note .. ")") or ""
  if n.kind == "cap" then
    local solid, soft = Providers(members, n.key)
    local all = {}
    for _, s in ipairs(solid) do all[#all + 1] = s end
    for _, s in ipairs(soft) do all[#all + 1] = s end
    local min = n.min or 1
    local status
    if #all == 0 then status = "miss" elseif #solid < min then status = "thin" else status = "ok" end
    local detail
    if #all == 0 then detail = "Nobody here brings it" .. note
    else detail = string.format("%d can: %s%s", #all, Names(all), note) end
    if n.unconfirmed then detail = detail .. " [unconfirmed]" end
    return { status = status, label = label, detail = detail, need = n }
  elseif n.kind == "role" then
    local have = count[n.key] or 0
    local want = n.key == "TANK" and (n.min or 2) or self:HealerTarget(n, count)
    local status = have == 0 and "miss" or (have < want and "thin" or "ok")
    local detail
    if n.key == "TANK" then detail = string.format("%d of %d", have, want)
    else detail = string.format("%d of %d suggested for %d players%s", have, want, count.total, note ~= "" and note or " (about 1 in 5)") end
    return { status = status, label = label, detail = detail, need = n }
  elseif n.kind == "class" then
    local found = {}
    for cls in tostring(n.key):gmatch("[^,]+") do
      for _, m in ipairs(members) do if m.class == cls then found[#found + 1] = m.name end end
    end
    local status = #found >= (n.min or 1) and "ok" or (#found > 0 and "thin" or "miss")
    local detail = #found > 0 and (Names(found) .. note) or ("Nobody here" .. note)
    return { status = status, label = label, detail = detail, need = n }
  elseif n.kind == "range" then
    local found = {}
    for _, m in ipairs(members) do if m.range == n.key then found[#found + 1] = m.name end end
    local status = #found >= (n.min or 1) and "ok" or (#found > 0 and "thin" or "miss")
    return { status = status, label = label, detail = string.format("%d %s%s", #found, n.key, note), need = n }
  end
  return { status = "thin", label = label, detail = "unknown need", need = n }
end

-- Class buffs: which of Ensemble's buffs the raid has (a class present brings it).
function Needs:Buffs(members)
  local have, missing = {}, {}
  local classes = {}
  for _, m in ipairs(members) do if m.class then classes[m.class] = true end end
  for _, b in ipairs(UD.BUFFS or {}) do
    if classes[b.class] then have[#have + 1] = b.name else missing[#missing + 1] = b.name end
  end
  return have, missing
end

-- The whole check: rows in data order, the buff row, and what's hidden above this difficulty.
function Needs:Evaluate(bossKey, diff, members)
  members = members or R.Roster:Members()
  local count = R.Roster:Counts(members)
  local rows = {}
  for _, n in ipairs(self:List(bossKey, diff)) do rows[#rows + 1] = self:Row(n, members, count) end
  local have, missing = self:Buffs(members)
  rows[#rows + 1] = {
    status = #missing == 0 and "ok" or "thin", label = "Class buffs",
    detail = #missing == 0 and string.format("all %d present", #have) or ("missing: " .. table.concat(missing, ", ")),
    info = true,
  }
  local gaps = 0
  for _, r in ipairs(rows) do if r.status ~= "ok" and not r.info then gaps = gaps + 1 end end
  return { rows = rows, above = self:Above(bossKey, diff), count = count, members = members, gaps = gaps }
end

-- "Post gaps": the needs that aren't OK, one line each.
function Needs:GapLines(result, bossKey, diff)
  local b = D.BOSSES[bossKey]
  local lines = {}
  local head = string.format("%s (%s) gaps:", b and b.name or bossKey, R:DiffLabel(diff))
  local parts = {}
  for _, r in ipairs(result.rows) do
    if r.status ~= "ok" then
      local tag = r.status == "miss" and "missing" or "thin"
      parts[#parts + 1] = string.format("%s %s", r.label, tag)
    end
  end
  if #parts == 0 then parts[1] = "none, every need covered" end
  for _, l in ipairs(R:Wrap(head .. " " .. table.concat(parts, "; "))) do lines[#lines + 1] = l end
  return lines
end
