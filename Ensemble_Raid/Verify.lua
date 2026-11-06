-- Ensemble Raid (test build) / Verify.lua
-- Adds a "Raid test module" section to /ens verify: what this client reports for raids, with
-- counts only (never a player's name). Wraps Ensemble's Verify:Build, so the report and its
-- OK / WARN / FAIL counts include these lines.

local _, R = ...
if R.disabled then return end
local ns = R.ns
local D = R.Data

local V = {}
R.Verify = V

function V:Lines()
  local out, counts = {}, {}
  local function Add(status, text)
    counts[status] = (counts[status] or 0) + 1
    out[#out + 1] = string.format("[%s] %s", status, text)
  end
  out[#out + 1] = ""
  out[#out + 1] = "== Raid test module =="
  Add("INFO", string.format("Ensemble_Raid %s; raid data checked %s", tostring(R.VERSION), D.DATA_CHECKED))
  local bad = D:Validate(ns.UD)
  Add(#bad == 0 and "OK" or "FAIL", #bad == 0 and "raid data valid (10 bosses, 3 instances)" or ("raid data problems: " .. table.concat(bad, "; ")))
  Add("INFO", string.format("mode: %s (setting %s; Auto would pick %s)", R:Mode(), tostring(R.db.mode), R:AutoMode()))
  Add(EnsembleCore == ns and "OK" or "FAIL", "EnsembleCore (Ensemble's namespace) readable")
  Add(GetRaidRosterInfo and "OK" or "WARN", "GetRaidRosterInfo " .. (GetRaidRosterInfo and "present" or "missing"))
  Add(NotifyInspect and GetInspectSpecialization and "OK" or "WARN", "inspect (NotifyInspect, GetInspectSpecialization) " .. ((NotifyInspect and GetInspectSpecialization) and "present" or "missing"))
  local members = R.Roster:Members()
  local c = R.Roster:Counts(members)
  Add("INFO", string.format("roster: %s, %d players (%d tanks, %d healers, %d DPS), specs known %d of %d, inspected this session %d",
    R.Roster:Source(), c.total, c.TANK, c.HEALER, c.DAMAGER, c.known, c.total, R.Roster.inspected or 0))
  local secretNames = 0
  if IsInRaid and IsInRaid() and GetRaidRosterInfo then
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
      local okR, nm = pcall(GetRaidRosterInfo, i)
      if okR and R.Secret(nm) then secretNames = secretNames + 1 end
    end
    Add(secretNames == 0 and "OK" or "WARN", string.format("raid roster names: %d hidden by the game", secretNames))
  end
  local inst, d, itype, diffID, name = R:CurrentInstance()
  Add("INFO", string.format("instance here: %s (type %s, difficulty ID %s) -> %s%s", tostring(name), tostring(itype), tostring(diffID),
    inst and inst.key or "not a season raid or Lair", d and (", " .. d) or ""))
  local seen = {}
  for n, id in pairs(R.db.encSeen) do seen[#seen + 1] = string.format("%s=%s%s", n, tostring(id), R.BossWindow:Match(n) and "" or " (no card)") end
  table.sort(seen)
  Add("INFO", "encounters seen (name=ID): " .. (#seen > 0 and table.concat(seen, ", ") or "none yet"))
  local le, lend = R.BossWindow.lastEncounter, R.BossWindow.lastEnd
  if le then Add(le.matched and "OK" or "WARN", "last encounter start " .. (le.matched and "matched a boss card" or "matched no card")) end
  if lend then Add("INFO", "last encounter end: success " .. tostring(lend.success) .. ", kills this session " .. tostring(R.BossWindow.kills or 0)) end
  local hasLock = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
  Add(hasLock and "OK" or "WARN", "chat lockdown check " .. (hasLock and ("present; locked now: " .. tostring(R:ChatLocked())) or "missing"))
  Add("INFO", "posts go to: " .. tostring(R:Channel(false) or "you (not in a group)") .. "; raid warning allowed: " .. tostring(R:CanWarn() and true or false))
  if R.lastSent then Add("INFO", string.format("last post: %s, %d lines to %s", tostring(R.lastSent.what), R.lastSent.count, tostring(R.lastSent.channel or "you"))) end
  local plans = 0
  for _, byDiff in pairs(R.db.plans) do for _ in pairs(byDiff) do plans = plans + 1 end end
  Add("INFO", string.format("saved plans: %d; planner list: %d players", plans, #R.db.planner.members))
  return out, counts
end

local origBuild = ns.Verify and ns.Verify.Build
if origBuild then
  function ns.Verify:Build(...)
    local text, counts, a3 = origBuild(self, ...)
    local ok, lines, extra = pcall(V.Lines, V)
    if ok and type(text) == "string" then
      text = text .. "\n" .. table.concat(lines, "\n")
      if type(counts) == "table" then for k, v in pairs(extra) do counts[k] = (counts[k] or 0) + v end end
    elseif not ok then
      text = tostring(text) .. "\n\n== Raid test module ==\n[FAIL] raid section error: " .. tostring(lines)
      if type(counts) == "table" then counts.FAIL = (counts.FAIL or 0) + 1 end
    end
    return text, counts, a3
  end
end
