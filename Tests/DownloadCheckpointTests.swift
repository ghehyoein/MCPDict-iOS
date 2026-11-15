import XCTest
import CryptoKit
@testable import MCPDictIOS

final class DownloadCheckpointTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func package(_ name: String, id: Int, text: String, root: URL) throws -> (TablePackage, URL) {
        let data = Data(text.utf8), commit = String(repeating: "a", count: 40)
        var blob = Data("blob \(data.count)\0".utf8); blob.append(data)
        let hash = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        let table = TablePackage(id: String(format: "%024x", id), name: name, fullName: name, atlas: [], dictionary: [], administrative: [], source: "test", sourceCommit: commit, recordCount: 0, size: Int64(data.count), sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), url: URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(commit)/tools/tables/output/\(name).tsv")!, format: "upstream-tsv-v1", gitBlob: hash)
        let file = root.appendingPathComponent(UUID().uuidString + ".db")
        try UpstreamTables.importTSV(data, table: table, to: file)
        return (table, file)
    }
    private func initial(_ table: TablePackage, shard: URL, root: URL) throws -> TableInstallation {
        let file = root.appendingPathComponent(UUID().uuidString + ".db")
        try FileManager.default.copyItem(at: shard, to: file)
        let state = TableInstallation(catalogVersion: "old", tables: [table], databaseFile: file.lastPathComponent)
        try JSONEncoder().encode(state).write(to: root.appendingPathComponent("index.json"))
        return state
    }

    func testRestartRecoversCompletedTablesWithoutFinalActivation() async throws {
        let root = try directory(), sources = try directory()
        let (old, oldFile) = try package("原有", id: 1, text: "中\told1\t保留\n", root: sources)
        let previous = try initial(old, shard: oldFile, root: root)
        let (new, newFile) = try package("新增", id: 2, text: "中\tnew1\t已完成\n", root: sources)
        let checkpoint = try TableDownloadCheckpoint(root: root, previous: previous, version: "new")
        try checkpoint.merge(new, from: newFile)
        checkpoint.close() // End the process before final activation.
        let repo = DictionaryRepository(), store = TableStore(repository: repo, root: root, bundledRoot: nil)
        let restored = try await store.restore()
        XCTAssertEqual(Set(restored?.tables.map(\.name) ?? []), ["原有", "新增"])
        let rows = try await repo.search("中", mode: .character, language: "")
        XCTAssertEqual(Set(rows.map(\.note)), ["保留", "已完成"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: TableDownloadCheckpoint.marker(in: root).path))
        let again = try await store.restore()
        XCTAssertEqual(again?.databaseFile, restored?.databaseFile)
        let db = try SQLiteConnection(url: root.appendingPathComponent(try XCTUnwrap(restored?.databaseFile)))
        XCTAssertTrue(try db.rows("SELECT name FROM sqlite_master WHERE name LIKE 'mcpdict_download_%'").isEmpty)
    }

    func testRestartRollsBackHotJournalOfInterruptedLastTable() async throws {
        let root = try directory(), sources = try directory(), snapshotParent = try directory()
        let snapshot = snapshotParent.appendingPathComponent("crashed")
        let (old, oldFile) = try package("原有", id: 1, text: "中\told1\t保留舊版\n", root: sources)
        let previous = try initial(old, shard: oldFile, root: root)
        let (done, doneFile) = try package("完成", id: 2, text: "中\tdone1\t已完成\n", root: sources)
        let (update, updateFile) = try package("原有", id: 1, text: String(repeating: "中\tnew1\t未完成的大字表更新\n", count: 250_000), root: sources)
        let checkpoint = try TableDownloadCheckpoint(root: root, previous: previous, version: "new")
        try checkpoint.merge(done, from: doneFile)
        enum Interrupted: Error { case stop }
        do {
            try checkpoint.merge(update, from: updateFile) {
                // The writer is paused inside an uncommitted transaction. Copy
                // both DB and journal as a process-death disk snapshot.
                try FileManager.default.copyItem(at: root, to: snapshot)
                throw Interrupted.stop
            }
            XCTFail("Expected interruption")
        } catch Interrupted.stop { }
        checkpoint.close()
        let journals = try FileManager.default.contentsOfDirectory(atPath: snapshot.path).filter { $0.hasSuffix("-journal") }
        XCTAssertFalse(journals.isEmpty)
        let repo = DictionaryRepository(), store = TableStore(repository: repo, root: snapshot, bundledRoot: nil)
        let restored = try await store.restore()
        XCTAssertEqual(Set(restored?.tables.map(\.name) ?? []), ["原有", "完成"])
        XCTAssertEqual(restored?.tables.first { $0.id == old.id }?.sha256, old.sha256)
        let rows = try await repo.search("中", mode: .character, language: "")
        XCTAssertEqual(Set(rows.map(\.pronunciation)), ["old1", "done1"])
    }

    func testCancelledMergeKeepsEarlierCheckpointAndOldVersion() async throws {
        let root = try directory(), sources = try directory()
        let (old, oldFile) = try package("甲", id: 1, text: "中\told1\t\n", root: sources)
        let previous = try initial(old, shard: oldFile, root: root)
        let (done, doneFile) = try package("乙", id: 2, text: "中\tdone1\t\n", root: sources)
        let (update, updateFile) = try package("甲", id: 1, text: "中\tnew1\t\n", root: sources)
        let task = Task {
            let checkpoint = try TableDownloadCheckpoint(root: root, previous: previous, version: "new")
            defer { checkpoint.close() }
            try checkpoint.merge(done, from: doneFile)
            try checkpoint.merge(update, from: updateFile) {
                withUnsafeCurrentTask { $0?.cancel() }
                try Task.checkCancellation()
            }
        }
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        let repo = DictionaryRepository(), store = TableStore(repository: repo, root: root, bundledRoot: nil)
        let restored = try await store.restore()
        XCTAssertEqual(restored?.tables.count, 2)
        let rows = try await repo.search("中", mode: .character, language: "")
        XCTAssertEqual(Set(rows.map(\.pronunciation)), ["old1", "done1"])
    }

    func testEmptyCheckpointDoesNotReplaceOldInstallation() async throws {
        let root = try directory(), sources = try directory()
        let (old, oldFile) = try package("甲", id: 1, text: "中\told1\t\n", root: sources)
        let previous = try initial(old, shard: oldFile, root: root)
        let checkpoint = try TableDownloadCheckpoint(root: root, previous: previous, version: "new")
        checkpoint.close()
        let store = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        let restored = try await store.restore()
        XCTAssertEqual(restored?.databaseFile, previous.databaseFile)
    }

    func testCancelInterruptsLargeSQLUpdateAndKeepsCommittedTables() async throws {
        let root = try directory(), sources = try directory()
        let (old, oldFile) = try package("甲", id: 1, text: String(repeating: "中\told1\t保留\n", count: 250_000), root: sources)
        let previous = try initial(old, shard: oldFile, root: root)
        let (done, doneFile) = try package("乙", id: 2, text: "中\tdone1\t\n", root: sources)
        let (update, updateFile) = try package("甲", id: 1, text: "中\tnew1\t\n", root: sources)
        let enteringSQL = expectation(description: "large update started")
        let task = Task.detached {
            let checkpoint = try TableDownloadCheckpoint(root: root, previous: previous, version: "new")
            defer { checkpoint.close() }
            try checkpoint.merge(done, from: doneFile)
            enteringSQL.fulfill()
            try checkpoint.merge(update, from: updateFile)
        }
        await fulfillment(of: [enteringSQL], timeout: 15)
        // Cancel from another task while SQLite is deleting/reindexing 250k rows.
        try await Task.sleep(nanoseconds: 50_000_000)
        let cancelledAt = Date()
        task.cancel()
        do { try await task.value; XCTFail("Large SQL update must be interrupted") }
        catch is CancellationError { }
        let responseSeconds = Date().timeIntervalSince(cancelledAt)
        XCTAssertLessThan(responseSeconds, 15)
        let store = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        let restored = try await store.restore()
        XCTAssertEqual(restored?.tables.count, 2)
        XCTAssertEqual(restored?.tables.first { $0.id == old.id }?.sha256, old.sha256)
        let db = try SQLiteConnection(url: root.appendingPathComponent(try XCTUnwrap(restored?.databaseFile)))
        XCTAssertEqual(try db.rows("SELECT count(*) AS n FROM langs WHERE 語言='甲'").first?["n"], "250000")
        print("DOWNLOAD_CANCEL_RESPONSE seconds=\(responseSeconds)")
    }
}
