import XCTest
import UIKit
@testable import MCPDictIOS

final class Version0107ExpansionTests: XCTestCase {
    func testHistoryLimitOrderingAndIndependentModes() {
        let name = "test-" + UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "queryHistory." + name) }
        for i in 0..<15 { QueryHistory.record(String(i), mode: .character, namespace: name) }
        XCTAssertEqual(QueryHistory.entries(name).count, 10)
        XCTAssertEqual(QueryHistory.entries(name).first?.query, "14")
        QueryHistory.record("12", mode: .character, namespace: name)
        XCTAssertEqual(QueryHistory.entries(name).first?.query, "12")
        QueryHistory.record("12", mode: .note, namespace: name)
        XCTAssertEqual(QueryHistory.entries(name).prefix(2).map(\.mode), [SearchMode.note.rawValue, SearchMode.character.rawValue])
        XCTAssertTrue(QueryHistory.entries(name + "other").isEmpty)
    }
    @MainActor func testMapLabelShrinksAndReadingsAreBelowName() {
        let point = DialectPoint(id: "x", name: "測試", longitude: 0, latitude: 0, color: "#112233", reading: "pa1")
        let view = LabelAnnotationView(annotation: nil, reuseIdentifier: "test")
        view.configure(point, fontSize: 16, labelSize: 25) {}
        let large = view.nameButton.frame
        view.configure(point, fontSize: 16, labelSize: 5) {}
        XCTAssertLessThan(view.nameButton.frame.width, large.width)
        XCTAssertLessThan(view.nameButton.frame.height, large.height)
        XCTAssertGreaterThanOrEqual(view.readingText.frame.minY, view.nameButton.frame.maxY)
    }
    func testBundledFontsAreRegistered() {
        for name in ["Voces-Regular", "Charis-Regular", "PlangothicP1", "PlangothicP2"] { XCTAssertNotNil(UIFont(name: name, size: 17), name) }
    }
}
