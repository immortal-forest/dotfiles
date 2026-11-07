pragma ComponentBehavior: Bound

import QtQuick
import "../colors"
import "../services"
import "../config"

/**
 * astralis — compact dropdown for a SettingsRow's control slot, for choices
 * with too many options for a SettingsSeg. Same chip + DropMenu as
 * DisplayPicker, minus the caption. The panel floats below the chip,
 * right-aligned, overlaying the rows beneath — the host row raises its `z`
 * while `showing`. Picking emits picked(value) and closes; the chip toggles.
 * `options` are `{ label, value }` like SettingsSeg, so keyboard nav can keep
 * the row's "seg" registry entry (←/→ step through `vals`).
 */
Item {
    id: drop

    property real s: 1
    property var options: []
    property var value
    property bool open: false
    property string accessibleName: ""
    signal picked(var value)

    readonly property string currentLabel: {
        for (var i = 0; i < options.length; i++)
            if (options[i].value === value)
                return options[i].label;
        return options.length ? options[0].label : "";
    }
    /** True while open or still animating closed — hosts key their z-raise on this. */
    readonly property bool showing: menu.showing

    implicitWidth: 136 * s
    implicitHeight: 26 * s

    Rectangle {
        id: field
        property bool hovered: false
        anchors.fill: parent
        radius: 9 * drop.s
        color: drop.open ? Qt.alpha(Colors.primary, 0.14)
            : (field.hovered ? Colors.surface_container_highest : "transparent")
        border.width: 1
        border.color: drop.open ? Qt.alpha(Colors.primary, 0.5) : Qt.alpha(Colors.on_surface, 0.06)
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

        Accessible.role: Accessible.ComboBox
        Accessible.name: drop.accessibleName
        Accessible.description: drop.currentLabel
        Accessible.onPressAction: drop.open = !drop.open

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10 * drop.s
            anchors.right: chev.left
            anchors.verticalCenter: parent.verticalCenter
            text: drop.currentLabel
            elide: Text.ElideRight
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 11.5 * drop.s
            font.weight: Font.DemiBold
        }

        GlyphIcon {
            id: chev
            anchors.right: parent.right
            anchors.rightMargin: 8 * drop.s
            anchors.verticalCenter: parent.verticalCenter
            width: 13 * drop.s
            height: 13 * drop.s
            name: drop.open ? "chevron-up" : "chevron-down"
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
            onClicked: drop.open = !drop.open
        }
    }

    DropMenu {
        id: menu
        anchors.top: field.bottom
        anchors.topMargin: 4 * drop.s
        anchors.right: parent.right
        width: Math.max(drop.width, 128 * drop.s)
        s: drop.s
        open: drop.open
        maxRows: 8
        options: drop.options
        isCurrent: (o) => o.value === drop.value
        onPicked: (o) => { drop.open = false; drop.picked(o.value); }
    }
}
