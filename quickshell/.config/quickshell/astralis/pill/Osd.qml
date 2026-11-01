import QtQuick
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "../colors"
import "../services"
import "../config"

/**
 * astralis — the OSD face (ported from Ricelin pill/Osd.qml). A short-lived
 * flash the pill morphs into when a watched quantity changes: volume keys,
 * brightness keys, a track switch, the charger landing, a workspace hop,
 * the camera hardware kill-switch flipping, a screen recording starting or
 * stopping.
 * `flashing` drives the pill's osd mode; each kind renders its own stacked
 * row and the rows cross-fade on `kind`.
 */
Item {
    id: root

    property real s: 1
    property string screenName: ""
    property bool suppressed: false
    property bool expanded: false
    property bool flashing: false
    property string kind: "volume"
    property bool armed: false
    property bool dirty: false
    property bool cooling: false
    property int holdExtends: 0

    /**
     * The player the current flash speaks for. Normally the active source, but an
     * announce can point it at another player that just started, so a video over
     * your music still gets its own flash without stealing the surface.
     */
    property var pendingSubject: null
    readonly property var subject: pendingSubject ? pendingSubject : Players.active
    readonly property bool subjectHas: subject !== null
    readonly property bool subjectPlaying: subjectHas && subject.isPlaying
    readonly property string subjectTitle: subjectHas ? Players.refineTitle(subject, subject.trackTitle || Players.labelOf(subject)) : ""
    readonly property string subjectArtist: subjectHas ? Players.artistsOf(subject) : ""
    readonly property string subjectIcon: subjectHas ? Players.appIconFor(subject) : ""

    /** Subject art, live so a cover that lands a beat after the title still resolves; the key forces a reload when a browser reuses one file path. */
    readonly property string liveArt: {
        if (!subjectHas)
            return "";
        var u = Players.artUrlFor(subject);
        if (!u)
            return "";
        return u.indexOf("file:") === 0 ? u + "#" + Players.keyFor(subject) : u;
    }

    readonly property real brightness: Backlight.brightness
    property bool recordStarted: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property real maxVol: 1.5
    readonly property real volume: sink && sink.audio ? Math.max(0, Math.min(root.maxVol, sink.audio.volume)) : 0
    readonly property bool overAmp: root.volume > 1.001

    /** Default capture source; its muted state drives the mic flash. */
    readonly property var micSource: Pipewire.defaultAudioSource
    readonly property bool micMuted: micSource && micSource.audio ? micSource.audio.muted : false

    /** Camera hardware kill-switch state (Legion privacy toggle); drives the camera flash. */
    readonly property bool cameraOn: CameraToggle.enabled

    readonly property real desiredW: kind === "workspace" ? Math.max(120 * s, wsIndicator.implicitWidth + 40 * s)
        : (kind === "track" ? 344 * s : (kind === "record" ? 270 * s : (kind === "mic" ? 196 * s : (kind === "camera" ? 180 * s : 248 * s))))
    // The workspace hop keeps the rest-pill height (38*s) so switching
    // workspaces never grows the top-anchored pill downward — the dots just
    // cross-fade in place of the clock. Other flashes use the taller 44*s bar.
    readonly property real desiredH: kind === "track" ? 64 * s : (kind === "workspace" ? 38 * s : 44 * s)

    /**
     * Active workspace name on this monitor. Any switch (Super+arrow,
     * Super+wheel, clicking a dot) changes it, so flashing the workspace OSD
     * here briefly morphs the pill open to show where you landed. The arm timer
     * swallows the initial populate, so login doesn't flash. Skipped while the
     * pill is expanded: the hover/surface pill already shows the live dots with
     * the active one marked, so the OSD would only be a redundant morph.
     */
    readonly property string activeWsName: {
        var mons = Hyprland.monitors.values;
        for (var i = 0; i < mons.length; i++)
            if (mons[i].name === screenName)
                return mons[i].activeWorkspace ? mons[i].activeWorkspace.name : "";
        return "";
    }
    onActiveWsNameChanged: if (activeWsName.length > 0 && !expanded) flash("workspace");

    /**
     * Leading-edge throttle. The first change flashes at once so a real track
     * switch feels instant, then the cooldown mutes the burst that hovering the
     * YouTube grid throws off. Anything that lands during the cooldown, or while
     * the OSD is suppressed (a surface open, the pill pinned), stays `dirty` and
     * fires when the gate opens, so the stashed-player flash still replays.
     */
    function tryShow() {
        if (cooling)
            return;
        if (flash("track")) {
            dirty = false;
            cooling = true;
            cooldownTimer.restart();
        }
    }

    /**
     * Every pill carries its own Osd but the volume/track/battery signals are
     * global, so without this gate one keypress flashes every monitor at once.
     * Workspace flashes skip it: those are already keyed to this screen's own
     * active workspace.
     */
    readonly property bool onFocusedMonitor: !Hyprland.focusedMonitor || Hyprland.focusedMonitor.name === screenName

    function flash(which) {
        if (!armed || suppressed)
            return false;
        if (which !== "workspace" && !onFocusedMonitor)
            return false;
        if (which === "track" && flashing && (kind === "volume" || kind === "brightness"))
            return false;
        if (which === "track")
            holdExtends = 0;
        kind = which;
        flashing = true;
        hideTimer.interval = (which === "battery" || which === "record") ? 2000 : 1800;
        hideTimer.restart();
        return true;
    }

    onSuppressedChanged: {
        if (suppressed) {
            hideTimer.stop();
            flashing = false;
        } else if (dirty) {
            tryShow();
        }
    }

    /** A track flash that lost to live hardware feedback replays once the bar clears. */
    onFlashingChanged: if (!flashing && dirty) tryShow()

    Timer {
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: cooldownTimer
        interval: 1500
        onTriggered: {
            root.cooling = false;
            if (root.dirty)
                root.tryShow();
        }
    }

    /**
     * Hold a track flash open until its cover decodes, so a cold remote thumbnail
     * that arrives after the base window still gets seen. Capped so a dead art url
     * never pins the OSD.
     */
    Timer {
        id: hideTimer
        interval: 1800
        onTriggered: {
            if (root.kind === "track" && cover.status !== Image.Ready && root.liveArt.length > 0 && root.holdExtends < 5) {
                root.holdExtends++;
                hideTimer.interval = 350;
                hideTimer.restart();
            } else {
                root.flashing = false;
            }
        }
    }

    PwObjectTracker {
        objects: [root.sink, root.micSource].filter(Boolean)
    }

    Connections {
        target: root.sink && root.sink.audio ? root.sink.audio : null
        function onVolumesChanged() { root.flash("volume"); }
        function onMutedChanged() { root.flash("volume"); }
    }

    Connections {
        target: root.micSource && root.micSource.audio ? root.micSource.audio : null
        function onMutedChanged() { root.flash("mic"); }
    }

    Connections {
        target: CameraToggle
        function onToggled(on) { root.flash("camera"); }
    }

    Connections {
        target: Players
        function onAnnounce(player) {
            root.pendingSubject = player;
            root.dirty = true;
            root.tryShow();
        }
    }

    Connections {
        target: Battery
        enabled: Battery.present
        // Any plug-in, including straight to "holding at a limit", which
        // never passes through Charging.
        function onDischargingChanged() {
            if (!Battery.discharging)
                root.flash("battery");
        }
        // Falling through 20% and again through 10% on battery flashes the
        // level once each, so running low is never only a quiet red seal.
        function onPctChanged() {
            const p = Battery.pct;
            if (!Battery.charging && ((root.lastBattPct > 20 && p <= 20) || (root.lastBattPct > 10 && p <= 10)))
                root.flash("battery");
            root.lastBattPct = p;
        }
    }
    property int lastBattPct: -1

    // A take opening or closing flashes the record row, so starting from a
    // keybind (with the surface never opened) still confirms itself, and a
    // recorder that dies on its own is visible instead of silent.
    Connections {
        target: ScreenRec
        function onRecordingChanged() {
            root.recordStarted = ScreenRec.recording;
            root.flash("record");
        }
    }

    Connections {
        target: Backlight
        function onChanged() {
            root.flash("brightness");
        }
    }

    Item {
        id: volRow
        anchors.fill: parent
        opacity: root.kind === "volume" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        GlyphIcon {
            id: volGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s
            name: root.muted ? "speaker-off" : "speaker"
            color: root.muted ? Qt.alpha(Colors.on_surface_variant, 0.8) : Colors.on_surface_variant
            stroke: 1.7
        }

        Text {
            id: volPct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 32 * root.s
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.volume * 100) + "%"
            color: root.muted ? Qt.alpha(Colors.on_surface_variant, 0.8) : Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }

        Rectangle {
            anchors.left: volGlyph.right
            anchors.leftMargin: 12 * root.s
            anchors.right: volPct.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            height: 4 * root.s
            radius: 2 * root.s
            color: Qt.alpha(Colors.on_surface, 0.13)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1, root.volume / root.maxVol)
                radius: parent.radius
                // same primary_container → tertiary ramp as the battery bar;
                // muting dims the whole ramp, over-amp burns its head red
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0.0
                        color: root.muted ? Qt.darker(Colors.primary_container, 1.6) : Colors.primary_container
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                    GradientStop {
                        position: 1.0
                        color: root.muted ? Qt.darker(Colors.tertiary, 1.6)
                            : (root.overAmp ? Colors.error : Colors.tertiary)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }
                Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }
        }
    }

    Item {
        id: trackRow
        anchors.fill: parent
        opacity: root.kind === "track" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        ClippingRectangle {
            id: coverBox
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 44 * root.s
            height: 44 * root.s
            radius: 9 * root.s
            color: Colors.surface_container_low

            Image {
                id: cover
                anchors.fill: parent
                source: root.liveArt
                sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: String(source).indexOf("file:") !== 0
                opacity: status === Image.Ready ? 1 : 0
                /** Art that arrives late still earns a moment on screen, so a cover
                 *  decoded near the end of the flash is actually seen. */
                onStatusChanged: if (status === Image.Ready && root.flashing && root.kind === "track") {
                    hideTimer.interval = 1300;
                    hideTimer.restart();
                }
            }
            GlyphIcon {
                anchors.centerIn: parent
                width: parent.width * 0.42
                height: width
                name: "music"
                color: Colors.on_surface_variant
                visible: cover.status !== Image.Ready
            }

            /** The source's own app icon, sat as a small badge on the art corner. */
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 3 * root.s
                width: 18 * root.s
                height: 18 * root.s
                radius: width / 2
                color: Qt.alpha(Colors.surface_container, 0.8)
                visible: srcIcon.status === Image.Ready

                Image {
                    id: srcIcon
                    anchors.centerIn: parent
                    width: 12 * root.s
                    height: 12 * root.s
                    sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    source: root.subjectIcon
                }
            }
        }

        /**
         * Play state as the media surface's seal: a tonal square carrying
         * 奏 (playing) / 休 (paused), or the play/pause glyph with kanji off.
         * Playing fills primary_container; paused drops to a quiet tonal.
         */
        Rectangle {
            id: trackCtrl
            anchors.right: parent.right
            anchors.rightMargin: 2 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 32 * root.s
            height: 32 * root.s
            radius: (root.subjectPlaying ? 9 : 16) * root.s
            rotation: -1.5
            color: root.subjectPlaying ? Colors.primary_container : Colors.surface_container_high
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on radius {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            readonly property color ink: root.subjectPlaying ? Colors.on_primary_container : Colors.on_surface_variant

            Text {
                anchors.centerIn: parent
                visible: Flags.showGlyphs
                text: root.subjectPlaying ? "奏" : "休"
                color: trackCtrl.ink
                font.family: Appearance.font.jp
                font.pixelSize: 16 * root.s
                font.weight: Font.DemiBold
            }
            GlyphIcon {
                anchors.centerIn: parent
                visible: !Flags.showGlyphs
                width: 14 * root.s
                height: 14 * root.s
                name: root.subjectPlaying ? "play" : "pause"
                color: trackCtrl.ink
            }
        }

        Column {
            anchors.left: coverBox.right
            anchors.leftMargin: 12 * root.s
            anchors.right: trackCtrl.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3 * root.s

            Text {
                width: parent.width
                text: root.subjectHas ? root.subjectTitle : "Nothing playing"
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 14 * root.s
                font.weight: Font.DemiBold
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.subjectArtist
                color: Qt.alpha(Colors.on_surface_variant, 0.8)
                font.family: Appearance.font.family
                font.pixelSize: 11 * root.s
                maximumLineCount: 1
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }
    }

    Item {
        id: brightRow
        anchors.fill: parent
        opacity: root.kind === "brightness" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        GlyphIcon {
            id: brightGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s
            name: "sun"
            color: Colors.on_surface_variant
            stroke: 1.7
        }

        Text {
            id: brightPct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 32 * root.s
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.brightness * 100) + "%"
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }

        Rectangle {
            anchors.left: brightGlyph.right
            anchors.leftMargin: 12 * root.s
            anchors.right: brightPct.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            height: 4 * root.s
            radius: 2 * root.s
            color: Qt.alpha(Colors.on_surface, 0.13)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * root.brightness
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Colors.primary_container }
                    GradientStop { position: 1.0; color: Colors.tertiary }
                }
                Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }
        }
    }

    Item {
        id: batteryRow
        anchors.fill: parent
        opacity: root.kind === "battery" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        Text {
            id: battGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            horizontalAlignment: Text.AlignHCenter
            text: !Battery.discharging ? "充" : "電"
            color: Battery.low ? Colors.error : Colors.tertiary
            font.family: Appearance.font.jp
            font.weight: Font.Bold
            font.pixelSize: 15 * root.s
        }

        Text {
            id: battPct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40 * root.s
            horizontalAlignment: Text.AlignRight
            text: Battery.pct + "%"
            color: Battery.low ? Colors.error : Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }

        Rectangle {
            anchors.left: battGlyph.right
            anchors.leftMargin: 12 * root.s
            anchors.right: battPct.left
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            height: 4 * root.s
            radius: 2 * root.s
            color: Qt.alpha(Colors.on_surface, 0.13)
            clip: true

            Rectangle {
                id: battFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Battery.frac
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Colors.primary_container }
                    GradientStop { position: 1.0; color: Colors.tertiary }
                }
                Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                // Plugged-in shimmer sweep (Ricelin's warm-white stops, rebuilt
                // on the tertiary glow family so a matugen retheme carries it).
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 34 * root.s
                    color: "transparent"
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.alpha(Qt.lighter(Colors.tertiary, 1.6), 0) }
                        GradientStop { position: 0.5; color: Qt.alpha(Qt.lighter(Colors.tertiary, 1.6), 0.35) }
                        GradientStop { position: 1.0; color: Qt.alpha(Qt.lighter(Colors.tertiary, 1.6), 0) }
                    }

                    NumberAnimation on x {
                        from: -34 * root.s
                        to: battFill.width
                        duration: 1200 * Motion.mult
                        loops: Animation.Infinite
                        running: root.kind === "battery" && !Battery.discharging && !Motion.reduceMotion
                    }
                }
            }
        }
    }

    Item {
        id: workspaceRow
        anchors.fill: parent
        opacity: root.kind === "workspace" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        Workspaces {
            id: wsIndicator
            anchors.centerIn: parent
            screenName: root.screenName
            s: root.s
            gap: 8 * root.s
            enabled: false
        }
    }

    Item {
        id: micRow
        anchors.fill: parent
        opacity: root.kind === "mic" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        GlyphIcon {
            id: micGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s
            name: root.micMuted ? "mic-off" : "mic"
            color: root.micMuted ? Qt.alpha(Colors.on_surface_variant, 0.8) : Colors.primary
            stroke: 1.7
        }

        Text {
            anchors.left: micGlyph.right
            anchors.leftMargin: 13 * root.s
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.micMuted ? "Microphone muted" : "Microphone live"
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 11.5 * root.s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    Item {
        id: cameraRow
        anchors.fill: parent
        opacity: root.kind === "camera" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        GlyphIcon {
            id: camGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s
            name: "video"
            color: root.cameraOn ? Colors.primary : Qt.alpha(Colors.on_surface_variant, 0.8)
            stroke: 1.7
        }

        // No baked video-off glyph; a diagonal strike over the dimmed camera
        // glyph reads as "off", mirroring mic-off's slash.
        Rectangle {
            anchors.centerIn: camGlyph
            width: 20 * root.s
            height: 1.7
            radius: height / 2
            rotation: 45
            color: Qt.alpha(Colors.on_surface_variant, 0.8)
            visible: !root.cameraOn
        }

        Text {
            anchors.left: camGlyph.right
            anchors.leftMargin: 13 * root.s
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.cameraOn ? "Camera on" : "Camera off"
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 11.5 * root.s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    /**
     * Record row, styled like the recorder surface's running take: an error
     * dot with a ripple and a REC badge while live; a squared-off stop mark
     * and the saved file's name once the take closes; the error tone if the
     * recorder died on its way out.
     */
    Item {
        id: recordRow
        anchors.fill: parent
        opacity: root.kind === "record" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        readonly property bool failed: !root.recordStarted && ScreenRec.error.length > 0
        readonly property bool live: root.recordStarted && root.kind === "record"

        Item {
            id: recGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 28 * root.s
            height: width

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.recordStarted || recordRow.failed ? Qt.alpha(Colors.error, 0.18) : Colors.surface_container_high
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Rectangle {
                id: recHalo
                anchors.centerIn: parent
                width: parent.width
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1.5 * root.s
                border.color: Colors.error
                opacity: 0
                ParallelAnimation {
                    running: recordRow.live && root.flashing && !Motion.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation {
                        target: recHalo; property: "scale"; from: 0.4; to: 1.1
                        duration: Motion.pulse * 3
                        easing.type: Motion.easeBezier; easing.bezierCurve: Motion.emphasizedDecel
                    }
                    NumberAnimation {
                        target: recHalo; property: "opacity"; from: 0.7; to: 0
                        duration: Motion.pulse * 3
                        easing.type: Motion.easeBezier; easing.bezierCurve: Motion.emphasizedDecel
                    }
                }
            }

            // Live: a round dot. Stopped: it squares off into the stop mark.
            Rectangle {
                anchors.centerIn: parent
                width: (root.recordStarted ? 11 : 9) * root.s
                height: width
                radius: root.recordStarted ? width / 2 : 2.5 * root.s
                color: root.recordStarted || recordRow.failed ? Colors.error : Colors.on_surface_variant
                Behavior on radius { NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial } }
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        Column {
            anchors.left: recGlyph.right
            anchors.leftMargin: 11 * root.s
            anchors.right: recBadge.visible ? recBadge.left : parent.right
            anchors.rightMargin: recBadge.visible ? 10 * root.s : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * root.s

            Text {
                width: parent.width
                text: root.recordStarted ? "Recording"
                    : (recordRow.failed ? "Recording failed" : "Recording saved")
                color: recordRow.failed ? Colors.error : Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 12 * root.s
                font.weight: Font.Bold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                width: parent.width
                visible: text.length > 0
                text: root.recordStarted
                    ? (ScreenRec.source + (ScreenRec.cap.fps ? " · " + Flags.recordFps + " fps" : ""))
                    : (recordRow.failed ? ScreenRec.error
                    : (ScreenRec.lastFile.length > 0 ? ScreenRec.baseName(ScreenRec.lastFile) : ""))
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
                font.capitalization: root.recordStarted ? Font.AllUppercase : Font.MixedCase
                font.letterSpacing: root.recordStarted ? 0.8 * root.s : 0
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }

        Rectangle {
            id: recBadge
            visible: root.recordStarted
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: recBadgeText.implicitWidth + 16 * root.s
            height: 20 * root.s
            radius: height / 2
            color: Colors.error

            Text {
                id: recBadgeText
                anchors.centerIn: parent
                text: "REC"
                color: Colors.on_error
                font.family: Appearance.font.family
                font.pixelSize: 9 * root.s
                font.weight: Font.ExtraBold
                font.letterSpacing: 1 * root.s
            }
        }
    }
}
