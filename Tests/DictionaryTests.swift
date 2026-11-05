import XCTest
import SQLite3
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
}
