import SwiftUI

struct SelectionTree: View {
    let tables: [TablePackage]
    let grouping: TableGrouping
    var depth = 0
    @Binding var selection: Set<String>
    var inspect: ((TablePackage) -> Void)? = nil
    @State private var expanded = Set<String>()
    var body: some View {
        let groups = Dictionary(grouping: tables.filter { grouping.path($0).count > depth }) { grouping.path($0)[depth] }
        ForEach(groups.keys.sorted(), id: \.self) { key in
            let members = groups[key] ?? []
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    check(Set(members.map(\.id)), label: key)
                    Button { if !expanded.insert(key).inserted { expanded.remove(key) } } label: {
                        HStack { Image(systemName: expanded.contains(key) ? "chevron.down" : "chevron.right"); Text(ui(key)); Spacer(); Text("\(members.count)").foregroundStyle(.secondary) }
                    }.buttonStyle(.plain).accessibilityIdentifier("expand-" + key)
                }
                if expanded.contains(key) {
                    SelectionTree(tables: members, grouping: grouping, depth: depth+1, selection: $selection, inspect: inspect).padding(.leading, 18)
                }
            }.padding(.vertical, 4)
        }
        ForEach(tables.filter { grouping.path($0).count <= depth }.sorted { $0.name < $1.name }) { table in
            HStack {
                check([table.id], label: table.name)
                Button { if let inspect { inspect(table) } else { toggle([table.id]) } } label: {
                    LanguageBadge(name: table.name, table: table, grouping: grouping)
                }.buttonStyle(.plain)
                Spacer()
            }.padding(.vertical, 4)
        }
    }
    private func toggle(_ ids: Set<String>) {
        if selection.isSuperset(of: ids) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }
    private func check(_ ids: Set<String>, label: String) -> some View {
        Button { toggle(ids) } label: {
            Image(systemName: selection.isSuperset(of: ids) ? "checkmark.square.fill" : (selection.isDisjoint(with: ids) ? "square" : "minus.square.fill")).font(.title3)
        }.buttonStyle(.plain).accessibilityLabel(ui("選擇") + label).accessibilityIdentifier("check-" + label)
    }
}

struct LanguageDropdown: View {
    let tables: [TablePackage]
    let initial: Set<String>
    var initialGrouping: TableGrouping = .atlas
    let done: (Set<String>) -> Void
    @State private var selection = Set<String>()
    @State private var grouping: TableGrouping = .atlas
    @State private var filter = ""
    var body: some View {
        VStack(alignment: .leading) {
            TextField(ui("搜尋語言或分區"), text: $filter).textFieldStyle(.roundedBorder)
            Picker(ui("分類方式"), selection: $grouping) {
                ForEach(TableGrouping.allCases) { Text(ui($0.rawValue)).tag($0) }
            }.pickerStyle(.menu)
            ScrollView {
                VStack(alignment: .leading) {
                    SelectionTree(tables: tables.filter { t in filter.isEmpty || ([t.name] + t.atlas + t.dictionary + t.administrative).contains { InterfaceLanguage.matches($0, filter) } }, grouping: grouping, selection: $selection)
                }.frame(maxWidth: .infinity)
            }.frame(maxHeight: 280)
            HStack {
                Button(ui("全選")) { selection = Set(tables.map(\.id)) }
                Button(ui("清空")) { selection = [] }
                Spacer()
                Button(ui("完成")) { done(Set(tables.filter { selection.contains($0.id) }.map(\.name))) }.accessibilityIdentifier("finishLanguages")
            }
        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .onAppear { grouping = initialGrouping; selection = Set(tables.filter { initial.contains($0.name) }.map(\.id)) }
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
