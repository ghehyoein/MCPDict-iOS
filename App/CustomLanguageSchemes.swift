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
    var paletteScheme: String? = nil
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
        let included = scope.isEmpty ? schemes.filter { $0.name == current || $0.name.hasPrefix(current + "－") } :
            schemes.filter { scope == "ALL" || $0.name == scope || $0.name.hasPrefix(scope + "－") }
        return included.reduce(into: Set<String>()) { $0.formUnion($1.languages) }
    }
    mutating func selectCurrent(_ names: Set<String>) {
        let branch = schemes.indices.filter { schemes[$0].name == current || schemes[$0].name.hasPrefix(current + "－") }
        for i in branch { schemes[i].languages.formIntersection(names) }
        let assigned = branch.reduce(into: Set<String>()) { $0.formUnion(schemes[$1].languages) }
        if let root = schemes.firstIndex(where: { $0.name == current }) { schemes[root].languages.formUnion(names.subtracting(assigned)) }
    }
    mutating func create(_ raw: String) -> Bool {
        let name = Self.normalize(raw)
        guard !name.isEmpty, !name.components(separatedBy: "－").contains(""), !schemes.contains(where: { $0.name == name }) else { return false }
        retainColors()
        schemes.append(Scheme(name: name, languages: [])); current = name; return true
    }
    mutating func rename(_ raw: String, scheme: String? = nil) -> Bool {
        let name = Self.normalize(raw)
        let old = scheme ?? current
        let selected = current
        guard !name.isEmpty, !name.components(separatedBy: "－").contains(""), schemes.contains(where: { $0.name == old }),
              name == old || !name.hasPrefix(old + "－") else { return false }
        let renamed = schemes.map { scheme -> String in
            scheme.name == old ? name : scheme.name.hasPrefix(old + "－") ? name + String(scheme.name.dropFirst(old.count)) : scheme.name
        }
        guard Set(renamed).count == renamed.count else { return false }
        for i in schemes.indices { schemes[i].name = renamed[i] }
        if scope == old || scope.hasPrefix(old + "－") { scope = name + String(scope.dropFirst(old.count)) }
        if let paletteScheme, paletteScheme == old || paletteScheme.hasPrefix(old + "－") {
            self.paletteScheme = name + String(paletteScheme.dropFirst(old.count))
        }
        current = selected == old || selected.hasPrefix(old + "－") ? name + String(selected.dropFirst(old.count)) : selected
        validateScope(); return true
    }
    mutating func delete() -> Bool {
        guard schemes.count > 1 else { return false }
        retainColors()
        schemes.removeAll { $0.name == current }; current = schemes[0].name; validateScope(); return true
    }
    func branchNames(_ roots: Set<String>) -> Set<String> {
        Set(schemes.filter { scheme in roots.contains { scheme.name == $0 || scheme.name.hasPrefix($0 + "－") } }.map(\.name))
    }
    @discardableResult mutating func removeBranches(_ roots: Set<String>) -> Bool {
        let removed = branchNames(roots)
        guard !removed.isEmpty, removed.count < schemes.count else { return false }
        retainColors()
        schemes.removeAll { removed.contains($0.name) }
        if removed.contains(current) { current = schemes[0].name }
        validateScope()
        return true
    }
    @discardableResult mutating func duplicateBranches(_ names: Set<String>, suffix: String) -> Set<String> {
        retainColors()
        let roots = names.filter { name in !names.contains { $0 != name && name.hasPrefix($0 + "－") } }.sorted()
        var copies = Set<String>()
        for root in roots {
            let branch = schemes.filter { $0.name == root || $0.name.hasPrefix(root + "－") }
            guard !branch.isEmpty else { continue }
            var number = 1
            var destination: String
            repeat {
                destination = root + "（" + suffix + (number == 1 ? "" : "\(number)") + "）"
                number += 1
            } while schemes.contains { $0.name == destination || $0.name.hasPrefix(destination + "－") }
            schemes.append(contentsOf: branch.map {
                Scheme(name: destination + String($0.name.dropFirst(root.count)), languages: $0.languages, colorHex: $0.colorHex)
            })
            copies.insert(destination)
        }
        return copies
    }
    private mutating func validateScope() {
        if !scope.isEmpty && scope != "ALL" && !parents.contains(scope) { scope = "" }
        if let paletteScheme, branchNames([paletteScheme]).isEmpty { self.paletteScheme = nil }
    }
    func paletteColors() -> [String: String] {
        guard let root = paletteScheme else { return [:] }
        let indices = schemes.indices.filter { schemes[$0].name == root || schemes[$0].name.hasPrefix(root + "－") }
            .sorted {
                let a = schemes[$0].name.components(separatedBy: "－").count
                let b = schemes[$1].name.components(separatedBy: "－").count
                return a == b ? $0 < $1 : a > b
            }
        var colors = [String: String]()
        for i in indices {
            let hex = color(at: i)
            for language in schemes[i].languages where colors[language] == nil { colors[language] = hex }
        }
        return colors
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
    var body: some View {
        HStack {
            Text(ui("方案")).foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            Picker(ui("方案"), selection: $state.custom.current) {
                ForEach(state.custom.schemes) { Text($0.name == "默認方案" ? ui("默認方案") : $0.name).tag($0.name) }
            }.labelsHidden().pickerStyle(.menu).accessibilityIdentifier("customSchemePicker")
        }.onAppear { state.custom.scope = "" }
    }
}
