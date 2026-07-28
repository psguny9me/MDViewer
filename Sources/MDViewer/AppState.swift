import Foundation
import SwiftUI

// MARK: - 공통 모델 / Enum

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "시스템"
        case .light:  return "라이트"
        case .dark:   return "다크"
        }
    }
}

/// 문서 종류 — 렌더 파이프라인(마크다운 vs JSON 트리)을 결정한다.
enum DocumentKind: String {
    case markdown, json

    init(url: URL?) {
        self = url?.pathExtension.lowercased() == "json" ? .json : .markdown
    }
}

/// 윈도우의 보기/편집 레이아웃.
enum ViewMode: String, CaseIterable, Identifiable {
    case preview   // 읽기 전용 렌더 (TOC 사이드바 가능)
    case split     // 좌: 소스 편집기 / 우: 라이브 프리뷰
    case editor    // 편집기 전폭
    var id: String { rawValue }
    var isEditing: Bool { self != .preview }
}

struct TOCItem: Identifiable, Hashable, Codable {
    let id: String      // anchor slug
    let level: Int      // 1...6
    let text: String
    var line: Int = 0   // 소스 0-based 줄 번호 (편집기 스크롤용)
}

// MARK: - 북마크

/// 뷰어에서 사용자가 라인 왼쪽 여백을 더블클릭해 새기는 수동 북마크.
struct Bookmark: Identifiable, Codable, Hashable {
    let id: UUID
    var line: Int        // 0-based, markdownText 기준 블록 시작 라인
    var snippet: String  // 원문 라인 텍스트(표시·재매핑용, 마크다운 기호 포함)
    let createdAt: Date

    init(id: UUID = UUID(), line: Int, snippet: String, createdAt: Date = Date()) {
        self.id = id
        self.line = line
        self.snippet = snippet
        self.createdAt = createdAt
    }

    /// 사이드바 표시용 — 라인 앞쪽의 마크다운 기호를 가볍게 걷어낸 라벨.
    var displayLabel: String {
        var s = snippet.trimmingCharacters(in: .whitespaces)
        // 헤딩(#)·인용(>)·리스트(-,*,+)·체크박스 마커를 앞에서 제거
        while let first = s.first, "#>-*+".contains(first) {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespaces)
            if first == "-" || first == "*" || first == "+" {
                if s.hasPrefix("[ ] ") || s.hasPrefix("[x] ") || s.hasPrefix("[X] ") {
                    s.removeFirst(4)
                }
                break  // 리스트 마커는 한 번만
            }
        }
        s = s.replacingOccurrences(of: "**", with: "")
             .replacingOccurrences(of: "`", with: "")
        return s.isEmpty ? "(빈 줄)" : s
    }
}

extension URL {
    /// 북마크/최근항목 저장 키로 쓰는 정규화된 경로 문자열.
    /// (심볼릭 링크/상대경로 차이로 같은 파일이 다른 키가 되는 것을 방지)
    var mdvKey: String {
        standardizedFileURL.resolvingSymlinksInPath().absoluteString
    }
}

struct DiffSegment: Identifiable, Hashable {
    let id = UUID()
    let line: Int       // OLD 텍스트 기준 0-based 라인
    let text: String
}

struct ChangeDiff: Equatable {
    let addedLines: Set<Int>
    let removedSegments: [DiffSegment]
    var addedCount: Int { addedLines.count }
    var removedCount: Int { removedSegments.count }
    var isEmpty: Bool { addedLines.isEmpty && removedSegments.isEmpty }
}

// MARK: - Focused window의 DocumentState를 commands에서 참조하기 위한 키

struct DocumentFocusKey: FocusedValueKey {
    typealias Value = DocumentState
}

extension FocusedValues {
    var document: DocumentState? {
        get { self[DocumentFocusKey.self] }
        set { self[DocumentFocusKey.self] = newValue }
    }
}
