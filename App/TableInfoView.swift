import SwiftUI

struct TableInfoView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let table: TablePackage
    @State private var log = ""
    @State private var statistics = [String: String]()
    private var current: TablePackage { model.table(named: table.name) ?? table }
    private func value(_ key: String) -> String {
        if key == "名稱" { return current.fullName }
        if let value = current.metadata?[key], !value.isEmpty, value != "null" { return MetadataText.plain(value) }
        if let value = statistics[key] { return value }
        if key == "地點" { return current.administrative.joined(separator: "/") }
        if key == "地圖集二分區" { return current.atlas.joined(separator: "－") }
        if key == "音典分區過渡色" { return DictionaryTransitions(tables: model.availableTables).description(current) }
        if key == "音典分區" { return current.dictionary.joined(separator: "－") }
        if key == "解析日志" { return log }
        if ["字數", "□數", "音節數", "不帶調音節數"].contains(key) { return ui("下載字表後統計") }
        return ""
    }
    private let first = ["名稱", "地點", "經緯度", "地圖集二分區", "音典分區", "音典分區過渡色", "字數", "□數", "音節數", "不帶調音節數"]
    private let second = ["錄入人", "維護人", "版本", "文件名", "字表來源", "參考文獻", "字表修改情況", "字表品質", "字表品質説明"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    SystemText(current.fullName).font(.title2).padding(.bottom, 12)
                    ForEach(first, id: \.self) { field($0) }
                    ForEach(second, id: \.self) { field($0) }
                    Color.clear.frame(height: 22)
                    SystemText(ui("解析日誌"), weight: .bold).font(.title2)
                    SystemText(value("解析日志"))
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle(table.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let location = current.location { ExternalMapMenu(location: location, name: current.name) }
                Button(ui("完成")) { dismiss() }
            }
            .task {
                if current.metadata == nil && !model.updating { await model.loadCatalog() }
                if let result = try? await model.repository.tableStatistics(current.name) { statistics = result }
                log = (try? await UpstreamDiagnostics.shared.log(for: current)) ?? ""
            }
        }
    }
    @ViewBuilder private func field(_ key: String) -> some View {
        if key == "文件名" {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                SystemText(ui(key) + "：", weight: .bold)
                if let source = current.metadata?["文件網址"], let url = URL(string: source), url.scheme == "https" {
                    Link(value(key), destination: url)
                } else { SystemText(value(key)) }
            }
        } else {
            SystemText(ui(key == "字表品質説明" ? "字表品質說明" : key) + "：" + value(key), boldPrefix: ui(key == "字表品質説明" ? "字表品質說明" : key) + "：")
            ForEach(MetadataText.links(current.metadata?[key] ?? ""), id: \.absoluteString) { url in
                Link(url.absoluteString, destination: url).font(.caption)
            }
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
