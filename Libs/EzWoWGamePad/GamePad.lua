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
-- 4. Confirm(): a yes / no question of ours. With the gamepad UI on, the
--    game's confirmation popup (StaticPopup) or chat box opened from addon
--    code, or a frame made inside an open game window, runs the game's
--    gamepad navigation code from that call: it is refused and the
--    navigation stays broken until the interface is reloaded (tested).
-- Secure buttons (items, spells) can't be clicked by addon code: while one
-- is selected, A and X are bound to clicking it (an override binding).
local _, ns = ...
local type, pairs, ipairs, pcall, tonumber, select = type, pairs, ipairs, pcall, tonumber, select
local abs, huge = math.abs, math.huge

local LIB_VERSION = 25

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
    "EzWoWBestGearFinderCriteria", "EzWoWBestGearFinderTryOn", "EzWoWBestGearFinderExport",
    "EzWoWChatTranslatorOptions", "EzWoWChatTranslatorCopy",
    "EzWoWDruidFormsConfig", "EzWoWDruidFormsMenu", "EzWoWDruidFormsDonate",
    "EzWoW_DungeonRouteGuideFrame", "EzWoW_DungeonRouteGuideMapPanel", "EzWoW_DungeonRouteGuideConfig", "EzWoW_DungeonRouteGuideWingPicker", "EzWoW_DungeonRouteGuideDonate",
    "EzWoW_DungeonRouteGuideExport",
    "EzWoWErrorCatcherMain", "EzWoWErrorCatcherDonate",
    "EzWoWFlightMapFrame", "EzWoWFlightMapSettings", "EzWoWFlightMapWorldPopover", "EzWoWFlightMapConfirm", "EzWoWFlightMapDonate",
    "EzWoWFontChangerSettings", "EzWoWFontChangerFamily", "EzWoWFontChangerAdvanced", "EzWoWFontChangerTest",
    "EzWoWFrameMoverSettings", "EzWoWFrameMoverDonatePopup",
    "EzWoWGroupFinderMain", "EzWoWGroupFinderConfig", "EzWoWGroupFinderDonate",
    "EzWoWMapFinderPanel", "EzWoWMapFinderSettings", "EzWoWMapFinderDonate",
    "EzWoWMiniGamesWindow",
    "EzWoWProfessionRecipesFrame", "EzWoWProfessionRecipesSettings", "EzWoWProfessionRecipesDonate",
    "EzWoWQuestSettings",
    "EzWoWShareWindow",
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
    -- (cards that show up by themselves: reached with View, they never take the gamepad)
    "EzWoWQuestXPFrame", "EzWoWMapFinderRareCard", "EzWoWGroupFinderRepost",
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
-- Item buttons (bag slots, EzWoW - Bags) are not protected frames, but their
-- right click uses the item, which addon code can't do (tested: the game
-- blocked UseContainerItem when the navigation clicked a bag slot): they go
-- through the bindings too and are never clicked from addon code.
local NAV_KEYS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PAD2", "PADLSHOULDER", "PADRSHOULDER", "PADBACK" }

local function isItemButton(f)
    if ask(f, "IsObjectType", "ItemButton") then return true end
    return type(f) == "table" and (type(f.GetBagID) == "function" or type(f.GetSlotAndBagID) == "function")
end

-- clicked only through a key binding (secure buttons and item buttons)
local function clickedByBinding(f)
    return ask(f, "IsProtected") == true or isItemButton(f)
end

-- the global name a binding can click the button by (nil: it has none)
local function bindingName(f)
    local name = ask(f, "GetName")
    if type(name) == "string" and _G[name] == f then return name end
    return nil
end

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
    local name = target and clickedByBinding(target) and bindingName(target)
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
-- A pad the game has no entry for gets its plain number pictures (1 2 3 4).
-- The pad's maker (USB vendor number) still tells the layout of its buttons:
-- PadStyle() gives the maker's picture set, nil when there is none.
local MAKER_STYLE = { [0x045E] = "ltr", [0x054C] = "shp", [0x057E] = "rev" }   -- Microsoft, Sony, Nintendo
local GAME_LABELS = { letters = true, shapes = true, reverse = true }   -- the game's own picture sets
local STYLE_BUTTONS = {
    ltr = { PAD1 = "a", PAD2 = "b", PAD3 = "x", PAD4 = "y" },
    shp = { PAD1 = "cross", PAD2 = "circle", PAD3 = "square", PAD4 = "triangle" },
    -- (Nintendo: the bottom button is B, the right one A)
    rev = { PAD1 = "b", PAD2 = "a", PAD3 = "y", PAD4 = "x" },
}
local SHARED_BUTTONS = {
    PADLSHOULDER = "lshoulder", PADRSHOULDER = "rshoulder",
    PADDUP = "up", PADDDOWN = "down", PADDLEFT = "left", PADDRIGHT = "right",
}

-- (the game's active device is its combined one, which has no maker: the pads
-- themselves are looked at, the first one the game has no pictures of whose
-- maker is known)
function lib.PadStyle()
    local pad = C_GamePad
    if not (pad and pad.GetAllDeviceIDs and pad.GetDeviceRawState and pad.GetDeviceMappedState) then return nil end
    local ok, ids = pcall(pad.GetAllDeviceIDs)
    if not ok or type(ids) ~= "table" then return nil end
    for _, id in ipairs(ids) do
        local okRaw, raw = pcall(pad.GetDeviceRawState, id)
        local vendor = okRaw and type(raw) == "table" and raw.vendorID or nil
        local style = type(vendor) == "number" and not isSecret(vendor) and MAKER_STYLE[vendor] or nil
        if style then
            local okMap, mapped = pcall(pad.GetDeviceMappedState, id)
            local label = okMap and type(mapped) == "table" and mapped.labelStyle or nil
            if type(label) ~= "string" or isSecret(label) or not GAME_LABELS[label:lower()] then return style end
        end
    end
    return nil
end

-- the button as the game draws it for the connected pad (Xbox, PlayStation,
-- Switch... the game's own icon); where the game draws a number, the maker's
-- picture in the same size; plain text when the game has none
local function glyph(key, fallback)
    local text
    if type(GetBindingText) == "function" then
        local ok, t = pcall(GetBindingText, key)
        if ok and type(t) == "string" and t ~= "" and t ~= key and not isSecret(t) then text = t end
    end
    if text and text:lower():find("gamepad_gen_", 1, true) then
        local style = lib.PadStyle()
        local name = style and ((STYLE_BUTTONS[style] or {})[key] or SHARED_BUTTONS[key])
        local atlas = name and ("gamepad_" .. style .. "_" .. name .. "_64")
        if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            local swapped, n = text:gsub("|[Aa]:[^:|]+:", "|A:" .. atlas .. ":", 1)
            if n == 1 then return swapped end
        end
    end
    return text or fallback
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
        -- secure buttons and item buttons are clicked by the bindings (bindSecure), never from addon code
        if clickedByBinding(target) then return end
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
    -- (a question of ours takes it even from a game window)
    local modal = (lib.windows[frame] or {}).modal == true
    if not already and not modal then
        local name = ask(frame, "GetName")
        if (name and NO_AUTO[name]) or lib.GameHasFocus() then return end
    end
    lib.hudMode = false
    -- a question of ours: the button it came from is selected again when it closes
    if modal then lib.modalReturn = lib.current end
    lib.Select(nil)
    lib.Capture()
end

function lib.OnWindowHidden(frame)
    for i = #lib.stack, 1, -1 do
        if lib.stack[i] == frame then table.remove(lib.stack, i) end
    end
    local back
    if (lib.windows[frame] or {}).modal then back, lib.modalReturn = lib.modalReturn, nil end
    if lib.current then lib.Select(nil) end
    if not topWindow() and not lib.hudMode then
        lib.Release()
        return
    end
    if back and visible(back) and not inCombat() then lib.Select(back) end
    -- the key guide goes back under the window still open
    if lib.UpdateHint then lib.UpdateHint() end
end

-----------------------------------------------------------------------------
-- Confirm: a yes / no question of ours (for the gamepad UI, see 4. above).
-- Moved through like the other EzWoW windows; it takes the gamepad even from
-- a game window, B or Esc answers no. A question still open is replaced
-- without an answer (as the game's popup does when it is reused).
-----------------------------------------------------------------------------
local CONFIRM_WORDS = {
    koKR = { yes = "예", no = "아니요" },
    enUS = { yes = "Yes", no = "No" },
}

local function confirmWord(key)
    local set = CONFIRM_WORDS[(GetLocale and GetLocale()) or "enUS"] or CONFIRM_WORDS.enUS
    return set[key] or CONFIRM_WORDS.enUS[key]
end

local function runAnswer(fn)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

local function confirmFrame()
    if lib.confirm then return lib.confirm end
    local f = CreateFrame("Frame", "EzWoWPadConfirm", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetSize(380, 130)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.96)
        f:SetBackdropBorderColor(1, 0.82, 0, 0.7)
    end
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOP", f, "TOP", 0, -18)
    f.text:SetWidth(340)
    f.text:SetJustifyH("CENTER")
    local function answer(yes)
        local accept, cancel = f.onAccept, f.onCancel
        f.onAccept, f.onCancel, f.answered = nil, nil, true
        f:Hide()
        runAnswer(yes and accept or cancel)
    end
    f.yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.yes:SetSize(150, 24)
    f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
    f.yes:SetScript("OnClick", function() answer(true) end)
    f.no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.no:SetSize(150, 24)
    f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
    f.no:SetScript("OnClick", function() answer(false) end)
    -- closed some other way (Esc...): no
    f:SetScript("OnHide", function()
        if f.answered then return end
        local cancel = f.onCancel
        f.onAccept, f.onCancel, f.answered = nil, nil, true
        runAnswer(cancel)
    end)
    f:Hide()
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWPadConfirm") end
    lib.RegisterWindow(f, { modal = true, close = function() answer(false) end })
    lib.confirm = f
    return f
end

function lib.Confirm(text, onAccept, onCancel, yesText, noText)
    local f = confirmFrame()
    f.answered = true
    f:Hide()
    f.text:SetText(text or "")
    f.yes:SetText(yesText or confirmWord("yes"))
    f.no:SetText(noText or confirmWord("no"))
    f.onAccept, f.onCancel, f.answered = onAccept, onCancel, false
    f:SetHeight(math.max(110, (f.text:GetStringHeight() or 40) + 76))
    f:Show()
    return f
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
-- frames on screen take it (after the game's own call has finished). The
-- text on screen is not always ERROR_NO_FRAME_TO_FOCUS (the Korean client
-- shows "전환할 사용자 인터페이스 창이 없습니다!" while the string says
-- "집중할 ..."), so the common part is matched as well.
function lib.IsNoFrameMessage(text)
    if type(text) ~= "string" or isSecret(text) then return false end
    if ERROR_NO_FRAME_TO_FOCUS and text == ERROR_NO_FRAME_TO_FOCUS then return true end
    if text:find("사용자 인터페이스 창이 없", 1, true) then return true end
    local lower = text:lower()
    return lower:find("no ui window", 1, true) ~= nil or lower:find("no interface window", 1, true) ~= nil
end
if not lib.errorHooked and UIErrorsFrame and hooksecurefunc then
    lib.errorHooked = true
    local function onMessage(_, text)
        if not (lib.IsNoFrameMessage and lib.IsNoFrameMessage(text)) then return end
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

-----------------------------------------------------------------------------
-- Map marks and the gamepad cursor
-----------------------------------------------------------------------------
-- The World Map's gamepad cursor only looks at the game's own pin pools, so
-- the EzWoW marks drawn as plain frames on the map (quest marks, NPC spots,
-- search results) showed no tooltip with the gamepad. Those marks are
-- registered here (MapMark). While the cursor is on the map its position is
-- read (nothing of the game's is called or changed) and the mark under it
-- gets OnEnter / OnLeave from this addon's own update, as a mouse gives them.
lib.mapMarks = lib.mapMarks or setmetatable({}, { __mode = "k" })
function lib.MapMark(f)
    if type(f) == "table" then lib.mapMarks[f] = true end
end

local MARK_PAD = 3   -- screen pixels around a mark that still count as on it

-- all of a script's handlers (hooks too) when the client can run them so
local function runScript(f, script)
    local run = rawget(_G, "ExecuteFrameScript")
    if type(run) == "function" and pcall(run, f, script) then return end
    callScript(f, script)
end

-- the registered mark under a screen point (the top one when marks overlap)
local function markUnder(cx, cy)
    local best, bestLevel
    for f in pairs(lib.mapMarks) do
        -- (only marks on the World Map: the same pin kinds also show on the minimap)
        if visible(f) and ask(f, "IsMouseEnabled") ~= false and onMap(f) then
            local l, b, w, h = rectOf(f)
            if l and cx >= l - MARK_PAD and cx <= l + w + MARK_PAD and cy >= b - MARK_PAD and cy <= b + h + MARK_PAD then
                local level = ask(f, "GetFrameLevel") or 0
                if not best or level > bestLevel then best, bestLevel = f, level end
            end
        end
    end
    return best
end

function lib.MapHoverTick()
    local hit
    local map, cursor = rawget(_G, "WorldMapFrame"), rawget(_G, "SoftCursor")
    if type(cursor) == "table" and visible(map) and ask(cursor, "IsShown") == true and lib.IsActive() then
        local l, b, w, h = rectOf(cursor)
        if l and w > 0 then hit = markUnder(l + w / 2, b + h / 2) end
    end
    if hit == lib.mapHover then
        -- the game's own pin on the same spot was entered after ours and left the
        -- tooltip empty (seen with quest pins): ours again, a few times at most
        -- (a tooltip the game's pin shows itself is left alone)
        if hit and ask(GameTooltip, "IsShown") ~= true and (lib.markRetry or 0) < 3 then
            lib.markRetry = (lib.markRetry or 0) + 1
            runScript(hit, "OnEnter")
        end
        return
    end
    lib.markRetry = 0
    local old = lib.mapHover
    lib.mapHover = hit
    if old then runScript(old, "OnLeave") end
    if hit then runScript(hit, "OnEnter") end
end

-----------------------------------------------------------------------------
-- EzWoW map pins outside the game's pin pools (gamepad UI)
-----------------------------------------------------------------------------
-- With the gamepad UI on, the game's map runs the mouse-enter / mouse-leave
-- code of the pins near its cursor itself (also for every pin it lets go and
-- when the map closes). An EzWoW pin in its pools makes that addon code: the
-- rest of the game's call is tainted and its own gamepad step is refused
-- ("Interface action failed because of an AddOn" when the map was closed with
-- B, tested). While the gamepad UI is on, the EzWoW pins are made here
-- instead: the same template as a frame of our own on the map's canvas,
-- placed and scaled by this code (the map's own position code puts pins in
-- its nudging lists, so it is not called for them), the gamepad cursor's
-- hover coming through MapMark. With the gamepad UI off the map's pools are
-- used as before.
lib.ownPinSets = lib.ownPinSets or {}   -- template -> { active = { pin = true }, free = { pin, ... } }

local function ownPinCanvas(pin)
    local map = pin.owningMap
    return map, map and map.GetCanvas and map:GetCanvas()
end

local function placeOwnPin(pin)
    local _, canvas = ownPinCanvas(pin)
    local x, y = pin.normalizedX, pin.normalizedY
    if not (canvas and x and y) then return end
    local scale = pin:GetScale() or 1
    if scale <= 0 then scale = 1 end
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * x / scale, -canvas:GetHeight() * y / scale)
    -- (as the game does with the gamepad: nothing off the map art)
    pin:SetShown(x >= 0 and x <= 1 and y >= 0 and y <= 1)
end

local function scaleOwnPin(pin)
    local map = pin.owningMap
    if not map then return end
    local ignoreGlobal = type(pin.IsIgnoringGlobalPinScale) == "function" and pin:IsIgnoringGlobalPinScale()
    local scale
    if pin.startScale and pin.endScale then
        local canvasScale = map.GetCanvasScale and map:GetCanvasScale() or 1
        local zoom = map.GetCanvasZoomPercent and map:GetCanvasZoomPercent() or 0
        local f = math.max(0, math.min(1, (pin.scaleFactor or 1) * zoom))
        scale = (1 / (canvasScale > 0 and canvasScale or 1)) * (pin.startScale + (pin.endScale - pin.startScale) * f)
    elseif not ignoreGlobal then
        scale = 1
    end
    if scale then
        if not ignoreGlobal and map.GetGlobalPinScale then scale = scale * (map:GetGlobalPinScale() or 1) end
        pin:SetScale(scale)
    end
    placeOwnPin(pin)
end

-- the level the map would give the pin (its level table is only read)
local function levelOwnPin(pin)
    local map, canvas = ownPinCanvas(pin)
    local level
    local mgr = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    if type(mgr) == "table" and type(mgr.GetValidFrameLevel) == "function" then
        local ok, l = pcall(mgr.GetValidFrameLevel, mgr, pin.pinFrameLevelType, pin.pinFrameLevelIndex)
        if ok and type(l) == "number" and not isSecret(l) then level = l end
    end
    if not level and canvas then level = (canvas:GetFrameLevel() or 0) + 40 end
    if level then pin:SetFrameLevel(level) end
end

local ownPinHooked, ownPinKey
local function refreshOwnPins()
    local map = rawget(_G, "WorldMapFrame")
    local canvas = map and map.GetCanvas and map:GetCanvas()
    -- (the map calls its canvas hooks on every frame with the gamepad cursor on it)
    local key = canvas and map.GetCanvasScale and format("%.4f:%.1f:%.1f", map:GetCanvasScale() or 0, canvas:GetWidth() or 0, canvas:GetHeight() or 0)
    if key and key == ownPinKey then return end
    ownPinKey = key
    for _, set in pairs(lib.ownPinSets) do
        for pin in pairs(set.active) do pcall(scaleOwnPin, pin) end
    end
end

local function hookOwnPins(map)
    if ownPinHooked or type(map) ~= "table" or not hooksecurefunc then return end
    ownPinHooked = true
    for _, method in ipairs({ "OnCanvasScaleChanged", "OnCanvasSizeChanged" }) do
        if type(map[method]) == "function" then
            pcall(hooksecurefunc, map, method, function() pcall(refreshOwnPins) end)
        end
    end
end

-- A pin of an EzWoW template on the map (the map's pool, or ours with the gamepad UI on)
function lib.AcquireMapPin(map, template, ...)
    if not lib.IsActive() then return map:AcquirePin(template, ...) end
    local set = lib.ownPinSets[template]
    if not set then
        set = { active = {}, free = {} }
        lib.ownPinSets[template] = set
    end
    local canvas = map:GetCanvas()
    local pin = table.remove(set.free)
    if not pin then
        -- made without a parent and put on the canvas below (see lib.MakeFrame)
        pin = CreateFrame("Frame", nil, nil, template)
        -- the map's own position and scale code is not used for these pins
        pin.SetPosition = function(self, x, y)
            self.normalizedX, self.normalizedY = x, y
            placeOwnPin(self)
        end
        pin.ApplyCurrentPosition = placeOwnPin
        pin.ApplyCurrentScale = scaleOwnPin
        pin.ApplyFrameLevel = levelOwnPin
        -- the mouse as the map gives it to its pins
        pin:SetScript("OnEnter", function(self) if self.OnMouseEnter then self:OnMouseEnter() end end)
        pin:SetScript("OnLeave", function(self) if self.OnMouseLeave then self:OnMouseLeave() end end)
        pin:SetScript("OnMouseUp", function(self, button) if self.OnClick then self:OnClick(button) end end)
        lib.MapMark(pin)
        -- a template without an OnLoad script of its own gets its mixin's OnLoad here
        -- (one with it has run it already: twice would draw its textures twice)
        pin.owningMap = map
        if type(pin.OnLoad) == "function" and not pin:GetScript("OnLoad") then pin:OnLoad() end
    end
    pin:SetParent(canvas)
    pin.pinTemplate = template
    pin.owningMap = map
    set.active[pin] = true
    hookOwnPins(map)
    pin:Show()
    levelOwnPin(pin)
    if pin.OnAcquired then pin:OnAcquired(...) end
    scaleOwnPin(pin)
    return pin
end

-- every pin of the template, both kinds (the map's pool may still have some
-- from before the gamepad UI was turned on)
function lib.RemoveMapPins(map, template)
    if map and map.RemoveAllPinsByTemplate then map:RemoveAllPinsByTemplate(template) end
    local set = lib.ownPinSets[template]
    if not set then return end
    for pin in pairs(set.active) do
        if lib.mapHover == pin then
            lib.mapHover = nil
            runScript(pin, "OnLeave")
        end
        pin:Hide()
        pin:ClearAllPoints()
        if pin.OnReleased then pcall(pin.OnReleased, pin) end
        set.active[pin] = nil
        set.free[#set.free + 1] = pin
    end
end

-- every newer copy sets the update again (an older copy may have made the frame)
lib.markPoll = lib.markPoll or CreateFrame("Frame")
do
    local wait = 0
    lib.markPoll:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 0.06
        if lib.MapHoverTick and (lib.mapHover or next(lib.mapMarks)) then pcall(lib.MapHoverTick) end
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

-- combat: the buttons go back to the game; after combat they come back only
-- to what had them before (the window, or the frames on screen)
function lib.OnCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- (still allowed here: the lockdown starts right after this event)
        lib.combatHold = holding() and { current = lib.current, hud = lib.hudMode == true, focus = lib.GameHasFocus() } or nil
        -- highlight, tooltip; before the lines below (bindSecure(nil) turns the buttons back on)
        pcall(lib.Select, nil)
        lib.hudMode = false
        if lib.nav then
            pcall(lib.nav.EnableGamePadButton, lib.nav, false)
            if ClearOverrideBindings then pcall(ClearOverrideBindings, lib.nav) end
            lib.boundSecure = false
        end
        if lib.aimOwner and ClearOverrideBindings then
            pcall(ClearOverrideBindings, lib.aimOwner)
            lib.aimBound = false
        end
        pcall(lib.UpdateHint)   -- hides the key guide
        return
    end
    local saved = lib.combatHold
    lib.combatHold = nil
    if not saved or inCombat() or not lib.IsActive() or holding() then return end
    -- a game window took the gamepad during combat: leave it there
    if lib.GameHasFocus() and not saved.focus then return end
    local window = topWindow()
    local list = window and targetsOf(window) or (saved.hud and hudTargets()) or {}
    if #list == 0 then return end
    lib.hudMode = not window
    lib.Capture()
    -- re-select (and re-bind a secure button) only if it is still there
    if saved.current and stillThere(list, saved.current) then lib.Select(saved.current) end
end

lib.combatWatch = lib.combatWatch or CreateFrame("Frame")
pcall(lib.combatWatch.RegisterEvent, lib.combatWatch, "PLAYER_REGEN_DISABLED")
pcall(lib.combatWatch.RegisterEvent, lib.combatWatch, "PLAYER_REGEN_ENABLED")
-- set again by every newer copy (an older copy may have made the frame)
lib.combatWatch:SetScript("OnEvent", function(_, event)
    if lib.OnCombatEvent then pcall(lib.OnCombatEvent, event) end
end)
