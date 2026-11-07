import SwiftUI

/// Dictionary and map observe one instance; downloads owns a separate instance.
@MainActor final class LanguageSelectionState: ObservableObject {
    let namespace: String
    private let defaults: UserDefaults
    @Published var expanded = false
    @Published var kind: MapSearchKind { didSet {
        guard kind != oldValue else { return }
        defaults.set(kind.rawValue, forKey: "selectionMode." + namespace)
        restoreControls()
    } }
    @Published var grouping: TableGrouping = .atlas { didSet {
        guard grouping != oldValue else { return }
        defaults.set(grouping.rawValue, forKey: "grouping." + key)
        expandedNodes = []
        region = defaults.string(forKey: "regionNode." + key + grouping.rawValue)
    } }
    @Published var flags: LanguageFlags { didSet {
        defaults.set(flags.island, forKey: "island." + namespace)
        defaults.set(flags.history, forKey: "history." + namespace)
    } }
    @Published var roles = Set(PersonRole.allCases) { didSet { defaults.set(roles.map(\.rawValue), forKey: "roles." + key) } }
    @Published var includeTransitions = false { didSet { defaults.set(includeTransitions, forKey: "transitions." + namespace) } }
    @Published var filter = ""
    @Published var expandedNodes = Set<String>()
    @Published var region: String? { didSet { defaults.set(region, forKey: "regionNode." + key + grouping.rawValue) } }
    var key: String { namespace + "." + kind.rawValue }
    var scope: LanguageSelectionScope { kind == .region ? .terminalGroups : kind == .administrative ? .administrativeGroups : .points }
    var groupingChoices: [TableGrouping] { kind == .region ? [.atlas, .dictionary] : TableGrouping.allCases }
    init(namespace: String, defaults: UserDefaults = .standard) {
        self.namespace = namespace; self.defaults = defaults
        kind = defaults.string(forKey: "selectionMode." + namespace).flatMap(MapSearchKind.init(rawValue:)) ?? .language
        flags = LanguageFlags(island: defaults.bool(forKey: "island." + namespace), history: defaults.bool(forKey: "history." + namespace))
        includeTransitions = defaults.bool(forKey: "transitions." + namespace)
        restoreControls()
    }
    func resetDefaults() {
        expanded = false; kind = .language; grouping = .atlas
        flags = LanguageFlags(); roles = Set(PersonRole.allCases); includeTransitions = false
        filter = ""; expandedNodes = []; region = nil
    }
    #if DEBUG
    func resetFixture() { resetDefaults() }
    #endif
    private func restoreControls() {
        let saved = defaults.string(forKey: "grouping." + key).flatMap(TableGrouping.init(rawValue:)) ?? .atlas
        grouping = kind == .administrative ? .administrative : (groupingChoices.contains(saved) ? saved : .atlas)
        roles = Set((defaults.stringArray(forKey: "roles." + key) ?? PersonRole.allCases.map(\.rawValue)).compactMap(PersonRole.init(rawValue:))).union([.editor])
        filter = ""; expandedNodes = []
        region = defaults.string(forKey: "regionNode." + key + grouping.rawValue)
    }
}

struct PaletteSwitch: View {
    @AppStorage("colorScheme") private var palette = "atlas"
    private var enabled: Binding<Bool> { Binding(get: { palette == "dictionary" }, set: { palette = $0 ? "dictionary" : "atlas" }) }
    var body: some View {
        NativePaletteSwitch(isOn: enabled)
            .fixedSize()
            .overlay {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Text("地").foregroundStyle(palette == "atlas" ? Color.blue : .white).frame(width: geometry.size.width / 2)
                        Text("音").foregroundStyle(palette == "dictionary" ? Color.orange : .white).frame(width: geometry.size.width / 2)
                    }.font(.system(size: 12, weight: .semibold)).frame(height: geometry.size.height)
                        .environment(\.layoutDirection, .leftToRight)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .accessibilityLabel(ui("地圖集二／音典分區配色"))
    }
}
private struct NativePaletteSwitch: UIViewRepresentable {
    @Binding var isOn: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UISwitch {
        let control = UISwitch()
        control.onTintColor = .systemOrange; control.tintColor = .systemBlue
        control.backgroundColor = .systemBlue; control.layer.cornerRadius = control.intrinsicContentSize.height / 2
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISwitch, context: Context) -> CGSize? { uiView.intrinsicContentSize }
    func updateUIView(_ control: UISwitch, context: Context) {
        context.coordinator.parent = self
        control.setOn(isOn, animated: false)
        control.accessibilityIdentifier = "paletteSwitch"
        control.accessibilityLabel = ui("地圖集二／音典分區配色")
        control.accessibilityValue = ui(isOn ? "音典分區" : "地圖集二")
    }
    final class Coordinator: NSObject {
        var parent: NativePaletteSwitch
        init(_ parent: NativePaletteSwitch) { self.parent = parent }
        @objc func changed(_ control: UISwitch) { parent.isOn = control.isOn }
    }
}
