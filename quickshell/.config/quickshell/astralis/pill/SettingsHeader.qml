import QtQuick
import "../colors"
import "../services"
import "../config"

/**
 * astralis — surface header strip (ported from Ricelin SettingsHeader.qml):
 * the surface kanji (gated by Flags.showGlyphs, the Appearance settings
 * toggle) and its uppercase letter-spaced title on the left, a close × (or
 * back chevron on a sub-surface) at the right that emits `back()`. Pure
 * chrome; each surface wires `back()` to requestClose() or its own subview
 * pop.
 */
Item {
    id: head

    property real s: 1
    property string glyph: ""
    property string title: ""
    property bool showBack: false

    signal back()

    width: parent ? parent.width : 0
    height: 22 * head.s

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * head.s

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Flags.showGlyphs && head.glyph.length > 0
            text: head.glyph
            color: Colors.on_surface
            font.family: Appearance.font.jp
            font.weight: Font.Medium
            font.pixelSize: 16 * head.s
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: head.title
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 10 * head.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.6 * head.s
        }
    }

    GlyphIcon {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 16 * head.s
        height: 16 * head.s
        name: head.showBack ? "chevron-left" : "close"
        color: exitArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
        stroke: head.showBack ? 2.2 : 1.7

        MouseArea {
            id: exitArea
            anchors.fill: parent
            anchors.margins: -6 * head.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: head.back()
        }
    }
}
