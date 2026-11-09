import SwiftUI
import CoreLocation

enum GuessKind { case character, language }
enum GuessRule: String, CaseIterable, Identifiable {
    case language = "猜方言", distance = "距離", province = "省級", city = "地級", county = "縣級", division = "方言片", subdivision = "方言小片"
    var id: String { rawValue }
}
enum GuessLogic {
    static func matchesLevel(_ value: String, _ level: String) -> Bool {
        if level.isEmpty { return true }
        let levels = Set(value.split(separator: ",").map(String.init))
        return level == "縣級" ? !levels.isDisjoint(with: ["縣級", "地級"]) : levels.contains(level)
    }
    static func isCharacter(_ value: Character) -> Bool {
        guard let scalar = value.unicodeScalars.first else { return false }
        let n = scalar.value
        return (0x3400...0x9FFF).contains(n) || (0xF900...0xFAFF).contains(n) || (0x20000...0x3347F).contains(n) || n == 0x3007
    }
    static func area(_ table: TablePackage, rule: GuessRule) -> String {
        let m = table.metadata ?? [:]
        let province = m["省"] ?? ""
        if province == "海外" { return "" }
        var parts = [province]
        let city = (m["市"] ?? "").replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespaces)
        if rule == .city || rule == .county {
            if !city.isEmpty { parts.append(city) }
            if rule == .county || (city.isEmpty && !["北京", "天津", "上海", "重慶"].contains(province)) {
                let county = (m["縣"] ?? "").replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespaces)
                if !county.isEmpty { parts.append(county) }
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "－")
    }
    static func division(_ table: TablePackage, rule: GuessRule, dictionary: Bool) -> String {
        let value = table.metadata?[dictionary ? "音典分區" : "地圖集二分區"] ?? ""
        return rule == .division ? String(value.split(separator: "－").first ?? "") : value
    }
    static func geography(from: TableLocation, to: TableLocation) -> (li: Double, arrow: String) {
        let a = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let b = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let lat1 = from.latitude * .pi / 180, lat2 = to.latitude * .pi / 180
        let delta = (to.longitude - from.longitude) * .pi / 180
        let bearing = atan2(sin(delta) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)) * 180 / .pi
        let direction = Int(((bearing + 360).truncatingRemainder(dividingBy: 360) / 45).rounded()) % 8
        return (a.distance(from: b) / 500, ["⬆️", "↗️", "➡️", "↘️", "⬇️", "↙️", "⬅️", "↖️"][direction])
    }
    static func won(_ guess: TablePackage, answer: TablePackage, rule: GuessRule, diameter: Double, dictionary: Bool) -> Bool {
        if guess.id == answer.id { return true }
        switch rule {
        case .language: return false
        case .distance:
            guard let a = guess.location, let b = answer.location else { return false }
            return geography(from: a, to: b).li < diameter
        case .province, .city, .county:
            let key = area(answer, rule: rule)
            return !key.isEmpty && area(guess, rule: rule) == key
        case .division, .subdivision:
            let key = division(answer, rule: rule, dictionary: dictionary)
            return !key.isEmpty && division(guess, rule: rule, dictionary: dictionary) == key
        }
    }
}

struct GuessGameView: View {
    let kind: GuessKind
    @EnvironmentObject private var model: AppModel
    @AppStorage("colorScheme") private var palette = "atlas"
    @State private var rule = GuessRule.language
    @State private var difficulty = 0
    @State private var level = ""
    @State private var province = ""
    @State private var division = ""
    @AppStorage("guessDiameter") private var diameter = 200.0
    @AppStorage("guessHintDirection") private var hintDirection = true
    @AppStorage("guessHintDistance") private var hintDistance = true
    @State private var answerCharacter = ""
    @State private var answerTable: TablePackage?
    @State private var input = ""
    @State private var language = ""
    @State private var hint = ""
    @State private var log = [String]()
    @State private var readings = [Reading]()
    @State private var busy = false
    @State private var error: String?
    @State private var generation = 0
    @State private var lastGuess = ""
    private var tables: [TablePackage] { (model.installed?.tables ?? []).sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending } }
    private var dictionary: Bool { palette == "dictionary" }
    private var candidates: [TablePackage] {
        tables.filter { t in
            guard t.location?.valid == true else { return false }
            if !province.isEmpty && t.metadata?["省"] != province { return false }
            let parts = dictionary ? t.dictionary : t.atlas
            if !division.isEmpty && !parts.contains(division) { return false }
            if rule == .language && !level.isEmpty {
                let value = t.metadata?["行政區級別"] ?? ""
                if !GuessLogic.matchesLevel(value, level) { return false }
            }
            if [.province, .city, .county].contains(rule) && GuessLogic.area(t, rule: rule).isEmpty { return false }
            if [.division, .subdivision].contains(rule) && GuessLogic.division(t, rule: rule, dictionary: dictionary).isEmpty { return false }
            return true
        }
    }
    var body: some View {
        Form {
            if kind == .language { languageOptions }
            else {
                Picker(ui("難度"), selection: $difficulty) {
                    Text(ui("隨機")).tag(0); Text(ui("簡單")).tag(1); Text(ui("普通")).tag(2); Text(ui("困難")).tag(3)
                }
            }
            Section {
                Button(ui("出題")) { Task { await newGame() } }.disabled(busy)
                if busy { ProgressView() }
                if let error { SystemText(error).foregroundStyle(.red) }
                TextField(ui(kind == .character ? "請輸入猜測的漢字" : "請輸入漢字"), text: $input).autocorrectionDisabled()
                    .onSubmit { if kind == .character { checkCharacter() } }
                    .onChange(of: input) { _, _ in if kind == .character { checkCharacter() } }
                if kind == .character {
                    Button(ui("提交")) { checkCharacter() }
                    Picker(ui("字形提示"), selection: $hint) {
                        Text(ui("選擇提示")).tag("")
                        ForEach(["總筆畫數", "首筆", "末筆", "部首", "結構"], id: \.self) { Text(ui($0)).tag($0) }
                    }.onChange(of: hint) { _, value in if !value.isEmpty { Task { await characterHint(value) } } }
                }
                NavigationLink {
                    GuessLanguagePicker(tables: kind == .language ? candidates : tables, selection: $language)
                } label: {
                    HStack { Text(ui(kind == .character ? "讀音提示" : "猜測語言")); Spacer(); Text(language).foregroundStyle(.secondary) }
                }
                Button(ui(kind == .character ? "讀音提示" : "提交")) {
                    if kind == .character { Task { await readingHint() } } else { checkLanguage() }
                }
            }
            if !readings.isEmpty {
                Section(ui("讀音提示")) {
                    ForEach(readings) { row in HStack { if kind == .language { SystemText(row.characters) }; PronunciationView(raw: row.pronunciation, table: kind == .language ? answerTable : model.table(named: row.language)) } }
                }
            }
            Section {
                ForEach(Array(log.enumerated()), id: \.offset) { _, line in SystemText(line) }
            }
        }.navigationTitle(ui(kind == .character ? "猜字" : "猜方言"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(ui("答案")) { reveal() }
                    ShareLink(item: log.reversed().joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }.disabled(log.isEmpty)
                }
            }
            .task(id: input) { if kind == .language { await readingHint() } }
            .onChange(of: rule) { _, _ in Task { await newGame() } }
            .onChange(of: level) { _, _ in Task { await newGame() } }
            .onChange(of: language) { _, _ in
                if kind == .language { checkLanguage() } else { Task { await readingHint() } }
            }
    }
    private var languageOptions: some View {
        Section {
            Picker(ui("出題模式"), selection: $rule) { ForEach(GuessRule.allCases) { Text(ui($0.rawValue)).tag($0) } }
            Picker(ui("行政區級別"), selection: $level) {
                Text(ui("隨機")).tag(""); Text(ui("省會")).tag("省會"); Text(ui("地級")).tag("地級"); Text(ui("縣級")).tag("縣級")
            }
            Picker(ui("省"), selection: $province) {
                Text(ui("全部")).tag("")
                ForEach(Array(Set(tables.compactMap { $0.metadata?["省"] })).sorted(), id: \.self) { Text($0).tag($0) }
            }
            Picker(ui("分區"), selection: $division) {
                Text(ui("全部")).tag("")
                ForEach(Array(Set(tables.flatMap { dictionary ? $0.dictionary : $0.atlas })).sorted(), id: \.self) { Text($0).tag($0) }
            }
            if rule == .distance { VStack { Text("\(ui("距離"))：\(Int(diameter)) \(ui("里"))"); Slider(value: $diameter, in: 10...200, step: 10) } }
            Toggle(ui("方向提示"), isOn: $hintDirection)
            Toggle(ui("距離提示"), isOn: $hintDistance)
        }
    }
    private func append(_ text: String) { log.insert(text, at: 0) }
    @MainActor private func newGame() async {
        guard !busy else { return }
        busy = true; error = nil; log = []; readings = []; generation += 1
        answerCharacter = ""; answerTable = nil; hint = ""; lastGuess = ""
        defer { busy = false }
        do {
            if kind == .language {
                guard let table = candidates.randomElement() else { throw DictionaryFailure(message: ui("未找到符合條件的方言，請重新出題")) }
                answerTable = table
                append(ui("根據指定漢字的讀音或相對地理位置猜方言"))
                await readingHint()
            } else {
                let character = try await CharacterReferenceIndex.shared.guessCharacter(level: difficulty)
                answerCharacter = character
                let rows = try await model.repository.searchAllCharacters(character, language: "")
                guard let row = rows.randomElement() else { throw DictionaryFailure(message: ui("此字在已下載字表中沒有讀音")) }
                readings = [row]
                append("\(ui("讀音提示"))：\(model.table(named: row.language)?.fullName ?? row.language)")
                if !language.isEmpty { await readingHint() }
            }
        } catch { self.error = error.localizedDescription; answerCharacter = ""; answerTable = nil }
    }
    private func checkCharacter() {
        guard !answerCharacter.isEmpty, let last = input.last, GuessLogic.isCharacter(last), String(last) != lastGuess else { return }
        lastGuess = String(last)
        if String(last) == answerCharacter { append(ui("答對了！恭喜！")); answerCharacter = "" }
        else { append("\(ui("不是"))：\(last)") }
    }
    private func checkLanguage() {
        guard let answer = answerTable, let guess = tables.first(where: { $0.name == language }), let a = guess.location, let b = answer.location else { return }
        let geo = GuessLogic.geography(from: a, to: b)
        var message = hintDirection ? geo.arrow : ""
        if hintDistance { message += String(format: " %.1f %@ (%.1f%%)", geo.li, ui("里"), 100 - geo.li / 104) }
        append(message + " " + guess.fullName)
        if GuessLogic.won(guess, answer: answer, rule: rule, diameter: diameter, dictionary: dictionary) {
            append(ui("答對了！恭喜！") + " " + answer.fullName); answerTable = nil
        } else { append(ui("不是") + " " + guess.fullName) }
    }
    private func reveal() {
        let answer = kind == .character ? answerCharacter : answerTable?.fullName ?? ""
        if !answer.isEmpty { append(ui("答案") + "：" + answer) }
        answerCharacter = ""; answerTable = nil
    }
    @MainActor private func readingHint() async {
        let query = kind == .character ? answerCharacter : input
        let lang = kind == .character ? language : answerTable?.name ?? ""
        let revision = generation
        guard !query.isEmpty, !lang.isEmpty else { return }
        do {
            var rows = try await model.repository.searchAllCharacters(query, language: lang)
            if rows.isEmpty { rows = try await model.repository.searchAllCharacters(CharacterVariants.expand(query).joined(), language: lang) }
            guard !Task.isCancelled, revision == generation, query == (kind == .character ? answerCharacter : input), lang == (kind == .character ? language : answerTable?.name ?? "") else { return }
            readings = rows
            if kind == .character && !rows.isEmpty {
                append((model.table(named: lang)?.fullName ?? lang) + "：" + rows.map(\.pronunciation).joined(separator: " / "))
            }
            if rows.isEmpty { append(ui("此字在已下載字表中沒有讀音")) }
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func characterHint(_ key: String) async {
        let answer = answerCharacter
        guard !answer.isEmpty else { return }
        do {
            let reference = try await CharacterReferenceIndex.shared.lookup(answer)
            guard answer == answerCharacter else { return }
            var value = ""
            switch key {
            case "總筆畫數": value = reference.values[key] ?? ""
            case "首筆", "末筆":
                let strokes = reference.values["五筆畫"] ?? ""
                if let c = key == "首筆" ? strokes.first : strokes.last, let index = c.wholeNumberValue, (1...5).contains(index) { value = ["橫", "豎", "撇", "捺", "折"][index - 1] }
            case "部首":
                if let radical = reference.values["部首餘筆"] {
                    value = radical.dropFirst() == "0" ? ui("這個字就是部首") : String(radical.prefix(1))
                }
            case "結構":
                if let first = reference.values["字形描述"]?.first { value = "⿰⿱⿲⿳⿴⿵⿶⿷⿸⿹⿺⿻⿼⿽㇯".contains(first) ? String(first) : ui("獨體字") }
            default: break
            }
            append(ui(key) + "：" + (value.isEmpty ? ui("缺資料") : value))
        } catch { self.error = error.localizedDescription }
    }
}
struct GuessLanguagePicker: View {
    let tables: [TablePackage]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        List {
            ForEach(tables.filter { query.isEmpty || ($0.fullName + $0.name).localizedCaseInsensitiveContains(query) }) { table in
                Button { selection = table.name; dismiss() } label: { LanguageBadge(name: table.fullName, table: table) }
            }
        }.searchable(text: $query).navigationTitle(ui("選擇語言"))
    }
}
