--===========================================================================
-- EzWoW shared : Libs/EzWoWMiniGames/Games/Memory.lua : Memory (find the matching pairs)
--===========================================================================
local ADDON_NAME = ...
local MG = _G.EzWoW_MiniGames
-- only the copy belonging to the running window registers
if not MG or MG.owner ~= ADDON_NAME then return end
local T = MG.T

local Game = { key = "memory", levels = { "easy", "normal" } }
local CONFIG = { easy = { cols = 4, rows = 4 }, normal = { cols = 6, rows = 5 } }
local MAX_CARDS = 30

-- Pictures that every client has: raid markers and class icons.
local PICTURES = {}
for i = 1, 8 do PICTURES[#PICTURES + 1] = { file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i } end
for _, class in ipairs({ "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }) do
    PICTURES[#PICTURES + 1] = { file = "Interface\\Icons\\ClassIcon_" .. class, crop = true }
end

local cards = {}
local cfg, deck, matched, first, second, locked, tries, pairsLeft

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

local function paint(i)
    local b = cards[i]
    local face = matched[i] or first == i or second == i
    if face then
        local pic = PICTURES[deck[i]]
        b.icon:SetTexture(pic.file)
        if pic.crop then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.icon:SetTexCoord(0, 1, 0, 1) end
        b.icon:Show()
        b.back:Hide()
        b:SetBackdropColor(0.07, 0.09, 0.12, 1)
        b:SetBackdropBorderColor(matched[i] and 0.3 or 0.52, matched[i] and 0.85 or 0.73, matched[i] and 0.4 or 1, 1)
    else
        b.icon:Hide()
        b.back:Show()
        b:SetBackdropColor(0.16, 0.22, 0.28, 1)
        b:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
    end
end

local function onClick(self)
    if MG.IsFinished() or locked then return end
    local i = self.index
    if matched[i] or i == first then return end
    MG.StartClock()
    if not first then
        first = i
        paint(i)
        return
    end
    second = i
    tries = tries + 1
    paint(i)
    if deck[first] == deck[second] then
        matched[first], matched[second] = true, true
        local a, b = first, second
        first, second = nil, nil
        paint(a)
        paint(b)
        pairsLeft = pairsLeft - 1
        if pairsLeft == 0 then MG.Win() end
    else
        locked = true
        local a, b = first, second
        C_Timer.After(0.8, function()
            if first == a and second == b then
                first, second, locked = nil, nil, false
                paint(a)
                paint(b)
            end
        end)
    end
end

function Game.Build(area)
    for i = 1, MAX_CARDS do
        local b = CreateFrame("Button", nil, area, "BackdropTemplate")
        b:SetBackdrop(MG.BACKDROP)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 6, -6)
        b.icon:SetPoint("BOTTOMRIGHT", -6, 6)
        b.back = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        b.back:SetPoint("CENTER")
        b.back:SetText("?")
        b.back:SetTextColor(0.52, 0.73, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.index = i
        b:SetScript("OnClick", onClick)
        cards[i] = b
    end
end

function Game.Start(level)
    cfg = CONFIG[level] or CONFIG.easy
    local count = cfg.cols * cfg.rows
    local kinds = {}
    for i = 1, #PICTURES do kinds[i] = i end
    shuffle(kinds)
    deck = {}
    for p = 1, count / 2 do
        deck[#deck + 1] = kinds[p]
        deck[#deck + 1] = kinds[p]
    end
    shuffle(deck)
    matched, first, second, locked, tries, pairsLeft = {}, nil, nil, false, 0, count / 2
    local area = Game.area
    local gap = 6
    local size = math.floor(math.min((area:GetWidth() - gap * (cfg.cols - 1)) / cfg.cols,
        (area:GetHeight() - gap * (cfg.rows - 1)) / cfg.rows))
    size = math.min(size, 84)
    local totalW = size * cfg.cols + gap * (cfg.cols - 1)
    local totalH = size * cfg.rows + gap * (cfg.rows - 1)
    local offX, offY = (area:GetWidth() - totalW) / 2, (area:GetHeight() - totalH) / 2
    for i = 1, MAX_CARDS do
        local b = cards[i]
        if i <= count then
            local c, r = (i - 1) % cfg.cols, math.floor((i - 1) / cfg.cols)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", area, "TOPLEFT", offX + c * (size + gap), -(offY + r * (size + gap)))
            b:SetSize(size, size)
            paint(i)
            b:Show()
        else
            b:Hide()
        end
    end
end

function Game.Status()
    return string.format(T("st_tries"), tries or 0, MG.Clock(MG.Elapsed()))
end

-- saved board (for /reload or logout in the middle of a game)
function Game.Save()
    local t = { deck = {}, matched = {}, tries = tries }
    for i, v in ipairs(deck) do t.deck[i] = v end
    for i in pairs(matched) do t.matched[#t.matched + 1] = i end
    return t
end

function Game.Load(t, level)
    Game.Start(level)
    if type(t.deck) ~= "table" or #t.deck ~= #deck then return end
    for i, v in ipairs(t.deck) do deck[i] = v end
    for _, i in ipairs(t.matched or {}) do matched[i] = true end
    tries = tonumber(t.tries) or 0
    pairsLeft = #deck / 2 - #(t.matched or {}) / 2
    for i = 1, #deck do paint(i) end
end

MG.Register(Game)
