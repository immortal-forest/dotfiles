pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — desktop-widget layout + options (cover art, lyrics), persisted
 * to ~/.cache/astralis/widgets.json.
 *
 * Geometry is stored as fractions of the screen (x, y, w, h ∈ 0..1) so a
 * layout survives scale and resolution changes; the cover is square, its
 * side = w × screen width. `editing` opens the full-screen placer
 * (modules/nowplaying/WidgetEditor.qml) on every screen.
 *
 * Same write guard as Flags: never overwrite a file we could not parse.
 */
Singleton {
    id: root

    readonly property var defaults: ({
        grid: 24,
        cover: { on: true, x: 0.045, y: 0.29, w: 0.16, radius: 1, halo: true, caption: true },
        lyrics: { on: true, x: 0.27, y: 0.2, w: 0.45, h: 0.6, size: 38, align: "left", glow: true, blur: true, backdrop: "off" }
    })

    property var data: JSON.parse(JSON.stringify(defaults))
    readonly property var cover: data.cover
    readonly property var lyrics: data.lyrics
    /** Snap-grid columns (rows follow the screen aspect); 0 = free. */
    readonly property int grid: data.grid

    /** Placer open (not persisted). */
    property bool editing: false

    function set(widget, keyOrObj, value) {
        var d = JSON.parse(JSON.stringify(root.data));
        if (widget === "grid")
            d.grid = keyOrObj;
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
        ["cover", "lyrics"].forEach(function (w) {
            var keep = Object.assign({}, root.data[w]);
            ["x", "y", "w", "h"].forEach(k => delete keep[k]);
            Object.assign(d[w], keep);
        });
        d.grid = root.data.grid;
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
            ["cover", "lyrics"].forEach(function (w) {
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
