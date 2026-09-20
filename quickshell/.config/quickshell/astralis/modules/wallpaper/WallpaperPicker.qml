pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../colors"
import "../../services"
import "../../config"
import "../../pill"
import "../../pill/lib/Fuzzy.js" as Fuzzy

/**
 * astralis — standalone wallpaper carousel (ported from ~/shell
 * modules/wallpaper/Wallpaper.qml). NOT a pill surface: its own layer-shell
 * overlay window that fills the WHOLE monitor. Hyprland frosts the entire
 * screen behind it (windows.lua layerrule on ^astralis-wallpaper$, blur +
 * ignore_alpha OFF); the picker itself paints only a whisper-light scrim, so
 * the frost carries the depth. Layout: the carousel is a large hero strip
 * vertically centered on the screen, with the All/Favorites tabs and the
 * search bar pinned to the bottom (tabs above the bar). Clicking the frost
 * dismisses.
 *
 * The carousel is the ~/shell 3D filmstrip: a horizontal ListView with
 * StrictlyEnforceRange centering, every card sheared into a parallelogram
 * (skewFactor -0.35) with its image counter-skewed back upright, the centered
 * card popped in scale over dimmed neighbours — and its image slides into
 * place as it takes focus. A favorites-only filter (All/Favorites tabs +
 * Tab-to-switch), per-card ♥ toggle, and Escape to walk back/hide.
 *
 * Navigation is TWO-LEVEL through the SAME carousel: a folder strip (one card
 * per theme subfolder of ~/wallpapers — cover image + name + count, no ♥) and
 * a wallpaper strip (the favorites filter applies within the folder).
 * `currentFolder` ("" = folder view) is the whole level state. OPENING jumps
 * straight INTO the folder of the live wallpaper, centered on it (folder
 * strip only when nothing is set); Escape walks back: search → wallpapers →
 * folders → close, and stepping out re-centers on the folder just left.
 *
 * SEARCH: a bottom, underline-free fuzzy field (inline TextField +
 * lib/Fuzzy.js) has keyboard focus the whole time — typing always filters,
 * arrows page the strip, Enter activates, Tab flips All/Favorites, Ctrl+F
 * toggles the focused card's favorite (bare F would collide with typing a
 * search that starts with the letter f). At the wallpaper level the
 * query filters the folder's wallpapers by filename; at the folder level it
 * searches EVERYTHING — matching folders first, then matching wallpapers from
 * any folder inline (empty query = plain folder browse). Results ease in/out
 * through ListView add/remove/displaced transitions.
 *
 * Backend is 100% astralis (not ~/shell's setwall command string): activating
 * a card routes through the Wallpaper singleton (scripts/setwall → awww
 * crossfade + matugen retheme), hearts persist through WallpaperFavorites
 * (absolute paths), and the live-wallpaper marker reads Wallpaper.current.
 * Videos are excluded from the filters: awww only sets images.
 *
 * The shell sets `screen`, `s` and `open`, and wires `requestClose()` back to
 * its wallpaperOpen flag. Keyboard focus is exclusive while open so
 * Escape/Ctrl+F/Tab/arrows work over any focused client.
 */
PanelWindow {
    id: picker

    property real s: 1
    property bool open: false

    signal requestClose()

    visible: open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "astralis-wallpaper"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Fills the ENTIRE monitor: the Hyprland layerrule (blur, ignore_alpha
    // OFF) then frosts the whole screen behind the picker. The carousel is a
    // centered hero; the All/Favorites tabs and the search bar are pinned to
    // the bottom; everywhere else is frost that dismisses on click.
    anchors { left: true; right: true; top: true; bottom: true }

    // ── carousel metrics (×s) ────────────────────────────────────────────────
    // Narrow portrait cards, tall, with a gentle shear.
    readonly property real itemW: Math.round(210 * s)
    readonly property real itemH: Math.round(460 * s)
    readonly property real borderW: Math.max(2, Math.round(3 * s))
    readonly property real skewFactor: -0.22
    // Current card widens only (height stays itemH); 2.2× the base.
    readonly property real heroW: Math.round(picker.itemW * 2.2)
    // Neighbours slide clear by half the extra width, plus a small gap.
    readonly property real heroPush: Math.round((picker.heroW - picker.itemW) / 2 + 4 * s)
    readonly property real tabsH: Math.round(34 * s)
    readonly property real searchH: Math.round(40 * s)
    readonly property real searchGap: Math.round(14 * s)

    // ── favorites state (~/shell) ───────────────────────────────────────────
    // Whether the carousel is filtered to favorites only.
    property bool favoritesOnly: false
    // Flat list of every wallpaper: [{ fileName, filePath, fileUrl, theme }].
    property var allWallpapers: []

    // ── two-level navigation ────────────────────────────────────────────────
    // "" = the folder carousel; a theme name = that folder's wallpapers.
    property string currentFolder: ""

    // ── fuzzy search (launcher scorer, pill/lib/Fuzzy.js) ───────────────────
    // Mirrors the search field's text. Fuzzy.rank keys on `.name`, which both
    // folder cards and wallpaper entries carry.
    property string query: ""

    // Folder-level cards: Wallpaper.folders + a per-theme image count, mapped
    // to the delegate's fields (isFolder switches the card chrome).
    readonly property var folderCards: {
        const counts = ({});
        for (let i = 0; i < picker.allWallpapers.length; i++) {
            const t = picker.allWallpapers[i].theme;
            counts[t] = (counts[t] || 0) + 1;
        }
        return Wallpaper.folders.map(f => ({
            isFolder: true,
            name: f.name,
            fileName: f.name,
            filePath: "",
            fileUrl: "file://" + encodeURI(f.cover).replace(/#/g, '%23').replace(/\?/g, '%3F'),
            count: counts[f.name] || 0
        }));
    }

    // Wallpaper-level pool BEFORE the query: the current folder's wallpapers —
    // all of them, or just the favorites (absolute paths in
    // WallpaperFavorites.list, so filter on filePath).
    readonly property var wallpaperPool: {
        const inFolder = picker.allWallpapers.filter(w => w.theme === picker.currentFolder);
        if (!picker.favoritesOnly)
            return inFolder;
        const favs = WallpaperFavorites.list;
        let set = ({});
        for (let i = 0; i < favs.length; i++)
            set[favs[i]] = true;
        return inFolder.filter(w => set[w.filePath] === true);
    }

    // What the carousel shows. Folder level: the folder cards; a non-empty
    // query searches EVERYTHING — matching folders first, then matching
    // wallpapers from every folder as a flat inline set. Wallpaper level: the
    // pool, fuzzy-filtered by filename while typing. Filters keep the SAME
    // entry objects (Fuzzy.rank returns its inputs), so ScriptModel diffs
    // granularly and the ListView transitions animate results in/out.
    readonly property var displayedItems: {
        const q = picker.query.trim();
        if (picker.currentFolder === "") {
            if (!q.length)
                return picker.folderCards;
            return Fuzzy.rank(picker.folderCards, q).concat(Fuzzy.rank(picker.allWallpapers, q));
        }
        return q.length ? Fuzzy.rank(picker.wallpaperPool, q) : picker.wallpaperPool;
    }

    // Built from the Wallpaper service's RECURSIVE scan (wallpapers live in
    // theme subfolders under ~/wallpapers), mapped to the delegate's fields.
    // fileUrl encodes spaces (theme names like "Tokyo Night"); filePath stays
    // raw for Wallpaper.set()/favorites; `name` feeds Fuzzy.rank.
    function rebuildList() {
        picker.allWallpapers = Wallpaper.list.map(w => ({
            name: w.name,
            fileName: w.name,
            filePath: w.path,
            fileUrl: "file://" + encodeURI(w.path).replace(/#/g, '%23').replace(/\?/g, '%3F'),
            theme: w.theme
        }));
    }

    function currentPath() {
        const list = picker.displayedItems;
        if (view.currentIndex >= 0 && view.currentIndex < list.length)
            return list[view.currentIndex].filePath;
        return "";
    }

    function pick(path) {
        if (!path || !path.length)
            return;
        Wallpaper.set(path);        // awww grow-from-cursor + matugen retheme
        picker.requestClose();
    }

    // Return/Enter/click on the centered card: drill into a folder, or apply
    // a wallpaper.
    function activateCurrent() {
        const list = picker.displayedItems;
        if (view.currentIndex < 0 || view.currentIndex >= list.length)
            return;
        const item = list[view.currentIndex];
        if (item.isFolder === true)
            picker.enterFolder(item.fileName);
        else
            picker.pick(item.filePath);
    }

    // Drill in. The query is cleared (a folder card picked out of a search
    // lands on the folder's full strip); centering falls to onCurrentFolderChanged.
    function enterFolder(name) {
        if (!name || !name.length)
            return;
        picker.clearQuery();
        picker.currentFolder = name;
    }

    // Escape walks back one step at a time: a live query clears first, then
    // wallpapers → the folder strip (re-centered on the folder just left),
    // then close.
    function goBack() {
        if (picker.query.length) {
            picker.clearQuery();
            return;
        }
        if (picker.currentFolder !== "") {
            const from = picker.currentFolder;
            picker.currentFolder = "";
            Qt.callLater(() => picker.centerOnFolder(from));
        } else {
            picker.requestClose();
        }
    }

    function clearQuery() {
        searchField.text = "";
        picker.query = "";      // searchField.text may already be "" (harness/tests)
    }

    // Arrow keys arrive through the search field (it holds keyboard focus);
    // StrictlyEnforceRange animates the recenter.
    function move(delta) {
        if (view.count <= 0)
            return;
        view.currentIndex = Math.max(0, Math.min(view.count - 1, view.currentIndex + delta));
    }

    function centerOnFolder(name) {
        const list = picker.displayedItems;
        for (let i = 0; i < list.length; i++)
            if (list[i].isFolder === true && list[i].fileName === name) {
                view.currentIndex = i;
                view.positionViewAtIndex(i, ListView.Center);
                return;
            }
    }

    function favoriteToggle(path) {
        if (!path || !path.length)
            return;
        const wasFav = WallpaperFavorites.has(path);
        WallpaperFavorites.toggle(path);
        // Removing the focused item from the favorites view keeps selection valid.
        if (picker.favoritesOnly && wasFav)
            Qt.callLater(picker.clampCurrentIndex);
    }

    function toggleCurrentFavorite() {
        picker.favoriteToggle(picker.currentPath());
    }

    function setFavoritesOnly(v) {
        if (v === picker.favoritesOnly)
            return;
        picker.favoritesOnly = v;
    }

    function clampCurrentIndex() {
        if (view.count <= 0) {
            view.currentIndex = -1;
            return;
        }
        if (view.currentIndex >= view.count)
            view.currentIndex = view.count - 1;
        else if (view.currentIndex < 0)
            view.currentIndex = 0;
        view.positionViewAtIndex(view.currentIndex, ListView.Center);
    }

    // Switching All ↔ Favorites or folder ↔ wallpapers always starts from the
    // first card.
    function resetToStart() {
        if (view.count > 0) {
            view.currentIndex = 0;
            view.positionViewAtIndex(0, ListView.Center);
        } else {
            view.currentIndex = -1;
        }
    }

    // The favorites filter only shapes the wallpaper level; at the folder
    // level toggling it must not disturb the selection.
    onFavoritesOnlyChanged: if (picker.currentFolder !== "") Qt.callLater(picker.resetToStart)
    // Level change: center on the live wallpaper if the new strip contains it
    // (centerOnCurrent falls back to the first card otherwise). goBack queues
    // centerOnFolder AFTER this, so stepping out still lands on the folder left.
    onCurrentFolderChanged: Qt.callLater(picker.centerOnCurrent)
    // Typing recenters on the best match; clearing recenters on the live
    // wallpaper (or its folder).
    onQueryChanged: Qt.callLater(picker.query.length ? picker.resetToStart : picker.centerOnCurrent)

    // Seed: center the strip on the live wallpaper (Wallpaper.current) instead
    // of ~/shell's WALLPAPER_INDEX env — at the folder level that means the
    // folder containing it. The scan fills asynchronously, so whoever lands
    // last (open or the model) does the centering.
    property bool seeded: false

    function centerOnCurrent() {
        const list = picker.displayedItems;
        if (list.length === 0)
            return;
        let idx = 0;
        if (picker.currentFolder === "") {
            const live = picker.allWallpapers.find(w => w.filePath === Wallpaper.current);
            if (live)
                for (let i = 0; i < list.length; i++)
                    if (list[i].fileName === live.theme) {
                        idx = i;
                        break;
                    }
        } else {
            for (let i = 0; i < list.length; i++)
                if (list[i].filePath === Wallpaper.current) {
                    idx = i;
                    break;
                }
        }
        view.currentIndex = idx;
        view.positionViewAtIndex(idx, ListView.Center);
    }

    // Opening jumps straight INTO the folder of the live wallpaper, centered
    // on it — the folder strip only when nothing is set / the file vanished.
    function jumpToCurrent() {
        const live = picker.allWallpapers.find(w => w.filePath === Wallpaper.current);
        picker.currentFolder = live ? live.theme : "";
        Qt.callLater(picker.centerOnCurrent);
    }

    onOpenChanged: if (open) {
        Wallpaper.rescan();     // pick up any newly-added wallpapers
        clearQuery();
        favoritesOnly = false;  // deterministic: the live wallpaper is always visible
        seeded = allWallpapers.length > 0;
        if (seeded)
            jumpToCurrent();
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    onAllWallpapersChanged: if (open && !seeded && allWallpapers.length > 0) {
        seeded = true;
        jumpToCurrent();
    }

    // Data source: the Wallpaper singleton's recursive scan of ~/wallpapers
    // (rebuilt whenever it rescans). The ListView renders a ScriptModel built
    // from allWallpapers so it can be filtered to favorites.
    Component.onCompleted: picker.rebuildList()
    Connections {
        target: Wallpaper
        function onListChanged() { picker.rebuildList(); }
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: picker.open

        Keys.onEscapePressed: picker.goBack()

        // ── full-screen frosted backdrop: click anywhere off the strip dismisses
        // Near-transparent on purpose: the Hyprland layerrule (ignore_alpha
        // OFF) blurs the desktop across the WHOLE monitor, so the entire
        // screen reads as frosted glass — just a whisper of tint for card
        // contrast, no dark dim. The transparent fill still catches clicks.
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colors.scrim, 0.08)

            Accessible.role: Accessible.Button
            Accessible.name: "Close wallpaper picker"
            Accessible.focusable: true
            Accessible.onPressAction: picker.requestClose()

            MouseArea {
                anchors.fill: parent
                // Full-screen dismiss scrim, not a discrete affordance — cursor
                // signals it is clickable, but a press dip has nothing visible
                // to scale against.
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.requestClose()
            }
        }

        // ── the carousel ─────────────────────────────────────────────────────
        // The hero strip, vertically centered on the monitor and given a large
        // slice of it (popped-card height). The dimmed area above and below
        // stays frosted backdrop (clicks there dismiss); the tabs and search
        // bar sit near the bottom, clear of it.
        ListView {
            id: view
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Math.round(picker.itemH * 1.04)   // itemH card + a little clearance for the border ring

            spacing: 0
            orientation: ListView.Horizontal

            clip: false
            cacheBuffer: Math.min(Math.round(2000 * picker.s), 1200)    // preload neighbours (capped so large/HiDPI grids don't spike image decode)

            // Edge-fade: the strip's ends dissolve into the frost instead of
            // hard-clipping. Same MultiEffect + ShaderEffectSource idiom as
            // pill/Marquee.qml (a bare Rectangle maskSource no-ops).
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskThresholdMin: 0.0
                maskSpreadAtMin: 1.0
                maskSource: ShaderEffectSource {
                    sourceItem: Rectangle {
                        width: Math.max(1, view.width)
                        height: Math.max(1, view.height)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0;  color: "transparent" }
                            GradientStop { position: 0.20; color: "black" }
                            GradientStop { position: 0.80; color: "black" }
                            GradientStop { position: 1.0;  color: "transparent" }
                        }
                    }
                }
            }

            // ~/shell centering: the current item snaps to the middle of the
            // strip; arrows and flicks always land on a centered card.
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (width / 2) - (picker.itemW / 2)
            preferredHighlightEnd: (width / 2) + (picker.itemW / 2)
            highlightMoveDuration: Motion.morph   // unified with the card grow
            highlightMoveVelocity: -1

            /**
             * StrictlyEnforceRange centers the CURRENT item by shifting
             * contentX — but Flickable still clamps contentX to
             * [0, contentWidth - width]. Centering index 0 needs a negative
             * contentX (there's nothing to its left to scroll into); that
             * gets clamped to 0, so the view sits at its raw start instead —
             * flush left, not centered. With few enough items every visible
             * index is effectively "index 0 or the last index", so a
             * one-or-two-card Favorites strip pins left instead of centering
             * (this is really the same edge-clamp the first/last card of ANY
             * strip would hit, just invisible there because you rarely park
             * on the very first/last item long enough to notice).
             *
             * Fix: pad both ends of the content with invisible header/footer
             * space equal to the same half-item slack the highlight range
             * already reserves (`width/2 - itemW/2`). That turns the clamp's
             * floor/ceiling into exactly the contentX index 0 / the last
             * index need, so both ends resolve to a legal, centered position
             * instead of the boundary. Constant (not count-dependent) — a
             * fixed width, so it costs nothing when the strip is already
             * long enough to fill the screen.
             */
            readonly property real edgePad: Math.max(0, (width - picker.itemW) / 2)
            header: Item { width: view.edgePad; height: 1 }
            footer: Item { width: view.edgePad; height: 1 }

            // Search re-shapes the model live: ease inserted/removed cards in
            // and out, and let the survivors glide to their new slots so the
            // strip re-centers smoothly instead of snapping.
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.morph; easing.type: Motion.easeStandard }
                NumberAnimation { property: "scale"; from: 0.85; to: 1; duration: Motion.morph; easing.type: Motion.easeStandard }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Motion.fast; easing.type: Motion.easeStandard }
            }
            displaced: Transition {
                NumberAnimation { property: "x"; duration: Motion.morph; easing.type: Motion.easeStandard }
                NumberAnimation { property: "opacity"; to: 1; duration: Motion.morph; easing.type: Motion.easeStandard }
            }
            move: Transition {
                NumberAnimation { property: "x"; duration: Motion.morph; easing.type: Motion.easeStandard }
            }

            model: ScriptModel {
                values: picker.displayedItems
            }

            delegate: Item {
                id: delegateRoot
                required property var modelData
                required property int index

                width: picker.itemW
                height: picker.itemH
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                // A folder card is the same skewed frame around the folder's
                // cover image, minus the ♥/live chrome, plus a name+count tag.
                readonly property bool isFolder: modelData.isFolder === true
                readonly property string filePath: modelData.filePath
                readonly property url fileUrl: modelData.fileUrl
                readonly property bool isCurrent: ListView.isCurrentItem
                readonly property bool live: !isFolder && filePath.length > 0 && filePath === Wallpaper.current
                readonly property bool isFav: !isFolder && WallpaperFavorites.list.indexOf(filePath) !== -1
                readonly property real reqImgWidth: picker.heroW + (picker.itemH * Math.abs(picker.skewFactor)) + 50 * picker.s

                z: isCurrent ? 10 : 1

                // whole-card tap: focus the card, then drill in / apply.
                MouseArea {
                    id: cardArea
                    anchors.fill: card
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.currentIndex = delegateRoot.index;
                        if (delegateRoot.isFolder)
                            picker.enterFolder(delegateRoot.modelData.fileName);
                        else
                            picker.pick(delegateRoot.filePath);
                    }
                }

                Item {
                    id: card
                    anchors.centerIn: parent
                    // The current card gets more WIDTH, not a different
                    // shape — height stays itemH like every neighbour, so it
                    // stands out by having more presence, not by turning
                    // into a different aspect ratio. centerIn keeps it
                    // growing symmetrically around its own centre.
                    width: delegateRoot.isCurrent ? picker.heroW : picker.itemW
                    height: picker.itemH
                    Behavior on width {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.emphasizedDecel
                        }
                    }

                    /**
                     * The shear below (`transform: Matrix4x4`) is a raw skew,
                     * not a rotation/scale — Qt Quick's border-stroke AA is
                     * a distance-field shader that assumes a near-axis-aligned
                     * local space, so under a genuine shear it degenerates to
                     * a hard 1px stair-step (confirmed: an isolated render of
                     * this exact shear showed a blended edge pixel on ~1/143
                     * scan rows — essentially none). Rendering the card into
                     * a layer FIRST and compositing that flat texture through
                     * the shear (linear-filtered) is what actually produces a
                     * real anti-aliased edge — confirmed the same way, ~114/143
                     * rows blended with a genuine gradient ramp across rows,
                     * not just a single soft pixel. Verified this doesn't
                     * disturb the children's own counter-shears (image/
                     * favBtn/liveBadge/folderTag below): they still cancel out
                     * to upright inside the layer exactly as before.
                     */
                    layer.enabled: true
                    layer.smooth: true

                    // Folder cards drill in; wallpaper cards apply. The live/
                    // favorite state matters more read aloud than on screen —
                    // there is no icon to glance at, so it goes in the description.
                    Accessible.role: Accessible.Button
                    Accessible.name: delegateRoot.isFolder
                        ? "Open " + delegateRoot.modelData.fileName + " folder"
                        : "Apply " + delegateRoot.modelData.fileName + " wallpaper"
                    Accessible.description: delegateRoot.isFolder
                        ? (delegateRoot.modelData.count || 0) + " wallpapers"
                        : (delegateRoot.live ? "Currently applied" : (delegateRoot.isFav ? "Favorite" : ""))
                    Accessible.selected: delegateRoot.isCurrent
                    Accessible.focusable: true
                    Accessible.onPressAction: {
                        view.currentIndex = delegateRoot.index;
                        if (delegateRoot.isFolder)
                            picker.enterFolder(delegateRoot.modelData.fileName);
                        else
                            picker.pick(delegateRoot.filePath);
                    }

                    // Slide neighbours clear of the widened current card so
                    // it doesn't just overlap them — half its extra width
                    // each way. The current card itself stays put.
                    anchors.horizontalCenterOffset: {
                        const rel = delegateRoot.index - view.currentIndex;
                        return rel === 0 ? 0 : (rel < 0 ? -picker.heroPush : picker.heroPush);
                    }
                    Behavior on anchors.horizontalCenterOffset {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.emphasizedDecel
                        }
                    }

                    // Press dip only — no per-card idle scale difference.
                    scale: cardArea.pressed ? 0.96 : 1
                    opacity: delegateRoot.isCurrent ? 1.0 : 0.55

                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.morph
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveDefaultSpatial
                        }
                    }
                    Behavior on opacity { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard } }

                    /**
                     * Parallelogram shear — every child (frame, borders)
                     * shears with the card; the image below counter-shears
                     * upright. The `-k*(height/2)` translation term pivots
                     * the shear around the card's OWN vertical center
                     * instead of its top edge (a raw `x' = x + k*y` shear
                     * leaves the top edge un-shifted and the bottom edge
                     * shifted by the full `k*height` — so the shape's
                     * visual centroid sits `k*height/2` away from the
                     * anchored/centered position, which is exactly the
                     * "card looks left of center" report: confirmed with an
                     * isolated render — a crosshair through the anchor
                     * point landed on the shape's right edge, not its
                     * middle, until this term was added). Same pattern
                     * folderTag/tabPill below already use for the same
                     * reason — this was just missing here and on the
                     * counter-shears (img/favBtn/liveBadge) that need the
                     * matching term to stay exactly where they were.
                     */
                    transform: Matrix4x4 {
                        readonly property real k: picker.skewFactor
                        matrix: Qt.matrix4x4(1, k, 0, -k * (card.height / 2),
                                             0, 1, 0, 0,
                                             0, 0, 1, 0,
                                             0, 0, 0, 1)
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: picker.borderW
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            color: Colors.surface_container_lowest
                        }

                        // Counter-skewed image: upright picture inside the
                        // sheared frame, widened so the parallelogram stays
                        // covered edge to edge. SLIDING ANIMATION lives here:
                        // the image is over-wide, so it CAN pan within the
                        // clipped frame, but at rest every card — current or
                        // not — sits at the same restOffset. Non-current
                        // cards used to carry an extra +52 on top of that,
                        // permanently, not just mid-transition, which is
                        // what read as off-centre: every neighbour's image
                        // sat visibly further off than the current card's
                        // own already-offset -35 rest position.
                        Image {
                            id: img
                            readonly property real restOffset: Math.round(-35 * picker.s)
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: restOffset
                            Behavior on anchors.horizontalCenterOffset {
                                NumberAnimation {
                                    duration: Motion.morph
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.emphasizedDecel
                                }
                            }

                            width: parent.width + (parent.height * Math.abs(picker.skewFactor)) + 50 * picker.s
                            height: parent.height

                            fillMode: Image.PreserveAspectCrop
                            source: delegateRoot.fileUrl
                            sourceSize: Qt.size(Math.round(delegateRoot.reqImgWidth), picker.itemH)
                            asynchronous: true
                            smooth: true

                            // Same pivot term as card's own shear above (with
                            // card's height, not img's — they must cancel
                            // against the SAME reference the outer shear
                            // pivots on) so the image stays exactly where it
                            // was rather than drifting off with just the
                            // frame re-centered under it.
                            transform: Matrix4x4 {
                                readonly property real k: -picker.skewFactor
                                matrix: Qt.matrix4x4(1, k, 0, -k * (card.height / 2),
                                                     0, 1, 0, 0,
                                                     0, 0, 1, 0,
                                                     0, 0, 0, 1)
                            }
                        }

                        // ♥ toggle (top-left, counter-skewed upright): shown on
                        // the focused card and on any favorite; tap toggles
                        // without applying the wallpaper.
                        Rectangle {
                            id: favBtn
                            visible: !delegateRoot.isFolder && (delegateRoot.isCurrent || delegateRoot.isFav)
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: Math.round(10 * picker.s)

                            width: Math.round(32 * picker.s)
                            height: Math.round(32 * picker.s)
                            radius: width / 2
                            color: Qt.alpha(Colors.scrim, favArea.containsMouse ? 0.7 : 0.45)
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            Accessible.role: Accessible.CheckBox
                            Accessible.name: "Favorite"
                            Accessible.description: delegateRoot.modelData.fileName
                            Accessible.checkable: true
                            Accessible.checked: delegateRoot.isFav
                            Accessible.focusable: true
                            Accessible.onPressAction: picker.favoriteToggle(delegateRoot.filePath)

                            scale: favArea.pressed ? 0.92 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }

                            // Same card-height pivot term as the image above.
                            transform: Matrix4x4 {
                                readonly property real k: -picker.skewFactor
                                matrix: Qt.matrix4x4(1, k, 0, -k * (card.height / 2),
                                                     0, 1, 0, 0,
                                                     0, 0, 1, 0,
                                                     0, 0, 0, 1)
                            }

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: Math.round(17 * picker.s)
                                height: Math.round(17 * picker.s)
                                name: delegateRoot.isFav ? "heart-filled" : "heart"
                                stroke: 1.8
                                color: delegateRoot.isFav ? Colors.error : Colors.on_surface
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }

                            MouseArea {
                                id: favArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.favoriteToggle(delegateRoot.filePath)
                            }
                        }

                        // live-wallpaper marker (bottom-left, counter-skewed):
                        // the card currently on screen per Wallpaper.current.
                        Rectangle {
                            id: liveBadge
                            visible: delegateRoot.live
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.margins: Math.round(10 * picker.s)

                            width: Math.round(26 * picker.s)
                            height: Math.round(26 * picker.s)
                            radius: width / 2
                            color: Colors.primary_container

                            // Same card-height pivot term as the image above.
                            transform: Matrix4x4 {
                                readonly property real k: -picker.skewFactor
                                matrix: Qt.matrix4x4(1, k, 0, -k * (card.height / 2),
                                                     0, 1, 0, 0,
                                                     0, 0, 1, 0,
                                                     0, 0, 0, 1)
                            }

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: Math.round(15 * picker.s)
                                height: Math.round(15 * picker.s)
                                name: "check"
                                stroke: 2.2
                                color: Colors.on_primary_container
                            }
                        }

                        // folder cards: name + image count tag (bottom-center,
                        // counter-skewed upright like the tab pills — the
                        // -k*h/2 translation centers the shear on the tag)
                        Rectangle {
                            id: folderTag
                            visible: delegateRoot.isFolder
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Math.round(16 * picker.s)

                            width: folderTagText.width + Math.round(28 * picker.s)
                            height: folderTagText.implicitHeight + Math.round(14 * picker.s)
                            radius: Appearance.rounding.small * picker.s
                            color: Qt.alpha(Colors.scrim, 0.6)

                            transform: Matrix4x4 {
                                readonly property real k: -picker.skewFactor
                                matrix: Qt.matrix4x4(1, k, 0, -k * (folderTag.height / 2),
                                                     0, 1, 0, 0,
                                                     0, 0, 1, 0,
                                                     0, 0, 0, 1)
                            }

                            Text {
                                id: folderTagText
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, picker.itemW - Math.round(64 * picker.s))
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                text: delegateRoot.isFolder
                                    ? delegateRoot.modelData.fileName + "  ·  " + (delegateRoot.modelData.count || 0)
                                    : ""
                                font.family: Appearance.font.family
                                font.pixelSize: Appearance.font.size * picker.s
                                font.weight: Font.Bold
                                color: Colors.on_surface
                            }
                        }
                    }

                    // soft outer glow on the centered card
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -Math.round(2 * picker.s)
                        color: "transparent"
                        border.width: picker.borderW
                        border.color: Qt.alpha(Colors.primary, 0.28)
                        opacity: delegateRoot.isCurrent ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard } }
                    }

                    // border ring: primary on the centered card, a hovered
                    // neighbour tints toward primary too (so the card you're
                    // about to click reads before you click it), hairline otherwise.
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: delegateRoot.isCurrent ? picker.borderW : 1
                        border.color: delegateRoot.isCurrent ? Colors.primary
                            : (cardArea.containsMouse ? Qt.alpha(Colors.primary, 0.45) : Qt.alpha(Colors.outline_variant, 0.6))
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                    }
                }
            }
        }

        // wheel pages the strip (no accepted buttons: clicks pass through)
        MouseArea {
            anchors.fill: view
            z: 20
            acceptedButtons: Qt.NoButton
            property real acc: 0
            onWheel: (event) => {
                acc += event.angleDelta.y / 120;
                const notches = Math.trunc(acc);
                if (notches !== 0 && view.count > 0) {
                    if (notches < 0)
                        view.incrementCurrentIndex();
                    else
                        view.decrementCurrentIndex();
                    acc -= notches;
                }
                event.accepted = true;
            }
        }

        // ── fuzzy search (inline TextField + lib/Fuzzy.js) ───────────────────
        // Pinned to the BOTTOM of the screen and holds keyboard focus the
        // whole time: typing always filters, Left/Right (and Up/Down) page the
        // strip, Enter activates the centered card, Tab flips All/Favorites,
        // Escape walks back. NO underline — a faint rounded outline (lit on
        // focus) is all that frames it over the frost.
        Rectangle {
            id: searchPill
            z: 110
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(40 * picker.s)
            // 420, not 620 — the bar was reading as a full-width input strip
            // rather than a compact search field sitting under the carousel.
            width: Math.min(Math.round(420 * picker.s), focusScope.width - Math.round(48 * picker.s))
            height: picker.searchH
            radius: Appearance.rounding.large * picker.s
            color: "transparent"
            border.width: 1
            border.color: searchField.activeFocus
                ? Qt.alpha(Colors.primary, 0.6)
                : Qt.alpha(Colors.outline_variant, 0.45)
            Behavior on border.color { ColorAnimation { duration: Motion.fast } }

            Text {
                id: searchGlyph
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Math.round(18 * picker.s)
                text: "探"
                color: Colors.on_surface_variant
                font.family: Appearance.font.jp
                font.weight: Font.Medium
                font.pixelSize: Math.round(16 * picker.s)
            }

            TextField {
                id: searchField
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: searchGlyph.right
                anchors.leftMargin: Math.round(10 * picker.s)
                anchors.right: searchCount.left
                anchors.rightMargin: Math.round(10 * picker.s)
                horizontalAlignment: TextInput.AlignHCenter
                background: null        // no underline, no box
                padding: 0
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: Math.round(15 * picker.s)
                placeholderText: picker.currentFolder === ""
                    ? "Search wallpapers & folders"
                    : "Search " + picker.currentFolder
                Accessible.name: placeholderText
                placeholderTextColor: Qt.alpha(Colors.on_surface_variant, 0.65)
                selectByMouse: true
                selectionColor: Qt.alpha(Colors.primary, 0.45)
                onTextChanged: picker.query = text
                Keys.onUpPressed: picker.move(-1)
                Keys.onDownPressed: picker.move(1)
                Keys.onPressed: (event) => {
                    // Left/Right page the strip (queries are short filenames,
                    // so the caret never needs them); Enter/Escape/Tab drive
                    // the picker.
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                        picker.move(event.key === Qt.Key_Right ? 1 : -1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        picker.activateCurrent();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        picker.goBack();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        picker.setFavoritesOnly(!picker.favoritesOnly);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                        // Ctrl+F, not bare F: bare 'f' is a real character —
                        // gating it on an empty field (the first attempt)
                        // still broke the moment a wallpaper's own name
                        // starts with "f", since typing the first letter of
                        // that search IS pressing 'f' on an empty field.
                        // Ctrl+F never collides with typing at all, so it
                        // works regardless of what's already in the box or
                        // what you're about to type.
                        picker.toggleCurrentFavorite();
                        event.accepted = true;
                    }
                }
            }

            Text {
                id: searchCount
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Math.round(18 * picker.s)
                text: picker.displayedItems.length + " / "
                    + (picker.currentFolder === ""
                        ? picker.folderCards.length + picker.allWallpapers.length
                        : picker.wallpaperPool.length)
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: Math.round(11 * picker.s)
                font.features: ({ "tnum": 1 })
            }
        }

        // ── view switcher: All / Favorites (~/shell) ─────────────────────────
        // Sits just ABOVE the search bar (both pinned to the bottom); each tab
        // is a skewed parallelogram (with a counter-skew-centered upright
        // label) matching the cards.
        Row {
            id: viewTabs
            z: 100
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: searchPill.top
            anchors.bottomMargin: picker.searchGap
            spacing: Math.round(16 * picker.s)

            Repeater {
                model: [
                    { label: "All", fav: false },
                    { label: "Favorites", fav: true }
                ]

                delegate: Item {
                    id: tabPill
                    required property var modelData
                    readonly property bool active: picker.favoritesOnly === modelData.fav
                    implicitHeight: picker.tabsH
                    implicitWidth: tabRow.implicitWidth + Math.round(40 * picker.s)

                    // A two-option segmented control reads as one choice among
                    // two, not two unrelated buttons (SettingsSeg idiom).
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: tabPill.modelData.label
                    Accessible.checkable: true
                    Accessible.checked: tabPill.active
                    Accessible.focusable: true
                    Accessible.onPressAction: picker.setFavoritesOnly(tabPill.modelData.fav)

                    scale: tabArea.pressed ? 0.92 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    // Skewed parallelogram background. The shear is centered on
                    // the pill (the -k*h/2 translation) so the upright label at
                    // the centre stays centered inside the shape.
                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.full
                        color: tabPill.active ? Colors.primary : Colors.surface_container
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        transform: Matrix4x4 {
                            readonly property real k: picker.skewFactor
                            matrix: Qt.matrix4x4(1, k, 0, -k * (tabPill.implicitHeight / 2),
                                                 0, 1, 0, 0,
                                                 0, 0, 1, 0,
                                                 0, 0, 0, 1)
                        }
                    }

                    // upright, centered label (not skewed)
                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: Math.round(6 * picker.s)

                        GlyphIcon {
                            visible: tabPill.modelData.fav
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(14 * picker.s)
                            height: Math.round(14 * picker.s)
                            name: "heart-filled"
                            stroke: 1.8
                            color: tabPill.active ? Colors.on_primary : Colors.error
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tabPill.modelData.fav
                                ? tabPill.modelData.label + " (" + WallpaperFavorites.list.length + ")"
                                : tabPill.modelData.label
                            font.family: Appearance.font.family
                            font.pixelSize: Appearance.font.size * picker.s
                            font.weight: Font.Bold
                            color: tabPill.active ? Colors.on_primary : Colors.on_surface
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                    }

                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: picker.setFavoritesOnly(tabPill.modelData.fav)
                    }
                }
            }
        }

        // ── empty folder hint ────────────────────────────────────────────────
        Column {
            z: 50
            anchors.centerIn: view
            spacing: Appearance.spacing.xs * picker.s
            visible: picker.allWallpapers.length === 0

            GlyphIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(28 * picker.s)
                height: Math.round(28 * picker.s)
                name: "image"
                stroke: 1.6
                color: Colors.on_surface_variant
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Add images to ~/wallpapers"
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: Appearance.font.sizeL * picker.s
            }
        }

        // ── empty favorites placeholder (~/shell; wallpaper level only) ──────
        Rectangle {
            z: 50
            anchors.centerIn: view
            visible: picker.currentFolder !== "" && picker.favoritesOnly
                && picker.displayedItems.length === 0
                && picker.allWallpapers.length > 0
            implicitWidth: emptyRow.implicitWidth + Math.round(40 * picker.s)
            implicitHeight: emptyRow.implicitHeight + Math.round(28 * picker.s)
            radius: Appearance.rounding.large * picker.s
            color: Colors.surface_container

            Row {
                id: emptyRow
                anchors.centerIn: parent
                spacing: Math.round(10 * picker.s)

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(20 * picker.s)
                    height: Math.round(20 * picker.s)
                    name: "heart-filled"
                    stroke: 1.8
                    color: Colors.error
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "No favorites yet — focus a wallpaper and press Ctrl+F (or tap the heart)"
                    font.family: Appearance.font.family
                    font.pixelSize: Appearance.font.sizeL * picker.s
                    color: Colors.on_surface
                }
            }
        }
    }
}
