import { build } from 'esbuild';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const output = path.resolve(here, '../../HTMLMarkdownPreviewer/Resources/YAML');
await mkdir(output, { recursive: true });
const result = await build({ absWorkingDir: here, entryPoints: ['runtime.mjs'], outfile: path.join(output, 'yaml-runtime.min.js'),
  bundle: true, format: 'iife', globalName: 'YAMLRuntime', platform: 'browser', target: ['safari17'],
  minify: true, legalComments: 'external', charset: 'ascii', metafile: true });
const javascript = await readFile(path.join(output, 'yaml-runtime.min.js'));
if (/\bimport\s*\(/.test(javascript.toString()) || Object.values(result.metafile.outputs).some(o => o.imports.some(i => i.external))) {
  throw new Error('YAML runtime must be self-contained.');
}
const lock = JSON.parse(await readFile(path.join(here, 'package-lock.json'), 'utf8'));
const dependencies = [];
const licenses = [];
for (const name of ['yaml', 'highlight.js']) {
  const info = JSON.parse(await readFile(path.join(here, 'node_modules', name, 'package.json'), 'utf8'));
  const provenance = lock.packages[`node_modules/${name}`];
  dependencies.push({ name, version: info.version, license: info.license, source: info.repository,
    tarball: provenance.resolved, integrity: provenance.integrity });
  licenses.push(`${name} ${info.version}\n\n${await readFile(path.join(here, 'node_modules', name, 'LICENSE'), 'utf8')}`);
}
await writeFile(path.join(output, 'THIRD-PARTY-LICENSES.txt'), licenses.join('\n\n'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
await writeFile(path.join(output, 'manifest.json'), JSON.stringify({ schemaVersion: 1, global: 'YAMLRuntime',
  target: 'JavaScriptCore / iOS 17+', dependencies, sourceSHA256: hash(await readFile(path.join(here, 'runtime.mjs'))),
  lockSHA256: hash(await readFile(path.join(here, 'package-lock.json'))), assets: [{ path: 'yaml-runtime.min.js', bytes: javascript.length, sha256: hash(javascript) }] }, null, 2) + '\n');
console.log(`Vendored offline YAML runtime: ${javascript.length} bytes.`);
