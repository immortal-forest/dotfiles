// No `pragma ComponentBehavior: Bound` here: the notification centre
// instantiates this file's KindTile / ShotThumb / ActChip / FileActs, and a
// bound inline component cannot be created from another file (the centre's
// rows silently failed to build). None of them reach into Toast's scope.

import QtQuick
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../colors"
import "../services"
import "../config"

/**
 * astralis — toast content for the morphing pill body (ported from
 * Gakuseei/Ricelin pill/Toast.qml): kind tile, source eyebrow, title,
 * caption, then whatever the notification's kind brings — a screenshot
 * thumbnail, the shell's own file actions, the sender's action pills — and a
 * dismiss glyph on the right. Draws no background of its own: the pill body
 * behind it provides the material.
 *
 * Critical: the pill body turns error_container (Pill.qml `body.critical`),
 * and everything drawn here switches to that container's one ink,
 * on_error_container — eyebrow, title, caption, dismiss, a tonal tile and
 * tonal/filled chips — with hierarchy from weight and alpha, never from a
 * second colour family. The eyebrow says "Urgent" in words so the state
 * never rests on colour alone. Clicking the body opens (screenshot/recording) or
 * jumps to the source app; dismiss and action pills consume their clicks.
 * Auto-expires via the deadline snapshot below unless the notification is
 * critical (criticals persist); hovering holds the countdown.
 *
 * The inline components below (KindTile, ShotThumb, ActChip, FileActs) are
 * also used by the notification centre (surfaces/Notifications.qml) as
 * `Toast.KindTile` etc., so the popup and the backlog share one visual
 * language for icons, thumbnails and actions.
 */
Item {
    id: root

    property real s: 1
    property bool live: true
    required property var notif

    readonly property string kind: Notifications.kindOf(notif)
    readonly property bool critical: notif ? notif.urgency === NotificationUrgency.Critical : false
    readonly property bool failed: Notifications.isFailure(notif)
    readonly property string file: Notifications.fileOf(notif)
    /** Primary / secondary ink: the error container's own on-colour on criticals. */
    readonly property color ink: root.critical ? Colors.on_error_container : Colors.on_surface
    readonly property color inkSoft: root.critical ? Qt.alpha(Colors.on_error_container, 0.8) : Colors.on_surface_variant
    readonly property var acts: (notif && notif.actions)
        ? notif.actions.filter(function(a) { return a && a.text && a.text.length > 0; }) : []

    implicitHeight: Math.max(tile.height, col.implicitHeight)

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
    onNotifChanged: {
        snapshotDeadline();
        root.wasHovered = false;
        leaveTimer.stop();
        root.shownAt = Date.now();
    }

    /**
     * The toast goes away the way the pill's hover does. "Leave" is always
     * the timeout's path — the popup retires, the notification stays in the
     * centre — never a dismiss.
     */
    function retire() {
        // Leaving clears the whole popup queue, not just the face on top:
        // retiring only the visible one let the next queued popup slide
        // straight in, which read as "it didn't go away". Everything stays
        // in the centre — this is the timeout's path, never a dismiss.
        var queued = Notifications.popups.slice();
        for (var i = 0; i < queued.length; i++)
            Notifications.removePopup(queued[i]);
    }

    /** A toast action (Open, Play, an app action…) may focus a window: don't read that as "clicked elsewhere". */
    function markAction() {
        root.quietUntil = Date.now() + Motion.standard * 3;
    }

    property bool wasHovered: false
    property double shownAt: Date.now()
    property double quietUntil: 0

    Timer {
        interval: Math.max(300, root.deadline - Date.now())
        running: root.deadline > 0 && root.live && !root.critical && !toastHover.hovered
        onTriggered: Notifications.removePopup(root.notif)
    }

    // Hover holds the countdown. Once the pointer has been on the toast,
    // leaving it retires the toast after the pill's own hover grace
    // (Pill.qml latchTimer, Motion.fast) — a pointer that grazed out and
    // straight back keeps it. Never hovered → the normal timeout.
    HoverHandler {
        id: toastHover
        // Cover the pill body's padding around this content, so the pointer
        // still counts as "on the toast" anywhere inside the pill.
        margin: 16 * root.s
        onHoveredChanged: {
            if (hovered) {
                root.wasHovered = true;
                leaveTimer.stop();
            } else if (root.wasHovered && root.live) {
                leaveTimer.restart();
            }
        }
    }

    Timer {
        id: leaveTimer
        interval: Motion.fast
        onTriggered: if (!toastHover.hovered) root.retire()
    }

    // A click elsewhere moves Hyprland focus (or workspace / monitor): the
    // toast leaves, like the pill collapsing — without grabbing any input
    // itself, so that click still lands in the app and keyboard focus never
    // moves. The whole queue goes (criticals included); events right after the toast
    // appeared (an app raising itself with its own notification) or right
    // after one of the toast's own actions (Open launching a viewer) are not
    // a click elsewhere.
    Connections {
        target: Hyprland
        // Criticals too: they never time out on their own, but a click
        // elsewhere still sends them to the centre like any other popup.
        enabled: root.live && root.notif !== null
        function onRawEvent(event) {
            if (event.name !== "activewindowv2" && event.name !== "workspacev2" && event.name !== "focusedmon")
                return;
            var now = Date.now();
            if (now < root.quietUntil || now - root.shownAt < Motion.morph)
                return;
            root.retire();
        }
    }

    // ── shared pieces (also used by the notification centre) ────────────────

    /**
     * The notification's identity tile, one shape language everywhere:
     *  - shell / recording → a kanji seal (星 / 録) on the primary container
     *    (error container for a failed take); a glyph stands in with glyphs off
     *  - message / media (when `avatar`) → the content image itself: a round
     *    avatar or a rounded cover, with the app's icon as a small badge
     *  - everything else → the app icon inset in a tonal tile, or a neutral
     *    glyph (cog, window, image…) when no icon resolves — never a broken
     *    image or a bare diamond.
     */
    component KindTile: Item {
        id: kt

        required property var n
        property real s: 1
        property real size: 28 * s
        property bool avatar: true
        /** Sitting on the error container (critical toast): tonal tile + on_error_container glyph. */
        property bool onError: false

        readonly property string kind: Notifications.kindOf(kt.n)
        readonly property bool crit: kt.n ? kt.n.urgency === NotificationUrgency.Critical : false
        readonly property bool failed: Notifications.isFailure(kt.n)
        // Screenshots get the shell's own 写 seal: their app icon used to
        // resolve to the capture itself, a postage-stamp copy of the big
        // thumbnail sitting right above it.
        readonly property string seal: kt.kind === "recording" ? "録"
            : kt.kind === "shell" ? "星"
            : kt.kind === "screenshot" ? "写" : ""
        readonly property string face: (kt.avatar && (kt.kind === "message" || kt.kind === "media"))
            ? Notifications.avatarFor(kt.n) : ""
        // A face that failed (a history row's image-data is gone with its
        // notification) drops back to the plain tile.
        readonly property bool faceOk: kt.face.length > 0 && faceImg.status !== Image.Error
        readonly property string icon: kt.seal.length ? "" : Notifications.appIconFor(kt.n)
        // Icons decode once at a fixed, generous size (the shell runs at
        // fractional scale): never bound to an animating width.
        readonly property int px: Math.ceil(kt.size * 2.5)
        /** One corner for seals, icon tiles and faces alike. */
        readonly property real radius: kt.size * 0.3

        width: kt.size
        height: kt.size

        // seal
        Rectangle {
            anchors.fill: parent
            visible: kt.seal.length > 0
            radius: kt.radius
            // Tonal, not a saturated slab: the container at half strength.
            color: Qt.alpha(kt.failed ? Colors.error_container : Colors.primary_container, 0.55)

            Text {
                anchors.centerIn: parent
                visible: Flags.showGlyphs
                text: kt.seal
                color: kt.failed ? Colors.on_error_container : Colors.on_primary_container
                font.family: Appearance.font.jp
                font.weight: Font.Medium
                font.pixelSize: kt.size * 0.56
            }

            GlyphIcon {
                anchors.centerIn: parent
                visible: !Flags.showGlyphs
                width: Math.max(13 * kt.s, kt.size * 0.5)
                height: width
                name: Notifications.glyphFor(kt.n)
                color: kt.failed ? Colors.on_error_container : Colors.on_primary_container
                stroke: 1.9
            }
        }

        // plain tile: app icon or neutral glyph
        Rectangle {
            anchors.fill: parent
            visible: kt.seal.length === 0 && !kt.faceOk
            radius: kt.radius
            color: kt.onError ? Qt.alpha(Colors.on_error_container, 0.12) : Colors.surface_container_high
            Behavior on color { ColorAnimation { duration: Motion.standard } }

            Image {
                id: iconImg
                anchors.centerIn: parent
                width: Math.round(kt.size * 0.64)
                height: width
                source: kt.icon
                sourceSize: Qt.size(kt.px, kt.px)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }

            GlyphIcon {
                anchors.centerIn: parent
                width: Math.max(13 * kt.s, kt.size * 0.5)
                height: width
                opacity: iconImg.status === Image.Ready ? 0 : 1
                name: Notifications.glyphFor(kt.n)
                color: kt.onError ? Colors.on_error_container : Colors.on_surface_variant
                stroke: 1.8
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }
        }

        // avatar / cover
        ClippingRectangle {
            anchors.fill: parent
            visible: kt.faceOk
            radius: kt.radius
            color: Colors.surface_container_high

            Image {
                id: faceImg
                anchors.fill: parent
                source: kt.face
                sourceSize: Qt.size(kt.px, kt.px)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                mipmap: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
            }
        }

        // app badge on the avatar
        ClippingRectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -2 * kt.s
            anchors.bottomMargin: -2 * kt.s
            width: Math.round(kt.size * 0.46)
            height: width
            radius: width * 0.32
            color: Colors.surface_container_highest
            border.width: 1.5 * kt.s
            border.color: Colors.surface_container
            visible: kt.faceOk
            opacity: badgeImg.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            Image {
                id: badgeImg
                anchors.centerIn: parent
                width: parent.width * 0.78
                height: width
                source: kt.faceOk ? Notifications.appIconFor(kt.n) : ""
                sourceSize: Qt.size(Math.ceil(kt.size * 1.2), Math.ceil(kt.size * 1.2))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
            }
        }
    }

    /**
     * Screenshot thumbnail: rounded, sized to the image's real aspect within
     * maxW × maxH (never squashed or cropped), decoded once at a fixed width.
     * Hover lifts a scrim with an eye; click emits `activated` (open).
     */
    component ShotThumb: ClippingRectangle {
        id: st

        property string path: ""
        property real s: 1
        property real maxW: 240 * s
        property real maxH: 140 * s
        signal activated()

        readonly property bool ok: shotImg.status === Image.Ready && shotImg.implicitWidth > 0
        // Aspect eases rather than snapping when the decode lands; width and
        // height then follow the host's width directly (no lag mid-morph).
        property real aspect: ok ? shotImg.implicitHeight / shotImg.implicitWidth : 10 / 16
        Behavior on aspect {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.morphCurve }
        }

        width: Math.min(st.maxW, st.maxH / Math.max(0.05, st.aspect))
        height: st.width * st.aspect
        radius: 10 * st.s
        color: Colors.surface_container_high

        scale: stArea.pressed ? 0.97 : 1
        Behavior on scale {
            NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial }
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Open screenshot"
        Accessible.onPressAction: st.activated()

        GlyphIcon {
            anchors.centerIn: parent
            width: 18 * st.s
            height: 18 * st.s
            name: "image"
            color: Colors.on_surface_variant
            opacity: st.ok ? 0 : 0.6
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
        }

        Image {
            id: shotImg
            anchors.fill: parent
            source: Notifications.fileUrl(st.path)
            sourceSize.width: 720
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            opacity: st.ok ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colors.scrim, 0.35)
            opacity: stArea.containsMouse && st.ok ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

            GlyphIcon {
                anchors.centerIn: parent
                width: 20 * st.s
                height: 20 * st.s
                name: "eye"
                color: Colors.on_surface
                stroke: 1.9
            }
        }

        // Hairline edge drawn over the image so light shots keep a boundary.
        Rectangle {
            anchors.fill: parent
            radius: st.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Colors.outline_variant, 0.5)
        }

        MouseArea {
            id: stArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: st.activated()
        }
    }

    /** Action pill: the shell's chip shape, optional leading glyph, primary / danger tints. */
    component ActChip: Rectangle {
        id: chip

        property real s: 1
        property string label: ""
        property string glyph: ""
        property bool primary: false
        property bool danger: false
        /** On the error container: primary = filled error/on_error, others tonal in on_error_container. */
        property bool onError: false
        signal tapped()

        height: 22 * chip.s
        width: chipRow.implicitWidth + 18 * chip.s
        radius: height / 2
        // Fill only, never an outline (architecture §2b-v): the neutral chip
        // sits one rung above the toast's own surface so it still reads, and
        // hover folds the M3 state layer (8% of the content colour) into it.
        color: (chip.onError && chip.primary) ? (chipArea.containsMouse ? Qt.lighter(Colors.error, 1.08) : Colors.error)
            : chip.onError ? Qt.alpha(Colors.on_error_container, chipArea.containsMouse ? 0.20 : 0.12)
            : chip.danger ? Qt.alpha(Colors.error, chipArea.containsMouse ? 0.28 : 0.18)
            : chip.primary ? Qt.alpha(Colors.primary, chipArea.containsMouse ? 0.24 : 0.14)
            : (chipArea.containsMouse
                ? Qt.tint(Colors.surface_container_highest, Qt.alpha(Colors.on_surface, 0.08))
                : Colors.surface_container_highest)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on width {
            NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial }
        }

        scale: chipArea.pressed ? 0.92 : 1
        Behavior on scale {
            NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial }
        }

        Accessible.role: Accessible.Button
        Accessible.name: chip.label
        Accessible.focusable: true
        Accessible.onPressAction: chip.tapped()

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 4 * chip.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.glyph.length > 0
                width: 13 * chip.s
                height: 13 * chip.s
                name: chip.glyph
                stroke: 1.9
                color: chipText.color
            }

            Text {
                id: chipText
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: (chip.onError && chip.primary) ? Colors.on_error
                    : chip.onError ? Colors.on_error_container
                    : chip.danger ? Colors.error : chip.primary ? Colors.primary : Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * chip.s
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.tapped()
        }
    }

    /**
     * The shell's own file actions, run by astralis itself (services/
     * Notifications.qml): screenshot → Open · Copy · Folder · Delete (two-tap,
     * trashes only that file); saved recording → Play · Folder. `opened` asks
     * the host to close (toast/centre), `deleted` to dismiss the entry.
     */
    component FileActs: Flow {
        id: fa

        required property var n
        property real s: 1
        signal opened()
        signal deleted()

        readonly property string kind: Notifications.kindOf(fa.n)
        readonly property string file: Notifications.fileOf(fa.n)
        readonly property bool shot: fa.kind === "screenshot" && fa.file.length > 0
        readonly property bool rec: fa.kind === "recording" && fa.file.length > 0
        readonly property bool shown: fa.shot || fa.rec
        property bool armed: false
        property bool copied: false

        spacing: 6 * fa.s
        onNChanged: {
            fa.armed = false;
            fa.copied = false;
        }

        Timer {
            id: disarm
            interval: 3000
            onTriggered: fa.armed = false
        }
        Timer {
            id: uncopy
            interval: 1600
            onTriggered: fa.copied = false
        }

        ActChip {
            visible: fa.shot
            s: fa.s
            label: "Open"
            glyph: "image"
            primary: true
            onTapped: {
                Notifications.openFile(fa.file);
                fa.opened();
            }
        }
        ActChip {
            visible: fa.rec
            s: fa.s
            label: "Play"
            glyph: "play"
            primary: true
            onTapped: {
                Notifications.openFile(fa.file);
                fa.opened();
            }
        }
        ActChip {
            visible: fa.shot
            s: fa.s
            label: fa.copied ? "Copied" : "Copy"
            glyph: fa.copied ? "check" : "copy"
            onTapped: {
                Notifications.copyImage(fa.file);
                fa.copied = true;
                uncopy.restart();
            }
        }
        ActChip {
            visible: fa.shown
            s: fa.s
            label: "Folder"
            onTapped: {
                Notifications.showInFolder(fa.file);
                fa.opened();
            }
        }
        ActChip {
            visible: fa.shot
            s: fa.s
            label: fa.armed ? "Delete file?" : "Delete"
            glyph: "trash"
            danger: fa.armed
            onTapped: {
                if (!fa.armed) {
                    fa.armed = true;
                    disarm.restart();
                    return;
                }
                fa.armed = false;
                Notifications.trashFile(fa.file);
                fa.deleted();
            }
        }
    }

    // ── the toast ───────────────────────────────────────────────────────────

    MouseArea {
        id: bodyArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.markAction();
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
    Accessible.name: root.notif ? Notifications.titleFor(root.notif) : ""
    Accessible.description: root.notif ? Notifications.captionFor(root.notif) : ""

    KindTile {
        id: tile
        anchors.left: parent.left
        anchors.top: parent.top
        n: root.notif
        s: root.s
        size: 30 * root.s
        onError: root.critical
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
        color: dismissArea.containsMouse ? root.ink : root.inkSoft
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
        anchors.left: tile.right
        anchors.leftMargin: 10 * root.s
        anchors.right: dismiss.left
        anchors.rightMargin: 8 * root.s
        anchors.top: parent.top
        spacing: 3 * root.s

        Text {
            width: parent.width
            text: Notifications.sourceLabel(root.notif) + (root.kind === "recording" ? "  ·  Recorder" : "")
                + (root.critical ? "  ·  Urgent" : "")
            color: root.critical ? Qt.alpha(Colors.on_error_container, 0.8) : Qt.alpha(Colors.on_surface_variant, 0.85)
            font.family: Appearance.font.family
            font.pixelSize: 8.5 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.4 * root.s
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: Notifications.titleFor(root.notif)
            color: root.critical ? root.ink : root.failed ? Colors.error : Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 11.5 * root.s
            font.weight: Font.DemiBold
            maximumLineCount: 1
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            visible: text.length > 0
            text: Notifications.captionFor(root.notif)
            // A failed take's caption IS the error: error ink, more lines.
            color: root.critical ? root.inkSoft
                : root.failed ? Colors.on_error_container
                : root.kind === "screenshot" ? Qt.alpha(Colors.on_surface_variant, 0.8) : Colors.on_surface_variant
            font.family: Appearance.font.family
            font.pixelSize: (root.kind === "screenshot" ? 9.5 : 10.5) * root.s
            wrapMode: root.kind === "screenshot" ? Text.NoWrap : Text.Wrap
            maximumLineCount: root.failed ? 4 : 2
            elide: root.kind === "screenshot" ? Text.ElideMiddle : Text.ElideRight
            textFormat: Text.PlainText
        }

        Item {
            visible: root.kind === "screenshot"
            width: parent.width
            height: visible ? thumb.height + 4 * root.s : 0

            ShotThumb {
                id: thumb
                y: 4 * root.s
                s: root.s
                path: root.kind === "screenshot" ? root.file : ""
                maxW: parent.width
                maxH: 140 * root.s
                onActivated: {
                    root.markAction();
                    Notifications.openFile(root.file);
                    Notifications.removePopup(root.notif);
                }
            }
        }

        FileActs {
            id: fileActs
            visible: fileActs.shown
            width: parent.width
            topPadding: 4 * root.s
            n: root.notif
            s: root.s
            onOpened: {
                root.markAction();
                Notifications.removePopup(root.notif);
            }
            onDeleted: Notifications.dismissNotif(root.notif)
        }

        Flow {
            visible: root.acts.length > 0
            width: parent.width
            spacing: 6 * root.s
            topPadding: 4 * root.s

            Repeater {
                model: root.acts

                ActChip {
                    id: actPill
                    required property var modelData
                    required property int index

                    s: root.s
                    label: actPill.modelData.text
                    // First sender action is the primary CTA unless the
                    // shell's own Open/Play already took that role.
                    primary: actPill.index === 0 && !fileActs.shown
                    onError: root.critical
                    onTapped: {
                        root.markAction();
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
