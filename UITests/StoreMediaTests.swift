import XCTest

final class StoreMediaTests: XCTestCase {
    @MainActor func testDictionary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
        func shot(_ name: String) {
            let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            item.name = name; item.lifetime = .keepAlways; add(item)
        }
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 120))
        Thread.sleep(forTimeInterval: 8)
        shot("home")
        let settings = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "設定")).firstMatch
        if settings.exists && settings.isHittable {
            settings.tap()
            let download = app.buttons["字表下載"]
            if download.waitForExistence(timeout: 6) {
                shot("settings")
                download.tap()
                Thread.sleep(forTimeInterval: 3)
                shot("tables")
            }
            app.terminate()
            app.launch()
        }
        field.tap()
        field.typeText("U+4E2D\n")
        Thread.sleep(forTimeInterval: 6)
        shot("dictionary")
    }
}