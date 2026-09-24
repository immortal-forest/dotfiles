pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — wallpaper theming bridge.
 *
 * Wallpaper SELECTION + DISPLAY is owned by skwd-wall (skwd-wall-v2 picker →
 * skwd-walld draws via its own skwd-paper engine with a GPU shader transition).
 * astralis owns only the THEMING: skwd's externalMatugenCommand hook calls
 * scripts/setwall per pick, which resolves the full-res image, then runs matugen +
 * chroma-rescue + base16/pywal and writes Colors.json + the app configs.
 *
 * This singleton exposes two things the shell still needs:
 *   - `current`  — the wallpaper on screen, mirrored live from
 *     ~/.cache/astralis/current-wallpaper (written by setwall, whoever ran it),
 *     consumed by the lock screen background.
 *   - `retheme()` — recolour from the current wallpaper WITHOUT re-displaying it,
 *     fired when an Appearance setting (paletteMode / wallReseed / base16Shell)
 *     changes so the palette repaints live.
 */
Singleton {
    id: root

    readonly property string setwall: Quickshell.env("HOME") + "/.config/quickshell/astralis/scripts/setwall"

    // The wallpaper on screen; "" until one has ever been set.
    property string current: ""

    FileView {
        path: Quickshell.env("HOME") + "/.cache/astralis/current-wallpaper"
        watchChanges: true      // stays live across external setwall runs
        printErrors: false      // silent before the first apply
        onFileChanged: reload()
        onLoaded: root.current = text().trim()
    }

    /**
     * Live palette refresh when an Appearance setting changes: recolour from the
     * CURRENT wallpaper without re-displaying it — RETHEME_ONLY skips recording a
     * new current-wallpaper, so only matugen + chroma-rescue + base16 re-run.
     * Debounced so dragging across a segmented control fires one retheme, not
     * three. Fire-and-forget: setwall rewrites Colors.json, which the Colors
     * singleton already watches.
     */
    function retheme() {
        if (!root.current.length)
            return;
        Quickshell.execDetached(["sh", "-c", 'RETHEME_ONLY=1 exec "$1" "$2"', "_", root.setwall, root.current]);
    }
    Timer {
        id: rethemeDebounce
        interval: 400
        onTriggered: root.retheme()
    }
    Connections {
        target: Flags
        function onWallReseedChanged() { rethemeDebounce.restart(); }
        function onPaletteModeChanged() { rethemeDebounce.restart(); }
        function onBase16ShellChanged() { rethemeDebounce.restart(); }
    }
}
