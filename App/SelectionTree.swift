import SwiftUI

struct SelectionTree: View {
    let tables: [TablePackage]
    let grouping: TableGrouping
    var scope: LanguageSelectionScope = .points
    var depth = 0
    var nodePath = [String]()
    var selectedRegion: Binding<String?> = .constant(nil)
    var regionTables: [TablePackage] = []
    @Binding var selection: Set<String>
    var inspect: ((TablePackage) -> Void)? = nil
    @State private var expanded = Set<String>()
    var body: some View {
        let groups = Dictionary(grouping: tables.filter { grouping.path($0).count > depth }) { grouping.path($0)[depth] }
        VStack(alignment: .leading, spacing: 8) {
        ForEach(groups.keys.sorted(), id: \.self) { key in
            let members = groups[key] ?? []
            let fullRegion = nodePath + [key]
            let selectable = scope == .terminalGroups ? regionTables.filter { grouping.path($0).starts(with: fullRegion) } : members
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    check(Set(selectable.map(\.id)), label: key, region: (nodePath + [key]).joined(separator: "\u{0}"))
                    if scope == .topGroups || (scope == .terminalGroups && !members.contains(where: { grouping.path($0).count > depth + 1 })) {
                        Button { toggle(Set(selectable.map(\.id)), region: (nodePath + [key]).joined(separator: "\u{0}")) } label: { HStack { Text(ui(key)); Spacer(); Text("\(members.count)").foregroundStyle(.secondary) } }.buttonStyle(.plain)
                    } else {
                    Button { if !expanded.insert(key).inserted { expanded.remove(key) } } label: {
                        HStack { Image(systemName: expanded.contains(key) ? "chevron.down" : "chevron.right"); Text(ui(key)); Spacer(); Text("\(members.count)").foregroundStyle(.secondary) }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("expand-" + key)
                        .accessibilityValue(expanded.contains(key) ? "expanded" : "collapsed")
                    }
                }
                if scope != .topGroups && expanded.contains(key) {
                    SelectionTree(tables: members, grouping: grouping, scope: scope, depth: depth+1, nodePath: nodePath + [key], selectedRegion: selectedRegion, regionTables: regionTables, selection: $selection, inspect: inspect).padding(.leading, 18)
                }
            }.padding(.vertical, 4).id((nodePath + [key]).joined(separator: "\u{0}"))
        }
        ForEach(tables.filter { scope == .points && grouping.path($0).count <= depth }.sorted { $0.name < $1.name }) { table in
            HStack {
                check([table.id], label: table.name)
                Button { if let inspect { inspect(table) } else { toggle([table.id]) } } label: {
                    LanguageBadge(name: table.name, table: table, grouping: grouping)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer()
            }.padding(.vertical, 4)
        }
        }
    }
    private func toggle(_ ids: Set<String>, region: String? = nil) {
        if scope == .terminalGroups {
            if selectedRegion.wrappedValue == region { selection = []; selectedRegion.wrappedValue = nil }
            else { selection = ids; selectedRegion.wrappedValue = region }
            return
        }
        if selection.isSuperset(of: ids) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }
    private func check(_ ids: Set<String>, label: String, region: String? = nil) -> some View {
        let checked = scope == .terminalGroups ? selectedRegion.wrappedValue == region : selection.isSuperset(of: ids)
        let mixed = scope != .terminalGroups && !selection.isDisjoint(with: ids)
        return Button { toggle(ids, region: region) } label: {
            Image(systemName: checked ? "checkmark.square.fill" : (mixed ? "minus.square.fill" : "square")).font(.title3)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(ui("選擇") + label).accessibilityIdentifier("check-" + label)
            .accessibilityValue(checked ? "checked" : (mixed ? "mixed" : "unchecked"))
    }
}

struct LanguageDropdown: View {
    let tables: [TablePackage]
    @Binding var names: Set<String>
    var initialGrouping: TableGrouping = .atlas
    var scope: LanguageSelectionScope = .points
    var regionCacheKey = ""
    var inspect: ((TablePackage) -> Void)? = nil
    let done: () -> Void
    @State private var grouping: TableGrouping = .atlas
    @State private var filter = ""
    @State private var selectedRegion: String?
    private var eligible: [TablePackage] { scope.eligible(tables, grouping: grouping) }
    private var selection: Binding<Set<String>> {
        Binding(get: { Set(tables.filter { names.contains($0.name) }.map(\.id)) },
                set: { ids in names = Set(tables.filter { ids.contains($0.id) }.map(\.name)) })
    }
    var body: some View {
        VStack(alignment: .leading) {
            TextField(ui("搜尋語言或分區"), text: $filter).textFieldStyle(.roundedBorder)
            if scope == .points {
                Picker(ui("分類方式"), selection: $grouping) {
                    ForEach(TableGrouping.allCases) { Text(ui($0.rawValue)).tag($0) }
                }.pickerStyle(.menu)
            }
            ScrollView {
                VStack(alignment: .leading) {
                    SelectionTree(tables: eligible.filter { t in filter.isEmpty || ([t.name] + t.atlas + t.dictionary + t.administrative).contains { InterfaceLanguage.matches($0, filter) } }, grouping: grouping, scope: scope, selectedRegion: $selectedRegion, regionTables: eligible, selection: selection, inspect: inspect)
                }.frame(maxWidth: .infinity).id(grouping.rawValue)
            }.frame(height: 240).accessibilityIdentifier("languageTreeScroll")
            HStack {
                if scope != .terminalGroups {
                    Button(ui("全選")) { names = Set(eligible.map(\.name)) }.accessibilityIdentifier("selectAllLanguages").frame(minWidth: 60, minHeight: 44)
                }
                Spacer(minLength: 32)
                Button(ui("清空")) { names = []; selectedRegion = nil }.accessibilityIdentifier("clearLanguages").frame(minWidth: 60, minHeight: 44)
                Spacer(minLength: 32)
                Button(ui("完成"), action: done).accessibilityIdentifier("finishLanguages")
            }.buttonStyle(.borderless)
        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .onAppear {
                grouping = initialGrouping
                if scope == .terminalGroups {
                    let saved = UserDefaults.standard.string(forKey: "regionNode." + regionCacheKey)
                    selectedRegion = RegionSelection.restore(tables: eligible, grouping: grouping, names: names, saved: saved)
                    if selectedRegion == nil { names = [] }
                }
            }
            .onChange(of: selectedRegion) { _, value in UserDefaults.standard.set(value, forKey: "regionNode." + regionCacheKey) }
    }
}

struct FavoriteButton: View {
    @EnvironmentObject var model: AppModel
    let reading: Reading
    private var saved: Bool { model.favorites.contains { $0.reading.characters == reading.characters && $0.reading.language == reading.language && $0.reading.pronunciation == reading.pronunciation && $0.reading.note == reading.note } }
    var body: some View {
        Button { model.save(reading) } label: { Image(systemName: saved ? "star.fill" : "star") }
            .buttonStyle(.borderless).tint(.orange).accessibilityLabel(ui(saved ? "已收藏" : "加入生字本"))
    }
}

struct HomophoneResultsView: View {
    @EnvironmentObject var model: AppModel
    private var groups: [[Reading]] {
        var order = [String](), map = [String: [Reading]]()
        for reading in model.results {
            let key = reading.language + "\u{0}" + reading.pronunciation
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(reading)
        }
        return order.compactMap { map[$0] }
    }
    @State private var info: TablePackage?
    var body: some View {
        ForEach(groups, id: \.first!.id) { rows in
            if let first = rows.first {
                VStack(alignment: .leading, spacing: 8) {
                    Button { info = model.table(named: first.language) } label: { LanguageBadge(name: first.language, table: model.table(named: first.language)) }.buttonStyle(.plain)
                    PronunciationView(raw: first.pronunciation, table: model.table(named: first.language)).font(.title3)
                    ForEach(rows) { row in
                        HStack(alignment: .top) {
                            FavoriteButton(reading: row)
                            (Text(row.characters).bold() + Text(row.note.isEmpty ? "" : "  " + row.note)).textSelection(.enabled)
                        }
                    }
                }
            }
        }.sheet(item: $info) { TableInfoView(table: $0) }
    }
}
