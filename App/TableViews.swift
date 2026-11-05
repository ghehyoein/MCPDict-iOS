import SwiftUI

enum TableGrouping: String, CaseIterable, Identifiable {
    case atlas = "地圖集二分區", dictionary = "音典分區", administrative = "行政區劃", name = "語言點"
    var id: String { rawValue }
    func path(_ table: TablePackage) -> [String] {
        switch self {
        case .atlas: return table.atlas
        case .dictionary: return table.dictionary
        case .administrative: return table.administrative
        case .name: return []
        }
    }
}

struct DataView: View {
    @EnvironmentObject var model: AppModel
    @State private var grouping: TableGrouping = .atlas
    @State private var selection = Set<String>()
    @State private var filter = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(ui("分類方式"), selection: $grouping) {
                    ForEach(TableGrouping.allCases) { Text(ui($0.rawValue)).tag($0) }
                }.pickerStyle(.menu).padding(.horizontal)
                if model.catalog != nil || model.installed != nil {
                    TableGroupList(tables: available.filter { table in
                        filter.isEmpty || ([table.name, table.fullName] + table.atlas + table.dictionary + table.administrative).contains { InterfaceLanguage.matches($0, filter) }
                    }, grouping: grouping, depth: 0, selection: $selection)
                } else {
                    Text(ui("尚無字表目錄")).padding()
                    Button(ui("取得目錄")) { Task { await model.loadCatalog() } }.disabled(model.updating)
                    Spacer()
                }
            }
            .navigationTitle(ui("字表"))
            .searchable(text: $filter, prompt: ui("搜尋語言點或地區"))
            .toolbar { Button(ui("更新目錄")) { Task { await model.loadCatalog() } }.disabled(model.updating) }
        }
        // Outside the navigation content: stays on screen at every navigation depth.
        .safeAreaInset(edge: .bottom, spacing: 0) { TableActions(selection: selection) }
        .task { await model.start(); if model.catalog == nil { await model.loadCatalog() } }
    }
    private var available: [TablePackage] {
        var tables = Dictionary(uniqueKeysWithValues: (model.installed?.tables ?? []).map { ($0.id, $0) })
        for table in model.catalog?.tables ?? [] { tables[table.id] = table }
        return Array(tables.values)
    }
}

struct TableActions: View {
    @EnvironmentObject var model: AppModel
    let selection: Set<String>
    private var localSelection: Set<String> { selection.intersection(Set(model.installed?.tables.map(\.id) ?? [])) }
    private var onlineSelection: Set<String> { selection.intersection(Set(model.catalog?.tables.map(\.id) ?? [])) }
    var body: some View {
        VStack(spacing: 8) {
            if model.updating {
                HStack { ProgressView(); Text(ui(model.status)).font(.caption) }
                if model.downloading { Button(ui("取消下載")) { model.cancelDownload() }.accessibilityIdentifier("cancelDownload") }
            } else if !model.status.isEmpty { Text(ui(model.status)).font(.caption).foregroundStyle(.secondary) }
            Text(ui("已選 \(selection.count) 份")).font(.caption)
            HStack {
                Button(ui("字表下載")) { model.downloadTables(onlineSelection) }
                    .buttonStyle(.borderedProminent).disabled(model.updating || onlineSelection.isEmpty)
                    .accessibilityIdentifier("downloadTables")
                Button(ui("字表移除"), role: .destructive) { model.removeTables(localSelection) }
                    .buttonStyle(.bordered).disabled(model.updating || localSelection.isEmpty)
                    .accessibilityIdentifier("removeTables")
            }
        }.frame(maxWidth: .infinity).padding(10).background(.bar)
    }
}

struct TableGroupList: View {
    @EnvironmentObject var model: AppModel
    let tables: [TablePackage]
    let grouping: TableGrouping
    let depth: Int
    @Binding var selection: Set<String>
    @State private var information: TablePackage?
    private var leaves: [TablePackage] { tables.filter { grouping.path($0).count <= depth } }
    private var groups: [String: [TablePackage]] {
        Dictionary(grouping: tables.filter { grouping.path($0).count > depth }) { grouping.path($0)[depth] }
    }
    var body: some View {
        List {
            Text(ui("網上字表 \(model.catalog?.tables.count ?? 0) 份 · 本地字表 \(model.installed?.tables.count ?? 0) 份"))
                .font(.caption).foregroundStyle(.secondary)
            if !tables.isEmpty {
                Button(ui(selection.isSuperset(of: tables.map(\.id)) ? "取消本頁全部選擇" : "選擇本頁全部字表")) {
                    let ids = Set(tables.map(\.id))
                    if selection.isSuperset(of: ids) { selection.subtract(ids) } else { selection.formUnion(ids) }
                }.disabled(model.updating)
            }
            ForEach(groups.keys.sorted(), id: \.self) { key in
                let members = groups[key] ?? []
                NavigationLink {
                    TableGroupList(tables: members, grouping: grouping, depth: depth + 1, selection: $selection).navigationTitle(ui(key))
                } label: { HStack { GroupColorSwatch(tables: members, grouping: grouping); LabeledContent(ui(key), value: ui("\(members.filter { selection.contains($0.id) }.count)/\(members.count) 份")) } }
            }
            ForEach(leaves.sorted { $0.name < $1.name }) { table in
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        if !selection.insert(table.id).inserted { selection.remove(table.id) }
                    } label: {
                        Image(systemName: selection.contains(table.id) ? "checkmark.circle.fill" : "circle").font(.title2)
                    }.buttonStyle(.borderless).disabled(model.updating)
                        .accessibilityLabel(ui("選擇") + table.name)
                    VStack(alignment: .leading, spacing: 4) {
                        Button { information = table } label: { LanguageBadge(name: table.name, table: table, grouping: grouping) }.buttonStyle(.borderless)
                        Text(table.fullName).font(.caption)
                        Text(table.administrative.joined(separator: " / ")).font(.caption2)
                        if let installed = model.installed?.tables.first(where: { $0.id == table.id }) {
                            Text(ui(installed.sha256 == table.sha256 ? "已下載" : "可更新")).font(.caption).foregroundStyle(.teal)
                        }
                    }
                }
            }
        }
        .sheet(item: $information) { TableInfoView(table: $0) }
    }
}

struct LanguageGroupList: View {
    let tables: [TablePackage]
    let grouping: TableGrouping
    let depth: Int
    var title: String = "全部語言"
    let choose: ([String], String) -> Void
    private var groups: [String: [TablePackage]] {
        Dictionary(grouping: tables.filter { grouping.path($0).count > depth }) { grouping.path($0)[depth] }
    }
    var body: some View {
        List {
            Button(ui("選擇本區全部語言") + "（\(tables.count)）") { choose(tables.map(\.name), title) }
                .accessibilityIdentifier("selectWholeRegion")
            ForEach(groups.keys.sorted(), id: \.self) { key in
                let members = groups[key] ?? []
                NavigationLink {
                    LanguageGroupList(tables: members, grouping: grouping, depth: depth + 1, title: key, choose: choose).navigationTitle(ui(key))
                } label: {
                    HStack { GroupColorSwatch(tables: members, grouping: grouping); LabeledContent(ui(key), value: "\(members.count)") }
                }
            }
            ForEach(tables.filter { grouping.path($0).count <= depth }.sorted { $0.name < $1.name }) { table in
                Button { choose([table.name], table.name) } label: { LanguageBadge(name: table.name, table: table, grouping: grouping) }
            }
        }
    }
}
