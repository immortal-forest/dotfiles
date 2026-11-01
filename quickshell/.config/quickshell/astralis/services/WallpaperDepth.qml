pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — wallpaper depth: cuts the wallpaper's FOREGROUND out so a desktop
 * widget (modules/depth/DepthClock.qml) can sit behind near objects in the
 * scene. Same idea as Noctalia's wallpaper_depth plugin.
 *
 * Pipeline: scripts/depth/depth.py runs Depth Anything V2 Small (ONNX, CPU,
 * ~5 s first time per wallpaper, depth map cached) and writes an RGBA PNG of
 * the scene in front of `threshold`, pre-cropped to each screen exactly like
 * skwd-paper's `fill`. scripts/depth/setup installs the venv + model once
 * (~140 MB) into ~/.local/share/astralis/depth, on first use.
 *
 * Widgets call want("WxH") with their screen's physical size and read
 * cutout(size); a wallpaper change clears every cut-out at once (the old one
 * would no longer line up) and regenerates them in one serial queue.
 */
Singleton {
    id: root

    readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/astralis/depth"
    readonly property string scripts: Quickshell.shellDir + "/scripts/depth"

    readonly property string wallpaper: Wallpaper.current
    readonly property real threshold: Widgets.depth.threshold
    readonly property real feather: Widgets.depth.feather

    /** "idle" | "setup" | "working" | "error" */
    property string status: "idle"
    property string error: ""
    property bool ready: false

    /** size "WxH" → cut-out file path ("" until generated). */
    property var paths: ({})
    property var sizes: []
    function cutout(size) { return root.paths[size] ?? ""; }

    function want(size) {
        if (root.sizes.indexOf(size) < 0)
            root.sizes = root.sizes.concat([size]);
        if (!root.paths[size])
            root.queue(size);
    }

    function regenerate() {
        root.paths = ({});
        root.pending = [];
        root.sizes.forEach(s => root.queue(s));
    }

    onWallpaperChanged: regenerate()
    onThresholdChanged: tuneDebounce.restart()
    onFeatherChanged: tuneDebounce.restart()
    Timer {
        id: tuneDebounce
        interval: 350
        // Keep the old cut-out on screen while re-thresholding (same wallpaper, still aligned).
        onTriggered: { root.pending = []; root.sizes.forEach(s => root.queue(s)); }
    }

    // ── serial job queue ──────────────────────────────────────────────────
    property var pending: []
    function queue(size) {
        if (root.pending.indexOf(size) < 0)
            root.pending = root.pending.concat([size]);
        root.pump();
    }
    function pump() {
        if (probe.running || gen.running || setup.running || root.pending.length === 0 || !root.wallpaper.length)
            return;
        if (!root.ready) {
            root.status = "setup";
            setup.running = true;
            return;
        }
        var size = root.pending[0];
        root.pending = root.pending.slice(1);
        gen.size = size;
        gen.wall = root.wallpaper;
        gen.command = [root.dataDir + "/venv/bin/python", "-I", root.scripts + "/depth.py",
            "--data-dir", root.dataDir, "--wallpaper", root.wallpaper, "--size", size,
            "--threshold", String(root.threshold), "--feather", String(root.feather)];
        root.status = "working";
        gen.running = true;
    }

    Process {
        id: gen
        property string size: ""
        property string wall: ""
        stdout: StdioCollector { id: genOut }
        stderr: StdioCollector { id: genErr }
        onExited: function (code) {
            if (code === 0 && gen.wall === root.wallpaper) {
                try {
                    var r = JSON.parse(genOut.text.trim().split("\n").pop());
                    var p = Object.assign({}, root.paths);
                    p[gen.size] = r.path;
                    root.paths = p;
                    root.error = "";
                } catch (e) {
                    root.error = "bad output: " + genOut.text;
                }
            } else if (code !== 0) {
                root.error = genErr.text.trim();
                console.warn("astralis WallpaperDepth:", root.error);
            }
            root.status = root.error.length ? "error" : "idle";
            root.pump();
        }
    }

    Process {
        id: setup
        command: [root.scripts + "/setup"]
        stderr: StdioCollector { id: setupErr }
        onExited: function (code) {
            root.ready = code === 0;
            if (!root.ready) {
                root.status = "error";
                root.error = "setup failed: " + setupErr.text.trim().split("\n").pop();
                console.warn("astralis WallpaperDepth:", root.error);
                root.pending = [];
                return;
            }
            root.pump();
        }
    }

    // Already installed? (venv python + model on disk) — skip setup if so.
    Process {
        id: probe
        running: true
        command: ["sh", "-c", 'test -x "$1/venv/bin/python" && test -s "$1/model.onnx"', "_", root.dataDir]
        onExited: function (code) {
            root.ready = code === 0;
            root.pump();
        }
    }
}
