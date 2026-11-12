import QtQuick
import "../../services"

/**
 * astralis — collapsible full-width section for settings pages: a wrapper for
 * content that is not a SettingsRow (the curve editor, the preset block) but
 * toggles with a condition like one. `shown: cond` eases the height to/from 0
 * (clipped) and fades the content; children go in the default slot and size
 * themselves from their own explicit/implicit height. Same timing as
 * SettingsRow's collapse; pass `surface` (the owning SettingsPage) so the
 * first layout after the page activates snaps rather than animating shut.
 */
Item {
    id: c

    property bool shown: true
    property var surface: null
    default property alias content: inner.data

    width: parent ? parent.width : 0

    property bool settled: false
    readonly property bool animate: c.settled && (c.surface ? c.surface.hoverArmed : true)
    Component.onCompleted: Qt.callLater(() => c.settled = true)

    property real shownT: c.shown ? 1 : 0
    Behavior on shownT {
        enabled: c.animate
        NumberAnimation {
            duration: c.shown ? Motion.normalDur : Motion.expressiveFastSpatialDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.emphasized
        }
    }

    height: inner.childrenRect.height * c.shownT
    clip: c.shownT < 0.999
    opacity: c.shown ? 1 : 0
    // Opacity gates visibility (never height): a hidden item drops out of its
    // Column's layout and could not grow back.
    visible: c.shown || c.opacity > 0.01
    Behavior on opacity {
        enabled: c.animate
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    Item {
        id: inner
        width: c.width
    }
}
