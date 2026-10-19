import QtQuick
import QtQuick.Layouts

// Notifications. Главное здесь — «не беспокоить» и время жизни карточки.
// Важные уведомления по умолчанию не гаснут сами: на них отвечают.
//
// Panacea is the notification daemon on this Omarchy install (Omarchy's own
// notification service is disabled), so these apply to every notification.
ColumnLayout {
    id: page

    property var sys

    Layout.fillWidth: true
    spacing: 12

    SetCard {
        sys: page.sys

        SetToggle {
            sys: page.sys
            label: "Do not disturb"
            sub: "Only critical notifications get through; the rest go straight to the history. "
                 + "Same switch as Omarchy's notification silencing."
            on: page.sys.dnd
            onToggled: v => page.sys.setDnd(v)
        }

        Text {
            Layout.fillWidth: true
            text: "Omarchy's notification keys work here too: SUPER + , dismisses, SUPER + SHIFT + , "
                  + "dismisses all, SUPER + ALT + , opens the last one, SUPER + SHIFT + ALT + , shows the history."
            color: page.sys.colMuted
            wrapMode: Text.WordWrap
            font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
        }
    }

    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: page.sys.tr("Время и количество") }

        SetSlider {
            sys: page.sys
            label: page.sys.tr("Сколько висит обычное")
            from: 1000; to: 20000; step: 500
            value: page.sys.cfg.notifTimeout
            valueText: (page.sys.cfg.notifTimeout / 1000).toFixed(1) + " s"
            onMoved: v => { page.sys.cfg.notifTimeout = v; page.sys.saveCfg(); }
        }

        SetSlider {
            sys: page.sys
            label: page.sys.tr("Сколько висит важное")
            from: 0; to: 60000; step: 1000
            value: page.sys.cfg.notifCritTimeout
            // ноль — карточка не гаснет сама, и это нужно сказать словом
            valueText: page.sys.cfg.notifCritTimeout === 0
                       ? page.sys.tr("до ответа")
                       : (page.sys.cfg.notifCritTimeout / 1000).toFixed(0) + " s"
            onMoved: v => { page.sys.cfg.notifCritTimeout = v; page.sys.saveCfg(); }
        }

    }

    SetCard {
        sys: page.sys

        SetLabel { sys: page.sys; text: page.sys.tr("Содержимое") }

        SetToggle {
            sys: page.sys
            label: page.sys.tr("Показывать текст в карточке")
            sub: page.sys.tr("Выключено — видно только приложение и заголовок.")
            on: page.sys.cfg.notifPreview
            onToggled: v => { page.sys.cfg.notifPreview = v; page.sys.saveCfg(); }
        }

    }
}
