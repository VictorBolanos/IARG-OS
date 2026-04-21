---------------------------------------------------------------------------
-- Chess.lua -- Classic Chess for IARG-OS
-- Launch with: game chess
-- Controls: Click to select/move, 1-3 for difficulty, N for new game, Esc to exit
---------------------------------------------------------------------------

-- BD, Utils are globals loaded by IARG-OS.lua

-- Chess application table
Chess = {
    -- Application metadata
    name = "Chess",
    version = "1.0"
}

---------------------------------------------------------------------------
-- Board and piece constants

local BOARD_SIZE = 8
local CELL_SIZE = 16
local BOARD_X = 123  -- Movido 15px más a la derecha
local BOARD_Y = 28   -- Posicionado dentro del área de contenido (12 + espacio para UI) - 5px más arriba

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
-- Columns: 0-5 all pieces (white sprites only)
-- Order: Pawn, Knight, Bishop, Rook, Queen, King
-- Color is applied dynamically based on piece color
local PIECE_SPRITES = {
    [BLACK] = {
        [PAWN] = 0, [KNIGHT] = 1, [BISHOP] = 2, 
        [ROOK] = 3, [QUEEN] = 4, [KING] = 5
    },
    [WHITE] = {
        [PAWN] = 0, [KNIGHT] = 1, [BISHOP] = 2, 
        [ROOK] = 3, [QUEEN] = 4, [KING] = 5
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
local cursorPos = {row = 4, col = 4} -- Cursor para teclado
local validMoves = {}
local gameOver = false
local winner = nil
local difficulty = 2 -- 1=Easy, 2=Medium, 3=Hard
local currentLevel = 1 -- Current level (1-3)
local moveHistory = {}
local inCheck = {white = false, black = false}
local lastMove = nil -- {from, to}
local capturedPieces = {white = {}, black = {}} -- Captured pieces display
local playerPieceColor = Color(255, 255, 255) -- Random color for player pieces
local exitConfirmMode = false -- Confirmation mode for ESC
local gameOverPopup = false -- Game over popup mode
local popupMessage = "" -- Message to display in popup
local popupType = "" -- Type of popup: "next_level", "game_completed", "new_game"

---------------------------------------------------------------------------
-- Random color generation

local function generateRandomPlayerColor()
    local colors = {
        Color(255, 255, 255), -- White
        Color(255, 200, 200), -- Light red
        Color(200, 255, 200), -- Light green
        Color(200, 200, 255), -- Light blue
        Color(255, 255, 200), -- Light yellow
        Color(255, 200, 255), -- Light magenta
        Color(200, 255, 255), -- Light cyan
    }
    return colors[math.random(#colors)]
end

local function getComplementaryColor(baseColor)
    -- Generate complementary color from theme text color
    local themeColor = _theme.text or Color(255, 255, 255)
    
    -- Calculate complementary color (invert RGB values)
    local r = 255 - themeColor.r
    local g = 255 - themeColor.g
    local b = 255 - themeColor.b
    
    -- Ensure the color is visible (not too dark)
    if r < 50 and g < 50 and b < 50 then
        r, g, b = 200, 200, 200 -- Make it light gray if too dark
    end
    
    return Color(r, g, b)
end

local function getThemeColor(colorName)
    -- Safe theme color getter with fallbacks
    if colorName == "error" then
        return _theme.error or Color(255, 100, 100)
    elseif colorName == "success" then
        return _theme.success or Color(100, 255, 100)
    elseif colorName == "dim" then
        return _theme.dim or Color(150, 150, 150)
    elseif colorName == "prompt" then
        return _theme.prompt or Color(100, 180, 255)
    else
        return _theme.text or Color(255, 255, 255)
    end
end

local function advanceToNextLevel()
    if currentLevel < 3 then
        currentLevel = currentLevel + 1
        difficulty = currentLevel -- Set difficulty to match level
        exitConfirmMode = false -- Reset confirmation mode
        gameOverPopup = false -- Reset game over popup mode
        popupMessage = "" -- Reset popup message
        popupType = "" -- Reset popup type
        initializeBoard()
        playerPieceColor = generateRandomPlayerColor()
        currentTurn = WHITE
        selectedPiece = nil
        cursorPos = {row = 4, col = 4}
        validMoves = {}
        gameOver = false
        winner = nil
        moveHistory = {}
        lastMove = nil
        inCheck = {white = false, black = false}
        capturedPieces = {white = {}, black = {}}
        return true -- Advanced to next level
    else
        -- Game completed all levels
        return false -- No more levels
    end
end

local function drawExitConfirmation()
    -- Draw confirmation dialog
    local dialogWidth = 200
    local dialogHeight = 60
    local dialogX = (336 - dialogWidth) / 2 -- Center horizontally
    local dialogY = (224 - dialogHeight) / 2 -- Center vertically
    
    -- Draw dialog background with safe colors
    local bgColor = _theme.bg or Color(50, 50, 50)
    local borderColor = _theme.text or Color(255, 255, 255)
    local errorColor = _theme.error or Color(255, 100, 100)
    local dimColor = _theme.dim or Color(150, 150, 150)
    
    _video:FillRect(vec2(dialogX, dialogY), vec2(dialogX + dialogWidth, dialogY + dialogHeight), bgColor)
    _video:DrawRect(vec2(dialogX, dialogY), vec2(dialogX + dialogWidth, dialogY + dialogHeight), borderColor)
    
    -- Draw dialog text with safe color fallbacks
    local title = "EXIT GAME?"
    local message = "Enter: Confirm  Esc: Cancel"
    
    -- Use safe text drawing function
    if _font and _video then
        -- Title
        local titleX = dialogX + (dialogWidth - #title * 4) / 2
        for i = 1, #title do
            local ch = title:sub(i, i)
            _video:DrawSprite(vec2(titleX + (i-1)*4, dialogY + 15), _font,
                ch:byte()%32, math.floor(ch:byte()/32), errorColor, color.clear)
        end
        
        -- Message
        local messageX = dialogX + (dialogWidth - #message * 4) / 2
        for i = 1, #message do
            local ch = message:sub(i, i)
            _video:DrawSprite(vec2(messageX + (i-1)*4, dialogY + 35), _font,
                ch:byte()%32, math.floor(ch:byte()/32), dimColor, color.clear)
        end
    end
end

local function drawGameOverPopup()
    -- Draw game over popup dialog
    local dialogWidth = 220
    local dialogHeight = 80
    local dialogX = (336 - dialogWidth) / 2 -- Center horizontally
    local dialogY = (224 - dialogHeight) / 2 -- Center vertically
    
    -- Draw dialog background with safe colors
    local bgColor = _theme.bg or Color(50, 50, 50)
    local borderColor = _theme.text or Color(255, 255, 255)
    local successColor = _theme.success or Color(100, 255, 100)
    local dimColor = _theme.dim or Color(150, 150, 150)
    
    _video:FillRect(vec2(dialogX, dialogY), vec2(dialogX + dialogWidth, dialogY + dialogHeight), bgColor)
    _video:DrawRect(vec2(dialogX, dialogY), vec2(dialogX + dialogWidth, dialogY + dialogHeight), borderColor)
    
    -- Draw dialog text with safe color fallbacks
    if _font and _video then
        -- Title (message)
        local titleX = dialogX + (dialogWidth - #popupMessage * 4) / 2
        for i = 1, #popupMessage do
            local ch = popupMessage:sub(i, i)
            _video:DrawSprite(vec2(titleX + (i-1)*4, dialogY + 20), _font,
                ch:byte()%32, math.floor(ch:byte()/32), successColor, color.clear)
        end
    end
end

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
    
    -- Place pawns (Player at bottom, AI at top)
    for col = 1, BOARD_SIZE do
        board[7][col] = {color = WHITE, type = PAWN}  -- Player pawns at row 7
        board[2][col] = {color = BLACK, type = PAWN}  -- AI pawns at row 2
    end
    
    -- Place pieces
    -- Player back rank (bottom)
    board[8][1] = {color = WHITE, type = ROOK}
    board[8][2] = {color = WHITE, type = KNIGHT}
    board[8][3] = {color = WHITE, type = BISHOP}
    board[8][4] = {color = WHITE, type = QUEEN}
    board[8][5] = {color = WHITE, type = KING}
    board[8][6] = {color = WHITE, type = BISHOP}
    board[8][7] = {color = WHITE, type = KNIGHT}
    board[8][8] = {color = WHITE, type = ROOK}
    
    -- AI back rank (top)
    board[1][1] = {color = BLACK, type = ROOK}
    board[1][2] = {color = BLACK, type = KNIGHT}
    board[1][3] = {color = BLACK, type = BISHOP}
    board[1][4] = {color = BLACK, type = QUEEN}
    board[1][5] = {color = BLACK, type = KING}
    board[1][6] = {color = BLACK, type = BISHOP}
    board[1][7] = {color = BLACK, type = KNIGHT}
    board[1][8] = {color = BLACK, type = ROOK}
end

---------------------------------------------------------------------------
-- Utility functions

local function tp(x, y, txt, col)
    if not _font or not _video then return end
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        _video:DrawSprite(vec2(x+(i-1)*4, y), _font, -- Use 4px width (standard)
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
    -- Player (WHITE) is at bottom, moves UP (-1 direction)
    -- AI (BLACK) is at top, moves DOWN (+1 direction)
    local direction = piece.color == WHITE and -1 or 1
    local startRow = piece.color == WHITE and 7 or 2
    
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
    -- Get the color of the piece being moved
    local movingPiece = board[fromRow][fromCol]
    if not movingPiece then return false end
    
    -- Simulate move
    local originalPiece = board[toRow][toCol]
    board[toRow][toCol] = board[fromRow][fromCol]
    board[fromRow][fromCol] = {color = EMPTY, type = EMPTY}
    
    local check = isInCheck(movingPiece.color)
    
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
        -- Capture piece if exists (AI is capturing)
        local targetPiece = getPiece(bestMove.to.row, bestMove.to.col)
        if targetPiece.type ~= EMPTY then
            local capturedColor = targetPiece.color == WHITE and "white" or "black"
            table.insert(capturedPieces[capturedColor], targetPiece.type)
        end
        
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
            
            -- Alternate colors using theme
            if (row + col) % 2 == 0 then
                _video:FillRect(vec2(x, y), vec2(x + CELL_SIZE - 1, y + CELL_SIZE - 1), Color(255, 255, 255))
            else
                _video:FillRect(vec2(x, y), vec2(x + CELL_SIZE - 1, y + CELL_SIZE - 1), getThemeColor("text"))
            end
            
            -- Highlight last move
            if lastMove then
                if (lastMove.from.row == row and lastMove.from.col == col) or
                   (lastMove.to.row == row and lastMove.to.col == col) then
                    _video:FillRect(vec2(x, y), vec2(x + CELL_SIZE - 1, y + CELL_SIZE - 1), Color(255, 255, 0))
                end
            end
            
            -- Highlight cursor
            if cursorPos.row == row and cursorPos.col == col then
                -- Use complementary color from theme
                local cursorColor = getComplementaryColor(_theme.text)
                
                -- Draw thick border (2px)
                _video:DrawRect(vec2(x, y), vec2(x + CELL_SIZE - 1, y + CELL_SIZE - 1), cursorColor)
                _video:DrawRect(vec2(x + 1, y + 1), vec2(x + CELL_SIZE - 2, y + CELL_SIZE - 2), cursorColor)
                
                -- Draw corner accents pointing inward (4px from each corner)
                -- Top-left corner
                _video:FillRect(vec2(x + 2, y + 2), vec2(x + 4, y + 3), cursorColor)
                _video:FillRect(vec2(x + 2, y + 2), vec2(x + 3, y + 4), cursorColor)
                
                -- Top-right corner
                _video:FillRect(vec2(x + CELL_SIZE - 5, y + 2), vec2(x + CELL_SIZE - 3, y + 3), cursorColor)
                _video:FillRect(vec2(x + CELL_SIZE - 4, y + 2), vec2(x + CELL_SIZE - 3, y + 4), cursorColor)
                
                -- Bottom-left corner
                _video:FillRect(vec2(x + 2, y + CELL_SIZE - 4), vec2(x + 4, y + CELL_SIZE - 3), cursorColor)
                _video:FillRect(vec2(x + 2, y + CELL_SIZE - 5), vec2(x + 3, y + CELL_SIZE - 3), cursorColor)
                
                -- Bottom-right corner
                _video:FillRect(vec2(x + CELL_SIZE - 5, y + CELL_SIZE - 4), vec2(x + CELL_SIZE - 3, y + CELL_SIZE - 3), cursorColor)
                _video:FillRect(vec2(x + CELL_SIZE - 4, y + CELL_SIZE - 5), vec2(x + CELL_SIZE - 3, y + CELL_SIZE - 3), cursorColor)
            end
            
            -- Highlight selected piece
            if selectedPiece and selectedPiece.row == row and selectedPiece.col == col then
                _video:DrawRect(vec2(x + 1, y + 1), vec2(x + CELL_SIZE - 2, y + CELL_SIZE - 2), getThemeColor("prompt"))
            end
            
            -- Highlight valid moves
            for _, move in ipairs(validMoves) do
                if move.row == row and move.col == col then
                    -- Use complementary color from theme
                    local validMoveColor = getComplementaryColor(_theme.text)
                    _video:FillRect(vec2(x + 4, y + 4), vec2(x + CELL_SIZE - 5, y + CELL_SIZE - 5), validMoveColor)
                end
            end
            
            -- Draw pieces
            local piece = getPiece(row, col)
            if piece.type ~= EMPTY and _pieceSprites then
                local spriteIndex = PIECE_SPRITES[piece.color][piece.type]
                local pieceColor = piece.color == WHITE and playerPieceColor or _theme.text
                _video:DrawSprite(
                    vec2(x, y), 
                    _pieceSprites,
                    spriteIndex, 0, -- column 0, row 0 (single row spritesheet)
                    pieceColor,
                    color.clear
                )
            end
        end
    end
    
    -- Draw board coordinates
    for i = 1, BOARD_SIZE do
        -- Row numbers
        tp(BOARD_X - 19, BOARD_Y + (i - 1) * CELL_SIZE + 6, tostring(9 - i), getThemeColor("text"))
        -- Column letters
        tp(BOARD_X + (i - 1) * CELL_SIZE - 3, BOARD_Y + BOARD_SIZE * CELL_SIZE + 2, string.char(96 + i), getThemeColor("text"))
    end
end

local function drawCapturedPieces()
    -- Position within content area
    local startY = BOARD_Y + 5 -- Above board
    local rightX = BOARD_X + BOARD_SIZE * CELL_SIZE + 5 -- Right of board
    
    -- Draw captured pieces in rows, divided by team
    local piecesPerRow = 5
    local pieceSpacing = 16
    local rowSpacing = 18
    
    -- PC captured pieces (top section)
    if #capturedPieces.white > 0 then
        tp(rightX, startY, "PC Captured:", getThemeColor("dim"))
        
        local x = rightX
        local y = startY + 10
        
        for i, pieceType in ipairs(capturedPieces.white) do
            if _pieceSprites then
                -- New row every 5 pieces
                if (i - 1) % piecesPerRow == 0 and i > 1 then
                    x = rightX
                    y = y + rowSpacing
                end
                
                local spriteIndex = PIECE_SPRITES[WHITE][pieceType]
                _video:DrawSprite(
                    vec2(x, y),
                    _pieceSprites,
                    spriteIndex, 0,
                    playerPieceColor, -- Player pieces use random color
                    color.clear
                )
                x = x + pieceSpacing
            end
        end
    end
    
    -- Player captured pieces (bottom section)
    if #capturedPieces.black > 0 then
        -- Calculate Y position based on whether PC has pieces
        local playerStartY = startY
        if #capturedPieces.white > 0 then
            -- Calculate rows needed for PC pieces
            local pcRows = math.ceil(#capturedPieces.white / piecesPerRow)
            playerStartY = startY + 10 + (pcRows * rowSpacing) + 5 -- 5px gap
        else
            playerStartY = startY + 10
        end
        
        tp(rightX, playerStartY, "You Captured:", getThemeColor("dim"))
        
        local x = rightX
        local y = playerStartY + 10
        
        for i, pieceType in ipairs(capturedPieces.black) do
            if _pieceSprites then
                -- New row every 5 pieces
                if (i - 1) % piecesPerRow == 0 and i > 1 then
                    x = rightX
                    y = y + rowSpacing
                end
                
                local spriteIndex = PIECE_SPRITES[BLACK][pieceType]
                _video:DrawSprite(
                    vec2(x, y),
                    _pieceSprites,
                    spriteIndex, 0,
                    getThemeColor("text"), -- AI pieces use theme color
                    color.clear
                )
                x = x + pieceSpacing
            end
        end
    end
end

local function drawUI()
    -- Title
    tp(BOARD_X, BOARD_Y - 25, "CHESS", getThemeColor("success"))
    
    -- Current turn
    local turnText = currentTurn == WHITE and "White's Turn" or "Black's Turn"
    tp(BOARD_X + 100, BOARD_Y - 25, turnText, getThemeColor("text"))
    
    -- Level indicator
    local levelText = string.format("Level %d/3", currentLevel)
    tp(BOARD_X, BOARD_Y - 16, levelText, getThemeColor("success"))
    
    -- Difficulty
    local diffText = "Difficulty: " .. (difficulty == 1 and "Easy" or difficulty == 2 and "Medium" or "Hard")
    tp(BOARD_X + 80, BOARD_Y - 16, diffText, getThemeColor("dim"))
    
    -- Check warning
    if inCheck.white or inCheck.black then
        local checkText = (currentTurn == WHITE and inCheck.white) or (currentTurn == BLACK and inCheck.black)
        if checkText then
            tp(BOARD_X + 200, BOARD_Y - 25, "CHECK!", getThemeColor("error"))
        end
    end
    
    -- Game over - activate popup instead of drawing on board
    if gameOver and not gameOverPopup then
        local winnerText = winner == WHITE and "White Wins!" or "Black Wins!"
        
        if winner == WHITE then
            if currentLevel < 3 then
                popupMessage = "Level Complete!"
                popupType = "next_level"
            else
                popupMessage = "All Levels Completed!"
                popupType = "game_completed"
            end
        else
            popupMessage = "Game Over - Try Again"
            popupType = "new_game"
        end
        
        gameOverPopup = true
    end
    
    -- Controls and Instructions
    tp(10, BOARD_Y + 15, "HOW TO PLAY:", getThemeColor("success"))
    tp(10, BOARD_Y + 25, "You play WHITE (bottom)", getThemeColor("text"))
    tp(10, BOARD_Y + 35, "Arrow keys: Move cursor", getThemeColor("dim"))
    tp(10, BOARD_Y + 45, "Enter: Select/Move", getThemeColor("dim"))
    tp(10, BOARD_Y + 55, "Green = valid moves", getThemeColor("dim"))
    tp(10, BOARD_Y + 65, "1-3: Difficulty", getThemeColor("text"))
    tp(10, BOARD_Y + 75, "N: New Game", getThemeColor("text"))
    tp(10, BOARD_Y + 85, "Esc: Exit", getThemeColor("text"))
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
        -- Check if clicking on the same selected piece (deselect)
        if selectedPiece.row == row and selectedPiece.col == col then
            selectedPiece = nil
            validMoves = {}
            return
        end
        
        -- Try to move
        local validMove = false
        for _, move in ipairs(validMoves) do
            if move.row == row and move.col == col then
                validMove = true
                break
            end
        end
        
        if validMove then
            -- Capture piece if exists
            local targetPiece = getPiece(row, col)
            if targetPiece.type ~= EMPTY then
                local capturedColor = targetPiece.color == WHITE and "white" or "black"
                table.insert(capturedPieces[capturedColor], targetPiece.type)
            end
            
            -- Make move
            board[row][col] = board[selectedPiece.row][selectedPiece.col]
            board[selectedPiece.row][selectedPiece.col] = {color = EMPTY, type = EMPTY}
            
            lastMove = {from = selectedPiece, to = {row = row, col = col}}
            table.insert(moveHistory, lastMove)
            
            currentTurn = currentTurn == WHITE and BLACK or WHITE
            selectedPiece = nil
            validMoves = {}
            
            updateGameState()
            
            -- AI move immediately after player move
            if currentTurn == BLACK and not gameOver then
                makeAIMove()
                updateGameState()
            end
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

-- Public API methods
Chess.Init = function(self, video, font, theme, onClose)
    -- Initialize Chess application
    _video = video
    _font = font
    _theme = theme
    _onClose = onClose
    
    -- Load chess pieces spritesheet
    local rom = gdt.ROM
    pcall(function() 
        _pieceSprites = rom.User.SpriteSheets["sprChess.png"]
    end)
    
    -- Initialize level system
    currentLevel = 1
    difficulty = 1 -- Start with easy difficulty
    exitConfirmMode = false -- Reset confirmation mode
    gameOverPopup = false -- Reset game over popup mode
    popupMessage = "" -- Reset popup message
    popupType = "" -- Reset popup type
    
    initializeBoard()
    playerPieceColor = generateRandomPlayerColor() -- Generate random color for player
    currentTurn = WHITE
    selectedPiece = nil
    cursorPos = {row = 4, col = 4}
    validMoves = {}
    gameOver = false
    winner = nil
    moveHistory = {}
    lastMove = nil
    inCheck = {white = false, black = false}
    capturedPieces = {white = {}, black = {}} -- Reset captured pieces
end

Chess.HandleKey = function(self, name, shift, ctrl)
    if name == "Escape" then
        if exitConfirmMode then
            -- Cancel confirmation
            exitConfirmMode = false
        else
            -- Enter confirmation mode
            exitConfirmMode = true
        end
        return
    end
    
    if name == "Return" then
        if exitConfirmMode then
            -- Confirm exit
            if _onClose then _onClose() end
            return
        elseif gameOverPopup then
            -- Handle game over popup with Enter
            if popupType == "next_level" then
                -- Advance to next level
                local advanced = advanceToNextLevel()
                if not advanced then
                    -- Game completed, reset to level 1
                    currentLevel = 1
                    difficulty = 1
                    advanceToNextLevel()
                end
            else
                -- New game (game_completed or new_game)
                initializeBoard()
                playerPieceColor = generateRandomPlayerColor()
                currentTurn = WHITE
                selectedPiece = nil
                cursorPos = {row = 4, col = 4}
                validMoves = {}
                gameOver = false
                winner = nil
                moveHistory = {}
                lastMove = nil
                inCheck = {white = false, black = false}
                capturedPieces = {white = {}, black = {}}
            end
            
            -- Close popup
            gameOverPopup = false
            popupMessage = ""
            popupType = ""
            return
        end
    end
    
    -- Don't process other keys while in confirmation mode or game over popup
    if exitConfirmMode or gameOverPopup then
        return
    end
    
    if name == "N" then
        -- Don't process N if game over popup is active (use Enter instead)
        if not gameOverPopup then
            if gameOver and winner == WHITE and currentLevel < 3 then
                -- Advance to next level
                local advanced = advanceToNextLevel()
                if not advanced then
                    -- Game completed, reset to level 1
                    currentLevel = 1
                    difficulty = 1
                    advanceToNextLevel()
                end
            else
                -- Reset current level or start new game
                exitConfirmMode = false -- Reset confirmation mode
                initializeBoard()
                playerPieceColor = generateRandomPlayerColor() -- New random color
                currentTurn = WHITE
                selectedPiece = nil
                cursorPos = {row = 4, col = 4}
                validMoves = {}
                gameOver = false
                winner = nil
                moveHistory = {}
                lastMove = nil
                inCheck = {white = false, black = false}
                capturedPieces = {white = {}, black = {}} -- Reset captured pieces
            end
        end
        return
    end
    
    if name >= "1" and name <= "3" then
        difficulty = tonumber(name)
        return
    end
    
    -- Arrow keys for cursor movement
    if name == "UpArrow" then
        cursorPos.row = math.max(1, cursorPos.row - 1)
        return
    elseif name == "DownArrow" then
        cursorPos.row = math.min(BOARD_SIZE, cursorPos.row + 1)
        return
    elseif name == "LeftArrow" then
        cursorPos.col = math.max(1, cursorPos.col - 1)
        return
    elseif name == "RightArrow" then
        cursorPos.col = math.min(BOARD_SIZE, cursorPos.col + 1)
        return
    elseif name == "Return" then
        -- Enter key: select or move
        handleSquareClick(cursorPos.row, cursorPos.col)
        return
    end
end

Chess.HandleMouse = function(self, button, x, y, pressed)
    if not pressed or button ~= 1 then return end
    
    -- Convert mouse coordinates to board coordinates
    local col = math.floor((x - BOARD_X) / CELL_SIZE) + 1
    local row = math.floor((y - BOARD_Y) / CELL_SIZE) + 1
    
    if isValidSquare(row, col) then
        handleSquareClick(row, col)
    end
end

Chess.Update = function(self)
    if not gameOver and currentTurn == BLACK then
        -- AI move for black
        makeAIMove()
        updateGameState()
    end
end

Chess.Draw = function(self)
    if not _video or not _theme then return end
    
    -- Background - only fill content area, preserve top bar
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(_video.Width - 1, _video.Height - 1), _theme.bg)
    
    drawBoard()
    drawCapturedPieces()
    drawUI()
    
    -- Draw exit confirmation dialog if active
    if exitConfirmMode then
        drawExitConfirmation()
    end
    
    -- Draw game over popup if active
    if gameOverPopup then
        drawGameOverPopup()
    end
end

---------------------------------------------------------------------------

return Chess
