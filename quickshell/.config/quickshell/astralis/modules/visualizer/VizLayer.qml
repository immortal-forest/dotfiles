pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../colors"
import "../../services"

/**
 * astralis — the full-screen visualizer's surface (see Visualizer.qml): one
 * transparent, click-through WlrLayer.Bottom window covering the screen, and
 * one ShaderEffect painting the edge wave (shaders/edgewave.frag). The scope's
 * eased levels and falling peaks go in as packed matrices each cava frame;
 * once the music stops and everything has sunk, nothing changes and the
 * surface stops repainting.
 */
PanelWindow {
    id: vizLayer

    required property var viz

    screen: viz.screen
    color: "transparent"
    mask: Region {}

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "astralis-viz"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    readonly property bool cycling: Flags.vizColorCycle
    readonly property real ph: viz.cyclePhase
    /** Live wave, bass → treble. */
    readonly property var mainStops: cycling
        ? [viz.ringColor(ph), viz.ringColor(ph + 0.5), viz.ringColor(ph + 1)]
        : [Colors.primary, Colors.tertiary, Colors.secondary]
    /** The peak veil behind it, a step deeper. */
    readonly property var veilStops: cycling
        ? [viz.ringColor(ph + 2), viz.ringColor(ph + 2.5), viz.ringColor(ph + 3)]
        : [Colors.primary_container, Colors.tertiary, Colors.secondary_container]

    /** 16 values from `a` at `base` as a matrix4x4 (missing → 0). */
    function pack(a, base) {
        const m = new Array(16);
        for (let i = 0; i < 16; i++)
            m[i] = a[base + i] || 0;
        return Qt.matrix4x4(m);
    }
    function rail(r) {
        return Qt.vector4d(r[0], r[1], r[2], 0);
    }

    /** Everything drawn (a plain Item so a dev harness can grabToImage it). */
    readonly property Item drawItem: drawRoot

    Item {
        id: drawRoot
        anchors.fill: parent
        // Gated on OPACITY (never visible) so the shader keeps painting.
        opacity: vizLayer.viz.fade

        ShaderEffect {
            id: fx
            anchors.fill: parent
            blending: true
            fragmentShader: Qt.resolvedUrl("shaders/edgewave.frag.qsb") + "?v=2"

            readonly property var rails: vizLayer.viz.rails
            readonly property var lv: vizLayer.viz.levels
            readonly property var pk: vizLayer.viz.peaks

            readonly property vector2d res: Qt.vector2d(width, height)
            // one device pixel, in the logical px the shader works in
            readonly property real aa: 1 / Math.max(1, (vizLayer.screen && vizLayer.screen.devicePixelRatio) || 1)
            readonly property real bands: Math.max(2, Math.min(48, fx.lv.length))

            readonly property matrix4x4 lv0: vizLayer.pack(fx.lv, 0)
            readonly property matrix4x4 lv1: vizLayer.pack(fx.lv, 16)
            readonly property matrix4x4 lv2: vizLayer.pack(fx.lv, 32)
            readonly property matrix4x4 pk0: vizLayer.pack(fx.pk, 0)
            readonly property matrix4x4 pk1: vizLayer.pack(fx.pk, 16)
            readonly property matrix4x4 pk2: vizLayer.pack(fx.pk, 32)

            readonly property vector4d eTop: vizLayer.rail(fx.rails.top)
            readonly property vector4d eRight: vizLayer.rail(fx.rails.right)
            readonly property vector4d eBottom: vizLayer.rail(fx.rails.bottom)
            readonly property vector4d eLeft: vizLayer.rail(fx.rails.left)

            readonly property real sym: fx.rails.sym
            readonly property real closed: fx.rails.closed
            readonly property real taper: fx.rails.taper
            readonly property real depth: vizLayer.viz.depth * fx.rails.scale
            readonly property real glowPx: 12 * vizLayer.viz.s
            readonly property real energy: vizLayer.viz.energy
            // Settings → Appearance → Visualizer fill
            readonly property real solid: Flags.vizFill === "opaque" ? 1 : 0

            readonly property color c0: vizLayer.mainStops[0]
            readonly property color c1: vizLayer.mainStops[1]
            readonly property color c2: vizLayer.mainStops[2]
            readonly property color d0: vizLayer.veilStops[0]
            readonly property color d1: vizLayer.veilStops[1]
            readonly property color d2: vizLayer.veilStops[2]
        }
    }
}
