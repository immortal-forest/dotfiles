import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — Material 3 button, all five container variants.
 *
 *   variant: "filled" | "tonal" | "outlined" | "text" | "elevated"
 *
 * 40dp tall, fully rounded, 24dp of side padding (16 on the leading side once
 * an icon is present), an 18dp icon and 8dp between icon and label — all
 * md-comp-*-button v0.192. Interaction, focus and accessibility come from
 * M3StateLayer, so this file only describes what the button LOOKS like.
 *
 *   M3Button {
 *       s: root.s
 *       variant: "filled"
 *       text: "Record"
 *       icon: "monitor"
 *       onClicked: ScreenRec.start("screen")
 *   }
 */
Item {
    id: btn

    property real s: 1
    property string variant: "filled"
    property string text: ""
    /** GlyphIcon name; empty for a label-only button. */
    property string icon: ""
    /** Screen-reader name. Defaults to the visible label. */
    property string accessibleName: btn.text

    /**
     * M3 Expressive's shape morph: the container un-rounds toward a squarer
     * corner while held, then springs back. It is the single most recognisable
     * "Material 3 Expressive" tell, and it costs one Behavior.
     */
    property bool morphOnPress: true

    signal clicked

    readonly property bool hasIcon: btn.icon.length > 0
    readonly property bool isOutlined: btn.variant === "outlined"
    readonly property bool isFlat: btn.variant === "text" || btn.isOutlined

    // Container and content colours per variant. `text`/`outlined` carry no
    // fill at all, so their state layer does the whole job of showing hover.
    readonly property color containerColor: {
        switch (btn.variant) {
        case "filled":   return Colors.primary;
        case "tonal":    return Colors.secondary_container;
        case "elevated": return Colors.surface_container_low;
        default:         return "transparent";
        }
    }
    readonly property color contentColor: {
        switch (btn.variant) {
        case "filled": return Colors.on_primary;
        case "tonal":  return Colors.on_secondary_container;
        default:       return Colors.primary;
        }
    }

    implicitWidth: row.implicitWidth
        + (btn.hasIcon ? M3.buttonPaddingIcon : M3.buttonPadding) * btn.s
        + M3.buttonPadding * btn.s
    implicitHeight: M3.buttonHeight * btn.s
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        id: container
        anchors.fill: parent
        // Full round at rest, cornerMedium while held (the Expressive morph).
        radius: (btn.morphOnPress && state_.pressed)
            ? M3.cornerMedium * btn.s
            : height / 2
        color: btn.containerColor
        // A disabled container keeps its shape but drops to 12% — M3 never
        // hides a disabled control, it mutes it, so the layout never shifts.
        opacity: btn.enabled ? 1 : (btn.isFlat ? 1 : M3.disabledContainerOpacity)
        border.width: btn.isOutlined ? M3.buttonOutline * btn.s : 0
        border.color: btn.enabled
            ? Colors.outline
            : Qt.alpha(Colors.on_surface, M3.disabledContainerOpacity)

        Behavior on radius {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        // Elevated is the only variant carrying a shadow; the others sit flat
        // on the surface and are separated by colour alone.
        layer.enabled: btn.variant === "elevated"

        Row {
            id: row
            anchors.centerIn: parent
            spacing: btn.hasIcon ? M3.buttonGap * btn.s : 0
            opacity: btn.enabled ? 1 : M3.disabledContentOpacity
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: btn.hasIcon
                width: M3.buttonIconSize * btn.s
                height: M3.buttonIconSize * btn.s
                name: btn.icon
                color: btn.contentColor
                stroke: 1.8
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: btn.text.length > 0
                text: btn.text
                color: btn.contentColor
                // M3 label-large: 14sp / medium.
                font.family: Appearance.font.family
                font.pixelSize: 14 * btn.s
                font.weight: Font.Medium
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        M3StateLayer {
            id: state_
            anchors.fill: parent
            enabled: btn.enabled
            s: btn.s
            radius: container.radius
            contentColor: btn.contentColor
            // The container already carries the Expressive corner morph; a dip
            // on top of it reads as two separate reactions to one press.
            pressScale: btn.morphOnPress ? 0 : 0.96
            minTarget: M3.buttonHeight
            accessibleRole: Accessible.Button
            accessibleName: btn.accessibleName
            onClicked: btn.clicked()
        }
    }
}
