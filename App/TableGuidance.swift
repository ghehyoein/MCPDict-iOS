import Foundation

enum TableGuidancePrompt: Equatable {
    case welcome, update
    var title: String { self == .welcome ? "字表下載指引" : "字表更新提醒" }
    var message: String {
        self == .welcome
            ? "App 已內置部分字表。你可以在「設定 → 字表下載」中手動下載所有字表，也可以現在下載。下載需要網絡，並會佔用裝置儲存空間。"
            : "字表與語言點資料可能已有更新。建議前往「設定 → 字表下載」，點擊「更新目錄」檢查。"
    }
}

struct TableGuidanceSchedule {
    let defaults: UserDefaults
    static let interval: TimeInterval = 30 * 24 * 60 * 60
    private let initialized = "tableGuidance.initialized"
    private let welcomed = "tableGuidance.welcomed"
    private let lastReminder = "tableGuidance.lastReminder"

    func prepare(existingInstallation: Bool, now: Date = Date()) {
        guard !defaults.bool(forKey: initialized) else { return }
        defaults.set(true, forKey: initialized)
        defaults.set(existingInstallation, forKey: welcomed)
        defaults.set(now, forKey: lastReminder)
    }
    func due(now: Date = Date()) -> TableGuidancePrompt? {
        guard defaults.bool(forKey: initialized) else { return nil }
        if !defaults.bool(forKey: welcomed) { return .welcome }
        guard let last = defaults.object(forKey: lastReminder) as? Date else { return nil }
        return now.timeIntervalSince(last) >= Self.interval ? .update : nil
    }
    func presented(_ prompt: TableGuidancePrompt, now: Date = Date()) {
        if prompt == .welcome { defaults.set(true, forKey: welcomed) }
        catalogChecked(now: now)
    }
    func catalogChecked(now: Date = Date()) { defaults.set(now, forKey: lastReminder) }
}
