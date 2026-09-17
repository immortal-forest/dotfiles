import QtQuick
import "../services"

/**
 * astralis — static design tokens (rounding, spacing, sizing, fonts,
 * elevation). Motion (durations/curves) lives separately in
 * services/Motion.qml. Instantiated once by the Appearance singleton facade;
 * consumers read grouped tokens: `Appearance.rounding.large`,
 * `Appearance.spacing.m`, `Appearance.font.family`, `Appearance.elevation.*`.
 *
 * One token is live, not static: `font.family` follows Flags.uiFont (the
 * 字 FONT picker's pick, persisted in flags.json), falling back to the
 * bundled `familyDefault` while unset — so a font pick re-renders the whole
 * shell at once, Ricelin's Theme.font contract.
 */
QtObject {
    readonly property QtObject rounding: QtObject {
        readonly property real small:    7
        readonly property real medium:   13
        readonly property real large:    20
        readonly property real pill:     18     // resting pill corner
        readonly property real pillOpen: 22     // expanded surface corner
        readonly property real full:     9999
    }
    readonly property QtObject spacing: QtObject {
        readonly property real xs: 4
        readonly property real s:  8
        readonly property real m:  12
        readonly property real l:  16
        readonly property real xl: 24
    }
    readonly property QtObject padding: QtObject {
        readonly property real tile:    12
        readonly property real surface: 16
        readonly property real header:  14
    }
    readonly property QtObject font: QtObject {
        /**
         * Outfit, not Inter.
         *
         * The shell's shape language is built from circles and stadiums — the
         * workspace dots, the unread badge, the privacy dots, the lock's
         * accent colon, the Ame bead, the round icon buttons, the pill itself.
         * Inter is a neutral grotesque: correct, legible, and standing beside
         * that geometry rather than participating in it. Outfit is built from
         * the same primitives, so the type belongs to the shape system instead
         * of merely coexisting with it — and it sets up the deliberate
         * contrast with the lock screen's handwritten display face.
         *
         * (It was also "Inter" for months on a machine where Inter was not
         * installed, so the shell in fact rendered in Noto Sans. Verify with
         * `fc-match` before changing this — see quickshell-core.md §9f.)
         */
        readonly property string familyDefault: "Outfit"
        readonly property string family:  Flags.uiFont.length > 0 ? Flags.uiFont : familyDefault
        /**
         * The lock screen's display face — its clock, date and lock mark, and
         * nothing else in the shell.
         *
         * It gets its own token because the lock is the only surface that is
         * pure type at display size (a 210px clock), and the face that is
         * right for an 11px settings row is chosen on completely different
         * grounds. Falls back to the UI family while unset, so the split costs
         * nothing until something is actually installed to put here.
         *
         * `displayDefault` is Kalam — a casual handwritten face, chosen by
         * eye against seven others rendered at the real 210px clock size. It
         * is the counterweight to how machined the rest of the shell is: the
         * pill is tabular figures and tight tracking, and the one surface you
         * meet before the machine does anything for you says the time in a
         * hand. It keeps enough stroke weight to stay legible at a glance,
         * which is where the thinner scripts (Shadows Into Light, Caveat) get
         * fragile at display size.
         *
         * Kalam carries no CJK, so the 鎖 mark falls through to `jp` — which
         * is correct: the kanji is the shell's stamp and should stay in the
         * shell's hand, not the clock's.
         *
         * The default is set HERE and not in flags.json because flags live in
         * ~/.cache and do not survive a wipe; `Flags.lockFont` stays as the
         * override. A face named here must actually be installed — the shell
         * spent months silently resolving "Inter" to Noto Sans because it was
         * not, and fontconfig substitutes without a word.
         */
        readonly property string displayDefault: "Kalam"
        readonly property string display: Flags.lockFont.length > 0 ? Flags.lockFont : displayDefault
        readonly property string mono:    "JetBrainsMono Nerd Font"
        /**
         * DEPRECATED — zero call sites. The shell had two icon families and
         * this was the second one; every use is now a `GlyphIcon`. Kept only
         * so a stale reference degrades to a missing ligature rather than to a
         * fatal "non-existent property". Do not reach for it: adding a path to
         * `pill/lib/glyphs.js` is the supported way to get a new icon.
         */
        readonly property string symbols: "Material Symbols Rounded"
        /**
         * CJK companion for every kanji mark across the shell — the pill's
         * 時 clock glyph, each settings page's header kanji (相 動 設 字 探…),
         * the lock's 鎖/開, PowerMenu, Clipboard, Mixer, WallpaperPicker.
         *
         * Was Noto Sans CJK JP: a generic system gothic with square, uniform
         * strokes and no relationship to the shape system the rest of the
         * shell is drawn from (round bowls, stadium pills, circular dots).
         * Sitting a kanji from it directly beside a numeral set in Outfit/
         * Geist/Space Grotesk/whatever `family` is this week read exactly
         * like the "two different design principles" this shell keeps
         * getting called out for — just in typeface instead of in shape.
         *
         * Rounded Mplus 1c is the standard pairing for this: a maru-gothic
         * built on the same round-terminal, geometric-round logic as the
         * Latin UI faces above, with a full weight ladder (Thin…Black) so
         * `Font.Medium`/`DemiBold` requests resolve to a real instance
         * instead of Qt synthesizing one. Confirmed installed and
         * fc-match-clean — see quickshell-core.md §9f before ever changing
         * this again.
         */
        readonly property string jp:      "Rounded Mplus 1c"
        readonly property int size:   13
        readonly property int sizeS:  11
        readonly property int sizeL:  16
        readonly property int sizeXL: 22
    }
    readonly property QtObject elevation: QtObject {
        readonly property real restBlur:      18
        readonly property real openBlur:      32
        readonly property real shadowOpacity: 0.5
    }
}
