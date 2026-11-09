import XCTest
@testable import MCPDictIOS

final class CharacterRangeTests: XCTestCase {
    func testAndroidRangeOrderAndTokens() {
        XCTAssertEqual(CharacterSearchRange.allCases.map(\.rawValue), ["", "GY", "SW", "JY", "KX", "HZ", "HD", "FD", "GJ", "kHKGlyph", "T1", "kBigFive"])
    }
    func testRealMembershipUnknownExemptionAndUnrestrictedInput() async throws {
        let index = CharacterRangeIndex.shared
        let restricted = try await index.filter(["一", "A", "□"], range: .guangyun)
        XCTAssertEqual(restricted, ["一", "□"])
        let all = try await index.filter(["一", "A", "□"], range: .all)
        XCTAssertEqual(all, ["一", "A", "□"])
        for range in CharacterSearchRange.allCases where range != .all {
            let common = try await index.filter(["一"], range: range)
            XCTAssertEqual(common, ["一"], range.title)
        }
    }
    func testFilteringKeepsReadingAndNoteWithoutMixingOutOfRangeCharacters() async throws {
        let row = Reading(id: 2, characters: "一 A □", language: "測試", pronunciation: "i1", note: "原始注釋")
        let result = try await CharacterRangeIndex.shared.filter([row], range: .guangyun)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.characters, "一 □")
        XCTAssertEqual(result.first?.pronunciation, "i1")
        XCTAssertEqual(result.first?.note, "原始注釋")
    }
}
