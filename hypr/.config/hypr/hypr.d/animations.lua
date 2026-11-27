hl.config({ animations = { enabled = true } })

hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("winIn", { type = "bezier", points = { { 0.1, 1.1 }, { 0.1, 1.1 } } })
hl.curve("winOut", { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
hl.curve("liner", { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "wind", style = "slide" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "winIn", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "winOut", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "wind", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "liner" })
-- The gradient sweeps once per focus change. A "loop" redraws every border,
-- and with them both screens and the blur behind translucent windows, every
-- frame: Hyprland went 74% -> 19% of the 780M with it off (2026-11-27).
-- astralis Settings > Look > Border motion overrides this (Spin / On AC / Still).
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "liner", style = "once" })
hl.animation({ leaf = "fade", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "wind" })
-- Layer fades (overview/power-menu frost) at ~250ms in, ~150ms out (the blur
-- trails the already-gone board otherwise) instead of the 1s window
-- fade, so the blur arrives and leaves with astralis's own motion.
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 2.5, bezier = "default" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.5, bezier = "default" })
