-- Ensemble / BossWindow.lua
-- The boss-card pop-up: a small, movable, resizable window with its own text size that
-- opens when you enter a Season dungeon and turns to the next boss when one dies. Shows
-- your role's lines first (or every role), your kick / dispel jobs from the plan in a
-- highlighted block, page arrows, an editor and "post to chat". Also holds the shared boss
-- card editor (UI:OpenBossEditor).
--
-- 1.7.0: between bosses it shows the trash section on the way to the next one ("On the way to
-- Galvazzt"): your rows on top, the other critical and high rows, the rest named on a
-- "+ N more" line. From the guides' sections with your changes (Walkthrough.lua); the boss
-- card takes over on the pull, as before. Nothing here reads combat data.
local _, ns = ...

local UI = ns.UI
local BW = {}
ns.BossWindow = BW

-- 250 wide at least: the footer's left group (role button up to 92 + A- A+) and right group
-- (Edit, Post, the grip) keep a gap at the smallest size (240 let Edit overlap A+ by 4px).
local MIN_W, MIN_H, MAX_W, MAX_H = 250, 120, 760, 640
BW.MIN_W, BW.MIN_H = MIN_W, MIN_H
BW.FONT_MIN, BW.FONT_MAX = 9, 20

local ROLE_TAG = {
  ALL = "|cffb4b8c4ALL|r", TANK = "|cff6fa8ffTANK|r", HEAL = "|cff61cc78HEAL|r", DPS = "|cffee6161DPS|r",
}
BW.ROLE_TAG = ROLE_TAG

local function S() return ns.db and ns.db.settings and ns.db.settings.bossWindow end
local function Kit() return UI.Kit end

---------------------------------------------------------------------------
-- What the window is showing: the dungeon you're in (and its current boss), or a dungeon
-- picked by hand (the Dungeon tab's "Open boss cards" or a card's "Open in the boss window",
-- or Settings > Boss cards > "Open the boss window" outside a dungeon).
---------------------------------------------------------------------------
BW.view = {}

-- Returns dungeon, boss index, inside (you're in that dungeon), phase ("boss" = the card,
-- "trash" = the section on the way to that boss). Opened by hand it starts on a boss card;
-- the arrows page through the trash sections too.
function BW:Current()
  local BC = ns.BossCards
  if BC.state.dk then return BC.state.dk, BC.state.index or 1, true, BC:Phase() end
  if self.view.dk then
    local i = self.view.index or BC:Order(self.view.dk)[1] or 1
    local phase = (self.view.phase == "trash" and BC:HasTrashPage(self.view.dk, i)) and "trash" or "boss"
    return self.view.dk, i, false, phase
  end
  local ok, dk = pcall(ns.GetEffectiveDungeon, ns, false)
  dk = ok and dk or (ns.Dungeons and ns.Dungeons.order[1])
  return dk, BC:Order(dk)[1] or 1, false, "boss"   -- the first boss in your order
end

function BW:Step(d)
  local BC = ns.BossCards
  local dk, i, inside, phase = self:Current()
  if inside then BC:Step(d); return end
  local p = BC:PageFrom(dk, i, phase, d)
  if not p then return end
  self.view = { dk = dk, index = p.index, phase = p.phase }
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
-- The trash on the way to a boss (1.7.0): rows of
--   { kind = "lust" | "mine" | "row" | "more" | "note" | "next", tag, text, backup }
-- "mine" rows (the casts you own in the group's plan) come first, then the other critical and
-- high rows, then one "+ N more" line naming the rest with who takes each. Alone (or before
-- specs are read) there are no names: the section still says what happens here. The role
-- button filters like the boss card's; a critical row always shows.
---------------------------------------------------------------------------
local TRASH_TAG = {
  interrupt = "KICK", dispel_bleed = "BLEED", stop = "STOP", aoe_stop = "STOP", purge = "PURGE", soothe = "SOOTHE", freedom = "FREE",
  external_defensive = "TANK", group_defensive = "GROUP", knockback = "KNOCK", root = "ROOT",
}
local SEV_RANK = { critical = 1, high = 2, medium = 3, low = 4 }
local BIG = { critical = true, high = true }

local function TrashTag(q)
  if ns.Dungeons:CategoryOf(q) == "tank" then return "TANK" end
  if TRASH_TAG[q.need] then return TRASH_TAG[q.need] end
  if tostring(q.need):find("^dispel_") then return "DISPEL" end
  return (ns.UD:CapShort(q.need) or "?"):upper():sub(1, 6)
end

local function ShortNames(owners, me)
  local t = {}
  for _, w in ipairs(owners) do
    if w.index ~= me then
      local hex = w.class and select(4, ns.Util.ClassColor(w.class)) or "|cffffffff"
      t[#t + 1] = hex .. UI.ShortLabel(ns.Assignments.ShortName(w.label)) .. "|r"
    end
  end
  return t
end

function BW:TrashRows(dk, i, role, all)
  local WT, BC, AS = ns.Walkthrough, ns.BossCards, ns.Assignments
  local HEX = Kit().HEX
  local rows = {}
  local st = WT and WT:TrashStep(dk, i)
  if not st then return rows end
  for _, x in ipairs(WT:LustAt(dk, st)) do
    rows[#rows + 1] = { kind = "lust", text = "Bloodlust" .. (x.use.note and (": " .. x.use.note) or " here") }
  end
  -- The group's plan (your party, or just you). Alone, nothing is "yours": no names.
  local plan, r = BC:Plan(dk)
  local me
  for idx, m in ipairs(r and r.members or {}) do if m.isPlayer then me = idx end end
  local grouped = plan and r and #r.members > 1 and me ~= nil
  local rowOf = {}
  if grouped then
    for _, e in ipairs(AS:Rows(plan)) do rowOf[e.row.req.id] = e end
  end
  local reqs = {}
  for _, q in ipairs(st.reqs) do reqs[#reqs + 1] = q end
  table.sort(reqs, function(a, b)
    local x, y = SEV_RANK[a.severity] or 9, SEV_RANK[b.severity] or 9
    if x ~= y then return x < y end
    return tostring(a.id) < tostring(b.id)
  end)
  local mine, big, more, otherRoles = {}, {}, {}, 0
  for _, q in ipairs(reqs) do
    local e = rowOf[q.id]
    local owners = e and AS.Owners(e.row) or {}
    local isMine, isBackup = false, e and e.row.backup and e.row.backup.index == me
    for _, w in ipairs(owners) do if w.index == me then isMine = true end end
    -- Rows anyone who has the ability answers (a stop, a freedom, tank defensives) aren't one
    -- player's job: they stay ordinary rows, marked "you can answer it" (as Your brief says),
    -- instead of a "yours with ..." job for every provider (1.7.0 review nit).
    local youCan = false
    if e and e.kind == "other" then youCan = isMine and q.need ~= "stop"; isMine = false end
    -- Nobody can kick or dispel it: its owners stop it instead (1.7.0 review, R1).
    local instead = e and (e.kind == "kick" or e.kind == "dispel") and AS.StopsInstead(e.row)
    local insteadText = instead and (HEX.muted .. " (instead of " .. AS.InsteadOf(e.kind, e.kind == "dispel" and e.row.type or nil) .. ")|r") or ""
    local tag = instead and "STOP" or TrashTag(q)
    local wanted = all or isMine or youCan or q.severity == "critical" or UI:WalkRoleWants(role, q)
    local cast = ns.Analysis.Decorate(q.source or "", q.need, q.dungeon)
    local sev = BIG[q.severity] and (UI.SevTag(q.severity) .. "  ") or ""
    if not wanted then
      otherRoles = otherRoles + 1
    elseif isMine then
      local with = ShortNames(owners, me)
      local tail = HEX.accent .. "  yours|r" .. insteadText
      if e.kind == "dispel" and not instead then
        tail = tail .. (e.row.backup and (HEX.muted .. ", backup |r" .. table.concat(ShortNames({ e.row.backup }, me), ""))
          or (q.severity == "critical" and (HEX.warn .. ", no backup: don't miss one|r") or ""))
      elseif #with > 0 then
        tail = tail .. HEX.muted .. " with |r" .. table.concat(with, HEX.muted .. ", |r")
      end
      mine[#mine + 1] = { kind = "mine", tag = tag, text = sev .. cast .. tail }
    elseif TrashTag(q) == "TANK" and role == "TANK" and not BIG[q.severity] then
      -- Your own role's part of the section stays a row: the tank busters, for a tank.
      big[#big + 1] = { kind = "row", tag = "TANK", text = HEX.muted .. "Defensive: |r" .. cast }
    elseif BIG[q.severity] then
      local tail = ""
      if grouped and e then
        local names = ShortNames(owners, nil)
        if e.kind == "other" and q.need == "stop" then tail = #names > 0 and (HEX.muted .. "  anyone with CC|r") or (HEX.bad .. "  nobody here can|r")
        elseif #names > 0 then tail = "  " .. table.concat(names, HEX.muted .. " + |r") .. insteadText
          .. ((e.kind == "dispel" and not instead and not e.row.backup and q.severity == "critical") and (HEX.warn .. " no backup|r") or "")
          .. (isBackup and (HEX.accent .. "  you back it up|r") or "")
          .. (youCan and (HEX.accent .. "  you can answer it|r") or "")
        else tail = HEX.bad .. "  nobody here can|r" end
      end
      big[#big + 1] = { kind = "row", tag = tag, text = sev .. cast .. tail }
    else
      local who = ""
      if grouped and e then
        local names = AS:OwnerNames(e, function(l) return UI.ShortLabel(AS.ShortName(l)) end)
        who = names and (" (" .. names .. (instead and (", instead of " .. AS.InsteadOf(e.kind, e.kind == "dispel" and e.row.type or nil)) or "") .. ")") or " (nobody)"
      end
      more[#more + 1] = tag:lower() .. " " .. UI.ReqNames(q) .. who .. (isBackup and " [you back it up]" or "") .. (youCan and " [you can answer it]" or "")
    end
  end
  for _, x in ipairs(mine) do rows[#rows + 1] = x end
  for _, x in ipairs(big) do rows[#rows + 1] = x end
  if #mine + #big == 0 and (#more > 0 or otherRoles > 0) then
    rows[#rows + 1] = { kind = "note", text = HEX.muted .. "Nothing critical or high here" .. (otherRoles > 0 and " for your role" or "") .. ".|r" }
  end
  if #more > 0 then
    rows[#rows + 1] = { kind = "more", text = HEX.accent .. "+ " .. #more .. " more:|r " .. HEX.muted .. table.concat(more, ", ") .. "|r" }
  end
  if otherRoles > 0 then
    rows[#rows + 1] = { kind = "note", text = HEX.muted .. "+ " .. otherRoles .. " for other roles (the role button shows them).|r" }
  end
  if #(st.hidden or {}) > 0 then
    local names = {}
    for _, q in ipairs(st.hidden) do names[#names + 1] = AS.CastName(q) end
    rows[#rows + 1] = { kind = "note", text = HEX.muted .. #st.hidden .. " hidden by you: " .. table.concat(names, ", ") .. "|r" }
  end
  -- What comes next: the boss, and whether Bloodlust is planned on it.
  local boss = BC:Boss(dk, i)
  local lust = self:LustRows(dk, "b" .. i)
  rows[#rows + 1] = { kind = "next", text = HEX.muted .. "Next: |r" .. (boss and boss.name or "?") .. HEX.muted .. " \194\183 "
    .. (lust[1] and (lust[1].text:gsub("^Bloodlust: ", "Bloodlust ")) or "no Bloodlust planned") .. "|r" }
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
  local f = CreateFrame("Frame", "EnsembleBossFrame", UIParent, "BackdropTemplate")
  self.frame = f
  K.Skin(f, C.bg, C.border)
  -- Over the main window (it was MEDIUM, under it), e.g. when opened from the Dungeon tab.
  f:SetFrameStrata(UI.OVER_WINDOW_STRATA or "HIGH")
  f:SetFrameLevel(UI.OVER_WINDOW_LEVEL or 200)
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
  self.close = SmallBtn(head, "x", 20, "Close (reopen from the Dungeon tab or Settings > Boss cards)", function() BW:Hide(true) end)
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
    local dk, i, _, phase = BW:Current()
    if phase == "trash" then UI:OpenTrashEditor(dk, i) else UI:OpenBossEditor(dk, i) end
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
    -- A wide row (a "+ N more" line, "Next:") has no tag and starts at the left edge.
    local left = item.wide and 6 or (tagW + 10)
    row.text:SetPoint("TOPLEFT", self.content, "TOPLEFT", left, -y - 3)
    row.text:SetWidth(width - left - 2)
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
  local dk, i, inside, phase = self:Current()
  local bosses = BC:Bosses(dk)
  local boss = bosses[i]
  local px = s.fontSize or 12
  self.title:SetFont(K.FONT, px + 1, "")
  if not boss then
    self.title:SetText(HEX.muted .. "No boss cards for this dungeon|r")
    self.items = {}
    self.shownPhase = nil
    self:Layout()
    return
  end
  local role = BC:MyRole()
  self.roleBtn.text:SetText(s.showAll and "All roles" or ("My role: " .. role))
  self.roleBtn:SetWidth(s.showAll and 64 or 92)
  self.shownPhase = phase
  local trash = phase == "trash"
  -- Posting a trash section isn't offered (the Plan tab's posts cover the trash); Edit opens
  -- the section's editor instead of the card's.
  self.post:SetShown(not trash)
  self.edit.tooltip = trash and "Hide the trash your group skips, or move a row to another boss's section" or "Edit this boss card"
  self.prev.tooltip, self.next.tooltip = "Previous page (the trash before a boss, then the boss)", "Next page (the trash before a boss, then the boss)"
  if trash then
    self.title:SetText(HEX.muted .. "On the way to |r" .. boss.name .. HEX.muted .. "  " .. BC:Position(dk, i) .. "/" .. #bosses .. "|r")
    local items = {}
    for _, r in ipairs(self:TrashRows(dk, i, role, s.showAll)) do
      if r.kind == "lust" then
        items[#items + 1] = { job = true, tag = HEX.warn .. "LUST|r", text = HEX.text .. r.text .. "|r" }
      elseif r.kind == "mine" then
        items[#items + 1] = { job = true, tag = HEX.accent .. r.tag .. "|r", text = r.text }
      elseif r.kind == "row" then
        items[#items + 1] = { tag = HEX.text .. r.tag .. "|r", text = r.text }
      else
        items[#items + 1] = { first = r.kind == "next", wide = true, tag = "", text = r.text }
      end
    end
    self.items = items
    self:Layout()
    self:ApplyCombatFade()
    return
  end
  local killed = inside and BC.state.killed and BC.state.killed[i]
  self.title:SetText(boss.name .. HEX.muted .. "  " .. BC:Position(dk, i) .. "/" .. #bosses
    .. (killed and "  (defeated)" or "") .. (BC:IsEdited(dk, i) and "  (edited)" or "") .. "|r")
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
  if ns.Tracker then ns.Tracker:Acquire("bosswindow") end
  self.frame:Show()
  self:Refresh()
  if ns.Tour then ns.Tour:PumpTips() end   -- the first time: a tip on the window
end

function BW:Hide(byUser)
  if self.frame then self.frame:Hide() end
  if ns.Tracker then ns.Tracker:Release("bosswindow") end
end

function BW:Toggle()
  if self.frame and self.frame:IsShown() then self:Hide(true) else self:Show() end
end

function BW:IsShown() return self.frame and self.frame:IsShown() or false end

-- Open the window on a given dungeon's cards.
function BW:Open(dk)
  if dk then self.view = { dk = dk } end   -- index unset: the first boss in your order
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
  if BW:IsShown() then BW:Hide() end
end)
-- Change events arrive in bursts (a roster update, then the plan, then a setting); one rebuild
-- next frame covers them all, like UI:QueueRefresh. Paging and the window's own buttons still
-- redraw at once.
function BW:QueueRefresh()
  if self.refreshQueued or not self:IsShown() then return end
  self.refreshQueued = true
  C_Timer.After(0, function()
    BW.refreshQueued = false
    if BW:IsShown() then BW:Refresh() end
  end)
end
ns:On("BOSS_CARD_CHANGED", function() BW:QueueRefresh() end)
ns:On("BOSS_NOTES_CHANGED", function()
  BW:QueueRefresh()
  if UI.currentTab == "dungeons" and UI.QueueRefresh then UI:QueueRefresh() end
end)
ns:On("LIVE_ROSTER_CHANGED", function() BW:QueueRefresh() end)
ns:On("SETTINGS_CHANGED", function() BW:QueueRefresh() end)
ns:On("BOSS_COMBAT", function(on) BW.inCombat = on; BW:ApplyCombatFade() end)
ns:On("LUST_CHANGED", function() BW:QueueRefresh() end)
ns:On("BOSS_ORDER_CHANGED", function() BW:QueueRefresh() end)
ns:On("ASSIGNMENTS_CHANGED", function() BW:QueueRefresh() end)
ns:On("TRASH_CHANGED", function() BW:QueueRefresh() end)

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
    e = CreateFrame("Frame", "EnsembleBossEditor", UIParent, "BackdropTemplate")
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
    if UISpecialFrames then table.insert(UISpecialFrames, "EnsembleBossEditor") end
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
