pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — live Material 3 color tokens, with a central vibrancy layer.
 *
 * matugen renders `colors/Colors.json` (all 49 M3 roles) on every wallpaper
 * change; this singleton watches it and reparses on change, so every
 * `Colors.<role>` binding recolors the whole shell live — no restart.
 *
 * ── Vibrancy (Settings → Appearance → Colorfulness) ────────────────────────
 * `vibrancy` (0 subtle / 1 balanced / 2 bold, pushed in from Flags.uiColor by
 * a Binding in Flags.qml so this singleton stays dependency-free) recolors the
 * WHOLE shell from one place instead of touching 350+ call sites:
 *   • accent roles get a saturation FLOOR (+ a boost at higher levels), so a
 *     washed-out or near-grey wallpaper never yields dead-grey accents — the
 *     shell-side half of the "matugen went grey" fix. It's a floor, so already
 *     vivid palettes are untouched.
 *   • neutral surfaces / outlines / the dim body text are blended a little way
 *     toward the wallpaper's accent HUE (at their own lightness, so dark stays
 *     dark), which is what makes the surfaces read "colourful" rather than
 *     grey. Subtle = 0 blend (faithful matugen), balanced/bold add tint.
 * The transforms run only on a palette reparse or a vibrancy change (both
 * rare), reading colours as `#rrggbb` strings straight from `_data`.
 *
 * `_data` is parsed imperatively from `onLoaded` (and once on construction), so
 * a live reload re-parses without any binding-loop hazard. Fallbacks (a
 * neutral-dark M3 scheme) apply only if Colors.json is absent/bad.
 */
Singleton {
    id: root

    // Parsed matugen palette; reassigned imperatively (never a binding → no loop).
    property var _data: ({})
    property string _lastText: ""
    function _reparse() {
        var t = file.text() || "{}";
        if (t === root._lastText)
            return;
        root._lastText = t;
        try { root._data = JSON.parse(t); }
        catch (e) { root._data = ({}); }
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/quickshell/astralis/colors/Colors.json"
        blockLoading: true      // synchronous load so the reparse below has text
        watchChanges: true      // retheme on every `matugen image <wall>`
        printErrors: false      // silent when the file doesn't exist yet
        onFileChanged: reload()
        onLoaded: root._reparse()   // re-parse on initial load and every reload
    }
    Component.onCompleted: _reparse()

    /**
     * Reload backstop. matugen rewrites Colors.json atomically (temp file +
     * rename), which on a long-running daemon can orphan Qt's inotify watch
     * after the first change, so `watchChanges` alone intermittently misses a
     * retheme. Re-reading the tiny JSON on a slow cadence guarantees the palette
     * catches up within ~1.5s; the `_lastText` guard makes an unchanged read
     * free, so this never churns.
     */
    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: file.reload()
    }

    // ── vibrancy engine ───────────────────────────────────────────────────
    // 0 subtle / 1 balanced / 2 bold. Written by a Binding in Flags.qml
    // (Flags.uiColor); plain property so that Binding can drive it. Default 1
    // (balanced) so a fresh install is colourful out of the box.
    property int vibrancy: 1
    readonly property int _v: Math.max(0, Math.min(2, vibrancy))

    // ── base16 shell bypass ────────────────────────────────────────────────
    // base16 (Settings → Appearance → Palette, "Flip the pill to base16 too")
    // is already a final, deliberately-chosen palette by the time it lands in
    // Colors.json — re-applying the saturation floor/boost and hue-tint below
    // would fight a palette that was never matugen's neutral M3 output.
    // Written by a Binding in Flags.qml (paletteMode !== "material" &&
    // base16Shell); plain property, default false, so material mode (the vast
    // majority of the time) is completely unaffected — _vivid/_tint fall
    // through to their original math exactly as before.
    property bool bypassTint: false

    // Accent saturation floor + boost. The wallpaper-boost pipeline (setwall)
    // now owns how colourful the PALETTE is, so this stays gentle: it lifts a
    // dead-grey accent a little at the higher levels without re-colourising a
    // deliberately neutral (grayscale-wallpaper → scheme-neutral) palette. A
    // no-op on already-saturated accents — it's a floor, not a target.
    readonly property real _satFloor: [0.00, 0.12, 0.28][_v]
    readonly property real _satBoost: [0.00, 0.08, 0.18][_v]
    // Extra chroma (absolute HSL saturation) pushed into neutral roles, which
    // are also snapped to the accent hue. matugen's dark neutrals are near-grey
    // and already roughly accent-hued, so a pure hue-shift is a no-op — raising
    // saturation is what actually colours the surfaces/dividers/dim text. Near-
    // black surfaces still read dark (chroma is barely visible at low lightness);
    // the mid containers, outlines and light dim-text carry the visible tint.
    readonly property real _surfTint:    [0.00, 0.06, 0.14][_v]
    readonly property real _variantTint: [0.00, 0.10, 0.20][_v]
    readonly property real _outlineTint: [0.00, 0.15, 0.30][_v]

    // Coerce a matugen "#rrggbb" string (or a color-ish {r,g,b}) to {r,g,b,a}.
    function _rgbOf(v) {
        if (v && v.r !== undefined)
            return { r: v.r, g: v.g, b: v.b, a: (v.a !== undefined ? v.a : 1) };
        var h = String(v).replace("#", "");
        return { r: parseInt(h.substr(0, 2), 16) / 255,
                 g: parseInt(h.substr(2, 2), 16) / 255,
                 b: parseInt(h.substr(4, 2), 16) / 255, a: 1 };
    }
    // [hue, sat, light] all 0..1 (hue in turns, to feed Qt.hsla directly).
    function _hslOf(c) {
        var mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b);
        var l = (mx + mn) / 2, h = 0, s = 0;
        if (mx !== mn) {
            var d = mx - mn;
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
            if (mx === c.r) h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0);
            else if (mx === c.g) h = (c.b - c.r) / d + 2;
            else h = (c.r - c.g) / d + 4;
            h /= 6;
        }
        return [h, s, l];
    }

    // Raw wallpaper accent hue, reused as the tint direction for neutrals.
    // Fallback matches the `primary` role fallback so a missing palette derives
    // both from the same colour.
    readonly property real _accentHue: _hslOf(_rgbOf(_data.primary ?? "#a9c7ff"))[0]

    /** Accent: enforce a saturation floor, then add the level's boost. */
    function _vivid(v) {
        var c = _rgbOf(v);
        if (root.bypassTint)
            return Qt.rgba(c.r, c.g, c.b, c.a);
        var hsl = _hslOf(c);
        var s = Math.min(1, Math.max(hsl[1], root._satFloor) + root._satBoost);
        return Qt.hsla(hsl[0], s, hsl[2], c.a);
    }
    /** Neutral: snap to the accent hue and raise chroma by `amt`, keeping lightness. */
    function _tint(v, amt) {
        var c = _rgbOf(v);
        if (root.bypassTint || amt <= 0)
            return Qt.rgba(c.r, c.g, c.b, c.a);
        var hsl = _hslOf(c);
        return Qt.hsla(root._accentHue, Math.min(1, hsl[1] + amt), hsl[2], c.a);
    }

    /**
     * base16 readability floor. Material mode already ships M3-guaranteed
     * contrast, so this is a pass-through there. In the base16 bypass an
     * arbitrary scheme can place a foreground too near the surface, leaving text
     * unreadable; nudge the foreground's lightness so it keeps a minimum gap
     * from the background (works for dark AND light schemes). Only foreground
     * (`on_*` text/icon) roles are wrapped — accent/container FILLS are trusted
     * verbatim, so a container that is meant to sit near the surface is untouched.
     */
    function _readable(v) {
        var c = _rgbOf(v);
        if (!root.bypassTint)
            return Qt.rgba(c.r, c.g, c.b, c.a);
        var fg = _hslOf(c);
        var bgL = _hslOf(_rgbOf(_data.surface ?? _data.background ?? "#111318"))[2];
        var minGap = 0.4;
        var l = fg[2];
        if (Math.abs(l - bgL) < minGap)
            l = bgL < 0.5 ? Math.min(1, bgL + minGap) : Math.max(0, bgL - minGap);
        return Qt.hsla(fg[0], fg[1], l, c.a);
    }

    // ── accents (vivid) ─────────────────────────────────────────────────────
    readonly property color primary: _vivid(_data.primary ?? "#a9c7ff")
    readonly property color on_primary: _data.on_primary ?? "#00315c"
    readonly property color primary_container: _vivid(_data.primary_container ?? "#1c4a7a")
    readonly property color on_primary_container: _data.on_primary_container ?? "#d3e3ff"

    readonly property color secondary: _vivid(_data.secondary ?? "#bcc7dc")
    readonly property color on_secondary: _data.on_secondary ?? "#263141"
    readonly property color secondary_container: _vivid(_data.secondary_container ?? "#3c4758")
    readonly property color on_secondary_container: _data.on_secondary_container ?? "#d8e3f8"

    readonly property color tertiary: _vivid(_data.tertiary ?? "#d9bde2")
    readonly property color on_tertiary: _data.on_tertiary ?? "#3c2946"
    readonly property color tertiary_container: _vivid(_data.tertiary_container ?? "#543f5e")
    readonly property color on_tertiary_container: _data.on_tertiary_container ?? "#f6d9ff"

    // Error stays true red — semantic, never re-hued by vibrancy.
    readonly property color error: _data.error ?? "#ffb4ab"
    readonly property color on_error: _data.on_error ?? "#690005"
    readonly property color error_container: _data.error_container ?? "#93000a"
    readonly property color on_error_container: _data.on_error_container ?? "#ffdad6"

    // ── surfaces / neutrals (M3 elevation ladder, accent-tinted) ────────────
    readonly property color background: _tint(_data.background ?? "#111318", _surfTint)
    readonly property color on_background: _readable(_data.on_background ?? "#e2e2e9")
    readonly property color surface: _tint(_data.surface ?? "#111318", _surfTint)
    readonly property color on_surface: _readable(_data.on_surface ?? "#e2e2e9")
    readonly property color on_surface_variant: _readable(_tint(_data.on_surface_variant ?? "#c4c6cf", _variantTint))
    readonly property color surface_variant: _tint(_data.surface_variant ?? "#44474e", _surfTint)
    readonly property color surface_dim: _tint(_data.surface_dim ?? "#111318", _surfTint)
    readonly property color surface_bright: _tint(_data.surface_bright ?? "#37393e", _surfTint)
    readonly property color surface_container_lowest: _tint(_data.surface_container_lowest ?? "#0c0e13", _surfTint)
    readonly property color surface_container_low: _tint(_data.surface_container_low ?? "#191c20", _surfTint)
    readonly property color surface_container: _tint(_data.surface_container ?? "#1d2024", _surfTint)
    readonly property color surface_container_high: _tint(_data.surface_container_high ?? "#282a2f", _surfTint)
    readonly property color surface_container_highest: _tint(_data.surface_container_highest ?? "#33353a", _surfTint)
    readonly property color surface_tint: _vivid(_data.surface_tint ?? "#a9c7ff")

    readonly property color outline: _tint(_data.outline ?? "#8e9099", _outlineTint)
    readonly property color outline_variant: _tint(_data.outline_variant ?? "#44474e", _outlineTint)

    readonly property color inverse_surface: _data.inverse_surface ?? "#e2e2e9"
    readonly property color inverse_on_surface: _data.inverse_on_surface ?? "#2e3036"
    readonly property color inverse_primary: _vivid(_data.inverse_primary ?? "#3a6294")

    readonly property color shadow: _data.shadow ?? "#000000"
    readonly property color scrim: _data.scrim ?? "#000000"
    readonly property color source_color: _data.source_color ?? "#7c9fb0"

    // ── fixed accent pairs (M3, vivid) ──────────────────────────────────────
    readonly property color primary_fixed: _vivid(_data.primary_fixed ?? "#d3e3ff")
    readonly property color primary_fixed_dim: _vivid(_data.primary_fixed_dim ?? "#a9c7ff")
    readonly property color on_primary_fixed: _data.on_primary_fixed ?? "#001c38"
    readonly property color on_primary_fixed_variant: _data.on_primary_fixed_variant ?? "#1c4a7a"
    readonly property color secondary_fixed: _vivid(_data.secondary_fixed ?? "#d8e3f8")
    readonly property color secondary_fixed_dim: _vivid(_data.secondary_fixed_dim ?? "#bcc7dc")
    readonly property color on_secondary_fixed: _data.on_secondary_fixed ?? "#111c2b"
    readonly property color on_secondary_fixed_variant: _data.on_secondary_fixed_variant ?? "#3c4758"
    readonly property color tertiary_fixed: _vivid(_data.tertiary_fixed ?? "#f6d9ff")
    readonly property color tertiary_fixed_dim: _vivid(_data.tertiary_fixed_dim ?? "#d9bde2")
    readonly property color on_tertiary_fixed: _data.on_tertiary_fixed ?? "#251431"
    readonly property color on_tertiary_fixed_variant: _data.on_tertiary_fixed_variant ?? "#543f5e"
}
