-- Ensemble / UI.lua
-- All frames: main window (Composition / Applicants / Dungeon / Plan / History / Settings),
-- Group Finder applicant panel, menus, minimap button.
-- Everything is a plain, non-secure frame; no secure templates, no protected calls, so the
-- window works during combat lockdown. Art is Blizzard's own textures only.

local _, ns = ...

local UI = {}
ns.UI = UI

local Util = ns.Util
local UD, DD, Analysis -- resolved at build time

---------------------------------------------------------------------------
-- Style
---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local C = {
  bg      = { 0.055, 0.059, 0.071, 0.97 },
  header  = { 0.078, 0.082, 0.098, 1 },
  panel   = { 0.090, 0.095, 0.114, 1 },
  btn     = { 0.125, 0.133, 0.157, 1 },
  btnHot  = { 0.165, 0.176, 0.208, 1 },
  border  = { 0.165, 0.176, 0.212, 1 },
  accent  = { 0.494, 0.718, 1.000, 1 },
  text    = { 0.910, 0.918, 0.941, 1 },
  muted   = { 0.580, 0.600, 0.659, 1 },
  good    = { 0.380, 0.800, 0.470, 1 },
  warn    = { 0.960, 0.720, 0.290, 1 },
  bad     = { 0.930, 0.380, 0.380, 1 },
}
local HEX = {
  good = "|cff61cc78", warn = "|cfff5b84a", bad = "|cffee6161", muted = "|cff9499a8",
  accent = "|cff7eb7ff", text = "|cffe8eaf0",
}
---------------------------------------------------------------------------
-- Theme: one accent color, user-chosen (hex / wheel / preset / class color).
-- Everything that shows the accent is registered here so a theme change recolors it live;
-- text built at refresh time reads C.accent / HEX.accent directly.
---------------------------------------------------------------------------
local DEFAULT_ACCENT = "7EB7FF"
UI.PRESETS = {
  { name = "Frost",    hex = "7EB7FF" }, { name = "Arcane",   hex = "A78BFA" },
  { name = "Fel",      hex = "7CE36A" }, { name = "Emerald",  hex = "3DDC97" },
  { name = "Tide",     hex = "2DD4BF" }, { name = "Gold",     hex = "FFD100" },
  { name = "Amber",    hex = "F5A524" }, { name = "Blood",    hex = "E5484D" },
  { name = "Rose",     hex = "F472B6" }, { name = "Mono",     hex = "D4D8E2" },
}

local function HexToRGB(hex)
  hex = tostring(hex or ""):gsub("^#", "")
  if not hex:match("^%x%x%x%x%x%x$") then return nil end
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
local function RGBToHex(r, g, b)
  local function c(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
  return string.format("%02X%02X%02X", c(r), c(g), c(b))
end
UI.HexToRGB, UI.RGBToHex = HexToRGB, RGBToHex

local accentRegistry = {}
local function PaintAccent(e)
  local a = C.accent
  if e.kind == "text" then e.obj:SetTextColor(a[1], a[2], a[3], e.alpha or 1)
  elseif e.kind == "tex" then e.obj:SetColorTexture(a[1], a[2], a[3], e.alpha or 1)
  elseif e.kind == "border" then e.obj:SetBackdropBorderColor(a[1], a[2], a[3], e.alpha or 1)
  elseif e.kind == "fn" then e.obj(a) end
end
-- Register an object that shows the accent color (kind: text / tex / border / fn).
local function Accent(obj, kind, alpha)
  local e = { obj = obj, kind = kind, alpha = alpha }
  accentRegistry[#accentRegistry + 1] = e
  PaintAccent(e)
  return obj
end

-- The accent color currently configured (class color, saved hex, or default).
function UI:CurrentAccent()
  local t = ns.db and ns.db.settings.theme or {}
  if t.classColor and UnitClass then
    local _, classFile = UnitClass("player")
    if classFile then
      local r, g, b = Util.ClassColor(classFile)
      return r, g, b
    end
  end
  local r, g, b = HexToRGB(t.hex)
  if not r then r, g, b = HexToRGB(DEFAULT_ACCENT) end
  return r, g, b
end

function UI:ApplyTheme(noRefresh)
  local r, g, b = self:CurrentAccent()
  C.accent[1], C.accent[2], C.accent[3] = r, g, b
  HEX.accent = "|cff" .. RGBToHex(r, g, b):lower()
  for _, e in ipairs(accentRegistry) do PaintAccent(e) end
  if self.tabButtons then
    for k, tb in pairs(self.tabButtons) do tb:SetActive(k == self.currentTab) end
  end
  if not noRefresh then self:QueueRefresh(); self:QueueFinderRefresh() end
end

-- Status = texture + word, never color alone (color-blind safe).
local TEX_OK   = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local TEX_WAIT = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t"
local TEX_NO   = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t"

local W, H = 952, 630
local COL_W = 300

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
local function Skin(f, bg, border)
  if not f.SetBackdrop and BackdropTemplateMixin then Mixin(f, BackdropTemplateMixin) end
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(unpack(bg or C.panel))
  f:SetBackdropBorderColor(unpack(border or C.border))
end

-- Text size: every font is created through SetFontSize, which records the design size
-- and applies the user's text-size setting (Settings > Appearance, 80-125%).
-- Independent of the window size: resizing gives more room, not bigger text.
local fontRegistry = setmetatable({}, { __mode = "k" })
local function FontPx(size)
  local pct = (ns.db and ns.db.settings and tonumber(ns.db.settings.textSize)) or 100
  return math.floor((size or 12) * pct / 100 + 0.5)
end
-- Labels fitted to their box (issue #16): the player's text size when the label fits, else one
-- pixel smaller at a time, never below the design size; still too long at the design size, it's
-- cut as before. `fs.cmFit()` returns the room in pixels. Measured with the unbounded width
-- (the bounded one reports an already-cut label). Refit on SetText, on the box's size change
-- and on a text-size change; `cmFitKey` skips the work when nothing changed.
local fitLabels = setmetatable({}, { __mode = "k" })
local function FitLabel(fs)
  if not (fs and fs.cmFit) then return end
  local design = fs.cmSize or 12
  local size = FontPx(design)
  local avail = fs.cmFit()
  local key = tostring(fs:GetText()) .. "\0" .. tostring(avail) .. "\0" .. size
  if fs.cmFitKey == key then return end
  fs.cmFitKey = key
  fs:SetFont(FONT, size, "")
  if type(avail) ~= "number" or avail <= 0 or size <= design then return end
  while size > design do
    local okW, w = pcall(fs.GetUnboundedStringWidth, fs)
    if not okW or type(w) ~= "number" or w <= avail then break end
    size = size - 1
    fs:SetFont(FONT, size, "")
  end
end
local function MakeFit(fs, room)
  fs.cmFit = room
  fitLabels[fs] = true
  local orig = fs.SetText
  fs.SetText = function(self, t) orig(self, t); FitLabel(self) end
end
UI.FitLabel, UI.MakeFit = FitLabel, MakeFit

local function SetFontSize(obj, size)
  obj.cmSize = size or 12
  fontRegistry[obj] = true
  obj:SetFont(FONT, FontPx(obj.cmSize), "")
  if obj.cmFit then obj.cmFitKey = nil; FitLabel(obj) end
end
UI.FontPx = FontPx

local function Text(parent, size, color, justify, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  SetFontSize(fs, size or 12)
  fs:SetTextColor(unpack(color or C.text))
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(true)
  return fs
end

local function Panel(parent)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  Skin(p, C.panel, C.border)
  return p
end

local function Button(parent, label, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  Skin(b, C.btn, C.border)
  b.text = Text(b, 12, C.text, "CENTER")
  b.text:SetPoint("LEFT", 6, 0); b.text:SetPoint("RIGHT", -6, 0)
  b.text:SetWordWrap(false)
  b.cmInset = 12   -- label room = width minus the side insets (a Dropdown changes it)
  MakeFit(b.text, function() return (b:GetWidth() or 0) - b.cmInset end)
  b.text:SetText(label or "")
  b:HookScript("OnSizeChanged", function() FitLabel(b.text) end)
  b:SetScript("OnEnter", function(self)
    self:SetBackdropColor(unpack(C.btnHot))
    if self.tooltip and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    if not self.active then self:SetBackdropColor(unpack(C.btn)) end
    if GameTooltip then GameTooltip:Hide() end
  end)
  if onClick then b:SetScript("OnClick", onClick) end
  function b:SetActive(on)
    self.active = on
    self:SetBackdropColor(unpack(on and C.btnHot or C.btn))
    self:SetBackdropBorderColor(unpack(on and C.accent or C.border))
  end
  return b
end

-- Flat header tab: muted text, accent underline when active.
local function Tab(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b.text = Text(b, 12, C.muted, "CENTER")
  b.text:SetPoint("CENTER", 0, 1)
  b.text:SetWordWrap(false)
  b.text:SetText(label)
  b:SetSize(math.max(64, (b.text:GetStringWidth() or 60) + 24), 40)
  b.line = b:CreateTexture(nil, "OVERLAY")
  b.line:SetPoint("BOTTOMLEFT", 8, 0); b.line:SetPoint("BOTTOMRIGHT", -8, 0); b.line:SetHeight(2)
  Accent(b.line, "tex")
  b.line:Hide()
  b:SetScript("OnEnter", function(self) if not self.active then self.text:SetTextColor(unpack(C.text)) end end)
  b:SetScript("OnLeave", function(self) if not self.active then self.text:SetTextColor(unpack(C.muted)) end end)
  b:SetScript("OnClick", onClick)
  function b:SetActive(on)
    self.active = on
    self.text:SetTextColor(unpack(on and C.text or C.muted))
    self.line:SetShown(on and true or false)
  end
  return b
end

-- Small flat text button (no box until hovered).
local function FlatButton(parent, label, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  b:SetBackdropColor(0, 0, 0, 0); b:SetBackdropBorderColor(0, 0, 0, 0)
  b.text = Text(b, 11, C.muted, "CENTER"); b.text:SetPoint("CENTER")
  MakeFit(b.text, function() return (b:GetWidth() or 0) - 6 end)
  b.text:SetText(label or "")
  b:HookScript("OnSizeChanged", function() FitLabel(b.text) end)
  b:SetScript("OnEnter", function(self)
    if self.IsEnabled and not self:IsEnabled() then return end
    self:SetBackdropColor(unpack(C.btn)); self:SetBackdropBorderColor(unpack(C.border))
    self.text:SetTextColor(unpack(C.text))
    if self.tooltip and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true); GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0, 0, 0, 0); self:SetBackdropBorderColor(0, 0, 0, 0)
    self.text:SetTextColor(unpack(C.muted))
    if GameTooltip then GameTooltip:Hide() end
  end)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

-- Shared look for windows defined in other files (BossWindow.lua).
UI.Kit = { C = C, HEX = HEX, Skin = Skin, Button = Button, FlatButton = FlatButton, Accent = Accent,
           Text = Text, FONT = FONT, WHITE = WHITE }

-- Dropdown: a field showing the current choice, with a divider and a drawn chevron on the
-- right (two rotated bars, so it stays crisp at any scale and follows the accent color).
local function Dropdown(parent, w, h, onClick)
  local b = Button(parent, "", w, h, onClick)
  b.text:ClearAllPoints()
  b.text:SetPoint("LEFT", 10, 0); b.text:SetPoint("RIGHT", -34, 0)
  b.text:SetJustifyH("LEFT")
  b.cmInset = 44
  local div = b:CreateTexture(nil, "ARTWORK")
  div:SetPoint("TOPRIGHT", -26, -5); div:SetPoint("BOTTOMRIGHT", -26, 5); div:SetWidth(1)
  div:SetColorTexture(unpack(C.border))
  local arrow = CreateFrame("Frame", nil, b)
  arrow:SetSize(12, 8); arrow:SetPoint("RIGHT", -8, 0)
  local function Bar(dx, rot)
    local t = arrow:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetSize(7, 2)
    t:SetPoint("CENTER", dx, 0)
    if t.SetRotation then t:SetRotation(rot) end
    return t
  end
  b.chev = { Bar(-2.2, -math.pi / 4), Bar(2.2, math.pi / 4) }
  local function Tint(r, g, bl) for _, t in ipairs(b.chev) do t:SetVertexColor(r, g, bl, 1) end end
  Tint(unpack(C.muted))
  local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
  b:SetScript("OnEnter", function(self)
    if enter then enter(self) end
    self:SetBackdropBorderColor(unpack(C.accent)); Tint(C.accent[1], C.accent[2], C.accent[3])
  end)
  b:SetScript("OnLeave", function(self)
    if leave then leave(self) end
    self:SetBackdropBorderColor(unpack(C.border)); Tint(unpack(C.muted))
  end)
  b.tooltip = nil
  return b
end

-- Section title: small uppercase accent text (registered for theme changes).
local function AccentText(parent)
  local fs = Text(parent, 11, C.accent)
  Accent(fs, "text")
  local orig = fs.SetText
  fs.SetText = function(self, t) orig(self, type(t) == "string" and not t:find("|", 1, true) and t:upper() or t) end
  return fs
end

-- Horizontal slider (custom-skinned).
local function SliderCtl(parent, w, minV, maxV, step, getter, setter, fmt)
  local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
  s:SetOrientation("HORIZONTAL")
  s:SetSize(w, 10)
  Skin(s, C.bg, C.border)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(8, 18)
  Accent(thumb, "tex")
  s:SetThumbTexture(thumb)
  s.label = Text(s, 11, C.muted); s.label:SetPoint("LEFT", s, "RIGHT", 10, 0)
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, d) self:SetValue((self:GetValue() or minV) + d * step) end)
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor((v or minV) / step + 0.5) * step
    self.label:SetText(string.format(fmt, v))
    if not self.syncing then setter(v) end
  end)
  function s:Sync()
    self.syncing = true
    self:SetValue(getter())
    self.label:SetText(string.format(fmt, getter()))
    self.syncing = false
  end
  return s
end

local function EditBox(parent, w, h, multiLine)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(w, h)
  Skin(e, C.bg, C.border)
  SetFontSize(e, 12)
  e:SetTextColor(unpack(C.text))
  e:SetAutoFocus(false)
  e:SetTextInsets(6, 6, 4, 4)
  e:SetMultiLine(multiLine and true or false)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  if not multiLine then e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end) end
  return e
end

local function Check(parent, label, getter, setter, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(260, 20)
  -- Hover help: one line on what the setting does and where you'll see it.
  b.tip = tip
  b:SetScript("OnEnter", function(self)
    if self.tip and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label, 1, 1, 1)
      GameTooltip:AddLine(self.tip, 0.8, 0.8, 0.8, true); GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  local box = CreateFrame("Frame", nil, b, "BackdropTemplate")
  box:SetSize(14, 14); box:SetPoint("LEFT", 0, 0)
  Skin(box, C.bg, C.border)
  local mark = box:CreateTexture(nil, "OVERLAY")
  mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  mark:SetPoint("CENTER"); mark:SetSize(18, 18)
  local t = Text(b, 12, C.text)
  t:SetPoint("LEFT", box, "RIGHT", 8, 0); t:SetText(label)
  b.label = t   -- rows built once and relabeled (Settings > Fill group's musts)
  function b:Sync() mark:SetShown(getter() and true or false) end
  b:SetScript("OnClick", function(self) setter(not getter()); self:Sync(); ns:Fire("SETTINGS_CHANGED") end)
  b:Sync()
  return b
end

local function SetSpecIcon(tex, specID, classFile)
  local _, icon = ns.API.GetSpecInfoByID(specID)
  if icon then
    tex:SetTexture(icon); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92); return
  end
  if classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
    tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
    tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[classFile]))
    return
  end
  tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

local function SpecLabel(specID)
  local p = UD:GetSpec(specID)
  if not p then return "?" end
  local _, _, _, hex = Util.ClassColor(p.class)
  return hex .. UD:SpecName(specID) .. " " .. UD:ClassName(p.class) .. "|r"
end

---------------------------------------------------------------------------
-- Scrollable line list (FontString pool + optional clickable rows)
---------------------------------------------------------------------------
local function ListRowEnter(btn)
  if btn.tip and GameTooltip then
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:SetText(btn.tip, 1, 1, 1, 1, true); GameTooltip:Show()
  end
end
local function TooltipHide() if GameTooltip then GameTooltip:Hide() end end

local function LineList(parent, width, height)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetSize(width, height)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(width, 1)
  ns.Links:Enable(content)   -- hover tooltips for ability/buff links in any line
  sf:SetScrollChild(content)
  local thumb = sf:CreateTexture(nil, "OVERLAY")
  Accent(thumb, "tex", 0.5)
  thumb:SetWidth(2)

  local L = { sf = sf, content = content, width = width, pool = {}, used = 0, bpool = {}, bused = 0, y = 0 }

  -- Stretch with the panel (the window is resizable): pin both corners to `parent`.
  function L:Fill(x1, y1, x2, y2)
    sf:ClearAllPoints()
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", x1, y1)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", x2, y2)
    return self
  end

  local function UpdateThumb()
    local total, view = content:GetHeight(), sf:GetHeight()
    if total <= view + 1 then thumb:Hide(); return end
    thumb:Show()
    local th = math.max(20, view * view / total)
    local pos = (sf:GetVerticalScroll() / (total - view)) * (view - th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, -pos)
    thumb:SetHeight(th)
  end
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 36)))
    UpdateThumb()
  end)

  function L:Clear()
    -- Lines wrap to the list's current width, so a bigger window shows more per line.
    local w = sf:GetWidth()
    if type(w) == "number" and w > 40 then self.width = w; content:SetWidth(w) end
    for i = 1, self.used do self.pool[i]:Hide() end
    for i = 1, self.bused do self.bpool[i]:Hide() end
    self.used, self.bused, self.y = 0, 0, 0
  end

  -- opts: size, color, indent, gap, onClick, tooltip
  function L:Add(text, opts)
    opts = opts or {}
    self.used = self.used + 1
    local fs = self.pool[self.used]
    if not fs then
      fs = Text(content, 12)
      self.pool[self.used] = fs
    end
    local indent = opts.indent or 0
    fs:SetFont(FONT, FontPx(opts.size or 12), "")
    fs:SetTextColor(unpack(opts.color or C.text))
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", indent + 4, -self.y)
    fs:SetWidth(self.width - indent - 14)
    fs:SetText(text or "")
    fs:Show()
    local h = math.max(fs:GetStringHeight() or 12, 12)
    -- A row with a tooltip but no click gets the hover area without the click highlight.
    if opts.onClick or opts.tooltip then
      self.bused = self.bused + 1
      local b = self.bpool[self.bused]
      if not b then
        b = CreateFrame("Button", nil, content)
        local hl = b:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(); Accent(hl, "tex", 0.10)
        b:SetHighlightTexture(hl)
        b.hl = hl
        b:SetScript("OnEnter", ListRowEnter)   -- set once: the handlers read b.tip
        b:SetScript("OnLeave", TooltipHide)
        self.bpool[self.bused] = b
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -self.y + 2)
      b:SetSize(self.width - 6, h + 4)
      b:SetScript("OnClick", opts.onClick)
      b.hl:SetAlpha(opts.onClick and 1 or 0)
      b.tip = opts.tooltip
      b:Show()
    end
    self.y = self.y + h + (opts.gap or 3)
    return fs
  end

  function L:Header(text)
    if self.y > 0 then self.y = self.y + 8 end
    local t = tostring(text or "")
    if not t:find("|", 1, true) then t = t:upper() end
    self:Add(HEX.accent .. t .. "|r", { size = 11, gap = 5 })
  end

  function L:Space(px) self.y = self.y + (px or 6) end

  -- Scroll so a position (from L.y at the time) is at the top.
  function L:ScrollTo(y)
    local max = math.max(0, (content:GetHeight() or 0) - (sf:GetHeight() or 0))
    sf:SetVerticalScroll(math.max(0, math.min(max, y or 0)))
    UpdateThumb()
  end

  function L:Finish()
    content:SetHeight(math.max(self.y, 1))
    local max = math.max(0, self.y - sf:GetHeight())
    if sf:GetVerticalScroll() > max then sf:SetVerticalScroll(max) end
    UpdateThumb()
  end

  return L
end

---------------------------------------------------------------------------
-- Popup menu (custom-skinned; replaces Blizzard dropdowns)
---------------------------------------------------------------------------
local menu, catcher
local menuButtons = {}
local MENU_ROWS = 16
local MENU_COL_W = 190

local function EnsureMenu()
  if menu then return end
  catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN")
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", function() UI:HideMenu() end)
  catcher:Hide()
  menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetClampedToScreen(true)
  Skin(menu, C.bg, C.accent)
  Accent(menu, "border")
  menu:Hide()
end

function UI:HideMenu()
  if menu then menu:Hide() end
  if catcher then catcher:Hide() end
end

-- items: { text, icon, specID, classFile, onClick, header, selected, color }
function UI:ShowMenu(anchor, items)
  EnsureMenu()
  for _, b in ipairs(menuButtons) do b:Hide() end
  local cols = math.max(1, math.ceil(#items / MENU_ROWS))
  local rows = math.min(#items, MENU_ROWS)
  for i, item in ipairs(items) do
    local b = menuButtons[i]
    if not b then
      b = CreateFrame("Button", nil, menu)
      b:SetSize(MENU_COL_W - 8, 20)
      local hl = b:CreateTexture(nil, "BACKGROUND")
      hl:SetAllPoints(); Accent(hl, "tex", 0.16)
      b:SetHighlightTexture(hl)
      b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(16, 16); b.icon:SetPoint("LEFT", 4, 0)
      b.text = Text(b, 12); b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0); b.text:SetPoint("RIGHT", -4, 0)
      b.text:SetWordWrap(false)
      menuButtons[i] = b
    end
    local col = math.floor((i - 1) / MENU_ROWS)
    local row = (i - 1) % MENU_ROWS
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4 + col * MENU_COL_W, -4 - row * 20)
    if item.specID or item.classFile then
      SetSpecIcon(b.icon, item.specID, item.classFile); b.icon:Show()
    elseif item.icon then
      b.icon:SetTexture(item.icon); b.icon:SetTexCoord(0, 1, 0, 1); b.icon:Show()
    else
      b.icon:Hide()
    end
    local label = item.text or ""
    if item.selected then label = TEX_OK .. " " .. label end
    b.text:SetText(label)
    b.text:SetTextColor(unpack(item.header and C.muted or (item.color or C.text)))
    b:EnableMouse(not item.header)
    b:SetScript("OnClick", function()
      UI:HideMenu()
      if item.onClick then item.onClick() end
    end)
    -- Optional hover text (string, or a function computed only when hovered).
    b:SetScript("OnEnter", item.tooltip and function(btn)
      local tip = type(item.tooltip) == "function" and item.tooltip() or item.tooltip
      if tip and GameTooltip then
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show()
      end
    end or nil)
    b:SetScript("OnLeave", item.tooltip and function() if GameTooltip then GameTooltip:Hide() end end or nil)
    b:Show()
  end
  menu:SetSize(math.max(cols * MENU_COL_W + 4, anchor.GetWidth and anchor:GetWidth() or 0), rows * 20 + 8)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  catcher:Show()
  menu:Show()
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
-- The boss window and the Group Finder applicant panel draw over the main window: same strata
-- (HIGH), a frame level well above it and everything inside it (its highest child, the tour
-- callout, sits about 50 above it). The addon's pop-ups (DIALOG) and menus stay on top of them.
UI.OVER_WINDOW_STRATA, UI.OVER_WINDOW_LEVEL = "HIGH", 200
UI.LOGO = "Interface\\AddOns\\Ensemble\\Media\\LogoMark"   -- emblem only (no tile), so it reads larger
UI.LOGO_SIZE = 38
UI.NAME = "Ensemble"
UI.SUBTITLE = "A Mythic+ Companion"

-- Tabs follow the three questions: who to bring (Composition, Applicants), what to know
-- (Dungeon) and who handles what (Plan).
local TABS = {
  { key = "composition", label = "Composition" },
  { key = "applicants", label = "Applicants" },
  { key = "dungeons", label = "Dungeon" },
  { key = "plan",     label = "Plan" },
  { key = "history",  label = "History" },
  { key = "settings", label = "Settings" },
}
UI.TABS = TABS
-- Older tab names (slash commands, saved last tab) and where they live now.
UI.TAB_ALIAS = { builder = "composition", live = "composition", saved = "composition", dungeon = "dungeons" }

function UI:Build()
  if self.frame then return end
  UD, DD, Analysis = ns.UD, ns.Dungeons, ns.Analysis

  local f = CreateFrame("Frame", "EnsembleFrame", UIParent, "BackdropTemplate")
  self.frame = f
  f:SetSize(W, H)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  Skin(f, C.bg, C.border)
  self:ApplyTheme(true)
  self:ApplyGeometry()
  f:Hide()
  -- Close on Escape. UISpecialFrames is Blizzard's list of frame NAMES closed by Escape.
  if UISpecialFrames then table.insert(UISpecialFrames, "EnsembleFrame") end

  -- Header bar: slightly lifted background, accent hairline underneath.
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(40)
  local hbg = header:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); hbg:SetColorTexture(unpack(C.header))
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function()
    if ns.db.settings.window.locked then return end
    f:StartMoving()
  end)
  header:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    UI:SaveGeometry()
  end)
  -- Brand: logo, name (white) and subtitle in the accent color (follows the theme: default blue,
  -- a preset, a hex or the class color). Fixed size, like the tab row, so the header always fits.
  local logo = header:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(UI.LOGO)
  logo:SetSize(UI.LOGO_SIZE, UI.LOGO_SIZE)
  logo:SetPoint("LEFT", 8, 0)
  self.logo = logo
  local title = Text(header, 15, C.text)
  title:SetWordWrap(false)
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 6, -4)
  self.titleText = title
  fontRegistry[title] = nil
  title:SetText(UI.NAME)
  local subtitle = Text(header, 10)
  Accent(subtitle, "text")
  subtitle:SetWordWrap(false)
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  fontRegistry[subtitle] = nil
  subtitle:SetText(UI.SUBTITLE)
  self.subtitleText = subtitle
  local brandW = math.max(title:GetStringWidth() or 0, subtitle:GetStringWidth() or 0)
  if brandW < 1 then brandW = 190 end
  local tabsX = 8 + UI.LOGO_SIZE + 6 + math.ceil(brandW) + 16

  self.tabButtons = {}
  local prev, first = nil, nil
  local tabList = {}
  for _, t in ipairs(TABS) do
    local b = Tab(header, t.label, function() UI:SetTab(t.key) end)
    fontRegistry[b.text] = nil   -- the tab row keeps its size so it always fits the header
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("LEFT", header, "LEFT", tabsX, 0); first = b end
    self.tabButtons[t.key] = b
    tabList[#tabList + 1] = b
    prev = b
  end
  -- Fill group: a dot on the Applicants tab while a full group passes and you're elsewhere.
  do
    local ab = self.tabButtons.applicants
    ab.dot = ab:CreateTexture(nil, "OVERLAY")
    ab.dot:SetSize(7, 7); ab.dot:SetPoint("TOPRIGHT", -5, -10)
    ab.dot:SetColorTexture(unpack(C.good))
    ab.dot:Hide()
  end
  -- Fit the brand and the tab row beside the title-bar buttons (~140px on the right) at
  -- the narrowest window: first tighten the tabs' padding, and only if a client font is
  -- still too wide, drop the subtitle (the tabs always stay).
  local room = UI.MIN_W - 140
  local function RowWidth(pad, minW)
    local w = 0
    for _, b in ipairs(tabList) do
      w = w + math.max(minW, (b.text:GetStringWidth() or 60) + pad) + 2
    end
    return w
  end
  local tabsW = RowWidth(24, 64)
  if tabsX + tabsW > room then
    for _, fit in ipairs({ { 16, 54 }, { 12, 48 } }) do
      if tabsX + RowWidth(fit[1], fit[2]) <= room or fit[1] == 12 then
        for _, b in ipairs(tabList) do b:SetWidth(math.max(fit[2], (b.text:GetStringWidth() or 60) + fit[1])) end
        tabsW = RowWidth(fit[1], fit[2])
        break
      end
    end
  end
  self.headerFit = { tabsX = tabsX, tabsW = tabsW, room = room, subtitleShown = tabsX + tabsW <= room }
  if tabsX + tabsW > room then
    subtitle:Hide()
    title:ClearAllPoints(); title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    first:ClearAllPoints()
    first:SetPoint("LEFT", header, "LEFT", 8 + UI.LOGO_SIZE + 6 + math.ceil(title:GetStringWidth() or 150) + 20, 0)
  end
  local close = FlatButton(header, "X", 26, 24, function() UI:Hide() end)
  close:SetPoint("RIGHT", -10, 0)
  close.tooltip = "Close (Esc)"
  self.lockBtn = FlatButton(header, "", 64, 24, function()
    local w = ns.db.settings.window
    w.locked = not w.locked
    ns:Fire("SETTINGS_CHANGED")
  end)
  self.lockBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
  local help = FlatButton(header, "?", 24, 24, function() UI:ShowGlossary() end)
  help:SetPoint("RIGHT", self.lockBtn, "LEFT", -4, 0)
  help.tooltip = "Glossary: what the addon's terms mean"
  self.helpBtn = help

  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", 1, -41); line:SetPoint("TOPRIGHT", -1, -41); line:SetHeight(1)
  Accent(line, "tex", 0.55)

  -- Resize grip (bottom-right): more room for the panels, same text size.
  f:SetResizable(true)
  local maxW = math.max(UI.MIN_W, (UIParent.GetWidth and UIParent:GetWidth()) or 0)
  local maxH = math.max(UI.MIN_H, (UIParent.GetHeight and UIParent:GetHeight()) or 0)
  if maxW <= UI.MIN_W then maxW = 4000 end
  if maxH <= UI.MIN_H then maxH = 4000 end
  if f.SetResizeBounds then f:SetResizeBounds(UI.MIN_W, UI.MIN_H, maxW, maxH)
  elseif f.SetMinResize then f:SetMinResize(UI.MIN_W, UI.MIN_H) end
  f:SetScript("OnSizeChanged", function() UI:OnResize() end)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(f:GetFrameLevel() + 20)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    if ns.db.settings.window.locked then return end
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    UI:SaveGeometry()
    UI:OnResize()
  end)
  grip:SetScript("OnEnter", function(btn)
    if GameTooltip then
      GameTooltip:SetOwner(btn, "ANCHOR_TOP"); GameTooltip:SetText("Drag to resize the window", 1, 1, 1); GameTooltip:Show()
    end
  end)
  grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  self.grip = grip
  self:UpdateLockState()

  self.pages = {}
  self:BuildCompPage()
  self:BuildApplicantsPage()
  self:BuildHistoryPage()
  self:BuildPrimerPage()
  self:BuildPlanPage()
  self:BuildSettingsPage()
  self:BuildSharePopup()

  f:SetScript("OnShow", function()
    UI:SetTab(UI.currentTab or ns.db.lastTab or "composition")
    UI:UpdateFillPopup()
  end)
  f:SetScript("OnHide", function()
    UI:HideMenu()
    if ns.Tracker then ns.Tracker:Disable() end
    UI:UpdateFillPopup()
  end)
end

---------------------------------------------------------------------------
-- Window geometry. The corner grip RESIZES the window (more room for the panels; text
-- stays the same size); text size is its own setting. Position is stored as the
-- top-left corner in UIParent units.
---------------------------------------------------------------------------
UI.MIN_W, UI.MIN_H = W, 600
UI.TEXT_MIN, UI.TEXT_MAX = 80, 125

local function ClampSize(w, h)
  local maxW = math.max(UI.MIN_W, (UIParent.GetWidth and UIParent:GetWidth() or 0) or 0)
  local maxH = math.max(UI.MIN_H, (UIParent.GetHeight and UIParent:GetHeight() or 0) or 0)
  if maxW < UI.MIN_W + 1 then maxW = 4000 end
  if maxH < UI.MIN_H + 1 then maxH = 4000 end
  w = math.max(UI.MIN_W, math.min(maxW, tonumber(w) or W))
  h = math.max(UI.MIN_H, math.min(maxH, tonumber(h) or H))
  return math.floor(w + 0.5), math.floor(h + 0.5)
end

function UI:ApplyGeometry()
  local f = self.frame
  if not f then return end
  local w = ns.db.settings.window
  f:SetScale(1)
  w.width, w.height = ClampSize(w.width, w.height)
  f:SetSize(w.width, w.height)
  f:ClearAllPoints()
  if w.point == "TOPLEFT" and w.left and w.top then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", w.left, w.top)
  else
    f:SetPoint(w.point or "CENTER", UIParent, w.relPoint or "CENTER", w.x or 0, w.y or 0)
  end
end

function UI:SaveGeometry()
  local f = self.frame
  if not f then return end
  local w = ns.db.settings.window
  if f:GetLeft() then
    w.point, w.relPoint = "TOPLEFT", "BOTTOMLEFT"
    w.left, w.top = f:GetLeft(), f:GetTop()
  end
  local fw, fh = f:GetWidth(), f:GetHeight()
  if type(fw) == "number" and fw > 0 then w.width, w.height = ClampSize(fw, fh) end
end

-- Set the window size (keeps the top-left corner).
function UI:SetWindowSize(width, height)
  local w = ns.db.settings.window
  w.width, w.height = ClampSize(width, height)
  if self.frame then
    self.frame:SetSize(w.width, w.height)
    self:OnResize()
  end
end

function UI:SetTextSize(pct)
  pct = math.max(self.TEXT_MIN, math.min(self.TEXT_MAX, math.floor((tonumber(pct) or 100) + 0.5)))
  ns.db.settings.textSize = pct
  self:ApplyTextSize()
  if self.textSlider and not self.textSlider.syncing then self.textSlider:Sync() end
end

-- Slot rows grow with the text size so the name and badges never overlap.
function UI:LayoutSlots()
  local cp = self.cp
  if not (cp and cp.slotRows) then return end
  local h = math.max(40, FontPx(13) + FontPx(11) + 14)
  for i, row in ipairs(cp.slotRows) do
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * (h + 4))
  end
  local listTop = -8 - ns.NUM_SLOTS * (h + 4) - 4
  cp.sideList:Fill(4, listTop, -4, 70)
  -- The hosting applicant panel moves with them (it kept its 100% spot and ran into the last slot at 125%).
  self:LayoutAppPanel(listTop)
end

function UI:ApplyTextSize()
  self.appliedTextSize = ns.db.settings.textSize
  self:LayoutSlots()
  for obj in pairs(fontRegistry) do
    if obj.SetFont then obj:SetFont(FONT, FontPx(obj.cmSize), "") end
  end
  for fs in pairs(fitLabels) do fs.cmFitKey = nil; FitLabel(fs) end
  self:QueueRefresh()
  self:QueueFinderRefresh()
end

function UI:ResetGeometry()
  local w = ns.db.settings.window
  w.point, w.relPoint, w.x, w.y, w.left, w.top = "CENTER", "CENTER", 0, 0, nil, nil
  w.width, w.height = W, H
  self:ApplyGeometry()
  self:OnResize()
end

-- Re-flow after a size change: fixed-width side columns, the rest goes to the middle.
-- Lists re-wrap on the next refresh (debounced while the grip is dragged).
function UI:OnResize()
  if self.LayoutComp then self:LayoutComp() end
  if self.resizeTimer then self.resizeTimer:Cancel() end
  self.resizeTimer = C_Timer.NewTimer(0.12, function() UI.resizeTimer = nil; UI:QueueRefresh() end)
end

function UI:UpdateLockState()
  if not self.frame then return end
  local locked = ns.db.settings.window.locked
  if self.grip then self.grip:SetShown(not locked) end
  if self.lockBtn then
    self.lockBtn.text:SetText(locked and "Locked" or "Unlocked")
    self.lockBtn.tooltip = locked and "Window locked. Click to allow moving and resizing."
      or "Drag the title bar to move, the corner grip to resize. Click to lock."
  end
end

local function PageFrame(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetPoint("TOPLEFT", 0, -41); p:SetPoint("BOTTOMRIGHT", 0, 0)
  p:Hide()
  return p
end

-- Composition (and Plan) work on your party when you're in one or have a listing, else on
-- the planner; Settings > General or the Composition tab's mode button can fix either.
-- Returns "live" (your party) or "builder" (the planner).
function UI:CompMode()
  local m = ns.db.settings.compMode or "auto"
  if m == "planner" then return "builder" elseif m == "party" then return "live" end
  local inGroup = IsInGroup and IsInGroup()
  local listed = false
  if C_LFGList and C_LFGList.HasActiveEntryInfo then
    local ok, has = pcall(C_LFGList.HasActiveEntryInfo)
    listed = ok and has and true or false
  end
  return (inGroup or listed) and "live" or "builder"
end

function UI:SetTab(key)
  if not self.frame then return end
  key = self.TAB_ALIAS[key] or key
  local valid = false
  for _, t in ipairs(TABS) do if t.key == key then valid = true end end
  if not valid then key = "composition" end
  self.currentTab = key
  ns.db.lastTab = key
  for k, b in pairs(self.tabButtons) do b:SetActive(k == key) end
  for _, p in pairs(self.pages) do p:Hide() end
  if key == "composition" or key == "plan" then
    local mode = self:CompMode()
    ns.state.mode = mode
    if mode == "live" then ns.Tracker:Enable() else ns.Tracker:Disable() end
    self.pages[key == "plan" and "plan" or "comp"]:Show()
  elseif key == "applicants" then
    ns.state.mode = "live"           -- applicants are rated against the live party
    ns.Tracker:Enable()
    self.pages.applicants:Show()
  else
    ns.Tracker:Disable()
    self.pages[key]:Show()
  end
  self:Refresh()
end

function UI:Show(tab)
  self:Build()
  -- The old Builder / Live names ask for Composition fixed to the planner / your party.
  if tab == "builder" then ns.db.settings.compMode = "planner" elseif tab == "live" then ns.db.settings.compMode = "party" end
  tab = tab and (self.TAB_ALIAS[tab] or tab)
  if tab then self.currentTab = tab end
  if self.frame:IsShown() then self:SetTab(tab or self.currentTab) else self.frame:Show() end
  -- First time the window opens (no particular tab asked for): the short tour.
  if not tab and ns.Tour then ns.Tour:MaybeStart() end
end
function UI:Hide() if self.frame then self.frame:Hide() end end
function UI:Toggle()
  if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

-- Coalesce bursts of change events into one refresh next frame.
function UI:QueueRefresh()
  if self.refreshQueued or not (self.frame and self.frame:IsShown()) then return end
  self.refreshQueued = true
  C_Timer.After(0, function()
    UI.refreshQueued = false
    UI:Refresh()
  end)
end

function UI:Refresh()
  if not (self.frame and self.frame:IsShown()) then return end
  local tab = self.currentTab
  -- pcall so a bad data row can never leave the user with a dead window.
  local ok, err = pcall(function()
    if tab == "composition" then UI:RefreshComp()
    elseif tab == "plan" then UI:RefreshPlan()
    elseif tab == "applicants" then UI:RefreshApplicants()
    elseif tab == "history" then UI:RefreshHistory()
    elseif tab == "dungeons" then UI:RefreshPrimer()
    elseif tab == "settings" then UI:RefreshSettings() end
    UI:SyncFillTabDot()
  end)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Composition page (planner and party modes share it)
---------------------------------------------------------------------------
function UI:BuildCompPage()
  local page = PageFrame(self.frame)
  self.pages.comp = page
  local cp = {}
  self.cp = cp

  -- Dungeon bar: prominent, one click from the comp view.
  local bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT", 12, -10); bar:SetPoint("TOPRIGHT", -12, -10); bar:SetHeight(30)
  local lbl = Text(bar, 12, C.muted); lbl:SetPoint("LEFT", 0, 0); lbl:SetText("Check against:")
  cp.dungeonBtn = Dropdown(bar, 280, 28, function(btn) UI:OpenDungeonMenu(btn) end)
  cp.dungeonBtn:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
  SetFontSize(cp.dungeonBtn.text, 13)
  cp.compactBtn = Button(bar, "", 120, 26, function()
    ns.db.settings.compact = not ns.db.settings.compact
    ns:Fire("SETTINGS_CHANGED")
  end)
  cp.compactBtn:SetPoint("RIGHT", 0, 0)
  cp.compactBtn.tooltip = "Toggle compact (gaps only) / full breakdown"
  cp.bestKeyBtn = Button(bar, "Best key", 96, 26, function() UI:ShowBestKey() end)
  cp.bestKeyBtn:SetPoint("RIGHT", cp.compactBtn, "LEFT", -6, 0)
  cp.bestKeyBtn.tooltip = "Rank every Season dungeon by how well this group covers it"
  -- Whose group: your party (when you're in one or listed) or the planner.
  cp.modeBtn = Dropdown(bar, 150, 26, function(btn) UI:OpenModeMenu(btn) end)
  cp.modeBtn:SetPoint("RIGHT", cp.bestKeyBtn, "LEFT", -6, 0)
  cp.dungeonNote = Text(bar, 11, C.muted); cp.dungeonNote:SetPoint("LEFT", cp.dungeonBtn, "RIGHT", 10, 0)
  cp.dungeonNote:SetPoint("RIGHT", cp.modeBtn, "LEFT", -8, 0); cp.dungeonNote:SetWordWrap(false)
  MakeFit(cp.dungeonNote, function() return cp.dungeonNote:GetWidth() or 0 end)
  -- Hover the short note for the full sentence (issue #16: the note has ~160px at the smallest window).
  cp.noteBtn = CreateFrame("Button", nil, bar)
  cp.noteBtn:SetPoint("TOPLEFT", cp.dungeonNote, "TOPLEFT", 0, 4); cp.noteBtn:SetPoint("BOTTOMRIGHT", cp.dungeonNote, "BOTTOMRIGHT", 0, -4)
  cp.noteBtn:SetScript("OnEnter", function(btn)
    if btn.tip and GameTooltip then GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM"); GameTooltip:SetText(btn.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
  end)
  cp.noteBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  -- Summary strip: dungeon + counts, one chip per key need (click to jump), biggest risks.
  local sum = Panel(page)
  sum:SetPoint("TOPLEFT", 12, -46); sum:SetPoint("TOPRIGHT", -12, -46); sum:SetHeight(72)
  ns.Links:Enable(sum)
  cp.sumPanel = sum
  cp.sumTitle = Text(sum, 13, C.text); cp.sumTitle:SetPoint("TOPLEFT", 10, -7); cp.sumTitle:SetPoint("RIGHT", -10, 0)
  cp.sumTitle:SetWordWrap(false)
  cp.chipBar = CreateFrame("Frame", nil, sum)
  cp.chipBar:SetPoint("TOPLEFT", 8, -25); cp.chipBar:SetPoint("RIGHT", -8, 0); cp.chipBar:SetHeight(20)
  -- Chips wrap onto more rows instead of running past the edge; clipping is a safety net
  -- for the moment between a resize and the next refresh.
  if cp.chipBar.SetClipsChildren then cp.chipBar:SetClipsChildren(true) end
  cp.chips = {}
  cp.sumRisks = Text(sum, 11, C.text); cp.sumRisks:SetPoint("TOPLEFT", cp.chipBar, "BOTTOMLEFT", 2, -7); cp.sumRisks:SetPoint("RIGHT", -10, 0)
  cp.sumRisks:SetWordWrap(false)
  cp.riskBtn = CreateFrame("Button", nil, sum)
  cp.riskBtn:SetPoint("TOPLEFT", cp.sumRisks, "TOPLEFT", 0, 2); cp.riskBtn:SetPoint("BOTTOMRIGHT", cp.sumRisks, "BOTTOMRIGHT", 0, -2)
  cp.riskBtn:SetScript("OnClick", function()
    UI.expand["risks"] = true
    if UI.cp.ready then UI.cp.ready:ScrollTo(0) end
    UI:QueueRefresh()
  end)
  cp.riskBtn:SetScript("OnEnter", function(btn)
    if GameTooltip then GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM"); GameTooltip:SetText("Click to list every gap", 1, 1, 1); GameTooltip:Show() end
  end)
  cp.riskBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- Kept for code that reads the old one-line summary.
  cp.summary = cp.sumRisks

  local top = -126
  local colH = H - 41 - 126 - 12
  cp.top = top

  -- Left column: slots + suggestions / applicants / saved comps + actions
  local left = Panel(page)
  left:SetPoint("TOPLEFT", sum, "BOTTOMLEFT", 0, -8); left:SetPoint("BOTTOMLEFT", 12, 12); left:SetWidth(COL_W + 8)
  cp.left = left
  cp.slotRows = {}
  for i = 1, ns.NUM_SLOTS do
    local row = CreateFrame("Button", nil, left, "BackdropTemplate")
    ns.Links:Enable(row)
    row:SetSize(COL_W - 8, 40)
    row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 44)
    Skin(row, C.btn, C.border)
    row.role = Text(row, 10, C.muted); row.role:SetPoint("LEFT", 8, 0); row.role:SetWidth(34)
    row.role:SetWordWrap(false)
    MakeFit(row.role, function() return 34 end)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(28, 28); row.icon:SetPoint("LEFT", 44, 0)
    -- The two lines sit at the row's top and bottom (not the 28px icon's), so they keep apart
    -- as the row grows with the text size (issue #16: "Empty" drew over its second line).
    row.name = Text(row, 13); row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 80, -5)
    row.name:SetPoint("RIGHT", -30, 0); row.name:SetWordWrap(false)
    row.sub = Text(row, 11, C.muted); row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 80, 5)
    row.sub:SetPoint("RIGHT", -30, 0); row.sub:SetWordWrap(false)
    row.clear = Button(row, "x", 20, 20, function()
      if ns.state.mode ~= "builder" then return end
      ns.db.currentComp[i] = 0
      -- Every writer that changes a slot drops the saved player on it, or a later write of the
      -- same spec would bring their name back (1.5.0 review, R1).
      ns.db.currentPeople[i] = false
      ns:Fire("COMP_CHANGED", "slot")
    end)
    row.clear:SetPoint("RIGHT", -6, 0)
    row.clear.tooltip = "Clear slot"
    row:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(unpack(C.accent))
      if self.tip and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tip, 1, 1, 1, 1, true); GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function(self)
      self:SetBackdropBorderColor(unpack(C.border))
      if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
      if ns.state.mode == "builder" then UI:OpenSpecMenu(self, i) end
    end)
    cp.slotRows[i] = row
  end

  local listTop = -8 - ns.NUM_SLOTS * 44 - 4
  local actionsH = 70
  cp.sideList = LineList(left, COL_W, colH + listTop - actionsH - 8):Fill(4, listTop, -4, actionsH)

  -- Builder actions
  local actions = CreateFrame("Frame", nil, left)
  actions:SetPoint("BOTTOMLEFT", 8, 8); actions:SetSize(COL_W - 8, actionsH - 8)
  cp.actions = actions
  -- Two rows on one three-column grid (ACT_BW wide, ACT_GAP apart) so neither row runs
  -- past the column into Needs: top = name box + Save over columns 1-2, Saved over column 3;
  -- bottom = Export, Clear all, Copy party.
  local ACT_BW, ACT_GAP, SAVE_W = 92, 6, 64
  cp.nameBox = EditBox(actions, 2 * ACT_BW + ACT_GAP - SAVE_W - ACT_GAP, 24)
  cp.nameBox:SetPoint("TOPLEFT", 0, 0)
  cp.saveBtn = Button(actions, "Save", SAVE_W, 24, function() UI:SaveCurrent() end)
  cp.saveBtn:SetPoint("LEFT", cp.nameBox, "RIGHT", ACT_GAP, 0)
  cp.exportBtn = Button(actions, "Export", ACT_BW, 24, function()
    UI:ShowShare("Export", ns.Share.Encode(Util.Trim(cp.nameBox:GetText()) ~= "" and cp.nameBox:GetText() or "Comp",
      ns.db.currentComp, (ns:GetEffectiveDungeon()) or "NONE"))
  end)
  cp.exportBtn:SetPoint("BOTTOMLEFT", 0, 0)
  cp.clearBtn = Button(actions, "Clear all", ACT_BW, 24, function()
    for s = 1, ns.NUM_SLOTS do ns.db.currentComp[s] = 0; ns.db.currentPeople[s] = false end
    ns:Fire("COMP_CHANGED", "clear")
  end)
  cp.clearBtn:SetPoint("LEFT", cp.exportBtn, "RIGHT", ACT_GAP, 0)
  cp.copyLiveBtn = Button(actions, "Copy party", ACT_BW, 24, function() UI:CopyLiveToBuilder() end)
  cp.copyLiveBtn:SetPoint("LEFT", cp.clearBtn, "RIGHT", ACT_GAP, 0)
  cp.copyLiveBtn.tooltip = "Copy your current party into the planner"
  cp.savedBtn = Dropdown(actions, ACT_BW, 24, function(btn) UI:OpenSavedMenu(btn) end)
  cp.savedBtn:SetPoint("LEFT", cp.saveBtn, "RIGHT", ACT_GAP, 0)   -- starts at column 3, over Copy party
  cp.actionsRowW = 3 * ACT_BW + 2 * ACT_GAP
  cp.savedBtn.text:SetText("Saved")
  cp.savedBtn.tooltip = "Load, delete or import saved comps"
  cp.liveStatus = Text(left, 11, C.muted)
  cp.liveStatus:SetPoint("BOTTOMLEFT", 10, 12); cp.liveStatus:SetPoint("BOTTOMRIGHT", -10, 12)
  -- While you host: your best-fit applicants under the slots (see BuildAppPanel).
  self:BuildAppPanel(left, listTop, colH)

  -- Right: Needs (every need, generic + dungeon, in one place). The plan has its own tab.
  local mid = Panel(page)
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); mid:SetPoint("BOTTOMRIGHT", -12, 12)
  cp.mid = mid
  local midT = AccentText(mid); midT:SetPoint("TOPLEFT", 10, -8); midT:SetText("Needs")
  cp.collapseBtn = FlatButton(mid, "Collapse all", 80, 18, function() UI:CollapseAll() end)
  cp.collapseBtn:SetPoint("TOPRIGHT", -6, -5)
  cp.collapseBtn.tooltip = "Fold every need and every expanded list"
  cp.expandBtn = FlatButton(mid, "Expand all", 74, 18, function() UI:ExpandAll() end)
  cp.expandBtn:SetPoint("RIGHT", cp.collapseBtn, "LEFT", -6, 0)
  cp.expandBtn.tooltip = "Open every need"
  cp.checksGear = UI:GearButton(mid, "checks", "What to check: choose the needs that matter to you")
  cp.checksGear:SetPoint("RIGHT", cp.expandBtn, "LEFT", -4, 0)
  cp.ready = LineList(mid, COL_W, colH - 34):Fill(6, -28, -6, 6)
  cp.analysis, cp.dungeon = cp.ready, cp.ready   -- older names for the same list
  self:LayoutComp()
  self:LayoutSlots()
end

-- The left column keeps its width; extra window width goes to Needs. The Plan tab splits
-- its width between your assignments and everyone's.
function UI:LayoutComp()
  local pl = self.pl
  if not (pl and pl.leftPanel and self.frame) then return end
  local fw = self.frame:GetWidth() or W
  pl.leftPanel:SetWidth(math.max(360, math.floor((fw - 34) * 0.44)))
end

-- In-game dungeon icons, looked up from the current season's Mythic+ map list and
-- matched to DungeonData by name. confirmed present in 12.1.0 (build 69933) by /ens verify (all 8 dungeons matched with icons):
-- C_ChallengeMode.GetMapTable() -> mapIDs, C_ChallengeMode.GetMapUIInfo(mapID) ->
-- name, id, timeLimit, texture. Falls back to the keystone icon until the data loads.
local KEYSTONE_ICON = "Interface\\Icons\\INV_Relics_Hourglass"
local dungeonIcons = {}
function UI:DungeonIcon(key)
  local DD = ns.Dungeons
  if not key or not DD.list[key] then return nil end
  if not dungeonIcons[key] and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
    local mapID = DD.CHALLENGE_MAP_IDS[key]
    local ok2, _, _, _, texture = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if ok2 and texture then dungeonIcons[key] = texture end
  end
  return dungeonIcons[key] or KEYSTONE_ICON
end

-- "|T icon|t Name" for buttons and headers.
function UI:DungeonLabel(key, size)
  local DD = ns.Dungeons
  if not key or not DD.list[key] then return "No dungeon selected" end
  return "|T" .. tostring(self:DungeonIcon(key)) .. ":" .. (size or 16) .. ":" .. (size or 16) .. ":0:0|t " .. DD.list[key].name
end

function UI:OpenDungeonMenu(anchor)
  local pick = ns:GetDungeonPick()
  local live = ns.state.mode == "live"
  local autoKey, autoSrc, autoLevel = ns:AutoDungeon()
  local autoText
  if autoKey then
    local why = (autoSrc == "listing" and "your listing") or (autoSrc == "zone" and "you're in it")
      or ("your key" .. (autoLevel and (" +" .. autoLevel) or ""))
    autoText = "Auto: " .. DD.list[autoKey].name .. "  " .. HEX.muted .. "(" .. why .. ")|r"
  else
    autoText = "Auto  " .. HEX.muted .. (live and "(listing or current dungeon)" or "(your keystone)") .. "|r"
  end
  local items = {
    { text = autoText, selected = pick == "AUTO", icon = autoKey and UI:DungeonIcon(autoKey) or nil,
      onClick = function() ns:SetManualDungeon("AUTO") end },
    { text = "No dungeon (generic only)", selected = pick == "NONE",
      onClick = function() ns:SetManualDungeon("NONE") end },
  }
  for _, key in ipairs(DD.order) do
    local d = DD.list[key]
    table.insert(items, { text = d.name, selected = pick == key,
      icon = UI:DungeonIcon(key),
      onClick = function() ns:SetManualDungeon(key) end })
  end
  self:ShowMenu(anchor, items)
end

function UI:OpenSpecMenu(anchor, slot)
  local role = ns.SLOT_ROLES[slot]
  local P = ns.Players
  local items = {
    { text = "Clear slot", onClick = function() ns.db.currentComp[slot] = 0; ns.db.currentPeople[slot] = false; ns:Fire("COMP_CHANGED", "slot") end },
    -- 1.5.1: a friend, Battle.net friend, guildmate or saved player, then their spec.
    { text = "Pick a friend or guildmate...", color = C.accent,
      tooltip = "Your friends, Battle.net friends and guild, by class; then the spec they'll play",
      onClick = function() UI:OpenFriendsPicker({ mode = "planner", slot = slot, role = role }) end },
  }
  -- Saved players (1.5.0) who play this slot's role: their spec fills it, their name shows on it.
  local saved = P:ForRole(role)
  if #saved > 0 then
    items[#items + 1] = { text = "Saved players", header = true }
    local cur = P:PlannerPerson(slot)
    for _, x in ipairs(saved) do
      local p = UD:GetSpec(x.specID)
      local r, g, b = Util.ClassColor(p.class)
      local name = x.p.full:match("^([^%-]+)") or x.p.full
      items[#items + 1] = {
        text = name .. "  -  " .. UI.ShortLabel(UD:SpecName(x.specID) .. " " .. UD:ClassName(p.class)),
        specID = x.specID, classFile = p.class, color = { r, g, b, 1 },
        selected = cur and P.Key(cur.full) == P.Key(x.p.full) and cur.spec == x.specID,
        onClick = function() P:SetPlannerSlot(slot, x.p.full, x.specID) end,
        tooltip = function() return x.p.full .. "\n" .. (UI:SpecPreviewText(slot, x.specID) or "") end,
      }
    end
    items[#items + 1] = { text = "Specs", header = true }
  end
  for _, specID in ipairs(UD:SpecsForRole(role)) do
    local p = UD:GetSpec(specID)
    local r, g, b = Util.ClassColor(p.class)
    table.insert(items, {
      text = UD:SpecName(specID) .. " " .. UD:ClassName(p.class) .. (p.verify and " (?)" or ""),
      specID = specID, classFile = p.class, color = { r, g, b, 1 },
      selected = ns.db.currentComp[slot] == specID and not P:PlannerPerson(slot),
      onClick = function() ns.db.currentComp[slot] = specID; ns.db.currentPeople[slot] = false; ns:Fire("COMP_CHANGED", "slot") end,
      tooltip = function() return UI:SpecPreviewText(slot, specID) end,
    })
  end
  self:ShowMenu(anchor, items)
end

-- Hover preview in the slot menu: what putting this spec in this slot would change.
function UI:SpecPreviewText(slot, specID)
  local p = UD:GetSpec(specID)
  if not p then return nil end
  local cur = ns.db.currentComp[slot]
  local title = UD:SpecName(specID) .. " " .. UD:ClassName(p.class)
  if cur == specID then return title .. "\nAlready in this slot." end
  local base, after = {}, {}
  for s = 1, ns.NUM_SLOTS do
    local id = ns.db.currentComp[s]
    if id and id ~= 0 and UD:GetSpec(id) then base[#base + 1] = { specID = id } end
    local nid = (s == slot) and specID or id
    if nid and nid ~= 0 and UD:GetSpec(nid) then after[#after + 1] = { specID = nid } end
  end
  local dk = ns:GetEffectiveDungeon(false)
  local settings = ns.db.settings
  local r0 = Analysis:Analyze(base, dk, settings)
  local r1 = Analysis:Analyze(after, dk, settings)
  local lines = { title .. ((cur and cur ~= 0 and UD:GetSpec(cur)) and (" (replacing " .. UD:SpecName(cur) .. " " .. UD:ClassName(UD:GetSpec(cur).class) .. ")") or "") }
  local delta = Analysis:ScoreDelta(r0, r1, ns.Affixes and ns.Affixes:KeyLevel(dk))
  -- From an empty group, every generic gap is "new"; that's noise, not a cost of this spec.
  local fromEmpty = #base == 0
  if fromEmpty then lines[#lines + 1] = "(Empty group: showing what this spec covers on its own.)" end
  local net = 0
  for _, d in ipairs(delta) do
    if not (fromEmpty and d.kind == "gap") then
      net = net + d.points
      lines[#lines + 1] = (d.points >= 0 and "|cff7ce36a+ " or "|cffff6b6b- ") .. UI.Plain(d.text) .. "|r"
    end
  end
  if #delta == 0 then lines[#lines + 1] = "Changes nothing the addon tracks." end
  lines[#lines + 1] = string.format("Net: %s%.1f points", net >= 0 and "+" or "-", math.abs(net))
  return table.concat(lines, "\n")
end

function UI:SaveCurrent()
  local name = Util.Trim(self.cp.nameBox:GetText())
  if name == "" then name = "Comp " .. (#ns.db.savedComps + 1) end
  local entry = { name = name, slots = Util.DeepCopy(ns.db.currentComp), dungeon = (ns:GetEffectiveDungeon(false)) or "NONE",
                  created = time and time() or 0, people = ns.Players:PlannerPeopleCopy() }   -- who was in each slot (1.5.0)
  for i, c in ipairs(ns.db.savedComps) do
    if c.name == name then ns.db.savedComps[i] = entry; ns:Print("Updated '" .. name .. "'."); self:QueueRefresh(); return end
  end
  table.insert(ns.db.savedComps, entry)
  ns:Print("Saved '" .. name .. "'.")
  self:QueueRefresh()
end

function UI:CopyLiveToBuilder()
  local slots = Analysis:RosterToSlots(ns.Tracker:GetComp())
  for s = 1, ns.NUM_SLOTS do
    local m = slots[s]
    ns.db.currentComp[s] = (m and m.specID) or 0
    ns.db.currentPeople[s] = false   -- the real party, never a saved player's name (R1)
  end
  ns:Fire("COMP_CHANGED", "copy")
  self:SetCompMode("planner")
  self:SetTab("composition")
end

-- "  +Battle Shout" style tag for the raid buff a profile brings (slot rows).
function UI:BuffTag(profile)
  if not profile or not profile.buffs or #profile.buffs == 0 then return "" end
  local names = {}
  for _, key in ipairs(profile.buffs) do
    for _, b in ipairs(UD.BUFFS) do if b.key == key then names[#names + 1] = ns.Links:Buff(b.key) end end
  end
  if #names == 0 then return "" end
  return "  " .. HEX.good .. "+|r" .. table.concat(names, " ")
end

local function RoleShort(role)
  return role == "TANK" and "TANK" or role == "HEALER" and "HEAL" or role == "DAMAGER" and "DPS" or "?"
end

-- The group Composition and Plan work on: your party, or the planner's slots.
-- Returns members, slotMembers, slotRoles, live.
-- withReserved: Composition counts reserved slots (1.5.0) like members; the Plan tab doesn't
-- (assignments are for the players who are here).
function UI:GroupInputs(withReserved)
  local db = ns.db
  local live = ns.state.mode == "live"
  local members, slotMembers, slotRoles = {}, {}, ns.SLOT_ROLES
  if live then
    slotMembers = Analysis:RosterToSlots(withReserved and ns.Players:LiveComp() or ns.Tracker:GetComp())
    for s = 1, ns.NUM_SLOTS do if slotMembers[s] then members[#members + 1] = slotMembers[s] end end
  else
    for s = 1, ns.NUM_SLOTS do
      local id = db.currentComp[s]
      if id and id ~= 0 and UD:GetSpec(id) then
        -- person: a saved player picked for this slot (shown on the slot only; the analysis and
        -- every post keep the spec label, so names never reach chat).
        local who = ns.Players:PlannerPerson(s)
        slotMembers[s] = { specID = id, person = who and who.full or nil }
        members[#members + 1] = slotMembers[s]
      end
    end
  end

  -- "You": the live party's player, or the first planner slot holding your current spec.
  if not live then
    local mine = ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID()
    for s = 1, ns.NUM_SLOTS do
      if mine and slotMembers[s] and slotMembers[s].specID == mine then slotMembers[s].isPlayer = true; break end
    end
  end
  return members, slotMembers, slotRoles, live
end

function UI:RefreshComp()
  local cp = self.cp
  local db = ns.db
  local settings = db.settings
  local members, slotMembers, slotRoles, live = self:GroupInputs(true)
  cp.modeBtn.text:SetText(self:ModeLabel())
  local dungeonKey, source = ns:GetEffectiveDungeon()
  local r = Analysis:Analyze(members, dungeonKey, settings)
  -- Previewing an applicant (hosting, panel view): show the group as it would be with them.
  local panel = self:AppPanelOn(live)
  if not panel then cp.preview = nil end
  local pev = panel and self:PreviewApplicant()
  -- The real group, kept for Best key and /ens report even while an applicant is previewed.
  local realR, realMembers = r, members
  local previewSlots = {}
  self.previewWas = nil
  if pev and pev.after then
    self.previewWas = {}
    -- rows is a cap -> row map (not a list), so pairs.
    for cap, row in pairs(Analysis:Readiness(r, settings).rows or {}) do self.previewWas[cap] = row.status end
    for _, m in ipairs(pev.members) do
      for s = 1, ns.NUM_SLOTS do
        if not slotMembers[s] and not previewSlots[s] and slotRoles[s] == (m.role or (m.specID and UD:GetSpec(m.specID) and UD:GetSpec(m.specID).role)) then
          previewSlots[s] = m; break
        end
      end
    end
    r = pev.after
    members = r.members
  end

  -- Dungeon bar
  if dungeonKey and DD.list[dungeonKey] then
    cp.dungeonBtn.text:SetText(self:DungeonLabel(dungeonKey))
  else
    cp.dungeonBtn.text:SetText(HEX.muted .. "No dungeon selected|r")
  end
  -- Short note beside the picker; the full sentence on hover.
  local note, full = "", nil
  local autoKey = ns:AutoDungeon()
  if source == "auto" then
    if ns.state.autoSource == "listing" then note, full = "From your listing", "Auto: from your Group Finder listing."
    else note, full = "You're in it", "Auto: the dungeon you're in." end
  elseif source == "keystone" then
    local _, lvl = ns:OwnKeystoneDungeon()
    local lv = lvl and (" (+" .. lvl .. ")") or ""
    note, full = "From your keystone" .. lv, "Auto: your keystone" .. lv .. "."
  elseif source == "manual" and autoKey and autoKey ~= dungeonKey then
    note, full = "Your pick; Auto: " .. DD.list[autoKey].name, "Your pick. Auto would be " .. DD.list[autoKey].name .. "."
  elseif not dungeonKey and source == nil then
    if live then note, full = "Nothing detected; pick one", "No listing or dungeon detected; pick one."
    else note, full = "No keystone; pick one", "No keystone found; pick a dungeon." end
  end
  cp.dungeonNote:SetText(note)
  cp.noteBtn.tip = full
  cp.noteBtn:SetShown(full ~= nil)
  cp.compactBtn.text:SetText(settings.compact and "Full view" or "Summary view")
  cp.compactBtn.tooltip = settings.compact and "Show every need, including covered ones"
    or "Summary view: the strip and the gaps only"

  local ready = Analysis:Readiness(r, settings)
  cp.lastReady = ready
  self:RenderSummaryStrip(r, ready, dungeonKey)

  -- Slot rows (with what each player brings)
  local memberIndex, idx = {}, 0
  for s = 1, ns.NUM_SLOTS do if slotMembers[s] then idx = idx + 1; memberIndex[s] = idx end end
  for s = 1, ns.NUM_SLOTS do
    local row = cp.slotRows[s]
    local m = slotMembers[s]
    row.role:SetText(RoleShort(slotRoles[s]))
    row.clear:SetShown(not live and m ~= nil)
    row.tip = nil
    if m and m.specID and UD:GetSpec(m.specID) then
      local p = UD:GetSpec(m.specID)
      SetSpecIcon(row.icon, m.specID, p.class)
      row.icon:SetDesaturated(false)
      -- Planner specs as players write them ("Veng Demon Hunter"); party members keep their names.
      local full = UD:SpecName(m.specID) .. " " .. UD:ClassName(p.class)
      if m.person then
        row.name:SetText(select(4, Util.ClassColor(p.class)) .. (m.person:match("^([^%-]+)") or m.person) .. "|r"
          .. HEX.muted .. "  " .. UI.ShortLabel(full) .. "|r")
      else
        row.name:SetText(select(4, Util.ClassColor(p.class)) .. (m.label or UI.ShortLabel(full)) .. "|r")
      end
      local badges, tip = self:SlotBadges(r, memberIndex[s])
      row.sub:SetText((m.reserved and (HEX.accent .. "held for a friend|r  ") or "") .. badges .. UI:BuffTag(p) .. (p.verify and "  (kit unconfirmed)" or ""))
      row.tip = (m.person and (m.person .. " (Saved players)\n") or "") .. (m.reserved and "Reserved slot: counts in Needs and Fill group's checks; suggestions and Fill group leave it open. Release it from the Applicants tab's Fill group band or Settings > Fill group.\n" or "")
        .. full .. "\n" .. (p.range and (p.range .. "\n") or "") .. tip
    elseif m and m.classFile then
      SetSpecIcon(row.icon, nil, m.classFile)
      row.icon:SetDesaturated(true)
      local _, _, _, hex = Util.ClassColor(m.classFile)
      row.name:SetText(hex .. (m.label or UD:ClassName(m.classFile)) .. "|r")
      local badges, tip = self:SlotBadges(r, memberIndex[s])
      row.sub:SetText(HEX.muted .. "spec pending|r " .. badges .. UI:BuffTag(UD:ClassCommonProfile(m.classFile)))
      row.tip = UD:ClassName(m.classFile) .. " - spec pending (only what every spec has is counted)\n" .. tip
    elseif previewSlots[s] then
      local m = previewSlots[s]
      local p = m.specID and UD:GetSpec(m.specID)
      SetSpecIcon(row.icon, p and m.specID or nil, m.classFile)
      row.icon:SetDesaturated(false)
      local _, _, _, hex = Util.ClassColor(m.classFile)
      row.name:SetText(hex .. (p and UI.ShortLabel(UD:SpecName(m.specID) .. " " .. UD:ClassName(p.class)) or UD:ClassName(m.classFile)) .. "|r")
      row.sub:SetText(HEX.accent .. "Preview: " .. tostring(m.name or "applicant") .. "|r")
      row.tip = "Previewing this applicant in your group. Click their row again (or another) to change."
    else
      row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      row.icon:SetDesaturated(true)
      row.name:SetText(HEX.muted .. (live and "Open slot" or "Empty") .. "|r")
      row.sub:SetText(live and "waiting for a player" or "Click to choose a spec")
    end
    row:SetBackdropBorderColor(unpack(previewSlots[s] and C.accent or C.border))
  end

  -- Left: applicants (live), suggestions for open slots, saved comps (builder)
  cp.actions:SetShown(not live)
  cp.liveStatus:SetShown(live and not panel)
  cp.appPanel:SetShown(panel)
  cp.sideList.sf:SetShown(not panel)
  if panel then self:RenderAppPanel() end
  local side = cp.sideList
  side:Clear()
  if live then
    local T = ns.Tracker
    local status
    if not IsInGroup() and not T.hosting then status = "Not in a group and no active listing."
    elseif T.hosting then status = "Hosting a Group Finder listing."
    else status = "In a party (no active listing)." end
    if T.inRaid then status = status .. " Raid group: showing first 5." end
    cp.liveStatus:SetText(status)
    if T.hosting and not panel then
      side:Add(HEX.accent .. "> Show applicants here|r", { size = 11, gap = 3,
        onClick = function() ns.db.settings.compApplicants = "panel"; UI:QueueRefresh() end,
        tooltip = "Your best-fit applicants under the slots, with Invite and a preview in your group" })
      side:Header("Applicants (" .. #T.applicants .. ")")
      if #T.applicants == 0 then side:Add("No pending applicants.", { color = C.muted }) end
      local _, evals = ns.ApplicantFit:ForLiveGroup()
      for _, ev in ipairs(evals) do
        local id = ev.applicantID
        side:Add(UI:RatingTag(ev) .. "  " .. UI:ApplicantNames(ev), {
          indent = 4, gap = 1,
          onClick = function() UI.ap.selected = id; UI:SetTab("applicants") end,
          tooltip = "Click for the full fit breakdown",
        })
        side:Add(HEX.muted .. ev.headline .. "|r", { indent = 18, size = 11, gap = 4 })
      end
    end
  end
  self.cp.lastAnalysis = realR
  self.cp.lastMembers = realMembers
  if self.bestKey and self.bestKey:IsShown() then self:RenderBestKey() end
  self:RenderSuggestions(side, slotMembers, slotRoles, dungeonKey, settings, live)
  if not live then self:RenderQuickSaved(side) end
  side:Finish()

  self:RenderReadiness(cp.ready, r, ready, members, dungeonKey, settings.compact)
end

---------------------------------------------------------------------------
-- Composition mode: your party, or the planner (automatic by default).
---------------------------------------------------------------------------
function UI:ModeLabel()
  local m = ns.db.settings.compMode or "auto"
  local live = ns.state.mode == "live"
  if m == "auto" then return "Auto: " .. (live and "My party" or "Planner") end
  return m == "party" and "My party" or "Planner"
end

function UI:SetCompMode(m)
  ns.db.settings.compMode = m
  if self.currentTab == "composition" or self.currentTab == "plan" then self:SetTab(self.currentTab) end
end

function UI:OpenModeMenu(anchor)
  local m = ns.db.settings.compMode or "auto"
  self:ShowMenu(anchor, {
    { text = "Automatic", selected = m == "auto", onClick = function() UI:SetCompMode("auto") end,
      tooltip = "Your party when you're in a group or have a listing; the planner otherwise" },
    { text = "Planner", selected = m == "planner", onClick = function() UI:SetCompMode("planner") end,
      tooltip = "Pick specs for each slot yourself" },
    { text = "My party", selected = m == "party", onClick = function() UI:SetCompMode("party") end,
      tooltip = "Always your current party (and applicants when you host)" },
  })
end

---------------------------------------------------------------------------
-- Plan tab: who handles what. Left: your assignments and the Bloodlust timing. Right: every
-- cast's assignments, the kick order and posting.
---------------------------------------------------------------------------
function UI:BuildPlanPage()
  local page = PageFrame(self.frame)
  self.pages.plan = page
  local pl = {}
  self.pl = pl
  local bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT", 12, -10); bar:SetPoint("TOPRIGHT", -12, -10); bar:SetHeight(30)
  local lbl = Text(bar, 12, C.muted); lbl:SetPoint("LEFT", 0, 0); lbl:SetText("Plan for:")
  pl.dungeonBtn = Dropdown(bar, 280, 28, function(btn) UI:OpenDungeonMenu(btn) end)
  pl.dungeonBtn:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
  SetFontSize(pl.dungeonBtn.text, 13)
  pl.modeBtn = Dropdown(bar, 150, 26, function(btn) UI:OpenModeMenu(btn) end)
  pl.modeBtn:SetPoint("RIGHT", 0, 0)
  pl.note = Text(bar, 11, C.muted); pl.note:SetPoint("LEFT", pl.dungeonBtn, "RIGHT", 10, 0)
  pl.note:SetPoint("RIGHT", pl.modeBtn, "LEFT", -8, 0); pl.note:SetWordWrap(false)

  local left = Panel(page)
  left:SetPoint("TOPLEFT", 12, -48); left:SetPoint("BOTTOMLEFT", 12, 12); left:SetWidth(400)
  pl.leftPanel = left
  -- Panel titles (issue #5): the left panel holds your assignments and the Bloodlust plan, so
  -- it's "Your plan"; the right one names the dungeon in its title instead of a second header.
  local lt = AccentText(left); lt:SetPoint("TOPLEFT", 10, -8); lt:SetText("Your plan")
  pl.leftTitle = lt
  pl.mine = LineList(left, 390, H - 41 - 48 - 12 - 34):Fill(6, -28, -6, 6)
  local right = Panel(page)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); right:SetPoint("BOTTOMRIGHT", -12, 12)
  pl.rightPanel = right
  local rt = AccentText(right); rt:SetPoint("TOPLEFT", 10, -8); rt:SetPoint("RIGHT", -10, 0); rt:SetText("Assignments")
  rt:SetWordWrap(false)
  pl.rightTitle = rt
  -- Post buttons (issue #9): real buttons in a row at the bottom of the assignments panel, the
  -- chat style link beside them; hovering a button previews the exact text it sends.
  local posts = CreateFrame("Frame", nil, right)
  posts:SetPoint("BOTTOMLEFT", 8, 8); posts:SetPoint("BOTTOMRIGHT", -8, 8); posts:SetHeight(26)
  pl.posts = posts
  pl.postPlanBtn = Button(posts, "Post assignments", 140, 24, function() UI:PostPlan() end)
  pl.postPlanBtn:SetPoint("LEFT", 0, 0)
  pl.postGapsBtn = Button(posts, "Post gaps", 96, 24, function() UI:PostGaps() end)
  pl.postGapsBtn:SetPoint("LEFT", pl.postPlanBtn, "RIGHT", 6, 0)
  for _, b in ipairs({ pl.postPlanBtn, pl.postGapsBtn }) do
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end  -- the tooltip says why it's off
  end
  pl.chatStyleBtn = FlatButton(posts, "Chat style: full", 120, 22, function() UI:OpenSettings("chat") end)
  pl.chatStyleBtn:SetPoint("LEFT", pl.postGapsBtn, "RIGHT", 8, 0)
  pl.chatStyleBtn.tooltip = "Choose full or short party-chat posts"
  pl.list = LineList(right, 480, H - 41 - 48 - 12 - 34 - 34):Fill(6, -28, -6, 40)
  self:LayoutComp()
end

function UI:RefreshPlan()
  local pl = self.pl
  local members, _, _, live = self:GroupInputs()
  local dungeonKey = ns:GetEffectiveDungeon()
  local r = Analysis:Analyze(members, dungeonKey, ns.db.settings)
  self.cp.lastAnalysis, self.cp.lastMembers = r, members
  pl.dungeonBtn.text:SetText(dungeonKey and DD.list[dungeonKey] and self:DungeonLabel(dungeonKey) or (HEX.muted .. "No dungeon selected|r"))
  pl.modeBtn.text:SetText(self:ModeLabel())
  pl.note:SetText(r.filled == 0 and (live and "No party yet." or "No players in the planner yet: add them on Composition.")
    or ((live and "Your party" or "The planner's group") .. ": " .. r.filled .. " player" .. (r.filled == 1 and "" or "s") .. "."))
  local assign = (r.filled > 0 and r.dungeon and not r.dungeon.unknown) and ns.Assignments:Build(r) or nil
  local mine = pl.mine
  mine:Clear()
  self:RenderYourJob(mine, r, assign, live)
  if self.RenderLust then self:RenderLust(mine, dungeonKey) end
  if r.filled == 0 then
    mine:Add(HEX.muted .. "Add players on the Composition tab (or join a group) to get assignments.|r", { size = 11 })
  end
  mine:Finish()
  pl.rightTitle:SetText(dungeonKey and DD.list[dungeonKey] and ("Assignments: " .. DD.list[dungeonKey].name) or "Assignments")
  local L = pl.list
  L:Clear()
  self:RenderCheatSheet(L, dungeonKey, r, assign, true)
  if ns.Assignments:OverrideCount() > 0 then
    L:Space(4)
    L:Add(HEX.accent .. "> Reset all assignments to automatic|r", { size = 11, gap = 3,
      onClick = function() ns.Assignments:ClearOverrides() end,
      tooltip = "Drop the changes you made by hand (they only last this session anyway)" })
  end
  self:RenderPostGaps(L, r)
  L:Finish()
  self:UpdatePostButtons(r)
end

-- Needs detail under each analysis check: what in the dungeon asks for it and which
-- classes (and abilities) could cover it. Classes that fit an open role come first.
local NEED_MAX_CLASSES = 4

local function SourceName(req)
  local src = req.source or ""
  return (src:match("^([^,(]+)") or src):gsub("%s+$", "")
end

function UI:CovererLine(c)
  local _, _, _, hex = Util.ClassColor(c.classFile)
  local abil = {}
  for _, a in ipairs(c.abilities) do
    local label = ns.Links:Ability(a.name, a.key)
    if not a.allSpecs then
      local specs = {}
      for _, id in ipairs(a.specs) do specs[#specs + 1] = UD:SpecName(id) end
      label = label .. HEX.muted .. " (" .. table.concat(specs, ", ") .. ")|r"
    end
    if a.talent then label = label .. HEX.muted .. "*|r" end
    abil[#abil + 1] = label
  end
  local name = c.inRole and (hex .. UD:ClassName(c.classFile) .. "|r") or (HEX.muted .. UD:ClassName(c.classFile) .. "|r")
  return name .. HEX.muted .. ": |r" .. table.concat(abil, ", ")
end

---------------------------------------------------------------------------
-- Left column under the slots: dungeon cheat sheet, quick saved comps, post gaps.
---------------------------------------------------------------------------
local SHEET = {
  { cat = "interrupts", label = "KICK" },
  { cat = "dispels",    label = "DISPEL" },
  { cat = "stops",      label = "STOP" },
  { cat = "tank",       label = "TANK" },
  { cat = "other",      label = "ALSO" },
  { cat = "affixes",    label = "AFFIX" },
}
local SHEET_SEV = { critical = 1, high = 2, medium = 3, low = 4 }
local SHEET_MAX = 5   -- per category

-- The selected dungeon's must-handle casts and debuffs, most dangerous first: critical,
-- then high, then medium (issue #6: medium ones used to be dropped whenever a category had a
-- critical or high one, hiding assignments). Low severity stays off the sheet. Each
-- category folds after SHEET_MAX behind "+N more".
function UI:CheatSheetRows(dungeonKey)
  local d = dungeonKey and DD.list[dungeonKey]
  if not d then return nil end
  local cats = ns.db.settings.dungeonCategories or {}
  local all = d.requirements
  if ns.Affixes and cats.affixes ~= false then
    all = {}
    for _, q in ipairs(d.requirements) do all[#all + 1] = q end
    for _, q in ipairs(ns.Affixes:Requirements(dungeonKey, ns.Affixes:KeyLevel(dungeonKey))) do all[#all + 1] = q end
  end
  local out = {}
  for _, def in ipairs(SHEET) do
    if cats[def.cat] ~= false then
      local reqs = {}
      for _, req in ipairs(all) do
        if not req.invalid and DD:CategoryOf(req) == def.cat then reqs[#reqs + 1] = req end
      end
      table.sort(reqs, function(a, b)
        local sa, sb = SHEET_SEV[a.severity] or 9, SHEET_SEV[b.severity] or 9
        if sa ~= sb then return sa < sb end
        return (a.id or "") < (b.id or "")
      end)
      local pick = {}
      for _, req in ipairs(reqs) do
        if (SHEET_SEV[req.severity] or 9) <= SHEET_SEV.medium then pick[#pick + 1] = req end
      end
      if #pick > 0 then out[#out + 1] = { label = def.label, cat = def.cat, reqs = pick } end
    end
  end
  return out
end

-- "Your assignments": your own kicks, dispels and stops from the plan, at the top of the Plan tab.
function UI:RenderYourJob(list, r, plan, live)
  if not plan or plan.empty then return end
  local me
  for i, m in ipairs(r.members) do if m.isPlayer then me = i; break end end
  if not me then
    if not live then
      local mine = ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID()
      if mine and UD:GetSpec(mine) then
        list:Header("Your assignments")
        list:Add(HEX.muted .. "Put your own spec (" .. UD:SpecName(mine) .. " " .. UD:ClassName(UD:GetSpec(mine).class)
          .. ") in a slot to see what you'd be responsible for.|r", { size = 10, gap = 4 })
      end
    end
    return
  end
  local m = r.members[me]
  local job
  for _, j in ipairs(ns.Assignments:PlayerJobs(plan, true)) do if j.index == me then job = j end end
  list:Header("Your assignments")
  list:Add(HEX.muted .. "As " .. m.label .. ". Kick your own casts first, help when free.|r", { size = 10, gap = 2 })
  -- Items are { text, ability }: casts answered with the same ability share one " - Pummel"
  -- at the end of their run instead of repeating it after every cast (first-seen order kept).
  local function block(label, items, color)
    if #items == 0 then return end
    local groups, byAb = {}, {}
    for _, it in ipairs(items) do
      if type(it) == "string" then groups[#groups + 1] = { texts = { it } }
      else
        local g = it.ability and byAb[it.ability]
        if not g then g = { texts = {}, ability = it.ability }; groups[#groups + 1] = g; if it.ability then byAb[it.ability] = g end end
        g.texts[#g.texts + 1] = it.text
      end
    end
    local parts = {}
    for _, g in ipairs(groups) do
      parts[#parts + 1] = table.concat(g.texts, HEX.muted .. ";|r ") .. (g.ability and (HEX.muted .. " - " .. g.ability .. "|r") or "")
    end
    list:Add((color or HEX.text) .. label .. "|r " .. table.concat(parts, HEX.muted .. ";|r "), { indent = 6, size = 11, gap = 2 })
  end
  local kicks, stops, dispels, backups = {}, {}, {}, {}
  if job then
    for _, k in ipairs(job.kicks) do
      kicks[#kicks + 1] = { text = k.cast .. (k.mob and (HEX.muted .. " [" .. k.mob .. "]|r") or "")
        .. (k.pos and (" " .. HEX.accent .. ns.Assignments.Ord(k.pos) .. " of " .. k.of .. "|r") or ""), ability = k.ability }
    end
    for _, st in ipairs(job.stops) do
      stops[#stops + 1] = { text = st.cast .. (st.instead and (HEX.muted .. " (" .. st.instead .. ")|r") or ""), ability = st.ability }
    end
    for _, d in ipairs(job.dispels) do
      dispels[#dispels + 1] = { text = d.cast .. HEX.muted .. " (" .. d.type .. ")|r", ability = d.ability }
    end
    for _, bk in ipairs(job.backups) do backups[#backups + 1] = bk.cast .. (bk.type and (" (" .. bk.type .. ")") or "") end
  end
  block("Kick:", kicks); block("Stop:", stops); block("Dispel:", dispels)
  block("Backup for:", backups, HEX.muted)
  if #kicks + #stops + #dispels + #backups == 0 then
    list:Add(HEX.muted .. "No kicks or dispels assigned to you here. Help kick when free.|r", { indent = 6, size = 11, gap = 2 })
  end
  list:Space(4)
end

-- Suggested classes for EMPTY slots, best fit first, each with why.
local SUGGEST_REASONS = 3
local ROLE_PLURAL = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
function UI:RenderSuggestions(side, slotMembers, slotRoles, dungeonKey, settings, live)
  local groups = Analysis:SuggestClasses(slotMembers, slotRoles, dungeonKey, settings, 4)
  if #groups == 0 then
    if not live then
      side:Header("Suggested for open slots")
      side:Add(HEX.muted .. "All five slots are filled.|r", { size = 11 })
    end
    return
  end
  side:Header("Suggested for open slots")
  local totalOpen = 0
  for _, g in ipairs(groups) do totalOpen = totalOpen + g.open end
  for _, g in ipairs(groups) do
    side:Add(HEX.accent .. ROLE_PLURAL[g.role] .. "|r" .. HEX.muted .. "  -  " .. g.open .. " open|r", { size = 10, gap = 2 })
    if #g.classes == 0 then
      side:Add(HEX.muted .. "Any " .. ROLE_PLURAL[g.role] .. " works: nothing left that this slot would fix.|r",
        { indent = 8, size = 11, gap = 4 })
    end
    for i, c in ipairs(g.classes) do
      local _, _, _, hex = Util.ClassColor(c.classFile)
      local _, icon = ns.API.GetSpecInfoByID(c.best)
      local specs = {}
      for _, id in ipairs(c.specs) do specs[#specs + 1] = UD:SpecName(id) end
      local line = HEX.muted .. i .. ".|r " .. (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "")
        .. hex .. UD:ClassName(c.classFile) .. "|r" .. HEX.muted .. "  " .. table.concat(specs, " / ") .. "|r"
      local slot, best = g.slot, c.best
      side:Add(line, {
        indent = 4, size = 12, gap = 1,
        onClick = (not live) and function()
          ns.db.currentComp[slot] = best
          ns.db.currentPeople[slot] = false   -- (R1)
          ns:Fire("COMP_CHANGED", "suggest")
        end or nil,
        tooltip = (not live) and ("Click to put " .. UD:SpecName(best) .. " " .. UD:ClassName(c.classFile) .. " in the open slot") or nil,
      })
      local wkey = "why:" .. g.role .. ":" .. c.classFile
      local all = UI:IsOpen(wkey, false)
      local why = {}
      for j = 1, (all and #c.reasons or math.min(SUGGEST_REASONS, #c.reasons)) do why[j] = c.reasons[j] end
      side:Add(HEX.muted .. "Why: |r" .. table.concat(why, HEX.muted .. "; |r"), { indent = 22, size = 10, gap = 1 })
      UI:MoreLine(side, wkey, #c.reasons - #why, 22, (#c.reasons - #why) == 1 and "reason" or "reasons")
      side:Space(3)
    end
  end
  if totalOpen > 1 then
    side:Add(HEX.muted .. "Ranked as your next pick; the list updates as slots fill.|r", { size = 10, gap = 2 })
  end
end

-- "Ann · Pummel 15s" with the player's class color.
local function DutyName(w)
  local hex = w.class and select(4, Util.ClassColor(w.class)) or HEX.text
  local cd = w.cd and w.cd > 0 and (" " .. w.cd .. "s") or ""
  return hex .. w.label .. "|r" .. HEX.muted .. " - " .. w.ability .. cd .. (w.pending and " (assumed)" or "") .. "|r"
end

-- Spec names shortened the way players write them ("Protection Warrior" -> "Prot Warrior").
-- Live labels (player names) are left alone.
local SPEC_ABBR = {
  ["Protection "] = "Prot ", ["Discipline "] = "Disc ", ["Restoration "] = "Resto ", ["Retribution "] = "Ret ",
  ["Beast Mastery "] = "BM ", ["Marksmanship "] = "MM ", ["Survival "] = "SV ", ["Assassination "] = "Sin ",
  ["Subtlety "] = "Sub ", ["Affliction "] = "Affli ", ["Destruction "] = "Destro ", ["Demonology "] = "Demo ",
  ["Elemental "] = "Ele ", ["Enhancement "] = "Enh ", ["Windwalker "] = "WW ", ["Mistweaver "] = "MW ",
  ["Brewmaster "] = "Brew ", ["Augmentation "] = "Aug ", ["Devastation "] = "Dev ", ["Preservation "] = "Pres ",
  ["Vengeance "] = "Veng ",
}
local function ShortLabel(label)
  label = tostring(label or "?")
  for long, short in pairs(SPEC_ABBR) do
    if label:sub(1, #long) == long then return short .. label:sub(#long + 1) end
  end
  return label
end
UI.ShortLabel = ShortLabel

-- Just the colored name, for the one-line assignment.
local function DutyShort(w)
  local hex = w.class and select(4, Util.ClassColor(w.class)) or HEX.text
  return hex .. ShortLabel(w.label) .. "|r" .. (w.pending and (HEX.muted .. "*|r") or "")
end
-- Full detail for the tooltip: "1st Protection Warrior - Pummel 15s".
local function DutyPlain(w)
  local cd = w.cd and w.cd > 0 and (" " .. w.cd .. "s") or ""
  return tostring(w.label) .. " - " .. tostring(w.ability) .. cd .. (w.pending and " (assumed: spec not known yet)" or "")
end

-- One line per job ("Kick: Prot Warrior > Arms Warrior (~8s), backup Outlaw Rogue"); who uses
-- which ability, the cooldowns and the order are in the line's tooltip.
function UI:RenderAssignment(side, row)
  local indent = 22
  local tip = {}
  local text
  if row.kickers and #row.kickers > 0 then
    local names = {}
    for i, k in ipairs(row.kickers) do
      names[#names + 1] = DutyShort(k)
      tip[#tip + 1] = (#row.kickers > 1 and (ns.Assignments.Ord(i) .. " ") or "") .. DutyPlain(k)
    end
    text = HEX.text .. "Kick: |r" .. table.concat(names, HEX.muted .. " > |r")
      .. ((#row.kickers > 1 and row.every) and (HEX.muted .. " (~" .. row.every .. "s)|r") or "")
    if #row.kickers > 1 and row.every then tip[#tip + 1] = "Together a kick every ~" .. row.every .. "s" end
  elseif row.primary then
    text = HEX.text .. "Dispel: |r" .. DutyShort(row.primary)
    tip[#tip + 1] = "Dispel: " .. DutyPlain(row.primary)
  end
  if row.stoppers then
    local names = {}
    for _, st in ipairs(row.stoppers) do names[#names + 1] = DutyShort(st); tip[#tip + 1] = (row.kickers and "Stop: " or "Instead: ") .. DutyPlain(st) end
    local part = HEX.text .. (row.kickers and "Stop: " or "Instead: ") .. "|r" .. table.concat(names, ", ")
    text = text and (text .. HEX.muted .. "; |r" .. part) or part
  end
  if row.backup then
    local part = HEX.muted .. "backup |r" .. DutyShort(row.backup)
    text = text and (text .. HEX.muted .. ", |r" .. part) or part
    tip[#tip + 1] = "Backup: " .. DutyPlain(row.backup)
  end
  if text then
    tip[#tip + 1] = "Base cooldowns; talents can shorten some."
    local editable = self.currentTab == "plan" and (row.kickers and #row.kickers > 0 or row.primary) and self.cp and self.cp.lastAnalysis
    if row.manual then text = text .. HEX.accent .. "  (set by you)|r" end
    if editable then tip[#tip + 1] = "Click to choose who takes it." end
    side:Add(text, { indent = indent, size = 10, gap = 1, tooltip = table.concat(tip, "\n"),
      onClick = editable and function(btn) UI:OpenAssignMenu(btn, row) end or nil })
  end
  for _, n in ipairs(row.notes) do
    side:Add((row.severe and HEX.bad or HEX.warn) .. n .. "|r", { indent = indent, size = 10, gap = 1 })
  end
end

-- Pick who takes a cast. Kicks: click players to add or drop them from the rotation (the
-- order you add them is the kick order). Dispels: pick the one who dispels it.
function UI:OpenAssignMenu(anchor, row)
  local AS = ns.Assignments
  local r = self.cp and self.cp.lastAnalysis
  if not (r and row and row.req) then return end
  local choices, kind = AS:Choices(r, row.req)
  local current = {}
  if kind == "kick" then for _, k in ipairs(row.kickers or {}) do current[#current + 1] = k.index end
  elseif row.primary then current[1] = row.primary.index end
  local isIn = {}
  for pos, i in ipairs(current) do isIn[i] = pos end
  local items = { { text = (kind == "kick" and "Who kicks " or "Who removes ") .. row.cast .. "?", header = true } }
  for _, c in ipairs(choices) do
    local label = c.label .. "  " .. c.ability .. (c.cd and c.cd > 0 and (" " .. c.cd .. "s") or "")
    if kind == "kick" and isIn[c.index] then label = ns.Assignments.Ord(isIn[c.index]) .. ": " .. label end
    items[#items + 1] = { text = label, selected = isIn[c.index] ~= nil,
      tooltip = kind == "kick" and (isIn[c.index] and "Click to take them out of the rotation" or "Click to add them to the rotation")
        or "Click to make them the dispeller",
      onClick = function()
        local list = {}
        if kind == "kick" then
          for _, i in ipairs(current) do if i ~= c.index then list[#list + 1] = i end end
          if not isIn[c.index] then list[#list + 1] = c.index end
          if #list == 0 then return end   -- somebody has to kick it
        else
          list = { c.index }
        end
        AS:SetOverride(r, row.req.id, kind, list)
      end }
  end
  if AS:HasOverride(row.req.id) then
    items[#items + 1] = { text = "Back to automatic", onClick = function() AS:ClearOverride(row.req.id) end }
  end
  if anchor then self:ShowMenu(anchor, items) end
  return items
end

-- AFFIX lines name their need, like DISPEL lines name the type (issue #7: Xal'atath's Guile
-- has two requirements with the same source, which read as a duplicate).
local SHEET_NEED_LABEL = {
  group_defensive = "Group defensives", external_defensive = "Externals", interrupt = "Kicks",
  stop = "Stops", aoe_stop = "AoE stops",
}
function UI:SheetNeedLabel(need)
  return SHEET_NEED_LABEL[need] or (self.NEEDS_TEXT_LABELS and self.NEEDS_TEXT_LABELS[need]) or UD:CapShort(need)
end

-- noHeader: the caller's panel title already names the dungeon (the Plan tab).
function UI:RenderCheatSheet(side, dungeonKey, r, plan, noHeader)
  local rows = self:CheatSheetRows(dungeonKey)
  local fromComp = plan ~= false
  if plan == nil then plan = r and r.filled > 0 and r.dungeon and ns.Assignments:Build(r) or nil end
  if plan == false then plan = nil end
  if self.cp and fromComp then self.cp.lastPlan = plan end
  if not rows then
    if not noHeader then side:Header(fromComp and "Assignments" or "Key needs") end
    side:Add(HEX.muted .. "Pick a dungeon to see its must-kick, must-dispel and must-stop list.|r", { size = 11 })
    return
  end
  if not noHeader then side:Header((fromComp and "Assignments: " or "Key needs: ") .. DD.list[dungeonKey].name) end
  for _, row in ipairs(rows) do
    side:Add(HEX.accent .. row.label .. "|r", { size = 10, gap = 1 })
    local skey = "sheet:" .. row.cat
    local showAll = UI:IsOpen(skey, false)
    local shownN = showAll and #row.reqs or math.min(SHEET_MAX, #row.reqs)
    for i = 1, shownN do
      local req = row.reqs[i]
      local text = Analysis.Decorate(req.source or "", req.need, req.dungeon)
      if row.cat == "dispels" then text = HEX.muted .. UD:CapLabel(req.need):gsub(" dispel", "") .. ":|r " .. text end
      if row.cat == "affixes" then text = HEX.muted .. self:SheetNeedLabel(req.need) .. ":|r " .. text end
      if req.severity == "critical" then text = TEX_NO .. " " .. text end
      if req.confidence ~= "verified" then text = text .. HEX.warn .. " [unconfirmed]|r" end
      side:Add(text, { indent = 8, size = 11, gap = 1 })
      -- "Interrupt every cast." under KICK says what the heading already says.
      if req.note and ns.db.settings.explain ~= false and not (row.cat == "interrupts" and req.note == "Interrupt every cast.") then
        side:Add(HEX.muted .. req.note .. "|r", { indent = 22, size = 10, gap = 1 })
      end
      local a = plan and plan.byReq[req.id]
      if a then self:RenderAssignment(side, a) end
    end
    UI:MoreLine(side, skey, #row.reqs - shownN, 8, (#row.reqs - shownN) == 1 and "cast" or "casts")
    side:Space(3)
  end
  if plan and not plan.empty then
    local pri = ns.Assignments:Priority(plan)
    if pri then side:Add(HEX.text .. "Two casts at once? Kick first:|r " .. pri, { size = 10, gap = 2 }) end
  end
end

local QUICK_SAVED = 4
function UI:RenderQuickSaved(side)
  side:Header("Saved comps")
  local list = {}
  for _, c in ipairs(ns.db.savedComps) do list[#list + 1] = c end
  if #list == 0 then
    side:Add(HEX.muted .. "None yet. Name a comp below and click Save.|r", { size = 11 })
    return
  end
  table.sort(list, function(a, b) return (a.created or 0) > (b.created or 0) end)
  local showAllSaved = UI:IsOpen("savedq", false)
  local shownSaved = showAllSaved and #list or math.min(QUICK_SAVED, #list)
  for i = 1, shownSaved do
    local c = list[i]
    local icons = {}
    for s = 1, ns.NUM_SLOTS do
      local id = c.slots[s]
      local _, icon = ns.API.GetSpecInfoByID(id)
      icons[#icons + 1] = icon and ("|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t") or "|TInterface\\Icons\\INV_Misc_QuestionMark:16:16|t"
    end
    local dname = c.dungeon and DD.list[c.dungeon] and ("  " .. HEX.muted .. DD.list[c.dungeon].name .. "|r") or ""
    side:Add(table.concat(icons, "") .. "  " .. c.name .. dname, {
      size = 11, gap = 3,
      onClick = function() UI:LoadSavedComp(c) end,
      tooltip = "Click to load into the planner",
    })
  end
  if #list > QUICK_SAVED then
    UI:MoreLine(side, "savedq", #list - shownSaved, 0, (#list - shownSaved) == 1 and "saved comp" or "saved comps")
  end
end

-- Plain-text chat lines (no links or icons: chat strips them) summarizing the gaps. Usually one
-- line; a long list goes on as "(cont.)" lines rather than being cut.
function UI:GapsLines(r)
  local needs = Analysis:StillNeeded(r)
  local missing, thin = {}, {}
  for _, e in ipairs(needs) do
    local label = e.title
    -- "short" chat style: just the needs, no casts.
    if e.sources[1] and ns.db.settings.chatStyle ~= "short" then label = label .. " (" .. SourceName(e.sources[1]) .. ")" end
    if e.status == "missing" then missing[#missing + 1] = label else thin[#thin + 1] = label end
  end
  local dk = r.dungeon and not r.dungeon.unknown and r.dungeon.key
  local tag = "[Ensemble]"
  local prefix = tag .. (dk and DD.list[dk] and (" " .. DD.list[dk].name) or "") .. " - "
  if #missing == 0 and #thin == 0 then return { prefix .. "nothing missing." } end
  local parts = {}
  if #missing > 0 then parts[#parts + 1] = "Missing: " .. table.concat(missing, ", ") end
  if #thin > 0 then parts[#parts + 1] = "Thin: " .. table.concat(thin, ", ") end
  return ns.Util.ChatWrap(prefix, table.concat(parts, ". ") .. ".", tag .. " (cont.): ", 250)
end

-- The same post as one text (tooltips and previews).
function UI:GapsMessage(r)
  return table.concat(self:GapsLines(r), "\n")
end

-- "What we need": a short line for your Group Finder listing's description, so players who
-- bring what the group lacks apply (and fewer have to be declined). Open roles, then the
-- needs still missing (most severe first), then thin ones. Plain text; the game's listing
-- box can't be filled by an addon, so it goes to the copy window.
UI.NEEDS_TEXT_MAX = 120
UI.NEEDS_TEXT_LABELS = {   -- what players say in a listing
  interrupt = "Kicks", battle_rez = "Brez", bloodlust = "Lust", dispel_magic = "Magic dispel",
  dispel_curse = "Curse dispel", dispel_poison = "Poison dispel", dispel_disease = "Disease dispel",
  dispel_bleed = "Bleed cleanse", aoe_stop = "AoE stops", stop = "Stops", purge = "Purge", soothe = "Soothe",
  knockback = "Knockback", root = "Roots", external_defensive = "Externals", group_defensive = "Group CDs",
  freedom = "Freedom", movement = "Speed boost", group_stealth = "Stealth/invis skip",
}
function UI:NeedsListingText(r, members)
  local open = ns.ApplicantFit:OpenRoles(members or {})
  local roles = {}
  if open.TANK > 0 then roles[#roles + 1] = "Tank" end
  if open.HEALER > 0 then roles[#roles + 1] = "Healer" end
  if open.DAMAGER > 0 then roles[#roles + 1] = (open.DAMAGER > 1 and (open.DAMAGER .. " DPS") or "DPS") end
  local short = self.NEEDS_TEXT_LABELS
  local missing, thin, seen = {}, {}, {}
  for _, e in ipairs(r and Analysis:StillNeeded(r) or {}) do
    local k = e.keys[1]
    if not seen[k] and not e.unconfirmed then
      seen[k] = true
      local label = short[k] or UD:CapLabel(k)
      if e.status == "missing" then missing[#missing + 1] = label else thin[#thin + 1] = label end
    end
  end
  local parts = {}
  if #roles > 0 then parts[#parts + 1] = "LF " .. table.concat(roles, ", ") end
  local function add(prefix, list)
    if #list == 0 then return end
    local text = prefix .. table.concat(list, ", ")
    while #list > 1 and #table.concat(parts, ". ") + #text > self.NEEDS_TEXT_MAX do
      table.remove(list); text = prefix .. table.concat(list, ", ")
    end
    parts[#parts + 1] = text
  end
  add("Need: ", missing)
  add("Nice to have: ", thin)
  if #parts == 0 then return "Group is full." end
  if #missing == 0 and #thin == 0 then parts[#parts + 1] = "Any spec welcome" end
  return table.concat(parts, ". ") .. "."
end

function UI:CopyNeedsText()
  local r, comp = self:LiveAnalysis()
  local text = self:NeedsListingText(r, comp)
  if not (ns.Verify and ns.Verify:ShowText(text, "what we need: paste it into your listing's description")) then ns:Print(text) end
  return text
end

-- The live group's analysis (party + the dungeon being run), for the listing text.
function UI:LiveAnalysis()
  local comp = ns.Players:LiveComp()   -- reserved slots count (their utility, their role)
  local dk = ns:GetEffectiveDungeon(true)
  local level = ns.ApplicantFit:GetKeyLevel(dk)
  return Analysis:Analyze(comp, dk, ns.db.settings, level and { keyLevel = level } or nil), comp
end

local function ChatSend(msg, channel)
  -- Midnight locks addon chat in some situations (e.g. inside a running key or encounter);
  -- a blocked call doesn't raise a Lua error, so check first and print locally instead.
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and locked then return false end
  end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if not send then return false end
  local ok = pcall(send, msg, channel)
  return ok
end

function UI:PostGaps()
  local r = self.cp and self.cp.lastAnalysis
  if not r or r.filled == 0 then ns:Print("Add players first."); return end
  self:SendLines(self:GapsLines(r), "Gaps")
end

local function ChatLocked()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    return ok and locked and true or false
  end
  return false
end
UI.ChatLocked = ChatLocked

-- Send several lines to party/raid chat a moment apart (so chat doesn't throttle them).
-- Not in a group: printed for you. Chat locked by the game (it can be inside a key):
-- the text opens in the copy window instead, so it can still be pasted by hand.
function UI:SendLines(lines, what)
  if not lines or #lines == 0 then return end
  local channel = (IsInRaid and IsInRaid() and "RAID") or (IsInGroup and IsInGroup() and "PARTY") or nil
  if channel and ChatLocked() then
    if ns.Verify and ns.Verify:ShowText(table.concat(lines, "\n"), (what or "chat text") .. ": chat is blocked right now, copy and paste it") then
      ns:Print("The game is blocking addon chat right now; the text is in the copy window.")
      return
    end
  end
  local function send(i)
    local line = lines[i]
    if not line then return end
    if not (channel and ChatSend(line, channel)) then
      ns:Print(line .. (channel and " (couldn't send to chat here)" or ""))
    end
    if lines[i + 1] then
      if C_Timer and channel then C_Timer.After(0.25, function() send(i + 1) end) else send(i + 1) end
    end
  end
  send(1)
  if not channel then ns:Print("(not in a group: shown only to you)") end
end

-- The assignments chat post, with the Bloodlust plan as its second line.
function UI:PlanChatLines(plan, dk)
  local lines = ns.Assignments:ChatLines(plan, dk and DD.list[dk] and DD.list[dk].name, ns.db.settings.chatStyle)
  local lust = #lines > 0 and dk and ns.Walkthrough and ns.Walkthrough:LustChat(dk)
  if lust then
    -- A long Bloodlust plan goes on as a second "Lust (cont.):" line rather than being cut.
    for i, l in ipairs(ns.Util.ChatWrap("", lust, "Lust (cont.): ", 250)) do table.insert(lines, 1 + i, l) end
  end
  return lines
end

function UI:PostPlan()
  local plan = self.cp and self.cp.lastPlan
  if not plan or plan.empty then ns:Print("No kick or dispel assignments for this dungeon yet."); return end
  local r = self.cp.lastAnalysis
  local dk = r and r.dungeon and r.dungeon.key
  self:SendLines(self:PlanChatLines(plan, dk), "Assignments")
end

-- "Copy what we need" for your listing, at the end of the assignments list (live group only).
-- The Post buttons sit in their own row under the list (UpdatePostButtons).
function UI:RenderPostGaps(side, r)
  if r.filled == 0 then return end
  if ns.state.mode == "live" then
    side:Space(6)
    side:Add(HEX.accent .. "> Copy \"what we need\" for your listing|r", {
      size = 12, gap = 4,
      onClick = function() UI:CopyNeedsText() end,
      tooltip = "For your Group Finder listing's description:\n" .. self:NeedsListingText(r, ns.Tracker:GetComp()),
    })
  end
end

-- The Plan tab's Post buttons: enabled when there's something to post, the tooltip previews
-- the exact text (or says why the button is off).
function UI:UpdatePostButtons(r)
  local pl = self.pl
  if not (pl and pl.postPlanBtn) then return end
  local channel = ((IsInRaid and IsInRaid()) and "raid") or ((IsInGroup and IsInGroup()) and "party") or nil
  local sends = channel and ("Sends to " .. channel .. " chat:\n") or "Not in a group, so this only prints it for you:\n"
  local plan = self.cp and self.cp.lastPlan
  local hasPlayers = r and r.filled > 0
  if hasPlayers and plan and not plan.empty then
    pl.postPlanBtn:Enable()
    pl.postPlanBtn.tooltip = sends .. table.concat(self:PlanChatLines(plan, r.dungeon and r.dungeon.key), "\n")
  else
    pl.postPlanBtn:Disable()
    pl.postPlanBtn.tooltip = hasPlayers and "No kick or dispel assignments for this dungeon yet." or "Add players first."
  end
  if hasPlayers then
    pl.postGapsBtn:Enable()
    pl.postGapsBtn.tooltip = sends .. self:GapsMessage(r)
  else
    pl.postGapsBtn:Disable()
    pl.postGapsBtn.tooltip = "Add players first."
  end
  for _, b in ipairs({ pl.postPlanBtn, pl.postGapsBtn }) do b:SetAlpha(b:IsEnabled() and 1 or 0.5) end
  pl.chatStyleBtn.text:SetText("Chat style: " .. (ns.db.settings.chatStyle == "short" and "short" or "full"))
end

function UI:RenderCoverers(list, keys, ctx, expandId, indent)
  local cov = Analysis:Coverers(keys, ctx.open, ctx.settings)
  if #cov == 0 then
    list:Add(HEX.warn .. "No class can cover this with your current settings.|r", { indent = indent, size = 11 })
    return
  end
  local expanded = UI:IsOpen("cov:" .. tostring(expandId), false)
  list:Add(HEX.muted .. (ctx.anyOpen and "Can cover it:" or "Can cover it (swap):") .. "|r", { indent = indent, size = 11, gap = 1 })
  local shown = 0
  for _, c in ipairs(cov) do
    if expanded or (shown < NEED_MAX_CLASSES and (c.inRole or shown == 0)) then
      list:Add(self:CovererLine(c), { indent = indent, size = 11, gap = 1 })
      shown = shown + 1
    end
  end
  if #cov > shown or expanded then
    list:Add(HEX.accent .. (expanded and "- show fewer" or ("+ " .. (#cov - shown) .. " more classes")) .. "|r", {
      indent = indent, size = 11,
      onClick = function() UI:SetOpen("cov:" .. tostring(expandId), not expanded) end,
      tooltip = expanded and "Collapse" or "Show every class that can cover this",
    })
  end
end

-- "This week (+12): Xal'atath's Guile, Fortified, Tyrannical" plus each affix's advice.
function UI:AffixIcons(active)
  local parts = {}
  for _, a in ipairs(active) do
    parts[#parts + 1] = (a.icon and ("|T" .. a.icon .. ":14:14:0:0|t ") or "") .. a.label
  end
  return table.concat(parts, ", ")
end

function UI:RenderAffixLine(list, d, compact)
  local AF = ns.Affixes
  if not AF or ns.db.settings.dungeonCategories.affixes == false then return end
  local level = AF:KeyLevel(d.key)
  local active, assumed = AF:Active(level)
  if #AF:Current() == 0 then
    list:Add(HEX.muted .. "This week's affixes: not loaded yet.|r", { size = 11, gap = 4 })
    return
  end
  local lvl = "+" .. (level or AF.ASSUMED_LEVEL)
  list:Add(HEX.text .. "Affixes at " .. lvl .. ":|r " .. (#active > 0 and self:AffixIcons(active) or (HEX.muted .. "none|r"))
    .. (assumed and (HEX.muted .. "  (key level unknown: assuming " .. lvl .. "; set it on Applicants)|r") or ""),
    { size = 11, gap = 2 })
  if not compact then
    for _, a in ipairs(active) do
      if a.def and a.def.note then
        list:Add(HEX.muted .. a.label .. ": " .. a.def.note .. "|r", { indent = 10, size = 10, gap = 1 })
      end
    end
  end
  list:Space(3)
end

---------------------------------------------------------------------------
-- Expand / fold state shared by every "+N more" and every Readiness row.
---------------------------------------------------------------------------
UI.expand = {}
function UI:IsOpen(key, default)
  local v = self.expand[key]
  if v == nil then return default and true or false end
  return v
end
function UI:SetOpen(key, v) self.expand[key] = v and true or false; self:QueueRefresh() end

-- Expand all: every Readiness row open, and the "All problems" list (lists inside rows
-- keep their short form).
-- Collapse all: every row folded, problems included, and every expanded list on the page
-- ("+N more" requirements, classes, reasons, casts, saved comps, the problem list) back to
-- its short form. Clicking a single row afterwards opens or folds just that row.
function UI:ExpandAll()
  self.readyMode = "all"
  for k in pairs(self.expand) do if k:find("^row:") or k == "risks" then self.expand[k] = nil end end
  self:QueueRefresh()
end

function UI:CollapseAll()
  self.readyMode = "none"
  for k in pairs(self.expand) do self.expand[k] = nil end
  self:QueueRefresh()
end

-- "can cover: Druid, Monk, Shaman" (class names; those fitting an open role colored),
-- five at a time with a "+N more" toggle.
function UI:ClassListLine(list, keys, openRoles, ekey, indent)
  local cov = Analysis:Coverers(keys, openRoles or {}, ns.db.settings)
  local all = self:IsOpen(ekey, false)
  local names = {}
  for k, c in ipairs(cov) do
    if all or k <= 5 then
      local _, _, _, hex = Util.ClassColor(c.classFile)
      names[#names + 1] = (c.inRole and hex or HEX.muted) .. UD:ClassName(c.classFile) .. "|r"
    end
  end
  list:Add(HEX.muted .. "can cover: |r" .. (#names > 0 and table.concat(names, ", ") or (HEX.warn .. "no class|r")),
    { indent = indent or 22, size = 10, gap = 1 })
  self:MoreLine(list, ekey, #cov - #names, indent or 22, "classes")
end

-- A "+N more" / "show fewer" line that toggles `key`.
function UI:MoreLine(list, key, hiddenCount, indent, noun)
  local open = self:IsOpen(key, false)
  if hiddenCount <= 0 and not open then return end
  list:Add(HEX.accent .. (open and "- show fewer" or ("+ " .. hiddenCount .. " more" .. (noun and (" " .. noun) or ""))) .. "|r", {
    indent = indent or 18, size = 10, gap = 3,
    onClick = function() UI:SetOpen(key, not open) end,
    tooltip = open and "Show fewer" or "Show all",
  })
end

---------------------------------------------------------------------------
-- Summary strip: dungeon, counts, a chip per key need, biggest risks.
---------------------------------------------------------------------------
local READY_TAG = {
  missing = TEX_NO .. " " .. HEX.bad .. "MISSING|r",
  thin    = TEX_WAIT .. " " .. HEX.warn .. "THIN|r",
  ok      = TEX_OK .. " " .. HEX.good .. "OK|r",
  none    = HEX.muted .. "NONE|r",   -- no dash: rows already start with a "+ " or "- " fold marker
}
UI.READY_TAG = READY_TAG
local CHIP_ICON = { missing = TEX_NO, thin = TEX_WAIT, ok = TEX_OK, none = "" }
local CHIP_COLOR = { missing = HEX.bad, thin = HEX.warn, ok = HEX.good, none = HEX.muted }
local ITEM_ICON = { missing = TEX_NO, thin = TEX_WAIT, covered = TEX_OK }

-- noStatus: the line already shows the status tag ("All gaps"), so don't say it twice.
local function RiskText(row, noStatus)
  local t = (noStatus and "" or (row.status == "missing" and "no " or "thin ")) .. row.label
  local it = row.items[1]
  if it and it.status ~= "covered" then
    t = t .. " for " .. ((it.req.source or ""):match("^([^,(]+)") or ""):gsub("%s+$", "")
  end
  if row.severity == "critical" then t = t .. " (critical)" end
  return t
end
UI.RiskText = RiskText

-- Jump to a need in Readiness (list view), opening its row.
function UI:JumpToNeed(cap)
  local row = self.cp and self.cp.lastReady and self.cp.lastReady.rows[cap]
  if ns.db.settings.compact and row and (row.status == "ok" or row.status == "none") then
    ns.db.settings.compact = false   -- Summary view hides covered rows
  end
  self.expand["row:" .. cap] = true
  self.pendingJump = cap
  self:QueueRefresh()
end

function UI:RenderSummaryStrip(r, ready, dungeonKey)
  local cp = self.cp
  local level = dungeonKey and ns.Affixes and ns.Affixes:KeyLevel(dungeonKey)
  local where = (dungeonKey and DD.list[dungeonKey]) and (self:DungeonLabel(dungeonKey, 14) .. (level and (" +" .. level) or ""))
    or (HEX.muted .. "No dungeon: generic checks only|r")
  if r.filled == 0 then
    cp.sumTitle:SetText(where .. HEX.muted .. "   Add players to see readiness.|r")
  else
    local c = ready.counts
    cp.sumTitle:SetText(where .. "     " .. TEX_NO .. " " .. HEX.bad .. c.missing .. " missing|r    " .. TEX_WAIT .. " "
      .. HEX.warn .. c.thin .. " thin|r    " .. TEX_OK .. " " .. HEX.good .. c.ok .. " ok|r")
  end
  -- Chips: as many rows as the strip's width needs, so none ever runs past the edge.
  for _, b in ipairs(cp.chips) do b:Hide() end
  local barW = cp.chipBar:GetWidth()
  if type(barW) ~= "number" or barW < 100 then barW = ((self.frame and self.frame:GetWidth()) or W) - 40 end
  local CHIP_H, GAP = 18, 4
  local x, row = 0, 0
  if r.filled > 0 then
    for i, ch in ipairs(ready.chips) do
      local b = cp.chips[i]
      if not b then
        b = Button(cp.chipBar, "", 60, CHIP_H)
        b.text.cmFit = nil   -- chips size themselves to their label instead
        SetFontSize(b.text, 11)
        cp.chips[i] = b
      end
      local label = CHIP_ICON[ch.status] .. (CHIP_ICON[ch.status] ~= "" and " " or "") .. CHIP_COLOR[ch.status] .. ch.short
        .. (ch.status == "none" and " -" or "") .. "|r"
      b.text:SetText(label)
      -- Unbounded width: the text is anchored inside the button, so the bounded width
      -- would report the old (truncated) size.
      local w = b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth() or b.text:GetStringWidth()
      if type(w) ~= "number" or w <= 0 then w = #ch.short * 6 + 18 end
      w = math.min(math.floor(w + 16), math.floor(barW))
      if x > 0 and x + w > barW then row = row + 1; x = 0 end   -- wrap
      b:SetSize(w, CHIP_H)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", cp.chipBar, "TOPLEFT", x, -row * (CHIP_H + GAP))
      x = x + w + GAP
      local cap = ch.cap
      b.tooltip = (ready.rows[cap] and ready.rows[cap].label or ch.short) .. ": " .. ch.status:upper()
        .. (UD:CapExplain(cap) and ("\n" .. UD:CapExplain(cap)) or "") .. "\nClick to see it under Needs"
      b:SetScript("OnClick", function() UI:JumpToNeed(cap) end)
      b:Show()
    end
  end
  local rows = row + 1
  cp.chipBar:SetHeight(rows * (CHIP_H + GAP) - GAP)
  cp.sumPanel:SetHeight(25 + rows * (CHIP_H + GAP) - GAP + 7 + 20)
  cp.chipRows = rows
  -- Biggest risks
  if r.filled == 0 then cp.sumRisks:SetText(""); return end
  if #ready.risks == 0 then
    cp.sumRisks:SetText(TEX_OK .. " " .. HEX.good .. "No missing or thin needs.|r")
  else
    local parts = {}
    for i = 1, math.min(3, #ready.risks) do parts[i] = RiskText(ready.risks[i]) end
    local more = #ready.risks - 3
    cp.sumRisks:SetText(HEX.text .. "Biggest risks: |r" .. table.concat(parts, HEX.muted .. "  -  |r")
      .. (more > 0 and (HEX.accent .. "   + " .. more .. " more (click)|r") or ""))
  end
end

---------------------------------------------------------------------------
-- Slot badges: what each player brings (Kick, Lust, Brez, dispels...), with "!" when
-- they are the group's only source.
---------------------------------------------------------------------------
local BADGES = {
  { cap = "interrupt", short = "Kick" }, { cap = "bloodlust", short = "Lust" }, { cap = "battle_rez", short = "Brez" },
  { cap = "dispel_magic", short = "Magic" }, { cap = "dispel_curse", short = "Curse" }, { cap = "dispel_poison", short = "Poison" },
  { cap = "dispel_disease", short = "Disease" }, { cap = "purge", short = "Purge" }, { cap = "soothe", short = "Soothe" },
  { cap = "aoe_stop", short = "AoE stop" }, { cap = "external_defensive", short = "External" },
}
local SOLE_MATTERS = { interrupt = true, bloodlust = true, battle_rez = true, dispel_magic = true, dispel_curse = true,
  dispel_poison = true, dispel_disease = true, aoe_stop = true }

function UI:SlotBadges(r, idx)
  if not idx then return "", "" end
  local bits, tip = {}, {}
  for _, b in ipairs(BADGES) do
    for _, p in ipairs(r.caps[b.cap] or {}) do
      if p.index == idx then
        local sole = #r.caps[b.cap] == 1 and SOLE_MATTERS[b.cap]
        bits[#bits + 1] = (sole and (HEX.warn .. b.short .. "!|r") or (HEX.text .. b.short .. "|r"))
      end
    end
  end
  for _, c in ipairs(UD.CAPS) do
    for _, p in ipairs(r.caps[c.key] or {}) do
      if p.index == idx then
        local sole = #r.caps[c.key] == 1
        tip[#tip + 1] = (p.entry.name == c.label and p.entry.name or (c.label .. ": " .. p.entry.name))
          .. (sole and "  (the group's only source)" or "")
      end
    end
  end
  return table.concat(bits, HEX.muted .. " - |r"), (#tip > 0 and table.concat(tip, "\n") or "No tracked utility.")
end

---------------------------------------------------------------------------
-- Readiness: one row per need. Problem rows are open; covered rows fold to one line
-- and open on click ("Expand all" opens everything). Nothing is only in a tooltip.
---------------------------------------------------------------------------
local NEEDED_MAX = 3

local function MemberNames(providers)
  local t = {}
  for _, p in ipairs(providers) do t[#t + 1] = p.member.label .. (p.member.pending and "*" or "") end
  return table.concat(t, ", ")
end

function UI:RenderReadyRow(list, row, ctx, r)
  local problem = row.status == "missing" or row.status == "thin"
  local key = "row:" .. row.cap
  -- Default: problems open, covered rows folded. "Expand all" / "Collapse all" override
  -- every row (and Collapse all also folds every "+N more" list).
  local default = problem
  if UI.readyMode == "all" then default = true elseif UI.readyMode == "none" then default = false end
  local open = self:IsOpen(key, default)
  self.cp.rowY[row.cap] = list.y
  local sev = row.severity and (HEX.muted .. "  " .. row.severity:upper() .. "|r") or ""
  local unconf = row.unconfirmed and (HEX.warn .. " [unconfirmed]|r") or ""
  local folded = ""
  if not open then
    if #row.providers > 0 then folded = HEX.muted .. "  - " .. MemberNames(row.providers) .. "|r"
    elseif row.status == "ok" then folded = HEX.muted .. "  - answered another way (see details)|r"
    else folded = HEX.muted .. "  - nobody brings it|r" end
  end
  local explain = UD:CapExplain(row.cap)
  local was = self.previewWas and self.previewWas[row.cap]
  local delta = ""
  if self.previewWas and was ~= row.status then
    delta = HEX.accent .. "  " .. (was and ("was " .. was:upper()) or "new") .. "|r"
  end
  list:Add(HEX.muted .. (open and "- " or "+ ") .. "|r" .. READY_TAG[row.status] .. "  " .. HEX.text .. row.label .. "|r" .. delta .. sev .. unconf .. folded, {
    indent = 2, gap = 2,
    onClick = function() UI:SetOpen(key, not open) end,
    tooltip = (open and "Click to fold" or "Click to show details") .. (explain and ("\n\n" .. row.label .. ": " .. explain) or ""),
  })
  if not open then return end
  local ind = 18
  if explain and ns.db.settings.explain ~= false then
    list:Add(HEX.muted .. explain .. "|r", { indent = ind, size = 10, gap = 2 })
  end
  if #row.providers > 0 then
    list:Add(HEX.muted .. "Covered by: |r" .. table.concat(Analysis.Labels(row.providers, row.cap), HEX.muted .. "; |r"),
      { indent = ind, size = 11, gap = 2 })
  elseif row.status == "ok" then
    -- (MISSING and NONE rows already say nobody has it.)
    list:Add(HEX.muted .. "Covered by: nobody in the group|r", { indent = ind, size = 11, gap = 2 })
  end
  if row.cap == "interrupt" and r.interrupts and r.interrupts.count > 0 then
    local I = r.interrupts
    list:Add(HEX.muted .. string.format("%d kick%s: %d rotational, %d long-CD  -  melee %d / ranged %d  -  tank %d / healer %d / dps %d",
      I.count, I.count == 1 and "" or "s", I.short, I.long, I.byRange.melee or 0, I.byRange.ranged or 0,
      I.byRole.TANK or 0, I.byRole.HEALER or 0, I.byRole.DAMAGER or 0) .. "|r", { indent = ind, size = 10, gap = 2 })
  end
  for _, f in ipairs(row.findings) do
    -- "No X." only repeats the status when nobody brings X; otherwise it explains it.
    if not ((f.short or ""):find("^no ") and #row.providers == 0) then
      local col = (f.severity == "low" or f.severity == "info") and HEX.muted or HEX.warn
      list:Add(col .. f.text .. "|r", { indent = ind, size = 11, gap = 2 })
    end
  end
  if row.aggregate and r.dungeon and r.dungeon.aggregate then
    local ag = row.aggregate
    list:Add(ITEM_ICON[ag.status] .. " " .. HEX.muted .. r.dungeon.aggregate.text .. "|r", { indent = ind, size = 11, gap = 2 })
  end
  if #row.items > 0 then
    local nkey = "need:" .. row.cap
    local showAll = self:IsOpen(nkey, false)
    list:Add(HEX.muted .. "Needed for:|r", { indent = ind, size = 11, gap = 1 })
    local shown = showAll and #row.items or math.min(NEEDED_MAX, #row.items)
    for i = 1, shown do
      local it = row.items[i]
      local tags = ""
      if it.req.affix then tags = tags .. HEX.muted .. " (affix: " .. it.req.affix .. ")|r" end
      if it.req.category == "tank" then tags = tags .. HEX.muted .. " (tank)|r" end
      if it.req.need ~= row.cap or (it.req.alt and #it.req.alt > 0) then
        local alts = {}
        for _, a in ipairs(it.req.alt or {}) do alts[#alts + 1] = UD:CapShort(a) end
        if #alts > 0 then tags = tags .. HEX.muted .. " (or " .. table.concat(alts, " / ") .. ")|r" end
      end
      -- A MISSING row already says nobody can answer it; only other reasons add something.
      local plainMissing = it.status == "missing" and row.status == "missing" and #row.providers == 0
      local reason = (it.status ~= "covered" and it.reason and not plainMissing) and (HEX.warn .. " - " .. it.reason .. "|r") or ""
      list:Add(ITEM_ICON[it.status] .. " " .. Analysis.Decorate(it.req.source or "", it.req.need, it.req.dungeon)
        .. HEX.muted .. "  " .. (it.req.severity or ""):upper() .. "|r" .. tags .. reason
        .. (it.unconfirmed and (HEX.warn .. " [unconfirmed]|r") or ""), { indent = ind + 6, size = 11, gap = 1 })
      if it.req.note and not (row.cap == "interrupt" and it.req.note == "Interrupt every cast.") then
        list:Add(HEX.muted .. it.req.note .. "|r", { indent = ind + 22, size = 10, gap = 1 })
      end
    end
    self:MoreLine(list, nkey, #row.items - shown, ind + 6, #row.items - shown == 1 and "requirement" or "requirements")
  end
  if problem or (open and row.status == "none") then
    self:RenderCoverers(list, row.coverKeys or { row.cap }, ctx, "cov:" .. row.cap, ind)
  end
  list:Space(4)
end

function UI:RenderBuffBlock(list, r, compact)
  list:Add(HEX.text .. "Raid buffs & synergy|r", { indent = 2, size = 11, gap = 2 })
  if #r.buffs.present == 0 then
    list:Add(HEX.muted .. "None from these classes.|r", { indent = 18, size = 11 })
  end
  local STRENGTH = {
    strong = HEX.good .. "STRONG SYNERGY|r", good = HEX.accent .. "GOOD SYNERGY|r",
    minor = HEX.muted .. "MINOR|r", none = TEX_WAIT .. " " .. HEX.warn .. "LITTLE VALUE|r",
  }
  for _, b in ipairs(r.buffs.present) do
    local tag = b.universal and (HEX.muted .. "everyone|r") or STRENGTH[b.strength]
    list:Add(ns.Links:Buff(b.key) .. HEX.muted .. " (" .. tostring(b.from) .. ")|r  " .. tag, { indent = 18, size = 11, gap = 1 })
    if not compact then
      local detail
      if b.universal then
        detail = b.effect .. " for the whole group"
      elseif b.strength == "none" then
        detail = b.effect .. " - no " .. (b.who or "beneficiaries") .. " in this group"
      else
        local who = {}
        for _, n in ipairs(b.full) do who[#who + 1] = n end
        for _, n in ipairs(b.partial) do who[#who + 1] = n .. " (partly)" end
        detail = b.effect .. " - boosts " .. table.concat(who, ", ")
      end
      list:Add(HEX.muted .. detail .. "|r", { indent = 30, size = 10, gap = 3 })
    end
  end
end

function UI:RenderReadiness(list, r, ready, members, dungeonKey, compact)
  list:Clear()
  self.cp.rowY = {}
  local pev = self.previewWas and self:PreviewApplicant()
  if pev then
    list:Add(HEX.accent .. "Preview:|r " .. self:ApplicantNames(pev) .. "  " .. self:RatingTag(pev) .. HEX.muted .. "  (click to clear)|r", {
      size = 12, gap = 2, onClick = function() UI.cp.preview = nil; UI:QueueRefresh() end,
      tooltip = "Needs as they'd be with this applicant. \"was\" shows what changes." })
    if pev.headline then list:Add(HEX.muted .. pev.headline .. "|r", { indent = 4, size = 11, gap = 6 }) end
  end
  -- Context first: season / data warnings, affixes, dungeon choice.
  local seasonWarn = ns:SeasonWarningText()
  if seasonWarn then list:Add(TEX_WAIT .. " " .. HEX.warn .. seasonWarn .. "|r", { size = 11, gap = 4 }) end
  local d = r.dungeon
  if not dungeonKey then
    list:Add(HEX.muted .. "No dungeon selected: generic checks only. Pick one above to add what that dungeon asks for.|r", { size = 11, gap = 4 })
  elseif d and d.unknown then
    list:Add(TEX_WAIT .. " " .. HEX.warn .. "Unknown dungeon '" .. tostring(dungeonKey) .. "'.|r", { size = 11, gap = 4 })
  elseif d then
    if d.incomplete then
      list:Add(TEX_WAIT .. " " .. HEX.warn .. "Dungeon data is incomplete: no requirement here is verified yet.|r", { size = 11, gap = 3 })
    elseif d.mostlyUnverified then
      list:Add(HEX.warn .. "Much of this dungeon's data is unconfirmed.|r", { size = 11, gap = 3 })
    end
    if d.hidden > 0 then list:Add(HEX.muted .. d.hidden .. " requirement(s) hidden by your settings.|r", { size = 10, gap = 3 }) end
    self:RenderAffixLine(list, d, compact)
  end
  if r.filled == 0 then
    list:Add("No players yet. " .. (ns.state.mode == "live" and "Invite players or open a listing." or "Click a slot to pick a spec."),
      { color = C.muted })
    list:Finish(); return
  end
  for _, f in ipairs(ready.notes) do
    if f.check == "pending" then list:Add(HEX.muted .. f.text .. "|r", { size = 10, gap = 3 }) end
  end
  -- Every problem in one place, when the summary strip couldn't show them all.
  local risksDefault = self.readyMode == "all"   -- Expand all opens the problem list too
  if #ready.risks > 3 or (#ready.risks > 0 and self:IsOpen("risks", risksDefault)) then
    local key = "risks"
    local open = self:IsOpen(key, risksDefault)
    list:Add(HEX.accent .. (open and "- " or "+ ") .. "All gaps (" .. #ready.risks .. ")|r", {
      size = 11, gap = 2, onClick = function() UI:SetOpen(key, not open) end, tooltip = open and "Fold" or "List every missing or thin need",
    })
    if open then
      for _, row in ipairs(ready.risks) do
        local cap = row.cap
        list:Add(READY_TAG[row.status] .. "  " .. RiskText(row, true), { indent = 12, size = 11, gap = 1,
          onClick = function() UI:JumpToNeed(cap) end, tooltip = "Jump to it" })
      end
      list:Space(4)
    end
  end

  local ctx = { open = ns.ApplicantFit:OpenRoles(members or {}), settings = ns.db.settings }
  ctx.anyOpen = (ctx.open.TANK or 0) + (ctx.open.HEALER or 0) + (ctx.open.DAMAGER or 0) > 0
  local hidden = 0
  for _, g in ipairs(ready.groups) do
    local miss, thin = 0, 0
    for _, row in ipairs(g.rows) do
      if row.status == "missing" then miss = miss + 1 elseif row.status == "thin" then thin = thin + 1 end
    end
    local visible = 0
    for _, row in ipairs(g.rows) do
      if not (compact and (row.status == "ok" or row.status == "none")) then visible = visible + 1 end
    end
    if visible > 0 or (g.buffs and not compact) then
      list:Header(g.label:upper() .. ((miss + thin) > 0 and ("  " .. (miss > 0 and (TEX_NO .. miss .. " ") or "") .. (thin > 0 and (TEX_WAIT .. thin) or "")) or ""))
      if g.key == "kicks" and not compact and r.cc then
        local parts = {}
        for _, t in ipairs(UD.CC_TYPES) do if (r.cc.types[t] or 0) > 0 then parts[#parts + 1] = t .. " x" .. r.cc.types[t] end end
        list:Add(HEX.muted .. string.format("CC: %d stop%s (%d AoE)", r.cc.stops, r.cc.stops == 1 and "" or "s", r.cc.aoeStops) .. "|r",
          { indent = 2, size = 10, gap = 3,
            tooltip = string.format("Stop-capable players: %d\nAoE stops: %d\nCC types: %s", r.cc.stops, r.cc.aoeStops,
              #parts > 0 and table.concat(parts, ", ") or "none") })
      end
    end
    -- Needs nobody brings that this dungeon doesn't ask for: one line instead of a row each
    -- (click opens them as rows, with who could bring them).
    local noneRows = {}
    for _, row in ipairs(g.rows) do
      if row.status == "none" and not self:IsOpen("row:" .. row.cap, UI.readyMode == "all") then noneRows[#noneRows + 1] = row end
    end
    local merged = {}
    if #noneRows > 1 and not compact then for _, row in ipairs(noneRows) do merged[row] = true end end
    for _, row in ipairs(g.rows) do
      if compact and (row.status == "ok" or row.status == "none") then hidden = hidden + 1
      elseif not merged[row] then self:RenderReadyRow(list, row, ctx, r) end
    end
    if next(merged) then
      local names, caps = {}, {}
      for _, row in ipairs(noneRows) do names[#names + 1] = UD:CapShort(row.cap); caps[#caps + 1] = row.cap end
      list:Add(HEX.muted .. "+ " .. READY_TAG.none .. "  Nobody brings: " .. table.concat(names, ", ") .. " (not needed here)|r", {
        indent = 2, gap = 4,
        onClick = function() for _, c in ipairs(caps) do UI:SetOpen("row:" .. c, true) end end,
        tooltip = "Click to show each one, with the classes that could bring it",
      })
    end
    if g.buffs and not compact then self:RenderBuffBlock(list, r, compact) end
  end
  local other = {}
  for _, f in ipairs(ready.notes) do if f.check ~= "pending" then other[#other + 1] = f end end
  if #other > 0 and not compact then
    list:Header("Notes")
    for _, f in ipairs(other) do
      list:Add(((f.severity == "low" or f.severity == "info") and HEX.muted or HEX.warn) .. f.text .. "|r", { indent = 4, size = 11, gap = 2 })
    end
  end
  if compact and hidden > 0 then
    list:Space(6)
    list:Add(HEX.muted .. hidden .. " covered or optional need" .. (hidden == 1 and " is" or "s are") .. " not shown in Summary view.|r",
      { size = 10, onClick = function() ns.db.settings.compact = false; ns:Fire("SETTINGS_CHANGED") end, tooltip = "Switch to Full view" })
  end
  list:Finish()
  if self.pendingJump and self.cp.rowY[self.pendingJump] then
    list:ScrollTo(self.cp.rowY[self.pendingJump] - 4)
  end
  self.pendingJump = nil
end

---------------------------------------------------------------------------
-- Applicants page: applicant fit cards (left) + full breakdown (right)
---------------------------------------------------------------------------
local ROLE_WORD = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

function UI:RatingTag(ev, withScore)
  local r = ev.rating
  return "|T" .. r.icon .. ":12:12|t " .. r.hex .. r.label .. (withScore == false and "" or (" " .. ev.score)) .. "|r"
end

-- "Group after:" in color, for an applicant evaluation's ev.groupAfter (ApplicantFit:GroupAfter).
-- form: "full" (every missing and thin need), "brief" (thin as a count), "short" (narrow rows:
-- icon and count only). label: prefix ("Group after: "), false for none.
function UI:GroupAfterText(ga, form, label)
  if not ga then return "" end
  local Fit = ns.ApplicantFit
  local col = Fit.GROUP_AFTER_COLOR[ga.status] or HEX.text
  local icon = "|T" .. (Fit.GROUP_AFTER_ICON[ga.status] or Fit.GROUP_AFTER_ICON.ready) .. ":11:11|t "
  if form == "short" then return icon .. col .. ga.short .. "|r" end
  local pre = label == false and "" or (HEX.muted .. (label or "Group after: ") .. "|r")
  -- Status in its color, the open-slot count muted.
  local body = form == "brief" and ga.brief or ga.text
  local main, slots = body:match("^(.-)(, %d+ slots? open)$")
  return pre .. icon .. col .. (main or body) .. "|r" .. (slots and (HEX.muted .. slots .. "|r") or "")
end

function UI:ApplicantNames(ev)
  local parts = {}
  for _, m in ipairs(ev.members) do
    local _, _, _, hex = Util.ClassColor(m.classFile)
    parts[#parts + 1] = hex .. tostring(m.name or "?") .. "|r"
  end
  return table.concat(parts, " + ")
end

local function ApplicantSub(m, role)
  local spec = m.specID and UD:GetSpec(m.specID)
  local bits = {}
  bits[#bits + 1] = spec and (UD:SpecName(m.specID) .. " " .. UD:ClassName(spec.class))
    or (UD:ClassName(m.classFile) .. " (spec unknown)")
  bits[#bits + 1] = ROLE_WORD[role or (spec and spec.role) or m.role] or "?"
  if tonumber(m.score) and tonumber(m.score) > 0 then bits[#bits + 1] = tostring(m.score) .. " rating" end
  if m.bestHere then
    bits[#bits + 1] = m.bestHere.level > 0 and string.format("best here +%d%s", m.bestHere.level, m.bestHere.timed and "" or " (over time)")
      or "new to this dungeon"
  end
  if tonumber(m.itemLevel) and tonumber(m.itemLevel) > 0 then bits[#bits + 1] = string.format("%d ilvl", math.floor(tonumber(m.itemLevel) + 0.5)) end
  return table.concat(bits, "  -  ")
end

-- Past keys together (1.5.0, F2): "With you: 2 timed, 1 over time" for an application (each
-- player named in a premade), colored by standing; nil when you share no recorded key.
-- plain = no color codes (Blizzard's tooltip).
function UI:PastKeysText(ev, plain)
  local H = ns.History
  if not (H and ev and ev.members) then return nil end
  local parts, worst = {}, nil
  for _, m in ipairs(ev.members) do
    local st, c = H:Standing(m.full)
    local t = c and H:WithText(c)
    if t then
      parts[#parts + 1] = (#ev.members > 1 and (tostring(m.name) .. " ") or "") .. t
      if st == "failed" then worst = "failed" elseif st == "timed" and worst ~= "failed" then worst = "timed" end
    end
  end
  if #parts == 0 then return nil, nil end
  local text = "With you: " .. table.concat(parts, "; ")
  if plain then return text, worst end
  local col = worst == "failed" and HEX.warn or worst == "timed" and HEX.good or HEX.muted
  return col .. text .. "|r", worst
end

-- Sort key for "Past keys": timed keys with you minus failed ones (per the setting), summed.
function UI:PastKeysScore(ev)
  local H = ns.History
  local n, any = 0, false
  for _, m in ipairs(ev.members or {}) do
    local c = H and H:With(m.full)
    if c then any = true; n = n + c.timed - H:FailedCount(c) end
  end
  return n, any
end

---------------------------------------------------------------------------
-- Fill group (1.4.0): the band at the top of the Applicants card column, the Fill plan in the
-- right panel, the button's breathing glow and the tab dot. The planning is FillGroup.lua.
-- "Ensemble only invites when you click": every invite comes from one of our buttons.
---------------------------------------------------------------------------
local FILL_BAND_H = 56
local FILL_LEVEL_RULE = {
  relaxed = "no critical need missing",
  standard = "no critical or high need missing",
  strict = "nothing medium or worse missing; critical and high needs not thin",
}
UI.FILL_LEVEL_RULE = FILL_LEVEL_RULE

-- "Strict (auto: +12 and up)" / "Standard (auto: key level unknown)" / "Relaxed".
function UI:FillLevelText(plan)
  local FG = ns.FillGroup
  local label = FG.LEVEL_LABEL[plan.level] or plan.level
  if not plan.levelAuto then return label end
  local H = DD.HEURISTICS
  local why
  if plan.levelUnknown then why = "key level unknown"
  elseif plan.level == "strict" then why = "+" .. H.FILL_STRICT_FROM .. " and up"
  elseif plan.level == "standard" then why = "+" .. H.FILL_STANDARD_FROM .. " to +" .. (H.FILL_STRICT_FROM - 1)
  else why = "up to +" .. (H.FILL_STANDARD_FROM - 1) end
  return label .. " (auto: " .. why .. ")"
end

-- A breathing glow behind a button (alpha bounce, about every 2 s) while `on`. Animation
-- groups run on our own textures only. Without them the glow is just shown, steady.
local function Glow(btn, pad)
  pad = pad or 4
  local g = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
  g:SetPoint("TOPLEFT", -pad, pad); g:SetPoint("BOTTOMRIGHT", pad, -pad)
  Accent(g, "tex", 0.45)
  g:Hide()
  local ag = g.CreateAnimationGroup and g:CreateAnimationGroup()
  if ag then
    if ag.SetLooping then ag:SetLooping("BOUNCE") end
    local a = ag.CreateAnimation and ag:CreateAnimation("Alpha")
    if a then
      if a.SetFromAlpha then a:SetFromAlpha(0.15) end
      if a.SetToAlpha then a:SetToAlpha(0.75) end
      if a.SetDuration then a:SetDuration(1.0) end
      if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
    end
  end
  btn.glow, btn.glowAnim = g, ag
  function btn:SetGlow(on)
    on = on and true or false
    if self.glowOn == on then return end
    self.glowOn = on
    g:SetShown(on)
    if ag then
      if on then ag:Play() else ag:Stop() end
    end
  end
  return g
end
UI.Glow = Glow

-- A small boxed tag ("IN PLAN", "SKIPPED") beside an applicant's rating.
local function Chip(parent)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(52, 15)
  Skin(f, C.btn, C.accent)
  f.text = Text(f, 9, C.accent, "CENTER"); f.text:SetPoint("CENTER", 0, 0)
  function f:Set(label, color)
    self.text:SetText(label)
    self.text:SetTextColor(unpack(color))
    self:SetBackdropBorderColor(unpack(color))
    self:SetWidth(math.max(40, (self.text:GetStringWidth() or 40) + 10))
    self:Show()
  end
  f:Hide()
  return f
end

-- Names in their class colors, "A, B, C".
function UI:FillNames(list)
  local out = {}
  for _, ev in ipairs(list or {}) do out[#out + 1] = self:ApplicantNames(ev) end
  return table.concat(out, HEX.muted .. ", |r")
end

-- The click on any Fill group button (Applicants band, docked panel, pop-up): re-plans on
-- fresh data and invites only if the group is the one shown.
function UI:ClickFill(shownSig)
  local FG = ns.FillGroup
  local ok, msg = FG:Fill(shownSig)
  if msg then ns:Print(msg) end
  self:QueueRefresh(); self:QueueFinderRefresh(); self:UpdateFillPopup()
  return ok
end

-- Sync a Fill group button: label, enabled, tooltip, glow. `plan` from FillGroup:Current().
function UI:SyncFillButton(b, plan)
  local FG = ns.FillGroup
  local ready = plan and plan.status == "ready"
  b.text:SetText(FG:ButtonText(plan))
  local can, why = FG:CanInvite(plan)
  local pause = ready and FG:PauseLeft() or 0
  if can and pause > 0 then can, why = false, "The plan just changed: check it first." end
  if can then b:Enable() else b:Disable() end
  b:SetAlpha(can and 1 or 0.5)
  b.tooltip = can and (FG:InviteMode() == "one" and "Invite the next player in the plan. The game takes one invite per click here."
    or "Invite every player in the plan. Nothing is sent until you click.")
    or (ready and why) or (plan and plan.blocking) or why
  if b.SetGlow then b:SetGlow(ready) end
  -- The plan the player sees; the click handler is set once and reads it.
  b.fillSig = ready and plan.sig or nil
  if not rawget(b, "fillClickSet") then
    b:SetScript("OnClick", function(self) local s = rawget(self, "fillSig"); if s then UI:ClickFill(s) end end)
    b.fillClickSet = true
  end
  -- After a change the button waits a moment; refresh when it may be clicked again.
  if ready and pause > 0 and not self.fillPauseQueued and C_Timer and C_Timer.After then
    self.fillPauseQueued = true
    C_Timer.After(pause + 0.05, function()
      UI.fillPauseQueued = false
      UI:QueueRefresh(); UI:QueueFinderRefresh(); UI:UpdateFillPopup()
    end)
  end
end

-- The band: line 1 status, Auto-fill, the button; line 2 who and how the group ends up.
---------------------------------------------------------------------------
-- Reserve a slot and Saved players (1.5.0): one small dialog for both. Reserve: spec required
-- (the role follows it), name optional, typing suggests Saved players; "Save this player"
-- (ticked) adds a new name, or a spec picked by hand, to Saved players. Save: add a saved
-- player from Settings > Saved players. Our own frame; nothing is typed into Blizzard's UI.
---------------------------------------------------------------------------
local ROLE_TEXT = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
UI.RESERVE_SUGGEST_ROWS = 6

function UI:BuildReserveDialog()
  if self.reserveDialog then return self.reserveDialog end
  local d = CreateFrame("Frame", "EnsembleReserveDialog", UIParent, "BackdropTemplate")
  d:SetSize(392, 214)
  d:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  d:SetFrameStrata("DIALOG")
  d:EnableMouse(true); d:SetMovable(true); d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving); d:SetScript("OnDragStop", d.StopMovingOrSizing)
  d:SetClampedToScreen(true)
  Skin(d, C.bg, C.accent); Accent(d, "border")
  if UISpecialFrames then table.insert(UISpecialFrames, "EnsembleReserveDialog") end   -- Escape closes it
  d:Hide()
  d.st = { saveOn = true, matches = {} }   -- dialog state: a plain table (fields on frames are the client's)
  d.title = AccentText(d); d.title:SetPoint("TOPLEFT", 12, -10)
  local nl = Text(d, 12, C.text); nl:SetPoint("TOPLEFT", 12, -36); nl:SetText("Name")
  d.nameLabel = nl
  d.name = EditBox(d, 230, 24); d.name:SetPoint("TOPLEFT", 74, -32)
  -- The hint sits inside the empty name box; "Browse" opens the friends and guild list beside
  -- the dialog (1.5.1, option A).
  d.nameNote = Text(d.name, 11, C.muted); d.nameNote:SetPoint("LEFT", 7, 0); d.nameNote:SetPoint("RIGHT", -6, 0)
  d.nameNote:SetWordWrap(false)
  d.nameNote:SetText("optional: type or browse")
  d.browse = Button(d, "Browse", 72, 24, function() UI:ToggleFriendsPicker() end)
  d.browse:SetPoint("LEFT", d.name, "RIGHT", 6, 0)
  d.browse.tooltip = "Pick from your online friends, Battle.net friends and guild"
  local sl = Text(d, 12, C.text); sl:SetPoint("TOPLEFT", 12, -70); sl:SetText("Spec")
  d.spec = Dropdown(d, 230, 24, function(btn) UI:OpenReserveSpecMenu(btn) end)
  d.spec:SetPoint("TOPLEFT", 74, -66)
  d.role = Text(d, 11, C.muted); d.role:SetPoint("TOPLEFT", 74, -94); d.role:SetWidth(300); d.role:SetWordWrap(false)
  d.save = Check(d, "Save this player", function() return d.st.saveOn end, function(v) d.st.saveOn = v end,
    "Adds them, or this spec, to Settings > Saved players. Their default spec doesn't change.")
  d.save:SetScript("OnClick", function(self) d.st.saveOn = not d.st.saveOn; self:Sync() end)   -- no settings refresh
  d.save:SetPoint("TOPLEFT", 74, -114)
  d.err = Text(d, 11, C.bad); d.err:SetPoint("TOPLEFT", 12, -140); d.err:SetPoint("RIGHT", -12, 0)
  d.note = Text(d, 10, C.muted); d.note:SetPoint("TOPLEFT", 12, -160); d.note:SetPoint("RIGHT", -12, 0)
  -- Stack by real height (1.5.1): any change to the error or the note lays the dialog out again,
  -- so a line that wraps at a larger text size pushes the buttons down instead of running into them.
  for _, fs in ipairs({ d.err, d.note }) do
    local set = fs.SetText
    fs.SetText = function(self, t) set(self, t); UI:LayoutReserveDialog() end
  end
  d.cancel = Button(d, "Cancel", 80, 22, function() d:Hide() end); d.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
  d.ok = Button(d, "Reserve", 96, 22, function() UI:ConfirmReserveDialog() end)
  d.ok:SetPoint("RIGHT", d.cancel, "LEFT", -6, 0)
  if d.ok.SetMotionScriptsWhileDisabled then d.ok:SetMotionScriptsWhileDisabled(true) end
  -- Suggestions under the name box (our own rows; up to six).
  local sug = CreateFrame("Frame", nil, d, "BackdropTemplate")
  sug:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -2); sug:SetWidth(230)
  sug:SetFrameLevel((d:GetFrameLevel() or 1) + 20)
  Skin(sug, C.bg, C.border)
  sug:Hide()
  sug.rows = {}
  for i = 1, UI.RESERVE_SUGGEST_ROWS do
    local b = CreateFrame("Button", nil, sug)
    b:SetHeight(20); b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20); b:SetPoint("RIGHT", sug, "RIGHT", -2, 0)
    local hl = b:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints(); Accent(hl, "tex", 0.15); b:SetHighlightTexture(hl)
    b.text = Text(b, 11, C.text); b.text:SetPoint("LEFT", 4, 0); b.text:SetPoint("RIGHT", -4, 0); b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
      if self.player then
        if self.player.specs then UI:PickReservePlayer(self.player) else UI:PickReserveFriend(self.player) end
      end
    end)
    sug.rows[i] = b
  end
  d.sug = sug
  d.name:SetScript("OnTextChanged", function(box, user)
    d.nameNote:SetShown((box:GetText() or "") == "")
    if user ~= false then UI:ReserveNameChanged(true) end
  end)
  d.name:SetScript("OnEnterPressed", function(box)
    local first = d.st.matches and d.st.matches[1]
    if first and sug:IsShown() then UI:PickSuggestion(first) else box:ClearFocus() end
  end)
  d.name:SetScript("OnTabPressed", function()
    local first = d.st.matches and d.st.matches[1]
    if first and sug:IsShown() then UI:PickSuggestion(first) end
  end)
  d.name:SetScript("OnEscapePressed", function(box)
    if sug:IsShown() then sug:Hide() else box:ClearFocus(); d:Hide() end
  end)
  d.name:SetScript("OnEditFocusLost", function() C_Timer.After(0.2, function() if not d.name:HasFocus() then sug:Hide() end end) end)
  d:SetScript("OnHide", function()
    sug:Hide()
    local fp = UI.friendsPicker
    if fp and fp.st.mode ~= "planner" then fp:Hide() end
  end)
  self.reserveDialog = d
  return d
end

-- The dialog's lower part by real height (1.5.1): the error (when there is one) at y 140, the
-- note under it (or at y 160), and the dialog tall enough for the note and the buttons. Found
-- while drawing the picker mock-ups: at 125% text the note wrapped into the Reserve button.
UI.RESERVE_DIALOG_MIN_H = 214
function UI:LayoutReserveDialog()
  local d = self.reserveDialog
  if not (d and d.err and d.note) then return end
  local function height(fs)
    if (fs:GetText() or "") == "" then return 0 end
    return math.max(12, tonumber(fs:GetStringHeight()) or 12)
  end
  local errH = height(d.err)
  local noteTop = 140 + (errH > 0 and (errH + 6) or 20)
  d.note:ClearAllPoints()
  d.note:SetPoint("TOPLEFT", 12, -noteTop); d.note:SetPoint("RIGHT", -12, 0)
  d:SetHeight(math.max(self.RESERVE_DIALOG_MIN_H, noteTop + height(d.note) + 10 + 22 + 10))
end

-- mode: "reserve" (Fill group) or "save" (Settings > Saved players).
function UI:OpenReserveDialog(mode)
  local d = self:BuildReserveDialog()
  d.st.mode = mode or "reserve"
  d.st.specID, d.st.player, d.st.saveOn, d.st.matches, d.st.done = nil, nil, true, {}, nil
  d.st.classFile, d.st.friends = nil, nil
  d.name:SetText("")
  d.err:SetText("")
  d.sug:Hide()
  if d.st.mode == "save" then
    d.title:SetText("Add a saved player")
    d.ok.text:SetText("Save")
    d.nameNote:SetText("required: type or browse")
    d.note:SetText("Name-Realm (your realm when none is given). Kept on this computer for all your characters.")
  else
    d.title:SetText("Reserve a slot")
    d.ok.text:SetText("Reserve")
    d.nameNote:SetText("optional: type or browse")
    d.note:SetText("Fill group plans only the other slots. Players still apply for this role: addons can't change your listing.")
  end
  d.nameNote:Show()
  if self.friendsPicker and self.friendsPicker.st.mode ~= "planner" then self.friendsPicker:Hide() end
  d.browse:SetActive(false)
  self:SyncReserveDialog()
  d:Show()
  if d.name.SetFocus then d.name:SetFocus() end
end

function UI:SyncReserveDialog()
  local d = self.reserveDialog
  if not d then return end
  local P = ns.Players
  local p = d.st.specID and UD:GetSpec(d.st.specID)
  d.spec.text:SetText(p and (select(4, Util.ClassColor(p.class)) .. UD:SpecName(d.st.specID) .. " " .. UD:ClassName(p.class) .. "|r")
    or (HEX.muted .. (d.st.classFile and ("Pick their " .. UD:ClassName(d.st.classFile) .. " spec (required)") or "Pick a spec (required)") .. "|r"))
  d.role:SetText(p and ("Role: " .. ROLE_TEXT[p.role] .. " (follows the spec)") or "The role follows the spec.")
  local full = P:Normalize(d.name:GetText())
  local saved = full and P:Find(full)
  d.st.player = saved or nil
  -- "Save this player": a new name, or a spec not on their list.
  local showSave = d.st.mode == "reserve" and full ~= nil and (not saved or (d.st.specID and not P:HasSpec(saved, d.st.specID)))
  d.save:SetShown(showSave and true or false)
  d.save:Sync()
  if d.st.done then d.save:Hide() end   -- reserved already; the button closes
  local can = d.st.done or (d.st.specID ~= nil and (d.st.mode ~= "save" or full ~= nil))
  if can then d.ok:Enable() else d.ok:Disable() end
  d.ok:SetAlpha(can and 1 or 0.5)
  d.ok.tooltip = not can and (d.st.mode == "save" and "Type a name and pick a spec" or "Pick a spec: it decides what the slot brings") or nil
end

function UI:ReserveNameChanged(typed)
  local d = self.reserveDialog
  local P, F = ns.Players, ns.Friends
  local text = d.name:GetText() or ""
  d.st.matches = P:Matches(text, UI.RESERVE_SUGGEST_ROWS)
  -- An exact saved name needs no list.
  local full = P:Normalize(text)
  local exact = full and P:Find(full)
  if exact and #d.st.matches == 1 and d.st.matches[1] == exact then d.st.matches = {} end
  -- Then online friends, Battle.net friends and guildmates (1.5.1), after Saved players.
  if F then
    d.st.friends = d.st.friends or F:List()
    local room = UI.RESERVE_SUGGEST_ROWS - #d.st.matches
    if room > 0 and not exact then
      for _, e in ipairs(F:Matches(text, room, d.st.friends)) do
        if not (full and e.full:lower() == full:lower()) then d.st.matches[#d.st.matches + 1] = e end
      end
    end
    -- Typing a name changes who it is: the class comes from a friend typed out in full.
    if typed then
      local fe = full and not exact and F:Find(full, d.st.friends) or nil
      d.st.classFile = fe and fe.classFile or nil
    end
  end
  local n = #d.st.matches
  for i, b in ipairs(d.sug.rows) do
    local p = d.st.matches[i]
    b.player = p
    b:SetShown(p ~= nil)
    if p then
      local name, realm = p.full:match("^([^%-]+)%-?(.*)$")
      local tag, cls, what
      if p.specs then
        local def = UD:GetSpec(p.default)
        tag, cls, what = "Saved", def and def.class, def and (UD:SpecName(p.default) .. " " .. UD:ClassName(def.class)) or ""
      else
        tag, cls = ns.Friends.LABEL[p.source] or "", p.classFile
        what = UD:ClassName(p.classFile) .. (p.rating and (" - " .. p.rating) or "")
      end
      local hex = cls and select(4, Util.ClassColor(cls)) or HEX.text
      b.text:SetText(HEX.muted .. tag .. "|r  " .. hex .. tostring(name) .. "|r" .. HEX.muted .. (realm ~= "" and ("-" .. realm) or "")
        .. "   " .. tostring(what) .. "|r")
    end
  end
  d.sug:SetHeight(4 + n * 20)
  d.sug:SetShown(n > 0)
  -- A saved player typed out in full: their default spec, unless one was picked already.
  if exact and not d.st.specID then d.st.specID = exact.default end
  self:SyncReserveDialog()
end

-- Enter / Tab on the first suggestion, saved or not.
function UI:PickSuggestion(x)
  if x.specs then self:PickReservePlayer(x) else self:PickReserveFriend(x) end
end

-- A friend, Battle.net friend or guildmate picked (1.5.1): their name, and the spec menu narrows
-- to their class (the game never shares a friend's spec). A saved player keeps their own specs.
function UI:PickReserveFriend(e)
  local d = self.reserveDialog
  local P = ns.Players
  d.name:SetText(e.full)
  local saved = P:Find(e.full)
  if saved then self:PickReservePlayer(saved); return end
  d.st.player, d.st.classFile, d.st.matches = nil, e.classFile, {}
  local cur = d.st.specID and UD:GetSpec(d.st.specID)
  if not (cur and cur.class == e.classFile) then d.st.specID = nil end
  d.sug:Hide()
  if d.name.ClearFocus then d.name:ClearFocus() end
  self:SyncReserveDialog()
end

-- A suggestion picked: their name and default spec (still changeable, their specs listed first).
function UI:PickReservePlayer(p)
  local d = self.reserveDialog
  d.name:SetText(p.full)
  d.st.specID = p.default
  d.st.player = p
  d.st.matches = {}
  d.sug:Hide()
  if d.name.ClearFocus then d.name:ClearFocus() end
  self:SyncReserveDialog()
end

function UI:OpenReserveSpecMenu(anchor)
  local d = self.reserveDialog
  local P = ns.Players
  local items = {}
  local function add(specID, suffix)
    local p = UD:GetSpec(specID)
    local r, g, b = Util.ClassColor(p.class)
    items[#items + 1] = { text = UD:SpecName(specID) .. " " .. UD:ClassName(p.class) .. (suffix or ""),
      specID = specID, classFile = p.class, color = { r, g, b, 1 }, selected = d.st.specID == specID,
      onClick = function() d.st.specID = specID; d.err:SetText(""); UI:SyncReserveDialog() end }
  end
  local saved = d.st.player
  -- A friend or guildmate picked (1.5.1): only their class's specs.
  if d.st.classFile and not saved then
    items[#items + 1] = { text = UD:ClassName(d.st.classFile) .. ": the spec they'll play", header = true }
    for _, id in ipairs(ns.Friends:ClassSpecs(d.st.classFile)) do
      local role = UD:GetSpec(id).role
      local word = ({ TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" })[role]
      local full = d.st.mode == "reserve" and P:FreeFor(role) <= 0
      add(id, " - " .. word .. (full and " (no open slot)" or ""))
    end
    self:ShowMenu(anchor, items)
    return
  end
  if saved then
    items[#items + 1] = { text = (saved.full:match("^([^%-]+)") or saved.full) .. "'s specs", header = true }
    for _, id in ipairs(saved.specs) do if UD:GetSpec(id) then add(id, id == saved.default and " (default)" or nil) end end
  end
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    local full = d.st.mode == "reserve" and P:FreeFor(role) <= 0
    items[#items + 1] = { text = ({ TANK = "Tanks", HEALER = "Healers", DAMAGER = "DPS" })[role] .. (full and " (no open slot)" or ""), header = true }
    for _, id in ipairs(UD:SpecsForRole(role)) do add(id) end
  end
  self:ShowMenu(anchor, items)
end

function UI:ConfirmReserveDialog()
  local d = self.reserveDialog
  local P = ns.Players
  if d.st.mode == "save" then
    local full = P:Normalize(d.name:GetText())
    if not full then d.err:SetText("Type their name."); return end
    if not d.st.specID then d.err:SetText("Pick a spec."); return end
    local ok, why = P:Save(full, d.st.specID)
    if not ok then d.err:SetText(why == "full" and ("Saved players is full (" .. P.MAX_SAVED .. ").") or "Couldn't save."); return end
    d:Hide()
    return
  end
  if d.st.done then d:Hide(); return end
  local name = d.name:GetText()
  local ok, why = P:Reserve(d.st.specID, name, d.save:IsShown() and d.st.saveOn)
  if not ok then d.err:SetText(why or "Couldn't reserve."); return end
  if why == "notSaved" then
    -- Reserved, but Saved players is full: say so instead of closing (1.5.0 review, N3).
    d.st.done = true
    d.err:SetText("Reserved. Not saved: Saved players is full (" .. P.MAX_SAVED .. "). Remove someone in Settings > Saved players.")
    d.ok.text:SetText("Close")
    self:SyncReserveDialog()
    return
  end
  d:Hide()
end

---------------------------------------------------------------------------
-- The friends and guild picker (1.5.1, option A): a list beside the reserve dialog (or on its
-- own for a Composition planner slot) of Saved players, online friends, Battle.net friends on a
-- Retail character and guildmates, with a search box and "Show offline". A person shows once,
-- Saved players first (their row names the other source). Picking fills the dialog's name and
-- narrows its spec menu to the class; in the planner it fills the slot after the spec. Nothing is
-- saved by picking. Our own frame; nothing is typed into Blizzard's UI.
---------------------------------------------------------------------------
local ROLE_SLOT_WORD = { TANK = "tank", HEALER = "healer", DAMAGER = "DPS" }
local TEX_ONLINE = "|TInterface\\FriendsFrame\\StatusIcon-Online:12:12|t"
local TEX_OFFLINE = "|TInterface\\FriendsFrame\\StatusIcon-Offline:12:12|t"
UI.FRIENDS_PICKER_W, UI.FRIENDS_PICKER_H = 312, 344

function UI:BuildFriendsPicker()
  if self.friendsPicker then return self.friendsPicker end
  local f = CreateFrame("Frame", "EnsembleFriendsPicker", UIParent, "BackdropTemplate")
  f:SetSize(self.FRIENDS_PICKER_W, self.FRIENDS_PICKER_H)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true); f:SetClampedToScreen(true)
  Skin(f, C.bg, C.accent); Accent(f, "border")
  if UISpecialFrames then table.insert(UISpecialFrames, "EnsembleFriendsPicker") end   -- Escape closes it
  f:Hide()
  f.st = { offline = false, search = "" }   -- picker state: a plain table
  f.title = AccentText(f); f.title:SetPoint("TOPLEFT", 12, -10)
  f.search = EditBox(f, self.FRIENDS_PICKER_W - 20, 22)
  f.searchHint = Text(f.search, 11, C.muted); f.searchHint:SetPoint("LEFT", 7, 0); f.searchHint:SetText("Search names")
  f.search:SetScript("OnTextChanged", function(box)
    local t = box:GetText() or ""
    f.searchHint:SetShown(t == "")
    f.st.search = t
    UI:RefreshFriendsPicker()
  end)
  f.offline = Check(f, "Show offline", function() return f.st.offline end,
    function(v) f.st.offline = v; UI:RefreshFriendsPicker() end,
    "Also friends and guildmates who aren't online. Battle.net friends show only the character they're on, so offline ones aren't listed.")
  f.offline:SetScript("OnClick", function(self) f.st.offline = not f.st.offline; f.st.stale = true; self:Sync(); UI:RefreshFriendsPicker() end)
  f.offline:SetWidth(140)
  f.maxNote = Text(f, 10, C.muted, "RIGHT"); f.maxNote:SetText("max level only")
  f.filterNote = Text(f, 10, C.muted); f.filterNote:SetWordWrap(false)
  f.list = LineList(f, self.FRIENDS_PICKER_W - 20, 200)
  f.cancel = Button(f, "Cancel", 80, 22, function() f:Hide() end)
  f.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
  f:SetScript("OnHide", function()
    local d = UI.reserveDialog
    if d and d.browse then d.browse:SetActive(false) end
  end)
  -- The game's roster events can come in bursts (a big guild sends one per member change):
  -- mark the list stale and rebuild once, half a second after the first (1.5.1 build review).
  ns:On("FRIENDS_CHANGED", function()
    f.st.stale = true
    if not f:IsShown() or f.st.pending then return end
    f.st.pending = true
    local function go() f.st.pending = nil; UI:RefreshFriendsPicker() end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, go) else go() end
  end)
  self.friendsPicker = f
  return f
end

-- opts: { mode = "reserve" | "save" | "planner", slot, role }.
function UI:OpenFriendsPicker(opts)
  local f = self:BuildFriendsPicker()
  opts = opts or {}
  f.st.mode, f.st.slot, f.st.role, f.st.picked = opts.mode or "reserve", opts.slot, opts.role, nil
  f.search:SetText(""); f.st.search = ""; f.searchHint:Show()
  f.st.stale = true
  f.offline:Sync()
  if ns.Friends then ns.Friends:Request() end
  local planner = f.st.mode == "planner"
  local top = planner and 36 or 8
  f.title:SetShown(planner)
  f.title:SetText(planner and ("Pick for the " .. (ROLE_SLOT_WORD[f.st.role] or "") .. " slot") or "")
  f.search:ClearAllPoints(); f.search:SetPoint("TOPLEFT", 10, -top)
  f.offline:ClearAllPoints(); f.offline:SetPoint("TOPLEFT", 10, -(top + 28))
  f.maxNote:ClearAllPoints(); f.maxNote:SetPoint("TOPRIGHT", -12, -(top + 31))
  local listTop = top + 52
  f.filterNote:ClearAllPoints(); f.filterNote:SetPoint("TOPLEFT", 12, -listTop); f.filterNote:SetPoint("RIGHT", -12, 0)
  f.filterNote:SetText(planner and ("Classes that can " .. (f.st.role == "TANK" and "tank" or f.st.role == "HEALER" and "heal" or "play DPS")
    .. ". Then pick their spec.") or "")
  if planner then listTop = listTop + 16 end
  f.list:Fill(10, -listTop, -10, planner and 40 or 10)
  f.cancel:SetShown(planner)
  f:ClearAllPoints()
  local d = self.reserveDialog
  if not planner and d and d:IsShown() then
    f:SetPoint("TOPLEFT", d, "TOPRIGHT", 4, 0)
    d.browse:SetActive(true)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 160, 60)
  end
  f:Show()
  self:RefreshFriendsPicker()
end

function UI:ToggleFriendsPicker()
  local f = self.friendsPicker
  if f and f:IsShown() and f.st.mode ~= "planner" then f:Hide(); return end
  local d = self.reserveDialog
  self:OpenFriendsPicker({ mode = d and d.st.mode or "reserve" })
end

-- Classes with a spec for `role` (planner mode), or nil for any.
local function RoleClasses(role)
  if not role then return nil end
  local out = {}
  for _, id in ipairs(UD:SpecsForRole(role)) do local p = UD:GetSpec(id); if p then out[p.class] = true end end
  return out
end

function UI:RefreshFriendsPicker()
  local f = self.friendsPicker
  if not (f and f:IsShown()) then return end
  local F, P = ns.Friends, ns.Players
  -- The sources are read once per change (opening, "Show offline", a roster event), not per
  -- keystroke: the search only filters the cached list (1.5.1 build review).
  if f.st.stale or not f.st.data then
    f.st.data = F and F:List({ offline = f.st.offline }) or {}
    f.st.stale = nil
    f.st.reads = (f.st.reads or 0) + 1
  end
  local data = f.st.data
  local q = (f.st.search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local classes = RoleClasses(f.st.mode == "planner" and f.st.role or nil)
  local L = f.list
  L:Clear()
  local function row(x, cls, what, right, online, other)
    local name, realm = x.full:match("^([^%-]+)%-?(.*)$")
    local hex = online and select(4, Util.ClassColor(cls)) or HEX.muted
    local text = (online and TEX_ONLINE or TEX_OFFLINE) .. " " .. hex .. tostring(name) .. "|r" .. HEX.muted
      .. (realm ~= "" and ("-" .. realm) or "") .. "  " .. tostring(what) .. (right and ("  -  " .. right) or "") .. "|r"
    if f.st.picked and f.st.picked == x.full then text = HEX.accent .. "> |r" .. text end
    local tip = x.full .. (other and ("\n" .. other) or "") .. (x.where and ("\n" .. x.where) or "")
    L:Add(text, { size = 11, gap = 3, indent = 2, onClick = function() UI:PickFromFriendsPicker(x) end, tooltip = tip })
  end
  local function match(full, cls) return (q == "" or full:lower():find(q, 1, true)) and (not classes or classes[cls]) end
  -- Saved players first; their row names where else they are (and shows them online when a
  -- source says so).
  local savedShown = 0
  local first = true
  for _, p in ipairs(P:List()) do
    local specs = {}
    for _, id in ipairs(p.specs) do
      local sp = UD:GetSpec(id)
      if sp and (not f.st.role or f.st.mode ~= "planner" or sp.role == f.st.role) then specs[#specs + 1] = id end
    end
    local def = UD:GetSpec(p.default) or UD:GetSpec(specs[1] or 0)
    local cls = def and def.class
    if cls and #specs > 0 and match(p.full, cls) then
      local e = F and F:Find(p.full, data) or nil
      if e or f.st.offline or not F then
        if first then L:Header("Saved players"); first = false end
        local note = e and (F.LABEL[e.source] .. (e.rating and (" - " .. e.rating) or "")) or nil
        -- Not in your friends or guild: the addon can't tell whether they're online, so the row
        -- never claims it (1.5.1 build review).
        local tip = note or (F and "Not in your friends or guild: online status unknown") or nil
        row(p, cls, UD:SpecName(specs[1] == p.default and p.default or specs[1]) .. " " .. UD:ClassName(cls), note,
          (e and e.online) or (not F), tip)
        savedShown = savedShown + 1
      end
    end
  end
  local HEAD = { friend = "Friends", bnet = "Battle.net", guild = "Guild" }
  local any = savedShown > 0
  for _, src in ipairs(F and F.SOURCES or {}) do
    local st = F.reads[src] or {}
    if st.ok then
      local rows = {}
      for _, e in ipairs(data) do
        if e.source == src and not P:Find(e.full) and match(e.full, e.classFile) then rows[#rows + 1] = e end
      end
      -- Online people the list can show (max level; Battle.net: Retail in this region).
      local nOn = 0
      for _, e in ipairs(data) do if e.source == src and e.online then nOn = nOn + 1 end end
      local count = src == "bnet" and (nOn .. " in WoW") or (nOn .. " online")
      L:Header(HEAD[src] .. " (" .. count .. ")")
      for _, e in ipairs(rows) do
        row(e, e.classFile, UD:ClassName(e.classFile), e.rating and tostring(e.rating) or (not e.online and e.where) or nil, e.online)
      end
      if #rows == 0 then L:Add(HEX.muted .. (q ~= "" and "Nobody matches." or "Nobody to show.") .. "|r", { size = 10, gap = 3, indent = 6 }) end
      any = true
    end
  end
  if not any then L:Add(HEX.muted .. "No friends, Battle.net friends or guild the game lets the addon read.|r", { size = 11 }) end
  L:Finish()
end

-- A row picked: the reserve dialog's name (and the class's specs), or the planner slot after
-- the spec.
function UI:PickFromFriendsPicker(x)
  local f = self.friendsPicker
  if f.st.mode == "planner" then
    local slot, role = f.st.slot, f.st.role
    local specs = {}
    if x.specs then
      if x.default and UD:GetSpec(x.default) and UD:GetSpec(x.default).role == role then specs[1] = x.default end
      for _, id in ipairs(x.specs) do
        local sp = UD:GetSpec(id)
        if sp and sp.role == role and id ~= specs[1] then specs[#specs + 1] = id end
      end
    else
      specs = ns.Friends:ClassSpecs(x.classFile, role)
    end
    if #specs == 0 then return end
    local function put(id) ns.Players:SetPlannerSlot(slot, x.full, id); f:Hide() end
    if #specs == 1 then put(specs[1]); return end
    local items = { { text = (x.full:match("^([^%-]+)") or x.full) .. ": the spec they'll play", header = true } }
    for _, id in ipairs(specs) do
      local sp = UD:GetSpec(id)
      local r, g, b = Util.ClassColor(sp.class)
      items[#items + 1] = { text = UD:SpecName(id) .. " " .. UD:ClassName(sp.class), specID = id, classFile = sp.class,
        color = { r, g, b, 1 }, onClick = function() put(id) end, tooltip = function() return UI:SpecPreviewText(slot, id) end }
    end
    self:ShowMenu(f, items)
    return
  end
  if x.specs then self:PickReservePlayer(x) else self:PickReserveFriend(x) end
  f.st.picked = x.full
  self:RefreshFriendsPicker()
end

-- The band's and Settings' button: no reservations -> the dialog; otherwise a menu to reserve
-- another or release one ("back to Fill group").
function UI:OpenReserveMenu(anchor)
  local P = ns.Players
  local list = P:Reservations()
  if #list == 0 then self:OpenReserveDialog("reserve"); return end
  local items = { { text = "Reserved slots", header = true } }
  for i, r in ipairs(list) do
    items[#items + 1] = { text = "Release: " .. P:ReservationLabel(r),
      tooltip = "Back to Fill group: it plans this slot again",
      onClick = function() P:Release(i) end }
  end
  items[#items + 1] = { text = "Reserve another slot...", onClick = function() UI:OpenReserveDialog("reserve") end }
  self:ShowMenu(anchor, items)
end

-- "Reserved: Holy Priest (Ann)", or nil.
function UI:ReservedText()
  local P = ns.Players
  local parts = {}
  for _, r in ipairs(P:Reservations()) do parts[#parts + 1] = P:ReservationLabel(r) end
  if #parts == 0 then return nil end
  return "Reserved: " .. table.concat(parts, ", ")
end

-- "Full group ready", or "Group ready (1 slot reserved for Ann)" with reserved slots (1.5.0).
function UI:ReadyTitle()
  local n, names = ns.Players:ReservedFor()
  if n == 0 then return "Full group ready" end
  return "Group ready (" .. n .. " slot" .. (n > 1 and "s" or "") .. " reserved"
    .. (#names > 0 and (" for " .. table.concat(names, ", ")) or "") .. ")"
end

function UI:RenderFillBand(band, plan)
  local FG = ns.FillGroup
  local skipped = plan and #plan.skipped or 0
  local tail = {}
  if plan and plan.level then tail[#tail + 1] = FG.LEVEL_LABEL[plan.level] end
  if skipped > 0 then tail[#tail + 1] = skipped .. " skipped" end
  local tailText = #tail > 0 and (HEX.muted .. "  -  " .. table.concat(tail, "  -  ") .. "|r") or ""
  local title, line, icon, border
  if not plan or plan.status == "empty" then
    icon, title, line, border = TEX_WAIT, HEX.muted .. "Fill group|r", HEX.muted .. "Waiting for applicants.|r", C.border
  elseif plan.status == "nodungeon" then
    icon, title, line, border = TEX_WAIT, HEX.muted .. "Fill group|r", HEX.muted .. "Pick the key above to plan a full group.|r", C.border
  elseif plan.status == "full" and plan.reservedAll then
    icon, title, line, border = TEX_OK, HEX.good .. "Every open slot is reserved|r",
      HEX.muted .. "Nothing to fill: the rest are taken, invited or held for a friend.|r", C.border
  elseif plan.status == "full" then
    icon, title, line, border = TEX_OK, HEX.good .. "Your group is full|r", HEX.muted .. "Every slot is taken or invited.|r", C.border
  elseif plan.status == "ready" then
    local ga = plan.groupAfter
    icon, border = TEX_OK, C.good
    title = HEX.good .. self:ReadyTitle() .. "|r"
    line = self:FillNames(plan.picks) .. HEX.muted .. "  -  |r" .. (ga and self:GroupAfterText(ga, "brief", false) or "") .. tailText
  else
    icon, border = TEX_WAIT, C.warn
    title = HEX.warn .. "No full group yet|r"
    -- 1.5.1: with a closest group the line stays short ("Closest group: short of 1 - passes
    -- Standard"); the level and the skipped count are in the Fill plan.
    line = HEX.text .. tostring(plan.blocking or "") .. "|r" .. (plan.status == "none" and "" or tailText)
  end
  band.title:SetText(icon .. " " .. title)
  band.line:SetText(line)
  local reserved = self:ReservedText()
  band.tip = UI.Plain(line) .. (reserved and ("\n" .. reserved) or "")
  local nRes = #ns.Players:Reservations()
  band.reserve.text:SetText(nRes > 0 and ("Reserved (" .. nRes .. ")") or "Reserve a slot")
  band.reserve.tooltip = nRes > 0 and (reserved .. "\nClick to release one or reserve another.")
    or "Hold an open slot for a friend who's joining: Fill group plans only the rest."
  band:SetBackdropBorderColor(unpack(border))
  band.auto:Sync()
  band.auto:SetShown(ns.Tracker.hosting and true or false)
  self:SyncFillButton(band.fill, plan)
end

-- The right panel's Fill plan (the band was clicked).
function UI:RenderFillPlan(list, plan, ctx)
  local FG = ns.FillGroup
  list:Clear()
  if not plan then
    list:Add(HEX.muted .. "Host a Group Finder listing and Fill group finds a full group among your applicants.|r", { size = 11 })
    list:Finish(); return
  end
  local dname = plan.dungeonKey and DD.list[plan.dungeonKey] and DD.list[plan.dungeonKey].name or "No dungeon"
  local key = dname .. (plan.keyLevel and (" +" .. plan.keyLevel) or "")
  local function settingsLink(text)
    list:Add(HEX.accent .. "> " .. (text or "Open Settings > Fill group") .. "|r", { size = 10, gap = 4,
      onClick = function() UI:OpenSettings("fill") end, tooltip = "Strictness, musts, filters and Auto-fill" })
  end
  if plan.status == "nodungeon" or plan.status == "empty" or plan.status == "full" then
    list:Add(plan.status == "full" and (plan.reservedAll and "Every open slot is reserved: nothing to fill." or "Your group is full.")
      or "Pick the key above to plan a full group.", { size = 13, gap = 4 })
    settingsLink(); list:Finish(); return
  end
  local ready = plan.status == "ready"
  local n = 0
  for _, ev in ipairs(plan.picks) do n = n + #ev.members end
  if ready then
    list:Add(key .. "  -  " .. n .. " invite" .. (n == 1 and "" or "s") .. ", "
      .. (FG:InviteMode() == "one" and "one per click" or "sent together with one click"), { size = 13, gap = 2 })
  else
    list:Add("No full group passes " .. FG.LEVEL_LABEL[plan.level] .. " yet", { size = 13, gap = 2 })
    list:Add(HEX.muted .. (FG.armed and "Auto-fill is on: you'll hear a sound and see the plan as soon as one does."
      or "Turn on Auto-fill to be told as soon as one does.") .. "|r", { size = 10, gap = 2 })
  end
  list:Add(HEX.muted .. "Strictness: " .. self:FillLevelText(plan) .. " - " .. FILL_LEVEL_RULE[plan.level] .. ".|r", { size = 10, gap = 2 })
  settingsLink("Settings > Fill group")

  local function memberRow(role, ev, note)
    local m1 = ev.members[1] or {}
    local p1 = m1.specID and UD:GetSpec(m1.specID)
    local spec = p1 and (UD:SpecName(m1.specID) .. " " .. UD:ClassName(p1.class)) or (UD:ClassName(m1.classFile) .. " (spec unknown)")
    local bits = { spec }
    if tonumber(m1.score) then bits[#bits + 1] = tostring(m1.score) end
    if m1.bestHere and m1.bestHere.level > 0 then
      bits[#bits + 1] = (m1.bestHere.timed and "timed +" or "+") .. m1.bestHere.level .. " here" .. (m1.bestHere.timed and "" or " (over time)")
    end
    if tonumber(m1.itemLevel) and tonumber(m1.itemLevel) > 0 then bits[#bits + 1] = math.floor(tonumber(m1.itemLevel) + 0.5) .. " ilvl" end
    list:Add(HEX.muted .. (ROLE_WORD[role] or "?"):upper() .. "|r   " .. self:ApplicantNames(ev) .. "   " .. self:RatingTag(ev)
      .. (note and (HEX.muted .. "  " .. note .. "|r") or ""), { size = 12, gap = 0, indent = 4 })
    list:Add(HEX.muted .. table.concat(bits, "  -  ") .. "|r", { size = 10, gap = 3, indent = 46 })
    local pastText = self:PastKeysText(ev)
    if pastText then list:Add(pastText, { size = 10, gap = 3, indent = 46 }) end
  end
  local function partyRows()
    for _, m in ipairs(ctx and ctx.base and ctx.base.members or {}) do
      local _, _, _, hex = Util.ClassColor(m.classFile)
      list:Add(HEX.muted .. (ROLE_WORD[m.role] or "?"):upper() .. "|r   " .. hex .. tostring(m.label) .. "|r"
        .. HEX.muted .. (m.isPlayer and "  (you)" or m.reserved and "" or "  (in your group)") .. "|r", { size = 12, gap = 3, indent = 4 })
    end
    for _, ev in ipairs(plan.pending) do memberRow(ev.roles[1], ev, "(invited)") end
  end

  if ready then
    list:Space(4)
    partyRows()
    for _, ev in ipairs(plan.picks) do memberRow(ev.roles[1], ev) end
    list:Header("Group after")
    local j = plan.judge
    local mustOK = {}
    for _, row in ipairs(j.mustRows) do
      if row.status ~= "missing" then mustOK[#mustOK + 1] = row.label .. (row.status == "thin" and (HEX.warn .. " (thin)|r") or "") end
    end
    if #j.mustRows > 0 then
      list:Add(TEX_OK .. " Musts: " .. table.concat(mustOK, ", "), { size = 11, gap = 2, indent = 4 })
    end
    list:Add(TEX_OK .. " Passes " .. FG.LEVEL_LABEL[plan.level] .. ": " .. FILL_LEVEL_RULE[plan.level], { size = 11, gap = 2, indent = 4 })
    if #j.thin > 0 then
      list:Add(TEX_WAIT .. " " .. #j.thin .. " thin: " .. table.concat(j.thin, ", "), { size = 11, gap = 2, indent = 4 })
    end
    if plan.groupAfter then list:Add(self:GroupAfterText(plan.groupAfter, "full"), { size = 11, gap = 2, indent = 4 }) end
    list:Header("Why this group")
    local why = "Highest total fit (" .. plan.total .. ") of the full groups that pass."
    local ru = plan.runnerUp
    if ru and ru.out and ru.inn and ru.tied then
      -- A tie (1.5.1): what decided it, in the tiebreak chain's order.
      local win, lose = ru.out, ru.inn
      local wn, ln = tostring(win.members[1].name), tostring(lose.members[1].name)
      local st = ru.tieStep and ns.ApplicantFit.TIE_STEPS[ru.tieStep]
      local reason
      if st then
        local a, b = ns.ApplicantFit.TieKey(win)[st.key] or 0, ns.ApplicantFit.TieKey(lose)[st.key] or 0
        reason = wn .. "'s " .. st.label .. " is higher, " .. st.fmt(a) .. " vs " .. st.fmt(b) .. "."
      else
        -- A full tie on the chain: the wait decides, and only when it differs (else the stable
        -- order picked one; say there's no difference rather than claim a reason).
        local ww = tonumber(win.members[1] and win.members[1].firstSeen)
        local lw = tonumber(lose.members[1] and lose.members[1].firstSeen)
        reason = (ww and lw and ww ~= lw) and (wn .. " has waited longer.") or "no difference between them."
      end
      why = why .. " Tied with " .. ln .. " in " .. wn .. "'s place (fit " .. tostring(lose.score) .. "): " .. reason
    elseif ru and ru.out and ru.inn then
      why = why .. " Next best: " .. tostring(ru.inn.members[1].name) .. " instead of "
        .. tostring(ru.out.members[1].name) .. " (total " .. ru.diff .. " lower)."
    elseif plan.runnerUp then
      why = why .. " Next best: total " .. plan.runnerUp.diff .. " lower."
    end
    list:Add(why, { size = 11, gap = 2, indent = 4 })
  else
    -- Panel A (1.5.1, the author's pick, October 26): each fact once. Every shortfall is one row
    -- with its rule folded in (the level that rejects it, or that it's a must) and, when nobody
    -- applying brings it, the classes that could; the must hint once; the repeat-class group in
    -- one line; "Best so far" instead of a closest group when there aren't enough applicants.
    local function partyNames()
      local names = {}
      for _, m in ipairs(ctx and ctx.base and ctx.base.members or {}) do
        if m.isPlayer then table.insert(names, 1, "you")
        elseif not m.reserved then names[#names + 1] = tostring(m.label) end
      end
      for _, ev in ipairs(plan.pending) do names[#names + 1] = tostring(ev.members[1] and ev.members[1].name) .. " (invited)" end
      if #names == 0 then return nil end
      return HEX.muted .. "With " .. FG.JoinOr(names):gsub(" or ", " and ") .. ".|r"
    end
    local usedGap = {}
    local function gapFor(keys)
      for i, g in ipairs(plan.poolGaps) do
        for _, a in ipairs(g.keys or {}) do
          for _, b in ipairs(keys or {}) do if a == b and not usedGap[i] then usedGap[i] = true; return g end end
        end
      end
    end
    local levelName = FG.LEVEL_LABEL[plan.level]
    if plan.closest then
      local head = "CLOSEST GROUP"
      if plan.closest.passesAt then
        head = head .. HEX.muted .. "  -  |r" .. HEX.good .. "would pass at " .. FG.LEVEL_LABEL[plan.closest.passesAt] .. "|r"
      end
      list:Header(head)
      for _, ev in ipairs(plan.closest.picks) do memberRow(ev.roles[1], ev) end
      local pn = partyNames()
      if pn then list:Add(pn, { size = 10, gap = 4, indent = 4 }) end
      for _, f in ipairs(plan.closest.judge.fails) do
        local what = (f.status == "missing" and "No " or "Thin ") .. f.label
        local rule
        if f.must then
          rule = (f.status == "missing") and "a must" or ("a must; " .. levelName .. " wants it not thin")
        else
          rule = levelName .. ((f.status == "missing") and " needs it" or " wants it not thin")
        end
        local g = gapFor(f.keys)
        local gapText = g and ("; nobody applying brings it" .. (#g.coverers > 0 and (HEX.muted .. " (" .. FG.JoinOr(g.coverers) .. ")|r") or "")) or ""
        list:Add(TEX_NO .. " " .. what .. ": " .. rule .. gapText, { size = 11, gap = 2, indent = 4 })
      end
      if plan.closest.mustMissing then
        list:Add(HEX.muted .. "A must blocks every level: untick it under Settings > Fill group > Always require.|r", { size = 10, gap = 2, indent = 4 })
      end
    elseif plan.bestSoFar then
      list:Header("Best so far")
      for _, ev in ipairs(plan.bestSoFar.picks) do memberRow(ev.roles[1], ev) end
      for _, x in ipairs(plan.bestSoFar.missing) do
        list:Add(TEX_NO .. " " .. (x.n > 1 and (x.n .. " ") or "") .. (ROLE_WORD[x.role] or "?")
          .. ": nobody applying yet" .. (plan.classBlocked and " of another class" or ""), { size = 11, gap = 2, indent = 4 })
      end
      list:Add(HEX.muted .. "Shown so you can invite by hand; Fill group never invites part of a group.|r", { size = 10, gap = 2, indent = 4 })
    else
      list:Add(TEX_NO .. " " .. tostring(plan.blocking or "No group passes yet."), { size = 11, gap = 2, indent = 4 })
    end
    -- A gap no closest-group row named (none in the short case).
    for i, g in ipairs(plan.poolGaps) do
      if not usedGap[i] then
        list:Add(TEX_NO .. " Nobody applying brings " .. g.label .. (#g.coverers > 0 and (HEX.muted .. ": " .. FG.JoinOr(g.coverers) .. "|r") or ""),
          { size = 11, gap = 2, indent = 4 })
      end
    end
    if plan.repeatGroup then
      list:Add(TEX_OK .. " Passes " .. levelName .. " with a repeat class: " .. self:FillNames(plan.repeatGroup.picks)
        .. HEX.muted .. " (" .. plan.repeatGroup.dups .. ")|r", { size = 11, gap = 1, indent = 4 })
      list:Add(HEX.muted .. "\"One player per class in each role\" is on, so Fill group won't plan it. You can invite them yourself.|r",
        { size = 10, gap = 2, indent = 16 })
    end
  end
  if #plan.skipped > 0 then
    list:Header("Skipped (" .. #plan.skipped .. ")")
    for _, x in ipairs(plan.skipped) do
      list:Add(self:ApplicantNames(x.ev) .. ": " .. x.reason, { size = 11, gap = 2, indent = 4 })
    end
  end
  list:Space(6)
  list:Add(HEX.muted .. "Ensemble only invites when you click. If someone declines, the slot reopens and the plan picks a replacement by the same rules.|r",
    { size = 10, gap = 2 })
  list:Finish()
end

-- The green dot on the Applicants tab: a full group passes and you're on another tab.
function UI:SyncFillTabDot()
  local b = self.tabButtons and self.tabButtons.applicants
  if not (b and b.dot) then return end
  local plan = ns.Tracker.enabled and ns.Tracker.hosting and ns.FillGroup:Current() or nil
  b.dot:SetShown(plan and plan.status == "ready" and self.currentTab ~= "applicants" and true or false)
end

local CARD_W, CARD_H = 424, 80

local function ApplicantCard(parent)
  local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
  c:SetSize(CARD_W, CARD_H)
  ns.Links:Enable(c)
  Skin(c, C.btn, C.border)
  c.bar = c:CreateTexture(nil, "ARTWORK")
  c.bar:SetPoint("TOPLEFT", 1, -1); c.bar:SetPoint("BOTTOMLEFT", 1, 1); c.bar:SetWidth(5)
  c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(30, 30); c.icon:SetPoint("TOPLEFT", 14, -8)
  c.badge = Text(c, 11); c.badge:SetPoint("TOPRIGHT", -8, -8); c.badge:SetJustifyH("RIGHT"); c.badge:SetWordWrap(false)
  c.name = Text(c, 13); c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, 0); c.name:SetPoint("RIGHT", c.badge, "LEFT", -8, 0)
  c.name:SetWordWrap(false)
  c.wait = Text(c, 10, C.muted); c.wait:SetPoint("TOPRIGHT", -8, -26); c.wait:SetJustifyH("RIGHT"); c.wait:SetWordWrap(false)
  c.sub = Text(c, 11, C.muted); c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3); c.sub:SetPoint("RIGHT", c.wait, "LEFT", -6, 0)
  c.sub:SetWordWrap(false)
  c.cmp = Button(c, "Compare", 66, 18)
  c.cmp:SetPoint("BOTTOMRIGHT", -6, 5)
  SetFontSize(c.cmp.text, 10)
  c.cmp.tooltip = "Pin to compare side by side (pin two)"
  c.inv = Button(c, "Invite", 56, 18)
  c.inv:SetPoint("RIGHT", c.cmp, "LEFT", -4, 0)
  if c.inv.SetMotionScriptsWhileDisabled then c.inv:SetMotionScriptsWhileDisabled(true) end  -- tooltip says why it's off
  SetFontSize(c.inv.text, 10)
  -- Headline under the name block (full width); "Group after:" on the bottom line beside the buttons.
  c.headline = Text(c, 11, C.text); c.headline:SetPoint("TOPLEFT", c.sub, "BOTTOMLEFT", 0, -5); c.headline:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  c.headline:SetWordWrap(false)
  c.after = Text(c, 11, C.text); c.after:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 8, -35); c.after:SetPoint("RIGHT", c.inv, "LEFT", -6, 0)
  c.after:SetWordWrap(false)
  -- Fill group: IN PLAN / SKIPPED, left of the rating.
  c.chip = Chip(c); c.chip:SetPoint("RIGHT", c.badge, "LEFT", -6, 0)
  -- The tag's own hover line (CLOSEST, 1.5.1): one line pointing to the Fill plan, not the list again.
  c.chip:EnableMouse(true)
  c.chip:SetScript("OnEnter", function(self)
    if self.tip and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.tip, 1, 1, 1, 1, true); GameTooltip:Show()
    end
  end)
  c.chip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  c:SetScript("OnEnter", function(self) if not self.selected then self:SetBackdropBorderColor(unpack(C.accent)) end end)
  c:SetScript("OnLeave", function(self)
    if not self.selected then self:SetBackdropBorderColor(unpack(self.inPlan and C.accent or C.border)) end
  end)
  return c
end

---------------------------------------------------------------------------
-- Applicants on the Composition tab while you host: the best fits under your slots. Click
-- one to preview them in an open slot (Needs shows what changes); Invite from the row.
-- "List view" switches back to the usual left column; the Applicants tab keeps compare,
-- filters and the full breakdown.
---------------------------------------------------------------------------
local APP_ROW_H = 36   -- at 100% text; rows grow with the text size (UI:AppRowH)
local APP_TAG_W = 72   -- room for the rating word / "Group after" status column, at least

-- Row pitch: the name (12) and headline (10) lines stacked with their gaps, never below 36.
function UI:AppRowH()
  return math.max(APP_ROW_H, FontPx(12) + FontPx(10) + 14)
end

-- Under the slots, wherever LayoutSlots puts them (they grow with the text size), and the rows
-- at the pitch for the text size. Called by LayoutSlots.
function UI:LayoutAppPanel(top)
  local f = self.cp and self.cp.appPanel
  if not f then return end
  f.top = top or f.top
  f.baseH = (f.colH or 450) + f.top - 12
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", 8, f.top - 4); f:SetPoint("BOTTOMRIGHT", -8, 8)
  f.rowH = self:AppRowH()
  for i, row in ipairs(f.rows) do
    row:SetHeight(f.rowH - 4)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -20 - (i - 1) * f.rowH); row:SetPoint("RIGHT", 0, 0)
  end
end

-- The name and headline end `gap` px left of Invite: room for the rating word and the
-- "Group after" status, which can be wider than APP_TAG_W at larger text sizes.
function UI:SetAppRowTextEdge(row, gap)
  if row.textGap == gap then return end
  row.textGap = gap
  row.name:SetPoint("RIGHT", row.inv, "LEFT", -gap, 0)
  row.head:SetPoint("RIGHT", row.inv, "LEFT", -gap, 0)
end

-- Widest of a row's status lines, measured (pcall: the method may differ by client).
local function StatusWidth(fs)
  for _, m in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
    if fs[m] then
      local ok, w = pcall(fs[m], fs)
      if ok and type(w) == "number" then return w end
    end
  end
  return 0
end

function UI:BuildAppPanel(left, top, colH)
  local cp = self.cp
  local f = CreateFrame("Frame", nil, left)
  f.colH, f.top = colH or 450, top
  f:Hide()
  cp.appPanel = f
  f.hide = FlatButton(f, "List view", 64, 18, function() ns.db.settings.compApplicants = "list"; UI:QueueRefresh() end)
  f.hide:SetPoint("TOPRIGHT", 0, 2)
  f.hide.tooltip = "Back to the usual view (suggestions for your open slots). Switch back from there."
  f.open = FlatButton(f, "Open tab", 64, 18, function() UI:SetTab("applicants") end)
  f.open:SetPoint("RIGHT", f.hide, "LEFT", -4, 0)
  f.open.tooltip = "Compare, filters and the full breakdown"
  -- The title stops short of the two links and fits its room (larger text sizes ran it under them).
  f.title = AccentText(f); f.title:SetPoint("TOPLEFT", 2, 0); f.title:SetPoint("RIGHT", f.open, "LEFT", -6, 0)
  f.title:SetWordWrap(false)
  MakeFit(f.title, function() return f.title:GetWidth() or 0 end)
  f.title:SetText("Applicants: best fit first")
  f.rows = {}
  for i = 1, 6 do
    local row = CreateFrame("Button", nil, f, "BackdropTemplate")
    Skin(row, C.btn, C.border)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT", 1, -1); row.bar:SetPoint("BOTTOMLEFT", 1, 1); row.bar:SetWidth(3)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(22, 22); row.icon:SetPoint("LEFT", 8, 0)
    row.inv = Button(row, "Invite", 50, 20)
    row.inv:SetPoint("RIGHT", -5, 0)
    SetFontSize(row.inv.text, 10)
    if row.inv.SetMotionScriptsWhileDisabled then row.inv:SetMotionScriptsWhileDisabled(true) end
    -- Two short lines at the right: the rating word, and the group's status after them.
    row.tag = Text(row, 10); row.tag:SetPoint("BOTTOMRIGHT", row.inv, "LEFT", -6, 1); row.tag:SetJustifyH("RIGHT")
    row.after = Text(row, 10); row.after:SetPoint("TOPRIGHT", row.inv, "LEFT", -6, -1); row.after:SetJustifyH("RIGHT")
    row.after:SetWordWrap(false)
    -- Name on the row's top edge, headline on its bottom edge (not the 22px icon's), so the
    -- two lines stay apart as the row grows; their right edge follows the status column.
    row.name = Text(row, 12); row.name:SetPoint("TOPLEFT", 36, -4)
    row.name:SetWordWrap(false)
    row.head = Text(row, 10, C.text); row.head:SetPoint("BOTTOMLEFT", 36, 4)
    row.head:SetWordWrap(false)
    UI:SetAppRowTextEdge(row, APP_TAG_W)
    row:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(unpack(C.accent))
      if self.tooltip and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true); GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function(self)
      self:SetBackdropBorderColor(unpack(self.selected and C.accent or C.border))
      if self.tooltip and GameTooltip then GameTooltip:Hide() end
    end)
    f.rows[i] = row
  end
  f.more = Text(f, 11, C.muted)
  f.more:SetJustifyH("LEFT"); f.more:SetWordWrap(true)
  self:LayoutAppPanel(top)
end

-- True when the Composition tab shows the applicant panel.
function UI:AppPanelOn(live)
  return live and ns.Tracker and ns.Tracker.hosting and ns.db.settings.compApplicants ~= "list" and true or false
end

-- The applicant being previewed (still applying), with the live context, or nil.
function UI:PreviewApplicant()
  local cp = self.cp
  if not cp.preview then return nil end
  local ctx, evals = ns.ApplicantFit:ForLiveGroup()
  for _, ev in ipairs(evals) do if ev.applicantID == cp.preview then return ev, ctx end end
  cp.preview = nil
  return nil
end

function UI:RenderAppPanel()
  local f = self.cp.appPanel
  local ctx, evals = ns.ApplicantFit:ForLiveGroup()
  local h = f:GetHeight()
  h = math.max(h or 0, f.baseH - (H - UI.MIN_H))   -- at least what the smallest window leaves
  -- 20 = title row; 30 = the hint under the rows, which may wrap to two lines.
  local rowH = f.rowH or APP_ROW_H
  local fits = math.max(1, math.floor((h - 20 - 30) / rowH))
  local n = math.min(#evals, fits, #f.rows)
  for i, row in ipairs(f.rows) do
    local ev = i <= n and evals[i]
    row:SetShown(ev and true or false)
    if ev then
      row.bar:SetColorTexture(unpack(ev.rating.color))
      local m1 = ev.members[1] or {}
      local p1 = m1.specID and UD:GetSpec(m1.specID)
      SetSpecIcon(row.icon, p1 and m1.specID or nil, m1.classFile)
      row.icon:SetDesaturated(p1 == nil)
      local spec = p1 and UI.ShortLabel(UD:SpecName(m1.specID) .. " " .. UD:ClassName(p1.class)) or UD:ClassName(m1.classFile)
      row.name:SetText(self:ApplicantNames(ev) .. HEX.muted .. "  " .. (#ev.members > 1 and (#ev.members .. " players") or spec) .. "|r")
      row.head:SetText(ev.headline or "")
      row.tag:SetText(ev.rating.hex .. ev.rating.word:upper() .. "|r")
      row.after:SetText(ev.roleConflict and "" or self:GroupAfterText(ev.groupAfter, "short"))
      self:SetAppRowTextEdge(row, math.max(APP_TAG_W, math.ceil(math.max(StatusWidth(row.tag), StatusWidth(row.after))) + 12))
      local id = ev.applicantID
      row.selected = self.cp.preview == id
      row:SetBackdropBorderColor(unpack(row.selected and C.accent or C.border))
      row.tooltip = not ev.roleConflict and self:GroupAfterText(ev.groupAfter, "full") or nil
      row:SetScript("OnClick", function()
        UI.cp.preview = (UI.cp.preview ~= id) and id or nil
        UI:QueueRefresh()
      end)
      self:SyncInviteButton(row.inv, ev, ctx)
    end
  end
  f.more:ClearAllPoints()
  f.more:SetPoint("TOPLEFT", 4, -20 - n * rowH - 2)
  f.more:SetPoint("RIGHT", f, "RIGHT", -4, 0)   -- wrap inside the column, never into Needs
  if #evals == 0 then
    f.more:SetText("No applicants yet. Ratings appear as soon as someone applies.")
  elseif #evals > n then
    f.more:SetText("+ " .. (#evals - n) .. " more on the Applicants tab. Click a row to preview.")
  else
    f.more:SetText("Click a row to preview them in your group.")
  end
end

function UI:BuildApplicantsPage()
  local page = PageFrame(self.frame)
  self.pages.applicants = page
  local ap = { cards = {}, selected = nil }
  self.ap = ap

  -- Top bar: dungeon (the key being run) + keystone level + legend.
  local bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT", 12, -10); bar:SetPoint("TOPRIGHT", -12, -10); bar:SetHeight(30)
  local lbl = Text(bar, 12, C.muted); lbl:SetPoint("LEFT", 0, 0); lbl:SetText("Key:")
  ap.dungeonBtn = Dropdown(bar, 240, 28, function(btn) UI:OpenDungeonMenu(btn) end)
  ap.dungeonBtn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
  ap.minus = Button(bar, "-", 24, 24, function() UI:StepKeyLevel(-1) end)
  ap.minus:SetPoint("LEFT", ap.dungeonBtn, "RIGHT", 10, 0)
  ap.level = Text(bar, 13, C.text, "CENTER"); ap.level:SetPoint("LEFT", ap.minus, "RIGHT", 4, 0); ap.level:SetWidth(44)
  ap.plus = Button(bar, "+", 24, 24, function() UI:StepKeyLevel(1) end)
  ap.plus:SetPoint("LEFT", ap.level, "RIGHT", 4, 0)
  ap.auto = Button(bar, "Auto", 48, 24, function() ns.state.keyLevelOverride = nil; UI:QueueRefresh(); UI:QueueFinderRefresh() end)
  ap.auto:SetPoint("LEFT", ap.plus, "RIGHT", 6, 0)
  ap.auto.tooltip = "Use your own keystone's level when it matches this dungeon"
  ap.levelNote = Text(bar, 11, C.muted); ap.levelNote:SetPoint("LEFT", ap.auto, "RIGHT", 8, 0); ap.levelNote:SetWidth(120)
  ap.levelNote:SetWordWrap(false)
  -- Legend (color + icon + word).
  local legend = Text(bar, 11, C.text); legend:SetPoint("RIGHT", 0, 0); legend:SetJustifyH("RIGHT")
  local parts = {}
  for _, k in ipairs(ns.ApplicantFit.RATING_ORDER) do
    local r = ns.ApplicantFit.RATINGS[k]
    parts[#parts + 1] = "|T" .. r.icon .. ":11:11|t" .. r.hex .. r.word .. "|r"
  end
  legend:SetText(table.concat(parts, "   "))

  -- Context line: party and open slots; sort + filter controls on the right.
  local view = function() return ns.db.settings.applicantView end
  ap.hidePoor = Check(page, "Hide Poor", function() return view().hidePoor end,
    function(v) view().hidePoor = v; UI:QueueRefresh() end)
  ap.hidePoor:SetSize(96, 20)
  ap.hidePoor:SetPoint("TOPRIGHT", -12, -42)
  ap.sortBtns = {}
  local prevBtn
  for i = 4, 1, -1 do
    local def = ({ { "fit", "Fit" }, { "rating", "Rating" }, { "ilvl", "ilvl" }, { "past", "Past keys" } })[i]
    local b = Button(page, def[2], def[1] == "past" and 68 or 52, 20, function() view().sort = def[1]; UI:QueueRefresh() end)
    SetFontSize(b.text, 11)
    b.tooltip = ({ fit = "Best fit first: what they add to your group, plus their experience in this dungeon at this key level.\nTies: best timed here, then this dungeon's score, M+ rating, item level, then who waited longest.",
      rating = "Highest M+ rating first", ilvl = "Highest item level first",
      past = "Players you've timed keys with first (from your own History; counts keys recorded with full names, 1.5.0 on)" })[def[1]]
    if prevBtn then b:SetPoint("RIGHT", prevBtn, "LEFT", -4, 0) else b:SetPoint("RIGHT", ap.hidePoor, "LEFT", -12, 0) end
    ap.sortBtns[def[1]] = b
    prevBtn = b
  end
  local sortLbl = Text(page, 11, C.muted); sortLbl:SetPoint("RIGHT", prevBtn, "LEFT", -6, 0); sortLbl:SetText("Sort:")
  ap.needs = Button(page, "What we need", 100, 20, function() UI:CopyNeedsText() end)
  SetFontSize(ap.needs.text, 11)
  ap.needs:SetPoint("RIGHT", sortLbl, "LEFT", -14, 0)
  ap.needs.tooltip = "A short line for your listing's description: open roles and what your group still needs, so the right players apply"
  ap.context = Text(page, 12, C.muted)
  ap.context:SetPoint("TOPLEFT", 14, -48); ap.context:SetPoint("RIGHT", ap.needs, "LEFT", -10, 0); ap.context:SetWordWrap(false)

  local top, colH = -72, H - 41 - 72 - 12
  local left = Panel(page)
  left:SetPoint("TOPLEFT", 12, top); left:SetPoint("BOTTOMLEFT", 12, 12); left:SetWidth(CARD_W + 16)
  -- Fill group band: at the top of the card column while you host (the cards move down).
  local band = CreateFrame("Button", nil, left, "BackdropTemplate")
  band:SetPoint("TOPLEFT", 8, -8); band:SetPoint("RIGHT", left, "RIGHT", -8, 0); band:SetHeight(FILL_BAND_H)
  Skin(band, C.btn, C.border)
  band.fill = Button(band, "Fill group", 136, 24)   -- room for "Invite next (2 of 4)"
  band.fill:SetPoint("TOPRIGHT", -6, -6)
  if band.fill.SetMotionScriptsWhileDisabled then band.fill:SetMotionScriptsWhileDisabled(true) end
  Glow(band.fill)
  band.auto = Check(band, "Auto-fill", function() return ns.FillGroup.armed end,
    function(v) ns.FillGroup:SetArmed(v) end,
    "Tell me (sound, and the plan by the Group Finder or a pop-up) when a full group passes. For this listing only; Settings > Fill group can turn it on for every listing. Ensemble only invites when you click.")
  band.auto:SetSize(84, 20)
  band.auto:SetPoint("RIGHT", band.fill, "LEFT", -8, 0)
  band.title = Text(band, 13); band.title:SetPoint("TOPLEFT", 10, -10); band.title:SetPoint("RIGHT", band.auto, "LEFT", -6, 0)
  band.title:SetWordWrap(false)
  -- Reserve a slot (1.5.0): bottom right, under the Fill group button.
  band.reserve = FlatButton(band, "Reserve a slot", 100, 16, function(btn) UI:OpenReserveMenu(btn) end)
  band.reserve:SetPoint("BOTTOMRIGHT", -6, 6)
  band.line = Text(band, 11, C.muted); band.line:SetPoint("BOTTOMLEFT", 10, 9); band.line:SetPoint("RIGHT", band.reserve, "LEFT", -6, 0)
  band.line:SetWordWrap(false)
  band:SetScript("OnClick", function() ap.showPlan = true; UI:QueueRefresh() end)
  band:SetScript("OnEnter", function(self)
    self:SetBackdropColor(unpack(C.btnHot))
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Fill group", 1, 1, 1)
      if self.tip and self.tip ~= "" then GameTooltip:AddLine(self.tip, 0.8, 0.8, 0.8, true) end
      GameTooltip:AddLine("Click for the full plan.", 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end
  end)
  band:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(C.btn)); if GameTooltip then GameTooltip:Hide() end end)
  band:Hide()
  ap.band = band
  local sf = CreateFrame("ScrollFrame", nil, left)
  sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -4, 8)
  ap.sf = sf
  local content = CreateFrame("Frame", nil, sf); content:SetSize(CARD_W, 1)
  sf:SetScrollChild(content)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, content:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40)))
  end)
  ap.content = content
  ap.empty = Text(content, 12, C.muted); ap.empty:SetPoint("TOPLEFT", 6, -6); ap.empty:SetWidth(CARD_W - 12)

  local right = Panel(page)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); right:SetPoint("BOTTOMRIGHT", -12, 12)
  local dt = AccentText(right); dt:SetPoint("TOPLEFT", 10, -8); dt:SetText("Applicant fit")
  ap.detailTitle = dt
  ap.detail = LineList(right, W - 24 - (CARD_W + 16) - 10 - 12, colH - 34):Fill(6, -28, -6, 6)
end

function UI:StepKeyLevel(delta)
  local dungeonKey = ns:GetEffectiveDungeon(true)
  local cur = ns.state.keyLevelOverride or ns.ApplicantFit:GetKeyLevel(dungeonKey) or 10
  ns.state.keyLevelOverride = math.max(2, math.min(30, cur + delta))
  self:QueueRefresh(); self:QueueFinderRefresh()
end

function UI:RefreshApplicants()
  local ap = self.ap
  local T = ns.Tracker
  local ctx, evals = ns.ApplicantFit:ForLiveGroup()
  local dungeonKey = ctx.dungeonKey

  local _, dsrc = ns:GetEffectiveDungeon(true)
  ap.dungeonBtn.text:SetText(dungeonKey and (self:DungeonLabel(dungeonKey) .. (dsrc == "auto" and (HEX.muted .. "  auto|r") or ""))
    or (HEX.muted .. "No dungeon selected|r"))
  ap.level:SetText(ctx.keyLevel and ("+" .. ctx.keyLevel) or "+?")
  ap.levelNote:SetText(ctx.keyLevel and (ctx.keyLevelSource or "") or "level unknown")

  -- Context: who is in, what's open, ideal pick.
  local open = ctx.open
  local openParts = {}
  for _, r in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    if open[r] > 0 then openParts[#openParts + 1] = (open[r] > 1 and (open[r] .. " ") or "") .. ROLE_WORD[r] end
  end
  -- Fill group: the plan (shared with the docked panel and the pop-up), and the pool check.
  local plan = T.hosting and ns.FillGroup:Current() or nil
  ap.plan = plan
  local pool = ""
  if plan and (plan.status == "ready" or plan.status == "none" or plan.status == "short") then
    if #plan.poolGaps > 0 then
      local labels = {}
      for _, g in ipairs(plan.poolGaps) do labels[#labels + 1] = g.label end
      pool = "   -   " .. HEX.bad .. "Nobody applying brings: " .. table.concat(labels, ", ") .. "|r"
    else
      pool = "   -   " .. HEX.good .. "Pool covers every need|r"
    end
  end
  ap.context:SetText(string.format("Your party: %d/5   -   Open: %s", #ctx.base.members,
    #openParts > 0 and table.concat(openParts, ", ") or "none (group is full)") .. pool)
  local showBand = T.hosting and true or false
  ap.band:SetShown(showBand)
  ap.sf:ClearAllPoints()
  ap.sf:SetPoint("TOPLEFT", 8, showBand and -(8 + FILL_BAND_H + 6) or -8); ap.sf:SetPoint("BOTTOMRIGHT", -4, 8)
  if showBand then self:RenderFillBand(ap.band, plan) end
  local inPlan, skippedWhy = {}, {}
  local closest, closestTip = {}, nil
  if plan then
    for _, ev in ipairs(plan.picks) do inPlan[ev.applicantID] = true end
    for _, x in ipairs(plan.skipped) do skippedWhy[x.ev.applicantID] = x.reason end
    -- What Fill group leans toward while nothing passes (1.5.1).
    if plan.status ~= "ready" then closest = plan.closestIDs or {} end
    if plan.closest then
      local n = #plan.closest.judge.fails
      closestTip = "In the closest group: short of " .. n .. ". See the Fill plan."
    elseif plan.bestSoFar then
      closestTip = "Best so far for an open slot: not enough applicants for a full group yet. See the Fill plan."
    end
  end
  if not showBand then ap.showPlan = false end

  for _, c in ipairs(ap.cards) do c:Hide() end
  local msg
  if not T.hosting then
    msg = "You're not hosting a Group Finder listing.\n\nList a group and applicants appear here, each rated against your current party and the key above."
  elseif #evals == 0 then
    msg = "No applicants yet. Ratings appear as soon as someone applies."
  end
  ap.empty:SetText(msg or "")
  ap.empty:SetShown(msg ~= nil)

  -- Sort and filter a copy (the evaluation list is shared with the Group Finder panel).
  local view = ns.db.settings.applicantView
  local allEvals = evals
  local byID = {}
  for _, ev in ipairs(allEvals) do byID[ev.applicantID] = ev end
  local shownList, hidden = {}, 0
  for _, ev in ipairs(allEvals) do
    -- A player in the Fill plan always shows, so the band never names a hidden card; so does a
    -- friend you reserved a slot for (their card says to invite them yourself; R6).
    if view.hidePoor and ev.rating and ev.rating.key == "poor" and not inPlan[ev.applicantID] and not ev.reservedFriend then
      hidden = hidden + 1
    else shownList[#shownList + 1] = ev end
  end
  local Avg = ns.ApplicantFit.Avg
  if view.sort == "past" then
    -- Past keys: most timed keys with you (less failed ones) first; no shared keys last; the
    -- tiebreak chain breaks ties.
    local key, any = {}, {}
    for _, ev in ipairs(shownList) do key[ev], any[ev] = self:PastKeysScore(ev) end
    table.sort(shownList, function(x, y)
      if any[x] ~= any[y] then return any[x] end
      if key[x] ~= key[y] then return key[x] > key[y] end
      return ns.ApplicantFit.TieBefore(x, y)   -- the tiebreak chain (1.5.1)
    end)
  elseif view.sort == "rating" or view.sort == "ilvl" then
    local field = view.sort == "rating" and "score" or "itemLevel"
    table.sort(shownList, function(x, y)
      local a, b = Avg(x.members, field) or 0, Avg(y.members, field) or 0
      if a ~= b then return a > b end
      return ns.ApplicantFit.TieBefore(x, y)   -- the tiebreak chain (1.5.1)
    end)
  end
  evals = shownList
  for k, b in pairs(ap.sortBtns) do b:SetActive(k == (view.sort or "fit")) end
  ap.hidePoor:Sync()
  if hidden > 0 and #evals == 0 and T.hosting then
    ap.empty:SetText(hidden .. " applicant" .. (hidden > 1 and "s" or "") .. " hidden by \"Hide Poor\".")
    ap.empty:Show()
  end

  -- Compare pins: keep only applicants still in the list.
  ap.compare = ap.compare or {}
  for i = #ap.compare, 1, -1 do if not byID[ap.compare[i]] then table.remove(ap.compare, i) end end

  local selectedEv
  for i, ev in ipairs(evals) do
    local c = ap.cards[i]
    if not c then c = ApplicantCard(ap.content); ap.cards[i] = c end
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD_H + 6))
    c.bar:SetColorTexture(unpack(ev.rating.color))
    local m1 = ev.members[1] or {}
    local p1 = m1.specID and UD:GetSpec(m1.specID)
    SetSpecIcon(c.icon, p1 and m1.specID or nil, m1.classFile)
    c.icon:SetDesaturated(p1 == nil)
    c.badge:SetText(self:RatingTag(ev))
    c.name:SetText(self:ApplicantNames(ev))
    c.subBase = #ev.members > 1 and (#ev.members .. " players applying together") or ApplicantSub(m1, ev.roles[1])
    -- Past keys together, right after who they are (the line is cut at the right edge).
    local pastText = self:PastKeysText(ev)
    if pastText then
      if #ev.members > 1 then c.subBase = c.subBase .. "  -  " .. pastText .. HEX.muted
      else
        local spec, rest = c.subBase:match("^(.-  %-  .-)(  %-  .*)$")
        c.subBase = spec and (spec .. "  -  " .. pastText .. HEX.muted .. rest) or (c.subBase .. "  -  " .. pastText .. HEX.muted)
      end
    end
    c.firstSeen = m1.firstSeen
    c.sub:SetText(c.subBase)
    c.wait:SetText(UI:WaitText(c.firstSeen, true))
    c.headline:SetText(ev.headline)
    c.after:SetText(ev.roleConflict and "" or self:GroupAfterText(ev.groupAfter, "brief"))
    local id = ev.applicantID
    -- Fill group: in the plan (tag and accent edge), or skipped by a filter (dimmed, tag, reason).
    c.inPlan = inPlan[id] or false
    if skippedWhy[id] then
      c.chip:Set("SKIPPED", C.muted)
      c.headline:SetText(HEX.muted .. "Skipped: " .. skippedWhy[id] .. "|r")
      c:SetAlpha(0.55)
    else
      c:SetAlpha(1)
      if c.inPlan then c.chip:Set("IN PLAN", C.accent)
      elseif closest[id] then c.chip:Set("CLOSEST", C.warn)
      else c.chip:Hide() end
    end
    c.chip.tip = (not skippedWhy[id] and not c.inPlan and closest[id]) and closestTip or nil
    -- The name stops before the tag (or the rating when there's none).
    c.name:ClearAllPoints()
    c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, 0)
    c.name:SetPoint("RIGHT", c.chip:IsShown() and c.chip or c.badge, "LEFT", -8, 0)
    c:SetScript("OnClick", function() ap.selected = id; ap.showPlan = false; UI:QueueRefresh() end)
    if ap.selected == id then selectedEv = ev end
    local pinned = false
    for _, x in ipairs(ap.compare) do if x == id then pinned = true end end
    c.cmp.text:SetText(pinned and "Pinned" or "Compare")
    c.cmp:SetActive(pinned)
    c.cmp:SetScript("OnClick", function() UI:TogglePin(id) end)
    UI:SyncInviteButton(c.inv, ev, ctx)
    c:Show()
  end
  if not selectedEv then selectedEv = evals[1]; ap.selected = selectedEv and selectedEv.applicantID end
  for i, c in ipairs(ap.cards) do
    local isSel = c:IsShown() and evals[i] and evals[i] == selectedEv and not ap.showPlan
    c.selected = isSel
    c:SetBackdropBorderColor(unpack((isSel or c.inPlan) and C.accent or C.border))
  end
  ap.content:SetHeight(math.max(1, #evals * (CARD_H + 6)))
  self:EnsureWaitTicker()
  ap.detailTitle:SetText(ap.showPlan and "Fill plan" or "Applicant fit")
  if ap.showPlan then
    self:RenderFillPlan(ap.detail, plan, ctx)
  elseif #ap.compare == 2 then
    self:RenderApplicantCompare(ap.detail, ctx, byID[ap.compare[1]], byID[ap.compare[2]])
  else
    self:RenderApplicantDetail(ap.detail, ctx, selectedEv, #ap.compare == 1 and byID[ap.compare[1]] or nil)
  end
end

-- Invite straight from the window. Ensemble only invites when you click: this button is
-- that click. (Blizzard doesn't document a hardware-event rule for C_LFGList.InviteApplicant;
-- it works from our own button, confirmed October 16, 2026.) A premade group applying
-- together is one application, invited as one.
-- Returns can (bool), reason (string when it can't).
function UI:CanInvite(ev, ctx)
  if not (C_LFGList and C_LFGList.InviteApplicant) then return false, "Inviting from here isn't available in this client." end
  local status = ev and ev.members and ev.members[1] and ev.members[1].status
  if status == "invited" then return false, "Invited: waiting for them to accept." end
  if IsInGroup and IsInGroup() and UnitIsGroupLeader then
    local lead = UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
    if not lead then return false, "Only the group leader (or an assistant) can invite." end
  end
  local open = 0
  for _, n in pairs((ctx and ctx.open) or {}) do open = open + n end
  -- A reserved slot (1.5.0) is still open in the game: your own click can fill it (your friend
  -- may apply through the listing).
  for _, n in pairs((ctx and ctx.reservedRoles) or {}) do open = open + n end
  if ctx and ctx.open and #(ev.members or {}) > open then
    return false, open == 0 and "Your group is full." or ("Only " .. open .. " open spot" .. (open > 1 and "s" or "") .. " for " .. #ev.members .. " players.")
  end
  return true
end

function UI:InviteApplicant(ev, ctx)
  local can, why = self:CanInvite(ev, ctx)
  if not can then ns:Print(why); return false end
  local ok, err = pcall(C_LFGList.InviteApplicant, ev.applicantID)
  if not ok then
    ns:Print("The game didn't accept the invite" .. (err and (": " .. tostring(err)) or "") .. ". Use the Group Finder's own Invite button.")
    return false
  end
  for _, m in ipairs(ev.members or {}) do m.status = "invited" end
  self:QueueRefresh(); self:QueueFinderRefresh()
  return true
end

function UI:SyncInviteButton(b, ev, ctx)
  local can, why = self:CanInvite(ev, ctx)
  local invited = ev.members and ev.members[1] and ev.members[1].status == "invited"
  b.text:SetText(invited and "Invited" or "Invite")
  b:SetActive(invited and true or false)
  if can then b:Enable() else b:Disable() end
  b:SetAlpha(can and 1 or (invited and 0.9 or 0.5))
  b.tooltip = can and ("Invite " .. (#ev.members > 1 and ("these " .. #ev.members .. " players") or "this player") .. " to your group") or why
  b:SetScript("OnClick", function() UI:InviteApplicant(ev, ctx) end)
end

-- Pin up to two applicants; pinning a third replaces the oldest pin.
function UI:TogglePin(id)
  local ap = self.ap
  ap.compare = ap.compare or {}
  for i, x in ipairs(ap.compare) do
    if x == id then table.remove(ap.compare, i); self:QueueRefresh(); return end
  end
  table.insert(ap.compare, id)
  if #ap.compare > 2 then table.remove(ap.compare, 1) end
  self:QueueRefresh()
end

function UI:RenderApplicantCompare(list, ctx, a, b)
  list:Clear()
  local cmp = ns.ApplicantFit:Compare(ctx, a, b)
  local nameA, nameB = self:ApplicantNames(a), self:ApplicantNames(b)
  list:Add("Comparing " .. HEX.accent .. "A|r " .. nameA .. "  vs  " .. HEX.accent .. "B|r " .. nameB, { size = 14, gap = 4 })
  for i, pair in ipairs({ { "A", a }, { "B", b } }) do
    local tag, ev = pair[1], pair[2]
    list:Add(HEX.text .. tag .. "|r " .. self:RatingTag(ev) .. HEX.muted .. "  -  " .. ApplicantSub(ev.members[1], ev.roles[1]) .. "|r",
      { size = 11, gap = 1 })
    if not ev.roleConflict then
      list:Add(self:GroupAfterText(ev.groupAfter, "full"), { indent = 14, size = 11, gap = i == 2 and 4 or 1 })
    end
  end
  -- Verdict first.
  local who = cmp.winner == "a" and ("A " .. nameA) or cmp.winner == "b" and ("B " .. nameB) or nil
  list:Add((who and (TEX_OK .. " " .. who .. ": ") or (TEX_WAIT .. " ")) .. cmp.verdict, { size = 13, gap = 4 })

  list:Header("Side by side")
  -- Labels in their own column (space padding can't line up in a proportional font): the
  -- values start at a fixed x that grows with the text size.
  local labelW = math.floor(FontPx(12) * 6.5 + 0.5)
  for _, st in ipairs(cmp.stats) do
    local va = st.better == "a" and (HEX.good .. st.a .. "|r") or st.a
    local vb = st.better == "b" and (HEX.good .. st.b .. "|r") or st.b
    local y0 = list.y
    list:Add(HEX.muted .. st.label .. "|r", { indent = 4, size = 12, gap = 2 })
    local y1 = list.y
    list.y = y0
    list:Add("A " .. va .. "   B " .. vb, { indent = 4 + labelW, size = 12, gap = 2 })
    list.y = math.max(list.y, y1)
  end

  list:Header("New utility for your group")
  local function lines(label, items, color)
    if #items == 0 then return end
    list:Add(color .. label .. "|r " .. table.concat(items, ", "), { indent = 4, size = 11, gap = 2 })
  end
  lines("Only A:", cmp.onlyA, HEX.text)
  lines("Only B:", cmp.onlyB, HEX.text)
  lines("Both:", cmp.both, HEX.muted)
  if #cmp.onlyA + #cmp.onlyB + #cmp.both == 0 then
    list:Add(HEX.muted .. "Neither adds a missing utility.|r", { indent = 4, size = 11 })
  end

  if a.dungeonName then
    list:Header(a.dungeonName .. (ctx.keyLevel and (" +" .. ctx.keyLevel) or "") .. " needs they close")
    local function fixes(label, items)
      if #items == 0 then return end
      list:Add(HEX.text .. label .. "|r", { indent = 4, size = 11, gap = 1 })
      for _, f in ipairs(items) do
        list:Add(TEX_OK .. " " .. f.text .. HEX.muted .. "  " .. string.upper(f.severity or "") .. "|r", { indent = 14, size = 11, gap = 1 })
      end
    end
    fixes("Only A", cmp.fixA); fixes("Only B", cmp.fixB); fixes("Both", cmp.fixBoth)
    if #cmp.fixA + #cmp.fixB + #cmp.fixBoth == 0 then
      list:Add(HEX.muted .. "Neither closes an open requirement.|r", { indent = 4, size = 11 })
    end
  end

  list:Header("Overlaps")
  local any = false
  for _, pair in ipairs({ { "A", a }, { "B", b } }) do
    local tag, ev = pair[1], pair[2]
    for _, o in ipairs(ev.overlaps) do list:Add(TEX_WAIT .. " " .. tag .. ": " .. o, { indent = 4, size = 11, gap = 1 }); any = true end
  end
  if not any then list:Add(HEX.muted .. "None.|r", { indent = 4, size = 11 }) end
  list:Space(6)
  list:Add(HEX.accent .. "> Clear comparison|r", { size = 12,
    onClick = function() UI.ap.compare = {}; UI:QueueRefresh() end, tooltip = "Unpin both" })
  list:Finish()
end

-- "Why 78?": the fit score taken apart, folded by default.
local function Pts(x) return string.format("%s%.1f", x >= 0 and "+" or "-", math.abs(x)) end
function UI:RenderScoreBreakdown(list, ctx, ev)
  local key = "score:" .. tostring(ev.applicantID)
  local open = self:IsOpen(key, false)
  list:Add(HEX.accent .. (open and "- " or "+ ") .. "Why " .. ev.score .. "?|r", {
    size = 11, gap = 2, onClick = function() UI:SetOpen(key, not open) end,
    tooltip = open and "Hide the breakdown" or "Show how the fit score was worked out",
  })
  if not open then return end
  local ind = 14
  if #(ev.breakdown or {}) == 0 then
    list:Add(HEX.muted .. "Closes no gap and adds none.|r", { indent = ind, size = 11, gap = 1 })
  end
  for _, b in ipairs(ev.breakdown or {}) do
    local col = b.points >= 0 and HEX.good or HEX.bad
    list:Add(col .. Pts(b.points) .. "|r  " .. b.text, { indent = ind, size = 11, gap = 1 })
  end
  list:Add(HEX.muted .. string.format("Total: %s points of gaps closed.", Pts(ev.gain or 0)) .. "|r", { indent = ind, size = 10, gap = 1 })
  -- The score's steps in order (pick position, experience, critical-gap rule, cap), each
  -- ending on the number the next one starts from.
  for _, st in ipairs(ns.ApplicantFit:ScoreSteps(ctx, ev)) do
    list:Add(HEX.muted .. st.text .. "|r", { indent = ind, size = 10, gap = 1 })
  end
  list:Space(3)
end

function UI:RenderApplicantDetail(list, ctx, ev, pinned)
  list:Clear()
  if pinned then
    list:Add(HEX.muted .. "Pinned " .. self:ApplicantNames(pinned) .. HEX.muted .. " - pin one more to compare side by side.|r",
      { size = 11, gap = 4 })
  end
  if not ev then
    list:Add("Select an applicant to see how they fit.", { color = C.muted })
    list:Finish(); return
  end
  list:Add(self:ApplicantNames(ev), { size = 15, gap = 2 })
  for i, m in ipairs(ev.members) do
    list:Add(HEX.muted .. ApplicantSub(m, ev.roles[i]) .. "|r", { size = 11, gap = 2 })
  end
  local pastText = self:PastKeysText(ev)
  if pastText then
    list:Add(pastText, { size = 11, gap = 2,
      tooltip = "From your own History: keys recorded with this player (1.5.0 on, with full names). History can't tell who left a key or why it was abandoned." })
  end
  list:Space(2)
  list:Add(self:RatingTag(ev, false) .. HEX.muted .. string.format("   %d / 100|r", ev.score), { size = 14, gap = 2 })
  if ev.experience then
    list:Add(HEX.muted .. string.format("Utility %d, experience %d (%s; counts %d%% at +%d).|r", ev.fitScore, ev.experience.points,
      ev.experience.text, math.floor(ev.experience.weight * 100 + 0.5), ctx.keyLevel), { size = 11, gap = 2 })
  end
  if ev.roleConflict then
    list:Add(HEX.muted .. "Rated poor because their role has no open slot.|r", { size = 11 })
  elseif ev.flat then
    list:Add(HEX.muted .. "No real difference between picks for this slot: decide on experience.|r", { size = 11 })
  else
    list:Add(HEX.muted .. string.format("How good a pick for this slot: 0 is the weakest %s, 100 the best.|r",
      ROLE_WORD[ev.roles[1]] or "pick"), { size = 11 })
  end
  self:RenderScoreBreakdown(list, ctx, ev)
  list:Space(2)
  list:Add(ev.headline, { size = 13 })

  list:Header("Utility they bring")
  if #ev.brings == 0 then list:Add(HEX.muted .. "No tracked utility.|r", { indent = 4, size = 11 }) end
  for _, line in ipairs(ev.brings) do list:Add(line, { indent = 4, size = 11, gap = 2 }) end

  list:Header("How they complement your group")
  for _, c in ipairs(ev.complements) do
    local tex = c.weight >= 3 and TEX_OK or c.weight > 0 and TEX_OK or TEX_WAIT
    list:Add(tex .. " " .. c.text, { indent = 4, size = 11, gap = 2 })
  end
  if #ev.overlaps > 0 then
    for _, o in ipairs(ev.overlaps) do list:Add(TEX_WAIT .. " " .. HEX.warn .. "Overlap:|r " .. o, { indent = 4, size = 11, gap = 2 }) end
  end

  if ev.dungeonName then
    list:Header(ev.dungeonName .. (ctx.keyLevel and (" +" .. ctx.keyLevel) or ""))
    if #ev.dungeonFixes == 0 then
      list:Add(TEX_WAIT .. " Doesn't close any of this dungeon's open requirements.", { indent = 4, size = 11 })
    end
    for _, f in ipairs(ev.dungeonFixes) do
      list:Add(TEX_OK .. " " .. f.text .. HEX.muted .. "  " .. string.upper(f.severity or "") .. "|r", { indent = 4, size = 11, gap = 2 })
    end
    if (ev.dungeonHelps or 0) > 0 then
      list:Add(HEX.muted .. "Provides for " .. ev.dungeonHelps .. " of this dungeon's requirements in total.|r", { indent = 4, size = 11 })
    end
    -- Gaps that remain after inviting them, each with the classes that could still cover it.
    local skey = "still:" .. tostring(ev.applicantID)
    local showAll = self:IsOpen(skey, false)
    local shownN = showAll and #ev.dungeonStill or math.min(3, #ev.dungeonStill)
    local openAfter = ns.ApplicantFit:OpenRoles(ev.after and ev.after.members or {})
    for i = 1, shownN do
      local it = ev.dungeonStillItems and ev.dungeonStillItems[i]
      list:Add(((it and it.status == "thin") and TEX_WAIT or TEX_NO) .. " " .. HEX.muted .. ev.dungeonStill[i] .. "|r", { indent = 4, size = 11, gap = 1 })
      if it then
        local keys = { it.req.need }
        for _, a in ipairs(it.req.alt or {}) do keys[#keys + 1] = a end
        self:ClassListLine(list, keys, openAfter, "stillcov:" .. tostring(ev.applicantID) .. ":" .. tostring(it.req.id), 22)
      end
    end
    self:MoreLine(list, skey, #ev.dungeonStill - shownN, 4, "remaining gaps")
  else
    list:Header("Key fit")
    list:Add(HEX.muted .. "Pick the dungeon above (or list your group for it) to rate fit for the specific key.|r", { indent = 4, size = 11 })
  end

  if #ev.notes > 0 or ev.idealPick then
    list:Header("Notes")
    for _, n in ipairs(ev.notes) do list:Add(HEX.muted .. n .. "|r", { indent = 4, size = 11, gap = 2 }) end
    if ev.idealPick then
      list:Add(HEX.muted .. "Ideal pick for this slot: |r" .. ev.idealPick, { indent = 4, size = 11 })
    end
  end
  list:Header("Group after inviting")
  if not ev.roleConflict and ev.groupAfter then list:Add(self:GroupAfterText(ev.groupAfter, "full"), { size = 11, gap = 2 }) end
  list:Add(HEX.muted .. (ev.after.summary or "") .. "|r", { size = 11 })
  list:Finish()
end

---------------------------------------------------------------------------
-- Applicant panel docked beside the Blizzard Group Finder.
-- Our own plain frame anchored to PVEFrame; Blizzard's frames are only hooked
-- (HookScript OnShow/OnHide), never modified, so no taint reaches the protected
-- Invite/Decline buttons.
-- PVEFrame (the Group Finder window global) confirmed present in 12.1.0 (build 69933) by /ens verify.
---------------------------------------------------------------------------
local FP_ROWS = 16        -- rows built; 8 shown until "+N more" is clicked
local FP_SHOW = 8

function UI:AttachFinderPanel()
  self:HookFinderTooltips()
  if self.finderHooked then return true end
  local host = PVEFrame
  if not host or not host.HookScript then return false end
  self.finderHooked = true
  host:HookScript("OnShow", function() UI:UpdateFinderPanel() end)
  host:HookScript("OnHide", function() UI:UpdateFinderPanel() end)
  self:UpdateFinderPanel()
  return true
end

-- The Group Finder may be load-on-demand; keep trying on ADDON_LOADED until it exists.
local finderWatcher = CreateFrame("Frame")
finderWatcher:RegisterEvent("ADDON_LOADED")
finderWatcher:SetScript("OnEvent", function(self)
  if ns.db and UI:AttachFinderPanel() and UI.tipHooked then self:UnregisterEvent("ADDON_LOADED") end
end)

-- Auto-open: when you create a Group Finder listing for a Season dungeon, open the window
-- on the Applicants tab. Always-on and cheap: one event, one HasActiveEntryInfo call.
-- Fires only on the not-listed -> listed transition, so editing a listing or /reload
-- while listed never pops the window.
local listingWatcher = CreateFrame("Frame")
listingWatcher:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
listingWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
listingWatcher:SetScript("OnEvent", function(_, event) UI:OnListingUpdate(event) end)

local function HasListing()
  if not (C_LFGList and C_LFGList.HasActiveEntryInfo) then return false end
  local ok, has = pcall(C_LFGList.HasActiveEntryInfo)
  return ok and has and true or false
end

function UI:OnListingUpdate(event)
  local has = HasListing()
  local was = self.wasListed
  self.wasListed = has
  -- Auto-fill is armed per listing (Settings > Fill group decides whether a new one arms it).
  if ns.db and ns.FillGroup and has ~= (was == true) then ns.FillGroup:OnListingChanged(has, was == true) end
  -- Reserved slots end with the listing they were made for (1.5.0).
  if ns.db and ns.Players then ns.Players:OnListing(has, was == true, was == nil) end
  if event == "PLAYER_ENTERING_WORLD" or was == nil then return end   -- baseline only
  if not has or was then return end
  if not ns.db or ns.db.settings.autoOpenOnListing == false then return end
  if InCombatLockdown and InCombatLockdown() then return end
  if not (ns.Tracker.DetectListingDungeon and ns.Tracker:DetectListingDungeon()) then return end  -- not a Season M+ listing
  self:Show("applicants")
end

-- Two layouts:
--   below (default): as wide as the Group Finder, applicants in two columns, under its
--     bottom tab row. Leaves the area to the right of the Group Finder free, where other
--     add-ons (e.g. Raider.IO's profile panel) attach.
--   right / free-floating: a single column.
local FP_ROW_H, FP_ROW_GAP, FP_TOP, FP_BOTTOM = 34, 2, 42, 30
local FP_COL_W = 280
local FP_TAB_CLEARANCE = 36   -- the Group Finder's bottom tabs hang below its frame

function UI:BuildFinderPanel()
  if self.fp then return end
  local fp = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  fp:SetSize(FP_COL_W, 120)
  fp:SetFrameStrata(UI.OVER_WINDOW_STRATA)
  fp:SetFrameLevel(UI.OVER_WINDOW_LEVEL)   -- over the main window ("Details" opens it beside the panel)
  fp:SetClampedToScreen(true)
  fp:SetMovable(true)
  fp:EnableMouse(true)
  fp:RegisterForDrag("LeftButton")
  -- Drag anywhere outside the applicant rows to move it; it then stays where you put it
  -- (undocked) until you click Dock.
  fp:SetScript("OnDragStart", function(self) self:StartMoving() end)
  fp:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    UI:SaveFinderPanelPosition()
  end)
  Skin(fp, C.bg, C.border)
  fp:Hide()
  fp.title = AccentText(fp); fp.title:SetPoint("TOPLEFT", 10, -8)
  fp.title:SetWordWrap(false)
  fp.dock = Button(fp, "Dock", 44, 16, function() UI:DockFinderPanel() end)
  fp.dock:SetPoint("TOPRIGHT", -6, -6)
  fp.dock.tooltip = "Re-attach to the Group Finder"
  -- Docked: flip between below and to the right of the Group Finder.
  fp.side = FlatButton(fp, "", 86, 16, function()
    UI:DockFinderPanel(ns.db.settings.finderPanel.side == "right" and "below" or "right")
  end)
  fp.side:SetPoint("TOPRIGHT", -6, -6)
  fp.gear = UI:GearButton(fp, "finder", "Group Finder settings")
  fp.sub = Text(fp, 10, C.muted); fp.sub:SetPoint("TOPLEFT", 10, -24); fp.sub:SetPoint("RIGHT", -10, 0)
  fp.sub:SetWordWrap(false)
  fp.rows = {}
  for i = 1, FP_ROWS do
    local r = CreateFrame("Button", nil, fp)
    ns.Links:Enable(r)
    r:SetSize(FP_COL_W - 16, FP_ROW_H)
    local hl = r:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints()
    Accent(hl, "tex", 0.10); r:SetHighlightTexture(hl)
    r.bar = r:CreateTexture(nil, "ARTWORK"); r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(4)
    r.top = Text(r, 11); r.top:SetPoint("TOPLEFT", 10, -3); r.top:SetPoint("RIGHT", -2, 0); r.top:SetWordWrap(false)
    -- Headline, then the group's status after them at the right end of the same line.
    r.after = Text(r, 10); r.after:SetPoint("BOTTOMRIGHT", -6, 3); r.after:SetJustifyH("RIGHT"); r.after:SetWordWrap(false)
    r.bottom = Text(r, 10, C.muted); r.bottom:SetPoint("BOTTOMLEFT", 10, 3); r.bottom:SetPoint("RIGHT", r.after, "LEFT", -6, 0)
    r.bottom:SetWordWrap(false)
    fp.rows[i] = r
  end
  fp.more = FlatButton(fp, "", 200, 18, function()
    UI.fpExpanded = not UI.fpExpanded
    UI:QueueFinderRefresh()
  end)
  fp.more:SetPoint("BOTTOMLEFT", 6, 7)
  fp.more.text:ClearAllPoints(); fp.more.text:SetPoint("LEFT", 4, 0)
  fp.open = Button(fp, "Details", 70, 20, function() UI:Show("applicants") end)
  fp.open:SetPoint("BOTTOMRIGHT", -8, 6)
  fp.needs = Button(fp, "What we need", 100, 20, function() UI:CopyNeedsText() end)
  fp.needs:SetPoint("RIGHT", fp.open, "LEFT", -6, 0)
  fp.needs.tooltip = "A short line for your listing's description: open roles and what your group still needs, so the right players apply"
  self.fp = fp
  self:BuildFinderPlanView()
end

-- Auto-fill's alert by the Group Finder (option C, approved October 23): the docked panel turns
-- into the plan. The list fades, the border flashes, the plan slides up 12px and fades in
-- (0.25 s), then a slow breathing glow. "Back to list" or a plan that stops passing switches back.
local FPP_H = 176
function UI:BuildFinderPlanView()
  local fp = self.fp
  local v = CreateFrame("Frame", nil, fp)
  v:SetPoint("TOPLEFT", 0, 0); v:SetPoint("BOTTOMRIGHT", 0, 0)
  v:Hide()
  v.title = Text(v, 13); v.title:SetPoint("TOPLEFT", 10, -10); v.title:SetWordWrap(false)
  v.back = Button(v, "Back to list", 90, 20, function()
    UI.fpListFor = ns.FillGroup.notifiedSig
    UI:QueueFinderRefresh()
  end)
  v.back:SetPoint("TOPRIGHT", -8, -8)
  v.back.tooltip = "Show the applicant list. The plan comes back when a different group passes."
  v.title:SetPoint("RIGHT", v.back, "LEFT", -8, 0)
  v.rows = {}
  for i = 1, 4 do
    local r = Text(v, 11); r:SetPoint("TOPLEFT", 12, -36 - (i - 1) * 18); r:SetWidth(300); r:SetWordWrap(false)
    v.rows[i] = r
  end
  v.side = Text(v, 11, C.text); v.side:SetPoint("TOPLEFT", 330, -36); v.side:SetPoint("RIGHT", -10, 0)
  v.side:SetJustifyV("TOP")
  v.note = Text(v, 10, C.muted); v.note:SetPoint("BOTTOMLEFT", 12, 12); v.note:SetText("Nothing is sent until you click.")
  v.fill = Button(v, "Fill group", 128, 24)
  v.fill:SetPoint("BOTTOMRIGHT", -10, 8)
  if v.fill.SetMotionScriptsWhileDisabled then v.fill:SetMotionScriptsWhileDisabled(true) end
  Glow(v.fill)
  v.review = Button(v, "Review", 96, 24, function()
    UI:Show("applicants"); UI.ap.showPlan = true; UI:QueueRefresh()
  end)
  v.review:SetPoint("RIGHT", v.fill, "LEFT", -8, 0)
  v.review.tooltip = "Open the Applicants tab on the full plan"
  -- The panel's own glow (around its edge), breathing while the plan shows.
  local edge = CreateFrame("Frame", nil, fp)
  edge:SetPoint("TOPLEFT", -3, 3); edge:SetPoint("BOTTOMRIGHT", 3, -3)
  edge:SetFrameLevel(math.max(0, (fp:GetFrameLevel() or 1) - 1))
  Glow(edge, 0)
  v.edge = edge
  -- Entrance: fade in and slide up 12px over 0.25 s. A Translation moves the frame from its
  -- anchor and snaps back when it ends, so the plan starts anchored 12px low, slides up into
  -- place, and is re-anchored there when the animation finishes.
  local function Settle() v:ClearAllPoints(); v:SetPoint("TOPLEFT", 0, 0); v:SetPoint("BOTTOMRIGHT", 0, 0) end
  v.settle = Settle
  local ag = v.CreateAnimationGroup and v:CreateAnimationGroup()
  if ag then
    local a = ag.CreateAnimation and ag:CreateAnimation("Alpha")
    if a then
      if a.SetFromAlpha then a:SetFromAlpha(0) end
      if a.SetToAlpha then a:SetToAlpha(1) end
      if a.SetDuration then a:SetDuration(0.25) end
    end
    local t = ag.CreateAnimation and ag:CreateAnimation("Translation")
    if t then
      if t.SetOffset then t:SetOffset(0, 12) end
      if t.SetDuration then t:SetDuration(0.25) end
      if t.SetSmoothing then t:SetSmoothing("OUT") end
    end
    if ag.SetScript then ag:SetScript("OnFinished", Settle) end
  end
  v.enter = ag
  fp.planView = v
end

-- Is Auto-fill's alert up (armed, told, and the plan still passing)?
function UI:FillAlertPlan()
  local FG = ns.FillGroup
  if not (FG.armed and FG.notifiedSig) then return nil end
  local plan = FG:Current()
  if plan and plan.status == "ready" then return plan end
  return nil
end

-- Show the plan in the docked panel; true when it did (the list rows stay hidden then).
function UI:RenderFinderPlanView(ctx)
  local fp, v = self.fp, self.fp and self.fp.planView
  if not v then return false end
  local plan = self:FillAlertPlan()
  local show = plan and self.fpListFor ~= plan.sig and true or false
  if not show then
    if v:IsShown() then v:Hide(); v.edge:SetGlow(false) end
    self.fpPlanSig = nil
    return false
  end
  local FG = ns.FillGroup
  local dname = DD.list[plan.dungeonKey] and DD.list[plan.dungeonKey].name or ""
  v.title:SetText(TEX_OK .. " " .. HEX.good .. UI:ReadyTitle() .. "|r" .. HEX.muted .. "  -  " .. dname
    .. (plan.keyLevel and (" +" .. plan.keyLevel) or "") .. "  -  " .. FG.LEVEL_LABEL[plan.level] .. "|r")
  for i, r in ipairs(v.rows) do
    local ev = plan.picks[i]
    if ev then
      local m1 = ev.members[1] or {}
      local p1 = m1.specID and UD:GetSpec(m1.specID)
      local spec = p1 and UI.ShortLabel(UD:SpecName(m1.specID) .. " " .. UD:ClassName(p1.class)) or UD:ClassName(m1.classFile)
      r:SetText(HEX.muted .. (ROLE_WORD[ev.roles[1]] or "?"):upper() .. "|r  " .. self:ApplicantNames(ev) .. HEX.muted .. " " .. spec
        .. "|r   " .. ev.rating.hex .. ev.rating.word .. " " .. ev.score .. "|r")
      r:Show()
    else r:Hide() end
  end
  local j = plan.judge
  local side = { HEX.accent .. "GROUP AFTER|r" }
  local thinMusts = 0
  for _, row in ipairs(j.mustRows) do if row.status == "thin" then thinMusts = thinMusts + 1 end end
  local musts = #j.mustRows > 0 and (TEX_OK .. " Musts: " .. (plan.musts.lust and "Bloodlust" or "")
    .. (#plan.musts.reqs > 0 and ((plan.musts.lust and ", " or "") .. #plan.musts.reqs .. " boss need" .. (#plan.musts.reqs == 1 and "" or "s")) or "")
    .. (thinMusts > 0 and (HEX.warn .. " (" .. thinMusts .. " thin)|r") or "")) or nil
  if musts then side[#side + 1] = musts end
  side[#side + 1] = TEX_OK .. " Passes " .. FG.LEVEL_LABEL[plan.level]
  if #j.thin > 0 then side[#side + 1] = TEX_WAIT .. " " .. #j.thin .. " thin: " .. table.concat(j.thin, ", ") end
  if #plan.skipped > 0 then side[#side + 1] = HEX.muted .. #plan.skipped .. " skipped by your filters|r" end
  v.side:SetText(table.concat(side, "\n"))
  self:SyncFillButton(v.fill, plan)
  local first = not v:IsShown() or self.fpPlanSig ~= plan.sig
  self.fpPlanSig = plan.sig
  -- Size: as wide as the panel's layout, tall enough for the plan.
  local wide = self:FinderPanelLayout() == "below"
  local width = wide and math.max(2 * FP_COL_W - 20, (PVEFrame and PVEFrame.GetWidth and PVEFrame:GetWidth()) or 0) or math.max(FP_COL_W, 460)
  fp:SetSize(width, FPP_H)
  v.side:ClearAllPoints()
  if width >= 540 then
    v.side:SetPoint("TOPLEFT", math.floor(width * 0.58), -36); v.side:SetPoint("RIGHT", -10, 0)
    for _, r in ipairs(v.rows) do r:SetWidth(math.floor(width * 0.58) - 20) end
  else
    v.side:SetPoint("TOPLEFT", 12, -36 - 4 * 18 - 4); v.side:SetPoint("RIGHT", -10, 0)
    for _, r in ipairs(v.rows) do r:SetWidth(width - 24) end
  end
  for _, r in ipairs(fp.rows) do r:Hide() end
  fp.more:Hide(); fp.needs:Hide(); fp.open:Hide(); fp.title:Hide(); fp.sub:Hide()
  fp.dock:Hide(); fp.side:Hide(); fp.gear:Hide()   -- "Back to list" takes their corner
  v:Show()
  v.edge:SetGlow(true)
  if first then
    -- The border flashes, then the plan slides in.
    fp:SetBackdropBorderColor(unpack(C.good))
    if C_Timer and C_Timer.After then
      C_Timer.After(0.3, function() if UI.fp then UI.fp:SetBackdropBorderColor(unpack(C.border)) end end)
    end
    if v.enter then
      v.enter:Stop()
      v:ClearAllPoints(); v:SetPoint("TOPLEFT", 0, -12); v:SetPoint("BOTTOMRIGHT", 0, -12)
      v.enter:Play()
      -- Without the animation finishing (no animation support), never leave it 12px low.
      if not (v.enter.IsPlaying and v.enter:IsPlaying()) then v.settle() end
    end
  end
  return true
end

---------------------------------------------------------------------------
-- Auto-fill's pop-up: shown when it finds a group while the main window and the Group Finder
-- are closed (none of the other alerts can be seen then). Near the top of the screen.
---------------------------------------------------------------------------
function UI:BuildFillPopup()
  if self.fillPopup then return self.fillPopup end
  local f = CreateFrame("Frame", "EnsembleFillPopup", UIParent, "BackdropTemplate")
  f:SetSize(384, 156)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  Skin(f, C.bg, C.accent)
  f.logo = f:CreateTexture(nil, "ARTWORK"); f.logo:SetTexture(UI.LOGO); f.logo:SetSize(22, 22); f.logo:SetPoint("TOPLEFT", 10, -9)
  f.title = Text(f, 13); f.title:SetPoint("LEFT", f.logo, "RIGHT", 6, 0); f.title:SetPoint("RIGHT", -34, 0); f.title:SetWordWrap(false)
  f.close = FlatButton(f, "x", 22, 20, function() UI.fillPopupDismissed = ns.FillGroup.notifiedSig; f:Hide() end)
  f.close:SetPoint("TOPRIGHT", -6, -8)
  f.close.tooltip = "Hide this until a different group passes"
  f.rows = {}
  for i = 1, 4 do
    local r = Text(f, 11); r:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 17); r:SetPoint("RIGHT", -12, 0); r:SetWordWrap(false)
    f.rows[i] = r
  end
  f.after = Text(f, 11); f.after:SetPoint("TOPLEFT", 12, -110); f.after:SetPoint("RIGHT", -12, 0); f.after:SetWordWrap(false)
  f.fill = Button(f, "Fill group", 150, 24)
  f.fill:SetPoint("BOTTOMRIGHT", -10, 8)
  if f.fill.SetMotionScriptsWhileDisabled then f.fill:SetMotionScriptsWhileDisabled(true) end  -- the tooltip says why it's off
  Glow(f.fill)
  f.review = Button(f, "Review", 110, 24, function()
    UI:Show("applicants"); UI.ap.showPlan = true; UI:QueueRefresh(); f:Hide()
  end)
  f.review:SetPoint("BOTTOMLEFT", 10, 8)
  f:Hide()
  self.fillPopup = f
  return f
end

function UI:UpdateFillPopup()
  local plan = self:FillAlertPlan()
  local want = plan and ns.db and ns.db.settings.fill.popup ~= false
    and not (self.frame and self.frame:IsShown())
    and not (PVEFrame and PVEFrame.IsShown and PVEFrame:IsShown())
    and self.fillPopupDismissed ~= plan.sig
  if not want then
    if self.fillPopup then self.fillPopup:Hide() end
    return
  end
  local f = self:BuildFillPopup()
  local FG = ns.FillGroup
  local dname = DD.list[plan.dungeonKey] and DD.list[plan.dungeonKey].name or ""
  f.title:SetText(HEX.good .. UI:ReadyTitle() .. "|r" .. HEX.muted .. "  -  " .. dname .. (plan.keyLevel and (" +" .. plan.keyLevel) or "") .. "|r")
  for i, r in ipairs(f.rows) do
    local ev = plan.picks[i]
    if ev then
      local m1 = ev.members[1] or {}
      local p1 = m1.specID and UD:GetSpec(m1.specID)
      local spec = p1 and UI.ShortLabel(UD:SpecName(m1.specID) .. " " .. UD:ClassName(p1.class)) or UD:ClassName(m1.classFile)
      r:SetText(HEX.muted .. (ROLE_WORD[ev.roles[1]] or "?"):upper() .. "|r  " .. self:ApplicantNames(ev) .. HEX.muted .. " " .. spec
        .. "|r   " .. ev.rating.hex .. ev.rating.word .. " " .. ev.score .. "|r")
      r:Show()
    else r:Hide() end
  end
  f.after:SetText((plan.groupAfter and self:GroupAfterText(plan.groupAfter, "brief") or "") .. HEX.muted .. "  -  " .. FG.LEVEL_LABEL[plan.level] .. "|r")
  self:SyncFillButton(f.fill, plan)
  f:Show()
end

-- "below" when docked under the Group Finder; otherwise one column.
function UI:FinderPanelLayout()
  local pos = ns.db.settings.finderPanel
  if pos.docked and pos.side ~= "right" then return "below" end
  return "column"
end

-- Size the panel and place its rows for `shown` applicants.
function UI:LayoutFinderPanel(shown)
  local fp = self.fp
  local wide = self:FinderPanelLayout() == "below"
  local cols = wide and 2 or 1
  local width = FP_COL_W
  if wide then
    width = math.max(2 * FP_COL_W - 20, (PVEFrame and PVEFrame.GetWidth and PVEFrame:GetWidth()) or 0)
  end
  local colW = math.floor((width - 16 - (cols - 1) * 8) / cols)
  for i, r in ipairs(fp.rows) do
    local col = (i - 1) % cols
    local line = math.floor((i - 1) / cols)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 8 + col * (colW + 8), -FP_TOP - line * (FP_ROW_H + FP_ROW_GAP))
    r:SetSize(colW, FP_ROW_H)
  end
  local lines = math.max(1, math.ceil(math.max(1, shown) / cols))
  fp:SetSize(width, FP_TOP + lines * (FP_ROW_H + FP_ROW_GAP) + FP_BOTTOM)
  -- Single column is narrow: shorter "what we need" label so the "+N more" link keeps its room.
  if fp.needs then
    fp.needs.text:SetText(wide and "What we need" or "Needs")
    fp.needs:SetWidth(wide and 100 or 58)
    fp.more:SetWidth(math.max(80, width - (wide and 100 or 58) - 70 - 30))
  end
end

function UI:SaveFinderPanelPosition()
  local fp = self.fp
  if not fp then return end
  local pos = ns.db.settings.finderPanel
  -- Store TOPLEFT relative to UIParent's BOTTOMLEFT so it survives resolution changes.
  local left, top = fp:GetLeft(), fp:GetTop()
  if left and top then
    local s = fp:GetEffectiveScale() / UIParent:GetEffectiveScale()
    pos.point, pos.relPoint, pos.x, pos.y = "TOPLEFT", "BOTTOMLEFT", left * s, top * s
    pos.docked = false
  end
  self:PositionFinderPanel()
  self:QueueRefresh()
end

-- Re-dock; `side` ("below"/"right") switches where, nil keeps the last choice.
function UI:DockFinderPanel(side)
  local pos = ns.db.settings.finderPanel
  pos.docked = true
  if side then pos.side = side end
  self:PositionFinderPanel()
  self:QueueFinderRefresh()
  self:QueueRefresh()
end

function UI:PositionFinderPanel()
  local fp = self.fp
  if not fp then return end
  local pos = ns.db.settings.finderPanel
  fp:ClearAllPoints()
  if pos.docked or not (pos.x and pos.y) then
    if pos.side == "right" then
      fp:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", 4, 0)
    else
      fp:SetPoint("TOPLEFT", PVEFrame, "BOTTOMLEFT", 0, -FP_TAB_CLEARANCE)
    end
  else
    fp:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relPoint or "BOTTOMLEFT", pos.x, pos.y)
  end
  fp.dock:SetShown(not pos.docked)
  fp.side:SetShown(pos.docked and true or false)
  fp.side.text:SetText(pos.side == "right" and "Dock below" or "Dock right")
  fp.side.tooltip = pos.side == "right" and "Move under the Group Finder" or "Move to the right of the Group Finder"
  fp.title:SetPoint("RIGHT", pos.docked and -118 or -76, 0)
  fp.gear:ClearAllPoints()
  fp.gear:SetPoint("RIGHT", pos.docked and fp.side or fp.dock, "LEFT", -4, 0)
end

-- "  waiting 2:40" for an application (amber after 3 minutes: decide soon).
function UI:WaitText(firstSeen, bare)
  if not firstSeen or not GetTime then return "" end
  local sec = math.max(0, math.floor(GetTime() - firstSeen))
  local t = string.format("%d:%02d", math.floor(sec / 60), sec % 60)
  return (sec >= 180 and HEX.warn or HEX.muted) .. (bare and "" or "  - ") .. "waiting " .. t .. "|r"
end

-- One ticker updates the waiting times once a second while applicants are on screen.
function UI:UpdateWaitTimes()
  local any = false
  if self.frame and self.frame:IsShown() and self.currentTab == "applicants" and self.ap then
    for _, c in ipairs(self.ap.cards) do
      if c:IsShown() and c.subBase then c.wait:SetText(self:WaitText(c.firstSeen, true)); any = true end
    end
  end
  if self.fp and self.fp:IsShown() then
    for _, r in ipairs(self.fp.rows) do
      if r:IsShown() and r.topBase then r.top:SetText(r.topBase .. self:WaitText(r.firstSeen)); any = true end
    end
  end
  if not any and self.waitTicker then self.waitTicker:Cancel(); self.waitTicker = nil end
end

function UI:EnsureWaitTicker()
  if self.waitTicker or not (C_Timer and C_Timer.NewTicker) then return end
  self.waitTicker = C_Timer.NewTicker(1, function() UI:UpdateWaitTimes() end)
end

-- Fit rating in the Group Finder's own applicant tooltip (hover a name in Blizzard's list).
-- Only adds lines to GameTooltip after Blizzard's own handler ran (hooksecurefunc), so the
-- protected Invite/Decline buttons are untouched.
local function Plain(text)
  return (tostring(text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("^%s+", ""))
end
UI.Plain = Plain

function UI:AddApplicantTooltip(member)
  if not ns.db or ns.db.settings.finderTooltip == false or not GameTooltip then return end
  local parent = member and member.GetParent and member:GetParent()
  local id = (parent and parent.applicantID) or (member and member.applicantID)
  if not id then return end
  local ok, _, evals = pcall(ns.ApplicantFit.ForLiveGroup, ns.ApplicantFit)
  if not ok or type(evals) ~= "table" then return end
  for _, ev in ipairs(evals) do
    if ev.applicantID == id then
      local c = ev.rating.color
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Ensemble: " .. ev.rating.label .. " (" .. ev.score .. "/100)", c[1], c[2], c[3])
      GameTooltip:AddLine(Plain(ev.headline), 1, 1, 1, true)
      local pastText, st = UI:PastKeysText(ev, true)
      if pastText then
        local col = st == "failed" and C.warn or st == "timed" and C.good or C.muted
        GameTooltip:AddLine(pastText, col[1], col[2], col[3], true)
      end
      if not ev.roleConflict and ev.groupAfter then
        GameTooltip:AddLine(UI:GroupAfterText(ev.groupAfter, "full"), 1, 1, 1, true)
      end
      local why = ev.breakdown and ev.breakdown[1]
      if why and why.points > 0 then GameTooltip:AddLine("Biggest reason: " .. Plain(why.text), 0.7, 0.7, 0.7, true) end
      GameTooltip:Show()
      return
    end
  end
end

function UI:HookFinderTooltips()
  if self.tipHooked or not hooksecurefunc then return end
  if type(LFGListApplicantMember_OnEnter) ~= "function" then return end
  self.tipHooked = true
  hooksecurefunc("LFGListApplicantMember_OnEnter", function(member) UI:AddApplicantTooltip(member) end)
end

function UI:FinderPanelWanted()
  return ns.db and ns.db.settings.applicantPanel ~= false and PVEFrame and PVEFrame:IsShown()
end

-- Acquire/release the tracker for the panel and show/hide it.
function UI:UpdateFinderPanel()
  if not ns.db then return end
  -- Keep applicant data fresh for the Group Finder tooltip lines while the window is open.
  if ns.db.settings.finderTooltip ~= false and PVEFrame and PVEFrame:IsShown() then
    ns.Tracker:Acquire("tooltip")
  else
    ns.Tracker:Release("tooltip")
  end
  if self:FinderPanelWanted() then
    ns.Tracker:Acquire("finder")
    self:QueueFinderRefresh()
  else
    ns.Tracker:Release("finder")
    if self.fp then self.fp:Hide() end
  end
  self:UpdateFillPopup()
end

function UI:QueueFinderRefresh()
  if self.finderQueued or not self:FinderPanelWanted() then return end
  self.finderQueued = true
  C_Timer.After(0, function()
    UI.finderQueued = false
    local ok, err = pcall(UI.RefreshFinderPanel, UI)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end)
end

function UI:RefreshFinderPanel()
  if not self:FinderPanelWanted() then if self.fp then self.fp:Hide() end return end
  local T = ns.Tracker
  if not T.hosting then if self.fp then self.fp:Hide() end return end
  self:BuildFinderPanel()
  UD, DD, Analysis = ns.UD, ns.Dungeons, ns.Analysis
  local fp = self.fp
  local ctx, evals = ns.ApplicantFit:ForLiveGroup()
  self:PositionFinderPanel()
  local dname = ctx.dungeonKey and DD.list[ctx.dungeonKey] and DD.list[ctx.dungeonKey].name
  fp.title:SetText("Applicant fit  " .. HEX.muted .. "(drag to move)|r")
  fp.sub:SetText(UI:DungeonLabel(ctx.dungeonKey, 12) .. (ctx.keyLevel and (" +" .. ctx.keyLevel) or ""))
  fp:Show()
  if self:RenderFinderPlanView(ctx) then return end
  fp.title:Show(); fp.sub:Show(); fp.more:Show(); fp.needs:Show(); fp.open:Show(); fp.gear:Show()
  local limit = UI.fpExpanded and FP_ROWS or FP_SHOW
  local shown = math.min(limit, #evals)
  self:LayoutFinderPanel(shown)
  for i = 1, FP_ROWS do
    local r, ev = fp.rows[i], i <= shown and evals[i] or nil
    if ev then
      r.bar:SetColorTexture(unpack(ev.rating.color))
      r.topBase = self:RatingTag(ev) .. "  " .. self:ApplicantNames(ev)
      r.firstSeen = ev.members[1] and ev.members[1].firstSeen
      r.top:SetText(r.topBase .. UI:WaitText(r.firstSeen))
      r.bottom:SetText(ev.headline)
      r.after:SetText(ev.roleConflict and "" or self:GroupAfterText(ev.groupAfter, "short"))
      local id = ev.applicantID
      r:SetScript("OnClick", function() UI:Show("applicants"); UI.ap.selected = id; UI:QueueRefresh() end)
      r:Show()
    else
      r:Hide()
    end
  end
  self:EnsureWaitTicker()
  if #evals == 0 then
    fp.more.text:SetText("No applicants yet."); fp.more:Disable(); fp.more.tooltip = nil
  elseif UI.fpExpanded and #evals > FP_SHOW then
    fp.more.text:SetText("- show fewer" .. (#evals > shown and ("  (" .. (#evals - shown) .. " more in Details)") or ""))
    fp.more:Enable(); fp.more.tooltip = "Show fewer"
  elseif #evals > shown then
    fp.more.text:SetText("+ " .. (#evals - shown) .. " more"); fp.more:Enable(); fp.more.tooltip = "Show all"
  else
    fp.more.text:SetText(""); fp.more:Disable(); fp.more.tooltip = nil
  end
  fp:Show()
end

---------------------------------------------------------------------------
-- Saved comps + comparison + import/export
---------------------------------------------------------------------------
function UI:LoadSavedComp(c)
  for s = 1, ns.NUM_SLOTS do
    ns.db.currentComp[s] = c.slots[s] or 0
    local x = c.people and c.people[s]
    ns.db.currentPeople[s] = type(x) == "table" and { full = x.full, spec = x.spec } or false
  end
  -- A saved comp's dungeon is a deliberate pick.
  if c.dungeon and c.dungeon ~= "NONE" and DD.list[c.dungeon] then ns.db.selectedDungeon = c.dungeon end
  if self.cp then self.cp.nameBox:SetText(c.name) end
  ns:Fire("COMP_CHANGED", "load"); ns:Fire("DUNGEON_CHANGED")
  self:SetCompMode("planner")
  self:SetTab("composition")
end

-- Import a comp string (from the Saved menu's "Import..." box).
function UI:ImportString(str)
  local data, err = ns.Share.Decode(str)
  if not data then return false, "Import failed: " .. tostring(err) end
  local name = data.name
  local exists = true
  local n = 1
  while exists do
    exists = false
    for _, c in ipairs(ns.db.savedComps) do if c.name == name then exists = true end end
    if exists then n = n + 1; name = data.name .. " (" .. n .. ")" end
  end
  table.insert(ns.db.savedComps, { name = name, slots = data.slots, dungeon = data.dungeon, created = time and time() or 0 })
  self:QueueRefresh()
  return true, "Imported '" .. name .. "'."
end

function UI:DeleteSavedComp(c)
  for i, x in ipairs(ns.db.savedComps) do
    if x == c then table.remove(ns.db.savedComps, i); ns:Print("Deleted '" .. tostring(c.name) .. "'."); break end
  end
  self:QueueRefresh()
end

-- Saved comps menu: load one, delete one, import a string.
function UI:OpenSavedMenu(anchor)
  local items = {}
  local list = {}
  for _, c in ipairs(ns.db.savedComps) do list[#list + 1] = c end
  table.sort(list, function(a, b) return (a.created or 0) > (b.created or 0) end)
  for _, c in ipairs(list) do
    local dname = c.dungeon and DD.list[c.dungeon] and ("  " .. HEX.muted .. DD.list[c.dungeon].name .. "|r") or ""
    items[#items + 1] = { text = "Load " .. c.name .. dname, onClick = function() UI:LoadSavedComp(c) end }
  end
  if #list == 0 then items[#items + 1] = { text = HEX.muted .. "No saved comps yet|r" } end
  items[#items + 1] = { text = "Import a comp string...", onClick = function() UI:ShowImport() end }
  if #list > 0 then
    items[#items + 1] = { text = "Delete a saved comp...", onClick = function()
      local del = {}
      for _, c in ipairs(list) do del[#del + 1] = { text = "Delete " .. c.name, onClick = function() UI:DeleteSavedComp(c) end } end
      UI:ShowMenu(anchor, del)
    end }
  end
  self:ShowMenu(anchor, items)
end


-- "Best key for this group": every Season dungeon ranked for the current comp. Click a
-- dungeon to check the group against it.
function UI:ShowBestKey()
  self:Build()
  if not self.bestKey then
    local p = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    p:SetSize(560, 400); p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    Skin(p, C.bg, C.accent)
    Accent(p, "border")
    p.title = AccentText(p); p.title:SetPoint("TOPLEFT", 12, -10); p.title:SetText("Best key for this group")
    local close = Button(p, "Close", 80, 22, function() p:Hide() end); close:SetPoint("TOPRIGHT", -10, -6)
    p.list = LineList(p, 540, 350):Fill(8, -34, -8, 8)
    self.bestKey = p
  end
  self:RenderBestKey()
  self.frame:Show()
  self.bestKey:Show()
end

function UI:RenderBestKey()
  local p = self.bestKey
  if not p then return end
  local L = p.list
  L:Clear()
  local members = (self.cp and self.cp.lastMembers) or {}
  if #members == 0 then
    L:Add(HEX.muted .. "Add players on Composition (or join a group) to rank the dungeons for them.|r")
    L:Finish(); return
  end
  local ownKey, ownLevel = ns:OwnKeystoneDungeon()
  local ranked = Analysis:RankDungeons(members, ns.db.settings, function(key)
    if key == ownKey then return ownLevel end
  end)
  L:Add(HEX.muted .. "Ranked by how well your " .. #members .. "-player group covers each dungeon (this week's affixes"
    .. " at your key's level, otherwise +10). Click one to check the group against it.|r", { size = 11, gap = 8 })
  for i, d in ipairs(ranked) do
    local c = d.counts
    local status
    if c.missing == 0 and c.thin == 0 then status = HEX.good .. TEX_OK .. " ready|r"
    else
      local parts = {}
      if c.missing > 0 then parts[#parts + 1] = HEX.bad .. c.missing .. " missing|r" end
      if c.thin > 0 then parts[#parts + 1] = HEX.warn .. c.thin .. " thin|r" end
      status = table.concat(parts, HEX.muted .. " · |r")
    end
    local tag = (d.key == ownKey) and (HEX.accent .. "  your key" .. (ownLevel and (" +" .. ownLevel) or "") .. "|r") or ""
    local key = d.key
    L:Add(HEX.text .. i .. ". " .. d.name .. "|r  " .. status .. tag, {
      size = 13, gap = 1,
      onClick = function() ns:SetManualDungeon(key, ns.state.mode == "live"); p:Hide() end,
      tooltip = "Check this group against " .. d.name,
    })
    local worst = {}
    for j = 1, math.min(3, #d.risks) do
      local row = d.risks[j]
      local it = row.items and row.items[1]
      local src = it and it.req and it.req.source and SourceName(it.req) or nil
      worst[#worst + 1] = (row.status == "missing" and HEX.bad or HEX.warn) .. row.label .. "|r"
        .. (src and (HEX.muted .. " (" .. Plain(src) .. ")|r") or "")
    end
    if #worst > 0 then L:Add(table.concat(worst, HEX.muted .. ", |r"), { indent = 18, size = 11, gap = 6 }) end
  end
  L:Finish()
end

-- Glossary popup (the "?" in the title bar).
function UI:ShowGlossary()
  self:Build()
  if not self.glossary then
    local p = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    p:SetSize(520, 420); p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    Skin(p, C.bg, C.accent)
    Accent(p, "border")
    p.title = AccentText(p); p.title:SetPoint("TOPLEFT", 12, -10); p.title:SetText("Glossary")
    local close = Button(p, "Close", 80, 22, function() p:Hide() end); close:SetPoint("TOPRIGHT", -10, -6)
    p.list = LineList(p, 500, 370):Fill(8, -34, -8, 8)
    self.glossary = p
  end
  local L = self.glossary.list
  L:Clear()
  L:Header("Terms")
  for _, g in ipairs(UD.GLOSSARY) do
    L:Add(HEX.text .. g[1] .. "|r" .. HEX.muted .. "  " .. g[2] .. "|r", { indent = 4, size = 11, gap = 3 })
  end
  L:Header("Needs")
  for _, c in ipairs(UD.CAPS) do
    L:Add(HEX.text .. c.label .. "|r" .. HEX.muted .. "  " .. (UD:CapExplain(c.key) or "") .. "|r", { indent = 4, size = 11, gap = 3 })
  end
  L:Finish()
  self.frame:Show()
  self.glossary:Show()
end

-- Sources: the guides the data comes from, grouped by use, each link in a read-only box to
-- copy (addons can't open a browser or show clickable web links).
function UI:ShowSources()
  self:Build()
  if not self.sources then
    local p = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    Skin(p, C.bg, C.accent)
    Accent(p, "border")
    p.title = AccentText(p); p.title:SetPoint("TOPLEFT", 12, -10); p.title:SetText("Sources")
    local close = Button(p, "Close", 80, 22, function() p:Hide() end); close:SetPoint("TOPRIGHT", -10, -6)
    local y = -38
    local intro = Text(p, 11, C.muted); intro:SetPoint("TOPLEFT", 14, y); intro:SetPoint("RIGHT", -14, 0)
    intro:SetText("The dungeon, boss and class data is written from these guides. Click a link, then Ctrl+C to copy it.")
    y = y - 34
    p.boxes = {}
    for _, grp in ipairs(DD.SOURCES) do
      local h = Text(p, 12, C.accent); h:SetPoint("TOPLEFT", 14, y); h:SetText(grp.group)
      y = y - 20
      for _, it in ipairs(grp.items) do
        local name = Text(p, 11, C.text); name:SetPoint("TOPLEFT", 22, y); name:SetText(it.name)
        y = y - 16
        local box = EditBox(p, 490, 22)
        box:SetPoint("TOPLEFT", 22, y)
        box.value = it.url
        box:SetText(it.url); box:SetCursorPosition(0)
        -- Read-only: typing puts the link back; focusing selects it for Ctrl+C.
        box:SetScript("OnTextChanged", function(b, user) if user then b:SetText(b.value); b:HighlightText() end end)
        box:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
        p.boxes[#p.boxes + 1] = box
        y = y - 30
      end
      y = y - 4
    end
    local foot = Text(p, 11, C.muted); foot:SetPoint("TOPLEFT", 14, y - 4); foot:SetPoint("RIGHT", -14, 0)
    foot:SetText(DD.SOURCES_FOOTER)
    p.footer = foot
    p:SetSize(540, -y + 40); p:SetPoint("CENTER")
    self.sources = p
  end
  self.frame:Show()
  self.sources:Show()
  return self.sources
end

-- Export popup: a read-only, pre-selected edit box to copy from.
function UI:BuildSharePopup()
  local p = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
  p:SetSize(560, 110); p:SetPoint("CENTER")
  p:SetFrameStrata("DIALOG")
  Skin(p, C.bg, C.accent)
  Accent(p, "border")
  p:Hide()
  p.title = AccentText(p); p.title:SetPoint("TOPLEFT", 12, -10)
  p.box = EditBox(p, 536, 26); p.box:SetPoint("TOPLEFT", 12, -34)
  p.box:SetScript("OnEscapePressed", function() p:Hide() end)
  p.box:SetScript("OnEnterPressed", function() if p.onAccept then p.import:Click() end end)
  p.box:SetScript("OnTextChanged", function(box, user)
    if user and not p.importing then box:SetText(p.value or ""); box:HighlightText() end
  end)
  p.hint = Text(p, 11, C.muted); p.hint:SetPoint("TOPLEFT", 12, -68); p.hint:SetPoint("RIGHT", -190, 0)
  local close = Button(p, "Close", 80, 22, function() p:Hide() end); close:SetPoint("BOTTOMRIGHT", -10, 10)
  p.import = Button(p, "Import", 80, 22, function()
    if p.onAccept then
      local f = p.onAccept
      p.onAccept = nil; p:Hide(); f(p.box:GetText())
      return
    end
    local ok, msg = UI:ImportString(p.box:GetText())
    p.hint:SetText((ok and HEX.good or HEX.bad) .. msg .. "|r")
    if ok then p.box:SetText("") end
  end)
  p.import:SetPoint("RIGHT", close, "LEFT", -6, 0)
  self.share = p
end

function UI:ShowShare(title, value)
  local p = self.share
  p.importing = false
  p.onAccept = nil
  p.title:SetText(title)
  p.value = value
  p.box:SetText(value)
  p.hint:SetText("Ctrl+C to copy.")
  p.import:Hide()
  p:Show()
  p.box:SetFocus(); p.box:HighlightText()
end

-- The same popup, editable, for pasting a comp string.
function UI:ShowImport()
  local p = self.share
  p.importing = true
  p.onAccept = nil
  p.import.text:SetText("Import")
  p.title:SetText("Import a comp string")
  p.value = nil
  p.box:SetText("")
  p.hint:SetText("Paste a ENS1: string (Ctrl+V), then Import.")
  p.import:Show()
  p:Show()
  p.box:SetFocus()
end

-- The same popup as a one-line text prompt: onAccept(text) on the button or Enter.
function UI:AskText(title, hint, value, label, onAccept)
  local p = self.share
  p.importing = true
  p.onAccept = onAccept
  p.title:SetText(title)
  p.value = nil
  p.box:SetText(value or "")
  p.hint:SetText(hint or "")
  p.import.text:SetText(label or "OK")
  p.import:Show()
  p:Show()
  p.box:SetFocus(); p.box:HighlightText()
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Dungeon: a walkthrough of any Season dungeon in the order you meet it (the guides'
-- order): each trash section and boss with what happens there, the Bloodlust plan,
-- filtered by role. Right: which classes answer the
-- most of it on their own, and the key-needs sheet. No group needed.
---------------------------------------------------------------------------
local PRIMER_TOP = 5
local WALK_ROLES = { { "ALL", "All" }, { "TANK", "Tank" }, { "HEAL", "Healer" }, { "DPS", "DPS" } }

function UI:BuildPrimerPage()
  local page = PageFrame(self.frame)
  self.pages.dungeons = page
  local pp = {}
  self.pp = pp
  local bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT", 12, -10); bar:SetPoint("TOPRIGHT", -12, -10); bar:SetHeight(30)
  local lbl = Text(bar, 12, C.muted); lbl:SetPoint("LEFT", 0, 0); lbl:SetText("Dungeon:")
  pp.dungeonBtn = Dropdown(bar, 280, 28, function(btn)
    local det, why = UI:PrimerDetected()
    local items = {
      { text = det and ("Auto: " .. DD.list[det].name .. "  " .. HEX.muted .. "(" .. why .. ")|r")
          or ("Auto  " .. HEX.muted .. "(the dungeon you're in, your listing or your keystone)|r"),
        icon = det and UI:DungeonIcon(det) or nil, selected = UI.primerPick == nil,
        onClick = function() UI:SetPrimerPick(nil) end },
    }
    for _, key in ipairs(DD.order) do
      table.insert(items, { text = DD.list[key].name, icon = UI:DungeonIcon(key), selected = UI.primerPick == key,
        onClick = function() UI:SetPrimerPick(key) end })
    end
    UI:ShowMenu(btn, items)
  end)
  pp.dungeonBtn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
  -- Role filter: boss notes and needs for one role (plus everyone's).
  pp.roleBtns = {}
  local prev
  for i = #WALK_ROLES, 1, -1 do
    local r = WALK_ROLES[i]
    local b = Button(bar, r[2], 58, 24, function() ns.db.settings.walkRole = r[1]; UI:QueueRefresh() end)
    SetFontSize(b.text, 11)
    b.tooltip = r[1] == "ALL" and "Everything, every role" or ("What a " .. r[2]:lower() .. " needs to know, plus what everyone does")
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT", 0, 0) end
    pp.roleBtns[r[1]] = b
    prev = b
  end
  local rl = Text(bar, 11, C.muted); rl:SetPoint("RIGHT", prev, "LEFT", -6, 0); rl:SetText("Show:")
  pp.note = Text(bar, 11, C.muted); pp.note:SetPoint("LEFT", pp.dungeonBtn, "RIGHT", 10, 0); pp.note:SetPoint("RIGHT", rl, "LEFT", -10, 0)
  pp.note:SetWordWrap(false)
  local top, colH = -48, H - 41 - 48 - 12
  local left = Panel(page)
  left:SetPoint("TOPLEFT", 12, top); left:SetPoint("BOTTOMRIGHT", page, "BOTTOM", 70, 12)
  pp.walkTitle = AccentText(left); pp.walkTitle:SetPoint("TOPLEFT", 10, -8); pp.walkTitle:SetText("Walkthrough")
  -- The boss window on the dungeon this tab shows (which starts as your key, listing or zone).
  pp.bossBtn = Button(left, "Open boss cards", 124, 20, function() UI:OpenPrimerBossCards() end)
  SetFontSize(pp.bossBtn.text, 11)
  pp.bossBtn:SetPoint("TOPRIGHT", -6, -5)
  pp.bossBtn.tooltip = "Open the boss window on this dungeon's cards. Inside a Season dungeon it shows the one you're in."
  pp.asks = LineList(left, 530, colH - 34):Fill(6, -28, -6, 6)
  pp.walk = pp.asks
  local right = Panel(page)
  right:SetPoint("TOPLEFT", page, "TOP", 80, top); right:SetPoint("BOTTOMRIGHT", -12, 12)
  local rt = AccentText(right); rt:SetPoint("TOPLEFT", 10, -8); rt:SetText("Best value here")
  pp.value = LineList(right, 370, colH - 34):Fill(6, -28, -6, 6)
end

-- Which dungeon the Dungeon tab follows on Auto: the dungeon you're in, else your Group
-- Finder listing, else the planner's dungeon (a hand pick on Composition, else your keystone).
-- With "auto dungeon" off in Settings only a Composition hand pick counts. Its own check,
-- because the roster tracker (which keeps the listing and zone for Composition) isn't running
-- on this tab. Returns key, why (for the menu and the note).
function UI:PrimerDetected()
  local auto = ns.db.settings.liveAutoDungeon ~= false
  if auto then
    local key = ns:CurrentInstanceDungeon()
    if key and DD.list[key] then return key, "you're in it" end
    key = ns.Tracker and ns.Tracker.DetectListingDungeon and ns.Tracker:DetectListingDungeon()
    if key and DD.list[key] then return key, "your listing" end
  end
  local key, src = ns:GetEffectiveDungeon(false)
  if not (key and DD.list[key]) then return nil end
  if src == "manual" then return key, "your Composition pick" end
  local _, level = ns:OwnKeystoneDungeon()
  return key, "your key" .. (level and (" +" .. level) or "")
end

-- A dungeon picked by hand on the Dungeon tab (nil = Auto). Like the Composition picker, a
-- hand pick lasts until the detected dungeon changes (a new key, listing or zone).
function UI:SetPrimerPick(key)
  self.primerPick = key
  self.primerPickDetected = key and (self:PrimerDetected()) or nil
  self:QueueRefresh()
end

-- The dungeon the tab shows: the hand pick while it holds, else the detected one, else the
-- last one shown (or the first Season dungeon).
function UI:PrimerResolve()
  local det, why = self:PrimerDetected()
  if self.primerPick and det and det ~= self.primerPickDetected then self.primerPick, self.primerPickDetected = nil, nil end
  local key = self.primerPick or det
  if not (key and DD.list[key]) then key = (self.primerKey and DD.list[self.primerKey]) and self.primerKey or DD.order[1] end
  self.primerKey = key
  return key, (not self.primerPick) and det and why or nil
end

-- Open the boss window on the Dungeon tab's dungeon (first boss in your order).
function UI:OpenPrimerBossCards()
  local key = self:PrimerResolve()
  if ns.BossWindow and key then ns.BossWindow:Open(key) end
end

-- Which needs a role handles or helps with. Everyone kicks, stops, soothes, purges, frees and
-- uses personals; dispels are the healer's (and yours too when your own spec has that dispel);
-- tank-damage needs are the tank's and the healer's.
local EVERYONE_NEEDS = { interrupt = true, stop = true, aoe_stop = true, purge = true, soothe = true,
  freedom = true, group_defensive = true, dispel_bleed = true }
function UI:WalkRoleWants(role, q)
  if role == "ALL" or EVERYONE_NEEDS[q.need] then return true end
  if q.need == "external_defensive" then return role == "TANK" or role == "HEAL" end
  if role == "HEAL" then return true end
  if q.need:find("^dispel_") then
    local mine = ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID()
    local spec = mine and UD:GetSpec(mine)
    return spec and spec.caps[q.need] ~= nil or false
  end
  return false
end

-- One requirement line (and its mechanic note) in the walkthrough.
function UI:WalkReq(L, q, explainOn)
  local alts = {}
  for _, a in ipairs(q.alt or {}) do alts[#alts + 1] = UD:CapShort(a) end
  local sev = (q.severity == "critical" and HEX.bad) or (q.severity == "high" and HEX.warn) or HEX.muted
  local tip = UD:CapLabel(q.need) .. (explainOn and UD:CapExplain(q.need) and (": " .. UD:CapExplain(q.need)) or "")
  L:Add(HEX.text .. UD:CapShort(q.need):upper() .. "|r  " .. Analysis.Decorate(q.source or "", q.need, q.dungeon)
    .. "  " .. sev .. (q.severity or ""):upper() .. "|r"
    .. (#alts > 0 and (HEX.muted .. " (or " .. table.concat(alts, " / ") .. ")|r") or "")
    .. (q.affix and (HEX.muted .. " (affix: " .. q.affix .. ")|r") or "")
    .. (q.confidence ~= "verified" and (HEX.warn .. " [unconfirmed]|r") or ""),
    { indent = 8, size = 11, gap = 1, tooltip = tip })
  if q.note and not (q.need == "interrupt" and q.note == "Interrupt every cast.") then
    L:Add(HEX.muted .. q.note .. "|r", { indent = 22, size = 10, gap = 2 })
  end
end

-- A LUST marker at a step: "BLOODLUST  on pull" (click to change it on the Plan tab).
function UI:WalkLust(L, dk, st)
  local WT = ns.Walkthrough
  for _, x in ipairs(WT:LustAt(dk, st)) do
    local u = x.use
    L:Add(HEX.warn .. "BLOODLUST|r  " .. (u.note or (st.kind == "boss" and "on pull" or "here")), {
      indent = 8, size = 11, gap = 2, tooltip = "Lust #" .. x.i .. ". " .. WT:LustSource(dk) .. "\nClick to change it.",
      onClick = function(btn) UI:OpenLustMenu(btn, dk, x.i) end })
  end
end

-- The Bloodlust plan: one clickable line per use (change the spot, add a note, remove),
-- "+ Add a Bloodlust" and "Reset to the default". On the Plan and Dungeon tabs.
function UI:RenderLust(L, dk)
  local WT = ns.Walkthrough
  if not (dk and DD.list[dk] and WT) then return end
  local uses, custom = WT:Lust(dk)
  L:Header("Bloodlust")
  L:Add(HEX.muted .. WT:LustSource(dk) .. "|r", { size = 10, gap = 2 })
  if #uses == 0 then
    L:Add(HEX.muted .. "No Bloodlust planned.|r", { indent = 6, size = 11, gap = 2 })
  end
  for i, u in ipairs(uses) do
    L:Add(HEX.warn .. i .. ".|r " .. WT:LustText(dk, u), { indent = 6, size = 11, gap = 2,
      tooltip = "Click to move it, add a note or remove it.", onClick = function(btn) UI:OpenLustMenu(btn, dk, i) end })
  end
  if #uses < WT.LUST_MAX then
    L:Add(HEX.accent .. "+ Add a Bloodlust|r", { indent = 6, size = 10, gap = 2,
      onClick = function(btn) UI:OpenLustMenu(btn, dk, #uses + 1) end, tooltip = "Pick where it goes" })
  end
  if custom then
    L:Add(HEX.accent .. "> Reset to the default|r", { indent = 6, size = 10, gap = 4,
      onClick = function() WT:ResetLust(dk) end })
  else
    L:Space(2)
  end
end

-- Menu for lust #i: every spot in the dungeon (the trash before each boss, and the boss), a
-- note, remove. i past the end adds a new one.
function UI:OpenLustMenu(anchor, dk, i)
  local WT = ns.Walkthrough
  local uses = WT:Lust(dk)
  local cur = uses[i]
  local items = { { text = cur and ("Move lust " .. i .. " to:") or "Add a Bloodlust at:", header = true } }
  for _, sp in ipairs(WT:Spots(dk)) do
    items[#items + 1] = { text = sp.label, selected = cur and cur.at == sp.at,
      onClick = function() WT:SetLustAt(dk, i, sp.at) end }
  end
  if cur then
    items[#items + 1] = { text = cur.note and "Change the note..." or "Add a note...", onClick = function()
      UI:AskText("Bloodlust " .. i .. ": " .. WT:SpotLabel(dk, cur.at, true), "A short note, like \"on pull\" or \"at 40%\". Enter to save.",
        cur.note or "", "Save", function(text) WT:SetLustNote(dk, i, text) end)
    end }
    items[#items + 1] = { text = "Remove this one", color = C.bad, onClick = function() WT:RemoveLust(dk, i) end }
  end
  if anchor then self:ShowMenu(anchor, items) end
  return items
end

-- Boss order: "Move earlier / later" under a boss whose place the data lets you change.
UI.ORDER_TIP = "Groups can do these bosses in either order. Your order is saved for this dungeon; it also sets the Bloodlust order and which boss the boss window shows next."
function UI:RenderOrderMoves(L, key, i)
  local BC = ns.BossCards
  if not BC:OrderGroup(key, i) then return end
  local bosses = BC:Bosses(key)
  local before, after = BC:Neighbor(key, i, -1), BC:Neighbor(key, i, 1)
  if before then
    L:Add(HEX.accent .. "> Move earlier|r" .. HEX.muted .. " (before " .. bosses[before].name .. ")|r", { indent = 10, size = 10, gap = 1,
      onClick = function() BC:MoveBoss(key, i, -1) end, tooltip = self.ORDER_TIP })
  end
  if after then
    L:Add(HEX.accent .. "> Move later|r" .. HEX.muted .. " (after " .. bosses[after].name .. ")|r", { indent = 10, size = 10, gap = 1,
      onClick = function() BC:MoveBoss(key, i, 1) end, tooltip = self.ORDER_TIP })
  end
end

function UI:RenderWalkthrough(L, key, explainOn)
  local WT, BC = ns.Walkthrough, ns.BossCards
  local role = ns.db.settings.walkRole or "ALL"
  local w = WT:Build(key)
  if not w then return end
  local tags = ns.BossWindow and ns.BossWindow.ROLE_TAG or {}
  local bosses = BC:Bosses(key)
  self:RenderLust(L, key, true)
  if BC:IsCustomOrder(key) then
    local first = bosses[BC:Order(key)[1]]
    L:Add(HEX.muted .. "Boss order: yours" .. (first and (", " .. first.name .. " first") or "") .. ".|r", { size = 10, gap = 1 })
    L:Add(HEX.accent .. "> Reset to the guides' order|r", { indent = 6, size = 10, gap = 4,
      onClick = function() BC:ResetOrder(key) end, tooltip = "Back to the order the dungeon guides list" })
  end
  for _, st in ipairs(w.steps) do
    local reqs = {}
    for _, q in ipairs(st.reqs) do if self:WalkRoleWants(role, q) then reqs[#reqs + 1] = q end end
    if st.kind == "anywhere" then
      if #reqs > 0 then
        L:Header("Throughout the dungeon")
        for _, q in ipairs(reqs) do self:WalkReq(L, q, explainOn) end
      end
    elseif st.kind == "trash" then
      local lust = WT:LustAt(key, st)
      if #reqs > 0 or #lust > 0 then
        local head = st.boss and bosses[st.boss] and ("Trash before " .. bosses[st.boss].name) or "Trash after the last boss"
        if st.merged then
          -- A shared path done in another order: one section for the whole group.
          local names = {}
          for _, b in ipairs(st.bosses) do names[#names + 1] = bosses[b].name end
          head = "Trash before " .. table.concat(names, " and ")
        end
        L:Header(head)
        self:WalkLust(L, key, st)
        for _, q in ipairs(reqs) do self:WalkReq(L, q, explainOn) end
      end
    else
      local i, boss = st.boss, bosses[st.boss]
      local k = "boss:" .. key .. ":" .. i
      local open = self:IsOpen(k, true)
      local lines, edited, changed = BC:Lines(key, i)
      L:Space(2)
      L:Add((open and "- " or "+ ") .. HEX.accent .. (st.pos or i) .. ". " .. boss.name:upper() .. "|r"
        .. (edited and (HEX.muted .. "  (edited)|r") or "") .. (changed and (HEX.warn .. "  default updated|r") or ""), {
        size = 12, gap = 2, onClick = function() UI:SetOpen(k, not open) end,
        tooltip = open and "Click to fold" or "Click to show this boss" })
      self:RenderOrderMoves(L, key, i)
      if open then
        self:WalkLust(L, key, st)
        for _, l in ipairs(lines) do
          if role == "ALL" or l.role == role or l.role == "ALL" then
            L:Add((tags[l.role] or l.role) .. "  " .. BC:Decorate(key, l.text) .. (l.nv and (HEX.warn .. " [unconfirmed]|r") or ""),
              { indent = 10, size = 11, gap = 1 })
          end
        end
        for _, q in ipairs(reqs) do self:WalkReq(L, q, explainOn) end
        L:Add(HEX.accent .. "> Edit card|r", { indent = 10, size = 10, gap = 1,
          onClick = function() UI:OpenBossEditor(key, i) end, tooltip = "Change this card. Reset to default any time." })
        L:Add(HEX.accent .. "> Post to chat|r", { indent = 10, size = 10, gap = 1,
          onClick = function() UI:SendLines(BC:ChatLines(key, i), "Boss card") end,
          tooltip = "Sends:\n" .. table.concat(BC:ChatLines(key, i), "\n") })
        L:Add(HEX.accent .. "> Open in the boss window|r", { indent = 10, size = 10, gap = 4,
          onClick = function() ns.BossWindow.view = { dk = key, index = i }; ns.BossWindow:Show() end })
      end
    end
  end
end

function UI:RefreshPrimer()
  local pp = self.pp
  local key, autoWhy = self:PrimerResolve()
  pp.dungeonBtn.text:SetText(self:DungeonLabel(key))
  local level = ns.Affixes and ns.Affixes:KeyLevel(key)
  local prof = Analysis:DungeonProfile(key, ns.db.settings, level)
  local explainOn = ns.db.settings.explain ~= false
  local role = ns.db.settings.walkRole or "ALL"
  for k, b in pairs(pp.roleBtns) do b:SetActive(k == role) end
  pp.note:SetText(autoWhy and ("Auto (" .. autoWhy .. "). No group needed.") or "In the guides' order. No group needed.")
  pp.walkTitle:SetText("Walkthrough" .. (role ~= "ALL" and (": " .. (role == "HEAL" and "healer" or role:lower())) or ""))

  local L = pp.asks
  L:Clear()
  L:Add(HEX.muted .. DD:FreshnessText() .. "|r  " .. HEX.accent .. "Sources|r", { size = 10, gap = 4,
    onClick = function() UI:ShowSources() end, tooltip = "The guides this data comes from" })
  self:RenderAffixLine(L, { key = key }, false)
  self:RenderWalkthrough(L, key, explainOn)
  L:Finish()

  local V = pp.value
  V:Clear()
  V:Add(HEX.muted .. "How much of this dungeon each class answers on its own (best spec shown). In a real group, overlap matters: check Composition.|r",
    { size = 10, gap = 4 })
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    local list = prof.roles[role]
    V:Header(ROLE_PLURAL[role])
    local rkey = "primer:" .. role
    local showAll = self:IsOpen(rkey, false)
    local n = showAll and #list or math.min(PRIMER_TOP, #list)
    for i = 1, n do
      local c = list[i]
      local _, _, _, hex = Util.ClassColor(c.classFile)
      local _, icon = ns.API.GetSpecInfoByID(c.specID)
      local specs = {}
      for _, id in ipairs(c.specs) do specs[#specs + 1] = UD:SpecName(id) end
      V:Add(HEX.muted .. i .. ".|r " .. (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. hex .. UD:ClassName(c.classFile) .. "|r"
        .. HEX.muted .. "  " .. table.concat(specs, " / ") .. "|r", { indent = 4, size = 12, gap = 1 })
      local cov = {}
      for _, cv in ipairs(c.covers) do cov[#cov + 1] = (cv.key and UD:CapShort(cv.key) or cv.label) .. " x" .. cv.n end
      V:Add(HEX.muted .. "answers: |r" .. (#cov > 0 and table.concat(cov, ", ") or "nothing on the list"), { indent = 22, size = 10, gap = 3 })
    end
    self:MoreLine(V, rkey, #list - n, 4, "classes")
  end
  -- Key needs sheet underneath (no group, so no assignments).
  self:RenderCheatSheet(V, key, nil, false)
  V:Finish()
end

---------------------------------------------------------------------------
-- History: runs you've done (left) and what they say about your gaps (right).
---------------------------------------------------------------------------
local RESULT_TAG = {
  timed     = TEX_OK .. " " .. HEX.good .. "TIMED|r",
  overtime  = TEX_NO .. " " .. HEX.bad .. "OVER TIME|r",
  abandoned = TEX_WAIT .. " " .. HEX.muted .. "ABANDONED|r",
}

local function Clock(sec)
  if not sec then return "?" end
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function Pct(x) return x and string.format("%d%%", math.floor(x * 100 + 0.5)) or "-" end

-- History draws the newest runs a page at a time (up to 500 are kept, 6-7 lines each);
-- "Show N more" adds the next page, so nothing stored is out of reach (1.5.0, C2).
UI.HISTORY_PAGE = 50

function UI:BuildHistoryPage()
  local page = PageFrame(self.frame)
  self.pages.history = page
  local hp = { filter = nil, shown = UI.HISTORY_PAGE }
  self.hp = hp

  local bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT", 12, -10); bar:SetPoint("TOPRIGHT", -12, -10); bar:SetHeight(30)
  local lbl = Text(bar, 12, C.muted); lbl:SetPoint("LEFT", 0, 0); lbl:SetText("Show:")
  hp.filterBtn = Dropdown(bar, 240, 28, function(btn)
    local items = { { text = "All dungeons", selected = hp.filter == nil,
      onClick = function() hp.filter = nil; hp.shown = UI.HISTORY_PAGE; UI:QueueRefresh() end } }
    for _, key in ipairs(DD.order) do
      table.insert(items, { text = DD.list[key].name, icon = UI:DungeonIcon(key), selected = hp.filter == key,
        onClick = function() hp.filter = key; hp.shown = UI.HISTORY_PAGE; UI:QueueRefresh() end })
    end
    UI:ShowMenu(btn, items)
  end)
  hp.filterBtn:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
  hp.record = Check(bar, "Record my keys", function() return ns.db.settings.history ~= false end,
    function(v) ns.db.settings.history = v end)
  hp.record:SetSize(140, 20)
  hp.record:SetPoint("LEFT", hp.filterBtn, "RIGHT", 16, 0)
  hp.clear = Button(bar, "Clear history", 120, 24)
  hp.clear:SetPoint("RIGHT", 0, 0)
  hp.clear:SetScript("OnClick", function(btn)
    if btn.armed then
      btn.armed = nil; btn.text:SetText("Clear history"); ns.History:Clear()
    else
      btn.armed = true; btn.text:SetText("Click again")
      C_Timer.After(4, function() if btn.armed then btn.armed = nil; btn.text:SetText("Clear history") end end)
    end
  end)

  local top, colH = -48, H - 41 - 48 - 12
  local left = Panel(page)
  left:SetPoint("TOPLEFT", 12, top); left:SetPoint("BOTTOMLEFT", 12, 12); left:SetWidth(520)
  local lt = AccentText(left); lt:SetPoint("TOPLEFT", 10, -8); lt:SetText("Runs")
  hp.runs = LineList(left, 508, colH - 34):Fill(6, -28, -6, 6)

  local right = Panel(page)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0); right:SetPoint("BOTTOMRIGHT", -12, 12)
  local rt = AccentText(right); rt:SetPoint("TOPLEFT", 10, -8); rt:SetText("What your history says")
  hp.insights = LineList(right, W - 24 - 520 - 10 - 12, colH - 34):Fill(6, -28, -6, 6)
end

function UI:RefreshHistory()
  local hp = self.hp
  hp.filterBtn.text:SetText(hp.filter and self:DungeonLabel(hp.filter) or "All dungeons")
  hp.record:Sync()
  local runs = ns.History:Runs(hp.filter)
  local L = hp.runs
  L:Clear()
  if #runs == 0 then
    L:Add(HEX.muted .. (ns.db.settings.history == false and "Recording is off. Tick \"Record my keys\" to start."
      or "No keys recorded yet. Every Mythic+ key you start is saved here when it ends (timed, over time or abandoned).") .. "|r",
      { size = 12 })
  end
  -- Lessons look for the same gap in your other over-time keys there: one count for all of them.
  local repeatIndex = ns.History:RepeatIndex(ns.db.history)
  local bestIndex = ns.History:BestIndex(ns.db.history)
  local shown = math.min(#runs, hp.shown or UI.HISTORY_PAGE)
  for ri = 1, shown do
    local run = runs[ri]
    local d = run.key and DD.list[run.key]
    local name = d and self:DungeonLabel(run.key, 16) or ("Unknown dungeon (map " .. tostring(run.mapID) .. ")")
    local upgrade = (run.result == "timed" and run.upgrade and run.upgrade > 0) and (" " .. HEX.good .. "+" .. run.upgrade .. "|r") or ""
    L:Add(name .. "  " .. HEX.text .. "+" .. tostring(run.level or "?") .. "|r   " .. RESULT_TAG[run.result or "abandoned"] .. upgrade,
      { size = 12, gap = 1 })
    local bits = {}
    if run.time then bits[#bits + 1] = Clock(run.time) .. (run.timeLimit and (" / " .. Clock(run.timeLimit)) or "") end
    if run.deaths then bits[#bits + 1] = run.deaths .. " death" .. (run.deaths == 1 and "" or "s") end
    bits[#bits + 1] = date and date("%b %d, %H:%M", run.started or 0) or ""
    L:Add(HEX.muted .. table.concat(bits, "   ") .. "|r", { indent = 22, size = 11, gap = 1 })
    -- Boss splits (1.5.0): kill time on the key's timer, deaths in that stretch, and the
    -- difference from your best timed run here.
    if (run.splits and #run.splits > 0) or (run.wipes and #run.wipes > 0) then
      local best = run.splits and ns.History:BestTimed(run.key, run, bestIndex)
      local parts = {}
      local killed = {}
      for _, row in ipairs(run.splits and ns.History:SplitRows(run, best) or {}) do
        local p = (row.final and "finish " or (row.name .. " ")) .. (row.t and ns.History.Clock(row.t) or "?")
        if row.approx then p = p .. "*" end
        if row.delta then
          p = p .. " " .. (row.delta > 0 and HEX.warn or HEX.good) .. (row.delta > 0 and "+" or "") .. ns.History.Clock(row.delta) .. "|r"
        end
        if row.deaths and row.deaths > 0 then p = p .. HEX.muted .. " (" .. row.deaths .. " death" .. (row.deaths == 1 and "" or "s") .. ")|r" end
        -- Wipes on this boss before the kill (1.5.1).
        local wt = row.enc and ns.History:WipeText(run, row.enc)
        if wt then p = p .. HEX.warn .. " " .. wt .. "|r" end
        if row.enc then killed[row.enc] = true end
        parts[#parts + 1] = p
      end
      -- A boss wiped on but never killed (an abandoned or over-time key).
      for _, w in ipairs(run.wipes or {}) do
        if not killed[w.enc] then
          parts[#parts + 1] = ns.History:BossName(run, w) .. " " .. HEX.warn .. ns.History:WipeText(run, w.enc) .. "|r"
        end
      end
      local tip = { "Boss kills on the key's timer, with the deaths in each stretch.",
        "\"wiped 2x, best 12%\": failed pulls of that boss and the lowest health it reached." }
      if best then tip[#tip + 1] = "Colored: the difference from your best timed run here (+" .. tostring(best.level or "?") .. ", " .. Clock(best.time) .. ")." end
      for _, sp in ipairs(run.splits) do
        if sp.approx then tip[#tip + 1] = "*: seen after a reload or loading screen, so the time is when it was seen, not the kill."; break end
      end
      L:Add(HEX.muted .. "Bosses: |r" .. table.concat(parts, HEX.muted .. "  ·  |r"),
        { indent = 22, size = 11, gap = 1, tooltip = table.concat(tip, "\n") })
    end
    -- Group: spec icons + names.
    local icons = {}
    for _, m in ipairs(run.comp or {}) do
      local _, icon = ns.API.GetSpecInfoByID(m.specID)
      local _, _, _, hex = Util.ClassColor(m.classFile)
      icons[#icons + 1] = (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. hex .. tostring(m.name or "?") .. "|r"
    end
    if #icons > 0 then L:Add(table.concat(icons, "  "), { indent = 22, size = 11, gap = 1 }) end
    -- Affixes.
    if run.affixes and #run.affixes > 0 and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
      local names = {}
      for _, id in ipairs(run.affixes) do
        local ok, n = pcall(C_ChallengeMode.GetAffixInfo, id)
        local def = ns.Affixes.Match(id, ok and n or nil)
        names[#names + 1] = (def and def.label) or (ok and n) or tostring(id)
      end
      L:Add(HEX.muted .. "Affixes: " .. table.concat(names, ", ") .. "|r", { indent = 22, size = 10, gap = 1 })
    end
    local gaps = {}
    for _, g in ipairs(run.gaps or {}) do gaps[#gaps + 1] = (g.status == "missing" and HEX.bad or HEX.warn) .. g.title .. "|r" end
    L:Add((#gaps > 0 and (HEX.muted .. "Gaps: |r" .. table.concat(gaps, HEX.muted .. ", |r")) or (HEX.muted .. "No gaps.|r")),
      { indent = 22, size = 11, gap = 2 })
    local lesson, tone = ns.History:Lesson(run, ns.db.history, repeatIndex, bestIndex)
    if lesson then
      local col = tone == "good" and HEX.good or tone == "warn" and HEX.warn or HEX.muted
      L:Add(col .. "Lesson: " .. lesson .. "|r", { indent = 22, size = 11, gap = 2 })
    end
    L:Space(6)
  end
  if #runs > shown then
    local more = math.min(UI.HISTORY_PAGE, #runs - shown)
    L:Add(HEX.accent .. "> Show " .. more .. " more|r" .. HEX.muted .. "  (" .. (#runs - shown) .. " older not shown)|r",
      { size = 12, gap = 2, onClick = function() hp.shown = shown + UI.HISTORY_PAGE; UI:QueueRefresh() end })
  end
  L:Finish()

  -- Insights.
  local I = hp.insights
  I:Clear()
  local s = ns.History:Insights(runs)
  I:Add(string.format("%d key%s recorded: %d timed, %d over time, %d abandoned", s.total, s.total == 1 and "" or "s",
    s.timed, s.finished - s.timed, s.abandoned), { size = 12, gap = 2 })
  if s.rate then I:Add(HEX.muted .. "Timed " .. Pct(s.rate) .. " of finished keys.|r", { size = 11, gap = 4 }) end

  I:Header("Gaps and your timed rate")
  if #s.gaps > 0 then I:Add(HEX.muted .. "Timed rate in keys where the group lacked each item vs. keys where it was covered.|r", { size = 10, gap = 3 }) end
  if #s.gaps == 0 then
    I:Add(HEX.muted .. string.format("Needs at least %d finished keys with a gap and %d without it before comparing.|r",
      ns.History.MIN_SAMPLE, ns.History.MIN_SAMPLE), { size = 11 })
  end
  for _, g in ipairs(s.gaps) do
    local col = g.delta >= 0.15 and HEX.bad or g.delta > 0 and HEX.warn or HEX.good
    I:Add(col .. g.title .. "|r", { indent = 4, size = 12, gap = 1 })
    I:Add(HEX.muted .. string.format("when missing: %s timed (%d/%d)   when covered: %s (%d/%d)", Pct(g.rateWith), g.withTimed, g.withN,
      Pct(g.rateWithout), g.withoutTimed, g.withoutN) .. "|r", { indent = 16, size = 11, gap = 4 })
  end
  if #s.gaps > 0 then
    I:Add(HEX.muted .. "Correlation from your own keys, not proof: small samples swing a lot.|r", { size = 10, gap = 4 })
  end

  if not hp.filter then
    I:Header("By dungeon")
    for _, d in ipairs(s.dungeons) do
      local label = DD.list[d.key] and self:DungeonLabel(d.key, 14) or tostring(d.key)
      I:Add(label .. HEX.muted .. string.format("   %d run%s, %s timed, avg +%.1f", d.n, d.n == 1 and "" or "s", Pct(d.rate), d.avgLevel) .. "|r",
        { indent = 4, size = 11, gap = 2 })
    end
  end
  I:Finish()
end

---------------------------------------------------------------------------
-- Settings: one window with a section list on the left.
--   General · What to check · Group Finder · Fill group · Saved players · Party chat · Boss cards ·
--   Appearance · Data
-- Every option has hover help; each section has its own Reset. UI:OpenSettings(key) jumps
-- straight to a section (used by the gear buttons next to the features they affect).
---------------------------------------------------------------------------
UI.SETTINGS_SECTIONS = {
  { key = "general",    label = "General" },
  { key = "checks",     label = "What to check" },
  { key = "finder",     label = "Group Finder" },
  { key = "fill",       label = "Fill group" },
  { key = "players",    label = "Saved players" },
  { key = "chat",       label = "Party chat" },
  { key = "bosses",     label = "Boss cards" },
  { key = "appearance", label = "Appearance" },
  { key = "data",       label = "Data" },
}

-- Settings each section's Reset puts back to their defaults.
UI.SECTION_KEYS = {
  general = { "compact", "explain", "liveAutoDungeon", "autoOpenOnListing", "minimap", "compMode" },
  checks = { "ignoredNeeds", "hideLowSeverity", "countTalentSources", "checks", "dungeonCategories" },
  finder = { "applicantPanel", "finderPanel", "compApplicants", "finderTooltip", "applicantView", "listingMarker",
             "listingHidePoor", "listingTooltip", "applyLine", "pastKeys" },
  fill = { "fill" },
  players = {},   -- Saved players is your list, not settings: no section reset (remove players one by one)
  chat = { "chatStyle" },
  bosses = { "bossWindow" },
  appearance = { "theme", "textSize" },
  data = { "history" },
}

-- Presets: a starting point; every setting stays adjustable afterwards.
UI.PRESETS_SETTINGS = {
  learning = { label = "Learning", explain = true, compact = false, chatStyle = "full", hidePoor = false,
               tip = "Explanations on, every need shown, full chat posts, every applicant listed." },
  expert = { label = "Expert", explain = false, compact = true, chatStyle = "short", hidePoor = true,
             tip = "No teaching text, problems only, one-line chat posts, Poor applicants hidden." },
}

function UI:ApplySettingsPreset(key)
  local p = self.PRESETS_SETTINGS[key]
  if not p then return end
  local s = ns.db.settings
  s.explain, s.compact, s.chatStyle = p.explain, p.compact, p.chatStyle
  s.applicantView = s.applicantView or {}
  s.applicantView.hidePoor = p.hidePoor
  ns:Fire("SETTINGS_CHANGED")
  self:RefreshSettings()
end

function UI:CurrentSettingsPreset()
  local s = ns.db.settings
  for key, p in pairs(self.PRESETS_SETTINGS) do
    if (s.explain ~= false) == p.explain and (s.compact and true or false) == p.compact
       and (s.chatStyle or "full") == p.chatStyle and ((s.applicantView or {}).hidePoor and true or false) == p.hidePoor then
      return key
    end
  end
  return nil
end

function UI:ResetSettingsSection(key)
  local s, d = ns.db.settings, ns.DEFAULTS.settings
  for _, k in ipairs(self.SECTION_KEYS[key] or {}) do
    local v = d[k]
    s[k] = (type(v) == "table") and Util.DeepCopy(v) or v
  end
  if key == "appearance" then self:ApplyTheme(); self:SetTextSize(s.textSize or 100) end
  ns:Fire("SETTINGS_CHANGED")
  self:RefreshSettings()
end

function UI:OpenSettings(key)
  self:Show("settings")
  self:ShowSettingsSection(key or self.settingsSection or "general")
end

function UI:ShowSettingsSection(key)
  if not self.settingsFrames then return end
  if not self.settingsFrames[key] then key = "general" end
  self.settingsSection = key
  for k, f in pairs(self.settingsFrames) do f:SetShown(k == key) end
  for k, b in pairs(self.settingsNav) do
    b.active = (k == key)
    b:SetBackdropColor(unpack(k == key and C.btnHot or C.btn))
    b.mark:SetShown(k == key)
  end
  self:RefreshSettings()
end

-- Small gear button that opens one settings section (placed next to a feature).
function UI:GearButton(parent, section, tip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  local t = b:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", function() UI:OpenSettings(section) end)
  b:SetScript("OnEnter", function(self)
    if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip or "Settings", 1, 1, 1); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return b
end

function UI:BuildSettingsPage()
  local outer = PageFrame(self.frame)
  self.pages.settings = outer
  self.checks, self.settingsSliders = {}, {}
  self.settingsFrames, self.settingsNav = {}, {}

  -- Section list
  local nav = CreateFrame("Frame", nil, outer)
  nav:SetPoint("TOPLEFT", 12, -12); nav:SetPoint("BOTTOMLEFT", 12, 12); nav:SetWidth(150)
  for i, sec in ipairs(self.SETTINGS_SECTIONS) do
    local b = Button(nav, sec.label, 150, 28, function() UI:ShowSettingsSection(sec.key) end)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
    b.text:SetJustifyH("LEFT"); b.text:SetPoint("LEFT", 14, 0)
    b.mark = b:CreateTexture(nil, "OVERLAY"); b.mark:SetPoint("TOPLEFT", 1, -1); b.mark:SetPoint("BOTTOMLEFT", 1, 1); b.mark:SetWidth(3)
    Accent(b.mark, "tex"); b.mark:Hide()
    b:SetScript("OnLeave", function(self)
      if not self.active then self:SetBackdropColor(unpack(C.btn)) end
      if GameTooltip then GameTooltip:Hide() end
    end)
    self.settingsNav[sec.key] = b
  end
  local about = Text(nav, 10, C.muted); about:SetPoint("BOTTOMLEFT", 2, 2); about:SetWidth(148)
  about:SetText("Ensemble " .. tostring(ns.VERSION) .. "\n/ens help")

  -- Content area
  for _, sec in ipairs(self.SETTINGS_SECTIONS) do
    local f = CreateFrame("Frame", nil, outer)
    f:SetPoint("TOPLEFT", 176, 0); f:SetPoint("BOTTOMRIGHT", 0, 0); f:Hide()
    self.settingsFrames[sec.key] = f
    local title = AccentText(f); title:SetPoint("TOPLEFT", 8, -16); title:SetText(sec.label)
    local reset = FlatButton(f, "Reset section", 100, 20, function() UI:ResetSettingsSection(sec.key) end)
    reset:SetPoint("TOPRIGHT", -16, -12)
    reset.tooltip = "Put this section's settings back to their defaults"
    f.reset = reset
    local builder = self["BuildSettings_" .. sec.key]
    if builder then builder(self, f) end
  end
  self:ShowSettingsSection(self.settingsSection or "general")
end

-- Helpers shared by the section builders.
local function S() return ns.db.settings end
local function AddCheck(self, parent, x, y, label, getter, setter, tip)
  local c = Check(parent, label, getter, setter, tip)
  c:SetPoint("TOPLEFT", x, y)
  table.insert(self.checks, c)
  return c
end
local function AddRadio(self, parent, x, y, label, field, value, tip)
  return AddCheck(self, parent, x, y, label, function() return S()[field] == value end,
    function() S()[field] = value; C_Timer.After(0, function() UI:RefreshSettings() end) end, tip)
end
local function SubHead(parent, x, y, text)
  local t = Text(parent, 12, C.text); t:SetPoint("TOPLEFT", x, y); t:SetText(text)
  return t
end
local function Note(parent, x, y, w, text)
  local t = Text(parent, 11, C.muted); t:SetPoint("TOPLEFT", x, y); t:SetWidth(w); t:SetText(text)
  return t
end

function UI:BuildSettings_general(f)
  SubHead(f, 8, -44, "Presets")
  -- Buttons hang below the note, so it can never run into them (larger text sizes wrap).
  local intro = Note(f, 8, -62, 520, "A one-click starting point. You can still change anything afterward.")
  local prev
  for _, key in ipairs({ "learning", "expert" }) do
    local p = self.PRESETS_SETTINGS[key]
    local b = Button(f, p.label, 110, 24, function() UI:ApplySettingsPreset(key) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -8) end
    b.tooltip = p.tip
    prev = b
  end
  self.presetNote = Text(f, 11, C.muted); self.presetNote:SetPoint("LEFT", prev, "RIGHT", 12, 0); self.presetNote:SetWidth(280)

  SubHead(f, 8, -128, "Window and behavior")
  local y = -150
  local function row(label, g, st, tip) AddCheck(self, f, 8, y, label, g, st, tip); y = y - 26 end
  row("Summary view (problems only)", function() return S().compact end, function(v) S().compact = v end,
    "Show only the gaps (with all their detail). You can switch back with the button on the Composition tab.")
  row("Show explanations (learning mode)", function() return S().explain ~= false end, function(v) S().explain = v end,
    "Plain-language explanations of each need and what to do about each dungeon mechanic. Off hides only the teaching text, never data.")
  row("Pick the dungeon automatically", function() return S().liveAutoDungeon end, function(v) S().liveAutoDungeon = v end,
    "Use your keystone's dungeon in the planner, and your listing or current dungeon for your party and Applicants.")
  row("Open Applicants when you list a group", function() return S().autoOpenOnListing ~= false end,
    function(v) S().autoOpenOnListing = v end, "Switch to the Applicants tab when you create a listing for a Season dungeon (never in combat).")
  row("Show minimap button", function() return not S().minimap.hide end, function(v) S().minimap.hide = not v end,
    "The logo button by the minimap: left-click opens the window, right-click opens settings. The Addon Compartment entry always stays.")
  SubHead(f, 8, y - 6, "Composition and Plan show")
  y = y - 28
  for _, def in ipairs({
    { "auto", "Automatic: my party when I'm grouped or listed, else the planner" },
    { "planner", "Always the planner" },
    { "party", "Always my party" },
  }) do
    AddRadio(self, f, 8, y, def[2], "compMode", def[1], "Also in the mode menu on the Composition and Plan tabs.")
    y = y - 24
  end
  local nb = Note(f, 8, y - 8, 520, "These settings can also be opened from Blizzard's Options > AddOns.")
  local tour = Button(f, "Take the tour", 130, 24, function() if ns.Tour then ns.Tour:Start() end end)
  tour:SetPoint("TOPLEFT", nb, "BOTTOMLEFT", 0, -10)
  tour.tooltip = "A seven-step look at the window"
end

-- What to check: every need, grouped like the Readiness panel. A group's switch turns all
-- of its needs on or off; each need has its own switch. Replaces the old generic-check,
-- requirement-category and needs lists (merged, same power).
function UI:BuildSettings_checks(f)
  Note(f, 8, -40, 560, "Untick anything you don't care about. It's left out of every check, rating and plan.")
  local function ignored() S().ignoredNeeds = S().ignoredNeeds or {}; return S().ignoredNeeds end
  local cols = { { x = 8, y = -64 }, { x = 290, y = -64 } }
  local ci = 1
  for _, g in ipairs(Analysis.READY_GROUPS) do
    local c = cols[ci]
    local caps = g.caps
    local head = AddCheck(self, f, c.x, c.y, HEX.accent .. g.label .. "|r",
      function() for _, cap in ipairs(caps) do if ignored()[cap] then return false end end return true end,
      function(v) for _, cap in ipairs(caps) do ignored()[cap] = (not v) or nil end
        C_Timer.After(0, function() UI:RefreshSettings() end) end,
      "Turn every need in this group on or off.")
    head:SetWidth(260)
    c.y = c.y - 22
    for _, cap in ipairs(caps) do
      local tip = UD:CapExplain(cap)
      local chk = AddCheck(self, f, c.x + 18, c.y, UD:CapLabel(cap), function() return not ignored()[cap] end,
        function(v) ignored()[cap] = (not v) or nil; C_Timer.After(0, function() UI:RefreshSettings() end) end, tip)
      chk:SetWidth(240)
      c.y = c.y - 22
    end
    c.y = c.y - 8
    if ci == 1 and c.y < -260 then ci = 2 end
  end
  -- Extras
  local c = cols[2]
  c.y = c.y - 4
  SubHead(f, c.x, c.y, "Also")
  c.y = c.y - 22
  local function extra(label, g, st, tip) AddCheck(self, f, c.x, c.y, label, g, st, tip):SetWidth(280); c.y = c.y - 22 end
  extra("Raid buffs & synergy", function() return S().checks.buffs ~= false end, function(v) S().checks.buffs = v end,
    "List the raid buffs your group brings and how well each suits it; adds a small synergy bonus to suggestions and ratings.")
  extra("This week's affixes", function() return S().dungeonCategories.affixes ~= false end,
    function(v) S().dungeonCategories.affixes = v end, "Add what this week's affixes ask for, at your key's level.")
  extra("Tank-buster requirements", function() return S().dungeonCategories.tank ~= false end,
    function(v) S().dungeonCategories.tank = v end, "Count the dungeon's tank busters (external defensives for the tank).")
  extra("Hide low-severity requirements", function() return S().hideLowSeverity end, function(v) S().hideLowSeverity = v end,
    "Leave out dungeon requirements marked low severity.")
  extra("Count optional talents", function() return S().countTalentSources ~= false end,
    function(v) S().countTalentSources = v end,
    "Count abilities that need an optional talent (marked 'talent'). Core talents every build takes always count.")
end

function UI:BuildSettings_finder(f)
  local x1, x2 = 8, 320   -- 320: room for the left column's longest label at 125% text (issue #16)
  SubHead(f, x1, -44, "Your listing's applicants")
  local y = -66
  AddCheck(self, f, x1, y, "Applicant panel by the Group Finder", function() return S().applicantPanel ~= false end,
    function(v) S().applicantPanel = v; UI:UpdateFinderPanel() end, "A compact list of your applicants with their fit ratings, beside Blizzard's Group Finder while you host."); y = y - 26
  AddCheck(self, f, x1, y, "Keep the panel docked", function() return S().finderPanel.docked ~= false end,
    function(v) if v then UI:DockFinderPanel() else S().finderPanel.docked = false; UI:PositionFinderPanel() end end,
    "Docked panels follow the Group Finder window; undocked ones stay wherever you drag them."); y = y - 26
  AddCheck(self, f, x1, y, "Applicants on the Composition tab", function() return S().compApplicants ~= "list" end,
    function(v) S().compApplicants = v and "panel" or "list" end,
    "While you host: your best-fit applicants under the party slots, with Invite and a preview in your group. Off keeps the usual left column."); y = y - 26
  AddCheck(self, f, x1, y, "Fit ratings in applicant tooltips", function() return S().finderTooltip ~= false end,
    function(v) S().finderTooltip = v end, "Add each applicant's fit rating to Blizzard's own tooltip when you hover them."); y = y - 26
  AddCheck(self, f, x1, y, "Hide Poor applicants", function() return (S().applicantView or {}).hidePoor end,
    function(v) S().applicantView = S().applicantView or {}; S().applicantView.hidePoor = v end,
    "On the Applicants tab, hide applicants rated Poor (no open slot for their role, or very little fit)."); y = y - 26

  -- Past keys together (1.5.0): how your recorded keys with an applicant went.
  y = y - 10
  SubHead(f, x1, y, "Past keys together"); y = y - 24
  local fl = Text(f, 12, C.text); fl:SetPoint("TOPLEFT", x1, y - 3); fl:SetText("A failed key:")
  local fm = Button(f, "", 200, 20, function(btn)
    local items = {}
    for _, k in ipairs(ns.History.FAILED_MODES) do
      items[#items + 1] = { text = ns.History.FAILED_LABEL[k], selected = ns.History:FailedMode() == k,
        onClick = function() S().pastKeys.failed = k; ns:Fire("SETTINGS_CHANGED"); ns:Fire("FILL_SETTINGS_CHANGED"); UI:RefreshSettings() end }
    end
    UI:ShowMenu(btn, items)
  end)
  SetFontSize(fm.text, 11)
  fm:SetPoint("LEFT", fl, "RIGHT", 8, 0)
  fm.tooltip = "Which keys with a player count as failed. Someone counts as \"failed with\" when you have more failed keys with them than timed ones."
  self.pastFailedBtn = fm
  y = y - 28
  AddCheck(self, f, x1, y, "Show past keys in pick ratings", function() return S().pastKeys.rating == true end,
    function(v) S().pastKeys.rating = v; ns:Fire("SETTINGS_CHANGED") end,
    "Adds a \"Past keys\" step to Why N?: the same points Fill group uses (5 at Relaxed, 3 at Standard, a tiebreak at Strict) for players you've timed with, taken off for players you've failed with. A full closer of a critical need still never rates below anyone who doesn't."):SetWidth(300)
  y = y - 24
  Note(f, x1, y, 300, "From your own History (keys recorded from 1.5.0 on). It can't tell who left a key or why it was abandoned.")

  SubHead(f, x2, -44, "Groups you could join")
  local yy = -66
  AddCheck(self, f, x2, yy, "Colored edge stripe on listings", function() return S().listingMarker ~= "off" end,
    function(v) S().listingMarker = v and "stripe" or "off" end,
    "A bar on each Mythic+ listing's left edge plus a faint tint showing your pick rating for that group (how strong an applicant you'd be for its open slot): solid for Great/Good, dashed for Fair, dotted for Poor."); yy = yy - 24
  AddCheck(self, f, x2, yy, "No marker on Poor fits", function() return S().listingHidePoor end,
    function(v) S().listingHidePoor = v end, "Leave groups that are a Poor fit for you unmarked."); yy = yy - 24
  AddCheck(self, f, x2, yy, "Your fit in listing tooltips", function() return S().listingTooltip ~= false end,
    function(v) S().listingTooltip = v end, "Hovering a listing adds what you'd add, what's uncertain and how the group looks after you join."); yy = yy - 24
  AddCheck(self, f, x2, yy, "A line for your Sign Up note", function() return S().applyLine ~= false end,
    function(v) S().applyLine = v end, "When you sign up, a short line under the dialog says your spec, rating, best run in that dungeon and what you'd bring. Copy it into the note yourself."); yy = yy - 32

end

-- Saved players (1.5.0): people you play with. Picked when you reserve a slot or fill a
-- planner slot. Click a row to change their specs or remove them.
function UI:BuildSettings_players(f)
  f.reset:Hide()
  SubHead(f, 8, -44, "People you play with")
  local note = Note(f, 8, -62, 600, "Pick them when you reserve a slot (Fill group) or fill a planner slot (Composition). Kept on this computer for all your characters. Names never appear in /ens verify, /ens report, party posts or share strings.")
  local add = Button(f, "+ Add a player", 124, 22, function() UI:OpenReserveDialog("save") end)
  add:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
  add.tooltip = "A name (Name-Realm) and the spec they play; add more specs afterward"
  local box = CreateFrame("Frame", nil, f)
  box:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -10); box:SetPoint("BOTTOMRIGHT", -16, 12)
  self.savedList = LineList(box, 600, 300):Fill(0, 0, 0, 0)
end

function UI:RefreshSavedPlayers()
  local L = self.savedList
  if not L then return end
  local P = ns.Players
  L:Clear()
  local list = P:List()
  if #list == 0 then
    L:Add(HEX.muted .. "No saved players yet. Add one here, or tick \"Save this player\" when you reserve a slot.|r", { size = 12 })
  end
  for _, p in ipairs(list) do
    local name, realm = p.full:match("^([^%-]+)%-?(.*)$")
    local def = UD:GetSpec(p.default)
    local hex = def and select(4, Util.ClassColor(def.class)) or HEX.text
    L:Add(hex .. tostring(name) .. "|r" .. HEX.muted .. (realm ~= "" and ("-" .. realm) or "") .. "|r", { size = 13, gap = 1,
      onClick = function(btn) UI:OpenSavedPlayerMenu(btn, p.full) end, tooltip = "Click to change their specs or remove them" })
    L:Add(HEX.muted .. P:SpecsText(p) .. "|r", { size = 11, gap = 6, indent = 16 })
  end
  L:Finish()
end

function UI:OpenSavedPlayerMenu(anchor, full)
  local P = ns.Players
  local p = P:Find(full)
  if not p then return end
  local items = { { text = full, header = true } }
  for _, id in ipairs(p.specs) do
    local s = UD:GetSpec(id)
    if s then
      items[#items + 1] = { text = "Default: " .. UD:SpecName(id) .. " " .. UD:ClassName(s.class), specID = id, classFile = s.class,
        selected = p.default == id, onClick = function() P:SetDefault(full, id) end }
    end
  end
  items[#items + 1] = { text = "Add a spec...", onClick = function()
    local add = { { text = "Add a spec for " .. (full:match("^([^%-]+)") or full), header = true } }
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
      for _, id in ipairs(UD:SpecsForRole(role)) do
        if not P:HasSpec(p, id) then
          local s = UD:GetSpec(id)
          add[#add + 1] = { text = UD:SpecName(id) .. " " .. UD:ClassName(s.class), specID = id, classFile = s.class,
            onClick = function() P:Save(full, id) end }
        end
      end
    end
    UI:ShowMenu(anchor, add)
  end }
  if #p.specs > 1 then
    for _, id in ipairs(p.specs) do
      local s = UD:GetSpec(id)
      if s then items[#items + 1] = { text = "Remove spec: " .. UD:SpecName(id) .. " " .. UD:ClassName(s.class), onClick = function() P:RemoveSpec(full, id) end } end
    end
  end
  items[#items + 1] = { text = "Remove " .. (full:match("^([^%-]+)") or full), color = C.bad, onClick = function() P:Remove(full) end }
  self:ShowMenu(anchor, items)
end

-- Fill group: how complete the group must be, the musts for the key being run, who can be
-- invited, and Auto-fill. (Mock-ups round 2, approved October 23, 2026.)
local function FillS() return S().fill end

-- The dungeon whose musts the section shows: the one picked here, else the key the
-- Applicants tab follows (your listing, else the dungeon you're in), else your keystone.
function UI:FillMustsDungeon()
  local dk = self.fillMustsDk
  if dk and DD.list[dk] then return dk, "picked" end
  -- Named by where it came from (it said "your listing" for all three before the 1.4.1 review).
  local live, src = ns:GetEffectiveDungeon(true)
  if live and DD.list[live] then
    if src == "manual" then return live, "your pick on the Applicants tab" end
    return live, ns.state.autoSource == "zone" and "the dungeon you're in" or "your listing"
  end
  local key = ns:OwnKeystoneDungeon()
  if key and DD.list[key] then return key, "your keystone" end
  return DD.order[1], "pick one"
end

function UI:BuildSettings_fill(f)
  local x1, x2 = 8, 320
  local FG = ns.FillGroup
  -- How complete the group must be.
  SubHead(f, x1, -44, "How complete the group must be")
  Note(f, x1, -62, 300, "Each level adds to the musts below.")
  -- Each level hangs below the previous one's description, and "Always require" below the
  -- last, so a description that wraps at a larger text size pushes the rest down instead of
  -- running into it (seen at 125% in 1.4.0).
  local prev
  for _, def in ipairs({
    { "auto", "Match the key level", "Relaxed to +6, Standard +7 to +11, Strict from +12" },
    { "relaxed", "Relaxed", "Your musts, and no critical need missing" },
    { "standard", "Standard", "Also battle rez and every high need, trash included" },
    { "strict", "Strict", "Nothing medium+ missing; critical and high not thin" },
  }) do
    local c = AddCheck(self, f, x1, -84, def[2], function() return (FillS().level or "auto") == def[1] end,
      function() FillS().level = def[1]; ns:Fire("FILL_SETTINGS_CHANGED"); C_Timer.After(0, function() UI:RefreshSettings() end) end,
      def[3] .. ". Needs you untick in What to check stay out at every level.")
    c:SetWidth(290)
    if prev then c:ClearAllPoints(); c:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -22, -6) end
    local n = Note(f, x1 + 22, -102, 280, def[3])
    n:ClearAllPoints(); n:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 22, 2)
    prev = n
  end
  -- Reserved slots (1.5.0): one line, with the button that reserves or releases.
  local resBtn = FlatButton(f, "Reserve a slot", 110, 18, function(btn) UI:OpenReserveMenu(btn) end)
  resBtn:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -22, -10)
  resBtn.tooltip = "Hold an open slot for a friend who's joining: Fill group plans only the rest. Clears when they join, when the group is full or when the listing ends."
  local resText = Text(f, 11, C.muted); resText:SetPoint("LEFT", resBtn, "RIGHT", 8, 0); resText:SetWidth(176); resText:SetWordWrap(false)
  self.fillReserveBtn, self.fillReserveText = resBtn, resText
  -- Always require: the musts for one dungeon.
  local head = Text(f, 12, C.text); head:SetPoint("TOPLEFT", resBtn, "BOTTOMLEFT", 0, -10); head:SetText("Always require:")
  local pick = FlatButton(f, "", 170, 18, function(btn)
    local items = { { text = "Musts for:", header = true } }
    for _, dk in ipairs(DD.order) do
      items[#items + 1] = { text = DD.list[dk].name, selected = UI:FillMustsDungeon() == dk,
        onClick = function() UI.fillMustsDk = dk; UI:RefreshSettings() end }
    end
    UI:ShowMenu(btn, items)
  end)
  pick:SetPoint("LEFT", head, "RIGHT", 4, 0)
  pick.text:ClearAllPoints(); pick.text:SetPoint("LEFT", 4, 0); pick.text:SetJustifyH("LEFT")
  pick.tooltip = "Pick another dungeon to see or change its musts"
  self.fillMustsPick = pick
  self.fillMustsNote = Note(f, x1, -258, 300, "")
  self.fillMustsNote:ClearAllPoints(); self.fillMustsNote:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
  -- Rows are built once and relabeled for each dungeon. The box is as tall as its rows, so the
  -- buttons under it sit right after the last must; it scrolls only when the rows would push
  -- the buttons off the panel (Kings' Rest lists 8 at a large text size). UI:LayoutFillMusts.
  local box = CreateFrame("ScrollFrame", nil, f)
  box:SetPoint("TOPLEFT", self.fillMustsNote, "BOTTOMLEFT", 0, -8); box:SetWidth(300); box:SetHeight(22)
  self.fillMustsBox, self.fillPanel = box, f
  local inner = CreateFrame("Frame", nil, box); inner:SetSize(300, 1)
  box:SetScrollChild(inner)
  box:EnableMouseWheel(true)
  box:SetScript("OnMouseWheel", function(sf, d)
    local max = math.max(0, inner:GetHeight() - sf:GetHeight())
    sf:SetVerticalScroll(math.min(max, math.max(0, sf:GetVerticalScroll() - d * 22)))
  end)
  self.fillMustRows, self.fillMustHeads, self.fillMustInner = {}, {}, inner
  for i = 1, 16 do
    local row = {}
    local c = Check(inner, "", function() return row.get and row.get() end, function(v) if row.set then row.set(v) end end)
    c:SetWidth(296)
    c.label:SetPoint("RIGHT", c, "RIGHT", 0, 0); c.label:SetWordWrap(false)
    row.check = c
    self.fillMustRows[i] = row
  end
  for i = 1, 2 do
    local h = Text(inner, 10, C.muted); self.fillMustHeads[i] = h
  end
  local add = Button(f, "+ Add a need", 120, 22, function(btn)
    local dk = UI:FillMustsDungeon()
    local m = FG:Musts(dk)
    local on = {}
    for _, q in ipairs(m.reqs) do on[q.id] = true end
    local items = { { text = "Add a need (" .. DD.list[dk].name .. "):", header = true } }
    for _, q in ipairs(FG:OtherNeeds(dk)) do
      if not on[q.id] then
        items[#items + 1] = { text = UD:CapLabel(q.need) .. " - " .. FG.CastName(q), tooltip = q.source,
          onClick = function() FG:SetMust(dk, q.id, true); UI:RefreshSettings() end }
      end
    end
    if #items == 1 then items[#items + 1] = { text = "Nothing else to add", header = true } end
    UI:ShowMenu(btn, items)
  end)
  add:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
  add.tooltip = "Add one of the dungeon's other needs (trash) to its musts"
  local back = Button(f, "Reset needs", 110, 22, function() FG:ResetMusts(UI:FillMustsDungeon()); UI:RefreshSettings() end)
  back:SetPoint("LEFT", add, "RIGHT", 8, 0)
  back.tooltip = "This dungeon's musts back to its defaults: Bloodlust and the boss needs"
  self.fillMustsAdd, self.fillMustsReset = add, back
  -- Re-fit when the window or the text size changes the room under the list.
  f:HookScript("OnSizeChanged", function() UI:LayoutFillMusts() end)
  f:HookScript("OnShow", function() C_Timer.After(0, function() UI:LayoutFillMusts() end) end)

  -- Who can be invited.
  SubHead(f, x2, -44, "Who can be invited")
  local yy = -66
  self.fillFilterRows = {}
  for _, def in ipairs({ { "rating", "Minimum M+ rating", 50 }, { "ilvl", "Minimum item level", 1 } }) do
    local k, label, step = def[1], def[2], def[3]
    AddCheck(self, f, x2, yy, label, function() return FillS()[k].on ~= false end, function(v) FillS()[k].on = v; ns:Fire("FILL_SETTINGS_CHANGED") end,
      k == "rating" and "Skip applicants below this M+ rating. Suggested: what timing every dungeon two levels below the key gives (off up to +6)."
      or "Skip applicants below this item level. Suggested: what a key two levels lower drops at the end of the run, from the game (off up to +6).")
    local src = Button(f, "", 150, 20, function(btn)
      local items = {}
      for _, s in ipairs({ { "suggested", "Suggested for the key" }, { "listing", "From my listing" }, { "custom", "Custom" } }) do
        items[#items + 1] = { text = s[2], selected = FillS()[k].source == s[1],
          onClick = function() FillS()[k].source = s[1]; ns:Fire("FILL_SETTINGS_CHANGED"); UI:RefreshSettings() end }
      end
      UI:ShowMenu(btn, items)
    end)
    SetFontSize(src.text, 11)
    src:SetPoint("TOPLEFT", x2 + 22, yy - 22)
    src.tooltip = "Where the minimum comes from: suggested for the key, your listing's own minimum, or a number you set"
    -- "-" / "+" switch to Custom, stepping from the number shown: the value in force (Suggested
    -- or From my listing) when the source isn't Custom yet, else the saved number (1.4.1 review, R3).
    local function stepFrom()
      local c = FillS()[k]
      if c.source ~= "custom" then
        local fl = FG:Filters(nil, ns.ApplicantFit:GetKeyLevel((UI:FillMustsDungeon())))[k]
        if fl and fl.on and fl.value then return fl.value end
      end
      return tonumber(c.value) or 0
    end
    local minus = Button(f, "-", 22, 20, function()
      local c = FillS()[k]; local v = stepFrom(); c.source = "custom"; c.value = math.max(0, v - step); ns:Fire("FILL_SETTINGS_CHANGED"); UI:RefreshSettings()
    end)
    minus:SetPoint("LEFT", src, "RIGHT", 8, 0)
    local val = Text(f, 12, C.text, "CENTER"); val:SetPoint("LEFT", minus, "RIGHT", 2, 0); val:SetWidth(50)
    local plus = Button(f, "+", 22, 20, function()
      local c = FillS()[k]; local v = stepFrom(); c.source = "custom"; c.value = v + step; ns:Fire("FILL_SETTINGS_CHANGED"); UI:RefreshSettings()
    end)
    plus:SetPoint("LEFT", val, "RIGHT", 2, 0)
    minus.tooltip = "Lower (sets a custom number)"; plus.tooltip = "Raise (sets a custom number)"
    local note = Text(f, 10, C.muted); note:SetPoint("TOPLEFT", x2 + 22, yy - 46); note:SetWidth(420); note:SetWordWrap(false)
    self.fillFilterRows[k] = { src = src, val = val, note = note }
    yy = yy - 66
  end
  AddCheck(self, f, x2, yy, "Skip players with the leaver flag", function() return FillS().skipLeavers ~= false end,
    function(v) FillS().skipLeavers = v; ns:Fire("FILL_SETTINGS_CHANGED") end,
    "The game flags players who recently left keys early. They stay on the list, dimmed and tagged SKIPPED."):SetWidth(400); yy = yy - 24
  AddCheck(self, f, x2, yy, "Skip players the game sends no data for", function() return FillS().skipNoData ~= false end,
    function(v) FillS().skipNoData = v; ns:Fire("FILL_SETTINGS_CHANGED") end,
    "With a minimum on, an applicant without a rating or item level from the game is skipped. Off lets them through that filter."):SetWidth(400); yy = yy - 24
  -- One player per class in each role (1.5.1, on by default).
  AddCheck(self, f, x2, yy, "One player per class in each role", function() return FillS().oneClassPerRole ~= false end,
    function(v) FillS().oneClassPerRole = v; ns:Fire("FILL_SETTINGS_CHANGED") end,
    "Fill group never plans two players of one class in the same role, counting your party and reserved slots: Restoration and Elemental Shaman together is fine; two Shaman DPS aren't. Premades that repeat a class in a role are skipped.\nYour own Invite clicks aren't limited."):SetWidth(400); yy = yy - 24
  -- Past keys together (1.5.0): only among groups that already pass the level and the musts.
  AddCheck(self, f, x2, yy, "Prefer players I've timed with", function() return FillS().preferTimed == true end,
    function(v) FillS().preferTimed = v; ns:Fire("FILL_SETTINGS_CHANGED") end,
    "Among groups that already pass, players you've timed keys with count for more (5 points each at Relaxed, 3 at Standard, a tiebreak at Strict). Never makes a failing group pass."):SetWidth(400); yy = yy - 26
  local fwl = Text(f, 12, C.text); fwl:SetPoint("TOPLEFT", x2 + 22, yy - 3); fwl:SetText("Players I've failed with:")
  local fw = Button(f, "", 130, 20, function(btn)
    local items = {}
    for _, d in ipairs({ { "off", "No change" }, { "lower", "Lower priority" }, { "skip", "Skip" } }) do
      items[#items + 1] = { text = d[2], selected = (FillS().failedWith or "off") == d[1],
        onClick = function() FillS().failedWith = d[1]; ns:Fire("FILL_SETTINGS_CHANGED"); UI:RefreshSettings() end }
    end
    UI:ShowMenu(btn, items)
  end)
  SetFontSize(fw.text, 11)
  fw:SetPoint("LEFT", fwl, "RIGHT", 8, 0)
  fw.tooltip = "More failed keys than timed ones with you (what counts as failed: Settings > Group Finder). Lower priority: they count for less among groups that pass. Skip: like a filter, dimmed and tagged SKIPPED with the reason."
  self.fillFailedBtn = fw
  yy = yy - 30   -- 1.5.1: 4 px tighter (room for "One player per class in each role")

  SubHead(f, x2, yy, "Auto-fill"); yy = yy - 22
  AddCheck(self, f, x2, yy, "Turn Auto-fill on when I list a group", function() return FillS().autoArm == true end,
    function(v) FillS().autoArm = v end, "Off: turn it on per listing with the Auto-fill box on the Applicants tab."):SetWidth(400); yy = yy - 24
  AddCheck(self, f, x2, yy, "Play a sound when a full group is ready", function() return FillS().sound ~= false end,
    function(v) FillS().sound = v end, "Once per new group: Ensemble's chime or the game's ready check (pick it below)."):SetWidth(400); yy = yy - 24
  -- Which sound, and a button to hear it.
  local snd = Button(f, "", 150, 20, function(btn)
    local items = {}
    for _, k in ipairs(FG.SOUND_ORDER) do
      items[#items + 1] = { text = FG.SOUNDS[k], selected = (FillS().soundChoice or "chime") == k,
        onClick = function() FillS().soundChoice = k; UI:RefreshSettings() end }
    end
    UI:ShowMenu(btn, items)
  end)
  SetFontSize(snd.text, 11)
  snd:SetPoint("TOPLEFT", x2 + 22, yy)
  snd.tooltip = "Ensemble's own chime, or the game's ready-check sound"
  local play = Button(f, "Play", 50, 20, function() FG:PlayReadySound(FillS().soundChoice) end)
  SetFontSize(play.text, 11)
  play:SetPoint("LEFT", snd, "RIGHT", 8, 0)
  play.tooltip = "Hear the sound now"
  self.fillSoundBtn, self.fillSoundPlay = snd, play
  yy = yy - 28
  AddCheck(self, f, x2, yy, "Show a pop-up when the window is closed", function() return FillS().popup ~= false end,
    function(v) FillS().popup = v; UI:UpdateFillPopup() end,
    "With the main window and the Group Finder closed, a small pop-up shows the plan, with Review and Fill group."):SetWidth(400); yy = yy - 26
  local wl = Text(f, 12, C.text); wl:SetPoint("TOPLEFT", x2, yy); wl:SetText("Wait before telling me")
  local wm = Button(f, "-", 22, 20, function() FillS().wait = math.max(0, (FillS().wait or 15) - 5); UI:RefreshSettings() end)
  wm:SetPoint("TOPLEFT", x2 + 230, yy + 3)
  local wv = Text(f, 12, C.text, "CENTER"); wv:SetPoint("LEFT", wm, "RIGHT", 2, 0); wv:SetWidth(44)
  local wp = Button(f, "+", 22, 20, function() FillS().wait = math.min(120, (FillS().wait or 15) + 5); UI:RefreshSettings() end)
  wp:SetPoint("LEFT", wv, "RIGHT", 2, 0)
  self.fillWaitText = wv
  local waitNote = Note(f, x2, yy - 24, 440, "Gives more players time to apply, so the first full group isn't the only one seen.")
  -- Hangs below the note above (two lines at larger text sizes).
  local inviteNote = Note(f, x2, yy - 52, 440, "Ensemble only invites when you click: Auto-fill finds the group and tells you; you send the invites.")
  inviteNote:ClearAllPoints(); inviteNote:SetPoint("TOPLEFT", waitNote, "BOTTOMLEFT", 0, -6)
end

-- The musts box: as tall as its rows, capped so "+ Add a need" and "Reset needs" stay inside
-- the panel (the box scrolls past that). Without real positions yet (before the first layout,
-- or in tests) it takes the rows' full height.
function UI:LayoutFillMusts()
  local box, f, inner = self.fillMustsBox, self.fillPanel, self.fillMustInner
  if not (box and f and inner) then return end
  local content = math.max(22, inner:GetHeight() or 22)
  local h = content
  local top, bottom = box:GetTop(), f:GetBottom()
  if type(top) == "number" and type(bottom) == "number" then
    h = math.max(44, math.min(content, top - bottom - 8 - 22 - 14))   -- gap, buttons, margin
  end
  box:SetHeight(h)
  local max = math.max(0, content - h)
  if (box:GetVerticalScroll() or 0) > max then box:SetVerticalScroll(max) end
end

-- The parts of the Fill group section that depend on the dungeon and the key.
function UI:RefreshFillSettings()
  if not self.fillMustRows then return end
  local FG = ns.FillGroup
  local dk, how = self:FillMustsDungeon()
  self.fillMustsPick.text:SetText(HEX.accent .. DD.list[dk].name .. "|r")
  self.fillMustsNote:SetText(how == "picked" and "Picked here. Saved per dungeon."
    or (how == "pick one" and "Pick a dungeon. Saved per dungeon." or ("Follows the key (" .. how .. "). Saved per dungeon.")))
  local m = FG:Musts(dk)
  local rows, heads = self.fillMustRows, self.fillMustHeads
  for _, h in ipairs(heads) do h:Hide() end
  local y, i = 0, 0
  local function place(get, set, label, sub, tip)
    i = i + 1
    local row = rows[i]
    if not row then return end
    row.get, row.set = get, set
    row.check.label:SetText(label .. (sub and (HEX.muted .. "  -  " .. sub .. "|r") or ""))
    row.check.tip = tip
    row.check:ClearAllPoints(); row.check:SetPoint("TOPLEFT", 0, -y)
    row.check:Sync(); row.check:Show()
    y = y + 22
  end
  local function head(n, text)
    local h = heads[n]
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y - 2); h:SetText(text); h:Show()
    y = y + 18
  end
  place(function() return FG:Musts(dk).lust end, function(v) FG:SetMust(dk, "lust", v) end,
    "Bloodlust", "every key", "A group needs Bloodlust. Untick it to let groups without one pass.")
  local boss, added = {}, {}
  for _, row in ipairs(m.rows) do if row.boss then boss[#boss + 1] = row else added[#added + 1] = row end end
  if #boss > 0 then head(1, "BOSS MECHANICS") end
  for _, row in ipairs(boss) do
    local id = row.req.id
    local label, sub = FG:MustLabel(row)
    place(function()
      for _, r in ipairs(FG:Musts(dk).rows) do if r.req.id == id then return r.on end end
      return false
    end, function(v) FG:SetMust(dk, id, v) end, label, sub,
      row.req.source .. (row.req.severity == "low" and "\nLow severity: starts unticked." or ""))
  end
  if #added > 0 then head(2, "ADDED BY YOU") end
  for _, row in ipairs(added) do
    local id = row.req.id
    local label, sub = FG:MustLabel(row)
    place(function() return true end, function(v) FG:SetMust(dk, id, v); UI:RefreshSettings() end, label, sub, row.req.source)
  end
  for k = i + 1, #rows do rows[k].check:Hide() end
  self.fillMustInner:SetHeight(math.max(1, y))
  self:LayoutFillMusts()
  -- Filters: the value in force for the key.
  local level = ns.ApplicantFit:GetKeyLevel(dk)
  local filters = FG:Filters(nil, level)
  local SRC = { suggested = "Suggested for the key", listing = "From my listing", custom = "Custom" }
  for k, r in pairs(self.fillFilterRows) do
    local fl = filters[k]
    local conf = ns.db.settings.fill[k]
    r.src.text:SetText(SRC[conf.source] or conf.source)
    r.val:SetText(conf.source == "custom" and tostring(conf.value) or (fl.on and tostring(fl.value) or "-"))
    local keyText = level and ("+" .. level) or "the key"
    r.note:SetText(conf.on == false and "Off." or (fl.on and ("In force for " .. keyText .. ": " .. fl.value .. ".")
      or ("Not in force: " .. tostring(fl.why) .. ".")))
  end
  self.fillWaitText:SetText((ns.db.settings.fill.wait or 15) .. " s")
  self.fillSoundBtn.text:SetText(FG.SOUNDS[ns.db.settings.fill.soundChoice or "chime"] or FG.SOUNDS.chime)
end

function UI:BuildSettings_chat(f)
  SubHead(f, 8, -44, "Style of posts")
  AddRadio(self, f, 8, -66, "Full: casts with their mobs, dispels and backups", "chatStyle", "full",
    "One line per player: what they kick (with the mob and their 1st/2nd turn), dispel and back up. Gaps name the cast that needs them.")
  AddRadio(self, f, 8, -92, "Short: just the essentials", "chatStyle", "short",
    "Still one line per player, so nobody's assignments are left out, but without mob names, dispel casts or backups. Gaps without the casts.")
  Note(f, 8, -124, 520, "Applies to \"Post gaps\" and \"Post assignments\" (Plan tab). Hover either to preview the exact text.")
end

function UI:BuildSettings_bosses(f)
  local function bw() return S().bossWindow end
  SubHead(f, 8, -44, "Boss window")
  local y = -66
  local function row(label, g, st, tip) AddCheck(self, f, 8, y, label, g, st, tip); y = y - 26 end
  row("Open when I enter a Season dungeon", function() return bw().autoOpen ~= false end,
    function(v) bw().autoOpen = v end, "The boss window opens on its own in a Season dungeon and turns to the next boss after each kill.")
  row("Show every role's notes", function() return bw().showAll end, function(v) bw().showAll = v end,
    "Off: your role's notes and everyone's. On: tank, healer and DPS notes too. The window's footer button switches this as well.")
  row("Fade in combat", function() return bw().fadeInCombat ~= false end, function(v) bw().fadeInCombat = v end,
    "Make the window see-through while you're in combat so it never hides the fight.")
  row("Lock the window", function() return bw().locked end, function(v) bw().locked = v end,
    "Stop moving and resizing the boss window.")
  y = y - 6
  local lbl = Text(f, 12, C.text); lbl:SetPoint("TOPLEFT", 8, y)
  self.bossFontLabel = lbl
  local minus = Button(f, "-", 26, 22, function() ns.BossWindow:SetFontSize((bw().fontSize or 12) - 1); UI:RefreshSettings() end)
  minus:SetPoint("TOPLEFT", 150, y + 3)
  local plus = Button(f, "+", 26, 22, function() ns.BossWindow:SetFontSize((bw().fontSize or 12) + 1); UI:RefreshSettings() end)
  plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  y = y - 34
  local open = Button(f, "Open the boss window", 180, 24, function() ns.BossWindow:Show() end)
  open:SetPoint("TOPLEFT", 8, y)
  open.tooltip = "Outside a dungeon it shows the dungeon you're checking."
  local reset = Button(f, "Reset its position and size", 200, 24, function()
    local b = bw(); b.point, b.relPoint, b.x, b.y, b.width, b.height = nil, nil, nil, nil, nil, nil
    if ns.BossWindow.frame then ns.BossWindow:ApplyGeometry() end
  end)
  reset:SetPoint("LEFT", open, "RIGHT", 8, 0)
  Note(f, 8, y - 36, 540, "Edit a boss's notes from the window's Edit button or the Dungeons tab. Your edits are kept when the addon updates; the card tells you when the built-in version has changed.")
end

function UI:BuildSettings_appearance(f)
  self:BuildAppearance(f, -40, 480)
end

function UI:BuildSettings_data(f)
  SubHead(f, 8, -44, "Run history")
  AddCheck(self, f, 8, -66, "Record my keys", function() return S().history ~= false end, function(v) S().history = v end,
    "Save every Mythic+ key you run (on your computer only) for the History tab.")
  local clear = Button(f, "Clear run history", 160, 24)
  clear:SetPoint("TOPLEFT", 8, -96)
  clear:SetScript("OnClick", function(btn)
    if btn.armed then btn.armed = nil; btn.text:SetText("Clear run history"); ns.History:Clear(); ns:Print("Run history cleared.")
    else
      btn.armed = true; btn.text:SetText("Click again to confirm")
      C_Timer.After(4, function() if btn.armed then btn.armed = nil; btn.text:SetText("Clear run history") end end)
    end
  end)
  SubHead(f, 8, -144, "Everything")
  Note(f, 8, -162, 520, "Wipes " .. ns.RESET_WIPES .. ". Can't be undone.")
  local reset = Button(f, "Reset all Ensemble data", 260, 26)
  reset:SetPoint("TOPLEFT", 8, -184)
  reset:SetScript("OnClick", function(btn)
    if btn.armed then
      btn.armed = nil; btn.text:SetText("Reset all Ensemble data")
      ns:ResetDB(); ns:Print("All Ensemble data reset.")
    else
      btn.armed = true; btn.text:SetText("Click again to confirm")
      C_Timer.After(4, function() if btn.armed then btn.armed = nil; btn.text:SetText("Reset all Ensemble data") end end)
    end
  end)
  SubHead(f, 8, -232, "Report a problem")
  local rn = Note(f, 8, -250, 520, "Opens a copyable report with your version, setup and recent errors. Add what happened at the top, then paste it with your issue.")
  local rep = Button(f, "Copy a bug report", 180, 24, function() if ns.Report then ns.Report:Run() end end)
  rep:SetPoint("TOPLEFT", rn, "BOTTOMLEFT", 0, -8)
  rep.tooltip = "Same as /ens report. Includes specs and settings, never player names."
  SubHead(f, 8, -334, "Game data")
  Note(f, 8, -352, 420, "Ensemble " .. tostring(ns.VERSION) .. ". " .. DD:FreshnessText())
  local src = Button(f, "Sources", 90, 24, function() UI:ShowSources() end)
  src:SetPoint("TOPLEFT", 440, -350)
  src.tooltip = "The guides this data comes from"
  self.sourcesBtn = src
end

function UI:RefreshSettings()
  for _, c in ipairs(self.checks or {}) do c:Sync() end
  for _, sl in ipairs(self.settingsSliders or {}) do sl:Sync() end
  if self.textSlider then self.textSlider:Sync() end
  if self.presetNote then
    local cur = self:CurrentSettingsPreset()
    self.presetNote:SetText(cur and ("Current: " .. self.PRESETS_SETTINGS[cur].label) or "Current: your own mix")
  end
  self:SyncAppearance()
  self:RefreshFillSettings()
  if self.pastFailedBtn then self.pastFailedBtn.text:SetText(ns.History.FAILED_LABEL[ns.History:FailedMode()]) end
  if self.fillReserveText then
    local n = #ns.Players:Reservations()
    self.fillReserveBtn.text:SetText(n > 0 and ("Reserved (" .. n .. ")") or "Reserve a slot")
    self.fillReserveText:SetText(self:ReservedText() or "No reserved slots.")
  end
  if self.RefreshSavedPlayers then self:RefreshSavedPlayers() end
  if self.fillFailedBtn then
    self.fillFailedBtn.text:SetText(({ off = "No change", lower = "Lower priority", skip = "Skip" })[ns.db.settings.fill.failedWith or "off"] or "No change")
  end
  if self.bossFontLabel then
    self.bossFontLabel:SetText("Text size: " .. tostring((ns.db.settings.bossWindow or {}).fontSize or 12) .. " px")
  end
end

---------------------------------------------------------------------------
-- Appearance: accent color (wheel + hex + presets + class color) and window options.
---------------------------------------------------------------------------
local function SetThemeHex(hex, fromWheel)
  local r, g, b = HexToRGB(hex)
  if not r then return false end
  local t = ns.db.settings.theme
  t.hex = RGBToHex(r, g, b)
  t.classColor = false
  UI:ApplyTheme()
  UI:SyncAppearance(fromWheel)
  return true
end
UI.SetThemeHex = SetThemeHex

-- Embedded color wheel built from the client's ColorSelect widget (the same widget the
-- Blizzard color picker uses). confirmed present in 12.1.0 (build 69933) by /ens verify:
-- CreateFrame("ColorSelect"), SetColorWheelTexture / SetColorValueTexture and their thumbs,
-- SetColorRGB, OnColorSelect. If it isn't available, a button opens Blizzard's picker.
local function BuildWheel(parent)
  local ok, cs = pcall(CreateFrame, "ColorSelect", nil, parent)
  if not ok or not cs or not cs.SetColorWheelTexture then return nil end
  cs:SetSize(168, 128)
  local wheel = cs:CreateTexture(nil, "ARTWORK")
  wheel:SetSize(128, 128); wheel:SetPoint("TOPLEFT")
  cs:SetColorWheelTexture(wheel)
  local wthumb = cs:CreateTexture(nil, "OVERLAY")
  wthumb:SetTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
  wthumb:SetTexCoord(0, 0.15625, 0, 0.625); wthumb:SetSize(10, 10)
  cs:SetColorWheelThumbTexture(wthumb)
  local value = cs:CreateTexture(nil, "ARTWORK")
  value:SetSize(16, 128); value:SetPoint("TOPLEFT", wheel, "TOPRIGHT", 18, 0)
  cs:SetColorValueTexture(value)
  local vthumb = cs:CreateTexture(nil, "OVERLAY")
  vthumb:SetTexture("Interface\\Buttons\\UI-ColorPicker-Buttons")
  vthumb:SetTexCoord(0.25, 1, 0.875, 0); vthumb:SetSize(28, 8)
  cs:SetColorValueThumbTexture(vthumb)
  cs:SetScript("OnColorSelect", function(self, r, g, b)
    if self.syncing then return end
    if not r then r, g, b = self:GetColorRGB() end
    SetThemeHex(RGBToHex(r, g, b), true)
  end)
  return cs
end

local function OpenBlizzardPicker()
  if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
  local r, g, b = UI:CurrentAccent()
  local prev = ns.db.settings.theme.hex
  ColorPickerFrame:SetupColorPickerAndShow({
    r = r, g = g, b = b, hasOpacity = false,
    swatchFunc = function() SetThemeHex(RGBToHex(ColorPickerFrame:GetColorRGB())) end,
    cancelFunc = function() SetThemeHex(prev) end,
  })
end

function UI:BuildAppearance(page, topOffset, windowX)
  local ap = {}
  self.appear = ap
  local top = topOffset or -284

  -- Color wheel (or picker button fallback)
  ap.wheel = BuildWheel(page)
  if ap.wheel then
    ap.wheel:SetPoint("TOPLEFT", 8, top - 34)
  else
    local b = Button(page, "Open color picker", 160, 26, OpenBlizzardPicker)
    b:SetPoint("TOPLEFT", 8, top - 34)
  end

  -- Hex input + live swatch
  local x = 196
  local hl = Text(page, 11, C.muted); hl:SetPoint("TOPLEFT", x, top - 36); hl:SetText("Accent color (hex)")
  ap.swatch = CreateFrame("Frame", nil, page, "BackdropTemplate")
  ap.swatch:SetSize(26, 26); ap.swatch:SetPoint("TOPLEFT", x, top - 54)
  ap.swatch:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  ap.swatch:SetBackdropBorderColor(unpack(C.border))
  Accent(function(a) ap.swatch:SetBackdropColor(a[1], a[2], a[3], 1) end, "fn")
  ap.hex = EditBox(page, 96, 26)
  ap.hex:SetPoint("LEFT", ap.swatch, "RIGHT", 8, 0)
  ap.hex:SetMaxLetters(7)
  ap.hex:SetScript("OnEnterPressed", function(box)
    if SetThemeHex(box:GetText()) then box:ClearFocus()
    else box:SetBackdropBorderColor(unpack(C.bad)); ap.hexNote:SetText(HEX.bad .. "Use 6 hex digits, e.g. 7EB7FF|r") end
  end)
  ap.hex:SetScript("OnEditFocusLost", function() UI:SyncAppearance() end)
  ap.hexNote = Text(page, 10, C.muted); ap.hexNote:SetPoint("LEFT", ap.hex, "RIGHT", 8, 0); ap.hexNote:SetWidth(170)
  ap.hexNote:SetText("Enter to apply")

  ap.classCheck = Check(page, "Use my class color", function() return ns.db.settings.theme.classColor end,
    function(v) ns.db.settings.theme.classColor = v; UI:ApplyTheme(); UI:SyncAppearance() end)
  ap.classCheck:SetPoint("TOPLEFT", x, top - 90)
  table.insert(self.checks, ap.classCheck)

  -- Presets
  local pl = Text(page, 11, C.muted); pl:SetPoint("TOPLEFT", x, top - 120); pl:SetText("Presets")
  ap.presets = {}
  for i, pr in ipairs(UI.PRESETS) do
    local b = CreateFrame("Button", nil, page, "BackdropTemplate")
    b:SetSize(24, 24)
    local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
    b:SetPoint("TOPLEFT", x + col * 32, top - 138 - row * 32)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    local r, g, bl = HexToRGB(pr.hex)
    b:SetBackdropColor(r, g, bl, 1)
    b:SetBackdropBorderColor(unpack(C.border))
    b.hexValue = pr.hex
    b:SetScript("OnClick", function() SetThemeHex(pr.hex) end)
    b:SetScript("OnEnter", function(self)
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(pr.name .. "  #" .. pr.hex, 1, 1, 1); GameTooltip:Show()
      end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    ap.presets[i] = b
  end
  local reset = FlatButton(page, "Reset color", 90, 22, function() SetThemeHex(DEFAULT_ACCENT) end)
  reset:SetPoint("TOPLEFT", x + 166, top - 138)

  -- Window options
  local wx = windowX or 640
  local wt = Text(page, 11, C.muted); wt:SetPoint("TOPLEFT", wx, top - 36); wt:SetText("Window")
  local lock = Check(page, "Lock window", function() return ns.db.settings.window.locked end,
    function(v) ns.db.settings.window.locked = v end, "No moving or resizing. The title bar's Unlocked / Locked button does the same.")
  lock:SetPoint("TOPLEFT", wx, top - 54)
  table.insert(self.checks, lock)
  local sl = Text(page, 11, C.muted); sl:SetPoint("TOPLEFT", wx, top - 88); sl:SetText("Text size")
  self.textSlider = SliderCtl(page, 180, UI.TEXT_MIN, UI.TEXT_MAX, 5,
    function() return ns.db.settings.textSize or 100 end,
    function(v) UI:SetTextSize(v) end, "%d%%")
  self.textSlider:SetPoint("TOPLEFT", wx, top - 108)
  local rp = FlatButton(page, "Reset position & size", 150, 22, function() UI:ResetGeometry() end)
  rp:SetPoint("TOPLEFT", wx - 6, top - 132)
  local hint = Text(page, 10, C.muted); hint:SetPoint("TOPLEFT", wx, top - 162); hint:SetWidth(270)
  hint:SetText("Unlocked: drag the title bar to move and the bottom-right grip to resize (more room, same text).")
end

-- Reflect the current theme in the appearance controls (wheel, hex box, preset borders).
function UI:SyncAppearance(fromWheel)
  local ap = self.appear
  if not ap then return end
  local r, g, b = self:CurrentAccent()
  local hex = RGBToHex(r, g, b)
  if not ap.hex:HasFocus() then ap.hex:SetText("#" .. hex) end
  ap.hex:SetBackdropBorderColor(unpack(C.border))
  ap.hexNote:SetText(ns.db.settings.theme.classColor and "Following your class color" or "Enter to apply")
  if ap.wheel and not fromWheel then
    ap.wheel.syncing = true
    ap.wheel:SetColorRGB(r, g, b)
    ap.wheel.syncing = false
  end
  for _, pb in ipairs(ap.presets) do
    local sel = (not ns.db.settings.theme.classColor) and pb.hexValue == ns.db.settings.theme.hex
    if sel then pb:SetBackdropBorderColor(1, 1, 1, 1) else pb:SetBackdropBorderColor(unpack(C.border)) end
  end
end

---------------------------------------------------------------------------
-- Minimap button (plain frame; Blizzard border art)
---------------------------------------------------------------------------
function UI:UpdateMinimapPosition()
  local b = self.minimapButton
  if not b or not Minimap then return end
  local angle = math.rad(ns.db.settings.minimap.angle or 215)
  local radius = (Minimap:GetWidth() / 2) + 5
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function UI:CreateMinimapButton()
  if self.minimapButton or not Minimap then return end
  local b = CreateFrame("Button", "EnsembleMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(UI.LOGO)   -- the addon's emblem (Media/LogoMark)
  icon:SetSize(22, 22); icon:SetPoint("TOPLEFT", 6, -5)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then UI:Show("settings") else UI:Toggle() end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local scale = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      cx, cy = cx / scale, cy / scale
      ns.db.settings.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
      UI:UpdateMinimapPosition()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    -- Name in white, subtitle in the accent color, then the actions (unchanged).
    GameTooltip:AddLine(UI.NAME, 1, 1, 1)
    GameTooltip:AddLine(UI.SUBTITLE, C.accent[1], C.accent[2], C.accent[3])
    GameTooltip:AddLine("Left-click: toggle   Right-click: settings   Drag: move", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.minimapButton = b
  self:UpdateMinimapPosition()
  b:SetShown(not ns.db.settings.minimap.hide)
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
-- An entry in Blizzard's Options > AddOns that points to the addon's own settings
-- (Settings.RegisterCanvasLayoutCategory / RegisterAddOnCategory, the 10.0+ settings API).
function UI:RegisterBlizzardOptions()
  if self.blizzCategory or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local panel = CreateFrame("Frame")
  panel.name = "Ensemble"
  local logo = panel:CreateTexture(nil, "ARTWORK"); logo:SetTexture(UI.LOGO); logo:SetSize(48, 48); logo:SetPoint("TOPLEFT", 16, -16)
  local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); t:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
  t:SetText("Ensemble")
  local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); sub:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
  sub:SetText(UI.SUBTITLE)
  local body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); body:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
  body:SetWidth(540); body:SetJustifyH("LEFT")
  body:SetText("Every setting is in the addon's own window: General, What to check, Group Finder, Fill group, Saved players, Party chat, Boss cards, Appearance and Data. Type /ens to open the addon, or use the button below.")
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(260, 26); b:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -14)
  b:SetText("Open Ensemble settings")
  b:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
    UI:OpenSettings("general")
  end)
  local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Ensemble")
  if ok and cat then
    pcall(Settings.RegisterAddOnCategory, cat)
    self.blizzCategory = cat
  end
end

ns:On("LOGIN", function() UI:ApplyTheme(true); UI:CreateMinimapButton(); pcall(UI.RegisterBlizzardOptions, UI) end)
-- Automatic mode: joining or leaving a group, or listing one, switches Composition and Plan
-- between your party and the planner while the window is open.
local modeWatcher = CreateFrame("Frame")
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "LFG_LIST_ACTIVE_ENTRY_UPDATE" }) do pcall(modeWatcher.RegisterEvent, modeWatcher, ev) end
modeWatcher:SetScript("OnEvent", function()
  if not (UI.frame and UI.frame:IsShown()) or (ns.db.settings.compMode or "auto") ~= "auto" then return end
  local tab = UI.currentTab
  if (tab == "composition" or tab == "plan") and UI:CompMode() ~= ns.state.mode then UI:SetTab(tab) end
end)
-- Which events each tab shows. The open tab refreshes on them; every other tab skips the
-- rebuild: SetTab refreshes a tab each time it's shown (and so does opening the window),
-- so a tab that missed an event is never shown stale. true = always; a function = only when
-- it returns true. SETTINGS_CHANGED refreshes every tab (its own handler below).
local function LiveMode() return ns.state.mode == "live" end
local function FillSection() return UI.settingsSection == "fill" end
local function PlayersSection() return UI.settingsSection == "players" end
UI.TAB_EVENTS = {
  composition = { COMP_CHANGED = true, DUNGEON_CHANGED = true, LIVE_ROSTER_CHANGED = LiveMode,
    RESERVED_CHANGED = LiveMode, SAVED_PLAYERS_CHANGED = true,
    -- Party mode: the applicant panel's "With you" and the opt-in past-keys rating follow a
    -- finished key (1.5.0 review, N4; the simpler of the two approved options).
    HISTORY_CHANGED = LiveMode },
  plan = { COMP_CHANGED = true, DUNGEON_CHANGED = true, LIVE_ROSTER_CHANGED = LiveMode,
    LUST_CHANGED = true, BOSS_ORDER_CHANGED = true, ASSIGNMENTS_CHANGED = true },
  applicants = { DUNGEON_CHANGED = true, LIVE_ROSTER_CHANGED = true, FILL_ALERT = true,
    FILL_ARMED = true, FILL_DONE = true, FILL_SETTINGS_CHANGED = true, HISTORY_CHANGED = true,
    RESERVED_CHANGED = true },
  dungeons = { DUNGEON_CHANGED = true, LUST_CHANGED = true, BOSS_ORDER_CHANGED = true,
    BOSS_DUNGEON_ENTERED = true, BOSS_DUNGEON_LEFT = true },
  history = { HISTORY_CHANGED = true },
  settings = { DUNGEON_CHANGED = FillSection, LIVE_ROSTER_CHANGED = FillSection, FILL_ARMED = FillSection,
    FILL_SETTINGS_CHANGED = FillSection, RESERVED_CHANGED = FillSection, SAVED_PLAYERS_CHANGED = PlayersSection },
}
function UI:TabWants(tab, event)
  local w = self.TAB_EVENTS[tab] and self.TAB_EVENTS[tab][event]
  if type(w) == "function" then return w() and true or false end
  return w and true or false
end
function UI:OnTabEvent(event)
  if self:TabWants(self.currentTab, event) then self:QueueRefresh() end
end
for _, ev in ipairs({ "COMP_CHANGED", "LUST_CHANGED", "BOSS_ORDER_CHANGED", "ASSIGNMENTS_CHANGED",
  "HISTORY_CHANGED", "DUNGEON_CHANGED", "BOSS_DUNGEON_ENTERED", "BOSS_DUNGEON_LEFT" }) do
  ns:On(ev, function() UI:OnTabEvent(ev) end)
end
-- Fill group: a new plan, an alert, an invite sent, a must or a filter changed.
local function FillChanged(ev)
  UI:OnTabEvent(ev); UI:QueueFinderRefresh(); UI:UpdateFillPopup()
  if UI.frame and UI.frame:IsShown() then UI:SyncFillTabDot() end
end
for _, ev in ipairs({ "FILL_ALERT", "FILL_ARMED", "FILL_DONE", "FILL_SETTINGS_CHANGED", "RESERVED_CHANGED" }) do
  ns:On(ev, function() FillChanged(ev) end)
end
ns:On("SAVED_PLAYERS_CHANGED", function() UI:OnTabEvent("SAVED_PLAYERS_CHANGED") end)
ns:On("LIVE_ROSTER_CHANGED", function()
  UI:OnTabEvent("LIVE_ROSTER_CHANGED")
  -- The Applicants tab's dot shows on other tabs, so it follows the roster on its own.
  if UI.frame and UI.frame:IsShown() then UI:SyncFillTabDot() end
  UI:QueueFinderRefresh()
end)
ns:On("DUNGEON_CHANGED", function() UI:QueueFinderRefresh() end)
ns:On("LOGIN", function() UI:AttachFinderPanel() end)
ns:On("SETTINGS_CHANGED", function()
  if UI.frame then
    UI:ApplyTheme(true); UI:UpdateLockState(); UI:ApplyGeometry()
    -- Re-fonting every text object is only needed when the size actually changed.
    if UI.appliedTextSize ~= ns.db.settings.textSize then UI:ApplyTextSize() end
  end
  if UI.minimapButton then UI.minimapButton:SetShown(not ns.db.settings.minimap.hide) end
  if ns.Tracker.enabled then ns.Tracker:RequestUpdate(0) end
  UI:QueueRefresh()
  UI:QueueFinderRefresh()
end)
