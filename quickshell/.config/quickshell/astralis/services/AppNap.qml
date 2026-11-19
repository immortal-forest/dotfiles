pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * astralis — mirror of appnap's state (~/.local/bin/appnap, Super+Ctrl+M):
 * which windows parked on special:minimized belong to a napped app, i.e.
 * frozen with its RAM pushed to swap. appnap does all the freezing and thaws
 * an app by itself the moment its window leaves special:minimized, so a plain
 * restore (MinimizedTray chip, Super+Shift+M) needs nothing from here.
 *
 * Also the auto-nap clock (Settings → App nap, Flags.napAutoMin): one sweep
 * every 30 s while it's on asks appnap to nap any window that has sat in the
 * minimized tray that long. appnap itself decides whether it may (excluded
 * class, audio playing, a window of the app still out); a refused window's
 * clock restarts, so it's asked again a full period later, not every sweep.
 */
Singleton {
    id: root

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/appnap"

    /** "0x…" window address → { cls, kind, freed (bytes), since (epoch s) }. */
    property var windows: ({})
    readonly property int count: Object.keys(windows).length

    function norm(address) {
        var a = String(address || "");
        return a.indexOf("0x") === 0 ? a : "0x" + a;
    }
    function isNapped(address) {
        return root.windows[root.norm(address)] !== undefined;
    }
    function info(address) {
        return root.windows[root.norm(address)] || null;
    }
    /** Freeze a minimized window's app where it is (it stays on special:minimized). */
    function nap(address) {
        Quickshell.execDetached([root.bin, "nap", root.norm(address)]);
    }
    /** Thaw it where it is: still minimized, just running again. */
    function wake(address) {
        Quickshell.execDetached([root.bin, "wake", root.norm(address)]);
    }
    function toggle(address) {
        if (root.isNapped(address))
            root.wake(address);
        else
            root.nap(address);
    }
    function wakeAll() {
        Quickshell.execDetached([root.bin, "wake-all"]);
    }

    /** A toplevel's window class (what appnap and Flags.napNever key on). */
    function classOf(t) {
        if (!t)
            return "";
        if (t.lastIpcObject && t.lastIpcObject["class"])
            return t.lastIpcObject["class"];
        return (t.wayland && t.wayland.appId) ? t.wayland.appId : "";
    }

    /** Display name + icon for a window class, from its desktop entry when one matches. */
    function appMeta(cls) {
        var c = String(cls || "");
        var lc = c.toLowerCase();
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            if (!e || !e.id)
                continue;
            if (e.id.toLowerCase() === lc || (e.startupClass && String(e.startupClass).toLowerCase() === lc))
                return {
                    name: e.name || c,
                    icon: (e.icon && Quickshell.iconPath(e.icon, true)) || Quickshell.iconPath(lc, true) || ""
                };
        }
        return { name: c, icon: Quickshell.iconPath(lc, true) || "" };
    }

    function _parse(txt) {
        var out = {};
        try {
            var naps = JSON.parse(txt).naps || {};
            for (var key in naps) {
                var n = naps[key];
                for (var a in n.windows)
                    out[a] = { cls: n["class"], kind: n.kind, freed: n.freed || 0, since: n.since || 0 };
            }
        } catch (e) {
            // Half-written or foreign file: treat as nothing napped until the next write.
        }
        root.windows = out;
    }

    // appnap replaces this file atomically on every change; FileView follows
    // creation, rewrites and replacement (verified), and it lives in the runtime
    // dir, so it's gone after logout along with the frozen apps.
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/appnap.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._parse(text())
        onLoadFailed: root.windows = ({})
    }

    // ── auto-nap ─────────────────────────────────────────────────────────────
    /**
     * Window address → ms timestamp it was first seen minimized (and un-napped).
     * Kept across hot reloads: any astralis file edit reloads the shell, and a
     * clock that restarts on each one never reaches the delay (seen in testing).
     * Held as JSON text: a `var` object comes back undefined after a reload
     * (verified), a string survives.
     */
    PersistentProperties {
        id: persist
        reloadableId: "astralis-appnap"
        property string minSince: "{}"
    }

    function _sweep() {
        var now = Date.now();
        var limit = Flags.napAutoMin * 60000;
        var seen = {};
        var prev = {};
        try {
            prev = JSON.parse(persist.minSince) || {};
        } catch (e) {}
        var tl = Hyprland.toplevels.values;
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            if (!t || !t.workspace || t.workspace.name !== "special:minimized")
                continue;
            var a = root.norm(t.address);
            if (root.isNapped(a))
                continue;
            var since = prev[a] !== undefined ? prev[a] : now;
            if (now - since >= limit) {
                Quickshell.execDetached([root.bin, "nap", a, "--auto"]);
                since = now;
            }
            seen[a] = since;
        }
        persist.minSince = JSON.stringify(seen);
    }

    // No triggeredOnStart: after a reload the first sweep must come after
    // PersistentProperties has handed the old clock back.
    Timer {
        interval: 30000
        repeat: true
        running: Flags.napAutoMin > 0
        onTriggered: root._sweep()
        onRunningChanged: if (!running) persist.minSince = "{}"
    }
}
