import SwiftUI
import JavaScriptCore

struct ReadingFormatSpec: Codable, Identifiable {
    struct Option: Codable, Identifiable { let id: String; let title: String }
    let id: String
    let title: String
    let multiple: Bool
    let options: [Option]
    let defaults: [String]
}
struct ReadingFormatPreferences: Codable {
    static let key = "readingFormats"
    var values = [String: [String]]()
    static func load(_ raw: String) -> Self { raw.data(using: .utf8).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self() }
    var encoded: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "" }
    func selected(_ spec: ReadingFormatSpec) -> [String] { values[spec.id] ?? spec.defaults }
}
final class ReadingFormatEngine {
    static let shared = ReadingFormatEngine()
    let specs: [ReadingFormatSpec]
    private let context: JSContext?
    private let lock = NSRecursiveLock()
    private init() {
        let data = Bundle.main.url(forResource: "ReadingFormatsData", withExtension: "json").flatMap { try? Data(contentsOf: $0) } ?? Data()
        struct Configuration: Decodable { let specs: [ReadingFormatSpec] }
        specs = (try? JSONDecoder().decode(Configuration.self, from: data).specs) ?? []
        context = JSContext()
        if let json = try? JSONSerialization.jsonObject(with: data) {
            context?.setObject(json, forKeyedSubscript: "FORMAT_DATA" as NSString)
            if let url = Bundle.main.url(forResource: "ReadingFormats", withExtension: "js"), let script = try? String(contentsOf: url, encoding: .utf8) { context?.evaluateScript(script) }
        }
    }
    static func key(for name: String) -> String? {
        switch name {
        case "廣韻": return "mc_display"
        case "中原音韻": return "zyyy_display"
        case "普通話", "國語": return "mandarin_display"
        case "香港": return "cantonese_romanization"
        case "高雄": return "minnan_display"
        case "東干甘肅話": return "dgy_display"
        case "越南": return "vietnamese_tone_position"
        case "朝鮮": return "korean_display"
        case "日語吳音", "日語漢音", "日語唐音", "日語慣用音", "日語未歸類字音": return "japanese_display"
        default: return nil
        }
    }
    func parts(_ raw: String, table: TablePackage?, style: String, pitch: String, preferences: ReadingFormatPreferences? = nil) -> [ToneDisplay.Part]? {
        guard let table, let key = Self.key(for: table.name), let spec = specs.first(where: { $0.id == key }) else { return nil }
        let settings = preferences ?? .load(UserDefaults.standard.string(forKey: ReadingFormatPreferences.key) ?? "")
        lock.lock(); defer { lock.unlock() }
        context?.exception = nil
        guard let segments = context?.objectForKeyedSubscript("readingFormat")?.call(withArguments: [raw, key, settings.selected(spec)])?.toArray() as? [[String: Any]], context?.exception == nil else { return nil }
        var result = [ToneDisplay.Part]()
        for segment in segments {
            guard let text = segment["text"] as? String else { continue }
            let parts = segment["tone"] as? Bool == true ? ToneDisplay.rawParts(text, table: table, style: style, pitchStyle: pitch) : [.init(id: 0, base: text, pitch: "", tone: "", stacked: false)]
            for part in parts { result.append(.init(id: result.count, base: part.base, pitch: part.pitch, tone: part.tone, stacked: part.stacked, italic: segment["italic"] as? Bool ?? false)) }
        }
        return result
    }
    func canonicalCantonese(_ input: String) -> String? { canonicalCantoneseInputs(input).first }
    func canonicalCantoneseInputs(_ input: String) -> [String] {
        guard let spec = specs.first(where: { $0.id == "cantonese_romanization" }) else { return [] }
        let selected = ReadingFormatPreferences.load(UserDefaults.standard.string(forKey: ReadingFormatPreferences.key) ?? "").selected(spec)
        lock.lock(); defer { lock.unlock() }
        return Array(Set(selected.compactMap { option in
            context?.objectForKeyedSubscript("canonicalCantonese")?.call(withArguments: [input, Int(option) ?? 0])?.toString()
        })).sorted()
    }
}

struct ReadingFormatSettingsView: View {
    @State private var selectedSpec: ReadingFormatSpec?
    @AppStorage("toneStyle") private var toneStyle = "baSheng"
    @AppStorage("pitchStyle") private var pitchStyle = "curve"
    @AppStorage(ReadingFormatPreferences.key) private var raw = ""
    private var settings: ReadingFormatPreferences {
        get { .load(raw) }
        nonmutating set { raw = newValue.encoded }
    }
    var body: some View {
        List {
            Section(ui("聲調顯示")) {
                HStack { SystemText(ui("聲調預覽：")); Spacer(); HStack(spacing: 0) { SystemText(ToneDisplay.previewCharacter); PronunciationView(raw: ToneDisplay.previewReading, table: ToneDisplay.previewTable, scrollable: false) } }
                Picker(ui("聲調顯示"), selection: $toneStyle) {
                    ForEach(ToneDisplay.styles, id: \.0) { Text(ui($0.1)).tag($0.0) }
                }.pickerStyle(.menu)
                Picker(ui("調值樣式"), selection: $pitchStyle) {
                    Text(ui("曲線")).tag("curve")
                    Text(ui("數字")).tag("number")
                    Text(ui("隱藏")).tag("hidden")
                }.pickerStyle(.menu)
            }
            ForEach(ReadingFormatEngine.shared.specs) { spec in
                if spec.multiple && spec.id != "dgy_display" {
                    Button { selectedSpec = spec } label: { Text(ui(spec.title)).foregroundStyle(Color.primary) }
                        .accessibilityIdentifier("readingFormat-" + spec.id)
                } else {
                    Menu {
                        ForEach(spec.options) { option in
                            Button { toggle(option, in: spec) } label: {
                                if settings.selected(spec).contains(option.id) { Label(ui(option.title), systemImage: "checkmark") }
                                else { Text(ui(option.title)) }
                            }.accessibilityIdentifier("readingFormat-" + spec.id + "-" + option.id)
                        }
                    } label: {
                        HStack { Text(ui(spec.title)).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 12); Text(spec.options.filter { settings.selected(spec).contains($0.id) }.map { ui($0.title) }.joined(separator: "、")).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true); Image(systemName: "chevron.up.chevron.down") }
                    }.menuActionDismissBehavior(.disabled).accessibilityIdentifier("readingFormat-" + spec.id)

                }
            }
        }.navigationTitle(ui("讀音格式")).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSpec) { spec in
            NavigationStack {
                List(spec.options) { option in
                    Toggle(ui(option.title), isOn: Binding(get: { settings.selected(spec).contains(option.id) }, set: { enabled in
                        var values = Set(settings.selected(spec))
                        if enabled { values.insert(option.id) } else { values.remove(option.id) }
                        settings.values[spec.id] = spec.options.map(\.id).filter(values.contains)
                    })).accessibilityIdentifier("readingFormat-" + spec.id + "-" + option.id)
                }.navigationTitle(ui(spec.title)).navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button(ui("完成")) { selectedSpec = nil } }
            }
        }
    }
    private func toggle(_ option: ReadingFormatSpec.Option, in spec: ReadingFormatSpec) {
        var selected = Set(settings.selected(spec))
        if !selected.insert(option.id).inserted { selected.remove(option.id) }
        settings.values[spec.id] = spec.options.map(\.id).filter(selected.contains)
    }

}
