pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"
import "../../services" as Services
import "../../config"

/**
 * astralis — 操 INPUT settings page (ported from Ricelin pill/Input.qml): the
 * pointer knobs (sensitivity, acceleration profile), the keyboard block
 * (layout cycled through a curated list, repeat rate and delay) and — astralis
 * delta — a touchpad group (natural scroll, tap to click, disable while
 * typing) in place of Ricelin's cursor-theme block (cursor size/theme edit
 * env.lua + `hyprctl setcursor`, a separate follow-up on astralis's Lua
 * config).
 *
 * Ricelin delta: where Ricelin regex-edits input.lua and reloads Hyprland,
 * every row reads and writes the Services.Settings store — the singleton
 * persists settings.json, live-applies the `input:*` / `input:touchpad:*`
 * keywords (debounced) and regenerates the reload overlay.
 */
SettingsPage {
    id: root

    contentY: flick.contentY

    /**
     * Row registry; scrub rows expose a bump that steps their ScrubValue one
     * increment. The layout row's vals gain the current layout at the end when
     * it is not in the curated list, so an exotic layout shows as-is and a
     * click wraps around to the start of the list.
     */
    rows: [
        { item: sensRow, kind: "scrub", bump: function (d) { sensScrub.bump(d); } },
        { item: accelRow, kind: "seg", vals: ["flat", "adaptive"], get: function () { return root.accelProfile; }, set: function (v) { root.accelProfile = v; root.setStore.set("accelProfile", v); } },
        { item: layoutRow, kind: "seg", vals: root.kbLayoutVals, get: function () { return root.kbLayout; }, set: function (v) { root.setKbLayout(v); } },
        { item: rateRow, kind: "scrub", bump: function (d) { rateScrub.bump(d); } },
        { item: delayRow, kind: "scrub", bump: function (d) { delayScrub.bump(d); } },
        { item: natScrollRow, kind: "toggle", get: function () { return root.natScroll; }, set: function (v) { root.natScroll = v; root.setStore.set("touchNaturalScroll", v); } },
        { item: tapRow, kind: "toggle", get: function () { return root.tapClick; }, set: function (v) { root.tapClick = v; root.setStore.set("touchTapToClick", v); } },
        { item: dwtRow, kind: "toggle", get: function () { return root.dwt; }, set: function (v) { root.dwt = v; root.setStore.set("touchDwt", v); } }
    ]

    property real sensitivity: 0
    property string accelProfile: "adaptive"
    property string kbLayout: "us"
    property int repeatRate: 25
    property int repeatDelay: 600
    property bool natScroll: true
    property bool tapClick: true
    property bool dwt: true

    property bool loaded: false

    /** Per-field values captured on the first seed; the ScrubValue undo glyphs revert to these. */
    property var base: ({})

    // The singleton, hoisted once (`Settings` unqualified would shadow-clash
    // with the surface type of the same name in importing contexts).
    readonly property var setStore: Services.Settings

    readonly property var accelOptions: [
        { label: "Flat", value: "flat" },
        { label: "Adaptive", value: "adaptive" }
    ]

    readonly property var kbLayouts: ["us", "de", "gb", "fr", "es", "it", "tr"]
    readonly property var kbLayoutVals: kbLayouts.indexOf(kbLayout) >= 0 ? kbLayouts : kbLayouts.concat([kbLayout])

    onActiveChanged: if (active && !root.loaded) root.seed()

    /**
     * Seeds every control from the Settings store once per pill session
     * (touched keys from settings.json, untouched keys from the defaults
     * table that mirrors hypr.d/input.lua), then snapshots the scrub revert
     * baseline.
     */
    function seed() {
        var sv = Number(root.setStore.get("sensitivity"));
        root.sensitivity = isNaN(sv) ? 0 : sv;
        root.accelProfile = String(root.setStore.get("accelProfile"));
        root.kbLayout = String(root.setStore.get("kbLayout"));
        var rr = Number(root.setStore.get("repeatRate"));
        root.repeatRate = isNaN(rr) ? 25 : rr;
        var rd = Number(root.setStore.get("repeatDelay"));
        root.repeatDelay = isNaN(rd) ? 600 : rd;
        root.natScroll = root.setStore.get("touchNaturalScroll") === true;
        root.tapClick = root.setStore.get("touchTapToClick") === true;
        root.dwt = root.setStore.get("touchDwt") === true;
        root.base = {
            sensitivity: root.sensitivity,
            repeatRate: root.repeatRate,
            repeatDelay: root.repeatDelay
        };
        root.loaded = true;
    }

    function setKbLayout(v) {
        root.kbLayout = v;
        root.setStore.set("kbLayout", v);
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "操"
        title: "INPUT"
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

            SettingsGroupLabel { s: root.s; text: "Pointer" }

            SettingsRow {
                id: sensRow
                surface: root
                name: "Sensitivity"
                sub: "Pointer speed offset"
                captionOnFocus: true
                icon: "mouse"

                ScrubValue {
                    id: sensScrub
                    s: root.s
                    value: root.sensitivity
                    openValue: root.base.sensitivity
                    from: -1; to: 1; step: 0.1; decimals: 1
                    onEdited: v => {
                        root.sensitivity = v;
                        root.setStore.set("sensitivity", v);
                    }
                }
            }

            SettingsRow {
                id: accelRow
                surface: root
                name: "Acceleration"
                sub: "How pointer speed follows motion"
                captionOnFocus: true
                icon: "bolt"
                last: true

                SettingsSeg {
                    s: root.s
                    options: root.accelOptions
                    value: root.accelProfile
                    onPicked: (v) => {
                        root.accelProfile = v;
                        root.setStore.set("accelProfile", v);
                    }
                }
            }

            SettingsGroupLabel { s: root.s; text: "Keyboard" }

            SettingsRow {
                id: layoutRow
                surface: root
                name: "Layout"
                sub: "Click to cycle common layouts"
                captionOnFocus: true
                icon: "language"

                Rectangle {
                    width: layoutLbl.implicitWidth + 20 * root.s
                    height: 22 * root.s
                    radius: 9 * root.s
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Colors.on_surface, 0.06)

                    Text {
                        id: layoutLbl
                        anchors.centerIn: parent
                        text: root.kbLayout
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                    }
                }
            }

            SettingsRow {
                id: rateRow
                surface: root
                name: "Repeat rate"
                sub: "Key repeats per second when held"
                captionOnFocus: true
                icon: "keyboard"

                ScrubValue {
                    id: rateScrub
                    s: root.s
                    value: root.repeatRate
                    openValue: root.base.repeatRate
                    from: 10; to: 80; step: 1; unit: "Hz"
                    onEdited: v => {
                        root.repeatRate = v;
                        root.setStore.set("repeatRate", v);
                    }
                }
            }

            SettingsRow {
                id: delayRow
                surface: root
                name: "Repeat delay"
                sub: "Hold time before a key repeats"
                captionOnFocus: true
                icon: "stopwatch"
                last: true

                ScrubValue {
                    id: delayScrub
                    s: root.s
                    value: root.repeatDelay
                    openValue: root.base.repeatDelay
                    from: 150; to: 1000; step: 25; unit: "ms"
                    onEdited: v => {
                        root.repeatDelay = v;
                        root.setStore.set("repeatDelay", v);
                    }
                }
            }

            SettingsGroupLabel { s: root.s; text: "Touchpad" }

            SettingsRow {
                id: natScrollRow
                surface: root
                name: "Natural scroll"
                sub: "Content follows the fingers"
                captionOnFocus: true
                icon: "waves"

                LinkToggle {
                    s: root.s
                    on: root.natScroll
                    onToggled: {
                        root.natScroll = !root.natScroll;
                        root.setStore.set("touchNaturalScroll", root.natScroll);
                    }
                }
            }

            SettingsRow {
                id: tapRow
                surface: root
                name: "Tap to click"
                sub: "A light tap counts as a click"
                captionOnFocus: true
                icon: "cursor"

                LinkToggle {
                    s: root.s
                    on: root.tapClick
                    onToggled: {
                        root.tapClick = !root.tapClick;
                        root.setStore.set("touchTapToClick", root.tapClick);
                    }
                }
            }

            SettingsRow {
                id: dwtRow
                surface: root
                name: "Disable while typing"
                sub: "Ignore the touchpad while keys are down"
                captionOnFocus: true
                icon: "keyboard"
                last: true

                LinkToggle {
                    s: root.s
                    on: root.dwt
                    onToggled: {
                        root.dwt = !root.dwt;
                        root.setStore.set("touchDwt", root.dwt);
                    }
                }
            }

            Item { width: 1; height: 10 * root.s }
        }
    }
}
