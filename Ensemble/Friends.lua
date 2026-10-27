-- Ensemble / Friends.lua
-- The friends and guild picker's sources (1.5.1, approved by the author October 27, 2026): your
-- character friends, Battle.net friends on a Retail character in this region, and your guild,
-- as names for the reserve dialog, Saved players and the Composition planner.
--
-- Read-only: nothing here touches Blizzard's frames, and nothing is stored (picking a name never
-- saves it; the dialog's "Save this player" does). Every call is existence-checked and in pcall,
-- every value goes through issecretvalue, and names never reach /ens verify or /ens report
-- (verify counts only). No source gives a spec: the picker narrows the spec menu to the class.
--
-- APIs (Blizzard's generated docs for 12.1.5, build 70575):
--   C_FriendList.GetNumFriends / GetFriendInfoByIndex(i) -> FriendInfo { connected, name,
--     className (localized), area, guid, level, ... }; refresh with C_FriendList.ShowFriends();
--     event FRIENDLIST_UPDATE. The class file comes from GetPlayerInfoByGUID(guid).
--   BNGetNumFriends() -> total, online; C_BattleNet.GetFriendNumGameAccounts(i) and
--     GetFriendGameAccountInfo(i, j) -> BNetGameAccountInfo { characterName, realmName,
--     classFilename, characterLevel, isOnline, clientProgram, wowProjectID, isInCurrentRegion,
--     areaName }. Only the character they're logged into, so offline friends have none.
--   C_Club.GetGuildClubId / GetClubMembers / GetMemberInfo -> ClubMemberInfo { name, classID,
--     level, presence, zone, overallDungeonScore, lastOnlineYear/Month/Day/Hour, isSelf };
--     secret during chat messaging lockdown. Refresh with C_GuildInfo.GuildRoster().
local _, ns = ...

local F = {}
ns.Friends = F

F.SOURCES = { "friend", "bnet", "guild" }
F.LABEL = { saved = "Saved", friend = "Friend", bnet = "Battle.net", guild = "Guild" }
F.reads = {}   -- per source: { ok = bool, why = string?, online = n, listed = n } from the last read

local function Plain(v)
  if v == nil or not issecretvalue then return v end
  local ok, secret = pcall(issecretvalue, v)
  if ok and not secret then return v end
  F.secretReads = (F.secretReads or 0) + 1
  return nil
end

local function Call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function MaxLevel()
  local ok, v = Call(rawget(_G, "GetMaxLevelForPlayerExpansion"))
  v = ok and Plain(v) or nil
  return type(v) == "number" and v > 0 and v or nil
end

-- A class file from a numeric class ID, guarded.
local function ClassFromID(id)
  local CI = rawget(_G, "C_CreatureInfo")
  local ok, info = Call(CI and CI.GetClassInfo, id)
  info = ok and Plain(info) or nil
  return type(info) == "table" and Plain(info.classFile) or nil
end

-- "Name-Realm" the way Saved players writes it (realms without spaces or hyphens; your realm
-- when none is given).
local function Full(name, realm)
  name = Plain(name)
  if type(name) ~= "string" or name == "" then return nil end
  realm = Plain(realm)
  if type(realm) == "string" and realm ~= "" and not name:find("-", 1, true) then name = name .. "-" .. realm end
  return ns.Players and ns.Players:Normalize(name) or name
end

local function Me()
  local ok, n = Call(UnitName, "player")
  return ok and type(Plain(n)) == "string" and Full(n) or nil
end

-- "offline 2 days" from a guild member's last-online fields (time since, as Blizzard's roster).
local function LastOnline(info)
  local y, mo, d, h = Plain(info.lastOnlineYear), Plain(info.lastOnlineMonth), Plain(info.lastOnlineDay), Plain(info.lastOnlineHour)
  local function n(v) return type(v) == "number" and v > 0 and v or nil end
  if n(y) then return "offline " .. y .. " year" .. (y > 1 and "s" or "") end
  if n(mo) then return "offline " .. mo .. " month" .. (mo > 1 and "s" or "") end
  if n(d) then return "offline " .. d .. " day" .. (d > 1 and "s" or "") end
  if n(h) then return "offline " .. h .. " hour" .. (h > 1 and "s" or "") end
  return "offline"
end

local function ReadFriends(out, opts, maxLevel)
  local FL = rawget(_G, "C_FriendList")
  local st = { ok = false, online = 0, listed = 0 }
  F.reads.friend = st
  if not (type(FL) == "table" and FL.GetNumFriends and FL.GetFriendInfoByIndex) then st.why = "api"; return end
  local ok, n = Call(FL.GetNumFriends)
  n = ok and Plain(n) or nil
  if type(n) ~= "number" then st.why = "unreadable"; return end
  st.ok = true
  for i = 1, math.min(n, 200) do
    local okI, info = Call(FL.GetFriendInfoByIndex, i)
    if okI and type(info) == "table" then
      local online = Plain(info.connected) == true
      if online then st.online = st.online + 1 end
      local lvl = Plain(info.level)
      local cls
      local guid = Plain(info.guid)
      if guid then
        local okG, _, eng = Call(rawget(_G, "GetPlayerInfoByGUID"), guid)
        cls = okG and Plain(eng) or nil
      end
      local full = Full(info.name)
      local maxOK = not (online and maxLevel and type(lvl) == "number" and lvl < maxLevel)
      if full and type(cls) == "string" and (online or opts.offline) and maxOK then
        out[#out + 1] = { full = full, classFile = cls, source = "friend", online = online,
          where = online and Plain(info.area) or "offline" }
        st.listed = st.listed + 1
      end
    end
  end
end

local function ReadBattleNet(out, opts, maxLevel)
  local BN = rawget(_G, "C_BattleNet")
  local st = { ok = false, online = 0, listed = 0 }
  F.reads.bnet = st
  local num = rawget(_G, "BNGetNumFriends")
  if not (type(BN) == "table" and BN.GetFriendNumGameAccounts and BN.GetFriendGameAccountInfo and type(num) == "function") then
    st.why = "api"; return
  end
  local ok, total = Call(num)
  total = ok and Plain(total) or nil
  if type(total) ~= "number" then st.why = "unreadable"; return end
  st.ok = true
  local wowClient = rawget(_G, "BNET_CLIENT_WOW") or "WoW"
  local mainline = rawget(_G, "WOW_PROJECT_MAINLINE") or 1
  for i = 1, math.min(total, 200) do
    local okN, games = Call(BN.GetFriendNumGameAccounts, i)
    games = okN and Plain(games) or 0
    for j = 1, (type(games) == "number" and math.min(games, 10) or 0) do
      local okG, g = Call(BN.GetFriendGameAccountInfo, i, j)
      if okG and type(g) == "table" and Plain(g.isOnline) == true and Plain(g.clientProgram) == wowClient
        and (Plain(g.wowProjectID) == nil or Plain(g.wowProjectID) == mainline) and Plain(g.isInCurrentRegion) ~= false then
        st.online = st.online + 1
        local lvl = Plain(g.characterLevel)
        local cls = Plain(g.classFilename)
        local full = Full(g.characterName, g.realmName)
        if full and type(cls) == "string" and not (maxLevel and type(lvl) == "number" and lvl < maxLevel) then
          out[#out + 1] = { full = full, classFile = cls, source = "bnet", online = true, where = Plain(g.areaName) }
          st.listed = st.listed + 1
        end
      end
    end
  end
end

-- Enum.ClubMemberPresence (12.1.5): Unknown 0, Online 1, OnlineMobile 2, Offline 3, Away 4,
-- Busy 5. In game means Online, Away or Busy: OnlineMobile is the Battle.net app (not in game,
-- can't join a key), and Unknown isn't a claim either way, so both count as offline.
local PRESENCE_IN_GAME = { 1, 4, 5 }
local function InGameSet()
  local E = rawget(_G, "Enum") and Enum.ClubMemberPresence
  local set = {}
  if type(E) == "table" and E.Online then
    for _, k in ipairs({ "Online", "Away", "Busy" }) do if E[k] then set[E[k]] = true end end
  else
    for _, v in ipairs(PRESENCE_IN_GAME) do set[v] = true end
  end
  return set
end
F.InGameSet = InGameSet

local function ReadGuild(out, opts, maxLevel)
  local CB = rawget(_G, "C_Club")
  local st = { ok = false, online = 0, listed = 0 }
  F.reads.guild = st
  local okIG, inGuild = Call(rawget(_G, "IsInGuild"))
  if okIG and Plain(inGuild) == false then st.why = "no guild"; return end
  if not (type(CB) == "table" and CB.GetGuildClubId and CB.GetClubMembers and CB.GetMemberInfo) then st.why = "api"; return end
  local ok, club = Call(CB.GetGuildClubId)
  club = ok and Plain(club) or nil
  if club == nil then st.why = okIG and Plain(inGuild) and "unreadable" or "no guild"; return end
  local okM, ids = Call(CB.GetClubMembers, club)
  ids = okM and Plain(ids) or nil
  if type(ids) ~= "table" then st.why = "unreadable"; return end
  st.ok = true
  local inGame = InGameSet()
  for k = 1, math.min(#ids, 1000) do
    local okI, info = Call(CB.GetMemberInfo, club, ids[k])
    info = okI and Plain(info) or nil
    if type(info) == "table" and Plain(info.isSelf) ~= true then
      local presence = Plain(info.presence)
      local online = presence ~= nil and inGame[presence] == true
      if online then st.online = st.online + 1 end
      local lvl = Plain(info.level)
      local cls = ClassFromID(Plain(info.classID))
      local full = Full(info.name)
      local rating = Plain(info.overallDungeonScore)
      if full and type(cls) == "string" and (online or opts.offline) and not (maxLevel and type(lvl) == "number" and lvl < maxLevel) then
        out[#out + 1] = { full = full, classFile = cls, source = "guild", online = online,
          where = online and Plain(info.zone) or LastOnline(info),
          rating = type(rating) == "number" and rating > 0 and math.floor(rating) or nil }
        st.listed = st.listed + 1
      end
    end
  end
end

-- Everyone the picker can list: { full, classFile, source, online, where, rating? }, one entry
-- per person (the first source wins: friend, Battle.net, guild), yourself left out.
-- opts.offline: also offline friends and guild members.
function F:List(opts)
  opts = opts or {}
  local raw = {}
  local maxLevel = MaxLevel()
  pcall(ReadFriends, raw, opts, maxLevel)
  pcall(ReadBattleNet, raw, opts, maxLevel)
  pcall(ReadGuild, raw, opts, maxLevel)
  local out, seen = {}, {}
  local me = Me()
  if me then seen[me:lower()] = true end
  for _, e in ipairs(raw) do
    local k = e.full:lower()
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = e
    elseif e.online then
      -- The same person listed offline by one source and online by another: keep online.
      for _, x in ipairs(out) do if x.full:lower() == k and not x.online then x.online, x.where = true, e.where end end
    end
  end
  return out
end

-- The first source that lists `full` (for a saved player's "Guild - 3010" note), or nil.
function F:Find(full, list)
  if type(full) ~= "string" then return nil end
  local k = full:lower()
  for _, e in ipairs(list or self:List({ offline = true })) do if e.full:lower() == k then return e end end
  return nil
end

-- Names starting with `text`, then containing it (name or realm), not already saved; at most max.
function F:Matches(text, max, list)
  text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
  if text == "" then return {} end
  local starts, contains = {}, {}
  local P = ns.Players
  for _, e in ipairs(list or self:List()) do
    if not (P and P:Find(e.full)) then
      local low = e.full:lower()
      if low:sub(1, #text) == text then starts[#starts + 1] = e
      elseif low:find(text, 1, true) then contains[#contains + 1] = e end
    end
  end
  local out = {}
  for _, t in ipairs({ starts, contains }) do
    for _, e in ipairs(t) do if #out < (max or 6) then out[#out + 1] = e end end
  end
  return out
end

-- Ask the game for fresh lists (friends and the guild roster); the events below redraw.
function F:Request()
  local FL = rawget(_G, "C_FriendList")
  if type(FL) == "table" then Call(FL.ShowFriends) end
  local GI = rawget(_G, "C_GuildInfo")
  if type(GI) == "table" then Call(GI.GuildRoster) end
end

-- The specs of `classFile` (optionally only those of one role).
function F:ClassSpecs(classFile, role)
  local out = {}
  for _, r in ipairs(role and { role } or { "TANK", "HEALER", "DAMAGER" }) do
    for _, id in ipairs(ns.UD:SpecsForRole(r)) do
      local p = ns.UD:GetSpec(id)
      if p and p.class == classFile then out[#out + 1] = id end
    end
  end
  return out
end

local frame = CreateFrame("Frame")
F.frame = frame
for _, ev in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
  "GUILD_ROSTER_UPDATE", "CLUB_MEMBER_PRESENCE_UPDATED" }) do
  pcall(frame.RegisterEvent, frame, ev)
end
frame:SetScript("OnEvent", function() ns:Fire("FRIENDS_CHANGED") end)
