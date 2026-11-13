--===========================================================================
-- EzWoW shared : Libs/EzWoWMiniGames/Games/Minesweeper.lua : Minesweeper (first click is always safe)
--===========================================================================
local ADDON_NAME = ...
local MG = _G.EzWoW_MiniGames
-- only the copy belonging to the running window registers
if not MG or MG.owner ~= ADDON_NAME then return end
local T = MG.T

local Game = { key = "mines", levels = { "easy", "normal" } }
local CONFIG = { easy = { cols = 9, rows = 9, mines = 10 }, normal = { cols = 12, rows = 12, mines = 24 } }
local MAX_CELLS = 12 * 12
local NUMBER_COLORS = {
    { 0.45, 0.70, 1.00 }, { 0.40, 0.85, 0.45 }, { 1.00, 0.45, 0.40 }, { 0.70, 0.50, 1.00 },
    { 1.00, 0.70, 0.30 }, { 0.40, 0.85, 0.85 }, { 0.90, 0.90, 0.90 }, { 0.60, 0.60, 0.60 },
}
local MINE_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local FLAG_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"

local cells = {}
local cfg, mines, revealed, flagged, counts
local revealedCount, flagCount, placed

local function neighbors(i)
    local out = {}
    local c = (i - 1) % cfg.cols
    local r = math.floor((i - 1) / cfg.cols)
    for dr = -1, 1 do
        for dc = -1, 1 do
            if not (dr == 0 and dc == 0) then
                local nr, nc = r + dr, c + dc
                if nr >= 0 and nr < cfg.rows and nc >= 0 and nc < cfg.cols then
                    out[#out + 1] = nr * cfg.cols + nc + 1
                end
            end
        end
    end
    return out
end

local function paint(i)
    local b = cells[i]
    b.icon:Hide()
    b.text:SetText("")
    if revealed[i] then
        if mines[i] then
            b:SetBackdropColor(b.boom and 0.55 or 0.25, 0.10, 0.10, 1)
            b.icon:SetTexture(MINE_ICON)
            b.icon:Show()
        else
            b:SetBackdropColor(0.07, 0.09, 0.12, 1)
            local n = counts[i]
            if n > 0 then
                local c = NUMBER_COLORS[n]
                b.text:SetText(n)
                b.text:SetTextColor(c[1], c[2], c[3])
            end
        end
    else
        b:SetBackdropColor(0.16, 0.22, 0.28, 1)
        if flagged[i] then
            b.icon:SetTexture(FLAG_ICON)
            b.icon:Show()
        end
    end
end

local function placeMines(safe)
    local forbidden = { [safe] = true }
    for _, n in ipairs(neighbors(safe)) do forbidden[n] = true end
    local total = cfg.cols * cfg.rows
    local left = cfg.mines
    while left > 0 do
        local i = math.random(1, total)
        if not mines[i] and not forbidden[i] then
            mines[i] = true
            left = left - 1
        end
    end
    for i = 1, total do
        local n = 0
        for _, j in ipairs(neighbors(i)) do if mines[j] then n = n + 1 end end
        counts[i] = n
    end
    placed = true
end

local function lose(i)
    cells[i].boom = true
    for j = 1, cfg.cols * cfg.rows do
        if mines[j] then revealed[j] = true paint(j) end
    end
    MG.Lose()
end

local function reveal(start)
    local stack = { start }
    while #stack > 0 do
        local i = table.remove(stack)
        if not revealed[i] and not flagged[i] then
            revealed[i] = true
            revealedCount = revealedCount + 1
            paint(i)
            if mines[i] then
                lose(i)
                return
            end
            if counts[i] == 0 then
                for _, j in ipairs(neighbors(i)) do
                    if not revealed[j] then stack[#stack + 1] = j end
                end
            end
        end
    end
    if revealedCount == cfg.cols * cfg.rows - cfg.mines then MG.Win() end
end

local function onClick(self, button)
    if MG.IsFinished() then return end
    local i = self.index
    if button == "RightButton" then
        if revealed[i] then return end
        flagged[i] = not flagged[i] or nil
        flagCount = flagCount + (flagged[i] and 1 or -1)
        paint(i)
        return
    end
    -- a flag is not a first click: no clock, no mine placement
    if flagged[i] and not revealed[i] then return end
    MG.StartClock()
    if not placed then placeMines(i) end
    if revealed[i] then
        -- open around a number when its flags are all set
        local n = 0
        for _, j in ipairs(neighbors(i)) do if flagged[j] then n = n + 1 end end
        if n == counts[i] and n > 0 then
            for _, j in ipairs(neighbors(i)) do
                if not revealed[j] and not flagged[j] then
                    reveal(j)
                    if MG.IsFinished() then return end
                end
            end
        end
        return
    end
    if flagged[i] then return end
    reveal(i)
end

function Game.Build(area)
    for i = 1, MAX_CELLS do
        local b = CreateFrame("Button", nil, area, "BackdropTemplate")
        b:SetBackdrop(MG.BACKDROP)
        b:SetBackdropBorderColor(0.05, 0.07, 0.09, 1)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        b.text:SetPoint("CENTER", 0, 0)
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetPoint("CENTER")
        b.index = i
        b:SetScript("OnClick", onClick)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        cells[i] = b
    end
end

function Game.Start(level)
    cfg = CONFIG[level] or CONFIG.easy
    mines, revealed, flagged, counts = {}, {}, {}, {}
    revealedCount, flagCount, placed = 0, 0, false
    local area = Game.area
    local size = math.floor(math.min(area:GetWidth() / cfg.cols, area:GetHeight() / cfg.rows))
    size = math.min(size, 40)
    local offX = (area:GetWidth() - size * cfg.cols) / 2
    local offY = (area:GetHeight() - size * cfg.rows) / 2
    for i = 1, MAX_CELLS do
        local b = cells[i]
        if i <= cfg.cols * cfg.rows then
            local c = (i - 1) % cfg.cols
            local r = math.floor((i - 1) / cfg.cols)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", area, "TOPLEFT", offX + c * size, -(offY + r * size))
            b:SetSize(size, size)
            b.icon:SetSize(size * 0.7, size * 0.7)
            b.boom = nil
            counts[i] = 0
            paint(i)
            b:Show()
        else
            b:Hide()
        end
    end
end

function Game.Status()
    return string.format(T("st_mines"), (cfg and cfg.mines or 0) - (flagCount or 0), MG.Clock(MG.Elapsed()))
end

-- saved board (for /reload or logout in the middle of a game)
function Game.Save()
    local t = { mines = {}, revealed = {}, flagged = {}, placed = placed }
    for i = 1, cfg.cols * cfg.rows do
        if mines[i] then t.mines[#t.mines + 1] = i end
        if revealed[i] then t.revealed[#t.revealed + 1] = i end
        if flagged[i] then t.flagged[#t.flagged + 1] = i end
    end
    return t
end

function Game.Load(t, level)
    Game.Start(level)
    for _, i in ipairs(t.mines or {}) do mines[i] = true end
    for _, i in ipairs(t.flagged or {}) do flagged[i] = true flagCount = flagCount + 1 end
    for _, i in ipairs(t.revealed or {}) do
        revealed[i] = true
        if not mines[i] then revealedCount = revealedCount + 1 end
    end
    placed = t.placed and true or false
    local total = cfg.cols * cfg.rows
    for i = 1, total do
        local n = 0
        if placed then
            for _, j in ipairs(neighbors(i)) do if mines[j] then n = n + 1 end end
        end
        counts[i] = n
        paint(i)
    end
end

MG.Register(Game)
