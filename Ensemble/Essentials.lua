-- Ensemble / Essentials.lua
-- The Essentials view (1.7.0) of Composition, Dungeon and Plan, Your brief, the trash section
-- editor and the "big ones" sheet. One rule on every surface: the verdict, then the few rows
-- that matter (critical and high, in plain words, one line each), then everything else counted
-- and named on a "+ N more" line. Nothing is hidden without a count, and the Everything view
-- (UI.lua, as up to 1.6.5) is one click away on each tab.
local _, ns = ...

local UI = ns.UI
local K = UI.Kit
local C, HEX = K.C, K.HEX
local TEX_OK, TEX_WAIT, TEX_NO = K.TEX_OK, K.TEX_WAIT, K.TEX_NO
local Util = ns.Util

local function DD() return ns.Dungeons end
local function UD() return ns.UD end
local function AS() return ns.Assignments end
local function Decorate(text, need, dk) return ns.Analysis.Decorate(text or "", need, dk) end

local BIG = { critical = true, high = true }
local DOT = HEX.muted .. " \194\183 |r"

-- Severity always keeps its word beside the color.
local function SevTag(sev)
  if sev == "critical" then return HEX.bad .. "CRITICAL|r" end
  if sev == "high" then return HEX.warn .. "HIGH|r" end
  return HEX.muted .. tostring(sev or ""):upper() .. "|r"
end
UI.SevTag = SevTag

local function ClassHex(classFile) return classFile and select(4, Util.ClassColor(classFile)) or HEX.text end

local function Names(list, max)
  local t = {}
  for i = 1, math.min(max or #list, #list) do t[i] = list[i] end
  return table.concat(t, ", ") .. ((max and #list > max) and (" + " .. (#list - max) .. " more") or "")
end

local function FirstSentence(text)
  return (tostring(text or ""):match("^(.-%.)%s") or tostring(text or ""))
end

---------------------------------------------------------------------------
-- Composition, layout 1A: the verdict strip
---------------------------------------------------------------------------
-- "Not ready for this +10 yet: 2 things missing" / "Fix first: ... Then: ..." on the left;
-- how much is covered and how many slots are open on the right.
function UI:RenderVerdictStrip(r, ready, dungeonKey, slotMembers)
  local cp = self.cp
  for _, b in ipairs(cp.chips) do b:Hide() end
  cp.chipBar:Hide(); cp.riskBtn:Hide(); cp.sumRight:Show()
  cp.sumTitle:ClearAllPoints()
  cp.sumTitle:SetPoint("TOPLEFT", 10, -8); cp.sumTitle:SetPoint("RIGHT", cp.sumRight, "LEFT", -8, 0)
  cp.sumRisks:ClearAllPoints()
  cp.sumRisks:SetPoint("TOPLEFT", cp.sumTitle, "BOTTOMLEFT", 0, -6); cp.sumRisks:SetPoint("RIGHT", cp.sumRight, "LEFT", -8, 0)
  cp.sumPanel:SetHeight(16 + UI.FontPx(13) + 6 + UI.FontPx(11) + 6)
  cp.chipRows = 0

  local level = dungeonKey and ns.Affixes and ns.Affixes:KeyLevel(dungeonKey)
  local d = dungeonKey and DD().list[dungeonKey]
  local what = d and (level and ("this +" .. level) or d.name) or "any key"
  local open = 0
  for s = 1, ns.NUM_SLOTS do if not (slotMembers and slotMembers[s]) then open = open + 1 end end
  local slots = open == 0 and "group full" or (open .. " slot" .. (open == 1 and "" or "s") .. " open")
  if r.filled == 0 then
    cp.sumTitle:SetText(HEX.muted .. "Add players to see what this group is missing" .. (d and (" for " .. d.name) or "") .. ".|r")
    cp.sumRisks:SetText(HEX.muted .. (d and "" or "No dungeon picked: generic checks only.") .. "|r")
    cp.sumRight:SetText(HEX.muted .. slots .. "|r")
    return
  end
  local c = ready.counts
  local missing, thin = {}, {}
  for _, row in ipairs(ready.risks) do
    local name = UD():CapShort(row.cap)
    if row.status == "missing" then missing[#missing + 1] = name else thin[#thin + 1] = name end
  end
  local function things(n) return n .. " thing" .. (n == 1 and "" or "s") end
  if #missing > 0 then
    cp.sumTitle:SetText(TEX_NO .. " " .. HEX.bad .. "Not ready for " .. what .. " yet: " .. things(#missing) .. " missing|r")
  elseif #thin > 0 then
    cp.sumTitle:SetText(TEX_WAIT .. " " .. HEX.warn .. "Nearly there for " .. what .. ": " .. things(#thin) .. " thin|r")
  else
    cp.sumTitle:SetText(TEX_OK .. " " .. HEX.good .. "Nothing missing or thin for " .. what .. "|r")
  end
  local parts = {}
  if #missing > 0 then parts[#parts + 1] = HEX.muted .. "Fix first: |r" .. HEX.text .. Names(missing, 3) .. "|r" end
  if #thin > 0 then parts[#parts + 1] = HEX.muted .. (#missing > 0 and "Then (thin): " or "Thin: ") .. "|r" .. HEX.text .. Names(thin, 3) .. "|r" end
  if #parts == 0 then parts[1] = HEX.muted .. (open > 0 and "Any pick works for the open slot; see the best ones on the left." or "Every need this dungeon and week ask for is covered.") .. "|r" end
  cp.sumRisks:SetText(table.concat(parts, HEX.muted .. ".  |r"))
  local total = c.ok + c.thin + c.missing
  cp.sumRight:SetText(TEX_OK .. " " .. HEX.text .. c.ok .. " of " .. total .. " needs covered|r\n" .. HEX.muted .. slots .. "|r")
end

---------------------------------------------------------------------------
-- Composition, layout 1A: "Best for the open slot"
---------------------------------------------------------------------------
local BEST_SHOWN = 3
local function IsBuffReason(text)
  return text:find("boosts more of the group", 1, true) or text:find("benefits from your", 1, true)
end

function UI:RenderBestForSlot(side, slotMembers, slotRoles, dungeonKey, settings, live)
  local ROLE = UI.ROLE_PLURAL
  local groups = ns.Analysis:SuggestClasses(slotMembers, slotRoles, dungeonKey, settings, 40)
  local totalOpen = 0
  for _, g in ipairs(groups) do totalOpen = totalOpen + g.open end
  if #groups == 0 then
    if not live then
      side:Header("Best for the open slot")
      side:Add(HEX.muted .. "All five slots are filled.|r", { size = 11 })
    end
    return
  end
  side:Header(totalOpen > 1 and "Best for the open slots" or "Best for the open slot")
  for _, g in ipairs(groups) do
    if #groups > 1 or g.open > 1 then
      side:Add(HEX.accent .. ROLE[g.role] .. "|r" .. HEX.muted .. "  -  " .. g.open .. " open|r", { size = 10, gap = 2 })
    end
    if #g.classes == 0 then
      side:Add(HEX.muted .. "Any " .. ROLE[g.role] .. " works: nothing left that this slot would fix.|r", { indent = 8, size = 11, gap = 4 })
    end
    local okey = "best:" .. g.role
    local all = self:IsOpen(okey, false)
    local shown = all and #g.classes or math.min(BEST_SHOWN, #g.classes)
    local roleSpecs = {}
    for _, id in ipairs(UD():SpecsForRole(g.role)) do
      local p = UD():GetSpec(id)
      if p then roleSpecs[p.class] = (roleSpecs[p.class] or 0) + 1 end
    end
    for i = 1, shown do
      local c = g.classes[i]
      local hex = ClassHex(c.classFile)
      local _, icon = ns.API.GetSpecInfoByID(c.best)
      local specs = {}
      for _, id in ipairs(c.specs) do specs[#specs + 1] = UD():SpecName(id) end
      local which = (#c.specs > 1 and #c.specs == (roleSpecs[c.classFile] or 0)) and "any spec" or table.concat(specs, " / ")
      local gaps, buffs = {}, {}
      for _, reason in ipairs(c.reasons) do
        if IsBuffReason(reason) then buffs[#buffs + 1] = reason else gaps[#gaps + 1] = reason end
      end
      local slot, best = g.slot, c.best
      local tip = {}
      for _, reason in ipairs(c.reasons) do tip[#tip + 1] = UI.Plain and UI.Plain(reason) or reason end
      if not live then tip[#tip + 1] = "Click to put " .. UD():SpecName(best) .. " " .. UD():ClassName(c.classFile) .. " in the open slot" end
      side:Add(HEX.muted .. i .. ".|r " .. (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "")
        .. hex .. UD():ClassName(c.classFile) .. "|r" .. HEX.muted .. "  " .. which .. "|r", {
        indent = 4, size = 12, gap = 1,
        onClick = (not live) and function()
          ns.db.currentComp[slot] = best
          ns.db.currentPeople[slot] = false
          ns:Fire("COMP_CHANGED", "suggest")
        end or nil,
        tooltip = table.concat(tip, "\n"),
      })
      -- One reason line: the gaps it closes first; raid buffs only when nothing else is left.
      local why = #gaps > 0 and gaps or buffs
      local line = {}
      for j = 1, math.min(2, #why) do line[j] = why[j] end
      local more = #c.reasons - #line
      side:Add(HEX.muted .. (line[1] and ((line[1]:gsub("^%l", string.upper)) .. (line[2] and (", " .. line[2]) or "")) or "A solid pick")
        .. (more > 0 and (" (+" .. more .. " on hover)") or "") .. "|r", { indent = 22, size = 10, gap = 4 })
    end
    local hiddenN = #g.classes - shown
    if hiddenN > 0 or all then
      side:Add(HEX.accent .. (all and "- show fewer" or ("+ " .. hiddenN .. " more class" .. (hiddenN == 1 and "" or "es"))) .. "|r"
        .. HEX.muted .. "  hover a class for every reason|r", { indent = 4, size = 10, gap = 3,
        onClick = function() UI:SetOpen(okey, not all) end, tooltip = all and "Show fewer" or "Show every class that would help" })
    end
  end
  if totalOpen > 1 then
    side:Add(HEX.muted .. "Ranked as your next pick; the list updates as slots fill.|r", { size = 10, gap = 2 })
  end
end

---------------------------------------------------------------------------
-- Composition, layout 1A: only what's missing, covered needs and affixes on one line each
---------------------------------------------------------------------------
function UI:RenderMissing(list, r, ready, members, dungeonKey)
  local cp = self.cp
  local risks = ready.risks or {}
  cp.midTitle:SetText(r.filled == 0 and "Needs" or (#risks > 0 and ("What this group is missing (" .. #risks .. ")") or "Nothing missing"))
  if not self:RenderReadyContext(list, r, ready, dungeonKey, true) then return end
  local settings = ns.db.settings
  local open = ns.ApplicantFit:OpenRoles(members or {})
  local anyOpen = (open.TANK or 0) + (open.HEALER or 0) + (open.DAMAGER or 0) > 0

  for _, row in ipairs(risks) do
    local cap = row.cap
    self.cp.rowY[cap] = list.y
    -- The cast that asks for it (the first one not covered).
    local it
    for _, x in ipairs(row.items) do if x.status ~= "covered" then it = x; break end end
    local was = self.previewWas and self.previewWas[cap]
    local delta = (self.previewWas and was ~= row.status) and (HEX.accent .. "  " .. (was and ("was " .. was:upper()) or "new") .. "|r") or ""
    local nMore = 0
    for _, x in ipairs(row.items) do if x.status ~= "covered" and x ~= it then nMore = nMore + 1 end end
    local explain = UD():CapExplain(cap)
    list:Add(UI.READY_TAG[row.status] .. "  " .. HEX.text .. row.label .. "|r"
      .. (it and (HEX.muted .. " for |r" .. Decorate(it.req.source, it.req.need, it.req.dungeon)) or "")
      .. (nMore > 0 and (HEX.muted .. " + " .. nMore .. " more|r") or "")
      .. (row.severity and ("  " .. SevTag(row.severity)) or "")
      .. (row.unconfirmed and (HEX.warn .. " [unconfirmed]|r") or "") .. delta, {
      indent = 2, gap = 2,
      onClick = function() UI:JumpToNeed(cap) end,
      tooltip = (explain and (row.label .. ": " .. explain .. "\n\n") or "") .. "Click for everything about this need: who covers it, every cast that asks for it and every class that brings it.",
    })
    -- Plain words: why it matters, then who would bring it.
    local why
    if row.status == "thin" then
      local who = {}
      for _, p in ipairs(row.providers) do who[#who + 1] = p.member.label .. (p.member.pending and "*" or "") end
      local reason = it and it.reason or (row.findings[1] and row.findings[1].text)
      why = (#who > 0 and ("Only " .. table.concat(who, ", ") .. " brings it") or "Covered thinly")
        .. (reason and (" (" .. (reason:gsub("%.$", "")) .. ")") or "") .. "."
      if it and it.req.note then why = why .. " " .. it.req.note end
    else
      why = (it and it.req.note) or (explain and ("Nobody here has it. " .. FirstSentence(explain))) or "Nobody here has it."
    end
    local cov = ns.Analysis:Coverers(row.coverKeys or { cap }, open, settings)
    local names = {}
    for k = 1, math.min(5, #cov) do
      local cv = cov[k]
      names[#names + 1] = (cv.inRole and ClassHex(cv.classFile) or HEX.muted) .. UD():ClassName(cv.classFile) .. "|r"
    end
    local brings = #cov == 0 and (HEX.warn .. "No class can cover this with your current settings.|r")
      or (HEX.text .. (anyOpen and "Brings it: " or "Brings it (a swap): ") .. "|r" .. table.concat(names, HEX.muted .. ", |r")
          .. (#cov > 5 and (HEX.muted .. " + " .. (#cov - 5) .. " more|r") or "") .. HEX.muted .. ".|r")
    list:Add(HEX.muted .. why .. "|r " .. brings, { indent = 20, size = 10, gap = 6 })
  end
  if #risks == 0 then
    list:Add(TEX_OK .. " " .. HEX.good .. "No missing or thin needs.|r", { indent = 2, gap = 6 })
  end

  -- Covered: one line. Nothing asked for and nobody brings: one line.
  local covered, none = {}, {}
  for _, g in ipairs(ready.groups) do
    for _, row in ipairs(g.rows) do
      local name = UD():CapShort(row.cap)
      if row.cap == "interrupt" and r.interrupts then name = "Kicks (" .. (r.interrupts.count or 0) .. ")" end
      if row.status == "ok" then covered[#covered + 1] = name elseif row.status == "none" then none[#none + 1] = name end
    end
  end
  local toAll = function() UI:SetView("composition", "everything") end
  list:Header("Covered (" .. #covered .. ")")
  if #covered > 0 then
    list:Add(TEX_OK .. " " .. HEX.text .. table.concat(covered, DOT .. HEX.text) .. "|r", { indent = 2, size = 11, gap = 3,
      onClick = toAll, tooltip = "Click for Everything: who covers each need and why" })
  else
    list:Add(HEX.muted .. "Nothing yet.|r", { indent = 2, size = 11, gap = 3 })
  end
  if #none > 0 then
    list:Add(HEX.muted .. "Nobody brings, and nothing here asks for (" .. #none .. "): " .. table.concat(none, ", ") .. "|r", { indent = 2, size = 10, gap = 3 })
  end
  if settings.checks and settings.checks.buffs ~= false then
    local buffs = {}
    for _, b in ipairs(r.buffs and r.buffs.present or {}) do buffs[#buffs + 1] = ns.Links:Buff(b.key) end
    list:Add(HEX.muted .. "Raid buffs (" .. #buffs .. ")" .. (#buffs > 0 and ": |r" or "|r") .. table.concat(buffs, HEX.muted .. ", |r"), { indent = 2, size = 10, gap = 3 })
  end
  local other = 0
  for _, f in ipairs(ready.notes) do if f.check ~= "pending" then other = other + 1 end end
  if other > 0 then
    list:Add(HEX.accent .. "+ " .. other .. " note" .. (other == 1 and "" or "s") .. " about this group|r", { indent = 2, size = 10, gap = 3,
      onClick = toAll, tooltip = "Role and range balance, duplicate classes and similar notes are under Everything" })
  end

  -- This week: one line; each affix's advice on hover.
  local AF = ns.Affixes
  if dungeonKey and DD().list[dungeonKey] and AF and settings.dungeonCategories.affixes ~= false then
    local level = AF:KeyLevel(dungeonKey)
    local active, assumed = AF:Active(level)
    local lvl = "+" .. (level or AF.ASSUMED_LEVEL)
    list:Header("This week at " .. lvl)
    if #AF:Current() == 0 then
      list:Add(HEX.muted .. "This week's affixes: not loaded yet.|r", { indent = 2, size = 11, gap = 3 })
    else
      local tip = {}
      for _, a in ipairs(active) do if a.def and a.def.note then tip[#tip + 1] = a.label .. ": " .. a.def.note end end
      list:Add((#active > 0 and self:AffixIcons(active) or (HEX.muted .. "none|r"))
        .. (assumed and (HEX.muted .. "  (key level unknown: assuming " .. lvl .. "; set it on Applicants)|r") or (HEX.muted .. "  (hover for what each changes)|r")),
        { indent = 2, size = 11, gap = 3, tooltip = #tip > 0 and table.concat(tip, "\n\n") or nil })
    end
  end
  list:Space(8)
  list:Add(HEX.muted .. "Essentials shows what to fix. |r" .. HEX.accent .. "Everything|r" .. HEX.muted .. " shows every need, who covers it and why.|r",
    { size = 10, gap = 2, onClick = toAll, tooltip = "Switch this tab to Everything" })
  list:Finish()
  if self.pendingJump and self.cp.rowY[self.pendingJump] then list:ScrollTo(self.cp.rowY[self.pendingJump] - 4) end
  self.pendingJump = nil
end

---------------------------------------------------------------------------
-- Your brief (the Dungeon tab's left panel) and "Your plan" (the Plan tab's), from Brief.lua
---------------------------------------------------------------------------
local function CastLine(e, dk)
  return Decorate(e.cast, e.req.need, dk) .. (e.mob and (HEX.muted .. " " .. e.mob .. "|r") or "")
end

local function PartnerText(list)
  local t = {}
  for _, p in ipairs(list or {}) do t[#t + 1] = ClassHex(p.class) .. UI.ShortLabel(p.label) .. "|r" end
  return table.concat(t, HEX.muted .. ", |r")
end

local function CastNames(list)
  local t = {}
  for _, e in ipairs(list) do t[#t + 1] = e.cast end
  return table.concat(t, ", ")
end

-- The sections of a brief: kick, stop, dispel, defensive, "not yours, but know it", and the
-- count of what it leaves to the walkthrough. `b` from Brief:Build.
function UI:RenderBrief(L, b)
  local dk = b.dk
  local solo = b.solo
  local function head(title, sub) L:Add(HEX.text .. title .. "|r" .. (sub and sub ~= "" and (HEX.muted .. " " .. sub .. "|r") or ""), { size = 12, gap = 2 }) end
  local function tipOf(e) return e.req.note end

  -- Kick
  local k = b.kick
  local ability = k.abilities[1] and ("(" .. k.abilities[1] .. ")") or ""
  if k.none then
    head("Kick")
    L:Add(HEX.warn .. "Your spec has no interrupt: use your stops and call for kicks.|r", { indent = 8, size = 11, gap = 2 })
  elseif #k.mine + #k.free + #k.backup > 0 then
    head(solo and "Kick" or "Yours to kick", ability .. (k.shared and (", shared with |r" .. PartnerText(k.shared) .. HEX.muted) or ""))
    for _, e in ipairs(k.mine) do
      local with = (not solo and not k.shared and #e.partners > 0) and (HEX.muted .. "  with |r" .. PartnerText(e.partners)) or ""
      local alone = (not solo and #e.partners == 0) and (HEX.warn .. "  yours alone|r") or ""
      L:Add((solo and (HEX.muted .. "First: |r") or "") .. CastLine(e, dk) .. with .. alone, { indent = 8, size = 11, gap = 1, tooltip = tipOf(e) })
    end
    if #k.mine == 0 and #k.free + #k.backup > 0 then
      L:Add(HEX.muted .. "Nothing critical or high is yours to kick here.|r", { indent = 8, size = 10, gap = 1 })
    end
    if #k.free > 0 then L:Add(HEX.muted .. "When free: " .. CastNames(k.free) .. "|r", { indent = 8, size = 10, gap = 1 }) end
    if #k.backup > 0 then L:Add(HEX.muted .. "Backup on " .. CastNames(k.backup) .. ".|r", { indent = 8, size = 10, gap = 1 }) end
  else
    head(solo and "Kick" or "Yours to kick", ability)
    L:Add(HEX.muted .. "No kick is assigned to you here: help when free.|r", { indent = 8, size = 10, gap = 1 })
  end
  L:Space(5)

  -- Stop
  local st = b.stop
  if #st.mine + #st.also > 0 then
    head(solo and "Stop" or "Your stop", #st.abilities > 0 and ("(" .. table.concat(st.abilities, ", ") .. ")") or "")
    for _, e in ipairs(st.mine) do
      local how = e.instead and (HEX.muted .. "  instead of " .. ns.Assignments.InsteadOf(nil, e.instead) .. ", with " .. tostring(e.ability) .. "|r")
        or ((not solo and not e.aoe) and (HEX.muted .. ": anyone with CC|r") or "")
      L:Add(CastLine(e, dk) .. how, { indent = 8, size = 11, gap = 1, tooltip = tipOf(e) })
    end
    if #st.also > 0 then
      local t = {}
      for _, e in ipairs(st.also) do t[#t + 1] = e.cast .. (e.aoe and " (one AoE stop)" or "") end
      L:Add(HEX.muted .. "Also: " .. table.concat(t, ", ") .. "|r", { indent = 8, size = 10, gap = 1 })
    end
    L:Space(5)
  end

  -- Dispel, purge, soothe
  local d = b.dispel
  if #d.mine + #d.backup > 0 then
    head(solo and "Dispel" or "Yours to dispel")
    for _, e in ipairs(d.mine) do
      local tail = e.backupWho and (HEX.muted .. "  backup |r" .. PartnerText({ e.backupWho }))
        or (e.noBackup and not solo and (HEX.warn .. "  no backup: don't miss one|r") or "")
      L:Add(CastLine(e, dk) .. HEX.muted .. " (" .. e.type .. ", " .. tostring(e.ability) .. ")|r" .. (BIG[e.severity] and ("  " .. SevTag(e.severity)) or "") .. tail,
        { indent = 8, size = 11, gap = 1, tooltip = tipOf(e) })
    end
    if #d.backup > 0 then L:Add(HEX.muted .. "Backup on " .. CastNames(d.backup) .. ".|r", { indent = 8, size = 10, gap = 1 }) end
    L:Space(5)
  end

  -- Defensives (tanks and healers: the tank busters)
  local def = b.defense
  if #def.mine > 0 then
    head(b.role == "TANK" and (solo and "Defensive" or "Your defensives") or "Tank busters", "(" .. def.count .. " " .. def.label .. ")")
    for _, e in ipairs(def.mine) do
      L:Add(Decorate(e.req.source, e.req.need, dk), { indent = 8, size = 11, gap = 1, tooltip = tipOf(e) })
    end
    L:Space(5)
  end

  -- Not yours, but know it
  if #b.notYours > 0 then
    head("Not yours, but know it")
    for _, e in ipairs(b.notYours) do
      L:Add(CastLine(e, dk) .. "  " .. SevTag(e.severity), { indent = 8, size = 11, gap = 1 })
      L:Add(HEX.muted .. e.why .. (e.req.note and (" " .. e.req.note) or "") .. "|r", { indent = 8, size = 10, gap = 3 })
    end
    L:Space(5)
  end

  -- Every big row is listed above; if one ever isn't (restBig), the count says so rather than
  -- calling it medium or low (1.7.0 review, R3).
  local more = b.rest + (b.restBig or 0)
  if more > 0 then
    local what = (b.restBig or 0) > 0 and (" (" .. b.restBig .. " critical or high)") or " (medium and low)"
    L:Add(HEX.muted .. "+ " .. more .. " more" .. what .. " that " .. (more == 1 and "isn't" or "aren't") .. " yours: see the walkthrough or the Plan tab.|r", { size = 10, gap = 2 })
  end
  if b.skipped > 0 then
    L:Add(HEX.muted .. b.skipped .. " trash row" .. (b.skipped == 1 and "" or "s") .. " hidden by you (left out here).|r", { size = 10, gap = 2 })
  end
end

-- The Bloodlust plan, short: one clickable line per use (the same menu as the Plan tab).
function UI:RenderBriefLust(L, b)
  local WT = ns.Walkthrough
  local dk = b.dk
  local lust = b.lust
  if not (WT and lust) then return end
  L:Add(HEX.text .. "Bloodlust|r" .. HEX.muted .. " (" .. (lust.custom and "your timing" or "suggested") .. (lust.yours and "; you bring it" or "") .. ")|r", { size = 12, gap = 2 })
  if #lust.uses == 0 then L:Add(HEX.muted .. "None planned.|r", { indent = 8, size = 11, gap = 1 }) end
  for i, u in ipairs(lust.uses) do
    L:Add(HEX.warn .. i .. ".|r " .. WT:SpotLabel(dk, u.at) .. (u.note and (HEX.muted .. ", " .. u.note .. "|r") or ""), { indent = 8, size = 11, gap = 1,
      tooltip = WT:LustSource(dk) .. "\nClick to move it, add a note or remove it.", onClick = function(btn) UI:OpenLustMenu(btn, dk, i) end })
  end
  if #lust.uses < WT.LUST_MAX then
    L:Add(HEX.accent .. "+ Add a Bloodlust|r", { indent = 8, size = 10, gap = 1,
      onClick = function(btn) UI:OpenLustMenu(btn, dk, #lust.uses + 1) end, tooltip = "Pick where it goes" })
  end
  if lust.custom then
    L:Add(HEX.accent .. "> Reset to the default|r", { indent = 8, size = 10, gap = 1, onClick = function() WT:ResetLust(dk) end })
  end
  L:Space(5)
end

-- The Dungeon tab's left panel.
function UI:RenderBriefPanel(L, dk, level)
  local pp = self.pp
  L:Clear()
  local b = ns.Brief and ns.Brief:ForPlayer(dk)
  self.lastBrief = b
  if not b then
    pp.briefTitle:SetText("Your brief")
    L:Add(HEX.muted .. "Your spec isn't known yet, so there's nothing to tailor. The walkthrough on the right has every role's part; pick a role with Show.|r", { size = 11, gap = 4 })
    L:Finish()
    return
  end
  pp.briefTitle:SetText("Your brief" .. HEX.muted .. "  " .. UI.ShortLabel(b.spec):upper() .. (level and (", +" .. level) or "") .. "|r")
  self:RenderBrief(L, b)
  self:RenderBriefLust(L, b)
  L:Add(HEX.muted .. (b.solo and "No group needed. In a group, \"First\" becomes \"Yours\" and names who shares each cast."
    or "For the group you're in. \"Yours\" means you own the cast with whoever is named; take it when your kick is ready.") .. "|r", { size = 10, gap = 2 })
  L:Finish()
end

-- The Plan tab's left panel in Essentials: owners instead of ordinals.
function UI:RenderYourPlan(L, r, plan, live, dk)
  if not plan or (plan.empty and #(plan.others or {}) == 0) then return end
  local b = ns.Brief and dk and ns.Brief:Build(dk, r, plan)
  if not b then
    if not live then
      local mine = ns.API.GetPlayerSpecID and ns.API.GetPlayerSpecID()
      if mine and UD():GetSpec(mine) then
        L:Add(HEX.muted .. "Put your own spec (" .. UD():SpecName(mine) .. " " .. UD():ClassName(UD():GetSpec(mine).class)
          .. ") in a slot to see what you'd be responsible for.|r", { size = 10, gap = 4 })
      end
    end
    return
  end
  L:Add(HEX.muted .. "As " .. b.spec .. ".|r", { size = 10, gap = 4 })
  self:RenderBrief(L, b)
  L:Add(HEX.muted .. "\"Yours\" replaces \"1st of 2\": you and your partner own a cast, and whoever has the kick ready takes it. The exact order is under Everything.|r",
    { size = 10, gap = 6 })
end

---------------------------------------------------------------------------
-- Plan: "The big ones" with owners, the rest counted and named
---------------------------------------------------------------------------
local KIND_WORD = { kick = "Kick", dispel = "Dispel" }
local function VerbWord(e)
  if e.kind == "dispel" then return (e.row.type == "Purge" and "Purge") or (e.row.type == "Soothe" and "Soothe") or "Dispel" end
  if KIND_WORD[e.kind] then return KIND_WORD[e.kind] end
  local need = e.row.need or e.row.req.need
  if need == "stop" or need == "aoe_stop" then return need == "aoe_stop" and "AoE stop" or "Stop" end
  return UD():CapShort(need)
end

-- Rows for a dungeon with no group yet: the data's requirements, most dangerous first.
local function DataRows(dk)
  local out = {}
  for _, cat in ipairs(UI:CheatSheetRows(dk) or {}) do
    for _, req in ipairs(cat.reqs) do
      local kind = req.need == "interrupt" and "kick" or (AS().DISPEL_KEYS[req.need] and "dispel" or "other")
      out[#out + 1] = { kind = kind, big = BIG[req.severity] or false,
        row = { req = req, cast = AS().CastName(req), severity = req.severity, need = req.need, type = AS().DISPEL_KEYS[req.need], notes = {} } }
    end
  end
  local RANK = DD().SEVERITY_RANK
  local KR = { dispel = 1, kick = 2, other = 3 }
  table.sort(out, function(a, b)
    local x, y = RANK[a.row.severity] or 9, RANK[b.row.severity] or 9
    if x ~= y then return x < y end
    if KR[a.kind] ~= KR[b.kind] then return KR[a.kind] < KR[b.kind] end
    return tostring(a.row.req.id) < tostring(b.row.req.id)
  end)
  return out
end

function UI:RenderBigRow(L, e, hasPlan)
  local row = e.row
  local req = row.req
  local text = SevTag(row.severity) .. "  " .. HEX.text .. VerbWord(e) .. "|r"
    .. ((e.kind == "dispel" and VerbWord(e) == "Dispel") and (HEX.muted .. " (" .. tostring(row.type) .. ")|r") or "")
    .. "  " .. Decorate(req.source, req.need, req.dungeon)
    .. (req.affix and (HEX.muted .. " (affix: " .. req.affix .. ")|r") or "")
    .. (req.confidence ~= "verified" and (HEX.warn .. " [unconfirmed]|r") or "")
  L:Add(text, { indent = 2, size = 11, gap = 1, tooltip = req.note })
  if not hasPlan then return end
  local owners = AS().Owners(row)
  local tip = {}
  local line
  if e.kind == "other" and (row.need == "stop") and #owners > 0 then
    line = HEX.text .. "Anyone with CC|r"
    for _, w in ipairs(owners) do tip[#tip + 1] = UI.DutyPlain(w) end
  elseif #owners > 0 then
    local names = {}
    for i, w in ipairs(owners) do
      names[#names + 1] = UI.DutyShort(w)
      tip[#tip + 1] = ((e.kind == "kick" and #owners > 1) and (AS().Ord(i) .. " ") or "") .. UI.DutyPlain(w)
    end
    line = table.concat(names, HEX.muted .. " + |r")
    if row.stoppers and not (row.kickers and #row.kickers > 0) and not row.primary then line = HEX.muted .. "instead: |r" .. line end
  else
    line = HEX.bad .. "Nobody in the group|r"
  end
  if row.backup then tip[#tip + 1] = "Backup: " .. UI.DutyPlain(row.backup) end
  if e.kind == "kick" and #owners > 1 and row.every then tip[#tip + 1] = "Together a kick every ~" .. row.every .. "s" end
  if row.manual then line = line .. HEX.accent .. "  (set by you)|r" end
  local editable = (e.kind == "kick" and row.kickers and #row.kickers > 0) or (e.kind == "dispel" and row.primary)
  if editable then tip[#tip + 1] = "Click to choose who takes it." end
  L:Add(line, { indent = 26, size = 11, gap = 1, tooltip = #tip > 0 and table.concat(tip, "\n") or nil,
    onClick = editable and function(btn) UI:OpenAssignMenu(btn, row) end or nil })
  for _, n in ipairs(row.notes or {}) do
    L:Add((row.severe and HEX.bad or HEX.warn) .. n .. "|r", { indent = 26, size = 10, gap = 1 })
  end
  L:Space(3)
end

function UI:RenderBigOnes(L, dungeonKey, r, plan)
  if not (dungeonKey and DD().list[dungeonKey]) then
    L:Add(HEX.muted .. "Pick a dungeon to see its must-kick, must-dispel and must-stop list.|r", { size = 11 })
    return
  end
  local hasPlan = plan ~= nil
  local big, rest = {}, {}
  if hasPlan then big, rest = AS():BigRows(plan)
  else
    for _, e in ipairs(DataRows(dungeonKey)) do
      if e.big then big[#big + 1] = e else rest[#rest + 1] = e end
    end
  end
  L:Header("The big ones (" .. #big .. ")")
  if #big == 0 then
    L:Add(HEX.muted .. "Nothing critical or high to assign here.|r", { indent = 2, size = 11, gap = 3 })
  end
  for _, e in ipairs(big) do self:RenderBigRow(L, e, hasPlan) end
  if hasPlan and not plan.empty then
    local pri = AS():Priority(plan)
    if pri then L:Add(HEX.text .. "Two casts at once? Kick first:|r " .. pri, { size = 10, gap = 4 }) end
  end
  if #rest > 0 then
    local key = "sheet:rest"
    local open = self:IsOpen(key, false)
    local names = {}
    for _, e in ipairs(rest) do names[#names + 1] = e.row.cast end
    L:Add(HEX.accent .. (open and "- " or "+ ") .. #rest .. " more assignment" .. (#rest == 1 and "" or "s") .. "|r"
      .. HEX.muted .. " (medium and low)" .. (open and "" or (": " .. table.concat(names, ", "))) .. "|r", { size = 11, gap = 4,
      onClick = function() UI:SetOpen(key, not open) end, tooltip = open and "Fold them" or "Show each one with who takes it" })
    if open then for _, e in ipairs(rest) do self:RenderBigRow(L, e, hasPlan) end end
  end
end

-- Trash you skip is out of the plan; say how much and where to change it.
function UI:RenderPlanSkipped(L, plan)
  local n = plan and #(plan.skipped or {}) or 0
  if n == 0 then return end
  local names = {}
  for _, req in ipairs(plan.skipped) do names[#names + 1] = AS().CastName(req) end
  L:Space(4)
  L:Add(HEX.muted .. n .. " trash row" .. (n == 1 and "" or "s") .. " hidden by you " .. (n == 1 and "isn't" or "aren't") .. " in the plan or its posts: " .. table.concat(names, ", ")
    .. ". Change it from the Dungeon tab (Edit this section).|r", { size = 10, gap = 3 })
end

---------------------------------------------------------------------------
-- Dungeon tab: the walkthrough in Essentials (with D1: each need in full once)
---------------------------------------------------------------------------
UI.WALK_BOSS_LINES = 3

local function NeedWord(q)
  if q.need == "interrupt" then return "Kick" end
  return UD():CapShort(q.need)
end

-- Every ability a requirement's source names: "Lightning Spire soaks (Galvazzt), Caustic Stomp
-- (Orb Watcher)" -> "Lightning Spire soaks, Caustic Stomp" (a one-line mention must not drop
-- the one that happens in this section).
local function AllNames(q)
  local flat = tostring(q.source or ""):gsub("%b()", "")
  local t = {}
  for part in flat:gmatch("[^,]+") do
    local name = part:gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" then t[#t + 1] = name end
  end
  return #t > 0 and table.concat(t, ", ") or AS().CastName(q)
end
UI.ReqNames = AllNames

function UI:WalkEssRow(L, q, movedFrom, notYours)
  local alts = {}
  for _, a in ipairs(q.alt or {}) do alts[#alts + 1] = UD():CapShort(a) end
  local explain = UD():CapExplain(q.need)
  local tip = {}
  if q.note and not (q.need == "interrupt" and q.note == "Interrupt every cast.") then tip[#tip + 1] = q.note end
  if explain then tip[#tip + 1] = UD():CapLabel(q.need) .. ": " .. explain end
  if movedFrom then tip[#tip + 1] = "Moved here by you. The guides list it before " .. movedFrom.name .. "." end
  L:Add(SevTag(q.severity) .. "  " .. HEX.text .. NeedWord(q) .. "|r  " .. Decorate(q.source, q.need, q.dungeon)
    .. (#alts > 0 and (HEX.muted .. " (or " .. table.concat(alts, " / ") .. ")|r") or "")
    .. (q.affix and (HEX.muted .. " (affix: " .. q.affix .. ")|r") or "")
    .. (q.confidence ~= "verified" and (HEX.warn .. " [unconfirmed]|r") or "")
    .. (movedFrom and (HEX.accent .. "  moved here by you|r") or "")
    .. (notYours and (HEX.muted .. "  (not your role's, but know it)|r") or ""),
    { indent = 8, size = 11, gap = 1, tooltip = #tip > 0 and table.concat(tip, "\n\n") or nil })
end

-- A section's needs: the critical and high ones in full (first time only), the rest on a
-- "+ N more" line, and what an earlier section already showed on an "Also here:" line.
-- `reqs` are the role's; `others` are the ones the role filter leaves out. A critical one is
-- shown to every role (with whose it is), a high one is named on the "Other roles:" line.
function UI:WalkEssNeeds(L, dk, st, reqs, others, skey, trash)
  local bosses = ns.BossCards:Bosses(dk)
  local big, rest, also = {}, {}, {}
  for _, q in ipairs(reqs) do
    if st.also[q.id] then also[#also + 1] = q
    elseif BIG[q.severity] then big[#big + 1] = q
    else rest[#rest + 1] = q end
  end
  -- Other roles' rows: critical in full, high named, a repeat of a big one on "Also here",
  -- and the medium and low ones counted (1.7.0 review, R4: nothing hidden without a count).
  local otherCrit, otherHigh, otherRest, otherAlso = {}, {}, {}, {}
  for _, q in ipairs(others or {}) do
    if st.also[q.id] then
      if BIG[q.severity] then also[#also + 1] = q; otherAlso[q] = true else otherRest[#otherRest + 1] = q end
    elseif q.severity == "critical" then otherCrit[#otherCrit + 1] = q
    elseif q.severity == "high" then otherHigh[#otherHigh + 1] = q
    else otherRest[#otherRest + 1] = q end
  end
  local alsoBig = false
  for _, q in ipairs(also) do if BIG[q.severity] then alsoBig = true end end
  local open = self:IsOpen(skey, false)
  local function moved(q) return st.moved and st.moved[q.id] and bosses[st.moved[q.id]] end
  local function note(q)
    if q.severity == "critical" and q.note then L:Add(HEX.muted .. q.note .. "|r", { indent = 22, size = 10, gap = 2 }) end
  end
  for _, q in ipairs(big) do self:WalkEssRow(L, q, moved(q)); note(q) end
  for _, q in ipairs(otherCrit) do self:WalkEssRow(L, q, moved(q), true); note(q) end
  -- "Nothing critical or high" only when it's true: a big repeat on "Also here" is still here.
  if trash and #big + #otherCrit == 0 and not alsoBig and (#rest + #also + #otherHigh + #otherRest) > 0 then
    L:Add(HEX.muted .. (#otherHigh > 0 and "Nothing critical or high for your role here." or "Nothing critical or high here.") .. "|r", { indent = 8, size = 11, gap = 1 })
  end
  if #rest > 0 then
    local names = {}
    for _, q in ipairs(rest) do names[#names + 1] = AllNames(q) end
    L:Add(HEX.accent .. (open and "- " or "+ ") .. #rest .. " more|r" .. HEX.muted .. (open and " (medium and low)" or (": " .. table.concat(names, ", "))) .. "|r", {
      indent = 8, size = 10, gap = 1, onClick = function() UI:SetOpen(skey, not open) end,
      tooltip = open and "Fold them" or "Show each one in full" })
    if open then
      for _, q in ipairs(rest) do self:WalkEssRow(L, q, moved(q)) end
    end
  end
  if #otherHigh > 0 then
    local names = {}
    for _, q in ipairs(otherHigh) do names[#names + 1] = AllNames(q) .. " (" .. NeedWord(q):lower() .. ", high)" end
    L:Add(HEX.muted .. "Other roles: " .. table.concat(names, ", ") .. "|r", { indent = 8, size = 10, gap = 1,
      tooltip = "High-severity needs your role doesn't handle. Set Show to All to see them in full." })
  end
  if #otherRest > 0 then
    local names = {}
    for _, q in ipairs(otherRest) do names[#names + 1] = AllNames(q) end
    L:Add(HEX.muted .. "+ " .. #otherRest .. " for other roles (medium and low): " .. table.concat(names, ", ") .. "|r", { indent = 8, size = 10, gap = 1,
      tooltip = "Set Show to All to see them in full." })
  end
  if #also > 0 then
    local names = {}
    for _, q in ipairs(also) do
      names[#names + 1] = AllNames(q) .. " (" .. NeedWord(q):lower() .. (otherAlso[q] and (", " .. q.severity .. ", other roles") or "") .. ")"
    end
    L:Add(HEX.muted .. "Also here: " .. table.concat(names, ", ") .. "|r", { indent = 8, size = 10, gap = 1,
      tooltip = "Shown in full in the first section it happens in." })
  end
end

function UI:RenderWalkEssentials(L, key)
  local WT, BC = ns.Walkthrough, ns.BossCards
  local role = self:WalkRole()
  local w = WT:Build(key)
  if not w then return end
  local tags = ns.BossWindow and ns.BossWindow.ROLE_TAG or {}
  local bosses = BC:Bosses(key)
  if BC:IsCustomOrder(key) then
    local first = bosses[BC:Order(key)[1]]
    L:Add(HEX.muted .. "Boss order: yours" .. (first and (", " .. first.name .. " first") or "") .. ".|r  " .. HEX.accent .. "> Reset to the guides' order|r",
      { size = 10, gap = 4, onClick = function() BC:ResetOrder(key) end, tooltip = "Back to the order the dungeon guides list" })
  end
  for _, st in ipairs(w.steps) do
    local reqs, others = {}, {}
    for _, q in ipairs(st.reqs) do
      if self:WalkRoleWants(role, q) then reqs[#reqs + 1] = q else others[#others + 1] = q end
    end
    local otherBig = 0
    for _, q in ipairs(others) do if BIG[q.severity] and not st.also[q.id] then otherBig = otherBig + 1 end end
    if st.kind == "anywhere" then
      if #reqs + otherBig > 0 then
        L:Header("Throughout the dungeon")
        self:WalkEssNeeds(L, key, st, reqs, others, "walk:" .. key .. ":any", true)
      end
    elseif st.kind == "trash" then
      local lust = WT:LustAt(key, st)
      local shown = #reqs + otherBig > 0 or #lust > 0
      if shown then
        local head = bosses[st.boss] and ("Trash before " .. bosses[st.boss].name) or "Trash after the last boss"
        if st.merged then
          local names = {}
          for _, b in ipairs(st.bosses) do names[#names + 1] = bosses[b].name end
          head = "Trash before " .. table.concat(names, " and ")
        end
        L:Header(head)
        self:WalkLust(L, key, st)
        self:WalkEssNeeds(L, key, st, reqs, others, "walk:" .. key .. ":t" .. st.boss, true)
      end
      self:WalkTrashEdit(L, key, st, shown)
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
        local mine, otherLines = {}, 0
        for _, l in ipairs(lines) do
          if role == "ALL" or l.role == role or l.role == "ALL" then mine[#mine + 1] = l else otherLines = otherLines + 1 end
        end
        local lkey = "bosslines:" .. key .. ":" .. i
        local all = self:IsOpen(lkey, false)
        local n = all and #mine or math.min(self.WALK_BOSS_LINES, #mine)
        for j = 1, n do
          local l = mine[j]
          L:Add((tags[l.role] or l.role) .. "  " .. BC:Decorate(key, l.text) .. (l.nv and (HEX.warn .. " [unconfirmed]|r") or ""), { indent = 10, size = 11, gap = 1 })
        end
        local more = #mine - n
        if more > 0 or all or otherLines > 0 then
          local parts = {}
          if all then parts[#parts + 1] = HEX.accent .. "- show fewer|r"
          elseif more > 0 then parts[#parts + 1] = HEX.accent .. "+ " .. more .. " more line" .. (more == 1 and "" or "s") .. "|r" end
          if otherLines > 0 then parts[#parts + 1] = HEX.muted .. "other roles: " .. otherLines .. "|r" end
          L:Add(table.concat(parts, DOT), { indent = 10, size = 10, gap = 1,
            onClick = (more > 0 or all) and function() UI:SetOpen(lkey, not all) end or nil,
            tooltip = ((more > 0 or all) and (all and "Show fewer lines" or "Show every line for this role") or "")
              .. (otherLines > 0 and (((more > 0 or all) and "\n" or "") .. "Lines for other roles: set Show to All.") or "") })
        end
        self:WalkEssNeeds(L, key, st, reqs, others, "walk:" .. key .. ":b" .. i, false)
        L:Add(HEX.accent .. "> Open in the boss window|r" .. HEX.muted .. " (edit the card or post it from there)|r", { indent = 10, size = 10, gap = 4,
          onClick = function() ns.BossWindow.view = { dk = key, index = i, phase = "boss" }; ns.BossWindow:Show() end })
      end
    end
  end
end

---------------------------------------------------------------------------
-- The trash section editor: hide a row ("we skip this") or move it to another boss's section.
-- Opened from "Edit this section" under a trash section on the Dungeon tab and from the boss
-- window's Edit button on a trash page. Saved per dungeon (Walkthrough.lua).
---------------------------------------------------------------------------
function UI:OpenTrashEditor(dk, section)
  if not (dk and DD().list[dk] and ns.BossCards:Boss(dk, section)) then return end
  self:Build()
  local e = self.trashEditor
  if not e then
    e = CreateFrame("Frame", "EnsembleTrashEditor", UIParent, "BackdropTemplate")
    K.Skin(e, C.bg, C.border)
    e:SetSize(540, 400); e:SetPoint("CENTER"); e:SetFrameStrata("DIALOG")
    e:SetMovable(true); e:EnableMouse(true); e:RegisterForDrag("LeftButton")
    e:SetScript("OnDragStart", e.StartMoving); e:SetScript("OnDragStop", e.StopMovingOrSizing)
    e.title = K.Text(e, 13, C.text); e.title:SetPoint("TOPLEFT", 12, -10); e.title:SetPoint("RIGHT", -12, 0)
    e.title:SetWordWrap(false)
    e.help = K.Text(e, 10, C.muted); e.help:SetPoint("TOPLEFT", 12, -30); e.help:SetPoint("RIGHT", -12, 0)
    e.help:SetText("From the dungeon guides by default. Hide what your group skips, or move a row to the section where you fight it. "
      .. "This changes the Dungeon tab, the boss window, Your brief, the Plan and its posts. Needs, pick ratings and Fill group keep the guides' full list.")
    e.list = K.LineList(e, 516, 270):Fill(10, -78, -10, 44)
    e.note = K.Text(e, 10, C.muted); e.note:SetPoint("BOTTOMLEFT", 12, 16); e.note:SetPoint("RIGHT", -230, 0); e.note:SetWordWrap(false)
    e.close = K.Button(e, "Close", 80, 24, function() e:Hide() end)
    e.close:SetPoint("BOTTOMRIGHT", -12, 10)
    e.reset = K.Button(e, "Reset to the guides", 130, 24, function() ns.Walkthrough:ResetTrash(e.dk) end)
    e.reset:SetPoint("RIGHT", e.close, "LEFT", -6, 0)
    e.reset.tooltip = "Put every trash row of this dungeon back where the guides have it"
    if e.reset.SetMotionScriptsWhileDisabled then e.reset:SetMotionScriptsWhileDisabled(true) end
    if UISpecialFrames then table.insert(UISpecialFrames, "EnsembleTrashEditor") end
    self.trashEditor = e
  end
  e.dk, e.section = dk, section
  e:Show()
  self:RenderTrashEditor()
end

-- The sections a row can move to: every other boss's trash, in your boss order.
function UI:TrashMoveMenu(anchor, dk, id, from, current)
  local WT, BC = ns.Walkthrough, ns.BossCards
  local bosses = BC:Bosses(dk)
  local items = { { text = "Move it to:", header = true } }
  for _, bi in ipairs(BC:Order(dk)) do
    if bi ~= current then
      items[#items + 1] = { text = "Trash before " .. bosses[bi].name .. (bi == from and "  (where the guides have it)" or ""),
        onClick = function() WT:MoveRow(dk, id, from, bi) end }
    end
  end
  if anchor then self:ShowMenu(anchor, items) end
  return items
end

function UI:RenderTrashEditor()
  local e = self.trashEditor
  if not (e and e:IsShown()) then return end
  local WT, BC = ns.Walkthrough, ns.BossCards
  local dk, section = e.dk, e.section
  local bosses = BC:Bosses(dk)
  local function where(b) return "Trash before " .. (bosses[b] and bosses[b].name or "?") end
  e.title:SetText("Edit section: " .. where(section) .. HEX.muted .. "  (" .. DD().list[dk].name .. ")|r")
  local L = e.list
  L:Clear()
  local rows = WT:SectionRows(dk, section)
  if #rows == 0 then
    L:Add(HEX.muted .. "The guides list no trash needs before this boss. Rows you move here from another section will show up in this list.|r", { size = 11 })
  end
  for _, x in ipairs(rows) do
    local q = x.req
    local id, from = q.id, x.from
    local what = SevTag(q.severity) .. "  " .. HEX.text .. NeedWord(q) .. "|r  " .. Decorate(q.source, q.need, q.dungeon)
    if x.state == "shown" or x.state == "movedIn" then
      L:Add(TEX_OK .. " " .. what .. (x.state == "movedIn" and (HEX.accent .. "  moved here by you (from " .. where(from) .. ")|r") or ""),
        { size = 11, gap = 1, tooltip = q.note })
      if x.state == "shown" then
        L:Add(HEX.accent .. "> Hide: we skip this|r", { indent = 22, size = 10, gap = 1,
          onClick = function() WT:HideRow(dk, id, from) end, tooltip = "Leave it out of this section. It stays counted (\"hidden by you\")." })
      else
        L:Add(HEX.accent .. "> Put it back|r" .. HEX.muted .. " (" .. where(from) .. ")|r", { indent = 22, size = 10, gap = 1,
          onClick = function() WT:RestoreRow(dk, id, from) end })
      end
      L:Add(HEX.accent .. "> Move to another section...|r", { indent = 22, size = 10, gap = 5,
        onClick = function(btn) UI:TrashMoveMenu(btn, dk, id, from, section) end })
    elseif x.state == "hidden" then
      L:Add(TEX_NO .. " " .. HEX.muted .. "hidden by you:|r " .. what, { size = 11, gap = 1, tooltip = q.note })
      L:Add(HEX.accent .. "> Show it again|r", { indent = 22, size = 10, gap = 5, onClick = function() WT:RestoreRow(dk, id, from) end })
    else
      L:Add(TEX_WAIT .. " " .. HEX.muted .. "moved by you to " .. where(x.to) .. ":|r " .. what, { size = 11, gap = 1, tooltip = q.note })
      L:Add(HEX.accent .. "> Put it back here|r", { indent = 22, size = 10, gap = 5, onClick = function() WT:RestoreRow(dk, id, from) end })
    end
  end
  L:Finish()
  local h, m = WT:TrashEditCounts(dk)
  e.note:SetText(h + m > 0 and (h .. " hidden and " .. m .. " moved in this dungeon.") or "Nothing changed: this dungeon follows the guides.")
  if h + m > 0 then e.reset:Enable() else e.reset:Disable() end
  e.reset:SetAlpha(e.reset:IsEnabled() and 1 or 0.5)
end

ns:On("TRASH_CHANGED", function()
  if UI.trashEditor and UI.trashEditor:IsShown() then UI:RenderTrashEditor() end
end)
ns:On("BOSS_ORDER_CHANGED", function()
  if UI.trashEditor and UI.trashEditor:IsShown() then UI:RenderTrashEditor() end
end)
