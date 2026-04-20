---------------------------------------------------------------------------
-- Utils.lua -- Shared utilities for IARG-OS
-- Centralized character input handling and text processing
---------------------------------------------------------------------------

-- BD is global loaded by IARG-OS.lua

Utils = {}

---------------------------------------------------------------------------
-- Convert InputName to printable character with Spanish support
-- Used by CLI, TextPad, and AIChat for consistent input handling
---------------------------------------------------------------------------

function Utils:InputToChar(name, shift)
    -- Spanish character substitutes (consistent across all apps)
    -- Solo se aplican si shift está activo para no interferir con caracteres básicos
    if shift then
        local spanishSubs = {
            -- Vocales con tilde (using nearby keys)
            LeftBracket = "á",  -- Shift + [ (near 'a')
            LeftCurlyBracket = "Á", -- Shift + { (capital á)
            Semicolon = "é",   -- Shift + ; (near 'e')
            Colon = "É",       -- Shift + : (capital é)
            Quote = "í",       -- Shift + ' (near 'i')
            DoubleQuote = "Í",  -- Shift + " (capital í)
            Comma = "ó",       -- Shift + , (near 'o')
            Less = "Ó",        -- Shift + < (capital ó)
            Period = "ú",      -- Shift + . (near 'u')
            Greater = "Ú",      -- Shift + > (capital ú)
            
            -- Signos españoles
            Question = "¿",    -- Shift + ? (opening question mark)
            Exclaim = "¡",     -- Shift + ! (inverted exclamation)
        }
        
        -- Check Spanish substitutes for shifted keys
        if spanishSubs[name] then
            return spanishSubs[name]
        end
    end
    
    -- Letters A-Z
    local letters = {
        A="a",B="b",C="c",D="d",E="e",F="f",G="g",H="h",I="i",J="j",
        K="k",L="l",M="m",N="n",O="o",P="p",Q="q",R="r",S="s",T="t",
        U="u",V="v",W="w",X="x",Y="y",Z="z"
    }
    if letters[name] then return shift and name or letters[name] end

    -- Digits
    local nums = {
        Alpha0="0",Alpha1="1",Alpha2="2",Alpha3="3",Alpha4="4",
        Alpha5="5",Alpha6="6",Alpha7="7",Alpha8="8",Alpha9="9",
        Keypad0="0",Keypad1="1",Keypad2="2",Keypad3="3",Keypad4="4",
        Keypad5="5",Keypad6="6",Keypad7="7",Keypad8="8",Keypad9="9",
    }
    if nums[name] then return nums[name] end

    -- Shift combinations
    if shift then
        if name == "Minus"        then return "_"     end  -- underscore
        if name == "Alpha2"       then return '"'    end
        if name == "Alpha7"       then return "/"    end
        if name == "Alpha8"       then return "("    end
        if name == "Alpha9"       then return ")"    end
        if name == "Alpha0"       then return "="    end
        if name == "Quote"        then return "@"    end
        if name == "LeftBracket"  then return "["    end
        if name == "RightBracket" then return "]"    end
        if name == "Backslash"    then return "|"    end
        if name == "Equals"       then return "+"    end
        if name == "Period"       then return ":"    end
        if name == "Comma"        then return ";"    end
        if name == "Slash"        then return "?"    end
        if name == "BackQuote"    then return "\128"    end  -- Ñ mayúscula (row4col0)
    end

    -- Direct symbols
    local direct = {
        Space             = " ",
        Period            = ".",
        Comma             = ",",
        Minus             = "-",
        Slash             = "/",
        Backslash         = "\\",
        Semicolon         = ";",
        Quote             = "'",
        Equals            = "=",
        LeftBracket       = "[",
        RightBracket      = "]",
        BackQuote         = "\127",  -- ñ minúscula (row3col31)
        Exclaim           = "!",
        DoubleQuote       = '"',
        Hash              = "#",
        Dollar            = "$",
        Percent           = "%",
        Ampersand         = "&",
        LeftParen         = "(",
        RightParen        = ")",
        Asterisk          = "*",
        Plus              = "+",
        Colon             = ":",
        Less              = "<",
        Greater           = ">",
        Question          = "?",
        At                = "@",
        Caret             = "^",
        Underscore        = "_",
        LeftCurlyBracket  = "{",
        Pipe              = "|",
        RightCurlyBracket = "}",
        Tilde             = "~",
        KeypadPeriod      = ".",
        KeypadDivide      = "/",
        KeypadMultiply    = "*",
        KeypadMinus       = "-",
        KeypadPlus        = "+",
        KeypadEquals      = "=",
    }
    return direct[name]
end

---------------------------------------------------------------------------
-- Calculate sprite coordinates for special characters
-- Standard ASCII: col = char % 32, row = math.floor(char / 32)
-- Special chars (127-130): custom mapping

function Utils:GetSpriteCoords(ch)
    local byteVal = ch:byte()
    
    -- Special Spanish characters mapping (solo para caracteres > 126)
    if byteVal == 127 then  -- ñ (row3col31)
        return 31, 3
    elseif byteVal == 128 then  -- Ñ (row4col0)
        return 0, 4
    elseif byteVal == 129 then  -- ¿ (row4col1)
        return 1, 4
    elseif byteVal == 130 then  -- ¡ (row4col3)
        return 3, 4
    else
        -- Standard ASCII calculation (para caracteres 0-126)
        return byteVal % 32, math.floor(byteVal / 32)
    end
end

---------------------------------------------------------------------------
-- Convert UTF-8 special chars to custom font sprite bytes
-- Sprite positions: ñ=row3col31 (char 127) Ñ=row4col0 (char 128) ¿=row4col1 (char 129) ¡=row4col3 (char 130)

function Utils:FixEncoding(s)
    s = s:gsub("\195\177", "\127")  -- ñ (row3col31)
    s = s:gsub("\195\145", "\128")  -- Ñ (row4col0)
    s = s:gsub("\194\191", "\129")  -- ¿ (row4col1)
    s = s:gsub("\194\161", "\130")  -- ¡ (row4col3)
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

---------------------------------------------------------------------------
-- Text wrapping utility for text display
---------------------------------------------------------------------------

function Utils:WrapText(txt, maxW)
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

---------------------------------------------------------------------------
-- DrawSprite-based text print (single line, uses custom font)
-- Used by CLI, TextPad, AIChat, Topbar via their local tp wrappers

function Utils:DrawText(video, font, x, y, txt, col)
    if not font or not video then return end
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        local bv = ch:byte()
        local sx, sy
        -- Special chars 127-130 use custom sprite positions
        if bv == 127 then sx, sy = 31, 3
        elseif bv == 128 then sx, sy = 0, 4
        elseif bv == 129 then sx, sy = 1, 4
        elseif bv == 130 then sx, sy = 2, 4
        else sx = bv % 32; sy = math.floor(bv / 32)
        end
        video:DrawSprite(vec2(x + (i-1)*BD.CHAR_W, y), font, sx, sy, col, color.clear)
    end
end

---------------------------------------------------------------------------

return Utils