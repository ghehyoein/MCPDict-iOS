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
    private func cacheDirectoryBytes() -> Int {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]) else { return 0 }
        var bytes = 0
        for case let file as URL in files {
            if let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]), values.isRegularFile == true {
                bytes += values.totalFileAllocatedSize ?? values.fileSize ?? 0
            }
        }
        return bytes
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
        let cacheBefore = cacheDirectoryBytes()
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
            "app_cache_before_bytes": cacheBefore, "app_cache_after_bytes": cacheDirectoryBytes(),
            "http_memory_cache_bytes": URLCache.shared.currentMemoryUsage, "http_disk_cache_bytes": URLCache.shared.currentDiskUsage,
            "frames": intervals.count, "p95_gap_ms": intervals[Int(Double(intervals.count - 1) * 0.95)] * 1000,
            "max_gap_ms": (intervals.last ?? 0) * 1000, "gaps_over_50ms": intervals.filter { $0 > 0.05 }.count]
        print("MAP_STRESS " + String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
        // Low-memory recovery must preserve every point and a native selection.
        let selected = try XCTUnwrap(map.annotations.compactMap { map.view(for: $0) as? LabelAnnotationView }.first {
            ($0.annotation as? NativeDialectMap.PointAnnotation)?.point.reading.isEmpty == false
        })
        let text = selected.readingText
        let fullText = text.text
        text.selectedRange = NSRange(location: 0, length: 1)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(map.annotations.count, points.count)
        XCTAssertTrue(selected.readingView === text)
        XCTAssertEqual(text.text, fullText)
        XCTAssertEqual(text.selectedRange.length, 1)
        coordinator.mapViewDidChangeVisibleRegion(map)
        for item in map.annotations(in: map.visibleMapRect) {
            guard let point = item.base as? NativeDialectMap.PointAnnotation,
                  let view = map.view(for: point) as? LabelAnnotationView else { continue }
            XCTAssertTrue(view.subviews.contains { !$0.isHidden }, "Visible labels must recover after memory pressure")
        }
    }
}
