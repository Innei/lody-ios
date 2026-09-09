import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
const root = path.join(import.meta.dirname, '..');
const { readCatalogs } = require(path.join(root, 'plugins/locales.js'));

const problems = [];
const fail = (message) => problems.push(message);

readCatalogs(root, fail);

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
