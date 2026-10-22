import QtQuick
import qs.Commons

// Panacea's text button (the chips on Panacea's Notifications page), in place
// of the kit's Button where the panel uses one: a faint tile at rest that
// brightens under the pointer, the label muted until then. A selected one is
// a solid pill in the text colour. `bordered` is the kit's; Panacea's chips
// have no outline.
Rectangle {
  id: root

  property string text: ""
  property bool selected: false
  property bool active: false
  property bool bordered: false
  property bool focusable: false
  property color foreground: PanaceaLook.fg
  property string fontFamily: PanaceaLook.font
  property real fontSize: PanaceaLook.fontSize - 4
  property real horizontalPadding: 14
  property real verticalPadding: 7

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  readonly property bool hot: mouse.containsMouse && enabled
  readonly property bool picked: selected || active

  implicitWidth: label.implicitWidth + horizontalPadding * 2
  implicitHeight: Math.max(30, label.implicitHeight + verticalPadding * 2)
  radius: PanaceaLook.chipRadius
  color: picked ? PanaceaLook.fg : hot ? PanaceaLook.chipHover : PanaceaLook.chipFill
  border.width: focusable && activeFocus ? 1 : 0
  border.color: PanaceaLook.label
  opacity: enabled ? 1 : 0.4
  Behavior on color { ColorAnimation { duration: PanaceaLook.animHover } }

  Text {
    id: label
    anchors.centerIn: parent
    width: Math.min(implicitWidth, root.width - root.horizontalPadding * 2)
    textFormat: Text.PlainText
    text: root.text
    elide: Text.ElideRight
    color: root.picked ? PanaceaLook.bg : root.hot ? root.foreground : PanaceaLook.muted
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    Behavior on color { ColorAnimation { duration: PanaceaLook.animHover } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      root.clicked()
    }
  }
}
