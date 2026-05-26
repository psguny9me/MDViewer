import SwiftUI
import WebKit

struct SearchBar: View {
    let holder: WebViewHolder
    @Binding var visible: Bool
    @State private var query: String = ""
    @State private var status: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("페이지 내 검색", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { find(backwards: false) }
                .onChange(of: query) { _ in
                    if !query.isEmpty { find(backwards: false) }
                }
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Button { find(backwards: true) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("이전 (⇧↩)")
            .keyboardShortcut(.return, modifiers: .shift)
            .disabled(query.isEmpty)

            Button { find(backwards: false) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("다음 (↩)")
            .disabled(query.isEmpty)

            Button { close() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("닫기 (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { focused = true }
    }

    private func find(backwards: Bool) {
        guard let webView = holder.webView, !query.isEmpty else { return }
        let cfg = WKFindConfiguration()
        cfg.backwards = backwards
        cfg.caseSensitive = false
        cfg.wraps = true
        webView.find(query, configuration: cfg) { result in
            status = result.matchFound ? "" : "없음"
        }
    }

    private func close() {
        visible = false
        query = ""
        status = ""
        // clear highlights
        holder.webView?.evaluateJavaScript("window.getSelection && window.getSelection().removeAllRanges();",
                                           completionHandler: nil)
    }
}
