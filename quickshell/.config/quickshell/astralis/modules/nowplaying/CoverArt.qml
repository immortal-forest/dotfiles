import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
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
    readonly property real coverSize: Math.round(Math.max(48, cfg.w * sw))
    /** Room around the cover for the halo to fade out fully (never clipped
     *  by the window edge). Tracks the halo's blur reach. */
    readonly property real haloReach: Math.round(Math.max(36 * s, Math.min(150 * s, coverSize * 0.38)))
    readonly property real pad: haloReach + Math.round(12 * s)
    // Per-side room: the halo's pad, or more where the song info reaches further.
    readonly property real padL: Math.round(Math.max(pad, info.reachL + 8 * s))
    readonly property real padR: Math.round(Math.max(pad, info.reachR + 8 * s))
    readonly property real padT: Math.round(Math.max(pad, info.reachT + 8 * s))
    readonly property real padB: Math.round(Math.max(pad, info.reachB + 8 * s))

    // Nothing shows until a cover has actually decoded (no empty placeholder
    // square); while the placer is open it shows even with nothing playing.
    readonly property bool shown: (Players.has && TrackInfo.art.length > 0 && slots.ready) || Widgets.editing

    color: "transparent"
    WlrLayershell.layer: win.layer
    WlrLayershell.namespace: "astralis-cover"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.left: true
    anchors.top: true
    margins.left: Math.round(cfg.x * sw - padL)
    margins.top: Math.round(cfg.y * sh - padT)
    implicitWidth: coverSize + padL + padR
    implicitHeight: coverSize + padT + padB + Math.round(70 * s)
    visible: stage.opacity > 0.001
    mask: Region { item: hit }

    // Which way the last swap went (+1 next, -1 prev) — the slide follows it.
    property int dir: 1
    // Halo colours, latched when a cover swaps in (and when the cover's
    // palette lands while nothing is pending), faded across.
    property color haloA: TrackInfo.accent
    property color haloB: TrackInfo.accent2
    property color haloC: TrackInfo.accentDeep
    Behavior on haloA { ColorAnimation { duration: Motion.largeDur } }
    Behavior on haloB { ColorAnimation { duration: Motion.largeDur } }
    Behavior on haloC { ColorAnimation { duration: Motion.largeDur } }
    function latchHalo() {
        haloA = TrackInfo.accent;
        haloB = TrackInfo.accent2;
        haloC = TrackInfo.accentDeep;
    }
    Connections {
        target: TrackInfo
        function onAccentChanged() { if (slots.pending < 0) win.latchHalo(); }
        function onAccent2Changed() { if (slots.pending < 0) win.latchHalo(); }
        function onAccentDeepChanged() { if (slots.pending < 0) win.latchHalo(); }
    }
    property int shownIndex: TrackInfo.index
    property string shownKey: TrackInfo.key

    Item {
        id: stage
        anchors.fill: parent
        opacity: win.shown ? 1 : 0
        scale: win.shown ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }
        Behavior on scale { NumberAnimation { duration: Motion.expressiveDefaultSpatialDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultSpatial } }

        // ── ambient halo: the cover's colours glowing out around its edges ──
        // A rounded rect with the cover's own corner radius (so it follows the
        // Square/Soft/Round/Circle setting), a little larger than the cover,
        // filled with a diagonal sweep of the cover hues, then blurred. The
        // blur radius is tied to the window pad, so the glow always fades out
        // before the window edge and never clips square. Colours only change
        // when a new cover has actually swapped in (win.haloA/B/C, set in flip()).
        Item {
            id: halo
            visible: win.cfg.halo && slots.ready
            anchors.centerIn: frame
            width: win.coverSize + win.haloReach * 2
            height: width
            opacity: Players.playing ? 0.9 : 0.4
            Behavior on opacity { NumberAnimation { duration: Motion.largeDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

            readonly property real spread: Math.round(win.haloReach * 0.16)
            readonly property real blurPx: win.haloReach * 0.5

            Shape {
                id: glowSrc
                anchors.centerIn: parent
                width: win.coverSize + halo.spread * 2
                height: width
                visible: false
                layer.enabled: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0
                        x2: glowSrc.width; y2: glowSrc.height
                        GradientStop { position: 0; color: win.haloA }
                        GradientStop { position: 0.5; color: win.haloC }
                        GradientStop { position: 1; color: win.haloB }
                    }
                    PathRectangle {
                        x: 0; y: 0
                        width: glowSrc.width; height: glowSrc.height
                        radius: Math.min(glowSrc.width / 2, frame.radius + halo.spread)
                    }
                }
            }
            MultiEffect {
                source: glowSrc
                anchors.fill: glowSrc
                autoPaddingEnabled: true
                blurEnabled: true
                blurMax: 64
                blur: Math.min(1, halo.blurPx / 64)
            }
        }

        // ── the cover ────────────────────────────────────────────────────
        Item {
            id: frame
            x: win.padL
            y: win.padT
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

                // Placeholder only in the placer with no cover at all.
                Rectangle {
                    anchors.fill: parent
                    visible: !slots.ready
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
                        // The back slot preloads invisibly; it only becomes
                        // front once decoded (win.flip), so nothing ever
                        // shows half-loaded or empty.
                        opacity: front ? 1 : 0
                        onStatusChanged: {
                            if (status === Image.Error) {
                                // No local copy yet → load it from the web.
                                var remote = index === 0 ? slots.ra : slots.rb;
                                if (String(source) !== remote) {
                                    if (index === 0) slots.a = remote; else slots.b = remote;
                                } else {
                                    TrackInfo.markBad(remote);
                                }
                            }
                            else if (status === Image.Ready && index === slots.pending)
                                win.flip();
                        }
                        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }
                    }
                }
                // Scrim under the song info when it sits on the cover.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * 0.55
                    z: 2
                    opacity: info.mode === "overlay" && info.wanted ? 1 : 0
                    visible: opacity > 0.001
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Qt.alpha("#000000", 0.62) }
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
                /** The covers' web urls (a / b show the local copy when there is one). */
                property string ra: ""
                property string rb: ""
                property int front: 0
                /** Slot preloading the next cover, -1 = none. */
                property int pending: -1
                /** A decoded cover is on the front slot. */
                property bool ready: false
                property bool sameSong: false
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

        // ── song info: below / beside / on / around the cover ─────────────
        CoverInfo {
            id: info
            anchors.fill: parent
            s: win.s
            cfg: win.cfg
            cx: frame.x + frame.width / 2
            cy: frame.y + frame.height / 2
            size: win.coverSize
            radius: frame.radius
            coverScale: frame.scale
            hovered: hover.hovered
            fx: win.cfg.x + win.coverSize / 2 / win.sw
            fy: win.cfg.y + win.coverSize / 2 / win.sh
        }

        Item {
            id: hit
            x: frame.x
            y: frame.y
            width: frame.width
            height: caption.y + caption.height + 8 * win.s - frame.y
        }

        // ── caption + edition dots ───────────────────────────────────────
        Column {
            id: caption
            anchors.top: frame.bottom
            // Under whatever song info hangs below the cover.
            anchors.topMargin: 22 * win.s + (info.wanted ? info.reachB : 0)
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

    // New art → preload it into the back slot. The old cover (and its halo)
    // stays up until the new one has decoded; then flip() swaps them.
    function swap() {
        var url = TrackInfo.art;
        var cur = slots.front === 0 ? slots.ra : slots.rb;
        if (url.length === 0) {
            slots.pending = -1;
            return;
        }
        if (url === cur && slots.ready) {
            slots.pending = -1;
            return;
        }
        var back = 1 - slots.front;
        // A new EDITION of the same song slides along the swap direction; a
        // new SONG just cross-fades in place.
        slots.sameSong = TrackInfo.key === win.shownKey && cur.length > 0;
        win.shownKey = TrackInfo.key;
        slots.pending = back;
        // The local copy TrackInfo keeps of every shown cover, when there is
        // one (no network, instant); the Image falls back to the url on error.
        var src = TrackInfo.localFor(url);
        if (back === 0) {
            slots.ra = url;
            slots.a = src;
        } else {
            slots.rb = url;
            slots.b = src;
        }
        // Already decoded in that slot (e.g. flipping back) → no status change
        // will fire, so flip now.
        var img = rep.itemAt(back);
        if (img && img.status === Image.Ready && (String(img.source) === src || String(img.source) === url))
            win.flip();
    }

    function flip() {
        var back = slots.pending;
        if (back < 0)
            return;
        slots.pending = -1;
        slots.front = back;
        slots.ready = true;
        win.latchHalo();
        var inc = rep.itemAt(back), out = rep.itemAt(1 - back);
        slide.stop();
        if (inc) inc.x = 0;
        if (out) out.x = 0;
        if (slots.sameSong && inc && out) {
            slide.inc = inc;
            slide.out = out;
            slide.d = win.dir * win.coverSize * 0.35;
            slide.start();
        }
    }
}
