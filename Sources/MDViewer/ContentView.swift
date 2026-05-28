import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var doc: DocumentState

    @State private var showSettings = false
    @State private var showTOC = true
    @State private var scrollToAnchor: String?

    var body: some View {
        Group {
            if doc.currentURL == nil {
                emptyState
            } else {
                document
            }
        }
        .frame(minWidth: 720, minHeight: 480)
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
            if let diff = doc.changeDiff, !diff.isEmpty {
                ChangeBanner(
                    diff: diff,
                    updatedAt: doc.lastUpdatedAt,
                    onShowRemoved: { doc.showRemovedSheet = true },
                    onClose: { doc.clearDiff() }
                )
            }
            if doc.showSearch {
                SearchBar(holder: doc.webHolder, visible: $doc.showSearch)
            }
            HStack(spacing: 0) {
                if showTOC && !doc.toc.isEmpty {
                    tocSidebar
                    Divider()
                }
                MarkdownWebView(
                    markdown: doc.markdownText,
                    isDark: resolvedIsDark,
                    addedLines: Array(doc.changeDiff?.addedLines ?? []).sorted(),
                    onTOC: { items in
                        Task { @MainActor in doc.toc = items }
                    },
                    scrollToAnchor: $scrollToAnchor,
                    holder: doc.webHolder
                )
                .contextMenu {
                    Button("선택 영역 복사") { copySelectionInWebView() }
                    Divider()
                    Button("새로고침") { doc.reload() }
                    Button("외부 에디터에서 편집") { doc.openInExternalEditor() }
                    Divider()
                    Button("찾기...") { doc.showSearch = true }
                    Divider()
                    Button("PDF로 내보내기...") { doc.exportPDF() }
                    Button("인쇄...") { doc.printDocument() }
                }
            }
        }
    }

    private var tocSidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(doc.toc) { item in
                    Button {
                        scrollToAnchor = item.id
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 240)
        .background(Color(NSColor.underPageBackgroundColor).opacity(0.6))
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { showTOC.toggle() } label: { toolbarIcon("sidebar.left") }
                .help("목차 토글")
                .disabled(doc.toc.isEmpty)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { doc.reload() } label: { toolbarIcon("arrow.clockwise") }
                .help("새로고침 (⌘R)")
                .disabled(doc.currentURL == nil)

            Button { doc.openInExternalEditor() } label: { toolbarIcon("pencil.line") }
                .help("외부 에디터에서 편집 (⌘E)")
                .disabled(doc.currentURL == nil)

            Button { settings.cycleTheme() } label: { toolbarIcon(themeIcon) }
                .help("테마: \(settings.themeMode.label) — 클릭하여 전환")

            Button { showSettings = true } label: { toolbarIcon("gearshape.fill") }
                .help("설정")
        }
    }

    /// toolbar 아이콘 공통 스타일 — chrome 위에서도 명확히 보이도록 굵게 + primary tint 강제
    private func toolbarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.primary)
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

    // MARK: - 컨텍스트 메뉴 액션

    private func copySelectionInWebView() {
        guard let webView = doc.webHolder.webView else { return }
        webView.evaluateJavaScript("(window.getSelection ? window.getSelection().toString() : '')") { result, _ in
            guard let s = result as? String, !s.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(s, forType: .string)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in doc.open(url: url) }
        }
        return true
    }
}
