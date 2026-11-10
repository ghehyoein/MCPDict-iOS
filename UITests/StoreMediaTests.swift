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
        let ready = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "輸入查詢內容")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 600), app.debugDescription)
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
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
            let dictionary = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "字典")).firstMatch
            if dictionary.exists { dictionary.tap() }
        }
        field.tap()
        field.typeText("U+4E2D\n")
        let result = app.buttons["加入生字本"].firstMatch
        _ = result.waitForExistence(timeout: 60)
        Thread.sleep(forTimeInterval: 2)
        shot("dictionary")
    }
}