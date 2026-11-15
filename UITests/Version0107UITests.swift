import XCTest

final class Version0107UITests: XCTestCase {
    @MainActor func testQueryHistorySelectionAndClear() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        let input = app.textFields["漢字、U+4E2D 或原始讀音"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap(); input.typeText("中")
        app.buttons["查詢"].tap()
        let selector = app.buttons["dictionaryLanguageSelection"]
        let originalGap = selector.frame.minY - input.frame.maxY
        input.tap()
        let history = app.buttons["history-dictionary-中"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertEqual(selector.frame.minY - input.frame.maxY, originalGap, accuracy: 2)
        XCTAssertTrue(history.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "dictionary-floating-history"; shot.lifetime = .keepAlways; add(shot)
        history.tap()
        XCTAssertEqual(input.value as? String, "中")
        input.tap(); app.buttons["刪除"].tap()
        XCTAssertTrue(app.alerts["是否確定刪除所有歷史記錄"].waitForExistence(timeout: 5))
        app.alerts.buttons["刪除"].tap()
        XCTAssertFalse(history.exists)
    }
    @MainActor func testMapHistoryFloatsAndDismissesWithoutMovingSelector() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["地圖"].waitForExistence(timeout: 15))
        app.tabBars.buttons["地圖"].tap()
        let input = app.textFields["請輸入漢字"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap(); input.typeText("好"); app.buttons["查字"].tap()
        let selector = app.buttons["mapLanguageSelection"]
        let gap = selector.frame.minY - input.frame.maxY
        input.tap()
        let history = app.buttons["history-map-好"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertEqual(selector.frame.minY - input.frame.maxY, gap, accuracy: 2)
        XCTAssertFalse(app.buttons["history-dictionary-中"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "map-floating-history"; shot.lifetime = .keepAlways; add(shot)
        // A tap above the dropdown dismisses it without operating the control underneath.
        app.segmentedControls.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(history.waitForNonExistence(timeout: 5))
        input.tap(); XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        XCTAssertEqual(input.value as? String, "好")
        XCTAssertTrue(history.waitForNonExistence(timeout: 5))
        input.tap(); XCTAssertTrue(history.waitForExistence(timeout: 5))
        let cell = app.cells.containing(.button, identifier: "history-map-好").firstMatch
        cell.swipeLeft()
        // Native List can complete a full swipe immediately, or reveal its action.
        if history.exists {
            // UICollectionView exposes its swipe action beside the cell, not inside it.
            let rowFrame = cell.frame
            let action = app.buttons.matching(NSPredicate(format: "label IN %@", ["刪除", "删除", "Delete"]))
                .allElementsBoundByIndex.first { $0.isHittable && abs($0.frame.midY - rowFrame.midY) < rowFrame.height / 2 }
            XCTAssertNotNil(action, app.debugDescription)
            action?.tap()
        }
        XCTAssertTrue(history.waitForNonExistence(timeout: 5))
    }
    @MainActor func testReadingMarkerHelpInDictionaryAndMap() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.buttons["readingMarkerHelp"].waitForExistence(timeout: 15))
        app.buttons["readingMarkerHelp"].tap()
        XCTAssertTrue(app.alerts.staticTexts["-為白讀標記，=為文讀標記，?為待考標記，*為俗字標記"].waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()
        app.tabBars.buttons["地圖"].tap()
        app.buttons["readingMarkerHelp"].tap()
        XCTAssertTrue(app.alerts.staticTexts["-為白讀標記，=為文讀標記，?為待考標記，*為俗字標記"].waitForExistence(timeout: 5))
        app.alerts.buttons["好"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "0.10.7-map-search-controls"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testNotebookWholeRowAndMap() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--notebook-list-fixture"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["生字本"].waitForExistence(timeout: 15))
        app.tabBars.buttons["生字本"].tap()
        app.buttons["編輯"].tap()
        let row = app.buttons["selectNotebookRow-好"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)).tap()
        XCTAssertTrue(app.textViews["已選 1"].waitForExistence(timeout: 5))
        app.buttons["notebookMap"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor func testSchemeWholeRowAndUnsavedColor() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["生字本"].waitForExistence(timeout: 15))
        app.tabBars.buttons["生字本"].tap(); app.buttons["自選分區"].tap()
        app.buttons["編輯"].tap()
        app.buttons["selectSchemeRow-默認方案"].tap()
        XCTAssertTrue(app.staticTexts["已選 1"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap(); app.buttons["schemeEditor-默認方案"].tap()
        let hex = app.textFields["customSchemeHex"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        let original = hex.value as? String ?? ""
        hex.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + "#123ABC")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["schemeEditor-默認方案"].tap()
        XCTAssertEqual(hex.value as? String, original)
        hex.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); hex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + "#123ABC")
        XCTAssertEqual(hex.value as? String, "#123ABC")
        app.buttons["saveCustomSchemeColor"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["schemeEditor-默認方案"].tap()
        XCTAssertEqual(hex.value as? String, "#123ABC")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "0.10.7-scheme-color"; shot.lifetime = .keepAlways; add(shot)
    }
}
