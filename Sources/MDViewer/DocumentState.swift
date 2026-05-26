import Foundation
import SwiftUI
import AppKit
import WebKit
import Combine

@MainActor
final class DocumentState: ObservableObject {
    @Published var currentURL: URL?
    @Published var markdownText: String = ""
    @Published var toc: [TOCItem] = []
    @Published var loadError: String?
    @Published var showSearch: Bool = false
    @Published var changeDiff: ChangeDiff?
    @Published var showRemovedSheet: Bool = false
    @Published var lastUpdatedAt: Date?

    let webHolder = WebViewHolder()
    private weak var settings: AppSettings?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - File watcher
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: CInt = -1
    private var reloadWorkItem: DispatchWorkItem?
    private var reattachAttempts = 0

    func wire(settings: AppSettings) {
        guard self.settings !== settings else { return }
        self.settings = settings
        // settings.liveReload 변경에 반응
        settings.$liveReload
            .dropFirst()
            .sink { [weak self, weak settings] _ in
                guard let self, let settings else { return }
                if settings.liveReload, let url = self.currentURL {
                    self.startWatching(url: url)
                } else {
                    self.stopWatching()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 파일 열기

    func open(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            currentURL = url
            markdownText = text
            changeDiff = nil
            lastUpdatedAt = nil
            loadError = nil
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            settings?.refreshRecents()
            startWatching(url: url)
        } catch {
            loadError = "파일을 읽을 수 없습니다: \(error.localizedDescription)"
        }
    }

    func reload() {
        guard let url = currentURL else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let old = markdownText
            let changed = !old.isEmpty && old != text
            let highlight = settings?.highlightChanges ?? true
            if highlight, changed {
                let diff = Self.computeDiff(old: old, new: text)
                changeDiff = diff.isEmpty ? nil : diff
            } else if !highlight {
                changeDiff = nil
            }
            markdownText = text
            loadError = nil
            if changed {
                let now = Date()
                lastUpdatedAt = now
                if settings?.notifyOnReload ?? false {
                    let a = changeDiff?.addedCount ?? 0
                    let r = changeDiff?.removedCount ?? 0
                    NotificationManager.shared.notifyFileUpdated(
                        url: url, addedCount: a, removedCount: r, time: now
                    )
                }
            }
        } catch {
            loadError = "파일을 읽을 수 없습니다: \(error.localizedDescription)"
        }
    }

    func clearDiff() {
        changeDiff = nil
        showRemovedSheet = false
    }

    // MARK: - 외부 에디터

    func openInExternalEditor() {
        guard let url = currentURL, let settings else { return }
        switch settings.editorMode {
        case .systemDefault:
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-t", url.path]
            do { try proc.run() } catch {
                loadError = "외부 에디터 실행 실패: \(error.localizedDescription)"
            }
        case .custom:
            let raw = settings.editorCustomApp.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                loadError = "사용자 지정 에디터가 설정되지 않았습니다."
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

    // MARK: - File Watcher

    private func startWatching(url: URL) {
        stopWatching()
        guard settings?.liveReload ?? true else { return }
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

    // MARK: - Diff

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
}
