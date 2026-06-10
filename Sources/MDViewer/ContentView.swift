import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var doc: DocumentState
    @Environment(\.openWindow) private var openWindow

    @State private var showSettings = false
    @State private var showTOC = true
    @State private var scrollToAnchor: String?
    @State private var editorScrollLine: Int?
    /// 윈도우의 실제(정착된) 외형이 다크인지 — 툴바 아이콘 색을 결정한다.
    @State private var effectiveIsDark = NSApp.effectiveAppearance
        .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

    var body: some View {
        Group {
            if doc.currentURL == nil {
                emptyState
            } else {
                document
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(AppearanceReader { isDark in
            // 외형이 dark↔light로 정착되는 시점에 호출 → 툴바 아이콘 색 재계산.
            if effectiveIsDark != isDark { effectiveIsDark = isDark }
        })
        .background(WindowAccessor(doc: doc))   // 미저장 변경 시 닫기 가드 + 윈도우 • 표시
        .navigationTitle(doc.currentURL?.lastPathComponent ?? "MDViewer")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(settings)
        }
        .sheet(isPresented: $doc.showRemovedSheet) {
            RemovedContentSheet(segments: doc.changeDiff?.removedSegments ?? [])
        }
        .alert("오류",
               isPresented: Binding(get: { doc.loadError != nil },
                                    set: { if !$0 { doc.loadError = nil } })) {
            Button("확인", role: .cancel) { doc.loadError = nil }
        } message: {
            Text(doc.loadError ?? "")
        }
        .animation(.easeInOut(duration: 0.2), value: doc.changeDiff?.addedCount)
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("마크다운 파일을 여세요")
                .font(.title2)
            Text("⌘O 로 열기, ⌘N 으로 새 윈도우. 창에 파일을 끌어다 놓을 수도 있어요.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("파일 열기...") {
                if let url = settings.showOpenPanel() { doc.open(url: url) }
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 문서 보기

    private var document: some View {
        VStack(spacing: 0) {
            // 인라인 변경 강조 배너는 뷰어 기능 — 프리뷰 모드에서만.
            if doc.viewMode == .preview, let diff = doc.changeDiff, !diff.isEmpty {
                ChangeBanner(
                    diff: diff,
                    updatedAt: doc.lastUpdatedAt,
                    onShowRemoved: { doc.showRemovedSheet = true },
                    onClose: { doc.clearDiff() }
                )
            }
            if doc.externalChange != nil {
                externalChangeBanner
            }
            if doc.showSearch && doc.viewMode != .editor {
                SearchBar(holder: doc.webHolder, visible: $doc.showSearch)
            }
            editorAndPreview
        }
    }

    /// 보기 모드에 따른 본문 레이아웃. 사이드바(목차·북마크)는 모든 모드 공통(좌측).
    private var editorAndPreview: some View {
        HStack(spacing: 0) {
            if showTOC && (!doc.toc.isEmpty || !doc.bookmarks.isEmpty) {
                sidebar
                Divider()
            }
            switch doc.viewMode {
            case .preview:
                preview
            case .split:
                HSplitView {
                    editor.frame(minWidth: 280)
                    preview.frame(minWidth: 280)
                }
            case .editor:
                editor
            }
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: $doc.markdownText,
            isDark: resolvedIsDark,
            scrollToLine: $editorScrollLine,
            onSyncLine: { line in doc.syncPreviewToLine(line) },
            holder: doc.editorHolder
        )
    }

    private var preview: some View {
        MarkdownWebView(
            markdown: doc.markdownText,
            isDark: resolvedIsDark,
            addedLines: Array(doc.changeDiff?.addedLines ?? []).sorted(),
            bookmarkLines: doc.bookmarks.map(\.line),
            onTOC: { items in
                Task { @MainActor in doc.toc = items }
            },
            onEditorLine: { line in if doc.isEditing { editorScrollLine = line } },  // 프리뷰 더블클릭 → 편집기 스크롤
            onBookmarkToggle: { doc.toggleBookmark(line: $0) },                      // 거터 더블클릭 → 북마크 토글
            scrollToAnchor: $scrollToAnchor,
            holder: doc.webHolder,
            menuActions: WebViewMenuActions(
                isEditing: doc.isEditing,
                reload: { doc.reload() },
                toggleEdit: { doc.toggleEdit() },
                save: { doc.save() },
                find: { doc.showFind() },
                exportPDF: { doc.exportPDF() },
                printDoc: { doc.printDocument() }
            )
        )
    }

    /// 편집 중 외부에서 파일이 바뀌었을 때의 충돌 해결 배너.
    private var externalChangeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("디스크에서 파일이 변경됨")
                .font(.callout.weight(.semibold))
            Text("편집 중인 내용과 다릅니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("디스크 내용으로") { doc.resolveExternalReload() }
                .buttonStyle(.borderless)
            Button("내 편집 유지") { doc.resolveExternalKeepMine() }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !doc.bookmarks.isEmpty {
                    if !doc.toc.isEmpty { sectionHeader("북마크") }
                    ForEach(doc.bookmarks) { bm in
                        bookmarkRow(bm)
                    }
                    if !doc.toc.isEmpty {
                        Divider().padding(.vertical, 6)
                        sectionHeader("목차")
                    }
                }
                ForEach(doc.toc) { item in
                    Button {
                        scrollToAnchor = item.id                       // 프리뷰(있으면)
                        if doc.isEditing { editorScrollLine = item.line } // 편집기(있으면)
                    } label: {
                        Text(item.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, CGFloat(max(0, item.level - 1)) * 12)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(item.level <= 1 ? .system(.body, design: .default).weight(.semibold)
                                                  : .system(.body))
                            .foregroundStyle(item.level <= 2 ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
                // 북마크가 아직 없으면 기능 존재와 사용법을 가볍게 알린다.
                if doc.bookmarks.isEmpty {
                    bookmarkHint
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 240)
        .background(Color(NSColor.underPageBackgroundColor).opacity(0.6))
    }

    /// 북마크가 없을 때 사이드바 하단에 표시되는 사용법 힌트.
    private var bookmarkHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "bookmark")
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.8))
            Text("줄 왼쪽 여백을 더블클릭하면 북마크가 추가됩니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .padding(.trailing, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .padding(.bottom, 2)
    }

    private func bookmarkRow(_ bm: Bookmark) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Button {
                doc.jumpToBookmark(bm)
            } label: {
                Text(bm.displayLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.callout)
            }
            .buttonStyle(.plain)
            Button {
                doc.removeBookmark(id: bm.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("북마크 삭제")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { showTOC.toggle() } label: { toolbarIcon("sidebar.left") }
                .help("목차·북마크 토글")
                .disabled(doc.toc.isEmpty && doc.bookmarks.isEmpty)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { doc.reload() } label: { toolbarIcon("arrow.clockwise") }
                .help("새로고침 (⌘R)")
                .disabled(doc.currentURL == nil)

            Button { doc.toggleEdit() } label: {
                toolbarIcon(doc.isEditing ? "eye" : "square.and.pencil")
            }
            .help(doc.isEditing ? "프리뷰로 전환 (⌘E)" : "편집 (⌘E)")
            .disabled(doc.currentURL == nil)

            if doc.isEditing {
                Button { doc.toggleEditorFullWidth() } label: {
                    toolbarIcon(doc.viewMode == .editor ? "rectangle.split.2x1" : "rectangle")
                }
                .help(doc.viewMode == .editor ? "분할 보기(프리뷰 표시)" : "편집기 전체 폭")

                Button { doc.save() } label: { toolbarIcon("square.and.arrow.down") }
                    .help("저장 (⌘S)")
                    .disabled(!doc.isDirty)
            }

            Button { settings.cycleTheme() } label: { toolbarIcon(themeIcon) }
                .help("테마: \(settings.themeMode.label) — 클릭하여 전환")

            Button { showSettings = true } label: { toolbarIcon("gearshape.fill") }
                .help("설정")
        }
    }

    /// toolbar 아이콘 공통 스타일 — chrome 위에서도 명확히 보이도록 굵게 + 정착된
    /// 외형 기준으로 색을 직접 지정한다. (Color.primary는 외형 전환 시 한 프레임
    /// 늦게 갱신돼 다크→시스템(라이트) 전환 직후 흰 아이콘이 안 보이는 문제가 있음.)
    private func toolbarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(effectiveIsDark ? Color.white : Color.black)
    }

    private var themeIcon: String {
        switch settings.themeMode {
        case .system: return "circle.dashed"   // 항상 outline만 — multi-tone 문제 없음
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    private var resolvedIsDark: Bool {
        switch settings.themeMode {
        case .light:  return false
        case .dark:   return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        // 첫 파일은 이 윈도우에, 나머지는 각각 새 윈도우로.
        for (idx, provider) in providers.enumerated() {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if idx == 0 {
                        doc.open(url: url)
                    } else {
                        openWindow(id: "doc", value: url)
                    }
                }
            }
        }
        return true
    }
}

// MARK: - 외형(다크/라이트) 변화 감지

/// 윈도우에 보이지 않게 얹혀, AppKit이 실제 외형 변화를 확정하는 시점
/// (`viewDidChangeEffectiveAppearance`)에 콜백을 던진다. SwiftUI의
/// `preferredColorScheme` 전환도 여기서 정확히 잡힌다.
private struct AppearanceReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReaderView)?.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?

        // 외형 감지 전용 — 마우스/드래그 이벤트는 일절 가로채지 않는다.
        // (onDrop 등 위쪽 SwiftUI 레이어로 그대로 통과시킨다.)
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            DispatchQueue.main.async { [weak self] in self?.onChange?(isDark) }
        }
    }
}
