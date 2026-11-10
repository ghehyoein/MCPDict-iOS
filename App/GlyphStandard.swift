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
        let fallback = CTFontCreateForStringWithLanguage(base as CTFont, "骨" as CFString,
            CFRange(location: 0, length: 1), standard.language as CFString)
        let descriptor = base.fontDescriptor.addingAttributes([
            .cascadeList: [UIFontDescriptor(name: CTFontCopyPostScriptName(fallback) as String, size: base.pointSize)],
            UIFontDescriptor.AttributeName(rawValue: kCTFontLanguagesAttribute as String): [standard.language]
        ])
        let font = UIFont(descriptor: descriptor, size: base.pointSize)
        fontCache.setObject(font, forKey: key)
        return font
    }
    static func apply(to text: NSMutableAttributedString, standard: Self = .current) {
        text.addAttribute(NSAttributedString.Key(kCTLanguageAttributeName as String), value: standard.language,
                          range: NSRange(location: 0, length: text.length))
    }
}
