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
-- Received records:
--   * facts by ID (quest NPCs, drops) wait until enough different players
--     sent the same one: one from the party, raid or guild, two from the
--     server-wide channel;
--   * sightings and spots are used as they arrive.
-- Received records are never sent on and never replace this character's own.
-- Senders are kept only as a number (no names are saved).
--
-- Saved data: every EzWoW addon declares the same saved variable
-- (EzWoW_SharedData). Each addon's copy of it is merged in as it loads, so the
-- records stay when some of the addons are turned off.
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall, next = type, pairs, ipairs, tonumber, tostring, pcall, next
local floor, format, concat, max = math.floor, string.format, table.concat, math.max

local LIB_VERSION = 1

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

local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function now() return (type(time) == "function" and time()) or 0 end

-----------------------------------------------------------------------------
-- Texts (English, Korean; other languages use English)
-----------------------------------------------------------------------------
local TEXTS = {
    enUS = {
        on = "Data sharing is on.",
        off = "Data sharing is off. Nothing is sent or received.",
        channelOn = "The shared data channel is used.",
        channelOff = "Only the party, raid and guild are used (no channel).",
        help = "/ezshare on | off | channel on | channel off | status",
        status = "Records: quests %d, rare sightings %d, drop sources %d, gathering spots %d.",
        seen = "Seen %s ago",
        seenShared = "Seen %s ago (shared)",
        droppedBy = "Drops from",
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
        help = "/ezshare on | off | channel on | channel off | status  (/공유)",
        status = "기록: 퀘스트 %d, 희귀 몬스터 목격 %d, 드롭 출처 %d, 채집 위치 %d.",
        seen = "%s 전 목격",
        seenShared = "%s 전 목격 (공유)",
        droppedBy = "드롭",
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
        lib.reverseDrops = rev
    end
    return lib.reverseDrops[itemID]
end

function lib.SourceName(src)
    if type(src) ~= "string" then return nil end
    local name = lib.Data().names[src]
    if name then return name end
    local api = _G.EzWoWMapFinderAPI
    local id = tonumber(src:sub(2))
    if api and type(api.NameByID) == "function" and id then
        local ok, n = pcall(api.NameByID, src:sub(1, 1) == "n" and "npc" or "object", id)
        if ok and type(n) == "string" and n ~= "" then return n end
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

local function isMe(sender)
    if not playerFull then
        local name = UnitName and UnitName("player")
        local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
        playerFull = (name or "") .. "-" .. realm
    end
    if sender == playerFull then return true end
    local short = Ambiguate and Ambiguate(sender, "none")
    return short ~= nil and UnitName and short == UnitName("player")
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

-- where an object (herb, vein, chest...) was looted: list of { continent, x, y }
function lib.GetGatherSpots(objectID)
    local list = lib.Data().gather[tonumber(objectID) or 0]
    return type(list) == "table" and list or nil
end

function lib.OnAddonMessage(prefix, text, channel, sender)
    if isSecret(prefix) or isSecret(text) or isSecret(channel) or isSecret(sender) then return end
    if prefix ~= PREFIX or type(text) ~= "string" or type(sender) ~= "string" or not lib.IsEnabled() then return end
    if channel == "WHISPER" or isMe(sender) then return end
    local version, kind, payload = text:match("^(%d)(%u)|(.+)$")
    if not kind or not payload then return end
    if not ((version == "1" and V1_KINDS[kind]) or (version == "2" and (V2_KINDS[kind] or lib.kinds[kind]))) then return end
    local hash = senderHash(sender)
    local needed = GROUP_CHANNELS[channel] and CONFIRM_GROUP or CONFIRM_PUBLIC
    local loc = locale()
    local localized = kind == "D" or kind == "O" or (lib.kinds[kind] and lib.kinds[kind].localized)
    for body in payload:gmatch("[^;]+") do
        if not allow(hash, 1) then break end
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
local sentAt = {}        -- record text -> time sent (this session)
local channelReady = false
local BASE_ORDER = { "E", "S", "V", "I", "O", "D", "R", "L", "G" }
local kindTurn = 0

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
    if channelReady and lib.UsesChannel() and GetChannelName then
        local ok, id = pcall(GetChannelName, CHANNEL_NAME)
        if ok and type(id) == "number" and not isSecret(id) and id > 0 then list[#list + 1] = { "CHANNEL", id } end
    end
    return list
end

local function nextMessage()
    local t = now()
    local loc = locale()
    local byKind = {}
    for _, rec in ipairs(ownRecords()) do
        local kind, body, version = rec[1], rec[2], rec[3]
        if kind == "D" or kind == "O" or (lib.kinds[kind] and lib.kinds[kind].localized) then body = loc .. "," .. body end
        -- a sighting is sent again as soon as it changes
        local key = kind .. ";" .. (kind == "R" and (body:match("^(%d+),") .. ":" .. tostring(rec[4])) or body)
        local last = sentAt[key]
        if not last or t - last > RESEND_AFTER then
            byKind[kind] = byKind[kind] or { version = version }
            local list = byKind[kind]
            list[#list + 1] = { key = key, body = body }
        end
    end
    -- kinds take turns, so many drops do not hold back the rest
    local order = kindOrder()
    for i = 1, #order do
        local kind = order[(kindTurn + i - 1) % #order + 1]
        local list = byKind[kind]
        if list then
            kindTurn = (kindTurn + i) % #order
            local head = list.version .. kind .. "|"
            local parts, size = {}, #head
            for _, rec in ipairs(list) do
                if size + #rec.body + 1 > MAX_MSG then break end
                parts[#parts + 1] = rec.body
                size = size + #rec.body + 1
                sentAt[rec.key] = t
            end
            if #parts > 0 then return head .. concat(parts, ";") end
        end
    end
    return nil
end

function lib.SendTick()
    if not lib.IsEnabled() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local list = targets()
    if #list == 0 then return end
    local msg = nextMessage()
    if not msg then return end
    for _, target in ipairs(list) do
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, target[1], target[2])
    end
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

local function counts()
    local d = lib.Data()
    local nq, nr, nd, ng = 0, 0, 0, 0
    for _, key in ipairs({ "questEnders", "questGivers" }) do
        for _ in pairs(d.quest[key]) do nq = nq + 1 end
    end
    for _ in pairs(d.rare) do nr = nr + 1 end
    for _ in pairs(d.drops) do nd = nd + 1 end
    for _, spots in pairs(d.gather) do
        if type(spots) == "table" then ng = ng + #spots end
    end
    return nq, nr, nd, ng
end

function lib.Slash(msg)
    msg = type(msg) == "string" and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if msg == "on" then
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
    else
        say(T("help"))
    end
end

-----------------------------------------------------------------------------
-- Tooltips: where an item drops, when a rare was seen
-----------------------------------------------------------------------------
local TIP_SOURCES = 4

local function ownTooltip(tip)
    return tip == _G.GameTooltip or tip == _G.ItemRefTooltip
end

function lib.OnItemTooltip(tip, data)
    if not (ownTooltip(tip) and lib.ShowsTooltips()) or type(data) ~= "table" then return end
    local itemID = data.id
    if isSecret(itemID) or type(itemID) ~= "number" then return end
    local list = lib.GetDropSources(itemID)
    if not list or #list == 0 then return end
    local names = {}
    for _, row in ipairs(list) do
        local name = lib.SourceName(row.src)
        if name then
            names[#names + 1] = name
        elseif row.src:sub(1, 1) == "o" then
            names[#names + 1] = T("object")
        end
        if #names >= TIP_SOURCES then break end
    end
    if #names == 0 then return end
    tip:AddLine(T("droppedBy") .. ": " .. concat(names, ", "), 0.6, 0.8, 1, true)
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
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        checkUnit(...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        checkUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        checkUnit("mouseover")
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
