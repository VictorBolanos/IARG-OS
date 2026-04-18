---------------------------------------------------------------------------
-- Renderer.lua — Wrapper del VideoChip
-- Usa globales: BD, Theme. NO hace require de nada.
-- Integra Tprint (tu función probada) para TODO el texto.
---------------------------------------------------------------------------

Renderer    = {}
local _video = nil
local _font  = nil

---------------------------------------------------------------------------
-- Init

function Renderer:Init(videoChip, fontSheet)
    _video = videoChip
    _font  = fontSheet
end

---------------------------------------------------------------------------
-- Tprint — función de texto probada (tuya, integrada aquí)

local function Tprint(pos, txt, textColor, maxWidth)
    if not _font then return end
    textColor = textColor or color.white
    maxWidth  = maxWidth  or 60

    local function wordWrap(text, maxCols)
        local lines = {}
        local cur   = ""
        for para in text:gmatch("[^\n]+") do
            local words = {}
            for w in para:gmatch("%S+") do table.insert(words, w) end
            for _, w in ipairs(words) do
                local test = (#cur > 0) and (cur .. " " .. w) or w
                if #test > maxCols then
                    if #cur > 0 then table.insert(lines, cur); cur = w
                    else table.insert(lines, w); cur = "" end
                else cur = test end
            end
            if #cur > 0 then table.insert(lines, cur); cur = "" end
        end
        return table.concat(lines, "\n")
    end

    txt = wordWrap(tostring(txt), maxWidth)

    local line, col = 0, 0
    for i = 1, #txt do
        local c = txt:sub(i,i)
        if c == "\n" then
            line = line + 1; col = 0
        else
            _video:DrawSprite(
                pos + vec2(BD.CHAR_W * col, BD.CHAR_H * line),
                _font,
                c:byte() % 32,
                math.floor(c:byte() / 32),
                textColor,
                color.clear)
            col = col + 1
        end
    end
end

---------------------------------------------------------------------------
-- Primitivas

function Renderer:Clear(c)
    _video:Clear(c or Theme.C.bg_desktop)
end

function Renderer:SetPixel(x, y, c)
    _video:SetPixel(vec2(x, y), c)
end

function Renderer:FillRect(x, y, w, h, c)
    _video:FillRect(vec2(x, y), vec2(x+w-1, y+h-1), c)
end

function Renderer:DrawRect(x, y, w, h, c)
    _video:DrawRect(vec2(x, y), vec2(x+w-1, y+h-1), c)
end

function Renderer:DrawLine(x1, y1, x2, y2, c)
    _video:DrawLine(vec2(x1,y1), vec2(x2,y2), c)
end

function Renderer:FillCircle(x, y, r, c)
    _video:FillCircle(vec2(x,y), r, c)
end

function Renderer:DrawSprite(x, y, sheet, sx, sy, tint, bg)
    _video:DrawSprite(vec2(x,y), sheet, sx, sy,
        tint or color.white, bg or color.clear)
end

function Renderer:GetVideo() return _video end
function Renderer:GetFont()  return _font  end

---------------------------------------------------------------------------
-- Texto

function Renderer:DrawText(x, y, txt, c, maxW)
    Tprint(vec2(x, y), txt, c or Theme.C.text_primary, maxW or 60)
end

function Renderer:DrawTextCentered(cx, y, txt, c)
    local t = tostring(txt)
    local w = #t * BD.CHAR_W
    Tprint(vec2(cx - math.floor(w/2), y), t, c or Theme.C.text_primary, 80)
end

function Renderer:DrawTextTrunc(x, y, txt, maxChars, c)
    local t = tostring(txt)
    if #t > maxChars then t = t:sub(1, maxChars-2) .. ".." end
    Tprint(vec2(x, y), t, c or Theme.C.text_primary, 80)
end

function Renderer:TextWidth(txt)
    return #tostring(txt) * BD.CHAR_W
end

---------------------------------------------------------------------------
-- Componentes UI

function Renderer:DrawPanel(x, y, w, h, bg, border)
    self:FillRect(x, y, w, h, bg or Theme.C.bg_window)
    self:DrawRect(x, y, w, h, border or Theme.C.border)
end

function Renderer:DrawButton(x, y, w, h, label, state)
    local bg, fg
    if state == "pressed" then
        bg = Theme.C.btn_pressed; fg = Theme.C.btn_text_press
    elseif state == "disabled" then
        bg = Theme.C.bg_panel;    fg = Theme.C.text_secondary
    elseif state == "hover" then
        bg = Theme.C.btn_hover;   fg = Theme.C.btn_text
    else
        bg = Theme.C.btn_bg;      fg = Theme.C.btn_text
    end
    self:FillRect(x, y, w, h, bg)
    self:DrawRect(x, y, w, h, Theme.C.border)
    local lbl = tostring(label)
    local tx  = x + math.floor((w - #lbl * BD.CHAR_W) / 2)
    local ty  = y + math.floor((h - BD.CHAR_H) / 2)
    Tprint(vec2(tx, ty), lbl, fg, 40)
end

function Renderer:DrawProgressBar(x, y, w, h, progress, fg, bg)
    self:FillRect(x, y, w, h, bg or Theme.C.bg_panel)
    self:DrawRect(x, y, w, h, Theme.C.border)
    local fw = math.floor((w-2) * math.max(0, math.min(1, progress)))
    if fw > 0 then
        self:FillRect(x+1, y+1, fw, h-2, fg or Theme.C.accent)
    end
end

function Renderer:DrawSeparator(x, y, w)
    self:DrawLine(x, y, x+w-1, y, Theme.C.border)
end

function Renderer:DrawListItem(x, y, w, h, label, selected, labelColor)
    if selected then self:FillRect(x, y, w, h, Theme.C.bg_selection) end
    local maxCh = math.floor((w - 8) / BD.CHAR_W)
    self:DrawTextTrunc(x+4, y + math.floor((h - BD.CHAR_H) / 2),
        label, maxCh, labelColor or Theme.C.text_primary)
    self:DrawLine(x, y+h-1, x+w-1, y+h-1, Theme.C.border)
end

function Renderer:DrawPopup(title, message, buttons)
    local x = BD.POPUP_X
    local y = BD.POPUP_Y
    local w = BD.POPUP_W
    local h = BD.POPUP_H

    -- Overlay
    _video:FillRect(vec2(0,0), vec2(BD.SW-1, BD.SH-1), ColorRGBA(0,0,0,140))

    -- Cuerpo
    self:FillRect(x, y, w, h, Theme.C.bg_window)
    self:DrawRect(x, y, w, h, Theme.C.border_focus)

    -- Header
    self:FillRect(x, y, w, 14, Theme.C.bg_panel)
    Tprint(vec2(x+4, y+4), title, Theme.C.text_accent, 30)
    self:DrawLine(x, y+13, x+w-1, y+13, Theme.C.border)

    -- Mensaje
    Tprint(vec2(x+6, y+20), message, Theme.C.text_primary,
        math.floor((w-12) / BD.CHAR_W))

    -- Botones
    if buttons and #buttons > 0 then
        local bw     = 50
        local bh     = 13
        local total  = #buttons * bw + (#buttons-1) * 5
        local startX = x + math.floor((w - total) / 2)
        local by     = y + h - bh - 6
        for i, lbl in ipairs(buttons) do
            local bx = startX + (i-1) * (bw+5)
            self:DrawButton(bx, by, bw, bh, lbl, "normal")
        end
    end
end

---------------------------------------------------------------------------

return Renderer