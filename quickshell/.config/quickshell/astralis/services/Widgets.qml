pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — desktop-widget layout + options (cover art, lyrics, depth clock), persisted
 * to ~/.cache/astralis/widgets.json.
 *
 * Geometry is stored as fractions of the screen (x, y, w, h ∈ 0..1) so a
 * layout survives scale and resolution changes; the cover is square, its
 * side = w × screen width. Lyrics options: size (px), lines (shown each side
 * of the current one; 0 = as many as fit), spacing (line-gap
 * multiplier), anchor (current line's height fraction), align left|center|right,
 * ink cover|theme|mono (lit-text gradient), roman off|below|replace, offset (s, + = lyrics earlier), fill sweep|line. `editing` opens the full-screen placer
 * (modules/nowplaying/WidgetEditor.qml) on every screen.
 *
 * Same write guard as Flags: never overwrite a file we could not parse.
 */
Singleton {
    id: root

    readonly property var defaults: ({
        grid: 24,
        avoid: true,
        cover: { on: true, x: 0.045, y: 0.29, w: 0.16, radius: 1, halo: true, caption: true },
        lyrics: { on: true, x: 0.27, y: 0.2, w: 0.45, h: 0.6, size: 38, spacing: 1, anchor: 0.42, lines: 0, align: "left",
                  ink: "cover", glow: true, blur: true, backdrop: "off", roman: "off", offset: 0, fill: "sweep" },
        // Depth clock: a box like the others (x, y = top-left, w, h as screen fractions; the
        // numerals auto-fit it). cut = the wallpaper-depth cut-out over it; threshold/feather
        // drive that cut-out (services/WallpaperDepth.qml). color = a Colors role name.
        depth: { on: true, x: 0.33, y: 0.17, w: 0.34, h: 0.22, date: true, align: "center",
                 color: "primary", weight: 700, opacity: 1, shadow: true,
                 cut: true, threshold: 0.3, feather: 0.08 }
    })

    property var data: JSON.parse(JSON.stringify(defaults))
    readonly property var cover: data.cover
    readonly property var lyrics: data.lyrics
    readonly property var depth: data.depth
    /** Snap-grid columns (rows follow the screen aspect); 0 = free. */
    readonly property int grid: data.grid
    /** Placer anti-collision: frames slide around / stop at each other instead of overlapping. */
    readonly property bool avoid: data.avoid

    /** Placer open (not persisted). */
    property bool editing: false

    /** Settings page the settings window should land on next time it opens. */
    property string pendingPage: ""
    /** Asks the shell to open the settings window (NowPlaying relays it). */
    signal settingsRequested()
    function openSettings() {
        root.editing = false;
        root.pendingPage = "widgets";
        root.settingsRequested();
    }

    function set(widget, keyOrObj, value) {
        var d = JSON.parse(JSON.stringify(root.data));
        if (widget === "grid")
            d.grid = keyOrObj;
        else if (widget === "avoid")
            d.avoid = keyOrObj;
        else if (typeof keyOrObj === "object")
            Object.assign(d[widget], keyOrObj);
        else
            d[widget][keyOrObj] = value;
        root.data = d;
        saveTimer.restart();
    }

    function reset() {
        var d = JSON.parse(JSON.stringify(root.defaults));
        // keep on/off + options, reset only geometry
        ["cover", "lyrics", "depth"].forEach(function (w) {
            var keep = Object.assign({}, root.data[w]);
            ["x", "y", "w", "h"].forEach(k => delete keep[k]);
            Object.assign(d[w], keep);
        });
        d.grid = root.data.grid;
        d.avoid = root.data.avoid;
        root.data = d;
        saveTimer.restart();
    }

    // ── persistence ───────────────────────────────────────────────────────
    property bool writable: false
    readonly property string path: Quickshell.env("HOME") + "/.cache/astralis/widgets.json"

    function merge(o) {
        var d = JSON.parse(JSON.stringify(root.defaults));
        if (o && typeof o === "object") {
            if (typeof o.grid === "number")
                d.grid = o.grid;
            if (typeof o.avoid === "boolean")
                d.avoid = o.avoid;
            ["cover", "lyrics", "depth"].forEach(function (w) {
                if (o[w] && typeof o[w] === "object")
                    Object.keys(d[w]).forEach(function (k) {
                        if (o[w][k] !== undefined && typeof o[w][k] === typeof d[w][k])
                            d[w][k] = o[w][k];
                    });
            });
        }
        return d;
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: if (root.writable) file.setText(JSON.stringify(root.data, null, 2) + "\n")
    }

    FileView {
        id: file
        path: root.path
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            var t = String(text()).trim();
            if (t.length === 0) {
                root.writable = true;
                return;
            }
            try {
                var o = JSON.parse(t);
                if (JSON.stringify(root.merge(o)) !== JSON.stringify(root.data))
                    root.data = root.merge(o);
                root.writable = true;
            } catch (e) {
                console.warn("astralis Widgets: widgets.json did not parse — holding writes.");
                root.writable = false;
            }
        }
        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound)
                root.writable = true;
        }
    }
    Component.onCompleted: mkdir.running = true
    Process {
        id: mkdir
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.cache/astralis"]
        onExited: file.reload()
    }
}
