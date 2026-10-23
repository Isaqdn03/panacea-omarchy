import QtQuick

// PANACEA-LOCAL: one of the two slots Panacea's open page lives in
// (Panacea.qml, pageHost). A slot holds a view; a new one is built in the
// spare slot and drawn, all but invisibly, before it takes the front. The
// page's first frame is slow to reach the screen, and taken while the panel
// changed shape, it froze that motion.
Loader {
    id: slot

    property var sys
    property var host
    property bool isFront: false
    // the view loaded here ("" for none) and the page it was loaded for
    property string view: ""
    property string pageName: ""
    // drawn once already: it can take the front with nothing to wait for
    property bool warm: false

    // In front, where the page shows; it stays there while that surface
    // closes, so the page goes with it. Otherwise in the bar, which is always
    // drawn, so a page warming there is drawn too.
    parent: isFront ? host.destination : host.warmPlace
    z: 10
    // A Loader is a focus scope: the page in it gets keys only while this
    // has focus (the page in front)
    focus: isFront
    anchors.top: parent ? parent.top : undefined
    anchors.topMargin: 15
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    // Ширина берётся у ЦЕЛЕВОЙ панели, а не у анимируемой капсулы:
    // иначе содержимое переливалось по ширине на каждом кадре
    // сворачивания и выглядело как размазанная краска.
    width: (sys.isModalPage(pageName) ? sys.settingsW : sys.panelW) - 30
    active: view !== ""
    sourceComponent: active ? sys.pageComp(view) : null
    // A view with sub-pages (Control Center) shows the one it was loaded
    // for, not sys.page: that moves on while the next view is still being
    // drawn behind this one.
    onLoaded: if (item && item.page !== undefined) item.page = Qt.binding(() => slot.pageName)
    // Esc закрывает любую страницу: если сам вид его не обработал
    // (или обработал только на подстранице), событие всплывает сюда.
    // Сначала спрашиваем вид, есть ли ему куда вернуться: со списка
    // сетей или устройств Escape должен уводить к плиткам, а не
    // захлопывать панель целиком.
    Keys.onEscapePressed: sys.escapeFromPage()

    // On screen while the surface is open. In the modal the card itself
    // fades, so its page stays as it is while it goes.
    property real shownAmount: isFront && (sys.shaped || (sys.modalMode && !(sys.expanded && !sys.shaped)))
                               ? 1 : 0
    Behavior on shownAmount {
        id: shownB
        enabled: !slot.sys.modalMode
        NumberAnimation { duration: shownB.targetValue > 0.5 ? slot.sys.animFast : 90; easing.type: Easing.OutCubic }
    }
    // warming: drawn from the first frame, at an opacity no one can see
    opacity: Math.max(shownAmount, !isFront && host.warming ? 0.01 : 0)
    visible: opacity > 0 && host.allowed
}
