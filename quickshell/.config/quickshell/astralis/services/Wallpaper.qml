pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

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

    /**
     * `current` as an image Qt can decode at full size — there is no webp
     * plugin here, and a skwd LIVE wallpaper records its 640×360
     * video-thumbs/*.webp. A jpg/png is itself; anything else becomes one
     * full-res frame of the source video (found like setwall finds a thumb's
     * full image), or the file converted, cached in ~/.cache/astralis/stills/.
     * "" while that runs (~0.5 s). Read by Retroact Rain and the depth cut-out.
     */
    property string still: ""
    onCurrentChanged: refreshStill()
    function refreshStill() {
        if (!root.current.length) {
            root.still = "";
            return;
        }
        if (/\.(jpe?g|png|bmp)$/i.test(root.current)) {
            root.still = root.current;
            return;
        }
        root.still = "";
        if (stillProc.running)
            return;     // onExited re-runs for the newest wallpaper
        stillProc.src = root.current;
        stillProc.command = ["sh", "-c", root.stillScript, "_", root.current];
        stillProc.running = true;
    }
    readonly property string stillScript: '
        src="$1"; out="$HOME/.cache/astralis/stills"; mkdir -p "$out"
        case "$src" in
          */video-thumbs/*)
            b="${src##*/}"; b="${b%.*}"; name="${b##*--}"; cand=""
            lw="$HOME/.cache/skwd-wall-v2/last-wallpaper.json"
            [ -f "$lw" ] && command -v jq >/dev/null && cand="$(jq -r ".path // empty" "$lw" 2>/dev/null)"
            c="${cand##*/}"
            if [ -n "$cand" ] && [ -f "$cand" ] && [ "${c%.*}" = "$name" ]; then src="$cand"
            else f="$(find -H "$HOME/wallpapers" -type f -name "$name.*" 2>/dev/null | head -n1)"; [ -n "$f" ] && src="$f"; fi ;;
        esac
        dst="$out/$(stat -c "%n %Y" "$src" | md5sum | cut -c1-16).jpg"
        [ -s "$dst" ] || ffmpeg -loglevel error -y -i "$src" -frames:v 1 -vf "scale=min(3840\\,iw):-2" -q:v 2 "$dst" </dev/null || exit 1
        printf "%s\\n" "$dst"'
    Process {
        id: stillProc
        property string src: ""
        stdout: StdioCollector { id: stillOut }
        stderr: StdioCollector { id: stillErr }
        onExited: function (code) {
            if (stillProc.src !== root.current) {
                root.refreshStill();
                return;
            }
            var p = stillOut.text.trim().split("\n").pop();
            if (code !== 0 || !p.length)
                console.warn("astralis Wallpaper: no still for", root.current, stillErr.text.trim());
            root.still = code === 0 && p.length ? p : "";
        }
    }

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

    /**
     * Redraw the screens left after a monitor unplugs. skwd-walld (beta.26)
     * reaps the still renderer that every output shares when ANY output
     * departs, and only spawns a new one when an output is added, so pulling
     * the MSI's cable left the laptop bare until it was plugged back in. 4 s
     * after a removal with no re-add (a monitor waking from standby re-plugs
     * within ~3 s, and skwd restores that itself), ask skwd to re-apply each
     * connected output's current wallpaper.
     */
    readonly property string redrawScript: '
        command -v skwd-helm >/dev/null && command -v jq >/dev/null || exit 0
        skwd-helm current --json | jq -r ".outputs[] | select(.connected) | [.name, (.current // .path // empty)] | @tsv" |
        while IFS="\t" read -r o p; do
            [ -n "$p" ] && skwd-helm apply "$p" --output "$o"
        done'
    Timer {
        id: redraw
        interval: 4000
        onTriggered: Quickshell.execDetached(["sh", "-c", root.redrawScript])
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "monitorremoved" || event.name === "monitorremovedv2")
                redraw.restart();
            else if (event.name === "monitoradded" || event.name === "monitoraddedv2")
                redraw.stop();
        }
    }
}
