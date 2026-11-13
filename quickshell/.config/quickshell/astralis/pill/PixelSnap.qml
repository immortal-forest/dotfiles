pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * astralis — device-pixel snap for one item's top edge.
 *
 * The panel runs at 1.6, so logical positions land between device pixels. A
 * hairline (a plain Rectangle, not antialiased) gets rounded onto a whole
 * pixel row, while an antialiased shape like a row's rounded hover highlight
 * is drawn at its true sub-pixel position. Beside each other, the two drift up
 * to a pixel apart, and a divider never sits midway between the highlights
 * above and below it. Shifting both by `dy` puts the target's top on the
 * pixel grid, so whole-pixel offsets from it stay whole pixels on screen.
 *
 *   PixelSnap { id: snap; target: row }
 *   // then offset the row's highlight/divider by snap.dy, and size them in
 *   // whole device pixels via snap.px() / snap.hair.
 *
 * `dy` is re-measured after every frame the window animates (scroll, page
 * slides, entrance rises), so it follows anything that moves the target. When
 * nothing moves, no frames run and this costs nothing.
 */
Item {
    id: snap

    required property Item target

    /** Real device pixel ratio of this window (Screen.devicePixelRatio reports 2 here). */
    readonly property real dpr: snap.QsWindow.window ? snap.QsWindow.window.devicePixelRatio : 1
    /** One device pixel, in logical px. */
    readonly property real hair: 1 / snap.dpr
    /** Push-down (0 ≤ dy < one device pixel) that lands target's top on a pixel row. */
    property real dy: 0

    /** Round a logical length to whole device pixels. */
    function px(v) {
        return Math.round(v * snap.dpr) / snap.dpr;
    }

    function measure() {
        if (!snap.target || !snap.target.visible)
            return;
        const d = snap.target.mapToItem(null, 0, 0).y * snap.dpr;
        const off = (Math.ceil(d - 0.001) - d) / snap.dpr;
        if (Math.abs(off - snap.dy) > 0.0005)
            snap.dy = off;
    }

    visible: false
    width: 0
    height: 0

    Component.onCompleted: Qt.callLater(snap.measure)

    Connections {
        target: snap.Window.window
        function onAfterAnimating() {
            snap.measure();
        }
    }
}
