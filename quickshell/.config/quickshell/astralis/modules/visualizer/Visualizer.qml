pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import "../../colors"
import "../../services"

/**
 * astralis — full-screen music visualizer, one per screen (ported from
 * ~/shell components/Visualizer.qml). Draws a smoothed quadratic-spline
 * "mountain wave" filled with a primary→tertiary→secondary gradient, plus a
 * stretched shadow pass at 0.25 alpha and a LOWER background ridge that reads
 * the spectrum the other way round (so its crests land in the main wave's
 * valleys) with its own deeper gradient.
 *
 * WHERE it draws is `Flags.vizLayout` (Settings → Appearance → Visualizer):
 *   top · bottom · topBottom (two mirrored waves) · sides (left + right) ·
 *   topHalf (the top wave bends round both corners and bleeds ~40% down the
 *   sides, tapering off) · topSides (up the left, across the top, down the
 *   right) · all (one closed loop round the screen).
 * Every layout is a list of PATHS along the screen edges; the wave is offset
 * inward along each edge's normal, and at a corner the miter normal puts the
 * offset point on the diagonal so the wave turns the corner without folding.
 *
 * Drawn by VizLayer: ONE click-through full-screen surface of GPU Shapes.
 * (Separate per-edge surfaces commit frames independently, which tore the wave
 * into steps where they met; a full-screen Canvas would software-raster the
 * whole screen 30×/s.)
 *
 * One cava (20 bars, pulse, 30fps) per screen feeds the layer, and runs only
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

    readonly property string layout: Flags.vizLayout
    /** Full wave height for straight edges (bent layouts scale it down). */
    readonly property real depth: Math.round(200 * s)
    readonly property real sw: screen ? screen.width : 0
    readonly property real sh: screen ? screen.height : 0

    /** Whether a wave runs along the top edge (the pill dims over it). */
    readonly property bool hasTop: ["top", "topBottom", "topHalf", "topSides", "all"].indexOf(layout) >= 0

    /**
     * Edge paths for the layout, in screen coordinates. `sym` paths are fed a
     * mirrored spectrum so the one wave stays balanced left/right:
     *   "u"    bass at the top centre, treble at the side bottoms
     *   "loop" bass at the top centre, treble at the bottom centre
     */
    readonly property var paths: {
        const W = sw, H = sh;
        if (W <= 0 || H <= 0)
            return [];
        const P = (x, y) => ({ x: x, y: y });
        let defs;
        switch (layout) {
        case "top":       defs = [{ v: [P(0, 0), P(W, 0)] }]; break;
        case "bottom":    defs = [{ v: [P(0, H), P(W, H)] }]; break;
        case "sides":     defs = [{ v: [P(0, 0), P(0, H)] }, { v: [P(W, 0), P(W, H)] }]; break;
        // Bent layouts run a lot more edge, so the band is thinner there.
        case "topHalf":   defs = [{ v: [P(0, H * 0.4), P(0, 0), P(W, 0), P(W, H * 0.4)], sym: "u",
                                    scale: 0.65, taper: 0.18 }]; break;
        case "topSides":  defs = [{ v: [P(0, H), P(0, 0), P(W, 0), P(W, H)], sym: "u",
                                    scale: 0.6, taper: 0.06 }]; break;
        case "all":       defs = [{ v: [P(W / 2, 0), P(W, 0), P(W, H), P(0, H), P(0, 0), P(W / 2, 0)],
                                    sym: "loop", closed: true, scale: 0.5 }]; break;
        default:          defs = [{ v: [P(0, 0), P(W, 0)] }, { v: [P(0, H), P(W, H)] }]; break;
        }
        return defs.map(d => viz.buildPath(d, W, H));
    }

    /** Samples a polyline evenly by arc length (corners always sampled). */
    function buildPath(def, W, H) {
        const v = def.v;
        const segs = [];
        let L = 0;
        for (let i = 0; i < v.length - 1; i++) {
            const dx = v[i + 1].x - v[i].x, dy = v[i + 1].y - v[i].y;
            const len = Math.hypot(dx, dy);
            let nx = -dy / len, ny = dx / len;
            // Point the normal into the screen.
            const mx = (v[i].x + v[i + 1].x) / 2, my = (v[i].y + v[i + 1].y) / 2;
            if (nx * (W / 2 - mx) + ny * (H / 2 - my) < 0) { nx = -nx; ny = -ny; }
            segs.push({ a: v[i], dx: dx / len, dy: dy / len, len: len, nx: nx, ny: ny, at: L });
            L += len;
        }
        // Same spacing the original 20-point top/bottom wave had.
        const step = W / 19;
        const n = Math.max(1, Math.round(L / step));
        const pos = [];
        for (let k = 0; k <= n; k++)
            pos.push(k * L / n);
        // Interior corners: force a sample, drop uniform ones crowding it.
        // (svgFor also drops, per frame, any that the rounded corner's arc
        // currently overlaps — it reaches 2× the band height along each edge.)
        const clear = step * 0.35;
        const corners = segs.slice(1).map(sg => sg.at);
        const out = [];
        const segAt = d => {
            let j = 0;
            while (j < segs.length - 1 && d >= segs[j + 1].at) j++;
            return j;
        };
        const all = pos.filter(d => corners.every(c => Math.abs(d - c) > clear))
                       .concat(corners).sort((a, b) => a - b);
        for (const d of all) {
            const j = segAt(d);
            const sg = segs[j];
            const off = d - sg.at;
            const pt = { x: sg.a.x + sg.dx * off, y: sg.a.y + sg.dy * off,
                         nx: sg.nx, ny: sg.ny, t: L > 0 ? d / L : 0 };
            if (j > 0 && Math.abs(off) < 0.001) {
                // Corner: u = incoming edge's normal, w = outgoing edge's.
                pt.corner = true;
                pt.ux = segs[j - 1].nx; pt.uy = segs[j - 1].ny;
                pt.wx = sg.nx; pt.wy = sg.ny;
            }
            let cd = Infinity;
            for (const c of corners)
                cd = Math.min(cd, Math.abs(d - c));
            pt.at = d;
            pt.cd = cd;            // arc-length distance to the nearest corner
            pt.cnear = corners.length ? corners.reduce((b, c) => Math.abs(d - c) < Math.abs(d - b) ? c : b) : -1;
            out.push(pt);
        }
        return { verts: v, samples: out, sym: def.sym || "", closed: !!def.closed,
                 scale: def.scale || 1, taper: def.taper || 0 };
    }

    /** Spectrum laid out for a path; `alt` is the lower ridge's arrangement. */
    function arrange(levels, sym, alt) {
        const S = levels, R = levels.slice().reverse();
        if (sym === "u") return alt ? S.concat(R) : R.concat(S);
        if (sym === "loop") return alt ? R.concat(S) : S.concat(R);
        return alt ? R : S;
    }

    // Linear interpolation into `data` at fraction t (0..1).
    function sampleAt(data, t) {
        const p = Math.max(0, Math.min(1, t)) * (data.length - 1);
        const i = Math.floor(p);
        const f = p - i;
        return i + 1 < data.length ? data[i] * (1 - f) + data[i + 1] * f : data[i];
    }

    /**
     * SVG fill for one pass of the wave along `path`: the offset curve
     * (quadratic-smoothed through the samples, as the original did) closed back
     * along the screen edge — or, for a loop, the curve plus the screen rect
     * (filled even-odd → the band between). `stretch` widens the shadow pass
     * about the path's middle; `taper` eases open ends of bent paths to 0.
     */
    function svgFor(path, data, amp, stretch) {
        if (data.length < 2 || path.samples.length < 2)
            return "";
        const h = depth * path.scale * amp;
        const f = n => n.toFixed(1);
        const vals = path.samples.map(p => {
            let env = 1;
            if (path.taper > 0) {
                const e = Math.min(p.t, 1 - p.t) / path.taper;
                env = e >= 1 ? 1 : e * e * (3 - 2 * e);
            }
            return sampleAt(data, 0.5 + (p.t - 0.5) / stretch) * h * env;
        });
        const cornerVal = {};
        path.samples.forEach((p, i) => { if (p.corner) cornerVal[p.at] = vals[i]; });
        const pts = [];
        path.samples.forEach((p, i) => {
            const val = vals[i];
            if (!p.corner) {
                // Skip samples the rounded corner's arc currently covers.
                const cv = cornerVal[p.cnear];
                if (cv !== undefined && p.cd < 2.05 * cv)
                    return;
                pts.push({ x: p.x + p.nx * val, y: p.y + p.ny * val });
                return;
            }
            // Rounded inner corner, radius = band height: a quarter arc from
            // the incoming edge's offset line to the outgoing one, centred at
            // 2·val along both normals. Collapses into the corner at silence.
            const K = 8;
            for (let k = 0; k <= K; k++) {
                const th = (k / K) * Math.PI / 2;
                const a = val * (2 - Math.cos(th)), b = val * (2 - Math.sin(th));
                pts.push({ x: p.x + p.ux * a + p.wx * b, y: p.y + p.uy * a + p.wy * b });
            }
        });
        const sm = path.samples;
        let d = path.closed ? `M${f(pts[0].x)} ${f(pts[0].y)}`
                            : `M${f(sm[0].x)} ${f(sm[0].y)} L${f(pts[0].x)} ${f(pts[0].y)}`;
        for (let i = 0; i < pts.length - 1; i++) {
            const a = pts[i], b = pts[i + 1];
            d += ` Q${f(a.x)} ${f(a.y)} ${f((a.x + b.x) / 2)} ${f((a.y + b.y) / 2)}`;
        }
        const z = pts[pts.length - 1];
        d += ` L${f(z.x)} ${f(z.y)}`;
        if (path.closed)
            return d + ` Z M0 0 L${f(sw)} 0 L${f(sw)} ${f(sh)} L0 ${f(sh)} Z`;
        const last = sm[sm.length - 1];
        d += ` L${f(last.x)} ${f(last.y)}`;
        const vs = path.verts;
        for (let i = vs.length - 2; i >= 1; i--)
            d += ` L${f(vs[i].x)} ${f(vs[i].y)}`;
        return d + " Z";
    }

    /** Smoothed spectrum (0..1, bass→treble). */
    property var levels: []

    /** Must match `framerate` in the cava config below (the repaint cadence). */
    readonly property int cavaFps: 30

    Process {
        id: cavaProc
        running: true
        command: ["sh", "-c", `cava -p /dev/stdin <<EOF
[general]
bars = 20
framerate = 30
autosens = 1

[input]
method = pulse

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 1000
bar_delimiter = 59

[smoothing]
monstercat = 1.5
waves = 0
gravity = 100
noise_reduction = 0.20
EOF
`]

        stdout: SplitParser {
            onRead: data => {
                const target = data.split(";")
                    .map(p => parseFloat(p.trim()) / 1000)
                    .filter(p => !isNaN(p));
                if (target.length === 0)
                    return;

                const smoothFactor = 0.3;
                const cur = viz.levels;
                if (cur.length !== target.length) {
                    viz.levels = target;
                } else {
                    const smoothed = [];
                    for (let i = 0; i < target.length; i++)
                        smoothed.push(cur[i] + (target[i] - cur[i]) * smoothFactor);
                    viz.levels = smoothed;
                }

                // Colour ring rides the repaint beat. Reduce-motion holds it
                // still rather than running it faster (Motion.mult would
                // shorten the period — the opposite of calmer).
                if (Flags.vizColorCycle && !Motion.reduceMotion)
                    viz.cyclePhase += viz.colorRing.length / (viz.cycleSeconds * viz.cavaFps);

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

    /** Position in the ring, in ring-entries; read in onPaint, never bound. */
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
