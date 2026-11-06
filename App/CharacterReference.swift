import SwiftUI

struct CharacterReference {
    static let books = ["說文", "集韻", "康熙", "匯纂", "漢大"]
    static let fields = ["異體字", "字形變體", "字形描述", "部件檢索", "兩分", "總筆畫數", "部首餘筆", "五筆畫", "五筆86", "五筆98", "五筆06", "倉頡三代", "倉頡五代", "倉頡六代", "山人"]
    let character: String
    var block = ""
    var values = [String: String]()
    var code: String { character.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ") }
}

actor CharacterReferenceIndex {
    static let shared = CharacterReferenceIndex()
    private var db: SQLiteConnection?
    func lookup(_ character: String) throws -> CharacterReference {
        if db == nil, let url = Bundle.main.resourceURL?.appendingPathComponent("BundledTables/references.db") {
            db = try SQLiteConnection(url: url)
        }
        var result = CharacterReference(character: character)
        if let scalar = character.unicodeScalars.first {
            result.block = try db?.rows("SELECT label FROM ranges WHERE ? BETWEEN lo AND hi", [String(scalar.value)]).first?["label"] ?? ""
        }
        for row in try db?.rows("SELECT field,value FROM entries WHERE hz=?", [character]) ?? [] {
            if let field = row["field"], let value = row["value"] { result.values[field] = value }
        }
        return result
    }
}

struct ReferencePage: Identifiable {
    let data: CharacterReference
    let book: String?
    var id: String { data.character + (book ?? "Unicode") }
}

struct CharacterReferenceHeader: View {
    let character: String
    let show: (ReferencePage) -> Void
    let map: () -> Void
    @State private var loaded: CharacterReference?
    @EnvironmentObject var model: AppModel
    var body: some View {
        let data = loaded?.character == character ? loaded : nil
        HStack {
            Text(character).font(.system(size: 46, design: .serif)).accessibilityIdentifier("dictionaryHeadword")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    Button((data ?? CharacterReference(character: character)).code) {
                        if let data { show(.init(data: data, book: nil)) }
                    }.disabled(data == nil).accessibilityIdentifier("characterUnicode")
                    ForEach(CharacterReference.books, id: \.self) { book in
                        if let data, data.values[book] != nil {
                            Button(ui(book)) { show(.init(data: data, book: book)) }
                        }
                    }
                    Button(action: map) { Text("🌍") }.accessibilityLabel(ui("在地圖上顯示")).accessibilityIdentifier("characterMap")
                }
            }
        }.buttonStyle(.borderless)
        .task(id: character) {
            do {
                let info = try await CharacterReferenceIndex.shared.lookup(character)
                if !Task.isCancelled { loaded = info }
            } catch { if !Task.isCancelled { model.error = error.localizedDescription } }
        }
    }
}

struct CharacterReferenceDetail: View {
    let page: ReferencePage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    Text(page.data.character).font(.system(size: 46, design: .serif))
                    if let book = page.book { Text(page.data.values[book] ?? "") }
                    else {
                        Text("【" + ui("統一碼") + "】 " + page.data.code + " " + ui(page.data.block))
                        ForEach(CharacterReference.fields, id: \.self) { field in
                            if let value = page.data.values[field] { Text("【" + ui(field) + "】 " + value) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
            }.navigationTitle(ui(page.book ?? "統一碼")).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(ui("完成")) { dismiss() } }
        }
    }
}
