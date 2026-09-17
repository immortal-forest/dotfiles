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
     * badge, age label that cross-fades into a dismiss glyph on hover, and —
     * when the notification actually shipped any — a row of real action
     * pills underneath (View, Reply, whatever the sender named them).
     *
     * Was a single 26·s line with no actions surfaced at all: the panel
     * itself is a full 460·s surface, and a two-row backlog of 26px lines
     * read as mostly empty chrome around a couple of hairline-thin strips.
     * 44·s plus a conditional action row gives each entry real visual
     * weight, and the actions are the same `n.actions` Toast.qml already
     * renders for the popup — they just vanished once a notification moved
     * into the backlog, with only a whole-row click (`activate()`, which
     * silently no-opped for anything without a literal "default" action —
     * see Notifications.qml service) standing in for them.
     *
     * Critical entries gain an error left hairline and full-contrast text.
     */
    component NotifRow: Rectangle {
        id: nrow

        required property var entry
        property bool critical: false
        readonly property var n: entry.n
        readonly property var acts: (n.actions || []).filter(function (a) {
            return a && a.text && a.text.length > 0;
        })

        width: parent ? parent.width : 0
        height: mainRow.height + 10 * root.s
            + (nrow.acts.length > 0 ? 6 * root.s + actRow.height : 0)
        radius: 9 * root.s
        color: nrowHover.hovered ? Colors.surface_container_highest : "transparent"

        // Summary as the name, body as the description — the same split the
        // row's own text draws (body falls back to summary when there is none).
        Accessible.role: Accessible.Notification
        Accessible.name: nrow.n.summary
        Accessible.description: nrow.n.body
        Accessible.focusable: true
        Accessible.onPressAction: nrow.activate()

        /** Shared by the click and the accessible press action so they can't drift. */
        function activate() {
            Services.Notifications.activateEntry(nrow.entry);
            root.requestClose();
        }

        Behavior on color { ColorAnimation { duration: Motion.fast } }

        // Wide row: the shallow "very wide full-width rows" dip, same depth
        // as a settings row or a notification body.
        scale: nrowArea.pressed ? 0.98 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        HoverHandler {
            id: nrowHover
        }

        MouseArea {
            id: nrowArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: nrow.activate()
        }

        Rectangle {
            visible: nrow.critical
            anchors.left: parent.left
            anchors.leftMargin: 1 * root.s
            anchors.top: parent.top
            anchors.topMargin: 5 * root.s
            width: 2 * root.s
            height: mainRow.height
            radius: Appearance.rounding.full
            color: Colors.error
        }

        Row {
            id: mainRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8 * root.s
            spacing: 10 * root.s

            Rectangle {
                id: nrowTile
                anchors.verticalCenter: parent.verticalCenter
                width: 24 * root.s
                height: 24 * root.s
                radius: 7 * root.s
                color: Colors.surface_container_high
                border.width: 1
                border.color: Qt.alpha(Colors.outline_variant, 0.6)

                Image {
                    id: nrowImg
                    anchors.fill: parent
                    anchors.margins: nrow.n.image ? 0 : 3 * root.s
                    source: Services.Notifications.iconFor(nrow.n)
                    sourceSize.width: 48
                    sourceSize.height: 48
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    visible: status === Image.Ready
                }

                Rectangle {
                    anchors.centerIn: parent
                    visible: !nrowImg.visible
                    width: 6 * root.s
                    height: 6 * root.s
                    radius: 2 * root.s
                    rotation: 45
                    color: nrow.critical ? Colors.error : Colors.primary
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - nrowTile.width - nrowRight.width - 2 * parent.spacing
                text: nrow.n.body.length > 0 ? nrow.n.body : nrow.n.summary
                color: nrow.critical ? Colors.on_surface : Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 11.5 * root.s
                font.weight: nrow.critical ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
                maximumLineCount: 1
                textFormat: Text.PlainText
            }

            Row {
                id: nrowRight
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
                        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                    }

                    GlyphIcon {
                        id: nrowX
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        // 13·s, not 11 — below that a stroked glyph's line
                        // can't rasterize thin enough to stay crisp; see
                        // Toast.qml's dismiss icon for the full note.
                        width: 13 * root.s
                        height: 13 * root.s
                        opacity: nrowHover.hovered ? 1 : 0
                        name: "close"
                        color: nrowXArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                        stroke: 1.9
                        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        // Small round target: the shell's deep dip.
                        scale: nrowXArea.pressed ? 0.92 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        // Names WHICH notification this dismisses — a bare "Dismiss"
                        // is meaningless once a screen reader has tabbed past ten of them.
                        Accessible.role: Accessible.Button
                        Accessible.name: "Dismiss " + nrow.n.summary
                        Accessible.focusable: true
                        Accessible.onPressAction: Services.Notifications.dismissEntry(nrow.entry)

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

        // Real per-notification actions — "View", "Reply", whatever the
        // sender named them (n.actions, the same source Toast.qml's popup
        // pills already read). These used to only exist while a notification
        // was still a toast; once it landed here the ONLY way to trigger one
        // was clicking the whole row, which only ever ran an action literally
        // identified "default" — most senders (hyprshot's "View" included)
        // don't ship one, so the row silently did nothing. Explicit pills
        // fix both: the action is visible, and it invokes the SPECIFIC
        // action pressed rather than guessing at the row's intent.
        Row {
            id: actRow
            visible: nrow.acts.length > 0
            anchors.left: mainRow.left
            anchors.leftMargin: nrowTile.width + mainRow.spacing
            anchors.top: mainRow.bottom
            anchors.topMargin: 6 * root.s
            spacing: 6 * root.s

            Repeater {
                model: nrow.acts

                Rectangle {
                    id: actPill
                    required property var modelData
                    required property int index

                    height: 20 * root.s
                    width: actText.implicitWidth + 18 * root.s
                    radius: Appearance.rounding.full
                    color: actPill.index === 0 ? Qt.alpha(Colors.primary, 0.14) : Colors.surface_container_high
                    border.width: 1
                    border.color: actPill.index === 0 ? Qt.alpha(Colors.primary, 0.5) : Qt.alpha(Colors.outline_variant, 0.6)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    scale: actArea.pressed ? 0.92 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: actPill.modelData.text
                    Accessible.focusable: true
                    Accessible.onPressAction: actArea.clicked(null)

                    Text {
                        id: actText
                        anchors.centerIn: parent
                        text: actPill.modelData.text
                        color: actPill.index === 0 ? Colors.primary : Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: actArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            actPill.modelData.invoke();
                            root.requestClose();
                        }
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
            id: unreadRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s
            // Arrivals and the clear-all both land while the surface is open,
            // so the badge dissolves rather than blinking out from under the
            // cursor. Gated on opacity, never on a measured size (core §5).
            readonly property bool shown: Services.Notifications.unread > 0
            opacity: shown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }

            Ember {
                id: headerEmber
                anchors.verticalCenter: parent.verticalCenter
                size: 5 * root.s

                // A closed surface has nothing to breathe at: the loop used to
                // run forever behind a hidden panel.
                SequentialAnimation on opacity {
                    running: unreadRow.shown && root.open && !Motion.reduceMotion
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
            spacing: 4 * root.s

            // Clearing is the click that empties this surface, so the control
            // that did it fades out with the list instead of vanishing on the
            // same frame.
            opacity: Services.Notifications.count > 0 ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
            }

            // Small text-button target: the shell's deep dip.
            scale: clearArea.pressed ? 0.92 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            Accessible.role: Accessible.Button
            Accessible.name: "Clear all notifications"
            Accessible.focusable: true
            Accessible.onPressAction: Services.Notifications.clearAll()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "払"
                color: clearArea.containsMouse ? Colors.error : Qt.alpha(Colors.error, 0.75)
                font.family: Appearance.font.jp
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "CLEAR ALL"
                color: clearArea.containsMouse ? Colors.error : Qt.alpha(Colors.error, 0.75)
                font.family: Appearance.font.family
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
                font.letterSpacing: 1.4 * root.s
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        MouseArea {
            id: clearArea
            anchors.fill: clearRow
            anchors.margins: -5 * root.s
            // `enabled`, not `visible`: the row underneath is mid-fade and must
            // not keep taking clicks, but hiding the area would also drop the
            // hover tint the fade is still painting.
            enabled: Services.Notifications.count > 0
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
                        // Matched to NotifRow's new weight (see its own doc)
                        // rather than left thin beside it — a collapsed group
                        // head sits directly above its own expanded rows in
                        // the same list and reads as one rhythm, not two.
                        height: 40 * root.s
                        radius: 9 * root.s
                        color: headHover.hovered ? Colors.surface_container_highest : "transparent"

                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        // Same full-width-row depth as a NotifRow — this header sits
                        // directly above one in the same list.
                        scale: headArea.pressed ? 0.98 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        Accessible.role: Accessible.Button
                        Accessible.name: group.modelData.app + ", " + group.modelData.count
                            + (group.modelData.count === 1 ? " notification" : " notifications")
                        Accessible.description: group.expanded ? "Expanded" : "Collapsed"
                        Accessible.focusable: true
                        Accessible.onPressAction: Services.Notifications.toggleExpanded(group.modelData.app)

                        HoverHandler {
                            id: headHover
                        }

                        MouseArea {
                            id: headArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Notifications.toggleExpanded(group.modelData.app)
                        }

                        Rectangle {
                            id: headTile
                            anchors.left: parent.left
                            anchors.leftMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24 * root.s
                            height: 24 * root.s
                            radius: 7 * root.s
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
                            font.pixelSize: 9.5 * root.s
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
                            font.pixelSize: 9.5 * root.s
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
                            font.pixelSize: 10.5 * root.s
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            textFormat: Text.PlainText
                        }

                        GlyphIcon {
                            id: headChev
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            // 13·s — see Toast.qml's dismiss icon note.
                            width: 13 * root.s
                            height: 13 * root.s
                            // One glyph that turns rather than two that
                            // swap: the rotation IS the expand, so the
                            // affordance animates on the state change instead
                            // of blinking between two pictograms.
                            name: "chevron-right"
                            rotation: group.expanded ? 90 : 0
                            color: Qt.alpha(Colors.on_surface_variant, 0.6)
                            stroke: 2
                            Behavior on rotation {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }
                        }

                        GlyphIcon {
                            id: headX
                            anchors.right: headChev.left
                            anchors.rightMargin: 7 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            // 13·s — see Toast.qml's dismiss icon note.
                            width: 13 * root.s
                            height: 13 * root.s
                            opacity: headHover.hovered ? 1 : 0
                            name: "close"
                            color: headXArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                            stroke: 1.9
                            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            // Small round target: the shell's deep dip.
                            scale: headXArea.pressed ? 0.92 : 1
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }

                            Accessible.role: Accessible.Button
                            Accessible.name: "Dismiss all from " + group.modelData.app
                            Accessible.focusable: true
                            Accessible.onPressAction: Services.Notifications.dismissApp(group.modelData.app)

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
        // Cross-fades with the backlog rather than snapping in: clearing the
        // last notification is a click the user made, and this is what answers
        // it. Same handoff as the 静 block on the 繋 LINK surface.
        anchors.centerIn: notifFlick
        opacity: Services.Notifications.count === 0 ? 1 : 0
        visible: opacity > 0.01
        spacing: 4 * root.s
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

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
