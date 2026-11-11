import SwiftUI

struct ResultArrangementSettings: View {
    @AppStorage("resultArrangement") private var selection = "list"
    @Environment(\.dismiss) private var dismiss
    static let choices = [("list", "呈列排列"), ("horizontal", "呈橫向表格排列"), ("vertical", "呈縱向表格排列")]
    var body: some View {
        NavigationStack {
            Form {
                ForEach(Self.choices, id: \.0) { value, title in
                    Button { selection = value } label: {
                        HStack { Text(ui(title)).foregroundStyle(.primary); Spacer(); if selection == value { Image(systemName: "checkmark") } }
                            .contentShape(Rectangle())
                    }.accessibilityIdentifier("arrangement-" + value)
                }
            }.navigationTitle(ui("排列")).toolbar { Button(ui("完成")) { dismiss() } }
        }
    }
}

struct ResultTableIndex {
    var languages = [String]()
    var characters = [String]()
    var cells = [String: [String: [Reading]]]()
    init(_ readings: [Reading]) {
        var langs = Set<String>(), chars = Set<String>()
        for row in readings {
            if langs.insert(row.language).inserted { languages.append(row.language) }
            for c in row.characters.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
                if chars.insert(c).inserted { characters.append(c) }
                cells[row.language, default: [:]][c, default: []].append(row)
            }
        }
    }
}

struct DictionaryResultTable: View {
    @EnvironmentObject var model: AppModel
    let languagesAsRows: Bool
    var viewportHeight: CGFloat = 500
    var body: some View {
        let index = ResultTableIndex(model.results)
        let rows = languagesAsRows ? index.languages : index.characters
        let columns = languagesAsRows ? index.characters : index.languages
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Text("").frame(width: 150)
                    ForEach(columns, id: \.self) { column in header(column, language: !languagesAsRows).frame(width: 180).padding(8) }
                }.background(Color(uiColor: .secondarySystemBackground))
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 0) {
                        header(row, language: languagesAsRows).frame(width: 134).padding(8)
                        ForEach(columns, id: \.self) { column in
                            let language = languagesAsRows ? row : column
                            let character = languagesAsRows ? column : row
                            VStack(alignment: .leading, spacing: 6) {
                                let readings = index.cells[language]?[character] ?? []
                                if readings.isEmpty { Text("—").foregroundStyle(.secondary) }
                                ForEach(readings) { reading in
                                    HStack(alignment: .top) { FavoriteButton(reading: reading); PronunciationView(raw: reading.pronunciation, table: model.table(named: language)) }
                                    if !reading.displayNote.isEmpty { SystemText(reading.displayNote, color: .secondaryLabel) }
                                }
                            }.frame(width: 180, alignment: .leading).padding(8)
                        }
                    }
                    Divider()
                }
            }
        }.frame(height: max(240, viewportHeight * 0.65)).accessibilityIdentifier("dictionary-result-table")
    }
    @ViewBuilder private func header(_ value: String, language: Bool) -> some View {
        if language {
            Button { model.tableDetail = model.table(named: value) } label: { LanguageBadge(name: value, table: model.table(named: value)) }.buttonStyle(.plain)
        } else { SystemText(value).font(.title3) }
    }
}
