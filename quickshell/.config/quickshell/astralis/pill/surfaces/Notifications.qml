pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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
    // The soul bead docks at the bottom centre: the list stops this far above
    // the edge so the bead never sits on the last row or its hover wash.
    readonly property real beadClear: 18 * s
    amePoint: Qt.point(width / 2, height - 6 * s)
    // Hug the backlog: header + rule + list (floored for the 静 empty state),
    // capped by Pill.qml's fixed 460.
    desiredH: hairline.y + 1 + 8 * s
        + Math.max(Services.Notifications.count === 0 ? 96 * s : 40 * s, notifCol.implicitHeight)
        + 12 * s + beadClear

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
     * One row geometry for everything in the list (entry rows and group
     * heads alike): 8·s inset, a 34·s lead (Toast.KindTile — or a screenshot
     * thumbnail in the same tile-size slot), two text lines, meta on the right.
     * Rows sit on the same full-width hover wash as before; criticals keep
     * that geometry and only add a faint error-container wash and an
     * error-coloured title.
     */
    readonly property real rowPad: 7 * s
    readonly property real tileSize: 34 * s

    /** Right-hand meta: age that cross-fades into a dismiss × on hover. */
    component AgeOrX: Item {
        id: aox
        property string age: ""
        property bool hovered: false
        property string what: ""
        signal dismissed()

        width: Math.max(aoxAge.implicitWidth, aoxX.width)
        height: Math.max(aoxAge.implicitHeight, aoxX.height)

        Text {
            id: aoxAge
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            opacity: aox.hovered ? 0 : 1
            text: aox.age
            color: Qt.alpha(Colors.on_surface_variant, 0.6)
            font.family: Appearance.font.family
            font.pixelSize: 9.5 * root.s
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }

        GlyphIcon {
            id: aoxX
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // 13·s, not 11 — below that a stroked glyph's line can't
            // rasterize thin enough to stay crisp (see Toast.qml's dismiss).
            width: 13 * root.s
            height: 13 * root.s
            opacity: aox.hovered ? 1 : 0
            name: "close"
            color: aoxArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
            stroke: 1.9
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            scale: aoxArea.pressed ? 0.92 : 1
            Behavior on scale {
                NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial }
            }

            Accessible.role: Accessible.Button
            Accessible.name: "Dismiss " + aox.what
            Accessible.focusable: true
            Accessible.onPressAction: aox.dismissed()

            MouseArea {
                id: aoxArea
                anchors.fill: parent
                anchors.margins: -6 * root.s
                enabled: aox.hovered
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: aox.dismissed()
            }
        }
    }

    /**
     * Entry row. `standalone` = the only item of its group, so there is no
     * group head above it: the second line then leads with the source
     * ("Firefox · disk full") instead of a head repeating the same item.
     */
    component NotifRow: Rectangle {
        id: nrow

        required property var entry
        property bool critical: false
        property bool standalone: false
        property string label: ""
        readonly property var n: entry.n
        readonly property string kind: Services.Notifications.kindOf(nrow.n)
        readonly property bool shot: nrow.kind === "screenshot"
        readonly property bool failed: Services.Notifications.isFailure(nrow.n)
        readonly property string caption: Services.Notifications.captionFor(nrow.n)
        readonly property string line2: nrow.standalone
            ? nrow.label + (nrow.caption.length ? "  ·  " + nrow.caption : "")
            : nrow.caption
        readonly property var acts: (n.actions || []).filter(function (a) {
            return a && a.text && a.text.length > 0;
        })
        readonly property bool hasActs: fileActs.shown || nrow.acts.length > 0

        width: parent ? parent.width : 0
        height: rowCol.implicitHeight + 2 * root.rowPad
        radius: 10 * root.s
        color: nrow.critical ? Qt.alpha(Colors.error_container, nrowHover.hovered ? 0.3 : 0.2)
            : nrowHover.hovered ? Colors.surface_container_highest : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Accessible.role: Accessible.Notification
        Accessible.name: Services.Notifications.titleFor(nrow.n)
        Accessible.description: nrow.line2
        Accessible.focusable: true
        Accessible.onPressAction: nrow.activate()

        /** Shared by the click and the accessible press action so they can't drift. */
        function activate() {
            Services.Notifications.activateEntry(nrow.entry);
            root.requestClose();
        }

        // Wide row: the shallow full-width dip.
        scale: nrowArea.pressed ? 0.98 : 1
        Behavior on scale {
            NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial }
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

        Column {
            id: rowCol
            x: 8 * root.s
            y: root.rowPad
            width: parent.width - 16 * root.s
            spacing: 6 * root.s

            Item {
                id: mainRow
                width: parent.width
                height: Math.max(root.tileSize, textCol.implicitHeight)

                Item {
                    id: lead
                    anchors.verticalCenter: parent.verticalCenter
                    // One lead column for every row, screenshots included, so all
                    // titles share a left edge (the popup keeps the big preview).
                    width: root.tileSize
                    height: root.tileSize

                    Toast.KindTile {
                        visible: !nrow.shot
                        n: nrow.n
                        s: root.s
                        size: root.tileSize
                    }

                    Toast.ShotThumb {
                        visible: nrow.shot
                        anchors.verticalCenter: parent.verticalCenter
                        s: root.s
                        path: nrow.shot ? Services.Notifications.fileOf(nrow.n) : ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        maxW: root.tileSize
                        maxH: root.tileSize
                        onActivated: {
                            Services.Notifications.openFile(Services.Notifications.fileOf(nrow.n));
                            root.requestClose();
                        }
                    }
                }

                Column {
                    id: textCol
                    anchors.left: lead.right
                    anchors.leftMargin: 10 * root.s
                    anchors.right: meta.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.s

                    Text {
                        width: parent.width
                        text: Services.Notifications.titleFor(nrow.n)
                        color: nrow.critical || nrow.failed ? Colors.error : Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                    }

                    Text {
                        width: parent.width
                        visible: nrow.line2.length > 0
                        text: nrow.line2
                        color: Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 11 * root.s
                        wrapMode: nrow.failed ? Text.Wrap : Text.NoWrap
                        maximumLineCount: nrow.failed ? 2 : 1
                        elide: nrow.shot ? Text.ElideMiddle : Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }

                Row {
                    id: meta
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s

                    Text {
                        visible: nrow.entry.count > 1
                        anchors.verticalCenter: parent.verticalCenter
                        text: "×" + nrow.entry.count
                        color: Qt.alpha(Colors.on_surface_variant, 0.75)
                        font.family: Appearance.font.family
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                    }

                    AgeOrX {
                        anchors.verticalCenter: parent.verticalCenter
                        age: Services.Notifications.ageLabel(nrow.n)
                        hovered: nrowHover.hovered
                        what: Services.Notifications.titleFor(nrow.n)
                        onDismissed: Services.Notifications.dismissEntry(nrow.entry)
                    }
                }
            }

            // Actions, aligned under the text: the shell's own file actions
            // first (screenshot / saved recording), then the sender's own
            // (n.actions — "View", "Reply"…), each invoking exactly the
            // action pressed.
            Column {
                visible: nrow.hasActs
                x: lead.width + 10 * root.s
                width: parent.width - x
                spacing: 6 * root.s

                Toast.FileActs {
                    id: fileActs
                    visible: fileActs.shown
                    width: parent.width
                    n: nrow.n
                    s: root.s
                    onOpened: root.requestClose()
                    onDeleted: Services.Notifications.dismissEntry(nrow.entry)
                }

                Flow {
                    visible: nrow.acts.length > 0
                    width: parent.width
                    spacing: 6 * root.s

                    Repeater {
                        model: nrow.acts

                        Toast.ActChip {
                            id: actPill
                            required property var modelData
                            required property int index

                            s: root.s
                            label: actPill.modelData.text
                            primary: actPill.index === 0 && !fileActs.shown
                            onTapped: {
                                actPill.modelData.invoke();
                                root.requestClose();
                            }
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
        anchors.topMargin: 12 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 30 * root.s // holds the 26s Clear chip

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
                    running: unreadRow.shown && root.settled && !Motion.reduceMotion
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

            Rectangle {
                height: 26 * root.s
                width: chipRowC.implicitWidth + 22 * root.s
                radius: height / 2
                color: Qt.alpha(Colors.error, clearArea.pressed ? 0.22 : clearArea.containsMouse ? 0.16 : 0.10)
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Row {
                    id: chipRowC
                    anchors.centerIn: parent
                    spacing: 6 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * root.s
                        height: 13 * root.s
                        name: "trash"
                        stroke: 1.8
                        color: Colors.error
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Clear all"
                        color: Colors.error
                        font.family: Appearance.font.family
                        font.pixelSize: 11 * root.s
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        MouseArea {
            id: clearArea
            anchors.fill: clearRow
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
        anchors.bottomMargin: root.beadClear
        contentHeight: notifCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: returnToBounds()

        // Overflow dissolves instead of cutting a row in half above the
        // docked bead: the list is drawn through an alpha ramp over its last
        // fadeH while there is more below (layer only while it overflows).
        readonly property real fadeH: 22 * root.s
        readonly property bool moreBelow: contentHeight - contentY - height > 1
        layer.enabled: contentHeight > height + 1
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: listFadeMask
            maskThresholdMin: 0
            maskSpreadAtMin: 1
        }

        Column {
            id: notifCol
            width: notifFlick.width
            spacing: 2 * root.s

            Repeater {
                model: groupModel

                Column {
                    id: group
                    required property var modelData
                    /** Criticals lead their own group; every item appears exactly once. */
                    readonly property var rows: modelData.criticals.concat(modelData.entries)
                    readonly property bool single: rows.length === 1
                    readonly property bool hasCrit: modelData.criticals.length > 0
                    readonly property bool expanded: !single && Services.Notifications.expandedApps[modelData.app] === true
                    width: notifCol.width
                    spacing: 0

                    /**
                     * Rows stay ALIVE through the collapse animation: the
                     * Repeater model only empties once the height has eased to
                     * 0 (see rowsClip). Set on expand, cleared on collapse end.
                     */
                    property bool rowsAlive: false
                    onExpandedChanged: if (expanded) rowsAlive = true
                    Component.onCompleted: rowsAlive = expanded

                    // A one-item group IS its item: no head repeating it.
                    NotifRow {
                        visible: group.single
                        entry: group.rows[0]
                        critical: group.hasCrit
                        standalone: true
                        label: group.modelData.app
                    }

                    Rectangle {
                        id: groupHead
                        visible: !group.single
                        width: parent.width
                        height: Math.max(root.tileSize, headText.implicitHeight) + 2 * root.rowPad
                        radius: 10 * root.s
                        color: headHover.hovered ? Colors.surface_container_highest : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        scale: headArea.pressed ? 0.98 : 1
                        Behavior on scale {
                            NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial }
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

                        // The group's identity: app icon / seal / glyph —
                        // never one item's content image.
                        Toast.KindTile {
                            id: headTile
                            x: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            n: group.modelData.newest
                            s: root.s
                            size: root.tileSize
                            avatar: false
                        }

                        Column {
                            id: headText
                            anchors.left: headTile.right
                            anchors.leftMargin: 10 * root.s
                            anchors.right: headMeta.left
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2 * root.s

                            Row {
                                width: parent.width
                                spacing: 6 * root.s

                                Text {
                                    id: headName
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, parent.width - headBadge.width - parent.spacing)
                                    text: group.modelData.app
                                    color: Colors.on_surface
                                    font.family: Appearance.font.family
                                    font.pixelSize: 12.5 * root.s
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                // Count badge; error-tinted while a critical
                                // sits inside the (collapsed) group.
                                Rectangle {
                                    id: headBadge
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 16 * root.s
                                    width: Math.max(height, headCount.implicitWidth + 10 * root.s)
                                    radius: height / 2
                                    color: group.hasCrit ? Qt.alpha(Colors.error_container, 0.6) : Colors.surface_container_highest

                                    Text {
                                        id: headCount
                                        anchors.centerIn: parent
                                        text: group.modelData.count
                                        color: group.hasCrit ? Colors.error : Colors.on_surface_variant
                                        font.family: Appearance.font.family
                                        font.pixelSize: 9.5 * root.s
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                readonly property var latest: group.rows[0].n
                                readonly property string cap: Services.Notifications.captionFor(latest)
                                text: Services.Notifications.titleFor(latest) + (cap.length ? "  ·  " + cap : "")
                                color: Colors.on_surface_variant
                                font.family: Appearance.font.family
                                font.pixelSize: 11 * root.s
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                            }
                        }

                        Row {
                            id: headMeta
                            anchors.right: parent.right
                            anchors.rightMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6 * root.s

                            AgeOrX {
                                anchors.verticalCenter: parent.verticalCenter
                                age: Services.Notifications.ageLabel(group.modelData.newest)
                                hovered: headHover.hovered
                                what: "all from " + group.modelData.app
                                onDismissed: Services.Notifications.dismissApp(group.modelData.app)
                            }

                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13 * root.s
                                height: 13 * root.s
                                // One glyph that turns: the rotation IS the expand.
                                name: "chevron-right"
                                rotation: group.expanded ? 90 : 0
                                color: Qt.alpha(Colors.on_surface_variant, 0.45)
                                stroke: 1.8
                                Behavior on rotation {
                                    NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial }
                                }
                            }
                        }
                    }

                    /**
                     * Row area: height eases (and the rows fade) on expand and
                     * collapse. Visibility rides rowsAlive, not the animated
                     * height, so the inner Column keeps computing its size.
                     */
                    Item {
                        id: rowsClip
                        width: parent.width
                        height: group.expanded ? rowsCol.implicitHeight : 0
                        opacity: group.expanded ? 1 : 0
                        visible: group.rowsAlive && !group.single
                        clip: true
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
                        }
                        Behavior on height {
                            NumberAnimation {
                                duration: Motion.standard
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.morphCurve
                                onRunningChanged: if (!running && !group.expanded) group.rowsAlive = false
                            }
                        }

                        Column {
                            id: rowsCol
                            width: parent.width
                            spacing: 2 * root.s
                            topPadding: 2 * root.s

                            Repeater {
                                model: group.rowsAlive && !group.single ? group.rows : []

                                NotifRow {
                                    required property var modelData
                                    required property int index
                                    entry: modelData
                                    critical: index < group.modelData.criticals.length
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Alpha ramp for the list's bottom dissolve (read by alpha only).
    Rectangle {
        id: listFadeMask
        width: notifFlick.width
        height: notifFlick.height
        visible: false
        layer.enabled: true
        readonly property real cut: notifFlick.moreBelow
            ? Math.max(0, 1 - notifFlick.fadeH / Math.max(1, notifFlick.height)) : 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1) }
            GradientStop { position: listFadeMask.cut; color: Qt.rgba(1, 1, 1, 1) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, notifFlick.moreBelow ? 0 : 1) }
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
