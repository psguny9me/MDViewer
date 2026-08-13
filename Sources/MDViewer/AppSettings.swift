import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppSettings: ObservableObject {
    static private(set) weak var shared: AppSettings?

    @Published var recentURLs: [URL] = []

    @Published var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode") }
    }
    @Published var liveReload: Bool {
        didSet { UserDefaults.standard.set(liveReload, forKey: "liveReload") }
    }
    @Published var highlightChanges: Bool {
        didSet { UserDefaults.standard.set(highlightChanges, forKey: "highlightChanges") }
    }
    @Published var notifyOnReload: Bool {
        didSet { UserDefaults.standard.set(notifyOnReload, forKey: "notifyOnReload") }
    }

    /// 파일별 북마크 — 정규화 경로(`URL.mdvKey`)를 키로. 모든 윈도우의
    /// source of truth라 `@Published`로 두어 같은 파일을 연 여러
    /// DocumentState가 변경을 함께 받게 한다.
    @Published private(set) var bookmarksByFile: [String: [Bookmark]] = [:]

    init() {
        let d = UserDefaults.standard
        themeMode = ThemeMode(rawValue: d.string(forKey: "themeMode") ?? "") ?? .system
        liveReload = d.object(forKey: "liveReload") as? Bool ?? true
        highlightChanges = d.object(forKey: "highlightChanges") as? Bool ?? true
        notifyOnReload = d.object(forKey: "notifyOnReload") as? Bool ?? true
        AppSettings.shared = self
        loadRecents()
        loadBookmarks()
    }

    var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    func cycleTheme() {
        let all = ThemeMode.allCases
        let i = all.firstIndex(of: themeMode) ?? 0
        themeMode = all[(i + 1) % all.count]
    }

    // MARK: - 최근 파일 (자체 관리 — UserDefaults 백업 + NSDocumentController 동기화)

    private static let recentsKey = "recentDocumentURLs"
    private static let recentsLimit = 12

    private func loadRecents() {
        let strings = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        let urls = strings.compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        recentURLs = Array(urls.prefix(Self.recentsLimit))
    }

    private func persistRecents() {
        let strings = recentURLs.prefix(Self.recentsLimit).map { $0.absoluteString }
        UserDefaults.standard.set(Array(strings), forKey: Self.recentsKey)
    }

    func addRecent(_ url: URL) {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        recentURLs.removeAll { $0.standardizedFileURL.resolvingSymlinksInPath() == normalized }
        recentURLs.insert(normalized, at: 0)
        if recentURLs.count > Self.recentsLimit {
            recentURLs = Array(recentURLs.prefix(Self.recentsLimit))
        }
        persistRecents()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func clearRecents() {
        recentURLs = []
        persistRecents()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    // MARK: - 북마크 (UserDefaults JSON 백업)

    private static let bookmarksKey = "bookmarksByFile"

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarksKey),
              let decoded = try? JSONDecoder().decode([String: [Bookmark]].self, from: data)
        else { return }
        // 존재하지 않는 파일이라도 즉시 삭제하지 않는다(외장 디스크 미연결 등 대비).
        bookmarksByFile = decoded
    }

    private func persistBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarksByFile) else { return }
        UserDefaults.standard.set(data, forKey: Self.bookmarksKey)
    }

    func bookmarks(for url: URL) -> [Bookmark] {
        bookmarksByFile[url.mdvKey] ?? []
    }

    func setBookmarks(_ list: [Bookmark], for url: URL) {
        let key = url.mdvKey
        if list.isEmpty {
            bookmarksByFile.removeValue(forKey: key)
        } else {
            bookmarksByFile[key] = list.sorted { $0.line < $1.line }
        }
        persistBookmarks()
    }

    func showOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "mdown"),
            UTType(filenameExtension: "txt"),
            UTType.json
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

import UniformTypeIdentifiers
