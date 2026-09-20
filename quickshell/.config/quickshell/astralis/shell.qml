//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "services"
import "config"
import "pill"
import "modules/visualizer"
import "modules/wallpaper"
import "modules/powermenu"
import "lock"

/**
 * astralis — dynamic-island core shell. Each monitor carries two layer-shell
 * windows (ported from Gakuseei/Ricelin pill/shell.qml):
 *
 *  - `reserve` (astralis-reserve, WlrLayer.Top) — a zero-content strip that
 *    only claims an exclusive zone the height of the rest pill + top gap, so
 *    tiled windows always sit below the pill even while it is expanded or a
 *    surface is open. The pill itself never reserves beyond rest height.
 *  - `overlay` (astralis-pill, WlrLayer.Overlay) — a full-screen transparent
 *    window hosting the single morphing pill anchored top-centre. The pill
 *    grows in place; it is never re-parented and never moves windows.
 *
 * Input is routed by the window mask. Collapsed → the mask is the pill rect
 * only, so the rest of the screen clicks through to windows. Expanded /
 * surface open (`modal`) → the mask is cleared to full screen so a backdrop
 * press dismisses and Escape closes. Fullscreen window on this monitor → the
 * mask is hidden and the pill retracts off the top edge.
 */
ShellRoot {
    id: root

    property string openMon: ""
    property string openSurface: ""

    /** Full-screen music visualizer pair (bottom + flipped top) per monitor. */
    property bool vizEnabled: false

    /** Standalone full-width wallpaper carousel overlay (modules/wallpaper). */
    property bool wallpaperOpen: false

    /** Standalone full-screen session/power menu overlay (modules/powermenu). */
    property bool powerMenuOpen: false

    /**
     * Force-loads the Hypridle singleton at startup so it writes
     * ~/.config/hypr/hypridle.conf from the IdleLock settings and starts the
     * hypridle daemon on login (and rewrites+restarts it whenever those
     * settings change). Singletons are lazy — without this reference nothing
     * would instantiate it.
     */
    readonly property var idleDaemon: Hypridle

    /**
     * QS 0.3.0-git gotcha: calling Hyprland.refreshMonitors() (especially early,
     * during the startup race) PERMANENTLY empties Hyprland.monitors — the model
     * then never populates, so focusedMonitor stays null and per-monitor focus /
     * fullscreen reads break. The monitor model auto-populates and self-maintains
     * over the event socket on its own (incl. hotplug), so we must NOT refresh it
     * manually. Workspaces/toplevels still need the explicit re-sync (keeps
     * lastIpcObject fresh for hasfullscreen etc.).
     */
    function refresh() {
        syncDebounce.needWs = true;
        syncDebounce.needTop = true;
        syncDebounce.restart();
    }

    Component.onCompleted: refresh()

    /**
     * Coalesce a burst of Hyprland events into a single model re-sync. A single
     * workspace switch or window spawn emits several raw events back-to-back;
     * doing refreshWorkspaces()/refreshToplevels() (an IPC round-trip each) per
     * event congests the event loop and visibly delays the OSD flash and
     * notification render. Collapse the burst into one re-sync on the next tick,
     * and only re-pull toplevels when a window event actually changed them —
     * a pure workspace switch leaves the toplevel set untouched, so it skips
     * that round-trip entirely.
     */
    Timer {
        id: syncDebounce
        interval: 16
        property bool needWs: false
        property bool needTop: false
        onTriggered: {
            if (needWs) Hyprland.refreshWorkspaces();
            if (needTop) Hyprland.refreshToplevels();
            needWs = false;
            needTop = false;
        }
    }

    /**
     * Workspace/monitor/fullscreen events move the pill's dots, occupancy and
     * fullscreen retract but not the toplevel set, so they only re-pull
     * workspaces. Window events also shift per-workspace occupancy, so they
     * re-pull both. Everything else (drags, resizes, title spam) is ignored.
     */
    readonly property var wsEvents: ({
        workspace: true, workspacev2: true,
        createworkspace: true, createworkspacev2: true,
        destroyworkspace: true, destroyworkspacev2: true,
        moveworkspace: true, moveworkspacev2: true,
        renameworkspace: true, activespecial: true,
        focusedmon: true, focusedmonv2: true,
        fullscreen: true,
        monitoradded: true, monitoraddedv2: true, monitorremoved: true
    })
    readonly property var winEvents: ({
        openwindow: true, closewindow: true,
        movewindow: true, movewindowv2: true
    })

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.winEvents[event.name]) {
                syncDebounce.needWs = true;
                syncDebounce.needTop = true;
                syncDebounce.restart();
            } else if (root.wsEvents[event.name]) {
                syncDebounce.needWs = true;
                syncDebounce.restart();
            }
        }
    }

    /**
     * An empty monitor argument resolves to the focused monitor here, so a
     * keybind opens the surface on the screen you're on with one IPC call.
     * Toggling the already-open surface closes it.
     */
    function toggleSurface(mon, surface) {
        if (!mon || mon.length === 0)
            mon = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        if (root.openMon === mon && root.openSurface === surface) {
            root.close();
            return;
        }
        root.openMon = mon;
        root.openSurface = surface;
    }

    function close() {
        root.openMon = "";
        root.openSurface = "";
    }

    /**
     * Keybind transport. Surfaces themselves are later stages; opening a
     * not-yet-built surface just sets openSurface, which the placeholder pill
     * shows as its name.
     */
    IpcHandler {
        target: "pill"
        function mixer(mon: string): void { root.toggleSurface(mon, "mixer"); }
        function calendar(mon: string): void { root.toggleSurface(mon, "calendar"); }
        function launcher(mon: string): void { root.toggleSurface(mon, "launcher"); }
        function link(mon: string): void { root.toggleSurface(mon, "link"); }
        function clipboard(mon: string): void { root.toggleSurface(mon, "clipboard"); }

        /**
         * The wallpaper picker is NOT a pill surface: it is the standalone
         * full-width carousel overlay (modules/wallpaper/WallpaperPicker.qml).
         * Kept on the `pill` target so the existing Super+C keybind
         * (`ipc call pill wallpaper ""`) keeps working.
         */
        function wallpaper(mon: string): void { root.wallpaperOpen = !root.wallpaperOpen; }
        function media(mon: string): void { root.toggleSurface(mon, "media"); }
        function notifications(mon: string): void { root.toggleSurface(mon, "notifications"); }
        function settings(mon: string): void { root.toggleSurface(mon, "settings"); }
        function sysmon(mon: string): void { root.toggleSurface(mon, "sysmon"); }
        function system(mon: string): void { root.toggleSurface(mon, "sysmon"); }
        function recorder(mon: string): void { root.toggleSurface(mon, "recorder"); }
        function hide(): void { root.close(); }

        /** Opens any surface by name; dev and scripting door. */
        function page(mon: string, name: string): void { root.toggleSurface(mon, name); }
    }

    /** Full-screen visualizer toggle: `qs -c astralis ipc call visualizer toggle`. */
    IpcHandler {
        target: "visualizer"
        function toggle(): void { root.vizEnabled = !root.vizEnabled; }
        function on(): void { root.vizEnabled = true; }
        function off(): void { root.vizEnabled = false; }
    }

    /**
     * Full-screen session/power menu (modules/powermenu/PowerMenu.qml) — its
     * own overlay. The old in-pill power dock (pill/surfaces/Power.qml) has been
     * removed entirely; this is the only power menu now, opened by the pill's
     * power icon, `Super+L`, or `qs -c astralis ipc call power toggle`.
     */
    IpcHandler {
        target: "power"
        function toggle(): void { root.powerMenuOpen = !root.powerMenuOpen; }
        function show(): void { root.powerMenuOpen = true; }
        function hide(): void { root.powerMenuOpen = false; }
    }

    /**
     * Screen recorder (services/ScreenRec.qml → gpu-screen-recorder /
     * wl-screenrec / wf-recorder). A keybind can start a take without ever
     * opening the 録 surface — `toggle` is the one to bind, since the same key
     * then stops it. The surface itself is on the `pill` target above
     * (`ipc call pill recorder ""`).
     *
     * Starting always closes an open surface first: the pill is an overlay
     * layer, so it would otherwise be baked into the recording, and the
     * region/window pickers need the pointer.
     */
    IpcHandler {
        target: "recorder"
        // All four start a take when idle and stop the running one otherwise,
        // so a single key both arms and ends a recording.
        function toggle(): void { root.close(); ScreenRec.toggle("screen"); }
        function screen(): void { root.close(); ScreenRec.toggle("screen"); }
        function window(): void { root.close(); ScreenRec.toggle("window"); }
        function region(): void { root.close(); ScreenRec.toggle("region"); }
        function stop(): void { ScreenRec.stop(); }
        function pause(): void { ScreenRec.togglePause(); }

        // State is read back as functions, not exposed properties: IpcHandler
        // warns once per property on every launch about the `…Changed` signals
        // it cannot expose, and `ipc call` reads these just as well.
        function isRecording(): bool { return ScreenRec.recording; }
        function elapsed(): int { return ScreenRec.elapsed; }
        function lastFile(): string { return ScreenRec.lastFile; }
        function backend(): string { return ScreenRec.backend; }
    }

    /**
     * Hardware brightness keys route here (keybinds.lua:
     * `qs -c astralis ipc call brightness change -- -0.05`) so the change goes
     * through the Backlight singleton and flashes the OSD, instead of a raw
     * brightnessctl that the shell never sees. Negative deltas need `--` before
     * them on the `qs ipc` CLI.
     */
    IpcHandler {
        target: "brightness"
        function change(delta: real): void { Backlight.change(delta); }
        function set(v: real): void { Backlight.set(v); }
    }

    /**
     * XF86AudioMicMute routes here (keybinds.lua:
     * `qs -c astralis ipc call mic toggle`) so the mute lands on the Pipewire
     * default AUDIO SOURCE through the shell — the Osd watches the same node
     * and flashes the mic state. Guarded: no default source (or its audio not
     * yet bound) is a silent no-op.
     */
    IpcHandler {
        target: "mic"
        function toggle(): void {
            var src = Pipewire.defaultAudioSource;
            if (src && src.audio)
                src.audio.muted = !src.audio.muted;
        }
        function setMuted(m: bool): void {
            var src = Pipewire.defaultAudioSource;
            if (src && src.audio)
                src.audio.muted = m;
        }
    }

    /** A Pipewire node's audio props are only live while tracked (Osd.qml pattern). */
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSource].filter(Boolean)
    }

    /**
     * Media keys land here via Hyprland's `global` dispatcher
     * (`hl.dsp.global("quickshell:mediaToggle")` etc. in keybinds.lua) —
     * cleaner than IPC for hardware keys: works locked, no script. Players
     * self-guards when no MPRIS player is around.
     */
    GlobalShortcut { appid: "quickshell"; name: "mediaToggle"; onPressed: Players.togglePlaying() }
    GlobalShortcut { appid: "quickshell"; name: "mediaNext";   onPressed: Players.next() }
    GlobalShortcut { appid: "quickshell"; name: "mediaPrev";   onPressed: Players.previous() }

    // ── visualizer: mirrored mountain-wave pair, created only while enabled ─
    Variants {
        model: Quickshell.screens

        Scope {
            id: vizScope
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1

            Loader {
                active: root.vizEnabled
                sourceComponent: Visualizer {
                    screen: vizScope.modelData
                    s: vizScope.s
                    anchorBottom: true
                }
            }

            Loader {
                active: root.vizEnabled
                sourceComponent: Visualizer {
                    screen: vizScope.modelData
                    s: vizScope.s
                    anchorBottom: false
                }
            }
        }
    }

    // ── wallpaper picker: standalone full-width carousel overlay ───────────
    Variants {
        model: Quickshell.screens

        Scope {
            id: wpScope
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1

            WallpaperPicker {
                screen: wpScope.modelData
                s: wpScope.s
                // Also Overlay layer — force it shut while locked so it can't
                // bleed over the session lock either. (#3)
                open: root.wallpaperOpen && !lockScope.locked
                onRequestClose: root.wallpaperOpen = false
            }
        }
    }

    // ── power menu: standalone full-screen session overlay ─────────────────
    Variants {
        model: Quickshell.screens

        Scope {
            id: pmScope
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1

            PowerMenu {
                screen: pmScope.modelData
                s: pmScope.s
                // Overlay layer + it owns the Lock tile that fires the lock —
                // force it shut while locked so it never lingers over the lock. (#3)
                open: root.powerMenuOpen && !lockScope.locked
                onRequestClose: root.powerMenuOpen = false
            }
        }
    }

    // ── lockscreen: real WlSessionLock + PAM (lock/Lock.qml) ───────────────
    // Driven by logind: `loginctl lock-session` (powermenu Lock tile, idle
    // daemons) locks; PAM success unlocks. Also `ipc call lock lock`.
    // `lockScope.locked` is read by the Overlay-layer windows below to hide
    // themselves while locked (see #3: the pill/Ame bleeds over the session
    // lock otherwise, since Overlay layer-shell renders above the lock surface).
    Lock { id: lockScope }

    // ── reserve: exclusive-zone spacer only ────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserve
            required property var modelData
            // 1080-relative screen scale × the user's UI-scale preference
            // (Settings → Appearance → Scale, persisted in Flags.uiScale).
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            readonly property real topGap: 8 * s
            readonly property real restHeight: 38 * s

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: restHeight + topGap
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "astralis-reserve"

            anchors { top: true; left: true; right: true }
            implicitHeight: restHeight + topGap

            mask: emptyReserve
            Region { id: emptyReserve }
        }
    }

    // ── overlay: the morphing pill + surfaces ──────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1
            readonly property real topGap: 8 * s

            readonly property string surface: root.openMon === modelData.name ? root.openSurface : ""
            readonly property bool surfaceOpen: surface.length > 0
            readonly property bool modal: surfaceOpen || pill.held

            /**
             * True while this monitor's active workspace holds a real
             * fullscreen window. The pill then retracts off the top edge and
             * the whole layer becomes click-through so fullscreen content owns
             * the screen.
             */
            // This monitor's Hyprland object, resolved by name in one cached
            // binding so the scan over Hyprland.monitors.values runs once per
            // monitor-model change rather than inside monFullscreen on every
            // IPC tick; monFullscreen then keys off the monitor's own live
            // activeWorkspace/lastIpcObject without re-scanning.
            readonly property var hMonitor: {
                var mons = Hyprland.monitors.values;
                for (var i = 0; i < mons.length; i++)
                    if (mons[i] && mons[i].name === modelData.name)
                        return mons[i];
                return null;
            }

            // hasFullscreen, not lastIpcObject.hasfullscreen: the IPC object is
            // empty {} on Hyprland 0.56.
            readonly property bool monFullscreen: {
                var ws = hMonitor ? hMonitor.activeWorkspace : null;
                return ws ? !!ws.hasFullscreen : false;
            }

            onMonFullscreenChanged: if (monFullscreen) {
                if (root.openMon === modelData.name) root.close();
                pill.pinned = false;
            }

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: surfaceOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
            WlrLayershell.namespace: "astralis-pill"

            // Hide the whole pill layer (and its Ame bead) while the session is
            // locked — an Overlay layer-shell surface renders ABOVE the
            // WlSessionLock surface, so the pill would otherwise bleed a stray
            // ring onto the lock. Unmapping the window is the clean fix; it
            // remaps the instant PAM releases the lock. (#3)
            visible: !lockScope.locked

            anchors { top: true; left: true; right: true; bottom: true }

            /**
             * The mask is the crux: collapsed pill clicks through, expanded /
             * modal catches clicks, fullscreen hides entirely.
             */
            mask: monFullscreen ? hiddenRegion : (modal ? fullRegion : pillRegion)
            Region { id: hiddenRegion }
            // Track the pill's *current* (animating) geometry, not the target.
            // Using Math.max(width, targetW) inflated the input region to the
            // final hover size the instant a hover began, so while the pill was
            // still visually small the region already spanned the full hover
            // width — an invisible catch-zone. A pointer that grazed the resting
            // pill and moved off sideways landed in that dead space, so the hover
            // never released and the window beneath it never got focus. Matching
            // the visible geometry means the region shrinks in lockstep with the
            // collapse and releases input (and hover) the moment the edge passes
            // the pointer.
            Region {
                id: pillRegion
                x: pill.x
                y: pill.y
                width: pill.width + pill.inputPadRight
                height: pill.height
            }
            Region {
                id: fullRegion
                width: overlay.width
                height: overlay.height
            }

            MouseArea {
                anchors.fill: parent
                enabled: overlay.modal
                acceptedButtons: Qt.AllButtons
                // A click-outside-to-dismiss backdrop is plumbing, not a
                // control. Left in the accessibility tree it announces itself
                // as an unnamed full-screen button sitting on top of the pill,
                // which is precisely the thing the user was trying to reach.
                Accessible.ignored: true
                onPressed: (mouse) => {
                    // This backdrop fills the whole overlay and only owns
                    // presses that land OUTSIDE the pill; presses inside belong
                    // to the pill's own handlers (the pin TapHandler, surface
                    // controls). Checking `inside` for BOTH modal branches makes
                    // dismissal deterministic — an inside press no longer both
                    // toggles pinned here AND in the TapHandler (the old race).
                    var inside = mouse.x >= pillRegion.x && mouse.x <= pillRegion.x + pillRegion.width
                        && mouse.y >= pillRegion.y && mouse.y <= pillRegion.y + pillRegion.height;
                    if (inside)
                        return;
                    if (overlay.surfaceOpen)
                        root.close();
                    else
                        pill.pinned = false;
                }
            }

            FocusScope {
                id: focusScope
                anchors.fill: parent
                focus: overlay.surfaceOpen

                // Hover source is at the window level (not on the resizing
                // pill) to avoid child-hover flicker during the width morph.
                HoverHandler {
                    onHoveredChanged: pill.hovered = hovered
                }
                Keys.onEscapePressed: root.close()

                Pill {
                    id: pill
                    anchors.top: parent.top
                    anchors.topMargin: overlay.topGap
                    anchors.horizontalCenter: parent.horizontalCenter

                    s: overlay.s
                    screenName: overlay.modelData.name
                    barWindow: overlay
                    surface: overlay.surface

                    // Fullscreen retract: slide off the top edge (and fade)
                    // when a real fullscreen window owns this monitor's
                    // active workspace; the mask is already hiddenRegion so
                    // the layer is click-through while retracted.
                    transform: Translate {
                        y: overlay.monFullscreen ? -(pill.height + overlay.topGap) : 0
                        Behavior on y {
                            NumberAnimation {
                                duration: Motion.morph
                                easing.type: Motion.easeMorph
                                easing.bezierCurve: Motion.morphCurve
                            }
                        }
                    }

                    opacity: overlay.monFullscreen ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeMorph
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }

                    onRequestSurface: (name) => root.toggleSurface(overlay.modelData.name, name)
                    onRequestClose: root.close()
                    // Hover-row power icon: open the standalone full-screen
                    // session menu (modules/powermenu), not a pill surface.
                    onRequestPower: root.powerMenuOpen = true
                }
            }

            onSurfaceOpenChanged: if (surfaceOpen) focusScope.forceActiveFocus()
        }
    }
}
