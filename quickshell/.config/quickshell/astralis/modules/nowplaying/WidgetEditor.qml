pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../colors"
import "../../config"
import "../../services"
import "../../pill"

/**
 * astralis — desktop-widget placer. A full-screen overlay (one per screen)
 * opened from Settings › Widgets: a light scrim with a snap grid and one
 * bracketed frame per desktop widget. Drag a frame to move it, drag its
 * corner to resize (the cover stays square); the real widget follows live
 * underneath.
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
    onFoldedChanged: if (folded) panel = ""

    function mix(a, b, f) {
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f);
    }
    property bool anyBusy: coverFrame.busy || lyricsFrame.busy

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "astralis-widget-editor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }

    function snap(v) {
        return win.cell > 0 ? Math.round(v / win.cell) * win.cell : v;
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
                    var o = {
                        x: Math.max(0, Math.min(1, fr.lx / win.sw)),
                        y: Math.max(0, Math.min(1, fr.ly / win.sh)),
                        w: Math.max(fr.minW / win.sw, fr.lw / win.sw)
                    };
                    if (!fr.square)
                        o.h = Math.max(fr.minH / win.sh, fr.lh / win.sh);
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
                        fr.lw = sz;
                        fr.lh = sz;
                        fr.lx = hx < 0 ? r0 - sz : x0;
                        fr.ly = hy < 0 ? b0 - sz : y0;
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
                    fr.lx = L;
                    fr.ly = T;
                    fr.lw = R - L;
                    fr.lh = B - T;
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
                        fr.lx = Math.max(0, Math.min(win.sw - fr.lw, win.snap(x0 + translation.x)));
                        fr.ly = Math.max(0, Math.min(win.sh - fr.lh, win.snap(y0 + translation.y)));
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
                            onTranslationChanged: if (active) fr.resizeBy(grip.hx, grip.hy, x0, y0, w0, h0, translation.x, translation.y)
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

            // ── dock ────────────────────────────────────────────────────────
            component Btn: Rectangle {
                id: b
                property string icon: ""
                property string label: ""
                property string tip: ""
                property string tipDesc: ""
                property bool on: false
                property bool accent: false
                /** Widget hidden — the icon greys out. */
                property bool dim: false
                opacity: dim && !on ? 0.5 : 1
                signal clicked()
                width: label.length > 0 ? Math.max(height, lbl.implicitWidth + 16 * win.s) : height
                height: 30 * win.s
                radius: height / 2
                color: b.accent ? Colors.primary
                     : b.on ? Qt.alpha(Colors.primary, 0.16)
                     : bh.hovered ? Qt.alpha(Colors.on_surface, 0.08) : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                GlyphIcon {
                    visible: b.label.length === 0
                    anchors.centerIn: parent
                    width: 15 * win.s
                    height: width
                    name: b.icon
                    color: b.accent ? Colors.on_primary : b.on ? Colors.primary : Colors.on_surface_variant
                }
                Text {
                    id: lbl
                    visible: b.label.length > 0
                    anchors.centerIn: parent
                    text: b.label
                    color: b.on ? Colors.primary : Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 11 * win.s
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                }
                HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: b.clicked() }
                Tooltip {
                    s: win.s
                    title: b.tip
                    desc: b.tipDesc
                    show: bh.hovered && b.tip.length > 0
                    placement: dock.y < win.sh / 2 ? "below" : "above"
                }
            }
            component Sep: Rectangle {
                width: 1
                height: 16 * win.s
                color: Qt.alpha(Colors.on_surface, 0.1)
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            }

            Rectangle {
                id: dock
                // Free-floating: starts top-centre; dragging overwrites x/y.
                x: Math.round((win.sw - width) / 2)
                y: Math.round(24 * win.s)
                width: win.folded ? height : dockRow.implicitWidth + 12 * win.s
                height: 40 * win.s
                radius: height / 2
                // Cover-tinted gradient: deep accent bleeding in from the left,
                // the second cover hue fading out on the right.
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: win.mix(Colors.surface_container, TrackInfo.accentDeep, 0.34) }
                    GradientStop { position: 0.55; color: Colors.surface_container }
                    GradientStop { position: 1; color: win.mix(Colors.surface_container, TrackInfo.accent2, 0.16) }
                }
                border.width: 1
                border.color: Qt.alpha(TrackInfo.accent, 0.18)
                Behavior on width { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial } }

                DragHandler {
                    target: dock
                    xAxis.minimum: 0
                    xAxis.maximum: win.sw - dock.width
                    yAxis.minimum: 0
                    yAxis.maximum: win.sh - dock.height
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
                        icon: "image"; on: win.panel === "cover"; dim: !Widgets.cover.on
                        tip: "Cover art"; tipDesc: "Style, halo, show / hide"
                        onClicked: win.panel = win.panel === "cover" ? "" : "cover"
                    }
                    Btn {
                        icon: "type"; on: win.panel === "lyrics"; dim: !Widgets.lyrics.on
                        tip: "Lyrics"; tipDesc: "Size, lines, colour, romanization"
                        onClicked: win.panel = win.panel === "lyrics" ? "" : "lyrics"
                    }
                    Sep {}
                    Btn {
                        label: Widgets.grid > 0 ? "#" + Widgets.grid : "#"
                        on: Widgets.grid > 0
                        tip: "Snap grid"
                        tipDesc: Widgets.grid > 0 ? Widgets.grid + " columns · G cycles" : "Off · G cycles"
                        onClicked: win.cycleGrid()
                    }
                    Btn { icon: "undo"; tip: "Reset layout"; onClicked: Widgets.reset() }
                    Btn { icon: "cog"; tip: "Widget settings"; onClicked: Widgets.openSettings() }
                    Btn { icon: "minus"; tip: "Preview"; tipDesc: "Hide the editor · H"; onClicked: win.chrome = false }
                    Sep {}
                    Btn { icon: "check"; accent: true; tip: "Done"; tipDesc: "Esc"; onClicked: Widgets.editing = false }
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
        /** Segmented choice. opts: [{ label, value }]. */
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
                    width: Math.max(26 * win.s, chipText.implicitWidth + 14 * win.s)
                    height: 24 * win.s
                    radius: height / 2
                    color: sel ? Qt.alpha(Colors.primary, 0.2) : chipHov.hovered ? Qt.alpha(Colors.on_surface, 0.08) : Qt.alpha(Colors.on_surface, 0.03)
                    border.width: sel ? 1 : 0
                    border.color: Qt.alpha(Colors.primary, 0.5)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
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
            readonly property bool below: dock.y < win.sh / 2
            readonly property var ly: Widgets.lyrics
            readonly property var cv: Widgets.cover
            visible: opacity > 0.01 && win.chrome
            opacity: win.panel.length > 0 && !win.folded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            width: 330 * win.s
            height: panelCol.implicitHeight + 24 * win.s
            x: Math.max(8 * win.s, Math.min(win.sw - width - 8 * win.s, dock.x + dock.width / 2 - width / 2))
            y: below ? dock.y + dock.height + 8 * win.s : dock.y - height - 8 * win.s
            radius: 20 * win.s
            gradient: Gradient {
                GradientStop { position: 0; color: win.mix(Colors.surface_container, TrackInfo.accentDeep, 0.22) }
                GradientStop { position: 0.45; color: Colors.surface_container }
                GradientStop { position: 1; color: win.mix(Colors.surface_container, TrackInfo.accent2, 0.08) }
            }
            border.width: 1
            border.color: Qt.alpha(TrackInfo.accent, 0.18)
            // Swallow clicks so they don't fall through to the frames.
            TapHandler {}

            Column {
                id: panelCol
                x: 14 * win.s
                y: 12 * win.s
                width: parent.width - 28 * win.s
                spacing: 6 * win.s

                // Header: name + show/hide.
                Item {
                    width: parent.width
                    height: 28 * win.s
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.panel === "cover" ? "Cover art" : "Lyrics"
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 13 * win.s
                        font.weight: Font.Bold
                    }
                    Sw {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        on: win.panel === "cover" ? panelCard.cv.on : panelCard.ly.on
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
