import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Panacea's island, in place of the kit's KeyboardPanel for the notification
// panel (NotificationPanel.qml, the line marked `// panacea`). It takes the
// part of KeyboardPanel's API the panel uses, so the panel's own code stays
// Omarchy's.
//
// The panel grows out of Panacea's rail, as the menu does (companions/menu):
// opening asks Panacea to keep its rail out (`pill holdFor notifications
// <screen>`), and the answer says where the card attaches: which edge the
// rail is on, and how far it reaches in on this screen (off; 0 where it is
// not shown, so the card meets the screen's own edge). The card then slides
// out from behind the rail once the rail itself is most of the way out,
// centred along it, with Panacea's flares where it meets the rail, and
// everything but the rail dims. Closing folds it back in, and the rail may
// hide again.
// Without Panacea, or with Panacea off the rail, it opens as a card of its own
// at the top right, beside the toasts.
//
// Keyboard and clicks work as in KeyboardPanel: a brief Exclusive prime takes
// focus on every open, then OnDemand; a click anywhere off the card, on any
// monitor, closes it.
PanelWindow {
  id: root

  required property Item anchorItem
  property QtObject bar: null
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  // Taken for KeyboardPanel's sake; the card draws Panacea's own hairline.
  property var borderSpec: null
  property int margin: Style.gapsOut
  property int padding: PanaceaLook.modalPadding
  property int contentWidth: 380
  property int contentHeight: 200

  // Built the first time the panel opens, then kept (KeyboardPanel's lazy
  // content).
  property Component content: null
  property bool contentRequested: false
  readonly property Item loadedContent: contentLoader.item
  readonly property real loadedContentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string screenName: screen ? String(screen.name || "") : ""
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0

  // --- where it attaches ---------------------------------------------------

  property var dock: ({})
  readonly property bool docked: dock.attach === true
  readonly property string edge: docked && ["top", "bottom", "right"].indexOf(dock.edge) >= 0 ? dock.edge : "left"
  readonly property bool flat: edge === "top" || edge === "bottom"
  // how far the rail reaches in from its edge (x: Panacea from before the
  // rail had other edges)
  readonly property real attachOff: docked ? Number(dock.off !== undefined ? dock.off : (dock.x || 0)) : 0
  readonly property real flare: docked ? Number(dock.flare || 0) : 0
  // Into the rail, so two windows meeting on a fractional pixel at 1.25
  // scale leave no seam.
  readonly property int overlap: 2

  // holdFrom: when Panacea's drawer is out (opened from its Control Centre,
  // say), it stays, and drawerW says how wide it is. The card then opens as
  // the drawer itself, full height and as wide, Panacea drops the drawer
  // under it, and the card shrinks to its own size: the island changes
  // shape, rather than folding into the rail and sliding back out.
  function holdRail(name) {
    var answer = IpcRegistry.call("pill", "holdFrom", ["notifications", name])
    var parsed = ({})
    try { if (answer.ran && answer.output) parsed = JSON.parse(answer.output) } catch (e) { parsed = ({}) }
    return parsed
  }
  readonly property bool fromDrawer: docked && !flat && Number(dock.drawerW || 0) > attachOff

  // morph: 0 = the drawer's shape, 1 = the card's own. Only the opening from
  // the drawer moves it; it rests at 1.
  property real morph: 1
  function mix(from, to) { return from + (to - from) * morph }
  readonly property real ownWidth: contentWidth + (docked && !flat ? overlap : 0)
  readonly property real ownHeight: contentHeight + (docked && flat ? overlap : 0)
  readonly property real drawerWidth: Number(dock.drawerW || 0) - attachOff + overlap
  // In dockClip, which starts at the rail's inner side: against the rail,
  // centred along it (on a side rail at the height it opened at).
  readonly property real ownX: !docked ? Math.round(dockClip.width - margin - ownWidth)
    : edge === "left" ? 0
    : edge === "right" ? dockClip.width - ownWidth
    : Math.round((dockClip.width - ownWidth) / 2)
  readonly property real ownY: !docked ? margin
    : edge === "top" ? 0
    : edge === "bottom" ? dockClip.height - ownHeight
    : Math.max(margin, Math.min(cardTop >= 0 ? cardTop : 0, screenH - margin - contentHeight))

  // --- size ----------------------------------------------------------------

  readonly property real availableCardWidth: screenW > 0 ? Math.max(120, screenW - (flat ? 0 : attachOff) - margin * 2) : 0
  readonly property real availableCardHeight: screenH > 0 ? Math.max(120, screenH - (flat ? attachOff : 0) - margin * 2) : 0
  readonly property real verticalContentInset: padding * 2

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  // Out of the rail the card opens centred on the screen's height and keeps
  // its top while it is open, so a section that expands grows it downward
  // (and up only once it would leave the screen).
  property int cardTop: -1

  // --- lifetime ------------------------------------------------------------

  // folding: closed, and still moving away; the window stays until it has.
  property bool folding: false
  // settled: the open motion is over, so size changes may animate.
  property bool settled: false

  screen: anchorWindow ? anchorWindow.screen : null
  // Not `&& !!screen`: mapping the window updates its screen, which made
  // this a binding loop. The anchor's window always has one.
  visible: open || folding
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  // KeyboardPanel's namespace, for Omarchy's no_anim and the blur rule in
  // looknfeel.lua: the motion here is the panel's own.
  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // As OverlayWindow does: keep the first frames transparent until the
  // window has the output's size and scale, so it never opens stretched or
  // soft. Fractional scale comes in 1/120ths.
  readonly property var monitor: {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++)
      if (screen && monitors[i].name === screen.name) return monitors[i]
    return null
  }
  readonly property bool contentReady: visible && backingWindowVisible && !!screen
    && width === screen.width && height === screen.height
    && !!monitor && Math.round(devicePixelRatio * 120) === Math.round(monitor.scale * 120)
  property bool revealed: false

  onContentReadyChanged: {
    revealed = false
    if (contentReady) Qt.callLater(function() {
      if (root.contentReady) root.revealed = true
    })
  }
  // A scale Hyprland has not reported yet must not keep the panel away.
  Timer {
    interval: 250
    running: root.visible && root.backingWindowVisible && !root.revealed
    onTriggered: root.revealed = true
  }
  onRevealedChanged: if (revealed && open) startOpen(false)

  Binding {
    target: root.contentItem
    property: "opacity"
    value: root.revealed ? 1 : 0
  }

  property bool focusPrimed: false
  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }
  onBackingWindowVisibleChanged: beginFocusPrime()

  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (root.open) root.focusPrimed = true
  }

  onOpenChanged: {
    if (open) {
      if (content) contentRequested = true
      Hyprland.refreshMonitors()
      root.dock = root.holdRail(root.screenName)
      focusPrimed = false
      beginFocusPrime()
      // Opened again while folding: straight back out from where it is.
      if (revealed) startOpen(folding)
      folding = false
      if (focusTarget) Qt.callLater(function() {
        if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
      })
      return
    }
    focusPrimeTimer.stop()
    focusPrimed = false
    settled = false
    slideMotion.stop()
    popMotion.stop()
    shapeMotion.stop()
    // Closed before it took the drawer: let it go now all the same.
    dropDrawer()
    if (revealed && PanaceaLook.animMs > 0) {
      folding = true
      if (docked) foldMotion.start()
      else fadeMotion.start()
    } else {
      finishClose()
    }
  }

  function startOpen(fromHere) {
    foldMotion.stop()
    fadeMotion.stop()
    settled = false
    if (!fromHere) cardTop = Math.round((screenH - contentHeight) / 2)
    morph = 1
    contentHolder.opacity = 1
    if (PanaceaLook.animMs <= 0) {
      dockSlide.x = 0; dockSlide.y = 0; card.opacity = 1; card.scale = 1; scrimFill.opacity = 1
      settled = true
      if (fromDrawer) { drawerPending = true; dropDrawer() }
    } else if (fromDrawer && !fromHere) {
      // The drawer's shape, faded in over the drawer so its content
      // dissolves; then the drawer goes and the card shrinks into its own.
      // The content starts at 1%, not 0, so its first frame is drawn now,
      // while nothing moves, rather than halfway through the shrink.
      dockSlide.x = 0; dockSlide.y = 0; card.opacity = 0; card.scale = 1; scrimFill.opacity = 0
      morph = 0
      contentHolder.opacity = 0.01
      drawerPending = true
      shapeMotion.start()
    } else if (docked) {
      card.opacity = 1; card.scale = 1
      if (!fromHere) { dockSlide.x = tuckedX; dockSlide.y = tuckedY; scrimFill.opacity = 0 }
      slideMotion.start()
    } else {
      dockSlide.x = 0; dockSlide.y = 0
      if (!fromHere) { card.opacity = 0; card.scale = 0.965 }
      popMotion.start()
    }
  }

  function finishClose() {
    folding = false
    if (open) return
    root.holdRail("")
  }

  Component.onDestruction: if (open || folding) holdRail("")

  // The drawer under the card is Panacea's to drop, once the card covers it.
  property bool drawerPending: false
  function dropDrawer() {
    if (!drawerPending) return
    drawerPending = false
    IpcRegistry.call("pill", "dropDrawer", [])
  }

  // --- motion --------------------------------------------------------------

  // Render-thread animators, so a busy frame cannot skip them. Tucked: as
  // far behind the rail as the card and its flares reach, along its normal.
  readonly property real tuckReach: (flat ? card.height : card.width) + flare + overlap + 8
  readonly property real tuckedX: edge === "left" ? -tuckReach : edge === "right" ? tuckReach : 0
  readonly property real tuckedY: edge === "top" ? -tuckReach : edge === "bottom" ? tuckReach : 0

  // From the drawer to the card: the card fades in over the drawer, the
  // drawer goes, then the shape shrinks, easing out like the slide. The
  // shrink is geometry, so it runs on the GUI thread, which Panacea shares:
  // Panacea only hides the drawer's page here and destroys it once the
  // shrink is over (drawerKeep), or the first frames would stall. The
  // content comes in over the second half.
  readonly property int shapeMs: PanaceaLook.animMs + 20
  SequentialAnimation {
    id: shapeMotion
    OpacityAnimator { target: card; from: 0; to: 1; duration: Math.round(PanaceaLook.animFast * 0.6); easing.type: Easing.OutCubic }
    ScriptAction { script: root.dropDrawer() }
    ParallelAnimation {
      NumberAnimation { target: root; property: "morph"; from: 0; to: 1; duration: root.shapeMs; easing.type: Easing.OutCubic }
      OpacityAnimator { target: scrimFill; to: 1; duration: root.shapeMs; easing.type: Easing.OutCubic }
      SequentialAnimation {
        PauseAnimation { duration: Math.round(root.shapeMs * 0.45) }
        OpacityAnimator { target: contentHolder; to: 1; duration: Math.round(root.shapeMs * 0.55); easing.type: Easing.OutCubic }
      }
    }
    onFinished: root.settled = true
  }

  ParallelAnimation {
    id: slideMotion
    OpacityAnimator { target: scrimFill; to: 1; duration: PanaceaLook.animMs; easing.type: Easing.OutCubic }
    SequentialAnimation {
      // The rail first, when it was hidden.
      PauseAnimation { duration: Math.round(Number(root.dock.railMs || 0) * 0.6) }
      ParallelAnimation {
        XAnimator { target: dockSlide; to: 0; duration: PanaceaLook.animMs; easing.type: Easing.OutCubic }
        YAnimator { target: dockSlide; to: 0; duration: PanaceaLook.animMs; easing.type: Easing.OutCubic }
      }
    }
    onFinished: root.settled = true
  }

  ParallelAnimation {
    id: popMotion
    OpacityAnimator { target: card; to: 1; duration: PanaceaLook.animFast + 40; easing.type: Easing.OutCubic }
    ScaleAnimator { target: card; to: 1; duration: PanaceaLook.animMs; easing.type: Easing.OutCubic }
    onFinished: root.settled = true
  }

  ParallelAnimation {
    id: foldMotion
    XAnimator { target: dockSlide; to: root.tuckedX; duration: PanaceaLook.animFast + 40; easing.type: Easing.InCubic }
    YAnimator { target: dockSlide; to: root.tuckedY; duration: PanaceaLook.animFast + 40; easing.type: Easing.InCubic }
    OpacityAnimator { target: scrimFill; to: 0; duration: PanaceaLook.animFast + 40; easing.type: Easing.InCubic }
    onFinished: root.finishClose()
  }

  ParallelAnimation {
    id: fadeMotion
    OpacityAnimator { target: card; to: 0; duration: PanaceaLook.animFast; easing.type: Easing.InCubic }
    onFinished: root.finishClose()
  }

  // --- the dim and outside clicks ------------------------------------------

  // Out of the rail, the dim leaves the rail alone, so the rail, its flares
  // and the card read as one shape over the windows.
  Rectangle {
    id: scrimFill
    anchors.fill: parent
    anchors.leftMargin: root.edge === "left" ? root.attachOff : 0
    anchors.rightMargin: root.edge === "right" ? root.attachOff : 0
    anchors.topMargin: root.edge === "top" ? root.attachOff : 0
    anchors.bottomMargin: root.edge === "bottom" ? root.attachOff : 0
    visible: root.docked
    color: PanaceaLook.scrim
    opacity: 0
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    onClicked: root.close()
  }

  // The window spans one output; a twin on every other one catches the click
  // that closes the panel there (KeyboardPanel does the same).
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        visible: root.open && !!root.screen && modelData.name !== root.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "omarchy-keyboard-panel-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  // --- the card ------------------------------------------------------------

  // Out of the rail, the card and its flares sit in dockSlide, which moves
  // as one, inside dockClip, which starts at the rail's inner side: the card
  // comes out from behind the rail, never across it.
  Item {
    id: dockClip
    readonly property real cut: root.docked ? root.attachOff - root.overlap : 0
    x: root.edge === "left" ? cut : 0
    y: root.edge === "top" ? cut : 0
    width: root.width - (root.edge === "left" || root.edge === "right" ? cut : 0)
    height: root.height - (root.flat ? cut : 0)
    clip: root.docked

    Item {
      id: dockSlide
      width: parent.width
      height: parent.height

      // Where the card meets the rail: above and below it on a side rail,
      // left and right of it on a top or bottom one.
      PanaceaFillet {
        visible: root.docked && root.flare > 0 && root.morph > 0.98
        edge: root.edge
        radius: root.flare
        overlap: root.overlap
        color: card.color
        x: root.flat ? card.x - radius : root.edge === "right" ? dockSlide.width - reach : 0
        y: root.flat ? (root.edge === "top" ? 0 : dockSlide.height - reach) : card.y - radius
      }

      PanaceaFillet {
        visible: root.docked && root.flare > 0 && root.morph > 0.98
        edge: root.edge
        below: true
        radius: root.flare
        overlap: root.overlap
        color: card.color
        x: root.flat ? card.x + card.width : root.edge === "right" ? dockSlide.width - reach : 0
        y: root.flat ? (root.edge === "top" ? 0 : dockSlide.height - reach) : card.y + card.height
      }

      Rectangle {
        id: card
        // At rest (morph 1) the card's own size and place; opening from the
        // drawer, it starts as the drawer: full height, as wide, square.
        width: root.mix(root.drawerWidth, root.ownWidth)
        height: root.mix(root.screenH, root.ownHeight)
        // a right rail's drawer and card grow from the right
        x: root.edge === "right" ? dockSlide.width - width : root.ownX
        y: root.mix(0, root.ownY)
        color: PanaceaLook.bg
        radius: PanaceaLook.modalRadius
        // Out of the rail its rail side is square and the flares round it
        // into the rail; on its own, all four corners are round. Coming from
        // the drawer, its free corners round as it shrinks.
        function corner(onRail) { return root.docked && onRail ? 0 : root.mix(0, radius) }
        topLeftRadius: corner(root.edge === "left" || root.edge === "top")
        topRightRadius: corner(root.edge === "right" || root.edge === "top")
        bottomLeftRadius: corner(root.edge === "left" || root.edge === "bottom")
        bottomRightRadius: corner(root.edge === "right" || root.edge === "bottom")
        border.width: root.docked ? 0 : 1
        border.color: PanaceaLook.line
        clip: true
        opacity: 0

        Behavior on height {
          enabled: root.settled
          NumberAnimation { duration: PanaceaLook.animMs; easing.type: Easing.InOutCubic }
        }
        Behavior on y {
          enabled: root.settled
          NumberAnimation { duration: PanaceaLook.animMs; easing.type: Easing.InOutCubic }
        }

        // Clicks on the card stay on the card.
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Item {
          id: contentHolder
          // The card's own content box, whatever the card's size on the way:
          // the panel never reflows while the shape moves or the card's
          // height animates, the card's clip shows what fits.
          // against a right rail it keeps to the card's right, where the
          // drawer it may come from is pinned
          x: root.edge === "right" ? card.width - root.overlap - root.padding - width
             : root.padding + (root.docked && root.edge === "left" ? root.overlap : 0)
          y: root.padding + (root.docked && root.edge === "top" ? root.overlap : 0)
          width: root.contentWidth - root.padding * 2
          height: root.contentHeight - root.padding * 2
          // Right-to-left languages read the card mirrored; the card itself
          // stays where the rail puts it.
          LayoutMirroring.enabled: Commons.I18n.rightToLeft
          LayoutMirroring.childrenInherit: true

          Loader {
            id: contentLoader
            anchors.fill: parent
            focus: true
            active: !!root.content && (root.open || root.contentRequested)
            sourceComponent: root.content
          }
        }
      }
    }
  }
}
