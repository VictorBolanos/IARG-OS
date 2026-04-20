---------------------------------------------------------------------------
-- TextPad.lua — Editor de texto para el CLI
-- Occupies full content area. Input via KeyboardChip.
-- Internal: Esc=exit, Ctrl+S=save (implementado via LedButton)
---------------------------------------------------------------------------

-- BD, SaveSystem, VFS are globals loaded by IARG-OS.lua
TextPad = {}

local BD         = require("BD.lua")

local _video   = nil
local _font    = nil
local _theme   = nil
local _onClose = nil   -- callback(wasSaved)

local node        = nil   -- VFS node of the open file
local _currentDir = nil   -- working directory for Save As
local lines     = {}    -- table of strings, one per line
local curLine   = 1     -- cursor line (1-based)
local curCol    = 1     -- cursor column (1-based)
local scrollTop = 1     -- first visible line
local dirty     = false
local blinkT    = 0

-- Edit area dimensions
local EDIT_X  = 2
local EDIT_Y  = nil
local EDIT_W  = nil
local VIS     = nil
local MAXCOLS = nil

---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Convert UTF-8 special chars to custom font sprite bytes

local function fixEncoding(s)
    s = s:gsub("\195\177", "\128")
    s = s:gsub("\195\145", "\127")
    s = s:gsub("\194\191", "\129")
    s = s:gsub("\194\161", "\130")
    s = s:gsub("\195\161", "a")
    s = s:gsub("\195\169", "e")
    s = s:gsub("\195\173", "i")
    s = s:gsub("\195\179", "o")
    s = s:gsub("\195\186", "u")
    s = s:gsub("\195\129", "A")
    s = s:gsub("\195\137", "E")
    s = s:gsub("\195\141", "I")
    s = s:gsub("\195\147", "O")
    s = s:gsub("\195\154", "U")
    s = s:gsub("\195\188", "u")
    return s
end

function TextPad:Init(videoChip, font, themeData, fileNode, currentDir, onCloseCb)
    _video      = videoChip
    _font       = font
    _theme      = themeData
    _onClose    = onCloseCb
    node        = fileNode
    _currentDir = currentDir or VFS:GetRoot()
    dirty       = false
    blinkT      = 0

    -- Initialize layout constants (BD values are final at this point)
    EDIT_Y  = BD.CONTENT_Y + 2
    EDIT_W  = (_video and _video.Width or BD.SW) - 4
    VIS     = BD.TP_LINES_VIS
    MAXCOLS = BD.TP_CHARS_W or 54

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
local saveAsMode  = false
local saveAsInput = ""
local saveAsCursor = 0

-- Title editing mode: Ctrl+Tab toggles between editing filename and text
local titleMode   = false
local titleInput  = ""
local titleCursor = 0

function TextPad:_showSaveMessage(msg)
    saveMsgText = msg
    saveMsgTimer = 120  -- Show for 2 seconds at 60 FPS
end

---------------------------------------------------------------------------
-- Save As dialog

function TextPad:_startSaveAsDialog()
    saveAsMode  = true
    saveAsInput = ""      -- always start empty, no placeholder
    saveAsCursor = 0
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

    -- Check for duplicate name in current directory
    local cwd = _currentDir or VFS:GetRoot()
    local fullName = saveAsInput .. ".txt"
    if VFS:FindChild(cwd, fullName) then
        return false, "Already exists: " .. fullName
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
        local cwd = _currentDir or VFS:GetRoot()
        
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
-- Title bar key handler (active when titleMode=true)

function TextPad:_handleTitleKey(name, shift, ctrl)
    if name == "Escape" then
        titleMode = false   -- cancel, restore original
        return
    end
    if name == "Return" or name == "KeypadEnter" then
        -- Same as Ctrl+Tab commit — handled above, but just in case
        titleMode = false
        return
    end
    if name == "Backspace" then
        if titleCursor > 0 then
            titleInput  = titleInput:sub(1, titleCursor-1) .. titleInput:sub(titleCursor+1)
            titleCursor = titleCursor - 1
        end
        return
    end
    if name == "Delete" then
        if titleCursor < #titleInput then
            titleInput = titleInput:sub(1, titleCursor) .. titleInput:sub(titleCursor+2)
        end
        return
    end
    if name == "LeftArrow"  then titleCursor = math.max(0, titleCursor-1);          return end
    if name == "RightArrow" then titleCursor = math.min(#titleInput, titleCursor+1); return end
    if name == "Home"       then titleCursor = 0;                                    return end
    if name == "End"        then titleCursor = #titleInput;                          return end

    -- Printable char
    local char = self:_inputToChar(name, shift)
    if char and #titleInput < 50 then
        -- Block characters invalid in filenames
        if not char:match('[<>:"/\|?*]') then
            titleInput  = titleInput:sub(1, titleCursor) .. char .. titleInput:sub(titleCursor+1)
            titleCursor = titleCursor + 1
        end
    end
end

---------------------------------------------------------------------------
-- Input de teclado -- called from IARG-OS on KeyboardChipEvent

function TextPad:HandleKey(inputName, shift, ctrl)

    -- ── Title mode: intercept ALL keys before anything else ───────────
    if titleMode then
        if inputName == "Escape" then
            titleMode = false   -- cancel, no rename
            return
        end
        if inputName == "Return" or inputName == "KeypadEnter" then
            -- Commit rename on Enter
            local trimmed = titleInput:match("^%s*(.-)%s*$")
            if trimmed and #trimmed > 0 then
                local fullName = trimmed
                if not fullName:match("%.txt$") then fullName = fullName .. ".txt" end
                local cwd = _currentDir or VFS:GetRoot()
                local existing = VFS:FindChild(cwd, fullName)
                if existing and existing ~= node then
                    self:_showSaveMessage("ERROR: Already exists: " .. fullName)
                elseif node then
                    node.name = fullName
                    dirty = true
                    self:_showSaveMessage("Renamed to: " .. fullName)
                end
            end
            titleMode = false
            return
        end
        -- All other keys routed to title key handler
        self:_handleTitleKey(inputName, shift, ctrl)
        return
    end

    -- ── Save As mode: intercept ALL keys before anything else ─────────
    if saveAsMode then
        if inputName == "Escape" then
            saveAsMode   = false
            saveAsInput  = ""
            saveAsCursor = 0
            return
        end
        if inputName == "Return" or inputName == "KeypadEnter" then
            self:_executeSaveAs()
            return
        end
        if inputName == "Backspace" then
            if saveAsCursor > 0 then
                saveAsInput  = saveAsInput:sub(1, saveAsCursor-1) .. saveAsInput:sub(saveAsCursor+1)
                saveAsCursor = saveAsCursor - 1
            end
            return
        end
        if inputName == "Delete" then
            if saveAsCursor < #saveAsInput then
                saveAsInput = saveAsInput:sub(1, saveAsCursor) .. saveAsInput:sub(saveAsCursor+2)
            end
            return
        end
        if inputName == "LeftArrow"  then saveAsCursor = math.max(0, saveAsCursor-1);             return end
        if inputName == "RightArrow" then saveAsCursor = math.min(#saveAsInput, saveAsCursor+1);  return end
        if inputName == "Home"       then saveAsCursor = 0;                                        return end
        if inputName == "End"        then saveAsCursor = #saveAsInput;                             return end
        local char = self:_inputToChar(inputName, shift)
        if char and #saveAsInput < 50 then
            if not char:match('[<>:"/\|?*]') then
                saveAsInput  = saveAsInput:sub(1, saveAsCursor) .. char .. saveAsInput:sub(saveAsCursor+1)
                saveAsCursor = saveAsCursor + 1
            end
        end
        return
    end

    -- ── Normal mode ────────────────────────────────────────────────────

    -- Esc = exit without saving
    if inputName == "Escape" then
        if _onClose then _onClose(false) end
        return
    end

    -- Ctrl+S = save
    if ctrl and inputName == "S" and not shift then
        self:Save(); return
    end

    -- Ctrl+Shift+S = Save As
    if ctrl and shift and inputName == "S" then
        self:_startSaveAsDialog(); return
    end

    -- Ctrl+Tab = enter title editing mode
    if ctrl and inputName == "Tab" then
        titleMode   = true
        titleInput  = node and node.name:gsub("%.txt$", "") or ""
        titleCursor = #titleInput
        return
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

    -- Backspace
    if inputName == "Backspace" then
        if curCol > 1 then
            local l = lines[curLine]
            lines[curLine] = l:sub(1, curCol-2) .. l:sub(curCol)
            curCol = curCol - 1
            dirty  = true
        elseif curLine > 1 then
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

    -- Delete
    if inputName == "Delete" then
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

    -- Enter -- new line
    if inputName == "Return" or inputName == "KeypadEnter" then
        local l      = lines[curLine]
        local before = l:sub(1, curCol-1)
        local after  = l:sub(curCol)
        lines[curLine] = before
        table.insert(lines, curLine+1, after)
        curLine = curLine + 1
        curCol  = 1
        dirty   = true
        self:_ensureVisible(); return
    end

    -- Tab = 4 spaces
    if inputName == "Tab" then
        local l = lines[curLine]
        if #self:_serialize() + 4 <= BD.TP_MAX_CHARS then
            lines[curLine] = l:sub(1,curCol-1) .. "    " .. l:sub(curCol)
            curCol = curCol + 4
            dirty  = true
        end
        return
    end

    -- Printable character
    local char = self:_inputToChar(inputName, shift)
    if char then
        local l = lines[curLine]
        if #self:_serialize() < BD.TP_MAX_CHARS then
            lines[curLine] = l:sub(1,curCol-1) .. char .. l:sub(curCol)
            curCol = curCol + 1
            dirty  = true
        end
    end
end

---------------------------------------------------------------------------
-- Convert InputName to printable character

function TextPad:_inputToChar(name, shift)
    -- Spanish character substitutes (same as CLI for consistency)
    local spanishSubs = {
        -- ñ/Ñ (most common Spanish characters)
        Tilde = "ñ",      -- Shift + ~ (easy to find)
        Caret = "Ñ",      -- Shift + ^ (alternative)
        
        -- Vocales con tilde (using nearby keys)
        LeftBracket = "á",  -- Shift + [ (near 'a')
        LeftCurlyBracket = "Á", -- Shift + { (capital á)
        Semicolon = "é",   -- Shift + ; (near 'e')
        Colon = "É",       -- Shift + : (capital é)
        Quote = "í",       -- Shift + ' (near 'i')
        DoubleQuote = "Í",  -- Shift + " (capital í)
        Comma = "ó",       -- Shift + , (near 'o')
        Less = "Ó",        -- Shift + < (capital ó)
        Period = "ú",      -- Shift + . (near 'u')
        Greater = "Ú",      -- Shift + > (capital ú)
        
        -- Signos españoles
        Question = "¿",    -- Shift + ? (opening question mark)
        Exclaim = "¡",     -- Shift + ! (inverted exclamation)
    }
    
    -- Check Spanish substitutes first (highest priority)
    if spanishSubs[name] then
        return spanishSubs[name]
    end
    
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
    -- Shift+Minus = "_" on keyboards where Underscore is not a separate key
    if name == "Minus" and shift then return "_" end


    -- Symbols with dedicated InputName (official docs)
    local direct = {
        Space=" ", Period=".", Comma=",", Minus="-", Slash="/",
        Backslash="\\", Semicolon=";", Quote="'", Equals="=",
        LeftBracket="[", RightBracket="]", BackQuote="\128",  -- ñ
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
    local fname = node and node.name or "[unsaved]"
    if dirty then fname = fname .. " *" end

    local header
    local headerColor = _theme.dim

    if saveAsMode then
        -- Save As dialog in header
        header = "Save As: " .. saveAsInput
        local cursorX = EDIT_X + #"Save As: " * BD.CHAR_W + saveAsCursor * BD.CHAR_W
        if blinkT < BD.CURSOR_BLINK then
            _video:DrawLine(vec2(cursorX, BD.CONTENT_Y+1), vec2(cursorX, BD.CONTENT_Y+1+BD.CHAR_H), _theme.prompt)
        end
        headerColor = _theme.prompt
    elseif titleMode then
        -- Title editing mode
        header = "Name: " .. titleInput
        local cursorX = EDIT_X + #"Name: " * BD.CHAR_W + titleCursor * BD.CHAR_W
        if blinkT < BD.CURSOR_BLINK then
            _video:DrawLine(vec2(cursorX, BD.CONTENT_Y+1), vec2(cursorX, BD.CONTENT_Y+1+BD.CHAR_H), _theme.success)
        end
        headerColor = _theme.success
    else
        header = fname .. "  [Ctrl+S=save  Ctrl+Shift+S=save as  Ctrl+Tab=rename  ESC=exit]"
    end

    self:_tprint(EDIT_X, BD.CONTENT_Y+1, header, headerColor)
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
        local lineText = fixEncoding(lines[li] or "")
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