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

    @MainActor func testLegacyFavoritesAndSharedBookMembershipSurviveRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("favorites.json")
        let legacy = SavedReading(reading: Reading(id: 12, characters: "中", language: "甲", pronunciation: "a1", note: ""), note: "舊筆記")
        try JSONEncoder().encode([legacy]).write(to: file)
        let model = AppModel(favoritesURL: file)
        try model.restoreNotebook()
        XCTAssertEqual(model.visibleFavorites.first?.id, legacy.id)
        XCTAssertEqual(model.visibleFavorites.first?.note, "舊筆記")
        model.setBookName("課堂")
        let book = try XCTUnwrap(model.notebook.books.last?.id)
        XCTAssertEqual(model.notebook.selected, [book])
        XCTAssertTrue(model.visibleFavorites.isEmpty)
        model.selectBooks(Set(model.notebook.books.map(\.id)))
        model.save(legacy.reading)
        XCTAssertEqual(model.visibleFavorites.count, 1)
        XCTAssertEqual(model.visibleFavorites.first?.membership, model.notebook.selected)
        model.setBookName("課後", id: book)
        let reopened = AppModel(favoritesURL: file)
        try reopened.restoreNotebook()
        XCTAssertEqual(reopened.notebook.selected.count, 2)
        XCTAssertEqual(reopened.notebook.books.last?.name, "課後")
        reopened.selectBooks([book])
        reopened.removeVisibleFavorites([legacy.id])
        XCTAssertEqual(reopened.favorites.first?.membership, [VocabularyBook.original.id])
        reopened.addFavorites([legacy.id], to: book)
        reopened.deleteBooks([VocabularyBook.original.id])
        XCTAssertEqual(reopened.visibleFavorites.first?.note, "舊筆記")
        XCTAssertEqual(reopened.visibleFavorites.first?.membership, [book])
        reopened.deleteBooks([book])
        try model.restoreNotebook()
        XCTAssertTrue(model.notebook.books.isEmpty)
        XCTAssertTrue(model.favorites.isEmpty)
    }
    @MainActor func testStarAssignmentIsIndependentOfBookFilter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(favoritesURL: root.appendingPathComponent("favorites.json"))
        model.setBookName("甲")
        let chosen = model.notebook.selected
        let all = Set(model.notebook.books.map(\.id))
        let row = Reading(id: 1, characters: "中", language: "甲", pronunciation: "a1", note: "")
        model.assign(row, to: all)
        XCTAssertEqual(model.memberships(row), all)
        XCTAssertEqual(model.notebook.selected, chosen)
        model.assign(row, to: [])
        XCTAssertTrue(model.favorites.isEmpty)
        XCTAssertEqual(model.notebook.books.count, 2)
    }
}
