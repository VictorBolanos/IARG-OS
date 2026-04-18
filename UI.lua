---------------------------------------------------------------------------
-- UI.lua — Topbar, Taskbar y Popup modal
-- Usa globales: BD, Theme, Renderer, InputManager. NO hace require.
---------------------------------------------------------------------------

UI = {}

local _dirty   = false
local _appTitle = ""
local _path    = ""
local _icons   = nil
local _onBack  = nil
local _onHome  = nil

local popup = {active=false, title="", message="", buttons={}, cb=nil}

function UI:Init(iconSheet)
    _icons = iconSheet
end

function UI:SetDirty(d)      _dirty    = d        end
function UI:SetAppTitle(t)   _appTitle = t or ""  end
function UI:SetPath(p)       _path     = p or ""  end
function UI:IsPopupActive()  return popup.active   end

function UI:SetTaskbarCallbacks(back, home)
    _onBack = back; _onHome = home
end

---------------------------------------------------------------------------
-- TOPBAR

function UI:DrawTopbar()
    Renderer:FillRect(0, 0, BD.SW, BD.TOPBAR_H, Theme.C.bg_panel)
    Renderer:DrawLine(0, BD.TOPBAR_H-1, BD.SW-1, BD.TOPBAR_H-1, Theme.C.border)
    Renderer:DrawText(3, 3, "IARG-OS", Theme.C.text_accent)

    local label = ""
    if _appTitle ~= "" then label = "> " .. _appTitle
    elseif _path ~= "" and _path ~= "root" then label = "> " .. _path end
    if #label > 0 then
        local tx = math.floor((BD.SW - Renderer:TextWidth(label)) / 2)
        Renderer:DrawText(tx, 3, label, Theme.C.text_secondary)
    end

    if _dirty then
        Renderer:DrawText(BD.SW - 4*BD.CHAR_W - 2, 3, "[*]", Theme.C.text_warning)
    end
end

function UI:RegisterTopbarZones() end

---------------------------------------------------------------------------
-- TASKBAR

function UI:DrawTaskbar()
    Renderer:FillRect(0, BD.TASKBAR_Y, BD.SW, BD.TASKBAR_H, Theme.C.bg_panel)
    Renderer:DrawLine(0, BD.TASKBAR_Y, BD.SW-1, BD.TASKBAR_Y, Theme.C.border)
    Renderer:DrawText(3,  BD.TASKBAR_Y+3, "< Atras", Theme.C.text_secondary)
    Renderer:DrawLine(54, BD.TASKBAR_Y+2, 54, BD.TASKBAR_Y+9, Theme.C.border)
    Renderer:DrawText(57, BD.TASKBAR_Y+3, "Home", Theme.C.text_secondary)
    Renderer:DrawLine(90, BD.TASKBAR_Y+2, 90, BD.TASKBAR_Y+9, Theme.C.border)

    local lbl = _appTitle ~= "" and _appTitle or "Escritorio"
    local tx  = math.floor((BD.SW - Renderer:TextWidth(lbl)) / 2)
    Renderer:DrawText(tx, BD.TASKBAR_Y+3, lbl, Theme.C.text_primary)
end

function UI:RegisterTaskbarZones()
    InputManager:Register("tb_back", 0, BD.TASKBAR_Y, 54, BD.TASKBAR_H, {
        onTap = function() if _onBack then _onBack() end end
    })
    InputManager:Register("tb_home", 54, BD.TASKBAR_Y, 36, BD.TASKBAR_H, {
        onTap = function() if _onHome then _onHome() end end
    })
end

---------------------------------------------------------------------------
-- POPUP

function UI:ShowPopup(title, msg, buttons, cb)
    popup.active  = true
    popup.title   = title   or ""
    popup.message = msg     or ""
    popup.buttons = buttons or {"OK"}
    popup.cb      = cb
end

function UI:ClosePopup()
    popup.active = false
end

function UI:DrawPopup()
    if not popup.active then return end
    Renderer:DrawPopup(popup.title, popup.message, popup.buttons)
end

function UI:RegisterPopupZones()
    if not popup.active then return end
    local x = BD.POPUP_X; local y = BD.POPUP_Y
    local w = BD.POPUP_W; local h = BD.POPUP_H
    local bw = 50; local bh = 13
    local total  = #popup.buttons * bw + (#popup.buttons-1) * 5
    local startX = x + math.floor((w - total) / 2)
    local by     = y + h - bh - 6

    InputManager:Register("popup_bg", x, y, w, h, {onTap=function() end})

    for i = 1, #popup.buttons do
        local bx   = startX + (i-1) * (bw+5)
        local idx  = i
        InputManager:Register("popup_btn_"..i, bx, by, bw, bh, {
            onTap = function()
                popup.active = false
                if popup.cb then popup.cb(idx) end
            end
        })
    end
end

return UI