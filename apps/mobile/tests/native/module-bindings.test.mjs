import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const moduleSource = await readFile(
  new URL('../../modules/lody-kit/ios/LodyKitModule.swift', import.meta.url),
  'utf8',
);

test('LodyKit keeps asynchronous native calls on the queued module DSL', () => {
  const unsafeBindings = [
    ...moduleSource.matchAll(/@JS\s+func\s+(\w+)[^{\n]*\basync\b/g),
  ].map((match) => match[1]);

  assert.deepEqual(unsafeBindings, []);

  for (const name of [
    'watchCatalog',
    'unwatchCatalog',
    'watchSession',
    'unwatchSession',
    'readContentText',
    'previewContent',
    'debugHangDataRuntime',
    'debugRestartDataRuntime',
    'readLocalStartup',
    'readLocalValue',
    'writeLocalValue',
    'readAuthToken',
    'saveAuthToken',
    'clearAuthToken',
    'openAuthBrowser',
    'closeAuthBrowser',
    'selectionFeedback',
  ]) {
    assert.match(moduleSource, new RegExp(`AsyncFunction\\("${name}"\\)`));
  }
});
