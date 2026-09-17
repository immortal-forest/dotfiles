pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — 字 FONT settings page (ported from Ricelin pill/FontPicker.qml):
 * a searchable list of curated families, each row rendering its own name as
 * a live preview so the shape reads before the pick, plus a preview line
 * under the search that follows the focused row. A click writes the family
 * to Flags.uiFont, which Appearance.font.family reads back so the whole
 * shell re-renders at once — chrome included, by design; the leading reset
 * row writes "" to fall back to the bundled default. The current pick
 * carries the primary tint. Reached from Appearance's Font nav row, not the
 * sidebar (Ricelin parity: the picker is a drill-in of Appearance); back
 * returns there.
 *
 * Curated, not every installed family. This used to list literally
 * everything `fc-list` returned — a few hundred families deep once the full
 * Google Fonts set landed, including script/handwritten/display faces never
 * meant to carry dense chrome text. Because `Flags.uiFont` really does apply
 * everywhere, picking one of those made the settings sidebar, nav chevrons'
 * neighbouring labels and every row title render in a cursive face — legible
 * as a novelty, not as a sidebar. `uiSafeFamilies` below is the fix: the same
 * grotesque/geometric families actually compared for this role (see
 * AppearanceConfig.qml's `family` doc), each with a real weight ladder so
 * `Font.Medium`/`DemiBold` requests never fall back to a synthesized style.
 * Ricelin delta otherwise unchanged: families come from `fc-list : family`
 * through a Process (first name per line, deduped) rather than
 * Qt.fontFamilies(), run once per pill session, now intersected with the
 * allowlist and sorted.
 */
SettingsPage {
    id: root

    rows: []

    /** Deduped, sorted, curated family names; filled once per session. */
    property var families: []
    property string query: ""
    property int focusIndex: 0

    /**
     * Window position of the last hover event allowed to move the highlight.
     * Rows sliding under a stationary cursor during keyboard scrolling repeat
     * the same window point and must not steal the selection.
     */
    property point lastPointer: Qt.point(-1, -1)

    readonly property string resetLabel: "System default (" + Appearance.font.familyDefault + ")"

    /**
     * The only families the picker will ever offer as `Flags.uiFont`. Every
     * one is a grotesque/geometric sans with a full weight range, installed
     * and `fc-match`-clean at the time this list was written — the actual
     * shortlist this shell's UI face was chosen from, not a guess. Widening
     * this is a deliberate design call (a script/display face becoming
     * legitimately selectable as the SHELL'S face, chrome included), not a
     * one-line addition — see the header doc above for why.
     */
    readonly property var uiSafeFamilies: [
        "Be Vietnam Pro", "DM Sans", "Figtree", "Geist", "Hanken Grotesk",
        "Inter", "Lexend", "Manrope", "Nunito", "Onest", "Outfit",
        "Plus Jakarta Sans", "Poppins", "Red Hat Display", "Schibsted Grotesk",
        "Sora", "Space Grotesk", "Urbanist", "Work Sans"
    ]

    /**
     * The family list narrowed by a case-insensitive substring on the live
     * query, with the reset entry prepended. The reset row carries an empty
     * family so a click clears Flags.uiFont; the search never hides it, so
     * the fallback stays one tap away.
     */
    readonly property var entries: {
        var q = root.query.trim().toLowerCase();
        var out = [{ family: "", label: root.resetLabel, reset: true }];
        for (var i = 0; i < root.families.length; i++) {
            if (q.length === 0 || root.families[i].toLowerCase().indexOf(q) >= 0)
                out.push({ family: root.families[i], label: root.families[i], reset: false });
        }
        return out;
    }

    /** Family the preview line renders: the focused row's, else the live pick. */
    readonly property string previewFamily: {
        if (root.entries.length > 0) {
            var e = root.entries[Math.min(root.focusIndex, root.entries.length - 1)];
            if (e && !e.reset && e.family.length > 0)
                return e.family;
        }
        return Flags.uiFont.length > 0 ? Flags.uiFont : Appearance.font.familyDefault;
    }

    function pick(family) {
        Flags.uiFont = family;
    }

    /** Slide the keyboard highlight by dir (+1 down, -1 up), clamped and kept in view. */
    function move(dir) {
        if (root.entries.length === 0)
            return;
        root.focusIndex = Math.max(0, Math.min(root.entries.length - 1, root.focusIndex + dir));
        list.positionViewAtIndex(root.focusIndex, ListView.Contain);
    }

    function activate() {
        if (root.focusIndex < 0 || root.focusIndex >= root.entries.length)
            return;
        root.pick(root.entries[root.focusIndex].family);
    }

    onActiveChanged: {
        if (active) {
            if (families.length === 0)
                fcProc.running = true;
            focusIndex = 0;
            Qt.callLater(() => search.input.forceActiveFocus());
        } else {
            search.text = "";
            query = "";
        }
    }

    Process {
        id: fcProc
        command: ["fc-list", ":", "family"]
        stdout: StdioCollector {
            onStreamFinished: {
                var seen = ({});
                var out = [];
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    // A line may alias several names ("JetBrainsMono Nerd
                    // Font,JetBrainsMono NF,…"); the first is the canonical
                    // family. Each weight/style instance of a variable font
                    // repeats its family on its own line, so this still needs
                    // the `seen` dedup even filtered down to 19 names.
                    var fam = lines[i].split(",")[0].trim();
                    if (root.uiSafeFamilies.indexOf(fam) < 0)
                        continue;
                    if (seen[fam] === true)
                        continue;
                    seen[fam] = true;
                    out.push(fam);
                }
                out.sort(function (a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : 1; });
                root.families = out;
            }
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "字"
        title: "FONT"
        showBack: true
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
        placeholder: "Search fonts"
        count: Math.max(0, root.entries.length - 1)
        total: root.families.length
        onTextChanged: {
            root.query = text;
            root.focusIndex = 0;
        }
        onMoved: (d) => root.move(d)
        onAccepted: root.activate()
        onDismissed: {
            if (text.length > 0)
                text = "";
            else
                root.back();
        }
    }

    /** Live preview line: one sentence set in the focused family. */
    Item {
        id: preview
        anchors.top: search.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 26 * root.s

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 12 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: "Aa Bb Cc 0123 — the quick brown fox"
            color: Colors.on_surface_variant
            font.family: root.previewFamily
            font.pixelSize: 13 * root.s
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: previewLine
        anchors.top: preview.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.alpha(Colors.on_surface, 0.06)
    }

    ListView {
        id: list
        anchors.top: previewLine.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries

        delegate: Item {
            id: frow
            required property int index
            required property var modelData

            readonly property bool isReset: frow.modelData.reset === true
            readonly property bool selected: frow.isReset
                ? Flags.uiFont.length === 0
                : Flags.uiFont === frow.modelData.family
            readonly property bool focused: root.focusIndex === frow.index

            width: ListView.view.width
            height: 36 * root.s

            onFocusedChanged: if (focused) root.focusRowItem = frow
            Component.onDestruction: if (root.focusRowItem === frow) root.focusRowItem = null

            // A font list row: `selected` marks the live pick (Flags.uiFont),
            // `focused` mirrors the page's own keyboard highlight — same
            // split KeybindsPage's rows use (quickshell-core.md §9b: no
            // Accessible.value, so nothing numeric belongs here).
            Accessible.role: Accessible.ListItem
            Accessible.name: frow.modelData.label
            Accessible.checkable: true
            Accessible.checked: frow.selected
            Accessible.focusable: true
            Accessible.focused: frow.focused
            Accessible.onPressAction: root.pick(frow.modelData.family)

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (m) => {
                    var g = rowArea.mapToItem(null, m.x, m.y);
                    if (g.x !== root.lastPointer.x || g.y !== root.lastPointer.y) {
                        root.lastPointer = Qt.point(g.x, g.y);
                        root.focusIndex = frow.index;
                    }
                }
                onClicked: root.pick(frow.modelData.family)
            }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 2 * root.s
                anchors.bottomMargin: 2 * root.s
                radius: 9 * root.s
                color: frow.selected
                    ? Qt.alpha(Colors.primary, 0.14)
                    : (frow.focused ? Colors.surface_container_highest : "transparent")
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12 * root.s
                anchors.right: tick.left
                anchors.rightMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: frow.modelData.label
                color: frow.selected ? Colors.primary : Colors.on_surface
                font.family: frow.isReset ? Appearance.font.family : frow.modelData.family
                font.pixelSize: 14 * root.s
                font.weight: frow.selected ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
            }

            Rectangle {
                id: tick
                anchors.right: parent.right
                anchors.rightMargin: 14 * root.s
                anchors.verticalCenter: parent.verticalCenter
                visible: frow.selected
                width: 6 * root.s
                height: 6 * root.s
                radius: width / 2
                color: Colors.primary
            }
        }
    }
}
