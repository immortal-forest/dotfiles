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

    // ── apply (debounced: one hyprctl batch + one overlay write) ────────────

    function fmtKw(v) {
        return typeof v === "boolean" ? (v ? "1" : "0") : String(v);
    }

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

    function apply() {
        if (!root.dirReady) {
            root.pendingApply = true;
            return;
        }
        var kws = [];
        var lua = [
            "-- Generated by astralis (services/Settings.qml) — DO NOT EDIT.",
            "-- Shell-edited Hyprland settings; loaded last (hypr.d/astralis-settings.lua",
            "-- stub) so these override the hand-written hypr.d values on reload.",
            "-- Delete this file (or the keys in ~/.cache/astralis/settings.json) to revert.",
            ""
        ];

        // 動 animation tree
        if (root.has("animEnabled")) {
            kws.push("keyword animations:enabled " + fmtKw(root.get("animEnabled")));
            lua.push(luaConfigLine("animations.enabled", root.get("animEnabled")));
        }
        var curveDirty = root.has("animCurve");
        if (curveDirty) {
            var c = root.get("animCurve");
            kws.push("keyword bezier wind," + c.join(","));
            lua.push("hl.curve(\"wind\", { type = \"bezier\", points = { { "
                + c[0] + ", " + c[1] + " }, { " + c[2] + ", " + c[3] + " } } })");
        }
        // A redefined bezier only reliably lands on leaves re-declared after
        // it, so a curve edit re-emits the leaf lines too (with the current
        // master speed, touched or default).
        if (root.has("animSpeed") || curveDirty) {
            var sp = root.get("animSpeed");
            for (var i = 0; i < root.animLeaves.length; i++) {
                var l = root.animLeaves[i];
                kws.push("keyword animation " + l.leaf + ",1," + sp + "," + l.bezier
                    + (l.style.length > 0 ? "," + l.style : ""));
                lua.push("hl.animation({ leaf = \"" + l.leaf + "\", enabled = true, speed = " + sp
                    + ", bezier = \"" + l.bezier + "\""
                    + (l.style.length > 0 ? ", style = \"" + l.style + "\"" : "") + " })");
            }
        }

        // table-driven scalars (the Look/Input pages set() these keys)
        for (var key in root.scalarKeywords) {
            if (!root.has(key))
                continue;
            kws.push("keyword " + root.scalarKeywords[key] + " " + fmtKw(root.get(key)));
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
                kws.push("keyword monitor " + mName + "," + m.mode + ","
                    + m.position + "," + m.scale + ",transform," + m.transform);
                lua.push("hl.monitor({ output = \"" + mName + "\", mode = \"" + m.mode
                    + "\", position = \"" + m.position + "\", scale = " + m.scale
                    + ", transform = " + m.transform + " })");
            }
        }

        overlay.setText(lua.join("\n") + "\n");
        if (root.liveApply && kws.length > 0)
            Quickshell.execDetached(["hyprctl", "--batch", kws.join("; ")]);
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
