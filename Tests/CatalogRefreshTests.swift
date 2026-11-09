import XCTest
import CryptoKit
@testable import MCPDictIOS

private actor CatalogRefreshProbe {
    var urls = [URL]()
    var fractions = [Double]()
    func request(_ url: URL) { urls.append(url) }
    func progress(_ value: Double) { fractions.append(value) }
}

final class CatalogRefreshTests: XCTestCase {
    private let commit = String(repeating: "c", count: 40)
    private func table(_ name: String, data: Data) -> TablePackage {
        let oldCommit = String(repeating: "a", count: 40)
        let id = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
        var blob = Data("blob \(data.count)\0".utf8); blob.append(data)
        let hash = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        let identity = SHA256.hash(data: Data(("tsv-v1:" + hash).utf8)).map { String(format: "%02x", $0) }.joined()
        return TablePackage(id: String(id), name: name, fullName: name, atlas: ["吳語"], dictionary: ["兩浙"], administrative: [],
            source: "old", sourceCommit: oldCommit, recordCount: 1, size: Int64(data.count), sha256: identity,
            url: URL(string: "https://raw.githubusercontent.com/osfans/MCPDict/\(oldCommit)/tools/tables/output/")!.appendingPathComponent(name + ".tsv"),
            metadata: ["歷史音": "0"], format: "upstream-tsv-v1", gitBlob: hash)
    }
    private func fixture(_ name: String, malformed: Bool = false) throws -> [String: Data] {
        let names = [name, "未下載的語言點"]
        let entries: [[String: Any]] = names.map { ["path": "tools/tables/output/" + $0 + ".tsv", "type": "blob", "sha": String(repeating: "d", count: 40), "size": 200] }
        let details = Dictionary(uniqueKeysWithValues: names.map { ($0, ["語言": $0, "歷史音": "#4D4D4D", "地圖集二分區": "吳語－太湖片", "音典分區": "兩浙－浙北－松江", "文件名": $0 + ".xlsx", "經緯度": "121.5,31.2"]) })
        return ["head": try JSONEncoder().encode(["sha": commit]),
                "tree": try JSONSerialization.data(withJSONObject: ["sha": commit, "truncated": false, "tree": entries]),
                "details": malformed ? Data("[]".utf8) : try JSONEncoder().encode(details)]
    }
    func testRefreshSynchronizesArchivesButPreservesReadingsAndDownloadIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("中\told1\t保留的讀音\n".utf8)
        let old = table("1853上海", data: data), retained = table("本地留存", data: data)
        let source = root.appendingPathComponent("source.tsv"); try data.write(to: source)
        let initial = TableCatalog(schemaVersion: 1, version: old.sourceCommit, sourceRepository: UpstreamTables.repository,
                                   sourceCommit: old.sourceCommit, scope: "test", tables: [old, retained])
        let repository = DictionaryRepository()
        let store = TableStore(repository: repository, root: root, bundledRoot: nil)
        let installed = try await store.apply(initial, selected: [old.id, retained.id], localFiles: [old.id: source, retained.id: source]) { _ in }
        let database = root.appendingPathComponent(try XCTUnwrap(installed.databaseFile))
        let before = try Data(contentsOf: database)
        let responses = try fixture(old.name), probe = CatalogRefreshProbe()
        let refreshed = try await store.refreshCatalog(progress: { await probe.progress($0) }, fetch: { url in
            await probe.request(url)
            if url.path.hasSuffix("/commits/master") { return responses["head"]! }
            if url.path.contains("/git/trees/") { return responses["tree"]! }
            if url.lastPathComponent == "_詳情.json" { return responses["details"]! }
            throw DictionaryFailure(message: "Unexpected reading download")
        })
        let state = try XCTUnwrap(refreshed.installation)
        let updated = try XCTUnwrap(state.tables.first { $0.id == old.id })
        XCTAssertTrue(LanguageFlags(history: true).matches(updated))
        XCTAssertEqual(updated.location, TableLocation(longitude: 121.5, latitude: 31.2))
        XCTAssertEqual(updated.dictionary, ["兩浙", "浙北", "松江"])
        XCTAssertEqual(updated.sha256, old.sha256)
        XCTAssertEqual(updated.gitBlob, old.gitBlob)
        XCTAssertEqual(updated.size, old.size)
        XCTAssertEqual(updated.sourceCommit, old.sourceCommit)
        XCTAssertEqual(updated.recordCount, old.recordCount)
        XCTAssertEqual(Set(state.tables.map(\.id)), [old.id, retained.id])
        XCTAssertEqual(state.databaseFile, installed.databaseFile)
        XCTAssertEqual(try Data(contentsOf: database), before)
        let rows = try await repository.search("中", mode: .character, language: old.name)
        XCTAssertEqual(rows.map(\.pronunciation), ["old1"])
        let fractions = await probe.fractions, urls = await probe.urls
        XCTAssertEqual(fractions.first, 0); XCTAssertEqual(fractions.last, 1)
        XCTAssertEqual(fractions, fractions.sorted()); XCTAssertGreaterThan(fractions.count, 3)
        XCTAssertEqual(urls.count, 3)
        let model = await MainActor.run { AppModel() }
        await MainActor.run {
            model.installed = state; model.catalog = refreshed.catalog
            XCTAssertEqual(model.downloadStates[old.id], .update)
        }
        // A cached latest catalog still repairs a stale installed archive without refetching TSVs.
        try JSONEncoder().encode(installed).write(to: root.appendingPathComponent("index.json"), options: .atomic)
        let cached = try await store.refreshCatalog { url in
            XCTAssertTrue(url.path.hasSuffix("/commits/master"))
            return responses["head"]!
        }
        XCTAssertTrue(LanguageFlags(history: true).matches(try XCTUnwrap(cached.installation?.tables.first { $0.id == old.id })))
        let reopened = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        let persisted = try await reopened.restore()
        XCTAssertEqual(persisted?.tables, cached.installation?.tables)
    }
    func testPackagedArchivesContainHistoricalGrayMarkers() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("BundledTables")
        let catalog = try JSONDecoder().decode(TableCatalog.self, from: Data(contentsOf: root.appendingPathComponent("catalog.json")))
        for name in ["1853上海", "1851寧波"] {
            let table = try XCTUnwrap(catalog.tables.first { $0.name == name })
            XCTAssertEqual(LanguageFlags.historicalMarker(table), "#4D4D4D")
            XCTAssertTrue(LanguageFlags(history: true).matches(table))
        }
        for name in ["上海", "寧波", "廣韻"] {
            XCTAssertFalse(LanguageFlags(history: true).matches(try XCTUnwrap(catalog.tables.first { $0.name == name })))
        }
        let gray = catalog.tables.filter { LanguageFlags.historicalMarker($0) != nil }.count
        let eligible = catalog.tables.filter(LanguageFlags(history: true).matches).count
        print("PACKAGED_HISTORY tables=\(catalog.tables.count) gray=\(gray) eligible=\(eligible) commit=\(catalog.sourceCommit)")
    }
    func testInvalidArchivesLeaveCachedCatalogAndInstalledIndexIntact() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = table("1853上海", data: Data("中\ta1\n".utf8))
        let initial = TableCatalog(schemaVersion: 1, version: old.sourceCommit, sourceRepository: UpstreamTables.repository, sourceCommit: old.sourceCommit, scope: "test", tables: [old])
        let state = TableInstallation(catalogVersion: old.sourceCommit, tables: [old], databaseFile: nil)
        let catalogData = try JSONEncoder().encode(initial), stateData = try JSONEncoder().encode(state)
        try catalogData.write(to: root.appendingPathComponent("catalog.json"))
        try stateData.write(to: root.appendingPathComponent("index.json"))
        let responses = try fixture(old.name, malformed: true)
        let store = TableStore(repository: DictionaryRepository(), root: root, bundledRoot: nil)
        do {
            _ = try await store.refreshCatalog { url in
                responses[url.path.hasSuffix("/commits/master") ? "head" : url.path.contains("/git/trees/") ? "tree" : "details"]!
            }
            XCTFail("Malformed archives must fail the refresh")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("catalog.json")), catalogData)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("index.json")), stateData)
    }
}
