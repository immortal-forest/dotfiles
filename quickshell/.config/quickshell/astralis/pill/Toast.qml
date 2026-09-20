pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Notifications
import "../colors"
import "../services"
import "../config"

/**
 * astralis — toast content for the morphing pill body (ported from
 * Gakuseei/Ricelin pill/Toast.qml): icon tile, app eyebrow, summary with a
 * critical ember dot, optional body text and action pills, dismiss glyph on
 * the right. Draws no background of its own — the pill body behind it
 * provides the material. Clicking the body jumps to the source app; dismiss
 * and action pills consume their clicks. Auto-expires via the deadline
 * snapshot below unless the notification is critical (criticals persist).
 */
Item {
    id: root

    property real s: 1
    property bool live: true
    required property var notif

    readonly property bool critical: notif ? notif.urgency === NotificationUrgency.Critical : false
    readonly property var acts: (notif && notif.actions)
        ? notif.actions.filter(function(a) { return a && a.text && a.text.length > 0; }) : []

    implicitHeight: Math.max(iconTile.height, col.implicitHeight)

    /**
     * Deadline is snapshotted (never bound to the live map): binding the
     * timer interval to Notifications.expireAt would restart the countdown —
     * and drift the lifetime — every time an unrelated notification replaces
     * the map. Re-snapshotted when the displayed notification changes (queue
     * advances), so each toast runs on its own clock.
     */
    property double deadline: 0

    function snapshotDeadline() {
        deadline = notif ? (Notifications.expireAt[notif.id] || (Date.now() + 6000)) : 0;
    }

    Component.onCompleted: snapshotDeadline()
    onNotifChanged: snapshotDeadline()

    Timer {
        interval: Math.max(300, root.deadline - Date.now())
        running: root.deadline > 0 && root.live && !root.critical
        onTriggered: Notifications.removePopup(root.notif)
    }

    MouseArea {
        id: bodyArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Notifications.activateNotif(root.notif);
            Notifications.removePopup(root.notif);
        }
    }

    scale: bodyArea.pressed ? 0.96 : 1
    Behavior on scale {
        NumberAnimation {
            duration: Motion.glide
            easing.type: Motion.easeBezier
            easing.bezierCurve: Motion.expressiveFastSpatial
        }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: root.notif ? root.notif.summary : ""
    Accessible.description: root.notif ? root.notif.body : ""

    Rectangle {
        id: iconTile
        anchors.left: parent.left
        anchors.top: parent.top
        width: 28 * root.s
        height: 28 * root.s
        radius: 9 * root.s
        color: Colors.surface_container_high
        border.width: 1
        border.color: Qt.alpha(Colors.outline_variant, 0.6)

        Image {
            id: toastImg
            anchors.fill: parent
            anchors.margins: (root.notif && root.notif.image) ? 0 : 6 * root.s
            source: Notifications.iconFor(root.notif)
            sourceSize.width: 56
            sourceSize.height: 56
            fillMode: Image.PreserveAspectCrop
            smooth: true
            // Ready (not just non-empty): iconFor may hand back a resolved path
            // that fails to load; gating on length would then paint Qt's magenta
            // broken-image placeholder instead of falling back to the diamond.
            visible: status === Image.Ready
        }

        Rectangle {
            anchors.centerIn: parent
            visible: !toastImg.visible
            width: 7 * root.s
            height: 7 * root.s
            radius: 2 * root.s
            rotation: 45
            color: root.critical ? Colors.error : Colors.primary
        }
    }

    GlyphIcon {
        id: dismiss
        anchors.right: parent.right
        anchors.top: parent.top
        // Was 11·s — below ~13·s a stroked glyph's rasterized line width
        // can't get thin enough to stay legible; the shape reads as a
        // blobby smudge instead of a crisp × (verified by rendering every
        // icon at every real size the shell uses, side by side).
        width: 13 * root.s
        height: 13 * root.s
        name: "close"
        color: dismissArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
        stroke: 1.9

        Behavior on color {
            ColorAnimation { duration: Motion.fast; easing.type: Motion.easeStandard }
        }

        scale: dismissArea.pressed ? 0.92 : 1
        Behavior on scale {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Dismiss notification"
        Accessible.onPressAction: dismissArea.clicked(null)

        MouseArea {
            id: dismissArea
            anchors.fill: parent
            anchors.margins: -6 * root.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifications.removePopup(root.notif)
        }
    }

    Column {
        id: col
        anchors.left: iconTile.right
        anchors.leftMargin: 10 * root.s
        anchors.right: dismiss.left
        anchors.rightMargin: 8 * root.s
        anchors.top: parent.top
        spacing: 3 * root.s

        Text {
            width: parent.width
            text: (root.notif && root.notif.appName && root.notif.appName.length)
                ? root.notif.appName : "System"
            color: Qt.alpha(Colors.on_surface_variant, 0.85)
            font.family: Appearance.font.family
            font.pixelSize: 8.5 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.4 * root.s
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            spacing: 5 * root.s

            Item {
                visible: root.critical
                anchors.verticalCenter: parent.verticalCenter
                width: 8 * root.s
                height: 8 * root.s

                Rectangle {
                    anchors.centerIn: parent
                    width: 8 * root.s
                    height: 8 * root.s
                    radius: width / 2
                    color: Colors.error
                    opacity: 0.3
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 4 * root.s
                    height: 4 * root.s
                    radius: width / 2
                    color: Colors.error
                }
            }

            Text {
                width: parent.width - (root.critical ? 13 * root.s : 0)
                text: root.notif ? root.notif.summary : ""
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 11.5 * root.s
                font.weight: Font.DemiBold
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }

        Text {
            width: parent.width
            visible: root.notif ? root.notif.body.length > 0 : false
            text: root.notif ? root.notif.body : ""
            color: Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: 10.5 * root.s
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        Row {
            visible: root.acts.length > 0
            spacing: 6 * root.s
            topPadding: 4 * root.s

            Repeater {
                model: root.acts

                Rectangle {
                    id: actPill
                    required property var modelData
                    required property int index

                    height: 20 * root.s
                    width: actText.implicitWidth + 18 * root.s
                    radius: Appearance.rounding.full
                    // First action is the primary CTA: give it a filled accent
                    // tint + accent border so it reads apart from the plainer
                    // secondary actions, not just a colour swap on the label.
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
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            actPill.modelData.invoke();
                            if (actPill.modelData.identifier === "default")
                                Notifications.raiseWindow(root.notif);
                            Notifications.removePopup(root.notif);
                        }
                    }
                }
            }
        }
    }
}
