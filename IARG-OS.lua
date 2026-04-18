---------------------------------------------------------------------------
-- IARG-OS.lua — Script principal. Enlazar al CPU0.
--
-- HARDWARE:
--   CPU0          este script
--   VideoChip0    pantalla 336×224
--   FlashMemory0  MEDIUM o LARGE
--   ROM           assets
--   KeyboardChip0  OPCIONAL, EventChannel1 del CPU0
--
-- TODOS LOS .lua Y .png deben estar importados como assets en el gadget.
-- Los módulos NO usan require() internamente — todo funciona por globales.
-- Solo este archivo hace require(), y solo al principio (nivel raíz).
--
-- ORDEN DE ARRANQUE CORRECTO:
--   1. Nivel raíz:  referencias hardware + require() de todos los módulos
--   2. update():    boot visual (SOLO APIs nativas, sin módulos del OS)
--   3. initOS():    llamado una vez al acabar el boot  inicializa módulos
--   4. update():    bucle normal del OS
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- 1. HARDWARE (nivel raíz  se ejecuta UNA VEZ al encender)

local video = gdt.VideoChip0
local flash = gdt.FlashMemory0
local rom   = gdt.ROM

local fontSheet  = rom.User.SpriteSheets["gameFont.png"]
local iconsSheet = nil
pcall(function() iconsSheet = rom.User.SpriteSheets["uiIcons.png"] end)

---------------------------------------------------------------------------
-- 2. MÓDULOS (require con extensión .lua, sin asignación local: usan globales)
--    El orden importa: los módulos que otros usan deben ir primero.

BD = require("BD.lua")  -- asignación explícita como global
Theme = require("Theme.lua")
Renderer = require("Renderer.lua")
InputManager = require("InputManager.lua")
VFS = require("VFS.lua")
SaveSystem = require("SaveSystem.lua")
UI = require("UI.lua")
VirtualKeyboard = require("VirtualKeyboard.lua")
Desktop = require("Desktop.lua")
TextPad = require("TextPad.lua")
PixelPaint = require("PixelPaint.lua")

---------------------------------------------------------------------------
-- 3. GLOBALES DEL OS

OSConfig  = { username = "Victor", theme = 0 }
activeApp = nil   -- nil = escritorio, o {type=string, obj=table}

---------------------------------------------------------------------------
-- 4. BOOT
--    REGLA CRÍTICA: durante el boot solo se usan las APIs nativas de RG
--    (video:FillRect, video:DrawSprite, ColorRGBA...).
--    Theme:Init(), Renderer:Init(), etc. NO se llaman aquí.
--    Motivo: Color() puede fallar si los módulos no están listos.

local bootTick = 0
local bootDone = false
local bootMsg  = ""

-- Dibuja un carácter de la fuente directamente (sin Renderer ni Tprint)
local function bootChar(x, y, ch, r, g, b, a)
    if not fontSheet then return end
    video:DrawSprite(
        vec2(x, y), fontSheet,
        ch:byte() % 32, math.floor(ch:byte() / 32),
        ColorRGBA(r, g, b, a or 255),
        color.clear)
end

-- Dibuja un string directamente (sin Renderer ni Tprint)
local function bootText(x, y, str, r, g, b, a)
    for i = 1, #str do
        bootChar(x + (i-1)*4, y, str:sub(i,i), r, g, b, a or 255)
    end
end

local function drawBoot()
    bootTick = bootTick + 1
    local t  = bootTick

    video:Clear(color.black)

    -- ── Fase negra ────────────────────────────────────────────────
    if t <= BD.BOOT_BLACK_END then return end

    -- ── Logo fade-in ──────────────────────────────────────────────
    if t <= BD.BOOT_PROGRESS_END then
        local alpha = math.min(255, math.floor(255 *
            (t - BD.BOOT_BLACK_END) /
            math.max(1, BD.BOOT_FADEIN_END - BD.BOOT_BLACK_END)))

        -- Logo "IARG-OS" centrado, letras 3× grande usando RasterSprite
        local logoStr  = "IARG-OS"
        local bigW     = 4 * 3   -- 12 px por letra
        local bigH     = 7 * 3   -- 21 px por letra
        local logoW    = #logoStr * bigW
        local logoX    = math.floor((BD.SW - logoW) / 2)
        local logoY    = math.floor(BD.SH / 2) - 24

        if fontSheet then
            for i = 1, #logoStr do
                local ch   = logoStr:sub(i, i)
                local sprX = ch:byte() % 32
                local sprY = math.floor(ch:byte() / 32)
                local cx   = logoX + (i-1) * bigW
                video:RasterSprite(
                    vec2(cx,       logoY),
                    vec2(cx+bigW,  logoY),
                    vec2(cx+bigW,  logoY+bigH),
                    vec2(cx,       logoY+bigH),
                    fontSheet, sprX, sprY,
                    ColorRGBA(80, 200, 255, alpha),
                    color.clear)
            end
        end

        -- Subtítulo pequeño
        local sub  = "Intelligent Autonomous RetroGadget OS"
        local subX = math.floor((BD.SW - #sub * 4) / 2)
        bootText(subX, logoY + bigH + 4, sub, 130, 130, 155, alpha)
    end

    -- ── Barra de progreso ─────────────────────────────────────────
    if t >= BD.BOOT_PROGRESS_START and t <= BD.BOOT_PROGRESS_END then
        local prog = (t - BD.BOOT_PROGRESS_START) /
                     math.max(1, BD.BOOT_PROGRESS_END - BD.BOOT_PROGRESS_START)
        local bx = 60
        local by = math.floor(BD.SH / 2) + 10
        local bw = BD.SW - 120
        local bh = 5

        -- Track
        video:FillRect(vec2(bx, by),       vec2(bx+bw-1, by+bh-1), Color(22, 22, 40))
        video:DrawRect(vec2(bx, by),       vec2(bx+bw-1, by+bh-1), Color(55, 55, 80))
        -- Fill
        local fw = math.max(0, math.floor((bw-2) * prog))
        if fw > 0 then
            video:FillRect(vec2(bx+1, by+1), vec2(bx+fw, by+bh-2), Color(80, 200, 255))
        end

        -- Mensaje de boot
        if BD.BOOT_MESSAGES[t] then bootMsg = BD.BOOT_MESSAGES[t] end
        if bootMsg ~= "" then
            local mx = math.floor((BD.SW - #bootMsg * 4) / 2)
            bootText(mx, by + 9, bootMsg, 130, 130, 155)
        end
    end

    -- ── Fade-out ──────────────────────────────────────────────────
    if t >= BD.BOOT_FADEOUT_START then
        local a = math.min(1.0, (t - BD.BOOT_FADEOUT_START) /
                  math.max(1, BD.BOOT_FADEOUT_END - BD.BOOT_FADEOUT_START))
        video:FillRect(vec2(0,0), vec2(BD.SW-1, BD.SH-1),
            ColorRGBA(0, 0, 0, math.floor(255 * a)))
    end

    if t >= BD.BOOT_DONE then bootDone = true end
end

---------------------------------------------------------------------------
-- 5. INICIALIZACIÓN DEL OS
--    Se llama UNA SOLA VEZ justo después de que bootDone = true.
--    Aquí sí es seguro llamar a Theme:Init() y al resto de módulos.

local osReady = false

local function initOS()
    -- Inicializar Theme PRIMERO (crea los objetos Color())
    Theme:Init()

    -- Luego el resto en orden de dependencia
    Renderer:Init(video, fontSheet)
    InputManager:Init(video)
    SaveSystem:Init(flash)

    -- Cargar datos guardados o inicializar VFS por defecto
    if flash.Usage == 0 then
        VFS:Init()
    else
        local cfg = SaveSystem:Load()
        if cfg then OSConfig = cfg end
        -- SaveSystem:Load ya llama a VFS:Deserialize internamente.
        -- Si devuelve nil (datos corruptos), también llama a VFS:Init.
    end

    -- Inicializar UI y escritorio
    UI:Init(iconsSheet)
    Desktop:Init(iconsSheet, function(node) launchApp(node) end)

    -- Callbacks de taskbar por defecto (escritorio activo)
    UI:SetTaskbarCallbacks(
        function()   -- Atrás
            if activeApp then
                if activeApp.obj and activeApp.obj.HandleBack then
                    activeApp.obj:HandleBack()
                end
            else
                if Desktop:CanGoBack() then Desktop:NavigateBack() end
            end
        end,
        function()   -- Home
            if activeApp then
                if activeApp.obj and activeApp.obj.HandleBack then
                    activeApp.obj:HandleBack()
                end
            end
        end
    )

    osReady = true
end

---------------------------------------------------------------------------
-- 6. LANZAR APPS

function launchApp(node)
    if not node then return end

    local function onAppClose()
        activeApp = nil
        UI:SetAppTitle("")
        UI:SetDirty(false)
        UI:SetTaskbarCallbacks(
            function()
                if activeApp then
                    if activeApp.obj and activeApp.obj.HandleBack then
                        activeApp.obj:HandleBack()
                    end
                else
                    if Desktop:CanGoBack() then Desktop:NavigateBack() end
                end
            end,
            function()
                if activeApp then
                    if activeApp.obj and activeApp.obj.HandleBack then
                        activeApp.obj:HandleBack()
                    end
                end
            end
        )
    end

    if node.name == "TextPad" then
        activeApp = { type = "textpad", obj = TextPad }
        TextPad:Init(onAppClose, node.targetFile)

    elseif node.name == "PixelPaint" then
        activeApp = { type = "pixelpaint", obj = PixelPaint }
        PixelPaint:Init(onAppClose, video, node.targetFile)
    end
end

---------------------------------------------------------------------------
-- 7. EVENTO DE TECLADO FÍSICO
--    CPU0  EventChannels[1] = KeyboardChip0  (configurar en Multitool)

function eventChannel1(sender, event)
    if event.Type == "KeyboardChipEvent" and event.ButtonDown then
        InputManager:PushKey(event.InputName)
    end
end

---------------------------------------------------------------------------
-- 8. UPDATE — bucle principal (llamado cada tick)

function update()

    -- ── Boot ─────────────────────────────────────────────────────
    if not bootDone then
        drawBoot()
        return
    end

    -- ── Init del OS (una sola vez, tras el boot) ──────────────────
    if not osReady then
        initOS()
        -- En el primer tick post-boot limpiamos la pantalla
        -- (el fade-out del boot dejó la pantalla en negro, perfecto)
        return
    end

    -- ═══════════════════════════════════════════════════════════════
    -- OS ACTIVO
    -- ═══════════════════════════════════════════════════════════════

    -- 1. Procesar teclas físicas del buffer
    local key = InputManager:PopKey()
    while key do
        local char = InputManager:KeyNameToChar(key)
        if char then
            if VirtualKeyboard:IsActive() then
                VirtualKeyboard:HandleKey(char)
            elseif activeApp and activeApp.obj and activeApp.obj.HandleKey then
                activeApp.obj:HandleKey(char)
            end
        end
        key = InputManager:PopKey()
    end

    -- 2. Limpiar hit zones del tick anterior
    InputManager:ClearZones()

    -- 3. Registrar hit zones
    --    Orden: fondo primero  encima después (las últimas tienen prioridad)
    if activeApp and activeApp.obj then
        activeApp.obj:RegisterZones()
    else
        Desktop:RegisterZones()
    end

    if UI:IsPopupActive() then
        UI:RegisterPopupZones()
    end

    UI:RegisterTaskbarZones()

    -- 4. Poll del touch (evalúa zonas y dispara callbacks)
    InputManager:Poll()

    -- 5. Update lógico
    if activeApp and activeApp.obj and activeApp.obj.Update then
        activeApp.obj:Update()
    else
        Desktop:Update()
    end

    -- ── RENDER ────────────────────────────────────────────────────

    -- 6. Asegurar que el VideoChip dibuja en pantalla (no en RenderBuffer)
    video:RenderOnScreen()

    -- 7. Limpiar pantalla
    Renderer:Clear()

    -- 8. Contenido principal
    if activeApp and activeApp.obj then
        activeApp.obj:Draw()
    else
        Desktop:Draw()
    end

    -- 9. Chrome del OS (siempre encima del contenido)
    UI:DrawTopbar()
    UI:DrawTaskbar()

    -- 10. Popup modal (encima de absolutamente todo)
    if UI:IsPopupActive() then
        UI:DrawPopup()
    end
end