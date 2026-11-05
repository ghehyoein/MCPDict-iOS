import Foundation

enum InterfaceLanguage {
    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 8192; cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
    static func text(_ text: String, script: String) -> String {
        guard script == "hans" else { return text }
        let key = text as NSString
        if let existing = cache.object(forKey: key) { return existing as String }
        let converted = (text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text)
            .replacingOccurrences(of: "设定", with: "设置")
        cache.setObject(converted as NSString, forKey: key, cost: (text.utf8.count + converted.utf8.count))
        return converted
    }
    static func matches(_ text: String, _ query: String) -> Bool {
        self.text(text, script: "hans").localizedStandardContains(self.text(query, script: "hans"))
    }
}

func ui(_ text: String) -> String {
    InterfaceLanguage.text(text, script: UserDefaults.standard.string(forKey: "uiLanguage") ?? "hant")
}
