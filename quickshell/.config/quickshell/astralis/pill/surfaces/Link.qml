pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import ".."
import "../../colors"
import "../../services"
import "../../services" as Services // Notifications singleton — the sibling
                                    // surface type shadows the bare name
import "../../config"
import "../settings" as SettingsUi

/**
 * astralis — 繋 LINK surface (Ricelin Link.qml layout): connectivity rows
 * (Network — wired primary — then Bluetooth, each with a toggle and a chevron
 * drill-in) over the 報 INBOX glance — the newest coalesced notification
 * entries from Services.Notifications, tap to activate — with its 静 SILENCE
 * empty state. The WLAN and Bluetooth drill-ins cross-fade in place and keep
 * the live Networking / Bluetooth lists (tap a network to connect, a paired
 * device to connect/disconnect). Security and known-profile ground truth come
 * from nmcli (Ricelin LinkWifi.qml); tapping a secured unknown network expands
 * an inline password row that connects through `nmcli --ask dev wifi connect`.
 * All adapter reads are guarded so missing hardware degrades to a hint.
 *
 * A cog on each saved network / paired device drills one level deeper into
 * that item's own settings page ("wifiItem" / "btItem"): connect, forget,
 * auto-connect, metered, saved password and live addressing for a network
 * (nmcli, via scripts/wifi-profile); rename, trust, block, wake and details
 * for a device (the writable Quickshell BluetoothDevice properties).
 */
PillSurface {
    id: root

    mTop: 13
    mLeft: 16
    mRight: 16
    mBottom: 13

    property string subview: "main"

    ameForm: "dock"
    amePoint: Qt.point(width / 2, height - 8 * s)
    /**
     * Strip the docked bead owns at the bottom. The main view's desiredH
     * already reserves it; the drill-in lists and item pages run to the
     * bottom edge, so they stop this far above it — otherwise the bead sat
     * on top of the last row (and its hover highlight).
     */
    readonly property real beadClear: 18 * s
    // Main view hugs its rows (+ the 静 block when empty, + the bead's dock);
    // the Wi-Fi / Bluetooth drill-ins keep the full fixed height for lists.
    desiredH: subview === "main"
        ? mainCol.implicitHeight + (notifCount === 0 ? 92 * s : 4 * s) + 16 * s
        : 0

    /**
     * Pops one navigation level: drill-in back to main returns true, main
     * returns false so the caller closes the surface instead.
     */
    function back() {
        if (subview === "wifiItem" || subview === "btItem") {
            subview = subview === "wifiItem" ? "wifi" : "bt";
            return true;
        }
        if (subview !== "main") {
            subview = "main";
            return true;
        }
        return false;
    }

    // ── network state ───────────────────────────────────────────────────────
    readonly property var netDevices: (typeof Networking !== "undefined" && Networking && Networking.devices)
        ? Networking.devices.values : []
    readonly property var eth: {
        for (var i = 0; i < netDevices.length; i++)
            if (netDevices[i] && netDevices[i].type === DeviceType.Wired && netDevices[i].connected)
                return netDevices[i];
        return null;
    }
    readonly property var wifiDev: {
        for (var i = 0; i < netDevices.length; i++)
            if (netDevices[i] && netDevices[i].type === DeviceType.Wifi)
                return netDevices[i];
        return null;
    }
    readonly property bool wired: eth !== null

    readonly property real ethSpeed: (eth && eth.linkSpeed) ? eth.linkSpeed : 0
    readonly property string ethSpeedText: ethSpeed > 0
        ? (ethSpeed >= 1000 ? (ethSpeed / 1000).toFixed(ethSpeed % 1000 === 0 ? 0 : 1) + " Gb/s" : ethSpeed + " Mb/s")
        : ""

    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking)
        ? Networking.wifiEnabled : false
    readonly property var nets: {
        if (!wifiDev || !wifiDev.networks)
            return [];
        var out = [];
        var all = wifiDev.networks.values;
        for (var i = 0; i < all.length; i++)
            if (all[i] && all[i].name && all[i].name.length)
                out.push(all[i]);
        out.sort((a, b) => (b.connected === true) - (a.connected === true)
            || ((b.signalStrength || 0) - (a.signalStrength || 0)));
        return out;
    }
    /** 0–100 regardless of whether the backend reports a 0–1 fraction. */
    function pct(net) {
        var v = (net && net.signalStrength) || 0;
        return v <= 1 ? v * 100 : v;
    }

    readonly property var wifiActive: {
        for (var i = 0; i < nets.length; i++)
            if (nets[i].connected === true)
                return nets[i];
        return null;
    }

    property string ethIp: ""

    readonly property string netzSubText: wired
        ? ("Ethernet"
            + (ethSpeedText.length ? " · " + ethSpeedText : "")
            + (ethIp.length ? " · " + ethIp : ""))
        : (wifiActive ? (wifiActive.name || "") : (wifiOn ? "Not connected" : "Off"))

    readonly property string wifiStatusText: !wifiOn ? "Off"
        : (wifiActive ? (wifiActive.name || "Connected") : "Not connected")

    // Scan only while the surface is open and the radio is up.
    Binding {
        target: root.wifiDev
        property: "scannerEnabled"
        value: root.open && root.wifiOn
        when: root.wifiDev !== null
    }

    Process {
        id: ipProc
        command: ["sh", "-c", "ip -4 -o addr show scope global up | awk '{for(i=1;i<=NF;i++) if($i==\"inet\"){print $(i+1); exit}}' | cut -d/ -f1"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.ethIp = this.text.trim() }
    }

    Timer {
        interval: 15000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: ipProc.running = true
    }

    // ── wifi security / saved-profile ground truth (Ricelin LinkWifi.qml) ──
    property var securityMap: ({})      // ssid → SECURITY column ("" / "--" = open)
    property var knownProfiles: ({})    // ssid → true when a saved profile exists
    property string expandedSsid: ""    // ssid whose inline password row is open
    property bool connecting: false
    property bool connectFailed: false

    /**
     * Draft of the password being typed for `expandedSsid`. Lives on the root
     * so the field can restore itself if the keyed list model swaps the
     * delegate's network object under it on a rescan.
     */
    property string pwDraft: ""
    property string pendingPw: ""
    property string attemptSsid: ""
    property bool attemptWasKnown: false

    function isSecured(ssid) {
        var sec = securityMap[ssid];
        return sec !== undefined && sec !== "" && sec !== "--";
    }

    function refreshWifiMeta() {
        secProc.running = true;
        profProc.running = true;
    }

    /**
     * Splits one `nmcli -t` line at its last unescaped colon and unescapes the
     * leading field. Returns null for lines without a field separator.
     */
    function splitTerse(line) {
        for (var k = line.length - 1; k >= 0; k--) {
            if (line[k] === ":" && (k === 0 || line[k - 1] !== "\\"))
                return { head: line.slice(0, k).replace(/\\:/g, ":"), tail: line.slice(k + 1) };
        }
        return null;
    }

    /**
     * Click dispatch for a network row (Ricelin LinkWifi.activateNetwork with
     * the confirm row elided): tapping the expanded row again collapses it, a
     * saved or open network connects through its stored profile at once, and
     * an unknown secured network expands the inline password row instead of
     * silently failing.
     */
    function activateNetwork(net) {
        if (!net || net.connected)
            return;
        var ssid = net.name || "";
        if (expandedSsid === ssid && ssid.length) {
            expandedSsid = "";
            return;
        }
        if (knownProfiles[ssid] === true || !isSecured(ssid)) {
            expandedSsid = "";
            if (typeof net.connect === "function")
                net.connect();
            refreshWifiMeta();
            return;
        }
        connectFailed = false;
        pwDraft = "";
        expandedSsid = ssid;
    }

    /**
     * Connects via `nmcli --ask`, feeding the password through stdin so the
     * secret never appears in the process command line (`/proc/<pid>/cmdline`
     * is world-readable for the whole connection attempt). The SSID rides as
     * its own argv element so an odd character can neither break nor inject
     * the command.
     */
    function connectWithPassword(ssid, pw) {
        if (connProc.running || !pw.length)
            return;
        connecting = true;
        connectFailed = false;
        attemptSsid = ssid;
        attemptWasKnown = knownProfiles[ssid] === true;
        pendingPw = pw;
        // `timeout` bounds a connect that stalls (e.g. nmcli re-prompts for a
        // second secret we can't answer): a non-zero/124 exit falls through the
        // onExited failure branch, clearing `connecting` and surfacing the error
        // instead of spinning forever. The SSID stays its own argv element.
        connProc.command = ["timeout", "45", "nmcli", "--ask", "dev", "wifi", "connect", ssid];
        connProc.running = true;
    }

    Process {
        id: secProc
        command: ["nmcli", "-t", "-f", "SSID,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i].length)
                        continue;
                    var parts = root.splitTerse(lines[i]);
                    if (parts && parts.head.length)
                        map[parts.head] = parts.tail;
                }
                root.securityMap = map;
            }
        }
    }

    Process {
        id: profProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var set = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = root.splitTerse(lines[i]);
                    if (parts && parts.head.length && parts.tail === "802-11-wireless")
                        set[parts.head] = true;
                }
                root.knownProfiles = set;
            }
        }
    }

    Process {
        id: connProc
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onStarted: {
            write(root.pendingPw + "\n");
            root.pendingPw = "";
        }
        onExited: function(exitCode) {
            root.connecting = false;
            if (exitCode === 0) {
                root.expandedSsid = "";
                root.pwDraft = "";
                root.connectFailed = false;
                root.refreshWifiMeta();
            } else {
                root.connectFailed = true;
                if (!root.attemptWasKnown && root.attemptSsid.length) {
                    cleanupProc.command = ["nmcli", "connection", "delete", "id", root.attemptSsid];
                    cleanupProc.running = true;
                }
            }
        }
    }

    /**
     * A failed `nmcli dev wifi connect` still leaves a connection profile
     * named after the SSID behind; without deleting it the network would be
     * treated as known on the next click and silently fail forever.
     */
    Process {
        id: cleanupProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: root.refreshWifiMeta()
    }

    // Debounced security re-read: the scanner mutates `nets` continuously
    // while the drill-in is open.
    onNetsChanged: if (open) secRefresh.restart()

    Timer {
        id: secRefresh
        interval: 1200
        onTriggered: if (root.open) secProc.running = true
    }

    /**
     * Keys the network list by SSID so a rescan diffs into the existing rows
     * rather than tearing every delegate down and rebuilding it; the inline
     * password row (and its focused field) stays open under the network the
     * user tapped.
     */
    ScriptModel {
        id: netModel
        objectProp: "name"
        values: root.wifiOn ? root.nets : []
    }

    // ── bluetooth state ─────────────────────────────────────────────────────
    readonly property var btAdapter: (typeof Bluetooth !== "undefined" && Bluetooth)
        ? Bluetooth.defaultAdapter : null
    readonly property bool btOn: btAdapter !== null && btAdapter.enabled === true
    /**
     * Ricelin LinkBt.devicesSorted: BlueZ hands the cache out in arbitrary
     * order; sort connected first, then paired, then named discoveries,
     * nameless MACs last so a discovery scan doesn't churn the useful rows
     * around. Unnamed devices stay listed — they are what a scan yields
     * before the name request completes.
     */
    readonly property var btDevices: {
        if (!btAdapter || !btOn)
            return [];
        var all = (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices)
            ? Bluetooth.devices.values : [];
        var out = [];
        for (var i = 0; i < all.length; i++)
            if (all[i])
                out.push(all[i]);
        out.sort(function(a, b) {
            function rank(d) {
                if (d.connected) return 0;
                if (d.paired) return 1;
                return (d.name && d.name.length) ? 2 : 3;
            }
            return rank(a) - rank(b)
                || String(a.name || "").localeCompare(String(b.name || ""));
        });
        return out;
    }
    readonly property var btConnected: {
        var out = [];
        for (var i = 0; i < btDevices.length; i++)
            if (btDevices[i].connected === true)
                out.push(btDevices[i]);
        return out;
    }
    readonly property var btPrimary: btConnected.length > 0 ? btConnected[0] : null
    readonly property string btSubText: !btOn ? "Off"
        : (btPrimary
            ? ((btPrimary.deviceName || btPrimary.name || "Unknown")
                + (btConnected.length > 1 ? " +" + (btConnected.length - 1) : ""))
            : "Not connected")

    // ── bluetooth drill-in state (Ricelin LinkBt.qml) ───────────────────────
    readonly property bool btDiscovering: btAdapter !== null && btAdapter.discovering === true
    property string btPairingAddress: ""   // device mid pair-trust-connect
    property string btFailedAddress: ""    // transient "Pairing failed" row
    property string btExpandedAddress: ""  // known device with its confirm row open

    /**
     * Meta line under a device name (Ricelin LinkBt.metaFor plus the trusted
     * flag): connected/paired · trusted · live state.
     */
    function btMetaFor(d) {
        if (!d)
            return "";
        var parts = [];
        if (d.connected) parts.push("connected");
        else if (d.paired) parts.push("paired");
        if (d.trusted) parts.push("trusted");
        if (d.state !== undefined && typeof BluetoothDeviceState !== "undefined") {
            var st = BluetoothDeviceState.toString(d.state);
            if (st && st.length > 0 && parts.indexOf(st.toLowerCase()) === -1)
                parts.push(st.toLowerCase());
        }
        return parts.join(" · ");
    }

    /**
     * Battery percent text, "" when the device exposes none. Quickshell
     * reports battery as 0..1; Ricelin's guard also tolerates a 0..100 scale.
     */
    function btBatteryText(d) {
        if (!d || d.batteryAvailable !== true)
            return "";
        var b = d.battery;
        if (b === undefined || b === null || b <= 0)
            return "";
        if (b <= 1)
            b = b * 100;
        return Math.round(b) + "%";
    }

    /**
     * Click dispatch for a device row (Ricelin LinkBt.activateDevice): a
     * connected or paired device toggles its inline confirm row rather than
     * acting at once; an unpaired device starts the pair flow.
     */
    function btActivate(d) {
        if (!d)
            return;
        if (d.connected || d.paired) {
            var addr = d.address || "";
            btExpandedAddress = (addr.length && btExpandedAddress === addr) ? "" : addr;
            return;
        }
        btPair(d);
    }

    function btConnect(d) {
        btExpandedAddress = "";
        if (d && typeof d.connect === "function")
            d.connect();
    }

    function btDisconnect(d) {
        btExpandedAddress = "";
        if (d && typeof d.disconnect === "function")
            d.disconnect();
    }

    /** Unpair via the Quickshell device object; the row falls back to Pair. */
    function btForget(d) {
        btExpandedAddress = "";
        if (d && typeof d.forget === "function")
            d.forget();
    }

    /**
     * Pairing flow (Ricelin LinkBt.pairDevice): bluetoothctl pair-trust-
     * connect in one sequential shot. Quickshell's native device.pair()
     * exists but stops at the bond — it neither trusts the device (BlueZ
     * would then refuse its reconnects) nor connects it, so the bluetoothctl
     * chain stays. The address rides as its own argv element and timeouts
     * bound each interactive step.
     */
    function btPair(d) {
        if (!d || !d.address || btPairProc.running)
            return;
        btPairingAddress = d.address;
        btFailedAddress = "";
        btPairProc.command = ["sh", "-c",
            'timeout 30 bluetoothctl pair "$1" && bluetoothctl trust "$1" && timeout 30 bluetoothctl connect "$1"',
            "sh", d.address];
        btPairProc.running = true;
    }

    /** Scan toggle (Ricelin LinkBt): 25s auto-stop so discovery can't run away. */
    function btToggleScan() {
        if (!btAdapter)
            return;
        // BlueZ applies `discovering` asynchronously, so reading it straight
        // back yields the stale prior value — drive the 25s auto-stop timer off
        // the intended state instead.
        var want = !btAdapter.discovering;
        btAdapter.discovering = want;
        if (want)
            btScanStop.restart();
        else
            btScanStop.stop();
    }

    /** Leaving the drill-in (or the surface) stops discovery and collapses rows. */
    function btLeave() {
        btScanStop.stop();
        btExpandedAddress = "";
        if (btAdapter && btAdapter.discovering)
            btAdapter.discovering = false;
    }

    onSubviewChanged: {
        if (subview !== "bt")
            btLeave();
        itemForgetArmed = false;
        // The saved password only lives in memory while its page is up.
        if (subview !== "wifiItem") {
            itemPsk = "";
            itemPskShown = false;
        }
    }

    Timer {
        id: btScanStop
        interval: 25000
        onTriggered: if (root.btAdapter) root.btAdapter.discovering = false
    }

    Timer {
        id: btFailClear
        interval: 4000
        onTriggered: root.btFailedAddress = ""
    }

    Process {
        id: btPairProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            var addr = root.btPairingAddress;
            root.btPairingAddress = "";
            if (exitCode !== 0) {
                root.btFailedAddress = addr;
                btFailClear.restart();
            }
        }
    }

    /**
     * Keys the device list by address so discovery churn diffs into existing
     * rows instead of rebuilding every delegate (same trick as the wifi
     * list's SSID keying); the open confirm row survives a rescan.
     */
    ScriptModel {
        id: btModel
        objectProp: "address"
        values: root.btDevices
    }

    // ── per-item settings (one saved network / one paired device) ───────────
    /**
     * Both item pages key on the SSID / MAC rather than holding the Quickshell
     * object: a rescan can swap the object out from under the page, so the
     * live object is re-resolved from the current list instead.
     */
    property string itemSsid: ""
    readonly property var itemNet: {
        if (!itemSsid.length)
            return null;
        for (var i = 0; i < nets.length; i++)
            if (nets[i].name === itemSsid)
                return nets[i];
        return null;
    }
    readonly property bool itemNetConnected: itemNet !== null && itemNet.connected === true
    /** Saved profiles whose SSID matches, the live one first: [{ uuid, id, autoconnect, metered, active }]. */
    property var itemProfiles: []
    /** Live addressing while this network is the link: { ip4, gw, dns, ip6, mac }. */
    property var itemIp: ({})
    /** The in-use (else strongest) access point: { signal, bssid, chan, freq, rate, security }. */
    property var itemAp: ({})
    property bool itemLoaded: false
    property bool itemQueued: false
    property string itemPsk: ""
    property bool itemPskShown: false
    property bool itemPskMissing: false
    property bool itemPskCopyAfter: false
    property bool itemForgetArmed: false
    /** Label of the detail row that just copied its value (flashes "Copied"). */
    property string itemCopied: ""
    /** nmcli writes waiting their turn: [[key, value], …]. */
    property var itemModQueue: []

    readonly property var itemPrimary: itemProfiles.length > 0 ? itemProfiles[0] : null
    readonly property bool itemAutoconnect: itemPrimary !== null && itemPrimary.autoconnect === true
    readonly property bool itemMetered: itemPrimary !== null && itemPrimary.metered === "yes"
    readonly property bool itemSecured: (itemAp.security || "").length > 0 || isSecured(itemSsid)
    readonly property string itemStatusText: itemNetConnected ? "Connected"
        : (itemNet && itemNet.stateChanging === true) ? "Connecting…"
        : (itemNet ? "Saved · in range" : "Saved · out of range")

    function itemUuids() {
        var out = [];
        for (var i = 0; i < itemProfiles.length; i++)
            out.push(itemProfiles[i].uuid);
        return out;
    }

    function openWifiItem(ssid) {
        if (!ssid || !ssid.length)
            return;
        itemSsid = ssid;
        itemProfiles = [];
        itemIp = ({});
        itemAp = ({});
        itemLoaded = false;
        itemPsk = "";
        itemPskShown = false;
        itemPskMissing = false;
        expandedSsid = "";
        subview = "wifiItem";
        refreshWifiItem();
    }

    function refreshWifiItem() {
        if (!itemSsid.length)
            return;
        if (wifiItemProc.running) {
            itemQueued = true;
            return;
        }
        wifiItemProc.command = ["sh", Quickshell.shellDir + "/scripts/wifi-profile", itemSsid];
        wifiItemProc.running = true;
    }

    /** Splits a terse nmcli row on every unescaped colon, unescaping each field. */
    function splitTerseAll(line) {
        var out = [];
        var cur = "";
        for (var k = 0; k < line.length; k++) {
            var c = line[k];
            if (c === "\\" && k + 1 < line.length) {
                cur += line[++k];
            } else if (c === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        out.push(cur);
        return out;
    }

    /** Folds scripts/wifi-profile output (see its header) into the item state. */
    function parseWifiItem(text) {
        var profs = {};
        var order = [];
        var active = "";
        var ip = {};
        var best = null;
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var f = lines[i].split("\t");
            var rest = f.slice(f[0] === "P" ? 2 : 1).join("\t");
            var c = rest.indexOf(":");
            var key = c < 0 ? "" : rest.slice(0, c).replace(/\[\d+\]$/, "");
            var val = c < 0 ? "" : rest.slice(c + 1).trim();
            if (f[0] === "P" && f.length >= 3) {
                var u = f[1];
                if (!profs[u]) {
                    profs[u] = { uuid: u, id: "", autoconnect: true, metered: "unknown", active: false };
                    order.push(u);
                }
                if (key === "connection.id")
                    profs[u].id = val;
                else if (key === "connection.autoconnect")
                    profs[u].autoconnect = val === "yes";
                else if (key === "connection.metered")
                    profs[u].metered = val;
            } else if (f[0] === "X" && f.length >= 2) {
                active = f[1];
            } else if (f[0] === "I" && val.length && val !== "--") {
                if (key === "IP4.ADDRESS" && !ip.ip4)
                    ip.ip4 = val.split("/")[0];
                else if (key === "IP4.GATEWAY")
                    ip.gw = val;
                else if (key === "IP4.DNS")
                    ip.dns = ip.dns ? ip.dns + ", " + val : val;
                else if (key === "IP6.ADDRESS" && !ip.ip6 && val.indexOf("fe80") !== 0)
                    ip.ip6 = val.split("/")[0];
                else if (key === "GENERAL.HWADDR")
                    ip.mac = val;
            } else if (f[0] === "A" && f.length >= 2) {
                var a = splitTerseAll(rest);
                if (a.length < 8 || a[7] !== itemSsid)
                    continue;
                var ap = {
                    inUse: a[0] === "*",
                    signal: parseInt(a[1]) || 0,
                    bssid: a[2],
                    chan: a[3],
                    freq: a[4],
                    rate: a[5],
                    security: a[6] === "--" ? "" : a[6]
                };
                if (!best || (ap.inUse && !best.inUse) || (ap.inUse === best.inUse && ap.signal > best.signal))
                    best = ap;
            }
        }
        var list = [];
        for (var j = 0; j < order.length; j++) {
            profs[order[j]].active = order[j] === active;
            list.push(profs[order[j]]);
        }
        list.sort((x, y) => (y.active === true) - (x.active === true));
        itemProfiles = list;
        itemIp = active.length ? ip : ({});
        itemAp = best || ({});
        itemLoaded = true;
    }

    function bandText(freq) {
        var mhz = parseInt(freq) || 0;
        if (mhz <= 0)
            return "";
        return mhz < 3000 ? "2.4 GHz" : (mhz < 5925 ? "5 GHz" : "6 GHz");
    }

    /**
     * Writes one connection setting to EVERY saved profile for the SSID, so a
     * duplicate ("Hmmm 1") can't keep auto-joining behind the switch. The row
     * flips at once; the re-read after nmcli exits settles it.
     */
    function setWifiItemProp(key, value) {
        if (!itemProfiles.length)
            return;
        var list = [];
        for (var i = 0; i < itemProfiles.length; i++) {
            var p = Object.assign({}, itemProfiles[i]);
            if (key === "connection.autoconnect")
                p.autoconnect = value === "yes";
            else if (key === "connection.metered")
                p.metered = value;
            list.push(p);
        }
        itemProfiles = list;
        itemModQueue = itemModQueue.concat([[key, value]]);
        runWifiMod();
    }

    function runWifiMod() {
        if (wifiModProc.running || !itemModQueue.length)
            return;
        var next = itemModQueue[0];
        itemModQueue = itemModQueue.slice(1);
        wifiModProc.command = ["sh", "-c",
            'k="$1"; v="$2"; shift 2; for u; do nmcli connection modify uuid "$u" "$k" "$v" || exit 1; done',
            "sh", next[0], next[1]].concat(itemUuids());
        wifiModProc.running = true;
    }

    /** Two taps: the first arms the button for 3 s, the second deletes every profile. */
    function forgetWifiItem() {
        if (!itemForgetArmed) {
            itemForgetArmed = true;
            forgetDisarm.restart();
            return;
        }
        itemForgetArmed = false;
        var uuids = itemUuids();
        if (uuids.length) {
            var cmd = ["nmcli", "connection", "delete"];
            for (var i = 0; i < uuids.length; i++)
                cmd.push("uuid", uuids[i]);
            wifiForgetProc.command = cmd;
            wifiForgetProc.running = true;
        } else if (itemNet && typeof itemNet.forget === "function") {
            itemNet.forget();
        }
        subview = "wifi";
    }

    /** Reads the saved secret on demand (never on page open). */
    function fetchWifiItemPsk(thenCopy) {
        if (!itemPrimary || pskProc.running)
            return;
        itemPskCopyAfter = thenCopy === true;
        pskProc.command = ["nmcli", "-s", "-t", "-f", "802-11-wireless-security.psk",
            "connection", "show", "uuid", itemPrimary.uuid];
        pskProc.running = true;
    }

    function toggleWifiItemPsk() {
        if (itemPskShown)
            itemPskShown = false;
        else if (itemPsk.length)
            itemPskShown = true;
        else
            fetchWifiItemPsk(false);
    }

    function copyWifiItemPsk() {
        if (itemPsk.length)
            copyText("Password", itemPsk, true);
        else
            fetchWifiItemPsk(true);
    }

    /**
     * Clipboard write. The text rides in the environment, not argv: argv is
     * world-readable in /proc while environ is owner-only, and wl-copy keeps
     * serving (so keeps living) after the copy. Secrets get `--sensitive` so
     * the cliphist watcher skips them.
     */
    function copyText(label, text, sensitive) {
        if (!text || !text.length || copyProc.running)
            return;
        copyProc.environment = ({ ASTRALIS_CLIP: text });
        copyProc.command = ["sh", "-c",
            sensitive ? 'printf "%s" "$ASTRALIS_CLIP" | wl-copy --sensitive'
                      : 'printf "%s" "$ASTRALIS_CLIP" | wl-copy'];
        copyProc.running = true;
        itemCopied = label;
        copiedClear.restart();
    }

    // Association / DHCP land after the switch flips: re-read once settled.
    onItemNetConnectedChanged: if (subview === "wifiItem") itemSettle.restart()

    Timer {
        id: itemSettle
        interval: 1500
        onTriggered: root.refreshWifiItem()
    }

    Timer {
        id: forgetDisarm
        interval: 3000
        onTriggered: root.itemForgetArmed = false
    }

    Timer {
        id: copiedClear
        interval: 1400
        onTriggered: root.itemCopied = ""
    }

    Process {
        id: wifiItemProc
        stdout: StdioCollector { onStreamFinished: root.parseWifiItem(this.text) }
        stderr: StdioCollector {}
        onExited: {
            if (root.itemQueued) {
                root.itemQueued = false;
                root.refreshWifiItem();
            }
        }
    }

    Process {
        id: wifiModProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: {
            if (root.itemModQueue.length)
                root.runWifiMod();
            else
                root.refreshWifiItem();
        }
    }

    Process {
        id: wifiForgetProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: root.refreshWifiMeta()
    }

    Process {
        id: pskProc
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.replace(/\n$/, "");
                var c = t.indexOf(":");
                var pw = c < 0 ? "" : t.slice(c + 1);
                root.itemPsk = pw;
                root.itemPskMissing = pw.length === 0;
                if (!pw.length)
                    return;
                if (root.itemPskCopyAfter)
                    root.copyText("Password", pw, true);
                else
                    root.itemPskShown = true;
            }
        }
        stderr: StdioCollector {}
    }

    Process {
        id: copyProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    // Bluetooth device page.
    property string itemBtAddress: ""
    readonly property var itemDev: {
        if (!itemBtAddress.length)
            return null;
        var all = (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices)
            ? Bluetooth.devices.values : [];
        for (var i = 0; i < all.length; i++)
            if (all[i] && all[i].address === itemBtAddress)
                return all[i];
        return null;
    }
    readonly property string itemDevName: itemDev
        ? (itemDev.name || itemDev.deviceName || itemBtAddress) : itemBtAddress
    readonly property bool itemDevInput: itemDev !== null && String(itemDev.icon || "").indexOf("input") === 0
    readonly property string itemDevStatus: {
        if (!itemDev)
            return "Unavailable";
        if (!btOn)
            return "Bluetooth is off";
        var parts = [itemDev.connected ? "Connected" : (itemDev.blocked ? "Blocked" : "Paired")];
        var b = btBatteryText(itemDev);
        if (itemDev.connected && b.length)
            parts.push(b);
        return parts.join(" · ");
    }

    function openBtItem(d) {
        if (!d || !d.address)
            return;
        itemBtAddress = d.address;
        btExpandedAddress = "";
        btNameField.text = d.name || "";
        subview = "btItem";
    }

    /** BlueZ's icon hint as a word. */
    function btKindText(icon) {
        var map = {
            "audio-headphones": "Headphones",
            "audio-headset": "Headset",
            "audio-card": "Speaker",
            "input-keyboard": "Keyboard",
            "input-mouse": "Mouse",
            "input-tablet": "Tablet",
            "input-gaming": "Game controller",
            "phone": "Phone",
            "computer": "Computer",
            "camera-video": "Camera",
            "camera-photo": "Camera",
            "printer": "Printer",
            "modem": "Modem",
            "network-wireless": "Network"
        };
        return map[icon] || (icon && icon.length ? "Device" : "");
    }

    /** Writes the BlueZ Alias; an empty name hands back the device's own. */
    function btRename(d, text) {
        if (!d)
            return;
        d.name = String(text || "").trim();
    }

    function forgetBtItem() {
        if (!itemForgetArmed) {
            itemForgetArmed = true;
            forgetDisarm.restart();
            return;
        }
        itemForgetArmed = false;
        var d = itemDev;
        subview = "bt";
        btForget(d);
    }

    onOpenChanged: {
        if (open) {
            subview = "main";
            refreshWifiMeta();
        } else {
            expandedSsid = "";
            connectFailed = false;
            connecting = false;   // clear the spinner so a reopen isn't stale
            pwDraft = "";
            btLeave();
            itemPsk = "";
            itemPskShown = false;
        }
    }

    // ── 報 INBOX glance state ───────────────────────────────────────────────
    readonly property int notifCount: Services.Notifications.count
    readonly property int notifUnread: Services.Notifications.unread

    /** Total coalesced entries across all app groups (drives the +N MORE hint). */
    readonly property int inboxTotal: {
        var t = 0;
        var gs = Services.Notifications.groups;
        for (var i = 0; i < gs.length; i++)
            t += gs[i].criticals.length + gs[i].entries.length;
        return t;
    }

    /**
     * Newest coalesced entries flattened across the app groups (groups are
     * already newest-first, criticals pinned per group), capped at 3 rows so
     * the glance fits the surface's fixed height. Each row carries its app
     * name since the glance flattens the grouping.
     */
    readonly property var inboxEntries: {
        var out = [];
        var gs = Services.Notifications.groups;
        for (var i = 0; i < gs.length && out.length < 3; i++) {
            var g = gs[i];
            var rows = g.criticals.concat(g.entries);
            for (var j = 0; j < rows.length && out.length < 3; j++)
                out.push({ app: g.app, entry: rows[j], critical: j < g.criticals.length });
        }
        return out;
    }

    // ── airplane mode ───────────────────────────────────────────────────────
    /**
     * Master radio kill: Flags.airplane persists the state and its edge fires
     * the rfkill sweep (services/Flags.qml), so the switch here is just the
     * flag. While on, the Network and Bluetooth rows dim — their hardware is
     * blocked — and an open drill-in pops back to the main view.
     */
    readonly property bool airplaneOn: Flags.airplane === true
    onAirplaneOnChanged: if (airplaneOn && subview !== "main") subview = "main"

    // ── shared bits ─────────────────────────────────────────────────────────
    // The airplane mark used to be an inline `component PlaneGlyph` here: a
    // second hand-written 24x24 stroked Shape, in a file that already draws
    // every other icon with GlyphIcon, because the baked table had no plane.
    // The path now lives in pill/lib/glyphs.js as "plane", where the rest of
    // the shell's icon vocabulary lives, and this surface just names it.

    // The toggle used to be declared here, as an inline `component LinkToggle`.
    // `import ".."` already brings in pill/LinkToggle.qml — the shell's toggle,
    // a thin adapter over `pill/m3/M3Switch.qml` — and an inline component of
    // the same name SHADOWS the imported type for the whole file. So every
    // switch on this surface was the old hand-rolled 28x16 pill with a 10dp
    // knob while every settings row in the shell was drawing the M3 switch:
    // two different toggles in one program, which is the exact seam this pass
    // exists to close. Deleting the shadow is the whole fix — the call sites
    // below keep the same `on` / `accessibleName` / `toggled()` surface and now
    // get the M3 track, thumb-growth spring, state layer, focus ring and 40dp
    // hit target for free. `s: root.s` is the one thing they must pass.

    component HintText: Text {
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 10.5 * root.s
    }

    /** Drill-in header: back chevron, uppercase title, dim status, right slot. */
    component SubHeader: Item {
        id: subHead

        property string title: ""
        property string status: ""
        property bool statusLit: false
        property string backHint: "Return to the connectivity list"
        default property alias rightContent: subRight.data

        width: parent ? parent.width : 0
        height: 34 * root.s

        Item {
            id: backBtn
            anchors.left: parent.left
            anchors.leftMargin: -4 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 30 * root.s
            height: 30 * root.s

            // Named for where it goes, not what it looks like — "chevron"
            // means nothing read aloud, and the title beside it is the only
            // other clue to depth a screen reader gets.
            Accessible.role: Accessible.Button
            Accessible.name: "Back"
            Accessible.description: subHead.backHint
            Accessible.focusable: true
            Accessible.onPressAction: root.back()

            scale: backArea.pressed ? 0.92 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: backArea.containsMouse ? Colors.surface_container_highest : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            GlyphIcon {
                anchors.centerIn: parent
                width: 16 * root.s
                height: 16 * root.s
                name: "chevron-left"
                color: backArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                stroke: 1.9
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.back()
            }
        }

        // Title over live status — the drill-in names where you are in the
        // same voice as the rows that led here, not as a tracked-out caption.
        Column {
            anchors.left: backBtn.right
            anchors.leftMargin: 6 * root.s
            anchors.right: subRight.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * root.s

            Text {
                width: parent.width
                text: subHead.title
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Row {
                visible: subHead.status.length > 0
                spacing: 5 * root.s

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5 * root.s
                    height: width
                    radius: width / 2
                    color: subHead.statusLit ? Colors.primary : Qt.alpha(Colors.on_surface_variant, 0.4)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: subHead.status
                    color: subHead.statusLit ? Colors.primary : Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 10 * root.s
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
        }

        Row {
            id: subRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9 * root.s
        }
    }

    /** Connectivity row: glyph, name over live subtext, toggle + chevron. */
    component LinkRow: Rectangle {
        id: lrow

        property string glyph: ""
        property bool glyphLit: false
        property string label: ""
        property string subText: ""
        property bool subLit: false
        property bool showToggle: true
        property bool toggleOn: false
        /** The switch controls a radio, which is rarely the row's own name. */
        property string toggleName: ""
        /** ≥ 0 swaps the glyph for live Wi-Fi bars at this strength. */
        property real strength: -1
        signal toggled()
        signal drill()

        width: parent ? parent.width : 0
        height: 44 * root.s
        radius: 10 * root.s
        color: lrowHover.hovered ? Colors.surface_container_highest : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        // Shallow dip: these rows span the whole surface, so anything deeper
        // reads as the panel itself flexing rather than the row taking a press.
        scale: lrowArea.pressed ? 0.98 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        // The subtext is the live link state, and it is the reason to open the
        // row at all — it belongs in the description, not lost as decoration.
        Accessible.role: Accessible.Button
        Accessible.name: lrow.label
        Accessible.description: lrow.subText
        Accessible.focusable: true
        Accessible.onPressAction: lrow.drill()

        HoverHandler {
            id: lrowHover
        }

        MouseArea {
            id: lrowArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: lrow.drill()
        }

        GlyphIcon {
            id: lrowGlyph
            anchors.left: parent.left
            anchors.leftMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 17 * root.s
            height: 17 * root.s
            name: lrow.glyph
            visible: lrow.strength < 0
            color: lrow.glyphLit ? Colors.primary : Colors.on_surface_variant
            stroke: 1.7
            // The lit tint tracks live link state (associate/drop), so it
            // blooms into the accent instead of flicking as the radio settles.
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        WifiSignal {
            anchors.fill: lrowGlyph
            visible: lrow.strength >= 0
            strength: lrow.strength
            color: lrow.glyphLit ? Colors.primary : Colors.on_surface_variant
        }

        Column {
            anchors.left: lrowGlyph.right
            anchors.leftMargin: 11 * root.s
            anchors.right: lrowRight.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s

            Text {
                width: parent.width
                text: lrow.label
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 12.5 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: lrow.subText
                color: lrow.subLit ? Colors.primary : Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 10 * root.s
                font.weight: lrow.subLit ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        Row {
            id: lrowRight
            anchors.right: parent.right
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9 * root.s

            LinkToggle {
                s: root.s
                visible: lrow.showToggle
                anchors.verticalCenter: parent.verticalCenter
                on: lrow.toggleOn
                accessibleName: lrow.toggleName.length > 0 ? lrow.toggleName : lrow.label
                onToggled: lrow.toggled()
            }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * root.s
                height: 14 * root.s
                name: "chevron-right"
                color: Colors.on_surface_variant
                stroke: 1.8
            }
        }
    }

    /** The per-row way into an item's settings page. */
    component ItemCog: Item {
        id: cog

        property string itemName: ""
        signal clicked()

        width: 24 * root.s
        height: 24 * root.s

        Accessible.role: Accessible.Button
        Accessible.name: "Settings"
        Accessible.description: cog.itemName
        Accessible.focusable: true
        Accessible.onPressAction: cog.clicked()

        scale: cogArea.pressed ? 0.9 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: cogArea.containsMouse ? Qt.alpha(Colors.on_surface, 0.08) : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        GlyphIcon {
            anchors.centerIn: parent
            width: 13 * root.s
            height: 13 * root.s
            name: "cog"
            stroke: 1.7
            color: cogArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        MouseArea {
            id: cogArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cog.clicked()
        }
    }

    /** One switch on an item page: name over a dim caption, the whole row toggles. */
    component ItemSwitch: Rectangle {
        id: isw

        property string label: ""
        property string sub: ""
        property bool on: false
        signal toggled()

        width: parent ? parent.width : 0
        height: (sub.length > 0 ? 42 : 34) * root.s
        radius: 9 * root.s
        color: iswHover.hovered ? Colors.surface_container_highest : "transparent"
        opacity: enabled ? 1 : 0.4
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        Accessible.role: Accessible.CheckBox
        Accessible.name: isw.label
        Accessible.description: isw.sub
        Accessible.checkable: true
        Accessible.checked: isw.on
        Accessible.focusable: true
        Accessible.onToggleAction: isw.toggled()
        Accessible.onPressAction: isw.toggled()

        HoverHandler {
            id: iswHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: isw.toggled()
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 10 * root.s
            anchors.right: iswToggle.left
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * root.s

            Text {
                width: parent.width
                text: isw.label
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 11.5 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: isw.sub.length > 0
                text: isw.sub
                color: Qt.alpha(Colors.on_surface_variant, 0.85)
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                elide: Text.ElideRight
            }
        }

        LinkToggle {
            id: iswToggle
            s: root.s
            anchors.right: parent.right
            anchors.rightMargin: 6 * root.s
            anchors.verticalCenter: parent.verticalCenter
            on: isw.on
            accessibleName: isw.label
            onToggled: isw.toggled()
        }
    }

    /** Read-only detail: name left, value right; a tap copies the value. */
    component ItemDetail: Rectangle {
        id: idt

        property string label: ""
        property string value: ""
        property bool copyable: true
        readonly property bool justCopied: root.itemCopied === idt.label

        visible: idt.value.length > 0
        width: parent ? parent.width : 0
        height: 28 * root.s
        radius: 8 * root.s
        color: idt.copyable && idtHover.hovered ? Colors.surface_container_highest : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Accessible.role: idt.copyable ? Accessible.Button : Accessible.StaticText
        Accessible.name: idt.label
        Accessible.description: idt.copyable ? idt.value + " — press to copy" : idt.value
        Accessible.focusable: idt.copyable
        Accessible.onPressAction: if (idt.copyable) root.copyText(idt.label, idt.value, false)

        HoverHandler {
            id: idtHover
        }

        MouseArea {
            anchors.fill: parent
            enabled: idt.copyable
            cursorShape: Qt.PointingHandCursor
            onClicked: root.copyText(idt.label, idt.value, false)
        }

        Text {
            id: idtLabel
            anchors.left: parent.left
            anchors.leftMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: idt.label
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
        }

        Text {
            anchors.left: idtLabel.right
            anchors.leftMargin: 12 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: idt.justCopied ? "Copied" : idt.value
            color: idt.justCopied ? Colors.primary : Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
            elide: Text.ElideMiddle
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    /** Pill action on an item page: outlined, `filled` (primary) or `danger` (error). */
    component ItemAction: Rectangle {
        id: iac

        property string label: ""
        property string icon: ""
        property string description: ""
        property bool filled: false
        property bool danger: false
        signal clicked()

        readonly property color fg: iac.danger ? Colors.error
            : (iac.filled ? Colors.on_primary : Colors.on_surface)

        height: 30 * root.s
        width: iacRow.implicitWidth + 26 * root.s
        radius: height / 2
        color: iac.danger ? Qt.alpha(Colors.error, 0.12)
            : (iac.filled ? Colors.primary : "transparent")
        border.width: iac.filled ? 0 : 1
        border.color: iac.danger ? Qt.alpha(Colors.error, 0.45) : Qt.alpha(Colors.outline_variant, 0.6)
        opacity: enabled ? 1 : 0.4
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        scale: iacArea.pressed ? 0.94 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: iac.label
        Accessible.description: iac.description
        Accessible.focusable: true
        Accessible.onPressAction: iac.clicked()

        // M3 state layer: the content colour at 8% hover / 12% press.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: iac.fg
            opacity: iacArea.pressed ? 0.12 : (iacArea.containsMouse ? 0.08 : 0)
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }

        Row {
            id: iacRow
            anchors.centerIn: parent
            spacing: 6 * root.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: iac.icon.length > 0
                width: 13 * root.s
                height: 13 * root.s
                name: iac.icon
                stroke: 1.9
                color: iac.fg
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: iac.label
                color: iac.fg
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: iacArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iac.clicked()
        }
    }

    // ── main view ───────────────────────────────────────────────────────────
    Item {
        id: mainView
        anchors.fill: parent
        opacity: root.subview === "main" ? 1 : 0
        visible: opacity > 0.01
        enabled: root.subview === "main" && root.active
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        Column {
            id: mainCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 4 * root.s

            Item {
                width: parent.width
                height: 24 * root.s

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Flags.showGlyphs
                        text: "繋"
                        color: Colors.on_surface
                        font.family: Appearance.font.jp
                        font.weight: Font.Medium
                        font.pixelSize: 16 * root.s
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "LINK"
                        color: Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 10 * root.s
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.6 * root.s
                    }
                }

                // Airplane-mode master switch (header affordance): plane glyph
                // lights primary and an ON tag appears while every radio is
                // rfkill-blocked; the switch just flips Flags.airplane.
                Row {
                    id: airplaneCtl
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.airplaneOn
                        text: "ON"
                        color: Colors.primary
                        font.family: Appearance.font.family
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4 * root.s
                    }

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14 * root.s
                        height: 14 * root.s
                        name: "plane"
                        color: root.airplaneOn ? Colors.primary : Colors.on_surface_variant
                        stroke: 1.7
                        // rfkill lands a beat after the switch flips, so the
                        // mark blooms into the accent rather than snapping.
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    LinkToggle {
                        s: root.s
                        anchors.verticalCenter: parent.verticalCenter
                        on: root.airplaneOn
                        accessibleName: "Airplane mode"
                        onToggled: Flags.airplane = !Flags.airplane
                    }
                }

                // Unread pulse (Ricelin Link header ember + "N NEW").
                Row {
                    anchors.right: airplaneCtl.left
                    anchors.rightMargin: 18 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s
                    visible: root.notifUnread > 0

                    Rectangle {
                        id: headerEmber
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6 * root.s
                        height: 6 * root.s
                        radius: width / 2
                        color: Colors.primary

                        SequentialAnimation on opacity {
                            running: headerEmber.visible && !Motion.reduceMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.55; duration: Motion.pulse; easing.type: Motion.easeStandard }
                            NumberAnimation { to: 1;    duration: Motion.pulse; easing.type: Motion.easeStandard }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.notifUnread + " NEW"
                        color: Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4 * root.s
                    }
                }
            }

            Item { width: 1; height: 4 * root.s }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.alpha(Colors.on_surface, 0.06)
            }

            Item { width: 1; height: 4 * root.s }

            LinkRow {
                // Airplane blocks the radio: dim and lock the row out.
                enabled: !root.airplaneOn
                opacity: root.airplaneOn ? 0.4 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }
                glyph: root.wired ? "ethernet" : "wifi"
                strength: (!root.wired && root.wifiOn) ? (root.wifiActive ? root.pct(root.wifiActive) : 0) : -1
                glyphLit: root.wired || (root.wifiOn && root.wifiActive !== null)
                label: "Network"
                subText: root.netzSubText
                subLit: !root.wired && root.wifiActive !== null
                showToggle: !root.wired
                toggleName: "Wi-Fi"
                toggleOn: root.wifiOn
                onToggled: {
                    if (typeof Networking !== "undefined" && Networking)
                        Networking.wifiEnabled = !Networking.wifiEnabled;
                }
                onDrill: root.subview = "wifi"
            }

            LinkRow {
                enabled: !root.airplaneOn
                opacity: root.airplaneOn ? 0.4 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }
                glyph: "bluetooth"
                glyphLit: root.btConnected.length > 0
                label: "Bluetooth"
                subText: root.btSubText
                subLit: root.btPrimary !== null
                toggleName: "Bluetooth"
                toggleOn: root.btOn
                onToggled: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
                onDrill: root.subview = "bt"
            }

            Item { width: 1; height: 8 * root.s }

            // ── 報 INBOX — compact recent-notifications glance ──────────────
            Item {
                width: parent.width
                height: 32 * root.s

                Row {
                    anchors.left: parent.left
                    // Align the 報 kanji with the surface's 8*s content column
                    // (the connectivity glyphs and the glance rows' app names all
                    // start here). Ricelin's 16*s indent aligned 報 over its
                    // NotifRow icon tile; astralis's glance dropped that tile, so
                    // 報 now shares the app-name gutter instead of floating right.
                    anchors.leftMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Flags.showGlyphs
                        text: "報"
                        color: Colors.on_surface_variant
                        font.family: Appearance.font.jp
                        font.weight: Font.Medium
                        font.pixelSize: 11.5 * root.s
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "INBOX"
                        color: Qt.alpha(Colors.on_surface_variant, 0.65)
                        font.family: Appearance.font.family
                        font.pixelSize: 9 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 1.8 * root.s
                    }
                }

                Row {
                    id: inboxClear
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: root.notifCount > 0 ? 1 : 0
                    visible: opacity > 0.01
                    spacing: 4 * root.s
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                    }

                    scale: inboxClearArea.pressed ? 0.92 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    // Destructive and irreversible, so the count rides along:
                    // "CLEAR" alone gives no sense of how much is about to go.
                    Accessible.role: Accessible.Button
                    Accessible.name: "Clear notifications"
                    Accessible.description: root.notifCount + " notification"
                        + (root.notifCount === 1 ? "" : "s")
                    Accessible.focusable: true
                    Accessible.onPressAction: Services.Notifications.clearAll()

                    Rectangle {
                        height: 26 * root.s
                        width: chipRowC.implicitWidth + 22 * root.s
                        radius: height / 2
                        color: Qt.alpha(Colors.error, inboxClearArea.pressed ? 0.22 : inboxClearArea.containsMouse ? 0.16 : 0.10)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Row {
                            id: chipRowC
                            anchors.centerIn: parent
                            spacing: 6 * root.s

                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13 * root.s
                                height: 13 * root.s
                                name: "trash"
                                stroke: 1.8
                                color: Colors.error
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Clear"
                                color: Colors.error
                                font.family: Appearance.font.family
                                font.pixelSize: 11 * root.s
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                MouseArea {
                    id: inboxClearArea
                    anchors.fill: inboxClear
                    visible: root.notifCount > 0
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.Notifications.clearAll()
                }
            }

            // Glance rows: app + summary + age, tap to activate (compact
            // NotifRow — the full center lives on the 報 surface).
            Column {
                visible: root.notifCount > 0
                width: parent.width
                spacing: 4 * root.s

                Repeater {
                    model: root.inboxEntries

                    Rectangle {
                        id: grow
                        required property var modelData
                        required property int index
                        readonly property var n: modelData.entry.n

                        width: parent.width
                        height: 30 * root.s
                        radius: 9 * root.s
                        color: growHover.hovered ? Colors.surface_container_highest : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        // A notification body spans the surface, so it takes the
                        // shallow row dip rather than a chip's.
                        scale: growArea.pressed ? 0.98 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        /**
                         * Entrance cascade (SettingsRow idiom): the glance is a
                         * fixed ≤3-row block that arrives as a unit, so it rides
                         * in as a short wave instead of popping. Re-armed from
                         * `active` rather than creation alone — the surface's
                         * Loader latches once, so a creation-only cascade would
                         * play on the very first open and never again.
                         */
                        property bool entered: false

                        Timer {
                            id: growEnter
                            interval: Motion.rowStagger * grow.index
                            onTriggered: grow.entered = true
                        }

                        Component.onCompleted: growEnter.restart()

                        Connections {
                            target: root
                            function onActiveChanged() {
                                if (root.active) {
                                    grow.entered = false;
                                    growEnter.restart();
                                }
                            }
                        }

                        opacity: grow.entered ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                        }

                        transform: Translate {
                            y: grow.entered ? 0 : 10 * root.s
                            Behavior on y {
                                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                            }
                        }

                        // The app name, age and repeat count are all visually
                        // separated from the summary; read aloud they are the
                        // context that says whether the row is worth opening.
                        Accessible.role: Accessible.Button
                        Accessible.name: (grow.n.summary && grow.n.summary.length)
                            ? grow.n.summary : (grow.n.body || "Notification")
                        Accessible.description: {
                            var parts = [grow.modelData.app];
                            if (grow.modelData.critical)
                                parts.push("critical");
                            if (grow.modelData.entry.count > 1)
                                parts.push(grow.modelData.entry.count + " repeats");
                            parts.push(Services.Notifications.ageLabel(grow.n));
                            return parts.join(" · ");
                        }
                        Accessible.focusable: true
                        Accessible.onPressAction: Services.Notifications.activateEntry(grow.modelData.entry)

                        HoverHandler {
                            id: growHover
                        }

                        MouseArea {
                            id: growArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Notifications.activateEntry(grow.modelData.entry)
                        }

                        Rectangle {
                            visible: grow.modelData.critical
                            anchors.left: parent.left
                            anchors.leftMargin: 1 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2 * root.s
                            height: parent.height - 10 * root.s
                            radius: Appearance.rounding.full
                            color: Colors.error
                        }

                        Text {
                            id: growApp
                            anchors.left: parent.left
                            anchors.leftMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 84 * root.s)
                            text: grow.modelData.app
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2 * root.s
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors.left: growApp.right
                            anchors.leftMargin: 8 * root.s
                            anchors.right: growRight.left
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            text: (grow.n.summary && grow.n.summary.length) ? grow.n.summary : (grow.n.body || "")
                            color: grow.modelData.critical ? Colors.on_surface : Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 10.5 * root.s
                            font.weight: grow.modelData.critical ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                        }

                        Row {
                            id: growRight
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6 * root.s

                            Text {
                                visible: grow.modelData.entry.count > 1
                                anchors.verticalCenter: parent.verticalCenter
                                text: "×" + grow.modelData.entry.count
                                color: grow.modelData.critical ? Colors.error : Qt.alpha(Colors.error, 0.75)
                                font.family: Appearance.font.family
                                font.pixelSize: 9 * root.s
                                font.weight: Font.Bold
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Services.Notifications.ageLabel(grow.n)
                                color: Qt.alpha(Colors.on_surface_variant, 0.6)
                                font.family: Appearance.font.family
                                font.pixelSize: 9 * root.s
                            }
                        }
                    }
                }

                Text {
                    visible: root.inboxTotal > root.inboxEntries.length
                    text: "+" + (root.inboxTotal - root.inboxEntries.length) + " MORE"
                    color: Qt.alpha(Colors.on_surface_variant, 0.5)
                    font.family: Appearance.font.family
                    font.pixelSize: 9 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: 1.4 * root.s
                    leftPadding: 8 * root.s
                    topPadding: 2 * root.s
                }
            }
        }

        // 静 SILENCE — the glance's empty state (Ricelin: Notifs.count === 0).
        Column {
            // Cross-fades with the glance instead of snapping: clearing the
            // inbox is a click the user makes and this is what answers it. The
            // padding is floored because the fade now renders in the other
            // direction too — while it dims out under a just-arrived glance row
            // this Column is briefly shorter than its own content, and a
            // negative top padding would shove 静 up out of its box.
            opacity: root.notifCount === 0 ? 1 : 0
            visible: opacity > 0.01
            anchors.top: mainCol.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 4 * root.s
            topPadding: Math.max(0, (height - 32 * root.s - 9 * root.s - 4 * root.s) / 2)
            Behavior on opacity {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Flags.showGlyphs
                text: "静"
                color: Qt.alpha(Colors.on_surface_variant, 0.4)
                opacity: 0.55
                font.family: Appearance.font.jp
                font.weight: Font.Medium
                font.pixelSize: 32 * root.s
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SILENCE"
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
                font.letterSpacing: 2.2 * root.s
            }
        }
    }

    // ── wifi drill-in ───────────────────────────────────────────────────────
    Item {
        id: wifiView
        anchors.fill: parent
        opacity: root.subview === "wifi" ? 1 : 0
        visible: opacity > 0.01
        enabled: root.subview === "wifi" && root.active
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        SubHeader {
            id: wifiHeader
            anchors.top: parent.top
            title: "Wi-Fi"
            status: root.wifiStatusText
            statusLit: root.wifiActive !== null

            LinkToggle {
                s: root.s
                anchors.verticalCenter: parent.verticalCenter
                on: root.wifiOn
                accessibleName: "Wi-Fi"
                onToggled: {
                    if (typeof Networking !== "undefined" && Networking)
                        Networking.wifiEnabled = !Networking.wifiEnabled;
                }
            }
        }

        Rectangle {
            id: wifiDivider
            anchors.top: wifiHeader.bottom
            anchors.topMargin: 8 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.alpha(Colors.on_surface, 0.06)
        }

        ListView {
            id: wifiList
            anchors.top: wifiDivider.bottom
            anchors.topMargin: 6 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.beadClear
            spacing: 2 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: netModel

            delegate: Column {
                id: netItem
                required property var modelData

                readonly property string ssid: (modelData && modelData.name) ? modelData.name : ""
                readonly property bool isActive: modelData ? modelData.connected === true : false
                readonly property bool secured: root.isSecured(ssid)
                readonly property bool asking: ssid.length > 0 && root.expandedSsid === ssid && !isActive
                readonly property bool known: root.knownProfiles[ssid] === true

                /**
                 * Everything the row says visually — signal as glyph opacity, a
                 * padlock, a tick — collapses to nothing when read aloud, so it
                 * is spelled out here. Security first: it decides whether a tap
                 * connects or opens the password row.
                 */
                readonly property string a11y: {
                    var parts = [netItem.secured ? "secured" : "open"];
                    var sig = Math.round(root.pct(netItem.modelData));
                    parts.push("signal " + sig + "%");
                    if (netItem.isActive)
                        parts.push("connected");
                    else if (netItem.known)
                        parts.push("saved");
                    return parts.join(" · ");
                }

                width: wifiList.width
                spacing: 2 * root.s

                /** Restore the shared draft after a keyed-model row rebuild. */
                function syncPwField() {
                    pwField.text = root.pwDraft;
                    pwField.cursorPosition = pwField.text.length;
                    pwField.forceActiveFocus();
                }

                onAskingChanged: if (asking) Qt.callLater(syncPwField)
                Component.onCompleted: if (asking) Qt.callLater(syncPwField)

                Rectangle {
                    id: netRow
                    width: parent.width
                    height: 30 * root.s
                    radius: 9 * root.s
                    color: netHover.hovered ? Colors.surface_container_highest
                        : (netItem.isActive ? Qt.alpha(Colors.primary, 0.12) : "transparent")
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    scale: netArea.pressed ? 0.96 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: netItem.ssid
                    Accessible.description: netItem.a11y
                    Accessible.selected: netItem.isActive
                    Accessible.focusable: true
                    Accessible.onPressAction: root.activateNetwork(netItem.modelData)

                    HoverHandler {
                        id: netHover
                    }

                    MouseArea {
                        id: netArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activateNetwork(netItem.modelData)
                    }

                    WifiSignal {
                        id: netGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 10 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16 * root.s
                        height: 16 * root.s
                        strength: root.pct(netItem.modelData)
                        // Association lands asynchronously; the bars light into
                        // the accent rather than flicking the instant nmcli
                        // reports back.
                        color: netItem.isActive ? Colors.primary : Colors.on_surface_variant
                    }

                    Text {
                        anchors.left: netGlyph.right
                        anchors.leftMargin: 9 * root.s
                        anchors.right: netRight.left
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: netItem.ssid
                        color: netItem.isActive ? Colors.on_surface : Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 11.5 * root.s
                        font.weight: netItem.isActive ? Font.DemiBold : Font.Medium
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    Row {
                        id: netRight
                        anchors.right: parent.right
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7 * root.s

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: netItem.secured
                            width: 13 * root.s
                            height: 13 * root.s
                            name: "lock-outline"
                            color: netItem.isActive ? Colors.primary : Colors.on_surface_variant
                            stroke: 1.9
                        }

                        GlyphIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: netItem.isActive
                            width: 13 * root.s
                            height: 13 * root.s
                            name: "check"
                            color: Colors.primary
                            stroke: 2
                        }

                        // Saved networks only: an unknown one has nothing to set.
                        ItemCog {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: netItem.known || netItem.isActive
                                || (netItem.modelData && netItem.modelData.known === true)
                            itemName: netItem.ssid
                            onClicked: root.openWifiItem(netItem.ssid)
                        }
                    }
                }

                // Inline password row (Ricelin LinkWifi "asking" row): masked
                // field, Enter or the return glyph submits, pulse dot while
                // nmcli runs.
                Item {
                    /**
                     * Grows open under the tapped row instead of snapping the
                     * whole list down a notch. Visibility is gated on OPACITY,
                     * never on the animated height: a Column stops recomputing
                     * its children's sizes while it is itself hidden, so a
                     * `visible: height > 0` gate would latch shut for good.
                     */
                    opacity: netItem.asking ? 1 : 0
                    visible: opacity > 0.01
                    enabled: netItem.asking
                    clip: true
                    width: parent.width
                    height: netItem.asking ? 42 * root.s : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }

                    // Filled field: lock, masked entry, reveal, and a round
                    // connect button that carries the pulse while nmcli runs.
                    Rectangle {
                        id: pwBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 4 * root.s
                        anchors.rightMargin: 4 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        height: 34 * root.s
                        radius: height / 2
                        color: Colors.surface_container_highest
                        border.width: 1.2 * root.s
                        border.color: root.connectFailed && netItem.asking ? Colors.error
                            : pwField.activeFocus ? Colors.primary : "transparent"
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        property bool reveal: false

                        GlyphIcon {
                            id: pwLock
                            anchors.left: parent.left
                            anchors.leftMargin: 12 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14 * root.s
                            height: 14 * root.s
                            name: "lock-outline"
                            stroke: 1.7
                            color: pwField.activeFocus ? Colors.primary : Colors.on_surface_variant
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        TextField {
                            id: pwField
                            anchors.left: pwLock.right
                            anchors.leftMargin: 8 * root.s
                            anchors.right: pwEye.left
                            anchors.rightMargin: 4 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            background: null
                            padding: 0
                            color: Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 12 * root.s
                            echoMode: pwBox.reveal ? TextInput.Normal : TextInput.Password
                            placeholderText: "Password"
                            Accessible.name: "Password for " + netItem.ssid
                            placeholderTextColor: Qt.alpha(Colors.on_surface_variant, 0.65)
                            selectByMouse: true
                            selectionColor: Colors.primary
                            selectedTextColor: Colors.on_primary
                            onTextEdited: root.pwDraft = text
                            onAccepted: root.connectWithPassword(netItem.ssid, text)
                        }

                        Item {
                            id: pwEye
                            anchors.right: pwGo.left
                            anchors.rightMargin: 4 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26 * root.s
                            height: 26 * root.s
                            opacity: pwField.text.length > 0 ? 1 : 0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                            Accessible.role: Accessible.Button
                            Accessible.name: pwBox.reveal ? "Hide password" : "Show password"
                            Accessible.onPressAction: pwBox.reveal = !pwBox.reveal

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: eyeArea.containsMouse ? Qt.alpha(Colors.on_surface, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 14 * root.s
                                height: 14 * root.s
                                name: pwBox.reveal ? "eye-off" : "eye"
                                stroke: 1.7
                                color: Colors.on_surface_variant
                            }
                            MouseArea {
                                id: eyeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pwBox.reveal = !pwBox.reveal;
                                    pwField.forceActiveFocus();
                                }
                            }
                        }

                        Rectangle {
                            id: pwGo
                            anchors.right: parent.right
                            anchors.rightMargin: 4 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26 * root.s
                            height: 26 * root.s
                            radius: width / 2
                            readonly property bool ready: pwField.text.length > 0
                            color: ready ? Colors.primary : Qt.alpha(Colors.on_surface, 0.1)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            scale: enterArea.pressed ? 0.92 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }

                            // While nmcli runs the button breathes instead of
                            // a separate dot competing with it.
                            SequentialAnimation on opacity {
                                running: root.connecting && netItem.asking && !Motion.reduceMotion
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { from: 1; to: 0.45; duration: Motion.pulse; easing.type: Motion.easeStandard }
                                NumberAnimation { from: 0.45; to: 1; duration: Motion.pulse; easing.type: Motion.easeStandard }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: "Connect"
                            Accessible.description: "Join " + netItem.ssid + " with the entered password"
                            Accessible.focusable: true
                            Accessible.onPressAction: root.connectWithPassword(netItem.ssid, pwField.text)

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 14 * root.s
                                height: 14 * root.s
                                name: "arrow-right"
                                stroke: 2
                                color: pwGo.ready ? Colors.on_primary : Colors.on_surface_variant
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }

                            MouseArea {
                                id: enterArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectWithPassword(netItem.ssid, pwField.text)
                            }
                        }
                    }
                }

                Text {
                    // Fades and grows in with the rest of the expansion rather
                    // than shunting the list down the frame nmcli gives up.
                    readonly property bool shown: netItem.asking && root.connectFailed
                    opacity: shown ? 1 : 0
                    visible: opacity > 0.01
                    clip: true
                    height: shown ? implicitHeight : 0
                    text: "Connection failed"
                    color: Colors.error
                    font.family: Appearance.font.family
                    font.pixelSize: 10 * root.s
                    leftPadding: 18 * root.s
                    bottomPadding: 4 * root.s
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }
                }
            }
        }

        HintText {
            // The hint and the list share this space, so they cross-fade: a
            // bare `visible` flip made the first scan result blink the hint out
            // mid-sentence.
            readonly property bool shown: root.wifiOn ? root.nets.length === 0 : true
            anchors.centerIn: wifiList
            opacity: shown ? 1 : 0
            visible: opacity > 0.01
            text: root.wifiDev === null ? "No Wi-Fi adapter"
                : (root.wifiOn ? "Searching networks…" : "Wi-Fi is off")
            Behavior on opacity {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }
        }
    }

    // ── bluetooth drill-in ──────────────────────────────────────────────────
    Item {
        id: btView
        anchors.fill: parent
        opacity: root.subview === "bt" ? 1 : 0
        visible: opacity > 0.01
        enabled: root.subview === "bt" && root.active
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        SubHeader {
            id: btHeader
            anchors.top: parent.top
            title: "Bluetooth"
            status: root.btSubText
            statusLit: root.btPrimary !== null

            // Scan/discovery toggle (Ricelin LinkBt header): lights primary
            // while discovering; the 25s timer stops a forgotten scan.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.btOn
                text: root.btDiscovering ? "Scanning…" : "Scan"
                color: root.btDiscovering ? Colors.primary
                    : (btScanArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant)
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
                scale: btScanArea.pressed ? 0.92 : 1
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.glide
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }

                // One control with two meanings, so the name follows the
                // state rather than the label — "Scanning…" read aloud sounds
                // like a status line, not something you can press to stop.
                Accessible.role: Accessible.Button
                Accessible.name: root.btDiscovering ? "Stop scanning" : "Scan for devices"
                Accessible.focusable: true
                Accessible.onPressAction: root.btToggleScan()

                MouseArea {
                    id: btScanArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.btToggleScan()
                }
            }

            LinkToggle {
                s: root.s
                anchors.verticalCenter: parent.verticalCenter
                on: root.btOn
                accessibleName: "Bluetooth"
                onToggled: if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled
            }
        }

        Rectangle {
            id: btDivider
            anchors.top: btHeader.bottom
            anchors.topMargin: 8 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.alpha(Colors.on_surface, 0.06)
        }

        ListView {
            id: btList
            anchors.top: btDivider.bottom
            anchors.topMargin: 6 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.beadClear
            spacing: 2 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: btModel

            // Ricelin LinkBt device delegate: two-line row (name over
            // connected/paired · trusted · state), pairing/busy ember,
            // battery %, Pair chip for unpaired devices, and an inline
            // confirm row (Connect/Disconnect · Trust · Forget) for known
            // ones, with a transient "Pairing failed" line.
            delegate: Column {
                id: devItem
                required property var modelData

                readonly property bool isConnected: modelData ? modelData.connected === true : false
                readonly property bool isPaired: modelData ? modelData.paired === true : false
                readonly property bool isTrusted: modelData ? modelData.trusted === true : false
                readonly property string addr: (modelData && modelData.address) ? modelData.address : ""
                readonly property bool pairing: (addr.length > 0 && root.btPairingAddress === addr)
                    || (modelData ? modelData.pairing === true : false)
                readonly property bool busy: (modelData && typeof BluetoothDeviceState !== "undefined")
                    ? (modelData.state === BluetoothDeviceState.Connecting
                        || modelData.state === BluetoothDeviceState.Disconnecting)
                    : false
                readonly property bool failed: addr.length > 0 && root.btFailedAddress === addr
                readonly property bool confirming: addr.length > 0 && root.btExpandedAddress === addr
                readonly property string batteryText: root.btBatteryText(modelData)

                /** A nameless discovery is still selectable, so it falls back to its MAC. */
                readonly property string devName: modelData
                    ? (modelData.deviceName || modelData.name || addr)
                    : ""

                /**
                 * The meta line, the battery percent and the pairing ember are
                 * three separate visual channels; read aloud they have to be
                 * one sentence, and "not paired" has to be said out loud —
                 * visually it is conveyed by the Pair chip merely existing.
                 */
                readonly property string a11y: {
                    var meta = root.btMetaFor(devItem.modelData);
                    var parts = meta.length > 0 ? [meta] : ["not paired"];
                    if (devItem.batteryText.length > 0)
                        parts.push("battery " + devItem.batteryText);
                    if (devItem.pairing)
                        parts.push("pairing…");
                    return parts.join(" · ");
                }

                width: btList.width
                spacing: 2 * root.s

                Rectangle {
                    id: devRow
                    width: parent.width
                    height: 36 * root.s
                    radius: 9 * root.s
                    color: devHover.hovered ? Colors.surface_container_highest
                        : (devItem.isConnected ? Qt.alpha(Colors.primary, 0.12) : "transparent")
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    scale: devArea.pressed ? 0.96 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: devItem.devName
                    Accessible.description: devItem.a11y
                    Accessible.selected: devItem.isConnected
                    Accessible.focusable: true
                    Accessible.onPressAction: root.btActivate(devItem.modelData)

                    HoverHandler {
                        id: devHover
                    }

                    MouseArea {
                        id: devArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.btActivate(devItem.modelData)
                    }

                    GlyphIcon {
                        id: devGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        width: 15 * root.s
                        height: 15 * root.s
                        name: "bluetooth"
                        color: devItem.isConnected ? Colors.primary : Colors.on_surface_variant
                        stroke: 1.7
                        // Connect/disconnect lands a beat after the tap, so the
                        // glyph blooms into the accent instead of flicking.
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    Column {
                        anchors.left: devGlyph.right
                        anchors.leftMargin: 9 * root.s
                        anchors.right: devRight.left
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1 * root.s

                        Text {
                            width: parent.width
                            text: devItem.devName
                            color: devItem.isConnected ? Colors.on_surface : Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 11.5 * root.s
                            font.weight: devItem.isConnected ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        Text {
                            width: parent.width
                            visible: text.length > 0
                            text: root.btMetaFor(devItem.modelData)
                            color: Qt.alpha(Colors.on_surface_variant, 0.65)
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * root.s
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: devRight
                        anchors.right: parent.right
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8 * root.s

                        // Pulse ember while pairing / connecting / disconnecting.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: devItem.pairing || devItem.busy
                            width: 4 * root.s
                            height: 4 * root.s
                            radius: width / 2
                            color: Colors.primary

                            SequentialAnimation on opacity {
                                running: (devItem.pairing || devItem.busy) && !Motion.reduceMotion
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Motion.easeStandard }
                                NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Motion.easeStandard }
                            }
                        }

                        // Battery %, only when the device exposes one.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: devItem.isConnected && devItem.batteryText.length > 0
                            text: devItem.batteryText
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9.5 * root.s
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                        }

                        // Pair chip for unpaired discoveries (Ricelin LinkBt).
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !devItem.isPaired && !devItem.pairing
                            radius: 999
                            color: pairArea.containsMouse ? Colors.surface_container_highest : "transparent"
                            border.width: 1
                            border.color: pairArea.containsMouse
                                ? Qt.alpha(Colors.primary, 0.5) : Qt.alpha(Colors.outline_variant, 0.6)
                            height: 18 * root.s
                            width: pairText.implicitWidth + 16 * root.s
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                            scale: pairArea.pressed ? 0.92 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }

                            Text {
                                id: pairText
                                anchors.centerIn: parent
                                text: "Pair"
                                color: pairArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                                font.family: Appearance.font.family
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.DemiBold
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }

                            // "Pair" alone is ambiguous in a list of devices —
                            // the description says which one it bonds.
                            Accessible.role: Accessible.Button
                            Accessible.name: "Pair"
                            Accessible.description: devItem.devName
                            Accessible.focusable: true
                            Accessible.onPressAction: root.btActivate(devItem.modelData)

                            MouseArea {
                                id: pairArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.btActivate(devItem.modelData)
                            }
                        }

                        ItemCog {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: devItem.isPaired
                            itemName: devItem.devName
                            onClicked: root.openBtItem(devItem.modelData)
                        }
                    }
                }

                // Inline confirm row for known devices (Ricelin LinkBt):
                // Connect/Disconnect, a Trust toggle, and Forget.
                Item {
                    // Grows open like the Wi-Fi password row; gated on opacity
                    // (a hidden Column stops recomputing its children).
                    opacity: devItem.confirming ? 1 : 0
                    visible: opacity > 0.01
                    clip: true
                    width: parent.width
                    height: devItem.confirming ? 26 * root.s : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10 * root.s
                        anchors.right: confirmBtns.left
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: devItem.isConnected ? "Connected" : "Paired"
                        color: Qt.alpha(Colors.on_surface_variant, 0.65)
                        font.family: Appearance.font.family
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    Row {
                        id: confirmBtns
                        anchors.right: parent.right
                        anchors.rightMargin: 10 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6 * root.s

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: primaryLabel.implicitWidth + 18 * root.s
                            height: 20 * root.s
                            radius: 7 * root.s
                            color: primaryArea.containsMouse ? Colors.surface_container_highest : "transparent"
                            border.width: 1
                            border.color: primaryArea.containsMouse
                                ? Qt.alpha(Colors.primary, 0.5) : Qt.alpha(Colors.outline_variant, 0.6)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                            scale: primaryArea.pressed ? 0.92 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }

                            // The label flips with the link state, so the name
                            // has to follow it rather than be fixed at "Connect".
                            Accessible.role: Accessible.Button
                            Accessible.name: primaryLabel.text
                            Accessible.description: devItem.devName
                            Accessible.focusable: true
                            Accessible.onPressAction: devItem.isConnected
                                ? root.btDisconnect(devItem.modelData)
                                : root.btConnect(devItem.modelData)

                            Text {
                                id: primaryLabel
                                anchors.centerIn: parent
                                text: devItem.isConnected ? "Disconnect" : "Connect"
                                color: Colors.on_surface
                                font.family: Appearance.font.family
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: primaryArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: devItem.isConnected
                                    ? root.btDisconnect(devItem.modelData)
                                    : root.btConnect(devItem.modelData)
                            }
                        }

                        // Trusted-state toggle: writes the BlueZ Trusted flag
                        // through the writable Quickshell device property.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: trustLabel.implicitWidth + 18 * root.s
                            height: 20 * root.s
                            radius: 7 * root.s
                            color: devItem.isTrusted ? Qt.alpha(Colors.primary, 0.12)
                                : (trustArea.containsMouse ? Colors.surface_container_highest : "transparent")
                            border.width: 1
                            border.color: devItem.isTrusted
                                ? Qt.alpha(Colors.primary, 0.5) : Qt.alpha(Colors.outline_variant, 0.6)
                            // BlueZ acknowledges the Trusted write a beat later,
                            // so the chip settles into the accent instead of
                            // flicking when the property comes back.
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                            scale: trustArea.pressed ? 0.92 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }

                            // A latching flag, not an action: CheckBox is what
                            // lets a screen reader say "Trusted, checked".
                            Accessible.role: Accessible.CheckBox
                            Accessible.name: "Trust"
                            Accessible.description: devItem.devName
                                + " — reconnects without asking"
                            Accessible.checkable: true
                            Accessible.checked: devItem.isTrusted
                            Accessible.focusable: true
                            Accessible.onToggleAction: if (devItem.modelData)
                                devItem.modelData.trusted = !devItem.modelData.trusted
                            Accessible.onPressAction: if (devItem.modelData)
                                devItem.modelData.trusted = !devItem.modelData.trusted

                            Text {
                                id: trustLabel
                                anchors.centerIn: parent
                                text: devItem.isTrusted ? "Trusted" : "Trust"
                                color: devItem.isTrusted ? Colors.primary : Colors.on_surface
                                font.family: Appearance.font.family
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.DemiBold
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }

                            MouseArea {
                                id: trustArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (devItem.modelData)
                                    devItem.modelData.trusted = !devItem.modelData.trusted
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: forgetLabel.implicitWidth + 18 * root.s
                            height: 20 * root.s
                            radius: 7 * root.s
                            color: forgetArea.containsMouse
                                ? Qt.alpha(Colors.error, 0.2) : Qt.alpha(Colors.error, 0.12)
                            border.width: 1
                            border.color: Qt.alpha(Colors.error, 0.45)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            scale: forgetArea.pressed ? 0.92 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }

                            // Destructive: the description names the device so
                            // it can't be confirmed blind from the wrong row.
                            Accessible.role: Accessible.Button
                            Accessible.name: "Forget"
                            Accessible.description: "Remove the pairing with " + devItem.devName
                            Accessible.focusable: true
                            Accessible.onPressAction: root.btForget(devItem.modelData)

                            Text {
                                id: forgetLabel
                                anchors.centerIn: parent
                                text: "Forget"
                                color: Colors.error
                                font.family: Appearance.font.family
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: forgetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.btForget(devItem.modelData)
                            }
                        }
                    }
                }

                Text {
                    readonly property bool shown: devItem.failed
                    opacity: shown ? 1 : 0
                    visible: opacity > 0.01
                    clip: true
                    height: shown ? implicitHeight : 0
                    text: "Pairing failed"
                    color: Colors.error
                    font.family: Appearance.font.family
                    font.pixelSize: 9.5 * root.s
                    leftPadding: 32 * root.s
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.morphCurve
                        }
                    }
                }
            }
        }

        HintText {
            // Cross-fades with the list like the Wi-Fi hint does.
            readonly property bool shown: root.btDevices.length === 0
            anchors.centerIn: btList
            opacity: shown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }
            text: root.btAdapter === null ? "No Bluetooth adapter"
                : (!root.btOn ? "Bluetooth is off"
                    : (root.btDiscovering ? "Scanning…" : "No devices — scan to discover"))
        }
    }

    // ── wifi network settings ───────────────────────────────────────────────
    Item {
        id: wifiItemView
        anchors.fill: parent
        opacity: root.subview === "wifiItem" ? 1 : 0
        visible: opacity > 0.01
        enabled: root.subview === "wifiItem" && root.active
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        SubHeader {
            id: wifiItemHeader
            anchors.top: parent.top
            title: root.itemSsid
            status: root.itemStatusText
            statusLit: root.itemNetConnected
            backHint: "Return to the Wi-Fi list"
        }

        Rectangle {
            id: wifiItemDivider
            anchors.top: wifiItemHeader.bottom
            anchors.topMargin: 8 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.alpha(Colors.on_surface, 0.06)
        }

        Flickable {
            anchors.top: wifiItemDivider.bottom
            anchors.topMargin: 2 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.beadClear
            contentHeight: wifiItemCol.implicitHeight + 8 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: wifiItemCol
                width: parent.width
                spacing: 2 * root.s

                Row {
                    topPadding: 10 * root.s
                    bottomPadding: 2 * root.s
                    leftPadding: 4 * root.s
                    spacing: 8 * root.s

                    ItemAction {
                        label: root.itemNetConnected ? "Disconnect" : "Connect"
                        icon: root.itemNetConnected ? "close" : "wifi"
                        filled: !root.itemNetConnected
                        description: root.itemSsid
                        enabled: root.itemNet !== null && root.wifiOn
                        onClicked: {
                            if (!root.itemNet)
                                return;
                            if (root.itemNetConnected)
                                root.itemNet.disconnect();
                            else
                                root.itemNet.connect();
                        }
                    }

                    ItemAction {
                        label: root.itemForgetArmed ? "Tap again to forget" : "Forget"
                        icon: "trash"
                        danger: true
                        description: "Delete the saved profile for " + root.itemSsid
                        enabled: root.itemProfiles.length > 0 || root.itemNet !== null
                        onClicked: root.forgetWifiItem()
                    }
                }

                SettingsUi.SettingsGroupLabel {
                    s: root.s
                    text: "Connection"
                }

                ItemSwitch {
                    label: "Auto-connect"
                    sub: "Join automatically when in range"
                    on: root.itemAutoconnect
                    enabled: root.itemPrimary !== null
                    onToggled: root.setWifiItemProp("connection.autoconnect", root.itemAutoconnect ? "no" : "yes")
                }

                ItemSwitch {
                    label: "Metered"
                    sub: "Tell apps this link has a data cap"
                    on: root.itemMetered
                    enabled: root.itemPrimary !== null
                    onToggled: root.setWifiItemProp("connection.metered", root.itemMetered ? "no" : "yes")
                }

                // Saved password: masked until asked for, read from nmcli on
                // demand and dropped again when the page closes.
                Rectangle {
                    id: pskRow
                    visible: root.itemPrimary !== null && (root.itemSecured || root.itemNet === null)
                    width: parent.width
                    height: 34 * root.s
                    radius: 9 * root.s
                    color: "transparent"

                    Text {
                        id: pskLabel
                        anchors.left: parent.left
                        anchors.leftMargin: 10 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password"
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 11.5 * root.s
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.left: pskLabel.right
                        anchors.leftMargin: 12 * root.s
                        anchors.right: pskBtns.left
                        anchors.rightMargin: 6 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: root.itemCopied === "Password" ? "Copied"
                            : root.itemPskMissing ? "Not stored"
                            : root.itemPskShown ? root.itemPsk : "••••••••"
                        color: root.itemCopied === "Password" ? Colors.primary
                            : root.itemPskMissing ? Colors.on_surface_variant : Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.Medium
                        elide: Text.ElideMiddle
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    Row {
                        id: pskBtns
                        anchors.right: parent.right
                        anchors.rightMargin: 4 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s
                        visible: !root.itemPskMissing

                        Repeater {
                            model: [
                                { glyph: root.itemPskShown ? "eye-off" : "eye",
                                  name: root.itemPskShown ? "Hide password" : "Show password", copy: false },
                                { glyph: "copy", name: "Copy password", copy: true }
                            ]

                            delegate: Item {
                                id: pskBtn
                                required property var modelData
                                width: 26 * root.s
                                height: 26 * root.s

                                Accessible.role: Accessible.Button
                                Accessible.name: pskBtn.modelData.name
                                Accessible.focusable: true
                                Accessible.onPressAction: pskBtn.modelData.copy
                                    ? root.copyWifiItemPsk() : root.toggleWifiItemPsk()

                                scale: pskBtnArea.pressed ? 0.9 : 1
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Motion.glide
                                        easing.type: Motion.easeBezier
                                        easing.bezierCurve: Motion.expressiveFastSpatial
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: pskBtnArea.containsMouse ? Qt.alpha(Colors.on_surface, 0.08) : "transparent"
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }
                                GlyphIcon {
                                    anchors.centerIn: parent
                                    width: 14 * root.s
                                    height: 14 * root.s
                                    name: pskBtn.modelData.glyph
                                    stroke: 1.7
                                    color: pskBtnArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }
                                MouseArea {
                                    id: pskBtnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pskBtn.modelData.copy
                                        ? root.copyWifiItemPsk() : root.toggleWifiItemPsk()
                                }
                            }
                        }
                    }
                }

                SettingsUi.SettingsGroupLabel {
                    s: root.s
                    text: "Details"
                }

                ItemDetail {
                    label: "Signal"
                    copyable: false
                    value: root.itemNet ? Math.round(root.pct(root.itemNet)) + "%" : ""
                }
                ItemDetail {
                    label: "Security"
                    copyable: false
                    value: root.itemAp.security
                        || (root.itemNet ? (root.itemSecured ? "Secured" : "Open") : "")
                }
                ItemDetail {
                    label: "Band"
                    copyable: false
                    value: {
                        var b = root.bandText(root.itemAp.freq);
                        var ch = root.itemAp.chan || "";
                        return b.length ? b + (ch.length ? " · ch " + ch : "") : "";
                    }
                }
                ItemDetail {
                    label: "Link rate"
                    copyable: false
                    value: root.itemNetConnected ? (root.itemAp.rate || "") : ""
                }
                ItemDetail { label: "IP address"; value: root.itemIp.ip4 || "" }
                ItemDetail { label: "Gateway"; value: root.itemIp.gw || "" }
                ItemDetail { label: "DNS"; value: root.itemIp.dns || "" }
                ItemDetail { label: "IPv6"; value: root.itemIp.ip6 || "" }
                ItemDetail { label: "MAC address"; value: root.itemIp.mac || "" }
                ItemDetail { label: "BSSID"; value: root.itemAp.bssid || "" }
                ItemDetail {
                    // Only worth a line when the profile isn't simply the SSID.
                    label: "Profile"
                    copyable: false
                    value: (root.itemPrimary && (root.itemPrimary.id !== root.itemSsid || root.itemProfiles.length > 1))
                        ? root.itemPrimary.id + (root.itemProfiles.length > 1
                            ? " +" + (root.itemProfiles.length - 1) + " more" : "")
                        : ""
                }
            }
        }

        HintText {
            anchors.centerIn: parent
            visible: root.itemLoaded && root.itemProfiles.length === 0 && root.itemNet === null
            text: "No saved profile"
        }
    }

    // ── bluetooth device settings ───────────────────────────────────────────
    Item {
        id: btItemView
        anchors.fill: parent
        opacity: root.subview === "btItem" ? 1 : 0
        visible: opacity > 0.01
        enabled: root.subview === "btItem" && root.active
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        SubHeader {
            id: btItemHeader
            anchors.top: parent.top
            title: root.itemDevName
            status: root.itemDevStatus
            statusLit: root.itemDev !== null && root.itemDev.connected === true
            backHint: "Return to the Bluetooth list"
        }

        Rectangle {
            id: btItemDivider
            anchors.top: btItemHeader.bottom
            anchors.topMargin: 8 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.alpha(Colors.on_surface, 0.06)
        }

        Flickable {
            anchors.top: btItemDivider.bottom
            anchors.topMargin: 2 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.beadClear
            contentHeight: btItemCol.implicitHeight + 8 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            visible: root.itemDev !== null

            Column {
                id: btItemCol
                width: parent.width
                spacing: 2 * root.s

                Row {
                    topPadding: 10 * root.s
                    bottomPadding: 2 * root.s
                    leftPadding: 4 * root.s
                    spacing: 8 * root.s

                    ItemAction {
                        readonly property bool conn: root.itemDev !== null && root.itemDev.connected === true
                        label: conn ? "Disconnect" : "Connect"
                        icon: conn ? "close" : "bluetooth"
                        filled: !conn
                        description: root.itemDevName
                        enabled: root.itemDev !== null && root.btOn && root.itemDev.blocked !== true
                        onClicked: conn ? root.btDisconnect(root.itemDev) : root.btConnect(root.itemDev)
                    }

                    ItemAction {
                        label: root.itemForgetArmed ? "Tap again to forget" : "Forget"
                        icon: "trash"
                        danger: true
                        description: "Remove the pairing with " + root.itemDevName
                        onClicked: root.forgetBtItem()
                    }
                }

                SettingsUi.SettingsGroupLabel {
                    s: root.s
                    text: "Name"
                }

                // Rename: writes the BlueZ alias; the undo mark hands the
                // device its own name back.
                Rectangle {
                    width: parent.width - 8 * root.s
                    x: 4 * root.s
                    height: 34 * root.s
                    radius: height / 2
                    color: Colors.surface_container_highest
                    border.width: 1.2 * root.s
                    border.color: btNameField.activeFocus ? Colors.primary : "transparent"
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    readonly property bool aliased: root.itemDev !== null
                        && (root.itemDev.deviceName || "").length > 0
                        && root.itemDev.name !== root.itemDev.deviceName

                    TextField {
                        id: btNameField
                        anchors.left: parent.left
                        anchors.leftMargin: 14 * root.s
                        anchors.right: btNameGo.left
                        anchors.rightMargin: 6 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        background: null
                        padding: 0
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 12 * root.s
                        placeholderText: root.itemDev ? (root.itemDev.deviceName || "Name") : "Name"
                        placeholderTextColor: Qt.alpha(Colors.on_surface_variant, 0.65)
                        Accessible.name: "Name for " + root.itemDevName
                        selectByMouse: true
                        selectionColor: Colors.primary
                        selectedTextColor: Colors.on_primary
                        onAccepted: {
                            root.btRename(root.itemDev, text);
                            focus = false;
                        }
                    }

                    // Apply when edited; reset-to-own-name when it carries an alias.
                    Item {
                        id: btNameGo
                        anchors.right: parent.right
                        anchors.rightMargin: 4 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26 * root.s
                        height: 26 * root.s

                        readonly property bool dirty: root.itemDev !== null
                            && btNameField.text.trim() !== (root.itemDev.name || "")
                        readonly property bool resettable: parent.aliased && !dirty
                        visible: dirty || resettable

                        Accessible.role: Accessible.Button
                        Accessible.name: btNameGo.dirty ? "Rename" : "Restore the device's own name"
                        Accessible.focusable: true
                        Accessible.onPressAction: btNameGoArea.clicked(null)

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: btNameGo.dirty ? Colors.primary
                                : (btNameGoArea.containsMouse ? Qt.alpha(Colors.on_surface, 0.08) : "transparent")
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 14 * root.s
                            height: 14 * root.s
                            name: btNameGo.dirty ? "check" : "undo"
                            stroke: 2
                            color: btNameGo.dirty ? Colors.on_primary : Colors.on_surface_variant
                        }
                        MouseArea {
                            id: btNameGoArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (btNameGo.dirty) {
                                    root.btRename(root.itemDev, btNameField.text);
                                } else {
                                    root.btRename(root.itemDev, "");
                                    btNameField.text = root.itemDev ? (root.itemDev.deviceName || "") : "";
                                }
                                btNameField.focus = false;
                            }
                        }
                    }
                }

                SettingsUi.SettingsGroupLabel {
                    s: root.s
                    text: "Device"
                }

                ItemSwitch {
                    label: "Trusted"
                    sub: "Reconnects without asking"
                    on: root.itemDev !== null && root.itemDev.trusted === true
                    onToggled: if (root.itemDev) root.itemDev.trusted = !root.itemDev.trusted
                }

                ItemSwitch {
                    // BlueZ only honours WakeAllowed for input (HID) devices.
                    visible: root.itemDevInput
                    label: "Wake from sleep"
                    sub: "Input from it can wake the computer"
                    on: root.itemDev !== null && root.itemDev.wakeAllowed === true
                    onToggled: if (root.itemDev) root.itemDev.wakeAllowed = !root.itemDev.wakeAllowed
                }

                ItemSwitch {
                    label: "Blocked"
                    sub: "Refuse every connection from it"
                    on: root.itemDev !== null && root.itemDev.blocked === true
                    onToggled: if (root.itemDev) root.itemDev.blocked = !root.itemDev.blocked
                }

                SettingsUi.SettingsGroupLabel {
                    s: root.s
                    text: "Details"
                }

                ItemDetail {
                    label: "Type"
                    copyable: false
                    value: root.itemDev ? root.btKindText(root.itemDev.icon) : ""
                }
                ItemDetail {
                    label: "Battery"
                    copyable: false
                    value: root.btBatteryText(root.itemDev)
                }
                ItemDetail {
                    label: "Address"
                    value: root.itemBtAddress
                }
                ItemDetail {
                    label: "Device name"
                    copyable: false
                    value: (root.itemDev && root.itemDev.deviceName !== root.itemDev.name)
                        ? (root.itemDev.deviceName || "") : ""
                }
            }
        }

        HintText {
            anchors.centerIn: parent
            visible: root.itemDev === null
            text: "Device no longer available"
        }
    }
}
