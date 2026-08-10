pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — live audio spectrum (ported from Ricelin pill/Singletons/Cava.qml).
 * A headless cava captures the default sink monitor, so the bars answer to any
 * system sound (music, a background video, a game) instead of one MPRIS player.
 * cava runs the FFT and smoothing; we only parse its raw ascii frames into
 * normalized 0..1 levels.
 *
 * LAZY SINGLETON — merely referencing Cava constructs it and spawns the cava
 * process. Consumers must therefore mount UNCONDITIONALLY and gate by opacity
 * on `active`, never `Loader { active: Cava.active }` (that would spawn/kill
 * cava on every inter-track gap).
 *
 * Silence arrives as an all-zero frame every tick, which `active` debounces
 * (450ms) into a clean play/stop signal so the clock↔bars morph does not flap
 * between tracks.
 *
 * cava is an optional dependency: a machine without it must degrade cleanly.
 * We probe for the binary once and only ever spawn it when it is actually
 * present, which keeps the plain clock on those machines.
 */
Singleton {
    id: root

    readonly property int bars: 5
    readonly property int framerate: 60

    // The parser writes these imperatively; the readonly facades below are the
    // public API every view binds to.
    property var _values: []
    property bool _active: false

    /** Normalized 0..1 level per band, updated each cava frame while audible. */
    readonly property var values: _values
    /** Debounced "there is signal" — true through inter-track gaps up to 450ms. */
    readonly property bool active: _active

    property bool available: false
    // Only run the FFT process (and hold the PipeWire capture stream) when the
    // visualizer is actually switched on — a hidden viz must not tap the sink.
    readonly property bool wanted: available && Flags.musicViz

    // Relaunch backoff: repeated immediate crashes must not respawn cava on a
    // tight 1.5s loop forever. Each crash backs off further and, past the cap,
    // we stop retrying; a healthy frame resets the count.
    property int _retries: 0
    readonly property int _maxRetries: 6

    /**
     * autosens is off so a silent browser holding the sink stays at zero bars
     * instead of autosens amplifying the noise floor up to full range and
     * tripping the visualizer on dead silence. The trade is a fixed gain,
     * tuned so real music fills the bars while silence stays under the
     * activate threshold. (Ricelin values, verbatim.)
     */
    readonly property string config: "[general]\n"
        + "bars = " + bars + "\nframerate = " + framerate + "\nautosens = 0\nsensitivity = 5500\n"
        + "[input]\nmethod = pipewire\nsource = auto\n"
        + "[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\n"
        + "ascii_max_range = 1000\nbar_delimiter = 59\nframe_delimiter = 10\n"
        + "channels = mono\nmono_option = average\n"
        + "[smoothing]\nnoise_reduction = 0.77\n"

    onWantedChanged: {
        if (wanted)
            root._retries = 0;
        cavaProc.running = wanted;
    }
    Component.onCompleted: cavaProc.running = wanted

    Process {
        running: true
        command: ["sh", "-c", "command -v cava >/dev/null 2>&1"]
        onExited: (code) => root.available = (code === 0)
    }

    Process {
        id: cavaProc
        command: ["sh", "-c", "printf '%s' \"$1\" | cava -p /dev/stdin", "_", root.config]
        stdout: SplitParser {
            onRead: (line) => {
                if (!line)
                    return;
                // A frame arrived → cava is healthy; clear any pending backoff.
                if (root._retries !== 0)
                    root._retries = 0;
                const parts = line.split(";");
                const out = [];
                let peak = 0;
                for (let i = 0; i < root.bars; i++) {
                    const v = (parseInt(parts[i]) || 0) / 1000;
                    out.push(v);
                    if (v > peak)
                        peak = v;
                }
                /**
                 * Silence frames stop mattering once the morph has settled
                 * back to the clock, so skip the 60Hz values churn while both
                 * the frame and the stored values are already flat.
                 */
                const flat = peak <= 0.001 && !root._active;
                if (!flat)
                    root._values = out;
                if (peak > 0.02) {
                    root._active = true;
                    idle.restart();
                }
            }
        }
        /** A crash while cava is still wanted earns one relaunch after a beat, never a tight respawn loop. */
        onExited: {
            if (!root.wanted)
                return;
            if (root._retries >= root._maxRetries)
                return; // repeated immediate crashes: give up rather than spin
            root._retries++;
            relaunch.restart();
        }
    }

    Timer {
        id: relaunch
        // Back off with each successive crash (1.5s, 3s, … capped at 15s).
        interval: Math.min(1500 * root._retries, 15000)
        onTriggered: if (root.wanted) cavaProc.running = true
    }

    /**
     * Signal debounce (not an animation — deliberately not a Motion token):
     * short enough to feel live, long enough that inter-track gaps do not
     * snap the morph back to the clock.
     */
    Timer {
        id: idle
        interval: 450
        onTriggered: root._active = false
    }
}
