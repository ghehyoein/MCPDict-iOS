import SwiftUI

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
    private var categories: Set<NotebookCategory> {
        Set(stored.split(separator: "|").compactMap { NotebookCategory(rawValue: String($0)) })
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        ForEach(NotebookCategory.allCases, id: \.self) { kind in
                            Button {
                                var active = categories
                                if !active.insert(kind).inserted { active.remove(kind) }
                                stored = NotebookCategory.allCases.filter(active.contains).map(\.rawValue).joined(separator: "|")
                            } label: {
                                Label(ui(kind.rawValue), systemImage: categories.contains(kind) ? "checkmark.square.fill" : "square")
                            }.buttonStyle(.borderless)
                        }
                    }
                    if selecting {
                        HStack {
                            Button(ui("全選")) { selection = Set(model.favorites.map(\.id)) }
                            Spacer()
                            Text(ui("已選 ") + String(selection.count))
                            Button(ui("刪除"), role: .destructive) { remove(selection) }.disabled(selection.isEmpty)
                        }.buttonStyle(.borderless)
                    }
                }
                if model.favorites.isEmpty { Text(ui("點擊查詢結果旁的星號，即可加入生字本。")) }
                ForEach(NotebookGroup.make(model.favorites, categories: categories)) { group in
                    Section {
                        ForEach(group.entries) { saved in
                            HStack(alignment: .top) {
                                if selecting {
                                    Button {
                                        if !selection.insert(saved.id).inserted { selection.remove(saved.id) }
                                    } label: {
                                        Image(systemName: selection.contains(saved.id) ? "checkmark.square.fill" : "square").padding(8)
                                    }.buttonStyle(.borderless).accessibilityLabel(ui("選擇") + saved.reading.characters)
                                }
                                VStack(alignment: .leading) {
                                    ReadingView(reading: saved.reading)
                                    TextField(ui("個人筆記"), text: Binding(get: { saved.note }, set: { note in
                                        if let i = model.favorites.firstIndex(where: { $0.id == saved.id }) {
                                            model.favorites[i].note = note; model.persistFavorites()
                                        }
                                    }), axis: .vertical)
                                }
                            }
                        }.onDelete { indices in remove(Set(indices.map { group.entries[$0].id })) }
                    } header: { if !group.title.isEmpty { Text(verbatim: group.title).textCase(nil) } }
                }
            }.navigationTitle(ui("生字本")).toolbar {
                Button(ui(selecting ? "完成" : "多選")) { selecting.toggle(); selection = [] }
            }
        }
    }
    private func remove(_ ids: Set<UUID>) {
        model.deleteFavorites(IndexSet(model.favorites.indices.filter { ids.contains(model.favorites[$0].id) }))
        selection.formIntersection(Set(model.favorites.map(\.id)))
    }
}
