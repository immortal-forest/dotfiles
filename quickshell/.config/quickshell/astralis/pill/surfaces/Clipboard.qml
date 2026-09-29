pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — clipboard history surface (Ricelin Clipboard.qml layout). The 控
 * search field (with the hold-to-wipe 掃 glyph on its right) over a hairline
 * divider and the cliphist list. Image entries render their cached thumbnail
 * beside a type/size label; text entries render as text. Enter/click copies
 * the entry back to the clipboard via cliphist decode | wl-copy and closes;
 * hovering a row cross-fades its age ↵ marker into a dismiss ✕ that deletes
 * it (Ctrl+X does the same for the keyboard selection). Thumbnails decode
 * into the cache before the list lands so image rows never bind to a missing
 * file.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 17
    mRight: 17
    mBottom: 14

    property string query: ""
    property int selectedIndex: 0
    property var entries: []
    property bool unavailable: false

    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/astralis-cliphist/"

    /**
     * Window-coordinate position of the last hover event that was allowed to
     * move the selection. Rows sliding under a stationary cursor during
     * keyboard scrolling produce hover events at an unchanged window position,
     * which must not steal the keyboard selection.
     */
    property point lastPointer: Qt.point(-1, -1)

    ameForm: "caret"
    amePoint: {
        void root.width;
        void root.height;
        void search.input.width;
        void search.input.cursorRectangle;
        var c = search.input.cursorRectangle;
        return search.input.mapToItem(root, c.x + c.width / 2, c.y + c.height / 2);
    }

    readonly property var results: {
        var q = query.trim().toLowerCase();
        if (!q.length)
            return entries;
        var out = [];
        for (var i = 0; i < entries.length; i++) {
            var hay = (entries[i].isImage
                ? entries[i].label + " " + entries[i].sizeLabel
                : entries[i].preview).toLowerCase();
            if (hay.indexOf(q) !== -1)
                out.push(entries[i]);
        }
        return out;
    }

    // Coalesce refreshes: if a thumb/list pass is mid-flight the request would
    // otherwise be silently dropped (e.g. a post-delete reload landing while a
    // prior pass runs). Remember it and flush once the current pass finishes.
    property bool refreshPending: false

    function refresh() {
        if (thumbProc.running || listProc.running) {
            refreshPending = true;
            return;
        }
        thumbProc.running = true;
    }

    function move(delta) {
        if (results.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(results.length - 1, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function activate() {
        if (results.length === 0 || selectedIndex < 0 || selectedIndex >= results.length)
            return;
        var id = String(results[selectedIndex].id);
        if (!/^\d+$/.test(id))
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "_", id]);
        root.requestClose();
    }

    function removeAt(index) {
        if (index < 0 || index >= results.length || delProc.running)
            return;
        var id = String(results[index].id);
        if (!/^\d+$/.test(id))
            return;
        // optimistic local prune so the row vanishes at once
        var kept = [];
        for (var i = 0; i < entries.length; i++)
            if (String(entries[i].id) !== id)
                kept.push(entries[i]);
        entries = kept;
        delProc.command = ["sh", "-c", "printf '%s' \"$1\" | cliphist delete", "_", id];
        delProc.running = true;
    }

    function wipe() {
        entries = [];
        wipeProc.running = true;
    }

    onOpenChanged: if (open) {
        search.text = "";
        query = "";
        selectedIndex = 0;
        refresh();
        Qt.callLater(() => search.input.forceActiveFocus());
    }

    onResultsChanged: if (selectedIndex >= results.length) selectedIndex = Math.max(0, results.length - 1)

    Process {
        id: delProc
        onExited: root.refresh()
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        onExited: root.refresh()
    }

    /**
     * Thumbnail pass, run before every list read: decodes any image entry
     * without a cached preview into thumbDir/<id> (QML sniffs the format, no
     * extension needed) and prunes thumbs whose entry left the history.
     */
    Process {
        id: thumbProc
        command: ["sh", "-c",
            'cache="$1"; mkdir -p "$cache"; chmod 700 "$cache"; ' +
            'tab=$(printf "\\t"); snapshot=$(cliphist list) || exit 1; ' +
            'ids=$(printf "%s\\n" "$snapshot" | cut -f1); ' +
            'for f in "$cache"/*; do [ -e "$f" ] || continue; fid=$(basename "$f"); ' +
            'printf "%s\\n" "$ids" | grep -qxF "$fid" || rm -f -- "$f"; done; ' +
            'printf "%s\\n" "$snapshot" | while IFS= read -r line; do case "$line" in ' +
            '*"$tab[[ binary data"*png*" ]]"|*"$tab[[ binary data"*jpg*" ]]"|*"$tab[[ binary data"*jpeg*" ]]"|*"$tab[[ binary data"*gif*" ]]"|*"$tab[[ binary data"*bmp*" ]]"|*"$tab[[ binary data"*webp*" ]]") ' +
            'id=${line%%"$tab"*}; t="$cache/$id"; ' +
            '[ -s "$t" ] || printf "%s" "$id" | cliphist decode > "$t" 2>/dev/null ;; ' +
            'esac; done',
            "_", root.thumbDir]
        onExited: listProc.running = true
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                var out = [];
                var metaRe = /^\[\[ binary data (.*) \]\]$/;
                var imgRe = /\b(png|jpg|jpeg|gif|bmp|webp)\b/;
                var splitRe = /^(\S+ \S+) (\w+) (\d+)x(\d+)$/;
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i];
                    var tab = line.indexOf("\t");
                    if (tab < 1)
                        continue;
                    var id = line.substring(0, tab);
                    if (!/^\d+$/.test(id))
                        continue;
                    var preview = line.substring(tab + 1);
                    var m = metaRe.exec(preview);
                    var isImage = m !== null && imgRe.test(m[1]);
                    var label = "";
                    var sizeLabel = "";
                    if (isImage) {
                        var p = splitRe.exec(m[1]);
                        label = p ? p[2] + " " + p[3] + "×" + p[4] : m[1];
                        sizeLabel = p ? p[1] : "";
                    }
                    out.push({
                        id: id,
                        preview: preview,
                        isImage: isImage,
                        label: label,
                        sizeLabel: sizeLabel,
                        thumb: isImage ? root.thumbDir + id : ""
                    });
                }
                root.entries = out;
                if (out.length)
                    root.unavailable = false;
            }
        }
        onExited: (exitCode) => {
            root.unavailable = exitCode !== 0;
            if (root.refreshPending) {
                root.refreshPending = false;
                thumbProc.running = true;
            }
        }
    }

    // ── search field + hold-to-wipe ─────────────────────────────────────────
    SearchField {
        id: search
        z: 5
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        kanji: "控"
        placeholder: "Search clipboard"
        count: root.results.length
        total: root.entries.length
        onTextChanged: {
            root.query = text;
            root.selectedIndex = 0;
        }
        onMoved: (d) => root.move(d)
        onAccepted: root.activate()
        onDismissed: root.requestClose()
        onKeyPressed: (e) => {
            if (e.key === Qt.Key_X && (e.modifiers & Qt.ControlModifier)
                && search.input.selectedText.length === 0) {
                root.removeAt(root.selectedIndex);
                e.accepted = true;
            }
        }

        Item {
            id: wipeBtn
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * root.s
            height: 16 * root.s

            readonly property real hold: wipeHeat.hold
            readonly property bool holding: wipeHeat.holding
            readonly property color tone: holding ? Colors.primary
                : (wipeArea.containsMouse ? Colors.on_surface : Qt.alpha(Colors.on_surface_variant, 0.65))

            // A screen-reader user gets no benefit from a heat-fill they
            // cannot see, so the hold requirement goes in the description
            // (PowerMenu's confirm-tile idiom). Deliberately NOT wired to a
            // press action: a destructive hold-to-confirm control must not be
            // fireable by a single synthetic activation.
            Accessible.role: Accessible.Button
            Accessible.name: "Clear clipboard history"
            Accessible.description: "Hold to confirm — this will delete all clipboard history"
            Accessible.focusable: true

            Text {
                anchors.centerIn: parent
                text: "掃"
                color: wipeBtn.tone
                font.family: Appearance.font.jp
                font.pixelSize: 12 * root.s
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            HeatHold {
                id: wipeHeat
                onConfirmed: root.wipe()
            }

            MouseArea {
                id: wipeArea
                anchors.fill: parent
                anchors.margins: -5 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: wipeHeat.press()
                onReleased: wipeHeat.release()
                onExited: wipeHeat.cancel()
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: search.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.alpha(Colors.on_surface, 0.06)

        // wipe heat sweeps along the divider while 掃 is held
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: parent.width * wipeBtn.hold
            visible: wipeBtn.holding
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(Colors.primary, 0.15) }
                GradientStop { position: 1.0; color: Colors.primary }
            }
        }
    }

    Text {
        anchors.centerIn: list
        visible: root.results.length === 0
        text: root.unavailable ? "cliphist unavailable"
            : (root.query.length ? "No matches" : "History empty")
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 10.5 * root.s
    }

    // ── history list ────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors.top: divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 2 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.results.length

        delegate: Item {
            id: row
            required property int index
            width: list.width
            height: (entry && entry.isImage ? 44 : 28) * root.s

            readonly property var entry: root.results[index]
            readonly property bool selected: index === root.selectedIndex

            Accessible.role: Accessible.Button
            Accessible.name: row.entry === undefined ? "" : (row.entry.isImage ? row.entry.label : row.entry.preview)
            Accessible.description: row.entry !== undefined && row.entry.isImage ? row.entry.sizeLabel : ""
            Accessible.selected: row.selected
            Accessible.focusable: true
            Accessible.onPressAction: {
                root.selectedIndex = row.index;
                root.activate();
            }

            HoverHandler {
                id: rowHover
                onPointChanged: {
                    if (!hovered)
                        return;
                    var sp = point.scenePosition;
                    if (sp.x !== root.lastPointer.x || sp.y !== root.lastPointer.y) {
                        root.lastPointer = Qt.point(sp.x, sp.y);
                        root.selectedIndex = row.index;
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                visible: row.selected || rowHover.hovered
                color: row.selected ? Colors.surface_container_highest : Qt.alpha(Colors.on_surface, 0.03)
                border.width: row.selected ? 1 : 0
                border.color: Qt.alpha(Colors.outline_variant, 0.9)
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.selectedIndex = row.index;
                    root.activate();
                }
            }

            Item {
                anchors.fill: parent
                anchors.leftMargin: 11 * root.s
                anchors.rightMargin: 11 * root.s

                Rectangle {
                    id: thumbTile
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.entry !== undefined && row.entry.isImage
                    width: visible ? 52 * root.s : 0
                    height: 32 * root.s
                    radius: 6 * root.s
                    color: Colors.surface_container_highest
                    border.width: 1
                    border.color: Qt.alpha(Colors.outline_variant, 0.6)
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: thumbTile.visible
                            ? "file://" + encodeURI(row.entry.thumb).replace(/#/g, '%23').replace(/\?/g, '%3F')
                            : ""
                        sourceSize.width: 128
                        sourceSize.height: 128
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: thumbTile.visible ? thumbTile.right : parent.left
                    anchors.leftMargin: thumbTile.visible ? 9 * root.s : 0
                    anchors.right: sizeTag.left
                    anchors.rightMargin: 8 * root.s
                    text: row.entry === undefined ? "" : (row.entry.isImage ? row.entry.label : row.entry.preview)
                    color: row.entry !== undefined && row.entry.isImage
                        ? (row.selected ? Colors.on_surface_variant : Qt.alpha(Colors.on_surface_variant, 0.65))
                        : (row.selected ? Colors.on_surface : Colors.on_surface_variant)
                    font.family: Appearance.font.family
                    font.pixelSize: 11.5 * root.s
                    font.weight: row.selected ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                }

                Text {
                    id: sizeTag
                    anchors.right: tail.left
                    // Gated on the TEXT, not on `width` — `width` is itself a
                    // binding on the same condition, and a margin that reads
                    // the width it participates in laying out is a binding
                    // loop ("Binding loop detected for property width"). Both
                    // now read the one source of truth.
                    anchors.rightMargin: sizeTag.text.length > 0 ? 8 * root.s : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.entry !== undefined && row.entry.isImage ? row.entry.sizeLabel : ""
                    width: text.length ? implicitWidth : 0
                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * root.s
                    font.features: ({ "tnum": 1 })
                }

                Item {
                    id: tail
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(ret.implicitWidth, dismiss.implicitWidth)
                    height: Math.max(ret.implicitHeight, dismiss.implicitHeight)

                    // GlyphIcon, not the "↵" and "✕" characters these used to
                    // be. A Unicode symbol borrowed from the UI font renders at
                    // the FONT's weight, metrics and optical size — never the
                    // icon set's — so it lands next to real icons as a visibly
                    // different object no matter how it is sized or coloured.
                    // That is where the shell's odd ones out were coming from.
                    GlyphIcon {
                        id: ret
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: row.selected && !rowHover.hovered ? 1 : 0
                        width: 14 * root.s
                        height: 14 * root.s
                        name: "return"
                        color: Colors.primary
                        stroke: 1.8
                        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    }

                    GlyphIcon {
                        id: dismiss
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: rowHover.hovered ? 1 : 0
                        width: 13 * root.s
                        height: 13 * root.s
                        name: "close"
                        color: dismissArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                        stroke: 1.8
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

                        Accessible.role: Accessible.Button
                        Accessible.name: "Remove clipboard entry"
                        Accessible.focusable: rowHover.hovered
                        Accessible.onPressAction: root.removeAt(row.index)

                        MouseArea {
                            id: dismissArea
                            anchors.fill: parent
                            anchors.margins: -6 * root.s
                            enabled: rowHover.hovered
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.removeAt(row.index)
                        }
                    }
                }
            }
        }
    }
}
