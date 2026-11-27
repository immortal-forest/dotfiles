pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import ".."
import "../m3"
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — volume mixer surface (Ricelin Mixer.qml layout). "調 MIXER"
 * header with output/input route pickers and mute chips on the right, a
 * hairline divider, then a row of vertical ink-faders: one brightness fader
 * per screen (leftmost; laptop backlight and DDC monitors), the default sink
 * (master) plus one per Pipewire playback stream, each an M3 Expressive slider (thick track, gapped
 * handle bar, stop dots), the app icon and a short label beneath.
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
    // Docked centred, in the strip BELOW the column labels: the labels end ~8·s
    // above this surface's bottom edge and a column's icon + label sit on the
    // centre line for an odd fader count, so the bead rests just past the
    // content box (4·s below it, i.e. 8·s above the pill's bottom edge, inside
    // the 12·s bottom margin) instead of on any column or boundary.
    // 226·s tall (Pill.qml) leaves a strip under the labels: the bead docks
    // in it, clear of the labels above and the rim below.
    amePoint: Qt.point(width / 2, height - 6 * s)

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    /**
     * The header's icon buttons are Ricelin-sized 26dp, not M3's 40dp icon
     * button (the codec pill beside them is 26 too). They are handed a scaled-down `s` rather than an overridden
     * `width`, because `s` is the one knob every m3/ component is built to take
     * — it carries the glyph, the corner radius, the hit-target floor and the
     * focus-ring offset down with it, where a bare width override would leave
     * all four sized for a 40dp button.
     */
    readonly property real hdrBtnS: root.s * 26 / M3.iconButtonSize

    /**
     * Screen-reader names have to say WHICH device is being muted or routed —
     * "Mute" alone is useless on a surface that carries several mutes.
     */
    readonly property string sinkName: deviceLabel(sink) || "output device"
    readonly property string sourceName: deviceLabel(source) || "input device"

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

    /**
     * Streams folded per app: a browser keeps one idle playback stream per
     * tab/media element (Zen held 33), and a fader each is a wall of
     * identical columns. One fader per app; its writes fan out to every
     * stream in the group, its reading follows the first.
     */
    readonly property var streamGroups: {
        var byKey = {};
        var out = [];
        for (var i = 0; i < streams.length; i++) {
            var n = streams[i];
            var p = n.properties || {};
            var key = p["application.process.binary"] || p["application.name"] || n.name || ("node" + n.id);
            if (!byKey[key]) {
                byKey[key] = { key: key, lead: n, nodes: [] };
                out.push(byKey[key]);
            }
            byKey[key].nodes.push(n);
        }
        return out;
    }

    /** One brightness column per screen with a control (panel backlight or DDC). */
    readonly property int brCount: Brightness.outputs.length
    readonly property int faderCount: brCount + 1 + streamGroups.length

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
            Brightness.refresh(); // pick up changes made with the monitor's own buttons
        }
    }

    // Volume/mute props only populate while their node is bound.
    PwObjectTracker {
        objects: [root.sink, root.source]
            .concat(root.streams).concat(root.outputSinks).concat(root.inputSources)
            .filter(Boolean)
    }

    /** Output/input route picker in the header: device glyph + chevron. */
    component RouteChip: Rectangle {
        id: chip
        property string glyph: ""
        property string kind: ""
        property string accessibleName: ""
        readonly property bool open: root.openPicker === chip.kind
        anchors.verticalCenter: parent.verticalCenter
        height: 26 * root.s
        width: chipRow.implicitWidth + 18 * root.s
        radius: height / 2
        color: chip.open ? Qt.alpha(Colors.primary, 0.20) : Colors.surface_container_highest
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        M3StateLayer {
            anchors.fill: parent
            s: root.s
            radius: chip.radius
            contentColor: chip.open ? Colors.primary : Colors.on_surface
            pressScale: 0.92
            minTarget: 26
            accessibleRole: Accessible.Button
            accessibleName: chip.accessibleName
            onClicked: root.openPicker = chip.open ? "" : chip.kind
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 3 * root.s
            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * root.s
                height: 14 * root.s
                name: chip.glyph
                stroke: 1.8
                color: chip.open ? Colors.primary : Colors.on_surface_variant
            }
            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 11 * root.s
                height: 11 * root.s
                name: "chevron-down"
                stroke: 2
                color: chip.open ? Colors.primary : Colors.on_surface_variant
                rotation: chip.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            }
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
            id: hdrActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s

            // Bluetooth codec pill: the wire codec of the active bluez sink,
            // opening the codec menu. Hidden entirely unless the default sink
            // is Bluetooth *and* its codecs were queryable.
            //
            // Drawn in the shell's own header-action idiom (the notification
            // centre's "Clear all": a 26-high stadium with a soft role tint,
            // a 13 glyph and an 11 DemiBold label), not as an M3 assist chip.
            // The spec chip is an outlined 8dp rectangle, which made it the
            // only rule and the only square corner in a header of borderless
            // round buttons. It deepens while its menu is open, as the route
            // pickers beside it light up for theirs.
            Rectangle {
                id: codecChip
                readonly property bool open: root.openPicker === "codec"
                anchors.verticalCenter: parent.verticalCenter
                visible: root.sinkIsBluez && root.btCodecs.length > 0
                // Mid-switch the profile swap tears the sink down, so a second
                // click genuinely cannot land: the label dims to M3's disabled
                // content opacity and the pill stops answering.
                enabled: !root.btCodecSwitching
                height: 26 * root.s
                width: codecRow.implicitWidth + 22 * root.s
                radius: height / 2
                color: Qt.alpha(Colors.primary, open ? 0.20 : 0.10)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                M3StateLayer {
                    anchors.fill: parent
                    enabled: codecChip.enabled
                    s: root.s
                    radius: codecChip.radius
                    contentColor: Colors.primary
                    // The shell's deep dip for small text-button targets.
                    pressScale: 0.92
                    minTarget: 26
                    accessibleRole: Accessible.Button
                    accessibleName: "Bluetooth audio codec, " + root.btCodecChipText
                    onClicked: root.openPicker = codecChip.open ? "" : "codec"
                }

                Row {
                    id: codecRow
                    anchors.centerIn: parent
                    spacing: 6 * root.s
                    opacity: codecChip.enabled ? 1 : M3.disabledContentOpacity
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * root.s
                        height: 13 * root.s
                        name: "bluetooth"
                        stroke: 1.8
                        color: Colors.primary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.btCodecChipText
                        color: Colors.primary
                        font.family: Appearance.font.family
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                    }
                }
            }

            // Route pickers are dropdown chips — device glyph + chevron, the
            // codec chip's stadium in the neutral fill, primary while their
            // menu is open — so they can't be mistaken for the two mutes
            // after them. As four look-alike icon buttons the header read
            // "speaker, mic, speaker, mic": the same glyph did two jobs.
            RouteChip {
                id: outBtn
                glyph: "speaker"
                kind: "out"
                accessibleName: "Output device, " + root.sinkName
            }
            RouteChip {
                id: inBtn
                glyph: "mic"
                kind: "in"
                accessibleName: "Input device, " + root.sourceName
            }

            // The mutes stay bare toggle icon buttons: "standard" is the only
            // variant whose off-state stays transparent (the header reads
            // quiet) while its on-state is still unambiguous — the accent
            // glyph. A wider gap than the chips' own sets them apart.
            Item { width: 2 * root.s; height: 1 }

            M3IconButton {
                anchors.verticalCenter: parent.verticalCenter
                s: root.hdrBtnS
                icon: root.sink && root.sink.audio && root.sink.audio.muted ? "speaker-off" : "speaker"
                toggle: true
                checked: root.sink !== null && root.sink.audio !== null && root.sink.audio.muted
                enabled: root.sink !== null && root.sink.audio !== null
                accessibleName: "Mute " + root.sinkName
                onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
            }
            M3IconButton {
                anchors.verticalCenter: parent.verticalCenter
                s: root.hdrBtnS
                icon: root.source && root.source.audio && root.source.audio.muted ? "mic-off" : "mic"
                toggle: true
                checked: root.source !== null && root.source.audio !== null && root.source.audio.muted
                enabled: root.source !== null && root.source.audio !== null
                accessibleName: "Mute " + root.sourceName
                onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
            }
        }
    }

    // Centred between the header controls and the fader caps (it sat 14px
    // under the controls but 21px over the caps). The device chip hangs ~1
    // below the header's box (negative air); the caps start ~1.5 into
    // their row.
    Rule {
        id: divider
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 19 * root.s + 1
        airAbove: -1 * root.s
        airBelow: 1.5 * root.s
    }

    // Outside-click catcher: a press off an open dropdown closes it. Sits
    // under the header (z 5) so its toggles still switch menus in one click.
    MouseArea {
        anchors.fill: parent
        z: 4
        enabled: root.openPicker !== ""
        onPressed: root.openPicker = ""
    }

    /**
     * Device dropdown. All three pickers share pill/DropMenu: `kind` keys it
     * to root.openPicker, `anchorItem` is the header control that opened it —
     * the menu hangs under that control, right edges aligned, clamped inside
     * the surface. It floats over the faders so the mixer height stays fixed.
     */
    component DeviceMenu: DropMenu {
        id: menu
        property string kind: ""
        property Item anchorItem
        property var current
        s: root.s
        z: 7
        open: root.openPicker === kind
        labelOf: (m) => root.deviceLabel(m)
        isCurrent: (m) => m === menu.current
        width: 300 * root.s
        y: divider.y + divider.line.y + 4 * root.s
        x: anchorItem ? Math.max(0, Math.min(root.width - width,
            hdrActions.x + anchorItem.x + anchorItem.width - width)) : root.width - width
        onPicked: root.openPicker = ""
    }

    DeviceMenu {
        kind: "out"
        anchorItem: outBtn
        options: root.outputSinks
        current: root.sink
        onPicked: (node) => Pipewire.preferredDefaultAudioSink = node
    }

    DeviceMenu {
        kind: "in"
        anchorItem: inBtn
        options: root.inputSources
        current: root.source
        onPicked: (node) => Pipewire.preferredDefaultAudioSource = node
    }

    // Bluetooth A2DP codec list; entries are {profile,label,active} from the
    // pactl card probe, picking one switches the bluez card profile.
    DeviceMenu {
        kind: "codec"
        anchorItem: codecChip
        options: root.btCodecs
        width: Math.max(150 * root.s, codecChip.width)
        labelOf: (m) => (m && m.label) ? m.label : ""
        isCurrent: (m) => m !== null && m !== undefined && m.active === true
        onPicked: (entry) => root.switchCodec(entry)
    }

    /**
     * Vertical ink-fader: M3 Expressive slider track split by a
     * thin handle with gaps either side, readout + icon + label beneath. Dim
     * at rest; saturates and reveals its readout when the pointer column
     * focuses it. Clicking the icon/label toggles the node's mute.
     */
    component InkFader: Item {
        id: fader

        property var node: null
        /** Every node this fader drives (a folded app group); defaults to `node`. */
        property var nodes: node ? [node] : []
        property string label: ""
        property string iconSource: ""
        property string glyph: "music"
        property bool focused: false
        /**
         * Brightness column for `output`, no mute: the laptop panel keeps the
         * debounced brightnessLocal scheme; a DDC monitor goes straight to
         * Brightness, which is already optimistic and coalesces its writes.
         */
        property bool brightnessMode: false
        property string output: ""
        readonly property bool panelMode: brightnessMode && Brightness.isPanel(output)

        readonly property bool ready: brightnessMode ? Brightness.presentOn(output)
            : (node !== null && node.audio !== null)
        readonly property real value: {
            // node.audio.volume / Backlight.brightness can arrive NaN; Math.max
            // and Math.min pass NaN through, which formats as "NaN%".
            var v = panelMode ? root.brightnessShown
                : brightnessMode ? Brightness.levelOf(output)
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
            if (panelMode)
                root.setBrightness(v);
            else if (brightnessMode)
                Brightness.set(output, v);
            else if (ready)
                for (var i = 0; i < nodes.length; i++)
                    if (nodes[i] && nodes[i].audio)
                        nodes[i].audio.volume = v;
        }

        /** Nudge by a signed percentage, clamped, for wheel stepping. */
        function toggleMute() {
            var m = !node.audio.muted;
            for (var i = 0; i < nodes.length; i++)
                if (nodes[i] && nodes[i].audio)
                    nodes[i].audio.muted = m;
        }

        function step(deltaPct) {
            setVolume(value + deltaPct / 100);
        }

        // No `.value` on Accessible (quickshell-core.md §9b) — the level is
        // read through description text, and increase/decrease drive it the
        // same amount a wheel notch does (see `step`).
        Accessible.role: Accessible.Slider
        Accessible.name: fader.label.length > 0 ? fader.label : (fader.brightnessMode ? "Brightness" : "Volume")
        Accessible.description: fader.muted ? "Muted" : Math.round(fader.value * 100) + " percent"
        Accessible.focusable: fader.ready
        Accessible.onIncreaseAction: fader.step(5)
        Accessible.onDecreaseAction: fader.step(-5)

        Item {
            id: trackArea
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 34 * root.s
            height: fader.trackH

            // M3 Expressive slider, vertical: a thick rounded track split by
            // a thin handle bar, with a gap either side of it. Active segment
            // below in primary, inactive above in surface_container_highest,
            // and stop dots marking the top end (and 100% when it can
            // over-amp). The spec's secondary_container comes out a saturated
            // dark red under a bold/vivid palette, heavier than the pale
            // active fill, so 4% read as nearly full; the inactive side must
            // stay the quiet one whatever the wallpaper.
            readonly property real frac: Math.max(0, Math.min(1, fader.value / fader.faderMax))
            readonly property real trackW: 18 * root.s
            readonly property real gap: 4 * root.s
            readonly property real handleH: 4 * root.s
            property real handleY: (1 - frac) * fader.trackH
            readonly property real outerR: 8 * root.s
            readonly property real innerR: 2 * root.s
            readonly property color activeColor: fader.muted ? Colors.outline
                : (fader.overAmp ? Colors.error : Colors.primary)

            Behavior on handleY {
                enabled: !dragArea.pressed
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            Rectangle {
                id: inactiveSeg
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: trackArea.trackW
                height: Math.max(0, trackArea.handleY - trackArea.handleH / 2 - trackArea.gap)
                visible: height > 0.5
                color: Colors.surface_container_highest
                topLeftRadius: trackArea.outerR
                topRightRadius: trackArea.outerR
                bottomLeftRadius: Math.min(trackArea.innerR, height / 2)
                bottomRightRadius: Math.min(trackArea.innerR, height / 2)
            }

            Rectangle {
                id: activeSeg
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.min(fader.trackH, trackArea.handleY + trackArea.handleH / 2 + trackArea.gap)
                width: trackArea.trackW
                height: Math.max(0, fader.trackH - y)
                visible: height > 0.5
                color: trackArea.activeColor
                opacity: fader.lit || fader.muted ? 1 : 0.8
                bottomLeftRadius: trackArea.outerR
                bottomRightRadius: trackArea.outerR
                topLeftRadius: Math.min(trackArea.innerR, height / 2)
                topRightRadius: Math.min(trackArea.innerR, height / 2)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }

            // Stop indicator at the top end of the inactive track.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 5 * root.s
                width: 4 * root.s
                height: width
                radius: width / 2
                color: Colors.on_surface_variant
                visible: inactiveSeg.height > 12 * root.s
            }

            // 100% stop — above it the sink is over-amplified.
            Rectangle {
                readonly property real yC: fader.trackH * (1 - 1 / fader.faderMax)
                visible: !fader.brightnessMode
                    && Math.abs(yC - trackArea.handleY) > trackArea.handleH / 2 + trackArea.gap + 3 * root.s
                anchors.horizontalCenter: parent.horizontalCenter
                y: yC - height / 2
                width: 4 * root.s
                height: width
                radius: width / 2
                color: yC > trackArea.handleY ? Colors.on_primary : Colors.on_surface_variant
                z: 1
            }

            Rectangle {
                id: handle
                anchors.horizontalCenter: parent.horizontalCenter
                y: trackArea.handleY - height / 2
                width: (fader.lit || dragArea.pressed ? 34 : 30) * root.s
                height: (dragArea.pressed ? 3 : trackArea.handleH / root.s) * root.s
                radius: height / 2
                color: trackArea.activeColor
                Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                Behavior on height { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                Behavior on color { ColorAnimation { duration: Motion.fast } }
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
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }
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
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }
            GlyphIcon {
                anchors.fill: parent
                visible: fader.iconSource.length === 0
                name: fader.muted && fader.glyph === "speaker" ? "speaker-off" : fader.glyph
                color: fader.muted ? Qt.alpha(Colors.on_surface_variant, 0.65)
                    : (fader.lit ? Colors.on_surface : Colors.on_surface_variant)
                stroke: 1.7
                Behavior on color { ColorAnimation { duration: Motion.fast } }
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
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        // Icon/label tap toggles mute (Ricelin mic-fader affordance).
        // Brightness has no mute, so the tap target is off in that mode.
        MouseArea {
            id: muteArea
            anchors.top: readout.top
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: 30 * root.s
            enabled: fader.ready && !fader.brightnessMode
            cursorShape: Qt.PointingHandCursor
            onClicked: fader.toggleMute()

            Accessible.role: Accessible.CheckBox
            Accessible.name: "Mute " + (fader.label.length > 0 ? fader.label : "device")
            Accessible.checkable: true
            Accessible.checked: fader.muted
            Accessible.focusable: muteArea.enabled
            Accessible.onPressAction: fader.toggleMute()
        }
    }

    // ── fader row: brightness + master + one per playback stream ────────────
    Row {
        id: faderRow
        anchors.top: divider.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        height: 142 * root.s
        spacing: 0

        // Columns span the full surface width and the row is centered, so 1-2
        // faders sit evenly spaced across the surface (each fader's content is
        // centered in its column) instead of clustered in a narrow center band.
        readonly property real colW: root.width / Math.max(1, root.faderCount)

        /**
         * One brightness fader per screen, leftmost like Ricelin's fader
         * order, in the screens' left-to-right layout: the laptop panel
         * (Backlight) and any DDC/CI monitor (ddcutil), labelled "Laptop" /
         * the monitor's maker.
         */
        Repeater {
            model: Brightness.outputs

            InkFader {
                required property string modelData
                required property int index
                width: faderRow.colW
                height: faderRow.height
                brightnessMode: true
                output: modelData
                label: Brightness.labelOf(modelData)
                glyph: "sun"
                focused: root.focusIndex === index
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
            model: root.streamGroups

            InkFader {
                required property var modelData
                required property int index
                width: faderRow.colW
                height: faderRow.height
                node: modelData.lead
                nodes: modelData.nodes
                label: root.nodeLabel(modelData.lead)
                iconSource: root.nodeIcon(modelData.lead)
                glyph: "music"
                focused: root.focusIndex === index + root.brCount + 1
            }
        }
    }

    Text {
        anchors.top: faderRow.top
        anchors.topMargin: 40 * root.s
        // In the gap between the last brightness fader and Master — with
        // several screens the surface centre is a fader column.
        x: root.brCount > 0 ? faderRow.x + root.brCount * faderRow.colW - width / 2 : (parent.width - width) / 2
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
