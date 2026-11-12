import QtQuick
import "../../colors"
import "../../config"
import "../../services"

/**
 * astralis — settings section header. The uppercase, letter-spaced group
 * label that sits above a run of SettingsRow lines (Motion / Curve / Window /
 * Pointer …). Extracted verbatim from the per-page `component GroupLabel` the
 * Animation / Look / Input / Workspaces pages each re-declared; callers pass
 * `s` for scale and `text` for the label.
 *
 * `shown: cond` (instead of `visible: cond`) folds the label away with the
 * same height-ease + fade as a SettingsRow, so a section that toggles glides
 * shut with its rows. Pass `surface` (the owning SettingsPage) so the first
 * layout after the page activates snaps instead of animating.
 */
Text {
    id: lbl

    property real s: 1
    property bool shown: true
    property var surface: null

    topPadding: 16 * s
    bottomPadding: 6 * s
    leftPadding: 12 * s
    color: Qt.alpha(Colors.on_surface_variant, 0.65)
    font.family: Appearance.font.family
    font.pixelSize: 8.5 * s
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1.2 * s

    property bool settled: false
    readonly property bool animate: lbl.settled && (lbl.surface ? lbl.surface.hoverArmed : true)
    Component.onCompleted: Qt.callLater(() => lbl.settled = true)

    property real shownT: lbl.shown ? 1 : 0
    Behavior on shownT {
        enabled: lbl.animate
        NumberAnimation {
            duration: lbl.shown ? Motion.normalDur : Motion.expressiveFastSpatialDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.emphasized
        }
    }
    height: implicitHeight * lbl.shownT
    clip: lbl.shownT < 0.999
    opacity: lbl.shown ? 1 : 0
    // Opacity gates visibility (never height): a hidden item drops out of its
    // Column's layout and could not grow back.
    visible: lbl.shown || lbl.opacity > 0.01
    Behavior on opacity {
        enabled: lbl.animate
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }
}
