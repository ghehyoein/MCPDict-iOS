import SwiftUI
import Combine

// Shared colors are independent of each page's language selection and filters.
@MainActor final class CustomPalette: ObservableObject {
    @Published private(set) var selected = ""
    @Published private(set) var choices = [String]()
    @Published private(set) var colors = [String: String]()
    private let source: LanguageSelectionState
    private var observation: AnyCancellable?
    var enabled: Bool { !selected.isEmpty }
    init(source: LanguageSelectionState) {
        self.source = source
        if source.custom.colorByScheme {
            source.custom.paletteScheme = source.custom.current
            source.custom.colorByScheme = false
        }
        observation = source.$custom.sink { [weak self] store in
            guard let self else { return }
            let names = store.schemes.map(\.name), existing = Set(names)
            self.choices = names + store.parents.filter { !existing.contains($0) }
            self.selected = store.paletteScheme.flatMap { self.choices.contains($0) ? $0 : nil } ?? ""
            self.colors = store.paletteColors()
        }
    }
    func select(_ name: String) {
        source.custom.paletteScheme = choices.contains(name) ? name : nil
        source.custom.colorByScheme = false
    }
}

struct PaletteControls: View {
    @EnvironmentObject private var palette: CustomPalette
    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker(ui("自選色"), selection: Binding(get: { palette.selected }, set: { palette.select($0) })) {
                    Text(ui("關閉")).tag("")
                    ForEach(palette.choices, id: \.self) { name in
                        Text(name == "默認方案" ? ui("默認方案") : name).tag(name)
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(compactUI("自選色")).lineLimit(1).fixedSize()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
            }.fixedSize(horizontal: true, vertical: false).layoutPriority(1)
                .accessibilityIdentifier("customColorMenu")
                .accessibilityValue(palette.enabled ? palette.selected : ui("關閉"))
            PaletteSwitch(isDisabled: palette.enabled)
        }
    }
}
