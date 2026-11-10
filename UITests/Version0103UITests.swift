import XCTest

final class Version0103UITests: XCTestCase {
    @MainActor func testSchemeEditingAndGuessSubmissionControls() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixture","--reset-selection"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["生字本"].waitForExistence(timeout: 15)); app.tabBars.buttons["生字本"].tap()
        XCTAssertTrue(app.buttons["編輯"].exists); XCTAssertFalse(app.buttons["多選"].exists)
        app.buttons["自選分區"].tap()
        app.buttons["新建"].tap()
        app.alerts.textFields.firstMatch.typeText("測試方案")
        app.alerts.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["schemeEditor-測試方案"].waitForExistence(timeout: 5))
        app.buttons["編輯"].tap()
        app.buttons["selectScheme-測試方案"].tap()
        app.buttons["刪除"].tap()
        XCTAssertFalse(app.buttons["schemeEditor-測試方案"].exists)
        app.buttons["完成"].tap()
        app.tabBars.buttons["工具"].tap(); app.buttons["猜方言"].tap()
        XCTAssertTrue(app.buttons["gameSettings"].exists)
        XCTAssertFalse(app.staticTexts["出題模式"].exists)
        app.buttons["gameSettings"].tap()
        XCTAssertTrue(app.staticTexts["出題模式"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["出題"].tap()
        let instruction = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "根據指定漢字")).firstMatch
        XCTAssertTrue(instruction.waitForExistence(timeout: 5))
        app.buttons["gameLanguageSelection"].tap()
        XCTAssertFalse(app.buttons["clearLanguages"].exists); XCTAssertFalse(app.buttons["finishLanguages"].exists)
        XCTAssertFalse(app.buttons["submitGuessLanguage"].isEnabled)
        app.buttons["check-示例語言點"].tap()
        XCTAssertTrue(app.buttons["submitGuessLanguage"].isEnabled)
        let won = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "答對了！恭喜！")).firstMatch
        XCTAssertFalse(won.exists)
        app.buttons["submitGuessLanguage"].tap()
        app.buttons["gameLanguageSelection"].tap()
        XCTAssertTrue(won.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "0.10.3-guess-submit"; shot.lifetime = .keepAlways; add(shot)
    }
}
