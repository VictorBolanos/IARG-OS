---------------------------------------------------------------------------
-- IARG-OS.lua -- Main script. Link to CPU0.
--
-- HARDWARE:
--   CPU0          -- this script
--   VideoChip0    -- screen 336x224
--   FlashMemory0  -- MEDIUM or LARGE
--   ROM           -- assets
--   RealityChip0  -- real-time clock
--   KeyboardChip0 -- keyboard (CPU0 EventChannel1)
--
-- CODE ASSETS (.lua):
--   BD.lua, VFS.lua, SaveSystem.lua, Topbar.lua, CLI.lua, TextPad.lua
--
-- ASSETS SPRITESHEET (.png):
--   fontPrincipal.png  -- text font 4x7 px (Tprint)
--   sprOsLogoSmall.png -- logo 24x12 px
--   sprSystem.png      -- 9x9 px icons (clock, folder, file)
---------------------------------------------------------------------------

-- Root-level requires
-- Load all modules as globals so they are visible to each other
BD         = require("BD.lua")
VFS        = require("VFS.lua")
SaveSystem = require("SaveSystem.lua")
Topbar     = require("Topbar.lua")
CLI        = require("CLI.lua")
TextPad    = require("TextPad.lua")
AIChat     = require("AIChat.lua")

-- Hardware
local video    = gdt.VideoChip0
local flash    = gdt.FlashMemory0
local rom      = gdt.ROM
local reality  = gdt.RealityChip
local keyboard = gdt.KeyboardChip0
local wifi     = gdt.Wifi0

-- Sprites -- safe load with pcall
local font    = nil
local sprLogo = nil
local sprSys  = nil

pcall(function() font    = rom.User.SpriteSheets["fontPrincipal.png"]  end)
pcall(function() sprLogo = rom.User.SpriteSheets["sprOsLogoSmall.png"] end)
pcall(function() sprSys  = rom.User.SpriteSheets["sprSystem.png"]      end)

-- Fallback to system StandardFont if user font not found
-- StandardFont is 8x8 -- adjust CHAR_W/H accordingly
if not font then
    pcall(function() font = rom.System.SpriteSheets["StandardFont"] end)
    if font then
        BD.CHAR_W = 8
        BD.CHAR_H = 8
    end
end

-- Global OS state
OSConfig  = { username = "user", theme = 0 }
activeApp = nil   -- nil = CLI, "textpad", "aichat"

-- Lifecycle flags
local bootTick = 0
local bootDone = false
local bootMsg  = ""
local osReady  = false

---------------------------------------------------------------------------
-- Tprint for boot screen -- same logic as Utils:Tprint from reference project
-- Uses font and video directly without module dependencies

local function Tprint(x, y, txt, r, g, b, maxWidth)
    if not font then return end
    maxWidth = maxWidth or 80

    -- Word wrap
    local function wrap(text, maxC)
        local lines = {}
        local cur = ""
        for para in text:gmatch("[^\n]+") do
            local words = {}
            for w in para:gmatch("%S+") do table.insert(words, w) end
            for _, w in ipairs(words) do
                local test = #cur > 0 and (cur.." "..w) or w
                if #test > maxC then
                    if #cur > 0 then table.insert(lines, cur); cur = w
                    else table.insert(lines, w); cur = "" end
                else cur = test end
            end
            if #cur > 0 then table.insert(lines, cur); cur = "" end
        end
        return table.concat(lines, "\n")
    end

    txt = wrap(txt, maxWidth)
    local line, charPos = 0, 0
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        if ch == "\n" then
            line = line + 1; charPos = 0
        else
            video:DrawSprite(
                vec2(x + BD.CHAR_W * charPos, y + BD.CHAR_H * line),
                font,
                ch:byte() % 32,
                math.floor(ch:byte() / 32),
                Color(r, g, b),
                color.clear)
            charPos = charPos + 1
        end
    end
end

---------------------------------------------------------------------------
-- Boot screen

local function drawBoot()
    bootTick = bootTick + 1
    local t  = bootTick
    video:Clear(color.black)

    if t <= BD.BOOT_BLACK_END then return end

    -- Use real screen dimensions for boot layout
    local sw = video.Width
    local sh = video.Height

    -- Centered logo
    local logo  = "IARG-OS"
    local logoX = math.floor((sw - #logo * BD.CHAR_W) / 2)
    local logoY = math.floor(sh / 2) - 20
    Tprint(logoX, logoY, logo, 80, 200, 255)

    local sub  = "Intelligent Autonomous RetroGadget OS"
    local subX = math.floor((sw - #sub * BD.CHAR_W) / 2)
    Tprint(subX, logoY + BD.CHAR_H + 4, sub, 130, 130, 155)

    -- Progress bar
    if t >= BD.BOOT_PROGRESS_START and t <= BD.BOOT_PROGRESS_END then
        local prog = (t - BD.BOOT_PROGRESS_START) /
                     math.max(1, BD.BOOT_PROGRESS_END - BD.BOOT_PROGRESS_START)
        local bx, by = 20, math.floor(sh / 2) + 8
        local pw, ph = sw - 40, 5

        video:FillRect(vec2(bx, by),     vec2(bx+pw-1, by+ph-1), Color(22,22,40))
        video:DrawRect(vec2(bx, by),     vec2(bx+pw-1, by+ph-1), Color(55,55,80))
        local fw = math.max(0, math.floor((pw-2)*prog))
        if fw > 0 then
            video:FillRect(vec2(bx+1,by+1), vec2(bx+fw, by+ph-2), Color(80,200,255))
        end

        if BD.BOOT_MESSAGES[t] then bootMsg = BD.BOOT_MESSAGES[t] end
        if bootMsg ~= "" then
            local mx = math.floor((BD.SW - #bootMsg * BD.CHAR_W) / 2)
            Tprint(mx, by + ph + 4, bootMsg, 130, 130, 155)
        end
    end

    -- Fade-out
    if t >= BD.BOOT_FADEOUT_START then
        local a = math.min(1.0,
            (t - BD.BOOT_FADEOUT_START) /
            math.max(1, BD.BOOT_FADEOUT_END - BD.BOOT_FADEOUT_START))
        video:FillRect(vec2(0,0), vec2(BD.SW-1,BD.SH-1),
            ColorRGBA(0,0,0, math.floor(255*a)))
    end

    if t >= BD.BOOT_DONE then bootDone = true end
end

---------------------------------------------------------------------------
-- OS init -- safe to call Color() here

local function initOS()
    -- Build themes (Color() is now available)
    BD.BuildThemes()

    -- Persistent data
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
            local t = BD.THEMES[OSConfig.theme] or BD.THEMES[0]
            TextPad:Init(video, font, t, data, CLI:GetCWD(), function()
                activeApp = nil
                CLI:_out("TextPad closed.",
                    (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).dim)
            end)
        elseif app == "AIChat" then
            activeApp = "aichat"
            local t = BD.THEMES[OSConfig.theme] or BD.THEMES[0]
            AIChat:Init(video, font, t, wifi, function()
                activeApp = nil
                CLI:_out("AIChat closed.", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).dim)
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
-- EventChannel1 -- KeyboardChip connected to CPU0 EventChannel 1

-- Track modifier keys state internally
local _shiftHeld = false
local _ctrlHeld  = false

function eventChannel1(sender, event)
    log("KEY: " .. name)
    if not osReady then return end
    if event.Type ~= "KeyboardChipEvent" then return end

    local name = event.InputName:gsub("^KeyboardChip%.", "")

    -- Track shift and ctrl via ButtonDown/ButtonUp
    if name == "LeftShift" or name == "RightShift" then
        _shiftHeld = event.ButtonDown
        return
    end
    if name == "LeftControl" or name == "RightControl" then
        _ctrlHeld = event.ButtonDown
        return
    end

    -- Process both key presses and releases
    if event.ButtonDown then
        if activeApp == "textpad" then
            TextPad:HandleKey(name, _shiftHeld, _ctrlHeld)
        elseif activeApp == "aichat" then
            AIChat:HandleKey(name, _shiftHeld, _ctrlHeld)
        else
            CLI:HandleKey(name, _shiftHeld, _ctrlHeld)
        end
    else
        -- Key release - only for CLI smooth scroll
        if activeApp == nil then
            CLI:HandleKeyRelease(name, _shiftHeld, _ctrlHeld)
        end
    end
end

---------------------------------------------------------------------------
-- EventChannel2 -- Wifi0 connected to CPU0 EventChannel 2

function eventChannel2(sender, event)
    if not osReady then return end
    if event.Type ~= "WifiWebResponseEvent" then return end
    if activeApp == "aichat" then
        AIChat:HandleWifiEvent(event)
    end
end

---------------------------------------------------------------------------
-- Update

function update()
    if not bootDone then
        drawBoot()
        return
    end

    if not osReady then
        initOS()
        return
    end

    -- Logic
    if activeApp == "textpad" then
        TextPad:Update()
    elseif activeApp == "aichat" then
        AIChat:Update()
    else
        CLI:Update()
    end

    -- Render
    video:RenderOnScreen()
    video:Clear(color.black)

    local cwdNode = CLI:GetCWD()
    local cwdName = (cwdNode and cwdNode.parent) and cwdNode.name or ""
    Topbar:Draw(cwdName)

    if activeApp == "textpad" then
        TextPad:Draw()
    elseif activeApp == "aichat" then
        AIChat:Draw()
    else
        CLI:Draw()
    end
end