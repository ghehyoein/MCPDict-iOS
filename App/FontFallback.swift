import UIKit
import CoreText

enum FontFallback {
    private static let supportCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>(); cache.countLimit = 8192; return cache
    }()
    private static func supports(_ font: UIFont, text: String) -> Bool {
        let key = (font.fontName + "|" + text) as NSString
        if let cached = supportCache.object(forKey: key) { return cached.boolValue }
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        let supported = CTFontGetGlyphsForCharacters(font as CTFont, chars, &glyphs, chars.count)
        supportCache.setObject(NSNumber(value: supported), forKey: key)
        return supported
    }
    static func apply(to text: NSMutableAttributedString) {
        var offset = 0
        for scalar in text.string.unicodeScalars {
            let length = scalar.utf16.count, range = NSRange(location: offset, length: length)
            let base = text.attribute(.font, at: offset, effectiveRange: nil) as? UIFont ?? .systemFont(ofSize: 17)
            let c = scalar.value
            if (0x2E5...0x2E9).contains(c), let tone = UIFont(name: "Voces-Regular", size: base.pointSize) {
                text.addAttribute(.font, value: tone, range: range)
            } else if !supports(base, text: String(scalar)) {
                for name in ["Charis-Regular", "PlangothicP1", "PlangothicP2"] {
                    if let fallback = UIFont(name: name, size: base.pointSize), supports(fallback, text: String(scalar)) {
                        text.addAttribute(.font, value: fallback, range: range); break
                    }
                }
            }
            offset += length
        }
    }
}
