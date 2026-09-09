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

const runtime = await build({
  entryPoints: [root + 'modules/lody-kit/data-runtime/index.ts'],
  bundle: true,
  format: 'esm',
  platform: 'browser',
  target: 'safari17',
  write: false,
});
await writeFile(
  output + '/DataRuntime.html',
  '<!doctype html><title>Lody Data Runtime</title><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; connect-src https:; script-src \'unsafe-inline\' \'wasm-unsafe-eval\'"><script type="module">' +
    runtime.outputFiles[0].text.replaceAll('</script', '<\\/script') +
    '</script>',
);

await writeFile(
  output + '/Loro-LICENSE.txt',
  await readFile(root + '../../node_modules/loro-crdt/LICENSE'),
);
for (const name of [
  'MarkdownView',
  'Litext',
  'pierre-diffs',
  'MaterialIconTheme',
]) {
  await writeFile(
    output + '/' + name + '-LICENSE.txt',
    await readFile(root + 'modules/lody-kit/licenses/' + name + '-LICENSE.txt'),
  );
}

const fileIcons = root + 'modules/lody-kit/file-icons';
for (const name of await readdir(fileIcons)) {
  if (name.endsWith('.png'))
    await copyFile(fileIcons + '/' + name, output + '/' + name);
}
