import Foundation

// One immutable snapshot per catalog/classification, reused for every checkbox update.
struct SelectionIndex {
    let revision = UUID()
    private var tableIDsByName = [String: String]()
    struct Node {
        let id: String
        let title: String
        let depth: Int
        let region: String?
        let table: TablePackage?
        var ids = Set<String>()
        var children = [String]()
    }
    struct Row: Identifiable {
        let node: Node
        let ids: Set<String>
        let expandable: Bool
        var id: String { node.id }
    }
    private(set) var nodes = [String: Node]()
    private(set) var roots = [String]()
    private var searchText = [String: String]()
    private(set) var membershipInsertions = 0
    init(tables: [TablePackage] = [], grouping: TableGrouping = .atlas, roles: Set<PersonRole> = Set(PersonRole.allCases), additionalPaths: [String: [[String]]] = [:]) {
        for table in tables.sorted(by: { $0.name < $1.name }) {
            let paths = grouping.paths(table, roles: roles) + (grouping == .dictionary ? additionalPaths[table.id] ?? [] : [])
            var terms = [table.name]
            for path in [table.atlas, table.dictionary, table.administrative] { terms.append(contentsOf: path) }
            if grouping == .person || grouping == .dictionary { terms.append(contentsOf: paths.flatMap { $0 }) }
            tableIDsByName[table.name] = table.id
            searchText[table.id] = InterfaceLanguage.text(terms.joined(separator: "\n"), script: "hans")
            for path in paths {
            var parent: String?
            for depth in path.indices {
                let region = path.prefix(depth + 1).joined(separator: "\u{0}")
                let key = "g:" + region
                if nodes[key] == nil {
                    nodes[key] = Node(id: key, title: path[depth], depth: depth, region: region, table: nil)
                    if let parent { nodes[parent]!.children.append(key) } else { roots.append(key) }
                }
                nodes[key]!.ids.insert(table.id)
                membershipInsertions += 1
                parent = key
            }
            let leaf = "t:" + (grouping == .person || !additionalPaths.isEmpty ? (parent ?? "") + ":" : "") + table.id
            nodes[leaf] = Node(id: leaf, title: table.name, depth: path.count, region: nil, table: table, ids: [table.id])
            if let parent { nodes[parent]!.children.append(leaf) } else { roots.append(leaf) }
            }
        }
        func ordered(_ ids: [String]) -> [String] {
            ids.sorted {
                let a = nodes[$0]!, b = nodes[$1]!
                if (a.table == nil) != (b.table == nil) { return a.table == nil }
                if grouping == .person, a.title != b.title {
                    if a.title == "(無)" { return true }; if b.title == "(無)" { return false }
                }
                return a.title < b.title
            }
        }
        roots = ordered(roots)
        for key in Array(nodes.keys) { nodes[key]!.children = ordered(nodes[key]!.children) }
    }
    func region(names: Set<String>, saved: String?) -> String? {
        guard !names.isEmpty else { return nil }
        let ids = Set(names.compactMap { tableIDsByName[$0] })
        guard ids.count == names.count else { return nil }
        if let saved, let node = nodes["g:" + saved], node.ids == ids { return saved }
        return nodes.values.filter { $0.region != nil && $0.ids.count == ids.count && $0.ids == ids }
            .sorted { $0.depth == $1.depth ? $0.region! < $1.region! : $0.depth < $1.depth }.first?.region
    }
    func matches(_ query: String) -> Set<String>? {
        guard !query.isEmpty else { return nil }
        let needle = InterfaceLanguage.text(query, script: "hans")
        return Set(searchText.compactMap { id, text in
            text.localizedStandardContains(needle) ? id : nil
        })
    }
    func rows(expanded: Set<String>, matching: Set<String>?, scope: LanguageSelectionScope) -> [Row] {
        var result = [Row]()
        func visit(_ key: String) {
            guard let node = nodes[key] else { return }
            if node.table != nil && scope != .points { return }
            if let matching, node.ids.isDisjoint(with: matching) { return }
            let ids = (scope == .terminalGroups || scope == .administrativeGroups) ? node.ids : matching.map { node.ids.intersection($0) } ?? node.ids
            let expandable = scope != .topGroups && node.children.contains { scope == .points || nodes[$0]?.table == nil }
            result.append(Row(node: node, ids: ids, expandable: expandable))
            if expandable && expanded.contains(key) { for child in node.children { visit(child) } }
        }
        for root in roots { visit(root) }
        return result
    }
}

// Owned by the selection state, so closing the dropdown does not discard the tree.
@MainActor final class SelectionIndexCache {
    private struct Entry {
        let tables: [TablePackage]
        let grouping: TableGrouping
        let roles: Set<PersonRole>
        let paths: [String: [[String]]]
        let index: SelectionIndex
    }
    private var entries = [Entry]()
    private(set) var builds = 0
    func index(tables: [TablePackage], grouping: TableGrouping, roles: Set<PersonRole>, paths: [String: [[String]]]) -> SelectionIndex {
        if let offset = entries.firstIndex(where: { $0.grouping == grouping && $0.roles == roles && $0.paths == paths && $0.tables == tables }) {
            let entry = entries.remove(at: offset); entries.append(entry)
            return entry.index
        }
        let result = SelectionIndex(tables: tables, grouping: grouping, roles: roles, additionalPaths: paths)
        builds += 1
        entries.append(Entry(tables: tables, grouping: grouping, roles: roles, paths: paths, index: result))
        if entries.count > 4 { entries.removeFirst() }
        return result
    }
}
