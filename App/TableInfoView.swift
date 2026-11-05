import SwiftUI

struct TableInfoView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let table: TablePackage
    private var current: TablePackage { model.table(named: table.name) ?? table }
    private var fields: [String: String] {
        current.metadata ?? ["語言": current.fullName, "簡稱": current.name, "字表來源": current.source,
                             "地圖集二分區": current.atlas.joined(separator: " / "), "音典分區": current.dictionary.joined(separator: " / ")]
    }
    var body: some View {
        NavigationStack {
            List {
                if current.metadata == nil {
                    Text(ui("完整字表資訊尚未取得，請連網更新目錄。")).font(.caption)
                    Button(ui("更新目錄")) { Task { await model.loadCatalog() } }.disabled(model.updating)
                }
                ForEach(fields.keys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ui(key)).font(.caption).foregroundStyle(.secondary)
                        let raw = fields[key] ?? ""
                        Text(raw.isEmpty ? ui("未填寫") : MetadataText.plain(raw)).textSelection(.enabled)
                        ForEach(MetadataText.links(raw), id: \.absoluteString) { url in
                            Link(url.absoluteString, destination: url).font(.caption)
                        }
                    }.padding(.vertical, 3)
                }
            }
            .navigationTitle(table.name)
            .toolbar { Button(ui("完成")) { dismiss() } }
            .task { if current.metadata == nil && !model.updating { await model.loadCatalog() } }
        }
    }
}

// Display source descriptions as text and explicit links, never as executable HTML.
enum MetadataText {
    static func plain(_ value: String) -> String {
        value.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
    static func links(_ value: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: "(?i)href\\s*=\\s*[\"']?(https?://[^\\s\"'<>]+)") else { return [] }
        let source = value as NSString
        let urls = regex.matches(in: value, range: NSRange(location: 0, length: source.length)).compactMap { match -> URL? in
            URL(string: source.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&"))
        }
        return Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
    }
}
