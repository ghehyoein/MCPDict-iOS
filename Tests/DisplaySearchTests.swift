import XCTest
@testable import MCPDictIOS

final class DisplaySearchTests: XCTestCase {
    func testSubstringPriorityLiteralSymbolsAndRegionAcrossPages() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let db = try SQLiteConnection(url: file, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋)")
        for row in [["中", "甲", "atsɿ1", ""], ["中", "乙", "tsɿ5", ""], ["中", "丙", "tsɿ3", ""], ["中", "甲", "a%1", ""]] {
            _ = try db.rows("INSERT INTO langs VALUES (?,?,?,?)", row)
        }
        for _ in 0..<110 { _ = try db.rows("INSERT INTO langs VALUES ('忠','甲','tsɿ1','')") }
        let repo = DictionaryRepository(); try await repo.open(file)
        let page = try await repo.search("tsɿ", mode: .pronunciation, language: "", languages: ["甲", "乙"])
        XCTAssertEqual(page.first?.pronunciation, "tsɿ5")
        XCTAssertEqual(page.count, 100)
        XCTAssertFalse(page.contains { $0.language == "丙" })
        let next = try await repo.search("tsɿ", mode: .pronunciation, language: "", offset: 100, languages: ["甲", "乙"])
        XCTAssertEqual(next.last?.pronunciation, "atsɿ1")
        XCTAssertEqual(next.count, 12)
        let literal = try await repo.search("%", mode: .pronunciation, language: "")
        XCTAssertEqual(literal.map(\.pronunciation), ["a%1"])
        let empty = try await repo.search("tsɿ", mode: .pronunciation, language: "", languages: [])
        XCTAssertTrue(empty.isEmpty)
        let characters = try await repo.searchAllCharacters("中", language: "", languages: ["甲", "乙"])
        XCTAssertEqual(characters.count, 3)
        let stats = try await repo.tableStatistics("乙")
        XCTAssertEqual(stats["字數"], "1")
    }
    func testToneModesAndUnknownPreservation() throws {
        var table = UITestFixtures.catalog.tables[0]
        table.metadata = ["聲調": #"{"1":["24","1","1a","陰平","꜀"],"5":["55","5","3a","陰去","꜄"]}"#]
        XCTAssertEqual(ToneDisplay.text("tsoŋ1", table: table, style: "baSheng", pitch: "curve"), "tsoŋ˨˦①")
        XCTAssertEqual(ToneDisplay.text("tsoŋ5", table: table, style: "siSheng", pitch: "hidden"), "tsoŋ③ⓐ")
        XCTAssertEqual(ToneDisplay.text("tsoŋ1", table: table, style: "hanzi", pitch: "number"), "tsoŋ24陰平")
        XCTAssertEqual(ToneDisplay.text("tsoŋ1", table: table, style: "corners", pitch: "hidden"), "tsoŋ꜀")
        XCTAssertEqual(ToneDisplay.text("tsoŋ1", table: table, style: "hidden", pitch: "hidden"), "tsoŋ")
        XCTAssertEqual(ToneDisplay.text("tsoŋ9", table: table, style: "hidden", pitch: "hidden"), "tsoŋ9")
        XCTAssertEqual(ToneDisplay.text("tsoŋ1/tsoŋ5", table: table, style: "pinYin", pitch: "hidden"), "tsoŋ1/tsoŋ5")
        let stacked = try XCTUnwrap(ToneDisplay.parts("tsoŋ1", table: table, style: "stacked", pitchStyle: "hidden").first)
        XCTAssertTrue(stacked.stacked); XCTAssertEqual(stacked.pitch, "24"); XCTAssertEqual(stacked.tone, "1a")
        XCTAssertEqual(ToneDisplay.curve("55"), "˥")
    }
    func testTwoColorPreservationAndFontRange() {
        XCTAssertEqual(TableColors.hexes("#7FDDE6,#CB1D7A"), ["#7FDDE6", "#CB1D7A"])
        XCTAssertTrue(TableColors.hexes("javascript:bad").isEmpty)
        XCTAssertNotEqual(AppTypography.size(14), AppTypography.size(26))
    }
}
