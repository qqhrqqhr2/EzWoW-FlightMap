--===========================================================================
-- EzWoW shared : Libs/EzWoWMiniGames/Games/Puzzle.lua : Sliding puzzle (3x3 / 4x4, always solvable)
--===========================================================================
local ADDON_NAME = ...
local MG = _G.EzWoW_MiniGames
-- only the copy belonging to the running window registers
if not MG or MG.owner ~= ADDON_NAME then return end
local T = MG.T

local Game = { key = "puzzle", levels = { "easy", "normal" } }
local SIZES = { easy = 3, normal = 4 }
local MAX_TILES = 15

local tiles = {}
local n, board, blank, moves

-- board[pos] = tile number (0 = gap), pos = 1..n*n
local function rowCol(pos) return math.floor((pos - 1) / n), (pos - 1) % n end

local function layout()
    local area = Game.area
    local gap = 4
    local size = math.floor((math.min(area:GetWidth(), area:GetHeight()) - gap * (n - 1)) / n)
    size = math.min(size, 96)
    local total = size * n + gap * (n - 1)
    local offX, offY = (area:GetWidth() - total) / 2, (area:GetHeight() - total) / 2
    for pos = 1, n * n do
        local value = board[pos]
        if value > 0 then
            local b = tiles[value]
            local r, c = rowCol(pos)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", area, "TOPLEFT", offX + c * (size + gap), -(offY + r * (size + gap)))
            b:SetSize(size, size)
            b.pos = pos
            local home = value == pos
            if home then
                b:SetBackdropColor(0.10, 0.20, 0.30, 1)
                b:SetBackdropBorderColor(0.52, 0.73, 1, 1)
            else
                b:SetBackdropColor(0.16, 0.22, 0.28, 1)
                b:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
            end
        end
    end
end

local function solved()
    for pos = 1, n * n - 1 do
        if board[pos] ~= pos then return false end
    end
    return true
end

-- Slides every tile between the clicked one and the gap (same row or column).
local function slide(pos, count)
    local r, c = rowCol(pos)
    local br, bc = rowCol(blank)
    if r ~= br and c ~= bc then return false end
    local step
    if r == br then step = (c < bc) and -1 or 1 else step = (r < br) and -n or n end
    while blank ~= pos do
        local from = blank + step
        board[blank], board[from] = board[from], 0
        blank = from
        if count then moves = moves + 1 end
    end
    return true
end

local function onClick(self)
    if MG.IsFinished() or not self.pos then return end
    if slide(self.pos, true) then
        MG.StartClock()
        layout()
        if solved() then MG.Win() end
    end
end

function Game.Build(area)
    for i = 1, MAX_TILES do
        local b = CreateFrame("Button", nil, area, "BackdropTemplate")
        b:SetBackdrop(MG.BACKDROP)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        b.text:SetPoint("CENTER")
        b.text:SetText(i)
        b.text:SetTextColor(0.93, 0.96, 0.97)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b:SetScript("OnClick", onClick)
        tiles[i] = b
    end
end

function Game.Start(level)
    n = SIZES[level] or 3
    board = {}
    for pos = 1, n * n - 1 do board[pos] = pos end
    board[n * n] = 0
    blank = n * n
    -- shuffle with random legal moves, so the puzzle can always be solved
    local last
    for _ = 1, n * n * 40 do
        local br, bc = rowCol(blank)
        local options = {}
        if br > 0 then options[#options + 1] = blank - n end
        if br < n - 1 then options[#options + 1] = blank + n end
        if bc > 0 then options[#options + 1] = blank - 1 end
        if bc < n - 1 then options[#options + 1] = blank + 1 end
        local pick
        repeat pick = options[math.random(1, #options)] until pick ~= last or #options == 1
        last = blank
        slide(pick, false)
    end
    if solved() then
        local _, bc = rowCol(blank)
        slide(bc > 0 and blank - 1 or blank + 1, false)
    end
    moves = 0
    for i = 1, MAX_TILES do tiles[i]:SetShown(i < n * n) end
    layout()
end

function Game.Status()
    return string.format(T("st_moves"), moves or 0, MG.Clock(MG.Elapsed()))
end

-- saved board (for /reload or logout in the middle of a game)
function Game.Save()
    local t = { board = {}, moves = moves }
    for i, v in ipairs(board) do t.board[i] = v end
    return t
end

function Game.Load(t, level)
    Game.Start(level)
    if type(t.board) ~= "table" or #t.board ~= n * n then return end
    for i, v in ipairs(t.board) do
        board[i] = v
        if v == 0 then blank = i end
    end
    moves = tonumber(t.moves) or 0
    layout()
end

MG.Register(Game)
