import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { unifiedPatch } from '../../src/features/diff/unifiedPatch.ts';

test('unified patch is a single hunk for a one-line change', () => {
  const patch = unifiedPatch(
    'docs/superpowers/.diff-check.md',
    'a\nb\nc\n',
    'a\nhello\nc\n',
  );
  assert.equal(
    patch,
    [
      '===================================================================',
      '--- a/docs/superpowers/.diff-check.md',
      '+++ b/docs/superpowers/.diff-check.md',
      '@@ -1,3 +1,3 @@',
      ' a',
      '-b',
      '+hello',
      ' c',
      '',
    ].join('\n'),
  );
});

test('unified patch treats an empty old side as a new file', () => {
  const patch = unifiedPatch('src/new.ts', '', 'export const n = 1;\n');
  assert.match(patch, /--- a\/src\/new\.ts\n/);
  assert.match(patch, /\+export const n = 1;\n/);
});

test('the JS patch matches the golden the native UnifiedPatch check pins', () => {
  const read = (name) =>
    JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url)));
  const golden = read('unified-patch.golden.json');
  for (const { name, path, old, new: next } of read('unified-patch.json'))
    assert.equal(unifiedPatch(path, old, next), golden[name], name);
});
