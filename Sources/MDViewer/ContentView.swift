import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false
    @State private var showTOC = true
    @State private var scrollToAnchor: String?

    var body: some View {
        Group {
            if state.currentURL == nil {
                emptyState
            } else {
                document
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle(state.currentURL?.lastPathComponent ?? "MDViewer")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(state)
        }
        .sheet(isPresented: $state.showRemovedSheet) {
            RemovedContentSheet(segments: state.changeDiff?.removedSegments ?? [])
        }
        .animation(.easeInOut(duration: 0.2), value: state.changeDiff?.addedCount)
        .alert("오류",
               isPresented: Binding(get: { state.loadError != nil },
                                    set: { if !$0 { state.loadError = nil } })) {
            Button("확인", role: .cancel) { state.loadError = nil }
        } message: {
            Text(state.loadError ?? "")
        }
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("마크다운 파일을 여세요")
                .font(.title2)
            Text("파일을 창에 드래그하거나, ⌘O 로 열 수 있습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("파일 열기...") { state.showOpenPanel() }
                .controlSize(.large)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 문서 보기

    private var document: some View {
        VStack(spacing: 0) {
            if let diff = state.changeDiff, !diff.isEmpty {
                ChangeBanner(
                    diff: diff,
                    onShowRemoved: { state.showRemovedSheet = true },
                    onClose: { state.clearDiff() }
                )
            }
            if state.showSearch {
                SearchBar(holder: state.webHolder, visible: $state.showSearch)
            }
            HStack(spacing: 0) {
                if showTOC && !state.toc.isEmpty {
                    tocSidebar
                    Divider()
                }
                MarkdownWebView(
                    markdown: state.markdownText,
                    isDark: resolvedIsDark,
                    addedLines: Array(state.changeDiff?.addedLines ?? []).sorted(),
                    onTOC: { items in
                        Task { @MainActor in state.toc = items }
                    },
                    scrollToAnchor: $scrollToAnchor,
                    holder: state.webHolder
                )
            }
        }
    }

    private var tocSidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(state.toc) { item in
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
            Button {
                showTOC.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("목차 토글")
            .disabled(state.toc.isEmpty)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("새로고침 (⌘R)")
            .disabled(state.currentURL == nil)

            Button {
                state.openInExternalEditor()
            } label: {
                Image(systemName: "pencil.line")
            }
            .help("외부 에디터에서 편집 (⌘E)")
            .disabled(state.currentURL == nil)

            Menu {
                Picker("테마", selection: $state.themeMode) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: themeIcon)
            }
            .help("테마")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("설정")
        }
    }

    private var themeIcon: String {
        switch state.themeMode {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    private var resolvedIsDark: Bool {
        switch state.themeMode {
        case .light:  return false
        case .dark:   return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in state.open(url: url) }
        }
        return true
    }
}
