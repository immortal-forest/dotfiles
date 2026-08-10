pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../colors"

/**
 * astralis — shared session flags persisted to a small JSON file and watched
 * for external change (ported from Ricelin pill/Singletons/Flags.qml), so
 * every astralis daemon reads and writes the same Do-Not-Disturb and
 * Keep-Awake state live without a second notification server or idle
 * inhibitor. Toggling in one surface updates the others on the next file
 * event, and the state survives a daemon restart.
 *
 * Ricelin deltas: the manual-palette fields (manualHue/manualDark/manualSat,
 * wallcolors.py backend) are dropped — matugen owns the astralis palette.
 * Everything else is kept verbatim even where its consumer lands in a later
 * phase (record, idle, nightLight…); JsonAdapter defaults keep them inert.
 */
Singleton {
    id: root

    property alias dnd: adapter.dnd
    property alias airplane: adapter.airplane
    property alias time12h: adapter.time12h
    property alias clockSeconds: adapter.clockSeconds
    property alias showGlyphs: adapter.showGlyphs
    property alias uiColor: adapter.uiColor
    property alias wallReseed: adapter.wallReseed
    property alias paletteMode: adapter.paletteMode
    property alias base16Shell: adapter.base16Shell
    property alias uiScale: adapter.uiScale
    property alias reduceMotion: adapter.reduceMotion
    property alias uiFont: adapter.uiFont
    property alias recordCountdown: adapter.recordCountdown
    property alias recordDir: adapter.recordDir
    property alias recordFps: adapter.recordFps
    property alias recordQuality: adapter.recordQuality
    property alias recordCursor: adapter.recordCursor
    property alias recordMic: adapter.recordMic
    property alias recordDesktop: adapter.recordDesktop
    property alias recordClearedBefore: adapter.recordClearedBefore
    property alias idleDimMin: adapter.idleDimMin
    property alias idleLockMin: adapter.idleLockMin
    property alias idleScreenOffMin: adapter.idleScreenOffMin
    property alias idleSuspendMin: adapter.idleSuspendMin
    property alias lockBeforeSleep: adapter.lockBeforeSleep
    property alias weatherCity: adapter.weatherCity
    property alias musicViz: adapter.musicViz
    property alias nightLightMode: adapter.nightLightMode
    property alias nightLightTemp: adapter.nightLightTemp
    property alias nightLightOnMin: adapter.nightLightOnMin
    property alias nightLightOffMin: adapter.nightLightOffMin

    // Push flags into their consumers from here so neither singleton needs to
    // know Flags exists (Ricelin wires Notifs.dnd the same way, shell-side).
    // A Binding survives the consumers' own defaults and re-asserts on every
    // flags.json change.
    Binding {
        target: Motion
        property: "reduceMotion"
        value: adapter.reduceMotion
    }
    Binding {
        target: Notifications
        property: "dnd"
        value: adapter.dnd
    }
    // Colourfulness (Settings → Appearance): map the string pref onto the
    // Colors singleton's numeric vibrancy so the whole shell recolours live.
    // Colors stays dependency-free (it never imports services); Flags pushes,
    // exactly as it does for Motion/Notifications above.
    Binding {
        target: Colors
        property: "vibrancy"
        value: adapter.uiColor === "bold" ? 2 : (adapter.uiColor === "subtle" ? 0 : 1)
    }

    // Palette mode (Settings → Appearance → Palette): base16 is already a
    // final, deliberately-chosen palette (vivid from the seed color, or
    // authentic/pywal-style from the raw image), so once the SHELL itself is
    // actually showing it, the vibrancy tint layer must be bypassed entirely —
    // otherwise Colors.qml would re-tint an already-final palette on top of
    // matugen's base16 remap. Keys on "is the shell showing base16", which is
    // paletteMode !== "material" AND base16Shell — `base16Shell` alone means
    // nothing while paletteMode is "material" (shell still reads plain M3
    // Colors.json then), and paletteMode alone doesn't flip the shell unless
    // base16Shell is also on (apps-only base16 leaves the shell M3). Same
    // dependency-free push as `vibrancy` above.
    Binding {
        target: Colors
        property: "bypassTint"
        value: adapter.paletteMode !== "material" && adapter.base16Shell
    }

    // Gates the rfkill sweep below. Stays false until the initial file load
    // resolves (set in the FileView's onLoaded/onLoadFailed, which fire AFTER the
    // adapter deserialize that drives onAirplaneChanged), so the load-time edge is
    // suppressed and only genuine post-load toggles touch the radios.
    property bool airplaneReady: false

    /**
     * Airplane mode: one rfkill sweep per USER flag edge — on blocks every radio
     * (wifi + bluetooth), off unblocks them all. Guarded by `command -v rfkill`
     * so a machine without the tool degrades to a silent no-op. The load-time
     * edge is skipped (see airplaneReady): daemon start reflects the radios'
     * actual state instead of unconditionally re-blocking from a persisted
     * `true`; the user re-toggles to re-apply.
     */
    onAirplaneChanged: {
        if (!root.airplaneReady)
            return;
        rfkillProc.running = false;
        rfkillProc.command = ["sh", "-c",
            "command -v rfkill >/dev/null 2>&1 && rfkill "
            + (adapter.airplane ? "block" : "unblock") + " all || true"];
        rfkillProc.running = true;
    }

    Process {
        id: rfkillProc
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.cache/astralis/flags.json"
        blockLoading: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: root.airplaneReady = true
        onLoadFailed: function (error) {
            // Defer the first-run default write until mkdir has created the cache
            // dir (dirReady); mkdirProc.onExited re-runs reload() so a missing file
            // still materialises, just after the dir exists.
            if (error === FileViewError.FileNotFound && root.dirReady)
                writeAdapter();
            root.airplaneReady = true;
        }

        JsonAdapter {
            id: adapter
            property bool dnd: false
            property bool airplane: false
            property bool time12h: false
            property bool clockSeconds: false
            property bool showGlyphs: true
            property string uiColor: "balanced"
            property string wallReseed: "balanced"
            property string paletteMode: "material"
            property bool base16Shell: false
            property real uiScale: 1.0
            property bool reduceMotion: false
            property string uiFont: ""
            property int recordCountdown: 5
            property string recordDir: ""
            property int recordFps: 60
            property string recordQuality: "high"
            property bool recordCursor: true
            property bool recordMic: true
            property bool recordDesktop: true
            property real recordClearedBefore: 0
            property int idleDimMin: 0
            property int idleLockMin: 5
            property int idleScreenOffMin: 6
            property int idleSuspendMin: 0
            property bool lockBeforeSleep: true
            property string weatherCity: ""
            property bool musicViz: true
            property string nightLightMode: "off"
            property int nightLightTemp: 4000
            property int nightLightOnMin: 1260
            property int nightLightOffMin: 450
        }
    }

    // writeAdapter() can't create directories; create the cache dir first, then
    // reload so a first-run missing file is written only after the dir exists.
    property bool dirReady: false
    Component.onCompleted: mkdirProc.running = true
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.cache/astralis"]
        onExited: {
            root.dirReady = true;
            file.reload();
        }
    }
}
