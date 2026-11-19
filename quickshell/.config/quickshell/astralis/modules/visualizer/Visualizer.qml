pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import "../../colors"
import "../../services"

/**
 * astralis — full-screen music visualizer, one per screen. A wave rides the
 * screen edges: a live body that fades toward the edge it grows from, with a
 * lit crest, hot tips on loud bands and a bloom that swells with loudness,
 * over a faint veil tracing the recent peaks as they fall.
 *
 * WHERE it draws is `Flags.vizLayout` (Settings → Appearance → Visualizer):
 *   top · bottom · topBottom (two mirrored waves) · sides (left + right) ·
 *   topHalf (the top wave bends round both corners and bleeds ~40% down the
 *   sides, tapering off) · topSides (up the left, across the top, down the
 *   right) · all (one closed loop round the screen).
 * A layout is a PATH along the screen edges; `rails` hands the shader, per
 * edge, where that edge sits on the path (t at each end). The spectrum is
 * mirrored along the path — bass mid-path, treble at the ends (a loop: bass at
 * the top centre, treble at the bottom centre) — so every layout stays
 * balanced left/right.
 *
 * Drawn by VizLayer: ONE click-through full-screen surface with ONE fragment
 * shader (shaders/edgewave.frag). The old SVG-path renderer rebuilt and
 * re-triangulated three paths per edge 30×/s on the CPU; the shader takes the
 * levels as uniforms and costs a few instructions per pixel near an edge.
 *
 * One cava (32 mono bands, pipewire, 60fps) per screen feeds it, and runs only
 * while this scope exists — shell.qml's Loader keeps it on `vizEnabled`
 * (Super+B / `ipc call visualizer toggle`). That toggle is deliberately
 * independent of `Flags.musicViz` (the rest-pill spectrum's switch).
 */
Scope {
    id: viz

    property var screen
    property real s: 1

    /** False starts the fade-out; shell.qml's Loader destroys us once it has run. */
    property bool shown: true
    /** 0..1 surface opacity: eases in on creation, out when `shown` flips off. */
    property real fade: 0
    Behavior on fade {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.standardCurve }
    }
    Component.onCompleted: fade = Qt.binding(() => viz.shown ? 1 : 0)

    property string layout: Flags.vizLayout
    /** Full wave height for straight edges (bent layouts scale it down). */
    readonly property real depth: Math.round(200 * s)
    readonly property real sw: screen ? screen.width : 0
    readonly property real sh: screen ? screen.height : 0

    /** Whether a wave runs along the top edge (the pill dims over it). */
    readonly property bool hasTop: ["top", "topBottom", "topHalf", "topSides", "all"].indexOf(layout) >= 0

    /**
     * The layout as shader rails. Each edge is [on, t at its start, t at its
     * end], where an edge's start is its left (top/bottom) or top (left/right)
     * end and t runs 0..1 along the layout's path. A rail only draws where its
     * t lands inside 0..1 (a closed loop wraps instead), so the sides of
     * topHalf stop 40% of the way down on their own.
     *   sym    1 mirror (bass mid-path) · 2 loop (bass at the path's start/end)
     *   scale  band height factor: bent layouts run more edge, thinner band
     *   taper  share of t eased to nothing at each open end
     */
    readonly property var rails: {
        const W = sw, H = sh;
        const off = [0, 0, 0];
        const full = [1, 0, 1];
        const r = { top: off, right: off, bottom: off, left: off,
                    sym: 1, closed: 0, taper: 0, scale: 1 };
        if (W <= 0 || H <= 0)
            return r;
        switch (layout) {
        case "top":       r.top = full; break;
        case "bottom":    r.bottom = full; break;
        case "sides":     r.left = full; r.right = full; break;
        case "topHalf": {
            const d = 0.4 * H, L = d + W + d;
            // up the left side, across the top, down the right side
            r.left = [1, d / L, (d - H) / L];
            r.top = [1, d / L, (d + W) / L];
            r.right = [1, (d + W) / L, (d + W + H) / L];
            r.scale = 0.65; r.taper = 0.18;
            break;
        }
        case "topSides": {
            const L = H + W + H;
            r.left = [1, H / L, 0];
            r.top = [1, H / L, (H + W) / L];
            r.right = [1, (H + W) / L, 1];
            r.scale = 0.6; r.taper = 0.06;
            break;
        }
        case "all": {
            // clockwise from the top centre: right half of the top, down the
            // right, back along the bottom, up the left, left half of the top
            const L = 2 * W + 2 * H;
            r.top = [1, -0.5 * W / L, 0.5 * W / L];
            r.right = [1, 0.5 * W / L, (0.5 * W + H) / L];
            r.bottom = [1, (1.5 * W + H) / L, (0.5 * W + H) / L];
            r.left = [1, (1.5 * W + 2 * H) / L, (1.5 * W + H) / L];
            r.sym = 2; r.closed = 1; r.scale = 0.5;
            break;
        }
        default:          r.top = full; r.bottom = full; break;   // topBottom
        }
        return r;
    }

    // ── motion ────────────────────────────────────────────────────────────
    // cava does the FFT with light smoothing; the follow below shapes how the
    // wave moves: a band snaps up on a transient (~45ms) and sinks away
    // gently (~170ms), frame-rate independent. Peaks ride on top and only
    // fall, so a hit stays traced in the veil as the wave drops away from it.

    readonly property int bands: 32
    /** Must match `framerate` in the cava config below (one follow step per frame). */
    readonly property int cavaFps: 60
    readonly property real dt: 1 / cavaFps
    readonly property real attackK: 1 - Math.exp(-dt / 0.045)
    readonly property real decayK: 1 - Math.exp(-dt / 0.17)
    /** Trail fall, in full heights per second. */
    readonly property real peakFall: 0.55

    /** Eased spectrum, 0..1, bass → treble. */
    property var levels: []
    /** Falling peaks over `levels`. */
    property var peaks: []
    /** 0..1 loudness, eased: drives the bloom. */
    property real energy: 0

    /** Where cava listens. A dev harness swaps in a fifo of decoded audio. */
    property string cavaInput: "method = pipewire\nsource = auto"

    function step(target) {
        const cur = viz.levels, pk = viz.peaks;
        const fresh = cur.length !== target.length;
        const out = new Array(target.length);
        const np = new Array(target.length);
        let mx = 0, moving = false;
        for (let i = 0; i < target.length; i++) {
            // Lift: 32 narrow bands leave most of the spectrum low next to
            // the peak autosens normalises to, so quiet bands get a curve up.
            const goal = Math.pow(Math.max(0, Math.min(1, target[i])), 0.6);
            const c = fresh ? 0 : cur[i];
            const v = c + (goal - c) * (goal > c ? viz.attackK : viz.decayK);
            out[i] = v < 0.0005 ? 0 : v;
            const p = fresh ? 0 : pk[i] - viz.peakFall * viz.dt;
            np[i] = out[i] > p ? out[i] : Math.max(0, p);
            if (out[i] > mx) mx = out[i];
            if (out[i] > 0 || np[i] > 0) moving = true;
        }
        const e = viz.energy + (mx - viz.energy) * (mx > viz.energy ? 0.25 : 0.06);
        // Silence once everything has sunk: stop touching the uniforms, so the
        // surface stops repainting until sound returns.
        if (!moving && !viz._live)
            return;
        viz._live = moving;
        viz.levels = out;
        viz.peaks = np;
        viz.energy = e < 0.001 ? 0 : e;

        // Colour ring rides the frame beat. Reduce-motion holds it still
        // rather than running it faster (Motion.mult would shorten the period
        // — the opposite of calmer).
        if (Flags.vizColorCycle && !Motion.reduceMotion)
            viz.cyclePhase += viz.colorRing.length / (viz.cycleSeconds * viz.cavaFps);
    }
    property bool _live: true

    Process {
        id: cavaProc
        running: true
        command: ["sh", "-c", "printf '%s' \"$1\" | cava -p /dev/stdin", "_", `[general]
bars = ${viz.bands}
framerate = ${viz.cavaFps}
autosens = 1

[input]
${viz.cavaInput}

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 1000
bar_delimiter = 59
channels = mono
mono_option = average

[smoothing]
noise_reduction = 25
`]

        stdout: SplitParser {
            onRead: data => {
                const t = data.split(";");
                const target = [];
                for (let i = 0; i < t.length; i++) {
                    const v = parseInt(t[i]);
                    if (!isNaN(v))
                        target.push(v / 1000);
                }
                if (target.length >= 2)
                    viz.step(target);
            }
        }
    }

    /**
     * Colour cycle (Settings → Appearance → "Visualizer colour cycle"). The
     * ring alternates a bright accent with a deep container: matugen palettes
     * are hue-coherent, so TONE is what reads as movement. Roles the palette
     * collapses onto one value are dropped (a duplicate is a dead beat).
     */
    readonly property var colorRing: {
        const want = [Colors.primary, Colors.tertiary_container, Colors.secondary,
                      Colors.primary_container, Colors.tertiary, Colors.inverse_primary];
        const out = [];
        for (let i = 0; i < want.length; i++) {
            let dup = false;
            for (let j = 0; j < out.length; j++)
                if (Qt.colorEqual(out[j], want[i]))
                    dup = true;
            if (!dup)
                out.push(want[i]);
        }
        return out.length >= 2 ? out : [Colors.primary, Colors.tertiary];
    }

    /** Position in the ring, in ring-entries. */
    property real cyclePhase: 0
    /** Seconds for one full trip around the ring. */
    readonly property real cycleSeconds: 42

    /** Ring colour at a fractional index, wrapped and blended between entries. */
    function ringColor(at) {
        const n = viz.colorRing.length;
        const p = ((at % n) + n) % n;
        const i = Math.floor(p);
        return Qt.tint(viz.colorRing[i], Qt.alpha(viz.colorRing[(i + 1) % n], p - i));
    }

    /** The drawing surface (exposed so a dev harness can grab its pixels). */
    readonly property var surface: surfaceWin

    VizLayer {
        id: surfaceWin
        viz: viz
    }
}
