pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../colors"
import "../../services"
import "../../config"
import "../../pill"
import "../../pill/surfaces" as Surfaces

/**
 * astralis — settings as a real floating window. A FloatingWindow toplevel that
 * Hyprland floats via a windowrule on the title `astralis-settings` — NOT a pill
 * surface and NOT a layer-shell overlay. Reuses the whole in-pill settings UI
 * (pill/surfaces/Settings.qml) on a Panel material, with `open` pinned true and
 * no pill morph. Opened by the Super+comma keybind (shell `settingsOpen`) and the
 * launcher's Settings entry; closed by the page header ×, Escape, or toggling again.
 */
FloatingWindow {
    id: win

    signal requestClose()

    // Matched by the Hyprland float/center windowrule.
    title: "astralis-settings"
    // Transparent so the Panel's rounded material is the visible shape.
    color: "transparent"

    // Real-window scale from its screen, same basis as the pill.
    readonly property real s: (win.screen ? win.screen.height / 1080 : 1.48) * Flags.uiScale

    // Fixed window size (Hyprland `center` rule drops it in the middle).
    implicitWidth:  Math.round(720 * win.s)   // default
    implicitHeight: Math.round(520 * win.s)
    minimumSize:    Qt.size(Math.round(720 * win.s), Math.round(520 * win.s))
    
    // Escape closes regardless of which child currently holds focus.
    Shortcut { sequences: ["Escape"]; onActivated: win.requestClose() }

    // Lazy: don't build the settings tree until the window opens, and drop it
    // again once it has been closed for 30s (the pill's surfaceReaper does the
    // same) — a dozen settings pages are dead weight for a window opened once.
    property bool warm: false
    onVisibleChanged: {
        if (visible) {
            coolDown.stop();
            warm = true;
            // Warm reopen: the content already exists, so replay the entrance
            // from here (a cold open replays it from the content's
            // Component.onCompleted, once the tree has actually been built).
            win.playEnter();
        } else {
            // Park the content hidden so the next show's first frame is the
            // start of the entrance, not a flash of the finished window.
            enterAnim.stop();
            win.fadeT = 0;
            win.riseT = 0;
            coolDown.restart();
        }
    }

    // Entrance. A Wayland toplevel cannot fade its own opacity, so the
    // window itself maps at once (transparent) and the CONTENT arrives:
    // a standard-curve fade with a slight emphasized rise + scale settle.
    property real fadeT: 0
    property real riseT: 0
    function playEnter() {
        enterAnim.stop();
        win.fadeT = 0;
        win.riseT = 0;
        enterAnim.start();
    }
    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: win
            property: "fadeT"
            from: 0
            to: 1
            duration: Motion.standard
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.standardCurve
        }
        NumberAnimation {
            target: win
            property: "riseT"
            from: 0
            to: 1
            duration: Motion.normalDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.emphasized
        }
    }
    Timer {
        id: coolDown
        interval: 30000
        onTriggered: win.warm = false
    }

    Loader {
        anchors.fill: parent
        active: win.visible || win.warm

        sourceComponent: Item {
            id: content
            opacity: win.fadeT
            scale: 0.96 + 0.04 * win.riseT
            transformOrigin: Item.Center
            transform: Translate { y: (1 - win.riseT) * 10 * win.s }
            Component.onCompleted: if (win.visible) win.playEnter()

            Panel {
                anchors.fill: parent
                s: win.s
                radius: 18 * win.s
            }

            Surfaces.Settings {
                anchors.fill: parent
                s: win.s
                open: win.visible
                morphCloseness: 1
                onRequestClose: win.requestClose()
            }
        }
    }
}
