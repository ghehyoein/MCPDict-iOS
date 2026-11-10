import XCTest

final class ToolsNavigationTests: XCTestCase {
    @MainActor func testArrangementAndBuiltInToolsBridge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["resultArrangementMenu"].waitForExistence(timeout: 15))
        app.buttons["resultArrangementMenu"].tap()
        app.buttons["呈橫向表格排列"].tap()
        app.textFields.firstMatch.tap()
        app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        XCTAssertTrue(app.scrollViews["dictionary-result-table"].waitForExistence(timeout: 10))
        app.buttons["resultArrangementMenu"].tap()
        app.buttons["呈縱向表格排列"].tap()
        XCTAssertTrue(app.scrollViews["dictionary-result-table"].exists)
        app.buttons["resultArrangementMenu"].tap()
        app.buttons["呈列排列"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "dictionary-reading-示例語言點").firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["工具"].tap()
        XCTAssertTrue(app.buttons["猜方言"].exists)
        XCTAssertTrue(app.buttons["猜字"].exists)
        app.buttons["字音比較"].tap()
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let input = app.textFields["compareCharacters"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap(); input.typeText("中输")
        let compare = app.buttons["runNativeAnalysis"]
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "中")).firstMatch.waitForExistence(timeout: 10))
        compare.tap()
        XCTAssertTrue(app.buttons["nativeComparisonMap"].waitForExistence(timeout: 15))
        let language = app.buttons["comparisonLanguage-示例語言點"]
        XCTAssertTrue(language.waitForExistence(timeout: 5)); language.tap()
        XCTAssertTrue(app.staticTexts["解析日誌"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["將該語言加入自選語言"].exists)
        app.buttons["完成"].tap()
        let status = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "comparisonStatus-")).firstMatch
        XCTAssertTrue(status.exists); status.tap()
        XCTAssertFalse(app.buttons["comparisonLanguage-示例語言點"].exists)
        status.tap()
        XCTAssertTrue(app.buttons["comparisonLanguage-示例語言點"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "0.10.3-native-tools"
        shot.lifetime = .keepAlways
        add(shot)
    }
    @MainActor func testCharacterRangesPreserveInputAndSynchronizeMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["resultArrangementMenu"].waitForExistence(timeout: 15))
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
