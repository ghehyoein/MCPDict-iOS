import XCTest
@testable import MCPDictIOS

final class ToolsRevisionTests: XCTestCase {
    func testTableKeepsPolyphonyNotesAndMissingCells() {
        let rows = [Reading(id: 1, characters: "好 行", language: "甲", pronunciation: "a1", note: "原文"), Reading(id: 2, characters: "好", language: "甲", pronunciation: "a2", note: "又讀"), Reading(id: 3, characters: "行", language: "乙", pronunciation: "b", note: "")]
        let index = ResultTableIndex(rows)
        XCTAssertEqual(index.characters, ["好", "行"])
        XCTAssertEqual(index.languages, ["甲", "乙"])
        XCTAssertEqual(index.cells["甲"]?["好"]?.map(\.pronunciation), ["a1", "a2"])
        XCTAssertEqual(index.cells["甲"]?["好"]?.last?.note, "又讀")
        XCTAssertNil(index.cells["乙"]?["好"])
    }
    func testCombinedAdministrativeLevelsAndCharacterInput() {
        XCTAssertTrue(GuessLogic.matchesLevel("省會,地級", "省會"))
        XCTAssertTrue(GuessLogic.matchesLevel("省會,地級", "地級"))
        XCTAssertTrue(GuessLogic.matchesLevel("省會,地級", "縣級"))
        XCTAssertFalse(GuessLogic.matchesLevel("鄉級", "縣級"))
        XCTAssertTrue(GuessLogic.isCharacter("𠀀"))
        XCTAssertFalse(GuessLogic.isCharacter("a"))
        XCTAssertFalse(GuessLogic.isCharacter("あ"))
    }
    func testDirectionsAndDistanceUnits() {
        let a = TableLocation(longitude: 0, latitude: 0)
        let east = GuessLogic.geography(from: a, to: TableLocation(longitude: 1, latitude: 0))
        XCTAssertEqual(east.arrow, "➡️")
        XCTAssertEqual(east.li, 222.64, accuracy: 1)
        XCTAssertEqual(GuessLogic.geography(from: a, to: a).li, 0)
    }
    func testGuessCorpusAndReferenceHints() async throws {
        let character = try await CharacterReferenceIndex.shared.guessCharacter(level: 1)
        XCTAssertEqual(character.count, 1)
        let hints = try await CharacterReferenceIndex.shared.lookup("一")
        XCTAssertFalse(hints.values["五筆畫", default: ""].isEmpty)
    }
    func testBundledToolRetainsBothCompleteWorkflows() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("YindianTools"))
        let js = try String(contentsOf: root.appendingPathComponent("app.js"), encoding: .utf8)
        for name in ["runEvolution", "runComparison", "showNativeComparisonMap", "getGuangyunRows", "resolveCharacters"] { XCTAssertTrue(js.contains(name)) }
    }
}

extension ToolsRevisionTests {
    func testToolsReadCompleteLanguageAndEscapeFTSName() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try SQLiteConnection(url: url, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋)")
        for index in 0..<137 {
            _ = try db.rows("INSERT INTO langs VALUES(?,?,?,?)", ["中", "測試\"點", "a\(index)", "原註"])
        }
        _ = try db.rows("INSERT INTO langs VALUES(?,?,?,?)", ["中", "其他點", "b", ""])
        let repository = DictionaryRepository()
        try await repository.open(url)
        let rows = try await repository.toolLanguageRows("測試\"點")
        XCTAssertEqual(rows.count, 137)
        XCTAssertTrue(rows.allSatisfy { $0.note == "原註" && $0.language == "測試\"點" })
    }
}
