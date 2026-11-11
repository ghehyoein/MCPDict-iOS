import SwiftUI

struct ComparisonPalette {
    static let key = "comparisonColors"
    static let defaults = ["same": "#15803D", "partial": "#CA8A04", "different": "#B91C1C", "missing": "#94A3B8"]
    private var values: [String: String]
    init(_ raw: String = "") {
        values = (try? JSONDecoder().decode([String: String].self, from: Data(raw.utf8))) ?? [:]
    }
    func color(_ status: String) -> String {
        values[status].flatMap(CustomLanguageSchemes.validColor) ?? Self.defaults[status] ?? "#808080"
    }
    func setting(_ raw: String, for status: String) -> String? {
        guard Self.defaults[status] != nil, let hex = CustomLanguageSchemes.validColor(raw) else { return nil }
        var updated = values; updated[status] = hex
        guard let data = try? JSONEncoder().encode(updated) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct ComparisonUnit: Identifiable, Equatable {
    let id = UUID()
    let characters: [String]
    var title: String { characters.joined(separator: "＋") }
    init(_ characters: [String]) {
        var seen = Set<String>()
        self.characters = characters.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func effective(_ groups: [Self], choices: [String], selected: Set<String>) -> [[String]] {
        groups.map(\.characters) + choices.filter(selected.contains).map { [$0] }
    }
}

struct ComparisonColorEditor: View {
    @Environment(\.dismiss) private var dismiss
    let status: String
    @Binding var storage: String
    @State private var hex = ""
    @State private var invalid = false
    private var color: Binding<Color> {
        Binding(get: { TableColors.color(CustomLanguageSchemes.validColor(hex) ?? ComparisonPalette(storage).color(status)) }, set: { value in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(value).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            hex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        })
    }
    var body: some View {
        Form {
        HStack(spacing: 8) {
            Text(ui("方案顏色")).foregroundStyle(Color.primary).fixedSize()
            Spacer(minLength: 0)
            TextField("#RRGGBB", text: $hex).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .keyboardType(.asciiCapable).multilineTextAlignment(.trailing).frame(width: 88)
                .minimumScaleFactor(0.7).lineLimit(1)
                .accessibilityIdentifier("comparisonColorHex-" + status)
            ColorPicker(ui("方案顏色"), selection: color, supportsOpacity: false).labelsHidden().frame(width: 32)
                .accessibilityIdentifier("comparisonColorPicker-" + status)
            Button(ui("保存"), action: save).fixedSize().buttonStyle(.borderless)
                .accessibilityIdentifier("saveComparisonColor-" + status)
        }
        }
        .navigationTitle(ui("方案顏色")).navigationBarTitleDisplayMode(.inline)
        .onAppear { hex = ComparisonPalette(storage).color(status) }
        .onChange(of: storage) { _, value in hex = ComparisonPalette(value).color(status) }
        .alert(ui("請輸入六位十六進制顏色碼。"), isPresented: $invalid) { Button(ui("好"), role: .cancel) {} }
    }
    private func save() {
        guard let value = ComparisonPalette(storage).setting(hex, for: status) else { invalid = true; return }
        storage = value; hex = ComparisonPalette(value).color(status); dismiss()
    }
}
