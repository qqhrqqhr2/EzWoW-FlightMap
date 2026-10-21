--===========================================================================
-- EzWoW - Flight Map
-- UI/OptionsWindow.lua : EzWoW Style Settings Dialog, Sliders & Slash Commands
--===========================================================================
local ADDON_NAME, ns = ...
-- Text for the game's AddOns panel in the six languages without their own line: { deDE, frFR, esES, ruRU, zhCN, zhTW }
local PANEL_LANG_INDEX = { deDE = 1, frFR = 2, esES = 3, esMX = 3, ruRU = 4, zhCN = 5, zhTW = 6, de = 1, fr = 2, es = 3, ru = 4 }
local function panelText(code, ko, en, others)
    if code == "koKR" or code == "ko" then return ko end
    local index = PANEL_LANG_INDEX[code or ""]
    return (index and others and others[index]) or en
end
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local SettingsDialog = ns.SettingsDialog or {}
ns.SettingsDialog = SettingsDialog

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local STYLE = ns.STYLE
local L = ns.L
local DONATE_URL = ns.DONATE_URL
local MEDIA = ns.MEDIA
local BACKDROP = ns.BACKDROP
local LABEL_BACKDROP = ns.LABEL_BACKDROP
local LANG_OPTIONS = ns.LANG_OPTIONS
local LANG_ALIASES = ns.LANG_ALIASES
local FLIGHT_TIPS_KO = ns.FLIGHT_TIPS_KO
local FLIGHT_TIPS_EN = ns.FLIGHT_TIPS_EN
local currentState = ns.cur
local defaults = ns.defaults
local resolveActiveLocaleKey = ns.GetActiveLocaleKey
local createFlightMapButton = ns.CreateStyledButton
local printAddonChatMessage = ns.Print
local refreshActiveView = function() if ns.Refresh then ns.Refresh() end end
local assignEnabled = function(on) if ns.SetEnabled then ns.SetEnabled(on) end end
local commitBarSetting = function() if ns.ApplyFlightTimerBarLayout then ns.ApplyFlightTimerBarLayout() end end
local commitAlpha = function() if ns.ApplyAlpha then ns.ApplyAlpha() end end
local commitPosition = function() if ns.ApplyPosition then ns.ApplyPosition() end end
local renderFlightMapCanvas = function() if ns.Render then ns.Render() end end
local paintList = function() if ns.RenderList then ns.RenderList() end end
local constructMainFrame = function() if ns.Build then return ns.Build() end end
local restoreDefaultFlightFrames = function() if ns.RestoreDefaultFlightFrame then ns.RestoreDefaultFlightFrame() end end
local scheduleRender = function() if ns.ScheduleRender then ns.ScheduleRender() end end

local switchSettingsPopup, dismissSettingsPopup

local donateModalFrame
function SettingsDialog.openDonateDialog()
    if not donateModalFrame then
        local windowFrame = CreateFrame("Frame", "EzWoWFlightMapDonate", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        windowFrame:SetSize(380, 132)
        windowFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        ns.UIKit:ElevateModal(windowFrame, 260)
        windowFrame:EnableMouse(true)
        windowFrame:SetMovable(true)
        windowFrame:RegisterForDrag("LeftButton")
        windowFrame:SetScript("OnDragStart", windowFrame.StartMoving)
        windowFrame:SetScript("OnDragStop", windowFrame.StopMovingOrSizing)
        if windowFrame.SetBackdrop then
            windowFrame:SetBackdrop(BACKDROP)
            windowFrame:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.97)
            windowFrame:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
        end
        local titleStr = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleStr:SetPoint("TOP", windowFrame, "TOP", 0, -12)
        titleStr:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
        titleStr:SetText(L.DONATE_TITLE)
        windowFrame.title = titleStr
        local extractSafeTooltipText = windowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        extractSafeTooltipText:SetPoint("TOP", titleStr, "BOTTOM", 0, -8)
        extractSafeTooltipText:SetWidth(346)
        extractSafeTooltipText:SetText(L.DONATE_TEXT)
        windowFrame.desc = extractSafeTooltipText
        local inputBox = CreateFrame("EditBox", nil, windowFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        inputBox:SetSize(344, 24)
        inputBox:SetFrameLevel(windowFrame:GetFrameLevel() + 5)
        inputBox:SetPoint("BOTTOM", windowFrame, "BOTTOM", 0, 16)
        inputBox:SetFontObject(ChatFontNormal)
        inputBox:SetTextInsets(6, 6, 0, 0)
        inputBox:SetAutoFocus(false)
        if inputBox.SetBackdrop then
            inputBox:SetBackdrop(LABEL_BACKDROP)
            inputBox:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
            inputBox:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
        end
        inputBox:SetText(DONATE_URL)
        inputBox:SetScript("OnEditFocusGained", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 1)
            end
        end)
        inputBox:SetScript("OnEditFocusLost", function(self)
            if self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
            end
        end)
        inputBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(DONATE_URL)
                self:HighlightText()
            end
        end)
        inputBox:SetScript("OnEscapePressed", function() windowFrame:Hide() end)
        inputBox:SetScript("OnEnterPressed", function() windowFrame:Hide() end)
        inputBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
        windowFrame.eb = inputBox
        local close = createFlightMapButton(windowFrame, 22, 22, false, function() windowFrame:Hide() end)
        close:SetPoint("TOPRIGHT", windowFrame, "TOPRIGHT", -8, -8)
        close:SetFrameLevel(windowFrame:GetFrameLevel() + 5)
        close.label:SetText("X")
        donateModalFrame = windowFrame
    end
    donateModalFrame.title:SetText(L.DONATE_TITLE)
    donateModalFrame.desc:SetText(L.DONATE_TEXT)
    ns.UIKit:ElevateModal(donateModalFrame, 260)
    donateModalFrame:Show()
    if donateModalFrame.Raise then donateModalFrame:Raise() end
    donateModalFrame.eb:SetText(DONATE_URL)
    donateModalFrame.eb:SetFocus()
    donateModalFrame.eb:HighlightText()
end

local SETTINGS = {
    { kind = "header", label = "HEAD_BASIC" },
    { kind = "lang",   label = "OPT_LANG" },
    { kind = "check",  key = "enabled",           label = "OPT_ENABLED" },
    { kind = "check",  key = "skipGossip",        label = "OPT_SKIP", sub = "OPT_SKIP_SUB" },
    { kind = "check",  key = "confirmFlight",     label = "OPT_CONFIRM" },
    { kind = "header", label = "HEAD_MAP" },
    { kind = "check",  key = "worldMapFlights",   label = "OPT_WORLDMAP" },
    { kind = "check",  key = "worldMapAutoAlign", label = "OPT_AUTOALIGN" },
    { kind = "check",  key = "labels",            label = "OPT_LABELS" },
    { kind = "check",  key = "crop",              label = "OPT_CROP" },
    { kind = "check",  key = "showUnreachable",   label = "OPT_ALL" },
    { kind = "check",  key = "showList",          label = "OPT_LIST", sub = "OPT_LIST_SUB" },
    { kind = "check",  key = "pulse",             label = "OPT_PULSE" },
    { kind = "check",  key = "autoSearch",        label = "OPT_AUTOSEARCH", sub = "OPT_AUTOSEARCH_SUB" },
    { kind = "slider", key = "scale",     label = "OPT_SCALE", min = 50, max = 120, step = 5, fmt = "%d%%" },
    { kind = "slider", key = "alpha",     label = "OPT_ALPHA", min = 0,  max = 70,  step = 5, fmt = "%d%%" },
    { kind = "slider", key = "labelSize", label = "OPT_FONT",  min = 8,  max = 14,  step = 1, fmt = "%d" },
    { kind = "header", label = "HEAD_FLIGHT" },
    { kind = "check",  key = "flightBar",         label = "OPT_BAR", sub = "OPT_BAR_SUB" },
    { kind = "check",  key = "arrivalAlert",      label = "OPT_ALERT" },
}

local allSettingRefreshers = {}

function SettingsDialog.resolveOpt(key)
    if key == "scale" then return floor(ns.DB.scale * 100 + 0.5) end
    if key == "alpha" then return floor((1 - ns.DB.alpha) * 100 + 0.5) end
    if key == "labelSize" then return ns.DB.labelSize end
    return ns.DB[key] and true or false
end

function SettingsDialog.assignOpt(key, value)
    if key == "enabled" then
        assignEnabled(value)
    elseif key == "worldMapFlights" then
        ns.DB.worldMapFlights = value and true or false
        if ns.RefreshWorldMap then ns.RefreshWorldMap() end
    elseif key == "worldMapAutoAlign" then
        ns.DB.worldMapAutoAlign = value and true or false
        if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.Layout then
            _G.EzWoWWorldMapDock:Layout()
        end
        if ns.RefreshWorldMap then ns.RefreshWorldMap() end
    elseif key == "showList" then
        ns.DB.showList = value and true or false
        if ns.GetMainFrame() and (ns.GetMainFrame() and ns.GetMainFrame():IsShown()) and currentState.nodes then renderFlightMapCanvas() end
    elseif key == "pulse" then
        ns.DB.pulse = value and true or false
        if ns.PulseAnimationDriver then ns.PulseAnimationDriver:Place() end
    elseif key == "scale" then
        ns.DB.scale = value / 100
        scheduleRender()
    elseif key == "alpha" then
        ns.DB.alpha = 1 - value / 100
        commitAlpha()
    elseif key == "labelSize" then
        ns.DB.labelSize = value
        scheduleRender()
    elseif key == "flightBar" then
        ns.DB.flightBar = value and true or false
        commitBarSetting()
    else
        ns.DB[key] = value and true or false
        refreshActiveView()
    end
end

function SettingsDialog.syncAllLocaleUI()
    for _, resolveCallback in ipairs(allSettingRefreshers) do
        pcall(resolveCallback)
    end
    if ns.GetMainFrame() and (ns.GetMainFrame() and ns.GetMainFrame():IsShown()) and currentState.open then
        constructMainFrame()
    elseif paintList then
        paintList()
    end
    if ns.RefreshWorldMap then
        ns.RefreshWorldMap()
    end
end
ns.RefreshAllLocaleUI = SettingsDialog.syncAllLocaleUI

function SettingsDialog.buildSlider(parent, width)
    local stateFlag = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    stateFlag:SetOrientation("HORIZONTAL")
    stateFlag:SetSize(width, 12)
    if stateFlag.SetHitRectInsets then stateFlag:SetHitRectInsets(0, 0, -6, -6) end
    if stateFlag.SetBackdrop then
        stateFlag:SetBackdrop(LABEL_BACKDROP)
        stateFlag:SetBackdropColor(0.047, 0.067, 0.086, 0.96)
        stateFlag:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
    end
    stateFlag:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    stateFlag:EnableMouse(true)
    if stateFlag.SetObeyStepOnDrag then stateFlag:SetObeyStepOnDrag(true) end
    return stateFlag
end

-- Full language names for the language list (the grid used short codes like EN / DE)
local LANGUAGE_NAMES = {
    koKR = "한국어", enUS = "English", deDE = "Deutsch", frFR = "Français",
    esES = "Español", ruRU = "Русский", zhCN = "简体中文", zhTW = "繁體中文",
}
function SettingsDialog.languageName(key)
    if key == "auto" then return L.LANG_AUTO end
    return LANGUAGE_NAMES[key] or key
end

function SettingsDialog.assembleSettings(parent, x, y, width)
    local controls = {}
    local headerPool = {}
    local langBox
    local langLabelFS
    for _, optionEntry in ipairs(SETTINGS) do
        if optionEntry.kind == "header" then
            local headerBar = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerBar:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
            headerBar:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
            headerBar:SetText(L[optionEntry.label])
            headerBar.labelKey = optionEntry.label
            headerPool[#headerPool + 1] = headerBar
            local line = parent:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(STYLE.border[1], STYLE.border[2], STYLE.border[3], 0.7)
            line:SetSize(width, 1)
            line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
            y = y - 26
        elseif optionEntry.kind == "lang" then
            -- label on the left, combo box on the right: click the box, then pick a language
            langLabelFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            langLabelFS:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y - 4)
            langLabelFS:SetText(L[optionEntry.label])
            langLabelFS.labelKey = optionEntry.label
            langBox = createFlightMapButton(parent, 200, 22, false, nil)
            langBox:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
            local langItems = {}
            for entryIndex, item in ipairs(LANG_OPTIONS) do
                local key = item.key
                langItems[entryIndex] = { value = key, text = function() return SettingsDialog.languageName(key) end }
            end
            ns.LanguageDropdown.Attach(langBox, {
                items = langItems,
                colors = { bg = STYLE.bgPrimary, border = STYLE.border, accent = STYLE.accent, text = STYLE.textBody },
                get = function() return (ns.DB and ns.DB.lang) or "auto" end,
                set = function(key)
                    if not ns.DB then return end
                    ns.DB.lang = key
                    SettingsDialog.syncAllLocaleUI()
                end,
            })
            y = y - 30
        elseif optionEntry.kind == "check" then
            local checkWidget = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            checkWidget:SetSize(24, 24)
            checkWidget:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 2, y)
            local extractSafeTooltipText = checkWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            extractSafeTooltipText:SetPoint("LEFT", checkWidget, "RIGHT", 2, 1)
            extractSafeTooltipText:SetWidth(width - 30)
            extractSafeTooltipText:SetJustifyH("LEFT")
            extractSafeTooltipText:SetText(L[optionEntry.label])
            -- rows are 26px apart, so long translations shrink to one line
            ns.UIKit:FitFontString(extractSafeTooltipText, width - 30, 1)
            checkWidget.labelFS = extractSafeTooltipText
            checkWidget.labelKey = optionEntry.label
            checkWidget.labelWidth = width - 30
            y = y - 26
            if optionEntry.sub then
                local sub = checkWidget:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                sub:SetPoint("TOPLEFT", extractSafeTooltipText, "BOTTOMLEFT", 0, -2)
                sub:SetWidth(width - 30)
                sub:SetJustifyH("LEFT")
                sub:SetText(L[optionEntry.sub])
                ns.UIKit:FitFontString(sub, width - 30, 1)
                checkWidget.subFS = sub
                checkWidget.subKey = optionEntry.sub
                y = y - 12
            end
            checkWidget.optKey = optionEntry.key
            checkWidget:SetScript("OnClick", function(self)
                SettingsDialog.assignOpt(self.optKey, self:GetChecked() and true or false)
            end)
            checkWidget:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.labelFS and self.labelFS:GetText() or "", STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
                local hasKo = (resolveActiveLocaleKey() == "koKR")
                local otherTips = ns.FLIGHT_TIPS_OTHER and ns.FLIGHT_TIPS_OTHER[resolveActiveLocaleKey()]
                local tipWidget = (hasKo and FLIGHT_TIPS_KO[self.optKey]) or (otherTips and otherTips[self.optKey]) or FLIGHT_TIPS_EN[self.optKey] or (self.subFS and self.subFS:GetText())
                if tipWidget and tipWidget ~= "" then
                    GameTooltip:AddLine(tipWidget, 0.85, 0.90, 0.94, true)
                end
                GameTooltip:Show()
            end)
            checkWidget:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
            controls[#controls + 1] = checkWidget
            if optionEntry.key == "worldMapFlights" then
                ns.WorldMapSettingControls = ns.WorldMapSettingControls or {}
                table.insert(ns.WorldMapSettingControls, checkWidget)
                local factionDefs = {
                    { id = 2, key = "alliance", color = { 0.2, 0.6, 1.0 } },
                    { id = 1, key = "horde",    color = { 1.0, 0.2, 0.15 } },
                    { id = 0, key = "neutral",  color = { 1.0, 0.82, 0.2 } },
                }
                for fIdx, fdVal in ipairs(factionDefs) do
                    local fcb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
                    fcb:SetSize(22, 22)
                    fcb:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 18 + (fIdx - 1) * 116, y + 2)
                    local ftVal = fcb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    ftVal:SetPoint("LEFT", fcb, "RIGHT", 2, 0)
                    ftVal:SetTextColor(fdVal.color[1], fdVal.color[2], fdVal.color[3])
                    fcb.labelFS = ftVal
                    fcb.labelWidth = 116 - 24 - 4
                    fcb.factionID = fdVal.id
                    fcb.factionKey = fdVal.key
                    fcb.isFactionCheck = true
                    fcb:SetScript("OnClick", function(self)
                        if ns.GetWorldMapFactionSettings then
                            local fOpts = ns.GetWorldMapFactionSettings()
                            if fOpts then fOpts[self.factionID] = self:GetChecked() and true or false end
                        end
                        if ns.RefreshWorldMap then ns.RefreshWorldMap() end
                    end)
                    controls[#controls + 1] = fcb
                end
                y = y - 24
            end
        elseif optionEntry.kind == "slider" then
            local formatLocalizedLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            formatLocalizedLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 2, y - 4)
            formatLocalizedLabel:SetText(L[optionEntry.label])
            ns.UIKit:FitFontString(formatLocalizedLabel, width - 50, 1)   -- leaves room for the value on the right
            local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            value:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width - 2, y - 4)
            value:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
            local stateFlag = SettingsDialog.buildSlider(parent, width - 8)
            stateFlag:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y - 22)
            stateFlag:SetMinMaxValues(optionEntry.min, optionEntry.max)
            stateFlag:SetValueStep(optionEntry.step)
            stateFlag.optKey, stateFlag.valueText, stateFlag.fmt, stateFlag.step, stateFlag.isSlider = optionEntry.key, value, optionEntry.fmt, optionEntry.step, true
            stateFlag.labelFS, stateFlag.labelKey = formatLocalizedLabel, optionEntry.label
            stateFlag.labelWidth = width - 50
            stateFlag:SetScript("OnValueChanged", function(self, v)
                v = floor(v / self.step + 0.5) * self.step
                self.valueText:SetText(self.fmt:format(v))
                if self.updating then return end
                if v ~= SettingsDialog.resolveOpt(self.optKey) then SettingsDialog.assignOpt(self.optKey, v) end
            end)
            controls[#controls + 1] = stateFlag
            y = y - 46
        end
    end
    local function refresh()
        for _, headerBar in ipairs(headerPool) do
            headerBar:SetText(L[headerBar.labelKey])
        end
        if langLabelFS then
            langLabelFS:SetText(L[langLabelFS.labelKey])
            ns.UIKit:FitFontString(langLabelFS, width - 212, 1)
        end
        if langBox then
            langBox.label:SetText(SettingsDialog.languageName((ns.DB and ns.DB.lang) or "auto") .. " ▼")
            ns.UIKit:FitFontString(langBox.label, 192, 1)
            ns.LanguageDropdown.Refresh(langBox)
        end
        for _, themeColor in ipairs(controls) do
            if themeColor.isFactionCheck then
                local wmVal = L.WM or {}
                if themeColor.labelFS and themeColor.factionKey then
                    themeColor.labelFS:SetText(wmVal[themeColor.factionKey] or themeColor.factionKey)
                    ns.UIKit:FitFontString(themeColor.labelFS, themeColor.labelWidth, 1)
                end
                local fOpts = ns.GetWorldMapFactionSettings and ns.GetWorldMapFactionSettings()
                themeColor:SetChecked(fOpts and fOpts[themeColor.factionID] == true or false)
            else
                if themeColor.labelFS and themeColor.labelKey then
                    themeColor.labelFS:SetText(L[themeColor.labelKey])
                    ns.UIKit:FitFontString(themeColor.labelFS, themeColor.labelWidth, 1)
                end
                if themeColor.subFS and themeColor.subKey then
                    themeColor.subFS:SetText(L[themeColor.subKey])
                    ns.UIKit:FitFontString(themeColor.subFS, themeColor.labelWidth, 1)
                end
                local v = SettingsDialog.resolveOpt(themeColor.optKey)
                if themeColor.isSlider then
                    themeColor.updating = true
                    themeColor:SetValue(v)
                    themeColor.valueText:SetText(themeColor.fmt:format(v))
                    themeColor.updating = false
                else
                    themeColor:SetChecked(v)
                end
            end
        end
    end
    allSettingRefreshers[#allSettingRefreshers + 1] = refresh
    return refresh, y
end

local settingsPopoverFrame, popupRefresh, popupDefaultBtn
dismissSettingsPopup = function()
    if settingsPopoverFrame then settingsPopoverFrame:Hide() end
end

switchSettingsPopup = function()
    if not settingsPopoverFrame then
        settingsPopoverFrame = CreateFrame("Frame", "EzWoWFlightMapSettings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        settingsPopoverFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        settingsPopoverFrame:SetToplevel(true)
        settingsPopoverFrame:SetClampedToScreen(true)
        settingsPopoverFrame:SetMovable(true)
        settingsPopoverFrame:EnableMouse(true)
        if settingsPopoverFrame.SetBackdrop then
            settingsPopoverFrame:SetBackdrop(BACKDROP)
            settingsPopoverFrame:SetBackdropColor(STYLE.bgPrimary[1], STYLE.bgPrimary[2], STYLE.bgPrimary[3], 0.97)
            settingsPopoverFrame:SetBackdropBorderColor(STYLE.border[1], STYLE.border[2], STYLE.border[3], 1)
        end
        if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWFlightMapSettings") end

        local top = CreateFrame("Frame", nil, settingsPopoverFrame, BackdropTemplateMixin and "BackdropTemplate" or nil)
        top:SetPoint("TOPLEFT", settingsPopoverFrame, "TOPLEFT", 1, -1)
        top:SetPoint("TOPRIGHT", settingsPopoverFrame, "TOPRIGHT", -1, -1)
        top:SetHeight(56)
        if top.SetBackdrop then
            top:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            top:SetBackdropColor(STYLE.bgSecondary[1], STYLE.bgSecondary[2], STYLE.bgSecondary[3], 0.96)
        end
        top:EnableMouse(true)
        top:RegisterForDrag("LeftButton")
        top:SetScript("OnDragStart", function() settingsPopoverFrame:StartMoving() end)
        top:SetScript("OnDragStop", function() settingsPopoverFrame:StopMovingOrSizing() end)

        local accentLine = top:CreateTexture(nil, "ARTWORK")
        accentLine:SetColorTexture(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3], 0.95)
        accentLine:SetPoint("BOTTOMLEFT", top, "BOTTOMLEFT", 0, 0)
        accentLine:SetPoint("BOTTOMRIGHT", top, "BOTTOMRIGHT", 0, 0)
        accentLine:SetHeight(2)

        local titleIcon = top:CreateTexture(nil, "ARTWORK")
        titleIcon:SetSize(28, 28)
        titleIcon:SetPoint("TOPLEFT", 14, -14)
        titleIcon:SetTexture(MEDIA .. "Icon")

        local headingRegion = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        headingRegion:SetPoint("TOPLEFT", 48, -11)
        headingRegion:SetText("EzWoW - Flight Map")
        headingRegion:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])

        local titleStr = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        titleStr:SetPoint("TOPLEFT", headingRegion, "BOTTOMLEFT", 0, -3)
        titleStr:SetWidth(330)
        titleStr:SetJustifyH("LEFT")
        titleStr:SetTextColor(STYLE.textMuted[1], STYLE.textMuted[2], STYLE.textMuted[3])
        titleStr:SetText(L.SETTINGS)
        settingsPopoverFrame.titleFS = titleStr

        local close = createFlightMapButton(top, 24, 24, false, function() settingsPopoverFrame:Hide() end)
        close:SetPoint("TOPRIGHT", top, "TOPRIGHT", -10, -10)
        close:SetFrameLevel(top:GetFrameLevel() + 3)
        close.label:SetText("X")

        local bottom
        popupRefresh, bottom = SettingsDialog.assembleSettings(settingsPopoverFrame, 20, -68, 380)

        local function resolveResetBtnLabel()
            if currentState.open then return L.BTN_DEFAULT end
            local hasKo = (L.SETTINGS == "설정")
            return panelText(resolveActiveLocaleKey(), "창·버튼 위치 초기화", "Reset Window Position", { "Fenster- und Knopfposition zurücksetzen", "Réinitialiser fenêtre et bouton", "Restablecer ventana y botón", "Сбросить позицию окна и кнопки", "重置窗口与按钮位置", "重設視窗與按鈕位置" })
        end

        popupDefaultBtn = createFlightMapButton(settingsPopoverFrame, 184, 28, false, function()
            if currentState.open then
                settingsPopoverFrame:Hide()
                if ns.GetMainFrame() then ns.GetMainFrame():Hide() end
                restoreDefaultFlightFrames()
            else
                if ns.DB then
                    ns.DB.point, ns.DB.barPoint, ns.DB.scale = nil, nil, 1.0
                    ns.DB.worldMapControlPoint = nil
                    ns.DB.worldMapAutoAlign = true
                end
                if ns.ResetFlightTimerBarPosition then ns.ResetFlightTimerBarPosition() end
                if ns.GetMainFrame() then commitPosition() end
                if _G.EzWoWWorldMapDock and _G.EzWoWWorldMapDock.Layout then
                    _G.EzWoWWorldMapDock:Layout()
                end
                if ns.RefreshWorldMap then ns.RefreshWorldMap() end
                if popupRefresh then popupRefresh() end
                printAddonChatMessage(L.MSG_RESET)
            end
        end)
        popupDefaultBtn:SetPoint("TOPLEFT", settingsPopoverFrame, "TOPLEFT", 20, bottom - 10)
        popupDefaultBtn:SetText(resolveResetBtnLabel())

        local donate = createFlightMapButton(settingsPopoverFrame, 184, 28, true, SettingsDialog.openDonateDialog)
        donate:SetPoint("TOPRIGHT", settingsPopoverFrame, "TOPRIGHT", -20, bottom - 10)
        donate:SetText(L.BTN_DONATE)
        settingsPopoverFrame.donateBtn = donate

        local footerRegion = settingsPopoverFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        footerRegion:SetPoint("BOTTOMRIGHT", settingsPopoverFrame, "BOTTOMRIGHT", -20, 10)
        footerRegion:SetText("EzWoW - Flight Map · /ezfl")
        footerRegion:SetTextColor(STYLE.textMuted[1], STYLE.textMuted[2], STYLE.textMuted[3])

        allSettingRefreshers[#allSettingRefreshers + 1] = function()
            if settingsPopoverFrame.titleFS then settingsPopoverFrame.titleFS:SetText(L.SETTINGS) end
            if popupDefaultBtn then popupDefaultBtn:SetText(resolveResetBtnLabel()) end
            if settingsPopoverFrame.donateBtn then settingsPopoverFrame.donateBtn:SetText(L.BTN_DONATE) end
        end

        settingsPopoverFrame:SetSize(420, -bottom + 66)
        settingsPopoverFrame:Hide()
    end
    if settingsPopoverFrame:IsShown() then
        settingsPopoverFrame:Hide()
    else
        settingsPopoverFrame:ClearAllPoints()
        if ns.GetMainFrame() and (ns.GetMainFrame() and ns.GetMainFrame():IsShown()) then
            settingsPopoverFrame:SetPoint("TOPLEFT", ns.GetMainFrame(), "TOPRIGHT", 6, 0)
        else
            settingsPopoverFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        popupRefresh()
        if popupDefaultBtn then
            local hasKo = (L.SETTINGS == "설정")
            popupDefaultBtn:SetText(currentState.open and L.BTN_DEFAULT or panelText(resolveActiveLocaleKey(), "창·버튼 위치 초기화", "Reset Window Position", { "Fenster- und Knopfposition zurücksetzen", "Réinitialiser fenêtre et bouton", "Restablecer ventana y botón", "Сбросить позицию окна и кнопки", "重置窗口与按钮位置", "重設視窗與按鈕位置" }))
        end
        settingsPopoverFrame:Show()
        settingsPopoverFrame:Raise()
    end
end
ns.ToggleSettingsPopup = switchSettingsPopup

local blizzardOptionsCanvas
function SettingsDialog.registerOptionsPanel()
    local panelFrameEntry = CreateFrame("Frame", "EzWoWFlightMapOptionsPanel", UIParent)
    panelFrameEntry.name = "EzWoW - Flight Map"

    local iconTex = panelFrameEntry:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(32, 32)
    iconTex:SetPoint("TOPLEFT", 18, -18)
    iconTex:SetTexture(MEDIA .. "Icon")

    local titleStr = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleStr:SetPoint("LEFT", iconTex, "RIGHT", 10, 0)
    titleStr:SetTextColor(STYLE.accent[1], STYLE.accent[2], STYLE.accent[3])
    titleStr:SetText("EzWoW - Flight Map")

    local desc = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", iconTex, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")

    local launchBtn = createFlightMapButton(panelFrameEntry, 220, 28, true, function()
        switchSettingsPopup()
    end)
    launchBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)

    local hint = panelFrameEntry:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", launchBtn, "BOTTOMLEFT", 0, -14)
    hint:SetTextColor(STYLE.textMuted[1], STYLE.textMuted[2], STYLE.textMuted[3])

    local function syncPanel()
        local hasKo = (L.SETTINGS == "설정")
        desc:SetText(panelText(resolveActiveLocaleKey(), "비행 조련사의 비행 지점 이름·요금·소요 시간과 세계지도 비행 조련사 위치를 표시합니다.", "Displays flight point names, fares, flight times, and world map flight master locations.", { "Zeigt Namen, Kosten und Flugzeiten der Flugpunkte sowie die Flugmeister auf der Weltkarte.", "Affiche le nom, le prix et la durée des vols, ainsi que les maîtres de vol sur la carte du monde.", "Muestra nombres, tarifas y duración de los vuelos, y los maestros de vuelo en el mapa del mundo.", "Показывает названия точек полёта, стоимость, время в пути и распорядителей полётов на карте мира.", "显示飞行点名称、费用、飞行时间以及世界地图上的飞行管理员位置。", "顯示飛行點名稱、費用、飛行時間以及世界地圖上的飛行管理員位置。" }))
        launchBtn:SetText((L.SETTINGS or "설정") .. " (/ezfl)")
        hint:SetText(panelText(resolveActiveLocaleKey(), "채팅창에 /ezfl 또는 /ezfl config를 입력해도 열립니다.", "Type /ezfl or /ezfl config in chat to open settings.", { "Du kannst die Einstellungen auch mit /ezfl oder /ezfl config im Chat öffnen.", "Vous pouvez aussi ouvrir les options en tapant /ezfl ou /ezfl config dans le chat.", "También puedes abrir las opciones escribiendo /ezfl o /ezfl config en el chat.", "Настройки также открываются командой /ezfl или /ezfl config в чате.", "也可以在聊天框输入 /ezfl 或 /ezfl config 打开设置。", "也可以在聊天框輸入 /ezfl 或 /ezfl config 開啟設定。" }))
    end
    allSettingRefreshers[#allSettingRefreshers + 1] = syncPanel
    panelFrameEntry:SetScript("OnShow", syncPanel)
    syncPanel()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panelFrameEntry, panelFrameEntry.name)
        Settings.RegisterAddOnCategory(category)
        panelFrameEntry.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panelFrameEntry)
    end
    return panelFrameEntry
end

function SettingsDialog.launchOptionsPanel()
    switchSettingsPopup()
end

ns.CloseSettingsPopup = dismissSettingsPopup

ns.RegisterOptionsPanel = SettingsDialog.registerOptionsPanel
ns.ShowDonate = SettingsDialog.openDonateDialog

function SettingsDialog.formatBooleanStateLabel(v) return v and L.ON or L.OFF end

function SettingsDialog.toggleBooleanOption(key, msg)
    SettingsDialog.assignOpt(key, not ns.DB[key])
    printAddonChatMessage(msg:format(SettingsDialog.formatBooleanStateLabel(ns.DB[key])))
end

local LANG_ALIASES = {
    auto = "auto",
    ko = "koKR", kokr = "koKR", kr = "koKR",
    en = "enUS", enus = "enUS", engb = "enUS",
    de = "deDE", dede = "deDE",
    fr = "frFR", frfr = "frFR",
    es = "esES", eses = "esES", esmx = "esMX",
    ru = "ruRU", ruru = "ruRU",
    zhcn = "zhCN", cn = "zhCN", zh = "zhCN",
    zhtw = "zhTW", tw = "zhTW",
}

SLASH_EZWOWFLIGHTMAP1 = "/ezfl"
SLASH_EZWOWFLIGHTMAP2 = "/efm"
SLASH_EZWOWFLIGHTMAP3 = "/ezwowflightmap"
SLASH_EZWOWFLIGHTMAP4 = "/비행지도"
SlashCmdList.EZWOWFLIGHTMAP = function(msg)
    msg = ((msg or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local numericVal = tonumber(rest)
    if cmd == "on" or cmd == "off" then
        assignEnabled(cmd == "on")
        printAddonChatMessage(L.MSG_ENABLED:format(SettingsDialog.formatBooleanStateLabel(ns.DB.enabled)))
    elseif cmd == "lang" or cmd == "language" or cmd == "언어" then
        local targetKey = LANG_ALIASES[(rest or ""):lower()]
        if targetKey then
            ns.DB.lang = targetKey
            SettingsDialog.syncAllLocaleUI()
            printAddonChatMessage(L.MSG_LANG:format(targetKey == "auto" and (L.LANG_AUTO .. " (" .. resolveActiveLocaleKey() .. ")") or targetKey))
        else
            printAddonChatMessage("Usage: /ezfl lang [auto|ko|en|de|fr|es|ru|zhcn|zhtw]")
        end
    elseif cmd == "" or cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "설정" then
        SettingsDialog.launchOptionsPanel()
    elseif cmd == "skip" then
        SettingsDialog.toggleBooleanOption("skipGossip", L.MSG_SKIP)
    elseif cmd == "labels" then
        SettingsDialog.toggleBooleanOption("labels", L.MSG_LABELS)
    elseif cmd == "crop" then
        SettingsDialog.toggleBooleanOption("crop", L.MSG_CROP)
    elseif cmd == "all" then
        SettingsDialog.toggleBooleanOption("showUnreachable", L.MSG_ALL)
    elseif cmd == "bar" then
        SettingsDialog.toggleBooleanOption("flightBar", L.MSG_BAR)
    elseif cmd == "alert" then
        SettingsDialog.toggleBooleanOption("arrivalAlert", L.MSG_ALERT)
    elseif cmd == "list" then
        SettingsDialog.toggleBooleanOption("showList", L.MSG_LIST)
    elseif cmd == "scale" then
        if numericVal then
            if numericVal <= 2 then numericVal = numericVal * 100 end   
            SettingsDialog.assignOpt("scale", max(50, min(120, numericVal)))
        end
        printAddonChatMessage(L.MSG_SCALE:format(SettingsDialog.resolveOpt("scale")))
    elseif cmd == "alpha" then
        if numericVal then SettingsDialog.assignOpt("alpha", max(0, min(70, numericVal))) end
        printAddonChatMessage(L.MSG_ALPHA:format(SettingsDialog.resolveOpt("alpha")))
    elseif cmd == "reset" then
        ns.DB.point, ns.DB.barPoint, ns.DB.scale = nil, nil, 1.0
        if ns.ResetFlightTimerBarPosition then ns.ResetFlightTimerBarPosition() end
        if ns.GetMainFrame() then commitPosition() end
        printAddonChatMessage(L.MSG_RESET)
        refreshActiveView()
    elseif cmd == "donate" then
        SettingsDialog.openDonateDialog()
    else
        printAddonChatMessage(L.MSG_ENABLED:format(SettingsDialog.formatBooleanStateLabel(ns.DB.enabled)))
        for _, line in ipairs(L.HELP) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
        end
    end
end

