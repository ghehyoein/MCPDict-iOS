import SwiftUI

struct NoteVariantPicker: View {
    let query: String
    let select: (String) -> Void
    @State private var choices = [[String]]()
    var body: some View {
        let inputCharacters = Array(query)
        ScrollView(.horizontal) {
            HStack {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, variants in
                    ForEach(variants, id: \.self) { variant in
                        Button {
                            var characters = query.map(String.init)
                            guard characters.indices.contains(index) else { return }
                            characters[index] = variant
                            select(characters.joined())
                        } label: { GlyphChoiceText(variant) }.buttonStyle(.bordered)
                            .tint(inputCharacters.indices.contains(index) && String(inputCharacters[index]) == variant ? AppAccent.color : .gray)
                    }
                    if index + 1 < choices.count { Divider() }
                }
            }
        }.task(id: query) {
            let input = query
            let expanded = await Task.detached { input.map { CharacterVariants.pickerChoices(String($0)) } }.value
            if !Task.isCancelled { choices = expanded }
        }.accessibilityIdentifier("noteInputVariants")
    }
}

enum ResultOrdering {
    static func ranks(_ tables: [TablePackage], namespace: String, defaults: UserDefaults = .standard) -> [String: Int] {
        let kind = defaults.string(forKey: "selectionMode." + namespace) ?? MapSearchKind.language.rawValue
        let grouping = defaults.string(forKey: "grouping." + namespace + "." + kind) ?? TableGrouping.atlas.rawValue
        let key = grouping == TableGrouping.dictionary.rawValue ? "音典排序" : "地圖集二排序"
        var ordered = tables.sorted {
            let a = $0.metadata?[key] ?? "", b = $1.metadata?[key] ?? ""
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return a == b ? $0.name < $1.name : a < b
        }
        // Atlas gives the primary historical tables the same "A" code. Use
        // their upstream MCPDict sequence, not their names, to break that tie.
        // Replace only historical slots so all other language ranks stay intact.
        let historicalIndices = ordered.indices.filter {
            ordered[$0].atlas.first == "歷史音" || ordered[$0].dictionary.first == "歷史音"
        }
        let historical = historicalIndices.map { ordered[$0] }.sorted {
            let a = $0.metadata?["音典排序"] ?? "", b = $1.metadata?["音典排序"] ?? ""
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return a == b ? $0.name < $1.name : a < b
        }
        for (index, table) in zip(historicalIndices, historical) { ordered[index] = table }
        return Dictionary(ordered.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: min)
    }
    static func sorted(_ rows: [Reading], ranks: [String: Int]) -> [Reading] {
        rows.enumerated().sorted {
            let a = ranks[$0.element.language] ?? Int.max, b = ranks[$1.element.language] ?? Int.max
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
}
