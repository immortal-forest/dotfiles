import QtQuick
import Quickshell
import Quickshell.Io
import "../../services"

/**
 * astralis — wallpaper-depth desktop widgets: one DepthClock per screen on the
 * Bottom layer. Options live in Widgets.depth (~/.cache/astralis/widgets.json);
 * place/resize it in the widget placer (`ipc call desktop edit`), style it in
 * Settings › Widgets. shell.qml only instantiates `Depth {}`.
 *
 *   qs -c astralis ipc call depth toggle
 *   qs -c astralis ipc call depth move 0.33 0.12      # top-left, screen fractions
 *   qs -c astralis ipc call depth resize 0.34 0.3     # box, screen fractions
 *   qs -c astralis ipc call depth threshold 0.3       # lower = more scene in front
 *   qs -c astralis ipc call depth status
 */
Scope {
    IpcHandler {
        target: "depth"
        function toggle(): void { Widgets.set("depth", "on", !Widgets.depth.on); }
        function move(x: real, y: real): void { Widgets.set("depth", { x: x, y: y }); }
        function resize(w: real, h: real): void { Widgets.set("depth", { w: w, h: h }); }
        function threshold(v: real): void { Widgets.set("depth", "threshold", v); }
        function feather(v: real): void { Widgets.set("depth", "feather", v); }
        function date(): void { Widgets.set("depth", "date", !Widgets.depth.date); }
        function regenerate(): void { WallpaperDepth.regenerate(); }
        function status(): string {
            return "status: " + WallpaperDepth.status + (WallpaperDepth.error ? " (" + WallpaperDepth.error + ")" : "")
                + "\nwallpaper: " + WallpaperDepth.wallpaper
                + "\ncut-outs: " + JSON.stringify(WallpaperDepth.paths)
                + "\nconfig: " + JSON.stringify(Widgets.depth);
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: per
            required property var modelData
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1

            Loader {
                active: Widgets.depth.on
                sourceComponent: DepthClock {
                    screen: per.modelData
                    s: per.s
                    sw: per.modelData.width
                    sh: per.modelData.height
                }
            }
        }
    }
}
