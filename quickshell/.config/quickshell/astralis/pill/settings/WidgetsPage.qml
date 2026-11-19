pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 景 WIDGETS settings page: the desktop widgets (cover art,
 * synced lyrics, depth clock). "Edit layout" opens the full-screen placer
 * (modules/nowplaying/WidgetEditor.qml) — drag, resize, snap grid. Everything
 * here backs onto services/Widgets.qml (~/.cache/astralis/widgets.json) and
 * applies live.
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    readonly property var radiusOptions: [
        { label: "Square", value: 0.25 }, { label: "Soft", value: 1 }, { label: "Round", value: 2.2 }
    ]
    readonly property var backdropOptions: [
        { label: "Off", value: "off" }, { label: "Soft", value: "soft" }, { label: "Solid", value: "solid" }
    ]
    readonly property var alignOptions: [
        { label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }
    ]
    readonly property var clockAlignOptions: [
        { label: "Left", value: "left" }, { label: "Center", value: "center" }, { label: "Right", value: "right" }
    ]
    readonly property var colorOptions: [
        { label: "Accent", value: "primary" }, { label: "Tertiary", value: "tertiary" },
        { label: "Secondary", value: "secondary" }, { label: "Light", value: "on_surface" }
    ]
    readonly property var layoutOptions: [
        { label: "Classic", value: "classic" }, { label: "Stacked", value: "stacked" }, { label: "Date below", value: "below" }
    ]
    readonly property var fillOptions: [
        { label: "Solid", value: "solid" }, { label: "Outline", value: "outline" }, { label: "Gradient", value: "gradient" },
        { label: "Glass", value: "glass" }
    ]
    readonly property var effectOptions: [
        { label: "None", value: "none" }, { label: "Glow", value: "glow" }, { label: "Extrude", value: "extrude" }, { label: "Echo", value: "echo" }
    ]
    /** Echo isn't offered with the outline fill. */
    readonly property var clockEffectOptions: Widgets.depth.fill === "outline" ? effectOptions.filter(o => o.value !== "echo") : effectOptions
    /** Picking Outline while Echo is on drops the effect with it. */
    function setClockFill(v) {
        if (v === "outline" && Widgets.depth.effect === "echo")
            Widgets.set("depth", { fill: v, effect: "none" });
        else
            Widgets.set("depth", "fill", v);
    }
    readonly property var dateFormatOptions: [
        { label: "Long", value: "long" }, { label: "Short", value: "short" }, { label: "Off", value: "off" }
    ]
    readonly property var hourOptions: [
        { label: "Auto", value: "auto" }, { label: "24 h", value: "24" }, { label: "12 h", value: "12" }
    ]
    readonly property var weightOptions: [
        { label: "Light", value: 300 }, { label: "Regular", value: 400 }, { label: "Bold", value: 700 }, { label: "Black", value: 900 }
    ]

    rows: [
        { item: editRow, kind: "toggle", get: function () { return Widgets.editing; }, set: function (v) { Widgets.editing = v; } },
        { item: coverRow, kind: "toggle", get: function () { return Widgets.cover.on; }, set: function (v) { Widgets.set("cover", "on", v); } },
        { item: coverSizeRow, kind: "scrub", bump: function (d) { coverSizeScrub.bump(d); } },
        { item: radiusRow, kind: "seg", vals: root.radiusOptions.map(o => o.value), get: function () { return Widgets.cover.radius; }, set: function (v) { Widgets.set("cover", "radius", v); } },
        { item: haloRow, kind: "toggle", get: function () { return Widgets.cover.halo; }, set: function (v) { Widgets.set("cover", "halo", v); } },
        { item: captionRow, kind: "toggle", get: function () { return Widgets.cover.caption; }, set: function (v) { Widgets.set("cover", "caption", v); } },
        { item: songFontRow, kind: "nav", surface: "songfont" },
        { item: lyricsRow, kind: "toggle", get: function () { return Widgets.lyrics.on; }, set: function (v) { Widgets.set("lyrics", "on", v); } },
        { item: lyrWRow, kind: "scrub", bump: function (d) { lyrWScrub.bump(d); } },
        { item: lyrHRow, kind: "scrub", bump: function (d) { lyrHScrub.bump(d); } },
        { item: sizeRow, kind: "scrub", bump: function (d) { sizeScrub.bump(d); } },
        { item: backdropRow, kind: "seg", vals: root.backdropOptions.map(o => o.value), get: function () { return Widgets.lyrics.backdrop; }, set: function (v) { Widgets.set("lyrics", "backdrop", v); } },
        { item: alignRow, kind: "seg", vals: root.alignOptions.map(o => o.value), get: function () { return Widgets.lyrics.align; }, set: function (v) { Widgets.set("lyrics", "align", v); } },
        { item: glowRow, kind: "toggle", get: function () { return Widgets.lyrics.glow; }, set: function (v) { Widgets.set("lyrics", "glow", v); } },
        { item: blurRow, kind: "toggle", get: function () { return Widgets.lyrics.blur; }, set: function (v) { Widgets.set("lyrics", "blur", v); } },
        { item: depthRow, kind: "toggle", get: function () { return Widgets.depth.on; }, set: function (v) { Widgets.set("depth", "on", v); } },
        { item: depthCutRow, kind: "toggle", get: function () { return Widgets.depth.cut; }, set: function (v) { Widgets.set("depth", "cut", v); } },
        { item: cutoffRow, kind: "scrub", bump: function (d) { cutoffScrub.bump(d); } },
        { item: featherRow, kind: "scrub", bump: function (d) { featherScrub.bump(d); } },
        { item: castRow, kind: "scrub", bump: function (d) { castScrub.bump(d); } },
        { item: castDistRow, kind: "scrub", bump: function (d) { castDistScrub.bump(d); } },
        { item: castSoftRow, kind: "scrub", bump: function (d) { castSoftScrub.bump(d); } },
        { item: clockLayoutRow, kind: "seg", vals: root.layoutOptions.map(o => o.value), get: function () { return Widgets.depth.layout; }, set: function (v) { Widgets.set("depth", "layout", v); } },
        { item: clockFontRow, kind: "nav", surface: "clockfont" },
        { item: clockFillRow, kind: "seg", vals: root.fillOptions.map(o => o.value), get: function () { return Widgets.depth.fill; }, set: function (v) { root.setClockFill(v); } },
        { item: clockEffectRow, kind: "seg", vals: root.clockEffectOptions.map(o => o.value), get: function () { return Widgets.depth.effect; }, set: function (v) { Widgets.set("depth", "effect", v); } },
        { item: clockColorRow, kind: "seg", vals: root.colorOptions.map(o => o.value), get: function () { return Widgets.depth.color; }, set: function (v) { Widgets.set("depth", "color", v); } },
        { item: clockWeightRow, kind: "seg", vals: root.weightOptions.map(o => o.value), get: function () { return Widgets.depth.weight; }, set: function (v) { Widgets.set("depth", "weight", v); } },
        { item: clockColor2Row, kind: "seg", vals: root.colorOptions.map(o => o.value), get: function () { return Widgets.depth.color2; }, set: function (v) { Widgets.set("depth", "color2", v); } },
        { item: clockTrackRow, kind: "scrub", bump: function (d) { clockTrackScrub.bump(d); } },
        { item: clockAlignRow, kind: "seg", vals: root.clockAlignOptions.map(o => o.value), get: function () { return Widgets.depth.align; }, set: function (v) { Widgets.set("depth", "align", v); } },
        { item: clockDateRow, kind: "seg", vals: root.dateFormatOptions.map(o => o.value), get: function () { return Widgets.depth.dateFormat; }, set: function (v) { Widgets.set("depth", "dateFormat", v); } },
        { item: clockDateColorRow, kind: "seg", vals: root.colorOptions.map(o => o.value), get: function () { return Widgets.depth.dateColor; }, set: function (v) { Widgets.set("depth", "dateColor", v); } },
        { item: clockDateSizeRow, kind: "scrub", bump: function (d) { clockDateSizeScrub.bump(d); } },
        { item: clockHourRow, kind: "seg", vals: root.hourOptions.map(o => o.value), get: function () { return Widgets.depth.hour; }, set: function (v) { Widgets.set("depth", "hour", v); } },
        { item: clockShadowRow, kind: "toggle", get: function () { return Widgets.depth.shadow; }, set: function (v) { Widgets.set("depth", "shadow", v); } },
        { item: clockOpacityRow, kind: "scrub", bump: function (d) { clockOpacityScrub.bump(d); } }
    ]

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "景"
        title: "WIDGETS"
        onBack: root.back()
    }

    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.topMargin: 4 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: returnToBounds()

        Column {
            id: content
            width: flick.width
            spacing: 0

            SettingsSection {
                s: root.s
                surface: root
                title: "Layout"
                key: "widgets/layout"

                SettingsRow {
                    id: editRow
                    surface: root
                    name: "Edit layout"
                    sub: "Drag, resize and snap the widgets on screen"
                    icon: "cursor"
                    last: true

                    LinkToggle {
                        s: root.s
                        on: Widgets.editing
                        onToggled: Widgets.editing = !Widgets.editing
                    }
                }
            }

            SettingsSection {
                s: root.s
                surface: root
                title: "Cover art"
                key: "widgets/cover-art"

                SettingsRow {
                    id: coverRow
                    surface: root
                    name: "Show cover"
                    sub: "Scroll or click it to switch editions of the song"
                    captionOnFocus: true
                    icon: "image"

                    LinkToggle {
                        s: root.s
                        on: Widgets.cover.on
                        onToggled: Widgets.set("cover", "on", !Widgets.cover.on)
                    }
                }
                SettingsRow {
                    id: coverSizeRow
                    surface: root
                    name: "Size"
                    sub: "Percent of screen width — or drag its corner in Edit layout"
                    captionOnFocus: true
                    icon: "scaling"
                    shown: Widgets.cover.on

                    ScrubValue {
                        id: coverSizeScrub
                        s: root.s
                        value: Math.round(Widgets.cover.w * 100)
                        openValue: 16
                        from: 6
                        to: 40
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("cover", "w", v / 100)
                    }
                }
                SettingsRow {
                    id: radiusRow
                    surface: root
                    name: "Corners"
                    icon: "app-window"
                    shown: Widgets.cover.on

                    SettingsSeg {
                        s: root.s
                        options: root.radiusOptions
                        value: Widgets.cover.radius
                        onPicked: (v) => Widgets.set("cover", "radius", v)
                    }
                }
                SettingsRow {
                    id: haloRow
                    surface: root
                    name: "Colour halo"
                    sub: "The cover's own colour, blurred out behind it"
                    captionOnFocus: true
                    icon: "sparkles"
                    shown: Widgets.cover.on

                    LinkToggle {
                        s: root.s
                        on: Widgets.cover.halo
                        onToggled: Widgets.set("cover", "halo", !Widgets.cover.halo)
                    }
                }
                SettingsRow {
                    id: captionRow
                    surface: root
                    name: "Edition caption"
                    sub: "Source, album and dots, shown on hover"
                    captionOnFocus: true
                    icon: "type"
                    shown: Widgets.cover.on

                    LinkToggle {
                        s: root.s
                        on: Widgets.cover.caption
                        onToggled: Widgets.set("cover", "caption", !Widgets.cover.caption)
                    }
                }
                SettingsRow {
                    id: songFontRow
                    surface: root
                    name: "Song info font"
                    icon: "type"
                    sub: Widgets.cover.infoFont.length > 0 ? Widgets.cover.infoFont : "Shell font (" + Appearance.font.family + ")"
                    shown: Widgets.cover.on && Widgets.cover.info !== "off"
                    last: true

                    GlyphIcon {
                        width: 16 * root.s
                        height: 16 * root.s
                        name: "chevron-right"
                        color: root.focusRowItem === songFontRow ? Colors.on_surface : Colors.on_surface_variant
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        stroke: 2.2
                    }
                }
            }

            SettingsSection {
                s: root.s
                surface: root
                title: "Lyrics"
                key: "widgets/lyrics"

                SettingsRow {
                    id: lyricsRow
                    surface: root
                    name: "Show lyrics"
                    sub: "Time-synced, from LRCLIB"
                    captionOnFocus: true
                    icon: "music"

                    LinkToggle {
                        s: root.s
                        on: Widgets.lyrics.on
                        onToggled: Widgets.set("lyrics", "on", !Widgets.lyrics.on)
                    }
                }
                SettingsRow {
                    id: lyrWRow
                    surface: root
                    name: "Width"
                    sub: "Percent of screen width — or drag its corner in Edit layout"
                    captionOnFocus: true
                    icon: "scaling"
                    shown: Widgets.lyrics.on

                    ScrubValue {
                        id: lyrWScrub
                        s: root.s
                        value: Math.round(Widgets.lyrics.w * 100)
                        openValue: 45
                        from: 15
                        to: 95
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("lyrics", "w", v / 100)
                    }
                }
                SettingsRow {
                    id: lyrHRow
                    surface: root
                    name: "Height"
                    icon: "scaling"
                    shown: Widgets.lyrics.on

                    ScrubValue {
                        id: lyrHScrub
                        s: root.s
                        value: Math.round(Widgets.lyrics.h * 100)
                        openValue: 60
                        from: 15
                        to: 95
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("lyrics", "h", v / 100)
                    }
                }
                SettingsRow {
                    id: backdropRow
                    surface: root
                    name: "Backdrop"
                    sub: "A cover-tinted panel behind the lyrics for busy wallpapers"
                    captionOnFocus: true
                    icon: "palette"
                    shown: Widgets.lyrics.on

                    SettingsSeg {
                        s: root.s
                        options: root.backdropOptions
                        value: Widgets.lyrics.backdrop
                        onPicked: (v) => Widgets.set("lyrics", "backdrop", v)
                    }
                }
                SettingsRow {
                    id: sizeRow
                    surface: root
                    name: "Text size"
                    icon: "type"
                    shown: Widgets.lyrics.on

                    ScrubValue {
                        id: sizeScrub
                        s: root.s
                        value: Widgets.lyrics.size
                        openValue: 38
                        from: 20
                        to: 72
                        step: 1
                        unit: "px"
                        onEdited: v => Widgets.set("lyrics", "size", v)
                    }
                }
                SettingsRow {
                    id: alignRow
                    surface: root
                    name: "Alignment"
                    icon: "app-window"
                    shown: Widgets.lyrics.on

                    SettingsSeg {
                        s: root.s
                        options: root.alignOptions
                        value: Widgets.lyrics.align
                        onPicked: (v) => Widgets.set("lyrics", "align", v)
                    }
                }
                SettingsRow {
                    id: glowRow
                    surface: root
                    name: "Accent glow"
                    sub: "The sung line glows in the cover's colour"
                    captionOnFocus: true
                    icon: "sparkles"
                    shown: Widgets.lyrics.on

                    LinkToggle {
                        s: root.s
                        on: Widgets.lyrics.glow
                        onToggled: Widgets.set("lyrics", "glow", !Widgets.lyrics.glow)
                    }
                }
                SettingsRow {
                    id: blurRow
                    surface: root
                    name: "Depth blur"
                    sub: "Blur lines by distance from the sung one"
                    captionOnFocus: true
                    icon: "waves"
                    shown: Widgets.lyrics.on
                    last: true

                    LinkToggle {
                        s: root.s
                        on: Widgets.lyrics.blur
                        onToggled: Widgets.set("lyrics", "blur", !Widgets.lyrics.blur)
                    }
                }
            }

            SettingsSection {
                s: root.s
                surface: root
                title: "Depth clock"
                key: "widgets/depth-clock"

                SettingsRow {
                    id: depthRow
                    surface: root
                    name: "Show depth clock"
                    sub: "A big clock tucked behind the wallpaper's foreground — place and resize it in Edit layout"
                    captionOnFocus: true
                    icon: "clock"

                    LinkToggle {
                        s: root.s
                        on: Widgets.depth.on
                        onToggled: Widgets.set("depth", "on", !Widgets.depth.on)
                    }
                }
                SettingsRow {
                    id: depthCutRow
                    surface: root
                    name: "Depth effect"
                    sub: WallpaperDepth.status === "working" ? "Cutting out the scene…"
                       : WallpaperDepth.status === "setup" ? "Installing the depth model (one time, ~140 MB)…"
                       : WallpaperDepth.status === "error" ? "Failed: " + WallpaperDepth.error
                       : "Near objects in the wallpaper pass in front of the clock"
                    captionOnFocus: WallpaperDepth.status === "idle"
                    icon: "eye"
                    shown: Widgets.depth.on

                    LinkToggle {
                        s: root.s
                        on: Widgets.depth.cut
                        onToggled: Widgets.set("depth", "cut", !Widgets.depth.cut)
                    }
                }
                SettingsRow {
                    id: cutoffRow
                    surface: root
                    name: "Foreground cutoff"
                    sub: "Lower brings more of the scene in front of the clock"
                    captionOnFocus: true
                    icon: "waves"
                    shown: Widgets.depth.on && Widgets.depth.cut

                    ScrubValue {
                        id: cutoffScrub
                        s: root.s
                        value: Math.round(Widgets.depth.threshold * 100)
                        openValue: 30
                        from: 0
                        to: 100
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("depth", "threshold", v / 100)
                    }
                }
                SettingsRow {
                    id: featherRow
                    surface: root
                    name: "Edge softness"
                    sub: "Fade where the scene drifts through the cutoff, like a curtain"
                    captionOnFocus: true
                    icon: "sparkles"
                    shown: Widgets.depth.on && Widgets.depth.cut

                    ScrubValue {
                        id: featherScrub
                        s: root.s
                        value: Math.round(Widgets.depth.feather * 100)
                        openValue: 8
                        from: 0
                        to: 50
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("depth", "feather", v / 100)
                    }
                }
                SettingsRow {
                    id: castRow
                    surface: root
                    name: "Cast shadow"
                    sub: "The scene in front shades the numerals · 0 turns it off"
                    captionOnFocus: true
                    icon: "sun"
                    shown: Widgets.depth.on && Widgets.depth.cut

                    ScrubValue {
                        id: castScrub
                        s: root.s
                        value: Math.round(Widgets.depth.castStrength * 100)
                        openValue: 40
                        from: 0
                        to: 100
                        step: 5
                        unit: "%"
                        onEdited: v => Widgets.set("depth", "castStrength", v / 100)
                    }
                }
                SettingsRow {
                    id: castDistRow
                    surface: root
                    name: "Shadow distance"
                    sub: "How far it falls from what casts it, × the clock size"
                    captionOnFocus: true
                    icon: "scaling"
                    shown: Widgets.depth.on && Widgets.depth.cut && Widgets.depth.castStrength > 0

                    ScrubValue {
                        id: castDistScrub
                        s: root.s
                        value: Widgets.depth.castDistance
                        openValue: 4
                        from: 0
                        to: 20
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("depth", "castDistance", v)
                    }
                }
                SettingsRow {
                    id: castSoftRow
                    surface: root
                    name: "Shadow softness"
                    sub: "Blur of its edge, × the clock size"
                    captionOnFocus: true
                    icon: "droplet"
                    shown: Widgets.depth.on && Widgets.depth.cut && Widgets.depth.castStrength > 0

                    ScrubValue {
                        id: castSoftScrub
                        s: root.s
                        value: Widgets.depth.castSoftness
                        openValue: 7
                        from: 1
                        to: 15
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("depth", "castSoftness", v)
                    }
                }
                SettingsRow {
                    id: clockLayoutRow
                    surface: root
                    name: "Layout"
                    sub: "Stacked puts hours over minutes"
                    captionOnFocus: true
                    icon: "app-window"
                    shown: Widgets.depth.on

                    SettingsSeg {
                        s: root.s
                        options: root.layoutOptions
                        value: Widgets.depth.layout
                        onPicked: (v) => Widgets.set("depth", "layout", v)
                    }
                }
                SettingsRow {
                    id: clockFontRow
                    surface: root
                    name: "Font"
                    icon: "type"
                    sub: Widgets.depth.font.length > 0 ? Widgets.depth.font : "Shell font (" + Appearance.font.family + ")"
                    shown: Widgets.depth.on

                    GlyphIcon {
                        width: 16 * root.s
                        height: 16 * root.s
                        name: "chevron-right"
                        color: root.focusRowItem === clockFontRow ? Colors.on_surface : Colors.on_surface_variant
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        stroke: 2.2
                    }
                }
                SettingsRow {
                    id: clockFillRow
                    surface: root
                    name: "Fill"
                    icon: "sparkles"
                    shown: Widgets.depth.on

                    SettingsSeg {
                        s: root.s
                        options: root.fillOptions
                        value: Widgets.depth.fill
                        onPicked: (v) => root.setClockFill(v)
                    }
                }
                SettingsRow {
                    id: clockEffectRow
                    surface: root
                    name: "Effect"
                    icon: "sun"
                    shown: Widgets.depth.on

                    SettingsSeg {
                        s: root.s
                        options: root.clockEffectOptions
                        value: Widgets.depth.effect
                        onPicked: (v) => Widgets.set("depth", "effect", v)
                    }
                }
                SettingsRow {
                    id: clockColorRow
                    surface: root
                    name: "Colour"
                    icon: "palette"
                    shown: Widgets.depth.on

                    SettingsSeg {
                        s: root.s
                        options: root.colorOptions
                        value: Widgets.depth.color
                        onPicked: (v) => Widgets.set("depth", "color", v)
                    }
                }
                SettingsRow {
                    id: clockWeightRow
                    surface: root
                    name: "Weight"
                    icon: "type"
                    shown: Widgets.depth.on

                    SettingsSeg {
                        s: root.s
                        options: root.weightOptions
                        value: Widgets.depth.weight
                        onPicked: (v) => Widgets.set("depth", "weight", v)
                    }
                }
                SettingsRow {
                    id: clockColor2Row
                    surface: root
                    name: Widgets.depth.fill === "gradient" ? "Gradient end" : "Echo colour"
                    icon: "palette"
                    shown: Widgets.depth.on && (Widgets.depth.fill === "gradient" || (Widgets.depth.effect === "echo" && Widgets.depth.fill !== "outline"))

                    SettingsSeg {
                        s: root.s
                        options: root.colorOptions
                        value: Widgets.depth.color2
                        onPicked: (v) => Widgets.set("depth", "color2", v)
                    }
                }
                SettingsRow {
                    id: clockTrackRow
                    surface: root
                    name: "Letter spacing"
                    sub: "Negative pulls the numerals together"
                    captionOnFocus: true
                    icon: "type"
                    shown: Widgets.depth.on

                    ScrubValue {
                        id: clockTrackScrub
                        s: root.s
                        value: Widgets.depth.tracking
                        openValue: -3
                        from: -15
                        to: 15
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("depth", "tracking", v)
                    }
                }
                SettingsRow {
                    id: clockAlignRow
                    surface: root
                    name: "Alignment"
                    sub: "Within its box"
                    captionOnFocus: true
                    icon: "app-window"
                    shown: Widgets.depth.on

                    SettingsSeg {
                        s: root.s
                        options: root.clockAlignOptions
                        value: Widgets.depth.align
                        onPicked: (v) => Widgets.set("depth", "align", v)
                    }
                }
                SettingsRow {
                    id: clockDateRow
                    surface: root
                    name: "Date"
                    icon: "clock"
                    shown: Widgets.depth.on

                    SettingsSeg {
                        s: root.s
                        options: root.dateFormatOptions
                        value: Widgets.depth.dateFormat
                        onPicked: (v) => Widgets.set("depth", "dateFormat", v)
                    }
                }
                SettingsRow {
                    id: clockDateColorRow
                    surface: root
                    name: "Date colour"
                    icon: "palette"
                    shown: Widgets.depth.on && Widgets.depth.dateFormat !== "off"

                    SettingsSeg {
                        s: root.s
                        options: root.colorOptions
                        value: Widgets.depth.dateColor
                        onPicked: (v) => Widgets.set("depth", "dateColor", v)
                    }
                }
                SettingsRow {
                    id: clockDateSizeRow
                    surface: root
                    name: "Date size"
                    sub: "Relative to the time"
                    captionOnFocus: true
                    icon: "type"
                    shown: Widgets.depth.on && Widgets.depth.dateFormat !== "off"

                    ScrubValue {
                        id: clockDateSizeScrub
                        s: root.s
                        value: Widgets.depth.dateSize
                        openValue: 16
                        from: 8
                        to: 40
                        step: 1
                        unit: "%"
                        onEdited: v => Widgets.set("depth", "dateSize", v)
                    }
                }
                SettingsRow {
                    id: clockHourRow
                    surface: root
                    name: "Hours"
                    sub: "Auto follows the shell's 12/24 h setting"
                    captionOnFocus: true
                    icon: "clock"
                    shown: Widgets.depth.on

                    SettingsSeg {
                        s: root.s
                        options: root.hourOptions
                        value: Widgets.depth.hour
                        onPicked: (v) => Widgets.set("depth", "hour", v)
                    }
                }
                SettingsRow {
                    id: clockShadowRow
                    surface: root
                    name: "Drop shadow"
                    sub: Widgets.depth.effect === "glow" ? "Not drawn under Glow — it carries its own light" : "Lifts the numerals off bright wallpapers"
                    captionOnFocus: true
                    icon: "sparkles"
                    shown: Widgets.depth.on

                    LinkToggle {
                        s: root.s
                        on: Widgets.depth.shadow
                        onToggled: Widgets.set("depth", "shadow", !Widgets.depth.shadow)
                    }
                }
                SettingsRow {
                    id: clockOpacityRow
                    surface: root
                    name: "Opacity"
                    icon: "eye"
                    shown: Widgets.depth.on
                    last: true

                    ScrubValue {
                        id: clockOpacityScrub
                        s: root.s
                        value: Math.round(Widgets.depth.opacity * 100)
                        openValue: 100
                        from: 20
                        to: 100
                        step: 5
                        unit: "%"
                        onEdited: v => Widgets.set("depth", "opacity", v / 100)
                    }
                }
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
