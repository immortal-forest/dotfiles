import QtQuick
import Quickshell
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

    /** WlrLayer.Bottom = on the desktop under windows (the default). */
    property int layer: WlrLayer.Bottom

    IpcHandler {
        target: "desktop"
        function edit(): void { Widgets.editing = !Widgets.editing; }
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
            readonly property real s: modelData ? (modelData.height / 1080) * Flags.uiScale : 1

            Loader {
                active: Widgets.cover.on
                sourceComponent: CoverArt {
                    screen: per.modelData
                    s: per.s
                    sw: per.modelData.width
                    sh: per.modelData.height
                    layer: root.layer
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
