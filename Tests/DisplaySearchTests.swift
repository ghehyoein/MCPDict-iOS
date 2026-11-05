import XCTest
@testable import MCPDictIOS

final class DisplaySearchTests: XCTestCase {
    func testBundledVariantsAreBidirectionalAndPreserveAmbiguity() {
        XCTAssertEqual(CharacterVariants.expand("输").prefix(2), ["输", "輸"])
        XCTAssertTrue(CharacterVariants.expand("輸").contains("输"))
        XCTAssertTrue(CharacterVariants.expand("发").contains("發"))
        XCTAssertTrue(CharacterVariants.expand("发").contains("髮"))
        XCTAssertTrue(CharacterVariants.expand("𰹰").contains("輸"))
        XCTAssertEqual(CharacterVariants.expand("U+8F93"), CharacterVariants.expand("输"))
        let values = CharacterVariants.expand("输輸输")
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertEqual(values.prefix(2), ["输", "輸"])
    }
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
    func testExternalMapURLsPreserveCoordinatesAndEscapeNames() throws {
        let point = TableLocation(longitude: 121.082015, latitude: 32.086091)
        for app in DeviceMapApp.allCases {
            let url = try XCTUnwrap(app.url(location: point, name: "金沙 & 測試"))
            XCTAssertEqual(url.scheme, app.scheme)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertTrue(values.values.contains { $0.contains("32.086091") })
            XCTAssertTrue(values.values.contains { $0.contains("121.082015") })
            if app != .google { XCTAssertTrue(values.values.contains("金沙 & 測試")) }
            XCTAssertNil(app.url(location: TableLocation(longitude: 200, latitude: 0), name: "bad"))
        }
        XCTAssertEqual(BaseMapStyle.standard.type, .standard)
        XCTAssertEqual(BaseMapStyle.satellite.type, .satellite)
        XCTAssertEqual(BaseMapStyle.hybrid.type, .hybrid)
    }
}
