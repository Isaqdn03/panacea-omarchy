pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// Panacea's look, for the Omarchy menu this companion redraws (each line that
// uses it is marked `// panacea`). Panacea works its colours out from the
// theme and its own settings; rather than copy that here, ask it (`pill look`,
// in process through IpcRegistry) and ask again whenever the theme or
// Panacea's settings change. Until Panacea answers, Omarchy's own menu colours
// stand in, so the menu is never unstyled.
Singleton {
  id: look

  property var panacea: ({})
  readonly property bool fromPanacea: panacea.bg !== undefined

  readonly property color bg: fromPanacea ? panacea.bg : Commons.Color.menu.background
  readonly property color fg: fromPanacea ? panacea.fg : Commons.Color.menu.text
  readonly property color muted: fromPanacea ? panacea.muted : Qt.rgba(fg.r, fg.g, fg.b, 0.45)
  readonly property color line: fromPanacea ? panacea.line : Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property string font: fromPanacea ? panacea.fontFam : Style.font.menuFamily
  readonly property int fontSize: fromPanacea ? panacea.fontSize : 15
  readonly property int iconSize: fromPanacea ? panacea.iconSize : 17
  // Panacea's move duration; 0 when Panacea's Reduce motion is on.
  readonly property int animMs: fromPanacea && panacea.animMs !== undefined ? panacea.animMs : 230
  readonly property int animFast: Math.round(animMs * 0.52)

  // Panacea's modal (Settings, Files): the card, its border and the scrim.
  readonly property int modalRadius: 26
  readonly property color modalBorder: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
  readonly property color scrim: Qt.rgba(0, 0, 0, 0.30)
  readonly property int modalPadding: 14

  // Panacea's launcher: the search field, its rows, and the icon tile.
  readonly property int fieldHeight: 42
  readonly property int fieldRadius: 13
  readonly property color fieldFill: Qt.rgba(fg.r, fg.g, fg.b, 0.06)
  readonly property color fieldFocus: Qt.rgba(fg.r, fg.g, fg.b, 0.22)
  readonly property int rowHeight: 44
  readonly property int rowRadius: 12
  readonly property color rowSelected: Qt.rgba(fg.r, fg.g, fg.b, 0.11)
  readonly property int tileSize: 26
  readonly property int tileRadius: 7
  readonly property color tileFill: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color scrollThumb: Qt.rgba(fg.r, fg.g, fg.b, 0.22)

  // Panacea's back arrow, at the start of every page header.
  readonly property int backSize: 30
  readonly property int backRadius: 10

  function refresh() {
    var answer = IpcRegistry.call("pill", "look", [])
    if (!answer.ran || !answer.output) return
    try {
      look.panacea = JSON.parse(answer.output)
    } catch (e) {
      console.warn("PanaceaLook: Panacea's look did not parse:", e)
    }
  }

  // Panacea loads after the services, so keep asking until it answers.
  property Timer untilPanacea: Timer {
    interval: 1000
    repeat: true
    running: !look.fromPanacea
    triggeredOnStart: true
    onTriggered: look.refresh()
  }

  // Panacea re-reads the theme's files when Omarchy's colours change; give it
  // a moment before asking.
  property Timer soon: Timer {
    interval: 400
    onTriggered: look.refresh()
  }

  property Connections theme: Connections {
    target: Commons.Color
    function onAccentChanged() { look.soon.restart() }
    function onBackgroundChanged() { look.soon.restart() }
    function onForegroundChanged() { look.soon.restart() }
  }

  property FileView settings: FileView {
    path: Quickshell.env("HOME") + "/.config/panacea/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: look.soon.restart()
  }
}
