pragma ComponentBehavior: Bound

import QtQuick
import "../colors"
import "../services"

/**
 * Rest-pill spectrum (ported from Ricelin pill/MusicBars.qml, Theme→Colors):
 * one rounded bar per cava band, packed into the clock-glyph slot so the
 * cluster never widens the pill. Heights chase Cava.values with a short ease
 * so the motion stays liquid instead of strobing on every frame cava emits.
 *
 * Mount UNCONDITIONALLY — referencing the lazy Cava singleton here is what
 * spawns cava; gate visibility by opacity on Cava.active, never by a Loader.
 */
Row {
    id: root

    property real s: 1
    property real span: 18

    /**
     * True only while the spectrum is actually on screen (host binds it to the
     * rest face being visible AND cava running). When false the bars freeze at
     * their floor height instead of chasing Cava.values — the height binding
     * stops depending on Cava.values, so a hidden/opacity-0 spectrum no longer
     * relayouts every one of its bars on every cava frame behind an open
     * surface. The smoothing Behavior is likewise idle when frozen and under
     * reduce-motion (a continuous 60Hz retarget is exactly what that suppresses).
     */
    property bool playing: false

    height: span * s
    spacing: 1.2 * s

    Repeater {
        model: Cava.bars

        Rectangle {
            required property int index

            width: 1.8 * root.s
            radius: width / 2
            anchors.bottom: parent.bottom
            height: root.playing
                ? Math.max(2 * root.s, (Cava.values[index] || 0) * root.span * root.s)
                : 2 * root.s

            gradient: Gradient {
                GradientStop { position: 0.0; color: Colors.primary }
                GradientStop { position: 1.0; color: Colors.primary_container }
            }

            Behavior on height {
                enabled: root.playing && !Motion.reduceMotion
                NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
            }
        }
    }
}
