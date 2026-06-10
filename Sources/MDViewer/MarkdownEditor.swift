import SwiftUI
import AppKit

/// DocumentState가 편집기 NSTextView에 명령(찾기 바 등)을 보낼 수 있게 하는 약한 참조 홀더.
final class EditorHolder {
    weak var textView: NSTextView?
}

/// 원본 마크다운 소스 편집기. NSTextView를 감싸 모노스페이스 폰트,
/// 네이티브 undo(⌘Z)/찾기, 대용량 텍스트 성능을 얻는다.
/// `text` 는 DocumentState.markdownText 에 양방향 바인딩되어
/// 타이핑이 곧바로 라이브 프리뷰(WebView)와 dirty 상태로 전파된다.
///
/// 스크롤 동기화: 마우스 클릭으로 커서를 놓았을 때만 그 소스 줄을 `onSyncLine`으로
/// 보고하고(타이핑·스크롤로는 따라가지 않음), `scrollToLine`(TOC 클릭 등)으로 특정
/// 줄을 편집기 상단으로 끌어온다.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let isDark: Bool
    @Binding var scrollToLine: Int?
    var onSyncLine: ((Int) -> Void)? = nil
    var holder: EditorHolder? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // 마크다운 소스에 끼어드는 자동 치환류는 모두 끈다.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.font = Self.editorFont
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        textView.string = text
        context.coordinator.textView = textView
        holder?.textView = textView
        applyTheme(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self      // 최신 클로저/바인딩 유지

        // 프로그램적 변경(리로드/충돌 해결 등)만 반영. 사용자 타이핑이 만든
        // text 값은 이미 textView.string 과 같으므로 커서/스크롤을 건드리지 않는다.
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            let len = (textView.string as NSString).length
            let safe = selected.compactMap { value -> NSValue? in
                let r = value.rangeValue
                guard r.location <= len else { return nil }
                return NSValue(range: NSRange(location: r.location,
                                              length: min(r.length, len - r.location)))
            }
            if !safe.isEmpty { textView.selectedRanges = safe }
        }
        applyTheme(textView)

        // TOC 클릭 등으로 들어온 줄 이동 요청 처리 후 소비.
        if let line = scrollToLine {
            context.coordinator.scrollEditor(toLine: line)
            DispatchQueue.main.async { self.scrollToLine = nil }
        }
    }

    private func applyTheme(_ textView: NSTextView) {
        let bg: NSColor = isDark ? NSColor(calibratedWhite: 0.12, alpha: 1)
                                 : NSColor(calibratedWhite: 0.99, alpha: 1)
        let fg: NSColor = isDark ? NSColor(calibratedWhite: 0.90, alpha: 1)
                                 : NSColor(calibratedWhite: 0.10, alpha: 1)
        textView.backgroundColor = bg
        textView.textColor = fg
        textView.insertionPointColor = isDark ? .white : .black
        textView.enclosingScrollView?.backgroundColor = bg
        if textView.font != Self.editorFont { textView.font = Self.editorFont }
    }

    private static let editorFont: NSFont =
        .monospacedSystemFont(ofSize: 13, weight: .regular)

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?
        private var lastReportedLine = -1

        init(_ parent: MarkdownEditor) { self.parent = parent }
        deinit { NotificationCenter.default.removeObserver(self) }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // 버퍼로 즉시 커밋 → dirty/저장은 정확, 프리뷰 재렌더는 WebView 쪽에서 디바운스.
            parent.text = tv.string
        }

        // 마우스 클릭으로 커서를 놓았을 때만 프리뷰를 그 위치로 동기화한다.
        // (타이핑·화살표 이동·드래그·스크롤로는 따라가지 않아 산만하지 않다.)
        func textViewDidChangeSelection(_ notification: Notification) {
            switch NSApp.currentEvent?.type {
            case .leftMouseDown, .leftMouseUp:
                reportCaretLine()
            default:
                break
            }
        }

        private func reportCaretLine() {
            guard let tv = textView, let cb = parent.onSyncLine else { return }
            let loc = min(tv.selectedRange().location, (tv.string as NSString).length)
            let line = lineNumber(at: loc, in: tv.string)
            guard line != lastReportedLine else { return }   // 같은 줄이면 생략
            lastReportedLine = line
            cb(line)
        }

        /// charIndex 앞의 줄바꿈 개수 = 0-based 줄 번호.
        private func lineNumber(at charIndex: Int, in s: String) -> Int {
            let ns = s as NSString
            let i = min(max(0, charIndex), ns.length)
            guard i > 0 else { return 0 }
            var count = 0, idx = 0
            while idx < i {
                let r = ns.range(of: "\n", range: NSRange(location: idx, length: i - idx))
                if r.location == NSNotFound { break }
                count += 1
                idx = r.location + 1
            }
            return count
        }

        /// 0-based 줄 시작 문자 인덱스.
        private func characterIndex(forLine line: Int, in s: String) -> Int {
            guard line > 0 else { return 0 }
            let ns = s as NSString
            var idx = 0, current = 0
            while current < line {
                let r = ns.range(of: "\n", range: NSRange(location: idx, length: ns.length - idx))
                if r.location == NSNotFound { return ns.length }
                idx = r.location + 1
                current += 1
            }
            return min(idx, ns.length)
        }

        /// 주어진 소스 줄을 편집기 가시 영역 상단으로 끌어온다.
        func scrollEditor(toLine line: Int) {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let clip = tv.enclosingScrollView?.contentView else { return }
            let ns = tv.string as NSString
            let charIndex = min(max(0, characterIndex(forLine: line, in: tv.string)), ns.length)
            lm.ensureLayout(for: tc)
            // 캐럿(length 0) 위치는 boundingRect가 빈 사각형을 줄 수 있어
            // 라인 프래그먼트 사각형으로 수직 위치를 구한다.
            let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 0),
                                           actualCharacterRange: nil)
            let glyphIdx = min(glyphRange.location, max(0, lm.numberOfGlyphs - 1))
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            let targetY = max(0, lineRect.minY + tv.textContainerInset.height - 4)
            clip.scroll(to: NSPoint(x: 0, y: targetY))
            tv.enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }
}
