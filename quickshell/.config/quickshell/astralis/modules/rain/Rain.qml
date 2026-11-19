pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../services"

/**
 * astralis — Retroact Rain (Wuthering Waves): rain falls, halts in mid-air,
 * then rises (or only rises: Flags.rainSequence). One rain on every screen at
 * once (clock: services/RetroactRain.qml); a RainLayer per screen exists only
 * while it plays. shell.qml instantiates `Rain { locked: … }`.
 *
 * What plays it:
 *   Super+Shift+W / `qs -c astralis ipc call rain toggle`
 *   a new wallpaper (Flags.rainOnWallpaper) — once skwd-paper's crossfade and
 *     the new depth cut-out are done, so it never rains on a half-faded scene
 *   unlocking (Flags.rainOnUnlock)
 *   Settings › Widgets › Retroact Rain
 * Automatic plays are skipped under reduce-motion. Locking cuts it at once.
 *
 * Length "Indefinite" is a state, not an event: while one plays,
 * Flags.rainActive is on, and only stopping it (key, toggle, ipc stop) clears
 * it — a lock or a shell restart cuts the rain but it comes back afterwards.
 * Whatever the length, the clock pauses while fullscreen windows cover every
 * screen, so a game never pays for rain it can't see.
 *
 *   qs -c astralis ipc call rain play      # Flags.rainLength decides when it ends
 *   qs -c astralis ipc call rain hold      # rise until stopped, whatever the length
 *   qs -c astralis ipc call rain stop      # fade out now
 *   qs -c astralis ipc call rain status
 */
Scope {
    id: root

    property bool locked: false

    function start(force) {
        if (root.locked)
            return;
        RetroactRain.play(force);
    }

    IpcHandler {
        target: "rain"
        function play(): void { root.start(false); }
        function hold(): void { root.start(true); }
        function stop(): void { RetroactRain.stop(); }
        function toggle(): void {
            if (RetroactRain.playing && !RetroactRain.ending)
                RetroactRain.stop();
            else
                root.start(false);
        }
        function status(): string {
            if (!RetroactRain.playing)
                return "idle";
            return (RetroactRain.ending ? "ending" : RetroactRain.holding ? "holding" : "playing")
                + (RetroactRain.paused ? " (paused: fullscreen)" : "")
                + " t=" + RetroactRain.t.toFixed(1) + "s vel=" + RetroactRain.vel.toFixed(2);
        }
    }

    // ── Indefinite: remembered on, back after a lock or restart ───────────
    function syncActive() {
        if (root.locked)
            return;     // the lock's cut is not the user stopping it
        var on = RetroactRain.playing && !RetroactRain.ending && RetroactRain.holding;
        if (Flags.rainActive !== on)
            Flags.rainActive = on;
    }
    Connections {
        target: RetroactRain
        function onPlayingChanged() { root.syncActive(); }
        function onEndingChanged() { root.syncActive(); }
        function onHoldingChanged() { root.syncActive(); }
    }
    function resume() {
        if (Flags.rainActive && !RetroactRain.playing && !root.locked)
            root.start(false);
    }
    // flags.json can land after we exist (startup) or before (hot reload);
    // either way an Indefinite rain that was on starts again
    Connections {
        target: Flags
        function onRainActiveChanged() { root.resume(); }
    }

    // ── lock: gone at once; back on the way out if Indefinite or asked ────
    onLockedChanged: {
        if (root.locked) {
            RetroactRain.cut();
            unlockDelay.stop();
            settle.stop();
            giveUp.stop();
            root.waitingCut = false;
        } else if (Flags.rainActive || (Flags.rainOnUnlock && !Flags.reduceMotion)) {
            unlockDelay.restart();
        }
    }
    Timer {
        id: unlockDelay
        // let the lock surface finish leaving first
        interval: Motion.morph
        onTriggered: root.start(false)
    }

    // ── fullscreen everywhere: freeze the clock (nothing to see, nothing to draw) ──
    readonly property bool covered: {
        var mons = Hyprland.monitors.values;
        if (!mons.length)
            return false;
        for (var i = 0; i < mons.length; i++) {
            var ws = mons[i] ? mons[i].activeWorkspace : null;
            // hasFullscreen, not lastIpcObject.hasfullscreen (empty on Hyprland 0.56)
            if (!ws || !ws.hasFullscreen)
                return false;
        }
        return true;
    }
    Binding {
        target: RetroactRain
        property: "paused"
        value: root.covered
    }

    // ── a new wallpaper ───────────────────────────────────────────────────
    property string seenWall: ""
    Component.onCompleted: {
        seenWall = Wallpaper.current;
        resume();
    }
    Connections {
        target: Wallpaper
        function onCurrentChanged() {
            var prev = root.seenWall;
            root.seenWall = Wallpaper.current;
            // "" → path is the first read at startup, not a change
            if (!prev.length || Wallpaper.current === prev || !Wallpaper.current.length)
                return;
            if (!Flags.rainOnWallpaper || Flags.reduceMotion || root.locked)
                return;
            settle.restart();
            giveUp.restart();
        }
    }
    /** Past skwd-paper's crossfade and waiting on the new cut-out. */
    property bool waitingCut: false
    readonly property bool cutBusy: WallpaperDepth.status === "working" || WallpaperDepth.pending.length > 0
    onCutBusyChanged: tryStart()
    function tryStart() {
        if (!root.waitingCut || root.cutBusy)
            return;
        root.waitingCut = false;
        giveUp.stop();
        root.start(false);
    }
    Timer {
        id: settle
        // skwd-wall-v2 config.json transition.durationMs is 2100
        interval: 2200
        onTriggered: {
            root.waitingCut = true;
            root.tryStart();
        }
    }
    Timer {
        id: giveUp
        // a cut-out still not done by now: rain anyway, it eases in when it lands
        interval: 6000
        onTriggered: {
            if (!root.waitingCut)
                return;
            root.waitingCut = false;
            root.start(false);
        }
    }

    // ── one surface per screen, only while it plays ───────────────────────
    Variants {
        model: Quickshell.screens

        Scope {
            id: per
            required property var modelData

            LazyLoader {
                active: RetroactRain.playing
                RainLayer {
                    screen: per.modelData
                    ev: RetroactRain
                }
            }
        }
    }
}
