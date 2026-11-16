--===========================================================================
-- EzWoW shared : Libs/EzWoWMiniGames/Games/Sudoku.lua : Sudoku (9x9, one solution, three levels)
--===========================================================================
local ADDON_NAME = ...
local MG = _G.EzWoW_MiniGames
-- only the copy belonging to the running window registers
if not MG or MG.owner ~= ADDON_NAME then return end
local T = MG.T
local floor, random, ipairs, tonumber, tostring = math.floor, math.random, ipairs, tonumber, tostring

local Game = { key = "sudoku", levels = { "easy", "normal", "hard" } }

-- Every board can be finished one sure step at a time (a cell with only one
-- possible number, or a number with only one possible cell in its row, column
-- or box): no guessing and no notes needed, and so only one solution.
-- givens: numbers left on the board (cells are emptied in pairs facing each
-- other through the centre). lone: hard also empties single cells after that.
local LEVELS = {
    easy   = { givens = 40 },
    normal = { givens = 32 },
    hard   = { givens = 24, lone = true },
}
-- search steps allowed for one try at filling a whole grid
local FILL_STEPS = 300

-----------------------------------------------------------------------------
-- Board geometry: cells 1..81 row by row; units 1-9 rows, 10-18 columns,
-- 19-27 boxes
-----------------------------------------------------------------------------
local ROW, COL, BOX = {}, {}, {}
local UNITS, UNIT_OF, PEERS = {}, {}, {}
for u = 1, 27 do UNITS[u] = {} end
for i = 1, 81 do
    local r, c = floor((i - 1) / 9), (i - 1) % 9
    local b = floor(r / 3) * 3 + floor(c / 3)
    ROW[i], COL[i], BOX[i] = r, c, b
    UNIT_OF[i] = { r + 1, c + 10, b + 19 }
    for x = 1, 3 do
        local list = UNITS[UNIT_OF[i][x]]
        list[#list + 1] = i
    end
end
for i = 1, 81 do
    local seen, list = { [i] = true }, {}
    for x = 1, 3 do
        for _, j in ipairs(UNITS[UNIT_OF[i][x]]) do
            if not seen[j] then
                seen[j] = true
                list[#list + 1] = j
            end
        end
    end
    PEERS[i] = list
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

-----------------------------------------------------------------------------
-- Solver: candidates per cell with sure steps applied right away, and a
-- search that tries the cell with the fewest candidates. Changes go on a
-- trail so a search branch can be undone without copying the board.
-----------------------------------------------------------------------------
local cand = {}      -- cand[(cell - 1) * 9 + n]: n is still possible in cell
local cnt = {}       -- number of candidates per cell
local val = {}       -- placed number per cell (0 = empty)
local ucnt = {}      -- ucnt[(unit - 1) * 9 + n]: cells of the unit where n is possible
local trail, trailN = {}, 0
local queueCell, queueNum, qHead, qTail = {}, {}, 1, 0
local steps = 0

local function reset()
    for k = 1, 729 do cand[k] = true end
    for i = 1, 81 do
        cnt[i] = 9
        val[i] = 0
    end
    for k = 1, 243 do ucnt[k] = 9 end
    trailN, qHead, qTail = 0, 1, 0
end

local function push(i, n)
    qTail = qTail + 1
    queueCell[qTail], queueNum[qTail] = i, n
end

-- the one cell of unit u where n is still possible becomes a sure step
local function onlyPlace(u, n)
    local cells = UNITS[u]
    for y = 1, 9 do
        local j = cells[y]
        if cand[(j - 1) * 9 + n] then
            if val[j] == 0 then push(j, n) end
            return
        end
    end
end

-- removes n from cell i; false when that leaves no way to finish
local function eliminate(i, n)
    local k = (i - 1) * 9 + n
    if not cand[k] then return true end
    cand[k] = false
    trailN = trailN + 1
    trail[trailN] = k
    local left = cnt[i] - 1
    cnt[i] = left
    local us = UNIT_OF[i]
    local k1, k2, k3 = (us[1] - 1) * 9 + n, (us[2] - 1) * 9 + n, (us[3] - 1) * 9 + n
    local m1, m2, m3 = ucnt[k1] - 1, ucnt[k2] - 1, ucnt[k3] - 1
    ucnt[k1], ucnt[k2], ucnt[k3] = m1, m2, m3
    if left == 0 or m1 == 0 or m2 == 0 or m3 == 0 then return false end
    if left == 1 and val[i] == 0 then
        local base = (i - 1) * 9
        for e = 1, 9 do
            if cand[base + e] then
                push(i, e)
                break
            end
        end
    end
    if m1 == 1 then onlyPlace(us[1], n) end
    if m2 == 1 then onlyPlace(us[2], n) end
    if m3 == 1 then onlyPlace(us[3], n) end
    return true
end

local function assign(i, n)
    local current = val[i]
    if current ~= 0 then return current == n end
    if not cand[(i - 1) * 9 + n] then return false end
    val[i] = n
    trailN = trailN + 1
    trail[trailN] = -i
    for e = 1, 9 do
        if e ~= n and not eliminate(i, e) then return false end
    end
    local peers = PEERS[i]
    for x = 1, #peers do
        if not eliminate(peers[x], n) then return false end
    end
    return true
end

local function propagate()
    while qHead <= qTail do
        local i, n = queueCell[qHead], queueNum[qHead]
        qHead = qHead + 1
        if not assign(i, n) then
            qHead, qTail = 1, 0
            return false
        end
    end
    qHead, qTail = 1, 0
    return true
end

local function undo(mark)
    while trailN > mark do
        local k = trail[trailN]
        trailN = trailN - 1
        if k > 0 then
            cand[k] = true
            local i = floor((k - 1) / 9) + 1
            local n = k - (i - 1) * 9
            cnt[i] = cnt[i] + 1
            local us = UNIT_OF[i]
            for x = 1, 3 do
                local uk = (us[x] - 1) * 9 + n
                ucnt[uk] = ucnt[uk] + 1
            end
        else
            val[-k] = 0
        end
    end
end

-- places the numbers of grid and every sure step that follows
local function setup(grid)
    reset()
    for i = 1, 81 do
        local n = grid[i]
        if n ~= 0 and not assign(i, n) then
            qHead, qTail = 1, 0
            return false
        end
    end
    return propagate()
end

-- fills the empty cells, trying the cell with the fewest candidates first
-- and its numbers in random order; true when the grid got filled
local function search()
    local best, bestN = 0, 10
    for i = 1, 81 do
        if val[i] == 0 and cnt[i] < bestN then
            best, bestN = i, cnt[i]
            if bestN <= 2 then break end
        end
    end
    if best == 0 then return true end
    steps = steps + 1
    if steps > FILL_STEPS then return false end
    local base, numbers = (best - 1) * 9, {}
    for n = 1, 9 do
        if cand[base + n] then numbers[#numbers + 1] = n end
    end
    shuffle(numbers)
    for x = 1, #numbers do
        local mark = trailN
        if assign(best, numbers[x]) and propagate() and search() then return true end
        qHead, qTail = 1, 0
        undo(mark)
        if steps > FILL_STEPS then return false end
    end
    return false
end

-- true when sure steps alone finish the puzzle (which also means it has
-- exactly one solution)
local function solvedBySingles(grid)
    if not setup(grid) then return false end
    for i = 1, 81 do
        if val[i] == 0 then return false end
    end
    return true
end

-----------------------------------------------------------------------------
-- Making a board. It runs as a coroutine that stops after a few milliseconds
-- and goes on in the next frame, so a new game never stalls the client.
-----------------------------------------------------------------------------
local SLICE_MS = 6
local now = debugprofilestop or function() return 0 end
local job, jobLevel, sliceStart = nil, nil, 0

-- between two checks: hands the rest of the work to the next frame when this
-- frame's share is used up
local function pace()
    if job and coroutine.running() == job and now() - sliceStart > SLICE_MS then coroutine.yield() end
end

local function fullGrid()
    local blank = {}
    for i = 1, 81 do blank[i] = 0 end
    for _ = 1, 20 do
        steps = 0
        if setup(blank) and search() then
            local out = {}
            for i = 1, 81 do out[i] = val[i] end
            return out
        end
    end
    -- a fixed pattern with shuffled numbers (never needed in practice)
    local numbers = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
    shuffle(numbers)
    local out = {}
    for i = 1, 81 do out[i] = numbers[(ROW[i] * 3 + floor(ROW[i] / 3) + COL[i]) % 9 + 1] end
    return out
end

-- empties cells (first in pairs facing each other through the centre, then
-- on hard single cells), keeping only the removals that leave a board sure
-- steps can finish. Each cell is tried once, so the work is bounded.
local function makePuzzle(solution, cfg)
    local puzzle = {}
    for i = 1, 81 do puzzle[i] = solution[i] end
    local givens = 81
    local order = {}
    for i = 1, 41 do order[i] = i end
    shuffle(order)
    for _, i in ipairs(order) do
        if givens <= cfg.givens then break end
        local j = 82 - i
        puzzle[i], puzzle[j] = 0, 0
        if solvedBySingles(puzzle) then
            givens = givens - (i == j and 1 or 2)
        else
            puzzle[i], puzzle[j] = solution[i], solution[j]
        end
        pace()
    end
    if cfg.lone and givens > cfg.givens then
        order = {}
        for i = 1, 81 do
            if puzzle[i] ~= 0 then order[#order + 1] = i end
        end
        shuffle(order)
        for _, i in ipairs(order) do
            if givens <= cfg.givens then break end
            puzzle[i] = 0
            if solvedBySingles(puzzle) then
                givens = givens - 1
            else
                puzzle[i] = solution[i]
            end
            pace()
        end
    end
    return puzzle, givens
end

-- puzzle (0 = empty) and its solution
function Game.Generate(level)
    local solution = fullGrid()
    local puzzle = makePuzzle(solution, LEVELS[level] or LEVELS.easy)
    return puzzle, solution
end

-----------------------------------------------------------------------------
-- Drawing
-----------------------------------------------------------------------------
local CELL, THIN, THICK, EDGE = 36, 1, 3, 2
local BOX_SIZE = CELL * 3 + THIN * 2
local BOARD = EDGE * 2 + BOX_SIZE * 3 + THICK * 2
local PAD_W, PAD_H, PAD_GAP, ERASE_W = 36, 38, 4, 64
local COLORS = {
    boxLine  = { 0.36, 0.50, 0.62 },
    cellLine = { 0.17, 0.23, 0.28 },
    cell     = { 0.09, 0.12, 0.15 },
    peer     = { 0.13, 0.18, 0.23 },   -- same row, column or box as the selected cell
    same     = { 0.17, 0.27, 0.38 },   -- same number as the selected cell
    selected = { 0.24, 0.38, 0.55 },
    given    = { 0.93, 0.96, 0.97 },
    entered  = { 0.52, 0.73, 1.00 },
    conflict = { 1.00, 0.42, 0.36 },
    done     = { 0.35, 0.40, 0.45 },
}

local cells, pad = {}, {}
local eraseButton
local given, grid, selected, emptyCount

local function offset(k) return EDGE + k * CELL + (k - floor(k / 3)) * THIN + floor(k / 3) * THICK end

-- cells whose number is also in their row, column or box
local function conflicts()
    local bad, any = {}, false
    for u = 1, 27 do
        local seen = {}
        for _, i in ipairs(UNITS[u]) do
            local n = grid[i]
            if n ~= 0 then
                if seen[n] then
                    bad[i], bad[seen[n]], any = true, true, true
                else
                    seen[n] = i
                end
            end
        end
    end
    return bad, any
end

-- (an empty board while a new one is being made)
local function paint()
    local bad = grid and conflicts() or {}
    local sel = grid and selected
    local sr, sc, sb, sv
    if sel then sr, sc, sb, sv = ROW[sel], COL[sel], BOX[sel], grid[sel] end
    local placed = {}
    for i = 1, 81 do
        local cell, n = cells[i], grid and grid[i] or 0
        if n ~= 0 then placed[n] = (placed[n] or 0) + 1 end
        local color = COLORS.cell
        if sel then
            if i == sel then
                color = COLORS.selected
            elseif sv ~= 0 and n == sv then
                color = COLORS.same
            elseif ROW[i] == sr or COL[i] == sc or BOX[i] == sb then
                color = COLORS.peer
            end
        end
        cell.bg:SetColorTexture(color[1], color[2], color[3], 1)
        if n == 0 then
            cell.text:SetText("")
        else
            local tc = bad[i] and COLORS.conflict or (given[i] ~= 0 and COLORS.given or COLORS.entered)
            cell.text:SetText(n)
            cell.text:SetTextColor(tc[1], tc[2], tc[3])
        end
    end
    -- a number placed nine times is dimmed on the number row
    for n = 1, 9 do
        pad[n].done = (placed[n] or 0) >= 9
        pad[n]:Paint()
    end
end

local function refreshTexts()
    if eraseButton then eraseButton:SetLabel(T("erase")) end
end

-----------------------------------------------------------------------------
-- Play
-----------------------------------------------------------------------------
local function put(n)
    local i = selected
    if MG.IsFinished() or not (grid and i) or given[i] ~= 0 or grid[i] == n then return end
    MG.StartClock()
    if grid[i] == 0 then emptyCount = emptyCount - 1 end
    if n == 0 then emptyCount = emptyCount + 1 end
    grid[i] = n
    if emptyCount == 0 then
        local _, any = conflicts()
        if not any then
            selected = nil
            paint()
            MG.Win()
            return
        end
    end
    paint()
end

local function onCellClick(self, button)
    if not grid then return end
    selected = self.index
    if button == "RightButton" then
        put(0)
    end
    paint()
end

local function onPadClick(self)
    local n = self.digit
    -- the number already in the cell takes it out again
    if n ~= 0 and selected and grid and grid[selected] == n then n = 0 end
    put(n)
end

function Game.Build(area)
    local width, height = area:GetWidth(), area:GetHeight()
    local top = floor((height - (BOARD + 10 + PAD_H)) / 2)
    local board = CreateFrame("Frame", nil, area)
    board:SetSize(BOARD, BOARD)
    board:SetPoint("TOPLEFT", area, "TOPLEFT", floor((width - BOARD) / 2), -top)
    local bg = board:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetAllPoints()
    bg:SetColorTexture(COLORS.boxLine[1], COLORS.boxLine[2], COLORS.boxLine[3], 1)
    for b = 0, 8 do
        local t = board:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetSize(BOX_SIZE, BOX_SIZE)
        t:SetPoint("TOPLEFT", board, "TOPLEFT", offset((b % 3) * 3), -offset(floor(b / 3) * 3))
        t:SetColorTexture(COLORS.cellLine[1], COLORS.cellLine[2], COLORS.cellLine[3], 1)
    end
    for i = 1, 81 do
        local cell = CreateFrame("Button", nil, board)
        cell:SetSize(CELL, CELL)
        cell:SetPoint("TOPLEFT", board, "TOPLEFT", offset(COL[i]), -offset(ROW[i]))
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell.bg = cell:CreateTexture(nil, "BACKGROUND")
        cell.bg:SetAllPoints()
        cell.bg:SetColorTexture(COLORS.cell[1], COLORS.cell[2], COLORS.cell[3], 1)
        cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        cell.text:SetPoint("CENTER", 0, 0)
        local hl = cell:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        cell.index = i
        cell:SetScript("OnClick", onCellClick)
        cells[i] = cell
    end

    -- number row under the board: 1-9 and erase
    local rowW = PAD_W * 9 + PAD_GAP * 8 + 8 + ERASE_W
    local left, y = floor((width - rowW) / 2), -(top + BOARD + 10)
    for n = 1, 9 do
        local b = MG.Button(area, PAD_W, PAD_H, tostring(n))
        b:SetPoint("TOPLEFT", area, "TOPLEFT", left + (n - 1) * (PAD_W + PAD_GAP), y)
        if GameFontHighlightLarge then
            b.label:SetFontObject(GameFontHighlightLarge)
            b.labelFont = nil
        end
        local basePaint = b.Paint
        function b:Paint()
            basePaint(self)
            if self.done and not self.active then
                self.label:SetTextColor(COLORS.done[1], COLORS.done[2], COLORS.done[3])
            end
        end
        b.digit = n
        b:SetScript("OnClick", onPadClick)
        pad[n] = b
    end
    eraseButton = MG.Button(area, ERASE_W, PAD_H, "")
    eraseButton:SetPoint("TOPLEFT", area, "TOPLEFT", left + rowW - ERASE_W, y)
    eraseButton.digit = 0
    eraseButton:SetScript("OnClick", onPadClick)
    refreshTexts()
end

local maker = CreateFrame("Frame")

local function stopJob()
    job, jobLevel = nil, nil
    maker:SetScript("OnUpdate", nil)
end

local function runJob()
    if not job then return stopJob() end
    sliceStart = now()
    local ok, puzzle = coroutine.resume(job, jobLevel)
    if ok and coroutine.status(job) == "suspended" then
        maker:SetScript("OnUpdate", runJob)
        return
    end
    stopJob()
    if not ok then
        -- leave the board empty (New game tries again) and report the error
        if geterrorhandler then geterrorhandler()(puzzle) end
        return
    end
    given, grid, selected, emptyCount = {}, {}, nil, 0
    for i = 1, 81 do
        given[i], grid[i] = puzzle[i], puzzle[i]
        if puzzle[i] == 0 then emptyCount = emptyCount + 1 end
    end
    paint()
end

function Game.Start(level)
    given, grid, selected, emptyCount = nil, nil, nil, 0
    refreshTexts()
    paint()
    job, jobLevel = coroutine.create(Game.Generate), level
    runJob()
end

function Game.OnSelect()
    refreshTexts()
end

function Game.Status()
    if not grid then return "" end
    return string.format(T("st_cells"), emptyCount or 0, MG.Clock(MG.Elapsed()))
end

-- saved board (for /reload or logout in the middle of a game)
local function pack(list)
    local out = {}
    for i = 1, 81 do out[i] = tostring(list[i]) end
    return table.concat(out)
end

local function unpackBoard(text)
    if type(text) ~= "string" or #text ~= 81 or text:find("[^0-9]") then return nil end
    local out = {}
    for i = 1, 81 do out[i] = text:byte(i) - 48 end
    return out
end

function Game.Save()
    if not grid then return nil end
    return { given = pack(given), grid = pack(grid), selected = selected }
end

function Game.Load(t, level)
    local g, c = unpackBoard(t.given), unpackBoard(t.grid)
    if not (g and c) then error("sudoku: no saved board") end
    local empty = 0
    for i = 1, 81 do
        if g[i] ~= 0 and c[i] ~= g[i] then error("sudoku: saved board does not match") end
        if c[i] == 0 then empty = empty + 1 end
    end
    stopJob()
    given, grid, emptyCount = g, c, empty
    local sel = tonumber(t.selected)
    selected = (sel and sel >= 1 and sel <= 81 and sel == floor(sel)) and sel or nil
    refreshTexts()
    paint()
end

MG.Register(Game)
