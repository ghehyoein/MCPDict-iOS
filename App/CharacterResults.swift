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
    let current: String
    @AppStorage("dictionaryPalette") private var palette = "atlas"
    let copy: (String) -> Void
    @State private var information: TablePackage?
    var body: some View {
        Group {
            let groups = model.characterGroups(current)
            if groups.isEmpty { Text(ui("此字在已下載字表中沒有讀音")).foregroundStyle(.secondary) }
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 12) {
                    Button { information = model.table(named: group.language) } label: { LanguageBadge(name: group.language, table: model.table(named: group.language), grouping: palette == "atlas" ? .atlas : .dictionary) }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(group.readings) { reading in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { FavoriteButton(reading: reading); PronunciationView(raw: reading.pronunciation, table: model.table(named: reading.language)).font(.title3).onLongPressGesture { copy(reading.pronunciation) } }
                                if !reading.note.isEmpty { Text(reading.note).font(.subheadline).foregroundStyle(.secondary) }
                            }

                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 5)
            }
        }
        .sheet(item: $information) { TableInfoView(table: $0) }
    }
}
