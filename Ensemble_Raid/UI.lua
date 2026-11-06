-- Ensemble Raid (test build) / UI.lua
-- Raid mode inside Ensemble's own window: a Mythic+ / Raid switch in the header (Auto by
-- default), raid tabs (Roster, Bosses, Plan, Settings) in place of the Mythic+ tabs, and three
-- pages built from Ensemble's widget kit (UI.Kit). Ensemble's UI:SetTab and UI:Refresh are wrapped
-- so the core never draws a Mythic+ page while Raid is on; Mythic+ mode is untouched.

local _, R = ...
if R.disabled then return end
local ns = R.ns
local UI = ns.UI
local UD = ns.UD
local D = R.Data

local RUI = {}
R.UI = RUI

local K -- UI.Kit, resolved when the window is built
local HEX
local RAID_TABS = {
  { key = "roster", label = "Roster" },
  { key = "bosses", label = "Bosses" },
  { key = "plan", label = "Plan" },
  { key = "settings", label = "Settings" },
}
RUI.TABS = RAID_TABS
local SPEC_TEX = "|T%s:14:14:0:0:64:64:5:59:5:59|t"

local function Tag(status)
  if status == "ok" then return HEX.good .. "OK|r" elseif status == "miss" then return HEX.bad .. "MISSING|r" end
  return HEX.warn .. "THIN|r"
end
RUI.Tag = function(s) HEX = HEX or UI.Kit.HEX; return Tag(s) end

local function ClassName(m)
  local hex = select(4, ns.Util.ClassColor(m.class)) or ""
  return hex .. (m.name or "?") .. "|r"
end
local function SpecIcon(specID)
  local _, icon = ns.API.GetSpecInfoByID(specID)
  return icon and string.format(SPEC_TEX, tostring(icon)) or ""
end
local function DiffTag(d)
  if d == "H" then return HEX.warn .. "HEROIC|r " elseif d == "M" then return HEX.bad .. "MYTHIC|r " end
  return ""
end
local ROLE_WORD = { TANK = "TANK", HEALER = "HEAL", DAMAGER = "" }

-- Your own role for the learner view's "Auto" filter.
function RUI:MyRole()
  local spec = ns.API.GetPlayerSpecID()
  local p = spec and UD:GetSpec(spec)
  if p and p.role then return p.role end
  local r = UnitGroupRolesAssigned and R.Plain(UnitGroupRolesAssigned("player"))
  if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r end
  return "DAMAGER"
end
function RUI:ViewRole()
  local r = R.db.role
  if r == "AUTO" then return self:MyRole(), true end
  return r, false
end
-- Does an item's `who` show for this role filter?
function RUI:ShowsFor(who, role)
  if role == "ALL" or who == "ALL" then return true end
  if who == role then return true end
  if (who == "MELEE" or who == "RANGED") and role == "DAMAGER" then return true end
  return false
end

---------------------------------------------------------------------------
-- Chrome: the mode switch and the raid tabs in Ensemble's header
---------------------------------------------------------------------------
function RUI:Attach()
  if self.attached or not UI.frame then return end
  self.attached = true
  K, HEX = UI.Kit, UI.Kit.HEX
  local wn = UI.whatsNewBtn
  local header = wn and wn:GetParent() or UI.frame
  self.header = header
  local mb = K.FlatButton(header, "Mythic+", 56, 24, function(btn) RUI:OpenModeMenu(btn) end)
  if wn then mb:SetPoint("RIGHT", wn, "LEFT", -4, 0) else mb:SetPoint("TOPRIGHT", -240, -8) end
  self.modeBtn = mb
  self.tabButtons = {}
  local first = UI.tabButtons and UI.tabButtons.composition
  local prev
  for _, t in ipairs(RAID_TABS) do
    local b = K.Tab(header, t.label, function() UI:SetTab(t.key) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
    elseif first and first.GetPoint then
      local p = { first:GetPoint(1) }
      if p[1] then b:SetPoint(unpack(p)) else b:SetPoint("LEFT", header, "LEFT", 200, 0) end
    else b:SetPoint("LEFT", header, "LEFT", 200, 0) end
    b:Hide()
    self.tabButtons[t.key] = b
    prev = b
  end
  self:BuildContainer()
  self:SyncModeButton()
end

function RUI:SyncModeButton()
  local b = self.modeBtn
  if not b then return end
  local mode = R:Mode()
  b.text:SetText(mode == "raid" and "Raid" or "Mythic+")
  local auto = R.db.mode == "auto"
  local why = R:AutoMode() == "raid" and "you're in a raid group or a raid or Lair" or "you're not in a raid"
  b.tooltip = string.format("Mode: %s (%s). Click to choose Auto, Mythic+ or Raid.%s",
    mode == "raid" and "Raid" or "Mythic+", auto and ("Auto: " .. why) or "picked by hand until you leave a group",
    "\nRaid is a test build (Ensemble_Raid folder).")
end

function RUI:OpenModeMenu(anchor)
  local m = R.db.mode
  UI:ShowMenu(anchor, {
    { text = "Auto (now " .. (R:AutoMode() == "raid" and "Raid" or "Mythic+") .. ")", selected = m == "auto", onClick = function() R:SetMode("auto") end,
      tooltip = "Raid while you're in a raid group or inside one of the season's raids or Lairs; Mythic+ otherwise." },
    { text = "Mythic+", selected = m == "mplus", onClick = function() R:SetMode("mplus") end },
    { text = "Raid", selected = m == "raid", onClick = function() R:SetMode("raid") end,
      tooltip = "Picked by hand: stays until you leave a group, then Auto again." },
  })
end

-- Show the tab set for the current mode.
function RUI:ApplyMode()
  if not UI.frame then return end
  self:Attach()
  self:SyncModeButton()
  local raid = R:IsRaidMode()
  for _, b in pairs(UI.tabButtons or {}) do b:SetShown(not raid) end
  for _, b in pairs(self.tabButtons) do b:SetShown(raid) end
  if raid then
    UI:SetTab(R.db.tab)
  else
    self.container:Hide()
    UI:SetTab(self.coreTab or ns.db.lastTab or "composition")
  end
end

function RUI:SetTab(key)
  self:Attach()
  local valid = false
  for _, t in ipairs(RAID_TABS) do if t.key == key then valid = true end end
  if not valid then key = R.db.tab end
  if key ~= "settings" and key ~= "roster" and key ~= "bosses" and key ~= "plan" then key = "roster" end
  if UI.currentTab and UI.currentTab ~= "settings" then self.coreTab = UI.currentTab end
  R.db.tab = key
  self.tab = key
  if ns.Tracker then ns.Tracker:Disable() end
  for _, p in pairs(UI.pages or {}) do p:Hide() end
  for _, b in pairs(UI.tabButtons or {}) do b:Hide() end
  for k, b in pairs(self.tabButtons) do b:Show(); b:SetActive(k == key) end
  if key == "settings" then
    self.container:Hide()
    UI.currentTab = "settings"
    if UI.pages.settings then UI.pages.settings:Show() end
  else
    self.container:Show()
    for k, p in pairs(self.pages) do p:SetShown(k == key) end
  end
  self:Refresh()
end

function RUI:HideRaid()
  if not self.attached then return end
  self.container:Hide()
  for _, b in pairs(self.tabButtons) do b:Hide() end
  for _, b in pairs(UI.tabButtons or {}) do b:Show() end
  self:SyncModeButton()
end

function RUI:Queue()
  if self.queued or not (UI.frame and UI.frame:IsShown() and R:IsRaidMode()) then return end
  self.queued = true
  C_Timer.After(0, function() RUI.queued = false; if R:IsRaidMode() then RUI:Refresh() end end)
end

function RUI:Refresh()
  if not (UI.frame and UI.frame:IsShown()) then return end
  local ok, err = pcall(function()
    if RUI.tab == "settings" then UI:RefreshSettings(); return end
    RUI:RefreshContext()
    if RUI.tab == "roster" then RUI:RefreshRoster()
    elseif RUI.tab == "bosses" then RUI:RefreshBosses()
    elseif RUI.tab == "plan" then RUI:RefreshPlan() end
  end)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- The container: context bar (raid, difficulty, boss) over the three pages
---------------------------------------------------------------------------
local function Panel(parent, left, width)
  local p = K.Panel(parent)
  if left then
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -4)
    p:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 12, 12)
    p:SetWidth(width)
  else
    p:SetPoint("TOPLEFT", width, "TOPRIGHT", 12, 0)
    p:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 12)
  end
  p.title = K.Text(p, 13, K.C.text)
  p.title:SetPoint("TOPLEFT", 12, -10)
  p.title:SetPoint("RIGHT", p, "RIGHT", -12, 0)
  p.title:SetWordWrap(false)
  return p
end

function RUI:BuildContainer()
  local c = K.PageFrame(UI.frame)
  self.container = c
  local inst = K.Dropdown(c, 210, 24, function(btn) RUI:OpenInstanceMenu(btn) end)
  inst:SetPoint("TOPLEFT", 12, -8)
  self.instBtn = inst
  self.diffBtns = {}
  for i = 1, 4 do
    local b = K.Button(c, "", 62, 24, function(btn) if btn.diffKey then R:SetDiff(btn.diffKey) end end)
    b:SetPoint("LEFT", i == 1 and inst or self.diffBtns[i - 1], "RIGHT", i == 1 and 8 or 2, 0)
    self.diffBtns[i] = b
  end
  local boss = K.Dropdown(c, 180, 24, function(btn) RUI:OpenBossMenu(btn) end)
  boss:SetPoint("LEFT", self.diffBtns[4], "RIGHT", 8, 0)
  self.bossBtn = boss
  local info = K.Text(c, 11, K.C.muted)
  info:SetPoint("LEFT", boss, "RIGHT", 10, 0)
  info:SetPoint("RIGHT", c, "RIGHT", -12, 0)
  info:SetWordWrap(false)
  self.infoText = info
  self.pages = {}
  for _, key in ipairs({ "roster", "bosses", "plan" }) do
    local p = CreateFrame("Frame", nil, c)
    p:SetPoint("TOPLEFT", 0, -40); p:SetPoint("BOTTOMRIGHT", 0, 0)
    p:Hide()
    self.pages[key] = p
  end
  self:BuildRoster()
  self:BuildBosses()
  self:BuildPlan()
  c:Hide()
end

function RUI:RefreshContext()
  local inst = R:Instance()
  local diff = R:Diff(inst)
  self.instBtn.text:SetText(inst.name .. (inst.kind == "lair" and " (Lair)" or ""))
  for i, b in ipairs(self.diffBtns) do
    local d = inst.diffs[i]
    if d then
      b.diffKey = d
      b.text:SetText(R:DiffLabel(d))
      b:SetActive(d == diff)
      b.tooltip = (d == "LFR" or d == "W") and "Uses Normal's mechanics (Normal is the baseline)." or nil
      b:Show()
    else
      b.diffKey = nil; b:Hide()
    end
  end
  local bk = R:Boss(inst)
  self.bossBtn.text:SetText(D.BOSSES[bk].name)
  local members = R.Roster:Members()
  local c = R.Roster:Counts(members)
  if R.Roster:Source() == "planner" then
    self.infoText:SetText(string.format("Planner: %d players (you're not in a group)", c.total))
  else
    self.infoText:SetText(string.format("%d in group: %d tanks, %d healers, %d DPS", c.total, c.TANK, c.HEALER, c.DAMAGER))
  end
  self.infoText.tip = inst.size
end

function RUI:OpenInstanceMenu(anchor)
  local items = {}
  for _, inst in ipairs(D.INSTANCES) do
    items[#items + 1] = { text = inst.name .. (inst.kind == "lair" and " (Lair)" or ""), selected = inst.key == R.db.instance,
      onClick = function() R:SetInstance(inst.key) end, tooltip = inst.size }
  end
  UI:ShowMenu(anchor, items)
end

function RUI:OpenBossMenu(anchor)
  local inst = R:Instance()
  local items = {}
  for i, bk in ipairs(R:Order(inst)) do
    items[#items + 1] = { text = i .. ". " .. D.BOSSES[bk].name, selected = bk == R:Boss(inst), onClick = function() R:SetBoss(bk) end }
  end
  UI:ShowMenu(anchor, items)
end

---------------------------------------------------------------------------
-- Roster page: the raid by group, and the needs for the chosen boss and difficulty
---------------------------------------------------------------------------
function RUI:BuildRoster()
  local page = self.pages.roster
  local left = Panel(page, true, 430)
  local right = Panel(page, false, left)
  self.rLeft, self.rRight = left, right
  self.rosterList = K.LineList(left, 400, 300):Fill(8, -32, -8, 46)
  self.needsList = K.LineList(right, 400, 300):Fill(8, -32, -8, 46)
  -- Planner controls (shown when you're not in a group).
  local name = K.EditBox(left, 150, 24)
  name:SetPoint("BOTTOMLEFT", 10, 12)
  name.tooltip = "Name (optional)"
  self.plannerName = name
  local add = K.Button(left, "Add player", 100, 24, function(btn) RUI:OpenAddMenu(btn) end)
  add:SetPoint("LEFT", name, "RIGHT", 6, 0)
  add.tooltip = "Pick a spec; the name box is optional. Your planner list is saved for the next time."
  self.addBtn = add
  local clear = K.Button(left, "Clear", 60, 24, function(btn)
    if btn.armed then btn.armed = nil; R.Roster:ClearPlanned() else btn.armed = true; btn.text:SetText("Sure?") end
  end)
  clear:SetPoint("LEFT", add, "RIGHT", 6, 0)
  self.clearBtn = clear
  local copy = K.Button(left, "Copy to planner", 130, 24, function()
    local n = R.Roster:CopyLiveToPlanner(R.Roster:Members())
    ns:Print(string.format("Copied %d players to the raid planner.", n))
  end)
  copy:SetPoint("BOTTOMLEFT", 10, 12)
  copy.tooltip = "Keep this group's names and specs to plan another night without a group."
  self.copyBtn = copy
  local post = K.Button(right, "Post gaps", 90, 22, function() RUI:PostGaps() end)
  post:SetPoint("TOPRIGHT", -10, -6)
  self.postGapsBtn = post
  local prev = K.Button(right, "Previous boss", 120, 24, function() R:StepBoss(-1) end)
  prev:SetPoint("BOTTOMLEFT", 10, 12)
  local nextB = K.Button(right, "Next boss", 100, 24, function() R:StepBoss(1) end)
  nextB:SetPoint("LEFT", prev, "RIGHT", 6, 0)
  self.prevBtn, self.nextBtn = prev, nextB
end

function RUI:OpenAddMenu(anchor)
  local items = {}
  for _, cls in ipairs(UD.classOrder) do
    items[#items + 1] = { text = UD:ClassName(cls), header = true }
    for _, id in ipairs(UD.classes[cls].specs) do
      items[#items + 1] = { text = UD:SpecName(id), specID = id, onClick = function()
        if R.Roster:AddPlanned(id, RUI.plannerName:GetText()) then RUI.plannerName:SetText("") end
      end }
    end
  end
  UI:ShowMenu(anchor, items)
end

function RUI:OpenPlannedMenu(anchor, i)
  UI:ShowMenu(anchor, {
    { text = "Move up", onClick = function() R.Roster:MovePlanned(i, -1) end },
    { text = "Move down", onClick = function() R.Roster:MovePlanned(i, 1) end },
    { text = "Remove", onClick = function() R.Roster:RemovePlanned(i) end },
  })
end

function RUI:RosterLines(L, members, onClick)
  local byGroup, groups = {}, {}
  for _, m in ipairs(members) do
    local g = m.group or 1
    if not byGroup[g] then byGroup[g] = {}; groups[#groups + 1] = g end
    table.insert(byGroup[g], m)
  end
  table.sort(groups)
  for _, g in ipairs(groups) do
    L:Header("Group " .. g)
    for _, m in ipairs(byGroup[g]) do
      local spec = m.spec and (SpecIcon(m.spec) .. " " .. UD:SpecName(m.spec)) or (HEX.muted .. (m.class and (UD:ClassName(m.class) .. ", spec being read") or "?") .. "|r")
      local role = m.role and ROLE_WORD[m.role] or ""
      local text = string.format("%s  %s%s", ClassName(m), HEX.muted .. spec .. "|r", role ~= "" and (HEX.muted .. "  " .. role .. "|r") or "")
      L:Add(text, onClick and onClick(m) or nil)
    end
  end
end

function RUI:RefreshRoster()
  local members = R.Roster:Members()
  local planner = R.Roster:Source() == "planner"
  local L = self.rosterList
  L:Clear()
  self.rLeft.title:SetText(HEX.accent .. (planner and "RAID PLANNER" or "RAID") .. "|r " .. HEX.muted .. "(" .. #members .. ")|r")
  if planner then
    if #members == 0 then
      L:Add(HEX.muted .. "You're not in a group. Add players by spec to plan ahead; the list is saved. In a group, this shows your real raid.|r")
    end
    self:RosterLines(L, members, function(m)
      return { onClick = function(btn) RUI:OpenPlannedMenu(btn, m.planner) end, tooltip = "Click: move or remove" }
    end)
  else
    local c = R.Roster:Counts(members)
    self:RosterLines(L, members)
    if c.known < c.total then
      L:Space(6)
      L:Add(HEX.muted .. string.format("Specs known: %d of %d. The rest are read one at a time (out of combat); until then they count as what every spec of their class brings.", c.known, c.total) .. "|r", { size = 11 })
    end
  end
  L:Finish()
  self.plannerName:SetShown(planner); self.addBtn:SetShown(planner); self.clearBtn:SetShown(planner)
  self.clearBtn.armed = nil; self.clearBtn.text:SetText("Clear")
  self.copyBtn:SetShown(not planner)
  -- Needs
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  local res = R.Needs:Evaluate(bk, diff, members)
  self.lastNeeds = res
  self.rRight.title:SetText(HEX.accent .. "NEEDS|r for " .. D.BOSSES[bk].name .. ", " .. R:DiffLabel(diff))
  local N = self.needsList
  N:Clear()
  if #members == 0 then N:Add(HEX.muted .. "Add players (or join a group) to check the needs.|r") end
  for _, r in ipairs(res.rows) do
    if #members > 0 then
      N:Add(Tag(r.status) .. "  " .. r.label, { gap = 1 })
      N:Add(HEX.muted .. r.detail .. "|r", { indent = 14, size = 11, gap = 6 })
    end
  end
  if #res.above > 0 then
    N:Space(4)
    local labels = {}
    for _, n in ipairs(res.above) do labels[#labels + 1] = (n.label or n.key) .. " (" .. R:DiffLabel(n.d) .. ")" end
    if self.showAbove then
      N:Add(HEX.muted .. "On higher difficulties:|r", { size = 11 })
      for _, n in ipairs(res.above) do
        N:Add(DiffTag(n.d) .. (n.label or n.key) .. (n.note and (HEX.muted .. " (" .. n.note .. ")|r") or ""), { indent = 14, size = 11 })
      end
      N:Add(HEX.accent .. "Hide|r", { size = 11, onClick = function() RUI.showAbove = false; RUI:Queue() end })
    else
      N:Add(HEX.muted .. string.format("Hidden at %s: %d need%s for higher difficulties.|r ", R:DiffLabel(diff), #res.above, #res.above == 1 and "" or "s") .. HEX.accent .. "Show|r",
        { size = 11, onClick = function() RUI.showAbove = true; RUI:Queue() end, tooltip = table.concat(labels, ", ") })
    end
  end
  N:Finish()
  local list, pos = R:Order(inst), 1
  for p, k in ipairs(list) do if k == bk then pos = p end end
  self.prevBtn.text:SetText(list[pos - 1] and ("< " .. D.BOSSES[list[pos - 1]].short) or "Previous boss")
  self.nextBtn.text:SetText(list[pos + 1] and (D.BOSSES[list[pos + 1]].short .. " >") or "Next boss")
  if list[pos - 1] then self.prevBtn:Enable() else self.prevBtn:Disable() end
  if list[pos + 1] then self.nextBtn:Enable() else self.nextBtn:Disable() end
end

function RUI:PostGaps()
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  local res = self.lastNeeds or R.Needs:Evaluate(bk, diff)
  if #res.members == 0 then ns:Print("Add players first."); return end
  R:Send(R.Needs:GapLines(res, bk, diff), "Gaps")
end

---------------------------------------------------------------------------
-- Bosses page: the boss list (with the order control) and the card, learner or leader
---------------------------------------------------------------------------
function RUI:BuildBosses()
  local page = self.pages.bosses
  local left = Panel(page, true, 220)
  local right = Panel(page, false, left)
  self.bLeft, self.bRight = left, right
  self.bossList = K.LineList(left, 200, 300):Fill(8, -32, -8, 104)
  local up = K.Button(left, "Earlier", 64, 22, function() RUI:MoveSelected(-1) end)
  up:SetPoint("BOTTOMLEFT", 10, 76)
  local down = K.Button(left, "Later", 64, 22, function() RUI:MoveSelected(1) end)
  down:SetPoint("LEFT", up, "RIGHT", 4, 0)
  local reset = K.FlatButton(left, "Reset order", 70, 22, function() R:ResetOrder() end)
  reset:SetPoint("LEFT", down, "RIGHT", 4, 0)
  self.upBtn, self.downBtn, self.resetOrderBtn = up, down, reset
  local auto = K.Check(left, "Boss window in raids", function() return R.db.bossWindow.auto end,
    function(v) R.db.bossWindow.auto = v and true or false end,
    "Open the raid boss window by itself when you enter one of the season's raids or Lairs.")
  auto:SetPoint("BOTTOMLEFT", 10, 44)
  self.autoBW = auto
  local bw = K.Button(left, "Open the boss window", 196, 24, function() if R.BossWindow then R.BossWindow:Show(true) end end)
  bw:SetPoint("BOTTOMLEFT", 10, 12)
  self.bwBtn = bw
  -- Card controls
  local learner = K.Button(right, "Learner", 78, 22, function() R.db.view = "learner"; RUI:Queue() end)
  local leader = K.Button(right, "Leader", 78, 22, function() R.db.view = "leader"; RUI:Queue() end)
  leader:SetPoint("TOPRIGHT", -10, -6)
  learner:SetPoint("RIGHT", leader, "LEFT", -2, 0)
  learner.tooltip = "What you do on this boss, for your role."
  leader.tooltip = "Leading the pull: what to check, what to call and when."
  self.learnerBtn, self.leaderBtn = learner, leader
  self.roleBtns = {}
  local prev
  for _, r in ipairs({ { "AUTO", "You" }, { "ALL", "All" }, { "TANK", "Tank" }, { "HEALER", "Heal" }, { "DAMAGER", "DPS" } }) do
    local b = K.Button(right, r[2], 46, 22, function() R.db.role = r[1]; RUI:Queue() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("BOTTOMLEFT", 10, 12) end
    b.roleKey = r[1]
    self.roleBtns[#self.roleBtns + 1] = b
    prev = b
  end
  self.roleBtns[1].tooltip = "Your own role (from your spec)."
  self.cardList = K.LineList(right, 400, 300):Fill(8, -32, -8, 46)
  local postA = K.Button(right, "Post pre-pull", 110, 24, function() RUI:PostPrepull() end)
  local postB = K.Button(right, "Post calls", 90, 24, function() RUI:PostCalls() end)
  local build = K.Button(right, "Build the plan", 120, 24, function() RUI:BuildPlanFromLeader() end)
  build:SetPoint("BOTTOMRIGHT", -10, 12)
  postB:SetPoint("RIGHT", build, "LEFT", -6, 0)
  postA:SetPoint("RIGHT", postB, "LEFT", -6, 0)
  build.tooltip = "Open this boss's plan with every row filled where your roster allows (rows you filled stay)."
  self.prepullBtn, self.callsBtn, self.buildBtn = postA, postB, build
  local dangers = K.Button(right, "Post dangers", 110, 24, function() RUI:PostDangers() end)
  dangers:SetPoint("BOTTOMRIGHT", -10, 12)
  dangers.tooltip = "Post \"what kills raids here\" to the group."
  self.dangersBtn = dangers
end

function RUI:MoveSelected(delta)
  local inst = R:Instance()
  R:Move(R:Boss(inst), delta)
end

function RUI:RefreshBosses()
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  local b = D.BOSSES[bk]
  local L = self.bossList
  L:Clear()
  self.bLeft.title:SetText(HEX.accent .. inst.name:upper() .. "|r")
  for i, k in ipairs(R:Order(inst)) do
    local sel = k == bk
    local movable = R:Movable(inst, k)
    L:Add(string.format("%s%d|r  %s%s", HEX.muted, i, sel and (HEX.accent .. D.BOSSES[k].name .. "|r") or D.BOSSES[k].name,
      movable and (HEX.muted .. " *|r") or ""), { onClick = function() R:SetBoss(k) end, tooltip = movable and "* Your group can take this boss earlier or later (left or right wing)." or nil })
  end
  if inst.orderGroups then
    L:Add(HEX.muted .. "* order can change: pick it, then Earlier or Later.|r", { size = 10 })
  end
  L:Space(8)
  L:Add(HEX.accent .. "ALSO THIS SEASON|r", { size = 11, gap = 5 })
  for _, other in ipairs(D.INSTANCES) do
    if other.key ~= inst.key then
      for _, k in ipairs(other.bosses) do
        L:Add(D.BOSSES[k].name .. HEX.muted .. (other.kind == "lair" and "  Lair" or (#other.bosses == 1 and "  raid, 1 boss" or "")) .. "|r",
          { onClick = function() R:SetBoss(k) end })
      end
    end
  end
  L:Finish()
  local canUp, canDown = R:CanMove(inst, bk, -1), R:CanMove(inst, bk, 1)
  self.upBtn:SetShown(inst.orderGroups ~= nil); self.downBtn:SetShown(inst.orderGroups ~= nil); self.resetOrderBtn:SetShown(inst.orderGroups ~= nil)
  if canUp then self.upBtn:Enable() else self.upBtn:Disable() end
  if canDown then self.downBtn:Enable() else self.downBtn:Disable() end
  self.autoBW:Sync()
  -- The card
  local leader = R.db.view == "leader"
  self.learnerBtn:SetActive(not leader); self.leaderBtn:SetActive(leader)
  for _, rb in ipairs(self.roleBtns) do rb:SetShown(not leader); rb:SetActive(R.db.role == rb.roleKey) end
  self.prepullBtn:SetShown(leader); self.callsBtn:SetShown(leader); self.buildBtn:SetShown(leader)
  self.dangersBtn:SetShown(not leader)
  local C = self.cardList
  C:Clear()
  if leader then
    self.bRight.title:SetText(HEX.accent .. "LEADING|r " .. b.name .. " (" .. R:DiffLabel(diff) .. ")")
    self:RenderLeader(C, bk, diff)
  else
    local role, auto = self:ViewRole()
    local roleName = role == "ALL" and "everyone" or ({ TANK = "tanks", HEALER = "healers", DAMAGER = "DPS" })[role]
    self.bRight.title:SetText(b.name .. HEX.muted .. ": what " .. roleName .. " do" .. (auto and " (your role)" or "") .. "|r")
    self:RenderLearner(C, bk, diff, role)
  end
  C:Finish()
end

local function Dangers(b, diff)
  local out = {}
  for _, d in ipairs(b.dangers or {}) do if R:Applies(d.d, diff) then out[#out + 1] = d end end
  return out
end

function RUI:RenderItem(L, it, role)
  local tag = (it.deadly and HEX.bad or HEX.muted) .. it.tag:upper() .. "|r"
  local who = ""
  if role == "ALL" and it.who ~= "ALL" then who = HEX.muted .. " (" .. (({ TANK = "tank", HEALER = "healer", DAMAGER = "DPS", MELEE = "melee", RANGED = "ranged" })[it.who] or it.who) .. ")|r" end
  L:Add(DiffTag(it.d) .. tag .. "  " .. it.n .. who, { gap = 1 })
  L:Add(HEX.muted .. it.t .. (it.src and (" [" .. it.src .. "]") or "") .. "|r", { indent = 14, size = 11, gap = 5 })
end

function RUI:RenderLearner(L, bk, diff, role)
  local b = D.BOSSES[bk]
  L:Add(HEX.muted .. b.summary .. "|r", { size = 11, gap = 6 })
  local dg = Dangers(b, diff)
  if #dg > 0 then
    L:Add(HEX.bad .. "WHAT KILLS RAIDS HERE|r", { size = 11, gap = 4 })
    for _, d in ipairs(dg) do L:Add(DiffTag(d.d) .. d.t, { indent = 8, size = 11, gap = 2 }) end
  end
  local stepUp = {}
  local nextRank = (D.DIFFS[diff].rank or 1) + 1
  for _, ph in ipairs(b.phases) do
    local shown = {}
    for _, it in ipairs(ph.items) do
      if self:ShowsFor(it.who, role) then
        if R:Applies(it.d, diff) then shown[#shown + 1] = it
        elseif D.DIFFS[it.d].rank == nextRank then stepUp[#stepUp + 1] = it end
      end
    end
    if #shown > 0 then
      L:Header(ph.name)
      for _, it in ipairs(shown) do self:RenderItem(L, it, role) end
    end
  end
  L:Space(4)
  L:Add(HEX.accent .. "BLOODLUST|r  " .. (b.lust[R:DataDiff(diff)] or b.lust.N), { size = 11, gap = 6 })
  if #stepUp > 0 then
    L:Header(nextRank == 2 and "Stepping up: what Heroic adds" or "Stepping up: what Mythic adds")
    for _, it in ipairs(stepUp) do self:RenderItem(L, it, role) end
  end
  L:Space(4)
  L:Add(HEX.muted .. "Sources: " .. b.src .. ". Data checked " .. D.DATA_CHECKED .. ".|r", { size = 10 })
end

function RUI:RenderLeader(L, bk, diff)
  local b = D.BOSSES[bk]
  L:Add(HEX.muted .. b.summary .. "|r", { size = 11, gap = 6 })
  L:Header("Before the pull")
  local res = R.Needs:Evaluate(bk, diff)
  if #res.members > 0 then
    for _, r in ipairs(res.rows) do
      if r.status ~= "ok" then L:Add(Tag(r.status) .. "  " .. r.label .. HEX.muted .. ": " .. r.detail .. "|r", { size = 11, gap = 2 }) end
    end
    if res.gaps == 0 then L:Add(HEX.good .. "Every need is covered.|r", { size = 11, gap = 2 }) end
  else
    L:Add(HEX.muted .. "No roster yet: the needs check runs on the Roster tab.|r", { size = 11 })
  end
  for _, p in ipairs(b.prepull or {}) do
    if R:Applies(p.d, diff) then L:Add(DiffTag(p.d) .. "- " .. R:IconText(p.t, 12), { size = 11, gap = 2 }) end
  end
  L:Header("Calls during the fight")
  L:Add(HEX.muted .. "Click a line to post it to your group's chat.|r", { size = 10, gap = 3 })
  for _, c in ipairs(b.calls or {}) do
    if R:Applies(c.d, diff) then
      L:Add(DiffTag(c.d) .. HEX.muted .. c.w .. "|r   " .. R:IconText(c.t, 12), {
        gap = 3, onClick = function() R:Send(R:Wrap(c.t), "Call") end, tooltip = "Post: " .. R:ChatText(c.t) })
    end
  end
  local marks = {}
  for _, row in ipairs(R.Plan:Rows(bk, diff)) do
    if row.marker then marks[#marks + 1] = R:MarkerIcon(row.marker, 12) .. " " .. row.mech end
  end
  if #marks > 0 then
    L:Header("Suggested markers")
    L:Add(table.concat(marks, HEX.muted .. "  |  |r"), { size = 11, gap = 2 })
    L:Add(HEX.muted .. "Named in the plan and its chat lines; you place world markers and mark targets yourself.|r", { size = 10 })
  end
  L:Space(4)
  L:Add(HEX.accent .. "BLOODLUST|r  " .. (b.lust[R:DataDiff(diff)] or b.lust.N), { size = 11, gap = 6 })
  local nextRank = (D.DIFFS[diff].rank or 1) + 1
  local up = {}
  for _, ph in ipairs(b.phases) do
    for _, it in ipairs(ph.items) do if D.DIFFS[it.d].rank == nextRank then up[#up + 1] = it end end
  end
  if #up > 0 then
    L:Header(nextRank == 2 and "Taking this group to Heroic" or "Taking this group to Mythic")
    for _, it in ipairs(up) do self:RenderItem(L, it, "ALL") end
  end
  L:Space(4)
  L:Add(HEX.muted .. "Sources: " .. b.src .. ".|r", { size = 10 })
end

function RUI:PostDangers()
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  local b = D.BOSSES[bk]
  local parts = {}
  for _, d in ipairs(Dangers(b, diff)) do parts[#parts + 1] = d.t:gsub("%.$", "") end
  R:Send(R:Wrap(b.name .. " (" .. R:DiffLabel(diff) .. ") - what kills raids: " .. table.concat(parts, "; ") .. "."), "Dangers")
end
function RUI:PostPrepull()
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  local b = D.BOSSES[bk]
  local parts = {}
  for _, p in ipairs(b.prepull or {}) do if R:Applies(p.d, diff) then parts[#parts + 1] = (p.t:gsub("%.$", "")) end end
  parts[#parts + 1] = "Bloodlust: " .. (b.lust[R:DataDiff(diff)] or b.lust.N)
  R:Send(R:Wrap(b.name .. " (" .. R:DiffLabel(diff) .. "): " .. table.concat(parts, "; ") .. "."), "Pre-pull")
end
function RUI:PostCalls()
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  local b = D.BOSSES[bk]
  local parts = {}
  for _, c in ipairs(b.calls or {}) do if R:Applies(c.d, diff) then parts[#parts + 1] = c.w .. ": " .. c.t end end
  R:Send(R:Wrap(b.name .. " calls - " .. table.concat(parts, "; ")), "Calls")
end
function RUI:BuildPlanFromLeader()
  local inst = R:Instance()
  local n = R.Plan:Suggest(R:Boss(inst), R:Diff(inst))
  UI:SetTab("plan")
  if n == 0 and #R.Roster:Members() == 0 then ns:Print("Add players on the Roster tab (or join a group) to fill the plan.") end
end

---------------------------------------------------------------------------
-- Plan page: the roster (click to add to the selected row) and the plan rows
---------------------------------------------------------------------------
function RUI:BuildPlan()
  local page = self.pages.plan
  local left = Panel(page, true, 220)
  local right = Panel(page, false, left)
  self.pLeft, self.pRight = left, right
  self.planRoster = K.LineList(left, 200, 300):Fill(8, -32, -8, 12)
  self.planList = K.LineList(right, 400, 300):Fill(8, -32, -8, 80)
  local suggest = K.Button(right, "Suggest", 76, 22, function()
    local inst = R:Instance()
    local n = R.Plan:Suggest(R:Boss(inst), R:Diff(inst))
    if n == 0 then ns:Print("No empty row could be filled from this roster.") end
  end)
  suggest.tooltip = "Fill the empty rows from your roster (rows you've filled stay as they are)."
  local marker = K.Button(right, "Marker", 70, 22, function(btn) RUI:OpenMarkerMenu(btn) end)
  local clear = K.Button(right, "Clear row", 76, 22, function()
    local inst = R:Instance()
    if RUI.selRow then R.Plan:ClearRow(R:Boss(inst), R:Diff(inst), RUI.selRow) end
  end)
  local reset = K.FlatButton(right, "Reset", 50, 22, function(btn)
    if btn.armed then
      btn.armed = nil; local inst = R:Instance(); R.Plan:Reset(R:Boss(inst), R:Diff(inst)); RUI.selRow = nil
    else btn.armed = true; btn.text:SetText("Sure?") end
  end)
  reset:SetPoint("TOPRIGHT", -10, -6)
  clear:SetPoint("RIGHT", reset, "LEFT", -4, 0)
  marker:SetPoint("RIGHT", clear, "LEFT", -4, 0)
  suggest:SetPoint("RIGHT", marker, "LEFT", -4, 0)
  self.resetPlanBtn = reset
  local rowName = K.EditBox(right, 200, 24)
  rowName:SetPoint("BOTTOMLEFT", 10, 46)
  self.rowName = rowName
  local addRow = K.Button(right, "+ Add row", 90, 24, function()
    local inst = R:Instance()
    local id = R.Plan:AddRow(R:Boss(inst), R:Diff(inst), RUI.rowName:GetText())
    if id then RUI.selRow = id; RUI.rowName:SetText("") else ns:Print("Type a name for the row first (for example \"Healing cooldown 1\").") end
  end)
  addRow:SetPoint("LEFT", rowName, "RIGHT", 6, 0)
  local removeRow = K.Button(right, "Remove row", 100, 24, function()
    local inst = R:Instance()
    if not (RUI.selRow and R.Plan:RemoveRow(R:Boss(inst), R:Diff(inst), RUI.selRow)) then ns:Print("Only rows you added can be removed; Clear row empties any row.") end
  end)
  removeRow:SetPoint("LEFT", addRow, "RIGHT", 6, 0)
  local post = K.Button(right, "Post to raid", 110, 24, function() RUI:PostPlan(false) end)
  post:SetPoint("BOTTOMLEFT", 10, 12)
  local warn = K.Button(right, "Post to raid warning", 160, 24, function() RUI:PostPlan(true) end)
  warn:SetPoint("LEFT", post, "RIGHT", 6, 0)
  warn.tooltip = "Raid warning needs leader or assist; otherwise it posts to the group's chat."
  local copy = K.Button(right, "Copy", 64, 24, function()
    local inst = R:Instance()
    local lines = R.Plan:ChatLines(R:Boss(inst), R:Diff(inst))
    if lines then R:Copy(lines, "Plan") else ns:Print("The plan is empty.") end
  end)
  copy:SetPoint("LEFT", warn, "RIGHT", 6, 0)
  local note = K.Text(right, 10, K.C.muted)
  note:SetPoint("LEFT", copy, "RIGHT", 10, 0); note:SetPoint("RIGHT", right, "RIGHT", -10, 0)
  note:SetText("Markers show as icons in chat; place them yourself.")
  self.planNote = note
end

function RUI:OpenMarkerMenu(anchor)
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  if not self.selRow then ns:Print("Pick a row first."); return end
  local items = {}
  for _, m in ipairs(D.MARKERS) do
    items[#items + 1] = { text = m.label, icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. m.i,
      onClick = function() R.Plan:SetMarker(bk, diff, RUI.selRow, m.key) end }
  end
  items[#items + 1] = { text = "No marker", onClick = function() R.Plan:SetMarker(bk, diff, RUI.selRow, false) end }
  UI:ShowMenu(anchor, items)
end

function RUI:RefreshPlan()
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  local members = R.Roster:Members()
  local rows = R.Plan:Rows(bk, diff)
  local valid = false
  for _, r in ipairs(rows) do if r.id == self.selRow then valid = true end end
  if not valid then self.selRow = rows[1] and rows[1].id or nil end
  self.resetPlanBtn.armed = nil; self.resetPlanBtn.text:SetText("Reset")
  local counts = R.Plan:Count(bk, diff)
  local sel = self.selRow and R.Plan:Row(bk, diff, self.selRow)
  local selSet = {}
  for _, n in ipairs(sel and sel.names or {}) do selSet[n] = true end
  local L = self.planRoster
  L:Clear()
  self.pLeft.title:SetText(HEX.accent .. "RAID|r " .. HEX.muted .. "click to add or remove|r")
  if #members == 0 then L:Add(HEX.muted .. "No roster yet: add players on the Roster tab, or join a group.|r", { size = 11 }) end
  for _, m in ipairs(members) do
    local mark = selSet[m.name] and (HEX.good .. "+ |r") or "  "
    local c = counts[m.name]
    L:Add(mark .. (m.spec and SpecIcon(m.spec) .. " " or "") .. ClassName(m) .. (c and (HEX.muted .. "  " .. c .. "|r") or ""), {
      gap = 2, onClick = function()
        if not RUI.selRow then ns:Print("Pick a row first."); return end
        R.Plan:Toggle(bk, diff, RUI.selRow, m.name)
      end, tooltip = sel and ((selSet[m.name] and "Remove from " or "Add to ") .. sel.mech) or "Pick a row first" })
  end
  L:Finish()
  self.pRight.title:SetText(HEX.accent .. "PLAN|r for " .. D.BOSSES[bk].name .. ", " .. R:DiffLabel(diff))
  local P = self.planList
  P:Clear()
  local inPlan = {}
  for _, r in ipairs(rows) do
    local isSel = r.id == self.selRow
    local head = (isSel and (HEX.accent .. "> |r") or "  ") .. (r.marker and (R:MarkerIcon(r.marker, 14) .. " ") or "") ..
      (isSel and (HEX.accent .. r.mech .. "|r") or r.mech) .. HEX.muted .. "  " .. (r.when ~= "" and r.when or "") ..
      (r.custom and "  (your row)" or "") .. (r.d ~= "N" and ("  " .. R:DiffLabel(r.d) .. " and up") or "") .. "|r"
    P:Add(head, { gap = 1, onClick = function() RUI.selRow = r.id; RUI:Queue() end, tooltip = "Click to pick this row, then click players on the left." })
    local names = {}
    for i, n in ipairs(r.names) do
      inPlan[n] = true
      local m
      for _, x in ipairs(members) do if x.name == n then m = x end end
      names[#names + 1] = (r.kind == "order" and (i .. ". ") or "") .. (m and ClassName(m) or (HEX.muted .. n .. " (not here)|r"))
    end
    local sep = r.kind == "order" and HEX.muted .. "  >  |r" or ", "
    local want = r.n and (r.kind == "group" and (" " .. HEX.muted .. "(" .. #r.names .. (r.n and (", " .. r.n .. "+ suggested") or "") .. ")|r") or (" " .. HEX.muted .. "(" .. #r.names .. ")|r")) or ""
    P:Add(#names > 0 and (table.concat(names, sep) .. want) or (HEX.muted .. "nobody yet|r"), { indent = 18, size = 11, gap = 6 })
  end
  if #members > 0 then
    local missing = {}
    for _, m in ipairs(members) do if not inPlan[m.name] then missing[#missing + 1] = m.name end end
    P:Space(4)
    if #missing == 0 then P:Add(HEX.good .. "Everyone has at least one job.|r", { size = 11 })
    else P:Add(HEX.warn .. "Not on any row:|r " .. HEX.muted .. table.concat(missing, ", ") .. "|r", { size = 11 }) end
  end
  local _, lust = R.Plan:ChatLines(bk, diff)
  P:Add(HEX.accent .. "BLOODLUST|r  " .. (lust or D.BOSSES[bk].lust.N), { size = 11 })
  P:Finish()
end

function RUI:PostPlan(warning)
  local inst = R:Instance()
  local lines = R.Plan:ChatLines(R:Boss(inst), R:Diff(inst))
  if not lines then ns:Print("The plan is empty: pick a row, then click players (or Suggest)."); return end
  R:Send(lines, "Plan", warning)
end

---------------------------------------------------------------------------
-- Wrap Ensemble's tab and refresh calls (the core never draws a Mythic+ page in Raid mode).
---------------------------------------------------------------------------
local origSetTab, origRefresh, origBuild = UI.SetTab, UI.Refresh, UI.Build
function UI:SetTab(key)
  if self.frame and R.db and R:IsRaidMode() then RUI:Attach(); return RUI:SetTab(key) end
  RUI:HideRaid()
  return origSetTab(self, key)
end
function UI:Refresh()
  if self.frame and R.db and R:IsRaidMode() then return RUI:Refresh() end
  return origRefresh(self)
end
function UI:Build()
  origBuild(self)
  if R.db then RUI:Attach() end
end
RUI.origSetTab = origSetTab

R:On("MODE_CHANGED", function() if UI.frame and UI.frame:IsShown() then RUI:ApplyMode() else RUI:SyncModeButton() end end)
for _, e in ipairs({ "CHANGED", "ROSTER_CHANGED", "PLAN_CHANGED" }) do R:On(e, function() RUI:Queue() end) end
R:On("DB_READY", function() if UI.frame then RUI:Attach() end end)
