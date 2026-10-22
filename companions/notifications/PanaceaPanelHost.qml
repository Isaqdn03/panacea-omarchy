import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Hosts the notification panel when Panacea is the bar. Omarchy's stock bar
// hosts it in its do-not-disturb indicator (bar/indicators/Dnd.qml), which
// Panacea's rail does not have, so `omarchy-shell notifications openPanel`
// and togglePanel found no one to answer. Here an invisible anchor sits in
// the top-right corner of every monitor, where the toasts are, and the one
// on the requested monitor builds the panel the first time, as Dnd.qml does.
// The panel is a KeyboardPanel, which reads a few things from the bar it
// hangs from; `barFacade` answers them.
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
      // KeyboardPanel puts its card below the anchor window's height, and
      // reads the anchor's x inside that window as its x on screen (true of a
      // full-width bar). So: full width, one pixel tall, the anchor at the
      // right end; the panel opens at the top right, beside the toasts.
      anchors {
        top: true
        left: true
        right: true
      }
      implicitHeight: 1
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      mask: Region {}
      WlrLayershell.namespace: "panacea-notifications-anchor"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Item {
        id: anchor
        anchors.right: parent.right
        width: 2
        height: 1
      }

      QtObject {
        id: barFacade
        readonly property string position: "top"
        readonly property int barSize: 1
        readonly property string fontFamily: PanaceaLook.font
        property var activePopout: null
        readonly property var clickTargets: []
        function requestPopout(owner) {
          if (activePopout === owner) return
          if (activePopout && "close" in activePopout) activePopout.close()
          activePopout = owner
        }
        function releasePopout(owner) {
          if (activePopout === owner) activePopout = null
        }
        function targetBelongsToWindow(target, window) {
          return !!target && !!window && !!target.QsWindow && target.QsWindow.window === window
        }
      }

      Connections {
        target: host.service
        function onPanelRequested(action, screenName) {
          if (screenName && screenName !== anchorWindow.screenName) return
          if (!panelLoader.item) {
            panelLoader.setSource(host.service.panelUrl,
                                  { anchorItem: anchor, bar: barFacade, service: host.service })
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
