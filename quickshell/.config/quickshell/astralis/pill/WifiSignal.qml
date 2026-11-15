import QtQuick
import "../colors"
import "../services"

/**
 * astralis — Wi-Fi strength as bars: the whole fan (dot + three arcs) as a
 * dim track with the live level (1 = dot … 4 = all arcs) stroked over it in
 * `color`. `strength` is 0–100, as Quickshell.Networking reports it. Both
 * layers skip GlyphIcon's ink-centring so every arc keeps the shared centre.
 * The track sits at 0.38, not the 0.3 the old filled wedges used: a thin
 * stroke loses more contrast than a solid sector and the top arc vanished.
 */
Item {
    id: sig

    property real strength: 0
    property color color: Colors.on_surface_variant
    property real stroke: 1.8

    readonly property int level: strength >= 75 ? 4 : strength >= 50 ? 3 : strength >= 25 ? 2 : 1

    GlyphIcon {
        anchors.fill: parent
        centerInk: false
        name: "wifi-4"
        stroke: sig.stroke
        color: Qt.alpha(sig.color, 0.38)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }
    GlyphIcon {
        anchors.fill: parent
        centerInk: false
        name: "wifi-" + sig.level
        stroke: sig.stroke
        color: sig.color
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }
}
