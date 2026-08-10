pragma ComponentBehavior: Bound

import QtQuick
import "../../services"

/**
 * astralis — shared base for the settings pages (the row-registry half of
 * Ricelin pill/SettingsSurface.qml; the pill-morph chrome half lives in
 * PillSurface, which hosts the whole Settings surface). Both the sidebar
 * index and every content subpage derive from this. Carries the
 * keyboard-navigable row registry that the glowing row-soul seam and the
 * click/hover routing key off. The deriving page sets `rows` and lays out
 * its own content column (header, section labels, SettingsRow lines).
 *
 * Each `rows` entry pairs a row item with its control kind and the backing
 * getter and setter: `seg` cycles a segmented choice (wrapping), `toggle`
 * flips a boolean, `scrub` bumps a numeric scrub through its `bump(dir)`,
 * `nav` requests another page. The host routes arrow keys through `kbMove`,
 * `kbAdjust` and `kbActivate` (hook for the follow-up — the pill has no
 * keyboard focus yet); hover and clicks route through `reportRowHover` and
 * `activateRow`, keeping `kbIndex` and the seam in sync.
 */
Item {
    id: root

    property real s: 1

    /** Page is on screen AND the surface is open; loss clears row focus. */
    property bool active: false

    signal requestPage(string name)
    signal back()

    property Item focusRowItem: null
    property int kbIndex: -1
    property var rows: []

    /**
     * Scroll offset of the deriving page's Flickable — each page binds this to
     * its `flick.contentY`. `rowPoint` reads it so the row-soul seam anchor
     * re-resolves when the page scrolls; without the dependency the anchor
     * (a plain mapToItem result) never recomputes on scroll and the bead
     * desyncs from its row. Defaults 0 for pages with no scroll registry.
     */
    property real contentY: 0

    /**
     * Hover is inert until the open/page-enter morph has settled. On a fresh
     * open the surface grows under a stationary cursor, so a row can slide
     * beneath the pointer and latch focus via reportRowHover — which never
     * clears focus on hover-OUT (sticky, for kb-nav parity). That left a
     * second, persistent highlight box on whatever row the cursor grazed
     * during the open (e.g. Input), sitting next to the current page's accent
     * so two rows looked selected. Arming hover only after the morph settles
     * means an incidental graze during the open is ignored; a genuine hover
     * MOVE afterwards still lights its row normally. Keyboard/click routing
     * (kbMove/activateRow) set focus directly and are unaffected.
     */
    property bool hoverArmed: false
    Timer {
        id: armTimer
        interval: Motion.morph
        running: root.active && !root.hoverArmed
        onTriggered: root.hoverArmed = true
    }

    function reportRowHover(item, hovered) {
        if (hovered && root.hoverArmed) {
            focusRowItem = item;
            kbIndex = rowIndexOf(item);
        }
    }

    onActiveChanged: if (!active) {
        focusRowItem = null;
        kbIndex = -1;
        hoverArmed = false;
    }

    function rowIndexOf(item) {
        for (var i = 0; i < rows.length; i++)
            if (rows[i].item === item)
                return i;
        return -1;
    }

    /**
     * Keep row focus valid when `rows` shrinks — a conditional row folds away
     * (Appearance's base16 row, Animation's speed row, Look's blur rows). If
     * the focused item is still present, just re-sync kbIndex to its new
     * position; if it's gone, clamp kbIndex to the new tail and re-point focus,
     * or clear focus entirely when no rows remain, so focus can never dangle
     * past the end of the list.
     */
    onRowsChanged: reconcileFocus()
    function reconcileFocus() {
        if (focusRowItem) {
            var idx = rowIndexOf(focusRowItem);
            if (idx >= 0) {
                kbIndex = idx;
                return;
            }
            if (rows.length === 0) {
                focusRowItem = null;
                kbIndex = -1;
                return;
            }
            kbIndex = Math.max(0, Math.min(rows.length - 1, kbIndex));
            focusRowItem = rows[kbIndex].item;
        } else if (kbIndex > rows.length - 1) {
            kbIndex = rows.length - 1;
        }
    }

    /** Step a seg row's value by `dir`, wrapping at both ends like a mouse click. */
    function segCycle(r, dir) {
        var n = r.vals.length;
        var i = r.vals.indexOf(r.get());
        r.set(r.vals[(((i < 0 ? 0 : i) + dir) % n + n) % n]);
    }

    function kbMove(dir) {
        if (!rows.length)
            return;
        kbIndex = Math.max(0, Math.min(rows.length - 1, (kbIndex < 0 ? 0 : kbIndex + dir)));
        focusRowItem = rows[kbIndex].item;
    }

    function kbAdjust(dir) {
        if (!rows.length)
            return;
        if (kbIndex < 0) {
            kbIndex = 0;
            focusRowItem = rows[0].item;
        }
        var r = rows[kbIndex];
        if (r.kind === "seg")
            segCycle(r, dir);
        else if (r.kind === "toggle")
            r.set(dir > 0);
        else if (r.kind === "scrub")
            r.bump(dir);
    }

    function kbActivate() {
        if (kbIndex < 0)
            return;
        var r = rows[kbIndex];
        if (r.kind === "toggle")
            r.set(!r.get());
        else if (r.kind === "nav")
            root.requestPage(r.surface);
        else if (r.kind === "seg")
            segCycle(r, 1);
    }

    /**
     * A click anywhere on a row drives its control: toggles flip, nav rows
     * open their page, and segmented rows step to the next value (wrapping).
     * The control's own hit areas stay on top, so clicking a specific segment
     * still picks it directly.
     */
    function activateRow(item) {
        var idx = rowIndexOf(item);
        if (idx < 0)
            return;
        kbIndex = idx;
        focusRowItem = item;
        var r = rows[idx];
        if (r.kind === "toggle")
            r.set(!r.get());
        else if (r.kind === "nav")
            root.requestPage(r.surface);
        else if (r.kind === "seg")
            segCycle(r, 1);
    }

    readonly property bool rowFocused: focusRowItem !== null && active

    /** Focused row's seam anchor in page-local coords (the host maps it on). */
    readonly property point rowPoint: {
        void root.width;
        void root.height;
        void root.focusRowItem;
        void root.contentY;
        if (!focusRowItem)
            return Qt.point(4 * root.s, root.height / 2);
        return focusRowItem.mapToItem(root, 4 * root.s, focusRowItem.height / 2);
    }
}
