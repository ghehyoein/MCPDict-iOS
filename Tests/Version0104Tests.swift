import XCTest
@testable import MCPDictIOS

final class Version0104Tests: XCTestCase {
    func testNestedSchemeRenameAndArchivePreserveMembersAndColors() throws {
        var source = CustomLanguageSchemes()
        XCTAssertTrue(source.create("甲"))
        source.members = ["一"]
        for depth in 1...20 {
            XCTAssertTrue(source.create((["甲"] + (1...depth).map { "子\($0)" }).joined(separator: "－")))
            source.members = ["語言\(depth)"]
            source.schemes[source.schemes.count - 1].colorHex = "#12ABEF"
        }
        source.current = "甲"
        XCTAssertEqual(source.selected.count, 21)
        XCTAssertTrue(source.rename("乙"))
        XCTAssertFalse(source.schemes.contains { $0.name.hasPrefix("甲") })
        XCTAssertEqual(source.selected.count, 21)
        let data = try JSONEncoder().encode(CustomSchemeArchive(source))
        let imported = try JSONDecoder().decode(CustomSchemeArchive.self, from: data).merging(into: CustomLanguageSchemes())
        XCTAssertEqual(imported.schemes.count, source.schemes.count)
        XCTAssertEqual(imported.schemes.last?.languages, ["語言20"])
        XCTAssertEqual(imported.schemes.last?.colorHex, "#12ABEF")
        let before = source
        XCTAssertFalse(source.rename("乙－子1"))
        XCTAssertEqual(source, before)
        XCTAssertTrue(source.create("丙－子1"))
        source.current = "乙"
        let collision = source
        XCTAssertFalse(source.rename("丙"))
        XCTAssertEqual(source, collision)
    }
    @MainActor func testEditorControlsAreIsolatedAndPersistIndependently() throws {
        let suite = "Version0104." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let editor = LanguageSelectionState(namespace: "customEditors", defaults: defaults)
        editor.grouping = .dictionary
        XCTAssertEqual(LanguageSelectionState(namespace: "customEditors", defaults: defaults).grouping, .dictionary)
        XCTAssertEqual(LanguageSelectionState(namespace: "dictionary", defaults: defaults).grouping, .name)
        XCTAssertEqual(LanguageSelectionState(namespace: "games", defaults: defaults).grouping, .name)
    }
    func testMiddleChineseFilterCombinesMultipleValues() async throws {
        let input: [String: Any] = ["kind":"evolution", "dialects":[["label":"測試"]], "dimension":"initial", "mode":"full", "glides":true,
            "guangyun":[["charGroup":"甲","切韻音系描述":"幫三A支平","攝":"止","方音字彙描述":"開"],
                        ["charGroup":"乙","切韻音系描述":"滂三A支平","攝":"止","方音字彙描述":"開"],
                        ["charGroup":"丙","切韻音系描述":"並三A支平","攝":"止","方音字彙描述":"開"]],
            "rows":[["漢字":"甲乙丙","音標":"pa1"]], "filters":["initial":["幫","滂"]]]
        let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
        let rows = try JSONDecoder().decode([EvolutionGroup].self, from: data)
        XCTAssertEqual(Set(rows.flatMap(\.chars)), ["甲","乙"])
    }
}
