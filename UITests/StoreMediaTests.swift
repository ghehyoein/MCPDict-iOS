import XCTest

final class StoreMediaTests: XCTestCase {
    @MainActor func testDictionary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 90))
        field.tap()
        field.typeText("中")
        let search = app.buttons["查詢"]
        let reference = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "dictionary-reading-")).firstMatch
        for _ in 0..<4 {
            search.tap()
            if reference.waitForExistence(timeout: 20) { break }
        }
        XCTAssertTrue(reference.exists, app.debugDescription)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "dictionary"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
