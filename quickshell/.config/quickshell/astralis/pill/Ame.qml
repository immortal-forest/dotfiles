pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../colors"
import "../services"

/**
 * 飴 Ame, the shapeshifter. One molten-glass bead, the shell's only glowing
 * element. Idle it just breathes (2.5% scale over ~8s). No music/audio/physics
 * coupling; every motion is a fixed, scripted timeline.
 *
 * Travel: a form change runs the full shapeshift over `Motion.shapeshift` ms.
 * anticipation stretch, a remnant droplet pinching off at the origin, a
 * quadratic-bezier flight with a tapered streak, a three-droplet landing splash,
 * then an easeOutBack settle into the new form. The flight launches once and
 * tracks a moving target live (bezier endpoint, control point and heading
 * recomputed per frame), so anchors that slide with the pill's 320ms morph bend
 * the arc, no restart. Short-distance form change skips travel and plays the
 * settle in place. Same-form target moves (hover width, seam progress, mixer
 * focus hops, seeks) glide over `Motion.glide` ms, chasing the anchor, never
 * escalating to a flight.
 *
 * Forms: "rest" breathing bead, "caret" blinking launcher capsule, "seam" media
 * bead, "soul" wicked candle bead, "tick" flattened clock-tick bead, "rowseam"
 * tall seam bar, "ring" calendar ring, "dock" plain bead (mixer/power/link),
 * "off" hidden. Entering "off" fades out over `Motion.fast` ms; leaving it snaps to
 * the current anchor and pops back with the settle, so toast/OSD handoffs don't
 * ghost-fly from stale positions. Body draws on a QtQuick Canvas: FrameAnimation
 * drives full-rate repaint only while the timeline, splash, remnant or a glide
 * is live; otherwise a Timer ticks the slow inner swirl at 12fps (30fps while
 * the caret blinks) to keep idle cost low for a 24/7 shell.
 *
 * astralis port (addendum A.7): the only change from Ricelin is the color
 * tokens — the vermilion Theme ramp becomes the matugen tertiary ramp, so the
 * bead recolors with the wallpaper and glows deliberately off the primary tint
 * of the pill body / workspace stick. Canvas gotcha: addColorStop/strokeStyle
 * need "#rrggbb" STRINGS (a QML color serializes #aarrggbb and corrupts the
 * gradient), so the tokens below keep a color-typed copy for derivation and a
 * String() copy the canvas reads.
 *
 * One addition on top of the port: the host's `point` is a REQUEST. It is
 * clamped into `anchor` by the current form's own painted extent, so no caller
 * can park the flame where this Canvas would cut it off (see `inkHalf`).
 */
Item {
    id: root

    property real s: 1
    property point point: Qt.point(0, 0)
    property string form: "rest"
    property real heat: 0
    property point wake: Qt.point(0, 0)
    property real wickDir: -1

    // ── matugen tertiary ramp (the only Ricelin change) ─────────────────────
    // flameInk → beadCore (hot ember core), vermLit → beadLit, verm → beadMid,
    // flameEmber → beadEmber (edge), flameBurn/flameTip → swirl strokes.
    readonly property color beadCoreC:  Qt.lighter(Colors.tertiary, 1.35)
    readonly property color beadLitC:   Colors.tertiary
    readonly property color beadMidC:   Qt.darker(Colors.tertiary, 1.12)
    readonly property color beadEmberC: Qt.darker(Colors.tertiary, 1.40)
    readonly property color swirlBurnC: Colors.tertiary_container
    readonly property color swirlTipC:  Qt.lighter(Colors.tertiary, 1.2)
    readonly property string beadCore:  String(beadCoreC)
    readonly property string beadLit:   String(beadLitC)
    readonly property string beadMid:   String(beadMidC)
    readonly property string beadEmber: String(beadEmberC)
    readonly property string swirlBurn: String(swirlBurnC)
    readonly property string swirlTip:  String(swirlTipC)
    function rgbaStr(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                       + Math.round(c.b * 255) + "," + a + ")";
    }
    onBeadLitCChanged: canvas.requestPaint()   // matugen retheme repaints the bead

    opacity: form === "off" ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    visible: opacity > 0.001

    readonly property real restR: 5 * s
    readonly property real heatScale: 1 - 0.4 * heat
    readonly property real flightThreshold: 30 * s
    readonly property real pAntic: 0.146
    readonly property real pFly: 0.658

    /**
     * Half the painted footprint of the REQUESTED form, read straight off the
     * renderers in onPaint (width, height), each with the settle's easeOutBack
     * overshoot folded in. Keyed off `form` — what the host asked for — never
     * `activeForm`: activeForm is written from inside decide(), which the
     * anchor below feeds, so reading it here would let the anchor chase its
     * own transition.
     */
    readonly property size inkHalf: {
        switch (form) {
        case "off":     return Qt.size(0, 0);
        case "soul":    return Qt.size(3 * s, 3 * s);    // the bead alone — the wick is one-sided, below
        case "seam":    return Qt.size(5 * s, 5 * s);    // R at its widest, before the fade-in tightens it
        case "tick":    return Qt.size(6 * s, 4 * s);    // the flattened rx/ry pair
        case "caret":   return Qt.size(5 * s, 9 * s);    // half the 15·s capsule, half its widest 8.5·s
        case "rowseam": return Qt.size(3 * s, 11 * s);   // half the 18·s bar
        case "ring":    return Qt.size(20 * s, 20 * s);  // (restR + 6 + 5)·s plus half the fat stroke
        default:        return Qt.size(6 * s, 6 * s);    // rest/dock bead: restR plus the land overshoot
        }
    }

    /**
     * The soul form is the one asymmetric renderer: its wick leaves the bead
     * on the `wickDir` side and runs a further 1.5·s gap + 7·s length + the
     * round cap's half line width (0.55·s) ≈ 9·s, so a soul ember needs ~12·s
     * of headroom on that side and only a bead's radius on the other.
     */
    readonly property real inkUp: inkHalf.height + (form === "soul" && wickDir < 0 ? 9 * s : 0)
    readonly property real inkDown: inkHalf.height + (form === "soul" && wickDir > 0 ? 9 * s : 0)

    /**
     * The anchor Ame actually flies to and rests on: `point` pulled far enough
     * inside this item for the whole form to be painted. The Canvas below is
     * anchors.fill of the pill, so ink past an edge is silently cut — a
     * surface anchoring the flame to its header (a kanji sits barely 12·s
     * below the pill's top edge) lost its entire wick that way, leaving a bare
     * dot glued to the border. Clamping HERE rather than in each surface means
     * every surface, present and future, gets the guarantee for free, and it
     * is a no-op for any anchor that already has headroom — a deliberate
     * dock-against-the-bottom-edge point is left exactly where it was put.
     * (Only the box is respected, not the body's corner radius; no anchor
     * lives in a corner, and rounding this would cost a per-corner solve.)
     */
    readonly property point anchor: {
        // Before the first layout there is no box to clamp against.
        if (width <= 0 || height <= 0)
            return point;
        const loX = inkHalf.width;
        const hiX = width - inkHalf.width;
        const loY = inkUp;
        const hiY = height - inkDown;
        return Qt.point(hiX < loX ? width / 2 : Math.max(loX, Math.min(hiX, point.x)),
                        hiY < loY ? height / 2 : Math.max(loY, Math.min(hiY, point.y)));
    }

    property real bx: 0
    property real by: 0
    property string activeForm: "rest"
    property bool hidden: false
    property bool arcFlip: false
    property bool quickFlight: false
    property point lastTarget: Qt.point(0, 0)

    property real prog: 1
    property string phase: "idle"
    property point fromPoint: Qt.point(0, 0)
    property point ctrlPoint: Qt.point(0, 0)
    property real flightAng: 0
    property real flightDist: 0
    property real remnant: 0
    property point remnantPoint: Qt.point(0, 0)
    property real swirl: 0

    property real glideT: 1
    property point glideFrom: Qt.point(0, 0)
    property point glideTo: Qt.point(0, 0)

    readonly property bool timelineLive: prog < 1 || remnant > 0
    readonly property bool gliding: glideT < 1
    readonly property bool blinking: activeForm === "caret"
    readonly property bool busy: timelineLive || gliding

    function clamp01(u) { return Math.max(0, Math.min(1, u)); }
    function smoothstep(u) { return u * u * (3 - 2 * u); }
    function easeInOutQuint(u) { return u < 0.5 ? 16 * u * u * u * u * u : 1 - Math.pow(-2 * u + 2, 5) / 2; }
    function easeOutBack(u) { const c = 1.70158; return 1 + (c + 1) * Math.pow(u - 1, 3) + c * Math.pow(u - 1, 2); }

    function bez(a, c, b, u) {
        const v = 1 - u;
        return Qt.point(v * v * a.x + 2 * v * u * c.x + u * u * b.x,
                        v * v * a.y + 2 * v * u * c.y + u * u * b.y);
    }

    /**
     * Recompute heading, distance and the perpendicular bezier control point
     * for the current fromPoint->anchor pair. Called per frame during the antic
     * and fly phases so a target that slides mid-flight bends the arc and the
     * painted streak stays on the same curve as the bead. Arc side is latched
     * in startFlight (arcFlip); re-deciding it per frame would mirror the whole
     * curve in one frame when the target crosses the vertical through the origin.
     */
    function updateFlightGeo() {
        const dx = anchor.x - fromPoint.x;
        const dy = anchor.y - fromPoint.y;
        const dd = Math.hypot(dx, dy) || 1;
        flightDist = dd;
        flightAng = Math.atan2(dy, dx);
        let px = -dy / dd;
        let py = dx / dd;
        if (arcFlip) { px = -px; py = -py; }
        ctrlPoint = Qt.point((fromPoint.x + anchor.x) / 2 + px * dd * 0.22,
                             (fromPoint.y + anchor.y) / 2 + py * dd * 0.22);
    }

    function stopGlide() {
        glideAnim.stop();
        glideTo = Qt.point(bx, by);
        glideT = 1;
    }

    function startFlight(targetForm, quick) {
        quickFlight = quick === true;
        fromPoint = Qt.point(bx, by);
        arcFlip = anchor.x > fromPoint.x;
        updateFlightGeo();
        remnantAnim.stop();
        remnantPoint = Qt.point(bx, by);
        remnant = flightDist > root.flightThreshold ? 1 : 0;
        activeForm = targetForm;
        stopGlide();
        settleAnim.stop();
        flightAnim.restart();
        if (remnant > 0)
            remnantAnim.restart();
    }

    /**
     * In-place transform: skip travel, replay only the settle window (splash +
     * easeOutBack pop) so a nearby form change still reads as a shapeshift
     * without a pointless flight.
     */
    function startMorph(targetForm) {
        flightAnim.stop();
        activeForm = targetForm;
        prog = root.pFly;
        settleAnim.restart();
    }

    function startGlide(target) {
        glideFrom = Qt.point(bx, by);
        glideTo = target;
        glideT = 0;
        glideAnim.restart();
    }

    /**
     * Wake from the hidden ("off") state. Re-shows start at the wake anchor: the
     * bead condenses there, then flies to its target if far or pops in place if
     * near. Positions from before the hidden period never leak in.
     */
    function appear() {
        stopGlide();
        remnantAnim.stop();
        remnant = 0;
        bx = wake.x;
        by = wake.y;
        if (Math.hypot(anchor.x - bx, anchor.y - by) > root.flightThreshold) {
            startFlight(form, true);
        } else {
            bx = anchor.x;
            by = anchor.y;
            startMorph(form);
        }
    }

    function retarget() {
        const dx = anchor.x - bx;
        const dy = anchor.y - by;
        const dd = Math.hypot(dx, dy);
        if (form !== activeForm) {
            if (dd > root.flightThreshold) {
                startFlight(form);
            } else {
                flightAnim.stop();
                settleAnim.stop();
                if (dd > 0.5)
                    startGlide(anchor);
                startMorph(form);
            }
        } else if (timelineLive && prog < 1) {
            // Covers BOTH the fly sub-phase (prog < pFly) and the settle
            // sub-phase (pFly <= prog < 1) that follows it in the SAME
            // flightAnim/settleAnim run. A same-form retarget landing while
            // still travelling — even just settling into place — is a
            // discrete hop, not a slow morph: without treating settle the
            // same as fly here, a hover arriving mid-settle fell through to
            // the plain `startGlide()` branch below while flightAnim/
            // settleAnim was still driving `prog` toward 1, and the very
            // next animation frame's onProgChanged (`if (!gliding) bx =
            // anchor.x; by = anchor.y;`) would win the race and teleport the
            // bead straight to the new anchor BEFORE that glide could take
            // over — rendering at whatever (still low) fadeIn settle had
            // reached, i.e. the collapsed "remnant droplet" instead of the
            // full ember. Stopping both anims and forcing prog to 1 here
            // makes the hop land on idle (fadeIn pinned to 1) immediately,
            // same as the already-correct fly-phase case, then glides.
            const jump = Math.hypot(anchor.x - lastTarget.x, anchor.y - lastTarget.y);
            if (jump > root.flightThreshold) {
                flightAnim.stop();
                settleAnim.stop();
                startGlide(anchor);
                prog = 1;
            }
        } else if (dd > 0.5) {
            startGlide(anchor);
        } else if (!gliding) {
            bx = anchor.x;
            by = anchor.y;
        }
    }

    /**
     * Coalesced decision point. form and point are sibling bindings in Pill
     * whose change handlers fire mid-cascade in unspecified order (and `anchor`
     * rides on both). Deciding synchronously would read a stale partner value
     * (a far form change sees dd≈0 against the not-yet-updated anchor and
     * quietly degrades the flight to an in-place morph). Qt.callLater defers
     * the decision until both bindings have settled, and collapses the
     * per-frame handler bursts of a pill morph into one retarget per tick.
     * lastTarget tracks the previous settled anchor
     * so a mid-flight DISCRETE hop (mixer focus jump, seek snap) is told apart
     * from a morph slide and handed to a glide rather than teleporting the
     * airborne bead.
     */
    function decide() {
        if (form === "off") {
            if (hidden)
                return;
            hidden = true;
            flightAnim.stop();
            settleAnim.stop();
            remnantAnim.stop();
            remnant = 0;
            stopGlide();
            prog = 1;
            return;
        }
        if (hidden) {
            hidden = false;
            appear();
        } else {
            retarget();
        }
        lastTarget = Qt.point(anchor.x, anchor.y);
    }

    // The clamped anchor, not the raw point, is what the timeline chases: a
    // host point that moves entirely inside the same clamped spot (a header
    // relayout under a pinned flame) is not a move worth re-deciding.
    onAnchorChanged: Qt.callLater(root.decide)
    onFormChanged: Qt.callLater(root.decide)
    onHeatChanged: canvas.requestPaint()

    Component.onCompleted: {
        bx = anchor.x;
        by = anchor.y;
        activeForm = form;
        hidden = form === "off";
        lastTarget = Qt.point(anchor.x, anchor.y);
    }

    NumberAnimation {
        id: flightAnim
        target: root
        property: "prog"
        from: 0
        to: 1
        duration: root.quickFlight ? Math.round(460 * Motion.mult) : Motion.shapeshift
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: settleAnim
        target: root
        property: "prog"
        to: 1
        duration: Math.round(Motion.shapeshift * (1 - root.pFly))
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: remnantAnim
        target: root
        property: "remnant"
        from: 1
        to: 0
        duration: Math.round(350 * Motion.mult)
        easing.type: Motion.easeStandard
    }

    NumberAnimation {
        id: glideAnim
        target: root
        property: "glideT"
        from: 0
        to: 1
        duration: Motion.glide
        easing.type: Motion.easeStandard
    }

    onProgChanged: {
        if (prog < pAntic) {
            phase = "antic";
            updateFlightGeo();
            bx = fromPoint.x;
            by = fromPoint.y;
        } else if (prog < pFly) {
            phase = "fly";
            updateFlightGeo();
            const u = easeInOutQuint((prog - pAntic) / (pFly - pAntic));
            const p = bez(fromPoint, ctrlPoint, anchor, u);
            bx = p.x;
            by = p.y;
        } else {
            if (phase === "fly")
                flightAng = Math.atan2(anchor.y - ctrlPoint.y, anchor.x - ctrlPoint.x);
            phase = prog >= 1 ? "idle" : "settle";
            if (!gliding) {
                bx = anchor.x;
                by = anchor.y;
            }
        }
    }

    onGlideTChanged: if (gliding || glideT === 1) {
        bx = glideFrom.x + (glideTo.x - glideFrom.x) * glideT;
        by = glideFrom.y + (glideTo.y - glideFrom.y) * glideT;
        if (glideT >= 1) {
            bx = glideTo.x;
            by = glideTo.y;
        }
    }

    FrameAnimation {
        running: root.visible && root.busy
        onTriggered: {
            root.swirl += frameTime * 0.5;
            canvas.requestPaint();
        }
    }

    Timer {
        // The idle breathe/swirl (and caret blink) is a continuous loop, so
        // reduce-motion stops it outright — the bead holds its resting frame
        // rather than breathing forever. One-shot shapeshift transitions still
        // run (mult-scaled) off the FrameAnimation above.
        running: root.visible && !root.busy && !Motion.reduceMotion
        interval: root.blinking ? 33 : 83
        repeat: true
        onTriggered: {
            root.swirl += interval * 0.0005;
            canvas.requestPaint();
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        antialiasing: true

        readonly property real breathe: 1 + 0.0125 * Math.sin(root.swirl * 0.32)

        function bead(ctx, x, y, R, stretch, ang, alpha) {
            ctx.save();
            if (alpha !== undefined)
                ctx.globalAlpha = alpha;
            ctx.translate(x, y);
            ctx.rotate(ang);
            ctx.scale(1 + stretch, 1 / (1 + stretch * 0.55));
            ctx.rotate(-ang);
            const hg = ctx.createRadialGradient(-R * 0.32, -R * 0.38, 0, 0, 0, R);
            hg.addColorStop(0, root.beadCore);
            hg.addColorStop(0.55, root.beadLit);
            hg.addColorStop(0.92, root.beadMid);
            hg.addColorStop(1, root.beadEmber);
            ctx.beginPath();
            ctx.arc(0, 0, R, 0, 7);
            ctx.fillStyle = hg;
            ctx.fill();
            ctx.save();
            ctx.beginPath();
            ctx.arc(0, 0, R, 0, 7);
            ctx.clip();
            ctx.globalAlpha = (alpha === undefined ? 1 : alpha) * 0.35;
            for (let k = 0; k < 2; k++) {
                ctx.beginPath();
                ctx.arc(0, 0, R * (0.45 + k * 0.22),
                        root.swirl * (0.5 + k * 0.25) + k * 2.6,
                        root.swirl * (0.5 + k * 0.25) + k * 2.6 + 2.4);
                ctx.strokeStyle = k ? root.swirlBurn : root.swirlTip;
                ctx.lineWidth = 1.6 * root.s;
                ctx.stroke();
            }
            ctx.restore();
            ctx.beginPath();
            ctx.ellipse(-R * 0.34 - R * 0.30, -R * 0.42 - R * 0.18, R * 0.60, R * 0.36);
            ctx.fillStyle = "rgba(255,246,240,0.6)";
            ctx.fill();
            ctx.beginPath();
            ctx.arc(0, 0, Math.max(0.5, R - 0.8 * root.s), Math.PI * 0.25, Math.PI * 0.75);
            ctx.strokeStyle = "rgba(255,217,194,0.45)";
            ctx.lineWidth = 1.2 * root.s;
            ctx.stroke();
            ctx.restore();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (!root.visible)
                return;

            const S = root.s;
            const bx = root.bx;
            const by = root.by;
            const baseR = root.restR;

            if (root.remnant > 0 && root.phase !== "antic") {
                const rr = baseR * 0.5 * root.remnant;
                if (rr > 0.4 * S)
                    bead(ctx, root.remnantPoint.x + (1 - root.remnant) * 6 * S, root.remnantPoint.y,
                         rr, 0, 0, root.remnant * 0.9);
            }

            if (root.phase === "antic") {
                const q = root.clamp01(root.prog / root.pAntic);
                const pull = root.smoothstep(q) * 0.55;
                bead(ctx, bx, by, baseR, pull, root.flightAng);
                return;
            }

            if (root.phase === "fly") {
                const q = (root.prog - root.pAntic) / (root.pFly - root.pAntic);
                const u = root.easeInOutQuint(root.clamp01(q));
                const tail = Math.max(0, u - 0.26 * Math.sin(Math.PI * Math.min(1, q * 1.4)));
                const NSEG = 15;
                for (let i = 0; i < NSEG; i++) {
                    const u1 = tail + (u - tail) * (i / NSEG);
                    const u2 = tail + (u - tail) * ((i + 1) / NSEG);
                    const a2 = root.bez(root.fromPoint, root.ctrlPoint, root.anchor, u1);
                    const b2 = root.bez(root.fromPoint, root.ctrlPoint, root.anchor, u2);
                    const fI = i / NSEG;
                    ctx.beginPath();
                    ctx.moveTo(a2.x, a2.y);
                    ctx.lineTo(b2.x, b2.y);
                    ctx.strokeStyle = fI > 0.6 ? root.beadLit : root.beadMid;
                    ctx.lineWidth = (0.8 + 6.5 * fI * fI) * S;
                    ctx.lineCap = "round";
                    ctx.globalAlpha = 0.12 + 0.55 * fI;
                    ctx.stroke();
                }
                ctx.globalAlpha = 1;
                const speed = Math.sin(Math.PI * root.clamp01(q));
                const d1 = root.bez(root.fromPoint, root.ctrlPoint, root.anchor, Math.min(1, u + 0.01));
                const tang = Math.atan2(d1.y - by, d1.x - bx);
                bead(ctx, bx, by, baseR * 1.62, speed * 1.0, tang);
                return;
            }

            const settling = root.phase === "settle";
            const q = settling ? root.clamp01((root.prog - root.pFly) / (1 - root.pFly)) : 1;
            const e = settling ? root.easeOutBack(q) : 1;
            const fadeIn = settling ? root.smoothstep(root.clamp01(q * 1.8)) : 1;

            if (settling && q < 0.55) {
                const sq = q / 0.55;
                const hop = Math.sin(Math.PI * sq);
                const angles = [-2.35, -1.57, -0.79];
                for (let i = 0; i < 3; i++) {
                    const sa = angles[i];
                    const sr = 13 * S * hop;
                    const sx2 = bx + Math.cos(sa) * sr;
                    const sy2 = by + Math.sin(sa) * sr * 1.25;
                    ctx.beginPath();
                    ctx.arc(sx2, sy2, (2.2 - 0.9 * sq) * S, 0, 7);
                    ctx.fillStyle = root.beadLit;
                    ctx.globalAlpha = hop * 0.85;
                    ctx.fill();
                }
                ctx.globalAlpha = 1;
            }

            const f = root.activeForm;

            if (f === "caret") {
                const blink = settling ? 1 : (0.35 + 0.65 * (0.5 + 0.5 * Math.sin(root.swirl * 5.7)));
                const hgt = 15 * S * e;
                const wdt = (2.5 + 6 * (1 - fadeIn)) * S;
                ctx.globalAlpha = blink;
                ctx.beginPath();
                ctx.roundedRect(bx - wdt / 2, by - hgt / 2, wdt, Math.max(2 * S, hgt), Math.min(wdt, hgt) / 2, Math.min(wdt, hgt) / 2);
                ctx.fillStyle = root.beadCore;
                ctx.fill();
                ctx.globalAlpha = 1;
                return;
            }

            if (f === "seam") {
                const R = (3.5 + 1.5 * (1 - fadeIn)) * S;
                bead(ctx, bx, by, R * (settling ? (0.8 + 0.2 * e) : 1), 0, 0);
                return;
            }

            if (f === "soul") {
                const r = 2.8 * S * (settling ? (0.7 + 0.3 * e) : 1);
                const wl = 7 * S * fadeIn;
                const wy0 = by + root.wickDir * (r + 1.5 * S);
                const wg = ctx.createLinearGradient(0, wy0, 0, wy0 + root.wickDir * wl);
                wg.addColorStop(0, "rgba(255,217,194," + (0.55 * fadeIn) + ")");
                wg.addColorStop(1, root.rgbaStr(root.beadLitC, 0));
                ctx.beginPath();
                ctx.moveTo(bx, wy0);
                ctx.lineTo(bx, wy0 + root.wickDir * wl);
                ctx.strokeStyle = wg;
                ctx.lineWidth = 1.1 * S;
                ctx.lineCap = "round";
                ctx.stroke();
                bead(ctx, bx, by, r, settling ? (1 - q) * 0.3 : 0, 0);
                return;
            }

            if (f === "tick") {
                const rx = 5.5 * S * (settling ? (0.75 + 0.25 * e) : 1);
                const ry = 3.1 * S;
                ctx.save();
                ctx.translate(bx, by);
                ctx.scale(rx / ry, 1);
                const tg = ctx.createRadialGradient(-ry * 0.3, -ry * 0.35, 0, 0, 0, ry);
                tg.addColorStop(0, root.beadCore);
                tg.addColorStop(0.55, root.beadLit);
                tg.addColorStop(0.92, root.beadMid);
                tg.addColorStop(1, root.beadEmber);
                ctx.beginPath();
                ctx.arc(0, 0, ry, 0, 7);
                ctx.fillStyle = tg;
                ctx.globalAlpha = Math.max(0.25, fadeIn);
                ctx.fill();
                ctx.restore();
                ctx.beginPath();
                ctx.ellipse(bx - rx * 0.55, by - ry * 0.75, rx * 0.55, ry * 0.4);
                ctx.fillStyle = "rgba(255,246,240," + (0.55 * fadeIn) + ")";
                ctx.fill();
                return;
            }

            if (f === "rowseam") {
                const sh = 18 * S * (settling ? (0.6 + 0.4 * e) : 1);
                const sw = 4.2 * S;
                const sg3 = ctx.createLinearGradient(0, by - sh / 2, 0, by + sh / 2);
                sg3.addColorStop(0, root.rgbaStr(root.beadLitC, 0.92));
                sg3.addColorStop(0.5, root.beadCore);
                sg3.addColorStop(1, root.rgbaStr(root.beadLitC, 0.92));
                ctx.beginPath();
                ctx.roundedRect(bx - sw / 2, by - sh / 2, sw, sh, sw / 2, sw / 2);
                ctx.fillStyle = sg3;
                ctx.globalAlpha = Math.max(0.85, fadeIn);
                ctx.fill();
                ctx.beginPath();
                ctx.ellipse(bx - sw * 0.26, by - sh * 0.3, sw * 0.28, sh * 0.18);
                ctx.fillStyle = "rgba(255,246,240,0.6)";
                ctx.fill();
                ctx.globalAlpha = 1;
                if (fadeIn < 0.7)
                    bead(ctx, bx, by, 2.6 * S * (1 - fadeIn), 0, 0, 1 - fadeIn * 1.3);
                return;
            }

            if (f === "ring") {
                const R = (baseR + 6 * S) + 5 * S * root.smoothstep(fadeIn) * e;
                ctx.globalAlpha = 1;
                ctx.beginPath();
                ctx.arc(bx, by, Math.max(2 * S, R), 0, 7);
                ctx.strokeStyle = root.beadLit;
                ctx.lineWidth = Math.max(1.6 * S, (7 - 4.8 * fadeIn) * S);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(bx, by, Math.max(2 * S, R), -1.2, 0.4);
                ctx.strokeStyle = "rgba(255,217,194," + (0.7 * fadeIn) + ")";
                ctx.lineWidth = 1.4 * S;
                ctx.stroke();
                if (fadeIn < 0.6)
                    bead(ctx, bx, by, baseR * (1 - fadeIn), 0, 0, 1 - fadeIn * 1.5);
                return;
            }

            const land = settling ? (0.7 + 0.3 * e) : 1;
            const breathe = (f === "rest") ? canvas.breathe : 1;
            const r = baseR * breathe * land * (f === "dock" ? root.heatScale : 1);
            bead(ctx, bx, by, r, settling ? (1 - q) * 0.4 : 0, root.flightAng);
        }
    }

    /**
     * The blur layer allocates an FBO the size of the whole pill; while the bead
     * is hidden (wallpaper strip, toast, plain hover) that's pure GPU tax on an
     * empty canvas, so the layer only exists while something is drawn or fading.
     */
    layer.enabled: opacity > 0.001 || busy
    layer.effect: MultiEffect {
        blurEnabled: true
        blur: 0.34
        blurMax: 8
    }
}
