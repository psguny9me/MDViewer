import SwiftUI
import WebKit

final class WebViewHolder: ObservableObject {
    weak var webView: WKWebView?
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let isDark: Bool
    let addedLines: [Int]
    let onTOC: ([TOCItem]) -> Void
    @Binding var scrollToAnchor: String?
    let holder: WebViewHolder?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTOC: onTOC)
    }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        // 외부 링크는 기본 브라우저로
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "toc")
        cfg.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true

        if let templateURL = Bundle.module.url(forResource: "template",
                                               withExtension: "html",
                                               subdirectory: "Resources") {
            webView.loadFileURL(templateURL, allowingReadAccessTo: templateURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<h1>템플릿을 찾을 수 없습니다</h1>", baseURL: nil)
        }

        context.coordinator.webView = webView
        context.coordinator.pendingMarkdown = markdown
        context.coordinator.pendingIsDark = isDark
        context.coordinator.pendingAddedLines = addedLines
        holder?.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.pendingMarkdown = markdown
        context.coordinator.pendingIsDark = isDark
        context.coordinator.pendingAddedLines = addedLines
        context.coordinator.flushRender()

        if let anchor = scrollToAnchor {
            context.coordinator.scrollToAnchor(anchor)
            DispatchQueue.main.async { self.scrollToAnchor = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var ready = false
        var pendingMarkdown: String = ""
        var pendingIsDark: Bool = false
        var pendingAddedLines: [Int] = []
        let onTOC: ([TOCItem]) -> Void

        init(onTOC: @escaping ([TOCItem]) -> Void) {
            self.onTOC = onTOC
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            flushRender()
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func flushRender() {
            guard ready, let webView else { return }
            let payload: [String: Any] = [
                "markdown": pendingMarkdown,
                "isDark": pendingIsDark,
                "addedLines": pendingAddedLines
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            let js = "window.MDV && window.MDV.render(\(json));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func scrollToAnchor(_ id: String) {
            guard let webView else { return }
            let escaped = id.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("window.MDV && window.MDV.scrollTo('\(escaped)');",
                                      completionHandler: nil)
        }

        // JS → Swift: TOC 페이로드 수신
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "toc" else { return }
            guard let arr = message.body as? [[String: Any]] else { return }
            let items: [TOCItem] = arr.compactMap { dict in
                guard let id = dict["id"] as? String,
                      let level = dict["level"] as? Int,
                      let text = dict["text"] as? String else { return nil }
                return TOCItem(id: id, level: level, text: text)
            }
            onTOC(items)
        }
    }
}
