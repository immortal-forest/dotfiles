pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import ".."
import "../../colors"
import "../../services"
import "../../services" as Services
import "../../config"

/**
 * astralis — 動 ANIMATION settings page (ported from Ricelin
 * pill/AnimationSurface.qml): toggles Hyprland animations, sets one master
 * speed across the motion leaves, and shapes the main motion curve (bezier
 * "wind") by dragging its two control points.
 *
 * Ricelin delta: where Ricelin regex-edits animations.lua in place and
 * reloads Hyprland, this page reads and writes the Services.Settings store —
 * the singleton persists settings.json, live-applies hyprctl keywords
 * (debounced) and regenerates the reload overlay (see its header doc). The
 * store is seeded once per pill session (first open); after that the
 * in-memory properties are the single source of truth. The speed scrub and
 * the curve carry a revert baseline snapshotted on that first seed, restored
 * by an undo glyph; it survives leaving and reopening the page so a curve
 * change stays revertable while you go watch it play. The editor's handle
 * positions are the source of truth — the curve point properties derive from
 * them — so dragging a handle never fights a binding.
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    /**
     * Row registry: the enabled toggle always, the speed scrub only while
     * animations are on (its row is folded away otherwise). The curve editor
     * and preset strip stay mouse-only — a 2D handle drag has no single bump
     * axis.
     */
    rows: {
        var r = [{ item: enabledRow, kind: "toggle", get: function () { return root.animOn; }, set: function (v) { root.animOn = v; root.writeEnabled(v); } }];
        if (root.animOn)
            r.push({ item: speedRow, kind: "scrub", bump: function (d) { speedScrub.bump(d); } });
        return r;
    }

    property bool animOn: true
    property real speed: 6
    property bool loaded: false
    property var base: ({})

    /** Bezier control points, read 0..1 (y may overshoot); derived from the handles. */
    property real cx1: 0.05
    property real cy1: 0.9
    property real cx2: 0.1
    property real cy2: 1.05

    /**
     * "Spring" and "Bouncy" are lifted straight from Motion.qml's own curves
     * (expressiveFastSpatial, a classic overshoot-and-settle "back" ease)
     * rather than invented fresh — picking one of these makes window motion
     * move on the SAME curve the shell's own controls already do, instead of
     * the two motion languages just happening to coexist. "Sharp" is M3's
     * sharp/decisive curve (steep in, steep out — the opposite temperament
     * from "Smooth"), included because every existing preset before it eased
     * gently in some direction; a fast, no-nonsense option was the missing
     * end of the range, not just another variation in the middle of it.
     *
     * Labelled "Spring", not "Expressive": six full-word options in this
     * segmented control have to fit the real settings content pane
     * (~367px, verified by actually rendering `SettingsSeg` at that exact
     * width before landing on this — see the git history on this file for
     * the harness). "Expressive" alone ran the whole row past that width,
     * which is exactly the overlap that shipped and had to be reverted;
     * every other label here is 5-6 characters and "Spring" reads just as
     * true for an overshoot curve while actually fitting the row.
     *
     * Each preset is now a full BUNDLE, not just a curve shape: `winStyle`
     * (windows/windowsIn/windowsOut — Hyprland has one style axis across all
     * three, only curve/speed differ per leaf) and `wsStyle` (workspaces'
     * own, independent axis). A curve alone still moved everything on the
     * same slide; picking "Bouncy" now actually pops windows in and swaps
     * workspaces differently than "Smooth" does, which is the point of
     * calling these presets for "the entire Hyprland setup" rather than
     * just a bezier picker with a different name.
     */
    readonly property var presets: [
        { label: "Smooth", x1: 0.23, y1: 1.0, x2: 0.32, y2: 1.0, winStyle: "slide", wsStyle: "slide" },
        { label: "Snappy", x1: 0.15, y1: 0.0, x2: 0.1, y2: 1.0, winStyle: "popin 80%", wsStyle: "slide" },
        { label: "Linear", x1: 0.33, y1: 0.33, x2: 0.66, y2: 0.66, winStyle: "slide", wsStyle: "fade" },
        { label: "Spring", x1: 0.42, y1: 1.67, x2: 0.21, y2: 0.9, winStyle: "popin 70%", wsStyle: "slidefade 15%" },
        { label: "Bouncy", x1: 0.34, y1: 1.56, x2: 0.64, y2: 1.0, winStyle: "popin 60%", wsStyle: "slidevert" },
        { label: "Sharp", x1: 0.4, y1: 0.0, x2: 0.6, y2: 1.0, winStyle: "slide", wsStyle: "slide" }
    ]

    onActiveChanged: {
        if (active && !root.loaded)
            root.seed();
        // focus/kbIndex reset on deactivate is handled by the SettingsPage base
    }

    /**
     * Seeds the controls from the Settings store once per pill session (the
     * store itself read settings.json once at daemon start; untouched keys
     * fall back to the hand-written hypr.d values via the defaults table).
     * Also snapshots the revert baseline and marks the session loaded.
     */
    function seed() {
        root.animOn = root.setStore.get("animEnabled") === true;
        var sp = Number(root.setStore.get("animSpeed"));
        root.speed = isNaN(sp) ? 6 : sp;
        var c = root.setStore.get("animCurve");
        if (c && c.length === 4) {
            root.cx1 = c[0];
            root.cy1 = c[1];
            root.cx2 = c[2];
            root.cy2 = c[3];
        }
        root.winStyle = root.setStore.get("animWindowStyle");
        root.wsStyle = root.setStore.get("animWorkspaceStyle");
        root.base = { speed: root.speed, cx1: root.cx1, cy1: root.cy1, cx2: root.cx2, cy2: root.cy2 };
        root.loaded = true;
    }

    /** Current window/workspace style — set only by picking a preset (see the doc on `presets`). */
    property string winStyle: "slide"
    property string wsStyle: ""

    function writeStyle(winSt, wsSt) {
        root.winStyle = winSt;
        root.wsStyle = wsSt;
        root.setStore.set("animWindowStyle", winSt);
        root.setStore.set("animWorkspaceStyle", wsSt);
    }

    // The singleton, hoisted once (`Settings` unqualified would shadow-clash
    // with the surface type of the same name in importing contexts).
    readonly property var setStore: Services.Settings

    function writeEnabled(on) {
        root.setStore.set("animEnabled", on);
    }

    function writeSpeed(v) {
        root.setStore.set("animSpeed", v);
    }

    function round2(v) {
        return Math.round(v * 100) / 100;
    }

    function writeCurve() {
        root.setStore.set("animCurve", [round2(root.cx1), round2(root.cy1), round2(root.cx2), round2(root.cy2)]);
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "動"
        title: "ANIMATION"
        onBack: root.back()
    }

    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.topMargin: 4 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: returnToBounds()

        Column {
            id: content
            width: flick.width
            spacing: 0

            SettingsGroupLabel { s: root.s; text: "Motion" }

            SettingsRow {
                id: enabledRow
                surface: root
                name: "Enabled"
                sub: "Animate windows, workspaces and fades"
                captionOnFocus: true
                icon: "sparkles"
                last: !root.animOn

                LinkToggle {
                    s: root.s
                    on: root.animOn
                    onToggled: {
                        root.animOn = !root.animOn;
                        root.writeEnabled(root.animOn);
                    }
                }
            }

            SettingsRow {
                id: speedRow
                surface: root
                name: "Speed"
                sub: "Higher is faster, applied to the motion leaves"
                captionOnFocus: true
                icon: "bolt"
                visible: root.animOn
                last: true

                ScrubValue {
                    id: speedScrub
                    s: root.s
                    value: root.speed
                    openValue: root.base.speed
                    from: 1
                    to: 10
                    step: 0.5
                    decimals: 1
                    onEdited: v => {
                        root.speed = v;
                        root.writeSpeed(v);
                    }
                }
            }

            SettingsGroupLabel {
                s: root.s
                text: "Curve"
                visible: root.animOn
            }

            /**
             * Bezier editor. The square maps unit curve-space (0,0 bottom-left to
             * 1,1 top-right) to pixels with y inverted; the two handles are the
             * source of truth and the cx/cy properties read back from them. An
             * undo glyph appears whenever the live points drift from the
             * session-open snapshot.
             */
            Item {
                id: editor
                visible: root.animOn
                width: parent.width
                height: visible ? square.height + 18 * root.s : 0

                readonly property real es: 150 * root.s
                readonly property real r: 7 * root.s
                readonly property bool dirty: root.base.cx1 !== undefined
                    && (root.cx1 !== root.base.cx1 || root.cy1 !== root.base.cy1
                        || root.cx2 !== root.base.cx2 || root.cy2 !== root.base.cy2)

                function pxX(v) { return v * editor.es; }
                function pxY(v) { return editor.es - v * editor.es; }

                function commitFromHandles() {
                    root.cx1 = Math.max(0, Math.min(1, (h1.x + editor.r) / editor.es));
                    root.cy1 = 1 - (h1.y + editor.r) / editor.es;
                    root.cx2 = Math.max(0, Math.min(1, (h2.x + editor.r) / editor.es));
                    root.cy2 = 1 - (h2.y + editor.r) / editor.es;
                }

                function syncHandles() {
                    h1.x = editor.pxX(root.cx1) - editor.r;
                    h1.y = editor.pxY(root.cy1) - editor.r;
                    h2.x = editor.pxX(root.cx2) - editor.r;
                    h2.y = editor.pxY(root.cy2) - editor.r;
                }

                onVisibleChanged: if (visible) syncHandles()
                Component.onCompleted: syncHandles()

                Connections {
                    target: root
                    function onBaseChanged() { editor.syncHandles(); }
                }

                Item {
                    id: square
                    width: editor.es
                    height: editor.es
                    anchors.horizontalCenter: parent.horizontalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 10 * root.s
                        color: Colors.surface_container_high
                        border.width: 1
                        border.color: Qt.alpha(Colors.on_surface, 0.06)
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Qt.alpha(Colors.on_surface, 0.12)
                            strokeWidth: 1
                            fillColor: "transparent"
                            startX: 0; startY: editor.es
                            PathLine { x: editor.es; y: 0 }
                        }
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Qt.alpha(Colors.primary, 0.35)
                            strokeWidth: 1.2
                            fillColor: "transparent"
                            startX: 0; startY: editor.es
                            PathLine { x: editor.pxX(root.cx1); y: editor.pxY(root.cy1) }
                        }
                    }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Qt.alpha(Colors.primary, 0.35)
                            strokeWidth: 1.2
                            fillColor: "transparent"
                            startX: editor.es; startY: 0
                            PathLine { x: editor.pxX(root.cx2); y: editor.pxY(root.cy2) }
                        }
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Colors.primary
                            strokeWidth: 2.4 * root.s
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            startX: 0; startY: editor.es
                            PathCubic {
                                control1X: editor.pxX(root.cx1); control1Y: editor.pxY(root.cy1)
                                control2X: editor.pxX(root.cx2); control2Y: editor.pxY(root.cy2)
                                x: editor.es; y: 0
                            }
                        }
                    }

                    Rectangle {
                        id: h1
                        width: 2 * editor.r
                        height: 2 * editor.r
                        radius: editor.r
                        color: h1drag.active ? Colors.on_primary : Colors.on_surface
                        border.width: 2
                        border.color: Colors.primary

                        // A 2D bezier control point — Accessible has no
                        // notion of a 2D range (or any value interface, see
                        // quickshell-core.md §9b), so this identifies as a
                        // slider and reports both coordinates in
                        // `description` rather than claiming a single axis.
                        Accessible.role: Accessible.Slider
                        Accessible.name: "Curve handle 1, start control point"
                        Accessible.description: "x " + root.cx1.toFixed(2) + ", y " + root.cy1.toFixed(2)
                        Accessible.focusable: true

                        DragHandler {
                            id: h1drag
                            target: h1
                            xAxis.minimum: -editor.r
                            xAxis.maximum: editor.es - editor.r
                            yAxis.minimum: -editor.r - 0.35 * editor.es
                            yAxis.maximum: editor.es - editor.r + 0.35 * editor.es
                            onActiveChanged: if (!active) root.writeCurve()
                        }
                        onXChanged: if (h1drag.active) editor.commitFromHandles()
                        onYChanged: if (h1drag.active) editor.commitFromHandles()
                    }

                    Rectangle {
                        id: h2
                        width: 2 * editor.r
                        height: 2 * editor.r
                        radius: editor.r
                        color: h2drag.active ? Colors.on_primary : Colors.on_surface
                        border.width: 2
                        border.color: Colors.primary

                        // Same reasoning as h1 above.
                        Accessible.role: Accessible.Slider
                        Accessible.name: "Curve handle 2, end control point"
                        Accessible.description: "x " + root.cx2.toFixed(2) + ", y " + root.cy2.toFixed(2)
                        Accessible.focusable: true

                        DragHandler {
                            id: h2drag
                            target: h2
                            xAxis.minimum: -editor.r
                            xAxis.maximum: editor.es - editor.r
                            yAxis.minimum: -editor.r - 0.35 * editor.es
                            yAxis.maximum: editor.es - editor.r + 0.35 * editor.es
                            onActiveChanged: if (!active) root.writeCurve()
                        }
                        onXChanged: if (h2drag.active) editor.commitFromHandles()
                        onYChanged: if (h2drag.active) editor.commitFromHandles()
                    }
                }

                GlyphIcon {
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * root.s
                    anchors.top: parent.top
                    anchors.topMargin: 4 * root.s
                    visible: editor.dirty
                    width: 15 * root.s
                    height: 15 * root.s
                    name: "undo"
                    color: revertArea.containsMouse ? Colors.on_surface : Qt.alpha(Colors.primary, 0.6)
                    stroke: 1.9

                    // Only reachable while the curve has actually drifted
                    // from the session-open snapshot (mirrors `visible`).
                    Accessible.role: Accessible.Button
                    Accessible.name: "Revert curve"
                    Accessible.description: "Restores the curve to the values from when this page opened"
                    Accessible.focusable: editor.dirty
                    Accessible.onPressAction: revertArea.clicked(null)

                    MouseArea {
                        id: revertArea
                        anchors.fill: parent
                        anchors.margins: -5 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.cx1 = root.base.cx1;
                            root.cy1 = root.base.cy1;
                            root.cx2 = root.base.cx2;
                            root.cy2 = root.base.cy2;
                            editor.syncHandles();
                            root.writeCurve();
                        }
                    }
                }
            }

            SettingsGroupLabel {
                s: root.s
                text: "Preset"
                visible: root.animOn
            }

            /**
             * Full-width section, like the curve editor above it — NOT a
             * SettingsRow trailing control. Six full-word options in a
             * SettingsSeg need close to the whole content pane's width
             * (verified against the real ~367px pane before shipping this;
             * see the doc on `presets`); squeezed into a row's trailing slot
             * next to an icon, a name and a caption, they overlapped all of
             * it instead of sitting in their own space.
             */
            Column {
                width: parent.width
                visible: root.animOn
                spacing: 6 * root.s

                Text {
                    x: 12 * root.s
                    width: parent.width - 24 * root.s
                    text: "A complete feel — curve, window pop-in, workspace swap"
                    color: Qt.alpha(Colors.on_surface_variant, 0.85)
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * root.s
                    wrapMode: Text.WordWrap
                    lineHeight: 1.2
                }

                SettingsSeg {
                    x: 12 * root.s
                    s: root.s
                    options: root.presets.map(function (p) { return { label: p.label, value: p.label }; })
                    value: ""
                    onPicked: (v) => {
                        for (var i = 0; i < root.presets.length; i++) {
                            if (root.presets[i].label === v) {
                                var p = root.presets[i];
                                root.cx1 = p.x1;
                                root.cy1 = p.y1;
                                root.cx2 = p.x2;
                                root.cy2 = p.y2;
                                editor.syncHandles();
                                root.writeCurve();
                                root.writeStyle(p.winStyle, p.wsStyle);
                                break;
                            }
                        }
                    }
                }

                Item { width: 1; height: 6 * root.s }
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
