import SwiftUI

// All three tabs share the selection controls. Only the map floats its expanded content.
struct SelectionMenuButton: View {
    let count: Int
    let entryID: String
    @Binding var expanded: Bool
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack { Text(ui("已選 \(count) 個語言點")); Spacer(); Image(systemName: expanded ? "chevron.up" : "chevron.down") }
        }.buttonStyle(.borderless).accessibilityIdentifier(entryID)
    }
}

struct LanguageSelectionPanel: View {
    let tables: [TablePackage]
    @Binding var names: Set<String>
    let cacheKey: String
    let entryID: String
    var initialKind: MapSearchKind = .language
    var inspect: ((TablePackage) -> Void)? = nil
    var searchMode: Binding<SearchMode>? = nil
    var finished: () -> Void = {}
    @Binding var colorScheme: String
    @State private var kind: MapSearchKind = .language
    @Binding var expanded: Bool
    @State private var flags = LanguageFlags()
    @State private var restored = false
    private let cache = LanguageSelectionCache()
    private var scope: LanguageSelectionScope { kind == .region ? .terminalGroups : (kind == .administrative ? .administrativeGroups : .points) }
    private var grouping: TableGrouping { kind == .administrative ? .administrative : .atlas }
    private var key: String { cacheKey + "." + kind.rawValue }
    private var available: Set<String> { Set(scope.eligible(tables, grouping: grouping).map(\.name)) }
    private var chosen: Binding<Set<String>> {
        Binding(get: { names }, set: { names = $0; cache.save($0, for: key) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SelectionMenuButton(count: names.count, entryID: entryID, expanded: $expanded)
            if expanded { controls }
        }
        .onAppear { restoreInitial() }
        .onChange(of: tables) { _, _ in restoreInitial() }
        .onChange(of: kind) { old, new in
            guard restored, old != new else { return }
            cache.defaults.set(new.rawValue, forKey: "selectionMode." + cacheKey)
            colorScheme = cache.defaults.string(forKey: "palette." + key) ?? "atlas"
            restoreMode()
        }
        .onChange(of: colorScheme) { _, _ in if restored { cache.defaults.set(colorScheme, forKey: "palette." + key) } }
    }
    private var controls: some View {
                VStack(alignment: .leading, spacing: 8) {
                if let searchMode {
                    Picker(ui("查詢方式"), selection: searchMode) {
                        ForEach(SearchMode.allCases) { Text(ui($0.rawValue)).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                Picker(ui("檢索選項"), selection: $kind) {
                    ForEach(MapSearchKind.allCases) { Text(ui($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Picker(ui("分區方式"), selection: $colorScheme) {
                    Text(ui("地圖集二")).tag("atlas")
                    Text(ui("音典分區")).tag("dictionary")
                }.pickerStyle(.segmented).labelsHidden()
                HStack {
                    flagButton("方言島", $flags.island); flagButton("歷史音", $flags.history)
                }
                if kind == .custom { Text(ui("自選功能後續待更新，目前與語言模式相同")).font(.caption).foregroundStyle(.secondary) }
                LanguageDropdown(tables: tables, names: chosen, initialGrouping: grouping, scope: scope, regionCacheKey: key, inspect: inspect, palette: colorScheme == "dictionary" ? .dictionary : .atlas, flags: flags, fixedAdministrative: kind == .administrative) {
                    expanded = false; finished()
                }.id(key)
                }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    private func flagButton(_ title: String, _ value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            Label(ui(title), systemImage: value.wrappedValue ? "checkmark.square.fill" : "square")
        }.buttonStyle(.borderless)
    }
    private func restoreInitial() {
        guard !restored, !tables.isEmpty else { return }
        let savedKind = cache.defaults.string(forKey: "selectionMode." + cacheKey).flatMap(MapSearchKind.init(rawValue:)) ?? initialKind
        // Initialize the mode before enabling mode-change persistence.
        kind = savedKind
        if let saved = cache.load(cacheKey + "." + savedKind.rawValue) {
            let savedScope: LanguageSelectionScope = savedKind == .region ? .terminalGroups : (savedKind == .administrative ? .administrativeGroups : .points)
            let savedGrouping: TableGrouping = savedKind == .administrative ? .administrative : .atlas
            names = saved.intersection(Set(savedScope.eligible(tables, grouping: savedGrouping).map(\.name)))
        }
        cache.save(names, for: cacheKey + "." + savedKind.rawValue)
        cache.defaults.set(savedKind.rawValue, forKey: "selectionMode." + cacheKey)
        restored = true
    }
    private func restoreMode() {
        names = (cache.load(key) ?? []).intersection(available)
    }
}
