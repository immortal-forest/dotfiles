pragma Singleton
import QtQuick
import Quickshell

/**
 * astralis — appearance facade. Exposes the static design tokens
 * (AppearanceConfig) shell-wide as `Appearance.rounding.*`,
 * `Appearance.spacing.*`, `Appearance.padding.*`, `Appearance.font.*`,
 * `Appearance.elevation.*`. Motion (durations/curves) is a separate singleton
 * (services/Motion.qml).
 */
Singleton {
    id: root
    readonly property AppearanceConfig tokens: AppearanceConfig {}

    // hoist the groups so consumers read Appearance.rounding.large, etc.
    readonly property QtObject rounding:  tokens.rounding
    readonly property QtObject spacing:   tokens.spacing
    readonly property QtObject padding:   tokens.padding
    readonly property QtObject font:      tokens.font
    readonly property QtObject elevation: tokens.elevation
}
