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
    @State private var information: TablePackage?
    private var available: [TablePackage] {
        var map = Dictionary(uniqueKeysWithValues: (model.installed?.tables ?? []).map { ($0.id, $0) })
        for table in model.catalog?.tables ?? [] { map[table.id] = table }
        return Array(map.values)
    }
    var body: some View {
        NavigationStack {
            List {
                Picker(ui("分類方式"), selection: $grouping) {
                    ForEach(TableGrouping.allCases) { Text(ui($0.rawValue)).tag($0) }
                }
                Text(ui("網上字表 \(model.catalog?.tables.count ?? 0) 份 · 本地字表 \(model.installed?.tables.count ?? 0) 份")).font(.caption)
                SelectionTree(tables: available.filter { t in filter.isEmpty || ([t.name] + t.atlas + t.dictionary + t.administrative).contains { InterfaceLanguage.matches($0, filter) } }, grouping: grouping, selection: $selection, inspect: { information = $0 })
                    .id(grouping.rawValue).disabled(model.updating)
                if model.updating {
                    HStack { ProgressView(); Text(ui(model.status)).font(.caption) }
                }
            }
            .navigationTitle(ui("字表")).navigationBarTitleDisplayMode(.large)
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: ui("搜尋語言點或地區"))
            .toolbar {
                Button(ui("全選")) { selection = Set(available.map(\.id)) }.disabled(model.updating).accessibilityIdentifier("selectAllTables")
                Button(ui("清空")) { selection = [] }.disabled(model.updating)
                Button(ui("更新目錄")) { Task { await model.loadCatalog() } }.disabled(model.updating) }
            .safeAreaInset(edge: .bottom, spacing: 0) { TableActions(selection: selection) }
            .sheet(item: $information) { TableInfoView(table: $0) }
        }.task { await model.start(); if model.catalog == nil { await model.loadCatalog() } }
    }
}

struct TableActions: View {
    @EnvironmentObject var model: AppModel
    let selection: Set<String>
    var body: some View {
        let online = selection.intersection(Set(model.catalog?.tables.map(\.id) ?? []))
        let local = selection.intersection(Set(model.installed?.tables.map(\.id) ?? []))
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Text(ui(model.downloading ? "已下載 \(model.downloadedCount) 份" : "已選 \(selection.count) 份")).foregroundStyle(.white).accessibilityIdentifier("downloadCount")
            if model.downloading {
                Button(ui("取消下載")) { model.cancelDownload() }.accessibilityIdentifier("cancelDownload")
            } else {
                Button(ui("字表下載")) { model.downloadTables(online) }.disabled(model.updating || online.isEmpty).accessibilityIdentifier("downloadTables")
            }
            Button(ui("字表移除"), role: .destructive) { model.removeTables(local) }.disabled(model.updating || local.isEmpty).accessibilityIdentifier("removeTables")
        }.font(.subheadline).buttonStyle(.bordered).padding(.horizontal, 10).padding(.vertical, 4)
            .background(.ultraThinMaterial).background(Color.black.opacity(0.45))
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
