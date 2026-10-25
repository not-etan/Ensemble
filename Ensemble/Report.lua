-- Ensemble / Report.lua
-- /ens report: one copyable block for bug reports. It holds everything a fix needs that a
-- player wouldn't think to mention: addon version, client build and language, where they
-- were (tab, dungeon, key level, affixes, listing), the group's specs (never player
-- names), settings changed from the defaults, addons that share the same screens, the
-- addon's own recent Lua errors, and the /ens verify summary with every WARN and FAIL line.
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
  Store({ msg = tostring(msg):sub(1, 400), stack = stack and tostring(stack):sub(1, 600) or nil,
          time = (time and time()) or 0, version = tostring(ns.VERSION), count = 1 })
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
-- The report
---------------------------------------------------------------------------
function Report:Build()
  local L = {}
  local function add(s) L[#L + 1] = s end
  local version, build, _, toc = "?", "?", "?", "?"
  if GetBuildInfo then version, build, _, toc = GetBuildInfo() end

  add("=== Ensemble bug report ===")
  add("What happened:  ")
  add("What you expected:  ")
  add("Steps to see it again (if you know them):  ")
  add("")
  add(string.format("Addon %s | client %s (%s, toc %s) | %s | %s", tostring(ns.VERSION), tostring(version),
    tostring(build), tostring(toc), tostring(GetLocale and GetLocale() or "?"),
    date and date("%Y-%m-%d %H:%M") or "?"))
  add(ns.Dungeons:FreshnessText())

  -- Where the player was
  local UI = ns.UI
  local shown = UI and UI.frame and UI.frame:IsShown()
  local tab = UI and UI.currentTab or (ns.db and ns.db.lastTab) or "?"
  local where = "Window: " .. (shown and ("open on " .. tostring(tab)) or ("closed (last tab " .. tostring(tab) .. ")"))
  if ns.db and ns.db.settings then
    local w = ns.db.settings.window or {}
    where = where .. string.format(" | size %sx%s | text %s%%", tostring(w.width), tostring(w.height), tostring(ns.db.settings.textSize))
  end
  add(where)

  local ok, key, source = pcall(ns.GetEffectiveDungeon, ns)
  local level
  if ok and key and ns.Affixes then
    local okL, lv = pcall(ns.Affixes.KeyLevel, ns.Affixes, key)
    level = okL and lv or nil
  end
  local pick = ns.db and ns.db.selectedDungeon or "?"
  add("Dungeon: " .. (ok and key and (DungeonName(key) .. (level and (" +" .. level) or "") .. " (" .. tostring(source) .. ")")
    or ("none (pick " .. tostring(pick) .. ")")))
  local okK, kKey, kLevel = pcall(ns.OwnKeystoneDungeon, ns)
  if okK and kKey then add("Your keystone: " .. tostring(DungeonName(kKey) or kKey) .. (kLevel and (" +" .. kLevel) or "")) end
  if ns.Affixes and ns.Affixes.Current then
    local okA, list = pcall(ns.Affixes.Current, ns.Affixes)
    if okA and type(list) == "table" and #list > 0 then
      local names = {}
      for _, a in ipairs(list) do names[#names + 1] = tostring(a.name or a.label or a.key or a.id) end
      add("Affixes this week: " .. table.concat(names, ", "))
    end
  end

  -- Group (specs only, never names)
  local comp = {}
  for i, id in ipairs((ns.db and ns.db.currentComp) or {}) do comp[#comp + 1] = (SpecLabel(id) or "empty") end
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
  local inGroup = IsInGroup and IsInGroup()
  local inInstance, instType = false, nil
  if IsInInstance then inInstance, instType = IsInInstance() end
  local listing = false
  if C_LFGList and C_LFGList.HasActiveEntryInfo then
    local okE, has = pcall(C_LFGList.HasActiveEntryInfo); listing = okE and has or false
  end
  add(string.format("In a group: %s | in an instance: %s | hosting a listing: %s",
    inGroup and "yes" or "no", inInstance and tostring(instType) or "no", listing and "yes" or "no"))
  local _, mySpec = pcall(function() return ns.API and ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID() end)
  if mySpec then add("Your spec: " .. tostring(SpecLabel(mySpec))) end

  -- Settings and other addons
  local changed = self:ChangedSettings()
  add("Settings changed from defaults: " .. (#changed > 0 and table.concat(changed, ", ") or "none"))
  local neighbors, total = self:OtherAddons()
  add("Other addons loaded: " .. (total and tostring(total) or "?")
    .. (#neighbors > 0 and (" (including " .. table.concat(neighbors, ", ") .. ")") or ""))

  -- Errors
  local errs = self:Errors()
  local bg = BugGrabberErrors()
  if #errs == 0 and #bg == 0 then
    -- With BugGrabber installed it owns the error handler, so our own capture stays off by
    -- design: say who is catching errors rather than "not active" (issue #8).
    local BG = rawget(_G, "BugGrabber")
    local why = (type(BG) == "table" and type(BG.GetDB) == "function") and " (BugGrabber is catching errors; none from this addon)"
      or (self.captureActive and "" or " (error capture not active in this client)")
    add("Lua errors from this addon: none recorded" .. why)
  else
    add("Lua errors from this addon (newest first):")
    local seen = {}
    local function addErr(e)
      if seen[e.msg] then return end
      seen[e.msg] = true
      add(string.format("  [x%d%s%s] %s", e.count or 1, e.version and (", v" .. e.version) or "",
        (e.time and date and e.time > 0) and (", " .. date("%m-%d %H:%M", e.time)) or "", e.msg))
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

  -- Verify summary: header, summary and every WARN/FAIL line
  if ns.Verify and ns.Verify.Build then
    local okV, _, counts, vlines = pcall(ns.Verify.Build, ns.Verify)
    if okV and vlines then
      add(string.format("Verify: %d OK, %d WARN, %d FAIL, %d INFO", counts.OK or 0, counts.WARN or 0, counts.FAIL or 0, counts.INFO or 0))
      -- FAIL lines first, then WARN; capped so the report stays pasteable.
      local picked, extra = 0, 0
      for _, tag in ipairs({ "^%[FAIL%]", "^%[WARN%]" }) do
        for _, l in ipairs(vlines) do
          if l:find(tag) then
            if picked < 12 then add("  " .. l); picked = picked + 1 else extra = extra + 1 end
          end
        end
      end
      if extra > 0 then add(string.format("  ... and %d more (run /ens verify for the full report)", extra)) end
    else
      add("Verify: could not run")
    end
  end
  add("=== end of report ===")
  return table.concat(L, "\n")
end

function Report:Run()
  local text = self:Build()
  self.lastReport = text
  if ns.db then ns.db.lastReport = text end
  local shown = ns.Verify and ns.Verify:ShowText(text, "bug report: add what happened at the top")
  if shown then
    ns:Print("Bug report ready: fill in the first three lines, then copy it (Ctrl+A, Ctrl+C) into your report.")
  else
    ns:Print("Could not open the report window; the report is in EnsembleDB.lastReport after /reload.")
  end
  return text
end

-- Install as early as possible (this file loads with the addon), and flush anything caught
-- before SavedVariables were ready.
Report:InstallErrorCapture()
ns:On("DB_READY", function() for _, e in ipairs(pending) do Store(e) end; pending = {} end)
