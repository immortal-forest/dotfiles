-- Suppress maximize requests (most apps misbehave when maximized under a tiler)
hl.window_rule({
	name  = "suppress-maximize",
	match = { class = ".*" },
	suppress_event = "maximize",
})

-- XWayland drag fix
hl.window_rule({
	name  = "xwayland-drag-fix",
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- Opacity: "active override inactive override" — absolute values (override = not multiplied)
hl.window_rule({ name = "opacity-firefox",  match = { class = "^firefox$" },               opacity = "0.9 override 0.9 override" })
hl.window_rule({ name = "opacity-zen",      match = { class = "^zen$" },                   opacity = "0.9 override 0.9 override" })
hl.window_rule({ name = "opacity-spotify",  match = { class = "^spotify$" },               opacity = "0.8 override 0.8 override" })
hl.window_rule({ name = "opacity-spotify2", match = { initial_title = "^Spotify Free$" },  opacity = "0.8 override 0.8 override" })
hl.window_rule({ name = "opacity-kitty",    match = { class = "^kitty$" },                 opacity = "0.9 override 0.9 override" })
hl.window_rule({ name = "opacity-ghostty",  match = { class = "^com.mitchellh.ghostty$" }, opacity = "0.9 override 0.9 override" })
hl.window_rule({ name = "opacity-nvim",     match = { title = ".*(nvim.*)$" },             opacity = "1.0 override 1.0 override" })
hl.window_rule({ name = "opacity-tmux",     match = { title = ".*(tmux.*)$" },             opacity = "1.0 override 1.0 override" })
hl.window_rule({ name = "opacity-qt5ct",    match = { class = "^qt5ct$" },                 opacity = "0.8 override 0.8 override" })
hl.window_rule({ name = "opacity-qt6ct",    match = { class = "^qt6ct$" },                 opacity = "0.8 override 0.8 override" })
hl.window_rule({ name = "opacity-discord",  match = { class = "^discord$" },               opacity = "0.9 override 0.9 override" })
hl.window_rule({ name = "opacity-solver",   match = { title = ".*solver.*" },              opacity = "0.2 override 0.2 override" })

-- Float
hl.window_rule({ name = "float-portal",      match = { class = "^xdg-desktop-portal-gtk$" },        float = true })
hl.window_rule({ name = "float-firefox-lib", match = { class = "^firefox$", title = "^Library$" },  float = true })
hl.window_rule({ name = "float-qt5ct",       match = { class = "^qt5ct$" },                         float = true })
hl.window_rule({ name = "float-qt6ct",       match = { class = "^qt6ct$" },                         float = true })
-- astralis: settings floating window (Quickshell FloatingWindow, title set in
-- modules/settings/SettingsWindow.qml). Float + centre it, and drop Hyprland's
-- own rounding/border so they don't fight the Panel's own rounded corners
-- (Hyprland rounds at 10 + a 2px border while the Panel rounds larger — that
-- mismatch was the squared, bordered corner). The Panel's radius over the
-- transparent window is then the only corner.
hl.window_rule({ name = "astralis-settings-float",    match = { title = "^astralis-settings$" }, float = true })
hl.window_rule({ name = "astralis-settings-center",   match = { title = "^astralis-settings$" }, center = true })
hl.window_rule({ name = "astralis-settings-rounding", match = { title = "^astralis-settings$" }, rounding = 0 })
hl.window_rule({ name = "astralis-settings-noborder", match = { title = "^astralis-settings$" }, border_size = 0 })

-- Tearing (immediate mode for games)
hl.window_rule({ name = "tear-lunar",     match = { class = "^Lunar Client" },      immediate = true })
hl.window_rule({ name = "tear-minecraft", match = { class = "^Minecraft Launcher" }, immediate = true })

-- Layer rules for the astralis shell (Quickshell layer-shell surfaces).
-- The reserve window's exclusive zone already reserves the top strip — no Hyprland gap here.
-- Pill overlay: blur behind, skip fully-transparent pixels, slide in from the top.
hl.layer_rule({
	name  = "astralis-pill",
	match = { namespace = "^astralis-pill$" },
	blur         = true,
	ignore_alpha = true,
	animation    = "slide top",
})
-- astralis: top-strip reserve spacer (fully transparent, exclusive zone only) —
-- same blur/ignore-alpha treatment so it never tints or blurs anything visible.
hl.layer_rule({
	name  = "astralis-reserve",
	match = { namespace = "^astralis-reserve$" },
	blur         = true,
	ignore_alpha = true,
	animation    = "slide top",
})
-- Fullscreen visualizer (bottom layer): blur the wallpaper behind, skip transparent pixels.
hl.layer_rule({
	name  = "astralis-viz",
	match = { namespace = "^astralis-viz$" },
	blur         = true,
	ignore_alpha = true,
})
-- Standalone wallpaper picker (full-width carousel overlay): frost the ENTIRE
-- band. ignore_alpha is deliberately OFF (unlike the pill) so the blur renders
-- behind the near-transparent scrim too — the whole window reads as blurred
-- glass instead of a dark dim, and the carousel cards pop over it.
-- astralis's own QML picker is no longer bound to a key (superseded by
-- skwd-wall below) but this rule is left in place — harmless if unused.
hl.layer_rule({
	name  = "astralis-wallpaper",
	match = { namespace = "^astralis-wallpaper$" },
	blur         = true,
	ignore_alpha = false,
})
-- skwd-wall v2 (standalone, github.com/liixini/skwd-wall — Rust/iced_layershell
-- rewrite, default branch): same whole-screen frost treatment, keyed on ITS
-- OWN layer-shell namespace. Confirmed from its actual source
-- (src/shell/shell.rs: `fn namespace() -> String { String::from("skwd-wall") }`),
-- not the README — can't be renamed without patching skwd-wall itself.
hl.layer_rule({
	name  = "skwd-wall",
	match = { namespace = "^skwd-wall$" },
	blur         = true,
	ignore_alpha = false,
})
-- Standalone full-screen power/session menu overlay: same whole-screen frost
-- treatment as the wallpaper picker (ignore_alpha OFF so the blur renders
-- behind the menu's own light scrim too, instead of a hard dim).
hl.layer_rule({
	name  = "astralis-powermenu",
	match = { namespace = "^astralis-powermenu$" },
	blur         = true,
	ignore_alpha = false,
})
