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
        for id in ["exportAdditionalCSV", "exportSankeyImage"] {
            let export = app.buttons[id]
            for _ in 0..<4 where !export.isHittable { app.swipeDown() }
            XCTAssertTrue(export.exists); export.tap()
            // The iOS 26 document picker exposes a hidden SwiftUI "Cancel"
            // element over its options menu. Exercise the actual Save action.
            let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "儲存", "存储"])).firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 30)); save.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 15), .completed)
        }
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
