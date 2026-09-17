pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../m3"
import "../../colors"
import "../../services"
import "../../config"
import "../lib/Fuzzy.js" as Fuzzy
import "../lib/calc.js" as Calc

/**
 * astralis — app launcher surface (Ricelin Launcher.qml layout). The 探
 * search field (autofocused on open, live "n / total" counter) over a
 * hairline divider and the ranked DesktopEntries list: each row an icon
 * tile, the app name on the left, its category dim on the right, and a
 * `return` glyph in `primary` on the keyboard selection. Entries are ranked by
 * fuzzy match (lib/Fuzzy.js) and prior launch frequency, persisted to
 * ~/.cache/astralis/launcher-usage.json; an arithmetic query flips into calc
 * mode with a copyable result row (lib/calc.js). Up/Down move the selection,
 * Enter launches and closes. The soul bead rides the search caret.
 *
 * ── The interaction contract here ───────────────────────────────────────────
 *
 * Every clickable — the calc result and every app row — hosts an
 * `M3StateLayer` rather than a hand-rolled MouseArea, so hover, press, the
 * press dip, the keyboard focus ring, the pointer target and the screen-reader
 * plumbing all come from one place (astralis-architecture §6.1).
 *
 * The rows keep a separate `HoverHandler` alongside it, because the state
 * layer only reports *whether* the pointer is inside and this list needs to
 * know *where* it moved: rows sliding under a stationary cursor during
 * keyboard scrolling emit hover events at an unchanged window position, and
 * those must not steal the keyboard selection.
 *
 * 🛑 No entrance stagger anywhere in this file. The list re-filters on every
 * keystroke and `ListView` rebuilds ALL delegates when the model COUNT
 * changes, so a staggered entrance would replay on every keypress.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 11
    mRight: 11
    mBottom: 14

    property string query: ""
    property int selectedIndex: 0

    /** Per-app launch counts ({ desktopId: count }), fed into Fuzzy.rank. */
    property var usage: ({})
    readonly property string usageFile: Quickshell.env("HOME") + "/.cache/astralis/launcher-usage.json"

    /**
     * Calc mode: when the whole query parses as a real calculation (an
     * expression with at least one operation, so lone numbers and app names like
     * i3 or python3 fall through to app search), a result row appears above the
     * list and Enter copies the value. The parser in lib/calc.js never evals, so
     * a query cannot run code.
     */
    readonly property var calc: Calc.evaluate(query)
    readonly property bool calcActive: calc.ok
    property bool calcCopied: false
    onQueryChanged: calcCopied = false

    function copyResult() {
        if (!root.calcActive)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", root.calc.display]);
        root.calcCopied = true;
    }

    /**
     * Window-coordinate position of the last hover event that was allowed to
     * move the selection. Rows sliding under a stationary cursor during
     * keyboard scrolling produce hover events at an unchanged window position,
     * which must not steal the keyboard selection.
     */
    property point lastPointer: Qt.point(-1, -1)

    readonly property var allEntries: {
        var src = DesktopEntries.applications.values;
        var out = [];
        for (var i = 0; i < src.length; i++)
            if (src[i] && !src[i].noDisplay)
                out.push(src[i]);
        return out;
    }

    readonly property var results: Fuzzy.rank(allEntries, query, usage)

    ameForm: "caret"
    amePoint: {
        void root.width;
        void root.height;
        void search.input.width;
        void search.input.cursorRectangle;
        var c = search.input.cursorRectangle;
        return search.input.mapToItem(root, c.x + c.width / 2, c.y + c.height / 2);
    }

    function mapCategory(raw) {
        const order = [
            ["TerminalEmulator", "Terminal"], ["WebBrowser", "Browser"],
            ["InstantMessaging", "Chat"], ["Audio", "Media"], ["AudioVideo", "Media"],
            ["Video", "Media"], ["Game", "Game"], ["Development", "Dev"],
            ["Graphics", "Graphics"], ["Office", "Office"], ["Settings", "System"],
            ["System", "System"], ["Utility", "Tool"], ["Network", "Net"]
        ];
        const cats = String(raw).split(/[;,]/);
        for (let i = 0; i < order.length; i++)
            if (cats.includes(order[i][0]))
                return order[i][1];
        return "";
    }

    function move(delta) {
        if (results.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function activate() {
        if (root.calcActive) {
            root.copyResult();
            return;
        }
        if (results.length === 0 || selectedIndex < 0 || selectedIndex >= results.length)
            return;
        var entry = results[selectedIndex];
        if (entry) {
            if (entry.id) {
                root.usage[entry.id] = (root.usage[entry.id] || 0) + 1;
                root.saveUsage();
            }
            entry.execute();
        }
        root.requestClose();
    }

    onOpenChanged: if (open) {
        search.text = "";
        query = "";
        selectedIndex = 0;
        Qt.callLater(() => search.input.forceActiveFocus());
    }

    onResultsChanged: if (selectedIndex >= results.length) selectedIndex = 0

    FileView {
        id: usageStore
        path: root.usageFile
        blockLoading: true
        atomicWrites: true
        printErrors: false      // silent when the file doesn't exist yet
    }

    property bool cacheDirReady: false
    property bool usagePending: false

    /**
     * Persist usage counts. atomicWrites can't create the cache dir, so a save
     * that lands before mkdir finishes is held and flushed from mkdir's
     * onExited — the first-run write never races the directory into existence.
     */
    function saveUsage() {
        if (cacheDirReady)
            usageStore.setText(JSON.stringify(root.usage));
        else
            usagePending = true;
    }

    // atomicWrites can't create directories; guarantee the cache dir exists.
    Process {
        id: mkdirProc
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.cache/astralis"]
        onExited: {
            root.cacheDirReady = true;
            if (root.usagePending) {
                root.usagePending = false;
                usageStore.setText(JSON.stringify(root.usage));
            }
        }
    }

    Component.onCompleted: {
        mkdirProc.running = true;
        var raw = usageStore.text();
        try {
            root.usage = raw && raw.length ? JSON.parse(raw) : ({});
        } catch (e) {
            root.usage = ({});
        }
    }

    // ── search field ────────────────────────────────────────────────────────
    SearchField {
        id: search
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        kanji: "探"
        placeholder: "Search apps"
        count: root.results.length
        total: root.allEntries.length
        onTextChanged: {
            root.query = text;
            root.selectedIndex = 0;
        }
        onMoved: (d) => root.move(d)
        onAccepted: root.activate()
        onDismissed: root.requestClose()
    }

    Rectangle {
        id: divider
        anchors.top: search.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.alpha(Colors.on_surface, 0.06)
    }

    // ── calc result row ─────────────────────────────────────────────────────
    Item {
        id: calcRow
        visible: root.calcActive
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? 44 * root.s : 0

        // The shell's one in-surface container recipe (Recorder's tiles): a
        // flat on_surface wash under a hairline of the same ink. The pill body
        // is already a Panel, and a Panel nested in a Panel reads as packaging
        // (astralis-architecture §2b-ii / §2b-iii).
        Rectangle {
            anchors.fill: parent
            radius: 9 * root.s
            color: Qt.alpha(Colors.on_surface, 0.04)
            border.width: 1
            border.color: Qt.alpha(Colors.on_surface, 0.06)
        }

        M3StateLayer {
            anchors.fill: parent
            radius: 9 * root.s
            s: root.s
            contentColor: Colors.on_surface
            // A card-sized target: §6.1's 0.96 tier. The hit area is already
            // the full row, so it does not need growing to the 40dp floor.
            pressScale: 0.96
            minTarget: 0
            accessibleName: "Copy result " + root.calc.display
            accessibleDescription: root.query
            onClicked: root.copyResult()
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 12 * root.s
            anchors.rightMargin: 12 * root.s

            Column {
                anchors.left: parent.left
                anchors.right: copyHint.left
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s

                Text {
                    width: parent.width
                    text: "= " + root.calc.display
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 15 * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.query
                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * root.s
                    elide: Text.ElideRight
                }
            }

            /**
             * The hint used to read "↵ copy" — the return ARROW borrowed from
             * the UI font. A Unicode symbol renders at the font's weight,
             * metrics and optical size, never the icon set's, so it landed
             * beside the shell's real icons as a visibly different object no
             * matter how it was sized (astralis-architecture §6.0-pre). It is
             * a GlyphIcon now, and the copied state swaps it for a check
             * rather than dropping to a bare word.
             */
            Row {
                id: copyHint
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5 * root.s

                readonly property color tone: root.calcCopied
                    ? Colors.on_surface_variant : Colors.primary

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13 * root.s
                    height: 13 * root.s
                    name: root.calcCopied ? "check" : "return"
                    color: copyHint.tone
                    stroke: 1.8
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.calcCopied ? "copied" : "copy"
                    color: copyHint.tone
                    font.family: Appearance.font.family
                    font.pixelSize: 11 * root.s
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
        }
    }

    Text {
        anchors.centerIn: list
        // Cross-faded rather than flipped: this appears and vanishes as the
        // query narrows, and a bare `visible` flip mid-typing reads as a
        // flicker. Safe here because it is anchor-positioned — gating
        // `visible` on a measured size inside a positioner is the one-way
        // latch in quickshell-core §5.
        opacity: root.results.length === 0 && !root.calcActive ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        text: root.query.length ? "No matches" : "No apps found"
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 10.5 * root.s
    }

    // ── results ─────────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors.top: root.calcActive ? calcRow.bottom : divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 5 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.results.length

        delegate: Item {
            id: appRow
            required property int index
            width: list.width
            height: 38 * root.s

            readonly property var entry: root.results[index]
            readonly property bool selected: index === root.selectedIndex

            readonly property string secondary: {
                if (!entry)
                    return "";
                if (entry.genericName && entry.genericName.length > 0)
                    return entry.genericName;
                if (entry.categories && entry.categories.length > 0)
                    return root.mapCategory(entry.categories);
                return "";
            }

            /**
             * Selection container. A neutral tonal step, deliberately NOT a
             * second accent: the shell has ONE accent and it is spent on the
             * `return` glyph marking the row Enter will launch. Tinting the
             * row with `secondary_container` as well would put two selection
             * colours in one list, which is the seam §3.5 exists to stop.
             *
             * Hover is no longer drawn here — that is the state layer's job
             * now, so this reads purely as "this is the selected row" and
             * cross-fades in instead of flipping.
             */
            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                color: Colors.surface_container_highest
                border.width: 1
                border.color: Qt.alpha(Colors.on_surface, 0.06)
                opacity: appRow.selected ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }

            /**
             * Pointer POSITION, which the state layer does not report. Rows
             * sliding under a stationary cursor while the keyboard scrolls the
             * list emit hover events at an unchanged window position; those
             * must not steal the keyboard selection, so only a genuine move
             * re-targets it.
             */
            HoverHandler {
                id: rowHover
                onPointChanged: {
                    if (!hovered)
                        return;
                    var sp = point.scenePosition;
                    if (sp.x !== root.lastPointer.x || sp.y !== root.lastPointer.y) {
                        root.lastPointer = Qt.point(sp.x, sp.y);
                        root.selectedIndex = appRow.index;
                    }
                }
            }

            M3StateLayer {
                anchors.fill: parent
                radius: 9 * root.s
                s: root.s
                contentColor: Colors.on_surface
                // §6.1's launcher-result tier. `minTarget: 0` because a
                // full-width row is already an easy target and growing it to
                // the 40dp floor would push each row's hit area 1dp into its
                // neighbour's gap.
                pressScale: 0.96
                minTarget: 0
                accessibleName: appRow.entry ? appRow.entry.name : ""
                accessibleDescription: appRow.secondary
                onClicked: {
                    root.selectedIndex = appRow.index;
                    root.activate();
                }
            }

            Item {
                anchors.fill: parent
                anchors.leftMargin: 11 * root.s
                anchors.rightMargin: 11 * root.s

                Rectangle {
                    id: iconBg
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22 * root.s
                    height: 22 * root.s
                    radius: 5 * root.s
                    color: Qt.alpha(Colors.on_surface, 0.05)
                    visible: !(icon.status === Image.Ready && icon.source != "")
                }
                Image {
                    id: icon
                    anchors.fill: iconBg
                    sourceSize.width: Math.round(40 * root.s)
                    sourceSize.height: Math.round(40 * root.s)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: status === Image.Ready && source != ""
                    source: appRow.entry && appRow.entry.icon
                        ? Quickshell.iconPath(appRow.entry.icon, true) : ""
                }

                // Same "↵" → GlyphIcon swap as Clipboard's; see the note there.
                // The metrics object stays because the row reserves this slot's
                // width whether or not the hint is showing, so a row does not
                // reflow as the selection moves — it just no longer has to
                // measure a text character to know how wide an icon is.
                QtObject {
                    id: retMetrics
                    readonly property real width: 14 * root.s
                }
                /**
                 * Reserved, never collapsed. The slot used to shrink to 0 on
                 * an unselected row, so every arrow keypress re-laid the
                 * secondary label and re-elided the app name one row above and
                 * one below the cursor — a list that shivered as you moved
                 * through it. It holds its width now and only the ink
                 * cross-fades, which is also the only way the fade is visible
                 * at all: a GlyphIcon scales its path by `min(w,h)/24`, so a
                 * zero-width one has already vanished before opacity matters.
                 */
                GlyphIcon {
                    id: ret
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    width: retMetrics.width
                    height: retMetrics.width
                    name: "return"
                    color: Colors.primary
                    stroke: 1.8
                    opacity: appRow.selected ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                }

                Text {
                    id: sec
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: ret.left
                    anchors.rightMargin: 8 * root.s
                    visible: appRow.secondary.length > 0
                    text: appRow.secondary
                    color: appRow.selected ? Colors.on_surface_variant
                        : Qt.alpha(Colors.on_surface_variant, 0.65)
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * root.s
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                Text {
                    anchors.left: iconBg.right
                    anchors.leftMargin: 10 * root.s
                    anchors.right: sec.visible ? sec.left : ret.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    text: appRow.entry ? appRow.entry.name : ""
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 13 * root.s
                    // PINNED. This used to go DemiBold on the selected row,
                    // and since hover moves the selection that was a weight
                    // change under the cursor: font.weight cannot be animated
                    // and re-flows the text as it changes (§6.1). Selection is
                    // said by the container and the `return` glyph instead.
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }
}
