pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../services" as Services
import "../../config"

/**
 * astralis — 報 NOTIFICATIONS settings page: the phone-style notification
 * controls. Do Not Disturb with daily quiet hours and an urgent bypass, how
 * long a popup stays, an optional chime, and one row per app that has ever
 * notified with Alert / Silent / Off — Alert pops up (and chimes), Silent
 * goes straight to the centre, Off drops the app's notifications outright.
 *
 * Everything persists through Flags (flags.json) and is pushed into the
 * Notifications service by Flags' Bindings; the app list itself comes from
 * the service's seen-apps cache (notif-apps.json) so a blocked app stays
 * listed and can be let back in.
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    readonly property var notifs: Services.Notifications

    readonly property var lengthOptions: [
        { label: "Short", value: "short" },
        { label: "Normal", value: "normal" },
        { label: "Long", value: "long" }
    ]
    readonly property var modeOptions: [
        { label: "Alert", value: "alert" },
        { label: "Silent", value: "silent" },
        { label: "Off", value: "off" }
    ]
    readonly property var modeVals: ["alert", "silent", "off"]

    readonly property var staticRows: [
        { item: dndRow, kind: "toggle", get: function () { return Flags.dnd; }, set: function (v) { Flags.dnd = v; } },
        { item: scheduleRow, kind: "toggle", get: function () { return Flags.dndSchedule; }, set: function (v) { Flags.dndSchedule = v; } },
        { item: fromRow, kind: "scrub", bump: function (d) { fromScrub.bump(d); } },
        { item: toRow, kind: "scrub", bump: function (d) { toScrub.bump(d); } },
        { item: urgentRow, kind: "toggle", get: function () { return Flags.dndUrgent; }, set: function (v) { Flags.dndUrgent = v; } },
        { item: lengthRow, kind: "seg", vals: ["short", "normal", "long"], get: function () { return Flags.notifPopup; }, set: function (v) { Flags.notifPopup = v; } },
        { item: soundRow, kind: "toggle", get: function () { return Flags.notifSound; }, set: function (v) { Flags.notifSound = v; } }
    ]
    property var appRowEntries: []
    rows: root.staticRows.concat(root.appRowEntries)

    function syncAppRows() {
        var out = [];
        for (var i = 0; i < appRep.count; i++) {
            var it = appRep.itemAt(i);
            if (!it) continue;
            out.push({
                item: it, kind: "seg", vals: root.modeVals,
                get: (function (a) { return function () { return root.notifs.modeFor(a); }; })(it.app),
                set: (function (a) { return function (v) { Flags.setNotifApp(a, v); }; })(it.app)
            });
        }
        root.appRowEntries = out;
    }

    /**
     * The app list is a plain array of labels, refreshed on page entry and
     * otherwise only when an app joins: a Repeater rebuilds every delegate on
     * any model reassignment, so re-sorting on each arrival would blink the
     * list while you're looking at it. Captions stay live per row.
     */
    property var appList: []
    function refreshApps() {
        var k = root.notifs.appKeys();
        if (k.length === root.appList.length && k.every(function (a) { return root.appList.indexOf(a) !== -1; }))
            return;
        root.appList = k;
    }
    onActiveChanged: if (active) refreshApps()
    Component.onCompleted: refreshApps()
    Connections {
        target: root.notifs
        function onKnownAppsChanged() { root.refreshApps(); }
        function onAppRulesChanged() { root.refreshApps(); }
    }

    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    function clockText(v) {
        var h = Math.floor(v / 60), m = v % 60;
        if (Flags.time12h)
            return ((h % 12) || 12) + ":" + root.pad2(m) + (h < 12 ? " AM" : " PM");
        return root.pad2(h) + ":" + root.pad2(m);
    }

    function ago(t) {
        void root.notifs.tick;
        void root.notifs.nowMin;
        if (!t) return "";
        var m = Math.floor((Date.now() - t) / 60000);
        if (m < 1) return "just now";
        if (m < 60) return m + "m ago";
        if (m < 1440) return Math.floor(m / 60) + "h ago";
        return Math.floor(m / 1440) + "d ago";
    }

    function captionFor(app) {
        var known = root.notifs.knownApps[app];
        var last = known ? known.last : 0;
        if (root.notifs.modeFor(app) === "off")
            return last ? "Blocked · last tried " + root.ago(last) : "Blocked";
        var gs = root.notifs.groups;
        for (var i = 0; i < gs.length; i++) {
            if (gs[i].app === app)
                return gs[i].count + " in the centre · " + root.ago(gs[i].t);
        }
        return last ? "Last one " + root.ago(last) : "Nothing recent";
    }

    readonly property string dndCaption: {
        if (root.notifs.dnd)
            return "On until you turn it off";
        if (root.notifs.inQuietHours)
            return "Quiet hours are on now, until " + root.clockText(Flags.dndTo);
        return "Hold popups; the centre still collects everything";
    }

    /** One app: its icon, name, a live caption, and the Alert / Silent / Off strip. */
    component AppRow: Item {
        id: arow
        required property string modelData
        required property int index
        readonly property string app: arow.modelData
        readonly property var known: root.notifs.knownApps[arow.app]
        readonly property string iconSrc: arow.known ? (arow.known.icon || "") : ""
        readonly property string mode: root.notifs.modeFor(arow.app)
        readonly property bool hot: ah.hovered || root.focusRowItem === arow
        readonly property real s: root.s
        // Device-pixel grid, same as SettingsRow (see PixelSnap): whole-pixel
        // height, insets and divider from a snapped top edge, so the divider
        // sits exactly midway between the highlights on either side.
        PixelSnap { id: snap; target: arow }
        readonly property real inset: snap.px(3 * arow.s)
        readonly property bool divided: arow.index < root.appList.length - 1

        width: parent ? parent.width : 0
        height: snap.px(Math.max(textCol.implicitHeight + 24 * arow.s, appSeg.height + 10 * arow.s))

        property bool entered: false
        function playEnter() {
            arow.entered = false;
            enterTimer.restart();
        }
        Component.onCompleted: if (root.active) arow.playEnter()
        Connections {
            target: root
            function onActiveChanged() {
                if (root.active)
                    arow.playEnter();
            }
        }
        Timer {
            id: enterTimer
            interval: Motion.rowStagger * Math.min(Math.max(root.rowIndexOf(arow), 0), 10)
            onTriggered: arow.entered = true
        }
        opacity: arow.entered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        transform: Translate {
            y: arow.entered ? 0 : 10 * arow.s
            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        }

        HoverHandler {
            id: ah
            onHoveredChanged: root.reportRowHover(arow, hovered)
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: arow.inset + snap.dy
            anchors.bottomMargin: arow.inset + (arow.divided ? snap.hair : 0) - snap.dy
            radius: 9 * arow.s
            color: arow.hot ? Colors.surface_container_highest : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        // App icon, else the kind's neutral glyph; faded while blocked.
        Item {
            id: lead
            anchors.left: parent.left
            anchors.leftMargin: 12 * arow.s
            anchors.verticalCenter: parent.verticalCenter
            width: 21 * arow.s
            height: 21 * arow.s
            opacity: arow.mode === "off" ? 0.4 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            Image {
                id: appImg
                anchors.fill: parent
                source: arow.iconSrc
                sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: status === Image.Ready ? 1 : 0
            }
            GlyphIcon {
                anchors.centerIn: parent
                width: 17 * arow.s
                height: 17 * arow.s
                visible: appImg.status !== Image.Ready
                name: arow.known && arow.known.glyph ? arow.known.glyph : "inbox"
                color: arow.hot ? Colors.on_surface : Colors.on_surface_variant
                stroke: 1.8
            }
        }

        Column {
            id: textCol
            anchors.left: lead.right
            anchors.leftMargin: 11 * arow.s
            anchors.right: appSeg.left
            anchors.rightMargin: 12 * arow.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * arow.s

            Text {
                width: parent.width
                text: arow.app
                elide: Text.ElideRight
                color: arow.mode === "off" ? Colors.on_surface_variant : Colors.on_surface
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                font.family: Appearance.font.family
                font.pixelSize: 12.5 * arow.s
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: root.captionFor(arow.app)
                elide: Text.ElideRight
                color: Qt.alpha(Colors.on_surface_variant, 0.85)
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * arow.s
            }
        }

        SettingsSeg {
            id: appSeg
            anchors.right: parent.right
            anchors.rightMargin: 14 * arow.s
            anchors.verticalCenter: parent.verticalCenter
            s: arow.s
            options: root.modeOptions
            value: arow.mode
            onPicked: (v) => Flags.setNotifApp(arow.app, v)
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -snap.dy
            anchors.left: parent.left
            anchors.right: parent.right
            height: snap.hair
            color: Qt.alpha(Colors.on_surface, 0.06)
            visible: arow.divided
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "報"
        title: "NOTIFICATIONS"
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

            SettingsSection {
                s: root.s
                surface: root
                title: "Quiet"
                key: "notifications/quiet"

                SettingsRow {
                    id: dndRow
                    surface: root
                    icon: "dnd"
                    name: "Do not disturb"
                    sub: root.dndCaption

                    LinkToggle {
                        s: root.s
                        on: Flags.dnd
                        accessibleName: "Do not disturb"
                        onToggled: Flags.dnd = !Flags.dnd
                    }
                }

                SettingsRow {
                    id: scheduleRow
                    surface: root
                    icon: "moon"
                    name: "Quiet hours"
                    sub: Flags.dndSchedule
                        ? "Every day, " + root.clockText(Flags.dndFrom) + " – " + root.clockText(Flags.dndTo)
                        : "Turn Do not disturb on by itself every night"

                    LinkToggle {
                        s: root.s
                        on: Flags.dndSchedule
                        accessibleName: "Quiet hours"
                        onToggled: Flags.dndSchedule = !Flags.dndSchedule
                    }
                }

                SettingsRow {
                    id: fromRow
                    surface: root
                    shown: Flags.dndSchedule
                    icon: "clock"
                    name: "Starts"

                    ScrubValue {
                        id: fromScrub
                        s: root.s
                        value: Flags.dndFrom
                        from: 0
                        to: 1425
                        step: 15
                        fmt: (v) => root.clockText(Math.round(v))
                        accessibleName: "Quiet hours start"
                        onEdited: (v) => Flags.dndFrom = Math.round(v)
                    }
                }

                SettingsRow {
                    id: toRow
                    surface: root
                    shown: Flags.dndSchedule
                    icon: "sun"
                    name: "Ends"

                    ScrubValue {
                        id: toScrub
                        s: root.s
                        value: Flags.dndTo
                        from: 0
                        to: 1425
                        step: 15
                        fmt: (v) => root.clockText(Math.round(v))
                        accessibleName: "Quiet hours end"
                        onEdited: (v) => Flags.dndTo = Math.round(v)
                    }
                }

                SettingsRow {
                    id: urgentRow
                    surface: root
                    icon: "bolt"
                    name: "Let urgent through"
                    sub: "Critical alerts still pop up while it's quiet"
                    captionOnFocus: true
                    last: true

                    LinkToggle {
                        s: root.s
                        on: Flags.dndUrgent
                        accessibleName: "Let urgent through"
                        onToggled: Flags.dndUrgent = !Flags.dndUrgent
                    }
                }
            }

            SettingsSection {
                s: root.s
                surface: root
                title: "Popups"
                key: "notifications/popups"

                SettingsRow {
                    id: lengthRow
                    surface: root
                    icon: "stopwatch"
                    name: "Popup length"
                    sub: "How long a popup stays before it tucks away"
                    captionOnFocus: true

                    SettingsSeg {
                        s: root.s
                        options: root.lengthOptions
                        value: Flags.notifPopup
                        onPicked: (v) => Flags.notifPopup = v
                    }
                }

                SettingsRow {
                    id: soundRow
                    surface: root
                    icon: "speaker"
                    name: "Sound"
                    sub: "Chime when a popup shows (apps can ask for their own)"
                    captionOnFocus: true
                    last: true

                    LinkToggle {
                        s: root.s
                        on: Flags.notifSound
                        accessibleName: "Notification sound"
                        onToggled: Flags.notifSound = !Flags.notifSound
                    }
                }
            }

            SettingsSection {
                s: root.s
                surface: root
                title: "Apps"
                key: "notifications/apps"

                Repeater {
                    id: appRep
                    model: root.appList
                    delegate: AppRow {}
                    onItemAdded: Qt.callLater(root.syncAppRows)
                    onItemRemoved: Qt.callLater(root.syncAppRows)
                }

                Text {
                    visible: root.appList.length === 0
                    topPadding: 6 * root.s
                    leftPadding: 12 * root.s
                    rightPadding: 12 * root.s
                    width: parent.width
                    text: "Apps show up here after they send their first notification."
                    color: Qt.alpha(Colors.on_surface_variant, 0.85)
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * root.s
                    wrapMode: Text.WordWrap
                }

                Text {
                    topPadding: 12 * root.s
                    leftPadding: 12 * root.s
                    rightPadding: 12 * root.s
                    width: parent.width
                    text: "Alert pops up in the pill (and chimes, if Sound is on). Silent skips the popup and goes straight to the centre. Off drops that app's notifications entirely — nothing is kept."
                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                    font.family: Appearance.font.family
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
