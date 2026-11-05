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
    @Published var favorites = [SavedReading]()
    @Published var query = "中"
    @Published var mode: SearchMode = .character
    @Published var language = ""
    @Published var error: String?
    @Published var status = "尚未下載詞典"
    @Published var updating = false
    @Published var searching = false
    @Published var hasMore = false
    private var lastSearch: (String, SearchMode, String)?
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
        do {
            if FileManager.default.fileExists(atPath: favoritesURL.path) {
                favorites = try JSONDecoder().decode([SavedReading].self, from: Data(contentsOf: favoritesURL))
            }
        } catch { self.error = "收藏讀取失敗：\(error.localizedDescription)" }
        do {
            installed = try await tableStore.restore()
            languages = try await repository.languages()
            status = "已下載 \(installed?.tables.count ?? 0) 份字表"
        } catch { self.error = error.localizedDescription }
    }
    func search(more: Bool = false) async {
        guard !searching else { return }
        searching = true
        defer { searching = false }
        let token = generation
        let request = more ? (lastSearch ?? (query, mode, language)) : (query, mode, language)
        do {
            let found = try await repository.search(request.0, mode: request.1, language: request.2, offset: more ? results.count : 0)
            guard token == generation else { return }
            if more { results += found } else { results = found }
            lastSearch = request
            hasMore = found.count == 100
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
    func applyTables(_ selection: Set<String>) {
        guard !updating, let catalog else { return }
        updating = true
        status = "正在處理所選字表，請保持 App 開啟…"
        updateTask = Task {
            defer { updating = false; updateTask = nil }
            do {
                installed = try await tableStore.apply(catalog, selected: selection) { message in
                    await MainActor.run { self.status = message }
                }
                generation += 1
                results = []; hasMore = false; lastSearch = nil
                languages = try await repository.languages()
                if !languages.contains(language) { language = "" }
                status = "已下載 \(installed?.tables.count ?? 0) 份字表；查詢只覆蓋已下載資料"
            } catch is CancellationError { status = "已取消，現有資料仍可使用" }
            catch { status = "更新失敗，現有資料仍可使用"; self.error = error.localizedDescription }
        }
    }
    func cancelDownload() { updateTask?.cancel() }
    func updateInstalledTables() async {
        await loadCatalog()
        guard let catalog, !updating else { return }
        let ids = Set(installed?.tables.map(\.id) ?? [])
        guard ids.isSubset(of: Set(catalog.tables.map(\.id))) else {
            error = "部分已下載字表已從上游目錄移除，請在資料頁確認選擇後再套用。"
            return
        }
        applyTables(ids)
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
    var body: some View {
        TabView {
            SearchView().tabItem { Label("字典", systemImage: "character.book.closed") }
            FavoritesView().tabItem { Label("生字本", systemImage: "star") }
            DataView().tabItem { Label("資料", systemImage: "arrow.down.circle") }
            SettingsView().tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tint(.teal)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .alert("提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct ReadingView: View {
    let reading: Reading
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reading.language).font(.caption).foregroundStyle(.secondary)
            Text(reading.pronunciation).font(.title3.bold()).foregroundStyle(.teal)
            Text(reading.characters).font(.title3).textSelection(.enabled)
            if !reading.note.isEmpty { Text(reading.note).font(.subheadline).textSelection(.enabled) }
        }.padding(.vertical, 6)
    }
}

struct SearchView: View {
    @EnvironmentObject var model: AppModel
    @State private var showLanguages = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("查詢方式", selection: $model.mode) {
                        ForEach(SearchMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        TextField("漢字、U+4E2D 或原始讀音", text: $model.query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onSubmit { Task { await model.search() } }
                        Button("查詢") { Task { await model.search() } }.disabled(model.searching)
                    }
                    Button { showLanguages = true } label: {
                        LabeledContent("語言", value: model.language.isEmpty ? "全部語言" : model.language)
                    }
                } footer: { Text("漢字按字分別匹配；讀音、註釋使用原始資料的 FTS 詞項檢索。本版尚未加入繁簡、異體字與拼音轉換。") }
                if model.searching { ProgressView("查詢中…") }
                if model.installed?.tables.isEmpty != false {
                    ContentUnavailableView("先選擇字表", systemImage: "arrow.down.circle", description: Text("本版不內置字表。前往「資料」按分區或名稱下載，完成後可離線使用。"))
                } else if model.results.isEmpty && !model.searching {
                    Text("輸入查詢內容；若沒有結果，可切換語言或使用原始字形／讀音。")
                }
                ForEach(model.results) { reading in
                    ReadingView(reading: reading)
                        .swipeActions { Button("收藏", systemImage: "star") { model.save(reading) }.tint(.orange) }
                        .contextMenu { Button("加入生字本", systemImage: "star") { model.save(reading) } }
                }
                if model.hasMore { Button("載入更多（每次 100 筆）") { Task { await model.search(more: true) } }.disabled(model.searching) }
            }
            .navigationTitle("漢字音典")
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
                Picker("分類方式", selection: $grouping) {
                    ForEach(TableGrouping.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).padding(.horizontal)
                Button("全部已下載語言") { model.language = ""; dismiss() }
                LanguageGroupList(tables: (model.installed?.tables ?? []).filter {
                    filter.isEmpty || ([$0.name, $0.fullName] + $0.atlas + $0.dictionary + $0.administrative).contains { $0.localizedStandardContains(filter) }
                }, grouping: grouping, depth: 0) { name in model.language = name; dismiss() }
                if model.languages.isEmpty { Text("尚未下載字表，請先到「資料」選擇字表。").padding() }
            }.searchable(text: $filter, prompt: "搜尋語言或分區").navigationTitle("選擇語言")
                .toolbar { Button("完成") { dismiss() } }
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                if model.favorites.isEmpty { Text("在查詢結果上向左滑動，即可收藏。") }
                ForEach($model.favorites) { $saved in
                    VStack(alignment: .leading) {
                        ReadingView(reading: saved.reading)
                        TextField("個人筆記", text: $saved.note, axis: .vertical)
                            .onChange(of: saved.note) { _, _ in model.persistFavorites() }
                    }
                }.onDelete(perform: model.deleteFavorites)
            }.navigationTitle("生字本").toolbar { EditButton() }
        }
    }
}

