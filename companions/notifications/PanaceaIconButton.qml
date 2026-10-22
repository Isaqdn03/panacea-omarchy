import QtQuick
import qs.Commons
import qs.Ui

// Panacea's square icon button (BackButton.qml's tile), in place of the kit's
// PanelActionButton: the same properties and signals, Panacea's drawing. A
// faint tile at rest that brightens under the pointer; the glyph takes the
// caller's foreground, which the panel uses to say on, off or snoozed.
Rectangle {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: PanaceaLook.fg
  property color hoverColor: foreground
  property string fontFamily: PanaceaLook.font
  property real fontSize: PanaceaLook.iconSize - 3
  property real size: 30
  property bool focusable: false
  property bool hasCursor: false
  property bool bordered: false

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  readonly property bool hot: (mouse.containsMouse || hasCursor) && enabled

  implicitWidth: size
  implicitHeight: size
  radius: PanaceaLook.chipRadius
  color: hot ? PanaceaLook.chipHover : PanaceaLook.chipFill
  border.width: focusable && activeFocus ? 1 : 0
  border.color: PanaceaLook.label
  Behavior on color { ColorAnimation { duration: PanaceaLook.animHover } }

  Text {
    textFormat: Text.PlainText
    // Whole pixels, so the glyph sits in the middle of the tile.
    x: Math.round((root.width - width) / 2)
    y: Math.round((root.height - height) / 2)
    text: root.iconText
    color: root.enabled ? (root.hot ? root.hoverColor : root.foreground) : PanaceaLook.muted
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

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    fontFamily: PanaceaLook.font
    fontSize: PanaceaLook.fontSize - 4
    panelForeground: PanaceaLook.fg
    panelBackground: PanaceaLook.bg
    panelBorder: PanaceaLook.line
  }
}
