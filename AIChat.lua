---------------------------------------------------------------------------
-- AIChat.lua -- AI Chat for IARG-OS
-- Provider: Groq (free) -- sign up at console.groq.com
-- Create ai.cfg in root:  apikey=gsk_xxx  model=llama-3.3-70b-versatile
-- run AI  |  Enter=send  ESC=exit  Ctrl+L=clear  Ctrl+Up/Down=scroll
---------------------------------------------------------------------------

-- BD, VFS are globals loaded by IARG-OS.lua

AIChat = {}

local BD         = require("BD.lua")

local _video, _font, _theme, _wifi, _onClose
local _apikey  = ""
local _model   = "llama-3.3-70b-versatile"
local _url     = "https://api.groq.com/openai/v1/chat/completions"
local _history = {}
local _lines   = {}
local _input, _cursor, _blink = "", 0, 0
local _scroll  = 0
local _pending, _waiting, _dotT, _dots = nil, false, 0, 0
local _sw, _sh, _chatY, _chatH, _promptY, _sepY, _charsW
local SESSION_KEY = "__aichat_session__"

---------------------------------------------------------------------------
local function tp(x, y, txt, col)
    if not _font or not _video then return end
    for i = 1, #txt do
        local ch = txt:sub(i,i)
        _video:DrawSprite(vec2(x+(i-1)*BD.CHAR_W,y),_font,
            ch:byte()%32,math.floor(ch:byte()/32),col,color.clear)
    end
end

local function wrap(txt, maxW)
    local out = {}
    for para in (txt.."\n"):gmatch("([^\n]*)\n") do
        if #para == 0 then
            table.insert(out, "")
        else
            local cur = ""
            for word in para:gmatch("%S+") do
                local test = #cur>0 and (cur.." "..word) or word
                if #test > maxW then
                    if #cur>0 then table.insert(out,cur); cur=word
                    else
                        while #word>maxW do
                            table.insert(out,word:sub(1,maxW))
                            word=word:sub(maxW+1)
                        end
                        cur=word
                    end
                else cur=test end
            end
            if #cur>0 then table.insert(out,cur) end
        end
    end
    return #out>0 and out or {""}
end

local function pushLines(prefix, text, colorKey)
    local maxW = _charsW - #prefix
    if maxW < 10 then maxW = 10 end
    local wrapped = wrap(text, maxW)
    for i, ln in ipairs(wrapped) do
        local display = (i==1) and (prefix..ln) or (string.rep(" ",#prefix)..ln)
        table.insert(_lines, {text=display, col=colorKey})
    end
    table.insert(_lines, {text="", col="sys"})
    _scroll = 0
end

local function pushSys(text)
    for _, ln in ipairs(wrap(text, _charsW)) do
        table.insert(_lines, {text=ln, col="sys"})
    end
    _scroll = 0
end

local function pushErr(text)
    for _, ln in ipairs(wrap(text, _charsW)) do
        table.insert(_lines, {text=ln, col="err"})
    end
    table.insert(_lines, {text="", col="sys"})
    _scroll = 0
end

---------------------------------------------------------------------------
local function fixEncoding(s)
    s = s:gsub("\195\177", "\128")  -- n~
    s = s:gsub("\195\145", "\127")  -- N~
    s = s:gsub("\194\191", "\129")  -- i?
    s = s:gsub("\194\161", "\130")  -- i!
    s = s:gsub("\195\161", "a")
    s = s:gsub("\195\169", "e")
    s = s:gsub("\195\173", "i")
    s = s:gsub("\195\179", "o")
    s = s:gsub("\195\186", "u")
    s = s:gsub("\195\129", "A")
    s = s:gsub("\195\137", "E")
    s = s:gsub("\195\141", "I")
    s = s:gsub("\195\147", "O")
    s = s:gsub("\195\154", "U")
    s = s:gsub("\195\188", "u")
    return s
end

local function stripMarkdown(s)
    s = s:gsub("%*%*(.-)%*%*","%1"):gsub("__(.-)__","%1")
    s = s:gsub("%*(.-)%*","%1"):gsub("`(.-)`%s*","%1")
    s = s:gsub("^#+%s*",""):gsub("\n#+%s*","\n")
    s = s:gsub("\n[%-%*]%s+","\n"):gsub("^[%-%*]%s+","")
    return s
end

local function saveSession()
    local parts = {}
    for _, msg in ipairs(_history) do
        local safe = msg.content:gsub("|","||"):gsub("\n","\\n")
        table.insert(parts, msg.role.."|"..safe)
    end
    local root = VFS:GetRoot()
    local node = VFS:FindChild(root, SESSION_KEY)
    if not node then
        node = VFS:CreateFile(root, SESSION_KEY, BD.NT_TXT, "")
    end
    if node then node.data = table.concat(parts,"\n") end
end

local function loadSession()
    local root = VFS:GetRoot()
    local node = VFS:FindChild(root, SESSION_KEY)
    if not node or not node.data or #node.data==0 then return false end
    _history = {}
    for line in (node.data.."\n"):gmatch("([^\n]*)\n") do
        local role, content = line:match("^([^|]+)|(.*)$")
        if role and content then
            content = content:gsub("\\n","\n"):gsub("||","|")
            table.insert(_history, {role=role, content=content})
        end
    end
    return #_history > 0
end

local function loadConfig()
    local root = VFS:GetRoot()
    local node = VFS:FindChild(root, "ai.cfg")
    if not node or not node.data or #node.data==0 then return false end
    for line in (node.data.."\n"):gmatch("([^\n]*)\n") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k=="apikey" and v and #v>0 then _apikey=v end
        if k=="model"  and v and #v>0 then _model=v  end
        if k=="url"    and v and #v>0 then _url=v    end
    end
    return true
end

local function jsonStr(s)
    s=s:gsub('\\','\\\\'):gsub('"','\\"')
    s=s:gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
    return '"'..s..'"'
end

local function buildBody()
    local parts = {}
    for _, msg in ipairs(_history) do
        table.insert(parts,'{"role":'..jsonStr(msg.role)..',"content":'..jsonStr(msg.content)..'}')
    end
    return '{"model":'..jsonStr(_model)..',"messages":['..table.concat(parts,",")..'],"max_tokens":1024}'
end

-- Decode \uXXXX JSON unicode escapes for Spanish characters
local function decodeUnicode(s)
    -- Handle common Spanish chars as \uXXXX JSON escapes
    s = s:gsub("\\u00f1", "\127")  -- ñ
    s = s:gsub("\\u00d1", "\128")  -- Ñ
    s = s:gsub("\\u00bf", "\129")  -- ¿
    s = s:gsub("\\u00a1", "\130")  -- ¡
    s = s:gsub("\\u00e1", "a")      -- á
    s = s:gsub("\\u00e9", "e")      -- é
    s = s:gsub("\\u00ed", "i")      -- í
    s = s:gsub("\\u00f3", "o")      -- ó
    s = s:gsub("\\u00fa", "u")      -- ú
    s = s:gsub("\\u00fc", "u")      -- ü
    s = s:gsub("\\u00c1", "A")      -- Á
    s = s:gsub("\\u00c9", "E")      -- É
    s = s:gsub("\\u00cd", "I")      -- Í
    s = s:gsub("\\u00d3", "O")      -- Ó
    s = s:gsub("\\u00da", "U")      -- Ú
    -- Also handle uppercase hex variants
    s = s:gsub("\\u00F1", "\127")
    s = s:gsub("\\u00D1", "\128")
    s = s:gsub("\\u00BF", "\129")
    s = s:gsub("\\u00A1", "\130")
    return s
end

local function parseBody(txt)
    if not txt or #txt==0 then return nil,"empty response" end
    local content = txt:match('"content"%s*:%s*"(.-)"[%s]*[,}]')
    if not content then content = txt:match('"content"%s*:%s*"(.*)"') end
    if content then
        content=content:gsub('\\n','\n'):gsub('\\t','\t'):gsub('\\"','"'):gsub('\\\\','\\')
        content=decodeUnicode(content)
        return content, nil
    end
    local err = txt:match('"message"%s*:%s*"(.-)"') or txt:match('"error"%s*:%s*"(.-)"')
    return nil, err or "could not parse response"
end

local function sendMessage(userText)
    if _waiting then return end
    if #_apikey==0 then pushErr("No API key. Create 'ai.cfg' in root."); return end
    if not _wifi   then pushErr("Wifi module not found."); return end
    if _wifi.AccessDenied then pushErr("Network permission denied."); return end
    table.insert(_history, {role="user", content=userText})
    pushLines("You: ", userText, "user")
    saveSession()
    _waiting=true; _dots=0; _dotT=0
    local headers = {Authorization="Bearer ".._apikey}
    _pending = _wifi:WebCustomRequest(_url,"POST",headers,"application/json",buildBody())
end

---------------------------------------------------------------------------
function AIChat:HandleWifiEvent(event)
    if not _waiting then return end
    if event.RequestHandle ~= _pending then return end
    _waiting=false; _pending=nil
    if event.IsError then pushErr("Network error: "..(event.ErrorMessage or "unknown")); return end
    if event.ResponseCode==401 then pushErr("HTTP 401: Invalid API key."); return end
    if event.ResponseCode==429 then pushErr("HTTP 429: Rate limit. Retry later."); return end
    if event.ResponseCode~=200 then pushErr("HTTP "..tostring(event.ResponseCode)); return end
    local text, err = parseBody(event.Text)
    if err then
        pushErr("Parse error: "..err)
    else
        local clean = fixEncoding(stripMarkdown(text))
        table.insert(_history, {role="assistant", content=text})
        pushLines("AI:  ", clean, "ai")
        saveSession()
    end
end

---------------------------------------------------------------------------
function AIChat:_toChar(name, shift)
    local L={A="a",B="b",C="c",D="d",E="e",F="f",G="g",H="h",I="i",J="j",
             K="k",L="l",M="m",N="n",O="o",P="p",Q="q",R="r",S="s",T="t",
             U="u",V="v",W="w",X="x",Y="y",Z="z"}
    if L[name] then return shift and name or L[name] end
    local N={Alpha0="0",Alpha1="1",Alpha2="2",Alpha3="3",Alpha4="4",
             Alpha5="5",Alpha6="6",Alpha7="7",Alpha8="8",Alpha9="9",
             Keypad0="0",Keypad1="1",Keypad2="2",Keypad3="3",Keypad4="4",
             Keypad5="5",Keypad6="6",Keypad7="7",Keypad8="8",Keypad9="9"}
    if N[name] then return N[name] end
    if shift then
        if name=="Minus"        then return "_" end
        if name=="Alpha2"       then return '"' end
        if name=="Alpha7"       then return "/" end
        if name=="Alpha8"       then return "(" end
        if name=="Alpha9"       then return ")" end
        if name=="Alpha0"       then return "=" end
        if name=="Quote"        then return "@" end
        if name=="LeftBracket"  then return "[" end
        if name=="RightBracket" then return "]" end
        if name=="Backslash"    then return "|" end
        if name=="Equals"       then return "+" end
        if name=="Period"       then return ":" end
        if name=="Comma"        then return ";" end
        if name=="Slash"        then return "?" end
    end
    local S={Space=" ",Period=".",Comma=",",Minus="-",Slash="/",
             Backslash="\\",Semicolon=";",Quote="'",Equals="=",
             LeftBracket="[",RightBracket="]",BackQuote="\128",  -- ñ
             Exclaim="!",DoubleQuote='"',Hash="#",Dollar="$",
             Percent="%",Ampersand="&",LeftParen="(",RightParen=")",
             Asterisk="*",Plus="+",Colon=":",Less="<",Greater=">",
             Question="?",At="@",Caret="^",Underscore="_",
             LeftCurlyBracket="{",Pipe="|",RightCurlyBracket="}",Tilde="~",
             KeypadPeriod=".",KeypadDivide="/",KeypadMultiply="*",
             KeypadMinus="-",KeypadPlus="+",KeypadEquals="="}
    return S[name]
end

---------------------------------------------------------------------------
function AIChat:HandleKey(name, shift, ctrl)
    if name=="Escape" then if _onClose then _onClose() end; return end
    if ctrl and name=="L" then
        _lines={}; _history={}; _scroll=0
        saveSession(); pushSys("Chat cleared."); return
    end
    local vis = math.floor(_chatH/BD.CHAR_H)
    if ctrl and name=="UpArrow" then
        _scroll=math.min(_scroll+1, math.max(0,#_lines-vis)); return
    end
    if ctrl and name=="DownArrow" then _scroll=math.max(0,_scroll-1); return end
    if _waiting then return end
    if name=="LeftArrow"  then _cursor=math.max(0,_cursor-1); return end
    if name=="RightArrow" then _cursor=math.min(#_input,_cursor+1); return end
    if name=="Home"       then _cursor=0; return end
    if name=="End"        then _cursor=#_input; return end
    if name=="Backspace" then
        if _cursor>0 then _input=_input:sub(1,_cursor-1).._input:sub(_cursor+1); _cursor=_cursor-1 end
        return
    end
    if name=="Delete" then
        if _cursor<#_input then _input=_input:sub(1,_cursor).._input:sub(_cursor+2) end
        return
    end
    if name=="Return" or name=="KeypadEnter" then
        local msg=_input:match("^%s*(.-)%s*$")
        if msg and #msg>0 then sendMessage(msg); _input=""; _cursor=0 end
        return
    end
    if #_input < _charsW-4 then
        local ch = self:_toChar(name,shift)
        if ch then _input=_input:sub(1,_cursor)..ch.._input:sub(_cursor+1); _cursor=_cursor+1 end
    end
end

---------------------------------------------------------------------------
function AIChat:Init(video, font, theme, wifi, onClose)
    _video=video; _font=font; _theme=theme; _wifi=wifi; _onClose=onClose
    _sw=video.Width; _sh=video.Height
    local promptH=BD.CHAR_H+4
    _promptY=_sh-promptH+1; _sepY=_sh-promptH-2
    _chatY=BD.CONTENT_Y+2; _chatH=_sepY-_chatY-2
    _charsW=math.floor((_sw-4)/BD.CHAR_W)
    _lines={}; _history={}; _input=""; _cursor=0
    _blink=0; _scroll=0; _waiting=false; _pending=nil
    local ok=loadConfig()
    pushSys("IARG-OS AI Chat  |  model: ".._model)
    pushSys("Ctrl+L=clear  Ctrl+Up/Down=scroll  ESC=exit")
    if not ok or #_apikey==0 then
        pushErr("No API key! Create 'ai.cfg' in root: apikey=gsk_...")
        pushSys("Free key at: console.groq.com")
    else
        if loadSession() and #_history>0 then
            for _, msg in ipairs(_history) do
                local prefix = msg.role=="user" and "You: " or "AI:  "
                local text   = msg.role=="user" and msg.content or stripMarkdown(msg.content)
                pushLines(prefix, text, msg.role=="user" and "user" or "ai")
            end
            pushSys("-- Session restored ("..#_history.." messages) --")
        else
            pushSys("Ready. Type a message and press Enter.")
        end
    end
    pushSys(string.rep("-", math.min(_charsW,42)))
end

---------------------------------------------------------------------------
function AIChat:Update()
    _blink=_blink+1
    if _blink>=BD.CURSOR_BLINK*2 then _blink=0 end
    if _waiting then
        _dotT=_dotT+1
        if _dotT>=15 then _dotT=0; _dots=(_dots%4)+1 end
    end
end

---------------------------------------------------------------------------
function AIChat:Draw()
    if not _video or not _theme then return end
    local colMap={user=_theme.prompt,ai=_theme.text,sys=_theme.dim,err=_theme.error}
    _video:FillRect(vec2(0,BD.CONTENT_Y),vec2(_sw-1,_sh-1),_theme.bg)
    local vis=math.floor(_chatH/BD.CHAR_H)
    local total=#_lines
    local maxS=math.max(0,total-vis)
    if _scroll>maxS then _scroll=maxS end
    local extraLine=nil
    if _waiting then
        extraLine={text="AI:  "..string.rep(".",_dots),col="ai"}
        total=total+1
    end
    local startIdx=math.max(1,total-vis+1-_scroll)
    for i=startIdx, startIdx+vis-1 do
        if i>=1 then
            local entry=nil
            if i<=#_lines then
                entry=_lines[i]
            elseif extraLine and i==#_lines+1 then
                entry=extraLine
            end
            if entry==nil then break end
            local lineY=_chatY+(i-startIdx)*BD.CHAR_H
            if entry.text~="" then
                tp(2,lineY,entry.text,colMap[entry.col] or _theme.dim)
            end
        end
    end
    if _scroll>0 then
        local ind="^".._scroll
        tp(_sw-(#ind+1)*BD.CHAR_W,_chatY,ind,_theme.dim)
    end
    _video:DrawLine(vec2(0,_sepY),vec2(_sw-1,_sepY),_theme.dim)
    if _waiting then
        tp(2,_promptY,"Waiting"..string.rep(".",_dots),_theme.dim)
    else
        local pfx="> "
        tp(2,_promptY,pfx,_theme.prompt)
        local ix=2+#pfx*BD.CHAR_W
        tp(ix,_promptY,_input,_theme.text)
        if _blink<BD.CURSOR_BLINK then
            local cx=ix+_cursor*BD.CHAR_W
            _video:DrawLine(vec2(cx,_promptY),vec2(cx,_promptY+BD.CHAR_H-1),_theme.cursor)
        end
    end
end

---------------------------------------------------------------------------

return AIChat