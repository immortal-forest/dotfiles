import QtQuick
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — Material 3 badge: a dot for "something happened", a number for
 * "how many" (md-comp-badge v0.192).
 *
 *   count === 0   → a 6dp dot
 *   count  >  0   → a pill carrying the number, "99+" past `maxCount`
 *
 * Purely visual and position-agnostic BY DESIGN — this component only ever
 * draws its own dot/pill at its own implicit size. The host anchors it to
 * whatever it decorates (`anchors.top/rightMargin` on a tray icon, a corner
 * of an M3Card); baking a corner-anchor in here would make it useless for the
 * next caller who needs the opposite corner.
 *
 * JUDGEMENT CALL: `count` alone can't express "nothing to show" — 0 is
 * explicitly the dot state, not empty — so a negative count is treated as the
 * off sentinel (`count: hasUnread ? unread : -1`). That keeps the badge a
 * single persistent Item whose entrance/exit is a Behavior on its own
 * opacity/scale, never a created/destroyed Loader — the same shape the
 * memory bank's Repeater/count-rebuild note argues for anywhere state needs
 * to animate rather than snap.
 *
 *   M3Badge {
 *       s: root.s
 *       count: Notifications.unreadCount
 *       accessibleName: count + " unread notifications"
 *   }
 */
Item {
    id: badge

    property real s: 1
    property int count: 0
    property int maxCount: 99
    property string accessibleName: ""

    readonly property bool hasContent: badge.count >= 0
    readonly property bool isDot: badge.count === 0
    readonly property string countText: badge.count > badge.maxCount
        ? (badge.maxCount + "+")
        : String(badge.count)

    // md-comp-badge's large (numeric) badge padding — 4dp each side, not in
    // M3.qml (only the dot/numeric heights are). // spec: md-comp-badge v0.192
    readonly property real numericPadding: M3.badgeNumericPadding

    implicitWidth: badge.isDot ? dot.width : pill.width
    implicitHeight: badge.isDot ? dot.height : pill.height

    // Entrance/exit: scale from 0 on the Expressive spatial curve (the same
    // overshoot-bearing bezier M3Button uses for its press morph) plus an
    // opacity fade — a badge that snaps into existence reads as a layout bug,
    // one that pops is the whole point of the component.
    opacity: badge.hasContent ? 1 : 0
    scale: badge.hasContent ? 1 : 0
    visible: opacity > 0.01   // gate on opacity, never on a measured size
    transformOrigin: Item.Center

    Behavior on opacity { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Motion.easeStandard } }
    Behavior on scale {
        NumberAnimation {
            duration: Motion.expressiveFastSpatialDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveFastSpatial
        }
    }

    // No M3StateLayer — a badge has nothing to press. `StaticText` per the
    // coordinator's live-daemon finding; QML's Accessible attached type only
    // guarantees the roles it was actually tested with, and this one is.
    Accessible.role: Accessible.StaticText
    Accessible.name: badge.accessibleName

    Rectangle {
        id: dot
        visible: badge.isDot
        width: M3.badgeDotSize * badge.s
        height: M3.badgeDotSize * badge.s
        radius: width / 2
        color: Colors.error
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Rectangle {
        id: pill
        visible: !badge.isDot
        height: M3.badgeNumericSize * badge.s
        // Min width equals height (a single digit reads as a circle); wider
        // counts push it out by the label plus its own horizontal padding.
        width: Math.max(height, label.implicitWidth + badge.numericPadding * 2 * badge.s)
        radius: height / 2
        color: Colors.error

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        Text {
            id: label
            anchors.centerIn: parent
            text: badge.countText
            color: Colors.on_error
            // M3 label-small: 11sp / medium — Appearance.font has no numeric
            // type-scale, so this is inlined the same way M3Button inlines
            // its own label-large 14sp.
            font.family: Appearance.font.family
            font.pixelSize: 11 * badge.s
            font.weight: Font.Medium
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }
}
