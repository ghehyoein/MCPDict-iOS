import XCTest

final class ToolsNavigationTests: XCTestCase {
    @MainActor func testArrangementAndBuiltInToolsBridge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["排列"].waitForExistence(timeout: 15))
        app.buttons["排列"].tap()
        app.buttons["arrangement-horizontal"].tap()
        app.buttons["完成"].tap()
        app.textFields.firstMatch.tap()
        app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        XCTAssertTrue(app.scrollViews["dictionary-result-table"].waitForExistence(timeout: 10))
        app.buttons["排列"].tap()
        app.buttons["arrangement-vertical"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.scrollViews["dictionary-result-table"].exists)
        app.buttons["排列"].tap()
        app.buttons["arrangement-list"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "dictionary-reading-示例語言點").firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["工具"].tap()
        XCTAssertTrue(app.buttons["猜方言"].exists)
        XCTAssertTrue(app.buttons["猜字"].exists)
        app.buttons["音典小工具"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        XCTAssertTrue(web.buttons["字音比較"].waitForExistence(timeout: 15))
        web.buttons["字音比較"].tap()
        let input = web.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap(); input.typeText("中输")
        web.buttons["字音比較"].tap()
        web.buttons["開始比較"].tap()
        XCTAssertTrue(web.staticTexts["各語言比較結果"].waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "0.10.1-built-in-tools"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
