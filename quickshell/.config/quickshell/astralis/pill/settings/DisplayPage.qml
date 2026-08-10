pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."
import "../../colors"
import "../../services"
import "../../services" as Services
import "../../config"
import "../lib/monitors.js" as Mon

/**
 * astralis — 画 DISPLAY settings page (ported from Ricelin pill/Display.qml).
 * A proportional mini-map of the monitor layout sits on top: one tile per
 * output (scaled from logical size, placed by real x/y), clicking a tile
 * selects it and dragging one snaps it left/right/above/below the other
 * monitor as a pending move. Below the map a single card edits the selected
 * output: resolution, refresh and scale from availableModes, plus a transform
 * seg (astralis addition — Ricelin had no rotation control).
 *
 * Ricelin delta: Ricelin hands the spec to display-apply.sh (detached 12s
 * watchdog that survives the pill) and persists by rewriting monitors.lua;
 * astralis applies live through one `hyprctl keyword monitor
 * "<name>,<res>@<hz>,<pos>,<scale>,transform,<t>"` (gated on
 * Services.Settings.liveApply so a harness never touches the session) with a
 * page-local 12s countdown that reverts the keyword if not confirmed — if the
 * shell dies mid-countdown the change survives until the next reload, the
 * accepted degradation of having no helper script. A confirmed Keep persists
 * through Settings.set("monitors", …), which re-emits the keyword (idempotent)
 * and regenerates the hypr-settings.lua overlay so the spec survives
 * `hyprctl reload`. Ricelin's "Set as main" workspace-loop swap is dropped —
 * astralis has no monitors.lua workspace loops to swap (workspace rules are
 * their own hand config).
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    property var monitors: []
    property string selName: ""
    property string openPicker: ""
    property string pendingOut: ""
    property int countdown: 0
    property string note: ""
    property bool quietRead: false

    /** Pending arrangement from a map drag: `{ name, side }`, or null. */
    property var pendingMove: null

    /** Specs bracketing an un-confirmed apply: what went live, what to revert to. */
    property var pendSpec: ({})
    property var prevSpec: ({})

    readonly property var selMon: monitorByName(selName)

    // The singleton, hoisted once (`Settings` unqualified would shadow-clash
    // with the surface type of the same name in importing contexts).
    readonly property var setStore: Services.Settings

    /** The stock scale strip, plus the live scale when it is not on it (fractional laptops). */
    readonly property var scaleOptions: {
        var vals = [1, 1.25, 1.5, 2];
        var mon = root.selMon;
        if (mon && vals.indexOf(mon.scale) === -1) {
            vals.push(mon.scale);
            vals.sort(function (a, b) { return a - b; });
        }
        return vals.map(function (v) {
            return { label: (v % 1 === 0 ? v.toFixed(1) : String(v)), value: v };
        });
    }

    readonly property var transformOptions: [
        { label: "0°", value: 0 },
        { label: "90°", value: 1 },
        { label: "180°", value: 2 },
        { label: "270°", value: 3 }
    ]

    onActiveChanged: {
        if (active) {
            readProc.running = true;
        } else {
            // Leaving mid-countdown counts as "not confirmed": put the old
            // spec back now — there is no detached watchdog to do it later.
            if (root.pendingOut.length > 0)
                root.revert("");
            root.openPicker = "";
            // focus/kbIndex reset on deactivate is handled by the SettingsPage base
        }
    }

    onSelMonChanged: if (selMon) card.syncToCurrent()

    rows: {
        void root.selMon;
        return [
            { item: resRow, kind: "scrub", bump: function (d) { card.bumpRes(d); } },
            { item: rateRow, kind: "scrub", bump: function (d) { card.bumpRate(d); } },
            { item: scaleRow, kind: "seg", vals: root.scaleOptions.map(function (o) { return o.value; }), get: function () { return card.pickScale; }, set: function (v) { card.pickScale = v; } },
            { item: transformRow, kind: "seg", vals: root.transformOptions.map(function (o) { return o.value; }), get: function () { return card.pickTransform; }, set: function (v) { card.pickTransform = v; } }
        ];
    }

    /**
     * Reduces a monitor's parsed modes to the list of distinct WxH, each
     * carrying the descending list of whole-number Hz offered for that
     * resolution. The native (current width/height) resolution sorts first,
     * then the rest by pixel count descending, so the default selection lands
     * on the panel's real mode.
     */
    function resolutionsFor(mon) {
        var byRes = {};
        for (var i = 0; i < mon.modes.length; i++) {
            var m = mon.modes[i];
            var key = m.w + "x" + m.h;
            if (!byRes[key])
                byRes[key] = { w: m.w, h: m.h, key: key, rates: [] };
            if (byRes[key].rates.indexOf(m.hz) === -1)
                byRes[key].rates.push(m.hz);
        }
        var list = [];
        for (var k in byRes) {
            byRes[k].rates.sort(function (a, b) { return b - a; });
            list.push(byRes[k]);
        }
        list.sort(function (a, b) {
            if (a.w === mon.width && a.h === mon.height) return -1;
            if (b.w === mon.width && b.h === mon.height) return 1;
            return (b.w * b.h) - (a.w * a.h);
        });
        return list;
    }

    function monitorByName(name) {
        for (var i = 0; i < monitors.length; i++)
            if (monitors[i].name === name)
                return monitors[i];
        return null;
    }

    /** The first monitor that is not `name`; the anchor for placement moves. */
    function otherMonitor(name) {
        for (var i = 0; i < monitors.length; i++)
            if (monitors[i].name !== name)
                return monitors[i];
        return null;
    }

    /** Logical (post-scale, post-transform) size of a monitor's mode pixels. */
    function logicalWH(w, h, scale, transform) {
        var lw = Math.round(w / scale);
        var lh = Math.round(h / scale);
        return (transform % 2) ? { w: lh, h: lw } : { w: lw, h: lh };
    }

    /**
     * Logical x/y of a monitor of `myW`x`myH` placed on `side` of `other`, top
     * or left edge aligned with the anchor. Negative coordinates are fine for
     * Hyprland, so left/above of an origin monitor need no re-anchoring.
     */
    function placementXY(other, side, myW, myH) {
        var o = logicalWH(other.width, other.height, other.scale, other.transform);
        if (side === "left")
            return { x: other.x - myW, y: other.y };
        if (side === "above")
            return { x: other.x, y: other.y - myH };
        if (side === "below")
            return { x: other.x, y: other.y + o.h };
        return { x: other.x + o.w, y: other.y };
    }

    /** The pending-move x/y for `mon` using the card's current size picks, or null. */
    function pendingXY(mon) {
        if (!pendingMove || pendingMove.name !== mon.name)
            return null;
        var other = otherMonitor(mon.name);
        if (!other || card.resolutions.length === 0)
            return null;
        var res = card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)];
        var my = logicalWH(res.w, res.h, card.pickScale, card.pickTransform);
        return placementXY(other, pendingMove.side, my.w, my.h);
    }

    /**
     * A dropped tile snaps to whichever side of the other monitor its centre
     * ended on, judged in tile-normalised offsets so flat and tall layouts
     * bias the same. A drop that lands the monitor back on its current x/y
     * clears the pending move instead of arming a no-op.
     */
    function dropTile(name, cx, cy) {
        var mon = monitorByName(name);
        var other = otherMonitor(name);
        if (!mon || !other)
            return;
        var oT = null;
        var tiles = mapLayout.tiles;
        for (var i = 0; i < tiles.length; i++)
            if (tiles[i].name !== name) { oT = tiles[i]; break; }
        if (!oT)
            return;
        var nx = (cx - (oT.x + oT.w / 2)) / oT.w;
        var ny = (cy - (oT.y + oT.h / 2)) / oT.h;
        var side = Math.abs(nx) >= Math.abs(ny) ? (nx < 0 ? "left" : "right") : (ny < 0 ? "above" : "below");
        var res = card.resolutions.length > 0 ? card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)] : null;
        var my = res ? logicalWH(res.w, res.h, card.pickScale, card.pickTransform)
            : logicalWH(mon.width, mon.height, mon.scale, mon.transform);
        var p = placementXY(other, side, my.w, my.h);
        pendingMove = (p.x === mon.x && p.y === mon.y) ? null : { name: name, side: side };
    }

    /**
     * Scaled tile geometry for the mini-map: logical rects (mode over scale,
     * pending move substituted for its monitor) fitted into the map width and
     * a capped height, centred horizontally. Selection state stays out of the
     * entries on purpose — it is read per-tile from root, so clicking a tile
     * never rebuilds the Repeater under an active press.
     */
    readonly property var mapLayout: {
        var mons = root.monitors;
        if (mons.length === 0 || mapBox.width <= 0)
            return { h: 0, tiles: [] };
        var rects = [];
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (var i = 0; i < mons.length; i++) {
            var m = mons[i];
            var lg = root.logicalWH(m.width, m.height, m.scale, m.transform);
            var r = { name: m.name, hz: m.refresh, x: m.x, y: m.y, w: lg.w, h: lg.h };
            var p = root.pendingXY(m);
            if (p) {
                var res = card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)];
                var my = root.logicalWH(res.w, res.h, card.pickScale, card.pickTransform);
                r.x = p.x;
                r.y = p.y;
                r.w = my.w;
                r.h = my.h;
            }
            rects.push(r);
            minX = Math.min(minX, r.x);
            minY = Math.min(minY, r.y);
            maxX = Math.max(maxX, r.x + r.w);
            maxY = Math.max(maxY, r.y + r.h);
        }
        var k = Math.min(mapBox.width / (maxX - minX), (96 * root.s) / (maxY - minY));
        var ox = (mapBox.width - (maxX - minX) * k) / 2;
        var tiles = rects.map(function (t) {
            return { name: t.name, hz: t.hz, x: ox + (t.x - minX) * k, y: (t.y - minY) * k, w: t.w * k, h: t.h * k };
        });
        return { h: (maxY - minY) * k, tiles: tiles };
    }

    Process {
        id: readProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.monitors = Mon.parse(this.text);
                if (!root.monitorByName(root.selName))
                    root.selName = root.monitors.length > 0 ? root.monitors[0].name : "";
                if (!root.quietRead)
                    root.note = "Changes apply live, no reload. If a mode looks wrong, it reverts on its own after 12s.";
                root.quietRead = false;
            }
        }
    }

    Process {
        id: applyProc
        property string spec: ""
        command: ["hyprctl", "keyword", "monitor", spec]
    }

    Process {
        id: revertProc
        property string spec: ""
        command: ["hyprctl", "keyword", "monitor", spec]
    }

    function specString(sp) {
        return sp.mode + "," + sp.position + "," + sp.scale + ",transform," + sp.transform;
    }

    /**
     * Applies whatever is pending on the selected monitor: one live monitor
     * keyword plus the 12s confirm countdown. Only availableModes Hz reach the
     * mode string, so an unsupported mode can never be requested. Nothing is
     * persisted here — that is Keep's job.
     */
    function apply() {
        var mon = root.selMon;
        if (!mon || root.pendingOut.length > 0 || !card.dirty)
            return;
        var res = card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)];
        var hz = res.rates[Math.min(card.rateIndex, res.rates.length - 1)];
        var p = pendingXY(mon);
        root.prevSpec = {
            mode: mon.width + "x" + mon.height + "@" + mon.refresh,
            position: mon.x + "x" + mon.y,
            scale: mon.scale,
            transform: mon.transform
        };
        root.pendSpec = {
            mode: res.w + "x" + res.h + "@" + hz,
            position: p ? p.x + "x" + p.y : mon.x + "x" + mon.y,
            scale: card.pickScale,
            transform: card.pickTransform
        };
        root.pendingOut = mon.name;
        if (root.setStore.liveApply) {
            applyProc.spec = mon.name + "," + specString(root.pendSpec);
            applyProc.running = true;
        }
        root.countdown = 12;
        countTimer.start();
    }

    /**
     * Confirm the pending change: stop the revert countdown and persist the
     * spec into the Settings store — set() re-emits the keyword (idempotent on
     * the already-live mode) and regenerates the hypr-settings.lua overlay so
     * the spec survives `hyprctl reload`. Then quietly re-read the live layout
     * so the map lands on ground truth.
     */
    function keep() {
        if (root.pendingOut.length === 0)
            return;
        var cur = root.setStore.get("monitors");
        var next = {};
        for (var k in cur)
            next[k] = cur[k];
        next[root.pendingOut] = root.pendSpec;
        var saved = "Saved. " + root.pendingOut + " set to " + root.pendSpec.mode + " · scale " + root.pendSpec.scale;
        root.setStore.set("monitors", next);
        root.cancelCountdown();
        root.pendingMove = null;
        root.quietRead = true;
        readProc.running = true;
        root.note = saved;
    }

    /** Put the pre-apply spec back live and forget the pending change. */
    function revert(msg) {
        if (root.pendingOut.length === 0)
            return;
        if (root.setStore.liveApply) {
            revertProc.spec = root.pendingOut + "," + specString(root.prevSpec);
            revertProc.running = true;
        }
        root.cancelCountdown();
        root.quietRead = msg.length === 0;
        readProc.running = true;
        if (msg.length > 0)
            root.note = msg;
    }

    function cancelCountdown() {
        countTimer.stop();
        root.countdown = 0;
        root.pendingOut = "";
    }

    Timer {
        id: countTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0)
                root.revert("Reverted — the change was not confirmed in time.");
        }
    }

    /**
     * One registry row inside the monitor card: a leading line icon, the
     * shared hover/focus treatment, and hover and clicks routed through
     * reportRowHover/activateRow so the soul seam and keyboard focus track
     * these rows like SettingsRow lines. The highlight hugs only the head
     * line, so an open dropdown grows past it.
     */
    component CardRow: Item {
        id: crow

        property string icon: ""
        default property alias content: crowInner.data

        readonly property bool focused: root.focusRowItem === crow

        width: parent ? parent.width : 0
        implicitHeight: crowInner.childrenRect.height

        HoverHandler {
            id: crowHover
            onHoveredChanged: root.reportRowHover(crow, hovered)
        }

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: -3 * root.s
            anchors.leftMargin: -7 * root.s
            anchors.rightMargin: -7 * root.s
            height: 32 * root.s
            radius: 8 * root.s
            color: (crowHover.hovered || crow.focused) ? Colors.surface_container_highest : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activateRow(crow)
        }

        GlyphIcon {
            id: crowIcon
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 5 * root.s
            width: 16 * root.s
            height: 16 * root.s
            name: crow.icon
            visible: crow.icon.length > 0
            color: crow.focused ? Colors.on_surface : Colors.on_surface_variant
            stroke: 1.8
        }

        Item {
            id: crowInner
            anchors.left: crowIcon.right
            anchors.leftMargin: 9 * root.s
            anchors.right: parent.right
            anchors.top: parent.top
            height: childrenRect.height
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "画"
        title: "DISPLAY"
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

            Item { width: 1; height: 12 * root.s }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12 * root.s
                anchors.rightMargin: 12 * root.s
                spacing: 12 * root.s

                Item {
                    id: mapBox
                    width: parent.width
                    height: root.mapLayout.h
                    Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                    Repeater {
                        model: root.mapLayout.tiles

                        Rectangle {
                            id: tile
                            required property var modelData

                            readonly property bool sel: tile.modelData.name === root.selName
                            readonly property bool moved: root.pendingMove !== null && root.pendingMove.name === tile.modelData.name
                            property real dx: 0
                            property real dy: 0

                            x: tile.modelData.x + 1.5 * root.s + dx
                            y: tile.modelData.y + 1.5 * root.s + dy
                            width: Math.max(2, tile.modelData.w - 3 * root.s)
                            height: Math.max(2, tile.modelData.h - 3 * root.s)
                            z: tileMA.pressed ? 10 : (tile.sel ? 5 : 0)
                            radius: 7 * root.s
                            color: tile.sel ? Qt.alpha(Colors.primary, 0.13) : Colors.surface_container_high
                            border.width: 1
                            border.color: tile.moved ? Qt.alpha(Colors.tertiary, 0.7)
                                : (tile.sel ? Colors.on_surface : Qt.alpha(Colors.on_surface, 0.06))

                            Behavior on x { enabled: !tileMA.pressed; NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                            Behavior on y { enabled: !tileMA.pressed; NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 2 * root.s

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.name
                                    color: tile.sel ? Colors.on_surface : Colors.on_surface_variant
                                    font.family: Appearance.font.family
                                    font.pixelSize: 10 * root.s
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.hz + "Hz"
                                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                                    font.family: Appearance.font.family
                                    font.pixelSize: 8.5 * root.s
                                    font.weight: Font.Medium
                                    font.features: ({ "tnum": 1 })
                                }
                            }

                            /**
                             * Manual drag: local deltas accumulate onto the
                             * layout position, so the binding keeps owning x/y
                             * and the snap animation plays the moment the
                             * deltas reset on release.
                             */
                            MouseArea {
                                id: tileMA
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: pressed ? Qt.ClosedHandCursor : (root.monitors.length >= 2 ? Qt.OpenHandCursor : Qt.PointingHandCursor)
                                property real sx: 0
                                property real sy: 0
                                onPressed: (mouse) => {
                                    if (root.pendingOut.length === 0)
                                        root.selName = tile.modelData.name;
                                    sx = mouse.x;
                                    sy = mouse.y;
                                }
                                onPositionChanged: (mouse) => {
                                    if (!pressed || root.monitors.length < 2 || root.pendingOut.length > 0)
                                        return;
                                    tile.dx += mouse.x - sx;
                                    tile.dy += mouse.y - sy;
                                }
                                onReleased: {
                                    if (tile.dx !== 0 || tile.dy !== 0)
                                        root.dropTile(tile.modelData.name, tile.x + tile.width / 2, tile.y + tile.height / 2);
                                    tile.dx = 0;
                                    tile.dy = 0;
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: card
                    visible: root.selMon !== null
                    width: parent.width
                    radius: Motion.rTile * root.s
                    color: Colors.surface_container_high
                    border.width: 1
                    border.color: card.pending ? Qt.alpha(Colors.tertiary, 0.55) : Qt.alpha(Colors.on_surface, 0.06)
                    implicitHeight: cardCol.implicitHeight + 22 * root.s
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    property int resIndex: 0
                    property int rateIndex: 0
                    property real pickScale: 1
                    property int pickTransform: 0

                    readonly property var resolutions: root.selMon ? root.resolutionsFor(root.selMon) : []
                    readonly property var rates: resolutions.length > 0 ? resolutions[Math.min(resIndex, resolutions.length - 1)].rates : []
                    readonly property bool pending: root.selMon !== null && root.pendingOut === root.selMon.name

                    /** Anything apply would change: mode, scale, transform or a dragged move. */
                    readonly property bool dirty: {
                        var mon = root.selMon;
                        if (!mon || card.resolutions.length === 0)
                            return false;
                        var res = card.resolutions[Math.min(card.resIndex, card.resolutions.length - 1)];
                        var hz = res.rates[Math.min(card.rateIndex, res.rates.length - 1)];
                        if (res.w !== mon.width || res.h !== mon.height || hz !== mon.refresh)
                            return true;
                        if (card.pickScale !== mon.scale)
                            return true;
                        if (card.pickTransform !== mon.transform)
                            return true;
                        var p = root.pendingXY(mon);
                        return p !== null && (p.x !== mon.x || p.y !== mon.y);
                    }

                    /**
                     * Seeds from locally computed lists, never from
                     * `card.rates`: inside onSelMonChanged the dependent
                     * bindings can still hold the previous monitor's values
                     * (handler order vs binding invalidation), which would
                     * seed one output's rate index against another's list.
                     */
                    function syncToCurrent() {
                        var mon = root.selMon;
                        if (!mon)
                            return;
                        var resos = root.resolutionsFor(mon);
                        var ri = 0;
                        for (var i = 0; i < resos.length; i++) {
                            if (resos[i].w === mon.width && resos[i].h === mon.height) {
                                ri = i;
                                break;
                            }
                        }
                        card.resIndex = ri;
                        card.rateIndex = card.nearestIn(resos.length > 0 ? resos[ri].rates : [], mon.refresh);
                        card.pickScale = mon.scale;
                        card.pickTransform = mon.transform;
                        if (root.pendingMove)
                            root.pendingMove = null;
                        root.openPicker = "";
                    }

                    function nearestIn(rates, hz) {
                        var best = 0;
                        var bestDiff = 1e9;
                        for (var i = 0; i < rates.length; i++) {
                            var d = Math.abs(rates[i] - hz);
                            if (d < bestDiff) { bestDiff = d; best = i; }
                        }
                        return best;
                    }

                    function nearestRateIndex(hz) {
                        return nearestIn(card.rates, hz);
                    }

                    function bumpRes(d) {
                        var i = Math.max(0, Math.min(card.resolutions.length - 1, card.resIndex + d));
                        if (i === card.resIndex)
                            return;
                        card.resIndex = i;
                        card.rateIndex = card.nearestRateIndex(card.rates.length > 0 ? card.rates[0] : 60);
                    }

                    function bumpRate(d) {
                        var cur = Math.min(card.rateIndex, Math.max(0, card.rates.length - 1));
                        card.rateIndex = Math.max(0, Math.min(card.rates.length - 1, cur + d));
                    }

                    Column {
                        id: cardCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 13 * root.s
                        anchors.rightMargin: 13 * root.s
                        anchors.topMargin: 11 * root.s
                        spacing: 9 * root.s

                        Text {
                            text: root.selMon ? root.selMon.name : ""
                            color: Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 12.5 * root.s
                            font.weight: Font.Bold
                            font.letterSpacing: 0.3 * root.s
                        }

                        CardRow {
                            id: resRow
                            icon: "monitor"
                            // Float above the rows below while the dropdown is open
                            // so its overlay panel paints over (and catches clicks
                            // for) Refresh/Scale/Rotation instead of pushing them down.
                            z: root.openPicker === root.selName + ":res" ? 20 : 0

                            DisplayPicker {
                                width: parent.width
                                s: root.s
                                label: "Resolution"
                                options: card.resolutions.map(function (r, i) { return { label: r.w + "×" + r.h, value: i }; })
                                value: card.resIndex
                                open: root.openPicker === root.selName + ":res"
                                onRequestToggle: root.openPicker = (root.openPicker === root.selName + ":res" ? "" : root.selName + ":res")
                                onPicked: (v) => {
                                    card.resIndex = v;
                                    card.rateIndex = card.nearestRateIndex(card.rates.length > 0 ? card.rates[0] : 60);
                                    root.openPicker = "";
                                }
                            }
                        }

                        CardRow {
                            id: rateRow
                            icon: "reboot"
                            z: root.openPicker === root.selName + ":rate" ? 20 : 0

                            DisplayPicker {
                                width: parent.width
                                s: root.s
                                label: "Refresh"
                                options: card.rates.map(function (hz, i) { return { label: hz + "Hz", value: i }; })
                                value: Math.min(card.rateIndex, Math.max(0, card.rates.length - 1))
                                open: root.openPicker === root.selName + ":rate"
                                onRequestToggle: root.openPicker = (root.openPicker === root.selName + ":rate" ? "" : root.selName + ":rate")
                                onPicked: (v) => {
                                    card.rateIndex = v;
                                    root.openPicker = "";
                                }
                            }
                        }

                        CardRow {
                            id: scaleRow
                            icon: "scaling"

                            Row {
                                width: parent.width
                                spacing: 8 * root.s

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 64 * root.s
                                    text: "Scale"
                                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                                    font.family: Appearance.font.family
                                    font.pixelSize: 10.5 * root.s
                                    font.weight: Font.Medium
                                }

                                SettingsSeg {
                                    anchors.verticalCenter: parent.verticalCenter
                                    s: root.s
                                    options: root.scaleOptions
                                    value: card.pickScale
                                    onPicked: (v) => card.pickScale = v
                                }
                            }
                        }

                        CardRow {
                            id: transformRow
                            icon: "record"

                            Row {
                                width: parent.width
                                spacing: 8 * root.s

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 64 * root.s
                                    text: "Rotation"
                                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                                    font.family: Appearance.font.family
                                    font.pixelSize: 10.5 * root.s
                                    font.weight: Font.Medium
                                }

                                SettingsSeg {
                                    anchors.verticalCenter: parent.verticalCenter
                                    s: root.s
                                    options: root.transformOptions
                                    value: card.pickTransform
                                    onPicked: (v) => card.pickTransform = v
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: 30 * root.s

                            Rectangle {
                                id: applyBtn
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !card.pending && root.pendingOut.length === 0
                                width: applyLabel.implicitWidth + 28 * root.s
                                height: 28 * root.s
                                radius: 9 * root.s
                                color: !card.dirty ? Qt.alpha(Colors.primary, 0.10)
                                    : (applyArea.containsMouse ? Qt.alpha(Colors.primary, 0.34) : Qt.alpha(Colors.primary, 0.20))
                                border.width: 1
                                border.color: Qt.alpha(Colors.primary, !card.dirty ? 0.22 : (applyArea.containsMouse ? 0.6 : 0.4))
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                                Text {
                                    id: applyLabel
                                    anchors.centerIn: parent
                                    text: "Apply"
                                    color: card.dirty ? Colors.on_surface : Qt.alpha(Colors.on_surface_variant, 0.65)
                                    font.family: Appearance.font.family
                                    font.pixelSize: 10.5 * root.s
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 0.3 * root.s
                                }

                                MouseArea {
                                    id: applyArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: card.dirty ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (card.dirty) root.apply()
                                }
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: card.pending
                                spacing: 9 * root.s

                                Rectangle {
                                    id: keepBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: keepLabel.implicitWidth + 28 * root.s
                                    height: 28 * root.s
                                    radius: 9 * root.s
                                    color: keepArea.containsMouse ? Colors.tertiary : Qt.alpha(Colors.tertiary, 0.75)
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                                    Text {
                                        id: keepLabel
                                        anchors.centerIn: parent
                                        text: "Keep (" + root.countdown + ")"
                                        color: Colors.on_tertiary
                                        font.family: Appearance.font.family
                                        font.pixelSize: 10.5 * root.s
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.3 * root.s
                                    }

                                    MouseArea {
                                        id: keepArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.keep()
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "reverts automatically if not kept"
                                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                                    font.family: Appearance.font.family
                                    font.pixelSize: 9.5 * root.s
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.note.length > 0
                    text: root.note
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 10 * root.s
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                }
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
