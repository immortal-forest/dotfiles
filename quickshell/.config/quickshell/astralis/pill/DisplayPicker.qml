pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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
    readonly property real listH: pick.open ? Math.min(options.length * 24 * pick.s + 4 * pick.s, 150 * pick.s) : 0

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

    /**
     * Shadow caster kept separate from the panel. A layer that holds the
     * option text would rasterise the glyphs to an offscreen texture and
     * soften them, so the shadow lives on this textless backing rect and the
     * panel above stays unlayered with crisp digits. Its own face hides behind
     * the opaque panel, only the shadow halo bleeds out.
     */
    Rectangle {
        anchors.fill: panel
        visible: pick.open
        radius: panel.radius
        color: Colors.surface_container
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colors.shadow
            shadowBlur: 0.6
            shadowVerticalOffset: 4 * pick.s
        }
    }

    Rectangle {
        id: panel
        anchors.top: head.bottom
        anchors.topMargin: pick.open ? pick.gap : 0
        anchors.left: parent.left
        anchors.leftMargin: 72 * pick.s
        anchors.right: parent.right
        height: pick.listH
        visible: pick.open
        clip: true
        radius: 9 * pick.s
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.surface_container_high }
            GradientStop { position: 1.0; color: Colors.surface_container }
        }
        border.width: 1
        border.color: Qt.alpha(Colors.on_surface, 0.09)

        ListView {
            anchors.fill: parent
            anchors.margins: 2 * pick.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: pick.options

            delegate: Rectangle {
                id: optRow
                required property var modelData
                readonly property bool current: pick.value === modelData.value

                width: ListView.view.width
                height: 24 * pick.s
                radius: 7 * pick.s
                color: optHover.hovered ? Colors.surface_container_highest
                    : (optRow.current ? Qt.alpha(Colors.primary, 0.16) : "transparent")
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                scale: optArea.pressed ? 0.96 : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.glide
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }

                Accessible.role: Accessible.ListItem
                Accessible.name: optRow.modelData.label
                Accessible.checkable: true
                Accessible.checked: optRow.current
                Accessible.onPressAction: optArea.clicked(null)

                HoverHandler { id: optHover }

                DisplayLabel {
                    anchors.left: parent.left
                    anchors.leftMargin: 9 * pick.s
                    anchors.verticalCenter: parent.verticalCenter
                    s: pick.s
                    text: optRow.modelData.label
                    color: optRow.current ? Colors.on_surface : Colors.on_surface_variant
                    weight: optRow.current ? Font.Bold : Font.Medium
                }

                MouseArea {
                    id: optArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pick.picked(optRow.modelData.value)
                }
            }
        }
    }
}
