pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — one shared watcher for the internal laptop backlight (ported from
 * Ricelin pill/Singletons/Backlight.qml). Every pill carries an Osd, so
 * watching /sys here keeps it a single source instead of one per monitor.
 * `changed` fires on a new reading after the initial populate, so login
 * doesn't flash the OSD; with no backlight device nothing is read and
 * `present` stays false.
 *
 * astralis delta: adds `set(v)` (0..1) through brightnessctl when installed
 * (probed once at startup). The sysfs reading, refreshed on each udev
 * backlight event, is what drives the OSD; without brightnessctl the setter
 * degrades to a no-op and the singleton stays read-only.
 */
Singleton {
    id: root

    property bool present: false
    property real brightness: 0
    property int lastPct: -1

    /** brightnessctl presence, probed once below; set() no-ops while false. */
    property bool hasCtl: false

    signal changed()

    /**
     * Set the backlight to v (0..1). Clamped with a 1% floor so a fader
     * dragged to zero never blanks the panel. The udev change event reports
     * the result back at once, so no optimistic local write is needed.
     */
    function set(v) {
        if (!hasCtl || !present)
            return;
        var pct = Math.max(1, Math.min(100, Math.round(v * 100)));
        Quickshell.execDetached(["brightnessctl", "-q", "set", pct + "%"]);
    }

    /**
     * Adjust brightness by delta (hardware keys send ±0.05). Optimistically
     * bumps `brightness` so autorepeat accumulates before brightnessctl lands
     * and the uevent reports back, and fires `changed()` so the OSD flashes
     * on the same frame.
     */
    function change(delta) {
        if (!hasCtl || !present)
            return;
        var v = Math.max(0, Math.min(1, brightness + delta));
        brightness = v;
        set(v);
        changed();
    }

    Process {
        command: ["sh", "-c", "command -v brightnessctl >/dev/null 2>&1 && echo yes || echo no"]
        running: true
        stdout: SplitParser {
            onRead: (line) => root.hasCtl = line.trim() === "yes"
        }
    }

    // ── sysfs, read in-process, re-read on udev ─────────────────────────────
    // The backlight core emits a `change` uevent for every brightness write
    // (sysfs or hotkey), and `brightness` only changes through those paths,
    // so Udev's event is exactly the old 1s poll's trigger — minus a `cat`
    // and a `sleep` forked every second, forever.

    /** The device under /sys/class/backlight, found once at startup. */
    property string dev: ""
    property int maxRaw: 0
    property int lastRaw: -1

    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: root.dev = this.text.trim()
        }
    }

    FileView {
        id: maxFile
        path: root.dev ? "/sys/class/backlight/" + root.dev + "/max_brightness" : ""
        printErrors: false
        onLoaded: {
            root.maxRaw = parseInt(text(), 10) || 0;
            root.publish();
        }
    }

    FileView {
        id: brightFile
        path: root.dev ? "/sys/class/backlight/" + root.dev + "/brightness" : ""
        printErrors: false
        onLoaded: root.publish()
    }

    Connections {
        target: Udev
        function onEvent(subsystem, action) {
            if (subsystem === "backlight")
                brightFile.reload();
        }
    }

    /**
     * A no-op write (same value) still raises a uevent, so compare the raw
     * reading: only a real change moves `brightness` or flashes the OSD, and
     * the first reading after startup populates silently.
     */
    function publish() {
        if (root.maxRaw <= 0 || !brightFile.loaded)
            return;
        var raw = parseInt(brightFile.text(), 10);
        if (isNaN(raw) || raw === root.lastRaw)
            return;
        var pct = Math.floor(raw * 100 / root.maxRaw);
        var seen = root.lastRaw >= 0;
        root.lastRaw = raw;
        // Value before `present`, so anything reacting to present sees it.
        root.brightness = Math.max(0, Math.min(100, pct)) / 100.0;
        root.lastPct = pct;
        root.present = true;
        if (seen)
            root.changed();
    }
}
