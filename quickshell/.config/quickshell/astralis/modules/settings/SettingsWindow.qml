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
 * launcher's Settings entry; closed by its header ×, Escape, or toggling again.
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

    // Latch-once: don't build the settings tree until the window is first opened
    // (the pill lazy-loads every surface the same way — no startup cost for a
    // window the user may never open this session).
    property bool everShown: false
    onVisibleChanged: if (visible) everShown = true

    Loader {
        anchors.fill: parent
        active: win.everShown

        sourceComponent: Item {
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
