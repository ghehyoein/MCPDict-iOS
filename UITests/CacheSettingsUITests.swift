import XCTest

final class CacheSettingsUITests: XCTestCase {
    @MainActor func testGroupedMaintenanceAndCacheConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 15))
        app.tabBars.buttons["設定"].tap()
        let cache = app.buttons["cacheSettings"]
        for _ in 0..<10 where !cache.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)))
        }
        XCTAssertTrue(cache.isHittable)
        XCTAssertLessThan(app.buttons["recentDeletionsSettings"].frame.minY, cache.frame.minY)
        XCTAssertLessThan(cache.frame.minY, app.buttons["contactSettings"].frame.minY)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "grouped-maintenance-settings"; shot.lifetime = .keepAlways; add(shot)
        cache.tap()
        XCTAssertTrue(app.navigationBars["清理緩存"].waitForExistence(timeout: 5))
        app.buttons["clearCache"].tap()
        XCTAssertTrue(app.alerts["是否確認清理緩存？"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertFalse(app.staticTexts["緩存已清理"].exists)
        app.buttons["clearCache"].tap()
        app.alerts.buttons["清理緩存"].tap()
        XCTAssertTrue(app.staticTexts["緩存已清理"].waitForExistence(timeout: 5))
    }
}
