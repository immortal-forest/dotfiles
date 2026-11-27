import QtQuick
import QtQuick.Shapes
import "lib/inkdots.js" as Ink
import "../colors"
import "../services"

/**
 * astralis — the obscured password as sumi dabs.
 *
 * Shared by every place the shell takes a secret: the lock screen capsule,
 * the 認 polkit prompt and the 鍵 GnuPG pinentry. Each typed character is one
 * brush dab — a 点, light entry tail at the upper left, pressed head at the
 * lower right — and every dab is a little different (lib/inkdots.js, seeded
 * per slot and per attempt). The shell's 筆 ink motif (InkStroke) at the size
 * of a bullet. Two looks were tried here first and rejected by the user:
 * Pixel-style shapes ("odd for the material + jp/pill vibe") and dots with
 * an accent stick ("I don't want workspace dots in the pinentry").
 *
 * Motion:
 *  - type: the dab blooms out of a pinpoint (springing a touch past full),
 *    a faint bleed spreads out from it and fades — ink taking to paper —
 *    and it dries from a wet accent tint to the ink colour.
 *  - backspace: the last dab shrinks away. The run re-centres by gliding.
 *  - `busy` (being checked): a slow ripple runs along the dabs, each one
 *    swelling and catching the accent as it passes (one FrameAnimation,
 *    only while busy).
 *  - `error`: the ink turns the error colour; when the host then empties
 *    the field the run washes out, right to left, a few ms apart.
 *  - `success`: the accent sweeps left to right through the run.
 *  - past the field's width the run scrolls (oldest dabs fade out on the
 *    left) instead of compressing.
 *
 * Built on a CONSTANT pool of delegates gated by `index < count`: any change
 * to a Repeater's model count re-creates every delegate, which re-ran every
 * entrance on every keystroke (see the lock screen history).
 */
Item {
    id: root

    property real s: 1
    /** Typed length. */
    property int count: 0
    property bool busy: false
    property bool error: false
    property bool success: false
    property color ink: Colors.on_surface
    property color accent: Colors.primary
    /** One dab's box, and the air between dabs. */
    property real dot: 13 * s
    property real gap: 5 * s
    /** Motion gate (reduce-motion). */
    property bool animate: !Motion.reduceMotion
    /** Slots built once (more than any real password). */
    property int pool: 64
    /** "center" re-centres the run as it grows; "left" types like a field. */
    property string align: "center"

    /** Re-dealt each time the field empties, so every attempt gets new dabs. */
    property int salt: Math.floor(Math.random() * 100000)

    readonly property int shown: Math.min(count, pool)
    readonly property real pitch: dot + gap
    /** Width of a run of n characters — hosts size themselves by it. */
    function naturalWidth(n) {
        return n > 0 ? (n - 1) * root.pitch + root.dot : 0;
    }
    readonly property int fits: Math.max(1, Math.floor((width - dot) / pitch) + 1)
    readonly property bool overflowing: shown > fits
    readonly property real runWidth: shown > 0 ? (Math.min(shown, fits) - 1) * pitch + dot : 0
    readonly property real liveStart: overflowing
        ? width - naturalWidth(shown)
        : (align === "left" ? 0 : (width - runWidth) / 2)
    // Frozen while the field empties, so a clearing or washing-out run
    // doesn't drift sideways as the (now empty) run re-centres under it.
    property real lastStart: 0
    onLiveStartChanged: if (shown > 0) lastStart = liveStart
    readonly property real start: shown > 0 ? liveStart : lastStart

    function firstShownIndex() {
        return root.overflowing ? root.shown - root.fits : 0;
    }

    implicitHeight: dot * 2.4
    implicitWidth: runWidth

    // ── the ripple while busy ───────────────────────────────────────────
    property real phase: 0
    property real waveAmt: busy && animate ? 1 : 0
    Behavior on waveAmt {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }
    FrameAnimation {
        running: root.waveAmt > 0.001 && root.visible
        onTriggered: root.phase += frameTime * 6 / Motion.slowmo
    }

    /** Run length before the field emptied: the wash-out counts from its right end. */
    property int lastShown: 0
    property int fallFrom: 0
    onShownChanged: {
        if (root.shown === 0) {
            if (root.error)
                root.fallFrom = root.lastShown;
            root.salt = Math.floor(Math.random() * 100000);
        }
        root.lastShown = root.shown;
    }

    Repeater {
        model: root.pool   // constant — never re-instantiates the delegates

        delegate: Item {
            id: d
            required property int index

            readonly property bool want: d.index < root.shown
            property int seed: 0
            property real tilt: 0

            // scrolled off the left when the run overflows
            readonly property int rank: root.shown - 1 - d.index
            property real keep: !root.overflowing || d.rank < root.fits - 1 ? 1
                : (d.rank === root.fits - 1 ? 0.4 : 0)
            Behavior on keep {
                enabled: root.animate
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }

            property real a: 0      // presence (springs a touch past 1 on the way in)
            property real bleed: 1  // 0 → 1 as the halo spreads and fades
            property real wet: 0    // 1 fresh → 0 dry
            property real fall: 0   // error wash-out
            property real glow: 0   // success sweep

            readonly property real crest: root.waveAmt
                * Math.pow(Math.max(0, Math.sin(root.phase - d.index * 0.7)), 3)

            width: root.dot
            height: root.dot
            x: root.start + d.index * root.pitch
            Behavior on x {
                enabled: root.animate
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }
            y: (root.height - height) / 2 - d.crest * root.dot * 0.18 + d.fall * root.dot * 1.6
            visible: (d.a > 0.002 || d.fall > 0) && d.keep > 0.002
            opacity: Math.min(1, Math.max(0, d.a)) * d.keep * (1 - d.fall)
            scale: (0.3 + 0.7 * Math.max(0, d.a)) * (1 + d.crest * 0.16 + d.glow * 0.1)
            rotation: d.tilt + (1 - Math.min(1, Math.max(0, d.a))) * -18


            Component.onCompleted: if (d.want) { d.seed = d.index * 7919 + root.salt; d.a = 1; }
            onWantChanged: {
                if (d.want) {
                    fallAnim.stop();
                    outAnim.stop();
                    d.fall = 0;
                    d.seed = d.index * 7919 + root.salt;
                    d.tilt = Ink.tilt(d.seed);
                    if (!root.animate) {
                        d.a = 1;
                        d.bleed = 1;
                        d.wet = 0;
                        return;
                    }
                    inAnim.restart();
                } else {
                    inAnim.stop();
                    if (!root.animate) {
                        d.a = 0;
                        return;
                    }
                    if (root.error && root.shown === 0 && d.a > 0.01) {
                        fallPause.duration = Math.round(Math.max(0, root.fallFrom - 1 - d.index) * 30 * Motion.mult);
                        fallAnim.restart();
                    } else {
                        outAnim.restart();
                    }
                }
            }

            ParallelAnimation {
                id: inAnim
                NumberAnimation {
                    target: d; property: "a"; from: 0; to: 1
                    duration: Motion.expressiveFastSpatialDur
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
                NumberAnimation {
                    target: d; property: "bleed"; from: 0; to: 1
                    duration: Motion.largeDur
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.emphasizedDecel
                }
                NumberAnimation {
                    target: d; property: "wet"; from: 1; to: 0
                    duration: Math.round(Motion.largeDur * 1.3)
                    easing.type: Motion.easeStandard
                }
            }
            NumberAnimation {
                id: outAnim
                target: d; property: "a"; to: 0
                duration: Motion.smallDur
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.emphasizedAccel
            }
            SequentialAnimation {
                id: fallAnim
                PauseAnimation { id: fallPause; duration: 0 }
                NumberAnimation {
                    target: d; property: "fall"; to: 1
                    duration: Motion.standard
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.emphasizedAccel
                }
                ScriptAction { script: { d.a = 0; d.fall = 0; } }
            }

            // success: the accent runs left to right through the run
            Connections {
                target: root
                function onSuccessChanged() {
                    if (root.success && d.want && root.animate) {
                        glowPause.duration = Math.round(Math.max(0, d.index - root.firstShownIndex()) * 28 * Motion.mult);
                        glowAnim.restart();
                    } else if (!root.success) {
                        glowAnim.stop();
                        d.glow = 0;
                    }
                }
            }
            SequentialAnimation {
                id: glowAnim
                PauseAnimation { id: glowPause; duration: 0 }
                NumberAnimation {
                    target: d; property: "glow"; to: 1
                    duration: Motion.standard
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            // the bleed: the same dab, spreading into the paper and fading
            Shape {
                width: 24
                height: 24
                scale: root.dot / 24 * (1 + 0.6 * d.bleed)
                transformOrigin: Item.TopLeft
                x: -(scale * 24 - root.dot) / 2
                y: -(scale * 24 - root.dot) / 2
                visible: d.bleed < 0.99 && !root.error
                opacity: 0.32 * (1 - d.bleed)
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.accent
                    PathSvg { path: Ink.dab(d.seed) }
                }
            }
            // The dab itself, painted as ink once per seed/colour: a soft bleed
            // into the paper, dry at the entry and dense at the pressed head,
            // with bristle gaps (掠れ) where the brush touched down.
            Canvas {
                id: inkCv
                readonly property real pad: root.dot * 0.3
                x: -pad
                y: -pad
                width: root.dot + 2 * pad
                height: root.dot + 2 * pad
                readonly property color inkColor: root.error ? Colors.error : root.ink
                onInkColorChanged: requestPaint()
                Connections {
                    target: d
                    function onSeedChanged() { inkCv.requestPaint(); }
                }
                onWidthChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    if (d.seed === 0 && !d.want)
                        return;
                    const sh = Ink.shape(d.seed);
                    const k = root.dot / 24;
                    const c = inkCv.inkColor;
                    // Canvas wants CSS colour strings (a QML colour serialises #aarrggbb)
                    const rgba = a => "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                        + Math.round(c.b * 255) + "," + a + ")";
                    const outline = () => {
                        const p = sh.pts;
                        ctx.beginPath();
                        ctx.moveTo(p[0][0], p[0][1]);
                        for (let i = 1; i < p.length; i++)
                            ctx.lineTo(p[i][0], p[i][1]);
                        ctx.closePath();
                    };
                    ctx.save();
                    ctx.translate(inkCv.pad, inkCv.pad);
                    ctx.scale(k, k);

                    // 1. the bleed: a soft edge where the ink took to the paper
                    ctx.shadowColor = rgba(0.55);
                    ctx.shadowBlur = 2.4 * root.s;
                    ctx.fillStyle = rgba(0.3);
                    outline();
                    ctx.fill();
                    ctx.shadowBlur = 0;
                    ctx.shadowColor = "rgba(0,0,0,0)";

                    // 2. the body: thin at the touch-down, full at the press
                    const g = ctx.createLinearGradient(sh.tip[0], sh.tip[1], sh.head[0], sh.head[1]);
                    g.addColorStop(0, rgba(0.42));
                    g.addColorStop(0.5, rgba(0.88));
                    g.addColorStop(1, rgba(1));
                    ctx.fillStyle = g;
                    outline();
                    ctx.fill();

                    // 3. dry brush: bristle gaps running in from the entry
                    ctx.save();
                    outline();
                    ctx.clip();
                    ctx.globalCompositeOperation = "destination-out";
                    ctx.lineCap = "round";
                    const nx = -sh.dir[1], ny = sh.dir[0];
                    const half = 6.5;
                    const bs = Ink.bristles(d.seed);
                    for (let i = 0; i < bs.length; i++) {
                        const b = bs[i];
                        const x0 = sh.tip[0] + sh.dir[0] * sh.len * b.from + nx * b.off * half;
                        const y0 = sh.tip[1] + sh.dir[1] * sh.len * b.from + ny * b.off * half;
                        const x1 = sh.tip[0] + sh.dir[0] * sh.len * b.to + nx * b.off * half * 1.25;
                        const y1 = sh.tip[1] + sh.dir[1] * sh.len * b.to + ny * b.off * half * 1.25;
                        const sg = ctx.createLinearGradient(x0, y0, x1, y1);
                        sg.addColorStop(0, "rgba(0,0,0,0.7)");
                        sg.addColorStop(1, "rgba(0,0,0,0)");
                        ctx.strokeStyle = sg;
                        ctx.lineWidth = b.w;
                        ctx.beginPath();
                        ctx.moveTo(x0, y0);
                        ctx.lineTo(x1, y1);
                        ctx.stroke();
                    }
                    ctx.restore();
                    ctx.restore();
                }
            }

            // Wet / checking / accepted: the accent laid over the ink.
            Shape {
                width: 24
                height: 24
                scale: root.dot / 24
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer
                readonly property real amt: root.error ? 0
                    : Math.min(1, Math.max(d.wet * 0.55, d.crest * 0.7, d.glow * 0.8))
                visible: amt > 0.01
                opacity: amt
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.accent
                    PathSvg { path: Ink.dab(d.seed) }
                }
            }
        }
    }
}
