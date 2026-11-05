import XCTest
import SQLite3
import CryptoKit
@testable import MCPDictIOS

final class DictionaryTests: XCTestCase {
    func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("fixture.db")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw DictionaryFailure(message: "Fixture open failed") }
        defer { sqlite3_close(db) }
        let sql = """
        CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋, tokenize='unicode61 remove_diacritics 0');
        CREATE VIRTUAL TABLE info USING fts5(簡稱, 語言);
        CREATE VIRTUAL TABLE mcpdict USING fts5(漢字);
        INSERT INTO info VALUES ('普通話', '普通話');
        INSERT INTO mcpdict VALUES ('中');
        INSERT INTO langs VALUES ('中 忠','普通話','zhong1','中心');
        INSERT INTO langs VALUES ('中 仲','普通話','zhong4','命中');
        INSERT INTO langs VALUES ('中','測試方言','tung1','測試');
        INSERT INTO langs VALUES ('𰻞','測試方言','biang','擴展字');
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DictionaryFailure(message: String(cString: sqlite3_errmsg(db)))
        }
        return url
    }

    func testSearchContract() async throws {
        let repo = DictionaryRepository()
        try await repo.open(fixture())
        let rows = try await repo.search("中", mode: .character, language: "普通話")
        XCTAssertEqual(rows.map(\.pronunciation), ["zhong1", "zhong4"])
        let unicode = try await repo.search("U+4E2D", mode: .character, language: "普通話")
        XCTAssertEqual(rows, unicode)
        let extensionCharacter = try await repo.search("𰻞", mode: .character, language: "")
        XCTAssertEqual(extensionCharacter.count, 1)
        let injection = try await repo.search("x\" OR \"zhong1", mode: .pronunciation, language: "")
        XCTAssertTrue(injection.isEmpty)
    }

    func testFailedActivationKeepsOldConnection() async throws {
        let repo = DictionaryRepository()
        let url = try fixture()
        try await repo.open(url)
        do {
            try await repo.activate(url) { throw DictionaryFailure(message: "Simulated pointer-write failure") }
            XCTFail("Expected pointer write to fail")
        } catch { }
        let rows = try await repo.search("中", mode: .character, language: "普通話")
        XCTAssertEqual(rows.count, 2)
        let invalid = url.deletingLastPathComponent().appendingPathComponent("broken.db")
        try Data("not sqlite".utf8).write(to: invalid)
        do {
            try await repo.activate(invalid) { XCTFail("Invalid DB must never commit its pointer") }
            XCTFail("Expected validation to fail")
        } catch { }
        let after = try await repo.search("中", mode: .character, language: "普通話")
        XCTAssertEqual(after, rows)
    }

    func testManifestRejectsIncompatibleSchema() throws {
        let manifest = DataManifest(schemaVersion: 99, version: "test", sourceCommit: String(repeating: "a", count: 40), sourceRepository: "https://github.com/osfans/MCPDict", database: .init(url: URL(string: "https://github.com/example/data/releases/download/test/mcpdict.db")!, size: 1024, sha256: String(repeating: "b", count: 64)))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testTableDownloadContractRestoreAndRemoval() async throws {
        let file = try fixture()
        do {
            let db = try SQLiteConnection(url: file, readOnly: false)
            _ = try db.rows("DELETE FROM langs WHERE 語言 != '普通話'")
        }
        let bytes = try Data(contentsOf: file)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        func table(_ hash: String) -> TablePackage {
            TablePackage(id: String(repeating: "a", count: 24), name: "普通話", fullName: "普通話", atlas: ["現代標準漢語"], dictionary: ["現代標準漢語"], administrative: ["北京"], source: "Test fixture", sourceCommit: String(repeating: "b", count: 40), recordCount: 2, size: Int64(bytes.count), sha256: hash, url: URL(string: "https://github.com/example/data/releases/download/test/table.db")!)
        }
        func catalog(_ package: TablePackage) -> TableCatalog {
            TableCatalog(schemaVersion: 1, version: "test", sourceRepository: "https://github.com/osfans/MCPDict", sourceCommit: package.sourceCommit, scope: "test", tables: [package])
        }
        let package = table(digest)
        let repo = DictionaryRepository()
        let directory = file.deletingLastPathComponent().appendingPathComponent("installed")
        let store = TableStore(repository: repo, root: directory)
        let installed = try await store.apply(catalog(package), selected: [package.id], localFiles: [package.id: file]) { _ in }
        XCTAssertEqual(installed.tables.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Original import must not be moved")
        let rows = try await repo.search("中", mode: .character, language: "普通話")
        XCTAssertEqual(rows.count, 2)
        do {
            let bad = table(String(repeating: "0", count: 64))
            _ = try await store.apply(catalog(bad), selected: [bad.id], localFiles: [bad.id: file]) { _ in }
            XCTFail("Bad hash must fail")
        } catch { }
        let unchanged = try await repo.search("中", mode: .character, language: "普通話")
        XCTAssertEqual(unchanged, rows)
        let restoredRepo = DictionaryRepository()
        let restoredStore = TableStore(repository: restoredRepo, root: directory)
        let restored = try await restoredStore.restore()
        XCTAssertEqual(restored?.tables, [package])
        let restoredRows = try await restoredRepo.search("中", mode: .character, language: "普通話")
        XCTAssertEqual(restoredRows, rows)
        _ = try await store.apply(catalog(package), selected: []) { _ in }
        let languages = try await repo.languages()
        XCTAssertTrue(languages.isEmpty)
    }
}
