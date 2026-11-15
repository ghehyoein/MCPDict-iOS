import XCTest
@testable import MCPDictIOS

final class DownloadRecoveryTests: XCTestCase {
    private func fixture() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let db = try SQLiteConnection(url: file, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組,語言,讀音,註釋,columnsize=0)")
        _ = try db.rows("CREATE TABLE info(簡稱 TEXT,語言 TEXT)")
        _ = try db.rows("INSERT INTO info VALUES('甲','甲語言')")
        _ = try db.rows("INSERT INTO langs VALUES('中','甲','a1','保留')")
        return file
    }

    @MainActor func testCancelledTransactionRollsBackBeforeConnectionCloses() async throws {
        let file = try fixture()
        let db = try SQLiteConnection(url: file, readOnly: false)
        db.enableCancellation()
        let task = Task { @MainActor in
            try db.transaction {
                _ = try db.rows("DELETE FROM langs")
                withUnsafeCurrentTask { $0?.cancel() }
                try Task.checkCancellation()
            }
        }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        // Keep the same connection alive: closing it would hide a skipped rollback.
        XCTAssertEqual(try db.rows("SELECT 註釋 FROM langs").first?["註釋"], "保留")
        try db.transaction { _ = try db.rows("INSERT INTO info VALUES('乙','乙語言')") }
        XCTAssertEqual(try db.rows("SELECT count(*) AS n FROM info").first?["n"], "2")
    }

    @MainActor func testCancelledDownloadCanRefreshCommittedLanguagesAndClearSearchState() async throws {
        let file = try fixture()
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        try await model.repository.open(file)
        model.languages = ["舊"]
        model.selectLanguages(["甲", "舊"])
        model.searching = true
        model.hasMore = true
        model.results = [Reading(id: 1, characters: "舊", language: "舊", pronunciation: "x", note: "")]
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await model.refreshAfterTables()
        }
        try await task.value
        XCTAssertEqual(model.languages, ["甲"])
        XCTAssertEqual(model.selectedLanguageNames, ["甲"])
        XCTAssertFalse(model.searching)
        XCTAssertFalse(model.hasMore)
        XCTAssertTrue(model.results.isEmpty)
        let found = try await model.repository.search("中", mode: .character, language: "甲")
        XCTAssertEqual(found.first?.note, "保留")
    }
}
