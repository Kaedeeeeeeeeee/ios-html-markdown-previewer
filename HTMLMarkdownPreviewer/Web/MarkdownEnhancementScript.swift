import Foundation

enum MarkdownEnhancementScript {
    static let source = #"""
    (() => {
      'use strict';
      const labels = document.body.dataset;
      const printing = document.body.classList.contains('printing');
      const originals = new WeakMap();
      function send(body) { globalThis.webkit?.messageHandlers.markdownAction?.postMessage(body); }
      function errorSource(element, message, source, inline) {
        element.replaceChildren();
        element.dataset.renderState = 'error';
        if (inline) {
          element.classList.add('math-error');
          element.textContent = source;
          element.title = message;
        } else {
          const note = document.createElement('div');
          note.className = 'render-error';
          note.dataset.readingIgnore = '';
          note.textContent = message;
          const code = document.createElement('pre');
          code.className = 'diagram-source';
          code.textContent = source;
          element.append(note, code);
        }
      }
      const ready = (async () => {
        const libraries = globalThis.MarkdownLibraries;
        if (!libraries?.katex || !libraries?.hljs || !libraries?.mermaid) throw new Error('Bundled libraries missing');
        for (const code of document.querySelectorAll('.code-block pre code')) {
          const source = code.textContent;
          originals.set(code, source);
          const language = (code.dataset.language || '').split(/\s+/)[0].toLowerCase();
          if (source.length <= 200000 && language && libraries.hljs.getLanguage(language)) {
            try {
              // highlight.js escapes all input; only its generated span markup is inserted.
              code.innerHTML = libraries.hljs.highlight(source, { language, ignoreIllegals:true }).value;
              code.dataset.highlighted = 'true';
            } catch { code.textContent = source; }
          }
        }
        for (const element of document.querySelectorAll('.math')) {
          const source = element.dataset.readingText || '';
          const display = element.dataset.mathDisplay === 'true';
          try {
            if (source.length > 10000) throw new Error('Formula too long');
            libraries.katex.render(source, element, {
              ...libraries.katexOptions, displayMode:display, throwOnError:true,
              trust:false, strict:'warn', maxExpand:1000, maxSize:20,
              output:'htmlAndMathml', macros:{}
            });
            element.dataset.renderState = 'ready';
          } catch { errorSource(element, labels.mathError, source, !display); }
        }
        let diagramIndex = 0;
        for (const element of document.querySelectorAll('.mermaid-diagram')) {
          const source = element.dataset.readingText || '';
          const renderID = 'markdown-diagram-' + (++diagramIndex);
          try {
            if (source.length > 50000 || diagramIndex > 50) throw new Error('Diagram limit');
            // Document-supplied directives must not change app rendering/security
            // configuration. Ordinary diagrams use the app's strict configuration.
            if (/%%\s*\{\s*(init|initialize)\s*:/i.test(source) || /^\s*---(?:\r?\n)/.test(source)) {
              throw new Error('Document configuration is unsupported');
            }
            const result = await libraries.mermaid.render(renderID, source);
            element.innerHTML = result.svg;
            // Strict Mermaid is already sanitized. Remove navigable or externally
            // sourced SVG constructs as defense in depth; never bind interactions.
            for (const node of element.querySelectorAll('script,foreignObject,iframe,object,embed,image,a')) {
              if (node.localName === 'a') node.replaceWith(...node.childNodes);
              else node.remove();
            }
            for (const node of element.querySelectorAll('*')) {
              for (const attr of Array.from(node.attributes)) {
                if (/^on/i.test(attr.name) || /^(?:xlink:)?href$/i.test(attr.name) && !attr.value.startsWith('#')) node.removeAttribute(attr.name);
              }
            }
            element.dataset.renderState = 'ready';
          } catch {
            document.getElementById('d' + renderID)?.remove();
            errorSource(element, labels.diagramError, source, false);
          }
        }
        await document.fonts.ready;
        if (printing) {
          // Match the PDF exporter's A4 printable width, after local fonts have
          // established the real formula width. Never clip a wide equation.
          for (const element of document.querySelectorAll('.math[data-render-state="ready"]')) {
            const formula = element.querySelector('.katex');
            if (!formula) continue;
            const container = element.classList.contains('math-display') ? element
              : element.closest('td,th,p,li,h1,h2,h3,h4,h5,h6,blockquote,div,main');
            if (!container) continue;
            const css = getComputedStyle(container);
            const available = container.clientWidth - parseFloat(css.paddingLeft || 0) - parseFloat(css.paddingRight || 0);
            const width = formula.getBoundingClientRect().width;
            if (available > 0 && width > available) {
              const size = parseFloat(getComputedStyle(element).fontSize);
              element.style.fontSize = (size * available / width * .98) + 'px';
            }
          }
        }
        await Promise.all(Array.from(document.images, image => image.complete ? Promise.resolve() : new Promise(resolve => {
          image.addEventListener('load', resolve, {once:true}); image.addEventListener('error', resolve, {once:true});
        })));
        // Offscreen PDF renderers do not necessarily receive animation frames.
        await new Promise(resolve => setTimeout(resolve, 80));
        document.documentElement.dataset.markdownReady = 'true';
        return true;
      })();
      globalThis.__markdownEnhancements = { ready };
      // The native owner observes/reports a renderer load failure via the promise.
      ready.catch(() => { document.documentElement.dataset.markdownReady = 'error'; });
      if (!printing) {
        document.addEventListener('click', event => {
          const target = event.target instanceof Element ? event.target : null;
          if (!target) return;
          const button = target.closest('.copy-code');
          if (button) {
            const code = button.closest('.code-block')?.querySelector('pre code');
            if (!code) return;
            send({ type:'copy', text:originals.get(code) ?? code.textContent });
            const label = button.querySelector('.copy-label');
            label.textContent = labels.copiedLabel;
            button.setAttribute('aria-label', labels.copiedLabel);
            clearTimeout(button.copyTimer);
            button.copyTimer = setTimeout(() => { label.textContent = labels.copyLabel; button.setAttribute('aria-label', labels.copyLabel); }, 1800);
            return;
          }
          const image = target.closest('[data-image-index]');
          if (image) { send({type:'image', index:Number(image.dataset.imageIndex)}); return; }
          const link = target.closest('[data-link-url]');
          if (link) { event.preventDefault(); send({type:'link', url:link.dataset.linkUrl}); }
        });
        document.addEventListener('keydown', event => {
          if ((event.key === 'Enter' || event.key === ' ') && event.target.matches('[data-image-index],[data-link-url]')) {
            event.preventDefault(); event.target.click();
          }
        });
      }
    })();
    """#
}
