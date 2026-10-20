--===========================================================================
-- EzWoW - Flight Map
-- Core/Init.lua : Namespace, EzWoW Style Palette, Time/Coin Formatters & Button Builder
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local CoreConfig = ns.CoreConfig or {}
ns.CoreConfig = CoreConfig

_G.EzWoW_FlightMap = ns
_G.EzWoW_FlightMap = ns

ns.ADDON_NAME = ADDON_NAME or "EzWoW-FlightMap"
ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs

local STYLE = {
    bgPrimary   = { 0.071, 0.094, 0.122, 0.96 }, 
    bgSecondary = { 0.114, 0.157, 0.192, 0.94 }, 
    border      = { 0.204, 0.298, 0.357, 1.00 }, 
    textBody    = { 0.929, 0.957, 0.969, 1.00 }, 
    textMuted   = { 0.655, 0.725, 0.773, 1.00 }, 
    accent      = { 0.522, 0.725, 1.000, 1.00 }, 
    accentHex   = "85B9FF",
    warning     = { 0.906, 0.486, 0.439, 1.00 }, 
    disabled    = { 0.388, 0.447, 0.482, 1.00 }, 
}
ns.STYLE = STYLE

local MEDIA = "Interface\\AddOns\\" .. ns.ADDON_NAME .. "\\Media\\"
ns.MEDIA = MEDIA

ns.CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
local FPS = Enum and Enum.FlightPathState
ns.FPS_CURRENT     = (FPS and FPS.Current) or 0
ns.FPS_REACHABLE   = (FPS and FPS.Reachable) or 1
ns.FPS_UNREACHABLE = (FPS and FPS.Unreachable) or 2

ns.ICON_FILE = {
    CURRENT   = MEDIA .. "Pin-Current",
    REACHABLE = MEDIA .. "Pin-Flight",
    DISTANT   = MEDIA .. "Pin-Distant",
}
ns.ICON_FALLBACK = {
    CURRENT   = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green",
    REACHABLE = "Interface\\TaxiFrame\\UI-Taxi-Icon-White",
    DISTANT   = "Interface\\TaxiFrame\\UI-Taxi-Icon-White",
}
ns.ICON_COLOR = {
    CURRENT   = { 0.2, 1.0, 0.2 },
    REACHABLE = { 1.0, 0.85, 0.4 },
    DISTANT   = { 0.5, 0.5, 0.5 },
}
ns.GLOW_FILE     = MEDIA .. "Pin-Glow"
ns.GEAR_FILE     = MEDIA .. "Gear"
ns.RING_FILE     = MEDIA .. "Pin-Selected"
ns.LIST_FILE     = MEDIA .. "List"
ns.STAR_ON_FILE  = MEDIA .. "Star-On"
ns.STAR_OFF_FILE = MEDIA .. "Star-Off"
ns.STAR_INLINE   = "|T" .. ns.STAR_ON_FILE .. ":0|t "

ns.BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}
ns.LABEL_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

ns.PAD, ns.TITLE_H, ns.FOOT_H = 10, 30, 22
ns.PIN_SIZE, ns.PIN_SIZE_CURRENT = 22, 26
ns.MIN_WIDTH = 340
ns.LIST_W, ns.LIST_GAP = 252, 8
ns.BLIZZARD_FRAMES = { "TaxiFrame", "FlightMapFrame" }

ns.cur = { open = false }
ns.hover = { segments = {}, total = 0 }
ns.hidden = {}
ns.preAlpha = {}
ns.allSettingRefreshers = {}

ns.defaults = {
    lang              = "auto",
    enabled           = true,
    skipGossip        = true,
    crop              = false,
    showUnreachable   = true,
    labels            = true,
    labelSize         = 12,
    scale             = 1.0,
    alpha             = 1.0,
    flightBar         = true,
    arrivalAlert      = true,
    confirmFlight     = false,
    worldMapFlights   = true,
    worldMapAutoAlign = true,
    autoSearch        = false,
    showList          = true,
    listSort          = "name",
    pulse             = true,
    point             = nil,
    barPoint          = nil,
}

function CoreConfig.resolveFiniteNumber(v)
    return type(v) == "number" and v == v and abs(v) < math.huge
end
ns.IsFiniteNumber = CoreConfig.resolveFiniteNumber

function CoreConfig.validPoint(pt)
    local alphaVal = {
        TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
    }
    return type(pt) == "table" and alphaVal[pt[1]] and alphaVal[pt[2]] and CoreConfig.resolveFiniteNumber(pt[3]) and CoreConfig.resolveFiniteNumber(pt[4])
end
ns.IsNormalizedMapCoordinate = CoreConfig.validPoint

function ns.InitDB()
    if type(_G.EzWoW_FlightMapDB) ~= "table" and type(_G.EzWoW_FlightMapDB) == "table" then
        _G.EzWoW_FlightMapDB = _G.EzWoW_FlightMapDB
    end
    if type(_G.EzWoW_FlightMapDB) ~= "table" then
        _G.EzWoW_FlightMapDB = {}
    end
    _G.EzWoW_FlightMapDB = _G.EzWoW_FlightMapDB
    local CONST_DB = _G.EzWoW_FlightMapDB
    ns.DB = CONST_DB

    for entryKey, v in pairs(ns.defaults) do
        if type(CONST_DB[entryKey]) ~= type(v) then CONST_DB[entryKey] = v end
    end
    if CONST_DB.lang ~= "auto" and ns.LOCALES and not ns.LOCALES[CONST_DB.lang] then
        CONST_DB.lang = "auto"
    end
    if type(CONST_DB.times) ~= "table" then CONST_DB.times = {} end
    if type(CONST_DB.flightSpeeds) ~= "table" then CONST_DB.flightSpeeds = {} end
    if type(CONST_DB.favorites) ~= "table" then CONST_DB.favorites = {} end
    if type(CONST_DB.recent) ~= "table" then CONST_DB.recent = {} end

    CONST_DB.scale = CoreConfig.resolveFiniteNumber(CONST_DB.scale) and max(0.5, min(1.2, CONST_DB.scale)) or ns.defaults.scale
    CONST_DB.alpha = CoreConfig.resolveFiniteNumber(CONST_DB.alpha) and max(0.3, min(1.0, CONST_DB.alpha)) or ns.defaults.alpha
    if CONST_DB.fullMapRevision ~= 1 then
        CONST_DB.crop = false
        CONST_DB.fullMapRevision = 1
    end
    if CONST_DB.destinationUI ~= 1 then
        CONST_DB.labels = true
        if CoreConfig.resolveFiniteNumber(CONST_DB.labelSize) then CONST_DB.labelSize = max(12, CONST_DB.labelSize) end
        CONST_DB.destinationUI = 1
    end
    CONST_DB.labelSize = CoreConfig.resolveFiniteNumber(CONST_DB.labelSize) and max(8, min(14, floor(CONST_DB.labelSize))) or ns.defaults.labelSize
    CONST_DB.art, CONST_DB.calib = nil, nil
    CONST_DB.flightDataRevision = 2
    if CONST_DB.listSort ~= "name" and CONST_DB.listSort ~= "time" and CONST_DB.listSort ~= "fare" then
        CONST_DB.listSort = "name"
    end
    if not CoreConfig.validPoint(CONST_DB.point) then CONST_DB.point = nil end
    if not CoreConfig.validPoint(CONST_DB.barPoint) then CONST_DB.barPoint = nil end
    return CONST_DB
end

-----------------------------------------------------------------------------
-- Print
-----------------------------------------------------------------------------
function ns.Print(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff85B9FFEzWoW - Flight Map|r: " .. tostring(text))
    end
end

function ns.ExtractShortStationName(name)
    return (name and name:match("^([^,]+)")) or name or "?"
end

function ns.FormatFlightDurationText(sec, approx)
    local L = ns.L
    sec = floor(sec + 0.5)
    if approx then
        return L.APPROX:format(L.MIN:format(max(1, floor(sec / 60 + 0.5))))
    end
    if sec < 60 then return L.SEC:format(sec) end
    local matchRef, stateFlag = floor(sec / 60), sec % 60
    if stateFlag == 0 then return L.MIN:format(matchRef) end
    return L.MIN_SEC:format(matchRef, stateFlag)
end

function ns.FormatSecondsAsClock(sec)
    sec = max(0, floor(sec + 0.5))
    return ("%d:%02d"):format(floor(sec / 60), sec % 60)
end

function ns.FormatCopperAsCoinString(cost, size)
    local L = ns.L
    if not CoreConfig.resolveFiniteNumber(cost) or cost < 0 then return L.COST_UNKNOWN end
    cost = floor(cost)
    if cost == 0 then return L.FREE end
    size = CoreConfig.resolveFiniteNumber(size) and max(8, min(16, floor(size))) or 12
    local gold, silver, copper = floor(cost / 10000), floor(cost / 100) % 100, cost % 100
    local parts = {}
    local function add(value, kind)
        if value > 0 then
            local texture = "Interface\\MoneyFrame\\UI-" .. kind .. "Icon"
            parts[#parts + 1] = ("%d|T%s:%d:%d:0:0|t"):format(value, texture, size, size)
        end
    end
    add(gold, "Gold")
    add(silver, "Silver")
    add(copper, "Copper")
    return table.concat(parts, " ")
end

function ns.SetFontSize(fs, size)
    local foVal = _G.GameFontHighlightSmall
    if foVal and foVal.GetFont and fs and fs.SetFont then
        local file, _, flags = foVal:GetFont()
        if file then fs:SetFont(file, size, flags or "") end
    end
end

function ns.CreateStyledButton(parent, w, h, isAccent, onClick)
    local buttonWidget = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    buttonWidget:SetSize(w, h)
    if buttonWidget.SetBackdrop then
        buttonWidget:SetBackdrop(ns.LABEL_BACKDROP)
    end
    local formatLocalizedLabel = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formatLocalizedLabel:SetPoint("CENTER", 0, 0)
    buttonWidget.label = formatLocalizedLabel
    local function applyNormalButtonLook()
        if not buttonWidget.SetBackdropColor then return end
        if isAccent then
            buttonWidget:SetBackdropColor(0.14, 0.22, 0.34, 0.96)
            buttonWidget:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
            formatLocalizedLabel:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
        else
            buttonWidget:SetBackdropColor(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.96)
            buttonWidget:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
            formatLocalizedLabel:SetTextColor(STYLE.textBody[1], STYLE.textBody[2], STYLE.textBody[3])
        end
    end
    applyNormalButtonLook()
    buttonWidget:SetScript("OnEnter", function(self)
        if not self.SetBackdropColor then return end
        self:SetBackdropColor(0.20, 0.29, 0.42, 1)
        self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
    end)
    buttonWidget:SetScript("OnLeave", applyNormalButtonLook)
    function buttonWidget:SetText(txt) formatLocalizedLabel:SetText(txt or "") end
    function buttonWidget:GetText() return formatLocalizedLabel:GetText() end
    buttonWidget:SetScript("OnMouseDown", function() formatLocalizedLabel:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() formatLocalizedLabel:SetPoint("CENTER", 0, 0) end)
    if onClick then buttonWidget:SetScript("OnClick", onClick) end
    return buttonWidget
end

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
CoreConfig.FormatCopperAsCoinString = ns.FormatCopperAsCoinString
CoreConfig.IsFiniteNumber = ns.IsFiniteNumber
CoreConfig.FormatSecondsAsClock = ns.FormatSecondsAsClock
CoreConfig.FormatFlightDurationText = ns.FormatFlightDurationText
CoreConfig.CreateStyledButton = ns.CreateStyledButton
CoreConfig.ExtractShortStationName = ns.ExtractShortStationName
CoreConfig.IsNormalizedMapCoordinate = ns.IsNormalizedMapCoordinate
