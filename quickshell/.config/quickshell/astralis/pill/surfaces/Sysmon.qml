pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"            // Motion, Flags (and the rest) unqualified
import "../../services" as Services // Sysmon singleton — see below
import "../../config"

/**
 * astralis — 系 SYSTEM surface (ported from Ricelin SysmonSurface.qml): a flat
 * card of live machine vitals fed by the Sysmon singleton. The header carries
 * the kanji, label and uptime. Below it sit flame dials for CPU, GPU and
 * memory load, each a 270deg arc stroked with a burn-to-lit primary gradient
 * on a thread track and rounded caps, the sweep eased over the value change;
 * the centre shows the value, a unit and a sub line (CPU/GPU temperature,
 * memory total). A hairline stripe underneath reports network throughput,
 * root-disk fill, swap and VRAM with their units folded into the faint labels
 * so the values read bare. On a machine with no discrete GPU the GPU dial and
 * VRAM cell drop and the remaining dials recentre. Polling lives in the
 * singleton and only runs while this surface is open.
 *
 * The services import is aliased: this file's own type is `Sysmon`
 * (pill/surfaces qmldir), so the singleton must be reached as
 * `Services.Sysmon` to dodge the name collision.
 */
PillSurface {
    id: root

    mTop: 14
    mLeft: 16
    mRight: 16
    mBottom: 16

    implicitHeight: content.implicitHeight

    readonly property var dialKeys: Services.Sysmon.hasGpu ? ["cpu", "gpu", "mem"] : ["cpu", "mem"]
    readonly property var cellKeys: Services.Sysmon.hasVram ? ["net", "disk", "swap", "vram"] : ["net", "disk", "swap"]

    onActiveChanged: Services.Sysmon.open = active

    /**
     * The soul ember rests with the 系 header kanji: the kanji is the lantern,
     * the bead its flame, hovering just above the glyph with its wick rising into
     * it. Anchored to the header rather than the dial row so the ember sits in the
     * same deliberate spot whether three dials or two are shown (the header never
     * changes with GPU presence). With glyphs off the kanji is hidden, so the
     * anchor falls back to the SYSTEM label's left edge, vertically centred on the
     * header, and never floats. Mapped into surface-local space so the host can
     * offset it by the surface origin.
     */
    readonly property point soulPoint: {
        void root.width;
        void root.height;
        if (Flags.showGlyphs)
            return kanji.mapToItem(root, kanji.width / 2, -3 * root.s);
        return sysLabel.mapToItem(root, -8 * root.s, sysLabel.height / 2);
    }

    ameForm: open ? "soul" : "off"
    amePoint: soulPoint

    component Dial: Item {
        id: dial

        property real arc: 0
        property string big: ""
        property string unit: ""
        property string sub: ""
        property string label: ""
        property bool shrink: false

        property real display: 0
        onArcChanged: display = arc
        Component.onCompleted: display = arc
        onDisplayChanged: face.requestPaint()
        Behavior on display { NumberAnimation { duration: Math.round(700 * Motion.mult); easing.type: Motion.easeStandard } }

        width: 110 * root.s
        height: 110 * root.s

        Canvas {
            id: face
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var cx = width / 2;
                var cy = height / 2;
                var lw = 8 * root.s;
                var r = Math.min(width, height) / 2 - lw / 2 - root.s;
                var start = 135 * Math.PI / 180;
                var full = 270 * Math.PI / 180;
                ctx.lineCap = "round";
                ctx.lineWidth = lw;
                ctx.strokeStyle = Qt.alpha(Colors.on_surface, 0.13);
                ctx.beginPath();
                ctx.arc(cx, cy, r, start, start + full, false);
                ctx.stroke();
                var v = Math.max(0, Math.min(100, dial.display));
                if (v > 0.5) {
                    var diag = r * 0.7071;
                    var grad = ctx.createLinearGradient(cx - diag, cy + diag, cx + diag, cy - diag);
                    // Canvas gradient stops take hex STRINGS, not color values
                    // (a translucent color serializes to #aarrggbb and corrupts
                    // the gradient); both stops here are opaque roles.
                    grad.addColorStop(0, String(Qt.darker(Colors.primary_container, 1.1)));
                    grad.addColorStop(0.35, String(Qt.darker(Colors.primary_container, 1.1)));
                    grad.addColorStop(1, String(Colors.primary));
                    ctx.strokeStyle = grad;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, start, start + full * v / 100, false);
                    ctx.stroke();
                }
            }
        }

        // A Canvas doesn't observe Colors, so a palette swap leaves the arc
        // painted in the old roles until the next value change. Repaint it when
        // any role the arc uses (track + gradient) changes.
        Connections {
            target: Colors
            function onPrimaryChanged() { face.requestPaint(); }
            function onPrimary_containerChanged() { face.requestPaint(); }
            function onOn_surfaceChanged() { face.requestPaint(); }
        }

        /**
         * The big value owns the dial's exact centre so it reads as the focal
         * number whatever its width, with the label and sub line stacked
         * directly beneath it; centring the value rather than the whole column
         * means a one- or three-digit value never drifts off the eye line.
         */
        Row {
            id: bigRow
            anchors.centerIn: parent
            /** Ring gap is at the bottom, so its optical middle sits above the hole centre; lift the value there. */
            anchors.verticalCenterOffset: -12 * root.s
            spacing: 1 * root.s

            Text {
                id: bigText
                text: dial.big
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: (dial.shrink ? 16 : 20) * root.s
                font.weight: Font.ExtraBold
                font.letterSpacing: -0.5 * root.s
                font.features: ({ "tnum": 1 })
            }
            Text {
                anchors.baseline: bigText.baseline
                visible: dial.unit.length > 0
                text: dial.unit
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 11 * root.s
                font.weight: Font.Bold
            }
        }

        Column {
            anchors.top: bigRow.bottom
            anchors.topMargin: 3 * root.s
            anchors.horizontalCenter: bigRow.horizontalCenter
            spacing: 3 * root.s

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.label
                color: Qt.alpha(Colors.on_surface_variant, 0.65)
                font.family: Appearance.font.family
                font.pixelSize: 8.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1 * root.s
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.sub
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
            }
        }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        spacing: 0

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
                    text: "系"
                    color: Colors.on_surface
                    font.family: Appearance.font.jp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    id: sysLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SYSTEM"
                    color: Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.8 * root.s
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Services.Sysmon.uptime
                color: Qt.alpha(Colors.on_surface_variant, 0.8)
                font.family: Appearance.font.family
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1 * root.s
                font.features: ({ "tnum": 1 })
            }
        }

        Item { width: 1; height: 16 * root.s }

        Item {
            width: parent.width
            height: 110 * root.s

            Repeater {
                model: root.dialKeys

                Dial {
                    required property int index
                    required property var modelData
                    readonly property string key: modelData
                    readonly property int val: key === "cpu" ? Services.Sysmon.cpu : key === "gpu" ? Services.Sysmon.gpu : Services.Sysmon.memPct

                    x: root.dialKeys.length > 1
                        ? index * (parent.width - width) / (root.dialKeys.length - 1)
                        : (parent.width - width) / 2

                    arc: val
                    big: key === "mem" ? Services.Sysmon.memUsedGb.toFixed(1) : "" + val
                    unit: key === "mem" ? "" : "%"
                    shrink: key !== "mem" && val >= 100
                    label: key
                    sub: key === "cpu" ? (Services.Sysmon.cpuTemp >= 0 ? Services.Sysmon.cpuTemp + "°" : "")
                        : key === "gpu" ? (Services.Sysmon.gpuTemp >= 0 ? Services.Sysmon.gpuTemp + "°" : "")
                        : "/ " + Services.Sysmon.memTotalGb.toFixed(0) + " GB"
                }
            }
        }

        Item { width: 1; height: 18 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.on_surface, 0.06)
        }

        Item { width: 1; height: 13 * root.s }

        Item {
            width: parent.width
            height: 30 * root.s

            Repeater {
                model: root.cellKeys

                Item {
                    id: cell
                    required property int index
                    required property var modelData
                    readonly property string key: modelData

                    width: parent.width / root.cellKeys.length
                    height: parent.height
                    x: index * width

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: 2 * root.s
                        anchors.bottomMargin: 2 * root.s
                        height: parent.height - 4 * root.s
                        width: 1
                        visible: cell.index > 0
                        color: Qt.alpha(Colors.on_surface, 0.04)
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6 * root.s

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: cell.key === "net" ? "Net · MB/s"
                                : cell.key === "disk" ? "Disk · %"
                                : cell.key === "swap" ? "Swap · GB"
                                : "VRAM · GB"
                            color: Qt.alpha(Colors.on_surface_variant, 0.65)
                            font.family: Appearance.font.family
                            font.pixelSize: 8 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.9 * root.s
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8 * root.s
                            visible: cell.key === "net"

                            Text {
                                text: "↓" + Services.Sysmon.netDown.toFixed(1)
                                color: Colors.on_surface
                                font.family: Appearance.font.family
                                font.pixelSize: 13 * root.s
                                font.weight: Font.ExtraBold
                                font.features: ({ "tnum": 1 })
                            }
                            Text {
                                text: "↑" + Services.Sysmon.netUp.toFixed(1)
                                color: Colors.primary
                                font.family: Appearance.font.family
                                font.pixelSize: 13 * root.s
                                font.weight: Font.ExtraBold
                                font.features: ({ "tnum": 1 })
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: cell.key !== "net"
                            text: cell.key === "disk" ? "" + Services.Sysmon.diskPct
                                : cell.key === "swap" ? Services.Sysmon.swapUsedGb.toFixed(1)
                                : Services.Sysmon.vramUsedGb.toFixed(1) + " / " + Services.Sysmon.vramTotalGb.toFixed(0)
                            color: Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 13 * root.s
                            font.weight: Font.ExtraBold
                            font.features: ({ "tnum": 1 })
                        }
                    }
                }
            }
        }
    }
}
