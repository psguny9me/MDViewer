import SwiftUI
import AppKit

/// 보이지 않게 윈도우에 얹혀 세 가지만 한다:
/// (1) 미저장 변경 시 닫기 버튼에 • 표시(`isDocumentEdited`),
/// (2) 윈도우가 닫힐 때 묻지 않고 자동 저장 — 실패하면 구제 다이얼로그
///     (다른 위치에 저장 / 변경 내용 버리기)로 데이터 유실을 막는다.
/// (3) 타이틀바의 문서 제목을 더블클릭하면 파일 경로를 클립보드에 복사한다.
///     같은 동작을 하는 복사 버튼도 제목 바로 뒤에 붙인다(발견 가능성).
///
/// 이전 구현은 `window.delegate`를 통째로 가로채(forwarding) SwiftUI의
/// 윈도우 처리(닫기/리사이즈)를 망가뜨렸다. 여기서는 델리게이트를 건드리지 않고
/// `NSWindow.willCloseNotification`만 관찰한다 → 닫기/리사이즈는 SwiftUI가
/// 그대로 담당하고, 우리는 닫히는 순간 저장만 한다.
struct WindowAccessor: NSViewRepresentable {
    let doc: DocumentState

    func makeNSView(context: Context) -> NSView {
        let v = HookView()
        v.doc = doc
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? HookView else { return }
        v.doc = doc
        v.syncEdited()
    }

    /// 윈도우 진입 시점(`viewDidMoveToWindow`)에 확실히 후킹한다.
    /// 마우스 이벤트는 일절 가로채지 않는다(hitTest → nil).
    final class HookView: NSView {
        var doc: DocumentState?
        private var observer: NSObjectProtocol?
        /// 더블클릭 제스처가 붙어 있는 타이틀 필드 — 타이틀바 뷰가 재생성되면
        /// weak 참조가 끊겨 다음 sync 시점에 자동으로 다시 붙인다.
        private weak var titleField: NSTextField?
        /// 제목 뒤의 경로 복사 버튼 — 타이틀 필드와 수명을 같이한다.
        private weak var copyButton: NSButton?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            guard let window else { return }
            syncEdited()
            // 타이틀바 뷰는 윈도우 진입 직후에는 아직 없을 수 있다 → 다음 런루프에서 후킹.
            DispatchQueue.main.async { [weak self] in self?.hookTitleDoubleClick() }
            // 닫히는 순간 자동 저장(델리게이트를 가로채지 않으므로 닫기 자체는 막지 않는다).
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak doc] _ in
                // queue: .main 옵저버이므로 메인 액터 보장.
                MainActor.assumeIsolated {
                    guard let doc else { return }
                    // 윈도우는 이미 닫히는 중이라 막을 수 없다 — 저장 실패 시
                    // 조용히 버리지 말고 구제 다이얼로그를 띄운다.
                    if !doc.save() { doc.rescueUnsavedChanges() }
                }
            }
        }

        func syncEdited() {
            window?.isDocumentEdited = doc?.isDirty ?? false
            hookTitleDoubleClick()
        }

        // MARK: 제목 더블클릭 / 복사 버튼 → 경로 복사

        /// 타이틀바에서 제목 텍스트 필드를 찾아 더블클릭 제스처와 복사 버튼을
        /// 붙인다. SwiftUI/AppKit이 타이틀바 뷰를 재생성할 수 있으므로 멱등하게,
        /// 살아있는 필드에 이미 붙어 있으면 표시 상태만 갱신한다.
        private func hookTitleDoubleClick() {
            guard let window else { return }
            if let titleField, titleField.window === window {            // 이미 후킹됨
                copyButton?.isHidden = (doc?.currentURL == nil)
                return
            }
            // 닫기 버튼이 속한 NSTitlebarView의 컨테이너부터 탐색하면
            // 콘텐츠 영역의 다른 텍스트 필드를 건드릴 일이 없다.
            guard let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview,
                  let field = findTitleField(in: titlebar, title: window.title)
            else { return }
            let gesture = NSClickGestureRecognizer(target: self,
                                                   action: #selector(titleDoubleClicked))
            gesture.numberOfClicksRequired = 2
            field.addGestureRecognizer(gesture)
            titleField = field
            attachCopyButton(to: field)
        }

        /// 제목 필드 바로 뒤(trailing)에 작은 복사 아이콘 버튼을 붙인다.
        private func attachCopyButton(to field: NSTextField) {
            copyButton?.removeFromSuperview()
            guard let container = field.superview else { return }
            let symbol = NSImage(systemSymbolName: "doc.on.doc",
                                 accessibilityDescription: "파일 경로 복사")?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
            let button = NSButton(image: symbol ?? NSImage(),
                                  target: self, action: #selector(copyButtonClicked))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = "파일 경로 복사 (제목 더블클릭도 동일)"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isHidden = (doc?.currentURL == nil)
            container.addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
                button.centerYAnchor.constraint(equalTo: field.centerYAnchor)
            ])
            copyButton = button
        }

        /// 타이틀바 서브트리에서 현재 윈도우 제목을 표시 중인 텍스트 필드를 찾는다.
        private func findTitleField(in view: NSView, title: String) -> NSTextField? {
            if let field = view as? NSTextField, !field.isEditable, field.stringValue == title {
                return field
            }
            for sub in view.subviews {
                if let found = findTitleField(in: sub, title: title) { return found }
            }
            return nil
        }

        @objc private func titleDoubleClicked() { copyPathToClipboard() }
        @objc private func copyButtonClicked() { copyPathToClipboard() }

        private func copyPathToClipboard() {
            guard let url = doc?.currentURL else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.path, forType: .string)
            flashTitle("경로가 복사되었습니다")
        }

        /// 복사 피드백 — 제목을 잠깐 바꿨다가 원래대로 되돌린다.
        /// (SwiftUI가 다음 업데이트에서 제목을 다시 쓰므로 충돌 위험은 없다.)
        private func flashTitle(_ message: String) {
            guard let window else { return }
            let original = window.title
            window.title = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak window] in
                guard let window, window.title == message else { return }
                window.title = original
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
