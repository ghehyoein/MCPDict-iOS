import XCTest
@testable import MCPDictIOS

final class ExportPresentationTests: XCTestCase {
    func testSharedFilesPreserveUnicodeAndHaveIndependentLifetimes() throws {
        let first = Data("\u{FEFF}漢字,讀音\r\n𠀀,ɕiŋ53\r\n".utf8)
        let second = Data("second export".utf8)
        let a = try ExportFiles.prepare(first, filename: "對應表.csv")
        let b = try ExportFiles.prepare(second, filename: "對應表.csv")
        defer { ExportFiles.remove(a); ExportFiles.remove(b) }
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.lastPathComponent, "對應表.csv")
        XCTAssertEqual(try Data(contentsOf: a), first)
        XCTAssertEqual(try Data(contentsOf: b), second)
        ExportFiles.remove(a)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertEqual(try Data(contentsOf: b), second)
    }
    func testNotebookShareRetainsImportableArchive() throws {
        let archive = NotebookArchive()
        let restored = try NotebookArchive.decode(ExportFiles.json(archive))
        XCTAssertEqual(restored.books.map(\.id), archive.books.map(\.id))
        XCTAssertEqual(restored.books.map(\.name), archive.books.map(\.name))
        XCTAssertEqual(restored.entries.count, archive.entries.count)
    }
}
