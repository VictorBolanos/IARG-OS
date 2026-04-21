---------------------------------------------------------------------------
-- BD.lua -- Global constants for IARG-OS (CLI mode)
-- NO Color() calls at root level -- themes are built in initOS()
---------------------------------------------------------------------------

BD = {}

-- SCREEN
BD.SW        = 336
BD.SH        = 160  -- real screen height (video.Height)
BD.TOPBAR_H  = 12
BD.TOPBAR_Y  = 0
BD.CONTENT_Y = 12
BD.CONTENT_H = 148   -- real content height (160 - 12px topbar)

-- FONT -- fontPrincipal.png uses 4x7 px per character (Tprint)
BD.CHAR_W = 4
BD.CHAR_H = 7

-- CLI
BD.CLI_X         = 2
BD.CLI_W         = 332
BD.CLI_MAX_LINES = 18
BD.CLI_CHARS     = 82

-- PROMPT
BD.PROMPT_PREFIX = "> "

-- CURSOR
BD.CURSOR_BLINK = 30

-- BOOT
BD.BOOT_BLACK_END      = 10
BD.BOOT_FADEIN_END     = 35
BD.BOOT_PROGRESS_START = 46
BD.BOOT_PROGRESS_END   = 72
BD.BOOT_FADEOUT_START  = 73
BD.BOOT_FADEOUT_END    = 85
BD.BOOT_DONE           = 86

BD.BOOT_MESSAGES = {
    [46] = "Loading IARG-Kernel...",
    [54] = "Mounting filesystem...",
    [62] = "Reading FlashMemory...",
    [70] = "Starting CLI...",
    [72] = "Ready.",
}

-- TEXTPAD
BD.TP_MAX_CHARS = 2000
BD.TP_LINES_VIS = 18
BD.TP_CHARS_W   = 54    -- chars per line in editor (336-4-linenum) / 4

-- VFS
BD.VFS_MAX_NODES = 80
BD.NT_FOLDER = "folder"
BD.NT_APP    = "app"
BD.NT_TXT    = "txt"
BD.NT_CFG    = "cfg"   -- config file type (.cfg), editable with TextPad

-- SAVE
BD.SAVE_VERSION = 2

-- THEMES -- RGB values only, Color() objects built via BD.BuildThemes() in initOS()
-- Format: {bg, text, prompt, output, error, success, dim, topbar, tbtext, tbclock, cursor}
-- each value is {r, g, b}
BD.THEME_DATA = {
    [0] = { name="Default",
        bg={15,15,25},    text={200,220,200}, prompt={100,180,255},
        output={180,180,210}, error={255,100,100}, success={100,255,150},
        dim={120,120,140}, topbar={10,10,20},   tbtext={100,180,255},
        tbclock={200,200,220}, cursor={100,180,255},
    },
    [1] = { name="Light",
        bg={245,245,250}, text={40,40,50},    prompt={60,100,200},
        output={60,60,80}, error={200,50,50},   success={50,150,50},
        dim={180,180,190}, topbar={230,235,240}, tbtext={60,100,200},
        tbclock={100,100,120}, cursor={60,100,200},
    },
    [2] = { name="Matrix Green",
        bg={0,15,0},      text={0,255,0},     prompt={100,255,100},
        output={0,200,0}, error={255,100,100}, success={100,255,100},
        dim={0,100,0},     topbar={0,10,0},     tbtext={0,255,100},
        tbclock={0,200,0}, cursor={0,255,100},
    },
    [3] = { name="Matrix Red",
        bg={15,0,0},      text={255,0,0},     prompt={255,100,100},
        output={200,0,0}, error={255,200,100}, success={255,150,100},
        dim={100,0,0},     topbar={10,0,0},     tbtext={255,100,100},
        tbclock={200,0,0}, cursor={255,100,100},
    },
    [4] = { name="Monokai",
        bg={39,40,34},    text={102,217,239}, prompt={249,128,38},
        output={190,190,170}, error={255,95,95}, success={150,200,100},
        dim={80,80,70},    topbar={30,30,25},   tbtext={249,128,38},
        tbclock={190,190,170}, cursor={249,128,38},
    },
    [5] = { name="Deep Ocean",
        bg={0,20,30},      text={100,200,220}, prompt={0,255,255},
        output={80,180,200}, error={255,100,150}, success={100,255,200},
        dim={0,60,80},     topbar={0,15,25},    tbtext={0,200,220},
        tbclock={80,180,200}, cursor={0,255,255},
    },
    [6] = { name="Xenospace",
        bg={25,0,40},      text={255,100,255}, prompt={200,150,255},
        output={180,80,200}, error={255,150,100}, success={150,255,200},
        dim={80,0,100},    topbar={15,0,30},    tbtext={200,100,255},
        tbclock={180,80,200}, cursor={200,150,255},
    },
    [7] = { name="Hacker Gold",
        bg={10,8,0},      text={255,215,0},   prompt={255,235,100},
        output={200,170,0}, error={255,100,0}, success={150,255,100},
        dim={100,80,0},    topbar={8,6,0},      tbtext={255,200,50},
        tbclock={200,170,0}, cursor={255,235,100},
    },
    [8] = { name="Caleido",
        bg={20,10,30},    text={255,150,200}, prompt={200,100,255},
        output={200,120,180}, error={255,200,100}, success={150,255,150},
        dim={100,60,120}, topbar={15,8,25},    tbtext={255,180,220},
        tbclock={200,120,180}, cursor={200,100,255},
    },
    [9] = { name="Void",
        bg={0,0,0},       text={80,80,80},    prompt={120,120,120},
        output={60,60,60}, error={150,50,50}, success={50,150,50},
        dim={30,30,30},    topbar={0,0,0},      tbtext={100,100,100},
        tbclock={60,60,60}, cursor={120,120,120},
    },
}

-- Builds the THEMES table with real Color() objects.
-- Call ONCE from initOS(), when the RG environment is ready.
function BD.BuildThemes()
    BD.THEMES = {}
    for i, d in pairs(BD.THEME_DATA) do
        BD.THEMES[i] = {
            name    = d.name,
            bg      = Color(d.bg[1],     d.bg[2],     d.bg[3]),
            text    = Color(d.text[1],   d.text[2],   d.text[3]),
            prompt  = Color(d.prompt[1], d.prompt[2], d.prompt[3]),
            output  = Color(d.output[1], d.output[2], d.output[3]),
            error   = Color(d.error[1],  d.error[2],  d.error[3]),
            success = Color(d.success[1],d.success[2],d.success[3]),
            dim     = Color(d.dim[1],    d.dim[2],    d.dim[3]),
            topbar  = Color(d.topbar[1], d.topbar[2], d.topbar[3]),
            tbtext  = Color(d.tbtext[1], d.tbtext[2], d.tbtext[3]),
            tbclock = Color(d.tbclock[1],d.tbclock[2],d.tbclock[3]),
            cursor  = Color(d.cursor[1], d.cursor[2], d.cursor[3]),
        }
    end
end

---------------------------------------------------------------------------

return BD