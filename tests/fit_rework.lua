-- python3 tests/run_tests.py --fit-rework
-- Pick rating rework: measurement report (not shipped, changes nothing in the addon).
-- Compares today's pick rating with a CANDIDATE scale on the same groups:
--   1. Severity ladder: a gap counts by its severity step (LADDER), not its raw penalty
--      weight, so one heavy item can't flatten every pick under it.
--   2. Stakes: when little separates the best and the weakest pick for a slot, ratings pull
--      toward STAKES_MID instead of stretching to 0-100.
-- The critical-gap floors apply to both. Experience and past keys mix in afterward the same
-- way for both, so they're left out except where a line says otherwise.
-- Everything a tuning pass changes is in CAND below.
local FILES = {}
for line in io.lines(ADDON_DIR .. "/Ensemble.toc") do
  local f = line:match("^%s*([%w_]+%.lua)%s*$")
  if f then FILES[#FILES + 1] = f end
end
ALLFRAMES = {}
local ns = {}
for _, f in ipairs(FILES) do assert(loadfile(ADDON_DIR .. "/" .. f))("Ensemble", ns) end
for _, fr in ipairs(ALLFRAMES) do
  if fr._events.ADDON_LOADED then
    fr._scripts.OnEvent(fr, "ADDON_LOADED", "Ensemble")
    fr._scripts.OnEvent(fr, "PLAYER_LOGIN")
  end
end
local Fit, UD, A, DD = ns.ApplicantFit, ns.UD, ns.Analysis, ns.Dungeons
local H = DD.HEURISTICS
local settings = ns.db.settings

---------------------------------------------------------------------------
-- The candidate's numbers.
---------------------------------------------------------------------------
local CAND = {
  LADDER = { critical = 5, high = 4, medium = 2, low = 0.5 },
  THIN = 0.4,            -- a thin need counts this share of a missing one...
  THIN_HIGH_KEY = 0.55,  -- ...and this share from HIGH_KEY_LEVEL up
  UNCONFIRMED = 0.5,     -- as today
  SYNERGY_DIV = 8,       -- raid buff synergy: penalty points / this
  STAKES_FULL = 6,       -- spread (ladder points) from which the full 0-100 scale is used
  STAKES_MID = 70,       -- where ratings sit when nothing separates the picks (today's FIT_FLAT_SCORE)
  GREAT = H.FIT_GREAT, GOOD = H.FIT_GOOD, FAIR = H.FIT_FAIR,
}

local function Band(score, c)
  c = c or CAND
  if score >= c.GREAT then return "great" elseif score >= c.GOOD then return "good"
  elseif score >= c.FAIR then return "fair" end
  return "poor"
end

-- A group's gaps in ladder points (lower is better), from the same itemized parts as the penalty.
local function LadderParts(r, level)
  local parts, syn = A:PenaltyParts(r, level)
  local thin = (level and level >= H.HIGH_KEY_LEVEL) and CAND.THIN_HIGH_KEY or CAND.THIN
  local out = {}
  for id, p in pairs(parts) do
    local w = CAND.LADDER[p.severity] or 0
    if p.status == "thin" then w = w * thin end
    -- PenaltyParts halves unconfirmed dungeon items; keep that.
    if id:find("^d:") then
      local full = ({ critical = 40, high = 20, medium = 8, low = 2 })[p.severity] or 0
      local expect = full * 1.5 * ((p.status == "missing") and 2 or ((level and level >= H.HIGH_KEY_LEVEL) and 1.5 or 0.8))
      if expect > 0 and p.points < expect * 0.75 then w = w * CAND.UNCONFIRMED end
    end
    out[id] = { points = w, label = p.label, severity = p.severity, status = p.status }
  end
  return out, syn / CAND.SYNERGY_DIV
end
local function LadderTotal(r, level)
  local parts, syn = LadderParts(r, level)
  local t = 0
  for _, p in pairs(parts) do t = t + p.points end
  return t - syn
end

local function With(members, specID)
  local out = {}
  for i, m in ipairs(members) do out[i] = m end
  out[#out + 1] = { specID = specID }
  return out
end
local function Members(specs)
  local out = {}
  for i, id in ipairs(specs) do out[i] = { specID = id, label = "M" .. i } end
  return out
end

-- Rate every spec of `role` for the open slot. Returns rows { id, today, cand, gain, lgain, kind }
-- plus info { spread (penalty), lspread (ladder), flat }.
local function RateSlot(members, role, dk, level)
  local ctx = Fit:BuildContext(members, dk, settings, level)
  local base = ctx.base
  local lbase = LadderTotal(base, level)
  local rows, lbest, lworst = {}, nil, nil
  for _, id in ipairs(UD:SpecsForRole(role)) do
    local ev = Fit:Evaluate(ctx, { applicantID = id, members = { { name = "S" .. id, specID = id, classFile = UD:GetSpec(id).class } } })
    if not ev.roleConflict then
      local lg = lbase - LadderTotal(ev.after, level)
      rows[#rows + 1] = { id = id, today = ev.score, gain = ev.gain, lgain = lg,
        kind = ev.critClose and ev.critClose.kind or nil, flat = ev.flat, after = ev.after }
      lbest = (not lbest or lg > lbest) and lg or lbest
      lworst = (not lworst or lg < lworst) and lg or lworst
    end
  end
  if #rows == 0 then return rows, { spread = 0, lspread = 0 } end
  local spread = lbest - lworst
  local function pos(g) return spread > 1e-6 and (g - lworst) / spread or 0.5 end
  -- Critical-gap floors, same rule as Fit.CritFloors, on ladder positions.
  local nonCloser, nonFull, anyFull, anyPartial
  for _, r in ipairs(rows) do
    if r.kind == "full" then anyFull = true
    else
      if not nonFull or r.lgain > nonFull then nonFull = r.lgain end
      if r.kind == "partial" then anyPartial = true
      elseif not nonCloser or r.lgain > nonCloser then nonCloser = r.lgain end
    end
  end
  local fullFloor = anyFull and nonFull and pos(nonFull) or nil
  local partFloor = anyPartial and nonCloser and pos(nonCloser) * (H.FIT_CRIT_PARTIAL_SHARE or 0.5) or nil
  local s = math.min(1, spread / CAND.STAKES_FULL)
  for _, r in ipairs(rows) do
    local p = pos(r.lgain)
    if r.kind == "full" and fullFloor then p = math.max(p, fullFloor) end
    if r.kind == "partial" and partFloor then p = math.max(p, partFloor) end
    r.pos = p
    r.cand = math.floor(s * p * 100 + (1 - s) * CAND.STAKES_MID + 0.5)
  end
  return rows, { spread = (ctx.bestGain[role] or 0) - (ctx.worstGain[role] or 0), lspread = spread, stakes = s,
                 flat = rows[1].flat, base = base }
end

local function Name(id) return UD:SpecName(id) .. " " .. UD:ClassName(UD:GetSpec(id).class) end
local function Find(rows, id) for _, r in ipairs(rows) do if r.id == id then return r end end end

---------------------------------------------------------------------------
-- 1. Reference cases (the author's answers, November 11, 2026).
---------------------------------------------------------------------------
print("# Pick rating rework: today vs candidate")
print(string.format("Candidate: ladder critical %g / high %g / medium %g / low %g; thin x%g (x%g from +%d); synergy / %g; full scale from a spread of %g ladder points, else toward %d. Bands %d / %d / %d.",
  CAND.LADDER.critical, CAND.LADDER.high, CAND.LADDER.medium, CAND.LADDER.low, CAND.THIN, CAND.THIN_HIGH_KEY, H.HIGH_KEY_LEVEL,
  CAND.SYNERGY_DIV, CAND.STAKES_FULL, CAND.STAKES_MID, CAND.GREAT, CAND.GOOD, CAND.FAIR))

local checks = {}
local function Check(ok, text) checks[#checks + 1] = (ok and "  PASS  " or "  MISS  ") .. text end

print("\n## Reference cases")
local SETH = { 581, 264, 63, 71 }   -- Vengeance DH, Restoration Shaman, Fire Mage, Arms Warrior
local SHOW = { 265, 258, 102, 70, 252, 269, 1467, 259, 253, 62, 71 }
for _, level in ipairs({ 8, 10, 12, 15 }) do
  local rows, info = RateSlot(Members(SETH), "DAMAGER", "TempleOfSethraliss", level)
  local parts = {}
  for _, id in ipairs(SHOW) do
    local r = Find(rows, id)
    parts[#parts + 1] = string.format("%s %d>%d", UD:SpecName(id), r.today, r.cand)
  end
  print(string.format("  Sethraliss +%d, last DPS slot (today>candidate): %s", level, table.concat(parts, ", ")))
  local druid, lock, dk, sp = Find(rows, 102), Find(rows, 265), Find(rows, 252), Find(rows, 258)
  Check(druid.cand >= 60 and druid.cand <= 79, string.format("case 4, +%d: Balance Druid (only battle rez) reads Good, upper half (60-79): %d", level, druid.cand))
  Check(lock.cand >= druid.cand, string.format("case 4, +%d: the Warlock (rez and a second Magic dispel) stays at or above the Druid: %d vs %d", level, lock.cand, druid.cand))
end
-- Case 1 at the item level: what one fix is worth on each scale.
do
  local L = CAND.LADDER
  for _, level in ipairs({ 10, 12 }) do
    local thin = (level >= H.HIGH_KEY_LEVEL) and CAND.THIN_HIGH_KEY or CAND.THIN
    local rez = L.high - L.low      -- fixes "no battle rez" (high), leaves "a single battle rez" (low)
    local backup = L.critical * thin
    local todayRez, todayBackup = 20 - 2, 40 * 1.5 * ((level >= H.HIGH_KEY_LEVEL) and 1.5 or 0.8)
    Check(rez > backup, string.format("case 1, +%d: bringing the only battle rez (%.2f) outranks a second dispeller for a critical mechanic (%.2f); today %.0f vs %.0f",
      level, rez, backup, todayRez, todayBackup))
  end
  Check(L.high < 2 * L.medium + 0.01 and L.high > L.medium, string.format("case 2: minor fixes add up, depending on the gap: one high (%g) = %g mediums = %g lows", L.high, L.high / L.medium, L.high / L.low))
end

---------------------------------------------------------------------------
-- 2. Random parties: band shares per open slot.
---------------------------------------------------------------------------
local seed = 20261111
local function Rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return (math.floor(seed / 65536) % n) + 1 end
local BY = { TANK = UD:SpecsForRole("TANK"), HEALER = UD:SpecsForRole("HEALER"), DAMAGER = UD:SpecsForRole("DAMAGER") }
local function Pick(role, used)
  for _ = 1, 60 do
    local id = BY[role][Rnd(#BY[role])]
    local k = UD:GetSpec(id).class .. role
    if not used[k] then used[k] = true; return id end
  end
end
local DKS = {}
for k in pairs(DD.list) do if k ~= "NONE" then DKS[#DKS + 1] = k end end
table.sort(DKS)

local FAMS = { "last DPS slot", "two DPS slots", "tank only: DPS", "healer slot", "tank slot" }
local stat = {}
local function Rec(fam, which, scores)
  stat[fam] = stat[fam] or {}
  local st = stat[fam][which] or { great = 0, good = 0, fair = 0, poor = 0, n = 0, groups = 0, noGood = 0, hist = {} }
  stat[fam][which] = st
  local good = 0
  for _, s in ipairs(scores) do
    local b = Band(s); st[b] = st[b] + 1; st.n = st.n + 1
    if b == "good" then good = good + 1 end
    local h = math.floor(s / 10); st.hist[h] = (st.hist[h] or 0) + 1
  end
  st.groups = st.groups + 1
  if good == 0 then st.noGood = st.noGood + 1 end
end
local low = { n = 0, both = 0, ranges = {} }
local agree = { n = 0, best = 0, great = 0, topDrop = 0 }
local exp = { today = { great = 0, good = 0, fair = 0, poor = 0, n = 0 }, cand = { great = 0, good = 0, fair = 0, poor = 0, n = 0 } }

local function Scenario(fam, specs, role, dk, level)
  local rows, info = RateSlot(Members(specs), role, dk, level)
  if #rows == 0 then return end
  local t, c = {}, {}
  for i, r in ipairs(rows) do t[i], c[i] = r.today, r.cand end
  Rec(fam, "today", t); Rec(fam, "cand", c)
  if fam == "last DPS slot" then
    -- low stakes: under 12 penalty points (less than one missing medium dungeon need) between best and weakest
    if info.spread < 12 then
      low.n = low.n + 1
      local tg, tp, mn, mx = false, false, 100, 0
      for _, r in ipairs(rows) do
        if r.today >= H.FIT_GREAT then tg = true end
        if r.today < H.FIT_FAIR then tp = true end
        mn, mx = math.min(mn, r.cand), math.max(mx, r.cand)
      end
      if tg and tp then low.both = low.both + 1 end
      low.ranges[#low.ranges + 1] = mx - mn
    end
    if not info.flat then
      local bt, bc = rows[1], rows[1]
      for _, r in ipairs(rows) do if r.gain > bt.gain then bt = r end; if r.cand > bc.cand then bc = r end end
      agree.n = agree.n + 1
      if bt.cand == bc.cand then agree.best = agree.best + 1 end
      if bt.cand >= CAND.GREAT or info.stakes < 1 then agree.great = agree.great + 1 end
    end
    -- With experience: every applicant has timed this dungeon at the key's level (100 points).
    local w = Fit:ExperienceWeight(level)
    for _, r in ipairs(rows) do
      local a = r.flat and r.today or math.floor((1 - w) * r.today + w * 100 + 0.5)
      local b = math.floor((1 - w) * r.cand + w * 100 + 0.5)
      exp.today[Band(a)] = exp.today[Band(a)] + 1; exp.today.n = exp.today.n + 1
      exp.cand[Band(b)] = exp.cand[Band(b)] + 1; exp.cand.n = exp.cand.n + 1
    end
  end
end

local PARTIES = tonumber(os and os.getenv and os.getenv("FIT_PARTIES")) or 40
for _, dk in ipairs(DKS) do
  for _, level in ipairs({ 8, 12 }) do
    for _ = 1, PARTIES do
      local used = {}
      local t, h = Pick("TANK", used), Pick("HEALER", used)
      local d1, d2, d3 = Pick("DAMAGER", used), Pick("DAMAGER", used), Pick("DAMAGER", used)
      Scenario("last DPS slot", { t, h, d1, d2 }, "DAMAGER", dk, level)
      Scenario("two DPS slots", { t, h, d1 }, "DAMAGER", dk, level)
      Scenario("tank only: DPS", { t }, "DAMAGER", dk, level)
      Scenario("healer slot", { t, d1, d2, d3 }, "HEALER", dk, level)
      Scenario("tank slot", { h, d1, d2, d3 }, "TANK", dk, level)
    end
  end
end

print(string.format("\n## Band shares, %d random parties per slot (8 dungeons x +8 and +12 x %d; specs drawn evenly, one per class in a role)", #DKS * 2 * PARTIES, PARTIES))
for _, fam in ipairs(FAMS) do
  for _, which in ipairs({ "today", "cand" }) do
    local s = stat[fam][which]
    print(string.format("  %-15s %-9s Great %4.1f%%  Good %4.1f%%  Fair %4.1f%%  Poor %4.1f%%  | groups with no Good: %4.1f%%",
      which == "today" and fam or "", which == "today" and "today" or "candidate",
      100 * s.great / s.n, 100 * s.good / s.n, 100 * s.fair / s.n, 100 * s.poor / s.n, 100 * s.noGood / s.groups))
  end
end
for _, which in ipairs({ "today", "cand" }) do
  local s = exp[which]
  print(string.format("  %-15s %-9s Great %4.1f%%  Good %4.1f%%  Fair %4.1f%%  Poor %4.1f%%  (every applicant timed this dungeon at the key's level)",
    which == "today" and "last DPS, exp." or "", which == "today" and "today" or "candidate",
    100 * s.great / s.n, 100 * s.good / s.n, 100 * s.fair / s.n, 100 * s.poor / s.n))
end

print("\n## Histogram, last DPS slot (score in tens)")
for _, which in ipairs({ "today", "cand" }) do
  local s, parts = stat["last DPS slot"][which], {}
  for i = 0, 10 do parts[#parts + 1] = string.format("%d:%d", i * 10, s.hist[i] or 0) end
  print(string.format("  %-9s %s", which == "today" and "today" or "candidate", table.concat(parts, " ")))
end

table.sort(low.ranges)
local function Pct(t, p) return #t > 0 and t[math.max(1, math.ceil(#t * p))] or 0 end
print("\n## Low stakes and agreement (last DPS slot)")
print(string.format("  %d of %d groups have under 12 penalty points between the best and the weakest pick; today %d of them show both Great and Poor.",
  low.n, stat["last DPS slot"].today.groups, low.both))
print(string.format("  Candidate, those groups: ratings span %d points at the median, %d at the 90th percentile, %d at most.",
  Pct(low.ranges, 0.5), Pct(low.ranges, 0.9), low.ranges[#low.ranges] or 0))
Check(Pct(low.ranges, 0.5) <= 20, string.format("case 3: with little at stake the ratings keep a narrow spread (about 15): median %d, 90th percentile %d", Pct(low.ranges, 0.5), Pct(low.ranges, 0.9)))
print(string.format("  Today's best pick is still the (joint) best on the candidate in %d of %d groups with a real difference.", agree.best, agree.n))

print("\n## Reference checks")
for _, c in ipairs(checks) do print(c) end

---------------------------------------------------------------------------
-- 3. A sample "Why N?" on the ladder.
---------------------------------------------------------------------------
print("\n## Sample breakdown on the ladder (Sethraliss +10, last DPS slot)")
do
  local rows, info = RateSlot(Members(SETH), "DAMAGER", "TempleOfSethraliss", 10)
  local bp, bs = LadderParts(info.base, 10)
  for _, id in ipairs({ 265, 102, 269, 259 }) do
    local r = Find(rows, id)
    local ap, as = LadderParts(r.after, 10)
    local lines = {}
    for pid, p in pairs(bp) do
      local d = p.points - (ap[pid] and ap[pid].points or 0)
      if d > 0.01 then lines[#lines + 1] = { d, string.format("+%g %s %s", d, (p.status == "thin") and "backs up" or "fixes", (p.label:gsub("^no ", "missing "))) } end
    end
    for pid, p in pairs(ap) do
      local d = p.points - (bp[pid] and bp[pid].points or 0)
      if d > 0.01 then lines[#lines + 1] = { -d, string.format("-%g adds a gap: %s", d, p.label) } end
    end
    if math.abs(as - bs) > 0.01 then lines[#lines + 1] = { as - bs, string.format("%+.1f raid buff synergy", as - bs) } end
    table.sort(lines, function(x, y) return math.abs(x[1]) > math.abs(y[1]) end)
    local t = {}
    for _, l in ipairs(lines) do t[#t + 1] = l[2] end
    print(string.format("  %s: %d (today %d). %s", Name(id), r.cand, r.today, table.concat(t, "; ")))
  end
end
