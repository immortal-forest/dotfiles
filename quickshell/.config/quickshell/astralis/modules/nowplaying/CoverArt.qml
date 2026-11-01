import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../colors"
import "../../config"
import "../../services"

/**
 * astralis — desktop cover-art widget. The cover IS the widget: a large,
 * rounded hi-res cover floating on the wallpaper with its own blurred colour
 * bleeding out behind it as an ambient halo.
 *
 * Alternate covers of the same song (TrackInfo.covers — other editions /
 * stores) are switched with the scroll wheel or a click (right-click goes
 * back); the pick is remembered per song. A shared-axis slide carries the
 * swap, an M3 pill-dot indicator shows where you are, and a small caption
 * names the edition. Paused, the cover settles back a little.
 *
 * WlrLayer.Bottom: visible on the desktop, under windows. Only the cover
 * takes input; everything else clicks through.
 */
PanelWindow {
    id: win

    property real s: 1
    property int layer: WlrLayer.Bottom
    /** Screen size in logical px; geometry comes from Widgets.cover as fractions of it. */
    property real sw: 1920
    property real sh: 1080
    readonly property var cfg: Widgets.cover
    readonly property real coverSize: Math.round(Math.max(120, cfg.w * sw))
    readonly property real pad: Math.round(90 * s)

    // While the placer is open the cover shows even with nothing playing.
    readonly property bool shown: (Players.has && TrackInfo.art.length > 0) || Widgets.editing

    color: "transparent"
    WlrLayershell.layer: win.layer
    WlrLayershell.namespace: "astralis-cover"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.left: true
    anchors.top: true
    margins.left: Math.round(cfg.x * sw - pad)
    margins.top: Math.round(cfg.y * sh - pad)
    implicitWidth: coverSize + pad * 2
    implicitHeight: coverSize + pad * 2 + Math.round(70 * s)
    visible: stage.opacity > 0.001
    mask: Region { item: hit }

    // Which way the last swap went (+1 next, -1 prev) — the slide follows it.
    property int dir: 1
    property int shownIndex: TrackInfo.index
    property string shownKey: TrackInfo.key

    Item {
        id: stage
        anchors.fill: parent
        opacity: win.shown ? 1 : 0
        scale: win.shown ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }
        Behavior on scale { NumberAnimation { duration: Motion.expressiveDefaultSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultSpatial } }

        // ── ambient halo: the cover's own colour, blurred out behind it ──
        Image {
            id: haloSrc
            enabled: win.cfg.halo
            anchors.centerIn: frame
            width: win.coverSize
            height: width
            source: TrackInfo.art
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            retainWhileLoading: true
            visible: false
        }
        MultiEffect {
            anchors.fill: haloSrc
            source: haloSrc
            scale: 1.28
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.35
            visible: win.cfg.halo
            opacity: Players.playing ? 0.62 : 0.32
            Behavior on opacity { NumberAnimation { duration: Motion.largeDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        }

        // ── the cover ────────────────────────────────────────────────────
        Item {
            id: frame
            x: win.pad
            y: win.pad
            width: win.coverSize
            height: width
            scale: Players.playing ? (hover.hovered ? 1.02 : 1) : 0.94
            Behavior on scale { NumberAnimation { duration: Motion.expressiveDefaultSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultSpatial } }

            readonly property real radius: Math.min(width / 2, Appearance.rounding.large * 1.4 * win.s * win.cfg.radius)
            // Fixed decode size: binding it to the item's width fed back into
            // its implicit size and reloaded forever.
            readonly property size decode: Qt.size(Math.ceil(win.coverSize * 2), Math.ceil(win.coverSize * 2))

            Rectangle {
                id: roundMask
                anchors.fill: parent
                radius: frame.radius
                visible: false
                layer.enabled: true
            }

            Item {
                id: clip
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: roundMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                Rectangle {
                    anchors.fill: parent
                    color: Colors.surface_container_high
                }

                // Two slots: the incoming cover slides in along `dir` while the
                // outgoing one slides away and fades (M3 shared-axis X).
                Repeater {
                    id: rep
                    model: 2
                    Image {
                        required property int index
                        readonly property bool front: index === slots.front
                        width: win.coverSize
                        height: win.coverSize
                        source: index === 0 ? slots.a : slots.b
                        sourceSize: frame.decode
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        retainWhileLoading: true
                        z: front ? 1 : 0
                        opacity: front ? (status === Image.Ready ? 1 : 0) : 0
                        onStatusChanged: if (status === Image.Error) TrackInfo.markBad(source)
                        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }
                    }
                }
            }

            // Faint edge so light covers don't dissolve into a light wallpaper.
            Rectangle {
                anchors.fill: parent
                radius: frame.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Colors.on_surface, 0.12)
            }

            QtObject {
                id: slots
                property string a: ""
                property string b: ""
                property int front: 0
            }

            ParallelAnimation {
                id: slide
                property Item inc
                property Item out
                property real d: 0
                NumberAnimation { target: slide.inc; property: "x"; from: slide.d; to: 0; duration: Motion.expressiveDefaultSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultSpatial }
                NumberAnimation { target: slide.out; property: "x"; from: 0; to: -slide.d; duration: Motion.expressiveDefaultSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultSpatial }
            }

            HoverHandler {
                id: hover
                cursorShape: TrackInfo.count > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                property real acc: 0
                onWheel: (ev) => {
                    acc += ev.angleDelta.y;
                    if (Math.abs(acc) >= 120) {
                        win.step(acc < 0 ? 1 : -1);
                        acc = 0;
                    }
                }
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (pt, button) => win.step(button === Qt.RightButton ? -1 : 1)
            }
        }

        Item {
            id: hit
            x: frame.x
            y: frame.y
            width: frame.width
            height: frame.height + caption.height + 30 * win.s
        }

        // ── caption + edition dots ───────────────────────────────────────
        Column {
            id: caption
            anchors.top: frame.bottom
            anchors.topMargin: 22 * win.s
            anchors.horizontalCenter: frame.horizontalCenter
            spacing: 10 * win.s
            width: win.coverSize
            // Hidden at rest — the cover stands alone; hovering reveals the
            // edition dots and caption.
            opacity: hover.hovered && win.cfg.caption && !Widgets.editing ? 1 : 0
            visible: opacity > 0.001
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6 * win.s
                visible: TrackInfo.count > 1
                Repeater {
                    model: TrackInfo.count
                    Rectangle {
                        required property int index
                        readonly property bool on: index === TrackInfo.index
                        width: (on ? 22 : 6) * win.s
                        height: 6 * win.s
                        radius: height / 2
                        color: on ? TrackInfo.accent : Qt.alpha(Colors.on_surface, 0.35)
                        Behavior on width { NumberAnimation { duration: Motion.expressiveFastSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial } }
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: {
                    var c = TrackInfo.cover;
                    if (!c)
                        return "";
                    var head = [c.source, c.kind].filter(x => x && x.length).join(" · ").toUpperCase();
                    var tail = [TrackInfo.coverAlbum, TrackInfo.coverYear].filter(x => x && x.length).join(" · ");
                    return head + (tail.length ? "   " + tail : "");
                }
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: Appearance.font.sizeS * win.s
                font.letterSpacing: 0.6 * win.s
                style: Text.Raised
                styleColor: Qt.alpha("#000000", 0.35)
            }
        }
    }

    function step(d) {
        if (TrackInfo.count < 2)
            return;
        win.dir = d;
        if (d > 0)
            TrackInfo.next();
        else
            TrackInfo.prev();
    }

    // Swap slots whenever the shown cover changes; a new SONG cross-fades in
    // place, a new EDITION of the same song slides.
    Connections {
        target: TrackInfo
        function onArtChanged() { win.swap(); }
    }
    Component.onCompleted: win.swap()

    function swap() {
        var url = TrackInfo.art;
        var cur = slots.front === 0 ? slots.a : slots.b;
        if (url === cur)
            return;
        // A new EDITION of the same song slides along the swap direction; a
        // new SONG just cross-fades in place.
        var sameSong = TrackInfo.key === win.shownKey && cur.length > 0;
        win.shownKey = TrackInfo.key;
        var back = 1 - slots.front;
        if (back === 0)
            slots.a = url;
        else
            slots.b = url;
        slots.front = back;
        var inc = rep.itemAt(back), out = rep.itemAt(1 - back);
        slide.stop();
        if (inc) inc.x = 0;
        if (out) out.x = 0;
        if (sameSong && inc && out) {
            slide.inc = inc;
            slide.out = out;
            slide.d = win.dir * win.coverSize * 0.35;
            slide.start();
        }
    }
}
