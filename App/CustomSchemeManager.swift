import SwiftUI
import UniformTypeIdentifiers

struct CustomSchemeArchive: Codable {
    var format = "MCPDict-custom-languages"
    var version = 1
    var schemes: [CustomLanguageSchemes.Scheme]
    init(_ source: CustomLanguageSchemes) {
        var source = source; source.retainColors(); schemes = source.schemes
    }
    func merging(into source: CustomLanguageSchemes) throws -> CustomLanguageSchemes {
        guard format == "MCPDict-custom-languages", version == 1, !schemes.isEmpty else {
            throw DictionaryFailure(message: ui("無效的自選分區檔案"))
        }
        var result = source; result.retainColors()
        for scheme in schemes {
            let name = CustomLanguageSchemes.normalize(scheme.name)
            guard !name.isEmpty, let hex = scheme.colorHex.flatMap(CustomLanguageSchemes.validColor) else {
                throw DictionaryFailure(message: ui("無效的自選分區檔案"))
            }
            if let index = result.schemes.firstIndex(where: { $0.name == name }) {
                result.schemes[index].languages.formUnion(scheme.languages)
            } else {
                result.schemes.append(.init(name: name, languages: scheme.languages, colorHex: hex))
            }
        }
        return result
    }
}

struct CustomSchemeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var archive: CustomSchemeArchive
    init(_ source: CustomLanguageSchemes) { archive = CustomSchemeArchive(source) }
    init(configuration: ReadConfiguration) throws {
        archive = try JSONDecoder().decode(CustomSchemeArchive.self, from: configuration.file.regularFileContents ?? Data())
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return FileWrapper(regularFileWithContents: try encoder.encode(archive))
    }
}

struct CustomSchemeManager: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var state: LanguageSelectionState
    @State private var naming = false
    @State private var name = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var message: String?
    var body: some View {
        List {
            ForEach(state.custom.schemes) { scheme in
                NavigationLink {
                    CustomSchemeEditor(state: state, originalName: scheme.name)
                } label: {
                    HStack {
                        Circle().fill(TableColors.color(state.custom.schemes.firstIndex(where: { $0.name == scheme.name }).map { state.custom.color(at: $0) } ?? "#808080")).frame(width: 16, height: 16)
                        Text(scheme.name == "默認方案" ? ui("默認方案") : scheme.name)
                        Spacer(); Text("\(scheme.languages.count)").foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("schemeEditor-" + scheme.name)
            }.onMove { from, to in
                state.custom.retainColors(); state.custom.schemes.move(fromOffsets: from, toOffset: to)
            }.onDelete { offsets in
                guard offsets.count < state.custom.schemes.count else { return }
                state.custom.retainColors()
                let current = state.custom.current
                for index in offsets.sorted(by: >) {
                    state.custom.current = state.custom.schemes[index].name; _ = state.custom.delete()
                }
                if state.custom.schemes.contains(where: { $0.name == current }) { state.custom.current = current }
            }
        }.navigationTitle(ui("自選分區")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditButton()
                Button(ui("新建")) { name = ""; naming = true }
                Menu {
                    Button(ui("匯入自選分區")) { importing = true }
                    Button(ui("匯出自選分區")) { exporting = true }
                } label: { Image(systemName: "square.and.arrow.up.on.square") }
            }
            .alert(ui("新建"), isPresented: $naming) {
                TextField(ui("方案名稱（空格可分級，如：江淮 洪巢）"), text: $name)
                Button(ui("取消"), role: .cancel) {}
                Button(ui("保存")) { if !state.custom.create(name) { message = ui("方案名稱不能為空或重複") } }
            }
            .fileExporter(isPresented: $exporting, document: CustomSchemeDocument(state.custom), contentType: .plainText, defaultFilename: "MCPDict-custom-languages") { result in
                if case .failure(let error) = result { model.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let archive = try JSONDecoder().decode(CustomSchemeArchive.self, from: Data(contentsOf: url))
                    state.custom = try archive.merging(into: state.custom)
                    message = ui("已合併匯入自選分區，原有內容及配色已保留。")
                } catch { model.error = error.localizedDescription }
            }
            .alert(ui("自選分區"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(ui("好")) { message = nil }
            } message: { Text(message ?? "") }
    }
}

struct CustomSchemeEditor: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var state: LanguageSelectionState
    let originalName: String
    @State private var identity = ""
    @State private var name = ""
    @State private var hex = ""
    @State private var filter = ""
    @State private var invalid = false
    private var index: Int? { state.custom.schemes.firstIndex { $0.name == (identity.isEmpty ? originalName : identity) } }
    private var color: Binding<Color> {
        Binding(get: { index.map { TableColors.color(state.custom.color(at: $0)) } ?? .blue }, set: { value in
            guard let i = index else { return }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(value).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            hex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
            state.custom.schemes[i].colorHex = hex
        })
    }
    var body: some View {
        List {
            Section {
                HStack {
                    TextField(ui("方案"), text: $name)
                    Button(ui("改名")) {
                        let normalized = CustomLanguageSchemes.normalize(name)
                        guard let i = index, !normalized.isEmpty, !state.custom.schemes.contains(where: { $0.name == normalized && $0.name != identity }) else { invalid = true; return }
                        let old = state.custom.schemes[i].name
                        let current = state.custom.current
                        state.custom.current = old
                        _ = state.custom.rename(normalized)
                        if current != old { state.custom.current = current }
                        identity = normalized; name = normalized
                    }
                }
                ColorPicker(ui("方案顏色"), selection: color, supportsOpacity: false)
                HStack {
                    TextField("#RRGGBB", text: $hex).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityIdentifier("customSchemeHex")
                    Button(ui("保存")) {
                        guard let i = index, let value = CustomLanguageSchemes.validColor(hex) else { invalid = true; return }
                        state.custom.schemes[i].colorHex = value; hex = value
                    }
                }
            }
            Section(ui("語言")) {
                TextField(ui("搜尋語言或分區"), text: $filter)
                if let i = index {
                    ForEach(model.availableTables.filter { filter.isEmpty || InterfaceLanguage.matches($0.fullName + $0.name, filter) }) { table in
                        Button {
                            if !state.custom.schemes[i].languages.insert(table.name).inserted { state.custom.schemes[i].languages.remove(table.name) }
                        } label: {
                            HStack {
                                Image(systemName: state.custom.schemes[i].languages.contains(table.name) ? "checkmark.square.fill" : "square")
                                LanguageBadge(name: table.name, table: table); Spacer()
                            }
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }.navigationTitle(ui("自選分區")).navigationBarTitleDisplayMode(.inline)
            .onAppear { if identity.isEmpty { identity = originalName; name = originalName; hex = index.map { state.custom.color(at: $0) } ?? "#808080" } }
            .alert(ui("請輸入有效且不重複的名稱，或六位十六進制顏色碼。"), isPresented: $invalid) { Button(ui("好"), role: .cancel) {} }
    }
}
