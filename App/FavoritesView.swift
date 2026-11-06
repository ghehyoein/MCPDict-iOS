import SwiftUI
import UniformTypeIdentifiers

enum NotebookCategory: String, CaseIterable {
    case language = "語言", pronunciation = "發音", character = "單字"
    func keys(_ reading: Reading) -> [String] {
        switch self {
        case .language: return [reading.language]
        case .pronunciation: return [reading.pronunciation]
        case .character: return CharacterResults.characters(reading.characters)
        }
    }
}

// Each classification is an independent view of the same saved IDs.
struct NotebookGroup: Identifiable {
    let id: String
    let title: String
    let entries: [SavedReading]
    static func make(_ entries: [SavedReading], categories: Set<NotebookCategory>) -> [Self] {
        if categories.isEmpty { return [Self(id: "all", title: "", entries: entries)] }
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
    @AppStorage("notebookCategories") private var stored = ""
    @State private var selection = Set<UUID>()
    @State private var selecting = false
    @State private var showBooks = false
    @State private var exporting = false
    @State private var importing = false
    @State private var transferMessage: String?
    private var categories: Set<NotebookCategory> {
        Set(stored.split(separator: "|").compactMap { NotebookCategory(rawValue: String($0)) })
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
                    HStack {
                        ForEach(NotebookCategory.allCases, id: \.self) { kind in
                            Button {
                                var active = categories
                                if !active.insert(kind).inserted { active.remove(kind) }
                                stored = NotebookCategory.allCases.filter(active.contains).map(\.rawValue).joined(separator: "|")
                            } label: {
                                Label(ui(kind.rawValue), systemImage: categories.contains(kind) ? "checkmark.square.fill" : "square").contentTransition(.identity).transaction { $0.animation = nil; $0.disablesAnimations = true }
                            }.buttonStyle(.borderless)
                        }
                    }
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
                ForEach(NotebookGroup.make(model.visibleFavorites, categories: categories)) { group in
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
            .fileExporter(isPresented: $exporting, document: NotebookTextDocument(archive: model.notebook), contentType: .json, defaultFilename: "漢字音典生字本") { result in
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
            .sheet(isPresented: $showBooks) { BookPicker() }
             .onChange(of: model.notebook.selected) { _, _ in selection = [] }
             .navigationTitle(ui("生字本")).toolbar {
                Menu {
                    Button(ui("匯出全部生字表 · JSON 純文字")) { exporting = true }
                    Button(ui("匯入生字表 · JSON 純文字")) { importing = true }
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
