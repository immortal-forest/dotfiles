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
 * classic / stacked / date-below, own font, solid / outline / gradient /
 * glass fill, effect (glow / extrude / echo), colours, weight, letter spacing,
 * date format + size, 12/24 h.
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
    /** False starts the fade-out; Depth.qml's Loader destroys us once it has run. */
    property bool shown: true
    /** 0..1 clock opacity: eases in on creation, out when `shown` flips off. */
    property real fade: 0
    Behavior on fade {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.standardCurve }
    }
    Component.onCompleted: {
        fade = Qt.binding(() => win.shown ? 1 : 0);
        WallpaperDepth.want(win.physSize);
    }
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
            return [h12 ? Qt.formatTime(d, "hh AP").split(" ")[0] : Qt.formatTime(d, "HH"), Qt.formatTime(d, "mm")];
        // Qt counts h/hh 1–12 only when the format has AP; the suffix is cut.
        return [h12 ? Qt.formatTime(d, "h:mm AP").split(" ")[0] : Qt.formatTime(d, "HH:mm")];
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

    // ── effects ─────────────────────────────────────────────────────────────
    // fill "glass": the wallpaper behind the numerals, frosted and lit on the
    // top edges. effect: glow = a soft halo of the face in its own colours;
    // extrude = a solid 3D side, shaded darker toward the back; echo = three
    // receding ghosts in color2. Extrude/echo run down-right (light from the
    // top-left); sizes are × the time size. Echo is not offered with the
    // outline fill (dropped after review), so that pair draws no effect.
    readonly property bool glass: cfg.fill === "glass"
    readonly property string effect: cfg.effect === "echo" && cfg.fill === "outline" ? "none" : cfg.effect
    readonly property real fxDx: 0.45
    readonly property real fxDy: 0.9
    readonly property real extrudeDepth: 0.075
    readonly property real echoStep: 0.045
    readonly property real fxReach: effect === "extrude" ? extrudeDepth : effect === "echo" ? 3 * echoStep : 0
    readonly property int extrudeSteps: Math.max(8, Math.min(48, Math.round(px * extrudeDepth * 1.1)))

    function mix(a, b, f) {
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f);
    }

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
    // Glow needs side room for its halo (the window clips at the box); extrude
    // and echo reach right and down past the glyphs.
    readonly property real wPer: Math.max(tmTime.advanceWidth / 100 + nChars * track
                                          + fxReach * fxDx + (effect === "glow" ? 0.14 : 0),
                                          dateOn ? tmDate.advanceWidth / 100 * dateRatio : 0)
    readonly property real lineH: fm.height / 100
    readonly property real hPer: (stacked ? 2 * lineH - stackGap : lineH) + fxReach * fxDy
                               + (dateOn ? tmDate.height / 100 * dateRatio + dateGap : 0)
    readonly property int px: Math.max(16, Math.floor(Math.min(boxW * 0.96 / Math.max(0.1, wPer), boxH / Math.max(0.1, hPer))))

    /** Halo reach of the glow (px), scaled with the clock. */
    readonly property int haloMax: Math.max(16, Math.min(64, Math.round(px * 0.16)))

    // Cast shadow: the foreground's silhouette falls on the numerals, pushed
    // down-right (light from the top-left, like extrude/echo). Strength,
    // distance and softness are settings (distance/softness × the time size).
    readonly property bool castShadow: cfg.cut && cfg.castStrength > 0 && cut.length > 0
    readonly property real castReach: px * cfg.castDistance / 100
    readonly property int castBlur: Math.max(2, Math.min(64, Math.round(px * cfg.castSoftness / 100)))
    /** The face's own hue, deep and saturated: black over a light ink reads as mud. */
    readonly property color castTint: {
        var c = cfg.fill === "gradient" ? mix(ink, ink2, 0.5) : ink;
        return c.hslHue < 0 ? Qt.hsla(0, 0, 0.1, 1) : Qt.hsla(c.hslHue, Math.min(1, c.hslSaturation * 0.8 + 0.3), 0.14, 1);
    }

    // Glass: the wallpaper, screen-aligned like the cut-out (skwd-paper's
    // centred cover crop), at quarter resolution — it is only ever shown
    // frosted. Never drawn itself; each glass line samples it.
    Image {
        id: wallImg
        x: -win.margins.left
        y: -win.margins.top
        width: win.sw
        height: win.sh
        visible: false
        layer.enabled: win.glass
        layer.textureSize: Qt.size(Math.round(win.sw * win.dpr / 4), Math.round(win.sh * win.dpr / 4))
        source: win.glass && Wallpaper.current.length ? "file://" + Wallpaper.current : ""
        sourceSize: Qt.size(Math.round(win.sw * win.dpr / 4), Math.round(win.sh * win.dpr / 4))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
    }

    // One line of the time, in any fill + effect.
    component TimeLine: Item {
        id: tl
        property string text: ""
        readonly property font face: Qt.font({
            family: win.family, pixelSize: win.px, weight: win.cfg.weight,
            letterSpacing: win.px * win.track, features: { "tnum": 1 }
        })
        // Extrude / echo reach right: count it so alignment includes them.
        implicitWidth: metric.implicitWidth + win.px * win.fxReach * win.fxDx
        implicitHeight: metric.implicitHeight

        /** This line's origin in the window — where glass samples the wallpaper. */
        readonly property point org: {
            face.x; face.y; timeCol.x; timeCol.y; tl.x; tl.y; win.px;
            return tl.mapToItem(null, 0, 0);
        }

        // Size master; never drawn.
        Text {
            id: metric
            visible: false
            text: tl.text
            font: tl.face
        }

        // Glyph mask for gradient, outline, glass and echo: the white glyphs on
        // a canvas padded by `pad` on every side (an outer stroke reaches past
        // the text box).
        readonly property real pad: Math.ceil(win.px * 0.05)
        readonly property real stroke: Math.max(1.5, win.px * 0.024)
        Item {
            id: glyphMask
            x: -tl.pad
            y: -tl.pad
            width: metric.implicitWidth + 2 * tl.pad
            height: metric.implicitHeight + 2 * tl.pad
            visible: false
            layer.enabled: win.cfg.fill !== "solid" || win.effect === "echo"
            Text {
                x: tl.pad
                y: tl.pad
                text: tl.text
                font: tl.face
                color: "white"
            }
        }

        // ── behind the face ─────────────────────────────────────────────────
        // Extrude: glyph copies stepped down-right, drawn back to front and
        // darkening toward the back, so the side reads as a lit solid.
        Repeater {
            model: win.effect === "extrude" ? win.extrudeSteps : 0
            Text {
                required property int index
                /** 1 = the back copy (drawn first) … 1/steps = right behind the face. */
                readonly property real k: (win.extrudeSteps - index) / win.extrudeSteps
                x: k * win.px * win.extrudeDepth * win.fxDx
                y: k * win.px * win.extrudeDepth * win.fxDy
                text: tl.text
                font: tl.face
                color: win.mix(win.ink, Colors.shadow, 0.3 + 0.45 * k)
            }
        }

        // Echo: three ghosts of the glyph shape in color2, receding and fading.
        Repeater {
            model: win.effect === "echo" ? 3 : 0
            Rectangle {
                required property int index
                /** 3 = the farthest ghost (drawn first). */
                readonly property int k: 3 - index
                x: glyphMask.x + k * win.px * win.echoStep * win.fxDx
                y: glyphMask.y + k * win.px * win.echoStep * win.fxDy
                width: glyphMask.width
                height: glyphMask.height
                color: win.ink2
                opacity: k === 1 ? 0.6 : k === 2 ? 0.32 : 0.14
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: glyphMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
            }
        }

        // Glow: the face itself blurred into a halo in its own colours — a wide
        // soft bloom plus a tight one hugging the glyphs. `art` is NOT layered:
        // MultiEffect then captures it with room for the blur (a layered source
        // is a fixed texture that gets stretched over the padding instead).
        Loader {
            active: win.effect === "glow"
            anchors.fill: art
            sourceComponent: Item {
                MultiEffect {
                    anchors.fill: parent
                    source: art
                    blurEnabled: true
                    blur: 1
                    blurMax: win.haloMax
                    brightness: 0.3
                    saturation: 0.5
                }
                MultiEffect {
                    anchors.fill: parent
                    source: art
                    blurEnabled: true
                    blur: 0.5
                    blurMax: Math.round(win.haloMax / 3)
                    brightness: 0.15
                    saturation: 0.4
                }
            }
        }

        // ── the face, in its fill ───────────────────────────────────────────
        Item {
            id: art
            x: -tl.pad
            y: -tl.pad
            width: glyphMask.width
            height: glyphMask.height

            Text {
                x: tl.pad
                y: tl.pad
                text: tl.text
                font: tl.face
                color: win.ink
                visible: win.cfg.fill === "solid"
            }

            // Gradient: the glyphs mask a vertical ink → ink2 ramp.
            Rectangle {
                anchors.fill: parent
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
                anchors.fill: parent
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

            // Glass: the wallpaper right behind the numerals, frosted, tinted
            // with the ink, lit along the top-left edges and shaded along the
            // bottom-right ones (each edge band = the glyphs minus themselves
            // nudged, so no stroke — variable fonts' inner contours never show).
            Item {
                id: glassFace
                anchors.fill: parent
                visible: win.glass
                layer.enabled: visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: glyphMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
                readonly property real edge: Math.max(1.5, win.px * 0.014)

                MultiEffect {
                    source: wallImg
                    x: -(win.margins.left + tl.org.x - tl.pad)
                    y: -(win.margins.top + tl.org.y - tl.pad)
                    width: win.sw
                    height: win.sh
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1
                    blurMax: 40
                    brightness: 0.14
                    saturation: 0.2
                }
                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(win.ink, 0.28)
                }
                // lit edge
                Item {
                    x: glassFace.edge * 0.5
                    y: glassFace.edge
                    width: parent.width
                    height: parent.height
                    layer.enabled: glassFace.visible
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskInverted: true
                        maskSource: glyphMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.75) }
                            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.3) }
                        }
                    }
                }
                // shaded edge
                Item {
                    x: -glassFace.edge * 0.5
                    y: -glassFace.edge
                    width: parent.width
                    height: parent.height
                    layer.enabled: glassFace.visible
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskInverted: true
                        maskSource: glyphMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(Colors.shadow, 0.35)
                    }
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

        // The clock face, padded by `room` on every side so its layer (shadow,
        // opacity) doesn't cut off what reaches past the glyphs (glow halo,
        // extrusion, echo).
        Item {
            id: face
            readonly property real room: win.haloMax + Math.ceil(win.px * 0.12)
            readonly property real gap: win.cfg.align === "center" ? 0 : win.px * 0.02
            width: stack.width + 2 * room
            height: stack.height + 2 * room
            x: (win.cfg.align === "left" ? gap
             : win.cfg.align === "right" ? parent.width - stack.width - gap
             : Math.round((parent.width - stack.width) / 2)) - room
            y: Math.round((parent.height - stack.height) / 2) - room
            opacity: win.cfg.opacity * win.fade

            // Glow carries its own light; a drop shadow under the halo only muddies it.
            layer.enabled: win.cfg.shadow || win.effect !== "none"
            layer.effect: MultiEffect {
                shadowEnabled: win.cfg.shadow && win.effect !== "glow"
                shadowColor: Qt.alpha(Colors.shadow, 0.45)
                shadowBlur: 0.8
                shadowVerticalOffset: 3 * win.s
            }

            Column {
                id: stack
                x: face.room
                y: face.room
                spacing: Math.round(win.px * win.dateGap)

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
            }
        }

        // What the clock draws (fills, extrusion, date), in window coordinates:
        // the cast shadow's mask, so it lands on the numerals and never on the
        // wallpaper around them.
        ShaderEffectSource {
            id: faceTex
            width: parent.width
            height: parent.height
            visible: false
            hideSource: false
            sourceItem: win.castShadow ? stack : null
            sourceRect: Qt.rect(-(face.x + stack.x), -(face.y + stack.y), width, height)
        }

        // The cast shadow: the tint, cut to the foreground's silhouette (the
        // cut-out at quarter resolution — it is only ever seen blurred),
        // shifted, then blurred and masked by the face.
        Rectangle {
            id: castInk
            width: 4
            height: 4
            visible: false
            color: win.castTint
            layer.enabled: win.castShadow
        }
        Image {
            id: castSil
            width: win.sw
            height: win.sh
            visible: false
            source: win.castShadow ? cutImg.source : ""
            sourceSize: Qt.size(Math.round(win.sw * win.dpr / 4), Math.round(win.sh * win.dpr / 4))
            fillMode: Image.Stretch
            asynchronous: true
            retainWhileLoading: true
            cache: false
            smooth: true
            layer.enabled: win.castShadow
            layer.textureSize: sourceSize
        }
        Item {
            anchors.fill: parent
            visible: win.castShadow && castSil.status === Image.Ready
            opacity: win.cfg.castStrength * face.opacity * cutImg.opacity
            layer.enabled: visible
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1
                blurMax: win.castBlur
                maskEnabled: true
                maskSource: faceTex
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            MultiEffect {
                x: cutImg.x + win.castReach * win.fxDx
                y: cutImg.y + win.castReach * win.fxDy
                width: win.sw
                height: win.sh
                source: castInk
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: castSil
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
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
                NumberAnimation { duration: Motion.largeDur; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.standardCurve }
            }
        }
    }
}
