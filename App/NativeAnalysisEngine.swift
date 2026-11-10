import Foundation
import JavaScriptCore

// No web view or page load: run upstream calculations off the UI thread.
enum NativeAnalysisEngine {
    static func run(_ data: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "app", withExtension: "js", subdirectory: "YindianTools"),
                  let context = JSContext() else { throw DictionaryFailure(message: "Analysis engine unavailable") }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            if let error = context.exception { throw DictionaryFailure(message: error.toString()) }
            let input = try JSONSerialization.jsonObject(with: data)
            guard let result = context.objectForKeyedSubscript("nativeAnalysis")?.call(withArguments: [input]), context.exception == nil,
                  let value = result.toObject() else { throw DictionaryFailure(message: context.exception?.toString() ?? "Analysis failed") }
            return try JSONSerialization.data(withJSONObject: value)
        }.value
    }
}
struct EvolutionGroup: Decodable, Identifiable {
    let oldValue: String
    let modernValue: String
    let chars: [String]
    let readings: [String]
    let positions: [String]
    let subtypes: [String]
    var id: String { oldValue + "\u{0}" + modernValue }
}
struct ComparisonGroup: Decodable, Identifiable {
    let name: String
    let status: String
    let readings: [[String]]
    let normalized: [[String]]
    var id: String { name }
    var title: String { ["same":"全同", "partial":"部分相同", "different":"全異", "missing":"缺資料"][status] ?? status }
    var color: String { ["same":"#15803d", "partial":"#ca8a04", "different":"#b91c1c", "missing":"#94a3b8"][status] ?? "#808080" }
}
