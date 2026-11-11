import SwiftUI

struct ToolsHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(ui("猜方言")) { GuessGameView(kind: .language) }
                NavigationLink(ui("猜字")) { GuessGameView(kind: .character) }
                NavigationLink(ui("長文注音")) { LongTextView() }
                NavigationLink(ui("古今演化")) { YindianToolsView(tool: .evolution) }
                NavigationLink(ui("字音比較")) { YindianToolsView(tool: .compare) }
            }.navigationTitle(ui("工具"))
        }
    }
}

struct ToolMapResult: Identifiable {
    let id = UUID()
    let points: [DialectPoint]
}
enum BuiltinAnalysisTool: String {
    case evolution, compare
    var title: String { self == .evolution ? "古今演化" : "字音比較" }
}
struct ToolsComparisonMap: View {
    let points: [DialectPoint]
    var title = "字音比較"
    @Environment(\.dismiss) private var dismiss
    @State private var selected: DialectPoint?
    @AppStorage("baseMapStyle") private var style = "standard"
    var body: some View {
        NavigationStack {
            NativeDialectMap(points: points, fit: 1, mapStyle: style) { id in selected = points.first { $0.id == id } }
                .navigationTitle(ui(title))
                .toolbar { Button(ui("完成")) { dismiss() } }
                .sheet(item: $selected) { point in
                    NavigationStack { ScrollView { SystemText(point.copyText ?? "").padding() }.navigationTitle(point.name) }
                        .presentationDetents([.medium, .large])
                }
        }
    }
}
