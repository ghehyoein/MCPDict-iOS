import XCTest

final class Version0105UITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["生字本"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testNestedSelectionCopySwipeDeleteAndColorRow() {
        let app = launch()
        app.tabBars.buttons["生字本"].tap(); app.buttons["自選分區"].tap()
        app.buttons["新建"].tap(); app.alerts.textFields.firstMatch.typeText("可刪方案"); app.alerts.buttons["保存"].tap()
        let root = app.buttons["schemeEditor-可刪方案"]
        XCTAssertTrue(root.waitForExistence(timeout: 5)); root.swipeLeft()
        XCTAssertTrue(app.buttons["刪除"].waitForExistence(timeout: 5)); app.buttons["刪除"].tap()
        XCTAssertFalse(root.exists)
        app.buttons["schemeEditor-默認方案"].tap()
        let hex = app.textFields["customSchemeHex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        let colorTitle = app.staticTexts["方案顏色"].firstMatch
        XCTAssertEqual(hex.frame.midY, colorTitle.frame.midY, accuracy: 12)
        for title in ["甲", "乙"] {
            app.buttons["newCustomSubgroup"].tap(); app.alerts.textFields.firstMatch.typeText(title); app.alerts.buttons["保存"].tap()
        }
        app.buttons["editChildSchemes"].tap()
        app.buttons["selectChildScheme-默認方案－甲"].tap()
        app.buttons["selectChildScheme-默認方案－乙"].tap()
        app.buttons["複製"].tap()
        XCTAssertTrue(app.buttons["childScheme-默認方案－甲（副本）"].waitForExistence(timeout: 5))
        app.buttons["刪除"].tap()
        XCTAssertFalse(app.buttons["childScheme-默認方案－甲"].exists)
        XCTAssertFalse(app.buttons["childScheme-默認方案－乙"].exists)
        app.buttons["editChildSchemes"].tap()
        let child = app.buttons["childScheme-默認方案－甲（副本）"]
        child.swipeLeft(); XCTAssertTrue(app.buttons["刪除"].waitForExistence(timeout: 5)); app.buttons["刪除"].tap()
        XCTAssertFalse(child.exists)
        capture(app, "0.10.5-subgroup-color-and-copy")
        app.tabBars.buttons["設定"].tap(); app.buttons["讀音格式"].tap()
        XCTAssertTrue(app.buttons["readingFormat-mc_display"].waitForExistence(timeout: 5))
        capture(app, "0.10.5-reading-format-accents")
    }
    @MainActor func testNotebookCopyAndComparisonLanguageFilter() {
        let app = launch()
        app.tabBars.buttons["生字本"].tap(); app.buttons["chooseNotebooks"].tap()
        let manage = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "管理")).firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 5)); manage.tap(); app.buttons["複製"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "副本")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.tabBars.buttons["工具"].tap(); app.buttons["字音比較"].tap()
        let input = app.textFields["compareCharacters"]
        input.tap(); input.typeText("中输")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "中")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["runNativeAnalysis"].tap()
        let selector = app.buttons["comparisonLanguageSelection"]
        XCTAssertTrue(selector.waitForExistence(timeout: 15)); selector.tap()
        XCTAssertTrue(app.buttons["classificationPickerToggle"].waitForExistence(timeout: 5))
        let check = app.buttons["check-示例語言點"]
        XCTAssertTrue(check.waitForExistence(timeout: 5)); check.tap()
        app.buttons["finishLanguages"].tap()
        XCTAssertFalse(app.buttons["comparisonLanguage-示例語言點"].exists)
        selector.tap(); check.tap(); app.buttons["finishLanguages"].tap()
        let point = app.buttons["comparisonLanguage-示例語言點"]
        for _ in 0..<3 where !point.isHittable { app.swipeUp() }
        XCTAssertTrue(point.waitForExistence(timeout: 5)); point.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "解析日誌")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "0.10.5-comparison-language-details")
    }
    @MainActor func testCustomPaletteDisablesBaseSwitchAndSharesAcrossPages() {
        let app = launch()
        app.tabBars.buttons["生字本"].tap(); app.buttons["自選分區"].tap()
        app.buttons["schemeEditor-默認方案"].tap()
        app.buttons["check-示例語言點"].tap()
        app.tabBars.buttons["字典"].tap()
        app.buttons["dictionaryLanguageSelection"].tap()
        let toggle = app.switches["paletteSwitch"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertTrue(toggle.isEnabled)
        XCTAssertGreaterThan(app.buttons["customColorMenu"].frame.width, 55)
        app.buttons["customColorMenu"].tap(); app.buttons["默認方案"].tap()
        XCTAssertFalse(toggle.isEnabled)
        capture(app, "0.10.5-custom-palette-dictionary")
        app.tabBars.buttons["地圖"].tap()
        if !app.buttons["customColorMenu"].isHittable { app.buttons["mapLanguageSelection"].tap() }
        XCTAssertTrue(app.buttons["customColorMenu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["paletteSwitch"].isEnabled)
        app.buttons["customColorMenu"].tap(); app.buttons["關閉"].tap()
        XCTAssertTrue(app.switches["paletteSwitch"].isEnabled)
        app.tabBars.buttons["字典"].tap()
        if !app.buttons["customColorMenu"].isHittable { app.buttons["dictionaryLanguageSelection"].tap() }
        XCTAssertTrue(app.switches["paletteSwitch"].isEnabled)
        capture(app, "0.10.5-custom-palette-off")
        app.tabBars.buttons["設定"].tap()
        app.buttons["interfaceLanguagePicker"].tap(); app.buttons["English"].tap()
        app.tabBars.buttons.element(boundBy: 0).tap()
        if !app.buttons["customColorMenu"].isHittable { app.buttons["dictionaryLanguageSelection"].tap() }
        let menu = app.buttons["customColorMenu"]
        XCTAssertTrue(menu.isHittable)
        XCTAssertGreaterThan(menu.frame.width, 60)
        XCTAssertLessThan(menu.frame.maxX, app.frame.maxX)
        menu.tap(); app.buttons["Default scheme"].tap()
        XCTAssertFalse(app.switches["paletteSwitch"].isEnabled)
        capture(app, "0.10.5-custom-palette-English")
    }
}
