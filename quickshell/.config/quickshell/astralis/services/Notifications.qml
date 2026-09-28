pragma Singleton

import QtQuick
import Quickshell
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
            var app = (n.appName && n.appName.length) ? n.appName : "System";
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
            if (last && last.n.summary === it.n.summary && last.n.body === it.n.body) {
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
    function recordArrival(n) {
        var a = Object.assign({}, root.arrivalMs);
        a[n.id] = Date.now();
        root.arrivalMs = a;
        var e = Object.assign({}, root.expireAt);
        e[n.id] = Date.now() + (n.urgency === NotificationUrgency.Low ? 4000 : 6000);
        root.expireAt = e;
        root.hookClosed(n);
        var critical = n.urgency === NotificationUrgency.Critical;
        if (!root.dnd || critical)
            root.popups = root.popups.concat([n]).slice(-3);
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

    /**
     * Best icon source for a notification (live or history snapshot):
     * image://icon/ payloads resolve through the theme, raster image paths
     * pass through, then appIcon/desktopEntry/appName try the icon theme.
     */
    function iconFor(n) {
        if (!n) return "";
        var img = n.image || "";
        var names = [];
        if (img.indexOf("image://icon/") === 0) {
            names.push(img.substring(13));
        } else if (img.length && !/\.svg$/i.test(img)) {
            return img;
        }
        names.push(n.appIcon, n.desktopEntry, (n.appName || n.app || "").toLowerCase());
        for (var i = 0; i < names.length; i++) {
            var nm = names[i];
            if (!nm || !nm.length) continue;
            if (nm.indexOf("/") === 0 || nm.indexOf("file://") === 0) return nm;
            var p = Quickshell.iconPath(nm, true);
            if (p.length) return p;
        }
        // Fuzzy desktop-entry fallback for launcher-wrapped apps that report one
        // name but install another (MPRIS/notify "spotify" ↔ spotify-launcher
        // .desktop, StartupWMClass spotify). Match a shared id prefix or the
        // entry's startup window class.
        var token = String(n.desktopEntry && n.desktopEntry.length ? n.desktopEntry : (n.appName || n.app || "")).toLowerCase();
        if (token.length) {
            var apps = DesktopEntries.applications.values;
            for (var j = 0; j < apps.length; j++) {
                var e = apps[j];
                if (!e || !e.icon) continue;
                var eid = (e.id || "").toLowerCase();
                var wm = (e.startupClass || "").toLowerCase();
                if (wm === token || (eid.length && (eid.indexOf(token) === 0 || token.indexOf(eid) === 0))) {
                    var ip = Quickshell.iconPath(e.icon, true);
                    if (ip.length) return ip;
                }
            }
        }
        return "";
    }

    /**
     * Retire a toast. The notification stays tracked (it still counts as
     * unread and shows in the center); it only moves to `history` when it is
     * actually closed/dismissed (hookClosed snapshots it there).
     */
    function removePopup(n) {
        root.popups = root.popups.filter(function(p) { return p !== n; });
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
            return ((n.appName && n.appName.length) ? n.appName : "System") === app;
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
        if (root.hookedIds[n.id])
            return;
        var hooked = Object.assign({}, root.hookedIds);
        hooked[n.id] = true;
        root.hookedIds = hooked;
        n.closed.connect(root, function(reason) {
            if (!root.userDismissed[n.id])
                root.history = [{
                    app: (n.appName && n.appName.length) ? n.appName : "System",
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
            n.tracked = true;
            root.recordArrival(n);
        }
    }
}
