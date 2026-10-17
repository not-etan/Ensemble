-- Keystone Command / BossCards.lua
-- Boss cards: the role-split boss notes from BossData.lua, your own edits to them, the
-- kick / dispel jobs the plan gives YOU on each boss, the chat text, and which boss you're
-- on inside a dungeon (first boss not yet killed; follows ENCOUNTER_START / ENCOUNTER_END).
-- No UI here: BossWindow.lua draws the pop-up and UI.lua the Dungeons-tab section.
--
-- Edits are saved per dungeon and boss name in db.bossNotes[dungeonKey][bossName] =
-- { text = "ROLE: line\n...", base = <default text when edited> }. A later data update
-- never overwrites them; `base` lets the card say when the built-in default has changed.
local _, ns = ...

local BC = {}
ns.BossCards = BC

BC.ROLE_LABEL = { ALL = "All", TANK = "Tank", HEAL = "Healer", DPS = "DPS" }
local SPEC_ROLE = { TANK = "TANK", HEALER = "HEAL", DAMAGER = "DPS" }

local function S() return ns.db and ns.db.settings end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
function BC:Bosses(dk)
  return (ns.BossData and ns.BossData.list[dk or ""]) or {}
end

function BC:Boss(dk, i) return self:Bosses(dk)[i] end

-- "ROLE: text" lines <-> { role, text } tables. Unknown or missing prefixes become ALL.
local PREFIX = { ALL = "ALL", EVERYONE = "ALL", TANK = "TANK", HEAL = "HEAL", HEALER = "HEAL",
                 HEALS = "HEAL", DPS = "DPS", DD = "DPS", DAMAGE = "DPS" }
function BC:Parse(text)
  local out = {}
  for raw in tostring(text or ""):gmatch("[^\r\n]+") do
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local tag, rest = line:match("^(%a+)%s*:%s*(.*)$")
      local role = tag and PREFIX[tag:upper()]
      if role and rest ~= "" then out[#out + 1] = { role = role, text = rest }
      else out[#out + 1] = { role = "ALL", text = line } end
    end
  end
  return out
end

function BC:Serialize(lines)
  local t = {}
  for _, l in ipairs(lines or {}) do t[#t + 1] = l.role .. ": " .. l.text end
  return table.concat(t, "\n")
end

function BC:DefaultText(dk, i)
  local b = self:Boss(dk, i)
  return b and self:Serialize(b.lines) or ""
end

local function Notes(dk, create)
  local db = ns.db
  if not db then return nil end
  if create then
    db.bossNotes = type(db.bossNotes) == "table" and db.bossNotes or {}
    db.bossNotes[dk] = db.bossNotes[dk] or {}
  end
  return db.bossNotes and db.bossNotes[dk]
end

-- Lines to show: your edit if there is one, else the built-in card.
-- Returns lines, edited (bool), defaultChanged (bool: the built-in card changed since you edited).
function BC:Lines(dk, i)
  local b = self:Boss(dk, i)
  if not b then return {}, false, false end
  local n = Notes(dk)
  local e = n and n[b.name]
  if e and type(e.text) == "string" then
    return self:Parse(e.text), true, (e.base ~= nil and e.base ~= self:DefaultText(dk, i))
  end
  return b.lines, false, false
end

function BC:EditText(dk, i)
  local b = self:Boss(dk, i)
  if not b then return "" end
  local n = Notes(dk)
  local e = n and n[b.name]
  return (e and e.text) or self:DefaultText(dk, i)
end

function BC:SetEdit(dk, i, text)
  local b = self:Boss(dk, i)
  if not b then return end
  local clean = self:Serialize(self:Parse(text))
  local default = self:DefaultText(dk, i)
  local n = Notes(dk, true)
  if clean == default or clean == "" then n[b.name] = nil
  else n[b.name] = { text = clean, base = default } end
  ns:Fire("BOSS_NOTES_CHANGED", dk, i)
end

function BC:Reset(dk, i)
  local b = self:Boss(dk, i)
  local n = b and Notes(dk)
  if n then n[b.name] = nil end
  ns:Fire("BOSS_NOTES_CHANGED", dk, i)
end

function BC:IsEdited(dk, i)
  local _, edited = self:Lines(dk, i)
  return edited
end

-- Your role: your spec's role, else the group role you queued as, else DPS.
function BC:MyRole()
  local id = ns.API and ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID()
  local spec = id and ns.UD and ns.UD:GetSpec(id)
  if spec and SPEC_ROLE[spec.role] then return SPEC_ROLE[spec.role] end
  if UnitGroupRolesAssigned then
    local ok, r = pcall(UnitGroupRolesAssigned, "player")
    if ok and SPEC_ROLE[r] then return SPEC_ROLE[r] end
  end
  return "DPS"
end

-- Lines in reading order: your role first, then everyone's, then (if `all`) the other roles.
function BC:Ordered(lines, role, all)
  local out = {}
  local function pick(want) for _, l in ipairs(lines) do if l.role == want then out[#out + 1] = l end end end
  pick(role); if role ~= "ALL" then pick("ALL") end
  if all then
    for _, r in ipairs(ns.BossData and ns.BossData.ROLES or {}) do
      if r ~= role and r ~= "ALL" then pick(r) end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Your jobs on this boss (from the kick and dispel plan)
---------------------------------------------------------------------------
-- The group to plan for: your live party if you're in one, else just you.
function BC:Members()
  local T = ns.Tracker
  if T and T.GetComp and IsInGroup and IsInGroup() then
    local comp = T:GetComp()
    if #comp > 0 then return comp end
  end
  local id = ns.API and ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID()
  if id and ns.UD and ns.UD:GetSpec(id) then return { { specID = id, isPlayer = true } } end
  return {}
end

-- The plan is cached on everything it depends on (dungeon, group, affixes, key level), so
-- paging, text size and the combat fade don't re-run the analysis; settings clear it.
local planCache = {}
local function PlanSig(dk, members)
  local t = { dk }
  for _, m in ipairs(members) do
    t[#t + 1] = tostring(m.specID or m.classFile) .. ":" .. tostring(m.role) .. ":" .. (m.pending and "p" or "")
      .. (m.isPlayer and "me" or "")
  end
  local AF = ns.Affixes
  if AF then t[#t + 1] = AF:Signature() .. "@" .. tostring(AF:KeyLevel(dk)) end
  t[#t + 1] = "o" .. tostring(ns.Assignments and ns.Assignments.overrideVersion or 0)
  return table.concat(t, ";")
end

function BC:Plan(dk, members)
  members = members or self:Members()
  if not dk or #members == 0 or not (ns.Analysis and ns.Assignments) then return nil end
  local sig = PlanSig(dk, members)
  if planCache.sig == sig then return planCache.plan, planCache.r end
  local ok, r = pcall(ns.Analysis.Analyze, ns.Analysis, members, dk, S())
  if not ok or not r then return nil end
  local ok2, plan = pcall(ns.Assignments.Build, ns.Assignments, r, S())
  if not ok2 then return nil end
  planCache = { sig = sig, plan = plan, r = r }
  return plan, r
end

function BC:ClearPlanCache() planCache = {} end

-- Your jobs for this boss's linked requirements: list of { kind, text, backup }.
function BC:Jobs(dk, i, plan, r)
  local b = self:Boss(dk, i)
  if not (b and plan and r and not plan.empty) then return {} end
  local want = {}
  for _, id in ipairs(b.reqs or {}) do want[id] = true end
  if not next(want) then return {} end
  local me
  for idx, m in ipairs(r.members or {}) do if m.isPlayer then me = idx; break end end
  if not me then return {} end
  local job
  for _, j in ipairs(ns.Assignments:PlayerJobs(plan, true)) do if j.index == me then job = j end end
  if not job then return {} end
  local AS = ns.Assignments
  local out = {}
  local function on(row) return row and row.req and want[row.req.id] end
  for _, k in ipairs(job.kicks) do
    if on(k.row) then
      out[#out + 1] = { kind = "kick", text = "Kick " .. k.cast .. (k.pos and (" (" .. AS.Ord(k.pos) .. " of " .. k.of .. ")") or "")
        .. " with " .. k.ability }
    end
  end
  for _, st in ipairs(job.stops) do
    if on(st.row) then out[#out + 1] = { kind = "stop", text = "Stop " .. st.cast .. " with " .. st.ability } end
  end
  for _, d in ipairs(job.dispels) do
    if on(d.row) then
      local verb = (d.type == "Purge" and "Purge ") or (d.type == "Soothe" and "Soothe ") or "Dispel "
      out[#out + 1] = { kind = "dispel", text = verb .. d.cast .. (verb == "Dispel " and (" (" .. d.type .. ")") or "") .. " with " .. d.ability }
    end
  end
  for _, bk in ipairs(job.backups) do
    if on(bk.row) then out[#out + 1] = { kind = "backup", backup = true, text = "Backup for " .. bk.cast .. (bk.type and (" (" .. bk.type .. ")") or "") } end
  end
  return out
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
local LINE_MAX = 250

-- One chat line per role (ALL first), "[KC] Boss -" on the first. Your personal jobs are
-- not included: "Post kick & dispel plan" covers everyone's jobs.
function BC:ChatLines(dk, i)
  local b = self:Boss(dk, i)
  if not b then return {} end
  local lines = self:Lines(dk, i)
  local out = {}
  local head = "[KC] " .. b.name .. " - "
  for _, role in ipairs(ns.BossData.ROLES) do
    local parts = {}
    for _, l in ipairs(lines) do if l.role == role then parts[#parts + 1] = l.text end end
    if #parts > 0 then
      -- Too long for one chat line: carried on as "ROLE: ..." lines, never cut.
      local prefix = (#out == 0 and head or "") .. role .. ": "
      for _, l in ipairs(ns.Util.ChatWrap(prefix, table.concat(parts, " "), role .. ": ", LINE_MAX)) do out[#out + 1] = l end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Which boss you're on
---------------------------------------------------------------------------
-- state: { dk, index, killed = { [i] = true }, at = time }, saved in db.bossProgress so a
-- /reload mid-key keeps it. A new key, or entering another dungeon, starts it over.
BC.state = { killed = {} }

local function Save()
  local db = ns.db
  if not db then return end
  db.bossProgress = { dk = BC.state.dk, index = BC.state.index, killed = BC.state.killed, at = time and time() or 0 }
end

local function norm(s) return (tostring(s or ""):lower():gsub("[^%w]", "")) end

-- The encounter journal's instance ID for a dungeon (issue #10). EJ_GetInstanceForMap wants a
-- UI map ID, not the instance map ID we hold, so it always returned 0. First choice:
-- C_EncounterJournal.GetInstanceForGameMap(instance map ID), which works anywhere (confirmed
-- for all eight Season 2 dungeons, October 16, build 70448). Fallback, only while you are
-- inside that dungeon: EJ_GetInstanceForMap(C_Map.GetBestMapForUnit("player")).
-- Returns the journal ID (or nil) and which call found it.
function BC:JournalInstance(dk, instanceMapID)
  instanceMapID = instanceMapID or (dk and ns.Dungeons and ns.Dungeons.INSTANCE_MAP_IDS and ns.Dungeons.INSTANCE_MAP_IDS[dk])
  local CEJ = rawget(_G, "C_EncounterJournal")
  local byGame = type(CEJ) == "table" and CEJ.GetInstanceForGameMap
  if instanceMapID and byGame then
    local ok, jid = pcall(byGame, instanceMapID)
    if ok and type(jid) == "number" and jid > 0 then return jid, "C_EncounterJournal.GetInstanceForGameMap" end
  end
  local here = false
  if dk and ns.CurrentInstanceDungeon then
    local ok, cur = pcall(ns.CurrentInstanceDungeon, ns)
    here = ok and cur == dk
  end
  local getInst = rawget(_G, "EJ_GetInstanceForMap")
  local CMap = rawget(_G, "C_Map")
  local best = type(CMap) == "table" and CMap.GetBestMapForUnit
  if here and getInst and best then
    local okM, uiMap = pcall(best, "player")
    if okM and type(uiMap) == "number" then
      local ok, jid = pcall(getInst, uiMap)
      if ok and type(jid) == "number" and jid > 0 then return jid, "EJ_GetInstanceForMap(C_Map.GetBestMapForUnit)" end
    end
  end
  return nil
end

-- Encounter-journal IDs for each boss, by position (best effort; names are the fallback).
local ejCache = {}
function BC:EncounterIDs(dk)
  if ejCache[dk] ~= nil then return ejCache[dk] or nil end
  local ids = false
  local getEnc = rawget(_G, "EJ_GetEncounterInfoByIndex")
  if getEnc then
    local jid = self:JournalInstance(dk)
    if jid then
      ids = { byID = {}, byName = {} }
      for n = 1, 12 do
        local ok2, name, _, _, _, _, _, dungeonEncounterID = pcall(getEnc, n, jid)
        if not ok2 or not name then break end
        ids.byName[norm(name)] = n
        if dungeonEncounterID then ids.byID[dungeonEncounterID] = n end
      end
    end
  end
  if ids then ejCache[dk] = ids end   -- the journal may not be loaded yet: look again next time
  return ids or nil
end

-- Boss ability names -> spell IDs from the game's encounter journal, for this dungeon's
-- bosses (every ability section with a spell). Used to turn ability names on the cards
-- into links with icons and real tooltips. Cached per dungeon; empty if the journal
-- isn't available. Names are the client's, so on non-English clients few will match.
local spellCache = {}
local NO_SPELLS = {}   -- shared "nothing found" table, so link-name lists built for it are reused
function BC:JournalSpells(dk)
  if spellCache[dk] then return spellCache[dk] end
  local out, found = {}, false
  local getEnc = rawget(_G, "EJ_GetEncounterInfoByIndex")
  local CEJ = rawget(_G, "C_EncounterJournal")
  local getSec = type(CEJ) == "table" and CEJ.GetSectionInfo
  if getEnc and getSec then
    local jid = self:JournalInstance(dk)
    if jid then
      found = true
      for n = 1, 12 do
        local ok2, name, _, _, rootSection = pcall(getEnc, n, jid)
        if not ok2 or not name then break end
        local stack, steps = { rootSection }, 0
        while #stack > 0 and steps < 400 do
          steps = steps + 1
          local id = table.remove(stack)
          if id and id > 0 then
            local ok3, info = pcall(getSec, id)
            if ok3 and type(info) == "table" then
              local title, spell = info.title, info.spellID
              if type(title) == "string" and title ~= "" and type(spell) == "number" and spell > 0 and not out[title] then
                out[title] = { id = spell, side = "e", type = "boss" }
              end
              if info.siblingSectionID then stack[#stack + 1] = info.siblingSectionID end
              if info.firstChildSectionID then stack[#stack + 1] = info.firstChildSectionID end
            end
          end
        end
      end
    end
  end
  if not found then return NO_SPELLS end   -- journal not ready: try again on the next draw
  spellCache[dk] = out
  return out
end

-- A card line (or job line) with its ability names as links.
function BC:Decorate(dk, text)
  if not (ns.Links and ns.Links.Decorate) then return text end
  return ns.Links:Decorate(text, nil, dk, self:JournalSpells(dk))
end

-- Which card an encounter belongs to: by name first (exact, then partial: "Kyrakka and
-- Erkhart Stormvein" vs "Kyrakka"), then by the journal's encounter ID and position.
function BC:IndexForEncounter(dk, encounterID, name)
  local bosses = self:Bosses(dk)
  local nn = norm(name)
  if nn ~= "" then
    for idx, b in ipairs(bosses) do if norm(b.name) == nn then return idx end end
    for idx, b in ipairs(bosses) do
      local bn = norm(b.name)
      if bn:find(nn, 1, true) or nn:find(bn, 1, true) then return idx end
    end
  end
  local ej = self:EncounterIDs(dk)
  local n = ej and encounterID and ej.byID[encounterID]
  if n and bosses[n] then return n end
  return nil
end

function BC:FirstAlive(dk, killed)
  for idx = 1, #self:Bosses(dk) do if not (killed or {})[idx] then return idx end end
  return #self:Bosses(dk)
end

-- Entering (or re-entering) a dungeon. Restores saved progress for the same dungeon if it
-- is recent (2 hours); otherwise starts at the first boss.
function BC:Enter(dk)
  if not dk or #self:Bosses(dk) == 0 then self.state = { killed = {} }; return false end
  if self.state.dk == dk then return true end
  local saved = ns.db and ns.db.bossProgress
  local now = time and time() or 0
  if saved and saved.dk == dk and (now - (saved.at or 0)) < 7200 and type(saved.killed) == "table" then
    self.state = { dk = dk, killed = saved.killed }
  else
    self.state = { dk = dk, killed = {} }
  end
  self.state.index = self:FirstAlive(dk, self.state.killed)
  Save()
  return true
end

function BC:Leave() self.state = { killed = {} } end

function BC:NewRun()
  if self.state.dk then
    self.state.killed = {}
    self.state.index = 1
    Save()
  end
end

function BC:Show(index)
  local dk = self.state.dk
  if not dk then return end
  local n = #self:Bosses(dk)
  if n == 0 then return end
  self.state.index = ((index - 1) % n) + 1
  Save()
  ns:Fire("BOSS_CARD_CHANGED")
end

function BC:Step(d) if self.state.dk then self:Show((self.state.index or 1) + d) end end

function BC:OnEncounterStart(encounterID, name)
  local dk = self.state.dk
  if not dk then return end
  local idx = self:IndexForEncounter(dk, encounterID, name)
  if idx then self:Show(idx) end
end

-- Same arguments as the ENCOUNTER_END event.
function BC:OnEncounterEnd(encounterID, name, difficultyID, groupSize, success)
  local dk = self.state.dk
  if not dk or not (success == 1 or success == true) then return end
  local idx = self:IndexForEncounter(dk, encounterID, name) or self.state.index
  if idx then self.state.killed[idx] = true end
  self:Show(self:FirstAlive(dk, self.state.killed))
end

-- Where you are right now (a Season dungeon with boss cards), or nil.
function BC:CurrentDungeon()
  local ok, dk = pcall(ns.CurrentInstanceDungeon, ns)
  if ok and dk and #self:Bosses(dk) > 0 then return dk end
  return nil
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
BC.frame = frame
local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ENCOUNTER_START", "ENCOUNTER_END",
                 "CHALLENGE_MODE_START", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
BC.eventsOK = {}
function BC:RegisterEvents()
  for _, ev in ipairs(EVENTS) do
    self.eventsOK[ev] = pcall(frame.RegisterEvent, frame, ev) and true or false
  end
end

function BC:CheckZone()
  local dk = self:CurrentDungeon()
  if dk then
    local fresh = self.state.dk ~= dk
    self:Enter(dk)
    if fresh then ns:Fire("BOSS_DUNGEON_ENTERED", dk) end
    ns:Fire("BOSS_CARD_CHANGED")
  elseif self.state.dk then
    self:Leave()
    ns:Fire("BOSS_DUNGEON_LEFT")
  end
end

-- Midnight can hand addons "secret" values in combat-related events; never compare those.
local function Plain(v)
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, v)
    if not ok or secret then return nil end
  end
  return v
end

frame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
  a1, a2, a5 = Plain(a1), Plain(a2), Plain(a5)
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    BC:CheckZone()
  elseif event == "ENCOUNTER_START" then
    BC:OnEncounterStart(a1, a2)
  elseif event == "ENCOUNTER_END" then
    BC:OnEncounterEnd(a1, a2, a3, a4, a5)
  elseif event == "CHALLENGE_MODE_START" then
    BC:CheckZone(); BC:NewRun(); ns:Fire("BOSS_CARD_CHANGED")
  elseif event == "PLAYER_REGEN_DISABLED" then
    ns:Fire("BOSS_COMBAT", true)
  elseif event == "PLAYER_REGEN_ENABLED" then
    ns:Fire("BOSS_COMBAT", false)
  end
end)

ns:On("LOGIN", function() BC:RegisterEvents() end)
ns:On("SETTINGS_CHANGED", function() BC:ClearPlanCache() end)
