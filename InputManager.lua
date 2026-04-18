---------------------------------------------------------------------------
-- InputManager.lua — Touch y teclado físico
-- Usa global: BD. NO hace require de nada.
---------------------------------------------------------------------------

InputManager = {}

local _video       = nil
local zones        = {}
local touchDownTick = 0
local holdFired    = false
local dragActive   = false
local dragStartPos = vec2(0,0)
local lastTapTick  = 0
local lastTapZoneId = ""
local currentTick  = 0
local keyBuffer    = {}

---------------------------------------------------------------------------

function InputManager:Init(videoChip)
    _video      = videoChip
    currentTick = 0
end

function InputManager:ClearZones()
    zones = {}
end

function InputManager:Register(id, x, y, w, h, callbacks)
    table.insert(zones, {id=id, x=x, y=y, w=w, h=h, cb=callbacks or {}})
end

---------------------------------------------------------------------------
-- Helpers

local function inZone(px, py, z)
    return px >= z.x and px < z.x+z.w and py >= z.y and py < z.y+z.h
end

local function hitTest(px, py)
    for i = #zones, 1, -1 do
        if inZone(px, py, zones[i]) then return zones[i] end
    end
    return nil
end

local function fire(z, cb, pos)
    if z and z.cb and z.cb[cb] then z.cb[cb](z.id, pos); return true end
    return false
end

---------------------------------------------------------------------------

function InputManager:Poll()
    currentTick = currentTick + 1
    local td = _video.TouchDown
    local tu = _video.TouchUp
    local ts = _video.TouchState
    local tp = _video.TouchPosition

    if td then
        touchDownTick = currentTick
        holdFired     = false
        dragActive    = false
        dragStartPos  = tp
    end

    if ts then
        local held = currentTick - touchDownTick
        if held >= BD.HOLD_TICKS and not holdFired then
            holdFired = true
            fire(hitTest(tp.x, tp.y), "onHold", tp)
        end
        if not holdFired and not dragActive then
            local dx = tp.x - dragStartPos.x
            local dy = tp.y - dragStartPos.y
            if math.sqrt(dx*dx + dy*dy) >= BD.DRAG_MIN_PX then
                dragActive = true
                fire(hitTest(dragStartPos.x, dragStartPos.y), "onDragStart", dragStartPos)
            end
        end
        if dragActive then
            fire(hitTest(dragStartPos.x, dragStartPos.y), "onDrag", tp)
        end
    end

    if tu then
        if dragActive then
            fire(hitTest(tp.x, tp.y), "onDrop", tp)
            dragActive = false
        elseif not holdFired then
            local held = currentTick - touchDownTick
            if held <= BD.TAP_MAX_TICKS then
                local z = hitTest(tp.x, tp.y)
                if z then
                    local dt = currentTick - lastTapTick
                    if dt <= BD.DOUBLE_TAP_TICKS and z.id == lastTapZoneId then
                        fire(z, "onDoubleTap", tp)
                        lastTapTick = 0; lastTapZoneId = ""
                    else
                        fire(z, "onTap", tp)
                        lastTapTick = currentTick; lastTapZoneId = z.id
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Teclado físico

function InputManager:PushKey(inputName)
    table.insert(keyBuffer, inputName)
end

function InputManager:PopKey()
    if #keyBuffer == 0 then return nil end
    return table.remove(keyBuffer, 1)
end

function InputManager:GetTick() return currentTick end
function InputManager:IsDragging() return dragActive end

---------------------------------------------------------------------------
-- Mapeo InputName  char

function InputManager:KeyNameToChar(name)
    if name == "Backspace" or name == "Delete" then return "DEL" end
    if name == "Return" or name == "KeypadEnter" then return "ENTER" end
    if name == "Space"       then return " " end
    if name == "LeftArrow"   then return "LEFT" end
    if name == "RightArrow"  then return "RIGHT" end
    if name == "UpArrow"     then return "UP" end
    if name == "DownArrow"   then return "DOWN" end
    if name == "Escape"      then return "ESC" end

    local letters = {A="a",B="b",C="c",D="d",E="e",F="f",G="g",H="h",
        I="i",J="j",K="k",L="l",M="m",N="n",O="o",P="p",Q="q",R="r",
        S="s",T="t",U="u",V="v",W="w",X="x",Y="y",Z="z"}
    if letters[name] then return letters[name] end

    local nums = {Alpha0="0",Alpha1="1",Alpha2="2",Alpha3="3",Alpha4="4",
        Alpha5="5",Alpha6="6",Alpha7="7",Alpha8="8",Alpha9="9",
        Keypad0="0",Keypad1="1",Keypad2="2",Keypad3="3",Keypad4="4",
        Keypad5="5",Keypad6="6",Keypad7="7",Keypad8="8",Keypad9="9"}
    if nums[name] then return nums[name] end

    local syms = {Period=".",Comma=",",Minus="-",Plus="+",Slash="/",
        Backslash="\\",Semicolon=";",Quote="'",Underscore="_",At="@",
        Exclaim="!",Question="?",Hash="#",Dollar="$"}
    if syms[name] then return syms[name] end

    return nil
end

return InputManager