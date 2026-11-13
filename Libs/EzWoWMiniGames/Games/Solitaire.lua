--===========================================================================
-- EzWoW shared : Libs/EzWoWMiniGames/Games/Solitaire.lua : Klondike solitaire (draw 1 / draw 3), click to move
--===========================================================================
local ADDON_NAME = ...
local MG = _G.EzWoW_MiniGames
-- only the copy belonging to the running window registers
if not MG or MG.owner ~= ADDON_NAME then return end
local T = MG.T

local Game = { key = "solitaire", levels = { "draw1", "draw3" } }

local CARD_W, CARD_H, GAP = 56, 76, 6
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
-- suit symbols when the client font has them, letters otherwise
local SUIT_GLYPHS = { "♠", "♥", "♦", "♣" }
local SUIT_LETTERS = { "S", "H", "D", "C" }

local buttons, slots = {}, {}
local stock, waste, foundations, tableau
local drawCount, moves, selected

local function suitText(suit)
    local locale = GetLocale and GetLocale() or "enUS"
    if locale == "koKR" or locale == "zhCN" or locale == "zhTW" then return SUIT_GLYPHS[suit] end
    return SUIT_LETTERS[suit]
end

local function isRed(card) return card.suit == 2 or card.suit == 3 end

-----------------------------------------------------------------------------
-- Rules
-----------------------------------------------------------------------------
local function top(pile) return pile[#pile] end

local function canFoundation(card, pile)
    local t = top(pile)
    if not t then return card.rank == 1 end
    return t.suit == card.suit and card.rank == t.rank + 1
end

local function canTableau(card, pile)
    local t = top(pile)
    if not t then return card.rank == 13 end
    return t.up and isRed(t) ~= isRed(card) and card.rank == t.rank - 1
end

local function flipTops()
    for _, pile in ipairs(tableau) do
        local t = top(pile)
        if t and not t.up then t.up = true end
    end
end

local function won()
    for _, f in ipairs(foundations) do if #f < 13 then return false end end
    return true
end

-- Moves cards from pile[index..] onto dest; returns true when legal.
local function move(pile, index, dest, destKind)
    if pile == dest then return false end
    if destKind ~= "foundation" and destKind ~= "tableau" then return false end
    local card = pile[index]
    if not card or not card.up then return false end
    if destKind == "foundation" then
        if index ~= #pile or not canFoundation(card, dest) then return false end
    elseif not canTableau(card, dest) then
        return false
    end
    for i = index, #pile do dest[#dest + 1] = pile[i] end
    for i = #pile, index, -1 do pile[i] = nil end
    flipTops()
    moves = moves + 1
    MG.StartClock()
    return true
end

local function drawFromStock()
    MG.StartClock()
    if #stock == 0 then
        for i = #waste, 1, -1 do
            local card = waste[i]
            card.up = false
            stock[#stock + 1] = card
            waste[i] = nil
        end
    else
        for _ = 1, drawCount do
            local card = table.remove(stock)
            if not card then break end
            card.up = true
            waste[#waste + 1] = card
        end
    end
    moves = moves + 1
end

local function toAnyFoundation(pile, index)
    for _, f in ipairs(foundations) do
        if move(pile, index, f, "foundation") then return true end
    end
    return false
end

local function canAutoFinish()
    if #stock > 0 or #waste > 0 then return false end
    for _, pile in ipairs(tableau) do
        for _, card in ipairs(pile) do if not card.up then return false end end
    end
    return not won()
end

-----------------------------------------------------------------------------
-- Drawing
-----------------------------------------------------------------------------
local render

local function paintCard(b, card, x, y, level)
    b.card = card
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", Game.area, "TOPLEFT", x, -y)
    b:SetFrameLevel(Game.area:GetFrameLevel() + 2 + level)
    if card.up then
        b:SetBackdropColor(0.93, 0.94, 0.92, 1)
        local r, g, bl = 0.10, 0.12, 0.15
        if isRed(card) then r, g, bl = 0.80, 0.15, 0.15 end
        local label = RANKS[card.rank] .. suitText(card.suit)
        b.corner:SetText(label)
        b.corner:SetTextColor(r, g, bl)
        b.center:SetText(suitText(card.suit))
        b.center:SetTextColor(r, g, bl)
        b.corner:Show()
        b.center:Show()
        b.back:Hide()
    else
        b:SetBackdropColor(0.20, 0.33, 0.52, 1)
        b.corner:Hide()
        b.center:Hide()
        b.back:Show()
    end
    local isSel = selected and selected.pile and selected.index and selected.pile[selected.index] and card.pileRef == selected.pile
        and card.indexInPile >= selected.index
    if isSel then
        b:SetBackdropBorderColor(1, 0.82, 0.2, 1)
    else
        b:SetBackdropBorderColor(0.05, 0.07, 0.09, 1)
    end
    b:Show()
end

local function slotPos(kind, i)
    local x0 = 2
    if kind == "stock" then return x0, 2 end
    if kind == "waste" then return x0 + (CARD_W + GAP), 2 end
    if kind == "foundation" then return x0 + (CARD_W + GAP) * (2 + i), 2 end
    return x0 + (CARD_W + GAP) * (i - 1), CARD_H + 14
end

render = function()
    local used = 0
    local function place(card, pile, index, x, y, level)
        used = used + 1
        card.pileRef, card.indexInPile = pile, index
        paintCard(buttons[used], card, x, y, level)
    end
    for _, s in ipairs(slots) do s:Show() end

    local sx, sy = slotPos("stock")
    if #stock > 0 then place(stock[#stock], stock, #stock, sx, sy, 1) end

    local wx, wy = slotPos("waste")
    local first = math.max(1, #waste - (drawCount == 3 and 2 or 0))
    for i = first, #waste do place(waste[i], waste, i, wx + (i - first) * 14, wy, i - first + 1) end

    for f = 1, 4 do
        local fx, fy = slotPos("foundation", f)
        local pile = foundations[f]
        if #pile > 0 then place(pile[#pile], pile, #pile, fx, fy, 1) end
    end

    local area = Game.area
    local maxBottom = area:GetHeight() - 2
    for t = 1, 7 do
        local pile = tableau[t]
        local tx, ty = slotPos("tableau", t)
        local count = #pile
        local step = 20
        if count > 1 then
            step = math.min(20, math.floor((maxBottom - ty - CARD_H) / (count - 1)))
            step = math.max(step, 8)
        end
        local y = ty
        for i, card in ipairs(pile) do
            place(card, pile, i, tx, y, i)
            y = y + (card.up and step or math.min(step, 10))
        end
    end
    for i = used + 1, #buttons do buttons[i]:Hide() buttons[i].card = nil end

    local extra = MG.ExtraButton()
    if extra and Game.area:IsShown() then extra:SetShown(canAutoFinish()) end
end

-----------------------------------------------------------------------------
-- Clicks
-----------------------------------------------------------------------------
local function pileKind(pile)
    if pile == stock then return "stock" end
    if pile == waste then return "waste" end
    for _, f in ipairs(foundations) do if f == pile then return "foundation" end end
    return "tableau"
end

local function finishCheck()
    render()
    if won() then MG.Win() end
end

local function clickPile(pile, index)
    if MG.IsFinished() then return end
    local kind = pileKind(pile)
    if kind == "stock" then
        selected = nil
        drawFromStock()
        finishCheck()
        return
    end
    if selected then
        local from, fromIndex = selected.pile, selected.index
        selected = nil
        if move(from, fromIndex, pile, kind) then
            finishCheck()
            return
        end
    end
    -- select: waste and foundation only their top card; tableau any face-up card
    local card = index and pile[index]
    if card and card.up and (kind == "tableau" or index == #pile) then
        selected = { pile = pile, index = index }
    end
    render()
end

local function onCardClick(self, button)
    local card = self.card
    if not card then return end
    local pile, index = card.pileRef, card.indexInPile
    if button == "RightButton" then
        if MG.IsFinished() then return end
        selected = nil
        if pileKind(pile) ~= "stock" and index == #pile and toAnyFoundation(pile, index) then
            finishCheck()
        else
            render()
        end
        return
    end
    clickPile(pile, index)
end

local function autoFinish()
    if not canAutoFinish() then return end
    local function step()
        if MG.IsFinished() or not Game.area:IsShown() then return end
        for _, pile in ipairs(tableau) do
            if #pile > 0 and toAnyFoundation(pile, #pile) then
                finishCheck()
                if not won() then C_Timer.After(0.06, step) end
                return
            end
        end
    end
    step()
end

-----------------------------------------------------------------------------
-- Game API
-----------------------------------------------------------------------------
function Game.Build(area)
    local function makeSlot(kind, i)
        local s = CreateFrame("Button", nil, area, "BackdropTemplate")
        s:SetSize(CARD_W, CARD_H)
        local x, y = slotPos(kind, i)
        s:SetPoint("TOPLEFT", area, "TOPLEFT", x, -y)
        s:SetBackdrop(MG.BACKDROP)
        s:SetBackdropColor(0.05, 0.08, 0.10, 0.8)
        s:SetBackdropBorderColor(0.204, 0.298, 0.357, 1)
        s:SetFrameLevel(area:GetFrameLevel() + 1)
        s.kind, s.i = kind, i
        if kind == "foundation" then
            local t = s:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
            t:SetPoint("CENTER")
            t:SetText("A")
        elseif kind == "stock" then
            local t = s:CreateTexture(nil, "ARTWORK")
            t:SetSize(24, 24)
            t:SetPoint("CENTER")
            t:SetTexture("Interface\\Buttons\\UI-RefreshButton")
            t:SetAlpha(0.6)
        end
        s:SetScript("OnClick", function(self)
            local pile
            if self.kind == "stock" then pile = stock
            elseif self.kind == "waste" then pile = waste
            elseif self.kind == "foundation" then pile = foundations[self.i]
            else pile = tableau[self.i] end
            clickPile(pile, nil)
        end)
        slots[#slots + 1] = s
    end
    makeSlot("stock")
    makeSlot("waste")
    for f = 1, 4 do makeSlot("foundation", f) end
    for t = 1, 7 do makeSlot("tableau", t) end

    for i = 1, 52 do
        local b = CreateFrame("Button", nil, area, "BackdropTemplate")
        b:SetSize(CARD_W, CARD_H)
        b:SetBackdrop(MG.BACKDROP)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.corner = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.corner:SetPoint("TOPLEFT", 4, -4)
        b.center = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        b.center:SetPoint("CENTER", 0, -6)
        b.back = b:CreateTexture(nil, "ARTWORK")
        b.back:SetPoint("TOPLEFT", 5, -5)
        b.back:SetPoint("BOTTOMRIGHT", -5, 5)
        b.back:SetTexture(MG.icon)
        b.back:SetAlpha(0.35)
        b:SetScript("OnClick", onCardClick)
        b:Hide()
        buttons[i] = b
    end
end

function Game.Start(level)
    drawCount = (level == "draw3") and 3 or 1
    local deck = {}
    for suit = 1, 4 do
        for rank = 1, 13 do deck[#deck + 1] = { suit = suit, rank = rank, up = false } end
    end
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    stock, waste = {}, {}
    foundations = { {}, {}, {}, {} }
    tableau = {}
    for t = 1, 7 do
        tableau[t] = {}
        for _ = 1, t do tableau[t][#tableau[t] + 1] = table.remove(deck) end
        tableau[t][#tableau[t]].up = true
    end
    for i = #deck, 1, -1 do stock[#stock + 1] = deck[i] end
    moves, selected = 0, nil
    render()
end

function Game.OnSelect()
    local extra = MG.ExtraButton()
    if extra then
        extra:SetLabel(T("autoFinish"))
        extra:SetScript("OnClick", autoFinish)
    end
end

function Game.Status()
    local extra = MG.ExtraButton()
    if extra and Game.area and Game.area:IsShown() then extra:SetShown(canAutoFinish()) end
    return string.format(T("st_moves"), moves or 0, MG.Clock(MG.Elapsed()))
end

-- saved table (for /reload or logout in the middle of a game)
local function packPile(pile)
    local out = {}
    for i, card in ipairs(pile) do out[i] = { card.suit, card.rank, card.up and 1 or 0 } end
    return out
end

local function unpackPile(list)
    local pile = {}
    for i, c in ipairs(list or {}) do pile[i] = { suit = c[1], rank = c[2], up = c[3] == 1 } end
    return pile
end

function Game.Save()
    local t = { stock = packPile(stock), waste = packPile(waste), foundations = {}, tableau = {}, moves = moves }
    for i = 1, 4 do t.foundations[i] = packPile(foundations[i]) end
    for i = 1, 7 do t.tableau[i] = packPile(tableau[i]) end
    return t
end

function Game.Load(t, level)
    Game.Start(level)
    stock, waste = unpackPile(t.stock), unpackPile(t.waste)
    for i = 1, 4 do foundations[i] = unpackPile(t.foundations and t.foundations[i]) end
    for i = 1, 7 do tableau[i] = unpackPile(t.tableau and t.tableau[i]) end
    moves, selected = tonumber(t.moves) or 0, nil
    render()
end

MG.Register(Game)
