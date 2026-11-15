import SwiftUI

struct CorrespondenceLink: Decodable, Identifiable {
    let left: String
    let right: String
    let chars: [String]
    var id: String { left + "\u{0}" + right }
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
    @StateObject private var leftSelector = LanguageSelectionState(namespace: "correspondenceLeft")
    @StateObject private var rightSelector = LanguageSelectionState(namespace: "correspondenceRight")
    @State private var left = ""
    @State private var right = ""
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
    @State private var draftColor = Color.teal
    @State private var hasResult = false
    private var tables: [TablePackage] { model.installed?.tables ?? [] }
    private var title: String { kind == .correspondence ? "兩地對應" : "單字音類" }
    private let palette = ["#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00", "#56B4E9"]
    var body: some View {
        List {
            Section {
                if kind == .correspondence {
                    SingleLanguageSelectionPanel(tables: tables, language: $left, state: leftSelector, entryID: "correspondenceLeft")
                    SingleLanguageSelectionPanel(tables: tables, language: $right, state: rightSelector, entryID: "correspondenceRight")
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
            if !links.isEmpty {
                Section(ui("桑基圖")) { CorrespondenceDiagram(links: links) { detail = $0 }.accessibilityIdentifier("correspondenceDiagram") }
                Section(ui("對應")) {
                    ForEach(links) { link in
                        Button { detail = link } label: {
                            VStack(alignment: .leading) {
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
                                draftColor = TableColors.color(colors[group.value] ?? palette[0]); editingColor = group.value
                            } label: { Image(systemName: "paintpalette.fill").foregroundStyle(TableColors.color(colors[group.value] ?? palette[0])) }
                                .buttonStyle(.borderless).accessibilityLabel(ui("方案顏色"))
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
                        SystemText(link.left + " → " + link.right)
                        ForEach(link.chars, id: \.self) { char in AnalysisCharacterRow(character: char) }
                    }.navigationTitle(ui("例字")).toolbar { Button(ui("完成")) { detail = nil } }
                }
            }
            .sheet(isPresented: Binding(get: { editingColor != nil }, set: { if !$0 { editingColor = nil } })) {
                NavigationStack {
                    Form { ColorPicker(ui("方案顏色"), selection: $draftColor, supportsOpacity: false) }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button(ui("取消")) { editingColor = nil } }
                            ToolbarItem(placement: .confirmationAction) { Button(ui("保存")) {
                                if let key = editingColor {
                                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                    UIColor(draftColor).getRed(&r, green: &g, blue: &b, alpha: &a)
                                    colors[key] = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
                                }
                                editingColor = nil
                            } }
                        }
                }
            }
    }
    private func run() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            if kind == .correspondence && (left.isEmpty || right.isEmpty) { throw DictionaryFailure(message: ui("請先選擇一種語言。")) }
            if kind == .soundClasses && characters.isEmpty { throw DictionaryFailure(message: ui("請輸入漢字。")) }
            let rows: [Reading]
            if kind == .correspondence {
                let a = try await model.repository.toolLanguageRows(left)
                let b = left == right ? [] : try await model.repository.toolLanguageRows(right)
                rows = a + b
            } else { rows = try await model.repository.searchAllCharacters(characters.sorted().joined(), language: "") }
            let payload: [String: Any] = ["kind": kind.rawValue, "left": left, "right": right, "characters": characters.sorted(),
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
                copyText: characters.sorted().joined(separator: "、") + " " + values.map(\.value).joined(separator: " / "))
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

// Each ribbon's thickness represents its number of distinct shared characters.
struct CorrespondenceDiagram: View {
    let links: [CorrespondenceLink]
    let choose: (CorrespondenceLink) -> Void
    private struct Band { let link: CorrespondenceLink; let left: CGFloat; let right: CGFloat; let height: CGFloat }
    var body: some View {
        let left = Array(Set(links.map(\.left))).sorted(), right = Array(Set(links.map(\.right))).sorted()
        let total = max(1, links.reduce(0) { $0 + $1.chars.count })
        let height = max(360, CGFloat(max(left.count, right.count)) * 36)
        let gap: CGFloat = 8
        let scale = max(1, height - CGFloat(max(left.count, right.count)) * gap) / CGFloat(total)
        let leftStarts = starts(left, key: \.left, scale: scale, gap: gap)
        let rightStarts = starts(right, key: \.right, scale: scale, gap: gap)
        let bands = bands(leftStarts, rightStarts, scale: scale)
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(bands.enumerated()), id: \.element.link.id) { index, band in
                    Path { p in
                        let x1: CGFloat = 110, x2: CGFloat = 430
                        p.move(to: .init(x: x1, y: band.left))
                        p.addCurve(to: .init(x: x2, y: band.right), control1: .init(x: 260, y: band.left), control2: .init(x: 280, y: band.right))
                        p.addLine(to: .init(x: x2, y: band.right + band.height))
                        p.addCurve(to: .init(x: x1, y: band.left + band.height), control1: .init(x: 280, y: band.right + band.height), control2: .init(x: 260, y: band.left + band.height))
                        p.closeSubpath()
                    }.fill(Color(hue: Double(index % 12) / 12, saturation: 0.65, brightness: 0.8).opacity(0.6))
                        .onTapGesture { choose(band.link) }
                        .accessibilityLabel(band.link.left + " → " + band.link.right + " \(band.link.chars.count)")
                        .accessibilityAddTraits(.isButton)
                }
                ForEach(left, id: \.self) { value in Text(value).font(.caption).frame(width: 100, alignment: .trailing).offset(y: leftStarts[value] ?? 0) }
                ForEach(right, id: \.self) { value in Text(value).font(.caption).frame(width: 100, alignment: .leading).offset(x: 440, y: rightStarts[value] ?? 0) }
            }.frame(width: 550, height: height)
        }.frame(height: min(height, 500))
    }
    private func starts(_ values: [String], key: KeyPath<CorrespondenceLink, String>, scale: CGFloat, gap: CGFloat) -> [String: CGFloat] {
        var y: CGFloat = 0, result = [String: CGFloat]()
        let counts = Dictionary(grouping: links, by: { $0[keyPath: key] }).mapValues { $0.reduce(0) { $0 + $1.chars.count } }
        for value in values { result[value] = y; y += CGFloat(counts[value] ?? 0) * scale + gap }
        return result
    }
    private func bands(_ a: [String: CGFloat], _ b: [String: CGFloat], scale: CGFloat) -> [Band] {
        var a = a, b = b
        return links.map { link in
            let height = CGFloat(link.chars.count) * scale
            let band = Band(link: link, left: a[link.left] ?? 0, right: b[link.right] ?? 0, height: height)
            a[link.left, default: 0] += height; b[link.right, default: 0] += height
            return band
        }
    }
}
