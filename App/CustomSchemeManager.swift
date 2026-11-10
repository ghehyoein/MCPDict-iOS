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
    @State private var renaming: String?
    @State private var naming = false
    @State private var name = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var message: String?
    @State private var selecting = false
    @State private var selection = Set<String>()
    private var exported: CustomLanguageSchemes {
        var value = state.custom; value.retainColors()
        if selecting { value.schemes.removeAll { scheme in !selection.contains(where: { scheme.name == $0 || scheme.name.hasPrefix($0 + "－") }) } }
        return value
    }
    var body: some View {
        List {
            ForEach(state.custom.schemes) { scheme in
                HStack {
                    if selecting {
                        Button { if !selection.insert(scheme.name).inserted { selection.remove(scheme.name) } } label: {
                            Image(systemName: selection.contains(scheme.name) ? "checkmark.square.fill" : "square").padding(8)
                        }.buttonStyle(.borderless).accessibilityIdentifier("selectScheme-" + scheme.name)
                    }
                NavigationLink {
                    CustomSchemeEditor(state: state, originalName: scheme.name)
                } label: {
                    HStack {
                        Circle().fill(TableColors.color(state.custom.schemes.firstIndex(where: { $0.name == scheme.name }).map { state.custom.color(at: $0) } ?? "#808080")).frame(width: 16, height: 16)
                        Text(scheme.name == "默認方案" ? ui("默認方案") : scheme.name)
                        Spacer(); Text("\(scheme.languages.count)").foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("schemeEditor-" + scheme.name)
                    if selecting {
                        Button(ui("改名")) { renaming = scheme.name; name = scheme.name; naming = true }.buttonStyle(.borderless)
                    }
                }
            }.onMove { source, destination in
                state.custom.retainColors()
                state.custom.schemes.move(fromOffsets: source, toOffset: destination)
            }

        }.environment(\.editMode, .constant(selecting ? .active : .inactive))
            .navigationTitle(ui("自選分區")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(ui("新建")) { renaming = nil; name = ""; naming = true }
                    Menu {
                        Button(ui("匯出自選分區")) { exporting = true }.disabled(selecting && selection.isEmpty)
                        Button(ui("匯入自選分區")) { importing = true }
                    } label: { Image(systemName: "square.and.arrow.up.on.square") }.accessibilityLabel(ui("匯入及匯出"))
                    Button(ui(selecting ? "完成" : "編輯")) { selecting.toggle(); selection = [] }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        Button(ui("全選")) { selection = Set(state.custom.schemes.map(\.name)) }
                        Spacer(); Text(ui("已選 ") + String(selection.count))
                        Button(ui("刪除"), role: .destructive) { remove(selection) }
                            .disabled(selection.isEmpty || selection.count == state.custom.schemes.count)
                    }.buttonStyle(.borderless).padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal).padding(.bottom, 6)
                }
            }
            .alert(ui(renaming == nil ? "新建" : "改名"), isPresented: $naming) {
                TextField(ui("方案名稱（空格可分級，如：江淮 洪巢）"), text: $name)
                Button(ui("取消"), role: .cancel) {}
                Button(ui("保存")) {
                    if let old = renaming {
                        if !state.custom.rename(name, scheme: old) { message = ui("方案名稱不能為空或重複") }
                        selection = []
                    } else if !state.custom.create(name) { message = ui("方案名稱不能為空或重複") }
                }
            }
            .fileExporter(isPresented: $exporting, document: CustomSchemeDocument(exported), contentType: .plainText, defaultFilename: "MCPDict-custom-languages") { result in
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
    private func remove(_ names: Set<String>) {
        let removed = Set(state.custom.schemes.filter { scheme in names.contains { scheme.name == $0 || scheme.name.hasPrefix($0 + "－") } }.map(\.name))
        guard removed.count < state.custom.schemes.count else { return }
        let current = state.custom.current
        for name in removed { state.custom.current = name; _ = state.custom.delete() }
        if state.custom.schemes.contains(where: { $0.name == current }) { state.custom.current = current }
        selection.subtract(removed)
    }

}

struct CustomSchemeEditor: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var state: LanguageSelectionState
    let originalName: String
    @State private var identity = ""
    @State private var name = ""
    @State private var hex = ""
    @State private var openedChild: String?
    @State private var addingChild = false
    @State private var childName = ""
    @State private var invalid = false
    private var children: [CustomLanguageSchemes.Scheme] {
        var seen = Set<String>()
        return state.custom.schemes.compactMap { scheme in
            guard scheme.name.hasPrefix(identity + "－"),
                  let part = scheme.name.dropFirst(identity.count + 1).split(separator: "－").first else { return nil }
            let path = identity + "－" + String(part)
            guard seen.insert(path).inserted else { return nil }
            return state.custom.schemes.first { $0.name == path } ?? .init(name: path, languages: [], colorHex: scheme.colorHex)
        }
    }
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
                        guard state.custom.rename(normalized, scheme: old) else { invalid = true; return }
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
            Section(ui("自選分區")) {
                ForEach(children) { child in
                    Button { openedChild = child.name } label: {
                        HStack {
                            Text(child.name.components(separatedBy: "－").last ?? child.name).foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.borderless).accessibilityIdentifier("childScheme-" + child.name)
                }.onMove { source, destination in
                    for child in children where !state.custom.schemes.contains(where: { $0.name == child.name }) { state.custom.schemes.append(child) }
                    state.custom.retainColors()
                    var ordered = children
                    ordered.move(fromOffsets: source, toOffset: destination)
                    let slots = state.custom.schemes.indices.filter { index in children.contains { $0.name == state.custom.schemes[index].name } }
                    for (slot, child) in zip(slots, ordered) { state.custom.schemes[slot] = child }
                }
                Button(ui("新建子分區")) { childName = ""; addingChild = true }.accessibilityIdentifier("newCustomSubgroup")
            }
            Section(ui("語言")) {
                LanguageDropdown(tables: model.availableTables, names: Binding(get: {
                    index.map { state.custom.schemes[$0].languages } ?? []
                }, set: { value in
                    if let i = index { state.custom.schemes[i].languages = value }
                }), state: model.customEditorSelection, inspect: { model.tableDetail = $0 }, showsDone: false, preservesHiddenSelection: true) {}
            }
        }.environment(\.editMode, .constant(.active))
            .navigationTitle(ui("自選分區")).navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $openedChild) { path in CustomSchemeEditor(state: state, originalName: path) }
            .onAppear {
                if identity.isEmpty {
                    identity = originalName; name = originalName
                    if index == nil {
                        let current = state.custom.current
                        _ = state.custom.create(originalName)
                        state.custom.current = current
                    }
                    hex = index.map { state.custom.color(at: $0) } ?? "#808080"
                }
            }
            .alert(ui("新建子分區"), isPresented: $addingChild) {
                TextField(ui("方案"), text: $childName)
                Button(ui("取消"), role: .cancel) {}
                Button(ui("保存")) {
                    let child = CustomLanguageSchemes.normalize(childName)
                    let current = state.custom.current
                    if child.isEmpty || !state.custom.create(identity + "－" + child) { invalid = true }
                    state.custom.current = current
                }
            }
            .alert(ui("請輸入有效且不重複的名稱，或六位十六進制顏色碼。"), isPresented: $invalid) { Button(ui("好"), role: .cancel) {} }
    }
}
