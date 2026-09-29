import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — Material 3 card, all three container variants.
 *
 *   variant: "elevated" | "filled" | "outlined"
 *
 * 12dp corner (md-comp-card v0.192's corner-medium). A card is a CONTAINER by
 * default, not a button — `interactive: false` renders bare content with no
 * hover, no press feedback and no Tab stop, because most cards in a dashboard
 * are display surfaces (a stat tile, a media art frame) that happen to sit on
 * a rounded rect, not affordances. Only `interactive: true` hosts the
 * M3StateLayer that makes it act — and read to a screen reader — like one;
 * gating the state layer's own `enabled` on `interactive` is what keeps a
 * plain card from stealing keyboard focus or lighting up on hover.
 *
 *   M3Card {
 *       s: root.s
 *       variant: "elevated"
 *       interactive: true
 *       accessibleName: "Open notification"
 *       onClicked: ...
 *       ColumnLayout { anchors.fill: parent; ... }
 *   }
 */
Item {
    id: card

    property real s: 1
    property string variant: "filled"
    property bool interactive: false
    property string accessibleName: ""
    default property alias content: contentSlot.data

    signal clicked

    readonly property bool isOutlined: card.variant === "outlined"
    readonly property bool isElevated: card.variant === "elevated"

    // Container colour per variant. Outlined sits directly on `surface` and
    // relies on its border for definition; filled and elevated both need a
    // tonal container colour to read as raised above the page.
    readonly property color containerColor: {
        switch (card.variant) {
        case "elevated": return Colors.surface_container_low;
        case "outlined": return Colors.surface;
        default:         return Colors.surface_container_highest;
        }
    }

    Rectangle {
        id: container
        anchors.fill: parent
        radius: M3.cardCorner * card.s
        color: card.containerColor
        // Muted, not hidden — a disabled card keeps its footprint so the
        // layout around it never reflows.
        opacity: card.enabled ? 1 : M3.disabledContainerOpacity
        border.width: card.isOutlined ? M3.cardOutline * card.s : 0
        border.color: card.enabled
            ? Colors.outline_variant
            : Qt.alpha(Colors.on_surface, M3.disabledContainerOpacity)

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        // Elevated is the only variant that lifts off the page; filled and
        // outlined stay flat and read via colour/border alone — same split
        // M3Button draws between its own "elevated" and everything else.
        layer.enabled: card.isElevated

        Item {
            id: contentSlot
            anchors.fill: parent
            opacity: card.enabled ? 1 : M3.disabledContentOpacity
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }

        // Always instantiated (matching M3Button/M3IconButton's shape), but
        // `enabled` folds in `interactive` — QtQuick blocks hover, press AND
        // keyboard-focus delivery to a disabled Item and everything under it,
        // which is what actually keeps a non-interactive card inert rather
        // than merely undrawn.
        M3StateLayer {
            anchors.fill: parent
            enabled: card.interactive && card.enabled
            s: card.s
            radius: container.radius
            contentColor: Colors.on_surface
            pressScale: 0.96
            accessibleRole: Accessible.Button
            accessibleName: card.accessibleName
            onClicked: card.clicked()
        }
    }
}
