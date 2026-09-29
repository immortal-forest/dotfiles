pragma ComponentBehavior: Bound

import QtQuick
import "../colors"
import "../services"
import "../config"

/**
 * astralis — numeric value control for the settings pages (ported from
 * Ricelin pill/ScrubValue.qml). At rest it is just the number, so a column of
 * them stays clean instead of a grid of boxes. Hover wakes a faint accent
 * backdrop and the ghost − / + glyphs. One control-wide handler does the
 * work: drag the number left or right to scrub, or tap near the − / + end to
 * step exactly. The whole control is the target, so it reads minimal but
 * stays easy to grab. Every path runs through `snap`, so the emitted value is
 * always clamped to `from..to`, landed on the `step` grid and rounded to
 * `decimals`. `value` stays a plain one-way binding to the backing field;
 * edits flow out through `edited`.
 */
Item {
    id: root

    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 1
    property int decimals: 0
    property string unit: ""
    property real s: 1
    signal edited(real value)

    /**
     * Name a screen reader announces. Left empty the control is still reported
     * as a slider with its value, just unlabelled — the owning SettingsRow's
     * name is the natural thing to pass in.
     */
    property string accessibleName: ""

    /**
     * Keyboard. This control was mouse-only: you could drag it or tap its ends,
     * and that was the whole vocabulary — which meant every numeric setting in
     * the shell was unreachable without a pointer. The standard slider keys
     * work here now, and `activeFocusOnTab` puts it in the tab order so they
     * can actually be reached.
     *
     * PageUp/PageDown move by a tenth of the range rather than by `step`, since
     * a range like 0..255 in steps of 1 would otherwise need 255 keypresses.
     */
    readonly property real pageStep: Math.max(root.step, (root.to - root.from) / 10)

    activeFocusOnTab: true

    /**
     * QML's `Accessible` attached type exposes only QAccessible's flags and
     * actions — NOT the value interface. `Accessible.value`, `.minimumValue`,
     * `.maximumValue` and `.stepSize` do not exist here and assigning any of
     * them is a hard load failure, not a warning (verified against this Qt
     * build). The readable number therefore goes in `description`, and the
     * increase/decrease ACTIONS are what let assistive tech drive the control.
     */
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: (root.fmt ? root.fmt(root.value) : root.value.toFixed(root.decimals))
        + (root.unit.length > 0 ? " " + root.unit : "")
        + " (" + root.from + " to " + root.to + ")"
    Accessible.focusable: true
    Accessible.onIncreaseAction: root.bump(1)
    Accessible.onDecreaseAction: root.bump(-1)

    Keys.onPressed: function (event) {
        var n = root.value;
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_Down:     n = root.value - root.step; break;
        case Qt.Key_Right:
        case Qt.Key_Up:       n = root.value + root.step; break;
        case Qt.Key_PageDown: n = root.value - root.pageStep; break;
        case Qt.Key_PageUp:   n = root.value + root.pageStep; break;
        case Qt.Key_Home:     n = root.from; break;
        case Qt.Key_End:      n = root.to; break;
        default: return;
        }
        event.accepted = true;
        var snapped = root.snap(n);
        if (snapped !== root.value)
            root.edited(snapped);
    }

    /** Optional value-to-text mapper. When set it owns the label, so the raw number and unit step aside (used for HH:MM schedule scrubs). */
    property var fmt: null

    /**
     * Value the host captured when the page opened. While the live value
     * differs from it the undo glyph surfaces, so a stray scrub is always one
     * click away from the value it had on open. `undefined` until the host
     * snapshots.
     */
    property var openValue: undefined
    readonly property bool dirty: openValue !== undefined && !isNaN(openValue) && root.value !== openValue

    // Keyboard focus counts as "awake" alongside hover: a tab-focused control
    // that still showed only a bare number gave no hint that the arrow keys
    // now do anything.
    readonly property bool hovered: hh.hovered || scrub.containsMouse || scrub.pressed
        || undoMA.containsMouse || root.activeFocus
    readonly property real pxPerStep: 8 * root.s

    /**
     * Display-only shadow of `value`, eased instead of snapping straight to
     * the new number — a click-step, wheel notch or undo lands with a quick
     * settle rather than an instant digit swap. Suppressed while an actual
     * drag is live (`scrub.pressed`) so the number still tracks the cursor
     * 1:1 instead of lagging behind it mid-scrub. Purely cosmetic:
     * `value`/`edited`/`snap` are unchanged, this only feeds the Text below.
     */
    property real displayValue: root.value
    Behavior on displayValue {
        enabled: !scrub.pressed
        NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
    }

    /** Which end the pointer sits over while hovering, so the right glyph lights up. */
    readonly property bool overMinus: scrub.containsMouse && scrub.mouseX < width * 0.4
    readonly property bool overPlus: scrub.containsMouse && scrub.mouseX > width * 0.6

    HoverHandler { id: hh }

    implicitWidth: Math.max(64 * root.s, content.implicitWidth + 14 * root.s)
    implicitHeight: content.implicitHeight + 8 * root.s

    function snap(v) {
        var n = root.from + Math.round((v - root.from) / root.step) * root.step;
        n = Math.max(root.from, Math.min(root.to, n));
        var p = Math.pow(10, root.decimals);
        return Math.round(n * p) / p;
    }

    function bump(dir) {
        var n = snap(root.value + dir * root.step);
        if (n !== root.value)
            root.edited(n);
    }

    Rectangle {
        anchors.fill: parent
        radius: Motion.rSmall * root.s
        color: Qt.alpha(Colors.primary, root.hovered ? 0.14 : 0)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    // Keyboard focus ring, same shape as the m3/ components use
    // (md-comp-focus-ring: 3dp of `secondary`, sitting 2dp clear of the edge).
    // Only for real focus, never for hover — a ring that followed the mouse
    // would fight the fill above rather than mean anything.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3.5 * root.s
        radius: (Motion.rSmall + 3.5) * root.s
        color: "transparent"
        border.width: 3 * root.s
        border.color: Colors.secondary
        opacity: root.activeFocus ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
    }

    /**
     * Drag to scrub, tap an end to step. A small move turns the press into a
     * scrub; a clean tap on the left or right fraction steps once. Sits under
     * the row so the undo glyph above keeps its own click.
     */
    MouseArea {
        id: scrub
        anchors.fill: parent
        anchors.leftMargin: -12 * root.s
        anchors.rightMargin: -10 * root.s
        anchors.topMargin: -3 * root.s
        anchors.bottomMargin: -3 * root.s
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeHorCursor

        property real pressX: 0
        property real pressVal: 0
        property bool dragged: false

        onPressed: mouse => {
            pressX = mouse.x;
            pressVal = root.value;
            dragged = false;
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            if (Math.abs(mouse.x - pressX) > 3 * root.s)
                dragged = true;
            if (!dragged)
                return;
            var steps = Math.round((mouse.x - pressX) / root.pxPerStep);
            var cand = root.snap(pressVal + steps * root.step);
            if (cand !== root.value)
                root.edited(cand);
        }
        onClicked: mouse => {
            if (dragged)
                return;
            if (mouse.x < width * 0.4)
                root.bump(-1);
            else if (mouse.x > width * 0.6)
                root.bump(1);
        }
    }

    /**
     * Wheel-to-step bridge (button-less MouseArea, the mixer pattern — native
     * WheelHandler is unreliable on this layer-shell). One notch is one step;
     * fractional touchpad deltas accumulate until they make a whole notch.
     */
    MouseArea {
        anchors.fill: scrub
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.SizeHorCursor
        property real acc: 0
        onWheel: (event) => {
            acc += event.angleDelta.y / 120;
            const notches = Math.trunc(acc);
            if (notches !== 0) {
                var cand = root.snap(root.value + notches * root.step);
                if (cand !== root.value)
                    root.edited(cand);
                acc -= notches;
            }
            event.accepted = true;
        }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6 * root.s

        GlyphIcon {
            id: undoG
            anchors.verticalCenter: parent.verticalCenter
            name: "undo"
            height: 14 * root.s
            width: root.dirty ? 14 * root.s : 0
            opacity: root.dirty ? 1 : 0
            clip: true
            stroke: 1.9
            color: undoMA.containsMouse ? Colors.on_surface : Qt.alpha(Colors.primary, 0.55)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            MouseArea {
                id: undoMA
                anchors.fill: parent
                anchors.margins: -6 * root.s
                enabled: root.dirty
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.edited(root.openValue)
            }
        }

        // A GlyphIcon, not the "−" character. Borrowing a symbol from the UI
        // font gave these buttons the FONT's weight and optical size while
        // every other icon in the shell carries the icon set's, so the two
        // ends of this control never matched the rest of the surface.
        // The reserved width is a constant rather than the glyph's own
        // implicit width — a width bound to the implicit width it feeds is a
        // binding loop, and it is also why this had to `clip`.
        GlyphIcon {
            id: minusG
            anchors.verticalCenter: parent.verticalCenter
            name: "minus"
            height: 13 * root.s
            width: root.hovered ? 13 * root.s : 0
            opacity: root.hovered ? 1 : 0
            clip: true
            stroke: 2
            color: root.overMinus ? Colors.on_surface : Qt.alpha(Colors.primary, 0.6)
            // The end glyphs are the control's buttons — a tap here steps the
            // value — so they answer the press the way every other button in the
            // shell does. Keyed on `overMinus` (which already means "pointer is
            // over this end"), so a press that lands mid-control to start a drag
            // never dips a glyph it isn't stepping.
            scale: (scrub.pressed && root.overMinus) ? 0.86 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }

        Item {
            id: valueWrap
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.max(28 * root.s, vrow.implicitWidth)
            implicitHeight: vrow.implicitHeight

            Row {
                id: vrow
                anchors.centerIn: parent
                spacing: 1 * root.s

                Text {
                    id: numText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.fmt ? root.fmt(root.displayValue) : root.displayValue.toFixed(root.decimals)
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 13 * root.s
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.verticalCenter: numText.verticalCenter
                    visible: !root.fmt && root.unit.length > 0
                    text: root.unit
                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                    font.family: Appearance.font.family
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.Medium
                }
            }
        }

        // A GlyphIcon, not the "+" character. Borrowing a symbol from the UI
        // font gave these buttons the FONT's weight and optical size while
        // every other icon in the shell carries the icon set's, so the two
        // ends of this control never matched the rest of the surface.
        // The reserved width is a constant rather than the glyph's own
        // implicit width — a width bound to the implicit width it feeds is a
        // binding loop, and it is also why this had to `clip`.
        GlyphIcon {
            id: plusG
            anchors.verticalCenter: parent.verticalCenter
            name: "plus"
            height: 13 * root.s
            width: root.hovered ? 13 * root.s : 0
            opacity: root.hovered ? 1 : 0
            clip: true
            stroke: 2
            color: root.overPlus ? Colors.on_surface : Qt.alpha(Colors.primary, 0.6)
            // Mirror of the − glyph above: this end is a button too.
            scale: (scrub.pressed && root.overPlus) ? 0.86 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }
    }
}
