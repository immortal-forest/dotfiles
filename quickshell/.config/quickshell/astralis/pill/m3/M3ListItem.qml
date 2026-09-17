import QtQuick
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — Material 3 list item: leading slot, headline + supporting text,
 * trailing slot, on one of the spec's three heights (56 / 72 / 88dp).
 *
 * The height is DERIVED, not requested. `lines` counts itself from what you
 * actually filled in — a headline alone is one line, adding `supporting` makes
 * it two, and letting the supporting text wrap past two lines makes it three.
 * A `lines` property the caller had to keep in sync with the text it passed is
 * the thing that goes stale the first time a translation gets longer, so the
 * component reads the content instead of being told about it.
 *
 * `interactive` follows M3Card's split, for the same reason: most list items
 * in this shell are read-only rows (a device in a list, a package in an update
 * summary) and a row that lights up under the cursor while doing nothing when
 * clicked is a lie about affordance. Only `interactive: true` gets the state
 * layer, the press dip, the Tab stop and the Button role.
 *
 *   M3ListItem {
 *       s: root.s
 *       headline: dev.name
 *       supporting: dev.address
 *       interactive: true
 *       onClicked: dev.connect()
 *       leading: GlyphIcon { name: "bluetooth" }
 *       trailing: M3Switch { checked: dev.connected }
 *   }
 */
Item {
    id: item

    property real s: 1

    property string headline: ""
    property string supporting: ""
    property string overline: ""

    /** Content slots. Sized by the item; anchor inside them, do not position. */
    property Component leading: null
    property Component trailing: null

    property bool interactive: false
    property bool selected: false

    property string accessibleName: ""
    property string accessibleDescription: ""

    signal clicked

    /**
     * 1, 2 or 3 — counted from the content, then from how far the supporting
     * text actually wrapped. `supportText.lineCount` is only meaningful once
     * the Text has laid out, hence the `> 0` guard: during the first frame it
     * reads 0 and would otherwise collapse a two-line row to one for a frame
     * and visibly pop.
     */
    readonly property int lines: {
        if (item.supporting.length === 0 && item.overline.length === 0)
            return 1;
        if (supportText.lineCount > 1)
            return 3;
        return 2;
    }

    readonly property real rowHeight: {
        switch (item.lines) {
        case 1: return M3.listItemOneLine;
        case 2: return M3.listItemTwoLine;
        default: return M3.listItemThreeLine;
        }
    }

    width: parent ? parent.width : 0
    height: item.rowHeight * item.s

    // Settling first, animating after: the first layout must snap into place,
    // or every list would grow its rows in on open. Same latch SettingsRow
    // uses, for the same reason.
    property bool settled: false
    Component.onCompleted: Qt.callLater(() => item.settled = true)
    Behavior on height {
        enabled: item.settled
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    Rectangle {
        id: container
        anchors.fill: parent
        radius: M3.cornerMedium * item.s
        // Selection is a container-level tint (M3's secondary_container), NOT
        // a state-layer opacity — a selected row must stay visibly selected
        // while the cursor is somewhere else entirely, which a state layer by
        // definition cannot do.
        color: item.selected ? Colors.secondary_container : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Item {
            id: leadingSlot
            anchors.left: parent.left
            anchors.leftMargin: M3.listItemPadding * item.s
            anchors.verticalCenter: parent.verticalCenter
            width: item.leading ? Math.max(childrenRect.width, M3.iconButtonIconSize * item.s) : 0
            height: item.leading ? Math.max(childrenRect.height, M3.iconButtonIconSize * item.s) : 0
            opacity: item.enabled ? 1 : M3.disabledContentOpacity

            Loader {
                anchors.centerIn: parent
                sourceComponent: item.leading
            }
        }

        Item {
            id: trailingSlot
            anchors.right: parent.right
            anchors.rightMargin: M3.listItemPadding * item.s
            anchors.verticalCenter: parent.verticalCenter
            width: item.trailing ? childrenRect.width : 0
            height: item.trailing ? childrenRect.height : 0
            opacity: item.enabled ? 1 : M3.disabledContentOpacity

            Loader {
                anchors.centerIn: parent
                sourceComponent: item.trailing
            }
        }

        Column {
            id: textCol
            anchors.left: leadingSlot.right
            anchors.leftMargin: item.leading ? M3.listItemSpace * item.s : 0
            anchors.right: trailingSlot.left
            anchors.rightMargin: item.trailing ? M3.listItemSpace * item.s : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2 * item.s
            opacity: item.enabled ? 1 : M3.disabledContentOpacity
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            Text {
                width: parent.width
                visible: item.overline.length > 0
                text: item.overline
                color: Colors.on_surface_variant
                elide: Text.ElideRight
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * item.s
                font.weight: Font.Medium
                font.letterSpacing: 0.5 * item.s
                font.capitalization: Font.AllUppercase
            }

            Text {
                width: parent.width
                text: item.headline
                color: item.selected ? Colors.on_secondary_container : Colors.on_surface
                elide: Text.ElideRight
                font.family: Appearance.font.family
                font.pixelSize: 12.5 * item.s
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Text {
                id: supportText
                width: parent.width
                visible: item.supporting.length > 0
                text: item.supporting
                // 0.85, not 0.65 — the supporting line renders over
                // secondary_container when the row is selected, where a
                // lighter alpha drops under 4.5:1 at this size.
                color: item.selected
                    ? Qt.alpha(Colors.on_secondary_container, 0.85)
                    : Qt.alpha(Colors.on_surface_variant, 0.85)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 1.2
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * item.s
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        // Ordered LAST so it sits above the text but below nothing — a
        // trailing M3Switch is a child of trailingSlot, which is declared
        // earlier, so the switch's own MouseArea would lose the hit test to
        // this one. `z` fixes that without reordering the visual stack.
        M3StateLayer {
            anchors.fill: parent
            z: -1
            enabled: item.interactive && item.enabled
            s: item.s
            radius: container.radius
            contentColor: item.selected ? Colors.on_secondary_container : Colors.on_surface
            pressScale: 0.99
            minTarget: 0
            accessibleRole: Accessible.ListItem
            accessibleName: item.accessibleName.length > 0 ? item.accessibleName : item.headline
            accessibleDescription: item.accessibleDescription.length > 0
                ? item.accessibleDescription
                : item.supporting
            onClicked: item.clicked()
        }
    }
}
