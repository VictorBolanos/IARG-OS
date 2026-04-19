---------------------------------------------------------------------------
-- CLI.lua — Interfaz de línea de comandos de IARG-OS
--
-- Comandos disponibles:
--   ls              — listar contenido del directorio actual
--   cd <nombre>     — entrar en carpeta
--   cd ..           — subir un nivel
--   mkdir <nombre>  — crear carpeta
--   touch <nombre>  — crear archivo de texto vacío
--   rm <nombre>     — eliminar archivo o carpeta vacía
--   rename <v> <n>  — renombrar
--   run TextPad [archivo] — abrir editor de texto
--   theme <0-3>     — cambiar tema visual
--   help            — mostrar ayuda
--   clear           — limpiar pantalla
--
-- Input: KeyboardChip (evento en eventChannel1 de IARG-OS.lua)
-- Shift/Ctrl se detectan con GetButton().ButtonState
---------------------------------------------------------------------------

local BD = require("BD.lua")
local VFS = require("VFS.lua")
local SaveSystem = require("SaveSystem.lua")
CLI = {}

local _video    = nil
local _font     = nil
local _theme    = nil
local _keyboard = nil   -- KeyboardChip0 para leer Shift/Ctrl en tiempo real

-- Output buffer: tabla de {text=string, color=colorObj}
local outputBuf  = {}
local MAX_OUTPUT = 200   -- máx líneas en buffer

-- Input actual
local inputLine  = ""    -- lo que el usuario está escribiendo
local cursorPos  = 0     -- posición del cursor en inputLine
local blinkT     = 0

-- Historial de comandos
local history    = {}
local histIdx    = 0     -- 0 = no navegando historial

-- Directorio actual
local cwd        = nil   -- nodo VFS del directorio actual

-- Callback hacia IARG-OS para lanzar apps
local _onLaunch  = nil   -- función(appName, fileNode)

-- Estado: "cli" | "textpad"
-- (el switch lo maneja IARG-OS, aquí solo exponemos el estado)

---------------------------------------------------------------------------
-- Tprint local

local function tp(x, y, txt, col)
    if not _font or not _video then return end
    for i=1,#txt do
        local ch=txt:sub(i,i)
        _video:DrawSprite(vec2(x+(i-1)*BD.CHAR_W, y), _font,
            ch:byte()%32, math.floor(ch:byte()/32), col, color.clear)
    end
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

    -- Mensaje de bienvenida
    self:_out("IARG-OS v0.1 — Modo Consola", _theme.success)
    self:_out("Escribe 'help' para ver los comandos.", _theme.dim)
    self:_out("", _theme.text)
end

function CLI:SetTheme(t)
    _theme = t
end

function CLI:GetCWD() return cwd end

---------------------------------------------------------------------------
-- Añadir línea al output

function CLI:_out(txt, col)
    col = col or _theme.output
    -- Word-wrap manual
    local maxCols = BD.CLI_CHARS
    if #txt == 0 then
        table.insert(outputBuf, {text="", color=col})
    else
        while #txt > 0 do
            local chunk = txt:sub(1, maxCols)
            table.insert(outputBuf, {text=chunk, color=col})
            txt = txt:sub(maxCols+1)
        end
    end
    -- Limitar buffer
    while #outputBuf > MAX_OUTPUT do
        table.remove(outputBuf, 1)
    end
end

---------------------------------------------------------------------------
-- Helpers de formato

local function pad2(n) return string.format("%02d", n) end

local function cwdStr()
    if not cwd then return "/" end
    local p = VFS:GetPath(cwd)
    -- Mostrar solo desde root/
    p = p:gsub("^root", "~")
    return p
end

---------------------------------------------------------------------------
-- Ejecutar comando

function CLI:_execute(cmdStr)
    -- Guardar en historial
    if cmdStr ~= "" then
        table.insert(history, 1, cmdStr)
        if #history > 50 then table.remove(history) end
    end
    histIdx = 0

    -- Mostrar el comando en el output
    self:_out(cwdStr().." "..BD.PROMPT_PREFIX..cmdStr, _theme.prompt)

    if cmdStr == "" then return end

    -- Parsear: primer token = comando, resto = argumentos
    local parts = {}
    for p in cmdStr:gmatch("%S+") do table.insert(parts, p) end
    local cmd  = parts[1]:lower()
    local arg1 = parts[2]
    local arg2 = parts[3]

    -- ── COMANDOS ──────────────────────────────────────────────────────

    if cmd == "clear" or cmd == "cls" then
        outputBuf = {}

    elseif cmd == "help" then
        self:_out("Comandos disponibles:", _theme.success)
        self:_out("  ls              Listar directorio actual", _theme.output)
        self:_out("  cd <nombre>     Entrar en carpeta", _theme.output)
        self:_out("  cd ..           Subir un nivel", _theme.output)
        self:_out("  mkdir <nombre>  Crear carpeta", _theme.output)
        self:_out("  touch <nombre>  Crear archivo de texto", _theme.output)
        self:_out("  rm <nombre>     Eliminar archivo o carpeta", _theme.output)
        self:_out("  rename <v> <n>  Renombrar elemento", _theme.output)
        self:_out("  run TextPad [archivo]  Abrir editor", _theme.output)
        self:_out("  theme <0-3>     Cambiar tema visual", _theme.output)
        self:_out("  help            Mostrar esta ayuda", _theme.output)
        self:_out("  clear           Limpiar pantalla", _theme.output)

    elseif cmd == "ls" then
        local children = VFS:GetChildren(cwd)
        if #children == 0 then
            self:_out("  (vacio)", _theme.dim)
        else
            for _, node in ipairs(children) do
                local suffix = node.type == BD.NT_FOLDER and "/" or ""
                local info   = ""
                if node.type == BD.NT_TXT and node.data then
                    info = "  ["..#node.data.." ch]"
                end
                local col = node.type == BD.NT_FOLDER and _theme.prompt or _theme.text
                self:_out("  "..node.name..suffix..info, col)
            end
        end

    elseif cmd == "cd" then
        if not arg1 then
            self:_out("Uso: cd <nombre> | cd ..", _theme.error)
        elseif arg1 == ".." then
            if cwd.parent then
                cwd = cwd.parent
            else
                self:_out("Ya estas en el directorio raiz.", _theme.dim)
            end
        elseif arg1 == "~" or arg1 == "/" then
            cwd = VFS:GetRoot()
        else
            local target = VFS:FindChild(cwd, arg1)
            if not target then
                self:_out("No existe: "..arg1, _theme.error)
            elseif target.type ~= BD.NT_FOLDER then
                self:_out(arg1.." no es una carpeta.", _theme.error)
            else
                cwd = target
            end
        end

    elseif cmd == "mkdir" then
        if not arg1 or arg1 == "" then
            self:_out("Uso: mkdir <nombre>", _theme.error)
        else
            local existing = VFS:FindChild(cwd, arg1)
            if existing then
                self:_out("Ya existe: "..arg1, _theme.error)
            else
                local newNode = VFS:CreateFolder(cwd, arg1)
                if newNode then
                    self:_out("Carpeta creada: "..arg1, _theme.success)
                    SaveSystem:Save(OSConfig)
                else
                    self:_out("Error: limite de nodos alcanzado.", _theme.error)
                end
            end
        end

    elseif cmd == "touch" then
        if not arg1 or arg1 == "" then
            self:_out("Uso: touch <nombre>", _theme.error)
        else
            local existing = VFS:FindChild(cwd, arg1)
            if existing then
                self:_out("Ya existe: "..arg1, _theme.error)
            else
                local newNode = VFS:CreateFile(cwd, arg1, BD.NT_TXT, "")
                if newNode then
                    self:_out("Archivo creado: "..arg1, _theme.success)
                    SaveSystem:Save(OSConfig)
                else
                    self:_out("Error: limite de nodos alcanzado.", _theme.error)
                end
            end
        end

    elseif cmd == "rm" then
        if not arg1 then
            self:_out("Uso: rm <nombre>", _theme.error)
        else
            local target = VFS:FindChild(cwd, arg1)
            if not target then
                self:_out("No existe: "..arg1, _theme.error)
            elseif target.type == BD.NT_FOLDER and #target.children > 0 then
                self:_out("La carpeta no esta vacia. Usa 'rm -r' (no implementado).", _theme.error)
            else
                VFS:Delete(target)
                self:_out("Eliminado: "..arg1, _theme.success)
                SaveSystem:Save(OSConfig)
            end
        end

    elseif cmd == "rename" then
        if not arg1 or not arg2 then
            self:_out("Uso: rename <nombre_actual> <nombre_nuevo>", _theme.error)
        else
            local target = VFS:FindChild(cwd, arg1)
            if not target then
                self:_out("No existe: "..arg1, _theme.error)
            else
                VFS:Rename(target, arg2)
                self:_out("Renombrado: "..arg1.."  "..arg2, _theme.success)
                SaveSystem:Save(OSConfig)
            end
        end

    elseif cmd == "run" then
        if not arg1 then
            self:_out("Uso: run TextPad [nombre_archivo]", _theme.error)
        elseif arg1:lower() == "textpad" then
            -- Buscar o crear archivo
            local fileNode = nil
            if arg2 then
                fileNode = VFS:FindChild(cwd, arg2)
                if not fileNode then
                    -- Crear si no existe
                    fileNode = VFS:CreateFile(cwd, arg2, BD.NT_TXT, "")
                    if fileNode then
                        self:_out("Creado: "..arg2, _theme.dim)
                        SaveSystem:Save(OSConfig)
                    end
                end
                if fileNode and fileNode.type ~= BD.NT_TXT then
                    self:_out(arg2.." no es un archivo de texto.", _theme.error)
                    fileNode = nil
                end
            end
            if _onLaunch then
                _onLaunch("TextPad", fileNode)
            end
        else
            self:_out("Aplicacion desconocida: "..arg1, _theme.error)
            self:_out("Apps disponibles: TextPad", _theme.dim)
        end

    elseif cmd == "theme" then
        if not arg1 then
            self:_out("Uso: theme <0-3>", _theme.error)
            self:_out("  0 = IARG Classic (cyan)", _theme.dim)
            self:_out("  1 = Amber Terminal", _theme.dim)
            self:_out("  2 = Green Matrix", _theme.dim)
            self:_out("  3 = Arctic (claro)", _theme.dim)
        else
            local n = tonumber(arg1)
            if not n or not BD.THEMES[n] then
                self:_out("Tema invalido. Valores: 0-3", _theme.error)
            else
                OSConfig.theme = n
                _theme = BD.THEMES[n]
                SaveSystem:Save(OSConfig)
                self:_out("Tema aplicado: "..n, _theme.success)
                -- Notificar a IARG-OS para que actualice Topbar
                if _onLaunch then _onLaunch("__theme__", n) end
            end
        end

    else
        self:_out("Comando desconocido: '"..cmd.."'. Escribe 'help'.", _theme.error)
    end
end

---------------------------------------------------------------------------
-- Input de teclado (llamado desde IARG-OS.lua en eventChannel1)

function CLI:HandleKey(inputName)
    if not _keyboard then return end

    local shift = _keyboard:GetButton("LeftShift").ButtonState
                or _keyboard:GetButton("RightShift").ButtonState
    local ctrl  = _keyboard:GetButton("LeftControl").ButtonState
                or _keyboard:GetButton("RightControl").ButtonState

    -- Historial: flecha arriba/abajo
    if inputName == "UpArrow" then
        if #history > 0 then
            histIdx = math.min(histIdx + 1, #history)
            inputLine = history[histIdx]
            cursorPos = #inputLine
        end
        return
    end

    if inputName == "DownArrow" then
        if histIdx > 1 then
            histIdx   = histIdx - 1
            inputLine = history[histIdx]
            cursorPos = #inputLine
        elseif histIdx == 1 then
            histIdx   = 0
            inputLine = ""
            cursorPos = 0
        end
        return
    end

    -- Navegación del cursor
    if inputName == "LeftArrow" then
        cursorPos = math.max(0, cursorPos - 1); return
    end
    if inputName == "RightArrow" then
        cursorPos = math.min(#inputLine, cursorPos + 1); return
    end
    if inputName == "Home" then cursorPos = 0; return end
    if inputName == "End"  then cursorPos = #inputLine; return end

    -- Backspace
    if inputName == "Backspace" then
        if cursorPos > 0 then
            inputLine = inputLine:sub(1, cursorPos-1)..inputLine:sub(cursorPos+1)
            cursorPos = cursorPos - 1
        end
        return
    end

    -- Delete
    if inputName == "Delete" then
        if cursorPos < #inputLine then
            inputLine = inputLine:sub(1, cursorPos)..inputLine:sub(cursorPos+2)
        end
        return
    end

    -- Enter  ejecutar
    if inputName == "Return" then
        self:_execute(inputLine)
        inputLine = ""
        cursorPos = 0
        return
    end

    -- Ctrl+L  clear
    if ctrl and inputName == "L" then
        outputBuf = {}; return
    end

    -- Carácter imprimible
    if #inputLine < BD.CLI_CHARS - #cwdStr() - 4 then
        local char = self:_inputToChar(inputName, shift)
        if char then
            inputLine = inputLine:sub(1, cursorPos)..char..inputLine:sub(cursorPos+1)
            cursorPos = cursorPos + 1
        end
    end
end

---------------------------------------------------------------------------
-- Convierte InputName a char (igual que TextPad)

function CLI:_inputToChar(name, shift)
    local letters={A="a",B="b",C="c",D="d",E="e",F="f",G="g",H="h",
        I="i",J="j",K="k",L="l",M="m",N="n",O="o",P="p",Q="q",R="r",
        S="s",T="t",U="u",V="v",W="w",X="x",Y="y",Z="z"}
    if letters[name] then
        return shift and letters[name]:upper() or letters[name]
    end
    local nums={Alpha0="0",Alpha1="1",Alpha2="2",Alpha3="3",Alpha4="4",
        Alpha5="5",Alpha6="6",Alpha7="7",Alpha8="8",Alpha9="9"}
    if nums[name] then
        if shift then
            local s={["0"]=")",["1"]="!",["2"]="@",["3"]="#",["4"]="$",
                ["5"]="%",["6"]="^",["7"]="&",["8"]="*",["9"]="("}
            return s[nums[name]] or nums[name]
        end
        return nums[name]
    end
    local syms={Space=" ",Period=".",Comma=",",Minus="-",Slash="/",
        Backslash="\\",Semicolon=";",Quote="'",LeftBracket="[",
        RightBracket="]",Equals="=",BackQuote="`"}
    if shift then
        local s={Period=">",Comma="<",Minus="_",Slash="?",Semicolon=":",
            Quote='"',LeftBracket="{",RightBracket="}",Equals="+",
            BackQuote="~",Backslash="|"}
        if s[name] then return s[name] end
    end
    return syms[name]
end

---------------------------------------------------------------------------
-- Update (parpadeo cursor)

function CLI:Update()
    blinkT = blinkT + 1
    if blinkT >= BD.CURSOR_BLINK * 2 then blinkT = 0 end
end

---------------------------------------------------------------------------
-- Draw

function CLI:Draw()
    if not _video or not _theme then return end

    -- Fondo completo del área de contenido
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(BD.SW-1, BD.SH-1), _theme.bg)

    -- Calcular cuántas líneas caben
    local promptH  = BD.CHAR_H + 4          -- alto del prompt fijo al fondo
    local areaH    = BD.SH - BD.CONTENT_Y - promptH - 2
    local visLines = math.floor(areaH / BD.CHAR_H)

    -- Mostrar las últimas N líneas del output
    local startIdx = math.max(1, #outputBuf - visLines + 1)
    for i = startIdx, #outputBuf do
        local entry = outputBuf[i]
        local lineY = BD.CONTENT_Y + (i - startIdx) * BD.CHAR_H + 2
        tp(BD.CLI_X, lineY, entry.text, entry.color)
    end

    -- Separador antes del prompt
    local sepY = BD.SH - promptH - 2
    _video:DrawLine(vec2(0, sepY), vec2(BD.SW-1, sepY), _theme.dim)

    -- Prompt
    local promptY  = BD.SH - promptH + 1
    local promptStr = cwdStr().." "..BD.PROMPT_PREFIX
    tp(BD.CLI_X, promptY, promptStr, _theme.prompt)

    -- Input con cursor
    local inputX = BD.CLI_X + #promptStr * BD.CHAR_W
    tp(inputX, promptY, inputLine, _theme.text)

    -- Cursor parpadeante
    if blinkT < BD.CURSOR_BLINK then
        local cx = inputX + cursorPos * BD.CHAR_W
        _video:DrawLine(vec2(cx, promptY), vec2(cx, promptY+BD.CHAR_H-1), _theme.cursor)
    end
end

---------------------------------------------------------------------------

return CLI