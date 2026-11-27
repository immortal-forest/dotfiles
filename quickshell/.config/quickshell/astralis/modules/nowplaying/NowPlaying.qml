import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../../services"

/**
 * astralis — desktop music widgets: the cover-art widget (CoverArt) and the
 * synced-lyrics widget (LyricsView), one of each per screen on the Bottom
 * layer (above the wallpaper, under every window). Placement and options
 * live in services/Widgets.qml (Settings › Widgets; "Edit layout" opens the
 * WidgetEditor placer). Self-contained: shell.qml only instantiates
 * `NowPlaying {}`.
 *
 *   qs -c astralis ipc call desktop edit      # open / close the placer
 *   qs -c astralis ipc call desktop cover     # toggle cover widget
 *   qs -c astralis ipc call desktop lyrics    # toggle lyrics widget
 *   qs -c astralis ipc call desktop nextArt   # next alternate cover
 *   qs -c astralis ipc call desktop prevArt
 *   qs -c astralis ipc call desktop status
 */
Scope {
    id: root

    /** Wire in shell.qml: `NowPlaying { onRequestSettings: root.settingsOpen = true }` */
    signal requestSettings()
    Connections {
        target: Widgets
        function onSettingsRequested() { root.requestSettings(); }
    }

    /** WlrLayer.Bottom = on the desktop under windows (the default). */
    property int layer: WlrLayer.Bottom

    IpcHandler {
        target: "desktop"
        function edit(): void { Widgets.editing = !Widgets.editing; }
        function settings(): void { Widgets.openSettings(); }
        function cover(): void { Widgets.set("cover", "on", !Widgets.cover.on); }
        function lyrics(): void { Widgets.set("lyrics", "on", !Widgets.lyrics.on); }
        function nextArt(): void { TrackInfo.next(); }
        function prevArt(): void { TrackInfo.prev(); }
        function status(): string {
            return "track: " + TrackInfo.key + "\ncovers: " + TrackInfo.count + " (showing " + (TrackInfo.index + 1)
                + ", " + TrackInfo.coverSource + ")\nlyrics: " + Lyrics.status + " (" + Lyrics.lines.length + " lines)";
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: per
            required property var modelData
            readonly property real s: modelData ? Flags.scaleFor(modelData) : 1

            readonly property var hMonitor: {
                var mons = Hyprland.monitors.values;
                for (var i = 0; i < mons.length; i++)
                    if (mons[i] && mons[i].name === per.modelData.name)
                        return mons[i];
                return null;
            }
            /**
             * This screen's desktop is covered: its active workspace holds a
             * tiled window (tiles fill the work area; floating ones are left
             * out). The toplevels' ipc objects are kept fresh by shell.qml's
             * refreshToplevels on every window event. While covered the
             * widgets fade out and their windows unmap, which also stops the
             * lyrics' per-frame sweep and keeps their text from showing
             * through a translucent terminal. Settings › Widgets can keep them.
             */
            readonly property bool covered: {
                if (!Widgets.hideCovered)
                    return false;
                var ws = per.hMonitor ? per.hMonitor.activeWorkspace : null;
                if (!ws || !ws.toplevels)
                    return false;
                var tl = ws.toplevels.values;
                for (var i = 0; i < tl.length; i++) {
                    var o = tl[i] ? tl[i].lastIpcObject : null;
                    if (o && o.floating === false)
                        return true;
                }
                return false;
            }

            Loader {
                active: Widgets.cover.on
                sourceComponent: CoverArt {
                    screen: per.modelData
                    s: per.s
                    sw: per.modelData.width
                    sh: per.modelData.height
                    layer: root.layer
                    covered: per.covered
                }
            }

            Loader {
                active: Widgets.lyrics.on
                sourceComponent: LyricsView {
                    screen: per.modelData
                    s: per.s
                    sw: per.modelData.width
                    sh: per.modelData.height
                    layer: root.layer
                    covered: per.covered
                }
            }

            LazyLoader {
                active: Widgets.editing
                WidgetEditor {
                    screen: per.modelData
                    s: per.s
                }
            }
        }
    }
}
