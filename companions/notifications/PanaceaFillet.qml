import QtQuick
import QtQuick.Shapes

// Panacea's flare: the concave corner where a surface that grows out of the
// rail meets the rail's edge, as the rail itself meets the screen's top and
// bottom. It sits on the rail's edge just above the card (below: false) or
// just below it (below: true), `radius` wide and tall, and reaches `overlap`
// into the rail: two windows' edges meeting on a fractional pixel at 1.25
// scale would otherwise leave a faint seam between them.
Shape {
  id: fillet

  property real radius: 12
  property real overlap: 2
  property bool below: false
  property color color: "black"

  width: radius + overlap
  height: radius
  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    fillColor: fillet.color
    strokeWidth: -1

    // Above the card: the corner is bottom-left, the arc's centre top-right.
    // Below it: the corner is top-left, the arc's centre bottom-right.
    startX: 0
    startY: fillet.below ? 0 : fillet.radius
    PathLine { x: 0; y: fillet.below ? fillet.radius : 0 }
    PathLine { x: fillet.overlap; y: fillet.below ? fillet.radius : 0 }
    PathArc {
      x: fillet.overlap + fillet.radius
      y: fillet.below ? 0 : fillet.radius
      radiusX: fillet.radius
      radiusY: fillet.radius
      direction: fillet.below ? PathArc.Clockwise : PathArc.Counterclockwise
    }
    PathLine { x: 0; y: fillet.below ? 0 : fillet.radius }
  }
}
