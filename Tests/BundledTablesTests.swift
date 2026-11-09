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
    private func historicalUpgradeFixture() throws -> (URL, URL, TableCatalog) {
        let (root, bundle, original) = try fixture()
        var kept = original.tables[0]
        kept.metadata = ["歷史音": "0"]
        var removed = package("乙", "中\tb1\t使用者移除\n")
        removed.metadata = ["歷史音": "0"]
        let db = try SQLiteConnection(url: bundle.appendingPathComponent("bundled.db"), readOnly: false)
        _ = try db.rows("INSERT INTO langs VALUES (?,?,?,?)", ["中", "乙", "b1", "使用者移除"])
        _ = try db.rows("INSERT INTO info VALUES (?,?)", ["乙", "乙"])
        let catalog = TableCatalog(schemaVersion: 1, version: original.version, sourceRepository: original.sourceRepository,
                                   sourceCommit: original.sourceCommit, scope: "old-bundle", tables: [kept, removed])
        try JSONEncoder().encode(catalog).write(to: bundle.appendingPathComponent("catalog.json"))
        return (root, bundle, catalog)
    }
    private func archives(_ old: TableCatalog, commit: String, marker: String) -> TableCatalog {
        let tables = old.tables.map { table in
            TablePackage(id: table.id, name: table.name, fullName: table.name + "-" + String(commit.prefix(1)),
                atlas: table.atlas, dictionary: table.dictionary, administrative: table.administrative,
                source: "archive-" + commit, sourceCommit: commit, recordCount: table.recordCount,
                size: table.size, sha256: table.sha256,
                url: URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(commit)/tools/tables/output/")!.appendingPathComponent(table.name + ".tsv"),
                metadata: ["歷史音": marker], location: table.location, atlasColor: table.atlasColor,
                dictionaryColor: table.dictionaryColor, format: table.format, gitBlob: table.gitBlob)
        }
        return TableCatalog(schemaVersion: 1, version: commit, sourceRepository: old.sourceRepository,
                            sourceCommit: commit, scope: "updated-archives", tables: tables)
    }
    func testUpgradeSynchronizesHistoricalArchivesWithoutRestoringRemovedTables() async throws {
        for missingCache in [false, true] {
            let (root, bundle, original) = try historicalUpgradeFixture()
            let repository = DictionaryRepository()
            let store = TableStore(repository: repository, root: root, bundledRoot: bundle)
            try await store.installBundledTablesIfNeeded()
            let before = try await store.remove(selected: [original.tables[1].id])
            XCTAssertTrue(before.tables.filter(LanguageFlags(history: true).matches).isEmpty)
            let metadataMarker = root.appendingPathComponent("bundled-metadata-installed")
            // Older app versions only wrote bundled-installed.
            try FileManager.default.removeItem(at: metadataMarker)
            let cacheFile = root.appendingPathComponent("catalog.json")
            if missingCache { try FileManager.default.removeItem(at: cacheFile) }
            let database = root.appendingPathComponent(try XCTUnwrap(before.databaseFile))
            let databaseBytes = try Data(contentsOf: database)
            let next = archives(original, commit: String(repeating: "b", count: 40), marker: "#4D4D4D")
            try JSONEncoder().encode(next).write(to: bundle.appendingPathComponent("catalog.json"), options: .atomic)
            let reopened = TableStore(repository: repository, root: root, bundledRoot: bundle)
            try await reopened.installBundledTablesIfNeeded()
            let restored = try await reopened.restore()
            let after = try XCTUnwrap(restored)
            let old = try XCTUnwrap(before.tables.first), updated = try XCTUnwrap(after.tables.first)
            let eligible = after.tables.filter(LanguageFlags(history: true).matches)
            XCTAssertEqual(eligible.map(\.name), [old.name])
            let tree = SelectionIndex(tables: eligible, grouping: .atlas)
            XCTAssertEqual(tree.nodes["t:" + old.id]?.table?.metadata?["歷史音"], "#4D4D4D")
            XCTAssertFalse(tree.rows(expanded: [], matching: nil, scope: .points).isEmpty)
            XCTAssertEqual(Set(after.tables.map(\.id)), [old.id])
            XCTAssertEqual(updated.fullName, next.tables[0].fullName)
            XCTAssertEqual(updated.source, next.tables[0].source)
            XCTAssertEqual(updated.sha256, old.sha256)
            XCTAssertEqual(updated.gitBlob, old.gitBlob)
            XCTAssertEqual(updated.sourceCommit, old.sourceCommit)
            XCTAssertEqual(updated.url, old.url)
            XCTAssertEqual(updated.recordCount, old.recordCount)
            XCTAssertEqual(updated.size, old.size)
            XCTAssertEqual(after.catalogVersion, before.catalogVersion)
            XCTAssertEqual(after.databaseFile, before.databaseFile)
            XCTAssertEqual(try Data(contentsOf: database), databaseBytes)
            let rows = try await repository.search("中", mode: .character, language: old.name)
            XCTAssertEqual(rows.map(\.pronunciation), ["a1"])
            let removedRows = try await repository.search("中", mode: .character, language: original.tables[1].name)
            XCTAssertTrue(removedRows.isEmpty)
            let cached = await reopened.cachedCatalog()
            XCTAssertEqual(cached?.sourceCommit, next.sourceCommit)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("bundled-installed"), encoding: .utf8), original.version)
            XCTAssertEqual(try String(contentsOf: metadataMarker, encoding: .utf8), next.sourceCommit)
            // Same-bundle relaunch must not rewrite any installation/catalog marker.
            let files = [root.appendingPathComponent("index.json"), cacheFile, metadataMarker]
            let fixedDate = Date(timeIntervalSince1970: 1_234_567_890)
            for file in files { try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: file.path) }
            try await reopened.installBundledTablesIfNeeded()
            for file in files {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                XCTAssertEqual(attributes[.modificationDate] as? Date, fixedDate)
            }
            // A second app upgrade must compare against the last processed bundle,
            // not forever against the first installation's bundled-installed value.
            let later = archives(original, commit: String(repeating: "d", count: 40), marker: "#808080")
            try JSONEncoder().encode(later).write(to: bundle.appendingPathComponent("catalog.json"), options: .atomic)
            try await reopened.installBundledTablesIfNeeded()
            let laterState = try await reopened.restore()
            XCTAssertEqual(laterState?.tables.first?.metadata?["歷史音"], "#808080")
            XCTAssertEqual(laterState?.tables.map(\.id), [old.id])
            XCTAssertEqual(try Data(contentsOf: database), databaseBytes)
        }
    }
    func testUpgradePreservesManuallyRefreshedArchives() async throws {
        for manualMarker in ["#BFBFBF", "0"] {
            let (root, bundle, original) = try historicalUpgradeFixture()
            let repository = DictionaryRepository()
            let store = TableStore(repository: repository, root: root, bundledRoot: bundle)
            try await store.installBundledTablesIfNeeded()
            let restored = try await store.restore()
            let before = try XCTUnwrap(restored)
            try FileManager.default.removeItem(at: root.appendingPathComponent("bundled-metadata-installed"))
            let database = root.appendingPathComponent(try XCTUnwrap(before.databaseFile))
            let databaseBytes = try Data(contentsOf: database)
            let manual = archives(original, commit: String(repeating: "c", count: 40), marker: manualMarker)
            let manualBytes = try JSONEncoder().encode(manual)
            let cacheFile = root.appendingPathComponent("catalog.json")
            try manualBytes.write(to: cacheFile, options: .atomic)
            let next = archives(original, commit: String(repeating: "b", count: 40), marker: "#4D4D4D")
            try JSONEncoder().encode(next).write(to: bundle.appendingPathComponent("catalog.json"), options: .atomic)
            let reopened = TableStore(repository: repository, root: root, bundledRoot: bundle)
            try await reopened.installBundledTablesIfNeeded()
            let state = try await reopened.restore()
            let after = try XCTUnwrap(state)
            XCTAssertEqual(try Data(contentsOf: cacheFile), manualBytes)
            XCTAssertEqual(after.tables.map(\.id), before.tables.map(\.id))
            for (old, updated) in zip(before.tables, after.tables) {
                XCTAssertEqual(updated.metadata?["歷史音"], manualMarker)
                XCTAssertEqual(updated.fullName, old.name + "-c")
                XCTAssertEqual(updated.source, "archive-" + manual.sourceCommit)
                XCTAssertEqual(updated.sha256, old.sha256)
                XCTAssertEqual(updated.sourceCommit, old.sourceCommit)
                XCTAssertEqual(updated.gitBlob, old.gitBlob)
                XCTAssertEqual(updated.url, old.url)
            }
            let eligible = after.tables.filter(LanguageFlags(history: true).matches)
            XCTAssertEqual(eligible.count, manualMarker == "0" ? 0 : 2)
            let tree = SelectionIndex(tables: eligible, grouping: .atlas)
            XCTAssertEqual(tree.roots.isEmpty, manualMarker == "0")
            XCTAssertEqual(after.databaseFile, before.databaseFile)
            XCTAssertEqual(try Data(contentsOf: database), databaseBytes)
        }
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
