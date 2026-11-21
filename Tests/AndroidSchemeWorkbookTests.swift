import XCTest
@testable import MCPDictIOS

final class AndroidSchemeWorkbookTests: XCTestCase {
    func testImportPreservesMembershipPathsAndIndividualColors() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "AndroidExample", withExtension: "xlsx"))
        let archive = try AndroidSchemeWorkbook.read(url)
        var store = try archive.merging(into: CustomLanguageSchemes())
        XCTAssertEqual(store.schemes.map(\.name), ["默認方案", "AndroidExample", "AndroidExample－嶺南", "AndroidExample－嶺南－沿海", "AndroidExample－另一組"])
        XCTAssertEqual(store.schemes[1].languages, ["直属"])
        XCTAssertEqual(store.schemes[3].languages, ["香港", "未知 & 名稱"])
        XCTAssertEqual(store.schemes[4].languages, ["香港"])
        store.paletteScheme = "AndroidExample－嶺南"
        XCTAssertEqual(store.paletteColors(), ["香港": "#246810", "未知 & 名稱": "#135791"])
        let data = try JSONEncoder().encode(CustomSchemeArchive(store))
        let reimport = try JSONDecoder().decode(CustomSchemeArchive.self, from: data).merging(into: store)
        XCTAssertEqual(reimport.schemes, store.schemes)
    }
}
