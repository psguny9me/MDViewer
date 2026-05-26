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

enum EditorMode: String, CaseIterable, Identifiable {
    case systemDefault, custom
    var id: String { rawValue }
}

struct TOCItem: Identifiable, Hashable, Codable {
    let id: String      // anchor slug
    let level: Int      // 1...6
    let text: String
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
