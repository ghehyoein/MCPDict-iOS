import SwiftUI

enum AppAccent {
    static let color = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.systemTeal : UIColor(red: 0, green: 0.34, blue: 0.48, alpha: 1)
    })
}
