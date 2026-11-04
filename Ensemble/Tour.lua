-- Ensemble / Tour.lua
-- Three ways the addon shows itself, all with one callout (a box with the text and buttons)
-- and an outline around what it points at:
--   * the tour (1.6.0): five steps, one per tab, each naming the question that tab answers.
--     Shown once, the first time the window opens; replay it from Settings > General.
--   * first-time tips (1.6.0): one short callout the first time something comes up (hosting a
--     listing, the boss window, a recorded key, the reserve dialog). Each shows once; Settings >
--     General can turn them off or show them again.
--   * What's new (1.6.0): the version list and its "Show me" (a one-step tour on one spot);
--     the panel itself is UI:ShowWhatsNew.
-- Nothing shows in combat or inside a key, and every callout sits on our own frames only.
-- Saved: `db.tourSeen`, `db.tipsSeen` (tip id -> true), `db.lastSeenVersion`.
local _, ns = ...

local UI = ns.UI
local Tour = { step = 0 }
ns.Tour = Tour

local function cp() return UI.cp end

---------------------------------------------------------------------------
-- When something may show: never in combat, never inside a key.
---------------------------------------------------------------------------
-- Inside a key: the game's active challenge map (guarded), or a run History is still recording
-- (covers the moment after a loading screen before the key's state arrives).
function ns:InKey()
  if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
    local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
    if ok and type(id) == "number" and id > 0 then return true end
  end
  return (ns.db and type(ns.db.activeRun) == "table") and true or false
end

function Tour:Quiet()
  return ns.API.InCombat() or ns:InKey()
end

---------------------------------------------------------------------------
-- The tour: one step per tab
---------------------------------------------------------------------------
-- Each step: the tab to show, the frame(s) to outline (first and optional last for a span) and
-- the text. The title names the tab and the question it answers; the outline is always on the
-- tab being shown.
Tour.STEPS = {
  { tab = "composition", title = "Composition: who should we bring?",
    target = function() return cp().slotRows[1], cp().slotRows[#cp().slotRows] end,
    text = "Pick the dungeon at the top (Auto follows your keystone, your listing or the dungeon you're in). Click a slot to try a spec; in a party, the slots show your real group. Needs lists what the group covers: MISSING and THIN rows are gaps, and clicking one shows who could fill it." },
  { tab = "applicants", title = "Applicants: who's applying?",
    target = function() return UI.ap and UI.ap.left end,
    text = "While you host a key, each applicant is rated on what they add to your group and their experience in this dungeon (\"Why 78?\" shows how). Fill group finds a full group that covers the key and invites it when you click; Reserve a slot holds a spot for a friend. When you apply instead, the Group Finder's listings show how well you fit each group." },
  { tab = "dungeons", title = "Dungeon: what do I need to know?",
    target = function() return UI.pp and UI.pp.asks and UI.pp.asks.sf end,
    text = "Every boss and trash pack in the order you meet them: what to do, and which classes help most. The role filter shows only your job. \"Open boss cards\" puts the same cards in a small window, which also opens by itself in a Season dungeon and follows the key." },
  { tab = "plan", title = "Plan: who handles what?",
    target = function() return UI.pl and UI.pl.leftPanel end,
    text = "Your own assignments and the Bloodlust plan (click it to set your own timing); the full kick and dispel sheet beside it (click a line to change who takes a cast). Post assignments sends it to party chat; when the game blocks addon chat, the text opens in a copy window to paste yourself." },
  { tab = "history", title = "History: how did it go?",
    target = function() return UI.hp and UI.hp.runs and UI.hp.runs.sf end,
    text = "Every key you run is recorded: time, boss splits against your best timed run, wipes, and the gaps your group had, with lessons once something repeats. \"?\" in the title bar is the glossary and \"What's new\" lists what changed. Replay this tour, or turn tips off, in Settings > General." },
}

-- Width of a callout: wider with larger text (Settings > Appearance), so a line holds as many
-- words at 125% as at 100%.
Tour.CALLOUT_W = 300
function Tour:CalloutWidth()
  local pct = (ns.db and ns.db.settings and tonumber(ns.db.settings.textSize)) or 100
  return math.floor(self.CALLOUT_W * math.max(1, math.min(1.25, pct / 100)) + 0.5)
end

-- Where a callout goes beside its target, inside `bounds` (the window, or the screen for
-- tips on other windows). Boxes are { l, r, t, b } in screen units (y grows upward).
-- Returns the side ("below", "above", "right", "left" or "inside") and the edge to align
-- ("LEFT" or "RIGHT" for below/above, "TOP" for right/left). "inside" (the target fills the
-- window, e.g. the History list at the smallest window): the callout sits inside the target's
-- bottom corner, so it never leaves the window; the outline stays visible around it.
function Tour.Place(tgt, bounds, bw, bh)
  local gap, pad = 10, 8
  if bounds.b and tgt.b - bounds.b >= bh + gap + pad then
    return "below", (tgt.l + bw > bounds.r - pad) and "RIGHT" or "LEFT"
  end
  if bounds.t and bounds.t - tgt.t >= bh + gap + pad then
    return "above", (tgt.l + bw > bounds.r - pad) and "RIGHT" or "LEFT"
  end
  if bounds.r - tgt.r >= bw + gap + pad and tgt.t - bounds.b >= bh then return "right", "TOP" end
  if tgt.l - bounds.l >= bw + gap + pad and tgt.t - bounds.b >= bh then return "left", "TOP" end
  return "inside", (tgt.l + bw > bounds.r - pad) and "RIGHT" or "LEFT"
end

local function Box(frame)
  if not frame then return nil end
  local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (l and r and t and b) then return nil end
  return { l = l, r = r, t = t, b = b }
end

-- One callout and its outline. `parent` is the window it lives on (the main window for the
-- tour, the screen for tips, which follow other windows' strata).
function Tour:MakeCallout(parent)
  local K = UI.Kit
  local C = K.C
  local hl = CreateFrame("Frame", nil, parent)
  hl.edges = {}
  for i = 1, 4 do
    local t = hl:CreateTexture(nil, "OVERLAY")
    K.Accent(t, "tex", 1)
    hl.edges[i] = t
  end
  hl.edges[1]:SetPoint("TOPLEFT"); hl.edges[1]:SetPoint("TOPRIGHT"); hl.edges[1]:SetHeight(2)
  hl.edges[2]:SetPoint("BOTTOMLEFT"); hl.edges[2]:SetPoint("BOTTOMRIGHT"); hl.edges[2]:SetHeight(2)
  hl.edges[3]:SetPoint("TOPLEFT"); hl.edges[3]:SetPoint("BOTTOMLEFT"); hl.edges[3]:SetWidth(2)
  hl.edges[4]:SetPoint("TOPRIGHT"); hl.edges[4]:SetPoint("BOTTOMRIGHT"); hl.edges[4]:SetWidth(2)
  hl:Hide()

  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  K.Skin(f, C.bg, C.border)
  K.Accent(f, "border")
  f:SetSize(self.CALLOUT_W, 140)
  f:EnableMouse(true)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  -- Title and body stack by real height (the title wraps at larger text sizes too).
  f.title = K.Text(f, 13, C.text); f.title:SetPoint("TOPLEFT", 12, -10); f.title:SetPoint("RIGHT", -12, 0)
  f.body = K.Text(f, 11, C.text); f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6); f.body:SetPoint("RIGHT", -12, 0)
  f.count = K.Text(f, 10, C.muted); f.count:SetPoint("BOTTOMLEFT", 12, 12)
  f.next = K.Button(f, "Next", 64, 22)
  f.next:SetPoint("BOTTOMRIGHT", -10, 8)
  f.back = K.Button(f, "Back", 56, 22)
  f.back:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
  f.skip = K.FlatButton(f, "Skip tour", 70, 22)
  f.skip:SetPoint("RIGHT", f.back, "LEFT", -6, 0)
  f:Hide()
  f.hl = hl
  return f
end

-- Lay out a callout for its text, then put it (and the outline) by its target.
function Tour:PlaceCallout(f, first, last, boundsFrame)
  local hl = f.hl
  f:SetWidth(self:CalloutWidth())
  -- Fit the box to its text: title, gap, body, then the button row (22) and its margins.
  local th = f.title:GetStringHeight() or 16
  local bh = f.body:GetStringHeight() or 40
  f:SetHeight(math.max(110, 10 + th + 6 + bh + 14 + 22 + 10))
  f:ClearAllPoints(); hl:ClearAllPoints()
  if not first then
    hl:Hide()
    f:SetPoint("CENTER", boundsFrame or UIParent, "CENTER")
    f.placed = "center"
    return
  end
  last = last or first
  hl:SetPoint("TOPLEFT", first, "TOPLEFT", -3, 3)
  hl:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 3, -3)
  hl:Show()
  local a, b = Box(first), Box(last)
  local bounds = Box(boundsFrame or UIParent)
  if not (a and b and bounds) then
    -- Positions not known yet (the frame was just shown): under the target, as before.
    f:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -10)
    f.placed = "below"
    return
  end
  local tgt = { l = math.min(a.l, b.l), r = math.max(a.r, b.r), t = math.max(a.t, b.t), b = math.min(a.b, b.b) }
  local where, side = self.Place(tgt, bounds, f:GetWidth(), f:GetHeight())
  local edge = (side == "RIGHT") and last or first   -- align with the target's own edge
  if where == "below" then
    f:SetPoint("TOP" .. side, edge, "BOTTOM" .. side, 0, -10)
  elseif where == "above" then
    f:SetPoint("BOTTOM" .. side, edge, "TOP" .. side, 0, 10)
  elseif where == "right" then
    f:SetPoint("TOPLEFT", last, "TOPRIGHT", 10, 0)
  elseif where == "left" then
    f:SetPoint("TOPRIGHT", first, "TOPLEFT", -10, 0)
  else
    f:SetPoint("BOTTOM" .. side, edge, "BOTTOM" .. side, side == "RIGHT" and -10 or 10, 10)
  end
  f.placed = where
end

function Tour:Build()
  if self.frame then return end
  local f = self:MakeCallout(UI.frame)
  f.hl:SetFrameLevel(UI.frame:GetFrameLevel() + 40)
  f:SetFrameLevel(UI.frame:GetFrameLevel() + 50)
  f.next:SetScript("OnClick", function() Tour:Go(Tour.step + 1) end)
  f.back:SetScript("OnClick", function() Tour:Go(Tour.step - 1) end)
  f.skip:SetScript("OnClick", function() Tour:Stop() end)
  self.frame, self.hl = f, f.hl
  UI.frame:HookScript("OnHide", function() Tour:Stop() end)
end

-- steps: nil for the tour, or a list (What's new's "Show me" is a one-step list).
function Tour:Start(steps)
  if not UI.frame then UI:Build() end
  if not steps and ns.db then ns.db.tourSeen = true end
  self:HideTip()
  if UI.whatsNew then UI.whatsNew:Hide() end
  self.steps = steps or self.STEPS
  self.starting = true   -- opening the window refreshes it: no tip may slip in before step 1
  UI:Show(self.steps[1].tab or "composition")
  self:Build()
  self.starting = nil
  self:Go(1)
end

function Tour:Stop()
  self.step = 0
  if self.frame then self.frame:Hide() end
  if self.hl then self.hl:Hide() end
end

function Tour:IsActive() return self.step > 0 end

function Tour:Go(i)
  local steps = self.steps or self.STEPS
  if i < 1 then i = 1 end
  if i > #steps then self:Stop(); return end
  self.step = i
  local s = steps[i]
  if s.open then s.open()
  elseif s.tab and UI.currentTab ~= s.tab then UI:Show(s.tab) end
  local f = self.frame
  local one = #steps == 1
  f.title:SetText(UI.Kit.HEX.accent .. s.title .. "|r")
  f.body:SetText(s.text)
  f.count:SetText(one and "" or (i .. " / " .. #steps))
  f.back:SetShown(i > 1)
  f.skip:SetShown(not one)
  f.next.text:SetText(i == #steps and "Done" or "Next")
  local first, last = s.target()
  self:PlaceCallout(f, first, last, UI.frame)
  f:Show()
end

-- First time the window opens: start the tour once (never in combat or inside a key; it waits
-- for the next open instead).
function Tour:MaybeStart()
  if ns.db and not ns.db.tourSeen and not self:IsActive() and not self:Quiet() then self:Start() end
end

---------------------------------------------------------------------------
-- First-time tips
---------------------------------------------------------------------------
-- Each tip: when it applies (`when`), the window it sits on (`host`, shown), what it outlines
-- and the bounds the callout stays inside ("window" = the main window, "screen" otherwise).
-- Shown once (saved when it shows), one at a time, never over the tour or What's new.
local function Shown(frame) return frame and frame.IsShown and frame:IsShown() and true or false end
Tour.TIPS = {
  { id = "hosting", title = "You're hosting: Fill group",
    host = function() return UI.frame end, bounds = "window",
    when = function()
      return ns.Tracker and ns.Tracker.hosting and UI.currentTab == "applicants" and UI.ap and Shown(UI.ap.band)
    end,
    target = function() return UI.ap.band end,
    text = "Fill group looks for a full group among your applicants that covers this key, and invites it only when you click. Click the band for the plan; Auto-fill tells you when one is ready. Reserve a slot holds a spot for a friend who's joining." },
  { id = "bosswindow", title = "The boss window",
    host = function() return ns.BossWindow and ns.BossWindow.frame end, bounds = "screen",
    when = function() return ns.BossWindow and ns.BossWindow:IsShown() end,
    target = function() return ns.BossWindow.frame end,
    text = "What each boss does and your role's job, with your assignments and the Bloodlust plan. In a key it turns to the next boss after each kill. The role button switches whose notes show; Post sends the card to party chat. Drag it to move it, the corner to resize." },
  { id = "history", title = "Your first key is recorded",
    host = function() return UI.frame end, bounds = "window",
    when = function()
      return ns.db and type(ns.db.history) == "table" and #ns.db.history > 0 and UI.tabButtons ~= nil
        and UI.currentTab ~= "history"
    end,
    target = function() return UI.tabButtons.history end,
    text = "The History tab keeps every key you run: the time, boss splits against your best timed run, wipes, and the gaps your group had, with lessons once something repeats." },
  { id = "reserve", title = "Reserve a slot",
    host = function() return UI.reserveDialog end, bounds = "screen",
    when = function() local d = UI.reserveDialog; return d and d:IsShown() and d.st and d.st.mode == "reserve" end,
    target = function() return UI.reserveDialog.name, UI.reserveDialog.browse end,
    text = "Type a name, or Browse your friends, Battle.net friends and guild, then pick their spec. Fill group plans only the other slots, and the reservation clears when they join. \"Save this player\" keeps them in Settings > Saved players." },
}

function Tour:TipsOn()
  return ns.db and ns.db.settings and ns.db.settings.tips ~= false
end

function Tour:TipSeen(id)
  return ns.db and type(ns.db.tipsSeen) == "table" and ns.db.tipsSeen[id] == true
end

function Tour:BuildTip()
  if self.tip then return self.tip end
  local f = self:MakeCallout(UIParent)
  f.next.text:SetText("Got it")
  f.next:SetScript("OnClick", function() Tour:HideTip() end)
  f.back:Hide()
  f.skip.text:SetText("No more tips")
  f.skip:SetWidth(84)
  f.skip:ClearAllPoints(); f.skip:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
  f.skip.tooltip = "Turn tips off. Settings > General turns them back on."
  f.skip:SetScript("OnClick", function()
    if ns.db then ns.db.settings.tips = false end
    Tour:HideTip()
    ns:Fire("SETTINGS_CHANGED")
  end)
  self.tip = f
  self.tipHooked = {}
  return f
end

function Tour:HideTip()
  if self.tip then self.tip:Hide(); self.tip.hl:Hide() end
  self.tipShowing = nil
end

-- Show the first tip that applies now. Called after window refreshes, when the boss window or
-- the reserve dialog opens, after combat and after a key is recorded. Cheap when nothing applies.
function Tour:PumpTips()
  if not ns.db or not self:TipsOn() then return end
  if self.tipShowing then
    -- Its window closed: the tip goes with it.
    local t = self.tipShowing
    if not Shown(t.host()) then self:HideTip() end
    return
  end
  if self:IsActive() or self.starting or Shown(UI.whatsNew) or self:Quiet() then return end
  for _, t in ipairs(self.TIPS) do
    if not self:TipSeen(t.id) then
      local ok, applies = pcall(t.when)
      local host = ok and applies and t.host()
      if host and Shown(host) then self:ShowTip(t, host); return end
    end
  end
end

function Tour:ShowTip(t, host)
  local f = self:BuildTip()
  if type(ns.db.tipsSeen) ~= "table" then ns.db.tipsSeen = {} end
  ns.db.tipsSeen[t.id] = true
  self.tipShowing = t
  -- Over its host window: the same strata, a level above it and its children.
  local strata = host.GetFrameStrata and host:GetFrameStrata() or "HIGH"
  local level = (host.GetFrameLevel and host:GetFrameLevel() or 1) + 60
  f:SetFrameStrata(strata); f:SetFrameLevel(level)
  f.hl:SetFrameStrata(strata); f.hl:SetFrameLevel(level - 10)
  if not self.tipHooked[host] and host.HookScript then
    self.tipHooked[host] = true
    host:HookScript("OnHide", function() if Tour.tipShowing and Tour.tipShowing.host() == host then Tour:HideTip() end end)
  end
  f.title:SetText(UI.Kit.HEX.accent .. t.title .. "|r")
  f.body:SetText(t.text)
  f.count:SetText("Tip")
  f.skip:Show()
  local first, last = t.target()
  self:PlaceCallout(f, first, last, t.bounds == "window" and UI.frame or UIParent)
  f:Show()
end

-- Settings > General's "Show tips again".
function Tour:ResetTips()
  if ns.db then ns.db.tipsSeen = {} end
  self:HideTip()
end

ns:On("BOSS_COMBAT", function(inCombat)
  if inCombat then Tour:HideTip() else C_Timer.After(1, function() Tour:PumpTips() end) end
end)
ns:On("HISTORY_CHANGED", function() C_Timer.After(0, function() Tour:PumpTips() end) end)

---------------------------------------------------------------------------
-- What's new: versions, what a player hasn't seen, "Show me"
---------------------------------------------------------------------------
-- The list itself is ns.HIGHLIGHTS (Highlights.lua, generated from CHANGELOG.md's
-- "### Highlights" blocks by tools/make_highlights.py; a test keeps the two in step).
local WN = {}
ns.WhatsNew = WN

-- "1.6.0", "v1.6.0-beta" -> { 1, 6, 0, pre = true }; anything else -> nil.
function WN.Parse(v)
  if type(v) ~= "string" then return nil end
  local a, b, c, rest = v:match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
  if not a then return nil end
  if rest ~= "" and not rest:match("^%-[%w%.]+$") then return nil end
  return { tonumber(a), tonumber(b), tonumber(c), pre = rest ~= "" }
end

-- -1, 0 or 1. A pre-release (1.6.0-beta) comes before its release (1.6.0). nil when either
-- isn't a version.
function WN.Compare(x, y)
  local a, b = WN.Parse(x), WN.Parse(y)
  if not (a and b) then return nil end
  for i = 1, 3 do
    if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
  end
  if a.pre == b.pre then return 0 end
  return a.pre and -1 or 1
end

-- Before 1.6.0 nothing recorded the version a player saw: an existing player (who saw the tour)
-- starts from here, so the first update shows every entry; a fresh install starts at the
-- installed version (the tour comes instead).
WN.BEFORE_TRACKING = "0.0.0"

function WN:Init()
  local db = ns.db
  if not db or db.lastSeenVersion ~= nil then return end
  if db.tourSeen then db.lastSeenVersion = self.BEFORE_TRACKING
  elseif WN.Parse(ns.VERSION) then db.lastSeenVersion = ns.VERSION end
end

-- Versions with highlights newer than the last one seen, up to this version, newest first.
function WN:Unseen()
  local out = {}
  local last = ns.db and ns.db.lastSeenVersion
  if not (WN.Parse(ns.VERSION) and WN.Parse(last)) then return out end
  for _, g in ipairs(ns.HIGHLIGHTS or {}) do
    if WN.Compare(g.version, last) == 1 and WN.Compare(g.version, ns.VERSION) <= 0 then out[#out + 1] = g end
  end
  table.sort(out, function(p, q) return WN.Compare(p.version, q.version) == 1 end)
  return out
end

function WN:HasUnseen() return #self:Unseen() > 0 end

-- Opened: everything up to this version counts as seen (the header button's dot goes).
function WN:MarkSeen()
  if ns.db and WN.Parse(ns.VERSION) then ns.db.lastSeenVersion = ns.VERSION end
  if UI.SyncWhatsNewDot then UI:SyncWhatsNewDot() end
end

-- The first plain window open after an update with entries: the panel, once. Never while the
-- tour runs, in combat or inside a key (the button's dot waits instead).
function WN:MaybeShow()
  if not ns.db or Tour:IsActive() or Tour:Quiet() then return end
  if self:HasUnseen() and UI.ShowWhatsNew then UI:ShowWhatsNew() end
end

-- "Show me": what each highlight can point at. A key here is named in CHANGELOG.md as
-- `<!-- show: key -->`; the test checks every key used there exists.
WN.SHOW_ME = {
  tour = function() Tour:Start() end,
  tips = function()
    Tour:Start({ { title = "Tips", open = function() UI:OpenSettings("general") end,
      target = function() return UI.tipsRow, UI.tipsReset end,
      text = "Tips show once, the first time something comes up. Turn them off here, or show them all again." } })
  end,
  whatsnew = function()
    Tour:Start({ { title = "What's new", tab = UI.currentTab or "composition",
      target = function() return UI.whatsNewBtn end,
      text = "This button brings the list back any time. A dot on it means there's something you haven't seen yet." } })
  end,
}

function WN:ShowMe(key)
  local fn = self.SHOW_ME[key]
  if not fn then return false end
  if UI.whatsNew then UI.whatsNew:Hide() end
  fn()
  return true
end

ns:On("LOGIN", function() WN:Init() end)
