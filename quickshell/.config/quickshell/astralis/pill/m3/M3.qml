pragma Singleton
import QtQuick
import Quickshell

/**
 * astralis — Material 3 component tokens.
 *
 * The numbers here are NOT invented and NOT recalled from memory: every value
 * is transcribed from Google's own machine-readable token set,
 * `material-components/material-web/tokens/versions/v0_192/*.scss` (design
 * system version v0.192). Where a token has no entry there, the source is the
 * published M3 component spec and the constant is marked `// spec`.
 *
 * WHY A SEPARATE SINGLETON. `config/Appearance.qml` already owns astralis's
 * OWN shape/spacing scale (rounding.small 7 / medium 13 / large 20, the pill's
 * 18/22), which is deliberately not M3's (4/8/12/16/28) — the pill's geometry
 * was tuned to the hardware notch idiom, not to the spec. Overwriting it to
 * "be M3" would have reshaped the whole rice. So the M3 scale lives beside it
 * and only the m3/ components read it. `Colors.*` (dynamic Material 3 roles
 * from matugen) and `Motion.*` (durations/curves) are shared unchanged — those
 * two were already M3.
 *
 * Everything is expressed in dp. Multiply by the host surface's `s` at the use
 * site, exactly like the rest of the shell: `height: M3.buttonHeight * root.s`.
 */
Singleton {
    id: root

    // ── state layer opacities (md-sys-state v0.192) ─────────────────────────
    // M3's interaction model: a translucent layer of the component's *content*
    // colour composited over its container. Not a colour swap — that is why a
    // hovered filled button and a hovered text button feel like the same
    // gesture despite having nothing in common visually.
    readonly property real hoverOpacity:   0.08
    readonly property real focusOpacity:   0.12
    readonly property real pressedOpacity: 0.12
    readonly property real draggedOpacity: 0.16

    // ── disabled treatment (consistent across every component) ──────────────
    readonly property real disabledContainerOpacity: 0.12
    readonly property real disabledContentOpacity:   0.38

    // ── shape scale (md-sys-shape v0.192) ───────────────────────────────────
    readonly property real cornerNone:       0
    readonly property real cornerExtraSmall: 4
    readonly property real cornerSmall:      8
    readonly property real cornerMedium:     12
    readonly property real cornerLarge:      16
    readonly property real cornerExtraLarge: 28
    readonly property real cornerFull:       9999

    // ── focus ring (md-comp-focus-ring) ─────────────────────────────────────
    // Drawn OUTSIDE the component: 3dp of `secondary` sitting 2dp clear of the
    // edge. Keyboard-only by contract — showing it on mouse press is the
    // classic mistake that makes every click leave a ring behind.
    readonly property real focusRingWidth:  3
    readonly property real focusRingOffset: 2

    // ── button (md-comp-*-button) ───────────────────────────────────────────
    readonly property real buttonHeight:      40
    readonly property real buttonIconSize:    18
    readonly property real buttonPadding:     24   // spec: leading/trailing
    readonly property real buttonPaddingIcon: 16   // spec: leading, when iconed
    readonly property real buttonGap:         8    // spec: icon → label
    readonly property real buttonOutline:     1    // spec: outlined variant

    // ── icon button (md-comp-icon-button) ───────────────────────────────────
    readonly property real iconButtonSize:       40   // state-layer w/h
    readonly property real iconButtonIconSize:   24

    // ── switch (md-comp-switch) ─────────────────────────────────────────────
    readonly property real switchTrackWidth:   52
    readonly property real switchTrackHeight:  32
    readonly property real switchTrackOutline: 2
    readonly property real switchHandleOff:    16
    readonly property real switchHandleOn:     24
    readonly property real switchHandlePress:  28
    readonly property real switchIconSize:     16
    readonly property real switchStateLayer:   40

    // ── slider (md-comp-slider) ─────────────────────────────────────────────
    readonly property real sliderTrackHeight:  4
    readonly property real sliderHandleSize:   20
    readonly property real sliderStateLayer:   40
    readonly property real sliderLabelHeight:  28
    readonly property real sliderTickSize:     2

    // ── chip (md-comp-filter-chip) ──────────────────────────────────────────
    readonly property real chipHeight:      32
    readonly property real chipIconSize:    18
    readonly property real chipOutline:     1    // 0 once selected
    readonly property real chipPadding:     16   // spec
    readonly property real chipGap:         8    // spec

    // ── card (md-comp-*-card) ───────────────────────────────────────────────
    readonly property real cardCorner:  12   // spec: corner-medium
    readonly property real cardOutline: 1    // spec: outlined variant

    // ── dialog (md-comp-dialog) ─────────────────────────────────────────────
    readonly property real dialogCorner:   28   // spec: corner-extra-large
    readonly property real dialogPadding:  24   // spec
    readonly property real dialogIconSize: 24
    readonly property real dialogScrim:    0.32 // spec: scrim at 32%

    // ── badge (md-comp-badge) ───────────────────────────────────────────────
    readonly property real badgeDotSize:        6
    readonly property real badgeNumericSize:    16
    readonly property real badgeNumericPadding: 4    // spec: large-badge side padding

    // ── progress (md-comp-*-progress) ───────────────────────────────────────
    readonly property real progressTrackHeight:  4    // spec
    readonly property real progressCircularSize: 48   // spec
    readonly property real progressCircularWidth: 4   // spec
    // M3 Expressive's wavy linear indicator: the ACTIVE portion is a sine, the
    // remaining track stays flat. These are the shape of that wave.
    readonly property real waveAmplitude:  3
    readonly property real waveLength:     20
    readonly property real waveSpeed:      0.9   // wavelengths per second

    // ── FAB (md-comp-fab) ───────────────────────────────────────────────────
    readonly property real fabSmall:    40   // spec
    readonly property real fabMedium:   56   // spec
    readonly property real fabLarge:    96   // spec
    readonly property real fabIconSize:      24   // spec
    readonly property real fabIconSizeLarge: 36   // spec: the large FAB's icon
    readonly property real fabCorner:        16   // spec: corner-large
    // md-comp-extended-fab, which has no token file of its own
    readonly property real fabExtendedGap:     12  // spec: icon → label
    readonly property real fabExtendedPadding: 16  // spec: leading/trailing

    // ── list item (md-comp-list-item) ───────────────────────────────────────
    readonly property real listItemSpace:      12   // top/bottom
    readonly property real listItemPadding:    16   // spec: leading/trailing
    readonly property real listItemOneLine:    56   // spec
    readonly property real listItemTwoLine:    72   // spec
    readonly property real listItemThreeLine:  88   // spec

    // ── astralis extensions (M3 Expressive sizes + the grouping scale) ──────
    //
    // Everything above is transcribed spec. Everything below is astralis's
    // own, kept here rather than in Appearance.qml because it only has meaning
    // next to the numbers above.
    //
    // These exist because the pill used to separate the clusters in its rows
    // with 1px vertical rules — a toolbar idiom from a decade before M3, and
    // the single most dated thing about it. M3 groups by PROXIMITY and by the
    // state layer instead: a cluster reads as one because its members sit at a
    // tighter pitch than anything around them, and the only container any of
    // them draws is the one that appears under the cursor. So the replacement
    // for a rule is not a box — it is these two numbers.

    /**
     * M3 Expressive's extra-small icon button: a 32dp state layer around an
     * 18dp glyph. The full-size 40/24 button is correct in a settings list and
     * far too large inside a 58dp-tall pill, and the previous 17dp glyph with
     * a 6dp handler margin was a ~29dp target with no state layer at all —
     * under the 40dp guidance AND invisible to the pointer until clicked.
     */
    readonly property real iconButtonSizeSmall:     32
    readonly property real iconButtonIconSizeSmall: 18

    /**
     * Inner padding and inter-item gap of a recessed control group.
     *
     * The gap is 4, not the 2 that would look tightest, because it is doing
     * arithmetic: a 32dp button whose state layer grows to a 36dp pointer
     * target (`M3StateLayer.minTarget`) reaches exactly 2dp past each edge, so
     * a 4dp gap is filled precisely by the two targets meeting in the middle.
     * Tighter and the targets would OVERLAP, and the later sibling would win
     * the hit test over its neighbour's visible edge.
     */
    /**
     * THE control line — the height every interactive control in an astralis
     * settings row sits on, and the number the rest of them derive from.
     *
     * M3's own control sizes are drawn for M3's own list item: a 32dp switch
     * inside a 56dp row is 57% of it. astralis's rows are ~43dp, where the
     * same 32dp switch is 74% and reads as the row's main event rather than as
     * its control — which is exactly the "M3 bolted onto astralis" seam. The
     * shell's scale wins for SIZE; M3 still wins for behaviour, colour roles
     * and motion. That split is the whole harmonisation.
     *
     * The pointer target does NOT shrink with it: `M3StateLayer.minTarget`
     * stays at the full 40dp and grows the hit area invisibly.
     */
    readonly property real controlHeight: 24

    readonly property real groupPadding: 5
    readonly property real groupGap:     4
    readonly property real groupTarget:  36

    /**
     * Fill of that recessed track, as an alpha over `surface_container_highest`.
     * Low on purpose: the track must be legible as a boundary at a glance and
     * must not read as a button itself. Above ~0.6 it starts competing with
     * the state layers of the buttons inside it.
     */
    readonly property real groupTrackAlpha: 0.45

    /**
     * The state-layer opacity for a given interaction, in M3's own precedence:
     * pressed beats focus beats hover. Returns 0 when nothing applies, so the
     * caller can bind it straight to an overlay's opacity and let a Behavior
     * animate between states.
     *
     * Focus is passed separately from hover because it must mean KEYBOARD
     * focus — see `M3StateLayer.showFocusRing`.
     */
    function stateOpacity(hovered, pressed, focused) {
        if (pressed)
            return root.pressedOpacity;
        if (focused)
            return root.focusOpacity;
        if (hovered)
            return root.hoverOpacity;
        return 0;
    }
}
