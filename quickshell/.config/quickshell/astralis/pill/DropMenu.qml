pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../colors"
import "../services"
import "../config"

/**
 * astralis — the shell's one dropdown menu panel. Hosts place it under the
 * control that opened it and drive `open`; the panel unrolls from its top
 * edge (spatial spring on the y-scale, effects curve on the fade) and rolls
 * back up on close, staying visible until the fade lands so the host can keep
 * it z-raised through the exit (`showing`).
 *
 * The current option carries a check glyph and primary label on a
 * secondary-container fill; hover is a separate on_surface state layer drawn
 * over either, so "this is selected" and "the pointer is here" never read as
 * the same thing. Labels containing "×" go through DisplayLabel so resolution
 * digits keep the shell face.
 *
 * `options` is any array; `labelOf(o)` and `isCurrent(o)` adapt it. Picking
 * emits picked(o) — the host closes the menu.
 */
Item {
    id: menu

    property real s: 1
    property bool open: false
    property var options: []
    property var labelOf: (o) => (o && o.label !== undefined) ? String(o.label) : String(o)
    property var isCurrent: (o) => false
    /** Rows shown before the list scrolls. */
    property int maxRows: 6
    signal picked(var option)

    readonly property real rowH: 26 * s
    readonly property real pad: 3 * s
    /** True from the moment it starts opening until the close fade ends. */
    readonly property bool showing: visible

    implicitWidth: 180 * s
    height: Math.min(options.length, maxRows) * rowH + 2 * pad
    visible: opacity > 0.01
    opacity: open ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Motion.expressiveEffectsDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveEffects
        }
    }

    transform: Scale {
        origin.x: menu.width / 2
        origin.y: 0
        yScale: menu.open ? 1 : 0.82
        xScale: menu.open ? 1 : 0.96
        Behavior on yScale {
            NumberAnimation {
                duration: Motion.expressiveFastSpatialDur
                easing.type: Motion.easeBezier
                easing.bezierCurve: menu.open ? Motion.expressiveFastSpatial : Motion.emphasizedAccel
            }
        }
        Behavior on xScale {
            NumberAnimation {
                duration: Motion.expressiveFastSpatialDur
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveDefaultSpatial
            }
        }
    }

    // Swallow clicks on the panel's own padding so they don't fall through
    // to a host's outside-click catcher underneath.
    MouseArea { anchors.fill: parent }

    /**
     * Shadow caster kept apart from the option text: a layer holding the
     * labels would rasterise them offscreen and soften the glyphs.
     */
    Rectangle {
        anchors.fill: panel
        radius: panel.radius
        color: Colors.surface_container
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha(Colors.shadow, Appearance.elevation.shadowOpacity)
            shadowBlur: 0.6
            shadowVerticalOffset: 4 * menu.s
        }
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 11 * menu.s
        color: Colors.surface_container_high
        border.width: 1
        border.color: Qt.alpha(Colors.outline_variant, 0.7)
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: menu.pad
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: menu.options

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: menu.isCurrent(modelData)
                readonly property string label: menu.labelOf(modelData)

                width: ListView.view.width
                height: menu.rowH

                Accessible.role: Accessible.RadioButton
                Accessible.name: row.label
                Accessible.checkable: true
                Accessible.checked: row.current
                Accessible.focusable: true
                Accessible.onPressAction: menu.picked(row.modelData)

                Rectangle {
                    id: chip
                    anchors.fill: parent
                    radius: 8 * menu.s
                    color: row.current ? Colors.secondary_container : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    scale: rowArea.pressed ? 0.97 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    // Hover/press state layer, over the selection fill.
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: row.current ? Colors.on_secondary_container : Colors.on_surface
                        opacity: rowArea.pressed ? 0.12 : (rowArea.containsMouse ? 0.08 : 0)
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }

                    GlyphIcon {
                        id: tick
                        anchors.left: parent.left
                        anchors.leftMargin: 7 * menu.s
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * menu.s
                        height: width
                        name: "check"
                        stroke: 2.2
                        color: Colors.on_secondary_container
                        opacity: row.current ? 1 : 0
                        scale: row.current ? 1 : 0.4
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }
                    }

                    readonly property color labelColor: row.current ? Colors.on_secondary_container
                        : (rowArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant)

                    DisplayLabel {
                        visible: row.label.indexOf("×") >= 0
                        anchors.left: tick.right
                        anchors.leftMargin: 6 * menu.s
                        anchors.verticalCenter: parent.verticalCenter
                        s: menu.s
                        text: row.label
                        color: chip.labelColor
                        weight: row.current ? Font.Bold : Font.Medium
                    }
                    Text {
                        visible: row.label.indexOf("×") < 0
                        anchors.left: tick.right
                        anchors.leftMargin: 6 * menu.s
                        anchors.right: parent.right
                        anchors.rightMargin: 9 * menu.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.label
                        elide: Text.ElideRight
                        color: chip.labelColor
                        font.family: Appearance.font.family
                        font.pixelSize: 10.5 * menu.s
                        font.weight: row.current ? Font.Bold : Font.Medium
                        font.features: ({ "tnum": 1 })
                    }
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menu.picked(row.modelData)
                }
            }
        }
    }

    /** Scroll the current option into view each time the menu opens. */
    onOpenChanged: if (open) {
        for (var i = 0; i < options.length; i++)
            if (isCurrent(options[i])) { list.positionViewAtIndex(i, ListView.Contain); break; }
    }
}
