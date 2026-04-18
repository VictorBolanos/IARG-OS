---------------------------------------------------------------------------
-- Theme.lua — Colores del tema IARG Classic
-- Usa BD (global). NO hace require de nada.
-- Theme:Init() se llama una vez desde IARG-OS.lua tras cargar BD.
-- Color(r,g,b) y ColorRGBA(r,g,b,a) toman valores 0-255.
---------------------------------------------------------------------------

Theme    = {}
Theme.C  = {}

function Theme:Init()
    -- Fondos
    Theme.C.bg_desktop   = Color(18,  18,  32)
    Theme.C.bg_window    = Color(28,  28,  48)
    Theme.C.bg_panel     = Color(12,  12,  24)
    Theme.C.bg_input     = Color(22,  22,  40)
    Theme.C.bg_selection = Color(40,  100, 180)
    Theme.C.bg_hover     = Color(38,  38,  70)

    -- Texto
    Theme.C.text_primary   = Color(220, 220, 240)
    Theme.C.text_secondary = Color(130, 130, 155)
    Theme.C.text_accent    = Color(80,  200, 255)
    Theme.C.text_error     = Color(255, 90,  90)
    Theme.C.text_success   = Color(80,  220, 120)
    Theme.C.text_warning   = Color(255, 200, 60)

    -- Acento / bordes
    Theme.C.accent       = Color(80,  200, 255)
    Theme.C.border       = Color(55,  55,  80)
    Theme.C.border_focus = Color(80,  200, 255)

    -- Botones
    Theme.C.btn_bg          = Color(45,  45,  75)
    Theme.C.btn_hover       = Color(65,  65,  105)
    Theme.C.btn_pressed     = Color(80,  200, 255)
    Theme.C.btn_text        = Color(220, 220, 240)
    Theme.C.btn_text_press  = Color(18,  18,  32)

    -- Básicos
    Theme.C.white       = color.white
    Theme.C.black       = color.black
    Theme.C.transparent = color.clear

    -- Paleta PixelPaint (construida desde BD.PALETTE)
    Theme.C.palette = {}
    for i = 0, 15 do
        local p = BD.PALETTE[i]
        Theme.C.palette[i] = Color(p.r, p.g, p.b)
    end
end

return Theme