import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls as Controls  // panacea: the thin scrollbar of Panacea's lists
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "MenuModel.js" as MenuModel

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    languageFile.reload()
    menuCatalogFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: PanaceaLook.font  // panacea
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  // Display language for the shipped rows. The code lives in
  // ~/.config/omarchy/language (omarchy-language owns it); a missing file
  // means English. The catalog at default/i18n/<code>/menu.json is applied
  // to the default items before the user extension merges on top, so a
  // user's own rows and retitles always win.
  property string language: "en"
  property var menuCatalog: ({})
  readonly property string languagePath: Quickshell.env("OMARCHY_LANGUAGE_FILE") || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/language")
  property var defaultMenuItems: []
  property var userMenuItems: []
  // Whether each file has answered once, loaded or (the user's) missing. At
  // startup both arrive separately, and evaluating guards for the first alone
  // would run the whole batch twice; an open before then evaluates anyway.
  property bool defaultMenuSettled: false
  property bool userMenuSettled: false
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property bool dmenuMultiple: false
  property var dmenuSelected: []
  // What the last confirmed change applied; a failed change returns the checks here.
  property var dmenuSaved: []
  property string dmenuChangeKey: ""
  property var dmenuOnChange: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  // Resets of filterText reach the search line; its edits come back through setFilter.
  onFilterTextChanged: if (filterInput.text !== filterText) filterInput.text = filterText
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null }
  // Bound to the central [menu] section in shell.toml via Commons.Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: PanaceaLook.bg  // panacea
  property color foreground: PanaceaLook.fg  // panacea
  property color border: PanaceaLook.modalBorder  // panacea
  property var borderSpec: Border.flat(border, 1)  // panacea: a hairline, as on Panacea's modal
  property color scrim: PanaceaLook.scrim  // panacea
  property color selectedBackground: PanaceaLook.rowSelected  // panacea
  property color selectedText: PanaceaLook.fg  // panacea
  property color selectedBorder: "transparent"  // panacea
  property var selectedBorderSpec: Border.none()  // panacea: the fill alone marks the row, as in Panacea's launcher
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: PanaceaLook.rowRadius  // panacea: the rows'; the card takes modalRadius
  property int contentMargin: PanaceaLook.modalPadding  // panacea
  property int headerHeight: PanaceaLook.fieldHeight  // panacea
  property int contentSpacing: 10  // panacea
  property int baseRowHeight: PanaceaLook.rowHeight  // panacea
  property int detailRowHeight: PanaceaLook.rowHeight  // panacea: the launcher fits its subtitle in the same row
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: 2  // panacea
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font" || root.activeMenu === "style.font.cjk") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight, panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    var summon = MenuModel.summonAction(command)
    if (summon && root.shell && root.shell.summon(summon.id, summon.payload)) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // panacea: the menu grows out of Panacea's rail, as every surface grows
  // out of the island. Opening on a screen asks Panacea to keep its rail out
  // (`pill holdFor`), and its answer says where the card attaches: the rail's
  // edge on the rail's screen, the screen's own edge on the others. Without
  // Panacea, or off the rail, the card opens centred, on its own.
  property var dock: ({})  // panacea
  readonly property bool docked: dock.attach === true  // panacea
  readonly property real attachX: Number(dock.x || 0)  // panacea
  readonly property real dockFlare: Number(dock.flare || 0)  // panacea
  readonly property int dockOverlap: 2  // panacea: into the rail, so no seam shows
  function dockAt(screen) {  // panacea
    var answer = IpcRegistry.call("pill", "holdFor", ["menu", screen ? String(screen.name || "") : ""])  // panacea
    if (!screen) return  // panacea: the window is going; keep its shape until it has
    var parsed = ({})  // panacea
    try { if (answer.ran && answer.output) parsed = JSON.parse(answer.output) } catch (e) { parsed = ({}) }  // panacea
    root.dock = parsed  // panacea
  }  // panacea

  // panacea: when any row shows an icon, every label starts in the icon
  // column's shadow, so a row without one (the fonts not in use, a picker's
  // plain option) does not stick out to the left.
  readonly property bool iconColumn: rowsHaveIcon(layoutSerial, displayModel.count)  // panacea
  function rowsHaveIcon(_serial, _count) {  // panacea
    for (var i = 0; i < displayModel.count; i++) {  // panacea
      var shown = displayModel.get(i)  // panacea
      if (shown.icon.length > 0 || shown.kind === "app") return true  // panacea
    }  // panacea
    return false  // panacea
  }  // panacea

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  function parseCatalog(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  function setLanguage(raw) {
    var code = String(raw || "").trim()
    if (!/^[a-z]{2,3}(-[A-Za-z]{2})?$/.test(code)) code = "en"
    if (root.language === code) return
    root.language = code
    menuCatalogFile.reload()
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  // Catalog-only rebuilds pass skipGuards: retitling rows cannot change any
  // when/checked answer, so re-running the guard batch would be pure waste.
  function rebuildItemsFromSources(skipGuards) {
    var translatedDefaults = MenuModel.applyTranslations(root.defaultMenuItems, root.menuCatalog)
    // The root row is injected by the merge (it has no JSONC entry), so its
    // "Go" label comes from the catalog's root entry; the merge only uses
    // it for the injected row, never over a user-supplied heading.
    var rootCatalog = root.menuCatalog.root
    var mergedMenu = MenuModel.mergeMenuSources(translatedDefaults, root.userMenuItems, rootCatalog && rootCatalog.label)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    if (!skipGuards && root.defaultMenuSettled && root.userMenuSettled) root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      // Profile names are powerprofilesctl ids; only the label is translated,
      // and the id stays searchable through searchTerms.
      labelFor: function(value) {
        if (value === "power-saver") return Commons.I18n.t("menu.powerProfilePowerSaver")
        if (value === "balanced") return Commons.I18n.t("menu.powerProfileBalanced")
        if (value === "performance") return Commons.I18n.t("menu.powerProfilePerformance")
        return value
      },
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    },
    // Rows carry a fourth field (the English name) so searching "danish"
    // finds the row labeled with its native name; mergeProviderRows turns
    // it into an alias.
    "languages": {
      script: "current=$(omarchy-language 2>/dev/null); omarchy-language list 2>/dev/null | while IFS=$'\\t' read -r name code english; do [[ -z $code ]] && continue; printf '%s\\t%s\\t%s\\t%s\\n' \"$name\" \"$code\" \"$current\" \"$english\"; done",
      icon: "\uf1ab",
      volatile: true,
      actionFor: function(value) { return "omarchy-language " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        searchTerms: [],
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var rawLabel = parts[0] || ""
      var label = spec.labelFor ? spec.labelFor(rawLabel) : rawLabel
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        searchTerms: (parts[3] ? [parts[3]] : []).concat(label !== rawLabel ? [rawLabel] : []),
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` or `disabled:` evaluated
  // truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults, root.disabledResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  // Rows whose `disabled:` evaluated truthy stay listed but dimmed, and the
  // cursor steps over them.
  function isDisabled(entry) {
    return MenuModel.isDisabled(root.disabledResults, entry)
  }

  // A disabled row earns its place in the submenu it belongs to, where the
  // list around it is the point. Search is a list of what you can do, so it
  // leaves them out.
  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry) && !root.isDisabled(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, root.disabledResults, entry, detail, score, section)
  }

  function rowSelectable(index) {
    if (index < 0 || index >= displayModel.count) return false
    return !displayModel.get(index).disabled
  }

  // First selectable row at or past `from`, continuing in the direction of
  // travel and wrapping. -1 when every row is disabled, which leaves the menu
  // with no cursor at all rather than one parked on a row Enter won't run.
  function nextSelectable(from, direction) {
    var count = displayModel.count
    if (count === 0) return -1

    var step = direction < 0 ? -1 : 1
    var index = ((from % count) + count) % count
    for (var i = 0; i < count; i++) {
      if (root.rowSelectable(index)) return index
      index = (index + step + count) % count
    }

    return -1
  }

  // Park the cursor on a selectable row after the rows underneath it changed.
  // A menu with nothing selectable in it -- every app in it already installed
  // -- shows no cursor at all, and grows one the moment a row can take it.
  function settleCursor() {
    var target = root.nextSelectable(root.selectedIndex, 1)
    root.selectedIndex = target >= 0 ? target : 0
    root.cursorActive = target >= 0
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    if (root.dmenuMultiple && root.dmenuOnChange.length === 0) {
      displayModel.append({
        itemId: "dmenu.apply", disabled: false, kind: "dmenu", icon: "", iconFont: "",
        appIcon: "", appId: "", label: Commons.I18n.t("common.apply"), target: "",
        detail: Commons.I18n.tn("menu.selectedCount", root.dmenuSelected.length).arg(Commons.I18n.formatNumber(root.dmenuSelected.length)), path: "", childCount: 0,
        action: "", provider: "", score: -1, section: ""
      })
    }
    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        disabled: false,
        kind: "dmenu",
        icon: root.dmenuMultiple ? (root.dmenuSelected.indexOf(MenuModel.dmenuValue(root.dmenuOptions[i])) !== -1 ? "✓" : "○") : icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function updateDmenuChecks() {
    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (row.itemId === "dmenu.apply") {
        displayModel.setProperty(i, "detail", Commons.I18n.tn("menu.selectedCount", root.dmenuSelected.length).arg(Commons.I18n.formatNumber(root.dmenuSelected.length)))
      } else if (row.kind === "dmenu") {
        var value = MenuModel.dmenuValue(root.dmenuOptions[Number(row.itemId.substring(6))])
        displayModel.setProperty(i, "icon", root.dmenuSelected.indexOf(value) !== -1 ? "✓" : "○")
      }
    }
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    root.settleCursor()

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    var from = cursorActive ? selectedIndex + delta : (delta < 0 ? displayModel.count - 1 : 0)
    var target = root.nextSelectable(from, delta)
    if (target < 0) return

    cursorActive = true
    selectedIndex = target
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      if (root.dmenuMultiple) {
        if (picked.itemId === "dmenu.apply") {
          root.applyDmenuSelection(JSON.stringify(MenuModel.dmenuSelections(root.dmenuOptions, root.dmenuSelected)))
        } else {
          var value = MenuModel.dmenuValue(root.dmenuOptions[Number(picked.itemId.substring(6))])
          var selected = MenuModel.toggleDmenuSelection(selectionProc.requestedSelection(), value)
          if (root.dmenuOnChange.length > 0) {
            selectionProc.enqueue(selected)
          } else {
            root.dmenuSelected = selected
            root.updateDmenuChecks()
          }
        }
      } else {
        root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      }
      return
    }

    if (!root.rowSelectable(index)) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? Commons.I18n.t("menu.inputPrompt") : Commons.I18n.t("menu.selectPrompt")))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    dmenuMultiple = mode === "select" && payload.multiple === true
    dmenuOnChange = dmenuMultiple && Array.isArray(payload.onChange)
      && payload.onChange.every(function(arg) { return typeof arg === "string" }) ? payload.onChange : []
    dmenuChangeKey = String(payload.changeKey || JSON.stringify(dmenuOnChange))
    dmenuSelected = MenuModel.dmenuSelections(dmenuOptions, Array.isArray(payload.selected) ? payload.selected : [], dmenuOnChange.length > 0)
    dmenuSaved = dmenuSelected
    if (dmenuOnChange.length > 0)
      dmenuSelected = MenuModel.dmenuSelections(dmenuOptions, selectionProc.requestedSelection(), true)
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    if (!root.rowSelectable(index)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: selectionProc
    property int serial: 0
    property string changeKey: ""
    property var selected: []
    property var queue: []
    property string collected: ""

    function requestedSelection() {
      for (var i = queue.length - 1; i >= 0; i--) {
        if (queue[i].key === root.dmenuChangeKey) return queue[i].selected
      }
      if (running && changeKey === root.dmenuChangeKey) return selected
      return root.dmenuSelected
    }

    function enqueue(values) {
      var selected = MenuModel.dmenuSelections(root.dmenuOptions, values, true)
      queue = queue.concat([{
        serial: root.requestSerial, key: root.dmenuChangeKey, selected: selected,
        command: root.dmenuOnChange.concat([JSON.stringify(selected)])
      }])
      if (!running) startNext()
    }

    function startNext() {
      if (queue.length === 0) return
      var change = queue[0]
      queue = queue.slice(1)
      serial = change.serial
      changeKey = change.key
      selected = change.selected
      collected = ""
      command = change.command
      running = true
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: selectionProc.collected = text
    }
    onExited: function(exitCode) {
      if (changeKey === root.dmenuChangeKey && root.dmenuActive && root.dmenuOnChange.length > 0) {
        if (exitCode === 0) {
          var applied = selected
          if (collected.trim()) {
            try { applied = JSON.parse(collected) } catch (error) { applied = root.dmenuSelected }
          }
          if (Array.isArray(applied))
            root.dmenuSelected = MenuModel.dmenuSelections(root.dmenuOptions, applied, true)
          root.dmenuSaved = root.dmenuSelected
        } else {
          root.dmenuSelected = root.dmenuSaved
        }
        root.updateDmenuChecks()
      }
      startNext()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.defaultMenuSettled = true; root.rebuildItemsFromSources() }
    // A user file that loaded first held its evaluation for this one.
    onLoadFailed: { root.defaultMenuSettled = true; if (root.userMenuSettled) root.evaluateGuards() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.userMenuSettled = true; root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.userMenuSettled = true; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // The language choice and its catalog are watched the same way, so
  // picking a language under Setup retitles the menu with no shell restart.
  FileView {
    id: languageFile
    path: root.languagePath
    watchChanges: true
    printErrors: false
    onLoaded: root.setLanguage(text())
    onLoadFailed: root.setLanguage("")
    onFileChanged: reload()
  }

  FileView {
    id: menuCatalogFile
    path: root.omarchyPath + "/default/i18n/" + root.language + "/menu.json"
    watchChanges: true
    printErrors: false
    onLoaded: { root.menuCatalog = root.parseCatalog(text()); root.rebuildItemsFromSources(true) }
    onLoadFailed: { root.menuCatalog = ({}); root.rebuildItemsFromSources(true) }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property var disabledResults: ({})   // id → true|false (dim, skip cursor)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      root.disabledResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var nextDisabled = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
        else if (tag === "d") nextDisabled[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      root.disabledResults = nextDisabled
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  OverlayWindow {
    id: panel
    // panacea: showOpen mirrors root.opened, set by the handler below once it
    // has decided whether the card folds back first: bound to root.opened
    // itself, the window went the moment the menu closed, before the fold
    // could hold it.
    property bool showOpen: false  // panacea
    shown: (showOpen && root.rowsLoaded) || folding  // panacea: stays while it folds back
    // panacea: the keyboard goes back to the windows the moment the menu
    // closes, not once it has folded away
    shownKeyboardFocus: folding ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive  // panacea
    WlrLayershell.namespace: "omarchy-menu"

    // The card opens centered exactly as always. The first search keystroke
    // or submenu move freezes the top line where it currently sits — from
    // then on the card grows and shrinks downward instead of re-centering
    // on every resize, which made the menu jump around. The rows height is
    // frozen at the same moment, so the starting menu also caps how tall the
    // card may grow from there. Closing or changing screens unfreezes both.
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - root.cardHeight) / 2))
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      if (shown && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    onShownChanged: if (!shown) { cardTop = -1; maxRowsHeight = -1 }
    onTargetScreenChanged: { cardTop = -1; maxRowsHeight = -1; root.dockAt(targetScreen) }  // panacea: dockAt

    // panacea: the opening. The window shows its content once the output's
    // scale is known (contentRevealed). Out of the rail (root.docked), the
    // card slides out from behind the rail's edge, once the rail itself is
    // most of the way out; on its own, it fades in over the scrim and grows
    // from 96.5%, as Panacea's modal does. Render-thread animators, so a
    // busy first frame cannot skip them, and every open starts from nothing.
    ParallelAnimation {  // panacea
      id: openMotion  // panacea
      OpacityAnimator { target: scrimFill; from: 0; to: 1; duration: PanaceaLook.animFast; easing.type: Easing.OutCubic }  // panacea
      OpacityAnimator { target: card; from: 0; to: 1; duration: PanaceaLook.animFast + 40; easing.type: Easing.OutCubic }  // panacea
      ScaleAnimator { target: card; from: 0.965; to: 1; duration: PanaceaLook.animMs; easing.type: Easing.OutCubic }  // panacea
    }  // panacea
    readonly property real tuckedX: -(card.width + root.dockFlare + root.dockOverlap + 8)  // panacea: behind the rail
    ParallelAnimation {  // panacea
      id: slideMotion  // panacea
      OpacityAnimator { target: scrimFill; from: 0; to: 1; duration: PanaceaLook.animMs; easing.type: Easing.OutCubic }  // panacea
      SequentialAnimation {  // panacea
        PauseAnimation { duration: Math.round(Number(root.dock.railMs || 0) * 0.6) }  // panacea: the rail first
        XAnimator { target: dockSlide; to: 0; duration: PanaceaLook.animMs; easing.type: Easing.OutCubic }  // panacea
      }  // panacea
    }  // panacea
    onContentRevealedChanged: {  // panacea
      openMotion.stop()  // panacea
      slideMotion.stop()  // panacea
      foldMotion.stop()  // panacea
      if (contentRevealed && root.docked) {  // panacea
        scrimFill.opacity = 0; card.opacity = 1; card.scale = 1  // panacea
        dockSlide.x = panel.tuckedX  // panacea
        slideMotion.start()  // panacea
      } else if (contentRevealed) {  // panacea
        dockSlide.x = 0  // panacea
        openMotion.start()  // panacea
      } else { scrimFill.opacity = 0; card.opacity = 0; card.scale = 0.965; dockSlide.x = 0 }  // panacea
    }  // panacea

    // panacea: closing folds the card back into the rail and lifts the dim;
    // the window goes once it has (folding holds `shown`). Opening again
    // meanwhile slides it straight back out.
    property bool folding: false  // panacea
    ParallelAnimation {  // panacea
      id: foldMotion  // panacea
      XAnimator { target: dockSlide; to: panel.tuckedX; duration: PanaceaLook.animFast + 40; easing.type: Easing.InCubic }  // panacea
      OpacityAnimator { target: scrimFill; to: 0; duration: PanaceaLook.animFast + 40; easing.type: Easing.InCubic }  // panacea
      onFinished: panel.folding = false  // panacea
    }  // panacea
    Connections {  // panacea
      target: root  // panacea
      function onOpenedChanged() {  // panacea
        if (root.opened) {  // panacea
          if (panel.folding) {  // panacea
            foldMotion.stop(); panel.folding = false  // panacea
            slideMotion.stop(); dockSlide.x = panel.tuckedX; slideMotion.start()  // panacea
          }  // panacea
          panel.showOpen = true  // panacea
          return  // panacea
        }  // panacea
        if (root.docked && panel.contentRevealed && PanaceaLook.animMs > 0) {  // panacea
          slideMotion.stop(); panel.folding = true; foldMotion.start()  // panacea
        }  // panacea
        panel.showOpen = false  // panacea
      }  // panacea
    }  // panacea

    Rectangle {
      id: scrimFill  // panacea
      anchors.fill: parent
      // panacea: out of the rail, the dim leaves the rail's column alone, so
      // the rail, its flares and the card read as one shape over the windows
      // (the card is the terminals' colour and would melt into one behind it).
      anchors.leftMargin: root.docked ? root.attachX : 0  // panacea
      color: root.scrim
      opacity: 0  // panacea: openMotion fades it in
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    // panacea: out of the rail, the card and its flares sit in dockSlide,
    // which moves as one, inside dockClip, which starts at the rail's edge:
    // the card comes out from behind the rail, never across it.
    Item {  // panacea
      id: dockClip  // panacea
      x: root.docked ? root.attachX - root.dockOverlap : 0  // panacea
      width: panel.width - x  // panacea
      height: panel.height  // panacea
      clip: root.docked  // panacea

      Item {  // panacea
        id: dockSlide  // panacea
        width: parent.width  // panacea
        height: parent.height  // panacea

        PanaceaFillet {  // panacea: where the card's top meets the rail
          visible: root.docked && root.dockFlare > 0  // panacea
          radius: root.dockFlare  // panacea
          overlap: root.dockOverlap  // panacea
          color: root.background  // panacea
          y: card.y - height  // panacea
        }  // panacea

        PanaceaFillet {  // panacea: where its bottom does
          visible: root.docked && root.dockFlare > 0  // panacea
          below: true  // panacea
          radius: root.dockFlare  // panacea
          overlap: root.dockOverlap  // panacea
          color: root.background  // panacea
          y: card.y + card.height  // panacea
        }  // panacea
      }  // panacea
    }  // panacea

    BorderSurface {
      id: card
      parent: dockSlide  // panacea: moves with its flares
      width: root.cardWidth + (root.docked ? root.dockOverlap : 0)  // panacea: the part under the rail's edge
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: PanaceaLook.modalRadius  // panacea
      // panacea: out of the rail, its rail side is square and the flares
      // round it into the rail; on its own, all four corners are round.
      topLeftRadius: root.docked ? 0 : radius  // panacea
      bottomLeftRadius: root.docked ? 0 : radius  // panacea
      x: root.docked ? 0 : Math.round((parent.width - width) / 2)  // panacea: against the rail, or centred
      y: panel.effectiveCardTop
      color: root.background
      borderSpec: root.docked ? Border.none() : root.borderSpec  // panacea: one shape with the rail, no outline
      padding: root.contentMargin
      leftPadding: root.contentMargin + (root.docked ? root.dockOverlap : 0)  // panacea
      // panacea: openMotion fades and scales it in. Moving between menus
      // resizes it smoothly, as Panacea's modal does between sections; the
      // first layout snaps.
      clip: true  // panacea: rows stay inside while the height moves
      opacity: 0  // panacea
      scale: 0.965  // panacea
      Behavior on height {  // panacea
        enabled: card.opacity > 0.98 && panel.cardTop >= 0  // panacea
        NumberAnimation { duration: PanaceaLook.animMs; easing.type: Easing.InOutCubic }  // panacea
      }  // panacea

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0

        // Focus is on filterInput, which forwards every key here first.
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            // Swallow the rest too, or it would type into the search line behind the dialog.
            deleteConfirm.handleKey(event)
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || Util.readingKey(event) === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || Util.readingKey(event) === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else root.settleCursor()
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: Commons.I18n.t("common.uninstallConfirm").arg((root.deleteTarget && root.deleteTarget.label) || "")
          confirmText: Commons.I18n.t("common.uninstall")
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          // panacea: Panacea's back arrow, in a submenu. It does what
          // Backspace does.
          Rectangle {  // panacea
            id: backButton  // panacea
            readonly property bool shown: !root.dmenuActive && root.activeMenu !== "root"  // panacea
            visible: shown  // panacea
            width: shown ? PanaceaLook.backSize : 0  // panacea
            height: PanaceaLook.backSize  // panacea
            anchors.left: parent.left  // panacea
            anchors.verticalCenter: parent.verticalCenter  // panacea
            radius: PanaceaLook.backRadius  // panacea
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, backArea.containsMouse ? 0.13 : 0.06)  // panacea
            Behavior on color { ColorAnimation { duration: 150 } }  // panacea

            Text {  // panacea
              anchors.centerIn: parent  // panacea
              text: String.fromCodePoint(0xF004D)  // panacea: md-arrow_left
              color: backArea.containsMouse ? root.foreground : PanaceaLook.muted  // panacea
              font.family: root.fontFamily  // panacea
              font.pixelSize: PanaceaLook.iconSize - 4  // panacea
              Behavior on color { ColorAnimation { duration: 150 } }  // panacea
            }  // panacea

            MouseArea {  // panacea
              id: backArea  // panacea
              anchors.fill: parent  // panacea
              hoverEnabled: true  // panacea
              cursorShape: Qt.PointingHandCursor  // panacea
              onClicked: if (!root.deleteConfirmOpen) root.goBack()  // panacea
            }  // panacea
          }  // panacea

          // panacea: Panacea's search field: a magnifier, the line, and how
          // many rows it shows.
          Rectangle {  // panacea
            id: searchField  // panacea
            anchors.left: backButton.right  // panacea
            anchors.leftMargin: backButton.shown ? 9 : 0  // panacea
            anchors.right: parent.right  // panacea
            height: parent.height  // panacea
            radius: PanaceaLook.fieldRadius  // panacea
            color: PanaceaLook.fieldFill  // panacea
            border.width: 1  // panacea
            border.color: filterInput.activeFocus ? PanaceaLook.fieldFocus : PanaceaLook.line  // panacea
            Behavior on border.color { ColorAnimation { duration: 150 } }  // panacea
          }  // panacea

          // panacea: in the rows' icon column, so the line starts where the
          // labels do.
          Text {  // panacea
            id: searchGlyph  // panacea
            anchors.left: searchField.left  // panacea
            anchors.leftMargin: 10  // panacea
            anchors.verticalCenter: parent.verticalCenter  // panacea
            width: PanaceaLook.tileSize  // panacea
            horizontalAlignment: Text.AlignHCenter  // panacea
            text: String.fromCodePoint(0xF0349)  // panacea: md-magnify
            color: PanaceaLook.muted  // panacea
            font.family: root.fontFamily  // panacea
            font.pixelSize: 14  // panacea
          }  // panacea

          Text {  // panacea
            id: rowCount  // panacea
            anchors.right: searchField.right  // panacea
            anchors.rightMargin: 13  // panacea
            anchors.verticalCenter: parent.verticalCenter  // panacea
            visible: root.mode !== "input" && displayModel.count > 0  // panacea
            text: Commons.I18n.formatNumber(displayModel.count)  // panacea
            color: PanaceaLook.muted  // panacea
            font.family: root.fontFamily  // panacea
            font.pixelSize: PanaceaLook.fontSize - 4  // panacea
          }  // panacea

          FilterInput {
            id: filterInput
            anchors.left: searchGlyph.right  // panacea
            anchors.leftMargin: 11  // panacea
            anchors.right: rowCount.visible ? rowCount.left : searchField.right  // panacea
            anchors.rightMargin: rowCount.visible ? 9 : 13  // panacea
            anchors.verticalCenter: parent.verticalCenter
            keyHandler: keyCatcher
            // Input-method commits bypass key handling, so the dialog has to refuse them here.
            readOnly: root.deleteConfirmOpen
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: PanaceaLook.fontSize - 2  // panacea
            onTextChanged: if (text !== root.filterText) root.setFilter(text)
          }

          Text {
            textFormat: Text.PlainText
            anchors.fill: filterInput
            verticalAlignment: Text.AlignVCenter
            visible: !root.filterText && !filterInput.preeditText
            text: root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "Go") + "…")
            color: PanaceaLook.muted  // panacea
            opacity: 1  // panacea: the colour is muted already
            font.family: root.fontFamily
            font.pixelSize: PanaceaLook.fontSize - 2  // panacea
            elide: Text.ElideRight
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            Controls.ScrollBar.vertical: Controls.ScrollBar {  // panacea: Panacea's thin scrollbar
              id: rowsBar  // panacea
              policy: Controls.ScrollBar.AsNeeded  // panacea
              width: 3  // panacea
              padding: 0  // panacea: the style pads 2 px a side, which left a 3 px bar no room for its thumb
              // panacea: shown while the rows overflow, as Panacea's lists do (the
              // style's fade-in never fires for the wheel)
              contentItem: Rectangle { radius: 2; color: PanaceaLook.scrollThumb; opacity: rowsBar.size < 1 ? 1 : 0 }  // panacea
            }  // panacea

            WheelHandler {
              target: null
              onWheel: function(event) {
                var delta = event.pixelDelta.y || event.angleDelta.y / 120 * root.rowHeightForDetail("") * 3
                var bottom = resultList.originY + Math.max(0, resultList.contentHeight - resultList.height)
                resultList.contentY = Math.max(resultList.originY, Math.min(bottom, resultList.contentY - delta))
                event.accepted = true
              }
            }

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: PanaceaLook.line  // panacea
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount
              required property bool disabled

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              // Faded: the row is here to say the software is already
              // installed, not to be picked.
              opacity: row.disabled ? 0.4 : 1
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              Behavior on color { ColorAnimation { duration: 120 } }  // panacea: as the launcher's rows
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              // panacea: the launcher's icon tile, behind a row's glyph.
              Rectangle {  // panacea
                visible: iconText.visible  // panacea
                anchors.fill: iconText  // panacea
                radius: PanaceaLook.tileRadius  // panacea
                color: PanaceaLook.tileFill  // panacea
              }  // panacea

              Text {
                id: iconText
                textFormat: Text.PlainText
                visible: row.hasIcon && !row.isApp
                text: row.icon
                color: root.foreground  // panacea
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: PanaceaLook.iconSize - 2  // panacea
                width: PanaceaLook.tileSize  // panacea
                height: PanaceaLook.tileSize  // panacea
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: 10  // panacea
                anchors.verticalCenter: parent.verticalCenter  // panacea: centred on the row, as in the launcher
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: PanaceaLook.tileSize  // panacea
                height: PanaceaLook.tileSize  // panacea
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp && root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: 10  // panacea
                anchors.verticalCenter: parent.verticalCenter  // panacea
              }

              Column {
                id: contentColumn
                anchors.left: root.iconColumn ? iconText.right : parent.left  // panacea
                anchors.leftMargin: root.iconColumn ? 11 : 14  // panacea
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0  // panacea

                Text {
                  id: labelText
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: PanaceaLook.fontSize - 2  // panacea
                  font.weight: row.hasCursor ? Font.Bold : Font.Normal  // panacea: the launcher bolds the row under the cursor
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  // A parent path's separator points along the reading direction.
                  text: Commons.I18n.rightToLeft && row.kind !== "dmenu" ? row.detail.replace(/ › /g, " ‹ ") : row.detail
                  visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0
                  color: PanaceaLook.muted  // panacea
                  opacity: 1  // panacea: the colour is muted already
                  font.family: root.fontFamily
                  font.pixelSize: PanaceaLook.fontSize - 5  // panacea
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: 13  // panacea: the count's margin, so the marks end where it does
                anchors.verticalCenter: parent.verticalCenter  // panacea
                spacing: 0

                Text {
                  textFormat: Text.PlainText
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                // panacea: Panacea's chevron on a submenu, and the launcher's
                // Enter mark on the row Enter would run.
                Text {
                  readonly property bool opens: row.kind === "menu" || row.kind === "link"  // panacea
                  width: trail.width  // panacea
                  horizontalAlignment: Text.AlignRight  // panacea
                  textFormat: Text.PlainText
                  text: opens ? String.fromCodePoint(Commons.I18n.rightToLeft ? 0xF0141 : 0xF0142) : (row.hasCursor ? "󰌑" : "")  // panacea: md-chevron_left/right, md-keyboard_return
                  color: opens && row.hasCursor ? root.foreground : PanaceaLook.muted  // panacea
                  opacity: 1  // panacea
                  font.family: root.fontFamily
                  font.pixelSize: opens ? 13 : 12  // panacea
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  if (row.disabled) return
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }
            }
          }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.background }
              GradientStop { position: 1; color: Util.alpha(root.background, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input"

            Text {
              visible: false  // panacea: the launcher says it in one quiet line
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              textFormat: Text.PlainText
              text: root.filterText ? Commons.I18n.t("common.noMatchesFor").arg(root.filterText) : Commons.I18n.t("menu.nothingHere")
              color: PanaceaLook.muted  // panacea
              opacity: 1  // panacea
              font.family: root.fontFamily
              font.pixelSize: PanaceaLook.fontSize - 4  // panacea
              horizontalAlignment: Text.AlignHCenter
              width: resultList.width  // panacea: inside the card
              elide: Text.ElideRight  // panacea
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }
  }
}
