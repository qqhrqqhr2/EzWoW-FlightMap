--===========================================================================
-- EzWoW shared : UI/LanguageDropdown.lua
-- Language combo box: click the box, then click a language in the list.
-- (Same file in every EzWoW addon.)
--===========================================================================
local _, ns = ...

local LanguageDropdown = {}
ns.LanguageDropdown = LanguageDropdown

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local ROW_HEIGHT = 20
local BACKDROP = {
    bgFile = WHITE8X8, edgeFile = WHITE8X8, tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local DEFAULT_COLORS = {
    bg     = { 0.071, 0.094, 0.122, 0.98 },
    border = { 0.204, 0.298, 0.357, 1.00 },
    accent = { 0.945, 0.741, 0.341, 1.00 },
    text   = { 0.929, 0.957, 0.969, 1.00 },
}

local openList   -- only one language list is open at a time

local function rgba(c)
    return c[1], c[2], c[3], c[4] or 1
end

local function itemText(item)
    if type(item.text) == "function" then return item.text() or "" end
    return item.text or tostring(item.value)
end

local function fillList(list)
    local opts = list.opts
    local current = opts.get()
    local accent, text = list.colors.accent, list.colors.text
    for index, row in ipairs(list.rows) do
        local item = opts.items[index]
        local selected = item.value == current
        row.text:SetText((selected and "> " or "") .. itemText(item))
        if selected then row.text:SetTextColor(rgba(accent)) else row.text:SetTextColor(rgba(text)) end
    end
end

local function buildList(button, opts)
    local colors = {}
    for key, value in pairs(DEFAULT_COLORS) do colors[key] = (opts.colors and opts.colors[key]) or value end

    local list = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate" or nil)
    list.opts, list.colors = opts, colors
    list:SetFrameStrata(button:GetFrameStrata() or "DIALOG")
    list:SetFrameLevel(button:GetFrameLevel() + 50)
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    list:SetWidth(opts.width or button:GetWidth())
    list:SetHeight(#opts.items * ROW_HEIGHT + 6)
    if list.SetBackdrop then
        list:SetBackdrop(BACKDROP)
        list:SetBackdropColor(rgba(colors.bg))
        list:SetBackdropBorderColor(rgba(colors.accent))
    end

    list.rows = {}
    for index, item in ipairs(opts.items) do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -3 - (index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -3, -3 - (index - 1) * ROW_HEIGHT)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(colors.accent[1], colors.accent[2], colors.accent[3], 0.18)
        row.highlight:Hide()
        row.text = row:CreateFontString(nil, "OVERLAY", opts.fontObject or "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        if row.text.SetWordWrap then row.text:SetWordWrap(false) end
        row.value = item.value
        row:SetScript("OnEnter", function(self) self.highlight:Show() end)
        row:SetScript("OnLeave", function(self) self.highlight:Hide() end)
        row:SetScript("OnClick", function(self)
            list:Hide()
            if self.value ~= opts.get() or opts.applySame then opts.set(self.value) end
        end)
        list.rows[index] = row
    end
    list:SetScript("OnHide", function(self) if openList == self then openList = nil end end)
    list:Hide()
    return list
end

-- Opens below the box, or above it when the list would run past the window's bottom edge.
local function placeList(button, list)
    list:ClearAllPoints()
    local window = list.opts.window or button:GetParent()
    local boxBottom = button:GetBottom()
    local windowBottom = window and window.GetBottom and window:GetBottom()
    local direction = list.opts.direction
    if direction == "up" or (direction ~= "down" and boxBottom and windowBottom
            and boxBottom - list:GetHeight() - 2 < windowBottom) then
        list:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
    else
        list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    end
end

-- Turns `button` into a language combo box.
-- opts.items  = { { value = code, text = "label" or function }, ... } (a value may be nil)
-- opts.get()  = the current value; opts.set(value) = apply it and refresh the window
-- opts.colors = { bg, border, accent, text } (optional), opts.width = list width (optional)
-- opts.direction = "up" / "down" (optional; default: down unless it would leave the window)
function LanguageDropdown.Attach(button, opts)
    local list = buildList(button, opts)
    button.languageList = list
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp") end
    button:SetScript("OnClick", function()
        if list:IsShown() then
            list:Hide()
            return
        end
        if openList and openList ~= list then openList:Hide() end
        fillList(list)
        placeList(button, list)
        list:Show()
        openList = list
    end)
    -- closing the window (or hiding the box) closes the list
    local parent = button:GetParent()
    if parent and parent.HookScript then
        parent:HookScript("OnHide", function() list:Hide() end)
    end
    if button.HookScript then
        button:HookScript("OnHide", function() list:Hide() end)
    end
    return list
end

-- Redraws the open list after the window's language changed.
function LanguageDropdown.Refresh(button)
    local list = button and button.languageList
    if list and list:IsShown() then fillList(list) end
end

function LanguageDropdown.Close(button)
    local list = button and button.languageList
    if list then list:Hide() end
end
