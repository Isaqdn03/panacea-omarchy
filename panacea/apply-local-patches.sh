#!/usr/bin/env bash
# Локальные правки Panacea: страница GitHub, сегменты на пилюле и настольные
# карточки. Panacea обновляется копированием каталога поверх (update.sh несёт
# из репозитория всё, кроме settings.json), поэтому после каждого обновления
# правки в shell.qml, LauncherView.qml и WidgetsView.qml исчезают. Этот скрипт
# накатывает их заново.
#
#   ./apply-local-patches.sh          — накатить
#   ./apply-local-patches.sh --check  — сказать, накачены ли, ничего не меняя
#
# Идемпотентен: каждая правка помечена маркером PANACEA-LOCAL и второй раз не
# ложится. Файлы, которые скрипт добавляет целиком (GithubView.qml, github.sh,
# usage_brief.sh), он не трогает — они не патчи, а новые файлы.
set -euo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/panacea"
MARK="PANACEA-LOCAL"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
skip() { printf '  \033[2m·\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

for f in shell.qml LauncherView.qml WidgetsView.qml Translations.qml ControlsView.qml AgentsView.qml scripts/agents.sh scripts/weather.sh scripts/wifi.sh; do
    [ -f "$CONF/$f" ] || die "нет $CONF/$f — это точно каталог Panacea?"
done

if [ "$CHECK" = "1" ]; then
    n=0
    for f in shell.qml LauncherView.qml WidgetsView.qml Translations.qml ControlsView.qml AgentsView.qml scripts/agents.sh scripts/weather.sh scripts/wifi.sh; do
        if grep -q "$MARK" "$CONF/$f"; then ok "$f — правки на месте"; n=$((n+1));
        else skip "$f — правок нет"; fi
    done
    [ "$n" -eq 9 ] && exit 0 || exit 1
fi

# Резервные копии рядом, по одной на запуск. Не .bak-с-датой: этот скрипт
# зовут после обновления, когда исходник заведомо чистый, и плодить копии
# незачем — интересна ровно одна, та, что была до правки.
for f in shell.qml LauncherView.qml WidgetsView.qml Translations.qml ControlsView.qml AgentsView.qml scripts/agents.sh scripts/weather.sh scripts/wifi.sh; do
    cp -f "$CONF/$f" "$CONF/$f.prepatch"
done

python3 - "$CONF" "$MARK" <<'PYEOF'
import sys, io

conf, MARK = sys.argv[1], sys.argv[2]

def patch(fname, edits):
    p = f"{conf}/{fname}"
    s = open(p, encoding="utf-8").read()
    if MARK in s:
        print(f"  \033[2m·\033[0m {fname} — уже пропатчен, пропускаю")
        return
    for anchor, addition, where in edits:
        if anchor not in s:
            raise SystemExit(f"якорь не найден в {fname}:\n{anchor[:120]}")
        if s.count(anchor) != 1:
            raise SystemExit(f"якорь неоднозначен в {fname} ({s.count(anchor)} совпадений):\n{anchor[:120]}")
        if where == "replace":
            s = s.replace(anchor, addition)
        else:
            s = s.replace(anchor, (anchor + addition) if where == "after" else (addition + anchor))
    open(p, "w", encoding="utf-8").write(s)
    print(f"  \033[32m✓\033[0m {fname}")


# ------------------------------------------------------------------ shell.qml
SHELL_EDITS = [
    # 1. Страница GitHub: счётчик открытий, как у агентов, и опрос цифр для пилюли.
    ('''    function openAgents() {
        root.agentsEpoch++;
        togglePage("agents");
    }
''', '''
    // ---------------------------------------------------------- PANACEA-LOCAL
    // Страница GitHub. Устроена как страница агентов: счётчик растёт на каждое
    // открытие, вид на него подписан и перечитывает цифры — без этого повторное
    // открытие показывало бы то, что приехало в прошлый раз.
    property int githubEpoch: 0
    function openGithub() {
        root.githubEpoch++;
        togglePage("github");
    }

    // Нагрузка Claude одной цифрой — для сегмента на пилюле и настольной
    // карточки. Отдельный скрипт, не agents.sh: тот опрашивает четырнадцать
    // бинарников и укладывается в секунды, а это читает один файл за
    // миллисекунды. На пилюле висит цифра, а не окно, которое открыли руками.
    //
    // -1 значит «данных нет», и это не ноль: ноль сказал бы, что ничего не
    // израсходовано. На -1 сегмент не рисуется вовсе.
    property int    usagePct: -1
    property string usageSeverity: ""
    property string usageKind: ""
    Process {
        id: pUsageBrief
        command: ["sh", root.scriptDir + "/usage_brief.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text);
                    root.usagePct = (d.percent === undefined) ? -1 : d.percent;
                    root.usageSeverity = d.severity || "";
                    root.usageKind = d.kind || "";
                } catch (e) {
                    root.usagePct = -1;
                    root.usageKind = "";
                }
            }
        }
    }
    Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: { pUsageBrief.running = false; pUsageBrief.running = true; }
    }

    // Входящие GitHub одним числом. Скрипт держит свой кэш на минуту, поэтому
    // спрашивать дёшево: пока кэш свежий, в сеть никто не идёт.
    property int ghCount: 0
    Process {
        id: pGhCount
        command: ["sh", root.scriptDir + "/github.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(text);
                    root.ghCount = (d.inbox && d.inbox.total) ? d.inbox.total : 0;
                } catch (e) {
                    root.ghCount = 0;
                }
            }
        }
    }
    Timer {
        interval: 180000; repeat: true; running: true
        onTriggered: { pGhCount.running = false; pGhCount.running = true; }
    }

    // Цвет нагрузки: важно, сколько осталось, а не как лимит называется.
    function usageColor() {
        if (root.usageSeverity === "critical" || root.usagePct >= 90) return root.colCrit;
        if (root.usagePct >= 70) return root.colWarn;
        return root.colMuted;
    }
    // -------------------------------------------------------- /PANACEA-LOCAL
''', "after"),

    # 2. Страница в переключателе видов.
    ('''                           : root.page === "agents"   ? agentsComp
''', '''                           : root.page === "github"   ? githubComp    // PANACEA-LOCAL
''', "after"),

    # 3. Сам компонент.
    ('''        Component { id: agentsComp;    AgentsView { sys: root } }
''', '''        Component { id: githubComp;    GithubView { sys: root } }   // PANACEA-LOCAL
''', "after"),

    # 4. IPC: `qs -c panacea ipc call pill github`.
    ('''        function agents(): void { root.openAgents(); }
''', '''        function github(): void { root.openGithub(); }   // PANACEA-LOCAL
''', "after"),

    # 5. Сегменты на свёрнутой пилюле (обычные темы), перед батареей.
    ('''            // Место резервируется под самый широкий вариант («100%»), иначе''',
'''            // ------------------------------------------ PANACEA-LOCAL
            // Нагрузка агента и входящие GitHub. Оба сегмента пропадают, когда
            // показывать нечего: ноль входящих — это не новость, а отсутствие
            // новостей, и место под него держать незачем. По той же причине
            // нагрузка молчит, пока агент не оставил цифр.
            Item {
                visible: root.usagePct >= 0
                implicitWidth: usageRow.implicitWidth
                implicitHeight: usageRow.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    id: usageRow
                    spacing: 3
                    Glyph {
                        glyph: String.fromCodePoint(0xF1719)   // md-robot_outline
                        color: root.usageColor()
                        fontFam: root.fontFam
                        size: root.fontSize - 3
                    }
                    Text {
                        text: root.usagePct + "%"
                        color: root.usageColor()
                        font { family: root.fontFam; pixelSize: root.fontSize - 3; bold: true }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAgents()
                }
            }

            Item {
                visible: root.ghCount > 0
                implicitWidth: ghRow.implicitWidth
                implicitHeight: ghRow.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    id: ghRow
                    spacing: 3
                    Glyph {
                        glyph: String.fromCodePoint(0xF02A4)   // md-github
                        color: root.colMuted
                        fontFam: root.fontFam
                        size: root.fontSize - 3
                    }
                    Text {
                        text: root.ghCount
                        color: root.colFg
                        font { family: root.fontFam; pixelSize: root.fontSize - 3; bold: true }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openGithub()
                }
            }
            // ----------------------------------------- /PANACEA-LOCAL

''', "before"),

    # 6. Тема Nothing: у неё свой ряд (см. themeNothing выше по файлу), цифры
    # там набраны точками, и обычный Text рядом с ними выглядел бы чужим.
    # Пропустить этот ряд нельзя — на Nothing первого просто нет.
    (r'''                // Заряда на настольной машине не существует — там этой пары
                // нет совсем, а не «ноль процентов».
                RowLayout {
                    spacing: 6
                    visible: root.batteryPresent''',
     r'''                // ------------------------------------- PANACEA-LOCAL
                // Обёртка Item, а не голый RowLayout: клик должен ловиться на
                // всей паре «значок + число», а MouseArea внутри RowLayout стал
                // бы его третьим элементом и растянул бы ряд.
                Item {
                    visible: root.ghCount > 0
                    implicitWidth: ghRowN.implicitWidth
                    implicitHeight: ghRowN.implicitHeight
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: ghRowN
                        spacing: 6
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: String.fromCodePoint(0xF02A4)   // md-github
                            color: root.colFg
                            font { family: root.fontFam; pixelSize: root.iconSize - 2 }
                        }
                        DotText {
                            Layout.alignment: Qt.AlignVCenter
                            value: String(root.ghCount)
                            size: root.dotHSmall
                            color: root.colFg
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openGithub()
                    }
                }
                // ------------------------------------ /PANACEA-LOCAL

''', "before"),

    # 7. Нагрузка — в ЛЕВОЕ плечо, чтобы капсула не разъезжалась.
    (r'''                }
            }

            // --------------------------------------------- центр: часы''',
     r'''                }

                // ------------------------------------- PANACEA-LOCAL
                // Нагрузка агента стоит СЛЕВА, рядом с погодой, а не справа
                // к остальным значкам. Обе группы резервируют ширину по
                // большей из них (arm выше по файлу), поэтому два лишних
                // элемента справа раздували не только правую половину, но и
                // пустое место слева — остров расползался, а между погодой и
                // часами зияла дыра. Один элемент туда, другой сюда — плечи
                // сравнялись, и капсула снова собралась.
                Item {
                    visible: root.usagePct >= 0
                    implicitWidth: usageRowN.implicitWidth
                    implicitHeight: usageRowN.implicitHeight
                    Layout.leftMargin: 6
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: usageRowN
                        spacing: 6
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: String.fromCodePoint(0xF1719)   // md-robot_outline
                            color: root.usageColor()
                            font { family: root.fontFam; pixelSize: root.iconSize - 2 }
                        }
                        DotText {
                            Layout.alignment: Qt.AlignVCenter
                            value: String(root.usagePct)
                            size: root.dotHSmall
                            color: root.usageColor()
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openAgents()
                    }
                }
                // ------------------------------------ /PANACEA-LOCAL
            }

            // --------------------------------------------- центр: часы''', "replace"),

    # 8. Просвет между плечами и часами.
    (r'''            readonly property real armGap: 22''',
     r'''            // PANACEA-LOCAL: было 22. Плечи теперь несут по три элемента, и
            // прежний просвет разносил группы шире, чем нужно, чтобы читались
            // отдельно.
            readonly property real armGap: 14''', "replace"),

    # 9. Плечи привязаны к часам: просветы вокруг них должны быть равны.
    (r'''                id: nLeft
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8''',
     r'''                id: nLeft
                // PANACEA-LOCAL: привязка к ЧАСАМ, а не к кромке капсулы.
                // Плечи резервируют ширину по большей из них (arm выше), и весь
                // излишек узкого плеча собирался в один просвет у часов: справа
                // он выходил втрое шире левого. Прижав обе группы к часам
                // одинаковым зазором, мы делаем эти два просвета равными по
                // построению, а неровность уезжает на внешний край — там её
                // съедает скругление капсулы.
                anchors.right: nClock.left
                anchors.rightMargin: nothingCapsule.armGap
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8''', "replace"),

    (r'''                id: nRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12''',
     r'''                id: nRight
                // PANACEA-LOCAL: см. nLeft — та же привязка к часам.
                //
                // Из зазора вычтено 19: первым в группе стоит значок Wi-Fi, а
                // у него в Nerd Font широкий левый отступ ВНУТРИ собственной
                // клетки. Раскладка ставила обе группы на одинаковом
                // расстоянии от часов честно, но глаз меряет не клетки, а
                // краску — и справа просвет выходил вдвое шире. Компенсируем
                // отступ, чтобы совпала краска, а не рамки.
                anchors.left: nClock.right
                anchors.leftMargin: nothingCapsule.armGap - 19
                anchors.verticalCenter: parent.verticalCenter
                // 16, а не 12: правая группа несёт меньше краски, чем левая
                // (там ещё и резерв под точки столов), и по внешнему краю
                // капсулы это выходило пустотой. Просвет между значками —
                // самый дешёвый способ добрать ширину, не добавляя элементов.
                spacing: 16''', "replace"),

    # 10. Резерв под точки столов.
    (r'''            readonly property int wsSlots: 5''',
     r'''            // PANACEA-LOCAL: было 5. Резерв держит ширину под точки столов,
            // чтобы капсула не дёргалась при переключении, — но под пять слотов
            // при трёх реальных столах между точками и погодой зияла дыра шире
            // всех прочих просветов вместе взятых. Три — сколько столов заведено
            // на самом деле; появится четвёртый, капсула подрастёт на шаг.
            readonly property int wsSlots: 3''', "replace"),

    (r"""                root.weatherErr = got["err"] || "";
                if (root.weatherErr.length) return;
""",
     r"""                root.weatherErr = got["err"] || "";
                if (root.weatherErr.length) return;
                root.weatherRetries = 0;   // PANACEA-LOCAL: получилось — счётчик обнуляем
""", "replace"),
    (r"""        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshWeather()
    }
""",
     r"""        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshWeather()
    }

    // PANACEA-LOCAL: первая попытка приходится ровно на тот момент, когда сети
    // ещё нет — остров стартует раньше, чем интерфейс получает адрес. По
    // журналу загрузки: `qs -c panacea` в 13:41:37.2, адрес и DNS в 13:41:38.5,
    // то есть запрос уходит за секунду до того, как ему есть куда уходить.
    // Другого расписания у погоды нет, поэтому один промах стоил пятнадцати
    // минут пустого виджета, и «Обновить» приходилось жать руками.
    //
    // Повторяем только по сетевой ошибке и не бесконечно: двадцать попыток
    // раз в пятнадцать секунд — это пять минут, с запасом на самую медленную
    // загрузку. При настоящей поломке незачем долбить чужой сервис.
    property int weatherRetries: 0
    Timer {
        interval: 15000
        repeat: true
        running: (root.cfg.featWidgets || root.cfg.weatherOnIsland)
                 && root.weatherRetries < 20
                 && (root.weatherErr === "network" || root.weatherErr === "bad-answer")
        onTriggered: {
            root.weatherRetries++;
            root.refreshWeather();
        }
    }
""", "replace"),

    # 8. Настольные карточки уезжают под верхнюю кромку окон.
    (r"""PanelWindow {
    id: widgetsWin

    visible: root.cfg.featWidgets
    screen: root.screen
    anchors { top: true; left: true }
    implicitWidth:  widgets.implicitWidth + 56
    implicitHeight: widgets.implicitHeight + 56""",
     r"""PanelWindow {
    id: widgetsWin

    // PANACEA-LOCAL: отступ сверху. Было 28 — запас под вогнутый уголок
    // острова. Но слой Bottom, а плиточное окно начинается ниже: под ним
    // зона острова (pillH) и зазор Hyprland. При 28 карточка вылезала
    // над верхней кромкой окна узкой полоской. Считаем от той же зоны, чтобы
    // правка пережила смену pillH и перенос пилюли на другую кромку.
    readonly property real topPad: (root.pillAtTop ? root.pillH : 0) + 8

    visible: root.cfg.featWidgets
    screen: root.screen
    anchors { top: true; left: true }
    implicitWidth:  widgets.implicitWidth + 56
    // высота считается от того же отступа, иначе слой обрежет карточки снизу
    implicitHeight: widgetsWin.topPad + widgets.implicitHeight + 28""", "replace"),

    (r"""        anchors.leftMargin: 28
        // ниже острова: тот стоит по центру верхней кромки и до левого
        // угла не достаёт, но запас нужен под его вогнутый уголок
        anchors.topMargin: 28""",
     r"""        anchors.leftMargin: 28
        anchors.topMargin: widgetsWin.topPad   // PANACEA-LOCAL, см. topPad""", "replace"),

    # 9. Группировка острова разделителями (2026-09-03).
    (r"""                                 ? capsule.evenUp(Math.max(nothingCapsule.implicitWidth + 28,
""",
     r"""                                 // PANACEA-LOCAL: 36, а не 28. nothingCapsule
                                 // отступает от кромок острова по 18 с каждой
                                 // стороны, то есть просит 36, — а остров
                                 // закладывал 28. Содержимое вылезало в
                                 // собственные поля на 4 пикселя с каждой
                                 // стороны, и справа заряд почти упирался в
                                 // скругление.
                                 ? capsule.evenUp(Math.max(nothingCapsule.implicitWidth + 36,
""", "replace"),

    # 10. Группировка острова разделителями (2026-09-03).
    (r"""            // Место под точки столов: пять слотов по шесть пикселей, просветы
            // между ними и надбавка на текущий стол — он растекается в полосу
            // и шире остальных.
            // PANACEA-LOCAL: было 5. Резерв держит ширину под точки столов,
            // чтобы капсула не дёргалась при переключении, — но под пять слотов
            // при трёх реальных столах между точками и погодой зияла дыра шире
            // всех прочих просветов вместе взятых. Три — сколько столов заведено
            // на самом деле; появится четвёртый, капсула подрастёт на шаг.
            readonly property int wsSlots: 3
            readonly property real wsReserve:
                nothingCapsule.wsSlots * 6
                + (nothingCapsule.wsSlots - 1) * nLeft.spacing
                + (17 - 6)
""",
     r"""            // ------------------------------------- PANACEA-LOCAL
            // Разделители между группами. Остров нёс девять значений подряд
            // одной ровной строкой: пять чисел одного кегля, одного цвета и
            // с одинаковыми просветами. Глаз в такой строке не находит, где
            // кончается одно и начинается другое, и перечитывает её целиком
            // каждый раз. Волосяная линия ставит границу дешевле, чем лишний
            // просвет: она видна, но краски в ней почти нет.
            //
            // Цвет берётся от colFg, а не белым напрямую: на других темах
            // передний план не белый, и жёстко вписанный белый там выпадет.
            readonly property real  ruleW: 1
            readonly property real  ruleH: root.pillH - 10
            readonly property color ruleCol: Qt.rgba(root.colFg.r, root.colFg.g,
                                                     root.colFg.b, 0.12)

            // Просвет между точками столов. Свой, а не общий по строке:
            // точки — это одна вещь, а не три, и разъезжаться вместе с
            // просветом между группами им не за чем.
            readonly property real wsGap: 8

            // Часы без AM/PM. В 12-часовом формате timeText приходит как
            // «11:54 AM», а DotText букв не знает: он их НЕ РИСУЕТ, но место
            // под них оставляет — три знака и три просвета, около 22 пикселей
            // пустоты справа внутри самих часов.
            //
            // Отсюда росла вся правая несимметрия, и прежний вычет 19 из якоря
            // правой группы гасил именно её. В комментарии он был записан как
            // компенсация левого отступа глифа Wi-Fi — это неверно: у глифа
            // отступа почти нет (измерено — 11 против 12 ожидаемых), а лишние
            // пиксели всё это время были хвостом часов.
            //
            // Лечим причину: в остров идут только цифры. Видно ровно то же,
            // что и раньше — AM/PM там никогда не рисовалось, — но ширина
            // теперь равна краске, и оба плеча встают от часов честно.
            readonly property string clockDigits:
                root.timeText.replace(/\s*[AP]M\s*$/i, "")

            // Пустая группа не должна оставлять после себя висящую линию:
            // на настольной машине нет заряда, а погода приезжает не сразу.
            readonly property bool hasAmbient:
                (root.weatherReady && root.cfg.weatherOnIsland) || root.usagePct >= 0
            readonly property bool hasStatus:
                root.ghCount > 0 || root.batteryPresent
            // ------------------------------------ /PANACEA-LOCAL

            // PANACEA-LOCAL: резерв под точки столов убран совсем.
            //
            // Он держал ширину под фиксированное число столов, чтобы остров не
            // дёргался, когда стол заводят или закрывают. Плата — пустое место
            // внутри острова ровно на разницу: при трёх зарезервированных
            // слотах и двух реальных столах между точками и разделителем
            // зияло 26 пикселей против 12 во всех прочих просветах. Это и была
            // самая заметная дыра в пилюле.
            //
            // Защищал он при этом от малого: остров и так меняет ширину
            // постоянно — час с «9:59» на «10:00» прибавляет цифру, градусы и
            // проценты тоже гуляют в ширине. Переключение стола ширину не
            // трогает (одна точка растекается, другая сжимается на столько
            // же); меняет её только появление или закрытие стола, а это
            // событие редкое и заметное по делу.
""", "replace"),

    # 11. Группировка острова разделителями (2026-09-03).
    (r"""                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

""",
     r"""                anchors.verticalCenter: parent.verticalCenter
                // PANACEA-LOCAL: плечо занимает ровно arm, а не свою ширину.
                //
                // arm — ширина БОЛЬШЕГО из плеч, и её резервируют оба, иначе
                // часы стояли бы по центру пустоты. Разницу узкое плечо
                // раньше отдавало целиком наружу: точки столов прижимались к
                // разделителю, а слева копилось поле вдвое шире правого.
                // Теперь излишек забирает ячейка столов (Layout.fillWidth
                // ниже) и точки встают по её центру — поля по краям острова
                // выходят равными, а просветы у часов не трогаются.
                //
                // implicitWidth от явной ширины не зависит, поэтому arm через
                // неё не считается заново и цикла в привязке нет.
                width: nothingCapsule.arm
                // PANACEA-LOCAL: было 8. Просветы внутри пары «значок и его
                // число» остались прежними (5-6), а этот — между соседними
                // показаниями. Границу между группами держит линия, поэтому
                // разносить их шире не нужно: 12 хватает и слева, и справа.
                spacing: 12

""", "replace"),

    # 12. Группировка острова разделителями (2026-09-03).
    (r"""                    Layout.preferredWidth: Math.max(wsRow.implicitWidth,
                                                    nothingCapsule.wsReserve)
""",
     r"""                    // PANACEA-LOCAL: ячейка столов забирает весь излишек
                    // узкого плеча, а точки стоят по её центру. Минимум — по
                    // содержимому, чтобы ячейка не сжалась уже точек.
                    Layout.fillWidth: true
                    Layout.minimumWidth: wsRow.implicitWidth
                    Layout.preferredWidth: wsRow.implicitWidth
""", "replace"),

    # 13. Группировка острова разделителями (2026-09-03).
    (r"""                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: nLeft.spacing
""",
     r"""                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        // PANACEA-LOCAL: свой просвет, см. wsGap.
                        spacing: nothingCapsule.wsGap
""", "replace"),

    # 14. Группировка острова разделителями (2026-09-03).
    (r"""
                // Погода сразу за точками. Значок и градусы, без города и
""",
     r"""
                // PANACEA-LOCAL: столы | окружение
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: nothingCapsule.ruleW
                    Layout.preferredHeight: nothingCapsule.ruleH
                    color: nothingCapsule.ruleCol
                    visible: nothingCapsule.hasAmbient
                }

                // Погода сразу за точками. Значок и градусы, без города и
""", "replace"),

    # 15. Группировка острова разделителями (2026-09-03).
    (r"""                RowLayout {
                    Layout.leftMargin: 6
                    spacing: 5
""",
     r"""                RowLayout {
                    // PANACEA-LOCAL: leftMargin убран — просвет теперь общий
                    // по строке (spacing 12), добавка сверху его удваивала.
                    spacing: 5
""", "replace"),

    # 16. Группировка острова разделителями (2026-09-03).
    (r"""                    implicitHeight: usageRowN.implicitHeight
                    Layout.leftMargin: 6
                    Layout.alignment: Qt.AlignVCenter
""",
     r"""                    implicitHeight: usageRowN.implicitHeight
                    // PANACEA-LOCAL: у глифа робота левый отступ внутри клетки
                    // шире правого, и просвет после градусов выходил 18 против
                    // 12 у соседей. Считаем по краске: вычитаем разницу.
                    //
                    // Отрицательный отступ безопасен ЗДЕСЬ, потому что слева
                    // стоит погода, а не разделитель: соседний элемент такой
                    // отступ схлопывает, и линию он бы просто стёр.
                    Layout.leftMargin: -6
                    Layout.alignment: Qt.AlignVCenter
""", "replace"),

    # 17. Группировка острова разделителями (2026-09-03).
    (r"""                    }
                }
                // ------------------------------------ /PANACEA-LOCAL
            }
""",
     r"""                    }
                }

                // Окружение | часы. Эта линия и её пара справа стоят вплотную
                // к часам с обеих сторон на одном и том же armGap, и обе —
                // фигуры шириной ровно в пиксель без собственных отступов.
                // Поэтому просветы у часов равны по построению, а не по
                // подобранному числу.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: nothingCapsule.ruleW
                    Layout.preferredHeight: nothingCapsule.ruleH
                    color: nothingCapsule.ruleCol
                }
                // ------------------------------------ /PANACEA-LOCAL
            }
""", "replace"),

    # 18. Группировка острова разделителями (2026-09-03).
    (r"""                value: root.timeText
""",
     r"""                // PANACEA-LOCAL: только цифры, см. clockDigits.
                value: nothingCapsule.clockDigits
""", "replace"),

    # 19. Группировка острова разделителями (2026-09-03).
    (r"""                // Из зазора вычтено 19: первым в группе стоит значок Wi-Fi, а
                // у него в Nerd Font широкий левый отступ ВНУТРИ собственной
                // клетки. Раскладка ставила обе группы на одинаковом
                // расстоянии от часов честно, но глаз меряет не клетки, а
                // краску — и справа просвет выходил вдвое шире. Компенсируем
                // отступ, чтобы совпала краска, а не рамки.
                anchors.left: nClock.right
                anchors.leftMargin: nothingCapsule.armGap - 19
                anchors.verticalCenter: parent.verticalCenter
                // 16, а не 12: правая группа несёт меньше краски, чем левая
                // (там ещё и резерв под точки столов), и по внешнему краю
                // капсулы это выходило пустотой. Просвет между значками —
                // самый дешёвый способ добрать ширину, не добавляя элементов.
                spacing: 16
""",
     r"""                // Зазор честно равен armGap, без вычетов. Прежние «-19»
                // компенсировали не глиф Wi-Fi, а невидимый хвост « AM»
                // внутри часов — он убран в clockDigits, и подпорка вместе с
                // ним. Первыми в обеих группах теперь стоят одинаковые линии
                // шириной в пиксель, так что просветы у часов равны по
                // построению.
                //
                // Отрицательный Layout.leftMargin здесь не применять: соседний
                // элемент с ним схлопывает линию — она перестаёт рисоваться
                // совсем (проверено, пропадала именно эта, у часов).
                anchors.left: nClock.right
                anchors.leftMargin: nothingCapsule.armGap
                anchors.verticalCenter: parent.verticalCenter
                // PANACEA-LOCAL: см. nLeft. Здесь fillWidth ни на чём не
                // стоит — центрировать в правом плече нечего, — поэтому
                // излишек, если правое станет узким, ляжет за последним
                // элементом, к внешней кромке.
                width: nothingCapsule.arm
                // PANACEA-LOCAL: было 16 — просветом добирали ширину, чтобы
                // группы читались раздельно. Теперь их разводят линии, и
                // просвет тот же, что слева.
                spacing: 12

                // Часы | живое
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: nothingCapsule.ruleW
                    Layout.preferredHeight: nothingCapsule.ruleH
                    color: nothingCapsule.ruleCol
                }
""", "replace"),

    # 20. Группировка острова разделителями (2026-09-03).
    (r"""                // Раскладка сразу за сетью. Буквами, а не точками: точечная
                // сетка знает цифры, а «RU» на ней пришлось бы рисовать
                // отдельно ради двух знаков.
                //
                // Текущая — в полную яркость, вторая приглушена: цветом их
                // на этой теме не развести, а разница нужна беглая.
                //
                // FlipText, а не обычная надпись: раскладку переключают
                // вслепую, посреди набора, и подтверждение нужно заметить
                // краем глаза. Подмена буквы без движения незаметна — здесь
                // она перелистывается, как и в обычном острове.
                FlipText {
                    Layout.alignment: Qt.AlignVCenter
                    value: root.kbLayout
                    textColor: root.kbLayout === "RU" ? root.colFg : root.colMuted
                    fontFam: root.fontFam
                    pixelSize: root.fontSize - 4
                    bold: true
                }
""",
     r"""                // PANACEA-LOCAL: раскладка с острова убрана. Заведена одна,
                // US, — надпись не менялась никогда и занимала место наравне
                // с показаниями, которые меняются. Сам FlipText остаётся в
                // файле и по-прежнему используется обычным островом; заведут
                // вторую раскладку — вернуть сюда четыре строки.
""", "replace"),

    # 21. Группировка острова разделителями (2026-09-03).
    (r"""                // ------------------------------------- PANACEA-LOCAL
                // Обёртка Item, а не голый RowLayout: клик должен ловиться на
""",
     r"""                // ------------------------------------- PANACEA-LOCAL
                // Живое | состояние. Слева от линии то, что меняется, пока
                // смотришь: сеть и звук. Справа — то, на что оглядываешься:
                // непрочитанное на гитхабе и заряд.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: nothingCapsule.ruleW
                    Layout.preferredHeight: nothingCapsule.ruleH
                    color: nothingCapsule.ruleCol
                    visible: nothingCapsule.hasStatus
                }

                // Обёртка Item, а не голый RowLayout: клик должен ловиться на
""", "replace"),

    # 22. Полоса под остров равна его высоте — зазор до окон отдан Hyprland.
    (r"""    // зазор между пилюлей и окнами (0 в режиме оверлея или при скрытии)
    exclusiveZone: (root.cfg.pillOverlay || root.pillHidden || (root.fullscreenActive && !root.expanded))
                   ? 0 : pillH + gap""",
     r"""    // ---------------------------------------------------------- PANACEA-LOCAL
    // Полоса под остров — ровно его высота. Своего зазора до окон здесь нет:
    // его задаёт Hyprland (general:gaps_out). Пока мы прибавляли ещё и gap,
    // они складывались, и сверху выходило 11 px против 6 по остальным
    // кромкам. 0 — в режиме оверлея и когда остров скрыт.
    exclusiveZone: (root.cfg.pillOverlay || root.pillHidden || (root.fullscreenActive && !root.expanded))
                   ? 0 : pillH""", "replace"),

    # 23. Стеклянный режим: состояние для тумблера в панели. Само переключение
    # живёт в scripts/glass.sh — файл наш, обновлением не затирается.
    (r"""    Process {
        running: root.keepAwake
        command: ["systemd-inhibit", "--what=idle:sleep:handle-lid-switch",
                  "--who=Panacea", "--why=Keep awake", "sleep", "infinity"]
    }
""",
     r"""
    // ---------------------------------------------------------- PANACEA-LOCAL
    // ------------------------------------------------------------ стекло
    // Размытие Hyprland и прозрачный фон терминала одним тумблером. Всё делает
    // scripts/glass.sh — он же знает, где лежит состояние, и он же перечитывает
    // оба конфига. Здесь только то, что показать в панели.
    //
    // true как стартовое значение — не догадка: отсутствие файла-флага и
    // означает включённое стекло, а на машине, где тумблером не пользовались,
    // файла нет. Ошибиться можно ровно на те миллисекунды, пока не ответил
    // pGlassRead ниже.
    property bool glassOn: true
    Process {
        id: pGlassRead
        command: ["sh", root.scriptDir + "/glass.sh", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.glassOn = (text.trim() !== "off")
        }
    }
    function refreshGlass() {
        pGlassRead.running = false;
        pGlassRead.running = true;
    }
    Process {
        id: pGlassSet
        command: ["sh", root.scriptDir + "/glass.sh", "toggle"]
        onExited: root.refreshGlass()
    }
    function toggleGlass() {
        // Тумблер переставляем сразу, не дожидаясь скрипта: тот перезагружает
        // конфиг Hyprland и рассылает сигнал терминалам — это доли секунды, но
        // всё это время кнопка выглядела бы ненажатой. Что вышло на самом деле,
        // придёт следом из refreshGlass и поправит, если не вышло ничего.
        root.glassOn = !root.glassOn;
        pGlassSet.running = false;
        pGlassSet.running = true;
    }
    // -------------------------------------------------------- /PANACEA-LOCAL
""", "after"),

    # 24. Стекло переключают и клавишами — панель должна это заметить.
    (r"""            if (n === "configreloaded") monReplayTimer.restart();""",
     r"""            if (n === "configreloaded") {
                monReplayTimer.restart();
                // PANACEA-LOCAL: стекло переключают и клавишами, мимо панели.
                // Свой тумблер тоже перезагружает конфиг, так что сюда мы
                // попадаем в любом случае — перечитать состояние здесь дешевле,
                // чем опрашивать скрипт по таймеру круглые сутки.
                root.refreshGlass();
            }""", "replace"),

    # 25. Пилюля должна вставать на заданный экран при старте. settings.json
    #     читается асинхронно, поэтому первое вычисление pickScreen идёт со
    #     значением "auto" по умолчанию, слой создаётся на экране Quickshell по
    #     умолчанию, а последующая смена теряется — после каждого входа пилюля
    #     оказывалась не на том мониторе. Повторное присвоение ПОСЛЕ старта
    #     срабатывает, отсюда таймер. При фиксированном pillScreen он отработает
    #     ровно один раз: полоса exclusiveZone не ездит, окна не прыгают.
    (r"""    readonly property var pickScreen: {
        var want = root.cfg.pillScreen;
        if (want && want !== "auto") {
            var all = Quickshell.screens;
            for (var i = 0; i < all.length; i++)
                if (all[i].name === want) return all[i];
        }
        var fm = Hyprland.focusedMonitor;
        return (fm && fm.screen) ? fm.screen : null;
    }""",
     r"""    // ---------------------------------------------------------- PANACEA-LOCAL
    // Startup pin. settings.json is read asynchronously, so the FIRST
    // evaluation of this runs while pillScreen is still the "auto" default and
    // the layer gets created on Quickshell's default output. The later change
    // to the configured screen arrives while the layer is still being set up
    // and is silently dropped, so the pill sat on the wrong monitor after
    // every login. Changing it once more AFTER startup does take effect.
    //
    // Hence the timer: the value is computed as a pure binding, then applied
    // one event-loop beat later. With a fixed pillScreen this fires once at
    // startup and never again, so the exclusiveZone strip stays put and
    // windows never resize.
    //
    // Deferring also avoids a crash: assigning `screen:` straight from the
    // binding let Quickshell call QWindow::setScreen() inside the Hyprland
    // socket-notifier callback, which segfaults
    // (#1 QWindow::setScreen ... #16 QSocketNotifier::event).
    readonly property var wantScreen: {
        var all = Quickshell.screens;
        var want = root.cfg.pillScreen;
        if (want && want !== "auto") {
            for (var i = 0; i < all.length; i++)
                if (all[i].name === want) return all[i];
        }
        var fm = Hyprland.focusedMonitor;
        if (fm && fm.screen) return fm.screen;
        if (fm && fm.name) {
            for (var j = 0; j < all.length; j++)
                if (all[j].name === fm.name) return all[j];
        }
        return null;
    }

    property var pickScreen: null
    onWantScreenChanged: pillScreenPin.restart()
    Timer {
        id: pillScreenPin
        interval: 400
        running: true
        onTriggered: {
            if (!root.wantScreen) return;
            if (root.pickScreen !== root.wantScreen)
                root.pickScreen = root.wantScreen;
            root.surfaceEpoch++;
        }
    }

    // Monitor hotplug. When an output goes away (monitor switched off),
    // Hyprland sends `closed` to every layer surface on it and Quickshell
    // hides the window: `visible` drops to false from C++, which leaves the
    // QML binding in place but stale. Moving the window to a screen later
    // does not show it again (ProxyWindowBase::setScreen only re-shows a
    // window that was visible), so the pill stayed gone after the monitor
    // came back. Every `visible:` of a layer on root.screen therefore reads
    // surfaceEpoch; bumping it after each screen pick re-evaluates those
    // bindings and re-shows whatever was closed. Otherwise it is a no-op.
    property int surfaceEpoch: 0""", "replace"),

    # 26. Значки на свёрнутом острове нажимаются мышью: наведение не
    #     раскрывает остров, пока курсор в столбце нажимаемого значка,
    #     и раскрывает с задержкой 120 мс вместо мгновенной.
    #     Подробно — в самой правке, над capsule.overSegment().
    (r'''        function openPanel() {
''',
     r'''        // PANACEA-LOCAL. Наведение раскрывает остров мгновенно, и всё, что
        // на свёрнутом острове нажимается — точки столов, погода, нагрузка
        // агента, GitHub, — мышью было не достать: пока курсор доезжал до
        // значка, остров уже становился панелью, и значка под ним не было.
        // Поэтому над нажимаемым значком наведение остров не раскрывает, а
        // сошёл курсор со значка на пустое место — раскрывает, как раньше.
        //
        // Значок узнаём не по списку, а по признаку: видимая MouseArea с
        // hoverEnabled. Так новые значки получают это сами. Сама капсула под
        // признак не попадает: её MouseArea (клик разворачивает) наведение
        // не слушает.
        //
        // Сверяем только X — весь столбец над значком и под ним. Значок ниже
        // острова, и снизу курсор сперва пересекает голую полосу под ним:
        // проверка «курсор на самой MouseArea» раскрывала остров ровно там,
        // за пару пикселей до цели.
        //
        // Прозрачное пропускаем: столбик для боковых кромок (vertCapsule) у
        // верхней кромки не скрыт, а лишь прозрачен, и его MouseArea плеера
        // лежит поперёк часов — без этой проверки часы считались значком.
        property bool segBlocked: false
        function overSegment() {
            var sp = capsuleHover.point.scenePosition;
            function walk(it) {
                var kids = it.children;
                for (var i = 0; i < kids.length; i++) {
                    var c = kids[i];
                    if (!c.visible || c.opacity < 0.01) continue;
                    if (c.hoverEnabled === true && c.enabled) {
                        var q = c.mapFromItem(null, sp.x, sp.y);
                        if (q.x >= 0 && q.x <= c.width) return true;
                    }
                    if (walk(c)) return true;
                }
                return false;
            }
            return walk(capsule);
        }

        function openPanel() {
''', "replace"),
    (r'''            onPointChanged: {
                if (root.hoverExpandArmed || !capsuleHover.hovered) return;
''',
     r'''            onPointChanged: {
                // PANACEA-LOCAL: курсор сошёл с нажимаемого значка на пустое
                // место острова — раскрытие, которое значок придержал (см.
                // capsule.overSegment), догоняет сейчас. Только придержанное:
                // свёрнутый Esc остров под курсором сам не раскрывается.
                if (capsule.segBlocked && capsuleHover.hovered && !root.expanded
                    && !capsule.overSegment()) {
                    capsule.segBlocked = false;
                    expandTimer.restart();
                    return;
                }
                if (root.hoverExpandArmed || !capsuleHover.hovered) return;
''', "replace"),
    (r'''                } else {
                    expandTimer.stop();
                    collapseTimer.restart();
''',
     r'''                } else {
                    expandTimer.stop();
                    collapseTimer.restart();
                    capsule.segBlocked = false;   // PANACEA-LOCAL, см. overSegment
''', "replace"),
    (r'''                if (root.cfg.pillAutoHide) return;
                capsule.openPanel();
''',
     r'''                if (root.cfg.pillAutoHide) return;
                // PANACEA-LOCAL: курсор на нажимаемом значке — не раскрываем,
                // иначе значок исчезнет из-под мыши раньше клика.
                if (capsule.overSegment()) { capsule.segBlocked = true; return; }
                capsule.openPanel();
''', "replace"),
    (r'''            id: expandTimer; interval: 0
''',
     r'''            // PANACEA-LOCAL: было 0. Между значками есть просветы, и курсор,
            // идущий к значку наискосок, на миг задевает голую капсулу —
            // мгновенное раскрытие убирало значок из-под мыши. 120 мс на
            // глаз не заметны, а наискосок просвет проходят быстрее.
            id: expandTimer; interval: 120
''', "replace"),

    # 27. Пилюля не возвращалась после выключения монитора: Hyprland
    #     закрывает слои на пропавшем выходе, Quickshell прячет окно, и
    #     ничто не показывало его снова. Привязки visible читают
    #     root.surfaceEpoch (заведён в правке 25), таймер выбора экрана его
    #     увеличивает — привязки пересчитываются и показывают закрытое.
    ('''    visible: !root.fullscreenActive || root.expanded || root.osdActive
''',
     '''    // PANACEA-LOCAL: surfaceEpoch is always >= 0; reading it lets a monitor
    // hotplug re-show the pill (see root.surfaceEpoch).
    visible: (!root.fullscreenActive || root.expanded || root.osdActive) && root.surfaceEpoch >= 0
''', "replace"),
    ('''    visible: root.cfg.featWidgets
''',
     '''    visible: root.cfg.featWidgets && root.surfaceEpoch >= 0   // PANACEA-LOCAL, see root.surfaceEpoch
''', "replace"),

    # 28. No self-update (2026-10-15). update.sh apply runs upstream install.sh,
    #     which replaces ~/.config/{hypr,fish,foot,fastfetch,nano} wholesale and
    #     wipes these patches. The button only shows when check says "behind",
    #     but if it ever appears, clicking it now just explains why it is off.
    ('''    function applyUpdate() {
        if (root.updBusy) return;
''', '''        // PANACEA-LOCAL: never self-update on Omarchy. update.sh runs upstream's
        // install.sh, which replaces ~/.config/{hypr,fish,foot,fastfetch,nano}
        // (Omarchy's hyprland.lua, autostart.lua, monitors.lua) and drops every
        // local patch. Update by hand: fetch upstream, re-run
        // apply-local-patches.sh, test, then ~/dev/panacea-omarchy/sync.sh.
        root.updError = "local";
        return;
''', "after"),
    ('''        case "install":  return root.tr("Установщик завершился с ошибкой");
''', '''        // PANACEA-LOCAL: see applyUpdate()
        case "local":    return "Self-update is off here: it would overwrite Omarchy's Hyprland config and the local patches. Update by hand.";
''', "after"),

    # 29. The layout label (US/RU) hides when only one layout is configured:
    #     it could never change, and it cost the island ~30 px (2026-10-15).
    ('''    // Hyprland шлёт activelayout при каждом переключении Alt+Shift
''', '''    // PANACEA-LOCAL: with a single keyboard layout the label can never change,
    // so the island hides it. Starts true so a failed probe never hides it.
    property bool kbMulti: true
    Process {
        id: pKbCount
        command: ["sh", "-c",
            "hyprctl devices -j | jq -r 'first(.keyboards[]|select(.main==true)|.layout)'"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                var s = line.trim();
                if (s.length) root.kbMulti = s.indexOf(",") >= 0;
            }
        }
    }
''', "before"),
    ('''            if (ev.name === "activelayout") pKbLayout.running = true;
''', '''            if (ev.name === "configreloaded") pKbCount.running = true;   // PANACEA-LOCAL
''', "after"),
    ('''            // текущая раскладка: перелистывается при Alt+Shift
            FlipText {
                value: root.kbLayout
''', '''                visible: root.kbMulti   // PANACEA-LOCAL
''', "after"),
    ('''                    text: root.kbLayout
''', '''                    visible: root.kbMulti   // PANACEA-LOCAL
''', "after"),
]

# ------------------------------------------------------------ LauncherView.qml
LAUNCHER_EDITS = [
    ('''        keys: "agents agent ai claude codex gemini copilot cursor limits usage plan "
              + "агенты агент лимиты тариф подписка нагрузка"
    }]''', '''        keys: "agents agent ai claude codex gemini copilot cursor limits usage plan "
              + "агенты агент лимиты тариф подписка нагрузка"
    },
        // PANACEA-LOCAL: страница GitHub тем же способом, что и агенты — своей
        // строкой в общем списке. Ключи английские и русские, плюс те слова,
        // которыми эту страницу зовут в голове: pr, ci, ревью.
        {
        builtin: "github",
        id: "panacea:github",
        glyph: String.fromCodePoint(0xF02A4),      // md-github
        name: "GitHub",
        genericName: view.sys.tr("Входящие, текущий репозиторий и прогоны CI"),
        keys: "github gh pr pull request review ci actions runs notifications repo "
              + "гитхаб пиар ревью прогоны уведомления репозиторий"
    }]''', "replace_tail"),

    ('''        if (app.builtin === "agents") { rememberApp(app); sys.openAgents(); return; }
''', '''        if (app.builtin === "github") { rememberApp(app); sys.openGithub(); return; }   // PANACEA-LOCAL
''', "after"),
]

# Первая правка лаунчера меняет хвост массива, поэтому не «до/после», а замена.
def patch_launcher():
    p = f"{conf}/LauncherView.qml"
    s = open(p, encoding="utf-8").read()
    if MARK in s:
        print(f"  \033[2m·\033[0m LauncherView.qml — уже пропатчен, пропускаю")
        return
    for anchor, addition, where in LAUNCHER_EDITS:
        if s.count(anchor) != 1:
            raise SystemExit(f"якорь не найден или неоднозначен в LauncherView.qml:\n{anchor[:120]}")
        if where == "replace_tail":
            s = s.replace(anchor, addition)
        else:
            s = s.replace(anchor, anchor + addition)
    open(p, "w", encoding="utf-8").write(s)
    print(f"  \033[32m✓\033[0m LauncherView.qml")

# ------------------------------------------------------------- WidgetsView.qml
WIDGETS_EDITS = [
    ('''        // ------------------------------------------------------ часы
        Card {
            Layout.preferredWidth: view.fullW
            Layout.preferredHeight: 62

            Num {
                anchors.centerIn: parent
                value: view.sys.timeText
                size: 30
                gapRatio: 0.14
                color: view.sys.colFg
            }
        }
''', '''
        // ------------------------------------------ PANACEA-LOCAL
        // Нагрузка агента и входящие GitHub. Ряд целиком пропадает, когда обеим
        // карточкам нечего показать: пустая плашка на обоях — не информация, а
        // пятно. Если данные есть только у одной, ряд не разъезжается — вторая
        // просто остаётся на своём месте слева, как карточка даты выше.
        //
        // Клик по карточке открывает свою страницу. Область ввода слоя — это
        // сами карточки (mask: Region { item: widgets } в shell.qml), поэтому
        // пустой рабочий стол остаётся свободным, а плашка мышь ловит; ровно
        // так же устроены кружки погоды выше.
        RowLayout {
            spacing: view.gap
            visible: view.sys.usagePct >= 0 || view.sys.ghCount > 0

            Card {
                visible: view.sys.usagePct >= 0
                Layout.preferredWidth: view.col
                Layout.preferredHeight: 84

                Num {
                    anchors.centerIn: parent
                    value: view.sys.usagePct + "%"
                    size: 28
                    gapRatio: 0.14
                    color: view.sys.usageColor()
                }
                Caption {
                    anchors {
                        left: parent.left; bottom: parent.bottom
                        leftMargin: 14; bottomMargin: 12
                    }
                    text: "CLAUDE"
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.sys.openAgents()
                }
            }

            Card {
                visible: view.sys.ghCount > 0
                Layout.preferredWidth: view.col
                Layout.preferredHeight: 84

                Num {
                    anchors.centerIn: parent
                    value: String(view.sys.ghCount)
                    size: 28
                    gapRatio: 0.14
                    color: view.sys.colFg
                }
                Caption {
                    anchors {
                        left: parent.left; bottom: parent.bottom
                        leftMargin: 14; bottomMargin: 12
                    }
                    text: "GITHUB"
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.sys.openGithub()
                }
            }
        }
        // ----------------------------------------- /PANACEA-LOCAL
''', "after"),
]

# ----------------------------------------------------------- Translations.qml
# Словарь переводит русский ключ в английский; строки, которых здесь нет,
# остаются русскими. Без этого блока страница GitHub говорила бы по-русски
# посреди английского интерфейса — что и случилось при первой сборке.
TRANS_EDITS = [
    ('''        "Тарифы и лимиты установленных ИИ-агентов": "Plans and limits of the AI agents you have installed",
''', '''        // PANACEA-LOCAL: страница GitHub
        "Входящие, текущий репозиторий и прогоны CI": "Inbox, current repository and CI runs",
        "Входящие": "Inbox",
        "уведомл.": "notifs",
        "ревью": "reviews",
        "на мне": "assigned",
        "Ничего не ждёт — входящие пусты": "Nothing waiting — your inbox is empty",
        "В фокусе": "In focus",
        "В окне под фокусом нет репозитория": "No repository in the focused window",
        "у ветки нет открытого PR": "no open PR for this branch",
        "Прогоны": "Runs",
        "ждут": "waiting",
        "входящие пусты": "inbox empty",
        "нагрузка неизвестна": "usage unknown",
        "gh не установлен": "gh is not installed",
        "gh не залогинен — выполните gh auth login": "gh is not logged in — run gh auth login",
        "jq не установлен": "jq is not installed",
        "Не удалось прочитать ответ GitHub": "Could not read GitHub's response",
        // ------------------------------------------------------------------
''', "after"),
]

# ----------------------------------------------------------- ControlsView.qml
# Карточка GitHub в раскрытой панели. Блоки панели перечислены в ccDefault и
# расставляются по строкам сетки через ccRow — новый блок надо и назвать, и
# нарисовать, иначе он либо не встанет в порядок, либо встанет в нулевую строку
# поверх часов.
CONTROLS_EDITS = [
    ('''    readonly property var ccDefault: ["clock", "toggles", "sliders", "media", "power", "quick", "tray"]''',
     '''    // PANACEA-LOCAL: "github" добавлен между power и quick — это содержимое,
    // а не действие, и над строкой с кофе и шестернёй ему место. "glass" —
    // следом за ними, вплотную к строке с кофе: два режима подряд.
    readonly property var ccDefault: ["clock", "toggles", "sliders", "media", "power", "github", "agents", "glass", "quick", "tray"]''', "replace"),

    ('''            // -------------------------------- не спать + кнопки-иконки''',
     '''            // ------------------------------------------ PANACEA-LOCAL
            // GitHub строкой: значок, имя и сколько ждёт. Блоком панели, а не
            // значком в нижнем ряду, — значку хватило бы места только на себя,
            // а сказать надо число.
            //
            // Показывается всегда, в том числе на нуле: в панель приходят
            // посмотреть, и «входящие пусты» — такой же ответ, как число.
            // Спрятать её значило бы заставить гадать, выключена она или
            // новостей действительно нет.
            Rectangle {
                objectName: "cc-github"
                Layout.row: view.ccRow("github")
                Layout.column: 0
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: ccGhMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                border.color: view.sys.colLine
                border.width: 1
                Behavior on color { ColorAnimation { duration: 160 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 13
                    spacing: 10

                    Glyph {
                        glyph: String.fromCodePoint(0xF02A4)   // md-github
                        color: view.sys.colFg
                        fontFam: view.sys.fontFam
                        size: view.sys.iconSize - 1
                    }
                    Text {
                        text: "GitHub"
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: view.sys.ghCount > 0
                              ? view.sys.ghCount + " " + view.sys.tr("ждут")
                              : view.sys.tr("входящие пусты")
                        color: view.sys.ghCount > 0 ? view.sys.colFg : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                    }
                }

                MouseArea {
                    id: ccGhMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.sys.openGithub()
                }
            }
            // Нагрузка агента. Тем же рядом, что и GitHub: обе строки — про
            // то, сколько чего осталось, и разводить их по разным формам
            // значило бы делать вид, что это разные вещи.
            //
            // Строка стоит и без цифр. Claude Code до 2.1.x клал нагрузку в
            // ~/.claude.json, теперь не кладёт никуда — её видит только строка
            // состояния, и та пересылает её нам (см. usage_brief.sh). Если
            // пересылки нет, честнее сказать «неизвестна», чем спрятать строку
            // и оставить думать, что лимитов не существует.
            Rectangle {
                objectName: "cc-agents"
                Layout.row: view.ccRow("agents")
                Layout.column: 0
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: ccAgMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                border.color: view.sys.colLine
                border.width: 1
                Behavior on color { ColorAnimation { duration: 160 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 13
                    spacing: 10

                    Glyph {
                        glyph: String.fromCodePoint(0xF1719)   // md-robot_outline
                        color: view.sys.usagePct >= 0 ? view.sys.usageColor() : view.sys.colFg
                        fontFam: view.sys.fontFam
                        size: view.sys.iconSize - 1
                    }
                    Text {
                        text: view.sys.tr("Агенты")
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: view.sys.usagePct < 0
                              ? view.sys.tr("нагрузка неизвестна")
                              : view.sys.usagePct + "% · "
                                + (view.sys.usageKind === "session"
                                   ? view.sys.tr("5 часов") : view.sys.tr("Неделя"))
                        color: view.sys.usagePct >= 0 ? view.sys.usageColor() : view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                    }
                }

                MouseArea {
                    id: ccAgMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.sys.openAgents()
                }
            }
            // ----------------------------------------- /PANACEA-LOCAL

            // ------------------------------------------ PANACEA-LOCAL
            // Стеклянный режим: размытие Hyprland плюс прозрачный фон
            // терминала. Своей строкой, а не значком в нижнем ряду: у режима
            // два состояния, и тумблер их показывает, а значок — нет.
            //
            // Форма ровно как у «Coffee mode» ниже, вплоть до тумблера
            // справа: обе строки переключают режим, который держится, пока
            // его не выключат, и разной формой мы делали бы вид, что это
            // разные вещи. Стоит выше — у стекла состояние видно на всём
            // экране сразу, у кофе не видно нигде.
            Rectangle {
                id: glassRow
                objectName: "cc-glass"
                Layout.row: view.ccRow("glass")
                Layout.column: 0

                // Голубой — цвет стекла на прочих темах. На Nothing цветного
                // акцента нет вовсе (см. кофе ниже, там ровно та же оговорка).
                readonly property color tint: view.sys.themeNothing
                                              ? view.sys.colOn : "#38bdf8"

                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: view.sys.glassOn
                       ? Qt.rgba(glassRow.tint.r, glassRow.tint.g, glassRow.tint.b, 0.16)
                       : (glassMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                border.color: view.sys.glassOn
                              ? Qt.rgba(glassRow.tint.r, glassRow.tint.g, glassRow.tint.b, 0.40)
                              : view.sys.colLine
                border.width: 1
                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on border.color { ColorAnimation { duration: 160 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 13
                    anchors.rightMargin: 13
                    spacing: 11

                    Glyph {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        // md-blur / md-blur_off — та же точечная россыпь,
                        // перечёркнутая в выключенном виде
                        glyph: String.fromCodePoint(view.sys.glassOn ? 0xF00B5 : 0xF00B7)
                        color: view.sys.glassOn ? glassRow.tint : view.sys.colMuted
                        fontFam: view.sys.fontFam
                        size: view.sys.iconSize + 2
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Glass mode"
                        color: view.sys.glassOn ? view.sys.colFg : view.sys.colMuted
                        font {
                            family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2
                            bold: view.sys.glassOn
                        }
                    }
                    // переключатель
                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 21
                        radius: 11
                        color: view.sys.glassOn ? glassRow.tint : Qt.rgba(1, 1, 1, 0.14)
                        Behavior on color { ColorAnimation { duration: 180 } }
                        Rectangle {
                            width: 17; height: 17; radius: 9
                            y: 2
                            x: view.sys.glassOn ? parent.width - width - 2 : 2
                            // на белой дорожке белый кружок пропадает
                            color: view.sys.glassOn
                                   ? view.sys.fgOn(glassRow.tint) : "#ffffff"
                            Behavior on x {
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }

                MouseArea {
                    id: glassMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.sys.toggleGlass()
                }
            }
            // ----------------------------------------- /PANACEA-LOCAL

            // -------------------------------- не спать + кнопки-иконки''', "replace"),

    # Прокрутка в списке сетей: без неё панель обрезает его по нижней кромке.
    (r'''            // ввод пароля для выбранной сети
            property string passwordFor: ""''',
     r'''            // ввод пароля для выбранной сети
            property string passwordFor: ""

            // PANACEA-LOCAL: Потолок высоты списка. Капсула просит у содержимого
            // implicitHeight + 30 и выше cfg.expandedH не растёт — значит виду
            // достаётся expandedH - 30. Из них вычитаем заголовок со строкой
            // отступа и, когда он открыт, поле пароля.
            readonly property int listCap: Math.max(140,
                (view.sys.cfg.expandedH || 620) - 30 - 35
                - (wifiPage.passwordFor.length > 0 ? 53 : 0))''', "replace"),
    (r'''            // список сетей
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Repeater {''',
     r'''            // список сетей
            // PANACEA-LOCAL: Прокрутка. В эфире тут три десятка точек, а панель не выше
            // cfg.expandedH — без Flickable список обрезало по нижней кромке, и
            // до половины сетей нельзя было добраться ничем: ни колесом, ни
            // клавишами. Ровно та же беда, что была у страницы агентов.
            //
            // Прокручивается только список: заголовок с кнопкой обновления и
            // поле ввода пароля должны оставаться на месте.
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(netList.implicitHeight, wifiPage.listCap)
                contentHeight: netList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 3000

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { radius: 2; color: Qt.rgba(1, 1, 1, 0.22) }
                }

            ColumnLayout {
                id: netList
                width: wifiPage.width
                spacing: 2
                Repeater {''', "replace"),
    (r'''                }
            }

            Text {
                Layout.fillWidth: true
                visible: view.sys.wifiNetworks.count === 0''',
     r'''                }
            }
            }

            Text {
                Layout.fillWidth: true
                visible: view.sys.wifiNetworks.count === 0''', "replace"),
]

# ----------------------------------------------------------- scripts/agents.sh
# Скрипт агентов обновление тоже перезаписывает, а без этих правок окно
# агентов снова зависнет на `crush --version` и снова забудет, где теперь
# лежит нагрузка Claude.
AGENTS_EDITS = [
    (r'''    local ver; ver="$("$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"''',
     r'''    # PANACEA-LOCAL: `crush --version` не возвращается никогда, а copilot думает
    # пять секунд. Один зависший бинарник вешал весь скрипт, и окно агентов не
    # открывалось вовсе. Версия — не та цифра, ради которой стоит ждать.
    local ver; ver="$(timeout 2 "$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"''', "replace"),
    (r'''    [ -n "$bin" ] && ver="$("$bin" --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"''',
     r'''    [ -n "$bin" ] && ver="$(timeout 2 "$bin" --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"''', "replace"),
    (r'''    # Почему лимитов нет — вопрос не праздный: «агент их не отдаёт» и «данных
    # ещё не приехало» выглядят одинаково, а значат противоположное.''',
     r'''    # PANACEA-LOCAL. Claude Code 2.1.x не пишет нагрузку в ~/.claude.json вовсе:
    # rate_limits он отдаёт ТОЛЬКО на stdin команде строки состояния. Поэтому
    # строка состояния складывает их в кэш (см. usage_brief.sh и
    # ~/.claude/statusline-command.sh), и если выше ничего не нашлось — берём
    # оттуда. Окно с истёкшим resets_at отбрасываем: счётчик там уже обнулился,
    # и старый процент соврал бы.
    local ucache="${XDG_CACHE_HOME:-$HOME/.cache}/panacea-claude-usage.json"
    if [ "$limits" = "[]" ] && [ -f "$ucache" ]; then
        local fresh
        fresh="$(jq -c --argjson now "$(date +%s)" '
            [ { kind: "session",    percent: (.five_hour_pct // -1), reset: (.five_hour_resets // 0) },
              { kind: "weekly_all", percent: (.seven_day_pct // -1), reset: (.seven_day_resets // 0) } ]
            | map(select(.percent >= 0 and (.reset == 0 or .reset > $now)))
            | map({ kind, percent: (.percent | floor), severity: "normal",
                    resetsAtIso: "", resetsAtSec: .reset })
        ' "$ucache" 2>/dev/null || echo '[]')"
        if [ -n "$fresh" ] && [ "$fresh" != "[]" ] && [ "$fresh" != "null" ]; then
            limits="$fresh"
            # Свежесть — это возраст кэша: сам файл и есть отметка времени.
            fetched="$(( $(stat -c %Y "$ucache" 2>/dev/null || echo 0) * 1000 ))"
        fi
    fi

    # Почему лимитов нет — вопрос не праздный: «агент их не отдаёт» и «данных
    # ещё не приехало» выглядят одинаково, а значат противоположное.''', "replace"),
    (r'''        iso="$(printf '%s' "$one" | jq -r '.resetsAtIso')"
        ms="$(iso_ms "$iso")"''',
     r'''        iso="$(printf '%s' "$one" | jq -r '.resetsAtIso')"
        ms="$(iso_ms "$iso")"
        # PANACEA-LOCAL: путь через кэш строки состояния отдаёт epoch в
        # секундах, а не ISO.
        if [ "${ms:-0}" = "0" ]; then
            local sec; sec="$(printf '%s' "$one" | jq -r '.resetsAtSec // 0')"
            [ "${sec:-0}" -gt 0 ] 2>/dev/null && ms="$(( sec * 1000 ))"
        fi''', "replace"),
    (r'''               '. + [ ($one | del(.resetsAtIso) | .resetsAt = $ms) ]')"''',
     r'''               '. + [ ($one | del(.resetsAtIso) | del(.resetsAtSec) | .resetsAt = $ms) ]')"''', "replace"),
    (r'''add "$(claude_json || true)"
add "$(other_agent codex        "Codex CLI"     "$(codex_plan)" || true)"
add "$(other_agent antigravity  "Antigravity"   || true)"
add "$(other_agent gemini       "Gemini CLI"    || true)"
add "$(other_agent opencode     "OpenCode"      || true)"
add "$(other_agent cursor-agent "Cursor Agent"  || true)"
add "$(other_agent windsurf     "Windsurf"      || true)"
add "$(other_agent copilot      "GitHub Copilot" || true)"
add "$(other_agent amp          "Amp"           || true)"
add "$(other_agent aider        "Aider"         || true)"
add "$(other_agent goose        "Goose"         || true)"
add "$(other_agent crush        "Crush"         || true)"
add "$(other_agent droid        "Droid"         || true)"
add "$(other_agent openhands    "OpenHands"     || true)"
add "$(other_agent qwen         "Qwen Code"     || true)"''',
     r'''# PANACEA-LOCAL: опрос версий стоил 3.2 с на КАЖДЫЙ запуск, и 3.0 из них —
# три бинарника с тяжёлым стартом среды: gemini (1.7 с), opencode (0.7 с),
# copilot (0.6 с). Причём вид дёргает скрипт не только на открытии: раз в 20 с
# по таймеру и на каждую правку ~/.claude.json, то есть на каждую отрисовку
# строки состояния Claude Code. Версия и тариф меняются при обновлении CLI —
# раз в неделю, — поэтому держим их в кэше. Нагрузка Claude, единственное живое
# число на этой странице, считается каждый раз заново. `--force` обходит кэш;
# после обновления CLI версия догонит сама, но не позже, чем через TTL.
#
# PANACEA-LOCAL: кэш лежал в /tmp, а /tmp чистится на каждой загрузке. Пустой
# кэш — это опрос с нуля, ~8 с (crush, copilot и cursor-agent упираются в
# timeout по 2 с каждый), и всё это время окно агентов стояло пустым. Хуже
# того: закрытие окна убивает скрипт раньше, чем тот успевал записать кэш, и
# следующее открытие начинало те же 8 с заново — окно не открывалось никогда.
# Поэтому кэш теперь в ~/.cache, а устаревший отдаётся сразу и обновляется в
# фоне (см. --probe ниже).
OTHERS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/panacea-agents.json"
OTHERS_TTL=21600   # 6 ч

others='[]'
oadd() {
    local one="$1"
    [ -n "$one" ] || return 0
    others="$(printf '%s' "$others" | jq -c --argjson one "$one" '. + [$one]')"
}

probe_others() {
    oadd "$(other_agent codex        "Codex CLI"     "$(codex_plan)" || true)"
    oadd "$(other_agent antigravity  "Antigravity"   || true)"
    oadd "$(other_agent gemini       "Gemini CLI"    || true)"
    oadd "$(other_agent opencode     "OpenCode"      || true)"
    oadd "$(other_agent cursor-agent "Cursor Agent"  || true)"
    oadd "$(other_agent windsurf     "Windsurf"      || true)"
    oadd "$(other_agent copilot      "GitHub Copilot" || true)"
    oadd "$(other_agent amp          "Amp"           || true)"
    oadd "$(other_agent aider        "Aider"         || true)"
    oadd "$(other_agent goose        "Goose"         || true)"
    oadd "$(other_agent crush        "Crush"         || true)"
    oadd "$(other_agent droid        "Droid"         || true)"
    oadd "$(other_agent openhands    "OpenHands"     || true)"
    oadd "$(other_agent qwen         "Qwen Code"     || true)"
}

# Запись через временный файл: вид может прочитать кэш посреди записи.
save_others() {
    mkdir -p "${OTHERS_CACHE%/*}" 2>/dev/null
    printf '%s' "$others" >"$OTHERS_CACHE.$$" 2>/dev/null \
        && mv -f "$OTHERS_CACHE.$$" "$OTHERS_CACHE" 2>/dev/null \
        || rm -f "$OTHERS_CACHE.$$"
}

# Фоновый опрос. Своя сессия (setsid) — чтобы закрытие окна не убило и его;
# flock — чтобы таймер вида, дёргающий скрипт раз в 20 с, не наплодил
# параллельных опросов, пока первый ещё идёт.
if [ "${1:-}" = "--probe" ]; then
    mkdir -p "${OTHERS_CACHE%/*}" 2>/dev/null
    exec 9>"$OTHERS_CACHE.lock"
    flock -n 9 || exit 0
    probe_others
    save_others
    exit 0
fi

cached=''; stale=1
if [ -f "$OTHERS_CACHE" ] && jq -e . "$OTHERS_CACHE" >/dev/null 2>&1; then
    cached="$(cat "$OTHERS_CACHE")"
    age=$(( $(date +%s) - $(stat -c %Y "$OTHERS_CACHE" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$OTHERS_TTL" ] && stale=0
fi

if [ "${1:-}" = "--force" ]; then
    probe_others
    save_others
else
    # Устаревшее лучше пустого: версии меняются раз в неделю, а пустое окно и
    # было тем, из-за чего страница казалась сломанной.
    [ -n "$cached" ] && others="$cached"
    [ "$stale" = 1 ] && setsid -f bash "$0" --probe </dev/null >/dev/null 2>&1
fi

add "$(claude_json || true)"
agents="$(printf '%s' "$agents" | jq -c --argjson o "$others" '. + $o')"''', "replace"),
]

patch("shell.qml", SHELL_EDITS)
patch_launcher()
patch("WidgetsView.qml", WIDGETS_EDITS)
patch("Translations.qml", TRANS_EDITS)
patch("ControlsView.qml", CONTROLS_EDITS)
patch("scripts/agents.sh", AGENTS_EDITS)

# --------------------------------------------------------------- AgentsView.qml
# Без этого страница агентов снова обрежется по нижнему краю панели: колонка
# просит 628, а места под неё ~560, и последняя карточка опять станет
# недостижимой.
AGENTSVIEW_EDITS = [
    (r"""import QtQuick
import QtQuick.Layouts""",
     r"""import QtQuick
import QtQuick.Controls
import QtQuick.Layouts""", "replace"),
    (r"""    implicitHeight: col.implicitHeight
""",
     r"""    // PANACEA-LOCAL: Шесть агентов в панель целиком не влезают. Под содержимое от неё
    // остаётся ~560 (сама она не выше cfg.expandedH = 620, минус заголовок и
    // поля), а колонка просит 628 — и всё лишнее просто обрезалось: карточка
    // Crush была разрезана пополам, и добраться до неё было нечем.
    //
    // Прокрутка одна, на всю страницу: вложенные списки со своей прокруткой
    // отнимали бы колесо друг у друга.
    implicitHeight: Math.min(col.implicitHeight, 560)
""", "replace"),
    (r"""    ColumnLayout {
        id: col
        width: parent.width
        spacing: 14
""",
     r"""    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 3000

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle { radius: 2; color: Qt.rgba(1, 1, 1, 0.22) }
        }

    ColumnLayout {
        id: col
        width: view.width
        spacing: 14
""", "replace"),
    (r"""            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
        }
    }
}""",
     r"""            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
        }
    }
    }
}""", "replace"),
]

patch("AgentsView.qml", AGENTSVIEW_EDITS)

# ---------------------------------------------------------- scripts/weather.sh
# Без этого «сети ещё нет» снова притворится «нет такого города», вид сочтёт
# ошибку окончательной и повторять не станет.
WEATHER_EDITS = [
    (r"""lat=$(printf '%s' "$geo" | jq -r '.results[0].latitude // empty' 2>/dev/null)""",
     r"""# PANACEA-LOCAL: Пустой ответ — это оборванная связь, а не отсутствующий город. Разница не
# косметическая: вид повторяет попытку только по сетевой ошибке, а «нет такого
# города» считает окончательным приговором и ждёт следующего круга.
[ -n "$geo" ] || fail "network"

lat=$(printf '%s' "$geo" | jq -r '.results[0].latitude // empty' 2>/dev/null)""", "replace"),
]

patch("scripts/weather.sh", WEATHER_EDITS)


# ------------------------------------------------------------- scripts/wifi.sh
# Без этого меню Wi-Fi снова опустеет: скрипт ходит к iwctl, а на этой машине
# сетями управляет NetworkManager и iwd не стоит вовсе.
WIFI_EDITS = [
    (r'''case "$1" in
status)''',
     r'''# ---------------------------------------------------------- PANACEA-LOCAL
# На этой машине сетями заведует NetworkManager, а iwd снесён вместе с
# iwctl. Всё, что ниже, спрашивало именно у iwctl — и молча получало
# пустоту: `list` не выдавал ни строки, и меню показывало «Сети не
# найдены» при живом, подключённом и прекрасно работающем Wi-Fi.
#
# Отсюда — ветка на nmcli, которая включается, только когда NetworkManager
# действительно запущен. Она берёт на себя ровно те команды, что упирались
# в iwctl; `status` оставлен общему коду ниже — он читает состояние у ядра
# через `iw` и работает при любом менеджере.
if command -v nmcli >/dev/null 2>&1 \
   && [ "$(nmcli -t -f RUNNING general 2>/dev/null)" = "running" ]; then

    # Интерфейс спрашиваем у самого NetworkManager: связанный, а если связи
    # нет ни у одного — первый беспроводной.
    nm_iface() {
        [ -n "${WIFI_IFACE:-}" ] && { printf '%s' "$WIFI_IFACE"; return; }
        nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '
            $2 == "wifi" {
                if ($3 == "connected") { print $1; done = 1; exit }
                if (first == "") first = $1
            }
            END { if (!done && first != "") print first }'
    }
    NMIF="$(nm_iface)"

    # В терсе nmcli экранирует двоеточия обратным слешем — снимаем.
    nm_unesc() { sed 's/\\\(.\)/\1/g'; }

    # UUID сохранённых беспроводных профилей.
    nm_saved() {
        nmcli -t -f UUID,TYPE connection show 2>/dev/null \
            | awk -F: '$2 == "802-11-wireless" { print $1 }'
    }

    # SSID сохранённых сетей. Имя профиля — не имя сети: профиль можно
    # переименовать, и тогда «сохранена» стояло бы не у той строки.
    nm_known() {
        local u
        nm_saved | while IFS= read -r u; do
            nmcli -g 802-11-wireless.ssid connection show uuid "$u" 2>/dev/null | nm_unesc
        done
    }

    case "$1" in
    scan)
        # Скан сразу после предыдущего NetworkManager запрещает. Это не
        # ошибка: у вида просто останется список с прошлого раза.
        nmcli device wifi rescan ${NMIF:+ifname "$NMIF"} >/dev/null 2>&1
        exit 0
        ;;

    list)
        # --rescan no: отдаём то, что уже в кэше. Сканирование — отдельная
        # команда, и ждать его здесь значило бы держать меню пустым лишние
        # секунды на каждом открытии.
        nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no 2>/dev/null \
        | awk -v known="$(nm_known)" '
        # Поля режем вручную: SSID может содержать двоеточие, приезжает оно
        # экранированным, и обычный split по ":" разорвал бы имя пополам.
        function cut(line, out,   i, c, n, fld) {
            n = 1; fld = ""
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "\\") { i++; fld = fld substr(line, i, 1); continue }
                if (c == ":" && n < 4) { out[n++] = fld; fld = ""; continue }
                fld = fld c
            }
            out[n] = fld
        }
        BEGIN {
            n = split(known, arr, "\n")
            for (i = 1; i <= n; i++) if (arr[i] != "") isKnown[arr[i]] = 1
        }
        {
            delete f
            cut($0, f)
            name = f[4]
            if (name == "") next          # скрытая сеть: в меню жать не на что

            sec = f[3]
            if (sec == "") s = "open"
            else if (index(sec, "802.1X")) s = "8021x"
            else if (tolower(sec) ~ /wep/) s = "wep"
            else s = "psk"

            q = f[2] + 0
            # Одна сеть — несколько точек: в меню нужна одна строка, и
            # сигнал у неё лучший из всех.
            if (!(name in best)) { order[++m] = name; best[name] = q; sech[name] = s }
            else if (q > best[name]) best[name] = q
            if (f[1] ~ /\*/) conn[name] = 1
        }
        END {
            for (i = 1; i <= m; i++) {
                name = order[i]
                print (conn[name] ? "yes" : "no") "|" name "|" sech[name] "|" \
                      best[name] "|" (isKnown[name] ? "yes" : "no")
            }
        }'
        exit 0
        ;;

    toggle)
        # Через nmcli, а не rfkill: NetworkManager держит свой флаг радио
        # отдельно, и погашенный только по rfkill он потом сам не поднимет.
        # Мягкую блокировку `radio wifi off` ставит тоже, так что radio_state
        # выше видит результат.
        if [ "$(nmcli radio wifi 2>/dev/null)" = "enabled" ]; then
            nmcli radio wifi off >/dev/null 2>&1
        else
            nmcli radio wifi on >/dev/null 2>&1
        fi
        exit 0
        ;;

    connect)
        SSID="$2"; PW="$3"
        [ -z "$SSID" ] && exit 1
        # --wait: без него неудачная попытка висит полторы минуты, и всё это
        # время меню стоит в «подключаюсь».
        if [ -n "$PW" ]; then
            nmcli --wait 25 device wifi connect "$SSID" password "$PW" \
                  ${NMIF:+ifname "$NMIF"} >/dev/null 2>&1
        else
            nmcli --wait 25 device wifi connect "$SSID" \
                  ${NMIF:+ifname "$NMIF"} >/dev/null 2>&1
        fi
        exit $?
        ;;

    disconnect)
        [ -n "$NMIF" ] && nmcli device disconnect "$NMIF" >/dev/null 2>&1
        exit 0
        ;;

    forget)
        [ -z "$2" ] && exit 1
        # Профилей с одним SSID может быть несколько — сносим все. Иначе
        # «забытая» сеть вернётся из второго профиля при первом же случае.
        nm_saved | while IFS= read -r u; do
            s=$(nmcli -g 802-11-wireless.ssid connection show uuid "$u" 2>/dev/null | nm_unesc)
            [ "$s" = "$2" ] && nmcli connection delete uuid "$u" >/dev/null 2>&1
        done
        exit 0
        ;;
    esac
fi

case "$1" in
status)''', "replace"),
]

patch("scripts/wifi.sh", WIFI_EDITS)


PYEOF

printf '\n'
ok "правки накачены; копии до правки — рядом, с суффиксом .prepatch"
printf '  \033[2mПерезапустить остров: pkill -f "qs -c panacea" && setsid qs -c panacea &\033[0m\n'
