# ASTRALIS — Quickshell Dynamic-Island Rice
### Research · Architecture · Build Spec (Hyprland + Quickshell + Matugen, Material 3)

> Target: a single morphing "dynamic island" pill (Ricelin-style) driven by **matugen** Material 3 tokens, a **full-screen music visualizer** and **wallpaper changer with live retheme** (dhrruvsharma-style), all with M3 expressive micro-animations. Built on your existing Arch + Hyprland 0.55 (Lua) + `astralis` stack.
>
> This document has four parts: (1) what the two reference repos actually do, distilled; (2) the target architecture for astralis; (3) highly specific implementation docs with the exact patterns; (4) a Claude Code sub-agent build prompt you can paste.

---

## PART 1 — The two references, distilled

### 1.1 `Gakuseei/Ricelin` — the morphing pill (QML 92%, hand-written Quickshell)

This is the gold-standard implementation of "one pill that morphs into everything." No waybar. Key architectural moves you must copy:

**A. Two layer-shell windows per monitor (`reserve` + `overlay`).**
- `reserve` — a zero-content `PanelWindow` with `exclusionMode: ExclusionMode.Normal` and an `exclusiveZone` equal to the resting pill height + top gap. Its only job is to push tiled windows down so they never sit under the pill, *even while the pill is expanded*. The pill itself never reserves space beyond rest height.
- `overlay` — a full-screen **transparent** `PanelWindow` on `WlrLayer.Overlay` with `exclusionMode: ExclusionMode.Ignore`, hosting the single pill anchored top-center. The pill grows *in place*; it is never re-parented and never moves windows.

**B. Input routing by window mask** — the trick that makes a full-screen overlay not eat all your clicks:
```qml
mask: monFullscreen ? hiddenRegion : (modal ? fullRegion : pillRegion)
```
- Collapsed → mask is just the pill rectangle → the rest of the screen clicks through to windows.
- Expanded / surface open (`modal`) → mask cleared to full screen → the layer catches clicks so a backdrop press dismisses and Escape closes.
- Fullscreen window on that monitor → mask hidden, pill retracts off the top edge.

**C. One `Item` carries every state.** Width/height are driven by a single `mode` string. A `surfaces` descriptor map is the *single source of truth* — each entry owns a target-size thunk and an anchor thunk. Adding a surface = one map entry + one Loader, no parallel ternary chains:
```qml
readonly property var surfaces: ({
    calendar: { size: () => Qt.size(...), ame: () => surfaceItem(ldCalendar) },
    media:    { size: () => { surfaceItem(ldMedia); return Qt.size(mediaW, mediaH); }, ame: () => surfaceItem(ldMedia) },
    // ...
})
readonly property string mode: surfaceOpen ? surface : (expanded ? "hover" : "rest")
readonly property size targetSize: surfaces[mode] ? surfaces[mode].size() : modeSize[mode]()
width:  targetW
height: targetH
Behavior on width  { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
Behavior on height { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
```

**D. `morphCloseness` gates content fade** — surfaces fade in only as the pill *reaches* full size, so you never see content painted over a half-grown pill:
```qml
readonly property real morphCloseness: {
    const d = Math.max(Math.abs(width - targetW), Math.abs(height - targetH));
    return 1 - Math.min(1, d / (110 * s));
}
// each face: opacity: mode === "hover" ? Math.pow(morphCloseness, 1.2) : 0
```

**E. The `Motion` singleton** — the actual feel of the morph. The signature curve is expo-out:
```qml
readonly property int  morph:      420   // ms — full surface morph
readonly property int  glide:      260   // ms — short rest↔hover hop
readonly property int  standard:   300
readonly property int  fast:       140
readonly property int  easeMorph:  Easing.BezierSpline
readonly property var  morphCurve: [0.16, 1, 0.3, 1, 1, 1]   // cubic-bezier(0.16,1,0.3,1)
readonly property real mult: reduceMotion ? 0.4 : 1           // all durations × mult
```
Note the `hoverHop` optimization: rest↔hover are only ~30px apart, so a 420ms morph reads sluggish on that hop; both endpoints use the shorter `glide` while real surface morphs keep the full duration.

**F. Latch-once lazy Loaders.** Every surface sleeps in an inactive `Loader` until first open; `surfaceItem(ld)` flips `active=true` then returns `ld.item`. Loading is synchronous so the first open reads real `implicitHeight` in the same evaluation and the morph target is exact. Nothing ever deactivates. A `Timer` preloads the "hot trio" (mixer/media/link) 2.5s after start so their PipeWire/MPRIS trackers are bound before first open.

**G. Rest-pill cava spectrum.** A headless `cava` reads the default sink monitor (system-wide audio, not one MPRIS player) and emits raw ascii; the `Cava` singleton parses it to normalized 0..1 levels; `MusicBars.qml` renders one rounded bar per band, packed into the clock-glyph slot so it never widens the pill. An `active` debounce (450ms) stops inter-track gaps from flapping the clock↔bars morph.

Ricelin uses **wallust** (not matugen) and a hand-tuned vermilion `Theme.qml`. We replace that layer with matugen M3 (see 1.2). Everything above is theme-agnostic and transfers directly.

### 1.2 `dhrruvsharma/shell` — full-screen viz, matugen, wallpaper (QML 84%, Python 14%, GLSL)

This is where the **matugen dynamic theming**, **full-screen music animation**, and **wallpaper changer** come from.

**A. Full-screen music visualizer** (`components/Visualizer.qml`) — a `PanelWindow` on `WlrLayer.Bottom` (above wallpaper, below windows), full width, `exclusionMode: Ignore`, `keyboardFocus: None`. A `cava` process (pulse input, raw ascii, 20 bars) feeds a `Canvas` that draws a "mountain wave": quadratic-curve spline across the band values, filled with a matugen `primary→tertiary→secondary` gradient, plus a translated/scaled shadow pass at 0.25 alpha. `shell.qml` mounts two — one anchored bottom, one anchored top (flipped) — toggled together via `qs ipc call visBottom toggle`. Values are smoothed frame-to-frame (`old + (new-old)*0.3`) so it flows instead of strobing.

**B. The matugen → Quickshell live-color pipeline** — this is the piece you specifically want. `~/.config/matugen/config.toml` declares one template per app; the quickshell one is a **Handlebars** file emitting a full M3 token JSON:
```toml
[templates.quickshell]
input_path  = "~/.config/matugen/templates/quickshell.json.hbs"
output_path = "~/.config/quickshell/colors/Colors.json"
```
```jsonc
// quickshell.json.hbs  (all 49 M3 roles)
{ "background": "{{colors.surface.default.hex}}",
  "primary": "{{colors.primary.default.hex}}",
  "surface_container": "{{colors.surface_container.default.hex}}",
  /* ...on_primary, primary_container, tertiary, outline, surface_container_{low..highest}, etc... */ }
```
`Colors.qml` is a singleton that watches that JSON with `FileView { watchChanges: true }` and reloads on a 100ms debounce — so every widget reading `Colors.primary` recolors **live** the instant the wallpaper changes, no restart:
```qml
FileView { id: colorsFile; path: HOME + "/.config/quickshell/colors/Colors.json"; watchChanges: true; onFileChanged: reloadTimer.restart() }
Timer  { id: reloadTimer; interval: 100; onTriggered: colorsFile.reload() }
property string primary: _colorsData.primary ?? "#d0bcfe"   // JSON.parse with fallbacks
```
The same config.toml also templates cava (recolors the bars to `primary`/`primary_container`), hyprland (`colors.conf` with a `<* for name,value in colors *>` loop → `post_hook = "hyprctl reload"`), gtk3/4, kitty, rofi.

**C. Wallpaper changer + retheme** (`modules/wallpaper/*`, `services/WallpaperFavorites.qml`). A skewed 3D carousel over a `FolderListModel` of `~/Pictures/wallpapers`, with a favorites filter persisted to its own JSON via `FileView`/`JsonAdapter`. Selection calls a `setwall` script that runs **swww** (`swww img … --transition-type any`) then **matugen image <path>** which regenerates every template and fires the post-hooks. Result: wallpaper crossfades and the whole desktop recolors in one action.

**D. M3 motion tokens** (`config/AppearanceConfig.qml`) — the *official* Material 3 easing sets and durations as a `JsonObject`, which you should adopt wholesale for "Material design/animations":
```qml
component AnimCurves: JsonObject {
    property list<real> emphasized:            [0.05,0, 2/15,0.06, 1/6,0.4, 5/24,0.82, 0.25,1, 1,1]
    property list<real> emphasizedAccel:       [0.3,0, 0.8,0.15, 1,1]
    property list<real> emphasizedDecel:       [0.05,0.7, 0.1,1, 1,1]
    property list<real> standard:              [0.2,0, 0,1, 1,1]
    property list<real> expressiveFastSpatial: [0.42,1.67, 0.21,0.9, 1,1]   // overshoot ("Pixel" bounce)
    property list<real> expressiveDefaultSpatial:[0.38,1.21, 0.22,1, 1,1]
    property list<real> expressiveEffects:     [0.34,0.8, 0.34,1, 1,1]
}
component AnimDurations: JsonObject {
    property int small: 200; property int normal: 400; property int large: 600;
    property int expressiveFastSpatial: 350; property int expressiveDefaultSpatial: 500;
}
```
The `expressive*Spatial` curves have `y>1` control points → **overshoot/bounce**, which is exactly the Pixel/Material-3-Expressive micro-animation feel you're after.

---

## PART 2 — Target architecture for `astralis`

**Synthesis:** take **Ricelin's morph engine** (Part 1.1 A–F) but drive its colors from **matugen M3 `Colors.qml`** (Part 1.2 B) instead of a hand-tuned theme; layer in **dhrruvsharma's full-screen Canvas visualizer** (1.2 A) and **wallpaper carousel + `setwall` retheme** (1.2 C); animate everything with the **M3 expressive tokens** (1.2 D) with `expressiveDefaultSpatial` as the pill morph curve for that Pixel bounce.

### 2.1 The layer stack (bottom → top)
| Layer | Window | Contents |
|---|---|---|
| `WlrLayer.Background` | swww | wallpaper (managed outside QS) |
| `WlrLayer.Bottom` | `Visualizer` ×2 | full-screen mountain-wave music viz (top+bottom), toggle via IPC |
| *(client windows)* | — | your apps |
| `WlrLayer.Top` (`reserve`) | per-monitor | exclusive-zone spacer only |
| `WlrLayer.Overlay` (`overlay`) | per-monitor | the morphing pill + all surfaces + OSD/toasts |

### 2.2 Directory layout (qmldir module system)
```
~/.config/quickshell/
├── shell.qml                       # ShellRoot entry: Variants over screens, IpcHandlers
├── .qmlls.ini                      # (empty; QS manages it — gitignore) LSP support
├── colors/
│   ├── Colors.json                 # ← matugen output (gitignore)
│   ├── Colors.qml                  # M3 token singleton, live FileView reload
│   └── qmldir                      # singleton Colors
├── config/
│   ├── Appearance.qml              # facade singleton
│   └── AppearanceConfig.qml        # M3 curves/durations/rounding/spacing tokens
├── services/                       # singletons: system state
│   ├── Motion.qml                  # morph durations + curves (M3 expressive)
│   ├── Cava.qml                    # rest-pill spectrum (sink monitor)
│   ├── Players.qml                 # MPRIS selection
│   ├── Wallpaper.qml               # swww query/set + setwall bridge
│   ├── WallpaperFavorites.qml      # persisted favorites
│   └── (Battery, Network, Volume, Notification, Time, System …)
├── pill/                           # the dynamic island
│   ├── Pill.qml                    # the one morphing Item (mode → geometry)
│   ├── PillSurface.qml             # shared surface chrome (header/back)
│   ├── MusicBars.qml               # rest-pill cava spectrum
│   ├── Osd.qml  Toast.qml          # non-surface morph faces
│   └── surfaces/  (Media, Calendar, Mixer, Wallpaper, Power, Link, Launcher…)
├── modules/
│   ├── visualizer/Visualizer.qml   # full-screen Canvas viz (WlrLayer.Bottom)
│   └── wallpaper/WallpaperPicker.qml
└── assets/  shaders/  scripts/
```

### 2.3 Component responsibilities
- **`Pill.qml`** owns `mode`, `targetSize`, `morphCloseness`, `Behavior`s, the `surfaces` map, the Loaders, and the rest/hover faces. It is the whole engine.
- **`Colors.qml`** is read *everywhere* as `Colors.primary`, `Colors.surface_container`, etc. Never hard-code a hex. This is what makes retheme instant and free.
- **`Motion.qml`** is read for every animation duration/curve. One knob (`mult`) does reduce-motion.
- **`Visualizer.qml`** and the pill are independent windows that both read `Cava` + `Colors` — no coupling.

---

## PART 3 — Highly specific implementation docs

### 3.1 Toolchain & packages (Arch, current as of mid-2026)
```bash
# Compositor (you have 0.55+ Lua already)
# Shell toolkit — release in extra, master in AUR:
sudo pacman -S quickshell            # release (recommended; rebuilt on Qt bumps by repo)
#   OR: paru -S quickshell-git       # master; YOU must rebuild after every Qt update

# Dynamic color
paru -S matugen-bin                  # or `cargo install matugen`

# Wallpaper daemon + audio spectrum + MPRIS + misc
sudo pacman -S swww cava playerctl cliphist wl-clipboard
# Fonts: a Nerd/Material set — Material Symbols Rounded + your JetBrainsMono NF
paru -S ttf-material-symbols-variable-git
```
> **Critical gotcha (you'll hit this):** Quickshell links against Qt at build time. After any `qt6-base` update, `quickshell-git` **must be rebuilt** or it crashes on launch (`built against Qt 6.x but system has 6.y`). Prefer the repo `quickshell` package which the maintainers rebuild, or wire a pacman hook. Enable the LSP by touching an empty `.qmlls.ini` next to `shell.qml` (QS fills it, gitignore it).
>
> **NVIDIA (your RTX 4070):** Quickshell/QtQuick under Wayland wants `QT_QPA_PLATFORM=wayland` and the usual `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `LIBVA_DRIVER_NAME=nvidia`, `NVD_BACKEND=direct` in your Hyprland `env`. Canvas-heavy widgets (the visualizer) are fine on the 4070; the reference repo runs them on a 1070.

### 3.2 The matugen pipeline (exact)

**`~/.config/matugen/config.toml`:**
```toml
[config]
prefer = "darkness"

[settings]
mode = "dark"
scheme = "material"          # or "tonal-spot" / "expressive" / "vibrant" for punchier accents
palette = "material"

[templates.quickshell]
input_path  = "~/.config/matugen/templates/quickshell.json.hbs"
output_path = "~/.config/quickshell/colors/Colors.json"

[templates.hyprland]
input_path  = "~/.config/matugen/templates/hyprland.conf"
output_path = "~/.config/hypr/colors.conf"
post_hook   = "hyprctl reload"

[templates.cava]
input_path  = "~/.config/matugen/templates/cava"
output_path = "~/.config/cava/config"

# + gtk3, gtk4, kitty/ghostty, rofi as needed
```
- **`quickshell.json.hbs`** — emit all 49 M3 roles (copy the list verbatim from Part 1.2 B; the full set is in `dhrruvsharma/shell/matugen/templates/quickshell.json.hbs`). Roles you'll actually lean on for M3 depth: `surface`, `surface_container_lowest…highest` (elevation ladder), `primary`, `on_primary`, `primary_container`, `secondary`, `tertiary`, `outline`, `outline_variant`.
- **`hyprland.conf`** template uses matugen's loop syntax:
  ```
  $image = {{image}}
  <* for name, value in colors *>
  ${{name}} = rgba({{value.default.hex_stripped}}ff)
  <* endfor *>
  ```
- **`cava`** template pins `foreground`/`gradient_color_{1,2,3}` to `{{colors.primary...}}` so the spectrum matches.

**Live reload contract:** `Colors.qml` watches `Colors.json`. `matugen image <wall>` rewrites it → `FileView.onFileChanged` → debounced `reload()` → every `Colors.*` binding updates → QML animates color changes if you put `Behavior on color { ColorAnimation { duration: Motion.standard } }` on the surfaces. **That color Behavior is what makes retheme feel like a Pixel theme swap rather than a snap.**

### 3.3 The morphing pill (exact pattern to reproduce)

Reproduce Ricelin's `pill/shell.qml` + `pill/Pill.qml` structure (Part 1.1). Concrete checklist:

1. **`shell.qml`**: `Variants { model: Quickshell.screens }` twice — once for `reserve`, once for `overlay`. Route `openMon`/`openSurface` state at `ShellRoot`. Expose `IpcHandler { target: "pill"; function media(mon){…} … }` so Hyprland keybinds open surfaces.
2. **`Pill.qml`**: the single `Item`. Define `rest*`/`hover*`/`<surface>W/H` size constants scaled by `s` (`s = monitor.height/1080 * uiScale`). Build the `surfaces` descriptor map. Compute `mode`, `targetSize`, `morphCloseness`. Put `Behavior on width/height/radius` with `Motion.expressiveDefaultSpatial` (bounce) or `morphCurve` (clean expo).
3. **Body**: a `Rectangle` with `radius: morphRadius` (rest 18 → open 22), an M3 elevation via `MultiEffect { shadowEnabled }`, a top sheen hairline, filled with `Colors.surface_container` (rest) → `Colors.surface_container_high` (open). Add `Behavior on color`.
4. **Faces** stacked absolutely, each `opacity: mode === X ? pow(morphCloseness, k) : 0`: `rest` (glyph/clock/`MusicBars`), `hover` (workspaces · clock · status icons), plus one Loader per surface.
5. **Hover/pin**: passive `HoverHandler` (fed from a window-level HoverHandler in `shell.qml` to avoid child-hover flicker) sets `hovered`; passive `TapHandler` toggles `pinned`. `expanded = surfaceOpen || held || hoverLatch`. A 300ms grace timer keeps it open after the pointer leaves until the morph settles.
6. **The "soul bead" (optional but it's the signature micro-animation):** a small `Canvas` bead that glides between the active-workspace dot and whichever status icon you hover, using a sticky `soulTarget` key so crossing gaps doesn't snap it back. This is Ricelin's `Ame`/`soulPoint` system — high polish, add it last.

### 3.4 Full-screen music visualizer (exact)

Copy `dhrruvsharma/shell/quickshell/components/Visualizer.qml` (Part 1.2 A) with two changes: read gradient stops from `Colors.primary/tertiary/secondary`, and gate `running` on a global "viz enabled" flag. Mount two in `shell.qml` (bottom + flipped top). Bind them per-monitor with `Variants` if you're multi-head. Toggle with `qs ipc call visualizer toggle`. For a shader-based alternative (the repo ships `.frag` files: `northern_lights`, `bar_spectrum`, `spectrogram`), use a `ShaderEffect` sampling the cava values as a uniform array — heavier but gorgeous; Canvas is the safe default.

### 3.5 Wallpaper changer + retheme (exact)

1. **`~/.local/bin/setwall`** (the hinge — make it executable):
   ```bash
   #!/usr/bin/env bash
   img="$1"; shift
   swww img "$img" --transition-type "${TRANSITION:-grow}" --transition-fps 60 --transition-duration 1 "$@"
   matugen image "$img"                 # rewrites ALL templates + fires post_hooks
   echo "$img" > "$HOME/.cache/astralis/current-wallpaper"
   ```
2. **`services/Wallpaper.qml`** — `swww query` to detect current, `Process` to call `setwall`, expose `set(path)`. **`WallpaperFavorites.qml`** — persist favorites via `FileView`+`JsonAdapter` (Part 1.2 C). 
3. **Picker** — a pill surface (`surfaces.wallpaper`) OR a full window: `FolderListModel` over `~/Pictures/wallpapers`, thumbnails, `onActivated: Wallpaper.set(path)`. The Ricelin wallpaper surface even adds DuckDuckGo image search on keystroke — optional.
4. **Autostart restore** on login: `swww img "$(cat ~/.cache/astralis/current-wallpaper)"` (+ matugen) in Hyprland `exec-once`.

### 3.6 Hyprland integration (Lua 0.55+)

`exec-once` (in your Lua config, e.g. `hypr/hyprland.lua` autostart table):
```
swww-daemon
qs                                   # launches the shell (shell.qml in ~/.config/quickshell)
wl-paste --watch cliphist store
~/.local/bin/restore-wallpaper.sh    # swww img <cached> ; matugen image <cached>
```
Keybinds → drive the pill/viz/wallpaper via Quickshell IPC (`qs ipc call <target> <fn>`):
```
$mod, M      → qs ipc call pill media
$mod, C      → qs ipc call pill wallpaper
$mod, V      → qs ipc call pill clipboard
$mod, B      → qs ipc call visualizer toggle
$mod, Space  → qs ipc call pill launcher
$mod, L      → qs ipc call pill power        # or your lock
```
Layer rules for blur/animation on the pill + viz namespaces:
```
layerrule = blur, quickshell
layerrule = ignorezero, quickshell
layerrule = animation slide top, pill
```
Reserve the top strip via the `reserve` window's exclusive zone (do **not** also add a Hyprland gap — let the layer-shell exclusive zone do it, so fullscreen retracts cleanly).

### 3.7 Known gotchas (the ones that will actually bite)
- **Binding loops on Loader size.** When a surface's `targetSize` reads `loader.item.implicitHeight`, flip `loader.active = true` *before* the read inside the thunk (Ricelin's `surfaceItem()` idiom) or you get a loop mid-evaluation.
- **Hover flicker** on the centered width-morph: don't put `hoverEnabled` MouseAreas as the hover source on a resizing item. Use a window-level `HoverHandler` in `shell.qml` and feed `pill.hovered`.
- **Content painted over a half-grown pill.** Always gate face opacity on `morphCloseness`, never on a raw timer.
- **Cava on silence.** Set `autosens = 0` with a fixed `sensitivity` and an `active` debounce, or a silent browser holding the sink amplifies the noise floor and the visualizer "plays" on dead silence.
- **`qs` vs `quickshell`.** The binary is `qs` (alias of `quickshell`). `qs ipc call …` is your keybind bridge; `qs -p <file.qml>` runs a standalone window (used for lock/wallpaper-picker-as-process).
- **Multi-monitor `s` scale.** Scale every px by `s = screen.height/1080 * uiScale` so the pill isn't tiny on 1440p/4K.
- **Qt rebuild** after updates (see 3.1).

### 3.8 Notifications — toasts as a pill mode + a center surface

Two pieces, and the island aesthetic decides the first:

**A. Toasts = a `toast` mode of the pill (not a separate corner popup).** Add `toast`
to the mode ladder right beside `osd` (Ricelin already does this). An incoming
notification morphs the pill to show it — icon tile, app eyebrow, summary, body,
action pills, dismiss glyph — gated on `morphCloseness` like every other face. It
auto-expires (~6s; snapshot the deadline **once** so an unrelated notification
replacing the map doesn't drift the timer), **critical urgency persists**, clicking
the body calls `activateNotif` + dismiss. A `+N` counter shows when several are queued.
This is the iOS-island behavior: the pill *becomes* the notification, then morphs back
to the clock. It sits in the mode ladder below `held`, so a pinned/open pill never gets
interrupted by a toast.

**B. Notification center = a surface (`surfaces.notifications`)** holding history:
grouped by `appName`, duplicate summaries/bodies coalesced into a count, sorted newest-
first, criticals separated, per-app expand/clear. Unread dot on the hover-row inbox
icon (`Notifs.unread`). Reuse the latch-once Loader pattern — it's one more `surfaces[]`
entry + one Loader, plus an IPC verb (`qs ipc call pill notifications`).

**Backend — `services/Notifications.qml` singleton wrapping `NotificationServer`:**
```qml
import Quickshell.Services.Notifications
Singleton {
  id: root
  NotificationServer {
    id: server
    keepOnReload: true            // survive shell hot-reload
    actionsSupported: true; bodySupported: true; bodyMarkupSupported: true
    imageSupported: true; actionIconsSupported: true
    onNotification: (n) => { n.tracked = true; /* push to popups + record arrivalMs */ }
  }
  readonly property var tracked: server.trackedNotifications.values
  readonly property int unread: /* count where !seenIds[id] */ 0
  // + groups (app grouping + coalesce), history[], iconFor(n) via Quickshell.iconPath,
  //   removePopup(n), activateNotif(n), dnd
}
```
Read `Notifs.popups` in the pill for the toast face, `Notifs.groups` in the center
surface, `Notifs.unread` for the inbox dot. Wire DND from your flags:
`Binding { target: Notifs; property: "dnd"; value: Flags.dnd }`. Ricelin's
`pill/Singletons/Notifs.qml` + `pill/Toast.qml` are the reference — grouping,
coalescing, critical handling, and icon resolution are all worked out there.

> **The gotcha that silently kills it:** only one process may own the DBus name
> `org.freedesktop.Notifications`. If mako / dunst / swaync is running (check your
> Hyprland `exec-once`!), QS's `NotificationServer` never binds — you get zero
> notifications with no error. Remove every other notification daemon first.

---

## PART 4 — Claude Code build prompt (sub-agent orchestration)

### How to run it
1. `cd ~/.config` and start `claude` (Claude Code). Have this spec file in the repo so agents can read it.
2. Paste the prompt below. It uses an **orchestrator + specialized sub-agents** pattern: the orchestrator sequences dependencies (colors/motion singletons must exist before the pill; the pill scaffold before surfaces) and dispatches independent workstreams (visualizer, wallpaper, Hyprland glue) in parallel via the Task tool.
3. Build **incrementally and test each stage with `qs`** before moving on — a rice is 90% iteration on feel.

### The prompt

```
You are the orchestrator for building "astralis": a Quickshell desktop shell for
Hyprland featuring a single morphing "dynamic island" pill, a full-screen music
visualizer, and a wallpaper changer with live matugen retheme. Material 3
expressive aesthetic, dynamic color from matugen, micro-animations throughout.

Read astralis-quickshell-rice-spec.md in full before doing anything. Architecture,
exact code patterns, and gotchas are all there — follow Part 2 (layout) and Part 3
(implementation) precisely. Reference implementations to study (already understood
in the spec, but consult if stuck): Gakuseei/Ricelin for the pill morph engine,
dhrruvsharma/shell for matugen + full-screen viz + wallpaper.

GROUND RULES
- Target: Arch, Hyprland 0.55 (Lua config), Quickshell (release), Qt6, matugen, swww,
  cava, playerctl. NVIDIA RTX 4070 (Wayland env vars per spec 3.1).
- NEVER hard-code a color. Every color reads from the Colors singleton (M3 tokens).
- Every animation duration/curve reads from the Motion singleton. One reduce-motion knob.
- Build in stages; after each stage, produce a `qs` command I can run to verify it,
  and STOP for my confirmation before the next stage. This is a feel-driven project.
- Use qmldir module singletons. Add an empty .qmlls.ini next to shell.qml. gitignore
  Colors.json, .qmlls.ini, .cache.

MODEL ASSIGNMENT: run agents C (core-shell), D (pill-engine), E (pill-surfaces),
and G (wallpaper) on Claude Fable 5 (model: claude-fable-5). Leave the other agents
and yourself as the orchestrator on the default model.

DISPATCH THESE SUB-AGENTS (use the Task tool; run independent ones in parallel):

Agent A — "theming-pipeline":
  Build the matugen pipeline (spec 3.2): config.toml, quickshell.json.hbs (all 49 M3
  roles), hyprland.conf + cava + kitty/ghostty + rofi templates, and colors/Colors.qml
  (FileView live reload with fallbacks) + colors/qmldir. Deliver a test: run
  `matugen image <wall>` and confirm Colors.json regenerates with valid hex.

Agent B — "design-tokens":
  Build config/AppearanceConfig.qml + Appearance.qml and services/Motion.qml exactly
  per spec 1.2D and 1.1E: M3 curves (emphasized, standard, expressiveDefaultSpatial
  with overshoot, expressiveEffects), durations, rounding/spacing tokens, and the
  morph curve [0.16,1,0.3,1] with a reduce-motion mult. No UI yet.

Agent C — "core-shell": (depends on A + B) [model: claude-fable-5]
  Scaffold shell.qml (ShellRoot, Variants over screens for reserve + overlay layer-shell
  windows per spec 1.1A/B), window masking (pill rect vs full vs hidden), the
  window-level HoverHandler feeding the pill, and IpcHandler stubs for pill/visualizer/
  wallpaper. Empty pill placeholder that just shows the rest clock. Verify: pill appears
  top-center, clicks pass through when collapsed, windows tile below it.

Agent D — "pill-engine": (depends on C) [model: claude-fable-5]
  Implement pill/Pill.qml as the single morphing Item per spec 1.1C/D/F and 3.3: the
  `surfaces` descriptor map, mode→targetSize, morphCloseness, Behavior on width/height/
  radius/color using Motion. Rest face (clock + MusicBars) and hover face (workspaces ·
  clock · status icons: wifi, battery, volume, notifs, settings, power). Latch-once
  Loaders. Verify: hover expands with a bouncy M3 morph; icons fade in on morphCloseness.

Agent E — "pill-surfaces": (depends on D) [model: claude-fable-5]
  Build the morphing surfaces as latch-once Loaders reading morphCloseness: Media
  (MPRIS via Players singleton), Calendar, Mixer (PipeWire), Wallpaper picker, Power,
  Link (net/bt), Launcher, Clipboard. Shared PillSurface chrome (header + back). Each
  = one surfaces[] entry + one Loader. Verify each opens/morphs/closes via IPC.

Agent F — "audio-viz": (depends on A + B, parallel with D/E)
  services/Cava.qml (sink-monitor spectrum, autosens=0 + active debounce, spec 1.1G),
  pill/MusicBars.qml (rest-pill bars), and modules/visualizer/Visualizer.qml (full-screen
  Canvas mountain-wave on WlrLayer.Bottom, matugen gradient, top+bottom pair, smoothing,
  spec 1.2A/3.4). Toggle via IPC. Verify: play music → rest pill morphs clock→bars AND
  full-screen wave animates; both recolor on retheme.

Agent G — "wallpaper": (depends on A, parallel) [model: claude-fable-5]
  ~/.local/bin/setwall (swww + matugen, spec 3.5), restore-wallpaper.sh, services/
  Wallpaper.qml + WallpaperFavorites.qml, and the wallpaper picker surface/window
  (FolderListModel over ~/Pictures/wallpapers, favorites). Verify: pick wallpaper →
  swww crossfade + whole shell recolors live in one action.

Agent I — "notifications": (depends on D, parallel with E/F/G) [model: claude-fable-5]
  Build services/Notifications.qml wrapping NotificationServer (keepOnReload, actions/
  body/markup/image supported), with app grouping, duplicate coalescing, history,
  unread, iconFor, removePopup/activateNotif, dnd (spec 3.8). Add the `toast` face to
  Pill.qml's mode ladder (auto-expire w/ snapshotted deadline, criticals persist, +N
  counter, below `held`), the inbox unread dot on the hover row, and a notification-
  center surface (surfaces.notifications) with grouped/coalesced history + clear, plus
  its IPC verb. FIRST verify no other notification daemon (mako/dunst/swaync) is in my
  exec-once — remove it, or the server won't bind. Verify: `notify-send` → pill morphs
  to a toast, expires; a critical persists; center surface lists grouped history.

Agent H — "hypr-glue": (depends on C, last)
  Add to my Hyprland Lua config: exec-once (swww-daemon, qs, cliphist, restore-wallpaper;
  and confirm NO mako/dunst/swaync), keybinds bridging to `qs ipc call …` including
  notifications center (spec 3.6/3.8), and layerrules (blur/ignorezero/animation) for
  the quickshell + pill + visualizer namespaces. Reserve top strip via the layer-shell
  exclusive zone only, not Hyprland gaps.

ORCHESTRATION ORDER: A+B (parallel) → C → D → {E, F, G, I in parallel} → H → integration
pass. After H, do a full-desktop smoke test checklist and list anything unpolished
(soul-bead micro-animation, OSD/toast polish, blur tuning) as follow-ups. Keep commits
small and per-stage. Do not gold-plate before the core morph feels right.
```

---

### Quick reference — the two repos on disk
- **Pill morph engine:** `Gakuseei/Ricelin` → `configs/quickshell/pill/{shell,Pill,PillSurface,MusicBars}.qml`, `pill/Singletons/{Motion,Cava,Players}.qml`
- **Matugen + viz + wallpaper:** `dhrruvsharma/shell` → `matugen/`, `quickshell/colors/Colors.qml`, `quickshell/components/Visualizer.qml`, `quickshell/config/AppearanceConfig.qml`, `quickshell/modules/wallpaper/`, `quickshell/services/{Cava,WallpaperFavorites}.qml`

Clone both to read the full source alongside the build — they are the answer key.
```bash
git clone https://github.com/Gakuseei/Ricelin
git clone https://github.com/dhrruvsharma/shell
```
