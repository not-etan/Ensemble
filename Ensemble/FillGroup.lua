-- Ensemble / FillGroup.lua
-- Fill group and Auto-fill: find a full group among your applicants (always 1 tank, 1 healer,
-- 3 DPS) that covers what the key needs, and invite it with one click.
--
-- Pure planning first (no frames): filters, musts, strictness, choosing the group. Then the
-- invite (always from the player's click) and Auto-fill, which only finds a group and tells
-- the player; Ensemble never invites on its own.
--
-- How a group passes (designed with the author, October 22-24, 2026):
--   Musts, per dungeon: Bloodlust, plus every requirement the dungeon's boss cards list
--     (BossData `reqs`), low-severity ones unticked; the player can untick any or add the
--     dungeon's other requirements. A must passes when it isn't MISSING; Strict adds not THIN.
--   Strictness, on top of the musts (the needs model's status x severity):
--     Relaxed  = no critical need MISSING
--     Standard = also no high need MISSING (battle rez is a high generic need, so it's in)
--     Strict   = nothing medium or worse MISSING, and no critical or high need THIN
--     Match the key level = Relaxed to +6, Standard +7 to +11, Strict from +12 (default).
--   Needs unticked in What to check stay out. A need only counts as covered through a solid
--   source, so a Mass Dispel or an Imp can't make a group pass: never a pet, conditional,
--   long-cooldown or unconfirmed source, or a member whose spec isn't known. Optional talents
--   count when What to check's "Count optional talents" is on (the default; the author's call,
--   October 24, 2026, after the strict full-close test left Freedom to Mistweaver Monks only).
--   A fallback battle rez (Holy Paladin's Intercession, when no Death Knight, Druid or Warlock
--   is in the group) counts as a THIN battle rez: Relaxed and Standard pass, Strict doesn't.
-- Filters: minimum M+ rating and item level (each from "Suggested for the key", your listing's
-- minimums or a number you set), the leaver flag, and missing data. A premade is all-or-nothing.
-- Choosing: pending invites count toward the group; the remaining slots are filled from the
-- applications that pass the filters, pruned per role to the best few by pick rating; cheap
-- capability counts rule groups out before the full analysis; the highest total pick rating
-- among the groups that pass wins, ties to the longest wait. Never a partial invite.

local _, ns = ...

local FG = {}
ns.FillGroup = FG

local UD, DD, A, Fit
local function Init() UD, DD, A, Fit = ns.UD, ns.Dungeons, ns.Analysis, ns.ApplicantFit end

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_WORD = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local SEV_RANK = { critical = 1, high = 2, medium = 3, low = 4, info = 5 }

FG.LEVELS = { "relaxed", "standard", "strict" }
FG.LEVEL_LABEL = { auto = "Match the key level", relaxed = "Relaxed", standard = "Standard", strict = "Strict" }

-- The generic needs (What to check's generic checks) a level can ask for, with the severity
-- the needs model gives a group that has none. Each follows its What to check switch.
local GENERIC = {
  { cap = "interrupt", sev = "critical", check = "interrupts" },
  { cap = "bloodlust", sev = "high", check = "lust" },
  { cap = "battle_rez", sev = "high", check = "brez" },
  { cap = "stop", sev = "high", check = "cc" },
  { cap = "aoe_stop", sev = "medium", check = "cc" },
  { cap = "dispel_magic", sev = "medium", check = "dispels" },
  { cap = "dispel_curse", sev = "medium", check = "dispels" },
  { cap = "dispel_poison", sev = "medium", check = "dispels" },
  { cap = "dispel_disease", sev = "medium", check = "dispels" },
}
FG.GENERIC = GENERIC

local function H() return ns.Dungeons.HEURISTICS end
local function Settings(settings) return settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings end
local function FillSettings(settings) return Settings(settings).fill or ns.DEFAULTS.settings.fill end

---------------------------------------------------------------------------
-- Strictness
---------------------------------------------------------------------------
-- The level for this key: "relaxed" | "standard" | "strict", whether it came from the key
-- level (auto), and whether the key level was unknown (auto falls back to Standard).
function FG:Level(settings, keyLevel)
  Init()
  local lv = FillSettings(settings).level or "auto"
  if lv ~= "auto" then return lv, false, false end
  local h = H()
  if not keyLevel then return "standard", true, true end
  if keyLevel >= (h.FILL_STRICT_FROM or 12) then return "strict", true, false end
  if keyLevel >= (h.FILL_STANDARD_FROM or 7) then return "standard", true, false end
  return "relaxed", true, false
end

-- Does a need with this status and severity stop a group at this level?
function FG.LevelFails(level, status, sev)
  local r = SEV_RANK[sev] or 9
  if status == "missing" then
    if level == "strict" then return r <= 3 end
    if level == "standard" then return r <= 2 end
    return r <= 1
  elseif status == "thin" then
    return level == "strict" and r <= 2
  end
  return false
end

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------
-- Rating for timing every Season dungeon at +L, no speed bonus (Blizzard's scoring model as
-- the season's calculators give it; the numbers live in DD.HEURISTICS so a season change is
-- one place).
function FG.RatingForLevel(L)
  Init()
  local h = H()
  local base = h.RATING_BASE_LEVEL or 2
  if not L or L < base then return 0 end
  local per = (h.RATING_BASE or 155) + (h.RATING_PER_LEVEL or 15) * (L - base)
  for _, step in ipairs(h.RATING_AFFIX_LEVELS or {}) do
    if L >= step then per = per + (h.RATING_AFFIX_BONUS or 15) end
  end
  return per * (h.RATING_DUNGEONS or 8)
end

-- "Suggested for the key": every dungeon timed two levels below the key, rounded down to 50.
-- nil up to +6 (newer players, low keys) or with no key level.
function FG:SuggestedRating(keyLevel)
  Init()
  local h = H()
  if not keyLevel or keyLevel < (h.FILL_SUGGEST_FROM or 7) then return nil end
  local v = FG.RatingForLevel(keyLevel - (h.FILL_SUGGEST_OFFSET or 2))
  local step = h.FILL_RATING_ROUND or 50
  return math.floor(v / step) * step
end

-- What a key two levels lower drops at the end of the run, read from the game so it follows
-- patches: C_MythicPlus.GetRewardLevelForDifficultyLevel(level) -> weeklyRewardLevel,
-- endOfRunRewardLevel (Blizzard's 12.1.5 API docs). nil up to +6, with no key level, or when
-- the function is missing (second return "api").
function FG:SuggestedItemLevel(keyLevel)
  Init()
  local h = H()
  if not keyLevel or keyLevel < (h.FILL_SUGGEST_FROM or 7) then return nil end
  local fn = C_MythicPlus and C_MythicPlus.GetRewardLevelForDifficultyLevel
  if type(fn) ~= "function" then return nil, "api" end
  local ok, _, endOfRun = pcall(fn, math.max(2, keyLevel - (h.FILL_SUGGEST_OFFSET or 2)))
  endOfRun = ok and tonumber(endOfRun) or nil
  if endOfRun and endOfRun > 0 then return math.floor(endOfRun) end
  return nil, "api"
end

-- Your listing's own minimums: GetActiveEntryInfo().requiredDungeonScore / requiredItemLevel.
-- Each is nil when the listing sets none (or the fields are missing).
function FG:ListingMinimums()
  if not (C_LFGList and C_LFGList.GetActiveEntryInfo) then return nil, nil end
  local ok, entry = pcall(C_LFGList.GetActiveEntryInfo)
  if not ok or type(entry) ~= "table" then return nil, nil end
  local r = tonumber(entry.requiredDungeonScore)
  local i = tonumber(entry.requiredItemLevel)
  return (r and r > 0) and r or nil, (i and i > 0) and math.floor(i) or nil
end

-- The filters in force: { rating = { on, value, source, why }, ilvl = {...}, leaver, noData }.
-- `on` is false when the setting is off or no value applies (why says which).
function FG:Filters(settings, keyLevel)
  Init()
  local fs = FillSettings(settings)
  local h = H()
  local listing
  local function one(conf, suggested, kind)
    local out = { source = conf.source or "suggested", on = false }
    if conf.on == false then out.why = "off"; return out end
    local v, why
    if out.source == "custom" then v = tonumber(conf.value)
    elseif out.source == "listing" then
      if not listing then
        local r, i = self:ListingMinimums()
        listing = { rating = r, ilvl = i }
      end
      v = listing[kind]
      if not v then why = "your listing sets none" end
    else
      v = suggested
      if not v then
        if not keyLevel then why = "key level unknown"
        elseif keyLevel < (h.FILL_SUGGEST_FROM or 7) then why = "off up to +" .. ((h.FILL_SUGGEST_FROM or 7) - 1)
        else why = "the game didn't give a value" end
      end
    end
    if v and v > 0 then out.on, out.value = true, math.floor(v) else out.why = why or "no value" end
    return out
  end
  local sugI = self:SuggestedItemLevel(keyLevel)
  return {
    rating = one(fs.rating or {}, self:SuggestedRating(keyLevel), "rating"),
    ilvl = one(fs.ilvl or {}, sugI, "ilvl"),
    leaver = fs.skipLeavers ~= false,
    noData = fs.skipNoData ~= false,
  }
end

-- nil when an applicant row passes, else the reason ("M+ rating 2950 (needs 3000)").
function FG.FilterMember(m, f)
  if f.leaver and m.isLeaver then return "has the game's leaver flag" end
  if f.rating.on then
    local v = tonumber(m.score)
    if v == nil then
      if f.noData then return "no M+ rating from the game" end
    elseif v < f.rating.value then
      return string.format("M+ rating %d (needs %d)", math.floor(v), f.rating.value)
    end
  end
  if f.ilvl.on then
    local v = tonumber(m.itemLevel)
    if v == nil or v <= 0 then
      if f.noData then return "no item level from the game" end
    elseif v < f.ilvl.value then
      return string.format("item level %d (needs %d)", math.floor(v), f.ilvl.value)
    end
  end
  return nil
end

-- A premade is all-or-nothing: one member failing a filter rules out the application.
function FG.FilterApplication(ev, f)
  for _, m in ipairs(ev.members or {}) do
    local why = FG.FilterMember(m, f)
    if why then
      return (#ev.members > 1 and (tostring(m.name) .. ": ") or "") .. why
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Musts (per dungeon)
---------------------------------------------------------------------------
local function ReqByID(dk, id)
  local d = ns.Dungeons.list[dk or ""]
  for _, q in ipairs(d and d.requirements or {}) do if q.id == id then return q end end
  return nil
end
FG.ReqByID = ReqByID

-- "Toxic Spores" from "Toxic Spores (Hoardmonger, ...)".
local function CastName(req)
  local src = req and req.source or ""
  return ((src:match("^([^,(]+)") or src):gsub("%s+$", ""))
end
FG.CastName = CastName

-- The cast in a requirement's source that a given boss uses ("Rimeshatter" for the Sentinel
-- of Winter in "Glacial Tomb (Avatar of Determination), ..., Rimeshatter (Sentinel of Winter)").
local function BossCast(req, bossName)
  local src = req and req.source or ""
  if bossName then
    local lb = bossName:lower()
    for cast, mob in src:gmatch("%s*([^,(]-)%s*%(([^)]*)%)") do
      local lm = mob:lower()
      if lm ~= "" and (lm:find(lb, 1, true) or lb:find(lm, 1, true)) then return cast end
    end
  end
  return CastName(req)
end
FG.BossCast = BossCast

-- Every requirement the dungeon's boss cards list, once, in boss order:
-- { { req, bosses = { names }, default = bool } }. Low severity starts unticked.
function FG:BossNeeds(dk)
  Init()
  local out, byID = {}, {}
  for _, b in ipairs(ns.BossCards and ns.BossCards:Bosses(dk) or {}) do
    for _, id in ipairs(b.reqs or {}) do
      local req = ReqByID(dk, id)
      if req and not req.invalid then
        local e = byID[id]
        if not e then
          e = { req = req, bosses = {}, default = req.severity ~= "low" }
          byID[id] = e
          out[#out + 1] = e
        end
        e.bosses[#e.bosses + 1] = b.name
      end
    end
  end
  return out
end

-- The dungeon's other requirements (trash, from DungeonData), for "+ Add a need".
function FG:OtherNeeds(dk)
  Init()
  local boss = {}
  for _, e in ipairs(self:BossNeeds(dk)) do boss[e.req.id] = true end
  local out = {}
  local d = DD.list[dk or ""]
  for _, q in ipairs(d and d.requirements or {}) do
    if not q.invalid and not boss[q.id] then out[#out + 1] = q end
  end
  return out
end

-- The musts for a dungeon: { lust = bool, rows = { { req, bosses, boss = bool, on = bool } },
-- reqs = { the ticked requirements }, custom = bool }. Saved per dungeon in db.fillMusts[dk]
-- as { lust = bool|nil, on = { [id] = bool } } (only what differs from the defaults).
function FG:Musts(dk)
  Init()
  local saved = ns.db and type(ns.db.fillMusts) == "table" and ns.db.fillMusts[dk or ""] or nil
  local on = saved and type(saved.on) == "table" and saved.on or {}
  local out = { lust = not (saved and saved.lust == false), rows = {}, reqs = {}, custom = saved ~= nil, labels = {} }
  for _, e in ipairs(self:BossNeeds(dk)) do
    local v = on[e.req.id]
    if v == nil then v = e.default end
    out.rows[#out.rows + 1] = { req = e.req, bosses = e.bosses, boss = true, on = v and true or false }
    out.labels[e.req.id] = UD:CapLabel(e.req.need) .. " for " .. BossCast(e.req, e.bosses[1])
    if v then out.reqs[#out.reqs + 1] = e.req end
  end
  for _, q in ipairs(self:OtherNeeds(dk)) do
    if on[q.id] == true then
      out.rows[#out.rows + 1] = { req = q, bosses = {}, boss = false, on = true }
      out.reqs[#out.reqs + 1] = q
    end
  end
  return out
end

-- Tick or untick one must ("lust" for Bloodlust, else a requirement ID).
function FG:SetMust(dk, id, value)
  if not (ns.db and dk) then return end
  ns.db.fillMusts = ns.db.fillMusts or {}
  local s = ns.db.fillMusts[dk] or { on = {} }
  s.on = s.on or {}
  if id == "lust" then s.lust = value and true or false
  else s.on[id] = value and true or false end
  ns.db.fillMusts[dk] = s
  ns:Fire("FILL_SETTINGS_CHANGED")
end

-- "Reset needs": the dungeon's defaults again.
function FG:ResetMusts(dk)
  if ns.db and ns.db.fillMusts then ns.db.fillMusts[dk or ""] = nil end
  ns:Fire("FILL_SETTINGS_CHANGED")
end

-- "Poison dispel - Toxic Spores, The Hoardmonger" (min 2: "Interrupts (2)").
function FG:MustLabel(row)
  Init()
  local req = row.req
  local label = UD:CapLabel(req.need)
  if (req.minProviders or 1) > 1 then label = label .. " (" .. req.minProviders .. ")" end
  if not row.boss then return label, CastName(req) .. " (trash)" end
  local casts, seen = {}, {}
  for _, b in ipairs(row.bosses) do
    local c = BossCast(req, b)
    if not seen[c] then seen[c] = true; casts[#casts + 1] = c end
  end
  return label, table.concat(casts, ", ") .. ", " .. table.concat(row.bosses, ", ")
end

---------------------------------------------------------------------------
-- Judging one group (a full analysis)
---------------------------------------------------------------------------
local function ReqKeys(req)
  local keys = { req.need }
  for _, a in ipairs(req.alt or {}) do keys[#keys + 1] = a end
  return keys
end

-- A source Fill group counts (see the header): talents are already left out by UD:Sources when
-- "Count optional talents" is off. A fallback (Intercession) is its own case: thin, never solid.
local function SolidSource(e)
  return e and not (e.long or e.pet or e.conditional or e.verify or e.fallback) and true or false
end
FG.SolidSource = SolidSource
local function SolidEntry(p) return not p.member.pending and SolidSource(p.entry) end

-- Distinct members with a solid source of any of `keys` in analysis r, and how many more only
-- have a fallback (a thin source).
local function SolidCount(r, keys)
  local seen, n, fb = {}, 0, 0
  for _, k in ipairs(keys) do
    for _, p in ipairs(r.caps[k] or {}) do
      if not seen[p.index] then
        if SolidEntry(p) then seen[p.index] = true; n = n + 1
        elseif p.entry and p.entry.fallback and not p.member.pending then seen[p.index] = true; fb = fb + 1 end
      end
    end
  end
  return n, fb
end
FG.SolidCount = SolidCount

-- A must's status: missing / thin / covered, solid sources only.
local function MustStatus(r, req)
  local n, fb = SolidCount(r, ReqKeys(req))
  if n == 0 then return (req.confidence == "verified" and fb == 0) and "missing" or "thin" end
  if n < (req.minProviders or 1) then return "thin" end
  if n == 1 and req.severity == "critical" and H().CRITICAL_SOLE_PROVIDER_IS_THIN then return "thin" end
  return "covered"
end

-- A dungeon item's status with the solid-source rule on top of the analysis.
local function ItemStatus(it)
  if it.aggregate then return it.status end
  local n, fb = 0, 0
  for _, p in ipairs(it.providers or {}) do
    if SolidEntry(p) then n = n + 1 elseif p.entry and p.entry.fallback and not p.member.pending then fb = fb + 1 end
  end
  if n == 0 then return (it.unconfirmed or fb > 0) and "thin" or "missing" end
  if it.status ~= "covered" then return it.status end
  if n < (it.req.minProviders or 1) then return "thin" end
  return "covered"
end

local function GenericOn(g, settings)
  local s = Settings(settings)
  return (s.checks or {})[g.check] ~= false and not (s.ignoredNeeds or {})[g.cap]
end

local function ShortSource(src) return src and (src:gsub("%s*%(.-%)", "")) or "" end

-- Judge an analysis against a level and the musts. Returns
-- { pass, fails = { { label, status, sev, must, keys } }, thin = { labels }, mustRows = { { label, status } } }.
function FG:Judge(r, level, musts, settings)
  Init()
  local out = { pass = true, fails = {}, thin = {}, mustRows = {} }
  local function fail(e) out.pass = false; out.fails[#out.fails + 1] = e end
  -- Musts.
  if musts and musts.lust then
    local st = (SolidCount(r, { "bloodlust" })) > 0 and "covered" or "missing"
    out.mustRows[#out.mustRows + 1] = { label = "Bloodlust", status = st }
    if st == "missing" then fail({ label = "Bloodlust", status = st, sev = "high", must = true, keys = { "bloodlust" } }) end
  end
  for _, req in ipairs(musts and musts.reqs or {}) do
    local st = MustStatus(r, req)
    local label = (musts.labels and musts.labels[req.id]) or (UD:CapLabel(req.need) .. " for " .. CastName(req))
    out.mustRows[#out.mustRows + 1] = { label = label, status = st, req = req }
    if st == "missing" or (level == "strict" and st == "thin") then
      fail({ label = label, status = st, sev = req.severity, must = true, keys = ReqKeys(req) })
    elseif st == "thin" then
      -- A thin must passes below Strict, but it's still thin: listed with the rest, never
      -- shown as covered (1.4.1 review, R7; the never-hide-a-critical-detail rule).
      out.thin[#out.thin + 1] = label .. " (must)"
    end
  end
  -- The level: dungeon requirements (visible ones), then the generic needs. A requirement
  -- that's also a must was judged above (the must rule covers the level's).
  local isMust = {}
  for _, req in ipairs(musts and musts.reqs or {}) do isMust[req.id] = true end
  for _, it in ipairs((r.dungeon and r.dungeon.items) or {}) do
    local st = isMust[it.req.id] and "covered" or ItemStatus(it)
    local label = it.aggregate and "Kick rotation" or (UD:CapLabel(it.req.need) .. " for " .. CastName(it.req))
    if st == "thin" then out.thin[#out.thin + 1] = label end
    if st ~= "covered" and FG.LevelFails(level, st, it.req.severity) then
      fail({ label = label, status = st, sev = it.req.severity, keys = it.aggregate and { "interrupt" } or ReqKeys(it.req) })
    end
  end
  local solidMissing = {}
  for _, g in ipairs(GENERIC) do
    if GenericOn(g, settings) and not (g.cap == "bloodlust" and musts and musts.lust) then
      local n, fb = SolidCount(r, { g.cap })
      if n == 0 then
        solidMissing[g.cap] = true
        local label = UD:CapLabel(g.cap)
        if fb > 0 then
          -- Only a fallback (Intercession): a thin need at the need's own severity.
          label = label .. " (only a fallback)"
          out.thin[#out.thin + 1] = label
          if FG.LevelFails(level, "thin", g.sev) then fail({ label = label, status = "thin", sev = g.sev, keys = { g.cap } }) end
        elseif FG.LevelFails(level, "missing", g.sev) then
          fail({ label = label, status = "missing", sev = g.sev, keys = { g.cap } })
        end
      end
    end
  end
  for _, f in ipairs(r.findings or {}) do
    if f.cap and not solidMissing[f.cap] and not (f.short or ""):find("^no ")
      and (f.severity == "critical" or f.severity == "high" or f.severity == "medium") then
      local label = UD:CapLabel(f.cap) .. ": " .. f.short
      out.thin[#out.thin + 1] = label
      if FG.LevelFails(level, "thin", f.severity) then fail({ label = label, status = "thin", sev = f.severity, keys = { f.cap } }) end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Cheap capability counts (rule groups out before the full analysis)
---------------------------------------------------------------------------
-- Need specs: { keys, min, notMissing, covered, label, must, short = bool (rotational kicks) }.
-- Each test is a necessary condition of the full judge, so a group the counts rule out could
-- never pass; groups they let through still get the full analysis.
-- `solid` (1.4.1 review, R4): where the level fails a THIN need of that severity, a fallback
-- (Intercession) can't make it pass, so only solid sources count toward it. Then a pool whose
-- only battle rez is Intercession shows as a pool gap at Strict instead of sending every group
-- to the full analysis.
local function BuildSpecs(base, level, musts, settings)
  local specs = {}
  local crit = H().CRITICAL_SOLE_PROVIDER_IS_THIN
  -- A must's sole critical source is thin (MustStatus counts solid sources only), so 2 here.
  local function mustMin(req)
    local m = req.minProviders or 1
    if req.severity == "critical" and crit then m = math.max(m, 2) end
    return m
  end
  if musts and musts.lust then
    specs[#specs + 1] = { keys = { "bloodlust" }, min = 1, notMissing = true, label = "Bloodlust", must = true }
  end
  for _, req in ipairs(musts and musts.reqs or {}) do
    local strict = level == "strict"
    specs[#specs + 1] = { keys = ReqKeys(req), min = mustMin(req), notMissing = req.confidence == "verified",
      covered = strict, solid = strict, label = (musts.labels and musts.labels[req.id]) or (UD:CapLabel(req.need) .. " for " .. CastName(req)),
      must = true }
  end
  local isMust = {}
  for _, req in ipairs(musts and musts.reqs or {}) do isMust[req.id] = true end
  for _, it in ipairs((base.dungeon and base.dungeon.items) or {}) do
    local sev = it.req.severity
    if isMust[it.req.id] then
      -- judged as a must above
    elseif it.aggregate then
      local nm = FG.LevelFails(level, "missing", sev)
      local cv = FG.LevelFails(level, "thin", sev)
      if nm or cv then
        specs[#specs + 1] = { short = true, min = it.req.minProviders or 1, notMissing = nm, covered = cv, label = "Kick rotation" }
      end
    else
      local nm = FG.LevelFails(level, "missing", sev) and not it.unconfirmed
      local cv = FG.LevelFails(level, "thin", sev)
      if nm or cv then
        -- Only minProviders here, not the critical "sole source is thin" 2: the analysis applies
        -- that rule to every source, pets and conditional ones included, which these counts leave
        -- out (one solid source plus a pet's passes the judge; review, October 24, 2026).
        specs[#specs + 1] = { keys = ReqKeys(it.req), min = it.req.minProviders or 1, notMissing = nm, covered = cv, solid = cv,
          label = UD:CapLabel(it.req.need) .. " for " .. CastName(it.req) }
      end
    end
  end
  for _, g in ipairs(GENERIC) do
    if GenericOn(g, settings) and not (g.cap == "bloodlust" and musts and musts.lust) and FG.LevelFails(level, "missing", g.sev) then
      specs[#specs + 1] = { keys = { g.cap }, min = 1, notMissing = true, label = UD:CapLabel(g.cap), generic = true,
        solid = FG.LevelFails(level, "thin", g.sev) }
    end
  end
  return specs
end

local function ProfileFor(m)
  local p = m.specID and UD:GetSpec(m.specID)
  if p then return p, false end
  if m.classFile then return UD:ClassCommonProfile(m.classFile), true end
  return nil, true
end

-- Per member: does it solidly provide any of spec.keys; does it have a rotational kick.
local function MemberCounts(m, specs, settings)
  local profile, pending = ProfileFor(m)
  local out = {}
  for i, sp in ipairs(specs) do
    local hit = false
    if profile then
      if sp.short then
        for _, e in ipairs(UD:Sources(profile, "interrupt", settings) or {}) do if not e.long then hit = true end end
      elseif not pending then
        -- Fallbacks count here too (this is only a quick rule-out, never the final word), except
        -- where a thin need fails the level (sp.solid): there a fallback can't pass it.
        for _, k in ipairs(sp.keys) do
          for _, e in ipairs(UD:Sources(profile, k, settings) or {}) do
            if SolidSource(e) or (e.fallback and not sp.solid) then hit = true end
          end
        end
      end
    end
    out[i] = hit and 1 or 0
  end
  return out
end

local function AddCounts(into, add) for i, v in ipairs(add) do into[i] = (into[i] or 0) + v end end

-- Count of specs a set of counts fails.
local function CheapFails(specs, counts)
  local n = 0
  for i, sp in ipairs(specs) do
    local c = counts[i] or 0
    if (sp.notMissing and c == 0) or (sp.covered and c < sp.min) then n = n + 1 end
  end
  return n
end
-- For the tests: the cheap counts must never rule out a group the full judge would pass.
FG.BuildSpecs, FG.MemberCounts, FG.CheapFails = BuildSpecs, MemberCounts, CheapFails

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------
local function Members(ev)
  local out = {}
  for i, a in ipairs(ev.members or {}) do
    out[#out + 1] = { specID = a.specID, classFile = a.classFile, label = a.name,
      role = ev.roles and ev.roles[i] or a.role, applicant = true }
  end
  return out
end

local function Concat(a, b)
  local out = {}
  for _, x in ipairs(a) do out[#out + 1] = x end
  for _, x in ipairs(b) do out[#out + 1] = x end
  return out
end

local function Status(ev) return ev.members and ev.members[1] and ev.members[1].status end

-- Classes that could bring `keys` from a solid source in an open role: "Shaman, Mage or Evoker".
function FG:Coverers(keys, open, settings)
  Init()
  local names = {}
  for _, classFile in ipairs(UD.classOrder) do
    local cls = UD.classes[classFile]
    local ok = false
    for _, specID in ipairs(cls.specs) do
      local p = UD:GetSpec(specID)
      if (open[p.role] or 0) > 0 then
        for _, k in ipairs(keys) do
          for _, e in ipairs(UD:Sources(p, k, Settings(settings)) or {}) do if SolidSource(e) then ok = true end end
        end
      end
    end
    if ok then names[#names + 1] = UD:ClassName(classFile) end
  end
  return names
end

local function JoinOr(list)
  if #list == 0 then return "" end
  if #list == 1 then return list[1] end
  return table.concat(list, ", ", 1, #list - 1) .. " or " .. list[#list]
end
FG.JoinOr = JoinOr

-- Plan a fill from the live context and evaluations (ApplicantFit:ForLiveGroup).
-- Returns {
--   status = "ready" | "none" | "short" | "full" | "nodungeon" | "empty",
--   dungeonKey, keyLevel, level, levelAuto, levelUnknown, filters, musts,
--   open = { role -> slots left after pending invites }, slots, pending = { ev },
--   picks = { ev } (to invite, tank first), total, sig, judge, after (analysis), groupAfter,
--   runnerUp = { out = ev, inn = ev, diff } | nil, skipped = { { ev, reason } },
--   poolGaps = { { label, keys, coverers } }, blocking = text, closest = { picks, judge },
--   checked = full analyses run, leaves = groups counted
-- }
function FG:Plan(ctx, evals, settings)
  Init()
  settings = Settings(settings)
  local h = H()
  local plan = { picks = {}, pending = {}, skipped = {}, poolGaps = {}, checked = 0, leaves = 0 }
  plan.dungeonKey, plan.keyLevel = ctx and ctx.dungeonKey, ctx and ctx.keyLevel
  plan.level, plan.levelAuto, plan.levelUnknown = self:Level(settings, plan.keyLevel)
  plan.filters = self:Filters(settings, plan.keyLevel)
  plan.musts = self:Musts(plan.dungeonKey)
  if not ctx then plan.status = "empty"; return plan end
  if not plan.dungeonKey or not DD.list[plan.dungeonKey] then plan.status = "nodungeon"; return plan end

  -- Pending invites count toward the group.
  local open = {}
  for _, r in ipairs(ROLES) do open[r] = ctx.open[r] or 0 end
  local fixed = Concat(ctx.members, {})
  for _, ev in ipairs(evals or {}) do
    if Status(ev) == "invited" then
      plan.pending[#plan.pending + 1] = ev
      for _, m in ipairs(Members(ev)) do fixed[#fixed + 1] = m end
      for _, r in ipairs(ev.roles or {}) do if (open[r] or 0) > 0 then open[r] = open[r] - 1 end end
    end
  end
  plan.open = open
  local slots = 0
  for _, r in ipairs(ROLES) do slots = slots + open[r] end
  plan.slots = slots
  -- Reserved slots (1.5.0) are in ctx.members: Fill group plans only the rest.
  plan.reserved = 0
  for _, m in ipairs(ctx.members or {}) do if m.reserved then plan.reserved = plan.reserved + 1 end end
  if slots == 0 then plan.status = "full"; plan.reservedAll = plan.reserved > 0; return plan end

  -- Past keys together (1.5.0, F2): Skip works like a filter; Prefer and Lower priority move
  -- groups only in the order they're tried, so they act among groups that pass: a group that
  -- fails the level or a must never passes because of them, and coverage always wins.
  local fs = FillSettings(settings)
  local past = { prefer = fs.preferTimed == true, mode = fs.failedWith or "off" }
  past.w = ns.History and ns.History:PastPoints(plan.level) or 0
  plan.past = past
  local function PastOf(ev)
    local adj, tie, failedWho, timedN = 0, 0, nil, 0
    if not ns.History or not (past.prefer or past.mode ~= "off") then return 0, 0, nil, 0 end
    for _, m in ipairs(ev.members or {}) do
      local st, c = ns.History:Standing(m.full, settings)
      if st == "timed" and past.prefer then adj, tie, timedN = adj + past.w, tie + 1, timedN + 1
      elseif st == "failed" then
        if past.mode == "lower" then adj, tie = adj - past.w, tie - 1 end
        failedWho = failedWho or { m = m, c = c }
      end
    end
    return adj, tie, failedWho, timedN
  end

  -- Filters and the candidate pool.
  local cands = {}
  for _, ev in ipairs(evals or {}) do
    if Status(ev) ~= "invited" then
      local why = FG.FilterApplication(ev, plan.filters)
      local adj, tie, failedWho, timedN = PastOf(ev)
      if not why and failedWho and past.mode == "skip" then
        why = "past keys" .. (#(ev.members or {}) > 1 and (" with " .. tostring(failedWho.m.name)) or "")
          .. ": " .. tostring(ns.History:WithText(failedWho.c)) .. " with you"
      end
      if why then plan.skipped[#plan.skipped + 1] = { ev = ev, reason = why }
      else
        local need, fits = {}, true
        for _, r in ipairs(ev.roles or {}) do need[r] = (need[r] or 0) + 1 end
        for r, n in pairs(need) do if n > (open[r] or 0) then fits = false end end
        if fits and #(ev.roles or {}) > 0 then
          cands[#cands + 1] = { ev = ev, need = need, adj = adj, tie = tie, timedN = timedN, failed = failedWho and true or nil }
        end
      end
    end
  end

  -- Need specs and per-application counts.
  local baseR = A:Analyze(fixed, plan.dungeonKey, settings)
  local specs = BuildSpecs(baseR, plan.level, plan.musts, settings)
  plan.specs = specs
  local baseCounts = {}
  for _, m in ipairs(fixed) do AddCounts(baseCounts, MemberCounts(m, specs, settings)) end
  for _, c in ipairs(cands) do
    c.counts = {}
    for _, m in ipairs(Members(c.ev)) do AddCounts(c.counts, MemberCounts(m, specs, settings)) end
  end
  -- Pool gaps: musts and level needs nobody in the party, invited or applying (past the filters)
  -- brings from a solid source.
  local pool = {}
  AddCounts(pool, baseCounts)
  for _, c in ipairs(cands) do AddCounts(pool, c.counts) end
  for i, sp in ipairs(specs) do
    if sp.notMissing and (pool[i] or 0) == 0 then
      plan.poolGaps[#plan.poolGaps + 1] = { label = sp.label, keys = sp.keys or { "interrupt" }, must = sp.must,
        coverers = self:Coverers(sp.keys or { "interrupt" }, open, settings) }
    end
  end

  -- Prune per role to the best few by pick rating (premades kept, they're rare).
  local perRole = h.FILL_POOL_PER_ROLE or 8
  table.sort(cands, function(x, y)
    local sx, sy = x.ev.score + x.adj, y.ev.score + y.adj
    if sx ~= sy then return sx > sy end
    if x.tie ~= y.tie then return x.tie > y.tie end
    return (x.ev.members[1].firstSeen or 0) < (y.ev.members[1].firstSeen or 0)
  end)
  local kept, taken, cut = {}, {}, {}
  for _, c in ipairs(cands) do
    if #c.ev.members > 1 then kept[#kept + 1] = c
    else
      local r = c.ev.roles[1]
      taken[r] = (taken[r] or 0) + 1
      if taken[r] <= perRole then kept[#kept + 1] = c else cut[#cut + 1] = c end
    end
  end
  -- Need-aware keep (1.4.1 review, R1): pick rating scores each applicant alone, so the one
  -- player a must or a Strict need depends on can rank below the cut. For every need the group
  -- still has to find among applicants, each open role keeps at least one more provider than
  -- that role could seat (when the pool has them), taking the best-rated cut ones back. The
  -- search grows by a few players at most; `cut` is already sorted best first.
  plan.keptBack = 0
  if #cut > 0 then
    local back = {}
    for i, sp in ipairs(specs) do
      local target = sp.covered and sp.min or (sp.notMissing and 1 or 0)
      local need = target - (baseCounts[i] or 0)
      if need > 0 then
        for _, r in ipairs(ROLES) do
          if (open[r] or 0) > 0 then
            local want = math.min(need, open[r]) + 1
            local have = 0
            for _, c in ipairs(kept) do if (c.need[r] or 0) > 0 and (c.counts[i] or 0) > 0 then have = have + 1 end end
            for _, c in ipairs(cut) do
              if have >= want then break end
              if not back[c] and c.ev.roles[1] == r and (c.counts[i] or 0) > 0 then
                back[c] = true; have = have + 1
              end
            end
          end
        end
      end
    end
    for _, c in ipairs(cut) do
      if back[c] then kept[#kept + 1] = c; plan.keptBack = plan.keptBack + 1 end
    end
  end

  -- Every way to fill the open slots exactly. Counts, total and wait are kept as running sums
  -- (added on the way down, taken off on the way back), so a group costs one pass over the
  -- need specs (1,792 groups at 4 open slots with 8 per role).
  local leaves, chosen, left = {}, {}, {}
  for r, n in pairs(open) do left[r] = n end
  local counts, nspecs = {}, #specs
  for i = 1, nspecs do counts[i] = baseCounts[i] or 0 end
  local total, wait, adj, tie = 0, 0, 0, 0
  local function rec(i, remaining)
    if remaining == 0 then
      local fails = 0
      for k = 1, nspecs do
        local sp, c = specs[k], counts[k]
        if (sp.notMissing and c == 0) or (sp.covered and c < sp.min) then fails = fails + 1 end
      end
      local list = {}
      for k = 1, #chosen do list[k] = chosen[k] end
      leaves[#leaves + 1] = { list = list, total = total, wait = wait, cheap = fails, adj = adj, tie = tie }
      return
    end
    if i > #kept then return end
    local c = kept[i]
    local fits = true
    for r, n in pairs(c.need) do if n > (left[r] or 0) then fits = false end end
    if fits then
      local used = 0
      for r, n in pairs(c.need) do left[r] = left[r] - n; used = used + n end
      for k = 1, nspecs do counts[k] = counts[k] + (c.counts[k] or 0) end
      total, wait = total + (c.ev.score or 0), wait + (c.ev.members[1].firstSeen or 0)
      adj, tie = adj + c.adj, tie + c.tie
      chosen[#chosen + 1] = c
      rec(i + 1, remaining - used)
      chosen[#chosen] = nil
      total, wait = total - (c.ev.score or 0), wait - (c.ev.members[1].firstSeen or 0)
      adj, tie = adj - c.adj, tie - c.tie
      for k = 1, nspecs do counts[k] = counts[k] - (c.counts[k] or 0) end
      for r, n in pairs(c.need) do left[r] = left[r] + n end
    end
    rec(i + 1, remaining)
  end
  rec(1, slots)
  plan.leaves = #leaves
  if #leaves == 0 then
    plan.status = "short"
    local have = {}
    for _, c in ipairs(cands) do for r, n in pairs(c.need) do have[r] = (have[r] or 0) + n end end
    local want = {}
    for _, r in ipairs(ROLES) do
      local short = open[r] - (have[r] or 0)
      if short > 0 then want[#want + 1] = (short > 1 and (short .. " ") or "") .. ROLE_WORD[r] end
    end
    plan.blocking = #want > 0 and ("Waiting for applicants: " .. table.concat(want, ", ") .. (#plan.skipped > 0 and " (past your filters)" or ""))
      or "Waiting for applicants that fit the open slots together."
    return plan
  end
  -- Best total first; past keys (when on) add their points, and at Strict only break ties.
  table.sort(leaves, function(x, y)
    local tx, ty = x.total + x.adj, y.total + y.adj
    if tx ~= ty then return tx > ty end
    if x.tie ~= y.tie then return x.tie > y.tie end
    return x.wait < y.wait
  end)

  -- Full analysis, best total first, until two pass (the plan and the runner-up).
  local maxChecks = h.FILL_MAX_FULL_CHECKS or 60
  local function analyze(leaf)
    if leaf.judge then return leaf.judge end
    local adds = {}
    for _, c in ipairs(leaf.list) do for _, m in ipairs(Members(c.ev)) do adds[#adds + 1] = m end end
    local r = A:Analyze(Concat(fixed, adds), plan.dungeonKey, settings)
    plan.checked = plan.checked + 1
    leaf.r = r
    leaf.judge = self:Judge(r, plan.level, plan.musts, settings)
    return leaf.judge
  end
  local passed = {}
  for _, leaf in ipairs(leaves) do
    if leaf.cheap == 0 then
      if plan.checked >= maxChecks then plan.capped = true; break end
      if analyze(leaf).pass then passed[#passed + 1] = leaf; if #passed == 2 then break end end
    end
  end

  local function picksOf(leaf)
    local out = {}
    for _, c in ipairs(leaf.list) do out[#out + 1] = c.ev end
    local rank = { TANK = 1, HEALER = 2, DAMAGER = 3 }
    table.sort(out, function(a, b)
      local ra, rb = rank[a.roles[1]] or 4, rank[b.roles[1]] or 4
      if ra ~= rb then return ra < rb end
      return a.score > b.score
    end)
    return out
  end
  local function sigOf(list)
    local ids = {}
    for _, ev in ipairs(list) do ids[#ids + 1] = tostring(ev.applicantID) end
    table.sort(ids)
    return table.concat(ids, ",")
  end

  if passed[1] then
    local best = passed[1]
    plan.status = "ready"
    plan.picks = picksOf(best)
    plan.total = best.total
    plan.pastAdj = best.adj ~= 0 and best.adj or nil
    past.timedIDs = {}
    for _, c in ipairs(best.list) do if c.timedN > 0 then past.timedIDs[c.ev.applicantID] = true end end
    plan.judge = best.judge
    plan.after = best.r
    plan.groupAfter = Fit:GroupAfter(best.r, settings, 0)
    plan.sig = plan.dungeonKey .. ":" .. sigOf(plan.picks)
    local second = passed[2]
    if second then
      local inBest, inSecond = {}, {}
      for _, c in ipairs(best.list) do inBest[c.ev.applicantID] = c.ev end
      for _, c in ipairs(second.list) do inSecond[c.ev.applicantID] = c.ev end
      local outEv, innEv
      for id, ev in pairs(inBest) do if not inSecond[id] then outEv = ev end end
      for id, ev in pairs(inSecond) do if not inBest[id] then innEv = ev end end
      plan.runnerUp = { out = outEv, inn = innEv, diff = best.total - second.total }
    end
    return plan
  end

  -- Nothing passes: what's stopping it, and the closest group.
  plan.status = "none"
  table.sort(leaves, function(x, y)
    if x.cheap ~= y.cheap then return x.cheap < y.cheap end
    if x.total ~= y.total then return x.total > y.total end
    return x.wait < y.wait
  end)
  local closest = leaves[1]
  analyze(closest)
  plan.closest = { picks = picksOf(closest), judge = closest.judge, total = closest.total }
  local gap = plan.poolGaps[1]
  if gap then
    plan.blocking = "Waiting for " .. gap.label .. (#gap.coverers > 0 and (": " .. JoinOr(gap.coverers)) or "")
  else
    local f = closest.judge.fails[1]
    plan.blocking = f and ("Closest group: " .. (f.status == "missing" and "no " or "thin ") .. f.label) or "No group passes yet."
  end
  return plan
end

---------------------------------------------------------------------------
-- Current plan (cached on the live evaluation list and the Fill group settings)
---------------------------------------------------------------------------
local cache = {}
local function SettingsSig(settings, dk)
  local fs = FillSettings(settings)
  local parts = { tostring(fs.level), tostring(fs.skipLeavers), tostring(fs.skipNoData) }
  for _, k in ipairs({ "rating", "ilvl" }) do
    local c = fs[k] or {}
    parts[#parts + 1] = tostring(c.on) .. tostring(c.source) .. tostring(c.value)
  end
  -- Past keys (1.5.0): the toggles, what counts as failed, and the history they read.
  parts[#parts + 1] = tostring(fs.preferTimed) .. tostring(fs.failedWith)
  if fs.preferTimed or (fs.failedWith and fs.failedWith ~= "off") then
    local runs = ns.db and ns.db.history or {}
    parts[#parts + 1] = tostring((Settings(settings).pastKeys or {}).failed) .. ":" .. #runs .. ":"
      .. tostring(runs[1] and runs[1].started) .. ":" .. tostring(runs[1] and runs[1].result)
  end
  local m = ns.db and ns.db.fillMusts and ns.db.fillMusts[dk or ""]
  if m then
    parts[#parts + 1] = tostring(m.lust)
    local ids = {}
    for id, v in pairs(m.on or {}) do ids[#ids + 1] = id .. "=" .. tostring(v) end
    table.sort(ids)
    parts[#parts + 1] = table.concat(ids, ",")
  end
  return table.concat(parts, ";")
end
local function ClearCache() cache = {} end
FG.ClearCache = ClearCache
ns:On("SETTINGS_CHANGED", ClearCache)
ns:On("FILL_SETTINGS_CHANGED", ClearCache)

-- The plan for the live group right now, or nil when you're not hosting.
function FG:Current()
  Init()
  local T = ns.Tracker
  if not (T and T.hosting) then return nil end
  local ok, ctx, evals = pcall(Fit.ForLiveGroup, Fit)
  if not ok or not ctx then return nil end
  local sig = SettingsSig(nil, ctx.dungeonKey) .. "|" .. tostring(ctx.keyLevel)
  if cache.list == evals and cache.ctx == ctx and cache.sig == sig and cache.plan then return cache.plan end
  local okP, plan = pcall(self.Plan, self, ctx, evals)
  if not okP then
    self.planErrors = (self.planErrors or 0) + 1
    self.lastPlanError = tostring(plan)
    return nil
  end
  cache.list, cache.ctx, cache.sig, cache.plan = evals, ctx, sig, plan
  -- Track when the shown group last changed: the button pauses briefly after a change.
  local planSig = plan.status == "ready" and plan.sig or nil
  if planSig ~= self.lastPlanSig then
    self.lastPlanSig = planSig
    self.planChangedAt = GetTime and GetTime() or 0
  end
  return plan
end

-- Seconds left in the short pause after the plan changed (0 = clickable).
function FG:PauseLeft()
  local h = H()
  local since = (GetTime and GetTime() or 0) - (self.planChangedAt or -1000)
  return math.max(0, (h.FILL_INVITE_PAUSE or 1.5) - since)
end

---------------------------------------------------------------------------
-- Inviting (always from the player's click)
---------------------------------------------------------------------------
-- Whether the game lets one click send several invites isn't documented. The first fill on
-- a game build tries every invite on one click; if only some go through, Ensemble remembers it
-- for that build and the button invites one player per click ("Invite next (2 of 4)").
local function GameBuild()
  if not GetBuildInfo then return "?" end
  local ok, _, build = pcall(GetBuildInfo)
  return ok and tostring(build) or "?"
end
FG.GameBuild = GameBuild

function FG:InviteMode()
  local m = ns.db and ns.db.fillInvite
  if type(m) == "table" and m.oneAtATime and m.build == GameBuild() then return "one" end
  return "all"
end

local function Learn(reason)
  if not ns.db then return end
  ns.db.fillInvite = { oneAtATime = true, build = GameBuild(), reason = reason }
end
FG.Learn = Learn

-- Can the player send invites now? Returns can, reason.
function FG:CanInvite(plan)
  if not (C_LFGList and C_LFGList.InviteApplicant) then return false, "Inviting from here isn't available in this client." end
  if not plan or plan.status ~= "ready" then return false, "No full group passes yet." end
  if IsInGroup and IsInGroup() and UnitIsGroupLeader then
    local lead = UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
    if not lead then return false, "Only the group leader (or an assistant) can invite." end
  end
  -- Never past five: your group, invites already out, and this plan.
  local size = (GetNumGroupMembers and GetNumGroupMembers()) or 1
  if size == 0 then size = 1 end
  local out = 0
  if C_LFGList.GetNumInvitedApplicantMembers then
    local ok, n = pcall(C_LFGList.GetNumInvitedApplicantMembers)
    if ok and tonumber(n) then out = tonumber(n) end
  else
    for _, ev in ipairs(plan.pending) do out = out + #ev.members end
  end
  local adding = 0
  for _, ev in ipairs(plan.picks) do adding = adding + #ev.members end
  if size + out + adding > 5 then return false, "That would make more than five players." end
  return true
end

-- The button's label: "Fill group (4)", or "Invite next (2 of 4)" one per click.
function FG:ButtonText(plan)
  if not plan or plan.status ~= "ready" then return "Fill group" end
  local n = 0
  for _, ev in ipairs(plan.picks) do n = n + #ev.members end
  if self:InviteMode() == "one" then
    local done = 0
    for _, ev in ipairs(plan.pending) do done = done + #ev.members end
    return string.format("Invite next (%d of %d)", done + 1, done + n)
  end
  return "Fill group (" .. n .. ")"
end

-- The click. `shownSig` is the plan the player saw. Re-plans on fresh data and invites only if
-- the group is unchanged; returns ok, message. Records the attempt for /ens verify.
function FG:Fill(shownSig)
  Init()
  local T = ns.Tracker
  if T and T.Rescan then pcall(T.Rescan, T) end
  local plan = self:Current()
  if not plan or plan.status ~= "ready" then return false, "No full group passes any more." end
  if plan.sig ~= shownSig then return false, "The group changed: check the new plan, then click again." end
  if self:PauseLeft() > 0 then return false, "The plan just changed: check it, then click again." end
  local can, why = self:CanInvite(plan)
  if not can then return false, why end
  local mode = self:InviteMode()
  local todo = plan.picks
  local n = mode == "one" and 1 or #todo
  local rec = { at = GetTime and GetTime() or 0, mode = mode, planned = #todo, attempted = 0, sent = 0, errors = {}, ids = {},
    build = GameBuild() }
  self.lastFill = rec
  self.fillWindowUntil = rec.at + 3
  for i = 1, n do
    local ev = todo[i]
    rec.attempted = rec.attempted + 1
    local ok, err = pcall(C_LFGList.InviteApplicant, ev.applicantID)
    if ok then
      rec.sent = rec.sent + 1
      rec.ids[#rec.ids + 1] = ev.applicantID
      for _, m in ipairs(ev.members or {}) do m.status = "invited" end
    else
      rec.errors[#rec.errors + 1] = tostring(err)
      if i > 1 then Learn("error on invite " .. i) end
      break
    end
  end
  -- A few seconds later, count the invites the game took ("invited" or already in the group).
  if C_Timer and C_Timer.After and rec.sent > 1 then
    C_Timer.After(3, function() FG:ConfirmFill(rec) end)
  end
  ns:Fire("FILL_DONE", rec)
  Fit.ClearCache(); ClearCache()
  return rec.sent > 0, rec.sent > 0 and string.format("Invited %d of %d.", rec.sent, #todo) or "The game didn't accept the invite."
end

-- After a multi-invite click: how many actually went out. If only some did, invite one per
-- click from now on (for this game build).
function FG:ConfirmFill(rec)
  local T = ns.Tracker
  if T and T.Rescan then pcall(T.Rescan, T) end
  local status = {}
  for _, a in ipairs(T and T.applicants or {}) do status[a.applicantID] = a.status end
  local confirmed, stuck = 0, 0
  for _, id in ipairs(rec.ids) do
    local st = status[id]
    if st == "invited" or st == nil then confirmed = confirmed + 1   -- gone: joined (or declined)
    elseif st == "applied" then stuck = stuck + 1 end
  end
  rec.confirmed, rec.stuck = confirmed, stuck
  if stuck > 0 and confirmed > 0 then Learn(string.format("%d of %d invites went out", confirmed, #rec.ids))
  elseif stuck == 0 and confirmed == #rec.ids and #rec.errors == 0 and not rec.blocked and ns.db then
    -- Every invite went out on one click: remember it for this build, so /ens verify still says
    -- so after a /reload (1.4.1 review, R8). Never replaces a learned "one per click" for the build.
    local m = ns.db.fillInvite
    if not (type(m) == "table" and m.oneAtATime and m.build == GameBuild()) then
      ns.db.fillInvite = { oneAtATime = false, build = GameBuild(), reason = string.format("%d of %d invites went out on one click", confirmed, #rec.ids) }
    end
  end
  ns:Fire("FILL_DONE", rec)
end

-- The game's "blocked" event naming us during a fill: invite one per click from now on.
local blockWatch = CreateFrame and CreateFrame("Frame")
if blockWatch then
  for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do pcall(blockWatch.RegisterEvent, blockWatch, ev) end
  blockWatch:SetScript("OnEvent", function(_, event, addon, func)
    if addon ~= (ns.ADDON_NAME or "Ensemble") then return end
    local rec = FG.lastFill
    if rec and (GetTime and GetTime() or 0) <= (FG.fillWindowUntil or 0) then
      rec.blocked = tostring(func or event)
      Learn("the game blocked " .. tostring(func or "an invite"))
    end
  end)
end

-- One line for /ens verify and the bug report.
function FG:LastFillText()
  local rec = self.lastFill
  if not rec then return nil end
  local t = string.format("last fill: %d of %d invites sent (%s)", rec.sent, rec.planned, rec.mode == "one" and "one per click" or "one click")
  if rec.confirmed then t = t .. string.format(", %d confirmed by the game", rec.confirmed) end
  if rec.stuck and rec.stuck > 0 then t = t .. string.format(", %d not taken", rec.stuck) end
  if rec.blocked then t = t .. ", blocked: " .. rec.blocked end
  if #rec.errors > 0 then t = t .. ", error: " .. rec.errors[1] end
  return t
end

---------------------------------------------------------------------------
-- Auto-fill: armed per listing; finds the group and tells you, never invites by itself.
---------------------------------------------------------------------------
FG.armed = false

local function Hosting()
  if not (C_LFGList and C_LFGList.HasActiveEntryInfo) then return false end
  local ok, has = pcall(C_LFGList.HasActiveEntryInfo)
  return ok and has and true or false
end

function FG:SetArmed(v)
  v = v and Hosting() and true or false
  if v == self.armed then return end
  self.armed = v
  self.notifiedSig, self.pendingSig = nil, nil
  if self.waitTimer then self.waitTimer:Cancel(); self.waitTimer = nil end
  if v then ns.Tracker:Acquire("autofill") else ns.Tracker:Release("autofill") end
  ns:Fire("FILL_ARMED", v)
end

-- Listing created: arm when the setting says so. Listing gone: disarm.
function FG:OnListingChanged(listed, wasListed)
  if listed and not wasListed then
    self:SetArmed(FillSettings().autoArm == true)
  elseif not listed then
    self:SetArmed(false)
  end
end

-- A new passing group while armed: wait (so more players can apply), then notify once.
function FG:CheckAutoFill()
  if not self.armed then return end
  local plan = self:Current()
  local sig = plan and plan.status == "ready" and plan.sig or nil
  if not sig then
    self.pendingSig = nil
    if self.waitTimer then self.waitTimer:Cancel(); self.waitTimer = nil end
    if self.notifiedSig then self.notifiedSig = nil; ns:Fire("FILL_ALERT", nil) end
    return
  end
  if self.notifiedSig then
    if sig ~= self.notifiedSig then self.notifiedSig = sig; ns:Fire("FILL_ALERT", plan, true) end
    return
  end
  if self.pendingSig then return end
  self.pendingSig = sig
  local wait = tonumber(FillSettings().wait) or 15
  local function fire()
    FG.waitTimer = nil
    FG.pendingSig = nil
    local p = FG:Current()
    if FG.armed and p and p.status == "ready" and FG.notifiedSig ~= p.sig then
      FG.notifiedSig = p.sig
      FG:Notify(p)
    end
  end
  if self.waitTimer then self.waitTimer:Cancel(); self.waitTimer = nil end
  if wait <= 0 or not (C_Timer and C_Timer.NewTimer) then fire()
  else self.waitTimer = C_Timer.NewTimer(wait, fire) end
end

-- The group-ready sound (Settings > Fill group): Ensemble's chime (Media/GroupReady.ogg, the
-- default) or the game's ready check. The chime falls back to the ready check when the file
-- can't play (PlaySoundFile missing, or the client says it won't play it). Master channel, as
-- before, so it's heard with game sounds turned down. FG.lastSound records what played, for
-- /ens verify. Returns "chime", "readycheck" or nil.
FG.SOUNDS = { chime = "Ensemble chime", readycheck = "Game ready check" }
FG.SOUND_ORDER = { "chime", "readycheck" }
function FG:PlayReadySound(choice)
  choice = choice or FillSettings().soundChoice or "chime"
  local played, chimeDeclined, kitDeclined
  if choice == "chime" and PlaySoundFile then
    local ok, willPlay = pcall(PlaySoundFile, ns.READY_SOUND, "Master")
    if ok and willPlay then played = "chime" else chimeDeclined = true end
  end
  if not played and PlaySound then
    local kit = SOUNDKIT and (SOUNDKIT.READY_CHECK or SOUNDKIT.IG_PLAYER_INVITE)
    if kit then
      -- PlaySound's first return is willPlay too: false when game sound (or Master) is off.
      -- nil (a client that doesn't say) counts as played, as before (1.4.1 review, R6).
      local ok, willPlay = pcall(PlaySound, kit, "Master")
      if ok and willPlay ~= false then played = "readycheck" else kitDeclined = true end
    end
  end
  -- Both declined: the game isn't playing sounds right now, not a problem with the chime file.
  FG.lastSound = { choice = choice, played = played, soundOff = (not played and kitDeclined) or nil,
    chimeDeclined = chimeDeclined }
  return played
end

-- Sound plus the alert (the UI decides where: the docked panel, or the pop-up).
function FG:Notify(plan)
  if FillSettings().sound ~= false then self:PlayReadySound() end
  ns:Fire("FILL_ALERT", plan, false)
end

ns:On("LIVE_ROSTER_CHANGED", function() if FG.armed then FG:CheckAutoFill() end end)
ns:On("FILL_SETTINGS_CHANGED", function() if FG.armed then FG:CheckAutoFill() end end)
ns:On("SETTINGS_CHANGED", function() if FG.armed then FG:CheckAutoFill() end end)
ns:On("RESERVED_CHANGED", function() if FG.armed then FG:CheckAutoFill() end end)   -- 1.5.0
ns:On("HISTORY_CHANGED", function() if FG.armed then FG:CheckAutoFill() end end)    -- past keys
