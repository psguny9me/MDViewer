import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var pendingURLs: [URL] = []

    /// DocumentWindow의 task에서 wire. 마지막에 wire된 핸들러가 외부 openFile 이벤트를 받는다.
    var onOpenFiles: (([URL]) -> Void)? {
        didSet {
            guard let handler = onOpenFiles, !pendingURLs.isEmpty else { return }
            let queued = pendingURLs
            pendingURLs.removeAll()
            handler(queued)
        }
    }

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first {
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "didApplyDefaultWindowSize") {
                win.setContentSize(NSSize(width: 1100, height: 820))
                win.center()
                defaults.set(true, forKey: "didApplyDefaultWindowSize")
            }
            win.makeKeyAndOrderFront(nil)
        }
        Task { @MainActor in NotificationManager.shared.requestAuthIfNeeded() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 묻지 않고 모두 자동 저장 후 종료한다. 저장에 실패한 문서만
        // 구제 다이얼로그(다른 위치에 저장 / 버리기)를 띄워 유실을 막는다.
        for doc in DocumentRegistry.shared.dirtyDocuments where !doc.save() {
            doc.rescueUnsavedChanges()
        }
        return .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let handler = onOpenFiles {
            handler(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }
}

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings()
    @FocusedValue(\.document) private var focusedDoc: DocumentState?
    @State private var showingSettings = false

    var body: some Scene {
        WindowGroup("MDViewer", id: "doc", for: URL.self) { $url in
            DocumentWindow(url: $url)
                .environmentObject(settings)
                .preferredColorScheme(settings.preferredColorScheme)
                .sheet(isPresented: $showingSettings) {
                    SettingsView().environmentObject(settings)
                }
        }
        .defaultSize(width: 1100, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                NewWindowButton()
                OpenFileButton(settings: settings)
                RecentsMenu(settings: settings)
            }
            CommandGroup(after: .newItem) {
                Button("새로고침") { focusedDoc?.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(focusedDoc?.currentURL == nil)

                Button(focusedDoc?.isEditing == true ? "프리뷰로 전환" : "편집") {
                    focusedDoc?.toggleEdit()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(focusedDoc?.currentURL == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("저장") { focusedDoc?.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!(focusedDoc?.isDirty ?? false))
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("PDF로 내보내기...") { focusedDoc?.exportPDF() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(focusedDoc?.currentURL == nil)
                Button("인쇄...") { focusedDoc?.printDocument() }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(focusedDoc?.currentURL == nil)
            }
            CommandGroup(after: .pasteboard) {
                Button("찾기...") { focusedDoc?.showFind() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(focusedDoc?.currentURL == nil)
            }
            CommandGroup(after: .toolbar) {
                Toggle("변경 사항 인라인 강조", isOn: $settings.highlightChanges)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("제거된 내용 보기...") { focusedDoc?.showRemovedSheet = true }
                    .disabled((focusedDoc?.changeDiff?.removedCount ?? 0) == 0)
                Button("강조 지우기") { focusedDoc?.clearDiff() }
                    .keyboardShortcut("d", modifiers: [.command, .shift, .option])
                    .disabled(focusedDoc?.changeDiff == nil)
            }
            CommandGroup(after: .appSettings) {
                Button("설정...") { showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - 윈도우 호스팅 뷰

struct DocumentWindow: View {
    @Binding var url: URL?
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @StateObject private var doc = DocumentState()

    var body: some View {
        ContentView()
            .environmentObject(doc)
            .focusedSceneValue(\.document, doc)
            .task {
                doc.wire(settings: settings)
                if let url, doc.currentURL != url {
                    doc.open(url: url)
                }
                // 외부 file open 이벤트를 직접 처리: 빈 윈도우가 있으면 거기, 아니면 새 윈도우
                AppDelegate.shared?.onOpenFiles = { [weak doc] urls in
                    var remaining = urls
                    if let d = doc, d.currentURL == nil, let first = remaining.first {
                        d.open(url: first)
                        remaining.removeFirst()
                    }
                    for u in remaining {
                        openWindow(id: "doc", value: u)
                    }
                }
            }
            .onChange(of: url) { newURL in
                if let newURL, doc.currentURL != newURL {
                    doc.open(url: newURL)
                }
            }
    }
}

// MARK: - Command Buttons (SwiftUI Scene에서 @Environment(\.openWindow) 사용을 위해 작은 View로 감쌈)

private struct NewWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("새 윈도우") {
            openWindow(id: "doc")
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

private struct OpenFileButton: View {
    @ObservedObject var settings: AppSettings
    @FocusedValue(\.document) private var focusedDoc: DocumentState?
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("열기...") {
            if let url = settings.showOpenPanel() {
                if let doc = focusedDoc, doc.currentURL == nil {
                    doc.open(url: url)
                } else {
                    openWindow(id: "doc", value: url)
                }
            }
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}

private struct RecentsMenu: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu("최근 열기") {
            if settings.recentURLs.isEmpty {
                Text("최근 항목 없음").foregroundStyle(.secondary)
            } else {
                ForEach(settings.recentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        openWindow(id: "doc", value: url)
                    }
                }
                Divider()
                Button("최근 항목 지우기") { settings.clearRecents() }
            }
        }
    }
}
