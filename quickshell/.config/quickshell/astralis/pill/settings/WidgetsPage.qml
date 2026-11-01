pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 景 WIDGETS settings page: the desktop music widgets (cover art,
 * synced lyrics). "Edit layout" opens the full-screen placer
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

    rows: [
        { item: editRow, kind: "toggle", get: function () { return Widgets.editing; }, set: function (v) { Widgets.editing = v; } },
        { item: coverRow, kind: "toggle", get: function () { return Widgets.cover.on; }, set: function (v) { Widgets.set("cover", "on", v); } },
        { item: coverSizeRow, kind: "scrub", bump: function (d) { coverSizeScrub.bump(d); } },
        { item: radiusRow, kind: "seg", vals: root.radiusOptions.map(o => o.value), get: function () { return Widgets.cover.radius; }, set: function (v) { Widgets.set("cover", "radius", v); } },
        { item: haloRow, kind: "toggle", get: function () { return Widgets.cover.halo; }, set: function (v) { Widgets.set("cover", "halo", v); } },
        { item: captionRow, kind: "toggle", get: function () { return Widgets.cover.caption; }, set: function (v) { Widgets.set("cover", "caption", v); } },
        { item: lyricsRow, kind: "toggle", get: function () { return Widgets.lyrics.on; }, set: function (v) { Widgets.set("lyrics", "on", v); } },
        { item: lyrWRow, kind: "scrub", bump: function (d) { lyrWScrub.bump(d); } },
        { item: lyrHRow, kind: "scrub", bump: function (d) { lyrHScrub.bump(d); } },
        { item: sizeRow, kind: "scrub", bump: function (d) { sizeScrub.bump(d); } },
        { item: backdropRow, kind: "seg", vals: root.backdropOptions.map(o => o.value), get: function () { return Widgets.lyrics.backdrop; }, set: function (v) { Widgets.set("lyrics", "backdrop", v); } },
        { item: alignRow, kind: "seg", vals: root.alignOptions.map(o => o.value), get: function () { return Widgets.lyrics.align; }, set: function (v) { Widgets.set("lyrics", "align", v); } },
        { item: glowRow, kind: "toggle", get: function () { return Widgets.lyrics.glow; }, set: function (v) { Widgets.set("lyrics", "glow", v); } },
        { item: blurRow, kind: "toggle", get: function () { return Widgets.lyrics.blur; }, set: function (v) { Widgets.set("lyrics", "blur", v); } }
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

            SettingsGroupLabel { s: root.s; text: "Layout" }

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

            SettingsGroupLabel { s: root.s; text: "Cover art" }

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
                visible: Widgets.cover.on

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
                visible: Widgets.cover.on

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
                visible: Widgets.cover.on

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
                visible: Widgets.cover.on
                last: true

                LinkToggle {
                    s: root.s
                    on: Widgets.cover.caption
                    onToggled: Widgets.set("cover", "caption", !Widgets.cover.caption)
                }
            }

            SettingsGroupLabel { s: root.s; text: "Lyrics" }

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
                visible: Widgets.lyrics.on

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
                visible: Widgets.lyrics.on

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
                visible: Widgets.lyrics.on

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
                visible: Widgets.lyrics.on

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
                visible: Widgets.lyrics.on

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
                visible: Widgets.lyrics.on

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
                visible: Widgets.lyrics.on
                last: true

                LinkToggle {
                    s: root.s
                    on: Widgets.lyrics.blur
                    onToggled: Widgets.set("lyrics", "blur", !Widgets.lyrics.blur)
                }
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
