import QtQuick
import qs.Commons

// Panacea's row surface, in place of the kit's CursorSurface: the same
// properties, and the same rule that the keyboard cursor alone paints it. The
// row under the cursor takes the launcher's soft fill; a current one a fainter
// fill. No outline.
Rectangle {
  id: root

  property bool hasCursor: false
  property bool current: false
  property bool outline: false
  property bool bordered: false
  property color foreground: PanaceaLook.fg
  property color accent: PanaceaLook.on
  property color fill: PanaceaLook.rowHover
  property color currentFill: PanaceaLook.rowFill

  radius: PanaceaLook.rowRadius
  color: hasCursor ? fill : current ? currentFill : "transparent"
  Behavior on color { ColorAnimation { duration: PanaceaLook.animHover } }
}
