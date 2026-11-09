import XCTest

final class AdditionalToolsUITests: XCTestCase {
    @MainActor func testLongTextAndReadingFormatSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["工具"].waitForExistence(timeout: 15))
        app.tabBars.buttons["工具"].tap()
        app.buttons["長文注音"].tap()
        let input = app.textViews["longTextInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("中\n中")
        app.buttons["longTextLanguage"].tap()
        let language = app.buttons["示例語言點"].firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 5)); language.tap()
        app.buttons["annotateLongText"].tap()
        XCTAssertTrue(app.buttons["annotatedCharacter-0"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["annotatedCharacter-2"].exists)
        app.buttons["annotatedCharacter-0"].tap()
        XCTAssertTrue(app.navigationBars["中"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "長文注音"; shot.lifetime = .keepAlways; add(shot)
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        app.buttons["讀音格式"].tap()
        app.buttons["readingFormat-mc_display"].tap()
        XCTAssertTrue(app.switches["readingFormat-mc_display-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["readingFormat-mc_display-1"].exists)
    }
    @MainActor func testDetailCustomLanguageButtonAndOnlineMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 15))
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        let online = app.buttons["onlineDictionaryMenu"]
        XCTAssertTrue(online.waitForExistence(timeout: 10))
        online.tap()
        XCTAssertTrue(app.buttons["onlineDictionary-zdic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onlineDictionary-chise"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12)).tap()
        let language = app.buttons["示例語言點"].firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 5)); language.tap()
        let add = app.buttons["tableCustomLanguage"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertEqual(add.label, "將該語言加入自選語言")
        add.tap()
        XCTAssertEqual(add.label, "將該語言移出自選語言")
    }
}
