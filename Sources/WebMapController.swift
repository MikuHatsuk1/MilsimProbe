import CoreLocation
import SwiftUI
import WebKit

/// 网页地图（Leaflet），模拟安卓版“原生外壳 + 网页地图”的结构，
/// 并测试 原生 → JS（推送位置）和 JS → 原生（点地图打标记）两个方向的通信。
final class WebMapController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private var ready = false
    private var pending: CLLocation?

    override init() {
        let config = WKWebViewConfiguration()
        let content = WKUserContentController()
        config.userContentController = content
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        content.add(self, name: "native")
        webView.navigationDelegate = self
        webView.scrollView.bounces = false

        if let url = Bundle.main.url(forResource: "map", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            AppLog.shared.add("MAP", "找不到 map.html")
        }
    }

    func push(_ loc: CLLocation) {
        guard ready else {
            pending = loc
            return
        }
        let js = String(format: "updateSelf(%.7f,%.7f,%.1f)",
                        loc.coordinate.latitude, loc.coordinate.longitude,
                        max(loc.horizontalAccuracy, 0))
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func recenter() {
        webView.evaluateJavaScript("recenter()", completionHandler: nil)
    }

    func clearTrack() {
        webView.evaluateJavaScript("clearTrack()", completionHandler: nil)
    }

    func clearMarks() {
        webView.evaluateJavaScript("clearMarks()", completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            AppLog.shared.add("MAP", "地图就绪")
            if let p = pending {
                pending = nil
                push(p)
            }
        case "speak":
            // 页面里的游戏事件（中弹、阵亡、拾取空投等）交给原生语音播报
            if let text = body["text"] as? String { SpeechService.shared.speak(text) }
        case "log":
            if let text = body["text"] as? String { AppLog.shared.add("GAME", text) }
        case "unmark":
            AppLog.shared.add("MAP", "JS→原生 删除了一个标记")
        case "error":
            AppLog.shared.add("MAP", "错误: \(body["text"] as? String ?? "")")
        default:
            AppLog.shared.add("MAP", "未知消息: \(type)")
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        AppLog.shared.add("MAP", "加载失败: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        AppLog.shared.add("MAP", "加载失败: \(error.localizedDescription)")
    }
}

struct MapWebView: UIViewRepresentable {
    let controller: WebMapController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
