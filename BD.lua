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
BD.CONTENT_H = 212

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
    [0] = { name="IARG Classic",
        bg={12,12,24},    text={200,220,200}, prompt={80,200,255},
        output={180,180,210}, error={255,80,80}, success={80,220,120},
        dim={90,90,120},  topbar={8,8,18},    tbtext={80,200,255},
        tbclock={200,200,220}, cursor={80,200,255},
    },
    [1] = { name="Amber Terminal",
        bg={10,8,0},      text={255,176,0},   prompt={255,220,80},
        output={220,150,0}, error={255,60,0}, success={180,255,80},
        dim={120,80,0},   topbar={6,4,0},     tbtext={255,200,0},
        tbclock={200,150,0}, cursor={255,200,0},
    },
    [2] = { name="Green Matrix",
        bg={0,10,0},      text={0,220,0},     prompt={80,255,80},
        output={0,180,0}, error={255,80,0},   success={180,255,100},
        dim={0,80,0},     topbar={0,6,0},     tbtext={0,220,80},
        tbclock={0,180,0}, cursor={0,255,80},
    },
    [3] = { name="Arctic",
        bg={230,235,240}, text={20,20,40},    prompt={0,80,180},
        output={40,40,80}, error={200,0,0},   success={0,140,0},
        dim={140,140,160}, topbar={200,210,220}, tbtext={0,80,180},
        tbclock={40,40,80}, cursor={0,80,180},
    },
    -- 4: Blood Red -- deep black, crimson text, brutalist feel
    [4] = { name="Blood Red",
        bg={8,0,0},       text={220,40,40},   prompt={255,80,80},
        output={180,30,30}, error={255,200,0}, success={255,120,0},
        dim={100,20,20},  topbar={4,0,0},     tbtext={255,60,60},
        tbclock={200,40,40}, cursor={255,100,100},
    },
    -- 5: Red Matrix -- like Green Matrix but in deep red
    [5] = { name="Red Matrix",
        bg={10,0,0},      text={220,0,0},     prompt={255,60,60},
        output={180,0,0}, error={255,200,50},  success={255,120,0},
        dim={80,0,0},     topbar={6,0,0},     tbtext={255,40,40},
        tbclock={180,0,0}, cursor={255,80,80},
    },
    -- 6: Synthwave -- 80s purple/pink neon on dark navy
    [6] = { name="Synthwave",
        bg={10,5,20},     text={220,180,255}, prompt={255,80,220},
        output={180,130,255}, error={255,60,100}, success={80,255,200},
        dim={80,50,120},  topbar={6,3,14},    tbtext={255,80,220},
        tbclock={180,130,255}, cursor={255,80,220},
    },
    -- 7: Hacker Gold -- NSA terminal, black on gold
    [7] = { name="Hacker Gold",
        bg={5,4,0},       text={255,210,0},   prompt={255,240,80},
        output={200,160,0}, error={255,80,0},  success={150,255,80},
        dim={100,80,0},   topbar={3,2,0},     tbtext={255,220,30},
        tbclock={200,170,0}, cursor={255,240,80},
    },
    -- 8: Ocean Depth -- dark teal, bioluminescent feel
    [8] = { name="Ocean Depth",
        bg={0,12,18},     text={80,220,200},  prompt={0,255,220},
        output={60,180,160}, error={255,80,100}, success={100,255,180},
        dim={0,80,80},    topbar={0,7,12},    tbtext={0,200,180},
        tbclock={60,180,160}, cursor={0,255,220},
    },
    -- 9: Void -- near-black on near-black, ultra minimal
    [9] = { name="Void",
        bg={4,4,4},       text={130,130,130}, prompt={180,180,180},
        output={100,100,100}, error={200,60,60}, success={80,180,80},
        dim={50,50,50},   topbar={2,2,2},     tbtext={150,150,150},
        tbclock={100,100,100}, cursor={200,200,200},
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