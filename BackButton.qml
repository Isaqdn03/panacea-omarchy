import QtQuick
import QtQuick.Layouts

// The back arrow at the start of every panel's header. One look and one
// behaviour everywhere: sys.goBack() walks back through the panels opened
// since the drawer opened, and lands on Control Center when there is nothing
// further back.
Rectangle {
    id: btn

    property var sys
    // Optional function run first; return true when it handled the click
    // itself (a page stepping out of its own submenu), false to go back.
    property var before: null

    Layout.preferredWidth: 30
    Layout.preferredHeight: 30
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: 30
    implicitHeight: 30
    radius: 10
    color: Qt.rgba(btn.sys.colFg.r, btn.sys.colFg.g, btn.sys.colFg.b, ma.containsMouse ? 0.13 : 0.06)
    Behavior on color { ColorAnimation { duration: 150 } }

    Text {
        anchors.centerIn: parent
        text: String.fromCodePoint(0xF004D)   // md-arrow_left
        color: ma.containsMouse ? btn.sys.colFg : btn.sys.colMuted
        font { family: btn.sys.fontFam; pixelSize: btn.sys.iconSize - 4 }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (typeof btn.before === "function" && btn.before()) return;
            btn.sys.goBack();
        }
    }
}
