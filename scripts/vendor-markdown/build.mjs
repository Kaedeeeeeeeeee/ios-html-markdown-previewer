import { build } from 'esbuild';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, readdir, copyFile, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const output = path.join(repo, 'HTMLMarkdownPreviewer/Resources/Markdown');
const hash = (data) => createHash('sha256').update(data).digest('hex');
const readJSON = async (filename) => JSON.parse(await readFile(filename, 'utf8'));
await mkdir(output, { recursive: true });
const result = await build({
  absWorkingDir: here,
  entryPoints: ['browser-entry.mjs'],
  outfile: path.join(output, 'markdown-libraries.min.js'),
  bundle: true,
  format: 'iife',
  globalName: 'MarkdownLibraries',
  platform: 'browser',
  target: ['safari17'],
  minify: true,
  sourcemap: false,
  legalComments: 'external',
  charset: 'ascii',
  metafile: true,
  logLevel: 'warning'
});

// All dynamic imports must resolve into this IIFE; a resource fetch is a bug.
const jsPath = path.join(output, 'markdown-libraries.min.js');
const javascript = await readFile(jsPath, 'utf8');
if (/\bimport\s*\(/.test(javascript)) {
  throw new Error('Bundle still contains a dynamic import. Offline assets must be self-contained.');
}
if (Object.values(result.metafile.outputs).some(item => item.imports.some(ref => ref.external))) {
  throw new Error('Bundle contains an external import.');
}

// iOS 17 supports WOFF2. Keep upstream relative font paths, omit WOFF/TTF
// fallbacks to reduce the shipped font bytes without changing the font content.
let css = await readFile(path.join(here, 'node_modules/katex/dist/katex.min.css'), 'utf8');
const originalFontFaces = (css.match(/@font-face\s*\{/g) || []).length;
css = css.replace(/src:[^;}]+;?/g, (declaration) => {
  const woff2 = declaration.match(/url\([^)]*\.woff2\)\s*format\([^)]+\)/);
  if (!woff2) throw new Error('Unexpected KaTeX font declaration');
  return `src:${woff2[0]}${declaration.endsWith(';') ? ';' : ''}`;
});
if ((css.match(/@font-face\s*\{/g) || []).length !== originalFontFaces || originalFontFaces !== 20) {
  throw new Error('KaTeX font-face declarations were lost during WOFF2-only rewriting.');
}
if ((css.match(/url\(fonts\/[^)]+\.woff2\)/g) || []).length !== originalFontFaces) {
  throw new Error('Every KaTeX font face must retain its own WOFF2 source.');
}
await writeFile(path.join(output, 'katex.min.css'), css);
const fontDir = path.join(output, 'fonts');
await mkdir(fontDir, { recursive: true });
const wantedFonts = [...new Set([...css.matchAll(/url\((fonts\/[^)]+\.woff2)\)/g)].map(match => match[1]))].sort();
for (const relative of wantedFonts) {
  await copyFile(path.join(here, 'node_modules/katex/dist', relative), path.join(output, relative));
}
for (const existing of await readdir(fontDir)) {
  if (!wantedFonts.includes(`fonts/${existing}`)) await rm(path.join(fontDir, existing));
}

// Retain complete license texts for every npm package contributing source bytes.
const packageRoots = new Set();
for (const input of Object.keys(result.metafile.inputs)) {
  if (!input.includes('node_modules/')) continue;
  let directory = path.dirname(path.resolve(here, input));
  while (directory.startsWith(here)) {
    try {
      await stat(path.join(directory, 'package.json'));
      packageRoots.add(directory);
      break;
    } catch {
      directory = path.dirname(directory);
    }
  }
}
// Some packages have nested implementation package.json files without identity.
const resolvedPackages = new Map();
for (let root of [...packageRoots].sort()) {
  let info = await readJSON(path.join(root, 'package.json'));
  while (!info.name || !info.version) {
    root = path.dirname(root);
    try { info = await readJSON(path.join(root, 'package.json')); } catch { continue; }
  }
  resolvedPackages.set(`${info.name}@${info.version}`, { root, info });
}
const lock = await readJSON(path.join(here, 'package-lock.json'));
const dependencies = [];
const notices = ['# Third-party licenses', '', 'Generated from pinned npm packages by scripts/vendor-markdown/build.mjs.', ''];
for (const [identity, { root, info }] of [...resolvedPackages.entries()].sort(([a], [b]) => a.localeCompare(b, 'en'))) {
  const files = (await readdir(root)).filter(name => /^(LICENSE|COPYING|NOTICE)(\.|$)/i.test(name)).sort();
  const lockKey = path.relative(here, root).split(path.sep).join('/');
  const provenance = lock.packages[lockKey];
  if (!provenance?.integrity || !provenance?.resolved) throw new Error(`No locked provenance for ${identity}`);
  let readmeLicense = null;
  if (files.length === 0 && info.name === 'fastdom' && info.version === '1.0.12') {
    const readme = await readFile(path.join(root, 'README.md'), 'utf8');
    readmeLicense = readme.slice(readme.indexOf('(The MIT License)')).trim();
    if (!readmeLicense.startsWith('(The MIT License)') || !readmeLicense.includes('Copyright (c) 2016 Wilson Page')) {
      throw new Error('Unexpected fastdom README license');
    }
  }
  if (files.length === 0 && !readmeLicense) throw new Error(`No license text found for ${identity}`);
  const license = info.license || (info.name === 'khroma' && info.version === '2.1.0' ? 'MIT' : 'SEE LICENSE TEXT');
  dependencies.push({
    name: info.name,
    version: info.version,
    license,
    source: typeof info.repository === 'string' ? info.repository : info.repository?.url,
    tarball: provenance.resolved,
    integrity: provenance.integrity
  });
  notices.push(`## ${identity}`, '', `License: ${license}`, '');
  if (readmeLicense) notices.push('### README.md license section', '', readmeLicense, '');
  for (const file of files) notices.push(`### ${file}`, '', await readFile(path.join(root, file), 'utf8'), '');
}
await writeFile(path.join(output, 'THIRD-PARTY-LICENSES.txt'), notices.join('\n'));

const assets = [];
async function inventory(directory, prefix = '') {
  for (const name of (await readdir(directory)).sort()) {
    if (name === 'manifest.json' || name === 'README.md') continue;
    const full = path.join(directory, name);
    const relative = `${prefix}${name}`;
    if ((await stat(full)).isDirectory()) {
      await inventory(full, `${relative}/`);
    } else {
      const data = await readFile(full);
      assets.push({ path: relative, bytes: data.length, sha256: hash(data) });
    }
  }
}
await inventory(output);
const manifest = {
  schemaVersion: 1,
  global: 'MarkdownLibraries',
  target: 'Safari 17 / iOS 17 and newer',
  entry: 'markdown-libraries.min.js',
  stylesheet: 'katex.min.css',
  buildTool: { name: 'esbuild', version: (await readJSON(path.join(here, 'node_modules/esbuild/package.json'))).version },
  packageLockSHA256: hash(await readFile(path.join(here, 'package-lock.json'))),
  sourceEntrySHA256: hash(await readFile(path.join(here, 'browser-entry.mjs'))),
  dependencies,
  assets
};
await writeFile(path.join(output, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Vendored ${dependencies.length} packages, ${assets.length} assets, ${assets.reduce((sum, item) => sum + item.bytes, 0).toLocaleString('en')} bytes.`);
