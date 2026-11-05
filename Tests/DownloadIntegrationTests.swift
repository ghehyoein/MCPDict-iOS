import XCTest
@testable import MCPDictIOS

// Direct Android upstream catalog, Git blob validation and TSV import. Requires internet.
final class DownloadIntegrationTests: XCTestCase {
    func testUpstreamMandarinDownloadsAndQueries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = DictionaryRepository()
        let store = TableStore(repository: repository, root: directory)
        let catalog = try await store.catalog()
        XCTAssertGreaterThan(catalog.tables.count, 100)
        XCTAssertTrue(catalog.tables.allSatisfy { $0.url.host == "raw.githubusercontent.com" })
        let mandarin = try XCTUnwrap(catalog.tables.first { $0.name == "普通話" })
        let state = try await store.apply(catalog, selected: [mandarin.id]) { _ in }
        XCTAssertEqual(state.tables.map(\.name), ["普通話"])
        let results = try await repository.search("中", mode: .character, language: "普通話")
        XCTAssertEqual(Set(results.map(\.pronunciation)), ["zhong1", "zhong4"])
        XCTAssertTrue(results.allSatisfy { $0.characters == "中" })
        let languages = try await repository.languages()
        XCTAssertEqual(languages, ["普通話"])
    }
}
