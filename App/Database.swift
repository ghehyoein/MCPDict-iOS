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
    case character = "漢字", pronunciation = "發音", note = "註釋"
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

    // Reuse one compiled INSERT for every row in a TSV instead of preparing it
    // once per pronunciation. The connection remains owned by its importing task.
    func batch(_ sql: String, _ body: (_ execute: ([String]) throws -> Void) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DictionaryFailure(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        try body { values in
            try Task.checkCancellation()
            sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            guard values.count == Int(sqlite3_bind_parameter_count(statement)) else {
                throw DictionaryFailure(message: "寫入參數數量不符")
            }
            for (index, value) in values.enumerated() {
                let code = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                guard code == SQLITE_OK else { throw DictionaryFailure(message: "寫入參數綁定失敗") }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DictionaryFailure(message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    func transaction(_ body: () throws -> Void) throws {
        _ = try rows("BEGIN IMMEDIATE")
        do { try body(); _ = try rows("COMMIT") }
        catch { _ = try? rows("ROLLBACK"); throw error }
    }
    func removeLanguages(_ names: [String]) throws {
        // FTS already indexes language names. Exact equality still guards against
        // tokenizer normalization, punctuation and similarly named language points.
        for start in stride(from: 0, to: names.count, by: 128) {
            let batch = Array(names[start..<min(start + 128, names.count)])
            let indexed = batch.filter { $0.rangeOfCharacter(from: .alphanumerics) != nil }
            let fallback = batch.filter { $0.rangeOfCharacter(from: .alphanumerics) == nil }
            if !indexed.isEmpty {
                let expression = "語言 : (" + indexed.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " OR ") + ")"
                let json = String(data: try JSONEncoder().encode(indexed), encoding: .utf8)!
                _ = try rows("DELETE FROM langs WHERE rowid IN (SELECT rowid FROM langs WHERE langs MATCH ? AND 語言 IN (SELECT value FROM json_each(?)))", [expression, json])
            }
            if !fallback.isEmpty {
                let json = String(data: try JSONEncoder().encode(fallback), encoding: .utf8)!
                _ = try rows("DELETE FROM langs WHERE 語言 IN (SELECT value FROM json_each(?))", [json])
            }
        }
        if !names.isEmpty {
            let json = String(data: try JSONEncoder().encode(names), encoding: .utf8)!
            _ = try rows("DELETE FROM info WHERE 簡稱 IN (SELECT value FROM json_each(?))", [json])
        }
    }

    // When most tables are removed, copy the small retained set into a fresh
    // staging database instead of journaling and deleting millions of old rows.
    // Preserve row IDs, extra metadata columns and independent reference data.
    func copyRetainedLanguages(from source: URL, names: [String]) throws {
        _ = try rows("ATTACH DATABASE ? AS retained", [source.path])
        defer { _ = try? rows("DETACH DATABASE retained") }
        func quoted(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        try transaction {
            var columns = [String: String]()
            for name in ["langs", "info", "mcpdict"] {
                guard let sql = try rows("SELECT sql FROM retained.sqlite_master WHERE name=?", [name]).first?["sql"] else {
                    throw DictionaryFailure(message: "字表結構缺失")
                }
                _ = try rows(sql)
                let fields = try rows("PRAGMA retained.table_info(\(name))").compactMap { $0["name"] }
                columns[name] = (["rowid"] + fields).map(quoted).joined(separator: ",")
            }
            let languageColumns = columns["langs"]!
            for start in stride(from: 0, to: names.count, by: 128) {
                try Task.checkCancellation()
                let batch = Array(names[start..<min(start + 128, names.count)])
                let indexed = batch.filter { $0.rangeOfCharacter(from: .alphanumerics) != nil }
                let fallback = batch.filter { $0.rangeOfCharacter(from: .alphanumerics) == nil }
                for (group, useIndex) in [(indexed, true), (fallback, false)] where !group.isEmpty {
                    let json = String(data: try JSONEncoder().encode(group), encoding: .utf8)!
                    let expression = "語言 : (" + group.map { quoted($0) }.joined(separator: " OR ") + ")"
                    let condition = (useIndex ? "langs MATCH ? AND " : "") + "語言 IN (SELECT value FROM json_each(?))"
                    _ = try rows("INSERT INTO main.langs (\(languageColumns)) SELECT \(languageColumns) FROM retained.langs WHERE \(condition)", useIndex ? [expression, json] : [json])
                }
            }
            let json = String(data: try JSONEncoder().encode(names), encoding: .utf8)!
            let infoColumns = columns["info"]!
            _ = try rows("INSERT INTO main.info (\(infoColumns)) SELECT \(infoColumns) FROM retained.info WHERE 簡稱 IN (SELECT value FROM json_each(?))", [json])
            let referenceColumns = columns["mcpdict"]!
            _ = try rows("INSERT INTO main.mcpdict (\(referenceColumns)) SELECT \(referenceColumns) FROM retained.mcpdict")
        }
    }

    func validate(requireSample: Bool = true, checkIntegrity: Bool = true) throws {
        if checkIntegrity {
            guard try rows("PRAGMA quick_check").first?.values.first == "ok" else {
                throw DictionaryFailure(message: "資料庫完整性檢查失敗")
            }
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
    func activate(_ url: URL, requireSample: Bool = true, checkIntegrity: Bool = true, commitPointer: () throws -> Void) async throws {
        try await Task.detached(priority: .utility) {
            let candidate = try SQLiteConnection(url: url)
            try candidate.validate(requireSample: requireSample, checkIntegrity: checkIntegrity)
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
            let cantonese = ReadingFormatEngine.shared.canonicalCantonese(text) ?? text
            sql = "SELECT rowid AS id, 字組, 語言, 讀音, 註釋 FROM langs WHERE (instr(讀音, ?) > 0 OR (語言 = ? AND instr(讀音, ?) > 0))"
            bindings = [text, "香港", cantonese]
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

    func toolLanguageRows(_ language: String) throws -> [Reading] {
        guard let connection else { throw DictionaryFailure(message: "請先在「字表」頁下載詞典") }
        return try connection.rows("SELECT rowid AS id, 字組, 語言, 讀音, 註釋 FROM langs WHERE langs MATCH ? AND 語言 = ?", ["語言 : \"" + language.replacingOccurrences(of: "\"", with: "\"\"") + "\"", language]).map {
            Reading(id: Int64($0["id"] ?? "0") ?? 0, characters: $0["字組"] ?? "", language: $0["語言"] ?? "", pronunciation: $0["讀音"] ?? "", note: $0["註釋"] ?? "")
        }
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
