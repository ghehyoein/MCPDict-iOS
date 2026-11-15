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
    @State private var excluded = Set<String>()
    @State private var inspected: String?
    var body: some View {
        let index = ResultTableIndex(model.results)
        VStack(alignment: .leading) {
            characterSelection(index.characters)
            grid(index)
        }.onChange(of: index.characters) { _, _ in excluded = [] }
            .sheet(isPresented: Binding(get: { inspected != nil }, set: { if !$0 { inspected = nil } })) {
                if let char = inspected {
                    NavigationStack {
                        List { AnalysisCharacterRow(character: char) }
                            .toolbar { Button(ui("完成")) { inspected = nil } }
                    }
                }
            }
    }
    private func characterSelection(_ characters: [String]) -> some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(characters, id: \.self) { character in
                    Button { if !excluded.insert(character).inserted { excluded.remove(character) } } label: {
                        Label(character, systemImage: excluded.contains(character) ? "square" : "checkmark.square.fill")
                    }.buttonStyle(.borderless)
                }
            }
        }
    }
    private func grid(_ index: ResultTableIndex) -> some View {
        let characters = index.characters.filter { !excluded.contains($0) }
        let rows = languagesAsRows ? index.languages : characters
        let columns = languagesAsRows ? characters : index.languages
        return ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Text("").frame(width: 150)
                    ForEach(columns, id: \.self) { column in header(column, language: !languagesAsRows).frame(width: 180).padding(8) }
                }.background(Color(uiColor: .secondarySystemBackground))
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 0) {
                        header(row, language: languagesAsRows).frame(width: 134).padding(8)
                        ForEach(columns, id: \.self) { column in
                            cell(index, language: languagesAsRows ? row : column, character: languagesAsRows ? column : row)
                        }
                    }
                    Divider()
                }
            }
        }.frame(height: max(240, viewportHeight * 0.65)).accessibilityIdentifier("dictionary-result-table")
    }
    private func cell(_ index: ResultTableIndex, language: String, character: String) -> some View {
        let readings = index.cells[language]?[character] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            if readings.isEmpty { Text("—").foregroundStyle(.secondary) }
            ForEach(readings) { reading in
                HStack(alignment: .top) {
                    FavoriteButton(reading: reading)
                    PronunciationView(raw: reading.pronunciation, table: model.table(named: language), wrapReadings: true)
                }
                if !reading.displayNote.isEmpty { SystemText(reading.displayNote, color: .secondaryLabel) }
            }
        }.frame(width: 180, alignment: .leading).padding(8)
    }
    @ViewBuilder private func header(_ value: String, language: Bool) -> some View {
        if language {
            Button { model.tableDetail = model.table(named: value) } label: { LanguageBadge(name: value, table: model.table(named: value)) }.buttonStyle(.plain)
        } else { Button { inspected = value } label: { Text(value).font(.title3) }.buttonStyle(.borderless) }
    }
}
