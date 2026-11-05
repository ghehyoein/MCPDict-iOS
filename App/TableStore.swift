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
    init(repository: DictionaryRepository, root: URL? = nil) {
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
        let latest = try await UpstreamTables.catalog()
        try prepare()
        try JSONEncoder().encode(latest).write(to: root.appendingPathComponent("catalog.json"), options: .atomic)
        return latest
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
    private func applyInternal(_ catalog: TableCatalog, selected: Set<String>, localFiles: [String: URL] = [:], progress: @Sendable (String) async -> Void) async throws -> TableInstallation {
        try catalog.validate()
        guard selected.isSubset(of: Set(catalog.tables.map(\.id))) else { throw DictionaryFailure(message: "選取項目不在目前目錄中") }
        try prepare()
        let tables = catalog.tables.filter { selected.contains($0.id) }.sorted { $0.id < $1.id }
        let bytes = tables.reduce(Int64(0)) { $0 + $1.size }
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard available > bytes * 12 + 30_000_000 else { throw DictionaryFailure(message: "空間不足，請預留所選原始字表十二倍大小的空間") }
        var created = [URL]()
        var committed = false
        defer { if !committed { for file in created { try? FileManager.default.removeItem(at: file) } } }
        for (offset, table) in tables.enumerated() {
            try Task.checkCancellation()
            await progress("\(offset + 1)/\(tables.count) · \(table.name)")
            let file = root.appendingPathComponent(table.localName)
            if !FileManager.default.fileExists(atPath: file.path) {
                created.append(file)
                if table.isUpstream {
                    let data: Data
                    if let local = localFiles[table.id] { data = try Data(contentsOf: local) }
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
            try verify(file, table: table)
        }
        try Task.checkCancellation()
        await progress("建立已選字表的離線索引…")
        let assembled = tables.isEmpty ? nil : root.appendingPathComponent(UUID().uuidString + ".db")
        if let assembled {
            created.append(assembled)
            let output = try SQLiteConnection(url: assembled, readOnly: false)
            let first = try SQLiteConnection(url: root.appendingPathComponent(tables[0].localName))
            for name in ["langs", "info", "mcpdict"] {
                guard let sql = try first.rows("SELECT sql FROM sqlite_master WHERE name=?", [name]).first?["sql"] else { throw DictionaryFailure(message: "字表結構缺失") }
                _ = try output.rows(sql)
            }
            for table in tables {
                try Task.checkCancellation()
                _ = try output.rows("ATTACH DATABASE ? AS shard", [root.appendingPathComponent(table.localName).path])
                _ = try output.rows("INSERT INTO main.langs SELECT 字組, 語言, 讀音, 註釋 FROM shard.langs ORDER BY rowid")
                _ = try output.rows("INSERT INTO main.info (簡稱, 語言) SELECT 簡稱, 語言 FROM shard.info")
                _ = try output.rows("DETACH DATABASE shard")
            }
        }
        let state = TableInstallation(catalogVersion: catalog.version, tables: tables, databaseFile: assembled?.lastPathComponent)
        let data = try JSONEncoder().encode(state)
        let pointer = index
        try Task.checkCancellation()
        if let assembled {
            try await repository.activate(assembled, requireSample: false) { try data.write(to: pointer, options: .atomic) }
        } else {
            try await repository.clear { try data.write(to: pointer, options: .atomic) }
        }
        committed = true
        let retained = Set(tables.map(\.localName) + [assembled?.lastPathComponent].compactMap { $0 })
        for file in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "db" && !retained.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        return state
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
        let requested = catalog.tables.filter { selected.contains($0.id) }.sorted { $0.id < $1.id }
        let bytes = requested.reduce(Int64(0)) { $0 + $1.size }
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard available > bytes * 12 + 30_000_000 else { throw DictionaryFailure(message: "空間不足，請先釋放儲存空間") }
        var failure: String?
        var completed = 0
        await completedCount(0)
        do {
            for (offset, table) in requested.enumerated() {
                try Task.checkCancellation()
                await progress("\(offset + 1)/\(requested.count) · \(table.name)")
                try Task.checkCancellation()
                let file = root.appendingPathComponent(table.localName)
                if !FileManager.default.fileExists(atPath: file.path) {
                    let staging = root.appendingPathComponent(UUID().uuidString + ".partial")
                    defer { try? FileManager.default.removeItem(at: staging) }
                    if table.isUpstream {
                        let data: Data
                        if let local = localFiles[table.id] { data = try Data(contentsOf: local) }
                        else { data = try await UpstreamTables.get(table.url, limit: 200_000_000) }
                        try UpstreamTables.importTSV(data, table: table, to: staging)
                    } else if let local = localFiles[table.id] {
                        try FileManager.default.copyItem(at: local, to: staging)
                    } else {
                        let (temporary, response) = try await URLSession.shared.download(from: table.url)
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DictionaryFailure(message: "\(table.name)：下載失敗") }
                        try FileManager.default.moveItem(at: temporary, to: staging)
                    }
                    try verify(staging, table: table)
                    try FileManager.default.moveItem(at: staging, to: file)
                } else { try verify(file, table: table) }
                retained[table.id] = table
                completed += 1
                await completedCount(completed)
                await progress("已完成 \(completed)/\(requested.count) · \(table.name)")
            }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { failure = error.localizedDescription }
        }
        let cancelled = Task.isCancelled
        await progress(cancelled ? "正在保存已完成的字表…" : "正在建立查詢索引…")
        let combined = TableCatalog(schemaVersion: 1, version: catalog.version, sourceRepository: catalog.sourceRepository, sourceCommit: catalog.sourceCommit, scope: "", tables: Array(retained.values))
        // A new task intentionally finishes the atomic save after the user cancels networking.
        let state = try await Task.detached {
            try await self.applyInternal(combined, selected: Set(combined.tables.map(\.id))) { _ in }
        }.value
        return TableDownloadResult(installation: state, cancelled: cancelled, failure: failure, completed: completed)
    }
    func remove(selected: Set<String>) async throws -> TableInstallation {
        guard !busy else { throw DictionaryFailure(message: "正在處理字表") }
        busy = true
        defer { busy = false }
        let previous = try await restore()
        let remaining = (previous?.tables ?? []).filter { !selected.contains($0.id) }
        let catalog = TableCatalog(schemaVersion: 1, version: previous?.catalogVersion ?? "local", sourceRepository: UpstreamTables.repository, sourceCommit: remaining.first?.sourceCommit ?? "", scope: "", tables: remaining)
        return try await applyInternal(catalog, selected: Set(remaining.map(\.id))) { _ in }
    }

}


struct TableDownloadResult {
    let installation: TableInstallation
    let cancelled: Bool
    let failure: String?
    let completed: Int
}
