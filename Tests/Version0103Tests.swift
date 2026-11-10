import XCTest
@testable import MCPDictIOS

final class Version0103Tests: XCTestCase {
    @MainActor func testPointDefaultAndCustomClassificationMemberships() throws {
        let suite = "Version0103." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = LanguageSelectionState(namespace: "test", defaults: defaults)
        XCTAssertEqual(state.grouping, .name)
        XCTAssertEqual(state.groupingChoices.first, .name)
        XCTAssertTrue(state.groupingChoices.contains(.custom))
        let table = UITestFixtures.catalog.tables[0]
        let index = SelectionIndex(tables: [table], grouping: .custom, additionalPaths: [table.id:[["甲","子區"],["乙"]]])
        XCTAssertEqual(index.nodes["g:甲"]?.ids, [table.id])
        XCTAssertEqual(index.nodes["g:乙"]?.ids, [table.id])
        XCTAssertEqual(index.rows(expanded: Set(index.nodes.keys), matching: nil, scope: .points).filter { $0.node.table != nil }.count, 2)
        state.grouping = .custom
        XCTAssertEqual(LanguageSelectionState(namespace: "test", defaults: defaults).grouping, .custom)
        state.kind = .region
        XCTAssertFalse(state.groupingChoices.contains(.custom))
    }
    func testNativeComparisonPreservesPolyphonyMissingAndModes() async throws {
        let input: [String: Any] = ["kind":"compare","chars":["甲","乙"],"mode":"full","glides":true,
            "dialects":[["label":"全同"],["label":"部分"],["label":"全異"],["label":"空"]],
            "rows":[["語言":"全同","字組":"甲乙","讀音":"pa1"],
                    ["語言":"部分","字組":"甲乙","讀音":"pa1"],["語言":"部分","字組":"甲","讀音":"ba2"],
                    ["語言":"全異","字組":"甲","讀音":"pa1"],["語言":"全異","字組":"乙","讀音":"ba2"]]]
        let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
        let rows = try JSONDecoder().decode([ComparisonGroup].self, from: data)
        XCTAssertEqual(rows.map(\.status), ["same","partial","different","missing"])
        XCTAssertEqual(rows[1].readings[0].count, 2)
    }
    func testNativeEvolutionFiltersAndCompleteDetails() async throws {
        var input: [String: Any] = ["kind":"evolution","dialects":[["label":"測試"]],"dimension":"initial","mode":"full","glides":true,
            "guangyun":[["charGroup":"甲乙","切韻音系描述":"幫三A支平","攝":"止","方音字彙描述":"開"]],
            "rows":[["漢字":"甲乙","音標":"pa1 / ba2"]],"filters":[:]]
        let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
        let groups = try JSONDecoder().decode([EvolutionGroup].self, from: data)
        XCTAssertEqual(groups.count, 2); XCTAssertEqual(Set(groups.flatMap(\.chars)), ["甲","乙"])
        XCTAssertTrue(groups.allSatisfy { !$0.subtypes.isEmpty && $0.positions == ["幫三A支平"] })
        input["filters"] = ["voicing":["全濁"]]
        let empty = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
        XCTAssertTrue(try JSONDecoder().decode([EvolutionGroup].self, from: empty).isEmpty)
    }
}
