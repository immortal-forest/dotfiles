import QtQuick
import "../../colors"
import "../../config"

/**
 * astralis — settings section header. The uppercase, letter-spaced group
 * label that sits above a run of SettingsRow lines (Motion / Curve / Window /
 * Pointer …). Extracted verbatim from the per-page `component GroupLabel` the
 * Animation / Look / Input / Workspaces pages each re-declared; callers pass
 * `s` for scale and `text` for the label.
 */
Text {
    property real s: 1
    topPadding: 16 * s
    bottomPadding: 6 * s
    leftPadding: 12 * s
    color: Qt.alpha(Colors.on_surface_variant, 0.65)
    font.family: Appearance.font.family
    font.pixelSize: 8.5 * s
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1.2 * s
}
