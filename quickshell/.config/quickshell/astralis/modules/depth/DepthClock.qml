pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
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
 * screen fractions) — placed and resized in the widget placer; the clock
 * auto-fits the box. Style (Settings › Widgets › Depth clock): layout
 * classic / stacked / date-below, own font, solid / outline / gradient fill,
 * colours, weight, letter spacing, date format + size, 12/24 h.
 *
 * The window is exactly the box and the screen-sized cut-out is drawn at the
 * window's negative offset and clipped, so it never paints over the other
 * Bottom-layer widgets. Fully click-through.
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

    // ── style ───────────────────────────────────────────────────────────────
    readonly property string family: cfg.font.length > 0 ? cfg.font : Appearance.font.family
    readonly property bool stacked: cfg.layout === "stacked"
    readonly property bool h12: cfg.hour === "12" || (cfg.hour === "auto" && Flags.time12h)
    readonly property var lines: {
        var d = clock.date;
        if (stacked)
            return [Qt.formatTime(d, h12 ? "hh" : "HH"), Qt.formatTime(d, "mm")];
        return [Qt.formatTime(d, h12 ? "h:mm" : "HH:mm")];
    }
    readonly property bool dateOn: cfg.dateFormat !== "off"
    readonly property string dateText: Qt.formatDate(clock.date, cfg.dateFormat === "short" ? "ddd d MMM" : "dddd, d MMMM")
    readonly property real track: cfg.tracking / 100
    readonly property real dateRatio: cfg.dateSize / 100
    /** Stacked lines overlap their empty ascent/descent space by this much (× size). */
    readonly property real stackGap: 0.38
    readonly property real dateGap: -0.08
    readonly property color ink: Colors[cfg.color] ?? Colors.primary
    readonly property color ink2: Colors[cfg.color2] ?? Colors.tertiary
    readonly property color dateInk: Colors[cfg.dateColor] ?? Colors.on_surface

    // ── fit: the largest time size whose block fits the box ─────────────────
    // Measured at 100 px on a fixed widest sample, so the size does not jump
    // when the hour gains a digit.
    TextMetrics {
        id: tmTime
        font.family: win.family
        font.weight: win.cfg.weight
        font.pixelSize: 100
        text: win.stacked ? "00" : "00:00"
    }
    FontMetrics {
        id: fm
        font.family: win.family
        font.weight: win.cfg.weight
        font.pixelSize: 100
    }
    TextMetrics {
        id: tmDate
        font.family: Appearance.font.family
        font.weight: Font.DemiBold
        font.pixelSize: 100
        text: win.dateText
    }
    readonly property real nChars: stacked ? 2 : 5
    readonly property real wPer: Math.max(tmTime.advanceWidth / 100 + nChars * track,
                                          dateOn ? tmDate.advanceWidth / 100 * dateRatio : 0)
    readonly property real lineH: fm.height / 100
    readonly property real hPer: (stacked ? 2 * lineH - stackGap : lineH)
                               + (dateOn ? tmDate.height / 100 * dateRatio + dateGap : 0)
    readonly property int px: Math.max(16, Math.floor(Math.min(boxW * 0.96 / Math.max(0.1, wPer), boxH / Math.max(0.1, hPer))))

    // One line of the time, in any fill.
    component TimeLine: Item {
        id: tl
        property string text: ""
        readonly property font face: Qt.font({
            family: win.family, pixelSize: win.px, weight: win.cfg.weight,
            letterSpacing: win.px * win.track, features: { "tnum": 1 }
        })
        implicitWidth: solid.implicitWidth
        implicitHeight: solid.implicitHeight

        Text {
            id: solid
            text: tl.text
            font: tl.face
            color: win.ink
            visible: win.cfg.fill === "solid"
        }

        // Glyph mask for gradient + outline: the white glyphs on a canvas padded
        // by `pad` on every side (an outer stroke reaches past the text box).
        readonly property real pad: Math.ceil(win.px * 0.05)
        readonly property real stroke: Math.max(1.5, win.px * 0.024)
        Item {
            id: glyphMask
            anchors.fill: solid
            anchors.margins: -tl.pad
            visible: false
            layer.enabled: win.cfg.fill !== "solid"
            Text {
                x: tl.pad
                y: tl.pad
                text: tl.text
                font: tl.face
                color: "white"
            }
        }

        // Gradient: the glyphs mask a vertical ink → ink2 ramp.
        Rectangle {
            anchors.fill: glyphMask
            visible: win.cfg.fill === "gradient"
            gradient: Gradient {
                GradientStop { position: 0.2; color: win.ink }
                GradientStop { position: 0.85; color: win.ink2 }
            }
            layer.enabled: visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: glyphMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }

        // Outline: the glyph path stroked at 2x width, then the solid glyphs
        // masked OUT. Leaves a clean outer ring and hides the inner overlap
        // contours variable fonts carry (they would show as stray strokes).
        // PathText puts its x/y at the glyphs' tight top-left, so offset it by
        // the tight bounds to line up with the Text (baseline = ascent).
        TextMetrics {
            id: tight
            font: tl.face
            text: tl.text
        }
        FontMetrics {
            id: lineFm
            font: tl.face
        }
        Shape {
            anchors.fill: glyphMask
            visible: win.cfg.fill === "outline"
            preferredRendererType: Shape.CurveRenderer
            layer.enabled: visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskInverted: true
                maskSource: glyphMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
            ShapePath {
                strokeColor: win.ink
                strokeWidth: tl.stroke * 2
                fillColor: "transparent"
                joinStyle: ShapePath.RoundJoin
                PathText {
                    x: tl.pad + tight.tightBoundingRect.x
                    y: tl.pad + lineFm.ascent + tight.tightBoundingRect.y
                    text: tl.text
                    font: tl.face
                }
            }
        }
    }

    component DateLine: Text {
        anchors.left: win.cfg.align === "left" ? parent?.left : undefined
        anchors.right: win.cfg.align === "right" ? parent?.right : undefined
        anchors.horizontalCenter: win.cfg.align === "center" ? parent?.horizontalCenter : undefined
        anchors.leftMargin: win.px * 0.04
        anchors.rightMargin: win.px * 0.04
        text: win.dateText
        color: win.dateInk
        font.family: Appearance.font.family
        font.pixelSize: Math.max(8, Math.round(win.px * win.dateRatio))
        font.weight: Font.DemiBold
        font.letterSpacing: Math.max(8, Math.round(win.px * win.dateRatio)) * 0.04
    }

    Item {
        anchors.fill: parent
        clip: true

        Column {
            id: face
            readonly property real gap: win.cfg.align === "center" ? 0 : win.px * 0.02
            x: win.cfg.align === "left" ? gap
             : win.cfg.align === "right" ? parent.width - width - gap
             : Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            spacing: Math.round(win.px * win.dateGap)
            opacity: win.cfg.opacity

            DateLine { visible: win.dateOn && win.cfg.layout !== "below" }

            Column {
                id: timeCol
                anchors.left: win.cfg.align === "left" ? parent.left : undefined
                anchors.right: win.cfg.align === "right" ? parent.right : undefined
                anchors.horizontalCenter: win.cfg.align === "center" ? parent.horizontalCenter : undefined
                spacing: -Math.round(win.px * win.stackGap)

                Repeater {
                    model: win.lines
                    TimeLine {
                        required property string modelData
                        text: modelData
                        anchors.left: win.cfg.align === "left" ? parent?.left : undefined
                        anchors.right: win.cfg.align === "right" ? parent?.right : undefined
                        anchors.horizontalCenter: win.cfg.align === "center" ? parent?.horizontalCenter : undefined
                    }
                }
            }

            DateLine { visible: win.dateOn && win.cfg.layout === "below" }

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
