pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — the Hyprland-settings STORE + APPLY layer behind the 設 SETTINGS
 * surface (adapting Ricelin's model to astralis's Lua-based hypr config).
 *
 * ── The design (READ THIS before extending) ─────────────────────────────────
 *
 * Ricelin's settings pages regex-edit the user's own hypr modules/*.lua in
 * place (lib/setAnim.js & co.) and `hyprctl reload`. astralis's hypr config
 * is nested Lua (`hl.config`/`hl.animation` in ~/.config/hypr/hypr.d/*.lua,
 * a git-managed dotfiles tree) — machine-editing hand-written nested Lua is
 * brittle and dirties the user's repo, so astralis uses an OVERLAY model
 * instead. Three cooperating pieces:
 *
 *  1. STORE — ~/.cache/astralis/settings.json. A bare JSON object holding
 *     ONLY the keys the user has touched (untouched settings keep their
 *     hand-written hypr.d values; `defaults` below mirrors those values for
 *     page seeding). Read once at startup, mutated via set()/unset() which
 *     rewrite the whole file through FileView.setText — deliberately NOT a
 *     JsonAdapter and NOT watchChanges (the Events-singleton finding: a
 *     JsonAdapter writeAdapter round-trip races stale file state over the
 *     live object and loses back-to-back mutations).
 *
 *  2. LIVE APPLY — every set() debounces 200ms (a scrub drag lands its final
 *     value with exactly one process) into ONE
 *     `hyprctl --batch "keyword …; keyword …"` so the change is visible
 *     instantly, with no hyprland reload and no config-file churn.
 *
 *  3. RELOAD PERSISTENCE — the same debounce regenerates the Lua overlay
 *     ~/.cache/astralis/hypr-settings.lua (whole-file, from the store — no
 *     regex editing, nothing hand-written ever touched). The committed stub
 *     hypr.d/astralis-settings.lua dofile()s that overlay, and it is required
 *     LAST in hyprland.lua's module list, so on `hyprctl reload` the overlay
 *     re-asserts shell-edited settings over the hand-written values
 *     (hyprland keywords are last-wins). Deleting the cache file (or
 *     unset()ing the keys) reverts cleanly to the hand-written config.
 *
 * Nothing is applied at daemon startup: the overlay already persists across
 * hyprland reloads, and the live session either ran the overlay at its last
 * reload or got the keywords at edit time. (If the cache was wiped while
 * settings.json survived, the next edit regenerates the overlay.)
 *
 * Division of labour: shell-side prefs (clock format, glyphs, UI scale,
 * reduce-motion…) live in the Flags singleton (flags.json) — this singleton
 * owns exclusively what maps to Hyprland keywords.
 *
 * ── Extending ───────────────────────────────────────────────────────────────
 * Scalar `section:key` settings are table-driven: add the key to `defaults`,
 * its keyword to `scalarKeywords` and its Lua path to `scalarLua` — apply()
 * already loops them (Look and Input pages ride these tables). Structured
 * settings (the animation tree and the Display page's per-monitor `monitors`
 * dict below) get their own block in apply().
 *
 * `liveApply: false` lets a dev harness exercise the store + overlay without
 * firing hyprctl at the live session; storePath/overlayPath are settable for
 * the same reason (point them at /tmp scratch).
 */
Singleton {
    id: root

    /** Gate for the hyprctl side of apply(); harnesses switch it off. */
    property bool liveApply: true

    property string storePath: Quickshell.env("HOME") + "/.cache/astralis/settings.json"
    property string overlayPath: Quickshell.env("HOME") + "/.cache/astralis/hypr-settings.lua"

    /** Touched settings only. Reassigned wholesale so bindings through get() refresh. */
    property var data: ({})

    // File writes (persist + the overlay in apply) can't create the cache dir, so
    // they wait on dirReady — set once the async mkdir finishes — and any write
    // attempted before then is flushed from mkdirProc.onExited. Closes the
    // first-run race where the first setText could land before ~/.cache/astralis.
    property bool dirReady: false
    property bool pendingPersist: false
    property bool pendingApply: false

    /**
     * Defaults mirror the CURRENT hand-written hypr.d values (animations.lua,
     * general.lua, decorations.lua), so a page seeded from an untouched store
     * shows what the compositor is actually running, and writing a default
     * back is a visual no-op.
     */
    readonly property var defaults: ({
        // 動 ANIMATION (hypr.d/animations.lua)
        animEnabled: true,
        animSpeed: 6,                        // master speed for the motion leaves (ds)
        animCurve: [0.05, 0.9, 0.1, 1.05],   // bezier "wind" control points
        // Per-leaf STYLE, not just the curve's shape — a preset used to only
        // reach the "wind" bezier, so "Bouncy" and "Smooth" moved on the same
        // slide/fade regardless of pick. windows/windowsIn/windowsOut share
        // one style (Hyprland has no separate in/out style, only curve/speed);
        // workspaces has its own, since a slide that suits a window popping in
        // doesn't automatically suit a workspace swap.
        animWindowStyle: "slide",            // "slide" | "popin <percent>%" | "gnomed"
        animWorkspaceStyle: "",              // "" (leaf default) | "slide" | "slidevert" | "fade" | "slidefade <percent>%" | "slidefadevert <percent>%"
        // 飾 LOOK (hypr.d/general.lua + decorations.lua) — wired into
        // scalarKeywords/scalarLua below; the subpage just set()s them.
        gapsIn: 3,
        gapsOut: 8,
        borderSize: 2,
        resizeOnBorder: false,
        rounding: 10,
        blurEnabled: true,
        blurSize: 6,
        blurPasses: 3,
        blurXray: false,
        // Border colours are not in the hand-written hypr.d; these mirror the
        // compositor defaults (`hyprctl getoption general:col.*_border`), in
        // the keyword's own rgba(RRGGBBAA) literal form.
        activeBorder: "rgba(ffffffff)",
        inactiveBorder: "rgba(444444ff)",
        // 操 INPUT (hypr.d/input.lua; unset fields mirror the compositor /
        // libinput defaults — accel_profile unset means libinput's adaptive).
        kbLayout: "us",
        repeatRate: 25,
        repeatDelay: 600,
        sensitivity: 0,
        accelProfile: "adaptive",
        touchNaturalScroll: true,
        touchTapToClick: true,
        touchDwt: true,
        // 画 DISPLAY — structured `{ <output>: { mode, position, scale,
        // transform } }`, applied by its own block in apply() (not a scalar).
        monitors: ({})
    })

    /** Scalar setting → live `hyprctl keyword` name (follow-up pages extend). */
    readonly property var scalarKeywords: ({
        gapsIn: "general:gaps_in",
        gapsOut: "general:gaps_out",
        borderSize: "general:border_size",
        resizeOnBorder: "general:resize_on_border",
        rounding: "decoration:rounding",
        blurEnabled: "decoration:blur:enabled",
        blurSize: "decoration:blur:size",
        blurPasses: "decoration:blur:passes",
        blurXray: "decoration:blur:xray",
        activeBorder: "general:col.active_border",
        inactiveBorder: "general:col.inactive_border",
        kbLayout: "input:kb_layout",
        repeatRate: "input:repeat_rate",
        repeatDelay: "input:repeat_delay",
        sensitivity: "input:sensitivity",
        accelProfile: "input:accel_profile",
        touchNaturalScroll: "input:touchpad:natural_scroll",
        touchTapToClick: "input:touchpad:tap_to_click",
        touchDwt: "input:touchpad:disable_while_typing"
    })

    /** Scalar setting → overlay `hl.config` path (dot-nested, same order as the keyword map). */
    readonly property var scalarLua: ({
        gapsIn: "general.gaps_in",
        gapsOut: "general.gaps_out",
        borderSize: "general.border_size",
        resizeOnBorder: "general.resize_on_border",
        rounding: "decoration.rounding",
        blurEnabled: "decoration.blur.enabled",
        blurSize: "decoration.blur.size",
        blurPasses: "decoration.blur.passes",
        blurXray: "decoration.blur.xray",
        activeBorder: "general.col.active_border",
        inactiveBorder: "general.col.inactive_border",
        kbLayout: "input.kb_layout",
        repeatRate: "input.repeat_rate",
        repeatDelay: "input.repeat_delay",
        sensitivity: "input.sensitivity",
        accelProfile: "input.accel_profile",
        touchNaturalScroll: "input.touchpad.natural_scroll",
        touchTapToClick: "input.touchpad.tap_to_click",
        touchDwt: "input.touchpad.disable_while_typing"
    })

    /**
     * The animation leaves the master speed re-declares (mirroring
     * hypr.d/animations.lua's bezier/style per leaf). Deliberately NOT
     * border/borderangle: their hand-written speeds (1 / 30) are a different
     * scale — a Ricelin-style "set every leaf" would spin the border loop
     * wildly. The main curve edits bezier "wind" (windows / windowsMove /
     * workspaces); windowsIn/windowsOut keep their own in/out curves.
     */
    readonly property var animLeaves: [
        { leaf: "windows",     bezier: "wind",    style: "slide" },
        { leaf: "windowsIn",   bezier: "winIn",   style: "slide" },
        { leaf: "windowsOut",  bezier: "winOut",  style: "slide" },
        { leaf: "windowsMove", bezier: "wind",    style: "slide" },
        { leaf: "fade",        bezier: "default", style: "" },
        { leaf: "workspaces",  bezier: "wind",    style: "" }
    ]

    // ── store ───────────────────────────────────────────────────────────────

    function has(key) {
        return root.data !== null && root.data[key] !== undefined;
    }

    /** Touched value, else caller fallback, else the hand-config default. */
    function get(key, fallback) {
        if (root.has(key))
            return root.data[key];
        if (fallback !== undefined)
            return fallback;
        return root.defaults[key];
    }

    function set(key, value) {
        var next = {};
        for (var k in root.data)
            next[k] = root.data[k];
        next[key] = value;
        root.data = next;
        root.persist();
        applyTimer.restart();
    }

    /** Forget a key: back to the hand-written value on the next reload. */
    function unset(key) {
        if (!root.has(key))
            return;
        var next = {};
        for (var k in root.data)
            if (k !== key)
                next[k] = root.data[k];
        root.data = next;
        root.persist();
        applyTimer.restart();
    }

    function persist() {
        if (!root.dirReady) {
            root.pendingPersist = true;
            return;
        }
        file.setText(JSON.stringify(root.data, null, 2) + "\n");
    }

    /** Guarded read-once: a truncated or corrupt file is an empty store, never a throw. */
    function reloadStore() {
        var d = {};
        try {
            var t = file.text();
            if (t && t.trim().length > 0) {
                var parsed = JSON.parse(t);
                if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                    d = parsed;
            }
        } catch (e) {
            d = {};
        }
        root.data = d;
    }

    // ── apply (debounced: one hyprctl eval + one overlay write) ─────────────

    function fmtLua(v) {
        if (typeof v === "boolean")
            return v ? "true" : "false";
        if (typeof v === "string")
            // Escape for a Lua double-quoted string: backslash FIRST, then quote
            // and the control chars, so a value with " \ or a newline can't break
            // out of (or inject into) the generated overlay.
            return "\"" + v
                .replace(/\\/g, "\\\\")
                .replace(/"/g, "\\\"")
                .replace(/\n/g, "\\n")
                .replace(/\r/g, "\\r")
                .replace(/\t/g, "\\t") + "\"";
        return String(v);
    }

    /** "decoration.blur.size" + 6 → 'hl.config({ decoration = { blur = { size = 6 } } })' */
    function luaConfigLine(path, v) {
        var parts = path.split(".");
        var s = fmtLua(v);
        for (var i = parts.length - 1; i >= 0; i--)
            s = "{ " + parts[i] + " = " + s + " }";
        return "hl.config(" + s + ")";
    }

    /**
     * `hyprctl keyword`/`--batch` — this whole function's original live-apply
     * mechanism — turned out to never have worked, on any version, before or
     * after a full reboot: verified directly, `hyprctl keyword <anything>`
     * returns "unknown request" on this system even for a trivial built-in
     * option, while `getoption`/`monitors`/`reload` all work fine. This
     * Hyprland build is LUA-configured (the `hl.*` calls the overlay file
     * already writes), and apparently doesn't register the standard
     * keyword-value IPC handler at all — `hyprctl eval "<lua>"` is the
     * mechanism that actually works here, running the exact same `hl.*`
     * calls the overlay already generates, live, immediately (verified:
     * `hyprctl eval 'hl.config({ general = { gaps_in = 7 } })'` → "ok", and
     * the change actually lands per `getoption`).
     *
     * One real trap in `eval` specifically: passed a string that STARTS with
     * `--` (this file's own header comment, if included raw), hyprctl's own
     * argument parser reads it as an unrecognised CLI flag and prints the
     * top-level help instead of ever reaching the eval handler — silently,
     * with exit 0, so nothing in this function would have caught it. The
     * comment lines are only useful in the persisted overlay FILE for a
     * human reading it later; they add nothing to a live eval, so this
     * filters them (and blank separator lines) out before joining, rather
     * than special-casing just the first line.
     */
    function apply() {
        if (!root.dirReady) {
            root.pendingApply = true;
            return;
        }
        var lua = [
            "-- Generated by astralis (services/Settings.qml) — DO NOT EDIT.",
            "-- Shell-edited Hyprland settings; loaded last (hypr.d/astralis-settings.lua",
            "-- stub) so these override the hand-written hypr.d values on reload.",
            "-- Delete this file (or the keys in ~/.cache/astralis/settings.json) to revert.",
            ""
        ];

        // 動 animation tree
        if (root.has("animEnabled"))
            lua.push(luaConfigLine("animations.enabled", root.get("animEnabled")));
        var curveDirty = root.has("animCurve");
        if (curveDirty) {
            var c = root.get("animCurve");
            lua.push("hl.curve(\"wind\", { type = \"bezier\", points = { { "
                + c[0] + ", " + c[1] + " }, { " + c[2] + ", " + c[3] + " } } })");
        }
        // A redefined bezier only reliably lands on leaves re-declared after
        // it, so a curve edit re-emits the leaf lines too (with the current
        // master speed, touched or default). A style change re-emits the
        // same way — it is still just re-declaring the leaf, one field
        // different.
        var styleDirty = root.has("animWindowStyle") || root.has("animWorkspaceStyle");
        if (root.has("animSpeed") || curveDirty || styleDirty) {
            var sp = root.get("animSpeed");
            var winStyle = root.get("animWindowStyle");
            var wsStyle = root.get("animWorkspaceStyle");
            for (var i = 0; i < root.animLeaves.length; i++) {
                var l = root.animLeaves[i];
                // windows/windowsIn/windowsOut take the shared window style;
                // workspaces takes its own; fade has no style axis at all —
                // both overrides are no-ops there since l.style stays "".
                var style = l.leaf === "workspaces" ? wsStyle
                    : (l.leaf.indexOf("windows") === 0 ? winStyle : l.style);
                lua.push("hl.animation({ leaf = \"" + l.leaf + "\", enabled = true, speed = " + sp
                    + ", bezier = \"" + l.bezier + "\""
                    + (style.length > 0 ? ", style = \"" + style + "\"" : "") + " })");
            }
        }

        // table-driven scalars (the Look/Input pages set() these keys)
        for (var key in root.scalarKeywords) {
            if (!root.has(key))
                continue;
            lua.push(luaConfigLine(root.scalarLua[key], root.get(key)));
        }

        // 画 display tree — one whole-spec monitor line per stored output
        // ({ mode, position, scale, transform }, written by the Display page
        // on a confirmed Keep). `monitor` is last-wins per output, so the
        // overlay re-asserts the shell-picked spec over hypr.d/monitor.lua;
        // hand-written extras on that output (bitdepth 10) fall back to their
        // defaults while an entry is stored — unset("monitors") to revert.
        if (root.has("monitors")) {
            var mons = root.get("monitors");
            for (var mName in mons) {
                var m = mons[mName];
                lua.push("hl.monitor({ output = \"" + mName + "\", mode = \"" + m.mode
                    + "\", position = \"" + m.position + "\", scale = " + m.scale
                    + ", transform = " + m.transform + " })");
            }
        }

        overlay.setText(lua.join("\n") + "\n");
        var evalLines = lua.filter(function (l) {
            var t = l.trim();
            return t.length > 0 && t.indexOf("--") !== 0;
        });
        if (root.liveApply && evalLines.length > 0)
            Quickshell.execDetached(["hyprctl", "eval", evalLines.join("\n")]);
    }

    Timer {
        id: applyTimer
        interval: 200
        repeat: false
        onTriggered: root.apply()
    }

    // ── files ───────────────────────────────────────────────────────────────

    FileView {
        id: file
        path: root.storePath
        blockLoading: true
        printErrors: false
        atomicWrites: true
        // Missing store is a fresh start; it materialises on the first set().
    }

    FileView {
        id: overlay
        path: root.overlayPath
        blockLoading: true
        printErrors: false
        atomicWrites: true
    }

    onStorePathChanged: reloadStore()

    // setText can't create directories; create the cache dir before the first
    // persist/overlay write (reloadStore is a read, fine before the dir exists),
    // then flush any write deferred while the dir was still missing.
    Component.onCompleted: {
        mkdirProc.running = true;
        reloadStore();
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.cache/astralis"]
        onExited: {
            root.dirReady = true;
            if (root.pendingPersist) {
                root.pendingPersist = false;
                root.persist();
            }
            if (root.pendingApply) {
                root.pendingApply = false;
                root.apply();
            }
        }
    }
}
