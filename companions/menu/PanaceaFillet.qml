import QtQuick
import QtQuick.Shapes

// Panacea's flare: the concave corner where a surface that grows out of the
// rail meets the rail's edge, as the rail itself meets the screen's ends.
// Drawn for a rail on the left: it sits on the rail's edge just above the
// card (below: false) or just below it (below: true), `radius` wide and
// tall, and reaches `overlap` into the rail: two windows' edges meeting on a
// fractional pixel at 1.25 scale would otherwise leave a faint seam.
//
// For a rail on another edge the drawing is turned onto it (edge): mirrored
// for the right; transposed for the top, so "above" lands left of the card
// and "below" right of it, and transposed and flipped for the bottom. On the
// top and bottom its box is `radius` wide and radius + overlap tall.
Shape {
  id: fillet

  property real radius: 12
  property real overlap: 2
  property bool below: false
  property color color: "black"
  property string edge: "left"
  readonly property real reach: radius + overlap

  width: radius + overlap
  height: radius
  preferredRendererType: Shape.CurveRenderer

  transform: Matrix4x4 {
    matrix: fillet.edge === "right" ? Qt.matrix4x4(-1, 0, 0, fillet.reach, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
          : fillet.edge === "top" ? Qt.matrix4x4(0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
          : fillet.edge === "bottom" ? Qt.matrix4x4(0, 1, 0, 0, -1, 0, 0, fillet.reach, 0, 0, 1, 0, 0, 0, 0, 1)
          : Qt.matrix4x4()
  }

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
