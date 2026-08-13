import Foundation

/// Markdown 링크를 브라우저 URL 또는 로컬 파일 URL로 해석한다.
/// 상대 파일 경로는 현재 Markdown 문서가 있는 폴더를 기준으로 삼는다.
enum MarkdownLinkDestination: Equatable {
    case external(URL)
    case localFile(URL)
    case inDocumentAnchor
}

enum MarkdownLinkResolver {
    private static let externalSchemes: Set<String> = ["http", "https", "mailto"]
    private static let mdViewerExtensions: Set<String> = ["md", "markdown", "mdown", "txt", "json"]

    static func resolve(_ rawHref: String, relativeTo documentURL: URL?) -> MarkdownLinkDestination? {
        let href = rawHref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { return nil }

        if href.hasPrefix("#") {
            return .inDocumentAnchor
        }

        if href.hasPrefix("//"), let url = URL(string: "https:\(href)") {
            return .external(url)
        }

        if let url = URL(string: href), let scheme = url.scheme?.lowercased() {
            if url.isFileURL {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.query = nil
                components?.fragment = nil
                return .localFile((components?.url ?? url).standardizedFileURL)
            }
            guard externalSchemes.contains(scheme) else { return nil }
            return .external(url)
        }

        // 로컬 파일 링크의 query/fragment는 파일 경로가 아니므로 제거한다.
        // 퍼센트 인코딩은 그 뒤에 풀어 `%23`처럼 파일명에 포함된 문자를 보존한다.
        let encodedPath = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard !encodedPath.isEmpty else { return nil }
        let decodedPath = String(encodedPath).removingPercentEncoding ?? String(encodedPath)
        let expandedPath = (decodedPath as NSString).expandingTildeInPath

        if (expandedPath as NSString).isAbsolutePath {
            return .localFile(URL(fileURLWithPath: expandedPath).standardizedFileURL)
        }

        guard let documentURL else { return nil }
        let documentDirectory = documentURL.deletingLastPathComponent()
        let resolved = URL(fileURLWithPath: expandedPath, relativeTo: documentDirectory)
            .standardizedFileURL
        return .localFile(resolved)
    }

    static func opensInMDViewer(_ url: URL) -> Bool {
        mdViewerExtensions.contains(url.pathExtension.lowercased())
    }
}
