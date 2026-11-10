import XCTest
@testable import MCPDictIOS

final class Version0105Tests: XCTestCase {
    func testDuplicateBranchCopiesNestedMembersColorsAndAvoidsDuplicateSelection() throws {
        var store = CustomLanguageSchemes(legacy: ["保留"])
        XCTAssertTrue(store.create("父")); store.members = ["甲"]
        XCTAssertTrue(store.create("父－子")); store.members = ["乙"]
        XCTAssertTrue(store.create("父－子－孫")); store.members = ["丙"]
        store.schemes[2].colorHex = "#123ABC"
        let selected = store.current
        XCTAssertEqual(store.duplicateBranches(["父", "父－子"], suffix: "副本"), ["父（副本）"])
        XCTAssertEqual(store.current, selected)
        XCTAssertEqual(store.schemes.count, 7)
        XCTAssertEqual(store.schemes.first { $0.name == "父（副本）－子" }?.colorHex, "#123ABC")
        XCTAssertEqual(store.schemes.first { $0.name == "父（副本）－子－孫" }?.languages, ["丙"])
        XCTAssertEqual(store.duplicateBranches(["父"], suffix: "副本"), ["父（副本2）"])
        XCTAssertTrue(store.removeBranches(["父－子"]))
        XCTAssertEqual(store.current, "默認方案")
        XCTAssertEqual(store.schemes.first { $0.name == "父（副本）－子－孫" }?.languages, ["丙"])
        let data = try JSONEncoder().encode(CustomSchemeArchive(store))
        let restored = try JSONDecoder().decode(CustomSchemeArchive.self, from: data).merging(into: CustomLanguageSchemes())
        XCTAssertEqual(restored.schemes, store.schemes)
    }
    func testBulkRemovalPreservesParentAndOtherBranchesAndLastScheme() {
        var store = CustomLanguageSchemes()
        for name in ["父", "父－甲", "父－甲－孫", "父－乙", "其他"] { XCTAssertTrue(store.create(name)) }
        XCTAssertTrue(store.removeBranches(["父－甲", "父－乙"]))
        XCTAssertEqual(store.schemes.map(\.name), ["默認方案", "父", "其他"])
        XCTAssertEqual(store.current, "其他")
        let snapshot = store
        XCTAssertFalse(store.removeBranches(Set(store.schemes.map(\.name))))
        XCTAssertEqual(store, snapshot)
    }
    func testCopyNotebookSurvivesOriginalDeletionAndArchiveRoundTrip() throws {
        var archive = NotebookArchive()
        let original = archive.books[0].id
        archive.entries = [SavedReading(reading: Reading(id: 1, characters: "身", language: "甲", pronunciation: "ɕiŋ53", note: ""), note: "筆記")]
        let copy = try XCTUnwrap(archive.duplicate(original, suffix: "副本"))
        XCTAssertNotEqual(copy, original)
        XCTAssertEqual(archive.selected, [original])
        XCTAssertEqual(archive.entries[0].membership, [original, copy])
        let another = try XCTUnwrap(archive.duplicate(original, suffix: "副本"))
        XCTAssertNotEqual(copy, another)
        XCTAssertEqual(Set(archive.books.map(\.name)).count, 3)
        archive.remove([original])
        let restored = try NotebookArchive.decode(JSONEncoder().encode(archive))
        XCTAssertEqual(restored.entries[0].membership, [copy, another])
        XCTAssertEqual(restored.entries[0].note, "筆記")
        XCTAssertEqual(restored.entries[0].reading.pronunciation, "ɕiŋ53")
    }
    func testEvolutionExportIncludesAllCharactersAndEscapesCSV() {
        let chars = (0..<50).map { "字\($0)" }
        let group = EvolutionGroup(oldValue: "幫,並", modernValue: "p\"a", chars: chars,
            readings: ["pa1", "ba2"], positions: ["幫三支平"], subtypes: ["甲", "乙"])
        let csv = EvolutionExportDocument.csv(groups: [group], language: "測試", dimension: "聲母", mode: "完整讀音")
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("\"幫,並\""))
        XCTAssertTrue(csv.contains("\"p\"\"a\""))
        XCTAssertTrue(csv.contains("\"pa1\nba2\""))
        XCTAssertTrue(csv.contains(chars.joined(separator: " ")))
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }
    @MainActor func testComparisonSelectionControlsAreIndependent() throws {
        let suite = "Version0105." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let comparison = LanguageSelectionState(namespace: "comparisonResults", defaults: defaults)
        comparison.grouping = .dictionary; comparison.filter = "甲"; comparison.expandedNodes = ["漢語"]
        let dictionary = LanguageSelectionState(namespace: "dictionary", defaults: defaults)
        XCTAssertEqual(dictionary.grouping, .name)
        XCTAssertEqual(dictionary.filter, "")
        XCTAssertTrue(dictionary.expandedNodes.isEmpty)
    }
}
