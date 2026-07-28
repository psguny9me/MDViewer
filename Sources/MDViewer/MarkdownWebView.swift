import SwiftUI
@preconcurrency import WebKit

final class WebViewHolder: ObservableObject {
    weak var webView: WKWebView?
}

/// 우클릭 컨텍스트 메뉴 액션 모음 — ContentView가 DocumentState로 wire한다.
struct WebViewMenuActions {
    var isEditing: Bool
    var reload: () -> Void
    var toggleEdit: () -> Void
    var save: () -> Void
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
        menu.addItem(ClosureMenuItem(title: actions.isEditing ? "프리뷰로 전환" : "편집",
                                     handler: actions.toggleEdit))
        if actions.isEditing {
            menu.addItem(ClosureMenuItem(title: "저장", handler: actions.save))
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "찾기...", handler: actions.find))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "PDF로 내보내기...", handler: actions.exportPDF))
        menu.addItem(ClosureMenuItem(title: "인쇄...", handler: actions.printDoc))
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    /// 렌더 모드 — "markdown" 또는 "json" (render.js가 분기).
    let mode: String
    let isDark: Bool
    let addedLines: [Int]
    let bookmarkLines: [Int]
    let onTOC: ([TOCItem]) -> Void
    let onEditorLine: (Int) -> Void
    let onBookmarkToggle: (Int) -> Void
    @Binding var scrollToAnchor: String?
    let holder: WebViewHolder?
    let menuActions: WebViewMenuActions

    func makeCoordinator() -> Coordinator {
        Coordinator(onTOC: onTOC, onEditorLine: onEditorLine, onBookmarkToggle: onBookmarkToggle)
    }

    func makeNSView(context: Context) -> MDWebView {
        let cfg = WKWebViewConfiguration()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        // 외부 링크는 기본 브라우저로
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "toc")
        ucc.add(context.coordinator, name: "editorLine")
        ucc.add(context.coordinator, name: "bookmark")
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
        context.coordinator.pendingMode = mode
        context.coordinator.pendingIsDark = isDark
        context.coordinator.pendingAddedLines = addedLines
        context.coordinator.pendingBookmarkLines = bookmarkLines
        holder?.webView = webView
        return webView
    }

    static func dismantleNSView(_ nsView: MDWebView, coordinator: Coordinator) {
        // WKUserContentController는 핸들러를 강참조한다 — 해제하지 않으면
        // coordinator(와 캡처된 클로저들)가 webView 수명에 묶여 누수된다.
        coordinator.cancelPendingRender()
        let ucc = nsView.configuration.userContentController
        ucc.removeScriptMessageHandler(forName: "toc")
        ucc.removeScriptMessageHandler(forName: "editorLine")
        ucc.removeScriptMessageHandler(forName: "bookmark")
    }

    func updateNSView(_ nsView: MDWebView, context: Context) {
        nsView.menuActions = menuActions
        context.coordinator.pendingMarkdown = markdown
        context.coordinator.pendingMode = mode
        context.coordinator.pendingIsDark = isDark
        context.coordinator.pendingAddedLines = addedLines
        context.coordinator.pendingBookmarkLines = bookmarkLines
        context.coordinator.scheduleRender()
        context.coordinator.flushBookmarks()

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
        var pendingMode: String = "markdown"
        var pendingIsDark: Bool = false
        var pendingAddedLines: [Int] = []
        var pendingBookmarkLines: [Int] = []
        private var sentBookmarkLines: [Int]?
        let onTOC: ([TOCItem]) -> Void
        let onEditorLine: (Int) -> Void
        let onBookmarkToggle: (Int) -> Void

        init(onTOC: @escaping ([TOCItem]) -> Void,
             onEditorLine: @escaping (Int) -> Void,
             onBookmarkToggle: @escaping (Int) -> Void) {
            self.onTOC = onTOC
            self.onEditorLine = onEditorLine
            self.onBookmarkToggle = onBookmarkToggle
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            flushRender()
            flushBookmarks()
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

        private var renderWork: DispatchWorkItem?

        func cancelPendingRender() {
            renderWork?.cancel()
            renderWork = nil
        }

        /// 타이핑 중 매 입력마다 전체 재렌더하는 비용을 피하기 위한 디바운스(120ms).
        func scheduleRender() {
            renderWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flushRender() }
            renderWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: work)
        }

        func flushRender() {
            guard ready, let webView else { return }
            let payload: [String: Any] = [
                "markdown": pendingMarkdown,
                "mode": pendingMode,
                "isDark": pendingIsDark,
                "addedLines": pendingAddedLines
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            let js = "window.MDV && window.MDV.render(\(json));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        /// 북마크 마커만 갱신(전체 re-render 없이). 라이브 리로드 시 마커 유지는
        /// JS 쪽 `_lastBookmarks` 복원이 담당하고, 여기선 변경분만 내려보낸다.
        func flushBookmarks() {
            guard ready, let webView else { return }
            guard sentBookmarkLines != pendingBookmarkLines else { return }
            sentBookmarkLines = pendingBookmarkLines
            guard let data = try? JSONSerialization.data(withJSONObject: pendingBookmarkLines),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.MDV && window.MDV.setBookmarks(\(json));",
                                      completionHandler: nil)
        }

        func scrollToAnchor(_ id: String) {
            guard let webView else { return }
            let escaped = id.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("window.MDV && window.MDV.scrollTo('\(escaped)');",
                                      completionHandler: nil)
        }

        // JS → Swift: TOC 페이로드 / 프리뷰 더블클릭 줄 / 북마크 토글 수신
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "toc":
                guard let arr = message.body as? [[String: Any]] else { return }
                let items: [TOCItem] = arr.compactMap { dict in
                    guard let id = dict["id"] as? String,
                          let level = dict["level"] as? Int,
                          let text = dict["text"] as? String else { return nil }
                    let line = dict["line"] as? Int ?? 0
                    return TOCItem(id: id, level: level, text: text, line: line)
                }
                onTOC(items)
            case "editorLine":
                if let line = message.body as? Int {
                    onEditorLine(line)
                } else if let n = message.body as? NSNumber {
                    onEditorLine(n.intValue)
                }
            case "bookmark":
                guard let dict = message.body as? [String: Any],
                      let line = dict["line"] as? Int, line >= 0 else { return }
                onBookmarkToggle(line)
            default:
                break
            }
        }
    }
}
