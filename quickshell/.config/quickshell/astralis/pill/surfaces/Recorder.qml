pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../../colors"
import "../../services"
import "../../config"
import "../m3"

/**
 * astralis — 録 RECORD surface: the screen recorder's face.
 *
 * Three states share one panel so the pill never changes size mid-take. Idle
 * shows the three capture sources (whole screen / a window / a dragged region);
 * arming shows the countdown that gives the surface time to morph shut before
 * the encoder opens, with a cancel; recording shows the running clock, what is
 * being captured, and the stop (plus pause, on the one backend that has it).
 *
 * Everything below the divider is the take's settings, persisted in Flags and
 * shared with the rest of the shell. Rows a backend cannot honour are dimmed
 * and disabled from ScreenRec.cap rather than hidden, so it stays obvious that
 * the setting exists and which recorder is ignoring it — and the failure text
 * from the last launch takes over the panel when a take dies, since a recorder
 * that refuses a flag is the one thing the user has to be able to read.
 */
PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 14

    readonly property bool recording: ScreenRec.recording
    readonly property bool arming: ScreenRec.arming
    readonly property bool picking: ScreenRec.picking

    /**
     * Nothing to record with. Shown as soon as the probe reports back rather
     * than waiting for a click on a dead tile, so the panel explains itself
     * instead of leaving three greyed-out sources with no reason given.
     */
    readonly property bool noBackend: ScreenRec.probed && !ScreenRec.available
    readonly property bool showError: (ScreenRec.error.length > 0 || noBackend) && !recording && !arming
    readonly property string errorText: root.noBackend
        ? "Install gpu-screen-recorder, wl-screenrec or wf-recorder, then re-scan."
        : ScreenRec.error

    readonly property var sources: [
        { key: "screen", icon: "monitor",    label: "Screen" },
        { key: "window", icon: "app-window", label: "Window" },
        { key: "region", icon: "scaling",    label: "Region" }
    ]

    readonly property var countdownOptions: [
        { label: "Off", value: 0 }, { label: "3s", value: 3 },
        { label: "5s", value: 5 }, { label: "10s", value: 10 }
    ]
    readonly property var fpsOptions: ScreenRec.fpsOptions.map(function (f) {
        return { label: "" + f, value: f };
    })
    readonly property var qualityOptions: [
        { label: "Med", value: "medium" }, { label: "High", value: "high" },
        { label: "V.High", value: "very_high" }, { label: "Ultra", value: "ultra" }
    ]

    /**
     * The take's label under the clock: source, then the settings that actually
     * reached the encoder (dimmed rows never claim credit for a flag that was
     * never passed).
     */
    readonly property string takeLabel: {
        const bits = [ScreenRec.source.toUpperCase()];
        if (ScreenRec.cap.fps)
            bits.push(Flags.recordFps + " fps");
        if (ScreenRec.cap.quality)
            bits.push(Flags.recordQuality.replace("_", " "));
        // Spelled out rather than calling ScreenRec.audioDevices(): a function
        // call registers no dependencies, so the label would freeze on the
        // first evaluation instead of following the toggles below it.
        const desk = Flags.recordDesktop && ScreenRec.desktopDevice.length > 0;
        const mic = Flags.recordMic && ScreenRec.micDevice.length > 0;
        bits.push(!desk && !mic ? "muted"
            : (desk && mic && ScreenRec.cap.mergeAudio ? "audio ×2"
            : (mic && !desk ? "mic" : "audio")));
        return bits.join(" · ");
    }

    /**
     * The ember rests on the 録 header kanji while idle (Sysmon's lantern
     * idiom: the bead hangs a bead's diameter BELOW the glyph box, wick rising
     * back up into the strokes) and rides the pulsing capture dot while a take
     * runs, so the bead marks whatever the surface is actually about at that
     * moment. Below, not above: 3*s above the glyph put the wick's ~11.3*s of
     * ink straight through the pill's top edge, and the Ame canvas cuts
     * whatever falls outside the body. With glyphs off the kanji is hidden, so
     * the idle anchor falls back to the RECORD label's left edge and the bead
     * never floats.
     */
    readonly property point soulPoint: {
        void root.width;
        void root.height;
        void root.recording;
        if (root.recording)
            return recDot.mapToItem(root, recDot.width / 2, recDot.height / 2);
        if (Flags.showGlyphs)
            return kanji.mapToItem(root, kanji.width / 2, kanji.height + 6 * root.s);
        return recLabel.mapToItem(root, -8 * root.s, recLabel.height / 2);
    }

    ameForm: open ? (root.recording ? "dock" : "soul") : "off"
    amePoint: soulPoint

    implicitHeight: content.implicitHeight

    // ── one settings line: label on the left, control on the right ──────────
    component OptionRow: Item {
        id: orow
        property string label: ""
        property bool supported: true
        default property alias control: ctrl.data

        width: parent ? parent.width : 0
        height: 42 * root.s
        // A backend that ignores the flag gets the row dimmed rather than
        // removed, so the setting stays discoverable and its absence readable.
        opacity: orow.supported ? 1 : 0.32
        enabled: orow.supported
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: orow.label
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: 12 * root.s
            font.weight: Font.Medium
        }

        Item {
            id: ctrl
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    /**
     * A capture toggle (desktop audio / mic / cursor) as one of three equal
     * tiles. The state is spelled out under the label, because a struck-through
     * glyph alone read as "disabled" rather than "off". On fills
     * primary_container and squares its corners; off is the bare stadium.
     */
    component CaptureTile: Rectangle {
        id: ct
        property string icon: ""
        property string offIcon: ct.icon
        property string label: ""
        property bool on: false
        property bool supported: true
        signal toggled()

        readonly property color ink: ct.on ? Colors.on_primary_container : Colors.on_surface_variant

        height: 52 * root.s
        radius: (ctArea.pressed ? 12 : (ct.on ? 16 : 26)) * root.s
        color: ct.on ? Colors.primary_container
            : (ctArea.containsMouse ? Colors.surface_container_highest : Colors.surface_container_high)
        opacity: ct.supported ? 1 : 0.32
        enabled: ct.supported
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
        Behavior on radius {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Accessible.role: Accessible.CheckBox
        Accessible.name: ct.label
        Accessible.checkable: true
        Accessible.checked: ct.on
        Accessible.focusable: ct.supported
        Accessible.onPressAction: ct.toggled()

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 14 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10 * root.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * root.s
                height: 16 * root.s
                name: ct.on ? ct.icon : ct.offIcon
                color: ct.ink
                stroke: 1.8
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s

                Text {
                    text: ct.label
                    color: ct.on ? Colors.on_primary_container : Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 11 * root.s
                    font.weight: Font.Bold
                }
                Text {
                    text: !ct.supported ? "N/A" : (ct.on ? "On" : "Off")
                    color: Qt.alpha(ct.ink, 0.75)
                    font.family: Appearance.font.family
                    font.pixelSize: 9 * root.s
                    font.weight: Font.DemiBold
                }
            }
        }

        MouseArea {
            id: ctArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ct.toggled()
        }
    }

    /** Tonal stadium chip for the action row (countdown, save folder). */
    component ActionChip: Rectangle {
        id: ac
        property string icon: ""
        property string label: ""
        property real maxLabelWidth: 200 * root.s
        signal activated(int button)

        width: acRow.implicitWidth + 30 * root.s
        height: 52 * root.s
        radius: acArea.pressed ? 16 * root.s : height / 2
        color: acArea.containsMouse ? Colors.surface_container_highest : Colors.surface_container_high
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on radius {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Accessible.role: Accessible.Button
        Accessible.focusable: true
        Accessible.onPressAction: ac.activated(Qt.LeftButton)

        Row {
            id: acRow
            anchors.centerIn: parent
            spacing: 7 * root.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 15 * root.s
                height: 15 * root.s
                name: ac.icon
                color: acArea.containsMouse ? Colors.primary : Colors.on_surface_variant
                stroke: 1.8
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, ac.maxLabelWidth)
                text: ac.label
                color: acArea.containsMouse ? Colors.primary : Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: 11 * root.s
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
                elide: Text.ElideMiddle
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }

        MouseArea {
            id: acArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => ac.activated(mouse.button)
        }
    }


    /** Round tonal transport button (pause / resume) for the running take. */
    component TransportButton: Rectangle {
        id: tbtn
        property string icon: ""
        signal activated()

        width: 44 * root.s
        height: 44 * root.s
        radius: tbtnArea.pressed ? 14 * root.s : width / 2
        color: tbtnArea.containsMouse ? Colors.surface_container_highest : Colors.surface_container_high
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on radius {
            NumberAnimation {
                duration: Motion.glide
                easing.type: Motion.easeBezier
                easing.bezierCurve: Motion.expressiveFastSpatial
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: tbtn.icon === "pause" ? "Pause recording" : "Resume recording"
        Accessible.focusable: true
        Accessible.onPressAction: tbtn.activated()

        GlyphIcon {
            anchors.centerIn: parent
            width: 16 * root.s
            height: 16 * root.s
            name: tbtn.icon
            color: Colors.on_surface
            stroke: 1.8
        }

        MouseArea {
            id: tbtnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tbtn.activated()
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        spacing: 0

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9 * root.s

                Text {
                    id: kanji
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "録"
                    color: Colors.on_surface
                    font.family: Appearance.font.jp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    id: recLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "RECORD"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.8 * root.s
                }
            }

            /**
             * Backend chip. With more than one recorder installed a tap cycles
             * the pinned choice (persisted in Flags.recordBackend); with one it
             * is just a readout of what is driving the capture.
             */
            Rectangle {
                id: backendChip
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool switchable: ScreenRec.installed.length > 1 && !ScreenRec.busy
                width: backendText.implicitWidth + 18 * root.s
                height: 20 * root.s
                radius: 8 * root.s
                color: backendArea.containsMouse && backendChip.switchable
                    ? Colors.surface_container_highest : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Accessible.role: Accessible.Button
                Accessible.name: "Recording backend"
                Accessible.description: backendText.text
                    + (backendChip.switchable ? " — tap to switch" : "")
                Accessible.focusable: backendChip.switchable
                Accessible.onPressAction: {
                    const list = ScreenRec.installed;
                    const next = (list.indexOf(ScreenRec.backend) + 1) % list.length;
                    Flags.recordBackend = list[next];
                }

                Text {
                    id: backendText
                    anchors.centerIn: parent
                    text: ScreenRec.available ? ScreenRec.backendLabel
                        : (ScreenRec.probed ? "No backend" : "…")
                    color: ScreenRec.available ? Colors.on_surface_variant
                        : Qt.alpha(Colors.error, 0.9)
                    font.family: Appearance.font.family
                    font.pixelSize: 9.5 * root.s
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: backendArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: backendChip.switchable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const list = ScreenRec.installed;
                        const next = (list.indexOf(ScreenRec.backend) + 1) % list.length;
                        Flags.recordBackend = list[next];
                    }
                }
            }
        }

        Item { width: 1; height: 14 * root.s }

        // ── state panel: sources / countdown / running take / failure ───────
        Item {
            id: panel
            width: parent.width
            height: 64 * root.s

            /**
             * Idle — pick what to capture: one segmented track with a lit
             * indicator that slides to the chosen source. Picking only
             * selects; Record below starts the take.
             */
            Rectangle {
                id: sourceRow
                anchors.fill: parent
                radius: height / 2
                color: Colors.surface_container_high
                opacity: (!root.recording && !root.arming && !root.showError) ? 1 : 0
                visible: opacity > 0.01
                enabled: opacity > 0.9 && !root.picking
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                readonly property real inset: 5 * root.s
                readonly property real segW: (sourceRow.width - 2 * sourceRow.inset) / root.sources.length
                readonly property int current: {
                    for (let i = 0; i < root.sources.length; i++)
                        if (root.sources[i].key === Flags.recordSource)
                            return i;
                    return 0;
                }

                Rectangle {
                    x: sourceRow.inset + sourceRow.current * sourceRow.segW
                    y: sourceRow.inset
                    width: sourceRow.segW
                    height: sourceRow.height - 2 * sourceRow.inset
                    radius: height / 2
                    color: Colors.secondary_container
                    Behavior on x {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }
                }

                Repeater {
                    model: root.sources
                    Item {
                        id: seg
                        required property var modelData
                        required property int index
                        readonly property bool selected: sourceRow.current === seg.index
                        readonly property color ink: seg.selected ? Colors.on_secondary_container
                            : (segArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant)
                        x: sourceRow.inset + seg.index * sourceRow.segW
                        y: sourceRow.inset
                        width: sourceRow.segW
                        height: sourceRow.height - 2 * sourceRow.inset

                        Accessible.role: Accessible.RadioButton
                        Accessible.name: seg.modelData.label
                        Accessible.checkable: true
                        Accessible.checked: seg.selected
                        Accessible.focusable: true
                        Accessible.onPressAction: Flags.recordSource = seg.modelData.key

                        Column {
                            anchors.centerIn: parent
                            spacing: 5 * root.s
                            scale: segArea.pressed ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: Motion.fast } }

                            GlyphIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 18 * root.s
                                height: 18 * root.s
                                name: seg.modelData.icon
                                color: seg.ink
                                stroke: 1.7
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: seg.modelData.label
                                color: seg.ink
                                font.family: Appearance.font.family
                                font.pixelSize: 10.5 * root.s
                                font.weight: seg.selected ? Font.Bold : Font.DemiBold
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                        }

                        MouseArea {
                            id: segArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Flags.recordSource = seg.modelData.key
                        }
                    }
                }
            }

            // Arming — the countdown before the encoder opens.
            Column {
                anchors.centerIn: parent
                spacing: 6 * root.s
                opacity: root.arming ? 1 : 0
                visible: opacity > 0.01
                enabled: root.arming
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                Text {
                    id: countText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "" + ScreenRec.countdown
                    color: Colors.primary
                    font.family: Appearance.font.family
                    font.pixelSize: 40 * root.s
                    font.weight: Font.ExtraBold
                    font.features: ({ "tnum": 1 })

                    // One pop per tick, so the number reads as a beat rather
                    // than a silently swapping label.
                    onTextChanged: if (!Motion.reduceMotion) tickPop.restart()
                    SequentialAnimation {
                        id: tickPop
                        NumberAnimation { target: countText; property: "scale"; to: 1.16; duration: Motion.fast; easing.type: Motion.easeStandard }
                        NumberAnimation { target: countText; property: "scale"; to: 1; duration: Motion.standard; easing.type: Motion.easeStandard }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Recording " + ScreenRec.source + " in…"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 10.5 * root.s
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: cancelText.implicitWidth + 20 * root.s
                    height: 22 * root.s
                    radius: 8 * root.s
                    color: cancelArea.containsMouse ? Colors.surface_container_highest : "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Colors.on_surface, 0.08)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel recording"
                    Accessible.focusable: true
                    Accessible.onPressAction: ScreenRec.cancel()

                    Text {
                        id: cancelText
                        anchors.centerIn: parent
                        text: "CANCEL"
                        color: Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 1 * root.s
                    }

                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ScreenRec.cancel()
                    }
                }
            }

            // Running — the clock, what it is capturing, and the transport.
            Item {
                anchors.fill: parent
                opacity: root.recording ? 1 : 0
                visible: opacity > 0.01
                enabled: root.recording
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(Colors.error_container, 0.5)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 22 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14 * root.s

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30 * root.s
                        height: width

                        // Ripple off the dot while live; gone while paused.
                        Rectangle {
                            id: halo
                            anchors.centerIn: parent
                            width: parent.width
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 2 * root.s
                            border.color: Colors.error
                            opacity: 0
                            ParallelAnimation {
                                running: root.recording && !ScreenRec.paused && root.open && !Motion.reduceMotion
                                loops: Animation.Infinite
                                NumberAnimation {
                                    target: halo; property: "scale"; from: 0.45; to: 1.15
                                    duration: Motion.pulse * 3
                                    easing.type: Motion.easeBezier; easing.bezierCurve: Motion.emphasizedDecel
                                }
                                NumberAnimation {
                                    target: halo; property: "opacity"; from: 0.7; to: 0
                                    duration: Motion.pulse * 3
                                    easing.type: Motion.easeBezier; easing.bezierCurve: Motion.emphasizedDecel
                                }
                            }
                        }

                        Rectangle {
                            id: recDot
                            anchors.centerIn: parent
                            width: 14 * root.s
                            height: width
                            // Paused: the dot squares off into a held state.
                            radius: ScreenRec.paused ? 3 * root.s : width / 2
                            color: ScreenRec.paused ? Colors.on_surface_variant : Colors.error
                            Behavior on radius { NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2 * root.s

                        Text {
                            text: ScreenRec.elapsedText
                            color: Colors.on_error_container
                            font.family: Appearance.font.family
                            font.pixelSize: 28 * root.s
                            font.weight: Font.ExtraBold
                            font.letterSpacing: -0.5 * root.s
                            font.features: ({ "tnum": 1 })
                        }

                        Text {
                            text: ScreenRec.paused ? "PAUSED · " + root.takeLabel : root.takeLabel
                            color: Qt.alpha(Colors.on_error_container, 0.72)
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.9 * root.s
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 16 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8 * root.s

                    TransportButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: ScreenRec.cap.pause
                        icon: ScreenRec.paused ? "play" : "pause"
                        onActivated: ScreenRec.togglePause()
                    }

                    // Stop: the one filled control on the panel.
                    Rectangle {
                        id: stopBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: stopRow.implicitWidth + 32 * root.s
                        height: 44 * root.s
                        radius: stopArea.pressed ? 14 * root.s : height / 2
                        color: stopArea.containsMouse ? Qt.lighter(Colors.error, 1.1) : Colors.error
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on radius { NumberAnimation { duration: Motion.glide; easing.type: Motion.easeBezier; easing.bezierCurve: Motion.expressiveFastSpatial } }

                        Accessible.role: Accessible.Button
                        Accessible.name: "Stop recording"
                        Accessible.focusable: true
                        Accessible.onPressAction: ScreenRec.stop()

                        Row {
                            id: stopRow
                            anchors.centerIn: parent
                            spacing: 8 * root.s
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 11 * root.s
                                height: width
                                radius: 2.5 * root.s
                                color: Colors.on_error
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Stop"
                                color: Colors.on_error
                                font.family: Appearance.font.family
                                font.pixelSize: 12 * root.s
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: stopArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ScreenRec.stop()
                        }
                    }
                }
            }

            // Failure — whatever the recorder said on its way out.
            Item {
                anchors.fill: parent
                opacity: root.showError ? 1 : 0
                visible: opacity > 0.01
                enabled: root.showError
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

                Rectangle {
                    anchors.fill: parent
                    radius: 13 * root.s
                    color: Qt.alpha(Colors.error, 0.06)
                    border.width: 1
                    border.color: Qt.alpha(Colors.error, 0.2)
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16 * root.s
                    anchors.rightMargin: 16 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.s

                    Text {
                        text: root.noBackend ? "No recorder installed" : "Recording failed"
                        color: Colors.error
                        font.family: Appearance.font.family
                        font.pixelSize: 11 * root.s
                        font.weight: Font.Bold
                    }

                    Text {
                        width: parent.width
                        text: root.errorText
                        color: Qt.alpha(Colors.on_surface_variant, 0.9)
                        font.family: root.noBackend ? Appearance.font.family : Appearance.font.mono
                        font.pixelSize: root.noBackend ? 10 * root.s : 9 * root.s
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 3
                    }

                    Rectangle {
                        width: dismissText.implicitWidth + 20 * root.s
                        height: 20 * root.s
                        radius: 8 * root.s
                        color: dismissArea.containsMouse ? Colors.surface_container_highest : "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colors.on_surface, 0.08)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Accessible.role: Accessible.Button
                        Accessible.name: root.noBackend ? "Re-scan for a recorder" : "Dismiss error"
                        Accessible.focusable: true
                        Accessible.onPressAction: {
                            if (!ScreenRec.available)
                                ScreenRec.rescan();
                            ScreenRec.error = "";
                        }

                        Text {
                            id: dismissText
                            anchors.centerIn: parent
                            text: root.noBackend ? "RE-SCAN" : "DISMISS"
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * root.s
                            font.weight: Font.Bold
                            font.letterSpacing: 1 * root.s
                        }

                        MouseArea {
                            id: dismissArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!ScreenRec.available)
                                    ScreenRec.rescan();
                                ScreenRec.error = "";
                            }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 10 * root.s }

        // ── video settings, in one tonal card ───────────────────────────────
        Rectangle {
            width: parent.width
            height: setCol.implicitHeight + 8 * root.s
            radius: 22 * root.s
            color: Colors.surface_container_high

            Column {
                id: setCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18 * root.s
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter

                OptionRow {
                    label: "Frame rate"
                    supported: ScreenRec.cap.fps

                    SettingsSeg {
                        s: root.s
                        options: root.fpsOptions
                        value: Flags.recordFps
                        onPicked: (v) => Flags.recordFps = v
                    }
                }

                OptionRow {
                    label: "Quality"
                    supported: ScreenRec.cap.quality

                    SettingsSeg {
                        s: root.s
                        options: root.qualityOptions
                        value: Flags.recordQuality
                        onPicked: (v) => Flags.recordQuality = v
                    }
                }
            }
        }

        Item { width: 1; height: 8 * root.s }

        // ── what goes into the take besides pixels ──────────────────────────
        Row {
            id: capRow
            width: parent.width
            spacing: 8 * root.s
            readonly property real tileW: (capRow.width - 2 * capRow.spacing) / 3

            CaptureTile {
                width: capRow.tileW
                icon: "speaker"
                offIcon: "speaker-off"
                label: "Desktop"
                on: Flags.recordDesktop
                onToggled: Flags.recordDesktop = !Flags.recordDesktop
            }
            CaptureTile {
                width: capRow.tileW
                icon: "mic"
                offIcon: "mic-off"
                label: "Mic"
                on: Flags.recordMic
                onToggled: Flags.recordMic = !Flags.recordMic
            }
            CaptureTile {
                width: capRow.tileW
                icon: "cursor"
                label: "Cursor"
                on: Flags.recordCursor
                supported: ScreenRec.cap.cursor
                onToggled: Flags.recordCursor = !Flags.recordCursor
            }
        }

        Item { width: 1; height: 14 * root.s }

        // ── action row: countdown · save folder · record ────────────────────
        Row {
            id: actRow
            width: parent.width
            spacing: 8 * root.s

            /**
             * Countdown as one chip: click steps forward through Off/3/5/10,
             * right-click steps back. It sits beside Record because it only
             * changes what happens when Record is pressed.
             */
            ActionChip {
                id: countChip
                icon: "stopwatch"
                label: Flags.recordCountdown > 0 ? Flags.recordCountdown + "s" : "Off"
                Accessible.name: "Countdown"
                Accessible.description: label + " — tap to change"
                onActivated: (button) => {
                    const opts = root.countdownOptions;
                    let i = 0;
                    for (let k = 0; k < opts.length; k++)
                        if (opts[k].value === Flags.recordCountdown)
                            i = k;
                    const step = button === Qt.RightButton ? opts.length - 1 : 1;
                    Flags.recordCountdown = opts[(i + step) % opts.length].value;
                }
            }

            // Save folder, or the newest take once there is one this session.
            ActionChip {
                id: saveChip
                readonly property bool hasTake: ScreenRec.lastFile.length > 0
                icon: saveChip.hasTake ? "play" : "download"
                label: saveChip.hasTake ? "Last take"
                    : ScreenRec.dir.replace(/\/+$/, "").split("/").pop()
                maxLabelWidth: 90 * root.s
                Accessible.name: saveChip.hasTake ? "Open last recording" : "Open recordings folder"
                Accessible.description: ScreenRec.dir.replace(Quickshell.env("HOME"), "~")
                onActivated: (button) => {
                    if (saveChip.hasTake && button !== Qt.RightButton)
                        ScreenRec.openLast();
                    else
                        ScreenRec.openFolder();
                }
            }

            /**
             * The one filled control while idle. Closes the surface first: it
             * must be off-screen before the encoder opens, or the shell records
             * its own UI (and the window/region pickers grab the pointer).
             */
            Rectangle {
                id: recBtn
                readonly property bool live: !root.recording && !root.arming && !root.showError
                readonly property bool usable: recBtn.live && ScreenRec.available && !root.picking
                readonly property string srcLabel: {
                    for (let i = 0; i < root.sources.length; i++)
                        if (root.sources[i].key === Flags.recordSource)
                            return root.sources[i].label.toLowerCase();
                    return Flags.recordSource;
                }
                width: actRow.width - countChip.width - saveChip.width - 2 * actRow.spacing
                height: 52 * root.s
                radius: recArea.pressed ? 16 * root.s : height / 2
                color: recArea.containsMouse && recBtn.usable ? Qt.lighter(Colors.error, 1.08) : Colors.error
                opacity: recBtn.live ? (ScreenRec.available ? 1 : 0.38) : 0.38
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on radius {
                    NumberAnimation {
                        duration: Motion.glide
                        easing.type: Motion.easeBezier
                        easing.bezierCurve: Motion.expressiveFastSpatial
                    }
                }

                function go() {
                    if (!recBtn.usable)
                        return;
                    root.requestClose();
                    ScreenRec.start(Flags.recordSource);
                }

                Accessible.role: Accessible.Button
                Accessible.name: "Start recording " + Flags.recordSource
                Accessible.focusable: recBtn.usable
                Accessible.onPressAction: recBtn.go()

                Row {
                    anchors.centerIn: parent
                    spacing: 10 * root.s

                    // Record mark: a ring around a dot that swells on hover.
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18 * root.s
                        height: width

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 2 * root.s
                            border.color: Colors.on_error
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: (recArea.containsMouse && recBtn.usable ? 10 : 8) * root.s
                            height: width
                            radius: width / 2
                            color: Colors.on_error
                            Behavior on width {
                                NumberAnimation {
                                    duration: Motion.glide
                                    easing.type: Motion.easeBezier
                                    easing.bezierCurve: Motion.expressiveFastSpatial
                                }
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Record " + recBtn.srcLabel
                        color: Colors.on_error
                        font.family: Appearance.font.family
                        font.pixelSize: 13 * root.s
                        font.weight: Font.Bold
                    }
                }

                MouseArea {
                    id: recArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: recBtn.usable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: recBtn.go()
                }
            }
        }
    }
}
