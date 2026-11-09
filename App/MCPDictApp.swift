import SwiftUI

@main
struct MCPDictApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model).task { await model.start() } }
    }
}

struct SavedReading: Identifiable, Codable {
    var id = UUID()
    let reading: Reading
    var note = ""
    var books: Set<UUID>? = nil
    var membership: Set<UUID> { books ?? [VocabularyBook.original.id] }
}

@MainActor
final class AppModel: ObservableObject {
    let repository: DictionaryRepository
    let tableStore: TableStore
    let languageSelection: LanguageSelectionState
    @Published var activeTab = 0
    @Published var mapHandoff: MapHandoff?
    func openResultOnMap(_ character: String) {
        let mode: SearchMode = resultMode == .note ? .note : .character
        var found = MapSearchResult(mode: mode, query: resultQuery)
        found.choices = resultCharacters
        // Preserve the submitted dictionary result, even if the draft selection has since changed.
        let choices = Set(found.choices)
        var seen = [String: [String: Set<MapSearchResult.Line>]]()
        for row in results {
            let line = MapSearchResult.Line(text: row.pronunciation, pronunciation: row.pronunciation, note: mode == .note ? row.note : "")
            for c in row.characters where !c.isWhitespace {
                let key = String(c)
                if choices.contains(key), seen[key, default: [:]][row.language, default: []].insert(line).inserted {
                    found.groups[key, default: [:]][row.language, default: []].append(line)
                }
            }
        }
        let names = Set(results.map(\.language))
        mapHandoff = MapHandoff(character: character, result: found, names: names)
        activeTab = 2
    }
    @Published var tableDetail: TablePackage?
    @Published var installed: TableInstallation? { didSet { rebuildTableLookup() } }
    @Published var catalog: TableCatalog? { didSet { rebuildTableLookup() } }
    @Published var languages = [String]() { didSet { if selectedLanguages == nil { selectedLanguageNames = Set(languages) } } }
    @Published var results = [Reading]() { didSet { characterGroupCache = [:]; homophoneCache = nil } }
    @Published var resultMode: SearchMode = .character
    @Published var resultQuery = ""
    @Published var resultCharacters = [String]()
    @Published var downloading = false
    @Published var downloadedCount = 0
    @Published var tableProgress = 0.0
    @Published var removing = false
    @Published private(set) var notebook = NotebookArchive() {
        didSet { savedMemberships = notebook.entries.reduce(into: [:]) { $0[ReadingContentKey($1.reading)] = $1.membership } }
    }
    var favorites: [SavedReading] {
        get { notebook.entries }
        set { notebook.entries = newValue }
    }
    var visibleFavorites: [SavedReading] {
        favorites.filter { !$0.membership.isDisjoint(with: notebook.selected) }
    }
    @Published var query = ""
    @Published var mode: SearchMode = .character
    @Published var language = ""
    @Published var selectedLanguages: [String]? { didSet { selectedLanguageNames = Set(selectedLanguages ?? languages) } }
    private(set) var selectedLanguageNames = Set<String>()
    @Published var error: String?
    @Published var status = "尚未下載詞典"
    @Published var updating = false
    @Published var searching = false
    @Published var hasMore = false
    private var lastSearch: (String, SearchMode, String, [String]?)?
    private var generation = 0
    private var started = false
    private var updateTask: Task<Void, Never>?
    private var latestDownloadedCount = 0
    private var lastDownloadProgress = -Double.infinity
    private var lastDownloadStatus = -Double.infinity
    private func reportDownloadCount(_ count: Int, total: Int) {
        latestDownloadedCount = count
        let now = ProcessInfo.processInfo.systemUptime
        guard count == total || now - lastDownloadProgress >= 0.1 else { return }
        lastDownloadProgress = now
        downloadedCount = count; tableProgress = 0.9 * Double(count) / Double(max(1, total))
    }
    private func reportDownloadStatus(_ message: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard message.hasPrefix("正在") || now - lastDownloadStatus >= 0.1 else { return }
        lastDownloadStatus = now; status = message
    }
    private let favoritesURL: URL
    private let selectionCache: LanguageSelectionCache
    init(defaults: UserDefaults = .standard, favoritesURL: URL? = nil) {
        if defaults.object(forKey: "colorScheme") == nil {
            defaults.set(defaults.string(forKey: "dictionaryPalette") ?? defaults.string(forKey: "mapPalette") ?? "atlas", forKey: "colorScheme")
        }
        selectionCache = LanguageSelectionCache(defaults: defaults)
        languageSelection = LanguageSelectionState(namespace: "dictionary", defaults: defaults)
        let repository = DictionaryRepository()
        self.repository = repository
        tableStore = TableStore(repository: repository)
        self.favoritesURL = favoritesURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("favorites.json")
    }
    func start() async {
        guard !started else { return }; started = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-fixture") {
            UserDefaults.standard.set("hant", forKey: "uiLanguage")
            let fixture = UITestFixtures.catalog
            catalog = fixture
            installed = TableInstallation(catalogVersion: "ui-test", tables: fixture.tables, databaseFile: nil)
            languages = fixture.tables.map(\.name)
            if ProcessInfo.processInfo.arguments.contains("--reset-selection") {
                for key in ["favoriteAction", FavoritePreferences.defaultsKey, ReferencePreferences.key, "notebookCategory", "notebookCategories", "colorScheme", AppTypography.interfaceKey, AppTypography.mapKey, AppTypography.readingKey] { UserDefaults.standard.removeObject(forKey: key) }
                for namespace in ["dictionary", "map", "downloads"] {
                    selectionCache.defaults.removeObject(forKey: "languageSelection." + namespace)
                    selectionCache.defaults.removeObject(forKey: "selectionMode." + namespace)
                    for mode in MapSearchKind.allCases {
                        for prefix in ["languageSelection.", "grouping.", "roles."] { selectionCache.defaults.removeObject(forKey: prefix + namespace + "." + mode.rawValue) }
                        for grouping in TableGrouping.allCases { selectionCache.defaults.removeObject(forKey: "regionNode." + namespace + "." + mode.rawValue + grouping.rawValue) }
                    }
                    selectionCache.defaults.removeObject(forKey: "island." + namespace)
                    selectionCache.defaults.removeObject(forKey: "history." + namespace)
                    selectionCache.defaults.removeObject(forKey: "transitions." + namespace)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--reset-selection") { languageSelection.resetFixture() }
            try? await repository.open(UITestFixtures.database())
            restoreLanguageSelection()
            if ProcessInfo.processInfo.arguments.contains("--notebook-list-fixture") {
                favorites = (0..<35).map { index in
                    SavedReading(reading: Reading(id: Int64(index), characters: "好", language: "示例語言點", pronunciation: "hæ3", note: String(repeating: "完整注釋內容", count: 15)))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--busy-fixture") { updating = true; downloading = true }
            status = ""
            if ProcessInfo.processInfo.arguments.contains("--catalog-progress-fixture") {
                updating = true; tableProgress = 0.5; status = "正在取得字表目錄…"
            }
            return
        }
        #endif
        updating = true; status = "正在準備內置字表…"
        defer { updating = false }
        // Remove the retired optional map-provider setting on upgrade.
        UserDefaults.standard.removeObject(forKey: "mapTilerKey")
        do {
            try restoreNotebook()
        } catch { self.error = "收藏讀取失敗：\(error.localizedDescription)" }
        do {
            try await tableStore.installBundledTablesIfNeeded()
            installed = try await tableStore.restore()
            catalog = await tableStore.cachedCatalog()
            languages = try await repository.languages()
            restoreLanguageSelection()
            status = "已下載 \(installed?.tables.count ?? 0) 份字表"
        } catch { self.error = error.localizedDescription }
    }
    func search(more: Bool = false, queryOverride: String? = nil, modeOverride: SearchMode? = nil) async {
        generation += 1
        let token = generation
        searching = true
        defer { if token == generation { searching = false } }
        // Selecting a result variant must never overwrite the editable input.
        let input = (queryOverride ?? query, modeOverride ?? mode, language, selectedLanguages)
        let request = more ? (lastSearch ?? input) : input
        let ranks = ResultOrdering.ranks(installed?.tables ?? [], namespace: "dictionary")
        do {
            let found: [Reading]
            let variants = request.1 == .character ? await Task.detached(priority: .userInitiated) { CharacterVariants.expand(request.0) }.value : []
            if request.1 == .character { found = try await repository.searchAllCharacters(variants.joined(), language: request.2, languages: request.3) }
            else { found = try await repository.searchAll(request.0, mode: request.1, language: request.2, languages: request.3) }
            guard token == generation else { return }
            let previous = more ? results : []
            let prepared = await Task.detached {
                let ordered = previous + ResultOrdering.sorted(found, ranks: ranks)
                var choices = [String](), seen = Set<String>()
                if request.1 == .note {
                    for row in found { for char in row.characters where !char.isWhitespace {
                        let value = String(char); if seen.insert(value).inserted { choices.append(value) }
                    } }
                }
                return (ordered, request.1 == .pronunciation ? [:] : CharacterResults.index(ordered), choices)
            }.value
            guard token == generation else { return }
            results = prepared.0; characterGroupCache = prepared.1
            lastSearch = request
            resultMode = request.1; resultQuery = request.0
            resultCharacters = request.1 == .note ? prepared.2 : variants
            hasMore = false
        } catch { self.error = error.localizedDescription }
    }
    func resetSettings() {
        let defaults = selectionCache.defaults
        let keys = ["appearance", "uiLanguage", AppTypography.interfaceKey, AppTypography.mapKey,
                    AppTypography.readingKey, "toneStyle", "pitchStyle", "colorScheme", "dictionaryPalette",
                    "mapPalette", "baseMapStyle", "preferredMapApp", ReferencePreferences.key]
        let prefixes = ["languageSelection.", "selectionMode.", "grouping.", "roles.", "regionNode.", "island.", "history.", "transitions."]
        for key in defaults.dictionaryRepresentation().keys where keys.contains(key) || prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
        languageSelection.resetDefaults()
        selectedLanguages = nil; language = ""
        query = ""; mode = .character; generation += 1; searching = false
        results = []; resultCharacters = []; hasMore = false; lastSearch = nil; mapHandoff = nil
        settingsRevision += 1
    }
    @Published var settingsRevision = 0
    func downloadableIDs(_ selection: Set<String>) -> Set<String> {
        // Only catalog entries can be missing/update; use the cached lookup rather
        // than scanning every available table on each progress notification.
        selection.filter { downloadStates[$0] == .missing || downloadStates[$0] == .update }
    }
    func loadCatalog() async {
        guard !updating else { return }
        updating = true; tableProgress = 0
        status = "正在取得字表目錄…"
        let task = Task {
            defer { updating = false; updateTask = nil }
            do {
                let refreshed = try await tableStore.refreshCatalog(progress: { fraction in
                    await MainActor.run { self.tableProgress = fraction }
                })
                installed = refreshed.installation
                catalog = refreshed.catalog
                status = "目錄已更新 · 已下載 \(installed?.tables.count ?? 0) 份字表"
            } catch { status = "檢查失敗，現有資料仍可使用"; self.error = error.localizedDescription }
        }
        updateTask = task
        await task.value
    }
    func downloadTables(_ selection: Set<String>) {
        let selection = downloadableIDs(selection)
        guard !updating, !selection.isEmpty, let catalog else { return }
        updating = true; downloading = true; downloadedCount = 0; tableProgress = 0
        status = "正在下載字表…"
        latestDownloadedCount = 0; lastDownloadProgress = -Double.infinity; lastDownloadStatus = -Double.infinity
        updateTask = Task {
            defer {
                downloadedCount = latestDownloadedCount
                updating = false; downloading = false; updateTask = nil
            }
            do {
                let result = try await tableStore.download(catalog, selected: selection, completedCount: { count in
                    await MainActor.run { self.reportDownloadCount(count, total: selection.count) }
                }) { message in
                    await MainActor.run { self.reportDownloadStatus(message) }
                }
                installed = result.installation
                try await refreshAfterTables()
                tableProgress = result.cancelled || result.failure != nil ? tableProgress : 1
                if let failure = result.failure { status = "已保留完成的字表"; error = failure }
                else { status = result.cancelled ? "已取消，已保留完成的字表" : "下載完成" }
            } catch { status = "操作未完成，原有字表仍可使用"; self.error = error.localizedDescription }
        }
    }
    func removeTables(_ selection: Set<String>) {
        guard !updating, !selection.isEmpty else { return }
        updating = true
        removing = true; tableProgress = 0
        status = "正在移除字表…"
        updateTask = Task {
            defer { updating = false; removing = false; updateTask = nil }
            do {
                installed = try await tableStore.remove(selected: selection) { fraction in
                    await MainActor.run { self.tableProgress = fraction }
                }
                try await refreshAfterTables()
                status = "移除完成"
            } catch { self.error = error.localizedDescription }
        }
    }
    private func refreshAfterTables() async throws {
        generation += 1
        results = []; hasMore = false; lastSearch = nil
        languages = try await repository.languages()
        let availableLanguages = Set(languages)
        if let selection = selectedLanguages {
            selectLanguages(Set(selection.filter { availableLanguages.contains($0) }))
        } else if !languages.contains(language) { language = "" }
    }
    func selectLanguages(_ names: Set<String>) {
        guard selectedLanguageNames != names || selectedLanguages == nil else { return }
        selectedLanguages = names.sorted()
        language = ui("已選 \(names.count) 個語言點")
        selectionCache.save(names, for: "dictionary")
    }
    func restoreLanguageSelection() {
        if let saved = selectionCache.load("dictionary") { selectLanguages(saved.intersection(Set(languages))) }
    }
    func cancelDownload() { updateTask?.cancel(); status = "正在取消並保存已完成的字表…" }
    private(set) var availableTables = [TablePackage]()
    private(set) var downloadStates = [String: TableDownloadState]()
    private var tableLookup = [String: TablePackage]()
    private(set) var tableRevision = 0
    private var indexedInstalledTables: [TablePackage]?
    private var indexedCatalogTables: [TablePackage]?
    private func rebuildTableLookup() {
        let local = installed?.tables, online = catalog?.tables
        guard local != indexedInstalledTables || online != indexedCatalogTables else { return }
        indexedInstalledTables = local; indexedCatalogTables = online
        tableRevision += 1
        var lookup = [String: TablePackage]()
        for table in installed?.tables ?? [] { lookup[table.name] = table }
        for table in catalog?.tables ?? [] { lookup[table.name] = table }
        tableLookup = lookup
        var byID = Dictionary(uniqueKeysWithValues: (installed?.tables ?? []).map { ($0.id, $0) })
        var states = byID.mapValues { _ in TableDownloadState.downloaded }
        for table in catalog?.tables ?? [] {
            states[table.id] = byID[table.id].map { $0.sha256 == table.sha256 ? .downloaded : .update } ?? .missing
            byID[table.id] = table
        }
        downloadStates = states
        availableTables = byID.values.sorted { $0.name < $1.name }
    }
    func table(named name: String) -> TablePackage? { tableLookup[name] }
    func updateInstalledTables() async {
        guard !updating else { return }
        updating = true
        status = "正在檢查上游最新字表…"
        do { catalog = try await tableStore.catalog() }
        catch {
            updating = false
            status = "檢查失敗，現有資料仍可使用"
            self.error = error.localizedDescription
            return
        }
        updating = false
        guard let catalog else { return }
        let ids = Set(installed?.tables.map(\.id) ?? [])
        guard ids.isSubset(of: Set(catalog.tables.map(\.id))) else {
            error = "部分已下載字表已從上游目錄移除，請在資料頁確認選擇後再套用。"
            return
        }
        downloadTables(ids)
    }
    private var characterGroupCache = [String: [CharacterReadingGroup]]()
    private var homophoneCache: [[Reading]]?
    private var savedMemberships = [ReadingContentKey: Set<UUID>]()
    func isSaved(_ reading: Reading) -> Bool {
        !notebook.selected.isEmpty && notebook.selected.isSubset(of: savedMemberships[ReadingContentKey(reading)] ?? [])
    }
    func characterGroups(_ character: String) -> [CharacterReadingGroup] {
        if let cached = characterGroupCache[character] { return cached }
        let groups = CharacterResults.groups(results, character: character)
        characterGroupCache[character] = groups
        return groups
    }
    func homophoneGroups() -> [[Reading]] {
        if let homophoneCache { return homophoneCache }
        var order = [String](), groups = [String: [Reading]]()
        for row in results {
            let key = row.language + "\u{0}" + row.pronunciation
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        let values = order.compactMap { groups[$0] }
        homophoneCache = values
        return values
    }
    func restoreNotebook() throws {
        if FileManager.default.fileExists(atPath: favoritesURL.path) {
            notebook = try NotebookArchive.decode(Data(contentsOf: favoritesURL))
        }
    }
    @discardableResult private func changeNotebook(_ edit: (inout NotebookArchive) -> Void) -> Bool {
        var next = notebook
        edit(&next)
        do {
            try FileManager.default.createDirectory(at: favoritesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: favoritesURL, options: .atomic)
            notebook = next
            return true
        } catch { self.error = "收藏儲存失敗：\(error.localizedDescription)"; return false }
    }
    func memberships(_ reading: Reading) -> Set<UUID> { savedMemberships[ReadingContentKey(reading)] ?? [] }
    func assign(_ reading: Reading, to ids: Set<UUID>) {
        let targets = ids.intersection(notebook.books.map(\.id))
        changeNotebook { next in
            if let i = next.entries.firstIndex(where: { ReadingContentKey($0.reading) == ReadingContentKey(reading) }) {
                if targets.isEmpty { next.entries.remove(at: i) } else { next.entries[i].books = targets }
            } else if !targets.isEmpty { next.entries.append(SavedReading(reading: reading, books: targets)) }
        }
    }
    func save(_ reading: Reading, to targets: Set<UUID>? = nil) {
        let targets = (targets ?? notebook.selected).intersection(notebook.books.map(\.id))
        guard !targets.isEmpty else { error = "請先在生字本選擇或新建生字本"; return }
        if targets.isSubset(of: savedMemberships[ReadingContentKey(reading)] ?? []) { return }
        changeNotebook { next in
            if let i = next.entries.firstIndex(where: { ReadingContentKey($0.reading) == ReadingContentKey(reading) }) {
                next.entries[i].books = next.entries[i].membership.union(targets)
            } else { next.entries.append(SavedReading(reading: reading, books: targets)) }
        }
    }
    @discardableResult func setBookName(_ raw: String, id: UUID? = nil, selectNew: Bool = true) -> UUID? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !notebook.books.contains(where: { $0.id != id && $0.name == name }) else {
            error = "請輸入非空且未使用的生字本名稱"; return nil
        }
        let target = id ?? UUID()
        let saved = changeNotebook { next in
            if let i = next.books.firstIndex(where: { $0.id == target }) { next.books[i].name = name }
            else if id == nil {
                next.books.append(VocabularyBook(id: target, name: name))
                if selectNew { next.selected = [target] }
            }
        }
        return saved ? target : nil
    }
    func importNotebook(_ data: Data) throws {
        let incoming = try NotebookArchive.decode(data)
        guard changeNotebook({ $0.merge(incoming) }) else { throw DictionaryFailure(message: "生字本匯入儲存失敗") }
    }
    func selectBooks(_ ids: Set<UUID>) { changeNotebook { $0.selected = ids.intersection($0.books.map(\.id)) } }
    func deleteBooks(_ ids: Set<UUID>) { changeNotebook { $0.remove(ids) } }
    func addFavorites(_ ids: Set<UUID>, to book: UUID) {
        guard notebook.books.contains(where: { $0.id == book }) else { return }
        changeNotebook { next in
            for i in next.entries.indices where ids.contains(next.entries[i].id) {
                next.entries[i].books = next.entries[i].membership.union([book])
            }
        }
    }
    func setNote(_ note: String, for id: UUID) {
        changeNotebook { next in
            if let i = next.entries.firstIndex(where: { $0.id == id }) { next.entries[i].note = note }
        }
    }
    func removeVisibleFavorites(_ ids: Set<UUID>) {
        changeNotebook { next in
            for i in next.entries.indices where ids.contains(next.entries[i].id) {
                next.entries[i].books = next.entries[i].membership.subtracting(next.selected)
            }
            next.entries.removeAll { $0.membership.isEmpty }
        }
    }
    func deleteFavorites(_ offsets: IndexSet) { changeNotebook { $0.entries.remove(atOffsets: offsets) } }

}

// iOS 26 needs a stable native tab controller during page resets.
// Earlier navigation hosts must be replaced together with their page state.
private struct ResettableTabContent<Content: View>: View {
    let revision: String
    @ViewBuilder let content: () -> Content
    var body: some View { content().id(revision) }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("uiLanguage") private var uiLanguage = "hant"
    @AppStorage(AppTypography.interfaceKey) private var fontSize = 17.0
    private var settingsIdentity: String { uiLanguage + String(model.settingsRevision) }
    private var pageIdentity: String {
        if #available(iOS 26.0, *) { return settingsIdentity }
        return "page"
    }
    private var rootIdentity: String {
        if #available(iOS 26.0, *) { return "tabs" }
        return settingsIdentity
    }
    var body: some View {
        TabView(selection: $model.activeTab) {
            ResettableTabContent(revision: pageIdentity) { SearchView() }.tag(0).tabItem { Label { Text(ui("字典")) } icon: { Image(uiImage: DictionaryTabIcon.image) } }
            ResettableTabContent(revision: pageIdentity) { FavoritesView() }.tag(1).tabItem { Label(ui("生字本"), systemImage: "star") }
            ResettableTabContent(revision: pageIdentity) { DialectMapView() }.tag(2).tabItem { Label(ui("地圖"), systemImage: "map") }
            ResettableTabContent(revision: pageIdentity) { SettingsView() }.tag(4).tabItem { Label(ui("設定"), systemImage: "gearshape") }
        }
        .environmentObject(model.languageSelection)
        .sheet(item: $model.tableDetail) { TableInfoView(table: $0) }
        .id(rootIdentity)
        .environment(\.locale, Locale(identifier: uiLanguage == "hans" ? "zh-Hans" : "zh-Hant"))
        .dynamicTypeSize(AppTypography.size(fontSize))
        .tint(AppAccent.color)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .alert(ui("提示"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(ui("好")) { model.error = nil }
        } message: { Text(ui(model.error ?? "")) }
    }
}

struct ReadingView: View {
    @EnvironmentObject var model: AppModel
    let reading: Reading
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.tableDetail = model.table(named: reading.language) } label: { LanguageBadge(name: reading.language, table: model.table(named: reading.language)) }.buttonStyle(.plain)
            PronunciationView(raw: reading.pronunciation, table: model.table(named: reading.language)).font(.title3).foregroundStyle(.primary)
            SystemText(reading.characters).font(.title3)
            if !reading.note.isEmpty { SystemText(reading.note).font(.subheadline) }
        }.padding(.vertical, 6)
    }
}

struct SearchView: View {
    @AppStorage("colorScheme") private var palette = "atlas"
    @FocusState private var searchFocused: Bool
    @EnvironmentObject private var selector: LanguageSelectionState
    @State private var reference: ReferencePage?
    @State private var selectedCharacter = ""
    @State private var resultHeaderPinned = false
    private func submitQuery() {
        searchFocused = false
        Task { await model.search() }
    }

    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
            List {
                Section {
                    Picker(ui("查詢方式"), selection: $model.mode) {
                        ForEach(SearchMode.allCases) { Text(ui($0.rawValue)).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        TextField(ui("漢字、U+4E2D 或原始讀音"), text: $model.query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($searchFocused).onSubmit { submitQuery() }
                        Button(ui("查詢")) { submitQuery() }.disabled(model.searching)
                    }
                    LanguageSelectionPanel(tables: model.installed?.tables ?? [], names: Binding(get: { model.selectedLanguageNames }, set: { model.selectLanguages($0) }), state: selector, entryID: "dictionaryLanguageSelection", finished: { if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { submitQuery() } })
                }
                if model.searching { ProgressView(ui("查詢中…")) }
                if model.updating { ProgressView(ui(model.status)) }
                else if model.installed?.tables.isEmpty != false {
                    ContentUnavailableView(ui("先選擇字表"), systemImage: "arrow.down.circle", description: Text(ui("前往「設定 → 字表下載」恢復所需字表，或手動檢查上游更新。")))
                } else if model.results.isEmpty && !model.searching {
                    SystemText(ui("輸入查詢內容；若沒有結果，可切換語言或使用原始字形／讀音。"))
                }
                resultsSection(viewport: viewport.frame(in: .global))
                if model.hasMore { Button(ui("載入更多（每次 100 筆）")) { Task { await model.search(more: true) } }.disabled(model.searching) }
            }
            .listStyle(.plain)
            .toolbarBackground(resultHeaderPinned ? Color.black : Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackground(resultHeaderPinned ? .visible : .automatic, for: .navigationBar)
            .toolbarColorScheme(resultHeaderPinned ? .dark : nil, for: .navigationBar)
            .onChange(of: model.resultQuery) { _, _ in selectedCharacter = "" }
            .navigationTitle(ui("漢字音典"))
            .sheet(item: $reference) { CharacterReferenceDetail(page: $0) }
            }

        }
    }
    @ViewBuilder private func resultsSection(viewport: CGRect) -> some View {
                if !model.resultQuery.isEmpty {
                    let hasCharacters = model.resultMode == .character || model.resultMode == .note
                    let chars = model.resultCharacters
                    let current = chars.contains(selectedCharacter) ? selectedCharacter : chars.first ?? ""
                    Section {
                        if hasCharacters, !current.isEmpty {
                            CharacterReferenceHeader(character: current, show: { reference = $0 }, map: { model.openResultOnMap(current) })
                        }
                        if !model.resultQuery.isEmpty {
                            if hasCharacters { CharacterResultsView(current: current) }
                            else { HomophoneResultsView() }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            if model.resultMode == .note { NoteVariantPicker(query: model.resultQuery) { variant in
                                searchFocused = false
                                Task { await model.search(queryOverride: variant, modeOverride: .note) }
                            } }
                            if hasCharacters && !chars.isEmpty {
                                ScrollView(.horizontal) {
                                    HStack {
                                        ForEach(chars, id: \.self) { char in
                                            Button(char) { selectedCharacter = char }.buttonStyle(.bordered).tint(char == current ? AppAccent.color : .gray)
                                        }
                                    }
                                }
                            }
                        }.textCase(nil).frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.vertical, 4).background(Color(uiColor: .systemBackground))
                         .background {
                             GeometryReader { geometry in
                                 let top = max(0, geometry.frame(in: .global).minY - viewport.minY)
                                 if top <= 16 { Color.black.frame(width: viewport.width, height: top).offset(x: viewport.minX - geometry.frame(in: .global).minX, y: -top) }
                             }.allowsHitTesting(false)
                         }
                         // List hosts its pinned headers separately; use screen coordinates across those hosts.
                         .onGeometryChange(for: Bool.self) { geometry in
                             geometry.frame(in: .global).minY <= viewport.minY + 16
                         } action: { resultHeaderPinned = $0 }
                         .onDisappear { resultHeaderPinned = false }
                         .zIndex(1)
                    }
                }
    }

}

struct LanguageView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var filter = ""
    @State private var grouping: TableGrouping = .atlas
    var body: some View {
        NavigationStack {
            VStack {
                Picker(ui("分類方式"), selection: $grouping) {
                    ForEach(TableGrouping.allCases) { Text(ui($0.displayName)).tag($0) }
                }.pickerStyle(.menu).padding(.horizontal)
                Button(ui("全部已下載語言")) { model.language = ""; model.selectedLanguages = nil; dismiss() }
                LanguageGroupList(tables: (model.installed?.tables ?? []).filter {
                    filter.isEmpty || ([$0.name, $0.fullName] + $0.atlas + $0.dictionary + $0.administrative).contains { InterfaceLanguage.matches($0, filter) }
                }, grouping: grouping, depth: 0) { names, title in model.language = title; model.selectedLanguages = names; dismiss() }
                if model.languages.isEmpty { Text(ui("尚未下載字表，請先到「字表」選擇字表。")).padding() }
            }.searchable(text: $filter, prompt: ui("搜尋語言或分區")).navigationTitle(ui("選擇語言"))
                .toolbar { Button(ui("完成")) { dismiss() } }
        }
    }
}

