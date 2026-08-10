pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — volume mixer surface (Ricelin Mixer.qml layout). "調 MIXER"
 * header with output/input route pickers and mute chips on the right, a
 * hairline divider, then a row of vertical ink-faders: a laptop-backlight
 * brightness fader (leftmost, only when a panel is present), the default sink
 * (master) plus one per Pipewire playback stream, each a thin thread with a
 * rising fill and a flat tick, the app icon and a short label beneath.
 * Hover targets a fader column; the wheel nudges the targeted fader and
 * clicking a fader's icon toggles its mute.
 */
PillSurface {
    id: root

    mTop: 13
    mLeft: 14
    mRight: 14
    mBottom: 12

    ameForm: "dock"
    amePoint: Qt.point(width / 2, height - 8 * s)

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property var streams: {
        void Pipewire.nodes.values;
        var out = [];
        var all = Pipewire.nodes.values;
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && n.isStream && n.isSink && n.audio)
                out.push(n);
        }
        return out;
    }

    /** Brightness column only exists on machines with a laptop panel. */
    readonly property int brCount: Backlight.present ? 1 : 0
    readonly property int faderCount: brCount + 1 + streams.length

    /**
     * Optimistic brightness while the fader is moving: the sysfs poller lags
     * up to a second, so the fill tracks this local value until the poller
     * confirms. -1 = follow Backlight.brightness. Writes are debounced so a
     * drag doesn't spawn a brightnessctl per pointer move.
     */
    property real brightnessLocal: -1
    readonly property real brightnessShown: brightnessLocal >= 0 ? brightnessLocal : Backlight.brightness

    function setBrightness(v) {
        if (!Backlight.hasCtl)
            return; // no brightnessctl → fader stays a read-only level display
        brightnessLocal = Math.max(0.01, Math.min(1, v));
        brightnessCommit.restart();
    }

    /**
     * Flush any pending debounced brightness write right now — on fader release
     * and on surface close — so a fast drag-then-close doesn't drop the last
     * value while the debounce timer is still pending.
     */
    function commitBrightnessNow() {
        if (brightnessCommit.running) {
            brightnessCommit.stop();
            if (brightnessLocal >= 0)
                Backlight.set(brightnessLocal);
        }
        brightnessReconcile.restart();
    }

    Timer {
        id: brightnessCommit
        interval: 160
        onTriggered: {
            if (root.brightnessLocal >= 0)
                Backlight.set(root.brightnessLocal);
            brightnessReconcile.restart();
        }
    }

    // If the write is a no-op (the panel is already at that level), Backlight
    // never emits changed(), so brightnessLocal would stay latched to the local
    // value forever. Once a write settles with none pending, drop it so the
    // fader reconciles back to the real poller value.
    Timer {
        id: brightnessReconcile
        interval: 1200
        onTriggered: if (!brightnessCommit.running) root.brightnessLocal = -1;
    }

    // Once no write is pending, the poller (or a hardware key) takes back over.
    Connections {
        target: Backlight
        function onChanged() {
            if (!brightnessCommit.running)
                root.brightnessLocal = -1;
        }
    }

    /**
     * Output devices the user can make default: real sinks only, never the
     * per-app playback streams. Sorted by label so the list order stays stable
     * as nodes appear and vanish.
     */
    readonly property var outputSinks: {
        void Pipewire.nodes.values;
        var out = [];
        var all = Pipewire.nodes.values;
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && n.isSink && !n.isStream && n.audio)
                out.push(n);
        }
        out.sort((a, b) => root.deviceLabel(a).localeCompare(root.deviceLabel(b)));
        return out;
    }

    /**
     * Input devices the user can make default: real sources only. Sink
     * monitors also match isSink=false, so they are dropped by name.
     */
    readonly property var inputSources: {
        void Pipewire.nodes.values;
        var out = [];
        var all = Pipewire.nodes.values;
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && !n.isSink && !n.isStream && n.audio && !/monitor/i.test(n.name || ""))
                out.push(n);
        }
        out.sort((a, b) => root.deviceLabel(a).localeCompare(root.deviceLabel(b)));
        return out;
    }

    function deviceLabel(node) {
        if (!node)
            return "";
        return node.description || node.nickname || node.name || "";
    }

    // ── bluetooth A2DP codec selection (advanced; degrades to hidden) ───────
    /**
     * Detection method: the default sink is a Bluetooth one when its Pipewire
     * node carries `device.api == "bluez5"`. That node's `api.bluez5.codec`
     * property names the codec currently on the wire and `api.bluez5.address`
     * names the device (the node does NOT expose the owning card's name, so
     * the card is matched by that address in the probe below). PipeWire
     * exposes one card *profile* per A2DP codec the device+adapter pair
     * support (a2dp-sink-sbc / -sbc_xq / -aac / -aptx / … — beware: the
     * top-priority codec rides the bare `a2dp-sink` profile name, its codec
     * only appears in the profile description), so "available codecs" = the
     * bluez card's a2dp-sink* profiles, read via `pactl -f json list cards`.
     * Switch method: `pactl set-card-profile <card> <profile>` — PipeWire
     * tears the sink down and re-creates it with the new codec; the sink swap
     * re-triggers the probe so the chip follows. Degradation: a non-Bluetooth
     * sink, missing pactl, or unparseable JSON just leaves `btCodecs` empty
     * and the chip hidden — never an error.
     */
    readonly property var sinkProps: (sink && sink.properties) ? sink.properties : null
    readonly property bool sinkIsBluez: sinkProps !== null && sinkProps["device.api"] === "bluez5"
    readonly property string btSinkAddress: sinkIsBluez ? String(sinkProps["api.bluez5.address"] || "") : ""
    readonly property string btActiveCodec: sinkIsBluez ? String(sinkProps["api.bluez5.codec"] || "") : ""

    /** bluez card owning the active sink, resolved by the probe (its `name`). */
    property string btCardName: ""

    /** [{profile, label, active}] parsed from the bluez card; [] hides the chip. */
    property var btCodecs: []
    property bool btCodecSwitching: false

    /** Chip text: the live wire codec, else the active profile, else a stub. */
    readonly property string btCodecChipText: {
        if (btActiveCodec.length)
            return codecLabel(btActiveCodec);
        for (var i = 0; i < btCodecs.length; i++)
            if (btCodecs[i].active)
                return btCodecs[i].label;
        return "A2DP";
    }

    /** Pretty label for a bluez codec id ("aptx_hd"/"aptX HD" → "aptX-HD"). */
    function codecLabel(id) {
        var map = {
            sbc: "SBC", sbc_xq: "SBC-XQ", aac: "AAC",
            aptx: "aptX", aptx_hd: "aptX-HD", aptx_ll: "aptX-LL",
            ldac: "LDAC", msbc: "mSBC", cvsd: "CVSD",
            faststream: "FastStream", lc3: "LC3", opus_05: "Opus"
        };
        var k = String(id || "").toLowerCase().replace(/[\s-]/g, "_");
        return map[k] || (id ? String(id).toUpperCase() : "");
    }

    function refreshCodecs() {
        if (open && sinkIsBluez && btSinkAddress.length && !codecProbe.running)
            codecProbe.running = true;
    }

    function switchCodec(entry) {
        if (!entry || !entry.profile || !btCardName.length || btCodecSwitching)
            return;
        btCodecSwitching = true;
        codecSet.command = ["pactl", "set-card-profile", btCardName, entry.profile];
        codecSet.running = true;
    }

    // The default sink swapping (or its properties landing late) re-probes;
    // debounced because a profile switch churns nodes for a few hundred ms.
    // The completed-kick covers a surface created already-open.
    onSinkChanged: { btCodecs = []; btCardName = ""; codecRefetch.restart(); }
    onSinkPropsChanged: codecRefetch.restart()
    Component.onCompleted: codecRefetch.restart()

    Timer {
        id: codecRefetch
        interval: 400
        onTriggered: root.refreshCodecs()
    }

    Process {
        id: codecProbe
        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [];
                var cardName = "";
                try {
                    var want = root.btSinkAddress.toUpperCase();
                    var cards = JSON.parse(this.text);
                    for (var i = 0; i < cards.length && want.length; i++) {
                        var c = cards[i];
                        if (!c)
                            continue;
                        // Match the card by BT address (the sink node doesn't
                        // name its card); the constructed name is a fallback.
                        var caddr = (c.properties && c.properties["api.bluez5.address"])
                            ? String(c.properties["api.bluez5.address"]).toUpperCase() : "";
                        if (caddr !== want
                            && c.name !== "bluez_card." + root.btSinkAddress.replace(/:/g, "_"))
                            continue;
                        cardName = c.name || "";
                        var profs = c.profiles || {};
                        for (var key in profs) {
                            if (key.indexOf("a2dp-sink") !== 0)
                                continue;
                            var p = profs[key];
                            var avail = p ? p.available : false;
                            if (avail === false || avail === "no")
                                continue;
                            // Codec name lives in the description:
                            // "High Fidelity Playback (A2DP Sink, codec aptX HD)"
                            var m = /codec ([^)]+)\)?\s*$/.exec((p && p.description) ? p.description : "");
                            var label = m ? root.codecLabel(m[1])
                                : root.codecLabel(key.slice("a2dp-sink-".length));
                            out.push({
                                profile: key,
                                label: (label && label.length) ? label : key,
                                active: key === c.active_profile
                            });
                        }
                        break;
                    }
                } catch (e) {
                    out = []; // unparseable pactl output → chip hidden
                    cardName = "";
                }
                out.sort((a, b) => a.label.localeCompare(b.label));
                root.btCardName = cardName;
                root.btCodecs = cardName.length ? out : [];
            }
        }
        stderr: StdioCollector {}
    }

    Process {
        id: codecSet
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: {
            root.btCodecSwitching = false;
            codecRefetch.restart();
        }
    }

    function nodeLabel(n) {
        if (!n)
            return "";
        var p = n.properties;
        if (p && p["application.name"])
            return p["application.name"];
        return n.description || n.nickname || n.name || "";
    }

    /** Resolved app icon path, or "" (→ glyph fallback) so a themeless name never spams the log. */
    function nodeIcon(n) {
        var p = n ? n.properties : null;
        if (!p)
            return "";
        var name = p["application.icon-name"] || "";
        if (name.length) {
            var path = Quickshell.iconPath(name, true);
            if (path.length)
                return path;
        }
        var app = p["application.name"] || "";
        return app.length ? Quickshell.iconPath(String(app).toLowerCase(), true) : "";
    }

    /** Which device dropdown is open: "out", "in", or "" for none. */
    property string openPicker: ""

    property int focusIndex: -1
    readonly property bool surfaceHovered: hoverTracker.hovered

    /**
     * Pointer-driven fader targeting: the hover x maps to a fader column and
     * drives the focused (lit) fader, Ricelin-style.
     */
    readonly property int hoverIndex: surfaceHovered && width > 0 && faderCount > 0
        && hoverTracker.point.position.y >= faderRow.y
        ? Math.max(0, Math.min(faderCount - 1,
            Math.floor((hoverTracker.point.position.x - faderRow.x) / Math.max(1, faderRow.colW))))
        : -1
    onHoverIndexChanged: if (hoverIndex >= 0) focusIndex = hoverIndex

    HoverHandler {
        id: hoverTracker
    }

    onOpenChanged: {
        focusIndex = open ? 0 : -1;
        if (!open) {
            openPicker = "";
            commitBrightnessNow(); // flush a pending write before dropping local
            brightnessLocal = -1;
        } else {
            refreshCodecs();
        }
    }

    // Volume/mute props only populate while their node is bound.
    PwObjectTracker {
        objects: [root.sink, root.source]
            .concat(root.streams).concat(root.outputSinks).concat(root.inputSources)
            .filter(Boolean)
    }

    component IconChip: Rectangle {
        id: chip
        property string glyph: ""
        property bool on: false
        signal toggled()

        width: 26 * root.s
        height: 26 * root.s
        radius: 8 * root.s
        color: chip.on ? Colors.surface_container_highest : "transparent"
        border.width: 1
        border.color: chip.on ? Qt.alpha(Colors.outline_variant, 0.9) : Qt.alpha(Colors.outline_variant, 0.6)

        GlyphIcon {
            anchors.centerIn: parent
            width: 15 * root.s
            height: 15 * root.s
            name: chip.glyph
            color: chip.on ? Colors.primary : Colors.on_surface_variant
            stroke: 1.7
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.toggled()
        }
    }

    /**
     * Header device picker: an icon-only button that toggles its dropdown. It
     * reads as an open field (primary tint and border) while its list shows.
     */
    component DevicePickerChip: Rectangle {
        id: dchip
        property string glyph: ""
        property bool open: false
        signal toggled()

        width: 26 * root.s
        height: 26 * root.s
        radius: 8 * root.s
        color: dchip.open ? Qt.alpha(Colors.primary, 0.14)
            : (dchipHover.hovered ? Colors.surface_container_highest : "transparent")
        border.width: 1
        border.color: dchip.open ? Qt.alpha(Colors.primary, 0.5) : Qt.alpha(Colors.outline_variant, 0.6)
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        GlyphIcon {
            anchors.centerIn: parent
            width: 15 * root.s
            height: 15 * root.s
            name: dchip.glyph
            color: dchip.open ? Colors.primary : Colors.on_surface_variant
            stroke: 1.7
        }
        HoverHandler {
            id: dchipHover
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dchip.toggled()
        }
    }

    // ── header: 調 MIXER + route/mute chips ─────────────────────────────────
    Item {
        id: header
        z: 5
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Flags.showGlyphs
                text: "調"
                color: Colors.on_surface
                font.family: Appearance.font.jp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "MIXER"
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s

            // Bluetooth codec chip: shows the wire codec of the active bluez
            // sink and opens the codec menu. Hidden entirely unless the
            // default sink is Bluetooth *and* its codecs were queryable.
            Rectangle {
                id: codecChip
                visible: root.sinkIsBluez && root.btCodecs.length > 0
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool openState: root.openPicker === "codec"
                width: codecChipText.implicitWidth + 14 * root.s
                height: 26 * root.s
                radius: 8 * root.s
                color: openState ? Qt.alpha(Colors.primary, 0.14)
                    : (codecChipHover.hovered ? Colors.surface_container_highest : "transparent")
                border.width: 1
                border.color: openState ? Qt.alpha(Colors.primary, 0.5) : Qt.alpha(Colors.outline_variant, 0.6)
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: codecChipText
                    anchors.centerIn: parent
                    text: root.btCodecChipText
                    color: codecChip.openState ? Colors.primary : Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.6 * root.s
                    opacity: root.btCodecSwitching ? 0.5 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
                HoverHandler {
                    id: codecChipHover
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPicker = root.openPicker === "codec" ? "" : "codec"
                }
            }

            DevicePickerChip {
                glyph: "speaker"
                open: root.openPicker === "out"
                onToggled: root.openPicker = root.openPicker === "out" ? "" : "out"
            }
            DevicePickerChip {
                glyph: "mic"
                open: root.openPicker === "in"
                onToggled: root.openPicker = root.openPicker === "in" ? "" : "in"
            }
            IconChip {
                glyph: root.sink && root.sink.audio && root.sink.audio.muted ? "speaker-off" : "speaker"
                on: root.sink !== null && root.sink.audio !== null && root.sink.audio.muted
                onToggled: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
            }
            IconChip {
                glyph: root.source && root.source.audio && root.source.audio.muted ? "mic-off" : "mic"
                on: root.source !== null && root.source.audio !== null && root.source.audio.muted
                onToggled: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.alpha(Colors.on_surface, 0.06)
    }

    /**
     * Device dropdown overlay. Both pickers reuse this: `kind` ("out"/"in")
     * keys it to root.openPicker, `model` is the node list, `current` the
     * active default, `onPick` writes the matching preferredDefault. It
     * floats above the faders right-aligned under the header so the mixer
     * height stays fixed while a list is open.
     */
    component DeviceMenu: Item {
        id: menu
        property string kind: ""
        property var model: []
        property var current
        /**
         * Row-label and current-row tests, overridable so the codec menu can
         * feed plain {profile,label,active} objects through the same panel.
         */
        property var labelOf: (m) => root.deviceLabel(m)
        property var isCurrent: (m) => m === menu.current
        property real menuWidth: 300 * root.s
        signal pick(var node)

        readonly property bool open: root.openPicker === kind
        z: 7
        visible: open
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.right: parent.right
        width: menuWidth
        height: panel.height

        /**
         * Shadow caster kept apart from the option text so the labels stay
         * unlayered and crisp.
         */
        Rectangle {
            anchors.fill: panel
            visible: menu.open
            radius: panel.radius
            color: Colors.surface_container
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, Appearance.elevation.shadowOpacity)
                shadowBlur: 0.6
                shadowVerticalOffset: 4 * root.s
            }
        }

        Rectangle {
            id: panel
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.min(menu.model.length * 24 * root.s + 4 * root.s, 150 * root.s)
            clip: true
            radius: 9 * root.s
            gradient: Gradient {
                GradientStop { position: 0.0; color: Colors.surface_container_high }
                GradientStop { position: 1.0; color: Colors.surface_container }
            }
            border.width: 1
            border.color: Qt.alpha(Colors.outline_variant, 0.9)

            ListView {
                anchors.fill: parent
                anchors.margins: 2 * root.s
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: menu.model

                delegate: Rectangle {
                    id: devRow
                    required property var modelData
                    readonly property bool current: menu.isCurrent(modelData)

                    width: ListView.view.width
                    height: 24 * root.s
                    radius: 7 * root.s
                    color: devRowHover.hovered ? Colors.surface_container_highest
                        : (devRow.current ? Qt.alpha(Colors.primary, 0.16) : "transparent")

                    HoverHandler { id: devRowHover }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 9 * root.s
                        anchors.right: parent.right
                        anchors.rightMargin: 9 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: menu.labelOf(devRow.modelData)
                        elide: Text.ElideRight
                        color: devRow.current ? Colors.on_surface : Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 10.5 * root.s
                        font.weight: devRow.current ? Font.Bold : Font.Medium
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            menu.pick(devRow.modelData);
                            root.openPicker = "";
                        }
                    }
                }
            }
        }
    }

    DeviceMenu {
        kind: "out"
        model: root.outputSinks
        current: root.sink
        onPick: (node) => Pipewire.preferredDefaultAudioSink = node
    }

    DeviceMenu {
        kind: "in"
        model: root.inputSources
        current: root.source
        onPick: (node) => Pipewire.preferredDefaultAudioSource = node
    }

    // Bluetooth A2DP codec list; entries are {profile,label,active} from the
    // pactl card probe, picking one switches the bluez card profile.
    DeviceMenu {
        kind: "codec"
        model: root.btCodecs
        menuWidth: 150 * root.s
        labelOf: (m) => (m && m.label) ? m.label : ""
        isCurrent: (m) => m !== null && m !== undefined && m.active === true
        onPick: (entry) => root.switchCodec(entry)
    }

    /**
     * Vertical ink-fader (Ricelin VFader visual): a thin matte thread with a
     * rising fill and a flat tick marker, readout + icon + label beneath. Dim
     * at rest; saturates and reveals its readout when the pointer column
     * focuses it. Clicking the icon/label toggles the node's mute.
     */
    component InkFader: Item {
        id: fader

        property var node: null
        property string label: ""
        property string iconSource: ""
        property string glyph: "music"
        property bool focused: false
        /** Backlight column: value/set route to the Backlight singleton, no mute. */
        property bool brightnessMode: false

        readonly property bool ready: brightnessMode ? Backlight.present
            : (node !== null && node.audio !== null)
        readonly property real value: {
            // node.audio.volume / Backlight.brightness can arrive NaN; Math.max
            // and Math.min pass NaN through, which formats as "NaN%".
            var v = brightnessMode ? root.brightnessShown
                : (ready ? node.audio.volume : 0);
            v = Number.isFinite(v) ? v : 0;
            return Math.max(0, Math.min(fader.faderMax, v));
        }
        readonly property bool muted: !brightnessMode && ready && node.audio.muted
        readonly property bool lit: focused

        readonly property real trackH: 86 * root.s

        // Volume may over-amplify up to 150%; brightness stays capped at 100%.
        readonly property real faderMax: fader.brightnessMode ? 1.0 : 1.5
        readonly property bool overAmp: !fader.brightnessMode && fader.value > 1.001

        function setVolume(v) {
            v = Math.max(0, Math.min(fader.faderMax, v));
            if (brightnessMode)
                root.setBrightness(v);
            else if (ready)
                node.audio.volume = v;
        }

        /** Nudge by a signed percentage, clamped, for wheel stepping. */
        function step(deltaPct) {
            setVolume(value + deltaPct / 100);
        }

        Item {
            id: trackArea
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 22 * root.s
            height: fader.trackH

            Rectangle {
                id: thread
                anchors.horizontalCenter: parent.horizontalCenter
                width: 2 * root.s
                height: parent.height
                radius: width / 2
                color: Colors.surface_container_highest

                Rectangle {
                    id: fill
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: parent.height * Math.max(0, Math.min(1, fader.value / fader.faderMax))
                    radius: parent.radius
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: fader.muted ? Qt.alpha(Colors.outline, 0.7)
                                : (fader.overAmp ? Colors.error
                                    : (fader.lit ? Colors.primary : Qt.alpha(Colors.primary, 0.6)))
                        }
                        GradientStop {
                            position: 1.0
                            color: fader.muted ? Qt.alpha(Colors.outline, 0.5)
                                : (fader.lit ? Qt.darker(Colors.primary, 1.18)
                                    : Qt.alpha(Qt.darker(Colors.primary, 1.18), 0.6))
                        }
                    }
                    Behavior on height { enabled: !dragArea.pressed; NumberAnimation { duration: Motion.fast } }
                }
            }

            // 100% reference — above this the sink is over-amplified.
            Rectangle {
                visible: !fader.brightnessMode
                anchors.horizontalCenter: parent.horizontalCenter
                y: fader.trackH * (1 - 1 / fader.faderMax) - height / 2
                width: 8 * root.s
                height: 1.5 * root.s
                radius: height / 2
                color: Qt.alpha(Colors.on_surface, 0.4)
                z: 1
            }

            Rectangle {
                id: tick
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(0, Math.min(fader.trackH - height,
                    (1 - Math.max(0, Math.min(1, fader.value / fader.faderMax))) * fader.trackH - height / 2))
                width: 11 * root.s
                height: 2.5 * root.s
                radius: 2 * root.s
                color: Colors.on_surface_variant
                opacity: fader.focused ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                Behavior on y { enabled: !dragArea.pressed; NumberAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                anchors.margins: -10 * root.s
                preventStealing: true
                enabled: fader.ready
                function setFromY(my) {
                    fader.setVolume(fader.faderMax * (1 - Math.max(0, Math.min(1, (my - 10 * root.s) / fader.trackH))));
                }
                onPressed: (e) => setFromY(e.y)
                onPositionChanged: (e) => { if (pressed) setFromY(e.y); }
                // Brightness writes are debounced; commit immediately on release
                // so a quick drag isn't lost if the surface closes right after.
                onReleased: if (fader.brightnessMode) root.commitBrightnessNow()
                onCanceled: if (fader.brightnessMode) root.commitBrightnessNow()
            }
        }

        Text {
            id: readout
            anchors.top: trackArea.bottom
            anchors.topMargin: 7 * root.s
            anchors.horizontalCenter: parent.horizontalCenter
            text: fader.muted ? "off" : Math.round(fader.value * 100) + "%"
            color: fader.lit ? Colors.on_surface : Colors.on_surface_variant
            opacity: fader.lit || fader.muted ? 1 : 0
            font.family: Appearance.font.family
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        Item {
            id: iconBox
            anchors.top: readout.bottom
            anchors.topMargin: 3 * root.s
            anchors.horizontalCenter: parent.horizontalCenter
            width: 18 * root.s
            height: 18 * root.s

            IconImage {
                anchors.fill: parent
                source: fader.iconSource
                visible: fader.iconSource.length > 0
                opacity: fader.muted ? 0.45 : 1
            }
            GlyphIcon {
                anchors.fill: parent
                visible: fader.iconSource.length === 0
                name: fader.muted && fader.glyph === "speaker" ? "speaker-off" : fader.glyph
                color: fader.muted ? Qt.alpha(Colors.on_surface_variant, 0.65)
                    : (fader.lit ? Colors.on_surface : Colors.on_surface_variant)
                stroke: 1.7
            }
        }

        Text {
            id: subLabel
            anchors.top: iconBox.bottom
            anchors.topMargin: 1 * root.s
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, fader.width - 4 * root.s)
            horizontalAlignment: Text.AlignHCenter
            text: fader.label
            elide: Text.ElideRight
            maximumLineCount: 1
            color: fader.lit ? Colors.on_surface : Qt.alpha(Colors.on_surface_variant, 0.65)
            font.family: Appearance.font.family
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3 * root.s
        }

        // Icon/label tap toggles mute (Ricelin mic-fader affordance).
        // Brightness has no mute, so the tap target is off in that mode.
        MouseArea {
            anchors.top: readout.top
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: 30 * root.s
            enabled: fader.ready && !fader.brightnessMode
            cursorShape: Qt.PointingHandCursor
            onClicked: fader.node.audio.muted = !fader.node.audio.muted
        }
    }

    // ── fader row: brightness + master + one per playback stream ────────────
    Row {
        id: faderRow
        anchors.top: divider.bottom
        anchors.topMargin: 10 * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        height: 142 * root.s
        spacing: 0

        // Columns span the full surface width and the row is centered, so 1-2
        // faders sit evenly spaced across the surface (each fader's content is
        // centered in its column) instead of clustered in a narrow center band.
        readonly property real colW: root.width / Math.max(1, root.faderCount)

        /**
         * Laptop-backlight brightness, leftmost like Ricelin's fader order; a
         * Loader so machines without a panel skip the column entirely.
         * Ricelin also carries ddcutil-brightness and vibrance (nvibrant)
         * faders here; both are omitted — neither tool is installed on this
         * machine, and Backlight covers the panel that is.
         */
        Loader {
            active: Backlight.present
            visible: active
            width: active ? faderRow.colW : 0
            height: faderRow.height

            sourceComponent: InkFader {
                width: faderRow.colW
                height: faderRow.height
                brightnessMode: true
                label: "Brightness"
                glyph: "sun"
                focused: root.focusIndex === 0
            }
        }

        InkFader {
            width: faderRow.colW
            height: faderRow.height
            node: root.sink
            label: "Master"
            glyph: "speaker"
            focused: root.focusIndex === root.brCount
        }

        Repeater {
            model: root.streams

            InkFader {
                required property var modelData
                required property int index
                width: faderRow.colW
                height: faderRow.height
                node: modelData
                label: root.nodeLabel(modelData)
                iconSource: root.nodeIcon(modelData)
                glyph: "music"
                focused: root.focusIndex === index + root.brCount + 1
            }
        }
    }

    Text {
        anchors.top: faderRow.top
        anchors.topMargin: 40 * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.streams.length === 0
        text: "Nothing playing"
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 10.5 * root.s
    }

    // Wheel nudges the hovered fader column.
    MouseArea {
        id: wheelArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        property real acc: 0
        onWheel: (event) => {
            acc += event.angleDelta.y / 120;
            const notches = Math.trunc(acc);
            if (notches !== 0 && root.focusIndex >= 0) {
                const f = faderAt(root.focusIndex);
                if (f) {
                    f.step(notches * 5);
                    acc -= notches;
                }
            }
            event.accepted = true;
        }

        /**
         * i-th fader in visual order. The row's children are the brightness
         * Loader (unwrapped to its InkFader, null while inactive), the master
         * fader, the stream delegates, then the Repeater itself — anything
         * without a step() is skipped.
         */
        function faderAt(i) {
            for (var c = 0, k = 0; c < faderRow.children.length; c++) {
                var it = faderRow.children[c];
                if (it && it.step === undefined && it.item !== undefined)
                    it = it.item;
                if (it && it.step !== undefined) {
                    if (k === i)
                        return it;
                    k++;
                }
            }
            return null;
        }
    }
}
