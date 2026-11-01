pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "../../colors"
import "../../services"
import "../../services" as Services
import "../../config"
import "../../pill"
import "../../pill/m3"

/**
 * astralis — 覧 overview: a full-screen glance overlay on the focused monitor.
 * Blurred desktop (Hyprland layer rule on `astralis-dashboard`) under a light
 * scrim, a three-column bento of tiles over it:
 *
 *   when    — clock, weather + hourly strip, month calendar + next event
 *   now     — media, quick toggles + volume/brightness, workspace map
 *   machine — battery (gauge, history curve, draw/health/profile),
 *             CPU/RAM sparklines, latest notification
 *
 * Every tile is a door: tapping its body opens the matching pill surface
 * (openSurface) and closes the overlay. Controls inside a tile act in place.
 * Tiles drop in from the pill's edge column by column on open and lift back
 * on close; the window stays mapped through the exit (_closing).
 */
PanelWindow {
    id: root

    property real s: 1
    property bool open: false
    /** Idle-inhibit state, owned by shell.qml (its inhibitor needs a window that is always mapped). */
    property bool awake: false

    signal requestClose()
    signal openSurface(string name)
    signal toggleAwake()

    property bool _closing: false
    visible: root.open || root._closing

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "astralis-dashboard"
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }

    onOpenChanged: {
        Sysmon.dashOpen = root.open;
        if (root.open) {
            root._closing = false;
            closeTimer.stop();
            root.refreshHypr();
            root.captureRev++;
            profileProbe.running = true;
            profileFile.reload();
            Qt.callLater(() => focusScope.forceActiveFocus());
        } else {
            root.commitBrightnessNow();
            root._closing = true;
            closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer
        interval: Motion.expressiveEffectsDur + 40
        onTriggered: root._closing = false
    }

    /** Window class → icon path via its desktop entry (zen, ghostty… aren't theme names); "" when none. */
    function appIcon(cls) {
        if (!cls)
            return "";
        var e = DesktopEntries.heuristicLookup(cls);
        var p = String((e && e.icon ? Quickshell.iconPath(e.icon, true) : "") || "");
        return p.length ? p : String(Quickshell.iconPath(String(cls).toLowerCase(), true) || "");
    }

    function go(name) {
        root.openSurface(name);
    }

    // ── shared data ─────────────────────────────────────────────────────────
    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }
    readonly property var now: sysClock.date
    function fmtTime(d) {
        return Qt.formatTime(d, Flags.time12h ? "h:mm AP" : "HH:mm");
    }
    readonly property string greeting: {
        var h = root.now.getHours();
        return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker {
        objects: [root.sink, root.source].filter(Boolean)
    }

    /**
     * ACPI platform profile. Read from the platform-profile class device;
     * writable only once system/udev/90-platform-profile.rules hands it to
     * wheel — until then the segments are a read-only display (Fn+Q cycles it).
     */
    property string profilePath: ""
    property bool profileWritable: false
    Process {
        id: profileProbe
        command: ["sh", "-c", "for f in /sys/class/platform-profile/*/profile; do [ -e \"$f\" ] || continue; echo \"$f\"; [ -w \"$f\" ] && echo w; break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = this.text.trim().split("\n");
                root.profilePath = l[0] || "";
                root.profileWritable = l[1] === "w";
            }
        }
    }
    FileView {
        id: profileFile
        path: root.profilePath.length ? root.profilePath : "/sys/firmware/acpi/platform_profile"
        printErrors: false
    }
    readonly property string profileRead: profileFile.loaded ? profileFile.text().trim() : ""
    /** Optimistic pick: the segment flips on click, the sysfs read-back confirms it. */
    property string profileWant: ""
    readonly property string profile: root.profileWant.length ? root.profileWant : root.profileRead
    onProfileReadChanged: if (root.profileRead === root.profileWant) root.profileWant = ""
    Process {
        id: profileSet
        onExited: (code) => {
            if (code !== 0)
                root.profileWant = "";
            profileFile.reload();
            profileSettle.restart();
        }
    }
    // never let an unconfirmed pick stick
    Timer {
        id: profileSettle
        interval: 1500
        onTriggered: root.profileWant = ""
    }
    // Fn+Q (or anything else) can change it underneath an open overview
    Timer {
        interval: 2000
        repeat: true
        running: root.open && root.profilePath.length > 0
        onTriggered: profileFile.reload()
    }
    function setProfile(k) {
        if (!root.profileWritable || k === root.profile)
            return;
        root.profileWant = k;
        profileSet.running = false;
        profileSet.command = ["sh", "-c", "printf %s \"$1\" > \"$2\"", "sh", k, root.profilePath];
        profileSet.running = true;
    }

    /**
     * Optimistic brightness while the fader moves (the sysfs poller lags), with
     * debounced writes so a drag doesn't spawn a brightnessctl per pointer
     * move — the Mixer's scheme. -1 = follow Backlight.brightness.
     */
    property real brightnessLocal: -1
    readonly property real brightnessShown: brightnessLocal >= 0 ? brightnessLocal : Backlight.brightness
    function setBrightness(v) {
        if (!Backlight.hasCtl)
            return;
        brightnessLocal = Math.max(0.01, Math.min(1, v));
        brightnessCommit.restart();
    }
    function commitBrightnessNow() {
        if (brightnessCommit.running) {
            brightnessCommit.stop();
            if (brightnessLocal >= 0)
                Backlight.set(brightnessLocal);
        }
        brightnessReconcile.restart();
    }
    Timer {
        id: brightnessCommit
        interval: 120
        onTriggered: if (root.brightnessLocal >= 0) Backlight.set(root.brightnessLocal)
    }
    Timer {
        id: brightnessReconcile
        interval: 1200
        onTriggered: root.brightnessLocal = -1
    }

    /** Window/monitor geometry comes from Hyprland's IPC objects, refreshed on open and on window events. */
    function refreshHypr() {
        Hyprland.refreshMonitors();
        Hyprland.refreshToplevels();
    }
    Timer {
        id: clientsDebounce
        interval: 120
        onTriggered: root.refreshHypr()
    }
    /** Bumped on open so the window thumbnails re-capture. */
    property int captureRev: 0

    /** Wi-Fi / Bluetooth state lines for the quick tiles. */
    readonly property string wifiSub: {
        if (!Networking.wifiEnabled)
            return "Off";
        var devs = Networking.devices ? Networking.devices.values : [];
        for (var i = 0; i < devs.length; i++) {
            var d = devs[i];
            if (!d || d.type !== DeviceType.Wifi || !d.networks)
                continue;
            var nets = d.networks.values;
            for (var j = 0; j < nets.length; j++)
                if (nets[j] && nets[j].connected === true)
                    return nets[j].name || "Connected";
        }
        return "Not connected";
    }
    readonly property string btSub: {
        var a = Bluetooth.defaultAdapter;
        if (!a || !a.enabled)
            return "Off";
        var devs = Bluetooth.devices ? Bluetooth.devices.values : [];
        var names = [];
        for (var i = 0; i < devs.length; i++)
            if (devs[i] && devs[i].connected === true)
                names.push(devs[i].name || devs[i].deviceName || "Device");
        return names.length === 0 ? "On" : names.length === 1 ? names[0] : names.length + " devices";
    }

    Connections {
        target: Hyprland
        enabled: root.visible
        function onRawEvent(event) {
            var n = event.name;
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2"
                    || n === "workspace" || n === "workspacev2" || n === "changefloatingmode")
                clientsDebounce.restart();
        }
    }

    // ── shell ───────────────────────────────────────────────────────────────
    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: root.open
        Keys.onEscapePressed: root.requestClose()

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colors.scrim, 0.30)
            opacity: root.open ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: root.open ? Motion.standard : Motion.expressiveEffectsDur
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveEffects
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.requestClose()
            }
        }

        Item {
            id: board
            readonly property real natW: 1240 * root.s
            readonly property real natH: 760 * root.s
            width: natW
            height: natH
            anchors.centerIn: parent
            // Shrink the whole board on a small screen rather than reflowing.
            scale: Math.min(1, (parent.width - 48 * root.s) / natW, (parent.height - 48 * root.s) / natH)

            // Swallow clicks in the gutters so they don't dismiss.
            MouseArea { anchors.fill: parent }

            // header
            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                height: 44 * root.s
                opacity: root.open ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.open ? Motion.standard : Motion.expressiveEffectsDur
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveEffects
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 6 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12 * root.s
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Flags.showGlyphs
                        text: "覧"
                        color: Colors.on_surface
                        font.family: Appearance.font.jp
                        font.weight: Font.Medium
                        font.pixelSize: 26 * root.s
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.greeting
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 20 * root.s
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 6 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: Sysmon.uptime
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2 * root.s
                }
            }

            RowLayout {
                anchors.top: header.bottom
                anchors.topMargin: 12 * root.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 16 * root.s

                // ── column 1: when ──────────────────────────────────────────
                // Explicit widths on every column: a nested layout whose children
                // fillWidth would otherwise fill too and stretch by implicit size.
                ColumnLayout {
                    Layout.preferredWidth: 370 * root.s
                    Layout.maximumWidth: 370 * root.s
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    spacing: 16 * root.s

                    Tile {
                        id: clockTile
                        order: 0
                        surface: "calendar"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 170 * root.s
                        accessibleName: "Clock"

                        Text {
                            id: bigClock
                            anchors.left: parent.left
                            anchors.leftMargin: 26 * root.s
                            anchors.top: parent.top
                            anchors.topMargin: 6 * root.s
                            // "12:59 PM" in Kalam is wider than the tile at full size.
                            width: parent.width - 52 * root.s
                            height: 120 * root.s
                            fontSizeMode: Text.Fit
                            minimumPixelSize: 40 * root.s
                            verticalAlignment: Text.AlignVCenter
                            text: root.fmtTime(root.now)
                            color: Colors.on_surface
                            font.family: Appearance.font.display
                            font.weight: Font.Light
                            font.pixelSize: 96 * root.s
                            font.features: ({ "tnum": 1 })
                            opacity: clockTile.seg(0, 2)
                            transform: Translate { y: (1 - clockTile.seg(0, 2)) * 14 * root.s }
                        }
                        Row {
                            anchors.left: bigClock.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 18 * root.s
                            spacing: 9 * root.s
                            opacity: clockTile.seg(1, 2)
                            transform: Translate { y: (1 - clockTile.seg(1, 2)) * 10 * root.s }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: Flags.showGlyphs
                                text: "時"
                                color: Colors.primary
                                font.family: Appearance.font.jp
                                font.weight: Font.Medium
                                font.pixelSize: 16 * root.s
                            }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.locale().toString(root.now, "dddd, d MMMM")
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 15 * root.s
                            font.weight: Font.Medium
                        }
                        }
                    }

                    /**
                     * 天 weather, condensed: now on one line, today's range at the
                     * right, and the next 12 hours as one temperature curve with
                     * a reading every 3 h — a shape, not a copy of the hourly grid.
                     */
                    Tile {
                        id: wxTile
                        order: 2
                        surface: "calendar"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 172 * root.s
                        accessibleName: "Weather, " + (Weather.ready ? Weather.tempNow + " degrees, " + Weather.labelFor(Weather.codeNow) : "loading")

                        readonly property var next12: Weather.hourly.slice(0, 13)
                        readonly property var range: {
                            var h = Weather.hourly, lo = 999, hi = -999;
                            for (var i = 0; i < h.length; i++) {
                                lo = Math.min(lo, h[i].temp);
                                hi = Math.max(hi, h[i].temp);
                            }
                            return h.length ? { lo: lo, hi: hi } : null;
                        }

                        TileLabel { kanji: "天"; text: Weather.city.length ? "Weather · " + Weather.city : "Weather" }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 20 * root.s
                            y: 14 * root.s
                            height: 24 * root.s
                            verticalAlignment: Text.AlignVCenter
                            visible: wxTile.range !== null
                            text: wxTile.range ? "↑ " + wxTile.range.hi + "°   ↓ " + wxTile.range.lo + "°" : ""
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 11 * root.s
                            font.weight: Font.Bold
                            font.features: ({ "tnum": 1 })
                        }

                        Row {
                            x: 20 * root.s
                            y: 44 * root.s
                            spacing: 10 * root.s
                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30 * root.s
                                height: width
                                name: Weather.glyphFor(Weather.codeNow, Weather.isDay)
                                color: Colors.primary
                                stroke: 1.6
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Weather.ready ? Weather.tempNow + "°" : "—"
                                color: Colors.on_surface
                                font.family: Appearance.font.family
                                font.pixelSize: 30 * root.s
                                font.weight: Font.Medium
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Weather.ready ? Weather.labelFor(Weather.codeNow) + "  ·  " + Weather.humidity + "%" : ""
                                color: Colors.on_surface_variant
                                font.family: Appearance.font.family
                                font.pixelSize: 12 * root.s
                                font.weight: Font.Medium
                            }
                        }

                        Item {
                            id: wxCurveBox
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 20 * root.s
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12 * root.s
                            height: 74 * root.s
                            visible: wxTile.next12.length >= 2
                            // band the curve occupies between the temp labels and the hour labels
                            readonly property real bandTop: 18 * root.s
                            readonly property real bandBot: height - 18 * root.s
                            function px(i) { return 6 * root.s + i * (width - 12 * root.s) / Math.max(1, wxTile.next12.length - 1); }
                            function py(t) {
                                var r = wxTile.range;
                                if (!r || r.hi === r.lo) return (bandTop + bandBot) / 2;
                                return bandBot - (t - r.lo) / (r.hi - r.lo) * (bandBot - bandTop);
                            }

                            // the curve draws in left→right with the tile's reveal
                            Item {
                                width: parent.width * wxTile.reveal
                                height: parent.height
                                clip: true
                            Canvas {
                                id: wxCurve
                                width: wxCurveBox.width
                                height: wxCurveBox.height
                                readonly property var pts: wxTile.next12
                                readonly property color tint: Colors.primary
                                onPtsChanged: requestPaint()
                                onTintChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    var p = pts;
                                    if (p.length < 2) return;
                                    function X(i) { return wxCurveBox.px(i); }
                                    function Y(i) { return wxCurveBox.py(p[i].temp); }
                                    // smooth path through the samples (midpoint quadratic)
                                    function trace() {
                                        ctx.moveTo(X(0), Y(0));
                                        for (var i = 1; i < p.length - 1; i++)
                                            ctx.quadraticCurveTo(X(i), Y(i), (X(i) + X(i + 1)) / 2, (Y(i) + Y(i + 1)) / 2);
                                        ctx.lineTo(X(p.length - 1), Y(p.length - 1));
                                    }
                                    ctx.beginPath();
                                    trace();
                                    ctx.lineTo(X(p.length - 1), wxCurveBox.bandBot);
                                    ctx.lineTo(X(0), wxCurveBox.bandBot);
                                    ctx.closePath();
                                    var g = ctx.createLinearGradient(0, wxCurveBox.bandTop, 0, wxCurveBox.bandBot);
                                    g.addColorStop(0, Qt.alpha(tint, 0.22));
                                    g.addColorStop(1, Qt.alpha(tint, 0));
                                    ctx.fillStyle = g;
                                    ctx.fill();
                                    ctx.beginPath();
                                    trace();
                                    ctx.lineWidth = 2 * root.s;
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";
                                    ctx.strokeStyle = tint;
                                    ctx.stroke();
                                }
                            }
                            }
                            Repeater {
                                model: wxTile.next12.length >= 2 ? [0, 3, 6, 9, 12].filter(i => i < wxTile.next12.length) : []
                                Item {
                                    id: wxMark
                                    required property int modelData
                                    readonly property var h: wxTile.next12[modelData]
                                    readonly property real cx: wxCurveBox.px(modelData)
                                    readonly property real cy: wxCurveBox.py(h.temp)
                                    opacity: Math.max(0, Math.min(1, (wxTile.reveal * wxCurveBox.width - cx + 12 * root.s) / (24 * root.s)))
                                    Rectangle {
                                        x: wxMark.cx - width / 2
                                        y: wxMark.cy - height / 2
                                        width: (wxMark.modelData === 0 ? 8 : 6) * root.s
                                        height: width
                                        radius: width / 2
                                        color: wxMark.modelData === 0 ? Colors.primary : Colors.surface_container
                                        border.width: 1.5 * root.s
                                        border.color: Colors.primary
                                    }
                                    Text {
                                        x: Math.max(0, Math.min(wxCurveBox.width - width, wxMark.cx - width / 2))
                                        y: wxMark.cy - height - 4 * root.s
                                        text: wxMark.h.temp + "°"
                                        color: Colors.on_surface
                                        font.family: Appearance.font.family
                                        font.pixelSize: 11 * root.s
                                        font.weight: Font.DemiBold
                                        font.features: ({ "tnum": 1 })
                                    }
                                    Text {
                                        x: Math.max(0, Math.min(wxCurveBox.width - width, wxMark.cx - width / 2))
                                        y: wxCurveBox.height - height
                                        text: wxMark.modelData === 0 ? "now" : wxMark.h.hour
                                        color: Colors.on_surface_variant
                                        font.family: Appearance.font.family
                                        font.pixelSize: 10 * root.s
                                        font.weight: Font.Medium
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }
                        }
                    }

                    /**
                     * 暦 calendar: today large, the month as a ribbon of day
                     * capsules, then the agenda — the next few events in order.
                     */
                    Tile {
                        id: calTile
                        order: 5
                        surface: "calendar"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        accessibleName: "Calendar, " + (calTile.agenda.length ? calTile.agenda.length + " upcoming events" : "nothing coming up")

                        function key(d) {
                            var m = d.getMonth() + 1, dd = d.getDate();
                            return d.getFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (dd < 10 ? "0" : "") + dd;
                        }
                        readonly property var today: new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate())
                        /** Monday of this week. */
                        readonly property var monday: new Date(today.getFullYear(), today.getMonth(), today.getDate() - (today.getDay() + 6) % 7)
                        /** Upcoming events from today, within 60 days: [{date, when, time, text}]. */
                        readonly property var agenda: {
                            void Events.events; // dependency
                            var out = [];
                            for (var i = 0; i < 60 && out.length < 6; i++) {
                                var d = new Date(today.getFullYear(), today.getMonth(), today.getDate() + i);
                                var list = Events.eventsFor(calTile.key(d));
                                for (var j = 0; j < list.length && out.length < 6; j++)
                                    out.push({ date: d, rel: i, time: list[j].time || "", text: list[j].text || "" });
                            }
                            return out;
                        }

                        // today, large: the date numeral beside its day and month
                        Item {
                            id: calHero
                            x: 20 * root.s
                            y: 12 * root.s
                            width: parent.width - 40 * root.s
                            height: 64 * root.s
                            Text {
                                id: calDayNum
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: Qt.locale().toString(root.now, "MMMM")
                                color: Colors.primary
                                font.family: Appearance.font.family
                                font.pixelSize: 30 * root.s
                                font.weight: Font.Bold
                            }
                            Column {
                                anchors.left: calDayNum.right
                                anchors.leftMargin: 12 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2 * root.s
                                readonly property int daysLeft: ribbon.days - calTile.today.getDate()
                                readonly property int monthEvents: {
                                    void Events.events;
                                    var n = 0;
                                    for (var d = 1; d <= ribbon.days; d++)
                                        n += Events.eventsFor(calTile.key(new Date(calTile.today.getFullYear(), calTile.today.getMonth(), d))).length;
                                    return n;
                                }
                                // pointing at a day in the ribbon swaps these for that day
                                readonly property var hoverDate: ribbon.hoverDay > 0 ? new Date(calTile.today.getFullYear(), calTile.today.getMonth(), ribbon.hoverDay) : null
                                readonly property var hoverEvents: hoverDate ? (Events.events, Events.eventsFor(calTile.key(hoverDate))) : []
                                Text {
                                    text: parent.hoverDate ? Qt.locale().toString(parent.hoverDate, "dddd d")
                                        : parent.daysLeft === 0 ? "Last day" : parent.daysLeft + (parent.daysLeft === 1 ? " day left" : " days left")
                                    color: Colors.on_surface
                                    font.family: Appearance.font.family
                                    font.pixelSize: 12 * root.s
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: Math.min(implicitWidth, calHero.width - calDayNum.width - 90 * root.s)
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    text: parent.hoverDate
                                        ? (parent.hoverEvents.length === 0 ? "Nothing on"
                                            : parent.hoverEvents[0].text + (parent.hoverEvents.length > 1 ? "  +" + (parent.hoverEvents.length - 1) : ""))
                                        : parent.monthEvents === 0 ? "No events" : parent.monthEvents + (parent.monthEvents === 1 ? " event" : " events")
                                    color: parent.hoverEvents.length ? Colors.tertiary : Colors.on_surface_variant
                                    font.family: Appearance.font.family
                                    font.pixelSize: 10.5 * root.s
                                    font.weight: Font.Medium
                                }
                            }
                            Column {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3 * root.s
                                Text {
                                    anchors.right: parent.right
                                    visible: Flags.showGlyphs
                                    text: "暦"
                                    color: Colors.on_surface_variant
                                    font.family: Appearance.font.jp
                                    font.weight: Font.Medium
                                    font.pixelSize: 16 * root.s
                                }
                                Text {
                                    anchors.right: parent.right
                                    // ISO 8601 week: the week holding this date's Thursday
                                    text: {
                                        var d = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate());
                                        d.setDate(d.getDate() + 3 - (d.getDay() + 6) % 7);
                                        var jan4 = new Date(d.getFullYear(), 0, 4);
                                        return "Week " + (1 + Math.round(((d - jan4) / 86400000 - 3 + (jan4.getDay() + 6) % 7) / 7));
                                    }
                                    color: Colors.on_surface_variant
                                    font.family: Appearance.font.family
                                    font.pixelSize: 10.5 * root.s
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        /**
                         * The month as a ribbon of day capsules, grouped into weeks:
                         * days gone fill in primary so the month reads as progress,
                         * today stands tall and fills with the hours already spent,
                         * event days glow tertiary. Hovering a day names it (and its
                         * events) in the header; on open the capsules grow in as a
                         * wave. Takes whatever height the agenda doesn't need.
                         */
                        Item {
                            id: ribbon
                            x: 20 * root.s
                            anchors.top: calHero.bottom
                            anchors.topMargin: 10 * root.s
                            width: parent.width - 40 * root.s
                            readonly property int lead: (new Date(calTile.today.getFullYear(), calTile.today.getMonth(), 1).getDay() + 6) % 7
                            readonly property int days: new Date(calTile.today.getFullYear(), calTile.today.getMonth() + 1, 0).getDate()
                            readonly property real weekGap: 7 * root.s
                            readonly property int breaks: Math.floor((lead + days - 1) / 7)
                            readonly property real step: (width - breaks * weekGap) / days
                            readonly property real labelH: 16 * root.s
                            readonly property real topPad: 4 * root.s
                            readonly property real full: height - labelH - topPad
                            readonly property real dayFrac: (root.now.getHours() * 60 + root.now.getMinutes()) / 1440
                            readonly property int agendaRows: Math.max(1, Math.min(3, calTile.agenda.length))
                            height: Math.max(58 * root.s, Math.min(120 * root.s,
                                calTile.height - y - 34 * root.s - agendaRows * 44 * root.s))

                            function xOf(i) { return i * step + Math.floor((lead + i) / 7) * weekGap; }

                            property int hoverDay: 0
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton // clicks fall through to the tile
                                onPositionChanged: mouse => {
                                    var hit = 0;
                                    for (var i = 0; i < ribbon.days; i++)
                                        if (mouse.x >= ribbon.xOf(i) - ribbon.weekGap / 2 && mouse.x < ribbon.xOf(i) + ribbon.step + ribbon.weekGap / 2) {
                                            hit = i + 1;
                                            break;
                                        }
                                    ribbon.hoverDay = hit;
                                }
                                onExited: ribbon.hoverDay = 0
                            }

                            // 0→1 sweep driving the open wave
                            property real wave: 1
                            Connections {
                                target: root
                                function onOpenChanged() {
                                    if (root.open) {
                                        ribbon.wave = 0;
                                        waveAnim.restart();
                                    } else {
                                        ribbon.hoverDay = 0;
                                    }
                                }
                            }
                            SequentialAnimation {
                                id: waveAnim
                                PauseAnimation { duration: Motion.standard }
                                NumberAnimation {
                                    target: ribbon
                                    property: "wave"
                                    to: 1
                                    duration: Math.round(Motion.largeDur * 1.4)
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.emphasized
                                }
                            }

                            Repeater {
                                model: 31
                                Item {
                                    id: rd
                                    required property int index
                                    readonly property int day: index + 1
                                    readonly property bool isToday: day === calTile.today.getDate()
                                    readonly property bool past: day < calTile.today.getDate()
                                    readonly property bool monday: (ribbon.lead + index) % 7 === 0
                                    readonly property bool weekend: (ribbon.lead + index) % 7 >= 5
                                    readonly property bool hovered: ribbon.hoverDay === day
                                    readonly property bool hasEv: (Events.events, Events.hasEvents(calTile.key(new Date(calTile.today.getFullYear(), calTile.today.getMonth(), day))))
                                    // each capsule's share of the wave, trailing the one before it
                                    readonly property real grow: Math.max(0, Math.min(1, (ribbon.wave * (ribbon.days + 8) - index) / 8))
                                    visible: index < ribbon.days
                                    x: ribbon.xOf(index)
                                    width: ribbon.step
                                    height: ribbon.height

                                    Rectangle {
                                        id: cap
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: ribbon.topPad + ribbon.full - height
                                        width: Math.max(3 * root.s, ribbon.step - 3 * root.s)
                                        height: Math.max(width, rd.grow * (rd.isToday ? ribbon.full
                                            : ribbon.full * (rd.hovered ? 0.86 : rd.weekend ? 0.55 : 0.72)))
                                        radius: width / 2
                                        clip: true
                                        color: rd.isToday ? Qt.alpha(Colors.primary, 0.22)
                                            : rd.hasEv ? Qt.alpha(Colors.tertiary, rd.past ? 0.45 : 0.9)
                                            : rd.past ? Qt.alpha(Colors.primary, rd.hovered ? 0.6 : 0.38)
                                            : Qt.alpha(Colors.on_surface, rd.hovered ? 0.28 : rd.weekend ? 0.07 : 0.12)
                                        Behavior on height {
                                            enabled: ribbon.wave >= 1
                                            NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
                                        }
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                                        // today: the part of the day already spent, rising from the base
                                        Rectangle {
                                            visible: rd.isToday
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: Math.max(parent.width, parent.height * ribbon.dayFrac)
                                            radius: parent.radius
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: Qt.lighter(Colors.primary, 1.25) }
                                                GradientStop { position: 1.0; color: Colors.primary }
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        visible: rd.hovered || (ribbon.hoverDay === 0 && (rd.isToday
                                            || ((rd.monday || rd.day === 1) && Math.abs(rd.day - calTile.today.getDate()) > 2
                                                && !(rd.day === 1 && ribbon.lead >= 5))))
                                        text: rd.day
                                        color: rd.isToday || rd.hovered ? Colors.primary : Colors.on_surface_variant
                                        font.family: Appearance.font.family
                                        font.pixelSize: 9.5 * root.s
                                        font.weight: rd.isToday || rd.hovered ? Font.Bold : Font.Medium
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: calRule
                            x: 20 * root.s
                            y: ribbon.y + ribbon.height + 10 * root.s
                            width: parent.width - 40 * root.s
                            height: 1
                            color: Qt.alpha(Colors.outline_variant, 0.5)
                        }

                        // agenda
                        Column {
                            id: agendaList
                            x: 20 * root.s
                            anchors.top: calRule.bottom
                            anchors.topMargin: 10 * root.s
                            width: parent.width - 40 * root.s
                            spacing: 4 * root.s
                            readonly property real rowH: 40 * root.s
                            readonly property int rows: Math.max(1, Math.floor((calTile.height - calRule.y - 24 * root.s) / (rowH + spacing)))

                            Text {
                                visible: calTile.agenda.length === 0
                                text: "Nothing coming up"
                                color: Qt.alpha(Colors.on_surface_variant, 0.8)
                                font.family: Appearance.font.family
                                font.pixelSize: 12 * root.s
                                font.weight: Font.Medium
                            }
                            Repeater {
                                model: calTile.agenda.slice(0, agendaList.rows)
                                Item {
                                    id: ev
                                    required property var modelData
                                    required property int index
                                    opacity: calTile.seg(ev.index + 2, 5)
                                    transform: Translate { x: (1 - calTile.seg(ev.index + 2, 5)) * -14 * root.s }
                                    width: agendaList.width
                                    height: agendaList.rowH
                                    Column {
                                        id: evDate
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 40 * root.s
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Qt.locale().toString(ev.modelData.date, "ddd").toUpperCase()
                                            color: ev.modelData.rel === 0 ? Colors.primary : Colors.on_surface_variant
                                            font.family: Appearance.font.family
                                            font.pixelSize: 9.5 * root.s
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1 * root.s
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: ev.modelData.date.getDate()
                                            color: ev.modelData.rel === 0 ? Colors.primary : Colors.on_surface
                                            font.family: Appearance.font.family
                                            font.pixelSize: 16 * root.s
                                            font.weight: Font.Bold
                                            font.features: ({ "tnum": 1 })
                                        }
                                    }
                                    Rectangle {
                                        id: evBar
                                        anchors.left: evDate.right
                                        anchors.leftMargin: 8 * root.s
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 3 * root.s
                                        height: 28 * root.s
                                        radius: width / 2
                                        color: Events.isBirthday(ev.modelData.text) ? Colors.secondary : Colors.tertiary
                                    }
                                    Column {
                                        anchors.left: evBar.right
                                        anchors.leftMargin: 10 * root.s
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1 * root.s
                                        Text {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            textFormat: Text.PlainText
                                            text: ev.modelData.text
                                            color: Colors.on_surface
                                            font.family: Appearance.font.family
                                            font.pixelSize: 12.5 * root.s
                                            font.weight: Font.Medium
                                        }
                                        Text {
                                            text: (ev.modelData.rel === 0 ? "Today" : ev.modelData.rel === 1 ? "Tomorrow"
                                                    : "In " + ev.modelData.rel + " days")
                                                + (ev.modelData.time ? "  ·  " + ev.modelData.time : "")
                                            color: Colors.on_surface_variant
                                            font.family: Appearance.font.family
                                            font.pixelSize: 10.5 * root.s
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── column 2: now ───────────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: 480 * root.s
                    Layout.maximumWidth: 480 * root.s
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    spacing: 16 * root.s

                    Tile {
                        id: mediaTile
                        order: 1
                        surface: "media"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 206 * root.s
                        accessibleName: Players.has ? "Now playing: " + Players.title + " by " + Players.artist : "Nothing playing"

                        readonly property string art: {
                            var u = Players.artUrl;
                            if (!u || !root.visible)
                                return "";
                            if (u.indexOf("file:") === 0 || u.charAt(0) === "/") {
                                var p = u.indexOf("file://") === 0 ? u.substring(7) : (u.indexOf("file:") === 0 ? u.substring(5) : u);
                                return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F");
                            }
                            return u;
                        }

                        // Cover wash: the art blurred under the tile, tinting it.
                        ClippingRectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            visible: washSrc.status === Image.Ready
                            Image {
                                id: washSrc
                                anchors.fill: parent
                                source: mediaTile.art
                                sourceSize: Qt.size(96, 96)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: false
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: washSrc
                                blurEnabled: true
                                blur: 1
                                blurMax: 48
                                saturation: 0.2
                                opacity: 0.32
                            }
                        }

                        ClippingRectangle {
                            id: cover
                            x: 18 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -8 * root.s
                            width: 150 * root.s
                            height: width
                            radius: 18 * root.s
                            color: Colors.surface_container_highest
                            GlyphIcon {
                                anchors.centerIn: parent
                                visible: coverImg.status !== Image.Ready
                                width: 44 * root.s
                                height: width
                                name: "music"
                                color: Colors.on_surface_variant
                            }
                            Image {
                                id: coverImg
                                anchors.fill: parent
                                source: mediaTile.art
                                sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                        }

                        Column {
                            anchors.left: cover.right
                            anchors.leftMargin: 18 * root.s
                            anchors.right: parent.right
                            anchors.rightMargin: 20 * root.s
                            y: 26 * root.s
                            spacing: 3 * root.s
                            Row {
                                width: parent.width
                                spacing: 8 * root.s
                                Text {
                                    id: mediaKanji
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: Flags.showGlyphs
                                    text: "奏"
                                    color: Colors.primary
                                    font.family: Appearance.font.jp
                                    font.weight: Font.Medium
                                    font.pixelSize: 15 * root.s
                                }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - (mediaKanji.visible ? mediaKanji.width + parent.spacing : 0)
                                text: Players.has ? Players.serviceLabel : "Now playing"
                                elide: Text.ElideRight
                                color: Colors.primary
                                font.family: Appearance.font.family
                                font.pixelSize: 10 * root.s
                                font.weight: Font.Bold
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: 1.4 * root.s
                            }
                            }
                            Text {
                                width: parent.width
                                text: Players.has ? Players.title : "Nothing playing"
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                                color: Colors.on_surface
                                font.family: Appearance.font.family
                                font.pixelSize: 18 * root.s
                                font.weight: Font.Bold
                            }
                            Text {
                                width: parent.width
                                text: Players.artist
                                elide: Text.ElideRight
                                color: Colors.on_surface_variant
                                font.family: Appearance.font.family
                                font.pixelSize: 13 * root.s
                                font.weight: Font.Medium
                            }
                        }

                        Row {
                            anchors.left: cover.right
                            anchors.leftMargin: 10 * root.s
                            y: 116 * root.s
                            spacing: 16 * root.s
                            visible: Players.has
                            opacity: mediaTile.seg(1, 3)
                            transform: Translate { x: (1 - mediaTile.seg(1, 3)) * 16 * root.s }
                            // 前 · seal 奏/休 · 次 — the pill's kanji transport
                            DashSkip {
                                kanjiText: "前"
                                can: Players.canPrevious
                                accessibleName: "Previous track"
                                onActivated: Players.previous()
                            }
                            Rectangle {
                                id: mediaSeal
                                anchors.verticalCenter: parent.verticalCenter
                                width: 42 * root.s
                                height: width
                                radius: 10 * root.s
                                rotation: -1.5
                                scale: sealArea.pressed ? 0.94 : 1
                                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                                property real sat: Players.playing ? 1 : 0
                                Behavior on sat { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                                opacity: 0.75 + 0.25 * sat
                                border.width: 1
                                border.color: Qt.alpha(Colors.primary, sealArea.containsMouse ? 0.8 : 0.4)
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.alpha(Colors.primary, 0.45 + 0.27 * mediaSeal.sat) }
                                    GradientStop { position: 1.0; color: Qt.alpha(Qt.darker(Colors.primary, 1.18), 0.45 + 0.27 * mediaSeal.sat) }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: Players.playing ? "奏" : "休"
                                    color: Colors.on_surface
                                    font.family: Appearance.font.jp
                                    font.pixelSize: 21 * root.s
                                    font.weight: Font.DemiBold
                                }
                                MouseArea {
                                    id: sealArea
                                    anchors.fill: parent
                                    anchors.margins: -4 * root.s
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Players.togglePlaying()
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: Players.playing ? "Pause" : "Play"
                            }
                            DashSkip {
                                kanjiText: "次"
                                can: Players.canNext
                                accessibleName: "Next track"
                                onActivated: Players.next()
                            }
                        }

                        Timer {
                            interval: 1000
                            running: root.visible && Players.playing
                            repeat: true
                            onTriggered: if (Players.active) Players.active.positionChanged()
                        }
                        function mmss(sec) {
                            var t = Math.max(0, Math.floor(sec));
                            var m = Math.floor(t / 60), s2 = t % 60;
                            return m + ":" + (s2 < 10 ? "0" : "") + s2;
                        }
                        Text {
                            id: mElapsed
                            anchors.left: parent.left
                            anchors.leftMargin: 20 * root.s
                            anchors.verticalCenter: mInk.verticalCenter
                            visible: Players.has && !Players.live
                            text: mediaTile.mmss(Players.position)
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 10.5 * root.s
                            font.features: ({ "tnum": 1 })
                        }
                        InkStroke {
                            id: mInk
                            anchors.left: mElapsed.right
                            anchors.leftMargin: 10 * root.s
                            anchors.right: mLength.left
                            anchors.rightMargin: 10 * root.s
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10 * root.s
                            height: 18 * root.s
                            s: root.s
                            frac: (Players.length > 0 ? Math.max(0, Math.min(1, Players.position / Players.length)) : 0)
                            paper: Colors.surface_container
                            wet: Players.playing ? 1 : 0
                            glide: !Flags.reduceMotion
                            visible: Players.has && !Players.live
                        }
                        Text {
                            id: mLength
                            anchors.right: parent.right
                            anchors.rightMargin: 20 * root.s
                            anchors.verticalCenter: mInk.verticalCenter
                            visible: Players.has && !Players.live
                            text: mediaTile.mmss(Players.length)
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 10.5 * root.s
                            font.features: ({ "tnum": 1 })
                        }
                    }

                    Tile {
                        id: qsBox
                        order: 4
                        surface: "link"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 256 * root.s
                        accessibleName: "Quick settings"

                        readonly property var btAdapter: Bluetooth.defaultAdapter

                        TileLabel { kanji: "繋"; text: "Quick settings" }

                        Column {
                            id: qsGrid
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 16 * root.s
                            y: 46 * root.s
                            spacing: 8 * root.s
                            readonly property real gap: 8 * root.s
                            Row {
                                spacing: qsGrid.gap
                                QsTile {
                                    width: (qsGrid.width - 2 * qsGrid.gap) / 3
                                    icon: Networking.wifiEnabled ? "wifi" : "wifi-1"
                                    label: "Wi-Fi"
                                    enter: qsBox.seg(0, 7)
                                    sub: root.wifiSub
                                    checked: Networking.wifiEnabled
                                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                                }
                                QsTile {
                                    width: (qsGrid.width - 2 * qsGrid.gap) / 3
                                    icon: "bluetooth"
                                    label: "Bluetooth"
                                    enter: qsBox.seg(1, 7)
                                    sub: root.btSub
                                    checked: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
                                    onClicked: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                                }
                                QsTile {
                                    width: (qsGrid.width - 2 * qsGrid.gap) / 3
                                    icon: "dnd"
                                    label: "Silence"
                                    enter: qsBox.seg(2, 7)
                                    sub: Services.Notifications.dnd ? "On" : "Off"
                                    checked: Services.Notifications.dnd
                                    onClicked: Services.Notifications.dnd = !Services.Notifications.dnd
                                }
                            }
                            Row {
                                spacing: qsGrid.gap
                                QsTile {
                                    width: (qsGrid.width - qsGrid.gap) / 2
                                    icon: "awake"
                                    label: "Stay awake"
                                    enter: qsBox.seg(3, 7)
                                    sub: root.awake ? "Idle blocked" : "Off"
                                    checked: root.awake
                                    onClicked: root.toggleAwake()
                                }
                                QsTile {
                                    readonly property bool muted: !root.source || !root.source.audio || root.source.audio.muted
                                    width: (qsGrid.width - qsGrid.gap) / 2
                                    icon: muted ? "mic-off" : "mic"
                                    label: "Microphone"
                                    enter: qsBox.seg(4, 7)
                                    sub: muted ? "Muted" : "Live"
                                    // On = the mic is live.
                                    checked: !muted
                                    onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
                                }
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 20 * root.s
                            anchors.right: parent.right
                            anchors.rightMargin: 20 * root.s
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8 * root.s
                            spacing: 0

                            SliderRow {
                                muted: root.sink !== null && root.sink.audio !== null && root.sink.audio.muted
                                icon: muted ? "speaker-off" : "speaker"
                                label: "Volume"
                                enter: qsBox.seg(5, 7)
                                value: root.sink && root.sink.audio ? root.sink.audio.volume * 100 : 0
                                onIconClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                                onMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v / 100; }
                            }
                            SliderRow {
                                visible: Backlight.present
                                icon: "sun"
                                label: "Brightness"
                                enter: qsBox.seg(6, 7)
                                value: root.brightnessShown * 100
                                onMoved: (v) => root.setBrightness(v / 100)
                                onReleased: root.commitBrightnessNow()
                            }
                        }
                    }

                    Tile {
                        id: wsTile
                        order: 7
                        surface: ""
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        accessibleName: "Workspaces"

                        TileLabel { kanji: "窓"; text: "Workspaces" }

                        /**
                         * [{id, active, focusedMon, aspect, wins:[{x,y,w,h,tl,cls,focus}]}].
                         * Window rects are fractions of the monitor's usable area
                         * (reserved bar zone removed), so a mini-map is the desktop
                         * a window can actually occupy, edge to edge.
                         */
                        readonly property var spaces: {
                            var mons = Hyprland.monitors.values, tls = Hyprland.toplevels.values;
                            var byId = {}, out = {}, order = [];
                            for (var i = 0; i < mons.length; i++) {
                                var m = mons[i].lastIpcObject;
                                if (!m || m.id === undefined)
                                    continue;
                                var sc = m.scale || 1, tr = (m.transform || 0) % 2 === 1;
                                var r = m.reserved || [0, 0, 0, 0];
                                var W = (tr ? m.height : m.width) / sc, H = (tr ? m.width : m.height) / sc;
                                var mon = { x: m.x + r[0], y: m.y + r[1], w: Math.max(1, W - r[0] - r[2]), h: Math.max(1, H - r[1] - r[3]),
                                            active: m.activeWorkspace ? m.activeWorkspace.id : -1, focused: m.focused === true };
                                byId[m.id] = mon;
                                if (mon.active > 0) {
                                    out[mon.active] = { id: mon.active, mon: mon, wins: [] };
                                    order.push(mon.active);
                                }
                            }
                            var act = Hyprland.activeToplevel;
                            for (var j = 0; j < tls.length; j++) {
                                var c = tls[j].lastIpcObject;
                                if (!c || !c.at || !c.workspace || !(c.workspace.id > 0) || c.mapped === false || c.hidden === true)
                                    continue;
                                var mo = byId[c.monitor];
                                if (!mo)
                                    continue;
                                var wid = c.workspace.id;
                                if (!out[wid]) {
                                    out[wid] = { id: wid, mon: mo, wins: [] };
                                    order.push(wid);
                                }
                                out[wid].wins.push({
                                    x: (c.at[0] - mo.x) / mo.w, y: (c.at[1] - mo.y) / mo.h,
                                    w: c.size[0] / mo.w, h: c.size[1] / mo.h,
                                    tl: tls[j], cls: c["class"] || "", floating: c.floating === true,
                                    focus: act !== null && act === tls[j]
                                });
                            }
                            order.sort(function (a, b) { return a - b; });
                            return order.map(function (id) {
                                var sp = out[id];
                                sp.active = sp.mon.active === id;
                                sp.focusedMon = sp.active && sp.mon.focused;
                                sp.aspect = sp.mon.w / sp.mon.h;
                                sp.wins.sort(function (a, b) { return (a.floating === b.floating) ? 0 : (a.floating ? 1 : -1); });
                                return sp;
                            });
                        }

                        /** Focused workspace gets the big preview; the rest list beside it. */
                        readonly property var hero: {
                            var sp = wsTile.spaces;
                            for (var i = 0; i < sp.length; i++)
                                if (sp[i].focusedMon)
                                    return sp[i];
                            return sp.length ? sp[0] : null;
                        }
                        readonly property var others: wsTile.spaces.filter(function (sp) { return sp !== wsTile.hero; })

                        Item {
                            id: wsArea
                            anchors.fill: parent
                            anchors.margins: 16 * root.s
                            anchors.topMargin: 46 * root.s
                            readonly property real gap: 12 * root.s
                            readonly property bool solo: wsTile.others.length === 0
                            readonly property real heroW: wsTile.hero
                                ? Math.min(height * wsTile.hero.aspect, solo ? width : width * 0.52) : 0

                            WsMap {
                                id: heroMap
                                space: wsTile.hero
                                visible: wsTile.hero !== null
                                opacity: wsTile.seg(0, 4)
                                transform: Scale {
                                    origin.x: heroMap.width / 2
                                    origin.y: heroMap.height / 2
                                    xScale: 0.9 + 0.1 * wsTile.seg(0, 4)
                                    yScale: 0.9 + 0.1 * wsTile.seg(0, 4)
                                }
                                width: wsArea.heroW
                                height: wsTile.hero ? width / wsTile.hero.aspect : 0
                                x: wsArea.solo ? (wsArea.width - width) / 2 : 0
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 12 * root.s
                                pressed: heroArea.pressed

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8 * root.s
                                    width: heroChip.implicitWidth + 12 * root.s
                                    height: 22 * root.s
                                    radius: height / 2
                                    color: Qt.alpha(Colors.surface_container_high, 0.92)
                                    Row {
                                        id: heroChip
                                        anchors.centerIn: parent
                                        spacing: 6 * root.s
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.max(height, heroNum.implicitWidth + 8 * root.s)
                                            height: 16 * root.s
                                            radius: height / 2
                                            color: Colors.primary
                                            Text {
                                                id: heroNum
                                                anchors.centerIn: parent
                                                text: wsTile.hero ? wsTile.hero.id : ""
                                                color: Colors.on_primary
                                                font.family: Appearance.font.family
                                                font.pixelSize: 10.5 * root.s
                                                font.weight: Font.Bold
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            readonly property int k: wsTile.hero ? wsTile.hero.wins.length : 0
                                            text: k === 0 ? "Empty" : k + (k === 1 ? " window" : " windows")
                                            color: Colors.on_surface
                                            font.family: Appearance.font.family
                                            font.pixelSize: 10.5 * root.s
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                                MouseArea {
                                    id: heroArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.requestClose()
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: wsTile.hero ? "Workspace " + wsTile.hero.id + ", focused, " + wsTile.hero.wins.length + " windows" : ""
                            }

                            /**
                             * Other workspaces as cards: thumbnail, number, app icons.
                             * One column up to 3, two beyond; rows share the height,
                             * extra workspaces beyond what fits collapse into "+N".
                             */
                            Item {
                                id: wsList
                                visible: !wsArea.solo
                                anchors.left: heroMap.right
                                anchors.leftMargin: wsArea.gap
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                readonly property int count: wsTile.others.length
                                readonly property int cols: (count > 3 || count > maxRows) ? 2 : 1
                                readonly property real cgap: 8 * root.s
                                readonly property int maxRows: Math.max(1, Math.floor((height + cgap) / (44 * root.s + cgap)))
                                readonly property int rows: Math.min(maxRows, Math.ceil(count / cols))
                                readonly property int shown: Math.min(count, rows * cols)
                                readonly property real cardW: (width - (cols - 1) * cgap) / cols
                                readonly property real cardH: Math.min(64 * root.s, (height - (rows - 1) * cgap) / rows)
                                readonly property real blockH: rows * cardH + (rows - 1) * cgap

                                Grid {
                                    y: (wsList.height - wsList.blockH) / 2
                                    columns: wsList.cols
                                    spacing: wsList.cgap
                                    Repeater {
                                        model: wsTile.others.slice(0, wsList.shown)
                                        Rectangle {
                                            id: card
                                            required property var modelData
                                            required property int index
                                            opacity: wsTile.seg(card.index + 1, 4)
                                            transform: Translate { x: (1 - wsTile.seg(card.index + 1, 4)) * 18 * root.s }
                                            readonly property bool overflow: index === wsList.shown - 1 && wsList.count > wsList.shown
                                            readonly property var apps: {
                                                var seen = {}, o = [];
                                                card.modelData.wins.forEach(function (w) {
                                                    var c = String(w.cls);
                                                    if (c && !seen[c]) { seen[c] = true; o.push(c); }
                                                });
                                                return o;
                                            }
                                            width: wsList.cardW
                                            height: wsList.cardH
                                            radius: 12 * root.s
                                            color: Colors.surface_container_high
                                            scale: cardArea.pressed ? 0.97 : 1
                                            Behavior on scale {
                                                NumberAnimation {
                                                    duration: Motion.glide
                                                    easing.type: Motion.easeBezier
                                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                                }
                                            }

                                            WsMap {
                                                id: thumb
                                                space: card.modelData
                                                x: 6 * root.s
                                                anchors.verticalCenter: parent.verticalCenter
                                                // capped so the number and icons always keep half the card
                                                width: Math.min((card.height - 12 * root.s) * card.modelData.aspect, card.width * 0.5)
                                                height: width / card.modelData.aspect
                                                radius: 7 * root.s
                                            }
                                            Column {
                                                anchors.left: thumb.right
                                                anchors.leftMargin: 10 * root.s
                                                anchors.right: parent.right
                                                anchors.rightMargin: 8 * root.s
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 3 * root.s
                                                Row {
                                                    spacing: 5 * root.s
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: card.modelData.id !== undefined ? card.modelData.id : ""
                                                        color: card.modelData.active ? Colors.primary : Colors.on_surface
                                                        font.family: Appearance.font.family
                                                        font.pixelSize: 15 * root.s
                                                        font.weight: Font.Bold
                                                        font.features: ({ "tnum": 1 })
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: card.modelData.active
                                                        text: "shown"
                                                        color: Colors.primary
                                                        font.family: Appearance.font.family
                                                        font.pixelSize: 9.5 * root.s
                                                        font.weight: Font.Bold
                                                    }
                                                }
                                                Row {
                                                    spacing: 4 * root.s
                                                    Repeater {
                                                        model: card.apps.slice(0, 4)
                                                        Item {
                                                            id: appIcon
                                                            required property string modelData
                                                            readonly property string src: root.appIcon(appIcon.modelData)
                                                            width: 14 * root.s
                                                            height: width
                                                            IconImage {
                                                                visible: appIcon.src.length > 0
                                                                implicitSize: parent.width
                                                                source: appIcon.src
                                                                asynchronous: true
                                                            }
                                                            GlyphIcon {
                                                                visible: appIcon.src.length === 0
                                                                anchors.fill: parent
                                                                name: "app-window"
                                                                stroke: 1.7
                                                                color: Colors.on_surface_variant
                                                            }
                                                        }
                                                    }
                                                    Text {
                                                        visible: card.apps.length > 4 || card.apps.length === 0
                                                        text: card.apps.length === 0 ? "Empty" : "+" + (card.apps.length - 4)
                                                        color: Colors.on_surface_variant
                                                        font.family: Appearance.font.family
                                                        font.pixelSize: 10 * root.s
                                                        font.weight: Font.Medium
                                                    }
                                                }
                                            }
                                            // last visible card carries the overflow count
                                            Rectangle {
                                                visible: card.overflow
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 6 * root.s
                                                width: moreText.implicitWidth + 10 * root.s
                                                height: 16 * root.s
                                                radius: height / 2
                                                color: Colors.secondary_container
                                                Text {
                                                    id: moreText
                                                    anchors.centerIn: parent
                                                    text: "+" + (wsList.count - wsList.shown)
                                                    color: Colors.on_secondary_container
                                                    font.family: Appearance.font.family
                                                    font.pixelSize: 9.5 * root.s
                                                    font.weight: Font.Bold
                                                }
                                            }
                                            MouseArea {
                                                id: cardArea
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + card.modelData.id + " })");
                                                    root.requestClose();
                                                }
                                            }
                                            Accessible.role: Accessible.Button
                                            Accessible.name: "Workspace " + card.modelData.id + ", " + card.modelData.wins.length + " windows"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── column 3: machine ───────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 358 * root.s
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true
                    spacing: 16 * root.s

                    BatteryTile {
                        order: 3
                        visible: Battery.present
                        Layout.fillWidth: true
                        Layout.preferredHeight: 330 * root.s
                    }

                    Tile {
                        id: sysBox
                        order: 6
                        surface: "sysmon"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 196 * root.s
                        accessibleName: "System, CPU " + Sysmon.cpu + " percent, memory " + Sysmon.memPct + " percent"

                        TileLabel { kanji: "系"; text: "System" }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 20 * root.s
                            y: 14 * root.s
                            height: 24 * root.s
                            verticalAlignment: Text.AlignVCenter
                            visible: Sysmon.cpuTemp >= 0
                            text: Sysmon.cpuTemp + "°"
                            color: Sysmon.cpuTemp >= 90 ? Colors.error : Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 11 * root.s
                            font.weight: Font.Bold
                            font.features: ({ "tnum": 1 })
                        }
                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 20 * root.s
                            anchors.rightMargin: 20 * root.s
                            y: 46 * root.s
                            spacing: 8 * root.s
                            Spark {
                                label: "CPU"
                                value: Sysmon.cpu
                                valueText: Sysmon.cpu + "%"
                                hist: Sysmon.cpuHist
                                enter: sysBox.seg(0, 4)
                                tint: Colors.primary
                            }
                            Spark {
                                label: "RAM"
                                value: Sysmon.memPct
                                valueText: Sysmon.memUsedGb.toFixed(1) + " GB"
                                hist: Sysmon.memHist
                                enter: sysBox.seg(1, 4)
                                tint: Colors.tertiary
                            }
                        }
                        // live readings under the graphs, one even column each
                        Row {
                            id: sysStats
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 20 * root.s
                            anchors.rightMargin: 20 * root.s
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 16 * root.s
                            spacing: 14 * root.s
                            readonly property int n: (Sysmon.hasGpu ? 1 : 0) + 2 + (Sysmon.swapUsedGb > 0.05 ? 1 : 0)
                            readonly property real colW: (width - (n - 1) * spacing) / n
                            Stat {
                                visible: Sysmon.hasGpu
                                width: sysStats.colW
                                caption: "GPU"
                                enter: sysBox.seg(2, 4)
                                value: Sysmon.gpu + "%"
                                aside: Sysmon.gpuTemp >= 0 ? Sysmon.gpuTemp + "°" : ""
                                frac: Sysmon.gpu / 100
                            }
                            Stat {
                                width: sysStats.colW
                                caption: "Disk"
                                enter: sysBox.seg(2.6, 4)
                                value: Sysmon.diskPct + "%"
                                frac: Sysmon.diskPct / 100
                                tint: Sysmon.diskPct >= 90 ? Colors.error : Colors.secondary
                            }
                            Stat {
                                visible: Sysmon.swapUsedGb > 0.05
                                width: sysStats.colW
                                caption: "Swap"
                                enter: sysBox.seg(3.2, 4)
                                value: Sysmon.swapUsedGb.toFixed(1)
                                aside: "GB"
                            }
                            Stat {
                                width: sysStats.colW
                                caption: "Net"
                                enter: sysBox.seg(3.8, 4)
                                value: "↓ " + Sysmon.netDown.toFixed(1)
                                aside: "↑ " + Sysmon.netUp.toFixed(1)
                            }
                        }
                    }

                    Tile {
                        id: notifTile
                        order: 8
                        surface: "notifications"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property var latest: Services.Notifications.groups.length ? Services.Notifications.groups[0].newest : null
                        accessibleName: Services.Notifications.unread > 0 ? Services.Notifications.unread + " unread notifications" : "No unread notifications"

                        TileLabel { kanji: "報"; text: "Notifications" }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 20 * root.s
                            y: 14 * root.s
                            height: 24 * root.s
                            verticalAlignment: Text.AlignVCenter
                            visible: notifTile.latest !== null
                            text: Services.Notifications.unread > 0 ? Services.Notifications.unread + " unread"
                                : (Services.Notifications.dnd ? "Silenced" : "Read")
                            color: Services.Notifications.unread > 0 ? Colors.primary : Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 11 * root.s
                            font.weight: Font.Bold
                        }
                        Column {
                            visible: notifTile.latest === null
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 12 * root.s
                            spacing: 6 * root.s
                            GlyphIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 26 * root.s
                                height: width
                                name: Services.Notifications.dnd ? "dnd" : "inbox"
                                color: Qt.alpha(Colors.on_surface_variant, 0.6)
                                stroke: 1.6
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Services.Notifications.dnd ? "Silenced, nothing waiting" : "Nothing new"
                                color: Qt.alpha(Colors.on_surface_variant, 0.8)
                                font.family: Appearance.font.family
                                font.pixelSize: 11.5 * root.s
                                font.weight: Font.Medium
                            }
                        }
                        /** One quiet line per app, newest first: icon chip, summary, age. */
                        Column {
                            id: notifList
                            visible: notifTile.latest !== null
                            x: 12 * root.s
                            y: 44 * root.s
                            width: parent.width - 24 * root.s
                            readonly property real rowH: 34 * root.s
                            readonly property int rows: Math.max(1, Math.floor((notifTile.height - y - 10 * root.s) / rowH))
                            Repeater {
                                model: Services.Notifications.groups.slice(0, notifList.rows)
                                Item {
                                    id: nRow
                                    required property var modelData
                                    required property int index
                                    opacity: notifTile.seg(nRow.index, 4)
                                    transform: Translate { x: (1 - notifTile.seg(nRow.index, 4)) * -14 * root.s }
                                    readonly property var n: modelData.newest
                                    width: notifList.width
                                    height: notifList.rowH
                                    Rectangle {
                                        id: nChip
                                        x: 8 * root.s
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 24 * root.s
                                        height: width
                                        radius: 7 * root.s
                                        color: Colors.surface_container_highest
                                        IconImage {
                                            id: nIcon
                                            anchors.centerIn: parent
                                            implicitSize: 16 * root.s
                                            source: Services.Notifications.iconFor(nRow.n)
                                            asynchronous: true
                                            visible: status === Image.Ready
                                        }
                                        GlyphIcon {
                                            anchors.centerIn: parent
                                            visible: !nIcon.visible
                                            width: 14 * root.s
                                            height: width
                                            name: "inbox"
                                            color: Colors.on_surface_variant
                                            stroke: 1.7
                                        }
                                    }
                                    Text {
                                        anchors.left: nChip.right
                                        anchors.leftMargin: 10 * root.s
                                        anchors.right: nAge.left
                                        anchors.rightMargin: 10 * root.s
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        text: nRow.n ? (nRow.n.summary || nRow.modelData.app) : ""
                                        color: Colors.on_surface
                                        font.family: Appearance.font.family
                                        font.pixelSize: 12.5 * root.s
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        id: nAge
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8 * root.s
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (nRow.modelData.count > 1 ? nRow.modelData.count + "  ·  " : "")
                                            + (nRow.n ? Services.Notifications.ageLabel(nRow.n) : "")
                                        color: Colors.on_surface_variant
                                        font.family: Appearance.font.family
                                        font.pixelSize: 10.5 * root.s
                                        font.weight: Font.DemiBold
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── building blocks ─────────────────────────────────────────────────────

    /**
     * Base tile. Drops in from above (toward the pill) with a spatial spring,
     * staggered by `order`; lifts and fades on close. The body is a door to
     * `surface` when set — the press layer sits UNDER the content so controls
     * inside still take their own clicks.
     */
    /**
     * Mini-map of one workspace: its windows at their real positions in the
     * monitor's usable area, each a still screencopy (re-grabbed per open)
     * with the app icon until the first frame lands.
     */
    component WsMap: Rectangle {
        id: map
        property var space: null
        property bool pressed: false
        radius: 8 * root.s
        color: Colors.surface_container_lowest
        border.width: map.space && map.space.focusedMon ? 2 : 1
        border.color: map.space && map.space.focusedMon ? Colors.primary : Qt.alpha(Colors.outline_variant, 0.8)
        scale: map.pressed ? 0.98 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Item {
            id: winsBox
            anchors.fill: parent
            anchors.margins: map.border.width + 1
            Repeater {
                model: map.space ? map.space.wins : []
                ClippingRectangle {
                    id: win
                    required property var modelData
                    readonly property real pw: winsBox.width
                    readonly property real ph: winsBox.height
                    x: Math.max(0, win.modelData.x * pw)
                    y: Math.max(0, win.modelData.y * ph)
                    width: Math.max(4, Math.min(pw - x, win.modelData.w * pw))
                    height: Math.max(4, Math.min(ph - y, win.modelData.h * ph))
                    radius: Math.min(map.radius * 0.5, 5 * root.s)
                    color: Colors.surface_container_highest
                    border.width: win.modelData.focus && map.space.wins.length > 1 ? 1.5 : 0
                    border.color: Colors.primary

                    ScreencopyView {
                        id: shot
                        anchors.fill: parent
                        captureSource: root.visible && win.modelData.tl ? win.modelData.tl.wayland : null
                        live: false
                        readonly property int rev: root.captureRev
                        onRevChanged: if (root.open && hasContent) captureFrame()
                    }
                    IconImage {
                        anchors.centerIn: parent
                        readonly property real sz: Math.min(parent.width, parent.height) * 0.5
                        implicitSize: Math.min(sz, 22 * root.s)
                        visible: !shot.hasContent && sz > 7 && source != ""
                        source: root.appIcon(win.modelData.cls)
                        asynchronous: true
                    }
                }
            }
        }
    }

    /** 前/次 skip glyph for the media transport (the pill's KanjiSkip, dashboard-sized). */
    component DashSkip: Item {
        id: skip
        property bool can: false
        property string kanjiText: ""
        property string accessibleName: ""
        signal activated()

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 28 * root.s
        implicitHeight: 28 * root.s
        opacity: skip.can ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        Text {
            anchors.centerIn: parent
            text: skip.kanjiText
            font.family: Appearance.font.jp
            font.pixelSize: 19 * root.s
            color: skipArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
            scale: skipArea.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }
        MouseArea {
            id: skipArea
            anchors.fill: parent
            anchors.margins: -6 * root.s
            hoverEnabled: true
            enabled: skip.can
            cursorShape: Qt.PointingHandCursor
            onClicked: skip.activated()
        }
        Accessible.role: Accessible.Button
        Accessible.name: skip.accessibleName
    }

    component Tile: Rectangle {
        id: tile
        property int order: 0
        property string surface: ""
        property string accessibleName: ""
        property real rise: 0
        /**
         * Content entrance, 0→1, starting as the tile settles: contents stagger
         * in off it with seg(i, n) (item i of n), graphs draw in off it whole.
         */
        property real reveal: 1
        function seg(i, n) { return Math.max(0, Math.min(1, (tile.reveal * (n + 1.5) - i) / 1.5)); }

        radius: 24 * root.s
        color: Qt.alpha(Colors.surface_container, 0.94)
        border.width: 1
        border.color: Qt.alpha(Colors.outline_variant, 0.45)

        // In: eases up from rest (emphasized — slow start, long settle) rather
        // than launching. Out: fade tracks the shrink from the first frame, so
        // the tile never sits fully opaque and still before it goes.
        opacity: root.open ? Math.max(0, Math.min(1, tile.rise * 1.4)) : tile.rise
        transform: [
            Scale {
                origin.x: tile.width / 2
                origin.y: tile.height / 2
                xScale: 0.92 + 0.08 * tile.rise
                yScale: 0.92 + 0.08 * tile.rise
            },
            Translate { y: (1 - tile.rise) * 18 * root.s }
        ]

        Connections {
            target: root
            function onOpenChanged() {
                if (root.open) {
                    outAnim.stop();
                    tile.rise = 0;
                    tile.reveal = 0;
                    inAnim.restart();
                    revealAnim.restart();
                } else {
                    inAnim.stop();
                    outAnim.restart();
                }
            }
        }
        SequentialAnimation {
            id: inAnim
            PauseAnimation { duration: 60 * Motion.mult + tile.order * Motion.rowStagger * 2 }
            NumberAnimation {
                target: tile
                property: "rise"
                to: 1
                duration: Motion.largeDur
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.emphasized
            }
        }
        SequentialAnimation {
            id: revealAnim
            PauseAnimation { duration: 60 * Motion.mult + tile.order * Motion.rowStagger * 2 + Motion.smallDur + Motion.rowStagger * 2 }
            NumberAnimation {
                target: tile
                property: "reveal"
                to: 1
                duration: Math.round(Motion.largeDur * 1.8)
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.emphasized
            }
        }
        NumberAnimation {
            id: outAnim
            target: tile
            property: "rise"
            to: 0
            // same curve as the scrim so the board and backdrop leave together
            duration: Motion.expressiveEffectsDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveEffects
        }

        Accessible.role: tile.surface.length ? Accessible.Button : Accessible.Grouping
        Accessible.name: tile.accessibleName

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Colors.on_surface
            opacity: tileArea.enabled && tileArea.pressed ? 0.08 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            enabled: tile.surface.length > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: root.go(tile.surface)
        }
    }

    /** Tile header in the pill-surface idiom: kanji identity mark, then the uppercase label. */
    component TileLabel: Row {
        id: tl
        property string kanji: ""
        property string text: ""
        x: 20 * root.s
        y: 14 * root.s
        height: 24 * root.s
        spacing: 9 * root.s
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Flags.showGlyphs && tl.kanji.length > 0
            text: tl.kanji
            color: Colors.on_surface
            font.family: Appearance.font.jp
            font.weight: Font.Medium
            font.pixelSize: 16 * root.s
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: tl.text
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 10 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.8 * root.s
        }
    }

    /**
     * Expressive quick-settings tile: a pill at rest that firms into a
     * rounded square when on (shape carries state, not just colour), filled
     * with primary_container; icon, name and the live state under it.
     */
    component QsTile: Rectangle {
        id: qs
        property string icon: ""
        property string label: ""
        property string sub: ""
        property bool checked: false
        /** Entrance, 0→1 (the tile's stagger). */
        property real enter: 1
        signal clicked()

        height: 54 * root.s
        opacity: qs.enter
        transform: Scale {
            origin.x: qs.width / 2
            origin.y: qs.height / 2
            xScale: 0.82 + 0.18 * qs.enter
            yScale: 0.82 + 0.18 * qs.enter
        }
        radius: qs.checked ? 16 * root.s : height / 2
        color: qs.checked ? Colors.primary_container : Colors.surface_container_highest
        Behavior on radius {
            NumberAnimation {
                duration: Motion.expressiveFastSpatialDur
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        scale: qsArea.pressed ? 0.96 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        readonly property color ink: qs.checked ? Colors.on_primary_container : Colors.on_surface

        Accessible.role: Accessible.Button
        Accessible.name: qs.label
        Accessible.description: qs.sub
        Accessible.checkable: true
        Accessible.checked: qs.checked
        Accessible.onPressAction: qs.clicked()

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: qs.ink
            opacity: qsArea.pressed ? 0.12 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        GlyphIcon {
            id: qsIcon
            anchors.left: parent.left
            anchors.leftMargin: 18 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 19 * root.s
            height: width
            name: qs.icon
            color: qs.ink
            stroke: 1.8
        }
        Column {
            anchors.left: qsIcon.right
            anchors.leftMargin: 11 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 14 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * root.s
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: qs.label
                color: qs.ink
                font.family: Appearance.font.family
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: qs.sub
                color: qs.checked ? Qt.alpha(Colors.on_primary_container, 0.8) : Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Medium
            }
        }
        MouseArea {
            id: qsArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: qs.clicked()
        }
    }

    /**
     * Icon · fader · readout. The fader is the Mixer's ink-fader laid on its
     * side: a thick rounded track split by a thin handle bar with a gap either
     * side, active segment in primary (outline when muted), the rest in
     * secondary_container with a stop dot at the far end. `value` is 0..100
     * and host-owned; drags emit moved(v), let-go emits released().
     */
    component SliderRow: Item {
        id: sr
        property string icon: ""
        property string label: ""
        property real value: 0
        property bool muted: false
        /** Entrance, 0→1: the level pours in from empty. */
        property real enter: 1
        signal moved(real v)
        signal released()
        signal iconClicked()
        width: parent ? parent.width : 0
        height: 38 * root.s
        opacity: Math.min(1, sr.enter * 3)

        readonly property real safeValue: Number.isFinite(sr.value) ? Math.max(0, Math.min(100, sr.value)) : 0

        Accessible.role: Accessible.Slider
        Accessible.name: sr.label
        Accessible.description: sr.muted ? "Muted" : Math.round(sr.safeValue) + " percent"
        Accessible.onIncreaseAction: sr.moved(Math.min(100, sr.safeValue + 5))
        Accessible.onDecreaseAction: sr.moved(Math.max(0, sr.safeValue - 5))

        M3IconButton {
            id: srIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            s: root.s * 0.9
            icon: sr.icon
            accessibleName: sr.label
            onClicked: sr.iconClicked()
        }

        Item {
            id: track
            anchors.left: srIcon.right
            anchors.leftMargin: 8 * root.s
            anchors.right: srVal.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            height: 18 * root.s

            readonly property real gap: 4 * root.s
            readonly property real handleW: 4 * root.s
            readonly property real outerR: 8 * root.s
            readonly property real innerR: 2 * root.s
            readonly property bool lit: srArea.containsMouse || srArea.pressed
            property real handleX: sr.safeValue / 100 * width * sr.enter
            readonly property color activeColor: sr.muted ? Colors.outline : Colors.primary

            Behavior on handleX {
                enabled: !srArea.pressed && sr.enter >= 1
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            Rectangle {
                id: activeSeg
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                width: Math.max(0, track.handleX - track.handleW / 2 - track.gap)
                height: parent.height
                visible: width > 0.5
                color: track.activeColor
                opacity: track.lit || sr.muted ? 1 : 0.85
                topLeftRadius: track.outerR
                bottomLeftRadius: track.outerR
                topRightRadius: Math.min(track.innerR, width / 2)
                bottomRightRadius: Math.min(track.innerR, width / 2)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }
            Rectangle {
                id: inactiveSeg
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(track.width, track.handleX + track.handleW / 2 + track.gap)
                width: Math.max(0, track.width - x)
                height: parent.height
                visible: width > 0.5
                color: Colors.secondary_container
                topRightRadius: track.outerR
                bottomRightRadius: track.outerR
                topLeftRadius: Math.min(track.innerR, width / 2)
                bottomLeftRadius: Math.min(track.innerR, width / 2)
            }
            // Stop indicator at the far end of the inactive track.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: track.width - 5 * root.s - width
                width: 4 * root.s
                height: width
                radius: width / 2
                color: Colors.on_secondary_container
                visible: inactiveSeg.width > 12 * root.s
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: track.handleX - width / 2
                width: (srArea.pressed ? 3 : 4) * root.s
                height: (track.lit ? 32 : 28) * root.s
                radius: width / 2
                color: track.activeColor
                Behavior on height { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: srArea
                anchors.fill: parent
                anchors.margins: -10 * root.s
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                function setFromX(mx) {
                    sr.moved(100 * Math.max(0, Math.min(1, (mx - 10 * root.s) / track.width)));
                }
                onPressed: (e) => setFromX(e.x)
                onPositionChanged: (e) => { if (pressed) setFromX(e.x); }
                onReleased: sr.released()
                onCanceled: sr.released()
                onWheel: (w) => sr.moved(Math.max(0, Math.min(100, sr.safeValue + (w.angleDelta.y > 0 ? 5 : -5))))
            }
        }

        Text {
            id: srVal
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34 * root.s
            horizontalAlignment: Text.AlignRight
            text: sr.muted ? "off" : Math.round(sr.safeValue) + "%"
            color: track.lit ? Colors.on_surface : Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    /** Label · sparkline (history) · value. */
    component Spark: Item {
        id: sp
        property string label: ""
        property real value: 0
        property string valueText: ""
        property var hist: []
        property color tint: Colors.primary
        /** Entrance, 0→1: the graph draws in left→right. */
        property real enter: 1
        width: parent ? parent.width : 0
        height: 38 * root.s
        opacity: Math.min(1, sp.enter * 3)
        onHistChanged: graph.requestPaint()
        onTintChanged: graph.requestPaint()

        Text {
            id: spLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 38 * root.s
            text: sp.label
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Bold
            font.letterSpacing: 1 * root.s
        }
        Item {
            id: graphBox
            anchors.left: spLabel.right
            anchors.right: spVal.left
            anchors.rightMargin: 10 * root.s
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            Item {
                width: parent.width * sp.enter
                height: parent.height
                clip: true
        Canvas {
            id: graph
            width: graphBox.width
            height: graphBox.height
            onWidthChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var h = sp.hist;
                var n = Sysmon.histLen;
                // baseline + 50% guide so a fresh graph still reads as a graph
                ctx.fillStyle = Qt.alpha(Colors.on_surface, 0.07);
                ctx.fillRect(0, Math.round(height / 2), width, 1);
                ctx.fillStyle = Qt.alpha(Colors.on_surface, 0.12);
                ctx.fillRect(0, height - 1, width, 1);
                if (!h || h.length < 2)
                    return;
                if (h.length > n)
                    h = h.slice(h.length - n);
                var W = width, H = height, pad = 2 * root.s;
                // stretch what exists across the width; settles at histLen
                var step = W / (Math.max(2, Math.min(n, h.length)) - 1);
                var x0 = 0;
                function yOf(v) { return pad + (H - 2 * pad) * (1 - Math.max(0, Math.min(100, v)) / 100); }
                ctx.beginPath();
                ctx.moveTo(x0, H);
                for (var i = 0; i < h.length; i++)
                    ctx.lineTo(x0 + i * step, yOf(h[i]));
                ctx.lineTo(W, H);
                ctx.closePath();
                ctx.fillStyle = Qt.alpha(sp.tint, 0.16);
                ctx.fill();
                ctx.beginPath();
                for (var j = 0; j < h.length; j++) {
                    if (j === 0) ctx.moveTo(x0, yOf(h[0]));
                    else ctx.lineTo(x0 + j * step, yOf(h[j]));
                }
                ctx.lineWidth = 1.8 * root.s;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.strokeStyle = sp.tint;
                ctx.stroke();
            }
        }
            }
        }
        Text {
            id: spVal
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 58 * root.s
            horizontalAlignment: Text.AlignRight
            text: sp.valueText
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 13 * root.s
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
        }
    }

    /**
     * Battery: ink-filled gauge with a big percentage, time left plus the
     * wall-clock time it lands, a 3 h charge curve, draw/health/energy, and
     * the platform profile (read-only — it is root-owned sysfs and no
     * power-profiles daemon is installed; Fn+Q cycles it).
     */
    component BatteryTile: Tile {
        id: bt
        surface: ""
        accessibleName: "Battery " + Battery.pct + " percent, " + Battery.stateLabel
            + (Battery.hasTime ? ", " + Battery.timeStr + (Battery.charging ? " to full" : " left") : "")

        readonly property color tint: Battery.low ? Colors.error : (Battery.charging ? Colors.tertiary : Colors.primary)
        /** On the charger (charging, or holding at a charge limit). */
        readonly property bool onAc: Battery.present && !Battery.discharging
        readonly property real secs: !Battery.dev ? 0 : (Battery.charging ? Battery.dev.timeToFull : (Battery.discharging ? Battery.dev.timeToEmpty : 0))

        TileLabel { kanji: "電"; text: "Battery" }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 20 * root.s
            y: 16 * root.s
            text: Battery.stateLabel
            color: bt.tint
            font.family: Appearance.font.family
            font.pixelSize: 11 * root.s
            font.weight: Font.Bold
        }

        // gauge
        Item {
            id: gauge
            x: 20 * root.s
            y: 46 * root.s
            width: parent.width - 40 * root.s
            height: 58 * root.s

            Rectangle {
                id: body
                anchors.left: parent.left
                opacity: bt.onAc ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveEffects } }
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - pctText.width - 22 * root.s
                height: 46 * root.s
                radius: 14 * root.s
                color: Colors.surface_container_lowest
                border.width: 2 * root.s
                border.color: Qt.alpha(bt.tint, 0.55)

                ClippingRectangle {
                    id: well
                    anchors.fill: parent
                    anchors.margins: 5 * root.s
                    radius: 9 * root.s
                    color: "transparent"

                    Rectangle {
                        id: level
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(radius * 2, parent.width * Battery.frac)
                        radius: 9 * root.s
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.alpha(bt.tint, 0.75) }
                            GradientStop { position: 1.0; color: bt.tint }
                        }
                        Behavior on width {
                            NumberAnimation {
                                duration: Motion.normalDur
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveDefaultSpatial
                            }
                        }

                        // Wet edge: a soft bright lip at the ink front.
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.min(parent.width, 14 * root.s)
                            radius: parent.radius
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.alpha(Colors.on_surface, 0) }
                                GradientStop { position: 1.0; color: Qt.alpha(Colors.on_surface, 0.22) }
                            }
                        }
                    }
                }
            }
            // nub
            Rectangle {
                anchors.left: body.right
                opacity: bt.onAc ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveEffects } }
                anchors.leftMargin: 3 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 5 * root.s
                height: 16 * root.s
                radius: 2.5 * root.s
                color: Qt.alpha(bt.tint, 0.55)
            }
            /**
             * On the charger: the OSD's plug-in face held open — 充 and the
             * level as a wet 筆 ink stroke — with charge flowing along it, a
             * bright bead running from the entry press to the head on loop.
             * Holding at a limit flows at half the rate.
             */
            Item {
                id: acGauge
                anchors.left: parent.left
                anchors.right: pctText.left
                anchors.rightMargin: 18 * root.s
                anchors.verticalCenter: parent.verticalCenter
                height: 46 * root.s
                opacity: bt.onAc ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveEffects } }

                // Plugging in pours the level in from the entry press
                // instead of the stroke just appearing full.
                property real sweep: 1
                NumberAnimation {
                    id: acSweep
                    target: acGauge
                    property: "sweep"
                    from: 0
                    to: 1
                    duration: Math.round(Motion.largeDur * 1.6)
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.emphasized
                }
                Connections {
                    target: bt
                    function onOnAcChanged() { if (bt.onAc) acSweep.restart(); }
                }

                Text {
                    id: acGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "充"
                    color: Colors.tertiary
                    font.family: Appearance.font.jp
                    font.weight: Font.Bold
                    font.pixelSize: 30 * root.s
                    scale: 0.6 + 0.4 * Math.min(1, acGauge.sweep * 2.5)
                }
                InkStroke {
                    id: acInk
                    anchors.left: acGlyph.right
                    anchors.leftMargin: 14 * root.s
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 34 * root.s
                    s: root.s * 1.8
                    frac: Battery.frac * acGauge.sweep
                    glide: false
                    inkStops: [Colors.error, Colors.tertiary, Colors.primary]
                    wet: 1
                    paper: Colors.surface_container
                }
                Rectangle {
                    id: bead
                    property real t: 0
                    readonly property real run: Math.max(0, acInk.headX - acInk.inset - 26 * root.s)
                    visible: acGauge.visible && acGauge.sweep >= 1 && run > 8 * root.s && !Motion.reduceMotion
                    x: acInk.x + acInk.inset + bead.t * bead.run - width / 2
                    anchors.verticalCenter: acInk.verticalCenter
                    width: 30 * root.s
                    height: 7 * root.s
                    radius: height / 2
                    // fades in off the entry press and out before the dry head
                    opacity: Math.min(1, bead.t * 5, (1 - bead.t) * 4)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.alpha(Colors.on_primary, 0) }
                        GradientStop { position: 0.7; color: Qt.alpha(Colors.on_primary, 0.55) }
                        GradientStop { position: 1.0; color: Qt.alpha(Colors.on_primary, 0) }
                    }
                    SequentialAnimation on t {
                        running: bead.visible && root.open
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0
                            to: 1
                            duration: Motion.heat * (Battery.charging ? 2 : 4)
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.emphasized
                        }
                        PauseAnimation { duration: Motion.standard }
                    }
                }
            }

            Text {
                id: pctText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Battery.pct + "%"
                color: Battery.low ? Colors.error : Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 38 * root.s
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
            }
        }

        Text {
            id: timeLine
            x: 20 * root.s
            anchors.top: gauge.bottom
            anchors.topMargin: 8 * root.s
            width: parent.width - 40 * root.s
            elide: Text.ElideRight
            text: bt.secs > 0
                ? Battery.fmt(bt.secs) + (Battery.charging ? " to full" : " left") + "  ·  "
                    + (Battery.charging ? "full around " : "empty around ")
                    + root.fmtTime(new Date(root.now.getTime() + bt.secs * 1000))
                : (Battery.full ? "Fully charged"
                    : (!Battery.charging && !Battery.discharging ? "Plugged in, holding at " + Battery.pct + "%" : Battery.stateLabel))
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 13 * root.s
            font.weight: Font.Medium
        }

        // history curve, taking whatever height the bottom block leaves
        Item {
            id: histBox
            x: 20 * root.s
            anchors.top: timeLine.bottom
            anchors.topMargin: 12 * root.s
            anchors.bottom: battStats.top
            anchors.bottomMargin: 14 * root.s
            width: parent.width - 40 * root.s

            Text {
                id: histLabel
                anchors.left: parent.left
                anchors.top: parent.top
                text: Battery.hist.length >= 2
                    ? "LAST " + (Battery.hist.length >= 120 ? Math.round(Battery.hist.length / 60) + "H" : Battery.hist.length + " MIN")
                    : "HISTORY"
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
                font.letterSpacing: 1.2 * root.s
            }
            Text {
                anchors.centerIn: curve
                visible: Battery.hist.length < 2
                text: "Fills in by the minute"
                color: Qt.alpha(Colors.on_surface_variant, 0.7)
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
            }
            Canvas {
                id: curve
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: histLabel.bottom
                anchors.topMargin: 6 * root.s
                anchors.bottom: parent.bottom
                readonly property var h: Battery.hist
                readonly property color tint: bt.tint
                // unrolls from the left with the tile's reveal
                opacity: Math.min(1, bt.reveal * 3)
                transform: Scale { xScale: bt.reveal }
                onHChanged: requestPaint()
                onTintChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var W = width, H = height;
                    // 20% / 50% / 80% guides
                    ctx.strokeStyle = Qt.alpha(Colors.on_surface, 0.07);
                    ctx.lineWidth = 1;
                    [0.2, 0.5, 0.8].forEach(function (g) {
                        ctx.beginPath();
                        ctx.moveTo(0, Math.round(H * (1 - g)) + 0.5);
                        ctx.lineTo(W, Math.round(H * (1 - g)) + 0.5);
                        ctx.stroke();
                    });
                    if (h.length < 2)
                        return;
                    var step = W / (h.length - 1);
                    function yOf(p) { return 2 + (H - 4) * (1 - p / 100); }
                    ctx.beginPath();
                    ctx.moveTo(0, H);
                    for (var i = 0; i < h.length; i++)
                        ctx.lineTo(i * step, yOf(h[i].pct));
                    ctx.lineTo(W, H);
                    ctx.closePath();
                    var g = ctx.createLinearGradient(0, 0, 0, H);
                    g.addColorStop(0, Qt.alpha(tint, 0.28));
                    g.addColorStop(1, Qt.alpha(tint, 0.0));
                    ctx.fillStyle = g;
                    ctx.fill();
                    ctx.lineWidth = 2.2 * root.s;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";
                    for (var j = 1; j < h.length; j++) {
                        ctx.beginPath();
                        ctx.strokeStyle = h[j].chg ? Colors.tertiary : tint;
                        ctx.moveTo((j - 1) * step, yOf(h[j - 1].pct));
                        ctx.lineTo(j * step, yOf(h[j].pct));
                        ctx.stroke();
                    }
                }
            }
        }

        // readings, in the System tile's column style
        Row {
            id: battStats
            opacity: bt.seg(2, 4)
            transform: Translate { y: (1 - bt.seg(2, 4)) * 8 * root.s }
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20 * root.s
            anchors.rightMargin: 20 * root.s
            anchors.bottom: profileSeg.visible ? profileSeg.top : parent.bottom
            anchors.bottomMargin: profileSeg.visible ? 14 * root.s : 16 * root.s
            spacing: 14 * root.s
            readonly property int n: Battery.healthSupported ? 3 : 2
            readonly property real colW: (width - (n - 1) * spacing) / n
            Stat {
                width: battStats.colW
                caption: Battery.charging ? "Charging" : (Battery.discharging ? "Draw" : "Idle")
                value: Math.abs(Battery.rateW).toFixed(1)
                aside: "W"
            }
            Stat {
                visible: Battery.healthSupported
                width: battStats.colW
                caption: "Health"
                value: Battery.health + "%"
                frac: Battery.health / 100
                tint: Battery.health < 70 ? Colors.error : Colors.secondary
            }
            Stat {
                width: battStats.colW
                caption: "Energy"
                value: (Battery.dev ? Battery.dev.energy : 0).toFixed(1)
                aside: "/ " + Battery.capacityWh.toFixed(1) + " Wh"
            }
        }

        /**
         * Platform profile as a connected segmented control. Live when the
         * udev rule makes the sysfs node writable; otherwise a read-only
         * display with a lock glyph saying so.
         */
        Item {
            id: profileSeg
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20 * root.s
            anchors.rightMargin: 20 * root.s
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16 * root.s
            height: 30 * root.s
            visible: root.profile.length > 0

            readonly property var opts: [
                { k: "low-power", label: "Saver" },
                { k: "balanced", label: "Balanced" },
                { k: "performance", label: "Perform" },
                { k: "max-power", label: "Max" }
            ]
            readonly property real lockW: root.profileWritable ? 0 : 22 * root.s
            readonly property real gap: 2 * root.s
            readonly property real segW: (width - lockW - (opts.length - 1) * gap) / opts.length

            Row {
                spacing: profileSeg.gap
                Repeater {
                    model: profileSeg.opts
                    Rectangle {
                        id: seg
                        required property var modelData
                        required property int index
                        opacity: bt.seg(2.6 + seg.index * 0.4, 4)
                        transform: Translate { y: (1 - bt.seg(2.6 + seg.index * 0.4, 4)) * 8 * root.s }
                        readonly property bool on: root.profile === seg.modelData.k
                        readonly property bool first: index === 0
                        readonly property bool last: index === profileSeg.opts.length - 1
                        width: profileSeg.segW
                        height: profileSeg.height
                        readonly property real outer: height / 2
                        readonly property real inner: seg.on ? height / 2 : 5 * root.s
                        topLeftRadius: seg.first ? outer : inner
                        bottomLeftRadius: seg.first ? outer : inner
                        topRightRadius: seg.last ? outer : inner
                        bottomRightRadius: seg.last ? outer : inner
                        color: seg.on ? Colors.secondary_container : Colors.surface_container_highest
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        scale: segArea.pressed ? 0.95 : 1
                        Behavior on scale { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial } }
                        Behavior on topLeftRadius { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial } }
                        Behavior on topRightRadius { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial } }
                        Behavior on bottomLeftRadius { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial } }
                        Behavior on bottomRightRadius { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial } }

                        Accessible.role: Accessible.RadioButton
                        Accessible.name: seg.modelData.label + " power profile"
                        Accessible.checkable: true
                        Accessible.checked: seg.on
                        Accessible.onPressAction: root.setProfile(seg.modelData.k)

                        Row {
                            anchors.centerIn: parent
                            spacing: 4 * root.s
                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: seg.on
                                width: 11 * root.s
                                height: width
                                name: "check"
                                stroke: 2.2
                                color: Colors.on_secondary_container
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: seg.modelData.label
                                color: seg.on ? Colors.on_secondary_container : Colors.on_surface_variant
                                font.family: Appearance.font.family
                                font.pixelSize: 10.5 * root.s
                                font.weight: seg.on ? Font.Bold : Font.Medium
                            }
                        }
                        MouseArea {
                            id: segArea
                            anchors.fill: parent
                            enabled: root.profileWritable
                            cursorShape: Qt.PointingHandCursor
                            onPressed: root.setProfile(seg.modelData.k)
                        }
                    }
                }
            }
            GlyphIcon {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.profileWritable
                width: 14 * root.s
                height: width
                name: "lock"
                stroke: 1.7
                color: Colors.on_surface_variant
            }
        }
    }

    /** Uppercase caption, value with a quieter aside, and an optional thin meter. */
    component Stat: Column {
        id: stat
        property string caption: ""
        property string value: ""
        property string aside: ""
        /** 0..1 fills the meter; < 0 hides it. */
        property real frac: -1
        property color tint: Colors.primary
        /** Entrance, 0→1: fades up, the meter fills from empty. */
        property real enter: 1
        spacing: 4 * root.s
        opacity: stat.enter
        transform: Translate { y: (1 - stat.enter) * 8 * root.s }
        Text {
            text: stat.caption
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
        }
        Row {
            spacing: 5 * root.s
            Text {
                anchors.baseline: parent.children[1].baseline
                text: stat.value
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 14 * root.s
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
            }
            Text {
                text: stat.aside
                visible: text.length > 0
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }
        Rectangle {
            width: stat.width
            height: 3 * root.s
            radius: height / 2
            color: Qt.alpha(Colors.on_surface, 0.08)
            opacity: stat.frac >= 0 ? 1 : 0
            Rectangle {
                width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, stat.frac)) * stat.enter)
                height: parent.height
                radius: parent.radius
                color: stat.tint
                Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveDefaultSpatial } }
            }
        }
    }

    component Fact: Column {
        id: fact
        property string value: ""
        property string caption: ""
        spacing: 1 * root.s
        Text {
            text: fact.value
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 14 * root.s
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
        }
        Text {
            text: fact.caption
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
        }
    }
}
