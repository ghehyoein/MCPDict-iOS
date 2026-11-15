import XCTest
import CryptoKit
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
    func testFullCatalogImportAndUpdateHaveNoBulkWorkAfterLastCompletedTable() async throws {
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
        print("DOWNLOAD_STRESS install tables=\(catalog.tables.count) rows=\(rowCount ?? -1) seconds=\(ended.timeIntervalSince(started)) finalActivationSeconds=\(tail)")
        // Change cache identities while retaining the actual, Git-validated TSV
        // bodies. This forces every installed table through the update path.
        let updates = try catalog.tables.map { table -> TablePackage in
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(table)) as? [String: Any])
            object["sha256"] = SHA256.hash(data: Data(("update:" + table.sha256).utf8)).map { String(format: "%02x", $0) }.joined()
            return try JSONDecoder().decode(TablePackage.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let updatedCatalog = TableCatalog(schemaVersion: catalog.schemaVersion, version: "update", sourceRepository: catalog.sourceRepository, sourceCommit: catalog.sourceCommit, scope: catalog.scope, tables: updates)
        let updateTiming = DownloadTiming(), updateStarted = Date()
        let updated = try await reopened.download(updatedCatalog, selected: Set(sources.keys), localFiles: sources, completedCount: {
            await updateTiming.completed($0, total: updates.count)
        }) { message in
            if message.hasPrefix("已完成 ") { print("DOWNLOAD_UPDATE_PROGRESS \(message)") }
        }
        let updateEnded = Date(), lastUpdate = await updateTiming.lastCompleted
        let updateTail = updateEnded.timeIntervalSince(try XCTUnwrap(lastUpdate))
        XCTAssertNil(updated.failure)
        XCTAssertEqual(updated.completed, updates.count)
        XCTAssertLessThan(updateTail, 15)
        let updatedDB = try SQLiteConnection(url: root.appendingPathComponent(try XCTUnwrap(updated.installation.databaseFile)))
        XCTAssertEqual(try updatedDB.rows("SELECT count(*) AS n FROM langs").first?["n"], String(rowCount ?? -1))
        let restarted = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        let final = try await restarted.restore()
        XCTAssertEqual(Set(final?.tables.map(\.sha256) ?? []), Set(updates.map(\.sha256)))
        print("DOWNLOAD_STRESS update tables=\(updates.count) seconds=\(updateEnded.timeIntervalSince(updateStarted)) finalActivationSeconds=\(updateTail)")
    }
}
