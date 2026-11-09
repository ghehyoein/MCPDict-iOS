import XCTest

final class CustomSelectionUITests: XCTestCase {
    @MainActor func testVisibilityMenusAndSharedCustomScheme() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
        app.launch()
        let menu = app.buttons["dictionaryLanguageSelection"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15)); menu.tap()
        let islands = app.buttons["visibility-方言島"]
        XCTAssertTrue(islands.waitForExistence(timeout: 5)); islands.tap()
        XCTAssertTrue(app.buttons["僅顯示"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["顯示"].exists)
        app.buttons["隱藏"].tap()
        islands.tap(); app.buttons["顯示"].tap()
        let history = app.buttons["visibility-歷史音"]
        history.tap(); app.buttons["僅顯示"].tap()
        history.tap(); app.buttons["顯示"].tap()
        app.buttons["自選"].tap()
        let create = app.buttons["newCustomScheme"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("測試 江淮")
        alert.buttons["保存"].tap()
        let scheme = app.buttons["customSchemePicker"]
        XCTAssertTrue(scheme.waitForExistence(timeout: 5))
        XCTAssertTrue(scheme.label.contains("測試－江淮"), scheme.label)
        let photo = XCTAttachment(screenshot: app.screenshot()); photo.name = "自選方案與三態篩選"; photo.lifetime = .keepAlways; add(photo)
        app.tabBars.buttons["地圖"].tap()
        let mapMenu = app.buttons["mapLanguageSelection"]
        XCTAssertTrue(mapMenu.waitForExistence(timeout: 5))
        if !scheme.exists { mapMenu.tap() }
        XCTAssertTrue(scheme.waitForExistence(timeout: 5))
        XCTAssertTrue(scheme.label.contains("測試－江淮"), scheme.label)
    }
}
