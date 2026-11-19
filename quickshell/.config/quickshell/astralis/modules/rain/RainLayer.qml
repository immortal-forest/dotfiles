import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

/**
 * astralis — Retroact Rain's surface on one screen: transparent,
 * click-through, WlrLayer.Bottom (over the wallpaper and the desktop
 * widgets, under every window). Created by Rain.qml only while the event
 * plays, so at rest there is no surface at all.
 */
PanelWindow {
    id: layer

    property var ev

    color: "transparent"
    mask: Region {}
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "astralis-rain"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    readonly property real dpr: screen?.devicePixelRatio ?? 1
    /** Same key DepthClock asks for, so both share one cached cut-out. */
    readonly property string physSize: Math.round((screen?.width ?? 0) * dpr) + "x" + Math.round((screen?.height ?? 0) * dpr)

    // Ask for the cut-out only once the depth runtime is known to be
    // installed: want() on a box without it would start the ~140 MB setup.
    readonly property bool depthReady: WallpaperDepth.ready
    function wantCut() {
        if (WallpaperDepth.ready && (screen?.width ?? 0) > 0)
            WallpaperDepth.want(layer.physSize);
    }
    onDepthReadyChanged: wantCut()
    onPhysSizeChanged: wantCut()
    Component.onCompleted: wantCut()

    RainView {
        anchors.fill: parent
        ev: layer.ev
        dpr: layer.dpr
        // a live wallpaper refracts a full-res frame of its video
        wallPath: Wallpaper.still
        cutPath: WallpaperDepth.cutout(layer.physSize)
        // Settings › Widgets › Retroact Rain, live
        density: Flags.rainAmount / 100
        sizeMul: Flags.rainSize / 100
        strength: Flags.rainOpacity / 100
        tintRole: Flags.rainTint
        skyOn: Flags.rainSky
        behind: Flags.rainBehind
    }
}
