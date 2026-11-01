import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../colors"
import "../../config"
import "../../services"

/**
 * astralis — depth clock: a big desktop clock that sits INSIDE the wallpaper.
 * The real wallpaper (skwd-paper, Background layer) is behind it; on top of it
 * this window paints the wallpaper's own foreground cut-out
 * (services/WallpaperDepth.qml), so near objects in the scene pass in front
 * of the numerals.
 *
 * Geometry is a box like the other desktop widgets (Widgets.depth x/y/w/h as
 * screen fractions) — placed and resized in the widget placer; the numerals
 * auto-fit the box. The window is exactly the box and the screen-sized cut-out
 * is drawn at the window's negative offset and clipped, so it never paints over
 * the other Bottom-layer widgets. Fully click-through.
 */
PanelWindow {
    id: win

    property real s: 1
    /** Screen size in logical px. */
    property real sw: 1920
    property real sh: 1080
    readonly property real dpr: screen?.devicePixelRatio ?? 1
    /** Screen size in physical px — the cut-out is rendered at exactly this. */
    readonly property string physSize: Math.round(sw * dpr) + "x" + Math.round(sh * dpr)

    readonly property var cfg: Widgets.depth
    readonly property string cut: WallpaperDepth.cutout(physSize)
    readonly property real boxW: Math.max(80, cfg.w * sw)
    readonly property real boxH: Math.max(48, cfg.h * sh)

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "astralis-depth"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.left: true
    anchors.top: true
    margins.left: Math.round(cfg.x * sw)
    margins.top: Math.round(cfg.y * sh)
    implicitWidth: Math.round(boxW)
    implicitHeight: Math.round(boxH)
    mask: Region {}

    Component.onCompleted: WallpaperDepth.want(win.physSize)
    onPhysSizeChanged: WallpaperDepth.want(win.physSize)

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ── fit: the largest time size whose block fits the box ─────────────────
    // Measured at 100 px on a fixed widest sample, so the size does not jump
    // when the hour gains a digit.
    TextMetrics {
        id: tmTime
        font.family: Appearance.font.family
        font.weight: win.cfg.weight
        font.pixelSize: 100
        text: "00:00"
    }
    FontMetrics {
        id: fm
        font.family: Appearance.font.family
        font.weight: win.cfg.weight
        font.pixelSize: 100
    }
    readonly property real trackRatio: -0.03
    readonly property real dateRatio: 0.16
    readonly property real wPer: tmTime.advanceWidth / 100 + 5 * trackRatio
    readonly property real hPer: fm.height / 100 * (1 + (cfg.date ? dateRatio : 0)) + (cfg.date ? -0.06 : 0)
    readonly property int px: Math.max(16, Math.floor(Math.min(boxW * 0.96 / Math.max(0.1, wPer), boxH / Math.max(0.1, hPer))))

    readonly property color ink: Colors[cfg.color] ?? Colors.primary

    Item {
        anchors.fill: parent
        clip: true

        Column {
            id: face
            readonly property real gap: win.cfg.align === "left" || win.cfg.align === "right" ? win.px * 0.02 : 0
            x: win.cfg.align === "left" ? gap
             : win.cfg.align === "right" ? parent.width - width - gap
             : Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            spacing: Math.round(-0.06 * win.px)
            opacity: win.cfg.opacity

            Text {
                id: date
                visible: win.cfg.date
                anchors.left: win.cfg.align === "left" ? parent.left : undefined
                anchors.right: win.cfg.align === "right" ? parent.right : undefined
                anchors.horizontalCenter: win.cfg.align === "center" ? parent.horizontalCenter : undefined
                anchors.leftMargin: win.px * 0.04
                anchors.rightMargin: win.px * 0.04
                text: Qt.formatDate(clock.date, "dddd, d MMMM")
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: Math.round(win.px * win.dateRatio)
                font.weight: Font.DemiBold
                font.letterSpacing: Math.round(win.px * win.dateRatio) * 0.04
            }

            Text {
                id: time
                anchors.left: win.cfg.align === "left" ? parent.left : undefined
                anchors.right: win.cfg.align === "right" ? parent.right : undefined
                anchors.horizontalCenter: win.cfg.align === "center" ? parent.horizontalCenter : undefined
                text: Qt.formatTime(clock.date, Flags.time12h ? "h:mm" : "HH:mm")
                color: win.ink
                font.family: Appearance.font.family
                font.pixelSize: win.px
                font.weight: win.cfg.weight
                font.letterSpacing: win.px * win.trackRatio
                font.features: { "tnum": 1 }
            }

            layer.enabled: win.cfg.shadow
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.alpha(Colors.shadow, 0.45)
                shadowBlur: 0.8
                shadowVerticalOffset: 3 * win.s
            }
        }

        // The wallpaper's foreground, screen-aligned, over the clock.
        Image {
            id: cutImg
            x: -win.margins.left
            y: -win.margins.top
            width: win.sw
            height: win.sh
            visible: win.cfg.cut
            source: win.cut.length ? "file://" + win.cut : ""
            sourceSize: Qt.size(win.sw * win.dpr, win.sh * win.dpr)
            fillMode: Image.Stretch
            asynchronous: true
            retainWhileLoading: true
            cache: false
            smooth: true
            // Fades in once the new wallpaper's cut-out lands; cleared instantly
            // on a wallpaper change (the old one would no longer line up).
            opacity: win.cut.length && status === Image.Ready ? 1 : 0
            Behavior on opacity {
                enabled: cutImg.opacity < 0.5
                NumberAnimation { duration: Motion.largeDur; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve }
            }
        }
    }
}
