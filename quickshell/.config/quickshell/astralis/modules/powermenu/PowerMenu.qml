pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../colors"
import "../../services"
import "../../config"
import "../../pill"

/**
 * astralis — full-screen session/power menu. NOT a pill surface: its own
 * layer-shell overlay window that fills the WHOLE monitor, mirroring
 * modules/wallpaper/WallpaperPicker.qml's pattern (own PanelWindow,
 * WlrLayer.Overlay, exclusive keyboard focus while open, whole-screen frost
 * via the Hyprland layerrule on ^astralis-powermenu$ + a light scrim here).
 * Deliberately carries NO Ame soul bead — this is a modal outside the pill's
 * own morph/anchor system entirely.
 *
 * Six session actions as big centered tiles (Lock, Logout, Suspend,
 * Hibernate, Reboot, Shutdown). The destructive three (Logout/Reboot/
 * Shutdown) use the same hold-to-confirm heat fill as the in-pill Power
 * surface (pill/HeatHold.qml): holding ramps a bottom-up fill over
 * Motion.heat and fires on completion; releasing early drains it, so a
 * stray click or tap can never end the session. Lock/Suspend/Hibernate are
 * all resumable (no data loss), so they fire on a single tap — Ricelin's
 * "Lock/Suspend can be single-action" split, extended to Hibernate.
 *
 * Keyboard: Left/Right/Up/Down and hjkl move focus across the single tile
 * row; Enter activates the focused tile (a held Enter on a destructive tile
 * drives the same heat fill as a pointer hold — release before it completes
 * drains, so the keyboard path can't confirm on a single keystroke either);
 * number keys 1-6 jump focus straight to a tile (kept to *moving* focus,
 * never firing, so a stray digit can't queue a destructive action). Escape
 * or a click on the scrim dismisses.
 */
PanelWindow {
    id: root

    property real s: 1
    property bool open: false

    signal requestClose()

    // Kept visible a beat past `open` flipping false so the exit fade/scale
    // (bound to `open` below, not this) actually gets to play before the
    // layer-shell surface disappears outright.
    property bool _closing: false
    visible: root.open || root._closing

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "astralis-powermenu"
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Fills the ENTIRE monitor: the Hyprland layerrule (blur, ignore_alpha
    // OFF) frosts the whole screen behind it, same treatment as the
    // wallpaper picker; the scrim here just adds a touch more separation
    // since the content is plain UI chrome, not imagery.
    anchors { left: true; right: true; top: true; bottom: true }

    readonly property var actions: [
        { key: "lock",      glyph: "lock",     label: "Lock",      hint: "1", confirm: false, argv: ["loginctl", "lock-session"] },
        { key: "logout",    glyph: "logout",   label: "Logout",    hint: "2", confirm: true,  argv: ["hyprctl", "dispatch", "exit"] },
        { key: "suspend",   glyph: "suspend",  label: "Suspend",   hint: "3", confirm: false, argv: ["systemctl", "suspend"] },
        // No dedicated hand-drawn glyph for hibernate; "download" (an arrow
        // into a tray) reads as "save state to disk", which is what
        // hibernate actually does — reused rather than growing GlyphIcon.
        { key: "hibernate", glyph: "download", label: "Hibernate", hint: "4", confirm: false, argv: ["systemctl", "hibernate"] },
        { key: "reboot",    glyph: "reboot",   label: "Reboot",    hint: "5", confirm: true,  argv: ["systemctl", "reboot"] },
        { key: "shutdown",  glyph: "shutdown", label: "Shutdown",  hint: "6", confirm: true,  argv: ["systemctl", "poweroff"] }
    ]

    property int focusIndex: 0
    property bool keyHeld: false

    function run(a) {
        Quickshell.execDetached(a.argv);
        root.requestClose();
    }

    function move(dir) {
        root.keyHeld = false;
        root.focusIndex = (root.focusIndex + dir + root.actions.length) % root.actions.length;
    }

    /** Enter pressed on the focused tile: safe tiles fire at once; a
     * destructive tile latches `keyHeld` so its delegate ramps the heat fill
     * exactly like a pointer hold. */
    function pressFocused() {
        if (root.focusIndex < 0 || root.focusIndex >= root.actions.length)
            return;
        const a = root.actions[root.focusIndex];
        if (a.confirm)
            root.keyHeld = true;
        else
            root.run(a);
    }

    /** Enter released: drop the hold so an early release drains instead of confirming. */
    function releaseFocused() {
        root.keyHeld = false;
    }

    onOpenChanged: {
        if (root.open) {
            root._closing = false;
            closeTimer.stop();
            root.focusIndex = 0;
            root.keyHeld = false;
            Qt.callLater(() => focusScope.forceActiveFocus());
        } else {
            root.keyHeld = false;
            root._closing = true;
            closeTimer.restart();
        }
    }

    // Keeps the surface alive just long enough for the exit fade/scale
    // (bound to `open`, below) to finish before `visible` drops it.
    Timer {
        id: closeTimer
        interval: Motion.expressiveDefaultSpatialDur
        onTriggered: root._closing = false
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: root.open

        Keys.onEscapePressed: root.requestClose()
        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_H:
            case Qt.Key_Up:
            case Qt.Key_K:
                root.move(-1);
                event.accepted = true;
                break;
            case Qt.Key_Right:
            case Qt.Key_L:
            case Qt.Key_Down:
            case Qt.Key_J:
                root.move(1);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                // Guard autorepeat: an OS-repeated key-down while Enter stays
                // held would otherwise re-fire a safe action on every tick
                // (or restart the heat ramp instead of holding it steady).
                if (!event.isAutoRepeat)
                    root.pressFocused();
                event.accepted = true;
                break;
            case Qt.Key_1:
            case Qt.Key_2:
            case Qt.Key_3:
            case Qt.Key_4:
            case Qt.Key_5:
            case Qt.Key_6: {
                const idx = event.key - Qt.Key_1;
                if (idx < root.actions.length) {
                    root.keyHeld = false;
                    root.focusIndex = idx;
                }
                event.accepted = true;
                break;
            }
            default:
                break;
            }
        }
        Keys.onReleased: (event) => {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
                root.releaseFocused();
                event.accepted = true;
            }
        }

        // ── whole-screen scrim over the Hyprland-blurred desktop ────────────
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colors.scrim, 0.22)

            MouseArea {
                anchors.fill: parent
                onClicked: root.requestClose()
            }
        }

        // ── centered content: header + tile row + hint caption ──────────────
        Column {
            anchors.centerIn: parent
            spacing: 34 * root.s

            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.92
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.expressiveDefaultSpatialDur
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveDefaultSpatial
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "電"
                    color: Colors.on_surface
                    font.family: Appearance.font.jp
                    font.weight: Font.Medium
                    font.pixelSize: 22 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SESSION"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 13 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 3 * root.s
                }
            }

            Row {
                id: tileRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 28 * root.s

                // The six tiles are a fixed intrinsic width; on a narrow (or
                // portrait / small) output that overruns the screen. Shrink the
                // whole row uniformly to fit the available width — a visual
                // transform only, so tile hit-testing and the hold-to-confirm
                // heat fill inside each delegate are unaffected. transformOrigin
                // stays Center so it keeps sitting under the centered header.
                transformOrigin: Item.Center
                scale: {
                    const natural = tileRow.implicitWidth;
                    const avail = focusScope.width - 48 * root.s;
                    if (!(natural > 0) || !(avail > 0) || avail >= natural)
                        return 1;
                    return avail / natural;
                }

                Repeater {
                    model: root.actions

                    delegate: Item {
                        id: tile
                        required property int index
                        required property var modelData

                        width: 132 * root.s
                        height: 158 * root.s
                        scale: tile.kbFocus ? 1.04 : 1.0
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.expressiveDefaultSpatialDur
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveDefaultSpatial
                            }
                        }

                        readonly property bool kbFocus: root.focusIndex === tile.index
                        readonly property bool isHover: mouseArea.containsMouse || tile.kbFocus
                        readonly property bool holding: heat.holding
                        readonly property real hold: heat.hold
                        readonly property color accent: tile.modelData.confirm ? Colors.error : Colors.primary

                        // A held Enter on the focused destructive tile drives
                        // the same heat fill as a pointer hold; dropping the
                        // key (or losing focus) drains it.
                        readonly property bool keyDriving: tile.kbFocus && root.keyHeld && tile.modelData.confirm
                        onKeyDrivingChanged: {
                            if (tile.keyDriving)
                                heat.press();
                            else
                                heat.release();
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.large * root.s
                            color: tile.isHover ? Colors.surface_container_high : Colors.surface_container
                            border.width: tile.kbFocus ? 2 : 1
                            border.color: tile.kbFocus ? tile.accent : Qt.alpha(Colors.outline_variant, 0.5)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                        }

                        // Heat fill in a ClippingRectangle carrying the tile's
                        // own radius (pill/surfaces/Power.qml pattern) — a
                        // plain Rectangle's own radius clamps to height/2
                        // while the fill is still flat, poking corners past
                        // the tile outline on the first beat of every hold.
                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: (Appearance.rounding.large - 1) * root.s
                            color: "transparent"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * tile.hold
                                visible: tile.holding
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.alpha(Colors.error, 0.6) }
                                    GradientStop { position: 1.0; color: Qt.alpha(Colors.error, 0.12) }
                                }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 10 * root.s

                            GlyphIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 44 * root.s
                                height: 44 * root.s
                                name: tile.modelData.glyph
                                color: tile.holding ? Colors.on_surface : (tile.isHover ? tile.accent : Colors.on_surface_variant)
                                stroke: 1.9
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.label
                                color: tile.isHover ? Colors.on_surface : Colors.on_surface_variant
                                font.family: Appearance.font.family
                                font.pixelSize: Appearance.font.sizeL * root.s
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: tile.modelData.confirm
                                text: "hold to confirm"
                                color: Qt.alpha(Colors.error, 0.85)
                                font.family: Appearance.font.family
                                font.pixelSize: Appearance.font.sizeS * root.s
                                font.weight: Font.Medium
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.hint
                                color: Qt.alpha(Colors.on_surface_variant, 0.55)
                                font.family: Appearance.font.family
                                font.pixelSize: Appearance.font.sizeS * root.s
                                font.features: ({ "tnum": 1 })
                            }
                        }

                        HeatHold {
                            id: heat
                            onConfirmed: root.run(tile.modelData)
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.focusIndex = tile.index
                            onPressed: if (tile.modelData.confirm) heat.press()
                            onReleased: if (tile.modelData.confirm) heat.release()
                            onExited: if (tile.modelData.confirm) heat.cancel()
                            onClicked: {
                                if (!tile.modelData.confirm)
                                    root.run(tile.modelData);
                            }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "↵ activate · hold to confirm · Esc to dismiss"
                color: Qt.alpha(Colors.on_surface_variant, 0.55)
                font.family: Appearance.font.family
                font.pixelSize: Appearance.font.sizeS * root.s
            }
        }
    }
}
