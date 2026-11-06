import SwiftUI
import UniformTypeIdentifiers

// UTF-8 JSON is plain text and preserves book memberships, IPA and multiline notes.
struct NotebookTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var archive: NotebookArchive
    init(archive: NotebookArchive) { self.archive = archive }
    init(configuration: ReadConfiguration) throws {
        archive = try NotebookArchive.decode(configuration.file.regularFileContents ?? Data())
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return FileWrapper(regularFileWithContents: try encoder.encode(archive))
    }
}

enum FavoritePreferences {
    static let defaultsKey = "defaultFavoriteBooks"
    static func targets(in archive: NotebookArchive, defaults: UserDefaults = .standard) -> Set<UUID> {
        let stored = defaults.stringArray(forKey: defaultsKey)
        let ids = stored.map { Set($0.compactMap(UUID.init(uuidString:))) } ?? [VocabularyBook.original.id]
        return ids.intersection(archive.books.map(\.id))
    }
}

struct FavoriteSettingsSection: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("favoriteAction") private var action = "ask"
    @State private var defaults = Set<UUID>()
    var body: some View {
        Section(ui("收藏")) {
            Picker(ui("點擊收藏星號"), selection: $action) {
                Text(ui("詢問加入哪些生字表")).tag("ask")
                Text(ui("直接加入預設生字表")).tag("direct")
            }
            ForEach(model.notebook.books) { book in
                Button {
                    if !defaults.insert(book.id).inserted { defaults.remove(book.id) }
                    UserDefaults.standard.set(defaults.map(\.uuidString).sorted(), forKey: FavoritePreferences.defaultsKey)
                } label: {
                    HStack {
                        Image(systemName: defaults.contains(book.id) ? "checkmark.square.fill" : "square")
                            .contentTransition(.identity).transaction { $0.animation = nil; $0.disablesAnimations = true }
                        Text(verbatim: book.title); Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(ui("預設生字表") + " · " + book.title)
            }
        }.onAppear { defaults = FavoritePreferences.targets(in: model.notebook) }
    }
}

extension NotebookArchive {
    mutating func merge(_ incoming: Self) {
        var mapped = [UUID: UUID]()
        for book in incoming.books {
            if let existing = books.first(where: { $0.name == book.name }) { mapped[book.id] = existing.id }
            else {
                let id = books.contains(where: { $0.id == book.id }) ? UUID() : book.id
                books.append(VocabularyBook(id: id, name: book.name)); mapped[book.id] = id
            }
        }
        for entry in incoming.entries {
            let membership = Set(entry.membership.compactMap { mapped[$0] })
            if let i = entries.firstIndex(where: { ReadingContentKey($0.reading) == ReadingContentKey(entry.reading) }) {
                entries[i].books = entries[i].membership.union(membership)
                if !entry.note.isEmpty && !entries[i].note.contains(entry.note) {
                    entries[i].note = entries[i].note.isEmpty ? entry.note : entries[i].note + "\n" + entry.note
                }
            } else {
                var next = entry
                if entries.contains(where: { $0.id == next.id }) { next.id = UUID() }
                next.books = membership; entries.append(next)
            }
        }
    }
}
