import QtQuick
import "../services"

/**
 * astralis — static design tokens (rounding, spacing, sizing, fonts,
 * elevation). Motion (durations/curves) lives separately in
 * services/Motion.qml. Instantiated once by the Appearance singleton facade;
 * consumers read grouped tokens: `Appearance.rounding.large`,
 * `Appearance.spacing.m`, `Appearance.font.family`, `Appearance.elevation.*`.
 *
 * One token is live, not static: `font.family` follows Flags.uiFont (the
 * 字 FONT picker's pick, persisted in flags.json), falling back to the
 * bundled `familyDefault` while unset — so a font pick re-renders the whole
 * shell at once, Ricelin's Theme.font contract.
 */
QtObject {
    readonly property QtObject rounding: QtObject {
        readonly property real small:    7
        readonly property real medium:   13
        readonly property real large:    20
        readonly property real pill:     18     // resting pill corner
        readonly property real pillOpen: 22     // expanded surface corner
        readonly property real full:     9999
    }
    readonly property QtObject spacing: QtObject {
        readonly property real xs: 4
        readonly property real s:  8
        readonly property real m:  12
        readonly property real l:  16
        readonly property real xl: 24
    }
    readonly property QtObject padding: QtObject {
        readonly property real tile:    12
        readonly property real surface: 16
        readonly property real header:  14
    }
    readonly property QtObject font: QtObject {
        readonly property string familyDefault: "Inter"
        readonly property string family:  Flags.uiFont.length > 0 ? Flags.uiFont : familyDefault
        readonly property string mono:    "JetBrainsMono Nerd Font"
        readonly property string symbols: "Material Symbols Rounded"
        readonly property string jp:      "Noto Sans CJK JP"   // surface kanji (Ricelin fontJp)
        readonly property int size:   13
        readonly property int sizeS:  11
        readonly property int sizeL:  16
        readonly property int sizeXL: 22
    }
    readonly property QtObject elevation: QtObject {
        readonly property real restBlur:      18
        readonly property real openBlur:      32
        readonly property real shadowOpacity: 0.5
    }
}
