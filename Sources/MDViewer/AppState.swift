import Foundation
import SwiftUI
import AppKit
import WebKit

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "시스템"
        case .light:  return "라이트"
        case .dark:   return "다크"
        }
    }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case systemDefault, custom
    var id: String { rawValue }
}

struct TOCItem: Identifiable, Hashable, Codable {
    let id: String      // anchor slug
    let level: Int      // 1...6
    let text: String
}

struct DiffSegment: Identifiable, Hashable {
    let id = UUID()
    let line: Int       // OLD 텍스트 기준 0-based 라인
    let text: String
}

struct ChangeDiff: Equatable {
    let addedLines: Set<Int>           // NEW 텍스트 기준 0-based
    let removedSegments: [DiffSegment] // OLD 텍스트 기준
    var addedCount: Int { addedLines.count }
    var removedCount: Int { removedSegments.count }
    var isEmpty: Bool { addedLines.isEmpty && removedSegments.isEmpty }
}

@MainActor
final class AppState: ObservableObject {
    @Published var currentURL: URL?
    @Published var markdownText: String = ""
    @Published var toc: [TOCItem] = []
    @Published var loadError: String?
    @Published var recentURLs: [URL] = []
    @Published var showSearch: Bool = false
    @Published var changeDiff: ChangeDiff?
    @Published var showRemovedSheet: Bool = false

    @Published var themeMode: ThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode") }
    }
    @Published var editorMode: EditorMode {
        didSet { UserDefaults.standard.set(editorMode.rawValue, forKey: "editorMode") }
    }
    /// Bundle ID 또는 .app 절대 경로
    @Published var editorCustomApp: String {
        didSet { UserDefaults.standard.set(editorCustomApp, forKey: "editorCustomApp") }
    }
    @Published var liveReload: Bool {
        didSet {
            UserDefaults.standard.set(liveReload, forKey: "liveReload")
            liveReloadDidChange()
        }
    }
    @Published var highlightChanges: Bool {
        didSet { UserDefaults.standard.set(highlightChanges, forKey: "highlightChanges") }
    }

    /// ContentView가 만든 WKWebView 핸들 - App.commands에서도 접근하기 위함
    let webHolder = WebViewHolder()

    init() {
        let d = UserDefaults.standard
        self.themeMode = ThemeMode(rawValue: d.string(forKey: "themeMode") ?? "") ?? .system
        self.editorMode = EditorMode(rawValue: d.string(forKey: "editorMode") ?? "") ?? .systemDefault
        self.editorCustomApp = d.string(forKey: "editorCustomApp") ?? ""
        self.liveReload = d.object(forKey: "liveReload") as? Bool ?? true
        self.highlightChanges = d.object(forKey: "highlightChanges") as? Bool ?? true
    }

    // MARK: - 파일 watcher
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: CInt = -1
    private var reloadWorkItem: DispatchWorkItem?
    /// 외부 에디터 atomic save 대응을 위한 재구독 카운터
    private var reattachAttempts = 0

    /// macOS 권장 컬러스킴 (nil = 시스템)
    var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    // MARK: - 파일 열기

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!,
                                     .init(filenameExtension: "markdown")!,
                                     .init(filenameExtension: "mdown")!,
                                     .init(filenameExtension: "txt")!].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            self.currentURL = url
            self.markdownText = text
            self.loadError = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            refreshRecents()
            startWatching(url: url)
        } catch {
            self.loadError = "파일을 읽을 수 없습니다: \(error.localizedDescription)"
        }
    }

    func refreshRecents() {
        recentURLs = NSDocumentController.shared.recentDocumentURLs
    }

    func clearRecents() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecents()
    }

    func reload() {
        guard let url = currentURL else { return }
        // watch는 끊지 않고 내용만 다시 로드 (open 호출 시 watch가 reset되므로 동일 url 재오픈)
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let old = self.markdownText
            if highlightChanges, !old.isEmpty, old != text {
                let diff = Self.computeDiff(old: old, new: text)
                self.changeDiff = diff.isEmpty ? nil : diff
            } else {
                self.changeDiff = nil
            }
            self.markdownText = text
            self.loadError = nil
        } catch {
            self.loadError = "파일을 읽을 수 없습니다: \(error.localizedDescription)"
        }
    }

    func clearDiff() {
        changeDiff = nil
        showRemovedSheet = false
    }

    static func computeDiff(old: String, new: String) -> ChangeDiff {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let diff = newLines.difference(from: oldLines)
        var added = Set<Int>()
        var removed: [DiffSegment] = []
        for change in diff {
            switch change {
            case let .insert(offset, element, _):
                if !element.trimmingCharacters(in: .whitespaces).isEmpty {
                    added.insert(offset)
                }
            case let .remove(offset, element, _):
                if !element.trimmingCharacters(in: .whitespaces).isEmpty {
                    removed.append(DiffSegment(line: offset, text: element))
                }
            }
        }
        return ChangeDiff(addedLines: added, removedSegments: removed)
    }

    // MARK: - File Watcher

    private func startWatching(url: URL) {
        stopWatching()
        guard liveReload else { return }
        attach(url: url)
    }

    func stopWatching() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        watcher?.cancel()
        watcher = nil
        if watchedFD >= 0 {
            close(watchedFD)
            watchedFD = -1
        }
        reattachAttempts = 0
    }

    /// liveReload 토글 시 호출
    func liveReloadDidChange() {
        if liveReload, let url = currentURL {
            startWatching(url: url)
        } else {
            stopWatching()
        }
    }

    private func attach(url: URL) {
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.handleFileVanished(originalURL: url)
            } else {
                self.scheduleReload()
            }
        }
        src.setCancelHandler { [fd] in close(fd) }
        watchedFD = fd
        watcher = src
        src.resume()
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reload()
        }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: work)
    }

    /// VS Code 등의 atomic save는 파일을 지웠다가 같은 경로로 재생성한다.
    /// 잠시 후 같은 경로로 재구독을 시도.
    private func handleFileVanished(originalURL: URL) {
        watcher?.cancel()
        watcher = nil
        if watchedFD >= 0 {
            close(watchedFD)
            watchedFD = -1
        }
        guard reattachAttempts < 30 else {
            reattachAttempts = 0
            return
        }
        reattachAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
            guard let self else { return }
            guard self.currentURL == originalURL else { return }
            if FileManager.default.fileExists(atPath: originalURL.path) {
                self.reattachAttempts = 0
                self.attach(url: originalURL)
                self.scheduleReload()
            } else {
                self.handleFileVanished(originalURL: originalURL)
            }
        }
    }

    // MARK: - 외부 에디터로 열기

    func openInExternalEditor() {
        guard let url = currentURL else { return }
        switch editorMode {
        case .systemDefault:
            openWithSystemTextEditor(url)
        case .custom:
            openWithCustomApp(url)
        }
    }

    private func openWithSystemTextEditor(_ url: URL) {
        // `open -t` 는 LaunchServices에서 등록된 기본 텍스트 에디터로 엶
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-t", url.path]
        do { try proc.run() } catch {
            loadError = "외부 에디터 실행 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - 인쇄 / PDF

    func printDocument() {
        guard let webView = webHolder.webView else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    func exportPDF() {
        guard let webView = webHolder.webView else { return }
        let panel = NSSavePanel()
        let base = currentURL?.deletingPathExtension().lastPathComponent ?? "Document"
        panel.nameFieldStringValue = "\(base).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        let cfg = WKPDFConfiguration()
        webView.createPDF(configuration: cfg) { [weak self] result in
            switch result {
            case .success(let data):
                do { try data.write(to: dest) }
                catch {
                    Task { @MainActor in self?.loadError = "PDF 저장 실패: \(error.localizedDescription)" }
                }
            case .failure(let error):
                Task { @MainActor in self?.loadError = "PDF 생성 실패: \(error.localizedDescription)" }
            }
        }
    }

    private func openWithCustomApp(_ url: URL) {
        let raw = editorCustomApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            loadError = "사용자 지정 에디터가 설정되지 않았습니다. 설정에서 지정하세요."
            return
        }

        let appURL: URL?
        if raw.hasPrefix("/") || raw.hasSuffix(".app") {
            appURL = URL(fileURLWithPath: raw)
        } else {
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw)
        }
        guard let resolved = appURL, FileManager.default.fileExists(atPath: resolved.path) else {
            loadError = "지정한 에디터를 찾을 수 없습니다: \(raw)"
            return
        }

        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: resolved, configuration: cfg) { _, error in
            if let error {
                Task { @MainActor in
                    self.loadError = "외부 에디터 실행 실패: \(error.localizedDescription)"
                }
            }
        }
    }
}
