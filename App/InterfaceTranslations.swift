import Foundation

// Shared [key] identifiers in four UTF-8 files. Source data never enters this catalog.
enum InterfaceTranslations {
    enum FormatError: Error { case invalidLine, duplicateKey, emptyValue }
    static func parse(_ input: String) throws -> [String: String] {
        let source = input.hasPrefix("\u{FEFF}") ? String(input.dropFirst()) : input
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result = [String: String](), key: String?, value = [String]()
        func finish() throws {
            guard let current = key else { return }
            while value.last == "" { value.removeLast() }
            guard !value.isEmpty else { throw FormatError.emptyValue }
            guard result[current] == nil else { throw FormatError.duplicateKey }
            result[current] = value.joined(separator: "\n")
        }
        for line in lines {
            if line.hasPrefix("["), line.hasSuffix("]"), line.count > 2 {
                try finish()
                key = String(line.dropFirst().dropLast()); value = []
            } else if key != nil { value.append(line) }
            else if !line.isEmpty { throw FormatError.invalidLine }
        }
        try finish()
        return result
    }
    private static let catalogs: [String: [String: String]] = {
        var loaded = [String: [String: String]]()
        for language in ["hant", "hans", "ja", "en"] {
            guard let url = Bundle.main.url(forResource: language, withExtension: "txt", subdirectory: "InterfaceTexts"),
                  let source = try? String(contentsOf: url, encoding: .utf8),
                  let values = try? parse(source) else {
                assertionFailure("Missing or invalid interface text catalog: " + language)
                continue
            }
            loaded[language] = values
        }
        return loaded
    }()
    private static let patterns: [(String, NSRegularExpression)] = (catalogs["hant"] ?? [:]).keys.sorted().compactMap { key in
        guard key.contains("{0}") else { return nil }
        var pattern = key.components(separatedBy: "{0}").map(NSRegularExpression.escapedPattern(for:)).joined(separator: "([0-9]+)")
        pattern = pattern.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: "{1}"), with: "([0-9]+)")
        guard let expression = try? NSRegularExpression(pattern: "^" + pattern + "$") else { return nil }
        return (key, expression)
    }
    static func text(_ source: String, language: String) -> String? {
        let values = catalogs[language] ?? catalogs["hant"] ?? [:]
        if let value = values[source] { return value }
        let range = NSRange(source.startIndex..., in: source)
        for (key, pattern) in patterns {
            guard let match = pattern.firstMatch(in: source, range: range), var result = values[key] else { continue }
            for i in 1..<match.numberOfRanges {
                result = result.replacingOccurrences(of: "{\(i - 1)}", with: (source as NSString).substring(with: match.range(at: i)))
            }
            return result
        }
        return nil
    }
}
