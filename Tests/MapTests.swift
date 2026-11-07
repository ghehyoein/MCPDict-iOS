import XCTest
import MapKit
@testable import MCPDictIOS

final class MapTests: XCTestCase {
    func testCoordinateOrderAndValidation() {
        XCTAssertEqual(TableLocation.parse("113.26,23.13"), TableLocation(longitude: 113.26, latitude: 23.13))
        XCTAssertEqual(TableLocation.parse(" -73.5， 45.5 ")?.longitude, -73.5)
        for invalid in ["", "113", "a,23", "113,NaN", "181,23", "113,91", "1,2,3"] { XCTAssertNil(TableLocation.parse(invalid), invalid) }
    }
    @MainActor func testAutomaticMapFitLimitsDenseResultsAndKeepsSpreadOutPointsVisible() throws {
        func point(_ longitude: Double, _ latitude: Double) -> DialectPoint {
            DialectPoint(id: "\(longitude),\(latitude)", name: "點", longitude: longitude, latitude: latitude, color: "#008080", reading: "")
        }
        for viewport in [CGSize(width: 390, height: 700), CGSize(width: 700, height: 390)] {
            for latitude in [23.0, 45.0] {
                for points in [[point(113, latitude)], [point(113, latitude), point(113.01, latitude + 0.01)]] {
                    let rect = try XCTUnwrap(NativeDialectMap.Coordinator.automaticMapRect(points: points, viewport: viewport))
                    let north = MKMapPoint(x: rect.midX, y: rect.minY).coordinate
                    let south = MKMapPoint(x: rect.midX, y: rect.maxY).coordinate
                    let distance = CLLocation(latitude: north.latitude, longitude: north.longitude).distance(from: CLLocation(latitude: south.latitude, longitude: south.longitude))
                    XCTAssertEqual(distance, 500_000, accuracy: 5_000)
                    XCTAssertEqual(rect.width / rect.height, viewport.width / viewport.height, accuracy: 0.001)
                }
            }
            let points = [point(80, 22), point(130, 50)]
            let rect = try XCTUnwrap(NativeDialectMap.Coordinator.automaticMapRect(points: points, viewport: viewport))
            for item in points {
                XCTAssertTrue(rect.contains(MKMapPoint(CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude))))
            }
        }
        XCTAssertNil(NativeDialectMap.Coordinator.automaticMapRect(points: [], viewport: .zero))
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
    @MainActor func testMapNamesReadingsAndInterfaceUseIndependentSizes() throws {
        let suite = "map-font-test-" + UUID().uuidString
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }
        let point = DialectPoint(id: "a", name: "甲", longitude: 1, latitude: 2, color: "#008080", reading: "a1")
        let host = UIView()
        let label = LabelAnnotationView(annotation: nil, reuseIdentifier: nil)
        host.addSubview(label)
        func check(_ general: Double, _ map: Double, _ reading: Double) throws {
            XCTAssertEqual(store.double(forKey: AppTypography.interfaceKey), general)
            host.traitOverrides.preferredContentSizeCategory = general > 20 ? .accessibilityExtraExtraExtraLarge : .small
            label.configure(point, fontSize: store.double(forKey: AppTypography.readingKey), labelSize: store.double(forKey: AppTypography.mapKey)) {}
            let text = try XCTUnwrap(label.readingText.attributedText)
            let font = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
            XCTAssertEqual(label.nameButton.titleLabel?.font.pointSize, CGFloat(map))
            XCTAssertEqual(font.pointSize, CGFloat(reading))
        }
        store.set(14, forKey: AppTypography.interfaceKey)
        store.set(16, forKey: AppTypography.mapKey)
        store.set(5, forKey: AppTypography.readingKey)
        try check(14, 16, 5)
        store.set(26, forKey: AppTypography.interfaceKey)
        try check(26, 16, 5)
        store.set(25, forKey: AppTypography.mapKey)
        try check(26, 25, 5)
        store.set(19, forKey: AppTypography.readingKey)
        try check(26, 25, 19)
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
        let label = try XCTUnwrap(view as? LabelAnnotationView)
        XCTAssertFalse(label.readingText.isHidden)
        XCTAssertFalse(label.canShowCallout)
        label.nameButton.sendActions(for: .touchUpInside)
        XCTAssertLessThan(label.readingText.frame.minY, label.nameButton.frame.minY)
        XCTAssertNotNil(label.nameButton.backgroundColor)
        XCTAssertEqual(chosen, "gz")
        coordinator.update(map, points: [], fit: 0)
        XCTAssertTrue(map.annotations.isEmpty, "Clearing map filters must remove stale annotations")
    }
    @MainActor func testLongNoteKeepsAllTextInScrollableSelectableViewport() {
        let note = String(repeating: "完整注釋內容\n", count: 200)
        let point = DialectPoint(id: "long", name: "甲", longitude: 1, latitude: 2, color: "#008080", reading: note)
        let label = LabelAnnotationView(annotation: nil, reuseIdentifier: nil)
        label.configure(point, fontSize: 25) {}
        XCTAssertEqual(label.readingText.text, note)
        XCTAssertTrue(label.readingText.isSelectable)
        XCTAssertFalse(label.readingText.isEditable)
        XCTAssertTrue(label.readingText.isScrollEnabled)
        XCTAssertLessThanOrEqual(label.readingText.bounds.height, 180)
        XCTAssertGreaterThan(label.readingText.sizeThatFits(CGSize(width: 260, height: CGFloat.greatestFiniteMagnitude)).height, label.readingText.bounds.height)
    }

    func testMapNoteSearchKeepsEveryCompleteNote() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("notes.db")
        let db = try SQLiteConnection(url: url, readOnly: false)
        _ = try db.rows("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋)")
        for index in 0..<135 {
            _ = try db.rows("INSERT INTO langs VALUES (?,?,?,?)", ["中", "甲", "a", "needle " + String(repeating: "完整注釋", count: 30) + String(index)])
        }
        let repository = DictionaryRepository(); try await repository.open(url)
        let result = try await repository.mapSearch("needle", mode: .note, names: ["甲"])
        XCTAssertEqual(result.groups["中"]?["甲"]?.count, 135)
        XCTAssertTrue(result.groups["中"]?["甲"]?.last?.note.hasSuffix("134") == true)
    }

}
