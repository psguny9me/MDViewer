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
      lastTOC.push({ id: id, level: level, text: text });
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
    render: function (payload) {
      var isDark = !!payload.isDark;
      applyTheme(isDark);
      initMermaid(isDark);
      var html = renderMarkdown(payload.markdown || '');
      var root = document.getElementById('content');
      root.innerHTML = html;
      renderMath(root);
      renderMermaid(root);
      postTOC();
    },
    scrollTo: function (id) {
      var el = document.getElementById(id);
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  };
})();
