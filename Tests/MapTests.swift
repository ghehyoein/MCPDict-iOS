import XCTest
import WebKit
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
    @MainActor func testBundledMapRendersAndClearsPointsWithoutKey() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "MapWeb"))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let controller = UIViewController()
        controller.view = web
        let window = UIWindow(frame: web.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { web.stopLoading(); window.isHidden = true }
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        var loaded = false
        for _ in 0..<120 {
            if let ready = try? await web.evaluateJavaScript("typeof window.mapDiagnostic === 'function' && window.mapDiagnostic().loaded"), ready as? Bool == true { loaded = true; break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertTrue(loaded, "Bundled MapLibre must initialize in WKWebView")
        guard loaded else { return }
        let point: [String: Any] = ["id":"test","name":"廣州 </script>","longitude":113.26,"latitude":23.13,"color":"#008080","reading":"tung1"]
        _ = try await web.callAsyncJavaScript("window.updateMap(payload)", arguments: ["payload":["points":[point],"key":"","fit":0]], in: nil, in: .page)
        let count = try await web.evaluateJavaScript("window.mapDiagnostic().points")
        XCTAssertEqual(count as? Int, 1)
        _ = try await web.callAsyncJavaScript("window.updateMap(payload)", arguments: ["payload":["points":[],"key":"","fit":0]], in: nil, in: .page)
        let empty = try await web.evaluateJavaScript("window.mapDiagnostic().points")
        XCTAssertEqual(empty as? Int, 0)
    }
}
