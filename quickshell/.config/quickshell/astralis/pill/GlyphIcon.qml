import QtQuick
import QtQuick.Shapes
import "lib/glyphs.js" as Glyphs
import "../colors"

/**
 * astralis — self-contained vector glyph (ported from Ricelin GlyphIcon.qml),
 * drawn from baked SVG path data so the pill never depends on the system icon
 * theme or external asset files. Set `name` to pick a glyph, `color` to tint
 * it; stroked glyphs use `stroke` width, filled glyphs (media transport) paint
 * solid. Paths live in a 24x24 space and scale to the item's size. Each
 * glyph's actual bounding box is centred within the item on both axes, so
 * glyphs with differing path extents share one optical baseline.
 */
Item {
    id: root

    property string name: ""
    property color color: Colors.on_surface_variant
    property real stroke: 1.8

    readonly property real u: Math.min(width, height) / 24

    // Glyph path data lives in the shared `lib/glyphs.js` library module so the
    // ~60-entry map is allocated once for the whole shell, not per instance.
    readonly property var g: Glyphs.glyphs[name] !== undefined ? Glyphs.glyphs[name] : ({ d: "", fill: false })

    Shape {
        id: glyph

        width: 24
        height: 24
        scale: root.u
        transformOrigin: Item.TopLeft
        x: glyph.boundingRect.width > 0
           ? root.width / 2 - (glyph.boundingRect.x + glyph.boundingRect.width / 2) * root.u
           : (root.width - 24 * root.u) / 2
        y: glyph.boundingRect.height > 0
           ? root.height / 2 - (glyph.boundingRect.y + glyph.boundingRect.height / 2) * root.u
           : (root.height - 24 * root.u) / 2
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.g.fill ? "transparent" : root.color
            fillColor: root.g.fill ? root.color : "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.g.d }
        }
    }
}
