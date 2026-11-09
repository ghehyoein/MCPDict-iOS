import XCTest
@testable import MCPDictIOS

final class CustomSelectionTests: XCTestCase {
    func testVisibilityIntersectionAndHiddenHistoricalMarkers() throws {
        let source = UITestFixtures.catalog.tables[0]
        func table(island: Bool, history: Bool) throws -> TablePackage {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
            json["atlas"] = ["漢語"]; json["dictionary"] = ["漢語"]
            json["metadata"] = ["方言島": island ? "true" : "", "歷史音": history ? "#808080" : ""]
            return try JSONDecoder().decode(TablePackage.self, from: JSONSerialization.data(withJSONObject: json))
        }
        for a in LanguageVisibility.allCases { for b in LanguageVisibility.allCases {
            var flags = LanguageFlags(); flags.islandMode = a; flags.historyMode = b
            for island in [true, false] { for history in [true, false] {
                let expected = (a == .show || (a == .only) == island) && (b == .show || (b == .only) == history)
                XCTAssertEqual(try flags.matches(table(island: island, history: history)), expected)
            } }
        } }
    }
    func testSchemesHierarchyUnionNamesDeletionAndColors() throws {
        var store = CustomLanguageSchemes(legacy: ["甲"])
        XCTAssertFalse(store.delete())
        XCTAssertFalse(store.create("  "))
        XCTAssertTrue(store.create("江淮 洪巢")); store.members = ["乙", "丙"]
        XCTAssertTrue(store.create("江淮/通泰")); store.members = ["丁", "丙"]
        XCTAssertEqual(store.parents, ["江淮"])
        XCTAssertEqual(store.selected, ["丁", "丙"])
        store.scope = "江淮"
        XCTAssertEqual(store.selected, ["乙", "丙", "丁"])
        XCTAssertEqual(store.color(for: "丙"), "#0D47A1")
        store.scope = "ALL"
        XCTAssertEqual(store.selected, ["甲", "乙", "丙", "丁"])
        XCTAssertFalse(store.rename("江淮-洪巢"))
        XCTAssertTrue(store.rename("吳語／太湖"))
        XCTAssertEqual(store.current, "吳語－太湖")
        XCTAssertTrue(store.delete())
        XCTAssertEqual(store.current, "默認方案")
        let restored = try JSONDecoder().decode(CustomLanguageSchemes.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(restored, store)
    }
    @MainActor func testLegacyMigrationPersistenceAndDownloadIsolation() throws {
        let suite = "CustomSelectionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "history.dictionary")
        defaults.set(["甲"], forKey: "languageSelection.dictionary.自選")
        let state = LanguageSelectionState(namespace: "dictionary", defaults: defaults)
        XCTAssertEqual(state.flags.historyMode, .only)
        XCTAssertEqual(state.flags.islandMode, .show)
        XCTAssertEqual(state.custom.members, ["甲"])
        state.flags.historyMode = .hide
        XCTAssertTrue(state.custom.create("測試 一")); state.custom.members = ["乙"]
        state.custom.scope = "ALL"; state.custom.colorByScheme = true
        let restored = LanguageSelectionState(namespace: "dictionary", defaults: defaults)
        XCTAssertEqual(restored.flags.historyMode, .hide)
        XCTAssertEqual(restored.custom.selected, ["甲", "乙"])
        XCTAssertTrue(restored.custom.colorByScheme)
        XCTAssertTrue(LanguageSelectionState(namespace: "downloads", defaults: defaults).custom.members.isEmpty)
        restored.resetDefaults()
        XCTAssertEqual(restored.custom.selected, ["甲", "乙"], "Reset settings must preserve saved schemes")
    }
}
