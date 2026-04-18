---------------------------------------------------------------------------
-- SaveSystem.lua — Persistencia en FlashMemory
-- Usa globales: BD, VFS. NO hace require de nada.
-- FlashMemory.Save(table) / Load() — una sola tabla Lua.
---------------------------------------------------------------------------

SaveSystem = {}
local _flash = nil

function SaveSystem:Init(flashMem)
    _flash = flashMem
end

function SaveSystem:HasData()
    return _flash ~= nil and _flash.Usage > 0
end

function SaveSystem:Save(config)
    if not _flash then return false end
    return _flash:Save({
        version = BD.SAVE_VERSION,
        config  = {
            username = (config and config.username) or "Victor",
            theme    = (config and config.theme) or 0,
        },
        vfs = VFS:Serialize(),
    })
end

function SaveSystem:Load()
    if not self:HasData() then return nil end
    local data = _flash:Load()
    if not data or data.version ~= BD.SAVE_VERSION then
        VFS:Init(); return nil
    end
    VFS:Deserialize(data.vfs)
    return data.config
end

return SaveSystem