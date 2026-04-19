---------------------------------------------------------------------------
-- TextPad.lua — Editor de texto para el CLI
-- Ocupa toda el área de contenido. Input por KeyboardChip.
-- Comandos internos: Esc=salir, Ctrl+S=guardar (implementado via LedButton)
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

-- Dimensiones del área de edición
local EDIT_X  = 2
local EDIT_Y  = BD.CONTENT_Y + 2
local EDIT_W  = BD.SW - 4
local VIS     = BD.TP_LINES_VIS   -- líneas visibles
local MAXCOLS = BD.TP_CHARS_W     -- cols por línea

---------------------------------------------------------------------------

function TextPad:Init(videoChip, font, themeData, fileNode, onCloseCb)
    _video   = videoChip
    _font    = font
    _theme   = themeData
    _onClose = onCloseCb
    node     = fileNode
    dirty    = false
    blinkT   = 0

    -- Cargar contenido del nodo
    local content = (node and node.data) or ""
    lines = {}
    -- Dividir por \n
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
-- Asegura que curLine está dentro del scroll visible

function TextPad:_ensureVisible()
    if curLine < scrollTop then
        scrollTop = curLine
    elseif curLine >= scrollTop + VIS then
        scrollTop = curLine - VIS + 1
    end
    if scrollTop < 1 then scrollTop = 1 end
end

---------------------------------------------------------------------------
-- Serializa lines a string

function TextPad:_serialize()
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Guardar

function TextPad:Save()
    if node then
        node.data = self:_serialize()
        dirty = false
        SaveSystem:Save(OSConfig)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Input de teclado — llamado desde IARG-OS cuando llega un KeyboardChipEvent

function TextPad:HandleKey(inputName, shift, ctrl)
    -- Esc  salir
    if inputName == "Escape" then
        if dirty then
            -- guardar automáticamente al salir
            self:Save()
        end
        if _onClose then _onClose(dirty) end
        return
    end

    -- Ctrl+S  guardar
    if ctrl and inputName == "S" then
        self:Save(); return
    end

    -- Navegación
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

    -- Enter  nueva línea
    if inputName == "Return" then
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

    -- Tab  4 espacios
    if inputName == "Tab" then
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

    -- Carácter imprimible
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

---------------------------------------------------------------------------
-- Convierte InputName a carácter

function TextPad:_inputToChar(name, shift)
    -- Letras
    local letters={A="a",B="b",C="c",D="d",E="e",F="f",G="g",H="h",
        I="i",J="j",K="k",L="l",M="m",N="n",O="o",P="p",Q="q",R="r",
        S="s",T="t",U="u",V="v",W="w",X="x",Y="y",Z="z"}
    if letters[name] then
        return shift and letters[name]:upper() or letters[name]
    end
    -- Números
    local nums={Alpha0="0",Alpha1="1",Alpha2="2",Alpha3="3",Alpha4="4",
        Alpha5="5",Alpha6="6",Alpha7="7",Alpha8="8",Alpha9="9"}
    if nums[name] then
        if shift then
            local shifted={["0"]=")",["1"]="!",["2"]="@",["3"]="#",["4"]="$",
                ["5"]="%",["6"]="^",["7"]="&",["8"]="*",["9"]="("}
            return shifted[nums[name]] or nums[name]
        end
        return nums[name]
    end
    -- Símbolos
    local syms={Space=" ",Period=".",Comma=",",Minus="-",
        Slash="/",Backslash="\\",Semicolon=";",Quote="'",
        LeftBracket="[",RightBracket="]",Equals="=",BackQuote="`"}
    if shift then
        local shifted={Period=">",Comma="<",Minus="_",Slash="?",
            Semicolon=":",Quote="\"",LeftBracket="{",RightBracket="}",
            Equals="+",BackQuote="~",Backslash="|"}
        if shifted[name] then return shifted[name] end
    end
    if syms[name] then return syms[name] end
    return nil
end

---------------------------------------------------------------------------
-- Update (parpadeo cursor)

function TextPad:Update()
    blinkT = blinkT + 1
    if blinkT >= BD.CURSOR_BLINK * 2 then blinkT = 0 end
end

---------------------------------------------------------------------------
-- Draw

function TextPad:Draw()
    if not _video or not _theme or not _font then return end

    -- Fondo
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(BD.SW-1, BD.SH-1), _theme.bg)

    -- Header del editor
    local fname = node and node.name or "sin titulo"
    if dirty then fname = fname.." *" end
    local header = "-- TextPad: "..fname.." -- [ESC=salir Ctrl+S=guardar]"
    self:_tprint(EDIT_X, BD.CONTENT_Y+1, header, _theme.dim)
    _video:DrawLine(vec2(0, BD.CONTENT_Y+9), vec2(BD.SW-1, BD.CONTENT_Y+9), _theme.dim)

    -- Líneas visibles
    local startY = BD.CONTENT_Y + 12
    for i = 1, VIS do
        local li = i + scrollTop - 1
        if li > #lines then break end
        local lineText = lines[li] or ""
        local ty = startY + (i-1) * BD.CHAR_H

        -- Número de línea (dim)
        local numStr = string.format("%3d", li)
        self:_tprint(EDIT_X, ty, numStr, _theme.dim)

        -- Contenido de la línea (truncado si es muy largo)
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

    -- Barra de estado abajo
    local statY = BD.SH - BD.CHAR_H - 2
    _video:FillRect(vec2(0, statY-1), vec2(BD.SW-1, BD.SH-1), _theme.topbar)
    local stat = "Ln "..curLine.."/"..#lines.."  Col "..curCol
              .."  ["..#self:_serialize().."/"..BD.TP_MAX_CHARS.." ch]"
    self:_tprint(EDIT_X, statY, stat, _theme.dim)
end

---------------------------------------------------------------------------
-- tprint local

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