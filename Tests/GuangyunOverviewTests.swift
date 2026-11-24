import XCTest
@testable import MCPDictIOS

final class GuangyunOverviewTests: XCTestCase {
    func testBookOrderAndReverseMatching() throws {
        let index = try GyIndex.load()
        let dong = try XCTUnwrap(index.readings("東").first.map { index.groups[$0] })
        XCTAssertEqual(dong.position, "端一東平")
        XCTAssertEqual(dong.she, "通攝")
        let headings = GyIndex.ordered(index.groups.filter { $0.she == dong.she && $0.rhyme == dong.rhyme }.map(\.title))
        XCTAssertEqual(headings, ["上平聲1東", "上聲1董", "去聲1送", "入聲1屋"])
        let exact = index.matching(dong, fields: Set(GyField.allCases))
        XCTAssertTrue(exact.flatMap(\.characters).contains("菄"))
        XCTAssertTrue(exact.allSatisfy { $0.position == dong.position })
        let partial = index.matching(dong, fields: [.she, .rhyme])
        XCTAssertEqual(Set(partial.map(\.tone)), ["平", "上", "去", "入"])
        XCTAssertGreaterThan(Set(index.readings("行").map { index.groups[$0].position }).count, 1)
    }
}
