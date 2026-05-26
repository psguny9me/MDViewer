# MDViewer 데모

맥용 가벼운 **마크다운 뷰어**입니다. 외부 에디터에서 편집하고, 여기서 *깔끔하게* 봅니다.

## 기능

- 파일 열기 / 드래그앤드롭
- 다크 · 라이트 · 시스템 테마
- 코드 하이라이팅 + 수식(LaTeX)
- 헤딩 기반 목차

## 코드

```swift
import SwiftUI

@main
struct App: App {
    var body: some Scene {
        WindowGroup { Text("Hello, MD!") }
    }
}
```

```python
def fib(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```

## 수식

인라인: $E = mc^2$ 그리고 $\int_0^\infty e^{-x^2}\,dx = \tfrac{\sqrt{\pi}}{2}$.

블록:

$$
\begin{aligned}
\nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \\
\nabla \cdot \mathbf{B} &= 0
\end{aligned}
$$

## 다이어그램 (Mermaid)

```mermaid
flowchart LR
  A[마크다운 파일] --> B(MDViewer)
  B --> C{편집?}
  C -->|예| D[외부 에디터]
  D --> A
  C -->|아니오| E[즐겁게 읽기]
```

## 표

| 언어 | 등장 | 특징 |
|---|---:|---|
| Swift | 2014 | 안전, ARC |
| Rust  | 2010 | 소유권 |
| Go    | 2009 | 단순함 |

## 인용

> "Simplicity is the ultimate sophistication." — Leonardo da Vinci

## 체크리스트

- [x] 마크다운 렌더링
- [x] 다크 모드
- [ ] 라이브 프리뷰 (선택)

## 링크 / 이미지

[Anthropic](https://www.anthropic.com)

---

### 작은 헤딩
> 이 문서가 잘 보이면 셋업 완료!
