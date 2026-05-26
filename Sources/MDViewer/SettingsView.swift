import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("설정").font(.title2).bold()
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            GroupBox("외관") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("테마", selection: $state.themeMode) {
                        ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(8)
            }

            GroupBox("리로드") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("외부 에디터에서 저장 시 자동 새로고침", isOn: $state.liveReload)
                    Text("파일 변경을 감지해 자동으로 다시 읽어옵니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("외부 에디터") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("열기 방식", selection: $state.editorMode) {
                        Text("시스템 기본 텍스트 에디터").tag(EditorMode.systemDefault)
                        Text("사용자 지정 앱").tag(EditorMode.custom)
                    }
                    .pickerStyle(.radioGroup)

                    if state.editorMode == .custom {
                        HStack {
                            TextField("앱 경로 또는 Bundle ID",
                                      text: $state.editorCustomApp,
                                      prompt: Text("/Applications/Visual Studio Code.app"))
                                .textFieldStyle(.roundedBorder)
                            Button("선택...") { chooseAppFile() }
                        }
                        Text("예: `/Applications/Visual Studio Code.app`, `com.microsoft.VSCode`, `/Applications/Typora.app`")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 480)
    }

    private func chooseAppFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            state.editorCustomApp = url.path
        }
    }
}
