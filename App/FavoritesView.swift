import SwiftUI
import UniformTypeIdentifiers

enum NotebookCategory: String, CaseIterable {
    case language = "語言", pronunciation = "發音", character = "單字", hidden = "隱藏"
    func keys(_ reading: Reading) -> [String] {
        switch self {
        case .language: return [reading.language]
        case .pronunciation: return [reading.pronunciation]
        case .character: return CharacterResults.characters(reading.characters)
        case .hidden: return []
        }
    }
}

// Each classification is an independent view of the same saved IDs.
struct NotebookGroup: Identifiable {
    let id: String
    let title: String
    let entries: [SavedReading]
    static func make(_ entries: [SavedReading], categories: Set<NotebookCategory>) -> [Self] {
        if categories.isEmpty || categories == [.hidden] { return [Self(id: "all", title: "", entries: entries)] }
        return NotebookCategory.allCases.filter(categories.contains).flatMap { category in
            var groups = [String: [SavedReading]]()
            for item in entries {
                for key in category.keys(item.reading) { groups[key, default: []].append(item) }
            }
            return groups.keys.sorted().map { key in
                Self(id: category.rawValue + "\u{0}" + key, title: ui(category.rawValue) + " · " + key, entries: groups[key]!)
            }
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("notebookCategory") private var stored = ""
    @State private var selectedKey = ""
    @State private var selection = Set<UUID>()
    @State private var selecting = false
    @State private var showBooks = false
    @State private var exporting = false
    @State private var importing = false
    @State private var transferMessage: String?
    private var category: NotebookCategory { NotebookCategory(rawValue: stored) ?? .hidden }
    private var keys: [String] { Set(model.visibleFavorites.flatMap { category.keys($0.reading) }).sorted() }
    private var currentKey: String { keys.contains(selectedKey) ? selectedKey : keys.first ?? "" }
    private var shown: [SavedReading] {
        let entries = model.visibleFavorites
        guard category != .hidden else { return entries }
        let key = currentKey
        return entries.filter { category.keys($0.reading).contains(key) }
    }
    private var groups: [NotebookGroup] { [NotebookGroup(id: "current", title: "", entries: shown)] }
    @ViewBuilder private var choiceBar: some View {
        if category != .hidden && !keys.isEmpty {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(keys, id: \.self) { key in
                        Button {
                            selectedKey = key
                            if category == .language { model.tableDetail = model.table(named: key) }
                        } label: {
                            if category == .language { LanguageBadge(name: key, table: model.table(named: key)) }
                            else { Text(key) }
                        }.buttonStyle(.bordered).tint(key == currentKey ? AppAccent.color : .gray)
                    }
                }
            }.accessibilityIdentifier("notebookChoiceBar")
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showBooks = true } label: {
                        HStack {
                            Text(ui("生字表")); Spacer()
                            Text(model.notebook.books.filter { model.notebook.selected.contains($0.id) }.map(\.title).joined(separator: "、"))
                                .lineLimit(1).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                        }
                    }.accessibilityIdentifier("chooseNotebooks")
                    Picker(ui("生字本分類"), selection: $stored) {
                        ForEach(NotebookCategory.allCases, id: \.self) { Text(ui($0.rawValue)).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("notebookCategory")
                    choiceBar
                    if selecting {
                        HStack {
                            Button(ui("全選")) { selection = Set(model.visibleFavorites.map(\.id)) }
                            Spacer()
                            Text(ui("已選 ") + String(selection.count))
                            Menu(ui("加入生字表")) {
                                ForEach(model.notebook.books) { book in Button(book.title) { model.addFavorites(selection, to: book.id) } }
                            }.disabled(selection.isEmpty)
                            Button(ui("刪除"), role: .destructive) { remove(selection) }.disabled(selection.isEmpty)
                        }.buttonStyle(.borderless)
                    }
                }
                if model.notebook.books.isEmpty { Text(ui("請先新建生字表。")) }
                else if model.notebook.selected.isEmpty { Text(ui("請選擇要查看的生字表。")) }
                else if model.visibleFavorites.isEmpty { Text(ui("點擊查詢結果旁的星號，即可加入所選生字表。")) }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.entries) { saved in
                            HStack(alignment: .top) {
                                if selecting {
                                    Button {
                                        if !selection.insert(saved.id).inserted { selection.remove(saved.id) }
                                    } label: {
                                        Image(systemName: selection.contains(saved.id) ? "checkmark.square.fill" : "square").contentTransition(.identity).transaction { $0.animation = nil; $0.disablesAnimations = true }.padding(8)
                                    }.buttonStyle(.borderless).accessibilityLabel(ui("選擇") + saved.reading.characters)
                                }
                                VStack(alignment: .leading) {
                                    ReadingView(reading: saved.reading)
                                    TextField(ui("個人筆記"), text: Binding(get: { saved.note }, set: { note in
                                        model.setNote(note, for: saved.id)
                                    }), axis: .vertical)
                                }
                            }
                        }.onDelete { indices in remove(Set(indices.map { group.entries[$0].id })) }
                    } header: { if !group.title.isEmpty { Text(verbatim: group.title).textCase(nil) } }
                }
            }
            .fileExporter(isPresented: $exporting, document: NotebookTextDocument(archive: model.notebook.exportingSelected()), contentType: .plainText, defaultFilename: "漢字音典生字本") { result in
                if case .failure(let error) = result { model.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
                do {
                    let url = try result.get()
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    try model.importNotebook(Data(contentsOf: url))
                    transferMessage = ui("已合併匯入生字表，原有內容已保留。")
                } catch { model.error = error.localizedDescription }
            }
            .alert(ui("生字本匯入"), isPresented: Binding(get: { transferMessage != nil }, set: { if !$0 { transferMessage = nil } })) {
                Button(ui("好")) { transferMessage = nil }
            } message: { Text(transferMessage ?? "") }
            .onAppear {
                if stored.isEmpty {
                    let old = UserDefaults.standard.string(forKey: "notebookCategories") ?? ""
                    stored = old.split(separator: "|").compactMap { NotebookCategory(rawValue: String($0)) }.first?.rawValue ?? NotebookCategory.hidden.rawValue
                }
            }
            .onChange(of: stored) { _, _ in selectedKey = "" }
            .sheet(isPresented: $showBooks) { BookPicker() }
             .onChange(of: model.notebook.selected) { _, _ in selection = [] }
             .navigationTitle(ui("生字本")).toolbar {
                Menu {
                    Button(ui("匯出所選生字表")) { exporting = true }.disabled(model.notebook.selected.isEmpty)
                    Button(ui("匯入生字表")) { importing = true }
                } label: { Image(systemName: "square.and.arrow.up.on.square") }.accessibilityLabel(ui("匯入及匯出"))
                Button(ui(selecting ? "完成" : "多選")) { selecting.toggle(); selection = [] }
            }
        }
    }
    private func remove(_ ids: Set<UUID>) {
        model.removeVisibleFavorites(ids)
        selection.formIntersection(Set(model.visibleFavorites.map(\.id)))
    }
}
