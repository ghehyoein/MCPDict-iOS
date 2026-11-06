import SwiftUI

struct SelectionTree: View {
    @Environment(\.tableDownloadStates) private var downloadStates
    @Environment(\.mapLabelSize) private var mapLabelSize
    let tables: [TablePackage]
    let grouping: TableGrouping
    var roles: Set<PersonRole> = Set(PersonRole.allCases)
    var badgeGrouping: TableGrouping? = nil
    var scope: LanguageSelectionScope = .points
    var selectedRegion: Binding<String?> = .constant(nil)
    var filterQuery = ""
    @Binding var selection: Set<String>
    var inspect: ((TablePackage) -> Void)? = nil
    @State private var expanded = Set<String>()
    @State private var index = SelectionIndex()
    @State private var matching: Set<String>?
    @State private var rows = [SelectionIndex.Row]()
    var body: some View {
        // Read a transforming Binding once, not once per node/check state.
        let selected = selection
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                let checked = scope == .terminalGroups ? selectedRegion.wrappedValue == row.node.region : selected.isSuperset(of: row.ids)
                let mixed = scope != .terminalGroups && !selected.isDisjoint(with: row.ids)
                HStack {
                    Button { toggle(row) } label: {
                        Image(systemName: checked ? "checkmark.square.fill" : (mixed ? "minus.square.fill" : "square")).font(.title3)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(ui("選擇") + row.node.title).accessibilityIdentifier("check-" + row.node.title)
                        .accessibilityValue(checked ? "checked" : (mixed ? "mixed" : "unchecked"))
                    if let table = row.node.table {
                        Button { if let inspect { inspect(table) } else { toggle(row) } } label: {
                            LanguageBadge(name: table.name, table: table, grouping: badgeGrouping ?? grouping).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Spacer()
                        if let state = downloadStates[table.id] {
                            Text(ui(state.rawValue)).font(.caption).foregroundStyle(state == .update ? Color.orange : Color.secondary)
                                .accessibilityIdentifier("downloadState-" + table.id)
                        }
                    } else if row.expandable {
                        Button {
                            if !expanded.insert(row.id).inserted { expanded.remove(row.id) }
                            refreshRows()
                        } label: {
                            HStack { Image(systemName: expanded.contains(row.id) ? "chevron.down" : "chevron.right"); Text(ui(row.node.title)).font(mapLabelSize.map { Font.system(size: $0) }); Spacer(); Text("\(row.ids.count)").foregroundStyle(.secondary).padding(.trailing, 12) }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("expand-" + row.node.title)
                            .accessibilityValue(expanded.contains(row.id) ? "expanded" : "collapsed")
                    } else {
                        Button { toggle(row) } label: {
                            HStack { Text(ui(row.node.title)).font(mapLabelSize.map { Font.system(size: $0) }); Spacer(); Text("\(row.ids.count)").foregroundStyle(.secondary).padding(.trailing, 12) }
                        }.buttonStyle(.plain)
                    }
                }.padding(.leading, CGFloat(row.node.depth) * 18).padding(.vertical, 4)
            }
        }.onAppear { rebuild() }
            .onChange(of: tables) { _, _ in rebuild() }
            .onChange(of: grouping) { _, _ in expanded = []; rebuild() }
            .onChange(of: roles) { _, _ in expanded = []; rebuild() }
            .onChange(of: filterQuery) { _, _ in matching = index.matches(filterQuery); refreshRows() }
    }
    private func rebuild() {
        index = SelectionIndex(tables: tables, grouping: grouping, roles: roles)
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
    let tables: [TablePackage]
    @Binding var names: Set<String>
    var initialGrouping: TableGrouping = .atlas
    var scope: LanguageSelectionScope = .points
    var regionCacheKey = ""
    var inspect: ((TablePackage) -> Void)? = nil
    var palette: TableGrouping = .atlas
    var flags = LanguageFlags()
    var fixedAdministrative = false
    let done: () -> Void
    @State private var grouping: TableGrouping = .atlas
    @State private var filter = ""
    @State private var selectedRegion: String?
    @State private var wheel = false
    @State private var roles = Set(PersonRole.allCases)
    @State private var eligible = [TablePackage]()
    private var treeScope: LanguageSelectionScope {
        grouping == .administrative && scope == .points ? .administrativeGroups : scope
    }
    private var choices: [TableGrouping] { TableGrouping.allCases.filter { scope == .points || $0 != .name } }
    private func refresh(prune: Bool) {
        eligible = treeScope.eligible(tables.filter(flags.matches), grouping: grouping, roles: roles)
        let ids = Set(eligible.map(\.name))
        if prune { names = names.intersection(ids) }
        if scope == .terminalGroups {
            let saved = UserDefaults.standard.string(forKey: "regionNode." + regionCacheKey + grouping.rawValue)
            selectedRegion = RegionSelection.restore(tables: eligible, grouping: grouping, names: names, saved: saved, roles: roles)
            if selectedRegion == nil { names = [] }
        }
    }
    private var selection: Binding<Set<String>> {
        Binding(get: { Set(tables.filter { names.contains($0.name) }.map(\.id)) },
                set: { ids in names = Set(tables.filter { ids.contains($0.id) }.map(\.name)) })
    }
    var body: some View {
        VStack(alignment: .leading) {
            TextField(ui("搜尋語言或分區"), text: $filter).textFieldStyle(.roundedBorder)
            if !fixedAdministrative {
                HStack {
                    Button { wheel.toggle() } label: { Text(ui("分類方式") + " · " + ui(grouping.rawValue)) }.accessibilityIdentifier("classificationPickerToggle")
                    if grouping == .person {
                        ForEach(PersonRole.allCases, id: \.self) { role in
                            Button { if !roles.insert(role).inserted { roles.remove(role) } } label: {
                                Label(ui(role.rawValue), systemImage: roles.contains(role) ? "checkmark.square.fill" : "square")
                            }.accessibilityIdentifier("personRole-" + role.rawValue)
                        }
                    }
                }.font(.subheadline).buttonStyle(.borderless)
                if wheel {
                    Picker(ui("分類方式"), selection: $grouping) {
                        ForEach(choices) { Text(ui($0.rawValue)).tag($0) }
                    }.pickerStyle(.wheel).frame(height: 88).clipped()
                }
            }
            ScrollView {
                VStack(alignment: .leading) {
                    SelectionTree(tables: eligible, grouping: grouping, roles: roles, badgeGrouping: palette, scope: treeScope, selectedRegion: $selectedRegion, filterQuery: filter, selection: selection, inspect: inspect)
                }.frame(maxWidth: .infinity).id(grouping.rawValue)
            }.frame(height: wheel ? 130 : 200).accessibilityIdentifier("languageTreeScroll")
            HStack {
                if scope != .terminalGroups {
                    Button(ui("全選")) { names = Set(eligible.map(\.name)) }.accessibilityIdentifier("selectAllLanguages").frame(minWidth: 60, minHeight: 44)
                }
                Spacer(minLength: 32)
                Button(ui("清空")) { names = []; selectedRegion = nil }.accessibilityIdentifier("clearLanguages").frame(minWidth: 60, minHeight: 44)
                Spacer(minLength: 32)
                Button(ui("完成"), action: done).accessibilityIdentifier("finishLanguages")
            }.buttonStyle(.borderless)
        }
            .onAppear {
                if let stored = UserDefaults.standard.stringArray(forKey: "roles." + regionCacheKey) { roles = Set(stored.compactMap(PersonRole.init(rawValue:))) }
                let persisted = UserDefaults.standard.string(forKey: "grouping." + regionCacheKey).flatMap(TableGrouping.init(rawValue:))
                grouping = fixedAdministrative ? .administrative : (persisted.flatMap { choices.contains($0) ? $0 : nil } ?? initialGrouping)
                refresh(prune: flags.island || flags.history)
            }
            .onChange(of: tables) { _, _ in refresh(prune: true) }
            .onChange(of: grouping) { _, new in
                UserDefaults.standard.set(new.rawValue, forKey: "grouping." + regionCacheKey)
                refresh(prune: true)
            }
            .onChange(of: flags) { _, _ in refresh(prune: true) }
            .onChange(of: roles) { _, value in UserDefaults.standard.set(value.map(\.rawValue), forKey: "roles." + regionCacheKey); refresh(prune: true) }
            .onChange(of: selectedRegion) { _, value in UserDefaults.standard.set(value, forKey: "regionNode." + regionCacheKey + grouping.rawValue) }
    }
}

struct FavoriteButton: View {
    @EnvironmentObject var model: AppModel
    let reading: Reading
    @State private var choosing = false
    private var saved: Bool { !model.memberships(reading).isEmpty }
    var body: some View {
        Button { choosing = true } label: { Image(systemName: saved ? "star.fill" : "star") }
            .buttonStyle(.borderless).tint(.orange).accessibilityLabel(ui(saved ? "已收藏" : "加入生字本"))
            .sheet(isPresented: $choosing) { BookPicker(reading: reading) }
    }
}

struct HomophoneResultsView: View {
    @AppStorage("dictionaryPalette") private var palette = "atlas"
    let copy: (String) -> Void
    @EnvironmentObject var model: AppModel
    private var groups: [[Reading]] { model.homophoneGroups() }
    var body: some View {
        ForEach(groups, id: \.first!.id) { rows in
            if let first = rows.first {
                VStack(alignment: .leading, spacing: 8) {
                    Button { model.tableDetail = model.table(named: first.language) } label: { LanguageBadge(name: first.language, table: model.table(named: first.language), grouping: palette == "atlas" ? .atlas : .dictionary) }.buttonStyle(.plain)
                    PronunciationView(raw: first.pronunciation, table: model.table(named: first.language)).font(.title3)
                        .contentShape(Rectangle()).simultaneousGesture(LongPressGesture().onEnded { _ in copy(first.pronunciation) })
                    ForEach(rows) { row in
                        HStack(alignment: .top) {
                            FavoriteButton(reading: row)
                            (Text(row.characters).bold() + Text(row.note.isEmpty ? "" : "  " + row.note)).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}
