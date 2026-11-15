import XCTest
@testable import MCPDictIOS

private actor DownloadTiming {
    var lastCompleted: Date?
    var counts = [Int]()
    func completed(_ count: Int, total: Int) {
        counts.append(count)
        if count == total { lastCompleted = Date() }
    }
}

final class DownloadStressTests: XCTestCase {
    func testFullCatalogImportHasNoBulkWorkAfterLastCompletedTable() async throws {
        let bundle = Bundle(for: Self.self)
        guard bundle.url(forResource: "download-stress-enabled", withExtension: "txt") != nil else {
            throw XCTSkip("Opt-in full upstream download fixture not generated")
        }
        let catalogFile = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "BundledTables"))
        let catalog = try JSONDecoder().decode(TableCatalog.self, from: Data(contentsOf: catalogFile))
        let sources = try Dictionary(uniqueKeysWithValues: catalog.tables.map {
            ($0.id, try XCTUnwrap(bundle.url(forResource: $0.id, withExtension: "tsv")))
        })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = DictionaryRepository(), timing = DownloadTiming()
        let store = TableStore(repository: repo, root: root, bundledRoot: nil)
        let started = Date()
        let result = try await store.download(catalog, selected: Set(sources.keys), localFiles: sources, completedCount: {
            await timing.completed($0, total: catalog.tables.count)
        }) { message in
            if message.hasPrefix("已完成 ") { print("DOWNLOAD_STRESS_PROGRESS \(message)") }
        }
        let ended = Date(), last = await timing.lastCompleted, counts = await timing.counts
        XCTAssertNil(result.failure)
        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.completed, catalog.tables.count)
        XCTAssertEqual(counts, Array(0...catalog.tables.count))
        let tail = ended.timeIntervalSince(try XCTUnwrap(last))
        XCTAssertLessThan(tail, 15, "Completion must not rebuild all downloaded tables")
        let db = try SQLiteConnection(url: root.appendingPathComponent(try XCTUnwrap(result.installation.databaseFile)))
        let rowCount = Int(try db.rows("SELECT count(*) AS n FROM langs").first?["n"] ?? "")
        XCTAssertEqual(rowCount, catalog.tables.reduce(0) { $0 + $1.recordCount })
        let reopened = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        let restored = try await reopened.restore()
        XCTAssertEqual(restored?.tables.count, catalog.tables.count)
        let noOp = try await reopened.download(catalog, selected: Set(sources.keys)) { _ in }
        XCTAssertEqual(noOp.completed, 0)
        print("DOWNLOAD_STRESS tables=\(catalog.tables.count) rows=\(rowCount ?? -1) seconds=\(ended.timeIntervalSince(started)) finalActivationSeconds=\(tail)")
    }
}
