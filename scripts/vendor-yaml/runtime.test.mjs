import test from 'node:test';
import assert from 'node:assert/strict';
import { parse } from './runtime.mjs';

const preview = source => JSON.parse(parse(source));
test('YAML 1.2 types, quoted keys, precision, multiline values, and source positions', () => {
  const source = '# Config\nservices:\n  web:\n    port: 8080\n    enabled: true\n    mode: on\n    id: 9007199254740993\n    "a.b": "false"\n    notes: |\n      你好\n      second line\n';
  const result = preview(source);
  assert.equal(result.issue, null);
  const rows = result.documents[0].rows;
  assert.equal(rows.find(r => r.path === 'services.web.mode').kind, 'string');
  assert.equal(rows.find(r => r.path === 'services.web.id').value, '9007199254740993');
  assert.equal(rows.find(r => r.path === 'services.web["a.b"]').kind, 'string');
  assert.equal(rows.find(r => r.path === 'services.web.notes').value, '你好\nsecond line\n');
  assert.equal(rows.find(r => r.path === 'services.web.port').line, 4);
  assert.match(result.highlighted, /hljs-comment/);
});
test('multi-document streams and aliases stay distinct without expansion', () => {
  const result = preview('defaults: &base {port: 8080}\nweb: *base\n---\nname: second\n');
  assert.equal(result.documents.length, 2);
  assert.equal(result.documents[0].rows.find(r => r.label === 'web').kind, 'alias');
  assert.equal(result.documents[0].rows.length, 4);
  assert.equal(result.documents[1].startLine, 3);
});
test('syntax, duplicate keys, undefined aliases, and errors in later documents', () => {
  for (const source of ['app:\n  name: Demo\n port: 8080', 'key: 1\nkey: 2', 'web: *missing']) {
    const issue = preview(source).documents[0].issue;
    assert.equal(issue.code, 'syntax');
    assert.ok(issue.line >= 1 && issue.column >= 1);
  }
  const result = preview('name: valid\n---\nitems: [broken\n');
  assert.equal(result.documents[0].issue, null);
  assert.ok(result.documents[1].issue);
});
test('recursive aliases and repeated alias references do not expand', () => {
  const result = preview('self: &self [*self]\na: &a [1, 2]\nb: &b [*a, *a, *a]\nc: [*b, *b, *b]\n');
  assert.equal(result.documents[0].issue, null);
  assert.ok(result.documents[0].rows.length < 20);
});
test('anchors in mapping keys are valid and undefined key aliases are diagnosed', () => {
  const result = preview('&name title: Demo\ncopy: *name\n');
  assert.equal(result.documents[0].issue, null);
  assert.equal(result.documents[0].rows.find(r => r.label === 'copy').value, '*name');
  assert.equal(preview('*missing: value\n').documents[0].issue.line, 1);
  assert.equal(preview('copy: *later\nvalue: &later Demo\n').documents[0].issue.line, 1);
});
test('bounded CST prevents deep nesting and excessive nodes before composition', () => {
  assert.equal(preview('['.repeat(100) + '0' + ']'.repeat(100)).issue.code, 'depthLimit');
  assert.equal(preview('- 1\n'.repeat(13_000)).issue.code, 'nodeLimit');
  assert.equal(preview('---\na: 1\n'.repeat(101)).issue.code, 'documentLimit');
});
