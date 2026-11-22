pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * astralis — per-output brightness, keyed by output name ("eDP-2", "DP-1").
 * The laptop panel stays on Backlight (sysfs + brightnessctl); external
 * monitors go over DDC/CI with ddcutil (VCP 0x10). The brightness keys act on
 * the focused monitor, each pill's OSD flashes only for its own output, and
 * the Mixer/Dashboard faders pick an output.
 *
 * ddcutil is slow (~0.6 s a read, ~0.3 s a write), so a DDC level is updated
 * optimistically and writes are coalesced: one ddcutil runs at a time and
 * only the newest value per output is sent, so key autorepeat or a fader drag
 * never queues a backlog. The monitor's own buttons change brightness behind
 * our back; refresh() re-reads (the Mixer and Dashboard call it on open).
 */
Singleton {
    id: root

    /** ddcutil presence, probed once; externals stay uncontrolled without it. */
    property bool hasDdc: false

    /** DDC outputs from `ddcutil detect`: { "DP-1": { bus: 3, label: "MSI", max: 100 } }. */
    property var ddc: ({})
    /** Last read (or optimistic) DDC level per output, 0..1. */
    property var levels: ({})
    /** Raw VCP value waiting to be written, per output. */
    property var pending: ({})

    signal changed(string name)

    /** The internal panel's output name, "" when it isn't a connected screen (lid closed). */
    readonly property string panel: {
        var ss = Quickshell.screens;
        for (var i = 0; i < ss.length; i++)
            if (/^(eDP|LVDS|DSI)-/.test(ss[i].name))
                return ss[i].name;
        return "";
    }

    /** Outputs with a working control, left to right as the screens are laid out. */
    readonly property var outputs: {
        var out = [];
        if (panel.length > 0 && Backlight.present)
            out.push(panel);
        for (var n in ddc)
            if (levels[n] !== undefined)
                out.push(n);
        var ss = Quickshell.screens;
        function xOf(name) {
            for (var i = 0; i < ss.length; i++)
                if (ss[i].name === name)
                    return ss[i].x;
            return 0;
        }
        out.sort(function (a, b) { return xOf(a) - xOf(b); });
        return out;
    }

    function isPanel(name) {
        return name.length > 0 && name === panel;
    }

    function presentOn(name) {
        return isPanel(name) ? Backlight.present : (ddc[name] !== undefined && levels[name] !== undefined);
    }

    function levelOf(name) {
        if (isPanel(name))
            return Backlight.brightness;
        return levels[name] !== undefined ? levels[name] : 0;
    }

    /** Short fader label: "Laptop" for the panel, the maker for a DDC monitor. */
    function labelOf(name) {
        if (isPanel(name))
            return "Laptop";
        return ddc[name] && ddc[name].label ? ddc[name].label : name;
    }

    function focusedName() {
        var m = Hyprland.focusedMonitor;
        return m ? m.name : panel;
    }

    /** Set `name` to v (0..1). Panel → Backlight (1% floor); DDC → optimistic + coalesced write. */
    function set(name, v) {
        if (isPanel(name)) {
            Backlight.set(v);
            return;
        }
        var d = ddc[name];
        if (!d || levels[name] === undefined)
            return;
        v = Math.max(0, Math.min(1, v));
        var lv = Object.assign({}, levels);
        lv[name] = v;
        levels = lv;
        var p = Object.assign({}, pending);
        p[name] = Math.round(v * d.max);
        pending = p;
        pump();
    }

    /** Nudge `name` by delta (keys send ±0.05) and flash its OSD. */
    function change(name, delta) {
        if (isPanel(name)) {
            Backlight.change(delta); // Backlight.changed → changed(panel) below
            return;
        }
        if (!presentOn(name))
            return;
        set(name, levelOf(name) + delta);
        changed(name);
    }

    function changeFocused(delta) {
        change(focusedName(), delta);
    }

    function setFocused(v) {
        set(focusedName(), v);
    }

    /** Re-read every DDC monitor's level (skipped while a write is in flight). */
    function refresh() {
        if (!hasDdc || reader.running)
            return;
        var buses = [];
        for (var n in ddc)
            buses.push(String(ddc[n].bus));
        if (buses.length === 0)
            return;
        reader.command = ["sh", "-c",
            "for b in \"$@\"; do echo \"$b $(ddcutil --bus \"$b\" getvcp 10 --brief 2>/dev/null)\"; done",
            "sh"].concat(buses);
        reader.running = true;
    }

    function detect() {
        if (hasDdc && !detector.running)
            detector.running = true;
    }

    /** Send the next coalesced write, one ddcutil at a time. */
    function pump() {
        if (writer.running)
            return;
        for (var n in pending) {
            var d = ddc[n];
            var raw = pending[n];
            var p = Object.assign({}, pending);
            delete p[n];
            pending = p;
            if (!d)
                continue;
            writer.command = ["ddcutil", "--bus", String(d.bus), "setvcp", "10", String(raw), "--noverify"];
            writer.running = true;
            return;
        }
    }

    Connections {
        target: Backlight
        function onChanged() {
            if (root.panel.length > 0)
                root.changed(root.panel);
        }
    }

    Process {
        command: ["sh", "-c", "command -v ddcutil >/dev/null 2>&1 && echo yes || echo no"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                root.hasDdc = line.trim() === "yes";
                root.detect();
            }
        }
    }

    /**
     * `ddcutil detect --terse` prints one block per display; "Invalid display"
     * blocks (the laptop panel, which has no DDC) are skipped. The DRM
     * connector ("card1-DP-1") minus its card prefix is the Hyprland output.
     */
    Process {
        id: detector
        command: ["ddcutil", "detect", "--terse"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                var blocks = this.text.split(/\n\s*\n/);
                for (var i = 0; i < blocks.length; i++) {
                    var b = blocks[i];
                    if (!/^Display \d+/m.test(b))
                        continue;
                    var bus = b.match(/I2C bus:\s*\/dev\/i2c-(\d+)/);
                    var conn = b.match(/DRM connector:\s*card\d+-(\S+)/);
                    if (!bus || !conn)
                        continue;
                    var mon = b.match(/Monitor:\s*([^:\n]*):?([^:\n]*)/);
                    var label = mon ? (mon[1].trim() || mon[2].trim()) : "";
                    var old = root.ddc[conn[1]];
                    map[conn[1]] = { bus: parseInt(bus[1], 10), label: label, max: old ? old.max : 100 };
                }
                // Drop levels for outputs that went away so outputs/presentOn follow.
                var lv = {};
                for (var n in root.levels)
                    if (map[n])
                        lv[n] = root.levels[n];
                root.levels = lv;
                root.ddc = map;
                root.refresh();
            }
        }
    }

    /** Lines of "<bus> VCP 10 C <cur> <max>"; a monitor that didn't answer prints just "<bus> ". */
    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                var byBus = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var m = lines[i].match(/^(\d+) VCP 10 C (\d+) (\d+)/);
                    if (m)
                        byBus[m[1]] = { cur: parseInt(m[2], 10), max: parseInt(m[3], 10) };
                }
                var lv = Object.assign({}, root.levels);
                var dd = Object.assign({}, root.ddc);
                for (var n in dd) {
                    var r = byBus[String(dd[n].bus)];
                    if (!r || r.max <= 0)
                        continue;
                    dd[n] = Object.assign({}, dd[n], { max: r.max });
                    // Don't clobber an optimistic level whose write is still queued.
                    if (root.pending[n] === undefined && !writer.running)
                        lv[n] = r.cur / r.max;
                }
                root.ddc = dd;
                root.levels = lv;
            }
        }
    }

    Process {
        id: writer
        onExited: root.pump()
    }

    // A monitor plugged in (or moved to another port) needs a re-detect; DDC
    // isn't answering the instant the output appears, so give it a moment.
    Timer {
        id: redetect
        interval: 2500
        onTriggered: root.detect()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "monitoraddedv2" || event.name === "monitorremovedv2"
                    || event.name === "monitoradded" || event.name === "monitorremoved")
                redetect.restart();
        }
    }
}
