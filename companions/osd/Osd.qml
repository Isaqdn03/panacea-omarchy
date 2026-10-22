import QtQuick
import qs.Commons

// Panacea's stand-in for Omarchy's OSD. The manifest names omarchy.osd as the
// plugin it replaces (omarchy.clonedFrom), so the shell hands this plugin every
// pop-up addressed to omarchy.osd: the volume and brightness keys, the media
// service, the audio and monitor panels. Since Omarchy 4.5 those no longer go
// through `omarchy-shell osd show`, so Panacea's own `osd` handler never heard
// them. Each one goes on to that handler, in the same process.
//
// Installed by scripts/companions.sh as its own plugin folder,
// ~/.config/omarchy/plugins/isaqdn.panacea-osd: third-party plugins must sit
// at the top level, and Omarchy refuses a symlinked one.
Item {
  id: root

  // The panel contract shell.qml drives: open(payloadJson), close(), opened.
  // Panacea hides the OSD on its own timer, so nothing here stays open.
  readonly property bool opened: false

  function open(payloadJson) {
    var result = IpcRegistry.call("osd", "show", [String(payloadJson || "")])
    if (!result.ran) console.warn("isaqdn.panacea-osd: Panacea's osd handler is not running")
  }

  function close() {
    IpcRegistry.call("osd", "close", [])
  }
}
