import SwiftUI

struct AnnotatedCharacter: Identifiable {
    struct Choice: Hashable {
        let character: String
        let pronunciation: String
    }
    let id: Int
    let original: String
    let choices: [Choice]
    var selected = 0
    var choice: Choice? { choices.indices.contains(selected) ? choices[selected] : nil }
}

enum LongTextAnnotation {
    static let limit = 400
    static let formats = ["IPA", "IPA＋字", "IPA＋曲折線調值", "IPA＋曲折線調值＋字", "IPA＋調類", "IPA＋調類＋字", "IPA＋曲折線調值＋調類", "IPA＋曲折線調值＋調類＋字"]
    static func build(_ text: String, rows: [Reading], variants: (String) -> [String] = CharacterVariants.expand) -> [AnnotatedCharacter] {
        var byCharacter = [String: [AnnotatedCharacter.Choice]]()
        for row in rows {
            for character in CharacterResults.characters(row.characters) {
                let choice = AnnotatedCharacter.Choice(character: character, pronunciation: row.pronunciation)
                if !(byCharacter[character] ?? []).contains(choice) { byCharacter[character, default: []].append(choice) }
            }
        }
        var cache = [String: [AnnotatedCharacter.Choice]]()
        return Array(text).enumerated().map { index, character in
            let original = String(character)
            if cache[original] == nil { cache[original] = variants(original).flatMap { byCharacter[$0] ?? [] } }
            return AnnotatedCharacter(id: index, original: original, choices: cache[original] ?? [])
        }
    }
    static func reading(_ choice: AnnotatedCharacter.Choice, table: TablePackage?, format: Int) -> String {
        ToneDisplay.text(choice.pronunciation, table: table, style: format >= 5 ? "pinYin" : "hidden", pitch: [3,4,7,8].contains(format) ? "curve" : "hidden")
    }
    static func copyText(_ characters: [AnnotatedCharacter], table: TablePackage?, format: Int) -> String {
        characters.map {
            guard let choice = $0.choice else { return $0.original }
            return reading(choice, table: table, format: format) + (format.isMultiple(of: 2) ? " " + choice.character : "") + " "
        }.joined()
    }
}

struct LongTextView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(ReadingFormatPreferences.key) private var readingFormats = ""
    @AppStorage("longTextLanguage") private var language = ""
    @AppStorage("longTextFormat") private var format = 8
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @State private var characters = [AnnotatedCharacter]()
    @State private var submittedTable: TablePackage?
    @State private var languageSheet = false
    @State private var languageFilter = ""
    @State private var selectedCharacter: Int?
    @State private var busy = false
    private var tables: [TablePackage] { model.installed?.tables ?? [] }
    private var paragraphs: [[Int]] {
        var rows = [[Int]()] 
        for item in characters {
            if item.original == "\n" || item.original == "\r\n" { rows.append([]) }
            else { rows[rows.count - 1].append(item.id) }
        }
        return rows
    }
    var body: some View {
        let _ = readingFormats
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(ui("長文注音，每次最多 400 字。藍點表示多音或異體字，可點擊切換。"))
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $input).focused($inputFocused).frame(height: 140).overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary))
                    .accessibilityIdentifier("longTextInput")
                    .onChange(of: input) { _, value in if value.count > LongTextAnnotation.limit { input = String(value.prefix(LongTextAnnotation.limit)) } }
                HStack {
                    Text("\(input.count) / 400").foregroundStyle(.secondary)
                    Spacer()
                    Button { inputFocused = false; languageSheet = true } label: { Label(language.isEmpty ? ui("選擇語言") : language, systemImage: "gearshape") }.accessibilityIdentifier("longTextLanguage")
                    Button(ui("查詢")) { Task { await annotate() } }.disabled(busy || input.isEmpty).accessibilityIdentifier("annotateLongText")
                }
                Picker(ui("長文注音格式"), selection: $format) {
                    ForEach(1...8, id: \.self) { Text(ui(LongTextAnnotation.formats[$0 - 1])).tag($0) }
                }.pickerStyle(.menu)
                if busy { ProgressView() }
                if !characters.isEmpty {
                    HStack { Spacer(); Button(ui("複製")) { UIPasteboard.general.string = LongTextAnnotation.copyText(characters, table: submittedTable, format: format) }.accessibilityIdentifier("copyLongText") }
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, row in
                        WrappingInformationLayout {
                            ForEach(row, id: \.self) { index in
                                let item = characters[index]
                                if let choice = item.choice {
                                    Button { selectedCharacter = index } label: {
                                        VStack(spacing: 3) {
                                            Text(LongTextAnnotation.reading(choice, table: submittedTable, format: format)).foregroundStyle(.primary)
                                            if format.isMultiple(of: 2) { Text(choice.character).foregroundStyle(.primary) }
                                            Circle().fill(item.choices.count > 1 ? Color.blue : .clear).frame(width: 4, height: 4)
                                        }.padding(.horizontal, 2)
                                    }.buttonStyle(.plain).accessibilityIdentifier("annotatedCharacter-\(index)")
                                } else { Text(item.original).foregroundStyle(.secondary) }
                            }
                            if row.isEmpty { Text(" ") }
                        }
                    }
                }
            }.padding()
        }.navigationTitle(ui("長文注音")).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $languageSheet) {
            NavigationStack {
                List(tables.filter { languageFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(languageFilter) }) { table in
                    Button { language = table.name; characters = []; languageSheet = false } label: {
                        HStack { LanguageBadge(name: table.name, table: table); Spacer(); if language == table.name { Image(systemName: "checkmark") } }
                    }
                }.searchable(text: $languageFilter, prompt: ui("搜尋語言或分區"))
                    .navigationTitle(ui("選擇語言"))
                    .toolbar { Button(ui("完成")) { languageSheet = false } }
            }
        }
        .sheet(isPresented: Binding(get: { selectedCharacter != nil }, set: { if !$0 { selectedCharacter = nil } })) {
            if let index = selectedCharacter, characters.indices.contains(index) {
                NavigationStack {
                    List(Array(characters[index].choices.enumerated()), id: \.offset) { offset, choice in
                        Button { characters[index].selected = offset; selectedCharacter = nil } label: {
                            HStack { Text(choice.character); PronunciationView(raw: choice.pronunciation, table: submittedTable); Spacer(); if offset == characters[index].selected { Image(systemName: "checkmark") } }
                        }
                    }.navigationTitle(characters[index].original)
                        .toolbar { Button(ui("完成")) { selectedCharacter = nil } }
                }
            }
        }
    }
    @MainActor private func annotate() async {
        inputFocused = false
        guard let table = tables.first(where: { $0.name == language }) else { languageSheet = true; return }
        busy = true; defer { busy = false }
        let text = input
        do {
            let rows = try await model.repository.searchAllCharacters(CharacterVariants.expand(text).joined(), language: language)
            guard language == table.name else { return }
            characters = LongTextAnnotation.build(text, rows: rows); submittedTable = table
        } catch { model.error = error.localizedDescription }
    }
}
