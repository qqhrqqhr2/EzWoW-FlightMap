--===========================================================================
-- EzWoW Shared WorldMap Dock Coordinator (v3)
-- Core/WorldMapDock.lua : Bottom-Left WorldMap Action Button & Panel Manager
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local math_max, math_min = math.max, math.min
local tsort = table.sort

local WorldMapDockManager = ns.WorldMapDockManager or {}
ns.WorldMapDockManager = WorldMapDockManager

local DOCK_PROTOCOL_VERSION = 3
local DOCK_SLOT_PRIORITY = {
    EzWoW_MapFinder         = 1,
    EzWoW_FlightMap         = 2,
    EzWoW_DungeonRouteGuide = 3,
    EzWoW_SmartFishing      = 4,
}

local DockCoordinator = _G.EzWoWWorldMapDock
if type(DockCoordinator) ~= "table" or (DockCoordinator.version or 0) < DOCK_PROTOCOL_VERSION then
    DockCoordinator = DockCoordinator or {}
    DockCoordinator.version = DOCK_PROTOCOL_VERSION
    DockCoordinator.items = DockCoordinator.items or {}
    DockCoordinator.ORDER = DOCK_SLOT_PRIORITY

    function DockCoordinator:GetCanvas()
        if not WorldMapFrame then return UIParent end
        if WorldMapFrame.GetCanvasContainer then
            local container = WorldMapFrame:GetCanvasContainer()
            if container then return container end
        end
        return WorldMapFrame.ScrollContainer or WorldMapFrame
    end

    function DockCoordinator:NormalizeButtonParent(btn, canvas)
        canvas = canvas or self:GetCanvas()
        if not (btn and canvas) then return canvas end
        if btn.GetParent and btn:GetParent() ~= canvas and btn.SetParent then
            pcall(btn.SetParent, btn, canvas)
        end
        if btn.GetScale and btn.SetScale and btn:GetScale() ~= 1 then
            pcall(btn.SetScale, btn, 1)
        end
        if btn.SetFrameStrata then
            btn:SetFrameStrata("HIGH")
        end
        if btn.SetFrameLevel and canvas.GetFrameLevel then
            btn:SetFrameLevel((canvas:GetFrameLevel() or 1) + 500)
        end
        btn:SetSize(28, 28)
        return canvas
    end

    -- Returns cursor position (relX, relY) and canvas dimensions (maxW, maxH)
    -- in btn's effective scale coordinate space relative to canvas BOTTOMLEFT.
    function DockCoordinator:GetCursorCanvasXY(btn)
        local canvas = self:NormalizeButtonParent(btn)
        if not canvas then return nil, nil, nil, nil end
        local bScale = (btn and btn.GetEffectiveScale and btn:GetEffectiveScale()) or (canvas.GetEffectiveScale and canvas:GetEffectiveScale()) or 1
        local cScale = (canvas.GetEffectiveScale and canvas:GetEffectiveScale()) or bScale
        local left, bottom, w, h = canvas:GetLeft(), canvas:GetBottom(), canvas:GetWidth(), canvas:GetHeight()
        if not (left and bottom and w and h and w > 0 and h > 0 and bScale > 0 and cScale > 0) then
            return nil, nil, nil, nil
        end
        local cx, cy = GetCursorPosition()
        if not (cx and cy) then return nil, nil, nil, nil end
        local relX = (cx - left * cScale) / bScale
        local relY = (cy - bottom * cScale) / bScale
        local maxW = w * cScale / bScale
        local maxH = h * cScale / bScale
        return relX, relY, maxW, maxH
    end

    -- Returns btn's current center (centerX, centerY) in btn's effective scale
    -- coordinate space relative to canvas BOTTOMLEFT.
    function DockCoordinator:GetButtonCanvasCenter(btn)
        local canvas = self:NormalizeButtonParent(btn)
        if not (btn and canvas) then return nil, nil, nil, nil end
        local bScale = (btn.GetEffectiveScale and btn:GetEffectiveScale()) or (canvas.GetEffectiveScale and canvas:GetEffectiveScale()) or 1
        local cScale = (canvas.GetEffectiveScale and canvas:GetEffectiveScale()) or bScale
        local left, bottom, w, h = canvas:GetLeft(), canvas:GetBottom(), canvas:GetWidth(), canvas:GetHeight()
        local bx, by = btn:GetCenter()
        if not (left and bottom and w and h and bx and by and w > 0 and h > 0 and bScale > 0 and cScale > 0) then
            return nil, nil, nil, nil
        end
        local centerX = (bx * bScale - left * cScale) / bScale
        local centerY = (by * bScale - bottom * cScale) / bScale
        local maxW = w * cScale / bScale
        local maxH = h * cScale / bScale
        return centerX, centerY, maxW, maxH
    end

    function DockCoordinator:CloseOthers(activeAddonId)
        for addonId, entry in pairs(self.items) do
            if addonId ~= activeAddonId and type(entry.closePanel) == "function" then
                pcall(entry.closePanel)
            end
        end
    end

    function DockCoordinator:Layout()
        if self._inLayout then return end
        local canvas = self:GetCanvas()
        if not canvas then return end
        self._inLayout = true

        local dockedEntries = {}
        for _, entry in pairs(self.items) do
            local btn = entry.button
            if btn then
                self:NormalizeButtonParent(btn, canvas)
                local autoAlign = type(entry.isAuto) ~= "function" or entry.isAuto()
                if autoAlign then
                    if not entry.isShown or entry.isShown() then
                        dockedEntries[#dockedEntries + 1] = entry
                    else
                        btn:Hide()
                    end
                elseif type(entry.onFreeLayout) == "function" then
                    if not entry.isShown or entry.isShown() then
                        btn:Show()
                        pcall(entry.onFreeLayout, btn, canvas)
                    else
                        btn:Hide()
                    end
                end
            end
        end

        tsort(dockedEntries, function(lhs, rhs)
            local pL = lhs.order or DOCK_SLOT_PRIORITY[lhs.id] or 99
            local pR = rhs.order or DOCK_SLOT_PRIORITY[rhs.id] or 99
            if pL ~= pR then return pL < pR end
            return tostring(lhs.id) < tostring(rhs.id)
        end)

        local totalDocked = #dockedEntries
        local baseX, baseY, stepY = 12, 35, 34
        for idx = 1, totalDocked do
            local entry = dockedEntries[idx]
            local btn = entry.button
            local posX = baseX
            local posY = baseY + (idx - 1) * stepY
            self:NormalizeButtonParent(btn, canvas)
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", posX, posY)
            btn:Show()
            if type(entry.onDockedLayout) == "function" then
                pcall(entry.onDockedLayout, btn, canvas, idx, totalDocked, posX, posY)
            end
        end

        self._inLayout = false
    end

    function DockCoordinator:EnsureHooks()
        if self.hooksInstalled or not WorldMapFrame then return end
        self.hooksInstalled = true
        WorldMapFrame:HookScript("OnShow", function() self:Layout() end)
        local canvas = self:GetCanvas()
        if canvas and canvas.HookScript then
            canvas:HookScript("OnSizeChanged", function() self:Layout() end)
        end
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function() self:Layout() end)
        end
    end

    function DockCoordinator:Register(addonId, spec)
        if not addonId or type(spec) ~= "table" then return end
        spec.id = addonId
        self.items[addonId] = spec
        self:EnsureHooks()
        self:Layout()
    end

    _G.EzWoWWorldMapDock = DockCoordinator
end
