import XCTest
@testable import MCPDictIOS

final class HistoricalResultOrderingTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = UUID().uuidString
        let value = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { value.removePersistentDomain(forName: suite) }
        return value
    }

    private func table(_ name: String, sequence: String, root: String = "歷史音", atlas: String = "A") -> TablePackage {
        TablePackage(id: name, name: name, fullName: name, atlas: [root], dictionary: [root],
                     administrative: [], source: "fixture", sourceCommit: "", recordCount: 1,
                     size: 1, sha256: "", url: URL(string: "https://example.com/table")!,
                     metadata: ["地圖集二排序": atlas, "音典排序": sequence, "歷史音": "#808080"])
    }

    func testBundledHistoricalSequenceMatchesRequestedOrderForBothClassifications() throws {
        let url = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("BundledTables/catalog.json")
        let tables = try JSONDecoder().decode(TableCatalog.self, from: Data(contentsOf: url)).tables
        let expected = ["鄭張上古", "白－沙上古", "文獻上古", "廣韻", "盛唐", "中唐", "北宋", "蒙古字韻", "中原音韻", "西儒耳目資", "老國音"]
        let prefs = try defaults()
        for grouping in [TableGrouping.atlas, .dictionary] {
            prefs.set(grouping.rawValue, forKey: "grouping.dictionary.語言")
            let ranks = ResultOrdering.ranks(tables, namespace: "dictionary", defaults: prefs)
            let actual = tables.filter { $0.atlas.first == "歷史音" || $0.dictionary.first == "歷史音" }
                .sorted { ranks[$0.name]! < ranks[$1.name]! }.map(\.name)
            XCTAssertEqual(actual, expected)
        }
    }

    func testGrayMarkedDialectsKeepTheirRanksAndHistoryUsesUpdatedMetadata() throws {
        let prefs = try defaults()
        let tables = [table("乙", sequence: "A-001"), table("甲", sequence: "A-002"),
                      table("丙", sequence: "A-000", root: "吳語"),
                      table("丁", sequence: "Z-001", root: "官話", atlas: "B")]
        let ranks = ResultOrdering.ranks(tables, namespace: "dictionary", defaults: prefs)
        XCTAssertLessThan(try XCTUnwrap(ranks["乙"]), try XCTUnwrap(ranks["甲"]))
        // Non-primary gray historical markers must not enter the historical sequence.
        let original = tables.sorted {
            let a = $0.metadata!["地圖集二排序"]!, b = $1.metadata!["地圖集二排序"]!
            return a == b ? $0.name < $1.name : a < b
        }
        for name in ["丙", "丁"] { XCTAssertEqual(ranks[name], original.firstIndex { $0.name == name }) }
        let updated = [table("乙", sequence: "A-003"), table("甲", sequence: "A-001")]
        let newRanks = ResultOrdering.ranks(updated, namespace: "dictionary", defaults: prefs)
        XCTAssertLessThan(try XCTUnwrap(newRanks["甲"]), try XCTUnwrap(newRanks["乙"]))
    }

    func testMissingSequenceAndMultipleReadingsHaveDeterministicOrder() throws {
        let prefs = try defaults()
        let tables = [table("未知", sequence: ""), table("晚", sequence: "A-002"), table("早", sequence: "A-001")]
        let ranks = ResultOrdering.ranks(tables, namespace: "dictionary", defaults: prefs)
        let rows = ["晚", "早", "未知", "早"].enumerated().map {
            Reading(id: Int64($0.offset), characters: "身", language: $0.element, pronunciation: "a", note: "")
        }
        let ordered = ResultOrdering.sorted(rows, ranks: ranks)
        XCTAssertEqual(ordered.map(\.id), [1, 3, 0, 2])
        XCTAssertEqual(CharacterResults.groups(ordered, character: "身").map(\.language), ["早", "晚", "未知"])
    }
}
