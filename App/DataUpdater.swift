import Foundation
import CryptoKit

struct DataManifest: Codable {
    let schemaVersion: Int
    let version: String
    let sourceCommit: String
    let sourceRepository: String
    let database: Asset
    struct Asset: Codable {
        let url: URL
        let size: Int64
        let sha256: String
    }
    func validate() throws {
        guard schemaVersion == 1,
              sourceRepository == "https://github.com/osfans/MCPDict",
              sourceCommit.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              database.size > 0, database.size < 4_000_000_000,
              database.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              database.url.scheme == "https", database.url.host == "github.com",
              database.url.path.contains("/releases/download/") else {
            throw DictionaryFailure(message: "更新清單格式或資料版本不相容")
        }
    }
}

actor DataUpdater {
    let repository: DictionaryRepository
    let root: URL
    private var busy = false
    init(repository: DictionaryRepository) {
        self.repository = repository
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dictionary", isDirectory: true)
    }
    private var pointer: URL { root.appendingPathComponent("current.json") }

    func restore() async throws -> DataManifest? {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        let manifest = try JSONDecoder().decode(DataManifest.self, from: Data(contentsOf: pointer))
        try manifest.validate()
        try await repository.open(root.appendingPathComponent(manifest.database.sha256 + ".db"))
        return manifest
    }

    func check(_ text: String) async throws -> DataManifest {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
              ["github.com", "raw.githubusercontent.com"].contains(url.host ?? "") else {
            throw DictionaryFailure(message: "請填寫 GitHub Release 的 manifest.json HTTPS 網址")
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else {
            throw DictionaryFailure(message: "無法取得更新清單，請檢查網址或網路")
        }
        let manifest = try JSONDecoder().decode(DataManifest.self, from: data)
        try manifest.validate()
        return manifest
    }

    func install(_ manifest: DataManifest) async throws {
        guard !busy else { throw DictionaryFailure(message: "正在更新資料") }
        busy = true
        defer { busy = false }
        try manifest.validate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let capacity = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard capacity > manifest.database.size * 2 + 100_000_000 else {
            throw DictionaryFailure(message: "儲存空間不足，請保留約兩倍資料庫大小的空間")
        }
        let (temp, response) = try await URLSession.shared.download(from: manifest.database.url)
        defer { try? FileManager.default.removeItem(at: temp) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DictionaryFailure(message: "下載失敗") }
        try Task.checkCancellation()
        let size = try FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? NSNumber
        guard size?.int64Value == manifest.database.size else { throw DictionaryFailure(message: "下載大小不符") }
        let handle = try FileHandle(forReadingFrom: temp)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.database.sha256 else { throw DictionaryFailure(message: "SHA-256 校驗失敗，保留舊資料") }
        let destination = root.appendingPathComponent(digest + ".db")
        let existed = FileManager.default.fileExists(atPath: destination.path)
        if !existed { try FileManager.default.moveItem(at: temp, to: destination) }
        let encoded = try JSONEncoder().encode(manifest)
        let pointerURL = pointer
        do {
            try Task.checkCancellation()
            try await repository.activate(destination) {
                try encoded.write(to: pointerURL, options: .atomic)
            }
        } catch {
            if !existed { try? FileManager.default.removeItem(at: destination) }
            throw error
        }
        // Keep the immediately previous version, remove only older inactive databases.
        let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        let previous = (files ?? []).filter { $0.pathExtension == "db" && $0 != destination }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for file in previous.dropFirst() { try? FileManager.default.removeItem(at: file) }
    }
}
