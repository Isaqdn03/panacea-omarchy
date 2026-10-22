import QtQuick
import qs.Commons

// Panacea's switch (SetToggle.qml's track and knob), in place of the kit's
// ToggleSwitch: the same properties and signals, Panacea's drawing. On is the
// solid "on" colour with a knob in the card's colour; off is a faint track.
// The keyboard cursor shows as the track brightening, not a ring.
Item {
  id: root

  property bool checked: false
  property bool busy: false
  property bool interactive: true
  property bool hasCursor: false
  // Taken for the kit's sake; Panacea's look decides the colours.
  property color foreground: PanaceaLook.fg
  property color accent: PanaceaLook.on
  readonly property bool mirrored: LayoutMirroring.enabled

  signal toggled()
  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse

  property int trackWidth: 46
  property int trackHeight: 26
  readonly property int knobSize: trackHeight - 6

  implicitWidth: trackWidth
  implicitHeight: trackHeight

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: root.checked ? PanaceaLook.on
         : root.hot ? PanaceaLook.chipHover : PanaceaLook.switchOff
    Behavior on color { ColorAnimation { duration: PanaceaLook.animFade } }

    Rectangle {
      width: root.knobSize
      height: root.knobSize
      radius: height / 2
      y: 3
      x: root.checked !== root.mirrored ? track.width - width - 3 : 3
      color: root.checked ? PanaceaLook.bg : PanaceaLook.knobOff
      Behavior on x { NumberAnimation { duration: PanaceaLook.animHover; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: PanaceaLook.animFade } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: if (!root.busy) root.toggled()
  }
}
