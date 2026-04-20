---------------------------------------------------------------------------
-- Topbar.lua -- Top bar with logo, current directory and real-time clock
--
-- SPRITES:
--   sprOsLogoSmall.png   24x12 px, full image (no grid)
--                          drawn with DrawCustomSprite at actual size
--   sprSystem.png        9x9 px sprites in grid:
--     sx=0, sy=0   Clock
--     sx=0, sy=1   Small folder
--     sx=1, sy=1   Text file
--     (additional rows/cols reserved)
---------------------------------------------------------------------------

-- BD is a global loaded by IARG-OS.lua

Topbar = {}

local _video   = nil
local _font    = nil
local _sprLogo = nil   -- sprOsLogoSmall.png  (24x12)
local _sprSys  = nil   -- sprSystem.png       (9x9 sprites)
local _reality = nil
local _theme   = nil

-- Sprite dimensions
local LOGO_W = 24
local LOGO_H = 12
local ICO_W  = 9
local ICO_H  = 9

---------------------------------------------------------------------------
-- Local tprint

local function tprint(chip, x, y, txt, col)
    if not _font then return end
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        chip:DrawSprite(vec2(x + (i-1)*BD.CHAR_W, y), _font,
            ch:byte()%32, math.floor(ch:byte()/32),
            col, color.clear)
    end
end

---------------------------------------------------------------------------

function Topbar:Init(video, font, sprLogo, sprSys, realityChip)
    _video   = video
    _font    = font
    _sprLogo = sprLogo
    _sprSys  = sprSys
    _reality = realityChip
end

function Topbar:SetTheme(t) _theme = t end

function Topbar:GetTimeStr()
    if not _reality then return "--:--" end
    local dt = _reality:GetDateTime()
    return string.format("%02d:%02d", dt.hour, dt.min)
end

---------------------------------------------------------------------------

function Topbar:Draw(cwd)
    if not _video or not _theme then return end

    -- Background
    _video:FillRect(vec2(0,0), vec2(BD.SW-1, BD.TOPBAR_H-1), _theme.topbar)
    _video:DrawLine(vec2(0, BD.TOPBAR_H-1), vec2(BD.SW-1, BD.TOPBAR_H-1), _theme.dim)

    -- Logo (24x12) vertically centered in 12px topbar
    local logoX = 2
    local logoY = math.floor((BD.TOPBAR_H - LOGO_H) / 2)
    if _sprLogo then
        -- DrawCustomSprite: draws the full image ignoring the sprite grid
        _video:DrawCustomSprite(
            vec2(logoX, logoY),
            _sprLogo,
            vec2(0, 0),           -- offset within sprite
            vec2(LOGO_W, LOGO_H), -- draw size
            color.white,
            color.clear)
        logoX = logoX + LOGO_W + 3
    else
        -- Fallback: text if no sprite
        tprint(_video, logoX, 3, "IARG-OS", _theme.tbtext)
        logoX = logoX + 8 * BD.CHAR_W
    end

    -- Current directory centered
    if cwd and cwd ~= "" and cwd ~= "root" then
        local dirStr = "~/"..cwd
        local dx = math.floor((BD.SW - #dirStr * BD.CHAR_W) / 2)
        tprint(_video, dx, 3, dirStr, _theme.dim)
    end

    -- Clock -- right side
    local timeStr = self:GetTimeStr()
    local timeW   = #timeStr * BD.CHAR_W
    -- Space for clock icon (9px) + gap (2px) + text
    local totalW  = ICO_W + 2 + timeW
    local startX  = BD.SW - totalW - 3
    local iconY   = math.floor((BD.TOPBAR_H - ICO_H) / 2)

    if _sprSys then
        -- Clock icon: sx=0, sy=0
        _video:DrawCustomSprite(
            vec2(startX, iconY),
            _sprSys,
            vec2(0, 0),          -- offset in sheet: col 0, row 0
            vec2(ICO_W, ICO_H),
            _theme.tbclock,
            color.clear)
    end

    tprint(_video, startX + ICO_W + 2, 3, timeStr, _theme.tbclock)
end

---------------------------------------------------------------------------

return Topbar