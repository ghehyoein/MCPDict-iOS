import SwiftUI

struct DialectMapView: View {
    @EnvironmentObject var model: AppModel
    @State private var grouping: TableGrouping = .atlas
    @State private var region = ""
    @State private var filter = ""
    @State private var installedOnly = false
    @State private var character = ""
    @State private var activeCharacter = ""
    @State private var readings = [String: String]()
    @State private var querying = false
    @State private var selected: TablePackage?
    @State private var fit = 0
    private var tables: [TablePackage] { model.catalog?.tables ?? model.installed?.tables ?? [] }
    private var regions: [String] { Array(Set(tables.compactMap { grouping.path($0).first })).sorted() }
    private var points: [DialectPoint] {
        let installed = Set(model.installed?.tables.map(\.id) ?? [])
        return tables.filter {
            (!installedOnly || installed.contains($0.id)) &&
            (region.isEmpty || grouping.path($0).first == region) &&
            (filter.isEmpty || ([$0.name, $0.fullName] + $0.atlas + $0.dictionary + $0.administrative).contains { $0.localizedStandardContains(filter) }) &&
            (activeCharacter.isEmpty || readings[$0.name] != nil)
        }.compactMap { DialectPoint.make($0, grouping: grouping, reading: readings[$0.name] ?? "") }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    Picker("分區", selection: $grouping) {
                        ForEach(TableGrouping.allCases.filter { $0 != .name }) { Text($0.rawValue).tag($0) }
                    }
                    Picker("地區", selection: $region) {
                        Text("全部分區").tag("")
                        ForEach(regions, id: \.self) { Text($0).tag($0) }
                    }
                }.pickerStyle(.menu)
                HStack {
                    TextField("字表名稱／省市縣／分區", text: $filter).textFieldStyle(.roundedBorder)
                    Toggle("已下載", isOn: $installedOnly).fixedSize()
                }.padding(.horizontal)
                HStack {
                    TextField("單字讀音分布", text: $character).textFieldStyle(.roundedBorder)
                    Button("查字") { Task { await query() } }.disabled(querying || model.updating)
                    Button("全部點位") { activeCharacter = ""; readings = [:]; character = "" }
                }.padding(.horizontal)
                Text("\(points.count) 個點位" + (activeCharacter.isEmpty ? " · 依字表檔案經緯度" : " ·「\(activeCharacter)」僅查已下載字表"))
                    .font(.caption).foregroundStyle(.secondary)
                NativeDialectMap(points: points, fit: fit, choose: choose)
                if tables.isEmpty { Text("尚無點位目錄，點右上方更新取得；不會下載字表內容。").font(.caption).padding(.horizontal) }
                if querying || model.updating { ProgressView().padding(4) }
            }
            .navigationTitle("語言地圖").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("全覽", systemImage: "arrow.up.left.and.arrow.down.right") { fit += 1 }
                    Button("更新", systemImage: "arrow.clockwise") { Task { await model.loadCatalog() } }.disabled(model.updating)
                }
            }
            .task { await model.start(); if model.catalog == nil { await model.loadCatalog() } }
            .onChange(of: grouping) { _, _ in region = "" }
            .onChange(of: model.installed?.databaseFile) { _, _ in activeCharacter = ""; readings = [:] }
            .sheet(item: $selected) { table in
                NavigationStack {
                    List {
                        LabeledContent("字表", value: table.fullName)
                        LabeledContent("地圖集二分區", value: table.atlas.joined(separator: " / "))
                        LabeledContent("音典分區", value: table.dictionary.joined(separator: " / "))
                        LabeledContent("行政區劃", value: table.administrative.joined(separator: " / "))
                        if let location = table.location { Text("經度 \(location.longitude) · 緯度 \(location.latitude)") }
                        if let reading = readings[table.name] { LabeledContent(activeCharacter, value: reading).textSelection(.enabled) }
                        Text(model.installed?.tables.contains(where: { $0.id == table.id }) == true ? "已下載，可離線查字" : "尚未下載；到「資料」搜尋此字表即可下載")
                    }.navigationTitle(table.name).toolbar { Button("完成") { selected = nil } }
                }.presentationDetents([.medium, .large])
            }
        }
    }
    private func choose(_ id: String) { selected = tables.first { $0.id == id } }
    @MainActor private func query() async {
        let text = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 1 else { model.error = "請輸入一個漢字（支援擴展區漢字）"; return }
        querying = true
        defer { querying = false }
        do { readings = try await model.repository.mapReadings(text); activeCharacter = text; fit += 1 }
        catch { model.error = error.localizedDescription }
    }
}
