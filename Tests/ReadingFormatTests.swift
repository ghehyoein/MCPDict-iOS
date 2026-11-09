import XCTest
@testable import MCPDictIOS

final class ReadingFormatTests: XCTestCase {
    private func table(_ name: String) throws -> TablePackage {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(UITestFixtures.catalog.tables[0])) as? [String: Any])
        value["name"] = name
        value["metadata"] = ["聲調": "{\"1\":[\"55\",\"1\",\"1\",\"陰平\",\"꜀\"]}"]
        return try JSONDecoder().decode(TablePackage.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testAllAndroidGroupsAndExactMiddleChineseOptions() {
        let specs = ReadingFormatEngine.shared.specs
        XCTAssertEqual(specs.count, 9)
        let mc = specs.first { $0.id == "mc_display" }
        XCTAssertEqual(mc?.options.count, 24)
        XCTAssertEqual(mc?.defaults, ["0", "109", "110", "200", "201", "300", "400"])
        XCTAssertEqual(specs.first { $0.id == "zyyy_display" }?.options.count, 5)
        XCTAssertEqual(specs.first { $0.id == "dgy_display" }?.defaults, ["0", "1"])
    }
    func testNativeConversionBridgeAndToneStyleComposition() throws {
        let engine = ReadingFormatEngine.shared
        func convert(_ name: String, _ raw: String, _ key: String, _ option: String) throws -> String {
            var prefs = ReadingFormatPreferences(); prefs.values[key] = [option]
            let parts = try XCTUnwrap(engine.parts(raw, table: table(name), style: "hidden", pitch: "hidden", preferences: prefs))
            return parts.map { $0.base + $0.pitch + $0.tone }.joined()
        }
        XCTAssertEqual(try convert("普通話", "xing1", "mandarin_display", "0"), "ɕiŋ")
        XCTAssertEqual(try convert("普通話", "xing1", "mandarin_display", "1"), "xīng")
        XCTAssertEqual(try convert("普通話", "xing1", "mandarin_display", "2"), "ㄒㄧㄥ")
        XCTAssertEqual(try convert("朝鮮", "il", "korean_display", "1"), "일")
        XCTAssertEqual(try convert("日語漢音", "itu", "japanese_display", "1"), "いつ")
        XCTAssertEqual(try convert("越南", "nhaats", "vietnamese_tone_position", "1"), "nhất")
        let parts = try XCTUnwrap(engine.parts("xing1", table: table("普通話"), style: "hanzi", pitch: "number", preferences: ReadingFormatPreferences()))
        XCTAssertEqual(parts.map { $0.base + $0.pitch + $0.tone }.joined(), "ɕiŋ55陰平")
        var prefs = ReadingFormatPreferences(); prefs.values["zyyy_display"] = ["1", "4"]
        let selected = try XCTUnwrap(engine.parts("a1/b1/c1/d1/e1", table: table("中原音韻"), style: "hidden", pitch: "hidden", preferences: prefs))
        XCTAssertEqual(selected.map(\.base).joined(), "b(寧繼福) e(unt) ")
    }
    func testLongTextPreservesPunctuationAndIndependentOccurrences() {
        let rows = [Reading(id: 1, characters: "中", language: "例", pronunciation: "a1", note: ""), Reading(id: 2, characters: "中", language: "例", pronunciation: "b2", note: ""), Reading(id: 3, characters: "衆", language: "例", pronunciation: "c3", note: "")]
        var result = LongTextAnnotation.build("中，中\n众!", rows: rows, variants: { $0 == "众" ? ["众", "衆"] : [$0] })
        XCTAssertEqual(result.map(\.original).joined(), "中，中\n众!")
        XCTAssertEqual(result[0].choices.count, 2)
        result[0].selected = 1
        XCTAssertEqual(result[2].choice?.pronunciation, "a1")
        XCTAssertEqual(result[4].choice?.character, "衆")
        XCTAssertTrue(LongTextAnnotation.copyText(result, table: nil, format: 8).contains("\n"))
        XCTAssertTrue(LongTextAnnotation.copyText(result, table: nil, format: 8).contains("b2 中"))
        XCTAssertEqual(LongTextAnnotation.formats.count, 8)
    }
    func testOnlineDictionaryURLsAndVisibilityOrderRoundTrip() throws {
        XCTAssertEqual(OnlineDictionary.allCases.count, 8)
        XCTAssertEqual(try XCTUnwrap(OnlineDictionary.zisea.url(for: "𠀀")).query, "uni=20000")
        XCTAssertEqual(try XCTUnwrap(OnlineDictionary.zdic.url(for: "中")).path, "/hans/中")
        XCTAssertTrue(try XCTUnwrap(OnlineDictionary.ccamc.url(for: "中")).absoluteString.contains("cjkv="))
        var settings = OnlineDictionaryPreferences()
        settings.order = ["chise", "zdic", "zdic", "unknown"]
        settings.hidden = ["zdic"]
        let restored = OnlineDictionaryPreferences.load(settings.encoded)
        XCTAssertEqual(restored.order.count, 8)
        XCTAssertEqual(restored.visible.first, .chise)
        XCTAssertFalse(restored.visible.contains(.zdic))
    }
}
