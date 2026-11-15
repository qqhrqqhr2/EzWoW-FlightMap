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
-- How records travel (see "Messages: sending"):
--   * this character's records are numbered in the order they were found;
--     a hello on the hidden data channel, the guild and the party tells how
--     far they go, and each player asks for the ones it does not have yet
--     (an addon whisper back); records found now go to everyone at once;
--   * so a record goes to a player once, not again and again. Once in 7 to
--     14 days a player takes everything from the start again.
--   * copies up to version 12 still get the records they lack in their own
--     form while their players are around.
-- Received records:
--   * facts by ID (quest NPCs, drops) wait until enough different players
--     sent the same one: one from the party, raid or guild, two from the
--     players of the data channel;
--   * sightings and spots are used as they arrive.
-- Received records are never sent on and never replace this character's own.
-- Votes keep senders only as a number. The activity log of the window
-- (/ezshare) keeps the names of recent senders and whisper targets, saved
-- with the data (the newest entries only).
--
-- Saved data: every EzWoW addon declares a store of its own
-- (EzWoW_ShareStore_<name>) and the old shared variable (EzWoW_SharedData).
-- At most two of the loaded addons save the data in their store (see
-- "Saved data" below). Each copy found is merged in as its addon loads, so
-- the records stay when some of the addons are turned off.
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall, next = type, pairs, ipairs, tonumber, tostring, pcall, next
local floor, format, concat, max, min = math.floor, string.format, table.concat, math.max, math.min

local LIB_VERSION = 13

-- one table for every copy (a newer copy updates the functions in it)
local lib = _G.EzWoW_Share
if type(lib) ~= "table" then
    lib = {}
    _G.EzWoW_Share = lib
end
ns.Share = lib
lib.hosts = lib.hosts or {}
lib.hosts[ADDON_NAME] = true
-- copies from version 10 on save the data in their addon's own store (older
-- copies do not, and their .toc has no store)
lib.storeHosts = lib.storeHosts or {}
lib.storeHosts[ADDON_NAME] = true

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

-- the activity log (filled in below); seq counts stored changes, pend the
-- reports kept until more players send the same (not used yet)
local activity = { seq = 0, pend = 0 }
lib.sessionStart = lib.sessionStart or now()

-----------------------------------------------------------------------------
-- Texts (English, Korean; other languages use English)
-----------------------------------------------------------------------------
local TEXTS = {
    enUS = {
        on = "Data sharing is on.",
        off = "Data sharing is off. Nothing is sent or received.",
        channelOn = "The shared data channel is used.",
        channelOff = "Only the party, raid and guild are used (no channel).",
        help = "/ezshare (window) | on | off | channel on | channel off | status | roster | ping [name]",
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
        rosterLeft = "Not whispered: other server %d, other faction %d, left out for now %d, no name yet %d.",
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
        -- window
        winTitle = "EzWoW - Data sharing",
        tabRecv = "Received", tabPeople = "Players", tabSent = "Sent", tabKinds = "By kind",
        colTime = "Time", colFrom = "From", colWay = "Way", colKind = "Kind", colRecords = "Records",
        colNew = "New", colNote = "Note", colName = "Player", colWays = "Received via", colMsgs = "Messages",
        colWhispered = "Whispered", colLast = "Last", colState = "State", colTo = "To", colResult = "Result",
        colReceived = "Received", colSentRecs = "Sent", colOwn = "Mine",
        colWait = "Waiting", colKnown = "Had", colContent = "What came in", colFresh = "Found now",
        tipFresh = "%d found this session went first",
        wayChannel = "Channel", wayWhisper = "Whisper", wayGuild = "Guild", wayParty = "Party", wayRaid = "Raid",
        wayInstance = "Instance",
        kindE = "Quest turn-in", kindS = "Quest giver", kindQ = "Quest offer", kindV = "Quest spot",
        kindI = "Quest item source", kindD = "Quest item drop", kindO = "Quest item object", kindL = "Drop source",
        kindM = "Shop items", kindZ = "Dungeon creature", kindN = "NPC spot", kindR = "Rare sighting",
        kindG = "Gathering spot", kindF = "Fishing spot", kindT = "Flight time", kindB = "Boss spot",
        kindW = "Quest rewards", kindU = "Trainer spells", kindJ = "Object name", kindP = "Shop side", kindX = "Zone exit",
        sideA = "Alliance", sideH = "Horde", sideN = "Neutral",
        descRewards = "%s · rewards %d, choices %d", descTeaches = "%s · %d spells",
        noteLang = "other language %d", noteLimit = "over the limit",
        stateListed = "on the channel list", stateUnknown = "faction unknown", stateAway = "left out for now",
        stateNotFound = "not found %d", stateHeld = "not on the list %d",
        stateServer = "other server", stateFaction = "other faction", stateNoName = "no name yet",
        resultOk = "sent", resultFail = "failed (%s)",
        sumOn = "Sharing on", sumOff = "Sharing off. Nothing is sent or received.",
        sumChannel = "channel %d (%s players), %d to whisper", sumNoChannel = "channel not used",
        sumChannelWait = "joining the channel",
        sumSession = "This session: %d records from %d players (new %d, waiting %d), %d messages sent (%s)",
        sumLast = "Last send: %s",
        btnShareOn = "Sharing: on", btnShareOff = "Sharing: off",
        btnChannelOn = "Channel: used", btnChannelOff = "Channel: not used", btnClear = "Clear log",
        btnViewAll = "Show: every message", btnViewNew = "Show: new only",
        logSince = "Log since %s", emptyList = "Nothing yet.",
        tipNoDetail = "Details are kept for the newest %d messages only.",
        tipCounts = "New %d · waiting for more players %d · had already %d",
        tipWay = "%s: %d messages", tipKind = "%s: %d records", tipFirst = "First seen %s",
        moreRecords = "+%d more",
        npcN = "NPC %d", objectN = "Object %d", itemN = "Item %d", questN = "Quest %d", mapN = "Map %d",
        descStart = "%s · starts at %s", descEnd = "%s · ends at %s", descSpot = "%s · objective %d spot",
        descFrom = "%s (from %s)", descRare = "%s · %s, %s ago", descShop = "%s: %d items", descIn = "%s · %s",
        descMob = "%s (monster)", descFish = "%s: %s x%d", descFlight = "%s · %d:%02d",
        -- record numbers and versions
        syncLine = "Records in step: mine %d (numbered up to %d), players %d (all taken %d), taking from %d, waiting %d, giving to %d.",
        syncShort = "taking from %d, waiting %d, giving to %d",
        versions = "Versions heard this session: %s", verOld = "v12 or older", colVersion = "Version",
        tipVersion = "Sharing version %s", tipAddons = "Addons: %s", tipTaken = "Records taken: up to %d of %d",
        kindY = "Records (in order)",
    },
    koKR = {
        on = "데이터 공유를 켰습니다.",
        off = "데이터 공유를 껐습니다. 보내지도 받지도 않습니다.",
        channelOn = "공유 데이터 채널을 씁니다.",
        channelOff = "파티·공격대·길드로만 공유합니다(채널 안 씀).",
        help = "/ezshare (창 열기) | on | off | channel on | channel off | status | roster | ping [이름]  (/공유)",
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
        rosterLeft = "귓속말 안 보냄: 다른 서버 %d명, 다른 진영 %d명, 잠시 뺌 %d명, 이름 모름 %d명.",
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
        -- window
        winTitle = "EzWoW - 데이터 공유",
        tabRecv = "받은 기록", tabPeople = "사람", tabSent = "보낸 기록", tabKinds = "종류별",
        colTime = "시간", colFrom = "보낸 사람", colWay = "경로", colKind = "종류", colRecords = "기록",
        colNew = "새 기록", colNote = "비고", colName = "이름", colWays = "받은 경로", colMsgs = "메시지",
        colWhispered = "귓속말 보냄", colLast = "마지막", colState = "상태", colTo = "받는 곳", colResult = "결과",
        colReceived = "받은 기록", colSentRecs = "보낸 기록", colOwn = "내 기록",
        colWait = "확인 대기", colKnown = "이미 있음", colContent = "받은 내용", colFresh = "새로 찾음",
        tipFresh = "이번 접속에 새로 찾은 기록 %d개를 먼저 보냄",
        wayChannel = "채널", wayWhisper = "귓속말", wayGuild = "길드", wayParty = "파티", wayRaid = "공격대",
        wayInstance = "인스턴스",
        kindE = "퀘스트 완료 NPC", kindS = "퀘스트 시작 NPC", kindQ = "퀘스트를 준 NPC", kindV = "퀘스트 장소",
        kindI = "퀘스트 아이템 출처", kindD = "퀘스트 아이템 드롭", kindO = "퀘스트 아이템 오브젝트",
        kindL = "드롭 출처", kindM = "상점 물건", kindZ = "던전 몬스터", kindN = "NPC 위치",
        kindR = "희귀 몬스터 목격", kindG = "채집 위치", kindF = "낚시 자리", kindT = "비행 시간", kindB = "보스 위치",
        kindW = "퀘스트 보상", kindU = "트레이너 주문", kindJ = "오브젝트 이름", kindP = "상점 진영", kindX = "지역 입구",
        sideA = "얼라이언스", sideH = "호드", sideN = "중립",
        descRewards = "%s · 보상 %d, 선택 %d", descTeaches = "%s · 주문 %d개",
        noteLang = "언어 다름 %d", noteLimit = "받기 한도 넘음",
        stateListed = "채널 명단", stateUnknown = "진영 모름", stateAway = "잠시 뺌",
        stateNotFound = "찾지 못함 %d", stateHeld = "명단 밖 %d",
        stateServer = "다른 서버", stateFaction = "다른 진영", stateNoName = "이름 모름",
        resultOk = "보냄", resultFail = "실패 (%s)",
        sumOn = "공유 켜짐", sumOff = "공유 꺼짐. 보내지도 받지도 않습니다.",
        sumChannel = "채널 %d번 (%s명), 귓속말 대상 %d명", sumNoChannel = "채널 안 씀",
        sumChannelWait = "채널 들어가는 중",
        sumSession = "이번 접속: 받은 기록 %d개 (%d명, 새 기록 %d개, 확인 대기 %d개), 보낸 메시지 %d개 (%s)",
        sumLast = "마지막 보내기: %s",
        btnShareOn = "공유: 켜짐", btnShareOff = "공유: 꺼짐",
        btnChannelOn = "채널: 씀", btnChannelOff = "채널: 안 씀", btnClear = "기록 지우기",
        btnViewAll = "보기: 모든 메시지", btnViewNew = "보기: 새 기록만",
        logSince = "%s부터 기록", emptyList = "아직 없습니다.",
        tipNoDetail = "자세한 내용은 최근 메시지 %d개만 남습니다.",
        tipCounts = "새 기록 %d · 다른 사람 확인 대기 %d · 이미 있음 %d",
        tipWay = "%s: 메시지 %d개", tipKind = "%s: 기록 %d개", tipFirst = "처음 본 때: %s",
        moreRecords = "외 %d개",
        npcN = "NPC %d", objectN = "오브젝트 %d", itemN = "아이템 %d", questN = "퀘스트 %d", mapN = "지도 %d",
        descStart = "%s · 시작: %s", descEnd = "%s · 완료: %s", descSpot = "%s · 목표 %d 장소",
        descFrom = "%s (출처: %s)", descRare = "%s · %s, %s 전", descShop = "%s: 물건 %d개", descIn = "%s · %s",
        descMob = "%s (몬스터)", descFish = "%s: %s x%d", descFlight = "%s · %d:%02d",
        -- 기록 번호와 버전
        syncLine = "기록 맞추기: 내 기록 %d개 (번호 %d까지), 상대 %d명 (다 받음 %d명), 받는 중 %d명, 받을 차례 %d명, 보내는 중 %d명.",
        syncShort = "받는 중 %d명, 받을 차례 %d명, 보내는 중 %d명",
        versions = "이번 접속에 본 버전: %s", verOld = "v12 이하", colVersion = "버전",
        tipVersion = "공유 버전 %s", tipAddons = "애드온: %s", tipTaken = "받은 기록: 번호 %d까지 (상대 %d까지)",
        kindY = "기록 (번호 순서)",
    },
}
-- An addon can give the language of these texts (owner -> function that
-- returns a locale code, as its own language setting); the addon that draws
-- the item lines comes first, the game language when none gives one
lib.languageOf = lib.languageOf or {}
function lib.SetLanguageSource(owner, fn)
    if type(owner) ~= "string" then return end
    lib.languageOf[owner] = (type(fn) == "function") and fn or nil
end
local function activeLocale()
    local fns = lib.languageOf or {}
    local fn = lib.itemLinesBy and fns[lib.itemLinesBy]
    if not fn then
        for _, f in pairs(fns) do fn = f; break end
    end
    if fn then
        local ok, code = pcall(fn)
        if ok and type(code) == "string" and code ~= "" and code ~= "auto" and code ~= "Auto" then
            if code == "esMX" then code = "esES" elseif code == "enGB" then code = "enUS" end
            return code
        end
    end
    return (GetLocale and GetLocale()) or "enUS"
end
local function T(key)
    local set = TEXTS[activeLocale()] or TEXTS.enUS
    return set[key] or TEXTS.enUS[key] or key
end
lib.Text = T

local function say(text)
    if DEFAULT_CHAT_FRAME and not (InCombatLockdown and InCombatLockdown()) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff4bc8e8EzWoW|r: " .. tostring(text))
    end
end

-- secs: under a minute in seconds (else "1 min")
local function ago(t, secs)
    local age = max(0, now() - (t or 0))
    if secs and age < 60 then return format(T("seconds"), floor(age)) end
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
    local d = { v = 1, settings = {}, quest = {}, rare = {}, drops = {}, gather = {}, names = {}, inbox = {}, ext = {}, sync = {} }
    for _, key in ipairs(QUEST_KEYS) do d.quest[key] = {} end
    return d
end

local function shape(d)
    if type(d) ~= "table" then return fresh() end
    for _, key in ipairs({ "settings", "quest", "rare", "drops", "gather", "names", "inbox", "ext", "sync" }) do
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

-- The activity log is not joined like the records: of the saved copies, the
-- newest one is kept (taken into use by the first entry of this session).
function activity.adopt(saved)
    local log = saved.log
    saved.log = nil
    if type(log) ~= "table" then return end
    local cur = lib.savedLog
    if type(cur) ~= "table" or (tonumber(log.at) or 0) > (tonumber(cur.at) or 0) then lib.savedLog = log end
end

-- Each EzWoW addon declares a store of its own (EzWoW_ShareStore_ and its
-- folder name without "EzWoW-") besides the old shared variable. At logout
-- the whole data goes to the stores of at most two loaded addons (keepers);
-- the others save nothing for it. Every saved copy found is joined in as its
-- addon loads, so a keeper turned off keeps its copy until it comes back.
do
    -- the addons that keep the data first; the rest by name
    local KEEP_FIRST = { "EzWoW-MapFinder", "EzWoW-Quest", "EzWoW-Tooltip", "EzWoW-BestGearFinder",
        "EzWoW-DungeonRouteGuide", "EzWoW-ProfessionRecipes" }
    local rank = {}
    for i, name in ipairs(KEEP_FIRST) do rank[name] = i end

    lib.storeLoaded = lib.storeLoaded or {}   -- addon -> its store came from disk this session

    function lib.StoreName(name)
        return "EzWoW_ShareStore_" .. (tostring(name):gsub("^EzWoW%-", ""))
    end

    -- the settings as text, to tell at logout whether they changed this session
    local function asText(v, depth)
        if type(v) ~= "table" then return type(v):sub(1, 1) .. tostring(v) end
        if depth > 6 then return "?" end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for i, k in ipairs(keys) do keys[i] = asText(k, 0) .. "=" .. asText(v[k], depth + 1) end
        return "{" .. concat(keys, ",") .. "}"
    end

    -- data an older copy joined before this one ran: its settings count as of
    -- the newest stamp it took in
    local old = lib.data
    if type(old) == "table" and lib.settingsAt == nil and type(old.settings) == "table" and next(old.settings) ~= nil then
        lib.settingsAt = tonumber(old.settingsAt) or tonumber(old.savedAt) or 0
        lib.settingsSnap = asText(old.settings, 0)
    end

    -- One saved copy joined into the data. The settings are not joined: those
    -- of the copy where they changed last are used as they are (a copy without
    -- a stamp counts as oldest), so an older copy cannot bring back an old
    -- arrow position or look.
    function lib.TakeIn(saved)
        local data = lib.Data()
        if type(saved) ~= "table" or saved == data then return false end
        activity.adopt(saved)
        local s, at = saved.settings, tonumber(saved.settingsAt) or tonumber(saved.savedAt) or 0
        saved.settings, saved.settingsAt, saved.savedAt = nil, nil, nil
        shape(data)
        local cur = data.settings
        if type(s) == "table" and s ~= cur and at > (lib.settingsAt or -1) then
            for k in pairs(cur) do cur[k] = nil end
            for k, v in pairs(s) do cur[k] = v end
            lib.settingsAt, lib.settingsSnap = at, asText(cur, 0)
        end
        merge(data, shape(saved), 0)
        return true
    end

    -- The saved copies loaded since the last call (an addon's saved variables
    -- are loaded right before its ADDON_LOADED): the old shared variable and
    -- each addon's store. A store is let go once joined (the data holds it).
    function lib.TakeSaved()
        local data = lib.Data()
        lib.TakeIn(_G.EzWoW_SharedData)
        _G.EzWoW_SharedData = data
        for name in pairs(lib.hosts) do
            local key = lib.StoreName(name)
            local store = _G[key]
            if type(store) == "table" and store ~= data then
                lib.TakeIn(store)
                lib.storeLoaded[name] = true
                _G[key] = nil
            end
        end
        shape(data)
    end

    -- each EzWoW addon's saved copies, as that addon loads
    function lib.OnAddonLoaded(name)
        if not lib.hosts[name] then return end
        lib.TakeSaved()
    end

    -- the loaded addons that keep the data this session (at most two) among
    -- those whose copy has a store, then all of these in order
    function lib.Keepers()
        local list = {}
        for name in pairs(lib.storeHosts) do
            if lib.hosts[name] then list[#list + 1] = name end
        end
        table.sort(list, function(a, b)
            local ra, rb = rank[a] or 99, rank[b] or 99
            if ra ~= rb then return ra < rb end
            return a < b
        end)
        return { list[1], list[2] }, list
    end

    -- PLAYER_LOGOUT (also on /reload), before the game writes the saved
    -- variables. The old shared variable is let go only when a keeper's store
    -- came from disk this session (after an update a /reload alone does not
    -- add the stores, so they would not be written) and every loaded copy has
    -- a store; until then it is saved as before as well.
    function lib.OnLogout()
        local data = lib.Data()
        shape(data)
        -- the activity log of earlier sessions stays when it was not used
        if type(data.log) ~= "table" and type(lib.savedLog) == "table" then
            data.log, lib.savedLog = lib.savedLog, nil
        end
        local t = now()
        data.savedAt = t
        -- settings not changed this session keep the stamp they came with
        data.settingsAt = asText(data.settings, 0) ~= (lib.settingsSnap or "{}") and t or (lib.settingsAt or 0)
        local _, list = lib.Keepers()
        local proven = false
        for i, name in ipairs(list) do
            _G[lib.StoreName(name)] = i <= 2 and data or nil
            if i <= 2 and lib.storeLoaded[name] then proven = true end
        end
        local all = true
        for name in pairs(lib.hosts) do
            if not lib.storeHosts[name] then all = false end
        end
        _G.EzWoW_SharedData = not (proven and all) and data or nil
    end
end

local function settings() return lib.Data().settings end

function lib.IsEnabled() return settings().off ~= true end
function lib.UsesChannel() return lib.IsEnabled() and settings().noChannel ~= true end
function lib.ShowsTooltips() return settings().noTooltip ~= true end

-- The quest addon keeps reading its own saved table (ns.DB.questEnders ...):
-- those keys are moved here and read through this table.
function lib.AttachQuestDB(db)
    if type(db) ~= "table" then return end
    -- the quest addon's own saved copies (the old shared variable and its
    -- store) may not be joined yet (event order between frames is not fixed)
    lib.TakeSaved()
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
    activity.seq = activity.seq + 1
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

-- whether the shipped records hold <value> in the list of <key> (drops: "n123"
-- -> item IDs, vendors: npcID -> item IDs): such a fact needs no votes
do
    local sets = {}
    function lib.SeedHas(kind, key, value)
        local seed = lib.Seed(kind)
        if not seed or key == nil then return false end
        local byKey = sets[kind]
        if not byKey or byKey.seed ~= seed then
            byKey = { seed = seed, of = {} }
            sets[kind] = byKey
        end
        local set = byKey.of[key]
        if set == nil then
            set = false
            local list = seed[key]
            if type(list) == "table" then
                set = {}
                for _, v in ipairs(list) do set[v] = true end
            end
            byKey.of[key] = set
        end
        return set and set[value] == true or false
    end
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

-- Name lookups other addons add: function(kind, id, locale) -> name or nil,
-- where kind is "npc" or "object" (an addon's name tables; the locale asked
-- for may be ignored).
lib.nameResolvers = lib.nameResolvers or {}

-- (in a block: the file is at Lua's limit of 200 locals)
do
-- short language codes some addons save, and the game's variants
local LOCALE_CODES = {
    ko = "koKR", en = "enUS", de = "deDE", fr = "frFR", es = "esES", ru = "ruRU",
    cn = "zhCN", tw = "zhTW", enGB = "enUS", esMX = "esES",
}
local function localeCode(code)
    if type(code) ~= "string" or code == "" or code == "auto" or code == "Auto" then return nil end
    return LOCALE_CODES[code] or code
end

-- Name of a source ("n" NPC ID, "o" object ID) in the language given (an
-- addon's own language setting) or else the language of this library's texts.
-- Names seen in the game are in the game's language: they come first only
-- when that is the language asked for.
function lib.SourceName(src, locale)
    if type(src) ~= "string" then return nil end
    locale = localeCode(locale) or localeCode(activeLocale()) or "enUS"
    local seen = lib.Data().names[src]
    if seen and locale == (localeCode(GetLocale and GetLocale()) or "enUS") then return seen end
    local id = tonumber(src:sub(2))
    if not id then return seen end
    local kind = src:sub(1, 1) == "n" and "npc" or "object"
    local function ask(fn, ...)
        local ok, n = pcall(fn, kind, id, ...)
        if ok and type(n) == "string" and not isSecret(n) and n ~= "" then return n end
        return nil
    end
    -- the map addon has names in every language; its older versions answer in
    -- their own language only, so they are asked after the others
    local api = _G.EzWoWMapFinderAPI
    local mapName = type(api) == "table" and type(api.NameByID) == "function" and api.NameByID or nil
    local mapTakesLocale = mapName and api.NameByIDTakesLocale == true
    if mapTakesLocale then
        local n = ask(mapName, locale)
        if n then return n end
    end
    for _, resolve in ipairs(lib.nameResolvers) do
        if type(resolve) == "function" then
            local n = ask(resolve, locale)
            if n then return n end
        end
    end
    if mapName and not mapTakesLocale then
        local n = ask(mapName)
        if n then return n end
    end
    return seen
end
end

-----------------------------------------------------------------------------
-- Messages: encoding
-----------------------------------------------------------------------------
local PREFIX = "EzWoWQData"           -- at most 16 characters (the quest addon's, kept)
local CHANNEL_NAME = "EzWoWQuestData"
local MAX_MSG = 240                   -- addon messages are limited to 255 bytes
local SEND_EVERY = 8                  -- seconds between outgoing messages
local CONFIRM_GROUP, CONFIRM_PUBLIC = 1, 2
-- a row waits this long after its last new vote; when the inbox is full the
-- oldest rows make room (records come once now, so a vote is not refused)
local INBOX_DAYS = 21
local INBOX_MAX, INBOX_KIND = 8000, 5000
local RECEIVE_PER_MINUTE = 600        -- records taken from one sender a minute (answers are paced below this)
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

-- inbox rows: key -> { t = last new vote, v = { [value] = { s, n, p } } }
-- quest facts keep the quest addon's inbox ("v2:" keys); other kinds use "v1:".
-- A row lives only until its fact is stored (voteDone) or INBOX_DAYS after its
-- last new vote; each kind ("L", "M", "W"... the key's first part) may hold at
-- most INBOX_KIND rows, so one busy kind cannot fill the inbox for the others.
-- Rows of facts this character has by now (stored, or shipped with the addons)
-- are let go when the inbox is first used in a session.
-- inboxCount[which] = rows; inboxCount.kinds[which][kind] = rows of that kind
local inboxCount = { kinds = {} }

local function inboxOf(which)
    local d = lib.Data()
    local box = which == "quest" and d.quest.questShareInbox or d.inbox
    local tag = which == "quest" and "v2:" or "v1:"
    if not inboxCount[which] then
        local n, kinds = 0, {}
        local oldest = now() - INBOX_DAYS * 86400
        local known = lib.InboxKnown
        for key, row in pairs(box) do
            if type(key) ~= "string" or key:sub(1, #tag) ~= tag or type(row) ~= "table" or (row.t or 0) < oldest then
                box[key] = nil
            elseif known and known(which, key:sub(#tag + 1), row) then
                box[key] = nil
            else
                n = n + 1
                local k = key:sub(#tag + 1):match("^([^:]+):") or "?"
                kinds[k] = (kinds[k] or 0) + 1
            end
        end
        inboxCount[which], inboxCount.kinds[which] = n, kinds
    end
    return box, tag
end

-- the inbox is full (or one kind of it): its oldest tenth makes room
local function makeRoom(which, kind)
    local box, tag = inboxOf(which)
    local rows = {}
    local prefix = kind and (tag .. kind .. ":")
    for key, row in pairs(box) do
        if not prefix or key:sub(1, #prefix) == prefix then
            rows[#rows + 1] = { key, type(row) == "table" and tonumber(row.t) or 0 }
        end
    end
    table.sort(rows, function(a, b) return a[2] < b[2] end)
    for i = 1, min(#rows, max(1, floor(#rows / 10))) do box[rows[i][1]] = nil end
    -- counted again (and rows of facts had by now let go) on the next use
    inboxCount[which], inboxCount.kinds[which] = nil, nil
end

-- one sender's vote for a value. Returns the entry when this vote counted, or,
-- with again (a group message: one player is enough), the entry this sender
-- voted for before; nil otherwise. A repeat does not keep the row alive.
local function voteValue(which, key, value, hash, spot, again)
    local box, tag = inboxOf(which)
    key = tag .. key
    local row = box[key]
    local entry = row and row.v and row.v[value]
    if entry and entry.s[hash] then return again and entry or nil end
    if not row then
        local k = key:sub(#tag + 1):match("^([^:]+):") or "?"
        if inboxCount[which] >= INBOX_MAX or (inboxCount.kinds[which][k] or 0) >= INBOX_KIND then
            makeRoom(which, (inboxCount.kinds[which][k] or 0) >= INBOX_KIND and k or nil)
            box = inboxOf(which)
            if inboxCount[which] >= INBOX_MAX or (inboxCount.kinds[which][k] or 0) >= INBOX_KIND then return nil end
        end
        local kinds = inboxCount.kinds[which]
        row = {}
        box[key] = row
        inboxCount[which] = inboxCount[which] + 1
        kinds[k] = (kinds[k] or 0) + 1
    end
    row.t = now()
    row.v = row.v or {}
    entry = row.v[value]
    if not entry then
        entry = { s = {}, n = 0 }
        row.v[value] = entry
    end
    if entry.n >= MAX_SENDERS then return nil end
    entry.s[hash] = true
    entry.n = entry.n + 1
    if spot and not entry.p then entry.p = spot end
    return entry
end

-- the fact is stored: its votes are not needed any more
local function voteDone(which, key)
    local box, tag = inboxOf(which)
    key = tag .. key
    if box[key] == nil then return end
    box[key] = nil
    inboxCount[which] = max(0, inboxCount[which] - 1)
    local kinds, k = inboxCount.kinds[which], key:sub(#tag + 1):match("^([^:]+):") or "?"
    kinds[k] = max(0, (kinds[k] or 0) - 1)
end

-- E / S: who takes a quest in / gives it out "questID,n|o,ID[,continent,x,y]"
local function receiveQuestNpc(code, storeName, body, hash, needed)
    local q, k, id, rest = body:match("^(%d+),([no]),(%d+),?(.*)$")
    q, id = intIn(q, 1, 1000000), intIn(id, 1, 10000000)
    if not (q and id) then return end
    local value = (k == "n" and "npc:" or "object:") .. id
    local voteKey = code .. ":" .. q
    local entry = voteValue("quest", voteKey, value, hash, parseSpot(rest), needed == CONFIRM_GROUP)
    if not entry then return end
    local store = lib.Data().quest[storeName]
    local current = store[q]
    if type(current) == "table" and current.key == value then
        -- had it already: the count goes with the stored value, and a row that
        -- backs only this value is let go (another value keeps its row)
        if current.shared then current.n = max(tonumber(current.n) or 0, entry.n) end
        local box, tag = inboxOf("quest")
        local row = box[tag .. voteKey]
        local only = type(row) == "table" and type(row.v) == "table"
        for v in pairs(only and row.v or {}) do
            if v ~= value then only = false break end
        end
        if only then voteDone("quest", voteKey) end
        return
    end
    if entry.n < needed then
        -- waits for more players (unless this character has its own record)
        if not (type(current) == "table" and not current.shared) then
            activity.pend = activity.pend + 1
        end
        return
    end
    if type(current) == "table" and not current.shared then return end
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
    local tbl = lib.Data().quest[storeName]
    if type(tbl[key]) == "table" and tbl[key][npcID] then return end   -- had it already: no vote
    local entry = voteValue("quest", voteKey, "1", hash, nil, needed == CONFIRM_GROUP)
    if not entry then return end
    if entry.n < needed then
        activity.pend = activity.pend + 1
        return
    end
    tbl[key] = tbl[key] or {}
    tbl[key][npcID] = "s"
    voteDone("quest", voteKey)
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
    local drops = lib.Data().drops
    if type(drops[src]) == "table" and drops[src][itemID] then return end   -- had it already: no vote
    if lib.SeedHas("drops", src, itemID) then return end                     -- shipped already: no vote
    local voteKey = "L:" .. src .. ":" .. itemID
    local entry = voteValue("other", voteKey, "1", hash, nil, needed == CONFIRM_GROUP)
    if not entry then return end
    if entry.n < needed then
        activity.pend = activity.pend + 1
        return
    end
    drops[src] = drops[src] or {}
    drops[src][itemID] = "s"
    voteDone("other", voteKey)
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
            -- true: stored; "wait": kept until more players send the same
            local ok, any = pcall(spec.receive, body, hash, needed)
            if ok and any == "wait" then
                activity.pend = activity.pend + 1
            elseif ok and any then
                changed(kind)
            end
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
--   spec.receive(body, hash, needed) -> true when something was stored,
--                                  "wait" when it is kept until more players
--                                  send the same (needed = how many different
--                                  players must agree for a fact; see lib.Vote)
--   spec.localized = true       -> only players with the same client language
--                                  exchange it (records holding names)
--   spec.describe(body)         -> text for the shared records window, or nil
--                                  (then the general text of the kind)
-- Codes in use: M shops, P shop sides and spots, Z dungeon creatures, W quest
-- rewards, U trainer spells, J object names (this file); F fishing spots (Smart Fishing), T flight times
-- (Flight Map), N NPC spots and X zone exits (Map Finder), Q quest offers (Quest), B boss areas
-- (Dungeon Route Guide).
-----------------------------------------------------------------------------
lib.kinds = lib.kinds or {}

function lib.RegisterKind(code, spec)
    if type(code) ~= "string" or not code:match("^%u$") or V1_KINDS[code] or V2_KINDS[code] then return false end
    if type(spec) ~= "table" then return false end
    lib.kinds[code] = spec
    return true
end

-- one sender's vote for a value of a registered kind: the number of
-- different players that sent it so far (nil when this sender counted already).
-- With needed (as receive gets it), a repeat by party, raid or guild still answers
-- the count, so the "one player is enough there" rule works whatever came first.
function lib.Vote(key, value, hash, needed)
    local entry = voteValue("other", tostring(key), tostring(value), hash, nil, tonumber(needed) == CONFIRM_GROUP)
    return entry and entry.n or nil
end

-- the fact of this key is stored: its votes are dropped (keeps the inbox small)
function lib.VoteDone(key)
    voteDone("other", tostring(key))
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
    if lib.NotePlace then pcall(lib.NotePlace, npcID) end
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
-- confirmed by other players, then the records shipped with the addons.
-- Shops of the other faction are left out (nil when none is left).
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
    local list = lib.reverseVendors[itemID]
    if not list or type(lib.IsOtherSide) ~= "function" then return list end
    local out
    for i, npcID in ipairs(list) do
        local okSide, other = pcall(lib.IsOtherSide, npcID)
        if okSide and other then
            if not out then
                out = {}
                for j = 1, i - 1 do out[j] = list[j] end
            end
        elseif out then
            out[#out + 1] = npcID
        end
    end
    if not out then return list end
    return #out > 0 and out or nil
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
        local own = {}
        for _, id in ipairs(row and type(row.own) == "table" and row.own or {}) do own[id] = true end
        local any, waiting = false, false
        for code in list:gmatch("[^%.]+") do
            local itemID = tonumber(code, 36)
            -- what this character saw, confirmed already or shipped: no vote
            if itemID and itemID > 0 and itemID < 10000000 and not own[itemID]
                and not (row and type(row.got) == "table" and row.got[itemID])
                and not lib.SeedHas("vendors", npcID, itemID) then
                local key = "M:" .. npcID .. ":" .. itemID
                local n = lib.Vote(key, "1", hash, needed)
                if n and n >= (tonumber(needed) or 2) then
                    if not row then
                        row = {}
                        t[npcID] = row
                    end
                    row.got = type(row.got) == "table" and row.got or {}
                    row.got[itemID] = true
                    lib.VoteDone(key)
                    any = true
                elseif n then
                    waiting = true
                end
            end
        end
        if any then changed("vendors") end
        return any or (waiting and "wait") or false
    end,
})

-----------------------------------------------------------------------------
-- The side of a shop NPC and where it stands, noted when its shop window
-- opens (record kind "P": "npcID,side[,continent,x,y]"; side A Alliance,
-- H Horde, N neither). The side keeps the other faction's shops out of the
-- "sold by" lists. The spot goes to EzWoW - Map Finder's NPC spots (kind "N")
-- of the players who have it, so shops seen by players without it get a
-- place on the map too. A side from other players counts once enough
-- different players sent it (see lib.Vote).
-- store P: [npcID] = { side = own note, spot = { continent, x, y }, got = confirmed side }
-----------------------------------------------------------------------------
do
    local PLACE_KIND = "P"
    local GROUP_SIDE = { Alliance = "A", Horde = "H" }
    local VALID_SIDE = { A = true, H = true, N = true }

    local function placeStore()
        return lib.Store(PLACE_KIND)
    end

    -- "A", "H" or "N" for a unit (nil: not known)
    local function unitSide(unit)
        if type(UnitFactionGroup) ~= "function" then return nil end
        local ok, group = pcall(UnitFactionGroup, unit)
        if not ok or isSecret(group) then return nil end
        return GROUP_SIDE[group] or "N"
    end

    local mySide
    function lib.MySide()
        if not mySide then
            local side = unitSide("player")
            if side == "A" or side == "H" then mySide = side end
        end
        return mySide
    end

    -- the shop window of this NPC is open
    function lib.NotePlace(npcID)
        if type(npcID) ~= "number" then return end
        local side = unitSide("npc")
        if not side then return end
        local spot
        if not (IsInInstance and IsInInstance()) then spot = playerSpot() end
        local t = placeStore()
        local row = type(t[npcID]) == "table" and t[npcID] or {}
        -- where the player stood: a new spot only when 15 yards or more away
        local old = type(row.spot) == "table" and row.spot or nil
        local moved = spot and not (old and old[1] == spot[1] and type(old[2]) == "number" and type(old[3]) == "number"
            and (old[2] - spot[2]) ^ 2 + (old[3] - spot[3]) ^ 2 < 15 * 15)
        if row.side == side and not moved then return end
        row.side = side
        if moved then row.spot = spot end
        t[npcID] = row
        changed(PLACE_KIND)
    end

    -- an NPC's side: Alliance or Horde as this character or other players
    -- saw it, else as the shipped records have it; "N" when only "neither"
    -- was seen (nil: not known). A seen "N" does not override a known side:
    -- the game may not give a side for every NPC.
    function lib.NpcSide(npcID)
        npcID = tonumber(npcID)
        if not npcID then return nil end
        local row = placeStore()[npcID]
        local own = type(row) == "table" and row.side or nil
        local got = type(row) == "table" and row.got or nil
        if own == "A" or own == "H" then return own end
        if got == "A" or got == "H" then return got end
        local seed = lib.Seed("sides")
        local shipped = seed and seed[npcID]
        if shipped == "A" or shipped == "H" then return shipped end
        if own == "N" or got == "N" then return "N" end
        return nil
    end

    -- true for an NPC of the other faction (never for a shop this character used)
    function lib.IsOtherSide(npcID)
        local mine = lib.MySide()
        npcID = tonumber(npcID)
        if not (mine and npcID) then return false end
        local row = placeStore()[npcID]
        if type(row) == "table" and row.side then return false end
        local side = lib.NpcSide(npcID)
        return (side == "A" or side == "H") and side ~= mine
    end

    lib.RegisterKind(PLACE_KIND, {
        own = function()
            local out = {}
            for npcID, row in pairs(placeStore()) do
                if type(npcID) == "number" and type(row) == "table" and VALID_SIDE[row.side] then
                    local text = spotText(row.spot)
                    out[#out + 1] = npcID .. "," .. row.side .. (text and ("," .. text) or "")
                end
            end
            return out
        end,
        receive = function(body, hash, needed)
            local npcID, side, rest = body:match("^(%d+),([AHN]),?(.*)$")
            npcID = intIn(npcID, 1, 10000000)
            if not npcID then return false end
            local result = false
            local t = placeStore()
            local row = type(t[npcID]) == "table" and t[npcID] or nil
            -- this character's own note, a side confirmed already or shipped: no vote
            local shipped = lib.Seed("sides")
            if not (row and (row.side or row.got)) and not (shipped and shipped[npcID] == side) then
                local key = "P:" .. npcID
                local n = lib.Vote(key, side, hash, needed)
                if n and n >= (tonumber(needed) or 2) then
                    row = row or {}
                    row.got = side
                    t[npcID] = row
                    lib.VoteDone(key)
                    result = true
                elseif n then
                    result = "wait"
                end
            end
            -- the spot: Map Finder checks it against its data and counts it
            local spot = rest ~= "" and parseSpot(rest) or nil
            local spots = lib.kinds.N
            if spot and type(spots) == "table" and type(spots.receive) == "function" then
                local ok, r = pcall(spots.receive, format("%d,%d,%.1f,%.1f,5", npcID, spot[1], spot[2], spot[3]), hash, needed)
                if ok and r == true then
                    result = true
                elseif ok and r == "wait" and not result then
                    result = "wait"
                end
            end
            return result
        end,
        describe = function(body)
            local npcID, side = body:match("^(%d+),([AHN])")
            if not npcID then return nil end
            return format(T("descIn"), lib.SourceName("n" .. npcID) or ("#" .. npcID), T("side" .. side))
        end,
    })
end

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
        local t = lib.Store(INSTANCE_KIND)
        local row = type(t[npcID]) == "table" and t[npcID] or {}
        if row.got == mapID or row.own == mapID then return false end   -- had it already: no vote
        local shipped = lib.Seed("instances")
        if shipped and shipped[npcID] == mapID then return false end     -- shipped already: no vote
        local n = lib.Vote("Z:" .. npcID, tostring(mapID), hash, needed)
        if not n then return false end
        if n < (tonumber(needed) or 2) then return "wait" end
        row.got = mapID
        t[npcID] = row
        lib.VoteDone("Z:" .. npcID)
        changed("instances")
        return true
    end,
})

-----------------------------------------------------------------------------
-- More facts seen while playing, shared by every EzWoW addon:
--   W  quest rewards           "questID,rewards,choices"  item IDs in base 36 with "."
--                              between (a quest shows other choices to other classes,
--                              so each item is a fact of its own)
--   U  what a trainer teaches  "npcID,spell.spell..."      spell IDs in base 36
--   J  object names            "objectID,name"            players with the same client
--                              language only
-- A fact from other players is kept once enough different players sent it (lib.Vote).
-- store W: [questID]  = { own = { r = { itemID... }, c = { itemID... } }, got = { [itemID] = "r" | "c" } }
-- store U: [npcID]    = { own = { spellID... }, got = { [spellID] = true } }
-- store J: [objectID] = { own = name, got = name }
-----------------------------------------------------------------------------
do
local function setupMoreKinds()
    local REWARD_KIND, TRAINER_KIND, OBJECT_KIND = "W", "U", "J"
    local MAX_IDS = 60

    local function ids36(list)
        local parts = {}
        for _, id in ipairs(list) do parts[#parts + 1] = b36(id) end
        return concat(parts, ".")
    end

    local function parseIds(text)
        local out = {}
        for code in (text or ""):gmatch("[^%.]+") do
            local id = tonumber(code, 36)
            if id and id > 0 and id < 10000000 and #out < MAX_IDS then out[#out + 1] = id end
        end
        return out
    end

    local function sortedKeys(set)
        local list = {}
        for id in pairs(set) do list[#list + 1] = id end
        table.sort(list)
        return list
    end

    -- a list of IDs in chunks of "head,id.id..." under 180 bytes
    local function chunks(out, head, list)
        local parts, size = {}, #head
        for _, id in ipairs(list) do
            local code = b36(id)
            if size + #code + 1 > 180 then
                out[#out + 1] = head .. concat(parts, ".")
                parts, size = {}, #head
            end
            parts[#parts + 1] = code
            size = size + #code + 1
        end
        if #parts > 0 then out[#out + 1] = head .. concat(parts, ".") end
    end

    -- this character's IDs as a set { [id] = true } (a list from an earlier build is read
    -- too). A set, so joining the saved copies of the addons adds the IDs together.
    local function setOf(v)
        local set = {}
        if type(v) ~= "table" then return set end
        for k, x in pairs(v) do
            if x == true and type(k) == "number" then
                set[k] = true
            elseif type(x) == "number" then
                set[x] = true
            end
        end
        return set
    end

    -- votes for IDs of one record (IDs had already get no vote); returns stored, waiting
    local function voteIds(key, ids, value, hash, needed, have, store)
        local any, waiting = false, false
        for _, id in ipairs(ids) do
            if not have(id) then
                local voteKey = key .. ":" .. id
                local n = lib.Vote(voteKey, value, hash, needed)
                if n and n >= (tonumber(needed) or 2) then
                    store(id)
                    lib.VoteDone(voteKey)
                    any = true
                elseif n then
                    waiting = true
                end
            end
        end
        return any, waiting
    end

    ---------------------------------------------------------------- W: quest rewards
    local function questItems(kind, countFn)
        local list, seen = {}, {}
        if type(countFn) ~= "function" or type(GetQuestItemLink) ~= "function" then return list end
        local okN, n = pcall(countFn)
        n = okN and tonumber(n) or 0
        if isSecret(n) then return list end
        for i = 1, min(n, 10) do
            local okL, link = pcall(GetQuestItemLink, kind, i)
            local id = okL and itemIDOf(link)
            if id and not seen[id] then
                seen[id] = true
                list[#list + 1] = id
            end
        end
        return list
    end

    -- the quest window (offer or reward): what it gives
    function lib.OnQuestRewards()
        if not lib.IsEnabled() or type(GetQuestID) ~= "function" then return end
        local okQ, q = pcall(GetQuestID)
        q = okQ and tonumber(q)
        if not q or isSecret(q) or q < 1 or q > 1000000 then return end
        local r, c = questItems("reward", GetNumQuestRewards), questItems("choice", GetNumQuestChoices)
        if #r == 0 and #c == 0 then return end
        local t = lib.Store(REWARD_KIND)
        local row = type(t[q]) == "table" and t[q] or {}
        local own = type(row.own) == "table" and row.own or {}
        -- what this account's characters saw, joined (other classes see other choices)
        local added = false
        for part, list in pairs({ r = r, c = c }) do
            local set = setOf(own[part])
            for _, id in ipairs(list) do
                if not set[id] then
                    set[id] = true
                    added = true
                end
            end
            own[part] = set
        end
        row.own = own
        t[q] = row
        if added then changed("rewards") end
    end

    -- items a quest gives: { r = { itemID... }, c = { itemID... } } or nil
    function lib.GetQuestRewards(questID)
        local row = lib.Store(REWARD_KIND)[tonumber(questID) or 0]
        if type(row) ~= "table" then return nil end
        local out = { r = {}, c = {} }
        for part in pairs(out) do
            local set = setOf(type(row.own) == "table" and row.own[part])
            for id, p in pairs(type(row.got) == "table" and row.got or {}) do
                if p == part then set[id] = true end
            end
            out[part] = sortedKeys(set)
        end
        return out
    end

    lib.RegisterKind(REWARD_KIND, {
        own = function()
            local out = {}
            for q, row in pairs(lib.Store(REWARD_KIND)) do
                if type(q) == "number" and type(row) == "table" and type(row.own) == "table" then
                    local body = q .. "," .. ids36(sortedKeys(setOf(row.own.r))) .. "," .. ids36(sortedKeys(setOf(row.own.c)))
                    if #body < 200 then out[#out + 1] = body end
                end
            end
            return out
        end,
        receive = function(body, hash, needed)
            local q, r, c = body:match("^(%d+),([%w%.]*),([%w%.]*)$")
            q = tonumber(q)
            if not q or q < 1 or q > 1000000 then return false end
            local t = lib.Store(REWARD_KIND)
            local row0 = type(t[q]) == "table" and t[q] or {}
            local mine = { r = setOf(type(row0.own) == "table" and row0.own.r), c = setOf(type(row0.own) == "table" and row0.own.c) }
            -- had already: seen by this character, confirmed before or shipped
            local shipped = lib.Seed("rewards")
            shipped = shipped and type(shipped[q]) == "table" and shipped[q] or nil
            local function have(part)
                local seedSet = {}
                for _, id in ipairs(shipped and type(shipped[part]) == "table" and shipped[part] or {}) do seedSet[id] = true end
                return function(id)
                    local row = t[q]
                    return mine[part][id] or seedSet[id]
                        or (type(row) == "table" and type(row.got) == "table" and row.got[id] == part)
                end
            end
            local function store(part)
                return function(id)
                    local row = type(t[q]) == "table" and t[q] or {}
                    t[q] = row
                    row.got = type(row.got) == "table" and row.got or {}
                    row.got[id] = part
                end
            end
            local any1, wait1 = voteIds("W:" .. q, parseIds(r), "r", hash, needed, have("r"), store("r"))
            local any2, wait2 = voteIds("W:" .. q, parseIds(c), "c", hash, needed, have("c"), store("c"))
            if any1 or any2 then changed("rewards") end
            return (any1 or any2) or ((wait1 or wait2) and "wait") or false
        end,
    })

    ---------------------------------------------------------------- U: what trainers teach
    local function trainerFn(name)
        local t = _G.C_Trainer
        if type(t) == "table" and type(t[name]) == "function" then return t[name] end
        local fn = _G[name]
        return type(fn) == "function" and fn or nil
    end

    local function plainNumber(v)
        v = tonumber(v)
        if not v or isSecret(v) or v < 1 or v >= 10000000 then return nil end
        return v
    end

    -- the spell a service teaches (several ways; the first that answers)
    local function serviceSpell(i)
        local fn = trainerFn("GetTrainerServiceSpellID")
        if fn then
            local ok, id = pcall(fn, i)
            id = ok and plainNumber(id)
            if id then return id end
        end
        if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
            local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
            local id = ok and type(data) == "table" and plainNumber(data.id)
            if id then return id end
        end
        local linkFn = trainerFn("GetTrainerServiceItemLink")
        if linkFn then
            local ok, link = pcall(linkFn, i)
            if ok and type(link) == "string" and not isSecret(link) then
                return plainNumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
            end
        end
        return nil
    end

    -- the trainer window: the services it shows now (filters may hide some; what was
    -- seen before is kept)
    function lib.OnTrainerShow()
        if not lib.IsEnabled() then return end
        local okGuid, guid = pcall(UnitGUID, "npc")
        local src, npcID = guidSource(okGuid and guid or nil)
        if not src or src:sub(1, 1) ~= "n" then return end
        local numFn, infoFn = trainerFn("GetNumTrainerServices"), trainerFn("GetTrainerServiceInfo")
        if not (numFn and infoFn) then return end
        local okN, n = pcall(numFn)
        n = okN and tonumber(n) or 0
        if isSecret(n) then return end
        local t = lib.Store(TRAINER_KIND)
        local row = type(t[npcID]) == "table" and t[npcID] or {}
        local set = setOf(row.own)
        local added = false
        for i = 1, min(n, 300) do
            local ok, _, b, c = pcall(infoFn, i)
            if ok and b ~= "header" and c ~= "header" then
                local id = serviceSpell(i)
                if id and not set[id] then
                    set[id] = true
                    added = true
                end
            end
        end
        if not added then return end
        row.own = set
        t[npcID] = row
        changed("trainers")
    end

    -- spells a trainer teaches (this character's and confirmed ones)
    function lib.GetTrainerSpells(npcID)
        local row = lib.Store(TRAINER_KIND)[tonumber(npcID) or 0]
        if type(row) ~= "table" then return nil end
        local set = setOf(row.own)
        for id, ok in pairs(type(row.got) == "table" and row.got or {}) do
            if ok == true then set[id] = true end
        end
        return sortedKeys(set)
    end

    lib.RegisterKind(TRAINER_KIND, {
        own = function()
            local out = {}
            for npcID, row in pairs(lib.Store(TRAINER_KIND)) do
                if type(npcID) == "number" and type(row) == "table" and type(row.own) == "table" then
                    chunks(out, npcID .. ",", sortedKeys(setOf(row.own)))
                end
            end
            return out
        end,
        receive = function(body, hash, needed)
            local npcID, list = body:match("^(%d+),([%w%.]+)$")
            npcID = tonumber(npcID)
            if not npcID or npcID < 1 or npcID > 10000000 then return false end
            local t = lib.Store(TRAINER_KIND)
            local mine = setOf(type(t[npcID]) == "table" and t[npcID].own)
            local any, waiting = voteIds("U:" .. npcID, parseIds(list), "1", hash, needed,
                function(id)
                    local row = t[npcID]
                    return mine[id] or (type(row) == "table" and type(row.got) == "table" and row.got[id] == true)
                end,
                function(id)
                    local row = type(t[npcID]) == "table" and t[npcID] or {}
                    t[npcID] = row
                    row.got = type(row.got) == "table" and row.got or {}
                    row.got[id] = true
                end)
            if any then changed("trainers") end
            return any or (waiting and "wait") or false
        end,
    })

    ---------------------------------------------------------------- J: object names
    local function objectName(name)
        if type(name) ~= "string" or isSecret(name) or name == "" or #name > 90 then return nil end
        if name:find("[\1-\31\127|;]") then return nil end
        if UNKNOWNOBJECT and name == UNKNOWNOBJECT then return nil end
        return name
    end

    -- an object the player talks to or stands at (quest board, chest, mailbox...)
    function lib.OnObjectUnit(unit)
        if not lib.IsEnabled() then return end
        local okGuid, guid = pcall(UnitGUID, unit)
        local src, objectID = guidSource(okGuid and guid or nil)
        if not src or src:sub(1, 1) ~= "o" then return end
        local okName, name = pcall(UnitName, unit)
        name = okName and objectName(name)
        if not name then return end
        local t = lib.Store(OBJECT_KIND)
        local row = type(t[objectID]) == "table" and t[objectID] or {}
        if row.own == name then return end
        row.own = name
        t[objectID] = row
        changed("objects")
    end

    -- the name of an object in this client's language (nil when not known)
    function lib.ObjectName(objectID)
        local row = lib.Store(OBJECT_KIND)[tonumber(objectID) or 0]
        if type(row) ~= "table" then return nil end
        return row.own or row.got
    end

    lib.RegisterKind(OBJECT_KIND, {
        localized = true,
        own = function()
            local out = {}
            for id, row in pairs(lib.Store(OBJECT_KIND)) do
                if type(id) == "number" and type(row) == "table" and objectName(row.own) then
                    out[#out + 1] = id .. "," .. row.own
                end
            end
            return out
        end,
        receive = function(body, hash, needed)
            local id, name = body:match("^(%d+),(.+)$")
            id, name = tonumber(id), objectName(name)
            if not id or id < 1 or id > 10000000 or not name then return false end
            local t = lib.Store(OBJECT_KIND)
            local row = type(t[id]) == "table" and t[id] or {}
            if row.got == name or row.own == name then return false end   -- had it already: no vote
            local n = lib.Vote("J:" .. id, name, hash, needed)
            if not n then return false end
            if n < (tonumber(needed) or 2) then return "wait" end
            row.got = name
            t[id] = row
            lib.VoteDone("J:" .. id)
            changed("objects")
            return true
        end,
    })
end
setupMoreKinds()
end

-----------------------------------------------------------------------------
-- Inbox rows of facts this character has by now (its own record, a stored one,
-- or one shipped with the addons) are let go when the inbox is first used in a
-- session: a saved copy joined in can bring back rows that were done.
-- key: the row key without its tag ("L:n123:456", "E:1234", ...)
-----------------------------------------------------------------------------
do
    local function inList(list, id)
        if type(list) ~= "table" or not id then return false end
        if list[id] == true then return true end
        for _, v in ipairs(list) do
            if v == id then return true end
        end
        return false
    end

    local function row(code, id)
        local r = lib.Store(code)[tonumber(id) or 0]
        return type(r) == "table" and r or nil
    end

    local checks = {}
    function checks.L(src, item)
        item = tonumber(item)
        local items = lib.Data().drops[src]
        return (type(items) == "table" and items[item] ~= nil) or lib.SeedHas("drops", src, item)
    end
    function checks.M(npc, item)
        local r = row("M", npc)
        item = tonumber(item)
        if r and (inList(r.own, item) or (type(r.got) == "table" and r.got[item] ~= nil)) then return true end
        return lib.SeedHas("vendors", tonumber(npc), item)
    end
    function checks.P(npc)
        local r = row("P", npc)
        return r ~= nil and (r.side ~= nil or r.got ~= nil)
    end
    function checks.Z(npc)
        local r = row("Z", npc)
        return r ~= nil and (r.own ~= nil or r.got ~= nil)
    end
    function checks.W(q, item)
        local r = row("W", q)
        item = tonumber(item)
        if not r then return false end
        local own = type(r.own) == "table" and r.own or {}
        return inList(own.r, item) or inList(own.c, item) or (type(r.got) == "table" and r.got[item] ~= nil)
    end
    function checks.U(npc, spell)
        local r = row("U", npc)
        spell = tonumber(spell)
        return r ~= nil and (inList(r.own, spell) or (type(r.got) == "table" and r.got[spell] == true))
    end
    function checks.J(id)
        local r = row("J", id)
        return r ~= nil and (r.own ~= nil or r.got ~= nil)
    end

    local QUEST_STORES = { E = "questEnders", S = "questGivers" }
    local function questKnown(key, inboxRow)
        local code, rest = key:match("^(%u):(.+)$")
        local q = lib.Data().quest
        if QUEST_STORES[code] then
            -- only when every value of the row is the stored one
            local cur = q[QUEST_STORES[code]][tonumber(rest) or 0]
            if type(cur) ~= "table" or type(inboxRow.v) ~= "table" then return false end
            for v in pairs(inboxRow.v) do
                if v ~= cur.key then return false end
            end
            return true
        elseif code == "I" then
            local item, k, id = rest:match("^(%d+):([no]):(%d+)$")
            local t = item and q.questDropItems[tonumber(item)]
            return k == "n" and type(t) == "table" and t[tonumber(id)] ~= nil
        elseif code == "D" then
            local name, id = rest:match("^(.+):(%d+)$")
            local t = name and q.questDropSources[name]
            return type(t) == "table" and t[tonumber(id)] ~= nil
        end
        return false
    end

    function lib.InboxKnown(which, key, inboxRow)
        if type(key) ~= "string" or type(inboxRow) ~= "table" then return false end
        local ok, known
        if which == "quest" then
            ok, known = pcall(questKnown, key, inboxRow)
        else
            local code, a, b = key:match("^(%u):([^:]+):?(.*)$")
            local fn = code and checks[code]
            if not fn then return false end
            ok, known = pcall(fn, a, b)
        end
        return ok and known == true
    end
end

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
-- inChannel[base name] = everyone listed; left[base name] = why one is not
-- whispered ("server", "faction", "away", "noname")
local roster = { list = {}, byKey = {}, inChannel = {}, left = {}, asked = 0 }
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

-- a list entry to whisper, or nil and why not: this character ("me"), players
-- of another server or faction ("server", "faction": whispers cannot reach
-- them) and players not found a moment ago ("away")
local function member(name, guid)
    if type(name) ~= "string" or isSecret(name) or name == "" then return nil end
    learnMe()
    local key = baseName(name)
    if not key then return nil end
    if key == myKey then return nil, "me", key end
    -- whispered a moment ago and not found: left out for a while
    if (unreachable[key] or 0) > clock() then return nil, "away", key end
    local faction
    if type(guid) == "string" and not isSecret(guid) then
        local server = serverOf(guid)
        if server and myServer and server ~= myServer then return nil, "server", key end
        if GetPlayerInfoByGUID then
            local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, guid)
            faction = ok and type(race) == "string" and not isSecret(race) and RACE_FACTION[race] or nil
            if faction and myFaction and faction ~= myFaction then return nil, "faction", key end
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

-- whispers are taken from everyone on the channel's list, also from those
-- this character does not whisper (another server or faction, not found a
-- moment ago: a whisper from them shows they are there)
local function inRoster(sender)
    local key = baseName(sender)
    return key ~= nil and (roster.byKey[key] ~= nil or roster.inChannel[key] ~= nil)
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
    -- inChannel: everyone listed (whispers taken); left: why one is not whispered
    local list, byKey, raw, inChannel, left = {}, {}, 0, {}, {}
    learnMe()
    for i = 1, min(n or MAX_ROSTER, MAX_ROSTER) do
        local ok, name, _, _, guid = pcall(info, display, i)
        local secret = isSecret(name)
        if ok and not secret and type(name) == "string" and name ~= "" then
            raw = raw + 1
            -- back on the list after being off it: whispers may reach them again
            local back = baseName(name)
            if back and roster.at and not roster.inChannel[back] then
                unreachable[back], unreachableCount[back] = nil, nil
            end
            local m, why, key = member(name, guid)
            if m then
                inChannel[m.key] = true
                if not byKey[m.key] then
                    byKey[m.key] = m
                    list[#list + 1] = m
                end
            elseif key and why ~= "me" then
                inChannel[key] = true
                left[key] = why
            end
        elseif ok and not secret and n and (name == nil or name == "") then
            -- a row the game has no name for yet: the name from its GUID (it
            -- has no family name, so it only lets the player's whispers in)
            local key
            if type(guid) == "string" and not isSecret(guid) and GetPlayerInfoByGUID then
                local okInfo, _, _, _, _, _, guidName = pcall(GetPlayerInfoByGUID, guid)
                if okInfo then key = baseName(guidName) end
            end
            if key and key ~= myKey then
                raw = raw + 1
                inChannel[key] = true
                if not byKey[key] then left[key] = left[key] or "noname" end
            end
        elseif not n then
            break
        end
    end
    if raw == 0 then roster.why = "empty" return false end
    -- more names than the channel has: the game gave another channel's list
    if count and raw > count + 5 then roster.why = "other list" return false end
    -- (two players of the same first name: one is whispered)
    for key in pairs(byKey) do left[key] = nil end
    roster.list, roster.byKey, roster.raw, roster.at, roster.why = list, byKey, raw, clock(), nil
    roster.inChannel, roster.left = inChannel, left
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

-- asks the game for the channel's member list (CHANNEL_ROSTER_UPDATE follows).
-- Choosing the channel that is chosen already asks for nothing: the game keeps
-- the list it got then (players who left stay on it, those who came are
-- missing). Another channel is chosen first, in the same moment: then only
-- this channel's list comes (seen in game), not the other one's.
local function requestRoster()
    roster.asked = clock()
    local display = displayRow()
    local frame = _G.ChannelFrame
    local busy = frame and frame.IsShown and frame:IsShown()
    local asked = false
    if display and type(SetSelectedDisplayChannel) == "function" and not busy then
        local okN, total = pcall(GetNumDisplayChannels)
        if okN and type(total) == "number" and not isSecret(total) then
            for i = 1, min(total, 100) do
                local ok, _, header = pcall(GetChannelDisplayInfo, i)
                if i ~= display and ok and not isSecret(header) and not header then
                    asked = pcall(SetSelectedDisplayChannel, i)
                    break
                end
            end
        end
        pcall(SetSelectedDisplayChannel, display)
    end
    if not asked then
        if readRoster() then releaseHeld() end
    elseif C_Timer and C_Timer.After then
        -- the list is on its way (read on CHANNEL_ROSTER_UPDATE; until then the
        -- game holds none); read once more later in case no update comes
        C_Timer.After(5, function()
            local ok, got = pcall(readRoster)
            if ok and got then pcall(releaseHeld) end
        end)
    end
end
lib.RequestRoster = requestRoster

local function onChannelMember(joined, name, channelName, guid)
    if type(channelName) ~= "string" or isSecret(channelName) or channelName:lower() ~= CHANNEL_NAME:lower() then return end
    -- a player who (re)joined the channel is online again: whispers may reach them
    if joined then
        local key = baseName(name)
        if key then unreachableCount[key] = nil; unreachable[key] = nil end
    end
    local m, why, key = member(name, guid)
    key = m and m.key or key
    if not key or why == "me" then return end
    if not joined then
        roster.inChannel[key], roster.left[key] = nil, nil
        if m then removeMember(key) end
        return
    end
    roster.inChannel[key] = true
    if m and not roster.byKey[key] then
        roster.byKey[key] = m
        roster.list[#roster.list + 1] = m
        roster.left[key] = nil
    elseif not m and not roster.byKey[key] then
        roster.left[key] = why
    end
    -- whispers held for this player can be taken now
    releaseHeld()
end

-----------------------------------------------------------------------------
-- Activity log (shown by the window): which records came in from whom and
-- which went out. Kept with the saved data, the newest entries only; the
-- records themselves only for the newest messages.
--   log.recv   { t, who, way, k = kind, n = records, new = stored, wait = kept for
--                more players, known = had them already, lang, cut, p = records }
--   log.news   the messages that brought something new: { t, who, way, k, n, p = the new records }
--   log.sent   { t, way, to = whisper target, k, n, fail = result, p }
--   log.people [base name] = { name, msgs, recs, new, wait, last, ways = {}, kinds = {},
--                               whispered, whisperedAt, held, notFound, first }
--   log.kinds  [kind] = { r = received, u = stored, w = waiting, s = sent }
-----------------------------------------------------------------------------
do
local function setupActivity()
    local RECV_MAX, SENT_MAX, NEWS_MAX, PEOPLE_MAX = 300, 200, 300, 300
    local BODY_KEEP = 60
    activity.BODY_KEEP = BODY_KEEP

    local function data()
        local d = lib.Data()
        local log = d.log
        if type(log) ~= "table" then
            log = type(lib.savedLog) == "table" and lib.savedLog or {}
            lib.savedLog = nil
            d.log = log
        end
        for _, key in ipairs({ "recv", "news", "sent", "people", "kinds" }) do
            if type(log[key]) ~= "table" then log[key] = {} end
        end
        log.since = tonumber(log.since) or now()
        return log
    end
    activity.data = data

    function activity.clear()
        lib.Data().log = nil
        lib.savedLog = nil
    end

    local function shown(name)
        if type(name) ~= "string" or isSecret(name) or name == "" then return "?" end
        if Ambiguate then
            local ok, short = pcall(Ambiguate, name, "none")
            if ok and type(short) == "string" and not isSecret(short) and short ~= "" then return short end
        end
        return name
    end

    -- records as they came, without characters that would format the text
    local function plainRecords(payload)
        if type(payload) ~= "string" then return nil end
        return (payload:gsub("[\1-\31\127|]", ""))
    end

    local function kindRow(log, kind)
        local k = log.kinds[kind]
        if type(k) ~= "table" then
            k = { r = 0, u = 0, s = 0 }
            log.kinds[kind] = k
        end
        return k
    end

    local function person(log, name)
        local key = baseName(name)
        if not key then return nil end
        local p = log.people[key]
        if type(p) ~= "table" then
            p = { name = shown(name), first = now() }
            log.people[key] = p
            -- full: the one heard from longest ago makes room
            local n, oldKey, oldAt = 0, nil, math.huge
            for k, v in pairs(log.people) do
                n = n + 1
                local at = type(v) == "table" and max(tonumber(v.last) or 0, tonumber(v.whisperedAt) or 0) or 0
                if k ~= key and at < oldAt then oldKey, oldAt = k, at end
            end
            if n > PEOPLE_MAX and oldKey then log.people[oldKey] = nil end
        end
        -- "name surname" is the form whispers need: kept once seen
        local s = shown(name)
        if s:find(" ", 1, true) and not tostring(p.name or ""):find(" ", 1, true) then p.name = s end
        return p
    end

    -- keep: how many of the newest entries keep their records
    local function push(list, entry, limit, keep)
        list[#list + 1] = entry
        while #list > limit do table.remove(list, 1) end
        local old = list[#list - (keep or BODY_KEEP)]
        if old then old.p = nil end
    end

    -- one message taken in. c = { n = records, taken = looked at (the rest went
    -- over the sender's limit), new = stored, wait = kept for more players,
    -- lang = in another client language }; newBodies = the records that were new
    function activity.received(sender, way, kind, c, payload, newBodies)
        local log = data()
        local t = now()
        local n, taken = tonumber(c.n) or 0, tonumber(c.taken) or 0
        local new, wait, lang = tonumber(c.new) or 0, tonumber(c.wait) or 0, tonumber(c.lang) or 0
        local who = shown(sender)
        local known = max(0, taken - new - wait - lang)
        push(log.recv, { t = t, who = who, way = way, k = kind, n = n, new = new,
            wait = wait > 0 and wait or nil, known = known,
            lang = lang > 0 and lang or nil, cut = taken < n or nil, p = plainRecords(payload) }, RECV_MAX)
        if new > 0 and type(newBodies) == "table" then
            push(log.news, { t = t, who = who, way = way, k = kind, n = new,
                p = plainRecords(concat(newBodies, ";")) }, NEWS_MAX, NEWS_MAX)
        end
        local p = person(log, sender)
        if p then
            p.msgs = (p.msgs or 0) + 1
            p.recs = (p.recs or 0) + n
            p.new = (p.new or 0) + new
            p.wait = (p.wait or 0) + wait
            p.known = (p.known or 0) + known
            p.last = t
            p.ways = type(p.ways) == "table" and p.ways or {}
            p.ways[way] = (p.ways[way] or 0) + 1
            p.kinds = type(p.kinds) == "table" and p.kinds or {}
            p.kinds[kind] = (p.kinds[kind] or 0) + n
        end
        local k = kindRow(log, kind)
        k.r = (tonumber(k.r) or 0) + n
        k.u = (tonumber(k.u) or 0) + new
        k.w = (tonumber(k.w) or 0) + wait
        log.at = t
        lib.stats.used = (lib.stats.used or 0) + new
        lib.stats.waiting = (lib.stats.waiting or 0) + wait
    end

    -- one message sent (target: the whisper target; fresh: how many of its
    -- records were found this session)
    function activity.sent(way, target, msg, ok, why, fresh)
        local log = data()
        local t = now()
        local kind, payload = tostring(msg):match("^%d(%u)|(.+)$")
        local n = 0
        for _ in (payload or ""):gmatch("[^;]+") do n = n + 1 end
        fresh = tonumber(fresh) or 0
        push(log.sent, { t = t, way = way, to = target and shown(target) or nil, k = kind, n = n,
            fresh = fresh > 0 and fresh or nil,
            fail = (not ok) and tostring(why or "?") or nil, p = plainRecords(payload) }, SENT_MAX)
        if ok then
            if kind then
                local k = kindRow(log, kind)
                k.s = (tonumber(k.s) or 0) + n
            end
            local ways = lib.stats.sentWays or {}
            lib.stats.sentWays = ways
            ways[way] = (ways[way] or 0) + 1
            if target then
                local p = person(log, target)
                if p then
                    p.whispered = (p.whispered or 0) + 1
                    p.whisperedAt = t
                end
            end
        end
        log.at = t
    end

    -- a whisper from a player not (yet) on the channel list
    function activity.held(sender)
        local p = person(data(), sender)
        if p then
            p.held = (p.held or 0) + 1
            p.last = now()
        end
    end

    -- a whisper to this player found no such player
    function activity.notFound(name)
        local p = person(data(), name)
        if p then p.notFound = (p.notFound or 0) + 1 end
    end

    -- the sharing version a player has (and the EzWoW addons it told);
    -- weak: only noted when no newer version was heard from that player
    function activity.version(sender, ver, addons, weak)
        local p = person(data(), sender)
        if not p then return end
        ver = tostring(ver or "")
        if ver == "" then return end
        if weak and p.ver and p.ver ~= ver then return end
        p.ver = ver
        if type(addons) == "string" and addons ~= "" then p.addons = addons end
        p.verAt = now()
    end
end
setupActivity()
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
    -- hello, ask and numbered records (see "Messages: sending")
    if text:find("^3[HRY]|") then
        if not isMe(sender) and lib.SyncMessage then lib.SyncMessage(text, channel, sender) end
        return
    end
    if isMe(sender) or not text:find("^%d%u|.") then return end
    if channel == "WHISPER" then
        -- whispers are taken only from the players of the data channel
        if not lib.UsesChannel() then return end
        if not inRoster(sender) then
            countWay("unlisted", senderHash(sender))
            if activity.held then pcall(activity.held, sender) end
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
    -- the old form from a newer copy (for older copies around): its records
    -- come numbered as well, so this one passes it by (";~13", with names
    -- ";koKR,~13")
    if payload:find(";~%d+$") or payload:find(";%a%a%u%u,~%d+$") then
        if lib.SyncNewerPeer then lib.SyncNewerPeer(sender, channel) end
        return
    end
    -- a player whose whisper came in can be whispered again (a channel message
    -- only shows that they are in the channel, not that a whisper reaches them)
    local fromKey = baseName(sender)
    if channel == "WHISPER" and fromKey and unreachableCount[fromKey] then
        unreachableCount[fromKey] = nil; unreachable[fromKey] = nil
    end
    if not ((version == "1" and V1_KINDS[kind]) or (version == "2" and (V2_KINDS[kind] or lib.kinds[kind]))) then return end
    -- an older copy: its player gets the records it lacks in the old form too
    if lib.SyncOldPeer then lib.SyncOldPeer(sender, channel) end
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
    -- for the activity log: records in it, how many stored something (and
    -- which), how many wait for more players, how many in another language
    local total, taken, used, waiting, lang, limited = 0, 0, 0, 0, 0, false
    local newBodies
    for body in payload:gmatch("[^;]+") do
        total = total + 1
        if not limited and not allow(hash, 1) then limited = true end
        if not limited then
            taken = taken + 1
            stats.received = stats.received + 1
            local before, pendBefore = activity.seq, activity.pend
            if localized then
                -- item names: only from players with the same client language
                local l, rest = body:match("^(%a%a%u%u),(.+)$")
                if l == loc then receive(kind, rest, hash, needed) else lang = lang + 1 end
            else
                receive(kind, body, hash, needed)
            end
            if activity.seq > before then
                used = used + 1
                newBodies = newBodies or {}
                newBodies[#newBodies + 1] = body
            elseif activity.pend > pendBefore then
                waiting = waiting + 1
            end
        end
    end
    if activity.received then
        pcall(activity.received, sender, way, kind,
            { n = total, taken = taken, new = used, wait = waiting, lang = lang }, payload, newBodies)
    end
    flushChanged()
end

-----------------------------------------------------------------------------
-- Messages: sending. This character's own records are numbered in the order
-- they were found (its log, named by a random ID), so a player who has them
-- up to some number gets only the ones after it:
--   3H|log,last,version|addons  hello: "my records go up to <last>", with the
--                               sharing version and the EzWoW addons loaded
--                               ("MF2.0.30,QU1.0.21"); channel, guild and
--                               party, soon after login, then every 15 minutes
--   3R|log,have                 ask the log's owner for the records after
--                               <have> (a whisper; the channel when whispers
--                               can't reach that player)
--   3Y|log,from,to|records      the records numbered <from>..<to>, in order:
--                               "1E<body>;2L<body>;..." (numbers of records
--                               that changed or went are left out). The answer
--                               to an ask, or the records found now (channel,
--                               guild, party: everyone at once)
-- Numbers are in base 36. A player keeps how far it has each log: a message
-- moves that on only when it follows on (from <= have + 1) and none of its
-- records went over the receive limit. Every 7 to 14 days a log is taken from
-- the start again: votes of different players for the same fact meet again,
-- and records lost here come back.
-- Copies up to version 12 send their records again and again and don't know
-- these messages. Their records are taken as before, and while such players
-- are around, the records they did not have yet go out in the old form too
-- (one sweep for all of them, on the ways they were heard on), ending in
-- ";~13" so that newer copies pass them by.
-----------------------------------------------------------------------------
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

-- this character's records: { kind, version, key, body }; the key stays the
-- same while the record does (a sighting: its creature and when it was seen)
local function collect()
    local loc = locale()
    local out = {}
    for _, rec in ipairs(ownRecords()) do
        local kind, body, version = rec[1], rec[2], rec[3]
        if kind == "D" or kind == "O" or (lib.kinds[kind] and lib.kinds[kind].localized) then body = loc .. "," .. body end
        local key = kind .. ";" .. (kind == "R" and (body:match("^(%d+),") .. ":" .. tostring(rec[4])) or body)
        out[#out + 1] = { kind = kind, version = version, key = key, body = body }
    end
    return out
end

local whisperedCount = 0  -- players sent records by whisper this session
local recentWhisper = {}  -- whisper target -> time (to hide "no such player" notices)

-- quiet: not put in the activity log (hellos, asks)
local function sendOne(msg, way, target, fresh, quiet)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, way, target)
    lib.stats.results = lib.stats.results or {}
    lib.stats.results[way] = ok and tostring(result) or "error"
    -- result: nil/true/0 when sent, otherwise a send-result code (throttled...)
    local sent = ok and (result == nil or result == true or result == 0)
    local why = not sent and (ok and tostring(result) or ("error " .. tostring(result))) or nil
    if not quiet and activity.sent then pcall(activity.sent, way, way == "WHISPER" and target or nil, msg, sent, why, fresh) end
    if sent then return true end
    return false, why
end

local sync = {}
local sendTick
do
    local V = "3"
    local HELLO_FIRST, HELLO_EVERY = 30, 15 * 60
    -- answers: by whisper 4 s apart for one player; when three or more players
    -- (or one whispers can't reach) wait, on the channel 4 s apart for all of
    -- them at once; at most SERVE_MAX players, SESSION_MAX messages a session
    local SERVE_GAP, SERVE_CHANNEL_GAP, SERVE_MAX, SHARED_FROM, SESSION_MAX = 4, 4, 30, 3, 4000
    local ASK_MAX, ASK_STALL, ASK_TRIES = 2, 90, 3
    local NUMBER_MAX = 10000000     -- larger numbers in a message: not taken
    -- logs kept (the one heard from longest ago makes room) and logs waiting to be
    -- asked: bounded, so made-up hellos can't fill the saved data
    local PEERS_MAX, QUEUE_MAX = 600, 50
    local REFRESH_MIN, REFRESH_SPAN = 7 * 86400, 7 * 86400
    local PEER_KEEP, OLD_KEEP, OLD_AROUND, CHECK_EVERY = 90 * 86400, 30 * 86400, 30 * 60, 30
    -- an older copy can't tell what it missed (a loading screen, a lost message):
    -- it gets everything again once this long after the last whole sweep
    local OLD_AGAIN = 3 * 3600
    local MARK = ";~" .. LIB_VERSION

    -- addon folder (without "EzWoW-") -> its two letters in the hello
    local CODES = {
        Bags = "BA", BestGearFinder = "BG", ChatTranslator = "CT", DruidForms = "DF", DungeonRouteGuide = "DR",
        ErrorCatcher = "EC", FlightMap = "FL", FontChanger = "FC", FrameMover = "FM", GroupFinder = "GF",
        MapFinder = "MF", ProfessionRecipes = "PR", Quest = "QU", SmartFishing = "SF", SpellControl = "SC",
        Tooltip = "TT", UnitFrames = "UF", UtilityBar = "UB",
    }
    sync.CODES = CODES

    -- this session: online[base name] = { name, at, group = heard by party, raid or
    -- guild, newer = a hello came }; asking[log] = { progress, tries, way };
    -- queue[log] = { at, tries }; serve[sender] = { name, key, from, next, channel,
    -- fails, sent }; olds[base name] = { at, way } (older copies heard lately);
    -- sweep = the old-form round; served = answer messages sent this session
    local S = { online = {}, asking = {}, queue = {}, gaveUp = {}, serve = {}, olds = {}, checkAt = 0, served = 0 }
    -- recs[number] = record, order = the numbers in order, seqOf[record key] = number
    local L = { seqOf = {}, recs = {}, order = {}, count = 0 }
    sync.S, sync.L = S, L

    local function rand(a, b)
        if math.random then return math.random(a, b) end
        return a
    end

    -- the saved part (with the shared data): id = log ID, last = its last number,
    -- seq[record hash] = number, peers[log ID] = { h = have, l = their last,
    -- n = name, t = heard, r = take from the start again at }, old[base name] =
    -- { s = sent in the old form up to, t = heard, n = name }
    local function D()
        local d = lib.Data()
        local s = d.sync
        if type(s) ~= "table" then
            s = {}
            d.sync = s
        end
        if type(s.seq) ~= "table" then s.seq = {} end
        if type(s.peers) ~= "table" then s.peers = {} end
        if type(s.old) ~= "table" then s.old = {} end
        if type(s.id) ~= "string" or not s.id:match("^%w+$") or #s.id < 6 or #s.id > 12 then
            local a, b = b36(rand(0, 1679615)), b36(rand(0, 1679615))
            s.id = string.rep("0", 4 - #a) .. a .. string.rep("0", 4 - #b) .. b
            s.last, s.seq = 0, {}
        end
        s.last = tonumber(s.last) or 0
        return s
    end
    sync.D = D

    -- a record key as saved: two 31-bit hashes
    local function hashOf(key)
        local a, b = 5381, 52711
        for i = 1, #key do
            local c = key:byte(i)
            a = (a * 33 + c) % 2147483647
            b = (b * 131 + c) % 2147483629
        end
        return b36(a) .. "." .. b36(b)
    end

    -- this character's records with their numbers; a new record takes the next one
    function sync.number()
        local s = D()
        local list = collect()
        local recs, first, grew = {}, not L.numbered, false
        local hashes = first and {} or nil
        for _, rec in ipairs(list) do
            local n = L.seqOf[rec.key]
            if not n then
                local h = hashOf(rec.key)
                n = tonumber(s.seq[h])
                if not n then
                    s.last = s.last + 1
                    n = s.last
                    s.seq[h] = n
                end
                L.seqOf[rec.key] = n
                grew = true
                if hashes then hashes[h] = true end
            end
            if not recs[n] then recs[n] = rec end
        end
        if first then
            -- the numbers of records that are gone are let go
            for h in pairs(s.seq) do
                if not hashes[h] then s.seq[h] = nil end
            end
            L.numbered = true
            -- records numbered from now on go to everyone at once
            L.fresh = s.last + 1
        end
        local count = 0
        for _ in pairs(recs) do count = count + 1 end
        if grew or count ~= L.count then
            local order = {}
            for n in pairs(recs) do order[#order + 1] = n end
            table.sort(order)
            L.order = order
        end
        L.recs, L.count = recs, count
    end

    -- the place in the order of the first number >= from
    local function firstIndex(from)
        local order = L.order
        local lo, hi = 1, #order + 1
        while lo < hi do
            local mid = floor((lo + hi) / 2)
            if order[mid] < from then lo = mid + 1 else hi = mid end
        end
        return lo
    end

    -- one message of the records numbered from <from> on: message, last number
    -- in it, records in it, the records as text; nil when nothing is left
    local function pack(from)
        local s = D()
        if from > s.last then return nil end
        local head = V .. "Y|" .. s.id .. "," .. b36(from) .. ","
        local room = MAX_MSG - #head - 8
        local parts, size, to = {}, 0, from - 1
        local order, i = L.order, firstIndex(from)
        while i <= #order do
            local rec = L.recs[order[i]]
            local piece = rec.version .. rec.kind .. rec.body
            local add = #piece + (#parts > 0 and 1 or 0)
            if size + add > room then
                if #parts > 0 then break end
                -- longer than any message can carry: passed over
            else
                parts[#parts + 1] = piece
                size = size + add
            end
            to = order[i]
            i = i + 1
        end
        -- nothing after these: the numbers up to the last one are done
        if i > #order then to = s.last end
        local text = concat(parts, ";")
        return head .. b36(to) .. "|" .. text, to, #parts, text
    end
    sync.pack = pack

    -- the EzWoW addons loaded, with their versions
    local function addonList()
        local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
        local parts = {}
        if type(get) ~= "function" then return "" end
        for name in pairs(lib.hosts) do
            local code = CODES[(tostring(name):gsub("^EzWoW%-", ""))]
            if code then
                local ok, v = pcall(get, name, "Version")
                if ok and type(v) == "string" and not isSecret(v) and v:match("^[%w%.%-]+$") and #v <= 12 then
                    parts[#parts + 1] = code .. v
                end
            end
        end
        table.sort(parts)
        return concat(parts, ",")
    end

    local function helloText()
        local s = D()
        local text = V .. "H|" .. s.id .. "," .. b36(s.last) .. "," .. LIB_VERSION .. "|" .. addonList()
        while #text > 250 and text:find(",[^,|]*$") do text = text:gsub(",[^,|]*$", "") end
        return text
    end

    -- a player heard from this session
    local function seen(sender, way, newer)
        local key = baseName(sender)
        if not key then return nil end
        local o = S.online[key]
        if not o then
            o = {}
            S.online[key] = o
        end
        o.name, o.at = sender, clock()
        if GROUP_CHANNELS[way] then o.group = true end
        if newer then
            o.newer = true
            S.olds[key] = nil
        end
        return key, o
    end

    local function refreshAt() return now() + REFRESH_MIN + rand(0, REFRESH_SPAN) end

    local function peer(id, sender)
        local s = D()
        local p = s.peers[id]
        if type(p) ~= "table" then
            local n, oldId, oldAt = 0, nil, nil
            for k, v in pairs(s.peers) do
                n = n + 1
                local at = type(v) == "table" and tonumber(v.t) or 0
                if not oldAt or at < oldAt then oldId, oldAt = k, at end
            end
            if n >= PEERS_MAX and oldId then s.peers[oldId] = nil end
            p = { h = 0, l = 0, r = refreshAt() }
            s.peers[id] = p
        end
        p.h, p.l = tonumber(p.h) or 0, tonumber(p.l) or 0
        if type(sender) == "string" then p.n = sender end
        p.t = now()
        return p
    end

    -- that log has more than this character took: ask its owner soon (spread out)
    local function want(id)
        local p = D().peers[id]
        if type(p) ~= "table" or (tonumber(p.h) or 0) >= (tonumber(p.l) or 0) then return end
        if S.asking[id] or S.queue[id] or S.gaveUp[id] then return end
        local n = 0
        for _ in pairs(S.queue) do n = n + 1 end
        if n >= QUEUE_MAX then return end   -- (asked for later: the check comes every half minute)
        S.queue[id] = { at = clock() + rand(2, 15), tries = 0 }
    end

    ---------------------------------------------------------------- receiving
    function sync.hello(text, way, sender)
        local id, last, ver, addons = text:match("^3H|(%w+),(%w+),(%d+)|?([%w%.%-,]*)$")
        last = id and tonumber(last, 36)
        if not last or last > NUMBER_MAX or #id < 6 or #id > 12 or id == D().id then return end
        seen(sender, way, true)
        if activity.version then pcall(activity.version, sender, ver, addons) end
        local p = peer(id, sender)
        -- (a smaller number than before: the owner's data went back; take the rest again)
        if last < p.h then p.h = last end
        p.l = last
        lib.stats.hellos = (lib.stats.hellos or 0) + 1
        want(id)
    end

    -- someone asks for this character's records (only the log's owner answers)
    function sync.ask(text, way, sender)
        local id, have = text:match("^3R|(%w+),(%w+)$")
        have = id and tonumber(have, 36)
        local s = D()
        if not have or id ~= s.id or have < 0 or have >= s.last then return end
        local key = baseName(sender)
        if not key then return end
        -- by the channel only from players whispers can't reach (another faction or
        -- server): anyone else asks by whisper
        local far = roster.left[key] == "faction" or roster.left[key] == "server"
        if way == "CHANNEL" and not far then return end
        local q = S.serve[sender]
        if not q then
            local n = 0
            for _ in pairs(S.serve) do n = n + 1 end
            if n >= SERVE_MAX then return end
            q = { next = 0, sent = 0 }
            S.serve[sender] = q
        end
        q.name, q.key, q.from, q.channel, q.fails = sender, key, have + 1, way == "CHANNEL", 0
        lib.stats.askedBy = (lib.stats.askedBy or 0) + 1
    end

    -- numbered records: taken like any records, then the log moves on
    function sync.data(text, way, sender)
        local id, from, to, payload = text:match("^3Y|(%w+),(%w+),(%w+)|(.*)$")
        from, to = id and tonumber(from, 36), id and tonumber(to, 36)
        if not (from and to) or from < 1 or to < from - 1 or to > NUMBER_MAX or #id < 6 or #id > 12
            or id == D().id then return end
        -- by whisper only as the answer to an ask
        if way == "WHISPER" and not (S.asking[id] or S.queue[id]) then return end
        local key = seen(sender, way, true)
        local p = peer(id, sender)
        if to > p.l then p.l = to end
        -- the owner is answering (on the channel maybe for others first): no new ask
        local a = S.asking[id]
        if a then a.progress = clock() end
        if to <= p.h then
            if p.h >= p.l then S.asking[id], S.queue[id] = nil, nil end
            return
        end
        local hash = senderHash(sender)
        local stats = lib.stats
        if not stats.senders[hash] then
            stats.senders[hash] = true
            stats.players = stats.players + 1
        end
        local w = (stats.via or {})[way] or { players = 0, seen = {} }
        stats.via = stats.via or {}
        stats.via[way] = w
        if not w.seen[hash] then w.seen[hash] = true; w.players = w.players + 1 end
        -- a party, raid or guild member (heard there this session): one player is
        -- enough, whichever way the records come
        local o = key and S.online[key]
        local needed = (GROUP_CHANNELS[way] or (o and o.group)) and CONFIRM_GROUP or CONFIRM_PUBLIC
        local loc = locale()
        local groups, kinds = {}, {}
        local limited = false
        for piece in payload:gmatch("[^;]+") do
            local v, kind, body = piece:match("^(%d)(%u)(.+)$")
            if kind and ((v == "1" and V1_KINDS[kind]) or (v == "2" and (V2_KINDS[kind] or lib.kinds[kind]))) then
                local g = groups[kind]
                if not g then
                    g = { n = 0, taken = 0, new = 0, wait = 0, lang = 0, bodies = {} }
                    groups[kind] = g
                    kinds[#kinds + 1] = kind
                end
                g.n = g.n + 1
                g.bodies[#g.bodies + 1] = body
                if not limited and not allow(hash, 1) then limited = true end
                if not limited then
                    g.taken = g.taken + 1
                    stats.received = stats.received + 1
                    local before, pendBefore = activity.seq, activity.pend
                    if kind == "D" or kind == "O" or (lib.kinds[kind] and lib.kinds[kind].localized) then
                        local l, rest = body:match("^(%a%a%u%u),(.+)$")
                        if l == loc then receive(kind, rest, hash, needed) else g.lang = g.lang + 1 end
                    else
                        receive(kind, body, hash, needed)
                    end
                    if activity.seq > before then
                        g.new = g.new + 1
                        g.newBodies = g.newBodies or {}
                        g.newBodies[#g.newBodies + 1] = body
                    elseif activity.pend > pendBefore then
                        g.wait = g.wait + 1
                    end
                end
            end
        end
        if activity.received then
            for _, kind in ipairs(kinds) do
                local g = groups[kind]
                pcall(activity.received, sender, way, kind, g, concat(g.bodies, ";"), g.newBodies)
            end
        end
        -- the log moves on only when this follows on and nothing was cut
        if not limited and from <= p.h + 1 then p.h = to end
        if p.h >= p.l then S.asking[id], S.queue[id] = nil, nil end
        flushChanged()
    end

    function lib.SyncMessage(text, way, sender)
        if not lib.IsEnabled() or type(text) ~= "string" then return end
        local t = text:sub(1, 2)
        if t == "3H" then
            if way ~= "WHISPER" then sync.hello(text, way, sender) end
        elseif t == "3R" then
            sync.ask(text, way, sender)
        elseif t == "3Y" then
            sync.data(text, way, sender)
        end
    end

    -- an older copy's records came: its player is around (and gets the records
    -- it lacks in the old form)
    function lib.SyncOldPeer(sender, way)
        local key, o = seen(sender, way)
        if not key or o.newer then return end
        S.olds[key] = { at = clock(), way = (way == "WHISPER" or not way) and "CHANNEL" or way }
        local s = D()
        local r = s.old[key]
        if type(r) ~= "table" then
            r = { s = 0 }
            s.old[key] = r
        end
        r.t, r.n = now(), sender
        if activity.version then pcall(activity.version, sender, "12", nil, true) end
    end

    -- the old form from a newer copy: that player has the numbered records
    function lib.SyncNewerPeer(sender, way)
        seen(sender, way, true)
    end

    -- a whisper found no such player: no more answers or asks to them for now
    function lib.SyncNotFound(name)
        local key = baseName(name)
        if not key then return end
        for sender, q in pairs(S.serve) do
            if q.key == key then S.serve[sender] = nil end
        end
        S.online[key] = nil
        local peers = D().peers
        for id in pairs(S.asking) do
            local p = peers[id]
            if type(p) == "table" and baseName(p.n) == key then S.asking[id] = nil end
        end
    end

    -- the data channel is ready / a group joined: say hello there soon
    function lib.SyncChannelReady() S.helloAt = clock() + 5 end
    function lib.SyncGroupJoined() S.groupHelloAt = clock() + 5 end

    ---------------------------------------------------------------- asking
    -- how to reach a log's owner: "WHISPER", "CHANNEL" (whispers can't reach
    -- them: another faction or server) or nil (not around now)
    local function reach(p)
        local key = baseName(p.n)
        if not key or (unreachable[key] or 0) > clock() then return nil end
        local why = roster.left[key]
        if why == "faction" or why == "server" then return channelNumber() and "CHANNEL" or nil end
        if roster.byKey[key] or S.online[key] or roster.inChannel[key] then return "WHISPER" end
        return nil
    end

    -- every half minute: logs taken from the start again, saved logs whose owner
    -- is around now, entries not heard from for long let go
    function sync.check()
        local t = clock()
        if t < S.checkAt then return end
        S.checkAt = t + CHECK_EVERY
        local s, n = D(), now()
        for id, p in pairs(s.peers) do
            if type(p) ~= "table" or n - (tonumber(p.t) or 0) > PEER_KEEP then
                s.peers[id] = nil
            else
                if tonumber(p.r) and n > p.r then
                    p.h, p.r = 0, refreshAt()
                end
                local key = baseName(p.n)
                if key and (S.online[key] or roster.inChannel[key]) then want(id) end
            end
        end
        for key, o in pairs(s.old) do
            if type(o) ~= "table" or n - (tonumber(o.t) or 0) > OLD_KEEP then s.old[key] = nil end
        end
    end

    local function askTick(t)
        local peers = D().peers
        local active = 0
        -- (numbers read through tonumber: saved data may come from anywhere)
        local function done(p)
            return type(p) ~= "table" or (tonumber(p.h) or 0) >= (tonumber(p.l) or 0)
        end
        for id, a in pairs(S.asking) do
            local p = peers[id]
            if done(p) then
                S.asking[id] = nil
            elseif t - a.progress > ASK_STALL then
                -- no answer for a while: asked again a few times, then left for this session
                S.asking[id] = nil
                if a.tries + 1 >= ASK_TRIES then
                    S.gaveUp[id] = true
                else
                    S.queue[id] = { at = t + 5, tries = a.tries + 1 }
                end
            else
                active = active + 1
            end
        end
        if active >= ASK_MAX then return end
        local best, bestAt
        for id, q in pairs(S.queue) do
            if q.at <= t and (not bestAt or q.at < bestAt) then best, bestAt = id, q.at end
        end
        if not best then return end
        local q = S.queue[best]
        S.queue[best] = nil
        local p = peers[best]
        if done(p) or type(p.n) ~= "string" then return end
        local how = reach(p)
        local target
        if how == "CHANNEL" then target = channelNumber() elseif how then target = p.n end
        if not target then return end
        if how == "WHISPER" then recentWhisper[p.n] = t end
        if sendOne(V .. "R|" .. best .. "," .. b36(tonumber(p.h) or 0), how, target, nil, true) then
            S.asking[best] = { progress = t, tries = q.tries, way = how }
            lib.stats.asks = (lib.stats.asks or 0) + 1
        else
            S.queue[best] = { at = t + 30, tries = q.tries + 1 }
        end
    end

    ---------------------------------------------------------------- answering
    -- One answer every 2 seconds at most. Three or more players of the data
    -- channel waiting (or one whispers can't reach): one message on the channel
    -- serves them all, from the lowest number any of them needs (whoever has that
    -- part already passes it by on its header). The others (fewer, or not in the
    -- channel: guild members with the channel turned off): whispered in turn.
    local function serveTick(t)
        local s = D()
        if S.served >= SESSION_MAX then return end
        local chan = channelReady and lib.UsesChannel() and channelNumber()
        local onChannel, far, low = 0, false, nil
        for sender, q in pairs(S.serve) do
            if q.from > s.last or (q.channel and not chan) then
                S.serve[sender] = nil
            else
                q.onChan = chan and (q.channel or roster.inChannel[q.key]) and true or false
                if q.onChan then
                    onChannel = onChannel + 1
                    if q.channel then far = true end
                    if not low or q.from < low then low = q.from end
                end
            end
        end
        local shared = chan and (far or onChannel >= SHARED_FROM)
        if shared and t >= (S.chanNext or 0) then
            local msg, to, _, text = pack(low)
            if msg then
                local ok, why = sendOne(msg, "CHANNEL", chan, nil, true)
                if activity.sent and text ~= "" then pcall(activity.sent, "CHANNEL", nil, V .. "Y|" .. text, ok, why, 0) end
                if ok then
                    S.served = S.served + 1
                    lib.stats.sent = lib.stats.sent + 1
                    for _, q in pairs(S.serve) do
                        if q.onChan and q.from >= low and q.from <= to + 1 then q.from = to + 1 end
                    end
                    S.chanNext = t + SERVE_CHANNEL_GAP
                else
                    S.chanNext = t + 10
                end
                return
            end
        end
        local pick, pickKey
        for sender, q in pairs(S.serve) do
            if not q.channel and not (shared and q.onChan) and q.next <= t and (not pick or q.next < pick.next) then
                pick, pickKey = q, sender
            end
        end
        if not pick then return end
        -- one player is not sent more than three times this character's whole log
        -- a session (a client asking again and again over a lost message)
        if pick.sent >= 3 * (floor(L.count / 10) + 1) + 50 then
            S.serve[pickKey] = nil
            return
        end
        local msg, to, _, text = pack(pick.from)
        if not msg then
            S.serve[pickKey] = nil
            return
        end
        recentWhisper[pick.name] = t
        local ok, why = sendOne(msg, "WHISPER", pick.name, nil, true)
        if activity.sent and text ~= "" then
            pcall(activity.sent, "WHISPER", pick.name, V .. "Y|" .. text, ok, why, 0)
        end
        if ok then
            S.served = S.served + 1
            lib.stats.sent = lib.stats.sent + 1
            pick.sent = pick.sent + 1
            pick.from = to + 1
            pick.next = t + SERVE_GAP
            if not pick.counted then
                pick.counted = true
                whisperedCount = whisperedCount + 1
            end
            if pick.from > s.last then S.serve[pickKey] = nil end
        else
            pick.fails = (pick.fails or 0) + 1
            pick.next = t + 10
            if pick.fails >= 3 then S.serve[pickKey] = nil end
        end
    end

    -- every 2 seconds: one ask and one answer at most
    function lib.ServeTick()
        if not lib.IsEnabled() or not L.numbered then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
        local t = clock()
        askTick(t)
        serveTick(t)
    end

    ---------------------------------------------------------------- older copies
    -- the next old-form message of the sweep: kind by kind, the records numbered
    -- after <from> up to <upto>
    local function sweepMessage(sw)
        while sw.ki <= #sw.kinds do
            local kind = sw.kinds[sw.ki]
            local order, i = L.order, firstIndex(sw.pos + 1)
            local parts, size, head, done = {}, 0, nil, true
            -- records with names carry the client language: so does the mark, or an
            -- older copy counts it as a record in another language
            local localized = kind == "D" or kind == "O" or (lib.kinds[kind] and lib.kinds[kind].localized)
            local mark = localized and (";" .. locale() .. "," .. MARK:sub(2)) or MARK
            while i <= #order and order[i] <= sw.upto do
                local rec = L.recs[order[i]]
                if rec.kind == kind then
                    head = head or (rec.version .. kind .. "|")
                    if size + #rec.body + 1 > MAX_MSG - #head - #mark then
                        done = false
                        break
                    end
                    parts[#parts + 1] = rec.body
                    size = size + #rec.body + 1
                    sw.pos = order[i]
                end
                i = i + 1
            end
            if done then
                sw.ki, sw.pos = sw.ki + 1, sw.from
            end
            if #parts > 0 then return head .. concat(parts, ";") .. mark, kind, concat(parts, ";") end
        end
        return nil
    end

    -- older copies heard from lately: the records none of them had yet, once
    local function oldTick()
        local s = D()
        local t = clock()
        local start, ways = nil, {}
        for key, o in pairs(S.olds) do
            if t - o.at > OLD_AROUND then
                S.olds[key] = nil
            else
                local r = s.old[key]
                local from = type(r) == "table" and tonumber(r.s) or 0
                if type(r) == "table" and now() - (tonumber(r.at) or 0) > OLD_AGAIN then from = 0 end
                if not start or from < start then start = from end
                ways[o.way] = true
            end
        end
        if not start then
            S.sweep = nil
            return nil
        end
        local sw = S.sweep
        if not sw then
            if start >= s.last then return nil end
            sw = { from = start, upto = s.last, kinds = kindOrder(), ki = 1, pos = start, ways = ways, keys = {} }
            for key in pairs(S.olds) do sw.keys[key] = true end
            S.sweep = sw
        end
        local msg, kind, text = sweepMessage(sw)
        if msg then return msg, sw.ways, kind, text end
        -- done: everyone around then has these now
        for key in pairs(sw.keys) do
            local r = s.old[key]
            if type(r) == "table" then
                -- a whole sweep (from the start) starts the wait for the next one
                if sw.from == 0 then r.s, r.at = sw.upto, now() else r.s = max(tonumber(r.s) or 0, sw.upto) end
            end
        end
        S.sweep = nil
        return nil
    end

    ---------------------------------------------------------------- every 8 seconds
    -- where messages for everyone go: the data channel, the guild, the party or raid
    local function waysNow(useChannel)
        local list = {}
        local chan = useChannel and channelNumber()
        if chan then list[#list + 1] = { "CHANNEL", chan } end
        for _, w in ipairs(targets()) do list[#list + 1] = { w[1] } end
        return list
    end

    -- one kind of message a tick: the hello, then records found now, then the
    -- sweep for older copies
    sendTick = function()
        if not lib.IsEnabled() then return "off" end
        if InCombatLockdown and InCombatLockdown() then return "combat" end
        if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "no api" end
        local useChannel = channelReady and lib.UsesChannel()
        if useChannel and clock() - (roster.asked or 0) >= ROSTER_EVERY then requestRoster() end
        sync.number()
        sync.check()
        local t = clock()
        S.helloAt = S.helloAt or (t + HELLO_FIRST)
        local list = waysNow(useChannel)
        if #list == 0 then return "no target" end
        local all = t >= S.helloAt
        if all or (S.groupHelloAt and t >= S.groupHelloAt) then
            local msg = helloText()
            for _, w in ipairs(list) do
                if all or w[1] == "PARTY" or w[1] == "RAID" then sendOne(msg, w[1], w[2], nil, true) end
            end
            if all then S.helloAt = t + HELLO_EVERY end
            S.groupHelloAt = nil
            lib.stats.sentHellos = (lib.stats.sentHellos or 0) + 1
            return "hello"
        end
        local msg, to, n, text = pack(L.fresh)
        if msg then
            L.fresh = to + 1
            if n > 0 then
                local okAny
                for _, w in ipairs(list) do
                    local ok, why = sendOne(msg, w[1], w[2], nil, true)
                    if activity.sent then pcall(activity.sent, w[1], nil, V .. "Y|" .. text, ok, why, n) end
                    if ok then okAny = true end
                end
                if okAny then lib.stats.sent = lib.stats.sent + 1 end
                return okAny and "new sent" or "new failed"
            end
        end
        local old, oldWays, kind, oldText = oldTick()
        if old then
            for _, w in ipairs(list) do
                if oldWays[w[1]] then
                    local ok, why = sendOne(old, w[1], w[2], nil, true)
                    if activity.sent then pcall(activity.sent, w[1], nil, "2" .. kind .. "|" .. oldText, ok, why, 0) end
                end
            end
            lib.stats.sent = lib.stats.sent + 1
            return "old sent"
        end
        return "nothing new"
    end

    ---------------------------------------------------------------- status
    function lib.SyncStatus(short)
        local s = D()
        local peers, done = 0, 0
        for _, p in pairs(s.peers) do
            if type(p) == "table" then
                peers = peers + 1
                if (tonumber(p.h) or 0) >= (tonumber(p.l) or 0) then done = done + 1 end
            end
        end
        local asking, waiting, serving = 0, 0, 0
        for _ in pairs(S.asking) do asking = asking + 1 end
        for _ in pairs(S.queue) do waiting = waiting + 1 end
        for _ in pairs(S.serve) do serving = serving + 1 end
        if short then return format(T("syncShort"), asking, waiting, serving) end
        return format(T("syncLine"), L.count or 0, s.last, peers, done, asking, waiting, serving)
    end

    -- a log's progress for a player (by base name): have, their last
    function lib.SyncProgress(key)
        for _, p in pairs(D().peers) do
            if type(p) == "table" and baseName(p.n) == key then return tonumber(p.h) or 0, tonumber(p.l) or 0 end
        end
        return nil
    end
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
            if activity.notFound then pcall(activity.notFound, name) end
            if lib.SyncNotFound then pcall(lib.SyncNotFound, name) end
            if key then
                local n = (unreachableCount[key] or 0) + 1
                unreachableCount[key] = n
                unreachable[key] = clock() + UNREACHABLE_FOR[math.min(n, #UNREACHABLE_FOR)]
                -- still on the channel's list: a whisper from them is taken
                -- (and shows they can be whispered again)
                if roster.inChannel[key] then roster.left[key] = "away" end
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
        if lib.SyncChannelReady then lib.SyncChannelReady() end
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
        if lib.SyncChannelReady then lib.SyncChannelReady() end
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
    -- the players of the list who are not whispered, by why
    local left, t = { server = 0, faction = 0, away = 0, noname = 0 }, clock()
    for key, why in pairs(roster.left) do
        if left[why] and (why ~= "away" or (unreachable[key] or 0) > t) then left[why] = left[why] + 1 end
    end
    return format(T("roster"), #roster.list, tostring(roster.raw or "-"), tostring(roster.channelCount or "-"),
        tostring(roster.display or "-"), age, whisperedCount) .. " " .. format(T("unknownFaction"), unknown)
        .. " " .. format(T("rosterLeft"), left.server, left.faction, left.away, left.noname)
end

function lib.Slash(msg)
    local raw = type(msg) == "string" and msg:gsub("^%s+", ""):gsub("%s+$", "") or ""
    msg = raw:lower()
    if (msg == "" or msg == "window" or msg == "창") and lib.ToggleWindow then
        lib.ToggleWindow()
    elseif msg == "ping" or msg:find("^ping%s") then
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
        if lib.SyncStatus then say(lib.SyncStatus()) end
        -- the sharing versions of the players heard from this session
        local byVer = {}
        for _, p in pairs(activity.data().people) do
            if type(p) == "table" and p.ver and (tonumber(p.verAt) or 0) >= lib.sessionStart then
                byVer[p.ver] = (byVer[p.ver] or 0) + 1
            end
        end
        parts = {}
        for ver, n in pairs(byVer) do parts[#parts + 1] = (ver == "12" and T("verOld") or ("v" .. ver)) .. " " .. n end
        table.sort(parts)
        say(format(T("versions"), #parts > 0 and concat(parts, ", ") or "-"))
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
-- The window (/ezshare): what came in from whom, what went out, by kind.
-- Made the first time it is opened; refreshed every second while shown.
-----------------------------------------------------------------------------
do
local function setupWindow()
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
    local W, H, PAD = 800, 494, 12
    local LIST_W = W - PAD * 2 - 14
    local ROW_H, ROWS, HEAD_H = 17, 18, 18
    local GAP, MAX_COLS, MAX_TIP = 8, 9, 15
    local ACCENT = { 0.29, 0.78, 0.91 }
    local BG, PANEL = { 0.071, 0.094, 0.122, 0.96 }, { 0.047, 0.067, 0.086, 0.92 }
    local BTN, BTN_ON = { 0.114, 0.157, 0.192, 1 }, { 0.12, 0.30, 0.37, 1 }
    local BORDER, BORDER_ON = { 0.204, 0.298, 0.357, 1 }, { 0.29, 0.78, 0.91, 1 }
    local MUTED, BODY = { 0.65, 0.72, 0.77 }, { 0.93, 0.96, 0.97 }
    local KIND_ORDER = { "S", "E", "Q", "V", "I", "D", "O", "L", "M", "P", "Z", "N", "X", "R", "G", "F", "T", "B", "W", "U", "J", "Y" }
    local TABS = { "recv", "people", "sent", "kinds" }
    local TAB_TITLES = { recv = "tabRecv", people = "tabPeople", sent = "tabSent", kinds = "tabKinds" }
    local WAYS = { CHANNEL = "wayChannel", WHISPER = "wayWhisper", GUILD = "wayGuild", PARTY = "wayParty",
        RAID = "wayRaid", INSTANCE_CHAT = "wayInstance" }
    -- why a player of the channel's list is not whispered ("away" shows as stateAway)
    local LEFT_STATES = { server = "stateServer", faction = "stateFaction", noname = "stateNoName" }
    -- columns: title text key, width (the last one takes the rest), right-aligned
    -- ("news" is the received tab showing only the messages that brought something new)
    local COLS = {
        recv = { { t = "colTime", w = 64 }, { t = "colFrom", w = 140 }, { t = "colWay", w = 50 },
            { t = "colKind", w = 124 }, { t = "colRecords", w = 40, right = true },
            { t = "colNew", w = 52, right = true }, { t = "colWait", w = 60, right = true },
            { t = "colKnown", w = 60, right = true }, { t = "colNote" } },
        news = { { t = "colTime", w = 64 }, { t = "colFrom", w = 140 }, { t = "colWay", w = 50 },
            { t = "colKind", w = 124 }, { t = "colNew", w = 52, right = true }, { t = "colContent" } },
        people = { { t = "colName", w = 140 }, { t = "colVersion", w = 56 }, { t = "colWays", w = 100 }, { t = "colMsgs", w = 54, right = true },
            { t = "colRecords", w = 54, right = true }, { t = "colNew", w = 52, right = true },
            { t = "colWhispered", w = 70, right = true }, { t = "colLast", w = 52, right = true }, { t = "colState" } },
        sent = { { t = "colTime", w = 64 }, { t = "colTo", w = 220 }, { t = "colKind", w = 130 },
            { t = "colRecords", w = 44, right = true }, { t = "colFresh", w = 76, right = true }, { t = "colResult" } },
        kinds = { { t = "colKind", w = 180 }, { t = "colReceived", w = 90, right = true },
            { t = "colNew", w = 90, right = true }, { t = "colWait", w = 90, right = true },
            { t = "colSentRecs", w = 90, right = true }, { t = "colOwn", w = 90, right = true } },
    }

    local ui = { tab = "recv", offset = 0, newOnly = false }
    local refresh

    -- what the list shows: the tab, or "news" for the received tab's new-only view
    local function view()
        if ui.tab == "recv" and ui.newOnly then return "news" end
        return ui.tab
    end

    ---------------------------------------------------------------- texts
    local function kindName(code)
        if type(code) ~= "string" then return "?" end
        local key = "kind" .. code
        local text = T(key)
        return text ~= key and text or code
    end

    local function wayName(way)
        local key = WAYS[way]
        return key and T(key) or tostring(way or "?")
    end

    local function timeText(t)
        t = tonumber(t)
        if not t or type(date) ~= "function" then return "" end
        if date("%Y%m%d", t) == date("%Y%m%d") then return date("%H:%M:%S", t) end
        return date("%m-%d %H:%M", t)
    end

    local function countText(n, green)
        n = tonumber(n) or 0
        if green and n > 0 then return "|cff7fe07f" .. n .. "|r" end
        return tostring(n)
    end

    local function plain(v)
        if type(v) ~= "string" or isSecret(v) or v == "" then return nil end
        return v
    end

    local function itemName(id)
        id = tonumber(id) or 0
        if C_Item and C_Item.GetItemNameByID then
            local ok, n = pcall(C_Item.GetItemNameByID, id)
            if ok and plain(n) then return n end
            if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        end
        return format(T("itemN"), id)
    end

    local function questName(id)
        id = tonumber(id) or 0
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local ok, n = pcall(C_QuestLog.GetTitleForQuestID, id)
            if ok and plain(n) then return n end
        end
        return format(T("questN"), id)
    end

    local function sourceName(src)
        local ok, n = pcall(lib.SourceName, src)
        if ok and plain(n) then return n end
        local id = tonumber(tostring(src):sub(2)) or 0
        return format(tostring(src):sub(1, 1) == "o" and T("objectN") or T("npcN"), id)
    end

    local function mapName(id)
        id = tonumber(id) or 0
        if C_Map and C_Map.GetMapInfo then
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if ok and type(info) == "table" and plain(info.name) then return info.name end
        end
        return format(T("mapN"), id)
    end

    local function zoneName(id)
        id = tonumber(id) or 0
        if type(GetRealZoneText) == "function" then
            local ok, n = pcall(GetRealZoneText, id)
            if ok and plain(n) then return n end
        end
        return format(T("mapN"), id)
    end

    -- the zone a world position ("continent,x,y") lies in, asked once per spot:
    -- the spot on the continent's map, the map the game shows there, up to its
    -- zone; elsewhere (no continent map) the instance's name
    local CONTINENT_MAPS = { [0] = 1415, [1] = 1414, [530] = 1945, [571] = 113 }
    local ZONE_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local spotZones, spotZoneCount = {}, 0

    local function zoneAt(cont, x, y)
        local contMap = CONTINENT_MAPS[cont]
        if not (contMap and C_Map and C_Map.GetMapPosFromWorldPos and C_Map.GetMapInfoAtPosition
            and C_Map.GetMapInfo and CreateVector2D) then return nil end
        local ok, onMap, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(x, y), contMap)
        if not ok or (onMap ~= nil and onMap ~= contMap) or type(pos) ~= "table" then return nil end
        local px, py = pos.x, pos.y
        if type(px) ~= "number" and type(pos.GetXY) == "function" then
            local okXY, a, b = pcall(pos.GetXY, pos)
            if okXY then px, py = a, b end
        end
        if type(px) ~= "number" or type(py) ~= "number" or isSecret(px) or isSecret(py)
            or px < 0 or px > 1 or py < 0 or py > 1 then return nil end
        local okAt, info = pcall(C_Map.GetMapInfoAtPosition, contMap, px, py)
        -- a town or cave map at that spot: up to the zone it is in
        for _ = 1, 4 do
            if not okAt or type(info) ~= "table" or info.mapID == contMap then return nil end
            local kind = tonumber(info.mapType) or ZONE_TYPE
            if kind == ZONE_TYPE or info.parentMapID == contMap then return plain(info.name) end
            if kind < ZONE_TYPE or type(info.parentMapID) ~= "number" then return nil end
            okAt, info = pcall(C_Map.GetMapInfo, info.parentMapID)
        end
        return nil
    end

    local function spotZone(c, x, y)
        local key = tostring(c) .. "," .. tostring(x) .. "," .. tostring(y)
        local hit = spotZones[key]
        if hit ~= nil then return hit or nil end
        c, x, y = tonumber(c), tonumber(x), tonumber(y)
        local name
        if c and x and y then
            local ok, zone = pcall(zoneAt, c, x, y)
            name = ok and zone or nil
            if not name and not CONTINENT_MAPS[c] and type(GetRealZoneText) == "function" then
                local okZone, n = pcall(GetRealZoneText, c)
                if okZone then name = plain(n) end
            end
        end
        if spotZoneCount >= 2000 then spotZones, spotZoneCount = {}, 0 end
        spotZones[key] = name or false
        spotZoneCount = spotZoneCount + 1
        return name
    end

    -- "what · zone" when the zone is known
    local function withZone(text, c, x, y)
        local zone = spotZone(c, x, y)
        return zone and format(T("descIn"), text, zone) or text
    end

    -- one record of a message as text (the message formats are above)
    local function describe(kind, body)
        -- a numbered record: "1E<body>"
        if kind == "Y" then
            local k, rest = body:match("^%d(%u)(.+)$")
            if k then return describe(k, rest) end
            return body
        end
        -- a kind another addon registered may describe its own records
        local spec = lib.kinds[kind]
        if spec and type(spec.describe) == "function" then
            local ok, text = pcall(spec.describe, body)
            if ok and type(text) == "string" and text ~= "" then return text end
        end
        local _, rest = body:match("^(%a%a%u%u),(.+)$")
        if rest then body = rest end
        if kind == "E" or kind == "S" then
            local q, k, id = body:match("^(%d+),([no]),(%d+)")
            if q then return format(T(kind == "E" and "descEnd" or "descStart"), questName(q), sourceName(k .. id)) end
        elseif kind == "Q" then
            local npc, q = body:match("^(%d+),(%d+),")
            if npc then return format(T("descStart"), questName(q), sourceName("n" .. npc)) end
        elseif kind == "V" then
            local q, index = body:match("^(%d+),(%d+),")
            if q then return format(T("descSpot"), questName(q), tonumber(index) or 0) end
        elseif kind == "I" then
            local item, k, id = body:match("^(%d+),([no]),(%d+)")
            if item then return format(T("descFrom"), itemName(item), sourceName(k .. id)) end
        elseif kind == "D" then
            local id, name = body:match("^(%d+),(.+)$")
            if id then return format(T("descFrom"), name, sourceName("n" .. id)) end
        elseif kind == "O" then
            local id, name = body:match("^(%d+),[^,]*,[^,]*,[^,]*,(.+)$")
            if id then return format(T("descFrom"), name, sourceName("o" .. id)) end
        elseif kind == "L" then
            local src, item = body:match("^([no]%d+),(%d+)$")
            if src then return format(T("descFrom"), itemName(item), sourceName(src)) end
        elseif kind == "G" then
            local id, c, x, y = body:match("^(%d+),(%d+),(%-?[%d%.]+),(%-?[%d%.]+)$")
            if id then return withZone(sourceName("o" .. id), c, x, y) end
            id = body:match("^(%d+),")
            if id then return sourceName("o" .. id) end
        elseif kind == "R" then
            local npc, map, age = body:match("^(%d+),(%d+),[^,]*,[^,]*,(%d+)$")
            if npc then return format(T("descRare"), sourceName("n" .. npc), mapName(map), ago(now() - tonumber(age))) end
        elseif kind == "M" then
            local npc, items = body:match("^(%d+),(.+)$")
            if npc then
                local n = 0
                for _ in items:gmatch("[^%.]+") do n = n + 1 end
                return format(T("descShop"), sourceName("n" .. npc), n)
            end
        elseif kind == "Z" then
            local npc, map = body:match("^(%d+),(%d+)$")
            if npc then return format(T("descIn"), sourceName("n" .. npc), zoneName(map)) end
        elseif kind == "N" then
            local npc, c, x, y, flags = body:match("^(%d+),([^,]*),([^,]*),([^,]*),?(%d*)$")
            if npc then
                local name = sourceName("n" .. npc)
                if flags == "0" then name = format(T("descMob"), name) end
                return withZone(name, c, x, y)
            end
        elseif kind == "F" then
            local map, item, count = body:match("^(%d+),%d+,%d+,(%d+),(%d+)$")
            if map then return format(T("descFish"), mapName(map), itemName(item), tonumber(count) or 0) end
        elseif kind == "T" then
            local secs, route = body:match("^(%d+),(.+)$")
            if secs then
                secs = tonumber(secs) or 0
                return format(T("descFlight"), (route:gsub("~", " > ")), floor(secs / 60), secs % 60)
            end
        elseif kind == "B" then
            local npc, area = body:match("^(%d+),%d+,%d+,(.+)$")
            if npc then return format(T("descIn"), sourceName("n" .. npc), area) end
        elseif kind == "W" then
            local q, r, c = body:match("^(%d+),([%w%.]*),([%w%.]*)$")
            if q then
                local function count(list)
                    local n = 0
                    for _ in list:gmatch("[^%.]+") do n = n + 1 end
                    return n
                end
                return format(T("descRewards"), questName(q), count(r), count(c))
            end
        elseif kind == "U" then
            local npc, list = body:match("^(%d+),([%w%.]+)$")
            if npc then
                local n = 0
                for _ in list:gmatch("[^%.]+") do n = n + 1 end
                return format(T("descTeaches"), sourceName("n" .. npc), n)
            end
        elseif kind == "J" then
            local id, name = body:match("^(%d+),(.+)$")
            if id then return format(T("descIn"), format(T("objectN"), tonumber(id) or 0), name) end
        end
        return body
    end

    ---------------------------------------------------------------- tooltips
    local function addRecords(tip, kind, payload)
        if type(payload) ~= "string" then
            tip:AddLine(format(T("tipNoDetail"), activity.BODY_KEEP or 60), MUTED[1], MUTED[2], MUTED[3], true)
            return
        end
        local listed, total = 0, 0
        for body in payload:gmatch("[^;]+") do
            total = total + 1
            if listed < MAX_TIP then
                listed = listed + 1
                local ok, text = pcall(describe, kind, body)
                tip:AddLine(ok and tostring(text) or body, BODY[1], BODY[2], BODY[3])
            end
        end
        if total > listed then tip:AddLine(format(T("moreRecords"), total - listed), MUTED[1], MUTED[2], MUTED[3]) end
    end

    -- records already had (older entries have no count of their own)
    local function knownOf(e)
        if e.known then return tonumber(e.known) or 0 end
        return max(0, (tonumber(e.n) or 0) - (tonumber(e.new) or 0) - (tonumber(e.wait) or 0) - (tonumber(e.lang) or 0))
    end

    local tips = {}
    function tips.recv(tip, e)
        tip:AddLine(format("%s · %s · %s", tostring(e.who or "?"), wayName(e.way), kindName(e.k)),
            ACCENT[1], ACCENT[2], ACCENT[3])
        tip:AddLine(timeText(e.t), MUTED[1], MUTED[2], MUTED[3])
        tip:AddLine(format(T("tipCounts"), tonumber(e.new) or 0, tonumber(e.wait) or 0, knownOf(e)),
            MUTED[1], MUTED[2], MUTED[3])
        addRecords(tip, e.k, e.p)
    end
    function tips.news(tip, e)
        tip:AddLine(format("%s · %s · %s", tostring(e.who or "?"), wayName(e.way), kindName(e.k)),
            ACCENT[1], ACCENT[2], ACCENT[3])
        tip:AddLine(timeText(e.t), MUTED[1], MUTED[2], MUTED[3])
        addRecords(tip, e.k, e.p)
    end
    function tips.sent(tip, e)
        local to = wayName(e.way) .. (e.to and (": " .. tostring(e.to)) or "")
        tip:AddLine(format("%s · %s", to, kindName(e.k)), ACCENT[1], ACCENT[2], ACCENT[3])
        tip:AddLine(timeText(e.t), MUTED[1], MUTED[2], MUTED[3])
        if (tonumber(e.fresh) or 0) > 0 then
            tip:AddLine(format(T("tipFresh"), tonumber(e.fresh)), 0.5, 0.88, 0.5)
        end
        addRecords(tip, e.k, e.p)
    end
    function tips.people(tip, p)
        tip:AddLine(tostring(p.name or "?"), ACCENT[1], ACCENT[2], ACCENT[3])
        if p.ver then
            tip:AddLine(format(T("tipVersion"), p.ver == "12" and T("verOld") or ("v" .. tostring(p.ver))), BODY[1], BODY[2], BODY[3])
        end
        if type(p.addons) == "string" and p.addons ~= "" then
            -- "MF2.0.30" -> "MapFinder 2.0.30"
            local names = {}
            for code, folder in pairs(sync.CODES or {}) do names[folder] = code end
            local list = {}
            for part in p.addons:gmatch("[^,]+") do
                local code, v = part:match("^(%u%u)(.+)$")
                list[#list + 1] = code and ((names[code] or code) .. " " .. v) or part
            end
            tip:AddLine(format(T("tipAddons"), concat(list, ", ")), MUTED[1], MUTED[2], MUTED[3], true)
        end
        local have, last = nil, nil
        if lib.SyncProgress then have, last = lib.SyncProgress(baseName(p.name)) end
        if have then tip:AddLine(format(T("tipTaken"), have, last), MUTED[1], MUTED[2], MUTED[3]) end
        if p.recs then
            tip:AddLine(format(T("tipCounts"), tonumber(p.new) or 0, tonumber(p.wait) or 0, tonumber(p.known) or 0),
                MUTED[1], MUTED[2], MUTED[3])
        end
        for way, n in pairs(type(p.ways) == "table" and p.ways or {}) do
            tip:AddLine(format(T("tipWay"), wayName(way), tonumber(n) or 0), BODY[1], BODY[2], BODY[3])
        end
        local kinds = {}
        for k, n in pairs(type(p.kinds) == "table" and p.kinds or {}) do kinds[#kinds + 1] = { k, tonumber(n) or 0 } end
        table.sort(kinds, function(a, b) return a[2] > b[2] end)
        for _, kv in ipairs(kinds) do
            tip:AddLine(format(T("tipKind"), kindName(kv[1]), kv[2]), BODY[1], BODY[2], BODY[3])
        end
        if p.first then tip:AddLine(format(T("tipFirst"), timeText(p.first)), MUTED[1], MUTED[2], MUTED[3]) end
    end

    ---------------------------------------------------------------- rows
    local builders = {}

    function builders.recv()
        local out = {}
        local list = activity.data().recv
        for i = #list, 1, -1 do
            local e = list[i]
            if type(e) == "table" then
                local notes = {}
                if (tonumber(e.lang) or 0) > 0 then notes[#notes + 1] = format(T("noteLang"), e.lang) end
                if e.cut then notes[#notes + 1] = T("noteLimit") end
                out[#out + 1] = {
                    cells = { timeText(e.t), tostring(e.who or "?"), wayName(e.way), kindName(e.k), countText(e.n),
                        countText(e.new, true), countText(e.wait), countText(knownOf(e)), concat(notes, ", ") },
                    dim = (tonumber(e.t) or 0) < lib.sessionStart,
                    entry = e,
                }
            end
        end
        return out
    end

    -- the first new record as text, worked out only for the rows on screen
    local function firstRecord(e)
        return function()
            local body = type(e.p) == "string" and e.p:match("^[^;]+")
            if not body then return "" end
            local ok, text = pcall(describe, e.k, body)
            text = ok and tostring(text) or body
            local n = tonumber(e.n) or 1
            if n > 1 then text = text .. "  " .. format(T("moreRecords"), n - 1) end
            return text
        end
    end

    function builders.news()
        local out = {}
        local list = activity.data().news
        for i = #list, 1, -1 do
            local e = list[i]
            if type(e) == "table" then
                out[#out + 1] = {
                    cells = { timeText(e.t), tostring(e.who or "?"), wayName(e.way), kindName(e.k),
                        countText(e.n, true), firstRecord(e) },
                    dim = (tonumber(e.t) or 0) < lib.sessionStart,
                    entry = e,
                }
            end
        end
        return out
    end

    function builders.people()
        local log = activity.data()
        local out, seen = {}, {}
        local t = clock()
        local function add(key, p, m)
            local ways = {}
            for way in pairs(type(p.ways) == "table" and p.ways or {}) do ways[#ways + 1] = wayName(way) end
            table.sort(ways)
            local state = {}
            if m then state[#state + 1] = T("stateListed") end
            if m and m.unknown then state[#state + 1] = T("stateUnknown") end
            -- on the channel's list but not whispered (whispers from them are taken)
            local why = not m and LEFT_STATES[roster.left[key] or ""]
            if why then state[#state + 1] = T(why) end
            if (unreachable[key] or 0) > t then state[#state + 1] = T("stateAway") end
            if (tonumber(p.notFound) or 0) > 0 then state[#state + 1] = format(T("stateNotFound"), p.notFound) end
            if (tonumber(p.held) or 0) > 0 then state[#state + 1] = format(T("stateHeld"), p.held) end
            local last = max(tonumber(p.last) or 0, tonumber(p.whisperedAt) or 0)
            local name = tostring(p.name or (m and m.name) or key)
            local ver = p.ver and (p.ver == "12" and T("verOld") or ("v" .. tostring(p.ver))) or "-"
            out[#out + 1] = {
                cells = { name, ver, concat(ways, ", "), countText(p.msgs), countText(p.recs), countText(p.new, true),
                    countText(p.whispered), last > 0 and ago(last, true) or "-", concat(state, ", ") },
                dim = not m and last < lib.sessionStart,
                entry = p.name and p or { name = name },
                heard = tonumber(p.last) or 0, at = last, name = name,
            }
        end
        for key, p in pairs(log.people) do
            if type(p) == "table" then
                seen[key] = true
                add(key, p, roster.byKey[key])
            end
        end
        for key, m in pairs(roster.byKey) do
            if not seen[key] then add(key, {}, m) end
        end
        -- heard from lately first, then whispered lately, then by name
        table.sort(out, function(a, b)
            if a.heard ~= b.heard then return a.heard > b.heard end
            if a.at ~= b.at then return a.at > b.at end
            return a.name < b.name
        end)
        return out
    end

    function builders.sent()
        local out = {}
        local list = activity.data().sent
        for i = #list, 1, -1 do
            local e = list[i]
            if type(e) == "table" then
                local to = wayName(e.way) .. (e.to and (": " .. tostring(e.to)) or "")
                out[#out + 1] = {
                    cells = { timeText(e.t), to, kindName(e.k), countText(e.n), countText(e.fresh, true),
                        e.fail and ("|cffff8080" .. format(T("resultFail"), tostring(e.fail)) .. "|r") or T("resultOk") },
                    dim = (tonumber(e.t) or 0) < lib.sessionStart,
                    entry = e,
                }
            end
        end
        return out
    end

    -- this character's own records by kind (counted again every 15 seconds)
    local ownCache, ownAt = nil, -100
    local function ownCounts()
        if ownCache and clock() - ownAt < 15 then return ownCache end
        local counts = {}
        local ok, recs = pcall(collect)
        if ok and type(recs) == "table" then
            for _, r in ipairs(recs) do
                if type(r) == "table" and r.kind then counts[r.kind] = (counts[r.kind] or 0) + 1 end
            end
        end
        ownCache, ownAt = counts, clock()
        return counts
    end

    function builders.kinds()
        local log = activity.data()
        local own = ownCounts()
        local codes, seen = {}, {}
        local function addCode(c)
            if type(c) == "string" and not seen[c] then
                seen[c] = true
                codes[#codes + 1] = c
            end
        end
        for _, c in ipairs(KIND_ORDER) do addCode(c) end
        for c in pairs(log.kinds) do addCode(c) end
        for c in pairs(own) do addCode(c) end
        local out = {}
        for _, c in ipairs(codes) do
            local k = type(log.kinds[c]) == "table" and log.kinds[c] or {}
            local r, u, s, o = tonumber(k.r) or 0, tonumber(k.u) or 0, tonumber(k.s) or 0, own[c] or 0
            out[#out + 1] = {
                cells = { kindName(c), countText(r), countText(u, true), countText(k.w), countText(s), countText(o) },
                dim = r + s + o == 0,
            }
        end
        return out
    end

    -- the three lines at the top
    local function summary()
        local s = lib.stats
        local l1
        if not lib.IsEnabled() then
            l1 = T("sumOff")
        else
            local parts = { T("sumOn") }
            if not lib.UsesChannel() then
                parts[#parts + 1] = T("sumNoChannel")
            else
                local num = channelReady and channelNumber()
                if num then
                    parts[#parts + 1] = format(T("sumChannel"), num,
                        tostring(roster.channelCount or roster.raw or "-"), #roster.list)
                else
                    parts[#parts + 1] = T("sumChannelWait")
                end
            end
            if IsInGuild and IsInGuild() then parts[#parts + 1] = T("wayGuild") end
            l1 = concat(parts, " · ")
        end
        local ways = {}
        for way, n in pairs(s.sentWays or {}) do ways[#ways + 1] = wayName(way) .. " " .. n end
        table.sort(ways)
        local l2 = format(T("sumSession"), s.received or 0, s.players or 0, s.used or 0, s.waiting or 0, s.sent or 0,
            #ways > 0 and concat(ways, ", ") or "-")
        local res = {}
        for way, r in pairs(s.results or {}) do
            local done = r == "0" or r == "true" or r == "nil"
            res[#res + 1] = wayName(way) .. " " .. (done and T("resultOk") or format(T("resultFail"), tostring(r)))
        end
        table.sort(res)
        local last = #res > 0 and concat(res, ", ") or "-"
        local note = tostring(s.note or "")
        if note ~= "" and not note:find("sent", 1, true) and not note:find("nothing new", 1, true)
            and note ~= "hello" then
            last = last .. " (" .. note .. ")"
        end
        if lib.SyncStatus then
            local ok, text = pcall(lib.SyncStatus, true)
            if ok and text then last = last .. " · " .. text end
        end
        return l1, l2, format(T("sumLast"), last)
    end

    ---------------------------------------------------------------- drawing
    local function tint(frame, bg, border)
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end

    local function paint(frame, bg, border)
        frame:SetBackdrop(BACKDROP)
        tint(frame, bg, border)
    end

    local function showTip(row)
        local item = row.item
        local fn = tips[view()]
        ui.tipRow = row
        ui.tipEntry = item and item.entry
        if not (item and item.entry and fn) then
            if GameTooltip:GetOwner() == row then GameTooltip:Hide() end
            return
        end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        pcall(fn, GameTooltip, item.entry)
        GameTooltip:Show()
    end

    local function hideTip(row)
        if GameTooltip:GetOwner() == row then GameTooltip:Hide() end
        ui.tipRow, ui.tipEntry = nil, nil
    end

    local function place(fs, spec, x)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", fs:GetParent(), "LEFT", x, 0)
        fs:SetWidth(spec.w or max(20, LIST_W - 10 - x))
        fs:SetJustifyH(spec.right and "RIGHT" or "LEFT")
    end

    local function layout()
        local v = view()
        if ui.laidOut == v then return end
        ui.laidOut = v
        local cols = COLS[v]
        local x = 8
        for c = 1, MAX_COLS do
            local spec = cols[c]
            if spec then
                place(ui.header[c], spec, x)
                ui.header[c]:Show()
                for i = 1, ROWS do
                    place(ui.rows[i].cells[c], spec, x)
                    ui.rows[i].cells[c]:Show()
                end
                x = x + (spec.w or 0) + GAP
            else
                ui.header[c]:Hide()
                for i = 1, ROWS do ui.rows[i].cells[c]:Hide() end
            end
        end
    end

    local function draw()
        local data = ui.data or {}
        local cols = COLS[view()]
        for c = 1, #cols do ui.header[c]:SetText(T(cols[c].t)) end
        for i = 1, ROWS do
            local row = ui.rows[i]
            local item = data[ui.offset + i]
            row.item = item
            if item then
                local shade = item.dim and 0.55 or 0.93
                for c = 1, #cols do
                    local fs = row.cells[c]
                    local text = item.cells[c]
                    -- a function: text worked out only when the row is on screen
                    if type(text) == "function" then
                        local ok, value = pcall(text)
                        text = ok and value or ""
                    end
                    fs:SetText(tostring(text or ""))
                    fs:SetTextColor(shade, shade, shade)
                end
                row:Show()
            else
                row:Hide()
            end
        end
        ui.empty:SetText(#data == 0 and T("emptyList") or "")
        ui.range:SetText(format("%d-%d / %d", #data > 0 and ui.offset + 1 or 0, min(#data, ui.offset + ROWS), #data))
        -- the row under the mouse shows another entry now: its tooltip follows
        local row = ui.tipRow
        if row and GameTooltip:GetOwner() == row and (row.item and row.item.entry) ~= ui.tipEntry then showTip(row) end
    end

    refresh = function()
        local f = ui.frame
        if not (f and f:IsShown()) then return end
        layout()
        ui.title:SetText(T("winTitle"))
        local ok, l1, l2, l3 = pcall(summary)
        if ok then
            ui.lines[1]:SetText(l1)
            ui.lines[2]:SetText(l2)
            ui.lines[3]:SetText(l3)
        end
        for _, b in ipairs(ui.tabs) do
            b.text:SetText(T(TAB_TITLES[b.key]))
            if b.key == ui.tab then tint(b, BTN_ON, BORDER_ON) else tint(b, BTN, BORDER) end
        end
        ui.shareBtn.text:SetText(lib.IsEnabled() and T("btnShareOn") or T("btnShareOff"))
        ui.channelBtn.text:SetText(settings().noChannel and T("btnChannelOff") or T("btnChannelOn"))
        ui.clearBtn.text:SetText(T("btnClear"))
        ui.viewBtn.text:SetText(ui.newOnly and T("btnViewNew") or T("btnViewAll"))
        if ui.tab == "recv" then ui.viewBtn:Show() else ui.viewBtn:Hide() end
        ui.since:SetText(format(T("logSince"), timeText(activity.data().since)))
        local okRows, rows = pcall(builders[view()])
        ui.data = okRows and type(rows) == "table" and rows or {}
        local maxOffset = max(0, #ui.data - ROWS)
        if ui.offset > maxOffset then ui.offset = maxOffset end
        ui.bar:SetMinMaxValues(0, maxOffset)
        ui.bar:SetValue(ui.offset)
        draw()
    end

    ---------------------------------------------------------------- frame
    local function makeButton(parent, w, h, onClick)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(w, h)
        paint(b, BTN, BORDER)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER")
        b.text = fs
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b:SetScript("OnClick", onClick)
        return b
    end

    local function build()
        local f = CreateFrame("Frame", "EzWoWShareWindow", UIParent, "BackdropTemplate")
        f:Hide()
        ui.frame = f
        f:SetSize(W, H)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        paint(f, BG, BORDER)
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "EzWoWShareWindow") end

        ui.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        ui.title:SetPoint("TOPLEFT", PAD, -10)
        ui.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 1, 1)
        close:SetScript("OnClick", function() f:Hide() end)

        ui.lines = {}
        for i = 1, 3 do
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", PAD, -36 - (i - 1) * 16)
            fs:SetWidth(W - PAD * 2)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            ui.lines[i] = fs
        end

        ui.tabs = {}
        for i, key in ipairs(TABS) do
            local b = makeButton(f, 124, 22, function()
                ui.tab = key
                ui.offset = 0
                refresh()
            end)
            b:SetPoint("TOPLEFT", PAD + (i - 1) * 128, -88)
            b.key = key
            ui.tabs[i] = b
        end
        -- the received tab: every message, or only those that brought something new
        ui.viewBtn = makeButton(f, 150, 22, function()
            ui.newOnly = not ui.newOnly
            ui.offset = 0
            refresh()
        end)
        ui.viewBtn:SetPoint("TOPRIGHT", -(PAD + 14), -88)

        local list = CreateFrame("Frame", nil, f, "BackdropTemplate")
        list:SetPoint("TOPLEFT", PAD, -118)
        list:SetSize(LIST_W, HEAD_H + ROWS * ROW_H + 8)
        paint(list, PANEL, BORDER)
        list:EnableMouseWheel(true)

        local head = CreateFrame("Frame", nil, list)
        head:SetPoint("TOPLEFT", 0, -2)
        head:SetSize(LIST_W, HEAD_H)
        ui.header = {}
        for c = 1, MAX_COLS do
            local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetWordWrap(false)
            ui.header[c] = fs
        end
        local rule = list:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
        rule:SetPoint("TOPLEFT", 1, -(HEAD_H + 3))
        rule:SetPoint("TOPRIGHT", -1, -(HEAD_H + 3))
        rule:SetHeight(1)

        ui.rows = {}
        for i = 1, ROWS do
            local row = CreateFrame("Button", nil, list)
            row:SetSize(LIST_W - 2, ROW_H)
            row:SetPoint("TOPLEFT", 1, -(HEAD_H + 5 + (i - 1) * ROW_H))
            if i % 2 == 0 then
                local stripe = row:CreateTexture(nil, "BACKGROUND")
                stripe:SetAllPoints()
                stripe:SetColorTexture(1, 1, 1, 0.03)
            end
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
            row.cells = {}
            for c = 1, MAX_COLS do
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetWordWrap(false)
                row.cells[c] = fs
            end
            row:SetScript("OnEnter", showTip)
            row:SetScript("OnLeave", hideTip)
            -- the wheel over a row scrolls the list
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta)
                local wheel = list:GetScript("OnMouseWheel")
                if wheel then wheel(list, delta) end
            end)
            ui.rows[i] = row
        end
        ui.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ui.empty:SetPoint("CENTER", 0, -8)

        local bar = CreateFrame("Slider", nil, f, "BackdropTemplate")
        bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, 0)
        bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 4, 0)
        bar:SetWidth(10)
        bar:SetOrientation("VERTICAL")
        paint(bar, PANEL, BORDER)
        local thumb = bar:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(0.30, 0.45, 0.55, 1)
        thumb:SetSize(8, 30)
        bar:SetThumbTexture(thumb)
        bar:SetMinMaxValues(0, 0)
        bar:SetValueStep(1)
        if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
        bar:SetValue(0)
        bar:SetScript("OnValueChanged", function(_, v)
            local o = floor((tonumber(v) or 0) + 0.5)
            if o ~= ui.offset then
                ui.offset = o
                draw()
            end
        end)
        ui.bar = bar
        list:SetScript("OnMouseWheel", function(_, delta)
            local step = (IsShiftKeyDown and IsShiftKeyDown()) and ROWS or 3
            bar:SetValue(max(0, ui.offset - delta * step))
        end)

        ui.shareBtn = makeButton(f, 120, 22, function()
            lib.SetEnabled(not lib.IsEnabled())
            say(lib.IsEnabled() and T("on") or T("off"))
            refresh()
        end)
        ui.shareBtn:SetPoint("BOTTOMLEFT", PAD, 12)
        ui.channelBtn = makeButton(f, 120, 22, function()
            lib.SetEnabled(lib.IsEnabled(), settings().noChannel == true)
            say(settings().noChannel and T("channelOff") or T("channelOn"))
            refresh()
        end)
        ui.channelBtn:SetPoint("LEFT", ui.shareBtn, "RIGHT", 6, 0)
        ui.clearBtn = makeButton(f, 110, 22, function()
            activity.clear()
            ui.offset = 0
            refresh()
        end)
        ui.clearBtn:SetPoint("BOTTOMRIGHT", -PAD, 12)
        ui.since = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ui.since:SetPoint("RIGHT", ui.clearBtn, "LEFT", -10, 0)
        ui.range = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ui.range:SetPoint("RIGHT", ui.since, "LEFT", -14, 0)

        local elapsed = 0
        f:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + (tonumber(dt) or 0)
            if elapsed >= 1 then
                elapsed = 0
                refresh()
            end
        end)
        f:SetScript("OnShow", function() refresh() end)

        local pad = _G.EzWoW_GamePad
        if type(pad) == "table" and type(pad.RegisterWindow) == "function" then pcall(pad.RegisterWindow, f) end
        return f
    end

    function lib.ToggleWindow()
        local f = ui.frame or build()
        if f:IsShown() then f:Hide() else f:Show() end
    end

    -- tab: "recv", "people", "sent" or "kinds" (optional)
    function lib.OpenWindow(tab)
        local f = ui.frame or build()
        if TAB_TITLES[tab] then
            ui.tab = tab
            ui.offset = 0
        end
        f:Show()
        refresh()
    end
end
setupWindow()
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
        if lib.OnQuestRewards then pcall(lib.OnQuestRewards) end
        if lib.OnObjectUnit then pcall(lib.OnObjectUnit, "questnpc") end
    elseif event == "QUEST_COMPLETE" then
        if lib.IsEnabled() then onQuestComplete() end
        if lib.OnQuestRewards then pcall(lib.OnQuestRewards) end
        if lib.OnObjectUnit then pcall(lib.OnObjectUnit, "questnpc") end
    elseif event == "TRAINER_SHOW" then
        if lib.OnTrainerShow then pcall(lib.OnTrainerShow) end
    elseif event == "GOSSIP_SHOW" then
        if lib.OnObjectUnit then pcall(lib.OnObjectUnit, "npc") end
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        if lib.OnObjectUnit then pcall(lib.OnObjectUnit, "softinteract") end
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
    elseif event == "GROUP_JOINED" then
        if lib.SyncGroupJoined then lib.SyncGroupJoined() end
    elseif event == "PLAYER_ENTERING_WORLD" and not lib.started then
        lib.started = true
        -- after the game's own channels have their numbers
        later(12, lib.JoinChannel)
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(SEND_EVERY, function()
                if lib.SendTick then pcall(lib.SendTick) end
            end)
            -- asks and answers (numbered records)
            C_Timer.NewTicker(2, function()
                if lib.ServeTick then pcall(lib.ServeTick) end
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
for _, event in ipairs({ "CHANNEL_ROSTER_UPDATE", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "MERCHANT_SHOW",
    "TRAINER_SHOW", "GOSSIP_SHOW", "PLAYER_SOFT_INTERACT_CHANGED", "GROUP_JOINED" }) do
    pcall(lib.events.RegisterEvent, lib.events, event)
end

-- saving at logout: a frame of its own (the event frame may come from an
-- older copy); each newer copy sets its script again
if not lib.saver then lib.saver = CreateFrame("Frame") end
pcall(lib.saver.RegisterEvent, lib.saver, "PLAYER_LOGOUT")
lib.saver:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGOUT" or not lib.OnLogout then return end
    local ok, err = pcall(lib.OnLogout)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end)
