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
