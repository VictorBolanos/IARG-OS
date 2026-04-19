---------------------------------------------------------------------------
-- IARG-OS.lua — Script principal. Enlazar al CPU0.
--
-- HARDWARE: CPU0, VideoChip0, FlashMemory0, ROM, RealityChip0, KeyboardChip0
-- ── Hardware ────────────────────────────────────────────────────────────
local rom = gdt.ROM
local video    = gdt.VideoChip0
local flash    = gdt.FlashMemory0
local rom      = gdt.ROM
local reality  = gdt.RealityChip
local keyboard = gdt.KeyboardChip0

-- ASSETS CÓDIGO: BD.lua, VFS.lua, SaveSystem.lua, Topbar.lua, CLI.lua, TextPad.lua
-- ASSETS SPR: gameFont.png  (nombre EXACTO en el Multitool, con extensión)


pcall(function() sprLogo = rom.User.SpriteSheets["sprOsLogoSmall.png"] end)
pcall(function() sprSys  = rom.User.SpriteSheets["sprSystem.png"]      end)
---------------------------------------------------------------------------

-- ── Requires a nivel raíz ───────────────────────────────────────────────
local BD         = require("BD.lua")
local VFS        = require("VFS.lua")
local SaveSystem = require("SaveSystem.lua")
local Topbar     = require("Topbar.lua")
local CLI        = require("CLI.lua")
local TextPad    = require("TextPad.lua")

-- ── Sprites — carga segura con pcall para que un sprite faltante
--    no pete todo el script ──────────────────────────────────────────────
local font      = nil
local sprLogo   = nil   -- sprOsLogoSmall.png
local sprSys    = nil   -- sprSystem.png
-- Intenta fuente de usuario, si no existe usa la del sistema
pcall(function() font = rom.User.SpriteSheets["gameFont.png"] end)
if not font then
    font = rom.System.SpriteSheets["StandardFont"]
    -- StandardFont es 8x8, ajustar BD para que el texto se espacie bien
    BD.CHAR_W = 8
    BD.CHAR_H = 8
end

-- ── Estado global ────────────────────────────────────────────────────────
OSConfig  = { username = "user", theme = 0 }
activeApp = nil

-- ── Flags de ciclo de vida ───────────────────────────────────────────────
local bootTick = 0
local bootDone = false
local bootMsg  = ""
local osReady  = false

---------------------------------------------------------------------------
-- Helper de texto para el boot (solo usa DrawSprite, nil-safe)

local function btext(x, y, txt, r, g, b)
    if not font then return end
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        video:DrawSprite(
            vec2(x + (i-1)*BD.CHAR_W, y),
            font,
            ch:byte() % 32,
            math.floor(ch:byte() / 32),
            Color(r, g, b),
            color.clear)
    end
end

---------------------------------------------------------------------------
-- Boot visual — no usa RasterSprite para evitar el error con font nil

local function drawBoot()
    bootTick = bootTick + 1
    local t  = bootTick
    video:Clear(color.black)

    if t <= BD.BOOT_BLACK_END then return end

    -- Alpha del fade-in
    local alpha255 = math.min(255, math.floor(255 *
        (t - BD.BOOT_BLACK_END) /
        math.max(1, BD.BOOT_FADEIN_END - BD.BOOT_BLACK_END)))

    -- Logo "IARG-OS" — dibujado con DrawSprite normal (tamaño 1:1)
    -- centrado verticalmente en el centro de la pantalla
    local logo  = "IARG-OS"
    local logoW = #logo * 4
    local logoX = math.floor((BD.SW - logoW) / 2)
    local logoY = math.floor(BD.SH / 2) - 16

    btext(logoX, logoY, logo, 80, 200, 255)

    -- Subtítulo
    local sub  = "CLI v0.1 - Intelligent Autonomous RetroGadget OS"
    local subX = math.floor((BD.SW - #sub * 4) / 2)
    btext(subX, logoY + 10, sub, 130, 130, 155)

    -- Barra de progreso
    if t >= BD.BOOT_PROGRESS_START and t <= BD.BOOT_PROGRESS_END then
        local prog = (t - BD.BOOT_PROGRESS_START) /
                     math.max(1, BD.BOOT_PROGRESS_END - BD.BOOT_PROGRESS_START)
        local bx, by = 60, math.floor(BD.SH / 2) + 6
        local pw, ph = BD.SW - 120, 5

        video:FillRect(vec2(bx,   by),     vec2(bx+pw-1, by+ph-1), Color(22,22,40))
        video:DrawRect(vec2(bx,   by),     vec2(bx+pw-1, by+ph-1), Color(55,55,80))
        local fw = math.max(0, math.floor((pw - 2) * prog))
        if fw > 0 then
            video:FillRect(vec2(bx+1, by+1), vec2(bx+fw, by+ph-2), Color(80,200,255))
        end

        if BD.BOOT_MESSAGES[t] then bootMsg = BD.BOOT_MESSAGES[t] end
        btext(math.floor((BD.SW - #bootMsg*4)/2), by + 9, bootMsg, 130, 130, 155)
    end

    -- Fade-out final
    if t >= BD.BOOT_FADEOUT_START then
        local a = math.min(1.0,
            (t - BD.BOOT_FADEOUT_START) /
            math.max(1, BD.BOOT_FADEOUT_END - BD.BOOT_FADEOUT_START))
        video:FillRect(vec2(0,0), vec2(BD.SW-1, BD.SH-1),
            ColorRGBA(0, 0, 0, math.floor(255 * a)))
    end

    if t >= BD.BOOT_DONE then bootDone = true end
end

---------------------------------------------------------------------------
-- Init del OS (un tick tras el boot)

local function initOS()
    SaveSystem:Init(flash)

    if flash.Usage == 0 then
        VFS:Init()
    else
        local cfg = SaveSystem:Load()
        if cfg then OSConfig = cfg end
    end

    local theme = BD.THEMES[OSConfig.theme] or BD.THEMES[0]

    Topbar:Init(video, font, sprLogo, sprSys, reality)
    Topbar:SetTheme(theme)

    CLI:Init(video, font, theme, keyboard, function(app, data)
        if app == "TextPad" then
            activeApp = "textpad"
            local t   = BD.THEMES[OSConfig.theme] or BD.THEMES[0]
            TextPad:Init(video, font, t, data, function()
                activeApp = nil
                CLI:_out("TextPad cerrado.",
                    (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).dim)
            end)
        elseif app == "__theme__" then
            local nt = BD.THEMES[data] or BD.THEMES[0]
            Topbar:SetTheme(nt)
            CLI:SetTheme(nt)
        end
    end)

    osReady = true
end

---------------------------------------------------------------------------
-- EventChannel1 — KeyboardChip0 enlazado al CPU0 EventChannel 1

function eventChannel1(sender, event)
    if not osReady then return end
    if event.Type ~= "KeyboardChipEvent" then return end
    if not event.ButtonDown then return end

    local shift = keyboard:GetButton("LeftShift").ButtonState
               or keyboard:GetButton("RightShift").ButtonState
    local ctrl  = keyboard:GetButton("LeftControl").ButtonState
               or keyboard:GetButton("RightControl").ButtonState

    if activeApp == "textpad" then
        TextPad:HandleKey(event.InputName, shift, ctrl)
    else
        CLI:HandleKey(event.InputName)
    end
end

---------------------------------------------------------------------------
-- Update

function update()
    -- Boot
    if not bootDone then
        drawBoot()
        return
    end

    -- Init (un solo tick)
    if not osReady then
        initOS()
        return
    end

    -- Lógica
    if activeApp == "textpad" then
        TextPad:Update()
    else
        CLI:Update()
    end

    -- Render
    video:RenderOnScreen()
    video:Clear(color.black)

    -- Topbar siempre presente
    local cwdNode = CLI:GetCWD()
    local cwdName = (cwdNode and cwdNode.parent) and cwdNode.name or ""
    Topbar:Draw(cwdName)

    -- Contenido
    if activeApp == "textpad" then
        TextPad:Draw()
    else
        CLI:Draw()
    end
end