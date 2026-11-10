import XCTest

final class Version0106UITests: XCTestCase {
    @MainActor func testLongTextKeepsRepeatedCharactersAndOpensChoices() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["工具"].waitForExistence(timeout: 15))
        app.tabBars.buttons["工具"].tap(); app.buttons["長文注音"].tap()
        let input = app.textViews["longTextInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("中\n中")
        app.buttons["longTextLanguage"].tap()
        XCTAssertTrue(app.buttons["check-示例語言點"].waitForExistence(timeout: 5))
        app.buttons["check-示例語言點"].tap(); app.buttons["finishLanguages"].tap()
        app.buttons["annotateLongText"].tap()
        let first = app.buttons["annotatedCharacter-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["annotatedCharacter-2"].exists)
        first.tap()
        XCTAssertTrue(app.navigationBars["中"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "0.10.6-long-text"; shot.lifetime = .keepAlways; add(shot)
    }
}
