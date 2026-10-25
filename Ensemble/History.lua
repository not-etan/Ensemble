-- Ensemble / History.lua
-- Run history: every Mythic+ key you start is recorded locally (dungeon, level, affixes,
-- the group's specs and the gaps it had) and finished as timed, over time or abandoned.
-- Insights compare how often you time keys with and without each gap.
--
-- In-client APIs (all pcall-guarded; long-standing retail, confirmed by /ens verify):
--   C_ChallengeMode.GetActiveChallengeMapID(), C_ChallengeMode.GetActiveKeystoneInfo()
--     -> level, affixIDs, wasCharged
--   C_ChallengeMode.GetChallengeCompletionInfo() -> { mapChallengeModeID, level, time (ms),
--     onTime, keystoneUpgradeLevels, practiceRun, ... }  (older: GetCompletionInfo() returns)
--   C_ChallengeMode.GetDeathCount() -> deaths, timeLost
--   C_ChallengeMode.GetMapUIInfo(mapID) -> name, id, timeLimit (s), texture
local _, ns = ...

local H = {}
ns.History = H

H.MAX_RUNS = 500
H.MIN_SAMPLE = 3          -- runs needed on each side before a gap gets an insight row
H.MAX_GAPS_STORED = 8

local function Now() return (time and time()) or 0 end

local function ActiveMap()
  if not (C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID) then return nil end
  local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
  return ok and id or nil
end

local function Enabled() return ns.db and ns.db.settings.history ~= false end

-- Group snapshot from the live tracker: { specID|0, classFile, role, name }.
function H:Snapshot()
  local run = ns.db and ns.db.activeRun
  if not run or not ns.Tracker.enabled then return end
  local comp = ns.Tracker:GetComp()
  if #comp == 0 then return end
  local known = 0
  for _, m in ipairs(comp) do if m.specID then known = known + 1 end end
  local prevKnown = 0
  for _, m in ipairs(run.comp or {}) do if m.specID and m.specID ~= 0 then prevKnown = prevKnown + 1 end end
  if not run.comp or #comp > #run.comp or known >= prevKnown then
    local out = {}
    for _, m in ipairs(comp) do
      out[#out + 1] = { specID = m.specID or 0, classFile = m.classFile, role = m.role, name = m.label }
    end
    run.comp = out
  end
end

function H:OnStart()
  if not Enabled() then return end
  local mapID = ActiveMap()
  local key = mapID and ns.Dungeons:KeyForChallengeMap(mapID)
  local level, affixes
  if C_ChallengeMode.GetActiveKeystoneInfo then
    local ok, l, a = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
    if ok then level, affixes = l, a end
  end
  ns.db.activeRun = {
    mapID = mapID, key = key, level = level, affixes = type(affixes) == "table" and affixes or {},
    started = Now(), comp = {},
  }
  ns.Tracker:Acquire("history")
  self:Snapshot()
  -- Specs come in through inspect over the first seconds of the countdown.
  C_Timer.After(5, function() H:Snapshot() end)
  C_Timer.After(15, function() H:Snapshot() end)
end

-- Gaps the group had for this key, judged by the addon's current rules at record time.
local function Gaps(run)
  local members = {}
  for _, m in ipairs(run.comp or {}) do
    members[#members + 1] = { specID = (m.specID ~= 0) and m.specID or nil, classFile = m.classFile, role = m.role, label = m.name }
  end
  if #members == 0 then return {} end
  local ids = (run.affixes and #run.affixes > 0) and run.affixes or nil
  local r = ns.Analysis:Analyze(members, run.key, ns.db.settings, { keyLevel = run.level, affixIDs = ids })
  local out = {}
  for _, e in ipairs(ns.Analysis:StillNeeded(r)) do
    if #out >= H.MAX_GAPS_STORED then break end
    local src = e.sources and e.sources[1] and e.sources[1].source
    out[#out + 1] = { title = e.title, status = e.status, key = e.keys[1], severity = e.severity,
      source = src and ((src:match("^([^,(]+)") or src):gsub("%s+$", "")) or nil }
  end
  return out
end

function H:Finish(result, info)
  local run = ns.db and ns.db.activeRun
  if not run then return end
  self:Snapshot()
  ns.db.activeRun = nil
  ns.Tracker:Release("history")
  if info and info.practiceRun then return end
  run.result = result
  run.ended = Now()
  if info then
    run.level = info.level or run.level
    run.time = info.time and math.floor(info.time / 1000 + 0.5) or nil
    run.upgrade = info.keystoneUpgradeLevels
    if info.mapID and not run.key then run.mapID = info.mapID; run.key = ns.Dungeons:KeyForChallengeMap(info.mapID) end
  end
  if C_ChallengeMode.GetDeathCount then
    local ok, deaths = pcall(C_ChallengeMode.GetDeathCount)
    if ok and type(deaths) == "number" then run.deaths = deaths end
  end
  if run.mapID and C_ChallengeMode.GetMapUIInfo then
    local ok, _, _, limit = pcall(C_ChallengeMode.GetMapUIInfo, run.mapID)
    if ok and type(limit) == "number" then run.timeLimit = limit end
  end
  local okG, gaps = pcall(Gaps, run)
  run.gaps = okG and gaps or {}
  ns.db.history = ns.db.history or {}
  table.insert(ns.db.history, 1, run)
  while #ns.db.history > H.MAX_RUNS do table.remove(ns.db.history) end
  ns:Fire("HISTORY_CHANGED")
end

local function CompletionInfo()
  if C_ChallengeMode.GetChallengeCompletionInfo then
    local ok, t = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
    if ok and type(t) == "table" then
      return { mapID = t.mapChallengeModeID, level = t.level, time = t.time, onTime = t.onTime,
               keystoneUpgradeLevels = t.keystoneUpgradeLevels, practiceRun = t.practiceRun }
    end
  end
  if C_ChallengeMode.GetCompletionInfo then
    local ok, mapID, level, t, onTime, upgrade, practice = pcall(C_ChallengeMode.GetCompletionInfo)
    if ok then
      return { mapID = mapID, level = level, time = t, onTime = onTime, keystoneUpgradeLevels = upgrade, practiceRun = practice }
    end
  end
  return nil
end

function H:OnCompleted()
  if not (ns.db and ns.db.activeRun) then return end
  local info = CompletionInfo()
  local timed = info and info.onTime
  self:Finish(timed and "timed" or "overtime", info)
end

-- /reload inside a key keeps the run; leaving the dungeon without finishing abandons it.
-- Still inside a Mythic Keystone instance (difficulty 8), even if the key's state hasn't
-- arrived yet after a loading screen.
local function InKeystoneInstance()
  if not GetInstanceInfo then return false end
  local ok, _, instanceType, difficultyID = pcall(GetInstanceInfo)
  return ok and instanceType == "party" and difficultyID == 8
end

function H:OnEnteringWorld(attempt)
  local run = ns.db and ns.db.activeRun
  if not run then return end
  if ActiveMap() then
    ns.Tracker:Acquire("history")
    return
  end
  if InKeystoneInstance() then
    -- Key state not loaded yet: look again shortly rather than abandoning a live run.
    if (attempt or 1) < 4 then C_Timer.After(5, function() H:OnEnteringWorld((attempt or 1) + 1) end) end
    ns.Tracker:Acquire("history")
    return
  end
  self:Finish("abandoned")
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET", "PLAYER_ENTERING_WORLD" }) do
  pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event)
  if not ns.db or not C_ChallengeMode then return end
  if event == "CHALLENGE_MODE_START" then H:OnStart()
  elseif event == "CHALLENGE_MODE_COMPLETED" then H:OnCompleted()
  elseif event == "CHALLENGE_MODE_RESET" then H:Finish("abandoned")
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Give the client a moment after a loading screen before deciding the key is over.
    C_Timer.After(3, function() H:OnEnteringWorld() end)
  end
end)

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
function H:Runs(dungeonKey)
  local out = {}
  for _, run in ipairs(ns.db.history or {}) do
    if not dungeonKey or run.key == dungeonKey then out[#out + 1] = run end
  end
  return out
end

-- One line on what likely mattered in a run, from its own gaps and your other keys in the
-- same dungeon. Returns text, tone ("good" / "warn" / "muted").
local SEV = { critical = 1, high = 2, medium = 3, low = 4 }
local function RepeatKey(dk, g) return tostring(dk) .. "\0" .. tostring(g.title) .. "\0" .. tostring(g.status) end

-- How many over-time keys in each dungeon had each gap, counted once per run: one pass over
-- the runs, so drawing every lesson costs O(runs) instead of O(runs^2) (1.5.0, C2).
function H:RepeatIndex(runs)
  local idx = { counts = {}, has = {} }
  for _, run in ipairs(runs or {}) do
    if run.result == "overtime" then
      idx.has[run] = true
      local seen = {}
      for _, g in ipairs(run.gaps or {}) do
        local k = RepeatKey(run.key, g)
        if not seen[k] then seen[k] = true; idx.counts[k] = (idx.counts[k] or 0) + 1 end
      end
    end
  end
  return idx
end

-- index: H:RepeatIndex(runs), optional; built here when the caller has none.
function H:Lesson(run, runs, index)
  if run.result == "abandoned" then return nil end
  local gaps = {}
  for _, g in ipairs(run.gaps or {}) do gaps[#gaps + 1] = g end
  table.sort(gaps, function(a, b)
    if (a.status == "missing") ~= (b.status == "missing") then return a.status == "missing" end
    local x, y = SEV[a.severity] or 9, SEV[b.severity] or 9
    if x ~= y then return x < y end
    return tostring(a.title) < tostring(b.title)
  end)
  local function Describe(g)
    return (g.status == "missing" and "no " or "thin ") .. g.title
      .. (g.source and (" (" .. g.source .. (g.severity and (", " .. g.severity) or "") .. ")") or "")
  end
  if run.result == "timed" then
    if #gaps == 0 then return "Timed with nothing missing.", "good" end
    return "Timed despite " .. Describe(gaps[1]) .. ((#gaps > 1) and (" and " .. (#gaps - 1) .. " other gap" .. (#gaps > 2 and "s" or "")) or "") .. ".", "good"
  end
  -- Over time
  if #gaps == 0 then
    return "Over time with no utility gaps: the time went elsewhere" .. (run.deaths and run.deaths > 0 and (" (" .. run.deaths .. " deaths)") or "") .. ".", "muted"
  end
  local lead = gaps[1]
  local text = "Over time with " .. Describe(lead)
  if gaps[2] then text = text .. " and " .. Describe(gaps[2]) end
  -- Pattern: the same gap in your other over-time keys in this dungeon.
  -- Other runs only: when the run itself is in the list, it's one of the index's count.
  index = index or self:RepeatIndex(runs)
  local repeats = (index.counts[RepeatKey(run.key, lead)] or 0) - (index.has[run] and 1 or 0)
  if repeats > 0 then
    text = text .. ". Also " .. (lead.status == "missing" and "missing" or "thin") .. " in " .. repeats .. " other over-time key" .. (repeats > 1 and "s" or "") .. " here"
  end
  return text .. ".", "warn"
end

function H:Clear() ns.db.history = {}; ns:Fire("HISTORY_CHANGED") end

-- { total, finished, timed, abandoned, rate, gaps = { {title, withN, withTimed, withoutN, withoutTimed,
--   rateWith, rateWithout, delta} }, dungeons = { {key, n, timed, rate, avgLevel} } }
function H:Insights(runs)
  local s = { total = #runs, finished = 0, timed = 0, abandoned = 0, gaps = {}, dungeons = {} }
  local finished = {}
  for _, run in ipairs(runs) do
    if run.result == "abandoned" then s.abandoned = s.abandoned + 1
    else
      finished[#finished + 1] = run
      if run.result == "timed" then s.timed = s.timed + 1 end
    end
  end
  s.finished = #finished
  s.rate = #finished > 0 and s.timed / #finished or nil

  -- Gap correlation.
  local titles, seen = {}, {}
  for _, run in ipairs(finished) do
    for _, g in ipairs(run.gaps or {}) do
      if not seen[g.title] then seen[g.title] = true; titles[#titles + 1] = g.title end
    end
  end
  for _, title in ipairs(titles) do
    local wn, wt, on, ot = 0, 0, 0, 0
    for _, run in ipairs(finished) do
      local has = false
      for _, g in ipairs(run.gaps or {}) do if g.title == title then has = true end end
      local timed = run.result == "timed" and 1 or 0
      if has then wn, wt = wn + 1, wt + timed else on, ot = on + 1, ot + timed end
    end
    if wn >= H.MIN_SAMPLE and on >= H.MIN_SAMPLE then
      local rw, ro = wt / wn, ot / on
      s.gaps[#s.gaps + 1] = { title = title, withN = wn, withTimed = wt, withoutN = on, withoutTimed = ot,
        rateWith = rw, rateWithout = ro, delta = ro - rw }
    end
  end
  table.sort(s.gaps, function(a, b)
    if math.abs(a.delta - b.delta) > 1e-9 then return a.delta > b.delta end
    return a.title < b.title
  end)

  -- Per dungeon.
  local byKey = {}
  for _, run in ipairs(finished) do
    local k = run.key or "?"
    local d = byKey[k]
    if not d then d = { key = k, n = 0, timed = 0, levels = 0 }; byKey[k] = d; s.dungeons[#s.dungeons + 1] = d end
    d.n = d.n + 1
    if run.result == "timed" then d.timed = d.timed + 1 end
    d.levels = d.levels + (run.level or 0)
  end
  for _, d in ipairs(s.dungeons) do d.rate = d.timed / d.n; d.avgLevel = d.levels / d.n end
  table.sort(s.dungeons, function(a, b) if a.n ~= b.n then return a.n > b.n end return tostring(a.key) < tostring(b.key) end)
  return s
end
