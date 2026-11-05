import Foundation

enum LanguageSelectionScope {
    case points, terminalGroups, topGroups

    func eligible(_ tables: [TablePackage], grouping: TableGrouping) -> [TablePackage] {
        guard self != .points else { return tables }
        return tables.filter { !grouping.path($0).isEmpty }
    }
}

struct LanguageSelectionCache {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load(_ key: String) -> Set<String>? { defaults.stringArray(forKey: "languageSelection." + key).map { Set($0) } }
    func save(_ names: Set<String>, for key: String) { defaults.set(names.sorted(), forKey: "languageSelection." + key) }
}

// Build region membership once, rather than rescanning every table for every node.
enum RegionSelection {
    static func restore(tables: [TablePackage], grouping: TableGrouping, names: Set<String>, saved: String?) -> String? {
        guard !names.isEmpty else { return nil }
        var members = [[String]: Set<String>]()
        for table in tables {
            let path = grouping.path(table)
            guard !path.isEmpty else { continue }
            for length in 1...path.count { members[Array(path.prefix(length)), default: []].insert(table.name) }
        }
        let matching = members.filter { $0.value == names }.keys.sorted {
            $0.count == $1.count ? $0.lexicographicallyPrecedes($1) : $0.count < $1.count
        }.map { $0.joined(separator: "\u{0}") }
        return matching.contains(saved ?? "") ? saved : matching.first
    }
}
