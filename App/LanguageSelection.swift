import Foundation

enum LanguageSelectionScope {
    case points, terminalGroups, topGroups

    func eligible(_ tables: [TablePackage], grouping: TableGrouping) -> [TablePackage] {
        guard self != .points else { return tables }
        let paths = Set(tables.map { grouping.path($0) }.filter { !$0.isEmpty })
        if self == .topGroups { return tables.filter { !grouping.path($0).isEmpty } }
        // Only terminal regions are selectable. A point beside a deeper region is hidden.
        var ancestors = Set<[String]>()
        for path in paths where path.count > 1 {
            for length in 1..<path.count { ancestors.insert(Array(path.prefix(length))) }
        }
        let terminals = paths.subtracting(ancestors)
        return tables.filter { terminals.contains(grouping.path($0)) }
    }
}

struct LanguageSelectionCache {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load(_ key: String) -> Set<String>? { defaults.stringArray(forKey: "languageSelection." + key).map { Set($0) } }
    func save(_ names: Set<String>, for key: String) { defaults.set(names.sorted(), forKey: "languageSelection." + key) }
}
