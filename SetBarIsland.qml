import QtQuick
import QtQuick.Layouts

// Bar & Island.
//
// PANACEA-LOCAL: the bar's own settings (its place, shape, look, sizes and
// pages) live in the Layout island, which comes out of the bar itself
// (BarIsland.qml, LayoutView.qml); this page only points there. What stays
// here is not about the bar: what Super+Q closes.
ColumnLayout {
    id: page

    property var sys

    Layout.fillWidth: true
    spacing: 12

    SetCard {
        sys: page.sys

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: "Layout"
                    color: page.sys.colFg
                    font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 1 }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Where the bar sits, how it looks and what opens out of it, in an island that comes out of the bar. Changes show on the bar as you make them."
                    color: page.sys.colMuted
                    wrapMode: Text.WordWrap
                    font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
                }
            }

            SetButton {
                sys: page.sys
                text: "Open Layout"
                onClicked: page.sys.openLayout()
            }
        }
    }

    SetCard {
        sys: page.sys

        SetToggle {
            sys: page.sys
            label: page.sys.tr("Закрывать окна Panacea по Super+Q")
            sub: page.sys.tr("При открытых панелях или настройках Panacea нажатие Super+Q закрывает оверлей. Выключить — Super+Q всегда закрывает активное приложение на фоне.")
            on: page.sys.cfg.closePanaceaFirst
            onToggled: value => { page.sys.cfg.closePanaceaFirst = value; page.sys.saveCfg(); }
        }
    }
}
