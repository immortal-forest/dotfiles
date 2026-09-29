pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../services" as Services

/**
 * astralis — 飾 LOOK settings page (ported from Ricelin pill/Look.qml): the
 * window-decoration knobs — gaps in/out, border size, rounding, resize on
 * border, the blur block — plus the active/inactive border colours as
 * palette-derived swatch strips (Ricelin left the colours to its palette
 * pipeline; astralis exposes them as `general:col.*_border` keywords).
 *
 * Ricelin delta: where Ricelin regex-edits decoration.lua and reloads
 * Hyprland, every row here reads and writes the Services.Settings store — the
 * singleton persists settings.json, live-applies the hyprctl keyword
 * (debounced) and regenerates the reload overlay. Ricelin's collapsible
 * groups are flattened to labelled sections (the fixed surface scrolls, so
 * nothing needs to fold to fit); its shadow / opacity / night-light / pill
 * groups stay with their own owners (shadow is hand-config off, night-light
 * and pill prefs are Flags-side follow-ups). Colour swatches store the
 * keyword's own rgba(RRGGBBAA) literal, snapshotted from the live palette at
 * pick time — matugen re-runs recolour the shell, not a stored border.
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    rows: {
        var r = [
            { item: gapsInRow, kind: "scrub", bump: function (d) { gapsInScrub.bump(d); } },
            { item: gapsOutRow, kind: "scrub", bump: function (d) { gapsOutScrub.bump(d); } },
            { item: borderRow, kind: "scrub", bump: function (d) { borderScrub.bump(d); } },
            { item: roundRow, kind: "scrub", bump: function (d) { roundScrub.bump(d); } },
            { item: resizeRow, kind: "toggle", get: function () { return root.resizeOnBorder; }, set: function (v) { root.resizeOnBorder = v; root.setStore.set("resizeOnBorder", v); } },
            { item: activeColRow, kind: "seg", vals: root.activeOptions.map(function (o) { return o.value; }), get: function () { return root.activeBorder; }, set: function (v) { root.activeBorder = v; root.setStore.set("activeBorder", v); } },
            { item: inactiveColRow, kind: "seg", vals: root.inactiveOptions.map(function (o) { return o.value; }), get: function () { return root.inactiveBorder; }, set: function (v) { root.inactiveBorder = v; root.setStore.set("inactiveBorder", v); } },
            { item: blurEnRow, kind: "toggle", get: function () { return root.blurOn; }, set: function (v) { root.blurOn = v; root.setStore.set("blurEnabled", v); } }
        ];
        if (root.blurOn) {
            r.push({ item: blSizeRow, kind: "scrub", bump: function (d) { blSizeScrub.bump(d); } });
            r.push({ item: blPassRow, kind: "scrub", bump: function (d) { blPassScrub.bump(d); } });
        }
        return r;
    }

    property int gapsIn: 3
    property int gapsOut: 8
    property int borderSize: 2
    property int rounding: 10
    property bool resizeOnBorder: false
    property string activeBorder: ""
    property string inactiveBorder: ""
    property bool blurOn: true
    property int blurSize: 6
    property int blurPasses: 3

    property bool loaded: false

    /** Per-field values captured on the first seed; the ScrubValue undo glyphs revert to these. */
    property var base: ({})

    // The singleton, hoisted once (`Settings` unqualified would shadow-clash
    // with the surface type of the same name in importing contexts).
    readonly property var setStore: Services.Settings

    onActiveChanged: if (active && !root.loaded) root.seed()

    /**
     * Seeds every control from the Settings store once per pill session
     * (touched keys from settings.json, untouched keys from the defaults
     * table that mirrors the hand-written hypr.d values), then snapshots the
     * scrub revert baseline.
     */
    function seed() {
        root.gapsIn = root.numOr(root.setStore.get("gapsIn"), 3);
        root.gapsOut = root.numOr(root.setStore.get("gapsOut"), 8);
        root.borderSize = root.numOr(root.setStore.get("borderSize"), 2);
        root.rounding = root.numOr(root.setStore.get("rounding"), 10);
        root.resizeOnBorder = root.setStore.get("resizeOnBorder") === true;
        root.activeBorder = String(root.setStore.get("activeBorder"));
        root.inactiveBorder = String(root.setStore.get("inactiveBorder"));
        root.blurOn = root.setStore.get("blurEnabled") === true;
        root.blurSize = root.numOr(root.setStore.get("blurSize"), 6);
        root.blurPasses = root.numOr(root.setStore.get("blurPasses"), 3);
        root.base = {
            gapsIn: root.gapsIn,
            gapsOut: root.gapsOut,
            borderSize: root.borderSize,
            rounding: root.rounding,
            blurSize: root.blurSize,
            blurPasses: root.blurPasses
        };
        root.loaded = true;
    }

    function numOr(v, d) {
        var n = Number(v);
        return isNaN(n) ? d : n;
    }

    // ── palette-literal helpers: QML color → hyprland rgba(RRGGBBAA) ────────
    function hex2(x) {
        var n = Math.round(x * 255);
        var s = n.toString(16);
        return n < 16 ? "0" + s : s;
    }

    function rgbaOf(c) {
        return "rgba(" + hex2(c.r) + hex2(c.g) + hex2(c.b) + hex2(c.a) + ")";
    }

    /** Swatch choices; "Default" mirrors the compositor's own border colours. */
    readonly property var activeOptions: [
        { label: "Default", col: "#ffffff", value: "rgba(ffffffff)" },
        { label: "Primary", col: Colors.primary, value: rgbaOf(Colors.primary) },
        { label: "Secondary", col: Colors.secondary, value: rgbaOf(Colors.secondary) },
        { label: "Tertiary", col: Colors.tertiary, value: rgbaOf(Colors.tertiary) },
        { label: "Outline", col: Colors.outline, value: rgbaOf(Colors.outline) }
    ]

    readonly property var inactiveOptions: [
        { label: "Default", col: "#444444", value: "rgba(444444ff)" },
        { label: "Outline", col: Colors.outline, value: rgbaOf(Colors.outline) },
        { label: "Outline variant", col: Colors.outline_variant, value: rgbaOf(Colors.outline_variant) },
        { label: "Surface", col: Colors.surface_container_highest, value: rgbaOf(Colors.surface_container_highest) }
    ]

    /**
     * Palette swatch strip (the colour rows' control): one dot per option,
     * the stored value's dot wears the bright ring. Selection keys off the
     * stored rgba literal, so a palette re-run that orphans the value simply
     * lights no dot until the user picks again.
     */
    component SwatchSeg: Row {
        id: sw
        property var options: []
        property var value
        signal picked(var value)
        spacing: 7 * root.s

        Repeater {
            model: sw.options

            Rectangle {
                id: dot
                required property var modelData
                readonly property bool current: sw.value === dot.modelData.value

                width: 16 * root.s
                height: 16 * root.s
                radius: width / 2
                color: dot.modelData.col
                border.width: dot.current ? 2 : 1
                border.color: dot.current ? Colors.on_surface : Qt.alpha(Colors.on_surface, 0.18)
                // Hover grow and press dip are separate concepts on the same
                // scale — multiplied together so a press mid-hover still dips
                // from the grown size instead of one clobbering the other.
                scale: (dotMA.containsMouse ? 1.15 : 1) * (dotMA.pressed ? 0.96 : 1)
                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                // A colour strip is a radio GROUP, exactly like SettingsSeg —
                // one swatch is the stored border colour and picking another
                // clears it, so this reads as "2 of 5" rather than five
                // unrelated buttons. (`Accessible.value` and friends don't
                // exist on the attached type — quickshell-core.md §9b.)
                Accessible.role: Accessible.RadioButton
                Accessible.name: String(dot.modelData.label)
                Accessible.checkable: true
                Accessible.checked: dot.current
                Accessible.onPressAction: sw.picked(dot.modelData.value)

                MouseArea {
                    id: dotMA
                    anchors.fill: parent
                    anchors.margins: -3 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sw.picked(dot.modelData.value)
                }
            }
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "飾"
        title: "LOOK"
        onBack: root.back()
    }

    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.topMargin: 4 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: returnToBounds()

        Column {
            id: content
            width: flick.width
            spacing: 0

            SettingsGroupLabel { s: root.s; text: "Window" }

            SettingsRow {
                id: gapsInRow
                surface: root
                name: "Gaps inner"
                sub: "Space between tiled windows"
                captionOnFocus: true
                icon: "app-window"

                ScrubValue {
                    id: gapsInScrub
                    s: root.s
                    value: root.gapsIn
                    openValue: root.base.gapsIn
                    from: 0; to: 40; step: 1; unit: "px"
                    onEdited: v => {
                        root.gapsIn = v;
                        root.setStore.set("gapsIn", v);
                    }
                }
            }

            SettingsRow {
                id: gapsOutRow
                surface: root
                name: "Gaps outer"
                sub: "Space to the screen edge"
                captionOnFocus: true
                icon: "monitor"

                ScrubValue {
                    id: gapsOutScrub
                    s: root.s
                    value: root.gapsOut
                    openValue: root.base.gapsOut
                    from: 0; to: 60; step: 1; unit: "px"
                    onEdited: v => {
                        root.gapsOut = v;
                        root.setStore.set("gapsOut", v);
                    }
                }
            }

            SettingsRow {
                id: borderRow
                surface: root
                name: "Border size"
                sub: "Window outline thickness"
                captionOnFocus: true
                icon: "scaling"

                ScrubValue {
                    id: borderScrub
                    s: root.s
                    value: root.borderSize
                    openValue: root.base.borderSize
                    from: 0; to: 8; step: 1; unit: "px"
                    onEdited: v => {
                        root.borderSize = v;
                        root.setStore.set("borderSize", v);
                    }
                }
            }

            SettingsRow {
                id: roundRow
                surface: root
                name: "Rounding"
                sub: "Corner radius in pixels"
                captionOnFocus: true
                icon: "record"

                ScrubValue {
                    id: roundScrub
                    s: root.s
                    value: root.rounding
                    openValue: root.base.rounding
                    from: 0; to: 30; step: 1; unit: "px"
                    onEdited: v => {
                        root.rounding = v;
                        root.setStore.set("rounding", v);
                    }
                }
            }

            SettingsRow {
                id: resizeRow
                surface: root
                name: "Resize on border"
                sub: "Drag a window edge to resize"
                captionOnFocus: true
                icon: "mouse"
                last: true

                LinkToggle {
                    s: root.s
                    on: root.resizeOnBorder
                    onToggled: {
                        root.resizeOnBorder = !root.resizeOnBorder;
                        root.setStore.set("resizeOnBorder", root.resizeOnBorder);
                    }
                }
            }

            SettingsGroupLabel { s: root.s; text: "Border colour" }

            SettingsRow {
                id: activeColRow
                surface: root
                name: "Active window"
                sub: "Focused window border, from the palette"
                captionOnFocus: true
                icon: "awake"

                SwatchSeg {
                    options: root.activeOptions
                    value: root.activeBorder
                    onPicked: (v) => {
                        root.activeBorder = v;
                        root.setStore.set("activeBorder", v);
                    }
                }
            }

            SettingsRow {
                id: inactiveColRow
                surface: root
                name: "Inactive window"
                sub: "Unfocused window border"
                captionOnFocus: true
                icon: "moon"
                last: true

                SwatchSeg {
                    options: root.inactiveOptions
                    value: root.inactiveBorder
                    onPicked: (v) => {
                        root.inactiveBorder = v;
                        root.setStore.set("inactiveBorder", v);
                    }
                }
            }

            SettingsGroupLabel { s: root.s; text: "Blur" }

            SettingsRow {
                id: blurEnRow
                surface: root
                name: "Enabled"
                sub: "Blur behind transparent windows"
                captionOnFocus: true
                icon: "droplet"
                last: !root.blurOn

                LinkToggle {
                    s: root.s
                    on: root.blurOn
                    onToggled: {
                        root.blurOn = !root.blurOn;
                        root.setStore.set("blurEnabled", root.blurOn);
                    }
                }
            }

            SettingsRow {
                id: blSizeRow
                surface: root
                name: "Strength"
                sub: "Blur radius"
                captionOnFocus: true
                icon: "waves"
                visible: root.blurOn

                ScrubValue {
                    id: blSizeScrub
                    s: root.s
                    value: root.blurSize
                    openValue: root.base.blurSize
                    from: 1; to: 20; step: 1; unit: "px"
                    onEdited: v => {
                        root.blurSize = v;
                        root.setStore.set("blurSize", v);
                    }
                }
            }

            SettingsRow {
                id: blPassRow
                surface: root
                name: "Passes"
                sub: "More passes, smoother blur"
                captionOnFocus: true
                icon: "reboot"
                visible: root.blurOn
                last: true

                ScrubValue {
                    id: blPassScrub
                    s: root.s
                    value: root.blurPasses
                    openValue: root.base.blurPasses
                    from: 1; to: 5; step: 1
                    onEdited: v => {
                        root.blurPasses = v;
                        root.setStore.set("blurPasses", v);
                    }
                }
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
