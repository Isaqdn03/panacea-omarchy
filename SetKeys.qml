import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Быстрые клавиши. Открывается отдельным окном, а не разделом настроек: это
// справочник, к которому обращаются посреди работы, и сайдбар со списком
// разделов ему только мешал бы.
//
// Panacea's own shortcuts (its pages, peek, Glass mode). They live in the
// managed block of ~/.config/hypr/bindings.lua as ordinary Omarchy o.bind()
// lines; scripts/hyprconf.py reads them (binds-get) and writes them
// (binds-set). Window and app shortcuts are Omarchy's and stay in Omarchy's
// keybindings list (SUPER + K).
//
// Правки копятся в черновике и уезжают в Hyprland по «Применить». Сразу не
// применяем нарочно: полупустое сочетание, записанное по ходу набора, могло
// бы отобрать клавишу у того, чем её же и правят.
ColumnLayout {
    id: page

    property var sys

    // { actions: [{ id, label, group, combo, default }],
    //   taken: { "SUPER|v": "Universal paste", ... } } -- Omarchy's binds
    property var binds: ({ actions: [], taken: ({}) })
    property bool applying: false

    Process {
        id: pBinds
        command: ["/usr/bin/python3", page.sys.scriptDir + "/hyprconf.py", "binds-get"]
        stdout: SplitParser {
            onRead: line => {
                try { page.binds = JSON.parse(line); } catch (e) { return; }
                // The saved block is back: the draft has become the real thing.
                if (page.applying) { page.applying = false; page.discardBinds(); }
            }
        }
    }
    // The shell re-reads Hyprland once its save queue drains.
    Connections {
        target: page.sys
        function onHyprLiveChanged() { pBinds.running = false; pBinds.running = true; }
        function onHyprErrorChanged() { if (page.sys.hyprError.length) page.applying = false; }
    }

    // ---------------------------------------------------- черновик сочетаний
    property var bindDraft: ({})
    property int bindRev: 0          // счётчик, чтобы привязки перечитались
    readonly property bool dirty: {
        bindRev;
        for (var id in page.bindDraft) return true;
        return false;
    }

    function action(id) {
        var l = page.binds.actions || [];
        for (var i = 0; i < l.length; i++) if (l[i].id === id) return l[i];
        return null;
    }
    function rawCombo(id) {
        page.bindRev;                // зависимость для пересчёта
        if (page.bindDraft[id] !== undefined) return String(page.bindDraft[id]);
        var a = page.action(id);
        return a ? String(a.combo || "") : "";
    }
    function bindCombo(id) { return page.prettyCombo(page.rawCombo(id)); }

    // Same canonical form as hyprconf.py's combo_key().
    function comboKey(raw) {
        var parts = String(raw).split("+").map(p => p.trim()).filter(p => p.length > 0);
        if (!parts.length) return "";
        var key = parts.pop().toLowerCase();
        var mods = parts.map(p => p.toUpperCase());
        return ["SUPER", "CTRL", "ALT", "SHIFT"].filter(m => mods.indexOf(m) >= 0).join(" + ")
               + "|" + key;
    }
    // What the combo does in Omarchy now -- saving will unbind that.
    function conflict(id) {
        var k = page.comboKey(page.rawCombo(id));
        return k.length ? (page.binds.taken[k] || "") : "";
    }
    // Another Panacea action with the same combo (saving refuses that).
    function twin(id) {
        var k = page.comboKey(page.rawCombo(id));
        if (!k.length) return "";
        var l = page.binds.actions || [];
        for (var i = 0; i < l.length; i++)
            if (l[i].id !== id && page.comboKey(page.rawCombo(l[i].id)) === k) return l[i].label;
        return "";
    }

    // Hyprland знает клавиши по именам (slash, comma, period…), а человеку
    // привычнее сам знак. Показываем знак, в настройках лежит имя.
    readonly property var keySigns: ({
        slash: "/", backslash: "\\", comma: ",", period: ".",
        semicolon: ";", apostrophe: "'", grave: "`", minus: "-", equal: "=",
        bracketleft: "[", bracketright: "]", space: "Space", delete: "Del"
    })
    function prettyCombo(raw) {
        var parts = String(raw).split("+");
        for (var i = 0; i < parts.length; i++) {
            var k = parts[i].trim();
            var sign = page.keySigns[k.toLowerCase()];
            parts[i] = sign !== undefined ? sign : k;
        }
        return parts.join(" + ");
    }
    function bindChanged(id) {
        page.bindRev;
        return page.bindDraft[id] !== undefined;
    }
    function setBind(id, combo) {
        page.bindDraft[id] = combo;
        page.bindRev++;
    }
    function clearBind(id) { page.setBind(id, ""); }
    function discardBinds() { page.bindDraft = ({}); page.bindRev++; }

    function applyBinds() {
        var map = {};
        (page.binds.actions || []).forEach(a => map[a.id] = page.rawCombo(a.id));
        page.applying = true;
        page.sys.hyprRun(["binds-set", JSON.stringify(map)]);
    }
    // «Сбросить» возвращает заводские сочетания, а не просто отменяет правки:
    // в черновик кладём всё, что сейчас отличается от значений по умолчанию.
    function resetBinds() {
        var o = {};
        (page.binds.actions || []).forEach(a => {
            if (String(a.combo || "") !== String(a.default || "")) o[a.id] = a.default || "";
        });
        page.bindDraft = o;
        page.bindRev++;
    }

    // ------------------------------------------------------------- захват
    property string capturingKey: ""

    // Что уже нажато прямо сейчас — показывается в строке по мере набора.
    property bool  mMeta:  false
    property bool  mCtrl:  false
    property bool  mAlt:   false
    property bool  mShift: false
    property string pendingName: ""

    readonly property string capturePreview: {
        var m = [];
        if (mMeta)  m.push("SUPER");
        if (mCtrl)  m.push("CTRL");
        if (mAlt)   m.push("ALT");
        if (mShift) m.push("SHIFT");
        if (pendingName.length) m.push(pendingName);
        return m.join(" + ");
    }

    // Пока идёт захват, Hyprland уводится в пустой submap: иначе нажатие
    // срабатывало как уже существующее сочетание и до панели не доходило.
    Process { id: pCapture }
    function grabKeys(on) {
        // Перезапускаем явно: присвоение command работающему Process
        // не вступает в силу, и следующий вход в submap молча пропадал.
        pCapture.running = false;
        pCapture.command = ["sh", "-c",
            page.sys.scriptDir + "/capture.sh " + (on ? "on" : "off")];
        pCapture.running = true;
    }

    function clearHeld() {
        page.mMeta = false; page.mCtrl = false; page.mAlt = false; page.mShift = false;
        page.pendingName = "";
    }

    function startCapture(key) {
        page.capturingKey = key;
        page.clearHeld();
        page.forceActiveFocus();
        page.grabKeys(true);
        captureTimeout.restart();
    }
    function stopCapture() {
        if (page.capturingKey.length === 0) return;   // уже остановлен
        page.capturingKey = "";
        page.clearHeld();
        captureTimeout.stop();
        page.grabKeys(false);
    }

    // страховка: не оставлять систему без горячих клавиш
    Timer {
        id: captureTimeout
        interval: 8000
        onTriggered: page.stopCapture()
    }

    Connections {
        target: page.sys
        // приходит из capture.sh off; если захват уже снят — ничего не делаем
        function onCancelCaptureRequested() {
            if (page.capturingKey.length) page.stopCapture();
        }
    }

    readonly property var modKeys: [
        Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr,
        Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_CapsLock
    ]

    function isMeta(k)  { return k === Qt.Key_Meta || k === Qt.Key_Super_L || k === Qt.Key_Super_R; }
    function isCtrl(k)  { return k === Qt.Key_Control; }
    function isAlt(k)   { return k === Qt.Key_Alt || k === Qt.Key_AltGr; }
    function isShift(k) { return k === Qt.Key_Shift; }

    // Имя обычной клавиши в терминах Hyprland
    function keyName(k) {
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k);
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k);
        if (k >= Qt.Key_F1 && k <= Qt.Key_F12) return "F" + (k - Qt.Key_F1 + 1);
        switch (k) {
            case Qt.Key_Space:  return "Space";
            case Qt.Key_Return:
            case Qt.Key_Enter:  return "Return";
            case Qt.Key_Tab:    return "Tab";
            case Qt.Key_Left:   return "left";
            case Qt.Key_Right:  return "right";
            case Qt.Key_Up:     return "up";
            case Qt.Key_Down:   return "down";
            case Qt.Key_Comma:  return "comma";
            case Qt.Key_Period: return "period";
            case Qt.Key_Slash:  return "slash";
            case Qt.Key_Minus:  return "minus";
            case Qt.Key_Equal:  return "equal";
            case Qt.Key_BracketLeft:  return "bracketleft";
            case Qt.Key_BracketRight: return "bracketright";
            case Qt.Key_Semicolon:    return "semicolon";
            case Qt.Key_Apostrophe:   return "apostrophe";
            case Qt.Key_Backslash:    return "backslash";
            case Qt.Key_Delete:       return "delete";
            case Qt.Key_Insert:       return "insert";
            case Qt.Key_Home:         return "home";
            case Qt.Key_End:          return "end";
            case Qt.Key_PageUp:       return "Page_Up";
            case Qt.Key_PageDown:     return "Page_Down";
            case Qt.Key_Backspace:    return "BackSpace";
            case Qt.Key_Print:        return "Print";
            case Qt.Key_Pause:        return "Pause";
            case Qt.Key_Menu:         return "Menu";
        }
        return "";
    }

    focus: true

    Keys.onPressed: event => {
        if (page.capturingKey.length === 0) {
            if (event.key === Qt.Key_Escape) {
                page.sys.keysWindowOpen = false;
                event.accepted = true;
                return;
            }
            // Super + / закрывает окно тем же сочетанием, что открыло. До
            // Hyprland оно не доходит: пока окно на экране, слой держит
            // клавиатуру эксклюзивно, и биндинг компоситора не срабатывает —
            // поэтому ловим сочетание здесь.
            if (event.key === Qt.Key_Slash && (event.modifiers & Qt.MetaModifier)) {
                page.sys.keysWindowOpen = false;
                event.accepted = true;
            }
            return;
        }
        event.accepted = true;
        captureTimeout.restart();

        if (event.key === Qt.Key_Escape) { page.stopCapture(); return; }

        // Модификаторы отмечаем сразу — они появляются в строке по мере нажатия.
        // Qt в событии самого модификатора его ещё не показывает, поэтому
        // смотрим и на код клавиши, и на маску.
        page.mMeta  = page.mMeta  || page.isMeta(event.key)  || (event.modifiers & Qt.MetaModifier)    !== 0;
        page.mCtrl  = page.mCtrl  || page.isCtrl(event.key)  || (event.modifiers & Qt.ControlModifier) !== 0;
        page.mAlt   = page.mAlt   || page.isAlt(event.key)   || (event.modifiers & Qt.AltModifier)     !== 0;
        page.mShift = page.mShift || page.isShift(event.key) || (event.modifiers & Qt.ShiftModifier)   !== 0;

        if (page.modKeys.indexOf(event.key) >= 0) return;   // ждём настоящую клавишу

        var n = page.keyName(event.key);
        if (n.length === 0) return;
        page.pendingName = n;

        // сочетание собрано — запоминаем в черновик, применится по «Применить»
        var target = page.capturingKey;
        var combo = page.capturePreview;
        page.stopCapture();
        page.setBind(target, combo);
    }

    Keys.onReleased: event => {
        if (page.capturingKey.length === 0) return;
        event.accepted = true;
        if (page.isMeta(event.key))  page.mMeta = false;
        if (page.isCtrl(event.key))  page.mCtrl = false;
        if (page.isAlt(event.key))   page.mAlt = false;
        if (page.isShift(event.key)) page.mShift = false;
    }

    Component.onCompleted: { pBinds.running = true; page.forceActiveFocus(); }
    Component.onDestruction: {
        // не оставляем систему без горячих клавиш
        if (page.capturingKey.length) page.grabKeys(false);
    }

    // ------------------------------------------------------------ строки
    component BindRow: RowLayout {
        id: brow
        property string bindId: ""
        property string label: ""
        readonly property bool capturing: page.capturingKey === brow.bindId
        readonly property string combo: page.bindCombo(brow.bindId)
        readonly property bool edited: page.bindChanged(brow.bindId)
        readonly property string clash: page.conflict(brow.bindId)
        readonly property string twin: page.twin(brow.bindId)

        // Строки делят высоту колонки между собой: карточка занимает почти
        // весь экран, и без растяжения список сбивался бы к верхнему краю,
        // оставляя под собой пустое поле. Потолок нужен, чтобы на высоком
        // экране строки не разъезжались в разрежённый список.
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.maximumHeight: 56
        spacing: 14

        Rectangle {
            id: box
            Layout.preferredWidth: 176
            Layout.preferredHeight: 32
            Layout.alignment: Qt.AlignVCenter
            radius: 9
            color: brow.capturing
                   ? Qt.rgba(page.sys.colOn.r, page.sys.colOn.g, page.sys.colOn.b, 0.20)
                   : (bMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07))
            border.color: brow.capturing ? page.sys.colOn
                          : (brow.twin.length ? page.sys.colCrit : page.sys.colLine)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on border.color { ColorAnimation { duration: 160 } }

            SequentialAnimation {
                running: brow.capturing
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { target: box; property: "opacity"; to: 0.45; duration: 520 }
                NumberAnimation { target: box; property: "opacity"; to: 1.0;  duration: 520 }
            }

            Text {
                anchors.centerIn: parent
                // во время захвата показываем то, что уже нажато
                text: brow.capturing
                      ? (page.capturePreview.length ? page.capturePreview
                                                    : page.sys.tr("Нажмите сочетание…"))
                      : (brow.combo.length ? brow.combo : "—")
                color: brow.combo.length || brow.capturing ? page.sys.colFg : page.sys.colMuted
                font { family: page.sys.fontFam; pixelSize: page.sys.fontSize - 4; bold: true }
            }

            // точка-отметка: сочетание изменено, но ещё не применено
            Rectangle {
                width: 6; height: 6; radius: 3
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 5
                visible: brow.edited
                color: page.sys.colOk
            }

            MouseArea {
                id: bMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.startCapture(brow.bindId)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: brow.label
                color: page.sys.colMuted
                elide: Text.ElideRight
                font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 2 }
            }
            Text {
                Layout.fillWidth: true
                visible: brow.twin.length > 0 || brow.clash.length > 0
                text: brow.twin.length ? "Also set for " + brow.twin
                                       : "Replaces Omarchy's “" + brow.clash + "”"
                color: brow.twin.length ? page.sys.colCrit : page.sys.colWarn
                elide: Text.ElideRight
                font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 5 }
            }
        }

        Text {
            text: "×"
            visible: brow.combo.length > 0
            color: cMa.containsMouse ? page.sys.colCrit : page.sys.colMuted
            font { family: page.sys.fontFam; pixelSize: page.sys.fontSize + 2 }
            Behavior on color { ColorAnimation { duration: 150 } }
            MouseArea {
                id: cMa
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.clearBind(brow.bindId)
            }
        }
    }


    // Заголовок группы. Не SetLabel: тот рассчитан на карточку настроек, а
    // здесь колонки идут сплошным списком, и ему нужен отступ сверху.
    component Head: Text {
        Layout.fillWidth: true
        Layout.topMargin: 8
        color: page.sys.colMuted
        font {
            family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4
            bold: true; capitalization: Font.AllUppercase; letterSpacing: 1
        }
    }

    // =========================================================== раскладка
    // Прокрутки нет: две колонки по дюжине строк помещаются целиком, и
    // строки растягиваются по высоте карточки, а не жмутся к верхнему краю.
    Layout.fillWidth: true
    spacing: 10

    Text {
        Layout.fillWidth: true
        text: "Click a shortcut to change it, × removes it. Saved in ~/.config/hypr/bindings.lua. "
              + "Window and app shortcuts are Omarchy's: SUPER + K lists them all."
        color: Qt.rgba(1, 1, 1, 0.32)
        wrapMode: Text.WordWrap
        font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
    }

    Text {
        Layout.fillWidth: true
        visible: page.sys.hyprError.length > 0
        text: page.sys.hyprError
        color: page.sys.colCrit
        wrapMode: Text.WordWrap
        font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 26

        Repeater {
            model: ["Panacea", "More"]

            ColumnLayout {
                id: col
                required property string modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1     // делим поровну, а не по содержимому
                Layout.alignment: Qt.AlignTop
                spacing: 9

                Head { text: col.modelData === "Panacea" ? "Panacea pages" : "More" }

                Repeater {
                    model: (page.binds.actions || []).filter(a => a.group === col.modelData)
                    BindRow {
                        required property var modelData
                        bindId: modelData.id
                        label: modelData.label
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- кнопки
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 12

        SetButton {
            sys: page.sys
            text: "All shortcuts"
            onClicked: { page.sys.keysWindowOpen = false; page.sys.runDetached("omarchy-menu-keybindings"); }
        }

        Item { Layout.fillWidth: true }

        SetButton {
            sys: page.sys
            text: page.sys.tr("Сбросить")
            onClicked: page.resetBinds()
        }

        SetButton {
            sys: page.sys
            text: page.applying ? "Saving…" : page.sys.tr("Применить")
            primary: true
            enabled: page.dirty && !page.applying
            onClicked: page.applyBinds()
        }
    }
}
