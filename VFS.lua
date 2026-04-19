---------------------------------------------------------------------------
-- VFS.lua — Sistema de Archivos Virtual
---------------------------------------------------------------------------

local BD = require("BD.lua")
VFS = {}

local root    = nil
local nodeMap = {}
local nextId  = 1

local function newNode(id, name, ntype, parent)
    return { id=id, name=name, type=ntype, parent=parent,
             children={}, data=nil, posX=0, posY=0 }
end

function VFS:Init()
    nextId=1; nodeMap={}
    root = newNode(nextId,"root",BD.NT_FOLDER,nil); nodeMap[nextId]=root; nextId=nextId+1
    local docs = newNode(nextId,"Documentos",BD.NT_FOLDER,root)
    nodeMap[nextId]=docs; nextId=nextId+1; table.insert(root.children,docs)
end

function VFS:GetRoot()    return root end
function VFS:GetById(id)  return nodeMap[id] end

function VFS:GetChildren(n)
    if not n or n.type~=BD.NT_FOLDER then return {} end
    return n.children
end

function VFS:CreateFile(parent, name, ntype, data)
    if not parent or parent.type~=BD.NT_FOLDER then return nil end
    if self:CountNodes()>=BD.VFS_MAX_NODES then return nil end
    local node=newNode(nextId,name,ntype,parent)
    node.data=data; nodeMap[nextId]=node; nextId=nextId+1
    table.insert(parent.children,node); return node
end

function VFS:CreateFolder(parent, name)
    return self:CreateFile(parent,name,BD.NT_FOLDER,nil)
end

function VFS:Delete(node)
    if not node then return end
    if node.type==BD.NT_FOLDER then
        for i=#node.children,1,-1 do self:Delete(node.children[i]) end
    end
    nodeMap[node.id]=nil
    if node.parent then
        for i,c in ipairs(node.parent.children) do
            if c.id==node.id then table.remove(node.parent.children,i); break end
        end
    end
end

function VFS:Rename(node, newName)
    if node then node.name=newName end
end

function VFS:GetPath(node)
    if not node then return "" end
    if not node.parent then return node.name end
    return self:GetPath(node.parent).."/"..node.name
end

function VFS:CountNodes()
    local n=0; for _ in pairs(nodeMap) do n=n+1 end; return n
end

function VFS:FindByType(ntype, start)
    local results={}
    local function r(n)
        if n.type==ntype then table.insert(results,n) end
        for _,c in ipairs(n.children) do r(c) end
    end
    r(start or root); return results
end

-- Finds a child node by name in a folder
function VFS:FindChild(folder, name)
    if not folder then return nil end
    for _,c in ipairs(folder.children) do
        if c.name==name then return c end
    end
    return nil
end

-- Serialization
function VFS:Serialize()
    local list={}
    local function r(node)
        table.insert(list,{
            id=node.id, name=node.name, type=node.type,
            pid=node.parent and node.parent.id or 0,
            data=node.data
        })
        for _,c in ipairs(node.children) do r(c) end
    end
    r(root); return list
end

function VFS:Deserialize(list)
    nextId=1; nodeMap={}
    if not list or #list==0 then self:Init(); return end
    for _,e in ipairs(list) do
        local node={id=e.id,name=e.name,type=e.type,
                    parent=nil,children={},data=e.data,posX=0,posY=0}
        nodeMap[node.id]=node
        if node.id>=nextId then nextId=node.id+1 end
    end
    for _,e in ipairs(list) do
        local node=nodeMap[e.id]
        if e.pid==0 then root=node
        else
            local p=nodeMap[e.pid]
            if p then node.parent=p; table.insert(p.children,node) end
        end
    end
    if not root then self:Init() end
end

---------------------------------------------------------------------------

return VFS