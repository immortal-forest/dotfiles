pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — clipboard history surface (Ricelin Clipboard.qml layout). The 控
 * search field (with the hold-to-wipe trash glyph on its right) over a hairline
 * divider and the cliphist list. Image entries render their cached thumbnail
 * beside a type/size label; text entries render as text. Enter/click copies
 * the entry back to the clipboard via cliphist decode | wl-copy and closes;
 * hovering a row cross-fades its age ↵ marker into a dismiss ✕ that deletes
 * it (Ctrl+X does the same for the keyboard selection). Multi-select: Ctrl- or
 * Shift-click a row, click its thumbnail/type mark, Ctrl+Space, or Ctrl+A for
 * every result; once anything is marked a plain click toggles, the counter
 * reads "n selected", and the trash (or Ctrl+X / Delete) deletes the marked
 * rows with one click; Esc clears the marks. The history, its thumbnails and
 * the cliphist calls live in [[ClipHistory]], which outlives this surface, so
 * an open shows the last snapshot at once and re-syncs.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 17
    mRight: 17
    mBottom: 14

    property string query: ""
    property int selectedIndex: 0
    readonly property var entries: ClipHistory.entries

    readonly property var entryById: {
        var m = {};
        for (var i = 0; i < entries.length; i++)
            m[entries[i].id] = entries[i];
        return m;
    }

    // Multi-select marks, id → true. By id, so they survive narrowing the search.
    property var marked: ({})
    readonly property int markCount: Object.keys(marked).length
    property int markAnchor: -1

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
        for (var i = 0; i < entries.length; i++)
            if (entries[i].hay.indexOf(q) !== -1)
                out.push(entries[i]);
        return out;
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
        ClipHistory.copy(results[selectedIndex].id);
        root.requestClose();
    }

    function removeAt(index) {
        if (index < 0 || index >= results.length)
            return;
        slideTimer.arm();
        ClipHistory.remove(results[index].id);
    }

    function removeMarked() {
        var ids = Object.keys(marked);
        if (!ids.length)
            return;
        marked = {};
        markAnchor = -1;
        slideTimer.arm();
        ClipHistory.removeMany(ids);
    }

    function setMarks(ids, on) {
        var m = Object.assign({}, marked);
        for (var i = 0; i < ids.length; i++) {
            if (on)
                m[ids[i]] = true;
            else
                delete m[ids[i]];
        }
        marked = m;
    }

    function toggleMark(index) {
        if (index < 0 || index >= results.length)
            return;
        var id = results[index].id;
        setMarks([id], !marked[id]);
        markAnchor = index;
        selectedIndex = index;
    }

    // Shift-click: marks every row between the last toggled one and this one.
    function markRange(index) {
        if (index < 0 || index >= results.length)
            return;
        var from = markAnchor >= 0 && markAnchor < results.length ? markAnchor : index;
        var ids = [];
        for (var i = Math.min(from, index); i <= Math.max(from, index); i++)
            ids.push(results[i].id);
        setMarks(ids, true);
        selectedIndex = index;
    }

    // Ctrl+A: marks every current result, or unmarks them if all already are.
    function markAll() {
        var ids = results.map(e => e.id);
        setMarks(ids, !(ids.length > 0 && ids.every(id => marked[id] === true)));
    }

    /**
     * Keeps `rows` (one `eid` per result) in step with `results` by removing
     * and inserting only what changed. The old count-based model reset on
     * every change, which rebuilt every delegate and snapped the list back to
     * the top, so deleting a row halfway down lost your place.
     */
    function syncRows() {
        var want = results;
        if (rows.count === 0) {
            if (want.length)
                rows.append(want.map(e => ({ eid: e.id })));
            return;
        }
        var at = {};
        for (var j = 0; j < want.length; j++)
            at[want[j].id] = j;
        var i = 0;
        j = 0;
        while (j < want.length) {
            if (i < rows.count) {
                var have = rows.get(i).eid;
                if (at[have] === undefined || at[have] < j) {
                    rows.remove(i);
                    continue;
                }
                if (have === want[j].id) {
                    i++;
                    j++;
                    continue;
                }
            }
            rows.insert(i, { eid: want[j].id });
            i++;
            j++;
        }
        if (rows.count > i)
            rows.remove(i, rows.count - i);
    }

    function wipe() {
        ClipHistory.wipe();
    }

    onOpenChanged: if (open) {
        search.text = "";
        query = "";
        selectedIndex = 0;
        marked = {};
        markAnchor = -1;
        list.positionViewAtBeginning();
        ClipHistory.refresh();
        Qt.callLater(() => search.input.forceActiveFocus());
    }

    onResultsChanged: {
        syncRows();
        if (selectedIndex >= results.length)
            selectedIndex = Math.max(0, results.length - 1);
    }

    // Drop marks whose entry left the history (deleted elsewhere, wiped).
    onEntriesChanged: {
        var live = {};
        for (var i = 0; i < entries.length; i++)
            live[entries[i].id] = true;
        var gone = Object.keys(marked).filter(id => !live[id]);
        if (gone.length)
            setMarks(gone, false);
    }

    Component.onCompleted: syncRows()

    ListModel {
        id: rows
    }

    // Rows below a deleted one slide up into its place instead of jumping.
    // Armed only for a moment around a delete, so search filtering doesn't
    // set the whole list sliding.
    Timer {
        id: slideTimer
        property bool armed: false
        interval: Motion.standard
        function arm() {
            armed = true;
            restart();
        }
        onTriggered: armed = false
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
        counterText: root.markCount > 0 ? root.markCount + " selected"
            : root.results.length + " / " + root.entries.length
        onTextChanged: {
            root.query = text;
            root.selectedIndex = 0;
            Qt.callLater(list.positionViewAtBeginning);
        }
        onMoved: (d) => root.move(d)
        onAccepted: root.activate()
        onDismissed: root.requestClose()
        onKeyPressed: (e) => {
            var ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (ctrl && e.key === Qt.Key_X && search.input.selectedText.length === 0) {
                if (root.markCount > 0)
                    root.removeMarked();
                else
                    root.removeAt(root.selectedIndex);
                e.accepted = true;
            } else if (e.key === Qt.Key_Delete && root.markCount > 0) {
                root.removeMarked();
                e.accepted = true;
            } else if (ctrl && e.key === Qt.Key_A) {
                root.markAll();
                e.accepted = true;
            } else if (ctrl && e.key === Qt.Key_Space) {
                root.toggleMark(root.selectedIndex);
                e.accepted = true;
            } else if (e.key === Qt.Key_Escape && root.markCount > 0) {
                // first Esc drops the marks, the next one closes
                root.marked = {};
                root.markAnchor = -1;
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
            // With rows marked the trash deletes just those, on one click.
            readonly property bool selecting: root.markCount > 0
            readonly property color tone: holding || selecting ? Colors.primary
                : (wipeArea.containsMouse ? Colors.on_surface : Qt.alpha(Colors.on_surface_variant, 0.65))

            // A screen-reader user gets no benefit from a heat-fill they
            // cannot see, so the hold requirement goes in the description
            // (PowerMenu's confirm-tile idiom). Deliberately NOT wired to a
            // press action: a destructive hold-to-confirm control must not be
            // fireable by a single synthetic activation.
            Accessible.role: Accessible.Button
            Accessible.name: selecting ? "Delete " + root.markCount + " selected" : "Clear clipboard history"
            Accessible.description: selecting ? "" : "Hold to confirm — this will delete all clipboard history"
            Accessible.focusable: true
            Accessible.onPressAction: if (selecting) root.removeMarked()

            GlyphIcon {
                anchors.fill: parent
                name: "trash"
                stroke: 1.7
                color: wipeBtn.tone
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
                onPressed: if (!wipeBtn.selecting) wipeHeat.press()
                onReleased: wipeHeat.release()
                onExited: wipeHeat.cancel()
                onClicked: if (wipeBtn.selecting) root.removeMarked()
            }
        }
    }

    // Centred in the whole gap between the search field and the first
    // entry (it sat 8 below the field but only 6 above the entry).
    Rule {
        id: divider
        anchors.top: search.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 14 * root.s + 1

        // wipe heat sweeps along the divider while the wipe glyph is held
        Rectangle {
            anchors.top: divider.line.top
            anchors.bottom: divider.line.bottom
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
        // Cross-faded like Launcher's empty state: it appears as the query
        // narrows and while the list is still loading, and a bare flip flickers.
        opacity: root.results.length === 0 ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        text: ClipHistory.unavailable ? "cliphist unavailable"
            : (root.query.length ? "No matches" : "History empty")
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 10.5 * root.s
    }

    // ── history list ────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors.top: divider.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 2 * root.s
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: rows

        displaced: Transition {
            enabled: slideTimer.armed
            NumberAnimation {
                property: "y"
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.standardCurve
            }
        }

        delegate: Item {
            id: row
            required property int index
            required property string eid
            width: list.width
            height: (entry && entry.isImage ? 44 : 28) * root.s

            readonly property var entry: root.entryById[eid]
            readonly property bool selected: index === root.selectedIndex
            readonly property bool marked: root.marked[eid] === true

            Accessible.role: Accessible.Button
            Accessible.name: row.entry === undefined ? "" : (row.entry.isImage ? row.entry.label
                : (row.entry.secret ? "Hidden secret" : row.entry.preview))
            Accessible.description: row.entry !== undefined && row.entry.isImage ? row.entry.sizeLabel : ""
            Accessible.selected: row.selected
            Accessible.checkable: root.markCount > 0
            Accessible.checked: row.marked
            Accessible.focusable: true
            Accessible.onPressAction: {
                if (root.markCount > 0) {
                    root.toggleMark(row.index);
                    return;
                }
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

            // Cross-fades like Launcher's selection container instead of flipping.
            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                opacity: row.selected || rowHover.hovered ? 1 : 0
                visible: opacity > 0.01
                color: row.selected ? Colors.surface_container_highest : Qt.alpha(Colors.on_surface, 0.03)
                border.width: row.selected ? 1 : 0
                border.color: Qt.alpha(Colors.outline_variant, 0.9)
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }

            // marked tint, over the selection fill so a marked row still reads as marked when selected
            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                color: Qt.alpha(Colors.primary, 0.13)
                opacity: row.marked ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }

            // Press dip, the same 0.96 launcher-result tier as Launcher's rows.
            scale: rowArea.pressed ? 0.96 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.modifiers & Qt.ShiftModifier)
                        root.markRange(row.index);
                    else if ((mouse.modifiers & Qt.ControlModifier) || root.markCount > 0)
                        root.toggleMark(row.index);
                    else {
                        root.selectedIndex = row.index;
                        root.activate();
                    }
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
                        // empty until the thumb pass has the file on disk
                        source: thumbTile.visible && row.entry.thumb.length
                            ? "file://" + encodeURI(row.entry.thumb).replace(/#/g, '%23').replace(/\?/g, '%3F')
                            : ""
                        sourceSize.width: 128
                        sourceSize.height: 128
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }
                }

                // Text entries keep the thumbnail column too (a dim type mark
                // centred in the same 52·s slot), so every label starts on one
                // left edge instead of text rows hugging the inset while image
                // labels start a thumbnail further in.
                GlyphIcon {
                    id: textMark
                    visible: !thumbTile.visible && opacity > 0.01
                    opacity: markSlot.ring ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    x: (52 * root.s - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14 * root.s
                    height: width
                    // a lock marks rows whose key is hidden (ClipHistory.secretView)
                    name: row.entry !== undefined && row.entry.secret ? "lock" : "type"
                    stroke: 1.7
                    color: row.selected ? Colors.on_surface_variant : Qt.alpha(Colors.on_surface_variant, 0.5)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                // Multi-select toggle in the leading slot (M3's avatar tap):
                // hovering it, or any row being marked, shows an empty ring
                // there; a marked row fills it with a check. On an image the
                // ring sits on a scrim over the thumbnail.
                Item {
                    id: markSlot
                    width: 52 * root.s
                    height: parent.height
                    readonly property bool ring: row.marked || markHover.hovered || root.markCount > 0

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: (parent.height - thumbTile.height) / 2
                        anchors.bottomMargin: anchors.topMargin
                        visible: thumbTile.visible && opacity > 0.01
                        radius: thumbTile.radius
                        color: Qt.alpha(Colors.scrim, row.marked ? 0.55 : 0.4)
                        opacity: markSlot.ring ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 15 * root.s
                        height: width
                        radius: width / 2
                        color: row.marked ? Colors.primary : "transparent"
                        border.width: row.marked ? 0 : 1.5 * root.s
                        border.color: thumbTile.visible ? Colors.on_surface : Colors.on_surface_variant
                        opacity: markSlot.ring ? 1 : 0
                        visible: opacity > 0.01
                        scale: row.marked ? 1 : 0.86
                        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 10 * root.s
                            height: width
                            name: "check"
                            color: Colors.on_primary
                            stroke: 2.6
                            opacity: row.marked ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                        }
                    }

                    HoverHandler {
                        id: markHover
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (mouse.modifiers & Qt.ShiftModifier)
                                root.markRange(row.index);
                            else
                                root.toggleMark(row.index);
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: (52 + 9) * root.s
                    anchors.right: sizeTag.left
                    anchors.rightMargin: 8 * root.s
                    readonly property bool secret: row.entry !== undefined && row.entry.secret === true
                    // `shown` already has bullets where Obel's ss01 wouldn't mask
                    text: row.entry === undefined ? "" : (row.entry.isImage ? row.entry.label : row.entry.shown)
                    color: row.entry !== undefined && row.entry.isImage
                        ? (row.selected ? Colors.on_surface_variant : Qt.alpha(Colors.on_surface_variant, 0.65))
                        : (row.selected ? Colors.on_surface : Colors.on_surface_variant)
                    // Key rows only: Obel Mono with its ss01 secret masking (Outfit
                    // stays the UI face; Obel is a cell wider, hence a step smaller).
                    font.family: secret ? "Obel Mono Lig" : Appearance.font.family
                    font.features: secret ? ({ "ss01": 1 }) : ({})
                    font.pixelSize: (secret ? 10.5 : 11.5) * root.s
                    // Pinned, as in Launcher: hover moves the selection, and a weight
                    // change under the cursor reflows the text and can't be animated.
                    font.weight: Font.Medium
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
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
                    color: Qt.alpha(Colors.on_surface_variant, 0.65)
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * root.s
                    font.features: ({ "tnum": 1 })
                }

                Item {
                    id: tail
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    // Fixed: GlyphIcon has no implicit size, so sizing off it
                    // collapsed the tail to 0 and the glyphs drew over sizeTag.
                    width: 14 * root.s
                    height: 14 * root.s

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
