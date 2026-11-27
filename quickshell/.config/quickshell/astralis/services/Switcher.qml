pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

/**
 * astralis — Alt+Tab. State for the pill's 窓 switcher surface
 * (pill/surfaces/Windows.qml); shell.qml opens/closes the surface from `shown`.
 *
 * Hyprland binds (hypr.d/keybinds.lua) → GlobalShortcuts in shell.qml:
 *   Alt+Tab        next()    first press: snapshot the windows, aim at the last one
 *   Alt+Shift+Tab  prev()
 *   Alt release    commit()  (a release, non-consuming bind)
 * A tap shorter than `revealDelay` switches straight to the last window
 * without drawing the switcher; holding Alt shows it.
 *
 * The window list is a snapshot of `hyprctl clients -j` taken when Alt+Tab
 * starts, in most-recently-used order (focusHistoryID), so it doesn't
 * reshuffle while you cycle. Special workspaces (scratchpads, the minimized
 * tray) are left out.
 */
Singleton {
    id: root

    /** A switch is under way (Alt still held). */
    property bool active: false
    /** The switcher surface is showing. */
    property bool shown: false
    property int index: 0
    /** [{ address, cls, title, ws }] in MRU order. */
    property var windows: []
    readonly property var selected: index >= 0 && index < windows.length ? windows[index] : null

    readonly property int revealDelay: 140
    property bool commitWhenLoaded: false
    property int pendingStep: 1

    /** focusHistoryID, 0 = focused now; unknown last. */
    function mru(c) {
        return typeof c.focusHistoryID === "number" ? c.focusHistoryID : 99;
    }

    function next() { root.step(1); }
    function prev() { root.step(-1); }

    function step(d) {
        if (!root.active) {
            root.active = true;
            root.shown = false;
            root.commitWhenLoaded = false;
            root.pendingStep = d;
            root.windows = [];
            root.index = 0;
            snap.running = true;
            reveal.restart();
            return;
        }
        if (root.windows.length === 0) {
            root.pendingStep += d;
            return;
        }
        root.index = ((root.index + d) % root.windows.length + root.windows.length) % root.windows.length;
    }

    function commit() {
        if (!root.active)
            return;
        if (root.windows.length === 0 && snap.running) {
            // Released before the snapshot landed: switch once it does.
            root.commitWhenLoaded = true;
            return;
        }
        const w = root.selected;
        root.finish();
        if (w)
            Hyprland.dispatch("hl.dsp.focus({ window = " + JSON.stringify("address:" + w.address) + " })");
    }

    /** Pick a window directly (a click on its tile). */
    function choose(i) {
        if (i >= 0 && i < root.windows.length) {
            root.index = i;
            root.commit();
        }
    }

    function cancel() {
        root.finish();
    }

    function finish() {
        reveal.stop();
        root.active = false;
        root.shown = false;
        root.commitWhenLoaded = false;
    }

    Timer {
        id: reveal
        interval: root.revealDelay
        onTriggered: if (root.active) root.shown = true
    }

    Process {
        id: snap
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    list = [];
                }
                const wins = list
                    .filter(c => c && c.mapped !== false && c.workspace && c.workspace.id >= 0
                                 && !String(c.workspace.name || "").startsWith("special:"))
                    .sort((a, b) => root.mru(a) - root.mru(b))
                    .map(c => ({
                        address: c.address,
                        cls: c.class || c.initialClass || "",
                        title: c.title || c.initialTitle || c.class || "",
                        ws: c.workspace.name || String(c.workspace.id)
                    }));
                root.windows = wins;
                if (wins.length === 0) {
                    root.finish();
                    return;
                }
                // The first press aims at the previous window (index 1).
                const start = wins.length > 1 ? root.pendingStep : 0;
                root.index = ((start % wins.length) + wins.length) % wins.length;
                if (root.commitWhenLoaded)
                    root.commit();
            }
        }
    }
}
