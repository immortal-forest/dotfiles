pragma ComponentBehavior: Bound

import QtQuick
import "../colors"

/**
 * astralis — a horizontal divider that sits exactly midway in a gap.
 *
 * Give it the WHOLE gap between the two things it separates as its height,
 * anchor the next item to its bottom, and the line is centred in that gap:
 * the same space above and below it. It is exactly one device pixel thick and
 * on the pixel grid (PixelSnap), so it reads as the same crisp line wherever
 * it lands. A 1-logical-px Rectangle covered one or two device pixels on this
 * 1.6 panel, depending on position.
 *
 *   Rule { id: divider; anchors.top: header.bottom; height: 16 * s }
 *   ListView { anchors.top: divider.bottom; ... }
 *
 * Before this, every divider sat on a fixed margin from the item above with a
 * different margin to the item below (8 then 6, 9 then 10, 0 then 6), so the
 * line looked closer to one side.
 */
Item {
    id: rule

    property color color: Qt.alpha(Colors.on_surface, 0.06)
    /**
     * Empty space inside the neighbour above / below, at the edge it shares
     * with the rule: a header whose text sits a few px above its box bottom, a
     * list whose first row starts a few px into the list. The line centres on
     * what you SEE (ink or highlight edge), not on the item boxes.
     */
    property real airAbove: 0
    property real airBelow: 0
    /** The drawn line, for anything that rides along it (Clipboard's wipe heat). */
    readonly property alias line: line

    implicitHeight: 1

    PixelSnap {
        id: snap
        target: rule
    }

    Rectangle {
        id: line
        width: rule.width
        height: snap.hair
        y: snap.dy + Math.floor((rule.height + rule.airBelow - rule.airAbove - snap.hair) / 2 * snap.dpr) / snap.dpr
        color: rule.color
    }
}
