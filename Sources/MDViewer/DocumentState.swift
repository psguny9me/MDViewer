import Foundation
import SwiftUI
import AppKit
import WebKit
import Combine

@MainActor
final class DocumentState: ObservableObject {
    @Published var currentURL: URL?
    /// 편집 버퍼이자 렌더 소스. 편집기에 양방향 바인딩된다.
    @Published var markdownText: String = "" {
        didSet { isDirty = (markdownText != savedText) }
    }
    @Published var toc: [TOCItem] = []
    @Published var loadError: String?
    @Published var showSearch: Bool = false
    @Published var changeDiff: ChangeDiff?
    @Published var showRemovedSheet: Bool = false
    @Published var lastUpdatedAt: Date?
    /// 현재 문서의 북마크(UI 바인딩용 로컬 캐시). source of truth는 AppSettings.
    @Published private(set) var bookmarks: [Bookmark] = []

    // MARK: - 편집 상태
    /// 보기/편집 레이아웃.
    @Published var viewMode: ViewMode = .preview
    /// 디스크 기준선과 버퍼가 다른가 (미저장 변경).
    @Published private(set) var isDirty: Bool = false
    /// 편집 중 외부에서 파일이 바뀌었을 때의 충돌 정보. nil이면 충돌 없음.
    @Published var externalChange: ExternalChange?
    /// 마지막으로 디스크에서 읽었거나 저장한 내용 — dirty 판정 및 외부변경 비교의 기준선.
    private var savedText: String = ""

    var isEditing: Bool { viewMode.isEditing }

    let webHolder = WebViewHolder()
    private weak var settings: AppSettings?
    private var cancellables = Set<AnyCancellable>()

    init() {
        DocumentRegistry.shared.register(self)
    }

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

        // 북마크 동기화 — 다른 윈도우가 같은 파일의 북마크를 바꾸면 여기도 갱신.
        settings.$bookmarksByFile
            .sink { [weak self] dict in
                guard let self, let url = self.currentURL else { return }
                let updated = dict[url.mdvKey] ?? []
                if self.bookmarks != updated { self.bookmarks = updated }
            }
            .store(in: &cancellables)
    }

    // MARK: - 파일 열기

    func open(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            currentURL = url
            savedText = text          // 기준선 먼저 → markdownText didSet에서 isDirty=false
            markdownText = text
            changeDiff = nil
            externalChange = nil
            lastUpdatedAt = nil
            loadError = nil
            bookmarks = settings?.bookmarks(for: url) ?? []
            settings?.addRecent(url)
            startWatching(url: url)
        } catch {
            loadError = "파일을 읽을 수 없습니다: \(error.localizedDescription)"
        }
    }

    func reload() {
        guard let url = currentURL else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)

            // 편집 중(dirty)에는 watcher 리로드가 버퍼를 절대 덮지 않는다.
            // 디스크가 기준선과 달라졌다면 충돌 배너로 사용자에게 해결을 맡기고,
            // 같다면(되돌려 쓰기 등) 조용히 무시한다.
            if isDirty {
                if text != savedText {
                    externalChange = ExternalChange(diskText: text)
                }
                return
            }

            let old = markdownText
            let changed = !old.isEmpty && old != text
            // 라인 이동에 맞춰 북마크 재매핑 (old/new 둘 다 보유한 지금 처리).
            if changed, let settings {
                let existing = settings.bookmarks(for: url)
                if !existing.isEmpty {
                    let remapped = Self.remapBookmarks(existing, oldText: old, newText: text)
                    if remapped != existing { settings.setBookmarks(remapped, for: url) }
                }
            }
            // 인라인 변경 강조는 뷰어 기능 — 편집 모드에서는 끈다.
            let highlight = (settings?.highlightChanges ?? true) && !isEditing
            if highlight, changed {
                let diff = Self.computeDiff(old: old, new: text)
                changeDiff = diff.isEmpty ? nil : diff
            } else {
                changeDiff = nil
            }
            savedText = text          // 기준선 갱신 → markdownText didSet에서 isDirty=false
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

    // MARK: - 북마크

    /// 거터 더블클릭으로 들어온 라인 토글. snippet은 렌더 결과가 아니라
    /// markdownText 원문에서 뽑는다(재매핑 정확도).
    func toggleBookmark(line: Int) {
        guard let url = currentURL, let settings else { return }
        let lines = markdownText.components(separatedBy: "\n")
        guard line >= 0, line < lines.count else { return }
        var list = settings.bookmarks(for: url)
        if let idx = list.firstIndex(where: { $0.line == line }) {
            list.remove(at: idx)
        } else {
            let snippet = String(lines[line].prefix(120))
            list.append(Bookmark(line: line, snippet: snippet))
        }
        settings.setBookmarks(list, for: url)
        bookmarks = settings.bookmarks(for: url)   // sink 타이밍과 무관하게 즉시 반영
    }

    func removeBookmark(id: UUID) {
        guard let url = currentURL, let settings else { return }
        var list = settings.bookmarks(for: url)
        list.removeAll { $0.id == id }
        settings.setBookmarks(list, for: url)
        bookmarks = settings.bookmarks(for: url)
    }

    func jumpToBookmark(_ bm: Bookmark) {
        guard let webView = webHolder.webView else { return }
        webView.evaluateJavaScript("window.MDV && window.MDV.scrollToLine(\(bm.line));",
                                   completionHandler: nil)
    }

    /// old→new 라인 매핑(CollectionDifference) 기반 재매핑. 보존된 라인은
    /// 새 위치로 옮기고, 삭제된 라인의 북마크는 snippet 근방 검색으로 보정,
    /// 그래도 못 찾으면 버린다.
    static func remapBookmarks(_ list: [Bookmark], oldText: String, newText: String) -> [Bookmark] {
        let oldLines = oldText.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")
        let diff = newLines.difference(from: oldLines)

        var removed = Set<Int>()                 // old offsets
        var insertedSet = Set<Int>()             // new offsets
        for change in diff {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): insertedSet.insert(offset)
            }
        }
        // old의 보존 라인들을 순서대로 new의 비-insert 위치에 대응시킨다.
        let preservedOld = (0..<oldLines.count).filter { !removed.contains($0) }
        var oldToNew = [Int: Int]()
        var p = 0
        for n in 0..<newLines.count {
            if insertedSet.contains(n) { continue }
            if p < preservedOld.count { oldToNew[preservedOld[p]] = n; p += 1 }
        }

        var result: [Bookmark] = []
        for var bm in list {
            if let newLine = oldToNew[bm.line] {
                bm.line = newLine
                result.append(bm)
            } else if let found = findLine(snippet: bm.snippet, in: newLines, near: bm.line) {
                bm.line = found
                result.append(bm)
            }
            // 둘 다 실패하면 드롭
        }
        return result
    }

    /// snippet과 정확히 일치하는 라인을 `near`에 가장 가까운 순으로 찾는다.
    private static func findLine(snippet: String, in lines: [String], near: Int) -> Int? {
        let target = snippet.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        var best: Int?
        var bestDist = Int.max
        for (i, l) in lines.enumerated() where l.trimmingCharacters(in: .whitespaces) == target {
            let d = abs(i - near)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    // MARK: - 편집 / 저장

    func toggleEdit() {
        viewMode = isEditing ? .preview : .split
    }

    /// split ⟷ editor (프리뷰 표시/숨김). preview 상태면 편집 진입.
    func toggleEditorFullWidth() {
        switch viewMode {
        case .preview: viewMode = .split
        case .split:   viewMode = .editor
        case .editor:  viewMode = .split
        }
    }

    func save() {
        guard let url = currentURL else { return }   // Phase 1: 새 문서(Save As)는 미지원
        guard isDirty else { return }
        // 자기-저장이 watcher를 깨워 리로드 루프를 일으키지 않도록 감시를 잠시 끊는다.
        stopWatching()
        do {
            try markdownText.write(to: url, atomically: true, encoding: .utf8)
            savedText = markdownText
            isDirty = false
            changeDiff = nil
            lastUpdatedAt = nil
            loadError = nil
        } catch {
            loadError = "저장 실패: \(error.localizedDescription)"
        }
        // atomic write는 inode를 교체하므로 새 파일에 다시 부착해야 한다.
        startWatching(url: url)
    }

    /// 충돌 해결: 디스크 내용으로 다시 읽어 내 편집을 버린다.
    func resolveExternalReload() {
        guard let ec = externalChange else { return }
        externalChange = nil
        savedText = ec.diskText
        markdownText = ec.diskText
        changeDiff = nil
    }

    /// 충돌 해결: 내 편집을 유지한다(다음 저장 시 디스크를 덮어씀).
    func resolveExternalKeepMine() {
        externalChange = nil
    }

    /// 편집기 커서/스크롤 위치(소스 줄)에 맞춰 프리뷰를 스크롤한다(분할 모드에서만).
    func syncPreviewToLine(_ line: Int) {
        guard viewMode == .split else { return }
        webHolder.webView?.evaluateJavaScript("window.MDV && MDV.scrollToLine(\(line));",
                                              completionHandler: nil)
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

// MARK: - 외부 변경 충돌

/// 편집 중(dirty) 외부에서 파일이 바뀐 경우의 디스크 스냅샷.
struct ExternalChange: Equatable {
    let diskText: String
}

// MARK: - 열린 문서 레지스트리 (앱 종료 시 미저장 변경 확인용)

@MainActor
final class DocumentRegistry {
    static let shared = DocumentRegistry()

    private final class WeakDoc {
        weak var doc: DocumentState?
        init(_ d: DocumentState) { doc = d }
    }
    private var boxes: [WeakDoc] = []

    func register(_ doc: DocumentState) {
        boxes.append(WeakDoc(doc))
        prune()
    }

    private func prune() {
        boxes.removeAll { $0.doc == nil }
    }

    /// 미저장 변경이 있는 살아있는 문서들.
    var dirtyDocuments: [DocumentState] {
        prune()
        return boxes.compactMap { $0.doc }.filter { $0.isDirty }
    }
}
