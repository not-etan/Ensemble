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
-- Boss splits (1.5.0), every read through issecretvalue and left out when hidden:
--   C_ScenarioInfo.GetCriteriaInfo(i) -> { criteriaType, assetID, completed, description }; a
--     boss is criteriaType 165 with assetID = the DungeonEncounterID (what Blizzard's objective
--     tracker shows; the same reads WarpDeplete uses in Midnight). Count from
--     C_Scenario.GetStepInfo()'s third return, else C_ScenarioInfo.GetScenarioStepInfo().numCriteria.
--   GetWorldElapsedTime(1) -> _, elapsed seconds on the key's timer.
--   ENCOUNTER_END (encounterID, name, difficulty, size, success) is the second path; a failed
--     pull (success 0) is a wipe, with the bosses' remaining health from its sixth argument
--     (encounterUnitStatus, 12.0.7+) (1.5.1).
local _, ns = ...

local H = {}
ns.History = H

H.MAX_RUNS = 500
H.MIN_SAMPLE = 3          -- runs needed on each side before a gap gets an insight row
H.MAX_GAPS_STORED = 8

local function Now() return (time and time()) or 0 end

-- m:ss for a number of seconds (whole seconds).
function H.Clock(sec)
  sec = math.floor((sec or 0) + 0.5)
  local neg = sec < 0
  sec = math.abs(sec)
  return (neg and "-" or "") .. string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

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
    for i, m in ipairs(comp) do
      -- full = "Name-Realm" (1.5.0, for past keys together; only runs saved with it count).
      -- Inside a key the game may hide names: keep the one an earlier snapshot read for the same
      -- player (same short name, else the same spot with the same class).
      local full = m.full
      if not full then
        for _, p in ipairs(run.comp or {}) do
          if p.full and m.label and m.label ~= "?" and p.name == m.label then full = p.full end
        end
        local p = (run.comp or {})[i]
        if not full and p and p.full and p.classFile == m.classFile then full = p.full end
      end
      out[#out + 1] = { specID = m.specID or 0, classFile = m.classFile, role = m.role, name = m.label,
        full = full, me = m.isPlayer or nil }
    end
    run.comp = out
  end
end

---------------------------------------------------------------------------
-- Boss splits (1.5.0, F1): when each boss died on the key's timer and how many deaths the
-- group had by then. The scenario criteria come first (a /reload mid-key still sees every
-- boss already down); ENCOUNTER_END is the second path. A hidden value is left out.
---------------------------------------------------------------------------
H.BOSS_CRITERIA_TYPE = 165
H.MAX_CRITERIA = 20
H.secretReads = 0

local function Plain(v)
  if v == nil or not issecretvalue then return v end
  local ok, secret = pcall(issecretvalue, v)
  if ok and not secret then return v end
  H.secretReads = H.secretReads + 1
  return nil
end
H.Plain = Plain

-- Seconds on the key's timer, or nil.
function H:KeyElapsed()
  local fn = rawget(_G, "GetWorldElapsedTime")
  if type(fn) ~= "function" then return nil end
  local ok, _, elapsed = pcall(fn, 1)
  elapsed = ok and Plain(elapsed) or nil
  return type(elapsed) == "number" and elapsed or nil
end

function H:DeathCount()
  local cm = rawget(_G, "C_ChallengeMode")
  if not (type(cm) == "table" and cm.GetDeathCount) then return nil end
  local ok, deaths = pcall(cm.GetDeathCount)
  deaths = ok and Plain(deaths) or nil
  return type(deaths) == "number" and deaths or nil
end

local function NumCriteria()
  local CS = rawget(_G, "C_Scenario")
  if type(CS) == "table" and CS.GetStepInfo then
    local ok, _, _, n = pcall(CS.GetStepInfo)
    n = ok and Plain(n) or nil
    if type(n) == "number" then return n end
  end
  local SI = rawget(_G, "C_ScenarioInfo")
  if type(SI) == "table" and SI.GetScenarioStepInfo then
    local ok, t = pcall(SI.GetScenarioStepInfo)
    local n = ok and type(t) == "table" and Plain(t.numCriteria) or nil
    if type(n) == "number" then return n end
  end
  return nil
end

-- The key's boss objectives: list of { enc, completed, name }, plus how many criteria were read.
-- nil, reason when the game can't be asked ("api") or nothing came back ("empty").
function H:BossCriteria()
  local SI = rawget(_G, "C_ScenarioInfo")
  if not (type(SI) == "table" and SI.GetCriteriaInfo) then return nil, "api" end
  local num = NumCriteria() or H.MAX_CRITERIA
  local out, read = {}, 0
  for i = 1, math.min(num, H.MAX_CRITERIA) do
    local ok, c = pcall(SI.GetCriteriaInfo, i)
    if not ok or type(c) ~= "table" then break end
    read = read + 1
    if Plain(c.criteriaType) == H.BOSS_CRITERIA_TYPE then
      local enc = Plain(c.assetID)
      local done = Plain(c.completed)
      local name = Plain(c.description)
      if type(enc) == "number" then
        out[#out + 1] = { enc = enc, completed = done == true, name = type(name) == "string" and name or nil }
      end
    end
  end
  if read == 0 then return nil, "empty" end
  return out, read
end

local function HasSplit(run, enc)
  for _, sp in ipairs(run.splits or {}) do if sp.enc == enc then return true end end
  return false
end

local function AddSplit(run, enc, via, name, approx)
  if type(enc) ~= "number" or HasSplit(run, enc) then return false end
  run.splits = run.splits or {}
  local boss = run.key and ns.BossCards and ns.BossCards.IndexForEncounter
    and ns.BossCards:IndexForEncounter(run.key, enc, name) or nil
  run.seq = (run.seq or 0) + 1
  run.splits[#run.splits + 1] = { enc = enc, boss = boss, t = H:KeyElapsed(), deaths = H:DeathCount(), via = via,
    approx = approx or nil, n = run.seq }
  -- By kill time when every split has one; otherwise in the order they were seen. The order is
  -- always total (seen-order breaks ties), so splits never reorder and deaths per stretch never
  -- go negative when the timer is hidden or missing (1.5.0 review, R4).
  local allTimed = true
  for _, sp in ipairs(run.splits) do if sp.t == nil then allTimed = false end end
  table.sort(run.splits, function(a, b)
    if allTimed and a.t ~= b.t then return a.t < b.t end
    return (a.n or 0) < (b.n or 0)
  end)
  return true
end

-- Record every boss the criteria say is down. approx: kills seen only now (after a /reload or
-- a loading screen), so their time is when we looked, not when the boss died.
function H:CheckSplits(approx)
  local run = ns.db and ns.db.activeRun
  if not run then return end
  local list = self:BossCriteria()
  local added = false
  for _, c in ipairs(list or {}) do
    if c.completed and AddSplit(run, c.enc, "criteria", c.name, approx) then added = true end
  end
  return added
end

function H:OnEncounterEnd(encounterID, name, success, status)
  local run = ns.db and ns.db.activeRun
  if not run then return end
  if success == 1 or success == true then
    AddSplit(run, encounterID, "encounter", type(name) == "string" and name or nil)
  elseif success == 0 or success == false then
    self:AddWipe(run, encounterID, name, status)
  end
end

-- Wipes per boss (1.5.1, F1 extra): each failed pull of a boss and the lowest health it reached,
-- from ENCOUNTER_END's sixth argument (12.0.7+: a list of { creatureID, creatureName,
-- remainingHealthPercent } for every boss unit engaged; Blizzard's 12.1.5 API docs). An
-- encounter with several bosses counts its highest remaining health (all of them must die).
-- Every value through issecretvalue; a hidden or missing health still counts the wipe.
-- Unconfirmed in game: whether the percent is 0-100 (the field's name) or 0-1; /ens verify shows
-- the last raw value so the first wipe settles it. Read as 0-100.
function H:AddWipe(run, enc, name, status)
  if type(enc) ~= "number" then return false end
  run.wipes = run.wipes or {}
  local w
  for _, x in ipairs(run.wipes) do if x.enc == enc then w = x end end
  if not w then
    w = { enc = enc, n = 0, boss = run.key and ns.BossCards and ns.BossCards.IndexForEncounter
      and ns.BossCards:IndexForEncounter(run.key, enc, type(name) == "string" and name or nil) or nil }
    run.wipes[#run.wipes + 1] = w
  end
  w.n = w.n + 1
  local hp
  status = Plain(status)
  if type(status) == "table" then
    for _, u in ipairs(status) do
      local v = type(u) == "table" and Plain(u.remainingHealthPercent) or nil
      if type(v) == "number" and v >= 0 then hp = math.max(hp or 0, v) end
    end
  end
  self.lastWipe = { raw = hp, units = type(status) == "table" and #status or nil, status = status ~= nil }
  if hp then w.best = math.min(w.best or 100, math.floor(hp + 0.5)) end
  return true
end

-- " - wiped 2x, best 12%" for a boss, or nil.
function H:WipeText(run, enc)
  for _, w in ipairs(run and run.wipes or {}) do
    if w.enc == enc and (w.n or 0) > 0 then
      return "wiped " .. w.n .. "x" .. (w.best and (", best " .. w.best .. "%") or "")
    end
  end
  return nil
end

-- A boss's name from our cards, else "Boss N".
function H:BossName(run, sp)
  local bosses = run.key and ns.BossCards and ns.BossCards:Bosses(run.key) or {}
  local b = sp.boss and bosses[sp.boss]
  return b and b.name or ("Boss " .. tostring(sp.boss or "?"))
end

-- The two fastest timed runs with splits per dungeon and key level, in one pass (History draws
-- many runs): index[dk][level] = { fastest, second }.
function H:BestIndex(runs)
  local idx = {}
  for _, r in ipairs(runs or ns.db.history or {}) do
    if r.result == "timed" and r.time and r.splits and #r.splits > 0 and r.key then
      local byLevel = idx[r.key] or {}
      idx[r.key] = byLevel
      local lvl = tonumber(r.level) or 0
      local e = byLevel[lvl] or {}
      byLevel[lvl] = e
      if not e[1] or r.time < e[1].time then e[2] = e[1]; e[1] = r
      elseif not e[2] or r.time < e[2].time then e[2] = r end
    end
  end
  return idx
end

-- The run to compare `run` with: your fastest timed run of this dungeon with splits at the
-- key's own level, else at the nearest level (the higher one on a tie), never `run` itself
-- (1.5.0 review, N5: a +15 against a +8 mostly measured the level gap). Without a level on
-- `run`, the fastest at any level. index: H:BestIndex() over the whole history, optional.
function H:BestTimed(dk, run, index)
  local byLevel = (index or self:BestIndex(ns.db.history))[dk]
  if not byLevel then return nil end
  local target = run and tonumber(run.level)
  local pick, pickLvl
  for lvl, e in pairs(byLevel) do
    local cand = (e[1] ~= run) and e[1] or e[2]
    if cand then
      if not target then
        if not pick or cand.time < pick.time then pick, pickLvl = cand, lvl end
      else
        local d, pd = math.abs(lvl - target), pickLvl and math.abs(pickLvl - target)
        if not pick or d < pd or (d == pd and lvl > pickLvl) then pick, pickLvl = cand, lvl end
      end
    end
  end
  return pick
end

-- Each split against the best timed run: { name, t, deaths (in that stretch), delta (cumulative,
-- vs the same boss in best), seg, segLoss (this stretch vs best's, only where both runs reached
-- it from the same boss) }, plus the stretch after the last boss when both runs have a time.
function H:SplitRows(run, best)
  local rows = {}
  local byEnc = {}
  if best then
    for i, sp in ipairs(best.splits or {}) do byEnc[sp.enc] = { sp = sp, prev = best.splits[i - 1] } end
  end
  local prev
  for _, sp in ipairs(run.splits or {}) do
    local row = { name = self:BossName(run, sp), t = sp.t, approx = sp.approx, enc = sp.enc }
    if sp.deaths and (not prev or prev.deaths) then row.deaths = sp.deaths - (prev and prev.deaths or 0) end
    local b = byEnc[sp.enc]
    if b and sp.t and b.sp.t then
      row.delta = sp.t - b.sp.t
      local samePrev = (prev == nil and b.prev == nil) or (prev and b.prev and prev.enc == b.prev.enc)
      if samePrev and (not prev or (prev.t and b.prev.t)) and not sp.approx and not (prev and prev.approx) then
        row.segLoss = (sp.t - (prev and prev.t or 0)) - (b.sp.t - (b.prev and b.prev.t or 0))
      end
    end
    rows[#rows + 1] = row
    prev = sp
  end
  local last = run.splits and run.splits[#run.splits]
  local bLast = best and best.splits and best.splits[#best.splits]
  if last and last.t and run.time and run.time >= last.t and not last.approx then
    local row = { name = "after the last boss", t = run.time, final = true }
    if last.deaths and run.deaths then row.deaths = run.deaths - last.deaths end
    if best and bLast and bLast.enc == last.enc and bLast.t and best.time then
      row.delta = run.time - best.time
      row.segLoss = (run.time - last.t) - (best.time - bLast.t)
    end
    rows[#rows + 1] = row
  end
  return rows
end

-- Where an over-time key lost the most time against your best timed run, or nil.
function H:WorstStretch(run, index)
  if not (run.splits and #run.splits > 0) then return nil end
  local best = self:BestTimed(run.key, run, index)
  if not best then return nil end
  local rows = self:SplitRows(run, best)
  local worst, prevName
  for _, row in ipairs(rows) do
    if row.segLoss and row.segLoss > 0 and (not worst or row.segLoss > worst.segLoss) then
      worst = row
      worst.from = prevName
    end
    prevName = row.final and prevName or row.name
  end
  if worst then worst.best = best end
  return worst
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
    started = Now(), comp = {}, splits = {},
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
  -- The last boss's objective can complete in the same moment as the key.
  if result ~= "abandoned" then pcall(self.CheckSplits, self) end
  if run.splits and #run.splits == 0 then run.splits = nil end
  if run.wipes and #run.wipes == 0 then run.wipes = nil end
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
    -- Bosses that died while the screen was loading: their time is now, not the kill.
    pcall(self.CheckSplits, self, true)
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
for _, ev in ipairs({ "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET", "PLAYER_ENTERING_WORLD",
  "SCENARIO_CRITERIA_UPDATE", "ENCOUNTER_END" }) do
  pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5, a6)
  if not ns.db or not C_ChallengeMode then return end
  if event == "SCENARIO_CRITERIA_UPDATE" then
    if ns.db.activeRun then pcall(H.CheckSplits, H) end
  elseif event == "ENCOUNTER_END" then
    if ns.db.activeRun then pcall(H.OnEncounterEnd, H, Plain(a1), Plain(a2), Plain(a5), a6) end
  elseif event == "CHALLENGE_MODE_START" then H:OnStart()
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

-- index: H:RepeatIndex(runs), optional; built here when the caller has none. bestIndex:
-- H:BestIndex(), optional, for the over-time lesson that names where the time went.
function H:Lesson(run, runs, index, bestIndex)
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
    local w = self:WorstStretch(run, bestIndex)
    if w then
      local where = w.final and ("after " .. (w.from or "the last boss"))
        or (w.from and ("between " .. w.from .. " and " .. w.name) or ("up to " .. w.name))
      return "Over time with no utility gaps: the most time went " .. where .. " (+" .. H.Clock(w.segLoss)
        .. " vs your best timed +" .. tostring(w.best.level or "?")
        .. ((w.deaths and w.deaths > 0) and (", " .. w.deaths .. " death" .. (w.deaths == 1 and "" or "s") .. " there") or "")
        .. ").", "muted"
    end
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

---------------------------------------------------------------------------
-- Past keys together (1.5.0, F2): how your recorded keys with each player went. Only runs saved
-- with realm-qualified names count (1.5.0 on), so two same-named players on different realms
-- never merge. Local data only; names never leave this file's callers' tooltips and cards.
---------------------------------------------------------------------------
H.FAILED_MODES = { "overtime", "abandoned", "abandonedHigh" }
H.FAILED_LABEL = {
  overtime = "Over time only",
  abandoned = "Over time and abandoned",
  abandonedHigh = "Over time, and abandoned at +12 and up",
}

local function NameKey(full) return type(full) == "string" and full:lower() or nil end
H.NameKey = NameKey

local pastCache
function H:PastIndex()
  local runs = ns.db and ns.db.history or {}
  local sig = #runs .. ":" .. tostring(runs[1] and runs[1].started) .. ":" .. tostring(runs[1] and runs[1].result)
  if pastCache and pastCache.runs == runs and pastCache.sig == sig then return pastCache.idx end
  local idx = {}
  local high = ns.Dungeons.HEURISTICS.FILL_STRICT_FROM or 12
  for _, run in ipairs(runs) do
    local seen = {}
    for _, m in ipairs(run.comp or {}) do
      local k = not m.me and NameKey(m.full)
      if k and not seen[k] then
        seen[k] = true
        local c = idx[k] or { timed = 0, overtime = 0, abandoned = 0, abandonedHigh = 0, full = m.full }
        idx[k] = c
        if run.result == "timed" then c.timed = c.timed + 1
        elseif run.result == "overtime" then c.overtime = c.overtime + 1
        elseif run.result == "abandoned" then
          c.abandoned = c.abandoned + 1
          if (run.level or 0) >= high then c.abandonedHigh = c.abandonedHigh + 1 end
        end
      end
    end
  end
  pastCache = { runs = runs, sig = sig, idx = idx }
  return idx
end
function H:ClearPastCache() pastCache = nil end
ns:On("HISTORY_CHANGED", function() pastCache = nil end)

-- Keys with one player ("Name-Realm"), or nil when none.
function H:With(full)
  local k = NameKey(full)
  return k and self:PastIndex()[k] or nil
end

function H:FailedMode(settings)
  local pk = (settings or (ns.db and ns.db.settings) or {}).pastKeys or {}
  local m = pk.failed
  return H.FAILED_LABEL[m] and m or "overtime"
end

-- Failed keys with them under the setting.
function H:FailedCount(c, settings)
  if not c then return 0 end
  local mode = self:FailedMode(settings)
  if mode == "abandoned" then return c.overtime + c.abandoned end
  if mode == "abandonedHigh" then return c.overtime + c.abandonedHigh end
  return c.overtime
end

-- "timed": you've timed keys with them and they aren't "failed"; "failed": more failed keys
-- (per the setting) than timed ones, so one bad key never outweighs good ones; nil otherwise.
function H:Standing(full, settings)
  local c = self:With(full)
  if not c then return nil, nil end
  local failed = self:FailedCount(c, settings)
  if failed > c.timed then return "failed", c end
  if c.timed > 0 then return "timed", c end
  return nil, c
end

-- "With you: 2 timed, 1 over time" for one player, or nil when you share no key.
function H:WithText(c)
  if not c then return nil end
  local parts = {}
  if c.timed > 0 then parts[#parts + 1] = c.timed .. " timed" end
  if c.overtime > 0 then parts[#parts + 1] = c.overtime .. " over time" end
  if c.abandoned > 0 then parts[#parts + 1] = c.abandoned .. " abandoned" end
  if #parts == 0 then return nil end
  return table.concat(parts, ", ")
end

-- Points per player at a strictness level (DD.HEURISTICS.PAST_KEYS_POINTS).
function H:PastPoints(level)
  local t = ns.Dungeons.HEURISTICS.PAST_KEYS_POINTS or {}
  return t[level] or 0
end

-- Runs that can count (saved with full names), for /ens verify: counts only, no names.
function H:PastStats()
  local runs, withNames = 0, 0
  for _, run in ipairs(ns.db and ns.db.history or {}) do
    runs = runs + 1
    for _, m in ipairs(run.comp or {}) do if m.full and not m.me then withNames = withNames + 1; break end end
  end
  local players = 0
  for _ in pairs(self:PastIndex()) do players = players + 1 end
  return runs, withNames, players
end

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
