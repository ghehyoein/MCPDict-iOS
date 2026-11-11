import SwiftUI

struct CharacterReadingGroup: Identifiable {
    let character: String
    let language: String
    let readings: [Reading]
    var id: String { character + "\u{0}" + language }
}

enum CharacterResults {
    static func index(_ rows: [Reading]) -> [String: [CharacterReadingGroup]] {
        var values = [String: [String: [Reading]]](), order = [String: [String]]()
        for row in rows {
            for character in Set(row.characters.split(whereSeparator: { $0.isWhitespace }).map(String.init)) {
                if values[character]?[row.language] == nil { order[character, default: []].append(row.language) }
                values[character, default: [:]][row.language, default: []].append(Reading(id: row.id, characters: character, language: row.language, pronunciation: row.pronunciation, note: row.note))
            }
        }
        var result = [String: [CharacterReadingGroup]]()
        for (character, languages) in order {
            result[character] = languages.map { CharacterReadingGroup(character: character, language: $0, readings: values[character]?[$0] ?? []) }
        }
        return result
    }
    static func characters(_ input: String) -> [String] {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.uppercased().hasPrefix("U+"), let code = UInt32(value.dropFirst(2), radix: 16), let scalar = UnicodeScalar(code) { value = String(scalar) }
        var seen = Set<String>()
        return value.map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted }
    }
    static func groups(_ rows: [Reading], character: String) -> [CharacterReadingGroup] {
        let matching = rows.filter { $0.characters.split(whereSeparator: { $0.isWhitespace }).contains(Substring(character)) }
        var order = [String](), grouped = [String: [Reading]]()
        for row in matching {
            if grouped[row.language] == nil { order.append(row.language) }
            grouped[row.language, default: []].append(Reading(id: row.id, characters: character, language: row.language, pronunciation: row.pronunciation, note: row.note))
        }
        return order.map { CharacterReadingGroup(character: character, language: $0, readings: grouped[$0] ?? []) }
    }
}

struct CharacterResultsView: View {
    @EnvironmentObject var model: AppModel
    let current: String
    @AppStorage("colorScheme") private var palette = "atlas"
    var body: some View {
        Group {
            let groups = model.characterGroups(current)
            if groups.isEmpty { SystemText(ui("此字在已下載字表中沒有讀音"), color: .secondaryLabel) }
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 12) {
                    Button { model.tableDetail = model.table(named: group.language) } label: { LanguageBadge(name: group.language, table: model.table(named: group.language), grouping: palette == "atlas" ? .atlas : .dictionary) }.buttonStyle(.plain)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(group.readings) { reading in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { FavoriteButton(reading: reading); PronunciationView(raw: reading.pronunciation, table: model.table(named: reading.language)).font(.title3).contentShape(Rectangle()).textSelection(.enabled).accessibilityIdentifier("dictionary-reading-" + reading.language) }
                                if !reading.displayNote.isEmpty { SystemText(reading.displayNote, color: .secondaryLabel).font(.subheadline) }
                            }

                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 5)
            }
        }
    }
}
