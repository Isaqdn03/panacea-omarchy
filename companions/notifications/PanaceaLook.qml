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
  readonly property color on: fromPanacea ? panacea.on : Commons.Color.accent
  readonly property string font: fromPanacea ? panacea.fontFam : Style.font.family
  readonly property string fontBody: fromPanacea && panacea.fontBody ? panacea.fontBody : font
  readonly property int fontSize: fromPanacea ? panacea.fontSize : 15
  readonly property int iconSize: fromPanacea ? panacea.iconSize : 17

  // Panacea's timings; 0 when Panacea's Reduce motion is on.
  readonly property int animMs: fromPanacea && panacea.animMs !== undefined ? panacea.animMs : 230
  readonly property int animFast: Math.round(animMs * 0.52)
  readonly property int animFade: fromPanacea && panacea.animFade !== undefined ? panacea.animFade : 200
  readonly property int animHover: fromPanacea && panacea.animHover !== undefined ? panacea.animHover : 150

  // Panacea's card shapes: the rail card, and the icon tile inside a toast.
  readonly property int cardRadius: 18
  readonly property int tileRadius: 10
  readonly property int tileSize: 34
  readonly property color tileFill: Qt.rgba(fg.r, fg.g, fg.b, 0.08)

  // The panel: Panacea's modal card when it opens on its own, and the dim
  // behind it.
  readonly property int modalRadius: 26
  readonly property int modalPadding: 16
  readonly property color scrim: Qt.rgba(0, 0, 0, 0.30)

  // Panacea's page pieces: rows, chips and square buttons, the switch, the
  // small uppercase labels that head a group.
  readonly property int rowRadius: 12
  readonly property color rowFill: Qt.rgba(fg.r, fg.g, fg.b, 0.05)
  readonly property color rowHover: Qt.rgba(fg.r, fg.g, fg.b, 0.09)
  readonly property int chipRadius: 10
  readonly property color chipFill: Qt.rgba(fg.r, fg.g, fg.b, 0.06)
  readonly property color chipHover: Qt.rgba(fg.r, fg.g, fg.b, 0.13)
  readonly property color switchOff: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property color knobOff: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color label: Qt.rgba(fg.r, fg.g, fg.b, 0.35)
  readonly property color scrollThumb: Qt.rgba(fg.r, fg.g, fg.b, 0.22)

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
