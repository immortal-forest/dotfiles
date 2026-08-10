pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 相 APPEARANCE settings page (ported from Ricelin
 * pill/Appearance.qml): the clock format and seconds, the Japanese-glyph
 * toggle that gates every surface header, the music visualizer, the UI scale
 * and a reduce-motion switch, then a nav row into the font picker. All of it
 * backs onto the Flags singleton (persisted flags.json), so every choice
 * lands live shell-wide and survives a daemon restart.
 *
 * Ricelin delta: the palette rows (static/dynamic/manual + the manual hue
 * strip, wallcolors.py backend) are dropped — matugen owns the astralis
 * palette end-to-end (wallpaper → Colors.json). TODO(follow-up): a matugen
 * SCHEME seg (scheme-vibrant / tonal-spot / content re-run on the current
 * wallpaper) can take that row's place.
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    rows: {
        var r = [
            { item: timeRow, kind: "seg", vals: [false, true], get: function () { return Flags.time12h; }, set: function (v) { Flags.time12h = v; } },
            { item: secRow, kind: "toggle", get: function () { return Flags.clockSeconds; }, set: function (v) { Flags.clockSeconds = v; } },
            { item: glyphRow, kind: "toggle", get: function () { return Flags.showGlyphs; }, set: function (v) { Flags.showGlyphs = v; } },
            { item: colorRow, kind: "seg", vals: ["subtle", "balanced", "bold"], get: function () { return Flags.uiColor; }, set: function (v) { Flags.uiColor = v; } },
            { item: wallRow, kind: "seg", vals: ["faithful", "balanced", "vivid"], get: function () { return Flags.wallReseed; }, set: function (v) { Flags.wallReseed = v; } },
            { item: paletteRow, kind: "seg", vals: ["material", "vivid", "authentic"], get: function () { return Flags.paletteMode; }, set: function (v) { Flags.paletteMode = v; } }
        ];
        // Shell-scope toggle only makes sense once a base16 mode is picked —
        // dropped from the keyboard-nav registry entirely while Material is
        // active, mirroring LookPage's conditional blur-detail rows.
        if (Flags.paletteMode !== "material")
            r.push({ item: base16Row, kind: "toggle", get: function () { return Flags.base16Shell; }, set: function (v) { Flags.base16Shell = v; } });
        r.push(
            { item: vizRow, kind: "toggle", get: function () { return Flags.musicViz; }, set: function (v) { Flags.musicViz = v; } },
            { item: scaleRow, kind: "seg", vals: [0.9, 1.0, 1.1, 1.25], get: function () { return Flags.uiScale; }, set: function (v) { Flags.uiScale = v; } },
            { item: motionRow, kind: "toggle", get: function () { return Flags.reduceMotion; }, set: function (v) { Flags.reduceMotion = v; } },
            { item: fontRow, kind: "nav", surface: "fontpicker" }
        );
        return r;
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "相"
        title: "APPEARANCE"
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

            SettingsRow {
                id: timeRow
                surface: root
                name: "Time format"
                icon: "clock"

                SettingsSeg {
                    s: root.s
                    options: [{ label: "24H", value: false }, { label: "12H", value: true }]
                    value: Flags.time12h
                    onPicked: (v) => Flags.time12h = v
                }
            }

            SettingsRow {
                id: secRow
                surface: root
                name: "Clock seconds"
                icon: "stopwatch"

                LinkToggle {
                    s: root.s
                    on: Flags.clockSeconds
                    onToggled: Flags.clockSeconds = !Flags.clockSeconds
                }
            }

            SettingsRow {
                id: glyphRow
                surface: root
                name: "Japanese glyphs"
                icon: "language"

                LinkToggle {
                    s: root.s
                    on: Flags.showGlyphs
                    onToggled: Flags.showGlyphs = !Flags.showGlyphs
                }
            }

            SettingsRow {
                id: colorRow
                surface: root
                name: "Colorfulness"
                sub: "How boldly the wallpaper accent colors the shell"
                captionOnFocus: true
                icon: "droplet"

                SettingsSeg {
                    s: root.s
                    options: [{ label: "Subtle", value: "subtle" }, { label: "Balanced", value: "balanced" }, { label: "Bold", value: "bold" }]
                    value: Flags.uiColor
                    onPicked: (v) => Flags.uiColor = v
                }
            }

            SettingsRow {
                id: wallRow
                surface: root
                name: "Wallpaper boost"
                sub: "Lift color from muted or grayscale wallpapers"
                captionOnFocus: true
                icon: "palette"

                SettingsSeg {
                    s: root.s
                    options: [{ label: "Faithful", value: "faithful" }, { label: "Balanced", value: "balanced" }, { label: "Vivid", value: "vivid" }]
                    value: Flags.wallReseed
                    onPicked: (v) => Flags.wallReseed = v
                }
            }

            SettingsRow {
                id: paletteRow
                surface: root
                name: "Palette"
                sub: "Base16 recolors terminal, browser and Spotify to match"
                captionOnFocus: true
                icon: "sparkles"

                SettingsSeg {
                    s: root.s
                    options: [{ label: "Material", value: "material" }, { label: "Vivid", value: "vivid" }, { label: "Pywal", value: "authentic" }]
                    value: Flags.paletteMode
                    onPicked: (v) => Flags.paletteMode = v
                }
            }

            SettingsRow {
                id: base16Row
                surface: root
                name: "Flip the pill to base16 too"
                sub: "Recolor the shell itself, not just apps"
                captionOnFocus: true
                icon: "monitor"
                visible: Flags.paletteMode !== "material"

                LinkToggle {
                    s: root.s
                    on: Flags.base16Shell
                    onToggled: Flags.base16Shell = !Flags.base16Shell
                }
            }

            SettingsRow {
                id: vizRow
                surface: root
                name: "Music visualizer"
                icon: "music"

                LinkToggle {
                    s: root.s
                    on: Flags.musicViz
                    onToggled: Flags.musicViz = !Flags.musicViz
                }
            }

            SettingsRow {
                id: scaleRow
                surface: root
                name: "UI scale"
                icon: "scaling"

                SettingsSeg {
                    s: root.s
                    options: [{ label: "90%", value: 0.9 }, { label: "100%", value: 1.0 }, { label: "110%", value: 1.1 }, { label: "125%", value: 1.25 }]
                    value: Flags.uiScale
                    onPicked: (v) => Flags.uiScale = v
                }
            }

            SettingsRow {
                id: motionRow
                surface: root
                name: "Reduce motion"
                icon: "waves"

                LinkToggle {
                    s: root.s
                    on: Flags.reduceMotion
                    onToggled: Flags.reduceMotion = !Flags.reduceMotion
                }
            }

            SettingsRow {
                id: fontRow
                surface: root
                name: "Font"
                icon: "type"
                sub: Flags.uiFont.length > 0 ? Flags.uiFont : Appearance.font.family
                last: true

                GlyphIcon {
                    width: 16 * root.s
                    height: 16 * root.s
                    name: "chevron-right"
                    color: root.focusRowItem === fontRow ? Colors.on_surface : Colors.on_surface_variant
                    stroke: 1.9
                }
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
