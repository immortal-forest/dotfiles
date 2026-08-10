pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 錠 IDLE / LOCK settings page (ported from Ricelin
 * pill/IdleLock.qml): the idle timeouts held in minutes (0 = off) — dim the
 * panel, blank the display (DPMS), lock the session, suspend the machine —
 * plus the lock-before-sleep preference. All of it backs onto the Flags
 * singleton (flags.json), exactly like Ricelin's Flags.idle* trio; astralis
 * adds the dim timeout and the sleep-lock toggle.
 *
 * Ricelin delta — GRACEFUL DEGRADATION: Ricelin regenerates
 * ~/.config/hypr/hypridle.conf from these values on every pick and restarts
 * the hypridle user unit (see Ricelin IdleLock.qml buildConf()/apply()).
 * astralis now ships this daemon: services/Hypridle.qml regenerates the conf
 * on every pick and (re)starts the hypridle user unit (enabled by default —
 * lock at 5 min, screen-off at 6), so picks apply immediately. It wires: dim → a
 * brightnessctl listener, screen-off → `hyprctl dispatch dpms off/on`,
 * lock → the lock command listener, suspend → `systemctl suspend`, and
 * lockBeforeSleep → `before_sleep_cmd = loginctl lock-session`.
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    readonly property var dimOptions: [
        { label: "Off", value: 0 }, { label: "1 min", value: 1 }, { label: "3 min", value: 3 },
        { label: "5 min", value: 5 }, { label: "10 min", value: 10 }
    ]
    readonly property var screenOptions: [
        { label: "Off", value: 0 }, { label: "3 min", value: 3 }, { label: "5 min", value: 5 },
        { label: "10 min", value: 10 }, { label: "15 min", value: 15 }
    ]
    readonly property var lockOptions: [
        { label: "Off", value: 0 }, { label: "1 min", value: 1 }, { label: "3 min", value: 3 },
        { label: "5 min", value: 5 }, { label: "10 min", value: 10 }, { label: "15 min", value: 15 }
    ]
    readonly property var suspendOptions: [
        { label: "Off", value: 0 }, { label: "15 min", value: 15 },
        { label: "30 min", value: 30 }, { label: "60 min", value: 60 }
    ]

    rows: [
        { item: dimRow, kind: "seg", vals: root.dimOptions.map(function (o) { return o.value; }), get: function () { return Flags.idleDimMin; }, set: function (v) { Flags.idleDimMin = v; } },
        { item: screenRow, kind: "seg", vals: root.screenOptions.map(function (o) { return o.value; }), get: function () { return Flags.idleScreenOffMin; }, set: function (v) { Flags.idleScreenOffMin = v; } },
        { item: lockRow, kind: "seg", vals: root.lockOptions.map(function (o) { return o.value; }), get: function () { return Flags.idleLockMin; }, set: function (v) { Flags.idleLockMin = v; } },
        { item: suspendRow, kind: "seg", vals: root.suspendOptions.map(function (o) { return o.value; }), get: function () { return Flags.idleSuspendMin; }, set: function (v) { Flags.idleSuspendMin = v; } },
        { item: sleepLockRow, kind: "toggle", get: function () { return Flags.lockBeforeSleep; }, set: function (v) { Flags.lockBeforeSleep = v; } }
    ]

    /**
     * One idle row: name and caption on their own full-width line with the
     * segmented control stacked below, so a six-option strip never squeezes
     * the caption into a narrow wrapping column. Hover lights the row and
     * feeds the soul seam, matching the rest of the settings rows.
     */
    component IdleRow: Item {
        id: irow
        property string icon: ""
        property string name: ""
        property string caption: ""
        property bool last: false
        default property alias seg: segSlot.data
        readonly property real s: root.s

        width: parent ? parent.width : 0
        height: col.implicitHeight + 22 * irow.s

        HoverHandler {
            id: ih
            onHoveredChanged: root.reportRowHover(irow, hovered)
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 3 * irow.s
            anchors.bottomMargin: 3 * irow.s
            radius: 9 * irow.s
            color: (ih.hovered || root.focusRowItem === irow) ? Colors.surface_container_highest : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        // Leading glyph, aligned with the name line same as every other
        // settings row (CardRow in DisplayPage.qml, SettingsRow elsewhere) —
        // pinned near col's top rather than centred on the whole row, since
        // col grows taller than a single line once the segmented control and
        // caption are counted.
        GlyphIcon {
            id: irowIcon
            anchors.left: parent.left
            anchors.leftMargin: 12 * irow.s
            y: col.y + 2 * irow.s
            visible: irow.icon.length > 0
            width: 16 * irow.s
            height: 16 * irow.s
            name: irow.icon
            color: (ih.hovered || root.focusRowItem === irow) ? Colors.on_surface : Colors.on_surface_variant
            stroke: 1.8
        }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: (irow.icon.length > 0 ? 12 + 16 + 9 : 12) * irow.s
            anchors.rightMargin: 12 * irow.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * irow.s

            Text {
                text: irow.name
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 12.5 * irow.s
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                visible: irow.caption.length > 0
                text: irow.caption
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * irow.s
            }
            Item { width: 1; height: 7 * irow.s }
            Item {
                id: segSlot
                width: childrenRect.width
                height: childrenRect.height
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.alpha(Colors.on_surface, 0.06)
            visible: !irow.last
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "錠"
        title: "IDLE / LOCK"
        onBack: root.back()
    }

    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.topMargin: 4 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: returnToBounds()

        Column {
            id: content
            width: flick.width
            spacing: 0

            Item { width: 1; height: 12 * root.s }

            IdleRow {
                id: dimRow
                icon: "sun"
                name: "Dim screen"
                caption: "Soften the backlight after idle"

                SettingsSeg {
                    s: root.s
                    flushLeft: true
                    options: root.dimOptions
                    value: Flags.idleDimMin
                    onPicked: (v) => Flags.idleDimMin = v
                }
            }

            IdleRow {
                id: screenRow
                icon: "monitor"
                name: "Screen off"
                caption: "Blank the display after idle"

                SettingsSeg {
                    s: root.s
                    flushLeft: true
                    options: root.screenOptions
                    value: Flags.idleScreenOffMin
                    onPicked: (v) => Flags.idleScreenOffMin = v
                }
            }

            IdleRow {
                id: lockRow
                icon: "lock"
                name: "Auto-lock"
                caption: "Lock the screen after idle"

                SettingsSeg {
                    s: root.s
                    flushLeft: true
                    options: root.lockOptions
                    value: Flags.idleLockMin
                    onPicked: (v) => Flags.idleLockMin = v
                }
            }

            IdleRow {
                id: suspendRow
                icon: "suspend"
                name: "Suspend"
                caption: "Sleep the machine after idle"
                last: true

                SettingsSeg {
                    s: root.s
                    flushLeft: true
                    options: root.suspendOptions
                    value: Flags.idleSuspendMin
                    onPicked: (v) => Flags.idleSuspendMin = v
                }
            }

            SettingsRow {
                id: sleepLockRow
                surface: root
                name: "Lock before sleep"
                sub: "Lock the session on the way into suspend"
                captionOnFocus: true
                icon: "lock"
                last: true

                LinkToggle {
                    s: root.s
                    on: Flags.lockBeforeSleep
                    onToggled: Flags.lockBeforeSleep = !Flags.lockBeforeSleep
                }
            }

            Text {
                topPadding: 12 * root.s
                leftPadding: 12 * root.s
                rightPadding: 12 * root.s
                width: parent.width
                text: "Hypridle is running — these apply live: it dims the backlight, blanks the display, locks the session and suspends on the timeouts above (defaults: screen off at 6 min, lock at 5 min). Keep-awake (in the mixer) pauses all of it while on."
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
