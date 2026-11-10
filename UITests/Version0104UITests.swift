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
        XCTAssertTrue(app.buttons["子區"].waitForExistence(timeout: 5)); app.buttons["子區"].tap()
        XCTAssertTrue(app.buttons["newCustomSubgroup"].exists)
        app.buttons["newCustomSubgroup"].tap()
        app.alerts.textFields.firstMatch.typeText("孫區")
        app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["孫區"].waitForExistence(timeout: 5))
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
        app.buttons["interfaceLanguagePicker"].tap(); app.buttons["English"].tap()
        XCTAssertTrue(app.buttons["favoriteActionMenu"].waitForExistence(timeout: 5))
        let menu = app.buttons["favoriteActionMenu"]
        XCTAssertLessThan(app.frame.maxX - menu.frame.maxX, 60)
        let english = XCTAttachment(screenshot: app.screenshot()); english.name = "0.10.4-English-settings"; english.lifetime = .keepAlways; add(english)
    }
}
