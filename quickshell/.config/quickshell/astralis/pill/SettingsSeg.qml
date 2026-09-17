pragma ComponentBehavior: Bound

import QtQuick
import "m3"
import "../colors"
import "../services"
import "../config"

/**
 * astralis — Material 3 connected segmented button. `options` is a list of
 * `{ label, value }`; picking a segment emits `picked(value)`. Selection keys
 * off the source value, never a child's effective visibility. The host passes
 * `s` for scale.
 *
 * ── Why this was rebuilt ──────────────────────────────────────────────────
 *
 * It used to draw NO container at all: a bare row of labels, with the current
 * one marked by `primary` at 16% alpha behind it — which on the settings
 * surface's own background is invisible. So a settings list read as a mix of
 * two unrelated design languages: fully-drawn M3 switches in some rows, three
 * bold words in others, with nothing to say the words were a control.
 *
 * ── What harmonising with the switch does and does not mean ──────────────
 *
 * The first attempt at fixing that gave this control the switch's costume: an
 * outlined stadium track around the whole group, at the switch's exact track
 * height. It matched, and it was wrong — an enclosing outlined track is the
 * SWITCH's affordance. The track is a channel, and it is there because
 * something travels along it. A segmented control has no thumb and nothing
 * travels; drawing it a channel makes it a toggle wearing another control's
 * clothes, which is the same "two design languages" failure one layer down.
 *
 * Two controls harmonise by sharing the SYSTEM, not the form:
 *
 *   shared    the stadium (the whole shell is a pill); the 32dp control
 *             height; the state layer for hover/press; the shell's press dip
 *             and spring; `Motion` durations.
 *   distinct  the switch is an outlined track with a travelling thumb, and
 *             says on/off with `primary`. This is a set of labels with the
 *             chosen one lit, and says chosen-among-several with
 *             `secondary_container` — which is exactly M3's own split between
 *             a binary's on-state and a selection's container.
 *
 * So: no outer track. The container appears around the ONE segment that is
 * chosen, because that is the only place this control has anything to
 * contain, and the row reads as chips with one lit rather than as a toggle.
 */
Rectangle {
    id: seg

    property real s: 1
    property var options: []
    property var value
    signal picked(var value)

    /**
     * When `flushLeft`, the control shifts left by the first option's text
     * inset so that text lines up with x=0 of where the control is placed,
     * rather than the pill edge sitting there.
     */
    property bool flushLeft: false

    readonly property real pad: 0
    readonly property real edgePad: M3.chipPadding / 2 * seg.s

    x: seg.flushLeft ? -seg.edgePad : 0
    width: pills.implicitWidth
    // The shell's control line — the same number the compact switch derives
    // its geometry from, so a column of settings rows has ONE optical line
    // through its controls without any of them borrowing another's form.
    height: M3.controlHeight * seg.s
    color: "transparent"

    /** Index of the option matching `value`, or -1 while nothing matches. */
    readonly property int currentIndex: {
        for (var i = 0; i < seg.options.length; i++)
            if (seg.options[i].value === seg.value)
                return i;
        return -1;
    }
    /**
     * Geometry of the selected segment, PUSHED here by the delegate rather
     * than pulled with `rep.itemAt(currentIndex)`.
     *
     * `itemAt` is a FUNCTION, not a bindable property. A binding that calls it
     * registers no dependency on the Repeater's contents, so it evaluated once
     * — before the delegates existed, returning null — and never re-ran. That
     * is why the selection indicator was invisible for the entire life of this
     * control and the segments read as bare text: the fill was there in the
     * source and had never once been drawn.
     *
     * The delegate reports itself whenever it becomes current, moves, resizes,
     * or is rebuilt (a live palette re-run hands the Repeater a brand-new
     * array and re-creates every delegate), so the indicator tracks a
     * label-driven width change too.
     */
    property real selX: 0
    property real selW: 0
    property bool hasSel: false
    function syncSel(item, isCurrent) {
        if (!isCurrent)
            return;
        seg.selX = pills.x + item.x;
        seg.selW = item.width;
        seg.hasSel = true;
    }
    onCurrentIndexChanged: if (seg.currentIndex < 0) seg.hasSel = false;

    // Selected-segment indicator: one pill that glides/morphs behind whatever
    // option is current, instead of each option instantly recoloring on pick.
    // Geometry comes straight from the live delegate (Repeater.itemAt), so it
    // tracks any label-driven width change too. Declared ahead of the Row so
    // it paints underneath the option labels.
    Rectangle {
        id: indicator
        visible: seg.hasSel && seg.selW > 0
        /**
         * `primary`, the SAME accent the switch's on-state uses.
         *
         * M3's own roles put a binary's on-state on `primary` and a
         * selection's container on `secondary_container`, and following both
         * literally put two different accent colours down one settings column
         * — a light-blue switch beside a deep-indigo segment, which is two
         * shells' worth of accent in one list. In astralis there is one accent
         * and it means "this is the active choice", whichever control is
         * saying it.
         */
        radius: height / 2
        color: Colors.primary
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        x: seg.selX
        y: pills.y
        width: seg.selW
        height: pills.height

        Behavior on x { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
    }

    Row {
        id: pills
        anchors.centerIn: parent
        spacing: 2 * seg.s

        Repeater {
            id: rep
            model: seg.options

            Rectangle {
                id: opt
                required property var modelData
                readonly property bool current: seg.value === modelData.value
                property bool hovered: false

                // Report geometry up whenever anything the indicator needs to
                // follow changes. See `syncSel` for why this is pushed rather
                // than pulled.
                onCurrentChanged: seg.syncSel(opt, opt.current)
                onXChanged: seg.syncSel(opt, opt.current)
                onWidthChanged: seg.syncSel(opt, opt.current)
                Component.onCompleted: seg.syncSel(opt, opt.current)

                width: optLabel.implicitWidth + M3.chipPadding * seg.s
                height: seg.height
                radius: height / 2
                // The sliding `indicator` above owns the current-state fill.
                // Hover is M3's state layer — the content colour at 8% — and
                // not a jump to a named container colour, so an unselected
                // segment lights the same way every other target in the shell
                // does.
                color: (!opt.current && opt.hovered)
                    ? Qt.alpha(Colors.on_surface, M3.hoverOpacity) : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                // A segmented control is a radio GROUP, not a row of buttons —
                // exactly one option is current and picking one clears the
                // rest. Saying so lets assistive tech announce "2 of 4" rather
                // than reading four unrelated buttons. (`Accessible.value` and
                // the other range properties do not exist on the attached type
                // — see quickshell-core.md §9b.)
                Accessible.role: Accessible.RadioButton
                Accessible.name: String(opt.modelData.label)
                Accessible.checkable: true
                Accessible.checked: opt.current
                Accessible.onPressAction: seg.picked(opt.modelData.value)

                Text {
                    id: optLabel
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    color: opt.current ? Colors.on_primary : Colors.on_surface_variant
                    // The indicator takes Motion.standard to glide across; the
                    // labels used to swap tint on the same frame the value
                    // changed, so the destination lit up before the pill got
                    // there. Fading them lets the two arrive together.
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * seg.s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.3 * seg.s

                    // Press dip, on the LABEL rather than the option pill.
                    // Scaling the pill would not disturb the indicator (that
                    // binds x/width, not the transform), but a pill shrinking
                    // out from under a stationary indicator reads as a glitch.
                    // Text pressing in while the pill holds its place is the
                    // right reading of the gesture. Same spring as everything
                    // else pressable in the shell.
                    scale: optArea.pressed ? 0.92 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }
                }

                MouseArea {
                    id: optArea
                    // Visual pill is ~26px tall; grow the hit area vertically
                    // (only — the horizontal spacing between pills is just 2px,
                    // so widening would overlap the neighbour) toward a ~32px
                    // comfortable target.
                    anchors.fill: parent
                    anchors.topMargin: -3 * seg.s
                    anchors.bottomMargin: -3 * seg.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: opt.hovered = true
                    onExited: opt.hovered = false
                    onClicked: seg.picked(opt.modelData.value)
                }
            }
        }
    }
}
