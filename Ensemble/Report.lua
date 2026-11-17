-- Ensemble / Report.lua
-- /ens report: the one command for "something looks off" (1.6.5: /ens verify was folded in).
-- One copyable block with everything a fix needs that a player wouldn't think to mention:
-- addon version, client build and language, what was on screen right now (tab, sizes and
-- scale, dungeon, key level and where each came from, the group's specs, hosting state, the
-- boss window), every problem the checks found, the addon's own recent Lua errors with the tab
-- open at the time, its recent activity, settings changed from the defaults, addons that share
-- the same screens, and the checks' facts. Never player names.
-- Read-only: building a report changes nothing.
--
-- Error log: the addon keeps the last few Lua errors that came from its own files (found by
-- "AddOns/Ensemble" in the message or stack), with the time and version, in
-- SavedVariables (db.errors). It chains Blizzard's error handler (geterrorhandler /
-- seterrorhandler): every error still goes to the previous handler unchanged, and if
-- another addon owns the handler, or the client refuses the change, nothing breaks; the
-- log just stays empty. If BugGrabber is installed its records are read as well.

local _, ns = ...

local Report = {}
ns.Report = Report

local MAX_ERRORS = 10
local pending = {}          -- errors caught before SavedVariables are ready
Report.captureActive = false

---------------------------------------------------------------------------
-- Error log
---------------------------------------------------------------------------
local function Store(entry)
  local db = ns.db
  if not db then
    if #pending < MAX_ERRORS then pending[#pending + 1] = entry end
    return
  end
  db.errors = type(db.errors) == "table" and db.errors or {}
  local list = db.errors
  -- Same error again: count it instead of filling the log.
  for _, e in ipairs(list) do
    if e.msg == entry.msg then e.count = (e.count or 1) + 1; e.time = entry.time; return end
  end
  table.insert(list, 1, entry)
  while #list > MAX_ERRORS do table.remove(list) end
end

-- "Ensemble/" only as a whole folder name: another addon's folder can end in "Ensemble"
-- (a transmog tracker, say), so a plain substring match would claim its errors.
local function OurPath(s)
  s = tostring(s or "")
  return s:find("^Ensemble[/\\]") ~= nil or s:find("[^%w_]Ensemble[/\\]") ~= nil
end
Report.OurPath = OurPath

local function Ours(msg, stack)
  return OurPath(tostring(msg or "") .. "\n" .. tostring(stack or ""))
end

function Report:Record(msg, stack)
  if not Ours(msg, stack) then return end
  -- The tab open at the time (a window that is closed says so).
  local UI = ns.UI
  local tab
  if UI and UI.frame then
    local okS, shown = pcall(UI.frame.IsShown, UI.frame)
    tab = (okS and shown) and tostring(UI.currentTab) or "window closed"
  end
  Store({ msg = tostring(msg):sub(1, 400), stack = stack and tostring(stack):sub(1, 600) or nil,
          time = (time and time()) or 0, version = tostring(ns.VERSION), count = 1, tab = tab })
  -- Once per session, a chat line pointing at /ens report (it waits out combat and keys).
  if not self.hinted then
    self.hintPending = true
    if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(self.MaybeHint, self) end) end
  end
end

function Report:InstallErrorCapture()
  if self.captureActive or not (geterrorhandler and seterrorhandler) then return end
  local okGet, prev = pcall(geterrorhandler)
  if not okGet or type(prev) ~= "function" then return end
  local function handler(msg, ...)
    pcall(function()
      local stack = debugstack and debugstack(3) or nil
      Report:Record(msg, stack)
    end)
    return prev(msg, ...)
  end
  local okSet = pcall(seterrorhandler, handler)
  local okNow, now = pcall(geterrorhandler)
  self.captureActive = okSet and okNow and now == handler or false
end

-- Errors from BugGrabber (if installed) that came from this addon, newest first.
local function BugGrabberErrors()
  local out = {}
  local BG = rawget(_G, "BugGrabber")
  if type(BG) ~= "table" or type(BG.GetDB) ~= "function" then return out end
  local ok, db = pcall(BG.GetDB, BG)
  if not ok or type(db) ~= "table" then return out end
  for i = #db, 1, -1 do
    local e = db[i]
    if type(e) == "table" and Ours(e.message, e.stack) then
      out[#out + 1] = { msg = tostring(e.message):sub(1, 400), stack = e.stack and tostring(e.stack):sub(1, 600),
                        count = e.counter or 1, when = e.time }
      if #out >= 5 then break end
    end
  end
  return out
end

function Report:Errors()
  local list = {}
  for _, e in ipairs((ns.db and ns.db.errors) or pending) do list[#list + 1] = e end
  return list
end

function Report:ClearErrors()
  if ns.db then ns.db.errors = {} end
  pending = {}
end

---------------------------------------------------------------------------
-- Pieces of the report
---------------------------------------------------------------------------
local function SpecLabel(id)
  local UD = ns.UD
  if not id or id == 0 or not UD then return nil end
  local spec = UD:GetSpec(id)
  if not spec then return "spec " .. tostring(id) end
  return UD:SpecName(id) .. " " .. UD:ClassName(spec.class)
end

-- Settings that differ from the defaults, as "path=value". Window position is left out.
local SKIP = { x = true, y = true, point = true, relPoint = true, angle = true, scale = true }
local function Diff(cur, def, path, out)
  for k, v in pairs(cur) do
    if not SKIP[k] then
      local p = path and (path .. "." .. tostring(k)) or tostring(k)
      local d = def and def[k]
      if type(v) == "table" then
        if type(d) == "table" and next(d) ~= nil then
          Diff(v, d, p, out)
        else
          -- Sets such as ignoredNeeds: list the keys that are on.
          local keys = {}
          for kk, vv in pairs(v) do if vv then keys[#keys + 1] = tostring(kk) end end
          table.sort(keys)
          if #keys > 0 then out[#out + 1] = p .. "={" .. table.concat(keys, ",") .. "}" end
        end
      elseif v ~= d then
        out[#out + 1] = p .. "=" .. tostring(v)
      end
    end
  end
  return out
end

function Report:ChangedSettings()
  local s = ns.db and ns.db.settings
  if not s then return {} end
  local out = Diff(s, ns.DEFAULTS and ns.DEFAULTS.settings or {}, nil, {})
  table.sort(out)
  return out
end

-- Other addons that draw on the same screens (Group Finder, unit frames, chat) and so are
-- the usual suspects in visual or compatibility reports.
Report.NEIGHBORS = {
  "RaiderIO", "PremadeGroupsFilter", "LFGBulletinBoard", "MythicDungeonTools", "ElvUI", "TukUI",
  "Details", "WeakAuras", "BigWigs", "DBM-Core", "Plater", "Kui_Nameplates", "Bartender4",
  "Prat-3.0", "Chattynator", "BugSack", "!BugGrabber", "LibDBIcon-1.0",
}

local function Loaded(name)
  local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  if not fn then return false end
  local ok, a = pcall(fn, name)
  return ok and a and true or false
end

function Report:OtherAddons()
  local found, total = {}, nil
  for _, n in ipairs(self.NEIGHBORS) do if Loaded(n) then found[#found + 1] = n end end
  local num = (C_AddOns and C_AddOns.GetNumAddOns) or rawget(_G, "GetNumAddOns")
  if num then
    local ok, n = pcall(num)
    if ok and type(n) == "number" then
      total = 0
      for i = 1, n do if Loaded(i) then total = total + 1 end end
    end
  end
  return found, total
end

local function DungeonName(key)
  local DD = ns.Dungeons
  return key and DD and DD.list[key] and DD.list[key].name or nil
end

---------------------------------------------------------------------------
-- The one-time error hint (1.6.5)
---------------------------------------------------------------------------
-- When the addon catches a Lua error of its own, one chat line per session says how to report
-- it. Never in combat or inside a key: it waits (checked again when combat ends, when a key is
-- recorded and when the window opens).
function Report:MaybeHint()
  if self.hinted or not self.hintPending or not ns.db then return false end
  if (ns.API and ns.API.InCombat and ns.API.InCombat()) or (ns.InKey and ns:InKey()) then return false end
  self.hinted, self.hintPending = true, nil
  ns:Print("Ensemble hit an error: /ens report builds a report.")
  return true
end
local function HintSoon()
  if Report.hinted then return end
  if C_Timer and C_Timer.After then C_Timer.After(1, function() pcall(Report.MaybeHint, Report) end)
  else pcall(Report.MaybeHint, Report) end
end
ns:On("BOSS_COMBAT", function(inCombat) if not inCombat and Report.hintPending then HintSoon() end end)
ns:On("HISTORY_CHANGED", function() if Report.hintPending then HintSoon() end end)

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------
-- Layout, most useful first (1.6.5, one report command):
--   1 what happened (three lines to fill in)   2 header   3 Right now   4 Problems (every FAIL
--   and WARN from the checks)   5 Lua errors, then Recent activity   6 settings changed, other
--   addons   7 Checks, consolidated (Verify:Report).
-- Specs, counts and settings only: never a player's name.
local function Safe(fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
  return nil
end

function Report:RightNow(add)
  local UI, db = ns.UI, ns.db
  local set = db and db.settings or {}
  -- Window, sizes and scale (layout reports need these)
  local shown = UI and UI.frame and UI.frame:IsShown()
  local tab = UI and UI.currentTab or (db and db.lastTab) or "?"
  local w = set.window or {}
  add("Window: " .. (shown and ("open on " .. tostring(tab)) or ("closed (last tab " .. tostring(tab) .. ")"))
    .. string.format(" | size %sx%s | text %s%%", tostring(w.width), tostring(w.height), tostring(set.textSize)))
  local scale = Safe(function() return UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() end)
  local sw = Safe(function() return GetScreenWidth and GetScreenWidth() end)
  local sh = Safe(function() return GetScreenHeight and GetScreenHeight() end)
  local pw, ph = Safe(function() if GetPhysicalScreenSize then return GetPhysicalScreenSize() end end)
  add(string.format("Screen: UI scale %s | UI size %sx%s | screen %sx%s",
    type(scale) == "number" and string.format("%.2f", scale) or "?",
    type(sw) == "number" and math.floor(sw + 0.5) or "?", type(sh) == "number" and math.floor(sh + 0.5) or "?",
    tostring(pw or "?"), tostring(ph or "?")))

  -- Dungeon and key level, each with where it came from
  local key, source = Safe(ns.GetEffectiveDungeon, ns)
  local level, levelSource
  if key and ns.ApplicantFit and ns.ApplicantFit.GetKeyLevel then
    level, levelSource = Safe(ns.ApplicantFit.GetKeyLevel, ns.ApplicantFit, key)
  end
  local pick = db and db.selectedDungeon or "?"
  add("Dungeon: " .. (key and (tostring(DungeonName(key)) .. " (" .. tostring(source) .. ")") or ("none (pick " .. tostring(pick) .. ")"))
    .. " | key level: " .. (level and ("+" .. level .. " (" .. tostring(levelSource or "?") .. ")") or "unknown (+10 assumed)"))
  local kKey, kLevel = Safe(ns.OwnKeystoneDungeon, ns)
  local rKey, rLevel, rAffixes = Safe(ns.ActiveKey, ns)
  local inKey = ns.InKey and Safe(ns.InKey, ns)
  add("In a key: " .. (rKey and (tostring(DungeonName(rKey)) .. (rLevel and (" +" .. rLevel) or " (level hidden)")
      .. ((rAffixes and #rAffixes > 0) and (", affix IDs " .. table.concat(rAffixes, ", ")) or ""))
      or (inKey and "yes (a run is being recorded)" or "no"))
    .. " | your keystone: " .. (kKey and (tostring(DungeonName(kKey) or kKey) .. (kLevel and (" +" .. kLevel) or "")) or "none"))
  if ns.Affixes and ns.Affixes.Current then
    local list = Safe(ns.Affixes.Current, ns.Affixes)
    if type(list) == "table" and #list > 0 then
      local names = {}
      for _, a in ipairs(list) do names[#names + 1] = tostring(a.name or a.label or a.key or a.id) end
      add("Affixes this week: " .. table.concat(names, ", "))
    end
  end

  -- Group (specs only, never names)
  local T = ns.Tracker
  local mode = ns.state and ns.state.mode == "live" and "party" or "planner"
  local members, known = (T and T.members) or {}, 0
  for _, m in ipairs(members) do if m.specID then known = known + 1 end end
  local inGroup = IsInGroup and IsInGroup()
  local inInstance, instType = false, nil
  if IsInInstance then inInstance, instType = IsInInstance() end
  add(string.format("Group: %s | Composition shows the %s (setting: %s) | roster read: %d member(s), specs %d known, %d pending | in an instance: %s",
    inGroup and "in a group" or "solo", mode, tostring(set.compMode), #members, known, #members - known,
    inInstance and tostring(instType) or "no"))
  local comp = {}
  for _, id in ipairs((db and db.currentComp) or {}) do comp[#comp + 1] = (SpecLabel(id) or "empty") end
  add("Planner slots: " .. (#comp > 0 and table.concat(comp, ", ") or "?"))
  local r = UI and UI.cp and UI.cp.lastAnalysis
  if r and r.members and #r.members > 0 then
    local live = {}
    for _, m in ipairs(r.members) do
      local p = m.profile
      local label = p and SpecLabel(p.id) or (m.classFile and (m.classFile .. " (spec pending)")) or "?"
      live[#live + 1] = label .. (m.isPlayer and " (you)" or "") .. (m.reserved and " (reserved)" or "")
    end
    add("Last checked group: " .. table.concat(live, ", "))
  end

  -- Hosting
  local listing = false
  if C_LFGList and C_LFGList.HasActiveEntryInfo then listing = Safe(C_LFGList.HasActiveEntryInfo) and true or false end
  local FG = ns.FillGroup
  local reservedN = (db and type(db.reserved) == "table" and type(db.reserved.list) == "table") and #db.reserved.list or 0
  if listing then
    local apps = T and Safe(T.GetApplicantGroups, T)
    local view = set.applicantView or {}
    add(string.format("Hosting: yes | %s application(s) | sort %s%s | Fill plan: %s | Auto-fill: %s | reserved slots: %d",
      type(apps) == "table" and #apps or "?", tostring(view.sort), view.hidePoor and ", Hide Poor on" or "",
      tostring(FG and FG.lastPlanLog or "not looked at yet"), (FG and FG.armed) and "armed" or "off", reservedN))
  else
    add("Hosting: no" .. (reservedN > 0 and (" | reserved slots: " .. reservedN) or ""))
  end

  -- Boss window
  local BW, BC = ns.BossWindow, ns.BossCards
  local bw = set.bossWindow or {}
  local bwShown = BW and BW.IsShown and Safe(BW.IsShown, BW)
  local page = (BC and BC.state and BC.state.dk and BC.Phase) and Safe(BC.Phase, BC) or nil
  add(string.format("Boss window: %s | boss %s%s%s | size %sx%s | text %s",
    bwShown and "open" or "closed", tostring(BC and BC.state and BC.state.index or "-"),
    (BC and BC.state and BC.state.dk) and (" in " .. tostring(DungeonName(BC.state.dk))) or "",
    page and (" (" .. (page == "trash" and "the trash on the way" or "the boss card") .. ")") or "",
    tostring(bw.width or "default"), tostring(bw.height or "default"), tostring(bw.fontSize)))
  -- Views (1.7.0) and your trash changes (counts only)
  local view = type(set.view) == "table" and set.view or {}
  local hid, moved, dungeons = 0, 0, 0
  for dk in pairs((db and type(db.trashEdits) == "table") and db.trashEdits or {}) do
    local h, m = 0, 0
    if ns.Walkthrough and ns.Walkthrough.TrashEditCounts then h, m = Safe(ns.Walkthrough.TrashEditCounts, ns.Walkthrough, dk) end
    hid, moved, dungeons = hid + (tonumber(h) or 0), moved + (tonumber(m) or 0), dungeons + 1
  end
  add(string.format("Views: Composition %s, Dungeon %s (role filter %s), Plan %s | trash rows changed by you: %d hidden, %d moved in %d dungeon(s)",
    tostring(view.composition), tostring(view.dungeons), tostring(set.walkRole), tostring(view.plan), hid, moved, dungeons))

  local mySpec = Safe(function() return ns.API and ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID() end)
  local spec = mySpec and ns.UD and ns.UD:GetSpec(mySpec)
  add("Your spec: " .. (mySpec and (tostring(SpecLabel(mySpec)) .. (spec and spec.role and (" (" .. spec.role .. ")") or "")) or "not read"))
end

-- No "short version" (decided at the 1.6.5 build): in town the whole report is about 70 lines.
function Report:Build()
  local L = {}
  local function add(s) L[#L + 1] = s end
  local version, build, _, toc = "?", "?", "?", "?"
  if GetBuildInfo then version, build, _, toc = GetBuildInfo() end

  add("=== Ensemble report ===")
  add("What happened:  ")
  add("What you expected:  ")
  add("Steps to see it again (if you know them):  ")
  add("")
  add(string.format("Addon %s | client %s (%s, toc %s) | %s | %s", tostring(ns.VERSION), tostring(version),
    tostring(build), tostring(toc), tostring(GetLocale and GetLocale() or "?"),
    date and date("%Y-%m-%d %H:%M") or "?"))
  add(ns.Dungeons:FreshnessText())

  add("")
  add("-- Right now --")
  local okR, errR = pcall(self.RightNow, self, add)
  if not okR then add("(this part errored: " .. tostring(errR) .. ")") end

  -- The checks run once; their problems come first, their facts last.
  local checks
  if ns.Verify and ns.Verify.Report then
    local okV, res = pcall(ns.Verify.Report, ns.Verify)
    checks = okV and res or nil
    if not okV then self.lastCheckError = tostring(res) end
  end
  add("")
  if checks then
    local c = checks.counts
    add(string.format("-- Problems: %d FAIL, %d WARN (%d checks OK, %d not checked) --", c.FAIL or 0, c.WARN or 0, c.OK or 0, c.SKIP or 0))
    if #checks.problems == 0 then add("none found") end
    for _, l in ipairs(checks.problems) do add(l) end
  else
    add("-- Problems --")
    add("the checks could not run" .. (self.lastCheckError and (": " .. self.lastCheckError) or ""))
  end

  -- Errors
  add("")
  local errs = self:Errors()
  local bg = BugGrabberErrors()
  if #errs == 0 and #bg == 0 then
    -- With BugGrabber installed it owns the error handler, so our own capture stays off by
    -- design: say who is catching errors rather than "not active" (issue #8).
    local BG = rawget(_G, "BugGrabber")
    local why = (type(BG) == "table" and type(BG.GetDB) == "function") and " (BugGrabber is catching errors; none from this addon)"
      or (self.captureActive and "" or " (error capture not active in this client)")
    add("-- Lua errors from this addon: none recorded" .. why .. " --")
  else
    add("-- Lua errors from this addon (newest first) --")
    local seen = {}
    local function addErr(e)
      if seen[e.msg] then return end
      seen[e.msg] = true
      add(string.format("[x%d%s%s%s] %s", e.count or 1, e.version and (", v" .. e.version) or "",
        (e.time and date and e.time > 0) and (", " .. date("%m-%d %H:%M", e.time)) or "",
        e.tab and (", on " .. tostring(e.tab)) or "", e.msg))
      if e.stack then
        local first = 0
        for line in tostring(e.stack):gmatch("[^\n]+") do
          if OurPath(line) then
            add("      " .. line:gsub("^%s+", ""):sub(1, 160)); first = first + 1
            if first >= 3 then break end
          end
        end
      end
    end
    for _, e in ipairs(errs) do addErr(e) end
    for _, e in ipairs(bg) do addErr(e) end
  end

  -- Recent activity
  add("")
  local act = ns.Activity and ns.Activity:Lines() or {}
  add("-- Recent activity (newest first; this session) --")
  if #act == 0 then add("nothing yet") end
  for _, l in ipairs(act) do add(l) end

  -- Settings and other addons
  add("")
  local changed = self:ChangedSettings()
  add("Settings changed from defaults: " .. (#changed > 0 and table.concat(changed, ", ") or "none"))
  local neighbors, total = self:OtherAddons()
  add("Other addons loaded: " .. (total and tostring(total) or "?")
    .. (#neighbors > 0 and (" (including " .. table.concat(neighbors, ", ") .. ")") or ""))

  -- Checks, consolidated
  if checks then
    add("")
    add("-- Checks --")
    for _, l in ipairs(checks.checks) do add(l) end
  end
  add("=== end of report ===")
  return table.concat(L, "\n")
end

function Report:Run()
  local text = self:Build()
  self.lastReport = text
  if ns.db then ns.db.lastReport = text end
  local shown = ns.Verify and ns.Verify:ShowText(text, "report: add what happened at the top")
  if shown then
    ns:Print("Report ready: fill in the first three lines, then copy it (Ctrl+A, Ctrl+C) into your report.")
  else
    ns:Print("Could not open the report window; the report is in EnsembleDB.lastReport after /reload.")
  end
  return text
end

-- Install as early as possible (this file loads with the addon), and flush anything caught
-- before SavedVariables were ready.
Report:InstallErrorCapture()
ns:On("DB_READY", function() for _, e in ipairs(pending) do Store(e) end; pending = {} end)
