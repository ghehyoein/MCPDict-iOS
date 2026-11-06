import Foundation

enum PersonRole: String, CaseIterable { case editor = "錄入人", maintainer = "維護人" }

struct LanguageFlags: Equatable {
    var island = false
    var history = false
    func matches(_ table: TablePackage) -> Bool {
        func marked(_ key: String) -> Bool {
            guard let value = table.metadata?[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
            return !["", "0", "false", "null", "否"].contains(value)
        }
        let historical = marked("歷史音") || [table.atlas.first, table.dictionary.first].contains("歷史音")
        return (!island || marked("方言島")) && (!history || historical)
    }
}

extension TableGrouping {
    func paths(_ table: TablePackage, roles: Set<PersonRole>) -> [[String]] {
        guard self == .person else { return [path(table)] }
        var people = Set<String>()
        for role in roles {
            let raw = table.metadata?[role.rawValue] ?? ""
            let values = raw.components(separatedBy: CharacterSet(charactersIn: ",，、;；")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != "null" }
            people.formUnion(values.isEmpty ? ["(無)"] : values)
        }
        return people.sorted().map { [$0] }
    }
}
enum LanguageSelectionScope {
    case points, terminalGroups, administrativeGroups, topGroups

    func eligible(_ tables: [TablePackage], grouping: TableGrouping, roles: Set<PersonRole> = Set(PersonRole.allCases)) -> [TablePackage] {
        if grouping == .person { return roles.isEmpty ? [] : tables }
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
    static func restore(tables: [TablePackage], grouping: TableGrouping, names: Set<String>, saved: String?, roles: Set<PersonRole> = Set(PersonRole.allCases)) -> String? {
        guard !names.isEmpty else { return nil }
        var members = [[String]: Set<String>]()
        for table in tables {
            for path in grouping.paths(table, roles: roles) where !path.isEmpty {
            for length in 1...path.count { members[Array(path.prefix(length)), default: []].insert(table.name) }
            }
        }
        let matching = members.filter { $0.value == names }.keys.sorted {
            $0.count == $1.count ? $0.lexicographicallyPrecedes($1) : $0.count < $1.count
        }.map { $0.joined(separator: "\u{0}") }
        return matching.contains(saved ?? "") ? saved : matching.first
    }
}
