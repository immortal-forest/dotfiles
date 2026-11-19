import QtQuick
import "../../colors"
import "../../services"

/**
 * astralis — Retroact Rain, drawn: one ShaderEffect (shaders/retroact.frag)
 * over the wallpaper. A plain Item so RainLayer can host it full-screen and a
 * dev harness can grabToImage it offscreen.
 *
 * Every drop is the same glass bead refracting the wallpaper, stretched along
 * its motion: thin needles falling, round beads hanging, tall bubbles rising
 * (the open-world footage; never splash crowns). The back three layers pass
 * behind the wallpaper's depth cut-out, the front one in front of it.
 */
Item {
    id: view

    /** The event clock: RetroactRain, or a harness stand-in with t/travel/vel/sky/level. */
    property var ev
    /** The wallpaper on screen, and its depth cut-out ("" = none yet). */
    property string wallPath: ""
    property string cutPath: ""
    property real dpr: 1

    // ── the look (RainLayer feeds these from Flags; defaults = the approved look) ──
    /** Share of grid cells holding a drop, 0..1. */
    property real density: 0.55
    /** Drop size, × the default. */
    property real sizeMul: 1
    /** Overall opacity, 0..1. */
    property real strength: 1
    /** Highlight colour: "water" (the light on water) or a Colors role name. */
    property string tintRole: "water"
    /** The faint ripples overhead while it rises. */
    property bool skyOn: true
    /** Back drops pass behind the wallpaper's subject (the depth cut-out). */
    property bool behind: true

    // The colour of light on water, not a palette role: highlights tinted by
    // a wallpaper accent read as coloured glass (matched to the reference
    // footage; the look the user approved). Palette tints are opt-in.
    readonly property color waterTint: Qt.rgba(0.90, 0.95, 1.0, 1)
    readonly property color tint: view.tintRole === "water" ? view.waterTint : (Colors[view.tintRole] ?? view.waterTint)

    readonly property bool ready: wallImg.status === Image.Ready

    // The wallpaper whole, at about screen resolution; the shader crops it the
    // way skwd-paper's `fill` does (centred cover), so no screen-sized copy.
    Image {
        id: wallImg
        visible: false
        source: view.width > 0 && view.wallPath.length ? "file://" + view.wallPath : ""
        sourceSize: Qt.size(Math.round(view.width * view.dpr), Math.round(view.height * view.dpr))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
    }

    Image {
        id: cutImg
        visible: false
        source: view.cutPath.length ? "file://" + view.cutPath : ""
        asynchronous: true
        cache: false
        onStatusChanged: {
            if (status === Image.Ready) {
                cutIn.restart();
            } else {
                cutIn.stop();
                view.cutMix = 0;
            }
        }
    }

    /** 0..1: the cut-out eases in once loaded (a new wallpaper's arrives a few s late). */
    property real cutMix: 0
    NumberAnimation {
        id: cutIn
        target: view
        property: "cutMix"
        to: 1
        duration: Motion.largeDur
        easing.type: Motion.easeStandard
    }

    ShaderEffect {
        anchors.fill: parent
        opacity: view.ready && view.ev ? view.ev.level * view.strength : 0
        blending: true
        // bump ?v= with every qsb rebuild: Qt caches shaders by URL
        fragmentShader: Qt.resolvedUrl("shaders/retroact.frag.qsb") + "?v=2"

        property real time: view.ev ? view.ev.t : 0
        property real travel: view.ev ? view.ev.travel : 0
        property real vel: view.ev ? view.ev.vel : 0
        property real aspect: width / Math.max(1, height)
        property real density: view.density
        property real sizeMul: view.sizeMul
        property real sky: view.ev && view.skyOn ? view.ev.sky : 0
        property real cutMix: view.behind ? view.cutMix : 0
        /** Screen uv → wallpaper uv: the share of the image a centred cover crop shows. */
        property vector2d wallScale: {
            var ia = wallImg.implicitWidth / Math.max(1, wallImg.implicitHeight);
            return ia > aspect ? Qt.vector2d(aspect / ia, 1) : Qt.vector2d(1, ia / aspect);
        }
        property color tint: view.tint
        property var wall: wallImg
        property var cut: cutImg
    }
}
