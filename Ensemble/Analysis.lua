-- Ensemble / Analysis.lua  (Features 4 + 5, and the Feature 2 "suggest replacement")
-- Pure functions over data: no frames, no events. Input is a list of members:
--   { specID = n|nil, classFile = "MAGE"|nil, pending = bool|nil, label = "name"|nil }
-- Empty slots are simply absent from the list, so partial comps need no special casing.

local _, ns = ...

local Analysis = {}
ns.Analysis = Analysis

local UD -- resolved lazily (load order: UtilityDatabase before this file, but be safe)

local SEV_RANK = { critical = 1, high = 2, medium = 3, low = 4, info = 5 }
local SEV_WEIGHT = { critical = 40, high = 20, medium = 8, low = 2, info = 0 }
local STATUS_RANK = { missing = 1, thin = 2, covered = 3 }

local FRIENDLY_DISPELS = { "dispel_magic", "dispel_curse", "dispel_poison", "dispel_disease" }

---------------------------------------------------------------------------
-- Member resolution
---------------------------------------------------------------------------
local function Resolve(members)
  UD = UD or ns.UD
  local out = {}
  for _, m in ipairs(members or {}) do
    local profile, pending
    -- m.profile: a ready-made profile (e.g. your own spec with the talents you know).
    if m.profile then profile = m.profile
    elseif m.specID and m.specID ~= 0 then profile = UD:GetSpec(m.specID) end
    if not profile and m.classFile then
      profile = UD:ClassCommonProfile(m.classFile)
      pending = true
    end
    if profile then
      local label = m.label
      if not label then
        label = pending and (UD:ClassName(profile.class) .. " (spec pending)")
          or (UD:SpecName(profile.id) .. " " .. UD:ClassName(profile.class))
      end
      table.insert(out, {
        profile = profile, pending = pending or profile.pending or false,
        classFile = profile.class,
        -- A pending member has no spec role; fall back to their assigned group role.
        role = profile.role or ((m.role == "TANK" or m.role == "HEALER" or m.role == "DAMAGER") and m.role or nil),
        range = profile.range,
        label = label, specID = (not pending) and profile.id or nil,
        applicant = m.applicant or nil,   -- passthrough so applicant-fit can find "their" providers
        isPlayer = m.isPlayer or nil,      -- passthrough so the plan can say "your assignments"
      })
    end
  end
  return out
end

-- Best usable source of `key` for one member (prefers non-soft), or nil.
local function BestSource(member, key, settings)
  local list = UD:Sources(member.profile, key, settings)
  if not list then return nil end
  local best
  for _, e in ipairs(list) do
    if not best or (UD:IsSoft(best) and not UD:IsSoft(e)) then best = e end
  end
  return best
end

local function IsSoftProvider(p)
  return p.member.pending or UD:IsSoft(p.entry)
end

-- Providers of a capability: one entry per member. Handles `fallback` sources (count only
-- when no unconditional provider exists in the group).
local function Providers(resolved, key, settings)
  local list, fallbacks = {}, {}
  for i, m in ipairs(resolved) do
    local e = BestSource(m, key, settings)
    if e then
      local p = { index = i, member = m, entry = e }
      if e.fallback then table.insert(fallbacks, p) else table.insert(list, p) end
    end
  end
  if #list == 0 and #fallbacks > 0 then
    for _, p in ipairs(fallbacks) do table.insert(list, p) end
  end
  return list
end

-- "Member: <ability link> (tag)" for each provider. `key` = capability (for color);
-- providers found through an `alt` key carry their own viaKey.
local function Labels(providers, key)
  local out = {}
  for _, p in ipairs(providers) do
    local tag = ""
    if p.member.pending then tag = " (assumed)"
    elseif p.entry.conditional then tag = " (" .. p.entry.conditional .. ")"
    elseif p.entry.talent then tag = " (talent)"
    elseif p.entry.pet then tag = " (pet)"
    elseif p.entry.long then tag = " (long CD)"
    elseif p.entry.verify then tag = " (unconfirmed)" end
    local name = ns.Links and ns.Links:Ability(p.entry.name, p.viaKey or key) or p.entry.name
    out[#out + 1] = p.member.label .. ": " .. name .. tag
  end
  return out
end
Analysis.Labels = Labels

local function JoinNatural(list)
  if #list == 0 then return "" end
  if #list == 1 then return list[1] end
  if #list == 2 then return list[1] .. " and " .. list[2] end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

---------------------------------------------------------------------------
-- Generic analysis (Feature 4)
---------------------------------------------------------------------------
-- `cap` (optional) = the capability that would fix this gap; drives the "Still needed" list.
local function AddFinding(r, check, severity, text, short, cap)
  table.insert(r.findings, { check = check, severity = severity, text = text, short = short or text, cap = cap })
end

local function Generic(r, resolved, settings)
  local checks = settings.checks or {}
  local n = #resolved

  -- Capability map for display.
  for _, c in ipairs(UD.CAPS) do r.caps[c.key] = Providers(resolved, c.key, settings) end

  -- Raid buffs: informational only. A 5-player group can't carry every raid buff, so a
  -- buff the group lacks is never a gap and never affects scores or suggestions; the UI
  -- simply shows which ones this group brings.
  local have = {}
  for _, m in ipairs(resolved) do
    for _, b in ipairs(m.profile.buffs) do
      if not have[b] then have[b] = m.label end
    end
  end
  for _, b in ipairs(UD.BUFFS) do
    if have[b.key] then table.insert(r.buffs.present, { key = b.key, name = b.name, class = b.class, from = have[b.key] }) end
  end

  -- Raid buff synergy: who in THIS group actually benefits from each buff it has.
  local H = ns.Dungeons and ns.Dungeons.HEURISTICS or {}
  local perPoint = H.BUFF_SYNERGY_POINTS or 1.5
  r.synergyPoints = 0
  for _, pb in ipairs(r.buffs.present) do
    local info = UD.BUFF_INFO[pb.key]
    pb.effect, pb.who = info.effect, info.who
    pb.full, pb.partial, pb.value = {}, {}, 0
    pb.universal = info.affects and info.affects.all or false
    if not pb.universal then
      for _, m in ipairs(resolved) do
        local f = UD:BuffBenefit(info, m.profile)
        if f and f > 0 then
          local roleW = (m.role == "DAMAGER") and 1 or 0.5
          pb.value = pb.value + f * roleW
          if f >= 1 then pb.full[#pb.full + 1] = m.label else pb.partial[#pb.partial + 1] = m.label end
        end
      end
      pb.points = pb.value * perPoint
      r.synergyPoints = r.synergyPoints + pb.points
      -- Strength label for display: judged on DPS-equivalent beneficiaries.
      if pb.value >= 2 then pb.strength = "strong"
      elseif pb.value >= 1 then pb.strength = "good"
      elseif pb.value > 0 then pb.strength = "minor"
      else pb.strength = "none" end
    end
  end

  -- Interrupts
  local ints = r.caps.interrupt
  local I = r.interrupts
  I.count = #ints
  I.byRole = { TANK = 0, HEALER = 0, DAMAGER = 0 }
  I.byRange = { melee = 0, ranged = 0 }
  local abilities = {}
  for _, p in ipairs(ints) do
    if p.entry.long then I.long = I.long + 1 else I.short = I.short + 1 end
    if p.member.role then I.byRole[p.member.role] = (I.byRole[p.member.role] or 0) + 1 end
    if p.member.range then I.byRange[p.member.range] = (I.byRange[p.member.range] or 0) + 1 end
    abilities[p.entry.name] = true
  end
  I.distinctAbilities = ns.Util.Count(abilities)
  if checks.interrupts ~= false and n > 0 then
    if I.count == 0 then
      AddFinding(r, "interrupts", "critical", "No interrupts in the group.", "no interrupts", "interrupt")
    else
      if I.short <= 1 then
        AddFinding(r, "interrupts", "high",
          string.format("Only %d rotational interrupt%s (%d total) - a single point of failure.", I.short, I.short == 1 and "" or "s", I.count),
          I.short == 0 and "no rotational interrupt" or "only one rotational interrupt", "interrupt")
      end
      if I.count == I.byRole.HEALER and I.count > 0 then
        AddFinding(r, "interrupts", "high", "The only interrupt is on the healer - it needs a DPS/tank kick rotation behind it.",
          "the only kick is the healer's", "interrupt")
      end
      local rolesUsed = 0
      for _, v in pairs(I.byRole) do if v > 0 then rolesUsed = rolesUsed + 1 end end
      if I.count >= 2 and rolesUsed == 1 then
        AddFinding(r, "interrupts", "low", "All interrupts sit on one role; losing that role's uptime loses every kick.",
          "interrupts stacked on one role", "interrupt")
      end
      if I.count >= 2 and I.byRange.melee == I.count then
        AddFinding(r, "interrupts", "low", "All interrupts are melee-only; ranged casters out of reach go unkicked.",
          (I.count == 2 and "both" or "all") .. " interrupts are melee-only", "interrupt")
      elseif I.count >= 2 and I.byRange.ranged == I.count then
        AddFinding(r, "interrupts", "info", "All interrupts are ranged.", "interrupts all ranged", "interrupt")
      end
      if I.count >= 3 and I.distinctAbilities == 1 then
        AddFinding(r, "interrupts", "info", "Every interrupt is the same ability (stacked class).", "identical interrupts", "interrupt")
      end
    end
  end

  -- Battle rez
  local brez = r.caps.battle_rez
  r.brez.count = #brez
  r.brez.providers = brez
  r.brez.fallbackOnly = (#brez > 0 and brez[1].entry.fallback) and true or false
  if checks.brez ~= false and n > 0 then
    if #brez == 0 then
      AddFinding(r, "brez", "high", "No battle resurrection.", "no battle rez", "battle_rez")
    elseif r.brez.fallbackOnly then
      local inter = ns.Links and ns.Links:Ability("Intercession", "battle_rez") or "Intercession"
      AddFinding(r, "brez", "medium", "Battle rez only via Holy Paladin's " .. inter .. " fallback.", "only a fallback battle rez", "battle_rez")
    elseif #brez == 1 then
      AddFinding(r, "brez", "low", "Single battle rez source - if that player dies there is no rez.", "a single battle rez", "battle_rez")
    end
  end

  -- Bloodlust
  local lust = r.caps.bloodlust
  r.lust.present = #lust > 0
  r.lust.providers = lust
  if checks.lust ~= false and n > 0 then
    if #lust == 0 then
      AddFinding(r, "lust", "high", "No Bloodlust/Heroism.", "no Bloodlust", "bloodlust")
    else
      local allSoft = true
      for _, p in ipairs(lust) do if not IsSoftProvider(p) then allSoft = false end end
      if allSoft then
        AddFinding(r, "lust", "medium", "Bloodlust depends on a conditional source (e.g. a hunter pet).", "Bloodlust is conditional", "bloodlust")
      end
    end
  end

  -- Dispels
  for _, key in ipairs(FRIENDLY_DISPELS) do
    local ps = r.caps[key]
    table.insert(r.dispels, { key = key, label = UD:CapLabel(key), count = #ps, providers = ps })
    if checks.dispels ~= false and n > 0 and #ps == 0 then
      local label = UD:CapLabel(key)
      AddFinding(r, "dispels", "medium", "No " .. label .. ".", "no " .. label, key)
    end
  end
  if checks.dispels ~= false and n > 0 then
    if #r.caps.purge == 0 then AddFinding(r, "dispels", "low", "No offensive purge.", "no purge", "purge") end
    if #r.caps.soothe == 0 then AddFinding(r, "dispels", "low", "No soothe (enrage removal).", "no soothe", "soothe") end
  end

  -- Crowd control
  local C = r.cc
  for _, t in ipairs(UD.CC_TYPES) do C.types[t] = 0 end
  for _, m in ipairs(resolved) do
    local seen = {}
    for _, c in ipairs(m.profile.cc) do
      if (settings.countTalentSources ~= false or not c.talent) and not seen[c.type] then
        seen[c.type] = true
        C.types[c.type] = (C.types[c.type] or 0) + 1
      end
    end
  end
  for _, t in ipairs(UD.CC_TYPES) do if C.types[t] > 0 then C.typeCount = C.typeCount + 1 end end
  C.stops = #r.caps.stop
  C.aoeStops = #r.caps.aoe_stop
  if checks.cc ~= false and n > 0 then
    if C.stops == 0 then
      AddFinding(r, "cc", "high", "No stop-capable CC (stun/fear/incapacitate) to end channels.", "no stops", "stop")
    elseif C.aoeStops == 0 then
      AddFinding(r, "cc", "medium", "No AoE stop for packs of casters.", "no AoE stop", "aoe_stop")
    end
    if C.typeCount <= 2 and n >= 3 then
      AddFinding(r, "cc", "low", "Low crowd-control diversity (" .. C.typeCount .. " CC types).", "little CC variety", "stop")
    end
  end

  -- Composition shape
  local classCount = {}
  for _, m in ipairs(resolved) do classCount[m.classFile] = (classCount[m.classFile] or 0) + 1 end
  for classFile, count in pairs(classCount) do
    if count >= 3 then
      AddFinding(r, "utility", "low", string.format("%d %s: duplicate classes repeat the same utility.", count, UD:ClassName(classFile)),
        "stacked " .. UD:ClassName(classFile))
    end
  end
  local roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }
  for _, m in ipairs(resolved) do if m.role then roles[m.role] = roles[m.role] + 1 end end
  r.roles = roles
  if checks.utility ~= false and n > 0 then
    if #r.caps.group_stealth == 0 then AddFinding(r, "utility", "info", "No group stealth/invis for skips.", "no skip tools", "group_stealth") end
    if #r.caps.movement == 0 then AddFinding(r, "utility", "info", "No group movement-speed cooldown.", "no group speed", "movement") end
  end
  local pendingCount = 0
  for _, m in ipairs(resolved) do if m.pending then pendingCount = pendingCount + 1 end end
  r.pendingCount = pendingCount
  if pendingCount > 0 then
    AddFinding(r, "pending", "info", pendingCount .. " member(s) still have a pending spec - only utility their whole class shares is counted.",
      "specs pending")
  end
end

---------------------------------------------------------------------------
-- Dungeon readiness (Feature 5)
---------------------------------------------------------------------------
local function DungeonCheck(r, resolved, dungeonKey, settings, opts)
  local DD = ns.Dungeons
  local d = DD and DD.list[dungeonKey]
  if not d then
    r.dungeon = { key = dungeonKey, unknown = true, items = {} }
    return
  end
  local H = DD.HEURISTICS
  local cats = settings.dungeonCategories or {}
  local out = {
    key = dungeonKey, name = d.name, items = {}, hidden = 0,
    counts = { missing = 0, thin = 0, covered = 0 }, verified = 0, total = 0,
  }
  local interruptReqs = 0

  -- This week's affixes add their own requirements (category "affixes"), filtered by key level.
  local reqs = d.requirements
  if ns.Affixes and cats.affixes ~= false and not (opts and opts.noAffixes) then
    local level = (opts and opts.keyLevel) or ns.Affixes:KeyLevel(dungeonKey)
    local extra = ns.Affixes:Requirements(dungeonKey, level, opts and opts.affixIDs)
    if #extra > 0 then
      reqs = {}
      for _, q in ipairs(d.requirements) do reqs[#reqs + 1] = q end
      for _, q in ipairs(extra) do reqs[#reqs + 1] = q end
    end
    out.affixLevel, out.affixLevelAssumed = level or ns.Affixes.ASSUMED_LEVEL, level == nil
  end

  for _, req in ipairs(reqs) do
    out.total = out.total + 1
    if req.confidence == "verified" then out.verified = out.verified + 1 end
    local category = DD:CategoryOf(req)
    local ignored = settings.ignoredNeeds or {}
    if cats[category] == false or ignored[req.need]
       or (settings.hideLowSeverity and req.severity == "low") then
      out.hidden = out.hidden + 1
    else
      -- Providers: distinct members having `need` or any `alt`.
      local providers, byMember = {}, {}
      local keys = { req.need }
      if req.alt then for _, a in ipairs(req.alt) do keys[#keys + 1] = a end end
      if not req.invalid then
        for _, key in ipairs(keys) do
          for _, p in ipairs(r.caps[key] or Providers(resolved, key, settings)) do
            local prev = byMember[p.index]
            if not prev then
              local np = { index = p.index, member = p.member, entry = p.entry, viaKey = key }
              byMember[p.index] = np
              table.insert(providers, np)
            elseif IsSoftProvider(prev) and not IsSoftProvider(p) then
              prev.entry = p.entry; prev.viaKey = key
            end
          end
        end
      end
      local n = #providers
      local allSoft = n > 0
      for _, p in ipairs(providers) do if not IsSoftProvider(p) then allSoft = false end end
      local status, reason
      if req.invalid then
        status, reason = "thin", "data error: unknown capability key"
      elseif n == 0 then
        status, reason = "missing", "no one in the group can answer this"
      elseif n < req.minProviders then
        status, reason = "thin", string.format("%d of %d wanted", n, req.minProviders)
      elseif n == 1 and req.severity == "critical" and H.CRITICAL_SOLE_PROVIDER_IS_THIN then
        status, reason = "thin", "single point of failure"
      elseif n == 1 and allSoft and H.SOFT_SOLE_PROVIDER_IS_THIN
          and (req.severity == "critical" or req.severity == "high") then
        status, reason = "thin", "only source is conditional/talent/pending"
      else
        status = "covered"
      end
      local unconfirmed = req.confidence ~= "verified"
      if unconfirmed and status == "missing" then
        status = "thin"                       -- unverified data never yields "missing"
        reason = "no provider, but this requirement is unconfirmed"
      end
      out.counts[status] = out.counts[status] + 1
      if req.need == "interrupt" or ns.Util.Contains(req.alt, "interrupt") then interruptReqs = interruptReqs + 1 end
      table.insert(out.items, {
        req = req, category = category, status = status, reason = reason,
        providers = providers, unconfirmed = unconfirmed,   -- labels built on demand (Analysis.Labels)
      })
    end
  end

  -- Aggregate interrupt demand (heuristic thresholds live in DungeonData.lua).
  if cats.interrupts ~= false and not (settings.ignoredNeeds or {}).interrupt and interruptReqs > 0 then
    local wanted = (interruptReqs >= H.KICK_HEAVY_REQUIREMENTS) and H.KICKS_WANTED_KICK_HEAVY or H.KICKS_WANTED_DEFAULT
    local kicks = r.interrupts.short
    out.aggregate = {
      interruptReqs = interruptReqs, kicks = kicks, wanted = wanted,
      text = string.format("%s lists %d interrupt-worthy casts; your comp has %d rotational interrupt%s (heuristic target: %d).",
        d.name, interruptReqs, kicks, kicks == 1 and "" or "s", wanted),
    }
    if kicks < wanted then
      local status = kicks == 0 and "missing" or "thin"
      out.counts[status] = out.counts[status] + 1
      table.insert(out.items, {
        req = { id = "AGG_KICKS", need = "interrupt", severity = "high", minProviders = wanted,
                source = interruptReqs .. " interrupt-worthy casts in this dungeon",
                note = "Tunable heuristic, not a published number.", confidence = "verified" },
        category = "interrupts", status = status,
        reason = string.format("%d of %d rotational interrupts", kicks, wanted),
        providers = {}, unconfirmed = false, aggregate = true,
      })
    end
  end

  table.sort(out.items, function(a, b)
    local sa, sb = STATUS_RANK[a.status], STATUS_RANK[b.status]
    if sa ~= sb then return sa < sb end
    local va, vb = SEV_RANK[a.req.severity] or 9, SEV_RANK[b.req.severity] or 9
    if va ~= vb then return va < vb end
    if a.unconfirmed ~= b.unconfirmed then return not a.unconfirmed end
    return tostring(a.req.id) < tostring(b.req.id)
  end)

  out.unconfirmedCount = 0
  for _, it in ipairs(out.items) do if it.unconfirmed then out.unconfirmedCount = out.unconfirmedCount + 1 end end
  out.incomplete = (out.verified == 0)
  out.mostlyUnverified = out.total > 0 and (out.verified / out.total) < 0.5
  out.gaps = {}
  for _, it in ipairs(out.items) do
    if it.status ~= "covered" then table.insert(out.gaps, it) end
  end
  r.dungeon = out
end

---------------------------------------------------------------------------
-- Summary line
---------------------------------------------------------------------------
-- Dungeon ability names in a requirement's source text -> icon links, colored by the
-- kind of threat the requirement describes.
local function Decorate(text, need, dungeonKey)
  if not ns.Links then return text end
  return ns.Links:Decorate(text, ns.Links.NEED_TYPE[need], dungeonKey)
end
Analysis.Decorate = Decorate

local function GapPhrase(it)
  local label = UD:CapLabel(it.req.need)
  local alt = ""
  if it.req.alt and #it.req.alt > 0 then
    local names = {}
    for _, a in ipairs(it.req.alt) do names[#names + 1] = UD:CapLabel(a) end
    alt = " or " .. table.concat(names, "/")
  end
  local src = it.req.source and (" - " .. Decorate(it.req.source, it.req.need, it.req.dungeon)) or ""
  if it.status == "missing" then
    return "no " .. label .. alt .. src
  end
  return "thin " .. label .. " (" .. (it.reason or "") .. ")" .. src
end

local function BuildSummary(r)
  local parts = {}
  local d = r.dungeon
  if d and not d.unknown then
    if r.filled == 0 then
      parts[#parts + 1] = d.name .. ": add players to check readiness."
    elseif d.incomplete then
      parts[#parts + 1] = d.name .. ": dungeon data is incomplete/unconfirmed - not a clean bill of health."
    elseif #d.gaps > 0 then
      local top = { GapPhrase(d.gaps[1]) }
      if d.gaps[2] and d.gaps[2].status == "missing" and d.gaps[1].status == "missing" then
        top[2] = GapPhrase(d.gaps[2])
      end
      parts[#parts + 1] = d.name .. ": " .. table.concat(top, "; ") .. "."
    else
      local tail = "."
      if d.mostlyUnverified then tail = " (much of the data is unconfirmed)."
      elseif d.unconfirmedCount > 0 then tail = string.format(" (%d unconfirmed entr%s).", d.unconfirmedCount, d.unconfirmedCount == 1 and "y" or "ies") end
      parts[#parts + 1] = d.name .. ": all listed requirements covered" .. tail
    end
  end

  if r.filled == 0 then
    parts[#parts + 1] = "Pick specs to analyze."
  else
    local serious, minor = {}, {}
    for _, f in ipairs(r.findings) do
      if f.severity == "critical" or f.severity == "high" then serious[#serious + 1] = f.short
      elseif f.severity == "medium" then minor[#minor + 1] = f.short end
    end
    local lead
    local all = {}
    for _, x in ipairs(serious) do all[#all + 1] = x end
    for _, x in ipairs(minor) do all[#all + 1] = x end
    local function firstN(list, n)
      local out = {}
      for i = 1, math.min(n, #list) do out[i] = list[i] end
      return out
    end
    if #all == 0 then
      lead = "Strong utility coverage"
    elseif #serious == 0 and #minor <= 2 then
      lead = "Strong utility, but " .. JoinNatural(minor)
    elseif #serious == 0 then
      lead = "Decent core, but " .. JoinNatural(firstN(minor, 2)) .. string.format(" (+%d more)", #minor - 2)
    elseif #serious <= 2 and #minor <= 2 then
      lead = "Solid core, but " .. JoinNatural(serious)
    else
      lead = "Major gaps: " .. JoinNatural(firstN(all, 3))
      if #all > 3 then lead = lead .. string.format(" (+%d more)", #all - 3) end
    end
    if r.filled < ns.NUM_SLOTS then lead = lead .. string.format(" (%d/%d slots filled)", r.filled, ns.NUM_SLOTS) end
    parts[#parts + 1] = lead .. "."
  end
  return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
-- Analyze(members, dungeonKey|nil, settings, opts) -> result table (see fields below)
-- opts.keyLevel (optional): key level for affix requirements (default: your keystone / the
-- Applicants override). opts.affixIDs (optional): use these affixes instead of this week's.
function Analysis:Analyze(members, dungeonKey, settings, opts)
  UD = UD or ns.UD
  settings = settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings
  local resolved = Resolve(members)
  local r = {
    members = resolved, filled = #resolved, caps = {},
    buffs = { present = {} }, synergyPoints = 0,
    interrupts = { count = 0, short = 0, long = 0 },
    brez = { count = 0 }, lust = { present = false }, dispels = {},
    cc = { types = {}, typeCount = 0, stops = 0, aoeStops = 0 },
    findings = {},
  }
  Generic(r, resolved, settings)
  -- Needs the user chose to ignore drop out of the generic check too.
  local ignored = settings.ignoredNeeds
  if ignored and next(ignored) then
    for i = #r.findings, 1, -1 do
      if r.findings[i].cap and ignored[r.findings[i].cap] then table.remove(r.findings, i) end
    end
  end
  table.sort(r.findings, function(a, b)
    local x, y = SEV_RANK[a.severity] or 9, SEV_RANK[b.severity] or 9
    if x ~= y then return x < y end
    return a.text < b.text
  end)
  if dungeonKey and dungeonKey ~= "NONE" then DungeonCheck(r, resolved, dungeonKey, settings, opts) end
  r.summary = BuildSummary(r)
  return r
end

-- Penalty score used to rank suggestions (lower is better). Dungeon gaps are weighted
-- above generic ones so suggestions prefer closing dungeon-critical gaps.
local DUNGEON_MULT = 1.5
-- keyLevel (optional): at or above DD.HEURISTICS.HIGH_KEY_LEVEL, thin dungeon coverage
-- is penalized like a missing one.
function Analysis:Penalty(r, keyLevel)
  local H = ns.Dungeons and ns.Dungeons.HEURISTICS or {}
  local thinMult = (keyLevel and H.HIGH_KEY_LEVEL and keyLevel >= H.HIGH_KEY_LEVEL) and 1.5 or 0.8
  local p = 0
  for _, f in ipairs(r.findings) do
    if f.check ~= "pending" then p = p + (SEV_WEIGHT[f.severity] or 0) end
  end
  if r.dungeon and r.dungeon.items then
    for _, it in ipairs(r.dungeon.items) do
      local w = (SEV_WEIGHT[it.req.severity] or 0) * DUNGEON_MULT
      if it.unconfirmed then w = w * 0.5 end
      if it.status == "missing" then p = p + w * 2
      elseif it.status == "thin" then p = p + w * thinMult end
    end
  end
  -- Raid buff synergy lowers the penalty (it is a bonus, never a gap).
  p = p - (r.synergyPoints or 0)
  return p
end

-- Human-readable buff synergy gained from `base` to `after` (used by suggestions and
-- applicant fit). Returns a list of { text, gain } sorted by gain.
function Analysis:SynergyDelta(base, after)
  local before = {}
  for _, b in ipairs(base.buffs.present) do before[b.key] = b.value or 0 end
  local out = {}
  for _, b in ipairs(after.buffs.present) do
    if not b.universal then
      local gain = (b.value or 0) - (before[b.key] or 0)
      if gain >= 0.5 then
        local who = {}
        for _, n in ipairs(b.full) do who[#who + 1] = n end
        for _, n in ipairs(b.partial) do who[#who + 1] = n .. " (partly)" end
        local verb = before[b.key] and "now also boosts" or "brings it, boosting"
        local link = ns.Links and ns.Links:Buff(b.key) or b.name
        out[#out + 1] = { gain = gain, key = b.key,
          text = link .. ": " .. (before[b.key] and "boosts more of the group" or ("new, boosts " .. #who .. " member" .. (#who == 1 and "" or "s"))),
          long = link .. " (" .. b.effect .. ") " .. verb .. " " .. table.concat(who, ", ") }
      end
    end
  end
  table.sort(out, function(x, y) return x.gain > y.gain end)
  return out
end

local function GapKeys(r)
  local keys = {}
  for _, f in ipairs(r.findings) do
    -- Keyed by stable short phrase, not the full text (which embeds counts).
    if f.check ~= "pending" and f.severity ~= "info" then
      keys["g:" .. f.check .. ":" .. f.short] = f
    end
  end
  if r.dungeon and r.dungeon.items then
    for _, it in ipairs(r.dungeon.items) do
      if it.status ~= "covered" then keys["d:" .. it.req.id .. ":" .. it.status] = it end
    end
  end
  return keys
end

-- Build analysis members from a 5-slot array of spec IDs (0 = empty).
function Analysis:MembersFromSlots(slots)
  local out = {}
  for i = 1, ns.NUM_SLOTS do
    local id = slots[i]
    if type(id) == "number" and id ~= 0 then out[#out + 1] = { specID = id, slot = i } end
  end
  return out
end


---------------------------------------------------------------------------
-- Class suggestions for EMPTY slots only (never swaps), one entry per class per role,
-- never a class that already fills that role. For each open role, every spec
-- of that role is tried in one open slot; specs are grouped by class and classes ranked
-- by their best spec's improvement (gaps closed + raid buff synergy with the players
-- already in). Each class carries the reasons, best first.
-- Returns { { role, open = n, classes = { { classFile, gain, specs = {specID...},
--            reasons = {text...} } } } } in tank / healer / DPS order, plus the base analysis.
---------------------------------------------------------------------------
local SPEC_NEAR_BEST = 0.85   -- other specs listed when within 85% of the class's best gain

-- Everything in `settings` the analysis reads, as a string (for memo keys).
local function SortedPairs(t)
  local out = {}
  for k, v in pairs(type(t) == "table" and t or {}) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
  table.sort(out)
  return table.concat(out, ",")
end
function Analysis:SettingsSig(settings)
  return table.concat({ tostring(settings.countTalentSources), tostring(settings.hideLowSeverity),
    SortedPairs(settings.ignoredNeeds), SortedPairs(settings.checks), SortedPairs(settings.dungeonCategories) }, "|")
end

-- SuggestClasses runs dozens of analyses; the window redraws far more often than the group
-- changes, so the last answer is kept and reused while nothing it depends on has changed.
local suggestMemo = {}
local function SuggestSig(slotMembers, slotRoles, dungeonKey, settings, perRole)
  local t = { tostring(dungeonKey), tostring(perRole), Analysis:SettingsSig(settings) }
  for i = 1, ns.NUM_SLOTS do
    local m = slotMembers[i]
    t[#t + 1] = tostring(slotRoles[i]) .. ":" .. (m and (tostring(m.specID or m.classFile) .. ":" .. tostring(m.role)
      .. ":" .. (m.pending and "p" or "") .. (m.isPlayer and "me" or "")) or "-")
  end
  local AF = ns.Affixes
  if AF then t[#t + 1] = AF:Signature() .. "@" .. tostring(AF:KeyLevel(dungeonKey)) end
  return table.concat(t, ";")
end

function Analysis:SuggestClasses(slotMembers, slotRoles, dungeonKey, settings, perRole)
  UD = UD or ns.UD
  perRole = perRole or 4
  settings = settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings
  local sig = SuggestSig(slotMembers, slotRoles, dungeonKey, settings, perRole)
  if suggestMemo.sig == sig then return suggestMemo.out, suggestMemo.base end
  local out, base = self:SuggestClassesUncached(slotMembers, slotRoles, dungeonKey, settings, perRole)
  suggestMemo = { sig = sig, out = out, base = base }
  return out, base
end

function Analysis:SuggestClassesUncached(slotMembers, slotRoles, dungeonKey, settings, perRole)
  local filled, open, firstOpen = {}, {}, {}
  for i = 1, ns.NUM_SLOTS do
    if slotMembers[i] then filled[#filled + 1] = slotMembers[i]
    else
      local role = slotRoles[i]
      open[role] = (open[role] or 0) + 1
      firstOpen[role] = firstOpen[role] or i
    end
  end
  -- No duplicates within a role: a class already filling that role isn't suggested for
  -- it again (another role is fine: a Holy Paladin healer doesn't rule out a Ret Paladin).
  local taken = {}
  for _, m in ipairs(filled) do
    local p = m.specID and UD:GetSpec(m.specID)
    local cls = (p and p.class) or m.classFile
    local role = (p and p.role) or m.role
    if cls and role then taken[role .. ":" .. cls] = true end
  end
  local base = self:Analyze(filled, dungeonKey, settings)
  local basePenalty = self:Penalty(base)
  local baseGaps = GapKeys(base)
  local out = {}
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    if (open[role] or 0) > 0 then
      local byClass, order = {}, {}
      for _, specID in ipairs(UD:SpecsForRole(role)) do
        local p = UD:GetSpec(specID)
        if not taken[role .. ":" .. p.class] then
        local list = {}
        for _, m in ipairs(filled) do list[#list + 1] = m end
        list[#list + 1] = { specID = specID }
        local r = self:Analyze(list, dungeonKey, settings)
        local gain = basePenalty - self:Penalty(r)
        if gain > 0 then
          -- Reasons: dungeon requirements closed, then generic gaps, then synergy.
          local after = GapKeys(r)
          local dFix, gFix, dLabels, dGroup = {}, {}, {}, {}
          for k, item in pairs(baseGaps) do
            if not after[k] then
              if item.aggregate then
                dFix[#dFix + 1] = { sev = SEV_RANK[item.req.severity] or 9,
                  text = "brings your kick count up to what " .. ((base.dungeon and base.dungeon.name) or "this dungeon") .. " wants" }
              elseif item.req then
                local label = UD:CapLabel(item.req.need)
                dLabels[label] = true
                local verb = item.status == "missing" and "covers " or "backs up "
                local src = Decorate(((item.req.source or ""):match("^([^,(]+)") or ""):gsub("%s+$", ""), item.req.need, item.req.dungeon)
                -- One reason per need and verb, every cast listed ("covers Interrupt for A, B"),
                -- rather than the same words once per cast.
                local mk = verb .. label
                local same = dGroup[mk]
                if same then
                  same.srcs[#same.srcs + 1] = { sev = SEV_RANK[item.req.severity] or 9, src = src }
                  same.sev = math.min(same.sev, SEV_RANK[item.req.severity] or 9)
                else
                  same = { sev = SEV_RANK[item.req.severity] or 9, head = verb .. label .. " for ",
                    srcs = { { sev = SEV_RANK[item.req.severity] or 9, src = src } } }
                  dGroup[mk] = same
                  dFix[#dFix + 1] = same
                end
              else
                local short = item.short or ""
                local what = short:match("^no (.+)$")
                gFix[#gFix + 1] = { sev = SEV_RANK[item.severity] or 9, label = what,
                  text = what and ("adds " .. what) or ("fixes " .. short) }
              end
            end
          end
          -- Drop generic lines the dungeon lines already say ("adds Poison dispel").
          for i = #gFix, 1, -1 do
            if gFix[i].label and dLabels[gFix[i].label] then table.remove(gFix, i) end
          end
          for _, f in ipairs(dFix) do
            if f.srcs then
              table.sort(f.srcs, function(a, b) if a.sev ~= b.sev then return a.sev < b.sev end return a.src < b.src end)
              local names = {}
              for i, x in ipairs(f.srcs) do names[i] = x.src end
              f.text = f.head .. table.concat(names, ", ")
            end
          end
          table.sort(dFix, function(a, b) if a.sev ~= b.sev then return a.sev < b.sev end return a.text < b.text end)
          table.sort(gFix, function(a, b) if a.sev ~= b.sev then return a.sev < b.sev end return a.text < b.text end)
          local reasons = {}
          for _, f in ipairs(dFix) do reasons[#reasons + 1] = f.text end
          for _, f in ipairs(gFix) do reasons[#reasons + 1] = f.text end
          -- Synergy both ways: buffs they bring for your players, and your buffs that suit them.
          for _, d in ipairs(self:SynergyDelta(base, r)) do reasons[#reasons + 1] = d.text end
          for _, b in ipairs(base.buffs.present) do
            if not b.universal then
              local f = UD:BuffBenefit(UD.BUFF_INFO[b.key], p)
              if f and f >= 1 then
                reasons[#reasons + 1] = "benefits from your " .. (ns.Links and ns.Links:Buff(b.key) or b.name)
              end
            end
          end
          if #reasons > 0 then
            local c = byClass[p.class]
            if not c then
              c = { classFile = p.class, gain = gain, best = specID, reasons = reasons, specGains = {} }
              byClass[p.class] = c
              order[#order + 1] = c
            elseif gain > c.gain then
              c.gain, c.best, c.reasons = gain, specID, reasons
            end
            c.specGains[#c.specGains + 1] = { specID = specID, gain = gain }
          end
        end
        end
      end
      for _, c in ipairs(order) do
        table.sort(c.specGains, function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return a.specID < b.specID end)
        c.specs = {}
        for _, sg in ipairs(c.specGains) do
          if sg.gain >= c.gain * SPEC_NEAR_BEST then c.specs[#c.specs + 1] = sg.specID end
        end
        c.specGains = nil
      end
      table.sort(order, function(a, b)
        if math.abs(a.gain - b.gain) > 1e-6 then return a.gain > b.gain end
        return a.classFile < b.classFile
      end)
      local classes = {}
      for i = 1, math.min(perRole, #order) do classes[i] = order[i] end
      out[#out + 1] = { role = role, open = open[role], slot = firstOpen[role], classes = classes, total = #order }
    end
  end
  return out, base
end

---------------------------------------------------------------------------
-- Needs: what the group still lacks, and who could cover it. Rendered under the matching
-- check in the Composition analysis column (UI:RenderNeeds).
---------------------------------------------------------------------------
-- Gaps worth listing: dungeon requirements not fully covered, plus generic gaps of
-- medium severity or worse that a capability fixes. Grouped one entry per capability set.
-- Returns { { keys = {cap...}, status, severity, title, sources = {req...}, findings = {f...} } }
function Analysis:StillNeeded(r)
  UD = UD or ns.UD
  local byKey, out = {}, {}
  local function entry(keys, status, severity)
    local id = table.concat(keys, "+")
    local e = byKey[id]
    if not e then
      e = { keys = keys, status = status, severity = severity, sources = {}, findings = {} }
      byKey[id] = e
      out[#out + 1] = e
    else
      if STATUS_RANK[status] < STATUS_RANK[e.status] then e.status = status end
      if (SEV_RANK[severity] or 9) < (SEV_RANK[e.severity] or 9) then e.severity = severity end
    end
    return e
  end
  if r.dungeon and r.dungeon.items then
    for _, it in ipairs(r.dungeon.items) do
      if it.status ~= "covered" and not it.req.invalid then
        local keys = { it.req.need }
        for _, a in ipairs(it.req.alt or {}) do keys[#keys + 1] = a end
        local e = entry(keys, it.status, it.req.severity)
        if not it.aggregate then table.insert(e.sources, it.req) end
        e.unconfirmed = (e.unconfirmed == nil or e.unconfirmed) and it.unconfirmed
      end
    end
  end
  for _, f in ipairs(r.findings) do
    if f.cap and (f.severity == "critical" or f.severity == "high" or f.severity == "medium") then
      local e = entry({ f.cap }, (f.short:find("^no ") and "missing" or "thin"), f.severity)
      table.insert(e.findings, f)
    end
  end
  for _, e in ipairs(out) do
    local names = {}
    for _, k in ipairs(e.keys) do names[#names + 1] = UD:CapLabel(k) end
    e.title = table.concat(names, " or ")
  end
  table.sort(out, function(a, b)
    local sa, sb = STATUS_RANK[a.status], STATUS_RANK[b.status]
    if sa ~= sb then return sa < sb end
    local va, vb = SEV_RANK[a.severity] or 9, SEV_RANK[b.severity] or 9
    if va ~= vb then return va < vb end
    return a.title < b.title
  end)
  return out
end

-- Which classes/specs could cover any of `keys`, as
-- { { classFile, inRole, abilities = { { name, key, specs = {ids}, allSpecs, talent } } } }.
-- `openRoles` (TANK/HEALER/DAMAGER -> open slot count) puts classes that can fill an open
-- slot first; with no open slots every class is listed as a swap option.
function Analysis:Coverers(keys, openRoles, settings)
  UD = UD or ns.UD
  settings = settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings
  local anyOpen = false
  for _, n in pairs(openRoles or {}) do if n > 0 then anyOpen = true end end
  local out = {}
  for _, classFile in ipairs(UD.classOrder) do
    local cls = UD.classes[classFile]
    local abilities, byName, inRole = {}, {}, false
    for _, specID in ipairs(cls.specs) do
      local p = UD:GetSpec(specID)
      for _, key in ipairs(keys) do
        local src = UD:Sources(p, key, settings)
        for _, e in ipairs(src or {}) do
          local a = byName[e.name]
          if not a then
            a = { name = e.name, key = key, specs = {}, talent = e.talent, verify = e.verify }
            byName[e.name] = a
            abilities[#abilities + 1] = a
          end
          table.insert(a.specs, specID)
          if (not anyOpen) or (openRoles[p.role] or 0) > 0 then inRole = true end
        end
      end
    end
    if #abilities > 0 then
      for _, a in ipairs(abilities) do
        local seen, uniq = {}, {}
        for _, id in ipairs(a.specs) do if not seen[id] then seen[id] = true; uniq[#uniq + 1] = id end end
        a.specs = uniq
        a.allSpecs = (#uniq == #cls.specs)
      end
      out[#out + 1] = { classFile = classFile, inRole = inRole, abilities = abilities }
    end
  end
  table.sort(out, function(a, b)
    if a.inRole ~= b.inRole then return a.inRole end
    return UD:ClassName(a.classFile) < UD:ClassName(b.classFile)
  end)
  return out
end

---------------------------------------------------------------------------
-- Readiness: one row per need, merging the generic check and every dungeon/affix
-- requirement for that need. Status is the worse of the two:
--   missing / thin / ok, or "none" (nobody brings it and nothing here asks for it).
-- Returns {
--   groups = { { key, label, rows = { row }, buffs = bool } },
--   rows = { cap -> row }, counts = { missing, thin, ok, none },
--   chips = { { cap, short, status, text } }, risks = { row }, notes = { finding }, aggregate = item }
-- row = { cap, label, status, severity, providers, items = { dungeon item }, findings = { f },
--         unconfirmed, group }
---------------------------------------------------------------------------
Analysis.READY_GROUPS = {
  { key = "kicks",      label = "Kicks & stops",    caps = { "interrupt", "stop", "aoe_stop", "knockback", "root" } },
  { key = "dispels",    label = "Dispels",          caps = { "dispel_magic", "dispel_curse", "dispel_poison", "dispel_disease", "dispel_bleed", "purge", "soothe" } },
  { key = "survival",   label = "Survival",         caps = { "battle_rez", "external_defensive", "group_defensive" } },
  { key = "throughput", label = "Throughput",       caps = { "bloodlust" }, buffs = true },
  { key = "mobility",   label = "Mobility & skips", caps = { "freedom", "movement", "group_stealth" } },
}
-- Generic check that governs each capability (Settings > Generic checks).
local CAP_CHECK = {
  interrupt = "interrupts", stop = "cc", aoe_stop = "cc", knockback = "cc", root = "cc",
  dispel_magic = "dispels", dispel_curse = "dispels", dispel_poison = "dispels", dispel_disease = "dispels",
  dispel_bleed = "dispels", purge = "dispels", soothe = "dispels",
  battle_rez = "brez", external_defensive = "utility", group_defensive = "utility", bloodlust = "lust",
  freedom = "utility", movement = "utility", group_stealth = "utility",
}
Analysis.CAP_CHECK = CAP_CHECK
local CHIPS = {
  { cap = "bloodlust", short = "Lust" }, { cap = "battle_rez", short = "Brez" }, { cap = "interrupt", short = "Kicks" },
  { cap = "dispel_magic", short = "Magic" }, { cap = "dispel_curse", short = "Curse" }, { cap = "dispel_poison", short = "Poison" },
  { cap = "dispel_disease", short = "Disease" }, { cap = "aoe_stop", short = "AoE stop" }, { cap = "group_defensive", short = "Defensives" },
}
local READY_RANK = { missing = 1, thin = 2, ok = 3, none = 4 }
Analysis.READY_RANK = READY_RANK
local function Worse(a, b)
  if not a then return b end
  if not b then return a end
  return (READY_RANK[a] <= READY_RANK[b]) and a or b
end

function Analysis:Readiness(r, settings)
  UD = UD or ns.UD
  settings = settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings
  local checks = settings.checks or {}
  local itemsBy, aggregate = {}, nil
  if r.dungeon and r.dungeon.items then
    for _, it in ipairs(r.dungeon.items) do
      if it.aggregate then aggregate = it
      else
        local k = it.req.need
        itemsBy[k] = itemsBy[k] or {}
        table.insert(itemsBy[k], it)
      end
    end
  end
  local findBy, notes = {}, {}
  for _, f in ipairs(r.findings) do
    if f.cap then
      findBy[f.cap] = findBy[f.cap] or {}
      table.insert(findBy[f.cap], f)
    else
      notes[#notes + 1] = f
    end
  end

  local ignoredNeeds = settings.ignoredNeeds or {}
  local function BuildRow(cap, groupKey)
    if ignoredNeeds[cap] then return nil end
    local providers = r.caps[cap] or {}
    local items = itemsBy[cap] or {}
    local fs = findBy[cap] or {}
    local checkOn = checks[CAP_CHECK[cap] or ""] ~= false
    if not checkOn and #items == 0 and not (cap == "interrupt" and aggregate) then return nil end
    -- Generic status
    local gen, sev
    for _, f in ipairs(fs) do
      local st
      if f.severity == "critical" or f.severity == "high" or f.severity == "medium" then
        st = (f.short or ""):find("^no ") and "missing" or "thin"
      elseif f.severity == "low" and #providers == 0 then
        st = "none"
      end
      if st and (not gen or READY_RANK[st] < READY_RANK[gen]) then gen, sev = st, f.severity end
    end
    if not gen then gen = (#providers > 0) and "ok" or "none" end
    -- Dungeon status
    local dun, allUnconfirmed = nil, true
    for _, it in ipairs(items) do
      local st = it.status == "covered" and "ok" or it.status
      if st ~= "ok" then
        if not it.unconfirmed then allUnconfirmed = false end
        if not sev or (SEV_RANK[it.req.severity] or 9) < (SEV_RANK[sev] or 9) then sev = it.req.severity end
      end
      dun = Worse(dun, st)
    end
    if cap == "interrupt" and aggregate then
      dun = Worse(dun, aggregate.status == "covered" and "ok" or aggregate.status)
      if aggregate.status ~= "covered" then allUnconfirmed = false end
    end
    local status
    if dun and gen == "none" then status = dun          -- the dungeon decides when nobody brings it
    else status = Worse(gen, dun) end
    if status == "ok" or status == "none" then sev = nil end
    table.sort(items, function(a, b)
      local x, y = READY_RANK[a.status == "covered" and "ok" or a.status], READY_RANK[b.status == "covered" and "ok" or b.status]
      if x ~= y then return x < y end
      local p, q = SEV_RANK[a.req.severity] or 9, SEV_RANK[b.req.severity] or 9
      if p ~= q then return p < q end
      return tostring(a.req.id) < tostring(b.req.id)
    end)
    -- Classes worth listing: the need itself plus the alternatives of any short requirement
    -- (e.g. "soothe or stop": a stun class can also cover it).
    local coverKeys, seenKey = { cap }, { [cap] = true }
    for _, it in ipairs(items) do
      if it.status ~= "covered" then
        for _, a in ipairs(it.req.alt or {}) do
          if not seenKey[a] then seenKey[a] = true; coverKeys[#coverKeys + 1] = a end
        end
      end
    end
    return {
      cap = cap, label = UD:CapLabel(cap), status = status, severity = sev, providers = providers, coverKeys = coverKeys,
      items = items, findings = fs, group = groupKey, checkOn = checkOn,
      -- Only unconfirmed dungeon data makes this a problem (the generic check is fine).
      unconfirmed = ((status == "thin" or status == "missing") and dun ~= nil and dun ~= "ok"
        and gen ~= "missing" and gen ~= "thin" and allUnconfirmed) and true or false,
      aggregate = (cap == "interrupt") and aggregate or nil,
    }
  end

  local out = { groups = {}, rows = {}, counts = { missing = 0, thin = 0, ok = 0, none = 0 }, notes = notes, aggregate = aggregate }
  local placed = {}
  local defs = {}
  for _, g in ipairs(self.READY_GROUPS) do defs[#defs + 1] = g end
  -- Anything a requirement asks for that has no group of its own.
  local extra = {}
  for cap in pairs(itemsBy) do
    local known = false
    for _, g in ipairs(self.READY_GROUPS) do for _, c in ipairs(g.caps) do if c == cap then known = true end end end
    if not known then extra[#extra + 1] = cap end
  end
  table.sort(extra)
  if #extra > 0 then defs[#defs + 1] = { key = "other", label = "Other", caps = extra } end
  for _, g in ipairs(defs) do
    local grp = { key = g.key, label = g.label, rows = {}, buffs = g.buffs and checks.buffs ~= false }
    for _, cap in ipairs(g.caps) do
      local row = not placed[cap] and BuildRow(cap, g.key)
      if row then
        placed[cap] = true
        grp.rows[#grp.rows + 1] = row
        out.rows[cap] = row
        out.counts[row.status] = out.counts[row.status] + 1
      end
    end
    local order = {}
    for i, row in ipairs(grp.rows) do order[row] = i end
    table.sort(grp.rows, function(a, b)
      if READY_RANK[a.status] ~= READY_RANK[b.status] then return READY_RANK[a.status] < READY_RANK[b.status] end
      return order[a] < order[b]
    end)
    if #grp.rows > 0 or grp.buffs then out.groups[#out.groups + 1] = grp end
  end

  -- Summary chips: the key needs always, plus any other problem row.
  out.chips = {}
  local chipped = {}
  for _, c in ipairs(CHIPS) do
    local row = out.rows[c.cap]
    if row then
      chipped[c.cap] = true
      local text = c.short
      if c.cap == "interrupt" then text = "Kicks " .. (r.interrupts and r.interrupts.count or 0) end
      out.chips[#out.chips + 1] = { cap = c.cap, short = text, status = row.status }
    end
  end
  for _, g in ipairs(out.groups) do
    for _, row in ipairs(g.rows) do
      if not chipped[row.cap] and (row.status == "missing" or row.status == "thin") then
        out.chips[#out.chips + 1] = { cap = row.cap, short = row.label, status = row.status }
      end
    end
  end
  -- Biggest risks: worst status, then severity.
  local probs = {}
  for _, row in pairs(out.rows) do if row.status == "missing" or row.status == "thin" then probs[#probs + 1] = row end end
  table.sort(probs, function(a, b)
    if READY_RANK[a.status] ~= READY_RANK[b.status] then return READY_RANK[a.status] < READY_RANK[b.status] end
    local x, y = SEV_RANK[a.severity] or 9, SEV_RANK[b.severity] or 9
    if x ~= y then return x < y end
    return a.label < b.label
  end)
  out.risks = probs
  return out
end

-- "Best key for this group": every Season dungeon ranked by how well `members` cover it,
-- fewest and least severe gaps first. keyLevelFor(key) (optional) gives a known key level.
-- Returns { { key, name, penalty, counts, risks, level } } sorted best first.
function Analysis:RankDungeons(members, settings, keyLevelFor)
  local DD = ns.Dungeons
  settings = settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings
  local out = {}
  for _, key in ipairs(DD.order) do
    local level = keyLevelFor and keyLevelFor(key) or nil
    local r = self:Analyze(members, key, settings, level and { keyLevel = level } or nil)
    local ready = self:Readiness(r, settings)
    out[#out + 1] = { key = key, name = DD.list[key].name, penalty = self:Penalty(r, level),
                      counts = ready.counts, risks = ready.risks, level = level }
  end
  table.sort(out, function(a, b)
    if math.abs(a.penalty - b.penalty) > 0.01 then return a.penalty < b.penalty end
    if a.counts.missing ~= b.counts.missing then return a.counts.missing < b.counts.missing end
    return a.name < b.name
  end)
  return out
end

-- Penalty, itemized: the same numbers as Analysis:Penalty, one entry per gap, so a fit
-- score can be explained ("+30 covers Poison dispel for Cytotoxin").
-- Returns { [id] = { label, points } }, synergyPoints
function Analysis:PenaltyParts(r, keyLevel)
  local H = ns.Dungeons and ns.Dungeons.HEURISTICS or {}
  local thinMult = (keyLevel and H.HIGH_KEY_LEVEL and keyLevel >= H.HIGH_KEY_LEVEL) and 1.5 or 0.8
  local parts = {}
  for _, f in ipairs(r.findings) do
    if f.check ~= "pending" and (SEV_WEIGHT[f.severity] or 0) > 0 then
      local id = "g:" .. f.check .. ":" .. (f.short or f.text)
      local p = parts[id] or { label = f.short or f.text, points = 0, severity = f.severity }
      p.points = p.points + SEV_WEIGHT[f.severity]
      parts[id] = p
    end
  end
  if r.dungeon and r.dungeon.items then
    for _, it in ipairs(r.dungeon.items) do
      if it.status ~= "covered" then
        local w = (SEV_WEIGHT[it.req.severity] or 0) * DUNGEON_MULT
        if it.unconfirmed then w = w * 0.5 end
        w = (it.status == "missing") and w * 2 or w * thinMult
        if w > 0 then
          local name = ((it.req.source or ""):match("^([^,(]+)") or ""):gsub("%s+$", "")
          parts["d:" .. tostring(it.req.id)] = { points = w, severity = it.req.severity, status = it.status,
            label = (it.aggregate and "kick count for this dungeon")
              or (UD:CapLabel(it.req.need) .. " for " .. name) }
        end
      end
    end
  end
  return parts, (r.synergyPoints or 0)
end

-- What changes between two analyses, as scored lines: closed gaps (+), new gaps (-),
-- and raid buff synergy. Returns { { points, text, kind = "fix"|"gap"|"synergy" } }
-- sorted by size.
function Analysis:ScoreDelta(base, after, keyLevel)
  local bp, bs = self:PenaltyParts(base, keyLevel)
  local ap, as = self:PenaltyParts(after, keyLevel)
  local out = {}
  for id, p in pairs(bp) do
    local now = ap[id] and ap[id].points or 0
    local d = p.points - now
    if d > 0.05 then
      -- Dungeon items: "covers" when it was missing, "shores up" when it was only thin.
      local verb
      if id:find("^d:") then verb = (p.status == "thin") and "shores up " or "covers "
      else verb = ap[id] and "eases " or "fixes " end
      local label = p.label
      if not id:find("^d:") then label = label:gsub("^no ", "missing ") end
      out[#out + 1] = { points = d, text = verb .. label, kind = "fix" }
    end
  end
  for id, p in pairs(ap) do
    local was = bp[id] and bp[id].points or 0
    local d = p.points - was
    if d > 0.05 then out[#out + 1] = { points = -d, text = "adds a gap: " .. p.label, kind = "gap" } end
  end
  local syn = as - bs
  if math.abs(syn) > 0.05 then
    out[#out + 1] = { points = syn, text = "raid buff synergy", kind = "synergy" }
  end
  table.sort(out, function(a, b)
    if math.abs(a.points - b.points) > 1e-6 then return math.abs(a.points) > math.abs(b.points) end
    return a.text < b.text
  end)
  return out
end

---------------------------------------------------------------------------
-- Dungeon primer (no group needed): what a dungeon asks for, grouped by need, and which
-- classes answer the most of it on their own.
-- Returns { needs = { { key, label, reqs = {req}, worst, weight } },
--           roles = { TANK/HEALER/DAMAGER -> { { classFile, specID, specs, score, covers = { {key, label, n} } } } } }
---------------------------------------------------------------------------
local PRIMER_W = { critical = 5, high = 3, medium = 2, low = 1 }
function Analysis:DungeonProfile(dungeonKey, settings, level)
  UD = UD or ns.UD
  settings = settings or (ns.db and ns.db.settings) or ns.DEFAULTS.settings
  local DD = ns.Dungeons
  local d = DD and DD.list[dungeonKey]
  if not d then return nil end
  local cats = settings.dungeonCategories or {}
  local ignored = settings.ignoredNeeds or {}
  -- Same filters as Analyze and the walkthrough: categories turned off, needs the player
  -- ignores, and low-severity entries when "hide low" is on.
  local function Shown(q)
    return not q.invalid and not ignored[q.need] and not (settings.hideLowSeverity and q.severity == "low")
  end
  local reqs = {}
  for _, q in ipairs(d.requirements) do
    if Shown(q) and cats[DD:CategoryOf(q)] ~= false then reqs[#reqs + 1] = q end
  end
  if ns.Affixes and cats.affixes ~= false then
    for _, q in ipairs(ns.Affixes:Requirements(dungeonKey, level)) do if Shown(q) then reqs[#reqs + 1] = q end end
  end
  -- By need
  local byNeed, needs = {}, {}
  for _, q in ipairs(reqs) do
    local n = byNeed[q.need]
    if not n then n = { key = q.need, label = UD:CapLabel(q.need), reqs = {}, weight = 0 }; byNeed[q.need] = n; needs[#needs + 1] = n end
    n.reqs[#n.reqs + 1] = q
    n.weight = n.weight + (PRIMER_W[q.severity] or 1)
    if not n.worst or (SEV_RANK[q.severity] or 9) < (SEV_RANK[n.worst] or 9) then n.worst = q.severity end
  end
  for _, n in ipairs(needs) do
    table.sort(n.reqs, function(a, b)
      local x, y = SEV_RANK[a.severity] or 9, SEV_RANK[b.severity] or 9
      if x ~= y then return x < y end
      return tostring(a.id) < tostring(b.id)
    end)
  end
  table.sort(needs, function(a, b)
    local x, y = SEV_RANK[a.worst] or 9, SEV_RANK[b.worst] or 9
    if x ~= y then return x < y end
    if a.weight ~= b.weight then return a.weight > b.weight end
    return a.label < b.label
  end)
  -- Spec value on its own
  local roles = { TANK = {}, HEALER = {}, DAMAGER = {} }
  for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    local byClass, order = {}, {}
    for _, specID in ipairs(UD:SpecsForRole(role)) do
      local p = UD:GetSpec(specID)
      local score, covers, coverBy = 0, {}, {}
      for _, q in ipairs(reqs) do
        local keys = { q.need }
        for _, a in ipairs(q.alt or {}) do keys[#keys + 1] = a end
        local best
        for _, k in ipairs(keys) do
          for _, e in ipairs(UD:Sources(p, k, settings) or {}) do
            if not best or (UD:IsSoft(best.e) and not UD:IsSoft(e)) then best = { e = e, k = k } end
          end
        end
        if best then
          local w = (PRIMER_W[q.severity] or 1) * (UD:IsSoft(best.e) and 0.5 or 1)
          score = score + w
          -- Counted under what they actually bring (Addle Mind "Curse dispel or interrupt"
          -- answered by a Warrior counts as an Interrupt job).
          local c = coverBy[best.k]
          if not c then c = { key = best.k, label = UD:CapLabel(best.k), n = 0, w = 0 }; coverBy[best.k] = c; covers[#covers + 1] = c end
          c.n = c.n + 1; c.w = c.w + w
        end
      end
      table.sort(covers, function(a, b) if a.w ~= b.w then return a.w > b.w end return a.label < b.label end)
      local cl = byClass[p.class]
      if not cl then cl = { classFile = p.class, all = {} }; byClass[p.class] = cl; order[#order + 1] = p.class end
      cl.all[#cl.all + 1] = { specID = specID, score = score, covers = covers }
    end
    for _, cls in ipairs(order) do
      local cl = byClass[cls]
      table.sort(cl.all, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.specID < b.specID end)
      local best = cl.all[1]
      local entry = { classFile = cls, specID = best.specID, score = best.score, covers = best.covers, specs = {} }
      for _, x in ipairs(cl.all) do
        if x.score >= best.score * 0.85 then entry.specs[#entry.specs + 1] = x.specID end
      end
      roles[role][#roles[role] + 1] = entry
    end
    table.sort(roles[role], function(a, b)
      if math.abs(a.score - b.score) > 1e-6 then return a.score > b.score end
      return a.classFile < b.classFile
    end)
  end
  return { needs = needs, roles = roles, total = #reqs }
end

-- Place a live roster into role slots (1 tank / 1 healer / 3 dps), so the same Suggest
-- logic works in Live mode. Members with an unknown role fill whatever is left.
function Analysis:RosterToSlots(members)
  local slots, used = {}, {}
  local function place(role, slotIndex)
    for i, m in ipairs(members) do
      if not used[i] then
        local p = m.specID and ns.UD:GetSpec(m.specID)
        local mrole = (p and p.role) or m.role
        if mrole == role then used[i] = true; slots[slotIndex] = m; return end
      end
    end
  end
  for s = 1, ns.NUM_SLOTS do place(ns.SLOT_ROLES[s], s) end
  for i, m in ipairs(members) do
    if not used[i] then
      for s = 1, ns.NUM_SLOTS do
        if not slots[s] then slots[s] = m; used[i] = true; break end
      end
    end
  end
  return slots
end
