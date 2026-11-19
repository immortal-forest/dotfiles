pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../services"
import "../colors"

/**
 * astralis — row of icon chips for windows parked on Hyprland's
 * `special:minimized` workspace (ported from Ricelin pill/MinimizedTray.qml,
 * tooltip dropped). Clicking a chip moves the
 * window back to the active workspace of the monitor THIS pill lives on, so
 * it reappears on the screen the user clicked.
 *
 * Napped apps (appnap, Super+Ctrl+M: frozen, RAM in swap) sit here too: their
 * chip dims and wears a moon badge (AppNap service). A normal click restores
 * them like any other chip, and appnap thaws them as they leave. Right-click
 * naps or wakes a chip's app in place, without restoring it.
 */
Row {
    id: root

    property real s: 1
    property string screenName: ""
    spacing: 8 * s

    /**
     * Workspace id to restore into: this monitor's active workspace, falling
     * back to the focused workspace.
     */
    function restoreWorkspace() {
        var ms = Hyprland.monitors.values;
        for (var i = 0; i < ms.length; i++)
            if (ms[i].name === root.screenName && ms[i].activeWorkspace)
                return ms[i].activeWorkspace.id;
        return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
    }

    readonly property var items: {
        var out = [];
        var tl = Hyprland.toplevels.values;
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            if (t && t.workspace && t.workspace.name === "special:minimized")
                out.push(t);
        }
        return out;
    }
    readonly property int count: items.length

    /**
     * Resolve an icon path for a toplevel by matching its window class to a
     * desktop entry id (the class often differs from the icon-theme name),
     * with a direct icon-theme lookup as fallback.
     */
    function iconFor(t) {
        var cls = (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class
            : (t && t.wayland && t.wayland.appId ? t.wayland.appId : "");
        if (!cls)
            return "";
        var apps = DesktopEntries.applications.values;
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i];
            if (e && e.id && e.id.toLowerCase() === cls.toLowerCase() && e.icon)
                return (Quickshell.iconPath(e.icon, true) || Quickshell.iconPath("application-x-executable", true));
        }
        return (Quickshell.iconPath(cls, true) || Quickshell.iconPath("application-x-executable", true));
    }

    /**
     * Human-readable label for a screen reader — the IPC title if Hyprland
     * gave one, else the same class/appId chain `iconFor` already resolves.
     */
    function titleFor(t) {
        if (t && t.lastIpcObject && t.lastIpcObject.title)
            return t.lastIpcObject.title;
        var cls = (t && t.lastIpcObject && t.lastIpcObject.class) ? t.lastIpcObject.class
            : (t && t.wayland && t.wayland.appId ? t.wayland.appId : "");
        return cls || "window";
    }

    /** Shared by the click and the accessible press action so they can't drift. */
    function restoreToplevel(t) {
        var addr = String((t && t.address) || "");
        if (addr.indexOf("0x") !== 0)
            addr = "0x" + addr;
        // Lua config: dispatch takes hl.dsp.* expressions, not vanilla strings.
        Hyprland.dispatch("hl.dsp.window.move({ workspace = " + JSON.stringify(String(root.restoreWorkspace()))
            + ", follow = false, window = " + JSON.stringify("address:" + addr) + " })");
    }

    Repeater {
        model: root.items

        delegate: Item {
            id: chip
            required property var modelData
            width: 18 * root.s
            height: 18 * root.s

            readonly property string iconSrc: root.iconFor(chip.modelData)
            readonly property bool napped: AppNap.isNapped(chip.modelData.address)

            Accessible.role: Accessible.Button
            Accessible.name: "Restore " + root.titleFor(chip.modelData) + " to this screen"
                + (chip.napped ? " (napped: frozen, memory in swap)" : "")
            Accessible.focusable: true
            Accessible.onPressAction: root.restoreToplevel(chip.modelData)

            Image {
                anchors.fill: parent
                sourceSize.width: Math.round(36 * root.s)
                sourceSize.height: Math.round(36 * root.s)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                source: chip.iconSrc
                // Napped apps read as asleep: dimmer at rest, still lifting on hover.
                opacity: chip.napped ? (area.containsMouse ? 0.85 : 0.42) : (area.containsMouse ? 1 : 0.78)
                Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }
                scale: area.pressed ? 0.92 : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.glide
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }
            }

            // Moon badge on napped chips: pops in with the same spatial spring
            // the chip's press uses, fades with the standard curve.
            Rectangle {
                id: badge
                width: 10 * root.s
                height: width
                radius: width / 2
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -2 * root.s
                anchors.bottomMargin: -2 * root.s
                color: Colors.surface_container_highest
                opacity: chip.napped ? 1 : 0
                scale: chip.napped ? 1 : 0.4
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast ; easing.type: Motion.easeStandard } }
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.glide
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }

                GlyphIcon {
                    anchors.fill: parent
                    anchors.margins: 1.5 * root.s
                    name: "suspend"
                    color: Colors.primary
                    stroke: 2.4
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -3 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        AppNap.toggle(chip.modelData.address);
                    else
                        root.restoreToplevel(chip.modelData);
                }
            }
        }
    }
}
