import assert from 'node:assert/strict';
import { test } from 'node:test';
import { sheetContentBackground } from '../../src/lib/presentation/sheetContentBackground.ts';

test('iPhone form and page sheets keep a transparent content background for glass', () => {
  assert.equal(
    sheetContentBackground('formSheet', '#111113', false),
    'transparent',
  );
  assert.equal(
    sheetContentBackground('pageSheet', '#111113', false),
    'transparent',
  );
  assert.equal(
    sheetContentBackground('overFullScreen', '#111113', false),
    'transparent',
  );
});

test('iPad form and page sheets stay opaque so centered cards do not show through', () => {
  assert.equal(sheetContentBackground('formSheet', '#111113', true), '#111113');
  assert.equal(sheetContentBackground('pageSheet', '#111113', true), '#111113');
  assert.equal(
    sheetContentBackground('overFullScreen', '#111113', true),
    'transparent',
  );
});

test('pushed and full-screen pages keep the supplied background on both idioms', () => {
  assert.equal(sheetContentBackground('push', '#111113', false), '#111113');
  assert.equal(
    sheetContentBackground('fullScreen', '#111113', false),
    '#111113',
  );
  assert.equal(sheetContentBackground('push', '#111113', true), '#111113');
  assert.equal(
    sheetContentBackground('fullScreen', '#111113', true),
    '#111113',
  );
});
