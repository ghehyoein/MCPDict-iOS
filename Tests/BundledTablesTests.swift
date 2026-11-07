import XCTest
import CryptoKit
@testable import MCPDictIOS

final class BundledTablesTests: XCTestCase {
    private func package(_ name: String, _ text: String) -> TablePackage {
        let data = Data(text.utf8)
        var blob = Data("blob \(data.count)\0".utf8); blob.append(data)
        let git = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        let hash = SHA256.hash(data: Data(("tsv-v1:" + git).utf8)).map { String(format: "%02x", $0) }.joined()
        let id = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
        let commit = String(repeating: "a", count: 40)
        return TablePackage(id: String(id.prefix(24)), name: name, fullName: name, atlas: ["測試"], dictionary: ["測試"], administrative: ["測試"], source: "fixture", sourceCommit: commit, recordCount: 1, size: Int64(data.count), sha256: hash, url: URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(commit)/tools/tables/output/\(name).tsv")!, format: "upstream-tsv-v1", gitBlob: git)
    }
    private func fixture() throws -> (URL, URL, TableCatalog) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let table = package("甲", "中\ta1\t註釋\n")
        let catalog = TableCatalog(schemaVersion: 1, version: table.sourceCommit, sourceRepository: UpstreamTables.repository, sourceCommit: table.sourceCommit, scope: "test", tables: [table])
        let raw = Data("中\ta1\t註釋\n".utf8)
        try raw.write(to: bundle.appendingPathComponent(table.id + ".tsv"))
        try UpstreamTables.importTSV(raw, table: table, to: bundle.appendingPathComponent("bundled.db"))
        try JSONEncoder().encode(catalog).write(to: bundle.appendingPathComponent("catalog.json"))
        return (root.appendingPathComponent("installed"), bundle, catalog)
    }
    func testOfflineInstallRemovalRelaunchAndRestore() async throws {
        let (root, bundle, catalog) = try fixture()
        let original = try Data(contentsOf: bundle.appendingPathComponent("bundled.db"))
        let repo = DictionaryRepository()
        let store = TableStore(repository: repo, root: root, bundledRoot: bundle)
        try await store.installBundledTablesIfNeeded()
        let found = try await repo.search("中", mode: .character, language: "甲")
        XCTAssertEqual(found.map(\.pronunciation), ["a1"])
        let removed = try await store.remove(selected: [catalog.tables[0].id])
        XCTAssertTrue(removed.tables.isEmpty)
        let reopened = TableStore(repository: repo, root: root, bundledRoot: bundle)
        try await reopened.installBundledTablesIfNeeded()
        let after = try await reopened.restore()
        XCTAssertTrue(after?.tables.isEmpty == true)
        let restored = try await reopened.download(catalog, selected: [catalog.tables[0].id]) { _ in }
        XCTAssertNil(restored.failure)
        XCTAssertEqual(restored.installation.tables.count, 1)
        XCTAssertEqual(try Data(contentsOf: bundle.appendingPathComponent("bundled.db")), original)
    }
    func testManualUpdateSurvivesRelaunchAndUpgrade() async throws {
        let (root, bundle, catalog) = try fixture()
        let repo = DictionaryRepository()
        let store = TableStore(repository: repo, root: root, bundledRoot: bundle)
        // Simulate a user with a newer table before first upgrading to the bundled version.
        let updated = package("甲", "中\ta2\t新的註釋\n")
        let file = bundle.appendingPathComponent("update.tsv")
        try Data("中\ta2\t新的註釋\n".utf8).write(to: file)
        let current = TableCatalog(schemaVersion: 1, version: "updated", sourceRepository: catalog.sourceRepository, sourceCommit: catalog.sourceCommit, scope: "", tables: [updated])
        _ = try await store.download(current, selected: [updated.id], localFiles: [updated.id: file]) { _ in }
        try await store.installBundledTablesIfNeeded()
        let after = try await repo.search("中", mode: .character, language: "甲")
        XCTAssertEqual(after.map(\.pronunciation), ["a2"])
        let reopened = TableStore(repository: repo, root: root, bundledRoot: bundle)
        try await reopened.installBundledTablesIfNeeded()
        let state = try await reopened.restore()
        XCTAssertEqual(state?.tables.first?.sha256, updated.sha256)
    }
    func testReferenceIndexMatchesAndroidUnicodePopup() async throws {
        let one = try await CharacterReferenceIndex.shared.lookup("一")
        XCTAssertEqual(one.code, "U+4E00")
        XCTAssertEqual(one.block, "基本 1.1")
        XCTAssertEqual(one.values["兩分"], "heng 丿")
        XCTAssertEqual(one.values["字形描述"], "一(陸港臺日韓朝越)")
        XCTAssertEqual(one.values["總筆畫數"], "1")
        XCTAssertEqual(one.values["五筆86"], "ggll")
        XCTAssertTrue(CharacterReference.books.allSatisfy { one.values[$0]?.isEmpty == false })
        let rare = try await CharacterReferenceIndex.shared.lookup("𠀀")
        XCTAssertEqual(rare.block, "擴展B 3.1")
    }
    func testPackagedCatalogContainsEveryBundledTable() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("BundledTables")
        let catalog = try JSONDecoder().decode(TableCatalog.self, from: Data(contentsOf: root.appendingPathComponent("catalog.json")))
        try catalog.validate()
        XCTAssertGreaterThan(catalog.tables.count, 1000)
        let transitions = DictionaryTransitions(tables: catalog.tables)
        let eligible = catalog.tables.filter(transitions.hasTransition)
        let index = SelectionIndex(tables: eligible, grouping: .dictionary, additionalPaths: transitions.additionalPaths(eligible))
        XCTAssertNil(index.nodes["g:域外方音"])
        for name in ["南通", "贊皇", "贛榆", "繁峙", "阿拉善"] {
            let table = try XCTUnwrap(catalog.tables.first { $0.name == name })
            XCTAssertTrue(transitions.hasTransition(table), name)
            XCTAssertFalse(transitions.destinations(table).isEmpty, name)
        }
        XCTAssertTrue(eligible.allSatisfy { Set(TableColors.hexes($0.dictionaryColor)).count > 1 })
        let db = try SQLiteConnection(url: root.appendingPathComponent("bundled.db"))
        try db.validate()
        let counts = try db.rows("SELECT 語言, count(*) AS n FROM langs GROUP BY 語言")
        let actual = Dictionary(uniqueKeysWithValues: counts.map { ($0["語言"]!, Int($0["n"]!)!) })
        XCTAssertEqual(actual.count, catalog.tables.count)
        for table in catalog.tables {
            XCTAssertEqual(actual[table.name], table.recordCount, table.name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(table.id + ".tsv").path))
        }
    }
}
