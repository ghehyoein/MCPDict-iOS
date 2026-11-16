import XCTest

final class AppearanceUITests: XCTestCase {
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func scrollSettings(_ app: XCUIApplication, towardTop: Bool) {
        // Drag in the Form gutter: a centered vertical swipe can be consumed by
        // the font sliders instead of scrolling the list.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: towardTop ? 0.3 : 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: towardTop ? 0.8 : 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    @MainActor private func setAppearance(_ title: String, in app: XCUIApplication) {
        app.tabBars.buttons["設定"].tap()
        for _ in 0..<6 where !app.buttons[title].isHittable { scrollSettings(app, towardTop: false) }
        XCTAssertTrue(app.buttons[title].isHittable); app.buttons[title].tap()
        for _ in 0..<4 { scrollSettings(app, towardTop: true) }
        XCTAssertTrue(app.buttons["讀音格式"].waitForExistence(timeout: 5))
    }
    @MainActor func testWarmLightAppearanceScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--multi-correspondence-fixture"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["設定"].waitForExistence(timeout: 15))
        setAppearance("淺色", in: app)
        capture(app, "light-settings")
        app.buttons["讀音格式"].tap()
        XCTAssertTrue(app.buttons["readingFormat-mandarin_display"].waitForExistence(timeout: 5))
        capture(app, "light-reading-formats")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["字典"].tap()
        let input = app.textFields.firstMatch
        input.tap(); input.typeText("中"); app.buttons["查詢"].tap()
        XCTAssertTrue(app.textViews["dictionaryHeadword"].waitForExistence(timeout: 8))
        capture(app, "light-dictionary")
        app.buttons["dictionaryLanguageSelection"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].waitForExistence(timeout: 5))
        capture(app, "light-language-selection")
        app.buttons["finishLanguages"].tap()
        app.tabBars.buttons["地圖"].tap()
        let mapInput = app.textFields["請輸入漢字"]
        XCTAssertTrue(mapInput.waitForExistence(timeout: 5))
        mapInput.tap(); mapInput.typeText("中"); app.buttons["查字"].tap()
        let reading = app.descendants(matching: .any)["map-reading-" + String(repeating: "a", count: 24)]
        XCTAssertTrue(reading.waitForExistence(timeout: 8))
        capture(app, "light-map")
        app.tabBars.buttons["工具"].tap()
        capture(app, "light-tools")
        setAppearance("深色", in: app)
        app.buttons["讀音格式"].tap()
        XCTAssertTrue(app.buttons["readingFormat-mandarin_display"].waitForExistence(timeout: 5))
        capture(app, "dark-reading-formats")
    }
    @MainActor func testLightPinnedHeaderStaysLight() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--long-results-fixture", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 15))
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        XCTAssertTrue(app.textViews["dictionaryHeadword"].waitForExistence(timeout: 8))
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["中"].isHittable)
        capture(app, "light-pinned-header")
        let source = try XCTUnwrap(app.screenshot().image.cgImage)
        let scale = CGFloat(source.width) / app.frame.width
        for point in [CGPoint(x: 20, y: 40), CGPoint(x: 20, y: app.navigationBars.firstMatch.frame.midY)] {
            let pixel = try XCTUnwrap(source.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1)))
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            XCTAssertTrue(rgba.prefix(3).allSatisfy { $0 > 200 }, "Light pinned header must not become black: \(rgba)")
        }
    }
}
