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
