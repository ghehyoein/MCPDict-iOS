import SwiftUI

enum CacheMaintenance {
    static func clear() {
        // Only disposable HTTP responses; installed databases, downloads and user data are excluded.
        URLCache.shared.removeAllCachedResponses()
        UserDefaults.standard.set(Date(), forKey: "cacheLastCleared")
    }
    static func scheduled() {
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
        }.navigationTitle(ui("清理快取"))
    }
}
