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
