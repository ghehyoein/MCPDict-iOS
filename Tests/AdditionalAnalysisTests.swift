import XCTest
@testable import MCPDictIOS

final class AdditionalAnalysisTests: XCTestCase {
    private func run(_ extra: [String: Any], rows: [[String: String]]) async throws -> Data {
        var input: [String: Any] = ["kind": "correspondence", "left": "a", "right": "b", "mode": "tone", "rows": rows,
            "dialects": [["label": "a", "toneConfig": "{\"2a\":[\"陰平\"],\"2b\":[\"陰平\"]}"], ["label": "b"]]]
        input.merge(extra) { _, new in new }
        return try await NativeAnalysisEngine.run(JSONSerialization.data(withJSONObject: input))
    }
    func testDistinctCharactersPolyphonyAndToneCodes() async throws {
        let rows = [
            ["language":"a","characters":"中 忠","reading":"a2a\ta2b"],
            ["language":"a","characters":"中","reading":"a2a"],
            ["language":"b","characters":"中 忠","reading":"b1"]]
        let data = try await run([:], rows: rows)
        let links = try JSONDecoder().decode([CorrespondenceLink].self, from: data)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(Set(links.map(\.left)), ["2a / 陰平", "2b / 陰平"])
        XCTAssertTrue(links.allSatisfy { Set($0.chars) == ["中", "忠"] })
        let filtered = try await run(["minimumNode":3], rows: rows)
        XCTAssertEqual(try JSONDecoder().decode([CorrespondenceLink].self, from: filtered).count, 0)
    }
    func testMultisyllableFilterDoesNotRemoveAlternativeReadings() async throws {
        let rows = [["language":"a","characters":"中","reading":"a1\ta2\ta3 b4"], ["language":"b","characters":"中","reading":"b1"]]
        let data = try await run(["ignoreMultiple":true], rows: rows)
        let links = try JSONDecoder().decode([CorrespondenceLink].self, from: data)
        XCTAssertEqual(Set(links.map(\.left)), ["1", "2"])
    }
    func testMultisyllableSequenceStaysOneNode() async throws {
        let rows = [["language":"a","characters":"中","reading":"a1 b2"], ["language":"b","characters":"中","reading":"b3"]]
        let data = try await run([:], rows: rows)
        let links = try JSONDecoder().decode([CorrespondenceLink].self, from: data)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.left, "1 · 2")
    }
    func testMultiLanguageStagesMissingReadingsAndNoSelectionCap() async throws {
        let rows = [["language":"a","characters":"中忠","reading":"a1\ta2"],
                    ["language":"b","characters":"中忠","reading":"b3"],
                    ["language":"c","characters":"中","reading":"c4"]]
        let data = try await run(["languages":["a","b","c"]], rows: rows)
        let links = try JSONDecoder().decode([CorrespondenceLink].self, from: data)
        XCTAssertEqual(links.filter { $0.stage == 0 }.count, 2)
        XCTAssertEqual(links.filter { $0.stage == 1 }.count, 1)
        XCTAssertEqual(links.first { $0.stage == 1 }?.chars, ["中"])
        let filtered = try await run(["languages":["a","b","c"], "minimumLink":2], rows: rows)
        XCTAssertTrue(try JSONDecoder().decode([CorrespondenceLink].self, from: filtered).allSatisfy { $0.stage == 0 })
        let one = try await run(["languages":["a","a"]], rows: rows)
        XCTAssertTrue(try JSONDecoder().decode([CorrespondenceLink].self, from: one).isEmpty)
        let names = (0..<50).map { "language\($0)" }
        let many = try await run(["languages":names], rows: names.map { ["language":$0,"characters":"中","reading":"a1"] })
        let chain = try JSONDecoder().decode([CorrespondenceLink].self, from: many)
        XCTAssertEqual(chain.count, 49)
        XCTAssertEqual(Set(chain.map(\.stage)), Set(0..<49))
    }
    func testSingleCharacterGroupsUseDistinctLanguages() async throws {
        let rows = [["language":"a","characters":"中 忠","reading":"a1\ta1"], ["language":"b","characters":"中","reading":"b1"], ["language":"b","characters":"忠","reading":"b2"]]
        let data = try await run(["kind":"soundClasses","character":"中"], rows: rows)
        let groups = try JSONDecoder().decode([SoundClass].self, from: data)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.names, ["a", "b"])
    }
}
