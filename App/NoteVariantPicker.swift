import SwiftUI

struct NoteVariantPicker: View {
    @Binding var query: String
    let submit: () -> Void
    @State private var choices = [[String]]()
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, variants in
                    ForEach(variants, id: \.self) { variant in
                        Button(variant) {
                            var characters = query.map(String.init)
                            guard characters.indices.contains(index) else { return }
                            characters[index] = variant
                            query = characters.joined(); submit()
                        }.buttonStyle(.bordered)
                            .tint(Array(query).indices.contains(index) && String(Array(query)[index]) == variant ? AppAccent.color : .gray)
                    }
                    if index + 1 < choices.count { Divider() }
                }
            }
        }.task(id: query) {
            let input = query
            let expanded = await Task.detached { input.map { CharacterVariants.expand(String($0)) } }.value
            if !Task.isCancelled { choices = expanded }
        }.accessibilityIdentifier("noteInputVariants")
    }
}

enum ResultOrdering {
    static func ranks(_ tables: [TablePackage], namespace: String, defaults: UserDefaults = .standard) -> [String: Int] {
        let kind = defaults.string(forKey: "selectionMode." + namespace) ?? MapSearchKind.language.rawValue
        let grouping = defaults.string(forKey: "grouping." + namespace + "." + kind) ?? TableGrouping.atlas.rawValue
        let key = grouping == TableGrouping.dictionary.rawValue ? "音典排序" : "地圖集二排序"
        let ordered = tables.sorted {
            let a = $0.metadata?[key] ?? "", b = $1.metadata?[key] ?? ""
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return a == b ? $0.name < $1.name : a < b
        }
        return Dictionary(ordered.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: min)
    }
    static func sorted(_ rows: [Reading], ranks: [String: Int]) -> [Reading] {
        rows.enumerated().sorted {
            let a = ranks[$0.element.language] ?? Int.max, b = ranks[$1.element.language] ?? Int.max
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }
}
