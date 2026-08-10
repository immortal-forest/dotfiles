# matugen — astralis theming pipeline

A GNU-stow package holding the [matugen](https://github.com/InioX/matugen) config and
templates that drive astralis's Material 3 dynamic color.

## Stow layout

```
matugen/
└── .config/
    └── matugen/
        ├── config.toml
        └── templates/
            ├── quickshell.json.hbs   # all 49 M3 roles as JSON (the live-color source)
            ├── hyprland.conf         # $<role> = rgba(...) via matugen's for-loop
            ├── cava                  # full cava config, [color] bound to the accent
            ├── kitty                 # kitty colors.conf
            ├── ghostty               # ghostty theme file
            └── rofi                  # rofi colors.rasi
```

Stow it from the dotfiles root:

```bash
cd ~/dotfiles && stow matugen
```

This links `matugen/.config/matugen` → `~/.config/matugen`.

## What it does

`matugen image <wallpaper>` reads `~/.config/matugen/config.toml`, renders every
`[templates.*]` entry, and writes each to its **absolute** `output_path` (the paths
point at the *deployed* config locations, not into this repo):

| Template   | output_path                                                     | Notes |
|------------|-----------------------------------------------------------------|-------|
| quickshell | `~/.config/quickshell/astralis/colors/Colors.json`              | `~/.config/quickshell` is a symlink into the dotfiles repo; this file is gitignored there |
| hyprland   | `~/.config/hypr/colors.conf`                                    | `post_hook = hyprctl reload` |
| cava       | `~/.config/cava/config`                                         | full config regenerated each run |
| kitty      | `~/.config/kitty/colors.conf`                                   | `include colors.conf` from kitty.conf |
| ghostty    | `~/.config/ghostty/themes/matugen`                              | `theme = matugen` in ghostty config |
| rofi       | `~/.config/rofi/colors.rasi`                                    | `@import` from your rofi theme |

## The live-color contract

`quickshell.json.hbs` → `Colors.json` is the hinge of the whole rice. The astralis
Quickshell `Colors` singleton (`colors/Colors.qml`) watches `Colors.json` with a
`FileView { watchChanges: true }` and reloads it on a 100 ms debounce, so every widget
reading `Colors.primary`, `Colors.surface_container`, etc. recolors **live** the instant
the wallpaper changes — no restart. If `Colors.json` is absent (matugen not installed
yet), the singleton falls back to a coherent dark M3 palette, so the shell still renders.

Wallpaper changes are wired through a `setwall` script that runs `swww` then
`matugen image <path>` (see the astralis wallpaper module), regenerating every template
and firing the post-hooks in one action.
