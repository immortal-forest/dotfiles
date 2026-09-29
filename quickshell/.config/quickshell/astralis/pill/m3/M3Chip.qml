import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — Material 3 chip, all four kinds.
 *
 *   kind: "assist" | "filter" | "input" | "suggestion"
 *
 * 32dp tall with `cornerSmall` (8dp) rounding — chips are the one M3 control
 * that is deliberately NOT fully round, and reaching for `height/2` here is
 * the single most common way to get this component wrong (md-comp-chip
 * v0.192).
 *
 * The filter chip's signature is the leading check that appears on
 * selection and shoves the label over to make room. That is built from two
 * independent pieces rather than one width tween: the leading icon's slot
 * WIDTH jumps instantly (0 ↔ `chipIconSize + chipGap`), but `row`'s `move`
 * transition eases the LABEL's resulting x instead of letting it snap — that
 * easing is what actually reads as a slide. The chip's own outer `width`
 * carries a second, independent `Motion.standard` Behavior so a Row/Flow of
 * several chips glides its neighbours into their new slots too, rather than
 * having them jump the instant one chip is selected.
 *
 *   M3Chip {
 *       s: root.s
 *       kind: "filter"
 *       text: "Wired"
 *       selected: Flags.netFilter === "wired"
 *       onClicked: Flags.netFilter = "wired"
 *   }
 */
Item {
    id: chip

    property real s: 1
    property string kind: "filter"
    property string text: ""
    /** Leading GlyphIcon name. Ignored once a filter chip is selected — the
     *  check glyph takes the one leading-icon slot M3 allows. */
    property string icon: ""
    /** Filter chips only; ignored by the other three kinds. */
    property bool selected: false
    /** Input chips only: shows a trailing × and emits `removed`. */
    property bool removable: false
    property string accessibleName: text

    signal clicked
    signal removed

    readonly property bool isFilter: chip.kind === "filter"
    readonly property bool isSelected: chip.isFilter && chip.selected
    readonly property bool showLeading: chip.isSelected || chip.icon.length > 0
    readonly property string leadingGlyph: chip.isSelected ? "check" : chip.icon
    readonly property bool showTrailing: chip.kind === "input" && chip.removable

    implicitWidth: M3.chipPadding * 2 * chip.s + row.implicitWidth
    implicitHeight: M3.chipHeight * chip.s
    width: implicitWidth
    height: implicitHeight
    Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    Rectangle {
        id: container
        anchors.fill: parent
        radius: M3.cornerSmall * chip.s
        color: chip.isSelected ? Colors.secondary_container : "transparent"
        // Outline drops to 0 the moment the fill takes over — a border on
        // top of a filled container would double up as a seam.
        border.width: chip.isSelected ? 0 : M3.chipOutline * chip.s
        border.color: Colors.outline
        opacity: chip.enabled ? 1 : M3.disabledContainerOpacity

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        // Whole-chip interaction, declared first so it paints BELOW `row` —
        // the trailing remove control nested inside `row` needs to win the
        // hit test over this in its own small area, not have its click
        // swallowed as a chip-wide select/toggle.
        M3StateLayer {
            id: state_
            anchors.fill: parent
            enabled: chip.enabled
            s: chip.s
            radius: container.radius
            contentColor: chip.isSelected ? Colors.on_secondary_container : Colors.on_surface_variant
            pressScale: 0.96
            accessibleRole: chip.isFilter ? Accessible.CheckBox : Accessible.Button
            accessibleCheckable: chip.isFilter
            accessibleChecked: chip.selected
            accessibleName: chip.accessibleName
            onClicked: chip.clicked()
        }

        // Its own clip scope, kept separate from `state_`'s subtree above,
        // so the focus ring — which M3StateLayer deliberately draws OUTSIDE
        // the container via negative margins — is never cut off by the mask
        // that keeps `row`'s transient overflow inside the chip's edge while
        // `chip.width` (above) eases toward its new target.
        Item {
            anchors.fill: parent
            clip: true

            Row {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: M3.chipPadding * chip.s
                spacing: 0
                opacity: chip.enabled ? 1 : M3.disabledContentOpacity
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                // The label's half of the check-in signature — see the file
                // header. Fires whenever a sibling's resize moves this
                // item's target x, which is exactly the leading slot
                // opening/closing.
                move: Transition {
                    NumberAnimation { properties: "x"; duration: Motion.standard; easing.type: Motion.easeStandard }
                }

                Item {
                    id: leading
                    // The slot's width bakes in its OWN trailing gap so a
                    // bare `spacing: 0` Row still collapses to exactly zero
                    // — a Row-level `spacing` would still have inserted a
                    // gap next to a zero-width, un-hideable child.
                    width: chip.showLeading ? (M3.chipIconSize + M3.chipGap) * chip.s : 0
                    height: M3.chipIconSize * chip.s
                    clip: true

                    GlyphIcon {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: M3.chipIconSize * chip.s
                        height: width
                        name: chip.leadingGlyph
                        color: chip.isSelected ? Colors.on_secondary_container : Colors.on_surface_variant
                        stroke: 1.8
                        opacity: chip.showLeading ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: chip.text.length > 0
                    text: chip.text
                    color: chip.isSelected ? Colors.on_secondary_container : Colors.on_surface_variant
                    // M3 label-large: 14sp / medium — same as M3Button's label.
                    font.family: Appearance.font.family
                    font.pixelSize: 14 * chip.s
                    font.weight: Font.Medium
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                Item {
                    id: trailing
                    // Same fold-the-gap-into-the-slot trick as `leading`.
                    width: chip.showTrailing ? (M3.chipGap + M3.chipIconSize) * chip.s : 0
                    height: M3.chipIconSize * chip.s
                    clip: true

                    GlyphIcon {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: M3.chipIconSize * chip.s
                        height: width
                        name: "close"
                        color: chip.isSelected ? Colors.on_secondary_container : Colors.on_surface_variant
                        stroke: 1.8
                    }

                    // Its own small state layer with its own accessible name
                    // — "remove" is a different action than "select this
                    // chip", so it cannot share `state_` above. `enabled` is
                    // gated on `showTrailing` too: `clip: true` on this Item
                    // only hides the MouseArea visually when the slot is
                    // collapsed, it does not stop it from receiving events,
                    // so without this an invisible remove target would sit
                    // wherever the collapsed slot landed in the row.
                    M3StateLayer {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: M3.chipIconSize * chip.s
                        height: width
                        radius: width / 2
                        enabled: chip.enabled && chip.showTrailing
                        s: chip.s
                        contentColor: chip.isSelected ? Colors.on_secondary_container : Colors.on_surface_variant
                        pressScale: 0.96
                        accessibleRole: Accessible.Button
                        accessibleName: "Remove " + chip.accessibleName
                        onClicked: chip.removed()
                    }
                }
            }
        }
    }
}
