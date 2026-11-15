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
        }.listStyle(.plain).frame(height: min(240, CGFloat(entries.count + 1) * 44))
            .onAppear { entries = QueryHistory.entries(namespace) }
            .alert(ui("是否確定刪除所有歷史記錄"), isPresented: $confirm) {
                Button(ui("取消"), role: .cancel) {}
                Button(ui("刪除"), role: .destructive) { entries = []; QueryHistory.save([], namespace: namespace) }
            }
    }
}
