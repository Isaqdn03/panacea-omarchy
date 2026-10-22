import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Hosts the notification panel when Panacea is the bar. Omarchy's stock bar
// hosts it in its do-not-disturb indicator (bar/indicators/Dnd.qml), which
// Panacea's rail does not have, so `omarchy-shell notifications openPanel`
// and togglePanel found no one to answer. Here every monitor gets an
// invisible one-pixel anchor, and the one on the requested monitor builds the
// panel the first time, as Dnd.qml does. The panel is Panacea's island
// (PanaceaIsland.qml), which takes its monitor from the anchor's window and
// works out where to open by asking Panacea, so the anchor's place does not
// matter.
Item {
  id: host

  required property var service

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: anchorWindow

      required property var modelData
      readonly property string screenName: modelData ? String(modelData.name || "") : ""

      screen: modelData
      anchors {
        top: true
        left: true
      }
      implicitWidth: 1
      implicitHeight: 1
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      mask: Region {}
      WlrLayershell.namespace: "panacea-notifications-anchor"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Item {
        id: anchor
        width: 1
        height: 1
      }

      Connections {
        target: host.service
        function onPanelRequested(action, screenName) {
          if (screenName && screenName !== anchorWindow.screenName) return
          if (!panelLoader.item) {
            panelLoader.setSource(host.service.panelUrl,
                                  { anchorItem: anchor, service: host.service })
          }
          var panel = panelLoader.item
          if (!panel) return
          if (action === "settings") panel.openSettings()
          else panel.open()
        }
      }

      Loader { id: panelLoader }
    }
  }
}
