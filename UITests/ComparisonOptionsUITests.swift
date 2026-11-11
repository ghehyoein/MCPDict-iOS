import XCTest

final class ComparisonOptionsUITests: XCTestCase {
    @MainActor func testUnionUnitAndEditableCategoryColor() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["工具"].waitForExistence(timeout: 15))
        app.tabBars.buttons["工具"].tap(); app.buttons["字音比較"].tap()
        let input = app.textFields["compareCharacters"]
        input.tap(); input.typeText("中输輸")
        let traditional = app.buttons["comparisonChar-輸"]
        XCTAssertTrue(traditional.waitForExistence(timeout: 10))
        traditional.tap()
        app.buttons["addComparisonUnit"].tap()
        XCTAssertTrue(app.buttons["removeComparisonUnit-中＋输"].waitForExistence(timeout: 5))
        traditional.tap()
        app.buttons["runNativeAnalysis"].tap()
        let hex = app.textFields["comparisonColorHex-partial"]
        XCTAssertTrue(hex.waitForExistence(timeout: 15))
        for _ in 0..<4 where !hex.isHittable { app.swipeUp() }
        hex.tap()
        let value = hex.value as? String ?? ""
        hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count) + "#123ABC")
        app.buttons["saveComparisonColor-partial"].tap()
        XCTAssertEqual(hex.value as? String, "#123ABC")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "comparison-unit-color"; shot.lifetime = .keepAlways; add(shot)
        let map = app.buttons["nativeComparisonMap"]
        for _ in 0..<3 where !map.isHittable { app.swipeUp() }
        map.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
    }
}
