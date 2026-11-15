import QtQuick
import "../colors"
import "../services"

/**
 * astralis — 円相 ensō ink ring: a level gauge drawn as one brush circle.
 * The same 筆 stroke InkStroke lays in a line (entry press 起筆, breathing
 * body with hair grooves, 滲み bleed, 掠れ dry head) bent round a circle by
 * shaders/inkring.frag. The stroke starts bottom-left and runs clockwise;
 * `sweep` degrees of it make the full track, which shows grayed out for the
 * ink to fill, and the gap left at the bottom is the ensō's open mouth. At
 * frac 1 the circle all but closes.
 *
 * `frac` changes ease through `drawF` on the expressive spatial curve, so a
 * live reading slides rather than ticks. `inkStops` lays a colour ramp along
 * the whole track, so the head's hue reads the level.
 */
Item {
    id: ring

    property real s: 1
    /** Level, 0..1. */
    property real frac: 0
    /** Track length in degrees; the rest is the open gap at the bottom. */
    property real sweep: 300
    /** Half the body thickness at rest pressure. */
    property real halfW: 4.4 * ring.s
    property var inkStops: []
    property color paper: Colors.surface_container
    property real wet: 1

    property real drawF: Math.max(0, Math.min(1, ring.frac))
    Behavior on drawF {
        NumberAnimation {
            duration: Motion.expressiveDefaultSpatialDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveDefaultSpatial
        }
    }

    function stop(i) {
        const n = ring.inkStops ? ring.inkStops.length : 0;
        if (n < 2)
            return Colors.primary;
        const f = i / 2 * (n - 1), k = Math.min(n - 2, Math.floor(f)), t = f - k;
        return Qt.tint(ring.inkStops[k], Qt.alpha(ring.inkStops[k + 1], t));
    }

    ShaderEffect {
        // overhang so the bleed round the outside is never clipped
        readonly property real pad: 8 * ring.s
        x: -pad
        y: -pad
        width: ring.width + 2 * pad
        height: ring.height + 2 * pad
        visible: ring.width > 0 && ring.height > 0

        readonly property vector2d area: Qt.vector2d(width, height)
        readonly property real s: ring.s
        readonly property real halfW: ring.halfW
        readonly property real inset: 0
        // centre line: clear of the edge by the widest the brush presses (~1.45×)
        readonly property real ringR: Math.min(ring.width, ring.height) / 2 - ring.halfW * 1.45 - 1 * ring.s
        readonly property real usable: Math.max(1, ring.sweep * Math.PI / 180 * ringR)
        readonly property real headX: ring.drawF * usable
        readonly property real midY: 0
        readonly property real wet: ring.wet
        readonly property color c0: ring.stop(0)
        readonly property color c1: ring.stop(1)
        readonly property color c2: ring.stop(2)
        readonly property color paper: ring.paper
        readonly property color ghostC: Colors.on_surface_variant
        readonly property color glintC: Colors.on_surface
        readonly property real glintX: 0
        readonly property real glint: 0
        // gap centred on straight down (90° in y-down screen space)
        readonly property real gap: (360 - ring.sweep) * Math.PI / 180
        readonly property real a0: Math.PI / 2 + gap / 2

        fragmentShader: Qt.resolvedUrl("shaders/inkring.frag.qsb") + "?v=1"
    }
}
