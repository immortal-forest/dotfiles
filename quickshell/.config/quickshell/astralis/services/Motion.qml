pragma Singleton
import QtQuick
import Quickshell

/**
 * astralis — motion tokens. Single source of truth for every animation
 * duration, curve, and easing in the shell (kickoff ground rule: "every
 * duration/curve ← Motion"). Ported verbatim from Gakuseei/Ricelin
 * pill/Singletons/Motion.qml (the pill morph feel) and extended with the
 * Material 3 expressive curve/duration sets (from dhrruvsharma/shell
 * config/AppearanceConfig.qml).
 *
 * One reduce-motion knob: `reduceMotion` → `mult` scales every duration.
 *
 * CONVENTION (do not break): DURATIONS carry a `Dur` suffix
 * (`expressiveDefaultSpatialDur`) so they never collide with the same-named
 * CURVE (`expressiveDefaultSpatial`, a list<real> bezier). Use a curve as:
 *   NumberAnimation {
 *     easing.type: Motion.easeBezier
 *     easing.bezierCurve: Motion.expressiveDefaultSpatial
 *   }
 */
Singleton {
    id: root

    // ── the single reduce-motion knob ───────────────────────────────────────
    property bool reduceMotion: false
    readonly property real mult: reduceMotion ? 0.4 : 1

    // ── Ricelin pill durations (ms, ×mult) — port verbatim ──────────────────
    readonly property int fast:       Math.round(140  * mult)
    readonly property int standard:   Math.round(300  * mult)
    readonly property int morph:      Math.round(420  * mult)   // full surface morph
    readonly property int glide:      Math.round(260  * mult)   // short rest↔hover hop / bead chase
    readonly property int shapeshift: Math.round(820  * mult)   // Ame full shapeshift flight
    readonly property int heat:       Math.round(1100 * mult)   // power-hold heat ramp
    readonly property int pulse:      Math.round(420  * mult)   // looping breath pulse
    readonly property int rowStagger: Math.round(24   * mult)   // per-row cascade step (content entrance)

    // ── Material 3 expressive durations (ms, ×mult) — `Dur` suffix ──────────
    readonly property int smallDur:  Math.round(200 * mult)
    readonly property int normalDur: Math.round(400 * mult)
    readonly property int largeDur:  Math.round(600 * mult)
    readonly property int expressiveFastSpatialDur:    Math.round(350 * mult)
    readonly property int expressiveDefaultSpatialDur: Math.round(500 * mult)
    readonly property int expressiveEffectsDur:        Math.round(200 * mult)

    // ── easings ─────────────────────────────────────────────────────────────
    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeMorph:    Easing.BezierSpline   // Ricelin name (used with morphCurve)
    readonly property int easeBezier:   Easing.BezierSpline   // alias for any list<real> curve below

    // ── curves (list<real>: cubic-bezier control points, last pair 1,1) ─────
    // Ricelin signature morph: cubic-bezier(0.16,1,0.3,1) — front-loaded expo
    // with a long, visible settle tail. This is the pill's width/height/radius
    // Behavior curve (fidelity contract: match Ricelin, not the bounce).
    readonly property var morphCurve: [0.16, 1, 0.3, 1, 1, 1]

    // Material 3 official sets. expressive*Spatial have y>1 control points →
    // overshoot/bounce (the Pixel micro-animation feel) for surface content.
    readonly property var emphasized:              [0.05,0, 2/15,0.06, 1/6,0.4, 5/24,0.82, 0.25,1, 1,1]
    readonly property var emphasizedAccel:         [0.3,0, 0.8,0.15, 1,1]
    readonly property var emphasizedDecel:         [0.05,0.7, 0.1,1, 1,1]
    readonly property var standardCurve:           [0.2,0, 0,1, 1,1]
    readonly property var expressiveFastSpatial:   [0.42,1.67, 0.21,0.9, 1,1]
    readonly property var expressiveDefaultSpatial: [0.38,1.21, 0.22,1, 1,1]
    readonly property var expressiveEffects:       [0.34,0.8, 0.34,1, 1,1]

    // ── small radii the pill reads (from Ricelin Motion) ────────────────────
    readonly property real rSmall: 7
    readonly property real rTile:  13
}
