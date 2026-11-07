import SwiftUI

enum AppAccent {
    static let uiColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.systemTeal : UIColor(red: 0.10, green: 0.38, blue: 0.82, alpha: 1)
    }
    static let color = Color(uiColor: uiColor)
}
