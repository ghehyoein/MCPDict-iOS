import XCTest

final class NewAnalysisUITests: XCTestCase {
    @MainActor func testNewNativeAnalysisEntrypoints() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["工具"].waitForExistence(timeout: 15))
        app.tabBars.buttons["工具"].tap()
        app.buttons["兩地對應"].tap()
        XCTAssertTrue(app.buttons["runAdditionalAnalysis"].waitForExistence(timeout: 5))
        app.buttons["runAdditionalAnalysis"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["additionalAnalysisError"].waitForExistence(timeout: 5))
        for entry in ["correspondenceLeft", "correspondenceRight"] {
            app.buttons[entry].tap()
            let choice = app.buttons["check-示例語言點"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.tap()
            app.buttons["finishLanguages"].tap()
        }
        app.buttons["runAdditionalAnalysis"].tap()
        let chart = app.descendants(matching: .any)["correspondenceDiagram"]
        for _ in 0..<4 {
            if chart.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["單字音類"].tap()
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("中")
        app.buttons["runAdditionalAnalysis"].tap()
        XCTAssertTrue(app.buttons["在地圖上顯示"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }
}
