# ASTRALIS — Hyprland Integration Addendum
### The pill ↔ compositor bridge (supersedes the thin "hypr-glue" agent)

> Standalone add-on to `astralis-quickshell-rice-spec.md`. The main spec covered
> launching the shell + a few IPC keybinds, but the actual pill↔Hyprland bridge —
> workspaces, per-monitor focus, fullscreen retract, special-workspace trays, the
> event-driven refresh model, and the keybind transport — is a whole subsystem. This
> replaces Agent H with a proper "hypr-bridge" agent and documents every piece.
>
> Reference (traced on disk): `Gakuseei/Ricelin` → `configs/quickshell/pill/{shell,
> Workspaces,MinimizedTray}.qml`, `pill/Singletons/Workspacerules.qml`, and
> `configs/hypr/{hyprland.lua,modules/binds.lua,scripts/open-surface.sh,scripts/
> special-toggle.sh}`.

---

## PART A — Implementation doc

### A.1 The bridge — `Quickshell.Hyprland`
Everything flows through one QML service. The models you actually consume:
- `Hyprland.workspaces.values` — all workspaces (`.id`, `.name`, `.monitor`, `.lastIpcObject`)
- `Hyprland.monitors.values` — monitors (`.name`, `.focused`, `.activeWorkspace`)
- `Hyprland.toplevels.values` — windows (`.workspace`, `.wayland.appId`, `.lastIpcObject.class`, `.title`)
- `Hyprland.focusedMonitor` / `Hyprland.focusedWorkspace` / `Hyprland.activeToplevel`
- `Hyprland.dispatch("<dispatcher> <args>")` — fire any Hyprland dispatcher from QML
- `Hyprland.refreshMonitors()/refreshWorkspaces()/refreshToplevels()` — force model resync
- `Hyprland.onRawEvent(event)` — the raw IPC event stream (`event.name`, `event.data`)

`dispatch()` takes a **vanilla dispatcher string** — portable, no plugin needed:
```qml
Hyprland.dispatch('workspace 3')
Hyprland.dispatch('movetoworkspacesilent special:minimized,address:0x' + addr)
Hyprland.dispatch('focusworkspaceoncurrentmonitor 3')
```
> Ricelin uses the `hyprland-lua` plugin's `hl.dsp.focus({workspace="3"})` form because
> its whole config is Lua. If your Lua config loads that plugin you can mirror it; if
> not, use the vanilla strings above. Both reach the same dispatchers. Pick one and be
> consistent — the agent defaults to vanilla for portability.

### A.2 Event-driven refresh — the perf-critical whitelist
The pill must **not** re-query Hyprland on every event. Each full refresh is three IPC
round-trips (`refreshMonitors + refreshWorkspaces + refreshToplevels`); window drags,
resizes, and title spam fire dozens per second. Subscribe to `onRawEvent` but only
refresh on events that can actually change what the pill renders:
```qml
readonly property var refreshEvents: ({
  workspace:true, workspacev2:true, createworkspacev2:true, destroyworkspacev2:true,
  moveworkspacev2:true, renameworkspace:true, activespecial:true,
  focusedmon:true, focusedmonv2:true, openwindow:true, closewindow:true,
  movewindowv2:true, fullscreen:true,
  monitoradded:true, monitoraddedv2:true, monitorremoved:true
})
Connections {
  target: Hyprland
  function onRawEvent(e) { if (root.refreshEvents[e.name]) root.refresh() }
}
function refresh() { Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels() }
```
Skipping this is the difference between a smooth pill and one that stutters whenever you
drag a window.

### A.3 Per-monitor focus model
The pill runs once per screen (`Variants { model: Quickshell.screens }`). Each instance
knows its own `screenName`; the shell tracks which one is *focused* so an empty monitor
argument resolves correctly and a keybind opens the surface on the screen you're on —
one IPC call instead of the keybind script doing its own `hyprctl + jq` round-trip:
```qml
function toggleSurface(mon, surface) {
  if (!mon || mon.length === 0)
    mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  if (root.openMon === mon && root.openSurface === surface) { root.close(); return }
  root.openMon = mon; root.openSurface = surface
}
```

### A.4 Workspaces widget (`pill/Workspaces.qml`)
The hover face's workspace dots — the most visible bit of Hyprland integration.
- **Range** comes from `hyprctl workspacerules -j` (a `Workspacerules` singleton, A.4.1)
  so every *assigned* workspace shows as a dot even before it's visited (multi-monitor
  splits from `monitors.lua`). No rules → fall back to live workspaces on this monitor
  plus the active one, so dots appear/grow as you visit new workspaces.
- **Active dot** tracks `monitor.activeWorkspace.name`; it's a wider filled "stick" in
  `Colors.primary`, the rest are small dim dots in `Colors.on_surface_variant`,
  brightening on hover.
- **Click → focus** via `Hyprland.dispatch('workspace ' + wsName)` (or the Lua form).
- **Width Behavior** on the active stick uses `Motion.fast` + standard easing so the
  active indicator glides between slots. (Optional: a "soul bead" that travels to
  `activeDotPoint` — computed from *end-state* slot widths so it lands where the dot
  settles instead of chasing the width animation.)

**A.4.1 `services/Workspacerules.qml`** — persistent workspace→monitor map:
```qml
pragma Singleton
Singleton {
  property var byMonitor: ({})
  Process {
    id: proc; command: ["hyprctl", "workspacerules", "-j"]
    stdout: StdioCollector { onStreamFinished: {
      let map = {}; try { for (const r of JSON.parse(text)) {
        const ws = parseInt(r.workspaceString), mon = r.monitor
        if (!mon || isNaN(ws)) continue; (map[mon] ??= []).push(ws)
      } } catch (e) { return }
      for (const k in map) map[k].sort((a,b)=>a-b); byMonitor = map
    }}
  }
  Connections { target: Hyprland; function onRawEvent(e){ if (e.name==="configreloaded") proc.running=true } }
  Component.onCompleted: proc.running = true
}
```

### A.5 Fullscreen retract
When a real fullscreen window is on this monitor's active workspace, the pill slides off
the top edge and the whole overlay layer goes click-through so fullscreen content owns
the screen. Read it per-monitor from `activeWorkspace.lastIpcObject.hasfullscreen`:
```qml
readonly property bool monFullscreen: {
  for (const m of Hyprland.monitors.values)
    if (m.name === screenName) { const o = m.activeWorkspace?.lastIpcObject; return !!(o && o.hasfullscreen) }
  return false
}
onMonFullscreenChanged: if (monFullscreen) { if (root.openMon===screenName) root.close(); pill.retracted = true }
```
Tie `retracted` to the pill's `y` (animate to `-height - topGap`) and to the window mask
(→ `hiddenRegion`). Suppress *maximize* globally in your window rules so only true
fullscreen flips this. (Main-spec masking: collapsed→pill rect, modal→full, fullscreen→hidden.)

### A.6 Optional pill faces from Hyprland
Cheap wins the main spec doesn't mention:
- **Focused-window title / app** in the hover face: `Hyprland.activeToplevel?.title` and
  icon via class→desktop-entry resolution (A.7). Nice as a centered eyebrow when hovered.
- **Submap / resize-mode indicator**: `onRawEvent` fires `submap` with `event.data` = the
  submap name (empty = default). Track it and show a small mode chip ("resize", "gaps")
  in the pill while a submap is active — great for a Pixel-style modal affordance.

### A.7 Minimized + special-workspace tray (`pill/MinimizedTray.qml`)
Windows parked on `special:minimized` (your Super+M stash) render as a row of app-icon
chips in a pill face; clicking restores to *this pill's monitor's* active workspace:
```qml
readonly property var items: Hyprland.toplevels.values.filter(t => t.workspace?.name === "special:minimized")
function restoreWorkspace() {
  for (const m of Hyprland.monitors.values)
    if (m.name === screenName && m.activeWorkspace) return m.activeWorkspace.id
  return Hyprland.focusedWorkspace?.id ?? 1
}
// icon: match toplevel.lastIpcObject.class (or wayland.appId) → DesktopEntries → Quickshell.iconPath
onClicked: Hyprland.dispatch('movetoworkspacesilent ' + restoreWorkspace() + ',address:0x' + addr)
```
The class often differs from the icon-theme name, so resolve `class → DesktopEntries.applications`
first, then fall back to `Quickshell.iconPath(class, "application-x-executable")`.

### A.8 The keybind transport (compositor → pill)
Three mechanisms, each for a different job:

**1. Open/toggle surfaces — Quickshell IPC.** The keybind script is one line:
```sh
# ~/.config/hypr/scripts/open-surface.sh
qs -c <shell-name> ipc call pill "$1" ""
```
```lua
-- binds (Lua config)
hl.bind(mod.." + Space", hl.dsp.exec_cmd(HOME.."/.config/hypr/scripts/open-surface.sh launcher"))
hl.bind(mod.." + V",     hl.dsp.exec_cmd(HOME.."/.config/hypr/scripts/open-surface.sh clipboard"))
hl.bind(mod.." + C",     hl.dsp.exec_cmd(HOME.."/.config/hypr/scripts/open-surface.sh wallpaper"))
hl.bind(mod.." + N",     hl.dsp.exec_cmd(HOME.."/.config/hypr/scripts/open-surface.sh notifications"))
```
`-c <shell-name>` selects your Quickshell config (name it, e.g. `astralis`). The pill's
`IpcHandler { target: "pill"; function launcher(){…} … }` receives it.

**2. Media / global actions — Hyprland `global` dispatcher → `GlobalShortcut`.** Cleaner
than IPC for hardware keys because it works locked and needs no script:
```lua
hl.bind("XF86AudioPlay", hl.dsp.global("quickshell:mediaToggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.global("quickshell:mediaNext"),   { locked = true })
```
```qml
// QML side
GlobalShortcut { appid: "quickshell"; name: "mediaToggle"; onPressed: Players.active?.togglePlaying() }
GlobalShortcut { appid: "quickshell"; name: "mediaNext";   onPressed: Players.active?.next() }
```

**3. Special-workspace send/retrieve — one script, one key (`special-toggle.sh`).** From a
normal workspace the focused window drops into `special:<name>`; if it's already there it
comes back to the monitor's active workspace. Same shape for stash / private / minimized.

### A.9 Compositor-side rules (Hyprland config)
```
# autostart (Lua exec-once table): swww-daemon; qs -c astralis; cliphist watch; restore-wallpaper
layerrule = blur, astralis
layerrule = ignorezero, astralis          # don't blur fully-transparent overlay regions
layerrule = animation slide top, astralis # pill enters/retracts from the top edge
windowrule = suppressevent maximize, class:.*   # so only true fullscreen retracts the pill
```
- Namespace your layer windows (the `WlrLayer` `namespace`/`Quickshell` object name) as
  `astralis` so these `layerrule`s target only the shell.
- Reserve the top strip via the `reserve` window's **exclusive zone**, not a Hyprland
  gap, so fullscreen reclaims it cleanly (main spec 1.1A).

### A.10 Gotchas specific to the bridge
- **Refresh whitelist is mandatory** (A.2) — without it the pill stutters on window drag.
- **`lastIpcObject` can be stale** right after an event; the whitelist + explicit
  `refresh()` before reading `hasfullscreen`/`class` keeps it current.
- **`-c <name>` must match** the shell config name in all three of: `qs -c <name>` launch,
  `qs -c <name> ipc call …` scripts, and the `layerrule` namespace. Mismatch = silent no-op.
- **Monitor hotplug**: include `monitoradded*/monitorremoved` in the whitelist or dots
  vanish on a screen you plug in until the next unrelated event.
- **Special-workspace names** must match between `special-toggle.sh`, the `MinimizedTray`
  filter string, and your binds (`special:minimized`, `special:stash`, …).

---

## PART B — Paste into Claude Code (replaces Agent H)

```
This REPLACES Agent H ("hypr-glue") in the astralis build with a proper compositor-bridge
agent. Read astralis-hypr-integration-addendum.md Part A in full first. It DEPENDS ON
Agent C (core-shell) and Agent D (pill-engine); run it after D, in parallel with E/F/G/I.
Run on Claude Fable 5 (model: claude-fable-5) — it's heavy shell.qml + Pill.qml QML work,
same as C/D. Stop for my verification when done.

Agent H — "hypr-bridge": [model: claude-fable-5]
  Wire the pill to Hyprland via Quickshell.Hyprland. All colors from the Colors singleton,
  all durations/curves from Motion. Build:

  1. Event-driven refresh (spec A.2): in shell.qml, a refreshEvents whitelist +
     Connections onRawEvent → refresh() calling refreshMonitors/Workspaces/Toplevels.
     Do NOT refresh on unwhitelisted events (drag/resize/title spam).

  2. Per-monitor focus (A.3): toggleSurface(mon,surface) resolving empty mon →
     Hyprland.focusedMonitor.name; each pill instance carries its screenName.

  3. services/Workspacerules.qml (A.4.1): parse `hyprctl workspacerules -j` into
     byMonitor, re-read on configreloaded.

  4. pill/Workspaces.qml (A.4): per-monitor dots; range from Workspacerules with live
     fallback; active dot = wider Colors.primary stick tracking monitor.activeWorkspace;
     others dim Colors.on_surface_variant brightening on hover; click → Hyprland.dispatch
     ('workspace '+name); active-stick width Behavior on Motion.fast. Mount it in the
     pill's hover face.

  5. Fullscreen retract (A.5): per-monitor monFullscreen from activeWorkspace.lastIpcObject
     .hasfullscreen → animate pill y off top edge + mask → hiddenRegion + close any open
     surface. Add `windowrule = suppressevent maximize, class:.*` so only true fullscreen
     triggers it.

  6. pill/MinimizedTray.qml (A.7): row of icon chips for toplevels on special:minimized;
     class→DesktopEntries→Quickshell.iconPath icon resolution; click → movetoworkspacesilent
     back to this monitor's active workspace. Mount in the hover face (only when count>0).

  7. Keybind transport (A.8): ~/.config/hypr/scripts/open-surface.sh
     (`qs -c astralis ipc call pill "$1" ""`); IpcHandler funcs on the pill for every
     surface incl. notifications; GlobalShortcut handlers (appid "quickshell") for
     mediaToggle/Next/Prev wired to the Players singleton; special-toggle.sh for
     stash/private/minimized send-retrieve.

  8. Hyprland Lua config (A.9): exec-once (swww-daemon, qs -c astralis, cliphist watch,
     restore-wallpaper — and confirm NO other notification daemon); binds → open-surface.sh
     + global media dispatchers + special toggles; layerrules (blur, ignorezero, animation
     slide top) on the `astralis` namespace; reserve top strip via exclusive zone only.

  Use VANILLA Hyprland dispatcher strings via Hyprland.dispatch() (not a Lua plugin's
  hl.dsp form) unless I say otherwise. Keep `-c astralis` consistent across launch, ipc
  scripts, and the layerrule namespace.

  VERIFY: workspace dots appear per-monitor and switch on click; the active stick glides;
  opening a surface via keybind lands on the focused monitor; going fullscreen retracts the
  pill and makes the layer click-through, restoring on exit; Super+M stashes a window and it
  shows as a tray chip that restores on click; media keys work locked; dragging a window
  produces NO pill stutter (whitelist working).
```

---

### Decisions for you
- **Dispatcher form:** I defaulted the agent to vanilla `Hyprland.dispatch("workspace 3")`
  for portability. If your Lua config already loads the `hyprland-lua` plugin (the
  `hl.dsp.focus{…}` style Ricelin uses), say so and I'll switch the agent to match it.
- **What to show in the resting/hover pill:** dots-only (Ricelin) is clean. If you want the
  focused-window title or a submap/resize-mode chip (A.6), tell me and I'll fold those faces
  into the agent — they're cheap but they change the pill's information density.
