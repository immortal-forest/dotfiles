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
                readonly property bool hot: busy || hov.hovered || gripHov.hovered
                readonly property color ink: Colors.primary

                property bool busy: drag.active || resize.active
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

                function commit() {
                    var o = {
                        x: Math.max(0, Math.min(1, win.snap(fr.lx) / win.sw)),
                        y: Math.max(0, Math.min(1, win.snap(fr.ly) / win.sh)),
                        w: Math.max(0.04, win.snap(fr.lw) / win.sw)
                    };
                    if (!fr.square)
                        o.h = Math.max(0.06, win.snap(fr.lh) / win.sh);
                    Widgets.set(fr.key, o);
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
                        fr.lx = Math.max(0, Math.min(win.sw - fr.lw, x0 + translation.x));
                        fr.ly = Math.max(0, Math.min(win.sh - fr.lh, y0 + translation.y));
                    }
                }
                TapHandler {
                    onDoubleTapped: Widgets.set(fr.key, "on", !fr.on)
                }

                // Resize hit area over the bottom-right bracket.
                Item {
                    width: 30 * win.s
                    height: width
                    x: fr.width - width + 6 * win.s
                    y: fr.height - height + 6 * win.s
                    HoverHandler {
                        id: gripHov
                        cursorShape: Qt.SizeFDiagCursor
                    }
                    DragHandler {
                        id: resize
                        target: null
                        property real w0: 0
                        property real h0: 0
                        onActiveChanged: {
                            if (active) {
                                fr.grab();
                                w0 = fr.lw;
                                h0 = fr.lh;
                            } else {
                                fr.commit();
                            }
                        }
                        onTranslationChanged: {
                            if (!active)
                                return;
                            var minW = 120 * win.s, minH = 90 * win.s;
                            var w = Math.max(minW, Math.min(win.sw - fr.x, w0 + translation.x));
                            if (fr.square) {
                                w = Math.min(w, win.sh - fr.y);
                                fr.lw = w;
                                fr.lh = w;
                            } else {
                                fr.lw = w;
                                fr.lh = Math.max(minH, Math.min(win.sh - fr.y, h0 + translation.y));
                            }
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
                color: Colors.surface_container
                border.width: 1
                border.color: Qt.alpha(Colors.on_surface, 0.08)
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
                        icon: "image"; on: Widgets.cover.on
                        tip: Widgets.cover.on ? "Hide cover" : "Show cover"
                        onClicked: Widgets.set("cover", "on", !Widgets.cover.on)
                    }
                    Btn {
                        icon: "type"; on: Widgets.lyrics.on
                        tip: Widgets.lyrics.on ? "Hide lyrics" : "Show lyrics"
                        onClicked: Widgets.set("lyrics", "on", !Widgets.lyrics.on)
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
