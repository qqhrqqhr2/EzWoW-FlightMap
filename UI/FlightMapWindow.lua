--===========================================================================
-- EzWoW - Flight Map
-- UI/FlightMapWindow.lua : Custom Flight Map Canvas, Route Lines & Destination List
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local FlightMapWindow = ns.FlightMapWindow or {}
ns.FlightMapWindow = FlightMapWindow

local floor, ceil, min, max, sqrt, abs = math.floor, math.ceil, math.min, math.max, math.sqrt, math.abs
local STYLE = ns.STYLE
local L = ns.L
local MEDIA = ns.MEDIA
local ICON_FILE = ns.ICON_FILE
local ICON_FALLBACK = ns.ICON_FALLBACK
local ICON_COLOR = ns.ICON_COLOR
local GLOW_FILE = ns.GLOW_FILE
local GEAR_FILE = ns.GEAR_FILE
local RING_FILE = ns.RING_FILE
local LIST_FILE = ns.LIST_FILE
local STAR_ON_FILE = ns.STAR_ON_FILE
local STAR_OFF_FILE = ns.STAR_OFF_FILE
local STAR_INLINE = ns.STAR_INLINE
local BACKDROP = ns.BACKDROP
local PAD, TITLE_H, FOOT_H = ns.PAD, ns.TITLE_H, ns.FOOT_H
local PIN_SIZE, PIN_SIZE_CURRENT = ns.PIN_SIZE, ns.PIN_SIZE_CURRENT
local MIN_WIDTH = ns.MIN_WIDTH
local LIST_W, LIST_GAP = ns.LIST_W, ns.LIST_GAP
local BLIZZARD_FRAMES = ns.BLIZZARD_FRAMES

local resolveFiniteNumber = ns.IsFiniteNumber
local validPoint = ns.IsNormalizedMapCoordinate
local bootstrapDB = ns.InitDB
local printAddonChatMessage = ns.Print
local shortName = ns.ExtractShortStationName
local composeTime = ns.FormatFlightDurationText
local composeClock = ns.FormatSecondsAsClock
local resolveCoinText = ns.FormatCopperAsCoinString
local assignFontSize = ns.SetFontSize
local createFlightMapButton = ns.CreateStyledButton
local resolveContinentMapID = ns.ResolvePlayerContinentMapID
local enrichFlightNodesFromAPI = ns.PopulateFlightNodesFromAPI
local queryVerifiedFlightFare = ns.QueryVerifiedFlightRouteFare
local resolveFlightPathStatus = ns.EvaluateFlightRouteReachability
local captureFlightGraphSnapshot = ns.CaptureActiveFlightGraphSnapshot
local buildSnapshotHashKey = ns.ComputeFlightSnapshotSignature
local estimateFlightDuration = ns.EstimateRouteFlightDuration
local tooExpensive = ns.IsRouteFareUnaffordable
local resolveFareText = ns.FormatRouteFareDisplayText
local hasRecent = ns.IsRecentlyVisitedDestination

local mainWindowFrame, canvasViewport, labelOverlayLayer, titleText
local tilePool, pinPool, linePool, labelPool = {}, {}, {}, {}
local currentState = ns.cur
local hoverOverlayLayer
local syncFareLabel
local hover = ns.hover
local hidden = ns.hidden
local destinationListPanel, paintList, syncListSelection
local locationPulseFrame
local preAlpha = ns.preAlpha

local flightMapArtProbe
function FlightMapWindow.readDefaultFlightArtwork()
    local boxWidth, headerBar = TAXI_MAP_WIDTH or 316, TAXI_MAP_HEIGHT or 352
    local file, leftPos, resolvedValue, rowEntry, buttonWidget
    local tmVal = _G.TaxiMap
    if tmVal and tmVal.GetTexture then
        file = tmVal:GetTexture()
        if tmVal.GetSize then
            local swVal, shVal = tmVal:GetSize()
            if swVal and swVal > 0 and shVal and shVal > 0 then boxWidth, headerBar = swVal, shVal end
        end
        if file and tmVal.GetTexCoord then
            local ulx, uly, _, _, _, _, lrx, lry = tmVal:GetTexCoord()
            if ulx and lrx then leftPos, resolvedValue, rowEntry, buttonWidget = ulx, uly, lrx, lry end
        end
    end
    if not file and SetTaxiMap then
        if not flightMapArtProbe then
            local containerFrame = CreateFrame("Frame", nil, UIParent)
            containerFrame:Hide()
            flightMapArtProbe = containerFrame:CreateTexture(nil, "BACKGROUND")
        end
        SetTaxiMap(flightMapArtProbe)
        file = flightMapArtProbe:GetTexture()
        if file and flightMapArtProbe.GetTexCoord then
            local ulx, uly, _, _, _, _, lrx, lry = flightMapArtProbe:GetTexCoord()
            leftPos,resolvedValue,rowEntry,buttonWidget = ulx,uly,lrx,lry
        end
    end
    local tile = { x0 = 0, y0 = 0, x1 = boxWidth, y1 = headerBar, u0 = leftPos or 0, u1 = rowEntry or 1, v0 = resolvedValue or 0, v1 = buttonWidget or 1 }
    if file then
        tile.file = file
    else
        return
    end
    return { w = boxWidth, h = headerBar, tiles = { tile } }
end

-----------------------------------------------------------------------------
-- Disable Mouse Tree
-----------------------------------------------------------------------------
function FlightMapWindow.disableMouseTree(f, store)
    if f.IsProtected and f:IsProtected() then return end
    if f.IsMouseEnabled and f:IsMouseEnabled() then
        store[f] = true
        f:EnableMouse(false)
    end
    if f.GetChildren then
        for _, themeColor in ipairs({ f:GetChildren() }) do
            FlightMapWindow.disableMouseTree(themeColor, store)
        end
    end
end

function FlightMapWindow.suppressDefaultFlightFrames()
    for _, displayName in ipairs(BLIZZARD_FRAMES) do
        local f = _G[displayName]
        if f and f:IsShown() and not hidden[f] then
            local saved = { mouse = {}, alpha = preAlpha[f] or f:GetAlpha() }
            preAlpha[f] = nil
            hidden[f] = saved
            f:SetAlpha(0)
            FlightMapWindow.disableMouseTree(f, saved.mouse)
        end
    end
end

function FlightMapWindow.restoreDefaultFlightFrames()
    for f, saved in pairs(hidden) do
        for themeColor in pairs(saved.mouse) do
            if not (themeColor.IsProtected and themeColor:IsProtected()) then themeColor:EnableMouse(true) end
        end
        f:SetAlpha(saved.alpha)
        hidden[f] = nil
    end
    for f, opacityVal in pairs(preAlpha) do
        f:SetAlpha(opacityVal)
        preAlpha[f] = nil
    end
end

function FlightMapWindow.preMaskDefaultFlightFrame(f)
    if ns.DB and ns.DB.enabled and not hidden[f] then
        if preAlpha[f] == nil then preAlpha[f] = f:GetAlpha() end
        f:SetAlpha(0)
    end
end

-----------------------------------------------------------------------------
-- To View
-----------------------------------------------------------------------------

function FlightMapWindow.toView(nx, ny)
    return (nx * currentState.W - currentState.cx0) * currentState.s, (ny * currentState.H - currentState.cy0) * currentState.s
end

function FlightMapWindow.isElementCurrentlyVisible(node)

    if node.type == "DISTANT" and type(node.name) == "string" and node.name:lower():match("^%s*zzold") then return false end
    return node.x and (node.type ~= "DISTANT" or ns.DB.showUnreachable)
end

function FlightMapWindow.hasFavorite(node)
    return node and ns.DB.favorites[node.name] == true
end

function FlightMapWindow.switchFavorite(node)
    if not node then return end
    ns.DB.favorites[node.name] = (not FlightMapWindow.hasFavorite(node)) or nil
end

function FlightMapWindow.matchesFilter(node)
    local priorityQueue = currentState.query
    if not priorityQueue or priorityQueue == "" then return true end
    local displayName = node.name or ""
    return displayName:lower():find(priorityQueue, 1, true) ~= nil or displayName:find(currentState.queryRaw or priorityQueue, 1, true) ~= nil
end

function FlightMapWindow.resolvePinBaseAlpha(node)
    if not FlightMapWindow.matchesFilter(node) then return 0.22 end
    return node.type == "DISTANT" and 0.8 or 1
end

function FlightMapWindow.calculateViewportCropBounds(W, H, nodes)
    if not ns.DB.crop or not nodes then return 0, 0, W, H end
    local huge = math.huge
    local minX, minY, maxX, maxY = huge, huge, -huge, -huge
    for _, nodeEntry in ipairs(nodes) do
        if FlightMapWindow.isElementCurrentlyVisible(nodeEntry) then
            local pxVal, pyVal = nodeEntry.x * W, nodeEntry.y * H
            minX, maxX = min(minX, pxVal), max(maxX, pxVal)
            minY, maxY = min(minY, pyVal), max(maxY, pyVal)
        end
    end
    if minX == huge then return 0, 0, W, H end
    local matchRef = max(W, H) * 0.05
    local mxVal = ns.DB.labels and (matchRef + 70) or matchRef
    local function fit(a, buttonWidget, minLen, total)
        if buttonWidget - a < minLen then
            local themeColor = (a + buttonWidget) / 2
            a, buttonWidget = themeColor - minLen / 2, themeColor + minLen / 2
        end
        if a < 0 then buttonWidget, a = buttonWidget - a, 0 end
        if buttonWidget > total then a, buttonWidget = a - (buttonWidget - total), total end
        if a < 0 then a = 0 end
        return a, buttonWidget
    end
    local x0Val, x1Val = fit(minX - mxVal, maxX + mxVal, W * (ns.DB.labels and 0.5 or 0.35), W)
    local y0Val, y1Val = fit(minY - matchRef, maxY + matchRef, H * 0.45, H)
    return x0Val, y0Val, x1Val, y1Val
end

function FlightMapWindow.styleLabel(lb, selected)
    if not lb then return end
    local kind = lb.node and lb.node.type
    local dimmed = hover.pin and not selected
    local filtered = lb.node and not FlightMapWindow.matchesFilter(lb.node)
    lb.frame:SetAlpha((filtered and not selected) and 0.22 or (dimmed and 0.48 or 1))
    if lb.leader then
        lb.leader:SetThickness(selected and 3 or 1)
        lb.leader:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], selected and 1 or (dimmed and 0.08 or 0.24))
    end
    lb.info:SetTextColor(selected and 1 or STYLE.textBody[1], selected and 0.98 or STYLE.textBody[2], selected and 1 or STYLE.textBody[3])
    if lb.region then lb.region:SetTextColor(selected and 0.90 or STYLE.textMuted[1], selected and 0.94 or STYLE.textMuted[2], selected and 1 or STYLE.textMuted[3]) end
    lb.accent:SetWidth(selected and 4 or 2)
    if selected then
        lb.frame:SetBackdropColor(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.98)
        lb.frame:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        lb.accent:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        lb.name:SetTextColor(1, 0.96, 0.80)
    else
        lb.frame:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], kind == "DISTANT" and 0.72 or 0.88)
        lb.frame:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], kind == "DISTANT" and 0.35 or 0.65)
        if kind == "CURRENT" then
            lb.accent:SetColorTexture(0.35, 0.86, 0.52, 0.95)
            lb.name:SetTextColor(0.55, 1, 0.65)
        elseif kind == "DISTANT" then
            lb.accent:SetColorTexture(STYLE.disabled[1], STYLE.disabled[2], STYLE.disabled[3], 0.60)
            lb.name:SetTextColor(STYLE.textMuted[1], STYLE.textMuted[2], STYLE.textMuted[3])
        else
            lb.accent:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 0.95)
            lb.name:SetTextColor(0.65, 0.82, 1.00)
        end
    end
end

function FlightMapWindow.dismissLines()
    for _, lnVal in ipairs(linePool) do lnVal.glow:Hide(); lnVal.core:Hide() end
    if hoverOverlayLayer and hoverOverlayLayer.sparks then
        for _, spark in ipairs(hoverOverlayLayer.sparks) do spark:Hide() end
    end
    hover.segments, hover.total = {}, 0
end

function FlightMapWindow.resetHover()
    local pinFrame = hover.pin
    hover.pin, hover.source = nil, nil
    if pinFrame then
        pinFrame.ring:Hide()
        pinFrame.glow:Hide()
        pinFrame.icon:ClearAllPoints()
        pinFrame.icon:SetPoint("CENTER")
        pinFrame.icon:SetSize(pinFrame.baseSize or PIN_SIZE, pinFrame.baseSize or PIN_SIZE)
    end
    for _,lb in ipairs(labelPool) do FlightMapWindow.styleLabel(lb,false) end
    for _,anchorTarget in ipairs(pinPool) do
        if anchorTarget.node then
            anchorTarget:SetAlpha(FlightMapWindow.resolvePinBaseAlpha(anchorTarget.node))
            if canvasViewport then anchorTarget:SetFrameLevel(canvasViewport:GetFrameLevel()+(anchorTarget.node.type=="CURRENT" and 8 or (anchorTarget.node.type=="DISTANT" and 5 or 6))) end
        end
    end
    FlightMapWindow.dismissLines()
    if syncListSelection then syncListSelection() end
    if hoverOverlayLayer then
        hoverOverlayLayer:SetScript("OnUpdate", nil)
        hoverOverlayLayer:Hide()
    end
    if GameTooltip and GameTooltip:GetOwner() == (pinFrame and pinFrame.tooltipOwner) then GameTooltip:Hide() end
end

function FlightMapWindow.acquireTrackerRowWidget(i)
    local lnVal = linePool[i]
    if not lnVal then
        if not hoverOverlayLayer.CreateLine then return end
        lnVal = { glow = hoverOverlayLayer:CreateLine(nil, "ARTWORK", nil, -1),
               core = hoverOverlayLayer:CreateLine(nil, "ARTWORK", nil, 0) }
        lnVal.glow:SetThickness(11)
        lnVal.glow:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 0.34)
        lnVal.core:SetThickness(3)
        lnVal.core:SetColorTexture(0.75, 0.88, 1.00, 1)
        linePool[i] = lnVal
    end
    return lnVal
end

function FlightMapWindow.renderRouteHopSegments(node)
    FlightMapWindow.dismissLines()
    if node.type ~= "REACHABLE" or not node.segs then return end
    local used = 0
    for _, seg in ipairs(node.segs) do
        local a, buttonWidget = currentState.bySlot[seg[1]], currentState.bySlot[seg[2]]
        if a and buttonWidget and a.x and buttonWidget.x then
            local x1Val, y1Val = FlightMapWindow.toView(a.x, a.y)
            local x2Val, y2Val = FlightMapWindow.toView(buttonWidget.x, buttonWidget.y)
            local length = sqrt((x2Val - x1Val)^2 + (y2Val - y1Val)^2)
            if length > 0.01 then
                used = used + 1
                hover.segments[used] = { x1=x1Val, y1=y1Val, x2=x2Val, y2=y2Val, length=length }
                hover.total = hover.total + length
                local lnVal = FlightMapWindow.acquireTrackerRowWidget(used)
                if lnVal then
                    for _, part in ipairs({lnVal.glow, lnVal.core}) do
                        part:SetStartPoint("TOPLEFT", canvasViewport, x1Val, -y1Val)
                        part:SetEndPoint("TOPLEFT", canvasViewport, x2Val, -y2Val)
                        part:Show()
                    end
                end
            end
        end
    end
end

function FlightMapWindow.resolveRoutePoint(distance)
    for _, seg in ipairs(hover.segments) do
        if distance <= seg.length then
            local unitRef = distance / seg.length
            return seg.x1 + (seg.x2-seg.x1)*unitRef, seg.y1 + (seg.y2-seg.y1)*unitRef
        end
        distance = distance - seg.length
    end
end

function FlightMapWindow.refreshHover(_, dt)
    local pinFrame = hover.pin
    if not (pinFrame and pinFrame.node and pinFrame:IsShown() and currentState.open) then FlightMapWindow.resetHover(); return end
    hover.elapsed = (hover.elapsed or 0) + min(dt or 0, 0.1)
    local resolvedValue = hover.elapsed
    local pulse = (math.sin(resolvedValue * 3.2) + 1) / 2
    local ringSize = (pinFrame.baseSize or PIN_SIZE) + 25 + pulse * 8
    pinFrame.ring:SetSize(ringSize, ringSize)
    pinFrame.ring:SetAlpha(0.88 + pulse * 0.12)
    pinFrame.glow:SetAlpha(0.25 + pulse * 0.15)
    if pinFrame.ring.SetRotation then pinFrame.ring:SetRotation(resolvedValue * 0.30) end
    local grow = 1 + 0.28 * min(1, resolvedValue / 0.14)
    pinFrame.icon:SetSize(pinFrame.baseSize * grow, pinFrame.baseSize * grow)
    for i, spark in ipairs(hoverOverlayLayer.sparks) do
        if hover.total > 0 then
            local distance = (resolvedValue * 110 + (i-1) * hover.total / 3) % hover.total
            local coordX, coordY = FlightMapWindow.resolveRoutePoint(distance)
            if coordX then
                spark:ClearAllPoints()
                spark:SetPoint("CENTER", canvasViewport, "TOPLEFT", coordX, -coordY)
                spark:SetAlpha(i == 1 and 0.95 or 0.65)
                spark:Show()
            else spark:Hide() end
        else spark:Hide() end
    end
end

function FlightMapWindow.pinOnenter(self)
    local pinFrame = self.pin or self
    local node = pinFrame.node
    if not (node and currentState.open and hoverOverlayLayer) then return end
    if TaxiNodeName and TaxiNodeName(node.slot) ~= node.name then FlightMapWindow.resetHover(); return end
    if node.type == "REACHABLE" then
        if ns.snap then enrichFlightNodesFromAPI(ns.snap) end
        node.cost = queryVerifiedFlightFare(node)
        if syncFareLabel then syncFareLabel(pinFrame) end
    end
    if hover.pin ~= pinFrame then
        FlightMapWindow.resetHover()
        hover.pin, hover.elapsed = pinFrame, 0
        for _,lb in ipairs(labelPool) do FlightMapWindow.styleLabel(lb,lb.pin==pinFrame) end
        for _,anchorTarget in ipairs(pinPool) do if anchorTarget.node then anchorTarget:SetAlpha(anchorTarget==pinFrame and 1 or min(0.5, FlightMapWindow.resolvePinBaseAlpha(anchorTarget.node))) end end
        pinFrame:SetFrameLevel(canvasViewport:GetFrameLevel()+12)
        local rowEntry, greenVal, buttonWidget = STYLE.accent[1], STYLE.accent[2], STYLE.accent[3]
        if node.type == "CURRENT" then rowEntry,greenVal,buttonWidget = 0.42,1,0.63
        elseif node.type ~= "REACHABLE" then rowEntry,greenVal,buttonWidget = 0.64,0.72,0.82 end
        pinFrame.ring:SetVertexColor(rowEntry,greenVal,buttonWidget)
        pinFrame.glow:SetVertexColor(rowEntry,greenVal,buttonWidget)
        pinFrame.ring:Show(); pinFrame.glow:Show()
        FlightMapWindow.renderRouteHopSegments(node)
        if syncListSelection then syncListSelection() end
        hoverOverlayLayer:SetScript("OnUpdate", FlightMapWindow.refreshHover)
        hoverOverlayLayer:Show()
        FlightMapWindow.refreshHover(hoverOverlayLayer, 0)
    end
    hover.source, pinFrame.tooltipOwner = self, self
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(node.name, STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
    if node.type == "CURRENT" then
        GameTooltip:AddLine(L.CURRENT, 0.4, 1, 0.6)
    elseif node.type == "REACHABLE" then
        GameTooltip:AddLine(resolveFareText(node, 12), 1, 1, 1)
        if tooExpensive(node) then GameTooltip:AddLine(L.NO_MONEY, STYLE.warning[1], STYLE.warning[2], STYLE.warning[3]) end
        if hasRecent(node) then GameTooltip:AddLine(L.TT_RECENT, 0.55, 0.8, 1) end
        local sec, recorded = estimateFlightDuration(node)
        if sec then
            if recorded then GameTooltip:AddLine(L.TT_TIME:format(composeTime(sec)), 1, 1, 1)
            else
                GameTooltip:AddLine(L.TT_EST:format(composeTime(sec, true)), 0.86, 0.84, 0.75)
                GameTooltip:AddLine(L.TT_EST_NOTE, 0.6, 0.6, 0.6)
            end
        else
            GameTooltip:AddLine(L.TIME .. ": " .. L.TIME_UNKNOWN, 0.8, 0.8, 0.8)
            GameTooltip:AddLine(L.TT_EST_NOTE, 0.6, 0.6, 0.6)
        end
        if node.hops and node.hops > 1 then GameTooltip:AddLine(L.STOPS:format(node.hops - 1), 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(L.CLICK, 0.4, 0.8, 1)
    else GameTooltip:AddLine(resolveFlightPathStatus(node), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

function FlightMapWindow.pinOnleave(self)
    if hover.source == self then FlightMapWindow.resetHover() end
end

local LABEL_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1, insets = {left=1, right=1, top=1, bottom=1},
}

local function createFlightMapButton(parent, boxWidth, headerBar, isAccent, onClick)
    local buttonWidget = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    buttonWidget:SetSize(boxWidth, headerBar)
    if buttonWidget.SetBackdrop then
        buttonWidget:SetBackdrop(LABEL_BACKDROP)
    end
    local function applyNormalButtonLook()
        if not buttonWidget.SetBackdropColor then return end
        if isAccent then
            buttonWidget:SetBackdropColor(STYLE.accent[1] * 0.22, STYLE.accent[2] * 0.22, STYLE.accent[3] * 0.22, 0.96)
            buttonWidget:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        else
            buttonWidget:SetBackdropColor(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.96)
            buttonWidget:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
        end
    end
    applyNormalButtonLook()
    buttonWidget.normalStyle = applyNormalButtonLook
    local formatLocalizedLabel = buttonWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    formatLocalizedLabel:SetPoint("CENTER")
    if isAccent then
        formatLocalizedLabel:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
    else
        formatLocalizedLabel:SetTextColor(STYLE.textBody[1], STYLE.textBody[2], STYLE.textBody[3])
    end
    buttonWidget.label = formatLocalizedLabel
    function buttonWidget:SetText(txt) formatLocalizedLabel:SetText(txt or "") end
    function buttonWidget:GetText() return formatLocalizedLabel:GetText() end
    buttonWidget:SetScript("OnEnter", function()
        if buttonWidget.SetBackdropColor then
            buttonWidget:SetBackdropColor(0.18, 0.26, 0.34, 1)
            buttonWidget:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        end
    end)
    buttonWidget:SetScript("OnLeave", applyNormalButtonLook)
    buttonWidget:SetScript("OnMouseDown", function() formatLocalizedLabel:SetPoint("CENTER", 1, -1) end)
    buttonWidget:SetScript("OnMouseUp", function() formatLocalizedLabel:SetPoint("CENTER", 0, 0) end)
    if onClick then buttonWidget:SetScript("OnClick", onClick) end
    return buttonWidget
end

local flightConfirmDialog
function FlightMapWindow.canFly(node)
    return currentState.open and node and node.type == "REACHABLE" and TakeTaxiNode
        and (not TaxiNodeGetType or TaxiNodeGetType(node.slot)=="REACHABLE")
        and (not TaxiNodeName or TaxiNodeName(node.slot)==node.name)
end
function FlightMapWindow.confirmDetails(node,fare)
    local sec,recorded=estimateFlightDuration(node)
    return node.name .. "\n\n" .. resolveCoinText(fare,12) .. "   " .. L.TIME .. " " .. (sec and composeTime(sec,not recorded) or L.TIME_UNKNOWN)
end
function FlightMapWindow.presentFlightConfirm(node)
    if not flightConfirmDialog then
        local f=CreateFrame("Frame","EzWoWFlightMapConfirm",UIParent,BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(380,200);f:SetPoint("CENTER",UIParent,"CENTER",0,0)
        ns.UIKit:ElevateModal(f, 250);f:EnableMouse(true)
        f:SetBackdrop(BACKDROP)
        f:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.98)
        f:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        f.title=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        f.title:SetPoint("TOP",f,"TOP",0,-16);f.title:SetText(L.CONFIRM_TITLE)
        f.title:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
        f.details=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        f.details:SetPoint("TOP",f,"TOP",0,-43);f.details:SetWidth(350)
        f.notice=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        f.notice:SetPoint("BOTTOM",f,"BOTTOM",0,52);f.notice:SetWidth(350)
        f.notice:SetTextColor(STYLE.warning[1], STYLE.warning[2], STYLE.warning[3])
        f.accept=createFlightMapButton(f, 120, 24, true)
        f.accept:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",50,16);f.accept:SetText(L.CONFIRM_FLY)
        f.cancel=createFlightMapButton(f, 120, 24, false, function() f:Hide() end)
        f.cancel:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-50,16);f.cancel:SetText(L.CONFIRM_CANCEL)
        f.accept:SetScript("OnClick",function()
            local request=f.request
            if not request then return end
            if not FlightMapWindow.canFly(request.node) or currentState.generation~=request.generation or ns.snap~=request.snapshot then f:Hide();return end
            if ns.snap then enrichFlightNodesFromAPI(ns.snap) end
            local fare=queryVerifiedFlightFare(request.node)
            if fare~=request.fare then
                request.fare=fare;f.details:SetText(FlightMapWindow.confirmDetails(request.node,fare));f.notice:SetText(L.CONFIRM_CHANGED)
                return
            end
            f:Hide();TakeTaxiNode(request.node.slot)
        end)
        f:SetScript("OnHide",function() f.request=nil end)
        flightConfirmDialog=f
    end
    flightConfirmDialog.title:SetText(L.CONFIRM_TITLE)
    flightConfirmDialog.accept:SetText(L.CONFIRM_FLY)
    flightConfirmDialog.cancel:SetText(L.CONFIRM_CANCEL)
    if ns.snap then enrichFlightNodesFromAPI(ns.snap) end
    local fare=queryVerifiedFlightFare(node)
    flightConfirmDialog.request={node=node,fare=fare,generation=currentState.generation,snapshot=ns.snap}
    flightConfirmDialog.details:SetText(FlightMapWindow.confirmDetails(node,fare));flightConfirmDialog.notice:SetText("")
    ns.UIKit:ElevateModal(flightConfirmDialog, 250);flightConfirmDialog:Show();if flightConfirmDialog.Raise then flightConfirmDialog:Raise() end
end
function FlightMapWindow.pinOnclick(self)
    local node = (self.pin or self).node
    if FlightMapWindow.canFly(node) then
        if ns.DB and ns.DB.confirmFlight then FlightMapWindow.presentFlightConfirm(node) else TakeTaxiNode(node.slot) end
    end
end

function FlightMapWindow.buildPin()
    local buttonWidget = CreateFrame("Button", nil, canvasViewport)
    buttonWidget:SetSize(PIN_SIZE, PIN_SIZE)
    buttonWidget.icon = buttonWidget:CreateTexture(nil, "ARTWORK")
    buttonWidget.icon:SetPoint("CENTER")
    buttonWidget.icon:SetSize(PIN_SIZE, PIN_SIZE)
    buttonWidget.baseSize = PIN_SIZE
    buttonWidget.glow = buttonWidget:CreateTexture(nil, "BACKGROUND")
    buttonWidget.glow:SetTexture(GLOW_FILE)
    buttonWidget.glow:SetBlendMode("ADD")
    buttonWidget.glow:SetPoint("CENTER")
    buttonWidget.glow:SetSize(52, 52)
    buttonWidget.glow:Hide()
    buttonWidget.ring = buttonWidget:CreateTexture(nil, "OVERLAY")
    if buttonWidget.ring:SetTexture(RING_FILE) == false then buttonWidget.ring:SetTexture(GLOW_FILE) end
    buttonWidget.ring:SetBlendMode("ADD")
    buttonWidget.ring:SetPoint("CENTER")
    buttonWidget.ring:SetSize(43, 43)
    buttonWidget.ring:Hide()
    local hlVal = buttonWidget:CreateTexture(nil, "HIGHLIGHT")
    if hlVal:SetTexture(GLOW_FILE) == false then hlVal:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Icon-Highlight") end
    hlVal:SetBlendMode("ADD")
    hlVal:SetPoint("CENTER")
    buttonWidget.hl = hlVal
    buttonWidget:RegisterForClicks("LeftButtonUp")
    buttonWidget:SetScript("OnClick", FlightMapWindow.pinOnclick)
    buttonWidget:SetScript("OnEnter", FlightMapWindow.pinOnenter)
    buttonWidget:SetScript("OnLeave", FlightMapWindow.pinOnleave)
    buttonWidget:SetScript("OnHide", function(self)
        if hover.pin == self then FlightMapWindow.resetHover() end
    end)
    return buttonWidget
end

function FlightMapWindow.assignPinIcon(pinFrame, kind)
    if pinFrame.icon:SetTexture(ICON_FILE[kind] or ICON_FILE.REACHABLE) ~= false then return end
    if pinFrame.icon:SetTexture(ICON_FALLBACK[kind] or ICON_FALLBACK.REACHABLE) ~= false then return end
    local themeColor = ICON_COLOR[kind] or ICON_COLOR.REACHABLE
    pinFrame.icon:SetColorTexture(themeColor[1], themeColor[2], themeColor[3], 1)
end

-----------------------------------------------------------------------------
-- Build Label
-----------------------------------------------------------------------------
function FlightMapWindow.buildLabel()
    local lb = {}
    lb.frame = CreateFrame("Button", nil, labelOverlayLayer, BackdropTemplateMixin and "BackdropTemplate" or nil)
    lb.frame:SetBackdrop(LABEL_BACKDROP)
    lb.frame:RegisterForClicks("LeftButtonUp")
    lb.frame:SetScript("OnEnter", FlightMapWindow.pinOnenter)
    lb.frame:SetScript("OnLeave", FlightMapWindow.pinOnleave)
    lb.frame:SetScript("OnClick", FlightMapWindow.pinOnclick)
    lb.frame:SetScript("OnHide", FlightMapWindow.pinOnleave)
    lb.accent = lb.frame:CreateTexture(nil, "ARTWORK")
    lb.accent:SetPoint("TOPLEFT", 1, -1)
    lb.accent:SetPoint("BOTTOMLEFT", 1, 1)
    lb.accent:SetWidth(2)
    lb.name = lb.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lb.name:SetJustifyH("LEFT")
    lb.name:SetShadowOffset(1, -1)
    lb.region = lb.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lb.region:SetJustifyH("LEFT")
    lb.region:SetTextColor(0.57, 0.62, 0.68)
    lb.region:SetShadowOffset(1, -1)
    lb.info = lb.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lb.info:SetJustifyH("LEFT")
    lb.info:SetTextColor(0.85, 0.86, 0.88)
    lb.info:SetShadowOffset(1, -1)
    if labelOverlayLayer.CreateLine then
        lb.leader = labelOverlayLayer:CreateLine(nil, "ARTWORK")
        lb.leader:SetThickness(1)
        lb.leader:Hide()
    end
    return lb
end

function FlightMapWindow.dismissLabel(lb)
    lb.frame:Hide()
    lb.info:Hide()
    lb.region:Hide()
    if lb.leader then lb.leader:Hide() end
    if lb.pin then lb.pin.label = nil end
    lb.pin, lb.node, lb.frame.pin = nil, nil, nil
end

function FlightMapWindow.resolveDestinationInfo(node, size)
    if node.type == "CURRENT" then return L.CURRENT end
    if node.type ~= "REACHABLE" then return resolveFlightPathStatus(node) end
    local sec, recorded = estimateFlightDuration(node)
    local time = sec and composeTime(sec, not recorded) or L.TIME_UNKNOWN
    return resolveFareText(node, size) .. "   " .. L.TIME .. " " .. time
end

syncFareLabel = function(pinFrame)
    local lb = pinFrame.label
    if not lb or not lb.node then return end
    lb.info:SetText(FlightMapWindow.resolveDestinationInfo(lb.node, lb.fontSize or ns.DB.labelSize or 12))
end

function FlightMapWindow.splitDestinationName(displayName)
    displayName = displayName or "?"
    local destination, region = displayName:match("^(.-)%s*%((.-)%)%s*$")
    if not destination then destination, region = displayName:match("^([^,]+),%s*(.+)$") end
    if not destination then destination, region = displayName:match("^(.-)%s*·%s*(.+)$") end
    return destination or displayName, region or ""
end

function FlightMapWindow.resolveRectOverlap(ax,ay,aw,ah,bx,by,bw,bh)
    local boxWidth,headerBar=min(ax+aw,bx+bw)-max(ax,bx),min(ay+ah,by+bh)-max(ay,by)
    return boxWidth>0 and headerBar>0 and boxWidth*headerBar or 0
end

function FlightMapWindow.layoutNonOverlappingLabels(shown)
    for _,lb in ipairs(labelPool) do FlightMapWindow.dismissLabel(lb) end
    if not ns.DB.labels then return end
    local vwVal,vhVal=canvasViewport:GetSize()
    local order={}
    for _,item in ipairs(shown) do order[#order+1]=item end
    table.sort(order,function(a,buttonWidget)
        if a.py~=buttonWidget.py then return a.py<buttonWidget.py end
        return a.node.slot<buttonWidget.node.slot
    end)
    local size=ns.DB.labelSize or 12
    while size>8 and #shown*(size*16+16)*(size*3+10)>vwVal*vhVal*.55 do size=size-1 end
    
    local keepOut={}
    for i,other in ipairs(shown) do
        local radius=other.r+14
        keepOut[i]={other.px-radius,other.py-radius,other.px+radius,other.py+radius}
    end
    local nKeep=#keepOut
    local placed={}
    for i,item in ipairs(order) do
        local lb=labelPool[i]
        if not lb then lb=FlightMapWindow.buildLabel();labelPool[i]=lb end
        local node=item.node
        lb.pin,lb.node,lb.frame.pin=item.pin,node,item.pin
        lb.fontSize=size;item.pin.label=lb
        assignFontSize(lb.name,size);assignFontSize(lb.region,max(8,size-2));assignFontSize(lb.info,size)
        local destination,region=FlightMapWindow.splitDestinationName(node.name)
        if FlightMapWindow.hasFavorite(node) then destination=STAR_INLINE..destination end
        lb.name:SetText(destination);lb.region:SetText(region);lb.info:SetText(FlightMapWindow.resolveDestinationInfo(node,size))
        for _,labelRegion in ipairs({lb.name,lb.region,lb.info}) do labelRegion:SetWidth(0) end
        local boxWidth=min(max(lb.name:GetStringWidth(),lb.region:GetStringWidth(),lb.info:GetStringWidth())+16,vwVal*.42)
        local headerBar=size*3+10
        local pxVal,pyVal,rowEntry=item.px,item.py,item.r+16
        local maxX,maxY=max(0,vwVal-boxWidth),max(0,vhVal-headerBar)
        local bestX,bestY,bestScore,bestOverlap
        local function consider(coordX,coordY)
            if coordX<0 then coordX=0 elseif coordX>maxX then coordX=maxX end
            if coordY<0 then coordY=0 elseif coordY>maxY then coordY=maxY end
            local exVal=pxVal<coordX and coordX or (pxVal>coordX+boxWidth and coordX+boxWidth or pxVal)
            local eyVal=pyVal<coordY and coordY or (pyVal>coordY+headerBar and coordY+headerBar or pyVal)
            local dxVal,dyVal=exVal-pxVal,eyVal-pyVal
            local score=dxVal*dxVal+dyVal*dyVal*1.3
            if (pxVal<vwVal/2 and coordX+boxWidth<pxVal) or (pxVal>=vwVal/2 and coordX>pxVal) then score=score+80 end
            if bestScore and score>=bestScore then return end
            
            local x2Val,y2Val=coordX+boxWidth,coordY+headerBar
            for entryKey=1,nKeep do
                local priorityQueue=keepOut[entryKey]
                if coordX<priorityQueue[3] and x2Val>priorityQueue[1] and coordY<priorityQueue[4] and y2Val>priorityQueue[2] then return end
            end
            local overlap=0
            for entryKey=1,#placed do
                local anchorTarget=placed[entryKey]
                overlap=overlap+FlightMapWindow.resolveRectOverlap(coordX-2,coordY-2,boxWidth+4,headerBar+4,anchorTarget[1],anchorTarget[2],anchorTarget[3],anchorTarget[4])
            end
            score=score+250*overlap
            if not bestScore or score<bestScore then bestX,bestY,bestScore,bestOverlap=coordX,coordY,score,overlap end
        end
        
        for _,dyVal in ipairs({0,-headerBar-4,headerBar+4,-2*(headerBar+4),2*(headerBar+4)}) do
            consider(pxVal+rowEntry,pyVal-headerBar/2+dyVal);consider(pxVal-rowEntry-boxWidth,pyVal-headerBar/2+dyVal)
        end
        consider(pxVal-boxWidth/2,pyVal-rowEntry-headerBar);consider(pxVal-boxWidth/2,pyVal+rowEntry)
        
        if not bestX or bestOverlap>0 then
            local x0Val,x1Val=max(0,pxVal-boxWidth-200),min(maxX,pxVal+200)
            local y0Val,y1Val=max(0,pyVal-headerBar-160),min(maxY,pyVal+160)
            for coordY=y0Val,y1Val,12 do
                for coordX=x0Val,x1Val,16 do consider(coordX,coordY) end
            end
        end
        
        if not bestX or bestOverlap>0 then
            for coordY=0,maxY,12 do
                for coordX=0,maxX,16 do consider(coordX,coordY) end
                consider(maxX,coordY)
            end
            for coordX=0,maxX,16 do consider(coordX,maxY) end
        end
        if bestX then
            placed[#placed+1]={bestX,bestY,boxWidth,headerBar}
            lb.layoutX,lb.layoutY=bestX,bestY
            lb.frame:ClearAllPoints();lb.frame:SetPoint("TOPLEFT",labelOverlayLayer,"TOPLEFT",bestX,-bestY)
            lb.frame:SetSize(boxWidth,headerBar);lb.frame:SetFrameLevel(labelOverlayLayer:GetFrameLevel()+1)
            for _,labelRegion in ipairs({lb.name,lb.region,lb.info}) do
                labelRegion:SetWidth(boxWidth-16)
                if labelRegion.SetWordWrap then labelRegion:SetWordWrap(false) end
                if labelRegion.SetMaxLines then labelRegion:SetMaxLines(1) end
                labelRegion:ClearAllPoints()
            end
            lb.name:SetPoint("TOPLEFT",lb.frame,"TOPLEFT",8,-4)
            lb.region:SetPoint("TOPLEFT",lb.frame,"TOPLEFT",8,-(size+6))
            lb.info:SetPoint("TOPLEFT",lb.frame,"TOPLEFT",8,-(size*2+7))
            if lb.leader then
                local exVal,eyVal=min(max(pxVal,bestX),bestX+boxWidth),min(max(pyVal,bestY),bestY+headerBar)
                local dxVal,dyVal=exVal-pxVal,eyVal-pyVal
                local distance=sqrt(dxVal*dxVal+dyVal*dyVal)
                if distance>0 then
                    lb.leader:SetStartPoint("TOPLEFT",canvasViewport,pxVal+dxVal*(item.r+3)/distance,-(pyVal+dyVal*(item.r+3)/distance))
                    lb.leader:SetEndPoint("TOPLEFT",canvasViewport,exVal,-eyVal);lb.leader:Show()
                end
            end
            FlightMapWindow.styleLabel(lb,false);lb.region:Show();lb.info:Show();lb.frame:Show()
        else

            FlightMapWindow.dismissLabel(lb)
        end
    end
end

local renderFlightMapCanvas
local paintQueued = false
function FlightMapWindow.scheduleRender()
    if paintQueued then return end
    paintQueued = true
    C_Timer.After(0, function()
        paintQueued = false
        if mainWindowFrame and mainWindowFrame:IsShown() and currentState.nodes then renderFlightMapCanvas() end
    end)
end

-----------------------------------------------------------------------------
-- Sort Value
-----------------------------------------------------------------------------
local ROW_H, LIST_HEAD_H = 34, 54
local listRows, listItems, listOffset = {}, {}, 0

function FlightMapWindow.sortValue(node, key)
    if key == "time" then return (estimateFlightDuration(node)) end
    if key == "fare" then return resolveFiniteNumber(node.cost) and node.cost or nil end
end

function FlightMapWindow.compileSortedDestinationList()
    local itemEntries = {}
    for _, node in ipairs(currentState.nodes or {}) do
        if node.type ~= "CURRENT" and FlightMapWindow.isElementCurrentlyVisible(node) and FlightMapWindow.matchesFilter(node) then itemEntries[#itemEntries + 1] = node end
    end
    local key = ns.DB.listSort
    local function radioOptionGroup(nodeEntry)
        if hasRecent(nodeEntry) and nodeEntry.type == "REACHABLE" then return 0 end
        if FlightMapWindow.hasFavorite(nodeEntry) then return 1 end
        return nodeEntry.type == "REACHABLE" and 2 or 3
    end
    table.sort(itemEntries, function(a, buttonWidget)
        local gaVal, gbVal = radioOptionGroup(a), radioOptionGroup(buttonWidget)
        if gaVal ~= gbVal then return gaVal < gbVal end
        if key ~= "name" then
            local vaVal, vbVal = FlightMapWindow.sortValue(a, key), FlightMapWindow.sortValue(buttonWidget, key)
            if vaVal and vbVal and vaVal ~= vbVal then return vaVal < vbVal end
            if vaVal and not vbVal then return true end
            if vbVal and not vaVal then return false end
        end
        if a.name ~= buttonWidget.name then return a.name < buttonWidget.name end
        return a.slot < buttonWidget.slot
    end)
    return itemEntries
end

function FlightMapWindow.visibleRowCount()
    if not destinationListPanel then return 0 end
    return max(1, floor((destinationListPanel:GetHeight() - LIST_HEAD_H - 6) / ROW_H))
end

function FlightMapWindow.rowOnenter(self)
    if self.node and self.pin then FlightMapWindow.pinOnenter(self) end
end
function FlightMapWindow.rowOnleave(self) FlightMapWindow.pinOnleave(self) end
function FlightMapWindow.rowOnclick(self) if self.pin then FlightMapWindow.pinOnclick(self) end end

function FlightMapWindow.starOnclick(self)
    local rowWidget = self:GetParent()
    if not rowWidget.node then return end
    FlightMapWindow.switchFavorite(rowWidget.node)
    if renderFlightMapCanvas then renderFlightMapCanvas() end
end
function FlightMapWindow.starOnenter(self)
    local rowWidget = self:GetParent()
    if not rowWidget.node then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(FlightMapWindow.hasFavorite(rowWidget.node) and L.FAV_REMOVE or L.FAV_ADD, 1, 0.82, 0)
    GameTooltip:Show()
end
function FlightMapWindow.starOnleave(self)
    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end

function FlightMapWindow.buildRow(parent)
    local rowWidget = CreateFrame("Button", nil, parent)
    rowWidget:SetHeight(ROW_H)
    rowWidget:RegisterForClicks("LeftButtonUp")
    rowWidget.bg = rowWidget:CreateTexture(nil, "BACKGROUND")
    rowWidget.bg:SetAllPoints()
    rowWidget.bg:SetColorTexture(1, 1, 1, 0.03)
    rowWidget.sel = rowWidget:CreateTexture(nil, "BORDER")
    rowWidget.sel:SetAllPoints()
    rowWidget.sel:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 0.20)
    rowWidget.sel:Hide()
    local hlVal = rowWidget:CreateTexture(nil, "HIGHLIGHT")
    hlVal:SetAllPoints()
    hlVal:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 0.12)
    rowWidget.star = CreateFrame("Button", nil, rowWidget)
    rowWidget.star:SetSize(16, 16)
    rowWidget.star:SetPoint("LEFT", rowWidget, "LEFT", 4, 0)
    rowWidget.star.icon = rowWidget.star:CreateTexture(nil, "ARTWORK")
    rowWidget.star.icon:SetAllPoints()
    rowWidget.star:SetScript("OnClick", FlightMapWindow.starOnclick)
    rowWidget.star:SetScript("OnEnter", FlightMapWindow.starOnenter)
    rowWidget.star:SetScript("OnLeave", FlightMapWindow.starOnleave)
    rowWidget.name = rowWidget:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rowWidget.name:SetPoint("TOPLEFT", rowWidget, "TOPLEFT", 24, -4)
    rowWidget.name:SetJustifyH("LEFT")
    rowWidget.time = rowWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowWidget.time:SetPoint("TOPRIGHT", rowWidget, "TOPRIGHT", -6, -5)
    rowWidget.time:SetJustifyH("RIGHT")
    rowWidget.region = rowWidget:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rowWidget.region:SetPoint("BOTTOMLEFT", rowWidget, "BOTTOMLEFT", 24, 4)
    rowWidget.region:SetJustifyH("LEFT")
    rowWidget.fare = rowWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowWidget.fare:SetPoint("BOTTOMRIGHT", rowWidget, "BOTTOMRIGHT", -6, 4)
    rowWidget.fare:SetJustifyH("RIGHT")
    for _, labelRegion in ipairs({ rowWidget.name, rowWidget.time, rowWidget.region, rowWidget.fare }) do
        if labelRegion.SetWordWrap then labelRegion:SetWordWrap(false) end
    end
    rowWidget:SetScript("OnEnter", FlightMapWindow.rowOnenter)
    rowWidget:SetScript("OnLeave", FlightMapWindow.rowOnleave)
    rowWidget:SetScript("OnClick", FlightMapWindow.rowOnclick)
    rowWidget:SetScript("OnHide", FlightMapWindow.rowOnleave)
    return rowWidget
end

function FlightMapWindow.fillRow(rowWidget, node)
    rowWidget.node, rowWidget.pin = node, currentState.pinByNode and currentState.pinByNode[node]
    local destination, region = FlightMapWindow.splitDestinationName(node.name)
    rowWidget.name:SetText(destination)
    if hasRecent(node) then
        region = "|cff85B9FF" .. L.RECENT .. "|r" .. (region ~= "" and (" · " .. region) or "")
    end
    rowWidget.region:SetText(region)
    rowWidget.star.icon:SetTexture(FlightMapWindow.hasFavorite(node) and STAR_ON_FILE or STAR_OFF_FILE)
    rowWidget.star.icon:SetAlpha(FlightMapWindow.hasFavorite(node) and 1 or 0.45)
    if node.type == "REACHABLE" then
        local sec, recorded = estimateFlightDuration(node)
        rowWidget.name:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
        rowWidget.time:SetText(sec and composeTime(sec, not recorded) or L.TIME_UNKNOWN)
        rowWidget.time:SetTextColor(recorded and 1 or STYLE.textMuted[1], recorded and 0.94 or STYLE.textMuted[2], recorded and 0.72 or STYLE.textMuted[3])
        rowWidget.fare:SetText(resolveFareText(node, 11))
    else
        rowWidget.name:SetTextColor(STYLE.disabled[1], STYLE.disabled[2], STYLE.disabled[3])
        rowWidget.time:SetText("")
        rowWidget.fare:SetText(resolveFlightPathStatus(node))
        rowWidget.fare:SetTextColor(STYLE.disabled[1], STYLE.disabled[2], STYLE.disabled[3])
    end
    if node.type == "REACHABLE" then rowWidget.fare:SetTextColor(STYLE.textBody[1], STYLE.textBody[2], STYLE.textBody[3]) end
    local textW = LIST_W - 24 - 8
    rowWidget.name:SetWidth(max(40, textW - (rowWidget.time:GetStringWidth() or 0) - 6))
    rowWidget.region:SetWidth(max(40, textW - (rowWidget.fare:GetStringWidth() or 0) - 6))
    rowWidget.sel:SetShown(hover.pin ~= nil and hover.pin == rowWidget.pin)
end

paintList = function()
    if not destinationListPanel then return end
    if not (ns.DB.showList and currentState.nodes) then destinationListPanel:Hide(); return end
    listItems = FlightMapWindow.compileSortedDestinationList()
    local visible = FlightMapWindow.visibleRowCount()
    local maxOffset = max(0, #listItems - visible)
    listOffset = min(max(0, listOffset), maxOffset)
    for i = 1, visible do
        local rowWidget = listRows[i]
        if not rowWidget then
            rowWidget = FlightMapWindow.buildRow(destinationListPanel)
            listRows[i] = rowWidget
        end
        rowWidget:ClearAllPoints()
        rowWidget:SetPoint("TOPLEFT", destinationListPanel, "TOPLEFT", 4, -(LIST_HEAD_H + (i - 1) * ROW_H))
        rowWidget:SetPoint("TOPRIGHT", destinationListPanel, "TOPRIGHT", -8, -(LIST_HEAD_H + (i - 1) * ROW_H))
        local node = listItems[listOffset + i]
        if node then
            FlightMapWindow.fillRow(rowWidget, node)
            rowWidget.bg:SetAlpha((listOffset + i) % 2 == 0 and 1 or 0)
            rowWidget:Show()
        else
            rowWidget.node, rowWidget.pin = nil, nil
            rowWidget:Hide()
        end
    end
    for i = visible + 1, #listRows do listRows[i]:Hide() end
    destinationListPanel.empty:SetText(L.LIST_EMPTY)
    destinationListPanel.empty:SetShown(#listItems == 0)
    if destinationListPanel.search and destinationListPanel.search.hint then
        destinationListPanel.search.hint:SetText(L.LIST_SEARCH)
    end
    local track = destinationListPanel:GetHeight() - LIST_HEAD_H - 8
    if maxOffset > 0 and track > 20 then
        local thumbH = max(16, track * visible / #listItems)
        destinationListPanel.thumb:SetHeight(thumbH)
        destinationListPanel.thumb:ClearAllPoints()
        destinationListPanel.thumb:SetPoint("TOPRIGHT", destinationListPanel, "TOPRIGHT", -2, -(LIST_HEAD_H + (track - thumbH) * listOffset / maxOffset))
        destinationListPanel.thumb:Show()
    else
        destinationListPanel.thumb:Hide()
    end
    for key, tabWidget in pairs(destinationListPanel.tabs) do
        tabWidget.text:SetText(L["SORT_" .. key:upper()])
        local active = (key == ns.DB.listSort)
        if tabWidget.SetBackdropColor then
            if active then
                tabWidget:SetBackdropColor(STYLE.accent[1] * 0.25, STYLE.accent[2] * 0.25, STYLE.accent[3] * 0.25, 0.96)
                tabWidget:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
            else
                tabWidget:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.92)
                tabWidget:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
            end
        end
        tabWidget.text:SetTextColor(
            active and STYLE.accent[1] or STYLE.textMuted[1],
            active and STYLE.accent[2] or STYLE.textMuted[2],
            active and STYLE.accent[3] or STYLE.textMuted[3]
        )
    end
    destinationListPanel:Show()
end

syncListSelection = function()
    for _, rowWidget in ipairs(listRows) do
        if rowWidget:IsShown() then rowWidget.sel:SetShown(hover.pin ~= nil and hover.pin == rowWidget.pin) end
    end
end

function FlightMapWindow.commitFilterStyle()
    for _, anchorTarget in ipairs(pinPool) do
        if anchorTarget.node and anchorTarget:IsShown() then anchorTarget:SetAlpha(FlightMapWindow.resolvePinBaseAlpha(anchorTarget.node)) end
    end
    for _, lb in ipairs(labelPool) do
        if lb.node then FlightMapWindow.styleLabel(lb, false) end
    end
end

function FlightMapWindow.assignQuery(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    currentState.queryRaw = text ~= "" and text or nil
    currentState.query = currentState.queryRaw and currentState.queryRaw:lower() or nil
    listOffset = 0
    FlightMapWindow.resetHover()
    FlightMapWindow.commitFilterStyle()
    paintList()
end

function FlightMapWindow.flyToFirstResult()
    for _, node in ipairs(listItems) do
        if node.type == "REACHABLE" then
            local pinFrame = currentState.pinByNode and currentState.pinByNode[node]
            if pinFrame then FlightMapWindow.pinOnclick(pinFrame) end
            return
        end
    end
end

function FlightMapWindow.buildList()
    local anchorTarget = CreateFrame("Frame", "EzWoWFlightMapList", mainWindowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    anchorTarget:SetWidth(LIST_W)
    if anchorTarget.SetBackdrop then
        anchorTarget:SetBackdrop(LABEL_BACKDROP)
        anchorTarget:SetBackdropColor(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.94)
        anchorTarget:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 0.85)
    end
    anchorTarget:EnableMouseWheel(true)
    anchorTarget:SetScript("OnMouseWheel", function(_, delta)
        listOffset = listOffset - delta * 3
        paintList()
    end)

    local search = CreateFrame("EditBox", "EzWoWFlightMapSearch", anchorTarget, BackdropTemplateMixin and "BackdropTemplate" or nil)
    search:SetSize(LIST_W - 16, 20)
    search:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 8, -6)
    search:SetFontObject(ChatFontNormal)
    search:SetTextInsets(6, 6, 0, 0)
    search:SetAutoFocus(false)
    if search.SetBackdrop then
        search:SetBackdrop(LABEL_BACKDROP)
        search:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
        search:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
    end
    if search.SetMaxLetters then search:SetMaxLetters(40) end
    local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", search, "LEFT", 6, 0)
    hint:SetText(L.LIST_SEARCH)
    search.hint = hint
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "" and not self:HasFocus())
        FlightMapWindow.assignQuery(text)
    end)
    search:SetScript("OnEditFocusGained", function(self)
        self.hint:Hide()
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        end
    end)
    search:SetScript("OnEditFocusLost", function(self)
        self.hint:SetShown((self:GetText() or "") == "")
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
        end
    end)
    search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        FlightMapWindow.flyToFirstResult()
    end)
    anchorTarget.search = search

    anchorTarget.tabs = {}
    local tabW = floor((LIST_W - 16) / 3)
    for i, key in ipairs({ "name", "time", "fare" }) do
        local tabWidget = CreateFrame("Button", nil, anchorTarget, BackdropTemplateMixin and "BackdropTemplate" or nil)
        tabWidget:SetSize(tabW - 2, 20)
        tabWidget:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 8 + (i - 1) * tabW, -30)
        if tabWidget.SetBackdrop then
            tabWidget:SetBackdrop(LABEL_BACKDROP)
            tabWidget:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.92)
            tabWidget:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
        end
        tabWidget.text = tabWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tabWidget.text:SetPoint("CENTER")
        tabWidget.text:SetText(L["SORT_" .. key:upper()])
        tabWidget.key = key
        tabWidget:SetScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
            end
        end)
        tabWidget:SetScript("OnLeave", function(self)
            local active = (self.key == ns.DB.listSort)
            if self.SetBackdropBorderColor then
                if active then
                    self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
                else
                    self:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
                end
            end
        end)
        tabWidget:SetScript("OnClick", function(self)
            ns.DB.listSort = self.key
            listOffset = 0
            paintList()
        end)
        anchorTarget.tabs[key] = tabWidget
    end

    anchorTarget.empty = anchorTarget:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    anchorTarget.empty:SetPoint("TOP", anchorTarget, "TOP", 0, -(LIST_HEAD_H + 20))
    anchorTarget.empty:SetText(L.LIST_EMPTY)
    anchorTarget.empty:Hide()
    anchorTarget.thumb = anchorTarget:CreateTexture(nil, "OVERLAY")
    anchorTarget.thumb:SetWidth(3)
    anchorTarget.thumb:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 0.65)
    anchorTarget.thumb:Hide()
    anchorTarget:Hide()
    destinationListPanel = anchorTarget
end

function FlightMapWindow.commitAlpha()
    if mainWindowFrame then mainWindowFrame:SetAlpha(ns.DB.alpha or 1) end
end

renderFlightMapCanvas = function()
    local art, nodes = currentState.art, currentState.nodes
    if not art or not nodes then return end
    FlightMapWindow.resetHover()
    local W, H = art.w, art.h
    local x0Val, y0Val, x1Val, y1Val = FlightMapWindow.calculateViewportCropBounds(W, H, nodes)
    local cwVal, chVal = x1Val - x0Val, y1Val - y0Val
    local uwVal, uhVal = UIParent:GetWidth(), UIParent:GetHeight()
    local listW = (ns.DB.showList and destinationListPanel) and (LIST_W + LIST_GAP) or 0
    local maxHeight=uhVal*.95-TITLE_H-FOOT_H
    local stateFlag=(uhVal*.78*ns.DB.scale)/chVal
    stateFlag=min(stateFlag,(uwVal*.92-2*PAD-listW)/cwVal,maxHeight/chVal)
    currentState.s,currentState.cx0,currentState.cy0,currentState.W,currentState.H=stateFlag,x0Val,y0Val,W,H
    local vwVal,vhVal=cwVal*stateFlag,chVal*stateFlag
    local mainW=max(vwVal+2*PAD+listW,MIN_WIDTH)
    local mapX=PAD+((mainW-2*PAD-listW)-vwVal)/2
    canvasViewport:ClearAllPoints();canvasViewport:SetPoint("TOPLEFT",mainWindowFrame,"TOPLEFT",mapX,-TITLE_H)
    canvasViewport:SetSize(vwVal,vhVal)
    labelOverlayLayer:ClearAllPoints();labelOverlayLayer:SetPoint("TOPLEFT",canvasViewport,"TOPLEFT",0,0)
    labelOverlayLayer:SetSize(vwVal,vhVal)
    mainWindowFrame:SetSize(mainW,vhVal+TITLE_H+FOOT_H);mainWindowFrame:SetScale(1)
    if mainWindowFrame.hintText then mainWindowFrame.hintText:SetText(L.HINT) end
    if destinationListPanel then
        destinationListPanel:ClearAllPoints()
        destinationListPanel:SetPoint("TOPRIGHT",mainWindowFrame,"TOPRIGHT",-PAD,-TITLE_H)
        destinationListPanel:SetHeight(vhVal)
    end
    FlightMapWindow.commitAlpha()

    for _, resolvedValue in ipairs(tilePool) do resolvedValue:Hide() end
    local used = 0
    for _, tile in ipairs(art.tiles) do
        local ix0, iy0 = max(tile.x0, x0Val), max(tile.y0, y0Val)
        local ix1, iy1 = min(tile.x1, x1Val, W), min(tile.y1, y1Val, H)
        if ix1 > ix0 and iy1 > iy0 then
            used = used + 1
            local textureRegion = tilePool[used]
            if not textureRegion then
                textureRegion = canvasViewport:CreateTexture(nil, "BACKGROUND", nil, 1)
                tilePool[used] = textureRegion
            end
            if tile.taxi then SetTaxiMap(textureRegion) else textureRegion:SetTexture(tile.file) end
            local twVal, thVal = tile.x1 - tile.x0, tile.y1 - tile.y0
            local duVal, dvVal = tile.u1 - tile.u0, tile.v1 - tile.v0
            textureRegion:SetTexCoord(
                tile.u0 + duVal * (ix0 - tile.x0) / twVal, tile.u0 + duVal * (ix1 - tile.x0) / twVal,
                tile.v0 + dvVal * (iy0 - tile.y0) / thVal, tile.v0 + dvVal * (iy1 - tile.y0) / thVal)
            textureRegion:ClearAllPoints()
            textureRegion:SetPoint("TOPLEFT", canvasViewport, "TOPLEFT", (ix0 - x0Val) * stateFlag, -(iy0 - y0Val) * stateFlag)
            textureRegion:SetSize((ix1 - ix0) * stateFlag, (iy1 - iy0) * stateFlag)
            textureRegion:Show()
        end
    end

    for _, anchorTarget in ipairs(pinPool) do anchorTarget:Hide(); anchorTarget.node = nil end
    currentState.pinByNode, currentState.currentPin = {}, nil
    local shown = {}
    local entryKey = 0
    local baseLevel = canvasViewport:GetFrameLevel()
    labelOverlayLayer:SetFrameLevel(baseLevel + 3)
    hoverOverlayLayer:SetFrameLevel(baseLevel + 2)
    for _, node in ipairs(nodes) do
        if FlightMapWindow.isElementCurrentlyVisible(node) then
            entryKey = entryKey + 1
            local pinFrame = pinPool[entryKey]
            if not pinFrame then
                pinFrame = FlightMapWindow.buildPin()
                pinPool[entryKey] = pinFrame
            end
            pinFrame.node = node
            local size = (node.type == "CURRENT") and PIN_SIZE_CURRENT or PIN_SIZE
            pinFrame:SetSize(size, size)
            pinFrame.baseSize = size
            pinFrame.icon:SetSize(size, size)
            pinFrame.hl:SetSize(size * 1.9, size * 1.9)
            FlightMapWindow.assignPinIcon(pinFrame, node.type)
            local distant = (node.type == "DISTANT")
            pinFrame:SetAlpha(FlightMapWindow.resolvePinBaseAlpha(node))
            pinFrame:SetFrameLevel(baseLevel + ((node.type == "CURRENT") and 8 or (distant and 5 or 6)))
            local pxVal, pyVal = FlightMapWindow.toView(node.x, node.y)
            pinFrame:ClearAllPoints()
            pinFrame:SetPoint("CENTER", canvasViewport, "TOPLEFT", pxVal, -pyVal)
            pinFrame:Show()
            currentState.pinByNode[node] = pinFrame
            if node.type == "CURRENT" then currentState.currentPin = pinFrame end
            shown[#shown + 1] = { pin = pinFrame, node = node, px = pxVal, py = pyVal, r = size / 2 }
        end
    end
    FlightMapWindow.layoutNonOverlappingLabels(shown)
    FlightMapWindow.dismissLines()
    paintList()
    if locationPulseFrame then locationPulseFrame:Place() end
end

-----------------------------------------------------------------------------
-- Persist Position
-----------------------------------------------------------------------------
function FlightMapWindow.persistPosition()
    local anchorTarget, _, relativePoint, coordX, coordY = mainWindowFrame:GetPoint(1)
    if anchorTarget then ns.DB.point = { anchorTarget, relativePoint, coordX, coordY } end
end

function FlightMapWindow.commitPosition()
    mainWindowFrame:ClearAllPoints()
    local anchorPoint = ns.DB.point
    if type(anchorPoint) == "table" and anchorPoint[1] then
        mainWindowFrame:SetPoint(anchorPoint[1], UIParent, anchorPoint[2] or anchorPoint[1], anchorPoint[3] or 0, anchorPoint[4] or 0)
    else
        mainWindowFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function FlightMapWindow.dismissAll()
    if CloseTaxiMap then CloseTaxiMap() end
    local tfVal = _G.TaxiFrame
    if tfVal and tfVal:IsShown() and HideUIPanel then HideUIPanel(tfVal) end
    if mainWindowFrame then mainWindowFrame:Hide() end
    FlightMapWindow.restoreDefaultFlightFrames()
end

function FlightMapWindow.createLocationPulseRing()
    local PulseAnimationDriver = CreateFrame("Frame", nil, canvasViewport)
    PulseAnimationDriver:SetAllPoints(canvasViewport)
    PulseAnimationDriver:EnableMouse(false)
    PulseAnimationDriver.rings, PulseAnimationDriver.t = {}, 0
    for i = 1, 2 do
        local ring = canvasViewport:CreateTexture(nil, "ARTWORK", nil, 2)
        if ring:SetTexture(RING_FILE) == false then ring:SetTexture(GLOW_FILE) end
        ring:SetBlendMode("ADD")
        ring:SetVertexColor(0.42, 1, 0.63)
        ring:Hide()
        PulseAnimationDriver.rings[i] = ring
    end
    function PulseAnimationDriver:Place()
        local pinFrame = currentState.currentPin
        local coordX, coordY
        if pinFrame and pinFrame:IsShown() then
            local _, _, _, pxVal, pyVal = pinFrame:GetPoint(1)
            coordX, coordY = pxVal, pyVal
        end
        if not (ns.DB.pulse and coordX) then
            for _, ring in ipairs(self.rings) do ring:Hide() end
            self:Hide()
            return
        end
        for _, ring in ipairs(self.rings) do
            ring:ClearAllPoints()
            ring:SetPoint("CENTER", canvasViewport, "TOPLEFT", coordX, coordY)
            ring:Show()
        end
        self:Show()
    end
    PulseAnimationDriver:SetScript("OnUpdate", function(self, dt)
        self.t = (self.t + min(dt or 0, 0.1)) % 2.4
        local base = (currentState.currentPin and currentState.currentPin.baseSize) or PIN_SIZE_CURRENT
        for i, ring in ipairs(self.rings) do
            local phase = (self.t / 2.4 + (i - 1) * 0.5) % 1
            local size = base * (1.15 + 1.85 * phase)
            ring:SetSize(size, size)
            ring:SetAlpha(0.8 * (1 - phase) ^ 1.6)
        end
    end)
    PulseAnimationDriver:Hide()
    ns.PulseAnimationDriver = PulseAnimationDriver
    return PulseAnimationDriver
end

function FlightMapWindow.buildUI()
    if mainWindowFrame then return end

    mainWindowFrame = CreateFrame("Frame", "EzWoWFlightMapFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    mainWindowFrame:Hide()
    mainWindowFrame:SetFrameStrata("HIGH")
    mainWindowFrame:SetToplevel(true)
    mainWindowFrame:SetClampedToScreen(true)
    mainWindowFrame:SetMovable(true)
    mainWindowFrame:EnableMouse(true)
    mainWindowFrame:RegisterForDrag("LeftButton")
    mainWindowFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mainWindowFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        FlightMapWindow.persistPosition()
    end)
    mainWindowFrame:SetScript("OnHide", function()
        if ns.CloseSettingsPopup then ns.CloseSettingsPopup() end
        FlightMapWindow.resetHover()
        if flightConfirmDialog then flightConfirmDialog:Hide() end
        if GameTooltip:IsShown() then GameTooltip:Hide() end
    end)
    if mainWindowFrame.SetBackdrop then
        mainWindowFrame:SetBackdrop(BACKDROP)
        mainWindowFrame:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.96)
        mainWindowFrame:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
    end

    titleText = mainWindowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", mainWindowFrame, "TOP", 0, -9)
    titleText:SetWidth(260)
    if titleText.SetWordWrap then titleText:SetWordWrap(false) end
    titleText:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
    titleText:SetText(L.TITLE)

    local close = createFlightMapButton(mainWindowFrame, 22, 22, false, FlightMapWindow.dismissAll)
    close:SetPoint("TOPRIGHT", mainWindowFrame, "TOPRIGHT", -8, -5)
    close.label:SetText("X")

    local gear = CreateFrame("Button", "EzWoWFlightMapGearButton", mainWindowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    gear:SetSize(22, 22)
    gear:SetPoint("TOPLEFT", mainWindowFrame, "TOPLEFT", 8, -5)
    if gear.SetBackdrop then
        gear:SetBackdrop(LABEL_BACKDROP)
        gear:SetBackdropColor(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.96)
        gear:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
    end
    local gearIcon = gear:CreateTexture(nil, "ARTWORK")
    gearIcon:SetPoint("TOPLEFT", 3, -3)
    gearIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    gearIcon:SetTexture(GEAR_FILE)
    gear:SetScript("OnClick", function() if ns.ToggleSettingsPopup then ns.ToggleSettingsPopup() end end)
    gear:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("EzWoW - Flight Map", STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
        GameTooltip:AddLine((L.SETTINGS or "설정") .. " (/ezfl)", STYLE.textBody[1], STYLE.textBody[2], STYLE.textBody[3])
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
        end
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

    local listBtn = CreateFrame("Button", "EzWoWFlightMapListButton", mainWindowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    listBtn:SetSize(22, 22)
    listBtn:SetPoint("LEFT", gear, "RIGHT", 6, 0)
    if listBtn.SetBackdrop then
        listBtn:SetBackdrop(LABEL_BACKDROP)
        listBtn:SetBackdropColor(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.96)
        listBtn:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
    end
    local listIcon = listBtn:CreateTexture(nil, "ARTWORK")
    listIcon:SetPoint("TOPLEFT", 3, -3)
    listIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    listIcon:SetTexture(LIST_FILE)
    listBtn:SetScript("OnClick", function()
        ns.DB.showList = not ns.DB.showList
        if renderFlightMapCanvas then renderFlightMapCanvas() end
    end)
    listBtn:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L.LIST_TOGGLE, STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
        GameTooltip:Show()
    end)
    listBtn:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then
            self:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
        end
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)

    canvasViewport = CreateFrame("Frame", nil, mainWindowFrame)
    canvasViewport:SetPoint("TOP", mainWindowFrame, "TOP", 0, -TITLE_H)
    if canvasViewport.SetClipsChildren then canvasViewport:SetClipsChildren(true) end
    local backdropTex = canvasViewport:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdropTex:SetAllPoints()
    backdropTex:SetColorTexture(0, 0, 0, 1)
    canvasViewport:EnableMouseWheel(true)
    canvasViewport:SetScript("OnMouseWheel", function(_, delta)
        if not IsControlKeyDown() then return end
        ns.DB.scale = max(0.5, min(1.2, floor((ns.DB.scale + delta * 0.05) * 20 + 0.5) / 20))
        FlightMapWindow.scheduleRender()
    end)

    labelOverlayLayer = CreateFrame("Frame", nil, mainWindowFrame)
    labelOverlayLayer:EnableMouse(false)
    hoverOverlayLayer = CreateFrame("Frame", nil, canvasViewport)
    hoverOverlayLayer:SetAllPoints(canvasViewport)
    hoverOverlayLayer:EnableMouse(false)
    hoverOverlayLayer.sparks = {}
    for i = 1, 3 do
        local spark = hoverOverlayLayer:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(GLOW_FILE)
        spark:SetBlendMode("ADD")
        spark:SetSize(i == 1 and 16 or 11, i == 1 and 16 or 11)
        spark:Hide()
        hoverOverlayLayer.sparks[i] = spark
    end
    hoverOverlayLayer:Hide()
    locationPulseFrame = FlightMapWindow.createLocationPulseRing()
    FlightMapWindow.buildList()

    local hint = mainWindowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", mainWindowFrame, "BOTTOM", 0, 7)
    hint:SetTextColor(STYLE.textMuted[1], STYLE.textMuted[2], STYLE.textMuted[3])
    hint:SetText(L.HINT)
    mainWindowFrame.hintText = hint

    FlightMapWindow.commitPosition()
end

-----------------------------------------------------------------------------
-- Construct Main Frame
-----------------------------------------------------------------------------
function FlightMapWindow.constructMainFrame()
    if not ns.snap or #ns.snap.list == 0 then return false end
    local art, kind = FlightMapWindow.readDefaultFlightArtwork(), "taxi"
    if not art then return false end

    local nodes = {}
    for _, recordEntry in ipairs(ns.snap.list) do
        if resolveFiniteNumber(recordEntry.plotX) and resolveFiniteNumber(recordEntry.plotY) then
            recordEntry.x, recordEntry.y = recordEntry.plotX, recordEntry.plotY
        elseif resolveFiniteNumber(recordEntry.tx) and resolveFiniteNumber(recordEntry.ty) and recordEntry.tx >= 0 and recordEntry.tx <= 1 and recordEntry.ty >= 0 and recordEntry.ty <= 1 then
            recordEntry.x, recordEntry.y = recordEntry.tx, ns.snap.invertFlightAxisY and (1 - recordEntry.ty) or recordEntry.ty
        else
            recordEntry.x, recordEntry.y = nil, nil
        end
        if recordEntry.x then nodes[#nodes + 1] = recordEntry end
    end
    if #nodes == 0 then return false end

    currentState.nodes, currentState.art, currentState.artKind, currentState.bySlot = nodes, art, kind, ns.snap.bySlot

    local titleStr = L.TITLE
    local mapID = ns.snap.mapID or resolveContinentMapID()
    if mapID and C_Map and C_Map.GetMapInfo then
        local apiInfo = C_Map.GetMapInfo(mapID)
        if apiInfo and apiInfo.name and apiInfo.name ~= "" then titleStr = titleStr .. " - " .. apiInfo.name end
    end
    titleText:SetText(titleStr)
    renderFlightMapCanvas()
    return true
end

function FlightMapWindow.openMainWindow()
    if not (ns.DB and ns.DB.enabled and currentState.open) then
        FlightMapWindow.restoreDefaultFlightFrames()
        return
    end
    local isCallOk, evalResult = pcall(function()
        FlightMapWindow.buildUI()
        return FlightMapWindow.constructMainFrame()
    end)
    if isCallOk and evalResult then
        FlightMapWindow.suppressDefaultFlightFrames()
        mainWindowFrame:Show()
        if ns.DB.autoSearch and ns.DB.showList and destinationListPanel and destinationListPanel:IsShown() and destinationListPanel.search then
            destinationListPanel.search:SetFocus()
        end
    else
        if mainWindowFrame then mainWindowFrame:Hide() end
        FlightMapWindow.restoreDefaultFlightFrames()
        if not isCallOk then printAddonChatMessage(L.MSG_ERROR:format(tostring(evalResult))) end
    end
end

function FlightMapWindow.closeActiveWindow()
    if mainWindowFrame then mainWindowFrame:Hide() end
    FlightMapWindow.restoreDefaultFlightFrames()
    currentState.nodes, currentState.art, currentState.bySlot, currentState.pinByNode, currentState.currentPin = nil, nil, nil, nil, nil
    if destinationListPanel and destinationListPanel.search then
        destinationListPanel.search:ClearFocus()
        if (destinationListPanel.search:GetText() or "") ~= "" then destinationListPanel.search:SetText("") end
    end
    currentState.query, currentState.queryRaw = nil, nil
end

function FlightMapWindow.refreshActiveView()
    if mainWindowFrame and mainWindowFrame:IsShown() and currentState.open then FlightMapWindow.constructMainFrame() end
end

function FlightMapWindow.assignEnabled(on)
    ns.DB.enabled = on and true or false
    if not ns.DB.enabled then
        if mainWindowFrame then mainWindowFrame:Hide() end
        FlightMapWindow.restoreDefaultFlightFrames()
    elseif currentState.open then
        FlightMapWindow.openMainWindow()
    end
end

local TAXI_GOSSIP_ICON = 132057   

function FlightMapWindow.hasFlightMasterGossipOption(o)
    if type(o) ~= "table" then return false end
    if o.type == "taxi" then return true end
    for _, icVal in ipairs({ o.icon or false, o.overrideIconID or false }) do
        if icVal == TAXI_GOSSIP_ICON then return true end
        if type(icVal) == "string" and icVal:lower():find("taxigossipicon", 1, true) then return true end
    end
    return false
end

function FlightMapWindow.onGossipShow()
    if not (ns.DB and ns.DB.enabled and ns.DB.skipGossip) then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    local groupLayoutData = C_GossipInfo
    if not (groupLayoutData and groupLayoutData.GetOptions and groupLayoutData.SelectOption) then return end
    
    local avail = groupLayoutData.GetNumAvailableQuests and groupLayoutData.GetNumAvailableQuests() or 0
    local active = groupLayoutData.GetNumActiveQuests and groupLayoutData.GetNumActiveQuests() or 0
    if avail > 0 or active > 0 then return end
    local opts = groupLayoutData.GetOptions()
    if type(opts) ~= "table" then return end
    for i, o in ipairs(opts) do
        if FlightMapWindow.hasFlightMasterGossipOption(o) then
            groupLayoutData.SelectOption(o.gossipOptionID or i)
            return
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TAXIMAP_OPENED")
eventFrame:RegisterEvent("TAXIMAP_CLOSED")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            bootstrapDB()
            if ns.RegisterOptionsPanel then ns.OptionsPanel = ns.RegisterOptionsPanel() end
            local tfVal = _G.TaxiFrame
            if tfVal and tfVal.HookScript then tfVal:HookScript("OnShow", FlightMapWindow.preMaskDefaultFlightFrame) end

        end
    elseif event == "TAXIMAP_OPENED" then
        currentState.open = true
        currentState.generation = (currentState.generation or 0) + 1
        local generation = currentState.generation
        local function capture()
            if not currentState.open or currentState.generation ~= generation then return end
            local isCallOk, payloadData = pcall(captureFlightGraphSnapshot)
            if isCallOk and payloadData and ns.snap and mainWindowFrame and mainWindowFrame:IsShown() and currentState.nodes
                and buildSnapshotHashKey(payloadData) == buildSnapshotHashKey(ns.snap) then
                return
            end
            ns.snap = isCallOk and payloadData or nil
            if not isCallOk then printAddonChatMessage(L.MSG_ERROR:format(tostring(payloadData))) end
            if ns.DB and ns.DB.enabled then FlightMapWindow.openMainWindow() end
        end
        C_Timer.After(0, capture)
        C_Timer.After(0.10, capture)
    elseif event == "TAXIMAP_CLOSED" then
        currentState.open = false
        currentState.generation = (currentState.generation or 0) + 1
        FlightMapWindow.closeActiveWindow()
    elseif event == "GOSSIP_SHOW" then
        FlightMapWindow.onGossipShow()
    end
end)

ns.Refresh = FlightMapWindow.refreshActiveView
ns.Build = FlightMapWindow.constructMainFrame
ns.RestoreDefaultFlightFrame = FlightMapWindow.restoreDefaultFlightFrames
ns.ScheduleRender = FlightMapWindow.scheduleRender
ns.SetEnabled = FlightMapWindow.assignEnabled
ns.ApplyAlpha = FlightMapWindow.commitAlpha
ns.ApplyPosition = FlightMapWindow.commitPosition
ns.Render = renderFlightMapCanvas
ns.RenderList = function() if paintList then paintList() end end
ns.GetMainFrame = function() return mainWindowFrame end
ns.GetListPanel = function() return destinationListPanel end

-----------------------------------------------------------------------------
-- Module Class & Compatibility Exports
-----------------------------------------------------------------------------
ns.RestoreBlizzard = ns.RestoreDefaultFlightFrame
FlightMapWindow.RestoreDefaultFlightFrame = ns.RestoreDefaultFlightFrame
