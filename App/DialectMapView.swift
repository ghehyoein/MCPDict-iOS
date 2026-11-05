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
    @State private var names = Set<String>()
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
                LanguageSelectionPanel(tables: tables, names: $names, cacheKey: "map", entryID: "mapLanguageSelection", initialKind: .region, finished: { fit += 1 }).padding(.horizontal)
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
            .task { await model.start(); if model.catalog == nil { await model.loadCatalog() } }
            .onChange(of: model.installed?.databaseFile) { _, _ in activeCharacter = ""; readings = [:]; variants = []; readingsByVariant = [:] }
            .sheet(item: $selected) { TableInfoView(table: $0) }

        }
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
