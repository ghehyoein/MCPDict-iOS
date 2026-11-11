import XCTest
@testable import MCPDictIOS

final class CollectionMapTests: XCTestCase {
    func testBranchesIncludeDescendantsAndPreferDeepestSavedColor() {
        let table = UITestFixtures.catalog.tables[0]
        var custom = CustomLanguageSchemes()
        custom.schemes = [
            .init(name: "甲", languages: [table.name], colorHex: "#112233"),
            .init(name: "甲－乙", languages: [table.name], colorHex: "#445566"),
            .init(name: "丙", languages: ["unknown"], colorHex: "#778899")
        ]
        let points = CollectionMap.schemes(custom, roots: ["甲"], tables: [table])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.color, "#445566")
        XCTAssertTrue(CollectionMap.schemes(custom, roots: [], tables: [table]).isEmpty)
        XCTAssertTrue(CollectionMap.schemes(custom, roots: ["丙"], tables: [table]).isEmpty)
        XCTAssertEqual(custom.current, "默認方案")
    }
    func testNotebookMapKeepsEveryReadingAndAppliedColor() {
        let table = UITestFixtures.catalog.tables[0]
        let entries = ["中", "忠"].enumerated().map { i, char in
            SavedReading(reading: Reading(id: Int64(i), characters: char, language: table.name, pronunciation: "pa1", note: "注"))
        }
        let points = CollectionMap.readings(entries, tables: [table], grouping: .atlas, colors: [table.name: "#123ABC"])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.color, "#123ABC")
        XCTAssertTrue(points[0].reading.contains("中"))
        XCTAssertTrue(points[0].reading.contains("忠"))
        XCTAssertEqual(points[0].reading, points[0].copyText)
    }
}
