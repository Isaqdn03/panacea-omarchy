pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

// Panacea's look, for the Omarchy files this companion redraws (each line
// that uses it is marked `// panacea`). Panacea works its colours out from the
// theme and its own settings; rather than copy that here, ask it (`pill look`,
// in process through IpcRegistry) and ask again whenever the theme or
// Panacea's settings change. Until Panacea answers, Omarchy's own notification
// colours stand in, so the cards are never unstyled.
Singleton {
  id: look

  property var panacea: ({})
  readonly property bool fromPanacea: panacea.bg !== undefined

  readonly property color bg: fromPanacea ? panacea.bg : Commons.Color.notifications.background
  readonly property color fg: fromPanacea ? panacea.fg : Commons.Color.notifications.text
  readonly property color muted: fromPanacea ? panacea.muted : Qt.darker(fg, 1.4)
  readonly property color line: fromPanacea ? panacea.line : Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color hover: fromPanacea ? panacea.hover : Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color crit: fromPanacea ? panacea.crit : Commons.Color.urgent
  readonly property string font: fromPanacea ? panacea.fontFam : Style.font.family
  readonly property int fontSize: fromPanacea ? panacea.fontSize : 15
  readonly property int iconSize: fromPanacea ? panacea.iconSize : 17

  // Panacea's card shapes: the rail card, and the icon tile inside a toast.
  readonly property int cardRadius: 18
  readonly property int tileRadius: 10
  readonly property int tileSize: 34
  readonly property color tileFill: Qt.rgba(fg.r, fg.g, fg.b, 0.08)

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
