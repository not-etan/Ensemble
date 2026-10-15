-- Keystone Command / ListingFit.lua
-- "Your fit" for groups you could apply to: for a Group Finder search result, what YOU
-- would add to that group, what it may already have (talents can't be seen), and what it
-- would still be missing after you join. Pure logic, no frames; FinderSearch.lua draws it.
--
-- Uncertainty model (other players' talents are invisible):
--   * a need only an OPTIONAL talent covers is "maybe" (could already be covered)
--   * your own talents ARE visible: "What you'd add" counts a talent ability you know as yours
--     for sure
-- The rating is the same PICK rating as applicant ratings: how strong an applicant you are
-- for this group's open slot, against every other spec of your role (same bands, same "no
-- real difference" guard, same critical-gap rule). It rates you on equal terms with those
-- specs (1.2.1): everyone, you included, gets the same assumed profile as group members
-- (GroupProfile: Bloodlust assumed, talents uncertain, as a host would see you), so your
-- known talents never lift you above the best spec of your role. "Is the group OK after you
-- join?" is the separate res.groupAfter status, never a score. Affixes count only when the key
-- level can be read from the title.
--
-- API (long-standing, all pcall-guarded; /kc verify reports which are present):
--   C_LFGList.GetSearchResultInfo(resultID) -> { activityIDs | activityID, numMembers, isDelisted }
--   C_LFGList.GetSearchResultPlayerInfo(resultID, i) -> { classFilename, specName, assignedRole, specID? }
--   C_LFGList.GetSearchResultMemberInfo(resultID, i) -> role, classFile, className, specName (older;
--     its deprecated fallback was removed in 12.1.5, so live clients use PlayerInfo. Kept as a
--     guarded fallback: it costs nothing and covers a client that still has it.)
--   GetSpecializationInfoByID(specID) -> localized spec name, used to map names to spec IDs
--   IsPlayerSpell(spellID) -> whether you know a talent ability

local _, ns = ...

local Fit = ns.ApplicantFit
local LF = {}
ns.ListingFit = LF

local A, UD, DD

local function Init() A, UD, DD = ns.Analysis, ns.UD, ns.Dungeons end

LF.ASSUMED_LEVEL = 10   -- last resort when nothing else gives a level

---------------------------------------------------------------------------
-- Key level: hosts nearly always put it in the listing title ("+15 timing"). Titles may be
-- protected in some clients (a "secret" value addons can't read); any error or protected
-- value simply means the title can't be used and the fallback setting applies.
---------------------------------------------------------------------------
local function ParseLevel(text)
  local s = text:lower()
  -- "+15", "+ 15", "+15-17" (first number); not "+2k" or "+2.5k" (ratings).
  for num, after in s:gmatch("%+%s*(%d%d?)([^%s]?)") do
    if not after:find("^[k%.%d]") then return tonumber(num) end
  end
  -- "15 TSE", "15-16 ..." at the very start; "key 15", "15 key", "lvl 15", "level 15".
  local n = s:match("^%s*(%d%d?)[%s%-/]") or s:match("^%s*(%d%d?)$")
    or s:match("key%s*(%d%d?)") or s:match("(%d%d?)%s*key") or s:match("lvl%s*(%d%d?)") or s:match("level%s*(%d%d?)")
  return tonumber(n)
end
LF.ParseLevel = ParseLevel

function LF:LevelFromTitle(info)
  local name = info and info.name
  if name == nil then return nil end
  if issecretvalue then
    local okS, secret = pcall(issecretvalue, name)
    if not okS or secret then return nil, "protected" end
  end
  if type(name) ~= "string" then return nil, "unreadable" end
  -- Player-written text can arrive as an encoded "|K...|k" token that only the game's own
  -- frames can display; there is nothing to read in it.
  if name:find("|K", 1, true) then return nil, "encoded" end
  local ok, n = pcall(ParseLevel, name)
  if not ok then return nil, "unreadable" end
  if n and n >= 2 and n <= 30 then return n end
  return nil
end

-- Level for a listing: from its title, or nil. Without a readable level the listing is
-- judged on the dungeon's own needs only (affixes depend on the level, so guessing one
-- would count the wrong affixes). In 12.1 listing titles are protected from addons.
function LF:LevelFor(info)
  local n = self:LevelFromTitle(info)
  if n then return n, "title" end
  return nil, "none"
end

-- Short chip labels per need (badge style "What you'd add").
LF.SHORT = {
  interrupt = "Kick", battle_rez = "Brez", bloodlust = "Lust", dispel_magic = "Magic",
  dispel_curse = "Curse", dispel_poison = "Poison", dispel_disease = "Disease", dispel_bleed = "Bleed",
  aoe_stop = "AoE stop", stop = "Stop", purge = "Purge", soothe = "Soothe", knockback = "Knockback",
  root = "Root", external_defensive = "External", group_defensive = "Defensive", freedom = "Freedom",
  movement = "Speed", group_stealth = "Stealth",
}

---------------------------------------------------------------------------
-- Spec ID from a localized spec name (search results may give only the name).
---------------------------------------------------------------------------
local specByName
local function SpecFromName(classFile, specName)
  if not (classFile and specName) then return nil end
  Init()
  if not specByName then
    specByName = {}
    for id in pairs(UD.specs) do
      local name, _, _, cls = ns.API.GetSpecInfoByID(id)
      if name and cls then
        specByName[cls] = specByName[cls] or {}
        specByName[cls][name] = id
      end
    end
  end
  return specByName[classFile] and specByName[classFile][specName] or nil
end
LF.SpecFromName = SpecFromName

---------------------------------------------------------------------------
-- Reading a search result
---------------------------------------------------------------------------
local function ResultInfo(resultID)
  if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return nil end
  local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
  if ok and type(info) == "table" then return info end
  return nil
end

function LF:DungeonFor(resultID, info)
  Init()
  info = info or ResultInfo(resultID)
  if not info then return nil end
  local ids = info.activityIDs or (info.activityID and { info.activityID }) or {}
  for _, id in ipairs(ids) do
    local act
    if C_LFGList.GetActivityInfoTable then
      local ok, t = pcall(C_LFGList.GetActivityInfoTable, id)
      if ok then act = t end
    end
    local key = DD:KeyForActivity(id, act)
    if key then return key end
  end
  return nil
end

local VALID_ROLE = { TANK = true, HEALER = true, DAMAGER = true }

-- Needs assumed to be brought whenever a spec can bring them, even through a talent, pet or
-- condition: nobody who can Bloodlust leaves it at home. (Listing fit only; the Builder and
-- Live checks keep their usual caution.)
LF.ASSUMED_CAPS = { bloodlust = true }

local function MakeAssumed(profile)
  for cap in pairs(LF.ASSUMED_CAPS) do
    for _, e in ipairs(profile.caps[cap] or {}) do
      if e.talent or e.pet or e.conditional or e.verify or e.long then
        e.talent, e.pet, e.conditional, e.verify, e.long = nil, nil, nil, nil, nil
        e.assumed = true
      end
    end
  end
  return profile
end

local assumedProfiles = {}
local function GroupProfile(specID)
  if not specID then return nil end
  local p = assumedProfiles[specID]
  if p == nil then
    local base = UD:GetSpec(specID)
    p = base and MakeAssumed(ns.Util.DeepCopy(base)) or false
    assumedProfiles[specID] = p
  end
  return p or nil
end
LF.GroupProfile = GroupProfile

function LF:Members(resultID, info)
  Init()
  info = info or ResultInfo(resultID)
  if not info then return nil end
  local n = info.numMembers or 0
  local out = {}
  for i = 1, n do
    local m
    if C_LFGList.GetSearchResultPlayerInfo then
      local ok, p = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, i)
      if ok and type(p) == "table" then
        local cls = p.classFilename or p.classFile
        m = { classFile = cls, role = p.assignedRole,
              specID = (type(p.specID) == "number" and p.specID > 0 and p.specID) or SpecFromName(cls, p.specName) }
      end
    end
    if not m and C_LFGList.GetSearchResultMemberInfo then
      local ok, role, cls, _, specName = pcall(C_LFGList.GetSearchResultMemberInfo, resultID, i)
      if ok and cls then m = { classFile = cls, role = role, specID = SpecFromName(cls, specName) } end
    end
    if m and m.classFile then
      if m.specID and not UD:GetSpec(m.specID) then m.specID = nil end
      if not VALID_ROLE[m.role or ""] then m.role = nil end
      m.profile = GroupProfile(m.specID)
      out[#out + 1] = m
    end
  end
  return out
end

---------------------------------------------------------------------------
-- You: your spec, with the talents you actually have counted as certain.
---------------------------------------------------------------------------
local function KnowsSpell(id)
  if not id then return nil end
  local fn = IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
  if not fn then return nil end
  local ok, known = pcall(fn, id)
  if ok then return known and true or false end
  return nil
end

-- Copy of the spec profile where talent abilities you know are no longer "maybe". Names with
-- a qualifier in brackets ("Paralysis (Pressure Points)") depend on a second talent, so they
-- are left as they are; an ability you don't seem to know is never removed (the check can
-- miss renamed or overridden spells), it just stays a talent.
function LF:PlayerProfile(specID)
  Init()
  local base = specID and UD:GetSpec(specID)
  if not base then return nil end
  local copy = ns.Util.DeepCopy(base)
  for _, list in pairs(copy.caps) do
    for _, e in ipairs(list) do
      if e.talent and not e.pet and not tostring(e.name):find("[%(/]") and KnowsSpell(UD:SpellID(e.name)) then
        e.talent, e.core, e.owned = nil, nil, true
      end
    end
  end
  return MakeAssumed(copy)
end

-- Cached: every redraw of a search-result row asks for it. Cleared with the result cache
-- when your spec or talents change.
local playerMember
function LF:PlayerMember()
  local specID = ns.API.GetPlayerSpecID()
  if playerMember and playerMember.specID == specID then return playerMember end
  local profile = self:PlayerProfile(specID)
  if not profile then return nil end
  playerMember = { specID = specID, profile = profile, isPlayer = true, label = "You", role = profile.role }
  return playerMember
end

---------------------------------------------------------------------------
-- Evaluation
---------------------------------------------------------------------------
local function SoftOnly(row)
  -- True when the row's providers all depend on an optional talent (so it may be covered).
  local any = false
  for _, p in ipairs(row.providers or {}) do
    if not (p.entry and p.entry.talent and not p.entry.core) then return false end
    any = true
  end
  return any
end

local SEV_RANK = { critical = 1, high = 2, medium = 3, low = 4 }
local function RowOrder(a, b)
  local x, y = SEV_RANK[a.severity or "low"] or 5, SEV_RANK[b.severity or "low"] or 5
  if x ~= y then return x < y end
  return a.label < b.label
end

-- Whether you are one of the row's providers; `sure`: through something you certainly have
-- (not an optional talent you may lack).
local function YouProvide(row, sure)
  for _, p in ipairs(row.providers or {}) do
    if p.member and p.member.isPlayer then
      if not sure then return true end
      if not (p.entry and p.entry.talent and not p.entry.core) then return true end
    end
  end
  return false
end

-- Best/worst gain any spec of `role` could bring to these members, and the critical-gap floors
-- (Fit.CritFloors: full and partial, as 0-1 positions). Every spec is rated with the same
-- assumed profile as group members (GroupProfile), so the comparison is on equal terms.
-- Cached: the same group appears on every refresh while you scroll; cleared with each new search.
local gainCache = {}
local function RoleRange(members, sig, dungeonKey, settings, role, basePenalty, opts, level, baseCritical)
  local key = sig .. "|" .. role
  local c = gainCache[key]
  if c then return c[1], c[2], c[3], c[4] end
  local best, worst = 0, nil
  local list, gains = {}, {}
  for i, m in ipairs(members) do list[i] = m end
  for _, specID in ipairs(UD:SpecsForRole(role)) do
    list[#members + 1] = { specID = specID, profile = GroupProfile(specID) }
    local r = A:Analyze(list, dungeonKey, settings, opts)
    local g = basePenalty - A:Penalty(r, level)
    if g > best then best = g end
    if not worst or g < worst then worst = g end
    local cc = Fit.CriticalClose(baseCritical, r)
    gains[#gains + 1] = { gain = g, kind = cc and cc.kind or nil }
  end
  worst = math.min(worst or 0, best)
  local fullFloor, partialFloor = Fit.CritFloors(gains, best, worst)
  gainCache[key] = { best, worst, fullFloor, partialFloor }
  return best, worst, fullFloor, partialFloor
end

local function MembersSig(members)
  local t = {}
  for _, m in ipairs(members) do t[#t + 1] = tostring(m.specID or m.classFile) .. ":" .. tostring(m.role) end
  table.sort(t)
  return table.concat(t, ",")
end

-- Evaluate a group (`members`, list of { specID|classFile, role }) in `dungeonKey` for `me`.
-- Returns { rating, score, roleConflict, adds = {row...}, maybeAdds, maybe, still, ... }.
function LF:Evaluate(members, dungeonKey, me, settings, level, levelSource)
  Init()
  settings = settings or ns.db.settings
  local H = DD.HEURISTICS
  local opts = level and { keyLevel = level } or { noAffixes = true }
  local base = A:Analyze(members, dungeonKey, settings, opts)
  local withMe = {}
  for i, m in ipairs(members) do withMe[i] = m end
  withMe[#withMe + 1] = me
  local after = A:Analyze(withMe, dungeonKey, settings, opts)
  local bp = A:Penalty(base, level)
  -- The rating rates you like the specs you're compared with: the group-member profile
  -- (talents uncertain, Bloodlust assumed). "What you'd add" below keeps your known talents.
  local rateProfile = (me.specID and GroupProfile(me.specID)) or me.profile
  local afterRate = after
  if rateProfile ~= me.profile then
    local rated = {}
    for i, m in ipairs(members) do rated[i] = m end
    rated[#rated + 1] = { specID = me.specID, profile = rateProfile, role = me.role, label = me.label }
    afterRate = A:Analyze(rated, dungeonKey, settings, opts)
  end
  local gain = bp - A:Penalty(afterRate, level)

  local res = { dungeonKey = dungeonKey, level = level, levelSource = level and (levelSource or "title") or "none", gain = gain,
                adds = {}, maybeAdds = {}, maybe = {}, still = {}, members = members }
  local open = Fit:OpenRoles(members)
  local role = me.role or (me.profile and me.profile.role) or "DAMAGER"
  res.role = role
  res.roleConflict = (open[role] or 0) <= 0

  local baseCritical = Fit.CriticalGaps(base)
  local best, worst, fullFloor, partialFloor = RoleRange(members, dungeonKey .. "|" .. tostring(level) .. "|" .. MembersSig(members),
    dungeonKey, settings, role, bp, opts, level, baseCritical)
  res.best, res.worst = best, worst
  local rel = Fit.Relative(gain, best, worst)
  res.flat = (rel == nil) and not res.roleConflict
  res.rawImmediate = rel and math.floor(rel * 100 + 0.5) or nil
  -- Critical-gap rule, as for applicants: a full close never rates below a spec that doesn't
  -- fully close one; a partial close (weak source only) is floored at the partial share.
  res.critClose = Fit.CriticalClose(baseCritical, afterRate)
  res.closesCritical = res.critClose ~= nil
  res.closesCriticalFull = res.critClose ~= nil and res.critClose.kind == "full"
  local score = res.flat and (H.FIT_FLAT_SCORE or 70) or (res.rawImmediate or 0)
  if rel and res.critClose and not res.roleConflict then
    local floorRel = res.closesCriticalFull and fullFloor or partialFloor
    res.critFloor = floorRel and math.floor(floorRel * 100 + 0.5) or nil
    if res.critFloor and score < res.critFloor then score, res.critFloored = res.critFloor, res.critClose.kind end
  end
  if res.roleConflict then score = math.min(score, 15) end
  res.score = score
  res.rating = Fit:RatingFor(score, res.roleConflict)

  -- Need by need: before (the group) vs after (the group + you). A need the dungeon asks
  -- for that only OPTIONAL talents cover counts as uncertain even when the Readiness check
  -- calls it OK (other players' talents can't be seen).
  local R0, R1 = A:Readiness(base, settings), A:Readiness(after, settings)
  local RR = A.READY_RANK
  for cap, row0 in pairs(R0.rows) do
    local row1 = R1.rows[cap]
    local s0, s1 = row0.status, row1 and row1.status
    local dungeonAsks = row0.items and #row0.items > 0
    local soft0 = SoftOnly(row0) and dungeonAsks
    local soft1 = row1 and SoftOnly(row1) and dungeonAsks
    if row1 and (s0 == "missing" or s0 == "thin" or (s0 == "ok" and soft0)) then
      local entry = { cap = cap, label = row0.label, short = self.SHORT[cap] or row0.label,
                      severity = row0.severity or (row0.items[1] and row0.items[1].req.severity), items = row0.items }
      local sure = YouProvide(row1, true)
      local more = #(row1.providers or {}) > #(row0.providers or {})
      if sure and (RR[s1] > RR[s0] or more or soft0) then
        if soft0 and s0 ~= "missing" then
          entry.who = row0.providers
          res.maybeAdds[#res.maybeAdds + 1] = entry      -- you'd add it; they might already have it
        else
          entry.partial = (s1 == "thin")
          res.adds[#res.adds + 1] = entry
        end
      elseif s1 == "missing" then
        res.still[#res.still + 1] = entry
      elseif s1 == "thin" or soft1 then
        entry.who = row1.providers
        entry.talentOnly = soft1 or SoftOnly(row1)
        res.maybe[#res.maybe + 1] = entry
      end
    end
  end
  for _, l in ipairs({ res.adds, res.maybeAdds, res.maybe, res.still }) do table.sort(l, RowOrder) end
  -- "Group after you:" plain status: what is still missing once you join (with sources, in
  -- the tooltip), and how many needs stay thin or rest on a talent nobody can see.
  local thin, unsure = 0, 0
  for _, e in ipairs(res.maybe) do if e.talentOnly then unsure = unsure + 1 else thin = thin + 1 end end
  res.groupAfter = {
    status = (#res.still > 0 and "missing") or ((thin + unsure) > 0 and "thin") or "ready",
    missing = res.still, thin = thin, unsure = unsure,
  }
  return res
end

-- Per-result cache: a search result is re-drawn on every scroll; members rarely change.
local cache = {}
function LF:ClearCache() cache = {}; gainCache = {}; playerMember = nil end

-- Everything needed to evaluate a result, plus its cache signature (cheap: no analysis).
local function Prepare(self, resultID)
  if not resultID then return nil end
  local info = ResultInfo(resultID)
  if not info or info.isDelisted then return nil end
  local dungeonKey = self:DungeonFor(resultID, info)
  if not dungeonKey then return nil end
  local members = self:Members(resultID, info)
  if not members then return nil end
  local me = self:PlayerMember()
  if not me then return nil end
  local level, source = self:LevelFor(info)
  return members, dungeonKey, me, dungeonKey .. "|" .. MembersSig(members) .. "|" .. tostring(me.specID) .. "|" .. tostring(level),
    level, source
end

-- The cached answer if it is still current, else nil (never computes).
function LF:Cached(resultID)
  Init()
  local c = cache[resultID]
  if not c then return nil end
  local _, _, _, sig = Prepare(self, resultID)
  if sig and c.sig == sig then return c.res end
  return nil
end

function LF:ForResult(resultID)
  Init()
  local members, dungeonKey, me, sig, level, source = Prepare(self, resultID)
  if not sig then return nil end
  local c = cache[resultID]
  if c and c.sig == sig then return c.res end
  local res = self:Evaluate(members, dungeonKey, me, ns.db.settings, level, source)
  res.resultID = resultID
  cache[resultID] = { sig = sig, res = res }
  return res
end

-- Clear on anything that changes the answer: your spec or talents, settings, weekly affixes.
-- (The dungeon picked in the addon doesn't matter here: each listing names its own.)
local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "LFG_LIST_SEARCH_RESULTS_RECEIVED" }) do
  pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event, unit)
  if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then cache = {}; gainCache = {}
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return  -- a party member's spec
  else LF:ClearCache() end
end)
if ns.On then
  ns:On("SETTINGS_CHANGED", function() LF:ClearCache() end)
  ns:On("AFFIXES_CHANGED", function() LF:ClearCache() end)
end
