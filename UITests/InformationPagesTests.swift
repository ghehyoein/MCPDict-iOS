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
        XCTAssertTrue(app.textViews.containing(NSPredicate(format: "label CONTAINS %@", "contact@ghehyoein.com")).firstMatch.exists)
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
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let related = app.buttons["relatedLinksSettings"]
        for _ in 0..<3 where !related.isHittable { app.swipeUp() }
        XCTAssertTrue(related.isHittable)
        related.tap()
        XCTAssertTrue(relatedLink(app, "方言相似度").waitForExistence(timeout: 5))
        let webEdition = relatedLink(app, "唯二網頁版")
        let miniApp = relatedLink(app, "汉字音典小程序")
        XCTAssertTrue(webEdition.isHittable)
        XCTAssertTrue(miniApp.isHittable)
        XCTAssertGreaterThan(miniApp.frame.minY, webEdition.frame.minY)
        capture(app, "related-links-top")
        let lastLink = relatedLink(app, "字海（叶典）")
        for _ in 0..<6 where !lastLink.isHittable { app.swipeUp() }
        XCTAssertTrue(lastLink.isHittable)
        XCTAssertTrue(relatedLink(app, "漢語多功能字庫").exists)
        capture(app, "related-links-bottom")
    }

    @MainActor private func relatedLink(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        // Linked UITextViews are exposed as Link on iOS 26; match by label
        // so the same check covers both accessibility representations.
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
