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
    func testPersonUnionBlankBucketAndFlagIntersection() throws {
        func table(_ name: String, _ atlas: String, _ metadata: [String:String]) throws -> TablePackage {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(UITestFixtures.catalog.tables[0])) as? [String:Any])
            json["name"] = name; json["id"] = name; json["atlas"] = [atlas]; json["metadata"] = metadata
            return try JSONDecoder().decode(TablePackage.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let a = try table("甲", "歷史音", ["錄入人":"A,B","維護人":"B","方言島":"true","歷史音":"0"])
        let b = try table("乙", "吳語", ["錄入人":"B", "維護人":"", "方言島":"true"])
        let c = try table("丙", "吳語", ["維護人":"A", "歷史音":"#808080"])
        let tables = [a,b,c]
        let index = SelectionIndex(tables: tables, grouping: .person)
        XCTAssertEqual(index.nodes[index.roots[0]]?.title, "(無)")
        XCTAssertEqual(index.nodes["g:B"]?.ids, ["甲","乙"])
        XCTAssertEqual(index.nodes["g:(無)"]?.ids, ["丙"])
        XCTAssertEqual(index.nodes["g:B"]?.children.count, 2)
        XCTAssertTrue(SelectionIndex(tables: tables, grouping: .person, roles: []).roots.isEmpty)
        XCTAssertEqual(SelectionIndex(tables: tables, grouping: .person, roles: [.maintainer]).nodes["g:B"]?.ids, ["甲"])
        XCTAssertEqual(tables.filter(LanguageFlags(island: true, history: true).matches).map(\.name), [])
        XCTAssertEqual(tables.filter(LanguageFlags(history: true).matches).map(\.name), ["丙"])
    }
    func testAdministrativeGroupsStopAtCountyEvenWhenCityIsMissing() throws {
        func table(_ name: String, _ metadata: [String:String]) throws -> TablePackage {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(UITestFixtures.catalog.tables[0])) as? [String: Any])
            json["id"] = name; json["name"] = name; json["metadata"] = metadata
            json["administrative"] = ["省","市","縣","鎮","村"].compactMap { metadata[$0] }.filter { !$0.isEmpty }
            return try JSONDecoder().decode(TablePackage.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let direct = try table("直屬點", ["省":"北京","鎮":"某街道"])
        let a = try table("甲", ["省":"北京","市":"","縣":"東城","鎮":"示例街道"])
        let b = try table("乙", ["省":"北京","市":"／","縣":"東城","村":"某村"])
        let c = try table("丙", ["省":"廣西","市":"南寧","縣":"上林","鎮":"白墟","村":"龍寶"])
        XCTAssertEqual(TableGrouping.administrative.path(c), ["廣西","南寧","上林"])
        let index = SelectionIndex(tables: [direct,a,b], grouping: .administrative)
        let rows = index.rows(expanded: Set(index.nodes.keys), matching: nil, scope: .administrativeGroups)
        XCTAssertEqual(rows.map(\.node.title), ["北京","東城"])
        XCTAssertEqual(rows[0].ids, [direct.id,a.id,b.id])
        XCTAssertEqual(rows[1].ids, [a.id,b.id])
        XCTAssertTrue(rows[0].expandable)
        XCTAssertFalse(rows[1].expandable)
        XCTAssertTrue(rows.allSatisfy { $0.node.table == nil })
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
