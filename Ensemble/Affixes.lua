-- Ensemble / Affixes.lua
-- Weekly Mythic+ affix awareness: reads this week's affixes from the game and adds the
-- utility they call for to the dungeon checks, filtered by the key level.
--
-- DATA PROVENANCE: Midnight Season 2 (12.1) affix list and key-level brackets from
-- Icy Veins' Season 2 Mythic+ guide and Playnews' 12.1 affix overview (August 2026):
--   +2-+4  Lindormi's Guidance (newcomer help; no utility demands)
--   +5-+11 one Xal'atath's Bargain per week: Ascendant, Voidbound, Pulsar or Devour
--   +7     Fortified or Tyrannical (weekly); +10 both
--   +12    Xal'atath's Guile replaces the Bargain (deaths cost time)
-- Affix IDs are the long-standing ones (Tyrannical 9, Fortified 10) and The War Within's
-- Xal'atath affixes; every affix is ALSO matched by name, so a changed ID still works on
-- English clients. Confirmed in 12.1.0 (build 69933) by /ens verify: Lindormi's Guidance 165,
-- Ascendant 148, Tyrannical 9, Fortified 10, Xal'atath's Guile 147.
-- Ascendant handling (stops, displacements, interrupts or dispels; the orbs' shield is too
-- big to kill) is as Icy Veins' Season 2 Mythic+ guide states it (rechecked October 2026).
local _, ns = ...

local AF = {}
ns.Affixes = AF

local V = "verified"   -- an affix requirement a guide doesn't state outright: "needs_verification"

-- bracket: "bargain" (+5..+11), "weekly" (Fortified/Tyrannical), "guile" (+12), "low" (+2..+4)
AF.DEFS = {
  { key = "VOIDBOUND", ids = { 158 }, match = "voidbound", bracket = "bargain",
    label = "Xal'atath's Bargain: Voidbound",
    note = "Swap to the Voidbound Emissary and burn it; kick every Dark Prayer.",
    requirements = {
      { need = "interrupt", alt = { "stop" }, severity = "high", minProviders = 2,
        source = "Dark Prayer (Voidbound Emissary)", note = "Every cast must be stopped.", confidence = V },
    } },
  { key = "ASCENDANT", ids = { 148 }, match = "ascendant", bracket = "bargain",
    label = "Xal'atath's Bargain: Ascendant",
    note = "The orbs' absorb shield makes killing them impractical: stop, displace or dispel instead.",
    requirements = {
      { need = "stop", alt = { "knockback", "interrupt" }, severity = "medium", minProviders = 2,
        source = "Ascendant orbs", note = "Plan stops, displacements, interrupts or dispels for the orbs.", confidence = V },
    } },
  { key = "PULSAR", ids = { 162 }, match = "pulsar", bracket = "bargain",
    label = "Xal'atath's Bargain: Pulsar",
    note = "Run to each other (or stack) to clear Pulsars. Positioning only - no utility check.",
    requirements = {} },
  { key = "DEVOUR", ids = { 160 }, match = "devour", bracket = "bargain",
    label = "Xal'atath's Bargain: Devour",
    note = "Healer dispels only cover two of the five Devours: dispel yourselves where you can (personal cleanses, racials such as Stoneform).",
    requirements = {} },
  { key = "FORTIFIED", ids = { 10 }, match = "fortified", bracket = "weekly",
    label = "Fortified",
    note = "Trash hits harder and lives longer: crowd control and kicks matter more; plan Bloodlust around trash.",
    requirements = {
      { need = "aoe_stop", severity = "medium", minProviders = 2,
        source = "Fortified trash packs", note = "More AoE stops for big pulls.", confidence = V },
    } },
  { key = "TYRANNICAL", ids = { 9 }, match = "tyrannical", bracket = "weekly",
    label = "Tyrannical",
    note = "Bosses hit harder and live longer: save Bloodlust and group cooldowns for dangerous bosses.",
    requirements = {
      { need = "group_defensive", severity = "medium", minProviders = 2,
        source = "Tyrannical bosses", note = "Group cooldowns for boss damage.", confidence = V },
    } },
  { key = "GUILE", ids = { 147 }, match = "guile", bracket = "guile",
    label = "Xal'atath's Guile",
    note = "Each death removes 15 seconds from the timer: coordinate defensives and healer cooldowns.",
    requirements = {
      { need = "group_defensive", severity = "medium", minProviders = 2,
        source = "Xal'atath's Guile (deaths cost time)", note = "Deaths are much more punishing.", confidence = V },
      { need = "external_defensive", severity = "medium", minProviders = 1,
        source = "Xal'atath's Guile (deaths cost time)", note = "Externals to save players from dying.", confidence = V },
    } },
  { key = "LINDORMI", ids = { 165 }, match = "lindormi", bracket = "low",
    label = "Lindormi's Guidance",
    note = "Highlighted weaker monsters count toward Enemy Forces; deaths don't cost time. No utility check.",
    requirements = {} },
}

local byID, byKey = {}, {}
for _, d in ipairs(AF.DEFS) do
  byKey[d.key] = d
  for _, id in ipairs(d.ids) do byID[id] = d end
end

local function Match(id, name)
  if id and byID[id] then return byID[id] end
  local n = name and name:lower() or ""
  if n == "" then return nil end
  for _, d in ipairs(AF.DEFS) do
    if n:find(d.match, 1, true) then return d end
  end
  return nil
end
AF.Match = Match

---------------------------------------------------------------------------
-- This week's affixes, in the game's order.
-- C_MythicPlus.GetCurrentAffixes() -> { { id, seasonID } }, C_ChallengeMode.GetAffixInfo(id)
-- -> name, description, fileDataID. Both long-standing; pcall-guarded.
---------------------------------------------------------------------------
local current, currentSig
function AF:Refresh()
  current, currentSig = nil, nil
  if not (C_MythicPlus and C_MythicPlus.GetCurrentAffixes) then return end
  local ok, list = pcall(C_MythicPlus.GetCurrentAffixes)
  if not ok or type(list) ~= "table" or #list == 0 then return end
  local out, ids = {}, {}
  for _, a in ipairs(list) do
    local id = type(a) == "table" and (a.id or a.affixID) or a
    if type(id) == "number" then
      local name, desc, icon
      if C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
        local okI, n, d, f = pcall(C_ChallengeMode.GetAffixInfo, id)
        if okI then name, desc, icon = n, d, f end
      end
      out[#out + 1] = { id = id, name = name, description = desc, icon = icon, def = Match(id, name) }
      ids[#ids + 1] = id
    end
  end
  if #out > 0 then current, currentSig = out, table.concat(ids, ",") end
end

function AF:Current()
  if not current then self:Refresh() end
  return current or {}
end

function AF:Signature()
  if not current then self:Refresh() end
  return currentSig or "none"
end

-- Affixes active at `level` (nil = unknown, treated as +10 and flagged).
-- Returns list of { id, name, icon, def, label }, plus `assumed` = true when level was unknown.
AF.ASSUMED_LEVEL = 10
-- `ids` (optional): a specific affix list (e.g. a recorded run's) instead of this week's.
local function FromIDs(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local name, icon
    if C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
      local ok, n, _, f = pcall(C_ChallengeMode.GetAffixInfo, id)
      if ok then name, icon = n, f end
    end
    out[#out + 1] = { id = id, name = name, icon = icon, def = Match(id, name) }
  end
  return out
end

function AF:Active(level, ids)
  local assumed = level == nil
  level = level or self.ASSUMED_LEVEL
  local out, weeklySeen = {}, 0
  for _, a in ipairs(ids and FromIDs(ids) or self:Current()) do
    local d = a.def
    local on
    if not d then
      on = true                         -- unknown affix: show it, no requirements
    elseif d.bracket == "low" then on = level <= 4
    elseif d.bracket == "bargain" then on = level >= 5 and level <= 11
    elseif d.bracket == "guile" then on = level >= 12
    elseif d.bracket == "weekly" then
      -- The game lists this week's Fortified/Tyrannical first (from +7); the other joins at +10.
      weeklySeen = weeklySeen + 1
      on = (weeklySeen == 1 and level >= 7) or (weeklySeen > 1 and level >= 10)
    end
    if on then
      out[#out + 1] = { id = a.id, name = a.name, icon = a.icon, def = d,
        label = (d and d.label) or a.name or ("Affix " .. tostring(a.id)) }
    end
  end
  return out, assumed
end

-- Requirement rows for the dungeon check, shaped like DungeonData requirements.
local reqCache = {}
function AF:Requirements(dungeonKey, level, ids)
  local sig = tostring(dungeonKey) .. "|" .. tostring(level) .. "|" .. (ids and table.concat(ids, ",") or self:Signature())
  if reqCache[sig] then return reqCache[sig] end
  local out = {}
  local active = self:Active(level, ids)
  for _, a in ipairs(active) do
    local d = a.def
    if d then
      for i, r in ipairs(d.requirements) do
        local req = {}
        for k, v in pairs(r) do req[k] = v end
        req.id = "AFX_" .. d.key .. "_" .. i
        req.dungeon = dungeonKey
        req.category = "affixes"
        req.affix = d.label
        if ns.UD and not ns.UD.CAP_INFO[req.need] then req.invalid = true end
        if req.alt then
          for _, alt in ipairs(req.alt) do if ns.UD and not ns.UD.CAP_INFO[alt] then req.invalid = true end end
        end
        out[#out + 1] = req
      end
    end
  end
  reqCache[sig] = out
  return out
end

-- Key level used for affixes: the Applicants tab's override, else your own keystone's
-- level when it is for this dungeon, else unknown (nil).
function AF:KeyLevel(dungeonKey)
  if ns.state and ns.state.keyLevelOverride then return ns.state.keyLevelOverride end
  if dungeonKey and ns.OwnKeystoneDungeon then
    local key, level = ns:OwnKeystoneDungeon()
    if key == dungeonKey and level then return level end
  end
  return nil
end

-- Refresh when the game says the affixes changed (weekly reset, or data arriving).
local f = CreateFrame("Frame")
for _, ev in ipairs({ "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_MAPS_UPDATE" }) do
  pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" and C_MythicPlus and C_MythicPlus.RequestCurrentAffixes then
    pcall(C_MythicPlus.RequestCurrentAffixes)
  end
  local before = currentSig
  AF:Refresh()
  if currentSig ~= before then
    reqCache = {}
    if ns.Fire then ns:Fire("AFFIXES_CHANGED"); ns:Fire("DUNGEON_CHANGED") end
  end
end)
