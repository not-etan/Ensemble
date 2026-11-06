-- Ensemble Raid (test build) / BossWindow.lua
-- A small window for the pull: the boss at your difficulty, what your role does, your plan rows
-- and Bloodlust. Follows the fight: ENCOUNTER_START jumps to the boss by name, a kill moves to the
-- next boss in your order. Encounter IDs the game reports are kept (EnsembleRaidDB.encSeen) so the
-- data can match by ID later; names are read through the secret-value guard.

local _, R = ...
if R.disabled then return end
local ns = R.ns
local UI = ns.UI
local D = R.Data

local BW = {}
R.BossWindow = BW

local function Norm(s) return tostring(s or ""):lower():gsub("[^%w]", "") end

-- The boss key for an encounter name (the boss's name, short name or an alias).
function BW:Match(name)
  if type(name) ~= "string" or name == "" then return nil end
  local n = Norm(name)
  for bk, b in pairs(D.BOSSES) do
    if Norm(b.name) == n or Norm(b.short) == n then return bk end
    for _, a in ipairs(b.aliases or {}) do if Norm(a) == n then return bk end end
  end
  return nil
end

function BW:Build()
  if self.frame then return end
  local K = UI.Kit
  local f = CreateFrame("Frame", "EnsembleRaidBossFrame", UIParent, "BackdropTemplate")
  self.frame = f
  f:SetSize(320, 400)
  f:SetFrameStrata(UI.OVER_WINDOW_STRATA or "HIGH")
  f:SetFrameLevel(UI.OVER_WINDOW_LEVEL or 200)
  f:SetClampedToScreen(true)
  f:SetMovable(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local l, t = self:GetLeft(), self:GetTop()
    if l and t then R.db.bossWindow.left, R.db.bossWindow.top = l, t end
  end)
  K.Skin(f, K.C.bg, K.C.border)
  local p = R.db.bossWindow
  if p.left and p.top then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top) else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 40) end
  local title = K.Text(f, 13, K.C.text)
  title:SetPoint("TOPLEFT", 10, -8); title:SetPoint("RIGHT", f, "RIGHT", -34, 0)
  title:SetWordWrap(false)
  self.title = title
  local close = K.FlatButton(f, "X", 22, 20, function() BW:Hide() end)
  close:SetPoint("TOPRIGHT", -6, -6)
  self.list = K.LineList(f, 300, 320):Fill(6, -30, -6, 36)
  local prev = K.Button(f, "<", 30, 22, function() if R:StepBoss(-1) then BW:Refresh() end end)
  prev:SetPoint("BOTTOMLEFT", 8, 8)
  local nextB = K.Button(f, ">", 30, 22, function() if R:StepBoss(1) then BW:Refresh() end end)
  nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
  local open = K.FlatButton(f, "Open in Ensemble", 120, 22, function()
    if R.db.mode == "mplus" then R:SetMode("raid") end
    R.db.tab = "bosses"
    UI:Show()
    UI:SetTab("bosses")
  end)
  open:SetPoint("BOTTOMRIGHT", -8, 8)
  f:Hide()
end

function BW:Show(manual)
  self:Build()
  self.manual = manual and true or false
  self.frame:Show()
  self:Refresh()
end
function BW:Hide() if self.frame then self.frame:Hide() end end
function BW:IsShown() return self.frame and self.frame:IsShown() end

function BW:Refresh()
  if not self:IsShown() then return end
  local HEX = UI.Kit.HEX
  local inst = R:Instance()
  local bk, diff = R:Boss(inst), R:Diff(inst)
  local b = D.BOSSES[bk]
  self.title:SetText(b.name .. HEX.muted .. "  " .. R:DiffLabel(diff) .. "|r")
  local role = R.UI:MyRole()
  local L = self.list
  L:Clear()
  local me = UnitName and R.Plain((UnitName("player")))
  local jobs = R.Plan:JobsFor(bk, diff, me)
  if #jobs > 0 then
    L:Add(HEX.accent .. "YOUR JOBS|r", { size = 11, gap = 3 })
    for _, j in ipairs(jobs) do
      local r = j.row
      L:Add((r.marker and (R:MarkerIcon(r.marker, 12) .. " ") or "") .. r.mech .. (r.kind == "order" and (HEX.muted .. "  (#" .. j.pos .. ")|r") or "") ..
        HEX.muted .. (r.when and r.when ~= "" and ("  " .. r.when) or "") .. "|r", { size = 11, gap = 2 })
    end
    L:Space(4)
  end
  L:Add(HEX.accent .. "BLOODLUST|r  " .. (b.lust[R:DataDiff(diff)] or b.lust.N), { size = 11, gap = 6 })
  for _, ph in ipairs(b.phases) do
    local shown = {}
    for _, it in ipairs(ph.items) do
      if R:Applies(it.d, diff) and R.UI:ShowsFor(it.who, role) then shown[#shown + 1] = it end
    end
    if #shown > 0 then
      L:Header(ph.name)
      for _, it in ipairs(shown) do
        local tag = (it.deadly and HEX.bad or HEX.muted) .. it.tag:upper() .. "|r "
        L:Add(tag .. it.n .. HEX.muted .. ": " .. it.t .. "|r", { size = 11, gap = 3 })
      end
    end
  end
  L:Finish()
end

-- Follow the fight.
R:On("ENCOUNTER_START", function(encounterID, encounterName)
  local name, id = R.Plain(encounterName), R.Plain(encounterID)
  local bk = BW:Match(name)
  -- Kept only for the season's raid bosses (a match) or inside one of its raids (a new name to add).
  if name and id and (bk or R:CurrentInstance()) then R.db.encSeen[name] = id end
  BW.lastEncounter = { name = name, id = id, matched = bk }
  if bk then R:SetBoss(bk); BW:Refresh() end
end)
R:On("ENCOUNTER_END", function(encounterID, encounterName, _, _, success)
  local name, ok = R.Plain(encounterName), R.Plain(success)
  local bk = BW:Match(name) or (BW.lastEncounter and BW.lastEncounter.matched)
  BW.lastEnd = { name = name, success = ok, matched = bk }
  if ok == 1 or ok == true then
    if bk and bk == R:Boss() then R:StepBoss(1) end
    BW.kills = (BW.kills or 0) + 1
  end
  BW:Refresh()
end)
-- Open by itself in one of the season's raids or Lairs (once per arrival), if the setting is on.
R:On("PLAYER_ENTERING_WORLD", function()
  local inst = R:CurrentInstance()
  if inst and R.db.bossWindow.auto and not ns.API.InCombat() then
    if BW.autoFor ~= inst.key then BW.autoFor = inst.key; BW:Show(false) end
  elseif not inst then
    BW.autoFor = nil
    if BW:IsShown() and not BW.manual then BW:Hide() end
  end
end)
for _, e in ipairs({ "CHANGED", "PLAN_CHANGED", "ROSTER_CHANGED" }) do R:On(e, function() BW:Refresh() end) end
