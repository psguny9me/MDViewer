import WebKit
import XCTest
@testable import MDViewer

@MainActor
final class MarkdownWebViewLinkBridgeTests: XCTestCase {
    func testClickSendsOriginalRelativeHrefToSwift() {
        let opened = expectation(description: "raw href delivered to Swift")
        var webView: WKWebView!
        var didRequestClick = false

        let coordinator = MarkdownWebView.Coordinator(
            onTOC: { _ in
                guard !didRequestClick else { return }
                didRequestClick = true
                webView.evaluateJavaScript("document.querySelector('a').click();")
            },
            onEditorLine: { _ in },
            onBookmarkToggle: { _ in },
            onOpenLink: { href in
                XCTAssertEqual(href, "nested/relative%20target.md")
                opened.fulfill()
            }
        )

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(coordinator, name: "toc")
        controller.add(coordinator, name: "openLink")
        configuration.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        coordinator.webView = webView
        coordinator.pendingMarkdown = "[Relative](nested/relative%20target.md)"

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = projectRoot.appendingPathComponent("Sources/MDViewer/Resources", isDirectory: true)
        let template = resources.appendingPathComponent("template.html")
        webView.loadFileURL(template, allowingReadAccessTo: resources)

        wait(for: [opened], timeout: 5)
        controller.removeScriptMessageHandler(forName: "toc")
        controller.removeScriptMessageHandler(forName: "openLink")
    }
}
