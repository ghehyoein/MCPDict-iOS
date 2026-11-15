import XCTest
@testable import MCPDictIOS

final class CacheBudgetTests: XCTestCase {
    func testRepeatedResponsesStayWithinBudgetAndClear() async throws {
        CacheMaintenance.configure()
        let cache = URLCache.shared
        cache.removeAllCachedResponses()
        let data = Data(repeating: 65, count: 512 * 1024)
        for round in 0..<3 {
            for index in 0..<80 {
                let url = URL(string: "https://cache-test.invalid/\(round)/\(index)")!
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600", "Content-Type": "application/octet-stream"])!
                cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: URLRequest(url: url))
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            print("CACHE_BENCH round=\(round) offered_bytes=\((round + 1) * 80 * data.count) memory_bytes=\(cache.currentMemoryUsage) disk_bytes=\(cache.currentDiskUsage)")
            XCTAssertLessThanOrEqual(cache.currentMemoryUsage, CacheMaintenance.memoryBytes)
            XCTAssertLessThanOrEqual(cache.currentDiskUsage, CacheMaintenance.diskBytes)
        }
        CacheMaintenance.clear()
        XCTAssertEqual(cache.currentMemoryUsage, 0)
        XCTAssertEqual(cache.currentDiskUsage, 0)
    }
}
