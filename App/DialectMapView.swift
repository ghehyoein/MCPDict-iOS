import SwiftUI

enum MapSearchKind: String, CaseIterable, Identifiable {
    case language = "語言", custom = "自選", region = "分區", administrative = "行政區"
    var id: String { rawValue }
}

struct DialectMapView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("colorScheme") private var colorScheme = "atlas"
    @AppStorage("toneStyle") private var toneStyle = "baSheng"
    @AppStorage("pitchStyle") private var pitchStyle = "curve"
    @AppStorage("fontSize") private var fontSize = 17.0
    @AppStorage("baseMapStyle") private var baseMapStyle = "standard"
    @State private var center = TableLocation(longitude: 108, latitude: 34)
    @State private var kind: MapSearchKind = .region
    @State private var names = Set<String>()
    private var selectionTitle: String { "已選 \(names.count) 個語言點" }
    private let selectionCache = LanguageSelectionCache()
    @State private var showSelection = false
    @State private var character = ""
    @FocusState private var inputFocused: Bool
    @State private var activeCharacter = ""
    @State private var readings = [String: String]()
    @State private var variants = [String]()
    @State private var readingsByVariant = [String: [String: String]]()
    @State private var querying = false
    @State private var selected: TablePackage?
    @State private var fit = 0
    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?
    private var tables: [TablePackage] { model.catalog?.tables ?? model.installed?.tables ?? [] }
    private var grouping: TableGrouping { kind == .administrative ? .administrative : ((kind == .language || kind == .custom) ? .atlas : colorGrouping) }
    private var selectionScope: LanguageSelectionScope { kind == .region ? .terminalGroups : (kind == .administrative ? .topGroups : .points) }
    private var colorGrouping: TableGrouping { colorScheme == "dictionary" ? .dictionary : .atlas }
    private var points: [DialectPoint] {
        tables.filter { names.contains($0.name) && (activeCharacter.isEmpty || readings[$0.name] != nil) }
            .compactMap { table in
                guard var point = DialectPoint.make(table, grouping: colorGrouping, reading: readings[table.name] ?? "") else { return nil }
                point.toneParts = ToneDisplay.parts(point.reading, table: table, style: toneStyle, pitchStyle: pitchStyle)
                return point
            }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker(ui("檢索選項"), selection: $kind) {
                    ForEach(MapSearchKind.allCases) { Text(ui($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal)
                HStack {
                    Button { showSelection.toggle() } label: {
                        HStack { Text(ui(selectionTitle)); Spacer(); Image(systemName: "chevron.down") }
                    }.buttonStyle(.bordered).accessibilityIdentifier("mapLanguageSelection")
                    Picker(ui("分區顏色"), selection: $colorScheme) {
                        Text(ui("地圖集二")).tag("atlas")
                        Text(ui("音典分區")).tag("dictionary")
                    }.pickerStyle(.menu)
                }.padding(.horizontal)
                if kind == .custom { Text(ui("自選功能後續待更新，目前與語言模式相同")).font(.caption).foregroundStyle(.secondary) }
                if showSelection {
                    LanguageDropdown(tables: tables, names: Binding(get: { names }, set: { saveSelection($0) }), initialGrouping: grouping, scope: selectionScope) {
                        showSelection = false; fit += 1
                    }.id(kind.rawValue + grouping.rawValue).padding(.horizontal)
                }
                HStack {
                    TextField(ui("請輸入單字"), text: $character).textFieldStyle(.roundedBorder).focused($inputFocused).onSubmit { Task { await query() } }
                    Button(ui("查字")) { Task { await query() } }.disabled(querying || model.updating)
                    Button(ui("清除")) { activeCharacter = ""; readings = [:]; character = ""; variants = []; readingsByVariant = [:] }
                }.padding(.horizontal)
                if variants.count > 1 {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(variants, id: \.self) { variant in
                                Button(variant) { activeCharacter = variant; readings = readingsByVariant[variant] ?? [:] }
                                    .buttonStyle(.bordered).tint(variant == activeCharacter ? .teal : .gray)
                            }
                        }.padding(.horizontal)
                    }
                }
                Text(copied ? ui("已複製到剪貼版") : ui("\(points.count) 個語言點" + (activeCharacter.isEmpty ? "" : " ·「\(activeCharacter)」僅查已下載字表")))
                    .font(.caption).foregroundStyle(copied ? Color.orange : Color.secondary).accessibilityIdentifier("mapPointStatus")
                NativeDialectMap(points: points, fit: fit, fontSize: fontSize, mapStyle: baseMapStyle, centerChanged: { center = $0 }, copied: {
                    copied = true; copyTask?.cancel()
                    copyTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { copied = false } }
                }, choose: choose)
                if querying { ProgressView() }
            }
            .navigationTitle(ui("語言地圖")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker(ui("底圖"), selection: $baseMapStyle) {
                            ForEach(BaseMapStyle.allCases) { Text(ui($0.title)).tag($0.rawValue) }
                        }
                        ExternalMapMenu(location: center, name: ui("地圖中心"))
                    } label: { Image(systemName: "map") }
                    Button(ui("全覽"), systemImage: "arrow.up.left.and.arrow.down.right") { fit += 1 }
                    Button(ui("更新"), systemImage: "arrow.clockwise") { Task { await model.loadCatalog() } }.disabled(model.updating)
                }
            }
            .task { await model.start(); if model.catalog == nil { await model.loadCatalog() }; restoreSelection() }
            .onChange(of: kind) { _, _ in restoreSelection() }
            .onChange(of: colorScheme) { _, _ in if kind == .region { restoreSelection() } }
            .onChange(of: model.installed?.databaseFile) { _, _ in activeCharacter = ""; readings = [:]; variants = []; readingsByVariant = [:] }
            .sheet(item: $selected) { TableInfoView(table: $0) }

        }
    }
    private func saveSelection(_ chosen: Set<String>) {
        names = chosen
        selectionCache.save(chosen, for: "map." + kind.rawValue)
    }
    private func restoreSelection() {
        names = []
        let available = Set(selectionScope.eligible(tables, grouping: grouping).map(\.name))
        names = (selectionCache.load("map." + kind.rawValue) ?? []).intersection(available)
        fit += 1
    }
    private func choose(_ id: String) { selected = tables.first { $0.id == id } }
    @MainActor private func query() async {
        inputFocused = false
        let text = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 1 else { model.error = "請輸入一個漢字（支援擴展區漢字）"; return }
        querying = true
        defer { querying = false }
        do {
            let expanded = CharacterVariants.expand(text)
            var found = [String: [String: String]]()
            for variant in expanded { found[variant] = try await model.repository.mapReadings(variant) }
            variants = expanded; readingsByVariant = found
            activeCharacter = text; readings = found[text] ?? [:]; fit += 1
        }
        catch { model.error = error.localizedDescription }
    }
}

struct MapLanguageSelector: View {
    @Environment(\.dismiss) private var dismiss
    let tables: [TablePackage]
    let grouping: TableGrouping
    let custom: Bool
    let initial: Set<String>
    let choose: (Set<String>?, String) -> Void
    @State private var selection = Set<String>()
    @State private var filter = ""
    @State private var customGrouping: TableGrouping = .atlas
    var body: some View {
        NavigationStack {
            VStack {
                if custom {
                    Picker(ui("分類方式"), selection: $customGrouping) {
                        ForEach(TableGrouping.allCases) { Text(ui($0.rawValue)).tag($0) }
                    }.pickerStyle(.menu)
                }
                let filtered = tables.filter { table in filter.isEmpty || ([table.name, table.fullName] + table.atlas + table.dictionary + table.administrative).contains { InterfaceLanguage.matches($0, filter) } }
                if custom {
                    CustomLanguageList(tables: filtered, grouping: customGrouping, depth: 0, selection: $selection)
                } else {
                    LanguageGroupList(tables: filtered, grouping: grouping, depth: 0) { names, title in choose(Set(names), title); dismiss() }
                }
            }
            .searchable(text: $filter, prompt: ui("搜尋語言點或分區"))
            .navigationTitle(ui("選擇語言"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(ui("全部")) { choose(nil, "全部語言"); dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(ui("完成")) {
                    if custom { choose(selection, "已選 \(selection.count) 個語言點") }; dismiss()
                } }
            }
        }.onAppear { selection = initial }
    }
}

struct CustomLanguageList: View {
    let tables: [TablePackage]
    let grouping: TableGrouping
    let depth: Int
    @Binding var selection: Set<String>
    var body: some View {
        List {
            Button(ui("選擇本區全部語言")) { selection.formUnion(tables.map(\.name)) }
            Button(ui("取消本區全部選擇")) { selection.subtract(tables.map(\.name)) }
            let groups = Dictionary(grouping: tables.filter { grouping.path($0).count > depth }) { grouping.path($0)[depth] }
            ForEach(groups.keys.sorted(), id: \.self) { key in
                NavigationLink {
                    CustomLanguageList(tables: groups[key] ?? [], grouping: grouping, depth: depth+1, selection: $selection).navigationTitle(ui(key))
                } label: { HStack { GroupColorSwatch(tables: groups[key] ?? [], grouping: grouping); Text(ui(key)) } }
            }
            ForEach(tables.filter { grouping.path($0).count <= depth }.sorted { $0.name < $1.name }) { table in
                Button { if !selection.insert(table.name).inserted { selection.remove(table.name) } } label: {
                    HStack { Image(systemName: selection.contains(table.name) ? "checkmark.circle.fill" : "circle"); LanguageBadge(name: table.name, table: table, grouping: grouping) }
                }
            }
        }
    }
}
