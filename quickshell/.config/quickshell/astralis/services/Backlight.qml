pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — one shared poller for the internal laptop backlight (ported from
 * Ricelin pill/Singletons/Backlight.qml). Every pill carries an Osd, so
 * watching /sys here keeps it a single loop instead of one per monitor.
 * `changed` fires on a new reading after the initial populate, so login
 * doesn't flash the OSD; the loop exits at once on machines without a
 * backlight.
 *
 * astralis delta: adds `set(v)` (0..1) through brightnessctl when installed
 * (probed once at startup). Hardware keys already run brightnessctl from the
 * hypr binds — the poller alone is what drives the OSD — so the setter only
 * backs future UI faders; without brightnessctl it degrades to a no-op and
 * the singleton stays read-only.
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
     * dragged to zero never blanks the panel. The sysfs poller reports the
     * result back within a second, so no optimistic local write is needed.
     */
    function set(v) {
        if (!hasCtl || !present)
            return;
        var pct = Math.max(1, Math.min(100, Math.round(v * 100)));
        Quickshell.execDetached(["brightnessctl", "-q", "set", pct + "%"]);
    }

    /**
     * Adjust brightness by delta (hardware keys send ±0.05). Optimistically
     * bumps `brightness` so autorepeat accumulates before the 1 s sysfs poller
     * catches up, and fires `changed()` so the OSD flashes on the same frame.
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

    Process {
        command: ["sh", "-c", "dev=$(ls /sys/class/backlight 2>/dev/null | head -n1); [ -n \"$dev\" ] || exit 0; max=$(cat /sys/class/backlight/$dev/max_brightness); last=\"\"; while true; do val=$(cat /sys/class/backlight/$dev/brightness); if [ \"$val\" != \"$last\" ]; then echo \"$(( val * 100 / max ))\"; last=\"$val\"; fi; sleep 1; done"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                var pct = parseInt(line.trim(), 10);
                if (isNaN(pct))
                    return;
                var seen = root.lastPct >= 0;
                root.present = true;
                root.brightness = Math.max(0, Math.min(100, pct)) / 100.0;
                root.lastPct = pct;
                if (seen)
                    root.changed();
            }
        }
    }
}
