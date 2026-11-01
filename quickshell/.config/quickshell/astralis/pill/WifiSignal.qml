import QtQuick
import "../colors"
import "../services"

/**
 * astralis — Wi-Fi strength as bars: the full wedge as a dim track with the
 * live level (1–4 sectors) filled over it in `color`. `strength` is 0–100,
 * as Quickshell.Networking reports it. Both layers skip GlyphIcon's
 * ink-centring so every sector keeps the shared apex at (12,21).
 */
Item {
    id: sig

    property real strength: 0
    property color color: Colors.on_surface_variant

    readonly property int level: strength >= 75 ? 4 : strength >= 50 ? 3 : strength >= 25 ? 2 : 1

    GlyphIcon {
        anchors.fill: parent
        centerInk: false
        name: "wifi-4"
        color: Qt.alpha(sig.color, 0.3)
    }
    GlyphIcon {
        anchors.fill: parent
        centerInk: false
        name: "wifi-" + sig.level
        color: sig.color
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }
}
