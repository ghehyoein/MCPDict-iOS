import XCTest

final class Version0102UITests: XCTestCase {
    @MainActor func testSettingsAndCustomSchemeColorEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 15))
        app.tabBars.buttons["設定"].tap()
        XCTAssertFalse(app.buttons["調值樣式"].exists)
        let glyph = app.buttons["glyphStandardPicker"]
        XCTAssertTrue(glyph.waitForExistence(timeout: 5)); glyph.tap()
        XCTAssertTrue(app.buttons["日本"].waitForExistence(timeout: 5)); app.buttons["日本"].tap()
        app.buttons["讀音格式"].tap()
        XCTAssertTrue(app.buttons["readingFormat-mandarin_display"].waitForExistence(timeout: 5))
        app.buttons["readingFormat-mandarin_display"].tap()
        app.buttons["readingFormat-mandarin_display-1"].tap()
        XCTAssertTrue(app.buttons["readingFormat-mandarin_display-0"].exists)
        XCTAssertTrue(app.buttons["readingFormat-mandarin_display-2"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.12)).tap()
        app.tabBars.buttons["生字本"].tap()
        app.buttons["自選分區"].tap()
        app.buttons["默認方案"].tap()
        let hex = app.textFields["customSchemeHex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.tap()
        let old = hex.value as? String ?? ""
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "#12ABEF")
        app.buttons["保存"].tap()
        XCTAssertEqual(hex.value as? String, "#12ABEF")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "0.10.2-自選分區顏色"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testGamesShareSingleSelectionAndLongTextIsIndependent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["工具"].waitForExistence(timeout: 15))
        app.tabBars.buttons["工具"].tap()
        app.buttons["猜字"].tap()
        app.buttons["gameLanguageSelection"].tap()
        XCTAssertFalse(app.buttons["自選"].exists)
        XCTAssertFalse(app.buttons["selectAllLanguages"].exists)
        for name in ["漢語", "官話", "北京"] {
            let group = app.buttons["expand-" + name]
            XCTAssertTrue(group.waitForExistence(timeout: 5)); group.tap()
        }
        app.buttons["check-示例語言點"].tap()
        app.buttons["finishLanguages"].tap()
        XCTAssertTrue(app.buttons["gameLanguageSelection"].label.contains("1"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["猜方言"].tap()
        XCTAssertTrue(app.buttons["gameLanguageSelection"].label.contains("1"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["長文注音"].tap()
        XCTAssertTrue(app.buttons["longTextLanguage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["longTextLanguage"].label.contains("0"))
    }
}
