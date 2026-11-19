pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 眠 APP NAP settings page for appnap (~/.local/bin/appnap,
 * Super+Ctrl+M): whether a nap frees the app's memory or only freezes it,
 * notifications, the live list of what sits in the minimized tray (a nap /
 * wake switch each, same as right-clicking its chip), and auto-nap: apps left
 * minimized for a while nap on their own, minus the ones playing audio and the
 * ones switched off below. Prefs live in Flags (flags.json), which the script
 * reads on every nap; nap state comes from the AppNap service.
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    readonly property var autoOptions: [
        { label: "Off", value: 0 }, { label: "5 min", value: 5 }, { label: "15 min", value: 15 },
        { label: "30 min", value: 30 }, { label: "60 min", value: 60 }
    ]

    property var trayRowEntries: []
    property var appRowEntries: []
    rows: [
        { item: swapRow, kind: "toggle", get: function () { return Flags.napSwap; }, set: function (v) { Flags.napSwap = v; } },
        { item: notifyRow, kind: "toggle", get: function () { return Flags.napNotify; }, set: function (v) { Flags.napNotify = v; } }
    ].concat(root.trayRowEntries, [
        { item: autoRow, kind: "seg", vals: root.autoOptions.map(function (o) { return o.value; }), get: function () { return Flags.napAutoMin; }, set: function (v) { Flags.napAutoMin = v; } },
        { item: audioRow, kind: "toggle", get: function () { return Flags.napSkipAudio; }, set: function (v) { Flags.napSkipAudio = v; } }
    ], root.appRowEntries)

    function syncTrayRows() {
        var out = [];
        for (var i = 0; i < trayRep.count; i++) {
            var it = trayRep.itemAt(i);
            if (it)
                out.push({
                    item: it, kind: "toggle",
                    get: (function (a) { return function () { return AppNap.isNapped(a); }; })(it.address),
                    set: (function (a) { return function (v) { if (v) AppNap.nap(a); else AppNap.wake(a); }; })(it.address)
                });
        }
        root.trayRowEntries = out;
    }
    function syncAppRows() {
        var out = [];
        for (var i = 0; i < appRep.count; i++) {
            var it = appRep.itemAt(i);
            if (it)
                out.push({
                    item: it, kind: "toggle",
                    get: (function (c) { return function () { return !Flags.napNever[c]; }; })(it.cls),
                    set: (function (c) { return function (v) { Flags.setNapNever(c, !v); }; })(it.cls)
                });
        }
        root.appRowEntries = out;
    }

    // Windows to skip: the shell's own and Hyprland's dialogs are never napped.
    function isDesktop(cls) {
        var c = String(cls).toLowerCase();
        return c === "" || c.indexOf("quickshell") !== -1 || c === "hyprland-dialog";
    }

    /**
     * The two lists are reassigned only when their membership changes: a
     * Repeater rebuilds every delegate on model reassignment, and a browser
     * retitles itself constantly. Titles and nap state bind live per row.
     */
    readonly property var trayNow: {
        var out = [];
        var tl = Hyprland.toplevels.values;
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            if (t && t.workspace && t.workspace.name === "special:minimized" && !root.isDesktop(AppNap.classOf(t)))
                out.push({ address: AppNap.norm(t.address), cls: AppNap.classOf(t), toplevel: t });
        }
        return out;
    }
    property var trayList: []
    onTrayNowChanged: {
        var sig = trayNow.map(function (r) { return r.address + "|" + r.cls; }).join(",");
        if (sig !== root.trayList.map(function (r) { return r.address + "|" + r.cls; }).join(","))
            root.trayList = trayNow;
    }

    readonly property var appsNow: {
        var seen = {};
        var out = [];
        var tl = Hyprland.toplevels.values;
        for (var i = 0; i < tl.length; i++) {
            var c = AppNap.classOf(tl[i]);
            if (!root.isDesktop(c) && !seen[c]) {
                seen[c] = true;
                out.push(c);
            }
        }
        for (var k in Flags.napNever)
            if (!seen[k]) {
                seen[k] = true;
                out.push(k);
            }
        return out.map(function (c) { return { cls: c, name: AppNap.appMeta(c).name }; })
            .sort(function (a, b) { return a.name.toLowerCase().localeCompare(b.name.toLowerCase()); });
    }
    property var appList: []
    onAppsNowChanged: {
        var sig = appsNow.map(function (r) { return r.cls; }).join(",");
        if (sig !== root.appList.map(function (r) { return r.cls; }).join(","))
            root.appList = appsNow;
    }

    Component.onCompleted: {
        root.trayList = root.trayNow;
        root.appList = root.appsNow;
    }

    // Clock for the "napped 12 min" captions, ticking only while the page is up.
    property real now: Date.now()
    Timer {
        interval: 30000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    function ago(sec) {
        var m = Math.max(0, Math.round((root.now / 1000 - sec) / 60));
        return m < 1 ? "just now" : (m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " min");
    }
    function napCaption(info) {
        if (!info)
            return "Minimized, still running";
        var parts = ["Napped " + root.ago(info.since)];
        if (info.freed > 1048576)
            parts.push(Math.round(info.freed / 1048576) + " MB freed");
        else if (info.kind === "session")
            parts.push("frozen only");
        return parts.join(" · ");
    }

    /**
     * One app line: its icon (glyph fallback), a name and caption, and a
     * switch. Same metrics, hover, page-enter cascade and divider as the
     * other settings rows; a click anywhere on it flips the switch.
     */
    component AppToggleRow: Item {
        id: arow
        property string cls: ""
        property string label: ""
        property string caption: ""
        property bool on: false
        property bool faded: false
        property bool last: false
        signal flipped
        readonly property string iconSrc: AppNap.appMeta(arow.cls).icon
        readonly property bool hot: ah.hovered || root.focusRowItem === arow
        readonly property real s: root.s
        PixelSnap { id: snap; target: arow }
        readonly property real inset: snap.px(3 * arow.s)

        width: parent ? parent.width : 0
        height: snap.px(Math.max(textCol.implicitHeight + 24 * arow.s, 42 * arow.s))

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
            anchors.bottomMargin: arow.inset + (arow.last ? 0 : snap.hair) - snap.dy
            radius: 9 * arow.s
            color: arow.hot ? Colors.surface_container_highest : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activateRow(arow)
        }

        Item {
            id: lead
            anchors.left: parent.left
            anchors.leftMargin: 12 * arow.s
            anchors.verticalCenter: parent.verticalCenter
            width: 21 * arow.s
            height: 21 * arow.s
            opacity: arow.faded ? 0.45 : 1
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
                name: "app-window"
                color: arow.hot ? Colors.on_surface : Colors.on_surface_variant
                stroke: 1.8
            }
        }

        Column {
            id: textCol
            anchors.left: lead.right
            anchors.leftMargin: 11 * arow.s
            anchors.right: toggle.left
            anchors.rightMargin: 12 * arow.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * arow.s

            Text {
                width: parent.width
                text: arow.label
                elide: Text.ElideRight
                color: arow.faded ? Colors.on_surface_variant : Colors.on_surface
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                font.family: Appearance.font.family
                font.pixelSize: 12.5 * arow.s
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: arow.caption
                elide: Text.ElideRight
                color: Qt.alpha(Colors.on_surface_variant, 0.85)
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * arow.s
            }
        }

        LinkToggle {
            id: toggle
            anchors.right: parent.right
            anchors.rightMargin: 12 * arow.s
            anchors.verticalCenter: parent.verticalCenter
            s: arow.s
            on: arow.on
            accessibleName: arow.label
            onToggled: arow.flipped()
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -snap.dy
            anchors.left: parent.left
            anchors.right: parent.right
            height: snap.hair
            color: Qt.alpha(Colors.on_surface, 0.06)
            visible: !arow.last
        }
    }

    /** Name + caption on one line, the segmented control stacked below (IdleLockPage's IdleRow). */
    component SegRow: Item {
        id: srow
        property string icon: ""
        property string name: ""
        property string caption: ""
        property bool last: false
        default property alias seg: segSlot.data
        readonly property real s: root.s
        PixelSnap { id: snap; target: srow }
        readonly property real inset: snap.px(3 * srow.s)

        width: parent ? parent.width : 0
        height: snap.px(col.implicitHeight + 22 * srow.s)

        property bool entered: false
        function playEnter() {
            srow.entered = false;
            enterTimer.restart();
        }
        Component.onCompleted: if (root.active) srow.playEnter()
        Connections {
            target: root
            function onActiveChanged() {
                if (root.active)
                    srow.playEnter();
            }
        }
        Timer {
            id: enterTimer
            interval: Motion.rowStagger * Math.min(Math.max(root.rowIndexOf(srow), 0), 10)
            onTriggered: srow.entered = true
        }
        opacity: srow.entered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        transform: Translate {
            y: srow.entered ? 0 : 10 * srow.s
            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        }

        HoverHandler {
            id: sh
            onHoveredChanged: root.reportRowHover(srow, hovered)
        }

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: srow.inset + snap.dy
            anchors.bottomMargin: srow.inset + (srow.last ? 0 : snap.hair) - snap.dy
            radius: 9 * srow.s
            color: (sh.hovered || root.focusRowItem === srow) ? Colors.surface_container_highest : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        GlyphIcon {
            anchors.left: parent.left
            anchors.leftMargin: 14 * srow.s
            y: col.y + 1.5 * srow.s
            visible: srow.icon.length > 0
            width: 17 * srow.s
            height: 17 * srow.s
            name: srow.icon
            color: (sh.hovered || root.focusRowItem === srow) ? Colors.on_surface : Colors.on_surface_variant
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            stroke: 1.8
        }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: (srow.icon.length > 0 ? 14 + 17 + 13 : 12) * srow.s
            anchors.rightMargin: 12 * srow.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * srow.s

            Text {
                text: srow.name
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 12.5 * srow.s
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                visible: srow.caption.length > 0
                text: srow.caption
                wrapMode: Text.WordWrap
                color: Qt.alpha(Colors.on_surface_variant, 0.85)
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * srow.s
            }
            Item { width: 1; height: 7 * srow.s }
            Item {
                id: segSlot
                width: childrenRect.width
                height: childrenRect.height
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -snap.dy
            anchors.left: parent.left
            anchors.right: parent.right
            height: snap.hair
            color: Qt.alpha(Colors.on_surface, 0.06)
            visible: !srow.last
        }
    }

    component Note: Text {
        topPadding: 6 * root.s
        leftPadding: 12 * root.s
        rightPadding: 12 * root.s
        bottomPadding: 4 * root.s
        width: parent ? parent.width : 0
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 9.5 * root.s
        font.weight: Font.Medium
        wrapMode: Text.WordWrap
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "眠"
        title: "APP NAP"
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

            SettingsGroupLabel { s: root.s; text: "Napping" }

            SettingsRow {
                id: swapRow
                surface: root
                name: "Free its memory"
                sub: "Push a napped app's RAM to swap. Off: freeze only, so it wakes instantly"
                captionOnFocus: true
                icon: "chip"

                LinkToggle {
                    s: root.s
                    on: Flags.napSwap
                    onToggled: Flags.napSwap = !Flags.napSwap
                }
            }

            SettingsRow {
                id: notifyRow
                surface: root
                name: "Notify"
                sub: "Say when an app naps and how much memory it gave back"
                captionOnFocus: true
                icon: "inbox"
                last: true

                LinkToggle {
                    s: root.s
                    on: Flags.napNotify
                    onToggled: Flags.napNotify = !Flags.napNotify
                }
            }

            SettingsGroupLabel { s: root.s; text: "In the minimized tray" }

            Repeater {
                id: trayRep
                model: root.trayList
                delegate: AppToggleRow {
                    id: trow
                    required property var modelData
                    required property int index
                    readonly property string address: trow.modelData.address
                    readonly property var napInfo: AppNap.info(trow.address)
                    cls: trow.modelData.cls
                    label: {
                        var t = trow.modelData.toplevel;
                        var title = t ? (t.title || (t.lastIpcObject && t.lastIpcObject.title) || "") : "";
                        var name = AppNap.appMeta(trow.cls).name;
                        return title.length && title !== name ? name + " — " + title : name;
                    }
                    caption: root.napCaption(trow.napInfo)
                    on: trow.napInfo !== null
                    faded: trow.napInfo !== null
                    last: trow.index === root.trayList.length - 1
                    onFlipped: AppNap.toggle(trow.address)
                }
                onItemAdded: Qt.callLater(root.syncTrayRows)
                onItemRemoved: Qt.callLater(root.syncTrayRows)
            }

            Note {
                visible: root.trayList.length === 0
                text: "Nothing minimized. Super+Shift+M minimizes a window; Super+Ctrl+M minimizes and naps it."
            }

            SettingsGroupLabel { s: root.s; text: "Auto-nap" }

            SegRow {
                id: autoRow
                icon: "suspend"
                name: "Nap minimized apps"
                caption: "Apps left in the minimized tray this long nap on their own"

                SettingsSeg {
                    s: root.s
                    flushLeft: true
                    options: root.autoOptions
                    value: Flags.napAutoMin
                    onPicked: (v) => Flags.napAutoMin = v
                }
            }

            SettingsRow {
                id: audioRow
                surface: root
                name: "Skip apps playing audio"
                sub: "Music, videos and calls keep going while minimized"
                captionOnFocus: true
                icon: "speaker"
                last: true

                LinkToggle {
                    s: root.s
                    on: Flags.napSkipAudio
                    onToggled: Flags.napSkipAudio = !Flags.napSkipAudio
                }
            }

            SettingsGroupLabel { s: root.s; text: "Apps auto-nap may take" }

            Repeater {
                id: appRep
                model: root.appList
                delegate: AppToggleRow {
                    id: prow
                    required property var modelData
                    required property int index
                    readonly property bool allowed: !Flags.napNever[prow.cls]
                    cls: prow.modelData.cls
                    label: prow.modelData.name
                    caption: prow.allowed
                        ? (Flags.napAutoMin > 0 ? "Naps after " + Flags.napAutoMin + " min minimized" : "May auto-nap (auto-nap is off)")
                        : "Never auto-napped"
                    on: prow.allowed
                    faded: !prow.allowed || Flags.napAutoMin === 0
                    last: prow.index === root.appList.length - 1
                    onFlipped: Flags.setNapNever(prow.cls, prow.allowed)
                }
                onItemAdded: Qt.callLater(root.syncAppRows)
                onItemRemoved: Qt.callLater(root.syncAppRows)
            }

            Note {
                topPadding: 12 * root.s
                text: "Super+Ctrl+M naps the focused app: it moves to the minimized tray, stops using CPU and gives its memory back. "
                    + "Click its tray chip or press Super+Shift+M to bring it back; right-click a chip to nap or wake it in place. "
                    + "While napped an app sends no notifications and plays nothing. Auto-nap never takes an app with a window "
                    + "still on screen. Apps started by a plain Hyprland exec freeze without freeing memory."
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
