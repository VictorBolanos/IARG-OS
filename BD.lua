---------------------------------------------------------------------------
-- BD.lua — Constantes globales de IARG-OS (versión CLI)
---------------------------------------------------------------------------

BD = {}

-- PANTALLA
BD.SW        = 336
BD.SH        = 224
BD.TOPBAR_H  = 12
BD.TOPBAR_Y  = 0
BD.CONTENT_Y = 12
BD.CONTENT_H = 212   -- 224 - 12 (sin taskbar en CLI)

-- FUENTE — Tprint usa 4×7 px por carácter
BD.CHAR_W = 4
BD.CHAR_H = 7

-- CLI — área de terminal
BD.CLI_X         = 2              -- margen izquierdo
BD.CLI_W         = 332            -- ancho útil
BD.CLI_FIRST_Y   = 14             -- primera línea de output (bajo topbar)
BD.CLI_MAX_LINES = 28             -- líneas visibles: 212/7  30, dejamos margen
BD.CLI_CHARS     = 82             -- chars por línea: 332/4

-- PROMPT
BD.PROMPT_PREFIX = "> "           -- prefijo del prompt

-- INPUT
BD.HOLD_TICKS       = 35
BD.TAP_MAX_TICKS    = 18
BD.DOUBLE_TAP_TICKS = 22
BD.DRAG_MIN_PX      = 4
BD.CURSOR_BLINK     = 30

-- BOOT
BD.BOOT_BLACK_END      = 10
BD.BOOT_FADEIN_END     = 35
BD.BOOT_PROGRESS_START = 46
BD.BOOT_PROGRESS_END   = 72
BD.BOOT_FADEOUT_START  = 73
BD.BOOT_FADEOUT_END    = 85
BD.BOOT_DONE           = 86

BD.BOOT_MESSAGES = {
    [46] = "Cargando IARG-Kernel...",
    [54] = "Montando sistema de archivos...",
    [62] = "Leyendo FlashMemory...",
    [70] = "Iniciando CLI...",
    [72] = "Listo.",
}

-- TEXTPAD
BD.TP_MAX_CHARS = 2000
BD.TP_CHARS_W   = 82    -- chars por línea en el editor
BD.TP_LINES_VIS = 27    -- líneas visibles en el editor

-- VFS
BD.VFS_MAX_NODES = 80
BD.NT_FOLDER = "folder"
BD.NT_APP    = "app"
BD.NT_TXT    = "txt"

-- PALETA (para themes)
BD.THEMES = {
    [0] = { -- IARG Classic (cyan oscuro)
        bg       = Color(12,  12,  24),
        text     = Color(200, 220, 200),
        prompt   = Color(80,  200, 255),
        output   = Color(180, 180, 210),
        error    = Color(255, 80,  80),
        success  = Color(80,  220, 120),
        dim      = Color(90,  90,  120),
        topbar   = Color(8,   8,   18),
        tbtext   = Color(80,  200, 255),
        tbclock  = Color(200, 200, 220),
        cursor   = Color(80,  200, 255),
    },
    [1] = { -- Amber Terminal
        bg       = Color(10,  8,   0),
        text     = Color(255, 176, 0),
        prompt   = Color(255, 220, 80),
        output   = Color(220, 150, 0),
        error    = Color(255, 60,  0),
        success  = Color(180, 255, 80),
        dim      = Color(120, 80,  0),
        topbar   = Color(6,   4,   0),
        tbtext   = Color(255, 200, 0),
        tbclock  = Color(200, 150, 0),
        cursor   = Color(255, 200, 0),
    },
    [2] = { -- Green Matrix
        bg       = Color(0,   10,  0),
        text     = Color(0,   220, 0),
        prompt   = Color(80,  255, 80),
        output   = Color(0,   180, 0),
        error    = Color(255, 80,  0),
        success  = Color(180, 255, 100),
        dim      = Color(0,   80,  0),
        topbar   = Color(0,   6,   0),
        tbtext   = Color(0,   220, 80),
        tbclock  = Color(0,   180, 0),
        cursor   = Color(0,   255, 80),
    },
    [3] = { -- Blanco / Arctic
        bg       = Color(230, 235, 240),
        text     = Color(20,  20,  40),
        prompt   = Color(0,   80,  180),
        output   = Color(40,  40,  80),
        error    = Color(200, 0,   0),
        success  = Color(0,   140, 0),
        dim      = Color(140, 140, 160),
        topbar   = Color(200, 210, 220),
        tbtext   = Color(0,   80,  180),
        tbclock  = Color(40,  40,  80),
        cursor   = Color(0,   80,  180),
    },
}

BD.SAVE_VERSION = 2

---------------------------------------------------------------------------

return BD