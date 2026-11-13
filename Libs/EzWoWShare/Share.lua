--===========================================================================
-- EzWoW shared : Libs/EzWoWShare/Share.lua
-- Records the players of the EzWoW addons collect in the game, kept by all of
-- them and shared between players (addon messages only; nothing appears in
-- the chat windows).
-- The same file ships in every EzWoW addon. The newest copy runs; the others
-- only hand their saved data to it.
--===========================================================================
-- What is recorded (only what this character saw itself is ever sent):
--   quest  who gives / takes in a quest, where "event" objectives were done,
--          what a quest item drops from (the quest addon adds the last two)
--   rare   where and when a rare monster was seen
--   drops  which creature / object an item was looted from
-- How records travel:
--   * to the party, raid and guild as addon messages;
--   * to the other players in the hidden data channel as addon whispers, one
--     player at a time (addon messages sent to the channel itself do not
--     reach other players on this server, so the channel only tells who
--     else uses EzWoW). Whispers are taken only from players on that list.
-- Received records:
--   * facts by ID (quest NPCs, drops) wait until enough different players
--     sent the same one: one from the party, raid or guild, two from the
--     players of the data channel;
--   * sightings and spots are used as they arrive.
-- Received records are never sent on and never replace this character's own.
-- Senders are kept only as a number (no names are saved).
--
-- Saved data: every EzWoW addon declares the same saved variable
-- (EzWoW_SharedData). Each addon's copy of it is merged in as it loads, so the
-- records stay when some of the addons are turned off.
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall, next = type, pairs, ipairs, tonumber, tostring, pcall, next
local floor, format, concat, max, min = math.floor, string.format, table.concat, math.max, math.min

local LIB_VERSION = 7

-- one table for every copy (a newer copy updates the functions in it)
local lib = _G.EzWoW_Share
if type(lib) ~= "table" then
    lib = {}
    _G.EzWoW_Share = lib
end
ns.Share = lib
lib.hosts = lib.hosts or {}
lib.hosts[ADDON_NAME] = true

-- The loader is made by the first copy that runs; it calls whatever the
-- newest copy put in the table.
if not lib.loader then
    lib.loader = CreateFrame("Frame")
    lib.loader:RegisterEvent("ADDON_LOADED")
    lib.loader:SetScript("OnEvent", function(_, _, name)
        if lib.OnAddonLoaded then pcall(lib.OnAddonLoaded, name) end
    end)
end

if (tonumber(lib.version) or 0) >= LIB_VERSION then return end
lib.version = LIB_VERSION
lib.owner = ADDON_NAME
-- this session's traffic, shown by /ezshare status
lib.stats = lib.stats or { received = 0, players = 0, senders = {}, sent = 0 }
lib.stats.via = lib.stats.via or {}          -- message type -> { players = n, seen = {} }
lib.stats.results = lib.stats.results or {}  -- message type -> last send result

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return (type(time) == "function" and time()) or 0 end
local function clock() return (type(GetTime) == "function" and GetTime()) or 0 end

-----------------------------------------------------------------------------
-- Texts (English, Korean; other languages use English)
-----------------------------------------------------------------------------
local TEXTS = {
    enUS = {
        on = "Data sharing is on.",
        off = "Data sharing is off. Nothing is sent or received.",
        channelOn = "The shared data channel is used.",
        channelOff = "Only the party, raid and guild are used (no channel).",
        help = "/ezshare on | off | channel on | channel off | status | roster | ping [name]",
        status = "Records: quests %d, rare sightings %d, drop sources %d, gathering spots %d.",
        applied = "Of these, received from other players and in use: quests %d, rare sightings %d, drop sources %d, gathering spots %d.",
        traffic = "This session: %d records received from %d players, %d messages sent.",
        lastSend = "Last send: %s (targets %d).",
        via = "Players by way: %s",
        unlisted = "whispers from players not on the list %d",
        results = "Send results: %s",
        roster = "Channel list: %d players to whisper (list %s, channel %s, entry %s, updated %s ago), whispered %d players.",
        rosterNames = "On the list: %s",
        noRoster = "The channel list could not be read (%s).",
        seconds = "%ds",
        unknownFaction = "(faction unknown %d)",
        notFound = "Whispers that found no such player: %d (taken off the list).",
        pingSent = "Delivery check sent to %s. No answer within 10 seconds means it did not arrive.",
        pingFail = "Delivery check to %s could not be sent (%s).",
        pingSelf = "Delivery check: the whisper to yourself came back. Addon whispers are delivered.",
        pong = "Delivery check: %s answered (both have the new version).",
        seen = "Seen %s ago",
        seenShared = "Seen %s ago (shared)",
        droppedBy = "Drops from",
        soldBy = "Sold by",
        andMore = "+%d more",
        manyDrops = "many creatures (%d)",
        manyVendors = "many vendors (%d)",
        object = "object",
        minutes = "%d min",
        hours = "%d h",
        days = "%d d",
    },
    koKR = {
        on = "데이터 공유를 켰습니다.",
        off = "데이터 공유를 껐습니다. 보내지도 받지도 않습니다.",
        channelOn = "공유 데이터 채널을 씁니다.",
        channelOff = "파티·공격대·길드로만 공유합니다(채널 안 씀).",
        help = "/ezshare on | off | channel on | channel off | status | roster | ping [이름]  (/공유)",
        status = "기록: 퀘스트 %d, 희귀 몬스터 목격 %d, 드롭 출처 %d, 채집 위치 %d.",
        applied = "그중 다른 사람에게 받아 쓰고 있는 것: 퀘스트 %d, 희귀 몬스터 목격 %d, 드롭 출처 %d, 채집 위치 %d.",
        traffic = "이번 접속: 받은 기록 %d개 (보낸 사람 %d명), 보낸 메시지 %d개.",
        lastSend = "마지막 보내기: %s (보낼 곳 %d곳).",
        via = "보낸 사람 경로: %s",
        unlisted = "명단 밖 귓속말 %d명",
        results = "보내기 결과: %s",
        roster = "채널 명단: 귓속말 대상 %d명 (명단 %s명, 채널 %s명, 목록 번호 %s, %s 전 갱신), 귓속말 보낸 사람 %d명.",
        rosterNames = "명단: %s",
        noRoster = "채널 명단을 읽지 못했습니다 (%s).",
        seconds = "%d초",
        unknownFaction = "(진영 모름 %d명)",
        notFound = "받는 사람을 찾지 못한 귓속말: %d번 (명단에서 뺌).",
        pingSent = "%s님에게 전달 확인을 보냈습니다. 10초 안에 응답이 없으면 전달되지 않은 것입니다.",
        pingFail = "%s님에게 전달 확인을 보내지 못했습니다 (%s).",
        pingSelf = "전달 확인: 나에게 보낸 귓속말이 돌아왔습니다. 애드온 귓속말이 전달됩니다.",
        pong = "전달 확인: %s님이 응답했습니다 (양쪽 모두 새 버전).",
        seen = "%s 전 목격",
        seenShared = "%s 전 목격 (공유)",
        droppedBy = "드롭",
        soldBy = "판매",
        andMore = "외 %d곳",
        manyDrops = "여러 몬스터 (%d곳)",
        manyVendors = "여러 상인 (%d곳)",
        object = "오브젝트",
        minutes = "%d분",
        hours = "%d시간",
        days = "%d일",
    },
}
local function T(key)
    local loc = (GetLocale and GetLocale()) or "enUS"
    local set = TEXTS[loc] or TEXTS.enUS
    return set[key] or TEXTS.enUS[key] or key
end
lib.Text = T

local function say(text)
    if DEFAULT_CHAT_FRAME and not (InCombatLockdown and InCombatLockdown()) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff4bc8e8EzWoW|r: " .. tostring(text))
    end
end

local function ago(t)
    local age = max(0, now() - (t or 0))
    if age < 3600 then return format(T("minutes"), max(1, floor(age / 60))) end
    if age < 86400 then return format(T("hours"), floor(age / 3600)) end
    return format(T("days"), floor(age / 86400))
end
lib.Ago = ago

-----------------------------------------------------------------------------
-- Saved data
-----------------------------------------------------------------------------
local QUEST_KEYS = { "questEnders", "questGivers", "questEventSpots", "questEventShared",
    "questDropItems", "questDropSources", "questShareInbox" }

local function fresh()
    local d = { v = 1, settings = {}, quest = {}, rare = {}, drops = {}, gather = {}, names = {}, inbox = {}, ext = {} }
    for _, key in ipairs(QUEST_KEYS) do d.quest[key] = {} end
    return d
end

local function shape(d)
    if type(d) ~= "table" then return fresh() end
    for _, key in ipairs({ "settings", "quest", "rare", "drops", "gather", "names", "inbox", "ext" }) do
        if type(d[key]) ~= "table" then d[key] = {} end
    end
    for _, key in ipairs(QUEST_KEYS) do
        if type(d.quest[key]) ~= "table" then d.quest[key] = {} end
    end
    d.v = 1
    return d
end

local function isRecord(t)
    return t.key ~= nil or t.t ~= nil or type(t[1]) == "number"
end

-- union of two saved copies: tables are joined, this character's own records
-- win over shared ones, newer sightings over older, larger counts over smaller
local function merge(dst, src, depth)
    if depth > 8 then return end
    for k, v in pairs(src) do
        local d = dst[k]
        if d == nil then
            dst[k] = v
        elseif type(d) == "number" and type(v) == "number" then
            if v > d then dst[k] = v end
        elseif d == "s" and type(v) == "number" then
            dst[k] = v
        elseif type(d) == "table" and type(v) == "table" then
            if isRecord(d) or isRecord(v) then
                if d.shared and not v.shared then
                    dst[k] = v
                elseif type(d.t) == "number" and type(v.t) == "number" and v.t > d.t and (v.shared or not d.shared) then
                    dst[k] = v
                end
            else
                merge(d, v, depth + 1)
            end
        end
    end
end

function lib.Data()
    if not lib.data then lib.data = fresh() end
    return lib.data
end

-- each EzWoW addon's copy of the saved variable, as that addon loads
function lib.OnAddonLoaded(name)
    if not lib.hosts[name] then return end
    local saved = _G.EzWoW_SharedData
    local data = lib.Data()
    if type(saved) == "table" and saved ~= data then
        merge(data, shape(saved), 0)
    end
    shape(data)
    _G.EzWoW_SharedData = data
end

local function settings() return lib.Data().settings end

function lib.IsEnabled() return settings().off ~= true end
function lib.UsesChannel() return lib.IsEnabled() and settings().noChannel ~= true end
function lib.ShowsTooltips() return settings().noTooltip ~= true end

-- The quest addon keeps reading its own saved table (ns.DB.questEnders ...):
-- those keys are moved here and read through this table.
function lib.AttachQuestDB(db)
    if type(db) ~= "table" then return end
    -- the quest addon's own copy of the shared saved data may not be merged
    -- yet (event order between frames is not fixed)
    local saved = _G.EzWoW_SharedData
    if type(saved) == "table" and saved ~= lib.Data() then
        merge(lib.data, shape(saved), 0)
        _G.EzWoW_SharedData = lib.data
    end
    local q = lib.Data().quest
    for _, key in ipairs(QUEST_KEYS) do
        local own = rawget(db, key)
        if type(own) == "table" and own ~= q[key] then merge(q[key], own, 0) end
        rawset(db, key, nil)
    end
    local redirect = {}
    for _, key in ipairs(QUEST_KEYS) do redirect[key] = true end
    setmetatable(db, {
        __index = function(_, key) if redirect[key] then return q[key] end end,
        __newindex = function(t, key, value)
            if redirect[key] then
                if type(value) == "table" and value ~= q[key] then merge(q[key], value, 0) end
            else
                rawset(t, key, value)
            end
        end,
    })
end

-----------------------------------------------------------------------------
-- Change notices for the addons that show the records
-----------------------------------------------------------------------------
lib.callbacks = lib.callbacks or {}

function lib.RegisterCallback(owner, fn)
    if type(fn) == "function" then lib.callbacks[owner] = fn end
end

local pendingKinds = {}
local function changed(kind)
    pendingKinds[kind] = true
    if lib.reverseDrops then lib.reverseDrops = nil end
    if lib.reverseVendors then lib.reverseVendors = nil end
end

local function flushChanged()
    if not next(pendingKinds) then return end
    local kinds = pendingKinds
    pendingKinds = {}
    for _, fn in pairs(lib.callbacks) do pcall(fn, kinds) end
end

-----------------------------------------------------------------------------
-- Positions and IDs
-----------------------------------------------------------------------------
-- where the player stands: { continent, worldX, worldY } (rounded to 0.1)
local function playerSpot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or type(mapID) ~= "number" or isSecret(mapID) then return nil end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not okPos or not pos then return nil end
    local okWorld, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not okWorld or type(continent) ~= "number" or isSecret(continent) or type(world) ~= "table" then return nil end
    local x, y = world.x, world.y
    if type(x) ~= "number" or type(y) ~= "number" or isSecret(x) or isSecret(y) then return nil end
    return { continent, floor(x * 10 + 0.5) / 10, floor(y * 10 + 0.5) / 10 }
end
lib.PlayerSpot = playerSpot

-- the player's zone map and position on it (0..1)
local function playerMapPos()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or type(mapID) ~= "number" or isSecret(mapID) then return nil end
    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not okPos or not pos then return nil end
    local okXY, x, y = pcall(pos.GetXY, pos)
    if not okXY or type(x) ~= "number" or type(y) ~= "number" or isSecret(x) or isSecret(y) then return nil end
    return mapID, floor(x * 1000 + 0.5) / 1000, floor(y * 1000 + 0.5) / 1000
end

-- "n123" / "o123" for a creature / game object GUID
local function guidSource(guid)
    if type(guid) ~= "string" or isSecret(guid) then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    if unitType == "Creature" or unitType == "Vehicle" then return "n" .. id, id end
    if unitType == "GameObject" then return "o" .. id, id end
    return nil
end

local function questPartnerKey()
    for _, unit in ipairs({ "questnpc", "npc" }) do
        local ok, guid = pcall(UnitGUID, unit)
        local src, id
        if ok then src, id = guidSource(guid) end
        if src then return (src:sub(1, 1) == "n" and "npc:" or "object:") .. id end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Recording: quest givers and turn-ins (the quest addon records more)
-----------------------------------------------------------------------------
local pendingTurnIn

local function onQuestDetail()
    local questID = type(GetQuestID) == "function" and tonumber(GetQuestID()) or nil
    if not questID or isSecret(questID) or questID <= 0 then return end
    local key = questPartnerKey()
    if not key then return end
    local givers = lib.Data().quest.questGivers
    local current = givers[questID]
    if type(current) == "table" and not current.shared and current.key == key then return end
    givers[questID] = { key = key, spot = playerSpot() }
end

local function onQuestComplete()
    local questID = type(GetQuestID) == "function" and tonumber(GetQuestID()) or nil
    if not questID or isSecret(questID) or questID <= 0 then pendingTurnIn = nil return end
    local key = questPartnerKey()
    if not key then pendingTurnIn = nil return end
    pendingTurnIn = { questID = questID, key = key, spot = playerSpot() }
end

local function onQuestTurnedIn(questID)
    questID = tonumber(questID)
    local pending = pendingTurnIn
    pendingTurnIn = nil
    if not questID or isSecret(questID) or not pending or pending.questID ~= questID then return end
    lib.Data().quest.questEnders[questID] = { key = pending.key, spot = pending.spot }
end

-----------------------------------------------------------------------------
-- Recording: rare monsters seen (nameplates, target, mouseover)
-----------------------------------------------------------------------------
local RARE_CLASSES = { rare = true, rareelite = true }
local RARE_AGAIN = 60            -- seconds before the same rare is noted again

local function noteName(id, unit)
    local ok, name = pcall(UnitName, unit)
    if ok and type(name) == "string" and not isSecret(name) and name ~= "" then
        lib.Data().names["n" .. id] = name
    end
end

local function checkUnit(unit)
    if not unit or not lib.IsEnabled() then return end
    local okE, exists = pcall(UnitExists, unit)
    if not okE or not exists or isSecret(exists) then return end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or isSecret(isPlayer) or isPlayer then return end
    local okG, guid = pcall(UnitGUID, unit)
    local src, id
    if okG then src, id = guidSource(guid) end
    if not src or src:sub(1, 1) ~= "n" then return end
    local okC, class = pcall(UnitClassification, unit)
    if not okC or isSecret(class) or not RARE_CLASSES[class] then return end
    if IsInInstance then
        local okI, inside = pcall(IsInInstance)
        if okI and inside and not isSecret(inside) then return end
    end
    noteName(id, unit)
    local rare = lib.Data().rare
    local current = rare[id]
    local t = now()
    if type(current) == "table" and not current.shared and t - (current.t or 0) < RARE_AGAIN then return end
    local mapID, x, y = playerMapPos()
    if not mapID then return end
    rare[id] = { m = mapID, x = x, y = y, t = t }
    changed("rare")
end

-----------------------------------------------------------------------------
-- Recording: item drops (loot window) and where objects were looted
-----------------------------------------------------------------------------
local lootSeen = {}   -- "guid:itemID" -> true (this session; a loot window can open twice)
local GATHER_SAME = 3          -- yards: closer than this is the same spot
local GATHER_MAX = 30          -- spots kept per object

local function nearSpot(list, spot)
    for _, s in ipairs(list) do
        if s[1] == spot[1] then
            local dx, dy = s[2] - spot[2], s[3] - spot[3]
            if dx * dx + dy * dy <= GATHER_SAME * GATHER_SAME then return s end
        end
    end
    return nil
end

-- gather[objectID] = { { continent, x, y [, shared = true] }, ... }
local function addGatherSpot(objectID, spot, shared)
    local gather = lib.Data().gather
    local list = gather[objectID]
    if not list then
        list = {}
        gather[objectID] = list
    end
    local near = nearSpot(list, spot)
    if near then
        if not shared and near.shared then near.shared = nil end
        return false
    end
    if #list >= GATHER_MAX then return false end
    if shared then spot.shared = true end
    list[#list + 1] = spot
    return true
end

local function itemIDOf(link)
    if type(link) ~= "string" or isSecret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function onLootOpened()
    if not lib.IsEnabled() then return end
    if IsFishingLoot and IsFishingLoot() then return end
    -- inside a dungeon: which one (positions are not known there)
    local instanceMap
    if IsInInstance and IsInInstance() and GetInstanceInfo then
        local okInfo, _, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
        if okInfo and type(mapID) == "number" and not isSecret(mapID) and mapID > 0 then instanceMap = mapID end
    end
    local count = GetNumLootItems and GetNumLootItems() or 0
    if isSecret(count) then return end
    local drops = lib.Data().drops
    local any = false
    local spot
    for slot = 1, count do
        local okLink, link = pcall(GetLootSlotLink, slot)
        local itemID = okLink and itemIDOf(link)
        if itemID and GetLootSourceInfo then
            local sources = { pcall(GetLootSourceInfo, slot) }
            if sources[1] then
                for i = 2, #sources, 2 do
                    local guid = sources[i]
                    local src, sourceID = guidSource(guid)
                    if src and src:sub(1, 1) == "o" then
                        -- an object (herb, vein, chest...): where it stood
                        spot = spot or playerSpot()
                        if spot and addGatherSpot(sourceID, { spot[1], spot[2], spot[3] }) then
                            changed("gather")
                        end
                    end
                    if src and instanceMap and src:sub(1, 1) == "n" and lib.NoteInstance then
                        lib.NoteInstance(sourceID, instanceMap)
                    end
                    if src then
                        local key = guid .. ":" .. itemID
                        if not lootSeen[key] then
                            lootSeen[key] = true
                            drops[src] = drops[src] or {}
                            local n = drops[src][itemID]
                            drops[src][itemID] = (type(n) == "number" and n or 0) + 1
                            any = true
                        end
                    end
                end
            end
        end
    end
    if any then changed("drops") end
end

-----------------------------------------------------------------------------
-- Reading (for the addons that show records)
-----------------------------------------------------------------------------
-- Records shipped with the addons (EzWoW-MapFinder Database/ShareSeed.lua):
-- what EzWoW players found and shared before, for players who have not
-- received it themselves. kind: "drops", "gather", "offers"
function lib.Seed(kind)
    local seed = _G.EzWoW_ShareSeed
    local t = type(seed) == "table" and seed[kind]
    return type(t) == "table" and t or nil
end

-- rare monster sighting: { m = mapID, x, y, t = time, shared = true|nil } or nil
function lib.GetRare(npcID)
    local r = lib.Data().rare[tonumber(npcID) or 0]
    return type(r) == "table" and r or nil
end

-- sources an item was looted from: { { src = "n123", own = count|nil }, ... }
function lib.GetDropSources(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if not lib.reverseDrops then
        local rev = {}
        for src, items in pairs(lib.Data().drops) do
            if type(items) == "table" then
                for id, v in pairs(items) do
                    if type(id) == "number" then
                        rev[id] = rev[id] or {}
                        rev[id][#rev[id] + 1] = { src = src, own = type(v) == "number" and v or nil }
                    end
                end
            end
        end
        -- shipped records the player does not have yet
        local mine = lib.Data().drops
        for src, items in pairs(lib.Seed("drops") or {}) do
            if type(src) == "string" and type(items) == "table" then
                local have = type(mine[src]) == "table" and mine[src] or nil
                for _, id in ipairs(items) do
                    if type(id) == "number" and not (have and have[id]) then
                        rev[id] = rev[id] or {}
                        rev[id][#rev[id] + 1] = { src = src }
                    end
                end
            end
        end
        lib.reverseDrops = rev
    end
    return lib.reverseDrops[itemID]
end

-- Name lookups other addons add: function(kind, id) -> name or nil, where kind
-- is "npc" or "object" (an addon's name tables in the player's language).
lib.nameResolvers = lib.nameResolvers or {}

function lib.SourceName(src)
    if type(src) ~= "string" then return nil end
    local name = lib.Data().names[src]
    if name then return name end
    local id = tonumber(src:sub(2))
    if not id then return nil end
    local kind = src:sub(1, 1) == "n" and "npc" or "object"
    local api = _G.EzWoWMapFinderAPI
    if api and type(api.NameByID) == "function" then
        local ok, n = pcall(api.NameByID, kind, id)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    for _, resolve in ipairs(lib.nameResolvers) do
        if type(resolve) == "function" then
            local ok, n = pcall(resolve, kind, id)
            if ok and type(n) == "string" and n ~= "" and not isSecret(n) then return n end
        end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Messages: encoding
-----------------------------------------------------------------------------
local PREFIX = "EzWoWQData"           -- at most 16 characters (the quest addon's, kept)
local CHANNEL_NAME = "EzWoWQuestData"
local MAX_MSG = 240                   -- addon messages are limited to 255 bytes
local SEND_EVERY = 8                  -- seconds between outgoing messages
local RESEND_AFTER = 20 * 60          -- everything is sent again after this long
local CONFIRM_GROUP, CONFIRM_PUBLIC = 1, 2
local INBOX_DAYS = 14
local INBOX_MAX = 6000
local RECEIVE_PER_MINUTE = 400        -- records accepted from one sender
local RARE_SEND_AGE = 2 * 3600        -- own sightings younger than this are sent
local RARE_KEEP_AGE = 6 * 3600        -- received sightings older than this are not kept

local function num(v)
    local text = format("%.1f", v):gsub("%.0$", "")
    return text
end

local function spotText(spot)
    if type(spot) ~= "table" or type(spot[1]) ~= "number" or type(spot[2]) ~= "number" or type(spot[3]) ~= "number" then
        return nil
    end
    return spot[1] .. "," .. num(spot[2]) .. "," .. num(spot[3])
end

local function intIn(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= floor(v) or v < lo or v > hi then return nil end
    return v
end

local function numIn(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v < lo or v > hi then return nil end
    return v
end

local function parseSpot(text)
    if type(text) ~= "string" then return nil end
    local c, x, y = text:match("^(%d+),(%-?[%d%.]+),(%-?[%d%.]+)$")
    c, x, y = intIn(c, 0, 100000), numIn(x, -100000, 100000), numIn(y, -100000, 100000)
    if not (c and x and y) then return nil end
    return { c, x, y }
end

-- item name keys are kept as the quest objective pins normalize them
local function cleanName(text)
    if type(text) ~= "string" or text == "" or #text > 90 or isSecret(text) then return nil end
    -- control characters by byte range: "%c" can match bytes of Hangul / CJK letters
    if text:find("[\1-\31\127|;]") or text:find("\0", 1, true) then return nil end
    if text ~= text:lower() then return nil end
    return text
end

local function locale()
    local loc = (GetLocale and GetLocale()) or "enUS"
    if loc == "esMX" then loc = "esES" elseif loc == "enGB" then loc = "enUS" end
    return loc
end

-- This character's own records, as message parts: { kind, body, version }
-- (body has no ";"). Version 1 kinds are the quest records older copies of
-- the quest addon read too.
local function ownRecords()
    local list = {}
    local d = lib.Data()
    local q = d.quest
    for code, storeName in pairs({ E = "questEnders", S = "questGivers" }) do
        for questID, rec in pairs(q[storeName]) do
            if type(questID) == "number" and type(rec) == "table" and not rec.shared and type(rec.key) == "string" then
                local kind, id = rec.key:match("^(%a)%a*:(%d+)$")
                if kind == "n" or kind == "o" then
                    list[#list + 1] = { code, questID .. "," .. kind .. "," .. id .. (spotText(rec.spot) and ("," .. spotText(rec.spot)) or ""), 1 }
                end
            end
        end
    end
    for questID, spots in pairs(q.questEventSpots) do
        if type(questID) == "number" and type(spots) == "table" then
            for index, spot in pairs(spots) do
                local text = type(index) == "number" and type(spot) == "table" and not spot.shared and spotText(spot)
                if text then list[#list + 1] = { "V", questID .. "," .. index .. "," .. text, 1 } end
            end
        end
    end
    for itemID, ids in pairs(q.questDropItems) do
        if type(itemID) == "number" and type(ids) == "table" then
            for id, value in pairs(ids) do
                if type(id) == "number" and value == true then
                    list[#list + 1] = { "I", itemID .. ",n," .. id, 1 }
                elseif type(id) == "string" and type(value) == "table" and not value.shared then
                    local objectID = tonumber(id:match("^o:(%d+)$"))
                    local text = objectID and spotText(value)
                    if text then list[#list + 1] = { "I", itemID .. ",o," .. objectID .. "," .. text, 1 } end
                end
            end
        end
    end
    for key, ids in pairs(q.questDropSources) do
        local name = cleanName(key)
        if name and type(ids) == "table" then
            for id, value in pairs(ids) do
                if type(id) == "number" and value == true then
                    list[#list + 1] = { "D", id .. "," .. name, 1 }
                elseif type(id) == "string" and type(value) == "table" and not value.shared then
                    local objectID = tonumber(id:match("^o:(%d+)$"))
                    local text = objectID and spotText(value)
                    if text then list[#list + 1] = { "O", objectID .. "," .. text .. "," .. name, 1 } end
                end
            end
        end
    end
    -- R: rare sighting "npcID,mapID,x,y,age"
    local t = now()
    for npcID, r in pairs(d.rare) do
        if type(npcID) == "number" and type(r) == "table" and not r.shared and type(r.t) == "number"
            and t - r.t < RARE_SEND_AGE and type(r.m) == "number" then
            list[#list + 1] = { "R", format("%d,%d,%s,%s,%d", npcID, r.m, tostring(r.x), tostring(r.y), max(0, t - r.t)), 2, r.t }
        end
    end
    -- L: drop "n123,itemID" / "o123,itemID"
    for src, items in pairs(d.drops) do
        if type(src) == "string" and type(items) == "table" then
            for itemID, v in pairs(items) do
                if type(itemID) == "number" and type(v) == "number" then
                    list[#list + 1] = { "L", src .. "," .. itemID, 2 }
                end
            end
        end
    end
    -- G: where an object was looted "objectID,continent,x,y"
    for objectID, spots in pairs(d.gather) do
        if type(objectID) == "number" and type(spots) == "table" then
            for _, s in ipairs(spots) do
                local text = not s.shared and spotText(s)
                if text then list[#list + 1] = { "G", objectID .. "," .. text, 2 } end
            end
        end
    end
    -- kinds other EzWoW addons registered (fishing spots, flight times...)
    for code, spec in pairs(lib.kinds) do
        if type(spec.own) == "function" then
            local ok, bodies = pcall(spec.own)
            if ok and type(bodies) == "table" then
                for _, body in ipairs(bodies) do
                    if type(body) == "string" and body ~= "" and not body:find("[;|]") and #body < 200 then
                        list[#list + 1] = { code, body, 2 }
                    end
                end
            end
        end
    end
    return list
end

-----------------------------------------------------------------------------
-- Messages: receiving (votes)
-----------------------------------------------------------------------------
local SAME_SPOT = 3             -- yards: closer than this is the same spot
local MAX_EVENT_SPOTS = 20      -- spots kept per scouting objective
local MAX_SENDERS = 20          -- senders remembered per value
local MAX_OBJECT_SPOTS = 20

local function sameSpot(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or a[1] ~= b[1] then return false end
    local dx, dy = a[2] - b[2], a[3] - b[3]
    return dx * dx + dy * dy <= SAME_SPOT * SAME_SPOT
end

-- a number for the sender, so the same player is counted once
local function senderHash(sender)
    local h = 5381
    for i = 1, #sender do h = (h * 33 + sender:byte(i)) % 2147483647 end
    return h
end

local received = {}   -- sender hash -> { t, n } (this session)

local function allow(hash, n)
    local t = GetTime and GetTime() or 0
    local row = received[hash]
    if not row or t - row.t > 60 then
        row = { t = t, n = 0 }
        received[hash] = row
    end
    row.n = row.n + n
    return row.n <= RECEIVE_PER_MINUTE
end

-- inbox rows: key -> { t = last report, v = { [value] = { s, n, p } } }
-- quest facts keep the quest addon's inbox ("v2:" keys); other kinds use "v1:"
local inboxCount = {}

local function inboxOf(which)
    local d = lib.Data()
    local box = which == "quest" and d.quest.questShareInbox or d.inbox
    local tag = which == "quest" and "v2:" or "v1:"
    if not inboxCount[which] then
        local n = 0
        local oldest = now() - INBOX_DAYS * 86400
        for key, row in pairs(box) do
            if type(key) ~= "string" or key:sub(1, #tag) ~= tag or type(row) ~= "table" or (row.t or 0) < oldest then
                box[key] = nil
            else
                n = n + 1
            end
        end
        inboxCount[which] = n
    end
    return box, tag
end

local function voteValue(which, key, value, hash, spot)
    local box, tag = inboxOf(which)
    key = tag .. key
    local row = box[key]
    if not row then
        if inboxCount[which] >= INBOX_MAX then return nil end
        row = {}
        box[key] = row
        inboxCount[which] = inboxCount[which] + 1
    end
    row.t = now()
    row.v = row.v or {}
    local entry = row.v[value]
    if not entry then
        entry = { s = {}, n = 0 }
        row.v[value] = entry
    end
    if entry.s[hash] or entry.n >= MAX_SENDERS then return nil end
    entry.s[hash] = true
    entry.n = entry.n + 1
    if spot and not entry.p then entry.p = spot end
    return entry
end

-- E / S: who takes a quest in / gives it out "questID,n|o,ID[,continent,x,y]"
local function receiveQuestNpc(code, storeName, body, hash, needed)
    local q, k, id, rest = body:match("^(%d+),([no]),(%d+),?(.*)$")
    q, id = intIn(q, 1, 1000000), intIn(id, 1, 10000000)
    if not (q and id) then return end
    local value = (k == "n" and "npc:" or "object:") .. id
    local entry = voteValue("quest", code .. ":" .. q, value, hash, parseSpot(rest))
    if not entry or entry.n < needed then return end
    local store = lib.Data().quest[storeName]
    local current = store[q]
    if type(current) == "table" and not current.shared then return end
    if type(current) == "table" and current.key == value then
        current.n = entry.n
        return
    end
    -- a different value replaces a confirmed one only when more players report it
    if type(current) == "table" and entry.n <= (current.n or 0) then return end
    store[q] = { key = value, spot = entry.p, shared = true, n = entry.n }
    changed("quest")
end

-- V: scouting spot "questID,objective,continent,x,y" (used as it arrives)
local function receiveEventSpot(body)
    local q, index, rest = body:match("^(%d+),(%d+),(.+)$")
    q, index = intIn(q, 1, 1000000), intIn(index, 1, 20)
    local spot = parseSpot(rest)
    if not (q and index and spot) then return end
    local shared = lib.Data().quest.questEventShared
    shared[q] = shared[q] or {}
    local list = shared[q][index] or {}
    shared[q][index] = list
    for _, s in ipairs(list) do
        if sameSpot(s, spot) then return end
    end
    if #list >= MAX_EVENT_SPOTS then return end
    list[#list + 1] = spot
    changed("quest")
end

-- a creature that drops a quest item: store[key][npcID] = "s"
local function receiveDropFact(storeName, key, npcID, hash, needed, voteKey)
    local entry = voteValue("quest", voteKey, "1", hash)
    if not entry or entry.n < needed then return end
    local tbl = lib.Data().quest[storeName]
    tbl[key] = tbl[key] or {}
    if tbl[key][npcID] then return end
    tbl[key][npcID] = "s"
    changed("quest")
end

-- an object a quest item is looted from: store[key]["o:ID"] = spot (+ .more)
local function receiveDropSpot(storeName, key, objectID, spot)
    local tbl = lib.Data().quest[storeName]
    tbl[key] = tbl[key] or {}
    local slot = "o:" .. objectID
    local current = tbl[key][slot]
    if type(current) ~= "table" then
        spot.shared = true
        tbl[key][slot] = spot
        changed("quest")
        return
    end
    if sameSpot(current, spot) then return end
    current.more = current.more or {}
    for _, s in ipairs(current.more) do
        if sameSpot(s, spot) then return end
    end
    if #current.more >= MAX_OBJECT_SPOTS then return end
    current.more[#current.more + 1] = spot
    changed("quest")
end

-- R: "npcID,mapID,x,y,age" (used as it arrives; the newest sighting is kept)
local function receiveRare(body)
    local npc, map, x, y, age = body:match("^(%d+),(%d+),([%d%.]+),([%d%.]+),(%d+)$")
    npc, map = intIn(npc, 1, 10000000), intIn(map, 1, 100000)
    x, y, age = numIn(x, 0, 1), numIn(y, 0, 1), intIn(age, 0, RARE_KEEP_AGE)
    if not (npc and map and x and y and age) then return end
    local t = now() - age
    local rare = lib.Data().rare
    local current = rare[npc]
    if type(current) == "table" and (current.t or 0) >= t - 5 then return end
    rare[npc] = { m = map, x = x, y = y, t = t, shared = true }
    lib.newRares = lib.newRares or {}
    lib.newRares[#lib.newRares + 1] = npc
    changed("rare")
end

-- rares received since the last call (for alerts): { npcID, ... }
function lib.TakeNewRares()
    local list = lib.newRares or {}
    lib.newRares = nil
    return list
end

-- L: "n123,itemID" / "o123,itemID" (counted like the quest facts)
local function receiveDrop(body, hash, needed)
    local src, itemID = body:match("^([no]%d+),(%d+)$")
    itemID = intIn(itemID, 1, 10000000)
    if not (src and itemID and intIn(src:sub(2), 1, 10000000)) then return end
    local entry = voteValue("other", "L:" .. src .. ":" .. itemID, "1", hash)
    if not entry or entry.n < needed then return end
    local drops = lib.Data().drops
    drops[src] = drops[src] or {}
    if drops[src][itemID] then return end
    drops[src][itemID] = "s"
    changed("drops")
end

-- G: "objectID,continent,x,y" (used as it arrives)
local function receiveGather(body)
    local id, rest = body:match("^(%d+),(.+)$")
    id = intIn(id, 1, 10000000)
    local spot = parseSpot(rest)
    if id and spot and addGatherSpot(id, spot, true) then changed("gather") end
end

local function receive(kind, body, hash, needed)
    if kind == "G" then
        receiveGather(body)
        return
    end
    local spec = lib.kinds[kind]
    if spec then
        if type(spec.receive) == "function" then
            local ok, any = pcall(spec.receive, body, hash, needed)
            if ok and any then changed(kind) end
        end
        return
    end
    if kind == "E" then
        receiveQuestNpc("E", "questEnders", body, hash, needed)
    elseif kind == "S" then
        receiveQuestNpc("S", "questGivers", body, hash, needed)
    elseif kind == "V" then
        receiveEventSpot(body)
    elseif kind == "I" then
        local itemID, k, id, rest = body:match("^(%d+),([no]),(%d+),?(.*)$")
        itemID, id = intIn(itemID, 1, 10000000), intIn(id, 1, 10000000)
        if not (itemID and id) then return end
        if k == "n" then
            receiveDropFact("questDropItems", itemID, id, hash, needed, "I:" .. itemID .. ":n:" .. id)
        else
            local spot = parseSpot(rest)
            if spot then receiveDropSpot("questDropItems", itemID, id, spot) end
        end
    elseif kind == "D" then
        local id, name = body:match("^(%d+),(.+)$")
        id, name = intIn(id, 1, 10000000), cleanName(name)
        if id and name then receiveDropFact("questDropSources", name, id, hash, needed, "D:" .. name .. ":" .. id) end
    elseif kind == "O" then
        local id, c, x, y, name = body:match("^(%d+),(%d+),(%-?[%d%.]+),(%-?[%d%.]+),(.+)$")
        id, name = intIn(id, 1, 10000000), cleanName(name)
        local spot = parseSpot(c and (c .. "," .. x .. "," .. y))
        if id and name and spot then receiveDropSpot("questDropSources", name, id, spot) end
    elseif kind == "R" then
        receiveRare(body)
    elseif kind == "L" then
        receiveDrop(body, hash, needed)
    end
end

local playerFull

-- the sender may come as "name-realm", "name" or "name surname"
local playerWithSurname
local function isMe(sender)
    if not playerFull then
        local name, second = nil, nil
        if UnitName then name, second = UnitName("player") end
        local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
        playerFull = (name or "") .. "-" .. realm
        -- (a realm never comes with a space, so this can't match another player)
        if type(name) == "string" and type(second) == "string" and second ~= ""
            and not isSecret(second) then
            playerWithSurname = name .. " " .. second
        end
    end
    if sender == playerFull or (playerWithSurname and sender == playerWithSurname) then return true end
    local short = Ambiguate and Ambiguate(sender, "none")
    if short == nil then return false end
    if playerWithSurname and short == playerWithSurname then return true end
    return UnitName and short == UnitName("player")
end

-- true when a sender hash is this character's (its own messages coming back)
function lib.IsOwnHash(hash)
    hash = tonumber(hash)
    if not hash then return false end
    isMe("")
    local name = UnitName and UnitName("player")
    for _, n in ipairs({ playerFull, playerWithSurname, name }) do
        if type(n) == "string" and n ~= "" and senderHash(n) == hash then return true end
    end
    return false
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, GUILD = true, INSTANCE_CHAT = true }
local V1_KINDS = { E = true, S = true, V = true, I = true, D = true, O = true }
local V2_KINDS = { R = true, L = true, G = true }

-----------------------------------------------------------------------------
-- Kinds other EzWoW addons add: lib.RegisterKind("F", spec)
--   spec.own()                  -> list of message bodies (this character's own
--                                  records; no ";" or "|", under 200 bytes)
--   spec.receive(body, hash, needed) -> true when something was stored
--                                  (needed = how many different players must
--                                  agree for a fact; see lib.Vote)
--   spec.localized = true       -> only players with the same client language
--                                  exchange it (records holding names)
-- Codes in use: F fishing spots (Smart Fishing), T flight times (Flight Map).
-----------------------------------------------------------------------------
lib.kinds = lib.kinds or {}

function lib.RegisterKind(code, spec)
    if type(code) ~= "string" or not code:match("^%u$") or V1_KINDS[code] or V2_KINDS[code] then return false end
    if type(spec) ~= "table" then return false end
    lib.kinds[code] = spec
    return true
end

-- one sender's vote for a value of a registered kind: the number of
-- different players that sent it so far (nil when this sender counted already)
function lib.Vote(key, value, hash)
    local entry = voteValue("other", tostring(key), tostring(value), hash)
    return entry and entry.n or nil
end

-- the shared table of a registered kind (saved with the shared data)
function lib.Store(code)
    local ext = lib.Data().ext
    if type(ext[code]) ~= "table" then ext[code] = {} end
    return ext[code]
end

-----------------------------------------------------------------------------
-- What NPCs sell, seen in their shop windows (record kind "M":
-- "npcID,itemID.itemID...", base 36). This character's own list is the shop
-- as seen on the last visit; an item from other players counts once enough
-- different players saw it (see lib.Vote).
-- store M: [npcID] = { own = { itemID, ... }, got = { [itemID] = true } }
-----------------------------------------------------------------------------
local VENDOR_KIND = "M"
local VENDOR_ITEMS_MAX = 150

local function vendorStore()
    return lib.Store(VENDOR_KIND)
end

local function b36(n)
    local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    n = math.floor(n)
    repeat
        local d = n % 36
        out = digits:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    until n == 0
    return out
end

-- the shop window that is open: who sells what
function lib.OnMerchantShow()
    if not (lib.IsEnabled() and type(GetMerchantNumItems) == "function" and type(GetMerchantItemID) == "function") then return end
    local okGuid, guid = pcall(UnitGUID, "npc")
    local src, npcID = guidSource(okGuid and guid or nil)
    if not src or src:sub(1, 1) ~= "n" then return end
    local okN, n = pcall(GetMerchantNumItems)
    n = okN and tonumber(n) or 0
    if isSecret(n) or n <= 0 then return end
    local items, seen = {}, {}
    for i = 1, math.min(n, VENDOR_ITEMS_MAX) do
        local okID, itemID = pcall(GetMerchantItemID, i)
        if okID and type(itemID) == "number" and not isSecret(itemID) and itemID > 0 and not seen[itemID] then
            seen[itemID] = true
            items[#items + 1] = itemID
        end
    end
    if #items == 0 then return end
    table.sort(items)
    local t = vendorStore()
    local row = type(t[npcID]) == "table" and t[npcID] or {}
    t[npcID] = row
    local old = type(row.own) == "table" and table.concat(row.own, ",") or ""
    row.own = items
    row.t = now()
    if old ~= table.concat(items, ",") then changed("vendors") end
end

-- itemID -> list of npcIDs that sell it: this character's shops, items
-- confirmed by other players, then the records shipped with the addons
function lib.GetVendors(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if not lib.reverseVendors then
        local rev = {}
        local function add(id, npcID)
            local list = rev[id]
            if not list then
                list = {}
                rev[id] = list
            end
            for _, n in ipairs(list) do
                if n == npcID then return end
            end
            list[#list + 1] = npcID
        end
        local ownSeen = {}
        for npcID, row in pairs(vendorStore()) do
            if type(npcID) == "number" and type(row) == "table" then
                if type(row.own) == "table" then
                    ownSeen[npcID] = true
                    for _, id in ipairs(row.own) do add(id, npcID) end
                end
                for id, ok in pairs(type(row.got) == "table" and row.got or {}) do
                    -- a shop seen here lately: its own list is the newer one
                    if ok == true and not ownSeen[npcID] then add(id, npcID) end
                end
            end
        end
        for npcID, items in pairs(lib.Seed("vendors") or {}) do
            if type(npcID) == "number" and type(items) == "table" and not ownSeen[npcID] then
                for _, id in ipairs(items) do add(id, npcID) end
            end
        end
        lib.reverseVendors = rev
    end
    return lib.reverseVendors[itemID]
end

lib.RegisterKind(VENDOR_KIND, {
    own = function()
        local out = {}
        for npcID, row in pairs(vendorStore()) do
            if type(npcID) == "number" and type(row) == "table" and type(row.own) == "table" then
                local head = npcID .. ","
                local parts = {}
                local size = #head
                for _, id in ipairs(row.own) do
                    local code = b36(id)
                    if size + #code + 1 > 180 then
                        out[#out + 1] = head .. table.concat(parts, ".")
                        parts, size = {}, #head
                    end
                    parts[#parts + 1] = code
                    size = size + #code + 1
                end
                if #parts > 0 then out[#out + 1] = head .. table.concat(parts, ".") end
            end
        end
        return out
    end,
    receive = function(body, hash, needed)
        local npcID, list = body:match("^(%d+),([%w%.]+)$")
        npcID = tonumber(npcID)
        if not npcID or npcID < 1 or npcID > 10000000 or not list then return false end
        local t = vendorStore()
        local row = type(t[npcID]) == "table" and t[npcID] or nil
        local any = false
        for code in list:gmatch("[^%.]+") do
            local itemID = tonumber(code, 36)
            if itemID and itemID > 0 and itemID < 10000000 then
                local n = lib.Vote("M:" .. npcID .. ":" .. itemID, "1", hash)
                if n and n >= (tonumber(needed) or 2) then
                    if not row then
                        row = {}
                        t[npcID] = row
                    end
                    row.got = type(row.got) == "table" and row.got or {}
                    if not row.got[itemID] then
                        row.got[itemID] = true
                        any = true
                    end
                end
            end
        end
        if any then changed("vendors") end
        return any
    end,
})

-----------------------------------------------------------------------------
-- The dungeon a creature was looted in (record kind "Z": "npcID,instanceMapID").
-- store Z: [npcID] = { own = instanceMapID, got = instanceMapID }
-----------------------------------------------------------------------------
local INSTANCE_KIND = "Z"

function lib.NoteInstance(npcID, instanceMap)
    if type(npcID) ~= "number" or type(instanceMap) ~= "number" then return end
    local t = lib.Store(INSTANCE_KIND)
    local row = type(t[npcID]) == "table" and t[npcID] or {}
    if row.own == instanceMap then return end
    row.own = instanceMap
    t[npcID] = row
    changed("instances")
end

-- instance map ID of the dungeon a creature was looted in (nil when not known)
function lib.InstanceOf(npcID)
    local row = lib.Store(INSTANCE_KIND)[tonumber(npcID) or 0]
    if type(row) ~= "table" then return nil end
    return tonumber(row.own) or tonumber(row.got)
end

lib.RegisterKind(INSTANCE_KIND, {
    own = function()
        local out = {}
        for npcID, row in pairs(lib.Store(INSTANCE_KIND)) do
            if type(npcID) == "number" and type(row) == "table" and type(row.own) == "number" then
                out[#out + 1] = npcID .. "," .. row.own
            end
        end
        return out
    end,
    receive = function(body, hash, needed)
        local npcID, mapID = body:match("^(%d+),(%d+)$")
        npcID, mapID = tonumber(npcID), tonumber(mapID)
        if not (npcID and mapID) or npcID < 1 or npcID > 10000000 or mapID < 1 or mapID > 100000 then return false end
        local n = lib.Vote("Z:" .. npcID, tostring(mapID), hash)
        if not n or n < (tonumber(needed) or 2) then return false end
        local t = lib.Store(INSTANCE_KIND)
        local row = type(t[npcID]) == "table" and t[npcID] or {}
        if row.got == mapID then return false end
        row.got = mapID
        t[npcID] = row
        changed("instances")
        return true
    end,
})

-- where an object (herb, vein, chest...) was looted: list of { continent, x, y }
function lib.GetGatherSpots(objectID)
    local list = lib.Data().gather[tonumber(objectID) or 0]
    return type(list) == "table" and list or nil
end

-----------------------------------------------------------------------------
-- The players of the data channel: who gets whispers, whose are taken
-----------------------------------------------------------------------------
local ROSTER_EVERY = 60     -- seconds between channel list requests
local ROSTER_AGAIN = 10     -- a whisper from a player not listed asks again after this long
local HELD_WAIT = 30        -- such a whisper waits this long for a fresh list
local HELD_MAX = 40
local MAX_ROSTER = 500

-- list = { { name = whisper target (as the list gives it), key = base name }, ... }
local roster = { list = {}, byKey = {}, asked = 0 }
local held = {}             -- whispers waiting for the list: { text, sender, t }
local accept                -- handles a message that passed the checks (below)

local RACE_FACTION = {
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance", Draenei = "Alliance",
    Worgen = "Alliance", VoidElf = "Alliance", LightforgedDraenei = "Alliance", DarkIronDwarf = "Alliance",
    KulTiran = "Alliance", Mechagnome = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde", BloodElf = "Horde", Goblin = "Horde",
    Nightborne = "Horde", HighmountainTauren = "Horde", MagharOrc = "Horde", ZandalariTroll = "Horde",
    Vulpera = "Horde",
}

-- the name without realm or family name (to compare senders with the list)
local function baseName(name)
    if type(name) ~= "string" or isSecret(name) then return nil end
    name = name:match("^[^%-]+") or name
    name = name:match("^(%S+)") or name
    return name ~= "" and name or nil
end

local function serverOf(guid)
    if type(guid) ~= "string" or isSecret(guid) then return nil end
    return guid:match("^Player%-(%d+)%-")
end

-- a player not found is left off the list for a while, longer each time
-- in a row: 10 minutes, then an hour, then for the rest of the session
local UNREACHABLE_FOR = { 600, 3600, math.huge }
local unreachable = {}          -- base name -> time until left off (this session)
local unreachableCount = {}     -- base name -> "not found" in a row (this session)

local myKey, myServer, myFaction
local function learnMe()
    if myKey then return end
    local okN, name = pcall(UnitName, "player")
    if okN then myKey = baseName(name) end
    local okG, guid = pcall(UnitGUID, "player")
    if okG then myServer = serverOf(guid) end
    if UnitFactionGroup then
        local okF, faction = pcall(UnitFactionGroup, "player")
        if okF and type(faction) == "string" and not isSecret(faction) then myFaction = faction end
    end
end

-- a list entry, or nil for this character and players of another faction or
-- server (whispers cannot reach them)
local function member(name, guid)
    if type(name) ~= "string" or isSecret(name) or name == "" then return nil end
    learnMe()
    local key = baseName(name)
    if not key or key == myKey then return nil end
    -- whispered a moment ago and not found: left out for a while
    if (unreachable[key] or 0) > clock() then return nil end
    local faction
    if type(guid) == "string" and not isSecret(guid) then
        local server = serverOf(guid)
        if server and myServer and server ~= myServer then return nil end
        if GetPlayerInfoByGUID then
            local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, guid)
            faction = ok and type(race) == "string" and not isSecret(race) and RACE_FACTION[race] or nil
            if faction and myFaction and faction ~= myFaction then return nil end
        end
    end
    -- faction unknown: the game has no details of that player yet
    return { name = name, key = key, unknown = faction == nil or nil }
end

local function removeMember(key)
    if not key or not roster.byKey[key] then return end
    roster.byKey[key] = nil
    local list = {}
    for _, m in ipairs(roster.list) do
        if m.key ~= key then list[#list + 1] = m end
    end
    roster.list = list
end

local function inRoster(sender)
    local key = baseName(sender)
    return key ~= nil and roster.byKey[key] ~= nil
end

local function channelNumber()
    if not GetChannelName then return nil end
    local ok, id = pcall(GetChannelName, CHANNEL_NAME)
    return ok and type(id) == "number" and not isSecret(id) and id > 0 and id or nil
end

-- the data channel's row in the game's channel list, and its member count
local function displayRow()
    if not (GetNumDisplayChannels and GetChannelDisplayInfo) then return nil, nil, "no api" end
    local number = channelNumber()
    if not number then return nil, nil, "not joined" end
    local okN, n = pcall(GetNumDisplayChannels)
    if not okN or type(n) ~= "number" or isSecret(n) then return nil, nil, "no list" end
    local wanted = CHANNEL_NAME:lower()
    for i = 1, min(n, 100) do
        local ok, name, header, _, num, count = pcall(GetChannelDisplayInfo, i)
        if ok and not isSecret(header) and not header then
            local hit = type(num) == "number" and not isSecret(num) and num == number
            if not hit and type(name) == "string" and not isSecret(name) then
                hit = name:lower():find(wanted, 1, true) ~= nil
            end
            if hit then
                return i, (type(count) == "number" and not isSecret(count)) and count or nil
            end
        end
    end
    return nil, nil, "not listed"
end

local function rosterInfoFn()
    if C_ChatInfo and type(C_ChatInfo.GetChannelRosterInfo) == "function" then return C_ChatInfo.GetChannelRosterInfo end
    if type(_G.GetChannelRosterInfo) == "function" then return _G.GetChannelRosterInfo end
    return nil
end

-- reads the list the game holds for the channel (asked for with requestRoster)
local function readRoster()
    local display, count, why = displayRow()
    roster.display, roster.channelCount = display, count
    if not display then roster.why = why return false end
    local info = rosterInfoFn()
    if not info then roster.why = "no api" return false end
    local n = count
    if type(GetNumChannelMembers) == "function" then
        local ok, c = pcall(GetNumChannelMembers, display)
        if ok and type(c) == "number" and not isSecret(c) then n = c end
    end
    local list, byKey, raw = {}, {}, 0
    for i = 1, min(n or MAX_ROSTER, MAX_ROSTER) do
        local ok, name, _, _, guid = pcall(info, display, i)
        if ok and type(name) == "string" then
            raw = raw + 1
            local m = member(name, guid)
            if m and not byKey[m.key] then
                byKey[m.key] = m
                list[#list + 1] = m
            end
        elseif not n then
            break
        end
    end
    if raw == 0 then roster.why = "empty" return false end
    -- more names than the channel has: the game gave another channel's list
    if count and raw > count + 5 then roster.why = "other list" return false end
    roster.list, roster.byKey, roster.raw, roster.at, roster.why = list, byKey, raw, clock(), nil
    return true
end

-- whispers held for a fresher list: taken once the sender is listed
local function releaseHeld()
    if #held == 0 then return end
    local t = clock()
    local waiting = held
    held = {}
    for _, h in ipairs(waiting) do
        if inRoster(h.sender) then
            pcall(accept, h.text, "WHISPER", h.sender)
        elseif t - h.t < HELD_WAIT then
            held[#held + 1] = h
        end
    end
end

-- asks the game for the channel's member list (CHANNEL_ROSTER_UPDATE follows)
local function requestRoster()
    roster.asked = clock()
    local display = displayRow()
    local frame = _G.ChannelFrame
    local busy = frame and frame.IsShown and frame:IsShown()
    if display and type(SetSelectedDisplayChannel) == "function" and not busy then
        pcall(SetSelectedDisplayChannel, display)
    end
    if readRoster() then releaseHeld() end
end
lib.RequestRoster = requestRoster

local function onChannelMember(joined, name, channelName, guid)
    if type(channelName) ~= "string" or isSecret(channelName) or channelName:lower() ~= CHANNEL_NAME:lower() then return end
    -- a player who (re)joined the channel is online again: whispers may reach them
    if joined then
        local key = baseName(name)
        if key then unreachableCount[key] = nil; unreachable[key] = nil end
    end
    local m = member(name, guid)
    if not m then return end
    if not joined then
        removeMember(m.key)
    elseif not roster.byKey[m.key] then
        roster.byKey[m.key] = m
        roster.list[#roster.list + 1] = m
        releaseHeld()
    end
end

local function countWay(field, hash)
    local stats = lib.stats
    local w = stats[field]
    if type(w) ~= "table" then
        w = { players = 0, seen = {} }
        stats[field] = w
    end
    if not w.seen[hash] then
        w.seen[hash] = true
        w.players = w.players + 1
    end
end

-- Delivery check (/ezshare ping [name]): an addon whisper to this character or
-- to another player; players with this version answer. Format 0 is ignored by
-- every copy as a record.
local PING, PONG = "0P|ping", "0Q|pong"
local pongAt = {}       -- sender -> time answered (one answer per 10 seconds)

local function whisperRaw(text, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false, "no api" end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "WHISPER", target)
    if ok and (result == nil or result == true or result == 0) then return true end
    return false, ok and tostring(result) or "error"
end

function lib.OnPing(text, sender)
    learnMe()
    if text == PONG then
        say(format(T("pong"), sender))
    elseif isMe(sender) or baseName(sender) == myKey then
        say(T("pingSelf"))
    elseif clock() - (pongAt[sender] or -100) >= 10 then
        pongAt[sender] = clock()
        whisperRaw(PONG, sender)
    end
end

function lib.Ping(target)
    if type(target) ~= "string" or target == "" then
        -- this character by its full name: the family name is part of it
        -- (UnitName's second value, unless that is the realm)
        local ok, name, second = pcall(UnitName, "player")
        target = ok and type(name) == "string" and not isSecret(name) and name or nil
        if target and type(second) == "string" and not isSecret(second) and second ~= "" then
            local realm = (GetRealmName and GetRealmName()) or ""
            local normalized = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
            if second ~= realm and second ~= normalized then target = target .. " " .. second end
        end
    end
    if not target then return end
    local ok, why = whisperRaw(PING, target)
    if ok then
        say(format(T("pingSent"), target))
    else
        say(format(T("pingFail"), target, tostring(why)))
    end
end

function lib.OnAddonMessage(prefix, text, channel, sender)
    if isSecret(prefix) or isSecret(text) or isSecret(channel) or isSecret(sender) then return end
    if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" or not lib.IsEnabled() then return end
    if channel == "WHISPER" and (text == PING or text == PONG) then
        lib.OnPing(text, sender)
        return
    end
    if isMe(sender) or not text:find("^%d%u|.") then return end
    if channel == "WHISPER" then
        -- whispers are taken only from the players of the data channel
        if not lib.UsesChannel() then return end
        if not inRoster(sender) then
            countWay("unlisted", senderHash(sender))
            if #held < HELD_MAX then held[#held + 1] = { text = text, sender = sender, t = clock() } end
            if clock() - (roster.asked or 0) >= ROSTER_AGAIN then requestRoster() end
            return
        end
    end
    accept(text, channel, sender)
end

accept = function(text, channel, sender)
    local version, kind, payload = text:match("^(%d)(%u)|(.+)$")
    if not kind or not payload then return end
    -- a player heard from is reachable again
    local fromKey = baseName(sender)
    if fromKey and unreachableCount[fromKey] then unreachableCount[fromKey] = nil; unreachable[fromKey] = nil end
    if not ((version == "1" and V1_KINDS[kind]) or (version == "2" and (V2_KINDS[kind] or lib.kinds[kind]))) then return end
    local hash = senderHash(sender)
    local stats = lib.stats
    if not stats.senders[hash] then
        stats.senders[hash] = true
        stats.players = stats.players + 1
    end
    -- which way the players reached us (channel, guild, party...)
    local way = type(channel) == "string" and channel or "?"
    stats.via = stats.via or {}
    local w = stats.via[way] or { players = 0, seen = {} }
    stats.via[way] = w
    if not w.seen[hash] then w.seen[hash] = true; w.players = w.players + 1 end
    local needed = GROUP_CHANNELS[channel] and CONFIRM_GROUP or CONFIRM_PUBLIC
    local loc = locale()
    local localized = kind == "D" or kind == "O" or (lib.kinds[kind] and lib.kinds[kind].localized)
    for body in payload:gmatch("[^;]+") do
        if not allow(hash, 1) then break end
        stats.received = stats.received + 1
        if localized then
            -- item names: only from players with the same client language
            local l, rest = body:match("^(%a%a%u%u),(.+)$")
            if l == loc then receive(kind, rest, hash, needed) end
        else
            receive(kind, body, hash, needed)
        end
    end
    flushChanged()
end

-----------------------------------------------------------------------------
-- Messages: sending (one message every few seconds, own records only)
-----------------------------------------------------------------------------
local sentAt = {}        -- record key -> time sent to the party, raid and guild (this session)
local groupTurn = { turn = 0 }
local channelReady = false
local BASE_ORDER = { "E", "S", "V", "I", "O", "D", "R", "L", "G" }

local function kindOrder()
    local order = {}
    for _, k in ipairs(BASE_ORDER) do order[#order + 1] = k end
    for code in pairs(lib.kinds) do order[#order + 1] = code end
    return order
end

local function targets()
    local list = {}
    if IsInGuild and IsInGuild() then list[#list + 1] = { "GUILD" } end
    if IsInRaid and IsInRaid() then
        list[#list + 1] = { "RAID" }
    elseif IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) then
        list[#list + 1] = { "PARTY" }
    end
    return list
end

-- this character's records, ready to send: { kind, version, key, body }
local function collect()
    local loc = locale()
    local out = {}
    for _, rec in ipairs(ownRecords()) do
        local kind, body, version = rec[1], rec[2], rec[3]
        if kind == "D" or kind == "O" or (lib.kinds[kind] and lib.kinds[kind].localized) then body = loc .. "," .. body end
        -- a sighting is sent again as soon as it changes
        local key = kind .. ";" .. (kind == "R" and (body:match("^(%d+),") .. ":" .. tostring(rec[4])) or body)
        out[#out + 1] = { kind = kind, version = version, key = key, body = body }
    end
    return out
end

-- one message of the records not sent yet (sent: record key -> time; a
-- record goes again after resendAfter seconds, never when that is nil)
local function pack(records, sent, resendAfter, state)
    local t = now()
    local byKind = {}
    for _, rec in ipairs(records) do
        local last = sent[rec.key]
        if not last or (resendAfter and t - last > resendAfter) then
            local list = byKind[rec.kind]
            if not list then
                list = { version = rec.version }
                byKind[rec.kind] = list
            end
            list[#list + 1] = rec
        end
    end
    -- kinds take turns, so many drops do not hold back the rest
    local order = kindOrder()
    for i = 1, #order do
        local kind = order[(state.turn + i - 1) % #order + 1]
        local list = byKind[kind]
        if list then
            state.turn = (state.turn + i) % #order
            local head = list.version .. kind .. "|"
            local parts, keys, size = {}, {}, #head
            for _, rec in ipairs(list) do
                if size + #rec.body + 1 > MAX_MSG then break end
                parts[#parts + 1] = rec.body
                keys[#keys + 1] = { rec.key, sent[rec.key] }
                size = size + #rec.body + 1
                sent[rec.key] = t
            end
            if #parts > 0 then return head .. concat(parts, ";"), keys end
        end
    end
    return nil
end

-- a message that could not be sent: its records count as not sent
local function unsend(sent, keys)
    for _, k in ipairs(keys or {}) do sent[k[1]] = k[2] end
end

-- Whispers: one player of the channel list per tick, in turn. Each player
-- gets a record once this session (it is saved on their side).
local whisperTurn = 0
local whispered = {}     -- list key -> { sent = { record key -> time }, turn = n, any = true|nil }
local whisperedCount = 0
local recentWhisper = {} -- whisper target -> time (to hide "no such player" notices)

local function nextWhisper(records)
    local list = roster.list
    local n = #list
    for _ = 1, n do
        whisperTurn = whisperTurn % n + 1
        local m = list[whisperTurn]
        local w = whispered[m.key]
        if not w then
            w = { sent = {}, turn = 0 }
            whispered[m.key] = w
        end
        local msg, keys = pack(records, w.sent, nil, w)
        if msg then return m, msg, w, keys end
    end
    return nil
end

local function sendOne(msg, way, target)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, way, target)
    lib.stats.results = lib.stats.results or {}
    lib.stats.results[way] = ok and tostring(result) or "error"
    -- result: nil/true/0 when sent, otherwise a send-result code (throttled...)
    if ok and (result == nil or result == true or result == 0) then return true end
    return false, ok and tostring(result) or ("error " .. tostring(result))
end

local function sendTick()
    if not lib.IsEnabled() then return "off" end
    if InCombatLockdown and InCombatLockdown() then return "combat" end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "no api" end
    local useChannel = channelReady and lib.UsesChannel()
    if useChannel and clock() - (roster.asked or 0) >= ROSTER_EVERY then requestRoster() end
    local list = targets()
    local whisperOn = useChannel and #roster.list > 0
    if #list == 0 and not whisperOn then return "no target" end
    local records = collect()
    local notes = {}
    if #list > 0 then
        local msg, keys = pack(records, sentAt, RESEND_AFTER, groupTurn)
        if msg then
            local okAny, last = false, nil
            for _, target in ipairs(list) do
                local ok, why = sendOne(msg, target[1])
                if ok then okAny = true else last = why end
            end
            notes[#notes + 1] = okAny and "group sent" or ("group " .. tostring(last))
            if okAny then lib.stats.sent = lib.stats.sent + 1 else unsend(sentAt, keys) end
        else
            notes[#notes + 1] = "group nothing new"
        end
    end
    if whisperOn then
        local m, msg, w, keys = nextWhisper(records)
        if m then
            recentWhisper[m.name] = clock()
            local ok, why = sendOne(msg, "WHISPER", m.name)
            notes[#notes + 1] = ok and "whisper sent" or ("whisper " .. tostring(why))
            if ok then
                lib.stats.sent = lib.stats.sent + 1
                if not w.any then
                    w.any = true
                    whisperedCount = whisperedCount + 1
                end
            else
                unsend(w.sent, keys)
            end
        else
            notes[#notes + 1] = "whisper nothing new"
        end
    end
    return concat(notes, ", ")
end

-- "no such player" notices for a whisper sent a moment ago are not shown;
-- that player is taken off the list
local notFoundPattern
function lib.HideWhisperError(msg)
    if type(msg) ~= "string" or isSecret(msg) then return false end
    if not notFoundPattern then
        local fmt = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
        if type(fmt) ~= "string" or isSecret(fmt) then return false end
        -- Korean particle codes ("|1이라는;라는;") may come resolved or not
        fmt = fmt:gsub("|1[^;]*;[^;]*;", "\1")
        local escaped = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
        escaped = escaped:gsub("%%%%s", "\2")
        notFoundPattern = "^" .. (escaped:gsub("[\1\2]", ".-")) .. "$"
    end
    if not msg:find(notFoundPattern) then return false end
    -- the whisper target named in the notice (sent in the last 15 seconds)
    local t = clock()
    for name, at in pairs(recentWhisper) do
        if t - at <= 15 and msg:find(name, 1, true) then
            lib.stats.notFound = (lib.stats.notFound or 0) + 1
            -- the last few names, shown by /ezshare status (this session only)
            local names = lib.stats.notFoundNames or {}
            lib.stats.notFoundNames = names
            local key = baseName(name)
            -- "?" marks a player whose faction was not known
            local m = key and roster.byKey[key]
            names[#names + 1] = (m and m.unknown) and (name .. "(?)") or name
            if #names > 5 then table.remove(names, 1) end
            if key then
                local n = (unreachableCount[key] or 0) + 1
                unreachableCount[key] = n
                unreachable[key] = clock() + UNREACHABLE_FOR[math.min(n, #UNREACHABLE_FOR)]
            end
            removeMember(key)
            return true
        end
    end
    return false
end

-- the outcome of the last attempt is kept for /ezshare status
function lib.SendTick()
    local ok, note = pcall(sendTick)
    lib.stats.note = ok and note or ("error " .. tostring(note))
end

-----------------------------------------------------------------------------
-- The hidden channel: joined in the background, kept out of the chat windows
-----------------------------------------------------------------------------
local function isOurChannel(name)
    if type(name) ~= "string" or isSecret(name) then return false end
    -- the data channel and its short-lived placeholders ("EzWoWQPad1", ...)
    return name:lower():find("ezwowq", 1, true) ~= nil
end

local function removeFromChatWindows()
    local remove = (ChatFrameUtil and ChatFrameUtil.RemoveChannel) or _G.ChatFrame_RemoveChannel
    if type(remove) ~= "function" then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then pcall(remove, frame, CHANNEL_NAME) end
    end
end

-- The client gives a new channel the lowest free number (often 2, where
-- players expect Trade). The channel has to get a number from 10 up, which the
-- game's own channels never use. Numbers can't be picked, so placeholder
-- channels are joined one at a time until one lands on 9 or higher; the data
-- channel joined after that gets 10 or higher, and the placeholders are left
-- again. The numbers of the player's own channels never change. When that
-- fails, sharing goes through the party, raid and guild only (this session).
local LOW_LIMIT = 10
local MAX_SLOT = tonumber(MAX_WOW_CHAT_CHANNELS) or 20
local PAD_PREFIX = "EzWoWQPad"
local MAX_PADS = 12
local channelGaveUp, placing = false, false
local staleWaits = 0

local function channelIndex(name)
    local ok, id = pcall(GetChannelName, name)
    return ok and type(id) == "number" and not isSecret(id) and id > 0 and id or nil
end

local function joinByName(name)
    local join = (type(JoinTemporaryChannel) == "function" and JoinTemporaryChannel)
        or (C_ChatInfo and type(C_ChatInfo.JoinChannelByName) == "function" and C_ChatInfo.JoinChannelByName)
        or (type(JoinChannelByName) == "function" and JoinChannelByName)
    if join then pcall(join, name) end
end

local function leaveByName(name)
    if channelIndex(name) and type(LeaveChannelByName) == "function" then pcall(LeaveChannelByName, name) end
end

local function later(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, function() pcall(fn) end) end
end

local function joinedPads()
    local list = {}
    for index = 1, MAX_SLOT do
        local ok, id, name = pcall(GetChannelName, index)
        if ok and type(id) == "number" and id == index and type(name) == "string" and not isSecret(name)
            and name:find(PAD_PREFIX, 1, true) == 1 then
            list[#list + 1] = name
        end
    end
    return list
end

local function clearPads(tries)
    if placing then return end
    tries = tries or 0
    local pads = joinedPads()
    if #pads == 0 or tries >= 4 then return end
    for _, name in ipairs(pads) do leaveByName(name) end
    later(2, function() clearPads(tries + 1) end)
end

local function whenJoined(name, fn, tries)
    tries = tries or 0
    local index = channelIndex(name)
    if index or tries >= 8 then fn(index) return end
    later(0.5, function() whenJoined(name, fn, tries + 1) end)
end

local function finishPlacing(ok)
    placing = false
    if ok then
        channelReady = true
        later(1, removeFromChatWindows)
        later(3, requestRoster)
    else
        channelReady = false
        channelGaveUp = true
        leaveByName(CHANNEL_NAME)
    end
    later(1, clearPads)
end

local function relocate()
    placing = true
    channelReady = false
    leaveByName(CHANNEL_NAME)
    local count = 0

    local function joinOurs()
        joinByName(CHANNEL_NAME)
        whenJoined(CHANNEL_NAME, function(index)
            finishPlacing(index ~= nil and index >= LOW_LIMIT)
        end)
    end

    local function addPad()
        if count >= MAX_PADS then joinOurs() return end
        count = count + 1
        local name = PAD_PREFIX .. count
        joinByName(name)
        whenJoined(name, function(index)
            if not index then
                finishPlacing(false)
            elseif index >= LOW_LIMIT - 1 then
                joinOurs()
            else
                later(1, addPad)
            end
        end)
    end

    later(1.5, addPad)
end

function lib.JoinChannel()
    if channelGaveUp or placing or not lib.UsesChannel() then return end
    if InCombatLockdown and InCombatLockdown() then
        later(10, lib.JoinChannel)
        return
    end
    if #joinedPads() > 0 and staleWaits < 3 then
        staleWaits = staleWaits + 1
        clearPads()
        later(3, lib.JoinChannel)
        return
    end
    local mine = channelIndex(CHANNEL_NAME)
    if mine and mine >= LOW_LIMIT then
        channelReady = true
        later(1, removeFromChatWindows)
        later(3, requestRoster)
        return
    end
    relocate()
end

function lib.LeaveChannel()
    channelReady = false
    leaveByName(CHANNEL_NAME)
end

-- join / leave notices and any text typed into the channel are not shown
-- (registered once, by the first copy that gets here)
if not lib.chatFiltered then
    lib.chatFiltered = true
    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
    if type(addFilter) == "function" then
        local function chatFilter(_, _, _, _, _, channelString, _, _, _, _, channelBaseName)
            if isOurChannel(channelBaseName) or isOurChannel(channelString) then return true end
            return false
        end
        for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
            "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
            pcall(addFilter, event, chatFilter)
        end
    end
end

-- "no such player" after an addon whisper (a copy older than this one may
-- have set up the filters above, so this one has its own flag)
if not lib.whisperFiltered then
    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
    if type(addFilter) == "function" then
        lib.whisperFiltered = true
        pcall(addFilter, "CHAT_MSG_SYSTEM", function(_, _, msg)
            if lib.HideWhisperError then
                local ok, hide = pcall(lib.HideWhisperError, msg)
                if ok and hide then return true end
            end
            return false
        end)
    end
end

-----------------------------------------------------------------------------
-- Settings
-----------------------------------------------------------------------------
function lib.SetEnabled(on, useChannel)
    local s = settings()
    s.off = not on or nil
    if useChannel ~= nil then s.noChannel = not useChannel or nil end
    if lib.UsesChannel() then
        channelGaveUp = false
        if lib.started then lib.JoinChannel() end
    else
        lib.LeaveChannel()
    end
end

-- all records, then (shared = true) only those received from other players
local function counts(shared)
    local d = lib.Data()
    local nq, nr, nd, ng = 0, 0, 0, 0
    for _, key in ipairs({ "questEnders", "questGivers" }) do
        for _, v in pairs(d.quest[key]) do
            if not shared or (type(v) == "table" and v.shared) then nq = nq + 1 end
        end
    end
    for _, v in pairs(d.rare) do
        if not shared or (type(v) == "table" and v.shared) then nr = nr + 1 end
    end
    for _, items in pairs(d.drops) do
        local fromOthers = false
        if shared and type(items) == "table" then
            for _, v in pairs(items) do
                if v == "s" then fromOthers = true break end
            end
        end
        if not shared or fromOthers then nd = nd + 1 end
    end
    for _, spots in pairs(d.gather) do
        if type(spots) == "table" then
            if not shared then
                ng = ng + #spots
            else
                for _, spot in ipairs(spots) do
                    if type(spot) == "table" and spot.shared then ng = ng + 1 end
                end
            end
        end
    end
    return nq, nr, nd, ng
end

local function rosterLine()
    local age = roster.at and format(T("seconds"), floor(clock() - roster.at)) or "-"
    local unknown = 0
    for _, m in ipairs(roster.list) do
        if m.unknown then unknown = unknown + 1 end
    end
    return format(T("roster"), #roster.list, tostring(roster.raw or "-"), tostring(roster.channelCount or "-"),
        tostring(roster.display or "-"), age, whisperedCount) .. " " .. format(T("unknownFaction"), unknown)
end

function lib.Slash(msg)
    local raw = type(msg) == "string" and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    msg = raw:lower()
    if msg == "ping" or msg:find("^ping%s") then
        lib.Ping((raw:match("^%S+%s+(.+)$")))
    elseif msg == "on" then
        lib.SetEnabled(true)
        say(T("on"))
    elseif msg == "off" then
        lib.SetEnabled(false)
        say(T("off"))
    elseif msg == "channel on" then
        lib.SetEnabled(true, true)
        say(T("channelOn"))
    elseif msg == "channel off" then
        lib.SetEnabled(lib.IsEnabled(), false)
        say(T("channelOff"))
    elseif msg == "status" then
        say(lib.IsEnabled() and T("on") or T("off"))
        if lib.IsEnabled() then say(lib.UsesChannel() and T("channelOn") or T("channelOff")) end
        say(format(T("status"), counts()))
        say(format(T("applied"), counts(true)))
        local stats = lib.stats
        say(format(T("traffic"), stats.received, stats.players, stats.sent))
        say(format(T("lastSend"), tostring(stats.note or "-"), #targets()))
        local parts = {}
        for way, w in pairs(stats.via or {}) do parts[#parts + 1] = way .. " " .. w.players end
        if not (stats.via or {}).WHISPER then parts[#parts + 1] = "WHISPER 0" end
        if type(stats.unlisted) == "table" and stats.unlisted.players > 0 then
            parts[#parts + 1] = format(T("unlisted"), stats.unlisted.players)
        end
        say(format(T("via"), concat(parts, ", ")))
        parts = {}
        for way, r in pairs(stats.results or {}) do parts[#parts + 1] = way .. " " .. r end
        say(format(T("results"), #parts > 0 and concat(parts, ", ") or "-"))
        say(rosterLine())
        if (stats.notFound or 0) > 0 then
            say(format(T("notFound"), stats.notFound) .. " " .. concat(stats.notFoundNames or {}, ", "))
        end
    elseif msg == "roster" then
        requestRoster()
        say(rosterLine())
        if roster.why then say(format(T("noRoster"), tostring(roster.why))) end
        local names = {}
        for i, m in ipairs(roster.list) do
            if i > 20 then
                names[#names + 1] = "..."
                break
            end
            names[#names + 1] = m.name
        end
        if #names > 0 then say(format(T("rosterNames"), concat(names, ", "))) end
    else
        say(T("help"))
    end
end

-----------------------------------------------------------------------------
-- Tooltips: where an item drops, when a rare was seen
-----------------------------------------------------------------------------
local TIP_SOURCES = 3
local TIP_SOURCES_SHIFT = 10   -- with Shift held: the list opens up
local NAMES_PER_LINE = 3        -- an opened list goes down, this many names a line
local COMMON_DROP = 20          -- dropped by this many or more: not listed by name

local function tipLimit()
    return (IsShiftKeyDown and IsShiftKeyDown()) and TIP_SOURCES_SHIFT or TIP_SOURCES
end

local function ownTooltip(tip)
    return tip == _G.GameTooltip or tip == _G.ItemRefTooltip
end

-- The "EzWoW - <addon>" name line under the lines added here: the Tooltip
-- addon's name when it is loaded (item and unit tooltips are its part),
-- else the addon whose copy of this library runs
local function tagText()
    if lib.hosts and lib.hosts["EzWoW-Tooltip"] then return "EzWoW - Tooltip" end
    local title
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if type(getMeta) == "function" and lib.owner then
        local ok, t = pcall(getMeta, lib.owner, "Title")
        if ok and type(t) == "string" then title = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    end
    if type(title) == "string" and title:find("^EzWoW %- ") then return title end
    return "EzWoW"
end

local function addTag(tip)
    -- with EzWoW - Tooltip: its one name line at the bottom covers these lines too
    local attribute = _G.EzWoWTooltipAttribute
    if lib.hosts and lib.hosts["EzWoW-Tooltip"] and type(attribute) == "function" then
        if pcall(attribute, tip) then
            if tip.Show then pcall(tip.Show, tip) end
            return
        end
    end
    tip:AddDoubleLine(" ", tagText(), 0, 0, 0, 0.5, 0.5, 0.5)
    local sizer = _G.EzWoWTooltipTagSizer
    if sizer and sizer.Refit then pcall(sizer.Refit, tip) end
    if tip.Show then pcall(tip.Show, tip) end
end

-- "a, b, c" with "+N more" when the list is longer; a longer list (Shift)
-- goes on in more lines under the first: returns first line, { more lines }
local function namesText(names, total)
    local lines = {}
    for i = 1, #names, NAMES_PER_LINE do
        local part = {}
        for j = i, math.min(i + NAMES_PER_LINE - 1, #names) do part[#part + 1] = names[j] end
        lines[#lines + 1] = concat(part, ", ")
    end
    if #lines == 0 then return nil, nil end
    if total > #names then
        lines[#lines] = lines[#lines] .. " (" .. format(T("andMore"), total - #names) .. ")"
    end
    local first = table.remove(lines, 1)
    return first, (#lines > 0) and lines or nil
end

-- "Drops from" text of an item (nil: no named source)
function lib.DropText(itemID)
    local list = lib.GetDropSources(itemID)
    if not list or #list == 0 then return nil end
    -- sources without a known name are left out (no bare "object" word)
    local names, seen, total = {}, {}, 0
    for _, row in ipairs(list) do
        local name = lib.SourceName(row.src)
        if name and not seen[name] then
            seen[name] = true
            total = total + 1
            if #names < tipLimit() then names[#names + 1] = name end
        end
    end
    if #names == 0 then return nil end
    -- dropped all over (cloth, coins...): only how many (Shift opens the first ten)
    if total >= COMMON_DROP and not (IsShiftKeyDown and IsShiftKeyDown()) then
        return format(T("manyDrops"), total) .. " · Shift", nil
    end
    return namesText(names, total)
end

-- Recipe scrolls among the shops and drops seen: a scroll's name is
-- "<kind>: <recipe name>" ("요리법: ...", "Recipe: ..."), which ties it to the
-- recipe. Built again a while later (new records, names not loaded yet).
local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local scrollIndex, scrollIndexAt, scrollNamesMissing = nil, -1000, false

local function normName(text)
    if type(text) ~= "string" or text == "" or isSecret(text) then return nil end
    return (text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

local function buildScrollIndex()
    local ids = {}
    local function addID(id) if type(id) == "number" and id > 0 then ids[id] = true end end
    for _, row in pairs(lib.Store("M")) do
        if type(row) == "table" then
            for _, id in ipairs(type(row.own) == "table" and row.own or {}) do addID(id) end
            for id, ok in pairs(type(row.got) == "table" and row.got or {}) do if ok == true then addID(id) end end
        end
    end
    for _, items in pairs(lib.Seed("vendors") or {}) do
        for _, id in ipairs(type(items) == "table" and items or {}) do addID(id) end
    end
    for _, items in pairs(lib.Data().drops) do
        for id in pairs(type(items) == "table" and items or {}) do addID(id) end
    end
    for _, items in pairs(lib.Seed("drops") or {}) do
        for _, id in ipairs(type(items) == "table" and items or {}) do addID(id) end
    end
    local index = {}
    scrollNamesMissing = false
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    local getName = C_Item and C_Item.GetItemNameByID
    if type(getInstant) ~= "function" then return index end
    for id in pairs(ids) do
        local okInfo, _, _, _, _, _, classID = pcall(getInstant, id)
        if okInfo and classID == RECIPE_CLASS then
            local okName, name = false, nil
            if getName then okName, name = pcall(getName, id) end
            if okName and type(name) == "string" and not isSecret(name) then
                local key = normName(name:match("^[^:]+:%s*(.+)$") or name:match("：%s*(.+)$"))
                if key then
                    index[key] = index[key] or {}
                    table.insert(index[key], id)
                end
            else
                scrollNamesMissing = true
                if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
            end
        end
    end
    return index
end

-- { { label, text }, ... } for the scrolls of a recipe (by its name, any of
-- the names given)
function lib.RecipeSourceLines(...)
    local out = {}
    if not lib.ShowsTooltips() then return out end
    local t = clock()
    if not scrollIndex or t - scrollIndexAt > (scrollNamesMissing and 3 or 60) then
        local ok, index = pcall(buildScrollIndex)
        scrollIndex = ok and index or {}
        scrollIndexAt = t
    end
    local scrolls, seen = {}, {}
    for i = 1, select("#", ...) do
        for _, id in ipairs(scrollIndex[normName((select(i, ...)))] or {}) do
            if not seen[id] then
                seen[id] = true
                scrolls[#scrolls + 1] = id
            end
        end
    end
    local soldText, soldMore, dropText, dropMore
    for _, id in ipairs(scrolls) do
        if not soldText then soldText, soldMore = lib.VendorText(id) end
        if not dropText then dropText, dropMore = lib.DropText(id) end
    end
    if soldText then out[#out + 1] = { T("soldBy"), soldText, soldMore } end
    if dropText then out[#out + 1] = { T("droppedBy"), dropText, dropMore } end
    return out
end

-- The lines for an item, for an addon that draws them in its own block
-- (EzWoW - Tooltip): { { label, text }, ... } (empty: nothing to show)
function lib.ItemSourceLines(itemID)
    local out = {}
    itemID = tonumber(itemID)
    if not itemID or not lib.ShowsTooltips() then return out end
    local sold, soldMore = lib.VendorText(itemID)
    if sold then out[#out + 1] = { T("soldBy"), sold, soldMore } end
    local dropped, droppedMore = lib.DropText(itemID)
    if dropped then out[#out + 1] = { T("droppedBy"), dropped, droppedMore } end
    return out
end

function lib.OnItemTooltip(tip, data)
    if not (ownTooltip(tip) and lib.ShowsTooltips()) or type(data) ~= "table" then return end
    -- an addon draws these lines in its own block (see lib.ItemSourceLines)
    if lib.itemLinesBy and lib.hosts and lib.hosts[lib.itemLinesBy] then return end
    local itemID = data.id
    if isSecret(itemID) or type(itemID) ~= "number" then return end
    local added = lib.AddVendorLine(tip, itemID)
    local dropped, droppedMore = lib.DropText(itemID)
    if dropped then
        tip:AddLine(T("droppedBy") .. ": " .. dropped, 0.6, 0.8, 1, true)
        for _, line in ipairs(droppedMore or {}) do tip:AddLine("    " .. line, 0.6, 0.8, 1, true) end
        added = true
    end
    if added then addTag(tip) end
end

-- shops seen in the game that sell the item
-- npcID -> its spots in EzWoW - Map Finder's data (when it is loaded)
local npcSpotIndex
local function npcSpots(npcID)
    if not npcSpotIndex then
        local data = _G.EzWoWMapFinderData
        if type(data) ~= "table" then return nil end
        npcSpotIndex = {}
        for _, e in ipairs(data) do
            if type(e) == "table" and e.kind == "npc" and type(e.id) == "number" and not npcSpotIndex[e.id] then
                npcSpotIndex[e.id] = e
            end
        end
    end
    local e = npcSpotIndex[npcID]
    return e and type(e.spawns) == "table" and e.spawns or nil
end

-- yards from here to the closest spot of an NPC (nil: not known or elsewhere)
local function distanceTo(here, npcID)
    if not here then return nil end
    local best
    for _, sp in ipairs(npcSpots(npcID) or {}) do
        if type(sp) == "table" and sp[1] == here[1] and type(sp[2]) == "number" and type(sp[3]) == "number" then
            local dx, dy = sp[2] - here[2], sp[3] - here[3]
            local d = dx * dx + dy * dy
            if not best or d < best then best = d end
        end
    end
    return best
end

-- shops that sell the item: the closest first, a few named, the rest counted
-- (nil: no named shop)
function lib.VendorText(itemID)
    local list = lib.GetVendors(itemID)
    if not list or #list == 0 then return nil end
    local rows, seen = {}, {}
    local here = #list > tipLimit() and playerSpot() or nil
    for _, npcID in ipairs(list) do
        local name = lib.SourceName("n" .. npcID)
        if name and not seen[name] then
            seen[name] = true
            rows[#rows + 1] = { name = name, d = distanceTo(here, npcID) }
        end
    end
    if #rows == 0 then return nil end
    -- known distance first (closest first), the rest in their order
    for i, row in ipairs(rows) do row.i = i end
    table.sort(rows, function(a, b)
        if a.d and b.d then return a.d < b.d end
        if a.d or b.d then return a.d ~= nil end
        return a.i < b.i
    end)
    -- sold all over: only how many (Shift opens the ten closest)
    if #rows >= COMMON_DROP and not (IsShiftKeyDown and IsShiftKeyDown()) then
        return format(T("manyVendors"), #rows) .. " · Shift", nil
    end
    local names = {}
    for i = 1, math.min(#rows, tipLimit()) do names[i] = rows[i].name end
    return namesText(names, #rows)
end

-- true when a line was added
function lib.AddVendorLine(tip, itemID)
    local text, more = lib.VendorText(itemID)
    if not text then return false end
    tip:AddLine(T("soldBy") .. ": " .. text, 0.68, 0.89, 0.42, true)
    for _, line in ipairs(more or {}) do tip:AddLine("    " .. line, 0.68, 0.89, 0.42, true) end
    return true
end

function lib.OnUnitTooltip(tip, data)
    if not (ownTooltip(tip) and lib.ShowsTooltips()) or type(data) ~= "table" then return end
    local guid = data.guid
    if isSecret(guid) then return end
    local src, id = guidSource(guid)
    if not src or src:sub(1, 1) ~= "n" then return end
    local r = lib.GetRare(id)
    if not r or now() - (r.t or 0) < 30 then return end
    tip:AddLine(format(r.shared and T("seenShared") or T("seen"), ago(r.t)), 0.6, 0.8, 1)
    addTag(tip)
end

-----------------------------------------------------------------------------
-- Start-up (events are registered once; the newest copy handles them)
-----------------------------------------------------------------------------
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

function lib.OnEvent(event, ...)
    if event == "CHAT_MSG_ADDON" then
        lib.OnAddonMessage(...)
    elseif event == "QUEST_DETAIL" then
        if lib.IsEnabled() then onQuestDetail() end
    elseif event == "QUEST_COMPLETE" then
        if lib.IsEnabled() then onQuestComplete() end
    elseif event == "QUEST_TURNED_IN" then
        if lib.IsEnabled() then onQuestTurnedIn(...) end
    elseif event == "LOOT_OPENED" then
        onLootOpened()
    elseif event == "MERCHANT_SHOW" then
        lib.OnMerchantShow()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        checkUnit(...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        checkUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        checkUnit("mouseover")
    elseif event == "CHANNEL_ROSTER_UPDATE" then
        if readRoster() then releaseHeld() end
    elseif event == "CHAT_MSG_CHANNEL_JOIN" or event == "CHAT_MSG_CHANNEL_LEAVE" then
        local _, name, _, _, _, _, _, _, channelBaseName, _, _, guid = ...
        onChannelMember(event == "CHAT_MSG_CHANNEL_JOIN", name, channelBaseName, guid)
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        end
    elseif event == "PLAYER_ENTERING_WORLD" and not lib.started then
        lib.started = true
        -- after the game's own channels have their numbers
        later(12, lib.JoinChannel)
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(SEND_EVERY, function()
                if lib.SendTick then pcall(lib.SendTick) end
            end)
        end
    end
    flushChanged()
end

if not lib.events then
    lib.events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON", "QUEST_DETAIL",
        "QUEST_COMPLETE", "QUEST_TURNED_IN", "LOOT_OPENED", "NAME_PLATE_UNIT_ADDED",
        "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
        pcall(lib.events.RegisterEvent, lib.events, event)
    end
    lib.events:SetScript("OnEvent", function(_, event, ...)
        if not lib.OnEvent then return end
        local ok, err = pcall(lib.OnEvent, event, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end)

    SLASH_EZWOWSHARE1 = "/ezshare"
    SLASH_EZWOWSHARE2 = "/공유"
    SlashCmdList.EZWOWSHARE = function(msg) if lib.Slash then lib.Slash(msg) end end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        if Enum.TooltipDataType.Item then
            pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tip, data)
                if lib.OnItemTooltip then pcall(lib.OnItemTooltip, tip, data) end
            end)
        end
        if Enum.TooltipDataType.Unit then
            pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tip, data)
                if lib.OnUnitTooltip then pcall(lib.OnUnitTooltip, tip, data) end
            end)
        end
    end
end

-- events added after the first version (the frame may come from an older copy)
for _, event in ipairs({ "CHANNEL_ROSTER_UPDATE", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "MERCHANT_SHOW" }) do
    pcall(lib.events.RegisterEvent, lib.events, event)
end
