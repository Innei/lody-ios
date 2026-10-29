import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repoRoot = fileURLToPath(new URL('../../../../', import.meta.url));
const dataRoot = join(repoRoot, 'packages/LodyData');

async function swiftFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map((entry) => {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) return swiftFiles(path);
      return entry.name.endsWith('.swift') ? [path] : [];
    }),
  );
  return nested.flat();
}

test('LodyData builds for both iOS and macOS', async () => {
  const manifest = await readFile(join(dataRoot, 'Package.swift'), 'utf8');
  assert.match(manifest, /\.iOS\("26\.0"\)/);
  assert.match(manifest, /\.macOS\("26\.0"\)/);
});

test('LodyData sources never import a UI framework', async () => {
  const files = await swiftFiles(join(dataRoot, 'Sources'));
  assert.ok(files.length > 0, 'LodyData has no sources');
  const offenders = [];
  for (const file of files) {
    const source = await readFile(file, 'utf8');
    if (/^\s*(@\w+\s+)*import\s+(UIKit|AppKit|SwiftUI)\b/m.test(source)) {
      offenders.push(relative(repoRoot, file));
    }
  }
  assert.deepEqual(offenders, []);
});

test('LodyKit re-exports LodyData for the app and its pages', async () => {
  const manifest = await readFile(
    join(repoRoot, 'packages/LodyKit/Package.swift'),
    'utf8',
  );
  assert.match(manifest, /\.product\(name: "LodyData", package: "LodyData"\)/);
  const files = await swiftFiles(
    join(repoRoot, 'packages/LodyKit/Sources/LodyKit'),
  );
  const exports = [];
  for (const file of files) {
    if (/^@_exported import LodyData$/m.test(await readFile(file, 'utf8')))
      exports.push(file);
  }
  assert.equal(exports.length, 1);
});
