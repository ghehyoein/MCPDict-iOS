import XCTest
@testable import MCPDictIOS

final class ComparisonOptionsTests: XCTestCase {
    func testPaletteValidatesAndPreservesIndependentColors() throws {
        let defaults = ComparisonPalette()
        XCTAssertEqual(defaults.color("same"), "#15803D")
        let first = try XCTUnwrap(defaults.setting(" 123aBc ", for: "same"))
        let second = try XCTUnwrap(ComparisonPalette(first).setting("#AABBCC", for: "missing"))
        XCTAssertEqual(ComparisonPalette(second).color("same"), "#123ABC")
        XCTAssertEqual(ComparisonPalette(second).color("missing"), "#AABBCC")
        XCTAssertEqual(ComparisonPalette(second).color("partial"), defaults.color("partial"))
        XCTAssertNil(ComparisonPalette(second).setting("#12345Z", for: "same"))
        XCTAssertEqual(ComparisonPalette("invalid").color("same"), defaults.color("same"))
        let suite = "ComparisonColors." + UUID().uuidString
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        store.set(second, forKey: ComparisonPalette.key)
        XCTAssertEqual(ComparisonPalette(store.string(forKey: ComparisonPalette.key) ?? "").color("missing"), "#AABBCC")
    }
    func testUnitsKeepOrderAndAllowSharedCharactersBetweenGroups() {
        let a = ComparisonUnit(["台", "臺", "台"]), b = ComparisonUnit(["台", "中"])
        XCTAssertEqual(a.characters, ["台", "臺"])
        XCTAssertEqual(a.title, "台＋臺")
        XCTAssertEqual(ComparisonUnit.effective([a, b], choices: ["中", "忠"], selected: ["忠"]), [["台", "臺"], ["台", "中"], ["忠"]])
        XCTAssertEqual(ComparisonUnit.effective([], choices: ["中", "忠"], selected: ["中", "忠"]), [["中"], ["忠"]])
    }
    func testUnionDeduplicatesPolyphonyAndClassifiesMissingOnlyForEmptyUnits() async throws {
        let input: [String: Any] = ["kind":"compare", "units":[["台", "臺"], ["中", "忠"]], "mode":"full", "glides":true,
            "dialects":[["label":"同"], ["label":"部分"], ["label":"異"], ["label":"缺"]],
            "rows":[["語言":"同", "字組":"台 中", "讀音":"pa1"],
                    ["語言":"同", "字組":"臺 忠", "讀音":"ba2\tpa1"],
                    ["語言":"部分", "字組":"台", "讀音":"pa1\tba2"],
                    ["語言":"部分", "字組":"忠", "讀音":"pa1"],
                    ["語言":"異", "字組":"臺", "讀音":"pa1"],
                    ["語言":"異", "字組":"中", "讀音":"ka1"],
                    ["語言":"缺", "字組":"台 臺", "讀音":"pa1"]]]
        let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
        let rows = try JSONDecoder().decode([ComparisonGroup].self, from: data)
        XCTAssertEqual(rows.map(\.status), ["same", "partial", "different", "missing"])
        XCTAssertEqual(rows[0].readings, [["ba2", "pa1"], ["ba2", "pa1"]])
        XCTAssertEqual(rows[1].readings, [["ba2", "pa1"], ["pa1"]])
        XCTAssertEqual(rows[3].readings, [["pa1"], []])
    }
    func testUnitsRespectComparisonModeAndSupplementaryCharacters() async throws {
        let input: [String: Any] = ["kind":"compare", "units":[["𠀀", "台"], ["臺"]], "mode":"notone", "glides":true,
            "dialects":[["label":"測試"]], "rows":[["語言":"測試", "字組":"𠀀", "讀音":"pa1"], ["語言":"測試", "字組":"臺", "讀音":"pa2"]]]
        let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
        let rows = try JSONDecoder().decode([ComparisonGroup].self, from: data)
        XCTAssertEqual(rows[0].status, "same")
        XCTAssertEqual(rows[0].readings, [["pa1"], ["pa2"]])
    }
}
