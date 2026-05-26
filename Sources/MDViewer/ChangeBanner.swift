import SwiftUI

struct ChangeBanner: View {
    let diff: ChangeDiff
    let onShowRemoved: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.green)
            Text("변경됨")
                .font(.callout.weight(.semibold))

            Text("+\(diff.addedCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.green)
            Text("/")
                .foregroundStyle(.secondary)
            Text("-\(diff.removedCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.red)

            Spacer()

            if diff.removedCount > 0 {
                Button("제거된 내용 보기") { onShowRemoved() }
                    .buttonStyle(.borderless)
            }
            Button { onClose() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("닫기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct RemovedContentSheet: View {
    let segments: [DiffSegment]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("제거된 내용 (\(segments.count)줄)")
                    .font(.title3).bold()
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(segments) { seg in
                        HStack(alignment: .top, spacing: 10) {
                            Text("L\(seg.line + 1)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                            Text(seg.text.isEmpty ? "(빈 줄)" : seg.text)
                                .font(.system(.body, design: .monospaced))
                                .strikethrough()
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color.red.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 640, height: 480)
    }
}
