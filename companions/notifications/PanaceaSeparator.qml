import QtQuick
import qs.Commons

// In place of the kit's PanelSeparator. Panacea's pages draw no lines between
// groups; the space alone divides them. This keeps the separator's place in
// the panel's column, with a little room of its own, and draws nothing.
Item {
  id: root

  // Taken for the kit's sake.
  property color foreground: PanaceaLook.fg
  property real strength: 0

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 4
  height: 4
}
