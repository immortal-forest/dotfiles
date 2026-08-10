-- XDG
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Qt
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- GTK
hl.env("GDK_BACKEND", "wayland,x11,*")

-- Electron
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Cursor
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Google.Violet")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Google.Violet")
-- Native-Wayland apps (Electron/Qt) load cursors via libwayland-cursor, whose
-- default search path OMITS ~/.local/share/icons — so a theme installed there
-- (Google.Violet) isn't found and they fall back to a black cursor. Point
-- XCURSOR_PATH at it explicitly (~/.icons is also symlinked as a backstop).
hl.env("XCURSOR_PATH", "/home/immortalforest/.local/share/icons:/home/immortalforest/.icons:/usr/share/icons:/usr/share/pixmaps")
