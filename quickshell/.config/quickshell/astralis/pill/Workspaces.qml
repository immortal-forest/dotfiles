pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../colors"
import "../services"

/**
 * astralis — workspace dots for one monitor (ported from Ricelin
 * pill/Workspaces.qml, Theme→Colors / Motion tokens, hl.dsp→vanilla
 * dispatcher). No numbers, no icons: the active workspace is a wider filled
 * `Colors.primary` stick; the rest are small dim `Colors.on_surface_variant`
 * dots that brighten on hover. Clicking a dot focuses that workspace. The
 * active marker tracks the monitor's live active workspace name from the
 * Hyprland model (kept fresh by shell.qml's whitelisted refresh()).
 *
 * The dot range comes from this monitor's workspace rules ([[Workspacerules]])
 * so a rule-driven setup (e.g. monitors.lua splitting 1-5 / 6-10 across two
 * screens) always shows every assigned dot. A setup with no monitor-bound
 * rules (the current userpref.lua persistent workspaces) falls back to the
 * workspaces Hyprland currently has on this monitor plus the active one, so
 * dots still appear and grow as new workspaces are visited.
 *
 * That fallback derives everything from parseInt(w.name), never w.id — see
 * the long comment on `range` below for why (Hyprland 0.56 dropped the
 * numeric IPC id Quickshell's own id property still reads). One residual
 * limit worth knowing: Quickshell's workspace model only holds workspaces
 * it has actually seen fire an event (created/focused/etc.) since the shell
 * started — a persistent workspace nobody has touched yet this session
 * still won't have a dot even with this fix, exactly as the paragraph above
 * already describes ("grow as visited"). [[Workspacerules]] is the one path
 * that shows every assigned dot unconditionally, independent of that.
 */
Item {
    id: workspaces

    property string screenName: ""
    property real s: 1
    property real stickW: 20 * s
    property real dotW: 6 * s
    property real gap: 8 * s

    /**
     * `w.id` can't be trusted any more: Hyprland 0.56 dropped the numeric
     * `id` field from its workspace IPC (replaced by a string `address`),
     * and Quickshell's own `HyprlandWorkspace.id` is populated by reading
     * that now-absent JSON key — confirmed live against this exact build,
     * every entry reports id -1 (a freshly-constructed object) or 0 (one
     * sentinel some other internal path sets for the active workspace),
     * never the real workspace number. `w.name` is a separate JSON field
     * the schema change didn't touch, and is still correct — every id-keyed
     * lookup below reads parseInt(w.name) instead. Open upstream, unfixed
     * as of Quickshell 0.3.1: quickshell-mirror/quickshell#1149.
     *
     * `w.monitor` has a related but separate problem: on this build
     * Quickshell only resolves it reliably for the CURRENTLY ACTIVE
     * workspace — every other entry reports monitor: NULL even right after
     * Hyprland.refreshWorkspaces() (confirmed live), despite raw `hyprctl
     * workspaces -j` always carrying a real monitor string for all of
     * them. A single-monitor rig has nothing to disambiguate, so an
     * unresolved monitor is taken as "this one"; multi-monitor keeps the
     * old, stricter check (only count a workspace once its monitor
     * actually resolves) rather than risk the same dot appearing on every
     * screen. Workspacerules above stays the authoritative, live-state-
     * independent fix for multi-monitor — this fallback is best-effort.
     */
    readonly property var range: {
        var ruled = Workspacerules.byMonitor[screenName];
        if (ruled && ruled.length)
            return ruled;

        var out = [];
        var seen = ({});
        var wss = Hyprland.workspaces.values;
        var singleMonitor = Hyprland.monitors.values.length <= 1;
        for (var i = 0; i < wss.length; i++) {
            var w = wss[i];
            var n = parseInt(w.name);
            if (isNaN(n) || n < 1 || seen[n])
                continue;
            if (!singleMonitor && !(w.monitor && w.monitor.name === screenName))
                continue;
            seen[n] = true;
            out.push(n);
        }
        var a = parseInt(activeName);
        if (a >= 1 && !seen[a])
            out.push(a);
        out.sort(function (x, y) { return x - y; });
        return out;
    }

    readonly property string activeName: {
        var mons = Hyprland.monitors.values;
        for (var i = 0; i < mons.length; i++)
            if (mons[i].name === screenName)
                return mons[i].activeWorkspace ? mons[i].activeWorkspace.name : "";
        return "";
    }

    // Workspace NUMBER -> has-windows. Uses the per-workspace toplevel model,
    // not lastIpcObject.windows: on Hyprland 0.56 the workspace IPC object
    // Quickshell keeps is empty ({}), so .windows is undefined and no dot ever
    // read as filled. toplevels is the reliable occupancy signal.
    readonly property var occupied: {
        var m = ({});
        var wss = Hyprland.workspaces.values;
        for (var i = 0; i < wss.length; i++) {
            var w = wss[i];
            if (w.toplevels && w.toplevels.values.length > 0)
                m[parseInt(w.name)] = true;
        }
        return m;
    }

    property int hoverIndex: -1

    readonly property int activeIndex: range.indexOf(parseInt(activeName))

    /**
     * Centre x of a dot slot from target layout widths (active stick is
     * wider). Uses the animation end values, so a focus marker aimed here
     * (the Ame soul bead, later stage) lands where the dot settles and
     * doesn't chase the width Behavior.
     */
    function slotCenterX(idx) {
        let x = 0;
        for (let i = 0; i < idx; i++)
            x += (i === activeIndex ? stickW : dotW) + gap;
        return x + (idx === activeIndex ? stickW : dotW) / 2;
    }

    readonly property point activeDotPoint: {
        void workspaces.activeName;
        void workspaces.width;
        return Qt.point(slotCenterX(Math.max(0, activeIndex)), height / 2);
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: workspaces.gap

        Repeater {
            model: workspaces.range

            delegate: Item {
                id: slot

                required property var modelData
                required property int index

                readonly property string wsName: String(modelData)
                readonly property bool isActive: workspaces.activeName === wsName
                readonly property bool hasWindows: !!workspaces.occupied[parseInt(wsName)]

                // Each pip is a page in a radio group — exactly one workspace
                // is current, and clicking one switches to it. Saying so lets
                // assistive tech announce which of N you are on; a bare row of
                // 6px dots is otherwise unreadable. No press dip: on a dot this
                // small a scale change is invisible and only fights the
                // hover/occupancy swell the pip already does.
                Accessible.role: Accessible.PageTab
                Accessible.name: "Workspace " + slot.wsName
                Accessible.description: slot.isActive ? "Current workspace"
                    : (slot.hasWindows ? "Has windows" : "Empty")
                Accessible.checkable: true
                Accessible.checked: slot.isActive
                Accessible.onPressAction: Hyprland.dispatch("workspace " + slot.wsName)

                Layout.preferredWidth: slot.isActive ? workspaces.stickW : workspaces.dotW
                Layout.preferredHeight: 22 * workspaces.s
                Behavior on Layout.preferredWidth { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    // Occupied non-active dots swell a touch so having windows
                    // reads as weight, not just brightness — the active stick
                    // stays the widest. Width is uniform across non-active dots
                    // (height only), so the slotCenterX math the soul bead aims
                    // at is untouched.
                    height: slot.isActive ? workspaces.dotW : (slot.hasWindows ? workspaces.dotW : workspaces.dotW * 0.72)
                    radius: height / 2
                    color: slot.isActive ? Colors.primary : Colors.on_surface_variant
                    opacity: slot.isActive ? 1.0
                        : (slot.hasWindows ? (area.containsMouse ? 1.0 : 0.85)
                                           : (area.containsMouse ? 0.7 : 0.32))
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    Behavior on height { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.leftMargin: -workspaces.gap / 2
                    anchors.rightMargin: -workspaces.gap / 2
                    anchors.topMargin: -8 * workspaces.s
                    anchors.bottomMargin: -8 * workspaces.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + slot.wsName)
                    onContainsMouseChanged: {
                        if (containsMouse)
                            workspaces.hoverIndex = slot.index;
                        else if (workspaces.hoverIndex === slot.index)
                            workspaces.hoverIndex = -1;
                    }
                }
            }
        }
    }
}
