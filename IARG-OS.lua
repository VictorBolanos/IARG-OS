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
--   Mouse0        -- mouse (CPU0 EventChannel3)
--   AudioChip0    -- audio (optional)
--
-- CODE ASSETS (.lua):
--   BD.lua, VFS.lua, SaveSystem.lua, Topbar.lua, CLI.lua, TextPad.lua, Chess.lua
--
-- ASSETS SPRITESHEET (.png):
--   fontPrincipal.png  -- text font 4x7 px (Tprint)
--   sprOsLogoSmall.png -- logo 24x12 px
--   sprSystem.png      -- 9x9 px icons (clock, folder, file)
---------------------------------------------------------------------------

-- Root-level requires
-- Load all modules as globals so they are visible to each other
BD          = require("BD.lua")
Utils       = require("Utils.lua")
VFS         = require("VFS.lua")
SaveSystem  = require("SaveSystem.lua")
SoundSystem = require("SoundSystem.lua")
Topbar      = require("Topbar.lua")
CLI         = require("CLI.lua")
TextPad     = require("TextPad.lua")
AIChat      = require("AIChat.lua")
Tetris      = require("Tetris.lua")
Chess       = require("Chess.lua")
SystemInfo  = require("SysInfo.lua")
RetroMixer  = require("RetroMixer.lua")

-- Hardware
local video    = gdt.VideoChip0
local flash    = gdt.FlashMemory0
local rom      = gdt.ROM
local reality  = gdt.RealityChip
local keyboard = gdt.KeyboardChip0
local wifi      = gdt.Wifi0
local mouse     = nil
pcall(function() mouse = gdt.Mouse0 end)
local audioChip = nil
pcall(function() audioChip = gdt.AudioChip0 end)

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

    -- Play boot sound on first tick
    if t == 1 then
        SoundSystem:Init(audioChip)
        SoundSystem:PlayBoot(rom)
    end

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
        elseif app == "Tetris" then
            activeApp = "tetris"
            local t = BD.THEMES[OSConfig.theme] or BD.THEMES[0]
            Tetris:Init(video, font, t, function()
                activeApp = nil
                CLI:_out("Tetris closed.", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).dim)
            end)
        elseif app == "Chess" then
            activeApp = "chess"
            local t = BD.THEMES[OSConfig.theme] or BD.THEMES[0]
            Chess:Init(video, font, t, function()
                activeApp = nil
                CLI:_out("Chess closed.", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).dim)
            end)
        elseif app == "SysInfo" then
            activeApp = "sysinfo"
            local t = BD.THEMES[OSConfig.theme] or BD.THEMES[0]
            SystemInfo:Init(video, font, t, function()
                activeApp = nil
                CLI:_out("SystemInfo closed.", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).dim)
            end)
        elseif app == "RetroMixer" then
            CLI:_out("STEP1: About to start RetroMixer...", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).success)
            
            local success, err = pcall(function()
                CLI:_out("STEP2: Setting activeApp...", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).success)
                activeApp = "retromixer"
                CLI:_out("STEP3: activeApp is now: " .. tostring(activeApp), (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).success)
                
                CLI:_out("STEP4: Calling RetroMixer:Init...", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).success)
                local t = BD.THEMES[OSConfig.theme] or BD.THEMES[0]
                RetroMixer:Init(video, font, t, function()
                    CLI:_out("STEP6: RetroMixer onClose called", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).dim)
                    activeApp = nil
                    CLI:_out("RetroMixer closed.", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).dim)
                end, data)
                CLI:_out("STEP5: RetroMixer:Init completed", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).success)
            end)
            
            if not success then
                CLI:_out("ERROR: " .. tostring(err), (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).error)
                CLI:_out("FAILED: activeApp is: " .. tostring(activeApp), (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).error)
                activeApp = nil
            else
                CLI:_out("STEP7: RetroMixer initialized successfully!", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).success)
                CLI:_out("FINAL: activeApp is: " .. tostring(activeApp), (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).success)
            end
        elseif app == "__theme__" then
            local nt = BD.THEMES[data] or BD.THEMES[0]
            Topbar:SetTheme(nt)
            CLI:SetTheme(nt)
        elseif app == "SoundTest" then
            local soundFile = VFS:Open("soundtest.wav", "rb")
            if soundFile then
                local soundData = soundFile:Read()
                soundFile:Close()
                audioChip:PlaySound(soundData, 0)
            else
                CLI:_out("Error: soundtest.wav not found", (BD.THEMES[OSConfig.theme] or BD.THEMES[0]).error)
            end
        end
    end)  

    osReady = true
end  

---------------------------------------------------------------------------
-- Direct F2 Sound Test Function
local function testDirectF2Sound()
    CLI:_out("F2: Testing ROM sounds first...", Color(0, 255, 255))
    
    -- Try boot.wav from ROM first
    local bootSample = nil
    pcall(function()
        bootSample = rom.User.AudioSamples["boot.wav"]
    end)
    
    if bootSample then
        CLI:_out("F2: Found boot.wav in ROM!", Color(0, 255, 0))
        
        if audioChip then
            local playSuccess = audioChip:Play(bootSample, 0)  -- Channel 0
            audioChip:SetChannelVolume(80, 0)
            
            CLI:_out("F2: Boot sound play success=" .. tostring(playSuccess) .. " on channel 0", Color(255, 0, 255))
            
            if playSuccess then
                CLI:_out("F2: *** BOOT SOUND PLAYING! ***", Color(255, 255, 255))
                return
            end
        else
            CLI:_out("F2: ERROR - No AudioChip available!", Color(255, 0, 0))
        end
    else
        CLI:_out("F2: ERROR - boot.wav not found in ROM!", Color(255, 0, 0))
    end
    
    -- Try simple artificial sound (small sample)
    CLI:_out("F2: Trying simple artificial sound...", Color(255, 255, 0))
    
    local samples = {}
    for i = 1, 100 do  -- Only 100 samples to avoid unpack error
        samples[i] = 128 + math.floor(math.sin(i * 0.1) * 50)  -- Simple wave
    end
    
    CLI:_out("F2: Generated 100 samples (first=" .. samples[1] .. ", last=" .. samples[100] .. ")", Color(0, 255, 0))
    
    -- Create AudioSample
    local success, audioSample = pcall(function()
        return AudioSample(samples, 44100)
    end)
    
    if success and audioSample then
        CLI:_out("F2: AudioSample created successfully!", Color(0, 255, 0))
        
        if audioChip then
            local playSuccess = audioChip:Play(audioSample, 1)  -- Channel 1
            audioChip:SetChannelVolume(80, 1)
            
            CLI:_out("F2: Play success=" .. tostring(playSuccess) .. " on channel 1", Color(255, 0, 255))
            
            if playSuccess then
                CLI:_out("F2: *** ARTIFICIAL SOUND PLAYING! ***", Color(255, 255, 255))
                return
            end
        end
    else
        CLI:_out("F2: ERROR - Failed to create AudioSample: " .. tostring(audioSample), Color(255, 0, 0))
    end
    
    CLI:_out("F2: *** NO SOUND METHOD WORKED! ***", Color(255, 0, 0))
end

---------------------------------------------------------------------------
-- EventChannel1 -- KeyboardChip connected to CPU0 EventChannel 1

-- Track modifier keys state internally
local _shiftHeld = false
local _ctrlHeld  = false

function eventChannel1(sender, event)
    if not osReady then return end
    if event.Type ~= "KeyboardChipEvent" then return end

    local name = event.InputName:gsub("^KeyboardChip%.", "")

    -- Debug: Show ALL key events when RetroMixer is active
    if activeApp == "retromixer" and event.ButtonDown then
        -- Forzar salida a CLI para ver si llega algo
        pcall(function()
            CLI:_out("EVENT: " .. event.InputName .. " -> " .. name, Color(255, 255, 255))
        end)
    end

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
        -- DIRECT SOUND TEST: F2 (LedButton2) - Global test before mixer
        if name == "F2" then
            CLI:_out("F2 PRESSED - DIRECT SOUND TEST!", Color(255, 255, 0))
            testDirectF2Sound()
            return
        end
        
        if activeApp == "textpad" then
            TextPad:HandleKey(name, _shiftHeld, _ctrlHeld)
        elseif activeApp == "aichat" then
            AIChat:HandleKey(name, _shiftHeld, _ctrlHeld)
        elseif activeApp == "tetris" then
            Tetris:HandleKey(name, event.Shift, event.Ctrl)
        elseif activeApp == "chess" then
            Chess:HandleKey(name, event.Shift, event.Ctrl)
        elseif activeApp == "sysinfo" then
            SystemInfo:HandleKey(name, _shiftHeld, _ctrlHeld)
        elseif activeApp == "retromixer" then
            -- Debug: Show key being sent to RetroMixer
            CLI:_out("SEND: " .. name .. " to RetroMixer", Color(0, 255, 255))
            RetroMixer:HandleKey(name, _shiftHeld, _ctrlHeld)
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
-- EventChannel3 -- Mouse0 connected to CPU0 EventChannel 3

function eventChannel3(sender, event)
    if not osReady then return end
    if event.Type ~= "MouseEvent" then return end
    
    if activeApp == "chess" then
        Chess:HandleMouse(event.Button, event.X, event.Y, event.ButtonDown)
    elseif activeApp == "sysinfo" then
        SystemInfo:HandleMouse(event.Button, event.X, event.Y, event.ButtonDown)
    elseif activeApp == "retromixer" then
        RetroMixer:HandleMouse(event.Button, event.X, event.Y, event.ButtonDown)
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
    SoundSystem:Update()
    if activeApp == "textpad" then
        TextPad:Update()
    elseif activeApp == "aichat" then
        AIChat:Update()
    elseif activeApp == "tetris" then
        Tetris:Update()
    elseif activeApp == "chess" then
        Chess:Update()
    elseif activeApp == "sysinfo" then
        SystemInfo:Update()
    elseif activeApp == "retromixer" then
        RetroMixer:Update()
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
    elseif activeApp == "tetris" then
        Tetris:Draw()
    elseif activeApp == "chess" then
        Chess:Draw()
    elseif activeApp == "sysinfo" then
        SystemInfo:Draw()
    elseif activeApp == "retromixer" then
        RetroMixer:Draw()
    else
        CLI:Draw()
    end
end