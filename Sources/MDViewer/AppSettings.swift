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
    @Published var editorMode: EditorMode {
        didSet { UserDefaults.standard.set(editorMode.rawValue, forKey: "editorMode") }
    }
    @Published var editorCustomApp: String {
        didSet { UserDefaults.standard.set(editorCustomApp, forKey: "editorCustomApp") }
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

    init() {
        let d = UserDefaults.standard
        themeMode = ThemeMode(rawValue: d.string(forKey: "themeMode") ?? "") ?? .system
        editorMode = EditorMode(rawValue: d.string(forKey: "editorMode") ?? "") ?? .systemDefault
        editorCustomApp = d.string(forKey: "editorCustomApp") ?? ""
        liveReload = d.object(forKey: "liveReload") as? Bool ?? true
        highlightChanges = d.object(forKey: "highlightChanges") as? Bool ?? true
        notifyOnReload = d.object(forKey: "notifyOnReload") as? Bool ?? true
        AppSettings.shared = self
        loadRecents()
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

    func showOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            UTType(filenameExtension: "mdown"),
            UTType(filenameExtension: "txt")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

import UniformTypeIdentifiers
