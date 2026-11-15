import SwiftUI

struct ToolsHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(ui("猜方言")) { GuessGameView(kind: .language) }
                NavigationLink(ui("猜字")) { GuessGameView(kind: .character) }
                NavigationLink(ui("長文注音")) { LongTextView() }
                NavigationLink(ui("古今演化")) { YindianToolsView(tool: .evolution) }
                NavigationLink(ui("方言→中古")) { YindianToolsView(reverse: true) }
                NavigationLink(ui("兩地對應")) { AdditionalAnalysisView(kind: .correspondence) }
                NavigationLink(ui("單字音類")) { AdditionalAnalysisView(kind: .soundClasses) }
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
    @EnvironmentObject private var model: AppModel
    @State private var showHistory = true
    @State private var showIslands = true
    private var visible: [DialectPoint] {
        var flags = LanguageFlags()
        flags.historyMode = showHistory ? .show : .hide
        flags.islandMode = showIslands ? .show : .hide
        return points.filter { point in model.table(named: point.id).map { flags.matches($0) } ?? true }
    }
    var title = "字音比較"
    @Environment(\.dismiss) private var dismiss
    @State private var selected: DialectPoint?
    @AppStorage("baseMapStyle") private var style = "standard"
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Toggle(ui("歷史音"), isOn: $showHistory)
                    Toggle(ui("方言島"), isOn: $showIslands)
                    Text("\(visible.count)").monospacedDigit()
                }.padding()
                NativeDialectMap(points: visible, fit: 1, mapStyle: style) { id in selected = points.first { $0.id == id } }
                }
                .navigationTitle(ui(title))
                .toolbar { Button(ui("完成")) { dismiss() } }
                .sheet(item: $selected) { point in
                    NavigationStack { ScrollView { SystemText(point.copyText ?? "").padding() }.navigationTitle(point.name) }
                        .presentationDetents([.medium, .large])
                }
        }
    }
}
