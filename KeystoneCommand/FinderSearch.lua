-- Keystone Command / FinderSearch.lua
-- Group Finder search results (groups you could apply to): a small marker on each listing
-- and a "your fit" breakdown in its tooltip. The numbers come from ListingFit.lua.
--
-- Marker (Settings > Group Finder > Groups you could join): a colored bar on the left edge
-- plus a faint tint; the bar is solid (Great/Good), dashed (Fair) or dotted (Poor) so it
-- doesn't rely on color alone. It sits on the row's edge, so it never covers the listing's
-- text or icons (or other addons' additions). Badges were tried and removed: the rows have
-- no reliably free space for them.
--
-- Blizzard functions hooked (hooksecurefunc only: nothing of Blizzard's is replaced, so
-- the protected Sign Up flow is untouched). Both are long-standing; /kc verify reports them:
--   LFGListSearchEntry_Update(button)            - a search-result row is (re)drawn
--   LFGListUtil_SetSearchEntryTooltip(tooltip, resultID) - its tooltip is built
--   LFGListApplicationDialog_Show(dialog, resultID) - the Sign Up dialog opens: a line for
--                                                    your note (shown, never typed in for you)
-- The Sign Up line also hooks the dialog frame's OnShow (HookScript, read-only): some addons
-- replace LFGListApplicationDialog_Show after we hook it (issue #4, EllesmereUIQoL), and then
-- the function hook never fires. OnShow still does, with dialog.resultID already set.
-- Rows are recycled as you scroll, so every update re-reads button.resultID.

local _, ns = ...

local FS = {}
ns.FinderSearch = FS

local LOGO = "Interface\\AddOns\\KeystoneCommand\\Media\\LogoMark"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local FRAME_BUDGET_MS = 6      -- evaluation time per frame while results stream in (at least one)

local function S() return ns.db and ns.db.settings end

local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

local function CapColor(cap)
  local L = ns.Links
  local t = L and L.CAP_TYPE and L.TYPES[L.CAP_TYPE[cap] or "utility"]
  return (t and t.color) or { 0.85, 0.85, 0.85 }
end

---------------------------------------------------------------------------
-- Marker widgets (created once per Blizzard row, reused as the row is recycled)
---------------------------------------------------------------------------
-- Blizzard's result button -> our marker frame. Kept in the addon's own weak-keyed table:
-- addon code never writes fields onto Blizzard's frames.
local buttons = setmetatable({}, { __mode = "k" })

local function EnsureMarker(button)
  if buttons[button] then return buttons[button] end
  local m = CreateFrame("Frame", nil, button)
  m:SetAllPoints()
  m:SetFrameLevel(button:GetFrameLevel() + 3)
  if m.EnableMouse then m:EnableMouse(false) end

  -- Stripe: segments so the bar can be solid, dashed or dotted.
  m.segs = {}
  m.tint = m:CreateTexture(nil, "BACKGROUND", nil, 1)
  m.tint:SetPoint("TOPLEFT"); m.tint:SetPoint("BOTTOMLEFT"); m.tint:SetWidth(220); m.tint:SetTexture(WHITE)
  buttons[button] = m
  return m
end

-- The marker drawn on a result button, if any (tests and the tooltip read it here).
function FS:MarkerFor(button) return buttons[button] end

local function HideAll(m)
  if not m then return end
  m.tint:Hide()
  for _, t in ipairs(m.segs) do t:Hide() end
end

---------------------------------------------------------------------------
-- The stripe
---------------------------------------------------------------------------
local PATTERN = { great = { 99, 0 }, good = { 99, 0 }, fair = { 5, 4 }, poor = { 2, 4 } }
local WIDTH = { great = 5, good = 4, fair = 4, poor = 3 }

local function ShowStripe(button, m, res)
  local key = res.rating.key
  local c = res.rating.color
  local h = math.floor((button:GetHeight() or 36) + 0.5)
  local on, off = PATTERN[key][1], PATTERN[key][2]
  local n, y = 0, 0
  while y < h do
    n = n + 1
    local t = m.segs[n]
    if not t then t = m:CreateTexture(nil, "OVERLAY"); t:SetTexture(WHITE); m.segs[n] = t end
    local len = math.min(on, h - y)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -y)
    t:SetSize(WIDTH[key], len); t:SetVertexColor(c[1], c[2], c[3], 1); t:Show()
    y = y + len + off
    if off == 0 then break end
  end
  for i = n + 1, #m.segs do m.segs[i]:Hide() end
  -- Faint tint fading across the row (none for Poor).
  if key ~= "poor" then
    local a = (key == "great") and 0.16 or (key == "good" and 0.12 or 0.09)
    m.tint:SetVertexColor(1, 1, 1, 1)
    local ok = m.tint.SetGradient and CreateColor and pcall(m.tint.SetGradient, m.tint, "HORIZONTAL",
      CreateColor(c[1], c[2], c[3], a), CreateColor(c[1], c[2], c[3], 0))
    if not ok then m.tint:SetVertexColor(c[1], c[2], c[3], a * 0.5) end
    m.tint:Show()
  else
    m.tint:Hide()
  end
end

local function Apply(button, res)
  local m = buttons[button]
  HideAll(m)
  local s = S()
  if not s or not res then return end
  if s.listingMarker == "off" then return end
  if s.listingHidePoor and res.rating.key == "poor" then return end
  ShowStripe(button, EnsureMarker(button), res)
end

---------------------------------------------------------------------------
-- Updating rows (cached results draw at once; new ones are evaluated a few per frame)
---------------------------------------------------------------------------
local queue, queued, working = {}, {}, false

local function Pump()
  working = false
  local done = 0
  local clock = debugprofilestop
  local start = clock and clock()
  while #queue > 0 and (done == 0 or (clock and clock() - start < FRAME_BUDGET_MS)) do
    local button = table.remove(queue, 1)
    local id = queued[button]
    queued[button] = nil
    if rawget(button, "resultID") == id then
      local ok, res = pcall(ns.ListingFit.ForResult, ns.ListingFit, id)
      Apply(button, ok and res or nil)
      done = done + 1
    end
  end
  if #queue > 0 and C_Timer then working = true; C_Timer.After(0, Pump) end
end

function FS:UpdateButton(button)
  if not button then return end
  local s = S()
  local id = rawget(button, "resultID")
  if not s or not id or s.listingMarker == "off" then HideAll(buttons[button]); return end
  local res = ns.ListingFit:Cached(id)
  if res then Apply(button, res); return end
  HideAll(buttons[button])
  if queued[button] == nil then queue[#queue + 1] = button end
  queued[button] = id
  if not working and C_Timer then working = true; C_Timer.After(0, Pump) end
end

function FS:RefreshAll()
  for button in pairs(buttons) do
    if button:IsShown() then self:UpdateButton(button) else HideAll(buttons[button]) end
  end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function Short(src)
  src = tostring(src or "")
  return (src:match("^([^,(]+)") or src):gsub("%s+$", "")
end

local function NeedText(e, withSource)
  local src = withSource and e.items and e.items[1] and e.items[1].req and Short(e.items[1].req.source)
  return Hex(CapColor(e.cap)) .. e.label .. "|r" .. ((src and src ~= "") and (" (" .. src .. ")") or "")
end

local function Join(list, f)
  local out = {}
  for i = 1, math.min(#list, 4) do out[i] = f(list[i]) end
  if #list > 4 then out[#out + 1] = "+" .. (#list - 4) .. " more" end
  return table.concat(out, ", ")
end

function FS:AddTooltip(tooltip, resultID)
  local s = S()
  if not s or s.listingTooltip == false or not tooltip or not resultID then return end
  local ok, res = pcall(ns.ListingFit.ForResult, ns.ListingFit, resultID)
  if not ok or not res then return end
  local r = res.rating
  tooltip:AddLine(" ")
  tooltip:AddLine("|T" .. LOGO .. ":14:14|t Keystone Command - your fit: " .. r.hex .. r.word .. " " .. res.score .. "|r", 1, 1, 1)
  if res.roleConflict then
    tooltip:AddLine("No open " .. (res.role == "DAMAGER" and "DPS" or res.role:lower()) .. " slot for you.", 0.93, 0.38, 0.38, true)
  end
  if #res.adds > 0 then
    tooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t You'd add: " .. Join(res.adds, function(e) return NeedText(e, true) end), 1, 1, 1, true)
  end
  if #res.maybeAdds > 0 then
    tooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t You'd add (they may already have it through a talent): "
      .. Join(res.maybeAdds, function(e) return NeedText(e) end), 0.85, 0.85, 0.85, true)
  end
  if #res.maybe > 0 then
    tooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t Not guaranteed: " .. Join(res.maybe, function(e)
      return NeedText(e) .. (e.talentOnly and " (only through a talent)" or "")
    end), 1, 1, 1, true)
  end
  -- "Group after you:" - plain status once you join (never a score); missing needs keep
  -- their sources, thin or talent-only ones are named on the "Not guaranteed" line above.
  local ga = res.groupAfter
  if ga and not res.roleConflict then
    local GC = ns.ApplicantFit.GROUP_AFTER_COLOR
    local parts = {}
    if #ga.missing > 0 then
      parts[#parts + 1] = GC.missing .. #ga.missing .. " missing:|r " .. Join(ga.missing, function(e) return NeedText(e, true) end)
    end
    if ga.thin > 0 then parts[#parts + 1] = GC.thin .. ga.thin .. " thin|r" end
    if ga.unsure > 0 then parts[#parts + 1] = GC.thin .. ga.unsure .. " not guaranteed|r" end
    if #parts == 0 then parts[1] = GC.ready .. "Ready|r" end
    tooltip:AddLine("|T" .. ns.ApplicantFit.GROUP_AFTER_ICON[ga.status] .. ":12:12|t Group after you: " .. table.concat(parts, ", "),
      1, 1, 1, true)
  end
  if #res.adds + #res.maybeAdds + #res.maybe + #res.still == 0 then
    tooltip:AddLine("Nothing this group is missing that you'd change.", 0.7, 0.7, 0.7, true)
  end
  if res.level then
    tooltip:AddLine("Affixes for +" .. res.level .. " (from the listing title). Other players' talents can't be seen.", 0.55, 0.58, 0.65, true)
  else
    tooltip:AddLine("Other players' talents can't be seen.", 0.55, 0.58, 0.65, true)
  end
  tooltip:Show()
end

---------------------------------------------------------------------------
-- Applying: a short line about you for the Sign Up dialog's note, in a small box under the
-- dialog. You copy it (Ctrl+C) and paste it yourself: nothing is typed into Blizzard's
-- dialog, so the protected Sign Up stays untouched.
---------------------------------------------------------------------------
FS.APPLY_MAX = 120

-- Your best timed (or over-time) level in this dungeon this season, or nil.
local function OwnBest(dk)
  local mapID = dk and ns.Dungeons.CHALLENGE_MAP_IDS[dk]
  if not (mapID and C_MythicPlus and C_MythicPlus.GetSeasonBestForMap) then return nil end
  local ok, intime, over = pcall(C_MythicPlus.GetSeasonBestForMap, mapID)
  if not ok then return nil end
  local lvl = function(x) return type(x) == "table" and tonumber(x.level) or nil end
  if lvl(intime) then return lvl(intime), true end
  if lvl(over) then return lvl(over), false end
  return nil
end

local function OwnRating()
  if not (C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore) then return nil end
  local ok, v = pcall(C_ChallengeMode.GetOverallDungeonScore)
  v = ok and tonumber(v) or nil
  return v and v > 0 and math.floor(v + 0.5) or nil
end

-- "Enh Shaman, 2950, timed +13 here. Brings Bloodlust, Poison dispel." nil when unknown.
function FS:ApplyLineText(resultID)
  local ok, res = pcall(ns.ListingFit.ForResult, ns.ListingFit, resultID)
  if not ok or not res then return nil end
  local UD = ns.UD
  local me = ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID()
  local spec = me and UD:GetSpec(me)
  if not spec then return nil end
  local label = UD:SpecName(me) .. " " .. UD:ClassName(spec.class)
  if ns.UI and ns.UI.ShortLabel then label = ns.UI.ShortLabel(label) end
  local head = { label }
  local rating = OwnRating()
  if rating then head[#head + 1] = tostring(rating) end
  local dk = ns.ListingFit:DungeonFor(resultID)
  local best, timed = OwnBest(dk)
  if best then head[#head + 1] = (timed and "timed +" or "+") .. best .. (timed and "" or " (over time)") .. " here" end
  local text = table.concat(head, ", ") .. "."
  local adds = {}
  for _, e in ipairs(res.adds) do adds[#adds + 1] = e.label end
  for _, e in ipairs(res.maybeAdds) do adds[#adds + 1] = e.label end
  if #adds > 0 then
    local line = text .. " Brings " .. table.concat(adds, ", ") .. "."
    while #line > FS.APPLY_MAX and #adds > 1 do
      table.remove(adds)
      line = text .. " Brings " .. table.concat(adds, ", ") .. "."
    end
    text = line
  end
  return text:sub(1, FS.APPLY_MAX)
end

function FS:BuildApplyBox(dialog)
  if self.applyBox then return self.applyBox end
  local K = ns.UI and ns.UI.Kit
  local f = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
  f:SetSize(340, 64)
  f:SetPoint("TOP", dialog, "BOTTOM", 0, -4)
  if K then K.Skin(f, K.C.bg, K.C.border); K.Accent(f, "border") end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", 8, -7)
  f.title:SetText("|T" .. LOGO .. ":12:12|t For your note (Ctrl+C, then paste):")
  local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  box:SetSize(320, 22); box:SetPoint("TOPLEFT", 12, -26)
  box:SetAutoFocus(false)
  box:SetScript("OnTextChanged", function(b, user) if user then b:SetText(f.value or ""); b:HighlightText() end end)
  box:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
  box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
  f.box = box
  self.applyBox = f
  return f
end

function FS:ShowApplyLine(dialog, resultID)
  local s = S()
  if not s or s.applyLine == false or not dialog then
    if self.applyBox then self.applyBox:Hide() end
    return
  end
  local text = resultID and self:ApplyLineText(resultID)
  local f = self:BuildApplyBox(dialog)
  if not text then f:Hide(); return end
  f.value = text
  f.box:SetText(text); f.box:SetCursorPosition(0)
  f:Show()
end

-- The listing the Sign Up dialog is for: the dialog's own resultID (set before it shows),
-- else the search panel's selected result. Read only; nil when neither is readable.
function FS:DialogResultID(dialog)
  local id = dialog and type(dialog) == "table" and rawget(dialog, "resultID")
  if type(id) == "number" then return id end
  local lf = rawget(_G, "LFGListFrame")
  local panel = type(lf) == "table" and rawget(lf, "SearchPanel")
  id = type(panel) == "table" and rawget(panel, "selectedResult")
  return type(id) == "number" and id or nil
end

-- The globals FS hooks, with the feature each one drives (Verify reports them).
FS.HOOKED_GLOBALS = {
  { name = "LFGListSearchEntry_Update", feature = "listing markers in search results" },
  { name = "LFGListUtil_SetSearchEntryTooltip", feature = "your fit in listing tooltips" },
  { name = "LFGListApplicationDialog_Show", feature = "the Sign Up note line" },
}

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
function FS:Hook()
  local dialog = rawget(_G, "LFGListApplicationDialog")
  if not self.dialogHooked and type(dialog) == "table" and dialog.HookScript then
    local ok = pcall(dialog.HookScript, dialog, "OnShow", function(d) FS:ShowApplyLine(d, FS:DialogResultID(d)) end)
    self.dialogHooked = ok or nil
  end
  if not hooksecurefunc then return end
  if not self.rowsHooked and type(LFGListSearchEntry_Update) == "function" then
    hooksecurefunc("LFGListSearchEntry_Update", function(button) FS:UpdateButton(button) end)
    self.rowsHooked = true
  end
  if not self.tipHooked and type(LFGListUtil_SetSearchEntryTooltip) == "function" then
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, resultID) FS:AddTooltip(tooltip, resultID) end)
    self.tipHooked = true
  end
  if not self.applyHooked and type(LFGListApplicationDialog_Show) == "function" then
    hooksecurefunc("LFGListApplicationDialog_Show", function(dialog, resultID) FS:ShowApplyLine(dialog, resultID) end)
    self.applyHooked = true
  end
end

-- The Group Finder UI is load-on-demand on some clients: try at login and whenever an
-- addon finishes loading until every hook is in.
local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "ADDON_LOADED")
pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  if not (FS.rowsHooked and FS.tipHooked and FS.applyHooked and FS.dialogHooked) then FS:Hook() end
end)
if ns.On then
  ns:On("SETTINGS_CHANGED", function() FS:RefreshAll() end)
  ns:On("AFFIXES_CHANGED", function() FS:RefreshAll() end)
end
