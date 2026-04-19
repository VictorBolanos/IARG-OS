---------------------------------------------------------------------------
-- SaveSystem.lua — Persistencia en FlashMemory
---------------------------------------------------------------------------

local BD = require("BD.lua")
local VFS = require("VFS.lua")
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

---------------------------------------------------------------------------

return SaveSystem