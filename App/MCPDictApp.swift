import SwiftUI

enum AppConfiguration {
    static let manifestURL = "https://github.com/ghehyoein/MCPDict-iOS/releases/download/data-latest/manifest.json"
}

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
    let updater: DataUpdater
    @Published var installed: DataManifest?
    @Published var available: DataManifest?
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
        UserDefaults.standard.register(defaults: ["manifestURL": AppConfiguration.manifestURL])
        let repository = DictionaryRepository()
        self.repository = repository
        updater = DataUpdater(repository: repository)
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
            installed = try await updater.restore()
            languages = try await repository.languages()
            status = installed.map { "已安裝 \($0.version)" } ?? "請先設定更新網址，再下載詞典"
        } catch { self.error = error.localizedDescription }
        if UserDefaults.standard.bool(forKey: "autoCheck"), let url = UserDefaults.standard.string(forKey: "manifestURL"), !url.isEmpty {
            await check(url)
        }
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
    func check(_ url: String) async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        available = nil
        status = "正在檢查 GitHub 資料版本…"
        do {
            let manifest = try await updater.check(url)
            if manifest.database.sha256 == installed?.database.sha256 { status = "已是此更新源的最新資料" }
            else { available = manifest; status = "發現資料版本 \(manifest.version)" }
        } catch { status = "檢查失敗，現有資料仍可使用"; self.error = error.localizedDescription }
    }
    func download() {
        guard !updating, let manifest = available else { return }
        updating = true
        status = "正在下載及校驗，請保持 App 開啟…"
        updateTask = Task {
            defer { updating = false; updateTask = nil }
            do {
                try await updater.install(manifest)
                installed = manifest
                available = nil
                generation += 1
                results = []; hasMore = false; lastSearch = nil
                languages = try await repository.languages()
                if !languages.contains(language) { language = "" }
                status = "更新完成，可離線查詢"
            } catch is CancellationError { status = "已取消，現有資料仍可使用" }
            catch { status = "更新失敗，現有資料仍可使用"; self.error = error.localizedDescription }
        }
    }
    func cancelDownload() { updateTask?.cancel() }
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
    var body: some View {
        TabView {
            SearchView().tabItem { Label("字典", systemImage: "character.book.closed") }
            FavoritesView().tabItem { Label("生字本", systemImage: "star") }
            DataView().tabItem { Label("資料", systemImage: "arrow.down.circle") }
        }
        .tint(.teal)
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
                if model.installed == nil {
                    ContentUnavailableView("先下載詞典資料", systemImage: "arrow.down.circle", description: Text("前往「資料」設定 GitHub 更新源。下載完成後可離線使用。"))
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
    var body: some View {
        NavigationStack {
            List {
                Button("全部語言") { model.language = ""; dismiss() }
                ForEach(model.languages.filter { filter.isEmpty || $0.localizedStandardContains(filter) }, id: \.self) { name in
                    Button(name) { model.language = name; dismiss() }
                }
            }.searchable(text: $filter, prompt: "搜尋語言名稱").navigationTitle("選擇語言")
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

struct DataView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("manifestURL") private var manifestURL = AppConfiguration.manifestURL
    @AppStorage("autoCheck") private var autoCheck = false
    var body: some View {
        NavigationStack {
            Form {
                Section("目前資料") {
                    LabeledContent("版本", value: model.installed?.version ?? "尚未安裝")
                    if let commit = model.installed?.sourceCommit { LabeledContent("上游提交", value: String(commit.prefix(12))) }
                    Text(model.status)
                    if model.updating { ProgressView() }
                }
                Section {
                    TextField("manifest.json 的 HTTPS 網址", text: $manifestURL, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .disabled(model.updating)
                        .onChange(of: manifestURL) { _, _ in model.available = nil }
                    Toggle("啟動時檢查更新", isOn: $autoCheck)
                    Button("檢查更新") { Task { await model.check(manifestURL) } }.disabled(model.updating || manifestURL.isEmpty)
                    if let manifest = model.available {
                        Text("可下載：\(manifest.version) · \(ByteCountFormatter.string(fromByteCount: manifest.database.size, countStyle: .file))")
                        Button("更新資料（下載）") { model.download() }.disabled(model.updating)
                    }
                    if model.updating { Button("取消下載", role: .cancel) { model.cancelDownload() } }
                } header: { Text("GitHub 資料更新")
                } footer: { Text("更新源由配套 GitHub Actions 直接從 osfans/MCPDict 字表構建，完全不使用 APK。請填寫你部署後的 manifest 網址。初版需要保持前台下載，無固定時刻的背景更新。") }
                Section("關於試作版") {
                    Link("上游字表與來源說明", destination: URL(string: "https://github.com/osfans/MCPDict")!)
                    Text("0.1 · 原生 SwiftUI / SQLite FTS5。資料與收藏分開儲存；更新驗證大小、SHA-256、資料表和查字能力。")
                    Text("尚未移植：離線地圖、矩陣、猜字／猜方言、形碼檢索、OpenCC、音標轉換與擴展字體。")
                }
            }.navigationTitle("詞典資料")
        }
    }
}
