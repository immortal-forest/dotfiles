import QtQuick
import "../colors"
import "../services"
import "../config"

/**
 * astralis — shared morph-surface base (ported from Ricelin PillSurface.qml,
 * plus an optional title header). Each surface fills the pill body inset by
 * its own margins (scaled by `s`), fades in with the morph as the pill nears
 * full openness, and is only enabled while open. The host (Pill.qml's Loaders)
 * sets `s`, `open` and `morphCloseness`; the surface sets its margins, an
 * optional `title` (which renders a header row with a close button), and its
 * body as default children (routed into the content item below the header).
 *
 * `ameForm`/`amePoint` are the soul-bead hooks: each surface declares the
 * flame's form and dock point in surface-local coords; Stage 6 maps them into
 * pill space. Declared here so surfaces can bind them now.
 */
Item {
    id: surface

    // ── host-set ────────────────────────────────────────────────────────────
    property real s: 1
    property bool open: false
    property real morphCloseness: 1

    // ── surface-owned chrome ────────────────────────────────────────────────
    property real mTop: Appearance.padding.surface
    property real mLeft: Appearance.padding.surface
    property real mRight: Appearance.padding.surface
    property real mBottom: Appearance.padding.surface
    property string title: ""

    signal requestClose()

    // Soul-bead hooks (consumed by Stage 6; surfaces re-bind them).
    property string ameForm: "off"
    property point amePoint: Qt.point(width / 2, height / 2)

    readonly property bool active: open
    default property alias content: contentItem.data

    /**
     * Latched true once the open morph has first settled. The morphCloseness
     * gate only serves the rest-to-surface open fade; a relayout inside an
     * open surface also jumps the pill's target geometry, which would crater
     * closeness and dim the whole surface for a frame. After first settle,
     * hold full opacity and let the body morph alone do the reveal. Reset on
     * close so the next open still fades in.
     */
    property bool settled: false
    onOpenChanged: if (!open) settled = false
    onMorphClosenessChanged: if (open && morphCloseness > 0.92) settled = true

    anchors.fill: parent
    anchors.topMargin: mTop * s
    anchors.leftMargin: mLeft * s
    anchors.rightMargin: mRight * s
    anchors.bottomMargin: mBottom * s

    enabled: open
    opacity: open ? (settled ? 1 : Math.pow(morphCloseness, 1.3)) : 0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
    }

    // ── header (only when the surface names itself) ─────────────────────────
    Item {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: surface.title.length > 0 ? 26 * surface.s : 0
        visible: surface.title.length > 0

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: surface.title
            color: Colors.on_surface
            font.family: Appearance.font.family
            font.pixelSize: Appearance.font.sizeL * surface.s
            font.weight: Font.DemiBold
        }

        Item {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 26 * surface.s
            height: 26 * surface.s

            // Every surface in the shell wears this ×, so it is the most-pressed
            // button in the rice — it dips on press like the rest of them. The
            // dip lives on the wrapper so the disc and the glyph travel
            // together; 0.92 is the small-round-target depth.
            // The one control present on every surface in the shell, so it is
            // also the one a screen-reader user will meet most often.
            Accessible.role: Accessible.Button
            Accessible.name: "Close"
            Accessible.description: surface.title.length > 0 ? "Close " + surface.title : "Close this surface"
            Accessible.onPressAction: surface.requestClose()

            scale: closeArea.pressed ? 0.92 : 1
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.glide
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveFastSpatial
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: closeArea.containsMouse ? Colors.surface_container_highest : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            GlyphIcon {
                anchors.centerIn: parent
                width: Appearance.font.sizeL * surface.s
                height: Appearance.font.sizeL * surface.s
                name: "close"
                stroke: 1.8
                color: closeArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                // The disc behind it fades; without this the glyph snapped.
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: surface.requestClose()
            }
        }
    }

    // ── body — default children land here, inset below the header ──────────
    Item {
        id: contentItem
        anchors.top: headerRow.bottom
        anchors.topMargin: surface.title.length > 0 ? Appearance.spacing.s * surface.s : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
}
