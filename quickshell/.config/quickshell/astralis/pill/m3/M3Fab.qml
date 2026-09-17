import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — Material 3 floating action button, all three sizes and four
 * colour variants, plain or extended (md-comp-fab v0.192).
 *
 *   size: "small" | "medium" | "large"
 *   variant: "primary" | "secondary" | "tertiary" | "surface"
 *
 * A FAB is a ROUNDED SQUARE in M3, not the circle every pre-Expressive mental
 * model reaches for — `fabCorner` (16dp) at small/medium, `cornerExtraLarge`
 * (28dp) once `size: "large"` pushes the box to 96dp and the glyph to 36dp.
 * Setting `text` makes it EXTENDED: the box stops growing taller and instead
 * widens to hug icon + label, and per spec the extended shape never inherits
 * the large FAB's extra-large corner — only the plain, icon-only large FAB
 * gets that treatment; extended always keeps the 16dp `fabCorner`.
 *
 *   M3Fab {
 *       s: root.s
 *       variant: "primary"
 *       icon: "record"
 *       text: ScreenRec.active ? "Stop" : "Record"
 *       onClicked: ScreenRec.toggle()
 *   }
 */
Item {
    id: fab

    property real s: 1
    property string size: "medium"
    property string variant: "primary"
    property string icon: ""
    /** Non-empty makes this an EXTENDED fab: a pill hugging icon + label. */
    property string text: ""
    property string accessibleName: fab.text

    signal clicked

    readonly property bool isExtended: fab.text.length > 0
    readonly property bool isLarge: fab.size === "large"
    readonly property bool hasIcon: fab.icon.length > 0

    readonly property real boxSize: {
        switch (fab.size) {
        case "small": return M3.fabSmall;
        case "large": return M3.fabLarge;
        default:      return M3.fabMedium;
        }
    }
    // M3.qml's fabIconSize comment notes "36 on large" but doesn't expose it
    // as its own constant — inlined here rather than invented elsewhere.
    readonly property real iconSize: fab.isLarge ? M3.fabIconSizeLarge : M3.fabIconSize
    // Extended never takes the large FAB's extra-large corner — only the
    // plain (icon-only) large FAB does; see file header.
    readonly property real corner: (fab.isLarge && !fab.isExtended)
        ? M3.cornerExtraLarge
        : M3.fabCorner

    // md-comp-extended-fab has no entry in M3.qml at all (only the square FAB
    // does) — both numbers below come straight from this component's brief,
    // same v0.192 spec family as fabCorner/fabIconSize.
    readonly property real extendedGap:     M3.fabExtendedGap
    readonly property real extendedPadding: M3.fabExtendedPadding

    readonly property color containerColor: {
        switch (fab.variant) {
        case "secondary": return Colors.secondary_container;
        case "tertiary":  return Colors.tertiary_container;
        case "surface":   return Colors.surface_container_high;
        default:          return Colors.primary_container;
        }
    }
    readonly property color contentColor: {
        switch (fab.variant) {
        case "secondary": return Colors.on_secondary_container;
        case "tertiary":  return Colors.on_tertiary_container;
        case "surface":   return Colors.primary;
        default:          return Colors.on_primary_container;
        }
    }

    implicitWidth: fab.isExtended
        ? row.implicitWidth + fab.extendedPadding * 2 * fab.s
        : fab.boxSize * fab.s
    implicitHeight: fab.boxSize * fab.s
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        id: container
        anchors.fill: parent
        radius: fab.corner * fab.s
        color: fab.containerColor
        opacity: fab.enabled ? 1 : M3.disabledContainerOpacity

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on radius { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        // A FAB is the single most elevated thing on any surface it sits on
        // — unlike M3Button/M3IconButton, this shadow is never conditional.
        layer.enabled: true

        Row {
            id: row
            anchors.centerIn: parent
            // Icon-only, label-only and icon+label extended FABs are all
            // valid per spec; the gap only exists when both are present.
            spacing: (fab.isExtended && fab.hasIcon) ? fab.extendedGap * fab.s : 0
            opacity: fab.enabled ? 1 : M3.disabledContentOpacity
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: fab.hasIcon
                width: fab.iconSize * fab.s
                height: fab.iconSize * fab.s
                name: fab.icon
                color: fab.contentColor
                stroke: 1.8
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: fab.isExtended
                text: fab.text
                color: fab.contentColor
                // M3 label-large: 14sp / medium — same scale M3Button uses.
                font.family: Appearance.font.family
                font.pixelSize: 14 * fab.s
                font.weight: Font.Medium
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        M3StateLayer {
            anchors.fill: parent
            enabled: fab.enabled
            s: fab.s
            radius: container.radius
            contentColor: fab.contentColor
            pressScale: 0.94
            accessibleRole: Accessible.Button
            accessibleName: fab.accessibleName
            onClicked: fab.clicked()
        }
    }
}
