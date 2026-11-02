import QtQuick
import QtQuick.Effects
import "../../colors"
import "../../config"
import "../../services"

/**
 * astralis — the song info that goes with the cover-art widget (CoverArt).
 *
 * Widgets.cover.info picks where it goes:
 *   below    a stacked block under the cover
 *   side     a block beside it (infoSide left|right)
 *   overlay  on the cover itself, over a scrim CoverArt draws inside its clip
 *   edge     glyph by glyph along the cover's own outline: a rounded rect
 *            with the cover's corner radius, so it turns into a circle when
 *            the corners do. edgeFlow:
 *              around  one run (title · artist) centred at edgeAngle
 *              split   title on top going clockwise, artist on the bottom
 *                      going counter-clockwise, so both read upright
 *              loop    title · artist repeated all the way round, spaced so
 *                      it closes seamlessly; spins with edgeSpin (s per lap)
 *              side    title · artist hugging one vertical side (infoSide), and
 *                      when longer than it, turning the corner onto the top or
 *                      bottom edge (edgeCorner) — always oriented to read
 *            edgeSide outside|inside, edgeDir cw|ccw, infoGap = distance from the edge.
 *
 * Fills CoverArt's stage; (cx, cy, size, radius) is the cover box. It
 * follows the cover's hover/pause scale and takes no input.
 */
Item {
    id: root

    property real s: 1
    property var cfg: ({})
    property real cx: 0
    property real cy: 0
    property real size: 100
    property real radius: 0
    property real coverScale: 1
    property bool hovered: false

    readonly property string mode: cfg.info ?? "off"
    readonly property bool edge: mode === "edge"
    readonly property bool block: mode === "below" || mode === "side" || mode === "overlay"
    readonly property bool hasText: snap.title.length > 0
    readonly property bool wanted: mode !== "off" && hasText
        && (cfg.infoShow === "hover" ? hovered || Widgets.editing
          : cfg.infoShow === "playing" ? Players.playing || Widgets.editing
          : true)

    /** How far past each cover edge the info reaches (CoverArt sizes its window by it). */
    readonly property real reachL: mode === "side" && cfg.infoSide === "left" ? gap + sideW : edgeReach
    readonly property real reachR: mode === "side" && cfg.infoSide !== "left" ? gap + sideW : edgeReach
    readonly property real reachT: edgeReach
    readonly property real reachB: mode === "below" ? gap + stack.implicitHeight : edgeReach
    readonly property real edgeReach: edge && cfg.edgeSide !== "inside" ? gap + fm1.height + 6 * s : 0

    // ── text ────────────────────────────────────────────────────────────
    readonly property string family: cfg.infoFont && cfg.infoFont.length > 0 ? cfg.infoFont : Appearance.font.family
    readonly property real px: (cfg.infoSize ?? 16) * s
    readonly property real px2: px * (cfg.infoSub ?? 78) / 100
    readonly property int w1: cfg.infoWeight ?? 600
    readonly property int w2: Math.max(300, w1 - 200)
    readonly property real gap: (cfg.infoGap ?? 10) * s
    readonly property real tracking: (cfg.infoTracking ?? 0) / 100
    readonly property real sideW: Math.round(size * 1.15)
    readonly property string sep: ({ dot: "  ·  ", slash: "  /  ", dash: "  —  ", star: "  ✦  " })[cfg.infoSep] ?? "  ·  "

    function cased(t) {
        return cfg.infoCase === "upper" ? t.toUpperCase() : cfg.infoCase === "lower" ? t.toLowerCase() : t;
    }
    function ink(name) {
        return name === "cover" ? TrackInfo.accent : name === "cover2" ? TrackInfo.accent2 : (Colors[name] ?? Colors.on_surface);
    }
    property color c1: ink(cfg.infoColor ?? "on_surface")
    property color c2: Qt.alpha(ink(cfg.infoColor2 ?? "on_surface_variant"), 0.9)
    Behavior on c1 { ColorAnimation { duration: Motion.largeDur } }
    Behavior on c2 { ColorAnimation { duration: Motion.largeDur } }

    /** The texts on screen, latched so a track change fades out → swaps → fades in. */
    property var snap: ({ title: "", artist: "", album: "" })
    function live() {
        if (TrackInfo.title.length === 0 && Widgets.editing)
            return { title: "Song title", artist: "Artist", album: "Album" };
        return { title: TrackInfo.title, artist: TrackInfo.artist, album: TrackInfo.coverAlbum };
    }
    function relatch() {
        var n = live();
        if (n.title === snap.title && n.artist === snap.artist && n.album === snap.album)
            return;
        if (!root.wanted || content.opacity < 0.05) {
            snap = n;
            return;
        }
        swapAnim.restart();
    }
    Connections {
        target: TrackInfo
        function onTitleChanged() { root.relatch(); }
        function onArtistChanged() { root.relatch(); }
        function onCoverAlbumChanged() { root.relatch(); }
    }
    Connections {
        target: Widgets
        function onEditingChanged() { root.relatch(); }
    }
    Component.onCompleted: snap = live()
    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: content; property: "swapFade"; to: 0; duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
        ScriptAction { script: root.snap = root.live() }
        NumberAnimation { target: content; property: "swapFade"; to: 1; duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }

    /** Lines of the stacked block / runs of the edge text: [{ text, role }] (0 title, 1 detail, 2 separator). */
    readonly property var details: {
        var f = cfg.infoFields ?? "artist";
        var out = [];
        if (f !== "title" && snap.artist.length > 0)
            out.push(cased(snap.artist));
        if (f === "album" && snap.album.length > 0 && snap.album !== snap.title)
            out.push(cased(snap.album));
        return out;
    }

    FontMetrics { id: fm1; font.family: root.family; font.pixelSize: root.px; font.weight: root.w1 }
    FontMetrics { id: fm2; font.family: root.family; font.pixelSize: root.px2; font.weight: root.w2 }

    Item {
        id: content
        anchors.fill: parent
        property real swapFade: 1
        opacity: (root.wanted ? 1 : 0) * swapFade * (Players.playing || Widgets.editing ? 1 : 0.65)
        visible: opacity > 0.001
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }

        transform: Scale {
            origin.x: root.cx
            origin.y: root.cy
            xScale: root.coverScale
            yScale: root.coverScale
        }

        layer.enabled: root.cfg.infoShadow ?? true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha("#000000", 0.6)
            shadowBlur: 0.55
            shadowVerticalOffset: 1
            blurMax: 24
        }

        // ── stacked block: below / side / overlay ────────────────────────
        Column {
            id: stack
            visible: root.block
            readonly property string align: root.cfg.infoAlign ?? "start"
            readonly property bool leftSide: root.cfg.infoSide === "left"
            readonly property real m: Math.max(14 * root.s, root.radius * 0.32)
            readonly property real l: root.cx - root.size / 2
            readonly property real t: root.cy - root.size / 2
            width: root.mode === "side" ? root.sideW : root.mode === "overlay" ? root.size - m * 2 : root.size
            x: root.mode === "side" ? (leftSide ? l - root.gap - width : l + root.size + root.gap)
             : root.mode === "overlay" ? l + m : l
            y: root.mode === "below" ? t + root.size + root.gap
             : root.mode === "overlay" ? t + root.size - m - height
             : align === "center" ? root.cy - height / 2 : align === "end" ? t + root.size - height : t
            spacing: 3 * root.s

            readonly property int hAlign: root.mode === "side" ? (leftSide ? Text.AlignRight : Text.AlignLeft)
                : align === "center" ? Text.AlignHCenter : align === "end" ? Text.AlignRight : Text.AlignLeft

            Text {
                width: parent.width
                visible: root.cfg.infoLabel ?? false
                horizontalAlignment: stack.hAlign
                text: Players.playing || !Players.has ? "NOW PLAYING" : "PAUSED"
                color: root.c1
                opacity: 0.75
                font.family: root.family
                readonly property real labelPx: Math.max(9 * root.s, root.px2 * 0.72)
                font.pixelSize: labelPx
                font.weight: Font.Bold
                font.letterSpacing: labelPx * 0.18
                bottomPadding: 2 * root.s
            }
            Text {
                width: parent.width
                horizontalAlignment: stack.hAlign
                text: root.cased(root.snap.title)
                color: root.c1
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 0.95
                font.family: root.family
                font.pixelSize: root.px
                font.weight: root.w1
                font.letterSpacing: root.px * root.tracking
            }
            Repeater {
                model: root.details
                Text {
                    required property string modelData
                    width: stack.width
                    horizontalAlignment: stack.hAlign
                    text: modelData
                    color: root.c2
                    elide: Text.ElideRight
                    font.family: root.family
                    font.pixelSize: root.px2
                    font.weight: root.w2
                    font.letterSpacing: root.px2 * root.tracking
                }
            }
        }

        // ── edge: glyphs along the cover's outline ───────────────────────
        Repeater {
            model: root.edge ? ring.built.glyphs : []
            Text {
                id: g
                required property var modelData
                readonly property real fit: ring.built.lines[modelData.line] ? ring.built.lines[modelData.line].fit : 1
                // [x, y, angle] on the path
                readonly property var p: ring.place(modelData)
                text: modelData.ch
                renderType: Text.QtRendering
                color: modelData.role === 0 ? root.c1 : root.c2
                opacity: modelData.role === 2 ? 0.6 : 1
                font.family: root.family
                font.pixelSize: (modelData.role === 0 ? root.px : root.px2) * fit
                font.weight: modelData.role === 0 ? root.w1 : root.w2
                // Every glyph's baseline sits on one line, so title and
                // detail text (different sizes) share it.
                readonly property real ay: baselineOffset - ring.capH * fit / 2
                x: p[0] - width / 2
                y: p[1] - ay
                transform: Rotation { origin.x: g.width / 2; origin.y: g.ay; angle: g.p[2] }
            }
        }
    }

    QtObject {
        id: ring
        readonly property string flow: root.cfg.edgeFlow ?? "split"
        readonly property bool inside: root.cfg.edgeSide === "inside"
        readonly property real capH: fm1.ascent * 0.72
        /** Offset of the text's centre line from the cover edge (− = inside). */
        readonly property real d: (inside ? -1 : 1) * (root.gap + capH / 2 + (inside ? 0 : 1 * root.s))
        readonly property real hh: Math.max(4, root.size / 2 + d)
        readonly property real rr: Math.max(0, Math.min(hh, root.radius + d))
        readonly property real hs: hh - rr
        readonly property real arc: Math.PI * rr / 2
        readonly property real per: 8 * hs + 4 * arc
        readonly property real dir: (root.cfg.edgeDir ?? "cw") === "ccw" ? -1 : 1
        readonly property real u0: ((root.cfg.edgeAngle ?? 0) / 360) * per
        readonly property real lap: flow === "split" || flow === "side" ? 0 : (root.cfg.edgeSpin ?? 0)
        property real phase: 0

        NumberAnimation on phase {
            from: 0; to: 1
            duration: Math.max(1, ring.lap) * 1000
            loops: Animation.Infinite
            running: ring.lap > 0 && root.edge && content.visible
            paused: running && !Players.playing && !Widgets.editing
        }

        /** Lay runs out on a straight line: glyph centres (`at`), total width. */
        function layout(runs, line, out) {
            var x = 0;
            for (var r = 0; r < runs.length; r++) {
                var run = runs[r], fm = run.role === 0 ? fm1 : fm2;
                var tr = (run.role === 0 ? root.px : root.px2) * root.tracking;
                var chars = Array.from(run.text), cu = 0;
                for (var k = 0; k < chars.length; k++) {
                    var pre = fm.advanceWidth(run.text.substring(0, cu));
                    var w = fm.advanceWidth(chars[k]);
                    out.push({ ch: chars[k], role: run.role, line: line, at: x + pre + k * tr + w / 2 });
                    cu += chars[k].length;
                }
                x += fm.advanceWidth(run.text) + chars.length * tr;
            }
            return x;
        }
        function runsOf(list) {
            var runs = [];
            list.forEach(function (t, i) {
                if (i > 0)
                    runs.push({ text: root.sep, role: 2 });
                runs.push({ text: t.text, role: t.role });
            });
            return runs;
        }

        readonly property var built: {
            var glyphs = [], lines = [];
            if (!root.edge || !root.hasText)
                return { glyphs: glyphs, lines: lines };
            var title = { text: root.cased(root.snap.title), role: 0 };
            var det = root.details.map(t => ({ text: t, role: 1 }));
            if (flow === "split") {
                var half = per / 2 * 0.86;
                var wa = layout([title], 0, glyphs);
                var fa = Math.min(1, half / Math.max(1, wa));
                lines.push({ u0: u0, dir: 1, c: wa / 2, k: fa, fit: fa });
                if (det.length > 0) {
                    var wb = layout(runsOf(det), 1, glyphs);
                    var fb = Math.min(1, half / Math.max(1, wb));
                    lines.push({ u0: u0 + per / 2, dir: -1, c: wb / 2, k: fb, fit: fb });
                }
            } else if (flow === "side") {
                // Readable on every side means: left reads up (cw) / down (ccw),
                // right reads down (cw) / up (ccw), and the overflow lands on
                // the top edge (cw) or bottom edge (ccw), upright either way.
                // Left starts at its far corner and runs towards the turn; right
                // ends at its far corner, so the run arrives through the turn.
                var q = 2 * hs + arc;
                var left = root.cfg.infoSide === "left", top = (root.cfg.edgeCorner ?? "top") !== "bottom";
                var ws = layout(runsOf([title].concat(det)), 0, glyphs);
                var fs = Math.min(1, (2 * hh + arc) * 0.96 / Math.max(1, ws));
                var a0 = left ? (top ? 2 * q + hs + arc : 3 * q + hs) : (top ? q + hs : hs + arc);
                lines.push({ u0: a0, dir: top ? 1 : -1, c: left ? 0 : ws, k: fs, fit: fs });
            } else if (flow === "loop") {
                var unitRuns = runsOf([title].concat(det));
                unitRuns.push({ text: root.sep, role: 2 });
                var one = [];
                var uw = layout(unitRuns, 0, one);
                var fit = Math.min(1, per / Math.max(1, uw));
                var n = Math.max(1, Math.floor(per / (uw * fit)));
                for (var j = 0; j < n; j++)
                    one.forEach(gl => glyphs.push({ ch: gl.ch, role: gl.role, line: 0, at: gl.at + j * uw }));
                lines.push({ u0: u0, dir: dir, c: 0, k: per / (n * uw), fit: fit });
            } else {
                var w = layout(runsOf([title].concat(det)), 0, glyphs);
                var f = Math.min(1, per * 0.92 / Math.max(1, w));
                lines.push({ u0: u0, dir: dir, c: w / 2, k: f, fit: f });
            }
            return { glyphs: glyphs, lines: lines };
        }

        /** Point on the outline `u` px clockwise from top-centre: [x, y, tangent°]. */
        function at(u) {
            var q = 2 * hs + arc;
            u = ((u % per) + per) % per;
            var k = Math.min(3, Math.floor(u / q)), t = u - k * q, x, y, a;
            if (t < hs) {
                x = t; y = -hh; a = 0;
            } else if (t < hs + arc) {
                var ph = (-90 + 90 * (t - hs) / arc) * Math.PI / 180;
                x = hs + rr * Math.cos(ph); y = -hs + rr * Math.sin(ph); a = ph * 180 / Math.PI + 90;
            } else {
                x = hh; y = -hs + (t - hs - arc); a = 90;
            }
            // Rotate the top-right quadrant into quadrant k (90° clockwise each).
            for (var i = 0; i < k; i++) {
                var nx = -y;
                y = x;
                x = nx;
            }
            return [root.cx + x, root.cy + y, a + 90 * k];
        }
        function place(g) {
            var ln = built.lines[g.line];
            if (!ln)
                return [0, 0, 0];
            var u = ln.u0 + ln.dir * ((g.at - ln.c) * ln.k) - (ln.dir * phase * per);
            var p = at(u);
            if (ln.dir < 0)
                p[2] += 180;
            return p;
        }
    }
}
