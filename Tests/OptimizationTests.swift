import XCTest
import CryptoKit
import MapKit
@testable import MCPDictIOS

final class OptimizationTests: XCTestCase {
    private func table(_ i: Int, size: Int64 = 100) -> TablePackage {
        let name = "點\(i)", commit = String(repeating: "a", count: 40)
        return TablePackage(id: String(format: "%024x", i), name: name, fullName: name,
                            atlas: ["根\(i / 100)", "區\(i / 10)"], dictionary: ["區"], administrative: [],
                            source: "test", sourceCommit: commit, recordCount: 1, size: size,
                            sha256: String(repeating: "b", count: 64),
                            url: URL(string: "https://github.com/example/data/releases/download/test/\(i).db")!)
    }
    @MainActor func testCachedTreeRestorationAt3306Points() throws {
        let tables = (0..<3306).map { table($0) }
        let cache = SelectionIndexCache()
        let start = Date()
        let index = cache.index(tables: tables, grouping: .atlas, roles: [.editor], paths: [:])
        let cold = Date().timeIntervalSince(start)
        let names = Set(tables.prefix(10).map(\.name))
        let expected = RegionSelection.restore(tables: tables, grouping: .atlas, names: names, saved: nil)
        let warmStart = Date()
        for _ in 0..<100 {
            let reused = cache.index(tables: tables, grouping: .atlas, roles: [.editor], paths: [:])
            XCTAssertEqual(reused.revision, index.revision)
            XCTAssertEqual(reused.region(names: names, saved: expected), expected)
        }
        XCTAssertEqual(cache.builds, 1)
        XCTAssertEqual(index.matches("点100"), index.matches("點100"))
        _ = cache.index(tables: Array(tables.dropLast()), grouping: .atlas, roles: [.editor], paths: [:])
        XCTAssertEqual(cache.builds, 2, "A catalog/removal change must invalidate the snapshot")
        print("TREE_CACHE_BENCH points=3306 cold_seconds=\(cold) warm_100_seconds=\(Date().timeIntervalSince(warmStart)) builds=\(cache.builds)")
    }
    @MainActor func testNameOnlyMapDoesNotAllocate3306TextViews() throws {
        let start = Date()
        var views = [LabelAnnotationView]()
        for i in 0..<3306 {
            let point = DialectPoint(id: "\(i)", name: "點\(i)", longitude: 113, latitude: 23, color: "#008080", reading: "")
            let view = LabelAnnotationView(annotation: nil, reuseIdentifier: nil)
            view.configure(point, fontSize: 16) {}
            views.append(view)
        }
        XCTAssertTrue(views.allSatisfy { $0.readingView == nil && $0.subviews.count == 1 })
        print("MAP_NAME_BENCH points=3306 seconds=\(Date().timeIntervalSince(start)) text_views=0 blur_views=0")
        let point = DialectPoint(id: "0", name: "點0", longitude: 113, latitude: 23, color: "#008080", reading: "可選取的完整讀音")
        views[0].configure(point, fontSize: 16) {}
        XCTAssertEqual(views[0].readingView?.text, point.reading)
        XCTAssertTrue(views[0].readingView?.isSelectable == true)
        XCTAssertTrue(views.dropFirst().allSatisfy { $0.readingView == nil })
    }
    func testIndexedRemovalMatchesExactNamesAndRollsBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("base.db")
        let db = try SQLiteConnection(url: file, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋)")
        _ = try db.rows("CREATE VIRTUAL TABLE info USING fts5(簡稱, 語言)")
        let special = ["甲", "甲 乙", "A\"B", "---"]
        try db.transaction {
            try db.batch("INSERT INTO langs VALUES (?,?,?,?)") { insert in
                for i in 0..<30000 { try insert(["中", "點\(i % 300)", "a1", "註釋"]) }
                for name in special { try insert(["中", name, "a1", "註釋"]) }
            }
            for name in special { _ = try db.rows("INSERT INTO info VALUES (?,?)", [name, name]) }
        }
        enum Expected: Error { case rollback }
        XCTAssertThrowsError(try db.transaction { try db.removeLanguages(["點1"]); throw Expected.rollback })
        XCTAssertEqual(try db.rows("SELECT count(*) AS n FROM langs WHERE 語言='點1'").first?["n"], "100")
        let indexedFile = root.appendingPathComponent("indexed.db")
        try FileManager.default.copyItem(at: file, to: indexedFile)
        let indexed = try SQLiteConnection(url: indexedFile, readOnly: false)
        let names = ["點1", "甲", "A\"B", "---"]
        let json = String(data: try JSONEncoder().encode(names), encoding: .utf8)!
        let oldStart = Date()
        try db.transaction { _ = try db.rows("DELETE FROM langs WHERE 語言 IN (SELECT value FROM json_each(?))", [json]) }
        let scanTime = Date().timeIntervalSince(oldStart)
        let start = Date()
        try indexed.transaction { try indexed.removeLanguages(names) }
        let indexTime = Date().timeIntervalSince(start)
        XCTAssertEqual(try indexed.rows("SELECT 語言, count(*) AS n FROM langs GROUP BY 語言 ORDER BY 語言"), try db.rows("SELECT 語言, count(*) AS n FROM langs GROUP BY 語言 ORDER BY 語言"))
        XCTAssertEqual(try indexed.rows("SELECT 簡稱 FROM info").map { $0["簡稱"] }, ["甲 乙"])
        print("DELETE_BENCH rows=30004 scan_seconds=\(scanTime) indexed_seconds=\(indexTime)")
    }
    func testPreparedActivationStillRejectsInvalidSchemaAndPreservesActiveDatabase() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = root.appendingPathComponent("valid.db")
        let db = try SQLiteConnection(url: valid, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋)")
        _ = try db.rows("INSERT INTO langs VALUES ('中', '甲', 'a1', '')")
        let repository = DictionaryRepository()
        try await repository.open(valid)
        let invalid = root.appendingPathComponent("invalid.db")
        let broken = try SQLiteConnection(url: invalid, readOnly: false)
        _ = try broken.rows("CREATE TABLE langs(wrong TEXT)")
        var committed = false
        do {
            try await repository.activate(invalid, requireSample: false, checkIntegrity: false) { committed = true }
            XCTFail("Invalid prepared schema must not become active")
        } catch { }
        XCTAssertFalse(committed)
        let rows = try await repository.search("中", mode: .character, language: "甲")
        XCTAssertEqual(rows.map(\.pronunciation), ["a1"])
    }
    func testUnchangedCatalogOnlyRequestsHead() async throws {
        let cached = UITestFixtures.catalog
        let requests = RequestProbe()
        let latest = try await UpstreamTables.catalog(cached: cached) { url in
            await requests.record(url)
            return try JSONEncoder().encode(["sha": cached.sourceCommit])
        }
        XCTAssertEqual(latest.tables, cached.tables)
        let urls = await requests.urls
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls[0].path.hasSuffix("/commits/master"))
    }
    func testDownloadBatchRespectsCountSizeAndOrder() {
        let tables = (0..<12).map { table($0, size: $0 == 5 ? 20_000_000 : 5_000_000) }
        let batches = TableDownloadBatch.make(tables)
        XCTAssertEqual(batches.flatMap { $0 }.map(\.id), tables.map(\.id))
        XCTAssertTrue(batches.allSatisfy { $0.count <= 4 && ($0.count == 1 || $0.reduce(Int64(0)) { $0 + $1.size } <= 16 * 1024 * 1024) })
        XCTAssertEqual(batches.first { $0.contains { $0.id == tables[5].id } }?.count, 1)
    }
    func testParallelPrefetchRetainsEveryVerifiedTable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("中\ta1\t註釋\n".utf8)
        var blob = Data("blob \(data.count)\0".utf8); blob.append(data)
        let git = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        let commit = String(repeating: "a", count: 40)
        let tables = (0..<9).map { i in
            TablePackage(id: String(format: "%024x", i), name: "點\(i)", fullName: "點\(i)", atlas: [], dictionary: [], administrative: [], source: "test", sourceCommit: commit, recordCount: 0, size: Int64(data.count), sha256: String(repeating: "b", count: 64), url: URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(commit)/tools/tables/output/點\(i).tsv")!, format: "upstream-tsv-v1", gitBlob: git)
        }
        let probe = RequestProbe()
        let repository = DictionaryRepository()
        let store = TableStore(repository: repository, root: root, bundledRoot: nil) { url in
            try await probe.fetch(url, data: data)
        }
        let catalog = TableCatalog(schemaVersion: 1, version: commit, sourceRepository: UpstreamTables.repository, sourceCommit: commit, scope: "", tables: tables)
        let result = try await store.download(catalog, selected: Set(tables.map(\.id))) { _ in }
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.completed, 9)
        let maximum = await probe.maximum
        XCTAssertGreaterThan(maximum, 1)
        XCTAssertLessThanOrEqual(maximum, 4)
        let rows = try await repository.search("中", mode: .character, language: "")
        XCTAssertEqual(Set(rows.map(\.language)), Set(tables.map(\.name)))
        let reopened = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        let restored = try await reopened.restore()
        XCTAssertEqual(restored?.tables.count, 9)
    }
}

private actor RequestProbe {
    var urls = [URL]()
    private var active = 0
    var maximum = 0
    func record(_ url: URL) { urls.append(url) }
    func fetch(_ url: URL, data: Data) async throws -> Data {
        urls.append(url); active += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        return data
    }
}
