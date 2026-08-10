pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import "../colors"
import "../services"
import "../config"
import "../pill"

/**
 * astralis — lockscreen surface content (one per screen).
 *
 * Composition (a calm, deliberate surface built on the matugen palette):
 *  - background: the live wallpaper (Wallpaper.current) under a MultiEffect
 *    blur, a gentle top/bottom-weighted scrim (the middle stays legible, not a
 *    heavy dim), a soft side vignette, and a low primary-tinted radial lift
 *    behind the clock so numerals always have depth over any wallpaper. Falls
 *    back to the surface color when no wallpaper has ever been set.
 *  - date + 鎖 LOCKED, top-left, refined to on_surface_variant scale.
 *  - clock centered: a light, tracked numeral pair with a tinted, slowly
 *    breathing colon (a tasteful stand-in for seconds) — presence without bulk.
 *  - now-playing, bottom-left: a real card (rounded ring'd art, 2-line
 *    title/artist, understated 前/奏(休)/次 transport, a thin progress thread
 *    ONLY for a trustworthy timeline). Hidden cleanly when nothing plays.
 *  - identity (人 <user>) + password capsule, bottom-center. Every screen
 *    carries the capsule so keyboard focus always lands in a live TextInput,
 *    but only the main screen shows it (opacity 0 elsewhere); text is mirrored
 *    across screens through ctx.passBuf. The obscured input is drawn as an even
 *    row of dots (not the raw echo), with an understated focus ring, a graceful
 *    verifying loader, and an error state (border + shake).
 *
 * `ctx` is the lock scope (lock/Lock.qml) — or a stub in a harness. Contract:
 * passBuf (string), authenticating (bool), lastError (string), submit(pw),
 * signals failed()/succeeded().
 */
Item {
    id: surface

    property real s: 1
    property var ctx: null
    property string screenName: ""

    /**
     * The auth panel lands on one deterministic monitor: the first screen
     * Quickshell reports (Ricelin's isMain rule — no hardcoded output name).
     */
    readonly property bool isMain: {
        var scr = Quickshell.screens;
        if (scr.length === 0)
            return true;
        return surface.screenName === scr[0].name;
    }

    readonly property bool busy: ctx ? ctx.authenticating : false
    property bool showError: false
    /** Caps-Lock state, inferred from the last letter typed (see input Keys). */
    property bool capsLock: false
    property var np: Players

    /** Motion gate: only the main screen animates loops; reduce-motion silences them. */
    readonly property bool animate: surface.isMain && !Flags.reduceMotion

    /** Subtle greeting above the capsule; ctx (lock scope) carries the user. */
    readonly property string userName: (ctx && ctx.currentUser) ? ctx.currentUser : ""

    /** Entrance latch: content fades/rises in on the first frame after lock. */
    property bool ready: false
    Component.onCompleted: Qt.callLater(() => surface.ready = true)

    Connections {
        target: surface.ctx
        enabled: surface.ctx !== null
        function onFailed() {
            surface.showError = true;
            shake.restart();
        }
        function onSucceeded() {
            surface.showError = false;
        }
    }

    // ── now-playing model (Players singleton, same reads as the media pill) ─
    readonly property bool hasMedia: np.has
        && (np.playing || (np.active && np.active.trackTitle.length > 0))
    readonly property string artSrc: {
        if (!surface.hasMedia)
            return "";
        var u = np.artUrl;
        if (!u || u.length === 0)
            return "";
        // Locked session: never initiate a network fetch. Only LOCAL art
        // (file:/data:) is honoured; a remote http(s) cover falls back to the
        // placeholder glyph so nothing leaves the box while locked.
        if (u.indexOf("file:") !== 0 && u.indexOf("data:") !== 0)
            return "";
        // Key file art on the track so a player reusing one path still reloads.
        return u.indexOf("file:") === 0 ? u + "#" + np.trackKey : u;
    }
    // Players exposes position/length already in SECONDS (Quickshell converts
    // the MPRIS µs D-Bus values internally) — no /1e6 here. Browser/stream
    // players still report a stale position past length; a timeline is only
    // trustworthy when it is finite, positive, and position sits inside it.
    readonly property real posSec: np.position
    readonly property real lenSec: np.length
    readonly property bool hasTimeline: !np.live && surface.lenSec > 0
        && surface.posSec >= 0 && surface.posSec <= surface.lenSec + 2
    readonly property real playFrac: surface.hasTimeline
        ? Math.max(0, Math.min(1, surface.posSec / surface.lenSec)) : 0

    // mm:ss, promoting to h:mm:ss past the hour; guards NaN/≤0 → 0:00.
    function fmt(sec) {
        if (!(sec > 0))
            return "0:00";
        var t = Math.floor(sec);
        var h = Math.floor(t / 3600);
        var m = Math.floor((t % 3600) / 60);
        var s2 = t % 60;
        var ss = s2 < 10 ? "0" + s2 : "" + s2;
        if (h > 0)
            return h + ":" + (m < 10 ? "0" + m : "" + m) + ":" + ss;
        return m + ":" + ss;
    }

    // MPRIS position only ticks when polled; nudge it while visible + playing.
    Timer {
        interval: 1000
        running: surface.visible && surface.isMain && np.playing
        repeat: true
        onTriggered: if (np.active) np.active.positionChanged()
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Clock parts, split so the colon can carry an accent tint and the minutes
    // read a touch quieter than the hour (hierarchy inside one glyph pair).
    readonly property string hourStr: Qt.formatDateTime(clock.date, Flags.time12h ? "h" : "HH")
    readonly property string minStr: Qt.formatDateTime(clock.date, "mm")

    /** Small kanji transport button (media surface's 前/次 language). */
    component KanjiButton: Item {
        id: kb
        property bool can: false
        property string glyph: ""
        property real size: 13
        signal activated()

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: kbLabel.implicitWidth
        implicitHeight: kbLabel.implicitHeight
        opacity: kb.can ? 1 : 0.3
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        Text {
            id: kbLabel
            anchors.centerIn: parent
            text: kb.glyph
            font.family: Appearance.font.jp
            font.pixelSize: kb.size * surface.s
            color: kbArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        MouseArea {
            id: kbArea
            anchors.fill: parent
            anchors.margins: -6 * surface.s
            hoverEnabled: true
            enabled: kb.can
            cursorShape: Qt.PointingHandCursor
            onClicked: kb.activated()
        }
    }

    // ── background: wallpaper → blur → scrim → vignette → clock lift ─────────
    Rectangle {
        anchors.fill: parent
        color: Colors.surface_container_lowest
    }

    Image {
        id: wallSrc
        anchors.fill: parent
        source: Wallpaper.current.length > 0
            ? "file://" + encodeURI(Wallpaper.current).replace(/#/g, '%23').replace(/\?/g, '%3F')
            : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        cache: false
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallSrc
        visible: wallSrc.status === Image.Ready
        blurEnabled: true
        blur: 0.62
        blurMax: 48
        autoPaddingEnabled: false
    }

    // Base scrim — weighted to the top (date) and bottom (capsule/media) bands
    // so the text zones stay legible while the wallpaper breathes through the
    // middle. Deliberately gentler than a flat dim.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.alpha(Colors.scrim, 0.58) }
            GradientStop { position: 0.30; color: Qt.alpha(Colors.scrim, 0.24) }
            GradientStop { position: 0.60; color: Qt.alpha(Colors.scrim, 0.22) }
            GradientStop { position: 1.0;  color: Qt.alpha(Colors.scrim, 0.66) }
        }
    }

    // Side vignette — a soft horizontal darkening so the corners settle and the
    // eye is drawn to the centre. Clear through the middle.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: Qt.alpha(Colors.scrim, 0.34) }
            GradientStop { position: 0.22; color: "transparent" }
            GradientStop { position: 0.78; color: "transparent" }
            GradientStop { position: 1.0;  color: Qt.alpha(Colors.scrim, 0.30) }
        }
    }

    // Soft primary-tinted radial lift behind the clock. A small bright disc is
    // heavily blurred inside a much larger transparent frame, so its edges fade
    // to nothing — a real halo, not a panel. No external gradient dependency.
    Item {
        id: clockGlow
        width: 940 * surface.s
        height: 540 * surface.s
        x: surface.width / 2 - width / 2
        y: surface.height * 0.24 + 92 * surface.s - height / 2
        opacity: surface.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.largeDur } }

        Item {
            id: glowSrc
            anchors.fill: parent
            visible: false
            Rectangle {
                anchors.centerIn: parent
                width: 340 * surface.s
                height: 210 * surface.s
                radius: height / 2
                color: Qt.alpha(Colors.primary, 0.16)
            }
        }
        MultiEffect {
            anchors.fill: glowSrc
            source: glowSrc
            blurEnabled: true
            blur: 1
            blurMax: 64
            autoPaddingEnabled: false
            // A slow, restrained breath so the surface feels alive (gated off
            // on non-main screens and under reduce-motion).
            SequentialAnimation on opacity {
                running: surface.animate
                loops: Animation.Infinite
                NumberAnimation { to: 0.68; duration: Math.round(2800 * Motion.mult); easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;  duration: Math.round(2800 * Motion.mult); easing.type: Easing.InOutSine }
            }
        }
    }

    // Click anywhere refocuses the password field (it can lose focus to nothing).
    MouseArea {
        anchors.fill: parent
        onPressed: input.forceActiveFocus()
    }

    // ── content (entrance fade + rise) ──────────────────────────────────────
    Item {
        id: content
        anchors.fill: parent

        opacity: surface.ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Motion.largeDur; easing.type: Motion.easeStandard }
        }
        transform: Translate {
            y: surface.ready ? 0 : 18 * surface.s
            Behavior on y {
                NumberAnimation {
                    duration: Motion.expressiveDefaultSpatialDur
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveDefaultSpatial
                }
            }
        }

        // ── date + lock badge, top-centre ───────────────────────────────────
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.066
            spacing: 9 * surface.s

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.locale().toString(clock.date, "dddd") + "  ·  "
                    + Qt.locale().toString(clock.date, "d MMMM")
                color: Colors.on_surface
                opacity: 0.9
                font.family: Appearance.font.family
                font.weight: Font.DemiBold
                font.pixelSize: 19 * surface.s
                font.letterSpacing: 4 * surface.s
                font.capitalization: Font.AllUppercase
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.4)
                    shadowBlur: 0.6
                    shadowVerticalOffset: 1
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8 * surface.s
                Text {
                    visible: Flags.showGlyphs
                    anchors.verticalCenter: parent.verticalCenter
                    text: "鎖"
                    color: Qt.alpha(Colors.primary, 0.85)
                    font.family: Appearance.font.jp
                    font.pixelSize: 11 * surface.s
                }
                Rectangle {
                    visible: Flags.showGlyphs
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 10 * surface.s
                    color: Qt.alpha(Colors.on_surface, 0.22)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "LOCKED"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.weight: Font.Medium
                    font.pixelSize: 9.5 * surface.s
                    font.letterSpacing: 3.5 * surface.s
                }
            }
        }

        // ── clock, centered ─────────────────────────────────────────────────
        Row {
            id: clockRow
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.24

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.42)
                shadowBlur: 0.9
                shadowVerticalOffset: 2
            }

            Text {
                id: hourText
                text: surface.hourStr
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.weight: Font.Light
                font.pixelSize: 150 * surface.s
                font.letterSpacing: -1 * surface.s
            }
            // Hand-drawn accent colon — two evenly-gapped dots, optically
            // centred against the numerals, breathing slowly as a tasteful
            // stand-in for ticking seconds.
            Item {
                id: colon
                width: 40 * surface.s
                height: hourText.implicitHeight
                Column {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -9 * surface.s
                    spacing: 21 * surface.s
                    opacity: 1
                    SequentialAnimation on opacity {
                        running: surface.animate
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.4; duration: Math.round(1400 * Motion.mult); easing.type: Easing.InOutSine }
                        PauseAnimation { duration: Math.round(140 * Motion.mult) }
                        NumberAnimation { to: 1.0; duration: Math.round(1400 * Motion.mult); easing.type: Easing.InOutSine }
                        PauseAnimation { duration: Math.round(320 * Motion.mult) }
                    }
                    Rectangle {
                        width: 13 * surface.s; height: 13 * surface.s; radius: width / 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Colors.primary
                    }
                    Rectangle {
                        width: 13 * surface.s; height: 13 * surface.s; radius: width / 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Colors.primary
                    }
                }
            }
            Text {
                text: surface.minStr
                color: Qt.alpha(Colors.on_surface, 0.7)
                font.family: Appearance.font.family
                font.weight: Font.Light
                font.pixelSize: 150 * surface.s
                font.letterSpacing: -1 * surface.s
            }
        }

        // ── now-playing card, bottom-left (main screen only) ────────────────
        Item {
            id: mediaPanel
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: parent.width * 0.052
            // Grounded on the same baseline as the password capsule so the
            // bottom band (now-playing left · capsule centre) reads as one row.
            anchors.bottomMargin: parent.height * 0.10
            width: card.width
            height: card.height

            visible: opacity > 0.01
            opacity: surface.isMain && surface.hasMedia ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }

            // Chrome-less: the now-playing floats on the wallpaper like the rest
            // of the lock (no card box) so it doesn't stand out; the text carries
            // its own legibility shadow instead.
            Rectangle {
                id: card
                width: 344 * surface.s
                height: cardCol.implicitHeight + 26 * surface.s
                color: "transparent"

                Column {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: 13 * surface.s
                    spacing: 13 * surface.s

                    Row {
                        spacing: 13 * surface.s
                        width: parent.width

                        // album art — rounded, with a hairline ring + inner tile
                        Item {
                            width: 58 * surface.s
                            height: 58 * surface.s
                            anchors.verticalCenter: parent.verticalCenter

                            ClippingRectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.medium * surface.s
                                color: Qt.alpha(Colors.surface_container_highest, 0.9)

                                Image {
                                    anchors.fill: parent
                                    source: surface.artSrc
                                    sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    retainWhileLoading: true
                                    cache: String(source).indexOf("file:") !== 0
                                    visible: status === Image.Ready
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: surface.artSrc.length === 0
                                    text: "音"
                                    color: Qt.alpha(Colors.primary, 0.75)
                                    font.family: Appearance.font.jp
                                    font.pixelSize: 24 * surface.s
                                }
                            }
                            // ring
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.medium * surface.s
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.alpha(Colors.on_surface, 0.12)
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 58 * surface.s - 13 * surface.s
                            spacing: 3 * surface.s

                            Text {
                                width: parent.width
                                text: np.title
                                color: Colors.on_surface
                                font.family: Appearance.font.family
                                font.pixelSize: 13.5 * surface.s
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: Qt.rgba(0, 0, 0, 0.55)
                                    shadowBlur: 0.7
                                    shadowVerticalOffset: 1
                                }
                            }
                            Text {
                                width: parent.width
                                visible: np.artist.length > 0
                                text: np.artist
                                color: Colors.on_surface_variant
                                font.family: Appearance.font.family
                                font.pixelSize: 11 * surface.s
                                elide: Text.ElideRight
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: Qt.rgba(0, 0, 0, 0.55)
                                    shadowBlur: 0.7
                                    shadowVerticalOffset: 1
                                }
                            }

                            Row {
                                topPadding: 4 * surface.s
                                spacing: 15 * surface.s
                                height: 24 * surface.s

                                KanjiButton {
                                    glyph: "前"
                                    size: 13
                                    can: np.canPrevious
                                    onActivated: np.previous()
                                }

                                // play/pause seal: 奏 while playing, 休 paused
                                Rectangle {
                                    id: seal
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 24 * surface.s
                                    height: 24 * surface.s
                                    radius: Motion.rSmall * surface.s
                                    color: Qt.alpha(Colors.primary, np.playing ? 0.28 : 0.12)
                                    border.width: 1
                                    border.color: Qt.alpha(Colors.primary, sealArea.containsMouse ? 0.75 : 0.4)
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: np.playing ? "奏" : "休"
                                        color: Colors.on_surface
                                        font.family: Appearance.font.jp
                                        font.pixelSize: 12.5 * surface.s
                                        font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        id: sealArea
                                        anchors.fill: parent
                                        anchors.margins: -4 * surface.s
                                        hoverEnabled: true
                                        enabled: surface.hasMedia
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: np.togglePlaying()
                                    }
                                }

                                KanjiButton {
                                    glyph: "次"
                                    size: 13
                                    can: np.canNext
                                    onActivated: np.next()
                                }
                            }
                        }
                    }

                    // progress — the Media surface's waveform: a static damped-
                    // sine outline (outline_variant) with the played span filled
                    // by a tapered primary head that the Ame seam bead rides.
                    // Display-only here (no seek while locked). Real timeline only.
                    Item {
                        id: waveRow
                        width: parent.width
                        height: 18 * surface.s
                        visible: surface.hasTimeline

                        Text {
                            id: elapsed
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            text: surface.fmt(surface.posSec)
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * surface.s
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            id: total
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            text: surface.fmt(surface.lenSec)
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * surface.s
                            font.features: ({ "tnum": 1 })
                        }

                        // static waveform outline — repainted only on resize /
                        // theme change, never per playhead frame.
                        Canvas {
                            id: baseWave
                            anchors.left: elapsed.right
                            anchors.right: total.left
                            anchors.leftMargin: 10 * surface.s
                            anchors.rightMargin: 10 * surface.s
                            anchors.verticalCenter: parent.verticalCenter
                            height: 16 * surface.s

                            readonly property color tint: Colors.outline_variant
                            onTintChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onVisibleChanged: if (visible) requestPaint()

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                if (width <= 0 || height <= 0)
                                    return;
                                const n = 48;
                                const inset = wave.inset;
                                const usable = wave.usable;
                                ctx.strokeStyle = Qt.alpha(baseWave.tint, 0.6);
                                ctx.lineWidth = 2.5 * surface.s;
                                ctx.lineCap = "round";
                                ctx.lineJoin = "round";
                                ctx.beginPath();
                                ctx.moveTo(inset, wave.waveY(0));
                                for (let i = 1; i <= n; i++)
                                    ctx.lineTo(inset + (i / n) * usable, wave.waveY(i / n));
                                ctx.stroke();
                            }
                        }

                        // moving primary head — the only canvas repainted per
                        // frame; drives the Ame seam bead via headX/headY.
                        Canvas {
                            id: wave
                            anchors.fill: baseWave

                            readonly property real inset: 3 * surface.s
                            readonly property real usable: Math.max(1, width - 2 * inset)
                            property real targetF: surface.playFrac
                            property real lastFrac: 0
                            property real drawF: targetF
                            readonly property real headX: inset + drawF * usable
                            readonly property real headY: waveY(drawF)

                            Behavior on drawF {
                                enabled: Math.abs(surface.playFrac - wave.lastFrac) < 0.02 && !Flags.reduceMotion
                                NumberAnimation { duration: Math.round(500 * Motion.mult); easing.type: Easing.Linear }
                            }
                            onTargetFChanged: Qt.callLater(() => { wave.lastFrac = surface.playFrac; })
                            onDrawFChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onVisibleChanged: if (visible) requestPaint()

                            function waveY(u) {
                                return height / 2 - 2.6 * Math.sin(3 * Math.PI * u) * Math.exp(-2.5 * u) * surface.s;
                            }

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                if (width <= 0 || height <= 0)
                                    return;
                                if (drawF <= 0.002)
                                    return;
                                const n = 48;
                                const hTail = 2.5 * surface.s;
                                const hHead = 1.75 * surface.s;
                                const m = Math.max(2, Math.ceil(n * drawF));
                                ctx.fillStyle = Colors.primary;
                                ctx.beginPath();
                                ctx.arc(inset, waveY(0), hTail, Math.PI / 2, 3 * Math.PI / 2);
                                for (let i = 0; i <= m; i++) {
                                    const u = (i / m) * drawF;
                                    ctx.lineTo(inset + u * usable, waveY(u) - (hTail + (hHead - hTail) * (i / m)));
                                }
                                ctx.arc(headX, headY, hHead, -Math.PI / 2, Math.PI / 2);
                                for (let i = m; i >= 0; i--) {
                                    const u = (i / m) * drawF;
                                    ctx.lineTo(inset + u * usable, waveY(u) + (hTail + (hHead - hTail) * (i / m)));
                                }
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                    }

                    // "live" chip for endless streams (no trustworthy timeline).
                    Row {
                        visible: np.live && surface.hasMedia
                        spacing: 6 * surface.s
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6 * surface.s
                            height: 6 * surface.s
                            radius: width / 2
                            color: Colors.error
                        }
                        Text {
                            text: "LIVE"
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * surface.s
                            font.weight: Font.DemiBold
                            font.letterSpacing: 2 * surface.s
                        }
                    }
                }
            }
        }

        // ── identity prompt above the capsule ───────────────────────────────
        Row {
            id: prompt
            anchors.horizontalCenter: capsule.horizontalCenter
            anchors.bottom: capsule.top
            anchors.bottomMargin: 20 * surface.s
            spacing: 8 * surface.s
            opacity: surface.isMain ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            Text {
                visible: Flags.showGlyphs
                anchors.verticalCenter: parent.verticalCenter
                text: "人"
                color: Qt.alpha(Colors.primary, 0.8)
                font.family: Appearance.font.jp
                font.pixelSize: 13 * surface.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: surface.userName.length > 0 ? surface.userName : "welcome back"
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 12.5 * surface.s
                font.weight: Font.Medium
                font.letterSpacing: 1.5 * surface.s
            }
        }

        // ── password capsule, bottom-center ─────────────────────────────────
        // Present (and focused) on EVERY screen so typing always lands
        // somewhere live; visible only on the main one.
        Rectangle {
            id: capsule
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.10
            width: 300 * surface.s
            height: 62 * surface.s
            radius: height / 2
            color: Qt.alpha(Colors.surface_container_high, 0.62)
            border.width: 1
            border.color: surface.showError
                ? Qt.alpha(Colors.error, 0.85)
                : (input.activeFocus ? Qt.alpha(Colors.primary, 0.65)
                                     : Qt.alpha(Colors.outline_variant, 0.7))
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            // focus ring — a single, understated accent halo just outside the edge
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4 * surface.s
                radius: height / 2
                color: "transparent"
                border.width: 1.5 * surface.s
                border.color: Qt.alpha(surface.showError ? Colors.error : Colors.primary, 0.28)
                opacity: (input.activeFocus || surface.showError) && !surface.busy ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                z: -1
            }

            opacity: surface.isMain ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            transform: Translate { id: capsuleShift }

            // failure shake (Motion.mult keeps it reduce-motion-safe)
            SequentialAnimation {
                id: shake
                NumberAnimation { target: capsuleShift; property: "x"; to: 9 * surface.s; duration: Math.round(50 * Motion.mult) }
                NumberAnimation { target: capsuleShift; property: "x"; to: -9 * surface.s; duration: Math.round(50 * Motion.mult) }
                NumberAnimation { target: capsuleShift; property: "x"; to: 6 * surface.s; duration: Math.round(50 * Motion.mult) }
                NumberAnimation { target: capsuleShift; property: "x"; to: -6 * surface.s; duration: Math.round(50 * Motion.mult) }
                NumberAnimation { target: capsuleShift; property: "x"; to: 0; duration: Math.round(50 * Motion.mult) }
            }

            // The functional input — kept fully live (obscured echo, enter-to-
            // submit, passBuf mirror) but visually silent; the dot row below is
            // the visible obscured representation.
            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 30 * surface.s
                anchors.rightMargin: 30 * surface.s
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "•"
                color: "transparent"
                selectionColor: "transparent"
                selectedTextColor: "transparent"
                font.pixelSize: 1
                clip: true
                focus: true
                enabled: !surface.busy
                cursorVisible: false

                // Infer Caps-Lock from the produced character: a letter that
                // comes out uppercase without Shift (or lowercase with Shift)
                // means Caps is on. QtQuick exposes no direct lock state, and
                // this is exactly the moment it matters for a password.
                Keys.onPressed: event => {
                    var t = event.text;
                    if (t.length === 1 && t.toLowerCase() !== t.toUpperCase()) {
                        var shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        var upper = (t === t.toUpperCase());
                        surface.capsLock = (upper !== shift);
                    }
                }

                onTextChanged: {
                    if (text.length > 0)
                        surface.showError = false;
                    if (surface.ctx && surface.ctx.passBuf !== text)
                        surface.ctx.passBuf = text;
                }
                Connections {
                    target: surface.ctx
                    enabled: surface.ctx !== null
                    function onPassBufChanged() {
                        if (input.text !== surface.ctx.passBuf)
                            input.text = surface.ctx.passBuf;
                    }
                }
                onAccepted: {
                    if (surface.ctx && text.length > 0 && !surface.busy)
                        surface.ctx.submit(text);
                }
            }

            // obscured input — a CONSTANT pool of 20 dots, built once and never
            // rebuilt (any change to a Repeater/ListView model COUNT re-creates
            // every delegate — that was the reload/blink). Each dot is driven by
            // whether its index is within the typed length, so a keypress flips
            // exactly ONE dot's `shown`; only that one animates in, the rest just
            // glide (Behavior on x) to keep the group centred. A plain, simple dot.
            Item {
                id: dotField
                anchors.centerIn: parent
                width: parent.width
                height: 10 * surface.s
                visible: input.text.length > 0 && !surface.busy
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                readonly property int count: Math.min(input.text.length, 20)
                readonly property real pitch: 13 * surface.s

                Repeater {
                    model: 20   // constant — never re-instantiates the delegates
                    delegate: Item {
                        id: dot
                        required property int index
                        width: 8 * surface.s
                        height: 8 * surface.s
                        visible: dot.a > 0.001

                        // this dot is part of the password iff its index is within
                        // the typed length; typing/deleting flips exactly one.
                        readonly property bool shown: dot.index < dotField.count

                        // Centred slot; when `count` changes each remaining dot's
                        // slot shifts, so its x re-targets and glides — the group
                        // re-centres smoothly, no jump.
                        readonly property real slot: dot.index - (dotField.count - 1) / 2
                        x: dotField.width / 2 + slot * dotField.pitch - width / 2
                        y: (dotField.height - height) / 2
                        Behavior on x {
                            NumberAnimation { duration: Motion.standard; easing.type: Easing.OutCubic }
                        }

                        // a: 0→1 appear — a simple fade + gentle grow, run ONCE
                        // when this dot first shows; fades out on delete.
                        property real a: 0
                        opacity: a
                        scale: 0.4 + 0.6 * a
                        Component.onCompleted: if (dot.shown) dot.a = 1
                        onShownChanged: {
                            if (dot.shown) {
                                if (Flags.reduceMotion) dot.a = 1;
                                else appearAnim.restart();
                            } else {
                                appearAnim.stop();
                                fadeAnim.restart();
                            }
                        }
                        NumberAnimation {
                            id: appearAnim
                            target: dot; property: "a"; from: 0; to: 1
                            duration: Motion.standard; easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            id: fadeAnim
                            target: dot; property: "a"; to: 0; duration: Motion.fast
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Qt.alpha(Colors.on_surface, 0.9)
                        }
                    }
                }
            }

            // placeholder / error message — shown only when the field is empty
            Text {
                anchors.centerIn: parent
                visible: input.text.length === 0 && !surface.busy
                text: {
                    if (!surface.showError)
                        return "enter password";
                    var msg = surface.ctx ? surface.ctx.lastError : "";
                    return msg.length > 0 ? msg.toLowerCase() : "wrong password";
                }
                color: surface.showError ? Colors.error : Qt.alpha(Colors.on_surface_variant, 0.85)
                font.family: Appearance.font.family
                font.pixelSize: 13 * surface.s
                font.letterSpacing: 1.5 * surface.s
            }

            // verifying — an animated 3-dot loader (or a static word under
            // reduce-motion), so the wait reads as considered, not frozen.
            Item {
                anchors.centerIn: parent
                width: 40 * surface.s
                height: 12 * surface.s
                visible: surface.busy

                Row {
                    anchors.centerIn: parent
                    spacing: 7 * surface.s
                    visible: !Flags.reduceMotion
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 7 * surface.s
                            height: 7 * surface.s
                            radius: width / 2
                            color: Colors.primary
                            SequentialAnimation on opacity {
                                running: surface.busy && !Flags.reduceMotion
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * Math.round(150 * Motion.mult) }
                                NumberAnimation { to: 1.0; duration: Math.round(300 * Motion.mult); easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0.3; duration: Math.round(300 * Motion.mult); easing.type: Easing.InOutSine }
                                PauseAnimation { duration: (2 - index) * Math.round(150 * Motion.mult) }
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: Flags.reduceMotion
                    text: "verifying"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 13 * surface.s
                    font.letterSpacing: 1.5 * surface.s
                }
            }

            // submit affordance — a quiet return-key hint beside the capsule
            // that appears once a password is being typed, so Enter reads as the
            // way to unlock. Sits OUTSIDE the field so it never crowds the dots.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.right
                anchors.leftMargin: 14 * surface.s
                spacing: 6 * surface.s
                visible: input.text.length > 0 && !surface.busy
                opacity: visible ? 0.7 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "enter"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 9.5 * surface.s
                    font.letterSpacing: 2 * surface.s
                    font.capitalization: Font.AllUppercase
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: enterGlyph.implicitWidth + 10 * surface.s
                    height: 18 * surface.s
                    radius: Motion.rSmall * surface.s
                    color: Qt.alpha(Colors.on_surface, 0.08)
                    border.width: 1
                    border.color: Qt.alpha(Colors.outline_variant, 0.6)
                    Text {
                        id: enterGlyph
                        anchors.centerIn: parent
                        text: "↵"
                        color: Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 12 * surface.s
                    }
                }
            }
        }

        // ── Caps-Lock warning, stacked above the identity prompt ─────────────
        Row {
            anchors.horizontalCenter: prompt.horizontalCenter
            anchors.bottom: prompt.top
            anchors.bottomMargin: 12 * surface.s
            spacing: 6 * surface.s
            visible: surface.isMain && surface.capsLock
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "⇪"
                color: Colors.error
                font.family: Appearance.font.family
                font.pixelSize: 12 * surface.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "caps lock is on"
                color: Colors.error
                font.family: Appearance.font.family
                font.pixelSize: 11 * surface.s
                font.weight: Font.Medium
                font.letterSpacing: 1.5 * surface.s
            }
        }

        // ── Ame (a): the soul bead rests beside the capsule and flares to a
        // ring while verifying — the shell's one glowing element, on the lock.
        Ame {
            id: capsuleAme
            width: 90 * surface.s
            height: 90 * surface.s
            x: capsule.x - width - 4 * surface.s
            y: capsule.y + capsule.height / 2 - height / 2
            s: surface.s
            wickDir: -1
            heat: 0
            form: !surface.isMain ? "off" : (surface.busy ? "ring" : "rest")
            point: Qt.point(width / 2, height / 2)
            wake: Qt.point(width / 2, height / 2)
            opacity: surface.isMain ? (surface.ready ? 1 : 0) : 0
            Behavior on opacity { NumberAnimation { duration: Motion.largeDur } }
        }

        // Ame (b): the seam bead rides the now-playing waveform head — the same
        // soul-seam the Media surface draws. Hidden unless a real timeline plays.
        Ame {
            id: mediaAme
            x: mediaPanel.x
            y: mediaPanel.y
            width: card.width
            height: card.height
            s: surface.s
            wickDir: -1
            heat: 0
            form: (surface.isMain && surface.hasMedia && surface.hasTimeline) ? "seam" : "off"
            point: {
                void wave.drawF;
                void wave.width;
                void mediaPanel.x;
                void mediaPanel.y;
                void surface.playFrac;
                return wave.mapToItem(mediaAme, wave.headX, wave.headY);
            }
            wake: mediaAme.point
            opacity: mediaPanel.opacity
        }
    }
}
