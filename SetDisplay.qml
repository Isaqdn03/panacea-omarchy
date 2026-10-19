import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Display. Схемы расположения экранов здесь нет намеренно: её двигают мышью
// на самом рабочем столе, а сюда приходят за цифрами — разрешением, частотой
// и масштабом. Настройки применяются к одному экрану сразу, без общей кнопки:
// иначе непонятно, что именно применится.
//
// Every change is applied live and saved into ~/.config/hypr/monitors.lua,
// on that output's own hl.monitor({...}) line (see scripts/hyprconf.py), so
// it is the same setting Omarchy and a hand edit would make.
ColumnLayout {
    id: page

    property var sys

    // [{ name, desc, w, h, rr, scale, transform, vrr, x, y, modes: [] }]
    property var mons: []
    // output -> its hl.monitor fields in monitors.lua
    property var rules: ({})
    // { enabled, temperature } from `omarchy toggle nightlight --status`
    property var night: ({ enabled: false })

    Layout.fillWidth: true
    spacing: 12

    Component.onCompleted: {
        pMons.running = true;
        pRules.running = true;
        pNight.running = true;
        page.sys.brightRefresh(false);
    }

    Process {
        id: pRules
        command: ["/usr/bin/python3", page.sys.scriptDir + "/hyprconf.py", "monitors"]
        stdout: SplitParser {
            onRead: line => { try { page.rules = JSON.parse(line); } catch (e) {} }
        }
    }

    Process {
        id: pNight
        command: ["omarchy-toggle-nightlight", "--status"]
        stdout: SplitParser {
            onRead: line => { try { page.night = JSON.parse(line); } catch (e) {} }
        }
    }
    Process {
        id: pNightToggle
        command: ["omarchy-toggle-nightlight"]
        onExited: nightRecheck.restart()
    }
    // hyprsunset eases into the new temperature; ask again once it has.
    Timer { id: nightRecheck; interval: 900; onTriggered: { pNight.running = false; pNight.running = true; } }

    // Saves finish asynchronously; the shell re-reads Hyprland when its save
    // queue drains, which is the moment to re-read the monitors too.
    Connections {
        target: page.sys
        function onHyprLiveChanged() { reload.restart(); }
    }

    // Яркость экрана. На ноутбуке это внутренняя матрица, на ПК — сам монитор
    // по DDC/CI; сводим строку из brightness.sh с карточкой по имени разъёма.
    // У встроенной матрицы разъём в списке один и совпадать ему не с чем,
    // поэтому единственную строку отдаём единственному экрану как есть.
    function brightOf(name) {
        var l = page.sys.brightList || [];
        for (var i = 0; i < l.length; i++)
            if (l[i].name === name) return l[i];
        if (l.length === 1 && page.sys.brightBackend === "backlight") return l[0];
        return null;
    }

    Process {
        id: pMons
        command: ["sh", "-c", "hyprctl -j monitors all"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // StdioCollector копит вывод между запусками, поэтому в
                    // тексте может лежать несколько ответов подряд — разбираем
                    // последний, начиная от финального «[».
                    var raw = JSON.parse(text.slice(text.lastIndexOf("[{")));
                    page.mons = raw.map(m => ({
                        name: m.name,
                        desc: m.description || "",
                        w: m.width, h: m.height,
                        rr: m.refreshRate,
                        scale: m.scale,
                        transform: m.transform,
                        vrr: !!m.vrr,
                        x: m.x, y: m.y,
                        modes: m.availableModes || []
                    }));
                } catch (e) {
                    page.mons = [];
                }
            }
        }
    }

    // Only the fields that changed are passed on; everything else keeps its
    // live value and its line in monitors.lua stays as it is.
    function apply(m, over) {
        var ch = {};
        if (over.w !== undefined || over.rr !== undefined) {
            var w = over.w !== undefined ? over.w : m.w;
            var h = over.h !== undefined ? over.h : m.h;
            var rr = over.rr !== undefined ? over.rr : m.rr;
            ch.mode = w + "x" + h + "@" + Number(rr).toFixed(2);
        }
        if (over.scale !== undefined) ch.scale = Number(over.scale).toFixed(4);
        if (over.transform !== undefined) ch.transform = String(over.transform);
        if (over.pos !== undefined) ch.position = over.pos;
        if (over.vrr !== undefined) ch.vrr = over.vrr;
        page.sys.monApply(m.name, ch);
    }

    Timer {
        id: reload
        interval: 300
        onTriggered: {
            pMons.running = false; pMons.running = true;
            pRules.running = false; pRules.running = true;
        }
    }

    // Hyprland refused a change (or the file could not be written): say so
    // instead of leaving the old value on screen without explanation.
    Text {
        Layout.fillWidth: true
        visible: page.sys.hyprError.length > 0
        text: page.sys.hyprError
        color: page.sys.colCrit
        wrapMode: Text.WordWrap
        font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
    }

    // Куда экран поставлен относительно первого. Читаем из живых координат,
    // а не запоминаем выбор: раскладку могли поменять и мимо этого окна.
    function placeOf(m) {
        var base = page.mons.length ? page.mons[0] : null;
        if (!base || base.name === m.name) return "auto";
        if (m.x >= base.x + base.w) return "auto-right";
        if (m.x + m.w <= base.x)    return "auto-left";
        if (m.y >= base.y + base.h) return "auto-down";
        if (m.y + m.h <= base.y)    return "auto-up";
        return "auto";
    }

    // разрешения и частоты вытаскиваем из списка режимов «1920x1080@144.00Hz»
    function resList(m) {
        var seen = {}, out = [];
        (m.modes || []).forEach(s => {
            var r = s.split("@")[0];
            if (!seen[r]) { seen[r] = true; out.push(r); }
        });
        if (!out.length) out.push(m.w + "x" + m.h);
        return out;
    }
    function rrList(m, res) {
        var out = [];
        (m.modes || []).forEach(s => {
            var p = s.split("@");
            if (p[0] !== res) return;
            var hz = parseFloat(p[1]);
            if (out.indexOf(hz) < 0) out.push(hz);
        });
        if (!out.length) out.push(m.rr);
        return out.sort((a, b) => b - a);
    }

    // ------------------------------------------------------------- остров
    // На каком экране показывать остров. Один экран — карточка не нужна,
    // выбора всё равно нет.
    SetCard {
        sys: page.sys
        visible: page.mons.length > 1

        SetLabel {
            sys: page.sys
            text: page.sys.tr("Динамический остров")
        }

        SetPick {
            sys: page.sys
            label: page.sys.tr("Показывать на экране")
            options: [{ id: "auto", text: page.sys.tr("За фокусом") }].concat(
                page.mons.map(m => ({
                    id: m.name,
                    text: m.name + (m.desc.length ? " · " + m.desc : "")
                })))
            value: page.sys.cfg.pillScreen
            onPicked: id => { page.sys.cfg.pillScreen = id; page.sys.saveCfg(); }
        }

        Text {
            Layout.fillWidth: true
            text: page.sys.tr("«За фокусом» — остров переезжает на тот экран, где вы сейчас работаете.")
            color: page.sys.colMuted
            wrapMode: Text.WordWrap
            font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: page.mons.length === 0
        text: page.sys.tr("Экраны не читаются: hyprctl не ответил.")
        color: page.sys.colMuted
        font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 3 }
    }

    Repeater {
        model: page.mons

        SetCard {
            id: card
            required property var modelData
            required property int index
            readonly property string res: card.modelData.w + "x" + card.modelData.h

            sys: page.sys

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: card.modelData.name
                        color: page.sys.colFg
                        font { family: page.sys.fontDisplay; pixelSize: page.sys.fontSize }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: card.modelData.desc.length > 0
                        text: card.modelData.desc
                        color: page.sys.colMuted
                        elide: Text.ElideRight
                        font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
                    }
                }

                Text {
                    text: card.res + " · " + Number(card.modelData.rr).toFixed(0) + " Hz"
                    color: page.sys.colMuted
                    font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 3 }
                }
            }

            SetPick {
                sys: page.sys
                label: page.sys.tr("Разрешение")
                options: page.resList(card.modelData)
                value: card.res
                onPicked: id => {
                    var wh = id.split("x");
                    // частота из старого режима может не поддерживаться новым
                    // разрешением — берём наибольшую доступную для него
                    var hz = page.rrList(card.modelData, id)[0];
                    page.apply(card.modelData, { w: +wh[0], h: +wh[1], rr: hz });
                }
            }

            SetPick {
                sys: page.sys
                label: page.sys.tr("Частота обновления")
                options: page.rrList(card.modelData, card.res).map(hz => ({
                    id: String(hz), text: hz.toFixed(2) + " Hz"
                }))
                value: String(page.rrList(card.modelData, card.res)
                              .find(hz => Math.abs(hz - card.modelData.rr) < 0.6)
                              || card.modelData.rr)
                onPicked: id => page.apply(card.modelData, { rr: parseFloat(id) })
            }

            // Пустой список режимов означает, что EDID монитора не прочитан:
            // видеокарта работает на обобщённом драйвере, и система знает
            // только тот режим, в котором уже сидит. Обычно это 60 Гц на
            // мониторе, который умеет больше, — и без объяснения выглядит
            // как поломка настроек, а не как отсутствующий драйвер.
            Text {
                Layout.fillWidth: true
                visible: (card.modelData.modes || []).length === 0
                text: page.sys.tr("Монитор не сообщил свои режимы — обычно это значит, "
                                  + "что не установлен драйвер видеокарты.")
                color: page.sys.colCrit
                wrapMode: Text.WordWrap
                font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
            }

            // Раскладка. Первый экран — точка отсчёта, остальные встают
            // относительно него; поэтому у самого первого выбора нет.
            SetSelect {
                sys: page.sys
                visible: page.mons.length > 1 && card.index > 0
                label: page.sys.tr("Расположение") + (page.mons.length > 1
                       ? " — " + page.sys.tr("относительно") + " " + page.mons[0].name : "")
                options: [
                    { id: "auto-right", text: page.sys.tr("Справа от") },
                    { id: "auto-left",  text: page.sys.tr("Слева от") },
                    { id: "auto-up",    text: page.sys.tr("Над") },
                    { id: "auto-down",  text: page.sys.tr("Под") }
                ]
                value: page.placeOf(card.modelData)
                onPicked: id => page.apply(card.modelData, { pos: id })
            }

            // Яркость. На ПК клавиш яркости на клавиатуре обычно нет, и до
            // сегодняшнего дня крутить её можно было только кнопками на самом
            // мониторе — поэтому ползунок стоит здесь, а не только на клавишах.
            SetSlider {
                id: brightSl
                readonly property var b: page.brightOf(card.modelData.name)
                sys: page.sys
                visible: brightSl.b !== null
                label: page.sys.tr("Яркость")
                from: 1; to: 100; step: 1
                value: brightSl.b ? brightSl.b.pct : 0
                suffix: "%"
                onMoved: v => { if (brightSl.b) page.sys.brightSet(brightSl.b.id, v); }
            }

            // Монитор на шине виден, но на запрос яркости не отвечает, либо
            // ddcutil вовсе не установлен. Молча прятать ползунок нельзя:
            // человек будет искать настройку, которой нет по причине, о
            // которой ему никто не сказал.
            Text {
                Layout.fillWidth: true
                visible: page.brightOf(card.modelData.name) === null
                         && !page.sys.batteryPresent
                text: !page.sys.ddcutilPresent
                      ? page.sys.tr("Яркостью монитора управляет ddcutil — его нет в системе. "
                                    + "Поставьте пакет ddcutil, и ползунок появится здесь.")
                      : page.sys.tr("Монитор не отвечает на запрос яркости по DDC/CI. "
                                    + "Обычно это включается в его меню пунктом DDC/CI.")
                color: page.sys.colMuted
                wrapMode: Text.WordWrap
                font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
            }

            // Цифровая интенсивность стоит сразу под яркостью: обе про то,
            // как выглядит картинка, и крутят их подряд. Шкала намеренно та
            // же, что в панели NVIDIA на Windows: 50 — как есть, 100 —
            // максимум. Настройка одна на всю картинку, а не на экран:
            // считает её компоновщик на готовом кадре, а не видеокарта на
            // выходе, — поэтому у второго монитора ползунка нет.
            SetSlider {
                sys: page.sys
                visible: card.index === 0
                label: page.sys.tr("Цифровая интенсивность")
                from: 0; to: 100; step: 5
                value: page.sys.cfg.vibrance
                suffix: "%"
                onMoved: v => page.sys.applyVibrance(v)
            }

            SetSlider {
                sys: page.sys
                label: page.sys.tr("Масштаб")
                from: 1; to: 3; step: 0.05
                decimals: 2
                value: card.modelData.scale
                suffix: "×"
                onMoved: v => page.apply(card.modelData, { scale: v })
            }

            SetSelect {
                sys: page.sys
                label: page.sys.tr("Поворот")
                options: [
                    { id: "0", text: "0°" },
                    { id: "1", text: "90°" },
                    { id: "2", text: "180°" },
                    { id: "3", text: "270°" }
                ]
                value: String(card.modelData.transform)
                onPicked: id => page.apply(card.modelData, { transform: +id })
            }

            // Per-output VRR. "Default" leaves it out of the monitor line, so
            // the global misc:vrr (gaming.lua sets it) decides.
            SetSelect {
                readonly property var rule: page.rules[card.modelData.name] || ({})
                sys: page.sys
                label: "Adaptive sync (VRR)"
                options: [
                    { id: "",  text: "Default" },
                    { id: "0", text: "Off" },
                    { id: "1", text: "On" },
                    { id: "2", text: "Fullscreen" }
                ]
                value: rule.vrr === undefined ? "" : String(+rule.vrr)
                onPicked: id => page.apply(card.modelData, { vrr: id })
            }

            Text {
                Layout.fillWidth: true
                text: page.rules[card.modelData.name]
                      ? "Saved in monitors.lua as " + JSON.stringify(page.rules[card.modelData.name])
                            .replace(/[{}"]/g, "").replace(/,/g, ", ").replace(/:/g, " = ")
                      : "Not in monitors.lua yet: the first change adds a line for it."
                color: page.sys.colMuted
                wrapMode: Text.WrapAnywhere
                font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 5 }
            }

        }
    }

    // Night light is Omarchy's (hyprsunset); this is its own toggle.
    SetCard {
        sys: page.sys

        SetToggle {
            sys: page.sys
            label: "Night light"
            readonly property bool lit: page.sys.omarchyNight
                                        ? page.sys.omarchyNight.enabled === true
                                        : page.night.enabled === true
            sub: "Warmer colours in the evening. Same switch as `omarchy toggle nightlight`."
            on: lit
            onToggled: v => {
                if (v === lit) return;
                if (page.sys.omarchyNight) page.sys.omarchyNight.setNightlight(v);
                else pNightToggle.running = true;
            }
        }
    }

    // Пересчитать список экранов: воткнули или вынули кабель — Hyprland уже
    // знает, а окно настроек ещё нет.
    SetCard {
        sys: page.sys

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: page.sys.tr("Обнаружить экраны")
                    color: page.sys.colFg
                    font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 1 }
                }
                Text {
                    Layout.fillWidth: true
                    text: page.sys.tr("Перечитать список подключённых мониторов.")
                    color: page.sys.colMuted
                    wrapMode: Text.WordWrap
                    font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 4 }
                }
            }

            Rectangle {
                Layout.preferredWidth: 118
                Layout.preferredHeight: 32
                radius: page.sys.radiusS
                color: detectMa.containsMouse
                       ? Qt.rgba(page.sys.colOn.r, page.sys.colOn.g, page.sys.colOn.b, 0.28)
                       : Qt.rgba(page.sys.colFg.r, page.sys.colFg.g, page.sys.colFg.b, 0.07)
                Behavior on color { ColorAnimation { duration: page.sys.animFade } }

                Text {
                    anchors.centerIn: parent
                    text: page.sys.tr("Обновить")
                    color: page.sys.colFg
                    font { family: page.sys.fontBody; pixelSize: page.sys.fontSize - 3 }
                }
                MouseArea {
                    id: detectMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { pMons.running = false; pMons.running = true; }
                }
            }
        }
    }
}
