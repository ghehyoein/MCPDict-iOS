import Foundation
import SQLite3

struct DictionaryFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Reading: Identifiable, Codable, Hashable {
    let id: Int64
    let characters: String
    let language: String
    let pronunciation: String
    let note: String
}

struct ReadingContentKey: Hashable {
    let characters: String
    let language: String
    let pronunciation: String
    let note: String
    init(_ reading: Reading) {
        characters = reading.characters; language = reading.language
        pronunciation = reading.pronunciation; note = reading.note
    }
}

enum SearchMode: String, CaseIterable, Identifiable {
    case character = "漢字", pronunciation = "讀音", note = "註釋"
    var id: String { rawValue }
    var column: String {
        switch self {
        case .character: return "字組"
        case .pronunciation: return "讀音"
        case .note: return "註釋"
        }
    }
}

// Instances never leave the repository actor. All user values use bound parameters.
final class SQLiteConnection {
    private var db: OpaquePointer?
    init(url: URL, readOnly: Bool = true) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(url.path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "無法打開資料庫"
            if let db { sqlite3_close(db) }
            db = nil
            throw DictionaryFailure(message: message)
        }
    }
    deinit { sqlite3_close(db) }

    func rows(_ sql: String, _ values: [String] = []) throws -> [[String: String]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DictionaryFailure(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in values.enumerated() {
            let result = value.withCString {
                sqlite3_bind_text(stmt, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard result == SQLITE_OK else { throw DictionaryFailure(message: "查詢參數綁定失敗") }
        }
        let columns = (0..<sqlite3_column_count(stmt)).map { String(cString: sqlite3_column_name(stmt, $0)) }
        var result = [[String: String]]()
        while true {
            try Task.checkCancellation()
            let code = sqlite3_step(stmt)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { throw DictionaryFailure(message: String(cString: sqlite3_errmsg(db))) }
            var row = [String: String]()
            for (index, key) in columns.enumerated() {
                row[key] = sqlite3_column_text(stmt, Int32(index)).map { String(cString: $0) } ?? ""
            }
            result.append(row)
        }
    }

    func validate(requireSample: Bool = true) throws {
        guard try rows("PRAGMA quick_check").first?.values.first == "ok" else {
            throw DictionaryFailure(message: "資料庫完整性檢查失敗")
        }
        for (table, fields) in ["langs": ["字組", "語言", "讀音", "註釋"], "info": ["簡稱", "語言"], "mcpdict": ["漢字"]] {
            let actual = Set(try rows("PRAGMA table_info(\(table))").compactMap { $0["name"] })
            guard Set(fields).isSubset(of: actual) else { throw DictionaryFailure(message: "不相容的資料表：\(table)") }
        }
        let sample = try rows("SELECT rowid FROM langs WHERE langs MATCH ? LIMIT 1", ["字組 : \"中\""])
        guard !requireSample || !sample.isEmpty else {
            throw DictionaryFailure(message: "FTS5 查字測試未通過")
        }
    }
}

actor DictionaryRepository {
    private var connection: SQLiteConnection?
    private var statisticsCache = [String: [String: String]]()

    private var activeURL: URL?
    func open(_ url: URL) throws {
        guard activeURL != url else { return }
        connection = try SQLiteConnection(url: url); activeURL = url; statisticsCache = [:]
    }

    // Validate before touching the active connection; failed activation preserves it.
    func activate(_ url: URL, requireSample: Bool = true, commitPointer: () throws -> Void) async throws {
        try await Task.detached(priority: .utility) {
            let candidate = try SQLiteConnection(url: url)
            try candidate.validate(requireSample: requireSample)
        }.value
        try Task.checkCancellation()
        let candidate = try SQLiteConnection(url: url)
        try commitPointer()
        connection = candidate; activeURL = url
        statisticsCache = [:]
    }

    func clear(commitPointer: () throws -> Void) throws {
        try commitPointer()
        connection = nil; activeURL = nil
        statisticsCache = [:]
    }

    func languages() throws -> [String] {
        guard let connection else { return [] }
        return try connection.rows("SELECT DISTINCT 簡稱 FROM info WHERE 簡稱 != '' ORDER BY 簡稱").compactMap { $0["簡稱"] }
    }

    // Use the existing FTS language index to narrow small selections before substring
    // matching. Keep the exact SQL filter too: FTS normalization is not identity.
    private func languageCandidates(_ names: [String]) -> String? {
        guard !names.isEmpty, names.count <= 256,
              names.allSatisfy({ $0.rangeOfCharacter(from: .alphanumerics) != nil }) else { return nil }
        let quoted = names.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return "語言 : (" + quoted.joined(separator: " OR ") + ")"
    }

    func search(_ input: String, mode: SearchMode, language: String, offset: Int = 0, languages: [String]? = nil, limit: Int = 100) throws -> [Reading] {
        guard let connection else { throw DictionaryFailure(message: "請先在「字表」頁下載詞典") }
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .character && text.uppercased().hasPrefix("U+"),
           let number = UInt32(text.dropFirst(2), radix: 16), let scalar = UnicodeScalar(number) {
            text = String(scalar)
        }
        guard !text.isEmpty else { return [] }
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let terms = mode == .character ? text.map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : [text]
        let expression = "\(mode.column) : (" + terms.map(quote).joined(separator: " OR ") + ")"
        var sql = "SELECT rowid AS id, 字組, 語言, 讀音, 註釋 FROM langs WHERE langs MATCH ?"
        var bindings = [expression]
        if mode == .pronunciation {
            sql = "SELECT rowid AS id, 字組, 語言, 讀音, 註釋 FROM langs WHERE instr(讀音, ?) > 0"
            bindings = [text]
        }
        if languages?.isEmpty == true { return [] }
        if mode == .pronunciation, let candidates = languageCandidates(languages ?? (language.isEmpty ? [] : [language])) {
            sql += " AND langs MATCH ?"
            bindings.append(candidates)
        }
        if let languages {
            sql += " AND 語言 IN (SELECT value FROM json_each(?))"
            bindings.append(String(data: try JSONEncoder().encode(languages), encoding: .utf8)!)
        } else if !language.isEmpty { sql += " AND 語言 = ?"; bindings.append(language) }
        if mode == .pronunciation {
            sql += " ORDER BY CASE WHEN instr(讀音, ?) = 1 THEN 0 ELSE 1 END, rowid LIMIT ? OFFSET ?"
            bindings.append(text)
        } else { sql += " ORDER BY rowid LIMIT ? OFFSET ?" }
        bindings.append(String(limit < 0 ? -1 : max(1, limit)))
        bindings.append(String(max(0, offset)))
        let termSet = Set(terms)
        return try connection.rows(sql, bindings).map {
            let group = $0["字組"] ?? ""
            let displayed = mode == .character ? group.split(whereSeparator: { $0.isWhitespace }).filter { termSet.contains(String($0)) }.joined(separator: " ") : group
            return Reading(id: Int64($0["id"] ?? "0") ?? 0, characters: displayed, language: $0["語言"] ?? "", pronunciation: $0["讀音"] ?? "", note: $0["註釋"] ?? "")
        }
    }
    func searchAllCharacters(_ input: String, language: String, languages: [String]? = nil) throws -> [Reading] {
        try search(input, mode: .character, language: language, languages: languages, limit: -1)
    }

    func tableStatistics(_ language: String) throws -> [String: String] {
        guard let connection else { return [:] }
        if let cached = statisticsCache[language] { return cached }
        let candidates = languageCandidates([language])
        let sql = "SELECT 字組, 讀音, 註釋 FROM langs WHERE 語言 = ?" + (candidates == nil ? "" : " AND langs MATCH ?")
        let rows = try connection.rows(sql, [language] + (candidates.map { [$0] } ?? []))
        guard !rows.isEmpty else { return [:] }
        var chars = Set<String>(), syllables = Set<String>(), toneless = Set<String>(), boxes = Set<String>()
        for row in rows {
            let pronunciation = row["讀音"] ?? ""
            for ch in (row["字組"] ?? "").split(whereSeparator: { $0.isWhitespace }) {
                if ch == "□" { boxes.insert(pronunciation + "\t" + (row["註釋"] ?? "")) }
                else { chars.insert(String(ch)) }
            }
            syllables.insert(pronunciation)
            toneless.insert(String(pronunciation.prefix { !$0.isNumber }))
        }
        let result = ["字數": String(chars.count + boxes.count), "□數": String(boxes.count), "音節數": String(syllables.count), "不帶調音節數": String(toneless.count)]
        statisticsCache[language] = result
        return result
    }

    func searchAll(_ input: String, mode: SearchMode, language: String, languages: [String]?) throws -> [Reading] {
        try search(input, mode: mode, language: language, languages: languages, limit: -1)
    }

}
