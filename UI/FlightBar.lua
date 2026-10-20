--===========================================================================
-- EzWoW - Flight Map
-- UI/FlightBar.lua : Live In-Flight Progress Timer Bar & Arrival Notification
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local InFlightTimerBar = ns.InFlightTimerBar or {}
ns.InFlightTimerBar = InFlightTimerBar

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local STYLE = ns.STYLE
local L = ns.L
local BACKDROP = ns.BACKDROP
local ICON_FILE = ns.ICON_FILE
local ICON_FALLBACK = ns.ICON_FALLBACK
local resolveFiniteNumber = ns.IsFiniteNumber
local shortName = ns.ExtractShortStationName
local composeTime = ns.FormatFlightDurationText
local composeClock = ns.FormatSecondsAsClock
local printAddonChatMessage = ns.Print
local estimateFlightDuration = ns.EstimateRouteFlightDuration
local computeHopDistanceRatios = ns.CalculateRouteHopProgressFractions

local flightTimerBarFrame
local pending

function InFlightTimerBar.persistBarPosition()
    local anchorTarget, _, relativePoint, coordX, coordY = flightTimerBarFrame:GetPoint(1)
    if anchorTarget then ns.DB.barPoint = { anchorTarget, relativePoint, coordX, coordY } end
end

function InFlightTimerBar.ensureFlightTimerBar()
    if flightTimerBarFrame then return end
    flightTimerBarFrame = CreateFrame("Frame", "EzWoWFlightMapBar", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    flightTimerBarFrame:SetSize(330, 32)
    flightTimerBarFrame:SetFrameStrata("MEDIUM")
    flightTimerBarFrame:SetClampedToScreen(true)
    flightTimerBarFrame:SetMovable(true)
    flightTimerBarFrame:EnableMouse(true)
    flightTimerBarFrame:RegisterForDrag("LeftButton")
    flightTimerBarFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    flightTimerBarFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        InFlightTimerBar.persistBarPosition()
    end)
    if flightTimerBarFrame.SetBackdrop then
        flightTimerBarFrame:SetBackdrop(BACKDROP)
        flightTimerBarFrame:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.94)
        flightTimerBarFrame:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
    end
    local iconTex = flightTimerBarFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(22, 22)
    iconTex:SetPoint("LEFT", flightTimerBarFrame, "LEFT", 6, 0)
    if iconTex:SetTexture(ICON_FILE.REACHABLE) == false then iconTex:SetTexture(ICON_FALLBACK.REACHABLE) end

    local sbVal = CreateFrame("StatusBar", nil, flightTimerBarFrame)
    sbVal:SetPoint("TOPLEFT", flightTimerBarFrame, "TOPLEFT", 32, -7)
    sbVal:SetPoint("BOTTOMRIGHT", flightTimerBarFrame, "BOTTOMRIGHT", -7, 7)
    sbVal:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    sbVal:SetStatusBarColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
    sbVal:SetMinMaxValues(0, 1)
    local sbg = sbVal:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.75)
    flightTimerBarFrame.status = sbVal

    flightTimerBarFrame.dest = sbVal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flightTimerBarFrame.dest:SetPoint("LEFT", sbVal, "LEFT", 5, 0)
    flightTimerBarFrame.dest:SetJustifyH("LEFT")
    flightTimerBarFrame.time = sbVal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flightTimerBarFrame.time:SetPoint("RIGHT", sbVal, "RIGHT", -5, 0)
    flightTimerBarFrame.time:SetJustifyH("RIGHT")
    flightTimerBarFrame.dest:SetPoint("RIGHT", flightTimerBarFrame.time, "LEFT", -6, 0)
    if flightTimerBarFrame.dest.SetWordWrap then flightTimerBarFrame.dest:SetWordWrap(false) end

    flightTimerBarFrame:ClearAllPoints()
    local anchorPoint = ns.DB.barPoint
    if type(anchorPoint) == "table" and anchorPoint[1] then
        flightTimerBarFrame:SetPoint(anchorPoint[1], UIParent, anchorPoint[2] or anchorPoint[1], anchorPoint[3] or 0, anchorPoint[4] or 0)
    else
        flightTimerBarFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
    flightTimerBarFrame:Hide()
end

function InFlightTimerBar.stopsText(elapsed)
    local stops = (pending.hops or 0) - 1
    if stops < 1 then return "" end
    local passed
    if pending.hopFractions and pending.total and pending.total > 0 then
        local windowFrame = elapsed / pending.total
        passed = 0
        for index = 1, stops do if windowFrame >= pending.hopFractions[index] then passed = index end end
        return "  |cffaaaaaa" .. L.BAR_STOPS:format(min(passed + 1, stops), stops) .. "|r"
    end
    return "  |cffaaaaaa" .. L.BAR_STOPS_N:format(stops) .. "|r"
end

function InFlightTimerBar.refreshFlightTimerBar(now)
    if not (flightTimerBarFrame and pending and pending.start) then return end
    local elapsed = now - pending.start
    flightTimerBarFrame.dest:SetText(shortName(pending.dest) .. InFlightTimerBar.stopsText(elapsed))
    if pending.total and pending.total > 0 then
        local remain = pending.total - elapsed
        flightTimerBarFrame.status:SetValue(min(1, elapsed / pending.total))
        if remain <= 0 then
            flightTimerBarFrame.time:SetText(L.BAR_SOON)
        else
            local left = pending.recorded and composeClock(remain) or L.APPROX:format(composeClock(remain))
            
            if date and time then
                left = left .. "  |cffbbbbbb" .. L.BAR_ETA:format(date("%H:%M", time() + floor(remain + 0.5))) .. "|r"
            end
            flightTimerBarFrame.time:SetText(left)
        end
    else
        flightTimerBarFrame.status:SetValue(1)
        flightTimerBarFrame.time:SetText(composeClock(elapsed))
    end
end

function InFlightTimerBar.displayFlightTimerBar()
    if not (ns.DB.flightBar and pending) then return end
    InFlightTimerBar.ensureFlightTimerBar()
    flightTimerBarFrame.dest:SetText(shortName(pending.dest))
    flightTimerBarFrame.status:SetValue(0)
    flightTimerBarFrame:Show()
    InFlightTimerBar.refreshFlightTimerBar(pending.start or GetTime())
end

function InFlightTimerBar.concealFlightTimerBar()
    if flightTimerBarFrame then flightTimerBarFrame:Hide() end
end

function InFlightTimerBar.triggerArrivalNotification()
    if not ns.DB.arrivalAlert then return end
    if PlaySound then
        local entityID = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960
        pcall(PlaySound, entityID, "Master")
    end
    if FlashClientIcon then pcall(FlashClientIcon) end
end

local watcher = CreateFrame("Frame")
watcher:Hide()
local elapsedAcc = 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    elapsedAcc = elapsedAcc + (elapsed or 0)
    if elapsedAcc < 0.1 then return end
    elapsedAcc = 0
    if not pending then
        InFlightTimerBar.concealFlightTimerBar()
        self:Hide()
        return
    end
    local now = GetTime()
    local isPlayerInFlight = UnitOnTaxi("player")
    if not pending.start then
        if isPlayerInFlight then
            pending.start = now
            InFlightTimerBar.displayFlightTimerBar()
        elseif now - pending.t0 > 15 then
            pending = nil
            self:Hide()
        end
    elseif isPlayerInFlight then
        InFlightTimerBar.refreshFlightTimerBar(now)
    else
        local dur = now - pending.start
        local arrived = not pending.earlyLanding
        if arrived and dur >= 5 and dur <= 3600 and ns.DB then
            local updatedVal = floor(dur + 0.5)
            local previousVal = ns.DB.times[pending.key]
            ns.DB.times[pending.key] = updatedVal
            if pending.dist and pending.dist > 0 then
                local measured = pending.dist / dur / (pending.speedMultiplier or 1)
                local previous = ns.DB.flightSpeeds[pending.speedKey]
                if not resolveFiniteNumber(previous) or previous < 8 or previous > 120 then previous = nil end
                if measured >= 8 and measured <= 120 and
                    (not resolveFiniteNumber(previous) or (measured >= previous * .75 and measured <= previous * 1.33)) then
                    ns.DB.flightSpeeds[pending.speedKey] = resolveFiniteNumber(previous) and
                        (previous * .75 + measured * .25) or measured
                end
            end
            if not previousVal or abs(previousVal - updatedVal) >= 3 then
                printAddonChatMessage(L.MSG_RECORDED:format(shortName(pending.dest), composeTime(dur)))
            end
            InFlightTimerBar.triggerArrivalNotification()
        end
        pending = nil
        InFlightTimerBar.concealFlightTimerBar()
        self:Hide()
    end
end)

if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(slot)
        local recordEntry = ns.snap and ns.snap.bySlot[slot]
        if not (recordEntry and recordEntry.type == "REACHABLE" and ns.snap.current and GetTime and UnitOnTaxi) then return end
        local grandTotal, recorded = estimateFlightDuration(recordEntry)
        ns.DB.recent[ns.snap.current] = recordEntry.name
        pending = {
            key = recordEntry.timeKey, dest = recordEntry.name, dist = recordEntry.dist,
            hops = recordEntry.hops, hopFractions = computeHopDistanceRatios(recordEntry),
            speedKey=ns.snap.speedKey, speedMultiplier=ns.snap.speedMultiplier,
            total = grandTotal, recorded = recorded, t0 = GetTime(),
        }
        elapsedAcc = 0
        watcher:Show()
    end)
end

if hooksecurefunc and TaxiRequestEarlyLanding then
    hooksecurefunc("TaxiRequestEarlyLanding", function()
        if pending then pending.earlyLanding = true end
    end)
end

function ns.ApplyFlightTimerBarLayout()
    if not (ns.DB and ns.DB.flightBar) then
        InFlightTimerBar.concealFlightTimerBar()
    elseif pending and pending.start then
        InFlightTimerBar.displayFlightTimerBar()
    end
end

function ns.ResetFlightTimerBarPosition()
    if flightTimerBarFrame then
        flightTimerBarFrame:ClearAllPoints()
        flightTimerBarFrame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

ns.StartInFlightProgressTimer = InFlightTimerBar.displayFlightTimerBar
ns.StopInFlightProgressTimer = InFlightTimerBar.concealFlightTimerBar

-----------------------------------------------------------------------------
-- Module Class Exports
-----------------------------------------------------------------------------
InFlightTimerBar.ApplyFlightTimerBarLayout = ns.ApplyFlightTimerBarLayout
InFlightTimerBar.StopInFlightProgressTimer = ns.StopInFlightProgressTimer
InFlightTimerBar.ResetFlightTimerBarPosition = ns.ResetFlightTimerBarPosition
InFlightTimerBar.StartInFlightProgressTimer = ns.StartInFlightProgressTimer
