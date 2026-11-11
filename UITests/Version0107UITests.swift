import XCTest

final class Version0107UITests: XCTestCase {
    @MainActor func testNotebookWholeRowAndMap() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--notebook-list-fixture"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["生字本"].waitForExistence(timeout: 15))
        app.tabBars.buttons["生字本"].tap()
        app.buttons["編輯"].tap()
        let row = app.buttons["selectNotebookRow-好"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)).tap()
        XCTAssertTrue(app.staticTexts["已選 1"].waitForExistence(timeout: 5))
        app.buttons["notebookMap"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor func testSchemeWholeRowAndUnsavedColor() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["生字本"].waitForExistence(timeout: 15))
        app.tabBars.buttons["生字本"].tap(); app.buttons["自選分區"].tap()
        app.buttons["編輯"].tap()
        app.buttons["selectSchemeRow-默認方案"].tap()
        XCTAssertTrue(app.staticTexts["已選 1"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap(); app.buttons["schemeEditor-默認方案"].tap()
        let hex = app.textFields["customSchemeHex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        let original = hex.value as? String ?? ""
        hex.tap(); hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + "#123ABC")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["schemeEditor-默認方案"].tap()
        XCTAssertEqual(hex.value as? String, original)
        hex.tap(); hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + "#123ABC")
        app.buttons["保存"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["schemeEditor-默認方案"].tap()
        XCTAssertEqual(hex.value as? String, "#123ABC")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "0.10.7-scheme-color"; shot.lifetime = .keepAlways; add(shot)
    }
}
