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
const swiftRoot = path.join(root, 'modules/lody-kit/ios');
for (const file of fs.globSync('**/*.swift', { cwd: swiftRoot })) {
  const lines = fs.readFileSync(path.join(swiftRoot, file), 'utf8').split('\n');
  lines.forEach((line, index) => {
    if (CJK.test(line))
      fail(`modules/lody-kit/ios/${file}:${index + 1}: hardcoded copy`);
  });
}

if (problems.length) {
  for (const problem of problems) console.error(problem);
  process.exit(1);
}
