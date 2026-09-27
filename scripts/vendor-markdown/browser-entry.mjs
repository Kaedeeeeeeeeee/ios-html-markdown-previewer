// Build-time module only. App pages load the generated browser IIFE, never npm.
import katex from 'katex';
import hljs from 'highlight.js/lib/core';
import bash from 'highlight.js/lib/languages/bash';
import c from 'highlight.js/lib/languages/c';
import cpp from 'highlight.js/lib/languages/cpp';
import css from 'highlight.js/lib/languages/css';
import diff from 'highlight.js/lib/languages/diff';
import go from 'highlight.js/lib/languages/go';
import java from 'highlight.js/lib/languages/java';
import javascript from 'highlight.js/lib/languages/javascript';
import json from 'highlight.js/lib/languages/json';
import kotlin from 'highlight.js/lib/languages/kotlin';
import plaintext from 'highlight.js/lib/languages/plaintext';
import python from 'highlight.js/lib/languages/python';
import ruby from 'highlight.js/lib/languages/ruby';
import rust from 'highlight.js/lib/languages/rust';
import sql from 'highlight.js/lib/languages/sql';
import swift from 'highlight.js/lib/languages/swift';
import typescript from 'highlight.js/lib/languages/typescript';
import xml from 'highlight.js/lib/languages/xml';
import yaml from 'highlight.js/lib/languages/yaml';
import mermaid from 'mermaid';

const languages = {
  bash, c, cpp, css, diff, go, java, javascript, json, kotlin, plaintext,
  python, ruby, rust, sql, swift, typescript, xml, yaml
};
for (const [name, language] of Object.entries(languages)) {
  hljs.registerLanguage(name, language);
}

// These options are suitable for untrusted local Markdown. Pass a fresh macros
// object per document; do not share macro state across unrelated documents.
const katexOptions = Object.freeze({
  trust: false,
  strict: 'warn',
  throwOnError: false,
  output: 'htmlAndMathml',
  maxExpand: 1000,
  maxSize: 20
});

// Mermaid registers a window-load listener. Disable its automatic scanning as
// soon as the bundle is evaluated; rendering must be explicitly awaited.
// Document frontmatter/directives cannot change these security-sensitive keys.
const mermaidOptions = Object.freeze({
  startOnLoad: false,
  securityLevel: 'strict',
  suppressErrorRendering: true,
  maxTextSize: 50000,
  maxEdges: 500,
  htmlLabels: false,
  fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
  flowchart: Object.freeze({ htmlLabels: false, useMaxWidth: true }),
  secure: Object.freeze([
    'secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges',
    'suppressErrorRendering', 'htmlLabels', 'flowchart', 'fontFamily',
    'themeCSS', 'themeVariables', 'dompurifyConfig'
  ])
});
mermaid.initialize({
  ...mermaidOptions,
  flowchart: { ...mermaidOptions.flowchart },
  secure: [...mermaidOptions.secure]
});

export { katex, hljs, mermaid, katexOptions, mermaidOptions };
export const versions = Object.freeze({
  katex: '0.16.47', highlight: '11.12.0', mermaid: '11.17.2'
});
export const highlightLanguages = Object.freeze(Object.keys(languages));
