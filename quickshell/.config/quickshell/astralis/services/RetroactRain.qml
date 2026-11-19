pragma Singleton

import QtQuick
import Quickshell

/**
 * astralis — Retroact Rain (Wuthering Waves): the event clock. Rain falls,
 * slows, hangs in mid-air as glass beads, then rises. modules/rain draws it,
 * one click-through layer per screen, all reading this one clock so the
 * screens stay in step.
 *
 * The shader costs ~25–30% of the 780M iGPU while it runs (measured
 * 2026-11-19), so a timed play ends — the outro fades it and the layers are
 * destroyed, leaving nothing to repaint. `length` (Flags.rainLength) is read
 * LIVE: "short"/"long" rise ~9/50 s then fade, "endless" (Indefinite) rises
 * until stop(); switching it mid-play applies at once. `paused` (set by
 * modules/rain while fullscreen windows cover every screen) freezes the
 * clock, so nothing changes and Qt repaints nothing.
 *
 *   play(force) · stop() (fades out) · toggle() · cut() (gone now, no outro)
 *   play(true) holds it like Indefinite whatever the length (`ipc call rain hold`).
 *
 * The timeline is content timing matched to the approved prototype, not UI
 * motion, so it does not use Motion tokens (which reduce-motion would shrink).
 */
Singleton {
    id: root

    // ── settings (plain bindings, so a dev harness can override them without touching Flags) ──
    /** "short" | "long" | "endless" (Indefinite). */
    property string length: Flags.rainLength
    /**
     * "full" = fall → hang → rise; "rise" = only the rising part: the clock
     * starts at full rising speed, so bubbles fade in already drifting up
     * (never the 60% of hanging beads that shrink away as a full rise begins).
     */
    property string sequence: Flags.rainSequence

    // ── timeline, seconds ─────────────────────────────────────────────────
    // Defaults (hang 2.4 s, speed 100%) are the approved prototype's timing;
    // Settings › Widgets › Retroact Rain changes them, live.
    readonly property real fallEnd: 3.5      // full-speed rain
    readonly property real slowEnd: 4.6      // braked to a halt
    readonly property real stillEnd: slowEnd + Math.max(0, Flags.rainHang)   // beads hang in mid-air
    readonly property real riseIn: stillEnd + 2.0                            // up to full rising speed
    readonly property real fadeIn: 0.9
    readonly property real fadeOut: 2.5
    readonly property real speedMul: Math.max(0.1, Flags.rainSpeed / 100)
    readonly property real fallSpeed: 3.2 * speedMul    // screen heights / s
    readonly property real riseSpeed: 0.55 * speedMul
    /** Seconds of full-speed rising before the outro (unless holding). */
    readonly property real riseFor: length === "long" ? 50 : 9

    // ── state ─────────────────────────────────────────────────────────────
    /** Layers exist while true (fade-out included). */
    property bool playing: false
    /** play(true): hold whatever the length. */
    property bool holdForced: false
    /** Rises until stop() instead of ending on its own. */
    readonly property bool holding: holdForced || length === "endless"
    /** Clock frozen (fullscreen windows cover every screen). */
    property bool paused: false
    onPausedChanged: last = Date.now()
    /** Timeline position; starts at riseIn for sequence "rise". */
    property real t: 0
    /** Seconds since play() — the fade-in runs on this, since t starts late in "rise". */
    property real since: 0
    /** vel integrated over t, so drops keep their place when the speed changes. */
    property real travel: 0
    /** t at which the outro began; -1 = not ending. */
    property real endAt: -1
    readonly property bool ending: endAt >= 0
    /** A play() that arrived during the outro: start fresh once it ends. */
    property bool again: false
    property bool againForce: false

    readonly property real vel: velAt(t)
    readonly property real sky: inout((t - stillEnd - 0.5) / 3.0)
    /** 0..1 layer opacity: fades in from play(), out over the outro. */
    readonly property real level: !playing ? 0
        : Math.min(smooth(since / fadeIn), ending ? 1 - smooth((t - endAt) / fadeOut) : 1)

    function ease(u) { u = Math.max(0, Math.min(1, u)); return 1 - Math.pow(1 - u, 3); }
    function inout(u) { u = Math.max(0, Math.min(1, u)); return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2; }
    function smooth(u) { u = Math.max(0, Math.min(1, u)); return u * u * (3 - 2 * u); }

    /** Speed in screen heights/s at time t: + falls, − rises. */
    function velAt(t) {
        if (t < fallEnd) return fallSpeed;
        if (t < slowEnd) return fallSpeed * (1 - ease((t - fallEnd) / (slowEnd - fallEnd)));
        if (t < stillEnd) return 0;
        if (t < riseIn) return -riseSpeed * inout((t - stillEnd) / (riseIn - stillEnd));
        return -riseSpeed;
    }

    function play(force) {
        if (root.playing && root.ending) {
            root.again = true;
            root.againForce = !!force;
            return;
        }
        if (root.playing) {
            if (force)
                root.holdForced = true;
            return;
        }
        root.holdForced = !!force;
        root.t = root.sequence === "rise" ? root.riseIn : 0;
        root.since = 0;
        root.travel = 0;
        root.endAt = -1;
        root.again = false;
        root.last = Date.now();
        root.playing = true;
    }

    function stop() {
        root.again = false;
        if (root.playing && !root.ending)
            root.endAt = root.t;
    }

    function toggle() {
        if (root.playing && !root.ending)
            root.stop();
        else
            root.play(false);
    }

    function cut() {
        root.again = false;
        // playing drops BEFORE endAt clears: the other order passes through
        // "playing, not ending, holding", so Rain.syncActive briefly wrote
        // rainActive true then false in one tick, and the flags.json reload
        // could read back the true and resume() restarted the rain right after
        // it was stopped (an Indefinite rain could not be stopped).
        root.playing = false;
        root.endAt = -1;
    }

    /** One step of the clock (the Timer below; a dev harness steps it by hand). */
    function advance(dt) {
        if (!root.playing)
            return;
        root.since += dt;
        root.t += dt;
        root.travel += root.velAt(root.t - dt * 0.5) * dt;
        if (!root.ending && !root.holding && root.t >= root.riseIn + root.riseFor)
            root.endAt = root.t;
        if (root.ending && root.t >= root.endAt + root.fadeOut) {
            var again = root.again, againForce = root.againForce;
            root.cut();
            if (again)
                root.play(againForce);
        }
    }

    /** Off for a dev harness that renders frame by frame. */
    property bool clocked: true
    property real last: 0
    // 60 Hz, not the panel's 165: Qt only redraws when the uniforms change,
    // and the cost is per frame.
    Timer {
        interval: 16
        repeat: true
        running: root.playing && root.clocked && !root.paused
        onTriggered: {
            var now = Date.now();
            root.advance(Math.min(0.1, (now - root.last) / 1000));
            root.last = now;
        }
    }
}
