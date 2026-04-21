---------------------------------------------------------------------------
-- SoundSystem.lua -- Audio system for IARG-OS
--
-- Usage:
--   SoundSystem:Init(audioChip)        -- pass gdt.AudioChip0
--   SoundSystem:PlayBoot(rom)          -- play boot.wav from ROM
--   SoundSystem:PlayWav(sample, loop)  -- play any AudioSample
--   SoundSystem:Stop()                 -- stop current playback
--   SoundSystem:Update()               -- call every tick
---------------------------------------------------------------------------

-- No requires -- BD is global

SoundSystem = {}

local _chip      = nil   -- AudioChip0
local _channel   = 0     -- current active channel
local _playing   = false
local _volume    = 0.8

---------------------------------------------------------------------------
-- Init

function SoundSystem:Init(audioChip)
    _chip = audioChip
    if not _chip then
        log("SoundSystem: no AudioChip0 found")
        return false
    end
    _chip.Volume = math.floor(_volume * 100)
    log("SoundSystem: ready, channels=" .. tostring(_chip.ChannelsCount))
    return true
end

---------------------------------------------------------------------------
-- Play boot.wav from ROM immediately (call before boot animation)

function SoundSystem:PlayBoot(rom)
    if not _chip then return false end
    local sample = nil
    pcall(function()
        sample = rom.User.AudioSamples["boot.wav"]
    end)
    if not sample then
        log("SoundSystem: boot.wav not found in ROM")
        return false
    end
    return self:PlayWav(sample, false)
end

---------------------------------------------------------------------------
-- Play any AudioSample

function SoundSystem:PlayWav(sample, loop)
    print("SoundSystem: PlayWav", sample and sample.Name, "loop=" .. tostring(loop))
    if not _chip or not sample then return false end
    self:Stop()
    local ok = false
    if loop then
        ok = _chip:PlayLoop(sample, _channel)
    else
        ok = _chip:Play(sample, _channel)
    end
    if ok then
        _playing = true
        _chip:SetChannelVolume(math.floor(_volume * 100), _channel)
    end
    return ok
end

---------------------------------------------------------------------------
-- Stop

function SoundSystem:Stop()
    if _chip and _chip.ChannelsCount and _channel < _chip.ChannelsCount then
        _chip:Stop(_channel)
    end
    _playing = false
end

---------------------------------------------------------------------------
-- Volume (0.0 - 1.0)

function SoundSystem:SetVolume(vol)
    _volume = math.max(0, math.min(1, vol))
    if _chip then
        _chip.Volume = math.floor(_volume * 100)
    end
end

function SoundSystem:GetVolume() return _volume end
function SoundSystem:IsPlaying() return _playing end

---------------------------------------------------------------------------
-- Update -- call every tick to track playback state

function SoundSystem:Update()
    if not _playing or not _chip then return end
    -- AudioChip channels stop automatically when sample ends
    -- Check if still playing (if API supports it)
    -- For now, we rely on Stop() being called explicitly
end

---------------------------------------------------------------------------

return SoundSystem