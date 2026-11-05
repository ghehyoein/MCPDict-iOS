import SwiftUI
import WebKit

struct MapTilerWebView: UIViewRepresentable {
    let points: [DialectPoint]
    let apiKey: String
    let fit: Int
    let choose: (String) -> Void
    let report: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "mapEvent")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.customUserAgent = "MCPDict-iOS/0.3"
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = false
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "MapWeb") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { DispatchQueue.main.async { report("地圖資源缺失，請重新安裝新版") } }
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.choose = choose; coordinator.report = report
        coordinator.pending = self
        coordinator.send(web)
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "mapEvent")
        web.navigationDelegate = nil
        web.stopLoading()
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var choose: ((String) -> Void)?
        var report: ((String?) -> Void)?
        var pending: MapTilerWebView?
        var last: String?
        var ready = false
        func send(_ web: WKWebView) {
            guard ready, let pending,
                  let data = try? JSONEncoder().encode(pending.points),
                  let points = try? JSONSerialization.jsonObject(with: data) else { return }
            let value: [String: Any] = ["points": points, "key": pending.apiKey, "fit": pending.fit]
            guard let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let json = String(data: encoded, encoding: .utf8), json != last else { return }
            last = json
            // Arguments are serialized by WebKit; neither names nor API keys become executable JS.
            web.callAsyncJavaScript("window.updateMap(payload)", arguments: ["payload": value], in: nil, in: .page) { [weak self] result in
                if case .failure = result { self?.report?("地圖更新失敗，請切換頁面重試") }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; send(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report?("地圖載入失敗，請重試") }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let data = message.body as? [String: String] else { return }
            if let id = data["selected"] { choose?(id) }
            if let error = data["error"] { report?(error.isEmpty ? nil : error) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, url.scheme == "https" {
                UIApplication.shared.open(url); decisionHandler(.cancel)
            } else { decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel) }
        }
    }
}
