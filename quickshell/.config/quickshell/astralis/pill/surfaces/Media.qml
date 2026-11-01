pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — now-playing card (Ricelin Media.qml layout). Album art bleeds
 * edge-to-edge on the left, faded into the card; a blurred copy glows through
 * a near-opaque wash behind everything. Right of the cover: Marquee title,
 * artist, a dim source/time line, the play/pause seal (奏/休) flanked by 前/次
 * skips. Playback runs as a sumi brush stroke along the bottom, its dry-brush head
 * the dock for the pill's soul bead. All now-playing data comes from the
 * Players singleton; when two or more players run, the source token glows
 * into a bubble that opens a picker.
 */
PillSurface {
    id: root

    mTop: 0
    mLeft: 0
    mRight: 0
    mBottom: 0

    readonly property var player: Players.active
    readonly property bool hasPlayer: Players.has
    readonly property bool playing: Players.playing
    readonly property string title: Players.has && Players.title.length ? Players.title : "Nothing playing"
    readonly property string artist: Players.artist
    readonly property bool live: Players.live
    readonly property string serviceLabel: Players.serviceLabel

    /**
     * Art only decodes while the surface is open, keyed on the track so a
     * player reusing one file path still reloads on a new song.
     */
    readonly property string coverSource: {
        // Held through the close fade (visible) so the art doesn't drop to the
        // placeholder in the first collapsing frame; freed once hidden.
        if (!root.active && !root.visible)
            return "";
        var u = Players.artUrl;
        if (!u)
            return "";
        // Local art → a properly-escaped file:// URL. encodeURI leaves an
        // already-encoded path intact (it never escapes %) but leaves # and ?
        // raw, so escape those or a '#' in the path becomes a URL fragment and
        // loads the wrong file. (file:// images are uncached below, so they
        // reload on a track change without a cache-buster.)
        if (u.indexOf("file:") === 0 || u.charAt(0) === "/") {
            var path = u.indexOf("file://") === 0 ? u.substring(7)
                : (u.indexOf("file:") === 0 ? u.substring(5) : u);
            return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
        }
        // Remote art can be served stale under a reused url; bust the http
        // cache per track so a new song reloads.
        if (u.indexOf("http") === 0)
            return u + (u.indexOf("?") >= 0 ? "&" : "?") + "k=" + encodeURIComponent(Players.trackKey);
        return u;
    }
    /** Latched on first decode so the fallback glyph doesn't flash back while a track change reloads behind the retained cover. */
    property bool everReady: false
    onCoverSourceChanged: if (coverSource.length === 0) everReady = false

    readonly property real lengthSec: Players.length
    readonly property real positionSec: Players.position
    readonly property real playFrac: lengthSec > 0 ? Math.max(0, Math.min(1, positionSec / lengthSec)) : 0
    property real dragFrac: 0
    property bool dragging: false
    readonly property real frac: dragging ? dragFrac : playFrac

    /** Source picker is open; only reachable when more than one player runs. */
    property bool picking: false
    readonly property bool canPick: Players.pickable.length > 1
    onActiveChanged: if (!active) { picking = false; dragging = false; }
    onCanPickChanged: if (!canPick) picking = false
    onPickingChanged: if (picking) pickFlick.contentX = 0

    readonly property real textX: 134 * s
    readonly property real edgePad: 18 * s
    /** Vertical rhythm: title block, source/transport row, progress row. */
    readonly property real midBottom: 42 * s
    readonly property real barBottom: 12 * s
    readonly property color washMid: mix(Colors.surface_container_high, Colors.surface_container, 0.5)
    property real sealPulse: 0

    readonly property point seamHead: {
        void root.width;
        void root.height;
        void root.frac;
        void stroke.x;
        void stroke.width;
        return stroke.mapToItem(root, stroke.headX, stroke.headY);
    }

    ameForm: "seam"
    amePoint: Qt.point(seamHead.x, seamHead.y)

    function fmt(sec) {
        if (!(sec > 0))
            return "0:00";
        var t = Math.floor(sec);
        var m = Math.floor(t / 60);
        var ss = t % 60;
        return m + ":" + (ss < 10 ? "0" + ss : ss);
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    onTitleChanged: if (playing && active) pulseAnim.restart()

    // MPRIS position only ticks when polled; nudge it while playing on-screen.
    Timer {
        interval: 500
        running: root.active && root.playing
        repeat: true
        onTriggered: if (Players.active) Players.active.positionChanged()
    }

    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: root; property: "sealPulse"; to: 1; duration: Motion.fast; easing.type: Motion.easeStandard }
        NumberAnimation { target: root; property: "sealPulse"; to: 0; duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    component KanjiSkip: Item {
        id: skip

        property bool can: false
        property string kanjiText: ""
        signal activated()

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: kanjiLabel.implicitWidth
        implicitHeight: kanjiLabel.implicitHeight
        opacity: skip.can ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }

        Text {
            id: kanjiLabel
            anchors.centerIn: parent
            text: skip.kanjiText
            font.family: Appearance.font.jp
            font.pixelSize: 15 * root.s
            color: skipArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        MouseArea {
            id: skipArea
            anchors.fill: parent
            anchors.margins: -6 * root.s
            hoverEnabled: true
            enabled: skip.can
            cursorShape: Qt.PointingHandCursor
            onClicked: skip.activated()
        }
    }

    /** Round album swatch that tags a source, falls back to a plain tile. */
    component ArtDot: ClippingRectangle {
        id: dot
        property string url: ""
        radius: width / 2
        color: Colors.surface_container_highest
        Image {
            anchors.fill: parent
            source: dot.url
            sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
    }

    // ── art bleed: blurred cover under a warm wash, hard cover on the left ──
    ClippingRectangle {
        // Clipped to the LIVE morphing body (the host), not this fixed
        // card, so mid-morph the art keeps the pill's rounded corners; the
        // inner item steps back into layout coords so nothing slides.
        // root → its fixed-size Loader → the morphing body (surfaceHost).
        readonly property Item body: root.parent ? root.parent.parent : null
        x: body ? -(root.x + root.parent.x) : 0
        y: body ? -(root.y + root.parent.y) : 0
        width: body ? body.width : root.width
        height: body ? body.height : root.height
        radius: Appearance.rounding.pillOpen * root.s
        color: "transparent"

        Item {
            x: -parent.x
            y: -parent.y
            width: root.width
            height: root.height


            Image {
                id: bleedSrc
                anchors.fill: parent
                source: root.coverSource
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                retainWhileLoading: true
                cache: String(source).indexOf("file:") !== 0
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: bleedSrc
                scale: 1.12
                visible: (root.active || root.visible) && bleedSrc.status === Image.Ready
                blurEnabled: true
                blur: 0.95
                blurMax: 64
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(Colors.surface_container_high, 0.88) }
                    GradientStop { position: 1.0; color: Qt.alpha(Colors.surface_container, 0.93) }
                }
            }

            Item {
                id: coverBox
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 118 * root.s
                // No `clip: true` any more — the mask below fades the cover's
                // own alpha out before it reaches this box's edge, so there is
                // nothing left at the boundary for a hard clip to cut through.

                Rectangle {
                    anchors.fill: parent
                    color: Colors.surface_container_highest
                    visible: !root.everReady
                }

                Image {
                    id: cover
                    anchors.fill: parent
                    source: root.coverSource
                    sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    retainWhileLoading: true
                    cache: String(source).indexOf("file:") !== 0
                    onStatusChanged: if (status === Image.Ready) root.everReady = true
                    // Painted through maskedCover below instead of directly —
                    // the sharp pixels themselves need to fade, not just get
                    // painted over.
                    visible: false
                }

                // Alpha ramp for the mask: opaque through the first ~68% of the
                // box, then down to nothing at the trailing edge. Qt reads a
                // mask by its alpha, so the colour underneath is irrelevant —
                // only the gradient's own opacity stops matter.
                //
                // `layer.enabled: true` is not decoration here — it is the whole
                // fix. MultiEffect.maskSource docs: valid sources are a
                // ShaderEffectSource, an item with `layer.enabled`, or something
                // natively textured like Image. A bare Rectangle is none of
                // those, so without this the mask silently did nothing at all —
                // full pass-through, hard edge exactly where the old clip was —
                // which is why the "dissolve" looked unchanged.
                Rectangle {
                    id: coverFadeMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0;  color: "#ffffffff" }
                        GradientStop { position: 0.68; color: "#ffffffff" }
                        GradientStop { position: 1.0;  color: "#00ffffff" }
                    }
                }

                // What used to be a hard clip is now a real dissolve: the sharp
                // cover thins out and lets the already-blurred `bleedSrc` copy
                // (painted full-bleed behind everything, see above) show through
                // in its place — sharp fading INTO blur, not sharp stopping dead
                // against a flat wash colour.
                MultiEffect {
                    anchors.fill: parent
                    source: cover
                    maskEnabled: true
                    maskSource: coverFadeMask
                    maskThresholdMin: 0
                    maskSpreadAtMin: 1
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 40 * root.s
                    height: width
                    name: "music"
                    color: Colors.on_surface_variant
                    visible: !root.everReady
                }
            }

            // Colour-matches the dissolve into the surrounding wash once the
            // cover's own alpha has already done the actual softening above —
            // this only needs to carry the last bit of tint continuity now, not
            // hide a seam on its own.
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 62 * root.s
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 56 * root.s
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(root.washMid, 0) }
                    GradientStop { position: 0.7; color: Qt.alpha(root.washMid, 0.8) }
                    GradientStop { position: 1.0; color: root.washMid }
                }
            }
        }
    }

    // ── title / artist ──────────────────────────────────────────────────────
    Column {
        anchors.left: parent.left
        anchors.leftMargin: root.textX
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.top: parent.top
        anchors.topMargin: 22 * root.s
        spacing: 2 * root.s

        Marquee {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.title
            color: Colors.on_surface
            pixelSize: 17 * root.s
            weight: Font.DemiBold
            active: root.active
        }
        Marquee {
            anchors.left: parent.left
            anchors.right: parent.right
            text: root.artist
            color: Colors.on_surface_variant
            pixelSize: 11.5 * root.s
            active: root.active
            visible: text.length > 0
        }
    }

    // ── source · elapsed - length / picker bubble + flick ───────────────────
    Item {
        id: srcLine
        anchors.left: parent.left
        anchors.leftMargin: root.textX
        anchors.right: root.picking ? parent.right : transport.left
        anchors.rightMargin: root.picking ? root.edgePad : 10 * root.s
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.midBottom
        height: 34 * root.s

        Item {
            id: infoRow
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.picking ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }

            Text {
                id: plainSource
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.canPick && root.serviceLabel.length > 0
                text: root.serviceLabel
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
            }

            Rectangle {
                id: srcBubble
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: root.canPick
                height: 22 * root.s
                width: bubbleRow.width + 16 * root.s
                radius: height / 2
                color: Qt.alpha(Colors.primary, 0.16)
                border.width: 1
                border.color: Qt.alpha(Colors.primary, 0.45 + 0.35 * glow)

                property real glow: 0
                SequentialAnimation on glow {
                    running: srcBubble.visible && !root.picking
                    loops: Animation.Infinite
                    NumberAnimation { to: 1; duration: 1300; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 1300; easing.type: Easing.InOutSine }
                }

                Row {
                    id: bubbleRow
                    anchors.centerIn: parent
                    spacing: 5 * root.s
                    ArtDot {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 15 * root.s
                        height: 15 * root.s
                        url: Players.artUrlFor(root.player)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.serviceLabel
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                    }
                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9 * root.s
                        height: 9 * root.s
                        name: "chevron-down"
                        stroke: 2.2
                        color: Colors.primary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -5 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picking = true
                }
            }

        }

        Flickable {
            id: pickFlick
            anchors.fill: parent
            clip: true
            visible: opacity > 0.01
            opacity: root.picking ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }
            contentWidth: pickRow.width
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (e) => {
                    var step = e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x;
                    var max = Math.max(0, pickFlick.contentWidth - pickFlick.width);
                    pickFlick.contentX = Math.max(0, Math.min(max, pickFlick.contentX - step));
                }
            }

            Row {
                id: pickRow
                height: pickFlick.height
                spacing: 7 * root.s

                Repeater {
                    model: root.picking ? Players.pickable : []
                    delegate: Rectangle {
                        id: bub
                        required property var modelData
                        readonly property bool isActive: modelData === Players.active
                        anchors.verticalCenter: parent.verticalCenter
                        height: 32 * root.s
                        width: bubInner.width + 18 * root.s
                        radius: 11 * root.s
                        color: isActive ? Qt.alpha(Colors.primary, 0.2) : Qt.alpha(Colors.on_surface, 0.045)
                        border.width: 1
                        border.color: isActive ? Colors.primary : Qt.alpha(Colors.on_surface, 0.12)

                        Row {
                            id: bubInner
                            anchors.centerIn: parent
                            spacing: 7 * root.s
                            ArtDot {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16 * root.s
                                height: 16 * root.s
                                url: Players.artUrlFor(bub.modelData)
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0
                                Text {
                                    text: Players.labelOf(bub.modelData)
                                    color: bub.isActive ? Colors.on_surface : Colors.on_surface_variant
                                    font.family: Appearance.font.family
                                    font.pixelSize: 11 * root.s
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: Players.nowPlayingFor(bub.modelData)
                                    color: bub.isActive ? Colors.on_surface_variant : Qt.alpha(Colors.on_surface_variant, 0.6)
                                    font.family: Appearance.font.family
                                    font.pixelSize: 8.5 * root.s
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, 150 * root.s)
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Players.select(bub.modelData);
                                root.picking = false;
                            }
                        }
                    }
                }
            }
        }
    }

    // ── transport: 前 · seal 奏/休 · 次 ─────────────────────────────────────
    Row {
        id: transport
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.midBottom + 2 * root.s
        spacing: 18 * root.s
        opacity: root.picking ? 0 : 1
        enabled: !root.picking
        Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }

        KanjiSkip {
            kanjiText: "前"
            can: Players.canPrevious
            onActivated: Players.previous()
        }

        Rectangle {
            id: seal
            anchors.verticalCenter: parent.verticalCenter
            width: 30 * root.s
            height: 30 * root.s
            radius: 7 * root.s
            rotation: -1.5
            scale: 1 + 0.08 * root.sealPulse

            property real sat: root.playing ? 1 : 0
            Behavior on sat { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            opacity: (sealArea.enabled ? 1 : 0.4) * (0.75 + 0.25 * sat)
            Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }

            border.width: 1
            border.color: Qt.alpha(Colors.primary, 0.4 + 0.4 * root.sealPulse)
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.mix(Colors.primary, Colors.surface_container, 0.55 - 0.27 * seal.sat) }
                GradientStop { position: 1.0; color: root.mix(Qt.darker(Colors.primary, 1.18), Colors.surface_container, 0.55 - 0.27 * seal.sat) }
            }

            Text {
                anchors.centerIn: parent
                text: root.playing ? "奏" : "休"
                color: Colors.on_surface
                font.family: Appearance.font.jp
                font.pixelSize: 16 * root.s
                font.weight: Font.DemiBold
            }

            MouseArea {
                id: sealArea
                anchors.fill: parent
                anchors.margins: -4 * root.s
                hoverEnabled: true
                enabled: root.hasPlayer
                cursorShape: Qt.PointingHandCursor
                onClicked: Players.togglePlaying()
            }
        }

        KanjiSkip {
            kanjiText: "次"
            can: Players.canNext
            onActivated: Players.next()
        }
    }

    // ── progress: 筆 ink brush stroke (InkStroke) ────────────────────────────
    // elapsed · [ink body ≡ dry-brush · hairline ┊ ┊ ┊ ▕] · length
    Text {
        id: elapsedText
        anchors.left: parent.left
        anchors.leftMargin: root.textX
        anchors.verticalCenter: stroke.verticalCenter
        visible: root.hasPlayer
        text: root.fmt(root.dragging ? root.dragFrac * root.lengthSec : root.positionSec)
        color: root.dragging ? Colors.primary : Colors.on_surface
        font.family: Appearance.font.family
        font.pixelSize: 10 * root.s
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }

    Text {
        id: lengthText
        anchors.right: parent.right
        anchors.rightMargin: root.edgePad
        anchors.verticalCenter: stroke.verticalCenter
        visible: root.hasPlayer
        text: root.live ? "生" : root.fmt(root.lengthSec)
        color: root.live ? Colors.error : Colors.on_surface_variant
        font.family: root.live ? Appearance.font.jp : Appearance.font.family
        font.pixelSize: (root.live ? 12 : 10) * root.s
        font.weight: root.live ? Font.DemiBold : Font.Normal
        font.features: ({ "tnum": 1 })
    }

    InkStroke {
        id: stroke
        anchors.left: root.hasPlayer ? elapsedText.right : parent.left
        anchors.leftMargin: root.hasPlayer ? 10 * root.s : root.textX
        anchors.right: root.hasPlayer ? lengthText.left : parent.right
        anchors.rightMargin: root.hasPlayer ? 10 * root.s : root.edgePad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.barBottom
        height: 18 * root.s

        s: root.s
        frac: root.frac
        paper: root.washMid
        wet: root.playing || root.dragging ? 1 : 0

        MouseArea {
            id: seekArea
            anchors.fill: parent
            anchors.margins: -8 * root.s
            enabled: root.hasPlayer && root.lengthSec > 0 && !root.live
            cursorShape: Qt.PointingHandCursor
            function fracAt(mx) {
                return Math.max(0, Math.min(1, (mx - 8 * root.s - stroke.inset) / stroke.usable));
            }
            onPressed: (e) => {
                root.dragFrac = fracAt(e.x);
                root.dragging = true;
            }
            onPositionChanged: (e) => { if (pressed) root.dragFrac = fracAt(e.x); }
            onReleased: {
                Players.seek(root.dragFrac);
                root.dragging = false;
            }
            onCanceled: root.dragging = false
        }
    }
}
