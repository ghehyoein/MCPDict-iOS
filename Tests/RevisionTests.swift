import XCTest
import CryptoKit
@testable import MCPDictIOS

final class RevisionTests: XCTestCase {
    func testScriptSwitchAndGroupedReadingsPreserveSource() {
        XCTAssertEqual(InterfaceLanguage.text("字表下載", script: "hans"), "字表下载")
        XCTAssertEqual(InterfaceLanguage.text("設定", script: "hans"), "设置")
        XCTAssertEqual(InterfaceLanguage.text("字表下載", script: "hant"), "字表下載")
        XCTAssertTrue(InterfaceLanguage.matches("廣州", "广州"))
        let rows = [Reading(id: 1, characters: "中 忠", language: "廣州", pronunciation: "tsʊŋ1", note: "中心"),
                    Reading(id: 2, characters: "中", language: "廣州", pronunciation: "tsʊŋ3", note: "命中"),
                    Reading(id: 3, characters: "中", language: "普通話", pronunciation: "zhong1", note: "")]
        let groups = CharacterResults.groups(rows, character: "中")
        XCTAssertEqual(groups.count, 2)
        let cantonese = groups.first { $0.language == "廣州" }
        XCTAssertEqual(cantonese?.readings.map(\.pronunciation), ["tsʊŋ1", "tsʊŋ3"])
        XCTAssertEqual(cantonese?.readings.map(\.characters), ["中", "中"])
        XCTAssertEqual(CharacterResults.groups(rows, character: "忠").first?.readings.count, 1)
        XCTAssertEqual(CharacterResults.characters("中中𰻞"), ["中", "𰻞"])
        XCTAssertEqual(CharacterResults.characters("U+4E2D"), ["中"])
    }
    @MainActor func testCatalogRefreshMarksOnlyChangedInstalledContent() {
        func table(_ name: String, _ version: String, _ hash: String) -> TablePackage {
            TablePackage(id: name, name: name, fullName: name, atlas: [], dictionary: [], administrative: [], source: "", sourceCommit: version, recordCount: 1, size: 1, sha256: hash, url: URL(fileURLWithPath: "/fixture"))
        }
        let model = AppModel()
        let old = [table("甲", "old", "a"), table("乙", "old", "b"), table("丙", "old", "c")]
        model.installed = TableInstallation(catalogVersion: "old", tables: old, databaseFile: nil)
        let new = [table("甲", "new", "a"), table("乙", "new", "changed"), table("丁", "new", "d")]
        model.catalog = TableCatalog(schemaVersion: 1, version: "new", sourceRepository: "", sourceCommit: "new", scope: "", tables: new)
        XCTAssertEqual(model.downloadStates, ["甲": .downloaded, "乙": .update, "丙": .downloaded, "丁": .missing])
        model.installed = TableInstallation(catalogVersion: "new", tables: [new[1]], databaseFile: nil)
        XCTAssertEqual(model.downloadStates, ["甲": .missing, "乙": .downloaded, "丁": .missing])
    }
    func testAllMetadataFieldsAndSafeLinks() {
        let fields = UpstreamTables.metadataStrings(["維護人":"甲", "空欄":"", "字數":12, "自訂欄":["x":1]])
        XCTAssertEqual(fields.count, 4)
        XCTAssertEqual(fields["維護人"], "甲")
        XCTAssertEqual(fields["空欄"], "")
        XCTAssertEqual(fields["字數"], "12")
        XCTAssertEqual(MetadataText.plain("<a href=https://example.com>來源</a><br>說明"), "來源\n說明")
        XCTAssertEqual(MetadataText.links("<a href='javascript:alert(1)'>x</a><a href=https://example.com>a</a>").map(\.absoluteString), ["https://example.com"])
    }
    func testCancelKeepsCompletedAndUnselectedTablesAcrossRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        func fixture(_ name: String, id: String) throws -> (TablePackage, URL) {
            let data = Data("#漢字\t音標\t解釋\n中\tzhong1\t\n".utf8)
            var blob = Data("blob \(data.count)\0".utf8); blob.append(data)
            let hash = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
            let commit = String(repeating: "b", count: 40)
            let table = TablePackage(id: String(repeating: id, count: 24), name: name, fullName: name, atlas: [], dictionary: [], administrative: [], source: "fixture", sourceCommit: commit, recordCount: 0, size: Int64(data.count), sha256: String(repeating: id, count: 64), url: URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(commit)/tools/tables/output/\(name).tsv")!, metadata: ["維護人":"測試"], format: "upstream-tsv-v1", gitBlob: hash)
            let file = folder.appendingPathComponent(name + ".tsv")
            try data.write(to: file)
            return (table, file)
        }
        let (old, oldFile) = try fixture("原有", id: "1")
        let (first, firstFile) = try fixture("第一", id: "2")
        let (second, secondFile) = try fixture("第二", id: "3")
        let catalog = TableCatalog(schemaVersion: 1, version: "test", sourceRepository: UpstreamTables.repository, sourceCommit: old.sourceCommit, scope: "", tables: [old, first, second])
        let files = [old.id: oldFile, first.id: firstFile, second.id: secondFile]
        let root = folder.appendingPathComponent("store")
        let repo = DictionaryRepository()
        let store = TableStore(repository: repo, root: root)
        _ = try await store.download(catalog, selected: [old.id], localFiles: files) { _ in }
        let counts = CompletedCounts()
        let task = Task {
            try await store.download(catalog, selected: [first.id, second.id], localFiles: files, completedCount: { await counts.append($0) }) { message in
                if message.hasPrefix("已完成 1/") { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let result = try await task.value
        let reported = await counts.values
        XCTAssertEqual(reported, [0, 1])
        XCTAssertEqual(result.completed, 1)
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(Set(result.installation.tables.map(\.id)), [old.id, first.id])
        let restoredRepo = DictionaryRepository()
        let reopened = TableStore(repository: restoredRepo, root: root)
        let state = try await reopened.restore()
        XCTAssertEqual(Set(state?.tables.map(\.id) ?? []), [old.id, first.id])
        let rows = try await restoredRepo.search("中", mode: .character, language: "")
        XCTAssertEqual(Set(rows.map(\.language)), ["原有", "第一"])
        let noOp = try await reopened.download(catalog, selected: [old.id, first.id], localFiles: [:]) { _ in }
        XCTAssertEqual(noOp.completed, 0)
        XCTAssertEqual(noOp.installation.databaseFile, state?.databaseFile)
        let queriedDuringRemoval = CompletedCounts()
        let removed = try await reopened.remove(selected: [first.id]) { phase in
            if phase > 0 && phase < 1 {
                do {
                    let found = try await restoredRepo.search("中", mode: .character, language: "")
                    XCTAssertEqual(Set(found.map(\.language)), ["原有", "第一"])
                    await queriedDuringRemoval.append(found.count)
                } catch { XCTFail("Query during removal failed: \(error)") }
            }
        }
        let concurrentQueries = await queriedDuringRemoval.values
        XCTAssertGreaterThanOrEqual(concurrentQueries.count, 3)
        XCTAssertEqual(removed.tables.map(\.id), [old.id])
        let next = try await reopened.download(catalog, selected: [second.id], localFiles: files) { _ in }
        XCTAssertEqual(Set(next.installation.tables.map(\.id)), [old.id, second.id])
    }
}

private actor CompletedCounts {
    var values = [Int]()
    func append(_ count: Int) { values.append(count) }
}
