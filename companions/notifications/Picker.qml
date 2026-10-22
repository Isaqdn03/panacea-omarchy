import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A dropdown whose popup takes its height from its rows. qs.Ui's Dropdown sizes
// its list a couple of pixels short, so hovering the last row scrolls the list
// and every row jumps under the pointer. A list that always fits cannot scroll.
Item {
  id: picker

  property string label: ""
  property string value: ""
  // Plain strings or { value, label } objects, like the kit's Dropdown.
  property var options: []
  property color foreground: PanaceaLook.fg  // panacea
  property string fontFamily: PanaceaLook.font  // panacea
  property int rowHeight: 32  // panacea

  signal picked(string value)

  function optionValue(o) { return (o && typeof o === "object") ? String(o.value) : String(o) }
  function optionLabel(o) { return (o && typeof o === "object") ? String(o.label) : String(o) }
  function labelFor(wanted) {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === String(wanted)) return optionLabel(options[i])
    return String(wanted)
  }

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: label !== "" ? rowHeight + labelText.implicitHeight + stack.spacing : rowHeight  // panacea: Panacea's label is taller

  Column {
    id: stack
    anchors.fill: parent
    spacing: 8  // panacea

    Text {
      id: labelText  // panacea
      textFormat: Text.PlainText
      visible: picker.label !== ""
      text: picker.label
      color: picker.foreground  // panacea
      font.family: picker.fontFamily
      font.pixelSize: PanaceaLook.fontSize - 1  // panacea
    }

    BorderSurface {
      id: trigger
      width: parent.width
      height: picker.rowHeight
      radius: PanaceaLook.chipRadius  // panacea

      readonly property bool hot: triggerArea.containsMouse || menu.opened
      color: trigger.hot ? PanaceaLook.chipHover : PanaceaLook.chipFill  // panacea
      borderSpec: Border.none()  // panacea
      Behavior on color { ColorAnimation { duration: PanaceaLook.animHover } }  // panacea

      Text {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12  // panacea
        anchors.rightMargin: 6  // panacea
        textFormat: Text.PlainText
        text: picker.labelFor(picker.value)
        elide: Text.ElideRight
        color: picker.foreground
        font.family: picker.fontFamily
        font.pixelSize: PanaceaLook.fontSize - 3  // panacea
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 10  // panacea
        textFormat: Text.PlainText
        text: menu.opened ? "\u{f0143}" : "\u{f0140}"  // panacea: up while the list is open
        color: PanaceaLook.muted  // panacea
        font.family: picker.fontFamily
        font.pixelSize: PanaceaLook.fontSize - 2  // panacea
      }

      MouseArea {
        id: triggerArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.opened ? menu.close() : menu.open()
      }
    }
  }

  Popup {
    id: menu
    y: stack.y + trigger.y + trigger.height + Style.spacing.xxs
    width: picker.width
    padding: 6  // panacea

    background: BorderSurface {
      color: PanaceaLook.bg  // panacea
      radius: PanaceaLook.rowRadius  // panacea
      borderSpec: Border.flat(PanaceaLook.line, 1)  // panacea
    }

    contentItem: Column {
      spacing: 2  // panacea

      Repeater {
        model: picker.options

        Rectangle {
          id: row
          required property var modelData
          readonly property bool chosen: picker.optionValue(modelData) === String(picker.value)
          width: menu.availableWidth
          height: 30  // panacea
          radius: 8  // panacea
          color: row.chosen ? PanaceaLook.fg : rowArea.containsMouse ? PanaceaLook.rowHover : "transparent"  // panacea

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10  // panacea
            anchors.rightMargin: 10  // panacea
            textFormat: Text.PlainText
            text: picker.optionLabel(row.modelData)
            elide: Text.ElideRight
            color: row.chosen ? PanaceaLook.bg : picker.foreground  // panacea
            font.family: picker.fontFamily
            font.pixelSize: PanaceaLook.fontSize - 3  // panacea
            font.bold: row.chosen
          }

          MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              menu.close()
              picker.picked(picker.optionValue(row.modelData))
            }
          }
        }
      }
    }
  }
}
