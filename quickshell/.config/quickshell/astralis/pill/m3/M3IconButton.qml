import QtQuick
import ".."
import "../../colors"
import "../../services"

/**
 * astralis — Material 3 icon button, all four variants.
 *
 *   variant: "standard" | "filled" | "tonal" | "outlined"
 *
 * A 40dp state-layer square holding a 24dp glyph (md-comp-icon-button v0.192).
 * `toggle: true` makes it a toggle button — `checked` then selects the "on"
 * colour pair and the control reports itself to a screen reader as checkable,
 * which is what the transport buttons, the mute button and the DND switch all
 * actually are.
 *
 *   M3IconButton {
 *       s: root.s
 *       variant: "tonal"
 *       icon: "mic"
 *       toggle: true
 *       checked: !Flags.recordMic
 *       accessibleName: "Microphone"
 *       onClicked: Flags.recordMic = !Flags.recordMic
 *   }
 */
Item {
    id: ibtn

    property real s: 1
    property string variant: "standard"
    property string icon: ""
    property real iconSize: M3.iconButtonIconSize
    property real stroke: 1.8

    /** Toggle behaviour: `checked` drives the selected colour pair. */
    property bool toggle: false
    property bool checked: false

    property string accessibleName: ""
    property string accessibleDescription: ""

    /** Optional tint override — the error red for a destructive action. */
    property color accent: Colors.primary

    signal clicked

    readonly property bool selected: ibtn.toggle && ibtn.checked
    readonly property bool isOutlined: ibtn.variant === "outlined"

    readonly property color containerColor: {
        if (ibtn.variant === "filled")
            return ibtn.selected || !ibtn.toggle ? ibtn.accent : Colors.surface_container_highest;
        if (ibtn.variant === "tonal")
            return ibtn.selected || !ibtn.toggle
                ? Colors.secondary_container : Colors.surface_container_highest;
        // standard + outlined are transparent; their state layer shows hover.
        return "transparent";
    }
    readonly property color contentColor: {
        if (ibtn.variant === "filled")
            return ibtn.selected || !ibtn.toggle ? Colors.on_primary : Colors.on_surface_variant;
        if (ibtn.variant === "tonal")
            return ibtn.selected || !ibtn.toggle
                ? Colors.on_secondary_container : Colors.on_surface_variant;
        // A standard toggle marks its on-state with the accent alone.
        return ibtn.selected ? ibtn.accent : Colors.on_surface_variant;
    }

    implicitWidth: M3.iconButtonSize * ibtn.s
    implicitHeight: M3.iconButtonSize * ibtn.s
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        id: container
        anchors.fill: parent
        radius: width / 2
        color: ibtn.containerColor
        opacity: ibtn.enabled ? 1 : M3.disabledContainerOpacity
        border.width: ibtn.isOutlined ? M3.buttonOutline * ibtn.s : 0
        border.color: ibtn.enabled
            ? (ibtn.selected ? "transparent" : Colors.outline)
            : Qt.alpha(Colors.on_surface, M3.disabledContainerOpacity)

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        GlyphIcon {
            anchors.centerIn: parent
            width: ibtn.iconSize * ibtn.s
            height: ibtn.iconSize * ibtn.s
            name: ibtn.icon
            color: ibtn.contentColor
            stroke: ibtn.stroke
            opacity: ibtn.enabled ? 1 : M3.disabledContentOpacity
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }

        M3StateLayer {
            anchors.fill: parent
            enabled: ibtn.enabled
            s: ibtn.s
            radius: container.radius
            contentColor: ibtn.contentColor
            // Small round target — the shell's deep dip.
            pressScale: 0.92
            minTarget: M3.iconButtonSize
            accessibleRole: ibtn.toggle ? Accessible.CheckBox : Accessible.Button
            accessibleName: ibtn.accessibleName
            accessibleDescription: ibtn.accessibleDescription
            accessibleCheckable: ibtn.toggle
            accessibleChecked: ibtn.checked
            onClicked: ibtn.clicked()
        }
    }
}
