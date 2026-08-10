pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../../colors"
import "../../services"            // Motion (and the rest) unqualified
import "../../services" as Services // Notifications singleton — see below
import "../../config"

/**
 * astralis — notification-center surface (ported from the inbox section of
 * Gakuseei/Ricelin pill/Link.qml). "報 NOTIFICATIONS" header, an unread ember
 * badge + clear-all row, then the grouped/coalesced backlog from
 * Services.Notifications.groups: newest-first app groups, criticals pinned
 * above each group head, per-app expand + clear, per-entry activate/dismiss.
 * Opening the surface marks everything seen (clears the hover-row inbox dot).
 *
 * The services import is aliased: this file's own type is `Notifications`
 * (pill/surfaces qmldir), so the singleton must be reached as
 * `Services.Notifications` to dodge the name collision.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 17
    mRight: 17
    mBottom: 14

    ameForm: "dock"
    amePoint: Qt.point(width / 2, height - 6 * s)

    // Opening the center counts as reading: after a beat, mark all seen.
    onOpenChanged: open ? seenTimer.restart() : seenTimer.stop()

    Timer {
        id: seenTimer
        interval: 600
        onTriggered: Services.Notifications.markSeen()
    }

    /**
     * Keyed view over the app groups: Services.Notifications.groups hands back a
     * freshly-built array on every notification, which a plain Repeater model
     * would treat as a wholesale replacement — tearing down and rebuilding every
     * group delegate (losing hover, expansion and in-flight animations) on each
     * arrival. Diffing by the stable `app` key keeps unchanged group delegates
     * alive and only touches the rows that actually changed.
     */
    ScriptModel {
        id: groupModel
        objectProp: "app"
        values: Services.Notifications.groups
    }

    /** Ember mark: the unread dot over a soft halo (header badge). */
    component Ember: Item {
        id: ember
        property real size: 4 * root.s

        width: size * 2.2
        height: size * 2.2

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: Colors.primary
            opacity: 0.22
        }

        Rectangle {
            anchors.centerIn: parent
            width: ember.size
            height: ember.size
            radius: width / 2
            color: Colors.primary
        }
    }

    /**
     * Single entry row: icon tile (or accent diamond), body text, ×N coalesce
     * badge, age label that cross-fades into a dismiss glyph on hover.
     * Critical entries gain an error left hairline and full-contrast text.
     */
    component NotifRow: Rectangle {
        id: nrow

        required property var entry
        property bool critical: false
        readonly property var n: entry.n

        width: parent ? parent.width : 0
        height: 26 * root.s
        radius: 7 * root.s
        color: nrowHover.hovered ? Colors.surface_container_highest : "transparent"

        Behavior on color { ColorAnimation { duration: Motion.fast } }

        HoverHandler {
            id: nrowHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Services.Notifications.activateEntry(nrow.entry);
                root.requestClose();
            }
        }

        Rectangle {
            visible: nrow.critical
            anchors.left: parent.left
            anchors.leftMargin: 1 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 2 * root.s
            height: parent.height - 10 * root.s
            radius: Appearance.rounding.full
            color: Colors.error
        }

        Rectangle {
            id: nrowTile
            anchors.left: parent.left
            anchors.leftMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * root.s
            height: 16 * root.s
            radius: 5 * root.s
            color: Colors.surface_container_high
            border.width: 1
            border.color: Qt.alpha(Colors.outline_variant, 0.6)

            Image {
                id: nrowImg
                anchors.fill: parent
                anchors.margins: nrow.n.image ? 0 : 2 * root.s
                source: Services.Notifications.iconFor(nrow.n)
                sourceSize.width: 40
                sourceSize.height: 40
                fillMode: Image.PreserveAspectCrop
                smooth: true
                visible: status === Image.Ready
            }

            Rectangle {
                anchors.centerIn: parent
                visible: !nrowImg.visible
                width: 5 * root.s
                height: 5 * root.s
                radius: 1.5 * root.s
                rotation: 45
                color: nrow.critical ? Colors.error : Colors.primary
            }
        }

        Text {
            anchors.left: nrowTile.right
            anchors.leftMargin: 8 * root.s
            anchors.right: nrowRight.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: nrow.n.body.length > 0 ? nrow.n.body : nrow.n.summary
            color: nrow.critical ? Colors.on_surface : Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 10.5 * root.s
            font.weight: nrow.critical ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
            textFormat: Text.PlainText
        }

        Row {
            id: nrowRight
            anchors.right: parent.right
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s

            Text {
                visible: nrow.entry.count > 1
                anchors.verticalCenter: parent.verticalCenter
                text: "×" + nrow.entry.count
                color: nrow.critical ? Colors.error : Qt.alpha(Colors.error, 0.75)
                font.family: Appearance.font.family
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(nrowAge.implicitWidth, nrowX.implicitWidth)
                height: Math.max(nrowAge.implicitHeight, nrowX.implicitHeight)

                Text {
                    id: nrowAge
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: nrowHover.hovered ? 0 : 1
                    text: Services.Notifications.ageLabel(nrow.n)
                    color: Qt.alpha(Colors.on_surface_variant, 0.6)
                    font.family: Appearance.font.family
                    font.pixelSize: 9 * root.s
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                GlyphIcon {
                    id: nrowX
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11 * root.s
                    height: 11 * root.s
                    opacity: nrowHover.hovered ? 1 : 0
                    name: "close"
                    color: nrowXArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                    stroke: 1.9
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    MouseArea {
                        id: nrowXArea
                        anchors.fill: parent
                        anchors.margins: -6 * root.s
                        enabled: nrowHover.hovered
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Notifications.dismissEntry(nrow.entry)
                    }
                }
            }
        }
    }

    SettingsHeader {
        id: header
        anchors.top: parent.top
        s: root.s
        glyph: "報"
        title: "NOTIFICATIONS"
        onBack: root.requestClose()
    }

    // ── tool row: unread badge left, clear-all right ────────────────────────
    Item {
        id: toolRow
        anchors.top: header.bottom
        anchors.topMargin: 10 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 18 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s
            visible: Services.Notifications.unread > 0

            Ember {
                id: headerEmber
                anchors.verticalCenter: parent.verticalCenter
                size: 5 * root.s

                SequentialAnimation on opacity {
                    running: headerEmber.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.55; duration: Motion.pulse; easing.type: Motion.easeStandard }
                    NumberAnimation { to: 1;    duration: Motion.pulse; easing.type: Motion.easeStandard }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Services.Notifications.unread + " NEW"
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
                font.letterSpacing: 1.4 * root.s
            }
        }

        Row {
            id: clearRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: Services.Notifications.count > 0
            spacing: 4 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "払"
                color: clearArea.containsMouse ? Colors.error : Qt.alpha(Colors.error, 0.75)
                font.family: Appearance.font.jp
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "CLEAR ALL"
                color: clearArea.containsMouse ? Colors.error : Qt.alpha(Colors.error, 0.75)
                font.family: Appearance.font.family
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
                font.letterSpacing: 1.4 * root.s
            }
        }

        MouseArea {
            id: clearArea
            anchors.fill: clearRow
            anchors.margins: -5 * root.s
            visible: Services.Notifications.count > 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Services.Notifications.clearAll()
        }
    }

    Rectangle {
        id: hairline
        anchors.top: toolRow.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.alpha(Colors.on_surface, 0.06)
    }

    // ── grouped backlog ─────────────────────────────────────────────────────
    Flickable {
        id: notifFlick
        anchors.top: hairline.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: notifCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: returnToBounds()

        Column {
            id: notifCol
            width: notifFlick.width
            spacing: 6 * root.s

            Repeater {
                model: groupModel

                Column {
                    id: group
                    required property var modelData
                    readonly property bool expanded: Services.Notifications.expandedApps[modelData.app] === true
                    width: notifCol.width
                    spacing: 2 * root.s

                    // Criticals surface above the group head, always visible.
                    Repeater {
                        model: group.modelData.criticals

                        NotifRow {
                            required property var modelData
                            entry: modelData
                            critical: true
                        }
                    }

                    Rectangle {
                        id: groupHead
                        width: parent.width
                        height: 32 * root.s
                        radius: 8 * root.s
                        color: headHover.hovered ? Colors.surface_container_highest : "transparent"

                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        HoverHandler {
                            id: headHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Notifications.toggleExpanded(group.modelData.app)
                        }

                        Rectangle {
                            id: headTile
                            anchors.left: parent.left
                            anchors.leftMargin: 6 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20 * root.s
                            height: 20 * root.s
                            radius: 6 * root.s
                            color: Colors.surface_container_high
                            border.width: 1
                            border.color: Qt.alpha(Colors.outline_variant, 0.6)

                            Image {
                                id: headImg
                                anchors.fill: parent
                                anchors.margins: group.modelData.newest.image ? 0 : 3 * root.s
                                source: Services.Notifications.iconFor(group.modelData.newest)
                                sourceSize.width: 40
                                sourceSize.height: 40
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                visible: status === Image.Ready
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                visible: !headImg.visible
                                width: 6 * root.s
                                height: 6 * root.s
                                radius: 2 * root.s
                                rotation: 45
                                color: Colors.primary
                            }
                        }

                        Text {
                            id: headName
                            anchors.left: headTile.right
                            anchors.leftMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 110 * root.s)
                            text: group.modelData.app
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2 * root.s
                            elide: Text.ElideRight
                        }

                        Text {
                            id: headCount
                            anchors.left: headName.right
                            anchors.leftMargin: 5 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            text: "· " + group.modelData.count
                            color: Qt.alpha(Colors.on_surface_variant, 0.6)
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * root.s
                        }

                        Text {
                            anchors.left: headCount.right
                            anchors.leftMargin: 8 * root.s
                            anchors.right: headX.left
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            text: group.modelData.preview.body.length > 0
                                ? group.modelData.preview.body
                                : group.modelData.preview.summary
                            color: Qt.alpha(Colors.on_surface_variant, 0.8)
                            font.family: Appearance.font.family
                            font.pixelSize: 10 * root.s
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                        }

                        GlyphIcon {
                            id: headChev
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 11 * root.s
                            height: 11 * root.s
                            name: group.expanded ? "chevron-down" : "chevron-right"
                            color: Qt.alpha(Colors.on_surface_variant, 0.6)
                            stroke: 2
                        }

                        GlyphIcon {
                            id: headX
                            anchors.right: headChev.left
                            anchors.rightMargin: 7 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 11 * root.s
                            height: 11 * root.s
                            opacity: headHover.hovered ? 1 : 0
                            name: "close"
                            color: headXArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                            stroke: 1.9
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                            MouseArea {
                                id: headXArea
                                anchors.fill: parent
                                anchors.margins: -6 * root.s
                                enabled: headHover.hovered
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Notifications.dismissApp(group.modelData.app)
                            }
                        }
                    }

                    Column {
                        visible: group.expanded
                        width: parent.width
                        spacing: 2 * root.s

                        Repeater {
                            model: group.expanded ? group.modelData.entries : []

                            NotifRow {
                                required property var modelData
                                entry: modelData
                            }
                        }
                    }
                }
            }
        }
    }

    // ── empty state ─────────────────────────────────────────────────────────
    Column {
        anchors.centerIn: notifFlick
        visible: Services.Notifications.count === 0
        spacing: 4 * root.s

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Flags.showGlyphs
            text: "静"
            color: Colors.on_surface_variant
            opacity: 0.45
            font.family: Appearance.font.jp
            font.weight: Font.Medium
            font.pixelSize: 32 * root.s
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "SILENCE"
            color: Qt.alpha(Colors.on_surface_variant, 0.6)
            font.family: Appearance.font.family
            font.pixelSize: 9 * root.s
            font.weight: Font.Bold
            font.letterSpacing: 2.2 * root.s
        }
    }
}
