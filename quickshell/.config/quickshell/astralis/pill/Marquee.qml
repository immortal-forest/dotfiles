import QtQuick
import QtQuick.Effects
import "../colors"
import "../services"
import "../config"

/**
 * astralis — ping-pong marquee (ported from Ricelin Marquee.qml). Single-line
 * text that scrolls when wider than the available width, so long track and
 * artist names stay readable. Caller sets the width (e.g. via anchors) and
 * `active` to gate the motion. The label snaps to whole pixels so
 * NativeRendering stays crisp while it scrolls.
 */
Item {
    id: root

    property string text: ""
    property color color: Colors.on_surface
    property real pixelSize: 14
    property int weight: Font.Normal
    property bool active: true

    property real scrollX: 0

    implicitHeight: label.implicitHeight
    clip: true

    readonly property bool overflowing: label.implicitWidth > width

    // Edge-fade: while the label overflows (scrolling, or held static under
    // reduce-motion) its two ends dissolve into the pill instead of hard-
    // clipping. Layered only when overflowing so a fitting label pays nothing.
    layer.enabled: root.overflowing
    layer.effect: MultiEffect {
        maskEnabled: true
        maskThresholdMin: 0.0
        maskSpreadAtMin: 1.0
        maskSource: ShaderEffectSource {
            sourceItem: Rectangle {
                width: Math.max(1, root.width)
                height: Math.max(1, root.height)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0;  color: "transparent" }
                    GradientStop { position: 0.08; color: "black" }
                    GradientStop { position: 0.92; color: "black" }
                    GradientStop { position: 1.0;  color: "transparent" }
                }
            }
        }
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(root.scrollX)
        text: root.text
        color: root.color
        renderType: Text.NativeRendering
        font.family: Appearance.font.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        elide: root.overflowing ? Text.ElideNone : Text.ElideRight
        width: root.overflowing ? implicitWidth : root.width

        onTextChanged: root.sync()
    }

    /**
     * The durations here deliberately do NOT carry `Motion.mult`, and that is
     * not an oversight the next contract sweep should fix.
     *
     * `Motion.mult` exists to shorten animations under reduce-motion. This
     * animation does not run under reduce-motion at ALL — `start()` below
     * gates on `!Motion.reduceMotion` — so multiplying through it would only
     * ever change the speed of a marquee that a reduce-motion user is not
     * being shown. And the wrong way: scaling by 0.4 would make the text
     * scroll two and a half times FASTER, which is the opposite of what the
     * setting asks for. A marquee's answer to reduce-motion is to stop, not to
     * hurry.
     */
    SequentialAnimation {
        id: anim
        loops: Animation.Infinite
        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: root
            property: "scrollX"
            from: 0
            to: -(label.implicitWidth - root.width)
            duration: Math.max(1, label.implicitWidth - root.width) * 22
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: root
            property: "scrollX"
            from: -(label.implicitWidth - root.width)
            to: 0
            duration: Math.max(1, label.implicitWidth - root.width) * 22
            easing.type: Easing.InOutSine
        }
    }

    onActiveChanged: sync()
    onOverflowingChanged: sync()
    Component.onCompleted: sync()

    // Reduce-motion holds the label static (no scroll loop); re-sync when it
    // flips so the marquee stops/starts without a restart.
    Connections {
        target: Motion
        function onReduceMotionChanged() { root.sync(); }
    }

    /**
     * Fully imperative start/stop: a `running` binding here would be severed
     * by the first imperative stop() and leave the loop animating forever
     * inside a hidden surface. Re-syncing on overflow changes also refreshes
     * the captured from/to endpoints after a width change.
     */
    function sync() {
        anim.stop();
        root.scrollX = 0;
        if (overflowing && active && !Motion.reduceMotion)
            anim.start();
    }
}
