import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// PANACEA-LOCAL: content of the rail (root.railMode), on any edge. Three
// groups pinned to the rail's ends and middle: workspaces first, the clock in
// the middle, status last; top to bottom on a side rail, left to right on a
// top or bottom one (flat). Nothing here fills the rail with a MouseArea: a
// click on empty rail falls through to the capsule, which opens the drawer.
Item {
    id: rail
    property var sys
    readonly property bool flat: !sys.pillSide

    readonly property string hours: String(sys.timeText.split(":")[0] || "")
    readonly property string rest: String(sys.timeText.split(":")[1] || "")
    readonly property string minutes: rest.replace(/[^0-9]/g, "")
    readonly property string ampm: rest.replace(/[^A-Za-z]/g, "")
    // A level OSD (volume, mic, brightness) takes the rail's place while it
    // is up; text OSDs and notifications go to root.railCard instead.
    readonly property bool osdOn: sys.osdActive && sys.osdKind !== "msg"

    // ------------------------------------------------------------ workspaces
    Grid {
        opacity: rail.osdOn ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }
        // Placed by x and y, not anchors: anchors switched between edges at
        // run time left the group with a stale size (2708 x -6) once the
        // rail went from top to side.
        x: rail.flat ? 22 : Math.round((rail.width - width) / 2)
        y: rail.flat ? Math.round((rail.height - height) / 2) : 22
        // a row on a flat rail, a column on a side one. Only columns: Grid
        // will not take 0 back as "auto", so rows can never be reset.
        columns: rail.flat ? 99 : 1
        spacing: rail.flat ? 4 : 6

        Repeater {
            model: rail.sys.wsList
            Item {
                id: wsCell
                required property int modelData
                readonly property bool current: modelData === rail.sys.wsId
                width: 28
                height: 26

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: Qt.rgba(1, 1, 1, wsCell.current ? 0.10 : (wsMa.containsMouse ? 0.05 : 0))
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: rail.sys.wsLabel(wsCell.modelData)
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
    Row {
        opacity: rail.osdOn ? 0 : 1
        visible: rail.flat && opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rail.sys.timeText
            color: rail.sys.colFg
            font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize; bold: true }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rail.sys.dayText + " " + rail.sys.dayNum
            color: rail.sys.colMuted
            font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 3; bold: true }
        }
    }
    Column {
        opacity: rail.osdOn ? 0 : 1
        visible: !rail.flat && opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }
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
    Grid {
        opacity: rail.osdOn ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }
        x: rail.flat ? rail.width - width - 22 : Math.round((rail.width - width) / 2)
        y: rail.flat ? Math.round((rail.height - height) / 2) : rail.height - height - 22
        columns: rail.flat ? 99 : 1
        spacing: rail.flat ? 18 : 14
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        // music: cover art; click opens the player
        Item {
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
            visible: rail.sys.recActive
            width: 8
            height: 8
            radius: 4
            color: rail.sys.recPaused ? rail.sys.colWarn : rail.sys.colCrit
        }

        // agent usage
        Item {
            visible: rail.sys.usagePct >= 0
            width: usageCol.implicitWidth
            height: usageCol.implicitHeight

            Grid {
                id: usageCol
                columns: rail.flat ? 99 : 1
                spacing: rail.flat ? 5 : 2
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                Glyph {
                    glyph: String.fromCodePoint(0xF1719)   // md-robot_outline
                    color: rail.sys.usageColor()
                    fontFam: rail.sys.fontFam
                    size: rail.sys.fontSize - 1
                }
                Text {
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
            visible: rail.sys.ghCount > 0
            width: ghCol.implicitWidth
            height: ghCol.implicitHeight

            Grid {
                id: ghCol
                columns: rail.flat ? 99 : 1
                spacing: rail.flat ? 5 : 2
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                Glyph {
                    glyph: String.fromCodePoint(0xF02A4)   // md-github
                    color: rail.sys.colMuted
                    fontFam: rail.sys.fontFam
                    size: rail.sys.fontSize - 1
                }
                Text {
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

        // battery: same colours as the pill's; click opens the battery page
        Item {
            id: battItem
            visible: rail.sys.batteryPresent
            width: battCol.implicitWidth
            height: battCol.implicitHeight

            readonly property color tint: rail.sys.batteryCharging || rail.sys.acOnline ? rail.sys.colOk
                                        : rail.sys.batteryPct <= 15 ? rail.sys.colCrit : rail.sys.colMuted

            Grid {
                id: battCol
                columns: rail.flat ? 99 : 1
                spacing: rail.flat ? 5 : 2
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                Text {
                    text: rail.sys.batteryIcon
                    color: battItem.tint
                    font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 1 }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                Text {
                    text: rail.sys.batteryPct + "%"
                    color: rail.sys.batteryPct <= 15 && !rail.sys.acOnline ? rail.sys.colCrit : rail.sys.colFg
                    font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 5; bold: true }
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: rail.sys.openSub("battery")
            }
        }

        // network: cable or Wi-Fi; click opens the drawer's tiles
        Item {
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

    // ------------------------------------------------------------------ OSD
    // the level for volume / mic / brightness, in place of the rail's
    // contents while the OSD is up, along the rail; same colours as the
    // pill's level bar
    Grid {
        anchors.centerIn: parent
        columns: rail.flat ? 99 : 1
        spacing: 10
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        opacity: rail.osdOn ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Text {
            text: rail.sys.osdIcon
            color: rail.sys.osdMuted ? rail.sys.colMuted : rail.sys.colFg
            font { family: rail.sys.fontFam; pixelSize: rail.sys.iconSize }
        }
        Rectangle {
            readonly property real level: rail.sys.osdMuted ? 0 : rail.sys.osdValue
            width: rail.flat ? 260 : 6
            height: rail.flat ? 6 : Math.round(rail.height * 0.34)
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.16)
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: rail.flat ? parent.width * parent.level : parent.width
                height: rail.flat ? parent.height : parent.height * parent.level
                radius: 3
                color: rail.sys.osdKind === "bright" ? rail.sys.colWarn : rail.sys.colOn
                Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            text: rail.sys.osdMuted ? "—" : Math.round(rail.sys.osdValue * 100) + "%"
            color: rail.sys.colMuted
            font { family: rail.sys.fontFam; pixelSize: rail.sys.fontSize - 5; bold: true }
        }
    }
}
