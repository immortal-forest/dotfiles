import QtQuick
import "../../colors"
import "../../services"

/**
 * astralis — the Material 3 interaction primitive every m3/ component is built
 * on. Drop it inside a container and it owns the whole gesture: hover, press,
 * keyboard focus, the state layer, the focus ring, the press dip, the hit
 * target and the screen-reader plumbing.
 *
 * Putting all of that HERE rather than in each component is the point. The
 * audit that started this work found press feedback in 3 of 31 interactive
 * files and `Accessible.*` in 0 of 71 — both because every control was
 * hand-rolling its own MouseArea. A component that hosts one of these cannot
 * forget any of it.
 *
 *   Rectangle {
 *       radius: ...
 *       color: ...
 *       M3StateLayer {
 *           anchors.fill: parent
 *           radius: parent.radius
 *           contentColor: Colors.on_primary
 *           accessibleName: "Start recording"
 *           onClicked: doTheThing()
 *       }
 *   }
 *
 * M3's model is a translucent layer of the component's CONTENT colour over its
 * container — never a colour swap — which is why `contentColor` is required
 * and is the on-colour, not the fill.
 */
Item {
    id: layer

    /** The component's on-colour. The state layer is this, at low alpha. */
    property color contentColor: Colors.on_surface

    /** Corner radius to match the host container. */
    property real radius: 0

    /** Scale factor, as everywhere else in the shell. */
    property real s: 1

    /**
     * The hover/press fill below — M3's actual "state layer". Off for a
     * control whose own body already IS the feedback (M3Switch: the thumb
     * resizes and recolours on its own, so a translucent halo on top is a
     * second reaction to one press/hover, not reinforcement). The focus ring
     * is unaffected — that is keyboard-only and earns its keep as the one
     * signal a Tab user gets, never a mouse-hover decoration.
     */
    property bool showFill: true

    /**
     * Press dip depth. The shell's own convention (see astralis-architecture
     * §6.1) rather than an M3 token — M3 expresses press purely as a state
     * layer, but astralis dips as well, and dropping that here would make the
     * m3/ controls feel dead next to the rest of the rice. 0 disables it.
     */
    property real pressScale: 0.96

    /** Item the dip is applied to. Defaults to the host container. */
    property Item scaleTarget: layer.parent

    /**
     * Minimum pointer target. M3 asks for 48dp; the shell is mouse-driven on a
     * 2560×1600 panel where 48 would be comically large next to a 20dp chip, so
     * the floor is the 40dp state-layer size M3 itself uses for icon buttons
     * and switches. The MouseArea grows symmetrically past the visual bounds to
     * reach it — the visual stays small, the target does not.
     */
    property real minTarget: 40

    property alias hovered: area.containsMouse
    property alias pressed: area.pressed
    property bool keyboardFocused: layer.activeFocus && layer.focusFromKeyboard

    /** Accessibility. Set at minimum a name; role defaults to Button. */
    property int accessibleRole: Accessible.Button
    property string accessibleName: ""
    property string accessibleDescription: ""
    property bool accessibleChecked: false
    property bool accessibleCheckable: false

    signal clicked
    signal pressAndHold

    /**
     * Did focus arrive from the keyboard? The focus ring must appear for Tab
     * but NOT for a click — a ring left behind after every mouse press is the
     * classic way this goes wrong. A pointer press clears the flag; any key
     * that moves focus sets it.
     */
    property bool focusFromKeyboard: false

    activeFocusOnTab: enabled
    Accessible.role: layer.accessibleRole
    Accessible.name: layer.accessibleName
    Accessible.description: layer.accessibleDescription
    Accessible.checked: layer.accessibleChecked
    Accessible.checkable: layer.accessibleCheckable
    Accessible.focusable: layer.enabled
    Accessible.onPressAction: layer.clicked()

    // The state layer itself: content colour at M3's opacity for whichever
    // interaction is live (pressed > focus > hover). Animated, so a control
    // never snaps between states — Motion.fast is the shell's hover duration.
    Rectangle {
        anchors.fill: parent
        radius: layer.radius
        color: layer.contentColor
        opacity: (layer.enabled && layer.showFill)
            ? M3.stateOpacity(area.containsMouse, area.pressed, layer.keyboardFocused)
            : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
    }

    // Focus ring — OUTSIDE the container, per md-comp-focus-ring: 3dp of
    // `secondary`, offset 2dp clear of the edge. Keyboard only.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -(M3.focusRingOffset + M3.focusRingWidth / 2) * layer.s
        radius: layer.radius > 0 ? layer.radius + (M3.focusRingOffset + M3.focusRingWidth / 2) * layer.s : 0
        color: "transparent"
        border.width: M3.focusRingWidth * layer.s
        border.color: Colors.secondary
        opacity: layer.keyboardFocused ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
    }

    /**
     * The press dip, on the host container so the whole control moves as one.
     *
     * The animation lives HERE, on a local property, and the Binding below
     * republishes it — rather than writing the endpoints straight at the host
     * and hoping the host declared a Behavior. A `Behavior on scale` can only
     * be declared by the object that owns `scale`, so a state layer writing
     * its parent's scale directly can never animate it: every control in this
     * library snapped between 1 and `pressScale` in a single frame, which is
     * the difference between a button that answers and a button that twitches.
     * Interposing `dip` gives the whole library the shell's spring for free.
     *
     * NOT `readonly` — a `Behavior on X` is a value INTERCEPTOR and needs
     * write access to X; on a readonly property it is a fatal load error that
     * takes the entire shell down. The binding is still the only writer.
     */
    property real dip: (area.pressed && layer.pressScale > 0) ? layer.pressScale : 1
    Behavior on dip {
        NumberAnimation {
            duration: Motion.glide
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveFastSpatial
        }
    }

    Binding {
        target: layer.scaleTarget
        property: "scale"
        value: layer.dip
        when: layer.scaleTarget !== null && layer.pressScale > 0
    }
    Behavior on pressScale { enabled: false }

    MouseArea {
        id: area
        anchors.fill: parent
        // Grow the pointer target to `minTarget` without growing the visual.
        // Negative margins only — a control already at or above the floor is
        // left alone rather than being shrunk.
        anchors.margins: -Math.max(0,
            (layer.minTarget * layer.s - Math.min(layer.width, layer.height)) / 2)
        hoverEnabled: layer.enabled
        cursorShape: Qt.PointingHandCursor
        onPressed: layer.focusFromKeyboard = false
        onClicked: {
            layer.forceActiveFocus();
            layer.clicked();
        }
        onPressAndHold: layer.pressAndHold()
    }

    // Space and Enter activate, the way every platform's button does. Arrow /
    // Tab navigation is the window's business; this only claims the two keys
    // that mean "press me".
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            layer.focusFromKeyboard = true;
            layer.clicked();
            event.accepted = true;
        }
    }
    // Anything that MOVED focus here came from the keyboard, so the ring shows.
    onActiveFocusChanged: if (activeFocus && !area.pressed) layer.focusFromKeyboard = true
}
