import XCTest

final class Version0104UITests: XCTestCase {
    @MainActor func testNestedSchemeEditorAndSettingsNavigation() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["生字本"].waitForExistence(timeout: 15))
        app.tabBars.buttons["生字本"].tap(); app.buttons["自選分區"].tap()
        app.buttons["schemeEditor-默認方案"].tap()
        app.buttons["newCustomSubgroup"].tap()
        app.alerts.textFields.firstMatch.typeText("子區")
        app.alerts.buttons["保存"].tap()
        let child = app.buttons["childScheme-默認方案－子區"]
        XCTAssertTrue(child.waitForExistence(timeout: 5)); child.tap()
        XCTAssertTrue(app.buttons["newCustomSubgroup"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.element(boundBy: 0).value as? String, "默認方案－子區")
        app.buttons["newCustomSubgroup"].tap()
        app.alerts.textFields.firstMatch.typeText("孫區")
        app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["childScheme-默認方案－子區－孫區"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["classificationPickerToggle"].exists)
        XCTAssertTrue(app.buttons["check-示例語言點"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "0.10.4-nested-scheme-language-tree"; shot.lifetime = .keepAlways; add(shot)
        app.tabBars.buttons["設定"].tap()
        app.buttons["字頭資料顯示"].tap()
        XCTAssertTrue(app.buttons["referenceField-Unicode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["完成"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["讀音格式"].exists)
        for _ in 0..<5 where !app.buttons["淺色"].isHittable { app.swipeUp() }
        app.buttons["淺色"].tap()
        for _ in 0..<5 where !app.buttons["讀音格式"].isHittable { app.swipeDown() }
        app.buttons["讀音格式"].tap()
        XCTAssertTrue(app.buttons["readingFormat-mandarin_display"].waitForExistence(timeout: 5))
        let light = XCTAttachment(screenshot: app.screenshot()); light.name = "0.10.4-reading-formats-light"; light.lifetime = .keepAlways; add(light)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<5 where !app.buttons["深色"].isHittable { app.swipeUp() }
        app.buttons["深色"].tap()
        for _ in 0..<5 where !app.buttons["讀音格式"].isHittable { app.swipeDown() }
        app.buttons["讀音格式"].tap()
        XCTAssertTrue(app.buttons["readingFormat-mandarin_display"].waitForExistence(timeout: 5))
        let dark = XCTAttachment(screenshot: app.screenshot()); dark.name = "0.10.4-reading-formats-dark"; dark.lifetime = .keepAlways; add(dark)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["interfaceLanguagePicker"].tap(); app.buttons["English"].tap()
        XCTAssertTrue(app.buttons["favoriteActionMenu"].waitForExistence(timeout: 5))
        let menu = app.buttons["favoriteActionMenu"]
        XCTAssertLessThan(app.frame.maxX - menu.frame.maxX, 60)
        let english = XCTAttachment(screenshot: app.screenshot()); english.name = "0.10.4-English-settings"; english.lifetime = .keepAlways; add(english)
    }
}
