import XCTest
import MapKit
@testable import MCPDictIOS

final class Revision092Tests: XCTestCase {
    func testTransitionFilterExcludesSingleColorRoots() {
        let source = UITestFixtures.catalog.tables
        let transitions = DictionaryTransitions(tables: source)
        for table in source where TableColors.hexes(table.dictionaryColor).count < 2 {
            XCTAssertFalse(transitions.hasTransition(table), table.name)
        }
        var example = source[0]
        example.dictionaryColor = "#112233,#112233"
        XCTAssertFalse(transitions.hasTransition(example))
        example.dictionaryColor = "#112233,#AABBCC"
        XCTAssertTrue(transitions.hasTransition(example))
    }
    func testBlankMaintainersDoNotCreateBlankEditorGroup() {
        var table = UITestFixtures.catalog.tables[0]
        table.metadata = ["錄入人": "甲", "維護人": ""]
        XCTAssertEqual(TableGrouping.person.paths(table, roles: [.editor, .maintainer]), [["甲"]])
        table.metadata = ["錄入人": "", "維護人": "乙"]
        XCTAssertEqual(Set(TableGrouping.person.paths(table, roles: [.editor, .maintainer])), Set([["(無)"], ["乙"]]))
        table.metadata = ["錄入人": "甲", "維護人": "（无）"]
        XCTAssertEqual(TableGrouping.person.paths(table, roles: [.editor, .maintainer]), [["甲"]])
    }
    @MainActor func testResetPreservesNotebookAndTablesButRestoresControls() throws {
        let suite = "reset-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let reading = Reading(id: 1, characters: "好", language: "甲", pronunciation: "hæ", note: "")
        model.favorites = [SavedReading(reading: reading)]
        let installed = TableInstallation(catalogVersion: "test", tables: UITestFixtures.catalog.tables, databaseFile: "existing.db")
        model.installed = installed
        defaults.set("direct", forKey: "favoriteAction")
        defaults.set(25, forKey: AppTypography.mapKey)
        defaults.set("dictionary", forKey: "colorScheme")
        model.languageSelection.includeTransitions = true
        model.languageSelection.roles = [.maintainer]
        model.languageSelection.flags.history = true
        model.resetSettings()
        XCTAssertEqual(model.favorites.count, 1)
        XCTAssertEqual(model.installed?.databaseFile, "existing.db")
        XCTAssertEqual(defaults.string(forKey: "favoriteAction"), "direct")
        XCTAssertNil(defaults.object(forKey: AppTypography.mapKey))
        XCTAssertNil(defaults.object(forKey: "colorScheme"))
        XCTAssertFalse(model.languageSelection.includeTransitions)
        XCTAssertFalse(model.languageSelection.flags.history)
        XCTAssertTrue(model.languageSelection.roles.contains(.editor))
        XCTAssertEqual(model.settingsRevision, 1)
    }
    @MainActor func testInstalledTablesAreNotDownloadableUnlessChanged() {
        let model = AppModel()
        let tables = UITestFixtures.catalog.tables
        model.catalog = UITestFixtures.catalog
        model.installed = TableInstallation(catalogVersion: "test", tables: [tables[0]], databaseFile: "existing.db")
        XCTAssertFalse(model.downloadableIDs(Set(tables.map(\.id))).contains(tables[0].id))
        if tables.count > 1 { XCTAssertTrue(model.downloadableIDs([tables[1].id]).contains(tables[1].id)) }
    }
    @MainActor func testMapRetainsAnnotationAndSelectionAcrossPaletteChanges() throws {
        let coordinator = NativeDialectMap.Coordinator { _ in }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let point = DialectPoint(id: "a", name: "甲", longitude: 113, latitude: 23, color: "#008080", reading: "native selection")
        coordinator.update(map, points: [point], fit: 0, revision: UUID())
        let annotation = try XCTUnwrap(map.annotations.first as? NativeDialectMap.PointAnnotation)
        let label = LabelAnnotationView(annotation: annotation, reuseIdentifier: nil)
        label.configure(point, fontSize: 16) {}
        label.readingText.selectedRange = NSRange(location: 0, length: 6)
        let oldStorage = label.readingText.attributedText
        let colored = DialectPoint(id: point.id, name: point.name, longitude: point.longitude, latitude: point.latitude, color: "#AABBCC", reading: point.reading)
        label.configure(colored, fontSize: 16, labelSize: 20) {}
        XCTAssertEqual(label.readingText.selectedRange, NSRange(location: 0, length: 6))
        XCTAssertEqual(label.readingText.attributedText, oldStorage)
        coordinator.update(map, points: [colored], fit: 0, revision: UUID())
        XCTAssertTrue(map.annotations.first as AnyObject === annotation)
        XCTAssertEqual(annotation.point.color, "#AABBCC")
    }
}
