pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../colors"
import "../../config"
import "../../services"
import "../../pill"

/**
 * astralis — desktop-widget placer (cover, lyrics, depth clock). A full-screen overlay (one per screen)
 * opened from Settings › Widgets: a light scrim with a snap grid and one
 * bracketed frame per desktop widget. Drag a frame to move it, drag its
 * corner to resize (the cover stays square); the real widget follows live
 * underneath. With "No overlap" on (Widgets.avoid), a dragged frame slides
 * around the other visible widgets and a resize stops at their edge.
 *
 * The controls are one small dock (drag it anywhere; the chevron folds it to
 * a single 景 bead). H hides every bit of editor chrome to preview the real
 * layout, G cycles the grid, Esc / Enter finish.
 */
PanelWindow {
    id: win

    property real s: 1
    readonly property real sw: width
    readonly property real sh: height
    readonly property int cols: Widgets.grid
    readonly property real cell: cols > 0 ? sw / cols : 0
    readonly property var grids: [0, 12, 24, 48]

    /** H: hide all chrome (scrim, grid, frames, dock) to preview the layout. */
    property bool chrome: true
    /** Dock folded to a bead. */
    property bool folded: false
    /** Open settings panel under the dock: "" | "cover" | "lyrics". */
    property string panel: ""
    /** Dock button the open panel hangs from (its pointer aims at it). */
    property Item panelBtn: null
    function togglePanel(name, btn) {
        win.panelBtn = btn;
        win.panel = win.panel === name ? "" : name;
    }
    /** Dock button under the pointer — the one shared tooltip follows it. */
    property Item tipBtn: null
    /**
     * Fold / unfold keeps the dock's centre where it was and clamps it on
     * screen; x animates together with width only for that morph (a drag
     * writes x directly and must not lag behind the pointer).
     */
    property bool foldMorph: false
    onFoldedChanged: {
        if (folded)
            panel = "";
        tipBtn = null;
        const w = folded ? dock.height : dockRow.implicitWidth + 12 * win.s;
        const cx = dock.x + dock.width / 2;
        foldMorph = true;
        dock.x = Math.round(Math.max(0, Math.min(win.sw - w, cx - w / 2)));
        foldMorphEnd.restart();
    }
    Timer {
        id: foldMorphEnd
        interval: Motion.expressiveFastSpatialDur + 40
        onTriggered: win.foldMorph = false
    }

    function mix(a, b, f) {
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f);
    }
    property bool anyBusy: coverFrame.busy || lyricsFrame.busy || depthFrame.busy

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "astralis-widget-editor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }

    function snap(v) {
        return win.cell > 0 ? Math.round(v / win.cell) * win.cell : v;
    }
    // ── anti-collision (Widgets.avoid) ────────────────────────────────────
    readonly property var keys: ["cover", "lyrics", "depth"]
    readonly property real gap: 10 * win.s
    /** A widget's on-screen box in px (the cover is square). */
    function rectOf(k) {
        var c = Widgets[k];
        return { x: c.x * win.sw, y: c.y * win.sh, w: c.w * win.sw, h: k === "cover" ? c.w * win.sw : c.h * win.sh };
    }
    function hits(a, r) {
        return a.x < r.x + r.w + win.gap && a.x + a.w + win.gap > r.x
            && a.y < r.y + r.h + win.gap && a.y + a.h + win.gap > r.y;
    }
    function collides(key, x, y, w, h) {
        // The depth clock sits under the wallpaper's subject, so widgets may overlap it freely.
        if (!Widgets.avoid || key === "depth")
            return false;
        for (var i = 0; i < win.keys.length; i++) {
            var k = win.keys[i];
            if (k !== key && k !== "depth" && Widgets[k].on && win.hits({ x: x, y: y, w: w, h: h }, win.rectOf(k)))
                return true;
        }
        return false;
    }
    /** Slide a moved box out of every visible neighbour, the shortest way that stays on screen. */
    function resolveMove(key, x, y, w, h) {
        if (!Widgets.avoid || key === "depth")
            return { x: x, y: y };
        for (var it = 0; it < 4; it++) {
            var moved = false;
            for (var i = 0; i < win.keys.length; i++) {
                var k = win.keys[i];
                if (k === key || k === "depth" || !Widgets[k].on)
                    continue;
                var r = win.rectOf(k);
                if (!win.hits({ x: x, y: y, w: w, h: h }, r))
                    continue;
                var cx = x, cy = y;
                var cands = [
                    { x: r.x - w - win.gap, y: cy }, { x: r.x + r.w + win.gap, y: cy },
                    { x: cx, y: r.y - h - win.gap }, { x: cx, y: r.y + r.h + win.gap }
                ].filter(c => c.x >= 0 && c.y >= 0 && c.x + w <= win.sw && c.y + h <= win.sh);
                if (cands.length === 0)
                    continue;
                cands.sort((a, b) => (Math.abs(a.x - cx) + Math.abs(a.y - cy)) - (Math.abs(b.x - cx) + Math.abs(b.y - cy)));
                x = cands[0].x;
                y = cands[0].y;
                moved = true;
            }
            if (!moved)
                break;
        }
        return { x: x, y: y };
    }
    function cycleGrid() {
        var i = win.grids.indexOf(Widgets.grid);
        Widgets.set("grid", win.grids[(i + 1) % win.grids.length]);
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onPressed: (ev) => {
            if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                if (!win.chrome)
                    win.chrome = true;
                else
                    Widgets.editing = false;
            } else if (ev.key === Qt.Key_H) {
                win.chrome = !win.chrome;
            } else if (ev.key === Qt.Key_G) {
                win.cycleGrid();
            } else {
                return;
            }
            ev.accepted = true;
        }

        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        // Chrome layer — everything but the "show chrome" hint fades with H.
        Item {
            id: chromeLayer
            anchors.fill: parent
            opacity: win.chrome ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Colors.scrim !== undefined ? Colors.scrim : "#000000", 0.22)
            }

            // ── snap grid (brightens while something is being dragged) ──────
            Item {
                anchors.fill: parent
                visible: win.cols > 0
                opacity: win.anyBusy ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                Repeater {
                    model: win.cols > 0 ? win.cols - 1 : 0
                    Rectangle {
                        required property int index
                        x: Math.round((index + 1) * win.cell)
                        width: 1
                        height: parent.height
                        color: Qt.alpha(Colors.on_surface, (index + 1) % 4 === 0 ? 0.09 : 0.035)
                    }
                }
                Repeater {
                    model: win.cols > 0 && win.sh > 0 ? Math.max(0, Math.ceil(win.sh / win.cell) - 1) : 0
                    Rectangle {
                        required property int index
                        y: Math.round((index + 1) * win.cell)
                        height: 1
                        width: parent.width
                        color: Qt.alpha(Colors.on_surface, (index + 1) % 4 === 0 ? 0.09 : 0.035)
                    }
                }
            }

            // ── widget frames ───────────────────────────────────────────────
            component Frame: Item {
                id: fr
                property string key: ""
                property string label: ""
                property string icon: ""
                property bool square: false
                readonly property var cfg: Widgets[key]
                readonly property bool on: cfg.on
                readonly property bool hot: busy || hov.hovered || gripsHovered > 0
                readonly property color ink: Colors.primary

                readonly property bool busy: drag.active || resizing > 0
                property real lx: 0
                property real ly: 0
                property real lw: 0
                property real lh: 0
                function grab() {
                    lx = cfg.x * win.sw;
                    ly = cfg.y * win.sh;
                    lw = cfg.w * win.sw;
                    lh = square ? lw : cfg.h * win.sh;
                }
                x: busy ? lx : cfg.x * win.sw
                y: busy ? ly : cfg.y * win.sh
                width: busy ? lw : cfg.w * win.sw
                height: busy ? lh : (square ? cfg.w * win.sw : cfg.h * win.sh)
                opacity: on ? 1 : 0.38
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                /** Smallest size, logical px — the widgets honour the same floors. */
                readonly property real minW: square ? 48 : 80
                readonly property real minH: square ? 48 : 40

                // Geometry is snapped live while dragging, so what you see is
                // what you get on release (no bounce).
                function commit() {
                    var sx = win.snap(fr.lx), sy = win.snap(fr.ly), sw2 = win.snap(fr.lw), sh2 = fr.square ? sw2 : win.snap(fr.lh);
                    // Snapping can push a box back into a neighbour — keep the exact spot then.
                    if (win.collides(fr.key, sx, sy, sw2, sh2)) {
                        sx = fr.lx; sy = fr.ly; sw2 = fr.lw; sh2 = fr.lh;
                    }
                    var o = {
                        x: Math.max(0, Math.min(1, sx / win.sw)),
                        y: Math.max(0, Math.min(1, sy / win.sh)),
                        w: Math.max(fr.minW / win.sw, sw2 / win.sw)
                    };
                    if (!fr.square)
                        o.h = Math.max(fr.minH / win.sh, sh2 / win.sh);
                    Widgets.set(fr.key, o);
                }

                /** Snap an edge to the grid unless that would break the minimum. */
                function snapEdge(v, other, dir, min) {
                    var s = win.snap(v);
                    return dir * (s - other) >= min ? s : v;
                }

                /** Resize from a grip at (hx, hy) ∈ {-1,0,1}² given the drag delta. */
                function resizeBy(hx, hy, x0, y0, w0, h0, tx, ty) {
                    var r0 = x0 + w0, b0 = y0 + h0;
                    var L = x0, R = r0, T = y0, B = b0;
                    if (fr.square) {
                        // One size from the dominant axis; the opposite corner/edge stays put.
                        var d = hx !== 0 && hy !== 0 ? (hx * tx + hy * ty) / 2 : hx !== 0 ? hx * tx : hy * ty;
                        var lim = Math.min(hx > 0 ? win.sw - x0 : hx < 0 ? r0 : win.sw,
                                           hy > 0 ? win.sh - y0 : hy < 0 ? b0 : win.sh);
                        var sz = Math.max(fr.minW, Math.min(lim, w0 + d));
                        var edge = hx < 0 ? r0 - sz : x0 + sz;
                        if (win.cell > 0) {
                            var se = win.snap(edge);
                            var ss = hx < 0 ? r0 - se : se - x0;
                            if (ss >= fr.minW && ss <= lim)
                                sz = ss;
                        }
                        fr.place(hx < 0 ? r0 - sz : x0, hy < 0 ? b0 - sz : y0, sz, sz);
                        return;
                    }
                    if (hx > 0)
                        R = fr.snapEdge(Math.max(L + fr.minW, Math.min(win.sw, r0 + tx)), L, 1, fr.minW);
                    else if (hx < 0)
                        L = fr.snapEdge(Math.min(R - fr.minW, Math.max(0, x0 + tx)), R, -1, fr.minW);
                    if (hy > 0)
                        B = fr.snapEdge(Math.max(T + fr.minH, Math.min(win.sh, b0 + ty)), T, 1, fr.minH);
                    else if (hy < 0)
                        T = fr.snapEdge(Math.min(B - fr.minH, Math.max(0, y0 + ty)), B, -1, fr.minH);
                    fr.place(L, T, R - L, B - T);
                }
                /** Apply a resize step unless it would run into a neighbour (Widgets.avoid) — the box stops at it. */
                function place(x, y, w, h) {
                    if (win.collides(fr.key, x, y, w, h)) {
                        // Go as far toward the asked-for box as fits: binary-search the
                        // step from the current box, so a resize stops right at the neighbour.
                        var lo = 0, hi = 1;
                        for (var it = 0; it < 12; it++) {
                            var m = (lo + hi) / 2;
                            if (win.collides(fr.key, fr.lx + (x - fr.lx) * m, fr.ly + (y - fr.ly) * m,
                                             fr.lw + (w - fr.lw) * m, fr.lh + (h - fr.lh) * m))
                                hi = m;
                            else
                                lo = m;
                        }
                        if (lo <= 0)
                            return;
                        x = fr.lx + (x - fr.lx) * lo;
                        y = fr.ly + (y - fr.ly) * lo;
                        w = fr.lw + (w - fr.lw) * lo;
                        h = fr.lh + (h - fr.lh) * lo;
                        if (fr.square)
                            h = w = Math.min(w, h);
                    }
                    fr.lx = x;
                    fr.ly = y;
                    fr.lw = w;
                    fr.lh = h;
                }

                // Fill + hairline.
                Rectangle {
                    anchors.fill: parent
                    radius: 12 * win.s
                    color: Qt.alpha(fr.ink, fr.hot ? 0.09 : 0.03)
                    border.width: 1
                    border.color: Qt.alpha(fr.ink, fr.hot ? 0.55 : 0.22)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                }

                // Corner brackets.
                Repeater {
                    model: 4
                    Item {
                        id: br
                        required property int index
                        readonly property bool r: index % 2 === 1
                        readonly property bool b: index >= 2
                        readonly property real len: Math.min(18 * win.s, fr.width / 4)
                        readonly property real th: Math.max(2, 2 * win.s)
                        width: len
                        height: len
                        x: r ? fr.width - len : 0
                        y: b ? fr.height - len : 0
                        Rectangle {
                            width: br.len; height: br.th; radius: br.th / 2
                            y: br.b ? br.len - br.th : 0
                            color: Qt.alpha(fr.ink, fr.hot ? 1 : 0.7)
                        }
                        Rectangle {
                            width: br.th; height: br.len; radius: br.th / 2
                            x: br.r ? br.len - br.th : 0
                            color: Qt.alpha(fr.ink, fr.hot ? 1 : 0.7)
                        }
                    }
                }

                // Label tag, sitting on the frame's top edge.
                Rectangle {
                    x: 12 * win.s
                    y: -height / 2
                    height: 22 * win.s
                    width: tagRow.implicitWidth + 16 * win.s
                    radius: height / 2
                    color: Colors.surface_container_high
                    border.width: 1
                    border.color: Qt.alpha(fr.ink, fr.hot ? 0.6 : 0.25)
                    Row {
                        id: tagRow
                        anchors.centerIn: parent
                        spacing: 6 * win.s
                        GlyphIcon {
                            width: 12 * win.s
                            height: width
                            name: fr.icon
                            color: fr.ink
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: fr.busy ? Math.round(fr.width) + " × " + Math.round(fr.height)
                                          : fr.label + (fr.on ? "" : " · hidden")
                            color: Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 11 * win.s
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                HoverHandler {
                    id: hov
                    cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                }
                DragHandler {
                    id: drag
                    target: null
                    // A press on a resize grip belongs to the grip, never to the move.
                    enabled: active || (fr.gripsHovered === 0 && fr.resizing === 0)
                    property real x0: 0
                    property real y0: 0
                    onActiveChanged: {
                        if (active) {
                            fr.grab();
                            x0 = fr.lx;
                            y0 = fr.ly;
                        } else {
                            fr.commit();
                        }
                    }
                    onTranslationChanged: {
                        if (!active)
                            return;
                        var p = win.resolveMove(fr.key,
                            Math.max(0, Math.min(win.sw - fr.lw, win.snap(x0 + translation.x))),
                            Math.max(0, Math.min(win.sh - fr.lh, win.snap(y0 + translation.y))), fr.lw, fr.lh);
                        fr.lx = p.x;
                        fr.ly = p.y;
                    }
                }
                TapHandler {
                    onDoubleTapped: Widgets.set(fr.key, "on", !fr.on)
                }

                // ── resize grips: four corners + four edges ─────────────────
                // Edge grips are strips along each side (between the corner
                // grips); the cover keeps to its corners (it stays square).
                property int resizing: 0
                property int gripsHovered: 0
                Repeater {
                    model: [[-1, -1], [1, -1], [-1, 1], [1, 1], [0, -1], [0, 1], [-1, 0], [1, 0]]
                    Item {
                        id: grip
                        required property var modelData
                        readonly property int hx: modelData[0]
                        readonly property int hy: modelData[1]
                        readonly property bool corner: hx !== 0 && hy !== 0
                        readonly property real g: 22 * win.s       // corner grip size
                        readonly property real t: 12 * win.s       // edge grip thickness
                        visible: corner || !fr.square
                        width: corner ? g : hx === 0 ? Math.max(0, fr.width - g * 2) : t
                        height: corner ? g : hy === 0 ? Math.max(0, fr.height - g * 2) : t
                        x: hx < 0 ? -width / 2 : hx > 0 ? fr.width - width / 2 : g
                        y: hy < 0 ? -height / 2 : hy > 0 ? fr.height - height / 2 : g
                        z: 2
                        HoverHandler {
                            cursorShape: grip.corner ? (grip.hx === grip.hy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                                        : grip.hx === 0 ? Qt.SizeVerCursor : Qt.SizeHorCursor
                            onHoveredChanged: fr.gripsHovered += hovered ? 1 : -1
                        }
                        DragHandler {
                            target: null
                            grabPermissions: PointerHandler.CanTakeOverFromAnything
                            property real x0: 0
                            property real y0: 0
                            property real w0: 0
                            property real h0: 0
                            onActiveChanged: {
                                if (active) {
                                    fr.grab();
                                    x0 = fr.lx; y0 = fr.ly; w0 = fr.lw; h0 = fr.lh;
                                    fr.resizing++;
                                } else {
                                    fr.resizing--;
                                    fr.commit();
                                }
                            }
                            // Delta in scene coordinates: the grip moves with the edge it
                            // drags, so its local translation would cancel itself out.
                            onCentroidChanged: if (active) fr.resizeBy(grip.hx, grip.hy, x0, y0, w0, h0,
                                centroid.scenePosition.x - centroid.scenePressPosition.x,
                                centroid.scenePosition.y - centroid.scenePressPosition.y)
                        }
                    }
                }
            }

            Frame {
                id: coverFrame
                key: "cover"
                label: "Cover art"
                icon: "image"
                square: true
            }
            Frame {
                id: lyricsFrame
                key: "lyrics"
                label: "Lyrics"
                icon: "type"
            }
            Frame {
                id: depthFrame
                key: "depth"
                label: "Depth clock"
                icon: "clock"
            }

            // ── dock ────────────────────────────────────────────────────────
            component Btn: Rectangle {
                id: b
                property string icon: ""
                property string label: ""
                property string tip: ""
                property string tipDesc: ""
                /** Its menu is open: filled pill. */
                property bool on: false
                /** A toggle that is on: primary icon + a dot underneath. */
                property bool active: false
                property bool accent: false
                /** Widget hidden — the icon greys out. */
                property bool dim: false
                opacity: dim && !on ? 0.45 : 1
                signal clicked()
                width: label.length > 0 ? Math.max(height, lbl.implicitWidth + 16 * win.s) : height
                height: 30 * win.s
                radius: height / 2
                color: b.accent ? (bh.hovered ? Qt.lighter(Colors.primary, 1.1) : Colors.primary)
                     : b.on ? Colors.primary_container
                     : bh.hovered ? Qt.alpha(Colors.primary, 0.12) : "transparent"
                border.width: b.on ? 1 : 0
                border.color: Qt.alpha(Colors.primary, 0.45)
                scale: tap.pressed ? 0.9 : 1
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack } }
                readonly property color ink: b.accent ? Colors.on_primary
                    : b.on ? Colors.on_primary_container
                    : b.active ? Colors.primary
                    : bh.hovered ? Colors.on_surface : Colors.on_surface_variant
                GlyphIcon {
                    visible: b.label.length === 0
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: b.active && !b.on ? -2 * win.s : 0
                    width: 15 * win.s
                    height: width
                    name: b.icon
                    color: b.ink
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                Text {
                    id: lbl
                    visible: b.label.length > 0
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: b.active && !b.on ? -2 * win.s : 0
                    text: b.label
                    color: b.ink
                    font.family: Appearance.font.family
                    font.pixelSize: 11 * win.s
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
                // toggle-on dot
                Rectangle {
                    visible: !b.on && !b.accent
                    width: 4 * win.s
                    height: width
                    radius: width / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3 * win.s
                    color: Colors.primary
                    opacity: b.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
                HoverHandler {
                    id: bh
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered)
                            win.tipBtn = b;
                        else if (win.tipBtn === b)
                            win.tipBtn = null;
                    }
                }
                TapHandler { id: tap; onTapped: b.clicked() }
            }
            component Sep: Rectangle {
                width: 1
                height: 16 * win.s
                color: Qt.alpha(Colors.on_surface, 0.1)
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            }

            Rectangle {
                id: dock
                // Free-floating: starts top-centre BELOW the pill (the pill's
                // rest face sits in the top ~44px; the dock used to cover its
                // clock). Dragging and fold/unfold overwrite x/y.
                // x is placed imperatively (centred once the window has a
                // width), never bound: a live binding on x survives writes
                // made through the fold Behavior and snaps the dock back.
                // Re-centres while the window/row settle, until the user
                // drags it or folds it; from then on x is theirs.
                property bool placed: false
                function place() {
                    if (dock.placed || win.foldMorph)
                        return;
                    dock.x = Math.max(0, Math.round((win.sw - dock.width) / 2));
                }
                Component.onCompleted: dock.place()
                onWidthChanged: dock.place()
                Connections {
                    target: win
                    function onSwChanged() { dock.place(); }
                    function onFoldedChanged() { dock.placed = true; }
                }
                y: Math.round(76 * win.s)
                width: win.folded ? height : dockRow.implicitWidth + 12 * win.s
                height: 40 * win.s
                radius: height / 2
                // The row is wider than the dock mid-morph; never let it spill.
                clip: true
                Behavior on x {
                    enabled: win.foldMorph
                    NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial }
                }
                // Cover-tinted gradient: deep accent bleeding in from the left,
                // the second cover hue fading out on the right.
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: win.mix(Colors.surface_container, TrackInfo.accentDeep, 0.16) }
                    GradientStop { position: 0.5; color: Colors.surface_container }
                    GradientStop { position: 1; color: win.mix(Colors.surface_container, TrackInfo.accent2, 0.07) }
                }
                border.width: 1
                border.color: Qt.alpha(Colors.on_surface, 0.08)
                Behavior on width { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial } }

                DragHandler {
                    target: dock
                    xAxis.minimum: 0
                    xAxis.maximum: win.sw - dock.width
                    yAxis.minimum: 0
                    yAxis.maximum: win.sh - dock.height
                    onActiveChanged: if (active) dock.placed = true
                }
                HoverHandler { cursorShape: Qt.SizeAllCursor }

                // Folded: a single bead, tap to unfold.
                Text {
                    anchors.centerIn: parent
                    visible: win.folded
                    text: "景"
                    color: Colors.primary
                    font.family: Appearance.font.family
                    font.pixelSize: 16 * win.s
                    TapHandler { onTapped: win.folded = false }
                }

                Row {
                    id: dockRow
                    x: 6 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * win.s
                    opacity: win.folded ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                    Btn { icon: "chevron-left"; tip: "Fold"; onClicked: win.folded = true }
                    Sep {}
                    Btn {
                        id: coverBtn
                        icon: "image"; on: win.panel === "cover"; dim: !Widgets.cover.on
                        tip: "Cover art"; tipDesc: "Style, halo, show / hide"
                        onClicked: win.togglePanel("cover", coverBtn)
                    }
                    Btn {
                        id: lyricsBtn
                        icon: "type"; on: win.panel === "lyrics"; dim: !Widgets.lyrics.on
                        tip: "Lyrics"; tipDesc: "Size, lines, colour, romanization"
                        onClicked: win.togglePanel("lyrics", lyricsBtn)
                    }
                    Btn {
                        id: depthBtn
                        icon: "clock"; on: win.panel === "depth"; dim: !Widgets.depth.on
                        tip: "Clock"; tipDesc: "Depth or plain, style, date"
                        onClicked: win.togglePanel("depth", depthBtn)
                    }
                    Sep {}
                    Btn {
                        label: Widgets.grid > 0 ? "#" + Widgets.grid : "#"
                        active: Widgets.grid > 0
                        tip: "Snap grid"
                        tipDesc: Widgets.grid > 0 ? Widgets.grid + " columns · G cycles" : "Off · G cycles"
                        onClicked: win.cycleGrid()
                    }
                    Btn {
                        icon: "app-window"; active: Widgets.avoid
                        tip: "No overlap"
                        tipDesc: Widgets.avoid ? "On · widgets slide around each other" : "Off · widgets may overlap"
                        onClicked: Widgets.set("avoid", !Widgets.avoid)
                    }
                    Btn { icon: "undo"; tip: "Reset layout"; onClicked: Widgets.reset() }
                    Btn { icon: "cog"; tip: "Widget settings"; onClicked: Widgets.openSettings() }
                    Btn { icon: "minus"; tip: "Preview"; tipDesc: "Hide the editor · H"; onClicked: win.chrome = false }
                    Sep {}
                    Btn { icon: "check"; accent: true; tip: "Done"; tipDesc: "Esc"; onClicked: Widgets.editing = false }
                }
            }

            /**
             * One tooltip for the whole dock, outside it (the dock clips), on
             * a proxy spanning the hovered button's column at the dock's full
             * height. It goes on the side away from an open panel, and stays
             * quiet for the button whose panel is already showing.
             */
            Item {
                id: tipProxy
                readonly property Item btn: win.tipBtn
                x: btn ? dock.x + dockRow.x + btn.x : 0
                y: dock.y
                width: btn ? btn.width : 0
                height: dock.height
                Tooltip {
                    s: win.s
                    title: tipProxy.btn ? tipProxy.btn.tip : ""
                    desc: tipProxy.btn ? tipProxy.btn.tipDesc : ""
                    show: tipProxy.btn !== null && tipProxy.btn.tip.length > 0 && !tipProxy.btn.on && !win.folded
                    placement: win.panel.length > 0 ? (panelCard.below ? "above" : "below")
                        : (dock.y < win.sh / 2 ? "below" : "above")
                }
            }
        }

        // ── settings panel (opened from the dock's cover / lyrics buttons) ──
        component Lbl: Text {
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 11 * win.s
            font.weight: Font.DemiBold
        }
        /** A labelled settings row: name on the left, control on the right. */
        component PRow: Item {
            id: pr
            property string name: ""
            default property alias content: holder.data
            width: panelCol.width
            height: Math.max(28 * win.s, holder.childrenRect.height)
            Lbl { text: pr.name; anchors.verticalCenter: parent.verticalCenter }
            Item {
                id: holder
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: childrenRect.width
                height: childrenRect.height
            }
        }
        /** Segmented choice. opts: [{ label, value, swatch? }] — swatch = colour chip. */
        component Seg: Row {
            id: sg
            property var opts: []
            property var value
            signal picked(var v)
            spacing: 2 * win.s
            Repeater {
                model: sg.opts
                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool sel: sg.value === modelData.value
                    width: modelData.swatch !== undefined ? height : Math.max(26 * win.s, chipText.implicitWidth + 14 * win.s)
                    height: 24 * win.s
                    radius: height / 2
                    color: sel ? Qt.alpha(Colors.primary, 0.2) : chipHov.hovered ? Qt.alpha(Colors.on_surface, 0.08) : Qt.alpha(Colors.on_surface, 0.03)
                    border.width: sel ? 1 : 0
                    border.color: Qt.alpha(Colors.primary, 0.5)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Rectangle {
                        visible: chip.modelData.swatch !== undefined
                        anchors.centerIn: parent
                        width: parent.height - 8 * win.s
                        height: width
                        radius: width / 2
                        color: chip.modelData.swatch ?? "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colors.on_surface, 0.2)
                    }
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        color: chip.sel ? Colors.primary : Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 10.5 * win.s
                        font.weight: chip.sel ? Font.Bold : Font.Medium
                        font.features: { "tnum": 1 }
                    }
                    HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: sg.picked(chip.modelData.value) }
                }
            }
        }
        /** − value + stepper. */
        component Stepper: Row {
            id: st
            property real value: 0
            property real step: 1
            property real from: 0
            property real to: 100
            property int decimals: 0
            property string suffix: ""
            signal edited(real v)
            function nudge(d) {
                var v = Math.max(st.from, Math.min(st.to, st.value + d * st.step));
                st.edited(Number(v.toFixed(st.decimals)));
            }
            spacing: 2 * win.s
            Btn { icon: "minus"; height: 24 * win.s; onClicked: st.nudge(-1) }
            Text {
                width: 44 * win.s
                height: 24 * win.s
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: st.value.toFixed(st.decimals) + st.suffix
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 11 * win.s
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                WheelHandler { onWheel: (ev) => st.nudge(ev.angleDelta.y > 0 ? 1 : -1) }
            }
            Btn { icon: "plus"; height: 24 * win.s; onClicked: st.nudge(1) }
        }
        /** On/off switch. */
        component Sw: Rectangle {
            id: sw
            property bool on: false
            signal toggled()
            width: 36 * win.s
            height: 20 * win.s
            radius: height / 2
            color: on ? Colors.primary : Qt.alpha(Colors.on_surface, 0.14)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Rectangle {
                width: parent.height - 6 * win.s
                height: width
                radius: width / 2
                y: 3 * win.s
                x: sw.on ? parent.width - width - 3 * win.s : 3 * win.s
                color: sw.on ? Colors.on_primary : Colors.on_surface_variant
                Behavior on x { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial } }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sw.toggled() }
        }

        Rectangle {
            id: panelCard
            readonly property var ly: Widgets.lyrics
            readonly property var cv: Widgets.cover
            readonly property var dc: Widgets.depth
            readonly property var swatches: ["primary", "tertiary", "secondary", "on_surface"].map(v => ({ value: v, swatch: Colors[v], label: "" }))
            /** Theme roles plus the cover's own two hues. */
            readonly property var inkSwatches: [{ value: "cover", swatch: TrackInfo.accent, label: "" }, { value: "cover2", swatch: TrackInfo.accent2, label: "" }]
                .concat(["primary", "tertiary", "on_surface", "on_surface_variant"].map(v => ({ value: v, swatch: Colors[v], label: "" })))
            readonly property bool shown: win.panel.length > 0 && !win.folded

            // ── placement: hang from the button that opened it, on whichever
            // side of the dock has room; cap the height to that room (scrolls).
            readonly property real gap: 12 * win.s
            readonly property real margin: 8 * win.s
            readonly property real natural: panelCol.implicitHeight + 24 * win.s
            readonly property real roomBelow: win.sh - (dock.y + dock.height) - gap - margin
            readonly property real roomAbove: dock.y - gap - margin
            readonly property bool below: roomBelow >= natural || roomBelow >= roomAbove
            readonly property real aimX: win.panelBtn ? dock.x + dockRow.x + win.panelBtn.x + win.panelBtn.width / 2 : dock.x + dock.width / 2

            visible: opacity > 0.01 && win.chrome
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            transform: Translate {
                y: panelCard.shown ? 0 : (panelCard.below ? -8 : 8) * win.s
                Behavior on y { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial } }
            }
            width: 330 * win.s
            height: Math.max(80 * win.s, Math.min(natural, below ? roomBelow : roomAbove))
            x: Math.max(margin, Math.min(win.sw - width - margin, aimX - width / 2))
            y: below ? dock.y + dock.height + gap : dock.y - height - gap
            radius: 20 * win.s
            color: win.mix(Colors.surface_container, TrackInfo.accentDeep, 0.08)
            border.width: 1
            border.color: Qt.alpha(Colors.on_surface, 0.08)
            // Swallow clicks so they don't fall through to the frames.
            TapHandler {}

            // Pointer nub aiming at the opening button (drawn behind the card,
            // so only the outer half shows).
            Rectangle {
                z: -1
                width: 14 * win.s
                height: width
                rotation: 45
                color: panelCard.color
                border.width: 1
                border.color: panelCard.border.color
                x: Math.max(panelCard.radius, Math.min(panelCard.width - panelCard.radius - width, panelCard.aimX - panelCard.x - width / 2))
                y: panelCard.below ? -height / 2 : panelCard.height - height / 2
            }

            Flickable {
                id: panelFlick
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                contentHeight: panelCol.implicitHeight + 24 * win.s
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

            Column {
                id: panelCol
                x: 13 * win.s
                y: 11 * win.s
                width: panelCard.width - 28 * win.s
                spacing: 6 * win.s

                // Header: name + show/hide.
                Item {
                    width: parent.width
                    height: 28 * win.s
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.panel === "cover" ? "Cover art" : win.panel === "lyrics" ? "Lyrics" : "Clock"
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 13 * win.s
                        font.weight: Font.Bold
                    }
                    Sw {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        on: win.panel.length > 0 && Widgets[win.panel] ? Widgets[win.panel].on : false
                        onToggled: Widgets.set(win.panel, "on", !on)
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Qt.alpha(Colors.on_surface, 0.08) }

                // ── cover ──
                Column {
                    visible: win.panel === "cover"
                    width: parent.width
                    spacing: 6 * win.s
                    PRow {
                        name: "Corners"
                        Seg {
                            opts: [{ label: "Square", value: 0.25 }, { label: "Soft", value: 1 }, { label: "Round", value: 2.2 }, { label: "Circle", value: 99 }]
                            value: panelCard.cv.radius
                            onPicked: (v) => Widgets.set("cover", "radius", v)
                        }
                    }
                    PRow { name: "Halo"; Sw { on: panelCard.cv.halo; onToggled: Widgets.set("cover", "halo", !on) } }
                    PRow { name: "Caption on hover"; Sw { on: panelCard.cv.caption; onToggled: Widgets.set("cover", "caption", !on) } }

                    // ── song info ──
                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Colors.on_surface, 0.08) }
                    PRow {
                        name: "Song info"
                        Seg {
                            opts: [{ label: "Off", value: "off" }, { label: "Below", value: "below" }, { label: "Side", value: "side" }, { label: "On", value: "overlay" }, { label: "Edge", value: "edge" }]
                            value: panelCard.cv.info
                            onPicked: (v) => Widgets.set("cover", "info", v)
                        }
                    }
                    Column {
                        visible: panelCard.cv.info !== "off"
                        width: parent.width
                        spacing: 6 * win.s
                        readonly property bool edge: panelCard.cv.info === "edge"
                        readonly property bool sideFlow: edge && panelCard.cv.edgeFlow === "side"
                        readonly property bool turns: edge && panelCard.cv.edgeFlow !== "split" && !sideFlow

                        PRow {
                            visible: parent.edge
                            name: "Flow"
                            Seg {
                                opts: [{ label: "Around", value: "around" }, { label: "Split", value: "split" }, { label: "Side", value: "side" }, { label: "Loop", value: "loop" }]
                                value: panelCard.cv.edgeFlow
                                onPicked: (v) => Widgets.set("cover", "edgeFlow", v)
                            }
                        }
                        Lbl {
                            visible: parent.edge
                            width: parent.width
                            wrapMode: Text.WordWrap
                            font.weight: Font.Medium
                            opacity: 0.7
                            text: panelCard.cv.edgeFlow === "split" ? "Title along the top, artist along the bottom — both upright."
                                : panelCard.cv.edgeFlow === "loop" ? "Repeats all the way round the cover."
                                : panelCard.cv.edgeFlow === "side" ? "Runs along one side; a long title turns the corner."
                                : "One line following the edge from the start point."
                        }
                        PRow {
                            visible: parent.edge
                            name: "Edge"
                            Seg {
                                opts: [{ label: "Outside", value: "outside" }, { label: "Inside", value: "inside" }]
                                value: panelCard.cv.edgeSide
                                onPicked: (v) => Widgets.set("cover", "edgeSide", v)
                            }
                        }
                        PRow {
                            visible: parent.edge && !parent.sideFlow
                            name: "Start"
                            Stepper { value: panelCard.cv.edgeAngle; step: 15; from: -180; to: 180; suffix: "°"; onEdited: (v) => Widgets.set("cover", "edgeAngle", v) }
                        }
                        PRow {
                            visible: parent.turns
                            name: "Direction"
                            Seg {
                                opts: [{ label: "Clockwise", value: "cw" }, { label: "Counter", value: "ccw" }]
                                value: panelCard.cv.edgeDir
                                onPicked: (v) => Widgets.set("cover", "edgeDir", v)
                            }
                        }
                        PRow {
                            visible: parent.turns
                            name: "Spin while playing"
                            Seg {
                                opts: [{ label: "Off", value: 0 }, { label: "Slow", value: 60 }, { label: "Med", value: 30 }, { label: "Fast", value: 12 }]
                                value: panelCard.cv.edgeSpin
                                onPicked: (v) => Widgets.set("cover", "edgeSpin", v)
                            }
                        }
                        PRow {
                            visible: panelCard.cv.info === "side" || parent.sideFlow
                            name: "Side"
                            Seg {
                                opts: [{ label: "Auto", value: "auto" }, { label: "Left", value: "left" }, { label: "Right", value: "right" }]
                                value: panelCard.cv.infoSide ?? "auto"
                                onPicked: (v) => Widgets.set("cover", "infoSide", v)
                            }
                        }
                        PRow {
                            visible: parent.sideFlow
                            name: "Turns onto"
                            Seg {
                                opts: [{ label: "Auto", value: "auto" }, { label: "Top", value: "top" }, { label: "Bottom", value: "bottom" }]
                                value: panelCard.cv.edgeCorner ?? "auto"
                                onPicked: (v) => Widgets.set("cover", "edgeCorner", v)
                            }
                        }
                        PRow {
                            visible: parent.sideFlow
                            name: "Position"
                            Seg {
                                opts: [{ label: "Side", value: "side" }, { label: "Corner", value: "corner" }]
                                value: panelCard.cv.edgeAt ?? "side"
                                onPicked: (v) => Widgets.set("cover", "edgeAt", v)
                            }
                        }
                        PRow {
                            visible: !parent.edge
                            name: "Align"
                            Seg {
                                readonly property bool side: panelCard.cv.info === "side"
                                opts: [{ label: "Auto", value: "auto" }, { label: side ? "Top" : "Left", value: "start" }, { label: "Center", value: "center" }, { label: side ? "Bottom" : "Right", value: "end" }]
                                value: panelCard.cv.infoAlign ?? "auto"
                                onPicked: (v) => Widgets.set("cover", "infoAlign", v)
                            }
                        }
                        PRow {
                            visible: !parent.edge
                            name: "\"Now playing\" label"
                            Sw { on: panelCard.cv.infoLabel; onToggled: Widgets.set("cover", "infoLabel", !on) }
                        }
                        PRow {
                            name: "Show"
                            Seg {
                                opts: [{ label: "Title", value: "title" }, { label: "+ Artist", value: "artist" }, { label: "+ Album", value: "album" }]
                                value: panelCard.cv.infoFields
                                onPicked: (v) => Widgets.set("cover", "infoFields", v)
                            }
                        }
                        PRow {
                            name: "Visible"
                            Seg {
                                opts: [{ label: "Always", value: "always" }, { label: "Hover", value: "hover" }, { label: "Playing", value: "playing" }]
                                value: panelCard.cv.infoShow
                                onPicked: (v) => Widgets.set("cover", "infoShow", v)
                            }
                        }
                        PRow {
                            name: "Text size"
                            Stepper { value: panelCard.cv.infoSize; step: 1; from: 8; to: 64; suffix: "px"; onEdited: (v) => Widgets.set("cover", "infoSize", v) }
                        }
                        PRow {
                            name: "Artist / album size"
                            Stepper { value: panelCard.cv.infoSub; step: 5; from: 40; to: 120; suffix: "%"; onEdited: (v) => Widgets.set("cover", "infoSub", v) }
                        }
                        PRow {
                            name: "Weight"
                            Seg {
                                opts: [{ label: "Light", value: 300 }, { label: "Reg", value: 400 }, { label: "Semi", value: 600 }, { label: "Bold", value: 800 }]
                                value: panelCard.cv.infoWeight
                                onPicked: (v) => Widgets.set("cover", "infoWeight", v)
                            }
                        }
                        PRow {
                            name: "Case"
                            Seg {
                                opts: [{ label: "As is", value: "none" }, { label: "ABC", value: "upper" }, { label: "abc", value: "lower" }]
                                value: panelCard.cv.infoCase
                                onPicked: (v) => Widgets.set("cover", "infoCase", v)
                            }
                        }
                        PRow {
                            name: "Letter spacing"
                            Stepper { value: panelCard.cv.infoTracking; step: 2; from: -10; to: 60; suffix: "%"; onEdited: (v) => Widgets.set("cover", "infoTracking", v) }
                        }
                        PRow {
                            visible: panelCard.cv.infoFields !== "title" && parent.edge
                            name: "Separator"
                            Seg {
                                opts: [{ label: "·", value: "dot" }, { label: "/", value: "slash" }, { label: "—", value: "dash" }, { label: "✦", value: "star" }]
                                value: panelCard.cv.infoSep
                                onPicked: (v) => Widgets.set("cover", "infoSep", v)
                            }
                        }
                        PRow {
                            name: "Title colour"
                            Seg { opts: panelCard.inkSwatches; value: panelCard.cv.infoColor; onPicked: (v) => Widgets.set("cover", "infoColor", v) }
                        }
                        PRow {
                            visible: panelCard.cv.infoFields !== "title"
                            name: "Artist colour"
                            Seg { opts: panelCard.inkSwatches; value: panelCard.cv.infoColor2; onPicked: (v) => Widgets.set("cover", "infoColor2", v) }
                        }
                        PRow {
                            visible: panelCard.cv.info !== "overlay"
                            name: "Gap from cover"
                            Stepper { value: panelCard.cv.infoGap; step: 2; from: 0; to: 80; suffix: "px"; onEdited: (v) => Widgets.set("cover", "infoGap", v) }
                        }
                        PRow { name: "Shadow"; Sw { on: panelCard.cv.infoShadow; onToggled: Widgets.set("cover", "infoShadow", !on) } }
                        Lbl {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            font.weight: Font.Medium
                            opacity: 0.7
                            text: "Font: the gear button → Song info font."
                        }
                    }
                }

                // ── lyrics ──
                Column {
                    visible: win.panel === "lyrics"
                    width: parent.width
                    spacing: 6 * win.s
                    PRow {
                        name: "Text size"
                        Stepper { value: panelCard.ly.size; step: 2; from: 14; to: 96; suffix: "px"; onEdited: (v) => Widgets.set("lyrics", "size", v) }
                    }
                    PRow {
                        name: "Sync offset"
                        Stepper { value: panelCard.ly.offset; step: 0.05; from: -2; to: 2; decimals: 2; suffix: "s"; onEdited: (v) => Widgets.set("lyrics", "offset", v) }
                    }
                    PRow {
                        name: "Fill"
                        Seg {
                            opts: [{ label: "Sweep", value: "sweep" }, { label: "Whole line", value: "line" }]
                            value: panelCard.ly.fill
                            onPicked: (v) => Widgets.set("lyrics", "fill", v)
                        }
                    }
                    PRow {
                        name: "Lines around"
                        Seg {
                            opts: [{ label: "Auto", value: 0 }, { label: "1", value: 1 }, { label: "2", value: 2 }, { label: "3", value: 3 }, { label: "4", value: 4 }, { label: "6", value: 6 }]
                            value: panelCard.ly.lines
                            onPicked: (v) => Widgets.set("lyrics", "lines", v)
                        }
                    }
                    PRow {
                        name: "Line spacing"
                        Stepper { value: panelCard.ly.spacing; step: 0.1; from: 0.3; to: 2.5; decimals: 1; suffix: "×"; onEdited: (v) => Widgets.set("lyrics", "spacing", v) }
                    }
                    PRow {
                        name: "Current line"
                        Seg {
                            opts: [{ label: "Top", value: 0.22 }, { label: "Upper", value: 0.42 }, { label: "Middle", value: 0.5 }, { label: "Low", value: 0.65 }]
                            value: panelCard.ly.anchor
                            onPicked: (v) => Widgets.set("lyrics", "anchor", v)
                        }
                    }
                    PRow {
                        name: "Align"
                        Seg {
                            opts: [{ label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }]
                            value: panelCard.ly.align
                            onPicked: (v) => Widgets.set("lyrics", "align", v)
                        }
                    }
                    PRow {
                        name: "Gradient"
                        Row {
                            spacing: 8 * win.s
                            // Live preview of the lit-text gradient.
                            Rectangle {
                                width: 34 * win.s
                                height: 10 * win.s
                                radius: height / 2
                                anchors.verticalCenter: parent.verticalCenter
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: panelCard.ly.ink === "theme" ? Colors.primary : panelCard.ly.ink === "mono" ? "#ffffff" : TrackInfo.accent }
                                    GradientStop { position: 1; color: panelCard.ly.ink === "theme" ? Colors.tertiary : panelCard.ly.ink === "mono" ? "#ebebf2" : TrackInfo.accent2 }
                                }
                            }
                            Seg {
                                opts: [{ label: "Cover", value: "cover" }, { label: "Theme", value: "theme" }, { label: "Mono", value: "mono" }]
                                value: panelCard.ly.ink
                                onPicked: (v) => Widgets.set("lyrics", "ink", v)
                            }
                        }
                    }
                    PRow { name: "Glow on current line"; Sw { on: panelCard.ly.glow; onToggled: Widgets.set("lyrics", "glow", !on) } }
                    PRow { name: "Depth blur"; Sw { on: panelCard.ly.blur; onToggled: Widgets.set("lyrics", "blur", !on) } }
                    PRow {
                        name: "Backdrop"
                        Seg {
                            opts: [{ label: "Off", value: "off" }, { label: "Soft", value: "soft" }, { label: "Solid", value: "solid" }]
                            value: panelCard.ly.backdrop
                            onPicked: (v) => Widgets.set("lyrics", "backdrop", v)
                        }
                    }
                    PRow {
                        name: "Romanization"
                        Seg {
                            opts: [{ label: "Off", value: "off" }, { label: "Below", value: "below" }, { label: "Replace", value: "replace" }]
                            value: panelCard.ly.roman
                            onPicked: (v) => Widgets.set("lyrics", "roman", v)
                        }
                    }
                    Lbl {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: text.length > 0
                        color: Lyrics.romanStatus === "nokakasi" || Lyrics.romanStatus === "error" ? Colors.error : Colors.on_surface_variant
                        font.weight: Font.Medium
                        text: panelCard.ly.roman === "off" ? ""
                            : Lyrics.romanStatus === "nokakasi" ? "Japanese needs kakasi:  sudo pacman -S kakasi  — then toggle this again."
                            : Lyrics.romanStatus === "none" ? "This song has nothing to romanize."
                            : Lyrics.romanStatus === "busy" ? "Romanizing…"
                            : Lyrics.romanStatus === "error" ? "Romanization failed — toggle to retry."
                            : ""
                    }
                }

                // ── clock ──
                Column {
                    visible: win.panel === "depth"
                    width: parent.width
                    spacing: 6 * win.s
                    PRow {
                        name: "Style"
                        Seg {
                            opts: [{ label: "Depth", value: true }, { label: "Plain clock", value: false }]
                            value: panelCard.dc.cut
                            onPicked: (v) => Widgets.set("depth", "cut", v)
                        }
                    }
                    Lbl {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.weight: Font.Medium
                        opacity: 0.8
                        text: panelCard.dc.cut ? "Numerals tuck behind the wallpaper's subject — other widgets can sit on top."
                                               : "Just the clock, drawn over the wallpaper."
                    }
                    PRow {
                        visible: panelCard.dc.cut
                        name: "Foreground cutoff"
                        Stepper {
                            value: Math.round(panelCard.dc.threshold * 100); step: 5; from: 5; to: 95; suffix: "%"
                            onEdited: (v) => Widgets.set("depth", "threshold", v / 100)
                        }
                    }
                    PRow {
                        name: "Layout"
                        Seg {
                            opts: [{ label: "Classic", value: "classic" }, { label: "Stacked", value: "stacked" }, { label: "Date below", value: "below" }]
                            value: panelCard.dc.layout
                            onPicked: (v) => Widgets.set("depth", "layout", v)
                        }
                    }
                    PRow {
                        name: "Fill"
                        Seg {
                            opts: [{ label: "Solid", value: "solid" }, { label: "Outline", value: "outline" }, { label: "Gradient", value: "gradient" }]
                            value: panelCard.dc.fill
                            onPicked: (v) => Widgets.set("depth", "fill", v)
                        }
                    }
                    PRow {
                        name: panelCard.dc.fill === "gradient" ? "Colours" : "Colour"
                        Row {
                            spacing: 8 * win.s
                            Seg { opts: panelCard.swatches; value: panelCard.dc.color; onPicked: (v) => Widgets.set("depth", "color", v) }
                            Seg {
                                visible: panelCard.dc.fill === "gradient"
                                opts: panelCard.swatches; value: panelCard.dc.color2
                                onPicked: (v) => Widgets.set("depth", "color2", v)
                            }
                        }
                    }
                    PRow {
                        name: "Weight"
                        Seg {
                            opts: [{ label: "Light", value: 300 }, { label: "Reg", value: 400 }, { label: "Bold", value: 700 }, { label: "Black", value: 900 }]
                            value: panelCard.dc.weight
                            onPicked: (v) => Widgets.set("depth", "weight", v)
                        }
                    }
                    PRow {
                        name: "Hours"
                        Seg {
                            opts: [{ label: "Auto", value: "auto" }, { label: "24 h", value: "24" }, { label: "12 h", value: "12" }]
                            value: panelCard.dc.hour
                            onPicked: (v) => Widgets.set("depth", "hour", v)
                        }
                    }
                    PRow {
                        name: "Date"
                        Seg {
                            opts: [{ label: "Long", value: "long" }, { label: "Short", value: "short" }, { label: "Off", value: "off" }]
                            value: panelCard.dc.dateFormat
                            onPicked: (v) => Widgets.set("depth", "dateFormat", v)
                        }
                    }
                    PRow {
                        visible: panelCard.dc.dateFormat !== "off"
                        name: "Date colour"
                        Seg { opts: panelCard.swatches; value: panelCard.dc.dateColor; onPicked: (v) => Widgets.set("depth", "dateColor", v) }
                    }
                    PRow {
                        name: "Align"
                        Seg {
                            opts: [{ label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }]
                            value: panelCard.dc.align
                            onPicked: (v) => Widgets.set("depth", "align", v)
                        }
                    }
                    PRow { name: "Shadow"; Sw { on: panelCard.dc.shadow; onToggled: Widgets.set("depth", "shadow", !on) } }
                    Lbl {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.weight: Font.Medium
                        opacity: 0.7
                        text: "Font, tracking and date size: the gear button."
                    }
                }
            }
            }
        }

        // While previewing (H), a tiny pill brings the editor back.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20 * win.s
            height: 26 * win.s
            width: peekText.implicitWidth + 22 * win.s
            radius: height / 2
            color: Qt.alpha(Colors.surface_container, 0.85)
            opacity: win.chrome ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Text {
                id: peekText
                anchors.centerIn: parent
                text: "Previewing · H to edit"
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 11 * win.s
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: win.chrome = true }
        }
    }
}
