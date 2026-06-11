(function () {
  'use strict';

  // ----- slug 생성 (헤딩 anchor) -----
  function slugify(text) {
    return text
      .toLowerCase()
      .trim()
      .replace(/[\s]+/g, '-')
      .replace(/[^\p{L}\p{N}\-_]/gu, '')
      .replace(/-{2,}/g, '-')
      .replace(/^-|-$/g, '') || 'section';
  }

  // ----- markdown-it 인스턴스 -----
  var md = window.markdownit({
    html: false,
    linkify: true,
    typographer: true,
    breaks: false,
    highlight: function (str, lang) {
      // mermaid 코드블록은 후처리로 렌더링 — 원본 보존하고 마커만 부여
      if (lang === 'mermaid') {
        return '<pre class="mermaid-source" data-mermaid="1">' +
               md.utils.escapeHtml(str) + '</pre>';
      }
      if (lang && window.hljs && window.hljs.getLanguage(lang)) {
        try {
          return '<pre class="hljs"><code class="hljs language-' + lang + '">' +
                 window.hljs.highlight(str, { language: lang, ignoreIllegals: true }).value +
                 '</code></pre>';
        } catch (_) {}
      }
      return '<pre class="hljs"><code class="hljs">' + md.utils.escapeHtml(str) + '</code></pre>';
    }
  });

  // ----- Mermaid 초기화 -----
  var mermaidReady = false;
  function initMermaid(isDark) {
    if (!window.mermaid) return;
    try {
      window.mermaid.initialize({
        startOnLoad: false,
        theme: isDark ? 'dark' : 'default',
        securityLevel: 'strict',
        fontFamily: 'inherit'
      });
      mermaidReady = true;
    } catch (_) { mermaidReady = false; }
  }

  function renderMermaid(root) {
    if (!window.mermaid) return;
    var blocks = root.querySelectorAll('pre.mermaid-source[data-mermaid="1"]');
    var idx = 0;
    blocks.forEach(function (block) {
      var src = block.textContent;
      var id = 'mmd-' + Date.now() + '-' + (idx++);
      try {
        // mermaid 10.x — render는 Promise 반환
        var p = window.mermaid.render(id, src);
        if (p && typeof p.then === 'function') {
          p.then(function (res) {
            var wrap = document.createElement('div');
            wrap.className = 'mermaid-rendered';
            wrap.innerHTML = res.svg;
            block.replaceWith(wrap);
          }).catch(function (err) {
            var msg = document.createElement('pre');
            msg.className = 'mermaid-error';
            msg.textContent = 'Mermaid 오류: ' + (err && err.message ? err.message : err);
            block.replaceWith(msg);
          });
        }
      } catch (e) {
        var msg = document.createElement('pre');
        msg.className = 'mermaid-error';
        msg.textContent = 'Mermaid 오류: ' + e.message;
        block.replaceWith(msg);
      }
    });
  }

  // 모든 top-level block 토큰에 source line 마커 부여 (markdown-it source map 활용)
  function attachLineNumbers(tokens) {
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      if (!t.map || t.level !== 0) continue;
      // nesting 1 (open) 또는 0 (self-closing block)만 — close 토큰은 동일 element라 skip
      if (t.nesting !== 1 && t.nesting !== 0) continue;
      if (t.attrGet && t.attrGet('data-line') !== null) continue;
      t.attrJoin('class', 'mdv-block');
      t.attrSet('data-line', String(t.map[0]));
      t.attrSet('data-line-end', String(t.map[1]));
    }
  }

  function highlightAdded(root, addedLines) {
    if (!addedLines || addedLines.length === 0) return;
    var set = {};
    for (var i = 0; i < addedLines.length; i++) set[addedLines[i]] = true;
    var blocks = root.querySelectorAll('.mdv-block');
    blocks.forEach(function (el) {
      var start = parseInt(el.getAttribute('data-line'), 10);
      var end = parseInt(el.getAttribute('data-line-end'), 10);
      if (isNaN(start) || isNaN(end)) return;
      for (var ln = start; ln < end; ln++) {
        if (set[ln]) { el.classList.add('md-added'); break; }
      }
    });
  }

  // 북마크된 라인(블록 시작 data-line)에 마커 클래스 부여.
  // innerHTML 재생성 후 render()가 _lastBookmarks로 복원하는 데 쓴다.
  function applyBookmarks(root, lines) {
    if (!lines || lines.length === 0) return;
    var set = {};
    for (var i = 0; i < lines.length; i++) set[lines[i]] = true;
    var blocks = root.querySelectorAll('.mdv-block[data-line]');
    blocks.forEach(function (el) {
      var start = parseInt(el.getAttribute('data-line'), 10);
      if (!isNaN(start) && set[start]) el.classList.add('mdv-bookmarked');
    });
  }

  // 헤딩 anchor 부여 + TOC 추출
  var lastTOC = [];
  function addAnchors(tokens) {
    var slugCount = {};
    lastTOC = [];
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      if (t.type !== 'heading_open') continue;
      var inline = tokens[i + 1];
      if (!inline) continue;
      var text = inline.content;
      var level = parseInt(t.tag.slice(1), 10);
      var base = slugify(text);
      slugCount[base] = (slugCount[base] || 0) + 1;
      var id = slugCount[base] > 1 ? base + '-' + slugCount[base] : base;
      var existing = t.attrIndex('id');
      if (existing < 0) t.attrPush(['id', id]);
      else t.attrs[existing][1] = id;
      var srcLine = (t.map && t.map.length) ? t.map[0] : 0;
      lastTOC.push({ id: id, level: level, text: text, line: srcLine });
    }
  }

  // 기본 link_open 렌더러 가로채서 외부 링크는 새 창 처리 X (Swift에서 처리)
  var defaultRender = md.renderer.rules.link_open || function (tokens, idx, options, env, self) {
    return self.renderToken(tokens, idx, options, self);
  };

  // 렌더링 본체
  function renderMarkdown(text) {
    var env = {};
    var tokens = md.parse(text, env);
    addAnchors(tokens);
    attachLineNumbers(tokens);
    return md.renderer.render(tokens, md.options, env);
  }

  // KaTeX 후처리 (auto-render)
  function renderMath(root) {
    if (!window.renderMathInElement) return;
    try {
      window.renderMathInElement(root, {
        delimiters: [
          { left: '$$', right: '$$', display: true },
          { left: '\\[', right: '\\]', display: true },
          { left: '$', right: '$', display: false },
          { left: '\\(', right: '\\)', display: false }
        ],
        throwOnError: false,
        ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code']
      });
    } catch (e) { /* noop */ }
  }

  function applyTheme(isDark) {
    document.documentElement.dataset.theme = isDark ? 'dark' : 'light';
    var light = document.getElementById('hljs-light');
    var dark  = document.getElementById('hljs-dark');
    if (light && dark) {
      light.disabled = isDark;
      dark.disabled  = !isDark;
    }
  }

  function postTOC() {
    try {
      window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.toc &&
        window.webkit.messageHandlers.toc.postMessage(lastTOC);
    } catch (_) {}
  }

  window.MDV = {
    _lastSig: null,
    _lastBookmarks: [],
    render: function (payload) {
      var isDark = !!payload.isDark;
      // 내용/테마/하이라이트가 직전과 동일하면 DOM을 다시 그리지 않는다.
      // (updateNSView는 SwiftUI body 재평가마다 호출되므로, 그대로 두면
      //  텍스트 선택 드래그 도중 innerHTML이 재생성되어 선택이 풀린다.)
      var sig = JSON.stringify([payload.markdown || '', isDark, payload.addedLines || []]);
      if (sig === this._lastSig) return;
      this._lastSig = sig;
      // innerHTML 교체는 스크롤을 맨 위로 리셋하므로, 교체 전 위치를 저장했다가
      // 교체 후 복원한다. (라이브 리로드 중에도 읽던 위치가 유지된다.)
      var scroller = document.scrollingElement || document.documentElement;
      var prevTop = scroller ? scroller.scrollTop : 0;
      applyTheme(isDark);
      initMermaid(isDark);
      var html = renderMarkdown(payload.markdown || '');
      var root = document.getElementById('content');
      root.innerHTML = html;
      renderMath(root);
      renderMermaid(root);
      highlightAdded(root, payload.addedLines || []);
      // innerHTML이 통째로 교체됐으므로 직전 북마크 마커를 복원한다.
      // (라이브 리로드 후에도 마커가 유지된다.)
      applyBookmarks(root, this._lastBookmarks || []);
      postTOC();
      // 저장해 둔 스크롤 위치 복원. 자동으로 변경 위치로 끌고 가지 않는다 —
      // 변경 내용은 초록색 하이라이트와 상단 배너로 이미 드러난다.
      if (scroller) scroller.scrollTop = prevTop;
    },
    scrollTo: function (id) {
      var el = document.getElementById(id);
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    },
    // 편집기의 소스 줄(line)에 해당하는 블록을 상단으로 — 편집기→프리뷰 스크롤 동기화.
    scrollToLine: function (line) {
      var blocks = document.querySelectorAll('.mdv-block');
      if (!blocks.length) return;
      var best = null;
      for (var i = 0; i < blocks.length; i++) {
        var l = parseInt(blocks[i].getAttribute('data-line'), 10);
        if (isNaN(l)) continue;
        if (l <= line) best = blocks[i]; else break;
      }
      if (!best) best = blocks[0];
      var scroller = document.scrollingElement || document.documentElement;
      var top = best.getBoundingClientRect().top + scroller.scrollTop - 8;
      scroller.scrollTop = Math.max(0, top);
    },
    // Swift가 북마크 라인 배열을 내려보내면 마커만 토글(전체 re-render 없음).
    setBookmarks: function (lines) {
      this._lastBookmarks = lines || [];
      var root = document.getElementById('content');
      if (!root) return;
      root.querySelectorAll('.mdv-bookmarked').forEach(function (e) {
        e.classList.remove('mdv-bookmarked');
      });
      applyBookmarks(root, this._lastBookmarks);
    },
    clearHighlight: function () {
      var els = document.querySelectorAll('.md-added');
      els.forEach(function (e) { e.classList.remove('md-added'); });
    }
  };

  // 더블클릭 분기:
  //  · 본문 요소 위 → 해당 블록의 소스 줄을 Swift로 전달(편집기 스크롤 동기화)
  //  · 본문 바깥 왼쪽 여백(거터) → 같은 줄의 블록을 북마크 토글
  // 본문 텍스트 더블클릭의 단어 선택/복사는 그대로 둔다(preventDefault 금지).
  var GUTTER = 60; // 콘텐츠 왼쪽 경계로부터 거터로 간주할 폭(px)
  document.addEventListener('dblclick', function (e) {
    var content = document.getElementById('content');
    if (!content) return;

    // 1) 거터(블록 왼쪽 여백) 더블클릭 → 그 줄 북마크 토글 (우선 판정).
    //    본문 요소가 거터로 삐져나와 e.target에 잡혀도 북마크가 새치기당하지 않도록 먼저 본다.
    var blocks = content.querySelectorAll('.mdv-block[data-line]');
    for (var i = 0; i < blocks.length; i++) {
      var r = blocks[i].getBoundingClientRect();
      if (e.clientY >= r.top && e.clientY <= r.bottom) {
        if (e.clientX < r.left && e.clientX >= r.left - GUTTER) {
          var bline = parseInt(blocks[i].getAttribute('data-line'), 10);
          if (!isNaN(bline) && bline >= 0) {
            try {
              window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.bookmark &&
                window.webkit.messageHandlers.bookmark.postMessage({ line: bline });
            } catch (_) {}
          }
          return;   // 거터 처리 완료
        }
        break;       // 이 블록은 거터 아님 → 본문(편집기 동기화) 처리로
      }
    }

    // 2) 본문 요소 위 더블클릭 → 편집기 스크롤 동기화용 줄 전달.
    var el = (e.target && e.target.closest) ? e.target.closest('[data-line]') : null;
    if (el) {
      var line = parseInt(el.getAttribute('data-line'), 10);
      if (isNaN(line)) return;
      try {
        window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers.editorLine &&
          window.webkit.messageHandlers.editorLine.postMessage(line);
      } catch (_) {}
    }
  });
})();
