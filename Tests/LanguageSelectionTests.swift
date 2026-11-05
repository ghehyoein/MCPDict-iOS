import XCTest
@testable import MCPDictIOS

final class LanguageSelectionTests: XCTestCase {
    func testRegionGroupsIncludeAllDescendantsAtEveryDepth() throws {
        func table(_ name: String, _ path: [String]) throws -> TablePackage {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(UITestFixtures.catalog.tables[0])) as? [String: Any])
            json["id"] = name; json["name"] = name; json["atlas"] = path
            return try JSONDecoder().decode(TablePackage.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let tables = try [table("旁列點", ["漢語", "吳語"]), table("深層甲", ["漢語", "吳語", "太湖", "蘇嘉湖"]), table("深層乙", ["漢語", "吳語", "太湖", "蘇嘉湖"]), table("淺層", ["漢語", "粵語"]), table("無分區", [])]
        XCTAssertEqual(Set(LanguageSelectionScope.terminalGroups.eligible(tables, grouping: .atlas).map(\.name)), ["旁列點", "深層甲", "深層乙", "淺層"])
        XCTAssertEqual(RegionSelection.restore(tables: tables, grouping: .atlas, names: ["深層甲", "深層乙"], saved: "漢語\u{0}吳語\u{0}太湖\u{0}蘇嘉湖"), "漢語\u{0}吳語\u{0}太湖\u{0}蘇嘉湖")
        XCTAssertNil(RegionSelection.restore(tables: tables, grouping: .atlas, names: ["深層甲", "淺層"], saved: nil))
        for root in ["歷史音", "民族語", "吳語", "粵語", "域外方音", "戲劇"] {
            let example = try table(root, [root, "子類"])
            XCTAssertEqual(TableGrouping.atlas.path(example), [root, "子類"])
            XCTAssertEqual(TableGrouping.dictionary.path(example), ["漢語"], "Each classification must preserve its own complete root path")
        }
        XCTAssertEqual(LanguageSelectionScope.points.eligible(tables, grouping: .atlas).count, 5)
        XCTAssertEqual(LanguageSelectionScope.topGroups.eligible(tables, grouping: .atlas).count, 4)
    }
    @MainActor func testDictionaryAndMapCachesSurviveRecreationAndKeepEmptySelection() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.languages = ["甲", "乙"]
        model.selectLanguages(["甲"])
        let cache = LanguageSelectionCache(defaults: defaults)
        for mode in MapSearchKind.allCases { cache.save([mode.rawValue], for: "map." + mode.rawValue) }
        let reopened = AppModel(defaults: defaults)
        reopened.languages = ["甲", "乙"]; reopened.restoreLanguageSelection()
        XCTAssertEqual(reopened.selectedLanguages, ["甲"])
        for mode in MapSearchKind.allCases { XCTAssertEqual(cache.load("map." + mode.rawValue), [mode.rawValue]) }
        reopened.selectLanguages([])
        model.restoreLanguageSelection()
        XCTAssertEqual(model.selectedLanguages, [], "Empty selection must not silently become all languages")
    }
}
