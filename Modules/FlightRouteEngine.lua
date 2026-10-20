--===========================================================================
-- EzWoW - Flight Map
-- Modules/FlightRouteEngine.lua : Flight Node Graph Snapshot, Multi-Hop Pathing & ETA Calculator
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local FlightRouteEngine = ns.FlightRouteEngine or {}
ns.FlightRouteEngine = FlightRouteEngine

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local L = ns.L
local resolveFiniteNumber = ns.IsFiniteNumber
local resolveCoinText = ns.FormatCopperAsCoinString
local CONTINENT = ns.CONTINENT
local FPS_CURRENT = ns.FPS_CURRENT
local FPS_REACHABLE = ns.FPS_REACHABLE
local FPS_UNREACHABLE = ns.FPS_UNREACHABLE

function FlightRouteEngine.resolveNodeTypeOf(slot, st)
    if TaxiNodeGetType then
        local resolvedValue = TaxiNodeGetType(slot)
        if resolvedValue then return resolvedValue end
    end
    if st == FPS_CURRENT then return "CURRENT" end
    if st == FPS_REACHABLE then return "REACHABLE" end
    if st == FPS_UNREACHABLE then return "DISTANT" end
    return "NONE"
end

function FlightRouteEngine.resolveContinentMapID()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return end
    local entityID = C_Map.GetBestMapForUnit("player")
    for _ = 1, 10 do
        if not entityID then return end
        local apiInfo = C_Map.GetMapInfo(entityID)
        if not apiInfo then return end
        if apiInfo.mapType == CONTINENT then return entityID end
        if apiInfo.mapType and apiInfo.mapType < CONTINENT then return end
        entityID = apiInfo.parentMapID
    end
end

function FlightRouteEngine.enrichFlightNodesFromAPI(s)
    if not (s and s.list and s.bySlot) then return end
    for _, recordEntry in ipairs(s.list) do recordEntry.nodeID, recordEntry.apiCost, recordEntry.undiscovered = nil, nil, nil end
    if not (s.flightMapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
    local isCallOk, collectMapFlightNodes = pcall(C_TaxiMap.GetAllTaxiNodes, s.flightMapID)
    if not isCallOk or type(collectMapFlightNodes) ~= "table" then return end
    local visitedMap = {}
    for _, nodeEntry in ipairs(collectMapFlightNodes) do
        local recordEntry = type(nodeEntry) == "table" and s.bySlot[nodeEntry.slotIndex]
        if recordEntry and nodeEntry.name == recordEntry.name and FlightRouteEngine.resolveNodeTypeOf(recordEntry.slot, nodeEntry.state) == recordEntry.type then
            if visitedMap[recordEntry.slot] then
                recordEntry.nodeID, recordEntry.apiCost = nil, nil
            else
                if resolveFiniteNumber(nodeEntry.nodeID) and nodeEntry.nodeID > 0 then recordEntry.nodeID = nodeEntry.nodeID end
                if resolveFiniteNumber(nodeEntry.cost) and nodeEntry.cost >= 0 then recordEntry.apiCost = floor(nodeEntry.cost) end
            end
            visitedMap[recordEntry.slot] = true
        end
    end

    if C_TaxiMap.GetTaxiNodesForMap then
        local isValid, pointList = pcall(C_TaxiMap.GetTaxiNodesForMap, s.mapID or s.flightMapID)
        if isValid and type(pointList) == "table" then
            local byID, duplicates = {}, {}
            for _, nodeEntry in ipairs(pointList) do
                if type(nodeEntry) == "table" and resolveFiniteNumber(nodeEntry.nodeID) then
                    if byID[nodeEntry.nodeID] then duplicates[nodeEntry.nodeID] = true end
                    byID[nodeEntry.nodeID] = nodeEntry
                end
            end
            for _, recordEntry in ipairs(s.list) do
                local nodeEntry = recordEntry.nodeID and byID[recordEntry.nodeID]
                if nodeEntry and not duplicates[recordEntry.nodeID] and nodeEntry.name == recordEntry.name and type(nodeEntry.isUndiscovered) == "boolean" then
                    recordEntry.undiscovered = nodeEntry.isUndiscovered
                end
            end
        end
    end
end

function FlightRouteEngine.resolveFlightPathStatus(node)
    return node and node.undiscovered == true and L.UNDISCOVERED or L.UNREACHABLE
end

function FlightRouteEngine.resolveFlightSpeedMultiplier()
    if not (C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetNodeInfo) then return 1 end
    local isCallOk, config = pcall(C_Traits.GetConfigIDByTreeID, 1188)
    if not isCallOk or not config then return 1 end
    local isValid, node = pcall(C_Traits.GetNodeInfo, config, 110300)
    if isValid and type(node) == "table" and (tonumber(node.activeRank) or 0) > 0 then return 1.2 end
    return 1
end

function FlightRouteEngine.sumDirectedRouteYards(recordEntry, s)
    if not (recordEntry.segs and #recordEntry.segs > 0 and #recordEntry.segs == recordEntry.hops) then return end
    local grandTotal = 0
    local paths = EzWoWFlightMapRouteDistances or {}
    for _, seg in ipairs(recordEntry.segs) do
        local alphaVal, buttonWidget = s.bySlot[seg[1]].nodeID, s.bySlot[seg[2]].nodeID
        local yards = alphaVal and buttonWidget and paths[alphaVal] and paths[alphaVal][buttonWidget]
        if not resolveFiniteNumber(yards) or yards <= 0 then return end
        grandTotal = grandTotal + yards
    end
    return grandTotal
end

function FlightRouteEngine.queryVerifiedFlightFare(recordEntry)
    if not (recordEntry and recordEntry.type == "REACHABLE") then return end
    if TaxiNodeName and TaxiNodeName(recordEntry.slot) ~= recordEntry.name then return end
    if TaxiNodeGetType and TaxiNodeGetType(recordEntry.slot) ~= "REACHABLE" then return end
    local routes
    if GetNumRoutes then
        local isCallOk, value = pcall(GetNumRoutes, recordEntry.slot)
        if not isCallOk or not resolveFiniteNumber(value) or value < 1 then return end
        routes = value
    end
    local value = recordEntry.apiCost
    local isCallOk = resolveFiniteNumber(value)
    if not isCallOk and TaxiNodeCost then isCallOk, value = pcall(TaxiNodeCost, recordEntry.slot) end
    if isCallOk and resolveFiniteNumber(value) and value >= 0 then

        if value > 0 or (routes and recordEntry.segs and #recordEntry.segs == routes) then return floor(value) end
    end
end

function FlightRouteEngine.resolveNearestFlightNode(list, tx, ty)
    if not (tx and ty) then return end
    local best, bestD = nil, 0.0005 * 0.0005
    local ambiguous = false
    for _, nodeEntry in ipairs(list) do
        if nodeEntry.tx then
            local dxVal, dyVal = nodeEntry.tx - tx, nodeEntry.ty - ty
            local dataEntry = dxVal * dxVal + dyVal * dyVal
            if best and abs(dataEntry-bestD) < 1e-10 then ambiguous = true
            elseif dataEntry < bestD then best, bestD, ambiguous = nodeEntry, dataEntry, false end
        end
    end
    if not ambiguous then return best end
end

function FlightRouteEngine.traceConnectedHopSlots(slot, s)
    if s and s._hopSlotCache and s._hopSlotCache[slot] then return s._hopSlotCache[slot] end
    local outputList = {}
    local nodeEntry = GetNumRoutes and GetNumRoutes(slot) or 0
    if not resolveFiniteNumber(nodeEntry) or nodeEntry < 1 or nodeEntry > 64 then return outputList end
    local sxf, syf = TaxiGetSrcX, TaxiGetSrcY
    local dxf, dyf = TaxiGetDestX or TaxiGetDstX, TaxiGetDestY or TaxiGetDstY
    for hop = 1, nodeEntry do
        local alphaVal, buttonWidget
        if TaxiGetNodeSlot then
            alphaVal = TaxiGetNodeSlot(slot, hop, true)
            buttonWidget = TaxiGetNodeSlot(slot, hop, false)
        end
        if not (alphaVal and s.bySlot[alphaVal] and buttonWidget and s.bySlot[buttonWidget]) then
            alphaVal, buttonWidget = nil, nil
            if sxf and syf and dxf and dyf then
                local naVal = FlightRouteEngine.resolveNearestFlightNode(s.list, sxf(slot, hop), syf(slot, hop))
                local nbVal = FlightRouteEngine.resolveNearestFlightNode(s.list, dxf(slot, hop), dyf(slot, hop))
                alphaVal, buttonWidget = naVal and naVal.slot, nbVal and nbVal.slot
            end
        end
        if alphaVal and buttonWidget and alphaVal ~= buttonWidget then outputList[#outputList + 1] = { alphaVal, buttonWidget } end
    end
    
    if #outputList ~= nodeEntry or not s.currentSlot or outputList[1][1] ~= s.currentSlot or outputList[#outputList][2] ~= slot then return {} end
    for index=2,#outputList do if outputList[index-1][2] ~= outputList[index][1] then return {} end end
    if s then s._hopSlotCache = s._hopSlotCache or {}; s._hopSlotCache[slot] = outputList end
    return outputList
end

function FlightRouteEngine.resolveRegionScale(region)
    if region.GetEffectiveScale then return region:GetEffectiveScale() end
    local parentFrame = region.GetParent and region:GetParent()
    if parentFrame and parentFrame.GetEffectiveScale then return parentFrame:GetEffectiveScale() end
    return 1
end

local DEFAULT_FLIGHT_MAP_REGIONS = { "TaxiMap", "TaxiFrameInsetBg" }
function FlightRouteEngine.resolveDefaultFlightMapRect()
    for _, displayName in ipairs(DEFAULT_FLIGHT_MAP_REGIONS) do
        local region = _G[displayName]
        if region and region.GetLeft and region.GetTop and region.GetWidth and region.GetHeight then
            local left, top = region:GetLeft(), region:GetTop()
            local frameWidth, frameHeight = region:GetWidth(), region:GetHeight()
            local calculateCanvasScale = FlightRouteEngine.resolveRegionScale(region)
            if resolveFiniteNumber(left) and resolveFiniteNumber(top) and resolveFiniteNumber(frameWidth) and resolveFiniteNumber(frameHeight)
                and frameWidth > 1 and frameHeight > 1 and resolveFiniteNumber(calculateCanvasScale) and calculateCanvasScale > 0 then
                return left * calculateCanvasScale, top * calculateCanvasScale, frameWidth * calculateCanvasScale, frameHeight * calculateCanvasScale
            end
        end
    end
end

function FlightRouteEngine.calibrateFlightAxisLayout(s)
    local left, top, frameWidth, frameHeight = FlightRouteEngine.resolveDefaultFlightMapRect()
    local topVotes, bottomVotes = 0, 0
    for _, recordEntry in ipairs(s.list) do
        recordEntry.plotX, recordEntry.plotY = nil, nil
        if left and resolveFiniteNumber(recordEntry.tx) and resolveFiniteNumber(recordEntry.ty) then
            local button = _G["TaxiButton" .. recordEntry.slot]
            if button and button.GetCenter and (not button.IsShown or button:IsShown())
                and (not button.GetID or button:GetID() == recordEntry.slot) then
                local bxVal, byVal = button:GetCenter()
                local calculateCanvasScale = FlightRouteEngine.resolveRegionScale(button)
                if resolveFiniteNumber(bxVal) and resolveFiniteNumber(byVal) and resolveFiniteNumber(calculateCanvasScale) and calculateCanvasScale > 0 then
                    local coordX, coordY = (bxVal * calculateCanvasScale - left) / frameWidth, (top - byVal * calculateCanvasScale) / frameHeight
                    local direct, inverted = abs(coordY - recordEntry.ty), abs(coordY - (1 - recordEntry.ty))
                    if coordX >= 0 and coordX <= 1 and coordY >= 0 and coordY <= 1
                        and abs(coordX - recordEntry.tx) + min(direct, inverted) < 0.04 then
                        recordEntry.plotX, recordEntry.plotY = coordX, coordY
                        if direct + 0.05 < inverted then topVotes = topVotes + 1
                        elseif inverted + 0.05 < direct then bottomVotes = bottomVotes + 1 end
                    end
                end
            end
        end
    end
    s.invertFlightAxisY = bottomVotes > topVotes
    s.layoutSource = (topVotes + bottomVotes > 0) and "stock-buttons" or "taxi-api-top"
    for _, recordEntry in ipairs(s.list) do
        if not recordEntry.plotX and resolveFiniteNumber(recordEntry.tx) and resolveFiniteNumber(recordEntry.ty)
            and recordEntry.tx >= 0 and recordEntry.tx <= 1 and recordEntry.ty >= 0 and recordEntry.ty <= 1 then
            recordEntry.plotX = recordEntry.tx

            recordEntry.plotY = s.invertFlightAxisY and (1 - recordEntry.ty) or recordEntry.ty
        end
    end
end

function FlightRouteEngine.captureFlightGraphSnapshot()
    local s = { bySlot = {}, list = {} }
    local totalCount = NumTaxiNodes and NumTaxiNodes() or 0
    for index = 1, totalCount do
        local resolvedValue = FlightRouteEngine.resolveNodeTypeOf(index)
        if resolvedValue ~= "NONE" then
            local tx, ty
            if TaxiNodePosition then tx, ty = TaxiNodePosition(index) end
            local recordEntry = {
                slot = index, type = resolvedValue, tx = tx, ty = ty,
                name = (TaxiNodeName and TaxiNodeName(index)) or "?",
                
                cost = nil,
            }
            s.bySlot[index] = recordEntry
            s.list[#s.list + 1] = recordEntry
            if resolvedValue == "CURRENT" then s.current, s.currentSlot = recordEntry.name, recordEntry.slot end
        end
    end

    s.mapID = FlightRouteEngine.resolveContinentMapID()
    if GetTaxiMapID then
        local isCallOk,entityID = pcall(GetTaxiMapID)
        if isCallOk then s.flightMapID = entityID end
    end
    FlightRouteEngine.calibrateFlightAxisLayout(s)
    for _, recordEntry in ipairs(s.list) do
        if recordEntry.type == "REACHABLE" then recordEntry.hops = GetNumRoutes and GetNumRoutes(recordEntry.slot) or 0 end
    end
    FlightRouteEngine.enrichFlightNodesFromAPI(s)
    s.speedMultiplier = FlightRouteEngine.resolveFlightSpeedMultiplier()
    s.speedKey = tostring(s.flightMapID or s.mapID or "taxi") .. ":" .. (UnitFactionGroup and UnitFactionGroup("player") or "?")

    for _, recordEntry in ipairs(s.list) do
        if recordEntry.type == "REACHABLE" then
            recordEntry.segs = FlightRouteEngine.traceConnectedHopSlots(recordEntry.slot, s)
            recordEntry.dist = FlightRouteEngine.sumDirectedRouteYards(recordEntry, s)
            recordEntry.cost = FlightRouteEngine.queryVerifiedFlightFare(recordEntry)
            local route={"native-taxi-v2", tostring(s.flightMapID or s.mapID or "taxi"), UnitFactionGroup and UnitFactionGroup("player") or "?", s.current or "?"}
            for _,seg in ipairs(recordEntry.segs) do route[#route+1]=s.bySlot[seg[1]].name..">"..s.bySlot[seg[2]].name end
            if #recordEntry.segs == 0 then route[#route+1]="unresolved-hops:"..tostring(recordEntry.hops) end
            route[#route+1]=recordEntry.name
            route[#route+1]="speed:" .. tostring(s.speedMultiplier)
            recordEntry.timeKey=table.concat(route," | ")
        end
    end
    return s
end

function FlightRouteEngine.buildSnapshotHashKey(s)
    if not s then return "" end
    local parts = {}
    for _, recordEntry in ipairs(s.list) do
        parts[#parts + 1] = ("%d|%s|%s|%.4f|%.4f|%s|%s|%s|%s|%d"):format(recordEntry.slot, recordEntry.type, recordEntry.name,
            recordEntry.plotX or -1, recordEntry.plotY or -1, tostring(recordEntry.cost), tostring(recordEntry.hops), tostring(recordEntry.dist),
            tostring(recordEntry.undiscovered), recordEntry.segs and #recordEntry.segs or -1)
    end
    return table.concat(parts, ";")
end

function FlightRouteEngine.estimateFlightDuration(recordEntry)
    if not (ns.snap and ns.snap.current and recordEntry) then return end
    local recordItem = ns.DB.times[recordEntry.timeKey]
    if resolveFiniteNumber(recordItem) and recordItem >= 5 and recordItem <= 3600 then return recordItem, true end
    if resolveFiniteNumber(recordEntry.dist) and recordEntry.dist > 0 then
        local speed = ns.DB.flightSpeeds[ns.snap.speedKey]
        if not resolveFiniteNumber(speed) or speed < 8 or speed > 120 then speed = 30.4 end
        local duration = recordEntry.dist / (speed * (ns.snap.speedMultiplier or 1))
        if resolveFiniteNumber(duration) and duration > 0 and duration <= 3600 then
            return max(1, floor(duration + 0.5)), false
        end
    end
end

function FlightRouteEngine.tooExpensive(node)
    if not (node and node.type == "REACHABLE" and resolveFiniteNumber(node.cost) and GetMoney) then return false end
    local money = GetMoney()
    return resolveFiniteNumber(money) and node.cost > money
end

function FlightRouteEngine.resolveFareText(node, size)
    local extractSafeTooltipText = resolveCoinText(node.cost, size)
    if FlightRouteEngine.tooExpensive(node) then return "|cffff4d4d" .. extractSafeTooltipText .. "|r" end
    return extractSafeTooltipText
end

function FlightRouteEngine.hasRecent(node)
    return node and ns.snap and ns.snap.current and ns.DB.recent[ns.snap.current] == node.name
end

function FlightRouteEngine.computeHopDistanceRatios(recordEntry)
    if not (ns.snap and recordEntry.segs and #recordEntry.segs > 1 and recordEntry.dist and recordEntry.dist > 0) then return end
    local paths, elapsedAcc, outputList = EzWoWFlightMapRouteDistances or {}, 0, {}
    for index, seg in ipairs(recordEntry.segs) do
        local alphaVal, buttonWidget = ns.snap.bySlot[seg[1]].nodeID, ns.snap.bySlot[seg[2]].nodeID
        local yards = alphaVal and buttonWidget and paths[alphaVal] and paths[alphaVal][buttonWidget]
        if not resolveFiniteNumber(yards) then return end
        elapsedAcc = elapsedAcc + yards
        outputList[index] = elapsedAcc / recordEntry.dist
    end
    return outputList
end

ns.ResolveFlightNodeStateType = FlightRouteEngine.resolveNodeTypeOf
ns.ResolvePlayerContinentMapID = FlightRouteEngine.resolveContinentMapID
ns.PopulateFlightNodesFromAPI = FlightRouteEngine.enrichFlightNodesFromAPI
ns.EvaluateFlightRouteReachability = FlightRouteEngine.resolveFlightPathStatus
ns.ResolveMountSpeedMultiplier = FlightRouteEngine.resolveFlightSpeedMultiplier
ns.CalculateDirectedRouteYards = FlightRouteEngine.sumDirectedRouteYards
ns.QueryVerifiedFlightRouteFare = FlightRouteEngine.queryVerifiedFlightFare
ns.FindNearestStationByFlightCoords = FlightRouteEngine.resolveNearestFlightNode
ns.TraceConnectedRouteHopSlots = FlightRouteEngine.traceConnectedHopSlots
ns.CalibrateFlightCanvasProjection = FlightRouteEngine.calibrateFlightAxisLayout
ns.CaptureActiveFlightGraphSnapshot = FlightRouteEngine.captureFlightGraphSnapshot
ns.ComputeFlightSnapshotSignature = FlightRouteEngine.buildSnapshotHashKey
ns.EstimateRouteFlightDuration = FlightRouteEngine.estimateFlightDuration
ns.IsRouteFareUnaffordable = FlightRouteEngine.tooExpensive
ns.FormatRouteFareDisplayText = FlightRouteEngine.resolveFareText
ns.IsRecentlyVisitedDestination = FlightRouteEngine.hasRecent
ns.CalculateRouteHopProgressFractions = FlightRouteEngine.computeHopDistanceRatios

-----------------------------------------------------------------------------
-- Module Class & Compatibility Exports
-----------------------------------------------------------------------------
ns.ContinentMapID = ns.ResolvePlayerContinentMapID
FlightRouteEngine.ResolvePlayerContinentMapID = ns.ResolvePlayerContinentMapID
ns.FareText = ns.FormatRouteFareDisplayText
FlightRouteEngine.FormatRouteFareDisplayText = ns.FormatRouteFareDisplayText
ns.FlightPathStatus = ns.EvaluateFlightRouteReachability
FlightRouteEngine.EvaluateFlightRouteReachability = ns.EvaluateFlightRouteReachability
ns.FlightSpeedMultiplier = ns.ResolveMountSpeedMultiplier
FlightRouteEngine.ResolveMountSpeedMultiplier = ns.ResolveMountSpeedMultiplier
ns.FlightTime = ns.EstimateRouteFlightDuration
FlightRouteEngine.EstimateRouteFlightDuration = ns.EstimateRouteFlightDuration
ns.HopFractions = ns.CalculateRouteHopProgressFractions
FlightRouteEngine.CalculateRouteHopProgressFractions = ns.CalculateRouteHopProgressFractions
ns.IsRecent = ns.IsRecentlyVisitedDestination
FlightRouteEngine.IsRecentlyVisitedDestination = ns.IsRecentlyVisitedDestination
ns.NativeFare = ns.QueryVerifiedFlightRouteFare
FlightRouteEngine.QueryVerifiedFlightRouteFare = ns.QueryVerifiedFlightRouteFare
ns.FindNearestStationByFlightCoords = ns.FindNearestStationByFlightCoords
FlightRouteEngine.FindNearestStationByFlightCoords = ns.FindNearestStationByFlightCoords
ns.NodeTypeOf = ns.ResolveFlightNodeStateType
FlightRouteEngine.ResolveFlightNodeStateType = ns.ResolveFlightNodeStateType
ns.CalibrateFlightCanvasProjection = ns.CalibrateFlightCanvasProjection
FlightRouteEngine.CalibrateFlightCanvasProjection = ns.CalibrateFlightCanvasProjection
ns.RouteDistance = ns.CalculateDirectedRouteYards
FlightRouteEngine.CalculateDirectedRouteYards = ns.CalculateDirectedRouteYards
ns.RouteSlots = ns.TraceConnectedRouteHopSlots
FlightRouteEngine.TraceConnectedRouteHopSlots = ns.TraceConnectedRouteHopSlots
ns.SnapSignature = ns.ComputeFlightSnapshotSignature
FlightRouteEngine.ComputeFlightSnapshotSignature = ns.ComputeFlightSnapshotSignature
ns.TakeSnapshot = ns.CaptureActiveFlightGraphSnapshot
FlightRouteEngine.CaptureActiveFlightGraphSnapshot = ns.CaptureActiveFlightGraphSnapshot
ns.TooExpensive = ns.IsRouteFareUnaffordable
FlightRouteEngine.IsRouteFareUnaffordable = ns.IsRouteFareUnaffordable
ns.PopulateFlightNodesFromAPI = ns.PopulateFlightNodesFromAPI
FlightRouteEngine.PopulateFlightNodesFromAPI = ns.PopulateFlightNodesFromAPI
