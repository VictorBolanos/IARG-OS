---------------------------------------------------------------------------
-- VirtualKeyboard.lua — Teclado QWERTY táctil
-- Usa globales: BD, Theme, Renderer, InputManager. NO hace require.
---------------------------------------------------------------------------

VirtualKeyboard = {}

local KB_Y  = 164
local KB_H  = 60
local KEY_H = 12
local GAP   = 1

local SPEC_W = {DEL=22,ENTER=28,SHIFT=26,SPACE=56,["123"]=22,ABC=22,LEFT=18,RIGHT=18,OK=28}
local STD_W  = 22

local ROWS_LETTERS = {
    {"Q","W","E","R","T","Y","U","I","O","P","DEL"},
    {"A","S","D","F","G","H","J","K","L","ENTER"},
    {"Z","X","C","V","B","N","M","SHIFT","SPACE"},
    {"123","LEFT","RIGHT","OK"},
}
local ROWS_NUMBERS = {
    {"1","2","3","4","5","6","7","8","9","0","DEL"},
    {"-","_","(",")","/","\\","@",".",",","ENTER"},
    {"!","?","#","$","%","&","'","SPACE"},
    {"ABC","LEFT","RIGHT","OK"},
}

local active     = false
local shiftOn    = false
local numMode    = false
local callback   = nil
local pressedKey = nil
local pressTick  = 0

local function kw(lbl) return SPEC_W[lbl] or STD_W end

local function rowX(row)
    local total = 0
    for i, lbl in ipairs(row) do
        total = total + kw(lbl)
        if i < #row then total = total + GAP end
    end
    return math.floor((BD.SW - total) / 2)
end

---------------------------------------------------------------------------

function VirtualKeyboard:Show(cb)
    active=true; callback=cb; shiftOn=false; numMode=false; pressedKey=nil
end

function VirtualKeyboard:Hide()
    active=false; callback=nil
end

function VirtualKeyboard:IsActive() return active end

function VirtualKeyboard:RegisterZones()
    if not active then return end
    local rows = numMode and ROWS_NUMBERS or ROWS_LETTERS
    local curY = KB_Y + 2
    for _, row in ipairs(rows) do
        local curX = rowX(row)
        for _, lbl in ipairs(row) do
            local w = kw(lbl)
            InputManager:Register("kb_"..lbl, curX, curY, w, KEY_H, {
                onTap = function()
                    pressedKey = lbl
                    pressTick  = InputManager:GetTick()
                    self:HandleKey(lbl)
                end
            })
            curX = curX + w + GAP
        end
        curY = curY + KEY_H + GAP
    end
end

function VirtualKeyboard:HandleKey(lbl)
    if lbl == "DEL"   then if callback then callback("DEL")   end; return end
    if lbl == "ENTER" then if callback then callback("ENTER") end; return end
    if lbl == "LEFT"  then if callback then callback("LEFT")  end; return end
    if lbl == "RIGHT" then if callback then callback("RIGHT") end; return end
    if lbl == "OK"    then if callback then callback("OK") end; self:Hide(); return end
    if lbl == "SHIFT" then shiftOn = not shiftOn; return end
    if lbl == "123"   then numMode=true;  shiftOn=false; return end
    if lbl == "ABC"   then numMode=false; shiftOn=false; return end
    if lbl == "SPACE" then if callback then callback(" ") end; return end

    local ch = lbl
    if not numMode then
        ch = shiftOn and lbl:upper() or lbl:lower()
        if shiftOn then shiftOn=false end
    end
    if callback then callback(ch) end
end

function VirtualKeyboard:Draw()
    if not active then return end
    local rows = numMode and ROWS_NUMBERS or ROWS_LETTERS
    local tick = InputManager:GetTick()

    Renderer:FillRect(0, KB_Y, BD.SW, KB_H+2, Theme.C.bg_panel)
    Renderer:DrawLine(0, KB_Y, BD.SW-1, KB_Y, Theme.C.border)

    local curY = KB_Y + 2
    for _, row in ipairs(rows) do
        local curX = rowX(row)
        for _, lbl in ipairs(row) do
            local w = kw(lbl)
            local pressed = (lbl == pressedKey and (tick - pressTick) < 10)
            local isActive = (lbl=="SHIFT" and shiftOn) or
                             (lbl=="123" and numMode) or
                             (lbl=="ABC" and not numMode)
            local bg = (pressed or isActive) and Theme.C.btn_pressed or Theme.C.btn_bg
            local fg = (pressed or isActive) and Theme.C.btn_text_press or Theme.C.text_primary

            Renderer:FillRect(curX, curY, w, KEY_H, bg)
            Renderer:DrawRect(curX, curY, w, KEY_H, Theme.C.border)

            local disp = lbl
            if not numMode and #lbl == 1 then
                disp = shiftOn and lbl:upper() or lbl:lower()
            end
            local maxCh = math.floor((w-2) / BD.CHAR_W)
            if #disp > maxCh then disp = disp:sub(1, maxCh) end
            local tw = #disp * BD.CHAR_W
            local tx = curX + math.floor((w - tw) / 2)
            local ty = curY + math.floor((KEY_H - BD.CHAR_H) / 2)
            Renderer:DrawText(tx, ty, disp, fg)

            curX = curX + w + GAP
        end
        curY = curY + KEY_H + GAP
    end
end

return VirtualKeyboard