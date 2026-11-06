import SwiftUI

enum MapSearchKind: String, CaseIterable, Identifiable {
    case language = "語言", custom = "自選", region = "分區", administrative = "行政區"
    var id: String { rawValue }
}

struct DialectMapView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("mapPalette") private var colorScheme = "atlas"
    @AppStorage("toneStyle") private var toneStyle = "baSheng"
    @AppStorage("pitchStyle") private var pitchStyle = "curve"
    @AppStorage(AppTypography.mapKey) private var mapSize = 16.0
    @AppStorage(AppTypography.readingKey) private var readingSize = 16.0
    @State private var menuOpen = false
    @State private var submittedNames = Set<String>()
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
    @State private var fit = 0
    @StateObject private var feedback = CopyFeedback()
    private var tables: [TablePackage] { model.catalog?.tables ?? model.installed?.tables ?? [] }
    private var colorGrouping: TableGrouping { colorScheme == "dictionary" ? .dictionary : .atlas }
    @State private var points = [DialectPoint]()
    @State private var tableByName = [String: TablePackage]()
    private func rebuildMapTables() {
        tableByName = Dictionary(uniqueKeysWithValues: tables.map { ($0.name, $0) })
        rebuildPoints()
    }
    private func rebuildPoints() {
        points = (activeCharacter.isEmpty ? names : submittedNames).sorted().compactMap { name in
            guard let table = tableByName[name], activeCharacter.isEmpty || readings[name] != nil,
                  var point = DialectPoint.make(table, grouping: colorGrouping, reading: readings[name] ?? "") else { return nil }
            point.toneParts = ToneDisplay.parts(point.reading, table: table, style: toneStyle, pitchStyle: pitchStyle)
            return point
        }
    }
    var body: some View {
        NavigationStack {
            observedContent
                .navigationTitle(ui("語言地圖")).navigationBarTitleDisplayMode(.inline)
                .toolbar { mapToolbar }
                .task { await model.start(); if model.catalog == nil { await model.loadCatalog() } }
                .onChange(of: model.installed?.databaseFile) { _, _ in activeCharacter = ""; readings = [:]; variants = []; readingsByVariant = [:] }
        }
    }
    private var observedContent: some View {
        VStack(spacing: 8) {
            menu.environment(\.mapLabelSize, min(25, max(5, mapSize))).padding(.horizontal).zIndex(1)
            mapContent.overlay {
                if menuOpen { Color.clear.contentShape(Rectangle()).onTapGesture { menuOpen = false } }
            }
        }
        .onAppear { rebuildMapTables() }
        .onChange(of: tables) { _, _ in rebuildMapTables() }
        .onChange(of: names) { _, _ in if activeCharacter.isEmpty { rebuildPoints() } }
        .onChange(of: submittedNames) { _, _ in rebuildPoints() }
        .onChange(of: readings) { _, _ in rebuildPoints() }
        .onChange(of: activeCharacter) { _, _ in rebuildPoints() }
        .onChange(of: toneStyle) { _, _ in rebuildPoints() }
        .onChange(of: pitchStyle) { _, _ in rebuildPoints() }
        .onChange(of: colorScheme) { _, _ in rebuildPoints() }
    }
    private var menu: some View {
        LanguageSelectionPanel(tables: tables, names: $names, cacheKey: "map", entryID: "mapLanguageSelection", initialKind: .region,
                               floats: true, colorScheme: $colorScheme, expanded: $menuOpen)
    }
    private var mapContent: some View {
        VStack(spacing: 8) {
            searchBar
            variantBar
            statusLabel
            NativeDialectMap(points: points, fit: fit, fontSize: min(25, max(5, mapSize)), readingSize: readingSize, mapStyle: baseMapStyle,
                             centerChanged: { center = $0 }, copied: didCopy, choose: choose)
            if querying { ProgressView() }
        }
    }
    private func didCopy() {
        feedback.show()
    }
    private var searchBar: some View {
                HStack {
                    TextField(ui("請輸入單字"), text: $character).textFieldStyle(.roundedBorder).focused($inputFocused).onSubmit { Task { await query() } }
                    Button(ui("查字")) { Task { await query() } }.disabled(querying || model.updating)
                    Button(ui("清除")) { activeCharacter = ""; readings = [:]; character = ""; variants = []; readingsByVariant = [:] }
                }.padding(.horizontal)
    }
    @ViewBuilder private var variantBar: some View {
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
    }
    private var statusLabel: some View {
                Text(feedback.visible ? ui("已複製到剪貼版") : ui("\(points.count) 個語言點" + (activeCharacter.isEmpty ? "" : " ·「\(activeCharacter)」僅查已下載字表")))
                    .font(.caption).foregroundStyle(feedback.visible ? Color.orange : Color.secondary).accessibilityIdentifier("mapPointStatus")
    }
    @ToolbarContentBuilder private var mapToolbar: some ToolbarContent {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker(ui("底圖"), selection: $baseMapStyle) {
                            ForEach(BaseMapStyle.allCases) { Text(ui($0.title)).tag($0.rawValue) }
                        }
                        ExternalMapMenu(location: center, name: ui("地圖中心"))
                    } label: { Image(systemName: "map") }.simultaneousGesture(TapGesture().onEnded { menuOpen = false })
                    Button(ui("全覽"), systemImage: "arrow.up.left.and.arrow.down.right") { menuOpen = false; fit += 1 }
                    Button(ui("更新"), systemImage: "arrow.clockwise") { menuOpen = false; Task { await model.loadCatalog() } }.disabled(model.updating)
                }
    }
    private func choose(_ id: String) { model.tableDetail = tables.first { $0.id == id } }
    @MainActor private func query() async {
        inputFocused = false
        let text = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 1 else { model.error = "請輸入一個漢字（支援擴展區漢字）"; return }
        let requestedNames = names
        querying = true
        defer { querying = false }
        do {
            let expanded = await Task.detached(priority: .userInitiated) { CharacterVariants.expand(text) }.value
            let found = try await model.repository.mapReadingsForVariants(expanded)
            submittedNames = requestedNames; variants = expanded; readingsByVariant = found
            activeCharacter = text; readings = found[text] ?? [:]; fit += 1
        }
        catch { model.error = error.localizedDescription }
    }
}
