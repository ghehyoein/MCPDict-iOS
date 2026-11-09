import SwiftUI

// Order and tokens match Android res/values/arrays.xml pref_*_charset.
enum CharacterSearchRange: String, CaseIterable, Identifiable {
    case all = "", guangyun = "GY", shuowen = "SW", jiyun = "JY", kangxi = "KX", huizuan = "HZ", handa = "HD", survey = "FD", ancientPrint = "GJ", hongKong = "kHKGlyph", taiwan = "T1", bigFive = "kBigFive"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "不限"
        case .guangyun: return "廣韻"
        case .shuowen: return "說文解字"
        case .jiyun: return "集韻"
        case .kangxi: return "康熙字典"
        case .huizuan: return "古音匯纂"
        case .handa: return "漢語大字典"
        case .survey: return "方言調查字表"
        case .ancientPrint: return "古籍印刷通用字規範字形表"
        case .hongKong: return "常用字字形表"
        case .taiwan: return "常用國字標準字體表"
        case .bigFive: return "大五碼"
        }
    }
    static let preferenceKey = "characterSearchRange"
}

actor CharacterRangeIndex {
    static let shared = CharacterRangeIndex()
    private var members: [String: Set<String>]?
    private func allowed(_ range: CharacterSearchRange) throws -> Set<String> {
        if members == nil {
            guard let url = Bundle.main.url(forResource: "character-ranges", withExtension: "json", subdirectory: "BundledTables") else { throw DictionaryFailure(message: "缺少漢字範圍資料") }
            members = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url)).mapValues { Set($0) }
        }
        guard let result = members?[range.rawValue] else { throw DictionaryFailure(message: "缺少漢字範圍資料") }
        return result
    }
    func filter(_ characters: [String], range: CharacterSearchRange) throws -> [String] {
        guard range != .all else { return characters }
        let set = try allowed(range)
        // Android HanZi.isUnknown exempts □ from every character range.
        return characters.filter { $0.hasPrefix("□") || set.contains($0) }
    }
    func filter(_ readings: [Reading], range: CharacterSearchRange) throws -> [Reading] {
        guard range != .all else { return readings }
        let set = try allowed(range)
        return readings.compactMap { row in
            let chars = row.characters.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { $0.hasPrefix("□") || set.contains($0) }
            guard !chars.isEmpty else { return nil }
            return Reading(id: row.id, characters: chars.joined(separator: " "), language: row.language, pronunciation: row.pronunciation, note: row.note)
        }
    }
}

struct CharacterRangeSettings: View {
    @AppStorage(CharacterSearchRange.preferenceKey) private var selection = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(CharacterSearchRange.allCases) { range in
                Button { selection = range.rawValue } label: {
                    HStack { Text(ui(range.title)).foregroundStyle(.primary); Spacer(); if selection == range.rawValue { Image(systemName: "checkmark").foregroundStyle(AppAccent.color) } }
                        .contentShape(Rectangle())
                }.accessibilityAddTraits(selection == range.rawValue ? .isSelected : [])
                    .accessibilityIdentifier("character-range-" + (range == .all ? "all" : range.rawValue))
            }.navigationTitle(ui("漢字檢索範圍"))
                .toolbar { Button(ui("完成")) { dismiss() } }
        }
    }
}
struct CharacterRangeButton: View {
    @State private var showing = false
    var body: some View {
        Button("⋯") { showing = true }
            .font(.title2).foregroundStyle(AppAccent.color)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(ui("漢字檢索範圍"))
            .accessibilityIdentifier("characterRangeButton")
            .sheet(isPresented: $showing) { CharacterRangeSettings() }
    }
}
