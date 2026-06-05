import SwiftUI
import AppKit

/// 보이지 않게 윈도우에 얹혀 두 가지만 한다:
/// (1) 미저장 변경 시 닫기 버튼에 • 표시(`isDocumentEdited`),
/// (2) 윈도우가 닫힐 때 묻지 않고 자동 저장.
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

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            guard let window else { return }
            syncEdited()
            // 닫히는 순간 자동 저장(델리게이트를 가로채지 않으므로 닫기 자체는 막지 않는다).
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak doc] _ in
                doc?.save()
            }
        }

        func syncEdited() {
            window?.isDocumentEdited = doc?.isDirty ?? false
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
