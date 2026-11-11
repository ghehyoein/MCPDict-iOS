import XCTest
@testable import MCPDictIOS

final class ReadingMarkersTests: XCTestCase {
    func testSuffixMarkersAndMultipleReadings() {
        XCTAssertEqual(ReadingMarkers.keys("pa1-\tba2= ka3? ta4*"), ["白讀", "文讀", "待考", "俗字"])
        XCTAssertEqual(ReadingMarkers.keys("pa1- pa2-"), ["白讀"])
        XCTAssertEqual(ReadingMarkers.keys("*pa a-b - = ? *"), [])
        XCTAssertEqual(ReadingMarkers.keys("pa1-=*?"), ["白讀", "文讀", "待考", "俗字"])
    }
    func testDisplayPreservesSourceAndMapAnnotations() {
        let row = Reading(id: 1, characters: "字", language: "測試", pronunciation: "pa1-", note: "來源原文")
        XCTAssertEqual(row.note, "來源原文")
        XCTAssertEqual(row.pronunciation, "pa1-")
        XCTAssertTrue(row.displayNote.hasPrefix("來源原文；"))
        let line = MapSearchResult.Line(text: row.pronunciation, pronunciation: row.pronunciation, note: row.note)
        XCTAssertEqual(line.fullText, row.pronunciation + "  " + row.displayNote)
        XCTAssertEqual(ReadingMarkers.note("原文?", pronunciation: "pa1"), "原文?")
    }
}
