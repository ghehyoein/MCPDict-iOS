import XCTest
import CryptoKit
@testable import MCPDictIOS

final class UpstreamTests: XCTestCase {
    func testTSVHashImportAndRollback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let data = Data("#漢字\t音標\t解釋\n中\tzhong1\t中心\n忠\tzhong1\t忠誠\n中\tzhong4\t命中\n𰻞\tbiang\t\n".utf8)
        var blob = Data("blob \(data.count)\0".utf8); blob.append(data)
        let hash = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        let commit = String(repeating: "b", count: 40)
        let table = TablePackage(id: String(repeating: "a", count: 24), name: "普通話", fullName: "普通話", atlas: ["官話"], dictionary: ["官話"], administrative: ["北京"], source: "fixture", sourceCommit: commit, recordCount: 0, size: Int64(data.count), sha256: String(repeating: "c", count: 64), url: URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(commit)/tools/tables/output/普通話.tsv")!, format: "upstream-tsv-v1", gitBlob: hash)
        let catalog = TableCatalog(schemaVersion: 1, version: commit, sourceRepository: UpstreamTables.repository, sourceCommit: commit, scope: "test", tables: [table])
        let source = root.appendingPathComponent("source.tsv")
        try data.write(to: source)
        let repo = DictionaryRepository()
        let store = TableStore(repository: repo, root: root.appendingPathComponent("tables"))
        _ = try await store.apply(catalog, selected: [table.id], localFiles: [table.id: source]) { _ in }
        let rows = try await repo.search("中", mode: .character, language: "")
        XCTAssertEqual(rows.map(\.characters), ["中", "中"])
        XCTAssertEqual(rows.map(\.note), ["中心", "命中"])
        var bad = table
        bad.gitBlob = String(repeating: "0", count: 40)
        let invalid = root.appendingPathComponent("invalid.db")
        XCTAssertThrowsError(try UpstreamTables.importTSV(data, table: bad, to: invalid))
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalid.path))
        let restored = try await store.restore()
        XCTAssertEqual(restored?.tables.first?.gitBlob, hash)
        let extended = try await repo.search("𰻞", mode: .character, language: "")
        XCTAssertEqual(extended.first?.characters, "𰻞")
    }
}
