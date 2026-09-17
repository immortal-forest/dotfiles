import QtQuick
import ".."
import "../../colors"
import "../../services"

/**
 * astralis — Material 3 switch.
 *
 * The tell that separates an M3 switch from a generic toggle: the thumb
 * itself changes SIZE — 16dp off, 24dp on, ballooning to 28dp under a press —
 * rather than sliding a fixed dot (md-comp-switch v0.192). Both the resize
 * and the slide ride the same expressive-spatial spring, because sharing one
 * curve is what makes the two reads as a single gesture instead of two
 * uncoordinated ones.
 *
 * The thumb's rest positions are not a hand-tuned inset, they are the
 * CENTRES of the track's own rounded end-caps: a stadium of height 32 has
 * two radius-16 caps, so centreX is 16 (off) or `trackWidth - 16` = 36 (on).
 * Deriving position from the caps rather than a margin table is what
 * guarantees the thumb clears the track by the same 2dp gap at every size
 * from 16dp through the 28dp press-bulge, with nothing to keep in sync.
 *
 *   M3Switch {
 *       s: root.s
 *       checked: Flags.dnd
 *       accessibleName: "Do not disturb"
 *       onToggled: (v) => Flags.dnd = v
 *   }
 */
Item {
    id: sw

    property real s: 1
    property bool checked: false

    /**
     * astralis's control line instead of M3's list-item scale. Every spec
     * dimension below is multiplied by `k`; nothing else changes, so the
     * proportions, the roles, the springs and the state layer are all still
     * the spec's. See `M3.controlHeight` for why the shell's rows need this.
     *
     * A compact switch drops the thumb glyph by default: at 18dp of thumb a
     * check mark is a smudge, and it was the loudest thing in a settings row.
     */
    property bool compact: false
    readonly property real k: sw.compact ? M3.controlHeight / M3.switchTrackHeight : 1

    /** check/close glyph riding the thumb — the bare M3 "switch" variant. */
    property bool showIcon: !sw.compact
    property string accessibleName: ""

    signal toggled(bool checked)

    implicitWidth: M3.switchTrackWidth * sw.s * sw.k
    implicitHeight: M3.switchTrackHeight * sw.s * sw.k
    width: implicitWidth
    height: implicitHeight

    // Thumb centre travels between the track's two end-cap centres — see
    // the file header for why that is the right anchor, not a margin.
    // NOT `readonly`: a `Behavior on X` is a value INTERCEPTOR, so it needs
    // write access to X. Declaring the property readonly makes the Behavior
    // below a fatal load error ("Invalid property assignment: ... is a
    // read-only property"), which takes the whole shell down with it. The
    // binding is still the only writer — nothing assigns these imperatively.
    property real thumbCenterX: sw.checked
        ? (M3.switchTrackWidth - M3.switchTrackHeight / 2) * sw.s * sw.k
        : (M3.switchTrackHeight / 2) * sw.s * sw.k
    Behavior on thumbCenterX {
        NumberAnimation {
            duration: Motion.expressiveFastSpatialDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveFastSpatial
        }
    }

    // Off/on/pressed diameter, the SAME spring as the slide above so growth
    // and travel can never desync mid-gesture.
    property real thumbDiameter: (state_.pressed
        ? M3.switchHandlePress
        : (sw.checked ? M3.switchHandleOn : M3.switchHandleOff)) * sw.s * sw.k
    Behavior on thumbDiameter {
        NumberAnimation {
            duration: Motion.expressiveFastSpatialDur
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveFastSpatial
        }
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Colors.primary : Colors.surface_container_highest
        // Selected fill carries no outline at all — the fill alone reads as
        // "on"; a border on top of it would just be a seam in the colour.
        border.width: sw.checked ? 0 : M3.switchTrackOutline * sw.s * sw.k
        border.color: Colors.outline
        opacity: sw.enabled ? 1 : M3.disabledContainerOpacity

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
    }

    Rectangle {
        id: thumb
        width: sw.thumbDiameter
        height: sw.thumbDiameter
        radius: width / 2
        x: sw.thumbCenterX - width / 2
        y: (M3.switchTrackHeight * sw.s * sw.k) / 2 - height / 2
        color: sw.checked ? Colors.on_primary : Colors.outline
        // Content, not container — mutes to 0.38 when disabled, and every
        // child below inherits it for free via QtQuick's opacity multiply.
        opacity: sw.enabled ? 1 : M3.disabledContentOpacity

        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

        // Cross-faded on opacity, never `visible`-flipped — a flip would pop
        // instead of dissolve, and would fight the thumb's own resize.
        GlyphIcon {
            anchors.centerIn: parent
            width: M3.switchIconSize * sw.s
            height: width
            name: "check"
            color: Colors.on_primary_container
            stroke: 1.8
            opacity: (sw.showIcon && sw.checked) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }
        GlyphIcon {
            anchors.centerIn: parent
            width: M3.switchIconSize * sw.s
            height: width
            name: "close"
            color: Colors.surface_container_highest
            stroke: 1.8
            opacity: (sw.showIcon && !sw.checked) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }
    }

    // 40dp circular overlay centred on the THUMB, travelling with it — not
    // on the track — purely for its MouseArea (click, pointer target,
    // accessibility) and the keyboard focus ring. No hover/press fill: the
    // switch's own thumb already resizes and recolours for both, so a
    // translucent halo on top was a second reaction to one gesture — and at
    // this control's size it read as a ring bolted onto a toggle that was
    // already saying everything it needed to.
    //
    // Missing `* sw.k` here once left the overlay at full 40dp spec size
    // while every other switch dimension had shrunk to the compact control
    // line — a 40dp target plus its focus ring wrapped around a 24dp-tall
    // track. Fixed below, but `showFill: false` is what actually removes the
    // ring rather than merely resizing it.
    M3StateLayer {
        id: state_
        anchors.centerIn: thumb
        width: M3.switchStateLayer * sw.s * sw.k
        height: width
        radius: width / 2
        enabled: sw.enabled
        s: sw.s
        showFill: false
        // md-comp-switch's real state-layer pair: `primary` once selected
        // (it rides on the now-coloured track), `on_surface` unselected (it
        // rides on the bare surface behind the track). Not in M3.qml — no
        // per-role state-layer-colour token exists there for any component —
        // so this is a judgement call matching the spec's actual pairing.
        // Moot with `showFill: false` above (the focus ring is a fixed
        // `Colors.secondary`, not this) — kept in case a future call
        // re-enables the fill.
        contentColor: sw.checked ? Colors.primary : Colors.on_surface
        // The thumb's own resize already IS the press feedback; a scale dip
        // on top would read as two reactions to one press — the same call
        // M3Button makes for `morphOnPress`.
        pressScale: 0
        minTarget: M3.switchStateLayer
        accessibleRole: Accessible.CheckBox
        accessibleCheckable: true
        accessibleChecked: sw.checked
        accessibleName: sw.accessibleName
        // Never writes `checked` itself — the host owns the state, exactly
        // like every other m3/ control.
        onClicked: sw.toggled(!sw.checked)
    }
}
