import XCTest
import MapKit
@testable import MCPDictIOS

final class MapTests: XCTestCase {
    func testCoordinateOrderAndValidation() {
        XCTAssertEqual(TableLocation.parse("113.26,23.13"), TableLocation(longitude: 113.26, latitude: 23.13))
        XCTAssertEqual(TableLocation.parse(" -73.5， 45.5 ")?.longitude, -73.5)
        for invalid in ["", "113", "a,23", "113,NaN", "181,23", "113,91", "1,2,3"] { XCTAssertNil(TableLocation.parse(invalid), invalid) }
    }
    func testMapQueryDoesNotStopAtOneHundred() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("map.db")
        let db = try SQLiteConnection(url: file, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋)")
        for index in 0..<135 { _ = try db.rows("INSERT INTO langs VALUES (?,?,?,?)", ["中 忠", "點\(index)", "zhong1", ""]) }
        let repo = DictionaryRepository()
        try await repo.open(file)
        let result = try await repo.mapReadings("中")
        XCTAssertEqual(result.count, 135)
        XCTAssertEqual(result["點134"], "zhong1")
        do { _ = try await repo.mapReadings("中國"); XCTFail("Must reject multiple characters") } catch { }
    }
    @MainActor func testSystemMapUpdatesCoordinatesReadingsAndSelection() throws {
        var chosen: String?
        let coordinator = NativeDialectMap.Coordinator { chosen = $0 }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        map.delegate = coordinator
        let point = DialectPoint(id: "gz", name: "廣州", longitude: 113.26, latitude: 23.13, color: "#008080", reading: "tung1")
        coordinator.update(map, points: [point], fit: 0)
        XCTAssertEqual(map.annotations.count, 1)
        let annotation = try XCTUnwrap(map.annotations.first as? NativeDialectMap.PointAnnotation)
        XCTAssertEqual(annotation.coordinate.longitude, 113.26)
        XCTAssertEqual(annotation.coordinate.latitude, 23.13)
        XCTAssertEqual(annotation.subtitle, "tung1")
        let view = try XCTUnwrap(coordinator.mapView(map, viewFor: annotation) as? MKAnnotationView)
        XCTAssertNil(view.clusteringIdentifier)
        XCTAssertEqual(view.displayPriority, .required)
        XCTAssertEqual(view.centerOffset, .zero)
        coordinator.mapView(map, annotationView: view, calloutAccessoryControlTapped: UIButton())
        XCTAssertEqual(chosen, "gz")
        coordinator.update(map, points: [], fit: 0)
        XCTAssertTrue(map.annotations.isEmpty, "Clearing map filters must remove stale annotations")
    }
}
