import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// PANACEA-LOCAL: content of the full-height rail on the left edge
// (root.railMode, i.e. pillPos "left"). Three groups pinned to the rail's
// ends and middle: workspaces at the top, the clock in the middle, status at
// the bottom. Nothing here fills the rail with a MouseArea: a click on empty
// rail falls through to the capsule, which opens the drawer.
Item {
    id: rail
    property var sys

    readonly property string hours: String(sys.timeText.split(":")[0] || "")
    readonly property string rest: String(sys.timeText.split(":")[1] || "")
    readonly property string minutes: rest.replace(/[^0-9]/g, "")
    readonly property string ampm: rest.replace(/[^A-Za-z]/g, "")

    // ------------------------------------------------------------ workspaces
    Column {
        anchors.top: parent.top
        anchors.topMargin: 22
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        Repeater {
            model: rail.sys.wsList
            Item {
                id: wsCell
                required property int modelData
                readonly property bool current: modelData === rail.sys.wsId
                width: 30
                height: 26

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: Qt.rgba(1, 1, 1, wsCell.current ? 0.10 : (wsMa.containsMouse ? 0.05 : 0))
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: String(wsCell.modelData)
                    color: wsCell.current ? rail.sys.colFg : rail.sys.colMuted
                    font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 2; bold: wsCell.current }
                }
                MouseArea {
                    id: wsMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rail.sys.gotoWorkspace(wsCell.modelData)
                }
            }
        }
    }

    // ----------------------------------------------------------------- clock
    Column {
        anchors.centerIn: parent
        spacing: 1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: rail.hours
            color: rail.sys.colFg
            font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize + 3; bold: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: rail.minutes
            color: rail.sys.colFg
            font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize + 3; bold: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: rail.ampm.length > 0
            text: rail.ampm
            color: rail.sys.colMuted
            font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 5; bold: true }
        }
        Item { width: 1; height: 8 }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 14
            height: 1
            color: Qt.rgba(1, 1, 1, 0.18)
        }
        Item { width: 1; height: 8 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: rail.sys.dayText
            color: rail.sys.colMuted
            font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 4; bold: true }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: rail.sys.dayNum
            color: rail.sys.colMuted
            font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 4; bold: true }
        }
    }

    // ---------------------------------------------------------------- status
    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14

        // music: cover art; click opens the player
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: rail.sys.mediaActive
            width: 24
            height: 24

            Rectangle {
                anchors.fill: parent
                radius: 7
                color: Qt.rgba(1, 1, 1, 0.08)

                Image {
                    id: railArt
                    anchors.fill: parent
                    source: rail.sys.mediaArt
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 64
                    visible: false
                    layer.enabled: true
                }
                Item {
                    id: railArtMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: 7; color: "#ffffff" }
                }
                MultiEffect {
                    anchors.fill: parent
                    source: railArt
                    maskEnabled: true
                    maskSource: railArtMask
                    visible: railArt.status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: railArt.status !== Image.Ready
                    text: "󰝚"
                    color: rail.sys.colMuted
                    font { family: rail.sys.fontFam; pixelSize: 12 }
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rail.sys.togglePage("media")
            }
        }

        // screen recording in progress
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: rail.sys.recActive
            width: 8
            height: 8
            radius: 4
            color: rail.sys.recPaused ? rail.sys.colWarn : rail.sys.colCrit
        }

        // agent usage
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: rail.sys.usagePct >= 0
            width: usageCol.implicitWidth
            height: usageCol.implicitHeight

            Column {
                id: usageCol
                spacing: 2
                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    glyph: String.fromCodePoint(0xF1719)   // md-robot_outline
                    color: rail.sys.usageColor()
                    fontFam: rail.sys.fontFam
                    size: rail.sys.fontSize - 1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: rail.sys.usagePct + "%"
                    color: rail.sys.usageColor()
                    font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 5; bold: true }
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rail.sys.openAgents()
            }
        }

        // GitHub inbox
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: rail.sys.ghCount > 0
            width: ghCol.implicitWidth
            height: ghCol.implicitHeight

            Column {
                id: ghCol
                spacing: 2
                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    glyph: String.fromCodePoint(0xF02A4)   // md-github
                    color: rail.sys.colMuted
                    fontFam: rail.sys.fontFam
                    size: rail.sys.fontSize - 1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: rail.sys.ghCount
                    color: rail.sys.colFg
                    font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 5; bold: true }
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rail.sys.openGithub()
            }
        }

        // network: cable or Wi-Fi; click opens the drawer's tiles
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 24
            height: 22

            LanGlyph {
                anchors.centerIn: parent
                width: rail.sys.iconSize - 6
                height: rail.sys.iconSize - 6
                visible: rail.sys.wiredOn
                color: rail.sys.colMuted
            }
            Text {
                anchors.centerIn: parent
                visible: !rail.sys.wiredOn
                text: rail.sys.wifiOn ? (rail.sys.wifiQuality > 66 ? "󰤨"
                                       : rail.sys.wifiQuality > 33 ? "󰤥" : "󰤟") : "󰤮"
                color: rail.sys.colMuted
                font { family: rail.sys.fontFam; pixelSize: rail.sys.iconSize - 2 }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rail.sys.togglePage("main")
            }
        }
    }
}
