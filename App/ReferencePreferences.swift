import SwiftUI

struct ReferencePreferences: Codable {
    static let key = "referencePresentation"
    static let links = CharacterReference.books + ["地圖"]
    static let information = ["Unicode", "Unicode區段"] + CharacterReference.fields
    var order = ReferencePreferences.links
    var hidden = Set<String>()
    var fieldOrder = ReferencePreferences.information
    var fieldModes = [String: String]()
    static func load(_ raw: String) -> Self {
        guard let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var result = value
        if value.order.contains("Unicode"), value.hidden.contains("Unicode"), value.fieldModes["Unicode"] == nil { result.fieldModes["Unicode"] = "hidden" }
        result.hidden.formIntersection(links)
        result.order = normalized(value.order, allowed: links)
        result.fieldOrder = normalized(value.fieldOrder, allowed: information)
        return result
    }
    private static func normalized(_ values: [String], allowed: [String]) -> [String] {
        var seen = Set<String>()
        return (values + allowed).filter { allowed.contains($0) && seen.insert($0).inserted }
    }
    var encoded: String { String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? "" }
    func mode(_ field: String) -> String { fieldModes[field] ?? (field == "Unicode" ? "expanded" : "collapsed") }
    func value(_ field: String, data: CharacterReference) -> String? {
        if field == "Unicode" { return data.code }
        let text = field == "Unicode區段" ? data.block : data.values[field] ?? ""
        return text.isEmpty ? nil : contentUI(field == "Unicode" ? "Unicode 碼" : field == "Unicode區段" ? "統一碼區段" : field) + "：" + text
    }
}

struct ReferenceSettingsView: View {
    @AppStorage(ReferencePreferences.key) private var raw = ""
    @AppStorage(AppTypography.interfaceKey) private var fontSize = 17.0
    @Environment(\.dismiss) private var dismiss
    private var settings: ReferencePreferences {
        get { .load(raw) }
        nonmutating set { raw = newValue.encoded }
    }
    var body: some View {
        Group {
            List {
                Section(ui("漢字資料")) {
                    ForEach(settings.fieldOrder, id: \.self) { field in
                        Picker(ui(field == "Unicode" ? "Unicode 碼" : field == "Unicode區段" ? "統一碼區段" : field), selection: Binding(get: { settings.mode(field) }, set: { settings.fieldModes[field] = $0 })) {
                            Text(ui("展開顯示")).tag("expanded")
                            Text(ui("折疊顯示")).tag("collapsed")
                            Text(ui("不顯示")).tag("hidden")
                        }.pickerStyle(.menu).accessibilityIdentifier("referenceField-" + field)
                    }.onMove { settings.fieldOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                Section(ui("字典說明")) {
                    ForEach(settings.order, id: \.self) { item in
                        HStack {
                            Text(ui(item == "Unicode" ? "Unicode 碼" : item))
                            Spacer()
                            Toggle(ui(item == "Unicode" ? "Unicode 碼" : item), isOn: Binding(get: { !settings.hidden.contains(item) }, set: { if $0 { settings.hidden.remove(item) } else { settings.hidden.insert(item) } }))
                                .labelsHidden().fixedSize()
                        }
                    }.onMove { settings.order.move(fromOffsets: $0, toOffset: $1) }
                }
                OnlineDictionarySettingsSection()
            }
            .font(.system(size: fontSize))
            .dynamicTypeSize(AppTypography.size(fontSize))
            .environment(\.editMode, .constant(.active))
            .navigationTitle(ui("字頭資料顯示")).navigationBarTitleDisplayMode(.inline)
        }
    }
}
