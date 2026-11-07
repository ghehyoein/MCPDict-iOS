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
    @AppStorage(AppTypography.mapKey) private var mapSize = 16.0
    @AppStorage(AppTypography.readingKey) private var readingSize = 16.0
    @EnvironmentObject private var selector: LanguageSelectionState
    private var menuOpen: Bool { get { selector.expanded } nonmutating set { selector.expanded = newValue } }
    @State private var submittedNames = Set<String>()
    @AppStorage("baseMapStyle") private var baseMapStyle = "standard"
    @State private var center = TableLocation(longitude: 108, latitude: 34)
    private var names: Set<String> { Set(model.selectedLanguages ?? model.languages) }
    private var namesBinding: Binding<Set<String>> { Binding(get: { names }, set: { model.selectLanguages($0) }) }
    @State private var character = ""
    @FocusState private var inputFocused: Bool
    @State private var activeCharacter = ""
    @State private var mode: SearchMode = .character
    @State private var result: MapSearchResult?
    @State private var generation = 0
    @State private var querying = false
    @State private var fit = 0
    private var tables: [TablePackage] { model.catalog?.tables ?? model.installed?.tables ?? [] }
    private var colorGrouping: TableGrouping { colorScheme == "dictionary" ? .dictionary : .atlas }
    @State private var points = [DialectPoint]()
    @State private var pointsRevision = UUID()
    @State private var tableByName = [String: TablePackage]()
    private func rebuildMapTables() {
        tableByName = Dictionary(uniqueKeysWithValues: tables.map { ($0.name, $0) })
        rebuildPoints()
    }
    private func rebuildPoints() {
        pointsRevision = UUID()
        let group = result?.groups[activeCharacter] ?? [:]
        let ranks = ResultOrdering.ranks(tables, namespace: "dictionary")
        points = (result == nil ? names : submittedNames).sorted { (ranks[$0] ?? Int.max) < (ranks[$1] ?? Int.max) }.compactMap { name in
            let lines = group[name] ?? []
            guard let table = tableByName[name], result == nil || !lines.isEmpty else { return nil }
            let separator = result?.mode == .note ? "\n" : " / "
            var shown = Set<String>()
            let text = lines.map(\.fullText).filter { shown.insert($0).inserted }.joined(separator: separator)
            guard var point = DialectPoint.make(table, grouping: colorGrouping, reading: text) else { return nil }
            var raw = Set<String>()
            point.copyText = lines.map(\.pronunciation).filter { raw.insert($0).inserted }.joined(separator: " / ")
            if result?.mode == .character {
                point.toneParts = ToneDisplay.parts(text, table: table, style: toneStyle, pitchStyle: pitchStyle)
            } else if result?.mode == .note {
                var parts = [ToneDisplay.Part]()
                for line in lines {
                    if !parts.isEmpty { parts.append(.init(id: parts.count, base: "\n", pitch: "", tone: "", stacked: false)) }
                    parts += ToneDisplay.parts(line.pronunciation, table: table, style: toneStyle, pitchStyle: pitchStyle)
                    parts.append(.init(id: parts.count, base: "  " + line.note, pitch: "", tone: "", stacked: false))
                }
                point.toneParts = parts
            }
            return point
        }
    }
    var body: some View {
        NavigationStack {
            observedContent
                .navigationTitle(ui("語言地圖")).navigationBarTitleDisplayMode(.inline)
                .toolbar { mapToolbar }
                .task { await model.start(); if model.catalog == nil { await model.loadCatalog() } }
                .onChange(of: model.installed?.databaseFile) { _, _ in resetResults() }
        }
    }
    private var observedContent: some View {
        VStack(spacing: 8) {
            Picker(ui("查詢方式"), selection: $mode) {
                ForEach(SearchMode.allCases) { Text(ui($0.rawValue)).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal)
            searchBar
            SelectionMenuButton(count: names.count, entryID: menuOpen ? "" : "mapLanguageSelection", expanded: $selector.expanded)
                .opacity(menuOpen ? 0 : 1).allowsHitTesting(!menuOpen).accessibilityHidden(menuOpen)
                .overlay(alignment: .top) {
                    if menuOpen { menu.fixedSize(horizontal: false, vertical: true).environment(\.mapLabelSize, min(25, max(5, mapSize))) }
                }.padding(.horizontal).zIndex(1)
            mapContent.overlay {
                if menuOpen { Color.clear.contentShape(Rectangle()).onTapGesture { menuOpen = false } }
            }
        }
        .onAppear { rebuildMapTables(); receiveHandoff() }
        .onChange(of: menuOpen) { _, open in if open { inputFocused = false } }
        .onChange(of: model.mapHandoff?.id) { _, _ in receiveHandoff() }
        .onChange(of: tables) { _, _ in rebuildMapTables() }
        .onChange(of: names) { _, _ in if result == nil { rebuildPoints() } }
        .onChange(of: submittedNames) { _, _ in rebuildPoints() }
        .onChange(of: activeCharacter) { _, _ in rebuildPoints() }
        .onChange(of: toneStyle) { _, _ in rebuildPoints() }
        .onChange(of: pitchStyle) { _, _ in rebuildPoints() }
        .onChange(of: colorScheme) { _, _ in rebuildPoints() }
    }
    private var menu: some View {
        LanguageSelectionPanel(tables: model.installed?.tables ?? [], names: namesBinding, state: selector, entryID: "mapLanguageSelection",
                               finished: { Task { await query() } })
    }
    private var mapContent: some View {
        VStack(spacing: 8) {
            if result?.mode == .note { NoteVariantPicker(query: Binding(get: { result?.query ?? "" }, set: { character = $0; mode = .note })) { Task { await query() } }.padding(.horizontal) }
            variantBar
            statusLabel
            NativeDialectMap(points: points, fit: fit, revision: pointsRevision, fontSize: min(25, max(5, mapSize)), readingSize: readingSize, mapStyle: baseMapStyle,
                             centerChanged: { center = $0 }, choose: choose)
            if querying { ProgressView() }
        }
    }
    private var searchBar: some View {
                HStack {
                    TextField(ui(mode == .character ? "請輸入漢字" : mode == .pronunciation ? "請輸入讀音" : "請輸入註釋"), text: $character).textFieldStyle(.roundedBorder).focused($inputFocused).onSubmit { Task { await query() } }
                    Button(ui("查字")) { Task { await query() } }.disabled(querying)
                    Button(ui("清除")) { character = ""; resetResults() }
                }.padding(.horizontal)
    }
    @ViewBuilder private var variantBar: some View {
                if let variants = result?.choices, !variants.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(variants, id: \.self) { variant in
                                Button(variant) { activeCharacter = variant }
                                    .buttonStyle(.bordered).tint(variant == activeCharacter ? AppAccent.color : .gray)
                            }
                        }.padding(.horizontal)
                    }
                }
    }
    private var statusLabel: some View {
                SystemText(ui("\(points.count) 個語言點" + (result.map { " ·「" + (activeCharacter.isEmpty ? $0.query : activeCharacter) + "」僅查已下載字表" } ?? "")), color: .secondaryLabel)
                    .font(.caption).accessibilityIdentifier("mapPointStatus")
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
    private func receiveHandoff() {
        guard let handoff = model.mapHandoff else { return }
        model.mapHandoff = nil
        generation += 1; querying = false; menuOpen = false
        character = handoff.result.query; mode = handoff.result.mode
        submittedNames = handoff.names; result = handoff.result; activeCharacter = handoff.character
        rebuildPoints(); fit += 1
    }
    private func resetResults() {
        generation += 1; querying = false; result = nil; activeCharacter = ""; rebuildPoints()
    }
    @MainActor private func query() async {
        inputFocused = false
        let text = character.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !querying else { return }
        let requestedNames = names, requestedMode = mode
        generation += 1
        let token = generation
        querying = true
        defer { if token == generation { querying = false } }
        do {
            let found = try await model.repository.mapSearch(text, mode: requestedMode, names: requestedNames)
            guard token == generation else { return }
            submittedNames = requestedNames; result = found; activeCharacter = found.choices.first ?? ""
            rebuildPoints(); fit += 1
        } catch { if token == generation { model.error = error.localizedDescription } }
    }
}
