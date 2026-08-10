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

    readonly property bool hovered: hh.hovered || scrub.containsMouse || scrub.pressed || undoMA.containsMouse
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
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

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

        Text {
            id: minusG
            anchors.verticalCenter: parent.verticalCenter
            text: "−"
            width: root.hovered ? implicitWidth : 0
            opacity: root.hovered ? 1 : 0
            clip: true
            color: root.overMinus ? Colors.on_surface : Qt.alpha(Colors.primary, 0.6)
            font.family: Appearance.font.family
            font.pixelSize: 15 * root.s
            font.weight: Font.Medium
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
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

        Text {
            id: plusG
            anchors.verticalCenter: parent.verticalCenter
            text: "+"
            width: root.hovered ? implicitWidth : 0
            opacity: root.hovered ? 1 : 0
            clip: true
            color: root.overPlus ? Colors.on_surface : Qt.alpha(Colors.primary, 0.6)
            font.family: Appearance.font.family
            font.pixelSize: 15 * root.s
            font.weight: Font.Medium
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
    }
}
