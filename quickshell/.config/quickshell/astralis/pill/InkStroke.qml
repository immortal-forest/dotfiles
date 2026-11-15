import QtQuick
import "../colors"
import "../services"

/**
 * astralis — 筆 ink-brush progress stroke, shared by the Media surface, the
 * lock screen and the dashboard. Played time is a sumi stroke drawn by a
 * fragment shader (shaders/inkstroke.frag): a tilted entry press (起筆), a
 * body whose width breathes with the brush (keyed to absolute x, so the
 * texture never swims as it grows) with faint hair grooves, a soft bleed into
 * the paper (滲み), and a dry-brush head (掠れ) whose bristles run out one by
 * one. `wet` 0 dries the ink toward `paper` (paused). The unplayed rest is
 * the same stroke grayed out, which the ink fills as it plays. Ame rides
 * `headX`/`headY`.
 */
Item {
    id: ink

    property real s: 1
    /** Played fraction, 0..1. */
    property real frac: 0
    /** Background the dried ink fades toward. */
    property color paper: Colors.surface_container
    /** Glide the head between position samples (off under reduce-motion). */
    property bool glide: true

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
            easing.bezierCurve: Motion.standardCurve
        }
    }

    property real targetF: ink.frac
    property real lastFrac: 0
    property real drawF: targetF
    readonly property real headX: inset + drawF * usable
    readonly property real headY: height / 2

    // Playback time is the one place a constant rate is right: the head
    // tracks the clock between 1 s position samples.
    Behavior on drawF {
        enabled: ink.glide && Math.abs(ink.frac - ink.lastFrac) < 0.02
        NumberAnimation { duration: Math.round(500 * Motion.mult); easing.type: Easing.Linear }
    }
    onTargetFChanged: Qt.callLater(() => { ink.lastFrac = ink.frac; })

    /**
     * Optional colour ramp laid along the whole track (left → right): the
     * stroke reveals more of it as frac grows, so the head's hue reads the
     * level. Up to three stops; empty = flat `inkColor`.
     */
    property var inkStops: []

    readonly property color inkColor: Colors.primary
    /** The grayed-out full stroke under the ink. */
    readonly property color paperColor: Colors.on_surface_variant

    /**
     * Optional glint: a bright bead lighting the ink around `glintX` (item
     * x), with a long tail behind it. `glint` is its strength, 0 = off.
     */
    property real glintX: 0
    property real glint: 0

    function stop(i) {
        const n = ink.inkStops ? ink.inkStops.length : 0;
        if (n < 2)
            return ink.inkColor;
        // resample any stop count onto the shader's three (0, ½, 1)
        const f = i / 2 * (n - 1), k = Math.min(n - 2, Math.floor(f)), t = f - k;
        return Qt.tint(ink.inkStops[k], Qt.alpha(ink.inkStops[k + 1], t));
    }

    ShaderEffect {
        // overhang the item so the bleed and the entry press are never clipped
        readonly property real pad: 10 * ink.s
        x: -pad
        y: -pad
        width: ink.width + 2 * pad
        height: ink.height + 2 * pad
        visible: ink.width > 0 && ink.height > 0

        readonly property vector2d area: Qt.vector2d(width, height)
        readonly property real s: ink.s
        readonly property real halfW: ink.halfW
        readonly property real inset: ink.inset
        readonly property real usable: ink.usable
        readonly property real headX: ink.headX
        readonly property real midY: ink.height / 2
        readonly property real wet: ink.wet
        readonly property color c0: ink.stop(0)
        readonly property color c1: ink.stop(1)
        readonly property color c2: ink.stop(2)
        readonly property color paper: ink.paper
        readonly property color ghostC: ink.paperColor
        readonly property color glintC: Colors.on_surface
        readonly property real glintX: ink.glintX
        readonly property real glint: ink.glint

        // Qt caches a shader by its URL for the life of the process, so a
        // hot reload never re-reads a rebuilt .qsb: bump `v` with each rebuild.
        fragmentShader: Qt.resolvedUrl("shaders/inkstroke.frag.qsb") + "?v=2"
    }
}
