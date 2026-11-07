import XCTest
import UIKit

final class NavigationTests: XCTestCase {
    @MainActor func testDictionaryResultSurvivesModeSwitchAndNotebookSingleCategory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        let ipa = app.descendants(matching: .any).matching(identifier: "dictionary-reading-示例語言點").firstMatch
        XCTAssertTrue(ipa.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["dictionaryCopyStatus"].exists)
        app.buttons["dictionaryLanguageSelection"].tap()
        app.segmentedControls.buttons["行政區"].tap()
        app.buttons["check-北京"].tap()
        app.buttons["finishLanguages"].tap()
        XCTAssertTrue(ipa.waitForExistence(timeout: 8))
        let star = app.buttons["加入生字本"].firstMatch
        if star.exists { star.tap(); app.buttons["全選"].tap(); app.buttons["完成"].tap() }
        app.tabBars.buttons["生字本"].tap()
        app.segmentedControls.buttons["發音"].tap()
        XCTAssertTrue(app.scrollViews["notebookChoiceBar"].exists)
        XCTAssertTrue(app.buttons["tɕiɔŋ1"].exists)
        app.segmentedControls.buttons["隱藏"].tap()
        XCTAssertFalse(app.scrollViews["notebookChoiceBar"].exists)
        app.buttons["多選"].tap(); app.buttons["全選"].tap()
        XCTAssertTrue(app.staticTexts["已選 1"].exists)
    }
    @MainActor func testContributorGroupingDoesNotFollowColorTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.tabBars.buttons["設定"].tap(); app.buttons["字表下載"].tap()
        XCTAssertFalse(app.buttons["downloadLanguageSelection"].exists)
        let toggle = app.buttons["classificationPickerToggle"]
        chooseClassification(app, "維護人")
        let blank = app.buttons["check-(無)"]
        let person = app.buttons["check-測試維護人"]
        XCTAssertTrue(blank.exists); XCTAssertTrue(person.exists)
        person.tap()
        app.switches["paletteSwitch"].tap()
        XCTAssertEqual(person.value as? String, "checked")
        app.buttons["personRole-維護人"].tap()
        XCTAssertFalse(person.exists); XCTAssertTrue(blank.exists)
        app.buttons["personRole-錄入人"].tap()
        XCTAssertFalse(blank.exists)
        // Reset this persisted classification for other independent fixture launches.
        app.buttons["personRole-錄入人"].tap(); app.buttons["personRole-維護人"].tap()
        chooseClassification(app, "行政區劃")
        app.buttons["expand-北京"].tap()
        XCTAssertTrue(app.buttons["check-東城"].exists)
        XCTAssertFalse(app.buttons["expand-東城"].exists)
        XCTAssertFalse(app.buttons["check-示例街道"].exists)
        XCTAssertFalse(app.buttons["check-示例語言點"].exists)
        chooseClassification(app, "地圖集二分區")
    }

    @MainActor func testThreeIndependentFontSliders() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.tabBars.buttons["設定"].tap()
        let map = app.sliders["mapSizeSlider"]
        let other = app.sliders["fontSizeSlider"]
        for _ in 0..<4 {
            if other.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.7)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        }
        XCTAssertTrue(map.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(other.exists)
        let reading = app.sliders["mapReadingSlider"]
        XCTAssertTrue(reading.exists)
        XCTAssertEqual(app.sliders.count, 3)
        defer { other.adjust(toNormalizedSliderPosition: 0.25); map.adjust(toNormalizedSliderPosition: 0.55); reading.adjust(toNormalizedSliderPosition: 0.55) }
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = "字體大小內置預覽"; picture.lifetime = .keepAlways; add(picture)
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
        app.tabBars.buttons["設定"].tap(); app.buttons["字表下載"].tap()
        XCTAssertFalse(app.buttons["downloadLanguageSelection"].exists)
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
        XCTAssertFalse(app.buttons["finishLanguages"].exists)
        XCTAssertEqual(app.staticTexts["downloadState-" + String(repeating: "a", count: 24)].label, "已下載")
        app.buttons.matching(identifier: "示例語言點").firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["完成"].waitForExistence(timeout: 5))
        let vanished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars.buttons["完成"])
        XCTAssertEqual(XCTWaiter.wait(for: [vanished], timeout: 1.5), .timedOut)
        app.navigationBars.buttons["完成"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
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
        XCTAssertFalse(app.buttons["finishLanguages"].exists, app.debugDescription)
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
        XCTAssertFalse(app.buttons["finishLanguages"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 1"))
        app.terminate(); app.launchArguments = ["--ui-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 1"))
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.buttons["元來是正體ɵɤ̞ɵ("].exists)
        let simplified = app.descendants(matching: .any).matching(identifier: "简体中文").firstMatch
        XCTAssertTrue(simplified.waitForExistence(timeout: 5)); simplified.tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        for _ in 0..<3 { if app.sliders["fontSizeSlider"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.sliders["fontSizeSlider"].exists)
    }
    @MainActor func testMapModesRefreshOpenDropdownAndSelectableText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.tabBars.buttons["地圖"].tap()
        app.buttons["mapLanguageSelection"].tap()
        app.segmentedControls.buttons["分區"].tap()
        XCTAssertTrue(app.buttons["check-漢語"].exists)
        app.buttons["expand-漢語"].tap(); app.buttons["expand-官話"].tap()
        XCTAssertTrue(app.buttons["check-北京"].exists)
        XCTAssertFalse(app.buttons["check-示例語言點"].exists)
        app.buttons["check-北京"].tap()
        XCTAssertEqual(app.buttons["check-北京"].value as? String, "checked")
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "mixed")
        XCTAssertEqual(app.buttons["check-官話"].value as? String, "mixed")
        app.buttons["check-漢語"].tap()
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        XCTAssertEqual(app.buttons["check-北京"].value as? String, "unchecked")
        XCTAssertFalse(app.buttons["selectAllLanguages"].exists)
        app.segmentedControls.buttons["語言"].tap()
        XCTAssertTrue(app.buttons["mapLanguageSelection"].label.contains("已選 1"))
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
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
        let input = app.textFields["請輸入漢字"]
        input.tap(); input.typeText("中")
        app.buttons["查字"].tap()
        let reading = app.textViews["map-reading-" + String(repeating: "a", count: 24)]
        XCTAssertTrue(reading.waitForExistence(timeout: 10))
        XCTAssertTrue(reading.isHittable)
        let restored = app.textViews.matching(identifier: "mapPointStatus").matching(NSPredicate(format: "label CONTAINS %@", "1 個語言點")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10), app.textViews["mapPointStatus"].debugDescription)

        let labelFrame = reading.frame
        app.buttons["mapLanguageSelection"].tap()
        XCTAssertEqual(reading.frame.midY, labelFrame.midY, accuracy: 1)
        XCTAssertEqual(reading.frame.midX, labelFrame.midX, accuracy: 1)
        app.segmentedControls.buttons["自選"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].exists)
        // The floating menu covers the search bar. Tap the map below the menu.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.83)).tap()
        XCTAssertFalse(app.buttons["finishLanguages"].exists, app.debugDescription)
        XCTAssertTrue(reading.exists, "Switching draft selections must retain the submitted map result")

    }

    @MainActor func testUnicodeReferenceAndMapHandoff() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("一中")
        app.buttons["查詢"].tap()
        let unicode = app.textViews["characterUnicode"]
        XCTAssertTrue(unicode.waitForExistence(timeout: 8))
        app.buttons["更多字形資料"].tap()
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "label CONTAINS %@", "基本 1.1")).firstMatch.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.15)).tap()
        XCTAssertFalse(app.staticTexts["dictionaryCopyStatus"].exists)
        if app.navigationBars.buttons["完成"].exists { app.navigationBars.buttons["完成"].tap() }
        app.buttons["說文"].tap()
        XCTAssertTrue(app.navigationBars["說文"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["完成"].tap()
        app.buttons["中"].tap()
        app.buttons["characterMap"].tap()
        XCTAssertTrue(app.tabBars.buttons["地圖"].isSelected)
        let mark = app.textViews["map-reading-" + String(repeating: "a", count: 24)]
        XCTAssertTrue(mark.waitForExistence(timeout: 8))
        XCTAssertEqual(mark.label, "tɕiɔŋ1")
    }

    @MainActor func testMapSearchModeControlsAndVariantResults() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]; app.launch()
        app.tabBars.buttons["地圖"].tap()
        let menu = app.buttons["mapLanguageSelection"]
        menu.tap(); app.segmentedControls.buttons["語言"].tap()
        app.buttons["selectAllLanguages"].tap(); app.buttons["finishLanguages"].tap()
        func query(_ hint: String, _ value: String) {
            let field = app.textFields[hint]
            field.tap(); field.typeText(value); app.buttons["查字"].tap()
        }
        let mark = app.textViews["map-reading-" + String(repeating: "a", count: 24)]
        query("請輸入漢字", "中输")
        XCTAssertTrue(app.buttons["輸"].waitForExistence(timeout: 8))
        app.buttons["輸"].tap()
        XCTAssertEqual(mark.label, "su1")
        app.segmentedControls.buttons["讀音"].tap()
        XCTAssertEqual(mark.label, "su1")
        app.buttons["清除"].tap()
        query("請輸入讀音", "u1")
        XCTAssertTrue(mark.waitForExistence(timeout: 8))
        XCTAssertTrue(mark.label.contains("输") && mark.label.contains("輸"))
        app.segmentedControls.buttons["註釋"].tap()
        app.buttons["清除"].tap()
        query("請輸入註釋", "運送貨物的完整註釋")
        XCTAssertTrue(app.buttons["輸"].waitForExistence(timeout: 8))
        app.buttons["輸"].tap()
        XCTAssertEqual(mark.label, "su1  運送貨物的完整註釋")
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

    @MainActor func testFinishQueriesAndNewNotebookUsesAlert() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["dictionaryLanguageSelection"].tap()
        app.buttons["selectAllLanguages"].tap(); app.buttons["finishLanguages"].tap()
        XCTAssertTrue(app.textViews["dictionaryHeadword"].waitForExistence(timeout: 8))
        app.tabBars.buttons["生字本"].tap()
        app.buttons["chooseNotebooks"].tap()
        app.buttons["新建生字表"].tap()
        let alert = app.alerts["新建生字表"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let title = "測試表-" + String(UUID().uuidString.prefix(6))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText(String(title))
        alert.buttons["儲存"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", String(title))).firstMatch.waitForExistence(timeout: 3))
        app.navigationBars.buttons["完成"].tap()
        app.tabBars.buttons["地圖"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["漢字"].isHittable)
        XCTAssertTrue(app.segmentedControls.buttons["讀音"].isHittable)
        XCTAssertTrue(app.segmentedControls.buttons["註釋"].isHittable)
        app.textFields["請輸入漢字"].tap(); app.textFields["請輸入漢字"].typeText("中")
        app.buttons["mapLanguageSelection"].tap(); app.segmentedControls.buttons["語言"].tap()
        XCTAssertTrue(app.buttons["selectAllLanguages"].isHittable)
        XCTAssertTrue(app.buttons["finishLanguages"].isHittable)
        app.buttons["selectAllLanguages"].tap(); app.buttons["finishLanguages"].tap()
        XCTAssertTrue(app.textViews["map-reading-" + String(repeating: "a", count: 24)].waitForExistence(timeout: 8))
    }
    @MainActor func testPinnedHeaderPreservesInputAndLanguageMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--long-results-fixture"]; app.launch()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        XCTAssertTrue(app.textViews["dictionaryHeadword"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields.firstMatch.isHittable)
        app.buttons["dictionaryLanguageSelection"].tap()
        XCTAssertTrue(app.buttons["finishLanguages"].isHittable)
        app.buttons["finishLanguages"].tap()
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["中"].isHittable)
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = "滾動後固定選字區及頂部遮罩"; picture.lifetime = .keepAlways; add(picture)
        let image = app.screenshot().image
        let source = try XCTUnwrap(image.cgImage)
        let pixelScale = CGFloat(source.width) / app.frame.width
        for point in [CGPoint(x: 20, y: 40), CGPoint(x: 20, y: app.navigationBars.firstMatch.frame.midY)] {
            let pixel = try XCTUnwrap(source.cropping(to: CGRect(x: point.x * pixelScale, y: point.y * pixelScale, width: 1, height: 1)))
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            XCTAssertTrue(rgba.prefix(3).allSatisfy { $0 < 40 }, "Pinned header top must be black: \(rgba)")
        }
    }

    @MainActor func testSelectorsChangeOnlyAfterSubmittedQuery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.segmentedControls.buttons["註釋"].tap()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("输")
        XCTAssertFalse(app.scrollViews["noteInputVariants"].exists)
        app.buttons["查詢"].tap()
        XCTAssertTrue(app.scrollViews["noteInputVariants"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["輸"].exists)
        app.segmentedControls.buttons["漢字"].tap()
        XCTAssertTrue(app.scrollViews["noteInputVariants"].exists)
        app.buttons["查詢"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.scrollViews["noteInputVariants"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    @MainActor func testDownloadsPushAndReferenceOptionsSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        app.tabBars.buttons["設定"].tap(); app.buttons["字表下載"].tap()
        XCTAssertTrue(app.buttons["selectAllLanguages"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["downloadLanguageSelection"].exists)
        XCTAssertFalse(app.navigationBars.buttons["完成"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["字頭資料顯示"].tap()
        XCTAssertTrue(app.navigationBars["字頭資料顯示"].waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "referenceField-Unicode").firstMatch.tap()
        app.buttons["不顯示"].tap()
        app.navigationBars.buttons["完成"].tap()
        app.tabBars.buttons["字典"].tap()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        XCTAssertTrue(app.textViews["dictionaryHeadword"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textViews["characterUnicode"].exists, app.debugDescription)
    }

    @MainActor private func chooseClassification(_ app: XCUIApplication, _ value: String) {
        app.descendants(matching: .any).matching(identifier: "classificationPickerToggle").firstMatch.tap()
        app.buttons[value].tap()
        if app.navigationBars["分類方式"].exists { app.navigationBars.buttons.firstMatch.tap() }
    }
    @MainActor func testSharedLanguageStateAndIndependentDownloads() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        app.buttons["dictionaryLanguageSelection"].tap()
        app.buttons["clearLanguages"].tap()
        app.switches["paletteSwitch"].tap()
        app.segmentedControls.buttons["分區"].tap()
        XCTAssertEqual(app.segmentedControls["regionClassification"].buttons.count, 2)
        app.buttons["check-漢語"].tap()
        app.tabBars.buttons["地圖"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["分區"].isSelected)
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        XCTAssertEqual(app.switches["paletteSwitch"].value as? String, "1")
        app.buttons["finishLanguages"].tap()
        app.tabBars.buttons["設定"].tap(); app.buttons["字表下載"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["語言"].isSelected)
        XCTAssertEqual(app.switches["paletteSwitch"].value as? String, "1")
        XCTAssertFalse(app.buttons["finishLanguages"].exists)
    }
    @MainActor func testNativeTextSelectionAndDefaultBookNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--long-results-fixture"]; app.launch()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中"); app.buttons["查詢"].tap()
        let note = app.textViews.matching(NSPredicate(format: "label BEGINSWITH %@", "完整注釋內容")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8)); note.press(forDuration: 1.2)
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = "原生文字選區及系統選單"; picture.lifetime = .keepAlways; add(picture)
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Copy", "拷貝", "拷贝", "複製", "复制"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 4))
        app.tabBars.buttons["設定"].tap()
        XCTAssertFalse(app.buttons["設定預設字表"].exists)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "點擊收藏星號")).firstMatch.tap()
        app.buttons["直接加入預設字表"].tap()
        if app.navigationBars["點擊收藏星號"].exists { app.navigationBars.buttons.firstMatch.tap() }
        app.buttons["設定預設字表"].tap()
        XCTAssertTrue(app.navigationBars["設定預設字表"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.buttons["完成"].exists)
        XCTAssertTrue(app.buttons["預設生字表 · 預設生字表"].exists)
    }

}
