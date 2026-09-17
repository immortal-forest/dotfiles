pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../m3"
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 鍵 KEYBINDS settings page (ported from Ricelin pill/Keybinds.qml):
 * a searchable, scrolling list of the compositor's active keybinds, each row a
 * combo chip on the left and its dispatch on the right; hovering a row reveals
 * the raw dispatcher · arg and any flags underneath, and the arrow keys walk
 * the list from the search field.
 *
 * Ricelin delta: Ricelin parses and machine-edits its own binds.lua (chord
 * capture, add / rebind / delete, hyprctl reload). astralis binds are
 * hand-written Lua closures — hypr.d/keybinds.lua registers hl.bind callbacks,
 * which Hyprland reports as dispatcher "__lua" plus a callback index — so this
 * page reads `hyprctl binds -j` (language-agnostic ground truth; the Lua is
 * never parsed) and stays a READ-ONLY viewer: edit hypr.d/keybinds.lua and
 * `hyprctl reload` to change a bind. Ricelin's edit/add form is dropped whole.
 */
SettingsPage {
    id: root

    rows: []

    property var binds: []
    property string query: ""
    property int focusIndex: 0

    // hyprctl reports our binds only as "__lua callback #N", so descriptions
    // come from parsing hypr.d/keybinds.lua (scripts/keybind-desc → JSON keyed
    // by canonical combo). Kept separate from the hyprctl list (the ground
    // truth of what is actually bound) and merged in rebuild() by combo.
    property var descMap: ({})
    property string rawText: ""

    /**
     * Window position of the last hover event allowed to move the highlight.
     * Rows sliding under a stationary cursor during keyboard scrolling repeat
     * the same window point and must not steal the selection.
     */
    property point lastPointer: Qt.point(-1, -1)

    /**
     * Binds whose combo, action or caption contains the current query as a
     * case-insensitive substring. An empty query passes every bind through.
     */
    readonly property var filtered: {
        if (root.query.length === 0)
            return root.binds;
        var q = root.query.toLowerCase();
        return root.binds.filter(function (b) {
            return (b.combo + " " + b.action + " " + b.caption).toLowerCase().indexOf(q) !== -1;
        });
    }

    onFilteredChanged: if (focusIndex >= filtered.length)
        focusIndex = Math.max(0, filtered.length - 1)

    /** modmask bits → readable modifier names (SHIFT 1 / CTRL 4 / ALT 8 / SUPER 64). */
    function modsOf(mask) {
        var m = [];
        if (mask & 64) m.push("Super");
        if (mask & 4) m.push("Ctrl");
        if (mask & 8) m.push("Alt");
        if (mask & 1) m.push("Shift");
        return m;
    }

    /**
     * Display form of a key: mouse tokens spelled out (Ricelin comboPretty),
     * single letters uppercased.
     *
     * Scroll direction is a WORD, never an arrow. These strings sit inside a
     * combo chip beside "Super", "Ctrl", "Shift" — all spelled out — and a
     * "↑" borrowed from the UI font renders at the FONT's weight, metrics and
     * optical size, never the icon set's, so it lands in that chip as a
     * visibly different object no matter how it is sized. "Scroll up" matches
     * how every other token in the same chip already reads.
     */
    function prettyKey(b) {
        var k = String(b.key || "");
        if (k.length === 0)
            return b.keycode ? "keycode " + b.keycode : "?";
        if (k === "mouse_up") return "Scroll up";
        if (k === "mouse_down") return "Scroll down";
        if (k === "mouse:272") return "LMB";
        if (k === "mouse:273") return "RMB";
        return k.length === 1 ? k.toUpperCase() : k;
    }

    function refresh() {
        bindsProc.running = true;
        descProc.running = true;
    }

    /**
     * Canonical combo key — uppercased tokens, modifiers sorted, key last —
     * matching scripts/keybind-desc so a hyprctl bind (modmask + key) looks up
     * its Lua-derived description regardless of case/order.
     */
    function canonOf(modmask, key) {
        var mods = [];
        if (modmask & 64) mods.push("SUPER");
        if (modmask & 4) mods.push("CTRL");
        if (modmask & 8) mods.push("ALT");
        if (modmask & 1) mods.push("SHIFT");
        mods.sort();
        return mods.concat([String(key || "").toUpperCase()]).join("+");
    }

    /** Merge the hyprctl bind list (rawText) with the Lua descriptions (descMap). */
    function rebuild() {
        var out = [];
        try {
            var raw = JSON.parse(root.rawText || "[]");
            for (var i = 0; i < raw.length; i++) {
                var b = raw[i];
                var arg = String(b.arg || "");
                var lua = b.dispatcher === "__lua";
                var meta = root.descMap[root.canonOf(b.modmask, b.key)];

                var flags = [];
                if (b.locked) flags.push("locked");
                if (b.repeat) flags.push("repeats");
                if (b.release) flags.push("on release");

                var action = (meta && meta.desc) ? meta.desc
                    : (lua ? "Lua dispatch" : b.dispatcher + (arg.length > 0 ? " " + arg : ""));

                var cap = [];
                if (meta && meta.cmd && meta.cmd !== action)
                    cap.push(meta.cmd);
                if (!meta || !meta.desc)
                    cap.push(lua ? "keybinds.lua callback #" + arg
                        : b.dispatcher + (arg.length > 0 ? " · " + arg : ""));
                if (flags.length > 0)
                    cap.push(flags.join(" · "));

                out.push({
                    combo: root.modsOf(b.modmask).concat([root.prettyKey(b)]).join(" + "),
                    action: action,
                    caption: cap.join(" · ")
                });
            }
        } catch (e) {
            out = [];
        }
        root.binds = out;
    }

    /** Slide the focused row by `dir` (+1 down, -1 up), clamped and kept in view. */
    function move(dir) {
        if (root.filtered.length === 0)
            return;
        root.focusIndex = Math.max(0, Math.min(root.filtered.length - 1, root.focusIndex + dir));
        list.positionViewAtIndex(root.focusIndex, ListView.Contain);
    }

    onActiveChanged: {
        if (active) {
            refresh();
            focusIndex = 0;
        } else {
            search.text = "";
            query = "";
        }
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.rawText = this.text;
                root.rebuild();
            }
        }
    }

    // Lua-derived descriptions (scripts/keybind-desc parses hypr.d/keybinds.lua
    // live, so edits show up on the next page open). Merged in rebuild().
    Process {
        id: descProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/astralis/scripts/keybind-desc"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.descMap = JSON.parse(this.text || "{}");
                } catch (e) {
                    root.descMap = ({});
                }
                root.rebuild();
            }
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "鍵"
        title: "KEYBINDS"
        onBack: root.back()
    }

    SearchField {
        id: search
        anchors.top: header.bottom
        anchors.topMargin: 10 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        kanji: "探"
        placeholder: "Search binds"
        count: root.filtered.length
        total: root.binds.length
        onTextChanged: {
            root.query = text;
            root.focusIndex = 0;
        }
        onMoved: (d) => root.move(d)
        onDismissed: {
            if (text.length > 0)
                text = "";
            else
                root.back();
        }
    }

    ListView {
        id: list
        anchors.top: search.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.filtered

        delegate: Item {
            id: brow
            required property int index
            required property var modelData

            readonly property bool focused: root.focusIndex === brow.index

            width: ListView.view.width
            height: 38 * root.s

            onFocusedChanged: if (focused) root.focusRowItem = brow
            Component.onDestruction: if (root.focusRowItem === brow) root.focusRowItem = null

            // A read-only list line: the combo is its name, the action and the
            // raw dispatcher are its description. `focused` mirrors this page's
            // own highlight rather than QML focus, exactly as SettingsRow does,
            // so assistive tech follows the one notion of "current" the page
            // actually has. (Nothing numeric here, so no `description` range —
            // and `Accessible.value` does not exist anyway, see
            // quickshell-core.md §9b.)
            Accessible.role: Accessible.ListItem
            Accessible.name: brow.modelData.combo
            Accessible.description: brow.modelData.action
                + (brow.modelData.caption.length > 0 ? " · " + brow.modelData.caption : "")
            Accessible.focusable: true
            Accessible.focused: brow.focused
            Accessible.readOnly: true

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 3 * root.s
                anchors.bottomMargin: 3 * root.s
                radius: 9 * root.s
                color: (rowArea.containsMouse || brow.focused) ? Colors.surface_container_highest : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                // Read-only viewer — nothing fires on click, but the row
                // still reveals its raw dispatcher on hover, so the pointer
                // cursor keeps the row feeling responsive under the mouse.
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (m) => {
                    var g = rowArea.mapToItem(null, m.x, m.y);
                    if (g.x !== root.lastPointer.x || g.y !== root.lastPointer.y) {
                        root.lastPointer = Qt.point(g.x, g.y);
                        root.focusIndex = brow.index;
                    }
                }
            }

            Rectangle {
                id: comboChip
                anchors.left: parent.left
                anchors.leftMargin: 12 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: comboText.implicitWidth + 16 * root.s
                // The shell's control line, the same 24dp the switches, the
                // segmented control and the scrub values sit on — a keycap is
                // the only pill on this page, so it has to hold that line or it
                // reads as a different program's chip.
                height: M3.controlHeight * root.s
                radius: height / 2
                color: brow.focused ? Qt.alpha(Colors.primary, 0.16) : Colors.surface_container_high
                border.width: 1
                border.color: brow.focused ? Qt.alpha(Colors.primary, 0.45) : Qt.alpha(Colors.on_surface, 0.06)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                Text {
                    id: comboText
                    anchors.centerIn: parent
                    text: brow.modelData.combo
                    color: brow.focused ? Colors.on_surface : Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 11 * root.s
                    font.weight: Font.Bold
                    font.letterSpacing: 0.3 * root.s
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }

            Column {
                anchors.left: comboChip.right
                anchors.leftMargin: 12 * root.s
                anchors.right: parent.right
                anchors.rightMargin: 14 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: brow.modelData.action
                    color: brow.focused ? Colors.on_surface_variant : Qt.alpha(Colors.on_surface_variant, 0.65)
                    font.family: Appearance.font.family
                    font.pixelSize: 11 * root.s
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                Text {
                    // `shown` drives layout; opacity fades the raw dispatcher
                    // in/out over that so it eases in with the hover instead
                    // of hard-popping at full opacity (same idiom as
                    // SettingsRow's captionOnFocus).
                    readonly property bool shown: rowArea.containsMouse && brow.modelData.caption.length > 0
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    visible: shown || opacity > 0.01
                    opacity: shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    text: brow.modelData.caption
                    color: Qt.alpha(Colors.on_surface_variant, 0.5)
                    font.family: Appearance.font.family
                    font.pixelSize: 9 * root.s
                    elide: Text.ElideLeft
                }
            }
        }
    }

    Text {
        anchors.centerIn: list
        visible: root.filtered.length === 0
        text: root.binds.length === 0 ? "No binds reported" : "No matches"
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 10.5 * root.s
    }

    // No rule between the list and this footnote. A 1px line to fence two
    // clusters apart is the toolbar idiom every other surface in the shell
    // dropped (astralis-architecture §2b-iii); the gap below the last row does
    // the same job without laying ink over the wallpaper.
    Column {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        Item {
            width: parent.width
            height: 26 * root.s

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: "read-only · binds live in hypr.d/keybinds.lua"
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1 * root.s
            }
        }
    }
}
