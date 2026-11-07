import SwiftUI

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
    @ObservedObject var state: LanguageSelectionState
    let entryID: String
    var inspect: ((TablePackage) -> Void)? = nil
    var finished: () -> Void = {}
    var alwaysExpanded = false
    @AppStorage("colorScheme") private var palette = "atlas"
    @State private var restored = false
    @State private var paletteInfo = false
    private let cache = LanguageSelectionCache()
    private var chosen: Binding<Set<String>> {
        Binding(get: { names }, set: { names = $0; cache.save($0, for: state.key) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if alwaysExpanded {
                Text(ui("已選 \(names.count) 個語言點")).foregroundStyle(AppAccent.color).accessibilityIdentifier(entryID)
            } else { SelectionMenuButton(count: names.count, entryID: entryID, expanded: $state.expanded) }
            if alwaysExpanded || state.expanded { controls }
        }
        .onAppear { restoreInitial() }
        .onChange(of: tables) { _, _ in restoreInitial() }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(ui("檢索選項"), selection: Binding(get: { state.kind }, set: { mode in
                // Read the destination cache before changing shared controls. Child
                // refreshes must not overwrite it with the previous mode's names.
                let saved = cache.load(state.namespace + "." + mode.rawValue) ?? []
                state.kind = mode
                names = restoredNames(saved)
                cache.save(names, for: state.key)
            })) {
                ForEach(MapSearchKind.allCases) { Text(ui($0.rawValue)).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 10) {
                flagButton("方言島", $state.flags.island)
                flagButton("歷史音", $state.flags.history)
                if state.kind == .region && state.grouping == .dictionary { TransitionToggle(state: state) }
                Spacer(minLength: 0)
                PaletteSwitch()
                Button { paletteInfo = true } label: { Image(systemName: "info.circle").foregroundStyle(.blue) }
                    .buttonStyle(.plain).accessibilityLabel(ui("顏色切換說明"))
            }
            .alert(ui("顯示顏色"), isPresented: $paletteInfo) {
                Button(ui("好"), role: .cancel) {}
            } message: { Text(ui("此開關切換語言點顯示顏色。「地」使用地圖集二分區配色，「音」使用音典分區配色")) }
            if state.kind == .custom { SystemText(ui("自選功能後續待更新，目前與語言模式相同"), color: .secondaryLabel).font(.caption) }
            LanguageDropdown(tables: tables, names: chosen, state: state, inspect: inspect, palette: palette == "dictionary" ? .dictionary : .atlas, showsDone: !alwaysExpanded) {
                state.expanded = false; finished()
            }.id(state.key)
        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    private func flagButton(_ title: String, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 0) {
            Button { value.wrappedValue.toggle() } label: {
                Image(systemName: value.wrappedValue ? "checkmark.square.fill" : "square")
                    .contentTransition(.identity).transaction { $0.animation = nil; $0.disablesAnimations = true }
            }.buttonStyle(.borderless).accessibilityLabel(ui(title))
            SystemText(ui(title), color: AppAccent.uiColor, onTap: { value.wrappedValue.toggle() })
        }
    }

    private func restoreInitial() {
        guard !restored, !tables.isEmpty else { return }
        names = restoredNames(cache.load(state.key) ?? names)
        cache.save(names, for: state.key)
        restored = true
    }
    private func restoredNames(_ saved: Set<String>) -> Set<String> {
        var eligible = state.scope.eligible(tables.filter(state.flags.matches), grouping: state.grouping, roles: state.roles)
        if state.grouping == .dictionary && state.includeTransitions {
            eligible = eligible.filter(DictionaryTransitions(tables: tables).hasTransition)
        }
        return saved.intersection(Set(eligible.map(\.name)))
    }
}

struct TransitionToggle: View {
    @ObservedObject var state: LanguageSelectionState
    var body: some View {
        Button { state.includeTransitions.toggle() } label: {
            HStack(spacing: 0) {
                Image(systemName: state.includeTransitions ? "checkmark.square.fill" : "square")
                Text(ui("過渡色"))
            }.fixedSize().contentTransition(.identity)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }.buttonStyle(.borderless).accessibilityIdentifier("includeDictionaryTransitions")
    }
}
