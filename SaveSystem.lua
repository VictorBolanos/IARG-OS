---------------------------------------------------------------------------
-- SaveSystem.lua -- FlashMemory persistence
---------------------------------------------------------------------------

-- BD, VFS are globals loaded by IARG-OS.lua
SaveSystem = {}
local flash = nil

function SaveSystem:Init(f) flash=f end
function SaveSystem:HasData() return flash~=nil and flash.Usage>0 end

function SaveSystem:Save(config)
    if not flash then return false end
    return flash:Save({
        version = BD.SAVE_VERSION,
        config  = { username=config.username or "user", theme=config.theme or 0 },
        vfs     = VFS:Serialize(),
    })
end

function SaveSystem:Load()
    if not self:HasData() then return nil end
    local data=flash:Load()
    if not data or data.version~=BD.SAVE_VERSION then VFS:Init(); return nil end
    VFS:Deserialize(data.vfs)
    return data.config
end

function SaveSystem:SaveHighScores(highScores)
    if not flash then return false end
    local data = flash:Load()
    if not data or data.version ~= BD.SAVE_VERSION then
        data = { version = BD.SAVE_VERSION }
    end
    data.highScores = highScores
    return flash:Save(data)
end

function SaveSystem:LoadHighScores()
    if not self:HasData() then return {} end
    local data = flash:Load()
    if not data or data.version ~= BD.SAVE_VERSION then return {} end
    return data.highScores or {}
end

---------------------------------------------------------------------------

return SaveSystem