import XCTest

final class TableGuidanceUITests: XCTestCase {
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testWelcomeCancelAndRelaunchDoNotRepeatOrBlockNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--table-guidance-welcome", "--reset-guidance", "-appearance", "dark"]
        app.launch()
        let alert = app.alerts["字表下載指引"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        XCTAssertTrue(alert.buttons["下載所有字表"].exists)
        capture(app, name: "1.0.2-welcome-download-guidance")
        alert.buttons["取消"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-guidance" }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
    }
    @MainActor func testMonthlyReminderOpensDownloadsAndDoesNotRepeat() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--table-guidance-update", "--reset-guidance", "-appearance", "dark"]
        app.launch()
        let alert = app.alerts["字表更新提醒"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        capture(app, name: "1.0.2-monthly-catalog-reminder")
        alert.buttons["前往字表下載"].tap()
        XCTAssertTrue(app.navigationBars["字表下載"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.navigationBars["字表下載"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
