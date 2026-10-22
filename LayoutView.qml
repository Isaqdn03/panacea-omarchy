import QtQuick
import QtQuick.Layouts

// PANACEA-LOCAL: the layout island's content (BarIsland.qml): the bar's
// shape, its edge and auto-hide, applied as they are picked. Moving the bar
// takes the island with it (sys.moveBar): it folds into the bar, the bar
// goes to its new place, and the island comes back out of it there.
//
// The picture is the screen, with the bar drawn where and as it is; a click
// near one of its edges moves the bar there.
ColumnLayout {
    id: view

    property var sys

    spacing: 14

    readonly property var shapes: [
        { id: "rail", text: "Rail" },
        { id: "pill", text: "Pill" }
    ]
    readonly property var edges: [
        { id: "top", text: "Top" },
        { id: "bottom", text: "Bottom" },
        { id: "left", text: "Left" },
        { id: "right", text: "Right" }
    ]

    // --------------------------------------------------------------- header
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            text: "Layout"
            color: view.sys.colFg
            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize + 1; bold: true }
        }
        Text {
            Layout.fillWidth: true
            text: "Where the bar sits and how it behaves"
            color: view.sys.colMuted
            elide: Text.ElideRight
            font { family: view.sys.fontBody; pixelSize: view.sys.fontSize - 4 }
        }
    }

    // How a bar looks on the picture, on a given edge. (Inline components
    // cannot see this file's ids, so each is told its picture and Panacea.)
    component BarMark: Rectangle {
        property Item pic
        property string edge: "top"
        property bool rail: true
        readonly property bool flat: edge === "top" || edge === "bottom"
        readonly property real thick: 7
        readonly property real inset: 6
        width: flat ? (rail ? pic.width - inset * 2 : pic.width * 0.22) : thick
        height: flat ? thick : (rail ? pic.height - inset * 2 : pic.height * 0.34)
        x: edge === "left" ? inset : edge === "right" ? pic.width - width - inset
                                   : Math.round((pic.width - width) / 2)
        y: edge === "top" ? inset : edge === "bottom" ? pic.height - height - inset
                                  : Math.round((pic.height - height) / 2)
        radius: thick / 2
    }

    // -------------------------------------------------------------- picture
    // The screen at its own proportions, the bar drawn on it.
    Rectangle {
        id: screenPic
        Layout.fillWidth: true
        readonly property real aspect: view.sys.screen && view.sys.screen.height > 0
                                       ? view.sys.screen.width / view.sys.screen.height : 16 / 9
        Layout.preferredHeight: Math.round(width / aspect)
        radius: 12
        color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.05)
        border.width: 1
        border.color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.10)

        // the edge under the pointer, which a click would pick
        property string hoverEdge: ""
        function edgeAt(px, py) {
            var dx = Math.min(px, width - px) / width;
            var dy = Math.min(py, height - py) / height;
            if (dx < dy) return px < width / 2 ? "left" : "right";
            return py < height / 2 ? "top" : "bottom";
        }

        // where the bar would go
        BarMark {
            pic: screenPic
            edge: screenPic.hoverEdge || "top"
            rail: view.sys.railMode
            visible: picMa.containsMouse && screenPic.hoverEdge.length > 0
                     && screenPic.hoverEdge !== view.sys.pillPos
            color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.22)
        }
        // where it is
        BarMark {
            pic: screenPic
            edge: view.sys.pillPos
            rail: view.sys.railMode
            color: view.sys.colFg
        }

        MouseArea {
            id: picMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: mouse => screenPic.hoverEdge = screenPic.edgeAt(mouse.x, mouse.y)
            onExited: screenPic.hoverEdge = ""
            onClicked: mouse => view.sys.moveBar(view.sys.barShape, screenPic.edgeAt(mouse.x, mouse.y))
        }
    }

    // -------------------------------------------------------------- choices
    component Choice: RowLayout {
        id: choice
        property var sys
        property string label: ""
        property var options: []
        property string value: ""
        signal picked(string id)

        Layout.fillWidth: true
        spacing: 12

        Text {
            Layout.fillWidth: true
            text: choice.label
            color: choice.sys.colFg
            elide: Text.ElideRight
            font { family: choice.sys.fontBody; pixelSize: choice.sys.fontSize - 1 }
        }

        Rectangle {
            Layout.preferredWidth: segs.implicitWidth + 6
            Layout.preferredHeight: 32
            radius: 16
            color: Qt.rgba(choice.sys.colFg.r, choice.sys.colFg.g, choice.sys.colFg.b, 0.06)

            Row {
                id: segs
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: choice.options
                    Rectangle {
                        id: seg
                        required property var modelData
                        readonly property bool active: choice.value === seg.modelData.id
                        width: segText.implicitWidth + 24
                        height: 26
                        radius: 13
                        // the picked one is a solid pill; the others only
                        // answer the pointer
                        color: seg.active ? choice.sys.colFg
                             : segMa.containsMouse ? Qt.rgba(choice.sys.colFg.r, choice.sys.colFg.g, choice.sys.colFg.b, 0.08)
                             : "transparent"
                        Behavior on color { ColorAnimation { duration: choice.sys.animHover } }

                        Text {
                            id: segText
                            anchors.centerIn: parent
                            text: seg.modelData.text
                            color: seg.active ? choice.sys.colBg : choice.sys.colMuted
                            font { family: choice.sys.fontBody; pixelSize: choice.sys.fontSize - 3; bold: seg.active }
                        }
                        MouseArea {
                            id: segMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: choice.picked(seg.modelData.id)
                        }
                    }
                }
            }
        }
    }

    Choice {
        sys: view.sys
        label: "Shape"
        options: view.shapes
        value: view.sys.barShape
        onPicked: id => view.sys.moveBar(id, view.sys.pillPos)
    }

    Choice {
        sys: view.sys
        label: "Edge"
        options: view.edges
        value: view.sys.pillPos
        onPicked: id => view.sys.moveBar(view.sys.barShape, id)
    }

    SetToggle {
        sys: view.sys
        label: "Auto-hide"
        sub: view.sys.cfg.pillAutoHide ? "Floats over windows and shows at the edge"
                                       : "Stays out and keeps windows clear of it"
        on: view.sys.cfg.pillAutoHide
        onToggled: value => { view.sys.cfg.pillAutoHide = value; view.sys.saveCfg(); }
    }
}
