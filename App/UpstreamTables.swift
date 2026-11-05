import Foundation
import CryptoKit

struct UpstreamRateLimit: LocalizedError {
    var errorDescription: String? { "GitHub 暫時限制請求，請稍後重試；離線資料不受影響" }
}

// Read the Android repository's normalized output, pinned to one commit per refresh.
enum UpstreamTables {
    static let repository = "https://github.com/osfans/MCPDict"
    struct Tree: Decodable {
        let sha: String
        let truncated: Bool?
        let tree: [Entry]
    }
    struct Entry: Decodable {
        let path: String
        let type: String
        let sha: String
        let size: Int64?
    }
    static func get(_ url: URL, limit: Int = 20_000_000) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.setValue("MCPDict-iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode
        let remaining = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-RateLimit-Remaining")
        if code == 429 || (code == 403 && remaining == "0") { throw UpstreamRateLimit() }
        guard code == 200, data.count <= limit else {
            throw DictionaryFailure(message: "無法取得上游字表（HTTP \(code ?? 0)），請稍後重試")
        }
        return data
    }
    static func catalog() async throws -> TableCatalog {
        struct Head: Decodable { let sha: String }
        let head = try JSONDecoder().decode(Head.self, from: await get(URL(string: "https://api.github.com/repos/osfans/MCPDict/commits/master")!))
        guard head.sha.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { throw DictionaryFailure(message: "上游版本格式錯誤") }
        let base = URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(head.sha)/tools/tables/output/")!
        async let treeData = get(URL(string: "https://api.github.com/repos/osfans/MCPDict/git/trees/\(head.sha)?recursive=1")!)
        async let detailsData = get(base.appendingPathComponent("_詳情.json"))
        let tree = try JSONDecoder().decode(Tree.self, from: await treeData)
        guard tree.truncated != true else { throw DictionaryFailure(message: "上游目錄過大，無法安全取得完整字表清單") }
        guard let metadata = try JSONSerialization.jsonObject(with: await detailsData) as? [String: [String: Any]] else { throw DictionaryFailure(message: "上游分區資料格式變更") }
        let prefix = "tools/tables/output/"
        let sourcePaths = Set(tree.tree.filter { $0.type == "blob" }.map(\.path))
        var tables = [TablePackage]()
        for entry in tree.tree where entry.type == "blob" && entry.path.hasPrefix(prefix) && entry.path.hasSuffix(".tsv") {
            let filename = String(entry.path.dropFirst(prefix.count))
            guard !filename.contains("/"), let size = entry.size, size > 0 else { continue }
            let name = String(filename.dropLast(4))
            guard let info = metadata[name] else { continue }
            func value(_ key: String) -> String { info[key] as? String ?? "" }
            func path(_ key: String) -> [String] {
                let parts = value(key).components(separatedBy: "－").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return parts.isEmpty ? ["未分類"] : parts
            }
            let admin = ["省", "市", "縣", "鎮", "村", "自然村"].map(value).filter { !$0.isEmpty }
            let id = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
            // Stable cache identity changes only when this source blob changes.
            let identity = SHA256.hash(data: Data(("tsv-v1:" + entry.sha).utf8)).map { String(format: "%02x", $0) }.joined()
            var fields = metadataStrings(info)
            let sourceName = value("文件名")
            let sourcePath = "tools/tables/data/" + sourceName
            if !sourceName.isEmpty, sourcePaths.contains(sourcePath) {
                fields["文件網址"] = URL(string: "https://github.com/osfans/MCPDict/blob/\(head.sha)/")!.appendingPathComponent(sourcePath).absoluteString
            }
            tables.append(TablePackage(id: String(id), name: name, fullName: value("語言"), atlas: path("地圖集二分區"), dictionary: path("音典分區"), administrative: admin.isEmpty ? ["未標註行政區"] : admin, source: value("字表來源"), sourceCommit: head.sha, recordCount: 0, size: size, sha256: identity, url: base.appendingPathComponent(filename), metadata: fields, location: TableLocation.parse(value("經緯度")), atlasColor: value("地圖集二顏色"), dictionaryColor: value("音典顏色"), format: "upstream-tsv-v1", gitBlob: entry.sha))
        }
        guard !tables.isEmpty else { throw DictionaryFailure(message: "上游目錄沒有可用字表") }
        let catalog = TableCatalog(schemaVersion: 1, version: head.sha, sourceRepository: repository, sourceCommit: head.sha, scope: "直接連接安卓上游 · \(tables.count) 份字表 · \(head.sha.prefix(7))", tables: tables.sorted { $0.name < $1.name })
        try catalog.validate()
        return catalog
    }

    static func metadataStrings(_ info: [String: Any]) -> [String: String] {
        info.mapValues { value in
            if let string = value as? String { return string }
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), let string = String(data: data, encoding: .utf8) { return string }
            return String(describing: value)
        }
    }

    static func importTSV(_ data: Data, table: TablePackage, to file: URL) throws {
        var blob = Data("blob \(data.count)\0".utf8)
        blob.append(data)
        let digest = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        guard data.count == table.size, digest == table.gitBlob, let text = String(data: data, encoding: .utf8) else {
            throw DictionaryFailure(message: "\(table.name)：上游檔案大小、Git 雜湊或編碼校驗失敗")
        }
        let db = try SQLiteConnection(url: file, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋, tokenize='unicode61 remove_diacritics 0')")
        _ = try db.rows("CREATE VIRTUAL TABLE info USING fts5(簡稱, 語言)")
        _ = try db.rows("CREATE VIRTUAL TABLE mcpdict USING fts5(漢字)")
        _ = try db.rows("INSERT INTO info VALUES (?,?)", [table.name, table.fullName])
        _ = try db.rows("BEGIN")
        var count = 0
        for line in text.components(separatedBy: "\n") {
            try Task.checkCancellation()
            let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { throw DictionaryFailure(message: "\(table.name)：字表行格式不相容") }
            let characters = fields[0].map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
            _ = try db.rows("INSERT INTO langs VALUES (?,?,?,?)", [characters, table.name, fields[1], fields.dropFirst(2).joined(separator: "\t")])
            count += 1
        }
        guard count > 0 else { throw DictionaryFailure(message: "\(table.name)：字表沒有讀音") }
        _ = try db.rows("COMMIT")
        try db.validate(requireSample: false)
    }
}
