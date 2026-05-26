# MDViewer

맥용 가벼운 마크다운 뷰어. SwiftUI + WKWebView 네이티브 앱.
편집은 외부 에디터(시스템 기본 또는 사용자 지정)로 위임하고, 뷰어는 깔끔한 렌더링에 집중.

## 빌드 & 실행

```bash
# 개발용
swift run MDViewer

# .app 번들로 빌드
./scripts/build-app.sh           # debug
./scripts/build-app.sh release   # release

# 실행
open build/MDViewer.app
open -a build/MDViewer.app sample.md
```

## 기능

- 파일 열기 / Finder 드래그앤드롭
- **최근 열기** 메뉴 (File ▸ 최근 열기)
- 다크 / 라이트 / 시스템 테마
- 코드 하이라이팅 (highlight.js)
- 수식 렌더링 (KaTeX, `$...$` / `$$...$$`)
- **Mermaid 다이어그램** (` ```mermaid `)
- 헤딩 기반 목차 사이드바 + 클릭 스크롤
- **라이브 리로드** — 외부 에디터에서 저장하면 자동 갱신 (atomic save 대응)
- **인라인 변경 강조** — 리로드 시 추가된 블록을 녹색으로 하이라이트, 상단 배너에 `+N / −M · HH:mm:ss` 요약. 배너 ✕ 또는 `⌥⇧⌘D`로 직접 닫을 때까지 유지 (제거된 라인은 시트에서 라인 번호와 함께 확인)
- **시스템 알림** — 파일이 외부에서 업데이트되면 알림 센터에 `파일명 +N/−M · HH:mm:ss`. 설정에서 토글 가능
- **멀티 윈도우** — 여러 .md 파일을 동시에. `⌘N`으로 새 윈도우, `⌘O`는 빈 윈도우면 거기에, 아니면 새 윈도우. 윈도우별로 독립적인 문서/검색/diff 상태
- **페이지 내 검색** (⌘F) — 다음/이전, 자동 wrap
- **PDF 내보내기** / 인쇄
- 외부 에디터 연동 (⌘E)
  - 시스템 기본 텍스트 에디터 (`open -t`)
  - 사용자 지정 (.app 경로 또는 Bundle ID)

## 단축키

| 단축키 | 동작 |
|---|---|
| `⌘O` | 파일 열기 |
| `⌘R` | 새로고침 |
| `⌘E` | 외부 에디터에서 편집 |
| `⌘F` | 페이지 내 검색 |
| `⌘P` | 인쇄 |
| `⇧⌘E` | PDF로 내보내기 |
| `⇧⌘D` | 변경 사항 인라인 강조 토글 |
| `⌥⇧⌘D` | 강조 지우기 |
| `⌘N` | 새 윈도우 |
| `⌘,` | 설정 |

## 구조

```
Sources/MDViewer/
├── MDViewerApp.swift       # @main, AppDelegate, WindowGroup(for: URL.self), 명령
├── AppSettings.swift       # 글로벌 설정 (테마/에디터/플래그) + 최근 항목
├── DocumentState.swift     # 윈도우별 문서 상태 (파일/diff/watch/PDF/인쇄)
├── AppState.swift          # 공통 모델 (ThemeMode, TOCItem, ChangeDiff, FocusedValueKey)
├── ContentView.swift       # 툴바, 드롭, TOC 사이드바
├── SettingsView.swift      # 외부 에디터/테마/라이브리로드/알림
├── SearchBar.swift         # ⌘F 검색 바
├── ChangeBanner.swift      # 변경 알림 배너 + 제거 라인 시트
├── NotificationManager.swift # macOS 알림 센터 통합
├── MarkdownWebView.swift   # WKWebView wrapper
└── Resources/
    ├── template.html
    ├── render.js           # markdown-it + KaTeX + mermaid + TOC + diff
    ├── style.css
    └── vendor/             # markdown-it, highlight.js, KaTeX, mermaid (오프라인)
```
