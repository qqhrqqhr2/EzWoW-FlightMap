--===========================================================================
-- EzWoW shared : Libs/EzWoWGamePad/GamePad.lua
-- Gamepad helpers for the EzWoW addons. The same file ships in each of them;
-- the newest copy fills the shared table and the older copies use it.
--===========================================================================
-- 1. IsActive(): with the game's gamepad UI on, addon code must not open,
--    close or move the game's own windows (World Map, quest log, flight map,
--    profession window): the gamepad navigation then runs tainted, the game
--    blocks it and asks to turn the addon off. Each addon asks IsActive()
--    before such a call and leaves those windows to the player.
-- 2. Window navigation: the game's gamepad navigation only moves inside the
--    game's own windows. While an EzWoW window is open with the gamepad on,
--    the D-pad moves a highlight between its buttons, A clicks, X right-clicks,
--    LB / RB scroll the list under the highlight and B closes the window.
--    Windows are known by their global names (KNOWN_WINDOWS) and picked up
--    when the addon that owns them makes them.
-- 3. The EzWoW frames always on screen (quest list, utility bar, icons...):
--    the game's "change focus" button (View), pressed while no game window
--    is open, moves the highlight onto them; B gives the gamepad back.
--    The same mode has a key binding (Key Bindings > AddOns), so a gamepad
--    button can be set for it; with the World Map open it also reaches the
--    EzWoW icons and panels on the map. Pressed again, it gives the gamepad back.
-- Secure buttons (items, spells) can't be clicked by addon code: while one
-- is selected, A and X are bound to clicking it (an override binding).
local _, ns = ...
local type, pairs, ipairs, pcall, tonumber, select = type, pairs, ipairs, pcall, tonumber, select
local abs, huge = math.abs, math.huge

local LIB_VERSION = 22

-- one table for every copy, so a newer copy loaded later updates the
-- functions the older addons already hold
local lib = _G.EzWoW_GamePad
if type(lib) ~= "table" then
    lib = {}
    _G.EzWoW_GamePad = lib
end
ns.GamePad = lib
if (tonumber(lib.version) or 0) >= LIB_VERSION then return end
lib.version = LIB_VERSION

-- true while the game's gamepad input (and with it the gamepad UI) is on
function lib.IsActive()
    -- the gamepad UI itself (a pad plugged in with the UI off does not count)
    local util = _G.InputUtil
    if type(util) == "table" and type(util.IsGamepadUIEnabled) == "function" then
        local ok, on = pcall(util.IsGamepadUIEnabled)
        if ok and not (issecretvalue and issecretvalue(on)) then return on == true end
    end
    if C_GamePad and type(C_GamePad.IsEnabled) == "function" then
        local ok, on = pcall(C_GamePad.IsEnabled)
        if ok and on then return true end
    end
    local getBool = C_CVar and C_CVar.GetCVarBool
    if type(getBool) == "function" then
        local ok, on = pcall(getBool, "GamePadEnable")
        if ok and on then return true end
    end
    return false
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- key binding texts (Bindings.xml of the map addon)
do
    local ko = GetLocale and GetLocale() == "koKR"
    _G.BINDING_HEADER_EZWOWPAD = "EzWoW"
    _G.BINDING_NAME_EZWOW_PAD_FOCUS = ko and "게임패드: EzWoW 창으로 이동/돌아가기" or "Gamepad: move to / leave the EzWoW frames"
end
local function isSecret(v) return issecretvalue and issecretvalue(v) end

-- a frame method's result, or nil when it fails or is a secret value
-- (frames the game hides from addon code give secret values)
local function ask(f, method, ...)
    local fn = f and f[method]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, f, ...)
    if not ok or isSecret(v) then return nil end
    return v
end

local function visible(f) return ask(f, "IsVisible") == true end


-----------------------------------------------------------------------------
-- Windows
-----------------------------------------------------------------------------
-- EzWoW windows a player opens and uses with buttons
local KNOWN_WINDOWS = {
    "EzWoWBagsWindow",
    "EzWoWBestGearFinderFrame", "EzWoWBestGearFinderConfig", "EzWoWBestGearFinderSearchFrame", "EzWoWBestGearFinderDonate",
    "EzWoWChatTranslatorOptions",
    "EzWoWDruidFormsConfig", "EzWoWDruidFormsMenu", "EzWoWDruidFormsDonate",
    "EzWoW_DungeonRouteGuideFrame", "EzWoW_DungeonRouteGuideMapPanel", "EzWoW_DungeonRouteGuideConfig", "EzWoW_DungeonRouteGuideWingPicker", "EzWoW_DungeonRouteGuideDonate",
    "EzWoWErrorCatcherMain", "EzWoWErrorCatcherDonate",
    "EzWoWFlightMapFrame", "EzWoWFlightMapSettings", "EzWoWFlightMapWorldPopover", "EzWoWFlightMapConfirm", "EzWoWFlightMapDonate",
    "EzWoWFontChangerSettings",
    "EzWoWFrameMoverSettings", "EzWoWFrameMoverDonatePopup",
    "EzWoWGroupFinderMain", "EzWoWGroupFinderConfig", "EzWoWGroupFinderDonate",
    "EzWoWMapFinderPanel", "EzWoWMapFinderSettings", "EzWoWMapFinderDonate",
    "EzWoWMiniGamesWindow",
    "EzWoWProfessionRecipesFrame", "EzWoWProfessionRecipesSettings", "EzWoWProfessionRecipesDonate",
    "EzWoWQuestSettings",
    "EzWoW_SmartFishingWindow", "EzWoW_SmartFishingMapLegend", "EzWoW_SmartFishingConfig", "EzWoW_SmartFishingDonate",
    "EzWoWSpellControlSettings", "EzWoWSpellControlSpellsByLevel", "EzWoWSpellControlDonate",
    "EzWoWTooltipConfig", "EzWoWTooltipDonate",
    "EzWoWUnitFramesConfig", "EzWoWUnitFramesDonate",
    "EzWoWUtilityBarConfig", "EzWoWUtilityBarDonate",
}

-- EzWoW frames that stay on screen (reached with the game's View button)
local HUD_FRAMES = {
    "EzWoWQuest_TrackerFrame", "EzWoWUtilityBarFrame", "EzWoWSpellControlBoard", "EzWoWDruidFormsBar",
    "EzWoW_DungeonRouteGuideHUD", "EzWoW_DungeonRouteGuideIcon", "EzWoW_SmartFishingHUD",
    "EzWoW_ErrorCatcherIcon", "EzWoW_GroupFinderIcon", "EzWoWBestGearFinderLauncher",
    "EzWoWProfessionRecipesQuickButton", "EzWoWFlightMapBar",
}
lib.windows = lib.windows or {}      -- frame -> options
lib.stack = lib.stack or {}          -- open registered windows, newest last

-- options.close: function(frame) used for B (default frame:Hide())
function lib.RegisterWindow(frame, options)
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" or lib.windows[frame] then return end
    lib.windows[frame] = type(options) == "table" and options or {}
    frame:HookScript("OnShow", function(f) if lib.OnWindowShown then pcall(lib.OnWindowShown, f) end end)
    frame:HookScript("OnHide", function(f) if lib.OnWindowHidden then pcall(lib.OnWindowHidden, f) end end)
    if visible(frame) then lib.OnWindowShown(frame) end
end

function lib.RegisterKnownWindows()
    for _, name in ipairs(KNOWN_WINDOWS) do
        local f = _G[name]
        if type(f) == "table" and not lib.windows[f] then lib.RegisterWindow(f) end
    end
end

-----------------------------------------------------------------------------
-- Highlight around the selected button
-----------------------------------------------------------------------------
local function makeHighlight()
    local hl = CreateFrame("Frame", nil, UIParent)
    hl:SetFrameStrata("TOOLTIP")
    hl:EnableMouse(false)
    hl.edges = {}
    for i = 1, 4 do
        local t = hl:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.82, 0, 0.95)
        hl.edges[i] = t
    end
    local e = hl.edges
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(2)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(2)
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(2)
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(2)
    hl:Hide()
    return hl
end

-----------------------------------------------------------------------------
-- Targets: the buttons of the top window
-----------------------------------------------------------------------------
local MAX_TARGETS = 400

local function rectOf(f)
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not ok or not (l and b and w and h) or isSecret(l) or isSecret(b) or isSecret(w) or isSecret(h) then return nil end
    local s = ask(f, "GetEffectiveScale")
    if not s then return nil end
    return l * s, b * s, w * s, h * s
end

local function isTarget(f)
    if not (ask(f, "IsObjectType", "Button") or ask(f, "IsObjectType", "CheckButton") or ask(f, "IsObjectType", "Slider")) then
        return false
    end
    if f.IsMouseEnabled and ask(f, "IsMouseEnabled") ~= true then return false end
    if f.IsEnabled and ask(f, "IsEnabled") == false then return false end
    local _, _, w, h = rectOf(f)
    return w ~= nil and w >= 6 and h >= 6
end

local function collect(frame, out, depth, wl, wb, wr, wt)
    if depth > 14 or #out >= MAX_TARGETS then return end
    local children = { pcall(frame.GetChildren, frame) }
    for i = 2, #children do
        local child = children[i]
        if type(child) == "table" and visible(child) then
            local l, b, w, h = rectOf(child)
            if l and isTarget(child) then
                local cx, cy = l + w / 2, b + h / 2
                -- inside the window (rows scrolled out of a list are left out)
                if cx >= wl and cx <= wr and cy >= wb and cy <= wt then
                    out[#out + 1] = { frame = child, x = cx, y = cy }
                end
            end
            collect(child, out, depth + 1, wl, wb, wr, wt)
        end
    end
end

local function addFrameTargets(window, out)
    local l, b, w, h = rectOf(window)
    if not l then return end
    if isTarget(window) then
        out[#out + 1] = { frame = window, x = l + w / 2, y = b + h / 2 }
    end
    collect(window, out, 0, l, b, l + w, b + h)
end

local addMapDock, onMap   -- below

local function targetsOf(window)
    local out = {}
    addFrameTargets(window, out)
    -- a panel on the World Map: the map's EzWoW icons are reachable too
    if onMap(window) then addMapDock(out) end
    return out
end

-- EzWoW icons on the World Map (when it is open)
addMapDock = function(out)
    if not visible(_G.WorldMapFrame) then return end
    local dock = _G.EzWoWWorldMapDock
    if type(dock) ~= "table" or type(dock.items) ~= "table" then return end
    for _, entry in pairs(dock.items) do
        local btn = type(entry) == "table" and entry.button
        if type(btn) == "table" and visible(btn) then
            local l, b, w, h = rectOf(btn)
            if l then out[#out + 1] = { frame = btn, x = l + w / 2, y = b + h / 2 } end
        end
    end
end

onMap = function(frame)
    local map = _G.WorldMapFrame
    local f = frame
    for _ = 1, 12 do
        if not f then return false end
        if f == map then return true end
        f = ask(f, "GetParent")
    end
    return false
end

-- every EzWoW frame on screen (the View-button mode)
local function hudTargets()
    local out = {}
    addMapDock(out)
    for _, name in ipairs(HUD_FRAMES) do
        local f = _G[name]
        if type(f) == "table" and visible(f) then addFrameTargets(f, out) end
    end
    return out
end

-----------------------------------------------------------------------------
-- Navigation state
-----------------------------------------------------------------------------
local function topWindow()
    for i = #lib.stack, 1, -1 do
        local f = lib.stack[i]
        if visible(f) then return f end
        table.remove(lib.stack, i)
    end
    return nil
end

local function callScript(f, script)
    local fn = f and f.GetScript and f:GetScript(script)
    if fn then pcall(fn, f) end
end

-- A secure button (item, spell) can only be clicked by a key binding. While
-- one is selected the gamepad buttons are not taken by the navigation frame
-- (that would keep them from the bindings): every navigation button is bound
-- to a hidden helper button instead, and A / X to the secure button itself.
local NAV_KEYS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PAD2", "PADLSHOULDER", "PADRSHOULDER", "PADBACK" }

local function keyButton()
    if lib.keyButton then return lib.keyButton end
    local b = CreateFrame("Button", "EzWoWPadNavKey", UIParent)
    b:SetSize(1, 1)
    b:SetPoint("TOPLEFT")
    b:RegisterForClicks("AnyDown")
    b:SetScript("OnClick", function(_, key)
        if lib.OnButton then pcall(lib.OnButton, key) end
    end)
    lib.keyButton = b
    return b
end

local function bindSecure(target)
    local nav = lib.nav
    if not nav or inCombat() or not (ClearOverrideBindings and SetOverrideBindingClick) then return end
    pcall(ClearOverrideBindings, nav)
    local name = target and ask(target, "IsProtected") and ask(target, "GetName")
    if type(name) == "string" then
        keyButton()
        for _, key in ipairs(NAV_KEYS) do
            pcall(SetOverrideBindingClick, nav, true, key, "EzWoWPadNavKey", key)
        end
        pcall(SetOverrideBindingClick, nav, true, "PAD1", name, "LeftButton")
        pcall(SetOverrideBindingClick, nav, true, "PAD3", name, "RightButton")
        pcall(nav.EnableGamePadButton, nav, false)
        lib.boundSecure = true
        return
    end
    lib.boundSecure = false
    if lib.nav:IsShown() and (lib.hudMode or #lib.stack > 0) then
        pcall(nav.EnableGamePadButton, nav, true)
    end
end

-----------------------------------------------------------------------------
-- Key guide: the game's own guide line is gone while our frames have the
-- gamepad, so a line of ours shows the buttons under the window (or at the
-- bottom of the screen for the frames on screen)
-----------------------------------------------------------------------------
local HINTS = {
    koKR = { select = "선택", use = "사용", right = "오른쪽 클릭", scroll = "스크롤", close = "닫기", back = "돌아가기", move = "이동" },
    enUS = { select = "Select", use = "Use", right = "Right-click", scroll = "Scroll", close = "Close", back = "Back", move = "Move" },
}
local function hintText(key)
    local set = HINTS[(GetLocale and GetLocale()) or "enUS"] or HINTS.enUS
    return set[key] or HINTS.enUS[key]
end
-- the button as the game draws it for the connected pad (Xbox, PlayStation,
-- Switch... the game's own icon); plain text when the game has none
local function glyph(key, fallback)
    if type(GetBindingText) == "function" then
        local ok, text = pcall(GetBindingText, key)
        if ok and type(text) == "string" and text ~= "" and text ~= key and not isSecret(text) then return text end
    end
    return fallback
end

local function hintFrame()
    if lib.hint then return lib.hint end
    local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("TOOLTIP")
    f:EnableMouse(false)
    f:SetHeight(30)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
        f:SetBackdropBorderColor(1, 0.82, 0, 0.6)
    end
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("CENTER")
    f:Hide()
    lib.hint = f
    return f
end

function lib.UpdateHint()
    local holdingNow = lib.nav ~= nil and (lib.nav:IsGamePadButtonEnabled() or lib.boundSecure == true)
    if not holdingNow then
        if lib.hint then lib.hint:Hide() end
        return
    end
    local f = hintFrame()
    local secure = lib.boundSecure == true
    local window = nil
    for i = #lib.stack, 1, -1 do
        if visible(lib.stack[i]) then window = lib.stack[i] break end
    end
    local parts = {
        glyph("PADDUP", "") .. glyph("PADDDOWN", "") .. glyph("PADDLEFT", "") .. glyph("PADDRIGHT", "D-Pad") .. " " .. hintText("move"),
        glyph("PAD1", "A") .. " " .. hintText(secure and "use" or "select"),
        glyph("PAD3", "X") .. " " .. hintText("right"),
        glyph("PADLSHOULDER", "LB") .. glyph("PADRSHOULDER", "RB") .. " " .. hintText("scroll"),
        glyph("PAD2", "B") .. " " .. hintText(window and not lib.hudMode and "close" or "back"),
    }
    f.text:SetText(table.concat(parts, "    "))
    f:SetWidth((f.text:GetStringWidth() or 300) + 28)
    f:ClearAllPoints()
    if window and not lib.hudMode then
        f:SetPoint("TOP", window, "BOTTOM", 0, -4)
    else
        f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)
    end
    f:Show()
end

function lib.Select(target)
    local previous = lib.current
    if previous == target then return end
    bindSecure(target)
    if previous then
        callScript(previous, "OnLeave")
        if GameTooltip and GameTooltip:IsOwned(previous) then GameTooltip:Hide() end
    end
    lib.current = target
    lib.highlight = lib.highlight or makeHighlight()
    local hl = lib.highlight
    if not target then
        hl:Hide()
        lib.UpdateHint()
        return
    end
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", target, "TOPLEFT", -3, 3)
    hl:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 3, -3)
    hl:Show()
    callScript(target, "OnEnter")
    lib.UpdateHint()
end

-- the button closest to the top left, to start from
local function firstTarget(list)
    local best, bestScore = nil, huge
    for _, t in ipairs(list) do
        local score = -t.y * 2 + t.x
        if score < bestScore then best, bestScore = t, score end
    end
    return best and best.frame or nil
end

-- the nearest button in a direction (dx, dy) from the selected one
local function nextTarget(list, current, dx, dy)
    local cur
    for _, t in ipairs(list) do
        if t.frame == current then cur = t break end
    end
    if not cur then return firstTarget(list) end
    local best, bestScore = nil, huge
    for _, t in ipairs(list) do
        if t ~= cur then
            local vx, vy = t.x - cur.x, t.y - cur.y
            local along = vx * dx + vy * dy
            if along > 2 then
                local across = abs(vx * dy - vy * dx)
                local score = along + across * 2.5
                if score < bestScore then best, bestScore = t, score end
            end
        end
    end
    return best and best.frame or nil
end

local function stillThere(list, frame)
    for _, t in ipairs(list) do
        if t.frame == frame then return true end
    end
    return false
end

-- scroll the list under the selected button (its nearest parent that scrolls)
local function scroll(delta)
    local f = lib.current
    while f do
        local fn = f.GetScript and f:GetScript("OnMouseWheel")
        if fn then
            pcall(fn, f, delta)
            return
        end
        f = f.GetParent and f:GetParent()
    end
end

local DIRS = {
    PADDUP = { 0, 1 }, PADDDOWN = { 0, -1 }, PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 },
}

function lib.OnButton(button)
    local window = topWindow()
    if window then lib.hudMode = false end
    if not window and not lib.hudMode then lib.Release() return end
    local list = window and targetsOf(window) or hudTargets()
    if lib.current and not stillThere(list, lib.current) then lib.Select(nil) end
    local dir = DIRS[button]
    if dir then
        -- at the edge (nothing further that way) the highlight stays put
        local nextOne
        if lib.current then nextOne = nextTarget(list, lib.current, dir[1], dir[2]) else nextOne = firstTarget(list) end
        if nextOne then lib.Select(nextOne) end
    elseif button == "PAD1" or button == "PAD3" then
        local target = lib.current or firstTarget(list)
        if not target then return end
        if target ~= lib.current then lib.Select(target) return end
        -- secure buttons can't be clicked from addon code
        if ask(target, "IsProtected") then return end
        if target.Click then pcall(target.Click, target, button == "PAD3" and "RightButton" or "LeftButton") end
    elseif button == "PADLSHOULDER" then
        scroll(1)
    elseif button == "PADRSHOULDER" then
        scroll(-1)
    elseif button == "PADBACK" or button == "PADSOCIAL" then
        lib.ExitHUD()
    elseif button == "PAD2" then
        if not window then lib.ExitHUD() return end
        local options = lib.windows[window] or {}
        if type(options.close) == "function" then pcall(options.close, window) else window:Hide() end
    end
end

-- the navigation holds the gamepad (directly or through key bindings)
local function holding()
    local nav = lib.nav
    return nav ~= nil and (nav:IsGamePadButtonEnabled() or lib.boundSecure == true)
end

-- A frame made inside one of the game's open windows (the World Map...)
-- makes the game's gamepad cursor look that window over again as addon code,
-- and its buttons are then blocked. Frames are made without a parent and put
-- in afterwards (the same layer and level as a child gets).
function lib.MakeFrame(kind, name, parent, template)
    local f = CreateFrame(kind or "Frame", name, nil, template)
    if parent then f:SetParent(parent) end
    return f
end

-- The game's own focus keeper: true while the gamepad is in one of the
-- game's windows (then its windows keep the gamepad)
function lib.GameHasFocus()
    local mode = rawget(_G, "GamepadMode")
    local fcm = type(mode) == "table" and rawget(mode, "FrameControlsManager")
    if type(fcm) ~= "table" then return false end
    local on = rawget(fcm, "isUIFocused")
    if on ~= true or isSecret(on) then return false end
    -- the chat box keeps the focus after a line is sent: not a window
    local f = rawget(fcm, "focusedFrame")
    if type(f) ~= "table" or not visible(f) then return false end
    -- a game window masked by one of ours (alpha 0: the flight map) is not in use
    local alpha = ask(f, "GetEffectiveAlpha")
    if type(alpha) == "number" and alpha < 0.05 then return false end
    local name = ask(f, "GetName")
    if type(name) == "string" and name:find("^ChatFrame") then return false end
    return true
end

-- the gamepad is never kept while nothing of ours is on screen
function lib.Watchdog()
    local nav = lib.nav
    if not nav or inCombat() or not holding() then return end
    if topWindow() then return end
    if lib.hudMode and #hudTargets() > 0 then return end
    lib.hudMode = false
    lib.Release()
end

-- the View-button mode: the EzWoW frames on screen. From the key binding
-- (toggle = true) it also gives the gamepad back when pressed again, and an
-- open EzWoW window takes the highlight first.
function lib.EnterHUD(toggle)
    if not lib.IsActive() or inCombat() then return end
    if holding() then
        if toggle then lib.ExitHUD() end
        return
    end
    local window = topWindow()
    local list = window and targetsOf(window) or hudTargets()
    if #list == 0 then return end
    lib.hudMode = not window
    lib.Capture()
    lib.Select(firstTarget(list))
end

function lib.ExitHUD()
    lib.exitAt = GetTime and GetTime() or 0
    lib.hudMode = false
    lib.Release()
end

-----------------------------------------------------------------------------
-- The frame that takes the gamepad buttons while an EzWoW window is open
-----------------------------------------------------------------------------
local function navFrame()
    if lib.nav then return lib.nav end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(1, 1)
    f:SetPoint("TOPLEFT")
    f:EnableMouse(false)
    f:SetScript("OnGamePadButtonDown", function(_, button)
        if lib.OnButton then pcall(lib.OnButton, button) end
    end)
    lib.nav = f
    return f
end

function lib.Capture()
    if not lib.IsActive() or inCombat() then return end
    local f = navFrame()
    f:Show()
    pcall(f.EnableGamePadButton, f, true)
    lib.UpdateHint()
end

function lib.Release()
    lib.Select(nil)
    if lib.nav and not inCombat() then
        pcall(lib.nav.EnableGamePadButton, lib.nav, false)
        if ClearOverrideBindings then pcall(ClearOverrideBindings, lib.nav) end
        lib.boundSecure = false
    end
    if lib.UpdateHint then lib.UpdateHint() end
end

-- windows that are not given the gamepad when they show: panels on the
-- World Map (the map keeps it) and windows that open by themselves
local NO_AUTO = {
    EzWoWMapFinderPanel = true, EzWoW_SmartFishingMapLegend = true, EzWoW_DungeonRouteGuideMapPanel = true,
    EzWoWFlightMapWorldPopover = true, EzWoWMiniGamesWindow = true,
}

function lib.OnWindowShown(frame)
    for i = #lib.stack, 1, -1 do
        if lib.stack[i] == frame then table.remove(lib.stack, i) end
    end
    lib.stack[#lib.stack + 1] = frame
    if not lib.IsActive() or inCombat() then return end
    -- already moving in our frames (opened from there): go on in the new window
    local already = lib.nav ~= nil and (lib.nav:IsGamePadButtonEnabled() or lib.boundSecure == true)
    if not already then
        local name = ask(frame, "GetName")
        if (name and NO_AUTO[name]) or lib.GameHasFocus() then return end
    end
    lib.hudMode = false
    lib.Select(nil)
    lib.Capture()
end

function lib.OnWindowHidden(frame)
    for i = #lib.stack, 1, -1 do
        if lib.stack[i] == frame then table.remove(lib.stack, i) end
    end
    if lib.current then lib.Select(nil) end
    if not topWindow() and not lib.hudMode then lib.Release() end
end

-- The World Map's aim mode is left to the game. A hook on its crosshair frame
-- (or a binding on D-pad left) taints the game's gamepad input: its interact
-- target call is then blocked (ADDON_ACTION_FORBIDDEN in testing).
function lib.UpdateAimBinding()
    if not lib.aimBound then return end
    if not inCombat() and ClearOverrideBindings and lib.aimOwner then pcall(ClearOverrideBindings, lib.aimOwner) end
    lib.aimBound = false
end

function lib.HookAim() end

-- The game's View button (change focus): when the game has no window to
-- move the gamepad to, our frames take it
function lib.HookView()
    if lib.viewHooked or not hooksecurefunc then return end
    local mode = rawget(_G, "GamepadMode")
    if type(mode) ~= "table" or type(mode.ToggleUIFocus) ~= "function" then return end
    lib.viewHooked = pcall(hooksecurefunc, mode, "ToggleUIFocus", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                -- pressed while our frames have the gamepad: give it back
                local nav = lib.nav
                if nav and (nav:IsGamePadButtonEnabled() or lib.boundSecure == true) then
                    if lib.ExitHUD then pcall(lib.ExitHUD) end
                    return
                end
                if lib.EnterHUD and not lib.GameHasFocus() then pcall(lib.EnterHUD) end
            end)
        end
    end)
end
lib.HookView()

-- the game says there is no window to move the gamepad to: the EzWoW
-- frames on screen take it (after the game's own call has finished)
if not lib.errorHooked and UIErrorsFrame and hooksecurefunc then
    lib.errorHooked = true
    local function onMessage(_, text)
        if isSecret(text) or not ERROR_NO_FRAME_TO_FOCUS or text ~= ERROR_NO_FRAME_TO_FOCUS then return end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() if lib.EnterHUD then pcall(lib.EnterHUD) end end)
        end
    end
    pcall(hooksecurefunc, UIErrorsFrame, "AddMessage", onMessage)
    if UIErrorsFrame.AddExternalErrorMessage then
        pcall(hooksecurefunc, UIErrorsFrame, "AddExternalErrorMessage", onMessage)
    end
end

-- Nothing is added to the game's own menus (the map's filter menu): the
-- menu runs addon code while it is built, and with the gamepad UI on the
-- game's interact-target call after it is then blocked (tested).

-- With the World Map open the game keeps View inside the map (it does not go
-- through ToggleUIFocus, and there is no gamepad button event). While the map
-- is open the pad's button state is read (only read: nothing of the game's is
-- called or hooked); a View press then moves the gamepad to the EzWoW icons on
-- the map, and View again (taken by our frame) gives it back.
local VIEW_KEYS = { "PADBACK", "PADSOCIAL" }
local function viewDown()
    local pad = C_GamePad
    if type(pad) ~= "table" or type(pad.GetDeviceMappedState) ~= "function" then return false end
    local okId, id = pcall(pad.GetActiveDeviceID)
    if not okId or not id then return false end
    local okState, state = pcall(pad.GetDeviceMappedState, id)
    if not okState or type(state) ~= "table" or type(state.buttons) ~= "table" then return false end
    -- View / Back (Xbox), Create / Share (PlayStation), - (Switch)
    for _, key in ipairs(VIEW_KEYS) do
        local okIndex, index = pcall(pad.ButtonBindingToIndex, key)
        -- binding indexes start at 0
        if okIndex and type(index) == "number" and state.buttons[index + 1] == true then return true end
    end
    return false
end

-- Out in the world it is the same: when no game window had the gamepad
-- before the press and none has it after, the EzWoW frames on screen take it.
function lib.PollMapView()
    if not lib.IsActive() or inCombat() then
        lib.viewWasDown = false
        return
    end
    local down = viewDown()
    local pressed = down and not lib.viewWasDown
    lib.viewWasDown = down
    if not pressed then
        if not down then lib.focusBefore = lib.GameHasFocus() end
        return
    end
    if holding() then return end
    if lib.exitAt and GetTime and GetTime() - lib.exitAt < 0.4 then return end
    if visible(_G.WorldMapFrame) then
        local icons = {}
        addMapDock(icons)
        if #icons > 0 and lib.EnterHUD then pcall(lib.EnterHUD) end
        return
    end
    -- the press took the gamepad out of a game window: leave it to the game
    if lib.focusBefore then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
            if holding() or inCombat() or lib.GameHasFocus() then return end
            if lib.EnterHUD then pcall(lib.EnterHUD) end
        end)
    end
end

if not lib.viewPoll then
    lib.viewPoll = CreateFrame("Frame")
    local wait = 0
    lib.viewPoll:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.03
        if lib.PollMapView then pcall(lib.PollMapView) end
    end)
end

-- windows made later (most are made the first time they open)
if not lib.watcher and C_Timer and C_Timer.NewTicker then
    lib.watcher = C_Timer.NewTicker(2, function()
        if lib.RegisterKnownWindows and not inCombat() then pcall(lib.RegisterKnownWindows) end
        if lib.Watchdog then pcall(lib.Watchdog) end
        if lib.HookView and not lib.viewHooked then pcall(lib.HookView) end
        if lib.HookAim and not lib.aimHooked then pcall(lib.HookAim) end
        if lib.UpdateAimBinding then pcall(lib.UpdateAimBinding) end
    end)
end

-- combat: the buttons go back to the game; they come back after combat
if not lib.combatWatch then
    lib.combatWatch = CreateFrame("Frame")
    lib.combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
    lib.combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
    lib.combatWatch:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- (still allowed here: the lockdown starts right after this event)
            if lib.nav then
                pcall(lib.nav.EnableGamePadButton, lib.nav, false)
                if ClearOverrideBindings then pcall(ClearOverrideBindings, lib.nav) end
                lib.boundSecure = false
            end
            if lib.aimOwner and ClearOverrideBindings then
                pcall(ClearOverrideBindings, lib.aimOwner)
                lib.aimBound = false
            end
        elseif lib.Capture and topWindow() then
            lib.Capture()
        end
    end)
end
