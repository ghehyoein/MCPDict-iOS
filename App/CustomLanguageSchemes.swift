import SwiftUI

// Mirrors osfans/MCPDict Pref's ordered scheme store and full-width hierarchy separator.
struct CustomLanguageSchemes: Codable, Equatable {
    struct Scheme: Codable, Equatable, Identifiable {
        var name: String
        var languages: Set<String>
        var colorHex: String? = nil
        var id: String { name }
    }
    var schemes: [Scheme]
    var current: String
    var scope = ""
    var colorByScheme = false
    init(legacy: Set<String> = []) {
        current = "默認方案"; schemes = [Scheme(name: current, languages: legacy)]
    }
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[-/／ 　]", with: "－", options: .regularExpression)
    }
    var parents: [String] {
        var result = Set<String>()
        for scheme in schemes {
            let parts = scheme.name.components(separatedBy: "－")
            if parts.count > 1 { for i in 1..<parts.count { result.insert(parts.prefix(i).joined(separator: "－")) } }
        }
        return result.sorted()
    }
    var members: Set<String> {
        get { schemes.first { $0.name == current }?.languages ?? [] }
        set { if let i = schemes.firstIndex(where: { $0.name == current }) { schemes[i].languages = newValue } }
    }
    var selected: Set<String> {
        let included = scope.isEmpty ? schemes.filter { $0.name == current } :
            schemes.filter { scope == "ALL" || $0.name == scope || $0.name.hasPrefix(scope + "－") }
        return included.reduce(into: Set<String>()) { $0.formUnion($1.languages) }
    }
    mutating func create(_ raw: String) -> Bool {
        let name = Self.normalize(raw)
        guard !name.isEmpty, !schemes.contains(where: { $0.name == name }) else { return false }
        retainColors()
        schemes.append(Scheme(name: name, languages: [])); current = name; return true
    }
    mutating func rename(_ raw: String) -> Bool {
        let name = Self.normalize(raw)
        guard !name.isEmpty, let i = schemes.firstIndex(where: { $0.name == current }),
              !schemes.contains(where: { $0.name == name && $0.name != current }) else { return false }
        schemes[i].name = name; current = name; validateScope(); return true
    }
    mutating func delete() -> Bool {
        guard schemes.count > 1 else { return false }
        retainColors()
        schemes.removeAll { $0.name == current }; current = schemes[0].name; validateScope(); return true
    }
    private mutating func validateScope() {
        if !scope.isEmpty && scope != "ALL" && !parents.contains(scope) { scope = "" }
    }
    func color(for language: String) -> String {
        let candidates: [Int]
        if scope.isEmpty { candidates = schemes.indices.filter { schemes[$0].name == current } }
        else if scope != "ALL" { candidates = schemes.indices.filter { schemes[$0].name.hasPrefix(scope + "－") } }
        else { candidates = [] }
        guard let index = (candidates + Array(schemes.indices)).first(where: { schemes[$0].languages.contains(language) }) else { return "#808080" }
        return color(at: index)
    }
    func color(at index: Int) -> String {
        if let hex = schemes[index].colorHex.flatMap(Self.validColor) { return hex }
        return Self.defaultColor(index)
    }
    static func validColor(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let hex = value.hasPrefix("#") ? value : "#" + value
        return hex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) == nil ? nil : hex
    }
    mutating func retainColors() {
        for i in schemes.indices { schemes[i].colorHex = color(at: i) }
    }
    private static func defaultColor(_ index: Int) -> String {
        let vivid = ["#B71C1C", "#0D47A1", "#1B5E20", "#E65100", "#4A148C", "#006064", "#880E4F", "#3E2723"]
        if index < vivid.count { return vivid[index] }
        let i = index - vivid.count
        var hue = (i * 47 + (i / 7) * 19) % 360
        if (45...75).contains(hue) { hue = (hue + 40) % 360 }
        let color = UIColor(hue: CGFloat(hue) / 360, saturation: 0.78, brightness: 0.62, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

struct CustomSchemeControls: View {
    @ObservedObject var state: LanguageSelectionState
    @State private var naming = false
    @State private var renaming = false
    @State private var deleting = false
    @State private var name = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(ui("方案"), selection: $state.custom.current) {
                ForEach(state.custom.schemes) { Text($0.name == "默認方案" ? ui("默認方案") : $0.name).tag($0.name) }
            }.pickerStyle(.menu).accessibilityIdentifier("customSchemePicker")
            HStack {
                Button(ui("新建")) { renaming = false; name = ""; naming = true }.accessibilityIdentifier("newCustomScheme")
                Spacer()
                Button(ui("改名")) { renaming = true; name = state.custom.current; naming = true }
                Spacer()
                Button(ui("刪除"), role: .destructive) { deleting = true }.disabled(state.custom.schemes.count == 1)
            }.buttonStyle(.borderless)
            Picker(ui("自選範圍"), selection: $state.custom.scope) {
                Text(ui("全部方案")).tag("ALL")
                Text(ui("當前方案")).tag("")
                ForEach(state.custom.parents, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("customScopePicker")
            Button { state.custom.colorByScheme.toggle() } label: {
                HStack(spacing: 0) { Image(systemName: state.custom.colorByScheme ? "checkmark.square.fill" : "square"); Text(ui("按方案配色")) }
            }.buttonStyle(StaticCheckboxButtonStyle())
        }
        .alert(ui(renaming ? "改名" : "新建"), isPresented: $naming) {
            TextField(ui("方案名稱（空格可分級，如：江淮 洪巢）"), text: $name)
            Button(ui("取消"), role: .cancel) {}
            Button(ui("保存")) { invalid = !(renaming ? state.custom.rename(name) : state.custom.create(name)) }
        } message: { Text(ui("方案名稱（空格可分級，如：江淮 洪巢）")) }
        .alert(ui("方案名稱不能為空或重複"), isPresented: $invalid) { Button(ui("好"), role: .cancel) {} }
        .alert(ui("刪除方案"), isPresented: $deleting) {
            Button(ui("取消"), role: .cancel) {}
            Button(ui("刪除"), role: .destructive) { _ = state.custom.delete() }
        } message: { Text(state.custom.current) }
    }
}
