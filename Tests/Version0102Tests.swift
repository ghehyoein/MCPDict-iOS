import XCTest
import UIKit
@testable import MCPDictIOS

final class Version0102Tests: XCTestCase {
    func testCustomSchemeColorArchiveAndNonDestructiveMerge() throws {
        var source = CustomLanguageSchemes(legacy: ["甲"])
        source.schemes[0].colorHex = "#123ABC"
        XCTAssertTrue(source.create("江淮 洪巢")); source.members = ["乙", "丙"]
        let archive = try JSONDecoder().decode(CustomSchemeArchive.self, from: JSONEncoder().encode(CustomSchemeArchive(source)))
        XCTAssertEqual(archive.schemes[0].colorHex, "#123ABC")
        XCTAssertNotNil(archive.schemes[1].colorHex)
        var target = CustomLanguageSchemes(legacy: ["丁"])
        target.schemes[0].colorHex = "#ABC123"
        let merged = try archive.merging(into: target)
        XCTAssertEqual(merged.schemes[0].languages, ["甲", "丁"])
        XCTAssertEqual(merged.schemes[0].colorHex, "#ABC123")
        XCTAssertEqual(merged.schemes[1].languages, ["乙", "丙"])
        var invalid = archive; invalid.schemes[0].colorHex = "wrong"
        XCTAssertThrowsError(try invalid.merging(into: target))
        XCTAssertEqual(target.schemes[0].languages, ["丁"])
        source.retainColors()
        let original = source.color(for: "乙")
        source.schemes.reverse()
        XCTAssertEqual(source.color(for: "乙"), original)
        XCTAssertEqual(CustomLanguageSchemes.validColor(" 12abef "), "#12ABEF")
        XCTAssertNil(CustomLanguageSchemes.validColor("#1234"))
    }
    @MainActor func testSelectionNamespacesRemainIndependent() throws {
        let suite = "0102-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let games = LanguageSelectionState(namespace: "games", defaults: defaults)
        let longText = LanguageSelectionState(namespace: "longText", defaults: defaults)
        let dictionary = LanguageSelectionState(namespace: "dictionary", defaults: defaults)
        let downloads = LanguageSelectionState(namespace: "downloads", defaults: defaults)
        games.grouping = .person; games.flags.islandMode = .hide
        XCTAssertEqual(LanguageSelectionState(namespace: "games", defaults: defaults).grouping, .person)
        for state in [longText, dictionary, downloads] {
            XCTAssertEqual(state.grouping, .atlas); XCTAssertEqual(state.flags.islandMode, .show)
        }
    }
    func testGlyphStandardsKeepTextAndHaveExplicitLanguageAttributes() {
        XCTAssertEqual(GlyphStandard.allCases.count, 6)
        for standard in GlyphStandard.allCases {
            let text = NSMutableAttributedString(string: "骨辶 身ɕiŋ53")
            GlyphStandard.apply(to: text, standard: standard)
            XCTAssertEqual(text.string, "骨辶 身ɕiŋ53")
            XCTAssertFalse(text.attributes(at: 0, effectiveRange: nil).isEmpty)
            XCTAssertEqual(GlyphStandard.font(.systemFont(ofSize: 17), standard: standard).pointSize, 17)
        }
    }
}
