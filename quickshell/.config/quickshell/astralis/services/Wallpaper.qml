pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — wallpaper bridge (backend only; the picker grid is a pill
 * surface that consumes this API).
 *
 * All applies route through scripts/setwall (awww + matugen + cache write),
 * so the picker, the random keybind, and any future caller share the exact
 * same transition, palette rewrite, and state path. `current` mirrors
 * ~/.cache/astralis/current-wallpaper via a watching FileView, so it stays
 * live no matter who wrote it (this shell, a terminal, restore-on-login).
 *
 * setwall blocks through the whole transition + matugen run (~1-2s); a pick
 * landing in that window is queued (newest wins) and replayed once the
 * running apply exits, so rapid iteration converges on the last pick
 * (Ricelin Walls.qml's queued-apply idea).
 */
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/wallpapers"
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
     * Every image under `dir`, scanned RECURSIVELY — the wallpapers are
     * organized into theme subfolders (~/wallpapers/<Theme>/*.jpg), so a flat
     * FolderListModel would only see the folders. Exposed as
     * [{ path, name, theme }]; the picker consumes this. `-type f` skips the
     * `wall.set` symlink; the extension filter skips `wall.conf`.
     */
    property var list: []

    /**
     * The unique theme folders in `list`, as [{ name, cover }] sorted by name.
     * `cover` is the first image in the folder (list is find|sort output, so
     * "first" is stable). The picker's folder-level carousel consumes this.
     */
    readonly property var folders: {
        const seen = ({});
        const out = [];
        for (let i = 0; i < root.list.length; i++) {
            const w = root.list[i];
            if (!w.theme || !w.theme.length || seen[w.theme] === true)
                continue;
            seen[w.theme] = true;
            out.push({ name: w.theme, cover: w.path });
        }
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }

    function rescan() { scanProc.running = true; }
    Process {
        id: scanProc
        running: true
        command: ["sh", "-c",
            "find \"$1\" -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort",
            "_", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text.trim();
                if (!out.length) { root.list = []; return; }
                root.list = out.split("\n").map(p => {
                    const seg = p.split("/");
                    return { path: p, name: seg[seg.length - 1], theme: seg.length >= 2 ? seg[seg.length - 2] : "" };
                });
            }
        }
    }

    // Newest apply requested while applyProc was still running; replayed on exit.
    property string queuedApply: ""
    // Apply waiting on the cursor-position probe (newest wins there too).
    property string pendingApply: ""

    /**
     * Apply a wallpaper. The awww 'grow' circle originates at the cursor:
     * before running setwall we probe hyprctl for the cursor position and the
     * monitor layout, convert the cursor to a fraction of the monitor under it
     * and hand that to setwall as POS ("fx,fy" percentages — scale- and
     * resolution-independent). If the probe fails (no Hyprland socket, odd
     * output), POS falls back to "center".
     */
    function set(path) {
        if (!path || !path.length)
            return;
        if (applyProc.running) {
            root.queuedApply = path;
            return;
        }
        root.pendingApply = path;
        if (!posProc.running)
            posProc.running = true;
    }

    function random() {
        if (randomProc.running)
            return;
        randomProc.running = true;
    }

    /**
     * Live palette refresh when the "Wallpaper boost" setting (Flags.wallReseed)
     * changes: recolour from the CURRENT wallpaper without re-sweeping it in —
     * RETHEME_ONLY skips the awww transition, so only matugen + the chroma rescue
     * re-run. Debounced so dragging across the segmented control fires one
     * retheme, not three. Fire-and-forget: matugen rewrites Colors.json, which
     * the Colors singleton is already watching.
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
        // Palette mode / "flip the pill to base16 too": same live-repaint
        // path as wallReseed — RETHEME_ONLY recomputes from the current
        // wallpaper (base16-apps + optional shell remap) without re-sweeping
        // a new one in.
        function onPaletteModeChanged() { rethemeDebounce.restart(); }
        function onBase16ShellChanged() { rethemeDebounce.restart(); }
    }

    // Cursor probe: "X, Y" global logical coords + the monitor layout, in one
    // shell so a single collector sees both (separated by a marker line).
    Process {
        id: posProc
        command: ["sh", "-c", "hyprctl cursorpos 2>/dev/null; echo '---'; hyprctl monitors -j 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = root.pendingApply;
                root.pendingApply = "";
                if (!path.length)
                    return;
                root.apply(path, root.cursorFraction(this.text));
            }
        }
    }

    /**
     * Parse the posProc probe into an awww --transition-pos value: the cursor
     * as a fraction of the monitor it is on ("0.413,0.782"). hyprctl monitors
     * gives physical width/height + scale (+ transform, which swaps the axes
     * when odd), so the logical size is derived; hyprctl cursorpos is already
     * global logical. awww measures y from the BOTTOM, so fy is inverted, and
     * toFixed keeps a decimal point so awww parses percentages, not pixels.
     */
    function cursorFraction(out) {
        try {
            const parts = out.split("---");
            if (parts.length < 2)
                return "center";
            const cur = parts[0].trim().split(",");
            const cx = parseFloat(cur[0]);
            const cy = parseFloat(cur[1]);
            if (!isFinite(cx) || !isFinite(cy))
                return "center";
            const mons = JSON.parse(parts[1].trim());
            let mon = null, lw = 0, lh = 0;
            for (let i = 0; i < mons.length; i++) {
                const m = mons[i];
                const swap = m.transform % 2 === 1;   // 90°/270° rotations
                const w = (swap ? m.height : m.width) / m.scale;
                const h = (swap ? m.width : m.height) / m.scale;
                const contains = cx >= m.x && cx <= m.x + w && cy >= m.y && cy <= m.y + h;
                if (contains || (mon === null && m.focused === true)) {
                    mon = m; lw = w; lh = h;
                    if (contains)
                        break;
                }
            }
            if (mon === null || lw <= 0 || lh <= 0)
                return "center";
            const fx = Math.min(1, Math.max(0, (cx - mon.x) / lw));
            const fy = 1 - Math.min(1, Math.max(0, (cy - mon.y) / lh));
            return fx.toFixed(3) + "," + fy.toFixed(3);
        } catch (e) {
            return "center";
        }
    }

    function apply(path, pos) {
        applyProc.command = ["sh", "-c", 'POS="$1" exec "$2" "$3"', "_", pos, root.setwall, path];
        applyProc.running = true;
    }

    Process {
        id: applyProc
        onExited: {
            if (root.queuedApply.length) {
                const next = root.queuedApply;
                root.queuedApply = "";
                root.set(next);     // re-probe the cursor for the queued pick
            }
        }
    }

    Process {
        id: randomProc
        command: ["sh", "-c",
            "find \"$1\" -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | shuf -n1",
            "_", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const pick = this.text.trim();
                if (pick.length)
                    root.set(pick);
            }
        }
    }
}
