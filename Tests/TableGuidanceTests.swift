import XCTest
@testable import MCPDictIOS

final class TableGuidanceTests: XCTestCase {
    private func schedule() throws -> TableGuidanceSchedule {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return TableGuidanceSchedule(defaults: defaults)
    }
    func testFreshInstallWelcomesOnceAndPersistsAcrossLaunches() throws {
        let s = try schedule(), now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(s.due(now: now))
        s.prepare(existingInstallation: false, now: now)
        XCTAssertEqual(s.due(now: now), .welcome)
        // A partially completed first install must not suppress its pending tutorial.
        s.prepare(existingInstallation: true, now: now)
        XCTAssertEqual(s.due(now: now), .welcome)
        s.presented(.welcome, now: now)
        let reopened = TableGuidanceSchedule(defaults: s.defaults)
        XCTAssertNil(reopened.due(now: now.addingTimeInterval(10)))
        XCTAssertEqual(reopened.due(now: now.addingTimeInterval(TableGuidanceSchedule.interval)), .update)
    }
    func testUpgradeWaitsThirtyDaysAndDismissalResetsInterval() throws {
        let s = try schedule(), now = Date(timeIntervalSince1970: 1_000_000)
        s.prepare(existingInstallation: true, now: now)
        XCTAssertNil(s.due(now: now))
        XCTAssertNil(s.due(now: now.addingTimeInterval(TableGuidanceSchedule.interval-1)))
        let due = now.addingTimeInterval(TableGuidanceSchedule.interval)
        XCTAssertEqual(s.due(now: due), .update)
        s.presented(.update, now: due)
        XCTAssertNil(s.due(now: due.addingTimeInterval(1)))
        XCTAssertEqual(s.due(now: due.addingTimeInterval(TableGuidanceSchedule.interval)), .update)
    }
    func testSuccessfulCatalogCheckPostponesReminderWithoutRepeatingTutorial() throws {
        let s = try schedule(), now = Date(timeIntervalSince1970: 1_000_000)
        s.prepare(existingInstallation: true, now: now)
        let checked = now.addingTimeInterval(20*24*60*60)
        s.catalogChecked(now: checked)
        XCTAssertNil(s.due(now: now.addingTimeInterval(TableGuidanceSchedule.interval)))
        XCTAssertEqual(s.due(now: checked.addingTimeInterval(TableGuidanceSchedule.interval)), .update)
        XCTAssertNil(s.due(now: now.addingTimeInterval(-100)))
    }
}
