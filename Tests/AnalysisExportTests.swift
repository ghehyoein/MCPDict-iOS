import XCTest
import UIKit
@testable import MCPDictIOS

final class AnalysisExportTests: XCTestCase {
    func testCorrespondenceCSVRetainsUnicodeQuotesAndAllExamples() {
        let csv = AnalysisCSV.correspondences([.init(left: "a,\"b", right: "ɕ\niŋ", chars: ["身", "𠀀"])], languages: ["甲", "乙"], mode: "聲母")
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("\"a,\"\"b\""))
        XCTAssertTrue(csv.contains("\"ɕ\niŋ\""))
        XCTAssertTrue(csv.contains("\"2\",\"身 𠀀\""))
    }
    func testSoundClassExportIncludesEveryLanguageAndSavedColor() {
        let csv = AnalysisCSV.soundClasses([.init(value: "ɕ", names: ["甲", "乙"])], characters: ["身", "𠀀"], mode: "聲母", colors: ["ɕ":"#123456"])
        XCTAssertEqual(csv.components(separatedBy: "#123456").count - 1, 2)
        XCTAssertTrue(csv.contains("身 𠀀")); XCTAssertTrue(csv.contains("\"甲\"")); XCTAssertTrue(csv.contains("\"乙\""))
    }
    func testReverseEvolutionExportsModernColumnFirst() {
        let group = EvolutionGroup(oldValue: "OLD", modernValue: "MODERN", chars: ["身"], readings: ["ɕiŋ1"], positions: [], subtypes: [])
        let csv = EvolutionExportDocument.csv(groups: [group], language: "甲", dimension: "聲母", mode: "聲母", reverse: true)
        XCTAssertTrue(csv.contains("\"MODERN\",\"OLD\""))
    }
    @MainActor func testPNGIncludesFullTallDiagramBeyondViewport() throws {
        let links = (0..<30).map { CorrespondenceLink(left: "a\($0)", right: "b\($0)", chars: ["身"]) }
        let png = SankeyImageExport.png(links: links, languages: ["甲", "乙"], mode: "聲母")
        XCTAssertEqual(Array(png.prefix(8)), [137,80,78,71,13,10,26,10])
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertGreaterThan(image.height, 1000)
        XCTAssertLessThanOrEqual(image.height, 8192)
    }
    func testMultiLanguageCSVAndSharedIntermediateNodeLayout() {
        let links = [CorrespondenceLink(left: "a", right: "b", chars: ["身", "中"]),
                     CorrespondenceLink(left: "b", right: "c", chars: ["身"], stage: 1),
                     CorrespondenceLink(left: "a", right: "b", chars: ["中"], stage: 1)]
        let csv = AnalysisCSV.correspondences(links, languages: ["甲", "乙", "丙"], mode: "聲母")
        XCTAssertTrue(csv.contains("\"甲\",\"乙\""))
        XCTAssertTrue(csv.contains("\"乙\",\"丙\""))
        XCTAssertEqual(Set(links.map(\.id)).count, 3)
        let layout = CorrespondenceLayout(links: Array(links.prefix(2)), languages: ["甲", "乙", "丙"])
        XCTAssertEqual(layout.nodes.filter { $0.column == 1 && $0.value == "b" }.count, 1)
        XCTAssertEqual(layout.bands.count, 2)
        XCTAssertTrue(layout.nodes.allSatisfy { $0.rect.maxX <= layout.size.width && $0.rect.maxY <= layout.size.height })
        let incoming = layout.bands[0].path.boundingBoxOfPath
        let outgoing = layout.bands[1].path.boundingBoxOfPath
        XCTAssertEqual(incoming.minY, outgoing.minY, accuracy: 0.01)
        XCTAssertGreaterThan(incoming.height, outgoing.height)
    }
    @MainActor func testMultiLanguagePNGIncludesAllColumns() throws {
        let links = (0..<3).flatMap { stage in
            [CorrespondenceLink(left: "ɕ", right: "ɕ", chars: ["身", "書", "詩"], stage: stage),
             CorrespondenceLink(left: "tɕ", right: "tɕ", chars: ["中"], stage: stage)]
        }
        let png = SankeyImageExport.png(links: links, languages: ["甲", "乙", "丙", "丁"], mode: "聲母")
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertGreaterThan(image.width, 2000)
        XCTAssertLessThanOrEqual(image.width, 8192)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "sankey-export.png"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testReadingBackgroundIsGrayInDarkModeAndRetainsLightColor() {
        let dark = MapReadingAppearance.background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(dark.getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(r, 0.30, accuracy: 0.01); XCTAssertEqual(r, g); XCTAssertEqual(g, b)
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(MapReadingAppearance.background.resolvedColor(with: lightTraits), AppTheme.surface.resolvedColor(with: lightTraits).withAlphaComponent(0.94))
    }
}
