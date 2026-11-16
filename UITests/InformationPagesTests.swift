import XCTest

final class InformationPagesTests: XCTestCase {
    @MainActor func testContactAndBundledAboutPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 15))
        app.tabBars.buttons["設定"].tap()
        let contact = app.buttons["contactSettings"]
        for _ in 0..<10 where !contact.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(contact.isHittable)
        contact.tap()
        XCTAssertTrue(app.textViews.containing(NSPredicate(format: "label CONTAINS %@", "1127851625")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews.containing(NSPredicate(format: "label CONTAINS %@", "https://ghehyoein.com/")).firstMatch.exists)
        capture(app, "contact-page")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["aboutSettings"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 8))
        XCTAssertTrue(web.links["osfans/MCPDict"].waitForExistence(timeout: 8))
        XCTAssertTrue(web.staticTexts["iOS 版說明"].exists)
        capture(app, "about-ios-introduction")
        for _ in 0..<4 where !web.staticTexts["漢字音典介紹"].isHittable { web.swipeUp() }
        XCTAssertTrue(web.staticTexts["漢字音典介紹"].isHittable)
        XCTAssertTrue(web.links["osfans/MCPDict · README"].exists)
        capture(app, "about-android-original")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
