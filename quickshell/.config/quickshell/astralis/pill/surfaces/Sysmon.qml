pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../colors"
import "../../services"            // Motion, Flags (and the rest) unqualified
import "../../services" as Services // Sysmon singleton — see below
import "../../config"
import "../m3"

/**
 * astralis — 系 SYSTEM surface. Header: kanji, label, uptime. Then the
 * machine as three 円相 enso — CPU, GPU, memory — each one brush circle
 * (InkRing: the 筆 stroke of the Media/lock/battery ink bent round a ring)
 * whose length is the load, its ink running warm → hot along the track
 * (tertiary → primary → error) so the head's hue reads the level. Inside:
 * the value, its name, and the temperature (memory: the total); a reading at
 * 90° or over turns the error role. Under each ring the one figure that
 * belongs to that part: CPU load average, GPU VRAM, memory's swap.
 *
 * Under a hairline, M3 Expressive linear indicators (M3Progress): download
 * and upload each a wavy bar — the wave is M3's "work in flight" tell, so
 * an idle link lies flat and traffic ripples — filled on a log scale from
 * 1 KB/s to 100 MB/s so browsing and a big pull both read; the root disk a
 * flat bar (a static measurement), its value over it. All three keep the
 * spec's gap and stop dot. (Was a live waveform: at idle it was a bare line
 * across most of the strip.)
 *
 * Was: three geometric 270° arcs plus a strip of four bare numbers, the
 * surface's one shape repeated; the regrouping puts VRAM under the GPU and
 * swap under memory instead of in an unrelated row. On a machine with no
 * discrete GPU the GPU ring drops and the rest recentre. Polling lives in
 * the singleton and only runs while this surface is open.
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

    readonly property var ringKeys: Services.Sysmon.hasGpu ? ["cpu", "gpu", "mem"] : ["cpu", "mem"]
    readonly property color faint: Qt.alpha(Colors.on_surface_variant, 0.65)

    onActiveChanged: Services.Sysmon.open = active

    /**
     * The soul ember rests with the 系 header kanji: the kanji is the lantern,
     * the bead its flame, sitting a bead's diameter BELOW the glyph box with its
     * wick rising back up into the strokes (Ame paints under the surface, so the
     * glyph occludes the wick's faint tail — exactly how the pill's own hover
     * ember hangs under a status icon). It used to sit 3*s ABOVE the glyph, where
     * the ~11.3*s wick ran straight off the pill's top edge and left a bare dot
     * glued to the border. Anchored to the header rather than the dial row so the
     * ember sits in the same deliberate spot whether three dials or two are shown
     * (the header never changes with GPU presence). With glyphs off the kanji is
     * hidden, so the anchor falls back to the SYSTEM label's left edge, vertically
     * centred on the header, and never floats. Mapped into surface-local space so
     * the host can offset it by the surface origin.
     */
    readonly property point soulPoint: {
        void root.width;
        void root.height;
        if (Flags.showGlyphs)
            return kanji.mapToItem(root, kanji.width / 2, kanji.height + 6 * root.s);
        return sysLabel.mapToItem(root, -8 * root.s, sysLabel.height / 2);
    }

    ameForm: open ? "soul" : "off"
    amePoint: soulPoint

    /** One enso with its readings inside and the part's extra figure under it. */
    component Vital: Item {
        id: vital

        property string key: ""
        property real level: 0
        property string big: ""
        property string unit: ""
        property string label: ""
        property string sub: ""
        property color subColor: Colors.on_surface_variant
        property string capLabel: ""
        property string capValue: ""

        width: 120 * root.s
        height: enso.height + 6 * root.s + capRow.height

        InkRing {
            id: enso
            anchors.horizontalCenter: parent.horizontalCenter
            width: 102 * root.s
            height: 102 * root.s
            s: root.s
            // draws in once the open morph settles, like every surface's content
            frac: root.settled ? vital.level : 0
            inkStops: [Colors.tertiary, Colors.primary, Colors.error]
            paper: Colors.surface_container
        }

        // The value owns the ring's optical centre (lifted: the open mouth is
        // at the bottom), name and temperature stacked under it.
        Row {
            id: bigRow
            anchors.horizontalCenter: enso.horizontalCenter
            anchors.verticalCenter: enso.verticalCenter
            anchors.verticalCenterOffset: -9 * root.s
            spacing: 1 * root.s
            Text {
                id: bigText
                text: vital.big
                color: Colors.on_surface
                font.family: Appearance.font.family
                font.pixelSize: (vital.big.length > 3 ? 19 : 22) * root.s
                font.weight: Font.ExtraBold
                font.letterSpacing: -0.5 * root.s
                font.features: ({ "tnum": 1 })
            }
            Text {
                anchors.baseline: bigText.baseline
                text: vital.unit
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Bold
            }
        }
        Column {
            anchors.top: bigRow.bottom
            anchors.topMargin: 1 * root.s
            anchors.horizontalCenter: enso.horizontalCenter
            spacing: 2 * root.s
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: vital.label
                color: root.faint
                font.family: Appearance.font.family
                font.pixelSize: 8.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2 * root.s
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text.length > 0
                text: vital.sub
                color: vital.subColor
                font.family: Appearance.font.family
                font.pixelSize: 10 * root.s
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
            }
        }

        Row {
            id: capRow
            anchors.top: enso.bottom
            anchors.topMargin: 6 * root.s
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5 * root.s
            opacity: vital.capValue.length ? 1 : 0
            Text {
                anchors.baseline: capVal.baseline
                text: vital.capLabel
                color: root.faint
                font.family: Appearance.font.family
                font.pixelSize: 8.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1 * root.s
            }
            Text {
                id: capVal
                text: vital.capValue
                color: Colors.on_surface_variant
                font.family: Appearance.font.family
                font.pixelSize: 10.5 * root.s
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
            }
        }
    }

    /** ↓ / ↑ rate line: arrow glyph, value, unit. */
    component Rate: Row {
        id: rate
        property string glyph: "arrow-down"
        property real mbps: 0
        property color tint: Colors.on_surface
        spacing: 2 * root.s
        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 13 * root.s
            height: 13 * root.s
            name: rate.glyph
            color: rate.tint
            stroke: 1.8
        }
        Text {
            id: rateVal
            anchors.verticalCenter: parent.verticalCenter
            text: Services.Sysmon.fmtNet(rate.mbps)
            color: rate.tint
            font.family: Appearance.font.family
            font.pixelSize: 12.5 * root.s
            font.weight: Font.ExtraBold
            font.features: ({ "tnum": 1 })
        }
        Text {
            anchors.baseline: rateVal.baseline
            leftPadding: 1 * root.s
            text: Services.Sysmon.netUnit
            color: root.faint
            font.family: Appearance.font.family
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
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
                spacing: 8 * root.s

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
                    font.letterSpacing: 1.6 * root.s
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

        Item { width: 1; height: 8 * root.s }

        Item {
            width: parent.width
            height: 102 * root.s + 6 * root.s + 14 * root.s

            Repeater {
                model: root.ringKeys

                Vital {
                    required property int index
                    required property var modelData
                    readonly property var sm: Services.Sysmon
                    readonly property int temp: modelData === "cpu" ? sm.cpuTemp : modelData === "gpu" ? sm.gpuTemp : -1

                    key: modelData
                    x: root.ringKeys.length > 1
                        ? index * (parent.width - width) / (root.ringKeys.length - 1)
                        : (parent.width - width) / 2

                    level: (modelData === "cpu" ? sm.cpu : modelData === "gpu" ? sm.gpu : sm.memPct) / 100
                    big: modelData === "mem" ? sm.memUsedGb.toFixed(1) : "" + (modelData === "cpu" ? sm.cpu : sm.gpu)
                    unit: modelData === "mem" ? "GB" : "%"
                    label: modelData
                    sub: modelData === "mem" ? "of " + sm.memTotalGb.toFixed(0) : (temp >= 0 ? temp + "°" : "")
                    subColor: temp >= 90 ? Colors.error : Colors.on_surface_variant
                    capLabel: modelData === "cpu" ? "Load" : modelData === "gpu" ? "VRAM" : "Swap"
                    capValue: modelData === "cpu" ? sm.load1.toFixed(2)
                        : modelData === "gpu" ? (sm.hasVram ? sm.vramUsedGb.toFixed(1) + " / " + sm.fmtGb(sm.vramTotalGb) + " GB" : "")
                        : sm.swapUsedGb.toFixed(1) + " GB"
                }
            }
        }

        Rule {
            width: parent.width
            height: 23 * root.s + 1
        }

        // network (wavy: in flight) + disk (flat: a measurement)
        Item {
            width: parent.width
            height: 34 * root.s

            Column {
                id: net
                anchors.left: parent.left
                anchors.right: disk.left
                anchors.rightMargin: 22 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3 * root.s

                Repeater {
                    model: [
                        { glyph: "arrow-down", up: false },
                        { glyph: "arrow-up", up: true }
                    ]
                    Item {
                        id: netRow
                        required property var modelData
                        readonly property real mbps: modelData.up ? Services.Sysmon.netUp : Services.Sysmon.netDown
                        readonly property color tint: modelData.up ? Colors.tertiary : Colors.primary
                        width: net.width
                        height: 15 * root.s

                        Rate {
                            id: rateText
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 82 * root.s
                            glyph: netRow.modelData.glyph
                            mbps: netRow.mbps
                            tint: netRow.tint
                        }
                        M3Progress {
                            anchors.left: rateText.right
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            s: root.s
                            // log scale, 1 KB/s → 100 MB/s; draws in once settled
                            value: root.settled ? Math.log(1 + netRow.mbps * 1024) / Math.log(1 + 102400) : 0
                            activeColor: netRow.tint
                            trackColor: Qt.alpha(Colors.on_surface, 0.08)
                            accessibleName: (netRow.modelData.up ? "Upload " : "Download ") + Services.Sysmon.fmtNet(netRow.mbps) + " " + Services.Sysmon.netUnit
                        }
                    }
                }
            }

            Column {
                id: disk
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 104 * root.s
                spacing: 6 * root.s

                Item {
                    width: parent.width
                    height: diskVal.height
                    Text {
                        anchors.left: parent.left
                        // Baseline-aligned with the value. diskVal sits in the
                        // Row beside this, out of reach of an anchor (siblings
                        // and parent only: the anchor was dropped with a
                        // warning and the label sat at the top), so bind y.
                        y: diskRow.y + diskVal.y + diskVal.baselineOffset - baselineOffset
                        text: "Disk"
                        color: root.faint
                        font.family: Appearance.font.family
                        font.pixelSize: 8.5 * root.s
                        font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1 * root.s
                    }
                    Row {
                        id: diskRow
                        anchors.right: parent.right
                        spacing: 1 * root.s
                        Text {
                            id: diskVal
                            text: "" + Services.Sysmon.diskPct
                            color: Services.Sysmon.diskPct >= 90 ? Colors.error : Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 12.5 * root.s
                            font.weight: Font.ExtraBold
                            font.features: ({ "tnum": 1 })
                        }
                        Text {
                            anchors.baseline: diskVal.baseline
                            text: "%"
                            color: Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 9.5 * root.s
                            font.weight: Font.Bold
                        }
                    }
                }
                M3Progress {
                    width: parent.width
                    s: root.s
                    wavy: false
                    value: root.settled ? Services.Sysmon.diskPct / 100 : 0
                    activeColor: Services.Sysmon.diskPct >= 90 ? Colors.error : Colors.secondary
                    trackColor: Qt.alpha(Colors.on_surface, 0.08)
                    accessibleName: "Disk " + Services.Sysmon.diskPct + " percent used"
                }
            }
        }
    }
}
