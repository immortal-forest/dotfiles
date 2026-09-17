pragma ComponentBehavior: Bound

import QtQuick
import "../colors"
import "../services"
import "../config"

/**
 * astralis — one settings line (ported from Ricelin pill/SettingsRow.qml): an
 * optional leading kanji or icon, a name and an optional faint sub caption on
 * the left, and a control slot on the right, capped by a single bottom
 * hairline. `control` is the default slot for the toggle, segmented control
 * or chevron. `surface` wires hover and activation back to the owning
 * settings page (a SettingsPage — or anything exposing s / focusRowItem /
 * reportRowHover / activateRow) so the soul seam tracks the focused row;
 * scale derives from it.
 *
 * astralis delta: `lit` marks the sidebar's current-page row (name + icon
 * take the primary accent) — Ricelin's morphing index had no persistent
 * selection to show.
 */
Item {
    id: srow

    property var surface: null
    property string glyph: ""
    property string icon: ""
    property string name: ""
    property string sub: ""
    property bool last: false
    property bool captionOnFocus: false
    property bool lit: false
    default property alias control: controlSlot.data

    readonly property real s: srow.surface ? srow.surface.s : 1
    readonly property bool focused: srow.surface ? srow.surface.focusRowItem === srow : false

    /**
     * Screen-reader identity for the row. Every settings page in the shell is
     * built out of these, so labelling the row here labels forty-odd controls
     * at once — and it is the only place that knows both the name and the
     * caption, which is exactly what a screen reader wants to read out.
     *
     * `focused` is mirrored rather than using QML focus: the settings pages run
     * their own row-focus system (`surface.focusRowItem`, the gliding soul
     * seam), and assistive tech should follow THAT, not a second, competing
     * notion of what is current.
     *
     * Note `Accessible.value` and friends do not exist on the attached type —
     * see quickshell-core.md §9b. Anything numeric belongs in `description`.
     */
    Accessible.role: Accessible.ListItem
    Accessible.name: srow.name
    Accessible.description: srow.sub
    Accessible.focusable: true
    Accessible.focused: srow.focused
    Accessible.selected: srow.lit
    Accessible.onPressAction: if (srow.surface) srow.surface.activateRow(srow)

    width: parent ? parent.width : 0
    /**
     * Even row rhythm: size the row from its TEXT (one line + 26 padding, or a
     * shown caption), NOT from whichever control it happens to carry. Every
     * control the settings rows use (toggle 16, chevron 16, scrub ~24, seg ~27)
     * is shorter than a text row (≈41 at s=1) and just centres inside it, so a
     * toggle row and a segmented/scrub row now come out the SAME height instead
     * of the seg/scrub rows standing ~8px taller — the uneven-gap complaint.
     * The control term stays in the max only as a floor (control + 8 padding)
     * so a hypothetically tall control still gets its own space and never
     * overflows into the neighbouring row; for the real controls the text term
     * always wins, keeping the rhythm uniform.
     */
    height: Math.max(textCol.implicitHeight + 26 * srow.s,
                     controlSlot.childrenRect.height + 8 * srow.s)

    /**
     * Smooth the height change when a `captionOnFocus` row grows/shrinks on
     * hover: without this the caption toggling `visible` snaps textCol's
     * implicitHeight, so the parent Column instantly jumps every row below.
     * Animating `height` makes that reflow glide instead. Plain decelerate —
     * same easeStandard curve the row's other hover animations (highlight
     * color/scale) already use — no overshoot: an earlier pass tried the
     * glide+overshoot spring token LinkToggle's knob uses, but the bounce
     * past the settled height read as an unwanted wobble here, not a knob
     * flick. Gated on `settled` so the FIRST layout (implicitHeight
     * resolving from 0) snaps into place rather than animating a grow on
     * every page open.
     */
    property bool settled: false
    Behavior on height {
        enabled: srow.settled
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    /**
     * Content-entrance cascade: fade + rise once when the owning page/sidebar
     * goes active (page-enter), staggered by this row's position in the
     * registry (`rowIndexOf`) so a page's rows arrive in a short wave rather
     * than popping in together. Capped so a long page's tail doesn't lag.
     * Rows outside the kb registry (read-only list rows on a few pages)
     * fall back to index 0 — they fade in together, un-staggered, which
     * also keeps a long dynamic list from queuing a slow cascade. Re-plays
     * on every page-enter (open, or nav back to this page) — never on
     * Flickable scroll, since nothing here reads scroll position.
     */
    readonly property int rowIdx: srow.surface ? srow.surface.rowIndexOf(srow) : -1
    property bool entered: false

    function playEnter() {
        srow.entered = false;
        enterTimer.restart();
    }

    Component.onCompleted: {
        // Snap the first layout; only animate height changes (caption
        // grow/shrink) after this settles, so a page open never grows rows in.
        Qt.callLater(() => srow.settled = true);
        if (srow.surface && srow.surface.active)
            srow.playEnter();
    }

    Connections {
        target: srow.surface
        function onActiveChanged() {
            if (srow.surface.active)
                srow.playEnter();
        }
    }

    Timer {
        id: enterTimer
        interval: Motion.rowStagger * Math.min(srow.rowIdx < 0 ? 0 : srow.rowIdx, 10)
        onTriggered: srow.entered = true
    }

    opacity: srow.entered ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

    transform: Translate {
        y: srow.entered ? 0 : 10 * srow.s
        Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
    }

    HoverHandler {
        id: srowHover
        onHoveredChanged: if (srow.surface) srow.surface.reportRowHover(srow, hovered)
    }

    Rectangle {
        id: rowHighlight
        anchors.fill: parent
        anchors.topMargin: 3 * srow.s
        anchors.bottomMargin: 3 * srow.s
        radius: 9 * srow.s
        scale: rowArea.pressed ? 0.985 : 1
        color: rowArea.pressed ? Qt.alpha(Colors.primary, 0.10)
            : (srowHover.hovered || srow.focused) ? Colors.surface_container_highest : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        // Same spring as every other pressable in the shell (Recorder's
        // tiles, the surface ×, the lock transports) so a settings row
        // answers the finger with the same character — just a shallower
        // dip, because the target is a full-width row rather than a chip.
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }
    }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (srow.surface) srow.surface.activateRow(srow)
    }

    Text {
        id: rk
        anchors.left: parent.left
        anchors.leftMargin: 12 * srow.s
        anchors.verticalCenter: parent.verticalCenter
        visible: srow.glyph.length > 0 && srow.icon.length === 0 && Flags.showGlyphs
        text: srow.glyph
        color: srow.lit ? Colors.primary : Colors.on_surface_variant
        // The focus seam glides between rows; without this the kanji it
        // lands on snapped to the accent instead of blooming with it.
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        font.family: Appearance.font.jp
        font.pixelSize: 15 * srow.s
    }

    GlyphIcon {
        id: ri
        anchors.left: parent.left
        anchors.leftMargin: 14 * srow.s
        anchors.verticalCenter: parent.verticalCenter
        visible: srow.icon.length > 0
        width: 17 * srow.s
        height: 17 * srow.s
        name: srow.icon
        color: srow.lit ? Colors.primary
            : (srow.focused ? Colors.on_surface : Colors.on_surface_variant)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        stroke: 1.8
    }

    Column {
        id: textCol
        anchors.left: ri.visible ? ri.right : (rk.visible ? rk.right : parent.left)
        anchors.leftMargin: ri.visible ? 13 * srow.s : (rk.visible ? 11 * srow.s : 12 * srow.s)
        anchors.right: controlSlot.left
        anchors.rightMargin: 14 * srow.s
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5 * srow.s

        Text {
            text: srow.name
            color: srow.lit ? Colors.primary : Colors.on_surface
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            font.family: Appearance.font.family
            font.pixelSize: 12.5 * srow.s
            font.weight: Font.DemiBold
        }
        Text {
            id: subText
            width: parent.width
            // `shown` drives layout (implicitHeight, hence the row height);
            // opacity fades the caption in/out over that so it eases in with
            // the growing row rather than hard-popping at full opacity.
            readonly property bool shown: srow.sub.length > 0
                && (!srow.captionOnFocus || srow.focused || srowHover.hovered)
            visible: shown || opacity > 0.01
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            text: srow.sub
            // 0.85 (was 0.65): the caption renders over surface_container_highest
            // on hover/focus, where 0.65 fell to ~4.02:1 — below AA. 0.85 clears
            // 4.5:1 at this 10.5px size.
            color: Qt.alpha(Colors.on_surface_variant, 0.85)
            font.family: Appearance.font.family
            font.pixelSize: 10.5 * srow.s
            wrapMode: Text.WordWrap
            lineHeight: 1.2
        }
    }

    Item {
        id: controlSlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.alpha(Colors.on_surface, 0.06)
        visible: !srow.last
    }
}
