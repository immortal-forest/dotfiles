import QtQuick
import "../colors"
import "../services"

/**
 * astralis — toggle switch (ported from Ricelin pill/LinkToggle.qml): tile bg
 * off, primary fill on, knob slides on the fast motion token. Shared by the
 * settings rows and any surface drill-in. Same geometry and colors as the
 * inline toggle in surfaces/Link.qml — this is that control promoted to a
 * shared widget.
 */
Rectangle {
    id: toggle

    property real s: 1
    property bool on: false
    signal toggled()

    width: 28 * s
    height: 16 * s
    radius: 999
    color: on ? Colors.primary : Colors.surface_container_highest
    border.width: on ? 0 : 1
    border.color: Qt.alpha(Colors.outline_variant, 0.6)
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 10 * toggle.s
        height: 10 * toggle.s
        radius: width / 2
        color: toggle.on ? Colors.on_primary : Colors.on_surface
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        x: toggle.on ? toggle.width - width - 3 * toggle.s : 3 * toggle.s
        Behavior on x {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: toggle.toggled()
    }
}
