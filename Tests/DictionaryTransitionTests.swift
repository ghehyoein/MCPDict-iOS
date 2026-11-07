import XCTest
@testable import MCPDictIOS

final class DictionaryTransitionTests: XCTestCase {
    // Exact name/path/color triples from osfans/MCPDict _詳情.json at
    // 3cf11dfc91250259a20bf2f271eac4ad8134040a, including all primary
    // paths sharing the tested transition colors (to detect collisions).
    private let records: [[String]] = [
        ["南通", "下江－通泰－南通", "#CB1D7A,#7FDDE6"],
        ["南通唐閘", "下江－通泰－南通", "#CB1D7A,#7FDDE6"],
        ["1960南通", "下江－通泰－南通", "#CB1D7A,#7FDDE6"],
        ["通州鄉音字匯", "下江－通泰－南通", "#CB1D7A,#7FDDE6"],
        ["通州金沙", "兩浙－潤州－金沙", "#7FDDE6,#CB1D7A"],
        ["通東呂四", "兩浙－潤州－通東", "#7FDDE6"],
        ["贊皇", "華北－河北－冀西", "#D92E59,#FF2929"],
        ["贛榆", "華北－膠東－青濰", "#C06169,#FD73BF"],
        ["繁峙", "西北－雁北", "#6089D1,#6DE4D0"],
        ["滿洲里", "華北－河北－東北－關外", "#D92E59,#C06169"],
        ["阿拉善", "藍青－寧夏", "#5645A6,#8198C1"],
        ["泰順莒江", "浙南－溫州－莒江", "#0A788D,#139E8D"],
        ["道縣", "藍青－道州官話", "#4A0DA9,#719729"],
        ["昌化浙川", "兩浙－宣徽－績歙", "#75AA95,#184E32"],
        ["沙河橋西", "華北－邯彰", "#FF2929"],
        ["博興", "華北－膠東－青濰", "#C06169"],
        ["萊州", "華北－膠東－膠萊－萊州", "#C06169"],
        ["平度", "華北－膠東－膠萊－平即", "#C06169"],
        ["棲霞", "華北－膠東－東萊", "#C06169"],
        ["蓬萊", "華北－膠東－牟海－登州", "#C06169"],
        ["文登", "華北－膠東－牟海－文榮", "#C06169"],
        ["威海", "華北－膠東－牟海－烟威", "#C06169"],
        ["蓋州", "華北－膠東－牟海－蓋州", "#C06169,#D92E59"],
        ["集安", "華北－膠東－牟海－安東", "#C06169,#D92E59"],
        ["榮成靖海衛", "華北－膠東－靖海衛", "#C06169"],
        ["榆中", "西北－甘肅", "#8198C1"],
        ["忻州", "西北－忻州", "#6DE4D0"],
        ["東海", "下江－海泗", "#FD73BF"],
        ["建湖卞港", "下江－通泰－建鹽", "#CB1D7A,#CA5BB7"],
        ["興化", "下江－通泰－昭陽", "#CB1D7A"],
        ["興化舍陳", "下江－通泰－北泰", "#CB1D7A"],
        ["高港", "下江－通泰－南泰", "#CB1D7A"],
        ["揚中", "下江－通泰－沙上", "#CB1D7A,#632D6E"],
        ["東臺唐洋", "下江－通泰－如北", "#CB1D7A"],
        ["如東豐利", "下江－通泰－掘西", "#CB1D7A"],
        ["如東大豫", "下江－通泰－掘東", "#CB1D7A"],
        ["如東", "下江－通泰－掘港", "#CB1D7A"],
        ["如皋白蒲", "下江－通泰－如南", "#CB1D7A"],
        ["通東四甲", "兩浙－潤州－通東", "#7FDDE6"],
        ["丹陽", "兩浙－潤州－潤南", "#7FDDE6"],
        ["建德", "兩浙－杭嚴－建德", "#184E32"],
        ["淳安", "兩浙－杭嚴－淳安", "#184E32"],
        ["吉安東聯", "兩浙－杭嚴－淳西", "#184E32"],
        ["建德船上話", "兩浙－杭嚴－富春船上", "#184E32"],
        ["屯溪船上話", "兩浙－杭嚴－屯溪船上", "#184E32,#086A38"],
        ["富陽東梓關", "兩浙－杭嚴－分桐", "#184E32"],
        ["新登城陽", "兩浙－杭嚴－杭西", "#184E32"],
        ["富陽", "兩浙－杭嚴－富桐", "#184E32"],
        ["宣平", "浙南－處州－中處", "#139E8D"],
        ["青田", "浙南－處州－小溪", "#139E8D"],
        ["縉雲", "浙南－處州－縉雲", "#139E8D"],
        ["遂昌", "浙南－處州－西處", "#139E8D"],
        ["龍泉", "浙南－處州－南處", "#139E8D"],
        ["東方付馬", "湘贛－不分類", "#184E32"]
    ]
    private var tables: [TablePackage] {
        records.map { row in
            TablePackage(id: row[0], name: row[0], fullName: row[0], atlas: [], dictionary: row[1].components(separatedBy: "－"), administrative: [], source: "osfans/MCPDict", sourceCommit: "3cf11dfc91250259a20bf2f271eac4ad8134040a", recordCount: 1, size: 1, sha256: "", url: URL(string: "https://github.com/osfans/MCPDict")!, dictionaryColor: row[2])
        }
    }
    func testNantongReciprocalTransitionsKeepOriginalsAndAddSubmenus() throws {
        let tables = tables, transitions = DictionaryTransitions(tables: tables)
        let extra = transitions.additionalPaths(tables)
        for name in ["南通", "南通唐閘", "1960南通", "通州鄉音字匯"] {
            XCTAssertEqual(extra[name], [["兩浙", "潤州", "過渡色"]])
        }
        XCTAssertEqual(extra["通州金沙"], [["下江", "通泰", "過渡色"]])
        XCTAssertNil(extra["通東呂四"], "A plain color must not create a transition")
        let index = SelectionIndex(tables: tables, grouping: .dictionary, additionalPaths: extra)
        let original = try XCTUnwrap(index.nodes["g:下江\u{0}通泰\u{0}南通"])
        let added = try XCTUnwrap(index.nodes["g:兩浙\u{0}潤州\u{0}過渡色"])
        XCTAssertTrue(original.ids.contains("南通")); XCTAssertTrue(added.ids.contains("南通"))
        XCTAssertEqual(added.ids.count, 4)
        let leaves = index.rows(expanded: Set(index.nodes.keys), matching: nil, scope: .points).filter { $0.node.table?.name == "南通" }
        XCTAssertEqual(leaves.count, 2)
        XCTAssertNotEqual(leaves[0].id, leaves[1].id)
        let plain = SelectionIndex(tables: tables, grouping: .dictionary)
        XCTAssertNil(plain.nodes[added.id])
        XCTAssertFalse(plain.nodes["g:兩浙\u{0}潤州"]!.ids.contains("南通"))
    }
    func testTerminalRegionsReceivePointsDirectlyAcrossSeveralRegions() throws {
        let tables = tables, transitions = DictionaryTransitions(tables: tables)
        let extra = transitions.additionalPaths(tables)
        let expected = ["贊皇": ["華北", "邯彰"], "贛榆": ["下江", "海泗"], "繁峙": ["西北", "忻州"], "阿拉善": ["西北", "甘肅"]]
        let index = SelectionIndex(tables: tables, grouping: .dictionary, additionalPaths: extra)
        for (name, path) in expected {
            XCTAssertEqual(extra[name], [path])
            let key = "g:" + path.joined(separator: "\u{0}")
            let parent = try XCTUnwrap(index.nodes[key])
            XCTAssertTrue(parent.ids.contains(name))
            XCTAssertNil(index.nodes[key + "\u{0}過渡色"])
            XCTAssertTrue(parent.children.contains { index.nodes[$0]?.table?.name == name })
        }
        XCTAssertEqual(extra["滿洲里"], [["華北", "膠東", "過渡色"]])
        XCTAssertEqual(extra["泰順莒江"], [["浙南", "處州", "過渡色"]])
    }
    func testUnknownAndCollidingColorsDoNotInventARegion() {
        let tables = tables, transitions = DictionaryTransitions(tables: tables)
        let extra = transitions.additionalPaths(tables)
        XCTAssertNil(extra["道縣"])
        XCTAssertNil(extra["昌化浙川"])
        XCTAssertNil(transitions.regionsByColor["#184E32"])
        let unknown = tables.first { $0.name == "道縣" }!
        XCTAssertEqual(transitions.description(unknown), "#719729")
        var explicit = tables.first { $0.name == "昌化浙川" }!
        explicit.metadata = ["音典過渡色": "兩浙－杭嚴"]
        XCTAssertEqual(transitions.destinations(explicit), [["兩浙", "杭嚴"]])
    }
    func testRegionSelectionAndSearchIncludeAddedMembersWithoutDuplicates() throws {
        let tables = tables, transitions = DictionaryTransitions(tables: tables)
        let extra = transitions.additionalPaths(tables)
        let index = SelectionIndex(tables: tables, grouping: .dictionary, additionalPaths: extra)
        let region = "兩浙\u{0}潤州"
        let members = try XCTUnwrap(index.nodes["g:" + region]?.ids)
        XCTAssertEqual(RegionSelection.restore(tables: tables, grouping: .dictionary, names: members, saved: region, additionalPaths: extra), region)
        XCTAssertTrue(index.matches("潤州")!.contains("南通"))
        let all = index.rows(expanded: Set(index.nodes.keys), matching: nil, scope: .terminalGroups)
        XCTAssertTrue(all.allSatisfy { $0.node.table == nil })
        XCTAssertEqual(all.first { $0.node.region == region }?.ids, members)
    }
}
