import QtQuick
import qs.Commons

// Panacea's page header, in place of the kit's PanelHero: the same properties,
// Panacea's drawing. The icon sits in Panacea's tile (as on a toast), then the
// title and a muted line under it, in sentence case, then the trailing
// control, centred on the labels.
Item {
  id: root

  property Component iconComponent: null
  // false: the icon is a control of its own (a back arrow) and needs no tile.
  property bool iconTile: true
  property string title: ""
  property string meta: ""
  property string detail: ""
  property color foreground: PanaceaLook.fg
  property string fontFamily: PanaceaLook.font
  property real iconSize: PanaceaLook.iconSize
  property real iconOpacity: 1.0
  property alias metaOpacity: metaText.opacity
  property Component trailingControl: null

  readonly property color dim: PanaceaLook.muted
  readonly property real trailingInset: trailingLoader.item && trailingLoader.item.visible ? trailingLoader.width + 12 : 0

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(iconBox.height, heroLabels.implicitHeight, trailingLoader.implicitHeight)

  Rectangle {
    id: iconBox
    readonly property bool shown: !!root.iconComponent
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: !shown ? 0 : root.iconTile ? PanaceaLook.tileSize : iconLoader.implicitWidth
    height: !shown ? 0 : root.iconTile ? PanaceaLook.tileSize : iconLoader.implicitHeight
    radius: PanaceaLook.tileRadius
    color: root.iconTile ? PanaceaLook.tileFill : "transparent"

    Loader {
      id: iconLoader
      anchors.centerIn: parent
      sourceComponent: root.iconComponent
      opacity: root.iconOpacity
    }
  }

  Column {
    id: heroLabels
    anchors.left: iconBox.right
    anchors.leftMargin: iconBox.shown ? 12 : 0
    anchors.right: parent.right
    anchors.rightMargin: root.trailingInset
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Row {
      visible: root.title !== "" || root.detail !== ""
      width: parent.width
      spacing: 8

      Text {
        textFormat: Text.PlainText
        visible: root.title !== ""
        text: root.title
        width: Math.min(implicitWidth, Math.max(0, parent.width - (detailChip.visible ? detailChip.width + parent.spacing : 0)))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: PanaceaLook.fontSize + 1
        font.bold: true
        elide: Text.ElideRight
      }

      Rectangle {
        id: detailChip
        visible: root.detail !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: detailText.implicitWidth + 14
        height: detailText.implicitHeight + 6
        radius: height / 2
        color: PanaceaLook.chipFill

        Text {
          id: detailText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.detail
          color: PanaceaLook.muted
          font.family: root.fontFamily
          font.pixelSize: PanaceaLook.fontSize - 5
        }
      }
    }

    Text {
      id: metaText
      textFormat: Text.PlainText
      width: parent.width
      text: root.meta
      visible: text !== ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: PanaceaLook.fontSize - 4
      elide: Text.ElideRight
    }
  }

  Loader {
    id: trailingLoader
    sourceComponent: root.trailingControl
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
  }
}
