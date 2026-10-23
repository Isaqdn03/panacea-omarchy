import QtQuick

// PANACEA-LOCAL: an island that grows out of Panacea's bar, on whatever edge
// the bar is (the layout island: LayoutView.qml). It lives in Panacea's own
// window, beside the rail, so every motion between it and the bar is one
// drawing and needs no handoff between windows (the companions' islands do:
// companions/*/PanaceaIsland.qml).
//
// Where it sits: against the bar's inner side, centred along the edge, square
// where it meets the bar, with flares rounding it into the bar (or into the
// screen edge, for the pill, which then reads as part of it).
//
// How it comes and goes:
// - From a rail, it slides out from behind the rail and folds back in. The
//   capsule is drawn above it, so the rail covers it while it is tucked.
// - From the pill, it grows out of the pill's own shape and shrinks back
//   into it (morph).
// - From an open page (the drawer, a rail's sheet, the pill's panel), it
//   fades in over that page at its shape, the page drops away under it, and
//   it shrinks into its own (Panacea calls dropDrawer at that point).
//
// Everything but the bar dims while it is out; a click on the dim closes it.
Item {
    id: isl

    property var sys
    // Panacea asks for it to be out or not; the island answers with
    // folded() once it is all the way back in.
    property bool open: false
    property Component content: null
    property int contentWidth: 380
    readonly property int pad: 18
    signal folded()
    signal closeRequested()

    readonly property real contentHeight: loader.item ? loader.item.implicitHeight : 0

    // --- where it attaches ---------------------------------------------------

    readonly property string edge: sys.pillPos
    readonly property bool flat: edge === "top" || edge === "bottom"
    // a rail it sits beside; the pill it takes into itself, from the edge,
    // with room on that side for the pill, which is drawn over it (inset)
    readonly property real off: sys.railMode ? sys.railW : 0
    readonly property real inset: sys.railMode ? 0
                                : sys.pillH + (sys.cfg.notchMode ? 0 : sys.cfg.islandGap)
    readonly property real flare: sys.cornerR
    // under the bar by this much, so no seam shows where they meet
    readonly property int overlap: 2

    readonly property real ownW: contentWidth + pad * 2 + (flat ? 0 : overlap + inset)
    readonly property real ownH: contentHeight + pad * 2 + (flat ? overlap + inset : 0)
    readonly property real ownX: edge === "left" ? off - overlap
                               : edge === "right" ? width - off - ownW + overlap
                               : Math.round((width - ownW) / 2)
    // On a side edge it opens centred and then keeps its top, so a taller
    // tab grows it downward (and up only once it would leave the screen).
    property real pinnedY: -1
    readonly property real ownY: edge === "top" ? off - overlap
                               : edge === "bottom" ? height - off - ownH + overlap
                               : pinnedY >= 0 ? Math.max(12, Math.min(pinnedY, height - 12 - ownH))
                               : Math.round((height - ownH) / 2)

    // --- motion state --------------------------------------------------------

    // tuck: 1 = behind the rail, 0 = out. morph: 0 = the shape it came from
    // (fromRect, fromR), 1 = its own.
    property real tuck: 1
    property real morph: 1
    property rect fromRect: Qt.rect(0, 0, 0, 0)
    property real fromR: 0
    // busy: out, or still on its way in or out; the window keeps its input
    // and the dim while it is
    property bool busy: false
    // above the capsule while it takes an open page's place, which may be
    // the capsule itself (the drawer, the pill's panel)
    property bool overBar: false

    function mix(a, b) { return a + (b - a) * morph; }

    readonly property real cardX: mix(fromRect.x, ownX)
    readonly property real cardY: mix(fromRect.y, ownY)
    readonly property real cardW: mix(fromRect.width, ownW)
    readonly property real cardH: mix(fromRect.height, ownH)
    readonly property real freeR: mix(fromR, 26)

    visible: busy
    z: overBar ? 52 : 50.5

    // Called by Panacea when open turns true. page: the open page's rect and
    // free-corner radius, when the island takes its place (handoff), or null.
    function show(page) {
        foldMotion.stop(); shrinkMotion.stop();
        busy = true;
        contentHolder.opacity = 1;
        // Esc reaches the content, and the island, from the first frame
        Qt.callLater(function() { if (isl.open) loader.forceActiveFocus(); });
        pinnedY = -1;
        pinTimer.restart();
        if (sys.animMs <= 0) {
            tuck = 0; morph = 1; scrim.opacity = 1;
            if (page) sys.dropDrawer();
            return;
        }
        if (page) {
            // the page's shape, faded in over it; then the page goes and the
            // shape shrinks into the island's own
            fromRect = page.rect; fromR = page.r;
            tuck = 0; morph = 0; overBar = true;
            card.opacity = 0; contentHolder.opacity = 0.01; scrim.opacity = 0;
            handoffMotion.restart();
        } else if (!sys.railMode) {
            // out of the pill's own shape
            fromRect = Qt.rect(sys.pillRectX, sys.pillRectY, sys.pillRectW, sys.pillRectH);
            fromR = sys.pillH / 2;
            tuck = 0; morph = 0; overBar = false;
            card.opacity = 1; contentHolder.opacity = 0.01; scrim.opacity = 0;
            growMotion.restart();
        } else {
            tuck = 1; morph = 1; overBar = false;
            card.opacity = 1; scrim.opacity = 0;
            slideMotion.restart();
        }
    }

    // Back into the bar: a rail folds it in, the pill takes it back.
    function hide() {
        slideMotion.stop(); growMotion.stop(); handoffMotion.stop();
        overBar = false;
        if (!busy) { folded(); return; }
        if (sys.animMs <= 0) { finish(); return; }
        if (sys.railMode) {
            foldMotion.restart();
        } else {
            fromRect = Qt.rect(sys.pillRectX, sys.pillRectY, sys.pillRectW, sys.pillRectH);
            fromR = sys.pillH / 2;
            shrinkMotion.restart();
        }
    }

    function finish() {
        busy = false;
        pinnedY = -1;
        tuck = 1; morph = 1;
        folded();
    }

    onOpenChanged: open ? show(sys.islandFrom) : hide()

    // once the content has laid out, centred
    Timer {
        id: pinTimer
        interval: 60
        onTriggered: if (isl.busy && !isl.flat) isl.pinnedY = Math.round((isl.height - isl.ownH) / 2)
    }

    // the rail first, when auto-hide had it away
    readonly property int waitMs: Math.round(sys.islandRailMs * 0.6)

    // The content is built as the island is asked out, and its first frame
    // is slow to reach the screen: taken while the island moved, it froze
    // the motion. So nothing moves for the first warmMs (Panacea's pageHost
    // does the same for pages). Tucked behind the rail, or at the pill's
    // shape under the pill, the island is drawn but not seen meanwhile.
    SequentialAnimation {
        id: slideMotion
        PauseAnimation { duration: Math.max(isl.waitMs, isl.sys.warmMs) }
        ParallelAnimation {
            NumberAnimation { target: isl; property: "tuck"; to: 0; duration: isl.sys.animMs; easing.type: Easing.OutCubic }
            OpacityAnimator { target: scrim; to: 1; duration: isl.sys.animMs; easing.type: Easing.OutCubic }
        }
    }

    SequentialAnimation {
        id: growMotion
        PauseAnimation { duration: isl.sys.warmMs }
        ParallelAnimation {
            NumberAnimation { target: isl; property: "morph"; to: 1; duration: isl.sys.animMs + 20; easing.type: Easing.OutCubic }
            OpacityAnimator { target: scrim; to: 1; duration: isl.sys.animMs; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: Math.round(isl.sys.animMs * 0.45) }
                OpacityAnimator { target: contentHolder; to: 1; duration: Math.round(isl.sys.animMs * 0.55); easing.type: Easing.OutCubic }
            }
        }
    }

    // The shrink is geometry on the GUI thread; Panacea only hides the page
    // it dropped and destroys it once this is over (drawerKeep).
    SequentialAnimation {
        id: handoffMotion
        OpacityAnimator { target: card; from: 0; to: 1; duration: Math.round(isl.sys.animFast * 0.6); easing.type: Easing.OutCubic }
        ScriptAction { script: isl.sys.dropDrawer() }
        ParallelAnimation {
            NumberAnimation { target: isl; property: "morph"; from: 0; to: 1; duration: isl.sys.animMs + 20; easing.type: Easing.OutCubic }
            OpacityAnimator { target: scrim; to: 1; duration: isl.sys.animMs + 20; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: Math.round((isl.sys.animMs + 20) * 0.45) }
                OpacityAnimator { target: contentHolder; to: 1; duration: Math.round((isl.sys.animMs + 20) * 0.55); easing.type: Easing.OutCubic }
            }
        }
        ScriptAction { script: isl.overBar = false }
    }

    SequentialAnimation {
        id: foldMotion
        ParallelAnimation {
            NumberAnimation { target: isl; property: "tuck"; to: 1; duration: isl.sys.animFast + 40; easing.type: Easing.InCubic }
            OpacityAnimator { target: scrim; to: 0; duration: isl.sys.animFast + 40; easing.type: Easing.InCubic }
        }
        ScriptAction { script: isl.finish() }
    }

    SequentialAnimation {
        id: shrinkMotion
        ParallelAnimation {
            NumberAnimation { target: isl; property: "morph"; to: 0; duration: isl.sys.animFast + 60; easing.type: Easing.InOutCubic }
            OpacityAnimator { target: contentHolder; to: 0; duration: Math.round(isl.sys.animFast * 0.6); easing.type: Easing.OutCubic }
            OpacityAnimator { target: scrim; to: 0; duration: isl.sys.animFast + 60; easing.type: Easing.InCubic }
        }
        ScriptAction { script: isl.finish() }
    }

    // --- the dim -------------------------------------------------------------

    // The bar is drawn above it, so it stays bright, and the bar and the
    // island read as one shape over the windows.
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.30)
        opacity: 0
        z: -1

        MouseArea {
            anchors.fill: parent
            enabled: isl.open
            acceptedButtons: Qt.AllButtons
            onClicked: isl.closeRequested()
        }
    }

    // --- the card ------------------------------------------------------------

    // The card and its flares move as one: out of and back behind the bar.
    Item {
        id: slide
        anchors.fill: parent
        readonly property real reach: (isl.flat ? isl.ownH : isl.ownW) + isl.flare + 8
        transform: Translate {
            x: isl.edge === "left" ? -isl.tuck * slide.reach : isl.edge === "right" ? isl.tuck * slide.reach : 0
            y: isl.edge === "top" ? -isl.tuck * slide.reach : isl.edge === "bottom" ? isl.tuck * slide.reach : 0
        }

        // Flares at the two corners where the card meets the bar. Drawn for
        // the top edge and turned for the others: on a side edge they sit
        // above and below the card, hugging the bar.
        Repeater {
            model: [0, 1]
            NotchCorner {
                required property int modelData
                readonly property bool first: modelData === 0
                visible: isl.flare > 0 && isl.morph > 0.98
                fill: isl.sys.colBg
                r: isl.flare
                side: isl.flat ? (first ? "left" : "right")
                                : (isl.edge === "left" ? "right" : "left")
                // the square where the card meets the bar; the corner reaches
                // past it under both (NotchCorner.overlap)
                sqX: isl.flat ? (first ? isl.cardX - r : isl.cardX + isl.cardW)
                     : isl.edge === "left" ? isl.cardX + isl.overlap
                     : isl.cardX + isl.cardW - isl.overlap - r
                sqY: isl.flat ? (isl.edge === "top" ? isl.cardY + isl.overlap
                                                     : isl.cardY + isl.cardH - isl.overlap - r)
                     : (first ? isl.cardY - r : isl.cardY + isl.cardH)
                flip: isl.flat ? isl.edge === "bottom" : first
            }
        }

        Rectangle {
            id: card
            // Not rounded: whole pixels made the shape step against its own
            // curve at the slow end of a motion. At rest it is on whole
            // pixels anyway (ownX/ownY), and the content always is.
            x: isl.cardX
            y: isl.cardY
            width: isl.cardW
            height: isl.cardH
            color: isl.sys.colBg
            // square where it meets the bar, round on its free sides
            topLeftRadius: isl.edge === "top" || isl.edge === "left" ? 0 : isl.freeR
            topRightRadius: isl.edge === "top" || isl.edge === "right" ? 0 : isl.freeR
            bottomLeftRadius: isl.edge === "bottom" || isl.edge === "left" ? 0 : isl.freeR
            bottomRightRadius: isl.edge === "bottom" || isl.edge === "right" ? 0 : isl.freeR
            clip: true

            // a tab of another height: the card follows it (a bottom edge
            // grows it upward, so y moves too)
            Behavior on height {
                enabled: isl.busy && isl.morph >= 1 && isl.tuck <= 0
                NumberAnimation { duration: isl.sys.animMs; easing.type: Easing.InOutCubic }
            }
            Behavior on y {
                enabled: isl.busy && isl.morph >= 1 && isl.tuck <= 0
                NumberAnimation { duration: isl.sys.animMs; easing.type: Easing.InOutCubic }
            }

            // clicks on the card stay on the card
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            // While it changes shape the content sits where the island will
            // be: it never reflows, the card shows what fits. Settled, it
            // moves with the card.
            Item {
                id: contentHolder
                x: isl.pad + (isl.edge === "left" ? isl.overlap + isl.inset : 0)
                   + (isl.morph < 1 ? Math.round(isl.ownX) - card.x : 0)
                y: isl.pad + (isl.edge === "top" ? isl.overlap + isl.inset : 0)
                   + (isl.morph < 1 ? Math.round(isl.ownY) - card.y : 0)
                width: isl.contentWidth
                height: isl.contentHeight

                Loader {
                    id: loader
                    width: parent.width
                    focus: true
                    active: !!isl.content && (isl.open || isl.busy)
                    sourceComponent: isl.content
                    Keys.onEscapePressed: isl.closeRequested()
                }
            }
        }
    }
}
