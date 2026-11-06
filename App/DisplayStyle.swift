import SwiftUI

private struct MapLabelSizeKey: EnvironmentKey { static let defaultValue: Double? = nil }
extension EnvironmentValues {
    var mapLabelSize: Double? {
        get { self[MapLabelSizeKey.self] }
        set { self[MapLabelSizeKey.self] = newValue }
    }
}

enum AppTypography {
    static let interfaceKey = "fontSize"
    static let mapKey = "mapTextSize"
    static func size(_ value: Double) -> DynamicTypeSize {
        switch value {
        case ..<15: return .xSmall
        case ..<16: return .small
        case ..<17: return .medium
        case ..<19: return .large
        case ..<21: return .xLarge
        case ..<23: return .xxLarge
        case ..<25: return .xxxLarge
        default: return .accessibility1
        }
    }
}

enum TableColors {
    static func hexes(_ raw: String?) -> [String] {
        (raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil }
    }
    static func raw(_ table: TablePackage, _ grouping: TableGrouping) -> String? {
        grouping == .dictionary ? table.dictionaryColor : table.atlasColor
    }
    static func color(_ hex: String) -> Color { Color(uiColor: uiColor(hex)) }
    static func uiColor(_ hex: String) -> UIColor {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0x008080
        return UIColor(red: CGFloat(n >> 16 & 255)/255, green: CGFloat(n >> 8 & 255)/255, blue: CGFloat(n & 255)/255, alpha: 1)
    }
    static func gradient(_ values: [String]) -> LinearGradient {
        LinearGradient(colors: (values.isEmpty ? ["#008080"] : values).map(color), startPoint: .leading, endPoint: .trailing)
    }
}

struct LanguageBadge: View {
    @Environment(\.mapLabelSize) private var mapSize
    let name: String
    let table: TablePackage?
    var grouping: TableGrouping? = nil
    @AppStorage("colorScheme") private var colorScheme = "atlas"
    var body: some View {
        let scheme = grouping == .atlas || grouping == .dictionary ? grouping! : (colorScheme == "dictionary" ? .dictionary : .atlas)
        let colors = table.map { TableColors.hexes(TableColors.raw($0, scheme)) } ?? []
        Text(name).font(mapSize.map { Font.system(size: $0) } ?? .subheadline).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(TableColors.gradient(colors), in: RoundedRectangle(cornerRadius: 5))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct GroupColorSwatch: View {
    let tables: [TablePackage]
    let grouping: TableGrouping
    var body: some View { EmptyView() }
}

enum ToneDisplay {
    static let styles: [(String, String)] = [("pinYin", "拼音：12345678"), ("baSheng", "八聲：①③⑤⑦"), ("siSheng", "四聲：①②③④"), ("hanzi", "漢字：平上去入"), ("corners", "四角：꜀平꜂上去꜄入꜆"), ("stacked", "並排：上排調值、下排調類"), ("hidden", "隱藏")]
    struct Part: Identifiable, Codable, Equatable {
        let id: Int
        let base: String
        let pitch: String
        let tone: String
        let stacked: Bool
    }
    private final class ToneMap {
        let values: [String: [String]]
        init(_ values: [String: [String]]) { self.values = values }
    }
    private static let mappings: NSCache<NSString, ToneMap> = {
        let cache = NSCache<NSString, ToneMap>(); cache.countLimit = 512; return cache
    }()
    private static let tokenRegex = try! NSRegularExpression(pattern: "[0-9]+[a-z]?")
    static func mapping(_ table: TablePackage?) -> [String: [String]] {
        guard let raw = table?.metadata?["聲調"] else { return [:] }
        if let found = mappings.object(forKey: raw as NSString) { return found.values }
        let map = raw.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        mappings.setObject(ToneMap(map), forKey: raw as NSString)
        return map
    }
    static func circled(_ text: String) -> String {
        let source = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let output = Array("⓪①②③④⑤⑥⑦⑧⑨ⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩ")
        return text.map { c in source.firstIndex(where: { String($0) == c.lowercased() }).map { String(output[$0]) } ?? String(c) }.joined()
    }
    static func curve(_ text: String) -> String {
        let input = text.count == 2 && text.first == text.last ? String(text.prefix(1)) : text
        let levels = Array("˩˨˧˦˥")
        return input.map { c in c.wholeNumberValue.flatMap { (1...5).contains($0) ? String(levels[$0-1]) : nil } ?? String(c) }.joined()
    }
    // Only recognized tone tokens are changed. Unknown readings remain verbatim.
    static func parts(_ raw: String, table: TablePackage?, style: String, pitchStyle: String) -> [Part] {
        let map = mapping(table)
        guard !map.isEmpty else {
            return [Part(id: 0, base: raw, pitch: "", tone: "", stacked: false)]
        }
        let ns = raw as NSString
        var cursor = 0
        var result = [Part]()
        for match in tokenRegex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range)
            guard let values = map[key], values.count >= 5 else { continue }
            let base = ns.substring(with: NSRange(location: cursor, length: match.range.location-cursor))
            var pitch = pitchStyle == "hidden" ? "" : (pitchStyle == "number" ? values[0] : curve(values[0]))
            let tone: String
            switch style {
            case "pinYin": tone = key
            case "siSheng": tone = circled(values[2])
            case "hanzi": tone = values[3]
            case "corners": tone = values[4]
            case "stacked": tone = values[2]; pitch = values[0]
            case "hidden": tone = ""
            default: tone = circled(key)
            }
            result.append(Part(id: result.count, base: base, pitch: pitch, tone: tone, stacked: style == "stacked"))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { result.append(Part(id: result.count, base: ns.substring(from: cursor), pitch: "", tone: "", stacked: false)) }
        return result
    }
    static func text(_ raw: String, table: TablePackage?, style: String, pitch: String) -> String {
        parts(raw, table: table, style: style, pitchStyle: pitch).map { $0.base + $0.pitch + $0.tone }.joined()
    }
}

struct PronunciationView: View {
    let raw: String
    let table: TablePackage?
    @AppStorage("toneStyle") private var style = "baSheng"
    @AppStorage("pitchStyle") private var pitch = "curve"
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .center, spacing: 0) {
            ForEach(ToneDisplay.parts(raw, table: table, style: style, pitchStyle: pitch)) { part in
                Text(part.base)
                if part.stacked {
                    VStack(spacing: 0) { Text(part.pitch); Text(part.tone) }.font(.caption2)
                } else {
                    Text(part.pitch).font(pitch == "number" ? .caption : .body)
                    Text(part.tone)
                }
            }
        }.lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ToneDisplay.text(raw, table: table, style: style, pitch: pitch))
    }
}
