import XCTest
import UIKit

final class NavigationTests: XCTestCase {
    @MainActor private func tab(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let phone = app.tabBars.buttons[title]
        if phone.exists { return phone }
        // iPadOS exposes its floating tab bar as cells rather than UITabBar.
        let tablet = app.cells.matching(identifier: title).firstMatch
        if tablet.exists { return tablet }
        // The floating tab exposes both its cell and child as buttons.
        return app.buttons[title].firstMatch
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.75)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.35)))
        }
    }
    @MainActor private func scrollVisibleTree(_ scroll: XCUIElement, in app: XCUIApplication) {
        // A nested scroll view can extend behind the floating iOS 26 tab bar.
        // Limit the gesture to its visible content instead of the full AX frame.
        let frame = scroll.frame.intersection(app.frame)
        let top = max(frame.minY, app.navigationBars.firstMatch.frame.maxY)
        let bar = app.tabBars.firstMatch
        let bottom = min(frame.maxY, bar.exists ? bar.frame.minY : app.frame.maxY)
        guard bottom - top > 30 else { XCTFail("Language tree has no exposed scroll area: \(app.debugDescription)"); return }
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: bottom - 12))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: max(top + 12, bottom - 112)))
        start.press(forDuration: 0.01, thenDragTo: end)
    }
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
        tab(app, "生字本").tap()
        app.segmentedControls.buttons["發音"].tap()
        XCTAssertTrue(app.scrollViews["notebookChoiceBar"].exists)
        XCTAssertTrue(app.buttons["tɕiɔŋ1"].exists)
        app.segmentedControls.buttons["隱藏"].tap()
        XCTAssertFalse(app.scrollViews["notebookChoiceBar"].exists)
        app.buttons["多選"].tap(); app.buttons["全選"].tap()
        XCTAssertTrue(app.textViews["已選 1"].exists)
    }
    @MainActor func testContributorGroupingDoesNotFollowColorTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        tab(app, "設定").tap(); app.buttons["字表下載"].tap()
        XCTAssertFalse(app.buttons["downloadLanguageSelection"].exists)
        let toggle = app.buttons["classificationPickerToggle"]
        chooseClassification(app, "錄入人")
        let blank = app.buttons["check-(無)"]
        let person = app.buttons["check-測試維護人"]
        XCTAssertTrue(blank.exists); XCTAssertTrue(person.exists)
        person.tap()
        flipSwitch(app.switches["paletteSwitch"])
        XCTAssertEqual(person.value as? String, "checked")
        app.buttons["personRole-維護人"].tap()
        XCTAssertFalse(person.exists); XCTAssertTrue(blank.exists)
        XCTAssertFalse(app.buttons["personRole-錄入人"].exists)
        XCTAssertTrue(blank.exists)
        app.buttons["personRole-維護人"].tap()
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
        tab(app, "設定").tap()
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
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = "字體大小內置預覽"; picture.lifetime = .keepAlways; add(picture)
        let oldReading = reading.value as? String
        let oldOther = other.value as? String
        let originalMap = map.value as? String
        map.adjust(toNormalizedSliderPosition: 0.8)
        let enlarged = XCTAttachment(screenshot: app.screenshot()); enlarged.name = "地圖語言點放大後的固定分隔線"; enlarged.lifetime = .keepAlways; add(enlarged)
        XCTAssertEqual(other.value as? String, oldOther)
        XCTAssertEqual(reading.value as? String, oldReading)
        let mapValue = map.value as? String
        reading.adjust(toNormalizedSliderPosition: 0.35)
        XCTAssertEqual(map.value as? String, mapValue)
        other.adjust(toNormalizedSliderPosition: 0.6)
        XCTAssertEqual(map.value as? String, mapValue)
        let reset = app.buttons["resetSettings"]
        // Drag in the list margin: after resizing, an app-wide swipe can start
        // on a slider and adjust/intercept that control instead of scrolling.
        for _ in 0..<12 {
            if reset.exists && reset.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.75)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.3)))
        }
        guard reset.exists && reset.isHittable else { XCTFail("Reset row was not reached: \(app.debugDescription)"); return }
        reset.tap()
        let confirmation = app.alerts["是否還原默認設定？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["取消"].tap()
        XCTAssertFalse(confirmation.exists)
        // UIKit may remove the alert from accessibility before its dismissal
        // transition has restored hit testing to the underlying settings row.
        let resetReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: reset)
        XCTAssertEqual(XCTWaiter.wait(for: [resetReady], timeout: 5), .completed)
        reset.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["還原"].tap()
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertEqual(map.value as? String, originalMap)
        XCTAssertEqual(reading.value as? String, oldReading)
    }

    @MainActor func testTreeSelectionBlankStartAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "漢字、U+4E2D 或原始讀音")
        tab(app, "設定").tap(); app.buttons["字表下載"].tap()
        XCTAssertFalse(app.buttons["downloadLanguageSelection"].exists)
        app.buttons["selectAllLanguages"].tap()
        XCTAssertFalse(app.buttons["downloadTables"].isEnabled)
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
        XCTAssertEqual(app.textViews["downloadState-" + String(repeating: "a", count: 24)].label, "已下載")
        app.buttons.matching(identifier: "示例語言點").firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["完成"].waitForExistence(timeout: 5))
        let vanished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars.buttons["完成"])
        XCTAssertEqual(XCTWaiter.wait(for: [vanished], timeout: 1.5), .timedOut)
        app.navigationBars.buttons["完成"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tab(app, "字典").tap()
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
        tab(app, "設定").tap()
        XCTAssertTrue(app.buttons["元來是正體ɵɤ̞ɵ("].exists)
        let simplified = app.descendants(matching: .any).matching(identifier: "简体中文").firstMatch
        XCTAssertTrue(simplified.waitForExistence(timeout: 5)); simplified.tap()
        XCTAssertTrue(tab(app, "设置").waitForExistence(timeout: 5))
        reveal(app.sliders["fontSizeSlider"], in: app)
        XCTAssertTrue(app.sliders["fontSizeSlider"].exists)
    }
    @MainActor func testMapModesRefreshOpenDropdownAndSelectableText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection"]; app.launch()
        tab(app, "地圖").tap()
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
        XCTAssertTrue(app.textViews["自選功能後續待更新，目前與語言模式相同"].exists)
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
        let reading = app.descendants(matching: .any).matching(identifier: "map-reading-" + String(repeating: "a", count: 24)).firstMatch
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
        // The compact screen may have no map space below the menu. Its side
        // margin remains exposed on every device and must dismiss the menu.
        let mapMiddle = app.maps.firstMatch.frame.midY
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 6, dy: mapMiddle)).tap()
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
        // iPad's floating tab child does not expose the selected trait.
        // Verify the destination itself and the transferred reading below.
        XCTAssertTrue(app.buttons["mapLanguageSelection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.maps.firstMatch.exists)
        let mark = app.descendants(matching: .any).matching(identifier: "map-reading-" + String(repeating: "a", count: 24)).firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 8))
        XCTAssertEqual(mark.label, "tɕiɔŋ1")
    }

    @MainActor func testMapSearchModeControlsAndVariantResults() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]; app.launch()
        tab(app, "地圖").tap()
        let menu = app.buttons["mapLanguageSelection"]
        menu.tap(); app.segmentedControls.buttons["語言"].tap()
        app.buttons["selectAllLanguages"].tap(); app.buttons["finishLanguages"].tap()
        func query(_ hint: String, _ value: String) {
            let field = app.textFields[hint]
            field.tap(); field.typeText(value); app.buttons["查字"].tap()
        }
        let mark = app.descendants(matching: .any).matching(identifier: "map-reading-" + String(repeating: "a", count: 24)).firstMatch
        query("請輸入漢字", "中输")
        XCTAssertTrue(app.buttons["輸"].waitForExistence(timeout: 8))
        app.buttons["輸"].tap()
        XCTAssertEqual(mark.label, "su1")
        app.segmentedControls.buttons["讀音"].tap()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "中输")
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
            for _ in 0..<5 { if checkbox.isHittable { break }; scrollVisibleTree(scroll, in: app) }
            XCTAssertTrue(checkbox.isHittable)
            XCTAssertEqual(checkbox.frame.minX, rootX, accuracy: 2, "Every root must remain at depth zero")
            checkbox.tap()
            XCTAssertEqual(checkbox.value as? String, "checked")
            if let previous { XCTAssertEqual(app.buttons["check-" + previous].value as? String, "unchecked") }
            app.buttons["expand-" + root].tap()
            let child = app.buttons["check-" + root + "子區"]
            for _ in 0..<5 { if child.isHittable { break }; scrollVisibleTree(scroll, in: app) }
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
        tab(app, "生字本").tap()
        app.buttons["chooseNotebooks"].tap()
        app.buttons["新建生字本"].tap()
        let alert = app.alerts["新建生字本"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let title = "測試表-" + String(UUID().uuidString.prefix(6))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText(String(title))
        alert.buttons["儲存"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", String(title))).firstMatch.waitForExistence(timeout: 3))
        app.navigationBars.buttons["完成"].tap()
        tab(app, "地圖").tap()
        XCTAssertTrue(app.segmentedControls.buttons["漢字"].isHittable)
        XCTAssertTrue(app.segmentedControls.buttons["讀音"].isHittable)
        XCTAssertTrue(app.segmentedControls.buttons["註釋"].isHittable)
        app.textFields["請輸入漢字"].tap(); app.textFields["請輸入漢字"].typeText("中")
        app.buttons["mapLanguageSelection"].tap(); app.segmentedControls.buttons["語言"].tap()
        XCTAssertTrue(app.buttons["selectAllLanguages"].isHittable)
        XCTAssertTrue(app.buttons["finishLanguages"].isHittable)
        app.buttons["selectAllLanguages"].tap(); app.buttons["finishLanguages"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "map-reading-" + String(repeating: "a", count: 24)).firstMatch.waitForExistence(timeout: 8))
    }
    @MainActor func testPinnedHeaderPreservesInputAndLanguageMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--long-results-fixture"]; app.launch()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        XCTAssertTrue(app.textViews["dictionaryHeadword"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields.firstMatch.isHittable)
        app.buttons["dictionaryLanguageSelection"].tap()
        reveal(app.buttons["finishLanguages"], in: app)
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

    @MainActor func testVariantSelectionPreservesTypedInputAndMode() throws {
        for map in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]
            app.launch()
            if map { tab(app, "地圖").tap() }
            app.segmentedControls.buttons["註釋"].tap()
            let field = app.textFields.firstMatch
            field.tap(); field.typeText("运送貨物的完整註釋")
            app.buttons[map ? "查字" : "查詢"].tap()
            let picker = app.scrollViews["noteInputVariants"]
            XCTAssertTrue(picker.waitForExistence(timeout: 8))
            let variant = picker.buttons["運"]
            XCTAssertTrue(variant.waitForExistence(timeout: 8))
            // The previous result's selector remains available after changing mode.
            app.segmentedControls.buttons["漢字"].tap()
            variant.tap()
            let reading = app.descendants(matching: .any).matching(identifier: map
                ? "map-reading-" + String(repeating: "a", count: 24)
                : "dictionary-reading-示例語言點").firstMatch
            XCTAssertTrue(reading.waitForExistence(timeout: 8))
            XCTAssertEqual(field.value as? String, "运送貨物的完整註釋")
            XCTAssertTrue(app.segmentedControls.buttons["漢字"].isSelected)
            for title in ["註釋", "讀音", "漢字"] {
                app.segmentedControls.buttons[title].tap()
                XCTAssertEqual(field.value as? String, "运送貨物的完整註釋")
            }
            app.terminate()
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
        for title in ["字典", "生字本", "地圖", "設定"] { XCTAssertTrue(tab(app, title).exists) }
        XCTAssertFalse(tab(app, "字表").exists)
        tab(app, "設定").tap(); app.buttons["字表下載"].tap()
        XCTAssertTrue(app.buttons["selectAllLanguages"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["downloadLanguageSelection"].exists)
        XCTAssertFalse(app.navigationBars.buttons["完成"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["字頭資料顯示"].tap()
        XCTAssertTrue(app.navigationBars["字頭資料顯示"].waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "referenceField-Unicode").firstMatch.tap()
        app.buttons["不顯示"].tap()
        app.navigationBars.buttons["完成"].tap()
        tab(app, "字典").tap()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中")
        app.buttons["查詢"].tap()
        XCTAssertTrue(app.textViews["dictionaryHeadword"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textViews["characterUnicode"].exists, app.debugDescription)
    }

    @MainActor private func flipSwitch(_ control: XCUIElement) {
        guard let before = control.value as? String, ["0", "1"].contains(before) else {
            XCTFail("Expected a native on/off switch"); return
        }
        // A 50 ms synthesized tap can reach iOS 26 with both touch events in
        // one batch. Use one ordinary 200 ms touch, without retrying the action.
        control.press(forDuration: 0.2)
        let expected = before == "0" ? "1" : "0"
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed, "Switch must change before testing persistence")
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
        flipSwitch(app.switches["paletteSwitch"])
        app.segmentedControls.buttons["分區"].tap()
        XCTAssertEqual(app.segmentedControls["regionClassification"].buttons.count, 2)
        app.buttons["check-漢語"].tap()
        tab(app, "地圖").tap()
        XCTAssertTrue(app.segmentedControls.buttons["分區"].isSelected)
        XCTAssertEqual(app.buttons["check-漢語"].value as? String, "checked")
        XCTAssertEqual(app.switches["paletteSwitch"].value as? String, "1")
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = "共用語言選單及原生地音開關"; picture.lifetime = .keepAlways; add(picture)
        app.buttons["finishLanguages"].tap()
        tab(app, "設定").tap(); app.buttons["字表下載"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["語言"].isSelected)
        XCTAssertEqual(app.switches["paletteSwitch"].value as? String, "1")
        XCTAssertFalse(app.buttons["finishLanguages"].exists)
    }
    @MainActor func testNativeTextSelectionAndDefaultBookNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--long-results-fixture"]; app.launch()
        app.textFields.firstMatch.tap(); app.textFields.firstMatch.typeText("中"); app.buttons["查詢"].tap()
        let note = app.textViews.matching(NSPredicate(format: "label BEGINSWITH %@", "完整注釋內容")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.12)).press(forDuration: 1.2)
        let picture = XCTAttachment(screenshot: app.screenshot()); picture.name = "原生文字選區及系統選單"; picture.lifetime = .keepAlways; add(picture)
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Copy", "拷貝", "拷贝", "複製", "复制"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Look Up", "查詢", "查询"])).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Translate", "翻譯", "翻译"])).firstMatch.exists)
        tab(app, "設定").tap()
        XCTAssertFalse(app.buttons["設定預設生字本"].exists)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "點擊收藏星號")).firstMatch.tap()
        app.buttons["直接加入預設生字本"].tap()
        if app.navigationBars["點擊收藏星號"].exists { app.navigationBars.buttons.firstMatch.tap() }
        app.buttons["設定預設生字本"].tap()
        XCTAssertTrue(app.navigationBars["設定預設生字本"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.buttons["完成"].exists)
        XCTAssertTrue(app.buttons["預設生字本 · 預設生字本"].exists)
    }

    @MainActor func testRecordedTransitionsAppearUnderBranchesAndDirectlyInTerminalRegions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--transition-fixture"]; app.launch()
        app.buttons["dictionaryLanguageSelection"].tap()
        chooseClassification(app, "音典分區")
        let include = app.buttons["includeDictionaryTransitions"]
        XCTAssertTrue(include.exists)
        let tree = app.scrollViews["languageTreeScroll"]
        func reveal(_ element: XCUIElement) {
            for _ in 0..<5 { if element.isHittable { return }; tree.swipeUp() }
            for _ in 0..<5 { if element.isHittable { return }; tree.swipeDown() }
        }
        app.buttons["clearLanguages"].tap()
        include.tap()
        for name in ["兩浙", "潤州", "過渡色"] {
            let button = app.buttons["expand-" + name]; reveal(button); button.tap()
        }
        let added = app.buttons["check-南通"]; reveal(added); added.tap()
        XCTAssertEqual(app.buttons["南通"].value as? String, "*")
        XCTAssertTrue(app.buttons["dictionaryLanguageSelection"].label.contains("已選 1"))
        let branch = XCTAttachment(screenshot: app.screenshot()); branch.name = "南通補入潤州過渡色子目錄"; branch.lifetime = .keepAlways; add(branch)
        app.buttons["南通"].tap()
        XCTAssertTrue(app.navigationBars.buttons["完成"].waitForExistence(timeout: 5)); app.navigationBars.buttons["完成"].tap()
        let root = app.buttons["expand-兩浙"]; reveal(root); root.tap()
        include.tap()
        for name in ["華北", "邯彰"] {
            let button = app.buttons["expand-" + name]; reveal(button); button.tap()
        }
        XCTAssertFalse(app.buttons["check-贊皇"].exists)
        include.tap()
        let branchButton = app.buttons["expand-邯彰"]; reveal(branchButton)
        if branchButton.value as? String != "expanded" { branchButton.tap() }
        let terminal = app.buttons["check-贊皇"]; reveal(terminal)
        XCTAssertTrue(terminal.exists)
        XCTAssertNotEqual(app.buttons["贊皇"].value as? String, "*")
        XCTAssertFalse(app.buttons["expand-過渡色"].exists)
        let direct = XCTAttachment(screenshot: app.screenshot()); direct.name = "末級邯彰直接補入贊皇"; direct.lifetime = .keepAlways; add(direct)
        app.buttons["贊皇"].tap()
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "label CONTAINS %@", "音典分區過渡色：華北－邯彰")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["完成"].tap()
        include.tap()
        for name in ["下江", "通泰", "南通"] {
            let button = app.buttons["expand-" + name]; reveal(button); button.tap()
        }
        XCTAssertTrue(app.buttons["南通"].exists)
        XCTAssertNotEqual(app.buttons["南通"].value as? String, "*")
    }

    @MainActor func testDenseMapMenuRemainsInteractiveAfterLoading() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--dense-map-fixture"]; app.launch()
        // Bulk snapshots avoid thousands of per-element attribute requests
        // made by firstMatch when the map contains many accessible labels.
        func control(_ id: String) -> XCUIElement { app.buttons[id] }
        tab(app, "地圖").tap()
        let count = app.descendants(matching: .any).matching(identifier: "mapPointStatus").firstMatch
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "3306"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 30), .completed)
        control("mapLanguageSelection").tap()
        XCTAssertTrue(control("expand-根0").waitForExistence(timeout: 10))
        control("expand-根0").tap()
        control("expand-區0").tap()
        XCTAssertTrue(control("check-點0").exists)
        control("finishLanguages").tap()
        let warmStart = Date()
        for _ in 0..<3 {
            control("mapLanguageSelection").tap()
            XCTAssertTrue(control("check-點0").waitForExistence(timeout: 5))
            control("finishLanguages").tap()
        }
        XCTAssertTrue(count.label.contains("3306"))
        print("DENSE_MAP_MENU_BENCH points=3306 warm_open_close_3_seconds=\(Date().timeIntervalSince(warmStart))")
        // Exercise both removal and insertion after the native accessibility
        // snapshot has already been read, so caching cannot retain stale controls.
        for expected in ["3305", "3306"] {
            control("mapLanguageSelection").tap()
            control("check-點0").tap()
            control("finishLanguages").tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", expected), object: count)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            let marker = control("map-name-" + String(repeating: "0", count: 24))
            let markerChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == %@", NSNumber(value: expected == "3306")), object: marker)
            XCTAssertEqual(XCTWaiter.wait(for: [markerChanged], timeout: 30), .completed)
        }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "3306語言點完整地圖"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testMapTextSupportsNativeSelectionAndMenuFollowsInput() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--map-search-fixture"]; app.launch()
        tab(app, "地圖").tap()
        let input = app.textFields["請輸入漢字"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["mapLanguageSelection"].frame.minY, input.frame.maxY)
        input.tap(); input.typeText("输")
        app.buttons["查字"].tap()
        let text = app.descendants(matching: .any).matching(identifier: "map-reading-" + String(repeating: "a", count: 24)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.press(forDuration: 1.2)
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Copy", "拷貝", "拷贝", "複製", "复制"])).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), app.debugDescription)
        let lookup = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Look Up", "查詢", "查询"])).firstMatch
        XCTAssertTrue(lookup.exists, "Map text must expose the native selection menu, including dictionary lookup")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "地圖文字原生選取"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(app.textViews["map-reading-" + String(repeating: "a", count: 24)].exists)
    }

    @MainActor func testNotebookActionsFloatAndLanguageChoiceDoesNotOpenDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--notebook-list-fixture"]; app.launch()
        tab(app, "生字本").tap()
        app.segmentedControls.buttons["語言"].tap()
        let choice = app.scrollViews["notebookChoiceBar"].buttons["示例語言點"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        XCTAssertFalse(app.navigationBars.buttons["完成"].exists)
        app.buttons["多選"].tap()
        let all = app.buttons["全選"]
        let before = all.frame.midY
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(all.isHittable)
        XCTAssertEqual(all.frame.midY, before, accuracy: 2)
        all.tap()
        XCTAssertTrue(app.textViews["已選 35"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "生字本滾動後浮動操作"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testTableOperationDoesNotDisableSelectionOrMapQuery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--busy-fixture"]; app.launch()
        tab(app, "設定").tap(); app.buttons["字表下載"].tap()
        XCTAssertTrue(app.buttons["selectAllLanguages"].isEnabled)
        app.buttons["selectAllLanguages"].tap()
        XCTAssertTrue(app.buttons["expand-漢語"].isEnabled)
        app.buttons["expand-漢語"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        tab(app, "地圖").tap()
        let input = app.textFields["請輸入漢字"]
        input.tap(); input.typeText("中")
        XCTAssertTrue(app.buttons["查字"].isEnabled)
        app.buttons["查字"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "map-reading-" + String(repeating: "a", count: 24)).firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor func testCatalogProgressAllowsNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixture", "--reset-selection", "--catalog-progress-fixture"]; app.launch()
        tab(app, "設定").tap(); app.buttons["字表下載"].tap()
        let progress = app.progressIndicators["tableProcessingProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.isHittable)
        XCTAssertTrue(app.textViews["downloadCount"].label.contains("正在取得字表目錄"))
        XCTAssertTrue(app.buttons["selectAllLanguages"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "更新目錄進度"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars.buttons.firstMatch.tap()
        tab(app, "地圖").tap()
        XCTAssertTrue(app.buttons["mapLanguageSelection"].waitForExistence(timeout: 5))
    }

}
