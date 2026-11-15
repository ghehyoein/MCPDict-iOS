import SwiftUI

struct DeletedCollection: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var notebook: NotebookArchive?
    var schemes: [CustomLanguageSchemes.Scheme]?
}
final class RecentDeletions: ObservableObject {
    static let shared = RecentDeletions()
    @Published private(set) var items: [DeletedCollection] = []
    private let url: URL
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("recent-deletions.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url) { items = (try? JSONDecoder().decode([DeletedCollection].self, from: data)) ?? [] }
        try? prune()
    }
    private func write(_ value: [DeletedCollection]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        items = value
    }
    func prune() throws { try write(items.filter { Date().timeIntervalSince($0.date) < 30 * 86400 }) }
    func add(_ item: DeletedCollection) throws { try write([item] + items.filter { Date().timeIntervalSince($0.date) < 30 * 86400 }) }
    func remove(_ id: UUID) throws { try write(items.filter { $0.id != id }) }
    func capture(before: NotebookArchive, after: NotebookArchive) throws {
        let afterBooks = Set(after.books.map(\.id))
        let memberships = Dictionary(uniqueKeysWithValues: after.entries.map { ($0.id, $0.membership) })
        var removed = NotebookArchive(); removed.books = []; removed.entries = []; removed.selected = []
        for entry in before.entries {
            let lost = entry.membership.subtracting(memberships[entry.id] ?? [])
            if !lost.isEmpty { var copy = entry; copy.books = lost; removed.entries.append(copy) }
        }
        let required = removed.entries.reduce(into: Set<UUID>()) { $0.formUnion($1.membership) }
        removed.books = before.books.filter { !afterBooks.contains($0.id) || required.contains($0.id) }
        guard !removed.books.isEmpty || !removed.entries.isEmpty else { return }
        try add(DeletedCollection(title: "生字本", notebook: removed))
    }
}
struct RecentDeletionsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var store = RecentDeletions.shared
    @State private var error: String?
    var body: some View {
        List {
            ForEach(store.items) { item in
                VStack(alignment: .leading) {
                    Text(ui(item.title)); Text(item.date, style: .date).foregroundStyle(.secondary)
                    if let book = item.notebook { Text(book.books.map(\.title).joined(separator: "、")) }
                    if let schemes = item.schemes { Text(schemes.map(\.name).joined(separator: "、")) }
                    HStack {
                        Button(ui("還原")) { restore(item) }
                        Spacer()
                        Button(ui("永久刪除"), role: .destructive) { do { try store.remove(item.id) } catch { self.error = error.localizedDescription } }
                    }.buttonStyle(.borderless)
                }
            }
        }.navigationTitle(ui("最近刪除"))
            .onAppear { try? store.prune() }
            .alert(ui("最近刪除"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(ui("好")) {} } message: { Text(error ?? "") }
    }
    private func restore(_ item: DeletedCollection) {
        do {
            if let notebook = item.notebook { try model.importNotebook(JSONEncoder().encode(notebook)) }
            if let schemes = item.schemes {
                var source = CustomLanguageSchemes(); source.schemes = schemes
                model.languageSelection.custom = try CustomSchemeArchive(source).merging(into: model.languageSelection.custom)
            }
            try store.remove(item.id)
        } catch { self.error = error.localizedDescription }
    }
}
