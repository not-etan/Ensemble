-- python3 tests/run_tests.py --data
-- Prints the addon's game data as compact tables for checking against guides and hotfix
-- notes in an update session: every dungeon requirement, every boss card line (long lines
-- and unknown requirement IDs flagged), the affix list, and the spell-ID gaps.
local FILES = {}
for line in io.lines(ADDON_DIR .. "/KeystoneCommand.toc") do
  local f = line:match("^%s*([%w_]+%.lua)%s*$")
  if f then FILES[#FILES + 1] = f end
end
ALLFRAMES = {}
local ns = {}
for _, f in ipairs(FILES) do assert(loadfile(ADDON_DIR .. "/" .. f))("KeystoneCommand", ns) end

local DD, BD, AF = ns.Dungeons, ns.BossData, ns.Affixes
local LONG = 60
local flags = 0

for _, key in ipairs(DD.order) do
  local d = DD.list[key]
  print(string.format("\n## %s (%s) - map %s, instance %s", d.name, key, tostring(DD.CHALLENGE_MAP_IDS[key]),
    tostring(DD.INSTANCE_MAP_IDS[key])))
  print("Bosses: " .. table.concat(d.bosses, ", "))
  print("Requirements:")
  local ids = {}
  for _, q in ipairs(d.requirements) do
    ids[q.id] = true
    local need = q.need .. (q.alt and ("|" .. table.concat(q.alt, "|")) or "")
    print(string.format("  %-22s %-34s %-8s x%d %s  %s", q.id, need, q.severity, q.minProviders,
      q.confidence == "verified" and "  " or "NV", q.source))
  end
  print("Boss cards:")
  for i, card in ipairs(BD.list[key] or {}) do
    local bad = {}
    for _, r in ipairs(card.reqs or {}) do if not ids[r] then bad[#bad + 1] = r end end
    local nameOk = d.bosses[i] == card.name
    print(string.format("  %d. %s%s  reqs: %s%s", i, card.name, nameOk and "" or "  <- NOT the DungeonData boss name",
      table.concat(card.reqs or {}, ", "), #bad > 0 and ("  <- unknown: " .. table.concat(bad, ", ")) or ""))
    if not nameOk or #bad > 0 then flags = flags + 1 end
    for _, l in ipairs(card.lines) do
      local long = #l.text > LONG
      if long then flags = flags + 1 end
      print(string.format("     %-4s %s%s%s", l.role, l.text, l.nv and "  [nv]" or "", long and ("  <- " .. #l.text .. " chars") or ""))
    end
  end
end

print("\n## Affixes")
for _, a in ipairs(AF.DEFS) do
  local reqs = {}
  for _, q in ipairs(a.requirements) do reqs[#reqs + 1] = q.need .. (q.confidence == "verified" and "" or " NV") end
  print(string.format("  %-11s ids %-8s %-8s %s", a.key, table.concat(a.ids, ","), a.bracket, #reqs > 0 and table.concat(reqs, ", ") or "-"))
end

-- Ability names in requirement sources with no spell ID (they show a "?" icon in game).
print("\n## Source abilities without a spell ID")
local any = false
for _, key in ipairs(DD.order) do
  local d = DD.list[key]
  for _, q in ipairs(d.requirements) do
    local first = (q.source:match("^([^,(]+)") or ""):gsub("%s+$", "")
    local known = false
    for _, tbl in ipairs({ DD.SPELL_IDS, d.spellIds or {} }) do
      for name in pairs(tbl) do
        if first == name or first:sub(1, #name + 1) == name .. " " then known = true end
      end
    end
    if first ~= "" and not known then any = true; print(string.format("  %-22s %s", q.id, first)) end
  end
end
if not any then print("  none") end
print(string.format("\n%d flag(s): boss lines over %d characters (a guideline), and boss names or requirement IDs that don't match.", flags, LONG))
