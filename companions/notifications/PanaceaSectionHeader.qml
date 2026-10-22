import QtQuick
import qs.Commons

// Panacea's group label (SetLabel.qml), in place of the kit's
// PanelSectionHeader: small, spaced-out capitals in a faint text colour. It
// heads a group without competing with the rows under it.
Text {
  id: root

  // Taken for the kit's sake; Panacea's look decides the colour.
  property color foreground: PanaceaLook.fg
  property string fontFamily: PanaceaLook.font
  property real fontSize: PanaceaLook.fontSize - 5

  textFormat: Text.PlainText
  color: PanaceaLook.label
  font.family: fontFamily
  font.pixelSize: fontSize
  font.bold: true
  font.letterSpacing: 1.4
  font.capitalization: Font.AllUppercase
  // The kit's reason holds here too: room above for glyphs that overshoot
  // their ascent, so a header at the top of a clipped list keeps its head.
  topPadding: Math.ceil(fontSize * 0.15)
}
