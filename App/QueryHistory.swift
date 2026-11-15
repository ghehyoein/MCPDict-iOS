import SwiftUI

struct QueryHistoryEntry: Codable, Identifiable, Equatable {
    var query: String
    var mode: String
    var id: String { mode + "\u{0}" + query }
}
enum QueryHistory {
    static func entries(_ namespace: String) -> [QueryHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: "queryHistory." + namespace) else { return [] }
        return (try? JSONDecoder().decode([QueryHistoryEntry].self, from: data)) ?? []
    }
    static func save(_ values: [QueryHistoryEntry], namespace: String) {
        if let data = try? JSONEncoder().encode(Array(values.prefix(10))) { UserDefaults.standard.set(data, forKey: "queryHistory." + namespace) }
    }
    static func record(_ query: String, mode: SearchMode, namespace: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = QueryHistoryEntry(query: query, mode: mode.rawValue)
        save([entry] + entries(namespace).filter { $0.id != entry.id }, namespace: namespace)
    }
}
struct QueryHistoryDropdown: View {
    let namespace: String
    var maximumHeight: CGFloat = 240
    let select: (QueryHistoryEntry) -> Void
    @State private var entries: [QueryHistoryEntry] = []
    @State private var confirm = false
    var body: some View {
        List {
            ForEach(entries) { entry in
                Button { select(entry) } label: {
                    HStack { Text(entry.query).lineLimit(1); Spacer(); Text(ui(entry.mode)).foregroundStyle(.secondary) }
                }.buttonStyle(.plain).accessibilityIdentifier("history-" + namespace + "-" + entry.query)
            }.onDelete { indices in entries.remove(atOffsets: indices); QueryHistory.save(entries, namespace: namespace) }
            Button(ui("刪除"), role: .destructive) { confirm = true }.foregroundStyle(.red)
        }.listStyle(.plain).frame(height: min(maximumHeight, CGFloat(entries.count + 1) * 44))
            .onAppear { entries = QueryHistory.entries(namespace) }
            .alert(ui("是否確定刪除所有歷史記錄"), isPresented: $confirm) {
                Button(ui("取消"), role: .cancel) {}
                Button(ui("刪除"), role: .destructive) { entries = []; QueryHistory.save([], namespace: namespace) }
            }
    }
}

// Resolve the input row's anchor above the containing List/VStack. A row-level
// overlay would be clipped by List cells or covered by the language selector.
private struct QueryHistoryAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
extension View {
    func queryHistoryAnchor(_ namespace: String) -> some View {
        anchorPreference(key: QueryHistoryAnchorKey.self, value: .bounds) { [namespace: $0] }
    }
    func queryHistoryOverlay(_ namespace: String, presented: Binding<Bool>, select: @escaping (QueryHistoryEntry) -> Void) -> some View {
        overlayPreferenceValue(QueryHistoryAnchorKey.self) { anchors in
            GeometryReader { geometry in
                if presented.wrappedValue, let anchor = anchors[namespace] {
                    let frame = geometry[anchor]
                    let room = max(0, geometry.size.height - frame.maxY - 8)
                    if frame.maxY > 0, frame.minY < geometry.size.height {
                        ZStack(alignment: .topLeading) {
                            // Leave the input row uncovered so typing, search and clear
                            // still receive their first tap while history is open.
                            Color.clear.contentShape(Rectangle())
                                .frame(height: max(0, frame.minY))
                                .onTapGesture { presented.wrappedValue = false }
                            Color.clear.contentShape(Rectangle())
                                .frame(height: max(0, geometry.size.height - frame.maxY))
                                .offset(y: max(0, frame.maxY))
                                .onTapGesture { presented.wrappedValue = false }
                                .accessibilityIdentifier("historyDismiss-" + namespace)
                            if room >= 44 {
                                QueryHistoryDropdown(namespace: namespace, maximumHeight: min(240, room)) { entry in
                                    presented.wrappedValue = false
                                    select(entry)
                                }
                                .frame(width: frame.width)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.2)))
                                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                                .offset(x: frame.minX, y: frame.maxY + 4)
                                .accessibilityIdentifier("historyOverlay-" + namespace)
                            }
                        }
                    }
                }
            }
        }
    }
}
