import Foundation

// The active database remains immutable while this private copy is updated.
// Readings and their installation metadata commit in the SAME SQLite transaction;
// after a process exit, SQLite rolls back only the unfinished table.
final class TableDownloadCheckpoint {
    private struct Manifest: Codable {
        let databaseFile: String
        let previousFile: String?
        let catalogVersion: String
        var ready: TableInstallation?
    }
    static func marker(in root: URL) -> URL { root.appendingPathComponent("download-checkpoint.json") }
    private var connection: SQLiteConnection?

    init(root: URL, previous: TableInstallation?, version: String) throws {
        let file = root.appendingPathComponent(UUID().uuidString + ".db")
        do {
            if let old = previous?.databaseFile {
                try FileManager.default.copyItem(at: root.appendingPathComponent(old), to: file)
            }
            let db = try SQLiteConnection(url: file, readOnly: false)
            db.enableCancellation()
            // A memory journal cannot recover a process killed during a write and
            // can consume hundreds of MB when updating a large installation.
            _ = try db.rows("PRAGMA journal_mode=DELETE")
            _ = try db.rows("PRAGMA synchronous=FULL")
            _ = try db.rows("PRAGMA cache_size=-8192")
            try db.transaction {
                _ = try db.rows("CREATE TABLE mcpdict_download_tables(id TEXT PRIMARY KEY, package TEXT NOT NULL)")
                _ = try db.rows("CREATE TABLE mcpdict_download_progress(completed INTEGER NOT NULL)")
                _ = try db.rows("INSERT INTO mcpdict_download_progress VALUES(0)")
                try db.batch("INSERT INTO mcpdict_download_tables VALUES(?,?)") { insert in
                    for table in previous?.tables ?? [] {
                        try insert([table.id, String(decoding: JSONEncoder().encode(table), as: UTF8.self)])
                    }
                }
            }
            let manifest = Manifest(databaseFile: file.lastPathComponent, previousFile: previous?.databaseFile, catalogVersion: version)
            try JSONEncoder().encode(manifest).write(to: Self.marker(in: root), options: .atomic)
            connection = db
        } catch {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(atPath: file.path + "-journal")
            throw error
        }
    }

    func merge(_ table: TablePackage, from shard: URL, beforeCommit: () throws -> Void = {}) throws {
        guard let db = connection else { throw DictionaryFailure(message: "無法打開資料庫") }
        try db.attachReadOnly(shard, as: "downloaded")
        defer { _ = try? db.rows("DETACH DATABASE downloaded") }
        try db.transaction {
            if try db.rows("SELECT 1 FROM sqlite_master WHERE name='langs'").isEmpty {
                for name in ["langs", "info", "mcpdict"] {
                    guard let sql = try db.rows("SELECT sql FROM downloaded.sqlite_master WHERE name=?", [name]).first?["sql"] else {
                        throw DictionaryFailure(message: "字表結構缺失")
                    }
                    _ = try db.rows(SQLiteConnection.storageSchema(sql, table: name))
                }
            }
            try db.removeLanguages([table.name])
            _ = try db.rows("INSERT INTO main.langs SELECT 字組,語言,讀音,註釋 FROM downloaded.langs ORDER BY rowid")
            _ = try db.rows("INSERT INTO main.info(簡稱,語言) SELECT 簡稱,語言 FROM downloaded.info")
            _ = try db.rows("INSERT OR REPLACE INTO mcpdict_download_tables VALUES(?,?)", [table.id, String(decoding: JSONEncoder().encode(table), as: UTF8.self)])
            _ = try db.rows("UPDATE mcpdict_download_progress SET completed=completed+1")
            try beforeCommit()
        }
    }

    func close() { connection = nil }

    // Called either after the download stops or on the next app launch. No bulk
    // merge remains here: only metadata, validation and an atomic pointer switch.
    static func recover(in root: URL, repository: DictionaryRepository, checkIntegrity: Bool) async throws -> TableInstallation? {
        let marker = marker(in: root), index = root.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        var manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: marker))
        guard manifest.databaseFile.range(of: "^[0-9A-Fa-f-]{36}\\.db$", options: .regularExpression) != nil else {
            throw DictionaryFailure(message: "本地資料索引錯誤")
        }
        let current = FileManager.default.fileExists(atPath: index.path)
            ? try JSONDecoder().decode(TableInstallation.self, from: Data(contentsOf: index)) : nil
        let file = root.appendingPathComponent(manifest.databaseFile)
        func discard() {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(atPath: file.path + "-journal")
            try? FileManager.default.removeItem(at: marker)
        }
        if current?.databaseFile == manifest.databaseFile {
            try? FileManager.default.removeItem(at: marker)
            return current
        }
        guard current?.databaseFile == manifest.previousFile else {
            // Another committed installation wins over an obsolete checkpoint.
            discard(); return current
        }
        let state: TableInstallation
        do {
            // A writable open permits SQLite to recover a hot rollback journal.
            let db = try SQLiteConnection(url: file, readOnly: false)
            if let ready = manifest.ready {
                guard ready.databaseFile == manifest.databaseFile else { throw DictionaryFailure(message: "本地資料索引錯誤") }
                state = ready
            } else {
                let count = Int(try db.rows("SELECT completed FROM mcpdict_download_progress").first?["completed"] ?? "") ?? 0
                guard count > 0 else { discard(); return current }
                let tables = try db.rows("SELECT package FROM mcpdict_download_tables ORDER BY id").map {
                    try JSONDecoder().decode(TablePackage.self, from: Data(($0["package"] ?? "").utf8))
                }
                state = TableInstallation(catalogVersion: manifest.catalogVersion, tables: tables, databaseFile: manifest.databaseFile)
            }
            for table in state.tables { try table.validate() }
            try db.validate(requireSample: false, checkIntegrity: checkIntegrity)
            // Persist the final metadata before removing temporary checkpoint
            // tables, so a kill at any point of activation is also recoverable.
            manifest.ready = state
            try JSONEncoder().encode(manifest).write(to: marker, options: .atomic)
            try db.transaction {
                _ = try db.rows("DROP TABLE IF EXISTS mcpdict_download_tables")
                _ = try db.rows("DROP TABLE IF EXISTS mcpdict_download_progress")
            }
        }
        let encoded = try JSONEncoder().encode(state)
        try await repository.activate(file, requireSample: false, checkIntegrity: false) {
            try encoded.write(to: index, options: .atomic)
        }
        try? FileManager.default.removeItem(at: marker)
        if let old = current?.databaseFile { try? FileManager.default.removeItem(at: root.appendingPathComponent(old)) }
        return state
    }
}
