import Foundation
import XCTest
@testable import MDViewer

@MainActor
final class DocumentRegistryTests: XCTestCase {
    func testOpenRequestReusesEmptyDocument() throws {
        let registry = DocumentRegistry()
        let empty = DocumentState()
        registry.register(empty)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdviewer-registry-\(UUID().uuidString).md")
        try "# Test".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        registry.handleOpenRequests([url])
        XCTAssertEqual(empty.currentURL?.mdvKey, url.mdvKey)
    }

    func testSecondOpenRequestUsesLiveWindowAction() throws {
        let registry = DocumentRegistry()
        let existing = DocumentState()
        existing.currentURL = URL(fileURLWithPath: "/tmp/already-open.md")
        registry.register(existing)

        let requested = URL(fileURLWithPath: "/tmp/second.md")
        var openedURL: URL?
        registry.setOpenWindowAction(for: existing) { openedURL = $0 }
        registry.handleOpenRequests([requested])

        XCTAssertEqual(openedURL?.mdvKey, requested.mdvKey)
    }

    func testValueRoutedDocumentReplacesExistingEmptyDocument() {
        let registry = DocumentRegistry()
        let empty = DocumentState()
        let routed = DocumentState()
        routed.currentURL = URL(fileURLWithPath: "/tmp/routed.md")
        registry.register(empty)
        registry.register(routed)

        XCTAssertTrue(registry.redundantDocument(forValueRouted: routed) === empty)
    }

    func testValueRoutedDuplicateClosesNewDocument() {
        let registry = DocumentRegistry()
        let existing = DocumentState()
        let routed = DocumentState()
        let url = URL(fileURLWithPath: "/tmp/already-open.md")
        existing.currentURL = url
        routed.currentURL = url
        registry.register(existing)
        registry.register(routed)

        XCTAssertTrue(registry.redundantDocument(forValueRouted: routed) === routed)
    }
}
