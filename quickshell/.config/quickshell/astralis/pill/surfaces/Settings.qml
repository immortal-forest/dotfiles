pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../settings"
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 設 SETTINGS surface. Ricelin's settings index (pill/Settings.qml)
 * is a chain of morphing pill surfaces — index morphs to sub-surface and back.
 * astralis pins the pill to FIXED surface sizes (no content-driven morph), so
 * the same tree is laid out as one surface: the Ricelin index becomes the
 * LEFT sidebar (same Shell/Control groups, kanji-less icon rows, chevrons)
 * and the sub-surfaces become pages swapped in the RIGHT content pane, each
 * keeping its own Ricelin kanji header (相 APPEARANCE, 動 ANIMATION, …) whose
 * close glyph dismisses the surface (there is no separate index page to
 * morph back to — the sidebar IS the index).
 *
 * Both the sidebar and every page derive from SettingsPage (the Ricelin
 * SettingsSurface row registry), so hover/click routing and the glowing
 * row-soul seam behave exactly like Ricelin's: ameForm "rowseam" rides
 * whichever row is focused, on either side of the divide.
 *
 * Built pages: Appearance (Flags-backed), Animation / Look / Input
 * (Settings-store backed hyprctl keywords), Display (monitors dict + live
 * keyword with confirm countdown), Idle-Lock (Flags-backed, daemonless),
 * Keybinds (read-only `hyprctl binds -j` viewer), Workspaces (read-only
 * workspace-rules view), Updates (checkupdates/AUR pending list) and
 * FontPicker (fc-list → Flags.uiFont, reached from Appearance's Font row).
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 19
    mRight: 19
    mBottom: 14

    /** Current page key; the sidebar nav rows and the pageHost switch on it. */
    property string page: "appearance"

    function openPage(name) {
        root.page = name;
    }

    // Reopening the surface lands on the first page, like Ricelin reopening
    // its settings lands on the index. On open, claim the keyboard focus the
    // layershell hands this surface (shell.qml) so arrow/enter keys reach the
    // active page's row registry.
    onOpenChanged: {
        if (!open)
            root.page = "appearance";
        else
            Qt.callLater(() => kbNav.forceActiveFocus());
    }

    // Returning from the font picker (which owns focus for its search field)
    // to any keyboard-navigable page re-claims the focus sink.
    onPageChanged: if (root.open && root.page !== "fontpicker") Qt.callLater(() => kbNav.forceActiveFocus());

    // ── soul-bead seam: track the focused row on either side ────────────────
    readonly property var seamPage: sidebar.rowFocused ? sidebar
        : (root.activePage && root.activePage.rowFocused ? root.activePage : null)

    /**
     * Stays "rowseam" for the surface's whole open lifetime — never drops to
     * "off". Ame's hidden→shown transition (Ame.qml startFlight) always
     * launches from `wake`, the PILL's stale rest-kanji anchor near the
     * screen's top edge (Pill.qml wakePoint) — that's fine as a one-time
     * "shapeshift in" when it fires in step with the surface's own open
     * fade, same as every other surface's dock/seam/caret. The old
     * `: "off"` fallback here meant that first flight didn't fire until
     * `seamPage` first went non-null — i.e. the first row hover, which
     * `focusRowItem` requires (neither side starts focused) — so it landed
     * whenever the user happened to first hover a row, often well after the
     * surface had already faded in and settled. Firing that late, the
     * flight's remnant droplet (pinched off at `wake`, still up near the
     * top edge) read as a stray tertiary smudge over the SETTINGS/APPEARANCE
     * headers instead of part of the open. Keeping the form constant makes
     * that launch happen exactly once, during the open fade like everywhere
     * else, and — since Ame.qml only re-triggers a dramatic flight on a
     * `form` CHANGE — every later hover handoff between rows is a plain
     * `startGlide`, so the seam always tracks the focused row cleanly.
     */
    ameForm: "rowseam"

    /**
     * The seam's resting x in the sidebar's left gutter: past the pill's inner
     * edge and the navAccent corner, but well short of the row icon (14 * s),
     * so the bead reads as a deliberate left-margin marker rather than a bright
     * sliver jammed into the accent box's rounded corner (the earlier look).
     */
    readonly property real sidebarSeamX: 8 * root.s

    amePoint: {
        void root.width;
        void root.height;
        // A focused sidebar row (hover/kb), else — at rest — the lit
        // current-page row: both are sidebar rows, so the seam sits in the
        // sidebar gutter, vertically centred on the row from its STABLE layout
        // y (treeCol.y + row.y). mapToItem was used here before, but it folds
        // in the row's entrance Translate, so the anchor froze at the row's
        // pre-settle +10*s offset and the seam (and the navAccent box that
        // tracked it) drooped a row-height's tenth below centre on first open.
        var sb = sidebar.rowFocused ? sidebar.focusRowItem
            : (root.seamPage ? null : navAccent.litRow);
        if (sb)
            return Qt.point(root.sidebarSeamX, treeCol.y + sb.y + sb.height / 2);
        // A focused content-pane row: that pane's own left gutter is empty, so
        // the row's 4*s seam anchor reads clean without the sidebar nudge.
        if (root.seamPage) {
            var p = root.seamPage.rowPoint;
            return root.seamPage.mapToItem(root, p.x, p.y);
        }
        return Qt.point(root.sidebarSeamX, root.height / 2);
    }

    /** Sidebar trailing chevron: lights on row focus or on the current page's row. */
    component NavChevron: GlyphIcon {
        property Item row: null
        width: 16 * root.s
        height: 16 * root.s
        name: "chevron-right"
        color: (row && (sidebar.focusRowItem === row || row.lit))
            ? Colors.on_surface : Colors.on_surface_variant
        stroke: 2.2
    }

    /**
     * Content-pane slot: crossfades + a small vertical settle when `current`
     * flips, instead of the hard visible-swap the pageHost used to do. Both
     * the outgoing and incoming page can be mid-fade at once (that's the
     * point of a crossfade) but only the incoming one is ever interactable —
     * `enabled` cuts instantly on `current`, decoupled from the opacity
     * Behavior, so there's never a moment with two pages taking input.
     * `active` on the wrapped page is left bound to the exact same
     * `root.page === ... && root.open` expression every page used before
     * this pass (see the instances below) — this wrapper only adds the
     * visual fade/slide layer, it never delays row-registry/seam resets.
     */
    component PageSlot: Item {
        id: slot
        anchors.fill: parent
        property bool current: false
        default property alias content: inner.data

        enabled: slot.current
        opacity: slot.current ? 1 : 0
        visible: slot.opacity > 0.01
        transform: Translate { y: (1 - slot.opacity) * (14 * root.s) }

        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        Item {
            id: inner
            anchors.fill: parent
        }
    }

    readonly property var activePage: {
        switch (root.page) {
        case "appearance": return pgAppearance;
        case "animation":  return pgAnimation;
        case "look":       return pgLook;
        case "display":    return pgDisplay;
        case "input":      return pgInput;
        case "keybinds":   return pgKeybinds;
        case "workspaces": return pgWorkspaces;
        case "idlelock":   return pgIdleLock;
        case "updates":    return pgUpdates;
        case "fontpicker": return pgFontPicker;
        default:           return pgAppearance;
        }
    }

    // ── keyboard nav: route keys to the active page's row registry ──────────
    // A non-blocking focus sink (no input handlers, so hover/click on the rows
    // below is untouched). While open it holds the surface's Exclusive
    // layershell keyboard focus and drives the current content page's kb*
    // helpers, so toggle/seg/scrub rows are reachable without a mouse. Up/Down
    // move the focused row, Left/Right adjust its control, Enter/Space activate
    // it. Declared first so it sits at the bottom of the stack.
    Item {
        id: kbNav
        anchors.fill: parent
        focus: true

        Keys.onPressed: (e) => {
            var pg = root.activePage;
            if (!pg)
                return;
            switch (e.key) {
            case Qt.Key_Up:    pg.kbMove(-1);   e.accepted = true; break;
            case Qt.Key_Down:  pg.kbMove(1);    e.accepted = true; break;
            case Qt.Key_Left:  pg.kbAdjust(-1); e.accepted = true; break;
            case Qt.Key_Right: pg.kbAdjust(1);  e.accepted = true; break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space: pg.kbActivate(); e.accepted = true; break;
            }
        }
    }

    // ── left: the category tree (Ricelin pill/Settings.qml index) ───────────
    SettingsPage {
        id: sidebar

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: 190 * root.s
        s: root.s
        active: root.open
        onRequestPage: (name) => root.openPage(name)

        rows: [
            { item: appearanceRow, kind: "nav", surface: "appearance" },
            { item: lookRow, kind: "nav", surface: "look" },
            { item: displayRow, kind: "nav", surface: "display" },
            { item: inputRow, kind: "nav", surface: "input" },
            { item: animationRow, kind: "nav", surface: "animation" },
            { item: keybindsRow, kind: "nav", surface: "keybinds" },
            { item: workspacesRow, kind: "nav", surface: "workspaces" },
            { item: idleRow, kind: "nav", surface: "idlelock" },
            { item: updatesRow, kind: "nav", surface: "updates" }
        ]

        // Current-page accent: a soft primary panel that glides/morphs
        // behind the lit nav row instead of snapping between rows. Declared
        // ahead of treeCol so it paints underneath the row text/icons. Maps
        // the target row's geometry into sidebar-local space the same way
        // rowPoint/amePoint already do elsewhere in this file. `fontpicker`
        // (reached from Appearance, not a sidebar entry) has no lit row, so
        // the accent just fades out while that drill-in page is open.
        Rectangle {
            id: navAccent
            readonly property var litRow: {
                switch (root.page) {
                case "appearance": return appearanceRow;
                case "look":       return lookRow;
                case "display":    return displayRow;
                case "input":      return inputRow;
                case "animation":  return animationRow;
                case "keybinds":   return keybindsRow;
                case "workspaces": return workspacesRow;
                case "idlelock":   return idleRow;
                case "updates":    return updatesRow;
                default:           return null;
                }
            }

            x: 0
            width: sidebar.width
            radius: 9 * root.s
            color: Qt.alpha(Colors.primary, 0.10)
            visible: opacity > 0.01
            opacity: navAccent.litRow ? 1 : 0
            // Anchor to the lit row's STABLE layout y (treeCol sits at the
            // sidebar's origin, so treeCol.y + row.y is the row's top in
            // sidebar space) inset by 3*s, matching SettingsRow's own 3*s
            // highlight inset. The old mapToItem(row, 0, 3*s) folded in the
            // row's entrance Translate and froze the box a tenth of a row-
            // height low, so the accent drooped below the label on first open;
            // `y` is a plain reactive property, so this re-lays cleanly and
            // stays centred on the row.
            y: navAccent.litRow ? treeCol.y + navAccent.litRow.y + 3 * root.s : 0
            height: navAccent.litRow ? navAccent.litRow.height - 6 * root.s : 0

            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        Column {
            id: treeCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            SettingsHeader {
                s: root.s
                glyph: "設"
                title: "SETTINGS"
                onBack: root.requestClose()
            }

            Text {
                topPadding: 16 * root.s
                bottomPadding: 2 * root.s
                leftPadding: 12 * root.s
                text: "Shell"
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 8.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2 * root.s
            }

            // Sidebar rows drop Ricelin's hover captions (sub) — a fixed
            // surface can't grow a row into the pill edge like the morphing
            // index could.
            SettingsRow {
                id: appearanceRow
                surface: sidebar
                icon: "sparkles"
                name: "Appearance"
                lit: root.page === "appearance"
                NavChevron { row: appearanceRow }
            }

            SettingsRow {
                id: lookRow
                surface: sidebar
                icon: "app-window"
                name: "Look"
                lit: root.page === "look"
                NavChevron { row: lookRow }
            }

            SettingsRow {
                id: displayRow
                surface: sidebar
                icon: "monitor"
                name: "Display"
                lit: root.page === "display"
                NavChevron { row: displayRow }
            }

            SettingsRow {
                id: inputRow
                surface: sidebar
                icon: "mouse"
                name: "Input"
                lit: root.page === "input"
                NavChevron { row: inputRow }
            }

            SettingsRow {
                id: animationRow
                surface: sidebar
                icon: "waves"
                name: "Animation"
                lit: root.page === "animation"
                NavChevron { row: animationRow }
            }

            Text {
                topPadding: 16 * root.s
                bottomPadding: 2 * root.s
                leftPadding: 12 * root.s
                text: "Control"
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 8.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2 * root.s
            }

            SettingsRow {
                id: keybindsRow
                surface: sidebar
                icon: "keyboard"
                name: "Keybinds"
                lit: root.page === "keybinds"
                NavChevron { row: keybindsRow }
            }

            SettingsRow {
                id: workspacesRow
                surface: sidebar
                icon: "app-window"
                name: "Workspaces"
                lit: root.page === "workspaces"
                NavChevron { row: workspacesRow }
            }

            SettingsRow {
                id: idleRow
                surface: sidebar
                icon: "lock"
                name: "Idle / Lock"
                lit: root.page === "idlelock"
                NavChevron { row: idleRow }
            }

            SettingsRow {
                id: updatesRow
                surface: sidebar
                icon: "download"
                name: "Updates"
                lit: root.page === "updates"
                last: true
                NavChevron { row: updatesRow }
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: sidebar.right
        anchors.leftMargin: 10 * root.s
        width: 1
        color: Qt.alpha(Colors.on_surface, 0.06)
    }

    // ── right: the content pane, one SettingsPage per tree entry ────────────
    // Adding a page: create <Name>Page.qml in pill/settings/ deriving
    // SettingsPage (AppearancePage and AnimationPage are the worked examples:
    // rows registry + content Column + SettingsHeader wired to back(); every
    // other page followed the same swap), add it to settings/qmldir, and
    // instance it here (visible/active/signals identical across pages).
    // Hyprland-keyword pages persist through Services.Settings (see its
    // header doc for the scalar tables and the structured monitors block);
    // shell-side prefs persist through Flags.
    Item {
        id: pageHost
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: divider.right
        anchors.leftMargin: 14 * root.s
        anchors.right: parent.right

        // Each page is wrapped in a PageSlot (crossfade + small vertical
        // settle on swap, see the component doc above). `active` on every
        // page keeps the exact `root.page === ... && root.open` expression
        // it always had — only the surrounding visible/opacity/enabled
        // wiring moved into the wrapper.
        PageSlot {
            current: root.page === "appearance"

            AppearancePage {
                id: pgAppearance
                anchors.fill: parent
                s: root.s
                active: root.page === "appearance" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        PageSlot {
            current: root.page === "animation"

            AnimationPage {
                id: pgAnimation
                anchors.fill: parent
                s: root.s
                active: root.page === "animation" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        PageSlot {
            current: root.page === "look"

            LookPage {
                id: pgLook
                anchors.fill: parent
                s: root.s
                active: root.page === "look" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        PageSlot {
            current: root.page === "display"

            DisplayPage {
                id: pgDisplay
                anchors.fill: parent
                s: root.s
                active: root.page === "display" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        PageSlot {
            current: root.page === "input"

            InputPage {
                id: pgInput
                anchors.fill: parent
                s: root.s
                active: root.page === "input" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        PageSlot {
            current: root.page === "keybinds"

            KeybindsPage {
                id: pgKeybinds
                anchors.fill: parent
                s: root.s
                active: root.page === "keybinds" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        PageSlot {
            current: root.page === "workspaces"

            WorkspacesPage {
                id: pgWorkspaces
                anchors.fill: parent
                s: root.s
                active: root.page === "workspaces" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        PageSlot {
            current: root.page === "idlelock"

            IdleLockPage {
                id: pgIdleLock
                anchors.fill: parent
                s: root.s
                active: root.page === "idlelock" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        PageSlot {
            current: root.page === "updates"

            UpdatesPage {
                id: pgUpdates
                anchors.fill: parent
                s: root.s
                active: root.page === "updates" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.requestClose()
            }
        }

        // Reached from Appearance's Font nav row, not the sidebar (Ricelin
        // parity: fontpicker is a drill-in of Appearance); back returns there.
        PageSlot {
            current: root.page === "fontpicker"

            FontPickerPage {
                id: pgFontPicker
                anchors.fill: parent
                s: root.s
                active: root.page === "fontpicker" && root.open
                onRequestPage: (name) => root.openPage(name)
                onBack: root.openPage("appearance")
            }
        }
    }
}
