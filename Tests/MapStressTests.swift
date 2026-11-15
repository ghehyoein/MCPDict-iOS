import XCTest
import MapKit
import QuartzCore
import Darwin
@testable import MCPDictIOS

@MainActor private final class FrameProbe: NSObject {
    var intervals = [Double]()
    private var last: CFTimeInterval?
    @objc func frame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if let last { intervals.append(now - last) }
        last = now
    }
}

final class MapStressTests: XCTestCase {
    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
    @MainActor func testAllGeocodedPointsWithReadings() async throws {
        guard let fixture = Bundle(for: Self.self).url(forResource: "map-stress", withExtension: "json") else {
            throw XCTSkip("Generate the pinned full-catalog map fixture for this opt-in stress test")
        }
        let readings = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fixture))
        let catalogURL = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "BundledTables"))
        let catalog = try JSONDecoder().decode(TableCatalog.self, from: Data(contentsOf: catalogURL))
        let points = catalog.tables.compactMap { table -> DialectPoint? in
            guard let raw = readings[table.id] else { return nil }
            let parts = ToneDisplay.parts(raw, table: table, style: "baSheng", pitchStyle: "curve")
            guard var point = DialectPoint.make(table, grouping: .atlas, reading: parts.map { $0.base + $0.pitch + $0.tone }.joined()) else { return nil }
            point.toneParts = parts
            return point
        }
        XCTAssertGreaterThan(points.count, 2000)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        let map = CachedAccessibilityMapView(frame: window.bounds)
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(map)
        let coordinator = NativeDialectMap.Coordinator { _ in }
        map.delegate = coordinator
        window.makeKeyAndVisible()
        defer { map.delegate = nil; window.isHidden = true }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let before = footprint(), start = CACurrentMediaTime(), revision = UUID()
        coordinator.update(map, points: points, fit: 1, revision: revision)
        let updateSeconds = CACurrentMediaTime() - start
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let loaded = footprint()
        let probe = FrameProbe()
        let displayLink = CADisplayLink(target: probe, selector: #selector(FrameProbe.frame(_:)))
        displayLink.add(to: .main, forMode: .common)
        defer { displayLink.invalidate() }
        var peak = loaded, maxViews = 0
        for i in 0..<12 {
            let span = [40.0, 15, 5, 1][i % 4]
            map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 32 + Double(i % 3), longitude: 112 + Double(i % 4)), span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)), animated: true)
            coordinator.update(map, points: points, fit: 1, revision: revision)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            peak = max(peak, footprint())
            let views = map.annotations.compactMap { map.view(for: $0) as? LabelAnnotationView }
            maxViews = max(maxViews, views.count)
            XCTAssertTrue(views.allSatisfy { $0.readingView == nil }, "Idle labels must not allocate TextKit views")
        }
        displayLink.invalidate()
        XCTAssertEqual(map.annotations.count, points.count)
        let intervals = probe.intervals.sorted()
        XCTAssertFalse(intervals.isEmpty)
        let report: [String: Any] = ["points": points.count, "max_views": maxViews, "viewport_width": map.bounds.width,
            "update_seconds": updateSeconds, "before_bytes": before, "loaded_bytes": loaded, "peak_bytes": peak,
            "frames": intervals.count, "p95_gap_ms": intervals[Int(Double(intervals.count - 1) * 0.95)] * 1000,
            "max_gap_ms": (intervals.last ?? 0) * 1000, "gaps_over_50ms": intervals.filter { $0 > 0.05 }.count]
        print("MAP_STRESS " + String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
