import Foundation
import XCTest
@testable import MDViewer

final class MarkdownLinkResolverTests: XCTestCase {
    private let documentURL = URL(fileURLWithPath: "/Users/example/Documents/notes/index.md")

    func testRelativePath() {
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("guides/setup.md", relativeTo: documentURL),
            .localFile(URL(fileURLWithPath: "/Users/example/Documents/notes/guides/setup.md"))
        )
    }

    func testNormalizedRelativePath() {
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("../Shared/My%20Guide.md#install", relativeTo: documentURL),
            .localFile(URL(fileURLWithPath: "/Users/example/Documents/Shared/My Guide.md"))
        )
    }

    func testAbsolutePath() {
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("/tmp/reference.json", relativeTo: documentURL),
            .localFile(URL(fileURLWithPath: "/tmp/reference.json"))
        )
    }

    func testFileURL() {
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("file:///tmp/My%20File.txt", relativeTo: documentURL),
            .localFile(URL(fileURLWithPath: "/tmp/My File.txt"))
        )
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("file:///tmp/name%23tag.md#details", relativeTo: documentURL),
            .localFile(URL(fileURLWithPath: "/tmp/name#tag.md"))
        )
    }

    func testExternalURLs() {
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("https://example.com/docs?q=1#top", relativeTo: documentURL),
            .external(URL(string: "https://example.com/docs?q=1#top")!)
        )
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("mailto:hello@example.com", relativeTo: documentURL),
            .external(URL(string: "mailto:hello@example.com")!)
        )
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("//example.com/docs", relativeTo: documentURL),
            .external(URL(string: "https://example.com/docs")!)
        )
    }

    func testAnchor() {
        XCTAssertEqual(
            MarkdownLinkResolver.resolve("#details", relativeTo: documentURL),
            .inDocumentAnchor
        )
    }

    func testBlockedSchemes() {
        XCTAssertNil(MarkdownLinkResolver.resolve("javascript:alert(1)", relativeTo: documentURL))
        XCTAssertNil(MarkdownLinkResolver.resolve("data:text/plain,hello", relativeTo: documentURL))
        XCTAssertNil(MarkdownLinkResolver.resolve("vscode://file/tmp/test.md", relativeTo: documentURL))
    }

    func testSupportedDocuments() {
        XCTAssertTrue(MarkdownLinkResolver.opensInMDViewer(URL(fileURLWithPath: "/tmp/readme.MD")))
        XCTAssertTrue(MarkdownLinkResolver.opensInMDViewer(URL(fileURLWithPath: "/tmp/data.json")))
        XCTAssertTrue(MarkdownLinkResolver.opensInMDViewer(URL(fileURLWithPath: "/tmp/log.txt")))
        XCTAssertFalse(MarkdownLinkResolver.opensInMDViewer(URL(fileURLWithPath: "/tmp/image.png")))
    }

    func testEmptyOrMissingBase() {
        XCTAssertNil(MarkdownLinkResolver.resolve("   ", relativeTo: documentURL))
        XCTAssertNil(MarkdownLinkResolver.resolve("guide.md", relativeTo: nil))
    }
}
