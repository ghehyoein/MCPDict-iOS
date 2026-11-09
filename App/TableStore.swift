import Foundation
import CryptoKit

struct TablePackage: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let fullName: String
    let atlas: [String]
    let dictionary: [String]
    let administrative: [String]
    let source: String
    let sourceCommit: String
    let recordCount: Int
    let size: Int64
    let sha256: String
    let url: URL
    var metadata: [String: String]? = nil
    var location: TableLocation? = nil
    var atlasColor: String? = nil
    var dictionaryColor: String? = nil
    var format: String? = nil
    var gitBlob: String? = nil
    var isUpstream: Bool { format == "upstream-tsv-v1" }
    var localName: String { id + "-" + sha256 + ".db" }
    func validate() throws {
        guard id.range(of: "^[0-9a-f]{24}$", options: .regularExpression) != nil,
              sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              sourceCommit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              size > 0, size < 1_000_000_000, (isUpstream || recordCount > 0), !name.isEmpty,
              url.scheme == "https", (isUpstream ? (url.host == "raw.githubusercontent.com" && url.path == "/osfans/MCPDict/\(sourceCommit)/tools/tables/output/\(name).tsv" && gitBlob?.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil) : (url.host == "github.com" && url.path.contains("/releases/download/"))) else {
            throw DictionaryFailure(message: "字表資料包格式不相容")
        }
    }
}

struct TableCatalog: Codable {
    let schemaVersion: Int
    let version: String
    let sourceRepository: String
    let sourceCommit: String
    let scope: String
    let tables: [TablePackage]
    func validate() throws {
        guard schemaVersion == 1, sourceRepository == "https://github.com/osfans/MCPDict",
              Set(tables.map(\.id)).count == tables.count,
              Set(tables.map(\.name)).count == tables.count else {
            throw DictionaryFailure(message: "字表目錄格式不相容")
        }
        for table in tables { try table.validate() }
    }
}

struct TableInstallation: Codable {
    let catalogVersion: String
    let tables: [TablePackage]
    let databaseFile: String?
}

actor TableStore {
    static let catalogURL = URL(string: "https://github.com/ghehyoein/MCPDict-iOS/releases/download/tables-latest/catalog.json")!
    private let repository: DictionaryRepository
    private let root: URL
    private var busy = false
    private let bundledRoot: URL?
    private let fetchTable: @Sendable (URL) async throws -> Data
    init(repository: DictionaryRepository, root: URL? = nil, bundledRoot: URL? = Bundle.main.resourceURL?.appendingPathComponent("BundledTables"), fetchTable: @escaping @Sendable (URL) async throws -> Data = { try await UpstreamTables.get($0, limit: 200_000_000) }) {
        self.bundledRoot = bundledRoot
        self.fetchTable = fetchTable
        self.repository = repository
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tables", isDirectory: true)
    }
    private var index: URL { root.appendingPathComponent("index.json") }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func installBundledTablesIfNeeded() async throws {
        guard let bundledRoot, FileManager.default.fileExists(atPath: bundledRoot.appendingPathComponent("catalog.json").path) else { return }
        try prepare()
        let marker = root.appendingPathComponent("bundled-installed")
        let data = try Data(contentsOf: bundledRoot.appendingPathComponent("catalog.json"))
        let catalog = try JSONDecoder().decode(TableCatalog.self, from: data)
        try catalog.validate()
        let metadataMarker = root.appendingPathComponent("bundled-metadata-installed")
        if FileManager.default.fileExists(atPath: marker.path) {
            let processedBundle = try? String(contentsOf: metadataMarker, encoding: .utf8)
            guard processedBundle != catalog.sourceCommit else { return }
            let previousBundle = processedBundle ?? (try? String(contentsOf: marker, encoding: .utf8))
            let cached = cachedCatalog()
            // A different cached commit may be a newer manual update. SHA values
            // cannot establish its age, so preserve that catalog as authoritative.
            let useBundle = cached == nil || cached?.sourceCommit == previousBundle
            _ = try synchronizeMetadata(useBundle ? catalog : cached!)
            if useBundle {
                try data.write(to: root.appendingPathComponent("catalog.json"), options: .atomic)
            }
            // Track metadata separately: never reinstall removed tables or replace
            // the user's readings just because a new app bundles newer archives.
            try Data(catalog.sourceCommit.utf8).write(to: metadataMarker, options: .atomic)
            return
        }
        let previous = try await restore()
        var merged = Dictionary(uniqueKeysWithValues: catalog.tables.map { ($0.id, $0) })
        var overrides = [String]()
        for table in previous?.tables ?? [] where merged[table.id]?.sha256 != table.sha256 {
            merged[table.id] = table; overrides.append(table.name)
        }
        let filename = UUID().uuidString + ".db"
        let destination = root.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: bundledRoot.appendingPathComponent("bundled.db"), to: destination)
        do {
            if !overrides.isEmpty, let oldFile = previous?.databaseFile {
                let db = try SQLiteConnection(url: destination, readOnly: false)
                _ = try db.rows("ATTACH DATABASE ? AS old", [root.appendingPathComponent(oldFile).path])
                let names = String(data: try JSONEncoder().encode(overrides), encoding: .utf8)!
                _ = try db.rows("BEGIN")
                _ = try db.rows("DELETE FROM langs WHERE 語言 IN (SELECT value FROM json_each(?))", [names])
                _ = try db.rows("INSERT INTO langs SELECT 字組, 語言, 讀音, 註釋 FROM old.langs WHERE 語言 IN (SELECT value FROM json_each(?))", [names])
                _ = try db.rows("DELETE FROM info WHERE 簡稱 IN (SELECT value FROM json_each(?))", [names])
                _ = try db.rows("INSERT INTO info SELECT 簡稱, 語言 FROM old.info WHERE 簡稱 IN (SELECT value FROM json_each(?))", [names])
                _ = try db.rows("COMMIT")
                _ = try db.rows("DETACH DATABASE old")
            }
            let state = TableInstallation(catalogVersion: catalog.version, tables: Array(merged.values), databaseFile: filename)
            let encoded = try JSONEncoder().encode(state)
            let pointer = index
            try await repository.activate(destination, requireSample: false) { try encoded.write(to: pointer, options: .atomic) }
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent("catalog.json").path) { try data.write(to: root.appendingPathComponent("catalog.json"), options: .atomic) }
        try Data(catalog.version.utf8).write(to: marker, options: .atomic)
        try Data(catalog.sourceCommit.utf8).write(to: metadataMarker, options: .atomic)
    }
    private func bundledData(for table: TablePackage) throws -> Data? {
        guard table.isUpstream, let bundledRoot else { return nil }
        let file = bundledRoot.appendingPathComponent(table.id + ".tsv")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        var blob = Data("blob \(data.count)\0".utf8); blob.append(data)
        let hash = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        return hash == table.gitBlob ? data : nil
    }
    func restore() async throws -> TableInstallation? {
        try prepare()
        guard FileManager.default.fileExists(atPath: index.path) else { return nil }
        let state = try JSONDecoder().decode(TableInstallation.self, from: Data(contentsOf: index))
        for table in state.tables { try table.validate() }
        if let file = state.databaseFile {
            guard file.range(of: "^[0-9A-Fa-f-]{36}\\.db$", options: .regularExpression) != nil else {
                throw DictionaryFailure(message: "本地資料索引錯誤")
            }
            try await repository.open(root.appendingPathComponent(file))
        }
        return state
    }
    func catalog() async throws -> TableCatalog {
        try await refreshCatalog().catalog
    }
    // Refresh archive information without replacing, adding or removing installed readings.
    func refreshCatalog(progress: @escaping @Sendable (Double) async -> Void = { _ in },
                        fetch: @escaping @Sendable (URL) async throws -> Data = { try await UpstreamTables.get($0) }) async throws -> (catalog: TableCatalog, installation: TableInstallation?) {
        guard !busy else { throw DictionaryFailure(message: "正在處理字表") }
        busy = true
        defer { busy = false }
        let cached = cachedCatalog()
        let latest = try await UpstreamTables.catalog(cached: cached, progress: { await progress($0 * 0.85) }, fetch: fetch)
        try Task.checkCancellation()
        try prepare()
        let installation = try synchronizeMetadata(latest)
        await progress(0.95)
        if cached?.sourceCommit != latest.sourceCommit {
            try JSONEncoder().encode(latest).write(to: root.appendingPathComponent("catalog.json"), options: .atomic)
        }
        await progress(1)
        return (latest, installation)
    }
    private func synchronizeMetadata(_ catalog: TableCatalog) throws -> TableInstallation? {
        guard FileManager.default.fileExists(atPath: index.path) else { return nil }
        let state = try JSONDecoder().decode(TableInstallation.self, from: Data(contentsOf: index))
        let latest = Dictionary(uniqueKeysWithValues: catalog.tables.map { ($0.id, $0) })
        let tables = state.tables.map { old -> TablePackage in
            guard old.isUpstream, let new = latest[old.id], new.isUpstream, old.name == new.name else { return old }
            // Keep the installed content identity: changed TSVs must still show as updatable.
            return TablePackage(id: old.id, name: old.name, fullName: new.fullName,
                atlas: new.atlas, dictionary: new.dictionary, administrative: new.administrative,
                source: new.source, sourceCommit: old.sourceCommit, recordCount: old.recordCount,
                size: old.size, sha256: old.sha256, url: old.url, metadata: new.metadata,
                location: new.location, atlasColor: new.atlasColor, dictionaryColor: new.dictionaryColor,
                format: old.format, gitBlob: old.gitBlob)
        }
        guard tables != state.tables else { return state }
        let updated = TableInstallation(catalogVersion: state.catalogVersion, tables: tables, databaseFile: state.databaseFile)
        try JSONEncoder().encode(updated).write(to: index, options: .atomic)
        return updated
    }
    func cachedCatalog() -> TableCatalog? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("catalog.json")),
              let cached = try? JSONDecoder().decode(TableCatalog.self, from: data),
              (try? cached.validate()) != nil else { return nil }
        return cached
    }
    private func verify(_ file: URL, table: TablePackage) throws {
        if table.isUpstream {
            let db = try SQLiteConnection(url: file)
            try db.validate(requireSample: false)
            guard try db.rows("SELECT 1 FROM langs WHERE 語言 != ? LIMIT 1", [table.name]).isEmpty,
                  !(try db.rows("SELECT 1 FROM langs LIMIT 1")).isEmpty else { throw DictionaryFailure(message: "字表內容不符") }
            return
        }
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard size?.int64Value == table.size else { throw DictionaryFailure(message: "\(table.name)：檔案大小不符") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == table.sha256 else {
            throw DictionaryFailure(message: "\(table.name)：SHA-256 校驗失敗")
        }
        let db = try SQLiteConnection(url: file)
        try db.validate(requireSample: false)
        let counts = try db.rows("SELECT count(*) AS n FROM langs WHERE 語言 = ?", [table.name])
        guard Int(counts.first?["n"] ?? "") == table.recordCount,
              try db.rows("SELECT 1 FROM langs WHERE 語言 != ? LIMIT 1", [table.name]).isEmpty else {
            throw DictionaryFailure(message: "\(table.name)：字表內容不符")
        }
    }
    // Testable local path and network path share validation and the atomic commit.
    func apply(_ catalog: TableCatalog, selected: Set<String>, localFiles: [String: URL] = [:], progress: @Sendable (String) async -> Void) async throws -> TableInstallation {
        guard !busy else { throw DictionaryFailure(message: "正在處理字表") }
        busy = true
        defer { busy = false }
        return try await applyInternal(catalog, selected: selected, localFiles: localFiles, progress: progress)
    }
    private func applyInternal(_ catalog: TableCatalog, selected: Set<String>, localFiles: [String: URL] = [:], verifiedIDs: Set<String> = [], phaseProgress: @Sendable (Double) async -> Void = { _ in }, progress: @Sendable (String) async -> Void) async throws -> TableInstallation {
        try catalog.validate()
        guard selected.isSubset(of: Set(catalog.tables.map(\.id))) else { throw DictionaryFailure(message: "選取項目不在目前目錄中") }
        try prepare()
        await phaseProgress(0.05)
        let tables = catalog.tables.filter { selected.contains($0.id) }.sorted { $0.id < $1.id }
        let previous = try await restore()
        let previousByID = Dictionary(uniqueKeysWithValues: (previous?.tables ?? []).map { ($0.id, $0) })
        let reusable = previous?.databaseFile != nil
        let changed = tables.filter { !reusable || previousByID[$0.id]?.sha256 != $0.sha256 }
        if reusable, changed.isEmpty, selected == Set(previousByID.keys), let previous {
            let state = TableInstallation(catalogVersion: catalog.version, tables: tables, databaseFile: previous.databaseFile)
            try JSONEncoder().encode(state).write(to: index, options: .atomic)
            return state
        }
        let retainedSize = tables.reduce(Int64(0)) { $0 + $1.size }
        let previousSize = (previous?.tables ?? []).reduce(Int64(0)) { $0 + $1.size }
        let rebuildRetained = reusable && changed.isEmpty && retainedSize < previousSize / 2
        let bytes = changed.reduce(Int64(0)) { $0 + $1.size }
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        var previousBytes: Int64 = 0
        if let filename = previous?.databaseFile {
            let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(filename).path)
            previousBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard available > previousBytes + bytes * 12 + 30_000_000 else { throw DictionaryFailure(message: "空間不足，請釋放儲存空間後重試") }
        var created = [URL]()
        var committed = false
        defer { if !committed { for file in created { try? FileManager.default.removeItem(at: file) } } }
        for (offset, table) in changed.enumerated() {
            try Task.checkCancellation()
            await progress("\(offset + 1)/\(tables.count) · \(table.name)")
            let file = root.appendingPathComponent(table.localName)
            if !FileManager.default.fileExists(atPath: file.path) {
                created.append(file)
                if table.isUpstream {
                    let data: Data
                    if let local = localFiles[table.id] { data = try Data(contentsOf: local) }
                    else if let bundled = try bundledData(for: table) { data = bundled }
                    else { data = try await UpstreamTables.get(table.url, limit: 200_000_000) }
                    try UpstreamTables.importTSV(data, table: table, to: file)
                } else if let local = localFiles[table.id] {
                    try FileManager.default.copyItem(at: local, to: file)
                } else {
                    let (temporary, response) = try await URLSession.shared.download(from: table.url)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DictionaryFailure(message: "\(table.name)：下載失敗") }
                    try FileManager.default.moveItem(at: temporary, to: file)
                }
            }
            if !verifiedIDs.contains(table.id) { try verify(file, table: table) }
        }
        try Task.checkCancellation()
        await progress("建立已選字表的離線索引…")
        let assembled = tables.isEmpty ? nil : root.appendingPathComponent(UUID().uuidString + ".db")
        if let assembled {
            created.append(assembled)
            if !rebuildRetained, let oldFile = previous?.databaseFile {
                try FileManager.default.copyItem(at: root.appendingPathComponent(oldFile), to: assembled)
            }
            await phaseProgress(0.25)
            let output = try SQLiteConnection(url: assembled, readOnly: false)
            // This is an unpublished staging copy; a failed operation discards it.
            _ = try output.rows("PRAGMA journal_mode=MEMORY")
            _ = try output.rows("PRAGMA cache_size=-16384")
            if rebuildRetained, let oldFile = previous?.databaseFile {
                try output.copyRetainedLanguages(from: root.appendingPathComponent(oldFile), names: tables.map(\.name))
            } else if !reusable {
                let first = try SQLiteConnection(url: root.appendingPathComponent(tables[0].localName))
                for name in ["langs", "info", "mcpdict"] {
                    guard let sql = try first.rows("SELECT sql FROM sqlite_master WHERE name=?", [name]).first?["sql"] else { throw DictionaryFailure(message: "字表結構缺失") }
                    _ = try output.rows(sql)
                }
            } else {
                let changedIDs = Set(changed.map(\.id))
                let removed = (previous?.tables ?? []).filter { !selected.contains($0.id) || changedIDs.contains($0.id) }.map(\.name)
                try output.transaction { try output.removeLanguages(removed) }
            }
            await phaseProgress(0.75)
            for table in changed {
                try Task.checkCancellation()
                _ = try output.rows("ATTACH DATABASE ? AS shard", [root.appendingPathComponent(table.localName).path])
                try output.transaction {
                    _ = try output.rows("INSERT INTO main.langs SELECT 字組, 語言, 讀音, 註釋 FROM shard.langs ORDER BY rowid")
                    _ = try output.rows("INSERT INTO main.info (簡稱, 語言) SELECT 簡稱, 語言 FROM shard.info")
                }
                _ = try output.rows("DETACH DATABASE shard")
            }
        }
        let state = TableInstallation(catalogVersion: catalog.version, tables: tables, databaseFile: assembled?.lastPathComponent)
        let data = try JSONEncoder().encode(state)
        let pointer = index
        try Task.checkCancellation()
        if let assembled {
            // All imported shards have already passed full integrity/hash checks;
            // existing pages come from our immutable active database. SQLite has
            // committed the edits to this private copy. Recheck its schema and FTS
            // query before switching, without scanning every untouched page again.
            try await repository.activate(assembled, requireSample: false, checkIntegrity: false) { try data.write(to: pointer, options: .atomic) }
        } else {
            try await repository.clear { try data.write(to: pointer, options: .atomic) }
        }
        await phaseProgress(0.95)
        committed = true
        let retained = Set(tables.map(\.localName) + [assembled?.lastPathComponent].compactMap { $0 })
        for file in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "db" && !retained.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        return state
    }
    private func prefetchSources(_ tables: [TablePackage], localFiles: [String: URL]) async throws -> [String: Data] {
        try await withThrowingTaskGroup(of: (String, Data).self) { group in
            var sources = [String: Data]()
            for table in tables where table.isUpstream {
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: root.appendingPathComponent(table.localName).path) { continue }
                if let file = localFiles[table.id] { sources[table.id] = try Data(contentsOf: file) }
                else if let data = try bundledData(for: table) { sources[table.id] = data }
                else {
                    let fetch = fetchTable
                    group.addTask { (table.id, try await fetch(table.url)) }
                }
            }
            for try await (id, data) in group { sources[id] = data }
            return sources
        }
    }
    // Download is additive. Completed, verified tables are activated even on cancellation.
    func download(_ catalog: TableCatalog, selected: Set<String>, localFiles: [String: URL] = [:], completedCount: @escaping @Sendable (Int) async -> Void = { _ in }, progress: @escaping @Sendable (String) async -> Void) async throws -> TableDownloadResult {
        guard !busy else { throw DictionaryFailure(message: "正在處理字表") }
        busy = true
        defer { busy = false }
        try catalog.validate()
        guard selected.isSubset(of: Set(catalog.tables.map(\.id))) else { throw DictionaryFailure(message: "選取項目不在目前目錄中") }
        try prepare()
        let previous = try await restore()
        var retained = Dictionary(uniqueKeysWithValues: (previous?.tables ?? []).map { ($0.id, $0) })
        let requested = catalog.tables.filter {
            selected.contains($0.id) && (previous?.databaseFile == nil || retained[$0.id]?.sha256 != $0.sha256)
        }.sorted { $0.id < $1.id }
        if requested.isEmpty, let previous {
            return TableDownloadResult(installation: previous, cancelled: false, failure: nil, completed: 0)
        }
        let bytes = requested.reduce(Int64(0)) { $0 + $1.size }
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard available > bytes * 12 + 30_000_000 else { throw DictionaryFailure(message: "空間不足，請先釋放儲存空間") }
        var failure: String?
        var completed = 0
        var verifiedIDs = Set<String>()
        await completedCount(0)
        do {
            for batch in TableDownloadBatch.make(requested) {
                try Task.checkCancellation()
                let sources = try await prefetchSources(batch, localFiles: localFiles)
                for table in batch {
                let offset = completed
                try Task.checkCancellation()
                await progress("\(offset + 1)/\(requested.count) · \(table.name)")
                try Task.checkCancellation()
                if previous?.databaseFile != nil, retained[table.id]?.sha256 == table.sha256 {
                    completed += 1
                    await completedCount(completed)
                    continue
                }
                let file = root.appendingPathComponent(table.localName)
                if !FileManager.default.fileExists(atPath: file.path) {
                    let staging = root.appendingPathComponent(UUID().uuidString + ".partial")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    if table.isUpstream {
                        let data: Data
                        if let prefetched = sources[table.id] { data = prefetched }
                        else { throw DictionaryFailure(message: "字表下載資料缺失") }
                        try UpstreamTables.importTSV(data, table: table, to: staging)
                    } else if let local = localFiles[table.id] {
                        try FileManager.default.copyItem(at: local, to: staging)
                    } else {
                        let (temporary, response) = try await URLSession.shared.download(from: table.url)
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DictionaryFailure(message: "\(table.name)：下載失敗") }
                        try FileManager.default.moveItem(at: temporary, to: staging)
                    }
                    if !table.isUpstream { try verify(staging, table: table) }
                    try FileManager.default.moveItem(at: staging, to: file)
                } else { try verify(file, table: table) }
                retained[table.id] = table
                verifiedIDs.insert(table.id)
                completed += 1
                await completedCount(completed)
                await progress("已完成 \(completed)/\(requested.count) · \(table.name)")
                }
            }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { failure = error.localizedDescription }
        }
        let cancelled = Task.isCancelled
        await progress(cancelled ? "正在保存已完成的字表…" : "正在建立查詢索引…")
        let combined = TableCatalog(schemaVersion: 1, version: catalog.version, sourceRepository: catalog.sourceRepository, sourceCommit: catalog.sourceCommit, scope: "", tables: Array(retained.values))
        // A new task intentionally finishes the atomic save after the user cancels networking.
        let verified = verifiedIDs
        let state = try await Task.detached {
            try await self.applyInternal(combined, selected: Set(combined.tables.map(\.id)), verifiedIDs: verified) { _ in }
        }.value
        return TableDownloadResult(installation: state, cancelled: cancelled, failure: failure, completed: completed)
    }
    func remove(selected: Set<String>, progress: @escaping @Sendable (Double) async -> Void = { _ in }) async throws -> TableInstallation {
        guard !busy else { throw DictionaryFailure(message: "正在處理字表") }
        busy = true
        defer { busy = false }
        let previous = try await restore()
        let remaining = (previous?.tables ?? []).filter { !selected.contains($0.id) }
        let catalog = TableCatalog(schemaVersion: 1, version: previous?.catalogVersion ?? "local", sourceRepository: UpstreamTables.repository, sourceCommit: remaining.first?.sourceCommit ?? "", scope: "", tables: remaining)
        let result = try await applyInternal(catalog, selected: Set(remaining.map(\.id)), phaseProgress: progress) { _ in }
        await progress(1)
        return result
    }

}


struct TableDownloadResult {
    let installation: TableInstallation
    let cancelled: Bool
    let failure: String?
    let completed: Int
}
