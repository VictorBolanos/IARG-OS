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

-- Grid Sequencer Playback Function
local function updateGridSequencer()
    if not sequencer.isPlaying then return end
    
    -- Update play timer
    sequencer.playTimer = sequencer.playTimer + (1.0 / 60.0) -- Assuming 60 FPS
    
    -- Check if it's time to advance to next step (fixed 0.5s per step)
    if sequencer.playTimer >= 0.5 then
        sequencer.playTimer = 0
        
        -- Play notes for current step across all channels
        for channel = 1, 8 do
            local cell = sequencer.grid[channel][sequencer.currentPlayStep]
            if cell.active and cell.note then
                -- Play note with its mode
                playNoteFromROM(cell.note, cell.mode, channel)
            end
        end
        
        -- Advance to next step
        sequencer.currentPlayStep = sequencer.currentPlayStep + 1
        
        -- Loop back to beginning if reached end
        if sequencer.currentPlayStep > sequencer.maxSteps then
            sequencer.currentPlayStep = 1
        end
        
        -- Auto-scroll to follow playback
        if sequencer.currentPlayStep > sequencer.scrollOffset + sequencer.visibleSteps then
            sequencer.scrollOffset = sequencer.currentPlayStep - sequencer.visibleSteps
        elseif sequencer.currentPlayStep < sequencer.scrollOffset + 1 then
            sequencer.scrollOffset = sequencer.currentPlayStep - 1
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
    
    local y = BD.CONTENT_Y + 2
    local lineHeight = 7
    
    -- Page 1: Grid Navigation
    if helpPage == 1 then
        tp(10, y, "RETROWAVE 3000 - GRID NAVIGATION (1/4)", getThemeColor("success"))
        y = y + lineHeight + 3
        
        tp(10, y, "GRID CONTROLS:", getThemeColor("success"))
        y = y + lineHeight
        tp(10, y, "  Up/Down: Change Channel (Row)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  Left/Right: Change Step (Column)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  Tab: Toggle Duration (0.5s/1.0s)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  Ctrl+Arrows: Scroll Horizontal", getThemeColor("text"))
        y = y + lineHeight + 3
        
        tp(10, y, "CELL ACTIONS:", getThemeColor("success"))
        y = y + lineHeight
        tp(10, y, "  Enter: Toggle Cell Active/Empty", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  Delete: Clear Cell Content", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  Q-P,A-L,Z-C: Add Note to Cell", getThemeColor("text"))
    
    -- Page 2: Note Modes
    elseif helpPage == 2 then
        tp(10, y, "RETROWAVE 3000 - NOTE MODES (2/4)", getThemeColor("success"))
        y = y + lineHeight + 3
        
        tp(10, y, "MODES (1-9 KEYS):", getThemeColor("success"))
        y = y + lineHeight
        tp(10, y, "  1: Normal     2: Reverb    3: Delay", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  4: Distortion 5: Chorus    6: Flanger", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  7: Phaser     8: PitchBend 9: Glissando", getThemeColor("text"))
        y = y + lineHeight + 3
        
        tp(10, y, "HOW TO USE:", getThemeColor("success"))
        y = y + lineHeight
        tp(10, y, "  1. Activate cell with Enter", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  2. Add note with Q-P,A-L,Z-C", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  3. Press 1-9 to apply mode", getThemeColor("text"))
    
    -- Page 3: Playback & Files
    elseif helpPage == 3 then
        tp(10, y, "RETROWAVE 3000 - PLAYBACK & FILES (3/4)", getThemeColor("success"))
        y = y + lineHeight + 3
        
        tp(10, y, "PLAYBACK:", getThemeColor("success"))
        y = y + lineHeight
        tp(10, y, "  Space: Play/Stop Sequence", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  BPM: 120 (adjustable)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  8 Channels x 64 Steps Max", getThemeColor("text"))
        y = y + lineHeight + 3
        
        tp(10, y, "FILE OPERATIONS:", getThemeColor("success"))
        y = y + lineHeight
        tp(10, y, "  Ctrl+S: Save Pattern (.wavy)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  Ctrl+L: Load Pattern (.wavy)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  C: Clear All Grid", getThemeColor("text"))
    
    -- Page 4: Tips & Tricks
    else
        tp(10, y, "RETROWAVE 3000 - TIPS & TRICKS (4/4)", getThemeColor("success"))
        y = y + lineHeight + 3
        
        tp(10, y, "QUICK START:", getThemeColor("success"))
        y = y + lineHeight
        tp(10, y, "  1. Navigate to CH1,STEP1", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  2. Press Enter (activate)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  3. Press Q (adds C3 note)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  4. Press 2 (adds reverb)", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  5. Press Space (play)", getThemeColor("text"))
        y = y + lineHeight + 3
        
        tp(10, y, "ADVANCED:", getThemeColor("success"))
        y = y + lineHeight
        tp(10, y, "  Create drum patterns on CH1-2", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  Use CH5-8 for melodies", getThemeColor("text"))
        y = y + lineHeight
        tp(10, y, "  Experiment with modes!", getThemeColor("text"))
    end
    
    -- Navigation hint at bottom
    y = BD.CONTENT_Y + 70
    tp(10, y, "Use Arrow Keys to Navigate Pages | Ctrl+I: Exit Help", getThemeColor("dim"))
end

-- Initialize sequencer BEFORE drawMainInterface
local sequencer = {
    bpm = 120,
    currentChannel = 1,
    currentStep = 1,
    scrollOffset = 0,
    maxSteps = 64,
    isPlaying = false,
    playTimer = 0,
    currentPlayStep = 1,
    grid = {}, -- [channel][step] = {note, mode, duration}
    channels = {},
    visibleSteps = 8 -- steps visible on screen
}

-- Note modes with volume and pitch settings (expanded to 5 modes)
local noteModes = {
    [1] = "Normal",
    [2] = "Soft", 
    [3] = "High",
    [4] = "Low",
    [5] = "Sharp"
}

local modeSettings = {
    [1] = { name = "Normal", volume = 100, pitch = 1.0 },  -- Standard volume and pitch
    [2] = { name = "Soft", volume = 50, pitch = 1.0 },     -- Half volume, normal pitch
    [3] = { name = "High", volume = 100, pitch = 1.5 },     -- Full volume, higher pitch
    [4] = { name = "Low", volume = 100, pitch = 0.8 },     -- Full volume, lower pitch
    [5] = { name = "Sharp", volume = 75, pitch = 1.2 }      -- Medium volume, sharp pitch
}

-- Initialize sequencer grid
for channel = 1, 8 do
    sequencer.channels[channel] = {
        name = "Channel " .. channel,
        active = true,
        muted = false
    }
    sequencer.grid[channel] = {}
    for step = 1, sequencer.maxSteps do
        sequencer.grid[channel][step] = {
            note = nil,
            mode = 1,
            duration = 0.5,
            active = false,
            unlocked = false -- New state: unlocked for note input
        }
    end
end

-- Add selector lock state
sequencer.selectorLocked = false

-- Remember last used mode for new notes
sequencer.lastUsedMode = 1

-- Grid playback variables
sequencer.isPlaying = false
sequencer.currentPlayColumn = 1
sequencer.playTimer = 0
sequencer.maxColumns = 64  -- Maximum steps in grid

-- Extended column system variables
sequencer.totalColumns = 8        -- Total columns (starts at 8, can grow)
sequencer.visibleColumns = 12       -- Maximum visible columns on screen
sequencer.scrollOffset = 0          -- Horizontal scroll offset
sequencer.maxVisibleColumns = 12    -- Maximum columns that fit on screen


-- Note to WAV file mapping (MOVED HERE)
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

-- Keyboard to note mapping (MOVED HERE)
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

-- Play note function using AudioChip with mode settings (MOVED HERE)
local function playNoteFromROM(noteName, mode, channel)
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
    
    -- Get mode settings
    local settings = modeSettings[mode] or modeSettings[1]
    
    -- Use AudioChip with mode settings on specific channel
    _audioChip:Play(noteSample, channel)
    _audioChip:SetChannelVolume(settings.volume, channel)
    _audioChip:SetChannelPitch(settings.pitch, channel)
    
    print("PLAYING: " .. noteName .. " on channel " .. channel .. " with " .. settings.name .. " (vol:" .. settings.volume .. " pitch:" .. settings.pitch .. ")")
    
    return true
end

-- Function to find the last column with any notes
local function findLastColumnWithNotes()
    local lastColumn = 1
    for column = 1, sequencer.maxColumns do
        -- Check if any channel has a note in this column
        for channel = 1, 8 do
            local cell = sequencer.grid[channel][column]
            if cell.note then
                lastColumn = column
                break  -- Found a note in this column, move to next column
            end
        end
    end
    print("LAST COLUMN WITH NOTES: " .. lastColumn)
    return lastColumn
end

-- Function to auto-scroll when selector moves outside visible area
local function autoScrollToKeepSelectorVisible()
    local visibleStart = sequencer.scrollOffset + 1
    local visibleEnd = sequencer.scrollOffset + sequencer.visibleColumns
    
    -- Check if selector is to the right of visible area
    if sequencer.currentStep > visibleEnd then
        sequencer.scrollOffset = sequencer.currentStep - sequencer.visibleColumns
        print("AUTO-SCROLL RIGHT: Selector at column " .. sequencer.currentStep .. " - Scrolling to show it")
    end
    
    -- Check if selector is to the left of visible area
    if sequencer.currentStep < visibleStart then
        sequencer.scrollOffset = sequencer.currentStep - 1
        print("AUTO-SCROLL LEFT: Selector at column " .. sequencer.currentStep .. " - Scrolling to show it")
    end
    
    -- Ensure scroll limits are respected
    sequencer.scrollOffset = math.max(0, sequencer.scrollOffset)
    local maxScroll = math.max(0, sequencer.totalColumns - sequencer.visibleColumns)
    sequencer.scrollOffset = math.min(maxScroll, sequencer.scrollOffset)
end

-- Function to add a new column to the grid
local function addNewColumn()
    sequencer.totalColumns = sequencer.totalColumns + 1
    
    -- Initialize new column cells for all channels
    for channel = 1, 8 do
        sequencer.grid[channel][sequencer.totalColumns] = {
            active = false,
            note = nil,
            mode = 1
        }
    end
    
    print("COLUMN ADDED: New column " .. sequencer.totalColumns .. " added. Total: " .. sequencer.totalColumns)
    
    -- NO AUTO-SCROLL - Keep current view where it is
    print("VIEW LOCKED: Staying at current position - Use Ctrl+Flechas to scroll manually")
end

-- Function to play all notes in a specific column
local function playColumn(column)
    print("PLAYING COLUMN: " .. column)
    
    for channel = 1, 8 do
        local cell = sequencer.grid[channel][column]
        if cell.note then
            -- Play note with its mode settings on its specific channel
            playNoteFromROM(cell.note, cell.mode, channel)
            print("  Channel " .. channel .. ": " .. cell.note .. " (mode " .. cell.mode .. ")")
        end
    end
end

-- Helper function to get theme color with fallback (like Chess and Tetris)
local function getThemeColor(colorName)
    -- Use actual theme properties from IARG Classic
    if colorName == "bg_desktop" then
        return _theme.bg or Color(18, 18, 32)
    elseif colorName == "text_primary" then
        return _theme.text or Color(220, 220, 240)
    elseif colorName == "text_secondary" then
        return _theme.dim or Color(130, 130, 155)
    elseif colorName == "text_accent" then
        return _theme.text or Color(80, 200, 255) -- Use text as accent
    elseif colorName == "text_success" then
        return _theme.success or Color(80, 220, 120)
    elseif colorName == "text_warning" then
        return _theme.error or Color(255, 200, 60)
    elseif colorName == "bg_panel" then
        return _theme.bg or Color(12, 12, 24)
    elseif colorName == "bg_hover" then
        return _theme.bg or Color(38, 38, 70)
    elseif colorName == "border" then
        return _theme.dim or Color(55, 55, 80)
    elseif colorName == "border_focus" then
        return _theme.text or Color(80, 200, 255)
    else
        return _theme.text or Color(255, 255, 255) -- Default fallback
    end
end

local function drawMainInterface()
    -- Clear screen with theme background (with fallback)
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(_video.Width - 1, _video.Height - 1), getThemeColor("bg_desktop"))
    
    local tp = function(x, y, txt, col)
        for i = 1, #txt do
            local ch = txt:sub(i, i)
            _video:DrawSprite(vec2(x + (i-1) * 4, y), _font,
                ch:byte()%32, math.floor(ch:byte()/32), col, color.clear)
        end
    end
    
    -- Header
    tp(10, BD.CONTENT_Y + 2, "RETROWAVE 3000 - GRID SEQUENCER", getThemeColor("text_primary"))
    
    -- Status bar
    local statusY = BD.CONTENT_Y + 10
    local statusText = "BPM:" .. sequencer.bpm .. "  "
    if sequencer.isPlaying then
        local lastColumnWithNotes = findLastColumnWithNotes()
        statusText = statusText .. "PLAYING COL:" .. sequencer.currentPlayColumn .. "/" .. lastColumnWithNotes .. " (LOOP)"
    else
        statusText = statusText .. "STOPPED"
    end
    
    -- Add column system info
    statusText = statusText .. " | COLS:" .. sequencer.totalColumns
    if sequencer.scrollOffset > 0 then
        statusText = statusText .. " ◄"
    end
    if sequencer.scrollOffset < sequencer.totalColumns - sequencer.visibleColumns then
        statusText = statusText .. " ►"
    end
    
    -- Add selector lock status
    if sequencer.selectorLocked then
        statusText = statusText .. " | LOCKED"
    else
        statusText = statusText .. " | FREE"
    end
    
    tp(10, statusY, statusText, getThemeColor("text_accent"))
    
    -- Grid - moved lower and 30% larger (15x11 -> 16x12 = 5% increase)
    local gridStartY = BD.CONTENT_Y + 30 -- Moved 5px down
    local cellWidth = 16  -- 15 -> 16 (5% larger)
    local cellHeight = 12 -- 11 -> 12 (5% larger)
    local gridStartX = 55 -- Adjusted for larger cells
    
    -- Draw column headers (step numbers) - using extended column system
    for step = 1, sequencer.visibleColumns do
        local actualColumn = sequencer.scrollOffset + step
        if actualColumn <= sequencer.totalColumns then
            local x = gridStartX + (step-1) * cellWidth
            tp(x, gridStartY - 8, tostring(actualColumn), getThemeColor("text_secondary"))
        end
    end
    
    -- Draw grid rows (channels)
    for channel = 1, 8 do
        local y = gridStartY + (channel-1) * cellHeight
        
        -- Channel label
        tp(10, y, "CH" .. channel, getThemeColor("text_accent"))
        
        -- Debug: Show channel position
        if CLI and CLI._out and channel == 1 then
            CLI:_out("GRID: Channel 1 at y=" .. y .. " gridStartY=" .. gridStartY, Color(255, 255, 0))
        end
        
        -- Grid cells - using extended column system
        for step = 1, sequencer.visibleColumns do
            local actualColumn = sequencer.scrollOffset + step
            if actualColumn <= sequencer.totalColumns then
                local x = gridStartX + (step-1) * cellWidth
                local cell = sequencer.grid[channel][actualColumn]
            
            -- Debug: First cell
            if CLI and CLI._out and channel == 1 and step == 1 then
                CLI:_out("GRID: Cell 1,1 at x=" .. x .. " y=" .. y .. " size=" .. cellWidth .. "x" .. cellHeight, Color(255, 255, 0))
            end
            
            -- Cell background - Theme colors based on active state, with playback indicator
            if cell.active then
                -- Check if this is the currently playing column
                if sequencer.isPlaying and actualColumn == sequencer.currentPlayColumn then
                    _video:FillRect(vec2(x, y), vec2(x + cellWidth - 1, y + cellHeight - 1), getThemeColor("text_warning")) -- Warning color for playing
                else
                    _video:FillRect(vec2(x, y), vec2(x + cellWidth - 1, y + cellHeight - 1), getThemeColor("text_success")) -- Success color for active
                end
            else
                -- Check if this is the currently playing column (even if empty)
                if sequencer.isPlaying and actualColumn == sequencer.currentPlayColumn then
                    _video:FillRect(vec2(x, y), vec2(x + cellWidth - 1, y + cellHeight - 1), getThemeColor("bg_hover")) -- Hover color for playing empty
                else
                    _video:FillRect(vec2(x, y), vec2(x + cellWidth - 1, y + cellHeight - 1), getThemeColor("bg_panel")) -- Panel color for inactive
                end
            end
            
            -- Cell border - Theme colors for current position and others
            if channel == sequencer.currentChannel and actualColumn == sequencer.currentStep then
                _video:DrawRect(vec2(x, y), vec2(x + cellWidth - 1, y + cellHeight - 1), getThemeColor("border_focus")) -- Focus border for selector
            else
                _video:DrawRect(vec2(x, y), vec2(x + cellWidth - 1, y + cellHeight - 1), getThemeColor("border")) -- Standard border
            end
            
            -- Cell content (note)
            if cell.note then
                local noteText = string.sub(cell.note, 1, 2) -- First 2 chars
                tp(x + 4, y + 2, noteText, getThemeColor("text_primary")) -- Moved 2px down in 16x12 cell
            end
        end
    end
    
    -- Close the if statement for visible columns
    end
    
    -- Right side info panel
    local rightPanelX = 250 -- Start of right panel
    local rightPanelY = BD.CONTENT_Y + 10
    
    -- Current cell info - show note and mode if exists
    local currentCell = sequencer.grid[sequencer.currentChannel][sequencer.currentStep]
    
    -- Cell info
    local cellInfoText = "CH:" .. sequencer.currentChannel
    tp(rightPanelX, rightPanelY, cellInfoText, getThemeColor("text_secondary"))
    
    if currentCell.note then
        -- Cell has note - show detailed info
        local noteInfoText = "NOTE:" .. currentCell.note
        tp(rightPanelX, rightPanelY + 16, noteInfoText, getThemeColor("text_success"))
        
        local modeInfoText = "MODE:" .. noteModes[currentCell.mode]
        tp(rightPanelX, rightPanelY + 24, modeInfoText, getThemeColor("text_accent"))
        
        if sequencer.selectorLocked then
            local editText = "EDITING"
            tp(rightPanelX, rightPanelY + 32, editText, getThemeColor("text_warning"))
        end
    else
        -- Cell is empty - show basic info
        local emptyText = "EMPTY"
        tp(rightPanelX, rightPanelY + 16, emptyText, getThemeColor("text_secondary"))
        
        if sequencer.selectorLocked then
            local readyText = "READY"
            tp(rightPanelX, rightPanelY + 24, readyText, getThemeColor("text_warning"))
        end
    end
    
    -- Mode legend (show 5 available modes)
    local legendY = rightPanelY + 40
    tp(rightPanelX, legendY, "MODES:", getThemeColor("text_primary"))
    tp(rightPanelX, legendY + 8, "1:Normal", getThemeColor("text_secondary"))
    tp(rightPanelX, legendY + 16, "2:Soft", getThemeColor("text_secondary"))
    tp(rightPanelX, legendY + 24, "3:High", getThemeColor("text_secondary"))
    tp(rightPanelX, legendY + 32, "4:Low", getThemeColor("text_secondary"))
    tp(rightPanelX, legendY + 40, "5:Sharp", getThemeColor("text_secondary"))
    
    -- Controls hint (bottom area)
    local controlY = BD.CONTENT_Y + 140 -- Moved up 5px for visibility
    tp(10, controlY, "Q-P,A-L,Z-C:Notes | 1-5:Modes | Arrows:Nav | Space:Play | Enter:Toggle", getThemeColor("text_secondary"))
    local controlY2 = controlY + 7
    tp(10, controlY2, "Ctrl+N:AddCol | Ctrl+◄►:Scroll | Ctrl+S:Save | Ctrl+L:Load | Ctrl+C:Clear | Delete:ClearCell", getThemeColor("text_secondary"))
    
    -- Debug: Show activeApp status
    if CLI and CLI._out then
        CLI:_out("DRAW: RetroMixer Grid Sequencer drawing!", Color(0, 255, 0))
    end
end

---------------------------------------------------------------------------
-- Main Draw Function
function RetroMixer:Draw()
    if not _video then 
        if CLI and CLI._out then
            CLI:_out("DRAW: No _video available!", Color(255, 0, 0))
        end
        return 
    end
    
    -- Debug: Always show we're drawing
    if CLI and CLI._out then
        CLI:_out("DRAW: RetroMixer Draw() called!", Color(0, 255, 255))
    end
    
    -- Draw interface directly without pcall
    if synthState.showHelp then
        drawHelpScreen()
    else
        drawMainInterface()
    end
end

---------------------------------------------------------------------------
-- Audio Functions (must be defined before HandleKey)

-- noteToWav and keyToNote moved above to avoid "attempt to call a nil value" errors

-- Voice allocation for polyphony
local voices = {}
local nextChannel = 0
local maxVoices = 8

-- Help System
local helpPage = 1
local maxHelpPages = 4

-- playNoteFromROM function moved above to avoid "attempt to call a nil value" error

---------------------------------------------------------------------------
-- Input Handling
function RetroMixer:HandleKey(name, shift, ctrl)
    -- Debug ALL keys to see what's happening
    print("KEY PRESSED: '" .. tostring(name) .. "' shift=" .. tostring(shift) .. " ctrl=" .. tostring(ctrl))
    
    -- Handle key input
    
    -- DEBUG: Check if 1-5 keys are being detected
    if name == "Alpha1" or name == "Alpha2" or name == "Alpha3" or name == "Alpha4" or name == "Alpha5" then
        print("MODE KEY DETECTED: " .. name)
    end
    
    -- Help toggle - FIRST PRIORITY
    if ctrl and name == "I" then
        synthState.showHelp = not synthState.showHelp
        return
    end
    
    -- Exit - SECOND PRIORITY
    if name == "Escape" then
        -- Return to CLI (like other apps)
        if _onClose then
            _onClose()
        end
        return
    end
    
    -- Help navigation
    if synthState.showHelp then 
        if name == "Left" then
            helpPage = math.max(1, helpPage - 1)
            return
        elseif name == "Right" then
            helpPage = math.min(maxHelpPages, helpPage + 1)
            return
        end
        print("RETROMIXER: In help mode, ignoring key")
        return 
    end
    
    -- Extended column system controls - HIGHEST PRIORITY
    if ctrl then
        if name == "N" then
            -- Add new column
            addNewColumn()
            return
        elseif name == "Left" then
            -- Scroll left
            sequencer.scrollOffset = math.max(0, sequencer.scrollOffset - 1)
            print("SCROLL LEFT: Offset " .. sequencer.scrollOffset .. " (showing columns " .. (sequencer.scrollOffset + 1) .. "-" .. (sequencer.scrollOffset + sequencer.visibleColumns) .. ")")
            return
        elseif name == "Right" then
            -- Scroll right
            local maxScroll = math.max(0, sequencer.totalColumns - sequencer.visibleColumns)
            sequencer.scrollOffset = math.min(maxScroll, sequencer.scrollOffset + 1)
            print("SCROLL RIGHT: Offset " .. sequencer.scrollOffset .. " (showing columns " .. (sequencer.scrollOffset + 1) .. "-" .. (sequencer.scrollOffset + sequencer.visibleColumns) .. ")")
            return
        end
    end
    
    -- Grid sequencer controls
    if name == "Space" then
        if sequencer.isPlaying then
            -- Stop playback and reset
            sequencer.isPlaying = false
            sequencer.currentPlayColumn = 1
            sequencer.playTimer = 0
            print("GRID PLAYBACK STOPPED - Reset to start")
        else
            -- Start continuous loop playback from beginning
            sequencer.isPlaying = true
            sequencer.currentPlayColumn = 1
            sequencer.playTimer = 0
            print("GRID LOOP STARTED - Continuous playback from column 1")
            -- Play first column immediately
            playColumn(1)
        end
        return
    elseif name == "Return" then
        -- Toggle selector lock AND cell unlock
        sequencer.selectorLocked = not sequencer.selectorLocked
        local currentCell = sequencer.grid[sequencer.currentChannel][sequencer.currentStep]
        
        if sequencer.selectorLocked then
            -- Lock selector and unlock cell for editing
            currentCell.unlocked = true
            print("SELECTOR LOCKED")
        else
            -- Unlock selector and lock cell
            currentCell.unlocked = false
            print("SELECTOR UNLOCKED")
        end
        return
    elseif name == "Delete" then
        -- Clear current cell completely
        local currentCell = sequencer.grid[sequencer.currentChannel][sequencer.currentStep]
        currentCell.active = false
        currentCell.unlocked = false
        currentCell.note = nil
        currentCell.mode = 1
        print("CELL CLEARED")
        return
    elseif name == "C" and ctrl then
        -- Clear all grid with Ctrl+C
        for channel = 1, 8 do
            for step = 1, sequencer.maxSteps do
                sequencer.grid[channel][step] = {
                    note = nil,
                    mode = 1,
                    duration = 0.5,
                    active = false,
                    unlocked = false
                }
            end
        end
        sequencer.selectorLocked = false -- Reset selector lock
        sequencer.lastUsedMode = 1 -- Reset last used mode
        print("GRID CLEARED")
        return
    end
    
    -- Grid navigation - ONLY IF SELECTOR NOT LOCKED
    if not sequencer.selectorLocked then
        if name == "UpArrow" then
            -- Change channel up
            sequencer.currentChannel = math.max(1, sequencer.currentChannel - 1)
            return
        elseif name == "DownArrow" then
            -- Change channel down
            sequencer.currentChannel = math.min(8, sequencer.currentChannel + 1)
            return
        elseif name == "LeftArrow" then
            if ctrl then
                -- Scroll horizontal left
                sequencer.scrollOffset = math.max(0, sequencer.scrollOffset - 1)
            else
                -- Change step left
                sequencer.currentStep = math.max(1, sequencer.currentStep - 1)
                -- Auto-scroll to keep selector visible
                autoScrollToKeepSelectorVisible()
            end
            return
        elseif name == "RightArrow" then
            if ctrl then
                -- Scroll horizontal right
                sequencer.scrollOffset = math.min(sequencer.totalColumns - sequencer.visibleColumns, sequencer.scrollOffset + 1)
            else
                -- Change step right
                sequencer.currentStep = math.min(sequencer.totalColumns, sequencer.currentStep + 1)
                -- Auto-scroll to keep selector visible
                autoScrollToKeepSelectorVisible()
            end
            return
        end
    end
    
    -- Note modes (1-5) - apply to cells with notes and replay
    print("CHECKING MODE: not ctrl=" .. tostring(not ctrl) .. " name=" .. tostring(name))
    if not ctrl and (name == "Alpha1" or name == "Alpha2" or name == "Alpha3" or name == "Alpha4" or name == "Alpha5") then
        print("MODE CONDITION MET!")
        local modeNum = 0
        if name == "Alpha1" then modeNum = 1
        elseif name == "Alpha2" then modeNum = 2
        elseif name == "Alpha3" then modeNum = 3
        elseif name == "Alpha4" then modeNum = 4
        elseif name == "Alpha5" then modeNum = 5
        end
        
        local currentCell = sequencer.grid[sequencer.currentChannel][sequencer.currentStep]
        
        print("DEBUG: Selector locked=" .. tostring(sequencer.selectorLocked) .. " Cell note=" .. tostring(currentCell.note) .. " Cell mode=" .. tostring(currentCell.mode))
        
        if currentCell.note then
            print("MODE CHANGE: " .. currentCell.mode .. " -> " .. modeNum)
            currentCell.mode = modeNum
            sequencer.lastUsedMode = modeNum -- Update last used mode
            print("MODE SET: " .. modeNum .. " (" .. noteModes[modeNum] .. ")")
            
            -- Replay the note with new mode
            playNoteFromROM(currentCell.note, modeNum, sequencer.currentChannel)
        else
            print("MODE ERROR: No note in cell")
        end
        return
    else
        print("MODE CONDITION FAILED")
    end
    
    -- Musical note handling - LAST PRIORITY (only if not Ctrl)
    if not ctrl then
        local lowerName = name:lower()
        local note = keyToNote[lowerName]
        
        if note then
            local currentCell = sequencer.grid[sequencer.currentChannel][sequencer.currentStep]
            local mode = currentCell.mode or 1
            playNoteFromROM(note, mode, sequencer.currentChannel)
            
            -- Add note to current cell IF SELECTED (locked or unlocked)
            if sequencer.selectorLocked then
                -- Change note in selected cell
                currentCell.note = note
                currentCell.active = true
                currentCell.mode = currentCell.mode or sequencer.lastUsedMode -- Keep existing mode
                print("NOTE CHANGED: " .. note .. " (mode " .. currentCell.mode .. ")")
            elseif currentCell.unlocked then
                -- Add note to unlocked cell
                currentCell.note = note
                currentCell.active = true
                currentCell.mode = sequencer.lastUsedMode -- Use last used mode
                currentCell.unlocked = false -- Auto-lock after adding note
                print("NOTE ADDED: " .. note .. " (mode " .. currentCell.mode .. ")")
            end
        end
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
-- Update
function RetroMixer:Update()
    -- Process audio (keep existing audio processing)
    pcall(processAudio)
    
    -- Update sequencer (keep existing sequencer logic)
    pcall(updateSequencer)
    
    -- Update grid playback timer
    if sequencer.isPlaying then
        sequencer.playTimer = sequencer.playTimer + 1
        
        -- Check if 1 second has passed (assuming 60 FPS = 60 ticks per second)
        if sequencer.playTimer >= 60 then
            sequencer.playTimer = 0
            sequencer.currentPlayColumn = sequencer.currentPlayColumn + 1
            
            -- Find the actual last column with notes for intelligent looping
            local lastColumnWithNotes = findLastColumnWithNotes()
            
            -- Check if we've passed the last column with notes - LOOP BACK TO START
            if sequencer.currentPlayColumn > lastColumnWithNotes then
                -- Loop back to first column for continuous playback
                sequencer.currentPlayColumn = 1
                print("INTELLIGENT LOOP: Back to column 1 - Last note was at column " .. lastColumnWithNotes)
            end
            
            -- Play current column (works for both normal and looped playback)
            playColumn(sequencer.currentPlayColumn)
        end
    end
end

---------------------------------------------------------------------------
-- Update Function (COMPLETED ABOVE)
-- The Update function is already defined above with grid playback logic

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
