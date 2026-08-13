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

  // ----- JSON 뷰어 -----
  // .json 문서는 마크다운 대신 접이식 트리로 렌더한다.
  var JSON_EXPAND_ALL_LIMIT = 2000;   // 총 노드 수가 이하면 전부 펼친 상태로 시작
  var JSON_TREE_LIMIT = 50000;        // 초과하면 트리 대신 pretty-print 코드뷰로 폴백
  var JSON_HLJS_LIMIT = 500 * 1024;   // 이보다 큰 원문은 hljs 하이라이트 생략

  function escapeHtml(s) { return md.utils.escapeHtml(String(s)); }

  // 재귀 금지 — 수만 단계로 중첩된 JSON에서 스택 오버플로를 피하기 위해
  // 명시적 스택(배열) 기반 반복문으로 순회한다. (JSON.parse 자체는 반복문 기반)
  function countJSONNodes(v) {
    var n = 0;
    var stack = [v];
    while (stack.length) {
      var cur = stack.pop();
      n++;
      if (Array.isArray(cur)) {
        for (var i = 0; i < cur.length; i++) stack.push(cur[i]);
      } else if (cur !== null && typeof cur === 'object') {
        for (var k in cur) {
          if (Object.prototype.hasOwnProperty.call(cur, k)) stack.push(cur[k]);
        }
      }
    }
    return n;
  }

  function jsonLeafValueHTML(v) {
    if (typeof v === 'string') {
      var quoted = JSON.stringify(v);
      // http(s) URL 문자열은 링크로 (외부 링크는 Swift가 기본 브라우저로 연다)
      if (/^https?:\/\/\S+$/.test(v)) {
        return '<span class="json-str">"<a class="json-link" href="' + escapeHtml(v) + '">' +
               escapeHtml(quoted.slice(1, -1)) + '</a>"</span>';
      }
      return '<span class="json-str">' + escapeHtml(quoted) + '</span>';
    }
    if (typeof v === 'number') {
      // 1e400 → Infinity 같은 표현 범위 초과값은 원문과 다름을 표시한다.
      if (!isFinite(v)) {
        return '<span class="json-num json-num-approx" ' +
               'title="원문 숫자가 JS 표현 범위를 벗어나 근사값으로 표시됩니다">' +
               escapeHtml(String(v)) + '</span>';
      }
      return '<span class="json-num">' + escapeHtml(String(v)) + '</span>';
    }
    if (typeof v === 'boolean') return '<span class="json-bool">' + v + '</span>';
    return '<span class="json-null">null</span>';
  }

  function jsonCountLabel(v) {
    if (Array.isArray(v)) return v.length + (v.length === 1 ? ' item' : ' items');
    var n = Object.keys(v).length;
    return n + (n === 1 ? ' key' : ' keys');
  }

  // JSON 아웃라인(TOC) — 최상위/2단계 키를 사이드바 목차로 내려보낸다.
  var jsonAnchorSeq = 0;
  var jsonTOC = [];
  var JSON_TOC_LIMIT = 200;

  // out: HTML 문자열 조각 배열(성능 위해 join). 재귀 대신 명시적 스택으로
  // 순회한다(깊은 중첩 대비). trailing = 뒤에 형제가 있어 콤마가 필요한 항목.
  function buildJSONTree(out, rootValue, rootTocLevel, expandAll) {
    var stack = [{ key: null, value: rootValue, depth: 0, tocLevel: rootTocLevel, trailing: false }];
    while (stack.length) {
      var it = stack.pop();
      if (it.closeHTML !== undefined) { out.push(it.closeHTML); continue; }

      var value = it.value;
      var comma = it.trailing ? '<span class="json-punct">,</span>' : '';
      var keyHTML = it.key === null ? '' :
        '<span class="json-key">' + escapeHtml(JSON.stringify(it.key)) + '</span><span class="json-punct">: </span>';
      var isContainer = value !== null && typeof value === 'object';

      if (!isContainer) {
        out.push('<div class="json-entry json-leaf">', keyHTML,
                 jsonLeafValueHTML(value), comma, '</div>');
        continue;
      }

      var isArr = Array.isArray(value);
      var open = isArr ? '[' : '{';
      var close = isArr ? ']' : '}';
      var keys = isArr ? null : Object.keys(value);
      var count = isArr ? value.length : keys.length;

      if (count === 0) {
        out.push('<div class="json-entry json-leaf">', keyHTML,
                 '<span class="json-punct">', open, close, '</span>', comma, '</div>');
        continue;
      }

      // TOC 앵커: 최상위(레벨1)·2단계(레벨2) 키. 총량 제한은 순회 후
      // trimJSONTOC()가 레벨1 우선으로 적용한다(DFS 순서로 소진되지 않게).
      var anchorAttr = '';
      if (it.key !== null && it.tocLevel > 0 && it.tocLevel <= 2) {
        var id = 'jn-' + (jsonAnchorSeq++);
        anchorAttr = ' id="' + id + '"';
        // line: -1 — JSON은 소스 줄 매핑이 없다(편집기 스크롤 동기화 제외용 센티널).
        jsonTOC.push({ id: id, level: it.tocLevel, text: String(it.key), line: -1 });
      }

      var collapsed = expandAll || it.depth === 0 ? '' : ' json-collapsed';
      out.push('<div class="json-entry json-container', collapsed, '"', anchorAttr, '>',
               '<div class="json-line"><span class="json-caret"></span>', keyHTML,
               '<span class="json-punct">', open, '</span>',
               '<span class="json-count">', jsonCountLabel(value), '</span>',
               '<span class="json-ellipsis">… ', close, '</span></div>',
               '<div class="json-children">');
      // 닫는 조각을 먼저 push(스택이라 자식들 뒤에 pop된다).
      stack.push({ closeHTML: '</div><div class="json-closing"><span class="json-punct">' +
                              close + '</span>' + comma + '</div></div>' });
      // 자식들을 역순 push → pop 순서가 원래 순서가 된다.
      if (isArr) {
        for (var i = value.length - 1; i >= 0; i--) {
          stack.push({ key: null, value: value[i], depth: it.depth + 1,
                       tocLevel: 0, trailing: i < value.length - 1 });
        }
      } else {
        var childTocLevel = it.tocLevel > 0 && it.tocLevel < 2 ? it.tocLevel + 1
                          : (it.depth === 0 ? 1 : 0);
        for (var j = keys.length - 1; j >= 0; j--) {
          stack.push({ key: keys[j], value: value[keys[j]], depth: it.depth + 1,
                       tocLevel: childTocLevel, trailing: j < keys.length - 1 });
        }
      }
    }
  }

  // TOC 총량 제한 — 레벨1(최상위 키)을 먼저 채우고 남는 슬롯에만 레벨2를
  // 문서 순서대로 채운다. (순회 중 자르면 첫 키의 자식들이 한도를 소진해
  // 뒤쪽 최상위 키가 통째로 빠진다.)
  function trimJSONTOC(list) {
    if (list.length <= JSON_TOC_LIMIT) return list;
    var keep = new Set();
    var budget = JSON_TOC_LIMIT;
    for (var i = 0; i < list.length && budget > 0; i++) {
      if (list[i].level === 1) { keep.add(list[i]); budget--; }
    }
    for (var j = 0; j < list.length && budget > 0; j++) {
      if (list[j].level === 2) { keep.add(list[j]); budget--; }
    }
    return list.filter(function (e) { return keep.has(e); });
  }

  function jsonCodeFallback(text, note) {
    var body;
    if (text.length <= JSON_HLJS_LIMIT && window.hljs) {
      try {
        body = '<pre class="hljs"><code class="hljs language-json">' +
               window.hljs.highlight(text, { language: 'json', ignoreIllegals: true }).value +
               '</code></pre>';
      } catch (_) {}
    }
    if (!body) body = '<pre class="hljs"><code class="hljs">' + escapeHtml(text) + '</code></pre>';
    return (note ? '<div class="json-note">' + escapeHtml(note) + '</div>' : '') + body;
  }

  function renderJSONDoc(root, text) {
    jsonTOC = [];
    jsonAnchorSeq = 0;
    var data;
    try {
      data = JSON.parse(text);
    } catch (e) {
      root.innerHTML =
        '<div class="json-error">JSON 파싱 오류: ' +
        escapeHtml(e && e.message ? e.message : e) +
        '</div>' + jsonCodeFallback(text, null);
      lastTOC = [];
      return;
    }

    var total = countJSONNodes(data);
    if (total > JSON_TREE_LIMIT) {
      // 원문 text를 그대로 보여준다 — 재직렬화(JSON.stringify)는 숫자 왜곡과
      // 깊은 중첩에서의 재귀 오버플로 위험이 있다.
      root.innerHTML = jsonCodeFallback(
        text,
        '항목이 ' + total.toLocaleString() + '개로 많아 트리 대신 코드 보기로 표시합니다.'
      );
      lastTOC = [];
      return;
    }

    var expandAll = total <= JSON_EXPAND_ALL_LIMIT;
    var typeLabel = Array.isArray(data) ? 'Array' :
                    (data !== null && typeof data === 'object') ? 'Object' : 'Value';
    var out = [];
    out.push('<div class="json-doc"><div class="json-toolbar"><span class="json-meta">',
             typeLabel, ' · ', total.toLocaleString(), ' nodes</span>',
             '<span class="json-spacer"></span>',
             '<button class="json-btn" data-act="expand">모두 펼치기</button>',
             '<button class="json-btn" data-act="collapse">모두 접기</button>',
             '</div><div class="json-tree">');
    buildJSONTree(out, data,
                  (data !== null && typeof data === 'object' && !Array.isArray(data)) ? 0 : -1,
                  expandAll);
    out.push('</div></div>');
    root.innerHTML = out.join('');
    lastTOC = trimJSONTOC(jsonTOC);
  }

  // ----- 플레인 텍스트 뷰어 -----
  // .txt 문서는 마크다운 해석 없이 원문 그대로, 줄 단위로 렌더한다.
  // 각 줄이 data-line을 가진 .mdv-block이라 북마크·변경 강조·스크롤 동기화가
  // 마크다운과 동일하게 동작한다.
  var TEXT_LINE_LIMIT = 100000;   // 초과하면 줄 단위 기능 없이 통짜 <pre>로 폴백
  var textLinkRe = /https?:\/\/[^\s<>"')\]]+/g;

  // 한 줄을 escape하고 http(s) URL만 링크로 바꾼다(외부 링크는 Swift가 기본 브라우저로 연다).
  function textLineHTML(line) {
    if (!line) return '';
    var out = '';
    var last = 0;
    var m;
    textLinkRe.lastIndex = 0;
    while ((m = textLinkRe.exec(line)) !== null) {
      // 문장 끝에 붙은 마침표류는 링크에서 뺀다.
      var url = m[0].replace(/[.,;:!?]+$/, '');
      out += escapeHtml(line.slice(last, m.index));
      out += '<a href="' + escapeHtml(url) + '">' + escapeHtml(url) + '</a>';
      last = m.index + url.length;
    }
    out += escapeHtml(line.slice(last));
    return out;
  }

  function renderTextDoc(root, text) {
    lastTOC = [];   // 플레인 텍스트는 목차 없음
    var lines = text.split('\n');
    if (lines.length > TEXT_LINE_LIMIT) {
      root.innerHTML =
        '<div class="json-note">줄이 ' + lines.length.toLocaleString() +
        '개로 많아 줄 단위 기능(북마크·변경 강조) 없이 표시합니다.</div>' +
        '<pre class="txt-plain">' + escapeHtml(text) + '</pre>';
      return;
    }
    var out = ['<div class="txt-doc">'];
    for (var i = 0; i < lines.length; i++) {
      out.push('<div class="mdv-block txt-line" data-line="', i,
               '" data-line-end="', i + 1, '">', textLineHTML(lines[i]), '</div>');
    }
    out.push('</div>');
    root.innerHTML = out.join('');
  }

  // 트리 토글/전체 접기·펼치기 — 이벤트 위임(문서당 1회 등록)
  document.addEventListener('click', function (e) {
    if (!e.target || !e.target.closest) return;
    var btn = e.target.closest('.json-btn');
    if (btn) {
      var collapse = btn.getAttribute('data-act') === 'collapse';
      document.querySelectorAll('.json-tree .json-container').forEach(function (el, i) {
        // 루트 컨테이너(첫 항목)는 항상 펼친 채 둔다
        if (collapse && el.parentElement && el.parentElement.classList.contains('json-tree')) {
          el.classList.remove('json-collapsed');
          return;
        }
        el.classList.toggle('json-collapsed', collapse);
      });
      return;
    }
    var toggle = e.target.closest('.json-caret, .json-count, .json-ellipsis');
    if (toggle) {
      var entry = toggle.closest('.json-container');
      if (entry) entry.classList.toggle('json-collapsed');
    }
  });

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
      var mode = payload.mode === 'json' ? 'json'
               : payload.mode === 'text' ? 'text' : 'markdown';
      // 내용/테마/하이라이트가 직전과 동일하면 DOM을 다시 그리지 않는다.
      // (updateNSView는 SwiftUI body 재평가마다 호출되므로, 그대로 두면
      //  텍스트 선택 드래그 도중 innerHTML이 재생성되어 선택이 풀린다.)
      // JSON 모드는 addedLines를 쓰지 않으므로 sig에서 제외한다 — diff 배너
      // 닫기 등으로 addedLines만 바뀌어도 트리(펼침 상태)가 리셋되지 않게.
      var sig = JSON.stringify([payload.markdown || '', mode, isDark,
                                mode === 'json' ? [] : (payload.addedLines || [])]);
      if (sig === this._lastSig) return;
      this._lastSig = sig;
      // innerHTML 교체는 스크롤을 맨 위로 리셋하므로, 교체 전 위치를 저장했다가
      // 교체 후 복원한다. (라이브 리로드 중에도 읽던 위치가 유지된다.)
      var scroller = document.scrollingElement || document.documentElement;
      var prevTop = scroller ? scroller.scrollTop : 0;
      applyTheme(isDark);
      var root = document.getElementById('content');
      try {
        if (mode === 'json') {
          // JSON 트리 모드 — 마크다운 전용 후처리(수식/머메이드/diff/북마크)는 건너뛴다.
          renderJSONDoc(root, payload.markdown || '');
          postTOC();
          if (scroller) scroller.scrollTop = prevTop;
          return;
        }
        if (mode === 'text') {
          // 플레인 텍스트 모드 — 마크다운 해석 없이 줄 단위로 그린다.
          // 줄 기반 기능(diff 강조·북마크)은 마크다운과 동일하게 적용한다.
          renderTextDoc(root, payload.markdown || '');
          highlightAdded(root, payload.addedLines || []);
          applyBookmarks(root, this._lastBookmarks || []);
          postTOC();
          if (scroller) scroller.scrollTop = prevTop;
          return;
        }
        initMermaid(isDark);
        var html = renderMarkdown(payload.markdown || '');
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
      } catch (err) {
        // 렌더 실패가 화면(이전 문서 잔상)과 캐시를 오염시키지 않게 한다:
        // sig를 되돌려 다음 render가 다시 시도할 수 있게 하고, 오류를 표시한다.
        this._lastSig = null;
        lastTOC = [];
        var emsg = err && err.message ? err.message : String(err);
        try {
          root.innerHTML = '<div class="json-error">렌더 오류: ' + escapeHtml(emsg) + '</div>' +
            (mode === 'json'
              ? jsonCodeFallback(payload.markdown || '', '트리를 그리지 못해 원문 코드 보기로 표시합니다.')
              : mode === 'text'
                ? '<pre class="txt-plain">' + escapeHtml(payload.markdown || '') + '</pre>'
                : '');
          postTOC();
        } catch (_) {}
      }
    },
    scrollTo: function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      // JSON 트리: 접힌 조상 안에 있으면 먼저 펼쳐서 보이게 한다.
      var p = el.parentElement;
      while (p) {
        if (p.classList && p.classList.contains('json-collapsed')) {
          p.classList.remove('json-collapsed');
        }
        p = p.parentElement;
      }
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
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

  // 링크의 원문 href를 Swift로 넘긴다. WebView의 문서 기준 URL은 앱 번들의
  // template.html이므로, 상대경로 해석은 원본 Markdown URL을 아는 Swift가 담당한다.
  // 문서 내부 `#anchor`는 기존 WebView 탐색을 그대로 유지한다.
  document.addEventListener('click', function (e) {
    var anchor = (e.target && e.target.closest) ? e.target.closest('a[href]') : null;
    if (!anchor) return;
    var href = anchor.getAttribute('href');
    if (!href || href.charAt(0) === '#') return;
    try {
      if (window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers.openLink) {
        e.preventDefault();
        window.webkit.messageHandlers.openLink.postMessage(href);
      }
    } catch (_) {}
  });

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
