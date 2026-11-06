import XCTest
@testable import MCPDictIOS

final class RevisionSixTests: XCTestCase {
    func testOriginalDiagnosticsSelectsOnlyRequestedTable() {
        let raw = "甲話（甲）-a.tsv-editor *1\n\t【甲】的讀音太多:a1,a2\n乙話（乙）-b.tsv-editor *1\n\t【乙】提示\n"
        XCTAssertEqual(UpstreamDiagnostics.extract(raw, name: "甲"), "【甲】的讀音太多:a1,a2")
        XCTAssertEqual(UpstreamDiagnostics.extract(raw, name: "不存在"), "")
    }
    @MainActor func testBlankStartupAndFavoritePersistence() throws {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("favorites.json")
        let old = try? Data(contentsOf: file)
        defer { if let old { try? old.write(to: file) } else { try? FileManager.default.removeItem(at: file) } }
        let model = AppModel()
        XCTAssertEqual(model.query, "")
        let reading = Reading(id: 1, characters: "輸", language: "甲", pronunciation: "su1", note: "運輸")
        model.save(reading); model.save(reading)
        XCTAssertEqual(model.favorites.count, 1)
        let restored = try NotebookArchive.decode(Data(contentsOf: file)).entries
        XCTAssertEqual(restored.first?.reading, reading)
        model.deleteFavorites(IndexSet(integer: 0))
        XCTAssertTrue(model.favorites.isEmpty)
    }
}
