---------------------------------------------------------------------------
-- PixelPaint.lua — Editor pixel art
-- Usa globales: BD, Theme, Renderer, InputManager, VFS, UI, SaveSystem, OSConfig
-- NO hace require de nada.
---------------------------------------------------------------------------

PixelPaint = {}

-- Constantes de layout — se inicializan en Init() cuando BD ya existe
local HDR_Y, HDR_H, PAN_W, CX, CY, CW, CH, ZM, CPW, CPH
local TOOLS_LY, TOOLS_Y, PAL_LY, PAL_Y, BRUSH_LY, BRUSH_Y, CURCOL_Y

local canvas     = {}
local cDirty     = true
local tool       = "pen"
local colorIdx   = 1
local brushSz    = 1
local curNode    = nil
local dirty      = false
local onClose    = nil
local painting   = false
local lastPX     = -1; local lastPY = -1
local _video     = nil

---------------------------------------------------------------------------

function PixelPaint:Init(closeCb, videoChip, targetFile)
    -- Inicializar constantes de layout (BD ya existe en este punto)
    HDR_Y    = BD.CONTENT_Y;  HDR_H   = 16
    PAN_W    = BD.PP_PANEL_W
    CX       = BD.PP_CANVAS_X; CY     = BD.PP_CANVAS_Y
    CW       = BD.PP_CANVAS_W; CH     = BD.PP_CANVAS_H
    ZM       = BD.PP_ZOOM
    CPW      = CW * ZM;        CPH    = CH * ZM
    TOOLS_LY = BD.CONTENT_Y + HDR_H + 2
    TOOLS_Y  = TOOLS_LY + 9
    PAL_LY   = TOOLS_Y + 44;  PAL_Y  = PAL_LY + 9
    BRUSH_LY = PAL_Y + 72;    BRUSH_Y= BRUSH_LY + 9
    CURCOL_Y = BRUSH_Y + 22
    onClose=closeCb; _video=videoChip; dirty=false
    self:_newCanvas()
    if targetFile and targetFile.data then
        self:_deserialize(targetFile.data); curNode=targetFile
    else curNode=nil end
    if _video then _video:SetRenderBufferSize(0, CPW, CPH) end
    cDirty=true
    UI:SetAppTitle("PixelPaint")
    UI:SetTaskbarCallbacks(
        function() self:_handleBack() end,
        function() if onClose then onClose() end end)
end

function PixelPaint:_newCanvas()
    canvas={}; for i=1,CW*CH do canvas[i]=0 end; cDirty=true; dirty=false
end

function PixelPaint:_setPixel(cx,cy,ci)
    if cx<1 or cx>CW or cy<1 or cy>CH then return end
    local idx=(cy-1)*CW+cx
    if canvas[idx]~=ci then canvas[idx]=ci; cDirty=true; dirty=true; UI:SetDirty(true) end
end

function PixelPaint:_paint(cx,cy)
    local ci = tool=="eraser" and 0 or colorIdx
    if brushSz==1 then self:_setPixel(cx,cy,ci)
    elseif brushSz==2 then
        self:_setPixel(cx,cy,ci); self:_setPixel(cx+1,cy,ci)
        self:_setPixel(cx,cy+1,ci); self:_setPixel(cx+1,cy+1,ci)
    else
        for dy=-1,1 do for dx=-1,1 do self:_setPixel(cx+dx,cy+dy,ci) end end
    end
end

function PixelPaint:_scToCanvas(sx,sy)
    return math.floor((sx-CX)/ZM)+1, math.floor((sy-CY)/ZM)+1
end

function PixelPaint:_serialize()
    local parts={}; local rLen=1; local rC=canvas[1] or 0
    for i=2,#canvas do
        local c=canvas[i] or 0
        if c==rC and rLen<255 then rLen=rLen+1
        else table.insert(parts,rLen.."|"..rC); rC=c; rLen=1 end
    end
    table.insert(parts,rLen.."|"..rC)
    return table.concat(parts,",")
end

function PixelPaint:_deserialize(str)
    canvas={}
    if not str or str=="" then for i=1,CW*CH do canvas[i]=0 end; return end
    local idx=1
    for chunk in str:gmatch("[^,]+") do
        local cnt,ci=chunk:match("(%d+)|(%d+)")
        cnt=tonumber(cnt) or 1; ci=tonumber(ci) or 0
        for _=1,cnt do if idx<=CW*CH then canvas[idx]=ci end; idx=idx+1 end
    end
    while idx<=CW*CH do canvas[idx]=0; idx=idx+1 end
    cDirty=true
end

function PixelPaint:_save()
    local data=self:_serialize()
    if curNode then curNode.data=data
    else
        local parent=nil
        for _,f in ipairs(VFS:FindByType(BD.NT_FOLDER)) do
            if f.name=="Dibujos" then parent=f; break end
        end
        if not parent then parent=VFS:CreateFolder(VFS:GetRoot(),"Dibujos") end
        local cnt=#VFS:FindByType(BD.NT_IMG)+1
        local n=VFS:CreateFile(parent,"dibujo_"..cnt,BD.NT_IMG,data)
        if n then curNode=n end
    end
    dirty=false; UI:SetDirty(false); SaveSystem:Save(OSConfig)
end

function PixelPaint:_handleBack()
    if dirty then
        UI:ShowPopup("PixelPaint","Guardar dibujo?",{"Si","No"},function(idx)
            if idx==1 then self:_save() end
            if onClose then onClose() end
        end)
    else if onClose then onClose() end end
end

---------------------------------------------------------------------------

function PixelPaint:RegisterZones()
    InputManager:Register("pp_new",   BD.SW-118,HDR_Y,38,HDR_H,{onTap=function()
        if dirty then UI:ShowPopup("PixelPaint","Guardar?",{"Si","No"},function(i)
            if i==1 then self:_save() end; self:_newCanvas(); curNode=nil
        end)
        else self:_newCanvas(); curNode=nil end
    end})
    InputManager:Register("pp_save",  BD.SW-78, HDR_Y,38,HDR_H,{onTap=function() self:_save() end})
    InputManager:Register("pp_close", BD.SW-38, HDR_Y,36,HDR_H,{onTap=function() self:_handleBack() end})
    InputManager:Register("pp_pen",   2, TOOLS_Y,    PAN_W-4,18,{onTap=function() tool="pen"    end})
    InputManager:Register("pp_era",   2, TOOLS_Y+20, PAN_W-4,18,{onTap=function() tool="eraser" end})
    for i=0,15 do
        local col=i%4; local row=math.floor(i/4)
        local px=4+col*14; local py=PAL_Y+row*14; local ci=i
        InputManager:Register("pp_c"..i, px, py, 12, 12, {onTap=function() colorIdx=ci end})
    end
    for sz=1,3 do
        local bx=4+(sz-1)*18; local s=sz
        InputManager:Register("pp_b"..sz, bx,BRUSH_Y,16,14,{onTap=function() brushSz=s end})
    end
    InputManager:Register("pp_canvas", CX,CY,CPW,CPH, {
        onTap=function(_,pos) local cx,cy=self:_scToCanvas(pos.x,pos.y); self:_paint(cx,cy) end,
        onDragStart=function(_,pos) painting=true; local cx,cy=self:_scToCanvas(pos.x,pos.y); self:_paint(cx,cy); lastPX=cx; lastPY=cy end,
        onDrag=function(_,pos)
            if painting then
                local cx,cy=self:_scToCanvas(pos.x,pos.y)
                if cx~=lastPX or cy~=lastPY then self:_paint(cx,cy); lastPX=cx; lastPY=cy end
            end
        end,
        onDrop=function() painting=false; lastPX=-1; lastPY=-1 end,
    })
end

function PixelPaint:Update() end

function PixelPaint:Draw()
    Renderer:FillRect(0, BD.CONTENT_Y, BD.SW, BD.CONTENT_H, Theme.C.bg_window)
    self:_drawHeader()
    self:_drawPanel()
    self:_drawCanvas()
end

function PixelPaint:_drawHeader()
    Renderer:FillRect(0,HDR_Y,BD.SW,HDR_H,Theme.C.bg_panel)
    Renderer:DrawLine(0,HDR_Y+HDR_H-1,BD.SW-1,HDR_Y+HDR_H-1,Theme.C.border)
    local t=(curNode and curNode.name or "PixelPaint")..(dirty and " *" or "")
    Renderer:DrawTextTrunc(4,HDR_Y+5,t,24,Theme.C.text_accent)
    Renderer:DrawButton(BD.SW-118,HDR_Y+2,38,12,"Nuevo","normal")
    Renderer:DrawButton(BD.SW-78, HDR_Y+2,38,12,"Guardar",dirty and "normal" or "disabled")
    Renderer:DrawButton(BD.SW-38, HDR_Y+2,36,12,"Cerrar","normal")
end

function PixelPaint:_drawPanel()
    Renderer:FillRect(0,HDR_Y+HDR_H,PAN_W,BD.CONTENT_H-HDR_H,Theme.C.bg_panel)
    Renderer:DrawLine(PAN_W,HDR_Y+HDR_H,PAN_W,BD.TASKBAR_Y-1,Theme.C.border)
    Renderer:DrawText(3,TOOLS_LY,"TOOLS",Theme.C.text_secondary)
    Renderer:DrawButton(2,TOOLS_Y,   PAN_W-4,18,"Pen",    tool=="pen"    and "pressed" or "normal")
    Renderer:DrawButton(2,TOOLS_Y+20,PAN_W-4,18,"Eraser", tool=="eraser" and "pressed" or "normal")
    Renderer:DrawText(3,PAL_LY,"COLOR",Theme.C.text_secondary)
    for i=0,15 do
        local col=i%4; local row=math.floor(i/4)
        local px=4+col*14; local py=PAL_Y+row*14
        Renderer:FillRect(px,py,12,12,Theme.C.palette[i])
        if i==colorIdx then Renderer:DrawRect(px-1,py-1,14,14,Theme.C.white) end
    end
    Renderer:DrawText(3,BRUSH_LY,"BRUSH",Theme.C.text_secondary)
    for sz=1,3 do
        Renderer:DrawButton(4+(sz-1)*18,BRUSH_Y,16,14,tostring(sz),brushSz==sz and "pressed" or "normal")
    end
    Renderer:FillRect(4,CURCOL_Y,22,22,Theme.C.palette[colorIdx])
    Renderer:DrawRect(4,CURCOL_Y,22,22,Theme.C.border_focus)
end

function PixelPaint:_drawCanvas()
    Renderer:FillRect(CX-2,CY-2,CPW+4,CPH+4,Theme.C.border)
    if cDirty and _video then
        _video:RenderOnBuffer(0)
        _video:Clear(Theme.C.palette[0])
        for cy=1,CH do
            for cx=1,CW do
                local ci=canvas[(cy-1)*CW+cx] or 0
                if ci~=0 then
                    local px=(cx-1)*ZM; local py=(cy-1)*ZM
                    _video:FillRect(vec2(px,py),vec2(px+ZM-1,py+ZM-1),Theme.C.palette[ci])
                end
            end
        end
        _video:RenderOnScreen(); cDirty=false
    end
    if _video then
        _video:DrawRenderBuffer(vec2(CX,CY),_video.RenderBuffers[0],CPW,CPH)
    end
    local g=Color(30,30,50)
    for gx=0,CW do
        local sx=CX+gx*ZM
        Renderer:DrawLine(sx,CY,sx,CY+CPH-1,g)
    end
    for gy=0,CH do
        local sy=CY+gy*ZM
        Renderer:DrawLine(CX,sy,CX+CPW-1,sy,g)
    end
end

return PixelPaint