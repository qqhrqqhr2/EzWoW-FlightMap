--===========================================================================
-- EzWoW - Flight Map
-- Core/UIKit.lua : Unified EzWoW Surface, Widget & Event Dispatch Toolkit
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local UIKit = ns.UIKit or {}
ns.UIKit = UIKit

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"

UIKit.Theme = {
    bgPrimary   = { 0.071, 0.094, 0.122, 0.95 },
    bgSecondary = { 0.114, 0.157, 0.192, 0.96 },
    bgInput     = { 0.047, 0.067, 0.086, 0.96 },
    border      = { 0.204, 0.298, 0.357, 1.00 },
    textBody    = { 0.929, 0.957, 0.969, 1.00 },
    textMuted   = { 0.655, 0.725, 0.773, 1.00 },
    accent      = { 0.522, 0.725, 1.000, 1.00 },
    accentHex   = "85B9FF",
    warning     = { 0.906, 0.486, 0.439, 1.00 },
    disabled    = { 0.388, 0.447, 0.482, 1.00 },
}

local SHARED_BACKDROPS = {}

function UIKit:GetBackdropSpec(edgeSize, insetSize, tileFlag, tileSize)
    local e = edgeSize or 1
    local i = insetSize or 0
    local key = e .. ":" .. i .. ":" .. (tileFlag and 1 or 0) .. ":" .. (tileSize or 0)
    local spec = SHARED_BACKDROPS[key]
    if not spec then
        spec = {
            bgFile   = WHITE8X8,
            edgeFile = e > 0 and WHITE8X8 or nil,
            tile     = tileFlag or false,
            tileSize = tileSize or 0,
            edgeSize = e > 0 and e or nil,
            insets   = { left = i, right = i, top = i, bottom = i },
        }
        SHARED_BACKDROPS[key] = spec
    end
    return spec
end

function UIKit:ApplyBackdrop(frame, edgeSize, insetSize, tileFlag, tileSize)
    if not frame or not frame.SetBackdrop then return frame end
    frame:SetBackdrop(self:GetBackdropSpec(edgeSize, insetSize, tileFlag, tileSize))
    return frame
end

function UIKit:ApplySurface(frame, bgRGBA, borderRGBA, edgeSize, insetSize)
    if not frame or not frame.SetBackdrop then return frame end
    frame:SetBackdrop(self:GetBackdropSpec(edgeSize or 1, insetSize or 0))
    local bg = bgRGBA or self.Theme.bgPrimary
    local bd = borderRGBA or self.Theme.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.95)
    if frame.SetBackdropBorderColor and bd then
        frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1.0)
    end
    return frame
end

function UIKit:CreateLabel(parent, template, point, relFrame, relPoint, offsetX, offsetY, colorRGBA, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    if point then
        if type(relFrame) == "number" then
            fs:SetPoint(point, relFrame, relPoint or 0)
        else
            fs:SetPoint(point, relFrame or parent, relPoint or point, offsetX or 0, offsetY or 0)
        end
    end
    local col = colorRGBA or self.Theme.textBody
    fs:SetTextColor(col[1], col[2], col[3], col[4] or 1.0)
    if text then fs:SetText(text) end
    return fs
end

function UIKit:BindEvents(frame, handlerMap)
    if not frame or type(handlerMap) ~= "table" then return frame end
    for eventName in pairs(handlerMap) do
        pcall(frame.RegisterEvent, frame, eventName)
    end
    frame:SetScript("OnEvent", function(selfFrame, eventName, ...)
        local fn = handlerMap[eventName]
        if fn then fn(selfFrame, ...) end
    end)
    return frame
end

function UIKit:ElevateModal(frame, baseLevel)
    if not frame then return end
    local lvl = tonumber(baseLevel) or 260
    if frame.SetFrameStrata then frame:SetFrameStrata("TOOLTIP") end
    if frame.SetToplevel then frame:SetToplevel(true) end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    if frame.SetFrameLevel then frame:SetFrameLevel(lvl) end
    if frame.Raise then frame:Raise() end
end
