import QtQuick
import QtQuick.Effects
import "../colors"
import "../services"
import "../config"

/**
 * astralis — THE surface. One material, every container in the shell.
 *
 * Lives in `pill/` rather than in `pill/m3/`, because it is not a Material 3
 * spec component — nothing in the spec describes this gradient, and filing it
 * under the M3 prefix would claim an authority it does not have. `pill/` is
 * also where every consumer can already see it: the lock screen imports
 * `pill/` for Ame and the shared primitives and needs no second import to
 * reach the shell's own surface.
 *
 * This component exists because the shell had a coherence problem that no
 * amount of Material 3 component swapping could fix. The pill body was drawn
 * with a very specific recipe — a two-stop vertical gradient, a hairline
 * outline, a 1px sheen along the top edge inset past the corner curve, and a
 * soft drop shadow — and that recipe lived inline in `pill/Pill.qml` and
 * nowhere else. Every other container in the shell (the lock screen's password
 * capsule, its now-playing block, the badges) was drawn from scratch with flat
 * fills and different borders. The result read as several unrelated designs
 * sharing a palette, which is exactly what a palette cannot fix.
 *
 * So the recipe is extracted here, verbatim, and everything wears it. That is
 * the single decision that makes the lock screen and the pill look like one
 * program: they are literally made of the same material, at different sizes.
 *
 * ── Why this is not "un-Material" ──────────────────────────────────────────
 *
 * M3 asks a surface to state its elevation. It offers two ways: a tonal step
 * up the `surface_container_*` ramp, and a shadow. This panel uses both, and
 * adds a vertical gradient *between two adjacent steps of that same ramp*
 * (`surface_container_high` → `surface_container`) rather than picking one.
 * The gradient is a one-step tonal fade, not a decoration — the top edge of a
 * panel catches more light than its bottom, so the top sits one rung higher.
 * The sheen is the specular consequence of that. Both are read off the same
 * matugen roles as everything else, so a retheme sweeps them.
 *
 * ── Radius: astralis's scale, not M3's ─────────────────────────────────────
 *
 * `Appearance.rounding` (7 / 13 / 20, pill 18 / 22) is what containers use;
 * M3's 4/8/12/16/28 is what CONTROLS inside them use. That split is
 * deliberate and is written down in M3.qml's header: the pill's geometry was
 * tuned to a hardware-notch idiom and reshaping it to spec would have
 * reshaped the rice. So this panel takes whatever radius the caller gives and
 * does not opinionate.
 *
 * ── Layout ────────────────────────────────────────────────────────────────
 *
 * Children go in the default slot and are NOT part of the shadow's layer —
 * the background is layered on its own so a MultiEffect shadow never
 * rasterises live content (text, canvases, the Ame bead) into a cached
 * texture. Anchor inside; the panel does not position for you.
 *
 *   Panel {
 *       s: root.s
 *       radius: Appearance.rounding.pill * root.s
 *       Text { anchors.centerIn: parent; text: "hello" }
 *   }
 */
Item {
    id: panel

    property real s: 1

    /** Corner radius in PIXELS (already scaled) — callers pass `token * s`. */
    property real radius: Appearance.rounding.medium * panel.s

    /**
     * Opacity of the fill only. The lock screen floats panels over a photo and
     * wants the wallpaper to breathe through at ~0.72; the pill sits over
     * arbitrary windows and stays opaque. Border, sheen and shadow are scaled
     * with it so a translucent panel does not end up with a hard rim.
     */
    property real fillAlpha: 1

    /** Tonal pair. Defaults are the pill's — one step apart on the M3 ramp. */
    property color topColor: Colors.surface_container_high
    property color bottomColor: Colors.surface_container

    property color outlineColor: Colors.outline_variant
    property real outlineAlpha: 0.6
    property real outlineWidth: 1

    /**
     * The specular hairline. Off for panels small enough that a 1px highlight
     * across the top reads as a rendering artefact rather than as light (the
     * 20px-tall chips), on for everything else.
     */
    property bool sheen: true

    property bool elevated: true
    property real shadowOpacity: Appearance.elevation.shadowOpacity
    property real shadowBlur: 0.7
    property real shadowOffset: 3 * panel.s

    /**
     * Qt clamps a Rectangle's radius to half its shorter side, so a caller may
     * pass `Appearance.rounding.full` (9999) for a stadium. The sheen inset
     * below cannot use the raw value — 0.6 × 9999 would push both margins past
     * the panel's own width and the highlight would vanish — so everything
     * that does arithmetic on the corner reads this clamped copy instead.
     */
    readonly property real effRadius: Math.max(0, Math.min(panel.radius,
        Math.min(panel.width, panel.height) / 2))

    default property alias content: contentHolder.data

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: panel.effRadius
        border.width: panel.outlineWidth
        border.color: Qt.alpha(panel.outlineColor, panel.outlineAlpha * panel.fillAlpha)
        Behavior on border.color { ColorAnimation { duration: Motion.standard } }

        // Each stop animates independently so a matugen retheme sweeps THROUGH
        // the panel — top edge first, then the body — instead of the whole
        // container snapping to a new colour in one frame.
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.alpha(panel.topColor, panel.fillAlpha)
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
            GradientStop {
                position: 1.0
                color: Qt.alpha(panel.bottomColor, panel.fillAlpha)
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
        }

        // Layered on the BACKGROUND only. Putting the shadow on the whole panel
        // would rasterise the children into a texture every frame — fatal for
        // the lock screen, whose panels contain a live Canvas waveform and the
        // Ame bead.
        layer.enabled: panel.elevated
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, panel.shadowOpacity)
            shadowBlur: panel.shadowBlur
            shadowVerticalOffset: panel.shadowOffset
        }
    }

    // Sheen — inset by 0.6 × the radius at each end so it stops before the
    // corner curve instead of cutting a chord across it. A sibling of `bg`
    // rather than a child, because `bg` is layered and the sheen must not be
    // blurred into the shadow.
    Rectangle {
        visible: panel.sheen
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: panel.outlineWidth
        anchors.leftMargin: panel.effRadius * 0.6
        anchors.rightMargin: panel.effRadius * 0.6
        height: 1
        color: Qt.alpha(Colors.on_surface, 0.06 * panel.fillAlpha)
    }

    Item {
        id: contentHolder
        anchors.fill: parent
    }
}
