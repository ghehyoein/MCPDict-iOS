import SwiftUI
import CoreText

enum GlyphStandard: String, CaseIterable, Identifiable {
    case system = "", mainland = "zh-Hans-CN", hongKong = "zh-Hant-HK", taiwan = "zh-Hant-TW", japan = "ja-Jpan-JP", korea = "ko-Kore-KR"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "默認"
        case .mainland: return "大陸"
        case .hongKong: return "香港"
        case .taiwan: return "臺灣"
        case .japan: return "日本"
        case .korea: return "韓國"
        }
    }
    // Android's default_locale is ko-Kore-KR; this does not change interface translations.
    var language: String { self == .system ? "ko-Kore-KR" : rawValue }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: "glyphStandard") ?? "") ?? .system }
    private static let fontCache = NSCache<NSString, UIFont>()
    static func font(_ base: UIFont, standard: Self = .current) -> UIFont {
        let key = "\(base.fontName)|\(base.pointSize)|\(base.fontDescriptor.symbolicTraits.rawValue)|\(standard.language)" as NSString
        if let cached = fontCache.object(forKey: key) { return cached }
        let fallback = regionalFont(base, standard: standard)
        let descriptor = base.fontDescriptor.addingAttributes([
            .cascadeList: [fallback.fontDescriptor],
            UIFontDescriptor.AttributeName(rawValue: kCTFontLanguagesAttribute as String): [standard.language]
        ])
        let font = UIFont(descriptor: descriptor, size: base.pointSize)
        fontCache.setObject(font, forKey: key)
        return font
    }
    private static func regionalFont(_ base: UIFont, standard: Self) -> UIFont {
        let serif = base.fontName.contains("NewYork") || base.fontName.contains("Times") || base.fontName.contains("Songti") || base.fontName.contains("Mincho")
        let names: [String]
        switch standard {
        case .mainland: names = serif ? ["SongtiSC-Regular", "PingFangSC-Regular"] : ["PingFangSC-Regular"]
        case .hongKong: names = serif ? ["SongtiTC-Regular", "PingFangHK-Regular"] : ["PingFangHK-Regular"]
        case .taiwan: names = serif ? ["SongtiTC-Regular", "PingFangTC-Regular"] : ["PingFangTC-Regular"]
        case .japan: names = serif ? ["HiraMinProN-W3", "HiraginoSans-W3"] : ["HiraginoSans-W3", "HiraKakuProN-W3"]
        case .system, .korea: names = serif ? ["AppleMyungjo", "AppleSDGothicNeo-Regular"] : ["AppleSDGothicNeo-Regular"]
        }
        let chosen = names.compactMap { UIFont(name: $0, size: base.pointSize) }.first ?? base
        let traits = base.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic])
        return UIFont(descriptor: chosen.fontDescriptor.withSymbolicTraits(traits) ?? chosen.fontDescriptor, size: base.pointSize)
    }
    static func apply(to text: NSMutableAttributedString, standard: Self = .current) {
        text.addAttribute(NSAttributedString.Key(kCTLanguageAttributeName as String), value: standard.language,
                          range: NSRange(location: 0, length: text.length))
        // A system-font cascade can ignore Japanese language hints for unified Han.
        // Assign the regional font to CJK runs explicitly; keep IPA/Latin and the
        // underlying characters untouched, including supplementary-plane Han.
        var offset = 0
        for scalar in text.string.unicodeScalars {
            let length = scalar.utf16.count
            let c = scalar.value
            if (0x2E80...0x9FFF).contains(c) || (0xF900...0xFAFF).contains(c) || (0x20000...0x323AF).contains(c) {
                let base = text.attribute(.font, at: offset, effectiveRange: nil) as? UIFont ?? .systemFont(ofSize: 17)
                text.addAttribute(.font, value: regionalFont(base, standard: standard), range: NSRange(location: offset, length: length))
            }
            offset += length
        }
    }
}
