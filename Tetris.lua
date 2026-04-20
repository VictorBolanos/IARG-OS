---------------------------------------------------------------------------
-- Tetris.lua -- Classic Tetris for IARG-OS
-- Launch with: game tetris
-- Controls: Left/Right=move  Up=rotate  Down=soft drop  Space=hard drop
--           P=pause  Esc=exit
---------------------------------------------------------------------------

-- BD, Utils are globals loaded by IARG-OS.lua

Tetris = {}

---------------------------------------------------------------------------
-- Layout constants

local BLOCK     = 7       -- px per cell
local BOARD_W   = 10      -- columns
local BOARD_H   = 20      -- rows

-- Board position (centered horizontally, topbar-aware)
local BX        = 133     -- board left pixel
local BY        = 16      -- board top pixel (BD.CONTENT_Y + 4)

-- Sidebar
local SX        = BX + BOARD_W * BLOCK + 6   -- 209

---------------------------------------------------------------------------
-- Tetrominoes: each piece = list of {row,col} offsets from pivot
-- Rotations stored as separate tables (all 4 rotations precomputed)

local PIECES = {
    -- I
    {
        {{0,0},{0,1},{0,2},{0,3}},
        {{0,2},{1,2},{2,2},{3,2}},
        {{2,0},{2,1},{2,2},{2,3}},
        {{0,1},{1,1},{2,1},{3,1}},
        color = 1
    },
    -- O
    {
        {{0,0},{0,1},{1,0},{1,1}},
        {{0,0},{0,1},{1,0},{1,1}},
        {{0,0},{0,1},{1,0},{1,1}},
        {{0,0},{0,1},{1,0},{1,1}},
        color = 2
    },
    -- T
    {
        {{0,1},{1,0},{1,1},{1,2}},
        {{0,1},{1,1},{1,2},{2,1}},
        {{1,0},{1,1},{1,2},{2,1}},
        {{0,1},{1,0},{1,1},{2,1}},
        color = 3
    },
    -- S
    {
        {{0,1},{0,2},{1,0},{1,1}},
        {{0,1},{1,1},{1,2},{2,2}},
        {{1,1},{1,2},{2,0},{2,1}},
        {{0,0},{1,0},{1,1},{2,1}},
        color = 4
    },
    -- Z
    {
        {{0,0},{0,1},{1,1},{1,2}},
        {{0,2},{1,1},{1,2},{2,1}},
        {{1,0},{1,1},{2,1},{2,2}},
        {{0,1},{1,0},{1,1},{2,0}},
        color = 5
    },
    -- J
    {
        {{0,0},{1,0},{1,1},{1,2}},
        {{0,1},{0,2},{1,1},{2,1}},
        {{1,0},{1,1},{1,2},{2,2}},
        {{0,1},{1,1},{2,0},{2,1}},
        color = 6
    },
    -- L
    {
        {{0,2},{1,0},{1,1},{1,2}},
        {{0,1},{1,1},{2,1},{2,2}},
        {{1,0},{1,1},{1,2},{2,0}},
        {{0,0},{0,1},{1,1},{2,1}},
        color = 7
    },
}

-- Piece colors (index 1-7) -- will be set as Color() in Init
local COLORS = {}
local COLOR_DATA = {
    {0,   220, 220},  -- 1 I  cyan
    {220, 220, 0  },  -- 2 O  yellow
    {180, 0,   220},  -- 3 T  purple
    {0,   220, 0  },  -- 4 S  green
    {220, 0,   0  },  -- 5 Z  red
    {0,   0,   220},  -- 6 J  blue
    {220, 120, 0  },  -- 7 L  orange
}

---------------------------------------------------------------------------
-- State

local _video    = nil
local _font     = nil
local _theme    = nil
local _onClose  = nil

local board     = {}    -- [row][col] = color index (0=empty)
local curPiece  = nil   -- {type, rot, row, col}
local nextPiece = nil
local holdPiece = nil
local canHold   = true

local score     = 0
local lines     = 0
local level     = 1
local gameOver  = false
local paused    = false

local dropTimer    = 0
local dropInterval = 48   -- ticks between auto-drops (decreases with level)

local lockTimer    = 0
local lockDelay    = 30   -- ticks before piece locks after landing

---------------------------------------------------------------------------
-- Local tp

local function tp(x, y, txt, col)
    if not _font or not _video then return end
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        _video:DrawSprite(vec2(x+(i-1)*BD.CHAR_W, y), _font,
            ch:byte()%32, math.floor(ch:byte()/32), col, color.clear)
    end
end

---------------------------------------------------------------------------
-- Board helpers

local function newBoard()
    local b = {}
    for r = 1, BOARD_H do
        b[r] = {}
        for c = 1, BOARD_W do b[r][c] = 0 end
    end
    return b
end

local function getCells(piece)
    local t    = PIECES[piece.type]
    local rot  = t[piece.rot]
    local cells = {}
    for _, off in ipairs(rot) do
        table.insert(cells, {r = piece.row + off[1], c = piece.col + off[2]})
    end
    return cells
end

local function isValid(piece, dr, dc, drot)
    local p = {
        type = piece.type,
        rot  = drot or piece.rot,
        row  = piece.row + (dr or 0),
        col  = piece.col + (dc or 0),
    }
    for _, cell in ipairs(getCells(p)) do
        if cell.c < 1 or cell.c > BOARD_W then return false end
        if cell.r > BOARD_H then return false end
        if cell.r >= 1 and board[cell.r][cell.c] ~= 0 then return false end
    end
    return true
end

local function lockPiece()
    local col = PIECES[curPiece.type].color
    for _, cell in ipairs(getCells(curPiece)) do
        if cell.r >= 1 then
            board[cell.r][cell.c] = col
        else
            gameOver = true
            return
        end
    end
    -- Clear full lines
    local cleared = 0
    local r = BOARD_H
    while r >= 1 do
        local full = true
        for c = 1, BOARD_W do
            if board[r][c] == 0 then full = false; break end
        end
        if full then
            cleared = cleared + 1
            table.remove(board, r)
            local newRow = {}
            for c = 1, BOARD_W do newRow[c] = 0 end
            table.insert(board, 1, newRow)
        else
            r = r - 1
        end
    end
    if cleared > 0 then
        local pts = {0, 100, 300, 500, 800}
        score = score + (pts[cleared+1] or 800) * level
        lines = lines + cleared
        level = math.floor(lines / 10) + 1
        dropInterval = math.max(6, 48 - (level-1)*4)
    end
    curPiece = nextPiece
    nextPiece = {type=math.random(#PIECES), rot=1, row=0, col=4}
    canHold  = true
    dropTimer = 0
    lockTimer = 0
    if not isValid(curPiece, 0, 0) then gameOver = true end
end

local function spawnPiece()
    curPiece  = {type=math.random(#PIECES), rot=1, row=0, col=4}
    nextPiece = {type=math.random(#PIECES), rot=1, row=0, col=4}
end

local function getGhostRow()
    local dr = 0
    while isValid(curPiece, dr+1, 0) do dr = dr + 1 end
    return dr
end

local function hardDrop()
    local dr = 0
    while isValid(curPiece, dr+1, 0) do dr = dr + 1 end
    score = score + dr * 2
    curPiece.row = curPiece.row + dr
    lockPiece()
end

local function rotate(dir)
    local t    = PIECES[curPiece.type]
    local nrot = ((curPiece.rot - 1 + dir) % 4) + 1
    -- Try basic rotation, then wall kicks
    local kicks = {{0,0},{0,-1},{0,1},{0,-2},{0,2}}
    for _, k in ipairs(kicks) do
        local p = {type=curPiece.type, rot=nrot,
                   row=curPiece.row+k[1], col=curPiece.col+k[2]}
        if isValid(p, 0, 0) then
            curPiece.rot = nrot
            curPiece.row = p.row
            curPiece.col = p.col
            lockTimer = 0
            return
        end
    end
end

---------------------------------------------------------------------------
-- Draw helpers

local function drawBlock(r, c, col)
    local px = BX + (c-1) * BLOCK
    local py = BY + (r-1) * BLOCK
    _video:FillRect(vec2(px, py), vec2(px+BLOCK-2, py+BLOCK-2), col)
end

local function drawSmallBlock(px, py, col)
    _video:FillRect(vec2(px, py), vec2(px+4, py+4), col)
end

---------------------------------------------------------------------------
-- Init

function Tetris:Init(video, font, theme, onClose)
    _video   = video
    _font    = font
    _theme   = theme
    _onClose = onClose

    -- Build colors
    COLORS = {}
    for i, d in ipairs(COLOR_DATA) do
        COLORS[i] = Color(d[1], d[2], d[3])
    end

    board     = newBoard()
    score     = 0
    lines     = 0
    level     = 1
    gameOver  = false
    paused    = false
    holdPiece = nil
    canHold   = true
    dropTimer    = 0
    lockTimer    = 0
    dropInterval = 48

    math.randomseed(1337)
    spawnPiece()
end

---------------------------------------------------------------------------
-- HandleKey

function Tetris:HandleKey(name, shift, ctrl)
    if name == "Escape" then
        if _onClose then _onClose() end
        return
    end
    if name == "P" or name == "Return" then
        if not gameOver then paused = not paused end
        return
    end
    if gameOver then
        -- Any key restarts
        board     = newBoard()
        score     = 0
        lines     = 0
        level     = 1
        gameOver  = false
        paused    = false
        holdPiece = nil
        canHold   = true
        dropTimer    = 0
        lockTimer    = 0
        dropInterval = 48
        spawnPiece()
        return
    end
    if paused then return end

    if name == "LeftArrow" then
        if isValid(curPiece, 0, -1) then
            curPiece.col = curPiece.col - 1
            if not isValid(curPiece, 1, 0) then lockTimer = 0 end
        end
    elseif name == "RightArrow" then
        if isValid(curPiece, 0, 1) then
            curPiece.col = curPiece.col + 1
            if not isValid(curPiece, 1, 0) then lockTimer = 0 end
        end
    elseif name == "UpArrow" then
        rotate(1)
    elseif name == "Z" then
        rotate(-1)
    elseif name == "DownArrow" then
        if isValid(curPiece, 1, 0) then
            curPiece.row = curPiece.row + 1
            score = score + 1
            dropTimer = 0
        end
    elseif name == "Space" then
        hardDrop()
    elseif name == "C" or name == "LeftShift" then
        -- Hold piece
        if canHold then
            canHold = false
            if holdPiece then
                local tmp = holdPiece
                holdPiece = {type=curPiece.type, rot=1}
                curPiece  = {type=tmp.type, rot=1, row=0, col=4}
            else
                holdPiece = {type=curPiece.type, rot=1}
                curPiece  = nextPiece
                nextPiece = {type=math.random(#PIECES), rot=1, row=0, col=4}
            end
            if not isValid(curPiece, 0, 0) then gameOver = true end
            dropTimer = 0
        end
    end
end

---------------------------------------------------------------------------
-- Update

function Tetris:Update()
    if gameOver or paused then return end

    dropTimer = dropTimer + 1

    local grounded = not isValid(curPiece, 1, 0)

    if grounded then
        lockTimer = lockTimer + 1
        if lockTimer >= lockDelay then
            lockPiece()
            lockTimer = 0
        end
    else
        lockTimer = 0
        if dropTimer >= dropInterval then
            curPiece.row = curPiece.row + 1
            dropTimer = 0
        end
    end
end

---------------------------------------------------------------------------
-- Draw

function Tetris:Draw()
    if not _video or not _theme then return end

    local sw = _video.Width
    local sh = _video.Height

    -- Background
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(sw-1, sh-1), _theme.bg)

    -- Board border
    _video:DrawRect(
        vec2(BX-1, BY-1),
        vec2(BX + BOARD_W*BLOCK, BY + BOARD_H*BLOCK),
        _theme.dim)

    -- Board grid (subtle)
    for r = 1, BOARD_H do
        for c = 1, BOARD_W do
            local val = board[r][c]
            if val ~= 0 then
                drawBlock(r, c, COLORS[val])
                -- Highlight edge
                local px = BX + (c-1)*BLOCK
                local py = BY + (r-1)*BLOCK
                _video:DrawLine(vec2(px, py), vec2(px+BLOCK-2, py), Color(255,255,255))
            else
                -- Empty cell background
                local px = BX + (c-1)*BLOCK
                local py = BY + (r-1)*BLOCK
                _video:FillRect(vec2(px, py), vec2(px+BLOCK-2, py+BLOCK-2), Color(18,18,32))
            end
        end
    end

    -- Ghost piece
    if not gameOver and not paused then
        local ghostDr = getGhostRow()
        if ghostDr > 0 then
            local ghost = {type=curPiece.type, rot=curPiece.rot,
                           row=curPiece.row+ghostDr, col=curPiece.col}
            for _, cell in ipairs(getCells(ghost)) do
                if cell.r >= 1 and cell.r <= BOARD_H then
                    local px = BX + (cell.c-1)*BLOCK
                    local py = BY + (cell.r-1)*BLOCK
                    _video:DrawRect(vec2(px,py), vec2(px+BLOCK-2,py+BLOCK-2), _theme.dim)
                end
            end
        end
    end

    -- Current piece
    if not gameOver then
        local col = COLORS[PIECES[curPiece.type].color]
        for _, cell in ipairs(getCells(curPiece)) do
            if cell.r >= 1 then
                drawBlock(cell.r, cell.c, col)
                local px = BX + (cell.c-1)*BLOCK
                local py = BY + (cell.r-1)*BLOCK
                _video:DrawLine(vec2(px,py), vec2(px+BLOCK-2,py), Color(255,255,255))
            end
        end
    end

    -- ── Sidebar ──────────────────────────────────────────────────────────

    local ty = BY  -- current sidebar Y

    -- Score
    tp(SX, ty, "SCORE", _theme.dim)
    tp(SX, ty+8, tostring(score), _theme.text)
    ty = ty + 20

    -- Lines
    tp(SX, ty, "LINES", _theme.dim)
    tp(SX, ty+8, tostring(lines), _theme.text)
    ty = ty + 20

    -- Level
    tp(SX, ty, "LEVEL", _theme.dim)
    tp(SX, ty+8, tostring(level), _theme.text)
    ty = ty + 24

    -- Next piece preview
    tp(SX, ty, "NEXT", _theme.dim)
    ty = ty + 10
    if nextPiece then
        local t   = PIECES[nextPiece.type]
        local rot = t[1]
        local col = COLORS[t.color]
        for _, off in ipairs(rot) do
            drawSmallBlock(SX + off[2]*6, ty + off[1]*6, col)
        end
    end
    ty = ty + 36

    -- Hold piece
    tp(SX, ty, "HOLD", _theme.dim)
    ty = ty + 10
    if holdPiece then
        local t   = PIECES[holdPiece.type]
        local rot = t[1]
        local col = canHold and COLORS[t.color] or _theme.dim
        for _, off in ipairs(rot) do
            drawSmallBlock(SX + off[2]*6, ty + off[1]*6, col)
        end
    end
    ty = ty + 36

    -- Controls hint
    tp(SX, ty,    "CTRL", _theme.dim)
    tp(SX, ty+8,  "<=  move", _theme.dim)
    tp(SX, ty+16, "^  rotate", _theme.dim)
    tp(SX, ty+24, "v  drop", _theme.dim)
    tp(SX, ty+32, "SPC hard", _theme.dim)
    tp(SX, ty+40, "C  hold", _theme.dim)
    tp(SX, ty+48, "P  pause", _theme.dim)

    -- Game over overlay
    if gameOver then
        local ox = BX + 2
        local oy = BY + BOARD_H*BLOCK//2 - 16
        _video:FillRect(vec2(ox-2, oy-2), vec2(ox + 64, oy+24), Color(8,8,18))
        _video:DrawRect(vec2(ox-2, oy-2), vec2(ox + 64, oy+24), _theme.error)
        tp(ox, oy,    "GAME OVER", _theme.error)
        tp(ox, oy+10, "any key...", _theme.dim)
    end

    -- Paused overlay
    if paused then
        local ox = BX + 8
        local oy = BY + BOARD_H*BLOCK//2 - 6
        _video:FillRect(vec2(ox-2, oy-2), vec2(ox + 52, oy+14), Color(8,8,18))
        _video:DrawRect(vec2(ox-2, oy-2), vec2(ox + 52, oy+14), _theme.prompt)
        tp(ox, oy, "  PAUSED", _theme.prompt)
    end
end

---------------------------------------------------------------------------

return Tetris