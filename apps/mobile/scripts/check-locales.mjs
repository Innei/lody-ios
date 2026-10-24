import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const root = path.join(import.meta.dirname, '..');
const { isNativeKey, readCatalogs } = require(
  path.join(root, 'plugins/locales.js'),
);

const problems = [];
const fail = (message) => problems.push(message);

const catalogs = readCatalogs(root, fail);

const NATIVE_LOOKUP = /LodyStrings\.(text|plural)\("([^"]+)"/g;
const nativeBase = path.join(root, 'modules/lody-kit/ios');
for (const file of fs.globSync('**/*.swift', { cwd: nativeBase }))
  for (const [, kind, key] of fs
    .readFileSync(path.join(nativeBase, file), 'utf8')
    .matchAll(NATIVE_LOOKUP)) {
    if (key.includes('\\(') || key.endsWith('.')) continue;
    const entry = kind === 'plural' ? `${key}.one` : key;
    if (!isNativeKey(key) || !(entry in (catalogs.en ?? {})))
      fail(`modules/lody-kit/ios/${file}: ${key} is not in the native catalog`);
  }

const CJK = /[㐀-鿿豈-﫿！-｠]/;
// Debug scenes are development-only surfaces and keep their own copy inline.
const SOURCES = [
  ['modules/lody-kit/ios', '**/*.swift'],
  ['modules/lody-kit/live-activity', '**/*.swift'],
  ['src', '**/*.{ts,tsx}'],
];
for (const [dir, pattern] of SOURCES) {
  const base = path.join(root, dir);
  for (const file of fs.globSync(pattern, {
    cwd: base,
    exclude: (name) => name === 'debug',
  })) {
    const lines = fs.readFileSync(path.join(base, file), 'utf8').split('\n');
    lines.forEach((line, index) => {
      if (CJK.test(line)) fail(`${dir}/${file}:${index + 1}: hardcoded copy`);
    });
  }
}

if (problems.length) {
  for (const problem of problems) console.error(problem);
  process.exit(1);
}
