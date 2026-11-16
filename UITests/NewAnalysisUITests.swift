import XCTest

final class NewAnalysisUITests: XCTestCase {
    @MainActor func testNewNativeAnalysisEntrypoints() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture", "--multi-correspondence-fixture"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["工具"].waitForExistence(timeout: 15))
        app.tabBars.buttons["工具"].tap()
        app.buttons["多地對應"].tap()
        XCTAssertTrue(app.buttons["runAdditionalAnalysis"].waitForExistence(timeout: 5))
        app.buttons["runAdditionalAnalysis"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["additionalAnalysisError"].waitForExistence(timeout: 5))
        app.buttons["correspondenceLanguages"].tap()
        let choice = app.buttons["check-示例語言點"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        app.buttons["finishLanguages"].tap()
        app.buttons["runAdditionalAnalysis"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["correspondenceDiagram"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["additionalAnalysisError"].exists)
        app.buttons["correspondenceLanguages"].tap()
        for name in ["示例語言點乙", "示例語言點丙"] {
            let point = app.buttons["check-" + name]
            XCTAssertTrue(point.waitForExistence(timeout: 5)); point.tap()
        }
        app.buttons["finishLanguages"].tap()
        app.buttons["runAdditionalAnalysis"].tap()
        let chart = app.descendants(matching: .any)["correspondenceDiagram"]
        for _ in 0..<4 {
            if chart.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        let csv = app.buttons["exportAdditionalCSV"]
        for _ in 0..<4 where !csv.isHittable { app.swipeDown() }
        csv.tap()
        let share = app.descendants(matching: .any)["exportActivitySheet"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 15))
        let shareShot = XCTAttachment(screenshot: app.screenshot()); shareShot.name = "system-share-menu"; shareShot.lifetime = .keepAlways; add(shareShot)
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "關閉", "关闭"])).firstMatch
        if close.exists { close.tap() }
        else {
            let frame = share.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + 10)).press(forDuration: 0.1,
                thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: frame.maxY - 5)))
        }
        XCTAssertTrue(csv.waitForExistence(timeout: 10))
        app.buttons["exportSankeyImage"].tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Allow' OR label BEGINSWITH '允許' OR label BEGINSWITH '允许'")).firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }
        XCTAssertTrue(app.alerts.staticTexts["圖片已儲存至相簿"].waitForExistence(timeout: 30))
        app.alerts.buttons["好"].tap()
        let chartShot = XCTAttachment(screenshot: app.screenshot()); chartShot.name = "centered-sankey-cells"; chartShot.lifetime = .keepAlways; add(chartShot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["單字音類"].tap()
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("中")
        app.buttons["runAdditionalAnalysis"].tap()
        let palette = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "analysisColor-")).firstMatch
        for _ in 0..<5 {
            if palette.exists && palette.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(palette.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["analysisColorHex"].exists)
        palette.tap()
        let hex = app.textFields["analysisColorHex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.tap()
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (hex.value as? String ?? "").count) + "#123ABC")
        app.buttons["saveAnalysisColor"].tap()
        XCTAssertTrue(palette.waitForExistence(timeout: 5)); palette.tap()
        XCTAssertEqual(hex.value as? String, "#123ABC")
        hex.tap(); hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7) + "#AABBCC")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        palette.tap()
        XCTAssertEqual(hex.value as? String, "#123ABC")
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }
}
