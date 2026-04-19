---------------------------------------------------------------------------
-- TextPad.lua — Editor de texto para el CLI
-- Occupies full content area. Input via KeyboardChip.
-- Internal: Esc=exit, Ctrl+S=save (implementado via LedButton)
---------------------------------------------------------------------------

local BD = require("BD.lua")
local SaveSystem = require("SaveSystem.lua")
TextPad = {}

local _video   = nil
local _font    = nil
local _theme   = nil
local _onClose = nil   -- callback(wasSaved)

local node      = nil   -- nodo VFS del archivo
local lines     = {}    -- tabla de strings, una por línea
local curLine   = 1     -- línea del cursor (1-based)
local curCol    = 1     -- columna del cursor (1-based, tras último char)
local scrollTop = 1     -- primera línea visible
local dirty     = false
local blinkT    = 0

-- Edit area dimensions
local EDIT_X  = 2
local EDIT_Y  = BD.CONTENT_Y + 2
local EDIT_W  = BD.SW - 4
local VIS     = BD.TP_LINES_VIS   --Q líneas visibles
local MAXCOLS = BD.TP_CHARS_W     -- cols por línea

---------------------------------------------------------------------------

function TextPad:Init(videoChip, font, themeData, fileNode, onCloseCb, currentDir)
    _video   = videoChip
    _font    = font
    _theme   = themeData
    _onClose = onCloseCb
    node     = fileNode
    dirty    = false
    blinkT   = 0
    currentDir = currentDir or VFS:GetRoot()

    -- Load node content
    local content = (node and node.data) or ""
    lines = {}
    -- Split by newline
    for line in (content.."\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end
    if #lines == 0 then lines = {""} end
    curLine   = #lines
    curCol    = #lines[curLine] + 1
    scrollTop = 1
    self:_ensureVisible()
end

---------------------------------------------------------------------------
-- Ensure curLine is within visible scroll

function TextPad:_ensureVisible()
    if curLine < scrollTop then
        scrollTop = curLine
    elseif curLine >= scrollTop + VIS then
        scrollTop = curLine - VIS + 1
    end
    if scrollTop < 1 then scrollTop = 1 end
end

---------------------------------------------------------------------------
-- Serialize lines to string

function TextPad:_serialize()
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Save

function TextPad:Save()
    -- Handle unnamed files
    if not node then
        self:_showSaveMessage("Error: No file to save. Use 'run TextPad filename.txt'")
        return false
    end
    
    node.data = self:_serialize()
    dirty = false
    local saved = SaveSystem:Save(OSConfig)
    if saved then
        -- Show save confirmation
        self:_showSaveMessage("SAVED: " .. node.name)
    else
        self:_showSaveMessage("ERROR: Save failed - FlashMemory full?")
    end
    return true
end

---------------------------------------------------------------------------
-- Show save message temporarily

local saveMsgTimer = 0
local saveMsgText = ""
local saveAsMode = false
local saveAsInput = ""
local saveAsCursor = 0

function TextPad:_showSaveMessage(msg)
    saveMsgText = msg
    saveMsgTimer = 120  -- Show for 2 seconds at 60 FPS
end

---------------------------------------------------------------------------
-- Save As dialog

function TextPad:_startSaveAsDialog()
    saveAsMode = true
    -- Start with current name (without extension) or "untitled"
    if node and node.name then
        -- Remove .txt extension if present, avoid duplication
        local baseName = node.name:gsub("%.txt$", "")
        saveAsInput = baseName
    else
        saveAsInput = "untitled"
    end
    saveAsCursor = #saveAsInput
end

---------------------------------------------------------------------------
-- Validate Save As input

function TextPad:_validateSaveAsInput()
    -- Check for empty name
    if saveAsInput == "" then
        return false, "Empty filename"
    end
    
    -- Check for invalid characters
    local invalidChars = "<>:\/|?*\""
    for i = 1, #invalidChars do
        if saveAsInput:find(invalidChars:sub(i,i), 1, true) then
            return false, "Invalid characters: " .. invalidChars
        end
    end
    
    -- Check for reserved names (case-insensitive)
    local reservedNames = {"CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3"}
    local upperInput = saveAsInput:upper()
    for _, reserved in ipairs(reservedNames) do
        if upperInput == reserved then
            return false, "Reserved name: " .. reserved
        end
    end
    
    -- Check length limit
    if #saveAsInput > 50 then
        return false, "Filename too long (max 50)"
    end
    
    return true, ""
end

function TextPad:_executeSaveAs()
    if saveAsInput and #saveAsInput > 0 then
        -- Validate input before saving
        local valid, errorMsg = TextPad:_validateSaveAsInput()
        if not valid then
            self:_showSaveMessage("ERROR: " .. errorMsg)
            return
        end
        
        -- Use stored current working directory
        local cwd = currentDir or VFS:GetRoot()
        
        -- Create new file with the specified name + .txt
        local newNode = VFS:CreateFile(cwd, saveAsInput .. ".txt", BD.NT_TXT, self:_serialize())
        if newNode then
            -- Update current node to the new file
            node = newNode
            dirty = false
            SaveSystem:Save(OSConfig)
            self:_showSaveMessage("SAVED AS: " .. saveAsInput)
        else
            self:_showSaveMessage("ERROR: Could not create file")
        end
        saveAsMode = false
        saveAsInput = ""
        saveAsCursor = 0
    end
end

---------------------------------------------------------------------------
-- Input de teclado — llamado desde IARG-OS cuando llega un KeyboardChipEvent

function TextPad:HandleKey(inputName, shift, ctrl)
    -- Esc  salir
    if inputName == "Escape" then
        if dirty then
            -- auto-save on exit
            self:Save()
        end
        if _onClose then _onClose(dirty) end
        return
    end

    -- Ctrl+S  guardar
    if ctrl and inputName == "S" and not shift then
        self:Save(); return
    end
    
    -- Ctrl+Shift+S  Save As
    if ctrl and shift and inputName == "S" then
        self:_startSaveAsDialog(); return
    end

    -- Navigation
    if inputName == "LeftArrow" then
        if curCol > 1 then
            curCol = curCol - 1
        elseif curLine > 1 then
            curLine = curLine - 1
            curCol  = #lines[curLine] + 1
        end
        self:_ensureVisible(); return
    end

    if inputName == "RightArrow" then
        if curCol <= #lines[curLine] then
            curCol = curCol + 1
        elseif curLine < #lines then
            curLine = curLine + 1
            curCol  = 1
        end
        self:_ensureVisible(); return
    end

    if inputName == "UpArrow" then
        if curLine > 1 then
            curLine = curLine - 1
            curCol  = math.min(curCol, #lines[curLine] + 1)
        end
        self:_ensureVisible(); return
    end

    if inputName == "DownArrow" then
        if curLine < #lines then
            curLine = curLine + 1
            curCol  = math.min(curCol, #lines[curLine] + 1)
        end
        self:_ensureVisible(); return
    end

    if inputName == "Home" then curCol=1; return end
    if inputName == "End"  then curCol=#lines[curLine]+1; return end

    if inputName == "PageUp" then
        curLine = math.max(1, curLine - VIS)
        curCol  = math.min(curCol, #lines[curLine]+1)
        self:_ensureVisible(); return
    end

    if inputName == "PageDown" then
        curLine = math.min(#lines, curLine + VIS)
        curCol  = math.min(curCol, #lines[curLine]+1)
        self:_ensureVisible(); return
    end

    -- Backspace (different behavior in Save As mode)
    if inputName == "Backspace" then
        if saveAsMode then
            -- Backspace only affects Save As input
            if saveAsCursor > 1 then
                saveAsInput = saveAsInput:sub(1, saveAsCursor-1) .. saveAsInput:sub(saveAsCursor+1)
                saveAsCursor = saveAsCursor - 1
            end
            return
        end
        
        -- Normal Backspace for document editing
        if curCol > 1 then
            local l = lines[curLine]
            lines[curLine] = l:sub(1, curCol-2) .. l:sub(curCol)
            curCol = curCol - 1
            dirty  = true
        elseif curLine > 1 then
            -- fusionar con línea anterior
            local prev = lines[curLine-1]
            local curr = lines[curLine]
            curCol = #prev + 1
            lines[curLine-1] = prev .. curr
            table.remove(lines, curLine)
            curLine = curLine - 1
            dirty   = true
        end
        self:_ensureVisible(); return
    end

    -- Delete (different behavior in Save As mode)
    if inputName == "Delete" then
        if saveAsMode then
            -- Delete only affects Save As input
            if saveAsCursor <= #saveAsInput then
                saveAsInput = saveAsInput:sub(1, saveAsCursor-1) .. saveAsInput:sub(saveAsCursor+2)
            end
            return
        end
        
        -- Normal Delete for document editing
        local l = lines[curLine]
        if curCol <= #l then
            lines[curLine] = l:sub(1, curCol-1) .. l:sub(curCol+1)
            dirty = true
        elseif curLine < #lines then
            lines[curLine] = l .. lines[curLine+1]
            table.remove(lines, curLine+1)
            dirty = true
        end
        return
    end

    -- Enter (different behavior in Save As mode)
    if inputName == "Return" then
        if saveAsMode then
            -- Enter only executes Save As
            self:_executeSaveAs(); return
        end
        
        -- Normal Enter for document editing
        local l    = lines[curLine]
        local before = l:sub(1, curCol-1)
        local after  = l:sub(curCol)
        lines[curLine] = before
        table.insert(lines, curLine+1, after)
        curLine = curLine + 1
        curCol  = 1
        dirty   = true
        self:_ensureVisible(); return
    end

    -- Tab 4 espacios (disabled in Save As mode)
    if inputName == "Tab" and not saveAsMode then
        local spaces = "    "
        local l = lines[curLine]
        local total = #l + 4
        if total <= BD.TP_MAX_CHARS then
            lines[curLine] = l:sub(1,curCol-1)..spaces..l:sub(curCol)
            curCol = curCol + 4
            dirty  = true
        end
        return
    end

    -- Printable character (only when not in Save As mode)
    if not saveAsMode then
        local char = self:_inputToChar(inputName, shift)
        if char then
            local l = lines[curLine]
            if #self:_serialize() < BD.TP_MAX_CHARS then
                lines[curLine] = l:sub(1,curCol-1)..char..l:sub(curCol)
                curCol = curCol + 1
                dirty  = true
            end
        end
    end
    
    -- Save As mode input handling
    if saveAsMode then
        if inputName == "Return" or inputName == "KeypadEnter" then
            self:_executeSaveAs(); return
        end
        
        if inputName == "Escape" then
            saveAsMode = false
            saveAsInput = ""
            saveAsCursor = 0
            return
        end
        
        -- Backspace in Save As mode
        if inputName == "Backspace" then
            if saveAsCursor > 1 then
                saveAsInput = saveAsInput:sub(1, saveAsCursor-1) .. saveAsInput:sub(saveAsCursor+1)
                saveAsCursor = saveAsCursor - 1
            end
            return
        end
        
        -- Normal character input in Save As mode
        local char = self:_inputToChar(inputName, shift)
        if char then
            saveAsInput = saveAsInput:sub(1, saveAsCursor-1) .. char .. saveAsInput:sub(saveAsCursor+1)
            saveAsCursor = saveAsCursor + 1
        end
        return
    end
end

---------------------------------------------------------------------------
-- Convierte InputName a carácter

function TextPad:_inputToChar(name, shift)
    -- Letters A-Z
    local letters = {
        A="a",B="b",C="c",D="d",E="e",F="f",G="g",H="h",I="i",J="j",
        K="k",L="l",M="m",N="n",O="o",P="p",Q="q",R="r",S="s",T="t",
        U="u",V="v",W="w",X="x",Y="y",Z="z"
    }
    if letters[name] then
        return shift and name or letters[name]
    end
    -- Numbers
    local nums = {
        Alpha0="0",Alpha1="1",Alpha2="2",Alpha3="3",Alpha4="4",
        Alpha5="5",Alpha6="6",Alpha7="7",Alpha8="8",Alpha9="9",
        Keypad0="0",Keypad1="1",Keypad2="2",Keypad3="3",Keypad4="4",
        Keypad5="5",Keypad6="6",Keypad7="7",Keypad8="8",Keypad9="9",
    }
    if nums[name] then return nums[name] end
    -- Symbols con InputName propio (doc oficial)
    local direct = {
        Space=" ", Period=".", Comma=",", Minus="-", Slash="/",
        Backslash="\\", Semicolon=";", Quote="'", Equals="=",
        LeftBracket="[", RightBracket="]", BackQuote="`",
        Exclaim="!", DoubleQuote='"', Hash="#", Dollar="$",
        Percent="%", Ampersand="&", LeftParen="(", RightParen=")",
        Asterisk="*", Plus="+", Colon=":", Less="<", Greater=">",
        Question="?", At="@", Caret="^", Underscore="_",
        LeftCurlyBracket="{", Pipe="|", RightCurlyBracket="}", Tilde="~",
        KeypadPeriod=".", KeypadDivide="/", KeypadMultiply="*",
        KeypadMinus="-", KeypadPlus="+", KeypadEquals="=",
    }
    if direct[name] then return direct[name] end
    return nil
end

---------------------------------------------------------------------------
-- Update (cursor blink)

function TextPad:Update()
    blinkT = blinkT + 1
    if blinkT >= BD.CURSOR_BLINK * 2 then blinkT = 0 end
    
    -- Handle save message timer
    if saveMsgTimer > 0 then
        saveMsgTimer = saveMsgTimer - 1
    end
end

---------------------------------------------------------------------------
-- Draw

function TextPad:Draw()
    if not _video or not _theme or not _font then return end

    -- Background
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(BD.SW-1, BD.SH-1), _theme.bg)

    -- Editor header
    local fname = node and node.name or "sin titulo"
    if dirty then fname = fname.." *" end
    
    -- Different header when in Save As mode
    local header
    if saveAsMode then
        header = "-- Save As: "..saveAsInput.."_ [Enter=save ESC=cancel]"
        -- Draw cursor for Save As input
        local cursorX = EDIT_X + #"-- Save As: " * BD.CHAR_W + saveAsCursor * BD.CHAR_W
        if blinkT < BD.CURSOR_BLINK then
            _video:DrawLine(vec2(cursorX, BD.CONTENT_Y+1), vec2(cursorX, BD.CONTENT_Y+1 + BD.CHAR_H), _theme.text)
        end
    else
        header = "-- TextPad: "..fname.." -- [ESC=salir Ctrl+S=guardar Ctrl+Shift+S=save as]"
    end
    
    self:_tprint(EDIT_X, BD.CONTENT_Y+1, header, _theme.dim)
    _video:DrawLine(vec2(0, BD.CONTENT_Y+9), vec2(BD.SW-1, BD.CONTENT_Y+9), _theme.dim)
    
    -- Show save message if active (overlay on top)
    if saveMsgTimer > 0 then
        local msgY = BD.CONTENT_Y + 2
        -- Draw background for message
        local msgWidth = #saveMsgText * BD.CHAR_W + 4
        _video:FillRect(vec2(EDIT_X-1, msgY-1), vec2(EDIT_X + msgWidth, msgY + BD.CHAR_H + 1), _theme.success)
        _video:DrawRect(vec2(EDIT_X-1, msgY-1), vec2(EDIT_X + msgWidth, msgY + BD.CHAR_H + 1), _theme.text)
        self:_tprint(EDIT_X, msgY, saveMsgText, _theme.bg)
    end

    -- Visible lines
    local startY = BD.CONTENT_Y + 12
    for i = 1, VIS do
        local li = i + scrollTop - 1
        if li > #lines then break end
        local lineText = lines[li] or ""
        local ty = startY + (i-1) * BD.CHAR_H

        -- Line number (dim)
        local numStr = string.format("%3d", li)
        self:_tprint(EDIT_X, ty, numStr, _theme.dim)

        -- Line content (truncated if too long)
        local displayCols = math.floor((EDIT_W - 16) / BD.CHAR_W)
        local display = lineText
        if #display > displayCols then display = display:sub(1, displayCols) end
        self:_tprint(EDIT_X + 16, ty, display, _theme.text)

        -- Cursor
        if li == curLine and blinkT < BD.CURSOR_BLINK then
            local cx = EDIT_X + 16 + (curCol-1) * BD.CHAR_W
            _video:DrawLine(vec2(cx, ty), vec2(cx, ty+BD.CHAR_H-1), _theme.cursor)
        end
    end

    -- Status bar bottom
    local statY = BD.SH - BD.CHAR_H - 2
    _video:FillRect(vec2(0, statY-1), vec2(BD.SW-1, BD.SH-1), _theme.topbar)
    local stat = "Ln "..curLine.."/"..#lines.."  Col "..curCol
              .."  ["..#self:_serialize().."/"..BD.TP_MAX_CHARS.." ch]"
    self:_tprint(EDIT_X, statY, stat, _theme.dim)
end

---------------------------------------------------------------------------
-- local tprint

function TextPad:_tprint(x, y, txt, col)
    if not _font then return end
    for i=1,#txt do
        local ch=txt:sub(i,i)
        _video:DrawSprite(vec2(x+(i-1)*BD.CHAR_W, y), _font,
            ch:byte()%32, math.floor(ch:byte()/32), col, color.clear)
    end
end

---------------------------------------------------------------------------

return TextPad