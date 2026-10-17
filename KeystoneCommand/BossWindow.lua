-- Keystone Command / BossWindow.lua
-- The boss-card pop-up: a small, movable, resizable window with its own text size that
-- opens when you enter a Season dungeon and turns to the next boss when one dies. Shows
-- your role's lines first (or every role), your kick / dispel jobs from the plan in a
-- highlighted block, page arrows, an editor and "post to chat". Also draws the boss cards
-- in the Dungeons tab (UI:RenderBossCards) and the shared editor (UI:OpenBossEditor).
local _, ns = ...

local UI = ns.UI
local BW = {}
ns.BossWindow = BW

local MIN_W, MIN_H, MAX_W, MAX_H = 240, 120, 760, 640
BW.FONT_MIN, BW.FONT_MAX = 9, 20

local ROLE_TAG = {
  ALL = "|cffb4b8c4ALL|r", TANK = "|cff6fa8ffTANK|r", HEAL = "|cff61cc78HEAL|r", DPS = "|cffee6161DPS|r",
}
BW.ROLE_TAG = ROLE_TAG

local function S() return ns.db and ns.db.settings and ns.db.settings.bossWindow end
local function Kit() return UI.Kit end

---------------------------------------------------------------------------
-- What the window is showing: the dungeon you're in (and its current boss), or a dungeon
-- picked by hand (/kc boss outside a dungeon, or "Open in boss window" from the primer).
---------------------------------------------------------------------------
BW.view = {}

function BW:Current()
  local BC = ns.BossCards
  if BC.state.dk then return BC.state.dk, BC.state.index or 1, true end
  if self.view.dk then return self.view.dk, self.view.index or 1, false end
  local ok, dk = pcall(ns.GetEffectiveDungeon, ns, false)
  dk = ok and dk or (ns.Dungeons and ns.Dungeons.order[1])
  return dk, 1, false
end

function BW:Step(d)
  local BC = ns.BossCards
  local dk, i, inside = self:Current()
  if inside then BC:Step(d); return end
  local n = #BC:Bosses(dk)
  if n == 0 then return end
  self.view = { dk = dk, index = ((i - 1 + d) % n) + 1 }
  self:Refresh()
end

---------------------------------------------------------------------------
-- Bloodlust planned at a spot ("b2", "t3"): rows of kind "lust".
function BW:LustRows(dk, at)
  local out = {}
  local WT = ns.Walkthrough
  if not WT then return out end
  for _, u in ipairs(WT:Lust(dk)) do
    if u.at == at then out[#out + 1] = { kind = "lust", text = "Bloodlust" .. (u.note and (": " .. u.note) or (at:sub(1, 1) == "b" and ": on pull" or " here")) } end
  end
  return out
end

-- Content: rows of { kind = "job" | "line" | "lust", tag, text }
---------------------------------------------------------------------------
function BW:Rows(dk, i, role, all, inside)
  local BC = ns.BossCards
  local rows = {}
  local plan, r = BC:Plan(dk)
  for _, x in ipairs(self:LustRows(dk, "b" .. i)) do rows[#rows + 1] = x end
  for _, j in ipairs(BC:Jobs(dk, i, plan, r)) do
    rows[#rows + 1] = { kind = "job", backup = j.backup, text = j.text }
  end
  local lines = BC:Lines(dk, i)
  for _, l in ipairs(BC:Ordered(lines, role, all)) do
    rows[#rows + 1] = { kind = "line", role = l.role, text = l.text, nv = l.nv }
  end
  return rows
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
function BW:SaveGeometry()
  local f, s = self.frame, S()
  if not (f and s) then return end
  local point, _, relPoint, x, y = f:GetPoint()
  s.point, s.relPoint, s.x, s.y = point or "CENTER", relPoint or "CENTER", x or 0, y or 0
  s.width, s.height = math.floor((f:GetWidth() or 320) + 0.5), math.floor((f:GetHeight() or 200) + 0.5)
end

function BW:ApplyGeometry()
  local f, s = self.frame, S()
  if not (f and s) then return end
  f:ClearAllPoints()
  f:SetPoint(s.point or "RIGHT", UIParent, s.relPoint or "RIGHT", s.x or -60, s.y or 80)
  f:SetSize(math.max(MIN_W, math.min(MAX_W, s.width or 320)), math.max(MIN_H, math.min(MAX_H, s.height or 210)))
end

local function SmallBtn(parent, label, w, tip, onClick)
  local b = Kit().FlatButton(parent, label, w, 18, onClick)
  b.tooltip = tip
  return b
end

function BW:Build()
  if self.frame then return end
  local K = Kit()
  local C = K.C
  local f = CreateFrame("Frame", "KeystoneCommandBossFrame", UIParent, "BackdropTemplate")
  self.frame = f
  K.Skin(f, C.bg, C.border)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() if not (S() and S().locked) then f:StartMoving() end end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); BW:SaveGeometry() end)
  f:Hide()

  -- Header: arrows, boss name and page, close.
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(24)
  local hbg = head:CreateTexture(nil, "BACKGROUND"); hbg:SetAllPoints(); hbg:SetColorTexture(unpack(C.header))
  head:EnableMouse(true); head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() if not (S() and S().locked) then f:StartMoving() end end)
  head:SetScript("OnDragStop", function() f:StopMovingOrSizing(); BW:SaveGeometry() end)
  self.prev = SmallBtn(head, "<", 20, "Previous boss", function() BW:Step(-1) end)
  self.prev:SetPoint("LEFT", 4, 0)
  self.next = SmallBtn(head, ">", 20, "Next boss", function() BW:Step(1) end)
  self.next:SetPoint("LEFT", self.prev, "RIGHT", 2, 0)
  self.close = SmallBtn(head, "x", 20, "Close (reopen with /kc boss)", function() BW:Hide(true) end)
  self.close:SetPoint("RIGHT", -4, 0)
  self.title = head:CreateFontString(nil, "OVERLAY")
  self.title:SetPoint("LEFT", self.next, "RIGHT", 6, 0); self.title:SetPoint("RIGHT", self.close, "LEFT", -6, 0)
  self.title:SetJustifyH("LEFT"); self.title:SetWordWrap(false)
  self.head = head

  -- Footer: role filter, text size, edit, post, lock.
  local foot = CreateFrame("Frame", nil, f)
  foot:SetPoint("BOTTOMLEFT", 1, 1); foot:SetPoint("BOTTOMRIGHT", -1, 1); foot:SetHeight(20)
  self.roleBtn = SmallBtn(foot, "", 64, "Show only your role (and everyone's) lines, or every role", function()
    local s = S(); s.showAll = not s.showAll; BW:Refresh()
  end)
  self.roleBtn:SetPoint("LEFT", 4, 0)
  self.smaller = SmallBtn(foot, "A-", 24, "Smaller text", function() BW:SetFontSize((S().fontSize or 12) - 1) end)
  self.smaller:SetPoint("LEFT", self.roleBtn, "RIGHT", 2, 0)
  self.bigger = SmallBtn(foot, "A+", 24, "Bigger text", function() BW:SetFontSize((S().fontSize or 12) + 1) end)
  self.bigger:SetPoint("LEFT", self.smaller, "RIGHT", 0, 0)
  self.post = SmallBtn(foot, "Post", 40, "Post this boss card to party chat", function() BW:Post() end)
  self.post:SetPoint("RIGHT", -18, 0)
  self.edit = SmallBtn(foot, "Edit", 36, "Edit this boss card", function()
    local dk, i = BW:Current(); UI:OpenBossEditor(dk, i)
  end)
  self.edit:SetPoint("RIGHT", self.post, "LEFT", -2, 0)
  self.foot = foot

  -- Body: scrolling list of rows.
  local sf = CreateFrame("ScrollFrame", nil, f)
  sf:SetPoint("TOPLEFT", 8, -28); sf:SetPoint("BOTTOMRIGHT", -8, 22)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(1, 1)
  sf:SetScrollChild(content)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local maxS = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.max(0, math.min(maxS, (self:GetVerticalScroll() or 0) - delta * 24)))
  end)
  self.scroll, self.content = sf, content
  if ns.Links then ns.Links:Enable(content) end   -- ability names: highlighted, real tooltips
  self.rows = {}

  -- Resize grip (bottom-right).
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14); grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() if not (S() and S().locked) then f:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); BW:SaveGeometry(); BW:Layout() end)
  self.grip = grip
  f:SetScript("OnSizeChanged", function() BW:Layout() end)

  self:ApplyGeometry()
end

function BW:Row(n)
  local row = self.rows[n]
  if row then return row end
  local c = self.content
  row = {}
  row.bar = c:CreateTexture(nil, "BACKGROUND")
  row.edge = c:CreateTexture(nil, "BORDER")
  row.tag = c:CreateFontString(nil, "OVERLAY"); row.tag:SetJustifyH("LEFT"); row.tag:SetWordWrap(false)
  row.text = c:CreateFontString(nil, "OVERLAY"); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(true)
  self.rows[n] = row
  return row
end

function BW:SetFontSize(px)
  local s = S()
  s.fontSize = math.max(self.FONT_MIN, math.min(self.FONT_MAX, math.floor(tonumber(px) or 12)))
  self:Refresh()
end

-- Place rows top to bottom at the current width and text size.
function BW:Layout()
  if not self.frame or not self.items then return end
  local K = Kit()
  local px = (S() and S().fontSize) or 12
  local width = math.max(100, (self.scroll:GetWidth() or 300) - 4)
  local tagW = math.floor(px * 3.3 + 0.5)
  local y = 0
  for n, item in ipairs(self.items) do
    local row = self:Row(n)
    row.tag:SetFont(K.FONT, px - 1, "")
    row.text:SetFont(K.FONT, px, "")
    row.tag:ClearAllPoints(); row.text:ClearAllPoints(); row.bar:ClearAllPoints(); row.edge:ClearAllPoints()
    local gapTop = (item.first and n > 1) and 6 or 0
    y = y + gapTop
    row.tag:SetPoint("TOPLEFT", self.content, "TOPLEFT", 6, -y - 3)
    row.tag:SetWidth(tagW)
    row.text:SetPoint("TOPLEFT", self.content, "TOPLEFT", tagW + 10, -y - 3)
    row.text:SetWidth(width - tagW - 12)
    row.tag:SetText(item.tag); row.text:SetText(item.text)
    local h = math.max(px + 2, (row.text:GetStringHeight() or px)) + 6
    if item.job then
      local a = K.C.accent
      row.bar:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
      row.bar:SetSize(width, h)
      row.bar:SetColorTexture(a[1], a[2], a[3], item.backup and 0.07 or 0.14); row.bar:Show()
      row.edge:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
      row.edge:SetSize(3, h)
      row.edge:SetColorTexture(a[1], a[2], a[3], 1); row.edge:Show()
    else
      row.bar:Hide(); row.edge:Hide()
    end
    row.tag:Show(); row.text:Show()
    y = y + h
  end
  for n = #self.items + 1, #self.rows do
    local row = self.rows[n]
    row.tag:Hide(); row.text:Hide(); row.bar:Hide(); row.edge:Hide()
  end
  self.content:SetSize(width, math.max(1, y))
end

function BW:Refresh()
  if not self.frame then return end
  local K = Kit()
  local HEX = K.HEX
  local s = S()
  local BC = ns.BossCards
  local dk, i, inside = self:Current()
  local bosses = BC:Bosses(dk)
  local boss = bosses[i]
  local px = s.fontSize or 12
  self.title:SetFont(K.FONT, px + 1, "")
  if not boss then
    self.title:SetText(HEX.muted .. "No boss cards for this dungeon|r")
    self.items = {}
    self:Layout()
    return
  end
  local killed = inside and BC.state.killed and BC.state.killed[i]
  self.title:SetText(boss.name .. HEX.muted .. "  " .. i .. "/" .. #bosses
    .. (killed and "  (defeated)" or "") .. (BC:IsEdited(dk, i) and "  (edited)" or "") .. "|r")
  local role = BC:MyRole()
  self.roleBtn.text:SetText(s.showAll and "All roles" or ("My role: " .. role))
  self.roleBtn:SetWidth(s.showAll and 64 or 92)
  local items = {}
  local firstJob, firstLine = true, true
  for _, r in ipairs(self:Rows(dk, i, role, s.showAll, inside)) do
    if r.kind == "lust" then
      items[#items + 1] = { job = true, tag = HEX.warn .. "LUST|r", text = HEX.text .. r.text .. "|r" }
    elseif r.kind == "job" then
      items[#items + 1] = { job = true, backup = r.backup, first = firstJob,
        tag = HEX.accent .. (r.backup and "BACKUP" or "YOU") .. "|r", text = HEX.text .. BC:Decorate(dk, r.text) .. "|r" }
      firstJob = false
    else
      items[#items + 1] = { first = firstLine, tag = ROLE_TAG[r.role] or r.role,
        text = BC:Decorate(dk, r.text) .. (r.nv and (HEX.muted .. " (unconfirmed)|r") or "") }
      firstLine = false
    end
  end
  self.items = items
  self:Layout()
  self:ApplyCombatFade()
end

function BW:ApplyCombatFade()
  if not self.frame then return end
  local s = S()
  local fade = s and s.fadeInCombat ~= false and self.inCombat
  self.frame:SetAlpha(fade and 0.35 or 1)
end

function BW:Post()
  local dk, i = self:Current()
  UI:SendLines(ns.BossCards:ChatLines(dk, i), "Boss card")
end

function BW:Show()
  self:Build()
  self.closedByUser = nil
  if ns.Tracker then ns.Tracker:Acquire("bosswindow") end
  self.frame:Show()
  self:Refresh()
end

function BW:Hide(byUser)
  if byUser then self.closedByUser = true end
  if self.frame then self.frame:Hide() end
  if ns.Tracker then ns.Tracker:Release("bosswindow") end
end

function BW:Toggle()
  if self.frame and self.frame:IsShown() then self:Hide(true) else self:Show() end
end

function BW:IsShown() return self.frame and self.frame:IsShown() or false end

-- /kc boss [dungeon name]
function BW:Open(dk)
  if dk then self.view = { dk = dk, index = 1 } end
  self:Show()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns:On("BOSS_DUNGEON_ENTERED", function()
  BW.view = {}
  local s = S()
  if s and s.autoOpen ~= false then BW:Show() end
end)
ns:On("BOSS_DUNGEON_LEFT", function()
  BW.closedByUser = nil
  if BW:IsShown() then BW:Hide() end
end)
ns:On("BOSS_CARD_CHANGED", function() if BW:IsShown() then BW:Refresh() end end)
ns:On("BOSS_NOTES_CHANGED", function()
  if BW:IsShown() then BW:Refresh() end
  if UI.currentTab == "dungeons" and UI.QueueRefresh then UI:QueueRefresh() end
end)
ns:On("LIVE_ROSTER_CHANGED", function() if BW:IsShown() then BW:Refresh() end end)
ns:On("SETTINGS_CHANGED", function() if BW:IsShown() then BW:Refresh() end end)
ns:On("BOSS_COMBAT", function(on) BW.inCombat = on; BW:ApplyCombatFade() end)
ns:On("LUST_CHANGED", function() if BW:IsShown() then BW:Refresh() end end)
ns:On("ASSIGNMENTS_CHANGED", function() if BW:IsShown() then BW:Refresh() end end)

---------------------------------------------------------------------------
-- Editor (shared by the window and the Dungeons tab)
---------------------------------------------------------------------------
function UI:OpenBossEditor(dk, i)
  local BC = ns.BossCards
  local boss = BC:Boss(dk, i)
  if not boss then return end
  local K = self.Kit
  local C, HEX = K.C, K.HEX
  local e = self.bossEditor
  if not e then
    e = CreateFrame("Frame", "KeystoneCommandBossEditor", UIParent, "BackdropTemplate")
    K.Skin(e, C.bg, C.border)
    e:SetSize(520, 330); e:SetPoint("CENTER"); e:SetFrameStrata("DIALOG")
    e:SetMovable(true); e:EnableMouse(true); e:RegisterForDrag("LeftButton")
    e:SetScript("OnDragStart", e.StartMoving); e:SetScript("OnDragStop", e.StopMovingOrSizing)
    e.title = K.Text(e, 13, C.text); e.title:SetPoint("TOPLEFT", 12, -10); e.title:SetPoint("RIGHT", -12, 0)
    e.title:SetWordWrap(false)
    e.help = K.Text(e, 10, C.muted); e.help:SetPoint("TOPLEFT", 12, -30); e.help:SetPoint("RIGHT", -12, 0)
    e.help:SetText("One note per line, starting with ALL:, TANK:, HEAL: or DPS:. Lines without a role count as ALL. "
      .. "Keep each one a short instruction: what to do, not why.")
    local box = CreateFrame("Frame", nil, e, "BackdropTemplate")
    K.Skin(box, C.panel, C.border)
    box:SetPoint("TOPLEFT", 12, -60); box:SetPoint("BOTTOMRIGHT", -12, 44)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6); sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFont(K.FONT, 12, ""); eb:SetWidth(450)
    eb:SetScript("OnEscapePressed", function() e:Hide() end)
    sf:SetScrollChild(eb)
    e.edit = eb
    e.note = K.Text(e, 10, C.warn); e.note:SetPoint("BOTTOMLEFT", 12, 16); e.note:SetWordWrap(false)
    e.save = K.Button(e, "Save", 80, 24, function()
      BC:SetEdit(e.dk, e.i, e.edit:GetText()); e:Hide()
    end)
    e.save:SetPoint("BOTTOMRIGHT", -12, 10)
    e.cancel = K.Button(e, "Cancel", 80, 24, function() e:Hide() end)
    e.cancel:SetPoint("RIGHT", e.save, "LEFT", -6, 0)
    e.reset = K.Button(e, "Reset to default", 130, 24, function()
      e.edit:SetText(BC:DefaultText(e.dk, e.i))
    end)
    e.reset:SetPoint("RIGHT", e.cancel, "LEFT", -6, 0)
    if UISpecialFrames then table.insert(UISpecialFrames, "KeystoneCommandBossEditor") end
    self.bossEditor = e
  end
  e.dk, e.i = dk, i
  local _, edited, changed = BC:Lines(dk, i)
  e.title:SetText("Edit boss card: " .. boss.name .. HEX.muted .. "  (" .. (ns.Dungeons.list[dk] and ns.Dungeons.list[dk].name or dk) .. ")|r")
  e.note:SetText(changed and "The built-in card has been updated since you edited this one. Reset to see the new version."
    or (edited and HEX.muted .. "Your edited version. Reset to default to undo.|r" or ""))
  e.edit:SetText(BC:EditText(dk, i))
  e:Show()
  e.edit:SetFocus()
end

---------------------------------------------------------------------------
-- Dungeons tab: boss cards under the dungeon picker
---------------------------------------------------------------------------
function UI:RenderBossCards(L, dk)
  local BC = ns.BossCards
  local bosses = BC:Bosses(dk)
  if #bosses == 0 then return end
  local HEX = self.Kit.HEX
  L:Header("Bosses")
  L:Add(HEX.muted .. "Role notes for each boss. Click a boss to fold it. Edits are yours and survive updates.|r", { size = 10, gap = 3 })
  local role = BC:MyRole()
  for i, boss in ipairs(bosses) do
    local key = "boss:" .. dk .. ":" .. i
    local open = self:IsOpen(key, true)
    local lines, edited, changed = BC:Lines(dk, i)
    L:Add((open and "- " or "+ ") .. HEX.accent .. i .. ". " .. boss.name .. "|r"
      .. (edited and (HEX.muted .. "  (edited)|r") or "") .. (changed and (HEX.warn .. "  default updated|r") or ""), {
      size = 12, gap = 2, onClick = function() UI:SetOpen(key, not open) end,
      tooltip = open and "Click to fold" or "Click to show this boss",
    })
    if open then
      for _, l in ipairs(BC:Ordered(lines, role, true)) do
        L:Add((ROLE_TAG[l.role] or l.role) .. "  " .. BC:Decorate(dk, l.text) .. (l.nv and (HEX.warn .. " [unconfirmed]|r") or ""),
          { indent = 10, size = 11, gap = 1 })
      end
      L:Add(HEX.accent .. "> Edit|r", { indent = 10, size = 10, gap = 1,
        onClick = function() UI:OpenBossEditor(dk, i) end, tooltip = "Change this card. Reset to default any time." })
      L:Add(HEX.accent .. "> Post to chat|r", { indent = 10, size = 10, gap = 1,
        onClick = function() UI:SendLines(BC:ChatLines(dk, i), "Boss card") end,
        tooltip = "Sends:\n" .. table.concat(BC:ChatLines(dk, i), "\n") })
      L:Add(HEX.accent .. "> Open in the boss window|r", { indent = 10, size = 10, gap = 4,
        onClick = function() BW.view = { dk = dk, index = i }; BW:Show() end })
    end
  end
end
