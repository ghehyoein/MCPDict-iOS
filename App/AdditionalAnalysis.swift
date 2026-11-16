import SwiftUI
import UniformTypeIdentifiers

struct CorrespondenceLink: Decodable, Identifiable {
    let left: String
    let right: String
    let chars: [String]
    let stage: Int
    init(left: String, right: String, chars: [String], stage: Int = 0) {
        self.left = left; self.right = right; self.chars = chars; self.stage = stage
    }
    var id: String { String(stage) + "\u{0}" + left + "\u{0}" + right }
}
struct SoundClass: Decodable, Identifiable {
    let value: String
    let names: [String]
    var id: String { value }
}

struct AdditionalAnalysisView: View {
    enum Kind: String { case correspondence, soundClasses }
    let kind: Kind
    @EnvironmentObject private var model: AppModel
    @StateObject private var languageSelector = LanguageSelectionState(namespace: "correspondence")
    @State private var languages: Set<String> = {
        let cache = LanguageSelectionCache(), suffix = "." + MapSearchKind.language.rawValue
        return (cache.load("correspondenceLeft" + suffix) ?? []).union(cache.load("correspondenceRight" + suffix) ?? [])
    }()
    @State private var input = ""
    @State private var characters = Set<String>()
    @State private var choices = [String]()
    @State private var mode = "initial"
    @State private var minimumLink = 1
    @State private var minimumNode = 1
    @State private var ignoreMultiple = false
    @State private var links = [CorrespondenceLink]()
    @State private var groups = [SoundClass]()
    @State private var selected = Set<String>()
    @State private var colors = [String: String]()
    @State private var busy = false
    @State private var error: String?
    @State private var map: ToolMapResult?
    @State private var detail: CorrespondenceLink?
    @State private var editingColor: String?
    @State private var exporting = false
    @State private var exportData = Data()
    @State private var exportType: UTType = .commaSeparatedText
    @State private var exportName = "MCPDict-analysis"
    @State private var resultLanguages = [String]()
    @State private var resultMode = ""
    @State private var resultCharacters = [String]()
    @State private var hasResult = false
    private var tables: [TablePackage] { model.installed?.tables ?? [] }
    private var title: String { kind == .correspondence ? "多地對應" : "單字音類" }
    private let palette = ["#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00", "#56B4E9"]
    var body: some View {
        List {
            Section {
                if kind == .correspondence {
                    LanguageSelectionPanel(tables: tables, names: $languages, state: languageSelector,
                        entryID: "correspondenceLanguages", inspect: { model.tableDetail = $0 }, languageOnly: true)
                    Stepper("\(ui("連線最少字數"))：\(minimumLink)", value: $minimumLink, in: 1...50)
                    Stepper("\(ui("節點最少字數"))：\(minimumNode)", value: $minimumNode, in: 1...100)
                    Toggle(ui("忽略多音節讀音"), isOn: $ignoreMultiple)
                } else {
                    TextField(ui("漢字"), text: $input).textFieldStyle(.roundedBorder)
                    if !choices.isEmpty {
                        ScrollView(.horizontal) {
                            HStack { ForEach(choices, id: \.self) { char in
                                Button { if !characters.insert(char).inserted { characters.remove(char) } } label: {
                                    Label(char, systemImage: characters.contains(char) ? "checkmark.square.fill" : "square")
                                }.buttonStyle(.borderless)
                            } }
                        }
                    }
                }
                Picker(ui("今音觀察維度"), selection: $mode) {
                    Text(ui("聲母")).tag("initial")
                    Text(ui("韻母")).tag("final")
                    Text(ui("聲調")).tag("tone")
                    Text(ui("忽略聲調")).tag("notone")
                    Text(ui("完整讀音")).tag("full")
                }
                Button(ui(kind == .correspondence ? "生成桑基圖" : "生成對應表")) { Task { await run() } }
                    .accessibilityIdentifier("runAdditionalAnalysis")
                if busy { ProgressView() }
                if let error { SystemText(error).foregroundStyle(.red).accessibilityIdentifier("additionalAnalysisError") }
            }.disabled(busy)
            if hasResult && links.isEmpty && groups.isEmpty { Text(ui("沒有符合條件的結果。")) }
            if !links.isEmpty || !groups.isEmpty {
                Section {
                    Button(ui("匯出對應表"), systemImage: "square.and.arrow.up") { prepareCSV() }
                        .accessibilityIdentifier("exportAdditionalCSV")
                    if !links.isEmpty {
                        Button(ui("匯出桑基圖圖片"), systemImage: "photo") {
                            exportData = SankeyImageExport.png(links: links, languages: resultLanguages, mode: resultMode)
                            exportType = .png; exportName = "MCPDict-Sankey"; exporting = true
                        }.accessibilityIdentifier("exportSankeyImage")
                    }
                }.disabled(busy)
            }
            if !links.isEmpty {
                Section(ui("桑基圖")) { CorrespondenceDiagram(links: links, languages: resultLanguages) { detail = $0 }.accessibilityIdentifier("correspondenceDiagram") }
                Section(ui("對應")) {
                    ForEach(links) { link in
                        Button { detail = link } label: {
                            VStack(alignment: .leading) {
                                Text(languagePair(link)).font(.caption).foregroundStyle(.secondary)
                                Text(link.left + " → " + link.right)
                                Text("\(ui("字數"))：\(link.chars.count)").foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.borderless)
                    }
                }
            }
            if !groups.isEmpty {
                Section {
                    Button(ui("全部")) { selected = Set(groups.map(\.value)) }.buttonStyle(.borderless)
                    ForEach(groups) { group in
                        HStack {
                            Button { if !selected.insert(group.value).inserted { selected.remove(group.value) } } label: {
                                Label(group.value + " (\(group.names.count))", systemImage: selected.contains(group.value) ? "checkmark.square.fill" : "square")
                            }.buttonStyle(.borderless)
                            Spacer()
                            Button {
                                editingColor = group.value
                            } label: { AnalysisColorSwatch(hex: colors[group.value] ?? palette[0]) }
                                .buttonStyle(.borderless).accessibilityLabel(ui("方案顏色")).accessibilityIdentifier("analysisColor-" + group.value)
                        }
                        DisclosureGroup(ui("語言")) {
                            ForEach(group.names, id: \.self) { name in
                                Button { model.tableDetail = model.table(named: name) } label: { LanguageBadge(name: name, table: model.table(named: name)) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(ui("單字音類")); Spacer()
                        Button { openMap() } label: { Image(systemName: "map") }.accessibilityLabel(ui("在地圖上顯示"))
                    }
                }
            }
        }.navigationTitle(ui(title)).navigationBarTitleDisplayMode(.inline)
            .task(id: input) {
                guard kind == .soundClasses else { return }
                choices = CharacterResults.characters(input).filter { $0.first.map(GuessLogic.isCharacter) ?? false }.prefix(1).flatMap(CharacterVariants.expand)
                characters = Set(choices.prefix(1))
            }
            .sheet(item: $map) { ToolsComparisonMap(points: $0.points, title: title, legend: $0.legend) }
            .sheet(item: $detail) { link in
                NavigationStack {
                    List {
                        SystemText(languagePair(link))
                        SystemText(link.left + " → " + link.right)
                        ForEach(link.chars, id: \.self) { char in AnalysisCharacterRow(character: char) }
                    }.navigationTitle(ui("例字")).toolbar { Button(ui("完成")) { detail = nil } }
                }
            }
            .navigationDestination(item: $editingColor) { key in
                AnalysisColorEditor(initial: colors[key] ?? palette[0]) { colors[key] = $0 }
            }
            .fileExporter(isPresented: $exporting, document: AnalysisResultDocument(data: exportData), contentType: exportType, defaultFilename: exportName) { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
    }
    private func languagePair(_ link: CorrespondenceLink) -> String {
        guard resultLanguages.indices.contains(link.stage), resultLanguages.indices.contains(link.stage + 1) else { return "" }
        return resultLanguages[link.stage] + " → " + resultLanguages[link.stage + 1]
    }
    private func prepareCSV() {
        let csv: String
        if kind == .correspondence {
            csv = AnalysisCSV.correspondences(links, languages: resultLanguages, mode: resultMode)
        } else {
            csv = AnalysisCSV.soundClasses(groups.filter { selected.contains($0.value) }, characters: resultCharacters, mode: resultMode, colors: colors)
        }
        exportData = Data(csv.utf8); exportType = .commaSeparatedText
        exportName = "MCPDict-" + kind.rawValue; exporting = true
    }
    private func run() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            // Preserve catalog order in both the diagram and its exports.
            var seen = Set<String>()
            let chosenTables = tables.filter { languages.contains($0.name) && seen.insert($0.name).inserted }
            let chosenNames = chosenTables.map(\.name)
            if kind == .correspondence && chosenNames.count < 2 { throw DictionaryFailure(message: ui("請至少選擇兩個語言點。")) }
            if kind == .soundClasses && characters.isEmpty { throw DictionaryFailure(message: ui("請輸入漢字。")) }
            var rows = [Reading]()
            if kind == .correspondence {
                for name in chosenNames { rows.append(contentsOf: try await model.repository.toolLanguageRows(name)) }
            } else { rows = try await model.repository.searchAllCharacters(characters.sorted().joined(), language: "") }
            let payload: [String: Any] = ["kind": kind.rawValue, "languages": chosenNames, "characters": characters.sorted(),
                "mode": mode, "minimumLink": minimumLink, "minimumNode": minimumNode, "ignoreMultiple": ignoreMultiple,
                "dialects": tables.map { ["label": $0.name, "toneConfig": $0.metadata?["聲調"] ?? "", "formatKey": ReadingFormatEngine.key(for: $0.name) ?? ""] },
                "rows": rows.map { ["language": $0.language, "characters": $0.characters, "reading": $0.pronunciation] }]
            let result = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: payload))
            if kind == .correspondence { links = try JSONDecoder().decode([CorrespondenceLink].self, from: result) }
            else {
                groups = try JSONDecoder().decode([SoundClass].self, from: result)
                selected = Set(groups.map(\.value))
                for (i, group) in groups.enumerated() where colors[group.value] == nil { colors[group.value] = palette[i % palette.count] }
            }
            resultLanguages = chosenTables.map(\.fullName)
            resultMode = ui(["initial":"聲母", "final":"韻母", "tone":"聲調", "notone":"忽略聲調", "full":"完整讀音"][mode] ?? mode)
            resultCharacters = characters.sorted()
            hasResult = true
        } catch { self.error = error.localizedDescription }
    }
    private func openMap() {
        var byName = [String: [SoundClass]]()
        for group in groups where selected.contains(group.value) { for name in group.names { byName[name, default: []].append(group) } }
        let points = byName.keys.sorted().compactMap { name -> DialectPoint? in
            guard let table = model.table(named: name), let location = table.location, location.valid else { return nil }
            let values = byName[name] ?? []
            return DialectPoint(id: name, name: table.fullName, longitude: location.longitude, latitude: location.latitude,
                color: values.map { colors[$0.value] ?? palette[0] }.joined(separator: ","), reading: values.map(\.value).joined(separator: " / "),
                copyText: resultCharacters.joined(separator: "、") + " " + values.map(\.value).joined(separator: " / "))
        }
        if points.isEmpty { error = ui("當前結果沒有可用的地圖座標。") }
        else { map = ToolMapResult(points: points, legend: groups.filter { selected.contains($0.value) }.map { AnalysisLegend(title: $0.value, color: colors[$0.value] ?? palette[0], names: Set($0.names)) }) }
    }
}

struct AnalysisCharacterRow: View {
    let character: String
    @State private var page: ReferencePage?
    @State private var map: ToolMapResult?
    @EnvironmentObject private var model: AppModel
    var body: some View {
        CharacterReferenceHeader(character: character, show: { page = $0 }, map: {
            Task {
                do {
                    let rows = try await model.repository.searchAllCharacters(character, language: "")
                    let groups = Dictionary(grouping: rows, by: \.language)
                    let points = groups.keys.sorted().compactMap { name -> DialectPoint? in
                        guard let table = model.table(named: name) else { return nil }
                        return DialectPoint.make(table, grouping: .dictionary, reading: (groups[name] ?? []).map(\.pronunciation).joined(separator: " / "))
                    }
                    map = ToolMapResult(points: points)
                } catch { model.error = error.localizedDescription }
            }
        }).sheet(item: $page) { CharacterReferenceDetail(page: $0) }
            .sheet(item: $map) { ToolsComparisonMap(points: $0.points, title: character) }
    }
}

// Each column is one language; adjacent columns share node positions.
struct CorrespondenceDiagram: View {
    let links: [CorrespondenceLink]
    let languages: [String]
    let choose: (CorrespondenceLink) -> Void
    var body: some View {
        let layout = CorrespondenceLayout(links: links, languages: languages)
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.bands.enumerated()), id: \.element.link.id) { index, band in
                    Path(band.path).fill(Color(hue: Double(index % 12) / 12, saturation: 0.65, brightness: 0.8).opacity(0.6))
                        .onTapGesture { choose(band.link) }
                        .accessibilityLabel(band.link.left + " → " + band.link.right + " \(band.link.chars.count)")
                        .accessibilityAddTraits(.isButton)
                }
                ForEach(Array(languages.enumerated()), id: \.offset) { index, name in
                    Text(name).font(.caption.bold()).frame(width: CorrespondenceLayout.columnWidth, alignment: .leading)
                        .offset(x: CorrespondenceLayout.x(index), y: 12)
                }
                ForEach(layout.nodes) { node in
                    Text(node.value).font(.caption).frame(width: CorrespondenceLayout.columnWidth, alignment: .leading)
                        .offset(x: node.rect.minX, y: node.rect.minY)
                }
            }.frame(width: layout.size.width, height: layout.size.height)
        }.frame(height: min(layout.size.height, 500))
    }
}
