---------------------------------------------------------------------------
-- SoundSystem.lua -- Sistema de audio para IARG-OS
-- Soporta melodías, efectos de sonido, archivos WAV y synthesizer básico
---------------------------------------------------------------------------

SoundSystem = {}

-- Hardware de audio (si está disponible)
local _audioChip = nil
local _speakers = {nil, nil, nil, nil}  -- Speaker 0, 1, 2, 3
local _initialized = false

-- Configuración de audio
local _volume = 0.8
local _currentMelody = nil
local _melodyIndex = 0
local _melodyTimer = 0
local _isPlaying = false
local _currentAudioSample = nil
local _audioChannel = 0
local _audioPlaying = false

-- Frecuencias de notas musicales (Hz)
local NOTE_FREQUENCIES = {
    -- Octava 3
    ["C3"] = 130.81, ["C#3"] = 138.59, ["D3"] = 146.83, ["D#3"] = 155.56,
    ["E3"] = 164.81, ["F3"] = 174.61, ["F#3"] = 185.00, ["G3"] = 196.00,
    ["G#3"] = 207.65, ["A3"] = 220.00, ["A#3"] = 233.08, ["B3"] = 246.94,
    
    -- Octava 4
    ["C4"] = 261.63, ["C#4"] = 277.18, ["D4"] = 293.66, ["D#4"] = 311.13,
    ["E4"] = 329.63, ["F4"] = 349.23, ["F#4"] = 369.99, ["G4"] = 392.00,
    ["G#4"] = 415.30, ["A4"] = 440.00, ["A#4"] = 466.16, ["B4"] = 493.88,
    
    -- Octava 5
    ["C5"] = 523.25, ["C#5"] = 554.37, ["D5"] = 587.33, ["D#5"] = 622.25,
    ["E5"] = 659.25, ["F5"] = 698.46, ["F#5"] = 739.99, ["G5"] = 783.99,
    ["G#5"] = 830.61, ["A5"] = 880.00, ["A#5"] = 932.33, ["B5"] = 987.77,
    
    -- Octava 6
    ["C6"] = 1046.50, ["D6"] = 1174.66, ["E6"] = 1318.51, ["F6"] = 1396.91,
    ["G6"] = 1567.98, ["A6"] = 1760.00, ["B6"] = 1975.53
}

---------------------------------------------------------------------------
-- Inicialización del sistema de audio

function SoundSystem:Init(audioChip)
    _audioChip = audioChip
    
    -- Obtener referencias a los speakers
    if audioChip then
        _speakers[0] = gdt.Speaker0
        _speakers[1] = gdt.Speaker1
        _speakers[2] = gdt.Speaker2
        _speakers[3] = gdt.Speaker3
        
        -- Habilitar todos los speakers
        for i = 0, 3 do
            if _speakers[i] then
                _speakers[i].State = true
            end
        end
        
        _initialized = true
        print("SoundSystem: AudioChip0 and Speakers 0-3 initialized")
        print("SoundSystem: Channels available: " .. (_audioChip.ChannelsCount or 0))
    else
        print("SoundSystem: No AudioChip0 available - using simulation mode")
        _initialized = false
    end
    
    -- Configurar volumen por defecto
    SoundSystem:SetVolume(_volume)
    
    return _initialized
end

---------------------------------------------------------------------------
-- Reproducir un tono simple (generando AudioSample sintético)

function SoundSystem:PlayTone(frequency, durationMs)
    if not _initialized then
        -- Modo simulación - imprimir información
        print(string.format("Sound: %.2f Hz for %d ms", frequency, durationMs))
        return true
    end
    
    -- Por ahora, solo simulación hasta que implementemos generación de AudioSamples
    print(string.format("Sound: %.2f Hz for %d ms (simulated)", frequency, durationMs))
    
    -- TODO: Generar AudioSample sintético cuando la API lo permita
    return true
end

---------------------------------------------------------------------------
-- Detener sonido actual

function SoundSystem:Stop()
    if _initialized and _audioChip then
        -- Detener el canal actual
        if _audioChannel >= 0 and _audioChannel < (_audioChip.ChannelsCount or 0) then
            _audioChip:Stop(_audioChannel)
        end
    end
    
    _isPlaying = false
    _currentMelody = nil
    _melodyIndex = 0
    _melodyTimer = 0
    _audioPlaying = false
    _currentAudioSample = nil
    _audioChannel = 0
end

---------------------------------------------------------------------------
-- Configurar volumen

function SoundSystem:SetVolume(vol)
    _volume = math.max(0.0, math.min(1.0, vol))
    
    if _initialized and _audioChip then
        -- AudioChip.Volume usa rango 0-100
        _audioChip.Volume = _volume * 100
    end
end

function SoundSystem:GetVolume()
    return _volume
end

---------------------------------------------------------------------------
-- Reproducir melodía

function SoundSystem:PlayMelody(melody, loop)
    if not melody or #melody == 0 then
        return false
    end
    
    print("Starting melody playback with " .. #melody .. " notes")
    
    _currentMelody = melody
    _melodyIndex = 1
    _melodyTimer = 0
    _isPlaying = true
    
    -- Reproducir primera nota inmediatamente
    local note = melody[1]
    if note then
        local frequency = note.frequency or 440
        local duration = note.duration or 200
        
        print("Playing first note: " .. frequency .. "Hz for " .. duration .. "ms")
        
        if not _initialized then
            -- Modo simulación - imprimir información
            print(string.format("Sound: %.2f Hz for %d ms", frequency, duration))
        else
            -- Intentar reproducir tono directamente
            -- TODO: Implementar generación de AudioSample cuando la API lo permita
            print("AudioChip initialized - playing simulated tone")
        end
    end
    
    return true
end

---------------------------------------------------------------------------
-- Reproducir archivo WAV (AudioSample)

function SoundSystem:PlayWav(audioSample, loop)
    if not audioSample then
        print("Sound: No AudioSample provided")
        return false
    end
    
    if not _initialized then
        -- Modo simulación - imprimir información
        print("Sound: Playing AudioSample '" .. audioSample.Name .. "' (simulated)")
        return true
    end
    
    -- Detener reproducción actual
    SoundSystem:Stop()
    
    -- Seleccionar canal disponible (empezar con canal 0)
    _audioChannel = 0
    
    -- Reproducir el AudioSample
    local success = false
    if loop then
        success = _audioChip:PlayLoop(audioSample, _audioChannel)
    else
        success = _audioChip:Play(audioSample, _audioChannel)
    end
    
    if success then
        _currentAudioSample = audioSample
        _audioPlaying = true
        print("Sound: Playing AudioSample '" .. audioSample.Name .. "' on channel " .. _audioChannel)
        
        -- Configurar volumen del canal
        _audioChip:SetChannelVolume(_volume * 100, _audioChannel)
    else
        print("Sound: Failed to play AudioSample '" .. audioSample.Name .. "'")
    end
    
    return success
end

---------------------------------------------------------------------------
-- Actualizar sistema (para melodías)

function SoundSystem:Update()
    if not _isPlaying or not _currentMelody then
        return
    end
    
    if _melodyTimer <= 0 then
        -- Reproducir nota actual
        local note = _currentMelody[_melodyIndex]
        if note then
            local frequency = note.frequency or 440
            local duration = note.duration or 200
            
            SoundSystem:PlayTone(frequency, duration)
            _melodyTimer = duration
            
            -- Avanzar a siguiente nota
            _melodyIndex = _melodyIndex + 1
            
            -- Verificar si terminó la melodía
            if _melodyIndex > #_currentMelody then
                if loop then
                    _melodyIndex = 1  -- Repetir
                else
                    SoundSystem:Stop()  -- Terminar
                end
            end
        else
            SoundSystem:Stop()
        end
    else
        _melodyTimer = _melodyTimer - 16  -- Asumiendo 60 FPS (16ms por frame)
    end
end

---------------------------------------------------------------------------
-- Estado del sistema

function SoundSystem:IsPlaying()
    return _isPlaying or _audioPlaying
end

function SoundSystem:IsInitialized()
    return _initialized
end

function SoundSystem:IsPlayingAudioSample()
    return _audioPlaying
end

function SoundSystem:IsPlayingMelody()
    return _isPlaying
end

function SoundSystem:GetCurrentAudioSample()
    return _currentAudioSample
end

function SoundSystem:GetCurrentChannel()
    return _audioChannel
end

---------------------------------------------------------------------------
-- Utilidades para melodías

function SoundSystem:CreateNote(noteName, durationMs)
    local frequency = NOTE_FREQUENCIES[noteName] or 440
    return {
        frequency = frequency,
        duration = durationMs
    }
end

function SoundSystem:CreateRest(durationMs)
    return {
        frequency = 0,  -- Silencio
        duration = durationMs
    }
end

---------------------------------------------------------------------------
-- Melodías predefinidas

-- Melodía de arranque (retro style) - fallback si boot.wav no está disponible
SoundSystem.BOOT_MELODY = {
    SoundSystem:CreateNote("C4", 150),
    SoundSystem:CreateNote("E4", 150),
    SoundSystem:CreateNote("G4", 150),
    SoundSystem:CreateNote("C5", 300),
    SoundSystem:CreateNote("G4", 150),
    SoundSystem:CreateNote("E4", 150),
    SoundSystem:CreateNote("C4", 450)
}

-- Referencia al AudioSample de arranque (se cargará desde ROM)
SoundSystem.BOOT_AUDIO_SAMPLE = "boot.wav"

-- Melodía de error
SoundSystem.ERROR_MELODY = {
    SoundSystem:CreateNote("C4", 100),
    SoundSystem:CreateRest(50),
    SoundSystem:CreateNote("C4", 100),
    SoundSystem:CreateRest(50),
    SoundSystem:CreateNote("C4", 200)
}

-- Melodía de éxito
SoundSystem.SUCCESS_MELODY = {
    SoundSystem:CreateNote("C4", 100),
    SoundSystem:CreateNote("E4", 100),
    SoundSystem:CreateNote("G4", 200)
}

---------------------------------------------------------------------------

return SoundSystem
