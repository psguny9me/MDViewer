import SwiftUI
import WebKit

final class WebViewHolder: ObservableObject {
    weak var webView: WKWebView?
}

/// 우클릭 컨텍스트 메뉴 액션 모음 — ContentView가 DocumentState로 wire한다.
struct WebViewMenuActions {
    var reload: () -> Void
    var openInEditor: () -> Void
    var find: () -> Void
    var exportPDF: () -> Void
    var printDoc: () -> Void
}

/// 클로저를 직접 들고 있는 NSMenuItem.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}

/// WKWebView 서브클래스: native 컨텍스트 메뉴를 유지하되 hang 원인인
/// "Look Up"/"Translate" 항목만 제거하고, 우리 액션을 append한다.
final class MDWebView: WKWebView {
    var menuActions: WebViewMenuActions?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        // 일부 macOS 환경에서 메인 스레드를 hang시키는 시스템 lookup/translate 항목 제거.
        menu.items.removeAll { item in
            guard let id = item.identifier?.rawValue else { return false }
            return id.contains("LookUp") || id.contains("Translate")
        }

        guard let actions = menuActions else { return }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "새로고침", handler: actions.reload))
        menu.addItem(ClosureMenuItem(title: "외부 에디터에서 편집", handler: actions.openInEditor))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "찾기...", handler: actions.find))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "PDF로 내보내기...", handler: actions.exportPDF))
        menu.addItem(ClosureMenuItem(title: "인쇄...", handler: actions.printDoc))
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let isDark: Bool
    let addedLines: [Int]
    let onTOC: ([TOCItem]) -> Void
    @Binding var scrollToAnchor: String?
    let holder: WebViewHolder?
    let menuActions: WebViewMenuActions

    func makeCoordinator() -> Coordinator {
        Coordinator(onTOC: onTOC)
    }

    func makeNSView(context: Context) -> MDWebView {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        // 외부 링크는 기본 브라우저로
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "toc")
        cfg.userContentController = ucc

        let webView = MDWebView(frame: .zero, configuration: cfg)
        webView.menuActions = menuActions
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

    func updateNSView(_ nsView: MDWebView, context: Context) {
        nsView.menuActions = menuActions
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
