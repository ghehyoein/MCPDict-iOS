import XCTest

final class NavigationTests: XCTestCase {
    @MainActor func testDictionaryResultSurvivesModeSwitchAndNotebookMultiselect() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        let ipa = app.descendants(matching: .any).matching(identifier: "dictionary-reading-示例語言點").firstMatch
        XCTAssertTrue(ipa.waitForExistence(timeout: 8))
        ipa.press(forDuration: 0.55)
        XCTAssertEqual(app.staticTexts["dictionaryCopyStatus"].label, "已複製到剪貼板")
        app.buttons["dictionaryLanguageSelection"].tap()
        app.segmentedControls.buttons["行政區"].tap()
        app.buttons["finishLanguages"].tap()
        XCTAssertTrue(ipa.exists)
        let star = app.buttons["加入生字本"].firstMatch
        if star.exists { star.tap(); app.buttons["全選"].tap(); app.buttons["完成"].tap() }
        app.tabBars.buttons["生字本"].tap()
        app.buttons["語言"].tap(); app.buttons["發音"].tap(); app.buttons["單字"].tap()
        app.buttons["多選"].tap(); app.buttons["全選"].tap()
        XCTAssertTrue(app.staticTexts["已選 1"].exists)
        XCTAssertTrue(app.staticTexts["發音 · tɕiɔŋ1"].exists)
    }
    @MainActor func testContributorGroupingDoesNotFollowColorTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.tabBars.buttons["字表"].tap()
        app.buttons["downloadLanguageSelection"].tap()
        let toggle = app.buttons["classificationPickerToggle"]
        toggle.tap()
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "維護人")
        toggle.tap()
        let blank = app.buttons["check-(無)"]
        let person = app.buttons["check-測試維護人"]
        XCTAssertTrue(blank.exists); XCTAssertTrue(person.exists)
        person.tap()
        app.segmentedControls.buttons["音典分區"].tap()
        XCTAssertEqual(person.value as? String, "checked")
        app.buttons["personRole-維護人"].tap()
        XCTAssertFalse(person.exists); XCTAssertTrue(blank.exists)
        app.buttons["personRole-錄入人"].tap()
        XCTAssertFalse(blank.exists)
        // Reset this persisted classification for other independent fixture launches.
        app.buttons["personRole-錄入人"].tap(); app.buttons["personRole-維護人"].tap()
        toggle.tap(); app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "地圖集二分區")
    }

    @MainActor func testThreeIndependentFontSliders() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.tabBars.buttons["設定"].tap()
        let map = app.sliders["mapSizeSlider"]
        let other = app.sliders["fontSizeSlider"]
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertTrue(other.exists)
        let reading = app.sliders["mapReadingSlider"]
        XCTAssertTrue(reading.exists)
        XCTAssertEqual(app.sliders.count, 3)
        defer { other.adjust(toNormalizedSliderPosition: 0.25); map.adjust(toNormalizedSliderPosition: 0.55); reading.adjust(toNormalizedSliderPosition: 0.55) }
        let oldReading = reading.value as? String
        let oldOther = other.value as? String
        map.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertEqual(other.value as? String, oldOther)
        XCTAssertEqual(reading.value as? String, oldReading)
        let mapValue = map.value as? String
        reading.adjust(toNormalizedSliderPosition: 0.35)
        XCTAssertEqual(map.value as? String, mapValue)
        other.adjust(toNormalizedSliderPosition: 0.6)
        XCTAssertEqual(map.value as? String, mapValue)
    }

    @MainActor func testTreeSelectionBlankStartAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "漢字、U+4E2D 或原始讀音")
        app.tabBars.buttons["字表"].tap()
        app.buttons["downloadLanguageSelection"].tap()
        app.buttons["selectAllLanguages"].tap()
        XCTAssertTrue(app.buttons["downloadTables"].isEnabled)
        for key in ["漢語", "官話", "北京"] {
            let expand = app.buttons["expand-" + key]
            XCTAssertTrue(expand.waitForExistence(timeout: 5))
            expand.tap()
            XCTAssertEqual(expand.value as? String, "expanded")
            XCTAssertTrue(app.buttons["downloadTables"].isHittable)
        }
        app.buttons["check-示例語言點"].tap()
        XCTAssertEqual(app.buttons["check-示例語言點"].value as? String, "unchecked")
        XCTAssertFalse(app.buttons["downloadTables"].isEnabled)
        XCTAssertTrue(app.buttons["finishLanguages"].exists)
        app.buttons.matching(identifier: "示例語言點").firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["完成"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["完成"].tap()
        app.tabBars.buttons["字典"].tap()
        XCTAssertFalse(app.segmentedControls.buttons["自選"].exists)
        app.buttons["dictionaryLanguageSelection"].tap()
        XCTAssertFalse(app.staticTexts["分區顏色"].exists)
        app.buttons["check-漢語"].tap()
        app.buttons["finishLanguages"].tap()
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 0"))
        app.buttons["dictionaryLanguageSelection"].tap()
        app.buttons["selectAllLanguages"].tap()
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        app.buttons["dictionaryLanguageSelection"].tap()
        XCTAssertFalse(app.buttons["finishLanguages"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["自選"].exists)
        app.buttons["dictionaryLanguageSelection"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].exists)
        app.segmentedControls.buttons["行政區"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].exists)
        XCTAssertTrue(app.buttons["check-北京"].exists)
        app.buttons["expand-北京"].tap()
        XCTAssertTrue(app.buttons["check-東城"].exists)
        XCTAssertFalse(app.buttons["expand-東城"].exists)
        XCTAssertFalse(app.buttons["check-示例街道"].exists)
        XCTAssertFalse(app.buttons["check-示例語言點"].exists)
        app.segmentedControls.buttons["語言"].tap()
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        app.buttons["finishLanguages"].tap()
        XCTAssertFalse(app.buttons["finishLanguages"].exists)
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 1"))
        app.terminate(); app.launchArguments = ["--ui-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 1"))
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.buttons["元來是正體ɵɤ̞ɵ("].exists)
        let simplified = app.descendants(matching: .any).matching(identifier: "简体中文").firstMatch
        XCTAssertTrue(simplified.waitForExistence(timeout: 5)); simplified.tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["fontSizeSlider"].exists)
    }
    @MainActor func testMapModesRefreshOpenDropdownAndLongPressCopies() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.tabBars.buttons["地圖"].tap()
        app.buttons["mapLanguageSelection"].tap()
        XCTAssertTrue(app.buttons["check-漢語"].exists)
        app.buttons["expand-漢語"].tap(); app.buttons["expand-官話"].tap()
        XCTAssertTrue(app.buttons["check-北京"].exists)
        XCTAssertFalse(app.buttons["check-示例語言點"].exists)
        app.buttons["check-北京"].tap()
        XCTAssertEqual(app.buttons["check-北京"].value as? String, "checked")
        app.buttons["check-漢語"].tap()
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        XCTAssertEqual(app.buttons["check-北京"].value as? String, "unchecked")
        XCTAssertFalse(app.buttons["selectAllLanguages"].exists)
        app.segmentedControls.buttons["語言"].tap()
        XCTAssertTrue(app.buttons["mapLanguageSelection"].label.contains("已選 0"))
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "unchecked")
        app.buttons["selectAllLanguages"].tap()
        app.segmentedControls.buttons["自選"].tap()
        XCTAssertTrue(app.buttons["mapLanguageSelection"].label.contains("已選 0"))
        XCTAssertTrue(app.staticTexts["自選功能後續待更新，目前與語言模式相同"].exists)
        app.segmentedControls.buttons["行政區"].tap()
        XCTAssertTrue(app.buttons["check-北京"].exists)
        app.buttons["expand-北京"].tap()
        XCTAssertTrue(app.buttons["check-東城"].exists)
        XCTAssertFalse(app.buttons["expand-東城"].exists)
        XCTAssertFalse(app.buttons["check-示例街道"].exists)
        XCTAssertFalse(app.buttons["check-示例語言點"].exists)
        app.segmentedControls.buttons["分區"].tap()
        XCTAssertTrue(app.buttons["mapLanguageSelection"].label.contains("已選 1"))
        app.segmentedControls.buttons["語言"].tap()
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        app.buttons["finishLanguages"].tap()
        let input = app.textFields["請輸入單字"]
        input.tap(); input.typeText("中")
        app.buttons["查字"].tap()
        let reading = app.buttons["map-reading-" + String(repeating: "a", count: 24)]
        XCTAssertTrue(reading.waitForExistence(timeout: 10))
        reading.press(forDuration: 0.8)
        XCTAssertEqual(reading.value as? String, "tɕiɔŋ1", "The native long press must write the actual reading to the pasteboard")
        // Resolve a fresh accessibility element after the label changes. The simulator
        // can retain the toast snapshot while querying a cached XCUIElement.
        let restored = app.staticTexts.matching(identifier: "mapPointStatus").matching(NSPredicate(format: "label CONTAINS %@", "1 個語言點")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10), app.staticTexts["mapPointStatus"].debugDescription)

        app.buttons["mapLanguageSelection"].tap()
        app.segmentedControls.buttons["自選"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].exists)
        // Dismiss from the input area without submitting a new lookup.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["finishLanguages"].exists)
        XCTAssertTrue(reading.exists, "Switching draft selections must retain the submitted map result")

    }

    @MainActor func testIndependentRootLevelsAndExclusiveRegions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--tree-fixture"]; app.launch()
        app.buttons["dictionaryLanguageSelection"].tap()
        app.segmentedControls.buttons["分區"].tap()
        let scroll = app.scrollViews["languageTreeScroll"]
        var previous: String?
        let rootX = app.buttons["check-吳語"].frame.minX
        for root in ["吳語", "歷史音", "民族語", "粵語"].sorted() {
            let checkbox = app.buttons["check-" + root]
            for _ in 0..<5 { if checkbox.isHittable { break }; scroll.swipeUp() }
            XCTAssertTrue(checkbox.isHittable)
            XCTAssertEqual(checkbox.frame.minX, rootX, accuracy: 2, "Every root must remain at depth zero")
            checkbox.tap()
            XCTAssertEqual(checkbox.value as? String, "checked")
            if let previous { XCTAssertEqual(app.buttons["check-" + previous].value as? String, "unchecked") }
            app.buttons["expand-" + root].tap()
            let child = app.buttons["check-" + root + "子區"]
            for _ in 0..<5 { if child.isHittable { break }; scroll.swipeUp() }
            XCTAssertTrue(child.isHittable, "Lazy rows must appear when scrolled into view")
            XCTAssertGreaterThan(child.frame.minX, rootX)
            previous = root
        }
    }

}
