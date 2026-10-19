import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// GitHub: что ждёт лично меня, где я стою и что сломалось.
//
// Данные приезжают из scripts/github.sh — он и решает, куда ходить и что
// спрашивать. Вид ничего не знает про gh и рисует то, что дали: так же, как
// AgentsView не знает про формат чужих конфигов.
//
// Три раздела в порядке срочности, а не в порядке «сначала про меня, потом
// про мир»: входящие требуют ответа, свой репозиторий — контекст под руками,
// прогоны CI — то, что ломается само и без окна остаётся незамеченным.
//
// Строки кликабельны и уводят в браузер. Клик закрывает остров: человек ушёл
// в другое окно, и оставлять раскрытую панель за спиной незачем.
Item {
    id: view
    property var sys

    // Три раздела в панель целиком не влезают: она не выше cfg.expandedH
    // (620 по умолчанию), и всё, что ниже, просто обрезалось — «Прогоны» не
    // было видно вовсе. Поэтому страница прокручивается, а не урезается:
    // показать пять строк из пятидесяти и промолчать про остальные хуже, чем
    // дать до них домотать. 560 — сколько от панели остаётся под содержимое.
    //
    // Прокрутка одна, на всю страницу: вложенные списки со своей прокруткой
    // отнимали бы колесо друг у друга, и попасть в нужный было бы лотереей.
    implicitHeight: Math.min(col.implicitHeight, 560)

    property var  inbox: ({})
    property var  repo: ({})
    property var  actions: []
    property string owner: ""
    property string error: ""
    property bool loaded: false

    property real clockNow: Date.now()
    Timer {
        interval: 30000; repeat: true; running: true
        onTriggered: view.clockNow = Date.now()
    }

    // Разбор общий для обоих процессов ниже: быстрый читает кэш, медленный
    // ходит в сеть, а на экран идёт то, что приехало последним.
    function apply(out) {
        // Пустой ответ — это `--cached` без кэша: показывать нечего, но и
        // гасить уже показанное нельзя.
        if (!out || !String(out).trim()) return;
        try {
            var d = JSON.parse(out);
            view.inbox   = d.inbox   || ({});
            view.repo    = d.repo    || ({});
            view.actions = d.actions || [];
            view.owner   = d.user    || "";
            view.error   = d.error   || "";
        } catch (e) {
            view.inbox = ({}); view.repo = ({}); view.actions = [];
            view.error = "parse";
        }
        view.loaded = true;
        view.clockNow = Date.now();
    }

    // Показать немедленно: кэш любого возраста, в сеть не ходит.
    Process {
        id: pGithub
        command: ["sh", view.sys.scriptDir + "/github.sh", "--cached"]
        running: true
        stdout: StdioCollector { onStreamFinished: view.apply(text) }
    }

    // Обновление в обход кэша — отдельным процессом, а не сменой аргументов у
    // первого. Перезапуск гасил незавершённый вызов, и на остывшем кэше окно
    // стояло пустым все ~3 с, пока шли запросы. Этот не гасит ничего: на
    // экране остаются прошлые цифры, пока не приедут новые.
    // running: true — обновиться нужно и при первом создании вида. Сигнал
    // githubEpoch до сюда не доходит: openGithub() увеличивает счётчик ДО
    // togglePage(), то есть до того, как Connections ниже вообще существует.
    // Он ловит только повторные открытия уже созданного вида.
    Process {
        id: pGithubForce
        command: ["sh", view.sys.scriptDir + "/github.sh", "--force"]
        running: true
        stdout: StdioCollector { onStreamFinished: view.apply(text) }
    }

    // Две минуты — про то, как часто цифры меняются, а не про то, как часто их
    // можно спросить. Кэш скрипта живёт минуту, так что этот тик всегда идёт
    // в сеть, и это здесь именно то, что нужно.
    function refresh() { pGithubForce.running = false; pGithubForce.running = true; }
    Timer {
        interval: 120000; repeat: true; running: true
        onTriggered: view.refresh()
    }

    // Открыли окно — перечитали, причём в обход кэша: за страницей идут
    // именно тогда, когда хотят увидеть сейчас, а не минуту назад.
    Connections {
        target: view.sys
        function onGithubEpochChanged() { view.refresh(); }
    }

    function agoText(iso) {
        if (!iso) return "";
        var t = Date.parse(String(iso));
        if (isNaN(t)) return "";
        var mins = Math.floor((view.clockNow - t) / 60000);
        if (mins < 1)  return view.sys.tr("только что");
        if (mins < 60) return mins + " " + view.sys.tr("мин назад");
        var h = Math.floor(mins / 60);
        if (h < 24) return h + " " + view.sys.tr("ч назад");
        return Math.floor(h / 24) + " " + view.sys.tr("д назад");
    }

    // Цвет прогона по исходу, а не по статусу: «идёт» — это не хорошо и не
    // плохо, а вот «упал» надо увидеть, не читая слов.
    function runColor(status, conclusion) {
        if (String(status) !== "completed") return view.sys.colWarn;
        switch (String(conclusion)) {
        case "success":   return view.sys.tint("#3fb950");
        case "failure":
        case "timed_out": return view.sys.colCrit;
        case "cancelled":
        case "skipped":   return view.sys.colMuted;
        }
        return view.sys.colMuted;
    }

    function kindGlyph(kind) {
        switch (String(kind)) {
        case "review":   return String.fromCodePoint(0xF06A9);  // md-source_pull
        case "assigned": return String.fromCodePoint(0xF0C63);  // md-account_check
        }
        return String.fromCodePoint(0xF009A);                   // md-bell_outline
    }

    function openUrl(url) {
        if (!url) return;
        view.sys.openFileWith(String(url), "");
        view.sys.collapse();
    }

    Flickable {
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

        // -------------------------------------------------------- заголовок
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            BackButton { sys: view.sys }
            Glyph {
                glyph: String.fromCodePoint(0xF02A4)   // md-github
                color: view.sys.colFg
                fontFam: view.sys.fontFam
                size: 19
            }
            Text {
                text: "GitHub"
                color: view.sys.colFg
                font { family: view.sys.fontDisplay; pixelSize: view.sys.fontSize + 1; bold: true }
            }
            Text {
                visible: view.owner.length > 0
                text: view.owner
                color: view.sys.colMuted
                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5 }
            }
            Item { Layout.fillWidth: true }
        }

        // ----------------------------------------------------------- ошибки
        // Разница между «gh не стоит», «gh не залогинен» и «ничего нет» важна:
        // первые две человек чинит одной командой, третья — хорошая новость.
        Text {
            Layout.fillWidth: true
            visible: view.loaded && view.error.length > 0
            text: view.error === "nogh"   ? view.sys.tr("gh не установлен")
                : view.error === "noauth" ? view.sys.tr("gh не залогинен — выполните gh auth login")
                : view.error === "jq"     ? view.sys.tr("jq не установлен")
                                          : view.sys.tr("Не удалось прочитать ответ GitHub")
            color: view.sys.colMuted
            wrapMode: Text.WordWrap
            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
        }

        // --------------------------------------------------------- входящие
        Rectangle {
            Layout.fillWidth: true
            visible: view.loaded && view.error.length === 0
            implicitHeight: inboxBody.implicitHeight + 26
            radius: 14
            color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.05)
            border.width: 1
            border.color: view.sys.colLine

            ColumnLayout {
                id: inboxBody
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 14; rightMargin: 14
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: view.sys.tr("Входящие")
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
                    }
                    Item { Layout.fillWidth: true }

                    Repeater {
                        model: [
                            { n: view.inbox.notifications || 0, label: view.sys.tr("уведомл.") },
                            { n: view.inbox.reviews || 0,       label: view.sys.tr("ревью") },
                            { n: view.inbox.assigned || 0,      label: view.sys.tr("на мне") }
                        ]
                        Rectangle {
                            id: cntPill
                            required property var modelData
                            visible: cntPill.modelData.n > 0
                            implicitWidth: cntRow.implicitWidth + 16
                            implicitHeight: 22
                            radius: 11
                            color: Qt.rgba(view.sys.colOn.r, view.sys.colOn.g, view.sys.colOn.b, 0.18)
                            RowLayout {
                                id: cntRow
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: cntPill.modelData.n
                                    color: view.sys.colOn
                                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5; bold: true }
                                }
                                Text {
                                    text: cntPill.modelData.label
                                    color: view.sys.colOn
                                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 6 }
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: view.inbox.items || []

                    Rectangle {
                        id: itemRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 8
                        color: itemMa.containsMouse
                               ? Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.07)
                               : "transparent"

                        RowLayout {
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            spacing: 8

                            Glyph {
                                glyph: view.kindGlyph(itemRow.modelData.kind)
                                color: view.sys.colMuted
                                fontFam: view.sys.fontFam
                                size: 13
                            }
                            Text {
                                Layout.fillWidth: true
                                text: itemRow.modelData.title || ""
                                color: view.sys.colFg
                                elide: Text.ElideRight
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                            }
                            // Репозиторий без владельца: он один и тот же почти
                            // везде, а место в строке дорого.
                            Text {
                                text: String(itemRow.modelData.repo || "").split("/").pop()
                                color: view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 6 }
                            }
                        }

                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.openUrl(itemRow.modelData.url)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: (view.inbox.total || 0) === 0
                    text: view.sys.tr("Ничего не ждёт — входящие пусты")
                    color: view.sys.colMuted
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5 }
                }
            }
        }

        // -------------------------------------------------- текущий репозиторий
        Rectangle {
            Layout.fillWidth: true
            visible: view.loaded && view.error.length === 0
            implicitHeight: repoBody.implicitHeight + 26
            radius: 14
            color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.05)
            border.width: 1
            border.color: view.sys.colLine

            ColumnLayout {
                id: repoBody
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 14; rightMargin: 14
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: view.sys.tr("В фокусе")
                        color: view.sys.colFg
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: !!view.repo.found
                        text: view.repo.nameWithOwner || ""
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5 }
                    }
                }

                // Раздел зависит от того, какое окно в фокусе, и это не
                // недостаток, а условие: «текущего репозитория» вообще нет,
                // пока человек где-то не стоит. Так и говорим, а не молчим.
                Text {
                    Layout.fillWidth: true
                    visible: !view.repo.found
                    text: view.sys.tr("В окне под фокусом нет репозитория")
                    color: view.sys.colMuted
                    wrapMode: Text.WordWrap
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!view.repo.found
                    spacing: 8

                    Glyph {
                        glyph: String.fromCodePoint(0xF062C)   // md-source_branch
                        color: view.sys.colMuted
                        fontFam: view.sys.fontFam
                        size: 13
                    }
                    Text {
                        text: view.repo.branch || ""
                        color: view.sys.colFg
                        elide: Text.ElideRight
                        Layout.maximumWidth: 220
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                    }
                    Item { Layout.fillWidth: true }

                    Repeater {
                        model: [
                            { n: view.repo.ahead  || 0, sym: "↑", col: view.sys.colOn },
                            { n: view.repo.behind || 0, sym: "↓", col: view.sys.colWarn },
                            { n: view.repo.dirty  || 0, sym: "●", col: view.sys.colMuted }
                        ]
                        Text {
                            required property var modelData
                            visible: modelData.n > 0
                            text: modelData.sym + modelData.n
                            color: modelData.col
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5; bold: true }
                        }
                    }
                }

                // PR ветки: есть — открываем по клику, нет — так и написано.
                // Молчать нельзя: пустое место читается как «ещё не загрузилось».
                Rectangle {
                    Layout.fillWidth: true
                    visible: !!view.repo.found
                    implicitHeight: 28
                    radius: 8
                    color: prMa.containsMouse && !!view.repo.pr
                           ? Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.07)
                           : "transparent"

                    RowLayout {
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        spacing: 8
                        Glyph {
                            glyph: String.fromCodePoint(0xF06A9)   // md-source_pull
                            color: view.sys.colMuted
                            fontFam: view.sys.fontFam
                            size: 13
                        }
                        Text {
                            Layout.fillWidth: true
                            text: view.repo.pr
                                  ? ("#" + view.repo.pr.number + "  " + view.repo.pr.title)
                                  : view.sys.tr("у ветки нет открытого PR")
                            color: view.repo.pr ? view.sys.colFg : view.sys.colMuted
                            elide: Text.ElideRight
                            font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                        }
                    }
                    MouseArea {
                        id: prMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !!view.repo.pr
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.openUrl(view.repo.pr ? view.repo.pr.url : "")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!view.repo.found && !!view.repo.run
                    spacing: 8
                    Rectangle {
                        implicitWidth: 8; implicitHeight: 8; radius: 4
                        Layout.leftMargin: 6
                        color: view.repo.run
                               ? view.runColor(view.repo.run.status, view.repo.run.conclusion)
                               : view.sys.colMuted
                    }
                    Text {
                        Layout.fillWidth: true
                        text: view.repo.run ? (view.repo.run.workflowName || "") : ""
                        color: view.sys.colFg
                        elide: Text.ElideRight
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                    }
                    Text {
                        text: view.repo.run ? view.agoText(view.repo.run.updatedAt) : ""
                        color: view.sys.colMuted
                        font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 6 }
                    }
                }
            }
        }

        // ---------------------------------------------------------- прогоны
        Rectangle {
            Layout.fillWidth: true
            visible: view.loaded && view.error.length === 0 && view.actions.length > 0
            implicitHeight: runsBody.implicitHeight + 26
            radius: 14
            color: Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.05)
            border.width: 1
            border.color: view.sys.colLine

            ColumnLayout {
                id: runsBody
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 14; rightMargin: 14
                }
                spacing: 10

                Text {
                    text: view.sys.tr("Прогоны")
                    color: view.sys.colFg
                    font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 2; bold: true }
                }

                Repeater {
                    model: view.actions

                    Rectangle {
                        id: runRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 8
                        color: runMa.containsMouse
                               ? Qt.rgba(view.sys.colFg.r, view.sys.colFg.g, view.sys.colFg.b, 0.07)
                               : "transparent"

                        RowLayout {
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            spacing: 8

                            Rectangle {
                                implicitWidth: 8; implicitHeight: 8; radius: 4
                                color: view.runColor(runRow.modelData.status, runRow.modelData.conclusion)
                            }
                            Text {
                                text: String(runRow.modelData.repo || "").split("/").pop()
                                color: view.sys.colFg
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 4 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: runRow.modelData.workflowName || ""
                                color: view.sys.colMuted
                                elide: Text.ElideRight
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 5 }
                            }
                            Text {
                                text: view.agoText(runRow.modelData.updatedAt)
                                color: view.sys.colMuted
                                font { family: view.sys.fontFam; pixelSize: view.sys.fontSize - 6 }
                            }
                        }

                        MouseArea {
                            id: runMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.openUrl("https://github.com/" + runRow.modelData.repo + "/actions")
                        }
                    }
                }
            }
        }
    }
    }
}
