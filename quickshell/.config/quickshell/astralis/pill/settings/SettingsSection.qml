pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"

/**
 * astralis — a collapsible settings group: the uppercase group label as a
 * clickable header with a chevron, over the run of rows it heads (children go
 * in the default slot and stack in a Column). Clicking the header folds the
 * rows away; the state is kept per `key` in Flags.collapsedSections
 * (flags.json), so a page reopens the way it was left.
 *
 * `shown: cond` folds the whole section, header included, with the same
 * height-ease + fade as a SettingsRow (Animation's Curve/Preset groups that
 * only exist while animations are on). Pass `surface` (the owning
 * SettingsPage) so the first layout after the page activates snaps rather
 * than animating, and so collapsing a section drops row focus that sat in it.
 */
Item {
    id: sec

    property real s: 1
    property var surface: null
    property string title: ""
    /** Persistence key; unique per page ("widgets/lyrics"). */
    property string key: title
    property bool shown: true
    default property alias content: body.data

    readonly property bool collapsed: Flags.collapsedSections[sec.key] === true

    function toggle() {
        if (!sec.collapsed && sec.surface && sec.holds(sec.surface.focusRowItem))
            sec.surface.focusRowItem = null;
        Flags.setSectionCollapsed(sec.key, !sec.collapsed);
    }

    function holds(item) {
        for (var p = item; p; p = p.parent)
            if (p === body)
                return true;
        return false;
    }

    width: parent ? parent.width : 0

    property bool settled: false
    readonly property bool animate: sec.settled && (sec.surface ? sec.surface.hoverArmed : true)
    Component.onCompleted: Qt.callLater(() => sec.settled = true)

    property real shownT: sec.shown ? 1 : 0
    Behavior on shownT {
        enabled: sec.animate
        NumberAnimation {
            duration: sec.shown ? Motion.normalDur : Motion.expressiveFastSpatialDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.emphasized
        }
    }
    height: stack.height * sec.shownT
    clip: sec.shownT < 0.999
    opacity: sec.shown ? 1 : 0
    // Opacity gates visibility (never height): a hidden item drops out of its
    // Column's layout and could not grow back.
    visible: sec.shown || sec.opacity > 0.01
    Behavior on opacity {
        enabled: sec.animate
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    Column {
        id: stack
        width: sec.width

        Item {
            id: head
            width: parent.width
            height: label.implicitHeight

            Accessible.role: Accessible.Button
            Accessible.name: sec.title + (sec.collapsed ? ", collapsed" : ", expanded")
            Accessible.onPressAction: sec.toggle()

            // State layer over the label line only (not the top padding), so
            // the hover reads as the header's own pill rather than a slab.
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: label.topPadding - 6 * sec.s
                anchors.bottomMargin: 1 * sec.s
                radius: 9 * sec.s
                color: headArea.pressed ? Qt.alpha(Colors.primary, 0.10)
                    : headArea.containsMouse ? Qt.alpha(Colors.on_surface, 0.05) : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            SettingsGroupLabel {
                id: label
                s: sec.s
                text: sec.title
                color: headArea.containsMouse ? Colors.on_surface_variant
                    : Qt.alpha(Colors.on_surface_variant, 0.65)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            GlyphIcon {
                id: chevron
                anchors.right: parent.right
                anchors.rightMargin: 16 * sec.s
                anchors.verticalCenter: label.verticalCenter
                anchors.verticalCenterOffset: (label.topPadding - label.bottomPadding) / 2
                width: 12 * sec.s
                height: 12 * sec.s
                name: "chevron-right"
                stroke: 2.2
                color: label.color
                // Down while open, right while folded.
                rotation: sec.collapsed ? 0 : 90
                Behavior on rotation {
                    NumberAnimation {
                        duration: Motion.expressiveFastSpatialDur
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }
            }

            MouseArea {
                id: headArea
                anchors.fill: parent
                anchors.topMargin: label.topPadding - 6 * sec.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sec.toggle()
            }
        }

        SettingsCollapse {
            shown: !sec.collapsed
            surface: sec.surface

            Column {
                id: body
                width: parent.width
            }
        }
    }
}
