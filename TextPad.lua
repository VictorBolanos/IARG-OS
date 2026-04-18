---------------------------------------------------------------------------
-- TextPad.lua — Editor de texto
-- Usa globales: BD, Theme, Renderer, InputManager, VFS, UI, VirtualKeyboard
-- SaveSystem, OSConfig. NO hace require de nada.
---------------------------------------------------------------------------

TextPad = {}

-- Constantes de layout — se inicializan en Init() cuando BD ya existe
local HDR_Y, HDR_H, LIST_Y, ITEM_H, FOOT_Y, FOOT_H
local TA_Y, TA_H, TA_X, TA_W, VIS

local state        = "LIST"
local fileList     = {}
local selIdx       = 0
local curNode      = nil
local editText     = ""
local cursor       = 0
local dirty        = false
local blinkTick    = 0
local textScroll   = 0
local onClose      = nil
local newNameBuf   = ""
local waitName     = false

---------------------------------------------------------------------------

function TextPad:Init(closeCb, targetFile)
    -- Inicializar constantes de layout aquí (BD ya existe en este punto)
    HDR_Y  = BD.CONTENT_Y
    HDR_H  = 16
    LIST_Y = HDR_Y + HDR_H
    ITEM_H = 18
    FOOT_Y = BD.TASKBAR_Y - 16
    FOOT_H = 16
    TA_Y   = HDR_Y + HDR_H
    TA_H   = BD.TP_TEXTAREA_H
    TA_X   = BD.TP_TEXTAREA_X
    TA_W   = BD.TP_TEXTAREA_W
    VIS    = math.floor(TA_H / BD.CHAR_H)
    onClose = closeCb; state="LIST"; selIdx=0; dirty=false
    self:_refreshList()
    if targetFile then self:_openFile(targetFile) end
    UI:SetAppTitle("TextPad")
    UI:SetTaskbarCallbacks(
        function() self:_handleBack() end,
        function() if onClose then onClose() end end)
end

function TextPad:_refreshList()
    fileList = VFS:FindByType(BD.NT_TXT)
end

function TextPad:_openFile(node)
    curNode=node; editText=node.data or ""; cursor=#editText
    dirty=false; blinkTick=0; textScroll=0; state="EDIT"
    VirtualKeyboard:Show(function(ch) self:_handleKey(ch) end)
    UI:SetTaskbarCallbacks(
        function() self:_handleBack() end,
        function() if onClose then onClose() end end)
end

function TextPad:_createNew(name)
    local parent = nil
    for _, f in ipairs(VFS:FindByType(BD.NT_FOLDER)) do
        if f.name=="Documentos" then parent=f; break end
    end
    if not parent then parent=VFS:GetRoot() end
    local n = VFS:CreateFile(parent, name, BD.NT_TXT, "")
    if n then self:_refreshList(); self:_openFile(n); UI:SetDirty(true) end
end

function TextPad:_save()
    if not curNode then return end
    curNode.data=editText; dirty=false; UI:SetDirty(false)
    SaveSystem:Save(OSConfig)
end

function TextPad:_handleKey(ch)
    if ch=="DEL" then
        if cursor>0 then editText=editText:sub(1,cursor-1)..editText:sub(cursor+1); cursor=cursor-1; dirty=true end
    elseif ch=="ENTER" then
        if #editText<BD.TP_MAX_CHARS then editText=editText:sub(1,cursor).."\n"..editText:sub(cursor+1); cursor=cursor+1; dirty=true end
    elseif ch=="LEFT"  then cursor=math.max(0,cursor-1)
    elseif ch=="RIGHT" then cursor=math.min(#editText,cursor+1)
    elseif ch=="OK" or ch=="ESC" then VirtualKeyboard:Hide()
    elseif #ch==1 then
        if #editText<BD.TP_MAX_CHARS then editText=editText:sub(1,cursor)..ch..editText:sub(cursor+1); cursor=cursor+1; dirty=true end
    end
    if dirty then UI:SetDirty(true); self:_ensureCursorVis() end
end

function TextPad:_splitLines(text)
    local lines={}; local s=1
    while s <= #text+1 do
        local nl=text:find("\n",s,true)
        if nl then table.insert(lines,text:sub(s,nl-1)); s=nl+1
        else table.insert(lines,text:sub(s)); break end
    end
    if #lines==0 then lines={""} end
    return lines
end

function TextPad:_cursorLine(text, pos)
    local l=1; for i=1,pos do if text:sub(i,i)=="\n" then l=l+1 end end; return l
end

function TextPad:_cursorCol(text, pos)
    local c=0; for i=1,pos do local ch=text:sub(i,i); if ch=="\n" then c=0 else c=c+1 end end; return c
end

function TextPad:_ensureCursorVis()
    local cl = self:_cursorLine(editText, cursor)
    if cl < textScroll+1 then textScroll=cl-1
    elseif cl > textScroll+VIS then textScroll=cl-VIS end
    textScroll=math.max(0,textScroll)
end

function TextPad:_handleBack()
    if state=="EDIT" then
        if dirty then
            UI:ShowPopup("TextPad","Guardar cambios?",{"Si","No"},function(idx)
                if idx==1 then self:_save() end; self:_closeEditor()
            end)
        else self:_closeEditor() end
    else if onClose then onClose() end end
end

function TextPad:_closeEditor()
    VirtualKeyboard:Hide(); curNode=nil; editText=""; cursor=0; dirty=false
    state="LIST"; self:_refreshList()
    UI:SetTaskbarCallbacks(
        function() self:_handleBack() end,
        function() if onClose then onClose() end end)
end

---------------------------------------------------------------------------

function TextPad:RegisterZones()
    if state=="LIST" then self:_regListZones()
    else self:_regEditZones()
        if VirtualKeyboard:IsActive() then VirtualKeyboard:RegisterZones() end
    end
end

function TextPad:_regListZones()
    InputManager:Register("tp_new", BD.SW-56, HDR_Y, 54, HDR_H, {
        onTap=function() self:_startNameInput() end
    })
    local vis = math.floor((FOOT_Y-LIST_Y)/ITEM_H)
    for i=1,vis do
        local fi=i+selIdx  -- scrollOffset reutiliza selIdx como offset aquí no, usamos 0
        -- Nota: scroll no implementado en lista por simplicidad
        fi = i
        if fi>#fileList then break end
        local iy=LIST_Y+(i-1)*ITEM_H
        local fidx=fi
        InputManager:Register("tp_item_"..fidx, 0, iy, BD.SW-60, ITEM_H, {
            onTap=function() selIdx=fidx end,
            onDoubleTap=function() selIdx=fidx; self:_openFile(fileList[fidx]) end,
        })
    end
    InputManager:Register("tp_open", 4, FOOT_Y, 55, FOOT_H, {
        onTap=function()
            if selIdx>0 and fileList[selIdx] then self:_openFile(fileList[selIdx]) end
        end
    })
    InputManager:Register("tp_del", BD.SW-58, FOOT_Y, 56, FOOT_H, {
        onTap=function()
            if selIdx>0 and fileList[selIdx] then
                local n=fileList[selIdx]
                UI:ShowPopup("Eliminar","Borrar "..n.name.."?",{"Si","No"},function(idx)
                    if idx==1 then VFS:Delete(n); selIdx=0; self:_refreshList(); UI:SetDirty(true); SaveSystem:Save(OSConfig) end
                end)
            end
        end
    })
end

function TextPad:_regEditZones()
    InputManager:Register("tp_save",  BD.SW-38, HDR_Y, 36, HDR_H, {onTap=function() self:_save() end})
    InputManager:Register("tp_close", BD.SW-76, HDR_Y, 36, HDR_H, {onTap=function() self:_handleBack() end})
    InputManager:Register("tp_area",  TA_X, TA_Y, TA_W, TA_H, {
        onTap=function(_,pos)
            if not VirtualKeyboard:IsActive() then
                VirtualKeyboard:Show(function(ch) self:_handleKey(ch) end)
            end
            -- Mover cursor al toque
            local lines=self:_splitLines(editText)
            local relY=pos.y-TA_Y
            local li=math.floor(relY/BD.CHAR_H)+1+textScroll
            li=math.max(1,math.min(#lines,li))
            local relX=pos.x-TA_X
            local ci=math.floor(relX/BD.CHAR_W)
            local newC=0
            for i=1,li-1 do newC=newC+#(lines[i] or "")+1 end
            newC=newC+math.min(ci,#(lines[li] or ""))
            cursor=math.max(0,math.min(#editText,newC))
        end,
    })
end

function TextPad:_startNameInput()
    waitName=true; newNameBuf=""
    VirtualKeyboard:Show(function(ch)
        if ch=="OK" or ch=="ENTER" then
            waitName=false; VirtualKeyboard:Hide()
            local n=newNameBuf:match("^%s*(.-)%s*$")
            if n and #n>0 then self:_createNew(n) end
        elseif ch=="DEL" then
            if #newNameBuf>0 then newNameBuf=newNameBuf:sub(1,-2) end
        else if #newNameBuf<20 then newNameBuf=newNameBuf..ch end end
    end)
end

---------------------------------------------------------------------------

function TextPad:Update()
    blinkTick=blinkTick+1
    if blinkTick >= BD.CURSOR_BLINK*2 then blinkTick=0 end
end

function TextPad:Draw()
    Renderer:FillRect(0, BD.CONTENT_Y, BD.SW, BD.CONTENT_H, Theme.C.bg_window)
    if state=="LIST" then self:_drawList() else self:_drawEditor() end
end

function TextPad:_drawList()
    Renderer:FillRect(0, HDR_Y, BD.SW, HDR_H, Theme.C.bg_panel)
    Renderer:DrawLine(0, HDR_Y+HDR_H-1, BD.SW-1, HDR_Y+HDR_H-1, Theme.C.border)
    Renderer:DrawText(4, HDR_Y+5, "TextPad", Theme.C.text_accent)
    Renderer:DrawButton(BD.SW-56, HDR_Y+2, 54, 12, "+ Nuevo", "normal")

    local vis=math.floor((FOOT_Y-LIST_Y)/ITEM_H)
    for i=1,vis do
        if i>#fileList then break end
        local n=fileList[i]; local iy=LIST_Y+(i-1)*ITEM_H
        Renderer:DrawListItem(0, iy, BD.SW-60, ITEM_H, n.name, i==selIdx)
        local sz=tostring(#(n.data or "")).."ch"
        Renderer:DrawText(BD.SW-56, iy+5, sz, Theme.C.text_secondary)
    end
    if #fileList==0 then
        Renderer:DrawText(60, LIST_Y+40, "Sin archivos. Crea uno!", Theme.C.text_secondary)
    end

    Renderer:FillRect(0, FOOT_Y, BD.SW, FOOT_H, Theme.C.bg_panel)
    Renderer:DrawLine(0, FOOT_Y, BD.SW-1, FOOT_Y, Theme.C.border)
    Renderer:DrawButton(4, FOOT_Y+2, 55, 12, "Abrir",    selIdx>0 and "normal" or "disabled")
    Renderer:DrawButton(BD.SW-58, FOOT_Y+2, 56, 12, "Eliminar", selIdx>0 and "normal" or "disabled")

    if waitName then
        Renderer:FillRect(0, 142, BD.SW, 22, Theme.C.bg_window)
        Renderer:DrawLine(0, 142, BD.SW-1, 142, Theme.C.border_focus)
        Renderer:DrawText(4, 149, "Nombre: "..newNameBuf.."|", Theme.C.text_primary)
        VirtualKeyboard:Draw()
    end
end

function TextPad:_drawEditor()
    Renderer:FillRect(0, HDR_Y, BD.SW, HDR_H, Theme.C.bg_panel)
    Renderer:DrawLine(0, HDR_Y+HDR_H-1, BD.SW-1, HDR_Y+HDR_H-1, Theme.C.border)
    local title=(curNode and curNode.name or "sin titulo")..(dirty and " *" or "")
    Renderer:DrawTextTrunc(4, HDR_Y+5, title, 28, Theme.C.text_accent)
    Renderer:DrawButton(BD.SW-76, HDR_Y+2, 36, 12, "Cerrar", "normal")
    Renderer:DrawButton(BD.SW-38, HDR_Y+2, 36, 12, "Guardar", dirty and "normal" or "disabled")

    Renderer:FillRect(TA_X-1, TA_Y, TA_W+2, TA_H, Theme.C.bg_input)
    Renderer:DrawRect(TA_X-1, TA_Y, TA_W+2, TA_H, Theme.C.border)

    local lines = self:_splitLines(editText)
    local cLine = self:_cursorLine(editText, cursor)
    local cCol  = self:_cursorCol(editText, cursor)
    local showCursor = blinkTick < BD.CURSOR_BLINK

    for i=1,VIS do
        local li=i+textScroll
        if li>#lines then break end
        local txt=lines[li] or ""
        local ty=TA_Y+(i-1)*BD.CHAR_H+2
        -- Nro de línea
        Renderer:DrawText(2, ty, tostring(li), Theme.C.text_secondary)
        -- Texto de la línea
        Renderer:DrawText(TA_X, ty, txt, Theme.C.text_primary)
        -- Cursor
        if showCursor and li==cLine then
            local cx=TA_X+cCol*BD.CHAR_W
            Renderer:DrawLine(cx, ty, cx, ty+BD.CHAR_H-1, Theme.C.accent)
        end
    end

    local cnt=tostring(#editText).."/"..tostring(BD.TP_MAX_CHARS)
    Renderer:DrawText(BD.SW-Renderer:TextWidth(cnt)-4, TA_Y+TA_H-10, cnt, Theme.C.text_secondary)

    if VirtualKeyboard:IsActive() then VirtualKeyboard:Draw() end
end

return TextPad