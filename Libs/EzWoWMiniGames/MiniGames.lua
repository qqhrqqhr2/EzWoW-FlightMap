--===========================================================================
-- EzWoW shared : Libs/EzWoWMiniGames/MiniGames.lua
-- Mini games window (tabs, levels, records, clock, saved boards).
-- The same files ship in EzWoW - Flight Map and EzWoW - Smart Fishing; when both
-- are installed only one copy runs, so there is one window: the newest version
-- wins, and a newer copy that loads later retires the older one (its watcher and
-- logout saver are stopped and its Open/Toggle are routed to the new copy).
--===========================================================================
-- Games register themselves with MiniGames.Register (Games/*.lua). With the
-- flight map addon the window opens by itself when a flight starts and closes on
-- landing unless a game is still being played.
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tostring, pcall = type, pairs, ipairs, tostring, pcall

local LIB_VERSION = 3
local WINDOW_NAME = "EzWoWMiniGamesWindow"
local previous = _G.EzWoW_MiniGames
if type(previous) == "table" and (tonumber(previous.version) or 0) >= LIB_VERSION then return end

local MiniGames = { version = LIB_VERSION, owner = ADDON_NAME, windowName = WINDOW_NAME }
_G.EzWoW_MiniGames = MiniGames
ns.MiniGames = MiniGames
MiniGames.games, MiniGames.order = {}, {}
MiniGames.icon = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Libs\\EzWoWMiniGames\\Icon"
-- automatic opening on flights is for the flight map addon
local FLIGHT_HOST = ADDON_NAME == "EzWoW-FlightMap"

-- the host addon's language choice, if it has one
local function hostLocale()
    if type(ns.GetActiveLocaleKey) == "function" then
        local ok, lang = pcall(ns.GetActiveLocaleKey)
        if ok and type(lang) == "string" then return lang end
    end
    local pref = ns.settings and ns.settings.language
    if type(pref) == "string" and pref ~= "auto" then return pref end
    return (GetLocale and GetLocale()) or "enUS"
end

-- EzWoW palette (same in every host)
local STYLE = {
    bgPrimary   = { 0.071, 0.094, 0.122, 0.96 },
    bgSecondary = { 0.114, 0.157, 0.192, 0.94 },
    border      = { 0.204, 0.298, 0.357, 1.00 },
    textBody    = { 0.929, 0.957, 0.969, 1.00 },
    textMuted   = { 0.655, 0.725, 0.773, 1.00 },
    accent      = { 0.522, 0.725, 1.000, 1.00 },
}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local AREA_W, AREA_H = 436, 400

-----------------------------------------------------------------------------
-- Strings
-----------------------------------------------------------------------------
local STR = {
    koKR = {
        title = "미니게임", sub = "잠깐 쉬는 동안 가볍게 한 판",
        mines = "지뢰찾기", memory = "짝 맞추기", puzzle = "퍼즐 맞추기", solitaire = "솔리테어",
        new = "새 게임", easy = "쉬움", normal = "보통", draw1 = "1장 뽑기", draw3 = "3장 뽑기",
        st_mines = "남은 지뢰 %d  ·  %s", st_moves = "이동 %d  ·  %s", st_tries = "시도 %d  ·  %s",
        win = "성공! %s", newBest = "새 최고 기록! %s", lose = "펑! 지뢰를 밟았습니다. 새 게임을 눌러 보세요.",
        best = "최고 기록: %s", noBest = "최고 기록 없음",
        autoOpen = "비행을 시작하면 자동으로 열기",
        autoOff = "비행할 때 미니게임 창을 자동으로 열지 않습니다. 다시 켜려면 /미니게임 창 아래의 '비행을 시작하면 자동으로 열기'를 선택하세요.",
        h_mines = "왼쪽 클릭: 열기 · 오른쪽 클릭: 깃발 · 숫자 클릭: 주변 열기",
        h_memory = "같은 그림 두 장을 찾으세요.",
        h_puzzle = "빈칸과 같은 줄의 조각을 누르면 밀립니다. 1부터 순서대로 맞추세요.",
        h_solitaire = "카드를 누른 뒤 옮길 곳을 누르세요 · 오른쪽 클릭: 모으기 칸으로",
        autoFinish = "자동 완료",
        resizeTip = "오른쪽 아래 모서리를 끌거나 Ctrl + 휠로 창 크기를 바꿉니다.",
    },
    enUS = {
        title = "Mini Games", sub = "A quick game while you wait",
        mines = "Minesweeper", memory = "Memory", puzzle = "Sliding Puzzle", solitaire = "Solitaire",
        new = "New game", easy = "Easy", normal = "Normal", draw1 = "Draw 1", draw3 = "Draw 3",
        st_mines = "Mines left %d  ·  %s", st_moves = "Moves %d  ·  %s", st_tries = "Tries %d  ·  %s",
        win = "Solved! %s", newBest = "New best! %s", lose = "Boom! Press New game to try again.",
        best = "Best: %s", noBest = "No record yet",
        autoOpen = "Open when a flight starts",
        autoOff = "The mini games window will no longer open on flights. To turn it back on, tick 'Open when a flight starts' at the bottom of /ezgames.",
        h_mines = "Left-click: open · Right-click: flag · Click a number: open around it",
        h_memory = "Find the pairs of matching pictures.",
        h_puzzle = "Click a tile in line with the gap to slide it. Put 1 to the end in order.",
        h_solitaire = "Click a card, then where it goes · Right-click: to the foundation",
        autoFinish = "Auto finish",
        resizeTip = "Drag the bottom-right corner or use Ctrl + wheel to resize.",
    },
    deDE = {
        title = "Minispiele", sub = "Ein schnelles Spiel zwischendurch",
        mines = "Minensuche", memory = "Memory", puzzle = "Schiebepuzzle", solitaire = "Solitär",
        new = "Neues Spiel", easy = "Leicht", normal = "Normal", draw1 = "1 ziehen", draw3 = "3 ziehen",
        st_mines = "Minen übrig %d  ·  %s", st_moves = "Züge %d  ·  %s", st_tries = "Versuche %d  ·  %s",
        win = "Geschafft! %s", newBest = "Neuer Rekord! %s", lose = "Bumm! Neues Spiel für einen neuen Versuch.",
        best = "Rekord: %s", noBest = "Noch kein Rekord",
        autoOpen = "Beim Flugstart öffnen",
        h_mines = "Links: öffnen · Rechts: Flagge · Zahl anklicken: Umgebung öffnen",
        h_memory = "Finde die Paare gleicher Bilder.",
        h_puzzle = "Ein Teil in einer Linie mit der Lücke anklicken. 1 bis Ende ordnen.",
        h_solitaire = "Karte anklicken, dann das Ziel · Rechtsklick: auf die Ablage",
        autoFinish = "Automatisch beenden",
        resizeTip = "Untere rechte Ecke ziehen oder Strg + Mausrad zum Ändern der Größe.",
    },
    frFR = {
        title = "Mini-jeux", sub = "Une petite partie en attendant",
        mines = "Démineur", memory = "Mémoire", puzzle = "Taquin", solitaire = "Solitaire",
        new = "Nouvelle partie", easy = "Facile", normal = "Normal", draw1 = "Piocher 1", draw3 = "Piocher 3",
        st_mines = "Mines restantes %d  ·  %s", st_moves = "Coups %d  ·  %s", st_tries = "Essais %d  ·  %s",
        win = "Réussi ! %s", newBest = "Nouveau record ! %s", lose = "Boum ! Nouvelle partie pour réessayer.",
        best = "Record : %s", noBest = "Pas encore de record",
        autoOpen = "Ouvrir au début d'un vol",
        h_mines = "Clic gauche : ouvrir · Clic droit : drapeau · Clic sur un chiffre : ouvrir autour",
        h_memory = "Trouvez les paires d'images identiques.",
        h_puzzle = "Cliquez une pièce alignée avec la case vide. Remettez-les dans l'ordre.",
        h_solitaire = "Cliquez une carte, puis sa destination · Clic droit : vers les fondations",
        autoFinish = "Finir automatiquement",
        resizeTip = "Glissez le coin inférieur droit ou Ctrl + molette pour redimensionner.",
    },
    esES = {
        title = "Minijuegos", sub = "Una partida rápida mientras esperas",
        mines = "Buscaminas", memory = "Memoria", puzzle = "Puzle deslizante", solitaire = "Solitario",
        new = "Nueva partida", easy = "Fácil", normal = "Normal", draw1 = "Robar 1", draw3 = "Robar 3",
        st_mines = "Minas %d  ·  %s", st_moves = "Movimientos %d  ·  %s", st_tries = "Intentos %d  ·  %s",
        win = "¡Resuelto! %s", newBest = "¡Nuevo récord! %s", lose = "¡Bum! Pulsa Nueva partida para reintentar.",
        best = "Récord: %s", noBest = "Aún sin récord",
        autoOpen = "Abrir al empezar un vuelo",
        h_mines = "Clic izquierdo: abrir · Clic derecho: bandera · Clic en número: abrir alrededor",
        h_memory = "Encuentra las parejas de imágenes iguales.",
        h_puzzle = "Pulsa una pieza alineada con el hueco. Ordénalas del 1 al final.",
        h_solitaire = "Pulsa una carta y luego su destino · Clic derecho: a la base",
        autoFinish = "Terminar solo",
        resizeTip = "Arrastra la esquina inferior derecha o usa Ctrl + rueda para cambiar el tamaño.",
    },
    ruRU = {
        title = "Мини-игры", sub = "Быстрая партия, пока ждёте",
        mines = "Сапёр", memory = "Пары", puzzle = "Пятнашки", solitaire = "Пасьянс",
        new = "Новая игра", easy = "Легко", normal = "Средне", draw1 = "По 1", draw3 = "По 3",
        st_mines = "Мин осталось %d  ·  %s", st_moves = "Ходы %d  ·  %s", st_tries = "Попытки %d  ·  %s",
        win = "Готово! %s", newBest = "Новый рекорд! %s", lose = "Бум! Нажмите «Новая игра».",
        best = "Рекорд: %s", noBest = "Рекорда пока нет",
        autoOpen = "Открывать при начале полёта",
        h_mines = "ЛКМ: открыть · ПКМ: флажок · Клик по цифре: открыть вокруг",
        h_memory = "Найдите пары одинаковых картинок.",
        h_puzzle = "Нажмите плитку в одной линии с пустой клеткой. Расставьте по порядку.",
        h_solitaire = "Нажмите карту, затем место · ПКМ: в базу",
        autoFinish = "Доиграть",
        resizeTip = "Тяните правый нижний угол или Ctrl + колесо, чтобы изменить размер.",
    },
    zhCN = {
        title = "小游戏", sub = "等待时轻松玩一局",
        mines = "扫雷", memory = "翻牌配对", puzzle = "数字华容道", solitaire = "纸牌接龙",
        new = "新游戏", easy = "简单", normal = "普通", draw1 = "每次 1 张", draw3 = "每次 3 张",
        st_mines = "剩余地雷 %d  ·  %s", st_moves = "移动 %d  ·  %s", st_tries = "尝试 %d  ·  %s",
        win = "完成！%s", newBest = "新纪录！%s", lose = "砰！点击新游戏再试一次。",
        best = "最佳纪录：%s", noBest = "暂无纪录",
        autoOpen = "开始飞行时自动打开",
        h_mines = "左键：翻开 · 右键：插旗 · 点数字：翻开周围",
        h_memory = "找出相同图案的两张牌。",
        h_puzzle = "点击与空格同一行或列的方块即可滑动，按顺序排好。",
        h_solitaire = "先点卡牌，再点目标位置 · 右键：移到收牌区",
        autoFinish = "自动完成",
        resizeTip = "拖动右下角或按住 Ctrl 滚动滚轮调整窗口大小。",
    },
    zhTW = {
        title = "小遊戲", sub = "等待時輕鬆玩一局",
        mines = "踩地雷", memory = "翻牌配對", puzzle = "數字推盤", solitaire = "接龍",
        new = "新遊戲", easy = "簡單", normal = "普通", draw1 = "每次 1 張", draw3 = "每次 3 張",
        st_mines = "剩餘地雷 %d  ·  %s", st_moves = "移動 %d  ·  %s", st_tries = "嘗試 %d  ·  %s",
        win = "完成！%s", newBest = "新紀錄！%s", lose = "砰！點擊新遊戲再試一次。",
        best = "最佳紀錄：%s", noBest = "暫無紀錄",
        autoOpen = "開始飛行時自動開啟",
        h_mines = "左鍵：翻開 · 右鍵：插旗 · 點數字：翻開周圍",
        h_memory = "找出相同圖案的兩張牌。",
        h_puzzle = "點擊與空格同一行或列的方塊即可滑動，依序排好。",
        h_solitaire = "先點卡牌，再點目標位置 · 右鍵：移到收牌區",
        autoFinish = "自動完成",
        resizeTip = "拖曳右下角或按住 Ctrl 滾動滾輪調整視窗大小。",
    },
}

function MiniGames.T(key)
    local lang = hostLocale()
    if lang == "esMX" then lang = "esES" end
    local tbl = STR[lang] or STR.enUS
    return tbl[key] or STR.enUS[key] or key
end
local T = MiniGames.T

function MiniGames.Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-----------------------------------------------------------------------------
-- Small widgets (EzWoW style)
-----------------------------------------------------------------------------
local function S() return STYLE end
local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
MiniGames.BACKDROP = BACKDROP

function MiniGames.Button(parent, w, h, text)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop(BACKDROP)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetWordWrap(false)
    function b:Paint()
        local st = S()
        if self.active then
            self:SetBackdropColor(0.10, 0.17, 0.26, 0.96)
            self:SetBackdropBorderColor(rgba(st.accent))
            self.label:SetTextColor(rgba(st.accent))
        else
            self:SetBackdropColor(self.hover and 0.16 or 0.114, self.hover and 0.21 or 0.157, self.hover and 0.26 or 0.192, 0.96)
            self:SetBackdropBorderColor(rgba(self.hover and st.accent or st.border))
            self.label:SetTextColor(rgba(st.textBody))
        end
    end
    function b:SetActive(v) self.active = v and true or false self:Paint() end
    function b:SetLabel(t) self.label:SetText(t or "") end
    b:SetScript("OnEnter", function(self) self.hover = true self:Paint() end)
    b:SetScript("OnLeave", function(self) self.hover = false self:Paint() end)
    b:SetLabel(text)
    b:Paint()
    return b
end

-----------------------------------------------------------------------------
-- Records
-----------------------------------------------------------------------------
local function store()
    -- kept in the host addon's saved table (Flight Map: DB, Smart Fishing: db)
    local db = ns.DB or ns.db
    if type(db) ~= "table" then return nil end
    if type(db.games) ~= "table" then db.games = {} end
    local g = db.games
    if type(g.best) ~= "table" then g.best = {} end
    if g.autoOpen == nil then g.autoOpen = FLIGHT_HOST end
    return g
end

local function recordKey(game, level) return game .. ":" .. tostring(level) end

function MiniGames.BestText(game, level)
    local g = store()
    local value = g and g.best[recordKey(game, level)]
    return value and string.format(T("best"), MiniGames.Clock(value)) or T("noBest")
end

-----------------------------------------------------------------------------
-- Window
-----------------------------------------------------------------------------
local win
local state = { game = nil, level = {} }
-- one session per game: tabs keep their own board, and the clock only runs
-- while the window is open (flights and fishing breaks add up to one game)
local sessions = {}

local function session(key)
    key = key or state.game
    if not key then return nil end
    sessions[key] = sessions[key] or { accum = 0 }
    return sessions[key]
end

local function pause(key)
    local s = sessions[key or state.game or ""]
    if s and s.resumeAt then
        s.accum = s.accum + (GetTime() - s.resumeAt)
        s.resumeAt = nil
    end
end

local function resume(key)
    local s = sessions[key or state.game or ""]
    if s and s.started and not s.finished and not s.resumeAt then s.resumeAt = GetTime() end
end

-- Called by a game: first move starts the clock.
function MiniGames.StartClock()
    local s = session()
    if s and not s.started then
        s.started = true
        s.resumeAt = GetTime()
    end
end

function MiniGames.Elapsed()
    local s = sessions[state.game or ""]
    if not s then return 0 end
    return s.accum + (s.resumeAt and (GetTime() - s.resumeAt) or 0)
end

function MiniGames.IsPlaying()
    local s = sessions[state.game or ""]
    return s and s.started and not s.finished or false
end

function MiniGames.SetStatus(text)
    if win then win.status:SetText(text or "") end
end

local function finish(statusText)
    local s = session()
    pause()
    s.finished = true
    s.statusText = statusText
    MiniGames.SetStatus(statusText)
end

-- Called by a game when it is solved.
function MiniGames.Win()
    local s = session()
    if not s or s.finished then return end
    pause()
    local seconds = math.floor(MiniGames.Elapsed() + 0.5)
    local g = store()
    local key = recordKey(state.game, state.level[state.game])
    local isBest = false
    if g then
        local old = g.best[key]
        if not old or seconds < old then
            g.best[key] = seconds
            isBest = true
        end
    end
    finish("|cff40ff59" .. string.format(T(isBest and "newBest" or "win"), MiniGames.Clock(seconds)) .. "|r")
    win.best:SetText(MiniGames.BestText(state.game, state.level[state.game]))
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then
        pcall(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
    end
end

function MiniGames.Lose()
    local s = session()
    if not s or s.finished then return end
    finish("|cffff6a5a" .. T("lose") .. "|r")
end

function MiniGames.IsFinished()
    local s = sessions[state.game or ""]
    return s and s.finished or false
end

function MiniGames.Register(game)
    MiniGames.games[game.key] = game
    MiniGames.order[#MiniGames.order + 1] = game.key
end

local function showInfo()
    local game = MiniGames.games[state.game]
    local s = sessions[state.game]
    win.best:SetText(MiniGames.BestText(state.game, state.level[state.game]))
    win.hint:SetText(T("h_" .. state.game))
    if s and s.finished then
        MiniGames.SetStatus(s.statusText or "")
    elseif game and game.Status then
        MiniGames.SetStatus(game.Status())
    end
end

local function newGame()
    local game = MiniGames.games[state.game]
    if not game then return end
    sessions[state.game] = { accum = 0 }
    game.Start(state.level[state.game] or game.levels[1])
    showInfo()
end

local function selectGame(key)
    pause()
    state.game = key
    local g = store()
    if g then g.lastGame = key end
    for k, game in pairs(MiniGames.games) do
        if game.area then game.area:SetShown(k == key) end
    end
    for _, tab in ipairs(win.tabs) do tab:SetActive(tab.key == key) end
    local game = MiniGames.games[key]
    if not state.level[key] then state.level[key] = (g and g["level:" .. key]) or game.levels[1] end
    for i, chip in ipairs(win.levelChips) do
        local level = game.levels[i]
        chip:SetShown(level ~= nil)
        if level then
            chip.level = level
            chip:SetLabel(T(level))
            chip:SetActive(level == state.level[key])
        end
    end
    if win.extra then win.extra:Hide() end
    if game.OnSelect then game.OnSelect(win) end
    if sessions[key] then
        resume(key)      -- the board is still there: carry on
        showInfo()
    else
        newGame()
    end
end

-----------------------------------------------------------------------------
-- Keeping games between sessions (/reload, logout)
-----------------------------------------------------------------------------
local function saveAll()
    -- nothing loaded yet (the window's first Hide while it is being built)
    if not state.game then return end
    local g = store()
    if not g then return end
    pause()
    g.saved = {}
    for key, game in pairs(MiniGames.games) do
        local s = sessions[key]
        if s and game.Save then
            local ok, data = pcall(game.Save)
            if ok and type(data) == "table" then
                g.saved[key] = { data = data, level = state.level[key], started = s.started,
                    finished = s.finished, accum = s.accum, status = s.statusText }
            end
        end
    end
end

local function loadAll()
    local g = store()
    if not g or type(g.saved) ~= "table" then return end
    for key, saved in pairs(g.saved) do
        local game = MiniGames.games[key]
        if game and game.Load and type(saved) == "table" and type(saved.data) == "table" then
            local level = saved.level or game.levels[1]
            if pcall(game.Load, saved.data, level) then
                state.level[key] = level
                sessions[key] = { accum = tonumber(saved.accum) or 0, started = saved.started,
                    finished = saved.finished, statusText = saved.status }
            end
        end
    end
end

local saver = CreateFrame("Frame")
saver:RegisterEvent("PLAYER_LOGOUT")
saver:SetScript("OnEvent", function() if win then saveAll() end end)
MiniGames.saver = saver

-----------------------------------------------------------------------------
-- Size & place (scale 0.6 - 1.6, top-left corner kept while resizing)
-----------------------------------------------------------------------------
local MIN_SCALE, MAX_SCALE = 0.6, 1.6

function MiniGames.SetScale(scale)
    if not win then return end
    scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scale or 1))
    local old = win:GetScale()
    local left, top = win:GetLeft(), win:GetTop()
    win:SetScale(scale)
    if left and top then
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
    end
end

function MiniGames.SavePlace()
    local g = store()
    if not (g and win) then return end
    local scale = win:GetScale()
    local left, top = win:GetLeft(), win:GetTop()
    g.scale = scale
    if left and top then g.place = { left * scale, top * scale } end
end

function MiniGames.RestorePlace()
    local g = store()
    if not (g and win) then return end
    local scale = math.max(MIN_SCALE, math.min(MAX_SCALE, tonumber(g.scale) or 1))
    win:SetScale(scale)
    if type(g.place) == "table" and tonumber(g.place[1]) and tonumber(g.place[2]) then
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", g.place[1] / scale, g.place[2] / scale)
    end
end

local function build()
    win = CreateFrame("Frame", WINDOW_NAME, UIParent, "BackdropTemplate")
    MiniGames.window = win
    win:SetSize(460, 600)
    win:SetPoint("CENTER", UIParent, "CENTER", 260, 20)
    MiniGames.RestorePlace()
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetBackdrop(BACKDROP)
    win:SetBackdropColor(rgba(S().bgPrimary))
    win:SetBackdropBorderColor(rgba(S().border))
    if UISpecialFrames then tinsert(UISpecialFrames, WINDOW_NAME) end

    local top = CreateFrame("Frame", nil, win, "BackdropTemplate")
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(56)
    top:SetBackdrop({ bgFile = WHITE })
    top:SetBackdropColor(rgba(S().bgSecondary))
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function() win:StartMoving() end)
    top:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        MiniGames.SavePlace()
    end)
    local line = top:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(rgba(S().accent))
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(2)
    local icon = top:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 14, 0)
    icon:SetTexture(MiniGames.icon)
    win.title = top:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    win.title:SetTextColor(rgba(S().accent))
    win.sub = top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 1)
    win.sub:SetTextColor(rgba(S().textMuted))
    local close = MiniGames.Button(top, 24, 24, "X")
    close:SetPoint("TOPRIGHT", -12, -16)
    close:SetScript("OnClick", function() win:Hide() end)

    win.tabs = {}
    for i, key in ipairs(MiniGames.order) do
        local tab = MiniGames.Button(win, 106, 26, "")
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 110, -66)
        tab.key = key
        tab:SetScript("OnClick", function(self) selectGame(self.key) end)
        win.tabs[i] = tab
    end

    win.levelChips = {}
    for i = 1, 2 do
        local chip = MiniGames.Button(win, 90, 24, "")
        chip:SetPoint("TOPLEFT", 12 + (i - 1) * 94, -100)
        chip:SetScript("OnClick", function(self)
            state.level[state.game] = self.level
            local g = store()
            if g then g["level:" .. state.game] = self.level end
            for _, c in ipairs(win.levelChips) do c:SetActive(c.level == self.level) end
            newGame()
        end)
        win.levelChips[i] = chip
    end
    win.newBtn = MiniGames.Button(win, 110, 24, "")
    win.newBtn:SetPoint("TOPRIGHT", -12, -100)
    win.newBtn:SetScript("OnClick", newGame)
    -- a game may use this slot for its own button (e.g. auto finish)
    win.extra = MiniGames.Button(win, 100, 24, "")
    win.extra:SetPoint("RIGHT", win.newBtn, "LEFT", -6, 0)
    win.extra:Hide()

    local areaHolder = CreateFrame("Frame", nil, win, "BackdropTemplate")
    areaHolder:SetPoint("TOPLEFT", 12, -132)
    areaHolder:SetSize(AREA_W, AREA_H)
    areaHolder:SetBackdrop(BACKDROP)
    areaHolder:SetBackdropColor(0.047, 0.067, 0.086, 0.9)
    areaHolder:SetBackdropBorderColor(rgba(S().border))
    for _, key in ipairs(MiniGames.order) do
        local game = MiniGames.games[key]
        local area = CreateFrame("Frame", nil, areaHolder)
        area:SetPoint("TOPLEFT", 4, -4)
        area:SetSize(AREA_W - 8, AREA_H - 8)
        area:Hide()
        game.area = area
        game.Build(area)
    end

    win.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.status:SetPoint("TOPLEFT", 14, -540)
    win.status:SetJustifyH("LEFT")
    win.best = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.best:SetPoint("TOPRIGHT", -14, -542)
    win.best:SetTextColor(rgba(S().textMuted))
    win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.hint:SetPoint("TOPLEFT", 14, -560)
    win.hint:SetWidth(432)
    win.hint:SetJustifyH("LEFT")
    win.hint:SetTextColor(rgba(S().textMuted))

    win.auto = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    win.auto:SetSize(22, 22)
    win.auto:SetPoint("BOTTOMLEFT", 10, 4)
    win.autoText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.autoText:SetPoint("LEFT", win.auto, "RIGHT", 2, 0)
    win.auto:SetScript("OnClick", function(self)
        local g = store()
        if g then g.autoOpen = self:GetChecked() and true or false end
    end)

    local tick = 0
    win:SetScript("OnUpdate", function(_, elapsed)
        tick = tick + elapsed
        if tick < 0.25 then return end
        tick = 0
        local game = MiniGames.games[state.game]
        if game and game.Status and not MiniGames.IsFinished() then MiniGames.SetStatus(game.Status()) end
    end)
    win:SetScript("OnShow", function()
        win.title:SetText(T("title"))
        win.sub:SetText(T("sub"))
        win.newBtn:SetLabel(T("new"))
        win.autoText:SetText(T("autoOpen"))
        local g = store()
        win.auto:SetChecked(not g or g.autoOpen ~= false)
        for _, tab in ipairs(win.tabs) do tab:SetLabel(T(tab.key)) end
        if not state.game then
            loadAll()
            selectGame((g and g.lastGame and MiniGames.games[g.lastGame] and g.lastGame) or MiniGames.order[1])
        else
            resume()
        end
    end)
    -- resize: the whole window scales, so every game keeps its own layout
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(win:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(T("resizeTip"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    grip:SetScript("OnMouseDown", function(self)
        local left = win:GetLeft() * win:GetScale()
        local uiScale = UIParent:GetEffectiveScale()
        self:SetScript("OnUpdate", function()
            local cx = GetCursorPosition() / uiScale
            MiniGames.SetScale((cx - left) / 460)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        MiniGames.SavePlace()
    end)
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta)
        if not IsControlKeyDown() then return end
        MiniGames.SetScale(win:GetScale() + delta * 0.05)
        MiniGames.SavePlace()
    end)

    win:SetScript("OnHide", function()
        -- the clock stops while the window is closed; the board is kept
        saveAll()
        -- the player closed the window that opened by itself on this flight:
        -- stop opening it on later flights (the checkbox turns it back on)
        if MiniGames.autoOpened and not MiniGames.addonHiding
            and UnitOnTaxi and UnitOnTaxi("player") then
            local g = store()
            if g and g.autoOpen ~= false then
                g.autoOpen = false
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. T("title") .. "|r: " .. T("autoOff"))
                end
            end
        end
        MiniGames.autoOpened = false
    end)
    win:Hide()
end

function MiniGames.Open()
    if not win then build() end
    win:Show()
    win:Raise()
end

function MiniGames.Toggle()
    if win and win:IsShown() then win:Hide() else MiniGames.Open() end
end

-- hides done by the addon itself (landing, another copy taking over) are not
-- the player closing the window
local function addonHide()
    if not (win and win:IsShown()) then return end
    MiniGames.addonHiding = true
    pcall(win.Hide, win)
    MiniGames.addonHiding = false
end

function MiniGames.Close()
    addonHide()
end

function MiniGames.ExtraButton() return win and win.extra end

-----------------------------------------------------------------------------
-- Open on take-off, close on landing (unless a game is going on)
-- No permanent OnUpdate: taxi-related events start a short check that runs
-- only until the taxi state changes (or a few seconds pass).
-----------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
MiniGames.watcher = watcher
local wasOnTaxi, elapsedWatch, watchLeft = false, 0, 0
local WATCH_STEP, WATCH_TIME = 0.25, 6

local function checkTaxi()
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player") and true or false
    if onTaxi == wasOnTaxi then return false end
    if onTaxi then
        local g = store()
        if g and g.autoOpen ~= false and not (win and win:IsShown()) then
            MiniGames.Open()
            MiniGames.autoOpened = true
        end
    else
        MiniGames.autoOpened = false
        if win and win:IsShown() and not MiniGames.IsPlaying() then addonHide() end
    end
    wasOnTaxi = onTaxi
    return true
end

local function watchUpdate(self, elapsed)
    elapsedWatch = elapsedWatch + elapsed
    if elapsedWatch < WATCH_STEP then return end
    watchLeft = watchLeft - elapsedWatch
    elapsedWatch = 0
    if checkTaxi() or watchLeft <= 0 then self:SetScript("OnUpdate", nil) end
end

local function startWatch()
    if checkTaxi() then return end
    elapsedWatch, watchLeft = 0, WATCH_TIME
    watcher:SetScript("OnUpdate", watchUpdate)
end

for _, event in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "TAXIMAP_CLOSED",
    "PLAYER_ENTERING_WORLD" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end
watcher:SetScript("OnEvent", startWatch)

-----------------------------------------------------------------------------
-- Taking over from an older copy (another addon shipping an older version)
-----------------------------------------------------------------------------
local function retire(old)
    if type(old) ~= "table" or old == MiniGames then return end
    for _, key in ipairs({ "watcher", "saver" }) do
        local frame = old[key]
        if type(frame) == "table" and frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
            frame:SetScript("OnEvent", nil)
            frame:SetScript("OnUpdate", nil)
        end
    end
    -- close its window (its OnHide keeps that copy's boards); version 1 had an
    -- unnamed reference only, so look for its old global name as well
    local oldWin = old.window or _G["EzWoWFlightMapGames"]
    if type(oldWin) == "table" and oldWin ~= win and oldWin.Hide then pcall(oldWin.Hide, oldWin) end
    -- anything still calling the old table (its own flight check, buttons)
    -- now reaches this copy
    old.Open = function() return MiniGames.Open() end
    old.Toggle = function() return MiniGames.Toggle() end
    old.Close = function() return MiniGames.Close() end
    old.retired = true
end
retire(previous)

SLASH_EZWOWFLIGHTGAMES1 = "/ezgames"
SLASH_EZWOWFLIGHTGAMES2 = "/미니게임"
SlashCmdList.EZWOWFLIGHTGAMES = function() MiniGames.Toggle() end
