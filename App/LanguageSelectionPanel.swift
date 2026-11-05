import SwiftUI

// Shared by dictionary, downloads and map so selection rules cannot drift apart.
struct LanguageSelectionPanel: View {
    let tables: [TablePackage]
    @Binding var names: Set<String>
    let cacheKey: String
    let entryID: String
    var initialKind: MapSearchKind = .language
    var inspect: ((TablePackage) -> Void)? = nil
    var finished: () -> Void = {}
    @AppStorage("colorScheme") private var colorScheme = "atlas"
    @State private var kind: MapSearchKind = .language
    @State private var expanded = false
    @State private var restored = false
    private let cache = LanguageSelectionCache()
    private var scope: LanguageSelectionScope { kind == .region ? .terminalGroups : (kind == .administrative ? .topGroups : .points) }
    private var grouping: TableGrouping { kind == .administrative ? .administrative : (colorScheme == "dictionary" ? .dictionary : .atlas) }
    private var key: String { cacheKey + "." + kind.rawValue }
    private var available: Set<String> { Set(scope.eligible(tables, grouping: grouping).map(\.name)) }
    private var chosen: Binding<Set<String>> {
        Binding(get: { names }, set: { names = $0; cache.save($0, for: key) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(ui("檢索選項"), selection: $kind) {
                ForEach(MapSearchKind.allCases) { Text(ui($0.rawValue)).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Button { expanded = true } label: {
                    HStack { Text(ui("已選 \(names.count) 個語言點")); Spacer(); Image(systemName: "chevron.down") }
                }.buttonStyle(.borderless).accessibilityIdentifier(entryID)
                Picker(ui("分區顏色"), selection: $colorScheme) {
                    Text(ui("地圖集二")).tag("atlas")
                    Text(ui("音典分區")).tag("dictionary")
                }.pickerStyle(.menu)
            }
            if kind == .custom { Text(ui("自選功能後續待更新，目前與語言模式相同")).font(.caption).foregroundStyle(.secondary) }
            if expanded {
                LanguageDropdown(tables: tables, names: chosen, initialGrouping: grouping, scope: scope, inspect: inspect) {
                    expanded = false; finished()
                }.id(key + grouping.rawValue)
            }
        }
        .onAppear { restoreInitial() }
        .onChange(of: tables.map(\.id)) { _, _ in restoreInitial() }
        .onChange(of: kind) { old, new in
            guard restored, old != new else { return }
            cache.defaults.set(new.rawValue, forKey: "selectionMode." + cacheKey)
            restoreMode()
        }
        .onChange(of: colorScheme) { _, _ in if restored && kind == .region { restoreMode() } }
    }
    private func restoreInitial() {
        guard !restored, !tables.isEmpty else { return }
        let savedKind = cache.defaults.string(forKey: "selectionMode." + cacheKey).flatMap(MapSearchKind.init(rawValue:)) ?? initialKind
        // Initialize the mode before enabling mode-change persistence.
        kind = savedKind
        if let saved = cache.load(cacheKey + "." + savedKind.rawValue) {
            let savedScope: LanguageSelectionScope = savedKind == .region ? .terminalGroups : (savedKind == .administrative ? .topGroups : .points)
            let savedGrouping: TableGrouping = savedKind == .administrative ? .administrative : (colorScheme == "dictionary" ? .dictionary : .atlas)
            names = saved.intersection(Set(savedScope.eligible(tables, grouping: savedGrouping).map(\.name)))
        }
        cache.save(names, for: cacheKey + "." + savedKind.rawValue)
        cache.defaults.set(savedKind.rawValue, forKey: "selectionMode." + cacheKey)
        restored = true
    }
    private func restoreMode() {
        names = []
        names = (cache.load(key) ?? []).intersection(available)
        finished()
    }
}
