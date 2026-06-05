import SwiftUI
import AppKit

/// 보이지 않게 윈도우에 얹혀, 해당 윈도우의 NSWindowDelegate를 가로채
/// (1) 미저장 변경 시 닫기 버튼에 • 표시, (2) 닫을 때 저장 확인을 띄운다.
/// 기존 SwiftUI 윈도우 델리게이트는 forwarding으로 보존한다.
struct WindowAccessor: NSViewRepresentable {
    let doc: DocumentState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        // 뷰가 윈도우에 삽입된 뒤 델리게이트를 가로채야 하므로 다음 런루프로 미룬다.
        Task { @MainActor in coordinator.attach(to: view.window, doc: doc) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let doc = doc
        Task { @MainActor in
            coordinator.doc = doc
            if coordinator.window == nil {
                coordinator.attach(to: nsView.window, doc: doc)
            }
            coordinator.syncEdited()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var previousDelegate: NSWindowDelegate?
        var doc: DocumentState?

        @MainActor
        func attach(to window: NSWindow?, doc: DocumentState) {
            guard let window, self.window == nil else { return }
            self.window = window
            self.doc = doc
            previousDelegate = window.delegate
            window.delegate = self
            syncEdited()
        }

        @MainActor
        func syncEdited() {
            window?.isDocumentEdited = doc?.isDirty ?? false
        }

        // MARK: 닫기 가드

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let doc, doc.isDirty else { return true }
            let alert = NSAlert()
            alert.messageText = "변경 사항을 저장하시겠습니까?"
            let name = doc.currentURL?.lastPathComponent ?? "문서"
            alert.informativeText = "“\(name)”의 변경 내용을 저장하지 않으면 잃게 됩니다."
            alert.addButton(withTitle: "저장")        // .alertFirstButtonReturn
            alert.addButton(withTitle: "저장 안 함")    // .alertSecondButtonReturn
            alert.addButton(withTitle: "취소")         // .alertThirdButtonReturn
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                doc.save()
                return !doc.isDirty          // 저장 실패하면 닫지 않음
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }

        // MARK: 기존 델리게이트 forwarding

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return previousDelegate?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if previousDelegate?.responds(to: aSelector) == true { return previousDelegate }
            return nil
        }
    }
}
