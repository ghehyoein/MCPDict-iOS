#if DEBUG
import Foundation

enum UITestFixtures {
    static func database() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui-fixture.db")
        let db = try SQLiteConnection(url: url, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE IF NOT EXISTS langs USING fts5(字組, 語言, 讀音, 註釋)")
        _ = try db.rows("DELETE FROM langs")
        _ = try db.rows("INSERT INTO langs VALUES (?,?,?,?)", ["中", "示例語言點", "tɕiɔŋ1", ""])
        return url
    }
    static var catalog: TableCatalog {
        let commit = String(repeating: "a", count: 40)
        let table = TablePackage(id: String(repeating: "a", count: 24), name: "示例語言點", fullName: "示例語言點", atlas: ["漢語", "官話", "北京"], dictionary: ["漢語"], administrative: ["北京", "", "東城", "示例街道"], source: "UI test", sourceCommit: commit, recordCount: 1, size: 100, sha256: String(repeating: "b", count: 64), url: URL(string: "https://github.com/example/data/releases/download/test/test.db")!, metadata: ["省":"北京", "市":"", "縣":"東城", "鎮":"示例街道", "維護人":"測試維護人", "簡稱":"示例語言點"], location: TableLocation(longitude: 116.4, latitude: 39.9), atlasColor: "#008080", dictionaryColor: "#008080")
        var tables = [table]
        if ProcessInfo.processInfo.arguments.contains("--tree-fixture") {
            tables = ["吳語", "歷史音", "民族語", "粵語"].enumerated().map { index, root in
                TablePackage(id: String(repeating: String(index + 1), count: 24), name: root + "測試點", fullName: root + "測試點", atlas: [root, root + "子區"], dictionary: [root, root + "子區"], administrative: [root], source: "UI test", sourceCommit: commit, recordCount: 1, size: 100, sha256: String(repeating: "b", count: 64), url: table.url)
            }
        }
        return TableCatalog(schemaVersion: 1, version: "ui-test", sourceRepository: UpstreamTables.repository, sourceCommit: commit, scope: "", tables: tables)
    }
}
#endif
