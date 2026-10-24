-- Minimal WoW API stub for headless testing (LuaJIT = Lua 5.1 semantics).
local Frame = {}
local frameMT
local function newFrame(name)
  local f = { _shown = true, _scripts = {}, _events = {}, _text = "", _h = 100, _w = 100, _scroll = 0, _name = name }
  setmetatable(f, frameMT)
  if name then _G[name] = f end
  ALLFRAMES = ALLFRAMES or {}; table.insert(ALLFRAMES, f)
  return f
end
frameMT = {
  __index = function(t, k)
    local v = Frame[k]
    if v then return v end
    if k == "cmLinks" then return nil end
    return function() return nil end
  end,
}
function Frame:Show() self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
function Frame:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:SetAlpha(a) rawset(self, "_alpha", a) end
function Frame:GetAlpha() return rawget(self, "_alpha") or 1 end
function Frame:SetScript(k, fn) self._scripts[k] = fn end
function Frame:GetScript(k) return self._scripts[k] end
function Frame:RegisterEvent(e) if e == "BOGUS" then error("unknown event") end self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:UnregisterAllEvents() self._events = {} end
function Frame:CreateFontString() return newFrame() end
function Frame:CreateTexture() return newFrame() end
function Frame:SetText(t) self._text = t end
function Frame:GetText() return self._text end
function Frame:GetStringHeight() return 12 end
function Frame:GetHeight() return self._h end
function Frame:SetHeight(h) self._h = h end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:GetWidth() return self._w end
function Frame:GetVerticalScroll() return self._scroll end
function Frame:SetVerticalScroll(v) self._scroll = v end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:GetCenter() return 0, 0 end
function Frame:GetEffectiveScale() return 1 end
function Frame:Click(btn) if self._scripts.OnClick then self._scripts.OnClick(self, btn or "LeftButton") end end
-- Animation groups: built like frames; Play records it and finishes at once (IsPlaying false).
function Frame:CreateAnimationGroup() return newFrame() end
function Frame:CreateAnimation() return newFrame() end
function Frame:Play() rawset(self, "_played", (rawget(self, "_played") or 0) + 1) end
function Frame:Stop() rawset(self, "_stopped", true) end
function Frame:IsPlaying() return false end

function CreateFrame(_, name) local f = newFrame(name); f._shown = true; return f end
UIParent = newFrame("UIParent")
Minimap = newFrame("Minimap")
GameTooltip = newFrame("GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) PRINTED = (PRINTED or "") .. m .. "\n" end }
UISpecialFrames = {}
SlashCmdList = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
function Mixin(o) return o end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetTime() return os.clock() end
function time() return os.time() end
date = os.date
function InCombatLockdown() return false end
function geterrorhandler() return function(e) error(e) end end

-- Timers: queued; flushed by the test with RunTimers()
TIMERS = {}
C_Timer = {
  After = function(_, fn) table.insert(TIMERS, { fn = fn }) end,
  NewTimer = function(_, fn) local t = { fn = fn }; function t:Cancel() self.canceled = true end; table.insert(TIMERS, t); return t end,
}
function RunTimers()
  for _ = 1, 20 do
    if #TIMERS == 0 then return end
    local list = TIMERS; TIMERS = {}
    for _, t in ipairs(list) do if not t.canceled then t.fn() end end
  end
end

-- Group simulation
ROSTER = {}       -- unit -> { guid, name, class, spec, role }
INSPECTABLE = {}  -- guid -> spec revealed by inspect
function UnitExists(u) return ROSTER[u] ~= nil end
function UnitGUID(u) return ROSTER[u] and ROSTER[u].guid end
function UnitClass(u) local r = ROSTER[u]; if r then return r.class, r.class end end
function UnitName(u) local r = ROSTER[u]; if r then return r.name, nil end end
function UnitIsUnit(a, b) return a == b or (ROSTER[a] and ROSTER[b] and ROSTER[a].guid == ROSTER[b].guid) end
function UnitGroupRolesAssigned(u) return ROSTER[u] and ROSTER[u].role or "NONE" end
function IsInRaid() return false end
function IsInGroup() local n = 0 for _ in pairs(ROSTER) do n = n + 1 end return n > 1 end
function GetNumGroupMembers() local n = 0 for _ in pairs(ROSTER) do n = n + 1 end return n end
function GetNormalizedRealmName() return "Realm" end
INSPECT_CACHE = {}
function GetInspectSpecialization(u) local r = ROSTER[u]; return r and INSPECT_CACHE[r.guid] or 0 end
function CanInspect(u) return ROSTER[u] ~= nil end
NOTIFIED = {}
function NotifyInspect(u) table.insert(NOTIFIED, u) end
function ClearInspectPlayer() end
C_SpecializationInfo = {
  GetSpecialization = function() return 1 end,
  GetSpecializationInfo = function() return ROSTER.player and ROSTER.player.spec end,
}
LISTING = nil
C_LFGList = {
  HasActiveEntryInfo = function() return LISTING ~= nil end,
  -- Each distinct listing name gets its own activity ID (like the real client).
  GetActiveEntryInfo = function()
    ACTIVITY_BY_NAME = ACTIVITY_BY_NAME or {}
    ACTIVITY_NAMES = ACTIVITY_NAMES or {}
    local id = ACTIVITY_BY_NAME[LISTING]
    if not id then id = 5000 + #ACTIVITY_NAMES + 1; ACTIVITY_NAMES[#ACTIVITY_NAMES + 1] = LISTING; ACTIVITY_BY_NAME[LISTING] = id end
    return { activityIDs = { id }, requiredDungeonScore = LISTING_MIN_RATING, requiredItemLevel = LISTING_MIN_ILVL }
  end,
  GetActivityInfoTable = function(id) return { fullName = ACTIVITY_NAMES[id - 5000] } end,
  GetApplicants = function() local ids = {} for id in pairs(APPLICANTS) do ids[#ids+1] = id end table.sort(ids) return ids end,
  GetApplicantInfo = function(id) local a = APPLICANTS[id]; return a and { numMembers = #a, applicationStatus = (APPLICANT_STATUS and APPLICANT_STATUS[id]) or "applied" } end,
  GetApplicantMemberInfo = function(id, m)
    local x = APPLICANTS[id][m]
    local score = x.score or 2500
    if x.noScore then score = nil end
    local ilvl = x.ilvl or 600
    if x.noIlvl then ilvl = nil end
    return x.name, x.class, x.class, 90, ilvl, 0, x.role == "TANK", x.role == "HEALER", x.role == "DAMAGER", x.role, nil, score, 0, 0, 0, x.spec, x.leaver and true or false
  end,
}
APPLICANTS = { [7] = { { name = "Applicant-Realm", class = "SHAMAN", role = "HEALER", spec = 264, score = 2900 } } }
PVEFrame = CreateFrame("Frame", "PVEFrame"); PVEFrame._shown = false
function Frame:HookScript(k, fn) local old = self._scripts[k]; self._scripts[k] = function(...) if old then old(...) end fn(...) end end
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

KNOWN_BY_NAME = { ["Kick"] = 1766 }
C_Spell = {
  DoesSpellExist = function(id) return id ~= nil and id ~= 0 and id ~= 999999 end,
  GetSpellTexture = function(id) return 1000000 + id end,
  GetSpellInfo = function(x) if type(x) == "string" and KNOWN_BY_NAME[x] then return { spellID = KNOWN_BY_NAME[x] } end end,
  GetSpellLink = function(id) return "|cff71d5ff|Hspell:" .. id .. "|h[x]|h|r" end,
}
DUNGEON_MAPS = {
  [588] = { "Altar of Fangs", 7001, 2901 }, [249] = { "Kings' Rest", 7002, 1762 }, [584] = { "The Blinding Vale", 7003, 2902 },
  [585] = { "Voidscar Arena", 7004, 2903 }, [586] = { "Den of Nalorakk", 7005, 2904 }, [587] = { "Murder Row", 7006, 2905 },
  [399] = { "Ruby Life Pools", 7007, 2521 }, [250] = { "Temple of Sethraliss", 7008, 1877 },
}
C_ChallengeMode = {
  GetMapTable = function() local t = {} for id in pairs(DUNGEON_MAPS) do t[#t + 1] = id end table.sort(t) return t end,
  GetMapUIInfo = function(id) local m = DUNGEON_MAPS[id]; if m then return m[1], id, 1800, m[2], nil, m[3] end end,
}

function Frame:SetTextColor(r, g, b) self._color = { r, g, b } end
function Frame:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
function Frame:SetScale(v) self._scale = v end
function Frame:GetScale() return self._scale or 1 end
function GetCursorPosition() return 0, 0 end
function Frame:GetFrameLevel() return 1 end
function Frame:SetPoint(...) rawset(self, "_point", { ... }) end
function Frame:ClearAllPoints() self._point = nil end
function Frame:GetLeft() return rawget(self, "_left") end
function Frame:GetBottom() return rawget(self, "_bottom") end
function Frame:GetRight() return rawget(self, "_right") end
function Frame:GetTop() return rawget(self, "_top") end
function Frame:StartMoving() self._moving = true end
function Frame:StopMovingOrSizing() self._moving = false end

-- Keystone / zone
OWNED_KEY = nil   -- challenge mapID of the keystone in your bags
OWNED_LEVEL = nil
ACTIVE_CHALLENGE = nil
INSTANCE = nil    -- { name, type }
C_MythicPlus = {
  GetOwnedKeystoneChallengeMapID = function() return OWNED_KEY end,
  GetOwnedKeystoneLevel = function() return OWNED_LEVEL end,
}
C_ChallengeMode.GetActiveChallengeMapID = function() return ACTIVE_CHALLENGE end
function GetInstanceInfo()
  if INSTANCE then return INSTANCE[1], INSTANCE[2] end
  return "Dornogal", "none"
end
SENT = {}
function SendChatMessage(msg, channel) table.insert(SENT, { msg = msg, channel = channel }) end
C_Timer = C_Timer
-- Affixes
CURRENT_AFFIXES = {}   -- list of affix IDs
AFFIX_INFO = { [9] = "Tyrannical", [10] = "Fortified", [147] = "Xal'atath's Guile", [158] = "Xal'atath's Bargain: Voidbound",
  [148] = "Xal'atath's Bargain: Ascendant", [162] = "Xal'atath's Bargain: Devour", [999] = "Mystery Affix", [777] = "Xal'atath's Bargain: Pulsar" }
C_MythicPlus.GetCurrentAffixes = function() local t = {} for _, id in ipairs(CURRENT_AFFIXES) do t[#t + 1] = { id = id, seasonID = 17 } end return t end
C_MythicPlus.RequestCurrentAffixes = function() end
-- End-of-run reward item level for a key level (fake numbers: weekly 300 + L, end of run 290 + L).
C_MythicPlus.GetRewardLevelForDifficultyLevel = function(l) return 300 + l, 290 + l end
C_ChallengeMode.GetAffixInfo = function(id) return AFFIX_INFO[id], "desc", 4000 + id end
-- Keystone run
ACTIVE_KEY_LEVEL, ACTIVE_KEY_AFFIXES = nil, {}
COMPLETION = nil   -- table returned by GetChallengeCompletionInfo
DEATHS = 0
C_ChallengeMode.GetActiveKeystoneInfo = function() return ACTIVE_KEY_LEVEL, ACTIVE_KEY_AFFIXES, true end
C_ChallengeMode.GetChallengeCompletionInfo = function() return COMPLETION end
C_ChallengeMode.GetDeathCount = function() return DEATHS, DEATHS * 5 end
function Frame:SetFont(_, size) rawset(self, "_fontSize", size) end
function Frame:StartSizing() rawset(self, "_sizing", true) end
function Frame:SetWidth(w) rawset(self, "_w", w) end
function Frame:Enable() rawset(self, "_disabled", false) end
function Frame:Disable() rawset(self, "_disabled", true) end
function Frame:IsEnabled() return not rawget(self, "_disabled") end
function Frame:GetVerticalScroll() return rawget(self, "_scroll") or 0 end
TICKERS = {}
C_Timer.NewTicker = function(_, fn) local t = { fn = fn }; function t:Cancel() self.canceled = true end; table.insert(TICKERS, t); return t end
function TickAll() for _, t in ipairs(TICKERS) do if not t.canceled then t.fn() end end end
HOOKS = {}
function hooksecurefunc(name, fn) HOOKS[name] = fn end
NOW = 1000
function GetTime() return NOW end
function Frame:SetPoint(...)
  rawset(self, "_point", { ... })
  local pts = rawget(self, "_points") or {}
  pts[#pts + 1] = { ... }
  rawset(self, "_points", pts)
end
function Frame:ClearAllPoints() rawset(self, "_point", nil); rawset(self, "_points", {}) end

-- Strata and frame levels are remembered so tests can check how windows stack.
function Frame:SetFrameStrata(v) rawset(self, "_strata", v) end
function Frame:GetFrameStrata() return rawget(self, "_strata") or "MEDIUM" end
function Frame:SetFrameLevel(v) rawset(self, "_level", v) end
function Frame:GetFrameLevel() return rawget(self, "_level") or 1 end
