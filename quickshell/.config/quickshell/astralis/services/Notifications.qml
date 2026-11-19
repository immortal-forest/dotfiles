pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications

/**
 * astralis — notification backend (ported from Gakuseei/Ricelin
 * pill/Singletons/Notifs.qml). QS owns the freedesktop notification server
 * itself: every notification is tracked (kept alive in trackedNotifications),
 * recent arrivals also ride `popups` so the pill can morph into a toast, and
 * closed ones snapshot into `history` so the center surface keeps a backlog.
 *
 *  - `popups`   → the pill's toast face (newest last, capped at 3)
 *  - `groups`   → the notification-center surface (app-grouped, duplicate
 *                 summary/body pairs coalesced into counts, newest-first,
 *                 criticals separated per group)
 *  - `unread`   → the hover-row inbox dot
 *  - `dnd`      → suppresses non-critical toasts; the center still records
 *
 * ONLY one process may own org.freedesktop.Notifications: if mako/dunst/swaync
 * is running this server never binds and notifications silently vanish.
 */
Singleton {
    id: root

    // ── bookkeeping (maps reassigned wholesale so bindings re-evaluate) ─────
    property var seenIds: ({})          // id → true once the center was opened
    property var arrivalMs: ({})        // id → Date.now() at arrival
    property var expireAt: ({})         // id → toast deadline (snapshotted by Toast)
    property var userDismissed: ({})    // id → true when WE dismissed (skip history)
    property var hookedIds: ({})        // id → true once `closed` is connected
    property var expandedApps: ({})     // app → true when its group is expanded
    property var popups: []             // currently-showing toasts
    property var history: []            // closed-notification backlog (max 50)
    property int tick: 0                // 30s heartbeat for ageLabel refresh

    /** Do-not-disturb: non-critical arrivals skip the toast queue. */
    property bool dnd: false

    // ── Settings → Notifications (pushed in by Flags, like `dnd`) ───────────
    /** Quiet hours: DND turns itself on every day from quietFrom to quietTo (minutes since midnight). */
    property bool scheduleOn: false
    property int quietFrom: 1380
    property int quietTo: 420
    /** Critical notifications still pop up while quiet. */
    property bool urgentThrough: true
    /** "short" | "normal" | "long" — scales how long a toast stays. */
    property string popupLength: "normal"
    /** Chime when a toast shows. */
    property bool sound: false
    /** App label (sourceLabel) → "silent" | "off"; absent = "alert". */
    property var appRules: ({})

    property int nowMin: 0
    function stampNow() {
        var d = new Date();
        root.nowMin = d.getHours() * 60 + d.getMinutes();
    }
    Timer {
        interval: 20000
        running: root.scheduleOn
        repeat: true
        triggeredOnStart: true
        onTriggered: root.stampNow()
    }

    /** Quiet hours switched off for the rest of tonight's window (ms timestamp; phone-style tile tap). */
    property real quietSkipUntil: 0
    function skipQuietHours() {
        var d = new Date();
        d.setHours(Math.floor(root.quietTo / 60), root.quietTo % 60, 0, 0);
        if (d.getTime() <= Date.now())
            d.setDate(d.getDate() + 1);
        root.quietSkipUntil = d.getTime();
    }

    readonly property bool inQuietHours: {
        if (!root.scheduleOn || root.quietFrom === root.quietTo)
            return false;
        var t = root.nowMin;
        if (Date.now() < root.quietSkipUntil)
            return false;
        return root.quietFrom < root.quietTo
            ? (t >= root.quietFrom && t < root.quietTo)
            : (t >= root.quietFrom || t < root.quietTo);
    }
    /** What every view should treat as "silenced": manual DND or quiet hours. */
    readonly property bool quiet: root.dnd || root.inQuietHours

    function validMode(m) {
        return m === "silent" || m === "off" ? m : "";
    }

    /**
     * Mode for a sender label: its installed app's rule ("@<desktop id>",
     * set from that app's Settings row) when the label belongs to one, else
     * a rule on the label itself (scripts, the shell's own senders).
     */
    function modeFor(app) {
        var id = root.labelEntryId(app);
        var m = id.length ? root.validMode(root.appRules["@" + id]) : "";
        if (!m.length) m = root.validMode(root.appRules[app]);
        return m.length ? m : "alert";
    }

    /** Same rule as modeFor, for a Settings app row ({ key, labels }). */
    function rowMode(row) {
        if (!row) return "alert";
        var m = root.validMode(root.appRules[row.key]);
        for (var i = 0; !m.length && i < row.labels.length; i++)
            m = root.validMode(root.appRules[row.labels[i]]);
        return m.length ? m : "alert";
    }

    /** Labels the shell gives senders itself; never an installed app's. */
    readonly property var shellLabels: ["System", "Hyprland", "Screenshot", "astralis"]

    /**
     * The installed app (desktop-entry id) a notification comes from, or "":
     * the desktop-entry hint, else the sender name. A nameless sender only
     * counts when its label IS the hinted app (Ghostty), so a sender named in
     * the text ("Claude" via a terminal) keeps its own row.
     */
    function entryIdOf(n, label) {
        if (!n || root.shellLabels.indexOf(label) !== -1) return "";
        var k = root.kindOf(n);
        if (k === "screenshot" || k === "shell" || k === "recording") return "";
        var e = root.entryFor(n.desktopEntry);
        if (k === "system")
            return e && e.name === label ? e.id : "";
        if (!e) e = root.entryFor(label);
        return e ? e.id : "";
    }

    /** Entry id for a seen label: stored on arrival, else looked up by name (older cache rows). */
    function labelEntryId(label) {
        var kn = root.knownApps[label];
        if (kn && kn.entry !== undefined) return kn.entry;
        if (root.shellLabels.indexOf(label) !== -1) return "";
        var e = root.entryFor(label);
        return e ? e.id : "";
    }

    /** A content image picked up as an icon (hyprshot's shot, as image://icon//path) isn't the app's. */
    function rowIcon(icon) {
        var s = String(icon || "");
        return s.indexOf("image://icon//") === 0 ? "" : s;
    }

    /**
     * The Settings app list: every installed GUI app (a terminal tool
     * notifies as its terminal), each folding in the senders seen from it,
     * plus senders that aren't an installed app (scripts, Screenshot,
     * System). Alphabetical. A row is { key, name, icon, glyph, labels }:
     * key "@<desktop id>" for an app, else the sender label.
     */
    function appRows() {
        var rows = {};
        function addEntry(e) {
            var key = "@" + e.id;
            if (!rows[key])
                rows[key] = { key: key, name: e.name || e.id, icon: e.icon ? Quickshell.iconPath(e.icon, true) : "", glyph: "inbox", labels: [] };
            return rows[key];
        }
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i];
            if (a && !a.noDisplay && !a.runInTerminal) addEntry(a);
        }
        var labels = {};
        for (var l in root.knownApps) labels[l] = true;
        for (var r in root.appRules) if (r.charAt(0) !== "@") labels[r] = true;
        var gs = root.groups;
        for (var g = 0; g < gs.length; g++) if (gs[g].app) labels[gs[g].app] = true;
        for (var lab in labels) {
            var id = root.labelEntryId(lab);
            var e = id.length ? DesktopEntries.byId(id) : null;
            if (e) {
                addEntry(e).labels.push(lab);
                continue;
            }
            var kn = root.knownApps[lab];
            rows[lab] = { key: lab, name: lab, icon: root.rowIcon(kn ? kn.icon : ""), glyph: (kn && kn.glyph) || "inbox", labels: [lab] };
        }
        // A rule on an app since uninstalled keeps its row, so it can be reset.
        for (var rk in root.appRules) {
            if (rk.charAt(0) !== "@" || rows[rk]) continue;
            var ge = DesktopEntries.byId(rk.substring(1));
            if (ge) addEntry(ge);
            else rows[rk] = { key: rk, name: rk.substring(1), icon: "", glyph: "inbox", labels: [] };
        }
        var out = [];
        for (var k in rows) out.push(rows[k]);
        out.sort(function (x, y) {
            return x.name.toLowerCase().localeCompare(y.name.toLowerCase()) || x.key.localeCompare(y.key);
        });
        return out;
    }

    /**
     * Every app that has ever notified (label → { icon, glyph, last }), kept
     * in its own small cache so Settings can list an app after its
     * notifications are long gone — and, above all, so a blocked app (whose
     * notifications never arrive anywhere else) stays listed and can be
     * unblocked. Updated at most once a minute per app.
     */
    property alias knownApps: knownAdapter.apps

    function noteApp(n, app) {
        if (!app || !app.length) return;
        var cur = root.knownApps[app];
        var now = Date.now();
        var icon = root.appIconFor(n);
        if (!icon.length && cur) icon = cur.icon || "";
        var entry = root.entryIdOf(n, app);
        if (cur && cur.icon === icon && cur.entry === entry && now - (cur.last || 0) < 60000) return;
        var m = Object.assign({}, root.knownApps);
        m[app] = { icon: icon, glyph: root.glyphFor(n), entry: entry, last: now };
        root.knownApps = m;
    }

    /** Freedesktop chime via PipeWire (PulseAudio fallback); honours suppress-sound / sound-file / sound-name. */
    function chime(n) {
        if (!root.sound) return;
        var h = (n && n.hints) || {};
        if (h["suppress-sound"]) return;
        var dir = "/usr/share/sounds/freedesktop/stereo/";
        var f = String(h["sound-file"] || "");
        if (f.indexOf("file://") === 0) f = f.substring(7);
        var nm = String(h["sound-name"] || "");
        var fallback = dir + (n.urgency === NotificationUrgency.Critical ? "dialog-warning.oga" : "message.oga");
        var named = /^[\w.-]+$/.test(nm) ? dir + nm + ".oga" : "";
        Quickshell.execDetached(["sh", "-c",
            "f=\"$1\"; [ -f \"$f\" ] || f=\"$2\"; [ -f \"$f\" ] || f=\"$3\"; "
            + "command -v pw-play >/dev/null 2>&1 && exec pw-play \"$f\"; exec paplay \"$f\"",
            "sh", f.indexOf("/") === 0 ? f : "", named, fallback]);
    }

    /** The toast on top is critical: the pill body takes the error material while it shows. */
    readonly property bool topCritical: {
        var p = root.popups;
        var n = p.length > 0 ? p[p.length - 1] : null;
        return !!n && n.urgency === NotificationUrgency.Critical;
    }

    readonly property var tracked: server.trackedNotifications.values
    readonly property int count: tracked.length + history.length

    readonly property int unread: {
        var u = 0;
        for (var i = 0; i < tracked.length; i++)
            if (!seenIds[tracked[i].id]) u++;
        return u;
    }

    /**
     * App-grouped view over tracked + history. Per group: entries sorted
     * newest-first, runs of identical summary/body coalesced into one entry
     * with a count, criticals split out so the surface can pin them on top.
     * Groups themselves sort newest-first by their freshest entry.
     */
    readonly property var groups: {
        var map = {};
        var order = [];
        for (var i = 0; i < tracked.length; i++) {
            var n = tracked[i];
            var app = root.sourceLabel(n);
            if (map[app] === undefined) { map[app] = []; order.push(app); }
            map[app].push({ live: true, n: n, t: arrivalMs[n.id] || 0 });
        }
        for (var j = 0; j < history.length; j++) {
            var h = history[j];
            if (map[h.app] === undefined) { map[h.app] = []; order.push(h.app); }
            map[h.app].push({ live: false, n: h, t: h.ts || 0 });
        }
        function coalesce(list, it) {
            var last = list.length > 0 ? list[list.length - 1] : null;
            if (last && last.n.summary === it.n.summary && last.n.body === it.n.body
                    && last.n.image === it.n.image && last.n.appIcon === it.n.appIcon) {
                last.count++;
                last.items.push(it.n);
            } else {
                list.push({ live: it.live, n: it.n, count: 1, items: [it.n] });
            }
        }
        var gs = order.map(function(app) {
            var items = map[app];
            items.sort(function(a, b) { return b.t - a.t; });
            var criticals = [];
            var entries = [];
            for (var k = 0; k < items.length; k++)
                coalesce(items[k].n.urgency === NotificationUrgency.Critical ? criticals : entries, items[k]);
            var preview = items.find(function(it) { return it.n.urgency !== NotificationUrgency.Critical; });
            return {
                app: app,
                count: items.length,
                t: items[0].t,
                newest: items[0].n,
                preview: preview ? preview.n : items[0].n,
                criticals: criticals,
                entries: entries
            };
        });
        gs.sort(function(a, b) { return b.t - a.t; });
        return gs;
    }

    /**
     * Arrival bookkeeping, called from onNotification after n.tracked = true:
     * stamp arrival + toast deadline, hook the close snapshot, and (DND and
     * criticals permitting) push onto the toast queue.
     */
    /** Body as plain text: senders use markup (we advertise it) but rows render PlainText. */
    function plainBody(b) {
        if (!b) return "";
        return b.replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]*>/g, "")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
            .replace(/&apos;|&#39;/g, "'").replace(/&amp;/g, "&");
    }

    function recordArrival(n) {
        var a = Object.assign({}, root.arrivalMs);
        a[n.id] = Date.now();
        root.arrivalMs = a;
        var e = Object.assign({}, root.expireAt);
        // Screenshots/recordings carry one-click actions: give them time to be
        // used. Otherwise honour a sender's own short timeout (Hyprland's
        // popout asks for 1.5s) and fall back to the urgency default.
        var k = root.kindOf(n);
        var life = n.urgency === NotificationUrgency.Low ? 3000 : 4500;
        // expireTimeout is documented in seconds; guard against a build
        // that hands the raw spec milliseconds through.
        var t = n.expireTimeout;
        if (t > 0)
            life = Math.max(1500, Math.min(10000, t > 100 ? t : t * 1000));
        if (root.popupLength === "short")
            life = Math.max(1500, Math.round(life * 0.6));
        else if (root.popupLength === "long")
            life = Math.round(life * 2);
        if (k === "screenshot" || (k === "recording" && !root.isFailure(n)))
            life = Math.max(life, 8000);
        e[n.id] = Date.now() + life;
        if (k === "screenshot")
            root.probeShot(root.localImage(n));
        root.expireAt = e;
        root.hookClosed(n);
        var critical = n.urgency === NotificationUrgency.Critical;
        // Per-app "silent" goes straight to the centre; quiet (DND or quiet
        // hours) holds everything back except criticals, if those may pass.
        if (root.modeFor(root.sourceLabel(n)) === "alert"
                && (!root.quiet || (critical && root.urgentThrough))) {
            root.popups = root.popups.concat([n]).slice(-3);
            root.chime(n);
        }
        // Deferred: the new arrival only joins trackedNotifications after
        // onNotification returns, so counting now would run one over the cap.
        Qt.callLater(root.boundLive);
    }

    /**
     * Cap on LIVE notifications. Every arrival stays tracked until someone
     * closes it, and a chat app (Discord) rarely does — so a day of unread
     * messages kept hundreds of Notification objects alive, avatar pixels and
     * all. Past the cap, the oldest non-critical ones that aren't on screen as
     * a toast are expire()d: the closed hook snapshots them into `history`
     * (text + icon source, still listed in the center) and the object and
     * its image are released. Same thing mako/dunst do on a timeout.
     */
    readonly property int liveCap: 50

    function boundLive() {
        var live = server.trackedNotifications.values.slice();
        var excess = live.length - root.liveCap;
        if (excess <= 0)
            return;
        live.sort(function(x, y) {
            return (root.arrivalMs[x.id] || 0) - (root.arrivalMs[y.id] || 0);
        });
        for (var i = 0; i < live.length && excess > 0; i++) {
            var o = live[i];
            if (o.urgency === NotificationUrgency.Critical || root.popups.indexOf(o) !== -1)
                continue;
            excess--;
            o.expire();
        }
    }

    // ── kinds ───────────────────────────────────────────────────────────────
    //
    // One cheap, data-only classifier every view reads (works on a live
    // Notification and on a history snapshot, which carries its kind/label/
    // files precomputed at close time):
    //   screenshot — summary/app says screenshot AND the image is a local file
    //   recording  — astralis's own "Recording saved/failed"
    //   shell      — any other astralis notification
    //   system     — no app name (notify-send, GNotification via Ghostty),
    //                or Hyprland
    //   media      — a music/video player (cover art in the image hint)
    //   message    — any other app that ships an image (avatar, favicon)
    //   default    — everything else

    readonly property var mediaRe: /spotify|ncspot|mpd|rhythmbox|elisa|amberol|lollypop|strawberry|cmus|clementine|quodlibet|audacious|deadbeef|tidal|deezer|music|mpv|vlc|celluloid|tauon|feishin|sonixd/
    readonly property var shotAppRe: /hyprshot|screenshot|grim|flameshot|spectacle|satty|swappy|ksnip/

    /** Raw sender name; notify-send's default "notify-send" counts as none. */
    function rawApp(n) {
        var a = String((n && n.appName) || "").trim();
        return a.toLowerCase() === "notify-send" ? "" : a;
    }

    function baseName(p) {
        var str = String(p || "");
        return str.substring(str.lastIndexOf("/") + 1);
    }

    /** A local raster file path (no scheme) or "". */
    function filePathOf(v) {
        var p = String(v || "");
        if (p.indexOf("file://") === 0) {
            p = p.substring(7);
            try { p = decodeURIComponent(p); } catch (err) {}
        }
        return (p.indexOf("/") === 0 && /\.(png|jpe?g|webp|bmp|gif|avif|jxl)$/i.test(p)) ? p : "";
    }

    /** Percent-encoded file:// URL (bare paths would resolve against qrc:, `#` would cut). */
    function fileUrl(p) {
        return p && p.length ? "file://" + p.split("/").map(encodeURIComponent).join("/") : "";
    }

    // Bare paths (hyprshot's `-i /home/…png`) resolve against the QML file's
    // own qrc: URL inside IconImage/Image, so they need an explicit scheme.
    function asUrl(p) {
        return p.indexOf("/") === 0 ? root.fileUrl(p) : p;
    }

    /** The local image file a notification carries (image hint, image-path, or a path app icon). */
    function localImage(n) {
        if (!n) return "";
        if (n.img !== undefined) return n.img;
        var hp = (n.hints && n.hints["image-path"]) || "";
        return root.filePathOf(n.image) || root.filePathOf(hp) || root.filePathOf(n.appIcon);
    }

    function kindOf(n) {
        if (!n) return "default";
        if (n.kind !== undefined) return n.kind;
        var app = root.rawApp(n).toLowerCase();
        var sum = String(n.summary || "").toLowerCase();
        if (root.localImage(n).length && (/screen ?shot|hyprshot/.test(sum) || root.shotAppRe.test(app)))
            return "screenshot";
        if (app === "astralis")
            return /^recording\b/.test(sum) ? "recording" : "shell";
        if (!app.length || app === "hyprland")
            return "system";
        if (root.mediaRe.test(app + " " + String(n.desktopEntry || "").toLowerCase()))
            return "media";
        return root.avatarFor(n).length ? "message" : "default";
    }

    function isFailure(n) {
        return !!n && root.kindOf(n) === "recording"
            && (/fail|error/i.test(String(n.summary || "")) || n.urgency === NotificationUrgency.Critical);
    }

    /** "Backup is running…" / "Build Bot: done" → "Backup" / "Build Bot". */
    function senderOf(text) {
        var m = /^([A-Z][\w.+-]*(?: [A-Z][\w.+-]*){0,2})(?::\s| is | has | wants | needs | says | finished| completed| requires)/
            .exec(root.plainBody(String(text || "")).trim());
        return m ? m[1] : "";
    }

    /**
     * Who a notification is FROM, as the eyebrow/group label. A nameless
     * sender is only "System" when nothing better exists: the sender named in
     * the text (Backup), else the desktop-entry hint's app name (Ghostty).
     */
    function sourceLabel(n) {
        if (!n) return "";
        if (n.label !== undefined) return n.label;
        var k = root.kindOf(n);
        if (k === "screenshot") return "Screenshot";
        if (k === "shell" || k === "recording") return "astralis";
        var app = root.rawApp(n);
        if (k !== "system") return app;
        if (app.toLowerCase() === "hyprland") return "Hyprland";
        var who = root.senderOf(n.summary) || root.senderOf(n.body);
        if (who.length) return who;
        var e = root.entryFor(n.desktopEntry);
        return (e && e.name) ? e.name : "System";
    }

    /** The headline. Screenshots lead with where they came from. */
    function titleFor(n) {
        if (!n) return "";
        if (root.kindOf(n) === "screenshot") {
            var w = root.shotWhere(n);
            return w.length ? w : "Captured";
        }
        return String(n.summary || "");
    }

    /** The secondary line (plain text). */
    function captionFor(n) {
        if (!n) return "";
        var k = root.kindOf(n);
        var b = root.plainBody(n.body).trim();
        if (k === "screenshot") {
            var copied = /clipboard/i.test(b) || root.rawApp(n).length === 0;
            return (copied ? "Copied to clipboard · " : "") + root.baseName(root.localImage(n));
        }
        if (k === "recording" && !root.isFailure(n))
            return root.baseName(root.recordingPath(n));
        return b;
    }

    /** The file a notification's shell actions act on (screenshot / saved recording), else "". */
    function fileOf(n) {
        if (!n) return "";
        if (n.file !== undefined) return n.file;
        var k = root.kindOf(n);
        if (k === "screenshot") return root.localImage(n);
        if (k === "recording" && !root.isFailure(n)) return root.recordingPath(n);
        return "";
    }

    /** ScreenRec's toast body is the basename: resolve it back to the take on disk. */
    function recordingPath(n) {
        var b = root.plainBody(n.body).trim();
        if (b.indexOf("/") === 0) return b;
        var lf = ScreenRec.lastFile;
        if (!b.length || (lf.length && root.baseName(lf) === b)) return lf;
        return ScreenRec.dir + "/" + b;
    }

    // ── screenshot geometry: region / monitor / all monitors ────────────────
    // Hyprshot never says which mode it ran in, so the PNG header (bytes
    // 16..23: big-endian width, height) is read once per shot and matched
    // against the monitors' pixel modes.
    property var shotDims: ({})    // path → [w, h] ([0, 0] when unreadable)
    property var dimQueue: []

    function probeShot(p) {
        if (!p || !p.length || root.shotDims[p] !== undefined || root.dimQueue.indexOf(p) !== -1) return;
        root.dimQueue = root.dimQueue.concat([p]);
        if (!dimProc.running) root.nextProbe();
    }

    function nextProbe() {
        if (dimProc.running) return;
        root.dimQueue = root.dimQueue.filter(function(q) { return root.shotDims[q] === undefined; });
        if (root.dimQueue.length === 0) return;
        dimProc.path = root.dimQueue[0];
        dimProc.command = ["od", "-An", "-tu1", "-j16", "-N8", "--", dimProc.path];
        dimProc.running = true;
    }

    Process {
        id: dimProc
        property string path: ""
        // The next probe can only start once this one has fully exited.
        onRunningChanged: if (!running) Qt.callLater(root.nextProbe)
        stdout: StdioCollector {
            onStreamFinished: {
                var b = text.trim().split(/\s+/).map(Number);
                var d = Object.assign({}, root.shotDims);
                d[dimProc.path] = b.length === 8
                    ? [((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]) >>> 0,
                       ((b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7]) >>> 0]
                    : [0, 0];
                root.shotDims = d;
                root.dimQueue = root.dimQueue.filter(function(q) { return q !== dimProc.path; });
            }
        }
    }

    function shotWhere(n) {
        // The Print bind says it outright ("All monitors").
        var b = root.plainBody(n.body).trim();
        if (b.length && b.length <= 28 && !/[\/<]|clipboard|saved/i.test(b))
            return b.charAt(0).toUpperCase() + b.slice(1);
        var d = root.shotDims[root.localImage(n)];
        if (!d || !(d[0] > 0)) return "";
        var ms = Hyprland.monitors.values;
        var maxW = 0, maxH = 0;
        for (var i = 0; i < ms.length; i++) {
            var m = ms[i];
            var o = m.lastIpcObject || {};
            var w = o.width || m.width, h = o.height || m.height;
            maxW = Math.max(maxW, w, h);
            maxH = Math.max(maxH, w, h);
            if ((w === d[0] && h === d[1]) || (w === d[1] && h === d[0]))
                return ms.length > 1 ? "Monitor · " + m.name : "Full screen";
        }
        if (ms.length > 1 && (d[0] > maxW || d[1] > maxH)) return "All monitors";
        return "Region";
    }

    // ── icons ───────────────────────────────────────────────────────────────

    /** Desktop entry by id / wm class / name, or null. */
    function entryFor(token) {
        var t = String(token || "").trim();
        if (!t.length) return null;
        var e = DesktopEntries.heuristicLookup(t);
        if (e) return e;
        var lt = t.toLowerCase();
        var apps = DesktopEntries.applications.values;
        for (var j = 0; j < apps.length; j++) {
            var a = apps[j];
            if (!a) continue;
            var eid = (a.id || "").toLowerCase();
            var wm = (a.startupClass || "").toLowerCase();
            var nm = (a.name || "").toLowerCase();
            if (wm === lt || nm === lt || (eid.length >= 3 && (eid.indexOf(lt) === 0 || (eid.length >= 4 && lt.indexOf(eid) === 0))))
                return a;
        }
        return null;
    }

    /**
     * The APP's icon (never the content image): a theme icon named by the
     * image hint (image://icon/…, how GNotification senders like Ghostty pass
     * their app icon), the app_icon field, the desktop-entry hint, the app
     * name, then a desktop-entry lookup (spotify ↔ spotify-launcher, "Proton
     * VPN" ↔ proton.vpn.app.gtk) — and for nameless senders, the sender named
     * in the text. A raster path in app_icon is an app icon only when the
     * notification isn't using it as its content (screenshot, avatar).
     * Returns "" when nothing resolves; the views fall back to a glyph.
     */
    function appIconFor(n) {
        if (!n) return "";
        var k = root.kindOf(n);
        var img = String(n.image || "");
        var names = [];
        if (img.indexOf("image://icon/") === 0) names.push(img.substring(13));
        var ai = String(n.appIcon || "");
        if (ai.length) {
            if (root.filePathOf(ai).length) {
                if (k !== "screenshot" && k !== "message" && k !== "media") return root.asUrl(root.filePathOf(ai));
            } else if (ai.indexOf("/") === 0 || ai.indexOf("file://") === 0) {
                return root.asUrl(ai);
            } else {
                names.push(ai);
            }
        }
        var app = root.rawApp(n);
        names.push(n.desktopEntry, app.toLowerCase());
        for (var i = 0; i < names.length; i++) {
            // An image://icon/ payload (or a Players-built icon url) can carry
            // a "?fallback=…" query; looked up whole, "spotify?fallback=…"
            // matches no icon and the tile came out blank.
            var nm = String(names[i] || "").replace(/^image:\/\/icon\//, "").split("?")[0];
            if (!nm.length) continue;
            var p = Quickshell.iconPath(nm, true);
            if (p.length) return p;
        }
        var tokens = [n.desktopEntry, app];
        if (k === "system") tokens.push(root.senderOf(n.summary) || root.senderOf(n.body));
        for (var t = 0; t < tokens.length; t++) {
            var e = root.entryFor(tokens[t]);
            if (e && e.icon) {
                var ip = Quickshell.iconPath(e.icon, true);
                if (ip.length) return ip;
            }
        }
        return "";
    }

    /** Content image (avatar, cover, site icon) as a URL, or "" — never a theme icon. */
    function avatarFor(n) {
        if (!n) return "";
        var img = String(n.image || "");
        if (img.length && img.indexOf("image://icon/") !== 0 && !/\.svg$/i.test(img))
            return root.filePathOf(img).length ? root.fileUrl(root.filePathOf(img)) : img;
        var f = root.localImage(n);
        return f.length ? root.fileUrl(f) : "";
    }

    /** Neutral glyph (pill/lib/glyphs.js) when no icon resolves. */
    function glyphFor(n) {
        var k = root.kindOf(n);
        if (k === "screenshot") return "image";
        if (k === "recording") return "record";
        if (k === "shell") return "sparkles";
        if (k === "media") return "music";
        if (k === "system") return root.rawApp(n).toLowerCase() === "hyprland" ? "app-window" : "cog";
        return "inbox";
    }

    /**
     * Legacy single-source icon (Pill/Dashboard/Link glances): the content
     * image when there is one, else the app icon.
     */
    function iconFor(n) {
        var a = root.avatarFor(n);
        return a.length ? a : root.appIconFor(n);
    }

    // ── shell-run actions (each path its own argv element, never spliced) ───

    function openFile(p) {
        if (p && p.length) Quickshell.execDetached(["xdg-open", p]);
    }

    function copyImage(p) {
        if (!p || !p.length) return;
        var mime = /\.jpe?g$/i.test(p) ? "image/jpeg" : /\.webp$/i.test(p) ? "image/webp" : "image/png";
        Quickshell.execDetached(["sh", "-c", "wl-copy --type \"$2\" < \"$1\"", "sh", p, mime]);
    }

    /** Ask a FileManager1 service to select the file; else open its folder. */
    function showInFolder(p) {
        if (!p || p.indexOf("/") !== 0) return;
        var dir = p.substring(0, p.lastIndexOf("/")) || "/";
        var uri = root.fileUrl(p).replace(/'/g, "%27");
        Quickshell.execDetached(["sh", "-c",
            "gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 --method org.freedesktop.FileManager1.ShowItems \"['$1']\" '' >/dev/null 2>&1 || xdg-open \"$2\"",
            "sh", uri, dir]);
    }

    /** Move one regular file to the trash (rm only if there's no trash). */
    function trashFile(p) {
        if (!p || p.indexOf("/") !== 0) return;
        Quickshell.execDetached(["sh", "-c",
            "[ -f \"$1\" ] || exit 0; gio trash -- \"$1\" 2>/dev/null || rm -f -- \"$1\"", "sh", p]);
    }

    /** Dismiss one notification (live or history snapshot) without re-listing it. */
    function dismissNotif(n) {
        if (!n) return;
        root.removePopup(n);
        if (typeof n.dismiss === "function") {
            var d = Object.assign({}, root.userDismissed);
            d[n.id] = true;
            root.userDismissed = d;
            n.dismiss();
        } else {
            root.history = root.history.filter(function(h) { return h.id !== n.id; });
        }
    }

    /**
     * Retire a toast. The notification stays tracked (it still counts as
     * unread and shows in the center); it only moves to `history` when it is
     * actually closed/dismissed (hookClosed snapshots it there).
     */
    function dropInterruptedPopups() {
        root.popups = root.popups.filter(function(p) {
            return p && p.urgency === NotificationUrgency.Critical;
        });
    }

    function removePopup(n) {
        root.popups = root.popups.filter(function(p) { return p && p !== n; });
    }

    /** Focus the source app's Hyprland window by class match. */
    function raiseWindow(n) {
        if (!n) return;
        var token = String(n.desktopEntry && n.desktopEntry.length ? n.desktopEntry : (n.appName || "")).toLowerCase();
        if (token.length === 0) return;
        Quickshell.execDetached(["sh", "-c",
            "addr=$(hyprctl clients -j | jq -r --arg q \"$1\" 'first(.[] | select(((.class | if . then ascii_downcase else \"\" end) | contains($q)) or ((.initialClass | if . then ascii_downcase else \"\" end) | contains($q))) | .address)'); [ -n \"$addr\" ] && [ \"$addr\" != \"null\" ] && hyprctl dispatch focuswindow \"address:$addr\"",
            "sh", token]);
    }

    /**
     * Open the app behind a notification: invoke its default action when
     * present (else expire it), then jump to the app's window — stock
     * notification-center behavior.
     */
    function activateNotif(n) {
        if (!n) return;
        var acts = n.actions || [];
        // A screenshot or saved take with no sender action opens its file.
        var own = root.fileOf(n);
        if (own.length && acts.length === 0) {
            root.openFile(own);
            if (typeof n.expire === "function") n.expire();
            return;
        }
        var invoked = false;
        for (var i = 0; i < acts.length; i++) {
            if (acts[i].identifier === "default") {
                acts[i].invoke();
                invoked = true;
                break;
            }
        }
        // The freedesktop spec never requires a literal "default" action —
        // it names the ONE action a click on the notification BODY should
        // run, and plenty of senders (hyprshot's "View" among them) ship a
        // single named action and expect exactly that convention: the first
        // (only) action is what clicking the body means. Falling straight
        // to expire() when there was no "default" silently dropped it —
        // clicking the row did nothing an app author had actually wired up.
        if (!invoked && acts.length > 0) {
            acts[0].invoke();
            invoked = true;
        }
        if (!invoked && typeof n.expire === "function")
            n.expire();
        raiseWindow(n);
    }

    /** Center-row entry wrapper: activate the app, then dismiss the entry. */
    function activateEntry(e) {
        if (!e || !e.n) return;
        activateNotif(e.n);
        dismissEntry(e);
    }

    /** Dismiss one coalesced entry (all notifications folded into it). */
    function dismissEntry(e) {
        if (!e || !e.items) return;
        var d = Object.assign({}, userDismissed);
        var gone = {};
        var live = [];
        for (var i = 0; i < e.items.length; i++) {
            var n = e.items[i];
            if (typeof n.dismiss === "function") {
                d[n.id] = true;
                live.push(n);
            } else {
                gone[n.id] = true;
            }
        }
        root.userDismissed = d;
        for (var j = 0; j < live.length; j++) live[j].dismiss();
        root.history = root.history.filter(function(h) { return !gone[h.id]; });
    }

    /** Clear one app's group: live notifications and history rows both. */
    function dismissApp(app) {
        var doomed = tracked.filter(function(n) {
            return root.sourceLabel(n) === app;
        });
        var d = Object.assign({}, userDismissed);
        for (var i = 0; i < doomed.length; i++) d[doomed[i].id] = true;
        root.userDismissed = d;
        for (var j = 0; j < doomed.length; j++) doomed[j].dismiss();
        root.history = root.history.filter(function(h) { return h.app !== app; });
    }

    /** Opening the center marks everything currently tracked as seen. */
    function markSeen() {
        var m = {};
        for (var i = 0; i < tracked.length; i++) m[tracked[i].id] = true;
        root.seenIds = m;
    }

    function clearAll() {
        var l = tracked.slice();
        var d = Object.assign({}, userDismissed);
        for (var i = 0; i < l.length; i++) d[l[i].id] = true;
        root.userDismissed = d;
        for (var j = 0; j < l.length; j++) l[j].dismiss();
        root.history = [];
        root.popups = [];
    }

    function toggleExpanded(app) {
        var e = Object.assign({}, expandedApps);
        e[app] = e[app] !== true;
        root.expandedApps = e;
    }

    /**
     * Bind the history-snapshot handler to a notification's `closed` signal
     * once. `keepOnReload` re-runs Component.onCompleted on every QS reload over
     * the still-tracked notifications, so the id set gates re-hooks WITHIN a
     * singleton instance: without it each Component.onCompleted would stack
     * another handler and a single close would push duplicate history rows. The
     * id is cleared inside the handler so a later notification reusing the id
     * re-hooks cleanly. Across a hot-reload the surviving (keepOnReload)
     * notification would otherwise also retain the PREVIOUS singleton's closure,
     * so the connection is made with `root` as its receiver: when the old
     * singleton is torn down on reload Qt auto-disconnects that stale closure,
     * leaving only the live instance's handler (no accumulation, no double-fire).
     */
    function hookClosed(n) {
        // Also reached for notifications re-emitted after a hot reload.
        if (root.kindOf(n) === "screenshot")
            root.probeShot(root.localImage(n));
        if (root.hookedIds[n.id])
            return;
        var hooked = Object.assign({}, root.hookedIds);
        hooked[n.id] = true;
        root.hookedIds = hooked;
        n.closed.connect(root, function(reason) {
            if (!root.userDismissed[n.id])
                root.history = [{
                    app: root.sourceLabel(n),
                    label: root.sourceLabel(n),
                    kind: root.kindOf(n),
                    img: root.localImage(n),
                    file: root.fileOf(n),
                    appName: n.appName,
                    summary: n.summary,
                    body: n.body,
                    appIcon: n.appIcon,
                    desktopEntry: n.desktopEntry,
                    image: n.image,
                    urgency: n.urgency,
                    ts: root.arrivalMs[n.id] || Date.now(),
                    id: "h" + n.id + "-" + Date.now()
                }].concat(root.history).slice(0, 50);
            else {
                var du = Object.assign({}, root.userDismissed);
                delete du[n.id];
                root.userDismissed = du;
            }
            root.removePopup(n);
            var b = Object.assign({}, root.arrivalMs);
            delete b[n.id];
            root.arrivalMs = b;
            var c = Object.assign({}, root.expireAt);
            delete c[n.id];
            root.expireAt = c;
            var h = Object.assign({}, root.hookedIds);
            delete h[n.id];
            root.hookedIds = h;
        });
    }

    /** "now" / "12m" / "3h" — refreshed by the 30s tick. */
    function ageLabel(n) {
        void root.tick;
        var t = arrivalMs[n.id] || n.ts;
        if (!t) return "";
        var m = Math.floor((Date.now() - t) / 60000);
        if (m < 1) return "now";
        if (m < 60) return m + "m";
        return Math.floor(m / 60) + "h";
    }

    Timer {
        interval: 30000
        running: root.count > 0
        repeat: true
        onTriggered: root.tick++
    }

    /**
     * Highest notification id ever handled, kept across hot reloads. The
     * server re-emits everything it still tracks after a reload (not always
     * with `tracked` set), and ids only ever grow, so anything at or below
     * this was already seen and must not toast again.
     */
    PersistentProperties {
        id: persist
        reloadableId: "astralis-notifications"
        property int lastId: 0
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        actionIconsSupported: true

        /**
         * keepOnReload carries tracked notifications across a QS hot-reload,
         * but this singleton's maps start empty: re-stamp arrivals (so
         * grouping/ageLabel keep working) and re-hook `closed` for each.
         */
        Component.onCompleted: {
            var l = trackedNotifications.values;
            var a = Object.assign({}, root.arrivalMs);
            for (var i = 0; i < l.length; i++) {
                if (!a[l[i].id]) a[l[i].id] = Date.now();
                root.hookClosed(l[i]);
            }
            root.arrivalMs = a;
        }

        onNotification: function(n) {
            // keepOnReload re-emits every still-tracked notification after a
            // hot reload. Those are already tracked: re-hook and keep their
            // age, but never toast them again (they'd pop on every reload).
            if (n.tracked || n.id <= persist.lastId) {
                n.tracked = true;
                if (!root.arrivalMs[n.id]) {
                    var a = Object.assign({}, root.arrivalMs);
                    a[n.id] = Date.now();
                    root.arrivalMs = a;
                }
                root.hookClosed(n);
                return;
            }
            persist.lastId = Math.max(persist.lastId, n.id);
            var app = root.sourceLabel(n);
            root.noteApp(n, app);
            // Blocked app: never tracked, so the server drops it on the spot —
            // no toast, no centre row, no unread dot.
            if (root.modeFor(app) === "off")
                return;
            n.tracked = true;
            root.recordArrival(n);
        }
    }

    // Seen-apps cache (see knownApps). Writes only after a clean read, so a
    // torn or hand-broken file is left alone instead of being reset.
    property bool knownWritable: false
    FileView {
        id: knownFile
        path: Quickshell.env("HOME") + "/.cache/astralis/notif-apps.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onAdapterUpdated: if (root.knownWritable) writeAdapter()
        onLoaded: {
            var t = String(text() || "").trim();
            var ok = true;
            if (t.length) {
                try { var o = JSON.parse(t); ok = o !== null && typeof o === "object" && !Array.isArray(o); }
                catch (err) { ok = false; }
            }
            root.knownWritable = ok;
        }
        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound) {
                root.knownWritable = true;
                Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.cache/astralis"]);
            }
        }

        JsonAdapter {
            id: knownAdapter
            property var apps: ({})
        }
    }
}
