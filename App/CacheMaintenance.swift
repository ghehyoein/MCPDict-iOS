import SwiftUI

// URLCache capacities are advisory and can be exceeded until asynchronous
// eviction. Source bodies already live in verified databases, so never retain
// redundant HTTP responses. MapKit manages its own system cache separately.
private final class UncachedResponses: URLCache, @unchecked Sendable {
    override func storeCachedResponse(_ cachedResponse: CachedURLResponse, for request: URLRequest) {}
    override func storeCachedResponse(_ cachedResponse: CachedURLResponse, for dataTask: URLSessionDataTask) {}
}

enum CacheMaintenance {
    static let memoryBytes = 0
    static let diskBytes = 0
    static func configure() {
        guard !(URLCache.shared is UncachedResponses) else { return }
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = UncachedResponses(memoryCapacity: memoryBytes, diskCapacity: diskBytes, diskPath: nil)
    }
    static func releaseMemory() {
        URLCache.shared.removeAllCachedResponses()
        GlyphStandard.clearCache(); FontFallback.clearCache(); CharacterVariants.clearCache()
        ToneDisplay.clearCache()
        Task { await UpstreamDiagnostics.shared.clearCache() }
    }
    static func clear() {
        // Only disposable HTTP responses; installed databases, downloads and user data are excluded.
        URLCache.shared.removeAllCachedResponses()
        releaseMemory()
        UserDefaults.standard.set(Date(), forKey: "cacheLastCleared")
    }
    static func scheduled() {
        configure()
        guard UserDefaults.standard.object(forKey: "autoClearCache") as? Bool ?? true else { return }
        let last = UserDefaults.standard.object(forKey: "cacheLastCleared") as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= 7 * 86400 { clear() }
    }
}
struct CacheSettingsView: View {
    @AppStorage("autoClearCache") private var automatic = true
    @State private var cleared = false
    var body: some View {
        Form {
            Toggle(ui("每週自動清理快取"), isOn: $automatic)
            Button(ui("清理快取")) { CacheMaintenance.clear(); cleared = true }
            if cleared { Text(ui("快取已清理")) }
        }.appPageStyle().navigationTitle(ui("清理快取"))
    }
}
