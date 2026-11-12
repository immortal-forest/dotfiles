pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "../../colors"
import "../../services"

/**
 * astralis — the full-screen visualizer's surface (see Visualizer.qml): one
 * transparent, click-through WlrLayer.Bottom window covering the screen, with
 * three GPU Shapes per edge path — backmost the lower ridge (other spectrum
 * arrangement, 0.65 amp, deeper gradient, 0.5 alpha), then the main wave's
 * stretched shadow (0.25 alpha), then the main wave. Path strings are rebuilt
 * whenever the scope's `levels` change (cava's 30fps).
 */
PanelWindow {
    id: vizLayer

    required property var viz

    screen: viz.screen
    color: "transparent"
    mask: Region {}

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "astralis-viz"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    readonly property bool cycling: Flags.vizColorCycle
    readonly property real ph: viz.cyclePhase
    readonly property var mainStops: cycling
        ? [viz.ringColor(ph), viz.ringColor(ph + 0.5), viz.ringColor(ph + 1)]
        : [Colors.primary, Colors.tertiary, Colors.secondary]
    readonly property var lowStops: cycling
        ? [viz.ringColor(ph + 2), viz.ringColor(ph + 2.5), viz.ringColor(ph + 3)]
        : [Colors.tertiary, Colors.tertiary_container, Colors.secondary]

    component WavePass: Shape {
        id: pass
        property var path
        property var stops
        property string d
        readonly property var vs: pass.path.verts
        // Straight edge: gradient runs along it (as the original did).
        // Bent / looped: conical sweep round the screen centre,
        // symmetric so there's no seam and colours mirror like the data.
        readonly property bool bent: vs.length > 2

        anchors.fill: parent
        // Geometry renderer, triangulated on a worker thread: the path changes
        // 30×/s, and CurveRenderer's per-change preprocessing ran on the GUI
        // thread (it slowed every other surface, e.g. opening Settings).
        preferredRendererType: Shape.GeometryRenderer
        asynchronous: true
        antialiasing: true

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillRule: pass.path.closed ? ShapePath.OddEvenFill : ShapePath.WindingFill
            fillGradient: pass.bent ? conical : linear
            PathSvg { path: pass.d }
        }

        LinearGradient {
            id: linear
            x1: pass.vs[0].x; y1: pass.vs[0].y
            x2: pass.vs[pass.vs.length - 1].x; y2: pass.vs[pass.vs.length - 1].y
            GradientStop { position: 0.0; color: pass.stops[0] }
            GradientStop { position: 0.5; color: pass.stops[1] }
            GradientStop { position: 1.0; color: pass.stops[2] }
        }
        ConicalGradient {
            id: conical
            centerX: vizLayer.viz.sw / 2
            centerY: vizLayer.viz.sh / 2
            angle: 270
            GradientStop { position: 0.0; color: pass.stops[0] }
            GradientStop { position: 0.25; color: pass.stops[1] }
            GradientStop { position: 0.5; color: pass.stops[2] }
            GradientStop { position: 0.75; color: pass.stops[1] }
            GradientStop { position: 1.0; color: pass.stops[0] }
        }
    }

    /** Everything drawn (a plain Item so a dev harness can grabToImage it). */
    readonly property Item drawItem: drawRoot

    Item {
        id: drawRoot
        anchors.fill: parent
        // Gated on OPACITY (never visible) so the Shapes keep painting.
        opacity: vizLayer.viz.fade

        Repeater {
            model: vizLayer.viz.paths

            Item {
                id: pathItem
                required property var modelData
                anchors.fill: parent

                readonly property var levels: vizLayer.viz.levels
                readonly property var mainData: vizLayer.viz.arrange(levels, modelData.sym, false)
                readonly property var lowData: vizLayer.viz.arrange(levels, modelData.sym, true)

                WavePass {
                    path: pathItem.modelData
                    opacity: 0.5
                    stops: vizLayer.lowStops
                    d: vizLayer.viz.svgFor(pathItem.modelData, pathItem.lowData, 0.65, 1)
                }
                WavePass {
                    path: pathItem.modelData
                    opacity: 0.25
                    stops: vizLayer.mainStops
                    d: vizLayer.viz.svgFor(pathItem.modelData, pathItem.mainData, 1.05, 1.02)
                }
                WavePass {
                    path: pathItem.modelData
                    stops: vizLayer.mainStops
                    d: vizLayer.viz.svgFor(pathItem.modelData, pathItem.mainData, 1, 1)
                }
            }
        }
    }
}
