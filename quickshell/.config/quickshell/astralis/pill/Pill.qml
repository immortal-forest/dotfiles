pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../colors"
import "../services"
import "../config"
import "m3"
import "surfaces"
// `Notifications` names BOTH the services singleton and the surfaces type;
// both directories are imported unqualified above, so the two notification
// references below go through these aliases to dodge the shadowing.
import "../services" as Services
import "surfaces" as Surfaces

/**
 * astralis — the morphing pill (ported from Gakuseei/Ricelin pill/Pill.qml).
 *
 * One element carries every state. Width/height are driven by a single `mode`
 * string (rest, hover, or an open surface) with a no-overshoot expo easing so
 * surfaces grow out of the pill in place. Faces are stacked absolutely and
 * cross-fade, each gated on `morphCloseness` so content never paints over a
 * half-grown pill.
 *
 * Hover comes from shell.qml's window-level HoverHandler writing `hovered`
 * (a hover source on the resizing pill itself flickers during the centered
 * width morph); pin comes from a passive TapHandler here, so neither swallows
 * pointer events from the content stacked above.
 *
 * API contract (shell.qml depends on this exactly):
 *   settable  : s, screenName, barWindow, surface
 *   writable  : hovered, pinned
 *   readable  : held, targetW, targetH, inputPadRight, width/height/x/y
 *   signals   : requestSurface(name), requestClose()
 */
Item {
    id: pill

    // ── settable by the shell ───────────────────────────────────────────────
    property real s: 1
    property string screenName: ""
    property var barWindow: null
    property string surface: ""

    // ── state ───────────────────────────────────────────────────────────────
    property bool hovered: false
    property bool pinned: false
    property bool forcePinned: false
    readonly property bool held: pinned || forcePinned

    readonly property bool surfaceOpen: surface.length > 0
    property bool hoverLatch: false
    readonly property bool expanded: surfaceOpen || held || hoverLatch

    /**
     * The special workspace shown on this pill's monitor, surfaced as a plain word
     * in place of the clock so it is obvious you are looking at the minimized stash
     * or the private space rather than your real desktop. Empty in the normal case.
     */
    /**
     * This pill's Hyprland monitor object, resolved by name. Cached in one
     * binding so the linear scan over Hyprland.monitors.values runs once per
     * monitor-model change instead of inside every consumer on every IPC tick;
     * downstream reads (specialView) then key off the monitor's own live
     * properties (lastIpcObject) without re-scanning.
     */
    readonly property var hMonitor: {
        var ms = Hyprland.monitors.values;
        for (var i = 0; i < ms.length; i++)
            if (ms[i] && ms[i].name === pill.screenName)
                return ms[i];
        return null;
    }

    readonly property string specialView: {
        var o = hMonitor ? hMonitor.lastIpcObject : null;
        var sw = (o && o.specialWorkspace) ? o.specialWorkspace.name : "";
        if (sw === "special:minimized") return "Minimized";
        if (sw === "special:private") return "Private";
        if (sw === "special:stash") return "Stash";
        if (sw && sw.indexOf("special:") === 0) {
            var id = sw.slice("special:".length);
            // Ricelin resolves named spaces through its Spaces singleton
            // here; astralis has no Spaces yet, so an unknown special id
            // just shows capitalized.
            return id.charAt(0).toUpperCase() + id.slice(1);
        }
        return "";
    }

    // An incoming notification morphs the pill into a toast (unless a
    // pinned/open pill already owns the expansion — `held` outranks it).
    readonly property bool toastActive: Services.Notifications.popups.length > 0

    // A watched quantity changing (volume/brightness keys, a track switch, a
    // workspace hop, the charger landing) flashes the pill into the OSD face.
    readonly property bool osdActive: osd.flashing

    // Extra input width the shell's pill-rect mask adds on the right (used by
    // later stages for content poking past the body); none yet.
    readonly property real inputPadRight: 0

    signal requestSurface(string name)
    signal requestClose()
    // The power icon opens the standalone full-screen session menu
    // (modules/powermenu/PowerMenu.qml) instead of morphing a pill surface —
    // shell.qml wires this to its own `powerMenuOpen` flag. Kept as a
    // dedicated signal (not requestSurface) so the pill never latches
    // `surface` for it and the morph engine is untouched.
    signal requestPower()

    // ── size constants (Ricelin numbers, ×s) ────────────────────────────────
    readonly property real restW: 160 * s
    readonly property real restH: 38 * s
    readonly property real hoverPad: 20 * s
    readonly property real hoverW: hoverRow.implicitWidth + 2 * hoverPad
    readonly property real hoverH: 58 * s
    readonly property real toastW: 342 * s
    readonly property real restCorner: Appearance.rounding.pill * s        // 18
    readonly property real openCorner: Appearance.rounding.pillOpen * s    // 22

    /**
     * Latch-once lazy load. Every surface sleeps in an inactive Loader until
     * its first open; the size thunks below resolve items through here. The
     * ordering is the trick: flip `active` before any read of the loader, so
     * the calling binding never has the loader registered as a dep when the
     * flip fires mid-evaluation (that read-then-write would be a binding
     * loop). The write is idempotent and the Loader loads synchronously.
     * Nothing ever deactivates a loaded surface.
     */
    function surfaceItem(ld) {
        ld.active = true;
        // INVARIANT: every surface Loader MUST stay synchronous (the default,
        // asynchronous: false). This activate-then-read only works because
        // `ld.item` is populated in the SAME tick as the `active` flip; an
        // asynchronous Loader would return null here and crater every size
        // thunk (and the ame anchor) until a later frame. Assert loudly so a
        // future `asynchronous: true` regresses visibly instead of silently.
        if (ld.item === null)
            console.warn("Pill.surfaceItem: loader item null after activate — surface Loaders must be synchronous");
        return ld.item;
    }

    /**
     * Single source of truth for every morphing surface, keyed by its
     * `surface` string. Each entry owns the surface's target size as a thunk
     * (so the geometry it reads registers as a live dep of targetSize) and a
     * thunk resolving the surface item Ame anchors to while it is open
     * (null = Ame falls back to the pill's own hover or wake anchor).
     * Sizes are FIXED — deliberately not read from `.implicitHeight` of the
     * loader item, which avoids the binding-loop and relayout-dim risks of
     * content-driven targets. `surfaceItem` is still called first so the
     * loader latches active the instant its surface is targeted. Adding a
     * surface is one entry here plus its Loader in surfaceHost.
     */
    readonly property var surfaces: ({
        // Card back to its original 390 — the 430 tried here read too big on
        // screen. The source/time line's truncation this was chasing (see
        // Media.qml's `srcLine`, squeezed between `textX` and `transport.left`)
        // is still there when a multi-player picker chip is showing; if that
        // comes up again the fix belongs in that gap specifically, not in
        // widening the whole card.
        media:     { size: () => { surfaceItem(ldMedia);     return Qt.size(390 * s, 150 * s); }, ame: () => surfaceItem(ldMedia) },
        calendar:  { size: () => { surfaceItem(ldCalendar);  return Qt.size(698 * s, 304 * s); }, ame: () => surfaceItem(ldCalendar) },
        mixer:     { size: () => { surfaceItem(ldMixer);     return Qt.size(440 * s, 214 * s); }, ame: () => surfaceItem(ldMixer) },
        link:      { size: () => { surfaceItem(ldLink);      return Qt.size(330 * s, 360 * s); }, ame: () => surfaceItem(ldLink) },
        launcher:  { size: () => { surfaceItem(ldLauncher);  return Qt.size(360 * s, 332 * s); }, ame: () => surfaceItem(ldLauncher) },
        clipboard: { size: () => { surfaceItem(ldClipboard); return Qt.size(360 * s, 332 * s); }, ame: () => surfaceItem(ldClipboard) },
        notifications: { size: () => { surfaceItem(ldNotifications); return Qt.size(400 * s, 460 * s); }, ame: () => surfaceItem(ldNotifications) },
        // Sidebar tree (190) + divider gutter + content pane (~370, Ricelin
        // sub-surface width) wide; tall enough for the 9-row index column.
        settings:  { size: () => { surfaceItem(ldSettings);  return Qt.size(620 * s, 500 * s); }, ame: () => surfaceItem(ldSettings) },
        // Ricelin sizes sysmon 392×(content+33): header 24 + 16 + dials 110 +
        // 18 + divider 1 + 13 + cells 30 = 212 content ⇒ 245 fixed. Height is
        // GPU-independent (dials recentre, the cell row just gets wider cells).
        sysmon:    { size: () => { surfaceItem(ldSysmon);    return Qt.size(392 * s, 245 * s); }, ame: () => surfaceItem(ldSysmon) },
        // Header 24 + 14 + state panel 94 + 12 + rule + 6 + three option rows
        // 102 + 6 + chip row 28 + 10 + output 24 = 322 content ⇒ 350 fixed;
        // 430 wide keeps three capture tiles square-ish and fits the frame-rate
        // and quality strips on one line each.
        recorder:  { size: () => { surfaceItem(ldRecorder);  return Qt.size(430 * s, 350 * s); }, ame: () => surfaceItem(ldRecorder) }
    })

    // Mode ladder (Ricelin Pill.qml:224–231; game/quickChoose/quickCount rungs
    // splice in with their subsystems). `osd` and `toast` sit BELOW `held` so a
    // pinned or surface-open pill is never interrupted, and `osd` ABOVE `toast`
    // so a flash preempts a queued notification (the toast resumes when the
    // flash clears — popups stay queued). An open surface with no descriptor
    // (e.g. a not-yet-built name) falls through to hover instead of morphing
    // to nothing.
    readonly property string mode: surfaceOpen && Object.prototype.hasOwnProperty.call(surfaces, surface) ? surface
        : (held ? "hover"
        : (osdActive ? "osd"
        : (toastActive ? "toast"
        : (expanded ? "hover" : "rest"))))

    // Opening a surface releases the pin: the surface owns the expansion now,
    // and closing it should collapse the pill instead of leaving it latched —
    // so clear on BOTH transitions (a stray pin tap on open-surface padding
    // must not survive the surface closing and leave the pill stuck open).
    onSurfaceOpenChanged: pinned = false

    /**
     * A clock readout that ROLLS when the time changes.
     *
     * The pill is the most-looked-at object in the shell and, at rest, the
     * least animated: it holds a string for sixty seconds and then swaps it
     * between two frames. The new value now rises the last few pixels into
     * place out of a dim — the smallest gesture that reads as time PASSING
     * rather than as text being replaced, and the same one the lock screen's
     * numerals use, so the shell's two clocks tick the same way.
     *
     * Silenced when the clock is showing SECONDS: a roll once a minute is a
     * detail, and the identical roll sixty times a minute is a fidget. Also
     * silenced under reduce-motion, and while the readout is not on screen.
     */
    component TickText: Text {
        id: tick
        property bool live: true
        readonly property bool rolls: tick.live && !Flags.clockSeconds && !Motion.reduceMotion

        color: Colors.on_surface
        font.family: Appearance.font.family
        font.features: ({ "tnum": 1 })

        transform: Translate { id: tickRoll }
        onTextChanged: if (tick.rolls) tickAnim.restart()

        ParallelAnimation {
            id: tickAnim
            NumberAnimation {
                target: tickRoll; property: "y"
                from: 5 * pill.s; to: 0
                duration: Motion.expressiveFastSpatialDur
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
            NumberAnimation {
                target: tick; property: "opacity"
                from: 0.4; to: 1
                duration: Motion.standard
                easing.type: Motion.easeStandard
            }
        }
    }

    // ── clock ───────────────────────────────────────────────────────────────
    SystemClock {
        id: sysClock
        precision: Flags.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    QtObject {
        id: clock
        readonly property var now: sysClock.date
        readonly property string timeFormat: (Flags.time12h ? "h:mm" : "HH:mm")
            + (Flags.clockSeconds ? ":ss" : "")
            + (Flags.time12h ? " AP" : "")
        readonly property string hhmm: Qt.formatTime(now, timeFormat)
        readonly property string date: Qt.locale().toString(now, "ddd d MMM")
    }

    // ── morph geometry ──────────────────────────────────────────────────────
    property real morphRadius: (mode === "rest" || mode === "hover") ? restCorner : openCorner

    /**
     * Target geometry for the non-surface morph modes. Surface sizes come
     * from the `surfaces` descriptor; hover is the only pill-own mode with a
     * distinct size this stage. Thunks so the properties they read register
     * as live deps of targetSize.
     */
    readonly property var modeSize: ({
        hover: () => Qt.size(hoverW, hoverH),
        // The Osd reports its own per-kind footprint (Ricelin Pill.qml:530) —
        // wide for a track card, snug around the dot strip for a workspace hop.
        osd: () => Qt.size(osd.desiredW, osd.desiredH),
        // Content-driven height (Ricelin pattern): the toast Loader latches
        // active the instant a popup lands, so its item's implicitHeight is a
        // live dep here; +24*s covers the Loader's 12*s vertical margins.
        toast: () => Qt.size(toastW, ldToast.item ? ldToast.item.implicitHeight + 24 * s : restH)
    })

    /**
     * Rest width: whatever the resting row asks for plus the 18*s edge padding
     * on each side, never below restW's floor. Everything that can appear at
     * rest — capture chip, kanji + clock, privacy dots — lives inside restRow,
     * so its implicitWidth is the single measurement and the row stays centred
     * and evenly padded in every combination. (An earlier pass anchored the
     * privacy dots to the pill's right edge and reserved their width twice
     * here; that kept the clock centred but left the dots hard against it with
     * no gutter, and the reserve read as dead space on the left.)
     */
    readonly property real restTargetW: Math.max(restW, restRow.implicitWidth + 36 * s)

    readonly property size targetSize: {
        const sf = Object.prototype.hasOwnProperty.call(surfaces, mode) ? surfaces[mode] : undefined;
        if (sf)
            return sf.size();
        const f = Object.prototype.hasOwnProperty.call(modeSize, mode) ? modeSize[mode] : undefined;
        return f ? f() : Qt.size(restTargetW, restH);
    }
    readonly property real targetW: targetSize.width
    readonly property real targetH: targetSize.height

    width: targetW
    height: targetH

    /**
     * How settled the pill is into its target geometry: 0 while the morph is
     * far away, 1 once it arrives. Content opacities key off this, not their
     * own timers, so a surface fades in as the pill reaches full size, never
     * over a half-grown pill.
     */
    readonly property real morphCloseness: {
        const d = Math.max(Math.abs(width - targetW), Math.abs(height - targetH));
        return 1 - Math.min(1, d / (110 * s));
    }

    /**
     * Gate the soul bead until the hover morph has arrived and its icons exist.
     * Fire it earlier and the bead aims at anchors that aren't laid out yet.
     * Latched so small width changes inside hover (workspace dot growing, tray
     * icons appearing) don't flicker the bead off.
     */
    property bool hoverSoulGate: false
    readonly property bool hoverArrived: mode === "hover" && morphCloseness > 0.55
    onHoverArrivedChanged: if (hoverArrived) hoverSoulGate = true

    /**
     * Rest and hover sit a few dozen pixels apart, so the 420ms morph is
     * nearly all settle tail on that hop and reads sluggish. Both endpoints
     * in the rest/hover pair get the shorter glide; every real surface morph
     * keeps the full duration.
     */
    property string lastMode: "rest"
    property bool hoverHop: false

    onModeChanged: {
        hoverHop = (mode === "hover" || mode === "rest") && (lastMode === "hover" || lastMode === "rest");
        lastMode = mode;
        if (mode !== "hover") {
            hoverSoulGate = false;
            soulTarget = "";
            soulWsIndex = -1;
        }
    }
    onHoverSoulGateChanged: if (hoverSoulGate) kanjiFlashAnim.restart()

    property string soulTarget: ""
    property int soulWsIndex: -1

    property real kanjiFlash: 0

    SequentialAnimation {
        id: kanjiFlashAnim
        NumberAnimation { target: pill; property: "kanjiFlash"; to: 1; duration: Math.round(90 * Motion.mult); easing.type: Motion.easeStandard }
        NumberAnimation { target: pill; property: "kanjiFlash"; to: 0; duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    Behavior on width { NumberAnimation { duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
    Behavior on height { NumberAnimation { duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }
    Behavior on morphRadius { NumberAnimation { duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve } }

    /**
     * Hover grace: latch on the instant the pointer arrives; when it leaves,
     * hold the expansion briefly so the pill doesn't start collapsing under a
     * pointer that grazed out and back, and the hover morph gets to settle.
     */
    onHoveredChanged: {
        if (hovered) {
            hoverLatch = true;
            latchTimer.stop();
        } else {
            latchTimer.restart();
        }
    }

    Timer {
        id: latchTimer
        interval: Motion.fast    // ~140ms grace: quick defer once the pointer truly leaves
        onTriggered: pill.hoverLatch = false
    }

    // ── body ────────────────────────────────────────────────────────────────
    // The pill's material is now Panel — the same gradient, outline, sheen
    // and shadow the lock screen's capsule and now-playing panel wear. It used
    // to be written out inline here and nowhere else, which is precisely why
    // the lock screen and the pill did not look like the same program.
    Panel {
        id: body
        anchors.fill: parent
        s: pill.s
        radius: pill.morphRadius
    }

    // ── Ame, the soul bead ──────────────────────────────────────────────────

    /**
     * Rest anchor for Ame: the 時 kanji centre. The idle outline condenses into
     * the bead here before it moves.
     */
    readonly property point wakePoint: {
        void pill.width;
        void pill.height;
        return restKanji.mapToItem(pill, restKanji.width / 2, restKanji.height / 2);
    }

    /**
     * Bead target while hovered. soulTarget is a sticky key written by the
     * hover sources: the bead parks on the last focused dot or icon and glides
     * to the next, so crossing a gap between targets doesn't snap it back to
     * the active workspace. Pill geometry is voided so the anchor follows the
     * hover morph, the point stays live.
     */
    readonly property point soulPoint: {
        void pill.width;
        void pill.height;
        const drop = 12 * pill.s;
        // The bead parks just under the GLYPH, not under the button box. A
        // status slot is a 32dp state layer around an 18dp icon now, so
        // `height` overshoots the ink by 7dp on each side and aiming at it
        // would drop the bead onto the pill's bottom edge (where Ame's own
        // bounds clamp would catch it and pin it there for every icon alike).
        const glyphFoot = M3.iconButtonIconSizeSmall / 2 * pill.s + drop * 0.55;
        if (soulTarget === "tray") {
            void trayIcons.implicitWidth;
            return trayIcons.mapToItem(pill, trayIcons.width / 2, trayIcons.height + drop * 0.3);
        }
        if (soulTarget === "inbox")
            return inboxIcon.mapToItem(pill, inboxIcon.width / 2, inboxIcon.height / 2 + glyphFoot);
        if (soulTarget === "power")
            return powerIcon.mapToItem(pill, powerIcon.width / 2, powerIcon.height / 2 + glyphFoot);
        if (soulTarget === "settings")
            return settingsIcon.mapToItem(pill, settingsIcon.width / 2, settingsIcon.height / 2 + glyphFoot);
        if (soulTarget === "recorder")
            return recorderIcon.mapToItem(pill, recorderIcon.width / 2, recorderIcon.height / 2 + glyphFoot);
        if (soulTarget === "ws" && soulWsIndex >= 0) {
            void wsDots.activeName;
            void wsDots.width;
            const p = wsDots.mapToItem(pill, wsDots.slotCenterX(soulWsIndex), wsDots.height / 2);
            return Qt.point(p.x, p.y + drop);
        }
        return wsDots.mapToItem(pill, wsDots.activeDotPoint.x, wsDots.activeDotPoint.y + drop);
    }

    /**
     * Which open surface owns Ame's anchor. Each surface exports its own
     * `ameForm`/`amePoint`; the pill picks the open surface's `ame` from the
     * descriptor and maps it. Null = nothing open, so Ame falls back to the
     * pill's own hover/wake anchor.
     */
    readonly property var ameSurface: (surfaceOpen && Object.prototype.hasOwnProperty.call(surfaces, surface))
        ? surfaces[surface].ame() : null

    /**
     * The anchors below are handed over RAW. Ame's canvas fills the pill, so
     * ink outside the body is cut; rather than every anchor site carrying its
     * own safety margin, Ame clamps `point` into its own bounds by the current
     * form's painted extent (Ame.qml `anchor`/`inkHalf`). The clamp is a no-op
     * for a point that already has headroom, so the hover/wake anchors and the
     * surfaces' deliberate edge docks land exactly where they ask to.
     */
    Ame {
        id: ame
        anchors.fill: parent
        s: pill.s
        heat: 0
        wake: pill.wakePoint
        wickDir: -1
        form: pill.ameSurface ? pill.ameSurface.ameForm
            : (pill.mode === "hover" && pill.hoverSoulGate ? "soul" : "off")
        point: pill.ameSurface
            ? Qt.point(pill.ameSurface.x + pill.ameSurface.amePoint.x,
                       pill.ameSurface.y + pill.ameSurface.amePoint.y)
            : (pill.mode === "hover" ? pill.soulPoint : pill.wakePoint)
    }

    // ── rest face ───────────────────────────────────────────────────────────
    Item {
        id: rest
        anchors.fill: parent
        opacity: pill.mode === "rest" ? Math.pow(pill.morphCloseness, 1.5) : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: pill.mode === "rest" ? Motion.fast : Motion.glide
                easing.type: Motion.easeStandard
            }
        }

        // The capture chip and the privacy indicators used to be fenced off
        // from the clock by 1px vertical rules. The rules are gone and nothing
        // replaced them: restRow's spacing does the separating, tightened
        // inside each group and widened between them. Boxing the two groups
        // into tracks was tried and reverted — a container nested inside the
        // pill's own container reads as packaging, and the pill is small
        // enough that a wider gap says "different thing" perfectly well.

        /**
         * One live capture source, drawn as a DOT — not as an icon.
         *
         * These were tiny icons twice over: first Material Symbols ligatures,
         * then GlyphIcons, and both times they read as odd ones out in the
         * resting pill. The reason is not which icon set they came from. It is
         * that a 13dp stroked pictogram carries detail nobody can resolve at
         * that size, and putting three of them in three different accent
         * colours next to a clock makes a rash rather than a status.
         *
         * The pill already has a vocabulary for "something is live", and it is
         * a coloured dot — the capture chip's recording dot, three centimetres
         * to the left of these, does exactly this. So do the workspace dots,
         * the unread badge, the lock screen's colon and the Ame bead. Matching
         * it costs the pictogram and buys a status line that reads at a glance
         * and belongs to the shell. WHICH source is live is carried by colour
         * and, for anyone who needs it stated, by the accessible name.
         */
        component PrivacyDot: Item {
            id: pdot
            property color tint: Colors.on_surface
            property bool active: false
            property string label: ""
            anchors.verticalCenter: parent.verticalCenter
            width: 8 * pill.s
            height: 8 * pill.s
            opacity: active ? 1 : 0
            visible: opacity > 0.01
            scale: active ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            // A dot says "live" but not "live doing what", so the one thing it
            // cannot show is the one thing a screen reader must say.
            Accessible.role: Accessible.Indicator
            Accessible.name: pdot.label
            Accessible.ignored: !pdot.active

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: pdot.tint

                // The same breath, at the same rate, as the capture chip's
                // recording dot. Gated on the rest face actually showing, so
                // no infinite animation ticks behind an open surface.
                SequentialAnimation on opacity {
                    running: pdot.active && rest.visible && !Motion.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: Motion.pulse * 2; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1;    duration: Motion.pulse * 2; easing.type: Easing.InOutSine }
                }
            }
        }

        Row {
            id: restRow
            anchors.centerIn: parent
            // 11 rather than the old 9: the vertical rules used to hold the
            // optional groups off the clock, and with them gone the gap is the
            // only thing doing it.
            spacing: 11 * pill.s

            /**
             * Capture chip. While a take is arming or running the resting pill
             * grows a live counter to the left of the clock — a Row skips
             * invisible children, so at rest this costs nothing, and when it
             * appears the rest target (restRow.implicitWidth + 36*s, above
             * restW's floor) widens the pill through the same morph Behavior
             * as everything else. Read-only: the hover row's 録 icon is the way
             * back to the stop control, so a stray pill tap can't end a take.
             */
            Row {
                id: recChip
                anchors.verticalCenter: parent.verticalCenter
                visible: ScreenRec.recording || ScreenRec.arming
                spacing: 6 * pill.s

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8 * pill.s
                    height: 8 * pill.s
                    radius: width / 2
                    color: ScreenRec.arming || ScreenRec.paused
                        ? Colors.on_surface_variant : Colors.error

                    // Breathes while capturing; a countdown or a paused take
                    // holds steady, so "live" is never ambiguous at a glance.
                    SequentialAnimation on opacity {
                        running: ScreenRec.recording && !ScreenRec.paused
                            && rest.visible && !Motion.reduceMotion
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: Motion.pulse * 2; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1;    duration: Motion.pulse * 2; easing.type: Easing.InOutSine }
                    }
                }

                TickText {
                    anchors.verticalCenter: parent.verticalCenter
                    // A countdown is three deliberate beats and each one is
                    // worth marking; the running elapsed time is a second
                    // hand, and animating a second hand is a fidget.
                    live: rest.visible && ScreenRec.arming
                    text: ScreenRec.arming ? "" + ScreenRec.countdown : ScreenRec.elapsedText
                    font.pixelSize: 13 * pill.s
                    font.weight: Font.DemiBold
                }
            }

            // The resting 時 kanji (Ricelin Pill.qml:1174–1228). The kanji
            // carries the idle glow (an Outline copy whose alpha rides
            // kanjiFlash) and cross-fades with the cava spectrum. MusicBars is
            // mounted UNCONDITIONALLY — merely referencing the lazy Cava
            // singleton is what spawns cava, so a Loader gated on Cava.active
            // would spawn/kill the process on every inter-track gap.
            Item {
                id: restKanji
                visible: pill.specialView === ""
                anchors.verticalCenter: parent.verticalCenter
                width: kanjiFill.implicitWidth
                height: kanjiFill.implicitHeight

                /** Audio leaving the speakers flips the clock glyph over to the live waveform. */
                readonly property bool barsOn: Flags.musicViz && Cava.active

                Text {
                    anchors.fill: parent
                    opacity: (Flags.showGlyphs && !restKanji.barsOn) ? 1 : 0
                    text: kanjiFill.text
                    color: "transparent"
                    font: kanjiFill.font
                    style: Text.Outline
                    // Was a flat 0.5 baseline whenever at rest — a permanent
                    // tertiary-tinted halo, not a flash, sitting right next to
                    // a plain-fill numeral with none. It read as two different
                    // rendering techniques stapled together, the same
                    // complaint this shell keeps drawing for mismatched
                    // shapes/fonts, just done in outline-vs-fill this time.
                    // 0.16 keeps the kanji's warmth as a whisper; kanjiFlash
                    // still spikes it to a real glow on the hover-soul-gate
                    // event, which is the only place this was ever meant to
                    // read as a flash.
                    styleColor: Qt.alpha(Colors.tertiary,
                        Math.min(1, (pill.mode === "rest" || !pill.hoverSoulGate ? 0.16 : 0) + pill.kanjiFlash))
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                }

                Text {
                    id: kanjiFill
                    opacity: (Flags.showGlyphs && !restKanji.barsOn) ? 1 : 0
                    text: "時"
                    color: Colors.on_surface
                    font.family: Appearance.font.jp
                    font.weight: Font.Medium
                    font.pixelSize: 15 * pill.s
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    opacity: (!Flags.showGlyphs && !restKanji.barsOn) ? 1 : 0
                    width: 17 * pill.s
                    height: 17 * pill.s
                    name: "clock"
                    color: Colors.on_surface
                    stroke: 1.7
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                }

                MusicBars {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: kanjiFill.baseline
                    s: pill.s
                    // Freeze the spectrum whenever the rest face isn't showing
                    // (surface open, toast/osd flash) so it stops chasing cava.
                    playing: restKanji.barsOn && rest.visible
                    opacity: restKanji.barsOn ? 1 : 0
                    scale: restKanji.barsOn ? 1 : 0.7
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                    Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                }
            }

            TickText {
                visible: pill.specialView === ""
                live: rest.visible
                anchors.verticalCenter: parent.verticalCenter
                text: clock.hhmm
                font.pixelSize: 16 * pill.s
                font.weight: Font.DemiBold
            }

            Text {
                visible: pill.specialView !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pill.specialView
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 16 * pill.s
                font.weight: Font.DemiBold
            }

            // ── privacy indicators (iOS-style) ──────────────────────────
            // Something capturing the mic / camera / screen shows as a tiny
            // pulsing glyph at the trailing end of the same centred row,
            // mirroring the capture chip at the leading end. Both now sit in
            // the same recessed track, so the two read as a matched pair of
            // status wells flanking the clock rather than as two loose groups
            // fenced off by rules.
            //
            // The group must go `visible: false` when empty — a Row reserves a
            // spacing gap for a zero-width visible child, which would leave a
            // hole after the clock.
            //
            // Gate that on OPACITY, never on measured width: a positioner
            // stops recomputing its implicitWidth while it is invisible, so
            // `visible: width > 0` is a one-way latch — once the last dot
            // clears, the width never comes back and the indicators are gone
            // for the rest of the session (verified: implicitWidth holds 0.0
            // with a visible, opaque child underneath). Opacity is
            // layout-independent, so it keeps animating while hidden and lifts
            // the group back into the row on its own, and it buys the fade.
            Row {
                id: privacyRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5 * pill.s
                opacity: Privacy.anyActive ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                PrivacyDot { active: Privacy.micActive;    tint: Colors.tertiary; label: "Microphone in use" }
                PrivacyDot { active: Privacy.cameraActive; tint: Colors.primary;  label: "Camera in use" }
                PrivacyDot { active: Privacy.screenActive; tint: Colors.error;    label: "Screen being shared" }
            }
        }
    }

    // ── hover face ──────────────────────────────────────────────────────────
    Item {
        id: hover
        anchors.fill: parent
        opacity: pill.mode === "hover" ? Math.pow(pill.morphCloseness, 1.2) : 0
        // Deliberately never hidden: hoverW derives from hoverRow's implicit
        // width and a Row positioner skips invisible children, so hiding this
        // face would zero the hover morph target (Ricelin does the same).
        visible: true
        // Near-instant clear when leaving hover so this face never lingers
        // over an opening surface; fast fade-in smooths the closeness pop.
        Behavior on opacity {
            NumberAnimation {
                duration: pill.mode === "hover" ? Motion.fast : 0
                easing.type: Motion.easeStandard
            }
        }

        // This face stays visible at opacity 0 (see above), so every
        // interactive bit inside it must gate on `live` or an invisible
        // hover face would swallow clicks meant for the rest face / surfaces.
        readonly property bool live: pill.mode === "hover"

        /**
         * Entrance stagger. The hover face used to arrive as one flat
         * cross-fade: the pill grew and its whole contents appeared at once,
         * which reads as a picture being swapped rather than as a control
         * unfolding. Each zone now rises the last few pixels into place on its
         * own beat — workspaces first, then the clock, then the status icons
         * one after another — so the row assembles left to right in the ~200ms
         * the morph is already taking.
         *
         * Deliberately a TRANSLATE only, with no per-zone opacity: the face's
         * own cross-fade is already running underneath, and fading twice made
         * the row feel like it was arriving through fog. The rise is what adds
         * the life; the fade is already handled.
         *
         * Delays are held off `live` so LEAVING is instant — a staggered exit
         * would leave content hanging over a pill that had already collapsed.
         */
        component ZoneRise: Translate {
            property real delay: 0
            y: hover.live ? 0 : 7 * pill.s
            Behavior on y {
                SequentialAnimation {
                    PauseAnimation { duration: hover.live ? Math.round(delay * Motion.mult) : 0 }
                    NumberAnimation {
                        duration: Motion.expressiveFastSpatialDur
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }
            }
        }

        /**
         * A status slot in the hover row: an M3 Expressive extra-small icon
         * button — a 32dp state layer around an 18dp GlyphIcon.
         *
         * What this replaced, and why. The old slot was a bare 17dp Material
         * Symbols glyph whose only feedback was a colour swap, with a
         * TapHandler carrying a 6dp margin — a ~29dp pointer target, under
         * M3's floor, with nothing under the cursor to say it was aimable.
         * Now the target is a real 32dp box (grown to 36dp invisibly by
         * `minTarget`, which is exactly the pitch of the group's 4dp gaps, so
         * neighbouring targets tile without overlapping), and it carries M3's
         * state layer: 8% of the content colour on hover, 12% pressed, plus
         * the keyboard focus ring and the shell's press dip.
         *
         * The glyph is a GlyphIcon rather than a Material Symbols ligature so
         * that an icon matches the surface it opens — the notifications,
         * recorder and settings surfaces are all drawn in the shell's own
         * stroked set, and the launcher for a surface pointing at a different
         * icon family than the surface itself was the seam that made the pill
         * read as chrome bolted onto a different program.
         */
        component StatusGlyph: Item {
            id: statusGlyph
            /** A `pill/lib/glyphs.js` name — a name not in that file draws NOTHING. */
            property string icon: ""
            /** Per-slot override; the four shell icons all take the default. */
            property real iconSize: M3.iconButtonIconSizeSmall
            property string surface: ""
            property string soulKey: ""
            property bool dot: false
            // Clickable either because it owns a pill surface (surface
            // non-empty) or because it does something else on tap (the power
            // icon opens the standalone session menu) — set explicitly there.
            property bool interactive: surface !== ""
            /** What this icon IS, and what tapping it does. */
            property string accessibleName: ""
            property string accessibleDescription: ""
            signal activated()

            /** Position in the trailing cluster's entrance stagger. */
            property int order: 0

            width: M3.iconButtonSizeSmall * pill.s
            height: M3.iconButtonSizeSmall * pill.s

            transform: ZoneRise { delay: 130 + statusGlyph.order * Motion.rowStagger }

            // M3StateLayer drives this through its own animated `dip`.
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            GlyphIcon {
                anchors.centerIn: parent
                width: statusGlyph.iconSize * pill.s
                height: statusGlyph.iconSize * pill.s
                name: statusGlyph.icon
                color: glyphState.hovered ? Colors.on_surface : Colors.on_surface_variant
                stroke: 1.7
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            // Unread badge, tucked inside the 32dp box rather than hung off
            // its corner — the box is the button now, and a dot floating
            // outside it would sit on the group track's edge.
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 3 * pill.s
                anchors.rightMargin: 3 * pill.s
                width: M3.badgeDotSize * pill.s
                height: width
                radius: width / 2
                color: Colors.primary
                // Springs in when the first notification lands rather than
                // blinking into existence — the overshoot is what makes a
                // badge read as something that ARRIVED.
                scale: statusGlyph.dot ? 1 : 0
                visible: scale > 0.01
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.expressiveFastSpatialDur
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }
            }

            // Sticky soul-bead retarget (A.4): entering this glyph writes its
            // key; nothing clears it on exit, so the bead parks here and only
            // moves when another target claims it — icon→icon, never via home.
            HoverHandler {
                enabled: hover.live && statusGlyph.soulKey !== ""
                onHoveredChanged: if (hovered) pill.soulTarget = statusGlyph.soulKey
            }

            M3StateLayer {
                id: glyphState
                anchors.fill: parent
                enabled: hover.live && statusGlyph.interactive
                s: pill.s
                radius: width / 2
                contentColor: Colors.on_surface
                // Small round target — the contract's deep dip.
                pressScale: 0.92
                minTarget: M3.groupTarget
                accessibleName: statusGlyph.accessibleName
                accessibleDescription: statusGlyph.accessibleDescription
                onClicked: {
                    if (statusGlyph.surface !== "")
                        pill.requestSurface(statusGlyph.surface);
                    statusGlyph.activated();
                }
            }
        }

        Row {
            id: hoverRow
            anchors.centerIn: parent
            // The two 1px rules that used to fence the clock off from the
            // workspace dots and the status cluster are gone (see M3Group.qml),
            // so the gap is now the only thing separating the row's three
            // zones and it is widened to carry that on its own.
            spacing: 26 * pill.s

            /**
             * The clock sits at ROW POSITION 2 of 3, not at the pill's
             * geometric middle — those are only the same point when the
             * leading (workspace dots) and trailing (tray + status icons)
             * zones happen to measure the same width, and they usually
             * don't (5 status icons + a tray reliably outmeasures 2-8 dots).
             * A plain Row centred as a whole then just shifts the clock
             * toward whichever side is narrower — visibly off-centre next to
             * the rest face, where a lone clock has nothing to be
             * asymmetric against.
             *
             * Forcing both flanks to this shared width turns the row back
             * into a true three-lane layout (leading / centre / trailing),
             * so the clock lands on the pill's actual centre regardless of
             * which side is fuller. Each flank's content still hugs its
             * OUTER edge within the lane (dots against the leading edge,
             * icons against the trailing edge) rather than being centred in
             * the extra space, so the gap right next to the clock stays the
             * same 26·s on both sides instead of ballooning on whichever
             * side is shorter.
             */
            readonly property real sideLane: Math.max(wsDots.implicitWidth, trailGroup.implicitWidth)

            // Per-monitor Hyprland workspace dots: active = primary stick,
            // click-to-focus, range from Workspacerules with live fallback.
            // (`wsDots` is the id the soul bead will later retarget between.)
            Item {
                id: leadLane
                anchors.verticalCenter: parent.verticalCenter
                width: hoverRow.sideLane
                height: wsDots.implicitHeight

                Workspaces {
                    id: wsDots
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: implicitWidth
                    s: pill.s
                    screenName: pill.screenName
                    // Adaptive, not fixed: `sideLane` forces BOTH flanks to
                    // match whichever is wider, so every dot this side gains
                    // past 5 costs the pill 2 dot-pitches, not 1 — a screen
                    // with 8+ workspaces was making the whole pill visibly
                    // long even though the trailing side never grew. Tighten
                    // the pitch as the count climbs (8·s down to a 4·s floor)
                    // instead, so the lane — and the pill with it — grows
                    // sublinearly rather than in lockstep with dot count.
                    gap: Math.max(4, 8 - Math.max(0, wsDots.range.length - 5)) * pill.s
                    enabled: hover.live
                    transform: ZoneRise { delay: 0 }
                    onHoverIndexChanged: if (hoverIndex >= 0) {
                        pill.soulTarget = "ws";
                        pill.soulWsIndex = hoverIndex;
                    }
                }
            }

            // HH:mm over a small dim ddd d MMM date column (Ricelin
            // Pill.qml:1286–1324); tapping it opens the calendar surface.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: hoverClock.implicitWidth
                height: hoverClock.implicitHeight
                transform: ZoneRise { delay: 50 }

                Column {
                    id: hoverClock
                    anchors.centerIn: parent
                    spacing: 2 * pill.s

                    // Two stacked lines pressed as one block, so 0.96 rather
                    // than the 0.92 the single status glyphs take.
                    scale: clockArea.pressed ? 0.96 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    TickText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        live: hover.live
                        text: clock.hhmm
                        font.pixelSize: 18 * pill.s
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clock.date
                        color: Qt.alpha(Colors.on_surface_variant, 0.8)
                        font.family: Appearance.font.family
                        font.pixelSize: 8.5 * pill.s
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.6 * pill.s
                    }
                }

                MouseArea {
                    id: clockArea
                    anchors.centerIn: parent
                    width: hoverClock.implicitWidth + 22 * pill.s
                    height: hoverClock.implicitHeight + 10 * pill.s
                    enabled: hover.live
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.requestSurface("calendar")

                    // Read out as the time it shows, not as "clock" — the
                    // reason to reach for it is the date it is about to open.
                    Accessible.role: Accessible.Button
                    Accessible.name: clock.hhmm + ", " + clock.date
                    Accessible.description: "Opens the calendar"
                    Accessible.focusable: true
                    Accessible.onPressAction: pill.requestSurface("calendar")
                }
            }

            // Status icons — glyph visuals are static this stage (live
            // wifi/battery/volume/notification state lands with the surface
            // agents); every glyph with a home surface opens it on click.
            //
            // Wrapped in a lane (see `hoverRow.sideLane` above) so this
            // group's content hugs the pill's TRAILING edge instead of
            // centring in whatever extra width the lane carries to match the
            // workspace dots — the gap next to the clock stays constant on
            // both sides that way, and the group as a whole still balances
            // against `leadLane`.
            Item {
                id: trailLane
                anchors.verticalCenter: parent.verticalCenter
                width: hoverRow.sideLane
                height: trailGroup.implicitHeight

                Row {
                    id: trailGroup
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10 * pill.s

                    // Windows stashed on special:minimized (Super+Shift+M) show
                    // as app-icon chips; click restores to this monitor's active
                    // workspace. Invisible (and skipped by the Row, so the hover
                    // pill doesn't widen) while empty.
                    MinimizedTray {
                        id: minimized
                        anchors.verticalCenter: parent.verticalCenter
                        transform: ZoneRise { delay: 90 }
                        s: pill.s
                        screenName: pill.screenName
                        enabled: hover.live
                        visible: count > 0
                    }

                    // System tray (Ricelin Pill.qml:1391–1396). Invisible (and
                    // skipped by the Row) while no StatusNotifier items live, so
                    // the hover pill only widens when a tray exists. The hover
                    // handler makes the whole cluster a sticky soul-bead target
                    // (astralis adaptation: Ricelin's wider icon row gave tray
                    // items no anchor; the 4-icon astralis row does).
                    Tray {
                        id: trayIcons
                        anchors.verticalCenter: parent.verticalCenter
                        transform: ZoneRise { delay: 110 }
                        s: pill.s
                        barWindow: pill.barWindow
                        enabled: hover.live

                        HoverHandler {
                            enabled: hover.live
                            margin: 4 * pill.s
                            onHoveredChanged: if (hovered) pill.soulTarget = "tray"
                        }
                    }

                    // The shell's own four controls. They read as one cluster
                    // because they sit at a TIGHTER pitch than anything around
                    // them (M3.groupGap against hoverRow's 26), not because a box
                    // is drawn round them — the state layer under the cursor is
                    // the only container any of them ever needs, and it only
                    // exists while it is being aimed at.
                    Row {
                        id: statusIcons
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: M3.groupGap * pill.s

                        StatusGlyph { id: inboxIcon; order: 0;    icon: "inbox";    surface: "notifications"; dot: Services.Notifications.unread > 0; soulKey: "inbox"; accessibleName: "Notifications"; accessibleDescription: Services.Notifications.unread > 0 ? Services.Notifications.unread + " unread" : "No unread notifications" }
                        // The badge lights while a take runs, so the hover row
                        // doubles as the "am I still recording?" answer and the
                        // one-click way back to the stop control.
                        // `video`, not `record`. `record` is a solid disc, and a
                        // filled glyph sitting in a row of stroked outlines reads
                        // as a bullet dropped into the row rather than as the
                        // fourth icon — no size tuning rescues that, because the
                        // mismatch is the DRAWING STYLE, not the ink area. A
                        // camcorder is the same stroked family as the bell, the
                        // gear and the power mark, and says the same thing.
                        StatusGlyph { id: recorderIcon; order: 1; icon: "video"; surface: "recorder"; dot: ScreenRec.busy; soulKey: "recorder"; accessibleName: "Screen recorder"; accessibleDescription: ScreenRec.busy ? "Recording in progress" : "Not recording" }
                        StatusGlyph { id: settingsIcon; order: 2; icon: "cog";      surface: "settings"; soulKey: "settings"; accessibleName: "Settings" }
                        // No `surface`: the power icon opens the standalone full-screen
                        // session menu (requestPower), not a pill surface morph.
                        // `soulKey` still lets the Ame bead ride this icon on hover.
                        StatusGlyph { id: powerIcon; order: 3;    icon: "shutdown"; interactive: true; soulKey: "power"; accessibleName: "Session"; accessibleDescription: "Opens the power menu"; onActivated: pill.requestPower() }
                    }
                }
            }
        }
    }

    // ── toast face — incoming notification content over the pill body ──────
    // Active whenever a popup is queued (so its implicitHeight can drive the
    // toast target size), but only enabled/visible while the pill is actually
    // in toast mode — held/surface modes outrank it in the ladder and the
    // countdown pauses (Toast gates its timer on `live`).
    Loader {
        id: ldToast
        active: pill.toastActive
        anchors.fill: parent
        anchors.topMargin: 12 * pill.s
        anchors.leftMargin: 16 * pill.s
        anchors.rightMargin: 16 * pill.s
        anchors.bottomMargin: 12 * pill.s
        enabled: pill.mode === "toast"
        opacity: pill.mode === "toast" ? Math.pow(pill.morphCloseness, 1.2) : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        sourceComponent: Item {
            implicitHeight: toastContent.implicitHeight

            Toast {
                id: toastContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                s: pill.s
                live: pill.mode === "toast"
                notif: Services.Notifications.popups.length > 0
                    ? Services.Notifications.popups[Services.Notifications.popups.length - 1]
                    : null
            }

            // +N queue counter when several toasts are stacked behind this one.
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: Services.Notifications.popups.length > 1
                text: "+" + (Services.Notifications.popups.length - 1)
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 9 * pill.s
                font.weight: Font.DemiBold
            }
        }
    }

    // ── osd face — volume/brightness/track/battery/workspace flash ─────────
    // A direct child, not a Loader (Ricelin Pill.qml:2038–2055): the Osd's
    // Connections watch Pipewire/Backlight/Players/Battery even while hidden —
    // that watching is what raises `flashing` and morphs the pill here.
    // Suppressed (flash cleared, timers stopped) while a surface is open or
    // the pill is held, matching the ladder rungs above.
    Osd {
        id: osd
        anchors.fill: parent
        anchors.topMargin: 12 * pill.s
        anchors.leftMargin: 18 * pill.s
        anchors.rightMargin: 18 * pill.s
        anchors.bottomMargin: 12 * pill.s
        s: pill.s
        screenName: pill.screenName
        suppressed: pill.surfaceOpen || pill.held
        expanded: pill.expanded
        enabled: pill.mode === "osd"
        opacity: pill.mode === "osd" ? Math.pow(pill.morphCloseness, 1.2) : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
    }

    // ── surface host — one latch-once Loader per surface ────────────────────
    // Eager surfaces would dominate startup; a surface is built synchronously
    // on its first open (surfaceItem latches `active`) and kept forever. Each
    // loader fills the pill so the content anchors as a direct child would.
    // The Loaders carry no opacity/visible gating of their own: PillSurface
    // self-gates from open + morphCloseness + its settled latch, and a second
    // gate here would double-fade every surface.
    Item {
        id: surfaceHost
        anchors.fill: parent

        Loader {
            id: ldMedia
            active: false
            anchors.fill: parent
            sourceComponent: Media {
                s: pill.s
                open: pill.mode === "media"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }

        Loader {
            id: ldCalendar
            active: false
            anchors.fill: parent
            sourceComponent: Calendar {
                s: pill.s
                open: pill.mode === "calendar"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }

        Loader {
            id: ldMixer
            active: false
            anchors.fill: parent
            sourceComponent: Mixer {
                s: pill.s
                open: pill.mode === "mixer"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }


        Loader {
            id: ldLink
            active: false
            anchors.fill: parent
            sourceComponent: Link {
                s: pill.s
                open: pill.mode === "link"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }

        Loader {
            id: ldLauncher
            active: false
            anchors.fill: parent
            sourceComponent: Launcher {
                s: pill.s
                open: pill.mode === "launcher"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }

        Loader {
            id: ldClipboard
            active: false
            anchors.fill: parent
            sourceComponent: Clipboard {
                s: pill.s
                open: pill.mode === "clipboard"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }

        Loader {
            id: ldNotifications
            active: false
            anchors.fill: parent
            // Qualified: unqualified `Notifications` is shadowed by the
            // services singleton of the same name (see the import aliases).
            sourceComponent: Surfaces.Notifications {
                s: pill.s
                open: pill.mode === "notifications"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }

        Loader {
            id: ldSysmon
            active: false
            anchors.fill: parent
            // Qualified: unqualified `Sysmon` is shadowed by the services
            // singleton of the same name (see the import aliases).
            sourceComponent: Surfaces.Sysmon {
                s: pill.s
                open: pill.mode === "sysmon"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }

        Loader {
            id: ldRecorder
            active: false
            anchors.fill: parent
            sourceComponent: Recorder {
                s: pill.s
                open: pill.mode === "recorder"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }

        Loader {
            id: ldSettings
            active: false
            anchors.fill: parent
            // Qualified: unqualified `Settings` is shadowed by the services
            // singleton of the same name (see the import aliases).
            sourceComponent: Surfaces.Settings {
                s: pill.s
                open: pill.mode === "settings"
                morphCloseness: pill.morphCloseness
                onRequestClose: pill.requestClose()
            }
        }
    }

    // Pin toggle. A passive TapHandler so it never swallows pointer events
    // from content stacked above (surface controls get their own clicks).
    // Disabled while a surface is open: a tap on the open-surface padding must
    // NOT re-pin the pill (that would leave it stuck open after the surface
    // closes — the backdrop/close already own dismissal in that state).
    TapHandler {
        enabled: !pill.surfaceOpen
        onTapped: pill.pinned = !pill.pinned
    }
}
