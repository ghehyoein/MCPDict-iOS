import SwiftUI

enum TableGrouping: String, CaseIterable, Identifiable {
    case atlas = "地圖集二分區", dictionary = "音典分區", administrative = "行政區劃", name = "字表名稱"
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
                if let catalog = model.catalog {
                    Text(catalog.scope).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    Picker("分類方式", selection: $grouping) {
                        ForEach(TableGrouping.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).padding(.horizontal)
                    TableGroupList(tables: catalog.tables.filter { table in
                        filter.isEmpty || ([table.name, table.fullName] + table.atlas + table.dictionary + table.administrative).contains { $0.localizedStandardContains(filter) }
                    }, grouping: grouping, depth: 0, selection: $selection)
                    .disabled(model.updating)
                    let chosen = catalog.tables.filter { selection.contains($0.id) }
                    let current = Dictionary(uniqueKeysWithValues: (model.installed?.tables ?? []).map { ($0.id, $0.sha256) })
                    let needed = chosen.filter { current[$0.id] != $0.sha256 }
                    let removed = (model.installed?.tables ?? []).filter { !selection.contains($0.id) }.count
                    VStack(spacing: 8) {
                        Text("已選 \(chosen.count) 份 · 需下載 \(ByteCountFormatter.string(fromByteCount: needed.reduce(0) { $0 + $1.size }, countStyle: .file)) · 將移除 \(removed) 份")
                            .font(.caption)
                        Button("套用選擇（下載／更新／移除）") { model.applyTables(selection) }
                            .buttonStyle(.borderedProminent).disabled(model.updating)
                    }.padding()
                } else {
                    ContentUnavailableView("取得字表目錄", systemImage: "list.bullet.rectangle", description: Text("先取得小型目錄，再選擇需要的字表。本版不內置任何字表。"))
                    Button("取得目錄") { Task { await model.loadCatalog() } }.disabled(model.updating)
                }
                Text(model.status).font(.caption).padding(.horizontal)
                if model.updating {
                    ProgressView().padding(6)
                    Button("取消下載", role: .cancel) { model.cancelDownload() }
                }
                Text("只查詢已下載字表；不同分類選到同一字表只下載一份。收藏獨立保存。")
                    .font(.caption2).foregroundStyle(.secondary).padding()
            }
            .navigationTitle("字表下載")
            .searchable(text: $filter, prompt: "搜尋字表、語言或地區")
            .toolbar {
                Menu("更新") {
                    Button("檢查上游目錄") { Task { await model.loadCatalog() } }
                    Button("更新全部已下載字表") { Task { await model.updateInstalledTables() } }
                        .disabled(model.installed?.tables.isEmpty != false)
                }.disabled(model.updating)
            }
            .task {
                await model.start()
                selection = Set(model.installed?.tables.map(\.id) ?? [])
                if model.catalog == nil { await model.loadCatalog() }
            }
            .onChange(of: model.installed?.databaseFile) { _, _ in
                selection = Set(model.installed?.tables.map(\.id) ?? [])
            }
        }
    }
}

struct TableGroupList: View {
    @EnvironmentObject var model: AppModel
    let tables: [TablePackage]
    let grouping: TableGrouping
    let depth: Int
    @Binding var selection: Set<String>
    private var leaves: [TablePackage] { tables.filter { grouping.path($0).count <= depth } }
    private var groups: [String: [TablePackage]] {
        Dictionary(grouping: tables.filter { grouping.path($0).count > depth }) { grouping.path($0)[depth] }
    }
    var body: some View {
        List {
            if !tables.isEmpty {
                Button(selection.isSuperset(of: tables.map(\.id)) ? "取消本頁全部選擇" : "選擇本頁全部字表") {
                    let ids = Set(tables.map(\.id))
                    if selection.isSuperset(of: ids) { selection.subtract(ids) } else { selection.formUnion(ids) }
                }
            }
            ForEach(groups.keys.sorted(), id: \.self) { key in
                let members = groups[key] ?? []
                NavigationLink {
                    TableGroupList(tables: members, grouping: grouping, depth: depth + 1, selection: $selection)
                        .navigationTitle(key).disabled(model.updating)
                } label: {
                    LabeledContent(key, value: "\(members.filter { selection.contains($0.id) }.count)/\(members.count) 份")
                }
            }
            ForEach(leaves.sorted { $0.name < $1.name }) { table in
                Button {
                    if !selection.insert(table.id).inserted { selection.remove(table.id) }
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: selection.contains(table.id) ? "checkmark.circle.fill" : "circle")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(table.name).font(.headline)
                            Text(table.fullName).font(.caption)
                            Text("\(table.isUpstream ? "上游原始字表" : "\(table.recordCount) 條") · \(ByteCountFormatter.string(fromByteCount: table.size, countStyle: .file))").font(.caption)
                            Text(table.administrative.joined(separator: " / ")).font(.caption2)
                            if let installed = model.installed?.tables.first(where: { $0.id == table.id }) {
                                Text(installed.sha256 == table.sha256 ? "已下載" : "可更新").font(.caption).foregroundStyle(.teal)
                            }
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}

struct LanguageGroupList: View {
    let tables: [TablePackage]
    let grouping: TableGrouping
    let depth: Int
    let choose: (String) -> Void
    private var groups: [String: [TablePackage]] {
        Dictionary(grouping: tables.filter { grouping.path($0).count > depth }) { grouping.path($0)[depth] }
    }
    var body: some View {
        List {
            ForEach(groups.keys.sorted(), id: \.self) { key in
                NavigationLink {
                    LanguageGroupList(tables: groups[key] ?? [], grouping: grouping, depth: depth + 1, choose: choose).navigationTitle(key)
                } label: { LabeledContent(key, value: "\(groups[key]?.count ?? 0) 份") }
            }
            ForEach(tables.filter { grouping.path($0).count <= depth }.sorted { $0.name < $1.name }) { table in
                Button(table.name) { choose(table.name) }
            }
        }
    }
}
