import { buildDataRuntime } from '../../../packages/cloud-runtime/scripts/build.mjs';
import { build } from 'esbuild';
import {
  mkdir,
  writeFile,
  readFile,
  readdir,
  copyFile,
} from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const result = await build({
  entryPoints: [root + 'modules/lody-kit/decoder/index.ts'],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'safari17',
  write: false,
});
const output = root + 'modules/lody-kit/ios/Resources';
await mkdir(output, { recursive: true });
const markdownRepair = await build({
  stdin: {
    contents: `import remend from 'remend';
      globalThis.repairMarkdown = text => remend(text, {
        linkMode: 'text-only', katex: false, inlineKatex: false,
        htmlTags: false, comparisonOperators: false, singleTilde: false,
        setextHeadings: false,
      });`,
    resolveDir: root,
  },
  bundle: true,
  format: 'iife',
  platform: 'browser',
  target: 'safari17',
  write: false,
});
await writeFile(
  output + '/MarkdownRepair.js',
  markdownRepair.outputFiles[0].text,
);
await copyFile(
  root + '../../node_modules/remend/LICENSE',
  output + '/Remend-LICENSE.txt',
);
await writeFile(
  output + '/FlockDecoder.html',
  '<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\' \'wasm-unsafe-eval\'"><script type="module">' +
    result.outputFiles[0].text.replaceAll('</script', '<\\/script') +
    '</script>',
);
const license = await readFile(
  root + '../../node_modules/@loro-dev/flock-wasm/LICENSE',
  'utf8',
);
await writeFile(output + '/Flock-LICENSE.txt', license);
console.log('Built isolated Flock decoder');

await buildDataRuntime(output);
await copyFile(
  root + 'modules/lody-kit/licenses/LodyLicenses.json',
  output + '/LodyLicenses.json',
);
for (const name of [
  'MarkdownView',
  'Litext',
  'pierre-diffs',
  'MaterialIconTheme',
  'Octicons',
]) {
  await writeFile(
    output + '/' + name + '-LICENSE.txt',
    await readFile(root + 'modules/lody-kit/licenses/' + name + '-LICENSE.txt'),
  );
}

for (const folder of ['file-icons', 'images']) {
  const source = root + 'modules/lody-kit/' + folder;
  for (const name of await readdir(source)) {
    if (name.endsWith('.png'))
      await copyFile(source + '/' + name, output + '/' + name);
  }
}
