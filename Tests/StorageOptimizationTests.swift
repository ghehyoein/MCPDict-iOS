import XCTest
import CryptoKit
@testable import MCPDictIOS

final class StorageOptimizationTests: XCTestCase {
    private func fixture() throws -> (URL, URL, TableInstallation) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(UUID().uuidString + ".db")
        let db = try SQLiteConnection(url: file, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋, tokenize='unicode61 remove_diacritics 0')")
        _ = try db.rows("CREATE VIRTUAL TABLE info USING fts5(簡稱, 語言, 檔案)")
        _ = try db.rows("CREATE VIRTUAL TABLE mcpdict USING fts5(漢字, 資料)")
        try db.transaction {
            try db.batch("INSERT INTO langs(rowid,字組,語言,讀音,註釋) VALUES(?,?,?,?,?)") { insert in
                try insert(["7", "中 忠", "甲", "tɕiŋ53", "白讀\t完整註釋"])
                try insert(["9", "中 仲", "甲", "tɕiŋ51", "文讀"])
                try insert(["20", "𰻞", "乙", "biang", "擴展漢字\t第二欄"])
                for i in 0..<4000 { try insert([String(100+i), "好", "乙", "hæ3", "完整資料"] ) }
            }
            _ = try db.rows("INSERT INTO info(rowid,簡稱,語言,檔案) VALUES(10,'甲','甲語言','原始檔案')")
            _ = try db.rows("INSERT INTO info(rowid,簡稱,語言,檔案) VALUES(30,'乙','乙語言','')")
            _ = try db.rows("INSERT INTO mcpdict(rowid,漢字,資料) VALUES(17,'中','獨立字頭資料')")
        }
        let tables = ["甲", "乙"].enumerated().map { i, name in
            TablePackage(id: String(format: "%024x", i), name: name, fullName: name,
                atlas: [], dictionary: [], administrative: [], source: "test",
                sourceCommit: String(repeating: "a", count: 40), recordCount: i == 0 ? 2 : 4001, size: 100,
                sha256: String(repeating: "b", count: 64), url: URL(string: "https://github.com/example/data/releases/download/test/\(i).db")!)
        }
        let state = TableInstallation(catalogVersion: "legacy", tables: tables, databaseFile: file.lastPathComponent)
        try JSONEncoder().encode(state).write(to: root.appendingPathComponent("index.json"))
        return (root, file, state)
    }
    private func assertSameQueries(_ old: URL, _ new: URL) async throws {
        let before = DictionaryRepository(), after = DictionaryRepository()
        try await before.open(old); try await after.open(new)
        for (input, mode) in [("中", SearchMode.character), ("𰻞", .character), ("iŋ", .pronunciation), ("完整", .note)] {
            let expected = try await before.search(input, mode: mode, language: "")
            let actual = try await after.search(input, mode: mode, language: "")
            XCTAssertEqual(actual, expected)
        }
        for name in ["甲", "乙"] {
            let expected = try await before.tableStatistics(name)
            let actual = try await after.tableStatistics(name)
            XCTAssertEqual(actual, expected)
        }
        for mode in SearchMode.allCases {
            let input = mode == .character ? "中𰻞" : mode == .pronunciation ? "iŋ" : "完整"
            let expected = try await before.mapSearch(input, mode: mode, names: ["甲", "乙"])
            let actual = try await after.mapSearch(input, mode: mode, names: ["甲", "乙"])
            XCTAssertEqual(actual.choices, expected.choices)
            XCTAssertEqual(actual.groups, expected.groups)
        }
    }
    func testCompactCopyPreservesRowsIDsMetadataReferencesAndQueries() async throws {
        let (root, source, _) = try fixture()
        let target = root.appendingPathComponent("compact.db")
        let old = try SQLiteConnection(url: source), db = try SQLiteConnection(url: target, readOnly: false)
        try db.copyRetainedLanguages(from: source)
        try db.compactStoragePages()
        try db.validate()
        XCTAssertTrue(try old.needsStorageOptimization())
        XCTAssertFalse(try db.needsStorageOptimization())
        for table in ["langs", "info", "mcpdict"] {
            XCTAssertEqual(try db.rows("SELECT rowid,* FROM \(table) ORDER BY rowid"), try old.rows("SELECT rowid,* FROM \(table) ORDER BY rowid"))
        }
        try await assertSameQueries(source, target)
        XCTAssertLessThan(try Data(contentsOf: target).count, try Data(contentsOf: source).count)
        try db.removeLanguages(["甲"])
        XCTAssertEqual(try db.rows("SELECT count(*) AS n FROM langs WHERE 語言='甲'").first?["n"], "0")
        XCTAssertEqual(try db.rows("SELECT count(*) AS n FROM langs WHERE 語言='乙'").first?["n"], "4001")
    }
    func testLegacyInstallationMigratesAtomicallyAndOnlyOnce() async throws {
        let (root, source, state) = try fixture()
        let repo = DictionaryRepository(), store = TableStore(repository: repo, root: root, bundledRoot: nil)
        _ = try await store.restore()
        let expected = try await repo.search("中", mode: .character, language: "甲")
        let migrated = try await store.optimizeStorageIfNeeded(beforeActivation: {
            let during = try await repo.search("中", mode: .character, language: "甲")
            XCTAssertEqual(during, expected, "Queries must remain usable while the replacement is prepared")
        })
        let result = try XCTUnwrap(migrated)
        XCTAssertEqual(result.tables, state.tables)
        XCTAssertNotEqual(result.databaseFile, state.databaseFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let after = try await repo.search("中", mode: .character, language: "甲")
        XCTAssertEqual(after, expected)
        let again = try await store.optimizeStorageIfNeeded()
        XCTAssertNil(again)
        let restarted = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        let restored = try await restarted.restore()
        XCTAssertEqual(restored?.databaseFile, result.databaseFile)
    }
    func testFailedAndCancelledMigrationKeepOldPointerAndData() async throws {
        let (root, source, _) = try fixture()
        let repo = DictionaryRepository(), store = TableStore(repository: repo, root: root, bundledRoot: nil)
        _ = try await store.restore()
        let pointer = try Data(contentsOf: root.appendingPathComponent("index.json"))
        let bytes = try Data(contentsOf: source)
        enum Expected: Error { case failure }
        do { _ = try await store.optimizeStorageIfNeeded(beforeActivation: { throw Expected.failure }); XCTFail("Expected failure") }
        catch Expected.failure { }
        let reached = expectation(description: "candidate built")
        let task = Task {
            try await store.optimizeStorageIfNeeded(beforeActivation: {
                reached.fulfill()
                try await Task.sleep(nanoseconds: 60_000_000_000)
            })
        }
        await fulfillment(of: [reached], timeout: 15)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("index.json")), pointer)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let found = try await repo.search("𰻞", mode: .character, language: "乙")
        XCTAssertEqual(found.first?.pronunciation, "biang")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".storage-optimization-") })
    }
    func testConcurrentRemovalWinsOverOlderMigrationCandidate() async throws {
        let (root, _, state) = try fixture()
        let repo = DictionaryRepository(), store = TableStore(repository: repo, root: root, bundledRoot: nil)
        _ = try await store.restore()
        let migrated = try await store.optimizeStorageIfNeeded(beforeActivation: {
            _ = try await store.remove(selected: [state.tables[1].id])
        })
        XCTAssertNil(migrated)
        let current = try await store.restore()
        XCTAssertEqual(current?.tables.map(\.name), ["甲"])
        let removed = try await repo.search("𰻞", mode: .character, language: "乙")
        XCTAssertTrue(removed.isEmpty)
        let remaining = try await repo.search("中", mode: .character, language: "甲")
        XCTAssertEqual(remaining.map(\.id), [7, 9])
    }
    func testUpdatingLegacyInstallationCompactsAndPreservesOtherTables() async throws {
        let (root, _, state) = try fixture()
        let repo = DictionaryRepository(), store = TableStore(repository: repo, root: root, bundledRoot: nil)
        let data = Data("新\tnew1\t更新註釋\n".utf8)
        var blob = Data("blob \(data.count)\0".utf8); blob.append(data)
        let git = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        let commit = String(repeating: "c", count: 40)
        let updated = TablePackage(id: state.tables[0].id, name: "甲", fullName: "甲", atlas: [], dictionary: [], administrative: [],
            source: "test", sourceCommit: commit, recordCount: 1, size: Int64(data.count), sha256: String(repeating: "c", count: 64),
            url: URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(commit)/tools/tables/output/甲.tsv")!, format: "upstream-tsv-v1", gitBlob: git)
        let file = root.appendingPathComponent("update.tsv"); try data.write(to: file)
        let catalog = TableCatalog(schemaVersion: 1, version: "new", sourceRepository: UpstreamTables.repository,
            sourceCommit: commit, scope: "", tables: [updated, state.tables[1]])
        let installed = try await store.apply(catalog, selected: Set(catalog.tables.map(\.id)), localFiles: [updated.id: file]) { _ in }
        let db = try SQLiteConnection(url: root.appendingPathComponent(try XCTUnwrap(installed.databaseFile)))
        XCTAssertFalse(try db.needsStorageOptimization())
        let newRows = try await repo.search("新", mode: .character, language: "甲")
        XCTAssertEqual(newRows.first?.note, "更新註釋")
        let retained = try await repo.search("𰻞", mode: .character, language: "乙")
        XCTAssertEqual(retained.first?.id, 20)
        XCTAssertEqual(try db.rows("SELECT 資料 FROM mcpdict WHERE rowid=17").first?["資料"], "獨立字頭資料")
    }
    func testUnrecognizedExtraDataIsNotDiscarded() async throws {
        let (root, source, _) = try fixture()
        let db = try SQLiteConnection(url: source, readOnly: false)
        _ = try db.rows("CREATE TABLE personal_data(value TEXT)")
        _ = try db.rows("INSERT INTO personal_data VALUES('保留')")
        let store = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        let result = try await store.optimizeStorageIfNeeded()
        XCTAssertNil(result)
        XCTAssertEqual(try db.rows("SELECT value FROM personal_data").first?["value"], "保留")
    }
}
