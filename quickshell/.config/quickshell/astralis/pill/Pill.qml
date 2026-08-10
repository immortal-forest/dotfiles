pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import "../colors"
import "../services"
import "../config"
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
        sysmon:    { size: () => { surfaceItem(ldSysmon);    return Qt.size(392 * s, 245 * s); }, ame: () => surfaceItem(ldSysmon) }
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

    readonly property size targetSize: {
        const sf = Object.prototype.hasOwnProperty.call(surfaces, mode) ? surfaces[mode] : undefined;
        if (sf)
            return sf.size();
        const f = Object.prototype.hasOwnProperty.call(modeSize, mode) ? modeSize[mode] : undefined;
        return f ? f() : Qt.size(Math.max(restW, restRow.implicitWidth + 36 * s), restH);
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
        NumberAnimation { target: pill; property: "kanjiFlash"; to: 1; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: pill; property: "kanjiFlash"; to: 0; duration: 320; easing.type: Easing.OutCubic }
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
    Rectangle {
        id: body
        anchors.fill: parent
        radius: pill.morphRadius
        border.width: 1
        border.color: Qt.alpha(Colors.outline_variant, 0.6)

        // Subtle two-stop vertical depth; each stop animates so a matugen
        // retheme sweeps through the body instead of snapping.
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Colors.surface_container_high
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
            GradientStop {
                position: 1.0
                color: Colors.surface_container
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, Appearance.elevation.shadowOpacity)
            shadowBlur: 0.7
            shadowVerticalOffset: 3 * pill.s
        }

        // 1px top sheen hairline, inset by the corner radius so it never
        // clips across the curve.
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: body.radius * 0.6
            anchors.rightMargin: body.radius * 0.6
            height: 1
            color: Qt.alpha(Colors.on_surface, 0.06)
        }
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
        if (soulTarget === "tray") {
            void trayIcons.implicitWidth;
            return trayIcons.mapToItem(pill, trayIcons.width / 2, trayIcons.height + drop * 0.3);
        }
        if (soulTarget === "inbox")
            return inboxIcon.mapToItem(pill, inboxIcon.width / 2, inboxIcon.height + drop * 0.55);
        if (soulTarget === "power")
            return powerIcon.mapToItem(pill, powerIcon.width / 2, powerIcon.height + drop * 0.55);
        if (soulTarget === "settings")
            return settingsIcon.mapToItem(pill, settingsIcon.width / 2, settingsIcon.height + drop * 0.55);
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
        Behavior on opacity { NumberAnimation { duration: pill.mode === "rest" ? Motion.fast : Motion.glide } }

        Row {
            id: restRow
            anchors.centerIn: parent
            spacing: 9 * pill.s

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
                    styleColor: Qt.alpha(Colors.tertiary,
                        Math.min(1, (pill.mode === "rest" || !pill.hoverSoulGate ? 0.5 : 0) + pill.kanjiFlash))
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

            Text {
                visible: pill.specialView === ""
                anchors.verticalCenter: parent.verticalCenter
                text: clock.hhmm
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 16 * pill.s
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
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
        }

        // ── privacy indicators (iOS-style) ──────────────────────────────
        // Something capturing the mic / camera / screen shows as a tiny
        // pulsing glyph tucked against the right edge of the resting pill.
        // Anchored outside restRow so appearing never recenters the kanji +
        // clock and never feeds the rest width target (the pill does not
        // widen); living inside the rest face keeps them rest-only — the
        // hover row, toast/osd flashes and open surfaces stay clean.
        Row {
            id: privacyRow
            anchors.right: parent.right
            anchors.rightMargin: 9 * pill.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * pill.s

            component PrivacyDot: Item {
                id: pdot
                property alias glyph: pdotGlyph.text
                property alias tint: pdotGlyph.color
                property bool active: false
                width: 10 * pill.s
                height: 10 * pill.s
                opacity: active ? 1 : 0
                visible: opacity > 0.01
                scale: active ? 1 : 0.5
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                Text {
                    id: pdotGlyph
                    anchors.centerIn: parent
                    font.family: Appearance.font.symbols
                    font.pixelSize: 10 * pill.s

                    // Subtle breath so an active capture reads live, not stuck.
                    // Gated on the rest face actually showing, so no infinite
                    // animation ticks behind an open surface.
                    SequentialAnimation on opacity {
                        running: pdot.active && rest.visible && !Motion.reduceMotion
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: Motion.pulse * 2; easing.type: Motion.easeStandard }
                        NumberAnimation { to: 1;    duration: Motion.pulse * 2; easing.type: Motion.easeStandard }
                    }
                }
            }

            PrivacyDot { active: Privacy.micActive;    glyph: "mic";          tint: Colors.tertiary }
            PrivacyDot { active: Privacy.cameraActive; glyph: "videocam";     tint: Colors.primary }
            PrivacyDot { active: Privacy.screenActive; glyph: "screen_share"; tint: Colors.error }
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
        Behavior on opacity { NumberAnimation { duration: pill.mode === "hover" ? Motion.fast : 0 } }

        // This face stays visible at opacity 0 (see above), so every
        // interactive bit inside it must gate on `live` or an invisible
        // hover face would swallow clicks meant for the rest face / surfaces.
        readonly property bool live: pill.mode === "hover"

        // 17*s status-icon slot: a Material Symbols glyph in a fixed box.
        // A non-empty `surface` makes it clickable → requestSurface(surface)
        // (exclusive-grab tap so the pill's pin TapHandler doesn't also fire).
        component StatusGlyph: Item {
            id: statusGlyph
            property alias glyph: glyphText.text
            property string surface: ""
            property string soulKey: ""
            property bool dot: false
            // A glyph is clickable either because it owns a pill surface
            // (surface non-empty) or because it does something else on tap
            // (the power icon: `activated()` opens the full-screen session
            // menu, no surface morph involved) — set explicitly for those.
            property bool interactive: surface !== ""
            signal activated()
            width: 17 * pill.s
            height: 17 * pill.s

            Text {
                id: glyphText
                anchors.centerIn: parent
                color: glyphHover.hovered ? Colors.on_surface : Colors.on_surface_variant
                font.family: Appearance.font.symbols
                font.pixelSize: Appearance.font.sizeL * pill.s
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            // Top-right badge (the inbox unread dot).
            Rectangle {
                visible: statusGlyph.dot
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -2 * pill.s
                anchors.rightMargin: -2 * pill.s
                width: 5 * pill.s
                height: 5 * pill.s
                radius: width / 2
                color: Colors.primary
            }

            HoverHandler {
                id: glyphHover
                enabled: hover.live && statusGlyph.interactive
                margin: 6 * pill.s
                cursorShape: Qt.PointingHandCursor
            }

            // Sticky soul-bead retarget (A.4): entering this glyph writes its
            // key; nothing clears it on exit, so the bead parks here and only
            // moves when another target claims it — icon→icon, never via home.
            HoverHandler {
                enabled: hover.live && statusGlyph.soulKey !== ""
                margin: 6 * pill.s
                onHoveredChanged: if (hovered) pill.soulTarget = statusGlyph.soulKey
            }

            TapHandler {
                enabled: hover.live && statusGlyph.interactive
                margin: 6 * pill.s
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    if (statusGlyph.surface !== "")
                        pill.requestSurface(statusGlyph.surface);
                    statusGlyph.activated();
                }
            }
        }

        Row {
            id: hoverRow
            anchors.centerIn: parent
            spacing: 20 * pill.s

            // Per-monitor Hyprland workspace dots: active = primary stick,
            // click-to-focus, range from Workspacerules with live fallback.
            // (`wsDots` is the id the soul bead will later retarget between.)
            Workspaces {
                id: wsDots
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                s: pill.s
                screenName: pill.screenName
                gap: 8 * pill.s
                enabled: hover.live
                onHoverIndexChanged: if (hoverIndex >= 0) {
                    pill.soulTarget = "ws";
                    pill.soulWsIndex = hoverIndex;
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 22 * pill.s
                color: Qt.alpha(Colors.outline_variant, 0.7)
            }

            // HH:mm over a small dim ddd d MMM date column (Ricelin
            // Pill.qml:1286–1324); tapping it opens the calendar surface.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: hoverClock.implicitWidth
                height: hoverClock.implicitHeight

                Column {
                    id: hoverClock
                    anchors.centerIn: parent
                    spacing: 2 * pill.s

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: clock.hhmm
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 18 * pill.s
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
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
                    anchors.centerIn: parent
                    width: hoverClock.implicitWidth + 22 * pill.s
                    height: hoverClock.implicitHeight + 10 * pill.s
                    enabled: hover.live
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.requestSurface("calendar")
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 22 * pill.s
                color: Qt.alpha(Colors.outline_variant, 0.7)
            }

            // Status icons — glyph visuals are static this stage (live
            // wifi/battery/volume/notification state lands with the surface
            // agents); every glyph with a home surface opens it on click.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12 * pill.s

                // Windows stashed on special:minimized (Super+Shift+M) show
                // as app-icon chips; click restores to this monitor's active
                // workspace. Invisible (and skipped by the Row, so the hover
                // pill doesn't widen) while empty.
                MinimizedTray {
                    id: minimized
                    anchors.verticalCenter: parent.verticalCenter
                    s: pill.s
                    screenName: pill.screenName
                    enabled: hover.live
                    visible: count > 0
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: minimized.count > 0
                    width: 1
                    height: 14 * pill.s
                    color: Qt.alpha(Colors.outline_variant, 0.7)
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
                    s: pill.s
                    barWindow: pill.barWindow
                    enabled: hover.live

                    HoverHandler {
                        enabled: hover.live
                        margin: 4 * pill.s
                        onHoveredChanged: if (hovered) pill.soulTarget = "tray"
                    }
                }

                StatusGlyph { id: inboxIcon;    anchors.verticalCenter: parent.verticalCenter; glyph: "notifications";      surface: "notifications"; dot: Services.Notifications.unread > 0; soulKey: "inbox" }
                StatusGlyph { id: settingsIcon; anchors.verticalCenter: parent.verticalCenter; glyph: "settings";           surface: "settings"; soulKey: "settings" }
                // No `surface`: the power icon opens the standalone full-screen
                // session menu (requestPower), not a pill surface morph. The old
                // in-pill power dock (pill/surfaces/Power.qml) has been deleted;
                // `soulKey` still lets the Ame bead ride this icon on hover.
                StatusGlyph { id: powerIcon;    anchors.verticalCenter: parent.verticalCenter; glyph: "power_settings_new"; interactive: true; soulKey: "power"; onActivated: pill.requestPower() }
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
