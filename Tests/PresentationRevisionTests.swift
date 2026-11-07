import XCTest
@testable import MCPDictIOS

final class PresentationRevisionTests: XCTestCase {
    @MainActor func testSelectionStateSharesControlsAndKeepsDownloadsIndependent() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shared = LanguageSelectionState(namespace: "dictionary", defaults: defaults)
        shared.kind = .region; shared.grouping = .dictionary
        shared.flags = LanguageFlags(island: true, history: true)
        let downloads = LanguageSelectionState(namespace: "downloads", defaults: defaults)
        XCTAssertEqual(downloads.kind, .language)
        XCTAssertEqual(downloads.grouping, .atlas)
        XCTAssertFalse(downloads.flags.history)
        let restored = LanguageSelectionState(namespace: "dictionary", defaults: defaults)
        XCTAssertEqual(restored.kind, .region)
        XCTAssertEqual(restored.grouping, .dictionary)
        XCTAssertEqual(restored.groupingChoices, [.atlas, .dictionary])
        XCTAssertTrue(restored.flags.history && restored.flags.island)
        restored.kind = .language; restored.grouping = .person; restored.roles = [.editor]
        restored.kind = .region
        XCTAssertEqual(restored.grouping, .dictionary)
        restored.kind = .language
        XCTAssertEqual(restored.grouping, .person)
        XCTAssertEqual(restored.roles, [.editor])
    }
    func testSelectedNotebookTextExportExcludesOtherBooksAndMemberships() throws {
        var archive = NotebookArchive()
        let a = VocabularyBook(id: UUID(), name: "甲"), b = VocabularyBook(id: UUID(), name: "乙")
        archive.books += [a, b]; archive.selected = [a.id]
        let reading = Reading(id: 1, characters: "好 𠀀", language: "通東呂四", pronunciation: "hæ3", note: "註釋\n第二行")
        archive.entries = [SavedReading(reading: reading, note: "個人筆記", books: [a.id, b.id]), SavedReading(reading: reading, books: [b.id])]
        let exported = archive.exportingSelected()
        XCTAssertEqual(exported.books.map(\.id), [a.id])
        XCTAssertEqual(exported.entries.count, 1)
        XCTAssertEqual(exported.entries.first?.membership, [a.id])
        XCTAssertEqual(exported.entries.first?.note, "個人筆記")
        let roundTrip = try NotebookArchive.decode(JSONEncoder().encode(exported))
        XCTAssertEqual(roundTrip.entries.first?.reading, reading)
        XCTAssertEqual(archive.entries.count, 2)
        XCTAssertEqual(archive.entries.first?.membership, [a.id, b.id])
    }
    func testUnicodeMovesToInformationAndOnlyUnicodeExpandsByDefault() {
        let prefs = ReferencePreferences()
        XCTAssertFalse(prefs.order.contains("Unicode"))
        XCTAssertEqual(prefs.fieldOrder.first, "Unicode")
        XCTAssertEqual(prefs.fieldOrder.filter { prefs.mode($0) == "expanded" }, ["Unicode"])
        let old = #"{"order":["Unicode","康熙"],"hidden":["Unicode"],"fieldOrder":["兩分"],"fieldModes":{"兩分":"expanded"}}"#
        let migrated = ReferencePreferences.load(old)
        XCTAssertEqual(migrated.mode("Unicode"), "hidden")
        XCTAssertEqual(migrated.mode("兩分"), "expanded")
        XCTAssertEqual(migrated.order.first, "康熙")
        XCTAssertEqual(migrated.value("Unicode", data: CharacterReference(character: "好")), "U+597D")
    }
    func testHistoricalFlagReadsGrayMarkerRatherThanTransitionOrCategory() throws {
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(UITestFixtures.catalog.tables[0])) as? [String: Any])
        func table(_ marker: String) throws -> TablePackage {
            data["metadata"] = ["是否為語言歷史音": marker, "歷史音": "0"]
            data["dictionaryColor"] = "#808080,#AABBCC"
            return try JSONDecoder().decode(TablePackage.self, from: JSONSerialization.data(withJSONObject: data))
        }
        XCTAssertTrue(try LanguageFlags(history: true).matches(table("FF808080")))
        XCTAssertTrue(try LanguageFlags(history: true).matches(table("#BFBFBF")))
        for marker in ["0", "#000000", "#FFFFFF", "#7FDDE6", "true"] {
            XCTAssertFalse(try LanguageFlags(history: true).matches(table(marker)))
        }
    }
}
