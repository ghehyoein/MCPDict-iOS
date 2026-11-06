import SwiftUI

@MainActor
final class CopyFeedback: ObservableObject {
    @Published private(set) var visible = false
    private var timer: Task<Void, Never>?
    func show() {
        timer?.cancel()
        visible = true
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.visible = false
        }
    }
}
