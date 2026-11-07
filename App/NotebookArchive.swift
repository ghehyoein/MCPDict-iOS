import Foundation

struct VocabularyBook: Codable, Identifiable {
    let id: UUID
    var name: String
    static let original = VocabularyBook(id: UUID(uuidString: "7D382C3B-BD71-4956-975B-DC901F1CB63C")!, name: "預設生字表")
    var title: String { name == Self.original.name ? ui(name) : name }
}

struct NotebookArchive: Codable {
    var version = 1
    var books = [VocabularyBook.original]
    var selected: Set<UUID> = [VocabularyBook.original.id]
    var entries = [SavedReading]()

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let state: Self
        if let old = try? decoder.decode([SavedReading].self, from: data) {
            var migrated = Self()
            migrated.entries = old
            state = migrated
        } else { state = try decoder.decode(Self.self, from: data) }
        let ids = Set(state.books.map(\.id))
        guard state.version == 1, ids.count == state.books.count,
              Set(state.entries.map(\.id)).count == state.entries.count,
              Set(state.books.map(\.name)).count == state.books.count,
              state.books.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              state.selected.isSubset(of: ids),
              state.entries.allSatisfy({ !$0.membership.isEmpty && $0.membership.isSubset(of: ids) }) else {
            throw DictionaryFailure(message: "生字表資料格式不相容")
        }
        return state
    }

    func exportingSelected() -> Self {
        var archive = self
        archive.books = books.filter { selected.contains($0.id) }
        archive.entries = entries.compactMap { entry in
            let included = entry.membership.intersection(selected)
            guard !included.isEmpty else { return nil }
            var copy = entry; copy.books = included; return copy
        }
        return archive
    }

    mutating func remove(_ ids: Set<UUID>) {
        books.removeAll { ids.contains($0.id) }
        let lostSelection = !selected.isDisjoint(with: ids)
        selected.subtract(ids)
        if lostSelection && selected.isEmpty, let next = books.first { selected = [next.id] }
        for i in entries.indices { entries[i].books = entries[i].membership.subtracting(ids) }
        entries.removeAll { $0.membership.isEmpty }
    }
}
