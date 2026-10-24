-- Ensemble / Assignments.lua
-- Kick and dispel assignments for the selected dungeon, built from who is actually in
-- the group and how long each of their abilities takes to come back.
--
-- How it decides (all tunables in Assignments.TUNING):
--   * Must-kick casts are handled most dangerous first. Critical/high casts get a
--     rotation of two kickers where possible (or the requirement's own minProviders);
--     medium/low get one.
--   * Each kicker carries a "load": every cast they take adds severity x (cooldown / 15s),
--     so a 24s Counterspell fills up faster than a 15s Pummel and a 45s Silence is only
--     used when nothing shorter is free. The next cast goes to whoever is cheapest:
--     load + cooldown cost (+ a penalty for long-cooldown, pet or talent kicks, and for
--     healers, who kick only when the others are loaded; their kicks also count for more).
--   * Rotation order puts the shortest cooldown first; "every ~Ns" is the combined rate.
--   * Dispels: each must-dispel debuff gets a primary and a backup who can remove that
--     type. Load is tracked per COOLDOWN (one Nature's Cure covering Magic and Poison is
--     one cooldown), so two dangerous debuffs spread across dispellers when possible.
--     Healers are preferred for cleansing allies; non-healers for purge and soothe.
local _, ns = ...

local AS = {}
ns.Assignments = AS

AS.TUNING = {
  KICK_REF_CD = 15,        -- seconds that count as one unit of kick cost
  DISPEL_REF_CD = 8,
  LONG_PENALTY = 1.5,      -- extra cost for long-cooldown / pet / talent sources
  SOFT_PENALTY = 0.75,
  HEALER_DISPEL_BONUS = 0.3,
  HEALER_KICK_PENALTY = 1.0, -- healers are busy healing: they kick only when others are loaded
  HEALER_KICK_LOAD = 1.5,    -- and each kick they do take counts for more
  ROTATION_FOR = { critical = 2, high = 2, medium = 1, low = 1 },
  SEV_WEIGHT = { critical = 3, high = 2, medium = 1, low = 0.5 },
  OVERLOAD = 6,            -- load above which a player is flagged as overloaded
}
local T = AS.TUNING
local SEV_RANK = { critical = 1, high = 2, medium = 3, low = 4 }

local DISPEL_KEYS = {
  dispel_magic = "Magic", dispel_curse = "Curse", dispel_poison = "Poison", dispel_disease = "Disease",
  dispel_bleed = "Bleed", purge = "Purge", soothe = "Soothe",
}
AS.DISPEL_KEYS = DISPEL_KEYS

local DEFENSIVE = { external_defensive = true, group_defensive = true }


-- Short name of a requirement's ability: "Lightning Bolt (Storm Adept)" -> "Lightning Bolt".
function AS.CastName(req)
  local src = req.source or ""
  return ((src:match("^([^,(]+)") or src):gsub("%s+$", ""))
end

-- Every member's best (shortest-cooldown) source of `key`.
local function Candidates(r, key, settings)
  local UD = ns.UD
  local out = {}
  for i, m in ipairs(r.members) do
    local best
    for _, e in ipairs(UD:Sources(m.profile, key, settings) or {}) do
      local cd, known = UD:Cooldown(e.name, key)
      local soft = e.pet or (e.talent and not e.core) or e.conditional or e.verify or m.pending
      local c = { index = i, member = m, label = m.label, entry = e, ability = e.name, cd = cd, cdKnown = known,
                  long = e.long or cd >= 30, soft = soft and true or false,
                  group = UD.COOLDOWN_GROUP[e.name] or e.name }
      if not best or c.cd < best.cd or (c.cd == best.cd and best.soft and not c.soft) then best = c end
    end
    if best then out[#out + 1] = best end
  end
  return out
end

-- Distinct, readable labels (two "Fury Warrior"s in the Builder become "Fury Warrior" and
-- "Fury Warrior (2)").
local function Labels(r)
  local seen, out = {}, {}
  for i, m in ipairs(r.members) do
    local l = m.label or ("Player " .. i)
    seen[l] = (seen[l] or 0) + 1
    out[i] = seen[l] > 1 and (l .. " (" .. seen[l] .. ")") or l
  end
  return out
end

local function Who(c, labels)
  return { index = c.index, label = labels[c.index], ability = c.ability, cd = c.cd, cdKnown = c.cdKnown,
           long = c.long, soft = c.soft, pending = c.member.pending, role = c.member.role, key = c.key,
           class = c.member.classFile, isPlayer = c.member.isPlayer }
end

---------------------------------------------------------------------------
-- Your own changes: who kicks or dispels a cast, picked by hand (Plan tab). Kept for this
-- session only and checked against the group: an override names each player by slot AND
-- spec, so it stops applying the moment that player changes or leaves.
--   AS.overrides[reqId] = { kind = "kick", who = { {index, spec}, ... } }   (kick order)
--                       | { kind = "dispel", who = { {index, spec} } }      (primary)
---------------------------------------------------------------------------
AS.overrides = {}
AS.overrideVersion = 0

local function MemberSpec(m) return tostring(m and (m.specID or m.classFile) or "?") end

local function Changed()
  AS.overrideVersion = AS.overrideVersion + 1
  if ns.BossCards and ns.BossCards.ClearPlanCache then ns.BossCards:ClearPlanCache() end
  if ns.Fire then ns:Fire("ASSIGNMENTS_CHANGED") end
end

-- Members (in order) an override names who are still in the group with that spec, else nil.
local function OverrideWho(r, o)
  local out = {}
  for _, w in ipairs(o.who or {}) do
    local m = r.members[w.index]
    if not m or MemberSpec(m) ~= w.spec then return nil end
    out[#out + 1] = w.index
  end
  return #out > 0 and out or nil
end

function AS:HasOverride(reqId) return self.overrides[reqId] ~= nil end

function AS:SetOverride(r, reqId, kind, indexes)
  if not indexes or #indexes == 0 then self.overrides[reqId] = nil; Changed(); return end
  local who = {}
  for _, i in ipairs(indexes) do who[#who + 1] = { index = i, spec = MemberSpec(r.members[i]) } end
  self.overrides[reqId] = { kind = kind, who = who }
  Changed()
end

function AS:ClearOverride(reqId) self.overrides[reqId] = nil; Changed() end
function AS:ClearOverrides() self.overrides = {}; Changed() end
function AS:OverrideCount() local n = 0 for _ in pairs(self.overrides) do n = n + 1 end return n end

-- Everyone in the group who could take this cast: { {index, label, ability, cd} } (shortest cooldown first).
function AS:Choices(r, req, settings)
  settings = settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings
  local key = req.need == "interrupt" and "interrupt" or (DISPEL_KEYS[req.need] and req.need)
  if not key then return {} end
  local labels = Labels(r)
  local out = {}
  for _, c in ipairs(Candidates(r, key, settings)) do
    out[#out + 1] = { index = c.index, label = labels[c.index], ability = c.ability, cd = c.cd, class = c.member.classFile }
  end
  table.sort(out, function(a, b) if a.cd ~= b.cd then return a.cd < b.cd end return a.index < b.index end)
  return out, key == "interrupt" and "kick" or "dispel"
end

-- Build the plan from an Analysis result (needs r.dungeon).
-- Returns { kicks = {row}, dispels = {row}, byReq = {reqId -> row}, people = {summary}, empty = bool }
function AS:Build(r, settings)
  settings = settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings
  local plan = { kicks = {}, dispels = {}, byReq = {}, people = {} }
  if not (r and r.dungeon and r.dungeon.items) or r.filled == 0 then plan.empty = true; return plan end
  local labels = Labels(r)
  plan.labels = labels
  local load, kickCount, dispelCount = {}, {}, {}

  -- Requirements, most dangerous first (stable by id).
  local items = {}
  for _, it in ipairs(r.dungeon.items) do
    if not it.aggregate and not it.req.invalid then items[#items + 1] = it end
  end
  table.sort(items, function(a, b)
    local x, y = SEV_RANK[a.req.severity] or 9, SEV_RANK[b.req.severity] or 9
    if x ~= y then return x < y end
    return tostring(a.req.id) < tostring(b.req.id)
  end)

  -- Kicks
  local kickers = Candidates(r, "interrupt", settings)
  for _, c in ipairs(kickers) do c.key = "interrupt" end
  for _, it in ipairs(items) do
    local req = it.req
    -- Kick rows only where the cast's main answer is an interrupt (an "or interrupt"
    -- alternative, like Ascendant's orbs, is a stop job, not a kick rotation).
    if req.need == "interrupt" then
      local sev = req.severity or "medium"
      local want = math.max(req.minProviders or 1, T.ROTATION_FOR[sev] or 1)
      local row = { req = req, item = it, cast = AS.CastName(req), severity = sev, want = want, kickers = {}, notes = {} }
      local pool = {}
      for _, c in ipairs(kickers) do
        local cost = (load[c.index] or 0) + c.cd / T.KICK_REF_CD
          + (c.long and T.LONG_PENALTY or 0) + (c.soft and T.SOFT_PENALTY or 0)
          + (c.member.role == "HEALER" and T.HEALER_KICK_PENALTY or 0)
        pool[#pool + 1] = { c = c, cost = cost }
      end
      table.sort(pool, function(a, b)
        if math.abs(a.cost - b.cost) > 1e-6 then return a.cost < b.cost end
        return a.c.index < b.c.index
      end)
      local n = math.min(want, #pool)
      local chosen = {}
      local o = self.overrides[req.id]
      local forced = o and o.kind == "kick" and OverrideWho(r, o)
      if forced then
        local byIndex = {}
        for _, e in ipairs(pool) do byIndex[e.c.index] = e end
        for _, idx in ipairs(forced) do if byIndex[idx] then chosen[#chosen + 1] = byIndex[idx].c end end
        if #chosen == 0 then forced = nil end
      end
      if forced then
        -- your order stands; the backup is the best of the rest
        local used = {}
        for _, c in ipairs(chosen) do used[c.index] = true end
        local rest = {}
        for _, e in ipairs(pool) do if not used[e.c.index] then rest[#rest + 1] = e end end
        pool = {}
        for i, c in ipairs(chosen) do pool[i] = { c = c } end
        for _, e in ipairs(rest) do pool[#pool + 1] = e end
        n = #chosen
        row.manual = true
      else
        for i = 1, n do chosen[i] = pool[i].c end
        table.sort(chosen, function(a, b) if a.cd ~= b.cd then return a.cd < b.cd end return a.index < b.index end)
      end
      local rate = 0
      for _, c in ipairs(chosen) do
        row.kickers[#row.kickers + 1] = Who(c, labels)
        load[c.index] = (load[c.index] or 0) + (T.SEV_WEIGHT[sev] or 1) * (c.cd / T.KICK_REF_CD)
          * (c.member.role == "HEALER" and T.HEALER_KICK_LOAD or 1)
        kickCount[c.index] = (kickCount[c.index] or 0) + 1
        if c.cd > 0 then rate = rate + 1 / c.cd end
      end
      if pool[n + 1] then row.backup = Who(pool[n + 1].c, labels) end
      if rate > 0 then row.every = math.floor(1 / rate + 0.5) end
      -- No kicker at all: fall back to whoever can stop it, if the cast allows that.
      if #chosen == 0 then
        local alts = {}
        if req.need ~= "interrupt" then alts[#alts + 1] = req.need end
        for _, a in ipairs(req.alt or {}) do if a ~= "interrupt" then alts[#alts + 1] = a end end
        for _, a in ipairs(alts) do
          for _, p in ipairs(r.caps[a] or {}) do
            row.stoppers = row.stoppers or {}
            if #row.stoppers < 2 then
              row.stoppers[#row.stoppers + 1] = { index = p.index, label = labels[p.index], ability = p.entry.name, key = a,
                class = p.member.classFile, isPlayer = p.member.isPlayer }
            end
          end
        end
        row.notes[#row.notes + 1] = row.stoppers and "Nobody can kick this: stop it instead." or "Nobody in the group can kick or stop this."
        row.severe = true
      else
        local allLong = true
        for _, c in ipairs(chosen) do if not c.long then allLong = false end end
        if allLong then
          row.notes[#row.notes + 1] = string.format("Only long-cooldown kicks (%s %ds): expect to miss casts; plan stops.",
            chosen[1].ability, chosen[1].cd)
          row.severe = true
        elseif #chosen < want and not row.manual then
          row.notes[#row.notes + 1] = string.format("Wants %d kickers in rotation; the group has %d.", want, #chosen)
        end
      end
      plan.kicks[#plan.kicks + 1] = row
      plan.byReq[req.id] = row
    end
  end

  -- Dispels / purge / soothe
  local groupLoad, groupUse = {}, {}
  local cands = {}
  for key in pairs(DISPEL_KEYS) do
    cands[key] = Candidates(r, key, settings)
    for _, c in ipairs(cands[key]) do c.key = key end
  end
  for _, it in ipairs(items) do
    local req = it.req
    local key = DISPEL_KEYS[req.need] and req.need
    if key then
      local sev = req.severity or "medium"
      local row = { req = req, item = it, cast = AS.CastName(req), severity = sev, type = DISPEL_KEYS[key], key = key, notes = {} }
      local friendly = key:find("^dispel_") ~= nil
      local pool = {}
      for _, c in ipairs(cands[key]) do
        local gk = c.index .. ":" .. c.group
        local cost = (groupLoad[gk] or 0) + c.cd / T.DISPEL_REF_CD
          + (c.long and T.LONG_PENALTY or 0) + (c.soft and T.SOFT_PENALTY or 0)
        if c.member.role == "HEALER" then
          cost = cost + (friendly and -T.HEALER_DISPEL_BONUS or T.HEALER_DISPEL_BONUS)
        end
        pool[#pool + 1] = { c = c, cost = cost, gk = gk }
      end
      table.sort(pool, function(a, b)
        if math.abs(a.cost - b.cost) > 1e-6 then return a.cost < b.cost end
        return a.c.index < b.c.index
      end)
      local o = self.overrides[req.id]
      local forced = o and o.kind == "dispel" and OverrideWho(r, o)
      if forced then
        for i, e in ipairs(pool) do
          if e.c.index == forced[1] then table.remove(pool, i); table.insert(pool, 1, e); row.manual = true; break end
        end
      end
      if pool[1] then
        local c = pool[1].c
        row.primary = Who(c, labels)
        if pool[2] then row.backup = Who(pool[2].c, labels)
        elseif sev == "critical" then row.notes[#row.notes + 1] = "No backup dispeller." end
        local gk = pool[1].gk
        -- Shared cooldown: this ability already answers another debuff, one of them dangerous.
        local prior = groupUse[gk]
        local dangerous = sev == "critical" or sev == "high"
        if prior and prior.cast ~= row.cast and (dangerous or prior.dangerous) then
          row.notes[#row.notes + 1] = string.format("%s also covers %s on the same cooldown.", c.ability, prior.cast)
        end
        if not prior or (dangerous and not prior.dangerous) then groupUse[gk] = { cast = row.cast, dangerous = dangerous } end
        groupLoad[gk] = (groupLoad[gk] or 0) + (T.SEV_WEIGHT[sev] or 1) * (math.max(c.cd, 1) / T.DISPEL_REF_CD)
        dispelCount[c.index] = (dispelCount[c.index] or 0) + 1
        if c.long and not (pool[2] and not pool[2].c.long) then
          row.notes[#row.notes + 1] = string.format("Only %s (%ds): one cleanse per %ds - plan defensives.", c.ability, c.cd, c.cd)
          row.severe = true
        end
      else
        -- Nobody can dispel it: whoever covers the requirement's alternative (e.g. a stun
        -- instead of a soothe, freedom instead of a Magic dispel) takes it.
        -- A defensive "alternative" (Intervene, Guardian Spirit...) isn't a job for one
        -- player: the group is told to use defensives instead.
        local defs = {}
        for _, a in ipairs(req.alt or {}) do
          for _, p in ipairs(r.caps[a] or {}) do
            if DEFENSIVE[a] then
              if #defs < 3 then defs[#defs + 1] = p.entry.name end
            else
              row.stoppers = row.stoppers or {}
              if #row.stoppers < 2 then
                row.stoppers[#row.stoppers + 1] = { index = p.index, label = labels[p.index], ability = p.entry.name, key = a,
                  class = p.member.classFile, isPlayer = p.member.isPlayer }
              end
            end
          end
        end
        local verb = key == "soothe" and "soothe" or key == "purge" and "purge" or "dispel"
        if row.stoppers then
          row.notes[#row.notes + 1] = "Nobody can " .. verb .. " this: handle it as shown instead."
        elseif #defs > 0 then
          row.defensives = defs
          row.notes[#row.notes + 1] = "Nobody can " .. verb .. " this: use defensives (" .. table.concat(defs, ", ") .. ")."
          row.severe = it.status ~= "covered"
        else
          row.notes[#row.notes + 1] = "Nobody in the group can remove this."
          row.severe = it.status ~= "covered"
        end
      end
      plan.dispels[#plan.dispels + 1] = row
      plan.byReq[req.id] = row
    end
  end

  -- Per-player summary. "Heavy" = clearly more kick load than the others carry.
  local sum, n = 0, 0
  for i in ipairs(r.members) do if load[i] then sum = sum + load[i]; n = n + 1 end end
  local mean = n > 0 and sum / n or 0
  for i in ipairs(r.members) do
    if (kickCount[i] or 0) + (dispelCount[i] or 0) > 0 then
      local l = load[i] or 0
      plan.people[#plan.people + 1] = { index = i, label = labels[i], kicks = kickCount[i] or 0,
        dispels = dispelCount[i] or 0, load = l, overloaded = n > 1 and l > T.OVERLOAD and l > mean * 1.4 }
    end
  end
  plan.kickCasts, plan.dispelCasts = #plan.kicks, #plan.dispels
  table.sort(plan.people, function(a, b) return a.index < b.index end)
  plan.empty = #plan.kicks == 0 and #plan.dispels == 0
  return plan
end

---------------------------------------------------------------------------
-- Who does what, one entry per player (the chat post and "Your assignments" both read this, so
-- the window and chat always say the same thing). Kicks are owned per cast: "1st" takes
-- the next cast, "2nd" the one after; with several casters at once each owner kicks their
-- own cast first, then helps. Low-severity rows are left out unless `withLow`.
---------------------------------------------------------------------------
local function Ord(n) return n == 1 and "1st" or n == 2 and "2nd" or n == 3 and "3rd" or (n .. "th") end
AS.Ord = Ord

-- The mob that casts it, from the requirement's source: "Lightning Bolt (Storm Adept,
-- Imbued Stormcaller)" -> "Storm Adept". Nil for bosses, "adds" and other descriptions.
function AS.MobName(req)
  local inner = ((req and req.source) or ""):match("%((.-)%)")
  if not inner then return nil end
  local first = (inner:match("^([^,;]+)") or inner):gsub("%s+$", "")
  first = first:gsub(" channel.*$", ""):gsub(" trash.*$", ""):gsub(" shields.*$", "")
  if first == "" or first:match("^%l") then return nil end
  return first
end

local function ShortName(label) return (label or "?"):match("^([^%-]+)") or label end
AS.ShortName = ShortName

function AS:PlayerJobs(plan, withLow)
  local jobs, list = {}, {}
  local function J(i, label)
    local key = i or label or "?"
    if not jobs[key] then
      jobs[key] = { index = i, label = label or (plan.labels and plan.labels[i]) or ("Player " .. tostring(i)),
                    kicks = {}, stops = {}, dispels = {}, backups = {}, n = #list + 1 }
      list[#list + 1] = jobs[key]
    end
    return jobs[key]
  end
  for i, l in ipairs(plan.labels or {}) do J(i, l) end
  local function keep(row) return withLow or row.severity ~= "low" end
  for _, row in ipairs(plan.kicks) do
    if keep(row) then
      local n = #row.kickers
      for pos, k in ipairs(row.kickers) do
        table.insert(J(k.index, k.label).kicks, { row = row, cast = row.cast, mob = AS.MobName(row.req),
          pos = n > 1 and pos or nil, of = n, ability = k.ability, cd = k.cd, isPlayer = k.isPlayer })
      end
      if row.backup then table.insert(J(row.backup.index, row.backup.label).backups, { row = row, cast = row.cast, kick = true }) end
      for _, st in ipairs(row.stoppers or {}) do
        table.insert(J(st.index, st.label).stops, { row = row, cast = row.cast, ability = st.ability })
      end
    end
  end
  for _, row in ipairs(plan.dispels) do
    if keep(row) then
      if row.primary then
        table.insert(J(row.primary.index, row.primary.label).dispels, { row = row, cast = row.cast, type = row.type, ability = row.primary.ability })
      end
      if row.backup then table.insert(J(row.backup.index, row.backup.label).backups, { row = row, cast = row.cast, type = row.type }) end
      for _, st in ipairs(row.stoppers or {}) do
        table.insert(J(st.index, st.label).stops, { row = row, cast = row.cast, ability = st.ability, instead = row.type })
      end
    end
  end
  table.sort(list, function(a, b)
    if a.index and b.index then return a.index < b.index end
    return a.n < b.n
  end)
  return list
end

-- "Kick first if two cast at once": the top two severity tiers among kick casts, equal
-- casts joined with " / ". Nil when every cast is equally dangerous (nothing to rank).
function AS:Priority(plan)
  local tiers, seen = {}, {}
  for _, row in ipairs(plan.kicks) do
    if row.severity ~= "low" and (#row.kickers > 0 or row.stoppers) and not seen[row.cast] then
      seen[row.cast] = true
      local r = SEV_RANK[row.severity] or 9
      tiers[r] = tiers[r] or {}
      table.insert(tiers[r], row.cast)
    end
  end
  local ranks = {}
  for r in pairs(tiers) do ranks[#ranks + 1] = r end
  table.sort(ranks)
  if #ranks < 2 then return nil end
  return table.concat(tiers[ranks[1]], " / ") .. " > " .. table.concat(tiers[ranks[2]], " / ")
end

-- What nobody in the group can handle: { kicks = {cast}, dispels = {"Type (cast)"} }.
function AS:Uncovered(plan)
  -- dispelGroups: the uncovered dispels grouped by the defensives the group has for them
  -- (the same list the sheet's note names), in first-seen order; defs = {} means none.
  local out = { kicks = {}, dispels = {}, defensives = false, dispelGroups = {} }
  for _, row in ipairs(plan.kicks) do
    if row.severity ~= "low" and #row.kickers == 0 and not row.stoppers then out.kicks[#out.kicks + 1] = row.cast end
  end
  local byDefs = {}
  for _, row in ipairs(plan.dispels) do
    if row.severity ~= "low" and not row.primary and not row.stoppers then
      local what = row.type .. " (" .. row.cast .. ")"
      out.dispels[#out.dispels + 1] = what
      if row.defensives then out.defensives = true end
      local defs = row.defensives or {}
      local k = table.concat(defs, ", ")
      local g = byDefs[k]
      if not g then g = { defs = defs, what = {} }; byDefs[k] = g; out.dispelGroups[#out.dispelGroups + 1] = g end
      g.what[#g.what + 1] = what
    end
  end
  return out
end

local VERB = { Purge = "PURGE", Soothe = "SOOTHE" }

-- One player's line, without the name. style "full": casts with their mob, dispel types,
-- stop abilities and backups; "short": casts and dispel types only.
function AS:JobText(job, style, drop)
  local full = style ~= "short"
  drop = drop or {}
  local parts = {}
  if #job.kicks > 0 then
    local t = {}
    for _, k in ipairs(job.kicks) do
      t[#t + 1] = k.cast .. ((full and k.mob and not drop.mobs) and (" [" .. k.mob .. "]") or "") .. (k.pos and (" " .. Ord(k.pos)) or "")
    end
    parts[#parts + 1] = "KICK " .. table.concat(t, ", ")
  end
  if #job.stops > 0 then
    local t = {}
    for _, st in ipairs(job.stops) do t[#t + 1] = st.cast .. (full and (" (" .. st.ability .. ")") or "") end
    parts[#parts + 1] = "STOP " .. table.concat(t, ", ")
  end
  local byVerb, verbs = {}, {}
  for _, d in ipairs(job.dispels) do
    local v = VERB[d.type] or "DISPEL"
    if not byVerb[v] then byVerb[v] = {}; verbs[#verbs + 1] = v end
    local list = byVerb[v]
    if full then
      list[#list + 1] = d.cast .. (v == "DISPEL" and (" (" .. d.type .. ")") or "")
    elseif v == "DISPEL" then
      local dup = false
      for _, x in ipairs(list) do if x == d.type then dup = true end end
      if not dup then list[#list + 1] = d.type end
    else
      list[#list + 1] = d.cast
    end
  end
  for _, v in ipairs(verbs) do parts[#parts + 1] = v .. " " .. table.concat(byVerb[v], ", ") end
  if full and #job.backups > 0 and not drop.backups then
    local t, seen = {}, {}
    for _, b in ipairs(job.backups) do if not seen[b.cast] then seen[b.cast] = true; t[#t + 1] = b.cast end end
    parts[#parts + 1] = "Backup for " .. table.concat(t, ", ")
  end
  if #parts == 0 then return "no set assignments; help kick when free." end
  local text = table.concat(parts, ". ")
  return text:match("[%.!?]$") and text or (text .. ".")
end

local LINE_MAX = 250
-- A post line too long for one chat message goes on as "Name (cont.): ..." lines: nothing is
-- dropped or cut (every kick, stop, dispel and backup stays in the post).
local function Add(out, first, text, cont)
  for _, l in ipairs(ns.Util.ChatWrap(first, text, cont, LINE_MAX)) do out[#out + 1] = l end
end

-- Party-chat post: a header, one line per player (their name first, so everyone finds
-- their own), then the kick priority and anything nobody can handle. Plain text only.
function AS:ChatLines(plan, dungeonName, style)
  if not plan or plan.empty then return {} end
  local out = {}
  local where = dungeonName and (" " .. dungeonName) or ""
  if style == "short" then
    out[1] = "[Ensemble]" .. where .. " assignments:"
  else
    out[1] = "[Ensemble]" .. where .. " assignments. Kick your own casts first, help when free. 1st/2nd = who takes the next cast:"
  end
  for _, job in ipairs(self:PlayerJobs(plan)) do
    local name = ShortName(job.label)
    Add(out, name .. ": ", self:JobText(job, style), name .. " (cont.): ")
  end
  local pri = self:Priority(plan)
  if pri then Add(out, "Kick first if two cast at once: ", pri, "Kick first (cont.): ") end
  local un = self:Uncovered(plan)
  -- Name the defensives the group has (as the sheet's note does), or say there are none.
  for _, g in ipairs(un.dispelGroups) do
    local tail = #g.defs > 0 and (": use defensives (" .. table.concat(g.defs, ", ") .. ").")
      or (", and nobody has a defensive for " .. (#g.what > 1 and "them." or "it."))
    Add(out, "Nobody can remove ", table.concat(g.what, ", ") .. tail, "Nobody can remove (cont.): ")
  end
  if #un.kicks > 0 then
    Add(out, "Nobody can kick ", table.concat(un.kicks, ", ") .. ": CC or defensives.", "Nobody can kick (cont.): ")
  end
  return out
end
