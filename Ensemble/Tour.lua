-- Ensemble / Tour.lua
-- A short first-run tour: a callout with Back / Next / Skip that points at one part of the
-- window at a time. Shown once, the first time the window opens; replay it from
-- Settings > General. Pure UI, nothing saved but `db.tourSeen`.
local _, ns = ...

local UI = ns.UI
local Tour = { step = 0 }
ns.Tour = Tour

local function cp() return UI.cp end

-- Each step: tab to show, the frame(s) to outline (first and optional last for a span),
-- and the text. Short on purpose: one idea per step.
Tour.STEPS = {
  { tab = "composition", title = "Tabs",
    target = function() return UI.tabButtons.composition, UI.tabButtons.settings end,
    text = "Composition: who to bring. Applicants rates who applies to your listing. Dungeon: what to know, in the order you meet it. Plan: who handles what." },
  { tab = "composition", title = "Dungeon",
    target = function() return cp().dungeonBtn end,
    text = "Pick the dungeon to check against. Auto follows your keystone; with a party or a listing, your listing or the dungeon you're in." },
  { tab = "composition", title = "Your group",
    target = function() return cp().slotRows[1], cp().slotRows[#cp().slotRows] end,
    text = "Click a slot to try a spec. In a party (or with a listing) these fill in with your real group; the mode button switches between your party and the planner." },
  { tab = "composition", title = "Needs and gaps",
    target = function() return cp().ready.sf end,
    text = "Everything this group handles. MISSING and THIN rows are gaps: click one to see why it matters and which classes could cover it." },
  { tab = "plan", title = "Assignments",
    target = function() return UI.pl and UI.pl.leftPanel end,
    text = "Who takes each kick and dispel (click a line to change it) and Bloodlust timing (click to set your own). Post the assignments to party chat before the key starts: the game may block addon chat during a key, and then the text opens in a copy window instead." },
  { tab = "composition", title = "Hosting a key",
    target = function() return UI.tabButtons.applicants end,
    text = "Applicants rates each player on what they add to your group and their experience in this dungeon. Fill group finds a full group that covers the key and invites it when you click. While you host, the best fits also show under your slots on Composition. \"What we need\" gives you a line for your listing's description." },
  { tab = "composition", title = "Help is close",
    target = function() return UI.helpBtn end,
    text = "\"?\" opens the glossary. Boss cards open by themselves in a Season dungeon. Replay this tour from Settings > General." },
}

function Tour:Build()
  if self.frame then return end
  local K = UI.Kit
  local C = K.C
  -- Outline around the current target (four accent edges; never covers what it points at).
  local hl = CreateFrame("Frame", nil, UI.frame)
  hl:SetFrameLevel(UI.frame:GetFrameLevel() + 40)
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
  self.hl = hl

  local f = CreateFrame("Frame", nil, UI.frame, "BackdropTemplate")
  K.Skin(f, C.bg, C.border)
  K.Accent(f, "border")
  f:SetFrameLevel(UI.frame:GetFrameLevel() + 50)
  f:SetSize(300, 140)
  f:EnableMouse(true)
  f.title = K.Text(f, 13, C.text); f.title:SetPoint("TOPLEFT", 12, -10); f.title:SetPoint("RIGHT", -12, 0)
  f.title:SetWordWrap(false)
  f.body = K.Text(f, 11, C.text); f.body:SetPoint("TOPLEFT", 12, -30); f.body:SetPoint("RIGHT", -12, 0)
  f.count = K.Text(f, 10, C.muted); f.count:SetPoint("BOTTOMLEFT", 12, 12)
  f.next = K.Button(f, "Next", 64, 22, function() Tour:Go(Tour.step + 1) end)
  f.next:SetPoint("BOTTOMRIGHT", -10, 8)
  f.back = K.Button(f, "Back", 56, 22, function() Tour:Go(Tour.step - 1) end)
  f.back:SetPoint("RIGHT", f.next, "LEFT", -6, 0)
  f.skip = K.FlatButton(f, "Skip tour", 70, 22, function() Tour:Stop() end)
  f.skip:SetPoint("RIGHT", f.back, "LEFT", -6, 0)
  self.frame = f
  UI.frame:HookScript("OnHide", function() Tour:Stop() end)
end

function Tour:Start()
  if not UI.frame then UI:Build() end
  if ns.db then ns.db.tourSeen = true end
  UI:Show("composition")
  self:Build()
  self:Go(1)
end

function Tour:Stop()
  self.step = 0
  if self.frame then self.frame:Hide() end
  if self.hl then self.hl:Hide() end
end

function Tour:IsActive() return self.step > 0 end

function Tour:Go(i)
  local steps = self.STEPS
  if i < 1 then i = 1 end
  if i > #steps then self:Stop(); return end
  self.step = i
  local s = steps[i]
  if s.tab and UI.currentTab ~= s.tab then UI:Show(s.tab) end
  local f, hl = self.frame, self.hl
  f.title:SetText(UI.Kit.HEX.accent .. s.title .. "|r")
  f.body:SetText(s.text)
  f.count:SetText(i .. " / " .. #steps)
  f.back:SetShown(i > 1)
  f.next.text:SetText(i == #steps and "Done" or "Next")
  -- Fit the box to its text.
  local h = 30 + (f.body:GetStringHeight() or 40) + 40
  f:SetHeight(math.max(110, h))
  local first, last = s.target()
  f:ClearAllPoints(); hl:ClearAllPoints()
  if first then
    hl:SetPoint("TOPLEFT", first, "TOPLEFT", -3, 3)
    hl:SetPoint("BOTTOMRIGHT", last or first, "BOTTOMRIGHT", 3, -3)
    hl:Show()
    -- Callout below the target when there's room in the window, otherwise above it.
    local bottom, winBottom = (last or first):GetBottom(), UI.frame:GetBottom()
    local below = bottom and winBottom and bottom - winBottom > f:GetHeight() + 20
    -- Keep the box inside the window: right-align it when the target sits near the right edge.
    local left, winRight = first:GetLeft(), UI.frame:GetRight()
    local side = (left and winRight and left + f:GetWidth() > winRight - 8) and "RIGHT" or "LEFT"
    local tgt = side == "RIGHT" and (last or first) or first
    if below then
      f:SetPoint("TOP" .. side, tgt, "BOTTOM" .. side, 0, -10)
    else
      f:SetPoint("BOTTOM" .. side, tgt, "TOP" .. side, 0, 10)
    end
  else
    hl:Hide()
    f:SetPoint("CENTER", UI.frame, "CENTER")
  end
  f:Show()
end

-- First time the window opens: start the tour once.
function Tour:MaybeStart()
  if ns.db and not ns.db.tourSeen and not self:IsActive() then self:Start() end
end
