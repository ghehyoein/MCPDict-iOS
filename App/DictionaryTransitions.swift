import Foundation

/// Resolve only exact recorded colors (or an explicit recorded region name).
/// Unknown/colliding colors are not assigned to a guessed region.
struct DictionaryTransitions {
    let regionsByColor: [String: [String]]
    let branches: Set<[String]>
    private let knownPaths: Set<[String]>
    init(tables: [TablePackage]) {
        var colors = [String: [String]](), branches = Set<[String]>(), paths = Set<[String]>()
        for table in tables {
            let path = table.dictionary
            guard !path.isEmpty else { continue }
            for length in 1...path.count { paths.insert(Array(path.prefix(length))) }
            for length in 1..<path.count { branches.insert(Array(path.prefix(length))) }
            guard let color = TableColors.hexes(table.dictionaryColor).first?.uppercased() else { continue }
            if let previous = colors[color] {
                colors[color] = Array(zip(previous, path).prefix { $0.0 == $0.1 }.map { $0.0 })
            } else { colors[color] = path }
        }
        regionsByColor = colors.filter { !$0.value.isEmpty }
        self.branches = branches; knownPaths = paths
    }
    func destinations(_ table: TablePackage) -> [[String]] {
        var paths = [[String]]()
        for key in ["音典分區過渡色", "音典過渡分區", "音典過渡色"] {
            guard let raw = table.metadata?[key], !raw.isEmpty else { continue }
            let path = raw.replacingOccurrences(of: "-", with: "－").components(separatedBy: "－").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if knownPaths.contains(path) { paths.append(path) }
        }
        if paths.isEmpty {
            paths = TableColors.hexes(table.dictionaryColor).dropFirst().compactMap { regionsByColor[$0.uppercased()] }
        }
        var seen = Set<[String]>()
        return paths.filter { seen.insert($0).inserted }
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
