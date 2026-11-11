import SwiftUI

struct YindianToolsView: View {
    var tool: BuiltinAnalysisTool = .evolution
    @EnvironmentObject private var model: AppModel
    @StateObject private var selector = LanguageSelectionState(namespace: "evolution")
    @StateObject private var comparisonSelector = LanguageSelectionState(namespace: "comparisonResults")
    @State private var comparisonLanguages = Set<String>()
    @State private var exporting = false
    @State private var evolutionCSV = ""
    @State private var language = ""
    @State private var dimension = "initial"
    @State private var mode = "full"
    @State private var glides = true
    @State private var input = ""
    @State private var choices = [String]()
    @State private var selected = Set<String>()
    @State private var editingComparisonColor: String?
    @State private var resultChars = [String]()
    @State private var units = [ComparisonUnit]()
    @AppStorage(ComparisonPalette.key) private var comparisonColors = ""
    @State private var filters = [String: Set<String>]()
    @State private var filterOptions = [String: [String]]()
    @State private var guangyun = [[String: String]]()
    @State private var evolution = [EvolutionGroup]()
    @State private var comparison = [ComparisonGroup]()
    @State private var search = ""
    @State private var activeFilter: String?
    @State private var draftFilter = Set<String>()
    @State private var resultStatuses: Set<String> = ["same", "partial", "different", "missing"]
    @State private var showMissing = false
    @State private var busy = false
    @State private var error: String?
    @State private var detail: EvolutionGroup?
    @State private var map: ToolMapResult?
    @FocusState private var focused: Bool
    private let dimensions = [("initial","聲母"),("voicing","清濁"),("rime","韻母"),("division","等"),("openness","開合"),("she","攝"),("tone","聲調"),("position","完整音韻地位")]
    private let modes = [("full","完整讀音"),("initial","聲母"),("final","韻母"),("tone","聲調"),("notone","忽略聲調")]
    private let filterKeys = [("voicing","清濁"),("division","等"),("openness","開合"),("she","攝"),("tone","聲調"),("initial","聲母"),("rime","韻母")]
    private var tables: [TablePackage] { model.installed?.tables ?? [] }
    private var comparisonTables: [TablePackage] {
        let names = Set(comparison.map(\.name))
        return tables.filter { names.contains($0.name) }
    }
    private var shownComparisons: [ComparisonGroup] {
        comparison.filter { comparisonLanguages.contains($0.name) && resultStatuses.contains($0.status) && (search.isEmpty || InterfaceLanguage.matches(($0.name + (model.table(named: $0.name)?.fullName ?? "") + (model.table(named: $0.name)?.metadata?["地點"] ?? "")), search)) }
    }
    var body: some View {
        List {
            Section {
                if tool == .evolution {
                    SingleLanguageSelectionPanel(tables: tables, language: $language, state: selector, entryID: "evolutionLanguageSelection")
                    Picker(ui("中古分組維度"), selection: $dimension) {
                        ForEach(dimensions, id: \.0) { Text(ui($0.1)).tag($0.0) }
                    }.pickerStyle(.menu)
                } else {
                    TextField(ui("例如：雞溪低"), text: $input).textFieldStyle(.roundedBorder).focused($focused)
                        .accessibilityIdentifier("compareCharacters")
                    if !choices.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(choices, id: \.self) { char in
                                    Button { if !selected.insert(char).inserted { selected.remove(char) } } label: {
                                        Label(char, systemImage: selected.contains(char) ? "checkmark.square.fill" : "square")
                                    }.buttonStyle(.borderless).accessibilityIdentifier("comparisonChar-" + char)
                                }
                            }
                        }
                    }
                    Button(ui("加入比較單元")) {
                        let unit = ComparisonUnit(choices.filter(selected.contains))
                        guard !unit.characters.isEmpty else { return }
                        units.append(unit); selected = []
                    }.disabled(selected.isEmpty || units.count >= 10).accessibilityIdentifier("addComparisonUnit")
                    if !units.isEmpty {
                        Text(ui("未加入單元的勾選字會各自比較。"))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(units) { unit in
                            HStack {
                                Text(unit.title).foregroundStyle(Color.primary)
                                Spacer()
                                Button(ui("刪除"), role: .destructive) { units.removeAll { $0.id == unit.id } }
                                    .buttonStyle(.borderless).accessibilityIdentifier("removeComparisonUnit-" + unit.title)
                            }
                        }
                    }
                }
                Picker(ui(tool == .evolution ? "今音觀察維度" : "比較方式"), selection: $mode) {
                    ForEach(modes, id: \.0) { Text(ui($0.1)).tag($0.0) }
                }.pickerStyle(.menu)
                Toggle(ui("起首介音歸入韻母"), isOn: $glides)
                Button(ui(tool == .evolution ? "生成對應表" : "開始比較")) { focused = false; Task { await run() } }
                    .disabled(busy).accessibilityIdentifier("runNativeAnalysis")
                if busy { ProgressView() }
                if let error { SystemText(error).foregroundStyle(.red) }
            }.disabled(busy)
            if tool == .evolution { evolutionFilters.disabled(busy); evolutionResults }
            else { comparisonResults }
        }.navigationTitle(ui(tool.title)).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("nativeAnalysisView")
            .task { if tool == .evolution { mode = "initial"; await loadFilters() } }
            .task(id: input) { if tool == .compare { await resolveCharacters() } }
            .onChange(of: dimension) { _, _ in rerun() }
            .onChange(of: mode) { _, _ in rerun() }
            .onChange(of: glides) { _, _ in rerun() }
            .onChange(of: filters) { _, _ in rerun() }
            .sheet(item: $detail) { group in
                NavigationStack {
                    List {
                        Section(ui("音韻地位")) { ForEach(group.subtypes.sorted(), id: \.self) { SystemText($0) } }
                        Section(ui("發音")) { ForEach(group.readings.sorted(), id: \.self) { SystemText($0) } }
                        Section(ui("例字")) { SystemText(group.chars.joined(separator: " ")) }
                    }.navigationTitle(group.oldValue + " → " + group.modernValue)
                        .navigationBarTitleDisplayMode(.inline).toolbar { Button(ui("完成")) { detail = nil } }
                }
            }
            .sheet(isPresented: Binding(get: { activeFilter != nil }, set: { if !$0 { activeFilter = nil } })) {
                if let key = activeFilter {
                    NavigationStack {
                        List {
                            Button(ui("全部")) { draftFilter = [] }
                            ForEach(filterOptions.keys.filter { $0.hasPrefix("group:" + key + ":") }.sorted(), id: \.self) { group in
                                let members = Set(filterOptions[group] ?? [])
                                Button {
                                    if draftFilter.isSuperset(of: members) { draftFilter.subtract(members) }
                                    else { draftFilter.formUnion(members) }
                                } label: {
                                    Label(contentUI(String(group.split(separator: ":").last ?? "")), systemImage: draftFilter.isSuperset(of: members) ? "checkmark.square.fill" : "square")
                                }
                            }
                            ForEach(filterOptions[key] ?? [], id: \.self) { value in
                                Button { if !draftFilter.insert(value).inserted { draftFilter.remove(value) } } label: {
                                    Label(contentUI(value), systemImage: draftFilter.contains(value) ? "checkmark.square.fill" : "square")
                                }.accessibilityIdentifier("filterValue-" + value)
                            }
                        }.navigationTitle(ui(filterKeys.first { $0.0 == key }?.1 ?? "中古條件篩選"))
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button(ui("取消")) { activeFilter = nil } }
                                ToolbarItem(placement: .confirmationAction) { Button(ui("完成")) { filters[key] = draftFilter; activeFilter = nil } }
                            }
                    }
                }
            }
            .navigationDestination(item: $editingComparisonColor) { ComparisonColorEditor(status: $0, storage: $comparisonColors) }
            .sheet(item: $map) { ToolsComparisonMap(points: $0.points) }
            .fileExporter(isPresented: $exporting, document: EvolutionExportDocument(text: evolutionCSV), contentType: .commaSeparatedText, defaultFilename: "MCPDict-correspondences") { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
    }
    private var evolutionFilters: some View {
        Section(ui("中古條件篩選")) {
            WrappingInformationLayout(spacing: 12) {
                ForEach(filterKeys, id: \.0) { key, title in
                    Button {
                        draftFilter = filters[key] ?? []
                        activeFilter = key
                    } label: {
                        HStack(spacing: 4) {
                            Text(ui(title)).foregroundStyle(Color.primary)
                            Text((filters[key] ?? []).isEmpty ? ui("全部") : (filters[key] ?? []).sorted().map(contentUI).joined(separator: "、"))
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                    }.buttonStyle(.borderless).accessibilityIdentifier("evolutionFilter-" + key)
                }
            }
            Button(ui("恢復全部")) { filters = [:] }
        }
    }
    @ViewBuilder private var evolutionResults: some View {
        if !evolution.isEmpty {
            Section {
                Button(ui("匯出對應表"), systemImage: "square.and.arrow.up") { exporting = true }
                    .disabled(busy).accessibilityIdentifier("exportEvolution")
                Text("\(ui("匹配字"))：\(Set(evolution.flatMap(\.chars)).count) · \(ui("對應"))：\(evolution.count) · \(ui("音韻地位"))：\(Set(evolution.flatMap(\.positions)).count)")
                TextField(ui("輸入中古類別、今讀或漢字"), text: $search).textFieldStyle(.roundedBorder)
                ForEach(evolution.filter { search.isEmpty || InterfaceLanguage.matches([$0.oldValue,$0.modernValue,$0.chars.joined(),$0.readings.joined(),$0.subtypes.joined()].joined(), search) }) { group in
                    Button { detail = group } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.oldValue + " → " + group.modernValue).font(.headline)
                            Text("\(ui("字數"))：\(group.chars.count) · \(ui("涉及音韻地位數"))：\(group.positions.count)").foregroundStyle(.secondary)
                            Text(group.chars.prefix(22).joined() + (group.chars.count > 22 ? " … +\(group.chars.count - 22)" : ""))
                            Text(ui("查看詳情")).foregroundStyle(AppAccent.color)
                        }.foregroundStyle(.primary)
                    }.buttonStyle(.borderless)
                }
            }
        }
    }
    @ViewBuilder private var comparisonResults: some View {
        if !comparison.isEmpty {
            Section(ui("語言")) {
                LanguageSelectionPanel(tables: comparisonTables,
                    names: $comparisonLanguages, state: comparisonSelector, entryID: "comparisonLanguageSelection",
                    inspect: { model.tableDetail = $0 }, languageOnly: true)
            }
            Section {
                ForEach(["same","partial","different","missing"], id: \.self) { status in
                    if let sample = comparison.first(where: { $0.status == status }) {
                        HStack {
                        Button {
                            if !resultStatuses.insert(status).inserted { resultStatuses.remove(status) }
                        } label: {
                            HStack {
                                Image(systemName: resultStatuses.contains(status) ? "checkmark.square.fill" : "square")
                                Text(ui(sample.title)).foregroundStyle(Color.primary)
                                Spacer()
                                Text(String(comparison.filter { comparisonLanguages.contains($0.name) && $0.status == status }.count))
                            }
                        }.buttonStyle(.borderless).accessibilityIdentifier("comparisonStatus-" + status)
                        Button { editingComparisonColor = status } label: {
                            Image(systemName: "paintpalette.fill").foregroundStyle(TableColors.color(ComparisonPalette(comparisonColors).color(status)))
                        }.buttonStyle(.borderless).fixedSize().accessibilityLabel(ui("方案顏色")).accessibilityIdentifier("editComparisonColor-" + status)
                        }
                    }
                }
                Toggle(ui("顯示缺資料點"), isOn: $showMissing)
            } header: {
                HStack {
                    Text(ui("比較統計")); Spacer()
                    Button { openMap() } label: { Image(systemName: "map") }
                        .accessibilityLabel(ui("在地圖上顯示")).accessibilityIdentifier("nativeComparisonMap")
                }
            }
            Section(ui("各語言比較結果")) {
                TextField(ui("方言名稱 / 地區"), text: $search).textFieldStyle(.roundedBorder)
                ForEach(shownComparisons) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Button { model.tableDetail = model.table(named: row.name) } label: {
                            LanguageBadge(name: row.name, table: model.table(named: row.name))
                        }.buttonStyle(.borderless).accessibilityIdentifier("comparisonLanguage-" + row.name); Spacer(); Text(ui(row.title)).foregroundStyle(TableColors.color(ComparisonPalette(comparisonColors).color(row.status))) }
                        ForEach(Array(resultChars.enumerated()), id: \.offset) { index, char in
                            SystemText(line(row, index: index, char: char))
                        }
                    }
                }
            }
        }
    }
    private func line(_ row: ComparisonGroup, index: Int, char: String) -> String {
        let raw = row.readings[index].joined(separator: " / "), normal = row.normalized[index].joined(separator: " / ")
        return char + " " + (raw.isEmpty ? "—" : raw) + (mode != "full" && normal != raw && !normal.isEmpty ? "（\(normal)）" : "")
    }
    private func openMap() {
        let points = shownComparisons.filter { showMissing || $0.status != "missing" }.compactMap { row -> DialectPoint? in
            guard let table = model.table(named: row.name), let location = table.location, location.valid else { return nil }
            let text = ui(row.title) + "\n" + resultChars.enumerated().map { line(row, index: $0.offset, char: $0.element) }.joined(separator: "\n")
            return DialectPoint(id: row.name, name: table.fullName, longitude: location.longitude, latitude: location.latitude, color: ComparisonPalette(comparisonColors).color(row.status), reading: "", copyText: text)
        }
        if points.isEmpty { error = ui("當前結果沒有可用的地圖座標。") } else { map = ToolMapResult(points: points) }
    }
    private func rerun() { if !busy && (!comparison.isEmpty || !evolution.isEmpty) { Task { await run() } } }
    private func dialect(_ table: TablePackage) -> [String: Any] {
        ["label":table.name,"language":table.fullName,"toneConfig":table.metadata?["聲調"] ?? ""]
    }
    private func display(_ row: Reading) -> String {
        row.pronunciation.components(separatedBy: "\t").map {
            ToneDisplay.text($0, table: model.table(named: row.language), style: UserDefaults.standard.string(forKey: "toneStyle") ?? "baSheng", pitch: UserDefaults.standard.string(forKey: "pitchStyle") ?? "curve")
        }.joined(separator: "\t")
    }
    private func middleRows() async throws -> [[String: String]] {
        if !guangyun.isEmpty { return guangyun }
        let rows = try await model.repository.toolLanguageRows("廣韻")
        guard !rows.isEmpty else { throw DictionaryFailure(message: ui("請先下載廣韻字表")) }
        let result = rows.compactMap { row -> [String: String]? in
            let f = row.pronunciation.components(separatedBy: "/"); guard f.count > 20 else { return nil }
            return ["charGroup":row.characters,"切韻音系描述":f[18],"攝":f[19],"方音字彙描述":f[20],"廣韻韻目":f.count > 21 ? f[21] : ""]
        }
        guangyun = result; return result
    }
    private func loadFilters() async {
        do {
            let input: [String: Any] = ["kind":"filters","guangyun":try await middleRows()]
            let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
            filterOptions = try JSONDecoder().decode([String:[String]].self, from: data)
        } catch { self.error = error.localizedDescription }
    }
    private func resolveCharacters() async {
        let query = input
        if query.isEmpty { choices = []; selected = []; return }
        do {
            try await Task.sleep(for: .milliseconds(250))
            var found = [String](), defaults = Set<String>()
            let inputs = CharacterResults.characters(query).filter { $0.first.map(GuessLogic.isCharacter) ?? false }
            let expanded = inputs.map(CharacterVariants.expand)
            var seenForms = Set<String>()
            let formsToQuery = expanded.flatMap { $0 }.filter { seenForms.insert($0).inserted }
            let rows = formsToQuery.isEmpty ? [] : try await model.repository.searchAllCharacters(formsToQuery.joined(), language: "")
            let available = Set(rows.flatMap { CharacterResults.characters($0.characters) })
            for (char, forms) in zip(inputs, expanded) {
                let candidates = forms.filter(available.contains)
                let values = candidates.isEmpty ? [char] : candidates
                found.append(contentsOf: values); defaults.insert(values.first ?? char)
            }
            guard !Task.isCancelled, query == input else { return }
            var seen = Set<String>(); choices = found.filter { seen.insert($0).inserted }; selected = defaults
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func run() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            if tool == .evolution {
                guard let table = tables.first(where: { $0.name == language }) else { throw DictionaryFailure(message: ui("請先選擇一種語言。")) }
                let rows = try await model.repository.toolLanguageRows(language)
                let input: [String: Any] = ["kind":"evolution","dialects":[dialect(table)],"guangyun":try await middleRows(),"rows":rows.map { ["漢字":$0.characters,"音標":display($0)] },"dimension":dimension,"mode":mode,"glides":glides,"filters":filters.mapValues { Array($0) }]
                let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
                evolution = try JSONDecoder().decode([EvolutionGroup].self, from: data)
                evolutionCSV = EvolutionExportDocument.csv(groups: evolution, language: table.fullName,
                    dimension: ui(dimensions.first { $0.0 == dimension }?.1 ?? dimension),
                    mode: ui(modes.first { $0.0 == mode }?.1 ?? mode))
                if evolution.isEmpty { error = ui("沒有符合當前中古篩選條件的對應關係。") }
            } else {
                let groups = ComparisonUnit.effective(units, choices: choices, selected: selected)
                guard groups.count >= 2 else { throw DictionaryFailure(message: ui("請至少選擇兩個比較單元。")) }
                guard groups.count <= 10 else { throw DictionaryFailure(message: ui("一次最多比較 10 個單元。")) }
                var seen = Set<String>()
                let chars = groups.flatMap { $0 }.filter { seen.insert($0).inserted }
                let rows = try await model.repository.searchAllCharacters(chars.joined(), language: "")
                let input: [String: Any] = ["kind":"compare","chars":chars,"units":groups,"mode":mode,"glides":glides,"dialects":tables.map(dialect),"rows":rows.map { ["字組":$0.characters,"語言":$0.language,"讀音":display($0)] }]
                let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
                let firstResult = comparison.isEmpty
                comparison = try JSONDecoder().decode([ComparisonGroup].self, from: data); resultChars = groups.map { $0.joined(separator: "＋") }
                if firstResult { comparisonLanguages = Set(comparison.map(\.name)) }
                else { comparisonLanguages.formIntersection(comparison.map(\.name)) }
            }
        } catch { self.error = error.localizedDescription }
    }
}
