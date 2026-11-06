import SwiftUI

struct SelectionTree: View {
    let tables: [TablePackage]
    let grouping: TableGrouping
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
                            LanguageBadge(name: table.name, table: table, grouping: grouping).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Spacer()
                    } else if row.expandable {
                        Button {
                            if !expanded.insert(row.id).inserted { expanded.remove(row.id) }
                            refreshRows()
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
            .onChange(of: filterQuery) { _, _ in matching = index.matches(filterQuery); refreshRows() }
    }
    private func rebuild() {
        index = SelectionIndex(tables: tables, grouping: grouping)
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
    var paletteChanged: (String) -> Void = { _ in }
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
                Picker(ui("分類方式"), selection: Binding(get: { grouping }, set: { value in
                    grouping = value
                    if value != .administrative { paletteChanged(value == .atlas ? "atlas" : "dictionary") }
                })) {
                    ForEach(TableGrouping.allCases) { Text(ui($0.rawValue)).tag($0) }
                }.pickerStyle(.menu)
            }
            ScrollView {
                VStack(alignment: .leading) {
                    SelectionTree(tables: eligible, grouping: grouping, scope: scope, selectedRegion: $selectedRegion, filterQuery: filter, selection: selection, inspect: inspect)
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
        }
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
    private var saved: Bool { model.isSaved(reading) }
    var body: some View {
        Button { model.save(reading) } label: { Image(systemName: saved ? "star.fill" : "star") }
            .buttonStyle(.borderless).tint(.orange).accessibilityLabel(ui(saved ? "已收藏" : "加入生字本"))
    }
}

struct HomophoneResultsView: View {
    @AppStorage("dictionaryPalette") private var palette = "atlas"
    let copy: (String) -> Void
    @EnvironmentObject var model: AppModel
    private var groups: [[Reading]] { model.homophoneGroups() }
    @State private var info: TablePackage?
    var body: some View {
        ForEach(groups, id: \.first!.id) { rows in
            if let first = rows.first {
                VStack(alignment: .leading, spacing: 8) {
                    Button { info = model.table(named: first.language) } label: { LanguageBadge(name: first.language, table: model.table(named: first.language), grouping: palette == "atlas" ? .atlas : .dictionary) }.buttonStyle(.plain)
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
        }.sheet(item: $info) { TableInfoView(table: $0) }
    }
}
