#if DEBUG
import Foundation

enum UITestFixtures {
    static var catalog: TableCatalog {
        let commit = String(repeating: "a", count: 40)
        let table = TablePackage(id: String(repeating: "a", count: 24), name: "示例語言點", fullName: "示例語言點", atlas: ["漢語", "官話", "北京"], dictionary: ["漢語"], administrative: ["北京"], source: "UI test", sourceCommit: commit, recordCount: 1, size: 100, sha256: String(repeating: "b", count: 64), url: URL(string: "https://github.com/example/data/releases/download/test/test.db")!, metadata: ["維護人":"測試維護人", "簡稱":"示例語言點"])
        return TableCatalog(schemaVersion: 1, version: "ui-test", sourceRepository: UpstreamTables.repository, sourceCommit: commit, scope: "", tables: [table])
    }
}
#endif
