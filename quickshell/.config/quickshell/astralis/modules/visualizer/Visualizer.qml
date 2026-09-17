import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../../colors"
import "../../services"

/**
 * astralis — full-screen music visualizer (ported from ~/shell
 * components/Visualizer.qml). A transparent, click-through layer-shell window
 * on WlrLayer.Bottom that draws a smoothed quadratic-spline "mountain wave"
 * from the shared Cava singleton, filled with a primary→tertiary→secondary
 * linear gradient plus a translated/scaled shadow pass at 0.25 alpha.
 *
 * A third, LOWER background wave is drawn behind the shadow + main: it reuses
 * the same spectrum but MIRRORED (data read right-to-left) at ~0.65 amplitude,
 * so its crests land in the main wave's valleys and peek through instead of
 * hiding directly beneath it. It carries its OWN deeper-purple gradient (via the
 * pass's `stops`) so the shorter ridge stays differentiable from the other two.
 *
 * Faithful to ~/shell, this spawns its OWN cava (20 bars, pulse, 30fps) that
 * runs only while the window exists (the shell.qml Loader is gated on
 * vizEnabled), so the wave keeps the reference's 20-point density rather than
 * the 5-bar rest-pill singleton. Frame-to-frame smoothing
 * (shown += (target - shown) * 0.3) flows it.
 *
 * The two visualizers are deliberately INDEPENDENT: this one is runtime-only,
 * owned by `vizEnabled` (Super+B / `ipc call visualizer toggle`); the rest-pill
 * spectrum is the persisted `Flags.musicViz` setting driving the shared Cava
 * singleton. Neither switch touches the other.
 *
 * `anchorBottom: false` flips the wave to hang from the top edge, so shell.qml
 * mounts a mirrored bottom+top pair per screen.
 */
PanelWindow {
    id: musicVis

    property bool anchorBottom: true
    property bool flipped: !anchorBottom
    property real s: 1

    implicitHeight: Math.round(200 * s)
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "astralis-viz"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        left: true
        right: true
        bottom: anchorBottom
        top: !anchorBottom
    }

    /** Must match `framerate` in the cava config below (the repaint cadence). */
    readonly property int cavaFps: 30

    // Own cava capture (20 bars, pulse) — spawned only while this window
    // exists, so density matches ~/shell. Each frame eases toward the target
    // with the reference's 0.3 smoothing factor before painting.
    Process {
        id: cavaProc
        // Visibility is the ONLY gate: this window is created by a Loader that
        // shell.qml keeps on `vizEnabled`, so being mapped already means the
        // full-screen visualizer was switched on (Super+B / `ipc call visualizer
        // toggle`). It must NOT also read Flags.musicViz — that flag is the
        // rest-pill spectrum's own switch (services/Cava.qml `wanted`), and
        // sharing it meant turning the pill bars off in Settings silently
        // starved this window's cava too, leaving the full-screen wave flat.
        running: musicVis.visible
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

                if (canvas.cavaData.length === 0
                    || canvas.cavaData.length !== target.length) {
                    canvas.cavaData = target;
                } else {
                    const smoothed = [];
                    for (let i = 0; i < target.length; i++)
                        smoothed.push(canvas.cavaData[i] + (target[i] - canvas.cavaData[i]) * smoothFactor);
                    canvas.cavaData = smoothed;
                }

                // Advance the colour ring on the same beat as the repaint (see
                // `cyclePhase`). Reduce-motion holds the gradient still rather
                // than running it faster — Motion.mult would shorten the period,
                // which is the opposite of what a calmer setting should do.
                if (Flags.vizColorCycle && !Motion.reduceMotion)
                    musicVis.cyclePhase += musicVis.colorRing.length
                        / (musicVis.cycleSeconds * musicVis.cavaFps);

                canvas.requestPaint();
            }
        }
    }

    /**
     * Colour cycle (Settings → Appearance → "Visualizer colour cycle"). Off,
     * the two ridges hold their fixed matugen triples. On, both walk this ring
     * of wallpaper-derived roles, so the wave drifts through the whole palette
     * instead of holding one gradient.
     *
     * The order alternates a bright accent with a deep container on purpose.
     * matugen palettes are hue-COHERENT — on the wallpaper this was tuned
     * against, every accent sits between 13 and 35 degrees — so rotating hue
     * alone would be nearly invisible. TONE is what reads as movement, and
     * since the gradient samples one ring entry apart, an alternating ring
     * means the wave always carries a bright→deep ramp whose hues rotate under
     * it. Roles the palette collapses onto one value are dropped: primary,
     * primary_fixed_dim and surface_tint are frequently identical, and a
     * duplicate entry is a dead beat in the cycle.
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

    /**
     * Position in the ring, in ring-entries. Advanced by the cava frame handler
     * rather than by an animation on purpose: that handler already calls
     * requestPaint at cava's 30fps, so the gradient rides repaints that were
     * happening anyway instead of forcing this three-pass Canvas to redraw at
     * the panel's 165Hz. `cyclePhase` is read inside onPaint, never bound to,
     * so advancing it costs nothing until the next frame lands.
     */
    property real cyclePhase: 0
    /** Seconds for one full trip around the ring. */
    readonly property real cycleSeconds: 42

    /** Ring colour at a fractional index, wrapped and blended between entries. */
    function ringColor(at) {
        const n = musicVis.colorRing.length;
        const p = ((at % n) + n) % n;
        const i = Math.floor(p);
        return Qt.tint(musicVis.colorRing[i],
                       Qt.alpha(musicVis.colorRing[(i + 1) % n], p - i));
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        property var cavaData: []

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            // The two ridges sit a third of the ring apart so the lower one
            // stays differentiable from the main wave all the way round, the
            // same job the fixed deeper-purple triple does when cycling is off.
            var cycling = Flags.vizColorCycle;
            var lowStops = cycling
                ? [musicVis.ringColor(musicVis.cyclePhase + 2),
                   musicVis.ringColor(musicVis.cyclePhase + 2.5),
                   musicVis.ringColor(musicVis.cyclePhase + 3)]
                : [Colors.tertiary, Colors.tertiary_container, Colors.secondary];
            var mainStops = cycling
                ? [musicVis.ringColor(musicVis.cyclePhase),
                   musicVis.ringColor(musicVis.cyclePhase + 0.5),
                   musicVis.ringColor(musicVis.cyclePhase + 1)]
                : undefined;

            // Backmost first: the lower mirrored ridge (its own deeper-purple
            // gradient so it stays distinct), then the main wave's shadow, then
            // the main wave itself.
            drawMountainWave(ctx, cavaData, { amp: 0.65, alpha: 0.5, mirror: true,
                                              stops: lowStops });
            drawMountainWave(ctx, cavaData, { shadow: true });
            drawMountainWave(ctx, cavaData, { stops: mainStops });
        }

        function drawMountainWave(ctx, data, opts) {
            if (data.length < 2)
                return;

            var amp = opts.amp !== undefined ? opts.amp : 1.0;
            var n = data.length;
            // Sampled level for index i (mirrored → read right-to-left), scaled
            // by this pass's amplitude.
            function v(i) {
                var idx = opts.mirror ? (n - 1 - i) : i;
                return data[idx] * amp;
            }
            // y for index i, honouring flip (base at top vs bottom).
            function yAt(i) {
                return musicVis.flipped ? (v(i) * height) : (height - v(i) * height);
            }

            var gradient = ctx.createLinearGradient(0, 0, width, height);

            // Canvas gradients need "#rrggbb" strings; a raw QML color
            // serializes as #aarrggbb and corrupts the stops. `opts.stops` lets a
            // pass (the low mirrored wave) carry a distinct gradient.
            var stops = opts.stops || [Colors.primary, Colors.tertiary, Colors.secondary];
            gradient.addColorStop(0.0, String(stops[0]));
            gradient.addColorStop(0.5, String(stops[1]));
            gradient.addColorStop(1.0, String(stops[2]));

            ctx.beginPath();

            if (opts.shadow) {
                ctx.globalAlpha = opts.alpha !== undefined ? opts.alpha : 0.25;
                ctx.save();
                ctx.translate(0, musicVis.flipped ? 10 : -10);
                ctx.scale(1.02, 1.05);
            } else {
                ctx.globalAlpha = opts.alpha !== undefined ? opts.alpha : 1.0;
            }

            ctx.fillStyle = gradient;

            // For flipped: base is at top (y=0), waves grow downward
            // For normal: base is at bottom (y=height), waves grow upward
            var baseY = musicVis.flipped ? 0 : height;

            ctx.moveTo(0, baseY);
            ctx.lineTo(0, yAt(0));

            var barWidth = width / (n - 1);

            for (var i = 0; i < n - 1; i++) {
                var xCurr = i * barWidth;
                var yCurr = yAt(i);

                var xNext = (i + 1) * barWidth;
                var yNext = yAt(i + 1);

                var xMid = (xCurr + xNext) / 2;
                var yMid = (yCurr + yNext) / 2;

                ctx.quadraticCurveTo(xCurr, yCurr, xMid, yMid);
            }

            var lastX = (n - 1) * barWidth;
            ctx.lineTo(lastX, yAt(n - 1));
            ctx.lineTo(width, baseY);
            ctx.closePath();
            ctx.fill();

            if (opts.shadow)
                ctx.restore();
        }
    }
}
