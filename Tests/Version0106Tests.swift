import XCTest
@testable import MCPDictIOS

final class Version0106Tests: XCTestCase {
    func testImportRejectsEmptyHierarchySegmentsWithoutChangingSource() throws {
        let source = CustomLanguageSchemes(legacy: ["保留"])
        for name in ["甲－－乙", "－甲", "甲－", "甲 / 乙"] {
            var archive = CustomSchemeArchive(source)
            archive.schemes = [.init(name: name, languages: ["新增"], colorHex: "#123456")]
            XCTAssertThrowsError(try archive.merging(into: source))
            XCTAssertEqual(source.members, ["保留"])
        }
    }
    func testIndexedImportMergesDuplicateNormalizedNamesAndKeepsOrderAndColors() throws {
        var source = CustomLanguageSchemes(legacy: ["原有"])
        source.schemes[0].colorHex = "#ABCDEF"
        var archive = CustomSchemeArchive(source)
        archive.schemes = [.init(name: "甲 子", languages: ["一"], colorHex: "#112233"),
                           .init(name: "甲/子", languages: ["二"], colorHex: "#445566"),
                           .init(name: source.current, languages: ["追加"], colorHex: "#000000")]
        let merged = try archive.merging(into: source)
        XCTAssertEqual(merged.schemes.map(\.name), [source.current, "甲－子"])
        XCTAssertEqual(merged.schemes[1].languages, ["一", "二"])
        XCTAssertEqual(merged.schemes[1].colorHex, "#112233")
        XCTAssertEqual(merged.schemes[0].colorHex, "#ABCDEF")
        XCTAssertEqual(merged.members, ["原有", "追加"])
    }
    func testBranchIndexMatchesPrefixReferenceAcrossWideAndDeepTrees() {
        var store = CustomLanguageSchemes()
        store.schemes += (0..<2000).map { .init(name: "根\($0)－子－孫", languages: []) }
        store.schemes += [.init(name: "根1", languages: []), .init(name: "根10", languages: [])]
        let roots = Set((0..<1000).map { "根\($0)" })
        let reference = Set(store.schemes.filter { row in roots.contains { row.name == $0 || row.name.hasPrefix($0 + "－") } }.map(\.name))
        XCTAssertEqual(store.branchNames(roots), reference)
        XCTAssertFalse(CustomLanguageSchemes.belongs("根10－子", to: ["根1"]))
        XCTAssertTrue(CustomLanguageSchemes.belongs("根－" + Array(repeating: "子", count: 100).joined(separator: "－"), to: ["根"]))
    }
    func testLongTextDeduplicationPreservesReadingOrderAndEveryOccurrence() {
        let rows = (0..<3000).map { Reading(id: Int64($0), characters: "甲 乙", language: "測試", pronunciation: "p\($0 % 500)", note: "") }
        let result = LongTextAnnotation.build("甲，乙甲\n", rows: rows, variants: { [$0] })
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result[0].choices.map(\.pronunciation), (0..<500).map { "p\($0)" })
        XCTAssertEqual(result[0].choices, result[3].choices)
        XCTAssertEqual(result[2].choices.count, 500)
        XCTAssertTrue(result[1].choices.isEmpty)
    }
    func testNativeComparisonPreservesPolyphonyVariantsMissingAndSupplementaryCharacters() async throws {
        let input: [String: Any] = ["kind":"compare", "chars":["甲", "乙", "𠀀"], "mode":"full", "glides":true,
            "dialects":[["label":"一"], ["label":"二"]],
            "rows":[["語言":"一", "字組":"甲 乙 𠀀", "讀音":"pa1\tba2"],
                    ["語言":"一", "字組":"甲", "讀音":"pa1"],
                    ["語言":"二", "字組":"甲", "讀音":"pa1"]]]
        let data = try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
        let result = try JSONDecoder().decode([ComparisonGroup].self, from: data)
        XCTAssertEqual(result.map(\.status), ["same", "missing"])
        XCTAssertEqual(result[0].readings, Array(repeating: ["ba2", "pa1"], count: 3))
        XCTAssertEqual(result[1].readings, [["pa1"], [], []])
    }
}
