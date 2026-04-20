---------------------------------------------------------------------------
-- Chess.lua -- Classic Chess for IARG-OS
-- Launch with: game chess
-- Controls: Click to select/move, 1-3 for difficulty, N for new game, Esc to exit
---------------------------------------------------------------------------

-- BD, Utils are globals loaded by IARG-OS.lua

Chess = {}

---------------------------------------------------------------------------
-- Board and piece constants

local BOARD_SIZE = 8
local CELL_SIZE = 18
local BOARD_X = 90
local BOARD_Y = 30

-- Piece types
local EMPTY = 0
local PAWN = 1
local KNIGHT = 2
local BISHOP = 3
local ROOK = 4
local QUEEN = 5
local KING = 6

-- Colors
local WHITE = 1
local BLACK = 2

-- Chess piece spritesheet indices (sprChess.png)
-- Columns: 0-5 black pieces, 6-11 white pieces
-- Order: Pawn, Knight, Bishop, Rook, Queen, King
local PIECE_SPRITES = {
    [BLACK] = {
        [PAWN] = 0, [KNIGHT] = 1, [BISHOP] = 2, 
        [ROOK] = 3, [QUEEN] = 4, [KING] = 5
    },
    [WHITE] = {
        [PAWN] = 6, [KNIGHT] = 7, [BISHOP] = 8, 
        [ROOK] = 9, [QUEEN] = 10, [KING] = 11
    }
}

---------------------------------------------------------------------------
-- Game state

local _video = nil
local _font = nil
local _theme = nil
local _onClose = nil
local _pieceSprites = nil -- sprChess.png

local board = {} -- 8x8 board: {color, type}
local currentTurn = WHITE
local selectedPiece = nil -- {row, col}
local validMoves = {}
local gameOver = false
local winner = nil
local difficulty = 2 -- 1=Easy, 2=Medium, 3=Hard
local moveHistory = {}
local inCheck = {white = false, black = false}
local lastMove = nil -- {from, to}

---------------------------------------------------------------------------
-- Board initialization

local function initializeBoard()
    -- Clear board
    for row = 1, BOARD_SIZE do
        board[row] = {}
        for col = 1, BOARD_SIZE do
            board[row][col] = {color = EMPTY, type = EMPTY}
        end
    end
    
    -- Place pawns
    for col = 1, BOARD_SIZE do
        board[2][col] = {color = WHITE, type = PAWN}
        board[7][col] = {color = BLACK, type = PAWN}
    end
    
    -- Place pieces
    -- White back rank
    board[1][1] = {color = WHITE, type = ROOK}
    board[1][2] = {color = WHITE, type = KNIGHT}
    board[1][3] = {color = WHITE, type = BISHOP}
    board[1][4] = {color = WHITE, type = QUEEN}
    board[1][5] = {color = WHITE, type = KING}
    board[1][6] = {color = WHITE, type = BISHOP}
    board[1][7] = {color = WHITE, type = KNIGHT}
    board[1][8] = {color = WHITE, type = ROOK}
    
    -- Black back rank
    board[8][1] = {color = BLACK, type = ROOK}
    board[8][2] = {color = BLACK, type = KNIGHT}
    board[8][3] = {color = BLACK, type = BISHOP}
    board[8][4] = {color = BLACK, type = QUEEN}
    board[8][5] = {color = BLACK, type = KING}
    board[8][6] = {color = BLACK, type = BISHOP}
    board[8][7] = {color = BLACK, type = KNIGHT}
    board[8][8] = {color = BLACK, type = ROOK}
end

---------------------------------------------------------------------------
-- Utility functions

local function tp(x, y, txt, col)
    if not _font or not _video then return end
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        _video:DrawSprite(vec2(x+(i-1)*BD.CHAR_W, y), _font,
            ch:byte()%32, math.floor(ch:byte()/32), col, color.clear)
    end
end

local function isValidSquare(row, col)
    return row >= 1 and row <= BOARD_SIZE and col >= 1 and col <= BOARD_SIZE
end

local function getPiece(row, col)
    if not isValidSquare(row, col) then return nil end
    return board[row][col]
end

local function isPieceOwnedByCurrentPlayer(piece)
    return piece and piece.color == currentTurn
end

local function isOpponentPiece(piece)
    return piece and piece.color ~= currentTurn and piece.color ~= EMPTY
end

---------------------------------------------------------------------------
-- Movement validation

local function getPawnMoves(row, col, piece)
    local moves = {}
    local direction = piece.color == WHITE and 1 or -1
    local startRow = piece.color == WHITE and 2 or 7
    
    -- Forward move
    local newRow = row + direction
    if isValidSquare(newRow, col) then
        local target = getPiece(newRow, col)
        if target.type == EMPTY then
            table.insert(moves, {row = newRow, col = col})
            
            -- Double move from start
            if row == startRow then
                newRow = row + 2 * direction
                if isValidSquare(newRow, col) then
                    target = getPiece(newRow, col)
                    if target.type == EMPTY then
                        table.insert(moves, {row = newRow, col = col})
                    end
                end
            end
        end
    end
    
    -- Captures
    for dc = -1, 1, 2 do
        newRow = row + direction
        local newCol = col + dc
        if isValidSquare(newRow, newCol) then
            local target = getPiece(newRow, newCol)
            if isOpponentPiece(target) then
                table.insert(moves, {row = newRow, col = newCol})
            end
        end
    end
    
    return moves
end

local function getKnightMoves(row, col, piece)
    local moves = {}
    local knightMoves = {
        {-2, -1}, {-2, 1}, {-1, -2}, {-1, 2},
        {1, -2}, {1, 2}, {2, -1}, {2, 1}
    }
    
    for _, move in ipairs(knightMoves) do
        local newRow = row + move[1]
        local newCol = col + move[2]
        if isValidSquare(newRow, newCol) then
            local target = getPiece(newRow, newCol)
            if target.type == EMPTY or isOpponentPiece(target) then
                table.insert(moves, {row = newRow, col = newCol})
            end
        end
    end
    
    return moves
end

local function getSlidingMoves(row, col, piece, directions)
    local moves = {}
    
    for _, dir in ipairs(directions) do
        local newRow = row + dir[1]
        local newCol = col + dir[2]
        
        while isValidSquare(newRow, newCol) do
            local target = getPiece(newRow, newCol)
            if target.type == EMPTY then
                table.insert(moves, {row = newRow, col = newCol})
            elseif isOpponentPiece(target) then
                table.insert(moves, {row = newRow, col = newCol})
                break
            else
                break
            end
            newRow = newRow + dir[1]
            newCol = newCol + dir[2]
        end
    end
    
    return moves
end

local function getBishopMoves(row, col, piece)
    local directions = {{-1, -1}, {-1, 1}, {1, -1}, {1, 1}}
    return getSlidingMoves(row, col, piece, directions)
end

local function getRookMoves(row, col, piece)
    local directions = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
    return getSlidingMoves(row, col, piece, directions)
end

local function getQueenMoves(row, col, piece)
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},
        {0, -1}, {0, 1},
        {1, -1}, {1, 0}, {1, 1}
    }
    return getSlidingMoves(row, col, piece, directions)
end

local function getKingMoves(row, col, piece)
    local moves = {}
    
    for dr = -1, 1 do
        for dc = -1, 1 do
            if not (dr == 0 and dc == 0) then
                local newRow = row + dr
                local newCol = col + dc
                if isValidSquare(newRow, newCol) then
                    local target = getPiece(newRow, newCol)
                    if target.type == EMPTY or isOpponentPiece(target) then
                        table.insert(moves, {row = newRow, col = newCol})
                    end
                end
            end
        end
    end
    
    return moves
end

local function getValidMoves(row, col)
    local piece = getPiece(row, col)
    if not piece or piece.type == EMPTY then return {} end
    
    if piece.type == PAWN then
        return getPawnMoves(row, col, piece)
    elseif piece.type == KNIGHT then
        return getKnightMoves(row, col, piece)
    elseif piece.type == BISHOP then
        return getBishopMoves(row, col, piece)
    elseif piece.type == ROOK then
        return getRookMoves(row, col, piece)
    elseif piece.type == QUEEN then
        return getQueenMoves(row, col, piece)
    elseif piece.type == KING then
        return getKingMoves(row, col, piece)
    end
    
    return {}
end

---------------------------------------------------------------------------
-- Check and checkmate detection

local function findKing(color)
    for row = 1, BOARD_SIZE do
        for col = 1, BOARD_SIZE do
            local piece = getPiece(row, col)
            if piece.type == KING and piece.color == color then
                return {row = row, col = col}
            end
        end
    end
    return nil
end

local function isSquareUnderAttack(row, col, byColor)
    -- Temporarily switch turn to see opponent's moves
    local originalTurn = currentTurn
    currentTurn = byColor
    
    for r = 1, BOARD_SIZE do
        for c = 1, BOARD_SIZE do
            local piece = getPiece(r, c)
            if piece.color == byColor and piece.type ~= EMPTY then
                local moves = getValidMoves(r, c)
                for _, move in ipairs(moves) do
                    if move.row == row and move.col == col then
                        currentTurn = originalTurn
                        return true
                    end
                end
            end
        end
    end
    
    currentTurn = originalTurn
    return false
end

local function isInCheck(color)
    local kingPos = findKing(color)
    if not kingPos then return false end
    
    local opponentColor = color == WHITE and BLACK or WHITE
    return isSquareUnderAttack(kingPos.row, kingPos.col, opponentColor)
end

local function wouldBeInCheck(fromRow, fromCol, toRow, toCol)
    -- Simulate move
    local originalPiece = board[toRow][toCol]
    board[toRow][toCol] = board[fromRow][fromCol]
    board[fromRow][fromCol] = {color = EMPTY, type = EMPTY}
    
    local check = isInCheck(currentTurn)
    
    -- Restore board
    board[fromRow][fromCol] = board[toRow][toCol]
    board[toRow][toCol] = originalPiece
    
    return check
end

local function filterLegalMoves(moves, fromRow, fromCol)
    local legalMoves = {}
    for _, move in ipairs(moves) do
        if not wouldBeInCheck(fromRow, fromCol, move.row, move.col) then
            table.insert(legalMoves, move)
        end
    end
    return legalMoves
end

---------------------------------------------------------------------------
-- AI System

local function evaluateBoard()
    local score = 0
    local pieceValues = {
        [PAWN] = 100, [KNIGHT] = 320, [BISHOP] = 330,
        [ROOK] = 500, [QUEEN] = 900, [KING] = 20000
    }
    
    for row = 1, BOARD_SIZE do
        for col = 1, BOARD_SIZE do
            local piece = getPiece(row, col)
            if piece.type ~= EMPTY then
                local value = pieceValues[piece.type]
                if piece.color == BLACK then
                    score = score - value
                else
                    score = score + value
                end
            end
        end
    end
    
    return score
end

local function makeAIMove()
    local bestMove = nil
    local bestScore = -math.huge
    
    -- Find all possible moves for AI
    local allMoves = {}
    for row = 1, BOARD_SIZE do
        for col = 1, BOARD_SIZE do
            local piece = getPiece(row, col)
            if piece.color == currentTurn and piece.type ~= EMPTY then
                local moves = getValidMoves(row, col)
                local legalMoves = filterLegalMoves(moves, row, col)
                for _, move in ipairs(legalMoves) do
                    table.insert(allMoves, {
                        from = {row = row, col = col},
                        to = move,
                        score = math.random(1000) -- For tie-breaking
                    })
                end
            end
        end
    end
    
    if #allMoves == 0 then return false end
    
    if difficulty == 1 then
        -- Easy: Random move with slight preference for captures
        for _, move in ipairs(allMoves) do
            local targetPiece = getPiece(move.to.row, move.to.col)
            if targetPiece.type ~= EMPTY then
                move.score = move.score + 500
            end
        end
        table.sort(allMoves, function(a, b) return a.score > b.score end)
        bestMove = allMoves[1]
        
    elseif difficulty == 2 then
        -- Medium: Simple evaluation
        for _, move in ipairs(allMoves) do
            local targetPiece = getPiece(move.to.row, move.to.col)
            local pieceValues = {
                [PAWN] = 100, [KNIGHT] = 320, [BISHOP] = 330,
                [ROOK] = 500, [QUEEN] = 900, [KING] = 20000
            }
            
            move.score = evaluateBoard()
            if targetPiece.type ~= EMPTY then
                move.score = move.score + pieceValues[targetPiece.type]
            end
        end
        table.sort(allMoves, function(a, b) return a.score > b.score end)
        bestMove = allMoves[1]
        
    else
        -- Hard: Look ahead one move
        for _, move in ipairs(allMoves) do
            -- Simulate move
            local originalPiece = board[move.to.row][move.to.col]
            board[move.to.row][move.to.col] = board[move.from.row][move.from.col]
            board[move.from.row][move.from.col] = {color = EMPTY, type = EMPTY}
            
            local opponentColor = currentTurn == WHITE and BLACK or WHITE
            local inCheckAfter = isInCheck(opponentColor)
            
            move.score = evaluateBoard()
            if inCheckAfter then
                move.score = move.score + 1000
            end
            
            -- Restore board
            board[move.from.row][move.from.col] = board[move.to.row][move.to.col]
            board[move.to.row][move.to.col] = originalPiece
        end
        table.sort(allMoves, function(a, b) return a.score > b.score end)
        bestMove = allMoves[1]
    end
    
    if bestMove then
        -- Execute the move
        board[bestMove.to.row][bestMove.to.col] = board[bestMove.from.row][bestMove.from.col]
        board[bestMove.from.row][bestMove.from.col] = {color = EMPTY, type = EMPTY}
        
        lastMove = {from = bestMove.from, to = bestMove.to}
        table.insert(moveHistory, bestMove)
        
        currentTurn = currentTurn == WHITE and BLACK or WHITE
        return true
    end
    
    return false
end

---------------------------------------------------------------------------
-- Drawing functions

local function drawBoard()
    for row = 1, BOARD_SIZE do
        for col = 1, BOARD_SIZE do
            local x = BOARD_X + (col - 1) * CELL_SIZE
            local y = BOARD_Y + (row - 1) * CELL_SIZE
            
            -- Alternate colors
            if (row + col) % 2 == 0 then
                _video:FillRect(vec2(x, y), vec2(x + CELL_SIZE - 1, y + CELL_SIZE - 1), Color(240, 217, 181))
            else
                _video:FillRect(vec2(x, y), vec2(x + CELL_SIZE - 1, y + CELL_SIZE - 1), Color(181, 136, 99))
            end
            
            -- Highlight last move
            if lastMove then
                if (lastMove.from.row == row and lastMove.from.col == col) or
                   (lastMove.to.row == row and lastMove.to.col == col) then
                    _video:FillRect(vec2(x, y), vec2(x + CELL_SIZE - 1, y + CELL_SIZE - 1), Color(255, 255, 0))
                end
            end
            
            -- Highlight selected piece
            if selectedPiece and selectedPiece.row == row and selectedPiece.col == col then
                _video:DrawRect(vec2(x, y), vec2(x + CELL_SIZE - 1, y + CELL_SIZE - 1), Color(0, 255, 0))
            end
            
            -- Highlight valid moves
            for _, move in ipairs(validMoves) do
                if move.row == row and move.col == col then
                    _video:FillRect(vec2(x + 4, y + 4), vec2(x + CELL_SIZE - 5, y + CELL_SIZE - 5), Color(0, 200, 0))
                end
            end
            
            -- Draw pieces
            local piece = getPiece(row, col)
            if piece.type ~= EMPTY and _pieceSprites then
                local spriteIndex = PIECE_SPRITES[piece.color][piece.type]
                _video:DrawSprite(
                    vec2(x + 1, y + 1), 
                    _pieceSprites,
                    spriteIndex, 0, -- column 0, row 0 (single row spritesheet)
                    Color(255, 255, 255),
                    color.clear
                )
            end
        end
    end
    
    -- Draw board coordinates
    for i = 1, BOARD_SIZE do
        -- Row numbers
        tp(BOARD_X - 15, BOARD_Y + (i - 1) * CELL_SIZE + 6, tostring(9 - i), _theme.text)
        -- Column letters
        tp(BOARD_X + (i - 1) * CELL_SIZE + 6, BOARD_Y + BOARD_SIZE * CELL_SIZE + 2, string.char(96 + i), _theme.text)
    end
end

local function drawUI()
    -- Title
    tp(BOARD_X, 10, "CHESS", _theme.success)
    
    -- Current turn
    local turnText = currentTurn == WHITE and "White's Turn" or "Black's Turn"
    tp(BOARD_X + 100, 10, turnText, _theme.text)
    
    -- Difficulty
    local diffText = "Difficulty: " .. (difficulty == 1 and "Easy" or difficulty == 2 and "Medium" or "Hard")
    tp(BOARD_X, 25, diffText, _theme.dim)
    
    -- Check warning
    if inCheck.white or inCheck.black then
        local checkText = (currentTurn == WHITE and inCheck.white) or (currentTurn == BLACK and inCheck.black)
        if checkText then
            tp(BOARD_X + 200, 10, "CHECK!", _theme.error)
        end
    end
    
    -- Game over
    if gameOver then
        local winnerText = winner == WHITE and "White Wins!" or "Black Wins!"
        tp(BOARD_X + 150, 10, winnerText, _theme.success)
        tp(BOARD_X + 100, 25, "Press N for new game", _theme.dim)
    end
    
    -- Controls and Instructions
    tp(10, BOARD_Y + 90, "HOW TO PLAY:", _theme.success)
    tp(10, BOARD_Y + 100, "You play WHITE", _theme.text)
    tp(10, BOARD_Y + 110, "Click piece to select", _theme.dim)
    tp(10, BOARD_Y + 120, "Click square to move", _theme.dim)
    tp(10, BOARD_Y + 130, "Green = valid moves", _theme.dim)
    tp(10, BOARD_Y + 140, "1-3: Difficulty", _theme.text)
    tp(10, BOARD_Y + 150, "N: New Game", _theme.text)
    tp(10, BOARD_Y + 160, "Esc: Exit", _theme.text)
end

---------------------------------------------------------------------------
-- Game logic

local function updateGameState()
    -- Update check status
    inCheck.white = isInCheck(WHITE)
    inCheck.black = isInCheck(BLACK)
    
    -- Check for checkmate or stalemate
    local hasValidMoves = false
    for row = 1, BOARD_SIZE do
        for col = 1, BOARD_SIZE do
            local piece = getPiece(row, col)
            if piece.color == currentTurn and piece.type ~= EMPTY then
                local moves = getValidMoves(row, col)
                local legalMoves = filterLegalMoves(moves, row, col)
                if #legalMoves > 0 then
                    hasValidMoves = true
                    break
                end
            end
        end
        if hasValidMoves then break end
    end
    
    if not hasValidMoves then
        gameOver = true
        if (currentTurn == WHITE and inCheck.white) or (currentTurn == BLACK and inCheck.black) then
            winner = currentTurn == WHITE and BLACK or WHITE
        else
            winner = nil -- Stalemate
        end
    end
end

local function handleSquareClick(row, col)
    if gameOver then return end
    
    if selectedPiece then
        -- Try to move
        local validMove = false
        for _, move in ipairs(validMoves) do
            if move.row == row and move.col == col then
                validMove = true
                break
            end
        end
        
        if validMove then
            -- Make move
            board[row][col] = board[selectedPiece.row][selectedPiece.col]
            board[selectedPiece.row][selectedPiece.col] = {color = EMPTY, type = EMPTY}
            
            lastMove = {from = selectedPiece, to = {row = row, col = col}}
            table.insert(moveHistory, lastMove)
            
            currentTurn = currentTurn == WHITE and BLACK or WHITE
            selectedPiece = nil
            validMoves = {}
            
            updateGameState()
        else
            -- Select new piece
            local piece = getPiece(row, col)
            if isPieceOwnedByCurrentPlayer(piece) then
                selectedPiece = {row = row, col = col}
                local moves = getValidMoves(row, col)
                validMoves = filterLegalMoves(moves, row, col)
            else
                selectedPiece = nil
                validMoves = {}
            end
        end
    else
        -- Select piece
        local piece = getPiece(row, col)
        if isPieceOwnedByCurrentPlayer(piece) then
            selectedPiece = {row = row, col = col}
            local moves = getValidMoves(row, col)
            validMoves = filterLegalMoves(moves, row, col)
        end
    end
end

---------------------------------------------------------------------------
-- Public API

function Chess:Init(video, font, theme, onClose)
    _video = video
    _font = font
    _theme = theme
    _onClose = onClose
    
    -- Load chess pieces spritesheet
    local rom = gdt.ROM
    pcall(function() 
        _pieceSprites = rom.User.SpriteSheets["sprChess.png"]
    end)
    
    initializeBoard()
    currentTurn = WHITE
    selectedPiece = nil
    validMoves = {}
    gameOver = false
    winner = nil
    moveHistory = {}
    lastMove = nil
    inCheck = {white = false, black = false}
end

function Chess:HandleKey(name, shift, ctrl)
    if name == "Escape" then
        if _onClose then _onClose() end
        return
    end
    
    if name == "N" then
        initializeBoard()
        currentTurn = WHITE
        selectedPiece = nil
        validMoves = {}
        gameOver = false
        winner = nil
        moveHistory = {}
        lastMove = nil
        inCheck = {white = false, black = false}
        return
    end
    
    if name >= "1" and name <= "3" then
        difficulty = tonumber(name)
        return
    end
end

function Chess:HandleMouse(button, x, y, pressed)
    if not pressed or button ~= 1 then return end
    
    -- Convert mouse coordinates to board coordinates
    local col = math.floor((x - BOARD_X) / CELL_SIZE) + 1
    local row = math.floor((y - BOARD_Y) / CELL_SIZE) + 1
    
    if isValidSquare(row, col) then
        handleSquareClick(row, col)
    end
end

function Chess:Update()
    if not gameOver and currentTurn == BLACK then
        -- AI move for black
        makeAIMove()
        updateGameState()
    end
end

function Chess:Draw()
    if not _video or not _theme then return end
    
    -- Background
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(_video.Width - 1, _video.Height - 1), _theme.bg)
    
    drawBoard()
    drawUI()
end

---------------------------------------------------------------------------

return Chess
