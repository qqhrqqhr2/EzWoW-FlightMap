--===========================================================================
-- EzWoW - Flight Map
-- UI/FlightMapExtras.lua : World Map Art, Zone Names & Highlight, Quest and
--                          Dungeon Markers for the flight map window
--===========================================================================
-- The flight map can show the continent as one image made from the world
-- map's art (Media/FlightMap-*.tga: EzWoW tone, zone borders drawn in). The
-- image covers the continent's whole world map (uiMap 0..1), so flight
-- points are placed with that map's coordinates. Zone names are written at
-- runtime in the client's language at spots kept in Data/ZoneLabels.lua, the
-- zone under the cursor is lit with the game's own zone highlight shape, and
-- markers show quest turn-ins of the quest log and dungeon entrances.
-- Everything here is optional: when an API or a data table is missing the
-- part is skipped and the window keeps working as before.
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall
local floor, ceil, min, max, sqrt, abs = math.floor, math.ceil, math.min, math.max, math.sqrt, math.abs

local Extras = ns.FlightMapExtras or {}
ns.FlightMapExtras = Extras

local STYLE = ns.STYLE
local L = ns.L
local GLOW_FILE = ns.GLOW_FILE

-- EzWoW cyan (zone lines, highlight) and the muted zone-name color
local ZONE_ACCENT = { 0.294, 0.784, 0.910 }
local ZONE_TEXT = { 0.96, 0.92, 0.80 }
local DUNGEON_TEXT = { 0.62, 0.90, 1.00 }
local ROUND_DOT = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local QUEST_DONE = { 1.00, 0.82, 0.25 }

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function num(v)
    return type(v) == "number" and not isSecret(v) and v == v and abs(v) < math.huge
end

local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

local function vecXY(v)
    if type(v) ~= "table" then return nil end
    local x, y = v.x, v.y
    if not (num(x) and num(y)) and type(v.GetXY) == "function" then
        local ok, a, b = pcall(v.GetXY, v)
        if ok then x, y = a, b end
    end
    if num(x) and num(y) then return x, y end
    return nil
end

local function inUnit(x, y)
    return num(x) and num(y) and x >= -0.001 and x <= 1.001 and y >= -0.001 and y <= 1.001
end

-----------------------------------------------------------------------------
-- Placeholder taxi nodes
-----------------------------------------------------------------------------
-- The client lists a few internal taxi nodes (route targets for zeppelins
-- and test nodes) that are not flight points. They are hidden everywhere.
local PLACEHOLDER_NODE_IDS = { [3] = true, [24] = true, [36] = true }
local PLACEHOLDER_NAMES = {
    ["Generic, World target"] = true, ["Generic, World target for Zeppelin Paths"] = true, ["Programmer Isle"] = true,
    ["일반 (세계 대상)"] = true, ["일반 (비행선 경로)"] = true, ["프로그래머의 섬"] = true,
    ["Allgemein, Weltziel für Zeppelinrouten"] = true, ["Programmierer-Insel"] = true,
    ["Générique, cible monde"] = true, ["Générique, Cible monde pour les voies des zeppelins"] = true, ["Ile des programmeurs"] = true,
    ["Genérico, Objetivo mundial"] = true, ["Genérico, Objetivo mundial para rutas de zeppelines"] = true,
    ["Genérico, Objetivo mundial de rutas de zepelines"] = true, ["Isla del programador"] = true,
    ["Стандартный, мир, цель"] = true, ["Стандартный, мир, цель для маршрутов дирижаблей"] = true, ["Остров программиста"] = true,
}

function Extras.IsPlaceholderNode(node)
    if type(node) ~= "table" then return false end
    if node.nodeID and PLACEHOLDER_NODE_IDS[node.nodeID] then return true end
    local name = node.name
    if type(name) ~= "string" then return false end
    if PLACEHOLDER_NAMES[name] then return true end
    if name:find("^Quest Path %d+") then return true end
    return false
end
ns.IsPlaceholderFlightNode = Extras.IsPlaceholderNode

-----------------------------------------------------------------------------
-- Continent images
-----------------------------------------------------------------------------
-- [continent uiMapID] = image name; each image is 1002x668 (the world map's
-- size) in a 1024x768 area: a 1024x512 top part and a 1024x256 bottom part.
local MAP_IMAGES = { [1415] = "FlightMap-EK", [1414] = "FlightMap-Kalimdor" }
local IMAGE_W, IMAGE_H = 1002, 668

-- Returns { w, h, tiles = { {x0,y0,x1,y1,u0,u1,v0,v1,file}, ... }, kind = "world", mapID }
-- or nil when there is no image for the continent.
-- the sea changes with the season: by the month (auto) or one picked with
-- /ezfl season; "plain" is the plain navy sea
local SEASON_OF_MONTH = { "Winter", "Winter", "Spring", "Spring", "Spring", "Summer",
    "Summer", "Summer", "Autumn", "Autumn", "Autumn", "Winter" }
local SEASONS = { spring = "Spring", summer = "Summer", autumn = "Autumn", winter = "Winter", parchment = "Parchment" }
-- nil = the game's own continent map (the default look)
function Extras.Season()
    local mode = ns.DB and ns.DB.season or "plain"
    if mode == "plain" then return nil end
    if SEASONS[mode] then return SEASONS[mode] end
    local t = type(date) == "function" and date("*t")
    return SEASON_OF_MONTH[t and t.month or 1]
end

-- the game's own continent map picture (the "plain" look): its tiles, read
-- from the client, on the same 1002x668 frame
local function gameMapArt(mapID)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
    local ok, layers = call(C_Map.GetMapArtLayers, mapID)
    local layer1 = ok and type(layers) == "table" and layers[1]
    if type(layer1) ~= "table" then return nil end
    local lw, lh = layer1.layerWidth, layer1.layerHeight
    local tw, th = layer1.tileWidth, layer1.tileHeight
    if not (num(lw) and num(lh) and num(tw) and num(th)) or tw <= 0 or th <= 0 then return nil end
    local ok2, files = call(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not ok2 or type(files) ~= "table" or #files == 0 then return nil end
    local cols = ceil(lw / tw)
    local tiles = {}
    for i, fileID in ipairs(files) do
        local col, row = (i - 1) % cols, floor((i - 1) / cols)
        local x0, y0 = col * tw, row * th
        if x0 < lw and y0 < lh then
            local x1, y1 = min(x0 + tw, lw), min(y0 + th, lh)
            -- art size -> our 1002x668 frame
            local sx, sy = IMAGE_W / lw, IMAGE_H / lh
            tiles[#tiles + 1] = { x0 = x0 * sx, y0 = y0 * sy, x1 = x1 * sx, y1 = y1 * sy,
                u0 = 0, u1 = (x1 - x0) / tw, v0 = 0, v1 = (y1 - y0) / th, file = fileID }
        end
    end
    if #tiles == 0 then return nil end
    return { w = IMAGE_W, h = IMAGE_H, kind = "world", mapID = mapID, gameArt = true, tiles = tiles }
end

function Extras.BuildWorldArt(mapID)
    local name = num(mapID) and MAP_IMAGES[mapID]
    if not name then return nil end
    local season = Extras.Season()
    if not season then
        local art = gameMapArt(mapID)
        if art then return art end
    end
    if season then name = name .. "-" .. season end
    local file = (ns.MEDIA or "") .. name
    return {
        w = IMAGE_W, h = IMAGE_H, kind = "world", mapID = mapID,
        tiles = {
            { x0 = 0, y0 = 0, x1 = IMAGE_W, y1 = 512, u0 = 0, u1 = IMAGE_W / 1024, v0 = 0, v1 = 1, file = file .. "-1" },
            { x0 = 0, y0 = 512, x1 = IMAGE_W, y1 = IMAGE_H, u0 = 0, u1 = IMAGE_W / 1024, v0 = 0, v1 = (IMAGE_H - 512) / 256, file = file .. "-2" },
        },
    }
end

-- land span (art pixels) between two heights (art pixels), or nil
function Extras.LandSpan(mapID, y0, y1)
    local t = ns.LAND_ROWS and num(mapID) and ns.LAND_ROWS[mapID]
    if type(t) ~= "table" or not num(t.rows) then return nil end
    local r0 = max(1, floor(y0 / IMAGE_H * t.rows) + 1)
    local r1 = min(t.rows, floor(y1 / IMAGE_H * t.rows) + 1)
    local left, right
    for r = r0, r1 do
        local c = t[r]
        if type(c) == "table" then
            left = left and min(left, c[1]) or c[1]
            right = right and max(right, c[2]) or c[2]
        end
    end
    return left, right
end

-----------------------------------------------------------------------------
-- Flight point positions on the continent map
-----------------------------------------------------------------------------
-- The flight master's own map can be a separate flight-only map, so the
-- positions are taken in this order and checked against the player's spot:
--   1. the flight map is the continent itself: the taxi positions as they are
--   2. C_TaxiMap.GetAllTaxiNodes(continent) when its positions are on the continent
--   3. taxi position -> world position -> continent position
local function taxiXY(rec, snap)
    if not (num(rec.tx) and num(rec.ty)) then return nil end
    return rec.tx, snap.invertFlightAxisY and (1 - rec.ty) or rec.ty
end

local function fromApi(snap, mapID)
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return nil end
    local ok, list = call(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok or type(list) ~= "table" then return nil end
    local out, n = {}, 0
    for _, info in ipairs(list) do
        local rec = type(info) == "table" and snap.bySlot[info.slotIndex]
        if rec and info.name == rec.name then
            local x, y = vecXY(info.position)
            if inUnit(x, y) then out[rec] = { x, y }; n = n + 1 end
        end
    end
    return n > 0 and out or nil, n
end

local function fromWorld(snap, mapID)
    local src = snap.flightMapID
    if not (num(src) and C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local out, n = {}, 0
    for _, rec in ipairs(snap.list) do
        local tx, ty = taxiXY(rec, snap)
        if tx then
            local ok, cont, world = call(C_Map.GetWorldPosFromMapPos, src, CreateVector2D(tx, ty))
            if ok and num(cont) and type(world) == "table" then
                local ok2, onMap, pos = call(C_Map.GetMapPosFromWorldPos, cont, world, mapID)
                local x, y = vecXY(pos)
                if ok2 and (onMap == nil or onMap == mapID) and inUnit(x, y) then out[rec] = { x, y }; n = n + 1 end
            end
        end
    end
    return n > 0 and out or nil, n
end

-- true when a position set is just the flight map's own positions again
local function sameAsTaxi(pos, snap)
    local same, total = 0, 0
    for rec, p in pairs(pos) do
        local tx, ty = taxiXY(rec, snap)
        if tx then
            total = total + 1
            if abs(p[1] - tx) < 0.002 and abs(p[2] - ty) < 0.002 then same = same + 1 end
        end
    end
    return total > 0 and same >= total * 0.8
end

local function playerSpot(mapID)
    if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = call(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok then return nil end
    return vecXY(pos)
end

local function fitsPlayer(pos, snap, px, py)
    if not (px and snap.currentSlot) then return nil end
    local rec = snap.bySlot[snap.currentSlot]
    local p = rec and pos[rec]
    if not p then return nil end
    return abs(p[1] - px) < 0.03 and abs(p[2] - py) < 0.03
end

-- Sets rec.wx, rec.wy (continent position) on every node it can place and
-- returns how many it placed.
function Extras.ProjectNodes(snap, mapID)
    if not (snap and snap.list and num(mapID)) then return 0 end
    local candidates = {}
    if snap.flightMapID == mapID then
        local pos, n = {}, 0
        for _, rec in ipairs(snap.list) do
            local tx, ty = taxiXY(rec, snap)
            if inUnit(tx, ty) then pos[rec] = { tx, ty }; n = n + 1 end
        end
        if n > 0 then candidates[#candidates + 1] = pos end
    end
    local api = fromApi(snap, mapID)
    if api and not (snap.flightMapID ~= mapID and sameAsTaxi(api, snap)) then candidates[#candidates + 1] = api end
    local world = fromWorld(snap, mapID)
    if world then candidates[#candidates + 1] = world end
    if #candidates == 0 then return 0 end
    local chosen = candidates[1]
    local px, py = playerSpot(mapID)
    if px then
        for _, pos in ipairs(candidates) do
            if fitsPlayer(pos, snap, px, py) then chosen = pos; break end
        end
    end
    local placed = 0
    for _, rec in ipairs(snap.list) do
        local p = chosen[rec]
        rec.wx, rec.wy = p and p[1] or nil, p and p[2] or nil
        if p then placed = placed + 1 end
    end
    return placed
end

-----------------------------------------------------------------------------
-- Zones of a continent: name and the spot for the name
-----------------------------------------------------------------------------
local zoneCache = {}

-- the zone (one listed for the continent) a map belongs to
local function zoneOf(mapID, continentID, zones)
    for _ = 1, 4 do
        if not num(mapID) then return nil end
        if zones[mapID] then return mapID end
        local ok, info = call(C_Map.GetMapInfo, mapID)
        if not ok or type(info) ~= "table" or info.parentMapID == continentID then return nil end
        mapID = info.parentMapID
    end
    return nil
end

local function zoneAt(continentID, x, y, zones)
    local ok, info = call(C_Map and C_Map.GetMapInfoAtPosition, continentID, x, y)
    if not ok or type(info) ~= "table" or not num(info.mapID) or info.mapID == continentID then return nil end
    return zoneOf(info.mapID, continentID, zones)
end

-- zones with a name spot (Data/ZoneLabels.lua); the names come from the
-- client so they are in its language
function Extras.GetZones(continentID)
    if not num(continentID) then return nil end
    if zoneCache[continentID] ~= nil then return zoneCache[continentID] or nil end
    zoneCache[continentID] = false
    local spots = type(ns.ZONE_LABELS) == "table" and ns.ZONE_LABELS[continentID]
    if type(spots) ~= "table" or not (C_Map and C_Map.GetMapInfo) then return nil end
    local zones, any = {}, false
    for zoneID, spot in pairs(spots) do
        local ok, info = call(C_Map.GetMapInfo, zoneID)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= ""
            and type(spot) == "table" and num(spot[1]) and num(spot[2]) then
            zones[zoneID] = { id = zoneID, name = info.name, lx = spot[1], ly = spot[2], order = spot[3] or 0 }
            any = true
        end
    end
    if not any then return nil end
    zoneCache[continentID] = zones
    return zones
end

-- continent position of a spot given on one of its zones (or the continent)
function Extras.ToContinent(continentID, mapID, x, y)
    if not (num(x) and num(y)) then return nil end
    if mapID == continentID then return x, y end
    if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
    local ok, x0, x1, y0, y1 = call(C_Map.GetMapRectOnMap, mapID, continentID)
    if not ok or not (num(x0) and num(x1) and num(y0) and num(y1)) or x1 <= x0 or y1 <= y0 then return nil end
    local cx, cy = x0 + x * (x1 - x0), y0 + y * (y1 - y0)
    if inUnit(cx, cy) then return cx, cy end
    return nil
end

-----------------------------------------------------------------------------
-- Quest turn-ins of the quest log
-----------------------------------------------------------------------------
-- Turn-in spots ({ "npc"/"object", id, continent, worldX, worldY }) come from
-- the shared EzWoW - Data quest map when another addon already loaded it,
-- else from EzWoW - Map Finder's quest table. Nothing is loaded from here.
local function turnInTables()
    local out = {}
    local D = _G.EzWoW_Data
    if type(D) == "table" and D.formatVersion == 2 and type(D.Peek) == "function" then
        local ok, t = pcall(D.Peek, "QuestMap", "turnIns")
        if ok and type(t) == "table" then out[#out + 1] = t end
    end
    local mf = _G.EzWoWMapFinderQuestData
    if type(mf) == "table" and type(mf.turnIns) == "table" then out[#out + 1] = mf.turnIns end
    return out
end

local function worldToContinent(cont, wx, wy, continentID)
    if not (num(cont) and num(wx) and num(wy) and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, onMap, pos = call(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), continentID)
    if not ok or (onMap ~= nil and onMap ~= continentID) then return nil end
    local x, y = vecXY(pos)
    if inUnit(x, y) then return x, y end
    return nil
end

local function questDone(questID)
    for _, fn in ipairs({ C_QuestLog and C_QuestLog.ReadyForTurnIn, C_QuestLog and C_QuestLog.IsComplete }) do
        local ok, v = call(fn, questID)
        if ok and v == true then return true end
    end
    return false
end

function Extras.CollectQuests(continentID)
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
    local tables = turnInTables()
    if #tables == 0 then return out end
    local okN, n = call(C_QuestLog.GetNumQuestLogEntries)
    if not okN or not num(n) then return out end
    for i = 1, min(n, 200) do
        local ok, info = call(C_QuestLog.GetInfo, i)
        local qid = ok and type(info) == "table" and not info.isHeader and not info.isHidden and info.questID
        if num(qid) and qid > 0 then
            local rec
            for _, t in ipairs(tables) do
                rec = t[qid]
                if type(rec) == "table" and num(rec[3]) then break end
                rec = nil
            end
            if rec then
                local x, y = worldToContinent(rec[3], rec[4], rec[5], continentID)
                if x then
                    out[#out + 1] = { kind = "quest", x = x, y = y, done = questDone(qid), title = info.title or ("#" .. qid), questID = qid }
                end
            end
        end
    end
    return out
end

-----------------------------------------------------------------------------
-- Dungeon entrances
-----------------------------------------------------------------------------
-- The client's entrance list first (per continent, then per zone), else the
-- shared EzWoW - Data dungeon list when it is already loaded. Level ranges
-- come from that list when it is there.
local LOCALE_FIELD = { koKR = "ko", enUS = "en", enGB = "en", deDE = "de", frFR = "fr", esES = "es", esMX = "es", ruRU = "ru", zhCN = "zhCN", zhTW = "zhTW" }

local function dungeonList()
    local D = _G.EzWoW_Data
    if type(D) ~= "table" or D.formatVersion ~= 2 or type(D.Peek) ~= "function" then return nil end
    local ok, t = pcall(D.Peek, "Dungeons", "list")
    return ok and type(t) == "table" and t or nil
end

local function localName(names)
    if type(names) ~= "table" then return nil end
    local loc = type(GetLocale) == "function" and GetLocale() or "enUS"
    return names[LOCALE_FIELD[loc] or "en"] or names.en or names.ko
end

local function levelsFor(name, list)
    if not (list and type(name) == "string") then return nil end
    for _, d in ipairs(list) do
        if type(d) == "table" and type(d.name) == "table" then
            for _, text in pairs(d.name) do
                if text == name then return d.levels end
            end
        end
    end
    return nil
end

local function apiEntrances(continentID, zones, out)
    local ej = C_EncounterJournal
    if not (ej and ej.GetDungeonEntrancesForMap) then return end
    local seen = {}
    local function add(mapID)
        local ok, list = call(ej.GetDungeonEntrancesForMap, mapID)
        if not ok or type(list) ~= "table" then return end
        for _, e in ipairs(list) do
            local x, y = vecXY(type(e) == "table" and e.position)
            if x and type(e.name) == "string" then
                local cx, cy = Extras.ToContinent(continentID, mapID, x, y)
                local key = e.name .. floor((cx or 0) * 200) .. ":" .. floor((cy or 0) * 200)
                if cx and not seen[key] then
                    seen[key] = true
                    out[#out + 1] = { kind = "dungeon", x = cx, y = cy, name = e.name, atlas = e.atlasName }
                end
            end
        end
    end
    add(continentID)
    if #out == 0 and zones then
        for zoneID in pairs(zones) do add(zoneID) end
    end
end

function Extras.CollectDungeons(continentID, zones)
    local out = {}
    pcall(apiEntrances, continentID, zones, out)
    local list = dungeonList()
    if #out == 0 and list then
        for _, d in ipairs(list) do
            local e = type(d) == "table" and d.entrance
            if type(e) == "table" and num(e.map) and num(e.x) and num(e.y) then
                local cx, cy = Extras.ToContinent(continentID, e.map, e.x / 100, e.y / 100)
                local name = localName(d.name)
                if cx and name then out[#out + 1] = { kind = "dungeon", x = cx, y = cy, name = name, levels = d.levels } end
            end
        end
    end
    for _, m in ipairs(out) do
        if not m.levels then m.levels = levelsFor(m.name, list) end
    end
    -- every entrance on its own (same-spot ones are spread apart up/down);
    -- the number keeps the label spot of each apart
    local seen = {}
    for _, m in ipairs(out) do
        local spot = floor(m.x * 1000) .. ":" .. floor(m.y * 1000)
        seen[spot] = (seen[spot] or 0) + 1
        m.spotKey = "D" .. spot .. ":" .. seen[spot]
    end
    return out
end

-- the words two names start with ("Scarlet Monastery Library" + "... Armory")
local function words(text)
    local t = {}
    for w in text:gmatch("%S+") do t[#t + 1] = w end
    return t
end

local function sharedStart(a, b)
    local wa, wb, n = words(a), words(b), 0
    while wa[n + 1] and wa[n + 1] == wb[n + 1] do n = n + 1 end
    return n > 0 and table.concat(wa, " ", 1, n) or nil
end

-- one level range over several ("30-38", "34-45" -> "30-45")
local function joinLevels(list)
    local lo, hi
    for _, m in ipairs(list) do
        if type(m.levels) == "string" then
            local a, b = m.levels:match("^(%d+)%D+(%d+)$")
            a = tonumber(a or m.levels:match("^(%d+)$")); b = tonumber(b) or a
            if a then lo = lo and min(lo, a) or a; hi = hi and max(hi, b) or b end
        end
    end
    if not lo then return nil end
    return lo == hi and tostring(lo) or (lo .. "-" .. hi)
end

-- entrances on (almost) the same spot: one marker named by the words most of
-- them share (e.g. the wings of one monastery), each one listed in its tooltip
local SAME_SPOT = 0.012
function Extras.GroupDungeons(list)
    local groups = {}
    for _, m in ipairs(list) do
        local g
        for _, other in ipairs(groups) do
            if abs(other.x - m.x) < SAME_SPOT and abs(other.y - m.y) < SAME_SPOT then g = other; break end
        end
        if g then g.members[#g.members + 1] = m
        else groups[#groups + 1] = { kind = "dungeon", x = m.x, y = m.y, atlas = m.atlas, members = { m } } end
    end
    for _, g in ipairs(groups) do
        local ms = g.members
        if #ms == 1 then
            g.name, g.levels, g.members = ms[1].name, ms[1].levels, nil
        else
            local best, bestCount = nil, 0
            for i = 1, #ms do
                for j = i + 1, #ms do
                    local shared = sharedStart(ms[i].name, ms[j].name)
                    if shared then
                        local count = 0
                        for _, m in ipairs(ms) do
                            if m.name:sub(1, #shared) == shared then count = count + 1 end
                        end
                        if count > bestCount or (count == bestCount and best and #shared < #best) then best, bestCount = shared, count end
                    end
                end
            end
            g.name = best or ms[1].name
            g.levels = joinLevels(ms)
        end
    end
    return groups
end

-----------------------------------------------------------------------------
-- Drawing
-----------------------------------------------------------------------------
local layer, markerLayer
local namePool, markerPool = {}, {}
local ctx
local hoverZone

local function hitAny(x, y, w, h, rects)
    for i = 1, #rects do
        local r = rects[i]
        if x < r[1] + r[3] and x + w > r[1] and y < r[2] + r[4] and y + h > r[2] then return true end
    end
    return false
end

-- places a text box near (px, py): the spot itself, a little above or below,
-- or to a side; shown faded at the spot when every place is taken
local OFFSETS = { { 0, 0 }, { 0, -1 }, { 0, 1 }, { -0.6, 0 }, { 0.6, 0 }, { 0, -2 }, { 0, 2 } }
local function placeText(fs, px, py, rects, vw, vh)
    local w, h = (fs:GetStringWidth() or 0) + 4, (fs:GetStringHeight() or 10) + 2
    for _, o in ipairs(OFFSETS) do
        local x, y = px - w / 2 + o[1] * w, py - h / 2 + o[2] * h
        if x >= 0 and y >= 0 and x + w <= vw and y + h <= vh and not hitAny(x, y, w, h, rects) then
            rects[#rects + 1] = { x, y, w, h }
            return x + w / 2, y + h / 2, true
        end
    end
    return px, py, false
end

local function ensureLayers(canvas)
    if layer then return end
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetAllPoints(canvas)
    layer:EnableMouse(false)
    layer.hl = {}
    for i = 1, 2 do
        local t = layer:CreateTexture(nil, "ARTWORK", nil, -2)
        t:SetBlendMode("ADD")
        t:SetVertexColor(ZONE_ACCENT[1], ZONE_ACCENT[2], ZONE_ACCENT[3], 1)
        t:Hide()
        layer.hl[i] = t
    end
    markerLayer = CreateFrame("Frame", nil, canvas)
    markerLayer:SetAllPoints(canvas)
    markerLayer:EnableMouse(false)
end

local function nameString(i)
    local fs = namePool[i]
    if not fs then
        fs = layer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.95)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        namePool[i] = fs
    end
    return fs
end

-- names on the map: outlined so they read on any ground
local function setMapFont(fs, size)
    local fo = _G.GameFontNormal or _G.GameFontHighlightSmall
    local file = fo and fo.GetFont and fo:GetFont()
    if file and fs.SetFont then fs:SetFont(file, size, "OUTLINE") else ns.SetFontSize(fs, size) end
end

-- art pixel -> view (canvas) position
local function view(nx, ny)
    return (nx * ctx.W - ctx.cx0) * ctx.s, (ny * ctx.H - ctx.cy0) * ctx.s
end

local function styleName(fs, z, lit)
    if lit then
        fs:SetTextColor(1, 1, 1, 1)
    else
        fs:SetTextColor(ZONE_TEXT[1], ZONE_TEXT[2], ZONE_TEXT[3], 1)
    end
    -- a name that would overlap other text shows only while its zone is hovered
    fs:SetShown(lit or not fs.crowded)
end

-- the nearest flight point to a spot (reachable ones first)
local function nearestNode(x, y)
    if not (ctx and ctx.nodes) then return nil end
    local best, bestD, bestRank
    for _, node in ipairs(ctx.nodes) do
        if node.x and ctx.isVisible(node) then
            local dx, dy = (node.x - x) * ctx.W, (node.y - y) * ctx.H
            local d = dx * dx + dy * dy
            local rank = (node.type == "DISTANT") and 1 or 0
            if not best or rank < bestRank or (rank == bestRank and d < bestD) then best, bestD, bestRank = node, d, rank end
        end
    end
    return best
end

local function markerOnEnter(self)
    local m = self.data
    if not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if m.kind == "dungeon" then
        GameTooltip:AddLine(m.name, ZONE_ACCENT[1], ZONE_ACCENT[2], ZONE_ACCENT[3])
        if m.members then
            for _, d in ipairs(m.members) do
                GameTooltip:AddDoubleLine(d.name, d.levels and L.MARK_LEVELS:format(d.levels) or "", 1, 1, 1, 0.8, 0.8, 0.8)
            end
        elseif m.levels then
            GameTooltip:AddLine(L.MARK_LEVELS:format(m.levels), 1, 1, 1)
        end
    else
        GameTooltip:AddLine(L.MARK_TURNIN, QUEST_DONE[1], QUEST_DONE[2], QUEST_DONE[3])
        for _, q in ipairs(self.quests or { m }) do
            if q.done then
                GameTooltip:AddLine("|cffffd040?|r " .. q.title .. "  |cff8cffa6" .. L.MARK_DONE .. "|r", 1, 1, 1)
            else
                GameTooltip:AddLine("|cff9aa5ad?|r " .. q.title, 0.80, 0.84, 0.87)
            end
        end
    end
    local node = nearestNode(m.x, m.y)
    if node then
        local name = node.name or "?"
        if node.type == "CURRENT" then name = name .. " (" .. L.CURRENT .. ")" end
        GameTooltip:AddLine(L.MARK_NEAREST:format(name), STYLE.textMuted[1], STYLE.textMuted[2], STYLE.textMuted[3])
        GameTooltip:AddLine(L.MARK_CLICK, 0.4, 0.8, 1)
    end
    GameTooltip:Show()
    self.glow:SetAlpha(1)
end

local function markerOnLeave(self)
    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    self.glow:SetAlpha(self.glowAlpha or 0.5)
end

local function markerOnClick(self)
    local m = self.data
    local node = m and nearestNode(m.x, m.y)
    if node and ctx and ctx.onPick then ctx.onPick(node) end
end

local function markerButton(i)
    local b = markerPool[i]
    if b then return b end
    b = CreateFrame("Button", nil, markerLayer)
    b:RegisterForClicks("LeftButtonUp")
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(GLOW_FILE)
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetPoint("CENTER")
    b.bg:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.bullet = markerLayer:CreateTexture(nil, "OVERLAY")
    b.bullet:SetTexture(ROUND_DOT)
    b.bullet:SetSize(5, 5)
    b.bullet:Hide()
    b.text = markerLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetShadowOffset(1, -1)
    b.text:SetShadowColor(0, 0, 0, 0.95)
    if b.text.SetWordWrap then b.text:SetWordWrap(false) end
    b:SetScript("OnEnter", markerOnEnter)
    b:SetScript("OnLeave", markerOnLeave)
    b:SetScript("OnClick", markerOnClick)
    b:Hide()
    markerPool[i] = b
    return b
end

local function setIcon(b, m)
    local icon = b.icon
    icon:SetTexCoord(0, 1, 0, 1)
    icon:SetVertexColor(1, 1, 1, 1)
    if icon.SetDesaturated then icon:SetDesaturated(false) end
    b.bg:Hide()
    if m.kind == "dungeon" then
        if m.atlas and icon.SetAtlas and icon:SetAtlas(m.atlas) ~= false and icon:GetAtlas() then return end
        if icon.SetAtlas and icon:SetAtlas("Dungeon") ~= false and icon:GetAtlas() then return end
        icon:SetTexture("Interface\\Minimap\\Dungeon")
        return
    end
    -- quest: the world map's quest pin (dark round badge + "?"), grey while not done
    if icon.SetAtlas and icon:SetAtlas("UI-QuestPoi-QuestBangTurnIn") ~= false and icon:GetAtlas() then
        if b.bg:SetAtlas("UI-QuestPoi-QuestNumber") ~= false and b.bg:GetAtlas() then b.bg:Show() end
        if not m.done and icon.SetDesaturated then icon:SetDesaturated(true) end
        return
    end
    local file = m.done and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\IncompleteQuestIcon"
    if icon:SetTexture(file) == false then
        icon:SetColorTexture(QUEST_DONE[1], QUEST_DONE[2], QUEST_DONE[3], m.done and 1 or 0.5)
    end
end

-- group quest spots that would sit on top of each other
local function groupQuests(list)
    local groups = {}
    for _, q in ipairs(list) do
        local px, py = view(q.x, q.y)
        local g
        for _, other in ipairs(groups) do
            if abs(other.px - px) < 9 and abs(other.py - py) < 9 then g = other; break end
        end
        if g then
            g.quests[#g.quests + 1] = q
            g.done = g.done or q.done
        else
            groups[#groups + 1] = { kind = "quest", x = q.x, y = q.y, px = px, py = py, done = q.done, title = q.title, quests = { q } }
        end
    end
    return groups
end

local function hideMarkers(from)
    for i = from, #markerPool do
        local b = markerPool[i]
        b:Hide(); b.text:Hide(); b.bullet:Hide(); b.data, b.quests = nil, nil
    end
end

-- dotted leader lines (dungeon names, moved icons)
local dotPool, dotsUsed = {}, 0
local function hideDots(from)
    for i = from, #dotPool do dotPool[i]:Hide() end
    dotsUsed = from - 1
end

local function dottedLine(x1, y1, x2, y2, r, g, b, a)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 2 then return end
    local n = floor(len / 4)
    for i = 0, n do
        dotsUsed = dotsUsed + 1
        local d = dotPool[dotsUsed]
        if not d then
            d = markerLayer:CreateTexture(nil, "ARTWORK")
            d:SetTexture(ROUND_DOT)
            d:SetSize(2, 2)
            dotPool[dotsUsed] = d
        end
        local t = n > 0 and i / n or 0
        d:SetVertexColor(r, g, b, a)
        d:ClearAllPoints()
        d:SetPoint("CENTER", ctx.canvas, "TOPLEFT", x1 + dx * t, -(y1 + dy * t))
        d:Show()
    end
end

-- Label positions moved by hand (/ezfl edit): saved per continent as the
-- label's center on the continent image (0..1), so zoom and window size do
-- not matter. ns.LABEL_SPOTS (Data/ZoneLabels.lua) holds the built-in ones.
Extras.editMode = false

local function spotTable(mapID, create)
    if create then
        ns.DB.labelPos = type(ns.DB.labelPos) == "table" and ns.DB.labelPos or {}
        ns.DB.labelPos[mapID] = type(ns.DB.labelPos[mapID]) == "table" and ns.DB.labelPos[mapID] or {}
    end
    return type(ns.DB.labelPos) == "table" and ns.DB.labelPos[mapID] or nil
end

-- the saved center of a label in view coordinates, or nil
-- (st: mapID and the view: s, cx0, cy0, W, H)
function Extras.SavedSpotView(st, key)
    if not (st and num(st.mapID) and num(st.s) and num(st.W) and num(st.H)) then return nil end
    local own = spotTable(st.mapID)
    local builtIn = type(ns.LABEL_SPOTS) == "table" and ns.LABEL_SPOTS[st.mapID] or nil
    local p = own and own[key]
    if type(p) ~= "table" then p = type(builtIn) == "table" and builtIn[key] or nil end
    -- a dungeon spot a little off (the client's entrance spot can differ by a hair)
    local kx, ky, kn = key:match("^D(%d+):(%d+):(%d+)$")
    if type(p) ~= "table" and kx then
        kx, ky = tonumber(kx), tonumber(ky)
        for _, t in ipairs({ own or {}, builtIn or {} }) do
            for k, v in pairs(t) do
                local x, y, n = k:match("^D(%d+):(%d+):(%d+)$")
                if n == kn and abs(tonumber(x) - kx) <= 3 and abs(tonumber(y) - ky) <= 3 and type(v) == "table" then
                    p = v; break
                end
            end
            if type(p) == "table" then break end
        end
    end
    if type(p) ~= "table" or not (num(p[1]) and num(p[2])) then return nil end
    return (p[1] * st.W - (st.cx0 or 0)) * st.s, (p[2] * st.H - (st.cy0 or 0)) * st.s
end

local function savedSpot(key)
    return Extras.SavedSpotView(ctx, key)
end

-- the key of a flight point label: its spot on the continent
function Extras.FlightLabelKey(node)
    if not (node and num(node.x) and num(node.y)) then return nil end
    return "f" .. floor(node.x * 1000) .. ":" .. floor(node.y * 1000)
end

local function saveSpot(key, x, y)
    local t = spotTable(ctx.mapID, true)
    local nx = (x / ctx.s + ctx.cx0) / ctx.W
    local ny = (y / ctx.s + ctx.cy0) / ctx.H
    t[key] = { floor(nx * 10000 + 0.5) / 10000, floor(ny * 10000 + 0.5) / 10000 }
end

function Extras.ResetSpots(mapID)
    if type(ns.DB.labelPos) ~= "table" then return end
    if mapID then ns.DB.labelPos[mapID] = nil else ns.DB.labelPos = nil end
end

local handlePool, handlesUsed = {}, 0
local function hideHandles()
    for _, h in ipairs(handlePool) do h:Hide(); h:SetScript("OnUpdate", nil) end
    handlesUsed = 0
end

local function cursorInCanvas()
    local x, y = GetCursorPosition()
    local sc = ctx.canvas:GetEffectiveScale()
    return x / sc - (ctx.canvas:GetLeft() or 0), (ctx.canvas:GetTop() or 0) - y / sc
end

local function handleDown(self, button)
    if button ~= "LeftButton" or not ctx then return end
    local mx, my = cursorInCanvas()
    self.grab = { mx - self.x, my - self.y }
    self:SetScript("OnUpdate", function(me)
        if not ctx then me:SetScript("OnUpdate", nil); return end
        local cx, cy = cursorInCanvas()
        me.x, me.y = cx - me.grab[1], cy - me.grab[2]
        me:ClearAllPoints()
        me:SetPoint("TOPLEFT", ctx.canvas, "TOPLEFT", me.x, -me.y)
        if me.place then me.place(me.x, me.y) end
    end)
end

local function handleUp(self)
    self:SetScript("OnUpdate", nil)
    if not (self.grab and ctx) then return end
    self.grab = nil
    saveSpot(self.key, self.x + self.w / 2, self.y + self.h / 2)
    if ns.ScheduleRender then ns.ScheduleRender() end
end

-- a box over a label that can be dragged while the edit mode is on
local function addHandle(x, y, w, h, key, place)
    handlesUsed = handlesUsed + 1
    local hd = handlePool[handlesUsed]
    if not hd then
        hd = CreateFrame("Button", nil, markerLayer)
        hd:EnableMouse(true)
        hd.box = hd:CreateTexture(nil, "BACKGROUND")
        hd.box:SetAllPoints()
        hd.box:SetColorTexture(0.35, 0.75, 1, 0.18)
        hd:SetScript("OnMouseDown", handleDown)
        hd:SetScript("OnMouseUp", handleUp)
        handlePool[handlesUsed] = hd
    end
    hd.x, hd.y, hd.w, hd.h, hd.key, hd.place = x, y, w, h, key, place
    hd:SetSize(w, h)
    hd:ClearAllPoints()
    hd:SetPoint("TOPLEFT", ctx.canvas, "TOPLEFT", x, -y)
    hd:SetFrameLevel(markerLayer:GetFrameLevel() + 20)
    hd:Show()
end

-- drag a label that takes the mouse itself (flight point labels): follows the
-- cursor until the left button is let go, then the spot is saved
local dragFrame
function Extras.BeginDrag(x, y, w, h, key, place)
    if not (ctx and markerLayer and Extras.editMode and key and place) then return end
    local mx, my = cursorInCanvas()
    local d = { x = x, y = y, gx = mx - x, gy = my - y }
    dragFrame = dragFrame or CreateFrame("Frame", nil, markerLayer)
    dragFrame:Show()
    dragFrame:SetScript("OnUpdate", function(f)
        if not ctx then f:SetScript("OnUpdate", nil); return end
        local cx, cy = cursorInCanvas()
        d.x, d.y = cx - d.gx, cy - d.gy
        place(d.x, d.y)
        if not IsMouseButtonDown("LeftButton") then
            f:SetScript("OnUpdate", nil)
            saveSpot(key, d.x + w / 2, d.y + h / 2)
            if ns.ScheduleRender then ns.ScheduleRender() end
        end
    end)
end

function Extras.AddHandle(x, y, w, h, key, place)
    if ctx and markerLayer and Extras.editMode then addHandle(x, y, w, h, key, place) end
end

-- icons that would sit on a flight point or on each other move apart up/down
local function spreadMarkers(items, pins, vh)
    local function push(it, need, dir)
        it.py = max(it.size / 2, min(vh - it.size / 2, it.py + dir * need))
    end
    for _ = 1, 30 do
        local moved = false
        for i, a in ipairs(items) do
            for _, p in ipairs(pins) do
                local gap = a.size / 2 + p.r + 2
                local dx, dy = a.px - p.px, a.py - p.py
                if abs(dx) < gap and abs(dy) < gap then
                    push(a, gap - abs(dy) + 0.5, (dy > 0 or (dy == 0 and i % 2 == 0)) and 1 or -1)
                    moved = true
                end
            end
            for j = i + 1, #items do
                local b = items[j]
                local gap = (a.size + b.size) / 2 + 2
                local dx, dy = a.px - b.px, a.py - b.py
                if abs(dx) < gap and abs(dy) < gap then
                    local need = (gap - abs(dy)) / 2 + 0.5
                    local dir = dy >= 0 and 1 or -1
                    push(a, need, dir); push(b, need, -dir)
                    moved = true
                end
            end
        end
        if not moved then return end
    end
end

-----------------------------------------------------------------------------
-- Season touch: petals (spring), sparkles (summer), leaves (autumn) and snow
-- (winter) drifting slowly over the map. Few, small and see-through, under
-- the names and markers. Runs only while the map is shown.
-----------------------------------------------------------------------------
local FX = {
    Spring = { file = "Season-Petal",   n = 12, size = { 7, 11 },  fall = { 10, 20 }, sway = 16, spin = 1.2, alpha = 0.75 },
    Summer = { file = "Season-Sparkle", n = 10, size = { 6, 11 },  twinkle = true, alpha = 0.8 },
    Autumn = { file = "Season-Leaf",    n = 10, size = { 9, 13 },  fall = { 12, 22 }, sway = 20, spin = 1.6, alpha = 0.8 },
    Winter = { file = "Season-Snow",    n = 28, size = { 3, 7 },   fall = { 8, 18 },  sway = 7,  spin = 0,   alpha = 0.75 },
}
local fxFrame, fxSeason, fxDots = nil, nil, {}
local fxW, fxH = 0, 0

local function rnd(a, b) return a + math.random() * (b - a) end

local function fxSpawn(d, spec, anywhere)
    d.size = rnd(spec.size[1], spec.size[2])
    d.x = rnd(0, fxW)
    d.y = anywhere and rnd(0, fxH) or -d.size
    d.speed = spec.fall and rnd(spec.fall[1], spec.fall[2]) or 0
    d.phase, d.freq = rnd(0, 6.28), rnd(0.6, 1.4)
    d.angle, d.turn = rnd(0, 6.28), rnd(-1, 1) * (spec.spin or 0)
    d.life, d.age = rnd(1.6, 3.2), anywhere and rnd(0, 3) or 0
    d.tex:SetSize(d.size, d.size)
end

local function fxUpdate(_, elapsed)
    local spec = FX[fxSeason]
    if not spec or not (ctx and ctx.canvas) then return end
    elapsed = min(elapsed or 0, 0.1)
    for _, d in ipairs(fxDots) do
        if d.tex:IsShown() then
            d.age = d.age + elapsed
            if spec.twinkle then
                local t = d.age / d.life
                if t >= 1 then fxSpawn(d, spec, true); d.age = 0; t = 0 end
                d.tex:SetAlpha(spec.alpha * math.sin(t * math.pi))
            else
                d.y = d.y + d.speed * elapsed
                d.x = d.x + math.sin(d.age * d.freq + d.phase) * spec.sway * elapsed
                d.angle = d.angle + d.turn * elapsed
                if d.y > fxH + d.size or d.x < -20 or d.x > fxW + 20 then fxSpawn(d, spec, false) end
                if d.tex.SetRotation then d.tex:SetRotation(d.angle) end
            end
            d.tex:ClearAllPoints()
            d.tex:SetPoint("CENTER", fxFrame, "TOPLEFT", d.x, -d.y)
        end
    end
end

local function stopFx()
    if fxFrame then fxFrame:SetScript("OnUpdate", nil); fxFrame:Hide() end
    fxSeason = nil
end

-- (re)start for the shown continent; keeps running across re-draws
local function startFx(c, level)
    local season = ns.DB.seasonFx ~= false and Extras.Season and Extras.Season() or nil
    local spec = season and FX[season]
    if not spec then stopFx(); return end
    if not fxFrame then
        fxFrame = CreateFrame("Frame", nil, c.canvas)
        fxFrame:EnableMouse(false)
    end
    fxFrame:SetParent(c.canvas)
    fxFrame:ClearAllPoints()
    fxFrame:SetAllPoints(c.canvas)
    fxFrame:SetFrameLevel(level)
    fxW, fxH = c.vw or 0, c.vh or 0
    if fxSeason ~= season then
        fxSeason = season
        for i = 1, max(spec.n, #fxDots) do
            local d = fxDots[i]
            if not d then
                d = { tex = fxFrame:CreateTexture(nil, "ARTWORK") }
                fxDots[i] = d
            end
            if i <= spec.n then
                d.tex:SetTexture((ns.MEDIA or "") .. spec.file)
                d.tex:SetAlpha(spec.alpha)
                d.tex:Show()
                fxSpawn(d, spec, true)
            else
                d.tex:Hide()
            end
        end
    end
    fxFrame:Show()
    fxFrame:SetScript("OnUpdate", fxUpdate)
end

local function clearLayers()
    if layer then
        for _, fs in ipairs(namePool) do fs:Hide() end
        for _, t in ipairs(layer.hl) do t:Hide() end
        layer:SetScript("OnUpdate", nil)
    end
    if markerLayer then hideMarkers(1); hideDots(1); hideHandles() end
    hoverZone, ctx = nil, nil
end

function Extras.Clear()
    clearLayers()
    stopFx()
end

-- zone highlight under the cursor
local function showHighlight(zoneID, nx, ny)
    local hl = layer.hl
    if not zoneID or not C_Map.GetMapHighlightInfoAtPosition then
        for _, t in ipairs(hl) do t:Hide() end
        return
    end
    local ok, fileID, atlasID, px, py, tx, ty, sx, sy = call(C_Map.GetMapHighlightInfoAtPosition, ctx.mapID, nx, ny)
    if not ok or not (num(tx) and num(ty) and num(sx) and num(sy)) or tx <= 0 or ty <= 0 then
        for _, t in ipairs(hl) do t:Hide() end
        return
    end
    local x0, y0 = view(sx, sy)
    for _, t in ipairs(hl) do
        local set = false
        if num(fileID) and fileID > 0 then
            set = t:SetTexture(fileID) ~= false
            t:SetTexCoord(0, num(px) and px > 0 and px or 1, 0, num(py) and py > 0 and py or 1)
        elseif atlasID and t.SetAtlas and C_Texture and C_Texture.GetAtlasElement then
            local okA, atlas = call(C_Texture.GetAtlasElement, atlasID)
            if okA and type(atlas) == "string" then set = t:SetAtlas(atlas) ~= false end
        end
        if set then
            t:SetBlendMode("ADD")
            t:SetVertexColor(ZONE_ACCENT[1], ZONE_ACCENT[2], ZONE_ACCENT[3], 1)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", ctx.canvas, "TOPLEFT", x0, -y0)
            t:SetSize(tx * ctx.W * ctx.s, ty * ctx.H * ctx.s)
            t:Show()
        else
            t:Hide()
        end
    end
end

local function onUpdate(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    if self.t < 0.05 then return end
    self.t = 0
    if not ctx or not ctx.zones then return end
    local canvas = ctx.canvas
    local zoneID, nx, ny
    if canvas:IsVisible() and canvas:IsMouseOver() and not (ctx.isBusy and ctx.isBusy()) then
        local cx, cy = GetCursorPosition()
        local es = canvas:GetEffectiveScale()
        local left, top = canvas:GetLeft(), canvas:GetTop()
        if num(cx) and num(es) and es > 0 and left and top then
            local vx, vy = cx / es - left, top - cy / es
            nx, ny = (vx / ctx.s + ctx.cx0) / ctx.W, (vy / ctx.s + ctx.cy0) / ctx.H
            if inUnit(nx, ny) then zoneID = zoneAt(ctx.mapID, nx, ny, ctx.zones) end
        end
    end
    if zoneID == hoverZone then return end
    if hoverZone and ctx.zones[hoverZone] and ctx.zones[hoverZone].fs then styleName(ctx.zones[hoverZone].fs, ctx.zones[hoverZone], false) end
    hoverZone = zoneID
    if zoneID and ctx.zones[zoneID] and ctx.zones[zoneID].fs then styleName(ctx.zones[zoneID].fs, ctx.zones[zoneID], true) end
    showHighlight(zoneID, nx, ny)
end

-- c = { canvas, mapID, s, cx0, cy0, W, H, vw, vh, nodes, pins = { {px,py,r}, ... },
--       labels = { {x,y,w,h}, ... }, fontSize, isVisible(node), isBusy(), onPick(node) }
function Extras.Render(c)
    clearLayers()
    if not (c and c.canvas and c.mapID) then stopFx(); return end
    ensureLayers(c.canvas)
    ctx = c
    local base = c.canvas:GetFrameLevel()
    pcall(startFx, c, base + 1)
    layer:SetFrameLevel(base + 2)
    markerLayer:SetFrameLevel(base + 4)
    local rects = {}
    for _, p in ipairs(c.pins or {}) do rects[#rects + 1] = { p.px - p.r - 3, p.py - p.r - 3, p.r * 2 + 6, p.r * 2 + 6 } end
    for _, r in ipairs(c.labels or {}) do rects[#rects + 1] = r end

    local zones = Extras.GetZones(c.mapID)
    ctx.zones = zones
    local fontSize = max(10, min(13, (c.fontSize or 12)))

    -- markers first: they belong to a spot, names can move around them
    local items = {}
    local function collect(m, size, text)
        local px, py = view(m.x, m.y)
        if px < -size or py < -size or px > c.vw + size or py > c.vh + size then return end
        items[#items + 1] = { m = m, size = size, text = text, px = px, py = py, ox = px, oy = py }
    end
    if ns.DB.dungeonMarks then
        local ok, list = pcall(Extras.CollectDungeons, c.mapID, zones)
        for _, m in ipairs(ok and list or {}) do
            collect(m, 20, m.levels and (m.name .. " " .. m.levels) or m.name)
        end
    end
    if ns.DB.questMarks then
        local ok, list = pcall(Extras.CollectQuests, c.mapID)
        if ok and #list > 0 then
            for _, g in ipairs(groupQuests(list)) do collect(g, g.done and 22 or 18) end
        end
    end
    -- icons stay on their own spots (they may overlap)

    local used = 0
    for _, it in ipairs(items) do
        local m, size, px, py = it.m, it.size, it.px, it.py
        used = used + 1
        local b = markerButton(used)
        it.b = b
        b.data, b.quests = m, m.quests
        b:SetSize(size, size)
        b.icon:SetSize(size, size)
        b.bg:SetSize(size, size)
        b.glow:SetShown(false)
        b.glowAlpha = 0
        setIcon(b, m)
        b:ClearAllPoints()
        b:SetPoint("CENTER", c.canvas, "TOPLEFT", px, -py)
        b:SetFrameLevel(base + 4)
        b:SetAlpha((m.kind == "quest" and not m.done) and 0.75 or 1)
        b:Show()
        b.text:Hide(); b.bullet:Hide()
        rects[#rects + 1] = { px - size / 2, py - size / 2, size, size }
        -- moved off its spot: a short dotted line back to the real spot
        if abs(py - it.oy) > size * 0.6 then
            local dir = py > it.oy and -1 or 1
            dottedLine(px, py + dir * size / 2, it.ox, it.oy, 0.85, 0.85, 0.85, 0.7)
        end
    end

    -- dungeon names: out at the sides of the land (like the flight point
    -- labels), a dot on the icon's side, joined to the entrance by a dotted line
    local function landEdges(y0, y1)
        if not (Extras.LandSpan and c.s and c.s > 0) then return nil end
        local l, r = Extras.LandSpan(c.mapID, y0 / c.s + (c.cy0 or 0), y1 / c.s + (c.cy0 or 0))
        if not l then return nil end
        return (l - (c.cx0 or 0)) * c.s, (r - (c.cx0 or 0)) * c.s
    end
    local labeled = {}
    for _, it in ipairs(items) do
        if it.text then labeled[#labeled + 1] = it end
    end
    table.sort(labeled, function(p, q) return p.py < q.py end)
    local GAP = 10
    for _, it in ipairs(labeled) do
        local b, size, px, py = it.b, it.size, it.px, it.py
        b.text:SetText(it.text)
        setMapFont(b.text, max(9, fontSize - 1))
        b.text:SetTextColor(DUNGEON_TEXT[1], DUNGEON_TEXT[2], DUNGEON_TEXT[3], 1)
        local tw, th = (b.text:GetStringWidth() or 0) + 12, (b.text:GetStringHeight() or 9) + 2
        local l0, r0 = landEdges(py - 4, py + 4)
        local onLeft = l0 and (px - l0) < (r0 - px) or (px < c.vw / 2)
        local found
        it.key = it.m.spotKey or ("D" .. floor(it.m.x * 1000) .. ":" .. floor(it.m.y * 1000))
        local sx, sy = savedSpot(it.key)
        if sx then
            found = { sx - tw / 2, sy - th / 2 }
            onLeft = sx < px
        end
        -- the label's height: its own first, then a little up/down
        for step = 0, found and -1 or 24 do
            local dy = (step % 2 == 0 and 1 or -1) * floor((step + 1) / 2) * (th + 1)
            local ty = py - th / 2 + dy
            if ty >= 0 and ty + th <= c.vh then
                local l, r = landEdges(ty - 3, ty + th + 3)
                local tx
                if onLeft then
                    tx = min(l or (px - size), px - size / 2) - GAP - tw
                else
                    tx = max(r or (px + size), px + size / 2) + GAP
                end
                -- pushed out past flight point labels and other text on that side
                for _ = 1, 12 do
                    if tx < 0 or tx + tw > c.vw or not hitAny(tx, ty, tw, th, rects) then break end
                    tx = tx + (onLeft and -(th + 4) or (th + 4))
                end
                if tx >= 0 and tx + tw <= c.vw and not hitAny(tx, ty, tw, th, rects) then
                    found = { tx, ty }
                    break
                end
            end
        end
        if found then it.lab = { found[1], found[2], tw, th } end
    end

    -- entrances on one spot: their names in one straight column, dots in line
    local stacks = {}
    for _, it in ipairs(labeled) do
        local spot = it.lab and it.key:match("^(D%d+:%d+):%d+$")
        if spot then
            stacks[spot] = stacks[spot] or {}
            table.insert(stacks[spot], it)
        end
    end
    for _, list in pairs(stacks) do
        if #list > 1 then
            local lefts, sumBx, sumCy = 0, 0, 0
            for _, it in ipairs(list) do
                local tx, ty, tw, th = it.lab[1], it.lab[2], it.lab[3], it.lab[4]
                local left = tx + tw / 2 < it.px
                if left then lefts = lefts + 1 end
                sumBx = sumBx + (left and (tx + tw - 4) or (tx + 4))
                sumCy = sumCy + ty + th / 2
            end
            local left = lefts * 2 >= #list
            local bx = sumBx / #list
            table.sort(list, function(p, q) return p.lab[2] < q.lab[2] end)
            local total = 0
            for _, it in ipairs(list) do total = total + it.lab[4] end
            total = total + (#list - 1)
            local y = sumCy / #list - total / 2
            for _, it in ipairs(list) do
                local tw, th = it.lab[3], it.lab[4]
                it.lab[1] = left and (bx + 4 - tw) or (bx - 4)
                it.lab[2] = y
                y = y + th + 1
            end
        end
    end

    for _, it in ipairs(labeled) do
        if it.lab then
            local b, size, px, py = it.b, it.size, it.px, it.py
            local tx, ty, tw, th = it.lab[1], it.lab[2], it.lab[3], it.lab[4]
            rects[#rects + 1] = { tx, ty, tw, th }
            local function place(x, y)
                local left = x + tw / 2 < px
                local bx, by = left and (x + tw - 4) or (x + 4), y + th / 2
                b.bullet:ClearAllPoints()
                b.bullet:SetPoint("CENTER", c.canvas, "TOPLEFT", bx, -by)
                b.text:ClearAllPoints()
                if left then
                    b.text:SetPoint("RIGHT", c.canvas, "TOPLEFT", x + tw - 9, -by)
                else
                    b.text:SetPoint("LEFT", c.canvas, "TOPLEFT", x + 9, -by)
                end
                return bx, by
            end
            local bx, by = place(tx, ty)
            b.bullet:SetVertexColor(DUNGEON_TEXT[1], DUNGEON_TEXT[2], DUNGEON_TEXT[3], 1)
            b.bullet:Show()
            b.text:SetAlpha(1)
            b.text:Show()
            local dx, dy = bx - px, by - py
            local len = sqrt(dx * dx + dy * dy)
            if len > size / 2 + 6 then
                dottedLine(px + dx / len * (size / 2 + 1), py + dy / len * (size / 2 + 1), bx, by,
                    DUNGEON_TEXT[1], DUNGEON_TEXT[2], DUNGEON_TEXT[3], 0.6)
            end
            if Extras.editMode then addHandle(tx, ty, tw, th, it.key, place) end
        end
    end
    hideMarkers(used + 1)

    if zones and ns.DB.zoneNames then
        local list = {}
        for _, z in pairs(zones) do
            z.fs = nil
            list[#list + 1] = z
        end
        -- big zones first: they have the most room to move their names
        table.sort(list, function(a, b)
            if a.order ~= b.order then return a.order > b.order end
            return a.id < b.id
        end)
        for i, z in ipairs(list) do
            local fs = nameString(i)
            setMapFont(fs, fontSize)
            fs:SetText(z.name)
            fs:SetWidth(0)
            local px, py = view(z.lx, z.ly)
            local key = "z" .. tostring(z.id)
            local sx, sy = savedSpot(key)
            if sx then px, py = sx, sy end
            if px >= 0 and py >= 0 and px <= c.vw and py <= c.vh then
                local x, y, free
                local w, h = (fs:GetStringWidth() or 0) + 4, (fs:GetStringHeight() or 10) + 2
                if sx then
                    x, y, free = sx, sy, true
                    rects[#rects + 1] = { x - w / 2, y - h / 2, w, h }
                else
                    x, y, free = placeText(fs, px, py, rects, c.vw, c.vh)
                end
                fs.crowded = not free and not Extras.editMode
                fs:ClearAllPoints()
                fs:SetPoint("CENTER", c.canvas, "TOPLEFT", x, -y)
                z.fs = fs
                styleName(fs, z, false)
                if Extras.editMode then
                    addHandle(x - w / 2, y - h / 2, w, h, key, function(nx, ny)
                        fs:ClearAllPoints()
                        fs:SetPoint("CENTER", c.canvas, "TOPLEFT", nx + w / 2, -(ny + h / 2))
                    end)
                end
            else
                fs:Hide()
            end
        end
        for i = #list + 1, #namePool do namePool[i]:Hide() end
    end
    if zones and ns.DB.zoneNames then layer:SetScript("OnUpdate", onUpdate) end
end

ns.BuildWorldMapArt = Extras.BuildWorldArt
ns.ProjectFlightNodesToWorldMap = Extras.ProjectNodes
