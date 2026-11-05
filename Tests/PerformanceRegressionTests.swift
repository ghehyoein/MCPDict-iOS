import XCTest
@testable import MCPDictIOS

final class PerformanceRegressionTests: XCTestCase {
    private func table(_ index: Int) -> TablePackage {
        TablePackage(id: String(format: "%024x", index), name: "點\(index)", fullName: "點\(index)", atlas: ["根\(index / 50)", "區\(index / 10)", "片\(index / 5)"], dictionary: ["另一分區"], administrative: ["省"], source: "fixture", sourceCommit: String(repeating: "a", count: 40), recordCount: 1, size: 100, sha256: String(repeating: "b", count: 64), url: URL(string: "https://github.com/example/data/releases/download/test/test.db")!)
    }
    func testIndexedTreeMatchesReferenceAndReusesMembership() {
        let tables = (0..<1500).map(table)
        let start = Date()
        let index = SelectionIndex(tables: tables, grouping: .atlas)
        let buildTime = Date().timeIntervalSince(start)
        let groups = index.nodes.values.filter { $0.region != nil }
        var reference = [String: Set<String>]()
        let referenceStart = Date()
        for group in groups {
            let path = group.region!.components(separatedBy: "\u{0}")
            reference[group.id] = Set(tables.filter { $0.atlas.starts(with: path) }.map(\.id))
        }
        let referenceTime = Date().timeIntervalSince(referenceStart)
        for group in groups { XCTAssertEqual(group.ids, reference[group.id]) }
        XCTAssertEqual(index.membershipInsertions, 4500)
        XCTAssertEqual(groups.count * tables.count, 720000)
        let expanded = Set(groups.map(\.id))
        let rows = index.rows(expanded: expanded, matching: nil, scope: .points)
        XCTAssertEqual(rows.filter { $0.node.table != nil }.count, tables.count)
        let filtered = index.rows(expanded: expanded, matching: [tables[0].id], scope: .terminalGroups)
        XCTAssertEqual(filtered.count, 3)
        XCTAssertEqual(filtered.first?.ids.count, 50, "Searching a leaf must still select the complete region")
        XCTAssertTrue(filtered.allSatisfy { $0.node.table == nil })
        XCTAssertEqual(index.rows(expanded: expanded, matching: nil, scope: .topGroups).count, 30)
        print("TREE_BENCH tables=1500 groups=480 reference_scans=720000 indexed_insertions=4500 build_seconds=\(buildTime) reference_seconds=\(referenceTime)")
    }
    @MainActor func testResultAndFavoriteCachesInvalidate() {
        let model = AppModel()
        let first = Reading(id: 1, characters: "中 忠", language: "甲", pronunciation: "a1", note: "")
        model.results = [first]
        XCTAssertEqual(model.characterGroups("中").first?.readings.count, 1)
        XCTAssertEqual(model.homophoneGroups().count, 1)
        model.results = []
        XCTAssertTrue(model.characterGroups("中").isEmpty)
        XCTAssertTrue(model.homophoneGroups().isEmpty)
        model.favorites = [SavedReading(reading: first)]
        XCTAssertTrue(model.isSaved(Reading(id: 99, characters: first.characters, language: first.language, pronunciation: first.pronunciation, note: first.note)))
        model.favorites = []
        XCTAssertFalse(model.isSaved(first))
    }
    func testBatchedMapQueriesAndStatisticsInvalidation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.db")
        let db = try SQLiteConnection(url: first, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋)")
        _ = try db.rows("INSERT INTO langs VALUES ('输 輸', '甲', 'a1', '')")
        _ = try db.rows("INSERT INTO langs VALUES ('輸', '甲', 'a2', '')")
        let repo = DictionaryRepository()
        try await repo.open(first)
        let batch = try await repo.mapReadingsForVariants(["输", "輸", "输"])
        for character in ["输", "輸"] {
            let reference = try await repo.mapReadings(character)
            XCTAssertEqual(batch[character], reference)
        }
        let initial = try await repo.tableStatistics("甲")
        let cached = try await repo.tableStatistics("甲")
        XCTAssertEqual(initial, cached)
        let second = folder.appendingPathComponent("second.db")
        let replacement = try SQLiteConnection(url: second, readOnly: false)
        _ = try replacement.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋)")
        _ = try replacement.rows("INSERT INTO langs VALUES ('中', '甲', 'b1', '')")
        try await repo.open(second)
        let updated = try await repo.tableStatistics("甲")
        XCTAssertEqual(updated["字數"], "1")
        XCTAssertNotEqual(initial, updated)
    }
    func testToneCacheUsesContentAndPreservesStyles() throws {
        var sample = table(0)
        sample.metadata = ["聲調": "{\"1\":[\"55\",\"1\",\"1\",\"平\",\"꜀\"]}"]
        let first = ToneDisplay.parts("a1", table: sample, style: "baSheng", pitchStyle: "number")
        XCTAssertEqual(first, ToneDisplay.parts("a1", table: sample, style: "baSheng", pitchStyle: "number"))
        sample.metadata = ["聲調": "{\"1\":[\"21\",\"1\",\"1\",\"平\",\"꜀\"]}"]
        XCTAssertNotEqual(first, ToneDisplay.parts("a1", table: sample, style: "baSheng", pitchStyle: "number"))
        sample.metadata = ["聲調": "invalid"]
        XCTAssertEqual(ToneDisplay.parts("a1", table: sample, style: "baSheng", pitchStyle: "number").first?.base, "a1")
    }
}
