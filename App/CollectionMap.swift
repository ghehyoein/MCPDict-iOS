import SwiftUI

// Build independent snapshots so opening a collection never changes search selections.
enum CollectionMap {
    static func schemes(_ custom: CustomLanguageSchemes, roots: Set<String>, tables: [TablePackage]) -> [DialectPoint] {
        let branches = custom.branchNames(roots)
        let indices = custom.schemes.indices.filter { branches.contains(custom.schemes[$0].name) }.sorted {
            let a = custom.schemes[$0].name.components(separatedBy: "－").count
            let b = custom.schemes[$1].name.components(separatedBy: "－").count
            return a == b ? $0 < $1 : a > b
        }
        var colors = [String: String]()
        for i in indices {
            for language in custom.schemes[i].languages where colors[language] == nil { colors[language] = custom.color(at: i) }
        }
        return tables.compactMap { table in
            guard let color = colors[table.name], var point = DialectPoint.make(table, grouping: .atlas) else { return nil }
            point.color = color
            return point
        }
    }
    static func readings(_ entries: [SavedReading], tables: [TablePackage], grouping: TableGrouping, colors: [String: String]) -> [DialectPoint] {
        let grouped = Dictionary(grouping: entries, by: { $0.reading.language })
        return tables.compactMap { table in
            guard let saved = grouped[table.name] else { return nil }
            let lines = saved.map { item in
                let r = item.reading
                let pronunciation = ToneDisplay.text(r.pronunciation, table: table,
                    style: UserDefaults.standard.string(forKey: "toneStyle") ?? "baSheng",
                    pitch: UserDefaults.standard.string(forKey: "pitchStyle") ?? "curve")
                return r.characters + " " + pronunciation + (r.note.isEmpty ? "" : " " + r.note)
            }.joined(separator: "\n")
            guard var point = DialectPoint.make(table, grouping: grouping, reading: lines) else { return nil }
            if let color = colors[table.name] { point.color = color }
            point.copyText = lines
            return point
        }
    }
}
