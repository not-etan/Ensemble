-- Ensemble / Brief.lua
-- "Your brief" (1.7.0): one dungeon, for your own spec. What you kick, stop, dispel and use a
-- defensive on, what isn't yours but can end the key, and the Bloodlust plan. Built from the
-- same analysis and kick / dispel plan as the Plan tab, so the two never disagree.
--
-- No group needed: alone, every cast your spec can answer is yours ("First:" for the critical
-- and high ones, "When free:" for the rest). In a group the plan decides: "Yours" names the
-- casts you own and who shares them; the rest of what you could take is "When free" or
-- "Backup on". Trash you hid on the Dungeon tab or in the boss window is left out and counted.
local _, ns = ...

local Brief = {}
ns.Brief = Brief

local BIG = { critical = true, high = true }
local SEV_RANK = { critical = 1, high = 2, medium = 3, low = 4 }

local function Settings() return (ns.db and ns.db.settings) or ns.DEFAULTS.settings end

-- How many abilities a source names: "Sunder Slam, Lightning Bite (Krolusk)" -> 2.
local function CountNames(source)
  local flat = tostring(source or ""):gsub("%b()", "")
  local n = 0
  for part in flat:gmatch("[^,]+") do if part:find("%S") then n = n + 1 end end
  return math.max(1, n)
end
Brief.CountNames = CountNames

-- A member's ability names for a need, shortest cooldown first (at most `max`).
local function Abilities(member, key, max)
  local UD = ns.UD
  local list = {}
  for _, e in ipairs(UD:Sources(member.profile, key, Settings()) or {}) do
    list[#list + 1] = { name = e.name, cd = (UD:Cooldown(e.name, key)) or 0 }
  end
  table.sort(list, function(a, b) if a.cd ~= b.cd then return a.cd < b.cd end return a.name < b.name end)
  local out = {}
  for i = 1, math.min(max or #list, #list) do out[i] = list[i].name end
  return out, #list
end

local function Entry(row, extra)
  local AS = ns.Assignments
  local e = { req = row.req, cast = row.cast, mob = AS.MobName(row.req), severity = row.severity, big = BIG[row.severity] or false, row = row }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

local function SortEntries(list)
  table.sort(list, function(a, b)
    local x, y = SEV_RANK[a.severity] or 9, SEV_RANK[b.severity] or 9
    if x ~= y then return x < y end
    return tostring(a.req.id) < tostring(b.req.id)
  end)
  return list
end

-- The other owners of a row, as { label, class } (you left out).
local function Partners(owners, me)
  local out = {}
  for _, w in ipairs(owners or {}) do
    if w.index ~= me then out[#out + 1] = { label = w.label, class = w.class } end
  end
  return out
end

local function PartnerKey(list)
  local t = {}
  for _, p in ipairs(list) do t[#t + 1] = tostring(p.label) end
  return table.concat(t, "\0")
end

-- Build the brief from an analysis `r` (it must hold a member flagged `isPlayer`) and its
-- plan. Returns nil when you aren't in the group or the dungeon is unknown.
--   { dk, spec, solo, level,
--     kick    = { abilities, mine = {entry}, free = {entry}, backup = {entry}, shared = {partner}|nil, none = bool },
--     stop    = { abilities, mine = {entry}, also = {entry} },
--     dispel  = { mine = {entry}, backup = {entry} },
--     defense = { label, mine = {entry}, count },
--     notYours = { entry + why },
--     lust = { uses, custom, yours },
--     skipped = N (trash rows you hid), rest = N (medium and low rows not shown as yours) }
function Brief:Build(dk, r, plan)
  local DD, AS, UD = ns.Dungeons, ns.Assignments, ns.UD
  if not (dk and DD.list[dk] and r and r.members and plan) then return nil end
  local me
  for i, m in ipairs(r.members) do if m.isPlayer then me = i; break end end
  if not me then return nil end
  local m = r.members[me]
  local solo = #r.members == 1
  local b = { dk = dk, solo = solo, spec = m.label, role = m.role, classFile = m.classFile,
              level = ns.Affixes and ns.Affixes:KeyLevel(dk) or nil,
              kick = { mine = {}, free = {}, backup = {} }, stop = { mine = {}, also = {} },
              dispel = { mine = {}, backup = {} }, defense = { mine = {}, count = 0 }, notYours = {},
              skipped = #(plan.skipped or {}) }

  -- Kicks
  b.kick.abilities = Abilities(m, "interrupt", 1)
  b.kick.none = #b.kick.abilities == 0
  local partnerSets, firstSet = 0, nil
  for _, row in ipairs(plan.kicks or {}) do
    local mine, backup = false, row.backup and row.backup.index == me
    for _, k in ipairs(row.kickers or {}) do if k.index == me then mine = true end end
    if mine then
      local e = Entry(row, { partners = Partners(row.kickers, me) })
      if e.big then
        b.kick.mine[#b.kick.mine + 1] = e
        local key = PartnerKey(e.partners)
        if firstSet == nil then firstSet = key; partnerSets = 1 elseif key ~= firstSet then partnerSets = partnerSets + 1 end
      else
        b.kick.free[#b.kick.free + 1] = e
      end
    elseif backup then
      b.kick.backup[#b.kick.backup + 1] = Entry(row)
    elseif row.stoppers then
      for _, st in ipairs(row.stoppers) do
        if st.index == me then b.stop.mine[#b.stop.mine + 1] = Entry(row, { ability = st.ability, instead = "kick" }) end
      end
    elseif BIG[row.severity] and b.kick.none then
      local names = AS:OwnerNames({ kind = "kick", row = row })
      b.notYours[#b.notYours + 1] = Entry(row, { why = "Needs a kick; your spec has none." .. (names and (" " .. names .. " " .. (#row.kickers == 1 and "has" or "have") .. " it.") or " Nobody here can kick it.") })
    end
  end
  SortEntries(b.kick.mine); SortEntries(b.kick.free); SortEntries(b.kick.backup)
  -- Everyone you share your casts with is the same: say it once, in the heading.
  if partnerSets == 1 and b.kick.mine[1] and #b.kick.mine[1].partners > 0 then b.kick.shared = b.kick.mine[1].partners end

  -- Dispels, purges, soothes
  for _, row in ipairs(plan.dispels or {}) do
    if row.primary and row.primary.index == me then
      b.dispel.mine[#b.dispel.mine + 1] = Entry(row, { type = row.type, ability = row.primary.ability,
        backupWho = row.backup and { label = row.backup.label, class = row.backup.class } or nil,
        noBackup = (not row.backup and row.severity == "critical") or nil })
    elseif row.backup and row.backup.index == me then
      b.dispel.backup[#b.dispel.backup + 1] = Entry(row, { type = row.type })
    elseif BIG[row.severity] then
      local stopper
      for _, st in ipairs(row.stoppers or {}) do if st.index == me then stopper = st end end
      if stopper then
        b.stop.mine[#b.stop.mine + 1] = Entry(row, { ability = stopper.ability, instead = row.type })
      else
        local can = #(UD:Sources(m.profile, row.key, Settings()) or {}) > 0
        local verb = (row.type == "Purge" and "a purge") or (row.type == "Soothe" and "a soothe") or ("a " .. row.type .. " dispel")
        local who = row.primary and (AS.ShortName(row.primary.label) .. " takes it.") or "Nobody here can: use defensives."
        if solo then who = can and "" or "Bring someone who can, or use defensives." end
        b.notYours[#b.notYours + 1] = Entry(row, { type = row.type,
          why = "Needs " .. verb .. (can and "." or "; you can't remove it.") .. (who ~= "" and (" " .. who) or "") })
      end
    end
  end
  SortEntries(b.dispel.mine); SortEntries(b.dispel.backup)

  -- Stops, tank busters and the rest
  local stopNames = Abilities(m, "stop", 2)
  local aoe = Abilities(m, "aoe_stop", 1)
  for _, n in ipairs(aoe) do
    local dup = false
    for _, x in ipairs(stopNames) do if x == n then dup = true end end
    if not dup and #stopNames < 2 then stopNames[#stopNames + 1] = n end
  end
  b.stop.abilities = stopNames
  for _, row in ipairs(plan.others or {}) do
    local req = row.req
    local mine = false
    for _, w in ipairs(row.who or {}) do if w.index == me then mine = true end end
    local tank = DD:CategoryOf(req) == "tank"
    if tank then
      if m.role == "TANK" or m.role == "HEALER" then
        b.defense.mine[#b.defense.mine + 1] = Entry(row)
        b.defense.count = b.defense.count + CountNames(req.source)
      end
    elseif req.need == "stop" or req.need == "aoe_stop" then
      if mine then
        local e = Entry(row, { aoe = req.need == "aoe_stop" })
        if e.big then b.stop.mine[#b.stop.mine + 1] = e else b.stop.also[#b.stop.also + 1] = e end
      elseif BIG[row.severity] then
        local names = AS:OwnerNames({ kind = "other", row = row })
        b.notYours[#b.notYours + 1] = Entry(row, { why = "Needs " .. (req.need == "aoe_stop" and "an AoE stop" or "a stop") .. "; your spec has none."
          .. (names and (" Covered by " .. names .. ".") or " Nobody here has one.") })
      end
    elseif BIG[row.severity] then
      local label = UD:CapLabel(req.need)
      if mine then
        b.notYours[#b.notYours + 1] = Entry(row, { yours = true, why = "You can answer it (" .. label .. ")." })
      else
        local names = AS:OwnerNames({ kind = "other", row = row })
        b.notYours[#b.notYours + 1] = Entry(row, { why = "Needs " .. label .. "." .. (names and (" Covered by " .. names .. ".") or (solo and "" or " Nobody here has it.")) })
      end
    end
  end
  SortEntries(b.stop.mine); SortEntries(b.stop.also); SortEntries(b.defense.mine); SortEntries(b.notYours)
  b.defense.label = m.role == "TANK" and "tank busters" or "tank busters: heal through them or use an external"

  -- What the brief doesn't spell out: the medium and low rows that aren't yours.
  local shown = {}
  for _, list in ipairs({ b.kick.mine, b.kick.free, b.kick.backup, b.stop.mine, b.stop.also, b.dispel.mine, b.dispel.backup, b.defense.mine, b.notYours }) do
    for _, e in ipairs(list) do shown[e.req.id] = true end
  end
  b.rest = 0
  for _, e in ipairs(AS:Rows(plan)) do if not shown[e.row.req.id] then b.rest = b.rest + 1 end end

  -- Bloodlust
  local WT = ns.Walkthrough
  if WT then
    local uses, custom = WT:Lust(dk)
    b.lust = { uses = uses, custom = custom, yours = #(UD:Sources(m.profile, "bloodlust", Settings()) or {}) > 0 }
  end
  return b
end

-- Your brief for a dungeon with the group you're in right now (or just you): the boss
-- window's and the Dungeon tab's source. Returns brief, r, plan (nil when your spec isn't known).
function Brief:ForPlayer(dk)
  local BC = ns.BossCards
  if not (BC and dk) then return nil end
  local plan, r = BC:Plan(dk)
  if not (plan and r) then return nil end
  return self:Build(dk, r, plan), r, plan
end
