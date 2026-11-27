pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import ".."
import "../m3"
import "../../colors"
import "../../services"
import "../../config"

/**
 * 窓 WINDOWS — the Alt+Tab switcher, grown out of the pill.
 *
 * State lives in services/Switcher.qml (Hyprland binds → GlobalShortcuts in
 * shell.qml); this is only the view: the windows in most-recently-used order
 * as app tiles, the chosen one in a primary tint (the selection colour; a
 * solid fill would bury the icon, §2b-v) with the bead gliding underneath it,
 * its title below.
 * Release Alt to switch; Esc cancels, Enter or a click switches, the arrow
 * keys step too.
 */
PillSurface {
    id: root

    readonly property int count: Switcher.windows.length
    /** Tiles across before the row scrolls. */
    readonly property int tiles: Math.max(4, Math.min(8, root.count))
    readonly property real tileSize: 54 * s
    readonly property real tileGap: 8 * s
    readonly property real contentW: root.tiles * (root.tileSize + root.tileGap) - root.tileGap
    desiredH: column.implicitHeight

    ameForm: open && root.count > 0 ? "dock" : "off"
    amePoint: {
        void list.contentX;
        void Switcher.index;
        void root.width;
        const it = list.currentItem;
        if (!it)
            return Qt.point(width / 2, height - 6 * s);
        const p = it.mapToItem(root, it.width / 2, it.height);
        return Qt.point(p.x, p.y + 11 * s);
    }

    function appIcon(cls) {
        if (!cls)
            return "";
        const e = DesktopEntries.heuristicLookup(cls);
        const p = String((e && e.icon ? Quickshell.iconPath(e.icon, true) : "") || "");
        return p.length ? p : String(Quickshell.iconPath(String(cls).toLowerCase(), true) || "");
    }

    function appName(cls) {
        const e = cls ? DesktopEntries.heuristicLookup(cls) : null;
        return e && e.name ? e.name : String(cls || "");
    }

    onOpenChanged: {
        if (open)
            Qt.callLater(() => keys.forceActiveFocus());
        else if (Switcher.active)
            Switcher.cancel();   // closed some other way (a click outside, another surface)
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Switcher.cancel()
        Keys.onReturnPressed: Switcher.commit()
        Keys.onEnterPressed: Switcher.commit()
        Keys.onLeftPressed: Switcher.prev()
        Keys.onRightPressed: Switcher.next()
    }

    Column {
        id: column
        width: parent.width
        spacing: 0

        // ── header: 窓 WINDOWS · n open ──────────────────────────────────
        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "窓"
                    color: Colors.on_surface
                    font.family: Appearance.font.jp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "WINDOWS"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.6 * root.s
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.count + " open"
                color: Qt.alpha(Colors.on_surface_variant, 0.8)
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
                font.features: ({ "tnum": 1 })
            }
        }

        Item { width: 1; height: 12 * root.s }

        // ── the tiles ───────────────────────────────────────────────────
        ListView {
            id: list
            width: Math.min(parent.width, root.contentW)
            anchors.horizontalCenter: parent.horizontalCenter
            height: root.tileSize
            orientation: ListView.Horizontal
            spacing: root.tileGap
            interactive: false
            clip: true
            model: Switcher.windows
            currentIndex: Switcher.index
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index
                readonly property bool sel: tile.index === Switcher.index

                width: root.tileSize
                height: root.tileSize
                radius: 16 * root.s
                color: tile.sel ? Qt.alpha(Colors.primary, 0.22)
                    : (tileHover.hovered ? Qt.alpha(Colors.on_surface, 0.08) : "transparent")
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                HoverHandler { id: tileHover }
                TapHandler { onTapped: Switcher.choose(tile.index) }

                IconImage {
                    id: icon
                    anchors.centerIn: parent
                    implicitSize: 34 * root.s
                    source: root.appIcon(tile.modelData.cls)
                    asynchronous: true
                    visible: status === Image.Ready
                    scale: tile.sel ? 1.06 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }
                }
                // No icon: the app's initial, in the tile.
                Text {
                    anchors.centerIn: parent
                    visible: icon.status !== Image.Ready
                    text: String(root.appName(tile.modelData.cls)).charAt(0).toUpperCase()
                    color: tile.sel ? Colors.primary : Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 20 * root.s
                    font.weight: Font.DemiBold
                }

                Accessible.role: Accessible.Button
                Accessible.name: root.appName(tile.modelData.cls) + ", " + tile.modelData.title
            }
        }

        // the bead docks in this gap, under the chosen tile
        Item { width: 1; height: 24 * root.s }

        // ── the chosen window ───────────────────────────────────────────
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Switcher.selected ? Switcher.selected.title : ""
            color: Colors.on_surface
            elide: Text.ElideRight
            font.family: Appearance.font.family
            font.pixelSize: 12.5 * root.s
            font.weight: Font.DemiBold
        }

        Item { width: 1; height: 3 * root.s }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Switcher.selected
                ? root.appName(Switcher.selected.cls) + "  ·  workspace " + Switcher.selected.ws : ""
            color: Qt.alpha(Colors.on_surface_variant, 0.85)
            elide: Text.ElideRight
            font.family: Appearance.font.family
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Medium
        }

        Item { width: 1; height: 6 * root.s }
    }
}
