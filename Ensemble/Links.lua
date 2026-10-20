-- Ensemble / Links.lua
-- Ability / buff / item links: an icon in front, the name color-coded by type, and a
-- real game tooltip on hover (shift-click puts the spell link in chat).
--
-- Links are custom hyperlinks:  |Haddon:Ensemble:<side>:<id>:<type>:<name>|h ... |h
--   side = "a" (ally / class ability or buff), "e" (enemy ability in a dungeon), "i" (item)
--   id   = spell or item ID, 0 when unknown (the tooltip then shows name + type only)
-- Any frame that displays them must call Links:Enable(frame) so hover/click are handled.
-- All confirmed present in 12.1.0 (build 69933) by /ens verify: Frame:SetHyperlinksEnabled with the
-- OnHyperlinkEnter/Leave/Click scripts on plain frames, C_Spell.GetSpellTexture,
-- C_Spell.DoesSpellExist, C_Spell.GetSpellLink, GameTooltip:SetSpellByID/SetItemByID.

local _, ns = ...

local Links = {}
ns.Links = Links

local PREFIX = "addon:Ensemble:"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

---------------------------------------------------------------------------
-- Types: color + a word for the tooltip (color is never the only signal).
-- Dispel colors follow Blizzard's debuff-type colors, brightened for a dark UI.
---------------------------------------------------------------------------
Links.TYPES = {
  interrupt = { color = { 0.40, 0.80, 1.00 }, ally = "Interrupt",            enemy = "Interruptible cast" },
  cc        = { color = { 1.00, 0.60, 0.20 }, ally = "Crowd control / stop", enemy = "Channel or cast - stop it with CC" },
  magic     = { color = { 0.30, 0.65, 1.00 }, ally = "Magic dispel",         enemy = "Magic debuff" },
  curse     = { color = { 0.70, 0.35, 1.00 }, ally = "Curse dispel",         enemy = "Curse debuff" },
  poison    = { color = { 0.30, 0.85, 0.30 }, ally = "Poison dispel",        enemy = "Poison debuff" },
  disease   = { color = { 0.85, 0.60, 0.20 }, ally = "Disease dispel",       enemy = "Disease debuff" },
  bleed     = { color = { 0.90, 0.25, 0.25 }, ally = "Bleed cleanse",        enemy = "Bleed" },
  purge     = { color = { 0.55, 0.80, 1.00 }, ally = "Purge (enemy Magic)",  enemy = "Enemy Magic buff - purge it" },
  enrage    = { color = { 1.00, 0.40, 0.20 }, ally = "Soothe (enrage removal)", enemy = "Enrage - soothe it" },
  defensive = { color = { 1.00, 0.82, 0.00 }, ally = "Defensive cooldown",   enemy = "Heavy damage - defensives" },
  tank      = { color = { 0.95, 0.35, 0.35 }, ally = "Tank mitigation",      enemy = "Tank buster" },
  rez       = { color = { 0.60, 1.00, 0.60 }, ally = "Battle resurrection",  enemy = "Resurrection" },
  lust      = { color = { 1.00, 0.45, 0.55 }, ally = "Bloodlust / Heroism",  enemy = "Haste effect" },
  utility   = { color = { 0.78, 0.78, 0.95 }, ally = "Utility",              enemy = "Mechanic" },
  snare     = { color = { 0.30, 0.65, 1.00 }, ally = "Freedom (root/snare removal)", enemy = "Root or snare - a freedom effect removes it" },
  buff      = { color = { 0.45, 0.88, 0.45 }, ally = "Raid buff",            enemy = "Buff" },
  item      = { color = { 1.00, 1.00, 1.00 }, ally = "Item",                 enemy = "Item" },
  boss      = { color = { 1.00, 0.84, 0.50 }, ally = "Boss ability",         enemy = "Boss ability" },
}

-- Capability key -> type (class abilities are colored by what they do).
Links.CAP_TYPE = {
  interrupt = "interrupt", stop = "cc", aoe_stop = "cc", knockback = "cc", root = "cc",
  dispel_magic = "magic", dispel_curse = "curse", dispel_poison = "poison", dispel_disease = "disease",
  dispel_bleed = "bleed", purge = "purge", soothe = "enrage", freedom = "utility",
  battle_rez = "rez", bloodlust = "lust", external_defensive = "defensive", group_defensive = "defensive",
  movement = "utility", group_stealth = "utility",
}
-- Dungeon requirement `need` -> type of the ENEMY ability that creates it.
Links.NEED_TYPE = {
  interrupt = "interrupt", stop = "cc", aoe_stop = "cc", knockback = "cc", root = "cc",
  dispel_magic = "magic", dispel_curse = "curse", dispel_poison = "poison", dispel_disease = "disease",
  dispel_bleed = "bleed", purge = "purge", soothe = "enrage", freedom = "snare",
  battle_rez = "rez", bloodlust = "lust", external_defensive = "tank", group_defensive = "defensive",
  movement = "utility", group_stealth = "utility",
}

local function Hex(c)
  return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
for _, t in pairs(Links.TYPES) do t.hex = Hex(t.color) end

---------------------------------------------------------------------------
-- Spell lookup
---------------------------------------------------------------------------
local exists, icons = {}, {}

function Links:SpellExists(id)
  if not id or id == 0 then return false end
  if exists[id] == nil then
    local ok = false
    if C_Spell and C_Spell.DoesSpellExist then ok = C_Spell.DoesSpellExist(id) and true or false
    elseif C_Spell and C_Spell.GetSpellInfo then ok = C_Spell.GetSpellInfo(id) ~= nil end
    exists[id] = ok
  end
  return exists[id]
end

function Links:SpellIcon(id)
  if not self:SpellExists(id) then return nil end
  if icons[id] == nil then
    local tex
    if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(id)
    elseif GetSpellTexture then tex = GetSpellTexture(id) end
    icons[id] = tex or false
  end
  return icons[id] or nil
end

-- Resolve an ID: the listed ID if the client knows it, otherwise the player's own spell by
-- name (covers class abilities whose ID changed in a patch). nil if neither works.
function Links:Resolve(id, name)
  if id and self:SpellExists(id) then return id end
  if name and C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(info) == "table" and info.spellID then return info.spellID end
  end
  return nil
end

---------------------------------------------------------------------------
-- Building links
---------------------------------------------------------------------------
local function Clean(name) return (tostring(name or "?"):gsub("|", "")) end

function Links:Make(name, id, typeKey, side, lookupName)
  local t = self.TYPES[typeKey] or self.TYPES.utility
  side = side or "a"
  local icon
  if side == "i" then
    icon = (id and C_Item and C_Item.GetItemIconByID) and C_Item.GetItemIconByID(id) or nil
  else
    id = self:Resolve(id, side == "a" and (lookupName or name) or nil)
    icon = id and self:SpellIcon(id)
  end
  name = Clean(name)
  return "|H" .. PREFIX .. side .. ":" .. tostring(id or 0) .. ":" .. (typeKey or "utility") .. ":" .. name .. "|h"
    .. "|T" .. tostring(icon or QUESTION) .. ":13:13:0:0|t " .. t.hex .. name .. "|r|h"
end

-- Class ability by its UtilityDatabase entry name (e.g. "Spell Lock (Felhunter)").
function Links:Ability(name, capKey)
  local id = ns.UD and ns.UD:SpellID(name)
  local lookup = tostring(name):gsub("%s*%(.-%)", ""):gsub("%s*/.*$", "")
  return self:Make(name, id, self.CAP_TYPE[capKey] or "utility", "a", lookup)
end

-- Raid buff by its UD.BUFFS key.
function Links:Buff(key)
  local b = ns.UD and ns.UD.BUFF_INFO[key]
  if not b then return tostring(key) end
  return self:Make(b.name, b.spell, "buff", "a")
end

function Links:Item(itemID, name)
  return self:Make(name or ("item:" .. itemID), itemID, "item", "i")
end

---------------------------------------------------------------------------
-- Decorating free text: dungeon ability names and raid buff names found in a plain
-- string become links. Class ability names are NOT matched in free text (words like
-- "Purge" or "Kick" also appear as plain labels); those are linked where the code
-- knows it is naming an ability. `typeKey` overrides the dungeon ability's type
-- (e.g. the requirement being rendered says it's a Poison debuff).
---------------------------------------------------------------------------
local registry, names

local function BuildRegistry()
  registry, names = {}, {}
  local DD, UD = ns.Dungeons, ns.UD
  if DD and DD.SPELL_IDS then
    for name, id in pairs(DD.SPELL_IDS) do registry[name] = { id = id, side = "e" } end
    -- Default enemy type: from the first requirement whose source mentions the ability.
    for _, key in ipairs(DD.order) do
      for _, req in ipairs(DD.list[key].requirements) do
        for name, entry in pairs(registry) do
          if not entry.type and req.source and req.source:find(name, 1, true) then
            entry.type = Links.NEED_TYPE[req.need] or "utility"
          end
        end
      end
    end
  end
  if UD then
    for _, b in ipairs(UD.BUFFS) do registry[b.name] = { id = b.spell, side = "a", type = "buff" } end
  end
  for name in pairs(registry) do names[#names + 1] = name end
  table.sort(names, function(a, b) return #a > #b end) -- longest first ("Hex Volley" before "Hex")
end

local function IsWordChar(c) return c ~= "" and c:find("[%w']") ~= nil end

-- Names grouped by first character (longest first within each group), so each position
-- in the text is only compared against the names that could start there.
local function Index(list)
  local by = {}
  for _, n in ipairs(list) do
    local c = n:sub(1, 1)
    local g = by[c]
    if not g then g = {}; by[c] = g end
    g[#g + 1] = n
  end
  return by
end

-- `extra` (optional): more names to link for this text, { [name] = { id, type, side } },
-- e.g. a dungeon's boss abilities read from the encounter journal. Names already in the
-- registry keep their registry entry (it knows the ability's type).
local baseIndex
local extraIndex = setmetatable({}, { __mode = "k" })
local function IndexFor(extra)
  if not extra then
    baseIndex = baseIndex or Index(names)
    return baseIndex
  end
  local idx = extraIndex[extra]
  if idx then return idx end
  local list, seen = {}, {}
  for _, n in ipairs(names) do list[#list + 1] = n; seen[n] = true end
  for n in pairs(extra) do if not seen[n] then list[#list + 1] = n end end
  table.sort(list, function(a, b) return #a > #b end)
  idx = Index(list)
  extraIndex[extra] = idx
  return idx
end

-- Decorated text is cached: the same note is drawn on every refresh. Bounded so it can't
-- grow without limit; cleared with the registry.
local memo, memoSize = {}, 0
local MEMO_MAX = 600

function Links:Decorate(text, typeKey, dungeonKey, extra)
  if type(text) ~= "string" or text == "" then return text end
  if not registry then BuildRegistry() end
  local mkey = text .. "\0" .. tostring(typeKey) .. "\0" .. tostring(dungeonKey) .. "\0" .. tostring(extra)
  local hit = memo[mkey]
  if hit then return hit end
  local index = IndexFor(extra)
  local out, i, n = {}, 1, #text
  local plainStart = 1
  local depth = 0   -- text inside (...) is a location/NPC note: never linked
  while i <= n do
    local matched
    local c = text:sub(i, i)
    if c == "(" then depth = depth + 1 elseif c == ")" and depth > 0 then depth = depth - 1 end
    local group = depth == 0 and index[c]
    if group and (i == 1 or not IsWordChar(text:sub(i - 1, i - 1))) then
      for _, name in ipairs(group) do
        local len = #name
        if text:sub(i, i + len - 1) == name and not IsWordChar(text:sub(i + len, i + len)) then
          matched = name; break
        end
      end
    end
    if matched then
      out[#out + 1] = text:sub(plainStart, i - 1)
      local e = registry[matched] or extra[matched]
      local t = (e.side == "e" and typeKey) or e.type or "utility"
      local id = e.id
      local d = dungeonKey and ns.Dungeons and ns.Dungeons.list[dungeonKey]
      if e.side == "e" and d and d.spellIds and d.spellIds[matched] then id = d.spellIds[matched] end
      out[#out + 1] = self:Make(matched, id, t, e.side)
      i = i + #matched
      plainStart = i
    else
      i = i + 1
    end
  end
  out[#out + 1] = text:sub(plainStart)
  local result = table.concat(out)
  if memoSize >= MEMO_MAX then memo, memoSize = {}, 0 end
  memo[mkey], memoSize = result, memoSize + 1
  return result
end

function Links:Reset() registry, names, baseIndex = nil, nil, nil; memo, memoSize = {}, 0 end

---------------------------------------------------------------------------
-- Hover / click handling
---------------------------------------------------------------------------
local function Parse(link)
  local side, id, typeKey, name = link:match("^addon:Ensemble:(%a):(%d+):([%w_]+):(.*)$")
  if not side then return nil end
  return side, tonumber(id), typeKey, name
end

local function OnEnter(frame, link)
  local side, id, typeKey, name = Parse(link or "")
  if not side or not GameTooltip then return end
  GameTooltip:SetOwner(frame, "ANCHOR_CURSOR_RIGHT")
  local shown = false
  if side == "i" and id and id > 0 and GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(id); shown = true
  elseif id and id > 0 and Links:SpellExists(id) and GameTooltip.SetSpellByID then
    GameTooltip:SetSpellByID(id); shown = true
  end
  if not shown then GameTooltip:SetText(name or "?", 1, 1, 1) end
  local t = Links.TYPES[typeKey]
  if t then
    GameTooltip:AddLine("Ensemble: " .. (side == "e" and t.enemy or t.ally), t.color[1], t.color[2], t.color[3])
  end
  if not shown and side ~= "i" then
    GameTooltip:AddLine("No game tooltip for this ability: its spell isn't known to the addon yet.", 0.6, 0.6, 0.6, true)
  end
  GameTooltip:Show()
end

local function OnLeave() if GameTooltip then GameTooltip:Hide() end end

local function OnClick(_, link)
  local side, id = Parse(link or "")
  if not side or not id or id == 0 then return end
  if IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
    local real
    if side == "i" then
      real = select(2, C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id))
    elseif C_Spell and C_Spell.GetSpellLink then
      real = C_Spell.GetSpellLink(id)
    end
    if real then ChatEdit_InsertLink(real) end
  end
end

-- Make a frame's child font strings respond to our links.
function Links:Enable(frame)
  if not frame or frame.cmLinks or not frame.SetHyperlinksEnabled then return end
  frame.cmLinks = true
  frame:SetHyperlinksEnabled(true)
  frame:SetScript("OnHyperlinkEnter", OnEnter)
  frame:SetScript("OnHyperlinkLeave", OnLeave)
  frame:SetScript("OnHyperlinkClick", OnClick)
end
