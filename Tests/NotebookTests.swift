import XCTest
@testable import MCPDictIOS

final class NotebookTests: XCTestCase {
    func testParallelClassificationsKeepOneIdentityPerSavedEntry() {
        let entry = SavedReading(reading: Reading(id: 1, characters: "中 忠 中", language: "甲", pronunciation: "a1", note: ""))
        let other = SavedReading(reading: Reading(id: 2, characters: "中", language: "乙", pronunciation: "a1", note: ""))
        let groups = NotebookGroup.make([entry, other], categories: Set(NotebookCategory.allCases))
        XCTAssertEqual(groups.count, 5)
        XCTAssertEqual(groups.first { $0.id == "發音\u{0}a1" }?.entries.map(\.id), [entry.id, other.id])
        XCTAssertEqual(groups.first { $0.id == "單字\u{0}中" }?.entries.map(\.id), [entry.id, other.id])
        XCTAssertEqual(Set(groups.flatMap { $0.entries.map(\.id) }), [entry.id, other.id])
        XCTAssertEqual(NotebookGroup.make([entry], categories: []).first?.entries.first?.id, entry.id)
    }
}
