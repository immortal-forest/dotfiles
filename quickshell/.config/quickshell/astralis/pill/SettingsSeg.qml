pragma ComponentBehavior: Bound

import QtQuick
import "../colors"
import "../services"
import "../config"

/**
 * astralis — mini-segmented choice control (ported from Ricelin
 * pill/SettingsSeg.qml). `options` is a list of `{ label, value }`; the pill
 * whose value equals `value` lights with a primary tint. Picking a pill emits
 * `picked(value)`; selection keys off the source value, never a child's
 * effective visibility. The host passes `s` for scale.
 */
Rectangle {
    id: seg

    property real s: 1
    property var options: []
    property var value
    signal picked(var value)

    /**
     * When `flushLeft`, the control shifts left by the first option's text
     * inset so that text lines up with x=0 of where the control is placed,
     * rather than the pill edge sitting there.
     */
    property bool flushLeft: false

    readonly property real pad: 1
    readonly property real edgePad: seg.pad + 9 * seg.s

    x: seg.flushLeft ? -seg.edgePad : 0
    width: pills.implicitWidth + 2 * pad
    height: pills.implicitHeight + 2 * pad
    radius: 9 * seg.s
    color: "transparent"

    /** Index of the option matching `value`, or -1 while nothing matches. */
    readonly property int currentIndex: {
        for (var i = 0; i < seg.options.length; i++)
            if (seg.options[i].value === seg.value)
                return i;
        return -1;
    }
    // Re-looked-up (not just re-indexed) whenever `options` itself changes —
    // a live palette re-run (Look page's swatch options) hands the Repeater
    // a brand-new array, which rebuilds every delegate even when the picked
    // index number happens to land the same; without this the cached Item
    // could point at a just-destroyed delegate.
    readonly property Item currentItem: {
        void seg.options;
        return seg.currentIndex >= 0 ? rep.itemAt(seg.currentIndex) : null;
    }

    // Selected-segment indicator: one pill that glides/morphs behind whatever
    // option is current, instead of each option instantly recoloring on pick.
    // Geometry comes straight from the live delegate (Repeater.itemAt), so it
    // tracks any label-driven width change too. Declared ahead of the Row so
    // it paints underneath the option labels.
    Rectangle {
        id: indicator
        visible: seg.currentItem !== null
        radius: 8 * seg.s
        color: Qt.alpha(Colors.primary, 0.16)
        x: seg.currentItem ? pills.x + seg.currentItem.x : 0
        y: seg.currentItem ? pills.y + seg.currentItem.y : 0
        width: seg.currentItem ? seg.currentItem.width : 0
        height: seg.currentItem ? seg.currentItem.height : 0

        Behavior on x { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
    }

    Row {
        id: pills
        anchors.centerIn: parent
        spacing: 2 * seg.s

        Repeater {
            id: rep
            model: seg.options

            Rectangle {
                id: opt
                required property var modelData
                readonly property bool current: seg.value === modelData.value
                property bool hovered: false

                width: optLabel.implicitWidth + 18 * seg.s
                height: optLabel.implicitHeight + 12 * seg.s
                radius: 8 * seg.s
                // The sliding `indicator` above now owns the current-state
                // fill; this stays for hover only so the two never double-draw.
                color: (!opt.current && opt.hovered) ? Colors.surface_container_highest : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: optLabel
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    color: opt.current ? Colors.on_surface : Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * seg.s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.3 * seg.s
                }

                MouseArea {
                    // Visual pill is ~26px tall; grow the hit area vertically
                    // (only — the horizontal spacing between pills is just 2px,
                    // so widening would overlap the neighbour) toward a ~32px
                    // comfortable target.
                    anchors.fill: parent
                    anchors.topMargin: -3 * seg.s
                    anchors.bottomMargin: -3 * seg.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: opt.hovered = true
                    onExited: opt.hovered = false
                    onClicked: seg.picked(opt.modelData.value)
                }
            }
        }
    }
}
