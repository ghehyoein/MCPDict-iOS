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
    @State private var paletteInfo = false
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
                HStack(spacing: 10) {
                    flagButton("方言島", $flags.island); flagButton("歷史音", $flags.history)
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        paletteButton("地", value: "atlas", color: .blue)
                        paletteButton("音", value: "dictionary", color: .orange)
                    }.clipShape(Capsule()).fixedSize()
                    Button { paletteInfo = true } label: { Image(systemName: "info.circle").foregroundStyle(.blue) }
                        .buttonStyle(.plain).accessibilityLabel(ui("顏色切換說明"))
                }
                .alert(ui("顯示顏色"), isPresented: $paletteInfo) {
                    Button(ui("好"), role: .cancel) {}
                } message: { Text(ui("「地」使用地圖集二配色，「音」使用音典分區配色。只切換顯示顏色，不改變分類方式、選中範圍或已提交結果。")) }
                if kind == .custom { Text(ui("自選功能後續待更新，目前與語言模式相同")).font(.caption).foregroundStyle(.secondary) }
                LanguageDropdown(tables: tables, names: chosen, initialGrouping: grouping, scope: scope, regionCacheKey: key, inspect: inspect, palette: colorScheme == "dictionary" ? .dictionary : .atlas, flags: flags, fixedAdministrative: kind == .administrative) {
                    expanded = false; finished()
                }.id(key)
                }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    private func paletteButton(_ title: String, value: String, color: Color) -> some View {
        Button { colorScheme = value } label: {
            Text(ui(title)).font(.system(size: 13, weight: colorScheme == value ? .bold : .regular))
                .foregroundStyle(.white).frame(width: 26, height: 30)
                .background(color.opacity(colorScheme == value ? 1 : 0.35))
                .overlay { if colorScheme == value { Capsule().stroke(.white, lineWidth: 1.5).padding(2) } }
        }.buttonStyle(.plain).accessibilityLabel(ui(value == "atlas" ? "地圖集二" : "音典分區"))
            .accessibilityAddTraits(colorScheme == value ? .isSelected : [])
    }
    private func flagButton(_ title: String, _ value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            Label(ui(title), systemImage: value.wrappedValue ? "checkmark.square.fill" : "square").contentTransition(.identity).transaction { $0.animation = nil; $0.disablesAnimations = true }
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
