import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenFiles: (([URL]) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first {
            // 처음 실행 시에만 큰 디폴트 크기 적용
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "didApplyDefaultWindowSize") {
                win.setContentSize(NSSize(width: 1100, height: 820))
                win.center()
                defaults.set(true, forKey: "didApplyDefaultWindowSize")
            }
            win.makeKeyAndOrderFront(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        onOpenFiles?(urls)
        sender.reply(toOpenOrPrint: .success)
    }
}

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()
    @State private var showingSettings = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(state.preferredColorScheme)
                .frame(minWidth: 720, minHeight: 480)
                .onOpenURL { url in state.open(url: url) }
                .task {
                    state.refreshRecents()
                    appDelegate.onOpenFiles = { urls in
                        guard let url = urls.first else { return }
                        Task { @MainActor in state.open(url: url) }
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView().environmentObject(state)
                }
        }
        .defaultSize(width: 1100, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("열기...") { state.showOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)

                Menu("최근 열기") {
                    if state.recentURLs.isEmpty {
                        Text("최근 항목 없음").foregroundStyle(.secondary)
                    } else {
                        ForEach(state.recentURLs, id: \.self) { url in
                            Button(url.lastPathComponent) { state.open(url: url) }
                        }
                        Divider()
                        Button("최근 항목 지우기") { state.clearRecents() }
                    }
                }
            }
            CommandGroup(after: .newItem) {
                Button("새로고침") { state.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(state.currentURL == nil)

                Button("외부 에디터에서 편집") { state.openInExternalEditor() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(state.currentURL == nil)
            }
            CommandGroup(after: .pasteboard) {
                Button("찾기...") { state.showSearch = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(state.currentURL == nil)
            }
            CommandGroup(after: .toolbar) {
                Toggle("변경 사항 인라인 강조", isOn: $state.highlightChanges)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("제거된 내용 보기...") { state.showRemovedSheet = true }
                    .disabled((state.changeDiff?.removedCount ?? 0) == 0)
                Button("강조 지우기") { state.clearDiff() }
                    .keyboardShortcut("d", modifiers: [.command, .shift, .option])
                    .disabled(state.changeDiff == nil)
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("PDF로 내보내기...") { state.exportPDF() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(state.currentURL == nil)
                Button("인쇄...") { state.printDocument() }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(state.currentURL == nil)
            }
            CommandGroup(after: .appSettings) {
                Button("설정...") { showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
