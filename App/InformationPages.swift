import SwiftUI
import WebKit

struct ContactView: View {
    var body: some View {
        Form {
            Section {
                SystemText(ui("ios音典等反映qq群: 1127851625"))
                SystemText(ui("作者主頁") + ": https://ghehyoein.com/", detectLinks: true)
            }
        }
        .appPageStyle()
        .navigationTitle(ui("聯繫方式"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppTypography.interfaceKey) private var fontSize = 17.0

    var body: some View {
        AboutDocument(html: AboutContent.document(fontSize: fontSize, dark: scheme == .dark)) { openURL($0) }
            .navigationTitle(ui("關於"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

enum AboutContent {
    // The full upstream README, including its original links and attribution.
    static let sourceURL = "https://github.com/osfans/MCPDict/blob/232064ec009e524f2299bea9cc29602c667a22cc/README.md"
    private static let androidHTML: String = {
        guard let url = Bundle.main.url(forResource: "AndroidAbout", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing bundled Android project description")
            return "<p><a href=\"\(sourceURL)\">osfans/MCPDict README</a></p>"
        }
        return html
    }()

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func document(fontSize: Double, dark: Bool) -> String {
        let background = dark ? "#000000" : "#F8F7F3"
        let text = dark ? "#F2F2F7" : "#252620"
        let secondary = dark ? "#AEAEB2" : "#6A6D63"
        let link = dark ? "#30B0C7" : "#3E5637"
        let border = dark ? "#38383A" : "#E3E3DA"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data:">
        <style>
        :root { color-scheme: \(dark ? "dark" : "light"); }
        body { margin: 0; padding: 22px 20px 40px; background: \(background); color: \(text);
          font: \(min(26, max(14, fontSize)))px/1.65 -apple-system, sans-serif;
          overflow-wrap: anywhere; -webkit-text-size-adjust: 100%; -webkit-user-select: text; user-select: text; }
        h1 { font-size: 1.45em; } h2 { font-size: 1.25em; } h3, h4 { font-size: 1.1em; }
        h1, h2, h3, h4 { line-height: 1.4; margin: 1.6em 0 .7em; }
        .ios h1 { margin-top: 0; } p { margin: .8em 0; }
        a { color: \(link); text-decoration: underline; text-underline-offset: 3px; }
        .upstream { margin-top: 52px; padding-top: 26px; border-top: 1px solid \(border); }
        .source { color: \(secondary); font-size: .9em; }
        .anchor { display: none; } table { border-collapse: collapse; width: 100%; }
        th, td { padding: 7px 10px; border: 1px solid \(border); text-align: left; }
        img { max-width: 100%; height: auto; }
        </style></head><body>
        <section class="ios"><h1>\(escaped(ui("iOS 版說明")))</h1>
        <p>\(escaped(ui("iOS版介紹正文")).replacingOccurrences(of: "osfans/MCPDict", with: "<a href=\"https://github.com/osfans/MCPDict\">osfans/MCPDict</a>"))</p></section>
        <section class="upstream"><h1>\(escaped(ui("安卓版項目說明（原文）")))</h1>
        <p class="source"><a href="\(sourceURL)">osfans/MCPDict · README</a></p>
        \(androidHTML)</section></body></html>
        """
    }
}

private struct AboutDocument: UIViewRepresentable {
    let html: String
    let openLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(openLink: openLink) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = AppTheme.page
        view.scrollView.backgroundColor = AppTheme.page
        view.navigationDelegate = context.coordinator
        // WebKit's native text selection and copy menu remain available.
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.openLink = openLink
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        var openLink: (URL) -> Void
        init(openLink: @escaping (URL) -> Void) { self.openLink = openLink }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                decisionHandler(.cancel)
                openLink(url)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
