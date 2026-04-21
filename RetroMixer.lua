---------------------------------------------------------------------------
-- RetroMixer.lua -- RetroWave 3000 Professional Synthesizer
-- Launch with: run mixer
-- Controls: Q-P keys for notes, 1-9 for presets, Ctrl+I for help
---------------------------------------------------------------------------

-- BD, Utils are globals loaded by IARG-OS.lua

local rom      = gdt.ROM
-- RetroMixer application table
RetroMixer = {
    -- Application metadata
    name = "RetroMixer",
    version = "3.0",
    description = "RetroWave 3000 Professional Synthesizer"
}

---------------------------------------------------------------------------
-- Hardware and system references
local _video = nil
local _font = nil
local _theme = nil
local _onClose = nil
local _audioChip = nil

---------------------------------------------------------------------------
-- Audio Engine Constants
local SAMPLE_RATE = 44100
local MAX_VOICES = 8
local MAX_SEQUENCER_STEPS = 16
local MAX_NOTES = 61  -- 5 octaves

-- Musical note frequencies (A4 = 440Hz)
local NOTE_FREQUENCIES = {
    [1] = 27.50,   -- C1
    [2] = 29.14,   -- C#1
    [3] = 30.87,   -- D1
    [4] = 32.70,   -- D#1
    [5] = 34.65,   -- E1
    [6] = 36.71,   -- F1
    [7] = 38.89,   -- F#1
    [8] = 41.20,   -- G1
    [9] = 43.65,   -- G#1
    [10] = 46.25,  -- A1
    [11] = 49.00,  -- A#1
    [12] = 51.91,  -- B1
    [13] = 55.00,  -- C2
    [14] = 58.27,  -- C#2
    [15] = 61.74,  -- D2
    [16] = 65.41,  -- D#2
    [17] = 69.30,  -- E2
    [18] = 73.42,  -- F2
    [19] = 77.78,  -- F#2
    [20] = 82.41,  -- G2
    [21] = 87.31,  -- G#2
    [22] = 92.50,  -- A2
    [23] = 98.00,  -- A#2
    [24] = 103.83, -- B2
    [25] = 110.00, -- C3
    [26] = 116.54, -- C#3
    [27] = 123.47, -- D3
    [28] = 130.81, -- D#3
    [29] = 138.59, -- E3
    [30] = 146.83, -- F3
    [31] = 155.56, -- F#3
    [32] = 164.81, -- G3
    [33] = 174.61, -- G#3
    [34] = 185.00, -- A3
    [35] = 196.00, -- A#3
    [36] = 207.65, -- B3
    [37] = 220.00, -- C4 (Middle C)
    [38] = 233.08, -- C#4
    [39] = 246.94, -- D4
    [40] = 261.63, -- D#4
    [41] = 277.18, -- E4
    [42] = 293.66, -- F4
    [43] = 311.13, -- F#4
    [44] = 329.63, -- G4
    [45] = 349.23, -- G#4
    [46] = 369.99, -- A4
    [47] = 392.00, -- A#4
    [48] = 415.30, -- B4
    [49] = 440.00, -- C5
    [50] = 466.16, -- C#5
    [51] = 493.88, -- D5
    [52] = 523.25, -- D#5
    [53] = 554.37, -- E5
    [54] = 587.33, -- F5
    [55] = 622.25, -- F#5
    [56] = 659.25, -- G5
    [57] = 698.46, -- G#5
    [58] = 739.99, -- A5
    [59] = 783.99, -- A#5
    [60] = 830.61, -- B5
    [61] = 880.00  -- C6
}

---------------------------------------------------------------------------
-- Key mapping for musical notes
local keyToNote = {
    -- Octave 2 (Z-M)
    z = 1,  x = 3,  c = 5,  v = 6,  b = 8,  n = 10, m = 12,
    -- Octave 3 (A-L)  
    a = 13, s = 15, d = 17, f = 18, g = 20, h = 22, j = 24, k = 25, l = 27,
    -- Octave 4 (Q-P)
    q = 37, w = 39, e = 41, r = 42, t = 44, y = 46, u = 48, i = 49, o = 51, p = 53
}

---------------------------------------------------------------------------
-- Synthesizer Engine State
local synthState = {
    -- Current parameters
    waveform = "sine",
    filterType = "low",
    filterCutoff = 800,
    filterResonance = 0.2,
    reverbType = "room",
    delayType = "off",
    
    -- ADSR parameters
    attack = 0.01,
    decay = 0.3,
    sustain = 0.7,
    release = 0.5,
    
    -- Master controls
    masterVolume = 0.8,
    octaveOffset = 0,
    sustain = false,
    
    -- Sequencer
    sequencerActive = false,
    sequencerTempo = 120,
    currentBeat = 0,
    sequencerGrid = {}, -- [beat][note] = boolean
    
    -- UI state
    currentPreset = 1,
    showHelp = false,
    mode = "performance", -- "performance" or "sequencer"
    
    -- Performance monitoring
    activeVoices = 0,
    cpuUsage = 0,
    memoryUsage = 0
}

---------------------------------------------------------------------------
-- Voice Management System
local voices = {}
for i = 1, MAX_VOICES do
    voices[i] = {
        active = false,
        note = 0,
        frequency = 0,
        velocity = 0,
        phase = 0,
        time = 0,
        envelope = 0,
        filterState = 0
    }
end

---------------------------------------------------------------------------
-- Professional Presets Library
local presets = {
    {
        name = "Warm Piano",
        description = "Classic electric piano",
        wave = "sine",
        attack = 0.01, decay = 0.3, sustain = 0.7, release = 0.5,
        filter = "low", cutoff = 800, resonance = 0.2,
        reverb = "room", delay = "off",
        volume = 0.8
    },
    {
        name = "Retro Lead",
        description = "8-bit lead sound",
        wave = "square",
        attack = 0.001, decay = 0.1, sustain = 0.8, release = 0.2,
        filter = "band", cutoff = 1200, resonance = 0.8,
        reverb = "hall", delay = "echo",
        volume = 0.7
    },
    {
        name = "Deep Bass",
        description = "Analog bass synth",
        wave = "saw",
        attack = 0.05, decay = 0.2, sustain = 0.9, release = 0.8,
        filter = "low", cutoff = 200, resonance = 0.4,
        reverb = "off", delay = "delay",
        volume = 0.9
    },
    {
        name = "Cosmic Pad",
        description = "Ethereal pad sound",
        wave = "triangle",
        attack = 0.8, decay = 0.5, sustain = 0.6, release = 1.5,
        filter = "high", cutoff = 2000, resonance = 0.1,
        reverb = "cathedral", delay = "pingpong",
        volume = 0.6
    },
    {
        name = "Digital Bell",
        description = "Crystal bell tones",
        wave = "sine",
        attack = 0.001, decay = 0.8, sustain = 0.1, release = 2.0,
        filter = "high", cutoff = 3000, resonance = 0.3,
        reverb = "hall", delay = "echo",
        volume = 0.5
    },
    {
        name = "Wobble Bass",
        description = "Dubstep wobble bass",
        wave = "saw",
        attack = 0.02, decay = 0.1, sustain = 0.8, release = 0.3,
        filter = "low", cutoff = 100, resonance = 0.9,
        reverb = "off", delay = "delay",
        volume = 0.8
    },
    {
        name = "Vintage Organ",
        description = "Hammond organ sound",
        wave = "sine",
        attack = 0.01, decay = 0.1, sustain = 0.9, release = 0.1,
        filter = "low", cutoff = 1500, resonance = 0.1,
        reverb = "room", delay = "off",
        volume = 0.7
    },
    {
        name = "Sci-Fi Lead",
        description = "Futuristic lead",
        wave = "square",
        attack = 0.1, decay = 0.3, sustain = 0.6, release = 0.4,
        filter = "band", cutoff = 2000, resonance = 0.6,
        reverb = "cathedral", delay = "pingpong",
        volume = 0.6
    },
    {
        name = "Soft Strings",
        description = "String ensemble",
        wave = "triangle",
        attack = 0.4, decay = 0.2, sustain = 0.8, release = 1.0,
        filter = "low", cutoff = 1000, resonance = 0.2,
        reverb = "hall", delay = "off",
        volume = 0.7
    },
    {
        name = "Hard Synth",
        description = "Aggressive synth lead",
        wave = "saw",
        attack = 0.001, decay = 0.05, sustain = 0.7, release = 0.1,
        filter = "low", cutoff = 500, resonance = 0.8,
        reverb = "room", delay = "echo",
        volume = 0.8
    },
    {
        name = "Ambient Drone",
        description = "Atmospheric drone",
        wave = "triangle",
        attack = 2.0, decay = 1.0, sustain = 0.8, release = 3.0,
        filter = "low", cutoff = 800, resonance = 0.1,
        reverb = "cathedral", delay = "delay",
        volume = 0.5
    },
    {
        name = "Chime",
        description = "Percussive chime",
        wave = "sine",
        attack = 0.001, decay = 0.3, sustain = 0.0, release = 0.5,
        filter = "high", cutoff = 4000, resonance = 0.2,
        reverb = "hall", delay = "off",
        volume = 0.6
    },
    {
        name = "Pluck",
        description = "Plucked string",
        wave = "saw",
        attack = 0.001, decay = 0.4, sustain = 0.0, release = 0.2,
        filter = "band", cutoff = 1500, resonance = 0.3,
        reverb = "room", delay = "off",
        volume = 0.7
    },
    {
        name = "Brass",
        description = "Brass section",
        wave = "square",
        attack = 0.1, decay = 0.2, sustain = 0.8, release = 0.3,
        filter = "low", cutoff = 1200, resonance = 0.4,
        reverb = "room", delay = "off",
        volume = 0.8
    },
    {
        name = "Wave",
        description = "Ocean wave sound",
        wave = "sine",
        attack = 1.5, decay = 2.0, sustain = 0.4, release = 3.0,
        filter = "low", cutoff = 400, resonance = 0.2,
        reverb = "cathedral", delay = "delay",
        volume = 0.6
    },
    {
        name = "Laser",
        description = "Sci-fi laser",
        wave = "square",
        attack = 0.001, decay = 0.1, sustain = 0.0, release = 0.05,
        filter = "high", cutoff = 3000, resonance = 0.9,
        reverb = "off", delay = "echo",
        volume = 0.4
    }
}

---------------------------------------------------------------------------
-- Initialize sequencer grid
local function initializeSequencer()
    for beat = 1, MAX_SEQUENCER_STEPS do
        synthState.sequencerGrid[beat] = {}
        for note = 1, 8 do
            synthState.sequencerGrid[beat][note] = false
        end
    end
end

---------------------------------------------------------------------------
-- Audio Generation Functions

-- Generate waveform sample
local function generateWaveform(waveform, phase)
    if waveform == "sine" then
        return math.sin(2 * math.pi * phase)
    elseif waveform == "square" then
        return math.sin(2 * math.pi * phase) > 0 and 1 or -1
    elseif waveform == "saw" then
        return 2 * (phase % 1) - 1
    elseif waveform == "triangle" then
        return 2 * math.abs(2 * (phase % 1) - 1) - 1
    end
    return 0
end

-- ADSR envelope calculation
local function calculateADSR(voice, time)
    if time < voice.attack then
        return time / voice.attack
    elseif time < voice.attack + voice.decay then
        local decayTime = time - voice.attack
        return 1 - (1 - voice.sustain) * (decayTime / voice.decay)
    else
        if voice.sustain > 0 then
            return voice.sustain * math.exp(-(time - voice.attack - voice.decay) / voice.release)
        else
            return math.exp(-(time - voice.attack - voice.decay) / voice.release)
        end
    end
end

-- Digital filter implementation
local function applyFilter(input, filterType, cutoff, resonance, state)
    local normalizedCutoff = cutoff / SAMPLE_RATE
    local q = 1.0 / resonance
    
    if filterType == "low" then
        local b0 = 1.0 / (1.0 + q * normalizedCutoff + normalizedCutoff * normalizedCutoff)
        local b1 = 2.0 * b0
        local b2 = b0
        local a0 = 1.0
        local a1 = 2.0 * (normalizedCutoff * normalizedCutoff - 1.0) * b0
        local a2 = (1.0 - q * normalizedCutoff + normalizedCutoff * normalizedCutoff) * b0
        
        -- Simple one-pole low-pass filter for performance
        local alpha = normalizedCutoff * 2 * math.pi
        return state + alpha * (input - state)
        
    elseif filterType == "high" then
        local alpha = normalizedCutoff * 2 * math.pi
        return input - (state + alpha * (input - state))
        
    elseif filterType == "band" then
        local alpha = normalizedCutoff * 2 * math.pi
        local lowPass = state + alpha * (input - state)
        return input - lowPass
        
    else -- off
        return input
    end
end

-- Reverb algorithm (simple Schroeder reverb)
local reverbBuffer = {}
local reverbIndex = 1
local reverbSize = 2048

local function applyReverb(input, type)
    if type == "off" then
        return input
    end
    
    -- Initialize buffer if needed
    if #reverbBuffer == 0 then
        for i = 1, reverbSize do
            reverbBuffer[i] = 0
        end
    end
    
    local feedback = 0.5
    if type == "room" then
        feedback = 0.3
    elseif type == "hall" then
        feedback = 0.7
    elseif type == "cathedral" then
        feedback = 0.9
    end
    
    -- Simple delay line with feedback
    local delayed = reverbBuffer[reverbIndex]
    reverbBuffer[reverbIndex] = input + delayed * feedback
    reverbIndex = (reverbIndex % reverbSize) + 1
    
    return input * 0.7 + delayed * 0.3
end

-- Delay effect
local delayBuffer = {}
local delayIndex = 1
local delaySize = SAMPLE_RATE  -- 1 second delay

local function applyDelay(input, type)
    if type == "off" then
        return input
    end
    
    -- Initialize buffer if needed
    if #delayBuffer == 0 then
        for i = 1, delaySize do
            delayBuffer[i] = 0
        end
    end
    
    local delayTime = SAMPLE_RATE * 0.25  -- 250ms default
    if type == "echo" then
        delayTime = SAMPLE_RATE * 0.5
    elseif type == "delay" then
        delayTime = SAMPLE_RATE * 0.25
    elseif type == "pingpong" then
        delayTime = SAMPLE_RATE * 0.375
    end
    
    local delayed = delayBuffer[delayIndex]
    delayBuffer[delayIndex] = input
    
    delayIndex = (delayIndex % delaySize) + 1
    
    return input + delayed * 0.4
end

---------------------------------------------------------------------------
-- Audio Processing with AudioChip
local audioSamples = {}  -- Cache of generated AudioSamples
local nextChannel = 1

-- Create or get cached AudioSample
local function getAudioSample(frequency, waveform)
    local key = string.format("%.0f_%s", frequency, waveform)
    
    if not audioSamples[key] then
        -- Debug: Creating new AudioSample
        if CLI and CLI._out then
            CLI:_out("CREATE: New AudioSample " .. key, Color(255, 255, 255))
        end
        
        -- Generate AudioSample data - Ultra short for testing
        local samples = {}
        local sampleRate = 44100
        local numSamples = 100  -- Just 100 samples for testing
        
        local minVal = 255
        local maxVal = 0
        
        for i = 1, numSamples do
            -- Test with constant value first, then sine wave
            local byteSample = 128  -- Middle value for testing
            -- Uncomment below for sine wave once constant works
            -- local phase = (i - 1) / sampleRate * frequency * 2 * math.pi
            -- local sample = math.sin(phase) * 0.5  -- 50% volume
            -- local byteSample = math.floor((sample + 1.0) * 127.5)
            samples[i] = byteSample
            
            -- Track min/max for range
            if byteSample < minVal then minVal = byteSample end
            if byteSample > maxVal then maxVal = byteSample end
            
            -- Debug first few samples
            if i <= 5 and CLI and CLI._out then
                CLI:_out("SAMPLE " .. i .. ": byte=" .. byteSample, Color(200, 200, 200))
            end
        end
        
        if CLI and CLI._out then
            CLI:_out("GENERATED: " .. numSamples .. " byte samples for " .. frequency .. "Hz (range: " .. minVal .. "-" .. maxVal .. ")", Color(255, 255, 0))
        end
        
        -- Create AudioSample
        local success, result = pcall(function()
            return AudioSample(samples, sampleRate)
        end)
        if success then
            audioSamples[key] = result
            if CLI and CLI._out then
                CLI:_out("OK: AudioSample created! Samples: " .. #samples, Color(0, 255, 0))
            end
        else
            if CLI and CLI._out then
                CLI:_out("FAIL: AudioSample error! " .. tostring(result), Color(255, 0, 0))
            end
            return nil
        end
    else
        -- Debug: Using cached AudioSample
        if CLI and CLI._out then
            CLI:_out("CACHE: Using existing " .. key, Color(150, 150, 150))
        end
    end
    
    return audioSamples[key]
end

---------------------------------------------------------------------------
-- Voice Management

-- Allocate voice for note
local function allocateVoice(note, velocity)
    -- Get AudioSample for this note
    local frequency = NOTE_FREQUENCIES[note] * (2 ^ synthState.octaveOffset)
    local audioSample = getAudioSample(frequency, synthState.waveform)
    
    -- Debug: Audio sample creation
    if CLI and CLI._out then
        CLI:_out("FREQ: " .. math.floor(frequency) .. "Hz, WAVE: " .. synthState.waveform, Color(0, 255, 255))
    end
    
    -- Play on AudioChip - Simple and direct like SoundSystem
    if _audioChip and audioSample then
        -- Find available channel
        local channel = nextChannel
        nextChannel = (nextChannel % _audioChip.ChannelsCount) + 1
        
        -- Debug: AudioChip info
        if CLI and CLI._out then
            CLI:_out("AUDIO: Channel " .. channel .. "/" .. _audioChip.ChannelsCount, Color(0, 255, 0))
        end
        
        -- Stop any existing sound on this channel
        _audioChip:Stop(channel)
        
        -- Play note - Direct call like SoundSystem
        local success = _audioChip:Play(audioSample, channel)
        
        -- Set volume
        _audioChip:SetChannelVolume(50, channel)  -- 50% volume
        
        -- Debug: Sound played
        if CLI and CLI._out then
            CLI:_out("PLAY: Success=" .. tostring(success) .. " Channel=" .. channel, Color(255, 0, 255))
        end
        
        return success
    else
        -- Debug: No AudioChip or sample
        if CLI and CLI._out then
            CLI:_out("ERROR: No AudioChip=" .. tostring(_audioChip ~= nil) .. " or sample=" .. tostring(audioSample ~= nil), Color(255, 0, 0))
        end
        return false
    end
    
    -- Update voice tracking for display
    for i = 1, MAX_VOICES do
        if not voices[i].active then
            voices[i].active = true
            voices[i].note = note
            voices[i].frequency = frequency
            voices[i].velocity = velocity
            voices[i].channel = channel
            voices[i].time = 0
            return i
        end
    end
    
    -- Steal oldest voice
    local oldest = 1
    for i = 2, MAX_VOICES do
        if voices[i].time > voices[oldest].time then
            oldest = i
        end
    end
    
    voices[oldest].active = true
    voices[oldest].note = note
    voices[oldest].frequency = frequency
    voices[oldest].velocity = velocity
    voices[oldest].channel = channel
    voices[oldest].time = 0
    voices[oldest].envelope = 0
    voices[oldest].filterState = 0
    
    return oldest
end

-- Release voice
local function releaseVoice(note)
    for i = 1, MAX_VOICES do
        if voices[i].active and voices[i].note == note then
            -- Stop sound on AudioChip
            if _audioChip and voices[i].channel then
                _audioChip:Stop(voices[i].channel)
            end
            
            if not synthState.sustain then
                voices[i].active = false
            end
        end
    end
end

local function processAudio()
    if not _audioChip then return end
    
    -- Count active voices
    local activeCount = 0
    for i = 1, MAX_VOICES do
        if voices[i].active then
            activeCount = activeCount + 1
        end
    end
    
    -- Update performance metrics
    synthState.activeVoices = activeCount
    synthState.cpuUsage = math.floor(30 + activeCount * 8)  -- Simulated CPU usage
    synthState.memoryUsage = math.floor(2.0 + activeCount * 0.3)  -- KB
end

---------------------------------------------------------------------------
-- Preset Management

local function loadPreset(presetIndex)
    if not presets or #presets == 0 then return end
    if presetIndex < 1 or presetIndex > #presets then return end
    
    local preset = presets[presetIndex]
    if not preset then return end
    
    synthState.currentPreset = presetIndex
    
    -- Apply preset parameters safely
    synthState.waveform = preset.wave or "sine"
    synthState.attack = preset.attack or 0.01
    synthState.decay = preset.decay or 0.3
    synthState.sustain = preset.sustain or 0.7
    synthState.release = preset.release or 0.5
    synthState.filterType = preset.filter or "low"
    synthState.filterCutoff = preset.cutoff or 800
    synthState.filterResonance = preset.resonance or 0.2
    synthState.reverbType = preset.reverb or "room"
    synthState.delayType = preset.delay or "off"
    synthState.masterVolume = preset.volume or 0.8
end

---------------------------------------------------------------------------
-- Sequencer Functions

local function updateSequencer()
    if not synthState.sequencerActive then return end
    
    -- Update beat position
    local beatDuration = 60.0 / synthState.sequencerTempo
    local currentBeat = math.floor((audioPhase * SAMPLE_RATE / beatDuration)) % MAX_SEQUENCER_STEPS + 1
    
    if currentBeat ~= synthState.currentBeat then
        synthState.currentBeat = currentBeat
        
        -- Trigger notes for current beat
        for note = 1, 8 do
            if synthState.sequencerGrid[currentBeat][note] then
                -- Map sequencer note to actual note
                local sequencerNote = 25 + (note - 1) * 5  -- C3 to C5 range
                allocateVoice(sequencerNote, 100)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Utility Functions

local function getThemeColor(colorName)
    if not _theme then return Color(255, 255, 255) end
    
    local colors = {
        text = _theme.text or Color(255, 255, 255),
        dim = _theme.dim or Color(150, 150, 150),
        success = _theme.success or Color(100, 255, 100),
        error = _theme.error or Color(255, 100, 100),
        bg = _theme.bg or Color(0, 0, 0)
    }
    
    return colors[colorName] or colors.text
end

local function tp(x, y, txt, col)
    if not _font or not _video then return end
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        _video:DrawSprite(vec2(x+(i-1)*4, y), _font,
            ch:byte()%32, math.floor(ch:byte()/32), col, color.clear)
    end
end

---------------------------------------------------------------------------
-- Drawing Functions

local function drawMainInterface()
    -- Clear screen
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(_video.Width - 1, _video.Height - 1), getThemeColor("bg"))
    
    -- Title
    tp(10, BD.CONTENT_Y + 2, "RETROWAVE 3000 - PROFESSIONAL SYNTHESIZER", getThemeColor("success"))
    
    -- Current parameters display
    local y = BD.CONTENT_Y + 12
    tp(10, y, "WAVE: " .. synthState.waveform:upper() .. 
           "  FILTER: " .. synthState.filterType:upper() .. 
           "  REVERB: " .. synthState.reverbType:upper() .. 
           "  DELAY: " .. synthState.delayType:upper(), getThemeColor("text"))
    
    y = y + 8
    tp(10, y, "ATTACK: " .. string.format("%.2f", synthState.attack) .. 
           "  DECAY: " .. string.format("%.2f", synthState.decay) .. 
           "  SUSTAIN: " .. string.format("%.2f", synthState.sustain) .. 
           "  RELEASE: " .. string.format("%.2f", synthState.release), getThemeColor("text"))
    
    -- Draw sequencer grid
    y = y + 12
    tp(10, y, "SEQUENCER - 16 BEATS", getThemeColor("success"))
    y = y + 8
    
    local gridX = 10
    local gridY = y
    local cellWidth = 18
    local cellHeight = 6
    
    for beat = 1, MAX_SEQUENCER_STEPS do
        for note = 1, 8 do
            local x = gridX + (beat - 1) * cellWidth
            local y = gridY + (note - 1) * cellHeight
            
            if synthState.sequencerGrid[beat][note] then
                _video:FillRect(vec2(x, y), vec2(x + cellWidth - 1, y + cellHeight - 1), getThemeColor("success"))
            else
                _video:DrawRect(vec2(x, y), vec2(x + cellWidth - 1, y + cellHeight - 1), getThemeColor("dim"))
            end
        end
    end
    
    -- Current beat indicator
    if synthState.sequencerActive then
        local beatX = gridX + (synthState.currentBeat - 1) * cellWidth
        _video:FillRect(vec2(beatX, gridY - 2), vec2(beatX + cellWidth - 1, gridY - 1), getThemeColor("error"))
    end
    
    -- Performance monitor
    y = gridY + 8 * cellHeight + 8
    tp(10, y, "ACTIVE VOICES: " .. synthState.activeVoices .. "/8" .. 
           "  CPU: " .. synthState.cpuUsage .. "%" .. 
           "  MEMORY: " .. string.format("%.1f", synthState.memoryUsage) .. "KB", getThemeColor("text"))
    
    -- Current preset and tempo
    y = y + 8
    local currentPresetData = presets[synthState.currentPreset]
    tp(10, y, "PRESET: " .. synthState.currentPreset .. "/16 - \"" .. currentPresetData.name .. "\"" .. 
           "  TEMPO: " .. synthState.sequencerTempo .. " BPM", getThemeColor("text"))
    
    -- Mode indicator
    y = y + 8
    tp(10, y, "MODE: " .. synthState.mode:upper() .. 
           "  OCTAVE: " .. (4 + synthState.octaveOffset) .. 
           "  SUSTAIN: " .. (synthState.sustain and "ON" or "OFF"), getThemeColor("text"))
end

local function drawHelpScreen()
    -- Clear screen
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(_video.Width - 1, _video.Height - 1), getThemeColor("bg"))
    
    -- Title
    tp(10, BD.CONTENT_Y + 2, "RETROWAVE 3000 - USER MANUAL", getThemeColor("success"))
    
    local y = BD.CONTENT_Y + 12
    local lineHeight = 7
    
    -- Musical keys
    tp(10, y, "MUSICAL KEYS:", getThemeColor("success"))
    y = y + lineHeight
    tp(10, y, "  Q-P: C4-D5 (Middle C to D5)", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  A-L: C3-B3 (C3 to B3)", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  Z-M: C2-B2 (C2 to B2)", getThemeColor("text"))
    y = y + lineHeight + 3
    
    -- Control keys
    tp(10, y, "CONTROL KEYS:", getThemeColor("success"))
    y = y + lineHeight
    tp(10, y, "  1-9: Change preset (1-16)", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  0: Sustain pedal (hold notes)", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  - / =: Change octave (-1/+1)", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  [ ]: Change waveform (Sine->Square->Saw->Triangle)", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  ; ': Change reverb (Off->Room->Hall->Cathedral)", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  / *: Change attack/decay speed", getThemeColor("text"))
    y = y + lineHeight + 3
    
    -- Sequencer
    tp(10, y, "SEQUENCER:", getThemeColor("success"))
    y = y + lineHeight
    tp(10, y, "  Space: Play/Stop sequencer", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  Tab: Switch performance/sequencer mode", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  In sequencer mode: Musical keys add/remove notes", getThemeColor("text"))
    y = y + lineHeight + 3
    
    -- Advanced features
    tp(10, y, "ADVANCED:", getThemeColor("success"))
    y = y + lineHeight
    tp(10, y, "  Ctrl+S: Save current preset", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  Ctrl+L: Load preset from file", getThemeColor("text"))
    y = y + lineHeight
    tp(10, y, "  Ctrl+R: Reset to default settings", getThemeColor("text"))
    y = y + lineHeight + 3
    
    -- Exit
    tp(10, y, "ESC: Exit synthesizer and return to IARG-OS", getThemeColor("error"))
end

---------------------------------------------------------------------------
-- Main Draw Function
function RetroMixer:Draw()
    if not _video then return end
    
    -- Debug message - Draw simple text to verify it's working
    pcall(function()
        _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(_video.Width - 1, _video.Height - 1), color.black)
        local tp = function(x, y, txt, col)
            for i = 1, #txt do
                local ch = txt:sub(i, i)
                _video:DrawSprite(vec2(x + (i-1) * 4, y), _font,
                    ch:byte()%32, math.floor(ch:byte()/32), col, color.clear)
            end
        end
        tp(10, BD.CONTENT_Y + 10, "RETROWAVE 3000 ACTIVE", Color(255, 255, 255))
        tp(10, BD.CONTENT_Y + 20, "Q-I: Octavas 3-5 | A-L: Octavas 2-4 | Z-X: Octavas 5", Color(150, 150, 150))
        tp(10, BD.CONTENT_Y + 30, "18 notas con archivos .wav del ROM", Color(150, 150, 150))
        
        -- Draw TEST SOUND button - bigger and more visible
        _video:FillRect(vec2(10, BD.CONTENT_Y + 50), vec2(120, 75), Color(255, 100, 0))
        _video:DrawRect(vec2(10, BD.CONTENT_Y + 50), vec2(120, 75), Color(255, 255, 0))
        tp(20, BD.CONTENT_Y + 60, "CLICK FOR SOUND", Color(0, 0, 0))
        
        -- Debug: Show activeApp status
        if CLI and CLI._out then
            CLI:_out("DRAW: RetroMixer is drawing!", Color(0, 255, 0))
        end
        
        -- Try to draw main interface
        if synthState.showHelp then
            drawHelpScreen()
        else
            drawMainInterface()
        end
    end)
end

---------------------------------------------------------------------------
-- Audio Functions (must be defined before HandleKey)

-- Note to WAV file mapping
local noteToWav = {
    -- Octava 2
    A2 = "A2.wav",
    
    -- Octava 3
    B3 = "B3.wav",
    C3 = "C3.wav", 
    D3 = "D3.wav",
    E3 = "E3.wav",
    F3 = "F3.wav",
    G3 = "G3.wav",
    
    -- Octava 4
    A4 = "A4.wav",
    B4 = "B4.wav",
    C4 = "C4.wav",
    D4 = "D4.wav",
    E4 = "E4.wav",
    F4 = "F4.wav",
    G4 = "G4.wav",
    
    -- Octava 5
    C5 = "C5.wav",
    D5 = "D5.wav",
    E5 = "E5.wav",
    F5 = "F5.wav"
}

-- Keyboard to note mapping
local keyToNote = {
    -- Fila superior: Q W E R T Y U I O P
    q = "C3", w = "D3", e = "E3", r = "F3", t = "G3", 
    y = "A4", u = "B4", i = "C5", o = "D5", p = "E5",
    
    -- Fila media: A S D F G H J K L
    a = "A2", s = "C4", d = "D4", f = "E4", g = "F4", 
    h = "G4", j = "A4", k = "B4", l = "C5",
    
    -- Fila inferior: Z X C V B N M
    z = "D5", x = "E5", c = "F5"
}

-- Voice allocation for polyphony
local voices = {}
local nextChannel = 0
local maxVoices = 8

-- Play note function using SoundSystem:PlayWav (method that WORKS!)
local function playNoteFromROM(noteName, velocity)
    -- Get WAV filename for this note
    local wavFile = noteToWav[noteName]
    if not wavFile then
        if CLI and CLI._out then
            CLI:_out("RETROMIXER: No WAV file for note: " .. tostring(noteName), Color(255, 0, 0))
        end
        return false
    end
    
    -- Load the specific note from ROM
    local noteSample = nil
    pcall(function()
        noteSample = rom.User.AudioSamples[wavFile]
    end)
    
    if not noteSample then
        if CLI and CLI._out then
            CLI:_out("RETROMIXER: ERROR - " .. wavFile .. " not found in ROM!", Color(255, 0, 0))
        end
        return false
    end
    
    print("3NOTA:", noteSample)
    -- Use SoundSystem:PlayWav (the method that WORKS!)
    local success = SoundSystem:PlayWav(noteSample, false)
    
    if CLI and CLI._out then
        CLI:_out("RETROMIXER: Playing " .. noteName .. " (" .. wavFile .. ") using SoundSystem:PlayWav", Color(0, 255, 255))
        if success then
            CLI:_out("RETROMIXER: *** " .. noteName .. " PLAYING! ***", Color(255, 255, 255))
        else
            CLI:_out("RETROMIXER: ERROR - SoundSystem:PlayWav failed!", Color(255, 0, 0))
        end
    end
    
    return success
end

---------------------------------------------------------------------------
-- Input Handling
function RetroMixer:HandleKey(name, shift, ctrl)
    print("RETROMIXER: HandleKey called with: " .. tostring(name))
    
    -- Help toggle
    if ctrl and name == "I" then
        print("RETROMIXER: Help toggle")
        synthState.showHelp = not synthState.showHelp
        return
    end
    
    -- Exit
    if name == "Escape" then
        print("RETROMIXER: Exit")
        if _onClose then _onClose() end
        return
    end
    
    -- Don't process other keys in help mode
    if synthState.showHelp then 
        print("RETROMIXER: In help mode, ignoring key")
        return 
    end
    
    -- Musical note handling
    local lowerName = name:lower()
    local note = keyToNote[lowerName]
    
    if note then
        print("RETROMIXER: Musical note detected: " .. lowerName .. " -> " .. tostring(note))
        playNoteFromROM(note, 100)
    else
        print("RETROMIXER: Not a musical note: " .. tostring(lowerName))
    end
end

function RetroMixer:HandleMouse(button, x, y, buttonDown)
    -- Check if clicking on TEST SOUND button (bigger: 10-120, CONTENT_Y+50 to CONTENT_Y+75)
    if buttonDown and x >= 10 and x <= 120 and y >= BD.CONTENT_Y + 50 and y <= BD.CONTENT_Y + 75 then
        print("MOUSE: Clicked TEST SOUND button!")
        if CLI and CLI._out then
            CLI:_out("MOUSE: TEST SOUND button clicked!", Color(255, 255, 0))
        end
        
        -- Test sound directly
        playNoteFromROM("C4", 100)
        return
    end
end

---------------------------------------------------------------------------
-- Update Function
function RetroMixer:Update()
    -- Only process audio if audio chip is available
    if _audioChip then
        -- Update audio phase
        audioPhase = audioPhase + 1.0 / SAMPLE_RATE
        
        -- Process audio safely
        pcall(processAudio)
        
        -- Update sequencer safely
        pcall(updateSequencer)
    end
end

---------------------------------------------------------------------------
-- Initialization
function RetroMixer:Init(video, font, theme, onClose)
    print("RETROMIXER: Init started!")
    
    _video = video
    _font = font
    _theme = theme
    _onClose = onClose
    
    print("RETROMIXER: Variables assigned")
    
    -- Initialize audio chip
    pcall(function() _audioChip = gdt.AudioChip0 end)
    print("RETROMIXER: AudioChip initialized: " .. tostring(_audioChip ~= nil))
    
    -- Initialize sequencer grid safely
    if not synthState.sequencerGrid then
        synthState.sequencerGrid = {}
    end
    for beat = 1, MAX_SEQUENCER_STEPS do
        if not synthState.sequencerGrid[beat] then
            synthState.sequencerGrid[beat] = {}
        end
        for note = 1, 8 do
            synthState.sequencerGrid[beat][note] = false
        end
    end
    
    print("RETROMIXER: Sequencer initialized")
    
    -- Load first preset safely
    if presets and #presets > 0 then
        loadPreset(1)
        print("RETROMIXER: Preset loaded")
    end
    
    -- Reset audio phase
    audioPhase = 0
    
    print("RETROMIXER: Init completed!")
end

---------------------------------------------------------------------------
-- Return module for require()
return RetroMixer
