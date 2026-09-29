import QtQuick
import "m3"

/**
 * astralis — the shell's toggle switch. Now a thin adapter over
 * `pill/m3/M3Switch.qml` rather than its own control.
 *
 * WHY AN ADAPTER RATHER THAN A REPLACEMENT. This type has ~30 call sites —
 * every settings row that carries a toggle, plus the network and bluetooth
 * rows in surfaces/Link.qml. Keeping the old surface (`s`, `on`, `toggled()`)
 * means all of them pick up the Material 3 switch, its 32dp target, its state
 * layer, its focus ring and its screen-reader identity without a single
 * call-site edit. Passing `accessibleName` is the one thing a call site should
 * add, and it stays optional so nothing breaks by omitting it.
 *
 * WHAT CHANGED VISUALLY. The old control was 28x16 with a fixed 10dp dot. The
 * M3 switch is 52x32 with a thumb that grows 16 → 24 → 28dp as it is toggled
 * and pressed. That is twice the pointer target on the shell's most common
 * control, and it does NOT make settings rows taller: SettingsRow sizes from
 * its TEXT (`textCol.implicitHeight + 26*s`, about 41 at s=1) and only takes
 * the control as a floor (`control + 8` = 40 here), so the text term still
 * wins and the row rhythm is unchanged.
 *
 * `on` is deliberately not renamed to `checked`: renaming it would touch all
 * thirty call sites for no behavioural gain, which is exactly what this
 * adapter exists to avoid.
 */
Item {
    id: toggle

    property real s: 1
    property bool on: false
    /** Announced to a screen reader. Worth setting at every call site. */
    property string accessibleName: ""
    signal toggled

    implicitWidth: sw.implicitWidth
    implicitHeight: sw.implicitHeight
    width: implicitWidth
    height: implicitHeight

    M3Switch {
        // Every switch in the shell reaches M3Switch through this adapter, so
        // this one line is what puts the shell on its own control line.
        compact: true
        id: sw
        anchors.fill: parent
        s: toggle.s
        checked: toggle.on
        accessibleName: toggle.accessibleName
        // M3Switch reports the value it wants to move to; the shell's existing
        // toggle contract is a bare signal and the host flips its own flag, so
        // the argument is dropped here rather than pushed through and ignored
        // at thirty call sites.
        onToggled: toggle.toggled()
    }
}
