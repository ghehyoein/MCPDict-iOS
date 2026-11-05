import XCTest

final class NavigationTests: XCTestCase {
    @MainActor func testDeepTableActionsDetailsAndScriptSwitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture"]
        app.launch()
        app.tabBars.buttons["字表"].tap()
        XCTAssertTrue(app.buttons["downloadTables"].waitForExistence(timeout: 10))
        for title in ["漢語", "官話", "北京"] {
            app.staticTexts[title].firstMatch.tap()
            XCTAssertTrue(app.buttons["downloadTables"].isHittable)
            XCTAssertTrue(app.buttons["removeTables"].isHittable)
        }
        app.buttons["示例語言點"].tap()
        XCTAssertTrue(app.staticTexts["測試維護人"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.tabBars.buttons["設定"].tap()
        let simplified = app.descendants(matching: .any).matching(identifier: "简体中文").firstMatch
        XCTAssertTrue(simplified.waitForExistence(timeout: 5))
        simplified.tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        app.tabBars.buttons["字表"].tap()
        XCTAssertEqual(app.buttons["downloadTables"].label, "字表下载")
        XCTAssertEqual(app.buttons["removeTables"].label, "字表移除")
    }
}

