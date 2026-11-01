import QtQuick
import "../colors"
import "../services"

/**
 * astralis — 筆 ink-brush progress stroke, shared by the Media surface and the
 * lock screen. Played time is a sumi stroke: a pressed entry blob (起筆), a body
 * whose width breathes with the brush (keyed to absolute x, so the texture
 * never swims as it grows), a faint bleed into the paper (滲み), and a dry-brush
 * head (掠れ) that splits into bristle streaks. `wet` 0 dries the ink toward
 * `paper` (paused). The unplayed rest is a washi hairline with quarter nodes
 * and a closing tome mark. Ame rides `headX`/`headY`.
 */
Canvas {
    id: ink

    property real s: 1
    /** Played fraction, 0..1. */
    property real frac: 0
    /** Background the dried ink fades toward. */
    property color paper: Colors.surface_container
    /** Glide the head between position samples (off under reduce-motion). */
    property bool glide: true

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    /** Half the body thickness at rest pressure. */
    readonly property real halfW: 2.4 * ink.s
    readonly property real inset: halfW + 2 * ink.s
    readonly property real usable: Math.max(1, width - 2 * inset)
    /** Ink wetness: 1 playing (full primary), eases toward 0 (dried, dimmer) on pause. */
    property real wet: 1
    Behavior on wet {
        NumberAnimation {
            duration: Motion.expressiveDefaultSpatialDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveDefaultSpatial
        }
    }

    property real targetF: ink.frac
    property real lastFrac: 0
    property real drawF: targetF
    readonly property real headX: inset + drawF * usable
    readonly property real headY: height / 2

    Behavior on drawF {
        enabled: ink.glide && Math.abs(ink.frac - ink.lastFrac) < 0.02
        NumberAnimation { duration: Math.round(500 * Motion.mult); easing.type: Easing.Linear }
    }
    onTargetFChanged: Qt.callLater(() => { ink.lastFrac = ink.frac; })

    onWetChanged: requestPaint()
    onDrawFChanged: requestPaint()
    onWidthChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    /**
     * Optional colour ramp laid along the whole track (left → right): the
     * stroke reveals more of it as frac grows, so the head's hue reads the level.
     * Empty = flat `inkColor`.
     */
    property var inkStops: []
    onInkStopsChanged: requestPaint()

    readonly property color inkColor: Colors.primary
    readonly property color paperColor: Colors.on_surface_variant
    onInkColorChanged: requestPaint()
    onPaperColorChanged: requestPaint()

    /** Brush pressure at x: entry press, then a slow uneven breath (unitless, ~1). */
    function pressure(x) {
        const u = (x - inset) / ink.s;
        const press = 0.45 * Math.exp(-u / 7);
        const breath = 0.14 * Math.sin(u / 11.3) + 0.07 * Math.sin(u / 4.1 + 1.7);
        return 1 + press + breath;
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (width <= 0 || height <= 0)
            return;
        const mid = height / 2;
        const s = ink.s;
        const end = inset + usable;
        const len = headX - inset;
        // dried ink mixes toward the paper rather than going translucent,
        // so overlapping body/bristle passes never stack into seams
        const inkC = ink.mix(inkColor, ink.paper, 0.45 * (1 - wet));
        // gradient ink when a ramp is set; same dry-ink mix applied per stop
        let inkFill = inkC;
        if (inkStops && inkStops.length > 1) {
            inkFill = ctx.createLinearGradient(inset, 0, end, 0);
            for (let i = 0; i < inkStops.length; i++)
                inkFill.addColorStop(i / (inkStops.length - 1), ink.mix(inkStops[i], ink.paper, 0.45 * (1 - wet)));
        }

        // washi hairline: from just past the head to the end
        const tStart = headX + 4 * s;
        if (end - tStart > 0.5) {
            ctx.fillStyle = Qt.alpha(paperColor, 0.3);
            ctx.fillRect(tStart, mid - 0.5 * s, end - tStart, 1 * s);
        }
        // quarter nodes (節) on the unplayed hairline
        ctx.fillStyle = Qt.alpha(paperColor, 0.45);
        for (let q = 1; q <= 3; q++) {
            const nx = inset + q / 4 * usable;
            if (nx > tStart + 2 * s)
                ctx.fillRect(nx - 0.5 * s, mid - 2.5 * s, 1 * s, 5 * s);
        }
        // closing tome mark, gone once the stroke reaches it
        if (end - headX > 6 * s) {
            ctx.fillStyle = Qt.alpha(inkColor, 0.4 + 0.3 * wet);
            ctx.fillRect(end - 1 * s, mid - 4 * s, 2 * s, 8 * s);
        }
        if (len < 0.5)
            return;

        // dry-brush zone length at the head
        const dry = Math.min(22 * s, len * 0.45);
        const bodyEnd = headX - dry;
        const step = Math.max(1, s);

        // body polygon: top edge forward, bottom edge back; `tip` > bodyEnd
        // runs the outline on to a point (used by the bleed so it fades
        // into the dry zone instead of ending square)
        function bodyPath(scale, tip) {
            ctx.beginPath();
            const r0 = halfW * pressure(inset) * scale;
            ctx.arc(inset, mid, r0, Math.PI / 2, 3 * Math.PI / 2);
            for (let x = inset; x <= bodyEnd; x += step)
                ctx.lineTo(x, mid - halfW * pressure(x) * scale);
            ctx.lineTo(bodyEnd, mid - halfW * pressure(bodyEnd) * scale);
            ctx.lineTo(tip, mid);
            ctx.lineTo(bodyEnd, mid + halfW * pressure(bodyEnd) * scale * 0.92);
            for (let x = bodyEnd; x >= inset; x -= step)
                ctx.lineTo(x, mid + halfW * pressure(x) * scale * 0.92);
            ctx.closePath();
        }

        // 滲み bleed into the paper, then the ink body
        ctx.globalAlpha = 0.13;
        ctx.fillStyle = inkFill;
        bodyPath(1.9, bodyEnd + dry * 0.8);
        ctx.fill();
        ctx.globalAlpha = 1;
        bodyPath(1, bodyEnd);
        ctx.fill();

        // 掠れ dry-brush head: separate bristle streaks, the outer ones
        // broken where the brush ran out of ink
        const p = pressure(bodyEnd);
        const bristles = [
            { o: -0.9,  w: 0.7, a: 0.55, segs: [[0, 0.3], [0.45, 0.6]] },
            { o: -0.4,  w: 1.1, a: 0.9,  segs: [[0, 0.95]] },
            { o:  0.12, w: 1.3, a: 1.0,  segs: [[0, 1.0]] },
            { o:  0.62, w: 0.9, a: 0.75, segs: [[0, 0.5], [0.62, 0.78]] },
            { o:  1.0,  w: 0.6, a: 0.45, segs: [[0, 0.22]] }
        ];
        ctx.lineCap = "round";
        for (const b of bristles) {
            if (inkFill === inkC) {
                ctx.strokeStyle = b.a < 1 ? ink.mix(inkC, ink.paper, 1 - b.a) : inkC;
            } else {
                ctx.strokeStyle = inkFill;
                ctx.globalAlpha = b.a;
            }
            ctx.lineWidth = b.w * s;
            for (const sg of b.segs) {
                // bristles drift a little toward centre as they run out
                const xa = bodyEnd + dry * sg[0], xb = bodyEnd + dry * sg[1];
                const ya = mid + b.o * halfW * p * (1 - 0.3 * sg[0]);
                const yb = mid + b.o * halfW * p * (1 - 0.3 * sg[1]);
                ctx.beginPath();
                ctx.moveTo(sg[0] === 0 ? xa - 1 : xa, ya);
                ctx.lineTo(xb, yb);
                ctx.stroke();
            }
        }
        ctx.globalAlpha = 1;
    }
}
