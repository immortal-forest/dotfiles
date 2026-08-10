pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../../colors"
import "../../config"
import "../lib/Fuzzy.js" as Fuzzy
import "../lib/calc.js" as Calc

/**
 * astralis — app launcher surface (Ricelin Launcher.qml layout). The 探
 * search field (autofocused on open, live "n / total" counter) over a
 * hairline divider and the ranked DesktopEntries list: each row an icon
 * tile, the app name on the left, its category dim on the right, and a
 * vermilion ↵ on the keyboard selection. Entries are ranked by fuzzy match
 * (lib/Fuzzy.js) and prior launch frequency, persisted to
 * ~/.cache/astralis/launcher-usage.json; an arithmetic query flips into calc
 * mode with a copyable result row (lib/calc.js). Up/Down move the selection,
 * Enter launches and closes. The soul bead rides the search caret.
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

        Rectangle {
            anchors.fill: parent
            radius: 9 * root.s
            color: Colors.surface_container_highest
            border.width: 1
            border.color: Qt.alpha(Colors.outline_variant, 0.9)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
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

            Text {
                id: copyHint
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.calcCopied ? "copied" : "↵ copy"
                color: root.calcCopied ? Colors.on_surface_variant : Colors.primary
                font.family: Appearance.font.family
                font.pixelSize: 11 * root.s
            }
        }
    }

    Text {
        anchors.centerIn: list
        visible: root.results.length === 0 && !root.calcActive
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

            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                visible: appRow.selected || rowArea.containsMouse
                color: appRow.selected ? Colors.surface_container_highest : Qt.alpha(Colors.on_surface, 0.03)
                border.width: appRow.selected ? 1 : 0
                border.color: Qt.alpha(Colors.outline_variant, 0.9)
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (m) => {
                    var g = rowArea.mapToItem(null, m.x, m.y);
                    if (g.x !== root.lastPointer.x || g.y !== root.lastPointer.y) {
                        root.lastPointer = Qt.point(g.x, g.y);
                        root.selectedIndex = appRow.index;
                    }
                }
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

                TextMetrics {
                    id: retMetrics
                    font.family: Appearance.font.family
                    font.pixelSize: 12 * root.s
                    text: "↵"
                }
                Text {
                    id: ret
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: retMetrics.text
                    color: Colors.primary
                    font.family: Appearance.font.family
                    font.pixelSize: 12 * root.s
                    visible: appRow.selected
                    width: visible ? retMetrics.advanceWidth + 6 * root.s : 0
                    horizontalAlignment: Text.AlignRight
                }

                Text {
                    id: sec
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: ret.left
                    anchors.rightMargin: appRow.selected ? 8 * root.s : 0
                    visible: appRow.secondary.length > 0
                    text: appRow.secondary
                    color: appRow.selected ? Colors.on_surface_variant
                        : Qt.alpha(Colors.on_surface_variant, 0.65)
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * root.s
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
                    font.weight: appRow.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }
}
