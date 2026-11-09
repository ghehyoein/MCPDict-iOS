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
    @MainActor func testCharacterRangesPreserveInputAndSynchronizeMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["排列"].waitForExistence(timeout: 15))
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中输")
        app.buttons["查詢"].tap()
        let rangeButton = app.buttons["characterRangeButton"]
        XCTAssertTrue(rangeButton.waitForExistence(timeout: 10))
        rangeButton.tap()
        XCTAssertTrue(app.buttons["character-range-GY"].waitForExistence(timeout: 5))
        app.buttons["character-range-GY"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "中输")
        rangeButton.tap()
        XCTAssertTrue(app.buttons["character-range-GY"].isSelected)
        app.buttons["完成"].tap()
        app.tabBars.buttons["地圖"].tap()
        let mapInput = app.textFields.firstMatch
        XCTAssertTrue(mapInput.waitForExistence(timeout: 10))
        mapInput.tap(); mapInput.typeText("中输")
        app.buttons["查字"].tap()
        XCTAssertTrue(app.buttons["characterRangeButton"].waitForExistence(timeout: 10))
        app.buttons["characterRangeButton"].tap()
        XCTAssertTrue(app.buttons["character-range-GY"].isSelected)
        app.buttons["character-range-all"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(mapInput.value as? String, "中输")
        app.tabBars.buttons["字典"].tap()
        app.buttons["characterRangeButton"].tap()
        XCTAssertTrue(app.buttons["character-range-all"].isSelected)
        app.buttons["完成"].tap()
    }

}
