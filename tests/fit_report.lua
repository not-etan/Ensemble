-- python3 tests/run_tests.py --fit
-- Fit rating measurement report (not shipped). Rates every spec as an
-- applicant and as a listing searcher against fixed party states in four dungeons, with no
-- key level and at +12, and prints the score spread and band counts per case, plus the
-- pieces that explain clustering (immediate / look-ahead parts, "no real difference" cases).
-- Run it before and after a change to the rating model or the band thresholds.
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

local Fit, LF, UD, A, DD = ns.ApplicantFit, ns.ListingFit, ns.UD, ns.Analysis, ns.Dungeons
local H = DD.HEURISTICS
local settings = ns.db.settings
LF:PlayerProfile(nil)  -- resolves ListingFit's module references (GroupProfile needs them)

-- Temple of Sethraliss added in 1.2.1: its critical Magic dispel need is where the partial
-- critical-gap rule shows (pet and long-cooldown dispels).
local DUNGEONS = { "AltarOfFangs", "KingsRest", "RubyLifePools", "TempleOfSethraliss" }
-- Fixed party states: Protection Warrior, Discipline Priest, Fire Mage, Havoc Demon Hunter.
local STATES = {
  { name = "empty",         specs = {} },
  { name = "1 member",      specs = { 73 } },
  { name = "3 members",     specs = { 73, 256, 63 } },
  { name = "full but one",  specs = { 73, 256, 63, 577 } },
}
local LEVELS = { false, 12 }

local function Members(specs)
  local out = {}
  for i, id in ipairs(specs) do out[i] = { specID = id, label = "M" .. i } end
  return out
end
local function ListingMembers(specs)
  local out = {}
  for i, id in ipairs(specs) do out[i] = { specID = id, role = UD:GetSpec(id).role, profile = LF.GroupProfile(id) } end
  return out
end

local BAND_KEYS = { "great", "good", "fair", "poor" }
local function Stats(list)
  local n, sum, mn, mx, distinct, seen = #list, 0, nil, nil, 0, {}
  local bands = { great = 0, good = 0, fair = 0, poor = 0 }
  local mid = 0
  for _, x in ipairs(list) do
    sum = sum + x.score
    mn = (not mn or x.score < mn) and x.score or mn
    mx = (not mx or x.score > mx) and x.score or mx
    if not seen[x.score] then seen[x.score] = true; distinct = distinct + 1 end
    bands[x.band] = bands[x.band] + 1
    if x.score >= 70 and x.score <= 85 then mid = mid + 1 end
  end
  local mean = n > 0 and sum / n or 0
  local var = 0
  for _, x in ipairs(list) do var = var + (x.score - mean) ^ 2 end
  return { n = n, mean = mean, sd = n > 0 and math.sqrt(var / n) or 0, min = mn or 0, max = mx or 0,
           distinct = distinct, bands = bands, mid = mid }
end

local function Row(label, s, extra)
  print(string.format("  %-34s n=%2d  min %3d max %3d mean %5.1f sd %4.1f  distinct %2d | G %2d Gd %2d F %2d P %2d | 70-85: %2d%s",
    label, s.n, s.min, s.max, s.mean, s.sd, s.distinct, s.bands.great, s.bands.good, s.bands.fair, s.bands.poor,
    s.mid, extra or ""))
end

local totals = { app = {}, lst = {} }
local function Add(t, list) for _, x in ipairs(list) do t[#t + 1] = x end end

print(string.format("Bands: Great >= %d, Good >= %d, Fair >= %d, else Poor. Role conflicts (no open slot) are left out of the spread.",
  H.FIT_GREAT, H.FIT_GOOD, H.FIT_FAIR))
for _, dk in ipairs(DUNGEONS) do
  for _, level in ipairs(LEVELS) do
    local lvl = level or nil
    print(string.format("\n## %s, %s", DD.list[dk].name, lvl and ("+" .. lvl) or "no key level"))
    for _, st in ipairs(STATES) do
      -- Applicants
      local members = Members(st.specs)
      local ctx = Fit:BuildContext(members, dk, settings, lvl)
      local apps, flat, crit, part, immSum, potSum, potN = {}, 0, 0, 0, 0, 0, 0
      for id in pairs(UD.specs) do
        local ev = Fit:Evaluate(ctx, { applicantID = id, members = { { name = "S" .. id, specID = id, classFile = UD:GetSpec(id).class } } })
        if not ev.roleConflict then
          local band = ev.rating.key
          apps[#apps + 1] = { score = ev.score, band = band, spec = id }
          if ev.flat then flat = flat + 1 end
          immSum = immSum + (ev.immediate or 0)
          if ev.closesCriticalFull then crit = crit + 1 elseif ev.closesCritical then part = part + 1 end
          if ev.potential then potSum, potN = potSum + ev.potential, potN + 1 end
        end
      end
      local s = Stats(apps)
      -- "look" = mean look-ahead part, only while it was part of the score (before 1.2.0).
      Row("applicants, " .. st.name, s, string.format(" | pick %4.1f%s | flat %d | closes critical %d full, %d partial", s.n > 0 and immSum / s.n or 0,
        potN > 0 and string.format(" look %4.1f", potSum / potN) or "", flat, crit, part))
      Add(totals.app, apps)
      -- Listings: you (each spec) looking at a group of these members
      local lm = ListingMembers(st.specs)
      local lst, lflat, lcrit, lpart = {}, 0, 0, 0
      for id in pairs(UD.specs) do
        local me = { specID = id, profile = LF.GroupProfile(id), isPlayer = true, label = "You", role = UD:GetSpec(id).role }
        local res = LF:Evaluate(lm, dk, me, settings, lvl, lvl and "title" or nil)
        if not res.roleConflict then
          lst[#lst + 1] = { score = res.score, band = res.rating.key, spec = id }
          if res.flat then lflat = lflat + 1 end
          if res.closesCriticalFull then lcrit = lcrit + 1 elseif res.closesCritical then lpart = lpart + 1 end
        end
      end
      local ls = Stats(lst)
      Row("listing, " .. st.name, ls, string.format(" | flat %d | closes critical %d full, %d partial", lflat, lcrit, lpart))
      Add(totals.lst, lst)
    end
  end
end

print("\n## Totals (all dungeons, states and levels)")
Row("applicants", Stats(totals.app))
Row("listings", Stats(totals.lst))
-- Score histogram in tens, so clustering is visible at a glance.
for _, which in ipairs({ "app", "lst" }) do
  local buckets = {}
  for i = 0, 10 do buckets[i] = 0 end
  for _, x in ipairs(totals[which]) do local b = math.floor(x.score / 10); buckets[b] = buckets[b] + 1 end
  local parts = {}
  for i = 0, 10 do parts[#parts + 1] = string.format("%d:%d", i * 10, buckets[i]) end
  print(string.format("  %-10s histogram %s", which == "app" and "applicants" or "listings", table.concat(parts, " ")))
end
