pragma ComponentBehavior: Bound

import QtQuick
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — Material 3 slider, continuous or stepped.
 *
 * 4dp track, a 20dp round handle riding a 40dp state layer, 2dp stop
 * indicators and a 28dp value bubble — all md-comp-slider v0.192. Colour,
 * focus, the focus ring and the screen-reader plumbing come from
 * M3StateLayer; this file owns the geometry, the pointer maths and the keys.
 *
 *   M3Slider {
 *       s: root.s
 *       from: 0; to: 100
 *       value: Audio.volume * 100
 *       accessibleName: "Volume"
 *       fmt: v => Math.round(v) + "%"
 *       onMoved: v => Audio.setVolume(v / 100)
 *   }
 *
 * THE VALUE CONTRACT (the whole reason this is a component and not a
 * Rectangle). `value` is a plain one-way binding the HOST owns. Nothing in
 * here ever writes to it — writing would sever the host's binding the first
 * time a finger touched the control, and the slider would silently stop
 * reflecting the thing it is supposed to be showing. Drags emit `moved`, the
 * host applies it, the new `value` flows back in. `displayValue` below is the
 * eased shadow that actually draws, exactly as pill/ScrubValue.qml does it.
 */
Item {
    id: root

    property real s: 1
    property real from: 0
    property real to: 100
    property real value: 0

    /** 0 = continuous. Non-zero snaps every emitted value onto the grid. */
    property real stepSize: 0

    /** Stop indicators. Only meaningful stepped, so it is gated on stepSize. */
    property bool showTicks: false

    /** The value bubble above the handle, while dragging or keyboard-focused. */
    property bool showLabel: true

    /** Optional value→string for the bubble and the screen-reader description. */
    property var fmt: null

    property string accessibleName: ""

    /** Live, once per pointer move. */
    signal moved(real value)
    /** Once, on let-go — the seam a host uses to commit rather than to preview. */
    signal released(real value)

    // ── value ↔ pixel mapping ───────────────────────────────────────────────
    // Everything clamps against lo/hi rather than from/to so a host that hands
    // over an inverted range still gets a sane control instead of NaN.
    readonly property real lo: Math.min(root.from, root.to)
    readonly property real hi: Math.max(root.from, root.to)
    readonly property real span: (root.hi - root.lo) || 1

    /**
     * Display-only shadow of `value`. A click-step or an external change lands
     * with a settle instead of a jump; a real drag suppresses the easing so the
     * handle tracks the pointer 1:1 rather than swimming after it.
     */
    property real displayValue: root.value
    Behavior on displayValue {
        enabled: !pointer.dragging
        NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
    }

    readonly property real frac: Math.max(0, Math.min(1, (root.displayValue - root.lo) / root.span))
    // The handle's centre must stay inside the control, so its travel is inset
    // by its own radius at both ends. The tracks still span edge to edge.
    readonly property real trackInset: M3.sliderHandleSize * root.s / 2
    readonly property real travel: Math.max(1, root.width - 2 * root.trackInset)
    readonly property real handleX: root.trackInset + root.frac * root.travel

    /** Arrow-key step. Continuous sliders get 1% of the range, per WAI-ARIA. */
    readonly property real keyStep: root.stepSize > 0 ? root.stepSize : root.span / 100
    readonly property real pageStep: Math.max(root.keyStep, root.span / 10)

    /**
     * Stop indicators. `Repeater` rebuilds every delegate whenever the count
     * changes, so the count is deliberately a function of from/to/stepSize
     * alone — things that change when a settings page is built, never per
     * frame. A pathological step (0.001 over a range of 100) would ask for
     * 100 000 dots, so past 64 the ticks simply stop being drawn rather than
     * quietly costing a hundred thousand items.
     */
    readonly property int rawTicks: root.stepSize > 0
        ? Math.floor(root.span / root.stepSize) + 1 : 0
    readonly property int tickCount:
        (root.showTicks && root.rawTicks > 1 && root.rawTicks <= 64) ? root.rawTicks : 0

    readonly property string valueText: root.fmt
        ? root.fmt(root.displayValue)
        : root.displayValue.toFixed(root.stepSize > 0 && root.stepSize < 1 ? 2 : 0)

    // No M3 token exists for a slider's length — it is whatever the host gives
    // it. This is only a sane fallback so a slider dropped into a Column
    // without a width is still visible.
    implicitWidth: 200 * root.s
    implicitHeight: M3.sliderStateLayer * root.s

    /**
     * QML's `Accessible` attached type exposes only QAccessible's flags and
     * actions — NOT the value interface. `Accessible.value`, `.minimumValue`,
     * `.maximumValue` and `.stepSize` do not exist and assigning any of them is
     * a hard load failure. The readable number therefore goes in `description`,
     * and the increase/decrease ACTIONS are what let assistive tech drive it.
     */
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName
    Accessible.description: root.valueText + " (" + root.from + " to " + root.to + ")"
    Accessible.focusable: root.enabled
    Accessible.onIncreaseAction: root.nudge(root.keyStep)
    Accessible.onDecreaseAction: root.nudge(-root.keyStep)

    function snap(v) {
        var n = Math.max(root.lo, Math.min(root.hi, v));
        if (root.stepSize > 0) {
            n = root.lo + Math.round((n - root.lo) / root.stepSize) * root.stepSize;
            n = Math.max(root.lo, Math.min(root.hi, n));
        }
        // Kill the float dust `lo + k*step` accumulates, or a 0.1 step emits
        // 0.30000000000000004 and every `!==` comparison downstream misfires.
        return Math.round(n * 1e6) / 1e6;
    }

    function valueAt(px) {
        return root.lo + Math.max(0, Math.min(1, (px - root.trackInset) / root.travel)) * root.span;
    }

    /** Single funnel for every input path, so clamping and snapping cannot be skipped. */
    function commit(v, done) {
        var n = root.snap(v);
        if (n !== root.value)
            root.moved(n);
        if (done)
            root.released(n);
    }

    // A keyboard step is its own complete gesture — there is no let-go to wait
    // for — so it emits `moved` AND `released` together, and a host that only
    // listens to `released` still hears it.
    function nudge(delta) {
        var n = root.snap(root.value + delta);
        if (n === root.value)
            return;
        root.moved(n);
        root.released(n);
    }

    /**
     * Focus lives on the hosted M3StateLayer, so arrow keys arrive there first;
     * it accepts only Space/Enter and lets everything else bubble up to here.
     * Up/Down are deliberately NOT bound — a slider sitting in a settings list
     * must not eat the keys that move between rows.
     */
    Keys.onPressed: function (event) {
        if (!root.enabled)
            return;
        switch (event.key) {
        case Qt.Key_Left:     root.nudge(-root.keyStep); break;
        case Qt.Key_Right:    root.nudge(root.keyStep); break;
        case Qt.Key_PageDown: root.nudge(-root.pageStep); break;
        case Qt.Key_PageUp:   root.nudge(root.pageStep); break;
        case Qt.Key_Home:     root.nudge(root.lo - root.value); break;
        case Qt.Key_End:      root.nudge(root.hi - root.value); break;
        default: return;
        }
        // Reaching for the arrows IS keyboard use, so the ring comes back even
        // if focus originally arrived from a click.
        state_.focusFromKeyboard = true;
        event.accepted = true;
    }

    // Disabled slider, per M3: active track and handle to on_surface at 38%,
    // inactive to 12%. Muted, never hidden — the geometry does not move.
    Rectangle {
        id: activeTrack
        x: 0
        width: root.handleX
        height: M3.sliderTrackHeight * root.s
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: root.enabled
            ? Colors.primary
            : Qt.alpha(Colors.on_surface, M3.disabledContentOpacity)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Rectangle {
        id: inactiveTrack
        x: root.handleX
        width: Math.max(0, root.width - root.handleX)
        height: M3.sliderTrackHeight * root.s
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: root.enabled
            ? Colors.secondary_container
            : Qt.alpha(Colors.on_surface, M3.disabledContainerOpacity)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Repeater {
        model: root.tickCount

        Rectangle {
            id: tick
            required property int index

            // Positioned from index*stepSize rather than index/(count-1), so a
            // range that does not divide evenly by the step keeps its dots on
            // the real stop values instead of spreading them to fill.
            readonly property real t: Math.min(1, (tick.index * root.stepSize) / root.span)

            width: M3.sliderTickSize * root.s
            height: width
            radius: width / 2
            x: root.trackInset + tick.t * root.travel - width / 2
            y: root.height / 2 - height / 2
            // Over the active track the dot has to read against `primary`, over
            // the inactive one against `secondary_container` — hence two tints
            // rather than one. Dots under the handle are simply covered by it.
            color: tick.t <= root.frac ? Colors.on_primary : Colors.on_surface_variant
            opacity: root.enabled ? 1 : M3.disabledContentOpacity
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    Item {
        id: handleBox
        width: M3.sliderStateLayer * root.s
        height: width
        x: root.handleX - width / 2
        y: root.height / 2 - height / 2

        Rectangle {
            id: handle
            anchors.centerIn: parent
            width: M3.sliderHandleSize * root.s
            height: width
            radius: width / 2
            color: root.enabled
                ? Colors.primary
                : Qt.alpha(Colors.on_surface, M3.disabledContentOpacity)
            // The handle swells slightly under the finger instead of dipping.
            // A dip on a drag control reads as "this got smaller because you
            // grabbed it", which fights the gesture; growing reads as "you have
            // hold of it". Same spring as every other Expressive morph here.
            scale: pointer.dragging ? 1.1 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        /**
         * M3's `dragged` state (16%), which `M3.stateOpacity()` deliberately
         * does not model — it only knows hover/focus/pressed, and a slider has
         * no "pressed", it has "being dragged". The drag is driven by the
         * control-wide MouseArea below (a state layer's own MouseArea cannot
         * report motion), so this is the one piece of the interaction the
         * primitive genuinely cannot supply. Everything else — hover, focus,
         * the ring, the tab stop, the screen reader — still comes from it.
         */
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.primary
            opacity: pointer.dragging ? M3.draggedOpacity : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }

        M3StateLayer {
            id: state_
            anchors.fill: parent
            enabled: root.enabled
            s: root.s
            radius: width / 2
            contentColor: Colors.primary
            // A slider must never dip: the handle is a position, and moving it
            // by 4% on press would read as the value having changed.
            pressScale: 0
            minTarget: M3.sliderStateLayer
            accessibleRole: Accessible.Slider
            accessibleName: root.accessibleName
        }
    }

    /**
     * The value bubble. Floats ABOVE the control's own bounds on purpose: the
     * label is transient, and reserving 30dp of permanent height for something
     * visible only mid-drag would push every settings row apart for nothing.
     * A host that clips must leave headroom.
     */
    Item {
        id: label
        visible: root.showLabel && label.opacity > 0.01
        width: Math.max(M3.sliderLabelHeight * root.s, labelText.implicitWidth + 12 * root.s)
        height: M3.sliderLabelHeight * root.s
        x: root.handleX - width / 2
        y: root.height / 2 - (M3.sliderStateLayer / 2 + M3.sliderLabelHeight + 2) * root.s
        // Crossfaded, never toggled: a `visible` flip would pop, and the label
        // is the one thing on screen the eye is already tracking.
        opacity: (pointer.dragging || state_.keyboardFocused) ? 1 : 0
        scale: (pointer.dragging || state_.keyboardFocused) ? 1 : 0.7
        transformOrigin: Item.Bottom

        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Colors.primary
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        Text {
            id: labelText
            anchors.centerIn: parent
            text: root.valueText
            color: Colors.on_primary
            // M3 label-medium: 12sp / medium. M3.qml carries dimensions, not a
            // type scale, so the size is inline the way M3Button does it.
            font.family: Appearance.font.family
            font.pixelSize: 12 * root.s
            font.weight: Font.Medium
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
    }

    /**
     * One control-wide pointer handler owns the drag, because M3StateLayer's
     * MouseArea reports press but not motion. It sits ON TOP so a press that
     * lands on the handle still starts a drag, and it keeps `hoverEnabled`
     * false so hover events fall straight through to the state layer beneath —
     * which is how the handle still lights up on hover despite this covering
     * it. Press feedback is the dragged layer above.
     */
    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: false
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        property bool dragging: false

        onPressed: function (mouse) {
            // Focus without the ring: this arrived from a pointer, and a ring
            // left behind after every click is the classic way this goes wrong.
            state_.focusFromKeyboard = false;
            state_.forceActiveFocus();
            pointer.dragging = true;
            root.commit(root.valueAt(mouse.x), false);
        }
        onPositionChanged: function (mouse) {
            if (pointer.dragging)
                root.commit(root.valueAt(mouse.x), false);
        }
        onReleased: function (mouse) {
            if (!pointer.dragging)
                return;
            pointer.dragging = false;
            root.commit(root.valueAt(mouse.x), true);
        }
        // A stolen grab (a Flickable winning the gesture) must not leave the
        // slider believing it is still being dragged.
        onCanceled: pointer.dragging = false
    }
}
