import QtQuick
import "../../colors"
import "../../services"

/**
 * astralis — Material 3 Expressive progress indicator, linear and circular.
 *
 *   variant: "linear" | "circular"
 *
 * The Expressive tell on the linear one is that the ACTIVE portion is a sine
 * wave while the remaining track stays flat, with a gap between the two and a
 * stop dot pinned at the far end. That asymmetry is the whole point: a plain
 * two-tone bar tells you a fraction, a wave tells you something is RUNNING.
 * So the wave is not decoration — `wavy: false` is the right call for a bar
 * that reports a static measurement (a disk gauge), and the default `true` is
 * right for a bar that reports work in flight (a download, an update).
 *
 * The amplitude is animated to and from zero rather than switched, because the
 * moment work finishes the wave should SETTLE flat under the final value, not
 * vanish mid-crest.
 *
 * Painted on a Canvas rather than assembled from Rectangles because a sine
 * stroked with round caps is one path — the Rectangle version would be dozens
 * of slivers and would still have square joins. The repaint is driven by the
 * `phase` animation and nothing else, and that animation only runs while the
 * indicator is actually visible AND actually moving (see `animating`), so an
 * idle or hidden bar costs zero frames.
 *
 *   M3Progress {
 *       s: root.s
 *       width: 200 * root.s
 *       value: Updates.fraction
 *       accessibleName: "System update"
 *   }
 */
Item {
    id: prog

    property real s: 1
    property string variant: "linear"

    /** 0..1. Ignored while `indeterminate`. */
    property real value: 0
    property bool indeterminate: false

    /** Expressive wave on the active portion (linear only). */
    property bool wavy: true

    property color activeColor: Colors.primary
    property color trackColor: Colors.secondary_container

    property string accessibleName: ""

    readonly property bool isLinear: prog.variant === "linear"
    readonly property real clamped: Math.max(0, Math.min(1, prog.value))

    // Wave crest-to-trough eats vertical space the flat track does not, so the
    // implicit height carries it even when the wave is currently flat —
    // otherwise turning the wave on would resize the row it sits in.
    implicitWidth: prog.isLinear ? 240 * prog.s : M3.progressCircularSize * prog.s
    implicitHeight: prog.isLinear
        ? (M3.progressTrackHeight + 2 * M3.waveAmplitude) * prog.s
        : M3.progressCircularSize * prog.s

    opacity: prog.enabled ? 1 : M3.disabledContentOpacity
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

    /**
     * A screen reader gets the percentage through `description` — the
     * `Accessible` attached type has NO value/minimum/maximum/stepSize
     * properties, and assigning one is a fatal load error that cascades all
     * the way up the shell. See quickshell-core.md §9b.
     */
    Accessible.role: Accessible.ProgressBar
    Accessible.name: prog.accessibleName
    Accessible.description: prog.indeterminate
        ? "Working"
        : Math.round(prog.clamped * 100) + " percent"

    // ── the wave clock ──────────────────────────────────────────────────────
    // One looping phase in wavelengths. Everything animated on the linear bar
    // reads off this, so the crests, the sweep and the repaint can never drift
    // apart the way three independent animations would.
    property real phase: 0
    readonly property bool animating: prog.visible && prog.enabled && prog.isLinear
        && (prog.indeterminate || (prog.wavy && prog.clamped > 0 && prog.clamped < 1))

    NumberAnimation on phase {
        running: prog.animating
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: Math.max(1, Math.round(1000 / M3.waveSpeed * Motion.mult))
    }

    /**
     * Flat at the extremes, full in between. At 0 there is no active portion to
     * wave; at 1 the work is done and a still-rippling bar would read as "not
     * finished yet". Riding a Behavior means the flattening at the end of a
     * download is a settle, not a cut.
     */
    property real amplitude: (prog.wavy && !prog.indeterminate && prog.clamped > 0.02 && prog.clamped < 0.98)
        || (prog.wavy && prog.indeterminate)
        ? M3.waveAmplitude * prog.s
        : 0
    Behavior on amplitude {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    /** Eased so a jumpy source (a package count) glides instead of stuttering. */
    property real drawn: prog.clamped
    Behavior on drawn {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    // ── linear ──────────────────────────────────────────────────────────────
    Canvas {
        id: bar
        anchors.fill: parent
        visible: prog.isLinear
        antialiasing: true

        // Every input the paint reads, listed once. A missed one here shows up
        // as a bar that only redraws when something ELSE happens to change.
        readonly property real repaintKey: prog.phase + prog.amplitude + prog.drawn
            + width + height + (prog.indeterminate ? 1 : 0)
        onRepaintKeyChanged: bar.requestPaint()
        readonly property color activeC: prog.activeColor
        readonly property color trackC: prog.trackColor
        onActiveCChanged: bar.requestPaint()
        onTrackCChanged: bar.requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const h = height;
            const w = width;
            const stroke = M3.progressTrackHeight * prog.s;
            const mid = h / 2;
            const gap = M3.progressTrackHeight * prog.s;      // spec: gap == track height
            const stopR = stroke / 2;
            const stopX = w - stopR;

            // Indeterminate is a segment sweeping the full width; determinate
            // fills from the left. Both end up as one [a, b] span so the wave
            // and the track split below can be written once.
            let a, b;
            if (prog.indeterminate) {
                const t = prog.phase;
                const span = 0.35;
                const head = (t * (1 + span) - span) * w;
                a = Math.max(0, head);
                b = Math.min(w - stroke, head + span * w);
                if (b <= a) return;
            } else {
                a = 0;
                b = prog.drawn * (w - stroke);
            }

            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.lineWidth = stroke;

            // Inactive track first, so the active stroke's round cap sits on
            // top of it rather than being clipped by it.
            ctx.strokeStyle = bar.trackC;
            if (prog.indeterminate) {
                // The segment is somewhere in the middle of an unknown job, so
                // the FULL track has to be there behind it — a track that only
                // existed ahead of the segment would read as a determinate bar
                // that keeps resetting.
                ctx.beginPath();
                ctx.moveTo(stroke / 2, mid);
                ctx.lineTo(w - stroke / 2, mid);
                ctx.stroke();
            } else {
                const trackFrom = Math.min(w - stroke, b + gap + stroke / 2);
                if (trackFrom < stopX - stopR - gap) {
                    ctx.beginPath();
                    ctx.moveTo(trackFrom + stroke / 2, mid);
                    ctx.lineTo(stopX - stopR - gap, mid);
                    ctx.stroke();
                }

                // Stop indicator: M3 Expressive pins a dot at the track's end
                // so the bar has a visible destination even at 1%. It is
                // determinate-only — there is no "end" to point at when the
                // total is unknown.
                ctx.fillStyle = bar.trackC;
                ctx.beginPath();
                ctx.arc(stopX, mid, stopR, 0, Math.PI * 2);
                ctx.fill();
            }

            if (b <= a + 0.5)
                return;

            // Active portion. Amplitude 0 degenerates to a straight line, which
            // is exactly the flat bar — no separate code path for "not wavy".
            ctx.strokeStyle = bar.activeC;
            ctx.beginPath();
            const amp = prog.amplitude;
            if (amp < 0.15) {
                ctx.moveTo(a + stroke / 2, mid);
                ctx.lineTo(b + stroke / 2, mid);
            } else {
                const wl = M3.waveLength * prog.s;
                const step = Math.max(1, wl / 12);
                const shift = prog.phase * wl;
                for (let x = a; x <= b; x += step) {
                    const y = mid + amp * Math.sin(((x + shift) / wl) * Math.PI * 2);
                    if (x === a)
                        ctx.moveTo(x + stroke / 2, y);
                    else
                        ctx.lineTo(x + stroke / 2, y);
                }
                // Land exactly on b — the loop above stops one step short
                // whenever the span is not a whole number of steps, which
                // would make the bar's head twitch as it grows.
                ctx.lineTo(b + stroke / 2,
                           mid + amp * Math.sin(((b + shift) / wl) * Math.PI * 2));
            }
            ctx.stroke();
        }
    }

    // ── circular ────────────────────────────────────────────────────────────
    // Kept smooth rather than wavy: the circular indicator appears inline at
    // 20-24dp in this shell (a row's busy spinner), where a 3dp wave on a 4dp
    // stroke is noise, not motion.
    Item {
        id: ring
        anchors.centerIn: parent
        width: Math.min(prog.width, prog.height)
        height: width
        visible: !prog.isLinear

        // The spin is a whole-Item rotation, not a repaint — one transform per
        // frame instead of re-stroking an arc sixty times a second.
        RotationAnimator {
            target: ring
            running: !prog.isLinear && prog.indeterminate && prog.visible && prog.enabled
            from: 0
            to: 360
            duration: Math.round(1400 * Motion.mult)
            loops: Animation.Infinite
        }
        // A determinate ring must sit still at 12 o'clock; the animator leaves
        // whatever angle it stopped at behind, so reset it explicitly.
        onVisibleChanged: if (!prog.indeterminate) ring.rotation = 0

        Canvas {
            id: arc
            anchors.fill: parent
            antialiasing: true

            readonly property real repaintKey: prog.drawn + width + (prog.indeterminate ? 1 : 0)
            readonly property color activeC: prog.activeColor
            readonly property color trackC: prog.trackColor
            onRepaintKeyChanged: arc.requestPaint()
            onActiveCChanged: arc.requestPaint()
            onTrackCChanged: arc.requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();

                const stroke = M3.progressCircularWidth * prog.s;
                const r = (Math.min(width, height) - stroke) / 2;
                const cx = width / 2;
                const cy = height / 2;
                const top = -Math.PI / 2;

                ctx.lineWidth = stroke;
                ctx.lineCap = "round";

                if (!prog.indeterminate) {
                    ctx.strokeStyle = arc.trackC;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, Math.PI * 2);
                    ctx.stroke();
                }

                ctx.strokeStyle = arc.activeC;
                ctx.beginPath();
                // Indeterminate draws a fixed three-quarter arc and lets the
                // parent's rotation carry it; determinate sweeps from 12
                // o'clock by the value.
                const sweep = prog.indeterminate ? Math.PI * 1.5 : prog.drawn * Math.PI * 2;
                if (sweep > 0.01)
                    ctx.arc(cx, cy, r, top, top + sweep);
                ctx.stroke();
            }
        }
    }
}
