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
                NavigationLink(ui("多地對應")) { AdditionalAnalysisView(kind: .correspondence) }
                NavigationLink(ui("單字音類")) { AdditionalAnalysisView(kind: .soundClasses) }
                NavigationLink(ui("字音比較")) { YindianToolsView(tool: .compare) }
                NavigationLink(ui("語音分析小工具")) { SpeechToolView() }
            }.appPageStyle().navigationTitle(ui("工具"))
        }
    }
}

struct AnalysisLegend: Identifiable {
    let title: String
    let color: String
    let names: Set<String>
    var id: String { title }
}
struct ToolMapResult: Identifiable {
    let id = UUID()
    let points: [DialectPoint]
    var legend: [AnalysisLegend] = []
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
        return points.filter { point in (model.table(named: point.id) ?? model.table(named: point.name)).map { flags.matches($0) } ?? true }
    }
    var title = "字音比較"
    var legend: [AnalysisLegend] = []
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
                if !legend.isEmpty {
                    let names = Set(visible.map(\.id))
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(legend) { item in
                                HStack {
                                    Circle().fill(TableColors.color(item.color)).frame(width: 10, height: 10)
                                    Text(item.title + " (\(item.names.intersection(names).count))")
                                }
                            }
                        }.padding(.horizontal)
                    }
                }
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
