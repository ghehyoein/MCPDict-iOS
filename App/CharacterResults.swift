import SwiftUI

struct CharacterReadingGroup: Identifiable {
    let character: String
    let language: String
    let readings: [Reading]
    var id: String { character + "\u{0}" + language }
}

enum CharacterResults {
    static func characters(_ input: String) -> [String] {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.uppercased().hasPrefix("U+"), let code = UInt32(value.dropFirst(2), radix: 16), let scalar = UnicodeScalar(code) { value = String(scalar) }
        var seen = Set<String>()
        return value.map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted }
    }
    static func groups(_ rows: [Reading], character: String) -> [CharacterReadingGroup] {
        let matching = rows.filter { $0.characters.split(whereSeparator: { $0.isWhitespace }).contains(Substring(character)) }
        return Dictionary(grouping: matching, by: \.language).sorted { $0.key < $1.key }.map { language, readings in
            CharacterReadingGroup(character: character, language: language, readings: readings.map {
                Reading(id: $0.id, characters: character, language: $0.language, pronunciation: $0.pronunciation, note: $0.note)
            })
        }
    }
}

struct CharacterResultsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedCharacter = ""
    @State private var information: TablePackage?
    private var characters: [String] { model.resultCharacters.isEmpty ? CharacterResults.characters(model.resultQuery) : model.resultCharacters }
    private var current: String { characters.contains(selectedCharacter) ? selectedCharacter : characters.first ?? "" }
    var body: some View {
        Section {
            if characters.count > 1 {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(characters, id: \.self) { character in
                            Button(character) { selectedCharacter = character }
                                .buttonStyle(.bordered).tint(character == current ? .teal : .gray)
                        }
                    }
                }
            }
            HStack(alignment: .center, spacing: 16) {
                Text(current).font(.system(size: 58)).frame(width: 84, height: 84).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                Text(current.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")).foregroundStyle(.secondary)
            }
            let groups = CharacterResults.groups(model.results, character: current)
            if groups.isEmpty { Text(ui("此字在已下載字表中沒有讀音")).foregroundStyle(.secondary) }
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 12) {
                    Button { information = model.table(named: group.language) } label: { LanguageBadge(name: group.language, table: model.table(named: group.language)) }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(group.readings) { reading in
                            VStack(alignment: .leading, spacing: 2) {
                                PronunciationView(raw: reading.pronunciation, table: model.table(named: reading.language)).font(.title3)
                                if !reading.note.isEmpty { Text(reading.note).font(.subheadline).foregroundStyle(.secondary) }
                            }
                                .textSelection(.enabled)
                                .contextMenu { Button(ui("加入生字本"), systemImage: "star") { model.save(reading) } }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 5)
            }
        }
        .sheet(item: $information) { TableInfoView(table: $0) }
    }
}
