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

    /**
     * Rest vs. auth — the two states the lock screen actually has, the
     * structural idea taken from Panacea's lock.qml. At rest this is a clock on
     * a wallpaper. The moment a character is typed the whole composition
     * re-weights toward the capsule: the wallpaper drops further back (deeper
     * blur, an added scrim), the date and clock lift out of the way, the
     * LOCKED badge — which the act of unlocking has just contradicted — fades
     * out, and the capsule rises to meet the eye.
     *
     * Keyed on TYPED TEXT, not on focus. The input holds focus from the first
     * frame on every screen so that a keystroke always lands somewhere live,
     * which means focus would report "authenticating" before the user had done
     * anything and the surface would never have a resting state at all.
     */
    readonly property bool authMode: input.text.length > 0 || surface.busy || surface.showError
    /** How far the idle block lifts, and how far the bottom band rises. */
    readonly property real authRise: surface.authMode ? -54 * surface.s : 0
    readonly property real authLift: surface.authMode ? 26 * surface.s : 0

    /** The now-playing strip's measure, top right. */
    readonly property real measure: 400 * surface.s

    /**
     * What the capsule morphs out to when you start typing.
     *
     * It briefly shared `measure` with the media strip, from when the two were
     * stacked on one axis and landing flush was the point. They are not
     * stacked any more — the strip went to the top right and the capsule to
     * the bottom left — so the shared number stopped buying anything and just
     * left the capsule wider than it had any use for, a long empty tube with
     * eight dots adrift in the middle of it.
     *
     * 320 holds sixteen dots at the 13dp pitch plus the key-cap, which covers
     * any password anyone types, and the twenty-dot ceiling simply packs
     * tighter past that.
     */
    readonly property real authWidth: 320 * surface.s

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
        // ArtCache downloads a track's cover the moment it starts playing —
        // while unlocked, as part of the always-running shell, never as
        // something the lock screen itself triggers — and keys its result by
        // the same `trackKey` this reads. By the time the machine is actually
        // locked the currently-playing track's art has near-certainly already
        // landed, so this is the common case now, not the fallback.
        if (ArtCache.localArt.length > 0)
            return ArtCache.localArt + "#" + np.trackKey;
        var u = np.artUrl;
        if (!u || u.length === 0)
            return "";
        // Still locked-session-safe for whatever ArtCache hasn't (yet, or
        // ever) caught: only LOCAL art (file:/data:) the PLAYER itself
        // already had cached is honoured directly. A remote http(s) cover
        // with no local copy falls back to the placeholder glyph rather than
        // the lock screen fetching it itself.
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
        property string accessibleName: ""

        // A lock screen is exactly where a screen reader user is least able to
        // fall back on sighted guessing, so the three buttons that exist here
        // name themselves. `can` gates focusability too — a dead transport
        // button should not be a Tab stop.
        Accessible.role: Accessible.Button
        Accessible.name: kb.accessibleName
        Accessible.focusable: kb.can
        Accessible.onPressAction: if (kb.can) kb.activated()

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: kbLabel.implicitWidth
        implicitHeight: kbLabel.implicitHeight
        opacity: kb.can ? 1 : 0.3
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        // These kanji are the lock screen's only buttons (前 / 次 / the layout
        // toggle), so they answer a press the way the rest of the shell's
        // buttons do. A glyph is a small target, so the dip is the deep 0.92.
        scale: kbArea.pressed ? 0.92 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

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
        /**
         * Cap the DECODE size. Without this the wallpaper is decoded at its
         * native resolution, and Qt hard-refuses any single image over 256 MB
         * — a 10000x7000 photo is 280 MB decoded, so it silently fails to load
         * and the lock screen comes up as nothing but the scrim. On a LOCK
         * screen that reads as a hung machine, which is the worst place in the
         * shell for this to happen. Even well under the ceiling it is pure
         * waste: a 6000x4000 wallpaper costs ~96 MB and a long decode to fill
         * a 2560x1600 panel.
         *
         * Twice the surface gives the PreserveAspectCrop room to crop without
         * softening, and sourceSize only ever caps — a wallpaper smaller than
         * this still decodes at its own native size.
         */
        sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
        asynchronous: true
        smooth: true
        cache: false
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallSrc
        // Fade the wallpaper in when the decode lands rather than flipping it
        // on. `asynchronous` means there is always at least one frame without
        // it, and a hard `visible` flip made the lock punch from flat colour to
        // full photo. The opaque base Rectangle underneath is what keeps the
        // desktop covered in the meantime, so nothing leaks during the fade.
        opacity: wallSrc.status === Image.Ready ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.largeDur; easing.type: Motion.easeStandard } }
        blurEnabled: true
        // Rest 0.62, auth 0.86. Pushing the wallpaper further out of focus is
        // what makes the capsule feel like it came forward without actually
        // scaling anything — depth doing the work that size would otherwise
        // have to.
        blur: surface.authMode ? 0.86 : 0.62
        Behavior on blur {
            NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard }
        }
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

    /**
     * Auth-state scrim, layered OVER the two resting gradients rather than
     * animating their stops — a QML Gradient's stops are not animatable, and a
     * separate sheet that fades in is anyway the honest description of what
     * this is: the room dimming while you type, not the wallpaper changing.
     */
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colors.scrim, 0.30)
        opacity: surface.authMode ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard }
        }
    }

    // Soft primary-tinted radial lift behind the clock. A small bright disc is
    // heavily blurred inside a much larger transparent frame, so its edges fade
    // to nothing — a real halo, not a panel. No external gradient dependency.
    Item {
        id: clockGlow
        width: 940 * surface.s
        height: 540 * surface.s
        // Centred on the LEFT column now, not on the panel.
        x: surface.width * 0.07 + surface.width * 0.29 - width / 2
        // Rides the CLOCK. timeBlock starts at 0.13, the 鎖 mark above the
        // numerals is ~42 tall, and the numerals are ~240 — so their optical
        // centre sits ~160 below the block's top.
        y: surface.height * 0.13 + 160 * surface.s - height / 2
        opacity: surface.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.largeDur; easing.type: Motion.easeStandard } }

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
        // A whole-screen focus catcher is plumbing, not an affordance. Left in
        // the tree it would announce itself as a giant unnamed button covering
        // the lock screen and bury the capsule underneath it.
        Accessible.ignored: true
    }
    // ── content ─────────────────────────────────────────────────────────────
    //
    // ONE SPINE. Everything below is centred on the same vertical axis and
    // measured to the same width, in two blocks: what the machine is telling
    // you (date, time) above, and what you came here to do (identity, media,
    // password) below.
    //
    // What this replaced. The old composition had four elements on four
    // unrelated anchoring systems — a date centred at 6.6% of the height, a
    // clock centred at 24%, a now-playing block pinned to the bottom LEFT at
    // 5.2% in and 10% up, a capsule centred at the bottom with an "ENTER ↵"
    // hint hanging off its right edge and the Ame bead hanging off its left.
    // Nothing lined up with anything, the two bottom elements were drawn in
    // two different materials, and the capsule had an appendage on each side
    // pointing in opposite directions. It read as several designs sharing a
    // palette, because that is what it was.
    //
    // Now: the auth capsule and the now-playing strip are the SAME WIDTH
    // (`surface.measure`), stacked on the axis, and the capsule morphs out to
    // exactly that measure as you start typing — so the moment the composition
    // becomes about the password is the moment the two bottom elements snap
    // flush. That alignment landing is the point of the whole layout.
    Item {
        id: content
        anchors.fill: parent

        opacity: surface.ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Motion.largeDur; easing.type: Motion.easeStandard }
        }

        /**
         * The entrance beat. The lock used to arrive as one block sliding up;
         * each element now has its own, in reading order, so the screen
         * assembles top-down over ~300ms instead of appearing. Held off
         * `surface.ready` so it plays exactly once, on the frame the lock
         * takes over the session.
         */
        component Enter: Translate {
            property real delay: 0
            y: surface.ready ? 0 : 20 * surface.s
            Behavior on y {
                SequentialAnimation {
                    PauseAnimation { duration: Math.round(delay * Motion.mult) }
                    NumberAnimation {
                        duration: Motion.expressiveDefaultSpatialDur
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveDefaultSpatial
                    }
                }
            }
        }

        /**
         * The shared spring for everything that re-weights between rest and
         * auth. One curve for the whole re-composition, so the clock lifting,
         * the strip receding and the capsule growing read as ONE gesture
         * rather than as four things that happened to move at the same time.
         */
        component AuthShift: Translate {
            property real to: 0
            y: surface.authMode ? to : 0
            Behavior on y {
                NumberAnimation {
                    duration: Motion.expressiveDefaultSpatialDur
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveDefaultSpatial
                }
            }
        }

        // ── left column: the time, and the date under it ───────────────────
        //
        // Left-aligned rather than centred, and set at display sizes: the time
        // is the largest thing on the screen and the date is the second
        // largest, so the two of them ARE the composition rather than a label
        // sitting on a wallpaper. The now-playing strip counterweights them
        // from the top right and the capsule closes the diagonal at the
        // bottom — three points, none of them fighting for the same axis.
        Column {
            id: timeBlock
            anchors.left: parent.left
            anchors.leftMargin: parent.width * 0.07
            // Anchored by its BOTTOM, not by a fraction of the top. The block
            // is display-sized and its height moves with the type scale, so
            // pinning the top is how it ends up growing down into the capsule
            // the first time anything in it gets bigger.
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.30
            spacing: 0
            transform: [
                AuthShift { to: surface.authRise },
                Enter { delay: 0 }
            ]

            /** The measure the column is set to. */
            readonly property real column: surface.width * 0.62

            /**
             * The screen's type scale, in one place.
             *
             * The clock is the largest thing here and the date is the second
             * largest, and the RATIO between them is what makes that legible.
             * Set closer and the date stops reading as the date and starts
             * competing with the time for the same job; set much further apart
             * and it collapses back into being a caption, which is what it was
             * before.
             *
             * ~3.7:1, not the 2.7:1 this started at, because the display face
             * is Kalam: a handwritten face sets far wider than Inter at the
             * same pixel size, so a number chosen against Inter came out
             * reading a full size larger once the face changed. The ratio is
             * about apparent size, and apparent size is a property of the
             * face, not of the number.
             */
            readonly property real clockSize: 210 * surface.s
            readonly property real dateSize: 56 * surface.s

            // 鎖 LOCK, as a mark at the head of the column rather than a badge
            // in its own row. It states the one fact you are in the middle of
            // undoing, so it stands down the moment you start typing.
            Text {
                visible: Flags.showGlyphs
                text: "鎖"
                color: Qt.alpha(Colors.primary, 0.9)
                font.family: Appearance.font.jp
                font.pixelSize: 44 * surface.s
                opacity: surface.authMode ? 0.25 : 1
                Behavior on opacity {
                    NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard }
                }
                bottomPadding: 6 * surface.s
            }

            // ── the clock ───────────────────────────────────────────────────
            Row {
                id: clockRow

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.42)
                    shadowBlur: 0.9
                    shadowVerticalOffset: 2
                }

                /**
                 * An odometer digit: the old value scrolls UP and out while
                 * the new one arrives from below, inside a clipped slot.
                 *
                 * A lock screen is looked at for whole minutes at a time, so
                 * the one moment it has any motion of its own is the moment a
                 * digit turns over — and replacing the glyph between two
                 * frames throws that away entirely. Rolling per DIGIT rather
                 * than per numeral is what makes it read as a mechanism: at
                 * 23:05 → 23:06 exactly one digit moves, at 23:09 → 23:10 two
                 * do and the tens digit carries, and at 23:59 → 00:00 the
                 * whole row turns over at once. A single block animation
                 * cannot say any of that.
                 *
                 * The slot is a FIXED width measured off "0" with tabular
                 * figures, so nothing in the row shifts while a digit is
                 * mid-travel. An empty value collapses the slot to nothing —
                 * that is the 12-hour clock going from "9" to "10", and the
                 * width animates so the row grows rather than jumps.
                 */
                component ScrollDigit: Item {
                    id: sd
                    property string value: ""
                    property real px: timeBlock.clockSize
                    property color tint: Colors.on_surface

                    TextMetrics {
                        id: slotMetrics
                        text: "0"
                        font.family: Appearance.font.display
                        font.weight: Font.Light
                        font.pixelSize: sd.px
                        font.letterSpacing: -1 * surface.s
                        font.features: ({ "tnum": 1 })
                    }

                    /**
                     * Same probe, but every digit at once, purely for its
                     * `tightBoundingRect.height` below (see the `height`
                     * doc). A multi-glyph run's bounding box is one box, the
                     * union of every glyph's ink, which is exactly what a
                     * shared vertical extent needs — but it is NOT usable
                     * for width the same way: a ten-glyph run's ink span is
                     * the whole row, nothing close to one digit's width.
                     */
                    TextMetrics {
                        id: boundsMetrics
                        text: "0123456789"
                        font: slotMetrics.font
                    }

                    /**
                     * Width, per digit, not per run: Kalam is handwritten,
                     * and its digits do not share one advance box the way a
                     * tabular-figure face's do — `tnum` keeps them landing on
                     * the same rhythm, but a cursive stroke's actual ink can
                     * still overshoot ITS OWN box regardless of how wide the
                     * box is. "0" alone was too narrow a probe for that: it
                     * clipped whichever other digit happened to overshoot
                     * more than "0" does. Ten separate probes, one per glyph,
                     * and the widest ink span wins — static, computed once
                     * for the font, not re-measured per roll.
                     */
                    TextMetrics { id: dw0; text: "0"; font: slotMetrics.font }
                    TextMetrics { id: dw1; text: "1"; font: slotMetrics.font }
                    TextMetrics { id: dw2; text: "2"; font: slotMetrics.font }
                    TextMetrics { id: dw3; text: "3"; font: slotMetrics.font }
                    TextMetrics { id: dw4; text: "4"; font: slotMetrics.font }
                    TextMetrics { id: dw5; text: "5"; font: slotMetrics.font }
                    TextMetrics { id: dw6; text: "6"; font: slotMetrics.font }
                    TextMetrics { id: dw7; text: "7"; font: slotMetrics.font }
                    TextMetrics { id: dw8; text: "8"; font: slotMetrics.font }
                    TextMetrics { id: dw9; text: "9"; font: slotMetrics.font }
                    readonly property real widestDigit: Math.max(
                        dw0.tightBoundingRect.width, dw1.tightBoundingRect.width,
                        dw2.tightBoundingRect.width, dw3.tightBoundingRect.width,
                        dw4.tightBoundingRect.width, dw5.tightBoundingRect.width,
                        dw6.tightBoundingRect.width, dw7.tightBoundingRect.width,
                        dw8.tightBoundingRect.width, dw9.tightBoundingRect.width)

                    width: sd.value.length > 0
                        ? Math.max(slotMetrics.advanceWidth, sd.widestDigit) : 0

                    /**
                     * Tall enough for the INK, not just for the line box.
                     *
                     * The slot clips — that is what makes the roll a roll —
                     * and it was sized to `slotMetrics.height`, the font's
                     * line height. That is fine for a face whose digits sit
                     * inside their em box and wrong for one whose don't:
                     * Kalam is handwritten, and its 4 and 8 swing below the
                     * baseline, so the clip sheared the bottom off them.
                     * `tightBoundingRect` is the actual painted extent, so
                     * taking the larger of the two (plus a little air) means
                     * the window fits whatever face is configured rather than
                     * whatever face it was measured against.
                     */
                    height: Math.max(slotMetrics.height,
                        boundsMetrics.tightBoundingRect.height + 0.16 * sd.px)
                    Behavior on width {
                        NumberAnimation {
                            duration: Motion.expressiveDefaultSpatialDur
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveDefaultSpatial
                        }
                    }
                    clip: true

                    // `curr` is what is on screen; `incoming` is what is
                    // arriving. They are equal except during a roll.
                    property string curr: ""
                    property string incoming: ""
                    property real shift: 0

                    Component.onCompleted: {
                        sd.curr = sd.value;
                        sd.incoming = sd.value;
                    }
                    onValueChanged: {
                        if (sd.value === sd.curr)
                            return;
                        // No roll on the first paint, before the surface has
                        // entered, or under reduce-motion — the digit is
                        // simply already correct.
                        if (!surface.animate || !surface.ready) {
                            rollAnim.stop();
                            sd.curr = sd.value;
                            sd.incoming = sd.value;
                            sd.shift = 0;
                            return;
                        }
                        sd.incoming = sd.value;
                        rollAnim.restart();
                    }

                    // The two glyphs are spelled out rather than sharing a
                    // local component: QML does not allow an inline component
                    // to be declared inside another one.
                    Text {
                        text: sd.curr
                        height: sd.height
                        verticalAlignment: Text.AlignVCenter
                        y: -sd.shift * sd.height
                        width: sd.width
                        horizontalAlignment: Text.AlignHCenter
                        color: sd.tint
                        font.family: Appearance.font.display
                        font.weight: Font.Light
                        font.pixelSize: sd.px
                        font.letterSpacing: -1 * surface.s
                        font.features: ({ "tnum": 1 })
                    }
                    Text {
                        text: sd.incoming
                        height: sd.height
                        verticalAlignment: Text.AlignVCenter
                        // Arrives from BELOW, so the count reads as going up.
                        y: (1 - sd.shift) * sd.height
                        // Nothing to see until a roll is running; without this
                        // the incoming glyph sits one slot-height down inside
                        // the clip and shows through on tall line boxes.
                        visible: sd.shift > 0
                        width: sd.width
                        horizontalAlignment: Text.AlignHCenter
                        color: sd.tint
                        font.family: Appearance.font.display
                        font.weight: Font.Light
                        font.pixelSize: sd.px
                        font.letterSpacing: -1 * surface.s
                        font.features: ({ "tnum": 1 })
                    }

                    NumberAnimation {
                        id: rollAnim
                        target: sd
                        property: "shift"
                        from: 0
                        to: 1
                        duration: Motion.expressiveDefaultSpatialDur
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveDefaultSpatial
                        onFinished: {
                            sd.curr = sd.incoming;
                            sd.shift = 0;
                        }
                    }
                }

                // Two slots per side, fed one character each. The leading hour
                // slot is empty on a 12-hour clock before ten o'clock, which
                // is what collapses it.
                ScrollDigit { value: surface.hourStr.length > 1 ? surface.hourStr.charAt(0) : "" }
                ScrollDigit { id: hourText; value: surface.hourStr.charAt(surface.hourStr.length - 1) }

                // Hand-drawn accent colon — two evenly-gapped dots, optically
                // centred against the numerals, breathing slowly as a tasteful
                // stand-in for ticking seconds.
                Item {
                    id: colon
                    width: 50 * surface.s
                    height: hourText.height
                    Column {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -12 * surface.s
                        spacing: 28 * surface.s
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
                            width: 17 * surface.s; height: 17 * surface.s; radius: width / 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Colors.primary
                        }
                        Rectangle {
                            width: 17 * surface.s; height: 17 * surface.s; radius: width / 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Colors.primary
                        }
                    }
                }

                ScrollDigit { value: surface.minStr.charAt(0); tint: Qt.alpha(Colors.on_surface, 0.7) }
                ScrollDigit { value: surface.minStr.charAt(1); tint: Qt.alpha(Colors.on_surface, 0.7) }
            }

            /**
             * The date, directly under the time. Weekday over day-and-month,
             * both at ONE fixed size.
             *
             * They were briefly auto-fitted to the column instead, which is
             * the obvious way to keep a display-sized line from running off a
             * narrow panel — and it was wrong: `HorizontalFit` sizes each line
             * INDEPENDENTLY, so "SUNDAY" and "6 SEPTEMBER" came out at two
             * different sizes and the block read as two unrelated headlines.
             * A fixed size with an elide is the honest version: the two lines
             * are the same thing said twice, so they are the same size, and at
             * this scale even a long localised month clears the measure with
             * room to spare.
             *
             * The second line is dimmer than the first, which is the whole
             * hierarchy inside the block — no second size needed.
             */
            component DateLine: Text {
                color: Qt.alpha(Colors.on_surface, 0.6)
                font.family: Appearance.font.display
                font.weight: Font.Light
                font.pixelSize: timeBlock.dateSize
                font.letterSpacing: 2 * surface.s
                font.capitalization: Font.AllUppercase
                width: timeBlock.column
                // Safe now that the date is a SINGLE line: HorizontalFit sizes
                // each line independently, which is what made it wrong when
                // the weekday and the day-month were stacked (they came out at
                // two different sizes). With one line there is only one size
                // to pick, and the ceiling below is what a wide screen gets
                // while a narrow one shrinks to fit rather than eliding.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 26 * surface.s
                elide: Text.ElideRight
                lineHeight: 1.0
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.4)
                    shadowBlur: 0.7
                    shadowVerticalOffset: 1
                }
            }

            // One line. Weekday and day-month were briefly two lines; on one
            // line they are a single statement instead of a stack, and the
            // block under the clock stays a block rather than becoming a
            // list. The soul bead used to close this line (see `capsuleAme`,
            // now beside the capsule) — this Item still sizes off `dateLine`
            // alone, which was always the real content.
            Item {
                width: timeBlock.column
                height: dateLine.height + 18 * surface.s

                DateLine {
                    id: dateLine
                    anchors.bottom: parent.bottom
                    text: Qt.locale().toString(clock.date, "dddd") + "  ·  "
                        + Qt.locale().toString(clock.date, "d MMMM")
                }
            }
        }

        // ── now-playing strip, top right ────────────────────────────────────
        // The counterweight. The time block anchors the lower left of the
        // composition and this holds the upper right, which is what keeps a
        // display-sized clock from tipping the whole screen over — and it puts
        // the ambient information where the eye lands first and leaves,
        // instead of in the path between the clock and the password.
        //
        // Chrome-less on purpose: the capsule is the only container on this
        // screen, and giving the media a box of its own would have made two
        // competing objects out of one hierarchy.
        Item {
            id: mediaPanel
            anchors.right: parent.right
            anchors.rightMargin: parent.width * 0.07
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.11
            width: surface.measure
            height: cardCol.implicitHeight

            transform: Enter { delay: 120 }

            visible: opacity > 0.01
            opacity: surface.isMain && surface.hasMedia ? (surface.authMode ? 0.34 : 1) : 0
            Behavior on opacity {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }

            Item {
                id: card
                anchors.fill: parent

                Column {
                    id: cardCol
                    width: parent.width
                    spacing: 14 * surface.s

                    Row {
                        spacing: 14 * surface.s
                        width: parent.width

                        // album art — rounded, with a hairline ring. 76, not
                        // the original 56: at the old size the cover read as
                        // a favicon next to a 14px title, all weight sitting
                        // in the text; big enough now to actually carry the
                        // artwork rather than just confirm one exists.
                        Item {
                            id: artBox
                            width: 76 * surface.s
                            height: 76 * surface.s
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
                                    // The cover fades up as it decodes rather
                                    // than replacing the placeholder in one
                                    // frame — a track change should not punch.
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                                    }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: surface.artSrc.length === 0
                                    text: "音"
                                    color: Qt.alpha(Colors.primary, 0.75)
                                    font.family: Appearance.font.jp
                                    font.pixelSize: 31 * surface.s
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.medium * surface.s
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.alpha(Colors.on_surface, 0.14)
                            }
                        }

                        // Title / artist take whatever the art and the
                        // transports leave, so a long title elides instead of
                        // pushing the transports off the measure.
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - artBox.width - transport.width - 28 * surface.s
                            spacing: 4 * surface.s

                            Text {
                                width: parent.width
                                text: np.title
                                color: Colors.on_surface
                                font.family: Appearance.font.family
                                font.pixelSize: 14 * surface.s
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
                                font.pixelSize: 11.5 * surface.s
                                elide: Text.ElideRight
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: Qt.rgba(0, 0, 0, 0.55)
                                    shadowBlur: 0.7
                                    shadowVerticalOffset: 1
                                }
                            }
                        }

                        // Transports at the trailing end, balancing the art at
                        // the leading end — the strip is symmetric about the
                        // spine even though its contents are not.
                        Row {
                            id: transport
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 16 * surface.s

                            KanjiButton {
                                glyph: "前"
                                size: 13
                                can: np.canPrevious
                                accessibleName: "Previous track"
                                onActivated: np.previous()
                            }

                            // play/pause seal: 奏 while playing, 休 paused
                            Rectangle {
                                id: seal
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26 * surface.s
                                height: 26 * surface.s
                                radius: Motion.rSmall * surface.s
                                color: Qt.alpha(Colors.primary, np.playing ? 0.28 : 0.12)
                                border.width: 1
                                border.color: Qt.alpha(Colors.primary, sealArea.containsMouse ? 0.75 : 0.4)
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                                // The name says what the press will DO, not
                                // what the seal currently shows — "Pause"
                                // while playing — because that is the half a
                                // screen reader user is choosing between.
                                Accessible.role: Accessible.Button
                                Accessible.name: np.playing ? "Pause" : "Play"
                                Accessible.description: surface.hasMedia ? np.title : ""
                                Accessible.focusable: surface.hasMedia
                                Accessible.onPressAction: if (surface.hasMedia) np.togglePlaying()

                                scale: sealArea.pressed ? 0.92 : 1
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Motion.glide
                                        easing.type: Motion.easeBezier
                                        easing.bezierCurve: Motion.expressiveFastSpatial
                                    }
                                }

                                // The glyph itself flips with a quarter-turn
                                // and a dip rather than being swapped: play
                                // and pause are one control in two states, and
                                // the turn is what says so.
                                Text {
                                    anchors.centerIn: parent
                                    text: np.playing ? "奏" : "休"
                                    color: Colors.on_surface
                                    font.family: Appearance.font.jp
                                    font.pixelSize: 13 * surface.s
                                    font.weight: Font.DemiBold
                                    rotation: np.playing ? 0 : -8
                                    Behavior on rotation {
                                        NumberAnimation {
                                            duration: Motion.expressiveFastSpatialDur
                                            easing.type: Motion.easeBezier
                                            easing.bezierCurve: Motion.expressiveFastSpatial
                                        }
                                    }
                                }
                                MouseArea {
                                    id: sealArea
                                    anchors.fill: parent
                                    anchors.margins: -5 * surface.s
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
                                accessibleName: "Next track"
                                onActivated: np.next()
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
                            font.pixelSize: 9.5 * surface.s
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            id: total
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            text: surface.fmt(surface.lenSec)
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9.5 * surface.s
                            font.features: ({ "tnum": 1 })
                        }

                        // static waveform outline — repainted only on resize /
                        // theme change, never per playhead frame.
                        Canvas {
                            id: baseWave
                            anchors.left: elapsed.right
                            anchors.right: total.left
                            anchors.leftMargin: 12 * surface.s
                            anchors.rightMargin: 12 * surface.s
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

                            // Linear on purpose — one of the two places in the
                            // shell that may keep it. `drawF` is a PLAYBACK
                            // POSITION, not a UI reveal: it interpolates
                            // between position samples so the head glides
                            // instead of ticking. Any easing would make the
                            // head run ahead of, then lag behind, where the
                            // track actually is between samples. Do not
                            // "fix" this to Motion.easeStandard.
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
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: np.live && surface.hasMedia
                        spacing: 7 * surface.s
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6 * surface.s
                            height: 6 * surface.s
                            radius: width / 2
                            color: Colors.error
                            SequentialAnimation on opacity {
                                running: surface.animate && np.live && surface.hasMedia
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: Motion.pulse * 2; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1;    duration: Motion.pulse * 2; easing.type: Easing.InOutSine }
                            }
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

        // ── the capsule: the one object on this screen ──────────────────────
        //
        // It is a dynamic island, which is what the whole shell is. At rest it
        // is a compact stadium carrying the identity — `人 immortalforest` —
        // in exactly the grammar the resting pill uses for `時 10:44 PM`:
        // leading glyph, then the content. Type a character and it MORPHS out
        // to the shared measure, the identity hands the middle over to the
        // password dots, and a return key-cap arrives at the trailing end.
        //
        // That morph is the same curve, on the same duration, as the pill's
        // own rest→hover morph. The two are the same object at two sizes, and
        // the identity prompt, the "ENTER ↵" hint and the loading indicator —
        // three separate elements orbiting the old capsule — are now all
        // inside it, because they were always parts of it.
        //
        // Present (and focused) on EVERY screen so typing always lands
        // somewhere live; visible only on the main one.
        Panel {
            id: capsule
            // Centre-bottom. It was briefly left-aligned with the time
            // column, which is the tidier answer on a grid and the wrong one
            // for this control: it is the only thing on the screen you have to
            // AIM at, your hands are already at the keyboard, and centre-bottom
            // is where every lock screen has put that for thirty years. The
            // composition can afford one element that answers to the body
            // rather than to the grid.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.155 + surface.authLift
            Behavior on anchors.bottomMargin {
                NumberAnimation {
                    duration: Motion.expressiveDefaultSpatialDur
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveDefaultSpatial
                }
            }

            s: surface.s
            // Auth lands on exactly the strip's measure above it — the two
            // become one column the instant the screen is about the password.
            // At rest it shrinks to its own content, with a floor so a
            // one-letter username still reads as a capsule and not a chip.
            width: surface.authMode
                ? surface.authWidth
                : Math.max(216 * surface.s, restRow.implicitWidth + 76 * surface.s)
            height: 66 * surface.s
            // The pill's morph curve and duration, deliberately: this IS the
            // pill's morph, at lock-screen scale.
            Behavior on width {
                NumberAnimation {
                    duration: Motion.morph
                    easing.type: Motion.easeMorph
                    easing.bezierCurve: Motion.morphCurve
                }
            }

            radius: height / 2
            // Floats over a photograph rather than over windows, so the
            // wallpaper is allowed through — the one place the shell's material
            // is tuned per surface instead of per component.
            fillAlpha: 0.82
            outlineColor: surface.showError
                ? Colors.error
                : (input.activeFocus ? Colors.primary : Colors.outline_variant)
            outlineAlpha: surface.showError ? 1.0 : (input.activeFocus ? 0.8 : 0.85)
            shadowOpacity: 0.55
            shadowOffset: 6 * surface.s

            opacity: surface.isMain ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            transform: [
                Translate { id: capsuleShift },
                Enter { delay: 180 }
            ]

            /**
             * Failure shake. `Motion.mult` keeps it reduce-motion-safe.
             *
             * The segments carry no easing on purpose — they are the one place
             * in the shell that wants Easing.Linear. A shake is a sequence of
             * hard reversals, and easing each leg in and out rounds the
             * corners off into a wobble; the abruptness is the whole signal.
             */
            SequentialAnimation {
                id: shake
                NumberAnimation { target: capsuleShift; property: "x"; to: 9 * surface.s; duration: Math.round(50 * Motion.mult) }
                NumberAnimation { target: capsuleShift; property: "x"; to: -9 * surface.s; duration: Math.round(50 * Motion.mult) }
                NumberAnimation { target: capsuleShift; property: "x"; to: 6 * surface.s; duration: Math.round(50 * Motion.mult) }
                NumberAnimation { target: capsuleShift; property: "x"; to: -6 * surface.s; duration: Math.round(50 * Motion.mult) }
                NumberAnimation { target: capsuleShift; property: "x"; to: 0; duration: Math.round(50 * Motion.mult) }
            }

            // Keyboard focus ring, just outside the edge. Kept at the old
            // understated weight rather than M3's 3dp `secondary` ring: on a
            // lock screen there is exactly one focusable thing and the ring is
            // reassurance, not navigation.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4 * surface.s
                radius: height / 2
                color: "transparent"
                border.width: 1.5 * surface.s
                border.color: Qt.alpha(surface.showError ? Colors.error : Colors.primary, 0.28)
                opacity: (input.activeFocus || surface.showError) && !surface.busy ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                z: -1
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

            /**
             * REST content — the identity, in the pill's grammar.
             *
             * Never given `visible: false`: the capsule's resting width is
             * measured off this Row's implicitWidth, and a positioner stops
             * recomputing its implicit size the moment it goes invisible, so
             * hiding it would latch the resting width at whatever it happened
             * to be. Opacity is layout-independent and costs nothing at 0.
             */
            Row {
                id: restRow
                anchors.centerIn: parent
                opacity: surface.authMode ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
                }

                // Just the name. The 人 glyph that used to sit here was a
                // second mark doing the job the Ame bead beside it was
                // already doing — two things in one leading slot, neither of
                // them the other's companion. Ame is the shell's own mark and
                // it keeps the slot alone.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: surface.userName.length > 0 ? surface.userName : "welcome back"
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 14.5 * surface.s
                    font.weight: Font.Medium
                    font.letterSpacing: 1.6 * surface.s
                }
            }

            // AUTH content — the obscured password. A CONSTANT pool of 20
            // dots, built once and never rebuilt (any change to a
            // Repeater/ListView model COUNT re-creates every delegate — that
            // was the reload/blink). Each dot is driven by whether its index
            // is within the typed length, so a keypress flips exactly ONE
            // dot's `shown`; only that one animates in, the rest just glide
            // (Behavior on x) to keep the group centred.
            Item {
                id: dotField
                anchors.centerIn: parent
                width: parent.width
                height: 10 * surface.s
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                // While PAM is thinking the dots stand down and breathe.
                // Ame's ring is the loud half of that state and it lives up in
                // the date row now, so the capsule answers quietly, in place,
                // instead of gaining a spinner of its own.
                opacity: input.text.length > 0 ? (surface.busy ? 0.45 : 1) : 0
                SequentialAnimation on scale {
                    running: surface.busy && surface.animate
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.94; duration: Math.round(560 * Motion.mult); easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0;  duration: Math.round(560 * Motion.mult); easing.type: Easing.InOutSine }
                }

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
                            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                        }

                        // a: 0→1 appear. The scale runs PAST 1 on the way in —
                        // a keystroke is the one moment on this screen where
                        // the machine is confirming it heard you, and a dot
                        // that swells a little before settling is that
                        // confirmation. Backspace just fades; undoing does not
                        // deserve a flourish.
                        property real a: 0
                        opacity: Math.min(1, a)
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
                            duration: Motion.expressiveFastSpatialDur
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
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

            // Failure message, in the capsule's centre where the dots were —
            // the field it is about, not a caption somewhere near it.
            Text {
                anchors.centerIn: parent
                opacity: (surface.showError && input.text.length === 0 && !surface.busy) ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                text: {
                    var msg = surface.ctx ? surface.ctx.lastError : "";
                    return msg.length > 0 ? msg.toLowerCase() : "wrong password";
                }
                color: Colors.error
                font.family: Appearance.font.family
                font.pixelSize: 13 * surface.s
                font.letterSpacing: 1.5 * surface.s
            }

            /**
             * The return key-cap, at the capsule's trailing end.
             *
             * This is the old "ENTER ↵" hint, which used to hang OFF the right
             * edge of a centred capsule — the single most unfinished-looking
             * thing on the screen, an asymmetric appendage on an otherwise
             * symmetric composition. It belongs inside: a key-cap in the
             * trailing slot is the trailing control in the pill's own
             * leading/centre/trailing grammar, and it is the thing you are
             * about to press.
             *
             * It springs in with the first character and holds. No idle pulse:
             * a control that keeps moving while you type a password is
             * nagging, not helping.
             */
            Rectangle {
                id: enterCap
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 16 * surface.s
                width: 28 * surface.s
                height: 26 * surface.s
                radius: Motion.rSmall * surface.s
                color: Qt.alpha(Colors.on_surface, 0.09)
                border.width: 1
                border.color: Qt.alpha(Colors.outline_variant, 0.7)

                opacity: (input.text.length > 0 && !surface.busy) ? 1 : 0
                visible: opacity > 0.01
                scale: opacity > 0.5 ? 1 : 0.7
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.expressiveFastSpatialDur
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }

                // 開 OPEN, not the "↵" arrow. It is the direct counterpart to
                // the 鎖 LOCK on the date line — the screen says "locked" at
                // the top and "open" on the key you are about to press — and
                // it says what the key DOES rather than which key it is. Every
                // other glyph on this screen is a kanji; the return arrow was
                // the one piece of borrowed iconography.
                Text {
                    anchors.centerIn: parent
                    text: "開"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.jp
                    font.pixelSize: 13 * surface.s
                    font.weight: Font.DemiBold
                }
            }
        }

        /**
         * Ame, the shell's soul bead — back beside the capsule, opposite the
         * 開 key-cap on the trailing edge. It lived here before it moved up
         * to the date line's colophon slot; this is that same leading/
         * trailing grammar the pill itself uses (kanji leading, status icons
         * trailing), just at lock-screen scale, with the one thing on this
         * screen you actually interact with instead of a status row.
         *
         * Anchored to `capsule.left`, not a fixed x: the capsule's own width
         * Behavior morphs between its rest and auth measures, and an anchor
         * to the live edge rides that morph for free instead of snapping
         * when the capsule resizes under it. Same form/point logic as
         * before — it still flares to a ring while PAM is thinking.
         */
        Ame {
            id: capsuleAme
            anchors.right: capsule.left
            anchors.rightMargin: 34 * surface.s
            anchors.verticalCenter: capsule.verticalCenter
            width: 92 * surface.s
            height: 92 * surface.s
            s: surface.s
            wickDir: -1
            heat: 0
            form: !surface.isMain ? "off" : (surface.busy ? "ring" : "rest")
            point: Qt.point(width / 2, height / 2)
            wake: Qt.point(width / 2, height / 2)
            opacity: surface.isMain ? (surface.ready ? 1 : 0) : 0
            Behavior on opacity { NumberAnimation { duration: Motion.largeDur; easing.type: Motion.easeStandard } }
        }

        // ── Caps-Lock warning, under the capsule ────────────────────────────
        // Below rather than above: everything above the capsule is now the
        // composition, and a warning that pushed into it would break the
        // spine's rhythm every time a thumb brushed the key.
        Row {
            id: capsHint
            anchors.horizontalCenter: capsule.horizontalCenter
            anchors.top: capsule.bottom
            anchors.topMargin: 20 * surface.s
            spacing: 7 * surface.s
            opacity: (surface.isMain && surface.capsLock) ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            // Drops in from behind the capsule rather than appearing beneath
            // it, so it reads as the capsule having something to add.
            transform: Translate {
                y: (surface.isMain && surface.capsLock) ? 0 : -8 * surface.s
                Behavior on y {
                    NumberAnimation {
                        duration: Motion.expressiveFastSpatialDur
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }
            }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 13 * surface.s
                height: 13 * surface.s
                name: "caps-lock"
                color: Colors.error
                stroke: 1.8
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

        // Ame (b): the seam bead rides the now-playing waveform head — the same
        // soul-seam the Media surface draws. Hidden unless a real timeline plays.
        Ame {
            id: mediaAme
            x: mediaPanel.x
            y: mediaPanel.y
            width: mediaPanel.width
            height: mediaPanel.height
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
