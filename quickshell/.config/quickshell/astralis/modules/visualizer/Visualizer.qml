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

    // Own cava capture (20 bars, pulse) — spawned only while this window
    // exists, so density matches ~/shell. Each frame eases toward the target
    // with the reference's 0.3 smoothing factor before painting.
    Process {
        id: cavaProc
        // Gate on the flag AND visibility so cava never captures audio when the
        // visualizer is off or off-screen (mirrors the Cava.qml `wanted` gate).
        running: musicVis.visible && Flags.musicViz
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

                canvas.requestPaint();
            }
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        property var cavaData: []

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            // Backmost first: the lower mirrored ridge (its own deeper-purple
            // gradient so it stays distinct), then the main wave's shadow, then
            // the main wave itself.
            drawMountainWave(ctx, cavaData, { amp: 0.65, alpha: 0.5, mirror: true,
                                              stops: [Colors.tertiary, Colors.tertiary_container, Colors.secondary] });
            drawMountainWave(ctx, cavaData, { shadow: true });
            drawMountainWave(ctx, cavaData, {});
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
