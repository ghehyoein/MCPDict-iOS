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
}

@MainActor
final class AppModel: ObservableObject {
    let repository: DictionaryRepository
    let tableStore: TableStore
    @Published var installed: TableInstallation?
    @Published var catalog: TableCatalog?
    @Published var languages = [String]()
    @Published var results = [Reading]()
    @Published var resultMode: SearchMode = .character
    @Published var resultQuery = ""
    @Published var downloading = false
    @Published var favorites = [SavedReading]()
    @Published var query = "中"
    @Published var mode: SearchMode = .character
    @Published var language = ""
    @Published var selectedLanguages: [String]?
    @Published var error: String?
    @Published var status = "尚未下載詞典"
    @Published var updating = false
    @Published var searching = false
    @Published var hasMore = false
    private var lastSearch: (String, SearchMode, String, [String]?)?
    private var generation = 0
    private var started = false
    private var updateTask: Task<Void, Never>?
    private let favoritesURL: URL
    init() {
        let repository = DictionaryRepository()
        self.repository = repository
        tableStore = TableStore(repository: repository)
        favoritesURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("favorites.json")
    }
    func start() async {
        guard !started else { return }; started = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-fixture") {
            UserDefaults.standard.set("hant", forKey: "uiLanguage")
            catalog = UITestFixtures.catalog
            installed = TableInstallation(catalogVersion: "ui-test", tables: UITestFixtures.catalog.tables, databaseFile: nil)
            languages = UITestFixtures.catalog.tables.map(\.name)
            status = ""
            return
        }
        #endif
        // Remove the retired optional map-provider setting on upgrade.
        UserDefaults.standard.removeObject(forKey: "mapTilerKey")
        do {
            if FileManager.default.fileExists(atPath: favoritesURL.path) {
                favorites = try JSONDecoder().decode([SavedReading].self, from: Data(contentsOf: favoritesURL))
            }
        } catch { self.error = "收藏讀取失敗：\(error.localizedDescription)" }
        do {
            installed = try await tableStore.restore()
            catalog = await tableStore.cachedCatalog()
            languages = try await repository.languages()
            status = "已下載 \(installed?.tables.count ?? 0) 份字表"
        } catch { self.error = error.localizedDescription }
    }
    func search(more: Bool = false) async {
        guard !searching else { return }
        searching = true
        defer { searching = false }
        let token = generation
        let request = more ? (lastSearch ?? (query, mode, language, selectedLanguages)) : (query, mode, language, selectedLanguages)
        do {
            let found: [Reading]
            if request.1 == .character { found = try await repository.searchAllCharacters(request.0, language: request.2, languages: request.3) }
            else { found = try await repository.search(request.0, mode: request.1, language: request.2, offset: more ? results.count : 0, languages: request.3) }
            guard token == generation else { return }
            if more { results += found } else { results = found }
            lastSearch = request
            resultMode = request.1; resultQuery = request.0
            hasMore = request.1 != .character && found.count == 100
        } catch { self.error = error.localizedDescription }
    }
    func loadCatalog() async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        status = "正在取得字表目錄…"
        do {
            catalog = try await tableStore.catalog()
            status = "目錄已更新 · 已下載 \(installed?.tables.count ?? 0) 份字表"
        } catch { status = "檢查失敗，現有資料仍可使用"; self.error = error.localizedDescription }
    }
    func downloadTables(_ selection: Set<String>) {
        guard !updating, !selection.isEmpty, let catalog else { return }
        updating = true; downloading = true
        status = "正在下載字表…"
        updateTask = Task {
            defer { updating = false; downloading = false; updateTask = nil }
            do {
                let result = try await tableStore.download(catalog, selected: selection) { message in
                    await MainActor.run { self.status = message }
                }
                installed = result.installation
                try await refreshAfterTables()
                if let failure = result.failure { status = "已保留完成的字表"; error = failure }
                else { status = result.cancelled ? "已取消，已保留完成的字表" : "下載完成" }
            } catch { status = "操作未完成，原有字表仍可使用"; self.error = error.localizedDescription }
        }
    }
    func removeTables(_ selection: Set<String>) {
        guard !updating, !selection.isEmpty else { return }
        updating = true
        status = "正在移除字表…"
        updateTask = Task {
            defer { updating = false; updateTask = nil }
            do {
                installed = try await tableStore.remove(selected: selection)
                try await refreshAfterTables()
                status = "移除完成"
            } catch { self.error = error.localizedDescription }
        }
    }
    private func refreshAfterTables() async throws {
        generation += 1
        results = []; hasMore = false; lastSearch = nil
        languages = try await repository.languages()
        if let selection = selectedLanguages {
            selectedLanguages = selection.filter { languages.contains($0) }
            if selectedLanguages?.isEmpty == true { selectedLanguages = nil; language = "" }
        } else if !languages.contains(language) { language = "" }
    }
    func cancelDownload() { updateTask?.cancel(); status = "正在取消並保存已完成的字表…" }
    func table(named name: String) -> TablePackage? {
        catalog?.tables.first { $0.name == name } ?? installed?.tables.first { $0.name == name }
    }
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
    func save(_ reading: Reading) {
        guard !favorites.contains(where: { $0.reading.characters == reading.characters && $0.reading.language == reading.language && $0.reading.pronunciation == reading.pronunciation && $0.reading.note == reading.note }) else { return }
        let old = favorites
        favorites.append(SavedReading(reading: reading))
        if !persistFavorites() { favorites = old }
    }
    func deleteFavorites(_ offsets: IndexSet) {
        let old = favorites
        favorites.remove(atOffsets: offsets)
        if !persistFavorites() { favorites = old }
    }
    @discardableResult func persistFavorites() -> Bool {
        do {
            try FileManager.default.createDirectory(at: favoritesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(favorites).write(to: favoritesURL, options: .atomic)
            return true
        } catch { self.error = "收藏儲存失敗：\(error.localizedDescription)"; return false }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("uiLanguage") private var uiLanguage = "hant"
    @State private var tab = 0
    @AppStorage("fontSize") private var fontSize = 17.0
    var body: some View {
        TabView(selection: $tab) {
            SearchView().tag(0).tabItem { Label(ui("字典"), systemImage: "character.book.closed") }
            FavoritesView().tag(1).tabItem { Label(ui("生字本"), systemImage: "star") }
            DialectMapView().tag(2).tabItem { Label(ui("地圖"), systemImage: "map") }
            DataView().tag(3).tabItem { Label(ui("字表"), systemImage: "arrow.down.circle") }
            SettingsView().tag(4).tabItem { Label(ui("設定"), systemImage: "gearshape") }
        }
        .id(uiLanguage)
        .environment(\.locale, Locale(identifier: uiLanguage == "hans" ? "zh-Hans" : "zh-Hant"))
        .dynamicTypeSize(AppTypography.size(fontSize))
        .tint(.teal)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .alert(ui("提示"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(ui("好")) { model.error = nil }
        } message: { Text(ui(model.error ?? "")) }
    }
}

struct ReadingView: View {
    @EnvironmentObject var model: AppModel
    @State private var information: TablePackage?
    let reading: Reading
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { information = model.table(named: reading.language) } label: { LanguageBadge(name: reading.language, table: model.table(named: reading.language)) }.buttonStyle(.plain)
            PronunciationView(raw: reading.pronunciation, table: model.table(named: reading.language)).font(.title3).foregroundStyle(.primary)
            Text(reading.characters).font(.title3).textSelection(.enabled)
            if !reading.note.isEmpty { Text(reading.note).font(.subheadline).textSelection(.enabled) }
        }.padding(.vertical, 6).sheet(item: $information) { TableInfoView(table: $0) }
    }
}

struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @State private var showLanguages = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(ui("查詢方式"), selection: $model.mode) {
                        ForEach(SearchMode.allCases) { Text(ui($0.rawValue)).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        TextField(ui("漢字、U+4E2D 或原始讀音"), text: $model.query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit { Task { await model.search() } }
                        Button(ui("查詢")) { Task { await model.search() } }.disabled(model.searching)
                    }
                    Button { showLanguages = true } label: {
                        LabeledContent(ui("語言"), value: model.language.isEmpty ? ui("全部語言") : model.language)
                    }
                } footer: { Text(ui("讀音搜尋：先顯示開頭相同的讀音，再顯示包含輸入內容的讀音。搜尋使用字表原始音標。")) }
                if model.searching { ProgressView(ui("查詢中…")) }
                if model.installed?.tables.isEmpty != false {
                    ContentUnavailableView(ui("先選擇字表"), systemImage: "arrow.down.circle", description: Text(ui("本版不內置字表。前往「字表」按分區或名稱下載，完成後可離線使用。")))
                } else if model.results.isEmpty && !model.searching {
                    Text(ui("輸入查詢內容；若沒有結果，可切換語言或使用原始字形／讀音。"))
                }
                if model.resultMode == .character && !model.resultQuery.isEmpty {
                    CharacterResultsView()
                } else {
                    ForEach(model.results) { reading in
                        ReadingView(reading: reading)
                            .swipeActions { Button(ui("收藏"), systemImage: "star") { model.save(reading) }.tint(.orange) }
                            .contextMenu { Button(ui("加入生字本"), systemImage: "star") { model.save(reading) } }
                    }
                }
                if model.hasMore { Button(ui("載入更多（每次 100 筆）")) { Task { await model.search(more: true) } }.disabled(model.searching) }
            }
            .navigationTitle(ui("漢字音典"))
            .sheet(isPresented: $showLanguages) { LanguageView() }
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
                    ForEach(TableGrouping.allCases) { Text(ui($0.rawValue)).tag($0) }
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

struct FavoritesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                if model.favorites.isEmpty { Text(ui("在查詢結果上向左滑動，即可收藏。")) }
                ForEach($model.favorites) { $saved in
                    VStack(alignment: .leading) {
                        ReadingView(reading: saved.reading)
                        TextField(ui("個人筆記"), text: $saved.note, axis: .vertical)
                            .onChange(of: saved.note) { _, _ in model.persistFavorites() }
                    }
                }.onDelete(perform: model.deleteFavorites)
            }.navigationTitle(ui("生字本")).toolbar { EditButton() }
        }
    }
}

