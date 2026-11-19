import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../colors"
import "../../config"
import "../../services"

/**
 * astralis — desktop synced-lyrics widget.
 *
 * Motion follows Apple-Music-like-Lyrics (AMLL, the reference open-source
 * implementation of Apple Music's lyric view):
 *   • every line rides its OWN spring (k 180, c √k·2.2 — AMLL's values) to
 *     the new scroll offset, lines below the new current one starting 45ms
 *     apart, so the column ripples instead of sliding as a slab. Seeks and
 *     jumps move everything at once.
 *   • the sung word lights with a soft-edged gradient sweep (edge ≈ half a
 *     line-height, AMLL's wordFadeWidth) rather than a flat fade.
 *   • neighbours recede by distance: dimmer, smaller, slightly blurred.
 *
 * Colour comes from the cover: lit text runs accent → accent2 across the line
 * (TrackInfo), unsung ink is faintly tinted, the current line glows in the
 * deep accent.
 *
 * No glitch on line change: everything that differs between the current line
 * and the others (ink alpha, lit layer, lift, glow) is driven by one animated
 * `act` value, and effect layers stay enabled for every line near the centre
 * so nothing toggles while visible.
 *
 * Timing: a local clock advances per frame from the last MPRIS position and
 * re-syncs once a second. Word timing within a line is estimated (see
 * services/Lyrics.qml). WlrLayer.Bottom, fully click-through.
 */
PanelWindow {
    id: win

    property real s: 1
    property int layer: WlrLayer.Bottom
    /** Screen size in logical px; geometry comes from Widgets.lyrics as fractions of it. */
    property real sw: 1920
    property real sh: 1080
    readonly property var cfg: Widgets.lyrics
    readonly property real inset: Math.round(28 * s)
    readonly property real viewW: Math.max(60, cfg.w * sw - inset * 2)
    readonly property real fontPx: Math.round(cfg.size * s)
    readonly property bool centered: cfg.align === "center"
    readonly property bool righted: cfg.align === "right"
    /** Where the current line's centre sits, as a fraction of the height. */
    readonly property real anchorAt: Math.max(0.1, Math.min(0.9, cfg.anchor))
    readonly property real gapPx: Math.round(fontPx * 0.52 * cfg.spacing)
    readonly property string romanMode: cfg.roman

    // How many lines show before / after the current one: as many as fit in
    // the box (a smaller widget shows fewer), optionally capped by `lines`.
    readonly property real lineStep: fontPx * 1.45 + gapPx + (romanMode === "below" ? fontPx * 0.75 : 0)
    readonly property int fitAbove: Math.max(0, Math.floor((stage.height * anchorAt - lineStep * 0.5) / lineStep + 0.35))
    readonly property int fitBelow: Math.max(0, Math.floor((stage.height * (1 - anchorAt) - lineStep * 0.5) / lineStep + 0.35))
    readonly property int showAbove: Math.min(8, cfg.lines > 0 ? Math.min(cfg.lines, fitAbove) : fitAbove)
    readonly property int showBelow: Math.min(8, cfg.lines > 0 ? Math.min(cfg.lines, fitBelow) : fitBelow)
    readonly property int reach: Math.max(showAbove, showBelow)

    // Lit-text gradient (start → end across the line) and the current-line glow.
    readonly property color litA: cfg.ink === "theme" ? Colors.primary : cfg.ink === "mono" ? Qt.rgba(1, 1, 1, 1) : TrackInfo.accent
    readonly property color litB: cfg.ink === "theme" ? Colors.tertiary : cfg.ink === "mono" ? Qt.rgba(0.92, 0.92, 0.95, 1) : TrackInfo.accent2
    readonly property color glowC: cfg.ink === "theme" ? Colors.primary : cfg.ink === "mono" ? Qt.rgba(1, 1, 1, 0.55) : TrackInfo.accentDeep

    readonly property bool shown: Players.has && Lyrics.has
    /** fill "write": lines are hidden until sung; the current line's characters
     *  then appear one by one as the singing reaches them — each wipes in from
     *  the left while fading up and settling down onto the line, on its own
     *  easing (not tied frame-by-frame to the clock), so neighbours overlap. */
    readonly property bool writeMode: cfg.fill === "write"

    color: "transparent"
    WlrLayershell.layer: win.layer
    WlrLayershell.namespace: "astralis-lyrics"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.left: true
    anchors.top: true
    margins.left: Math.round(cfg.x * sw)
    margins.top: Math.round(cfg.y * sh)
    implicitWidth: Math.round(Math.max(80, cfg.w * sw))
    implicitHeight: Math.round(Math.max(40, cfg.h * sh))
    visible: stage.opacity > 0.001
    mask: Region {}

    // ── clock ──────────────────────────────────────────────────────────────
    property real pos: 0
    /** Lyrics lead the player by this much: MPRIS lag + the user sync offset. */
    readonly property real shift: Lyrics.lead + (cfg.offset || 0)
    onShiftChanged: if (!Players.playing) resync()
    property real basePos: 0
    property real baseAt: 0
    readonly property int cur: Lyrics.has ? Lyrics.lineAt(pos) : -1

    function now() {
        return Date.now() / 1000;
    }

    function resync() {
        if (!Players.active)
            return;
        Players.active.positionChanged();
        var p = Players.position;
        var t = now();
        var predicted = win.basePos + (Players.playing ? t - win.baseAt : 0);
        // Only jump on real drift (seek, track change) so the per-frame clock
        // stays smooth between MPRIS reads.
        if (Math.abs(predicted - p) > 0.25 || !Players.playing) {
            win.basePos = p;
            win.baseAt = t;
        }
        var np = (Players.playing ? win.basePos + (t - win.baseAt) : win.basePos) + win.shift;
        // Same rule as step(): no small rewinds while playing.
        if (!Players.playing || np >= win.pos || win.pos - np > 1)
            win.pos = np;
    }

    Timer {
        interval: 1000
        repeat: true
        running: win.visible || win.shown
        triggeredOnStart: true
        onTriggered: win.resync()
    }
    Connections {
        target: TrackInfo
        function onKeyChanged() {
            win.basePos = 0;
            win.baseAt = win.now();
            win.resync();
        }
    }

    // ── per-line springs ───────────────────────────────────────────────────
    readonly property real springK: 180
    readonly property real springC: Math.sqrt(springK) * 2.2
    readonly property real stagger: Motion.reduceMotion ? 0 : 0.045

    property int prevCur: -1
    property real switchAt: 0
    property bool staggered: false
    property bool settling: true

    onCurChanged: {
        win.staggered = Math.abs(win.cur - win.prevCur) === 1;
        win.prevCur = win.cur;
        win.switchAt = now();
        win.settling = true;
    }
    onHeightChanged: settling = true

    /** Scroll offset that puts the current (or first upcoming) line at the anchor.
     *  A binding, so a re-layout (fonts, wrapping) also wakes the springs. */
    readonly property Item anchorLine: lineRep.count > 0 ? lineRep.itemAt(Math.max(0, Math.min(lineRep.count - 1, cur))) : null
    readonly property real offTarget: anchorLine
        ? stage.height * anchorAt - (anchorLine.y + anchorLine.height / 2)
        : stage.height * anchorAt
    onOffTargetChanged: settling = true

    property real lastFrame: 0
    function step() {
        var t = now();
        var dt = Math.min(0.1, Math.max(0, t - win.lastFrame));   // AMLL MAX_FRAME_DELTA
        win.lastFrame = t;
        if (Players.playing) {
            var np = win.basePos + (t - win.baseAt) + win.shift;
            // A position read a little behind our clock would step the
            // lyrics back (flipping a line that just started back to the one
            // before); hold instead until the clock catches up. Real seeks
            // back are larger and still jump.
            if (np >= win.pos || win.pos - np > 1)
                win.pos = np;
        }
        if (!win.settling)
            return;
        var target = win.offTarget;
        var moving = false;
        for (var i = 0; i < lineRep.count; i++) {
            var it = lineRep.itemAt(i);
            if (!it)
                continue;
            var d = i - win.cur;
            if (!it.placed || Math.abs(d) > win.reach + 2 || Motion.reduceMotion) {
                it.ty = target;
                it.vy = 0;
                it.placed = true;
                continue;
            }
            var delay = win.staggered ? Math.max(0, d) * win.stagger : 0;
            if (t - win.switchAt < delay) {
                moving = true;
                continue;
            }
            // Semi-implicit Euler in two half steps — stable at 30–240Hz.
            for (var k = 0; k < 2; k++) {
                var h = dt / 2;
                var a = -win.springK * (it.ty - target) - win.springC * it.vy;
                it.vy += a * h;
                it.ty += it.vy * h;
            }
            if (Math.abs(it.ty - target) > 0.25 || Math.abs(it.vy) > 2)
                moving = true;
            else {
                it.ty = target;
                it.vy = 0;
            }
        }
        win.settling = moving;
    }

    FrameAnimation {
        running: win.visible && (Players.playing || win.settling)
        onRunningChanged: if (running) win.lastFrame = win.now()
        onTriggered: win.step()
    }
    // New lyrics (track change) → place every line again.
    Connections {
        target: Lyrics
        function onLinesChanged() { win.settling = true; }
    }

    function hasCJK(t) {
        return /[぀-ヿ㐀-鿿가-힯]/.test(t);
    }

    function mix(a, b, f) {
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f);
    }

    // ── view ───────────────────────────────────────────────────────────────
    Item {
        id: stage
        anchors.fill: parent
        opacity: win.shown ? (Players.playing ? 1 : 0.55) : 0
        Behavior on opacity { NumberAnimation { duration: Motion.largeDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }

        // Optional backdrop for legibility on busy wallpapers. Soft is a shade
        // on the words themselves; Solid is a rounded cover-tinted card.
        readonly property color tint: win.mix(Colors.surface, TrackInfo.accentDeep, 0.14)
        readonly property bool soft: win.cfg.backdrop === "soft"
        Rectangle {
            id: backdrop
            anchors.fill: parent
            radius: Appearance.rounding.large * 1.4 * win.s
            visible: win.cfg.backdrop === "solid"
            color: Qt.alpha(stage.tint, 0.72)
            border.width: 1
            border.color: Qt.alpha(Colors.on_surface, 0.07)
            Behavior on color { ColorAnimation { duration: Motion.largeDur } }
        }

        Column {
            id: col
            x: win.inset
            width: win.viewW
            spacing: win.gapPx

            Repeater {
                id: lineRep
                model: Lyrics.lines

                Item {
                    id: line
                    required property var modelData
                    required property int index

                    // Spring state, driven by win.step().
                    property real ty: 0
                    property real vy: 0
                    property bool placed: false
                    // A gap's height animating (dots ↔ lyrics) moves every row
                    // below it in the Column at once, before their staggered
                    // springs start — the next line jumped, then got pulled
                    // back. Absorb layout moves into the spring offset so only
                    // the springs ever move a line on screen.
                    property real layY: 0
                    onYChanged: {
                        if (placed) {
                            ty -= y - layY;
                            win.settling = true;
                        }
                        layY = y;
                    }

                    readonly property int dist: index - win.cur
                    readonly property bool current: dist === 0
                    readonly property bool near: Math.abs(dist) <= win.reach
                    /** What is drawn: the line, or its romanized re-timing ("replace"). */
                    readonly property var src: win.romanMode === "replace" && Lyrics.romanLines.length > index ? Lyrics.romanLines[index] : modelData
                    /** Romanization shown under the line ("below"). */
                    readonly property string rtext: win.romanMode === "below" && Lyrics.roman.length > index && Lyrics.roman[index] !== modelData.text ? Lyrics.roman[index] : ""
                    readonly property bool cjk: win.hasCJK(src.text)
                    readonly property real prog: current
                        ? Math.max(0, Math.min(1, (win.pos - modelData.t) / modelData.span))
                        : (dist < 0 ? 1 : 0)

                    // 0 → 1 as this line becomes the current one. Everything
                    // that differs between current and other lines reads this.
                    property real act: current ? 1 : 0
                    Behavior on act { NumberAnimation { duration: Motion.normalDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

                    // Instrumental breaks are an ordinary row of fixed height:
                    // their dots scroll in and out with the lines around them.
                    // (They used to grow in only while current, which shoved
                    // every line below down and back again around each break.)
                    readonly property real gapH: 28 * win.s

                    width: col.width
                    height: modelData.gap ? gapH : dimFlow.height + (rtext.length > 0 ? romanText.implicitHeight + 4 * win.s : 0)
                    transform: Translate { y: line.ty }
                    transformOrigin: win.centered ? Item.Center : win.righted ? Item.Right : Item.Left
                    scale: 0.86 + 0.14 * act
                    // Fade by distance over however many lines fit (showAbove /
                    // showBelow); past lines leave faster than upcoming arrive.
                    opacity: {
                        var d = Math.abs(dist);
                        if (d === 0) return 1;
                        var n = dist < 0 ? win.showAbove : win.showBelow;
                        if (d > n) return 0;
                        var f = 1 - (d - 1) / n;
                        return dist < 0 ? 0.36 * Math.pow(f, 1.4) : 0.55 * Math.pow(f, 1.2);
                    }
                    // No `visible` toggle here: Column drops invisible children
                    // from the layout, so a past line fading out past ±4 used to
                    // collapse its slot and yank every line up a row mid-scroll
                    // (springs then chased it back down). Opacity 0 already
                    // skips rendering, and layers only run for `near` lines.
                    Behavior on opacity { NumberAnimation { duration: Motion.normalDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }

                    // One effect per line: distance blur + a shadow that is a
                    // dark legibility shade on far lines and the cover's deep
                    // accent glow on the current one. Enabled for every line
                    // near the centre so it never toggles while visible.
                    // Backdrop Soft widens that shadow into a dark tinted shade
                    // hugging the words (the glow still tints the current
                    // line's); blur is rescaled so the distance blur keeps its
                    // 12 px reach under the larger blurMax.
                    property real blurAmt: win.cfg.blur ? Math.min(1, Math.abs(dist) * 0.22) : 0
                    Behavior on blurAmt { NumberAnimation { duration: Motion.normalDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }
                    layer.enabled: near && win.visible
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        readonly property real glow: win.cfg.glow ? line.act : 0
                        readonly property bool shade: stage.soft
                        blurEnabled: true
                        blurMax: shade ? Math.round(18 * win.s) : 12
                        blur: line.blurAmt * 12 / blurMax
                        shadowEnabled: true
                        shadowColor: shade
                            ? win.mix(Qt.alpha(stage.tint, 1), Qt.alpha(win.glowC, 0.9), 0.4 * glow)
                            : win.mix(Qt.rgba(0, 0, 0, 0.55), Qt.alpha(win.glowC, 0.9), glow)
                        shadowBlur: shade ? 1 : 0.6 + 0.35 * glow
                        shadowScale: shade ? 1.02 : 1
                        shadowVerticalOffset: shade ? 0 : 2 * win.s * (1 - glow)
                        shadowHorizontalOffset: 0
                    }

                    // ── instrumental gap: three dots fill as it passes ─────
                    Row {
                        visible: line.modelData.gap
                        x: win.centered ? (parent.width - width) / 2 : win.righted ? parent.width - width : 0
                        spacing: 12 * win.s
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                // Fill one by one across the break; a passed break stays
                                // lit as it scrolls away instead of snapping back to dim.
                                readonly property real f: line.dist < 0 ? 1 : line.current
                                    ? Math.max(0, Math.min(1, ((win.pos - line.modelData.t) / Math.max(0.5, line.modelData.end - line.modelData.t - 0.3)) * 3 - index))
                                    : 0
                                width: 12 * win.s
                                height: width
                                radius: width / 2
                                color: win.mix(Qt.alpha(TrackInfo.ink, 0.35), index === 1 ? win.litB : win.litA, f)
                                scale: 0.78 + 0.3 * f
                            }
                        }
                    }

                    readonly property real fadeW: win.fontPx * 0.5
                    readonly property real litOpacity: act
                    /** Write mode: inked character by character while current, and while fading out after. */
                    readonly property bool writing: win.writeMode && !modelData.gap && (current || act > 0.001)

                    // ── dim ink (layout master) ────────────────────────────
                    // Word placement, computed here (not a Flow) so wrapped
                    // lines can centre row by row.
                    property var place: []
                    function relayout() {
                        var maxW = col.width, rows = [], row = [], x = 0, lh = 0, i, it;
                        for (i = 0; i < dimRep.count; i++) {
                            it = dimRep.itemAt(i);
                            if (!it)
                                return;
                            lh = Math.max(lh, it.height);
                            if (row.length > 0 && x + it.textW > maxW) {
                                rows.push(row);
                                row = [];
                                x = 0;
                            }
                            row.push(i);
                            x += it.width;
                        }
                        if (row.length)
                            rows.push(row);
                        var out = [];
                        for (var r = 0; r < rows.length; r++) {
                            var ws = rows[r], used = 0;
                            for (var j = 0; j < ws.length; j++)
                                used += j === ws.length - 1 ? dimRep.itemAt(ws[j]).textW : dimRep.itemAt(ws[j]).width;
                            var cx = win.centered ? (maxW - used) / 2 : win.righted ? maxW - used : 0;
                            for (var k = 0; k < ws.length; k++) {
                                out[ws[k]] = { x: cx, y: r * lh };
                                cx += dimRep.itemAt(ws[k]).width;
                            }
                        }
                        line.place = out;
                        dimFlow.height = rows.length * lh;
                    }
                    Timer {
                        id: relayoutTimer
                        interval: 0
                        onTriggered: line.relayout()
                    }
                    onWidthChanged: relayoutTimer.restart()
                    Connections {
                        target: win
                        function onCenteredChanged() { relayoutTimer.restart(); }
                        function onRightedChanged() { relayoutTimer.restart(); }
                    }

                    Item {
                        id: dimFlow
                        visible: !line.modelData.gap
                        width: parent.width
                        Repeater {
                            id: dimRep
                            model: line.src.words
                            onCountChanged: relayoutTimer.restart()
                            Item {
                                id: word
                                required property var modelData
                                required property int index
                                readonly property real textW: dimText.implicitWidth
                                x: line.place[index] ? line.place[index].x : 0
                                y: line.place[index] ? line.place[index].y : 0
                                onWidthChanged: relayoutTimer.restart()
                                onHeightChanged: relayoutTimer.restart()
                                readonly property real fill: line.dist < 0 ? 1 : line.current && win.cfg.fill === "line" ? 1 : line.current
                                    ? Math.max(0, Math.min(1, (line.prog - modelData.a) / Math.max(0.0001, modelData.b - modelData.a)))
                                    : 0
                                readonly property int chars: Array.from(modelData.text).length
                                readonly property real baseY: dimText.baselineOffset
                                // Written words stay on the line (ink doesn't hop).
                                readonly property real lift: win.writeMode ? 0 : fill * fill * (3 - 2 * fill) * 3 * win.s * line.act
                                width: dimText.implicitWidth + (modelData.space ? spaceM.advanceWidth(" ") : 0)
                                height: dimText.implicitHeight
                                Text {
                                    renderType: Text.QtRendering
                                    id: dimText
                                    y: -word.lift
                                    text: word.modelData.text
                                    // Write mode: nothing shows before it is written — upcoming
                                    // lines and the current line's unsung text are hidden (the
                                    // lit layer writes the line in); a finished line hands over
                                    // from its lit ink to this dim ink as `act` falls.
                                    color: Qt.alpha(TrackInfo.ink, (0.9 - 0.52 * line.act)
                                                    * (!win.writeMode ? 1 : line.dist < 0 ? 1 - line.act : 0))
                                    font.family: line.cjk ? Appearance.font.jp : Appearance.font.family
                                    font.pixelSize: win.fontPx
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    // ── lit text: accent → accent2 across the line ─────────
                    Item {
                        id: litLayer
                        width: dimFlow.width
                        height: dimFlow.height
                        visible: !line.modelData.gap && line.litOpacity > 0.001
                        opacity: line.litOpacity
                        // Write mode reveals per character below; no sweep mask.
                        layer.enabled: visible && !line.writing
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: sweep
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                        }
                        Item {
                            width: dimFlow.width
                            Repeater {
                                model: line.src.words
                                Item {
                                    required property var modelData
                                    required property int index
                                    readonly property Item twin: line.place.length >= 0 ? dimRep.itemAt(index) : null
                                    x: line.place[index] ? line.place[index].x : 0
                                    y: line.place[index] ? line.place[index].y : 0
                                    width: twin ? twin.width : 0
                                    height: twin ? twin.height : 0
                                    readonly property color ink: win.mix(win.litA, win.litB,
                                                                         twin ? Math.min(1, (twin.x + twin.width / 2) / Math.max(1, dimFlow.width * 0.8)) : 0)
                                    Text {
                                        renderType: Text.QtRendering
                                        visible: !line.writing
                                        y: parent.twin ? -parent.twin.lift : 0
                                        text: parent.modelData.text
                                        color: parent.ink
                                        font.family: line.cjk ? Appearance.font.jp : Appearance.font.family
                                        font.pixelSize: win.fontPx
                                        font.weight: Font.DemiBold
                                    }
                                    // Write mode: one clipped window per character onto the whole
                                    // word (so kerning matches the dim text exactly).
                                    Repeater {
                                        id: chRep
                                        readonly property var chs: line.writing ? Array.from(parent.modelData.text) : []
                                        readonly property Item word: parent
                                        model: chs.length
                                        Item {
                                            id: cell
                                            required property int index
                                            readonly property Item w: chRep.word.twin
                                            readonly property FontMetrics fm: line.cjk ? jpM : spaceM
                                            readonly property bool last: index === chRep.chs.length - 1
                                            readonly property real x0: fm.advanceWidth(chRep.chs.slice(0, index).join(""))
                                            // The edge cells reach past the advance so overhanging ink isn't cut.
                                            readonly property real padL: index === 0 ? 0.2 * win.fontPx : 0
                                            readonly property real full: fm.advanceWidth(chRep.chs[index] || "") + padL + (last ? 0.2 * win.fontPx : 0)
                                            /** The singing has reached this character. */
                                            readonly property bool on: !!w && (w.fill >= 1 || w.fill > index / chRep.chs.length)
                                            property real p: on ? 1 : 0
                                            Behavior on p { NumberAnimation { duration: Motion.normalDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                                            x: x0 - padL
                                            width: full * p
                                            height: chRep.word.height
                                            clip: true
                                            visible: p > 0
                                            Text {
                                                renderType: Text.QtRendering
                                                x: -cell.x
                                                y: (1 - cell.p) * 0.12 * win.fontPx
                                                opacity: Math.min(1, cell.p * 1.6)
                                                text: chRep.word.modelData.text
                                                color: chRep.word.ink
                                                font.family: line.cjk ? Appearance.font.jp : Appearance.font.family
                                                font.pixelSize: win.fontPx
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── sweep mask: per word, a solid strip with a soft
                    //    trailing edge that slides across as it is sung ─────
                    Item {
                        id: sweep
                        width: dimFlow.width
                        height: dimFlow.height
                        visible: false
                        layer.enabled: litLayer.visible && !line.writing
                        Repeater {
                            model: litLayer.visible && !line.writing ? line.src.words : []
                            Item {
                                required property int index
                                readonly property Item twin: line.place.length >= 0 ? dimRep.itemAt(index) : null
                                readonly property real w: twin ? twin.width : 0
                                x: line.place[index] ? line.place[index].x : 0
                                y: line.place[index] ? line.place[index].y : 0
                                width: w
                                height: twin ? twin.height : 0
                                clip: true
                                Rectangle {
                                    id: strip
                                    readonly property real span: parent.w + line.fadeW
                                    readonly property real cut: parent.w / Math.max(1, span)
                                    width: span
                                    height: parent.height
                                    x: (parent.twin ? parent.twin.fill : 0) * span - span
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: "white" }
                                        GradientStop { position: strip.cut; color: "white" }
                                        GradientStop { position: 1; color: "transparent" }
                                    }
                                }
                            }
                        }
                    }

                    // ── romanization under the line ("below") ──────────────
                    Text {
                        renderType: Text.QtRendering
                        id: romanText
                        visible: line.rtext.length > 0
                        y: dimFlow.height + 4 * win.s
                        width: parent.width
                        text: line.rtext
                        wrapMode: Text.WordWrap
                        horizontalAlignment: win.centered ? Text.AlignHCenter : win.righted ? Text.AlignRight : Text.AlignLeft
                        color: win.mix(Qt.alpha(TrackInfo.ink, 0.6), win.litA, line.act * 0.85)
                        // Write mode: upcoming lines' romanization stays hidden with them.
                        opacity: win.writeMode && line.dist > 0 ? 0 : 1
                        // Eases in as the line becomes current instead of
                        // snapping on while the line itself is still writing in.
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Motion.normalDur
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.standardCurve
                            }
                        }
                        font.family: Appearance.font.family
                        font.pixelSize: Math.round(win.fontPx * 0.5)
                        font.weight: Font.Medium
                    }
                }
            }
        }

        FontMetrics {
            id: jpM
            font.family: Appearance.font.jp
            font.pixelSize: win.fontPx
            font.weight: Font.DemiBold
        }
        FontMetrics {
            id: spaceM
            font.family: Appearance.font.family
            font.pixelSize: win.fontPx
            font.weight: Font.DemiBold
        }
    }
}
