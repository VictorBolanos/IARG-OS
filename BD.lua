---------------------------------------------------------------------------
-- BD.lua — Constantes globales de IARG-OS
-- NO hace require de nada. Solo define la tabla BD global.
-- Se carga primero desde IARG-OS.lua con require("BD.lua")
---------------------------------------------------------------------------

BD = {}

-- PANTALLA
BD.SW         = 336
BD.SH         = 224
BD.TOPBAR_H   = 12
BD.TASKBAR_H  = 12
BD.TOPBAR_Y   = 0
BD.TASKBAR_Y  = 212
BD.CONTENT_Y  = 12
BD.CONTENT_H  = 200   -- 224 - 12 - 12

-- FUENTE (Tprint: 4×7 px por carácter)
BD.CHAR_W = 4
BD.CHAR_H = 7

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
    [70] = "Iniciando escritorio...",
    [72] = "Listo.",
}

-- ESCRITORIO
BD.ICON_SPR    = 16
BD.ICON_CELL_W = 48
BD.ICON_CELL_H = 36
BD.ICON_PAD_Y  = 4
BD.ICON_LABEL_Y = 24

-- POPUP
BD.POPUP_W = 180
BD.POPUP_H = 80
BD.POPUP_X = 78    -- (336-180)/2
BD.POPUP_Y = 72    -- (224-80)/2

-- TEXTPAD
BD.TP_MAX_CHARS    = 1500
BD.TP_HEADER_H     = 16
BD.TP_TEXTAREA_Y   = 28
BD.TP_TEXTAREA_H   = 124
BD.TP_TEXTAREA_X   = 18   -- deja espacio para nro de línea
BD.TP_TEXTAREA_W   = 314

-- PIXELPAINT
BD.PP_CANVAS_W   = 56
BD.PP_CANVAS_H   = 48
BD.PP_ZOOM       = 3
BD.PP_PANEL_W    = 64
BD.PP_CANVAS_X   = 68
BD.PP_CANVAS_Y   = 28

-- PALETA 16 colores (valores 0-255)
BD.PALETTE = {
    [0]  = {r=18,  g=18,  b=32},
    [1]  = {r=255, g=255, b=255},
    [2]  = {r=180, g=180, b=200},
    [3]  = {r=90,  g=90,  b=110},
    [4]  = {r=220, g=50,  b=50},
    [5]  = {r=50,  g=200, b=80},
    [6]  = {r=60,  g=120, b=220},
    [7]  = {r=230, g=210, b=50},
    [8]  = {r=230, g=120, b=30},
    [9]  = {r=160, g=60,  b=210},
    [10] = {r=50,  g=210, b=220},
    [11] = {r=230, g=100, b=160},
    [12] = {r=130, g=70,  b=30},
    [13] = {r=130, g=220, b=80},
    [14] = {r=100, g=180, b=255},
    [15] = {r=220, g=200, b=160},
}

-- VFS
BD.VFS_MAX_NODES = 80
BD.NT_FOLDER = "folder"
BD.NT_APP    = "app"
BD.NT_TXT    = "txt"
BD.NT_IMG    = "img"

-- Iconos en uiIcons.png (col, fila) — sprites 16×16
BD.ICO_TEXTPAD    = {sx=0, sy=0}
BD.ICO_PIXELPAINT = {sx=1, sy=0}
BD.ICO_FOLDER     = {sx=2, sy=0}
BD.ICO_FOLDER_OPEN= {sx=3, sy=0}
BD.ICO_TXT        = {sx=4, sy=0}
BD.ICO_IMG        = {sx=5, sy=0}
BD.ICO_UNKNOWN    = {sx=6, sy=0}
BD.ICO_SAVE       = {sx=0, sy=1}
BD.ICO_HOME       = {sx=1, sy=1}
BD.ICO_BACK       = {sx=2, sy=1}
BD.ICO_OK         = {sx=3, sy=1}
BD.ICO_CANCEL     = {sx=4, sy=1}
BD.ICO_NEW        = {sx=5, sy=1}
BD.ICO_DELETE     = {sx=6, sy=1}
BD.ICO_RENAME     = {sx=7, sy=1}

-- SAVE
BD.SAVE_VERSION = 1

return BD