import XCTest
import UIKit
import MapKit
@testable import MCPDictIOS

final class Version0107ExpansionTests: XCTestCase {
    func testRecentDeletionRetentionAndMembershipCapture() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecentDeletions(url: folder.appendingPathComponent("trash.json"))
        try store.add(DeletedCollection(date: Date().addingTimeInterval(-31 * 86400), title: "expired"))
        try store.prune(); XCTAssertTrue(store.items.isEmpty)
        var before = NotebookArchive()
        before.entries = [SavedReading(reading: Reading(id: 1, characters: "中", language: "test", pronunciation: "pa", note: ""))]
        var after = before; after.entries = []
        try store.capture(before: before, after: after)
        XCTAssertEqual(store.items.first?.notebook?.entries.count, 1)
        XCTAssertEqual(RecentDeletions(url: folder.appendingPathComponent("trash.json")).items.count, 1)
    }
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
    @MainActor func testUnchangedLargeMapKeepsAnnotationObjects() {
        let points = (0..<3000).map { i in
            DialectPoint(id: String(i), name: "點\(i)", longitude: 100 + Double(i % 100) / 10, latitude: 30 + Double(i / 100) / 10, color: "#112233", reading: "")
        }
        let map = MKMapView()
        let coordinator = NativeDialectMap.Coordinator { _ in }
        let revision = UUID()
        coordinator.update(map, points: points, fit: 0, revision: revision)
        let before = Set(map.annotations.map { ObjectIdentifier($0 as AnyObject) })
        for _ in 0..<10 { coordinator.update(map, points: points, fit: 0, revision: revision) }
        XCTAssertEqual(Set(map.annotations.map { ObjectIdentifier($0 as AnyObject) }), before)
        XCTAssertEqual(map.annotations.count, 3000)
    }
    func testBundledFontsAreRegistered() {
        for name in ["Charis-Regular", "PlangothicP1", "PlangothicP2"] { XCTAssertNotNil(UIFont(name: name, size: 17), name) }
    }
}
