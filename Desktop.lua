---------------------------------------------------------------------------
-- Desktop.lua — Escritorio del OS
-- Usa globales: BD, Theme, Renderer, InputManager, VFS, UI, VirtualKeyboard
-- NO hace require de nada.
---------------------------------------------------------------------------

Desktop = {}

local _currentFolder = nil
local _folderStack   = {}
local _selected      = nil
local _icons         = nil
local _onLaunch      = nil

-- Drag
local _dragging = nil
local _dragOffX = 0; local _dragOffY = 0
local _dragCurX = 0; local _dragCurY = 0

-- Menú contextual
local ctx = {active=false, node=nil, x=0, y=0, opts={}}

-- Input de nombre
local ni = {active=false, mode="", target=nil, text="", cursor=0}

---------------------------------------------------------------------------

function Desktop:Init(iconSheet, launchCb)
    _icons   = iconSheet
    _onLaunch = launchCb
    _currentFolder = VFS:GetRoot()
    _folderStack   = {}
    _selected      = nil
    ctx.active     = false
    ni.active      = false
    self:_updateUI()
end

function Desktop:_updateUI()
    local path = VFS:GetPath(_currentFolder)
    UI:SetPath(path == "root" and "" or (path:match("([^/]+)$") or path))
    UI:SetAppTitle("")
end

---------------------------------------------------------------------------
-- Navegación

function Desktop:NavigateInto(folder)
    table.insert(_folderStack, _currentFolder)
    _currentFolder = folder; _selected = nil
    self:_updateUI()
end

function Desktop:NavigateBack()
    if #_folderStack == 0 then return end
    _currentFolder = table.remove(_folderStack); _selected = nil
    self:_updateUI()
end

function Desktop:CanGoBack() return #_folderStack > 0 end

---------------------------------------------------------------------------
-- Hit zone de icono

local function iconRect(node)
    return node.posX, node.posY + BD.CONTENT_Y, BD.ICON_CELL_W, BD.ICON_CELL_H
end

---------------------------------------------------------------------------

function Desktop:RegisterZones()
    -- Fondo
    InputManager:Register("dt_bg", 0, BD.CONTENT_Y, BD.SW, BD.CONTENT_H, {
        onTap  = function() _selected=nil; ctx.active=false end,
        onHold = function(_, pos)
            if not _selected then self:_beginNameInput("new_folder", nil) end
        end,
    })

    for _, node in ipairs(VFS:GetChildren(_currentFolder)) do
        local ix,iy,iw,ih = iconRect(node)
        InputManager:Register("ic_"..node.id, ix, iy, iw, ih, {
            onTap       = function() _selected=node; ctx.active=false end,
            onDoubleTap = function() self:_openNode(node) end,
            onHold      = function(_,pos) _selected=node; self:_showCtx(node,pos.x,pos.y) end,
            onDragStart = function(_,pos)
                _dragging=node
                _dragOffX=pos.x-node.posX; _dragOffY=pos.y-(node.posY+BD.CONTENT_Y)
                _dragCurX=node.posX; _dragCurY=node.posY
            end,
            onDrag = function(_,pos)
                if _dragging and _dragging.id==node.id then
                    _dragCurX=pos.x-_dragOffX; _dragCurY=pos.y-BD.CONTENT_Y-_dragOffY
                end
            end,
            onDrop = function(_,pos)
                if _dragging and _dragging.id==node.id then
                    local tgt = self:_findDropFolder(pos.x, pos.y, node)
                    if tgt then VFS:Move(node, tgt)
                    else
                        node.posX = math.max(0, math.min(BD.SW-BD.ICON_CELL_W, _dragCurX))
                        node.posY = math.max(0, math.min(BD.CONTENT_H-BD.ICON_CELL_H, _dragCurY))
                    end
                    _dragging=nil; UI:SetDirty(true)
                end
            end,
        })
    end

    if ctx.active then self:_registerCtxZones() end
    if ni.active  then VirtualKeyboard:RegisterZones() end
end

function Desktop:_openNode(node)
    if node.type == BD.NT_FOLDER then self:NavigateInto(node)
    elseif node.type == BD.NT_APP then
        if _onLaunch then _onLaunch(node) end
    elseif node.type == BD.NT_TXT then
        if _onLaunch then _onLaunch({name="TextPad", type=BD.NT_APP, targetFile=node}) end
    elseif node.type == BD.NT_IMG then
        if _onLaunch then _onLaunch({name="PixelPaint", type=BD.NT_APP, targetFile=node}) end
    end
end

function Desktop:_findDropFolder(px, py, exclude)
    for _, n in ipairs(VFS:GetChildren(_currentFolder)) do
        if n ~= exclude and n.type == BD.NT_FOLDER then
            local ix,iy,iw,ih = iconRect(n)
            if px>=ix and px<ix+iw and py>=iy and py<iy+ih then return n end
        end
    end
    return nil
end

function Desktop:_showCtx(node, mx, my)
    ctx.active = true; ctx.node = node
    ctx.x = math.min(mx, BD.SW-92)
    ctx.y = math.min(my, BD.TASKBAR_Y-56)
    ctx.opts = (node.type==BD.NT_APP) and {"Abrir","Renombrar"} or {"Abrir","Renombrar","Eliminar"}
end

function Desktop:_registerCtxZones()
    InputManager:Register("ctx_bg", 0, BD.CONTENT_Y, BD.SW, BD.CONTENT_H, {
        onTap = function() ctx.active=false end
    })
    for i, opt in ipairs(ctx.opts) do
        local iy  = ctx.y + 14 + (i-1)*14
        local opt2 = opt
        InputManager:Register("ctx_"..i, ctx.x, iy, 88, 14, {
            onTap = function()
                self:_handleCtxOpt(opt2, ctx.node); ctx.active=false
            end
        })
    end
end

function Desktop:_handleCtxOpt(opt, node)
    if opt == "Abrir" then self:_openNode(node)
    elseif opt == "Renombrar" then self:_beginNameInput("rename", node)
    elseif opt == "Eliminar" then
        UI:ShowPopup("Eliminar", "Borrar "..node.name.."?", {"Si","No"}, function(idx)
            if idx==1 then
                if _selected and _selected.id==node.id then _selected=nil end
                VFS:Delete(node); UI:SetDirty(true)
            end
        end)
    end
end

function Desktop:_beginNameInput(mode, target)
    ni.active = true; ni.mode = mode; ni.target = target
    ni.text   = (mode=="rename" and target) and target.name or ""
    ni.cursor = #ni.text
    VirtualKeyboard:Show(function(ch) self:_handleNameKey(ch) end)
end

function Desktop:_handleNameKey(ch)
    if ch=="DEL" then
        if ni.cursor>0 then
            ni.text=ni.text:sub(1,ni.cursor-1)..ni.text:sub(ni.cursor+1); ni.cursor=ni.cursor-1
        end
    elseif ch=="LEFT"  then ni.cursor=math.max(0,ni.cursor-1)
    elseif ch=="RIGHT" then ni.cursor=math.min(#ni.text,ni.cursor+1)
    elseif ch=="ENTER" or ch=="OK" then self:_commitName()
    else
        if #ni.text < 20 then
            ni.text=ni.text:sub(1,ni.cursor)..ch..ni.text:sub(ni.cursor+1); ni.cursor=ni.cursor+1
        end
    end
end

function Desktop:_commitName()
    local name = ni.text:match("^%s*(.-)%s*$")
    if name and #name > 0 then
        if ni.mode == "new_folder" then
            local n = VFS:CreateFolder(_currentFolder, name)
            if n then
                local ch = VFS:GetChildren(_currentFolder)
                local idx = #ch - 1
                n.posX = 16 + (idx%6)*(BD.ICON_CELL_W+8)
                n.posY = 20 + math.floor(idx/6)*(BD.ICON_CELL_H+8)
                UI:SetDirty(true)
            end
        elseif ni.mode == "rename" and ni.target then
            VFS:Rename(ni.target, name); UI:SetDirty(true)
        end
    end
    ni.active=false; VirtualKeyboard:Hide()
end

---------------------------------------------------------------------------

function Desktop:Update()
    self:_updateUI()
end

function Desktop:Draw()
    Renderer:FillRect(0, BD.CONTENT_Y, BD.SW, BD.CONTENT_H, Theme.C.bg_desktop)

    -- Patrón de puntos
    local dot = Color(26, 26, 44)
    for dy = BD.CONTENT_Y, BD.TASKBAR_Y-1, 16 do
        for dx = 0, BD.SW-1, 16 do
            Renderer:SetPixel(dx, dy, dot)
        end
    end

    -- Iconos
    for _, node in ipairs(VFS:GetChildren(_currentFolder)) do
        if not (_dragging and _dragging.id == node.id) then
            self:_drawIcon(node, node.posX, node.posY + BD.CONTENT_Y, node == _selected)
        end
    end

    -- Icono arrastrado
    if _dragging then
        self:_drawIcon(_dragging, _dragCurX, _dragCurY + BD.CONTENT_Y, true)
        local tgt = self:_findDropFolder(
            _dragCurX + math.floor(BD.ICON_CELL_W/2),
            _dragCurY + BD.CONTENT_Y + math.floor(BD.ICON_CELL_H/2),
            _dragging)
        if tgt then
            local tx,ty,tw,th = iconRect(tgt)
            Renderer:DrawRect(tx-1, ty-1, tw+2, th+2, Theme.C.accent)
        end
    end

    if ctx.active then self:_drawCtx() end
    if ni.active  then self:_drawNameInput() end
end

function Desktop:_drawIcon(node, px, py, sel)
    if sel then
        Renderer:FillRect(px, py, BD.ICON_CELL_W, BD.ICON_CELL_H, Theme.C.bg_selection)
        Renderer:DrawRect(px, py, BD.ICON_CELL_W, BD.ICON_CELL_H, Theme.C.border_focus)
    end
    local ico = VFS:GetIcon(node)
    local sx  = px + math.floor((BD.ICON_CELL_W - BD.ICON_SPR) / 2)
    local sy  = py + BD.ICON_PAD_Y
    if _icons then
        Renderer:DrawSprite(sx, sy, _icons, ico.sx, ico.sy)
    else
        local c = Theme.C.accent
        if node.type == BD.NT_FOLDER then c = Theme.C.text_warning
        elseif node.type == BD.NT_TXT then c = Theme.C.text_success end
        Renderer:FillRect(sx, sy, BD.ICON_SPR, BD.ICON_SPR, c)
    end
    local maxCh = math.floor(BD.ICON_CELL_W / BD.CHAR_W)
    local lbl   = node.name
    if #lbl > maxCh then lbl = lbl:sub(1,maxCh-1).."." end
    local tw = #lbl * BD.CHAR_W
    Renderer:DrawText(px + math.floor((BD.ICON_CELL_W-tw)/2),
        py + BD.ICON_LABEL_Y, lbl,
        sel and Theme.C.text_accent or Theme.C.text_primary)
end

function Desktop:_drawCtx()
    local mx=ctx.x; local my=ctx.y; local mw=88
    local mh = 14 + #ctx.opts*14 + 4
    Renderer:FillRect(mx, my, mw, mh, Theme.C.bg_window)
    Renderer:DrawRect(mx, my, mw, mh, Theme.C.border_focus)
    Renderer:FillRect(mx, my, mw, 14, Theme.C.bg_panel)
    Renderer:DrawTextTrunc(mx+4, my+4, ctx.node and ctx.node.name or "",
        math.floor((mw-8)/BD.CHAR_W), Theme.C.text_accent)
    for i, opt in ipairs(ctx.opts) do
        Renderer:DrawListItem(mx, my+14+(i-1)*14, mw, 14, opt, false)
    end
end

function Desktop:_drawNameInput()
    local by = 164 - 22
    Renderer:FillRect(0, by, BD.SW, 22, Theme.C.bg_window)
    Renderer:DrawLine(0, by, BD.SW-1, by, Theme.C.border_focus)
    local prompt = ni.mode=="new_folder" and "Nueva carpeta: " or "Renombrar: "
    local inputX = 4 + #prompt * BD.CHAR_W
    Renderer:DrawText(4, by+7, prompt, Theme.C.text_secondary)
    local disp = ni.text:sub(1,ni.cursor).."|"..ni.text:sub(ni.cursor+1)
    Renderer:DrawText(inputX, by+7, disp, Theme.C.text_primary)
end

return Desktop