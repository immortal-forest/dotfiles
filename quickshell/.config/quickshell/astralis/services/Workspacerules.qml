pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * astralis — persistent workspace→monitor map from Hyprland's workspace rules
 * (`hyprctl workspacerules -j`), ported from Ricelin Singletons/Workspacerules.
 *
 * Single source for a rule-driven monitor split (e.g. monitors.lua assigning
 * 1-5 / 6-10 across two screens), so the pill's workspace dots show every
 * assigned workspace on a monitor even before it has been visited, without
 * hardcoding monitor names. Rules with no monitor field (plain persistent
 * workspaces) are skipped, so a setup like the current userpref.lua leaves
 * `byMonitor` empty and the dots fall back to live workspaces. Re-read on
 * `configreloaded`, since editing the Lua config rewrites the rules.
 */
Singleton {
    id: root

    property var byMonitor: ({})

    function refresh() {
        proc.running = true;
    }

    Process {
        id: proc
        command: ["hyprctl", "workspacerules", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                try {
                    var rules = JSON.parse(this.text);
                    for (var i = 0; i < rules.length; i++) {
                        var ws = parseInt(rules[i].workspaceString);
                        var mon = rules[i].monitor;
                        if (!mon || isNaN(ws))
                            continue;
                        if (!map[mon])
                            map[mon] = [];
                        map[mon].push(ws);
                    }
                } catch (e) {
                    return;
                }
                for (var k in map)
                    map[k].sort(function (a, b) { return a - b; });
                root.byMonitor = map;
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
