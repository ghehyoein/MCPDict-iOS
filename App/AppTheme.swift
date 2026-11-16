import SwiftUI

// Warm paper and moss green for light appearance. Semantic dark colors retain
// the existing appearance, including the gray map reading backgrounds.
enum AppTheme {
    private static func adaptive(_ hex: UInt32, dark: UIColor) -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark { return dark.resolvedColor(with: traits) }
            return UIColor(red: CGFloat(hex >> 16 & 255) / 255,
                           green: CGFloat(hex >> 8 & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    static let accent = adaptive(0x3E5637, dark: .systemTeal)
    static let tabSelected = adaptive(0x344E2D, dark: .systemTeal)
    static let tabUnselected = adaptive(0x6C7465, dark: .label)
    static let page = adaptive(0xF8F7F3, dark: .systemGroupedBackground)
    static let surface = adaptive(0xFFFFFF, dark: .secondarySystemGroupedBackground)
    static let inset = adaptive(0xEEF1E8, dark: .secondarySystemBackground)
    static let border = adaptive(0xE3E3DA, dark: .separator)
    static let text = adaptive(0x252620, dark: .label)
    static let secondaryText = adaptive(0x6A6D63, dark: .secondaryLabel)
    static let info = adaptive(0x3E5637, dark: .systemBlue)
    static let navigation = adaptive(0xF8F7F3, dark: .systemBackground)
    static let pinnedHeader = adaptive(0xF8F7F3, dark: .black)

    @MainActor static func configureTabBar() {
        applyTabBarColors(to: UITabBar.appearance())
    }

    @MainActor static func applyTabBarColors(to tabBar: UITabBar) {
        // Keep native materials, selection indicators, and all tab layouts.
        // Dynamic colors also follow an in-app appearance change.
        func styled(_ base: UITabBarAppearance) -> UITabBarAppearance {
            let appearance = base.copy() as! UITabBarAppearance
            for item in [appearance.stackedLayoutAppearance,
                         appearance.inlineLayoutAppearance,
                         appearance.compactInlineLayoutAppearance] {
                item.normal.iconColor = tabUnselected
                item.normal.titleTextAttributes[.foregroundColor] = tabUnselected
                item.selected.iconColor = tabSelected
                item.selected.titleTextAttributes[.foregroundColor] = tabSelected
            }
            return appearance
        }
        tabBar.standardAppearance = styled(tabBar.standardAppearance)
        if let scrollEdge = tabBar.scrollEdgeAppearance {
            tabBar.scrollEdgeAppearance = styled(scrollEdge)
        }
        tabBar.tintColor = tabSelected
        tabBar.unselectedItemTintColor = tabUnselected
    }
}

// SwiftUI on iOS 26 can replace UIAppearance colors when creating its tab bar.
// Apply only colors to the live native bar after SwiftUI finishes updating it.
struct NativeTabBarPalette: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.refresh() }

    final class Controller: UIViewController {
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            refresh()
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            refresh()
        }
        func refresh() {
            DispatchQueue.main.async { [weak self] in
                guard let bar = self?.tabBarController?.tabBar else { return }
                AppTheme.applyTabBarColors(to: bar)
            }
        }
    }
}

private struct AppPageStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let background: UIColor
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(scheme == .light ? .hidden : .automatic)
            .background(scheme == .light ? Color(uiColor: background) : .clear)
    }
}

private struct AppPanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius)
                .fill(scheme == .light ? AnyShapeStyle(Color(uiColor: AppTheme.surface)) : AnyShapeStyle(.regularMaterial)))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(scheme == .light ? Color(uiColor: AppTheme.border) : .clear, lineWidth: 1)
                .allowsHitTesting(false))
    }
}

extension View {
    func appPageStyle(background: UIColor = AppTheme.page) -> some View {
        modifier(AppPageStyle(background: background))
    }
    func appPanelBackground(radius: CGFloat) -> some View {
        modifier(AppPanelBackground(radius: radius))
    }
}
