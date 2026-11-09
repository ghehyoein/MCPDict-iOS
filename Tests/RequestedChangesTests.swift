import XCTest
@testable import MCPDictIOS

final class RequestedChangesTests: XCTestCase {
    func testDictionaryTabLoadsApprovedArtworkAtOriginalSize() throws {
        let image = DictionaryTabIcon.image
        let pixels = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(pixels.width, 520)
        XCTAssertEqual(pixels.height, 520)
        XCTAssertEqual(image.size.width, 26)
        XCTAssertEqual(image.size.height, 26)
        XCTAssertEqual(image.renderingMode, .alwaysTemplate)
    }

    func testOnlyMarkedHistoricalColorMatchesAndRootCategoryDoesNot() {
        let table = UITestFixtures.catalog.tables[0]
        // TablePackage has immutable identity; construct variants using Codable.
        func example(_ value: String, root: String = "漢語") throws -> TablePackage {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(table)) as? [String: Any])
            json["metadata"] = ["歷史音": value]
            json["atlas"] = [root]
            return try JSONDecoder().decode(TablePackage.self, from: JSONSerialization.data(withJSONObject: json))
        }
        for value in ["", "0", "1", "true", "#000000", "#FFFFFF", "#BADDFF", "bad"] {
            XCTAssertFalse(try LanguageFlags(history: true).matches(example(value)), value)
        }
        XCTAssertTrue(try LanguageFlags(history: true).matches(example("#808080")))
        XCTAssertFalse(try LanguageFlags(history: true).matches(example("#808080", root: "歷史音")))
    }
    func testRegionAncestorsFollowPathRatherThanSharedMembership() {
        let selected = "漢語\u{0}吳語\u{0}太湖"
        XCTAssertTrue(RegionSelection.isAncestor("漢語", of: selected))
        XCTAssertTrue(RegionSelection.isAncestor("漢語\u{0}吳語", of: selected))
        XCTAssertFalse(RegionSelection.isAncestor(selected, of: selected))
        XCTAssertFalse(RegionSelection.isAncestor("漢語\u{0}吳", of: selected))
        XCTAssertFalse(RegionSelection.isAncestor(nil, of: selected))
    }
    func testReferencePreferenceRoundTripKeepsOrderAndModes() {
        var prefs = ReferencePreferences()
        prefs.order = ["康熙", "Unicode", "康熙", "unknown"]
        prefs.hidden = ["說文"]
        prefs.fieldModes["兩分"] = "collapsed"
        prefs.fieldModes["山人"] = "hidden"
        let restored = ReferencePreferences.load(prefs.encoded)
        XCTAssertEqual(Array(restored.order.prefix(2)), ["康熙", "說文"])
        XCTAssertEqual(restored.mode("Unicode"), "expanded")
        XCTAssertEqual(restored.mode("Unicode區段"), "collapsed")
        XCTAssertEqual(Set(restored.order), Set(ReferencePreferences.links))
        XCTAssertEqual(restored.order.count, ReferencePreferences.links.count)
        XCTAssertTrue(restored.hidden.contains("說文"))
        XCTAssertEqual(restored.mode("兩分"), "collapsed")
        XCTAssertEqual(restored.mode("山人"), "hidden")
    }
    func testPlainTextRoundTripAndMergePreserveNotesMembershipAndFilter() throws {
        var original = NotebookArchive()
        let book = VocabularyBook(id: UUID(), name: "課堂")
        original.books.append(book)
        original.selected = [book.id]
        let row = Reading(id: 7, characters: "𠀀 輸", language: "甲", pronunciation: "tɕiɔŋ¹\tɵ", note: "多行\n註釋")
        original.entries = [SavedReading(reading: row, note: "筆記\n第二行", books: [book.id, VocabularyBook.original.id])]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        XCTAssertNotNil(String(data: data, encoding: .utf8))
        let imported = try NotebookArchive.decode(data)
        var target = NotebookArchive()
        target.entries = [SavedReading(reading: row, note: "現有筆記", books: [VocabularyBook.original.id])]
        let selected = target.selected
        target.merge(imported)
        XCTAssertEqual(target.selected, selected)
        XCTAssertEqual(target.entries.count, 1)
        XCTAssertEqual(target.entries[0].membership, [book.id, VocabularyBook.original.id])
        XCTAssertEqual(target.entries[0].note, "現有筆記\n筆記\n第二行")
        target.merge(imported)
        XCTAssertEqual(target.entries.count, 1)
        XCTAssertEqual(target.entries[0].note, "現有筆記\n筆記\n第二行")
        XCTAssertEqual(target.entries[0].reading, row)
        XCTAssertThrowsError(try NotebookArchive.decode(Data("broken".utf8)))
    }
    func testDefaultFavoritesAreIndependentOfBrowsingAndAllowSeveralBooks() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var archive = NotebookArchive()
        let book = VocabularyBook(id: UUID(), name: "課堂")
        archive.books.append(book); archive.selected = []
        defaults.set([book.id.uuidString, VocabularyBook.original.id.uuidString, UUID().uuidString], forKey: FavoritePreferences.defaultsKey)
        XCTAssertEqual(FavoritePreferences.targets(in: archive, defaults: defaults), [book.id, VocabularyBook.original.id])
        defaults.set([], forKey: FavoritePreferences.defaultsKey)
        XCTAssertTrue(FavoritePreferences.targets(in: archive, defaults: defaults).isEmpty)
    }
    func testImportRejectsDanglingMembershipAndDuplicateIdentity() throws {
        var archive = NotebookArchive()
        let row = Reading(id: 1, characters: "中", language: "甲", pronunciation: "a", note: "")
        let entry = SavedReading(reading: row, books: [UUID()])
        XCTAssertThrowsError(try NotebookArchive.decode(JSONEncoder().encode([entry])))
        archive.entries = [entry]
        XCTAssertThrowsError(try NotebookArchive.decode(JSONEncoder().encode(archive)))
        let valid = SavedReading(reading: row, books: [VocabularyBook.original.id])
        archive.entries = [valid, valid]
        XCTAssertThrowsError(try NotebookArchive.decode(JSONEncoder().encode(archive)))
    }

    func testIndexedResultsPreserveOrderAndRepeatedReadings() {
        let rows = [Reading(id: 1, characters: "中 輸", language: "乙", pronunciation: "a", note: ""), Reading(id: 2, characters: "中", language: "甲", pronunciation: "b", note: ""), Reading(id: 3, characters: "中", language: "乙", pronunciation: "c", note: "")]
        let sorted = ResultOrdering.sorted(rows, ranks: ["甲": 0, "乙": 1])
        XCTAssertEqual(sorted.map(\.id), [2, 1, 3])
        let index = CharacterResults.index(sorted)
        XCTAssertEqual(index["中"]?.map(\.language), ["甲", "乙"])
        XCTAssertEqual(index["中"]?.last?.readings.map(\.id), [1, 3])
        XCTAssertEqual(index["輸"]?.first?.readings.map(\.id), [1])
    }
    func testTonePreviewUsesYinPingAnd53() {
        let part = ToneDisplay.parts(ToneDisplay.previewReading, table: ToneDisplay.previewTable, style: "hanzi", pitchStyle: "number")
        XCTAssertEqual(ToneDisplay.previewCharacter, "身")
        XCTAssertEqual(part.first?.base, "ɕiŋ")
        XCTAssertEqual(part.first?.tone, "陰平")
        XCTAssertEqual(part.first?.pitch, "53")
        XCTAssertEqual(ToneDisplay.parts(ToneDisplay.previewReading, table: ToneDisplay.previewTable, style: "baSheng", pitchStyle: "number").first?.tone, "①")
    }

    func testLargeResultIndexMatchesExistingGrouping() {
        let characters = (0..<60).compactMap { UnicodeScalar(0x4E00 + $0).map(String.init) }
        let rows = (0..<6000).map { i in Reading(id: Int64(i), characters: characters[i % characters.count], language: "點\(i % 100)", pronunciation: "a\(i % 8)", note: "較長的注釋內容") }
        let start = Date()
        let old = Dictionary(uniqueKeysWithValues: characters.map { ($0, CharacterResults.groups(rows, character: $0)) })
        let oldDuration = Date().timeIntervalSince(start)
        let indexedStart = Date()
        let indexed = CharacterResults.index(rows)
        let indexedDuration = Date().timeIntervalSince(indexedStart)
        for character in characters {
            XCTAssertEqual(indexed[character]?.map(\.id), old[character]?.map(\.id))
            XCTAssertEqual(indexed[character]?.flatMap { $0.readings.map(\.id) }, old[character]?.flatMap { $0.readings.map(\.id) })
        }
        print("RESULT_INDEX_BENCHMARK old=\(oldDuration)s indexed=\(indexedDuration)s rows=6000 characters=60")
    }

}
