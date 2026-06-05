import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
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
                    Picker("테마", selection: $settings.themeMode) {
                        ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(8)
            }

            GroupBox("리로드") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("외부에서 파일이 바뀌면 자동 새로고침", isOn: $settings.liveReload)
                    Text("다른 앱이 파일을 변경하면 감지해 자동으로 다시 읽어옵니다. 편집 중 변경이 생기면 충돌 안내를 띄웁니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider().padding(.vertical, 4)
                    Toggle("변경 사항 인라인 강조 (추가/제거)", isOn: $settings.highlightChanges)
                    Text("리로드 직후 추가된 블록을 잠깐 하이라이트하고, 상단에 +/− 요약 배너를 표시합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider().padding(.vertical, 4)
                    Toggle("업데이트 시 시스템 알림", isOn: $settings.notifyOnReload)
                    Text("파일이 외부에서 변경되면 알림 센터에 “파일명 +N/−M · HH:mm:ss” 를 띄웁니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 480)
    }
}
