import Foundation

/// Resolve only exact recorded colors (or an explicit recorded region name).
/// A color shared by several paths resolves to their highest common region in each root.
/// No nearest-color match is used; inferred/unknown memberships retain an asterisk.
struct DictionaryTransitions {
    let regionsByColor: [String: [[String]]]
    private let ambiguousColors: Set<String>
    let branches: Set<[String]>
    private let knownPaths: Set<[String]>
    init(tables: [TablePackage]) {
        var colors = [String: Set<[String]>](), branches = Set<[String]>(), paths = Set<[String]>()
        for table in tables {
            let path = table.dictionary
            guard !path.isEmpty else { continue }
            for length in 1...path.count { paths.insert(Array(path.prefix(length))) }
            for length in 1..<path.count { branches.insert(Array(path.prefix(length))) }
            guard let color = TableColors.hexes(table.dictionaryColor).first?.uppercased() else { continue }
            colors[color, default: []].insert(path)
        }
        ambiguousColors = Set(colors.filter { $0.value.count > 1 }.keys)
        regionsByColor = colors.mapValues { candidates in
            Dictionary(grouping: candidates, by: { $0[0] }).values.map { group in
                group.dropFirst().reduce(group[0]) { prefix, path in
                    Array(zip(prefix, path).prefix { $0.0 == $0.1 }.map { $0.0 })
                }
            }.sorted { $0.lexicographicallyPrecedes($1) }
        }
        self.branches = branches; knownPaths = paths
    }
    private func recordedDestinations(_ table: TablePackage) -> [[String]] {
        var paths = [[String]]()
        for key in ["音典分區過渡色", "音典過渡分區", "音典過渡色"] {
            guard let raw = table.metadata?[key], !raw.isEmpty else { continue }
            let path = raw.replacingOccurrences(of: "-", with: "－").components(separatedBy: "－").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if knownPaths.contains(path) { paths.append(path) }
        }
        return paths
    }
    func destinations(_ table: TablePackage) -> [[String]] {
        let recorded = recordedDestinations(table)
        let paths = recorded.isEmpty
            ? TableColors.hexes(table.dictionaryColor).dropFirst().flatMap { regionsByColor[$0.uppercased()] ?? [] }
            : recorded
        var seen = Set<[String]>()
        return paths.filter { seen.insert($0).inserted }
    }
    func needsAsterisk(_ table: TablePackage) -> Bool {
        guard recordedDestinations(table).isEmpty else { return false }
        return TableColors.hexes(table.dictionaryColor).dropFirst().contains {
            ambiguousColors.contains($0.uppercased()) || regionsByColor[$0.uppercased()] == nil
        }
    }
    func additionalPaths(_ tables: [TablePackage]) -> [String: [[String]]] {
        var result = [String: [[String]]]()
        for table in tables {
            let paths = destinations(table).map {
                branches.contains($0) ? $0 + ["過渡色"] : $0
            }.filter { $0 != table.dictionary }
            if !paths.isEmpty { result[table.id] = paths }
        }
        return result
    }
    func description(_ table: TablePackage) -> String {
        let destinations = destinations(table)
        let unknown = TableColors.hexes(table.dictionaryColor).dropFirst().filter { regionsByColor[$0.uppercased()] == nil }
        return (destinations.map { $0.joined(separator: "－") } + unknown).joined(separator: "、")
    }
}
