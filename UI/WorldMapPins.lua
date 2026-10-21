--===========================================================================
-- EzWoW - Flight Map
-- UI/WorldMapPins.lua : WorldMap Flight Node Pins, Dock Toggle & Faction Filter Popover
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local WorldMapPinProvider = ns.WorldMapPinProvider or {}
ns.WorldMapPinProvider = WorldMapPinProvider
local PIN = "EzWoWFlightMapPinTemplate"

local STYLE = ns.STYLE or {
    bgPrimary   = { 0.071, 0.094, 0.122, 0.96 },
    bgSecondary = { 0.114, 0.157, 0.192, 0.94 },
    border      = { 0.204, 0.298, 0.357, 1.00 },
    textBody    = { 0.929, 0.957, 0.969, 1.00 },
    textMuted   = { 0.655, 0.725, 0.773, 1.00 },
    accent      = { 0.522, 0.725, 1.000, 1.00 },
}

function WorldMapPinProvider.resolveText()
    if ns.GetWorldMapText then
        return ns.GetWorldMapText()
    end
    return {
        title = "EzWoW - Flight Map · Flight Master",
        toggle = "Flight masters",
        move = "Drag to move",
        openSettings = "Left-click: Expand/collapse filter panel\nRight-click: Reset icon position\nDrag: Move icon",
        toggleHelp = "Show or hide flight masters on world and continent maps.",
        alliance = "Alliance", horde = "Horde", neutral = "Neutral",
        unknown = "Unknown faction", undiscovered = "Flight path not discovered",
        enemy = "Opposing faction flight master",
        visit = "Speak to this flight master to fly",
        autoAlign = "Auto-align on map",
    }
end

function WorldMapPinProvider.resolveFactionInfo(factionID)
    local resolvedValue = WorldMapPinProvider.resolveText()
    if factionID == 0 then return { resolvedValue.neutral, 1, 0.82, 0.2 } end
    if factionID == 1 then return { resolvedValue.horde, 1, 0.2, 0.15 } end
    if factionID == 2 then return { resolvedValue.alliance, 0.2, 0.6, 1 } end
    return { resolvedValue.unknown, 0.7, 0.7, 0.7 }
end

local WorldMapDataProvider, mapToggle, autoAlignToggle, switchLabel
local factionToggles = {}

function WorldMapPinProvider.isFeatureEnabled()
    return EzWoW_FlightMapDB and EzWoW_FlightMapDB.worldMapFlights ~= false
end

function WorldMapPinProvider.hasAutoAlign()
    return not EzWoW_FlightMapDB or EzWoW_FlightMapDB.worldMapAutoAlign ~= false
end

function WorldMapPinProvider.resolveFactionSettings()
    if not EzWoW_FlightMapDB then return end
    local radioOptionGroup = UnitFactionGroup("player") or "Neutral"
    if type(EzWoW_FlightMapDB.worldMapFactionFilters) ~= "table" then
        EzWoW_FlightMapDB.worldMapFactionFilters = {}
    end
    local filters = EzWoW_FlightMapDB.worldMapFactionFilters
    if type(filters[radioOptionGroup]) ~= "table" then filters[radioOptionGroup] = {} end
    local options = filters[radioOptionGroup]
    local defaults = {[0] = true, [1] = radioOptionGroup == "Horde", [2] = radioOptionGroup == "Alliance"}
    for entityID = 0, 2 do
        if type(options[entityID]) ~= "boolean" then options[entityID] = defaults[entityID] end
    end
    return options
end

function WorldMapPinProvider.presentFaction(entityID)
    local options = WorldMapPinProvider.resolveFactionSettings()
    return options and options[entityID] == true
end

function WorldMapPinProvider.formatCountWithCommas(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

function WorldMapPinProvider.normalizePointCoordinates(pos)
    if not pos then return end
    local coordX, coordY
    if pos.GetXY then coordX, coordY = pos:GetXY() else coordX, coordY = pos.x, pos.y end
    if WorldMapPinProvider.formatCountWithCommas(coordX) and WorldMapPinProvider.formatCountWithCommas(coordY) then return coordX, coordY end
end

-- Boat, zeppelin and tram docks come back from the taxi API with continent atlases.
-- They are not flight masters, so they are left to Map Finder's transport option.
function WorldMapPinProvider.isTransportNode(n)
    local atlas = n.atlasName or n.textureKit
    return type(atlas) == "string" and atlas:find("Continent", 1, true) ~= nil
end

function WorldMapPinProvider.collectMapFlightNodes(mapID)
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return {} end
    local isCallOk, nodeList2 = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    return isCallOk and type(nodeList2) == "table" and nodeList2 or {}
end

function WorldMapPinProvider.computeLabelBoundingRect(child, parent)
    if not (C_Map and C_Map.GetMapRectOnMap) then return end
    local isCallOk, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, child, parent)
    if isCallOk and WorldMapPinProvider.formatCountWithCommas(left) and WorldMapPinProvider.formatCountWithCommas(right) and WorldMapPinProvider.formatCountWithCommas(top) and WorldMapPinProvider.formatCountWithCommas(bottom)
        and right > left and bottom > top then
        return left, right, top, bottom
    end
end

function WorldMapPinProvider.collectMatchingEntries(mapID)
    local result, visitedMap = {}, {}
    local function appendEntry(nodeList2, left, right, top, bottom)
        for _, n in ipairs(nodeList2) do
            if type(n) == "table" and type(n.name) == "string"
                and not n.name:lower():match("^zzold")
                and not WorldMapPinProvider.isTransportNode(n) then
                local coordX, coordY = WorldMapPinProvider.normalizePointCoordinates(n.position)
                if coordX and coordX >= 0 and coordX <= 1 and coordY >= 0 and coordY <= 1 then
                    coordX, coordY = left + coordX * (right - left), top + coordY * (bottom - top)
                    local lookupKey = n.nodeID or (n.name .. ":" .. tostring(n.faction))
                    if not visitedMap[lookupKey] and coordX >= 0 and coordX <= 1 and coordY >= 0 and coordY <= 1 then
                        visitedMap[lookupKey] = true
                        result[#result + 1] = {node = n, x = coordX, y = coordY}
                    end
                end
            end
        end
    end
    appendEntry(WorldMapPinProvider.collectMapFlightNodes(mapID), 0, 1, 0, 1)
    local apiInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if not apiInfo then return result end
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    if apiInfo.mapType and apiInfo.mapType < continentType and C_Map.GetMapChildrenInfo then
        for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, continentType, true) or {}) do
            local leftPos, rowEntry, resolvedValue, buttonWidget = WorldMapPinProvider.computeLabelBoundingRect(child.mapID, mapID)
            if leftPos then appendEntry(WorldMapPinProvider.collectMapFlightNodes(child.mapID), leftPos, rowEntry, resolvedValue, buttonWidget) end
        end
    elseif apiInfo.mapType and apiInfo.mapType > continentType then
        local parent = apiInfo
        for _ = 1, 10 do
            if not parent or parent.mapType == continentType or not parent.parentMapID or parent.parentMapID == 0 then break end
            parent = C_Map.GetMapInfo(parent.parentMapID)
        end
        if parent and parent.mapType == continentType then
            local leftPos, rowEntry, resolvedValue, buttonWidget = WorldMapPinProvider.computeLabelBoundingRect(mapID, parent.mapID)
            if leftPos then appendEntry(WorldMapPinProvider.collectMapFlightNodes(parent.mapID), -leftPos / (rowEntry-leftPos), (1-leftPos) / (rowEntry-leftPos), -resolvedValue / (buttonWidget-resolvedValue), (1-resolvedValue) / (buttonWidget-resolvedValue)) end
        end
    end
    return result
end

EzWoWFlightMapPinMixin = {}
function EzWoWFlightMapPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_FLIGHT_POINT")
    self:SetScalingLimits(1, 1, 1)
    self:SetMouseClickEnabled(false)
    self:SetMouseMotionEnabled(true)
    self.Ring = self:CreateTexture(nil, "BACKGROUND")
    self.Ring:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Pin-Glow")
    self.Ring:SetPoint("CENTER")
    self.Ring:SetSize(20, 20)
    self.Icon = self:CreateTexture(nil, "ARTWORK")
    self.Icon:SetAllPoints()
end
function EzWoWFlightMapPinMixin:OnAcquired(entry)
    self.node = entry.node
    local windowFrame = WorldMapPinProvider.resolveFactionInfo(self.node.faction)
    self.Ring:SetVertexColor(windowFrame[2], windowFrame[3], windowFrame[4])
    local atlas = self.node.atlasName
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        self.Icon:SetAtlas(atlas)
    else
        self.Icon:SetTexture("Interface\\Minimap\\Tracking\\FlightMaster")
    end
    self:SetPosition(entry.x, entry.y)
end
function EzWoWFlightMapPinMixin:OnMouseEnter()
    local n = self.node
    if not n then return end
    local resolvedValue = WorldMapPinProvider.resolveText()
    local windowFrame = WorldMapPinProvider.resolveFactionInfo(n.faction)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(n.name, 1, 0.82, 0)
    GameTooltip:AddLine(windowFrame[1], windowFrame[2], windowFrame[3], windowFrame[4])
    local player = UnitFactionGroup("player")
    local enemy = (n.faction == 1 and player == "Alliance") or (n.faction == 2 and player == "Horde")
    if enemy then
        GameTooltip:AddLine(resolvedValue.enemy, 1, 0.3, 0.25)
    elseif n.isUndiscovered == true then
        GameTooltip:AddLine(resolvedValue.undiscovered, 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(resolvedValue.visit, 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(resolvedValue.title, STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
    GameTooltip:Show()
end
function EzWoWFlightMapPinMixin:OnMouseLeave()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
function EzWoWFlightMapPinMixin:OnReleased()
    self:OnMouseLeave()
    self.node = nil
    MapCanvasPinMixin.OnReleased(self)
end

ns.GetWorldMapFactionSettings = WorldMapPinProvider.resolveFactionSettings

local WorldMapFilterPopover

function WorldMapPinProvider.syncToggle()
    for _, checkbox in ipairs(ns.WorldMapSettingControls or {}) do
        checkbox:SetChecked(WorldMapPinProvider.isFeatureEnabled() and true or false)
    end
    if WorldMapFilterPopover and WorldMapFilterPopover.RefreshPopover then
        WorldMapFilterPopover:RefreshPopover()
    end
end

function WorldMapPinProvider.constructSmallBtn(parent, width, height, text, onClick)
    local buttonWidget = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    buttonWidget:SetSize(width, height)
    if buttonWidget.SetBackdrop then
        ns.UIKit:ApplyBackdrop(buttonWidget, 1, 1)
        buttonWidget:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.96)
        buttonWidget:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
    end
    local labelRegion = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelRegion:SetPoint("CENTER")
    labelRegion:SetTextColor(STYLE.textBody[1], STYLE.textBody[2], STYLE.textBody[3])
    labelRegion:SetText(text or "")
    buttonWidget.label = labelRegion
    -- Long translations (German, Russian, ...) shrink to fit the button
    function buttonWidget:SetText(txt)
        labelRegion:SetText(txt or "")
        ns.UIKit:FitFontString(labelRegion, width - 8, 1)
    end
    buttonWidget:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        end
    end)
    buttonWidget:SetScript("OnLeave", function(self)
        if self.UpdateActiveStyle then
            self:UpdateActiveStyle()
        elseif self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
        end
    end)
    buttonWidget:SetScript("OnMouseDown", function() labelRegion:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() labelRegion:SetPoint("CENTER", 0, 0) end)
    buttonWidget:SetScript("OnClick", onClick)
    return buttonWidget
end

function WorldMapPinProvider.buildMapToggle()
    local parent = WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer() or WorldMapFrame
    local panelFrameEntry = CreateFrame("Frame", nil, parent)
    panelFrameEntry:SetSize(28, 28)
    panelFrameEntry:SetMovable(true)
    panelFrameEntry:EnableMouse(true)
    panelFrameEntry:RegisterForDrag("LeftButton")
    panelFrameEntry:SetClampedToScreen(true)
    panelFrameEntry:SetFrameLevel(parent:GetFrameLevel() + 500)

    local function restoreFreePosition()
        local width, height = parent:GetWidth(), parent:GetHeight()
        if not WorldMapPinProvider.formatCountWithCommas(width) or not WorldMapPinProvider.formatCountWithCommas(height) or width <= 0 or height <= 0 then return end
        local point = EzWoW_FlightMapDB and EzWoW_FlightMapDB.worldMapControlPoint
        local coordX, coordY = 12, 35 + 33 + 28
        if type(point) == "table" and WorldMapPinProvider.formatCountWithCommas(point.x) and WorldMapPinProvider.formatCountWithCommas(point.y) then
            coordX, coordY = point.x * width, point.y * height
        end
        coordX = math.max(0, math.min(math.max(0, width - panelFrameEntry:GetWidth()), coordX))
        coordY = math.max(math.min(panelFrameEntry:GetHeight(), height), math.min(height, coordY))
        panelFrameEntry:ClearAllPoints()
        panelFrameEntry:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", coordX, coordY)
    end

    local function commitPositionLayout()
        if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.Layout then
            _G.EzWoWWorldMapDock:Layout()
        else
            restoreFreePosition()
        end
    end

    local function persistPosition()
        if not EzWoW_FlightMapDB then return end
        local calculateCanvasScale, parentScale = panelFrameEntry:GetEffectiveScale(), parent:GetEffectiveScale()
        local left, top = panelFrameEntry:GetLeft(), panelFrameEntry:GetTop()
        local plVal, pbVal, boxWidth, headerBar = parent:GetLeft(), parent:GetBottom(), parent:GetWidth(), parent:GetHeight()
        if not (left and top and plVal and pbVal and boxWidth > 0 and headerBar > 0) then return end
        EzWoW_FlightMapDB.worldMapControlPoint = {
            x = (left * calculateCanvasScale / parentScale - plVal) / boxWidth,
            y = (top * calculateCanvasScale / parentScale - pbVal) / headerBar,
        }
        EzWoW_FlightMapDB.worldMapAutoAlign = false
        commitPositionLayout()
        if ns.RefreshAllLocaleUI then ns.RefreshAllLocaleUI() end
    end

    local iconTex = CreateFrame("Button", nil, panelFrameEntry)
    iconTex:SetSize(28, 28)
    iconTex:SetPoint("CENTER", panelFrameEntry, "CENTER")
    local texPath = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Icon"
    local artwork = iconTex:CreateTexture(nil, "ARTWORK")
    artwork:SetTexture(texPath)
    if not artwork:GetTexture() then
        artwork:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\WorldMapIcon")
    end
    artwork:SetAllPoints()
    local hlVal = iconTex:CreateTexture(nil, "HIGHLIGHT")
    hlVal:SetTexture(artwork:GetTexture())
    hlVal:SetAllPoints()
    hlVal:SetBlendMode("ADD")
    hlVal:SetAlpha(0.35)
    iconTex:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    iconTex:RegisterForDrag("LeftButton")
    iconTex:SetScript("OnEnter", function(self)
        local ltVal = WorldMapPinProvider.resolveText()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("EzWoW - Flight Map", STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
        local lineList = {}
        for line in tostring(ltVal.openSettings or ""):gmatch("[^\n]+") do
            lineList[#lineList + 1] = line
        end
        if lineList[1] then GameTooltip:AddLine(lineList[1], STYLE.textBody[1], STYLE.textBody[2], STYLE.textBody[3]) end
        for index = 2, #lineList do
            GameTooltip:AddLine(lineList[index], STYLE.textMuted[1], STYLE.textMuted[2], STYLE.textMuted[3])
        end
        GameTooltip:Show()
    end)
    iconTex:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

    WorldMapFilterPopover = CreateFrame("Frame", "EzWoWFlightMapWorldPopover", parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    WorldMapFilterPopover:SetSize(256, 92)
    WorldMapFilterPopover:SetFrameStrata("HIGH")
    WorldMapFilterPopover:SetFrameLevel(panelFrameEntry:GetFrameLevel() + 20)
    WorldMapFilterPopover:SetClampedToScreen(true)
    WorldMapFilterPopover:EnableMouse(true)
    WorldMapFilterPopover:SetPoint("BOTTOMLEFT", panelFrameEntry, "BOTTOMRIGHT", 6, 0)
    if WorldMapFilterPopover.SetBackdrop then
        ns.UIKit:ApplyBackdrop(WorldMapFilterPopover)
        WorldMapFilterPopover:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.96)
        WorldMapFilterPopover:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
    end

    local headerBg = WorldMapFilterPopover:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 1, -1)
    headerBg:SetPoint("TOPRIGHT", -1, -1)
    headerBg:SetHeight(29)
    headerBg:SetColorTexture(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.96)

    local headerLine = WorldMapFilterPopover:CreateTexture(nil, "ARTWORK")
    headerLine:SetPoint("TOPLEFT", headerBg, "BOTTOMLEFT", 0, 0)
    headerLine:SetPoint("TOPRIGHT", headerBg, "BOTTOMRIGHT", 0, 0)
    headerLine:SetHeight(1)
    headerLine:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)

    local dismissBtn = WorldMapPinProvider.constructSmallBtn(WorldMapFilterPopover, 20, 20, "X", function() WorldMapFilterPopover:Hide() end)
    dismissBtn:SetPoint("TOPRIGHT", -5, -5)

    local cfgBtn = WorldMapPinProvider.constructSmallBtn(WorldMapFilterPopover, 44, 20, "설정", function()
        if ns.ToggleSettingsPopup then ns.ToggleSettingsPopup() end
    end)
    cfgBtn:SetPoint("RIGHT", dismissBtn, "LEFT", -3, 0)

    local popTitle = WorldMapFilterPopover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    popTitle:SetPoint("TOPLEFT", 10, -9)
    popTitle:SetPoint("RIGHT", cfgBtn, "LEFT", -6, 0)
    popTitle:SetJustifyH("LEFT")
    popTitle:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
    popTitle:SetText("EzWoW - Flight Map")

    local presentCheck = CreateFrame("CheckButton", nil, WorldMapFilterPopover, "UICheckButtonTemplate")
    presentCheck:SetSize(22, 22)
    presentCheck:SetPoint("TOPLEFT", 8, -34)
    local presentLabel = presentCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    presentLabel:SetPoint("LEFT", presentCheck, "RIGHT", 2, 0)
    presentLabel:SetTextColor(STYLE.textBody[1], STYLE.textBody[2], STYLE.textBody[3])
    presentCheck:SetScript("OnClick", function(self)
        if not EzWoW_FlightMapDB then return end
        EzWoW_FlightMapDB.worldMapFlights = self:GetChecked() and true or false
        ns.RefreshWorldMap()
    end)

    local factionBtns = {}
    local factionOrder = { 2, 1, 0 } 
    local btnW = 76
    for entryIndex, fid in ipairs(factionOrder) do
        local WorldMapFilterButton = WorldMapPinProvider.constructSmallBtn(WorldMapFilterPopover, btnW, 20, "", function()
            local opts = WorldMapPinProvider.resolveFactionSettings()
            if not opts then return end
            opts[fid] = not opts[fid]
            ns.RefreshWorldMap()
        end)
        WorldMapFilterButton:SetPoint("TOPLEFT", 8 + (entryIndex - 1) * (btnW + 6), -62)
        WorldMapFilterButton.fid = fid
        function WorldMapFilterButton:UpdateActiveStyle()
            local active = WorldMapPinProvider.presentFaction(self.fid) and WorldMapPinProvider.isFeatureEnabled()
            if self.SetBackdropColor then
                if active then
                    self:SetBackdropColor(STYLE.accent[1] * 0.24, STYLE.accent[2] * 0.24, STYLE.accent[3] * 0.24, 0.96)
                    self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
                else
                    self:SetBackdropColor(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.85)
                    self:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
                end
            end
            self.label:SetTextColor(
                active and STYLE.accent[1] or STYLE.textMuted[1],
                active and STYLE.accent[2] or STYLE.textMuted[2],
                active and STYLE.accent[3] or STYLE.textMuted[3]
            )
        end
        factionBtns[entryIndex] = WorldMapFilterButton
    end

    function WorldMapFilterPopover:RefreshPopover()
        local ltVal = WorldMapPinProvider.resolveText()
        local hasKo = (ltVal.alliance == "얼라이언스")
        cfgBtn:SetText(hasKo and "설정" or "Config")
        presentLabel:SetText(ltVal.toggle or "Flight masters")
        ns.UIKit:FitFontString(presentLabel, 256 - 32 - 10, 1)
        presentCheck:SetChecked(WorldMapPinProvider.isFeatureEnabled())
        local labels = { [2] = ltVal.alliance, [1] = ltVal.horde, [0] = ltVal.neutral }
        for _, WorldMapFilterButton in ipairs(factionBtns) do
            WorldMapFilterButton:SetText(labels[WorldMapFilterButton.fid] or "")
            WorldMapFilterButton:UpdateActiveStyle()
        end
    end
    WorldMapFilterPopover:SetScript("OnShow", function(self) self:RefreshPopover() end)
    WorldMapFilterPopover:Hide()

    iconTex:SetScript("OnClick", function(_, button)
        if not EzWoW_FlightMapDB or panelFrameEntry.dragging then return end
        if button == "RightButton" then
            EzWoW_FlightMapDB.worldMapAutoAlign = true
            EzWoW_FlightMapDB.worldMapControlPoint = nil
            commitPositionLayout()
            WorldMapPinProvider.syncToggle()
            if ns.RefreshAllLocaleUI then ns.RefreshAllLocaleUI() end
            return
        end
        GameTooltip:Hide()
        if WorldMapFilterPopover:IsShown() then
            WorldMapFilterPopover:Hide()
        else
            if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.CloseOthers then
                _G.EzWoWWorldMapDock:CloseOthers("EzWoW_FlightMap")
            end
            WorldMapFilterPopover:Show()
        end
    end)

    local function refreshDrag()
        if not panelFrameEntry.dragging then return end
        local dock = _G.EzWoWWorldMapDock
        if dock and dock.GetCursorCanvasXY then
            local curX, curY, maxW, maxH = dock:GetCursorCanvasXY(panelFrameEntry)
            if not (curX and curY and maxW and maxH) then return end
            local w, h = panelFrameEntry:GetWidth() or 28, panelFrameEntry:GetHeight() or 28
            local leftX = math.max(0, math.min(math.max(0, maxW - w), curX + (panelFrameEntry.grabLeftDX or -14)))
            local topY = math.max(h, math.min(maxH, curY + (panelFrameEntry.grabTopDY or 14)))
            panelFrameEntry:ClearAllPoints()
            panelFrameEntry:SetPoint("TOPLEFT", dock:GetCanvas(), "BOTTOMLEFT", leftX, topY)
            return
        end
        local cxVal, cyVal = GetCursorPosition()
        local bScale = panelFrameEntry:GetEffectiveScale()
        local pScale = parent:GetEffectiveScale()
        local coordX = (cxVal - panelFrameEntry.dragOffsetX) / bScale - (parent:GetLeft() * pScale / bScale)
        local coordY = (cyVal - panelFrameEntry.dragOffsetY) / bScale - (parent:GetBottom() * pScale / bScale)
        coordX = math.max(0, math.min(math.max(0, parent:GetWidth() - panelFrameEntry:GetWidth()), coordX))
        coordY = math.max(math.min(panelFrameEntry:GetHeight(), parent:GetHeight()), math.min(parent:GetHeight(), coordY))
        panelFrameEntry:ClearAllPoints()
        panelFrameEntry:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", coordX, coordY)
    end

    local function startDrag()
        local dock = _G.EzWoWWorldMapDock
        if dock and dock.GetCursorCanvasXY then
            local curX, curY, maxW, maxH = dock:GetCursorCanvasXY(panelFrameEntry)
            local btnCX, btnCY = dock:GetButtonCanvasCenter(panelFrameEntry)
            if curX and curY and btnCX and btnCY and maxW and maxH and maxW > 0 and maxH > 0 then
                local leftX = btnCX - 14
                local topY = btnCY + 14
                panelFrameEntry.grabLeftDX = leftX - curX
                panelFrameEntry.grabTopDY = topY - curY
                if EzWoW_FlightMapDB then
                    EzWoW_FlightMapDB.worldMapControlPoint = { x = leftX / maxW, y = topY / maxH }
                    EzWoW_FlightMapDB.worldMapAutoAlign = false
                end
                dock:Layout()
            end
        end
        local cxVal, cyVal = GetCursorPosition()
        local left, top = panelFrameEntry:GetLeft(), panelFrameEntry:GetTop()
        if not left or not top then return end
        local calculateCanvasScale = panelFrameEntry:GetEffectiveScale()
        panelFrameEntry.dragOffsetX, panelFrameEntry.dragOffsetY = cxVal - left * calculateCanvasScale, cyVal - top * calculateCanvasScale
        panelFrameEntry.dragging = true
        WorldMapFilterPopover:Hide()
        panelFrameEntry:SetScript("OnUpdate", refreshDrag)
    end
    iconTex:SetScript("OnDragStart", startDrag)

    local function stopDrag()
        if not panelFrameEntry.dragging then return end
        refreshDrag()
        panelFrameEntry.dragging = false
        panelFrameEntry:SetScript("OnUpdate", nil)
        persistPosition()
    end
    iconTex:SetScript("OnDragStop", stopDrag)
    panelFrameEntry:SetScript("OnHide", function() stopDrag(); WorldMapFilterPopover:Hide() end)
    panelFrameEntry:SetScript("OnShow", function() commitPositionLayout(); WorldMapPinProvider.syncToggle() end)
    parent:HookScript("OnSizeChanged", function() if not panelFrameEntry.dragging then commitPositionLayout() end end)

    if _G.EzWoWWorldMapDock then
        _G.EzWoWWorldMapDock:Register("EzWoW_FlightMap", {
            order = 2,
            button = panelFrameEntry,
            isAuto = WorldMapPinProvider.hasAutoAlign,
            closePanel = function()
                if WorldMapFilterPopover then WorldMapFilterPopover:Hide() end
            end,
            onDockedLayout = function() end,
            onFreeLayout = function()
                restoreFreePosition()
            end,
        })
    end

    commitPositionLayout()
    ns.WorldMapControlPanel = panelFrameEntry
    ns.WorldMapSettingsIcon = iconTex
    WorldMapPinProvider.syncToggle()
end

function WorldMapPinProvider.installWorldMapPinProvider()
    if WorldMapDataProvider or not (WorldMapFrame and WorldMapFrame.AddDataProvider
        and MapCanvasDataProviderMixin and MapCanvasPinMixin
        and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
    for lookupKey, value in pairs(MapCanvasPinMixin) do
        if EzWoWFlightMapPinMixin[lookupKey] == nil then EzWoWFlightMapPinMixin[lookupKey] = value end
    end
    WorldMapDataProvider = CreateFromMixins(MapCanvasDataProviderMixin)
    WorldMapDataProvider.Collect = WorldMapPinProvider.collectMatchingEntries
    function WorldMapDataProvider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(PIN)
    end
    function WorldMapDataProvider:RefreshAllData()
        self:RemoveAllData()
        if not WorldMapPinProvider.isFeatureEnabled() then return end
        for _, entry in ipairs(WorldMapPinProvider.collectMatchingEntries(self:GetMap():GetMapID())) do
            if WorldMapPinProvider.presentFaction(entry.node.faction) then
                self:GetMap():AcquirePin(PIN, entry)
            end
        end
    end
    function WorldMapDataProvider:OnShow()
        self:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
        WorldMapPinProvider.syncToggle()
    end
    function WorldMapDataProvider:OnHide() self:UnregisterEvent("TAXI_NODE_STATUS_CHANGED") end
    function WorldMapDataProvider:OnEvent() self:RefreshAllData() end
    WorldMapFrame:AddDataProvider(WorldMapDataProvider)
    local function bindStock(_, stock)
        if not (FlightPointDataProviderMixin and stock ~= WorldMapDataProvider
            and stock.ShouldShowTaxiNode == FlightPointDataProviderMixin.ShouldShowTaxiNode)
            or stock.ezWoWFlightMapHooked then return end
        stock.ezWoWFlightMapHooked = true
        hooksecurefunc(stock, "RefreshAllData", function(p)
            if WorldMapPinProvider.isFeatureEnabled() and p:GetMap() == WorldMapFrame then
                WorldMapFrame:RemoveAllPinsByTemplate("FlightPointPinTemplate")
            end
        end)
    end
    for p in pairs(WorldMapFrame.dataProviders or {}) do bindStock(WorldMapFrame, p) end
    hooksecurefunc(WorldMapFrame, "AddDataProvider", bindStock)
    ns.WorldMapProvider = WorldMapDataProvider
    WorldMapPinProvider.buildMapToggle()
    if WorldMapFrame:IsShown() then
        WorldMapDataProvider:OnShow()
        ns.RefreshWorldMap()
    end
end

function ns.RefreshWorldMap()
    WorldMapPinProvider.installWorldMapPinProvider()
    WorldMapPinProvider.syncToggle()
    if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.Layout then
        _G.EzWoWWorldMapDock:Layout()
    end
    if WorldMapDataProvider and WorldMapFrame:IsShown() then WorldMapFrame:RefreshAllDataProviders() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_FACTION")
events:SetScript("OnEvent", function(_, event, name)
    if event == "UNIT_FACTION" then
        if name == "player" then ns.RefreshWorldMap() end
    elseif event == "PLAYER_LOGIN" or name == ADDON_NAME or name == "Blizzard_WorldMap" then
        WorldMapPinProvider.installWorldMapPinProvider()
        WorldMapPinProvider.syncToggle()
    end
end)

_G.EzWoWFlightMapPinMixin = EzWoWFlightMapPinMixin
