---------------------------------------------------------------------------
-- VFS.lua — Sistema de Archivos Virtual
-- Usa global: BD. NO hace require de nada.
---------------------------------------------------------------------------

VFS = {}

local root    = nil
local nodeMap = {}
local nextId  = 1

local function newNode(id, name, t, parent)
    return {id=id, name=name, type=t, parent=parent,
            children={}, data=nil, posX=0, posY=0}
end

---------------------------------------------------------------------------

function VFS:Init()
    nextId = 1; nodeMap = {}
    root = newNode(nextId, "root", BD.NT_FOLDER, nil)
    nodeMap[nextId] = root; nextId = nextId + 1

    local tp = newNode(nextId, "TextPad", BD.NT_APP, root)
    tp.posX=16; tp.posY=20; nodeMap[nextId]=tp; nextId=nextId+1
    table.insert(root.children, tp)

    local pp = newNode(nextId, "PixelPaint", BD.NT_APP, root)
    pp.posX=72; pp.posY=20; nodeMap[nextId]=pp; nextId=nextId+1
    table.insert(root.children, pp)

    local docs = newNode(nextId, "Documentos", BD.NT_FOLDER, root)
    docs.posX=128; docs.posY=20; nodeMap[nextId]=docs; nextId=nextId+1
    table.insert(root.children, docs)

    local draws = newNode(nextId, "Dibujos", BD.NT_FOLDER, root)
    draws.posX=184; draws.posY=20; nodeMap[nextId]=draws; nextId=nextId+1
    table.insert(root.children, draws)
end

function VFS:GetRoot()   return root end
function VFS:GetById(id) return nodeMap[id] end

function VFS:GetChildren(folder)
    if not folder or folder.type ~= BD.NT_FOLDER then return {} end
    return folder.children
end

function VFS:CreateFile(parent, name, t, data)
    if not parent or parent.type ~= BD.NT_FOLDER then return nil end
    if self:Count() >= BD.VFS_MAX_NODES then return nil end
    local n = newNode(nextId, name, t, parent)
    n.data = data
    nodeMap[nextId] = n; nextId = nextId+1
    table.insert(parent.children, n)
    return n
end

function VFS:CreateFolder(parent, name)
    return self:CreateFile(parent, name, BD.NT_FOLDER, nil)
end

function VFS:Delete(node)
    if not node then return end
    if node.type == BD.NT_FOLDER then
        for i = #node.children, 1, -1 do self:Delete(node.children[i]) end
    end
    nodeMap[node.id] = nil
    if node.parent then
        for i, c in ipairs(node.parent.children) do
            if c.id == node.id then table.remove(node.parent.children, i); break end
        end
    end
end

function VFS:Rename(node, name)
    if node then node.name = name end
end

function VFS:Move(node, newParent)
    if not node or not newParent or newParent.type ~= BD.NT_FOLDER then return end
    if node.parent then
        for i, c in ipairs(node.parent.children) do
            if c.id == node.id then table.remove(node.parent.children, i); break end
        end
    end
    node.parent = newParent
    table.insert(newParent.children, node)
end

function VFS:GetPath(node)
    if not node then return "" end
    if not node.parent then return node.name end
    return self:GetPath(node.parent) .. "/" .. node.name
end

function VFS:Count()
    local n = 0; for _ in pairs(nodeMap) do n=n+1 end; return n
end

function VFS:FindByType(t, start)
    local res = {}
    local function r(n)
        if n.type == t then table.insert(res, n) end
        for _, c in ipairs(n.children) do r(c) end
    end
    r(start or root)
    return res
end

function VFS:GetIcon(node)
    if node.type == BD.NT_FOLDER    then return BD.ICO_FOLDER end
    if node.type == BD.NT_TXT       then return BD.ICO_TXT end
    if node.type == BD.NT_IMG       then return BD.ICO_IMG end
    if node.type == BD.NT_APP then
        if node.name == "TextPad"    then return BD.ICO_TEXTPAD end
        if node.name == "PixelPaint" then return BD.ICO_PIXELPAINT end
    end
    return BD.ICO_UNKNOWN
end

function VFS:Serialize()
    local list = {}
    local function r(n)
        table.insert(list, {
            id=n.id, name=n.name, type=n.type,
            pid = n.parent and n.parent.id or 0,
            posX=n.posX, posY=n.posY, data=n.data
        })
        for _, c in ipairs(n.children) do r(c) end
    end
    r(root); return list
end

function VFS:Deserialize(list)
    nextId=1; nodeMap={}
    if not list or #list==0 then self:Init(); return end
    for _, e in ipairs(list) do
        local n = {id=e.id, name=e.name, type=e.type,
                   parent=nil, children={}, data=e.data,
                   posX=e.posX or 0, posY=e.posY or 0}
        nodeMap[n.id] = n
        if n.id >= nextId then nextId = n.id+1 end
    end
    for _, e in ipairs(list) do
        local n = nodeMap[e.id]
        if e.pid == 0 then root = n
        else
            local p = nodeMap[e.pid]
            if p then n.parent = p; table.insert(p.children, n) end
        end
    end
    if not root then self:Init() end
end

return VFS