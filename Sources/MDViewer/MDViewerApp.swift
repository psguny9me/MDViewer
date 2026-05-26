import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

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
    // application(_:openFiles:)는 의도적으로 구현하지 않음.
    // WindowGroup(for: URL.self)가 macOS의 파일 열기 이벤트를 자동으로 받아 새 윈도우를 띄움.
    // 핸들러를 같이 구현하면 한 파일당 윈도우가 2배로 만들어진다.
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
                OpenFileButton()
                Menu("최근 열기") {
                    if settings.recentURLs.isEmpty {
                        Text("최근 항목 없음").foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.recentURLs, id: \.self) { url in
                            OpenRecentButton(url: url)
                        }
                        Divider()
                        Button("최근 항목 지우기") { settings.clearRecents() }
                    }
                }
            }
            CommandGroup(after: .newItem) {
                Button("새로고침") { focusedDoc?.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(focusedDoc?.currentURL == nil)

                Button("외부 에디터에서 편집") { focusedDoc?.openInExternalEditor() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(focusedDoc?.currentURL == nil)
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
                Button("찾기...") { focusedDoc?.showSearch = true }
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
    @EnvironmentObject var settings: AppSettings
    @FocusedValue(\.document) private var focusedDoc: DocumentState?
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("열기...") {
            if let url = settings.showOpenPanel() {
                // 현재 활성 윈도우가 비어있으면 거기서 열고, 아니면 새 윈도우
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

private struct OpenRecentButton: View {
    let url: URL
    @FocusedValue(\.document) private var focusedDoc: DocumentState?
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(url.lastPathComponent) {
            if let doc = focusedDoc, doc.currentURL == nil {
                doc.open(url: url)
            } else {
                openWindow(id: "doc", value: url)
            }
        }
    }
}
