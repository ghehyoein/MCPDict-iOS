import XCTest

final class NavigationTests: XCTestCase {
    @MainActor func testTreeSelectionBlankStartAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture"]; app.launch()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "漢字、U+4E2D 或原始讀音")
        app.tabBars.buttons["字表"].tap()
        app.buttons["check-漢語"].tap()
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
        XCTAssertFalse(app.buttons["完成"].exists)
        app.buttons["示例語言點"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.tabBars.buttons["字典"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "全部語言")).firstMatch.tap()
        app.buttons["check-漢語"].tap()
        app.buttons["finishLanguages"].tap()
        app.tabBars.buttons["設定"].tap()
        let simplified = app.descendants(matching: .any).matching(identifier: "简体中文").firstMatch
        XCTAssertTrue(simplified.waitForExistence(timeout: 5)); simplified.tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["fontSizeSlider"].exists)
    }
}

