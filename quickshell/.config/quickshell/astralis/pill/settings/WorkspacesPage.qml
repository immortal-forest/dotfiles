pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Quickshell.Hyprland
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 場 WORKSPACES settings page (ported from Ricelin
 * pill/Workspaces.qml, the surface listing each space with its note on the
 * left and a chip on the right). What it lists here is Hyprland's live
 * workspace rules: one row per rule from `hyprctl workspacerules -j`
 * (persistent / default badges, live open-now state from the Hyprland model)
 * with the rule's monitor chip on the right, plus a per-monitor assignment
 * section from the Workspacerules singleton (the same map that drives the
 * pill's workspace dots).
 *
 * Ricelin delta: Ricelin's surface managed its own Spaces store (create /
 * remove special workspaces, chord capture, SpaceApps drill-in). astralis
 * workspace rules are hand-written Lua (hypr.d/userpref.lua), and
 * machine-writing rules is out of scope for the Lua config — so this page is
 * a READ-ONLY view of the live rules, stated in the note under the header:
 * edit the Lua and `hyprctl reload` to change them (the page re-reads on
 * every open; the singleton re-reads on configreloaded).
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    rows: []

    /** Normalized rules from `hyprctl workspacerules -j`. */
    property var rules: []

    readonly property var monitorKeys: Object.keys(Workspacerules.byMonitor)

    function refresh() {
        Workspacerules.refresh();
        rulesProc.running = true;
    }

    onActiveChanged: if (active) refresh()

    /** Live workspace for `id` out of the passed model values (passed in so the binding tracks them). */
    function liveWs(values, id) {
        if (isNaN(id))
            return null;
        for (var i = 0; i < values.length; i++)
            if (values[i].id === id)
                return values[i];
        return null;
    }

    Process {
        id: rulesProc
        command: ["hyprctl", "workspacerules", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [];
                try {
                    var raw = JSON.parse(this.text);
                    for (var i = 0; i < raw.length; i++) {
                        var r = raw[i];
                        out.push({
                            ws: String(r.workspaceString),
                            id: parseInt(r.workspaceString),
                            monitor: r.monitor || "",
                            persistent: r.persistent === true,
                            isDefault: r["default"] === true
                        });
                    }
                } catch (e) {
                    out = [];
                }
                root.rules = out;
            }
        }
    }

    /** Right-side chip shared by the rule and assignment rows. */
    component SideChip: Rectangle {
        property string label: ""
        width: chipText.implicitWidth + 20 * root.s
        height: 22 * root.s
        radius: 9 * root.s
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Colors.on_surface, 0.06)

        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.label
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 10.5 * root.s
            font.weight: Font.DemiBold
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "場"
        title: "WORKSPACES"
        onBack: root.back()
    }

    /** The limitation, up front: this is a viewer over the Lua-owned rules. */
    Text {
        id: note
        anchors.top: header.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 4 * root.s
        anchors.rightMargin: 4 * root.s
        text: "Read-only — workspace rules are hand-written Lua (hypr.d). Edit there and `hyprctl reload`; this view follows."
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 10 * root.s
        font.weight: Font.Medium
        wrapMode: Text.WordWrap
        lineHeight: 1.25
    }

    Flickable {
        id: flick
        anchors.top: note.bottom
        anchors.topMargin: 4 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: returnToBounds()

        Column {
            id: content
            width: flick.width
            spacing: 0

            SettingsGroupLabel {
                s: root.s
                text: root.rules.length > 0 ? "Rules · " + root.rules.length : "Rules"
            }

            Repeater {
                model: root.rules

                delegate: SettingsRow {
                    id: ruleRow
                    required property int index
                    required property var modelData

                    readonly property var live: root.liveWs(Hyprland.workspaces.values, ruleRow.modelData.id)

                    surface: root
                    icon: "app-window"
                    name: isNaN(ruleRow.modelData.id) ? ruleRow.modelData.ws : "Workspace " + ruleRow.modelData.ws
                    sub: {
                        var b = [];
                        if (ruleRow.modelData.persistent) b.push("persistent");
                        if (ruleRow.modelData.isDefault) b.push("default");
                        if (ruleRow.live)
                            b.push(ruleRow.live.active ? "active now" : "open now");
                        return b.join(" · ");
                    }
                    last: ruleRow.index === root.rules.length - 1

                    Row {
                        spacing: 8 * root.s

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: ruleRow.live !== null
                            width: 6 * root.s
                            height: 6 * root.s
                            radius: width / 2
                            color: ruleRow.live && ruleRow.live.active
                                ? Colors.primary : Qt.alpha(Colors.on_surface_variant, 0.5)
                        }

                        SideChip {
                            anchors.verticalCenter: parent.verticalCenter
                            label: ruleRow.modelData.monitor.length > 0
                                ? ruleRow.modelData.monitor : "any monitor"
                        }
                    }
                }
            }

            Text {
                visible: root.rules.length === 0
                topPadding: 4 * root.s
                leftPadding: 12 * root.s
                text: "No workspace rules defined"
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.italic: true
            }

            SettingsGroupLabel { s: root.s; text: "Monitor assignments" }

            Repeater {
                model: root.monitorKeys

                delegate: SettingsRow {
                    id: monRow
                    required property int index
                    required property var modelData

                    surface: root
                    icon: "monitor"
                    name: monRow.modelData
                    sub: "Workspaces pinned to this output"
                    captionOnFocus: true
                    last: monRow.index === root.monitorKeys.length - 1

                    SideChip {
                        label: (Workspacerules.byMonitor[monRow.modelData] || []).join(" · ")
                    }
                }
            }

            Text {
                visible: root.monitorKeys.length === 0
                topPadding: 4 * root.s
                leftPadding: 12 * root.s
                width: parent.width
                text: "None — no rule names a monitor, so workspaces open on the focused one"
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.italic: true
                wrapMode: Text.WordWrap
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
