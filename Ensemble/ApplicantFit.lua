-- Ensemble / ApplicantFit.lua
-- Applicant fit analysis: for each Group Finder applicant (or premade applying together),
-- what utility they bring, how it complements the classes already in the group, how it
-- answers the selected dungeon's demands, and a color-coded rating.
--
-- Pure logic, no frames. Builds on Analysis (Analyze/Penalty) so the rating uses exactly
-- the same gap model as the rest of the addon.
--
-- How the score works (see DD.HEURISTICS for the tunable bands): a PICK rating, "how good a
-- pick is this person for this slot", against every other spec that could fill it.
--   gain  = how much the applicant reduces the group's gap penalty (generic + dungeon)
--   best / worst = the largest / smallest reduction any spec of the same role could give
--   score = 100 * (gain - worst) / (best - worst)
--           ("where this applicant sits between the least and most useful pick right now")
--   No real difference: when best - worst is under FIT_FLAT_SPREAD points, every applicant
--     of the role gets FIT_FLAT_SCORE and the card says to decide on experience.
--   Critical gaps (a critical dungeon need that is MISSING, or a critical generic gap):
--     full close (through a solid source of theirs): never rates below anyone who doesn't
--       fully close one, experience included;
--     partial close (only through a weak source: talent, pet, long cooldown, conditional,
--       unconfirmed, spec pending): floored at FIT_CRIT_PARTIAL_SHARE of the way from the
--       weakest pick to the best pick that closes nothing, and never lifted further.
--   Order (and the "Why N?" breakdown): pick position -> experience mix -> critical-gap floor
--     -> the cross-applicant lift for full closers (EvaluateAll) -> role-conflict cap.
-- An applicant whose role has no open slot is always rated POOR.
-- Look-ahead (the best way to fill the remaining slots) is NOT part of the score: it feeds the
-- headline ("OK if the last slot brings ...") and the notes. "Is the group OK?" is answered
-- separately, in plain words, by ev.groupAfter (Fit:GroupAfter), never as a second score.
--
-- Experience (when the key level is known and the client shares per-dungeon scores):
--   each applicant's best run of the listed dungeon this season, against the key level,
--   gives 0-100 (timed at or above the key = 100). The rating blends it in:
--   score = (1 - w) * utility fit + w * experience, with w from DD.HEURISTICS (10% up to +5,
--   20% to +9, 30% from +10). No key level or no data: utility fit alone, never a penalty.

local _, ns = ...

local Fit = {}
ns.ApplicantFit = Fit

local A, UD, DD -- resolved lazily

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local LOOKAHEAD_POOL = 5      -- specs per role considered when simulating the remaining slots
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local SLOTS_PER_ROLE = { TANK = 1, HEALER = 1, DAMAGER = 3 }

-- Ratings: color + icon + word, so they never rely on color alone.
-- Green / blue / amber / red is more distinguishable for red-green color blindness than
-- a green-to-red gradient.
Fit.RATINGS = {
  great = { key = "great", rank = 1, label = "GREAT FIT", word = "Great", color = { 0.33, 0.85, 0.47, 1 },
            hex = "|cff54d978", icon = "Interface\\RaidFrame\\ReadyCheck-Ready" },
  good  = { key = "good",  rank = 2, label = "GOOD FIT",  word = "Good",  color = { 0.45, 0.70, 1.00, 1 },
            hex = "|cff73b3ff", icon = "Interface\\RaidFrame\\ReadyCheck-Ready" },
  fair  = { key = "fair",  rank = 3, label = "FAIR FIT",  word = "Fair",  color = { 0.96, 0.72, 0.29, 1 },
            hex = "|cfff5b84a", icon = "Interface\\RaidFrame\\ReadyCheck-Waiting" },
  poor  = { key = "poor",  rank = 4, label = "POOR FIT",  word = "Poor",  color = { 0.93, 0.38, 0.38, 1 },
            hex = "|cffee6161", icon = "Interface\\RaidFrame\\ReadyCheck-NotReady" },
}
Fit.RATING_ORDER = { "great", "good", "fair", "poor" }

-- Capabilities worth calling out when an applicant adds or doubles them, in priority order.
local KEY_CAPS = {
  "interrupt", "battle_rez", "bloodlust", "dispel_magic", "dispel_curse", "dispel_poison",
  "dispel_disease", "aoe_stop", "stop", "purge", "soothe", "external_defensive", "freedom",
  "group_defensive", "dispel_bleed", "movement", "group_stealth",
}
-- Capabilities where a SECOND provider meaningfully removes a single point of failure.
local BACKUP_CAPS = {
  battle_rez = true, dispel_magic = true, dispel_curse = true, dispel_poison = true,
  dispel_disease = true, aoe_stop = true, external_defensive = true,
}
-- Capabilities where a second copy adds nothing (one is enough for the group).
local SINGLETON_CAPS = { bloodlust = true }

local function Init()
  A, UD, DD = ns.Analysis, ns.UD, ns.Dungeons
end

---------------------------------------------------------------------------
-- Critical gaps: confirmed critical dungeon needs that are MISSING, plus critical generic gaps.
-- Returns key -> info (same keys before and after, so closing one is a key that disappears).
---------------------------------------------------------------------------
function Fit.CriticalGaps(r)
  Init()
  local out = {}
  for _, f in ipairs(r.findings or {}) do
    if f.severity == "critical" and f.check ~= "pending" then
      out["g:" .. tostring(f.check) .. ":" .. tostring(f.short)] = { cap = f.cap,
        label = f.cap and UD:CapLabel(f.cap) or tostring(f.short) }
    end
  end
  for _, it in ipairs((r.dungeon and r.dungeon.items) or {}) do
    if it.status == "missing" and it.req.severity == "critical" and not it.unconfirmed then
      local src = it.req.source and ((it.req.source):gsub("%s*%(.-%)", "")) or nil
      out["d:" .. tostring(it.req.id)] = { id = it.req.id, need = it.req.need,
        label = UD:CapLabel(it.req.need) .. (src and src ~= "" and (" for " .. src) or "") }
    end
  end
  return out
end

-- "Mass Dispel, long cooldown": the ability that answers a need and why it's weak, if it is.
local function SourcePhrase(p)
  if not p then return nil end
  local e = p.entry or {}
  local why
  if p.member.pending then why = "spec not known yet"
  elseif e.conditional then why = tostring(e.conditional)
  elseif e.talent and not e.core then why = "talent"
  elseif e.pet then why = "pet"
  elseif e.long then why = "long cooldown"
  elseif e.verify then why = "unconfirmed" end
  return tostring(e.name or "?") .. (why and (", " .. why) or "")
end

-- How the members added to a group close its critical gaps (`baseGaps` from CriticalGaps).
-- A gap that was MISSING had no provider at all, so every provider it has afterwards is one of
-- the added members. Full: at least one of those sources is solid (UD:IsSoft is false and the
-- spec is known). Returns nil when nothing closes, else
-- { kind = "full"|"partial", closes = { { key, label, full, how } } } (full closes first).
function Fit.CriticalClose(baseGaps, after)
  Init()
  local now = Fit.CriticalGaps(after)
  local closes, anyFull = {}, false
  for k, g in pairs(baseGaps) do
    if not now[k] then
      local providers
      if g.id then
        for _, it in ipairs((after.dungeon and after.dungeon.items) or {}) do
          if it.req.id == g.id then providers = it.providers; break end
        end
      elseif g.cap then
        providers = after.caps and after.caps[g.cap]
      end
      local full, pick = false, nil
      for _, p in ipairs(providers or {}) do
        if not (p.member.pending or UD:IsSoft(p.entry)) then full, pick = true, p; break end
        pick = pick or p
      end
      -- No provider to judge (shouldn't happen): keep the long-standing rule and count it as full.
      if not pick then full = true end
      closes[#closes + 1] = { key = k, label = g.label or k, full = full, how = SourcePhrase(pick) }
      if full then anyFull = true end
    end
  end
  if #closes == 0 then return nil end
  table.sort(closes, function(a, b)
    if a.full ~= b.full then return a.full end
    return a.key < b.key
  end)
  return { kind = anyFull and "full" or "partial", closes = closes }
end

function Fit.ClosesCritical(baseGaps, after)
  return Fit.CriticalClose(baseGaps, after) ~= nil
end

-- Critical-gap floors for one role from every spec's { gain, kind } (kind = nil / "partial" /
-- "full"): the 0-1 position a full closer can't fall below (the best pick that doesn't fully
-- close a gap) and the one a partial closer can't fall below (FIT_CRIT_PARTIAL_SHARE of the way
-- to the best pick that closes nothing). nil when no spec of that kind exists or no real spread.
function Fit.CritFloors(entries, best, worst)
  local nonCloser, nonFull, anyFull, anyPartial
  for _, e in ipairs(entries) do
    if e.kind == "full" then anyFull = true
    else
      if not nonFull or e.gain > nonFull then nonFull = e.gain end
      if e.kind == "partial" then anyPartial = true
      elseif not nonCloser or e.gain > nonCloser then nonCloser = e.gain end
    end
  end
  local full = anyFull and nonFull and Fit.Relative(nonFull, best, worst) or nil
  local partial
  if anyPartial and nonCloser then
    local rel = Fit.Relative(nonCloser, best, worst)
    if rel then partial = rel * (ns.Dungeons.HEURISTICS.FIT_CRIT_PARTIAL_SHARE or 0.5) end
  end
  return full, partial
end

-- Rating band for a 0-100 pick score.
function Fit:RatingFor(score, conflict)
  local H = ns.Dungeons.HEURISTICS
  if conflict then return Fit.RATINGS.poor end
  if score >= H.FIT_GREAT then return Fit.RATINGS.great end
  if score >= H.FIT_GOOD then return Fit.RATINGS.good end
  if score >= H.FIT_FAIR then return Fit.RATINGS.fair end
  return Fit.RATINGS.poor
end

-- 0-1 position of `gain` between the weakest and best pick; nil when there's no real
-- difference between picks (spread under FIT_FLAT_SPREAD penalty points).
function Fit.Relative(gain, best, worst)
  local spread = (ns.Dungeons.HEURISTICS.FIT_FLAT_SPREAD or 5)
  if best - worst < spread then return nil end
  return math.min(1, math.max(0, gain - worst) / (best - worst))
end

---------------------------------------------------------------------------
-- "Group after:" - is the group OK once this person joins? Plain status from the same
-- Needs model (Analysis:Readiness), never a score.
-- Returns { status = "ready"|"thin"|"missing", missing = {labels}, thin = {labels},
--           slots = open slots left, text = full line, brief = thin count only,
--           short = compact form for narrow rows }
---------------------------------------------------------------------------
local function SlotsText(n)
  if not n or n <= 0 then return "" end
  return ", " .. n .. " slot" .. (n == 1 and "" or "s") .. " open"
end

function Fit:GroupAfter(r, settings, slots)
  Init()
  local ready = A:Readiness(r, settings)
  local miss, thin = {}, {}
  for _, row in ipairs(ready.risks or {}) do
    local label = row.label .. (row.unconfirmed and " (unconfirmed)" or "")
    if row.status == "missing" then miss[#miss + 1] = label
    elseif row.status == "thin" then thin[#thin + 1] = label end
  end
  local out = { missing = miss, thin = thin, slots = slots or 0 }
  out.status = (#miss > 0 and "missing") or (#thin > 0 and "thin") or "ready"
  local full, brief = {}, {}
  if #miss > 0 then
    local p = #miss .. " missing (" .. table.concat(miss, ", ") .. ")"
    full[#full + 1] = p; brief[#brief + 1] = p
  end
  if #thin > 0 then
    full[#full + 1] = #thin .. " thin (" .. table.concat(thin, ", ") .. ")"
    brief[#brief + 1] = #thin .. " thin"
  end
  if #full == 0 then full[1] = "Ready"; brief[1] = "Ready" end
  out.text = table.concat(full, ", ") .. SlotsText(slots)
  out.brief = table.concat(brief, ", ") .. SlotsText(slots)
  out.short = (#miss > 0 and (#miss .. " missing")) or (#thin > 0 and (#thin .. " thin")) or "Ready"
  return out
end
Fit.GROUP_AFTER_COLOR = { ready = "|cff54d978", thin = "|cfff5b84a", missing = "|cffee6161" }
Fit.GROUP_AFTER_ICON = {
  ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
  thin = "Interface\\RaidFrame\\ReadyCheck-Waiting",
  missing = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}

local function ValidRole(r)
  return (r == "TANK" or r == "HEALER" or r == "DAMAGER") and r or nil
end

local function MemberRole(m)
  local p = m.specID and UD:GetSpec(m.specID)
  return (p and p.role) or ValidRole(m.role)
end

-- Open slots per role for the current party. Members with no known role take a DPS slot
-- first (the most common case for a pending member), then whatever is left.
function Fit:OpenRoles(members)
  Init()
  local open = { TANK = 1, HEALER = 1, DAMAGER = 3 }
  local unknown = 0
  for _, m in ipairs(members) do
    local role = MemberRole(m)
    if role then open[role] = open[role] - 1 else unknown = unknown + 1 end
  end
  for _ = 1, unknown do
    if open.DAMAGER > 0 then open.DAMAGER = open.DAMAGER - 1
    elseif open.HEALER > 0 then open.HEALER = open.HEALER - 1
    elseif open.TANK > 0 then open.TANK = open.TANK - 1 end
  end
  for _, r in ipairs(ROLES) do if open[r] < 0 then open[r] = 0 end end
  return open
end

---------------------------------------------------------------------------
-- Keystone level for the key being run.
-- Only knowable in-client for the player's OWN keystone; used when it matches the dungeon.
-- confirmed present in 12.1.0 (build 69933) by /ens verify (keystone matched): C_MythicPlus.GetOwnedKeystoneChallengeMapID,
-- C_MythicPlus.GetOwnedKeystoneLevel, C_ChallengeMode.GetMapUIInfo(mapID) -> name.
---------------------------------------------------------------------------
function Fit:GetKeyLevel(dungeonKey)
  Init()
  if ns.state.keyLevelOverride then return ns.state.keyLevelOverride, "manual" end
  if not dungeonKey then return nil end
  local key, level = ns:OwnKeystoneDungeon()
  if key == dungeonKey and level then return level, "your keystone" end
  return nil
end

---------------------------------------------------------------------------
-- Context: everything that only depends on the current party, computed once per refresh.
---------------------------------------------------------------------------
local function Concat(a, b)
  local out = {}
  for _, x in ipairs(a) do out[#out + 1] = x end
  for _, x in ipairs(b) do out[#out + 1] = x end
  return out
end

function Fit:BuildContext(members, dungeonKey, settings, keyLevel)
  Init()
  settings = settings or ns.db.settings
  local ctx = { members = members, dungeonKey = dungeonKey, settings = settings, keyLevel = keyLevel }
  ctx.base = A:Analyze(members, dungeonKey, settings)
  ctx.basePenalty = A:Penalty(ctx.base, keyLevel)
  ctx.baseCritical = Fit.CriticalGaps(ctx.base)
  ctx.open = self:OpenRoles(members)
  -- Reserved slots (1.5.0) count as members; an applicant whose role has no open slot because
  -- of one rates Poor, with that as the reason.
  ctx.reservedRoles = {}
  for _, m in ipairs(members) do
    if m.reserved then
      local p = m.specID and UD:GetSpec(m.specID)
      local r = (p and p.role) or m.role
      if r then ctx.reservedRoles[r] = (ctx.reservedRoles[r] or 0) + 1 end
    end
  end
  ctx.bestGain, ctx.bestSpec, ctx.critFloor, ctx.critPartialFloor = {}, {}, {}, {}
  for _, role in ipairs(ROLES) do
    local best, bestSpec, worst = 0, nil, nil
    local gains = {}
    for _, specID in ipairs(UD:SpecsForRole(role)) do
      local r = A:Analyze(Concat(members, { { specID = specID } }), dungeonKey, settings)
      local g = ctx.basePenalty - A:Penalty(r, keyLevel)
      local cc = Fit.CriticalClose(ctx.baseCritical, r)
      gains[#gains + 1] = { specID = specID, gain = g, kind = cc and cc.kind or nil }
      if g > best then best, bestSpec = g, specID end
      if not worst or g < worst then worst = g end
    end
    ctx.bestGain[role], ctx.bestSpec[role] = best, bestSpec
    ctx.worstGain = ctx.worstGain or {}
    ctx.worstGain[role] = math.min(worst or 0, best)
    -- Critical-gap floors (positions 0-1): a full closer rates at least as high as the best
    -- spec of the role that doesn't fully close one; a partial closer at least the partial share.
    ctx.critFloor[role], ctx.critPartialFloor[role] = Fit.CritFloors(gains, best, ctx.worstGain[role])
    -- Candidate pool for "fill the remaining slots" lookahead: the most useful specs only,
    -- which keeps the greedy search to a few dozen analyses per applicant.
    table.sort(gains, function(x, y) if x.gain ~= y.gain then return x.gain > y.gain end return x.specID < y.specID end)
    ctx.pool = ctx.pool or {}
    ctx.pool[role] = {}
    for i = 1, math.min(LOOKAHEAD_POOL, #gains) do ctx.pool[role][i] = gains[i].specID end
  end
  ctx.idealPenalty, ctx.idealFill = self:GreedyFill(ctx, members, ctx.open)
  -- Class -> existing member label, for overlap notes.
  ctx.classes = {}
  for _, m in ipairs(ctx.base.members) do
    ctx.classes[m.classFile] = ctx.classes[m.classFile] or m.label
  end
  return ctx
end

-- Greedily fill `open` role slots with the spec that lowers the penalty most at each step.
-- Returns the final penalty and the list of picked spec IDs.
function Fit:GreedyFill(ctx, members, open, memoKey)
  if memoKey and ctx.greedyMemo and ctx.greedyMemo[memoKey] then
    local m = ctx.greedyMemo[memoKey]
    return m[1], m[2]
  end
  local cur = Concat(members, {})
  local left = {}
  for r, n in pairs(open) do left[r] = n end
  local picks = {}
  local penalty = A:Penalty(A:Analyze(cur, ctx.dungeonKey, ctx.settings), ctx.keyLevel)
  while true do
    local bestP, bestSpec, bestRole
    for _, role in ipairs(ROLES) do
      if (left[role] or 0) > 0 then
        for _, specID in ipairs(ctx.pool[role] or {}) do
          cur[#cur + 1] = { specID = specID }
          local p = A:Penalty(A:Analyze(cur, ctx.dungeonKey, ctx.settings), ctx.keyLevel)
          cur[#cur] = nil
          if not bestP or p < bestP then bestP, bestSpec, bestRole = p, specID, role end
        end
      end
    end
    if not bestSpec then break end
    cur[#cur + 1] = { specID = bestSpec }
    picks[#picks + 1] = bestSpec
    left[bestRole] = left[bestRole] - 1
    penalty = bestP
  end
  if memoKey then
    ctx.greedyMemo = ctx.greedyMemo or {}
    ctx.greedyMemo[memoKey] = { penalty, picks }
  end
  return penalty, picks
end

---------------------------------------------------------------------------
-- Helpers for the explanation text
---------------------------------------------------------------------------
local function ProfileFor(a)
  local p = a.specID and UD:GetSpec(a.specID)
  if p then return p, false end
  if a.classFile then return UD:ClassCommonProfile(a.classFile), true end
  return nil, true
end

-- "What they bring": one line per capability, buffs first.
local function BringsLines(profile, settings)
  local lines = {}
  if not profile then return lines end
  for _, bkey in ipairs(profile.buffs) do
    for _, b in ipairs(UD.BUFFS) do
      if b.key == bkey then lines[#lines + 1] = { cap = "buff", text = "Raid buff: " .. ns.Links:Buff(b.key) } end
    end
  end
  for _, key in ipairs(KEY_CAPS) do
    local src = UD:Sources(profile, key, settings)
    if src and #src > 0 then
      local names = {}
      for _, e in ipairs(src) do
        local tag = e.talent and " (talent)" or e.pet and " (pet)" or e.long and " (long CD)"
          or e.conditional and (" (" .. e.conditional .. ")") or e.verify and " (unconfirmed)" or ""
        names[#names + 1] = ns.Links:Ability(e.name, key) .. tag
      end
      -- An ability named like its need ("Bloodlust / Heroism") isn't preceded by the same words.
      local label = UD:CapLabel(key)
      local text = (#src == 1 and src[1].name == label) and names[1] or (label .. ": " .. table.concat(names, ", "))
      lines[#lines + 1] = { cap = key, text = text }
    end
  end
  return lines
end

local function ProviderLabels(providers, skipApplicant)
  local out = {}
  for _, p in ipairs(providers or {}) do
    if not (skipApplicant and p.member.applicant) then out[#out + 1] = p.member.label end
  end
  return out
end

local function ApplicantProvides(providers)
  for _, p in ipairs(providers or {}) do if p.member.applicant then return true end end
  return false
end

local function ShortSource(src)
  if not src then return "" end
  return (src:gsub("%s*%(.-%)", ""))
end

---------------------------------------------------------------------------
-- Experience: how ready an application looks for THIS key, from Blizzard's per-dungeon data
-- (best run of the listed dungeon this season). Returns nil when it can't be judged (no key
-- level, or the client gave no per-dungeon data for anyone), else
-- { points = 0-100, weight = 0-1, text = short phrase, verdict = "proven"|"close"|"stretch"|"new" }.
---------------------------------------------------------------------------
function Fit:ExperienceWeight(level)
  local H = DD.HEURISTICS
  if not level then return 0 end
  if level <= 5 then return H.EXPERIENCE_WEIGHT_LOW or 0.10 end
  if level <= 9 then return H.EXPERIENCE_WEIGHT_MID or 0.20 end
  return H.EXPERIENCE_WEIGHT_HIGH or 0.30
end

local function MemberExperience(best, level)
  local lvl = best.level or 0
  if lvl <= 0 then return 30, "new", "no run of this dungeon yet" end
  if best.timed then
    if lvl >= level then return 100, "proven", string.format("timed +%d here", lvl) end
    if lvl >= level - 2 then return 80, "close", string.format("timed +%d here", lvl) end
    return math.max(25, 80 - 15 * (level - 2 - lvl)), "stretch", string.format("best timed here +%d", lvl)
  end
  if lvl >= level then return 60, "close", string.format("+%d here, over time", lvl) end
  return math.max(20, 50 - 10 * (level - lvl)), "stretch", string.format("best here +%d, over time", lvl)
end

function Fit:Experience(members, level)
  Init()
  if not level then return nil end
  local sum, n, worst = 0, 0, nil
  local texts = {}
  for _, m in ipairs(members or {}) do
    if m.bestHere then
      local pts, verdict, text = MemberExperience(m.bestHere, level)
      sum, n = sum + pts, n + 1
      texts[#texts + 1] = (#members > 1 and (tostring(m.name) .. ": ") or "") .. text
      if not worst or pts < worst.points then worst = { points = pts, verdict = verdict } end
    end
  end
  if n == 0 then return nil end
  return { points = math.floor(sum / n + 0.5), weight = self:ExperienceWeight(level), verdict = worst.verdict,
           text = table.concat(texts, "; ") }
end

---------------------------------------------------------------------------
-- Evaluate one application (one player or a premade group applying together).
-- group = { applicantID, members = { { name, classFile, specID?, role? , score?, itemLevel? } } }
---------------------------------------------------------------------------
function Fit:Evaluate(ctx, group)
  Init()
  local H = DD.HEURISTICS
  local ev = {
    applicantID = group.applicantID, members = group.members,
    brings = {}, complements = {}, overlaps = {}, dungeonFixes = {}, dungeonStill = {}, notes = {},
  }

  -- Build analysis members for the applicant(s) + role fit.
  local adds, open, conflicts, roles, pendingAny = {}, {}, {}, {}, false
  for r, n in pairs(ctx.open) do open[r] = n end
  for _, a in ipairs(group.members) do
    local profile, pending = ProfileFor(a)
    if pending then pendingAny = true end
    local role = (profile and profile.role) or ValidRole(a.role) or "DAMAGER"
    roles[#roles + 1] = role
    if open[role] and open[role] > 0 then open[role] = open[role] - 1
    else conflicts[#conflicts + 1] = role end
    adds[#adds + 1] = { specID = a.specID, classFile = a.classFile, label = a.name, role = role, applicant = true }
    for _, line in ipairs(BringsLines(profile, ctx.settings)) do
      ev.brings[#ev.brings + 1] = (#group.members > 1 and (tostring(a.name) .. " - ") or "") .. line.text
    end
  end
  ev.roles, ev.pending, ev.roleConflict = roles, pendingAny, #conflicts > 0

  local after = A:Analyze(Concat(ctx.members, adds), ctx.dungeonKey, ctx.settings)
  ev.after = after
  local gain = ctx.basePenalty - A:Penalty(after, ctx.keyLevel)
  local best, worst = 0, 0
  for _, r in ipairs(roles) do
    best = best + (ctx.bestGain[r] or 0)
    worst = worst + (ctx.worstGain[r] or 0)
  end
  ev.gain, ev.best, ev.worst = gain, best, worst
  -- Itemized: which gaps this applicant closes or opens, and synergy (same numbers as gain).
  ev.breakdown = A:ScoreDelta(ctx.base, after, ctx.keyLevel)

  -- Pick rating: position between the weakest and the strongest spec this role could bring
  -- (0 = no better than the least useful pick, 100 = as good as the ideal pick).
  local rel = Fit.Relative(gain, best, worst)
  ev.flat = (rel == nil) and not ev.roleConflict
  ev.rawImmediate = rel and math.floor(rel * 100 + 0.5) or nil   -- the pick position itself
  -- Critical gaps: full or partial close, and the floor that goes with it (one-player
  -- applications; premades get the cross-applicant step in EvaluateAll).
  ev.critClose = Fit.CriticalClose(ctx.baseCritical, after)
  ev.closesCritical = ev.critClose ~= nil
  ev.closesCriticalFull = ev.critClose ~= nil and ev.critClose.kind == "full"
  if rel and ev.critClose and #roles == 1 and not ev.roleConflict then
    local floorRel = ev.critClose.kind == "full" and ctx.critFloor[roles[1]] or ctx.critPartialFloor[roles[1]]
    if floorRel then ev.critFloor = math.floor(floorRel * 100 + 0.5) end
  end
  -- Utility pick after the critical-gap floor (no experience): drives the headline and coaching.
  ev.immediate = ev.rawImmediate and math.max(ev.rawImmediate, ev.critFloor or 0) or nil

  -- Look-ahead (not part of the score): with other slots still open, the best way to fill
  -- them after inviting, and what the rest of the group would still have to bring.
  local anyRemaining, slotsLeft = false, 0
  for _, n in pairs(open) do if n > 0 then anyRemaining = true; slotsLeft = slotsLeft + n end end
  if anyRemaining and not ev.roleConflict then
    -- Memo key: applicants with the same specs (a common case) share the lookahead.
    local sig = {}
    for _, a in ipairs(adds) do sig[#sig + 1] = tostring(a.specID or a.classFile) end
    table.sort(sig)
    local memo = table.concat(sig, ",") .. "|" .. (open.TANK or 0) .. (open.HEALER or 0) .. (open.DAMAGER or 0)
    local _, fill = self:GreedyFill(ctx, Concat(ctx.members, adds), open, memo)
    if fill[1] then
      local names = {}
      for _, sid in ipairs(fill) do names[#names + 1] = UD:SpecName(sid) .. " " .. UD:ClassName(UD:GetSpec(sid).class) end
      ev.bestPartners = names
    end
    local need
    if after.dungeon and after.dungeon.gaps then
      for _, it in ipairs(after.dungeon.gaps) do
        if it.status == "missing" and not it.unconfirmed then need = UD:CapLabel(it.req.need); break end
      end
    end
    if not need then
      for _, f in ipairs(after.findings) do
        if f.severity == "critical" or f.severity == "high" then need = f.short; break end
      end
    end
    ev.dependsOn = need
  end
  -- "Group after:" - plain status of the group once they join.
  ev.groupAfter = self:GroupAfter(after, ctx.settings, ev.roleConflict and 0 or slotsLeft)

  local score = ev.flat and (H.FIT_FLAT_SCORE or 70) or (ev.rawImmediate or 0)
  ev.fitScore = score   -- utility fit alone (the pick position, before the critical-gap rule)
  -- Experience in this dungeon at this key level (Blizzard's per-dungeon data). With no real
  -- difference between picks the rating stays the same for everyone and experience decides
  -- (shown on the card, used to order the list).
  ev.experience = self:Experience(group.members, ctx.keyLevel)
  if ev.experience and not ev.roleConflict and not ev.flat then
    local w = ev.experience.weight
    score = math.floor((1 - w) * score + w * ev.experience.points + 0.5)
  end
  ev.blended = score    -- after the experience mix, before the critical-gap rule
  -- Past keys together (1.5.0, opt-in): the same points Fill group uses at this key's
  -- strictness, before the critical-gap floor, so a full closer still never rates below anyone
  -- who doesn't fully close a critical need.
  ev.past = Fit.PastAdjust(group.members, ctx)
  if ev.past and not ev.roleConflict and ev.past.points ~= 0 then
    score = math.max(0, math.min(100, score + ev.past.points))
  end
  ev.pastScore = score
  if ev.critFloor and score < ev.critFloor then
    score = ev.critFloor
    ev.critFloored = ev.critClose.kind   -- "full" or "partial"
  end
  if ev.roleConflict then score = math.min(score, 15) end
  ev.baseScore = score  -- before the cross-applicant lift (EvaluateAll resets to this)
  ev.score = score
  ev.rating = self:RatingFor(score, ev.roleConflict)

  -- Complements: what changes for the group's existing classes.
  local base = ctx.base
  -- Raid buff synergy: buffs they bring that suit your damage profile, and your existing
  -- buffs that suit theirs.
  for _, d in ipairs(A:SynergyDelta(base, after)) do
    ev.complements[#ev.complements + 1] = { weight = d.gain >= 1.5 and 3 or 2, synergy = true, text = d.long }
  end
  for _, b in ipairs(base.buffs.present) do
    if not b.universal then
      local info = UD.BUFF_INFO[b.key]
      for _, a in ipairs(group.members) do
        local f = UD:BuffBenefit(info, (ProfileFor(a)))
        if f and f >= 1 then
          ev.complements[#ev.complements + 1] = { weight = 1, synergy = true,
            text = "Benefits from your " .. ns.Links:Buff(b.key) .. " (" .. b.from .. ")" }
        end
      end
    end
  end
  for _, b in ipairs(after.buffs.present) do
    local had = false
    for _, x in ipairs(base.buffs.present) do if x.key == b.key then had = true end end
    if not had and b.universal then
      ev.complements[#ev.complements + 1] = { weight = 1, text = "Adds " .. ns.Links:Buff(b.key) .. " (" .. b.effect .. ", everyone)" }
    elseif not had and b.strength == "none" then
      ev.overlaps[#ev.overlaps + 1] = ns.Links:Buff(b.key) .. " does little here: no " .. (b.who or "beneficiaries") .. " in the group"
    end
  end
  for _, key in ipairs(KEY_CAPS) do
    local before, now = base.caps[key] or {}, after.caps[key] or {}
    if ApplicantProvides(now) then
      local label = UD:CapLabel(key)
      if #before == 0 then
        ev.complements[#ev.complements + 1] = { weight = 5, cap = key,
          text = "Adds " .. label .. " - your group has none" }
      elseif #before == 1 and BACKUP_CAPS[key] then
        ev.complements[#ev.complements + 1] = { weight = 2, cap = key,
          text = "Second " .. label .. ", backing up " .. ProviderLabels(before)[1] }
      elseif SINGLETON_CAPS[key] then
        ev.overlaps[#ev.overlaps + 1] = label .. " already covered by " .. table.concat(ProviderLabels(before), ", ")
      end
    end
  end
  -- Interrupt rotation depth and range balance.
  local bi, ai = base.interrupts, after.interrupts
  if ai.short > bi.short then
    local txt = string.format("Rotational interrupts %d -> %d", bi.short, ai.short)
    local addedRanged = (ai.byRange.ranged or 0) > (bi.byRange.ranged or 0)
    local addedMelee = (ai.byRange.melee or 0) > (bi.byRange.melee or 0)
    if bi.count > 0 and addedRanged and (bi.byRange.ranged or 0) == 0 then
      txt = txt .. "; a ranged kick balances your melee-only interrupts"
    elseif bi.count > 0 and addedMelee and (bi.byRange.melee or 0) == 0 then
      txt = txt .. "; adds a melee kick next to your ranged ones"
    end
    ev.complements[#ev.complements + 1] = { weight = bi.short <= 1 and 4 or 1, text = txt }
  end
  -- New crowd-control types.
  local newCC = {}
  for _, t in ipairs(UD.CC_TYPES) do
    if (after.cc.types[t] or 0) > 0 and (base.cc.types[t] or 0) == 0 then newCC[#newCC + 1] = t end
  end
  if #newCC > 0 then
    ev.complements[#ev.complements + 1] = { weight = 1, text = "New CC types: " .. table.concat(newCC, ", ") }
  end
  table.sort(ev.complements, function(x, y)
    if x.weight ~= y.weight then return x.weight > y.weight end
    return x.text < y.text
  end)
  if #ev.complements == 0 and #base.members > 0 then
    ev.complements[#ev.complements + 1] = { weight = 0, text = "Adds nothing your group doesn't already have" }
  end

  -- Overlaps: classes already present (duplicate class = no new raid buff).
  for _, a in ipairs(group.members) do
    local profile = ProfileFor(a)
    local cls = profile and profile.class or a.classFile
    if cls and ctx.classes[cls] then
      local buffNames = {}
      for _, bkey in ipairs(profile and profile.buffs or {}) do
        for _, b in ipairs(UD.BUFFS) do if b.key == bkey then buffNames[#buffNames + 1] = ns.Links:Buff(b.key) end end
      end
      ev.overlaps[#ev.overlaps + 1] = "Same class as " .. ctx.classes[cls] ..
        (#buffNames > 0 and (" - " .. table.concat(buffNames, ", ") .. " already present") or "")
    end
  end

  -- Dungeon / key fit.
  local bd, ad = base.dungeon, after.dungeon
  if ad and not ad.unknown and bd then
    local before = {}
    for _, it in ipairs(bd.items) do before[it.req.id] = it.status end
    local helps = 0
    for _, it in ipairs(ad.items) do
      local was = before[it.req.id]
      local theirs = ApplicantProvides(it.providers)
      if theirs then helps = helps + 1 end
      if was and was ~= it.status and theirs then
        local sevRank = DD.SEVERITY_RANK[it.req.severity] or 4
        local verb = (was == "missing") and "Covers " or "Shores up "
        ev.dungeonFixes[#ev.dungeonFixes + 1] = {
          rank = (was == "missing" and 0 or 10) + sevRank, severity = it.req.severity, id = it.req.id,
          unconfirmed = it.unconfirmed, cap = it.req.need,
          text = verb .. UD:CapLabel(it.req.need) .. " for " .. A.Decorate(ShortSource(it.req.source), it.req.need, it.req.dungeon)
            .. (it.unconfirmed and " [unconfirmed]" or ""),
        }
      elseif it.aggregate and was and was ~= it.status then
        ev.dungeonFixes[#ev.dungeonFixes + 1] = { rank = 5, severity = "high",
          text = "Brings the kick rotation up to what " .. ad.name .. " wants" }
      end
    end
    table.sort(ev.dungeonFixes, function(x, y) return x.rank < y.rank end)
    for _, it in ipairs(ad.gaps) do
      ev.dungeonStillItems = ev.dungeonStillItems or {}
      ev.dungeonStillItems[#ev.dungeonStillItems + 1] = it
      ev.dungeonStill[#ev.dungeonStill + 1] = (it.status == "missing" and "Still missing " or "Still thin ")
        .. UD:CapLabel(it.req.need) .. " (" .. A.Decorate(ShortSource(it.req.source), it.req.need, it.req.dungeon) .. ")"
    end
    ev.dungeonHelps = helps
    ev.dungeonName = ad.name
    if ad.incomplete then ev.notes[#ev.notes + 1] = ad.name .. " data is unconfirmed; treat key fit as an estimate." end
  end

  if pendingAny then
    ev.notes[#ev.notes + 1] = "Spec not shared by the Group Finder: rated on utility every spec of the class has."
  end
  -- Low keys: coach the host toward giving a newer player the run when they fit.
  local lowKey = ctx.keyLevel and ctx.keyLevel <= (H.LOW_KEY_LEVEL or 9)
  local utility = ev.flat and ev.fitScore or ev.immediate or 0
  if lowKey and not ev.roleConflict and ev.experience and ev.experience.points < 70 and utility >= H.FIT_GOOD then
    ev.coaching = string.format("Less experienced here, but a strong fit: +%d is a good key to give them the run.", ctx.keyLevel)
    ev.notes[#ev.notes + 1] = ev.coaching
  end
  if ev.flat then
    ev.notes[#ev.notes + 1] = "No real difference between picks for this slot: decide on experience" ..
      (ev.experience and (" (" .. ev.experience.text .. ")") or "") .. "."
  elseif ev.experience then
    ev.notes[#ev.notes + 1] = string.format("Experience counts %d%% of the rating at +%d (utility %d, experience %d).",
      math.floor(ev.experience.weight * 100 + 0.5), ctx.keyLevel, ev.fitScore, ev.experience.points)
  end
  if ctx.keyLevel and H.HIGH_KEY_LEVEL and ctx.keyLevel >= H.HIGH_KEY_LEVEL then
    ev.notes[#ev.notes + 1] = string.format("+%d key: thin coverage weighs as much as missing coverage.", ctx.keyLevel)
  end
  if ev.bestPartners then
    ev.notes[#ev.notes + 1] = "Best way to fill the rest after inviting: " .. table.concat(ev.bestPartners, ", ")
  end
  if ctx.bestSpec[roles[1]] and score < H.FIT_GREAT and not ev.roleConflict and not ev.flat then
    local bs = ctx.bestSpec[roles[1]]
    ev.idealPick = UD:SpecName(bs) .. " " .. UD:ClassName(UD:GetSpec(bs).class)
  end

  -- Headline: the single most useful reason, in priority order.
  if ev.roleConflict then
    local r = conflicts[1]
    local held = ctx.reservedRoles and ctx.reservedRoles[r] or 0
    local mine
    for _, a in ipairs(group.members) do
      for _, m in ipairs(ctx.members) do
        if m.reserved and m.full and a.full and m.full:lower() == a.full:lower() then mine = a end
      end
    end
    if mine then
      ev.reservedFriend = true   -- Hide Poor keeps this card (1.5.0 review, R6)
      ev.headline = "Your reserved slot is for " .. tostring(mine.name) .. ": invite them yourself"
    elseif held > 0 then
      ev.headline = "No open " .. ROLE_NAME[r] .. " slot - the last " .. (held > 1 and (held .. " ") or "")
        .. ROLE_NAME[r] .. (held > 1 and " slots are" or " slot is") .. " reserved"
    else
      ev.headline = "No open " .. ROLE_NAME[r] .. " slot - you already have " ..
        (SLOTS_PER_ROLE[r] == 1 and ("a " .. ROLE_NAME[r]:lower()) or (SLOTS_PER_ROLE[r] .. " " .. ROLE_NAME[r]))
    end
  else
    -- Closes the group's last open dungeon requirement(s): the clearest reason to invite.
    local needs, needList, afterMissing = {}, {}, 0
    for _, it in ipairs((base.dungeon and base.dungeon.gaps) or {}) do
      if it.status == "missing" and not it.unconfirmed and not it.aggregate and not needs[it.req.need] then
        needs[it.req.need] = true
        needList[#needList + 1] = UD:CapLabel(it.req.need)
      end
    end
    for _, it in ipairs((ev.after.dungeon and ev.after.dungeon.gaps) or {}) do
      if it.status == "missing" and not it.unconfirmed then afterMissing = afterMissing + 1 end
    end
    local firstFix = ev.dungeonFixes[1]
    if #needList > 0 and afterMissing == 0 and firstFix and firstFix.text:find("^Covers ") then
      ev.onlyGap = true
      ev.headline = #needList == 1 and ("Fills your only gap: " .. firstFix.text:gsub("^Covers ", ""))
        or ("Fills all your gaps: " .. table.concat(needList, ", "))
    end
    local strongFix
    for _, f in ipairs(ev.dungeonFixes) do
      if not f.unconfirmed and (f.severity == "critical" or f.severity == "high") then strongFix = f; break end
    end
    if ev.headline then
      -- set above (fills the last gap)
    elseif strongFix then
      ev.headline = strongFix.text
    elseif ev.dependsOn and (ev.immediate or 0) < DD.HEURISTICS.FIT_GOOD and ev.bestPartners then
      ev.headline = "OK if the last slot brings " .. ev.dependsOn .. " (e.g. " .. ev.bestPartners[1] .. ")"
    end
  end
  if not ev.headline then
    if ev.complements[1] and ev.complements[1].weight >= 3 then
      ev.headline = ev.complements[1].text
    elseif ev.dungeonFixes[1] then
      ev.headline = ev.dungeonFixes[1].text
    elseif ev.complements[1] and ev.complements[1].weight > 0 then
      ev.headline = ev.complements[1].text
    else
      ev.headline = "Fills the slot but adds little new utility"
    end
  end
  return ev
end

---------------------------------------------------------------------------
-- Past keys together in the pick rating (1.5.0, F2; off unless "Show past keys in pick
-- ratings" is on). Per player: + the level's points for one you've timed with, - for one
-- you've failed with (History:Standing). Returns nil when off or nobody has a shared key.
---------------------------------------------------------------------------
function Fit.PastAdjust(members, ctx)
  local settings = ctx and ctx.settings or ns.db.settings
  local pk = settings.pastKeys or {}
  if not pk.rating or not ns.History then return nil end
  local level = ns.FillGroup and ns.FillGroup:Level(settings, ctx and ctx.keyLevel) or "standard"
  local w = ns.History:PastPoints(level)
  local out = { points = 0, timed = 0, failed = 0, level = level, w = w, parts = {} }
  for _, m in ipairs(members or {}) do
    local st, c = ns.History:Standing(m.full, settings)
    if st == "timed" then out.timed = out.timed + 1; out.points = out.points + w
    elseif st == "failed" then out.failed = out.failed + 1; out.points = out.points - w end
    if c and st then out.parts[#out.parts + 1] = ((#members > 1) and (tostring(m.name) .. ": ") or "") .. ns.History:WithText(c) end
  end
  if out.timed == 0 and out.failed == 0 then return nil end
  out.rank = (out.timed > out.failed) and 1 or ((out.failed > out.timed) and -1 or 0)
  return out
end

-- Part of ForLiveGroup's context signature: past keys change the rating only when it's on.
function Fit.PastSig(settings)
  local pk = settings.pastKeys or {}
  if not pk.rating or not ns.History then return "off" end
  local runs = ns.db.history or {}
  return table.concat({ "on", tostring(pk.failed), tostring((settings.fill or {}).level), tostring(#runs),
    tostring(runs[1] and runs[1].started), tostring(runs[1] and runs[1].result) }, ":")
end

---------------------------------------------------------------------------
-- "Why N?": the score's steps in the order they're applied, each with the value it ends on,
-- so every number on the card adds up. Returns { { text, value = number|nil } }; the last
-- step with a value equals ev.score. (The gap lines and their total come from ev.breakdown.)
---------------------------------------------------------------------------
local function CloseText(cc, onlyFull)
  local parts = {}
  for _, c in ipairs(cc.closes) do
    if not onlyFull or c.full then parts[#parts + 1] = c.label .. (c.how and (": " .. c.how) or "") end
    if #parts == 2 then break end
  end
  return table.concat(parts, "; ")
end

function Fit:ScoreSteps(ctx, ev)
  Init()
  local H = DD.HEURISTICS
  local steps = {}
  local n = #(ev.roles or {})
  local who = n > 1 and ("picks for these " .. n .. " slots") or ((ROLE_NAME[ev.roles and ev.roles[1]] or "player") .. " for this slot")
  if ev.flat then
    local role = ROLE_NAME[ev.roles and ev.roles[1]] or "pick"
    steps[#steps + 1] = { value = ev.fitScore, text = string.format(
      "The best and weakest %s are under %d points apart: no real difference, so every %s gets %d. Decide on experience.",
      who, H.FIT_FLAT_SPREAD or 5, role, ev.fitScore) }
  else
    steps[#steps + 1] = { value = ev.fitScore, text = string.format(
      "The best %s would close %.1f points and the weakest %.1f; this one closes %.1f, so %d/100 as a pick.",
      who, ev.best or 0, ev.worst or 0, ev.gain or 0, ev.fitScore or 0) }
  end
  if ev.experience and not ev.flat and not ev.roleConflict then
    local w = ev.experience.weight
    local pw = math.floor(w * 100 + 0.5)
    steps[#steps + 1] = { value = ev.blended, text = string.format(
      "Experience counts %d%%%s: %d%% of utility %d + %d%% of experience %d = %d.",
      pw, ctx and ctx.keyLevel and (" at +" .. ctx.keyLevel) or "", 100 - pw, ev.fitScore, pw, ev.experience.points, ev.blended) }
  end
  local past = ev.past
  if past and not ev.roleConflict then
    local lvl = ns.FillGroup and ns.FillGroup.LEVEL_LABEL[past.level] or past.level
    local text = "Past keys with you (" .. table.concat(past.parts, "; ") .. "): "
    if past.w == 0 then
      text = text .. "at " .. tostring(lvl) .. " past keys only break ties, so no points."
    else
      local bits = {}
      if past.timed > 0 then bits[#bits + 1] = "+" .. past.w .. " per player you've timed with" end
      if past.failed > 0 then bits[#bits + 1] = "-" .. past.w .. " per player you've failed with" end
      -- Say so when the 0-100 clamp changed the result ("+5, capped at 100", not "+5 = 100" from
      -- 98; 1.5.0 review, N6).
      local capped = (ev.blended or 0) + past.points ~= ev.pastScore
      text = text .. table.concat(bits, ", ") .. " at " .. tostring(lvl)
        .. (capped and string.format(": %+d, capped at %d.", past.points, ev.pastScore)
          or string.format(": %+d = %d.", past.points, ev.pastScore))
    end
    steps[#steps + 1] = { value = past.w ~= 0 and ev.pastScore or nil, text = text }
  end
  local cc = ev.critClose
  if cc and not ev.roleConflict then
    local share = math.floor((H.FIT_CRIT_PARTIAL_SHARE or 0.5) * 100 + 0.5)
    if ev.critFloored == "full" then
      steps[#steps + 1] = { value = ev.critFloor, text = string.format(
        "Raised to %d: they close a critical gap (%s), so they rate at least as high as the best %s that doesn't fully close one.",
        ev.critFloor, CloseText(cc, true), who) }
    elseif ev.critFloored == "partial" then
      steps[#steps + 1] = { value = ev.critFloor, text = string.format(
        "Raised to %d: they only partly close a critical gap (%s). A partial close counts for %d%% of the way from the weakest pick to the best one that closes nothing.",
        ev.critFloor, CloseText(cc), share) }
    elseif cc.kind == "full" then
      steps[#steps + 1] = { text = "They close a critical gap (" .. CloseText(cc, true) .. ")" ..
        (ev.critFloor and string.format(", which keeps them at %d or more; they're already there.", ev.critFloor) or ".") }
    else
      steps[#steps + 1] = { text = "They only partly close a critical gap (" .. CloseText(cc) .. "), which counts for less than a full close" ..
        (ev.critFloor and string.format(": at least %d; they're already there.", ev.critFloor) or ".") }
    end
  end
  if ev.critLifted then
    steps[#steps + 1] = { value = ev.score, text = string.format(
      "Raised to %d: they fully close a critical gap, so no applicant who doesn't rates above them.", ev.score) }
  end
  if ev.roleConflict then
    steps[#steps + 1] = { value = ev.score, text = string.format("Their role has no open slot, so the score is capped at 15: %d.", ev.score) }
  end
  return steps
end

---------------------------------------------------------------------------
-- Side-by-side comparison of two applications against the same party.
---------------------------------------------------------------------------
local function Avg(members, field)
  local sum, n = 0, 0
  for _, m in ipairs(members) do
    local v = tonumber(m[field])
    if v and v > 0 then sum = sum + v; n = n + 1 end
  end
  return n > 0 and (sum / n) or nil
end
Fit.Avg = Avg

---------------------------------------------------------------------------
-- The tiebreak chain (1.5.1, approved by the author October 26, 2026): between applications
-- with the same rating (and past keys, when on), the higher of each step wins, in order:
--   1. best timed level in this dungeon, 2. this dungeon's score, 3. overall M+ rating,
--   4. item level; then the longest wait, then the applicant ID (a stable order).
-- Missing per-dungeon data counts as "no run here" (0), and a missing rating or item level as 0,
-- so the order is consistent (Lua's table.sort needs one). A premade uses the average of its
-- members that have the value. Used by Fill group (the per-role cut and the group order) and by
-- every Applicants sort, so the cards and the plan agree.
---------------------------------------------------------------------------
Fit.TIE_STEPS = {
  { key = "timed", label = "best timed here", fmt = function(v) return v > 0 and ("+" .. math.floor(v + 0.5)) or "none" end },
  { key = "map", label = "score in this dungeon", fmt = function(v) return tostring(math.floor(v + 0.5)) end },
  { key = "rating", label = "M+ rating", fmt = function(v) return tostring(math.floor(v + 0.5)) end },
  { key = "ilvl", label = "item level", fmt = function(v) return tostring(math.floor(v + 0.5)) end },
}

function Fit.TieKey(ev)
  local sums = { timed = { 0, 0 }, map = { 0, 0 }, rating = { 0, 0 }, ilvl = { 0, 0 } }
  local function add(k, v) sums[k][1] = sums[k][1] + v; sums[k][2] = sums[k][2] + 1 end
  for _, m in ipairs(ev.members or {}) do
    local b = m.bestHere
    if type(b) == "table" then
      add("timed", (b.timed and tonumber(b.level)) or 0)
      add("map", tonumber(b.score) or 0)
    end
    local r, i = tonumber(m.score), tonumber(m.itemLevel)
    if r and r > 0 then add("rating", r) end
    if i and i > 0 then add("ilvl", i) end
  end
  local key = {}
  for k, s in pairs(sums) do key[k] = s[2] > 0 and (s[1] / s[2]) or 0 end
  return key
end

-- -1 when x goes first, 1 when y does, 0 on a full tie; the second return is the step that
-- decided (an index into TIE_STEPS), nil on a tie.
function Fit.TieCompare(x, y)
  local a, b = Fit.TieKey(x), Fit.TieKey(y)
  for i, st in ipairs(Fit.TIE_STEPS) do
    local va, vb = a[st.key] or 0, b[st.key] or 0
    if math.abs(va - vb) > 1e-9 then return va > vb and -1 or 1, i end
  end
  return 0, nil
end

local function Wait(ev) return tonumber(ev.members and ev.members[1] and ev.members[1].firstSeen) or math.huge end
-- The full tail after the step a sort cares about: the chain, the longest wait, the ID.
function Fit.TieBefore(x, y)
  local c = Fit.TieCompare(x, y)
  if c ~= 0 then return c < 0 end
  local wx, wy = Wait(x), Wait(y)
  if wx ~= wy then return wx < wy end
  return tostring(x.applicantID) < tostring(y.applicantID)
end

-- Returns { stats = { {label, a, b, better = "a"|"b"|nil} }, onlyA, onlyB, both (utility lines),
--           fixA, fixB, fixBoth (dungeon fixes), verdict, winner = "a"|"b"|nil }
function Fit:Compare(ctx, a, b)
  Init()
  local out = { stats = {}, onlyA = {}, onlyB = {}, both = {}, fixA = {}, fixB = {}, fixBoth = {} }
  local function stat(label, va, vb, fmt, higherBetter)
    local better
    if va and vb and va ~= vb then better = ((va > vb) == (higherBetter ~= false)) and "a" or "b" end
    out.stats[#out.stats + 1] = { label = label, a = va and string.format(fmt, va) or "-", b = vb and string.format(fmt, vb) or "-", better = better }
  end
  stat("Fit", a.score, b.score, "%d")
  if a.experience or b.experience then
    stat("Utility", a.fitScore, b.fitScore, "%d")
    stat("Experience", a.experience and a.experience.points, b.experience and b.experience.points, "%d")
  end
  stat("M+ rating", Avg(a.members, "score"), Avg(b.members, "score"), "%d")
  stat("Item level", Avg(a.members, "itemLevel"), Avg(b.members, "itemLevel"), "%.0f")

  -- Utility: what each adds that the group lacks (or only has once, for backup-worthy caps).
  for _, key in ipairs(KEY_CAPS) do
    local before = ctx.base.caps[key] or {}
    local pa, pb = ApplicantProvides(a.after.caps[key]), ApplicantProvides(b.after.caps[key])
    local label
    if #before == 0 then label = UD:CapLabel(key)
    elseif #before == 1 and BACKUP_CAPS[key] then label = "second " .. UD:CapLabel(key) end
    if label and (pa or pb) then
      local list = (pa and pb) and out.both or (pa and out.onlyA) or out.onlyB
      list[#list + 1] = label
    end
  end
  -- Dungeon requirements each one closes.
  local fa, fb = {}, {}
  for _, f in ipairs(a.dungeonFixes) do if f.id then fa[f.id] = f end end
  for _, f in ipairs(b.dungeonFixes) do if f.id then fb[f.id] = f end end
  for id, f in pairs(fa) do
    if fb[id] then out.fixBoth[#out.fixBoth + 1] = f else out.fixA[#out.fixA + 1] = f end
  end
  for id, f in pairs(fb) do if not fa[id] then out.fixB[#out.fixB + 1] = f end end
  local function byRank(x, y) if x.rank ~= y.rank then return x.rank < y.rank end return x.text < y.text end
  table.sort(out.fixA, byRank); table.sort(out.fixB, byRank); table.sort(out.fixBoth, byRank)

  -- Verdict.
  local function reason(only, fixes)
    if fixes[1] then return fixes[1].text end
    if only[1] then return "brings " .. only[1] end
    return nil
  end
  if a.roleConflict ~= b.roleConflict then
    out.winner = a.roleConflict and "b" or "a"
    out.verdict = "only one of them fits an open slot"
  elseif math.abs(a.score - b.score) >= (DD.HEURISTICS.COMPARE_CLOSE or 10) then
    out.winner = a.score > b.score and "a" or "b"
    local r = out.winner == "a" and reason(out.onlyA, out.fixA) or reason(out.onlyB, out.fixB)
    out.verdict = string.format("better fit (%d vs %d)%s", math.max(a.score, b.score), math.min(a.score, b.score),
      r and (": " .. r) or "")
  else
    local ra, rb = Avg(a.members, "score"), Avg(b.members, "score")
    if ra and rb and math.abs(ra - rb) >= 100 then
      out.winner = ra > rb and "a" or "b"
      out.verdict = string.format("similar fit; higher M+ rating (%d vs %d)", math.max(ra, rb), math.min(ra, rb))
    else
      out.verdict = "close call: similar fit and rating - pick on what you know of the players"
    end
  end
  return out
end

-- Evaluate every application; sorted best first (role conflicts last, then M+ score).
function Fit:EvaluateAll(ctx, groups)
  local out = {}
  for _, g in ipairs(groups or {}) do out[#out + 1] = self:Evaluate(ctx, g) end
  return self:Rank(out)
end

-- The cheap cross-applicant step over evaluations (fresh or cached): the critical-gap lift,
-- then the sort. Safe to run again on the same evaluations: each starts from its baseScore.
function Fit:Rank(out)
  for _, ev in ipairs(out) do
    ev.score, ev.critLifted, ev.liftedTo = ev.baseScore or ev.score, nil, nil
    ev.rating = self:RatingFor(ev.score, ev.roleConflict)
  end
  -- Critical-gap rule across the actual applicants (covers premades, class-only applicants
  -- and experience): nobody who FULLY closes a critical gap rates below somebody who doesn't
  -- (partial closers included). Partial closers keep their own floor and are never lifted.
  local topOther = nil
  for _, ev in ipairs(out) do
    if not ev.roleConflict and not ev.closesCriticalFull and (not topOther or ev.score > topOther) then topOther = ev.score end
  end
  if topOther then
    for _, ev in ipairs(out) do
      if not ev.roleConflict and ev.closesCriticalFull and ev.score < topOther then
        ev.score, ev.critLifted = topOther, true
        ev.rating = self:RatingFor(ev.score)
      end
    end
  end
  local function Past(ev) return ev.past and ev.past.rank or 0 end
  table.sort(out, function(x, y)
    if x.roleConflict ~= y.roleConflict then return not x.roleConflict end
    if x.score ~= y.score then return x.score > y.score end
    if Past(x) ~= Past(y) then return Past(x) > Past(y) end   -- only with past keys in ratings on
    -- The tiebreak chain (1.5.1): best timed here, this dungeon's score, M+ rating, item level,
    -- then the longest wait. Experience points left the sort: they come from the same best run.
    return Fit.TieBefore(x, y)
  end)
  return out
end

-- Convenience for the UI: current party + applicants -> ctx, evals.
-- Two cache levels, so one application arriving or leaving costs about one evaluation:
--   * the context (party, dungeon, key level, affixes, settings), rebuilt only when one changes;
--   * each application's evaluation, keyed on that application's own signature (everything
--     Evaluate reads from it), kept while the context stays the same.
-- The cheap cross-applicant step (critical-gap lift, sort) runs on every change. The whole
-- answer is also kept on a signature that adds what the UI shows straight from the applicant
-- rows (status, rating, item level, wait time), so the Composition tab, the Applicants tab and
-- the Group Finder panel share one computation per change and an invite made through
-- Blizzard's own button still updates the Invite buttons here.
local cache = { evals = {} }
local function ClearCache() cache.sig, cache.list, cache.ctxSig, cache.ctx, cache.evals = nil, nil, nil, nil, {} end
ns:On("SETTINGS_CHANGED", ClearCache)
Fit.ClearCache = ClearCache

local function ContextSig(dungeonKey, level, levelSource, comp, settings)
  local parts = { tostring(dungeonKey), tostring(level), tostring(levelSource),
    ns.Affixes and ns.Affixes:Signature() or "", A:SettingsSig(settings), Fit.PastSig(settings) }
  for _, m in ipairs(comp) do
    -- The label shows up in the notes ("Second Battle rez, backing up Hal").
    parts[#parts + 1] = tostring(m.specID or m.classFile) .. ":" .. tostring(m.role) .. ":" .. tostring(m.label) .. (m.reserved and ":R" or "")
  end
  return table.concat(parts, ";")
end

-- What Evaluate reads from one application.
local function AppSig(g)
  local parts = { tostring(g.applicantID) }
  for _, a in ipairs(g.members) do
    parts[#parts + 1] = tostring(a.full or a.name) .. ":" .. tostring(a.specID or a.classFile) .. ":" .. tostring(a.role) .. ":" ..
      (a.bestHere and (tostring(a.bestHere.level) .. (a.bestHere.timed and "T" or "")) or "")
  end
  return table.concat(parts, ",")
end

-- What the UI reads straight from the applicant rows (not part of the evaluation).
local function RowSig(g)
  local parts = {}
  for _, a in ipairs(g.members) do
    parts[#parts + 1] = tostring(a.status) .. ":" .. tostring(a.score) .. ":" .. tostring(a.itemLevel) .. ":" ..
      tostring(a.level) .. ":" .. tostring(a.firstSeen) .. ":" .. tostring(a.isLeaver)
  end
  return table.concat(parts, ",")
end

function Fit:ForLiveGroup()
  Init()
  local T = ns.Tracker
  local settings = ns.db.settings
  local dungeonKey = ns:GetEffectiveDungeon(true)
  local level, levelSource = self:GetKeyLevel(dungeonKey)
  -- The party plus reserved slots (1.5.0): applicants are rated for the slots still open.
  local comp, groups = (ns.Players and ns.Players:LiveComp() or T:GetComp()), T:GetApplicantGroups()
  local ctxSig = ContextSig(dungeonKey, level, levelSource, comp, settings)
  local appSigs, full = {}, { ctxSig }
  for i, g in ipairs(groups) do
    appSigs[i] = AppSig(g)
    full[#full + 1] = appSigs[i] .. "/" .. RowSig(g)
  end
  local sig = table.concat(full, "|")
  if cache.sig == sig then return cache.ctx, cache.list end
  if cache.ctxSig ~= ctxSig then
    cache.ctx = self:BuildContext(comp, dungeonKey, settings, level)
    cache.ctx.keyLevelSource = levelSource
    cache.ctxSig, cache.evals = ctxSig, {}
  end
  local ctx, kept, list = cache.ctx, {}, {}
  for i, g in ipairs(groups) do
    local ev = cache.evals[appSigs[i]] or self:Evaluate(ctx, g)
    ev.members = g.members   -- the live rows: status, rating, item level, wait time
    kept[appSigs[i]] = ev
    list[#list + 1] = ev
  end
  cache.evals = kept         -- applications that left drop out
  self:Rank(list)
  cache.sig, cache.list = sig, list
  return ctx, list
end
