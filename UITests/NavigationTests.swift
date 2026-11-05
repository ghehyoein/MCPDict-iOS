import XCTest

final class NavigationTests: XCTestCase {
    @MainActor func testTreeSelectionBlankStartAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "漢字、U+4E2D 或原始讀音")
        app.tabBars.buttons["字表"].tap()
        app.buttons["downloadLanguageSelection"].tap()
        app.buttons["selectAllLanguages"].tap()
        app.buttons["downloadLanguageSelection"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].exists, "Only Done may close the dropdown")
        XCTAssertTrue(app.buttons["downloadTables"].isEnabled)
        for key in ["漢語", "官話", "北京"] {
            let expand = app.buttons["expand-" + key]
            XCTAssertTrue(expand.waitForExistence(timeout: 5))
            expand.tap()
            XCTAssertEqual(expand.value as? String, "expanded")
            XCTAssertTrue(app.buttons["downloadTables"].isHittable)
        }
        app.buttons["check-示例語言點"].tap()
        XCTAssertEqual(app.buttons["check-示例語言點"].value as? String, "unchecked")
        XCTAssertFalse(app.buttons["downloadTables"].isEnabled)
        XCTAssertTrue(app.buttons["finishLanguages"].exists)
        app.buttons.matching(identifier: "示例語言點").firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["完成"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["完成"].tap()
        app.tabBars.buttons["字典"].tap()
        app.buttons["dictionaryLanguageSelection"].tap()
        app.buttons["check-漢語"].tap()
        app.buttons["finishLanguages"].tap()
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 0"))
        app.buttons["dictionaryLanguageSelection"].tap()
        app.buttons["selectAllLanguages"].tap()
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        app.buttons["dictionaryLanguageSelection"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].exists)
        app.segmentedControls.buttons["行政區"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].exists)
        XCTAssertTrue(app.buttons["check-北京"].exists)
        XCTAssertFalse(app.buttons["expand-北京"].exists)
        app.segmentedControls.buttons["語言"].tap()
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        app.buttons["finishLanguages"].tap()
        XCTAssertFalse(app.buttons["finishLanguages"].exists)
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 1"))
        app.terminate(); app.launchArguments = ["--ui-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 1"))
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.buttons["元來是正體ɵɤ̞ɵ("].exists)
        let simplified = app.descendants(matching: .any).matching(identifier: "简体中文").firstMatch
        XCTAssertTrue(simplified.waitForExistence(timeout: 5)); simplified.tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["fontSizeSlider"].exists)
    }
    @MainActor func testMapModesRefreshOpenDropdownAndLongPressCopies() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.tabBars.buttons["地圖"].tap()
        app.buttons["mapLanguageSelection"].tap()
        XCTAssertFalse(app.buttons["check-漢語"].exists)
        app.buttons["expand-漢語"].tap(); app.buttons["expand-官話"].tap()
        XCTAssertTrue(app.buttons["check-北京"].exists)
        XCTAssertFalse(app.buttons["check-示例語言點"].exists)
        app.buttons["check-北京"].tap()
        app.segmentedControls.buttons["語言"].tap()
        XCTAssertTrue(app.buttons["mapLanguageSelection"].label.contains("已選 0"))
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "unchecked")
        app.buttons["selectAllLanguages"].tap()
        app.segmentedControls.buttons["自選"].tap()
        XCTAssertTrue(app.buttons["mapLanguageSelection"].label.contains("已選 0"))
        XCTAssertTrue(app.staticTexts["自選功能後續待更新，目前與語言模式相同"].exists)
        app.segmentedControls.buttons["行政區"].tap()
        XCTAssertTrue(app.buttons["check-北京"].exists)
        XCTAssertFalse(app.buttons["expand-北京"].exists)
        app.segmentedControls.buttons["分區"].tap()
        XCTAssertTrue(app.buttons["mapLanguageSelection"].label.contains("已選 1"))
        app.segmentedControls.buttons["語言"].tap()
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        app.buttons["finishLanguages"].tap()
        let input = app.textFields["請輸入單字"]
        input.tap(); input.typeText("中")
        app.buttons["查字"].tap()
        let reading = app.buttons["map-reading-" + String(repeating: "a", count: 24)]
        XCTAssertTrue(reading.waitForExistence(timeout: 10))
        reading.press(forDuration: 0.8)
        let status = app.staticTexts["mapPointStatus"]
        expectation(for: NSPredicate(format: "label == %@", "已複製到剪貼版"), evaluatedWith: status)
        waitForExpectations(timeout: 2)
        // Resolve a fresh accessibility element after the label changes. The simulator
        // can retain the toast snapshot while querying a cached XCUIElement.
        let restored = app.staticTexts.matching(identifier: "mapPointStatus").matching(NSPredicate(format: "label CONTAINS %@", "1 個語言點")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10), app.staticTexts["mapPointStatus"].debugDescription)

    }

}
