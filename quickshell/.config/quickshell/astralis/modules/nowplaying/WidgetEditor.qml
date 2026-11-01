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
 * opened from Settings › Widgets: a dimmed scrim with a snap grid and one
 * frame per desktop widget. Drag a frame to move it, drag its corner to
 * resize (the cover stays square); the real widget follows live underneath.
 * The bottom toolbar toggles widgets, picks the grid and closes. Esc / Enter
 * also close.
 */
PanelWindow {
    id: win

    property real s: 1
    readonly property real sw: width
    readonly property real sh: height
    readonly property int cols: Widgets.grid
    readonly property real cell: cols > 0 ? sw / cols : 0

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "astralis-widget-editor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }

    function snap(v) {
        return win.cell > 0 ? Math.round(v / win.cell) * win.cell : v;
    }

    Item {
        id: root
        anchors.fill: parent
        focus: true
        Keys.onPressed: (ev) => {
            if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                Widgets.editing = false;
                ev.accepted = true;
            }
        }

        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colors.scrim !== undefined ? Colors.scrim : "#000000", 0.42)
        }

        // ── snap grid ───────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: win.cols > 0
            Repeater {
                model: win.cols > 0 ? win.cols - 1 : 0
                Rectangle {
                    required property int index
                    x: Math.round((index + 1) * win.cell)
                    width: 1
                    height: parent.height
                    color: Qt.alpha(Colors.on_surface, (index + 1) % 4 === 0 ? 0.12 : 0.05)
                }
            }
            Repeater {
                model: win.cols > 0 ? Math.ceil(win.sh / win.cell) - 1 : 0
                Rectangle {
                    required property int index
                    y: Math.round((index + 1) * win.cell)
                    height: 1
                    width: parent.width
                    color: Qt.alpha(Colors.on_surface, (index + 1) % 4 === 0 ? 0.12 : 0.05)
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

            // Live geometry while dragging; committed fractions otherwise.
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
            opacity: on ? 1 : 0.4

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

            Rectangle {
                anchors.fill: parent
                radius: 14 * win.s
                color: Qt.alpha(TrackInfo.accent, fr.busy || hov.hovered ? 0.14 : 0.07)
                border.width: Math.max(1, 1.5 * win.s)
                border.color: Qt.alpha(TrackInfo.accent, fr.busy || hov.hovered ? 0.95 : 0.6)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Row {
                x: 14 * win.s
                y: 12 * win.s
                spacing: 8 * win.s
                GlyphIcon {
                    width: 16 * win.s
                    height: width
                    name: fr.icon
                    color: TrackInfo.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: fr.label + (fr.on ? "" : " · hidden")
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 13 * win.s
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12 * win.s
                anchors.rightMargin: 34 * win.s
                text: Math.round(fr.width) + " × " + Math.round(fr.height)
                color: Qt.alpha(Colors.on_surface_variant, 0.8)
                font.family: Appearance.font.mono !== undefined ? Appearance.font.mono : Appearance.font.family
                font.pixelSize: 10.5 * win.s
                visible: fr.busy
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
                // Double-click shows / hides the widget.
                onDoubleTapped: Widgets.set(fr.key, "on", !fr.on)
            }

            // Corner resize grip.
            Item {
                id: grip
                width: 26 * win.s
                height: width
                x: fr.width - width + 4 * win.s
                y: fr.height - height + 4 * win.s
                Rectangle {
                    anchors.centerIn: parent
                    width: 14 * win.s
                    height: width
                    radius: width / 2
                    color: TrackInfo.accent
                    border.width: 2 * win.s
                    border.color: Colors.surface
                    scale: resize.active || gripHov.hovered ? 1.25 : 1
                    Behavior on scale { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial } }
                }
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
            key: "cover"
            label: "Cover art"
            icon: "image"
            square: true
        }
        Frame {
            key: "lyrics"
            label: "Lyrics"
            icon: "type"
        }

        // ── toolbar ─────────────────────────────────────────────────────
        Rectangle {
            id: bar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40 * win.s
            width: barRow.implicitWidth + 28 * win.s
            height: barRow.implicitHeight + 20 * win.s
            radius: height / 2
            color: Colors.surface_container
            border.width: 1
            border.color: Qt.alpha(Colors.on_surface, 0.08)

            Row {
                id: barRow
                anchors.centerIn: parent
                spacing: 14 * win.s

                component Chip: Rectangle {
                    id: chip
                    property string text: ""
                    property string icon: ""
                    property bool on: false
                    property bool accent: false
                    signal clicked()
                    height: 34 * win.s
                    width: chipRow.implicitWidth + 26 * win.s
                    radius: height / 2
                    color: chip.accent ? Colors.primary
                         : chip.on ? Qt.alpha(Colors.primary, 0.18)
                         : (ch.hovered ? Colors.surface_container_highest : Colors.surface_container_high)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6 * win.s
                        GlyphIcon {
                            visible: chip.icon.length > 0
                            width: 15 * win.s
                            height: width
                            name: chip.icon
                            color: chip.accent ? Colors.on_primary : chip.on ? Colors.primary : Colors.on_surface_variant
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: chip.text
                            color: chip.accent ? Colors.on_primary : chip.on ? Colors.primary : Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 12 * win.s
                            font.weight: Font.DemiBold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: chip.clicked() }
                }

                Text {
                    text: "Widgets"
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 14 * win.s
                    font.weight: Font.Bold
                    leftPadding: 6 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                }
                Chip {
                    text: "Cover"
                    icon: "image"
                    on: Widgets.cover.on
                    onClicked: Widgets.set("cover", "on", !Widgets.cover.on)
                }
                Chip {
                    text: "Lyrics"
                    icon: "type"
                    on: Widgets.lyrics.on
                    onClicked: Widgets.set("lyrics", "on", !Widgets.lyrics.on)
                }
                Rectangle { width: 1; height: 22 * win.s; color: Qt.alpha(Colors.on_surface, 0.12); anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Grid"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 12 * win.s
                    anchors.verticalCenter: parent.verticalCenter
                }
                SettingsSeg {
                    s: win.s
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ label: "Off", value: 0 }, { label: "12", value: 12 }, { label: "24", value: 24 }, { label: "48", value: 48 }]
                    value: Widgets.grid
                    onPicked: (v) => Widgets.set("grid", v)
                }
                Rectangle { width: 1; height: 22 * win.s; color: Qt.alpha(Colors.on_surface, 0.12); anchors.verticalCenter: parent.verticalCenter }
                Chip {
                    text: "Reset"
                    icon: "undo"
                    onClicked: Widgets.reset()
                }
                Chip {
                    text: "Done"
                    icon: "check"
                    accent: true
                    onClicked: Widgets.editing = false
                }
            }
        }

        Text {
            anchors.horizontalCenter: bar.horizontalCenter
            anchors.bottom: bar.top
            anchors.bottomMargin: 12 * win.s
            text: "Drag to move · corner to resize · double-click to hide · Esc to finish"
            color: Qt.alpha(Colors.on_surface, 0.75)
            font.family: Appearance.font.family
            font.pixelSize: 11.5 * win.s
            style: Text.Raised
            styleColor: Qt.alpha("#000000", 0.4)
        }
    }
}
