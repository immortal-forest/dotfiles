import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — Material 3 basic dialog (md-comp-dialog v0.192).
 *
 * astralis has had no dialog at all: destructive actions either fired
 * immediately or leaned on a bespoke hold-to-confirm (HeatHold, the power
 * menu's heat fill). This is the first real "are you sure?" surface, meant
 * for the cases a heat-hold doesn't fit — e.g. a keyboard-only confirmation,
 * or a question that isn't binary enough for a hold gesture.
 *
 * This component is the dialog's CONTENT AND SCRIM, not a window — it is an
 * Item that fills whatever parent hosts it (a pill surface, typically) and
 * the host decides when to show it via `open`. No PanelWindow/PopupWindow
 * here on purpose: a dialog answering a question already on a pill surface
 * has no business becoming its own layer-shell surface.
 *
 * Motion is deliberately split into two independently-timed pieces, because
 * nesting one opacity fade inside another would SQUARE the curve (Qt opacity
 * multiplies down the item tree, so two Behaviors chasing the same `open`
 * would visibly double-ease) — every source consulted for this file
 * (M3.qml, M3StateLayer.qml, M3Button.qml, M3IconButton.qml) confirms
 * dimensions only, no typography scale, so the type sizes below are
 * `// spec` values from the published M3 type scale, not M3.qml tokens:
 *   • the scrim's alpha fades on Motion.standard (a plain existence fade —
 *     it has no shape to "grow", so the expressive curve buys it nothing).
 *   • the CARD scales up from 0.9 while fading in on
 *     Motion.expressiveDefaultSpatial — "M3 dialogs grow in, they do not
 *     slide" is the literal spec language for this component.
 * Root `visible` is a plain OR of "still open" and "either child is still
 * mid-exit-animation", so the whole assembly only leaves the scene (and
 * stops eating clicks) once both animations have actually finished — no
 * opacity of its own to double up against the children's.
 *
 *   M3Dialog {
 *       anchors.fill: parent
 *       s: root.s
 *       open: confirmingClear
 *       icon: "trash"
 *       title: "Clear all notifications?"
 *       body: "This can't be undone."
 *       destructive: true
 *       confirmText: "Clear"
 *       onConfirmed: { Notifications.clearAll(); confirmingClear = false }
 *       onCancelled: confirmingClear = false
 *   }
 */
FocusScope {
    id: dialog

    property real s: 1
    property bool open: false
    property string icon: ""
    property string title: ""
    property string body: ""
    property string confirmText: "Confirm"
    property string cancelText: "Cancel"
    property bool destructive: false
    default property alias content: contentSlot.data

    signal confirmed
    signal cancelled

    anchors.fill: parent
    // Stay in the scene until BOTH children have actually finished fading —
    // see the file comment on why this can't just be `opacity: open?1:0`.
    visible: dialog.open || scrim.opacity > 0.01 || container.opacity > 0.01
    focus: dialog.open

    Accessible.role: Accessible.Dialog
    Accessible.name: dialog.title
    Accessible.description: dialog.body

    onOpenChanged: if (dialog.open) Qt.callLater(() => dialog.forceActiveFocus())

    Keys.onEscapePressed: dialog.cancelled()
    // The dialog itself (not a button) holds focus the instant it opens —
    // M3Button exposes no hook to hand focus to its INTERNAL M3StateLayer
    // from outside (no id, no alias; only Tab can reach it), so "initial
    // focus on Cancel" is delivered behaviourally instead of literally: as
    // long as focus hasn't moved (no Tab yet), Enter here resolves to
    // cancel — the exact outcome focusing Cancel would have produced, and
    // the safety property the brief cares about (Enter can never be the
    // FIRST keystroke that fires a destructive confirm). Once the user Tabs
    // to a button, that button's own M3StateLayer owns Enter/Space and this
    // handler never fires — Return/Enter here only ever fire while the
    // FocusScope itself, not a button, holds activeFocus.
    Keys.onReturnPressed: dialog.cancelled()
    Keys.onEnterPressed: dialog.cancelled()

    // ── scrim ────────────────────────────────────────────────────────────
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Colors.scrim
        opacity: dialog.open ? M3.dialogScrim : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        MouseArea {
            anchors.fill: parent
            // Full-screen dismiss surface, not a discrete affordance — same
            // call PowerMenu makes for its own scrim: the pointer cursor
            // signals it's clickable, but there's no shape here for a press
            // dip to scale against.
            cursorShape: Qt.PointingHandCursor
            onClicked: dialog.cancelled()
        }
    }

    // ── card ─────────────────────────────────────────────────────────────
    Rectangle {
        id: container
        anchors.centerIn: parent
        // 24dp clear of the host's edges isn't an M3 token — it's a plain
        // overflow guard so the 560dp cap never touches the surface's rim on
        // a narrow host; chosen to match dialogPadding for visual rhythm.
        width: Math.min(560 * dialog.s, dialog.width - 48 * dialog.s)
        height: col.implicitHeight + M3.dialogPadding * 2 * dialog.s
        radius: M3.dialogCorner * dialog.s
        color: Colors.surface_container_high

        scale: dialog.open ? 1 : 0.9
        opacity: dialog.open ? 1 : 0
        visible: opacity > 0.01
        Behavior on scale {
            NumberAnimation {
                duration: Motion.expressiveDefaultSpatialDur
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveDefaultSpatial
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.expressiveDefaultSpatialDur
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveDefaultSpatial
            }
        }

        // `col.implicitHeight` is 0 for one frame on creation before the
        // Column's children resolve their real sizes; guard the height
        // Behavior the same way SettingsRow guards its own (see that file's
        // `height:` comment) so a freshly-opened dialog never visibly
        // "grows" on its very first layout — only genuine later content
        // changes (title/body swapped while still open) animate.
        property bool settled: false
        Component.onCompleted: Qt.callLater(() => container.settled = true)
        Behavior on height {
            enabled: container.settled
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        // Blocks the scrim's dismiss-on-click from firing when the click
        // lands on blank padding inside the card instead of a button —
        // without this, any point inside `container` that isn't covered by
        // a child MouseArea falls straight through to the scrim underneath.
        // An empty handler is enough to claim the point.
        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: M3.dialogPadding * dialog.s
            }
            // Icon→headline→body rhythm below is `// spec`: the published
            // M3 basic-dialog layout (16dp icon-to-headline, 16dp headline-
            // to-supporting-text, 24dp supporting-text-to-actions) — none of
            // it is in M3.qml, which stops at dimensions/shape, not layout.
            spacing: 16 * dialog.s

            // Centred icon: anchoring inside a Column would fight the
            // Column's own x-management, so it gets a full-width wrapper
            // Item to centre within instead — the wrapper is the Column's
            // actual child, the icon just lives inside it.
            Item {
                width: col.width
                height: dialogIcon.height
                visible: dialog.icon.length > 0
                GlyphIcon {
                    id: dialogIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: M3.dialogIconSize * dialog.s
                    height: width
                    name: dialog.icon
                    // spec: md-comp-dialog icon colour is `secondary`, not
                    // `onSurfaceVariant` — dialogs are the one place M3 asks
                    // for the accent on a glyph that isn't otherwise a CTA.
                    color: Colors.secondary
                    stroke: 1.8
                }
            }

            Text {
                visible: dialog.title.length > 0
                width: parent.width
                horizontalAlignment: dialog.icon.length > 0 ? Text.AlignHCenter : Text.AlignLeft
                text: dialog.title
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 24 * dialog.s   // spec: M3 type scale headline-small, 24/32
                wrapMode: Text.WordWrap
            }

            Text {
                visible: dialog.body.length > 0
                width: parent.width
                text: dialog.body
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 14 * dialog.s   // spec: M3 type scale body-medium, 14/20
                wrapMode: Text.WordWrap
                lineHeight: 1.3
            }

            // Optional custom body (e.g. an inline input) — 0 height and
            // excluded from the Column's spacing when nothing is slotted in,
            // since positioners skip invisible children and empty `data`
            // means `childrenRect` is empty too.
            Item {
                id: contentSlot
                width: col.width
                height: childrenRect.height
                visible: height > 0
            }

            // Trailing-aligned action row. A Row can't anchor itself inside
            // a Column (same conflict as the icon above), so it gets the
            // same full-width-wrapper treatment.
            Item {
                width: col.width
                height: actionsRow.implicitHeight
                Row {
                    id: actionsRow
                    anchors.right: parent.right
                    spacing: 8 * dialog.s   // spec: md-comp-dialog action-button spacing

                    M3Button {
                        s: dialog.s
                        variant: "text"
                        text: dialog.cancelText
                        onClicked: dialog.cancelled()
                    }

                    // Non-destructive confirm: the real M3Button, filled.
                    M3Button {
                        visible: !dialog.destructive
                        s: dialog.s
                        variant: "filled"
                        text: dialog.confirmText
                        onClicked: dialog.confirmed()
                    }

                    // Destructive confirm: M3Button has no per-instance
                    // colour override (M3IconButton has `accent` for exactly
                    // this; M3Button doesn't, and adding one is out of scope
                    // here — flagged in the report). This is a literal
                    // structural copy of M3Button's "filled" variant —
                    // same tokens, same press morph, same M3StateLayer host
                    // — with `error`/`on_error` in place of `primary`/
                    // `on_primary`, so it still LOOKS like an M3Button, it
                    // just can't BE one.
                    Rectangle {
                        id: destructiveConfirm
                        visible: dialog.destructive
                        implicitWidth: destructiveLabel.implicitWidth + M3.buttonPadding * 2 * dialog.s
                        implicitHeight: M3.buttonHeight * dialog.s
                        width: implicitWidth
                        height: implicitHeight
                        radius: destructiveState.pressed ? M3.cornerMedium * dialog.s : height / 2
                        color: Colors.error
                        Behavior on radius {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        Text {
                            id: destructiveLabel
                            anchors.centerIn: parent
                            text: dialog.confirmText
                            color: Colors.on_error
                            font.family: Appearance.font.family
                            font.pixelSize: 14 * dialog.s   // spec: M3 label-large, 14/medium
                            font.weight: Font.Medium
                        }

                        M3StateLayer {
                            id: destructiveState
                            anchors.fill: parent
                            s: dialog.s
                            radius: destructiveConfirm.radius
                            contentColor: Colors.on_error
                            pressScale: 0   // the container already morphs; see M3Button's own reasoning
                            minTarget: M3.buttonHeight
                            accessibleRole: Accessible.Button
                            accessibleName: dialog.confirmText
                            onClicked: dialog.confirmed()
                        }
                    }
                }
            }
        }
    }
}
