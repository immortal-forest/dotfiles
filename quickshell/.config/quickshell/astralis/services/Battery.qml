pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/**
 * astralis — laptop-battery state for the pill (ported verbatim from Ricelin
 * pill/Singletons/Battery.qml), sourced from UPower's display device and
 * gated so a desktop without a battery reports `present` false (the hover
 * cluster and 蓄 surface stay hidden). Exposes percentage, charge state, a
 * signed draw/charge wattage, capacity and optional health, plus a formatted
 * time-to-empty/full string. `low` flags a discharging battery at or below 20%.
 */
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice

    readonly property bool present: dev !== null && dev.ready && dev.isLaptopBattery && dev.isPresent
    readonly property real frac: dev ? Math.max(0, Math.min(1, dev.percentage)) : 0
    readonly property int pct: Math.round(frac * 100)
    readonly property int state: dev ? dev.state : UPowerDeviceState.Unknown

    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool full: state === UPowerDeviceState.FullyCharged || pct >= 100
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool low: !charging && pct <= 20

    readonly property real rateW: !dev ? 0
        : (discharging ? -dev.changeRate : (charging ? dev.changeRate : 0))
    readonly property real capacityWh: dev ? dev.energyCapacity : 0

    readonly property bool healthSupported: dev ? dev.healthSupported : false
    readonly property int health: dev ? Math.round(dev.healthPercentage) : 0

    readonly property bool hasTime: !dev ? false
        : (charging ? dev.timeToFull > 0 : (discharging ? dev.timeToEmpty > 0 : false))
    readonly property string timeStr: !dev ? ""
        : (charging ? fmt(dev.timeToFull) : (discharging ? fmt(dev.timeToEmpty) : ""))

    readonly property string stateLabel: charging ? "Charging"
        : (full ? "On AC · Full"
        : (discharging ? "Discharging" : "On AC"))

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (h > 0)
            return h + "h " + m + "m";
        return m + "m";
    }

    /**
     * Wear, straight from sysfs: UPower reports `healthSupported` false on
     * this firmware, but the kernel has energy_full / energy_full_design and
     * cycle_count. -1 = unknown. Re-read every 30 min (both move slowly).
     */
    property int wearPct: -1
    property int cycles: -1
    Process {
        id: wearProc
        command: ["sh", "-c", "for b in /sys/class/power_supply/BAT*; do echo \"$(cat \"$b/energy_full\" 2>/dev/null || echo 0) $(cat \"$b/energy_full_design\" 2>/dev/null || echo 0) $(cat \"$b/cycle_count\" 2>/dev/null || echo -1)\"; break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim().split(/\s+/);
                var full = parseFloat(p[0]) || 0, design = parseFloat(p[1]) || 0;
                root.wearPct = design > 0 && full > 0 ? Math.round(100 * full / design) : -1;
                var c = parseInt(p[2], 10);
                root.cycles = isNaN(c) || c < 0 ? -1 : c;
            }
        }
    }
    Timer {
        interval: 1800000
        running: root.present
        repeat: true
        triggeredOnStart: true
        onTriggered: wearProc.running = true
    }

    /**
     * Charge history for the dashboard curve: one {t, pct, chg} sample a
     * minute over the last histSpan ms (3 h), with its timestamp so the curve
     * can sit on a real time axis and leave gaps where the machine slept.
     * Saved to the cache on every sample and reloaded at start, so a shell
     * restart no longer wipes it (the curve used to read "LAST 2 MIN" of one
     * flat line after every reload).
     */
    readonly property real histSpan: 3 * 3600 * 1000
    property var hist: []
    /** The saved history is loaded; `present` can flip during init, before the file's path is bound. */
    property bool loaded: false
    function sample() {
        if (!present || !loaded)
            return;
        var now = Date.now();
        var h = hist.filter(function (e) { return now - e.t <= root.histSpan; });
        // a reload or a state echo inside the minute adds nothing new
        var last = h.length ? h[h.length - 1] : null;
        if (last && now - last.t < 50000 && last.pct === pct && last.chg === charging)
            return;
        h.push({ t: now, pct: pct, chg: charging });
        hist = h;
        histFile.setText(JSON.stringify(h));
    }
    FileView {
        id: histFile
        path: Quickshell.env("HOME") + "/.cache/astralis/battery-hist.json"
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: {
        try {
            var now = Date.now();
            var h = JSON.parse(histFile.text());
            if (Array.isArray(h))
                root.hist = h.filter(function (e) {
                    return e && typeof e.t === "number" && typeof e.pct === "number" && now - e.t <= root.histSpan && e.t <= now;
                });
        } catch (e) {}
        root.loaded = true;
        root.sample();
    }
    onPresentChanged: if (present) sample()
    // a state flip lands at once rather than on the next minute
    onChargingChanged: if (present) sample()
    Timer {
        interval: 60000
        running: root.present
        repeat: true
        onTriggered: root.sample()
    }
}
