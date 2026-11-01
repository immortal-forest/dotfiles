pragma ComponentBehavior: Bound

import QtQuick
import "../colors"
import "../services"
import "../config"

/**
 * astralis — labelled dropdown for the display settings page (ported from
 * Ricelin pill/DisplayPicker.qml): a left caption, a value chip styled like
 * the segmented control's pill, and a panel that floats below when open.
 * The item's own height stays a single row whether open or closed — the panel
 * is absolutely positioned and overlays the rows beneath it (a real drop-down,
 * not a push-down), so opening it never shoves Refresh/Scale/Rotation
 * downward. The host raises this picker's row `z` while open so the panel
 * paints above (and catches clicks over) the rows it covers. Picking emits
 * picked(value) and the parent closes it; tapping the chip emits requestToggle
 * so the page keeps only one dropdown open at a time. Resolution labels carry a
 * "×" the picker renders as a smaller, dimmer separator in the shell font, so
 * the digits never shift to a fallback face.
 */
Item {
    id: pick

    property real s: 1
    property string label: ""
    property var options: []
    property var value
    property bool open: false
    signal picked(var value)
    signal requestToggle()

    readonly property string currentLabel: {
        for (var i = 0; i < options.length; i++)
            if (options[i].value === value)
                return options[i].label;
        return options.length ? options[0].label : "";
    }

    readonly property real rowH: 26 * pick.s
    readonly property real gap: 4 * pick.s
    /** True while the menu is open or still animating closed — hosts key their z-raise on this. */
    readonly property bool showing: menu.showing

    width: parent ? parent.width : 0
    // Height is always one row: the open panel overlays the rows below (it is
    // absolutely positioned and drawn above them via the host's z-raise),
    // rather than extending this item and pushing siblings down.
    implicitHeight: pick.rowH

    Row {
        id: head
        width: parent.width
        height: pick.rowH
        spacing: 8 * pick.s

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 64 * pick.s
            text: pick.label
            color: Qt.alpha(Colors.on_surface_variant, 0.65)
            font.family: Appearance.font.family
            font.pixelSize: 10.5 * pick.s
            font.weight: Font.Medium
        }

        Rectangle {
            id: field
            property bool hovered: false
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 72 * pick.s
            height: 24 * pick.s
            radius: 9 * pick.s
            color: pick.open ? Qt.alpha(Colors.primary, 0.14)
                : (field.hovered ? Colors.surface_container_highest : "transparent")
            border.width: 1
            border.color: pick.open ? Qt.alpha(Colors.primary, 0.5) : Qt.alpha(Colors.on_surface, 0.06)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            scale: fieldArea.pressed ? 0.92 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            Accessible.role: Accessible.Button
            Accessible.name: pick.label
            Accessible.description: pick.currentLabel
            Accessible.onPressAction: fieldArea.clicked(null)

            DisplayLabel {
                anchors.left: parent.left
                anchors.leftMargin: 10 * pick.s
                anchors.verticalCenter: parent.verticalCenter
                s: pick.s
                text: pick.currentLabel
                color: Colors.on_surface
                weight: Font.DemiBold
            }

            GlyphIcon {
                anchors.right: parent.right
                anchors.rightMargin: 8 * pick.s
                anchors.verticalCenter: parent.verticalCenter
                width: 13 * pick.s
                height: 13 * pick.s
                name: pick.open ? "chevron-up" : "chevron-down"
                color: Colors.on_surface_variant
                stroke: 2
            }

            MouseArea {
                id: fieldArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: field.hovered = true
                onExited: field.hovered = false
                onClicked: pick.requestToggle()
            }
        }
    }

    DropMenu {
        id: menu
        anchors.top: head.bottom
        anchors.topMargin: pick.gap
        anchors.left: parent.left
        anchors.leftMargin: 72 * pick.s
        anchors.right: parent.right
        s: pick.s
        open: pick.open
        options: pick.options
        isCurrent: (o) => o.value === pick.value
        onPicked: (o) => pick.picked(o.value)
    }
}
