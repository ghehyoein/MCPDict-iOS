import Foundation

enum PersonRole: String, CaseIterable { case editor = "錄入人", maintainer = "維護人" }

enum LanguageVisibility: String, CaseIterable, Codable {
    case only, show, hide
    var title: String { switch self { case .only: return "僅顯示"; case .show: return "顯示"; case .hide: return "隱藏" } }
    func accepts(_ marked: Bool) -> Bool { self == .show || (self == .only ? marked : !marked) }
}

struct LanguageFlags: Equatable {
    var islandMode: LanguageVisibility = .show
    var historyMode: LanguageVisibility = .show
    var island: Bool { get { islandMode == .only } set { islandMode = newValue ? .only : .show } }
    var history: Bool { get { historyMode == .only } set { historyMode = newValue ? .only : .show } }
    init(island: Bool = false, history: Bool = false) {
        islandMode = island ? .only : .show; historyMode = history ? .only : .show
    }
    var isFiltering: Bool { islandMode != .show || historyMode != .show }
    static func historicalMarker(_ table: TablePackage) -> String? {
        let fields = ["是否為語言歷史音", "是否为语言历史音", "是否為方言歷史音", "歷史音"]
        guard let raw = fields.lazy.compactMap({ table.metadata?[$0] }).first else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: "#", with: "")
        let rgb = value.count == 8 ? String(value.suffix(6)) : value
        guard rgb.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil,
              let number = UInt32(rgb, radix: 16) else { return nil }
        let r = number >> 16 & 255, g = number >> 8 & 255, b = number & 255
        return r == g && g == b && r > 0 && r < 255 ? "#" + rgb : nil
    }
    func matches(_ table: TablePackage) -> Bool {
        func marked(_ key: String) -> Bool {
            guard let value = table.metadata?[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
            return !["", "0", "false", "null", "否"].contains(value)
        }
        let historical = Self.historicalMarker(table) != nil && ![table.atlas.first, table.dictionary.first].contains("歷史音")
        return islandMode.accepts(marked("方言島")) && historyMode.accepts(historical)
    }
}

extension TableGrouping {
    func paths(_ table: TablePackage, roles: Set<PersonRole>) -> [[String]] {
        guard self == .person else { return [path(table)] }
        var people = Set<String>()
        for role in roles {
            let raw = table.metadata?[role.rawValue] ?? ""
            let values = raw.components(separatedBy: CharacterSet(charactersIn: ",，、;；")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != "null" }
            if role == .maintainer {
                people.formUnion(values.filter { !["(無)", "（無）", "(无)", "（无）"].contains($0) })
            } else { people.formUnion(values.isEmpty ? ["(無)"] : values) }
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
    static func isAncestor(_ region: String?, of selected: String?) -> Bool {
        guard let region, let selected else { return false }
        return selected.hasPrefix(region + "\u{0}")
    }
    static func restore(tables: [TablePackage], grouping: TableGrouping, names: Set<String>, saved: String?, roles: Set<PersonRole> = Set(PersonRole.allCases), additionalPaths: [String: [[String]]] = [:]) -> String? {
        guard !names.isEmpty else { return nil }
        var members = [[String]: Set<String>]()
        for table in tables {
            for path in grouping.paths(table, roles: roles) + (grouping == .dictionary ? additionalPaths[table.id] ?? [] : []) where !path.isEmpty {
            for length in 1...path.count { members[Array(path.prefix(length)), default: []].insert(table.name) }
            }
        }
        let matching = members.filter { $0.value == names }.keys.sorted {
            $0.count == $1.count ? $0.lexicographicallyPrecedes($1) : $0.count < $1.count
        }.map { $0.joined(separator: "\u{0}") }
        return matching.contains(saved ?? "") ? saved : matching.first
    }
}
