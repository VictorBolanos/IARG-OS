---------------------------------------------------------------------------
-- CLI.lua -- Command Line Interface for IARG-OS
--
-- Available commands:
--   ls                    - list current directory contents
--   cd <name>             - enter folder
--   cd ..                 - go up one level
--   mkdir <name>          - create folder
--   touch <name>          - create empty text file
--   rm <name>             - delete file or empty folder
--   rename <old> <new>    - rename item
--   run TextPad [file]    - open text editor
--   theme <0-3>           - change visual theme
--   help                  - show help
--   clear / cls           - clear screen
--
-- Input: KeyboardChip via eventChannel1 in IARG-OS.lua
-- shift and ctrl are resolved in IARG-OS and passed as parameters
---------------------------------------------------------------------------

local BD         = require("BD.lua")
local VFS        = require("VFS.lua")
local SaveSystem = require("SaveSystem.lua")

CLI = {}

-- Private state
local _video    = nil
local _font     = nil
local _theme    = nil
local _keyboard = nil
local _onLaunch = nil

local outputBuf  = {}
local MAX_OUTPUT = 200

local inputLine = ""
local cursorPos = 0
local blinkT    = 0

local history = {}
local histIdx = 0

-- Output scroll navigation
local outputScrollOffset = 0
local maxScrollOffset = 0

-- Smooth scroll system for held keys
local scrollKey = nil          -- Currently scrolling key (UpArrow/DownArrow)
local scrollTimer = 0          -- Timer for smooth scroll
local scrollSpeed = 6           -- Frames between scroll steps (smoothness)
local scrollActive = false       -- Whether smooth scroll is active

local cwd = nil

---------------------------------------------------------------------------
-- Local text print (single line, no wrap)

local function tp(x, y, txt, col)
    if not _font or not _video then return end
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        _video:DrawSprite(
            vec2(x + (i-1) * BD.CHAR_W, y),
            _font,
            ch:byte() % 32,
            math.floor(ch:byte() / 32),
            col,
            color.clear)
    end
end

---------------------------------------------------------------------------
-- Current working directory as display string

local function cwdStr()
    if not cwd then return "/" end
    local p = VFS:GetPath(cwd)
    p = p:gsub("^root", "~")
    return p
end

---------------------------------------------------------------------------
-- Add line to output buffer (with word-wrap)

function CLI:_out(txt, col)
    col = col or _theme.output
    local maxCols = BD.CLI_CHARS
    if #txt == 0 then
        table.insert(outputBuf, {text = "", color = col})
    else
        while #txt > 0 do
            table.insert(outputBuf, {text = txt:sub(1, maxCols), color = col})
            txt = txt:sub(maxCols + 1)
        end
    end
    while #outputBuf > MAX_OUTPUT do
        table.remove(outputBuf, 1)
    end
    -- Reset scroll to bottom when new output is added
    outputScrollOffset = 0
    -- Update max scroll based on current screen dimensions
    local sw = _video and _video.Width or BD.SW
    local sh = _video and _video.Height or BD.SH
    local promptY = sh - BD.CHAR_H - 2
    local outputBottom = promptY - 4
    local visLines = math.floor((outputBottom - BD.CONTENT_Y) / BD.CHAR_H)
    maxScrollOffset = math.max(0, #outputBuf - visLines)
end

---------------------------------------------------------------------------
-- Init

function CLI:Init(video, font, themeData, keyboard, onLaunch)
    _video    = video
    _font     = font
    _theme    = themeData
    _keyboard = keyboard
    _onLaunch = onLaunch
    cwd       = VFS:GetRoot()
    outputBuf = {}
    inputLine = ""
    cursorPos = 0
    history   = {}
    histIdx   = 0
    outputScrollOffset = 0
    maxScrollOffset = 0

    self:_out("IARG-OS v0.1 -- Console Mode", _theme.success)
    self:_out("Type 'help' to see available commands.", _theme.dim)
    self:_out("", _theme.text)
end

function CLI:SetTheme(t) _theme = t end
function CLI:GetCWD()    return cwd end

---------------------------------------------------------------------------
-- Execute command

function CLI:_execute(cmdStr)
    if cmdStr ~= "" then
        table.insert(history, 1, cmdStr)
        if #history > 50 then table.remove(history) end
    end
    histIdx = 0

    self:_out(cwdStr() .. " " .. BD.PROMPT_PREFIX .. cmdStr, _theme.prompt)
    if cmdStr == "" then return end

    local parts = {}
    for p in cmdStr:gmatch("%S+") do table.insert(parts, p) end
    local cmd  = parts[1]:lower()
    local arg1 = parts[2]
    local arg2 = parts[3]

    if cmd == "clear" or cmd == "cls" then
        outputBuf = {}
        outputScrollOffset = 0
        maxScrollOffset = 0

    elseif cmd == "help" then
        self:_out("Available commands:", _theme.success)
        self:_out("  ls                 List current directory", _theme.output)
        self:_out("  cd <name>          Enter folder", _theme.output)
        self:_out("  cd ..              Go up one level", _theme.output)
        self:_out("  mkdir <name>       Create folder", _theme.output)
        self:_out("  touch <name>       Create text file", _theme.output)
        self:_out("  rm <name>          Delete file or folder", _theme.output)
        self:_out("  rename <old> <new> Rename item", _theme.output)
        self:_out("  run TextPad [file] Open text editor", _theme.output)
        self:_out("  theme <0-3>        Change visual theme", _theme.output)
        self:_out("  help               Show this help", _theme.output)
        self:_out("  clear              Clear screen", _theme.output)
        self:_out("", _theme.text)
        self:_out("Navigation:", _theme.success)
        self:_out("  Up/Down arrows     Navigate command history", _theme.output)
        self:_out("  Ctrl+Up/Down       Scroll terminal output", _theme.output)
        self:_out("  Left/Right arrows  Move cursor in input", _theme.output)
        self:_out("  Ctrl+L             Clear screen", _theme.output)

    elseif cmd == "ls" then
        local children = VFS:GetChildren(cwd)
        if #children == 0 then
            self:_out("  (empty)", _theme.dim)
        else
            for _, node in ipairs(children) do
                local suffix = node.type == BD.NT_FOLDER and "/" or ""
                local info   = ""
                if node.type == BD.NT_TXT and node.data then
                    info = "  [" .. #node.data .. " ch]"
                end
                local col = node.type == BD.NT_FOLDER and _theme.prompt or _theme.text
                self:_out("  " .. node.name .. suffix .. info, col)
            end
        end

    elseif cmd == "cd" then
        if not arg1 then
            self:_out("Usage: cd <name> | cd ..", _theme.error)
        elseif arg1 == ".." then
            if cwd.parent then
                cwd = cwd.parent
            else
                self:_out("Already at root.", _theme.dim)
            end
        elseif arg1 == "~" or arg1 == "/" then
            cwd = VFS:GetRoot()
        else
            local target = VFS:FindChild(cwd, arg1)
            if not target then
                self:_out("Not found: " .. arg1, _theme.error)
            elseif target.type ~= BD.NT_FOLDER then
                self:_out(arg1 .. " is not a folder.", _theme.error)
            else
                cwd = target
            end
        end

    elseif cmd == "mkdir" then
        if not arg1 or arg1 == "" then
            self:_out("Usage: mkdir <name>", _theme.error)
        elseif VFS:FindChild(cwd, arg1) then
            self:_out("Already exists: " .. arg1, _theme.error)
        else
            local node = VFS:CreateFolder(cwd, arg1)
            if node then
                self:_out("Folder created: " .. arg1, _theme.success)
                SaveSystem:Save(OSConfig)
            else
                self:_out("Error: node limit reached.", _theme.error)
            end
        end

    elseif cmd == "touch" then
        if not arg1 or arg1 == "" then
            self:_out("Usage: touch <name>", _theme.error)
        elseif VFS:FindChild(cwd, arg1) then
            self:_out("Already exists: " .. arg1, _theme.error)
        else
            local node = VFS:CreateFile(cwd, arg1, BD.NT_TXT, "")
            if node then
                self:_out("File created: " .. arg1, _theme.success)
                SaveSystem:Save(OSConfig)
            else
                self:_out("Error: node limit reached.", _theme.error)
            end
        end

    elseif cmd == "rm" then
        if not arg1 then
            self:_out("Usage: rm <name>", _theme.error)
        else
            local target = VFS:FindChild(cwd, arg1)
            if not target then
                self:_out("Not found: " .. arg1, _theme.error)
            elseif target.type == BD.NT_FOLDER and #target.children > 0 then
                self:_out("Folder is not empty.", _theme.error)
            else
                VFS:Delete(target)
                self:_out("Deleted: " .. arg1, _theme.success)
                SaveSystem:Save(OSConfig)
            end
        end

    elseif cmd == "rename" then
        if not arg1 or not arg2 then
            self:_out("Usage: rename <old_name> <new_name>", _theme.error)
        else
            local target = VFS:FindChild(cwd, arg1)
            if not target then
                self:_out("Not found: " .. arg1, _theme.error)
            else
                VFS:Rename(target, arg2)
                self:_out("Renamed: " .. arg1 .. " -> " .. arg2, _theme.success)
                SaveSystem:Save(OSConfig)
            end
        end

    elseif cmd == "run" then
        if not arg1 then
            self:_out("Usage: run TextPad [filename]", _theme.error)
        elseif arg1:lower() == "textpad" then
            local fileNode = nil
            if arg2 then
                fileNode = VFS:FindChild(cwd, arg2)
                if not fileNode then
                    fileNode = VFS:CreateFile(cwd, arg2, BD.NT_TXT, "")
                    if fileNode then
                        self:_out("Created: " .. arg2, _theme.dim)
                        SaveSystem:Save(OSConfig)
                    end
                end
                if fileNode and fileNode.type ~= BD.NT_TXT then
                    self:_out(arg2 .. " is not a text file.", _theme.error)
                    fileNode = nil
                end
            else
                -- Create default file when no filename specified
                local defaultName = "untitled.txt"
                fileNode = VFS:CreateFile(cwd, defaultName, BD.NT_TXT, "")
                if fileNode then
                    self:_out("Created: " .. defaultName, _theme.dim)
                    SaveSystem:Save(OSConfig)
                end
            end
            if _onLaunch then _onLaunch("TextPad", fileNode) end
        else
            self:_out("Unknown app: " .. arg1, _theme.error)
            self:_out("Available apps: TextPad", _theme.dim)
        end

    elseif cmd == "theme" then
        if not arg1 then
            self:_out("Usage: theme <0-3>", _theme.error)
            self:_out("  0 = IARG Classic (cyan)", _theme.dim)
            self:_out("  1 = Amber Terminal", _theme.dim)
            self:_out("  2 = Green Matrix", _theme.dim)
            self:_out("  3 = Arctic (light)", _theme.dim)
        else
            local n = tonumber(arg1)
            if not n or not BD.THEMES[n] then
                self:_out("Invalid theme. Valid values: 0-3", _theme.error)
            else
                OSConfig.theme = n
                _theme = BD.THEMES[n]
                SaveSystem:Save(OSConfig)
                self:_out("Theme applied: " .. n, _theme.success)
                if _onLaunch then _onLaunch("__theme__", n) end
            end
        end

    else
        self:_out("Unknown command: '" .. cmd .. "'. Type 'help'.", _theme.error)
    end
end

---------------------------------------------------------------------------
-- Key input handler
-- name  : InputName with "KeyboardChip." prefix already stripped
-- shift : boolean, left or right shift held
-- ctrl  : boolean, left or right ctrl held

function CLI:HandleKey(name, shift, ctrl)
    -- Output buffer scroll navigation with Ctrl+arrows
    if ctrl then
        if name == "UpArrow" then
            -- Start smooth scroll up
            if outputScrollOffset < maxScrollOffset then
                scrollKey = "UpArrow"
                scrollTimer = 0
                scrollActive = true
                -- Immediate first step
                outputScrollOffset = outputScrollOffset + 1
            end
            return
        end
        if name == "DownArrow" then
            -- Start smooth scroll down
            if outputScrollOffset > 0 then
                scrollKey = "DownArrow"
                scrollTimer = 0
                scrollActive = true
                -- Immediate first step
                outputScrollOffset = outputScrollOffset - 1
            end
            return
        end
    end
    
    -- Command history (normal arrows) - NO REPEAT
    if name == "UpArrow" then
        if #history > 0 then
            histIdx   = math.min(histIdx + 1, #history)
            inputLine = history[histIdx]
            cursorPos = #inputLine
        end
        return
    end
    if name == "DownArrow" then
        if histIdx > 1 then
            histIdx   = histIdx - 1
            inputLine = history[histIdx]
            cursorPos = #inputLine
        elseif histIdx == 1 then
            histIdx = 0; inputLine = ""; cursorPos = 0
        end
        return
    end

    -- Cursor movement
    if name == "LeftArrow"  then cursorPos = math.max(0, cursorPos - 1);          return end
    if name == "RightArrow" then cursorPos = math.min(#inputLine, cursorPos + 1); return end
    if name == "Home"       then cursorPos = 0;                                    return end
    if name == "End"        then cursorPos = #inputLine;                           return end

    -- Backspace / Delete
    if name == "Backspace" then
        if cursorPos > 0 then
            inputLine = inputLine:sub(1, cursorPos-1) .. inputLine:sub(cursorPos+1)
            cursorPos = cursorPos - 1
        end
        return
    end
    if name == "Delete" then
        if cursorPos < #inputLine then
            inputLine = inputLine:sub(1, cursorPos) .. inputLine:sub(cursorPos+2)
        end
        return
    end

    -- Execute
    if name == "Return" or name == "KeypadEnter" then
        self:_execute(inputLine)
        inputLine = ""; cursorPos = 0
        return
    end

    -- Ctrl+L = clear
    if ctrl and name == "L" then
        outputBuf = {}
        outputScrollOffset = 0
        maxScrollOffset = 0
        return
    end

    -- Printable character
    local maxLen = BD.CLI_CHARS - #cwdStr() - 4
    if #inputLine < maxLen then
        local char = self:_inputToChar(name, shift)
        if char then
            inputLine = inputLine:sub(1, cursorPos) .. char .. inputLine:sub(cursorPos+1)
            cursorPos = cursorPos + 1
        end
    end
    
    -- Reset scroll on any other key
    scrollKey = nil
    scrollActive = false
    scrollTimer = 0
end

---------------------------------------------------------------------------
-- Handle key release events for smooth scroll

function CLI:HandleKeyRelease(name, shift, ctrl)
    -- Stop smooth scroll when Ctrl+arrow keys are released
    if ctrl and (name == "UpArrow" or name == "DownArrow") then
        if scrollKey == name then
            scrollKey = nil
            scrollActive = false
            scrollTimer = 0
        end
    end
end

---------------------------------------------------------------------------
-- Convert InputName to printable character
-- All symbol InputNames are taken directly from the official RG docs

function CLI:_inputToChar(name, shift)
    -- Letters A-Z
    local letters = {
        A="a",B="b",C="c",D="d",E="e",F="f",G="g",H="h",I="i",J="j",
        K="k",L="l",M="m",N="n",O="o",P="p",Q="q",R="r",S="s",T="t",
        U="u",V="v",W="w",X="x",Y="y",Z="z"
    }
    if letters[name] then
        return shift and name or letters[name]
    end

    -- Digits
    local nums = {
        Alpha0="0",Alpha1="1",Alpha2="2",Alpha3="3",Alpha4="4",
        Alpha5="5",Alpha6="6",Alpha7="7",Alpha8="8",Alpha9="9",
        Keypad0="0",Keypad1="1",Keypad2="2",Keypad3="3",Keypad4="4",
        Keypad5="5",Keypad6="6",Keypad7="7",Keypad8="8",Keypad9="9",
    }
    if nums[name] then return nums[name] end

    -- Symbols with dedicated InputName (from official KeyboardChip docs)
    local direct = {
        Space             = " ",
        Period            = ".",
        Comma             = ",",
        Minus             = "-",
        Slash             = "/",
        Backslash         = "\\",
        Semicolon         = ";",
        Quote             = "'",
        Equals            = "=",
        LeftBracket       = "[",
        RightBracket      = "]",
        BackQuote         = "`",
        Exclaim           = "!",
        DoubleQuote       = '"',
        Hash              = "#",
        Dollar            = "$",
        Percent           = "%",
        Ampersand         = "&",
        LeftParen         = "(",
        RightParen        = ")",
        Asterisk          = "*",
        Plus              = "+",
        Colon             = ":",
        Less              = "<",
        Greater           = ">",
        Question          = "?",
        At                = "@",
        Caret             = "^",
        Underscore        = "_",
        LeftCurlyBracket  = "{",
        Pipe              = "|",
        RightCurlyBracket = "}",
        Tilde             = "~",
        KeypadPeriod      = ".",
        KeypadDivide      = "/",
        KeypadMultiply    = "*",
        KeypadMinus       = "-",
        KeypadPlus        = "+",
        KeypadEquals      = "=",
    }
    return direct[name]
end

---------------------------------------------------------------------------
-- Update (cursor blink counter)

function CLI:Update()
    blinkT = blinkT + 1
    if blinkT >= BD.CURSOR_BLINK * 2 then blinkT = 0 end
    
    -- Handle smooth scroll
    if scrollActive and scrollKey then
        scrollTimer = scrollTimer + 1
        if scrollTimer >= scrollSpeed then
            if scrollKey == "UpArrow" then
                if outputScrollOffset < maxScrollOffset then
                    outputScrollOffset = outputScrollOffset + 1
                else
                    scrollActive = false  -- Stop at limit
                end
            elseif scrollKey == "DownArrow" then
                if outputScrollOffset > 0 then
                    outputScrollOffset = outputScrollOffset - 1
                else
                    scrollActive = false  -- Stop at limit
                end
            end
            scrollTimer = 0
        end
    end
end

---------------------------------------------------------------------------
-- Draw

function CLI:Draw()
    if not _video or not _theme then return end

    -- Use actual VideoChip dimensions (not BD constants)
    -- This ensures we draw within the real screen bounds
    local sw = _video.Width
    local sh = _video.Height

    -- Background
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(sw-1, sh-1), _theme.bg)

    -- Prompt is always 10px from the bottom
    local promptY   = sh - BD.CHAR_H - 2
    local promptStr = cwdStr() .. " " .. BD.PROMPT_PREFIX

    -- Separator
    _video:DrawLine(vec2(0, promptY - 2), vec2(sw-1, promptY - 2), _theme.dim)

    -- Output area above prompt
    local outputBottom = promptY - 4
    local visLines = math.floor((outputBottom - BD.CONTENT_Y) / BD.CHAR_H)

    -- Keep maxScrollOffset current every frame
    maxScrollOffset = math.max(0, #outputBuf - visLines)
    if outputScrollOffset > maxScrollOffset then outputScrollOffset = maxScrollOffset end

    -- Output buffer with scroll offset
    local startIdx = math.max(1, #outputBuf - visLines + 1 - outputScrollOffset)
    local endIdx = math.min(#outputBuf, startIdx + visLines - 1)
    for i = startIdx, endIdx do
        local entry = outputBuf[i]
        local lineY = BD.CONTENT_Y + (i - startIdx) * BD.CHAR_H + 2
        if lineY < outputBottom then
            tp(BD.CLI_X, lineY, entry.text, entry.color)
        end
    end

    -- Show scroll indicator if not at bottom
    if outputScrollOffset > 0 then
        local scrollIndicator = "^" .. outputScrollOffset .. " lines"
        tp(BD.SW - #scrollIndicator * BD.CHAR_W - 2, outputBottom - BD.CHAR_H, scrollIndicator, _theme.dim)
    end

    -- Prompt text
    tp(BD.CLI_X, promptY, promptStr, _theme.prompt)

    -- Input text
    local inputX = BD.CLI_X + #promptStr * BD.CHAR_W
    tp(inputX, promptY, inputLine, _theme.text)

    -- Blinking cursor
    if blinkT < BD.CURSOR_BLINK then
        local cx = inputX + cursorPos * BD.CHAR_W
        _video:DrawLine(
            vec2(cx, promptY),
            vec2(cx, promptY + BD.CHAR_H - 1),
            _theme.cursor)
    end

end

---------------------------------------------------------------------------

return CLI