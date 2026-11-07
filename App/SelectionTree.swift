import SwiftUI

struct SelectionTree: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tableDownloadStates) private var downloadStates
    @Environment(\.mapLabelSize) private var mapLabelSize
    let tables: [TablePackage]
    let grouping: TableGrouping
    var roles: Set<PersonRole> = Set(PersonRole.allCases)
    var badgeGrouping: TableGrouping? = nil
    var scope: LanguageSelectionScope = .points
    var selectedRegion: Binding<String?> = .constant(nil)
    var filterQuery = ""
    var additionalPaths = [String: [[String]]]()
    var inferredTransitionIDs = Set<String>()
    @Binding var selection: Set<String>
    var inspect: ((TablePackage) -> Void)? = nil
    @Binding var expanded: Set<String>
    @State private var index = SelectionIndex()
    @State private var matching: Set<String>?
    @State private var rows = [SelectionIndex.Row]()
    var body: some View {
        // Read a transforming Binding once, not once per node/check state.
        let selected = selection
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                let checked = scope == .terminalGroups ? selectedRegion.wrappedValue == row.node.region : selected.isSuperset(of: row.ids)
                let mixed = scope == .terminalGroups ? RegionSelection.isAncestor(row.node.region, of: selectedRegion.wrappedValue) : !selected.isDisjoint(with: row.ids)
                HStack {
                    Button { toggle(row) } label: {
                        Image(systemName: checked ? "checkmark.square.fill" : (mixed ? "minus.square.fill" : "square")).contentTransition(.identity).transaction { $0.animation = nil; $0.disablesAnimations = true }.font(.title3)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(ui("選擇") + row.node.title).accessibilityIdentifier("check-" + row.node.title)
                        .accessibilityValue(checked ? "checked" : (mixed ? "mixed" : "unchecked"))
                    if let table = row.node.table {
                        Button { if let inspect { inspect(table) } else { model.tableDetail = table } } label: {
                            LanguageBadge(name: table.name, table: table, grouping: badgeGrouping ?? grouping, transitionAsterisk: inferredTransitionIDs.contains(table.id)).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(inferredTransitionIDs.contains(table.id) ? "*" : "")
                        Spacer()
                        if let state = downloadStates[table.id] {
                            Text(ui(state.rawValue)).font(.caption).foregroundStyle(state == .update ? Color.orange : Color.secondary)
                                .accessibilityIdentifier("downloadState-" + table.id)
                        }
                    } else if row.expandable {
                        Button {
                            if !expanded.insert(row.id).inserted { expanded.remove(row.id) }
                        } label: {
                            HStack { Image(systemName: expanded.contains(row.id) ? "chevron.down" : "chevron.right"); Text(ui(row.node.title)); Spacer(); Text("\(row.ids.count)").foregroundStyle(.secondary).padding(.trailing, 12) }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("expand-" + row.node.title)
                            .accessibilityValue(expanded.contains(row.id) ? "expanded" : "collapsed")
                    } else {
                        Button { toggle(row) } label: {
                            HStack { Text(ui(row.node.title)); Spacer(); Text("\(row.ids.count)").foregroundStyle(.secondary).padding(.trailing, 12) }
                        }.buttonStyle(.plain)
                    }
                }.padding(.leading, CGFloat(row.node.depth) * 18).padding(.vertical, 4)
            }
        }.onAppear { rebuild() }
            .onChange(of: tables) { _, _ in rebuild() }
            .onChange(of: grouping) { _, _ in expanded = []; rebuild() }
            .onChange(of: roles) { _, _ in expanded = []; rebuild() }
            .onChange(of: expanded) { _, _ in refreshRows() }
            .onChange(of: additionalPaths) { _, _ in rebuild() }
            .onChange(of: filterQuery) { _, _ in matching = index.matches(filterQuery); refreshRows() }
    }
    private func rebuild() {
        index = SelectionIndex(tables: tables, grouping: grouping, roles: roles, additionalPaths: additionalPaths)
        matching = index.matches(filterQuery)
        refreshRows()
    }
    private func refreshRows() { rows = index.rows(expanded: expanded, matching: matching, scope: scope) }
    private func toggle(_ row: SelectionIndex.Row) {
        if scope == .terminalGroups {
            if selectedRegion.wrappedValue == row.node.region { selection = []; selectedRegion.wrappedValue = nil }
            else { selection = row.ids; selectedRegion.wrappedValue = row.node.region }
        } else {
            var chosen = selection
            if chosen.isSuperset(of: row.ids) { chosen.subtract(row.ids) } else { chosen.formUnion(row.ids) }
            selection = chosen
        }
    }
}

struct LanguageDropdown: View {
    @EnvironmentObject var model: AppModel
    let tables: [TablePackage]
    @Binding var names: Set<String>
    @ObservedObject var state: LanguageSelectionState
    var inspect: ((TablePackage) -> Void)? = nil
    var palette: TableGrouping = .atlas
    var showsDone = true
    let done: () -> Void
    @State private var eligible = [TablePackage]()
    @State private var additionalPaths = [String: [[String]]]()
    @State private var inferredTransitionIDs = Set<String>()
    private var treeScope: LanguageSelectionScope {
        state.grouping == .administrative && state.scope == .points ? .administrativeGroups : state.scope
    }
    private func refresh(prune: Bool, updateRegion: Bool = false) {
        eligible = treeScope.eligible(tables.filter(state.flags.matches), grouping: state.grouping, roles: state.roles)
        let transitions = DictionaryTransitions(tables: model.availableTables)
        let includesTransitions = state.grouping == .dictionary && state.includeTransitions
        additionalPaths = includesTransitions ? transitions.additionalPaths(eligible) : [:]
        inferredTransitionIDs = includesTransitions ? Set(eligible.filter { transitions.needsAsterisk($0) }.map(\.id)) : []
        if prune { names = names.intersection(Set(eligible.map(\.name))) }
        if updateRegion, state.scope == .terminalGroups, let region = state.region {
            let index = SelectionIndex(tables: eligible, grouping: state.grouping, roles: state.roles, additionalPaths: additionalPaths)
            if let ids = index.nodes["g:" + region]?.ids { names = Set(eligible.filter { ids.contains($0.id) }.map(\.name)) }
        }
        restoreRegion()
    }
    private func restoreRegion() {
        guard state.scope == .terminalGroups else { return }
        state.region = RegionSelection.restore(tables: eligible, grouping: state.grouping, names: names, saved: state.region, roles: state.roles, additionalPaths: additionalPaths)
        if state.region == nil, !names.isEmpty { names = [] }
    }
    private var selection: Binding<Set<String>> {
        Binding(get: { Set(tables.filter { names.contains($0.name) }.map(\.id)) },
                set: { ids in names = Set(tables.filter { ids.contains($0.id) }.map(\.name)) })
    }
    var body: some View {
        VStack(alignment: .leading) {
            TextField(ui("搜尋語言或分區"), text: $state.filter).textFieldStyle(.roundedBorder)
            if state.kind != .administrative {
                HStack(spacing: 8) {
                    if state.grouping == .dictionary {
                        Button { state.includeTransitions.toggle() } label: {
                            HStack(spacing: 0) {
                                Image(systemName: state.includeTransitions ? "checkmark.square.fill" : "square")
                                Text(ui("過渡色"))
                            }.fixedSize().contentTransition(.identity)
                                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                        }.buttonStyle(.borderless).accessibilityIdentifier("includeDictionaryTransitions")
                    }
                    if state.grouping == .person {
                        ForEach(PersonRole.allCases, id: \.self) { role in
                            Button { if !state.roles.insert(role).inserted { state.roles.remove(role) } } label: {
                                HStack(spacing: 0) {
                                    Image(systemName: state.roles.contains(role) ? "checkmark.square.fill" : "square")
                                    Text(ui(role.rawValue))
                                }.fixedSize().contentTransition(.identity)
                                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
                            }.buttonStyle(.borderless).accessibilityIdentifier("personRole-" + role.rawValue)
                        }
                    }
                    if state.kind == .region {
                        Picker(ui("分區方式"), selection: $state.grouping) {
                            ForEach([TableGrouping.atlas, .dictionary]) { Text(ui($0.rawValue)).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("regionClassification")
                    } else {
                        Picker(ui("分類方式"), selection: $state.grouping) {
                            ForEach(state.groupingChoices) { Text(ui($0.rawValue)).tag($0) }
                        }.pickerStyle(.navigationLink).accessibilityIdentifier("classificationPickerToggle")
                    }
                }
            }
            ScrollView {
                SelectionTree(tables: eligible, grouping: state.grouping, roles: state.roles, badgeGrouping: palette,
                              scope: treeScope, selectedRegion: $state.region, filterQuery: state.filter, additionalPaths: additionalPaths, inferredTransitionIDs: inferredTransitionIDs,
                              selection: selection, inspect: inspect, expanded: $state.expandedNodes)
                    .frame(maxWidth: .infinity).id(state.grouping.rawValue)
            }.frame(height: 200).accessibilityIdentifier("languageTreeScroll")
            HStack {
                if state.scope != .terminalGroups {
                    Button(ui("全選")) { names = Set(eligible.map(\.name)) }.accessibilityIdentifier("selectAllLanguages").frame(minWidth: 60, minHeight: 44)
                }
                Spacer(minLength: 32)
                Button(ui("清空")) { names = []; state.region = nil }.accessibilityIdentifier("clearLanguages").frame(minWidth: 60, minHeight: 44)
                if showsDone {
                    Spacer(minLength: 32)
                    Button(ui("完成"), action: done).accessibilityIdentifier("finishLanguages")
                }
            }.buttonStyle(.borderless)
        }
        .onAppear { refresh(prune: state.flags.island || state.flags.history) }
        .onChange(of: tables) { _, _ in refresh(prune: true) }
        .onChange(of: state.grouping) { _, _ in refresh(prune: true) }
        .onChange(of: state.includeTransitions) { _, _ in refresh(prune: false, updateRegion: true) }
        .onChange(of: model.availableTables) { _, _ in refresh(prune: false, updateRegion: true) }
        .onChange(of: state.flags) { _, _ in refresh(prune: true) }
        .onChange(of: state.roles) { _, _ in refresh(prune: true) }
        .onChange(of: names) { _, _ in restoreRegion() }
    }
}

struct FavoriteButton: View {
    @EnvironmentObject var model: AppModel
    let reading: Reading
    @State private var choosing = false
    private var saved: Bool { !model.memberships(reading).isEmpty }
    var body: some View {
        Button {
            if UserDefaults.standard.string(forKey: "favoriteAction") == "direct" {
                let ids = FavoritePreferences.targets(in: model.notebook)
                guard !ids.isEmpty else { model.error = "請先在設定中選擇預設生字表"; return }
                model.save(reading, to: ids)
            } else { choosing = true }
        } label: { Image(systemName: saved ? "star.fill" : "star").foregroundStyle(.orange).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel(ui(saved ? "已收藏" : "加入生字本"))
            .sheet(isPresented: $choosing) { BookPicker(reading: reading) }
    }
}

struct HomophoneResultsView: View {
    @AppStorage("colorScheme") private var palette = "atlas"
    @EnvironmentObject var model: AppModel
    private var groups: [[Reading]] { model.homophoneGroups() }
    var body: some View {
        ForEach(groups, id: \.first!.id) { rows in
            if let first = rows.first {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Button { model.tableDetail = model.table(named: first.language) } label: { LanguageBadge(name: first.language, table: model.table(named: first.language), grouping: palette == "atlas" ? .atlas : .dictionary) }.buttonStyle(.plain)
                    PronunciationView(raw: first.pronunciation, table: model.table(named: first.language)).font(.title3)
                        .textSelection(.enabled)
                    ForEach(rows) { row in
                        HStack(alignment: .top) {
                            FavoriteButton(reading: row)
                            SystemText(row.characters + (row.note.isEmpty ? "" : "  " + row.note), boldPrefix: row.characters)
                        }
                    }
                }
            }
        }
    }
}
