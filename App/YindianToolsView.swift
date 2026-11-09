import SwiftUI
import WebKit

struct ToolsHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(ui("猜方言")) { GuessGameView(kind: .language) }
                NavigationLink(ui("猜字")) { GuessGameView(kind: .character) }
                NavigationLink(ui("音典小工具")) { YindianToolsView() }
            }.navigationTitle(ui("工具"))
        }
    }
}

struct ToolMapResult: Identifiable {
    let id = UUID()
    let points: [DialectPoint]
}
struct YindianToolsView: View {
    @EnvironmentObject var model: AppModel
    @State private var map: ToolMapResult?
    var body: some View {
        ToolsWebView(model: model) { map = ToolMapResult(points: $0) }
            .navigationTitle(ui("音典小工具")).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $map) { value in ToolsComparisonMap(points: value.points) }
    }
}
struct ToolsComparisonMap: View {
    let points: [DialectPoint]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: DialectPoint?
    @AppStorage("baseMapStyle") private var style = "standard"
    var body: some View {
        NavigationStack {
            NativeDialectMap(points: points, fit: 1, mapStyle: style) { id in selected = points.first { $0.id == id } }
                .navigationTitle(ui("字音比較"))
                .toolbar { Button(ui("完成")) { dismiss() } }
                .sheet(item: $selected) { point in
                    NavigationStack { ScrollView { SystemText(point.copyText ?? "").padding() }.navigationTitle(point.name) }
                        .presentationDetents([.medium, .large])
                }
        }
    }
}

// Retain the upstream tool algorithms and UI. Only the Android bridge is replaced.
// A local-only prompt bridge preserves its synchronous JavaScript API while the
// database actor performs requests away from the main thread.
struct ToolsWebView: UIViewRepresentable {
    let model: AppModel
    let showMap: ([DialectPoint]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(model: model, showMap: showMap) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let script = """
        window.YindianBridge = new Proxy({}, {get: (_, name) => (...args) => {
            const result = JSON.parse(prompt('mcpdict-tools', JSON.stringify({name, args})) || '{"error":"Cancelled"}');
            if (result.error) throw new Error(result.error);
            return result.value;
        }});
        """
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = context.coordinator
        view.navigationDelegate = context.coordinator
        if let root = Bundle.main.resourceURL?.appendingPathComponent("YindianTools"), FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) {
            view.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let model: AppModel
        let showMap: ([DialectPoint]) -> Void
        init(model: AppModel, showMap: @escaping ([DialectPoint]) -> Void) { self.model = model; self.showMap = showMap }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard prompt == "mcpdict-tools", frame.isMainFrame, frame.request.url?.isFileURL == true,
                  let data = defaultText?.data(using: .utf8), let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = request["name"] as? String else { completionHandler(nil); return }
            let args = request["args"] as? [String] ?? []
            Task {
                do { completionHandler(try json(["value": try await call(name, args)])) }
                catch { completionHandler(try? json(["error": error.localizedDescription])) }
            }
        }
        private func json(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self) }
        private func call(_ name: String, _ args: [String]) async throws -> Any {
            let input = args.first ?? ""
            let tables = model.installed?.tables ?? []
            switch name {
            case "getApiVersion": return 3
            case "getInterfaceTexts":
                guard let url = Bundle.main.url(forResource: UserDefaults.standard.string(forKey: "uiLanguage") ?? "hant", withExtension: "txt", subdirectory: "InterfaceTexts") else { return "{}" }
                return try json(InterfaceTranslations.parse(String(contentsOf: url, encoding: .utf8)))
            case "getLanguages":
                return try json(tables.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { table -> [String: Any] in
                    let meta = table.metadata ?? [:]
                    return ["language": table.fullName, "label": table.name, "coordinate": table.location.map { "\($0.longitude),\($0.latitude)" } ?? "", "mapLevel": Int(meta["地圖級別"] ?? "0") ?? 0, "toneConfig": meta["聲調"] ?? "", "location": meta["地點"] ?? "", "historical": meta["歷史音"] ?? "", "color": TableColors.hexes(UserDefaults.standard.string(forKey: "colorScheme") == "dictionary" ? table.dictionaryColor : table.atlasColor).first ?? "#64748b", "subColor": TableColors.hexes(table.dictionaryColor).first ?? "#64748b"]
                })
            case "searchLanguages":
                return try json(tables.filter { InterfaceLanguage.matches($0.fullName + $0.name + ($0.metadata?["地點"] ?? ""), input) }.map { ["language": $0.fullName] })
            case "getTextVariants": return try json(Array(Set([input, input.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? input, input.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? input])))
            case "resolveCharacters":
                var result = [[String: Any]]()
                for char in CharacterResults.characters(input) {
                    let forms = CharacterVariants.expand(char)
                    let rows = try await model.repository.searchAllCharacters(forms.joined(), language: "")
                    let found = Set(rows.flatMap { $0.characters.split(whereSeparator: { $0.isWhitespace }).map(String.init) })
                    let candidates = forms.filter { found.contains($0) }
                    result.append(["input": char, "candidates": candidates.isEmpty ? [char] : candidates])
                }
                return try json(result)
            case "getGuangyunRows":
                let rows = try await model.repository.toolLanguageRows("廣韻")
                guard !rows.isEmpty else { throw DictionaryFailure(message: "請先下載廣韻字表") }
                return try json(rows.compactMap { row -> [String: String]? in
                    let fields = row.pronunciation.components(separatedBy: "/")
                    guard fields.count > 20 else { return nil }
                    return ["charGroup": row.characters, "description": fields[18], "she": fields[19], "fanqieDescription": fields[20], "guangyunRime": fields.count > 21 ? fields[21] : ""]
                })
            case "getLanguageRows":
                let rows = try await model.repository.toolLanguageRows(input)
                return try json(rows.map { ["漢字": $0.characters, "音標": display($0), "原始音標": $0.pronunciation] })
            case "queryChars":
                let rows = try await model.repository.searchAllCharacters(input, language: "")
                return try json(rows.map { ["字組": $0.characters, "語言": $0.language, "讀音": display($0), "原始讀音": $0.pronunciation, "註釋": $0.note] })
            case "showCompareMap":
                guard let data = input.data(using: .utf8), let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw DictionaryFailure(message: "無效的地圖資料") }
                let colors = ["same": "#15803d", "partial": "#ca8a04", "different": "#b91c1c", "missing": "#94a3b8"]
                let points = rows.enumerated().compactMap { index, row -> DialectPoint? in
                    guard let coordinate = row["coordinate"] as? String, let location = TableLocation.parse(coordinate) else { return nil }
                    return DialectPoint(id: String(index), name: row["label"] as? String ?? "", longitude: location.longitude, latitude: location.latitude, color: colors[row["status"] as? String ?? ""] ?? "#64748b", reading: "", copyText: row["detail"] as? String)
                }
                showMap(points); return ""
            default: throw DictionaryFailure(message: "Unknown tools request")
            }
        }
        private func display(_ row: Reading) -> String {
            // Tool analysis needs numeric source tone categories; these are the
            // same source readings that the Android tool's tone parser accepts.
            row.pronunciation
        }
    }
}
