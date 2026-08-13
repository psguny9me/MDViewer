# MDViewer

맥용 가벼운 마크다운 · JSON · 텍스트 뷰어 + 에디터. SwiftUI + WKWebView 네이티브 앱.
원본 마크다운을 내장 편집기로 직접 고치며, 분할 화면에서 라이브 프리뷰로 확인.
`.json` 파일은 접이식 트리 뷰어로, `.txt` 파일은 마크다운 해석 없이 원문 그대로 렌더링.

## 빌드 & 실행

```bash
# 개발용
swift run MDViewer

# 테스트
swift test

# .app 번들로 빌드
./scripts/build-app.sh           # debug
./scripts/build-app.sh release   # release

# 실행
open build/MDViewer.app
open -a build/MDViewer.app sample.md
```

## 기능

- 파일 열기 / Finder 드래그앤드롭
- **문서 링크** — 현재 문서 폴더 기준 상대경로와 절대경로·`file://` 지원
  - Markdown·JSON·텍스트 파일은 MDViewer 새 창으로, 그 외 로컬 파일은 기본 앱으로 열기
  - `http(s)`·메일 링크는 기본 브라우저·메일 앱으로 열기
- **경로 복사** — 타이틀바 제목 뒤 복사 버튼 클릭 또는 제목 더블클릭으로 파일 경로 복사
- **최근 열기** 메뉴 (File ▸ 최근 열기)
- 다크 / 라이트 / 시스템 테마
- 코드 하이라이팅 (highlight.js)
- 수식 렌더링 (KaTeX, `$...$` / `$$...$$`)
- **Mermaid 다이어그램** (` ```mermaid `)
- **JSON 뷰어** — `.json` 파일을 접이식 트리로 렌더링
  - 노드별 접기/펼치기 + 모두 펼치기/접기, 키·타입별 컬러, 항목 수 배지
  - 최상위·2단계 키를 목차 사이드바로 표시 + 클릭 스크롤
  - URL 문자열은 클릭 시 기본 브라우저로 열기
  - 파싱 오류 시 오류 메시지 + 하이라이팅된 원문 표시, 초대형 파일은 코드 보기로 자동 폴백
  - 편집(⌘E)·저장(⌘S)·라이브 리로드 등 기존 기능 그대로 동작
- **텍스트 뷰어** — `.txt` 파일을 마크다운 해석 없이 원문 그대로(고정폭 글꼴) 표시
  - 줄 단위 북마크·인라인 변경 강조·라이브 리로드·편집(⌘E)·검색 그대로 동작
  - http(s) URL은 클릭 시 기본 브라우저로 열기
  - 초대형 파일(10만 줄 초과)은 줄 단위 기능 없는 단순 보기로 자동 폴백
- 헤딩 기반 목차 사이드바 + 클릭 스크롤
- **내장 편집** (⌘E) — 원본 마크다운을 직접 편집. `⌘E`로 프리뷰 ⟷ 편집 전환
  - **분할 라이브 프리뷰** — 좌: 소스 편집기 / 우: 실시간 렌더 (디바운스). 가운데 구분선 드래그로 비율 조절
  - **편집기 전체 폭** 토글 (프리뷰 숨김)
  - `⌘S`로 저장(UTF-8). 미저장 변경은 닫기 버튼 •로 표시하고, 창 닫기/앱 종료 시 묻지 않고 자동 저장 (저장 실패 시에만 `다른 위치에 저장 / 버리기` 다이얼로그)
  - **외부 변경 충돌 처리** — 편집 중 다른 앱이 파일을 바꾸면 버퍼를 덮지 않고 `디스크 내용으로 / 내 편집 유지` 배너로 해결
- **라이브 리로드** — 다른 앱이 파일을 저장하면 자동 갱신 (atomic save 대응)
- **인라인 변경 강조** — 리로드 시 추가된 블록을 녹색으로 하이라이트, 상단 배너에 `+N / −M · HH:mm:ss` 요약. 배너 ✕ 또는 `⌥⇧⌘D`로 직접 닫을 때까지 유지 (제거된 라인은 시트에서 라인 번호와 함께 확인)
- **시스템 알림** — 파일이 외부에서 업데이트되면 알림 센터에 `파일명 +N/−M · HH:mm:ss`. 설정에서 토글 가능
- **멀티 윈도우** — 여러 .md 파일을 동시에. `⌘N`으로 새 윈도우, `⌘O`는 빈 윈도우면 거기에, 아니면 새 윈도우. 윈도우별로 독립적인 문서/검색/diff 상태
- **페이지 내 검색** (⌘F) — 다음/이전, 자동 wrap
- **PDF 내보내기** / 인쇄

## 단축키

| 단축키 | 동작 |
|---|---|
| `⌘O` | 파일 열기 |
| `⌘R` | 새로고침 |
| `⌘E` | 편집 ⟷ 프리뷰 전환 |
| `⌘S` | 저장 |
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
├── MDViewerApp.swift       # @main, AppDelegate(종료 시 자동 저장), WindowGroup, 명령(⌘E/⌘S)
├── AppSettings.swift       # 글로벌 설정 (테마/라이브리로드/플래그) + 최근 항목
├── DocumentState.swift     # 윈도우별 상태 (파일/편집버퍼/dirty/save/diff/watch/충돌) + DocumentRegistry
├── AppState.swift          # 공통 모델 (ThemeMode, ViewMode, TOCItem, ChangeDiff, FocusedValueKey)
├── ContentView.swift       # 툴바, 드롭, TOC, 편집/프리뷰 레이아웃 분기, 충돌 배너
├── SettingsView.swift      # 테마/라이브리로드/알림
├── MarkdownEditor.swift    # NSTextView wrapper (소스 편집기, 양방향 바인딩)
├── MarkdownLinkResolver.swift # 원본 문서 기준 상대·절대·외부 링크 해석
├── WindowAccessor.swift    # 윈도우 닫힐 때 자동 저장 + 미저장 • 표시 (willCloseNotification 관찰)
├── SearchBar.swift         # ⌘F 검색 바
├── ChangeBanner.swift      # 변경 알림 배너 + 제거 라인 시트
├── NotificationManager.swift # macOS 알림 센터 통합
├── MarkdownWebView.swift   # WKWebView wrapper (디바운스 라이브 렌더)
└── Resources/
    ├── template.html
    ├── render.js           # markdown-it + KaTeX + mermaid + TOC + diff + JSON 트리 + 텍스트 뷰
    ├── style.css
    └── vendor/             # markdown-it, highlight.js, KaTeX, mermaid (오프라인)

Tests/MDViewerTests/
├── MarkdownLinkResolverTests.swift      # 링크 경로·스킴·지원 확장자 단위 테스트
└── MarkdownWebViewLinkBridgeTests.swift # 렌더된 원문 href의 JS→Swift 전달 테스트
```
