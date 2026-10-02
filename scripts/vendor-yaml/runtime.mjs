import { parseAllDocuments, Parser, LineCounter, isMap, isSeq, isScalar, isAlias } from 'yaml';
import hljs from 'highlight.js/lib/core';
import yamlLanguage from 'highlight.js/lib/languages/yaml';

hljs.registerLanguage('yaml', yamlLanguage);
const limits = { bytes: 2_000_000, nodes: 12_000, depth: 64, documents: 100, cstTokens: 120_000, highlight: 200_000 };
export { limits };

// Check the iterative CST before the composer's recursive descent. Aliases stay
// references in the preview: we never call toJS(), stringify(), or expand them.
function preflight(source) {
  let count = 0, documents = 0;
  for (const token of new Parser().parse(source)) {
    if (token.type === 'document' && ++documents > limits.documents) throw { code: 'documentLimit', offset: token.offset };
    const stack = [{ value: token, depth: 0 }];
    while (stack.length) {
      const { value, depth } = stack.pop();
      if (!value || typeof value !== 'object') continue;
      if (++count > limits.cstTokens) throw { code: 'nodeLimit', offset: value.offset };
      const nextDepth = depth + (['block-map', 'block-seq', 'flow-collection'].includes(value.type) ? 1 : 0);
      if (nextDepth > limits.depth) throw { code: 'depthLimit', offset: value.offset };
      for (const entry of Object.values(value)) {
        if (entry && typeof entry === 'object') {
          if (Array.isArray(entry)) for (const item of entry) stack.push({ value: item, depth: nextDepth });
          else stack.push({ value: entry, depth: nextDepth });
        }
      }
    }
  }
}

const pathForKey = (base, key) => /^[A-Za-z_][A-Za-z0-9_-]*$/.test(key)
  ? (base ? `${base}.${key}` : key) : `${base}[${JSON.stringify(key)}]`;

function makeIssue(code, message, offset, counter) {
  const pos = counter.linePos(Math.max(0, offset || 0));
  return { code, message: message || '', line: pos.line, column: pos.col };
}

// Validate references in YAML serialization order, including mapping keys.
// This walks nodes once and never resolves/expands alias content.
function aliasIssue(document, counter) {
  const anchors = new Set();
  const pending = [document.contents];
  while (pending.length) {
    const node = pending.pop();
    if (node?.anchor) anchors.add(node.anchor);
    if (isAlias(node) && !anchors.has(node.source)) {
      return makeIssue('syntax', `Unresolved alias: ${node.source}`, node.range?.[0], counter);
    }
    if (isMap(node)) {
      for (let index = node.items.length - 1; index >= 0; --index) {
        pending.push(node.items[index].value, node.items[index].key);
      }
    } else if (isSeq(node)) {
      for (let index = node.items.length - 1; index >= 0; --index) pending.push(node.items[index]);
    }
  }
  return null;
}

export function parse(source) {
  const normalized = source.replace(/\r\n?/g, '\n');
  const counter = new LineCounter();
  counter.addNewLine(0);
  for (let i = 0; i < normalized.length; ++i) if (normalized[i] === '\n') counter.addNewLine(i + 1);
  const result = { documents: [], issue: null, highlighted: null };
  try {
    // Swift checks UTF-8 bytes before entering JavaScriptCore; this also bounds
    // the standalone JS entry point without relying on browser TextEncoder.
    if (source.length > limits.bytes) throw { code: 'sizeLimit', offset: 0 };
    preflight(normalized);
    const documents = parseAllDocuments(normalized, { version: '1.2', strict: true, uniqueKeys: true, prettyErrors: false });
    let totalNodes = 0;
    for (const [documentIndex, document] of documents.entries()) {
      const startOffset = document.range?.[0] || 0;
      const endOffset = document.range?.[2] ?? normalized.length;
      const sheet = { index: documentIndex, startLine: counter.linePos(startOffset).line,
        endLine: counter.linePos(Math.max(startOffset, endOffset - 1)).line, rows: [], issue: null };
      const error = document.errors[0];
      sheet.issue = error ? makeIssue('syntax', error.message, error.pos?.[0], counter) : aliasIssue(document, counter);
      if (!sheet.issue) {
        function visit(node, label, path, parents, depth, keyNode = null) {
          if (++totalNodes > limits.nodes) throw { code: 'nodeLimit', offset: node?.range?.[0] };
          if (depth > limits.depth) throw { code: 'depthLimit', offset: node?.range?.[0] };
          const id = `yaml-${documentIndex}-${sheet.rows.length}`;
          const nodeOffset = keyNode?.range?.[0] ?? node?.range?.[0] ?? startOffset;
          const position = counter.linePos(nodeOffset);
          const row = { id, label, path: path || '$', depth, parents, kind: 'null', value: 'null',
            line: position.line, column: position.col, count: 0, anchor: node?.anchor || '', tag: node?.tag || '' };
          if (isMap(node)) { row.kind = 'object'; row.value = ''; row.count = node.items.length; }
          else if (isSeq(node)) { row.kind = 'array'; row.value = ''; row.count = node.items.length; }
          else if (isAlias(node)) {
            row.kind = 'alias'; row.value = `*${node.source}`;
          } else if (isScalar(node)) {
            row.kind = node.value === null ? 'null' : typeof node.value === 'boolean' ? 'boolean'
              : typeof node.value === 'number' || typeof node.value === 'bigint' ? 'number' : 'string';
            // Numeric source survives precision limits, exponent notation, and
            // hexadecimal formatting. Strings retain their decoded content.
            row.value = row.kind === 'number' ? node.source : node.value === null ? 'null' : String(node.value);
          }
          sheet.rows.push(row);
          const nextParents = [...parents, id];
          if (isMap(node)) node.items.forEach((pair, index) => {
            const scalarKey = isScalar(pair.key);
            const key = scalarKey ? String(pair.key.value ?? 'null') : `[key ${index + 1}]`;
            const keyPath = scalarKey ? pathForKey(path, key) : `${path}[?${index}]`;
            visit(pair.value, key, keyPath, nextParents, depth + 1, pair.key);
          });
          else if (isSeq(node)) node.items.forEach((item, index) => visit(item, `[${index}]`, `${path}[${index}]`, nextParents, depth + 1));
        }
        visit(document.contents, '$', '', [], 0);
      }
      result.documents.push(sheet);
    }
  } catch (error) {
    result.documents = [];
    result.issue = makeIssue(error.code || 'syntax', error.message, error.offset, counter);
  }
  if (normalized.length <= limits.highlight) {
    result.highlighted = hljs.highlight(normalized, { language: 'yaml', ignoreIllegals: true }).value;
  }
  return JSON.stringify(result);
}
